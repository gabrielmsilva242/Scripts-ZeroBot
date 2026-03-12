local Comms = require("PartySystem.lib_comms")

local MY_PORT = 45000
local LEADER_VOC = "EM" 
local FOLLOWERS = { 
    { name = "Don Kina", ip = "26.131.131.149", port = 45001 }, 
    -- Descomente as linhas abaixo quando eles forem participar!
    { name = "Clt Anthera", ip = "26.3.73.134", port = 45003 }, 
    { name = "Nick Invalido", ip = "26.3.73.134", port = 45002 }
}

-- OLHE A HUD NOVA PARA PEGAR SEU X, Y, Z E ATUALIZAR AQUI!
local SAFE_POS      = { x = 33861, y = 30743, z = 7 }
local POS_TOLERANCE = 5
local CAP_MIN       = 100

-- =============================================
-- CONFIGURACOES DO SISTEMA DE EMERGENCIA
-- =============================================
-- Tempo em segundos sem receber pacote do follower para considerar OFFLINE/MORTO
local OFFLINE_TIMEOUT      = 12
-- Tempo extra para confirmar morte (follower mandou isDead=true) antes de forçar retorno
local DEATH_CONFIRM_DELAY  = 3

local VOC_DATA = {
    EM = { {name="Gt Mana", id=238, min=100}, {name="Ult Spirit", id=23374, min=100} },
    EK = { {name="Str Mana", id=237, min=100}, {name="Sup Health", id=23375, min=100}, {name="Ult Health", id=7643, min=100} },
    RP = { {name="Ult Spirit", id=23374, min=100}, {name="GFB", id=3191, min=100}, {name="Diam Arrow", id=35901, min=100} },
    MS = { {name="Ult Mana", id=23373, min=100}, {name="GFB", id=3191, min=100} },
    ED = { {name="Ult Mana", id=23373, min=100}, {name="GFB", id=3191, min=100} }
}



Comms.LeaderSetup(MY_PORT)
local myVoc = VOC_DATA[LEADER_VOC]

-- Limpeza de Cache Inicial
pcall(function() local f = io.open("zb_leader_phase.txt", "w"); if f then f:write("STANDBY"); f:close() end end)
_G.LeaderPhase = "STANDBY"

local flags = {}
for _, f in ipairs(FOLLOWERS) do 
    flags[f.name] = { 
        needs_refill = false, at_safe = false, is_following = false, 
        is_lost = false, is_dead = false, last_seen = 0, cap = 0, 
        reason = "OK", fPhase = "STANDBY", last_pulse = 0,
        dead_since = 0  -- [NOVO] timestamp de quando detectou morte
    } 
end

-- =============================================
-- FUNCOES UTILITARIAS
-- =============================================
local function getCapOz() local ok, v = pcall(Player.getCapacity); return (ok and v) and v / 100 or 0 end
local function countItem(id) if not id then return 0 end local ok, v = pcall(Game.getItemCount, id); return ok and v or 0 end
local function getPos() local ok, p = pcall(Map.getCameraPosition); return ok and p or { x = 0, y = 0, z = 0 } end
local function nearPos(a, b, tol) if not a or not b or a.z ~= b.z then return false end return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= (tol or 1) end

local function leaderNeedsRefill()
    if getCapOz() < CAP_MIN then return true, "Cap" end
    for _, item in ipairs(myVoc) do if countItem(item.id) < item.min then return true, item.name end end
    return false, "OK"
end

local function saveCavebotState(lNeed, fNeed, isR, isFlw)
    pcall(function() local f = io.open("zb_leader_state.txt", "w"); if f then f:write((lNeed and "1" or "0") .. "," .. (fNeed and "1" or "0") .. "," .. (isR and "1" or "0") .. "," .. (isFlw and "1" or "0")); f:close() end end)
end

local function readCavebotPhase()
    pcall(function() local f = io.open("zb_leader_phase.txt", "r"); if f then local p = f:read("*a"); if p and p ~= "" then _G.LeaderPhase = p end; f:close() end end)
end

-- =============================================
-- [NOVO] FORÇAR FASE VIA ARQUIVO
-- Escreve no arquivo para que o CaveBot waypoint leia
-- =============================================
local function forcePhase(newPhase)
    _G.LeaderPhase = newPhase
    pcall(function() local f = io.open("zb_leader_phase.txt", "w"); if f then f:write(newPhase); f:close() end end)
    print("[LEADER] Fase FORCADA para: " .. newPhase)
end

-- =============================================
-- HUD
-- =============================================
local hudHandle = nil
local function renderHud(lNeed, fNeed, allAtSafe, allFollowing, emergencyActive)
    local _, reason = leaderNeedsRefill()
    local myPos = getPos()
    
    local smText = ">>> MÁQUINA DE ESTADO <<<\n"
    smText = smText .. string.format("- Lider quer loja? %s (%s)\n", lNeed and "SIM" or "NAO", reason)
    smText = smText .. string.format("- Kina quer loja?  %s\n", fNeed and "SIM" or "NAO")
    smText = smText .. string.format("- Todos no Safe?   %s\n", allAtSafe and "SIM" or "NAO")
    smText = smText .. string.format("- Kina deu Follow? %s\n", allFollowing and "SIM" or "NAO")
    if emergencyActive then
        smText = smText .. "- !! EMERGENCIA !!  SIM\n"
    end

    local text = string.format("[ LEADER HUD v15 ]\nFase Ditada: %s\nPos Atual: %d, %d, %d\n------------------\n%s------------------\nCap: %.0f oz\n", 
        _G.LeaderPhase, myPos.x, myPos.y, myPos.z, smText, getCapOz())
        
    for _, item in ipairs(myVoc) do text = text .. string.format("%s: %d\n", item.name, countItem(item.id)) end
    
    text = text .. "------------------\n[ FOLLOWERS ]"
    for _, f in ipairs(FOLLOWERS) do
        local fl = flags[f.name]; local isOnline = (os.time() - fl.last_seen) < OFFLINE_TIMEOUT
        local alerta = "[OK]"
        if fl.is_dead then alerta = "[MORTO!!!]"
        elseif not isOnline then alerta = "[OFFLINE/FECHADO]" 
        elseif fl.is_lost then alerta = "[PERDIDO/GPS ON]" end
        
        text = text .. string.format("\n- %s: %s\n  Sfe:%s | Flw:%s | Ref:%s | Dead:%s", 
            f.name, alerta, fl.at_safe and "S" or "N", fl.is_following and "S" or "N", 
            fl.needs_refill and "S" or "N", fl.is_dead and "S" or "N")
    end
    
    if not hudHandle then hudHandle = HUD.new(10, 10, text, true); hudHandle:setDraggable(true) else hudHandle:setText(text) end
    hudHandle:setColor(220, 220, 220)
end

-- =============================================
-- VARIÁVEIS DE ESTADO
-- =============================================
print("[LEADER v15] Radio HUD + Pos Tracker + Detecção de Morte + Emergência.")
local radarBraked       = false
local emergencyActive   = false  -- [NOVO] Flag de emergência global
local emergencyTimer    = 0      -- [NOVO] Timestamp de quando emergência foi ativada

-- =============================================
-- LOOP PRINCIPAL
-- =============================================
while true do
    readCavebotPhase()

    -- =========================================
    -- RECEBER PACOTES DOS FOLLOWERS
    -- =========================================
    for _, f in ipairs(FOLLOWERS) do
        local pkt = Comms.LeaderReceiveFrom(f.name)
        if pkt and pkt.from and flags[pkt.from] and pkt.pulse ~= flags[pkt.from].last_pulse then 
            local fl = flags[pkt.from]
            fl.needs_refill = pkt.needsRefill
            fl.at_safe      = pkt.atSafe
            fl.is_following = pkt.isFollowing
            fl.is_lost      = pkt.isLost
            fl.last_seen    = os.time()
            fl.last_pulse   = pkt.pulse

            -- [NOVO] Detecção de morte reportada pelo follower
            if pkt.isDead then
                if not fl.is_dead then
                    fl.is_dead = true
                    fl.dead_since = os.time()
                    print("[LEADER] ⚠️ ALERTA: " .. pkt.from .. " REPORTOU MORTE!")
                end
            else
                -- Follower voltou a viver (respawnou e reconectou)
                if fl.is_dead then
                    fl.is_dead = false
                    fl.dead_since = 0
                    print("[LEADER] " .. pkt.from .. " voltou! Morte resetada.")
                end
            end
        end
    end

    -- =========================================
    -- CALCULAR FLAGS AGREGADAS
    -- =========================================
    local lNeed = leaderNeedsRefill()
    local fNeed, allAtSafe, allFollowing, anyLost, anyDead = false, nearPos(getPos(), SAFE_POS, POS_TOLERANCE), true, false, false

    for _, f in ipairs(FOLLOWERS) do
        local fl = flags[f.name]
        local isOnline = (os.time() - fl.last_seen) < OFFLINE_TIMEOUT

        if fl.is_dead then
            anyDead = true
        end

        if isOnline and not fl.is_dead then 
            if fl.needs_refill then fNeed = true end
            if not fl.at_safe then allAtSafe = false end
            if not fl.is_following then allFollowing = false end
            if fl.is_lost then anyLost = true end
        elseif not isOnline then
            -- Follower offline = possível morte ou DC
            allAtSafe = false; allFollowing = false; anyLost = true
            -- Se sumiu durante HUNTING, pode ter morrido
            if _G.LeaderPhase == "HUNTING" and fl.last_seen > 0 then
                anyDead = true
                print("[LEADER] " .. f.name .. " OFFLINE há " .. (os.time() - fl.last_seen) .. "s!")
            end
        end
    end

    -- =========================================
    -- [NOVO] SISTEMA DE EMERGÊNCIA POR MORTE
    -- Se alguém morreu durante a hunt, força retorno ao safe
    -- =========================================
    if anyDead and _G.LeaderPhase == "HUNTING" and not emergencyActive then
        emergencyActive = true
        emergencyTimer  = os.time()
        -- Força fase WAIT_SAFE para que o cavebot do líder volte ao safe spot
        -- O script do cavebot ao ler WAIT_SAFE no label de checagem irá pular para VOLTAR_SAFE
        forcePhase("WAIT_SAFE")
        print("[LEADER] 🚨 EMERGÊNCIA ATIVADA! Follower morreu ou desconectou. Voltando ao Safe Spot!")
    end

    -- Reseta emergência quando todos voltaram ao safe e ninguém mais está morto
    if emergencyActive and not anyDead and allAtSafe then
        emergencyActive = false
        emergencyTimer  = 0
        print("[LEADER] Emergência encerrada. Todos seguros.")
    end

    -- =========================================
    -- RADAR DE QUÓRUM (Trava de Segurança durante Hunt)
    -- =========================================
    if _G.LeaderPhase == "HUNTING" then
        if anyLost or anyDead then
            if not radarBraked then 
                pcall(Engine.enableCaveBot, false)
                radarBraked = true
                if anyDead then
                    print("[RADAR] Follower morto/offline! Freio de emergência acionado.")
                else
                    print("[RADAR] Falha no Quorum! Freio acionado.")
                end
            end
        else
            if radarBraked then pcall(Engine.enableCaveBot, true); radarBraked = false; print("[RADAR] Quorum restabelecido! Freio solto.") end
        end
    else
        if radarBraked then radarBraked = false end
    end

    -- =========================================
    -- SALVAR ESTADO E BROADCAST
    -- =========================================
    saveCavebotState(lNeed, fNeed, allAtSafe, allFollowing)
    Comms.LeaderBroadcast(FOLLOWERS, { 
        phase   = _G.LeaderPhase, 
        leaderX = getPos().x, 
        leaderY = getPos().y, 
        leaderZ = getPos().z 
    })
    renderHud(lNeed, fNeed, allAtSafe, allFollowing, emergencyActive)
    wait(200)
end
