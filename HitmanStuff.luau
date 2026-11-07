local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local hitmanActive = false
local trackedTargetName = nil
local currentHitmanModel = nil

-- Ensure global safety flags exist
_G.StealthWorkerRunning = true
_G.StealthConnections = _G.StealthConnections or {}

-- Cleanup helpers for Hitman visuals
local function clearHitmanVisuals()
    if _G.StealthHitmanHighlightCache then
        for model, hl in pairs(_G.StealthHitmanHighlightCache) do
            pcall(function() hl:Destroy() end)
        end
        _G.StealthHitmanHighlightCache = {}
    end
    if _G.StealthHitmanDrawingCache then
        for model, drawings in pairs(_G.StealthHitmanDrawingCache) do
            if drawings then
                for _, obj in pairs(drawings) do
                    pcall(function() obj:Destroy() end)
                end
            end
        end
        _G.StealthHitmanDrawingCache = {}
    end
    currentHitmanModel = nil
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

-- Clean strings to prevent whitespace/formatting mismatch
local function cleanString(str)
    if not str then return "" end
    -- Remove non-alphanumeric/spaces or trim trailing spaces
    return string.match(str, "^%s*(.-)%s*$"):lower()
end

local function findNPCByName(targetName)
    if not targetName or string.lower(targetName):find("musketspringfield") then return nil end
    local cleanTarget = cleanString(targetName)
    if cleanTarget == "" then return nil end

    local entitiesFolder = Workspace:FindFirstChild("WORKSPACE_Entities")
    if not entitiesFolder then return nil end
    local npcsFolder = entitiesFolder:FindFirstChild("NPCs")
    if not npcsFolder then return nil end

    local function searchContainer(parentObj)
        for _, child in ipairs(parentObj:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                -- Check if this child itself is the target model
                if child:IsA("Model") then
                    local mName = cleanString(getModelName(child))
                    if mName == cleanTarget or mName:find(cleanTarget) then
                        return child
                    end
                end
                -- Recurse deeper
                local found = searchContainer(child)
                if found then return found end
            end
        end
        return nil
    end

    return searchContainer(npcsFolder)
end

-- Render loop for Hitman target
local hitmanRenderConn = RunService.RenderStepped:Connect(function()
    if not hitmanActive or not _G.StealthWorkerRunning then
        clearHitmanVisuals()
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    if not currentHitmanModel or not currentHitmanModel.Parent then
        if trackedTargetName and trackedTargetName ~= "" then
            currentHitmanModel = findNPCByName(trackedTargetName)
        else
            currentHitmanModel = nil
        end
    end

    if not currentHitmanModel then
        clearHitmanVisuals()
        return
    end

    -- Update or create highlight
    _G.StealthHitmanHighlightCache = _G.StealthHitmanHighlightCache or {}
    local highlight = _G.StealthHitmanHighlightCache[currentHitmanModel]
    if not highlight then
        clearHitmanVisuals()
        highlight = Instance.new("Highlight")
        highlight.Name = "HitmanTargetHighlight"
        highlight.Adornee = currentHitmanModel
        highlight.Enabled = true
        highlight.FillTransparency = 0.5
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineTransparency = 0
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        
        local container = (gethui and gethui()) or Workspace
        pcall(function() highlight.Parent = container end)
        if not highlight.Parent then highlight.Parent = currentHitmanModel end
        _G.StealthHitmanHighlightCache[currentHitmanModel] = highlight
    end

    -- Update or create drawing for name overhead
    _G.StealthHitmanDrawingCache = _G.StealthHitmanDrawingCache or {}
    local drawings = _G.StealthHitmanDrawingCache[currentHitmanModel]
    if not drawings then
        local nameObj = Drawing.new("Text")
        nameObj.Visible = false
        nameObj.Center = true
        nameObj.Outline = true
        nameObj.OutlineColor = Color3.fromRGB(0, 0, 0)
        nameObj.Font = Drawing.Fonts.System
        nameObj.Size = 18
        nameObj.Color = Color3.fromRGB(255, 50, 50)
        
        drawings = { NameText = nameObj }
        _G.StealthHitmanDrawingCache[currentHitmanModel] = drawings
    end

    local cframe, size = currentHitmanModel:GetBoundingBox()
    local topWorldPos = (cframe + Vector3.new(0, size.Y / 2 + 1, 0)).Position
    local vector, onScreen = camera:WorldToViewportPoint(topWorldPos)

    if onScreen then
        local nameText = drawings.NameText
        if nameText then
            nameText.Text = "★ TARGET: " .. getModelName(currentHitmanModel) .. " ★"
            nameText.Position = Vector2.new(vector.X, vector.Y)
            nameText.Visible = true
        end
    else
        if drawings.NameText then drawings.NameText.Visible = false end
    end
end)
table.insert(_G.StealthConnections, hitmanRenderConn)

-- Setup UI tracking for TargetName text changes
local function setupHitmanTracker()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not playerGui then return end

    local hitmanGamepass = playerGui:WaitForChild("HitmanGamepass", 5)
    if not hitmanGamepass then return end

    local hitmanInfo = hitmanGamepass:WaitForChild("HitmanInfo", 5)
    if not hitmanInfo then return end

    local container = hitmanInfo:WaitForChild("Container", 5)
    if not container then return end

    local body = container:WaitForChild("Body", 5)
    if not body then return end

    local targetNameLabel = body:WaitForChild("TargetName", 5)
    if targetNameLabel and targetNameLabel:IsA("TextLabel") then
        local function updateTarget()
            trackedTargetName = targetNameLabel.Text
            currentHitmanModel = findNPCByName(trackedTargetName)
            if not currentHitmanModel then
                clearHitmanVisuals()
            end
        end

        updateTarget()
        table.insert(_G.StealthConnections, targetNameLabel:GetPropertyChangedSignal("Text"):Connect(updateTarget))
    end
end

-- Listen for dynamic spawning/despawning of NPCs
local entitiesFolder = Workspace:WaitForChild("WORKSPACE_Entities", 5)
if entitiesFolder then
    local npcsFolder = entitiesFolder:WaitForChild("NPCs", 5)
    if npcsFolder then
        local function monitorFolder(folder)
            table.insert(_G.StealthConnections, folder.ChildAdded:Connect(function(child)
                if hitmanActive and trackedTargetName and not currentHitmanModel then
                    task.defer(function()
                        if child:IsA("Model") and (cleanString(getModelName(child)) == cleanString(trackedTargetName)) then
                            currentHitmanModel = child
                        end
                    end)
                end
                if child:IsA("Folder") or child:IsA("Model") then
                    monitorFolder(child)
                end
            end))
            table.insert(_G.StealthConnections, folder.ChildRemoved:Connect(function(child)
                if child == currentHitmanModel then
                    clearHitmanVisuals()
                end
            end))
        end

        monitorFolder(npcsFolder)
    end
end

-- Toggle Hitman feature via key '9'
local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Nine then
        hitmanActive = not hitmanActive
        if hitmanActive then
            setupHitmanTracker()
            print("[WWHE]: Hitman Tracker Enabled")
        else
            clearHitmanVisuals()
            print("[WWHE]: Hitman Tracker Disabled")
        end
    end
end)
table.insert(_G.StealthConnections, keyConn)
