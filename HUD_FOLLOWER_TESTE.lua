-- =========================================================
-- HUD BUILDER FOLLOWER - CLEAN UI & FLUXO GUIADO
-- =========================================================

local PANEL_X = 25
local FIRST_ROW_Y = 100          
local ROW_SPACING = 30 

local HANDLE_TEXT = "[ ARRASTAR AQUI ] HUD FOLLOWER"
local HANDLE_COLOR = {0, 200, 255} -- Azul claro para diferenciar do Líder na tela

local WAYPOINT_LABEL = 9
local WAYPOINT_SCRIPT = 11

local function injectAction(actionType, content)
    local x, y, z = 0, 0, 0
    pcall(function()
        local pos = Map.getCameraPosition()
        if pos then x, y, z = pos.x, pos.y, pos.z end
    end)

    if actionType == "label" then
        CaveBot.addWaypoint(WAYPOINT_LABEL, x, y, z, content)
        print("[INJETADO] Label adicionado: " .. content)
    elseif actionType == "script" then
        CaveBot.addWaypoint(WAYPOINT_SCRIPT, x, y, z, content)
        print("[INJETADO] Script adicionado!")
    elseif actionType == "info" then
        print("[AVISO PARA O JOGADOR] " .. content)
    end
end

local function hudGetPos(h)
    local x, y = h:getPos()
    if type(x) == "table" then return (x.x or x[1] or 0), (x.y or x[2] or 0) end
    return (x or 0), (y or 0)
end

local function createTextHUD(x, y, text, callback, isInfo)
    local hudName = HUD.new(x, y, text)
    if isInfo then
        hudName:setColor(255, 215, 0) -- Amarelo para alertas
    else
        hudName:setColor(255, 255, 255)
    end
    hudName:setDraggable(false)
    hudName:setCallback(callback)
    return hudName
end

local huds = {}

-- Matriz Guiada: 10 passos do Follower + 2 Extras
local builderNodes = {
    { name="1. Label: HUNT_IDLE", type="label", content="HUNT_IDLE" },
    { name="2. Script: Loop Hunt", type="script", content='local phase = "UNKNOWN"; pcall(function() local f=io.open("zb_follower_phase.txt","r"); if f then phase=f:read("*a"); f:close() end end); if phase=="HUNTING" or phase=="UNKNOWN" then wait(1000); CaveBot.GoTo("HUNT_IDLE") else CaveBot.GoTo("VOLTAR_SAFE") end' },
    
    { name="3. Label: VOLTAR_SAFE", type="label", content="VOLTAR_SAFE" },
    
    -- INSTRUÇÃO 1: Fuga
    { name="4. INFO: Rota Fuga p/ Safe", type="info", content="Caminhe agora saindo da cave até pisar exatamente no SQM do seu Safe Spot." },
    
    { name="5. Script: Pausa 6s Chegada", type="script", content='print("Pausa 6s chegada"); wait(6000)' },
    { name="6. Label: AT_SAFE", type="label", content="AT_SAFE" },
    { name="7. Script: Loop Safe (Espera)", type="script", content='local phase = "UNKNOWN"; pcall(function() local f=io.open("zb_follower_phase.txt","r"); if f then phase=f:read("*a"); f:close() end end); local myNeed = false; pcall(function() local f=io.open("zb_follower_need.txt","r"); if f then if f:read("*a")=="1" then myNeed=true end; f:close() end end); if phase=="HUNTING" then CaveBot.GoTo("HUNT_IDLE") elseif phase=="REFILL" and myNeed then CaveBot.GoTo("FAZER_REFILL") else wait(1000); CaveBot.GoTo("AT_SAFE") end' },
    
    { name="8. Label: FAZER_REFILL", type="label", content="FAZER_REFILL" },
    
    -- INSTRUÇÃO 2: Loja
    { name="9. INFO: Fazer Rota Loja (Ida/Volta)", type="info", content="Caminhe do Safe até o NPC, faça os waypoints, adicione os extras (Sell/Deposit) e FAÇA A ROTA DE VOLTA ao Safe." },
    
    { name="10. Script: Voltei Loja", type="script", content='print("Terminei a loja. Voltando ao loop de safe."); CaveBot.GoTo("AT_SAFE")' },
    
    -- EXTRAS
    { name="EXTRA: Sell Loot", type="script", content='gameTalk("hi", 1)\nwait(1500)\ngameTalk("sell lootpouch", 12)\nwait(1500)\ngameTalk("sell lootpouch", 12)\ngameTalk("yes", 12)\nwait(5000)\ngameTalk("yes", 12)\nwait(3000)\ngameTalk("yes", 12)\nwait(5000)' },
    { name="EXTRA: Deposit All", type="script", content='gameTalk("hi", 1)\nwait(1500)\ngameTalk("deposite all", 12)\nwait(1500)\ngameTalk("yes", 12)\nwait(1500)\ngameTalk("yes", 12)\nwait(1500)' }
}

local handleX = PANEL_X
local handleY = FIRST_ROW_Y - ROW_SPACING

local hudHandleName = HUD.new(handleX, handleY, HANDLE_TEXT)
hudHandleName:setColor(HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3])
hudHandleName:setDraggable(true)
hudHandleName:setCallback(function() end)

local lastHX, lastHY = handleX, handleY

local function getAnchorPos()
    local tx, ty = hudGetPos(hudHandleName)
    local movedText = (tx ~= lastHX) or (ty ~= lastHY)
    lastHX, lastHY = tx, ty
    return tx, ty
end

for i, node in ipairs(builderNodes) do
    local offX = 0
    local offY = i * ROW_SPACING  

    local callback = function()
        injectAction(node.type, node.content)
        
        for j, hud in ipairs(huds) do
            if j == i then 
                hud.name:setColor(0, 255, 0) 
            else 
                if builderNodes[j].type == "info" then
                    hud.name:setColor(255, 215, 0)
                else
                    hud.name:setColor(255, 255, 255)
                end
            end
        end
        Timer.new("ColorReset" .. i, function() 
            if huds[i] then 
                if builderNodes[i].type == "info" then
                    huds[i].name:setColor(255, 215, 0)
                else
                    huds[i].name:setColor(255, 255, 255) 
                end
            end 
        end, 500, false)
    end

    local x = handleX + offX
    local y = handleY + offY
    local isInfo = (node.type == "info")
    local hudName = createTextHUD(x, y, node.name, callback, isInfo)
    huds[i] = { name = hudName, offX = offX, offY = offY }
end

local timerDrag = Timer.new("BuilderHUD_Drag", function()
    local ax, ay = getAnchorPos()
    for _, hud in ipairs(huds) do
        hud.name:setPos(ax + hud.offX, ay + hud.offY)
    end
end, 50)

print("[HUD FOLLOWER] Carregada! Siga os 10 passos para estruturar seu CaveBot.")