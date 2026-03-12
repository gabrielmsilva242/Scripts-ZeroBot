-------------------------------------------------------------------------
-- lib_comms.lua v6 — Comunicação UDP (Sintaxe Blindada)
-------------------------------------------------------------------------

local socket = require("socket")

local json = {}
json.encode = function(val)
    if val == nil then return "null" end
    local t = type(val)
    if t == "boolean" then return val and "true" or "false" end
    if t == "number"  then return tostring(val) end
    if t == "string"  then
        return '"' .. val:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n') .. '"'
    end
    if t == "table" then
        if #val > 0 then
            local p = {}
            for i = 1, #val do p[i] = json.encode(val[i]) end
            return "[" .. table.concat(p, ",") .. "]"
        else
            local p = {}
            for k, v in pairs(val) do
                if type(k) == "string" then
                    p[#p+1] = json.encode(k) .. ":" .. json.encode(v)
                end
            end
            return "{" .. table.concat(p, ",") .. "}"
        end
    end
    return "null"
end

json.decode = function(str)
    if not str or str == "" then return nil end
    local s = str:gsub('"(%w+)"%s*:', '["%1"]='):gsub('%[%s*%]', '{}'):gsub(':null', '=nil'):gsub(':true', '=true'):gsub(':false', '=false')
    local fn = loadstring or load
    local func = fn("return " .. s)
    if func then
        local ok, r = pcall(func)
        if ok then return r end
    end
    return nil
end

-------------------------------------------------------------------------
-- VARIÁVEIS INTERNAS DA REDE
-------------------------------------------------------------------------
local Comms = {}
local udp = nil
local role = nil

-- Variáveis de alvo para o Seguidor
local targetLeaderIp = "26.131.131.149"
local targetLeaderPort = 45000

-- Líder: endereço e dados de cada seguidor
local followerAddrs = {}
local followerData  = {}
local lastLeaderData = nil

-------------------------------------------------------------------------
-- LÍDER
-------------------------------------------------------------------------
Comms.LeaderSetup = function(myPort)
    role = "leader"
    udp = socket.udp()
    udp:setsockname("0.0.0.0", myPort)
    udp:settimeout(0)
    print("[COMMS] Lider escutando na porta: " .. tostring(myPort))
end

local drainFollowerPackets = function()
    while true do
        local data, ip, port = udp:receivefrom()
        if not data then break end
        local pkt = json.decode(data)
        if pkt and pkt.from then
            followerAddrs[pkt.from] = { ip = ip, port = port }
            followerData[pkt.from]  = pkt
        end
    end
end

Comms.LeaderReceiveFrom = function(name)
    drainFollowerPackets()
    return followerData[name]
end

Comms.LeaderBroadcast = function(followers, statusTable)
    drainFollowerPackets()
    local data = json.encode(statusTable)
    if not data then return end
    for _, f in ipairs(followers) do
        local addr = followerAddrs[f.name]
        local ip   = addr and addr.ip   or f.ip
        local port = addr and addr.port or f.port
        if ip and port then
            udp:sendto(data, ip, port)
        end
    end
end

-------------------------------------------------------------------------
-- SEGUIDOR
-------------------------------------------------------------------------
Comms.FollowerSetup = function(myPort, leaderIp, leaderPort)
    role = "follower"
    targetLeaderIp = leaderIp
    targetLeaderPort = leaderPort
    
    udp = socket.udp()
    udp:setsockname("0.0.0.0", myPort)
    udp:settimeout(0)
    
    print("[COMMS] Seguidor OK, porta local: " .. tostring(myPort))
end

Comms.FollowerReceive = function()
    while true do
        local data, ip, port = udp:receivefrom()
        if not data then break end
        local pkt = json.decode(data)
        if pkt then lastLeaderData = pkt end
    end
    return lastLeaderData
end

Comms.FollowerSendToLeader = function(statusTable)
    local data = json.encode(statusTable)
    if data then
        udp:sendto(data, targetLeaderIp, targetLeaderPort)
    end
end

return Comms