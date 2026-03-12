-- ============================================================
-- lib_event_log.lua  —  Registro de Eventos com Timestamp
-- ============================================================
-- Uso:
--   local Log = require("PartySystem.lib_event_log")
--   Log.init("leader")   -- cria arquivo event_log_leader.txt
--   Log.event("MORTE_DETECTADA", "Don Kina reportou isDead")
--   Log.transition("HUNTING", "WAIT_SAFE", "follower morreu")
-- ============================================================

local EventLog = {}

local logFile   = nil
local logPath   = "event_log.txt"
local MAX_LINES = 2000  -- evita arquivo infinito; faz rotação simples

-- Conta linhas aproximadamente para decidir rotação
local lineCount = 0

function EventLog.init(role)
    logPath = "event_log_" .. (role or "unknown") .. ".txt"
    -- Abre em modo append
    local f = io.open(logPath, "a")
    if f then
        f:write("\n========== SESSÃO INICIADA: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ==========\n")
        f:close()
    end
    lineCount = 0
end

local function writeEntry(line)
    local ok, err = pcall(function()
        local f = io.open(logPath, "a")
        if f then
            f:write(line .. "\n")
            f:close()
            lineCount = lineCount + 1
        end
    end)
    -- Rotação simples: se passou do limite, renomeia e recria
    if lineCount > MAX_LINES then
        pcall(function()
            os.remove(logPath .. ".old")
            os.rename(logPath, logPath .. ".old")
        end)
        lineCount = 0
    end
end

-- Evento genérico
function EventLog.event(tag, detail)
    local ts = os.date("%H:%M:%S")
    local line = string.format("[%s] [%s] %s", ts, tag, detail or "")
    writeEntry(line)
    print(line)  -- também imprime no console do bot
end

-- Transição de fase (máquina de estados)
function EventLog.transition(fromPhase, toPhase, reason)
    local ts = os.date("%H:%M:%S")
    local line = string.format("[%s] [TRANSICAO] %s -> %s  (motivo: %s)", ts, fromPhase, toPhase, reason or "auto")
    writeEntry(line)
    print(line)
end

-- Erro ou alerta
function EventLog.warn(detail)
    EventLog.event("AVISO", detail)
end

function EventLog.error(detail)
    EventLog.event("ERRO", detail)
end

return EventLog
