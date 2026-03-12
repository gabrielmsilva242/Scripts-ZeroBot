-- ============================================================
-- party_config.lua  —  Arquivo de Configuração Compartilhado
-- ============================================================
-- Todas as constantes que antes eram duplicadas entre
-- role_leader e role_follower agora vivem aqui.
-- Qualquer script faz:  local CFG = require("PartySystem.party_config")
-- ============================================================

local CFG = {}

-- =============================================
-- IDENTIDADES  (edite conforme seu time)
-- =============================================
CFG.LEADER = {
    name = "Joaquim Quiabo",
    ip   = "26.131.131.149",   -- IP Radmin/Hamachi do líder
    port = 45000,
    voc  = "EM",
}

CFG.FOLLOWERS = {
    { name = "Don Kina",      ip = "26.131.131.149", port = 45001, voc = "EK" },
    { name = "Clt Anthera",   ip = "26.3.73.134",    port = 45003, voc = "RP" },
    { name = "Nick Invalido", ip = "26.3.73.134",    port = 45002, voc = "MS" },
}

-- =============================================
-- POSIÇÕES & TOLERÂNCIAS
-- =============================================
CFG.SAFE_POS      = { x = 33861, y = 30743, z = 7 }
CFG.POS_TOLERANCE = 5
CFG.CAP_MIN       = 100

-- =============================================
-- TIMERS  (em ciclos de 200 ms salvo indicação)
-- =============================================
CFG.GPS_DIST_EXTREME    = 20       -- sqm pra considerar "perdido"
CFG.REFOLLOW_INTERVAL   = 900      -- ciclos (~3 min) pra re-follow preventivo
CFG.OFFLINE_TIMEOUT     = 12       -- segundos sem pacote = offline
CFG.DEATH_CONFIRM_DELAY = 3        -- segundos extras antes de confirmar morte
CFG.PANIC_TOLERANCE     = 5        -- ciclos de tolerância antes de GPS emergência
CFG.RECONNECT_QUARANTINE = 15      -- ciclos de "quarentena" ao voltar de offline/morte
CFG.GPS_RETRY_TIMEOUT   = 50       -- ciclos em GPS_EMERGENCIA antes de resetar follow

-- =============================================
-- FASES VÁLIDAS
-- =============================================
CFG.FOLLOW_PHASES = { HUNTING = true, WAIT_SAFE = true }
CFG.ROUTE_PHASES  = { REFILL = true, VOLTAR_HUNT = true }

-- =============================================
-- VOCAÇÕES & ITENS DE REFILL
-- Centralizado: líder e followers leem daqui.
-- =============================================
CFG.VOC_DATA = {
    EM = { {name="Gt Mana",    id=238,   min=100}, {name="Ult Spirit",  id=23374, min=100} },
    EK = { {name="Str Mana",   id=237,   min=100}, {name="Sup Health",  id=23375, min=100}, {name="Ult Health", id=7643, min=100} },
    RP = { {name="Ult Spirit", id=23374, min=100}, {name="GFB",         id=3191,  min=100}, {name="Diam Arrow", id=35901, min=100} },
    MS = { {name="Ult Mana",   id=23373, min=100}, {name="GFB",         id=3191,  min=100} },
    ED = { {name="Ult Mana",   id=23373, min=100}, {name="GFB",         id=3191,  min=100} },
}

-- =============================================
-- TRANSIÇÕES DA MÁQUINA DE ESTADO (Leader)
-- Formato: STATE_TRANSITIONS[fase_atual] = { {cond=func, to="FASE", reason="motivo"}, ... }
-- A primeira condição verdadeira vence (ordem importa!).
-- =============================================
-- Será preenchido pelo leader, mas a estrutura vive aqui
-- para que o config seja a "fonte da verdade".
CFG.VALID_PHASES = {
    "STANDBY", "HUNTING", "WAIT_SAFE", "REFILL", "VOLTAR_HUNT"
}

return CFG
