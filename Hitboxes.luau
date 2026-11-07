local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local isExpanded = false
local MAX_DISTANCE = 500
local activeEntities = {}

local registerEntity, cleanupEntity, removeVisuals

local function isEntityDead(model)
    if not model or not model.Parent then return true end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("Model") then
                local h = child:FindFirstChildOfClass("Humanoid")
                if h and h.Health <= 0 then return true end
            end
        end
    else
        if humanoid.Health <= 0 then return true end
    end
    if model:GetAttribute("IsDead") == true or model:GetAttribute("Health") == 0 then return true end
    return false
end

removeVisuals = function(model)
    if _G.StealthHighlightCache[model] then
        pcall(function() _G.StealthHighlightCache[model]:Destroy() end)
        _G.StealthHighlightCache[model] = nil
    end
    if _G.StealthDrawingCache[model] then
        for _, obj in pairs(_G.StealthDrawingCache[model]) do
            pcall(function() obj:Destroy() end)
        end
        _G.StealthDrawingCache[model] = nil
    end
end

cleanupEntity = function(model, targetPart)
    if targetPart and _G.StealthHeadCache[targetPart] then
        pcall(function()
            targetPart.Size = _G.StealthHeadCache[targetPart]
            targetPart.Transparency = 0
            targetPart.CanCollide = true
        end)
        _G.StealthHeadCache[targetPart] = nil
    end
    removeVisuals(model)
end

local function findValidHeadPart(model)
    local headPart = nil
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and child.Name:lower() == "head" then
            headPart = child
            break
        end
    end
    if not headPart then
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") and child.Name:lower() ~= "humanoidrootpart" then
                headPart = child
                break
            end
        end
    end
    if not headPart and model:IsA("Model") and model.PrimaryPart and model.PrimaryPart:IsA("BasePart") and model.PrimaryPart.Name:lower() ~= "humanoidrootpart" then
        headPart = model.PrimaryPart
    end
    return headPart
end

local function getModelName(model)
    if not model then return "Unknown" end
    if model.Name == "NPCTemplateHumanV4" then
        local parentFolder = model.Parent
        if parentFolder and parentFolder:IsA("Folder") and parentFolder.Name == "The Colonel" then
            return "Colonel"
        end
    end
    local attrName = model:GetAttribute("DisplayName") or model:GetAttribute("NPCName") or model:GetAttribute("Name")
    if attrName and type(attrName) == "string" and attrName ~= "" then return attrName end
    
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("StringValue") and (child.Name:lower() == "displayname" or child.Name:lower() == "npcname" or child.Name:lower() == "name") then
            if child.Value and child.Value ~= "" then return child.Value end
        end
    end
    return model.Name
end

local function updateVisualsAndHitbox(model, targetPart, isAnimal)
    if not model or not model.Parent then 
        cleanupEntity(model, targetPart)
        return 
    end

    local data = activeEntities[model]
    if not data then
        registerEntity(model, isAnimal)
        data = activeEntities[model]
        if not data then return end
    end

    local mNameLower = model.Name:lower()
    if string.find(mNameLower, "horse") or string.find(mNameLower, "thigh") or string.find(mNameLower, "antlers") or string.find(mNameLower, "musketspringfield") then
        cleanupEntity(model, targetPart)
        removeVisuals(model)
        return
    end

    if isAnimal then
        if targetPart and _G.StealthHeadCache[targetPart] then
            pcall(function()
                targetPart.Size = _G.StealthHeadCache[targetPart]
                targetPart.Transparency = 0
                targetPart.CanCollide = true
            end)
        end
    else
        if not isExpanded or isEntityDead(model) then
            if targetPart and _G.StealthHeadCache[targetPart] then
                pcall(function()
                    targetPart.Size = _G.StealthHeadCache[targetPart]
                    targetPart.Transparency = 0
                    targetPart.CanCollide = true
                end)
            end
            removeVisuals(model)
            return
        end

        if targetPart and targetPart:IsA("BasePart") and targetPart.Name:lower() ~= "humanoidrootpart" then
            local pNameLower = targetPart.Name:lower()
            if string.find(pNameLower, "thigh") or string.find(pNameLower, "antlers") then
                removeVisuals(model)
                return
            end

            if not _G.StealthHeadCache[targetPart] then
                _G.StealthHeadCache[targetPart] = targetPart.Size
            end
            pcall(function()
                targetPart.Size = Vector3.new(5, 5, 5)
                targetPart.Transparency = 0.5
                targetPart.CanCollide = false
            end)
        else
            removeVisuals(model)
            return
        end
    end

    if isEntityDead(model) then
        removeVisuals(model)
        return
    end

    local camera = Workspace.CurrentCamera
    local character = Players.LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    
    local distance = 9999
    if rootPart and targetPart then
        distance = (rootPart.Position - targetPart.Position).Magnitude
    elseif camera and targetPart then
        distance = (camera.CFrame.Position - targetPart.Position).Magnitude
    end

    if distance > MAX_DISTANCE then
        removeVisuals(model)
        return
    end

    local highlight = _G.StealthHighlightCache[model]
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "StealthEspHighlight"
        highlight.Adornee = model
        highlight.Enabled = true
        highlight.FillTransparency = 1
        highlight.OutlineTransparency = 0.3
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        
        local container = (gethui and gethui()) or Workspace
        local success = pcall(function() highlight.Parent = container end)
        if not success then highlight.Parent = model end
        _G.StealthHighlightCache[model] = highlight
    else
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    end

    local drawings = _G.StealthDrawingCache[model]
    if not drawings then
        local nameObj = Drawing.new("Text")
        nameObj.Visible = false; nameObj.Center = true; nameObj.Outline = true; nameObj.Font = Drawing.Fonts.System
        local infoObj = Drawing.new("Text")
        infoObj.Visible = false; infoObj.Center = true; infoObj.Outline = true; infoObj.Font = Drawing.Fonts.System
        local hbOutline = Drawing.new("Square")
        hbOutline.Visible = false; hbOutline.Filled = false; hbOutline.Thickness = 1; hbOutline.Color = Color3.fromRGB(15, 15, 15)
        local hbFill = Drawing.new("Square")
        hbFill.Visible = false; hbFill.Filled = true

        drawings = { NameText = nameObj, InfoText = infoObj, HealthBarOutline = hbOutline, HealthBarFill = hbFill, SmoothHealth = 100 }
        _G.StealthDrawingCache[model] = drawings
    end

    if targetPart and camera then
        local cframe, size = model:GetBoundingBox()
        local topWorldPos = (cframe + Vector3.new(0, size.Y / 2, 0)).Position
        local bottomWorldPos = (cframe - Vector3.new(0, size.Y / 2, 0)).Position

        local topVector, topOnScreen = camera:WorldToViewportPoint(topWorldPos)
        local bottomVector, bottomOnScreen = camera:WorldToViewportPoint(bottomWorldPos)

        if topOnScreen or bottomOnScreen then
            local currentHealth = 100
            local maxHealth = data.MaxHealth or 100
            local foundCustomHealth = false

            for _, desc in ipairs(model:GetChildren()) do
                if desc:IsA("NumberValue") and (desc.Name:lower() == "health" or desc.Name:lower() == "hp") then
                    currentHealth = desc.Value
                    foundCustomHealth = true
                    break
                end
            end

            if not foundCustomHealth then
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    currentHealth = humanoid.Health
                    if not data.MaxHealth then data.MaxHealth = humanoid.MaxHealth end
                    maxHealth = data.MaxHealth
                end
            else
                if not data.MaxHealth and currentHealth > 0 then data.MaxHealth = currentHealth end
                maxHealth = data.MaxHealth or 100
            end

            drawings.SmoothHealth = drawings.SmoothHealth + (currentHealth - drawings.SmoothHealth) * 0.05
            local roundedDist = math.floor(distance)
            local healthPercent = math.clamp(drawings.SmoothHealth / maxHealth, 0, 1)

            local scaleFactor = math.clamp(1 - (distance / MAX_DISTANCE), 0.35, 1.0)
            local dynamicNameSize = math.clamp(math.floor(13 * scaleFactor + 2), 9, 13)
            local dynamicInfoSize = math.clamp(math.floor(10 * scaleFactor + 2), 8, 10)

            local nameText = drawings.NameText
            if nameText then
                nameText.Text = getModelName(model)
                nameText.Size = dynamicNameSize
                nameText.Position = Vector2.new(topVector.X, topVector.Y - (18 * scaleFactor))
                if healthPercent > 0.5 then
                    local t = (healthPercent - 0.5) * 2
                    nameText.Color = Color3.fromRGB(math.floor(255 * (1 - t)), 255, 0)
                else
                    local t = healthPercent * 2
                    nameText.Color = Color3.fromRGB(255, math.floor(255 * t), 0)
                end
                nameText.Visible = true
            end

            local hbOutline = drawings.HealthBarOutline
            local hbFill = drawings.HealthBarFill
            if hbOutline and hbFill then
                local barWidth = 46
                local barHeight = 4
                local barX = bottomVector.X - (barWidth / 2)
                local barY = bottomVector.Y + 8

                hbOutline.Size = Vector2.new(barWidth + 2, barHeight + 2)
                hbOutline.Position = Vector2.new(barX - 1, barY - 1)
                hbOutline.Visible = true

                local currentWidth = math.clamp(math.floor(barWidth * healthPercent), 0, barWidth)
                hbFill.Size = Vector2.new(currentWidth, barHeight)
                hbFill.Position = Vector2.new(barX, barY)
                
                if healthPercent > 0.5 then
                    local t = (healthPercent - 0.5) * 2
                    hbFill.Color = Color3.fromRGB(math.floor(255 * (1 - t)), 255, 0)
                else
                    local t = healthPercent * 2
                    hbFill.Color = Color3.fromRGB(255, math.floor(255 * t), 0)
                end
                hbFill.Visible = true

                local infoText = drawings.InfoText
                if infoText then
                    infoText.Text = string.format("[%d studs]", roundedDist)
                    infoText.Size = dynamicInfoSize
                    infoText.Position = Vector2.new(bottomVector.X, barY + barHeight + 4)
                    infoText.Color = Color3.fromRGB(200, 200, 200)
                    infoText.Visible = true
                end
            end
        else
            if drawings.NameText then drawings.NameText.Visible = false end
            if drawings.InfoText then drawings.InfoText.Visible = false end
            if drawings.HealthBarOutline then drawings.HealthBarOutline.Visible = false end
            if drawings.HealthBarFill then drawings.HealthBarFill.Visible = false end
        end
    else
        if drawings.NameText then drawings.NameText.Visible = false end
        if drawings.InfoText then drawings.InfoText.Visible = false end
        if drawings.HealthBarOutline then drawings.HealthBarOutline.Visible = false end
        if drawings.HealthBarFill then drawings.HealthBarFill.Visible = false end
    end
end

local function isValidNPCFolder(folder)
    if not folder or not folder:IsA("Folder") then return false end
    local nameLower = folder.Name:lower()
    return (nameLower == "folder" or string.find(nameLower, "soldier") or string.find(nameLower, "colonel"))
end

registerEntity = function(model, isAnimal)
    if not model or not model:IsA("Model") or activeEntities[model] then return end
    if model.Name:lower() == "collisionmodel" then return end

    local mNameLower = model.Name:lower()
    if string.find(mNameLower, "horse") or string.find(mNameLower, "thigh") or string.find(mNameLower, "antlers") then return end

    local entitiesFolder = Workspace:FindFirstChild("WORKSPACE_Entities")
    if entitiesFolder then
        local animalsFolder = entitiesFolder:FindFirstChild("Animals")
        local npcsFolder = entitiesFolder:FindFirstChild("NPCs")
        local validSource = false
        
        if animalsFolder and model:IsDescendantOf(animalsFolder) then validSource = true end
        if npcsFolder and model:IsDescendantOf(npcsFolder) then
            local current = model.Parent
            while current and current ~= npcsFolder and current ~= Workspace do
                if current:IsA("Folder") and isValidNPCFolder(current) then
                    validSource = true
                    break
                end
                current = current.Parent
            end
            if not validSource and model.Parent and isValidNPCFolder(model.Parent) then validSource = true end
        end
        if not validSource then return end
    end

    local targetPart = findValidHeadPart(model)
    if not targetPart or targetPart.Name:lower() == "humanoidrootpart" then return end
    if string.find(targetPart.Name:lower(), "thigh") or string.find(targetPart.Name:lower(), "antlers") then return end

    activeEntities[model] = { Part = targetPart, IsAnimal = isAnimal }

    local ancestryConn
    ancestryConn = model.AncestryChanged:Connect(function(_, parent)
        if not parent then
            cleanupEntity(model, targetPart)
            activeEntities[model] = nil
            if ancestryConn then ancestryConn:Disconnect() end
        end
    end)
    table.insert(_G.StealthConnections, ancestryConn)
end

local function scanTargetContainer(container, isAnimal)
    if not container then return end
    local function recursiveScan(parentObj)
        for _, child in ipairs(parentObj:GetChildren()) do
            if child:IsA("Folder") then
                recursiveScan(child)
            elseif child:IsA("Model") then
                if child.Name:lower() ~= "collisionmodel" then registerEntity(child, isAnimal) end
            end
        end
    end
    recursiveScan(container)
end

local function runInitialScan()
    activeEntities = {}
    local entitiesFolder = Workspace:FindFirstChild("WORKSPACE_Entities")
    if entitiesFolder then
        local animalsFolder = entitiesFolder:FindFirstChild("Animals")
        if animalsFolder then scanTargetContainer(animalsFolder, true) end
        
        local npcsFolder = entitiesFolder:FindFirstChild("NPCs")
        if npcsFolder then
            for _, child in ipairs(npcsFolder:GetChildren()) do
                if child:IsA("Folder") and isValidNPCFolder(child) then scanTargetContainer(child, false) end
            end
        end
    end
end

local function initializeFolderListeners()
    local entitiesFolder = Workspace:FindFirstChild("WORKSPACE_Entities")
    if not entitiesFolder then return end

    local animalsFolder = entitiesFolder:FindFirstChild("Animals")
    if animalsFolder then
        table.insert(_G.StealthConnections, animalsFolder.ChildAdded:Connect(function(child)
            if child:IsA("Folder") then scanTargetContainer(child, true)
            elseif child:IsA("Model") and child.Name:lower() ~= "collisionmodel" then
                task.defer(function() if child and child.Parent then registerEntity(child, true) end end)
            end
        end))
        table.insert(_G.StealthConnections, animalsFolder.ChildRemoved:Connect(function(child)
            if child:IsA("Model") and activeEntities[child] then
                cleanupEntity(child, activeEntities[child].Part)
                activeEntities[child] = nil
            end
        end))
    end

    local npcsFolder = entitiesFolder:FindFirstChild("NPCs")
    if npcsFolder then
        table.insert(_G.StealthConnections, npcsFolder.ChildAdded:Connect(function(child)
            if child:IsA("Folder") and isValidNPCFolder(child) then
                scanTargetContainer(child, false)
                table.insert(_G.StealthConnections, child.DescendantAdded:Connect(function(descendant)
                    if descendant:IsA("Model") and descendant.Name:lower() ~= "collisionmodel" then
                        task.defer(function() if descendant and descendant.Parent then registerEntity(descendant, false) end end)
                    end
                end))
            elseif child:IsA("Model") and child.Name:lower() ~= "collisionmodel" then
                task.defer(function() if child and child.Parent then registerEntity(child, false) end end)
            end
        end))
        
        for _, child in ipairs(npcsFolder:GetChildren()) do
            if child:IsA("Folder") and isValidNPCFolder(child) then
                table.insert(_G.StealthConnections, child.DescendantAdded:Connect(function(descendant)
                    if descendant:IsA("Model") and descendant.Name:lower() ~= "collisionmodel" then
                        task.defer(function() if descendant and descendant.Parent then registerEntity(descendant, false) end end)
                    end
                end))
            end
        end

        table.insert(_G.StealthConnections, npcsFolder.ChildRemoved:Connect(function(child)
            if child:IsA("Model") and activeEntities[child] then
                cleanupEntity(child, activeEntities[child].Part)
                activeEntities[child] = nil
            end
        end))
    end
end
initializeFolderListeners()

local function toggleHitboxes()
    isExpanded = not isExpanded
    if not isExpanded then
        if _G.StealthHeadCache then
            for part, originalSize in pairs(_G.StealthHeadCache) do
                if part and part.Parent then
                    pcall(function() part.Size = originalSize; part.Transparency = 0; part.CanCollide = true end)
                end
            end
            _G.StealthHeadCache = {}
        end
        if _G.StealthHighlightCache then
            for _, highlight in pairs(_G.StealthHighlightCache) do if highlight then pcall(function() highlight:Destroy() end) end end
            _G.StealthHighlightCache = {}
        end
        if _G.StealthDrawingCache then
            for _, drawings in pairs(_G.StealthDrawingCache) do
                if drawings then for _, obj in pairs(drawings) do pcall(function() obj:Destroy() end) end end
            end
            _G.StealthDrawingCache = {}
        end
    else
        runInitialScan()
    end
end

local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Z then
        toggleHitboxes()
    end
end)
table.insert(_G.StealthConnections, keyConn)

local renderConn = RunService.RenderStepped:Connect(function()
    if not _G.StealthWorkerRunning or not isExpanded then return end
    for model, data in pairs(activeEntities) do
        if not model or not model.Parent or isEntityDead(model) then
            cleanupEntity(model, data.Part)
            activeEntities[model] = nil
        else
            updateVisualsAndHitbox(model, data.Part, data.IsAnimal)
        end
    end
end)
table.insert(_G.StealthConnections, renderConn)
