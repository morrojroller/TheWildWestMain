-- WWHE GunMod Module (Forcefield Overlay / Gun Effects)
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local gunForcefieldActive = false
local targetEntityPath = Workspace:WaitForChild("WORKSPACE_Entities", 5) 
and Workspace.WORKSPACE_Entities:WaitForChild("Players", 5) 
and Workspace.WORKSPACE_Entities.Players:WaitForChild("fodragonman", 5)

if targetEntityPath then
    local activeGunOverlay = nil
    local trackedGunModel = nil
    local gunSyncedParts = {}
    local gunRenderConn = nil

    local function isGunModel(model)
        if not model or not model:IsA("Model") then return false end
        for _, child in ipairs(model:GetChildren()) do
            local cName = child.Name:lower()
            if cName == "barrel" or cName == "chamber" or cName == "trigger" then return true end
        end
        return false
    end

    local function removeGunOverlay()
        if gunRenderConn then gunRenderConn:Disconnect(); gunRenderConn = nil end
        for _, pair in ipairs(gunSyncedParts) do
            if pair.Real and pair.Real.Parent then
                pcall(function()
                    pair.Real.Transparency = pair.OriginalTransparency
                    pair.Real.LocalTransparencyModifier = pair.OriginalLocalTransparencyModifier
                    pair.Real.Material = pair.OriginalMaterial
                    pair.Real.Color = pair.OriginalColor
                end)
            end
            if pair.Fake then pcall(function() pair.Fake:Destroy() end) end
        end
        if activeGunOverlay then pcall(function() activeGunOverlay:Destroy() end); activeGunOverlay = nil end
        trackedGunModel = nil
        gunSyncedParts = {}
    end

    local function applyGunOverlay(gunModel)
        if not gunForcefieldActive then removeGunOverlay(); return end
        if trackedGunModel == gunModel then return end
        removeGunOverlay()

        if isGunModel(gunModel) then
            trackedGunModel = gunModel
            local WAVE_TRANSPARENCY = 0.001
            local GLOW_BRIGHTNESS = 0.01
            local WAVE_COLOR = Color3.fromRGB(0, 230, 255)

            local cloneModel = Instance.new("Model")
            cloneModel.Name = "GunGalaxyWaveOverlay"
            cloneModel.Parent = workspace
            activeGunOverlay = cloneModel

            local highlight = Instance.new("Highlight")
            highlight.Name = "GunWaveBooster"
            highlight.Adornee = cloneModel
            highlight.FillColor = WAVE_COLOR
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = GLOW_BRIGHTNESS
            highlight.OutlineTransparency = 0.05
            highlight.Parent = cloneModel

            gunSyncedParts = {}
            for _, v in ipairs(gunModel:GetChildren()) do
                if v:IsA("BasePart") then
                    local origTransparency = v.Transparency
                    local origLTM = v.LocalTransparencyModifier
                    local origMaterial = v.Material
                    local origColor = v.Color

                    v.LocalTransparencyModifier = 1
                    pcall(function() v.Transparency = 1 end)
                    
                    local pClone = v:Clone()
                    pClone:ClearAllChildren()
                    pClone.Anchored = false
                    pClone.CanCollide = false
                    pClone.Transparency = WAVE_TRANSPARENCY
                    pClone.Material = Enum.Material.ForceField
                    pClone.Color = WAVE_COLOR
                    pClone.Parent = cloneModel
                    
                    table.insert(gunSyncedParts, {
                        Real = v, Fake = pClone,
                        OriginalTransparency = origTransparency,
                        OriginalLocalTransparencyModifier = origLTM,
                        OriginalMaterial = origMaterial,
                        OriginalColor = origColor
                    })
                end
            end

            gunRenderConn = RunService.RenderStepped:Connect(function()
                if not gunModel or not gunModel.Parent or not cloneModel.Parent or not gunForcefieldActive then
                    removeGunOverlay()
                    return
                end
                for _, pair in ipairs(gunSyncedParts) do
                    if pair.Real and pair.Real.Parent and pair.Fake and pair.Fake.Parent then
                        pair.Fake.CFrame = pair.Real.CFrame
                    end
                end
            end)
            table.insert(_G.StealthConnections, gunRenderConn)
        end
    end

    local function toggleGunForcefield()
        gunForcefieldActive = not gunForcefieldActive
        if gunForcefieldActive then
            for _, child in ipairs(targetEntityPath:GetChildren()) do
                if child:IsA("Model") and isGunModel(child) then applyGunOverlay(child); break end
            end
        else
            removeGunOverlay()
        end
    end

    local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and input.KeyCode == Enum.KeyCode.J then
            toggleGunForcefield()
        end
    end)
    table.insert(_G.StealthConnections, keyConn)

    local gunAddedConn = targetEntityPath.ChildAdded:Connect(function(child)
        if child:IsA("Model") then
            task.defer(function()
                if child and child.Parent and isGunModel(child) and gunForcefieldActive then applyGunOverlay(child) end
            end)
        end
    end)
    table.insert(_G.StealthConnections, gunAddedConn)

    local gunRemovedConn = targetEntityPath.ChildRemoved:Connect(function(child)
        if child == trackedGunModel then removeGunOverlay() end
    end)
    table.insert(_G.StealthConnections, gunRemovedConn)
else
    local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and input.KeyCode == Enum.KeyCode.J then
            gunForcefieldActive = not gunForcefieldActive
        end
    end)
    table.insert(_G.StealthConnections, keyConn)
end