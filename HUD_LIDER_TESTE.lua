-- =========================================================
-- HUD BUILDER - CLEAN UI & FLUXO GUIADO v17
-- =========================================================

local PANEL_X = 25
local ROW_SPACING = 35 -- Ajustado para 30 para caber todos os 17 passos na tela confortavelmente
local FIRST_ROW_Y = 100          

local HANDLE_TEXT = "[ ARRASTAR AQUI ] Assistente de CaveBot"
local HANDLE_COLOR = {0, 255, 0} -- Verde

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
    -- Adicionamos colchetes e vários espaços em branco ao final para "esticar" a área do clique
    local textoEsticado = string.format("[ %s ]           ", text)
    
    local hudName = HUD.new(x, y, textoEsticado)
    
    -- Se for um botão de INFO, a cor será amarela
    if isInfo then
        hudName:setColor(255, 215, 0)
    else
        hudName:setColor(255, 255, 255)
    end
    hudName:setDraggable(false)
    hudName:setCallback(callback)
    return hudName
end

local huds = {}

-- Matriz Guiada: Intercalando injeção de código com instruções de caminhada
local builderNodes = {
    { name="1. Label: HUNT_START", type="label", content="HUNT_START" },
    { name="2. Script: Phase HUNTING", type="script", content='pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("HUNTING") f:close() end)' },
    
    -- INSTRUÇÃO 1
    { name="3. INFO: Fazer Rota da Cave", type="info", content="Caminhe agora e grave os waypoints de toda a sua rota de caça." },
    
    { name="4. Script: Check State", type="script", content='local lNeed, fNeed = false, false; pcall(function() local f=io.open("zb_leader_state.txt","r"); if f then local d=f:read("*a"); if d then if d:sub(1,1)=="1" then lNeed=true end; if d:sub(3,3)=="1" then fNeed=true end end; f:close() end end); if lNeed or fNeed then pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("WAIT_SAFE") f:close() end); CaveBot.GoTo("VOLTAR_SAFE") else CaveBot.GoTo("HUNT_START") end' },
    { name="5. Label: VOLTAR_SAFE", type="label", content="VOLTAR_SAFE" },
    
    -- INSTRUÇÃO 2 (Adicionada conforme seu pedido)
    { name="6. INFO: Fazer Rota p/ Safe", type="info", content="Caminhe agora saindo da cave até pisar exatamente no SQM do seu Safe Spot." },
    
    { name="7. Script: Pausa 6s Chegada", type="script", content='print("Pausa 6s chegada"); wait(6000); pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("WAIT_SAFE") f:close() end)' },
    { name="8. Label: AGUARDA_PARTY", type="label", content="AGUARDA_PARTY" },
    { name="9. Script: Máquina de Estado", type="script", content='local lNeed, fNeed, isR, isFlw = false, false, false, false\npcall(function() local f=io.open("zb_leader_state.txt","r"); if f then local d=f:read("*a"); if d then if d:sub(1,1)=="1" then lNeed=true end; if d:sub(3,3)=="1" then fNeed=true end; if d:sub(5,5)=="1" then isR=true end; if d:sub(7,7)=="1" then isFlw=true end end; f:close() end end)\nif not isR then\n    pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("REFILL") f:close() end)\n    print("Aguardando todos chegarem no Safe Spot...")\n    wait(2000)\n    CaveBot.GoTo("AGUARDA_PARTY")\nelseif lNeed and not fNeed then\n    pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("REFILL") f:close() end)\n    print("Só EU refilo. Followers ficam no Safe.")\n    CaveBot.GoTo("IR_REFILL")\nelseif lNeed and fNeed then\n    pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("REFILL") f:close() end)\n    print("Todos refilam. Partiu loja.")\n    CaveBot.GoTo("IR_REFILL")\nelseif fNeed then\n    pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("REFILL") f:close() end)\n    print("Aguardando Follower ir refilar...")\n    wait(2000)\n    CaveBot.GoTo("AGUARDA_PARTY")\nelseif not isFlw then\n    pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("HUNTING") f:close() end)\n    print("Aguardando Follower dar !follow...")\n    wait(2000)\n    CaveBot.GoTo("AGUARDA_PARTY")\nelse\n    pcall(function() local f=io.open("zb_leader_phase.txt","w") f:write("HUNTING") f:close() end)\n    print("Checklist OK! Descendo para hunt em 6s...")\n    wait(6000)\n    CaveBot.GoTo("VOLTAR_HUNT")\nend' },
    { name="10. Label: IR_REFILL", type="label", content="IR_REFILL" },
    
    -- INSTRUÇÃO 3 (Adicionada conforme seu pedido)
    { name="11. INFO: Fazer Rota Loja (Ida/Volta)", type="info", content="Caminhe do Safe até o NPC, faça os waypoints, adicione os extras (Sell/Deposit) e FAÇA A ROTA DE VOLTA ao Safe." },
    
    { name="12. Script: Voltei Loja", type="script", content='print("Voltei da Loja."); CaveBot.GoTo("AGUARDA_PARTY")' },
    { name="13. Label: VOLTAR_HUNT", type="label", content="VOLTAR_HUNT" },
    
    -- INSTRUÇÃO 4 (Bônus de completude)
    { name="14. INFO: Fazer Rota p/ Buraco da Cave", type="info", content="Caminhe do Safe Spot até o buraco/escada que desce para iniciar a Hunt." },
    
    { name="15. Script: Fim Voltar Hunt", type="script", content='CaveBot.GoTo("HUNT_START")' },
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
        
        -- Pisca verde ao clicar, mas retorna para amarelo se for INFO, ou branco se for botão normal
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

print("[HUD BUILDER] Fluxo Guiado ativado! Siga os passos amarelos para gravar suas rotas.")