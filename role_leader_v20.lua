-- ============================================================
-- role_leader_v20.lua  —  Líder com Melhorias Consolidadas
-- ============================================================
local Comms = require("PartySystem.lib_comms")
local CFG   = require("PartySystem.party_config")
local Log   = require("PartySystem.lib_event_log")

Log.init("leader")

local MY_PORT   = CFG.LEADER.port
local LEADER_VOC = CFG.LEADER.voc
local FOLLOWERS  = CFG.FOLLOWERS

Comms.LeaderSetup(MY_PORT)
local myVoc = CFG.VOC_DATA[LEADER_VOC]

local VALID_SENDERS = {}
for _, f in ipairs(FOLLOWERS) do VALID_SENDERS[f.name] = true end
local function isValidSender(name) return VALID_SENDERS[name] == true end

local function getCapOz() local ok, v = pcall(Player.getCapacity); return (ok and v) and v / 100 or 0 end
local function countItem(id) if not id then return 0 end local ok, v = pcall(Game.getItemCount, id); return ok and v or 0 end
local function getPos() local ok, p = pcall(Map.getCameraPosition); return ok and p or { x = 0, y = 0, z = 0 } end
local function nearPos(a, b, tol) if not a or not b or a.z ~= b.z then return false end return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= (tol or 1) end

local function leaderNeedsRefill()
    if getCapOz() < CFG.CAP_MIN then return true, "Cap" end
    for _, item in ipairs(myVoc) do if countItem(item.id) < item.min then return true, item.name end end
    return false, "OK"
end

local function isFollowerOnline(fl) return (os.time() - fl.last_seen) < CFG.OFFLINE_TIMEOUT end
local function isFollowerInQuarantine(fl) return fl.quarantine_until and (os.time() < fl.quarantine_until) end
local function shouldTriggerEmergency(anyDead, currentPhase, emergencyActive) return anyDead and currentPhase == "HUNTING" and not emergencyActive end

local flags = {}
for _, f in ipairs(FOLLOWERS) do
    flags[f.name] = { needs_refill = false, at_safe = false, is_following = false, is_lost = false, is_dead = false, last_seen = 0, cap = 0, reason = "OK", fPhase = "STANDBY", last_pulse = 0, dead_since = 0, quarantine_until = 0 }
end

pcall(function() local f = io.open("zb_leader_phase.txt", "w"); if f then f:write("STANDBY"); f:close() end end)
_G.LeaderPhase = "STANDBY"

local function readCavebotPhase() pcall(function() local f = io.open("zb_leader_phase.txt", "r"); if f then local p = f:read("*a"); if p and p ~= "" then _G.LeaderPhase = p end; f:close() end end) end
local function forcePhase(newPhase, reason) local old = _G.LeaderPhase; _G.LeaderPhase = newPhase; pcall(function() local f = io.open("zb_leader_phase.txt", "w"); if f then f:write(newPhase); f:close() end end); Log.transition(old, newPhase, reason or "forcePhase") end
local function saveCavebotState(lNeed, fNeed, isR, isFlw) pcall(function() local f = io.open("zb_leader_state.txt", "w"); if f then f:write((lNeed and "1" or "0") .. "," .. (fNeed and "1" or "0") .. "," .. (isR and "1" or "0") .. "," .. (isFlw and "1" or "0")); f:close() end end) end

local hudHandle = nil
local function renderHud(lNeed, fNeed, allAtSafe, allFollowing, emergencyActive)
    local _, reason = leaderNeedsRefill()
    local myPos = getPos()
    local smText = string.format(">>> MAQUINA DE ESTADO <<<\n- Lider quer loja? %s (%s)\n- Follower quer loja? %s\n- Todos no Safe?   %s\n- Todos Follow?    %s\n", lNeed and "SIM" or "NAO", reason, fNeed and "SIM" or "NAO", allAtSafe and "SIM" or "NAO", allFollowing and "SIM" or "NAO")
    if emergencyActive then smText = smText .. "- !! EMERGENCIA !!  SIM\n" end
    local text = string.format("[ LEADER HUD v20 ]\nFase: %s\nPos: %d, %d, %d\n------------------\n%s------------------\nCap: %.0f oz\n", _G.LeaderPhase, myPos.x, myPos.y, myPos.z, smText, getCapOz())
    for _, item in ipairs(myVoc) do text = text .. string.format("%s: %d\n", item.name, countItem(item.id)) end
    text = text .. "------------------\n[ FOLLOWERS ]"
    for _, f in ipairs(FOLLOWERS) do
        local fl = flags[f.name]; local online = isFollowerOnline(fl); local inQ = isFollowerInQuarantine(fl)
        local alerta = "[OK]"
        if fl.is_dead then alerta = "[MORTO!!!]" elseif not online then alerta = "[OFFLINE]" elseif inQ then alerta = "[QUARENTENA]" elseif fl.is_lost then alerta = "[PERDIDO/GPS]" end
        text = text .. string.format("\n- %s: %s\n  Sfe:%s | Flw:%s | Ref:%s | Dead:%s", f.name, alerta, fl.at_safe and "S" or "N", fl.is_following and "S" or "N", fl.needs_refill and "S" or "N", fl.is_dead and "S" or "N")
    end
    if not hudHandle then hudHandle = HUD.new(10, 10, text, true); hudHandle:setDraggable(true) else hudHandle:setText(text) end; hudHandle:setColor(220, 220, 220)
end

Log.event("INICIO", "Leader v20 iniciado. Vocação: " .. LEADER_VOC)
local radarBraked, emergencyActive, emergencyTimer = false, false, 0

while true do
    readCavebotPhase()

    for _, f in ipairs(FOLLOWERS) do
        local pkt = Comms.LeaderReceiveFrom(f.name)
        if pkt and pkt.from then
            if not isValidSender(pkt.from) then
                Log.warn("Pacote de remetente DESCONHECIDO: " .. tostring(pkt.from))
            elseif flags[pkt.from] and pkt.pulse ~= flags[pkt.from].last_pulse then
                local fl = flags[pkt.from]
                fl.needs_refill, fl.at_safe, fl.is_following, fl.is_lost, fl.last_seen, fl.last_pulse = pkt.needsRefill, pkt.atSafe, pkt.isFollowing, pkt.isLost, os.time(), pkt.pulse
                if pkt.isDead then
                    if not fl.is_dead then fl.is_dead = true; fl.dead_since = os.time(); Log.event("MORTE_DETECTADA", pkt.from .. " reportou isDead=true") end
                else
                    if fl.is_dead then fl.is_dead = false; fl.dead_since = 0; fl.quarantine_until = os.time() + CFG.RECONNECT_QUARANTINE; Log.event("RESPAWN", pkt.from .. " voltou! Quarentena ativada.") end
                end
            end
        end
    end

    local lNeed, fNeed, allAtSafe, allFollowing, anyLost, anyDead = leaderNeedsRefill(), false, nearPos(getPos(), CFG.SAFE_POS, CFG.POS_TOLERANCE), true, false, false

    for _, f in ipairs(FOLLOWERS) do
        local fl = flags[f.name]; local online = isFollowerOnline(fl)
        if fl.is_dead then anyDead = true end

        if online and not fl.is_dead then
            if isFollowerInQuarantine(fl) then
                -- CORREÇÃO DA QUARENTENA: Trava de segurança ativa
                allAtSafe    = false
                allFollowing = false
            else
                if fl.needs_refill then fNeed = true end
                if not fl.at_safe then allAtSafe = false end
                if not fl.is_following then allFollowing = false end
                if fl.is_lost then anyLost = true end
            end
        elseif not online then
            allAtSafe, allFollowing, anyLost = false, false, true
            if _G.LeaderPhase == "HUNTING" and fl.last_seen > 0 then anyDead = true; Log.warn(f.name .. " OFFLINE") end
        end
    end

    if shouldTriggerEmergency(anyDead, _G.LeaderPhase, emergencyActive) then
        emergencyActive = true; emergencyTimer = os.time(); forcePhase("WAIT_SAFE", "Emergência ativada"); Log.event("EMERGENCIA_ON", "Voltando ao Safe Spot!")
    end

    if emergencyActive and not anyDead and allAtSafe then emergencyActive = false; emergencyTimer = 0; Log.event("EMERGENCIA_OFF", "Emergência encerrada.") end

    if _G.LeaderPhase == "HUNTING" then
        if anyLost or anyDead then
            if not radarBraked then pcall(Engine.enableCaveBot, false); radarBraked = true; Log.event("RADAR_FREIO", "Freio acionado") end
        else
            if radarBraked then pcall(Engine.enableCaveBot, true); radarBraked = false; Log.event("RADAR_SOLTO", "Quórum restabelecido") end
        end
    else
        if radarBraked then radarBraked = false end
    end

    saveCavebotState(lNeed, fNeed, allAtSafe, allFollowing)
    Comms.LeaderBroadcast(FOLLOWERS, { phase = _G.LeaderPhase, leaderX = getPos().x, leaderY = getPos().y, leaderZ = getPos().z })
    renderHud(lNeed, fNeed, allAtSafe, allFollowing, emergencyActive)
    wait(200)
end
