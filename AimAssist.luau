local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local aimAssistActive = false
local fovRadius = 350 -- Customizable FOV radius
local aliveCheck = true -- Added alive check, defaulted to true

-- Global tracking for cleanup integration
_G.StealthAimAssistDrawings = _G.StealthAimAssistDrawings or {}
_G.StealthConnections = _G.StealthConnections or {}

-- Load AllGunData and Prediction modules
local AllGunData = loadstring(game:HttpGet("https://raw.githubusercontent.com/morrojroller/TheWildWestMain/main/AllGunData.luau"))()
local Prediction = loadstring(game:HttpGet("https://raw.githubusercontent.com/morrojroller/TheWildWestMain/main/Prediction.luau"))()

-- Initialize Prediction with Gun Data and start weapon monitoring
Prediction.SetGunData(AllGunData)
Prediction.StartWeaponMonitor()

-- Safely create Drawing objects with nil-protection
local fovCircle
pcall(function()
    if Drawing and Drawing.new then
        fovCircle = Drawing.new("Circle")
        fovCircle.Visible = false
        fovCircle.Radius = fovRadius
        fovCircle.Filled = false
        fovCircle.Thickness = 1.5
        fovCircle.Color = Color3.fromRGB(255, 255, 255)
        fovCircle.Transparency = 0.7
        table.insert(_G.StealthAimAssistDrawings, fovCircle)
    end
end)

local targetDot
pcall(function()
    if Drawing and Drawing.new then
        targetDot = Drawing.new("Circle")
        targetDot.Visible = false
        targetDot.Radius = 4
        targetDot.Filled = true
        targetDot.Color = Color3.fromRGB(255, 0, 0)
        targetDot.Transparency = 1
        table.insert(_G.StealthAimAssistDrawings, targetDot)
    end
end)

-- Cached Entity Registries, Head Caches, & Original Folder Tracking
local cachedEntities = {}
local headKeyCache = {}
local entityOriginalFolders = {}

local CONFIG = {
    Players = true,
    Animals = true,
    NPCs = true
}

local function getValidHeadPart(model)
    if not model then return nil end
    local cachedKey = headKeyCache[model]
    if cachedKey then
        local found = model:FindFirstChild(cachedKey)
        if found and found:IsA("BasePart") then return found end
    end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            local cName = child.Name:lower()
            if cName == "head" then
                headKeyCache[model] = child.Name
                return child
            end
        end
    end
    return nil
end

local function getPriorityAimPosition(model)
    if not model then return nil end
    local head = getValidHeadPart(model)
    local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
    
    if head then
        return head.Position, head
    elseif torso then
        return torso.Position, nil
    end
    return nil, nil
end

local function clearAimAssistVisuals()
    if fovCircle then fovCircle.Visible = false end
    if targetDot then targetDot.Visible = false end
end

-- Setup and populate complete folder hierarchies
local entitiesFolder = Workspace:WaitForChild("WORKSPACE_Entities", 5)

if entitiesFolder then
    local playersFolder = entitiesFolder:FindFirstChild("Players")
    local animalsFolder = entitiesFolder:FindFirstChild("Animals")
    local npcsFolder = entitiesFolder:FindFirstChild("NPCs")

    local function registerEntity(model, parentFolder)
        if model:IsA("Model") and model.Name ~= LocalPlayer.Name then
            cachedEntities[model] = true
            entityOriginalFolders[model] = parentFolder
        end
    end

    local function unregisterEntity(model)
        cachedEntities[model] = nil
        headKeyCache[model] = nil
        entityOriginalFolders[model] = nil
        Prediction.CleanupTarget(model)
    end

    local monitorContainer

    monitorContainer = function(container)
        if not container then return end

        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                if child:IsA("Model") then
                    registerEntity(child, container)
                end
                monitorContainer(child)
            end
        end

        table.insert(_G.StealthConnections, container.ChildAdded:Connect(function(child)
            task.defer(function()
                if child and child.Parent then
                    if child:IsA("Model") then
                        registerEntity(child, container)
                    end
                    if child:IsA("Folder") or child:IsA("Model") then
                        monitorContainer(child)
                    end
                end
            end)
        end))

        table.insert(_G.StealthConnections, container.ChildRemoved:Connect(function(child)
            if child:IsA("Model") then
                unregisterEntity(child)
            end
        end))
    end

    if CONFIG.Players and playersFolder then
        monitorContainer(playersFolder)
    end

    if CONFIG.Animals and animalsFolder then
        monitorContainer(animalsFolder)
    end

    if CONFIG.NPCs and npcsFolder then
        monitorContainer(npcsFolder)
    end
end

-- Frame-locked RenderStepped calculation loop with ballistic prediction integration
local currentBestAimPos = nil

RunService.RenderStepped:Connect(function()
    if not aimAssistActive or not _G.StealthWorkerRunning then
        clearAimAssistVisuals()
        currentBestAimPos = nil
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then 
        clearAimAssistVisuals()
        currentBestAimPos = nil
        return 
    end

    local mousePos = UserInputService:GetMouseLocation()
    if fovCircle then
        fovCircle.Position = mousePos
        fovCircle.Visible = true
    end

    local character = LocalPlayer.Character
    local hrpChar = character and character:FindFirstChild("HumanoidRootPart")
    local charPos = hrpChar and hrpChar.Position or camera.CFrame.Position
    local charLook = hrpChar and hrpChar.CFrame.LookVector or camera.CFrame.LookVector

    local bestScore = math.huge
    local bestTargetPos = nil
    local bestScreenVec = nil
    local bestDistance = 0

    for model, _ in pairs(cachedEntities) do
        if model and model.Parent then
            -- Alive Check: if enabled, check if they are "dead" (moved out of their original folder)
            if aliveCheck then
                local originalFolder = entityOriginalFolders[model]
                if not originalFolder or model.Parent ~= originalFolder then
                    unregisterEntity(model)
                    continue
                end
            end

            if string.find(model.Name:lower(), "musketspringfield") then
                continue
            end
            local basePos, headPart = getPriorityAimPosition(model)
            if basePos then
                local distToPlayer = (basePos - charPos).Magnitude
                
                -- Apply Prediction module to calculate intercept position based on target velocity, gravity, and weapon projectile speed
                local predictedPos = Prediction.GetPredictedPosition(charPos, model, basePos)
                
                local scaleFactor = math.clamp(1 - (distToPlayer / 500), 0.2, 1.0)
                local adjustedAimPos = predictedPos
                if headPart then
                    adjustedAimPos = predictedPos - Vector3.new(0, 0.25 * scaleFactor, 0)
                end

                local toTarget = (adjustedAimPos - charPos).Unit
                if charLook:Dot(toTarget) > 0 then
                    local screenPos, onScreen = camera:WorldToScreenPoint(adjustedAimPos)
                    if onScreen and screenPos.Z > 0 then
                        local screenVec = Vector2.new(screenPos.X, screenPos.Y)
                        local distToMouse = (screenVec - mousePos).Magnitude
                        
                        if distToMouse <= fovRadius then
                            local score = distToMouse + (distToPlayer * 0.05)
                            
                            if score < bestScore then
                                bestScore = score
                                bestTargetPos = adjustedAimPos
                                bestScreenVec = screenVec
                                bestDistance = distToPlayer
                            end
                        end
                    end
                end
            end
        else
            unregisterEntity(model)
        end
    end

    currentBestAimPos = bestTargetPos

    if bestTargetPos and bestScreenVec and targetDot then
        targetDot.Position = bestScreenVec
        local dotScale = math.clamp(1 - (bestDistance / 400), 0.4, 1.0)
        targetDot.Radius = math.clamp(math.floor(4 * dotScale), 2, 4)
        targetDot.Visible = true
    else
        if targetDot then targetDot.Visible = false end
    end
end)

-- Toggle Aim Assist via CapsLock
local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.CapsLock then
        aimAssistActive = not aimAssistActive
        if not aimAssistActive then
            clearAimAssistVisuals()
            print("[WWHE]: Aim Assist Disabled")
        else
            print("[WWHE]: Aim Assist Enabled")
        end
    end
end)
table.insert(_G.StealthConnections, keyConn)

-- Hook ProjectileHandler (Silent Aim Spread redirection)
local success, ProjectileHandler = pcall(function()
    return require(ReplicatedStorage:WaitForChild("SharedModules", 5):WaitForChild("World", 5):WaitForChild("ProjectileHandler", 5))
end)

if success and ProjectileHandler then
    if not ProjectileHandler._OriginalGetSpread then
        ProjectileHandler._OriginalGetSpread = ProjectileHandler.GetProjectileSpread
    end
    if not ProjectileHandler._OriginalInitProjectiles then
        ProjectileHandler._OriginalInitProjectiles = ProjectileHandler.InitProjectiles
    end

    ProjectileHandler.GetProjectileSpread = function(self, projectileType, projectileParams, info, numProjectiles)
        if aimAssistActive and info and info.origin and currentBestAimPos then
            info.direction = (currentBestAimPos - info.origin).Unit
        end
        return ProjectileHandler._OriginalGetSpread(self, projectileType, projectileParams, info, numProjectiles)
    end

    ProjectileHandler.InitProjectiles = function(self, projectileType, projectileParams, info, callback)
        if aimAssistActive and info and info.origin and currentBestAimPos then
            info.direction = (currentBestAimPos - info.origin).Unit
        end
        return ProjectileHandler._OriginalInitProjectiles(self, projectileType, projectileParams, info, callback)
    end
end
