-- ============================================================
-- role_follower_v20.lua  —  Follower com Melhorias Consolidadas
-- ============================================================
local Comms = require("PartySystem.lib_comms")
local CFG   = require("PartySystem.party_config")
local Log   = require("PartySystem.lib_event_log")

local MY_NAME = "Don Kina"
local MY_VOC  = "EK"

local myFollowerData = nil
for _, f in ipairs(CFG.FOLLOWERS) do
    if f.name == MY_NAME then myFollowerData = f; break end
end
if not myFollowerData then error("[FOLLOWER] ERRO FATAL: '" .. MY_NAME .. "' não encontrado!") end

Log.init("follower_" .. MY_NAME:gsub(" ", "_"))

local MY_PORT     = myFollowerData.port
local LEADER_IP   = CFG.LEADER.ip
local LEADER_PORT = CFG.LEADER.port
local TARGET_TO_FOLLOW = CFG.LEADER.name

Comms.FollowerSetup(MY_PORT, LEADER_IP, LEADER_PORT)
local myVoc = CFG.VOC_DATA[MY_VOC]

pcall(function() local f = io.open("zb_follower_phase.txt", "w"); if f then f:write("STANDBY"); f:close() end end)
_G.FollowerPhase = "STANDBY"

local function getCapOz() local ok, v = pcall(Player.getCapacity); return (ok and v) and v / 100 or 0 end
local function countItem(id) if not id then return 0 end local ok, v = pcall(Game.getItemCount, id); return ok and v or 0 end
local function getPos() local ok, p = pcall(Map.getCameraPosition); return ok and p or { x = 0, y = 0, z = 0 } end
local function nearPos(a, b, tol) if not a or not b or a.z ~= b.z then return false end return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= (tol or 1) end
local function getDistance(pos1, pos2) if not pos1 or not pos2 then return 999 end return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y)) end

local function amIDead() local ok, hp = pcall(Player.getHealth); return (ok and hp ~= nil and hp <= 0) end
local function needsRefill()
    if getCapOz() < CFG.CAP_MIN then return true, "Cap" end
    for _, item in ipairs(myVoc) do if countItem(item.id) < item.min then return true, item.name end end
    return false, "OK"
end

local function sendFollow(targetName) pcall(Player.stopAutoWalk); pcall(Game.talk, "!follow " .. targetName, Enums.TalkTypes.TALKTYPE_SAY) end
local function sendUnfollow() pcall(Game.talk, "!follow", Enums.TalkTypes.TALKTYPE_SAY) end

local function goToAdjacentTile(targetX, targetY, targetZ)
    local myPos = getPos()
    if myPos.z ~= targetZ then pcall(Map.goTo, targetX, targetY, targetZ); return end
    local dx, dy = targetX - myPos.x, targetY - myPos.y
    local adjX, adjY = targetX, targetY
    if math.abs(dx) >= math.abs(dy) then adjX = dx > 0 and (targetX - 1) or (targetX + 1) else adjY = dy > 0 and (targetY - 1) or (targetY + 1) end
    if adjX == targetX and adjY == targetY then adjY = targetY + 1 end
    pcall(Map.goTo, adjX, adjY, targetZ)
end

local function isLeaderOnDifferentFloor(myPos, leaderFloor) return leaderFloor ~= myPos.z end
local function isLeaderExtremelyFar(dist) return dist > CFG.GPS_DIST_EXTREME end
local function saveCavebotPhase(phase) pcall(function() local f = io.open("zb_follower_phase.txt", "w"); if f then f:write(phase); f:close() end end) end
local function saveFollowerNeed(needR) pcall(function() local f = io.open("zb_follower_need.txt", "w"); if f then f:write(needR and "1" or "0"); f:close() end end) end

local hudHandle = nil
local function renderHud(isLost, needR, reason, followStatus, dist, gpsTimer)
    local myPos = getPos()
    local text = string.format(
        "[ FOLLOWER HUD v20 ]\nFase: %s\nPos: %d, %d, %d\nCaveBot: %s\nAcao: %s\nGPS Emerg: %s\nGPS Timer: %d/%d\nDist Lider: %d sqm\nAlvo: %s\nRefill: %s (%s)\n------------------\nCap: %.0f oz\n",
        _G.FollowerPhase, myPos.x, myPos.y, myPos.z, CFG.ROUTE_PHASES[_G.FollowerPhase] and "ON (Rotas)" or "OFF", followStatus, isLost and "ATIVO" or "OFF", gpsTimer, CFG.GPS_RETRY_TIMEOUT, dist, TARGET_TO_FOLLOW, needR and "SIM" or "NAO", reason, getCapOz()
    )
    for _, item in ipairs(myVoc) do text = text .. string.format("%s: %d\n", item.name, countItem(item.id)) end
    if not hudHandle then hudHandle = HUD.new(10, 10, text, true); hudHandle:setDraggable(true) else hudHandle:setText(text) end
    hudHandle:setColor(220, 220, 220)
end

Log.event("INICIO", "Follower v20 iniciado. Char: " .. MY_NAME)
local isFollowing, gpsActive = false, false
local myPulse, cbState = 0, nil
local lastPhase, followStatus = "STANDBY", "NENHUM"
local refollowTimer, isDead, panicCounter, gpsRetryTimer = 0, false, 0, 0

while true do
    myPulse = myPulse + 1
    local st = Comms.FollowerReceive()
    if st and st.phase then _G.FollowerPhase = st.phase end

    local myPos, isLost, leaderDist, leaderFloor, hasLeaderPos = getPos(), false, 999, getPos().z, false
    isDead = amIDead()

    if st and st.leaderX and st.leaderY and st.leaderZ then
        leaderDist, leaderFloor, hasLeaderPos = getDistance(myPos, { x = st.leaderX, y = st.leaderY, z = st.leaderZ }), st.leaderZ, true
    end

    local diffFloor = isLeaderOnDifferentFloor(myPos, leaderFloor)
    local extremeDist = isLeaderExtremelyFar(leaderDist) and not diffFloor

    if CFG.FOLLOW_PHASES[_G.FollowerPhase] then
        if not CFG.FOLLOW_PHASES[lastPhase] then
            sendFollow(TARGET_TO_FOLLOW); isFollowing, gpsActive, refollowTimer, panicCounter, gpsRetryTimer = true, false, 0, 0, 0
            followStatus = "!follow " .. TARGET_TO_FOLLOW
        end

        if diffFloor or extremeDist then
            panicCounter = panicCounter + 1
            if panicCounter > CFG.PANIC_TOLERANCE then
                isLost = true
                if not gpsActive then sendUnfollow(); isFollowing, gpsActive, gpsRetryTimer = false, true, 0 end
                followStatus = "GPS EMERGENCIA"; gpsRetryTimer = gpsRetryTimer + 1
                if hasLeaderPos then goToAdjacentTile(st.leaderX, st.leaderY, st.leaderZ) end
                
                if gpsRetryTimer >= CFG.GPS_RETRY_TIMEOUT then
                    pcall(Player.stopAutoWalk); sendFollow(TARGET_TO_FOLLOW)
                    gpsActive, isFollowing, gpsRetryTimer, panicCounter = false, true, 0, 0
                    followStatus = "!follow " .. TARGET_TO_FOLLOW .. " (reset pós-timeout)"
                end
            else
                followStatus = "!follow (Aguardando Servidor...)"
            end
        else
            panicCounter, gpsRetryTimer = 0, 0
            if gpsActive then
                pcall(Player.stopAutoWalk); sendFollow(TARGET_TO_FOLLOW)
                gpsActive, isFollowing, refollowTimer, followStatus = false, true, 0, "!follow " .. TARGET_TO_FOLLOW .. " (retomado)"
            elseif not isFollowing then
                sendFollow(TARGET_TO_FOLLOW); isFollowing, refollowTimer, followStatus = true, 0, "!follow " .. TARGET_TO_FOLLOW
            else
                refollowTimer = refollowTimer + 1
                if refollowTimer >= CFG.REFOLLOW_INTERVAL then sendFollow(TARGET_TO_FOLLOW); refollowTimer, followStatus = 0, "!follow " .. TARGET_TO_FOLLOW .. " (refresh)" end
            end
        end
        if cbState ~= false then pcall(Engine.enableCaveBot, false); cbState = false end

    elseif CFG.ROUTE_PHASES[_G.FollowerPhase] then
        if isFollowing then sendUnfollow(); isFollowing = false end
        if gpsActive then pcall(Player.stopAutoWalk); gpsActive = false end
        refollowTimer, panicCounter, gpsRetryTimer, followStatus = 0, 0, 0, "ROTA CAVEBOT"
        if cbState ~= true then pcall(Engine.enableCaveBot, true); cbState = true end
    else
        if isFollowing then sendUnfollow(); isFollowing = false end
        if gpsActive then pcall(Player.stopAutoWalk); gpsActive = false end
        refollowTimer, panicCounter, gpsRetryTimer, followStatus, cbState = 0, 0, 0, "PARADO (STANDBY)", nil
    end

    lastPhase = _G.FollowerPhase; saveCavebotPhase(_G.FollowerPhase)
    local needR, reason = needsRefill(); saveFollowerNeed(needR)

    Comms.FollowerSendToLeader({ from = MY_NAME, needsRefill = needR, reason = reason, atSafe = nearPos(getPos(), CFG.SAFE_POS, CFG.POS_TOLERANCE), cap = getCapOz(), fPhase = _G.FollowerPhase, isFollowing = isFollowing, isLost = isLost, pulse = myPulse, isDead = isDead })
    renderHud(isLost, needR, reason, followStatus, leaderDist, gpsRetryTimer); wait(200)
end
