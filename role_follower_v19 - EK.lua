local Comms = require("PartySystem.lib_comms")

local MY_NAME          = "Don Kina"
local MY_VOC           = "EK" 
local LEADER_NAME      = "Joaquim Quiabo"
local TARGET_TO_FOLLOW = "Joaquim Quiabo"
local LEADER_IP        = "26.131.131.149"
local MY_PORT          = 45001
local LEADER_PORT      = 45000

local SAFE_POS      = { x = 33861, y = 30743, z = 7 }
local POS_TOLERANCE = 5
local CAP_MIN       = 100

local GPS_DIST_EXTREME  = 20
local REFOLLOW_INTERVAL = 900

local FOLLOW_PHASES = { HUNTING = true, WAIT_SAFE = true }
local ROUTE_PHASES  = { REFILL = true, VOLTAR_HUNT = true }

local VOC_DATA = {
    EM = { {name="Gt Mana", id=238, min=100}, {name="Ult Spirit", id=23374, min=100} },
    EK = { {name="Str Mana", id=237, min=100}, {name="Sup Health", id=23375, min=100}, {name="Ult Health", id=7643, min=100} },
    RP = { {name="Ult Spirit", id=23374, min=100}, {name="GFB", id=3191, min=100}, {name="Diam Arrow", id=35901, min=100} },
    MS = { {name="Ult Mana", id=23373, min=100}, {name="GFB", id=3191, min=100} },
    ED = { {name="Ult Mana", id=23373, min=100}, {name="GFB", id=3191, min=100} }
}

Comms.FollowerSetup(MY_PORT, LEADER_IP, LEADER_PORT)
local myVoc = VOC_DATA[MY_VOC]

pcall(function() local f = io.open("zb_follower_phase.txt", "w"); if f then f:write("STANDBY"); f:close() end end)
_G.FollowerPhase = "STANDBY"

local function getCapOz() local ok, v = pcall(Player.getCapacity); return (ok and v) and v / 100 or 0 end
local function countItem(id) if not id then return 0 end local ok, v = pcall(Game.getItemCount, id); return ok and v or 0 end
local function getPos() local ok, p = pcall(Map.getCameraPosition); return ok and p or { x = 0, y = 0, z = 0 } end
local function nearPos(a, b, tol) if not a or not b or a.z ~= b.z then return false end return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= (tol or 1) end
local function getDistance(pos1, pos2) if not pos1 or not pos2 then return 999 end return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y)) end

local function sendFollow(targetName) pcall(Player.stopAutoWalk); pcall(Game.talk, "!follow " .. targetName, Enums.TalkTypes.TALKTYPE_SAY) end
local function sendUnfollow() pcall(Game.talk, "!follow", Enums.TalkTypes.TALKTYPE_SAY) end

local function goToAdjacentTile(targetX, targetY, targetZ)
    local myPos = getPos()
    if myPos.z ~= targetZ then pcall(Map.goTo, targetX, targetY, targetZ) return end
    local dx, dy = targetX - myPos.x, targetY - myPos.y
    local adjX, adjY = targetX, targetY
    if math.abs(dx) >= math.abs(dy) then
        if dx > 0 then adjX = targetX - 1 elseif dx < 0 then adjX = targetX + 1 end
    else
        if dy > 0 then adjY = targetY - 1 elseif dy < 0 then adjY = targetY + 1 end
    end
    if adjX == targetX and adjY == targetY then adjY = targetY + 1 end
    pcall(Map.goTo, adjX, adjY, targetZ)
end

local function amIDead() local ok, hp = pcall(Player.getHealth); return (ok and hp ~= nil and hp <= 0) end
local function needsRefill()
    if getCapOz() < CAP_MIN then return true, "Cap" end
    for _, item in ipairs(myVoc) do if countItem(item.id) < item.min then return true, item.name end end
    return false, "OK"
end
local function saveCavebotPhase(phase) pcall(function() local f = io.open("zb_follower_phase.txt", "w"); if f then f:write(phase); f:close() end end) end
local function saveFollowerNeed(needR) pcall(function() local f = io.open("zb_follower_need.txt", "w"); if f then f:write(needR and "1" or "0"); f:close() end end) end

local hudHandle = nil
local function renderHud(isLost, needR, reason, followStatus, dist)
    local myPos = getPos()
    local text = string.format("[ FOLLOWER HUD v19.1 ]\nFase: %s\nPos: %d, %d, %d\nCaveBot: %s\nAcao: %s\nGPS Emerg: %s\nDist Lider: %d sqm\nAlvo: %s\nRefill: %s (%s)\n------------------\nCap: %.0f oz\n", 
        _G.FollowerPhase, myPos.x, myPos.y, myPos.z, ROUTE_PHASES[_G.FollowerPhase] and "ON (Rotas)" or "OFF", followStatus, isLost and "ATIVO" or "OFF", dist, TARGET_TO_FOLLOW, needR and "SIM" or "NAO", reason, getCapOz())
    for _, item in ipairs(myVoc) do text = text .. string.format("%s: %d\n", item.name, countItem(item.id)) end
    if not hudHandle then hudHandle = HUD.new(10, 10, text, true); hudHandle:setDraggable(true) else hudHandle:setText(text) end
    hudHandle:setColor(220, 220, 220)
end

print("[FOLLOWER v19.1] Tolerância a Teleports e Delay de Pânico Adicionados.")
local isFollowing, gpsActive = false, false
local myPulse, cbState = 0, nil
local lastPhase, followStatus = "STANDBY", "NENHUM"
local refollowTimer, isDead, panicCounter = 0, false, 0

while true do
    myPulse = myPulse + 1
    local st = Comms.FollowerReceive()
    if st and st.phase then _G.FollowerPhase = st.phase end

    local myPos, isLost = getPos(), false
    isDead = amIDead()

    local leaderDist, leaderFloor, hasLeaderPos = 999, myPos.z, false
    if st and st.leaderX and st.leaderY and st.leaderZ then
        leaderDist = getDistance(myPos, { x = st.leaderX, y = st.leaderY, z = st.leaderZ })
        leaderFloor, hasLeaderPos = st.leaderZ, true
    end

    local diffFloor   = (leaderFloor ~= myPos.z)
    local extremeDist = (leaderDist > GPS_DIST_EXTREME and not diffFloor)

    if FOLLOW_PHASES[_G.FollowerPhase] then
        if not FOLLOW_PHASES[lastPhase] then
            sendFollow(TARGET_TO_FOLLOW)
            isFollowing, gpsActive, refollowTimer, panicCounter = true, false, 0, 0
            followStatus = "!follow " .. TARGET_TO_FOLLOW
        end

        if diffFloor or extremeDist then
            panicCounter = panicCounter + 1
            if panicCounter > 5 then -- ~1 segundo de tolerância para o servidor teleportar
                isLost = true
                if not gpsActive then sendUnfollow(); isFollowing, gpsActive = false, true end
                followStatus = "GPS EMERGENCIA"
                if hasLeaderPos then goToAdjacentTile(st.leaderX, st.leaderY, st.leaderZ) end
            else
                followStatus = "!follow (Aguardando Servidor...)"
            end
        else
            panicCounter = 0
            if gpsActive then
                pcall(Player.stopAutoWalk)
                sendFollow(TARGET_TO_FOLLOW)
                gpsActive, isFollowing, refollowTimer = false, true, 0
                followStatus = "!follow " .. TARGET_TO_FOLLOW .. " (retomado)"
            elseif not isFollowing then
                sendFollow(TARGET_TO_FOLLOW)
                isFollowing, refollowTimer, followStatus = true, 0, "!follow " .. TARGET_TO_FOLLOW
            else
                refollowTimer = refollowTimer + 1
                if refollowTimer >= REFOLLOW_INTERVAL then
                    sendFollow(TARGET_TO_FOLLOW)
                    refollowTimer, followStatus = 0, "!follow " .. TARGET_TO_FOLLOW .. " (refresh)"
                end
            end
        end
        if cbState ~= false then pcall(Engine.enableCaveBot, false); cbState = false end

    elseif ROUTE_PHASES[_G.FollowerPhase] then
        if isFollowing then sendUnfollow(); isFollowing = false end
        if gpsActive then pcall(Player.stopAutoWalk); gpsActive = false end
        refollowTimer, panicCounter, followStatus = 0, 0, "ROTA CAVEBOT"
        if cbState ~= true then pcall(Engine.enableCaveBot, true); cbState = true end
    else
        if isFollowing then sendUnfollow(); isFollowing = false end
        if gpsActive then pcall(Player.stopAutoWalk); gpsActive = false end
        refollowTimer, panicCounter, followStatus, cbState = 0, 0, "PARADO (STANDBY)", nil
    end

    lastPhase = _G.FollowerPhase
    saveCavebotPhase(_G.FollowerPhase)
    local needR, reason = needsRefill()
    saveFollowerNeed(needR)
    
    Comms.FollowerSendToLeader({ 
        from = MY_NAME, needsRefill = needR, reason = reason, atSafe = nearPos(getPos(), SAFE_POS, POS_TOLERANCE),
        cap = getCapOz(), fPhase = _G.FollowerPhase, isFollowing = isFollowing, isLost = isLost, pulse = myPulse, isDead = isDead
    })
    
    renderHud(isLost, needR, reason, followStatus, leaderDist)
    wait(200)
end