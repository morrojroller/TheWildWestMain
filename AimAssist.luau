local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local aimAssistActive = false
local fovRadius = 150 -- Customizable FOV radius

-- Global or module-level tracking for cleanup integration
_G.StealthAimAssistDrawings = _G.StealthAimAssistDrawings or {}

-- Safely create FOV Circle
local fovCircle
pcall(function()
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible = false
    fovCircle.Radius = fovRadius
    fovCircle.Filled = false
    fovCircle.Thickness = 1.5
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
    fovCircle.Transparency = 0.7
    table.insert(_G.StealthAimAssistDrawings, fovCircle)
end)

-- Safely create Target Dot
local targetDot
pcall(function()
    targetDot = Drawing.new("Circle")
    targetDot.Visible = false
    targetDot.Radius = 4
    targetDot.Filled = true
    targetDot.Color = Color3.fromRGB(255, 0, 0)
    targetDot.Transparency = 1
    table.insert(_G.StealthAimAssistDrawings, targetDot)
end)

table.insert(_G.StealthAimAssistDrawings, fovCircle)
table.insert(_G.StealthAimAssistDrawings, targetDot)

local CONFIG = {
    Players = true,
    Animals = true,
    NPCs = true
}

local function clearAimAssistVisuals()
    if fovCircle then fovCircle.Visible = false end
    if targetDot then targetDot.Visible = false end
end

-- Priority target selection: Head -> Neck -> Torso (UpperTorso/Torso/HumanoidRootPart)
local function getPriorityAimPosition(model)
    if not model then return nil end
    local head = model:FindFirstChild("Head")
    local neck = model:FindFirstChild("Neck")
    local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
    
    if head then
        return head.Position - Vector3.new(0, 0.5, 0)
    elseif neck then
        return neck.Position
    elseif torso then
        return torso.Position
    end
    return nil
end

local function getTargetPosition(origin)
    if not aimAssistActive or not _G.StealthWorkerRunning then
        clearAimAssistVisuals()
        return nil
    end

    local camera = Workspace.CurrentCamera
    if not camera then 
        warn("[AimAssist Debug]: Workspace.CurrentCamera is missing or nil!")
        return nil 
    end

    local mousePos = UserInputService:GetMouseLocation()
    fovCircle.Position = mousePos
    fovCircle.Visible = aimAssistActive

    local character = LocalPlayer.Character
    local hrpChar = character and character:FindFirstChild("HumanoidRootPart")
    local charPos = hrpChar and hrpChar.Position or origin
    local charLook = hrpChar and hrpChar.CFrame.LookVector or camera.CFrame.LookVector

    local Entities = Workspace:FindFirstChild("WORKSPACE_Entities")
    if not Entities then
        warn("[AimAssist Debug]: Workspace.WORKSPACE_Entities folder could not be found!")
        targetDot.Visible = false
        return nil
    end

    local PlayersFolder = Entities:FindFirstChild("Players")
    local AnimalsFolder = Entities:FindFirstChild("Animals")
    local NPCsFolder = Entities:FindFirstChild("NPCs")

    local bestScore = math.huge
    local targetPos = nil
    local bestScreenPos = nil

    local function processTarget(part, aimPosition)
        if not part or not aimPosition then 
            warn("[AimAssist Debug]: processTarget received a nil part or aimPosition!")
            return 
        end
        local toTarget = (aimPosition - charPos).Unit
        if charLook:Dot(toTarget) > 0 then
            local screenPos, onScreen = camera:WorldToScreenPoint(aimPosition)
            if onScreen and screenPos.Z > 0 then
                local screenVec = Vector2.new(screenPos.X, screenPos.Y)
                local distToMouse = (screenVec - mousePos).Magnitude
                
                -- Must be inside the FOV circle radius
                if distToMouse <= fovRadius then
                    local distToPlayer = (aimPosition - charPos).Magnitude
                    local score = distToMouse + (distToPlayer * 0.05)
                    
                    if score < bestScore then
                        bestScore = score
                        targetPos = aimPosition
                        bestScreenPos = screenVec
                    end
                end
            end
        end
    end

    if CONFIG.Players and PlayersFolder then
        for _, model in ipairs(PlayersFolder:GetChildren()) do
            if model ~= character and model:IsA("Model") then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local aimPos = getPriorityAimPosition(model) or hrp.Position
                    processTarget(hrp, aimPos)
                end
            end
        end
    end

    if CONFIG.Animals and AnimalsFolder then
        for _, model in ipairs(AnimalsFolder:GetChildren()) do
            if model:IsA("Model") then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local aimPos = getPriorityAimPosition(model) or hrp.Position
                    processTarget(hrp, aimPos)
                end
            end
        end
    end

    if CONFIG.NPCs and NPCsFolder then
        for _, descendant in ipairs(NPCsFolder:GetDescendants()) do
            if descendant:IsA("Model") then
                local hrp = descendant:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local aimPos = getPriorityAimPosition(descendant) or hrp.Position
                    processTarget(hrp, aimPos)
                end
            end
        end
    end

    if targetPos and bestScreenPos then
        targetDot.Position = bestScreenPos
        targetDot.Visible = true
    else
        targetDot.Visible = false
    end

    return targetPos
end

-- RenderStepped to update FOV circle position with mouse movement
local renderConn = RunService.RenderStepped:Connect(function()
    if not aimAssistActive or not _G.StealthWorkerRunning then
        clearAimAssistVisuals()
        return
    end
    fovCircle.Position = UserInputService:GetMouseLocation()
    fovCircle.Visible = true
end)
table.insert(_G.StealthConnections, renderConn)

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

-- Hook ProjectileHandler (Silent Aim Spread Only)
local success, ProjectileHandler = pcall(function()
    return require(ReplicatedStorage:WaitForChild("SharedModules", 5):WaitForChild("World", 5):WaitForChild("ProjectileHandler", 5))
end)

if not success or not ProjectileHandler then
    warn("[AimAssist Debug]: Failed to require ProjectileHandler module! Path may have changed.")
end

if success and ProjectileHandler then
    if not ProjectileHandler._OriginalGetSpread then
        ProjectileHandler._OriginalGetSpread = ProjectileHandler.GetProjectileSpread
    end

    ProjectileHandler.GetProjectileSpread = function(self, projectileType, projectileParams, info, numProjectiles)
        if aimAssistActive and info and info.origin then
            local targetPos = getTargetPosition(info.origin)
            if targetPos then
                local newDir = (targetPos - info.origin).Unit
                info.direction = newDir
            end
        end
        if ProjectileHandler._OriginalGetSpread then
            return ProjectileHandler._OriginalGetSpread(self, projectileType, projectileParams, info, numProjectiles)
        else
        	warn("[AimAssist Debug]: _OriginalGetSpread is missing!")
        end
    end
end
