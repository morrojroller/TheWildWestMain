-- Prediction.luau - Projectile prediction system for aim assist
-- Calculates where to aim based on target velocity, projectile speed, and gravity

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Gravity constant used by the game's projectile system
local GRAVITY = Vector3.new(0, -32, 0)

-- Velocity tracking for targets
local targetVelocities = {} -- [model] = { lastPos, lastTime, velocity, smoothVelocity }

local Prediction = {}

-- ============================================================
-- WEAPON DETECTION: Monitors LocalPlayer's equipped weapon
-- ============================================================
local currentWeaponName = nil
local currentWeaponData = nil
local AllGunData = nil

function Prediction.SetGunData(gunData)
    AllGunData = gunData
end

-- Finds the weapon model name from the player's entity folder
local function findWeaponModel(playerFolder)
    if not playerFolder then return nil end
    for _, child in ipairs(playerFolder:GetChildren()) do
        if child:IsA("Model") then
            -- Check if this is a gun model (has barrel/chamber/trigger parts)
            for _, part in ipairs(child:GetChildren()) do
                if part:IsA("BasePart") then
                    local pName = part.Name:lower()
                    if pName == "barrel" or pName == "chamber" or pName == "trigger" then
                        return child.Name
                    end
                end
            end
        end
    end
    return nil
end

-- Resolves the weapon name to gun data, handling variant lookups
local function resolveWeaponData(weaponName)
    if not AllGunData or not weaponName then return nil end
    
    -- Direct match first
    if AllGunData[weaponName] then
        return AllGunData[weaponName]
    end
    
    -- Try common name variations (the model name in workspace may differ slightly)
    local stripped = weaponName:gsub("Item$", "")
    if AllGunData[stripped] then
        return AllGunData[stripped]
    end
    
    -- Fuzzy match: check if any key is contained in the weapon name or vice versa
    for gunName, data in pairs(AllGunData) do
        if weaponName:lower() == gunName:lower() then
            return data
        end
    end
    
    return nil
end

-- Start monitoring the local player's weapon via Workspace.WORKSPACE_Entities.Players.LOCALPLAYER
function Prediction.StartWeaponMonitor()
    local entitiesFolder = Workspace:FindFirstChild("WORKSPACE_Entities")
    if not entitiesFolder then return end
    local playersFolder = entitiesFolder:FindFirstChild("Players")
    if not playersFolder then return end
    
    local playerFolder = playersFolder:FindFirstChild(LocalPlayer.Name)
    
    local function onWeaponChanged(playerF)
        if not playerF then return end
        local weaponName = findWeaponModel(playerF)
        if weaponName ~= currentWeaponName then
            currentWeaponName = weaponName
            currentWeaponData = resolveWeaponData(weaponName)
        end
    end
    
    if playerFolder then
        onWeaponChanged(playerFolder)
        
        table.insert(_G.StealthConnections, playerFolder.ChildAdded:Connect(function(child)
            if child:IsA("Model") then
                task.defer(function()
                    onWeaponChanged(playerFolder)
                end)
            end
        end))
        
        table.insert(_G.StealthConnections, playerFolder.ChildRemoved:Connect(function(child)
            if child:IsA("Model") then
                task.defer(function()
                    onWeaponChanged(playerFolder)
                end)
            end
        end))
    end
    
    if not playerFolder then
        table.insert(_G.StealthConnections, playersFolder.ChildAdded:Connect(function(child)
            if child.Name == LocalPlayer.Name then
                playerFolder = child
                task.defer(function()
                    onWeaponChanged(playerFolder)
                    
                    table.insert(_G.StealthConnections, playerFolder.ChildAdded:Connect(function(c)
                        if c:IsA("Model") then
                            task.defer(function() onWeaponChanged(playerFolder) end)
                        end
                    end))
                    
                    table.insert(_G.StealthConnections, playerFolder.ChildRemoved:Connect(function(c)
                        if c:IsA("Model") then
                            task.defer(function() onWeaponChanged(playerFolder) end)
                        end
                    end))
                end)
            end
        end))
    end
end

-- ============================================================
-- VELOCITY TRACKING: Smooth velocity estimation per target
-- ============================================================
local VELOCITY_SMOOTH_FACTOR = 0.35
local MIN_VELOCITY_THRESHOLD = 0.5
local MAX_VELOCITY_CAP = 80

function Prediction.UpdateTargetVelocity(model, currentPos)
    local now = tick()
    local data = targetVelocities[model]
    
    if not data then
        targetVelocities[model] = {
            lastPos = currentPos,
            lastTime = now,
            velocity = Vector3.zero,
            smoothVelocity = Vector3.zero,
        }
        return Vector3.zero
    end
    
    local dt = now - data.lastTime
    if dt < 0.001 then
        return data.smoothVelocity
    end
    
    local rawVelocity = (currentPos - data.lastPos) / dt
    if rawVelocity.Magnitude > MAX_VELOCITY_CAP then
        rawVelocity = rawVelocity.Unit * MAX_VELOCITY_CAP
    end
    
    local smoothed = data.smoothVelocity:Lerp(rawVelocity, VELOCITY_SMOOTH_FACTOR)
    if smoothed.Magnitude < MIN_VELOCITY_THRESHOLD then
        smoothed = Vector3.zero
    end
    
    data.lastPos = currentPos
    data.lastTime = now
    data.velocity = rawVelocity
    data.smoothVelocity = smoothed
    
    return smoothed
end

function Prediction.CleanupTarget(model)
    targetVelocities[model] = nil
end

-- ============================================================
-- PREDICTION SOLVER: Calculate predicted aim position
-- ============================================================
local function solveInterceptTime(origin, targetPos, targetVel, projectileSpeed, gravity)
    local relPos = targetPos - origin
    local relVel = targetVel
    local gravY = gravity.Y
    
    local a = relVel:Dot(relVel) - projectileSpeed * projectileSpeed
    local b = 2 * relPos:Dot(relVel)
    local c = relPos:Dot(relPos)
    
    local discriminant = b * b - 4 * a * c
    
    if math.abs(a) < 0.0001 then
        if math.abs(b) < 0.0001 then return nil end
        local t = -c / b
        return t > 0 and t or nil
    end
    
    if discriminant < 0 then return nil end
    
    local sqrtDisc = math.sqrt(discriminant)
    local t1 = (-b - sqrtDisc) / (2 * a)
    local t2 = (-b + sqrtDisc) / (2 * a)
    
    local t = nil
    if t1 > 0.001 and t2 > 0.001 then
        t = math.min(t1, t2)
    elseif t1 > 0.001 then
        t = t1
    elseif t2 > 0.001 then
        t = t2
    end
    
    if not t then return nil end
    
    local gravDrop = 0.5 * math.abs(gravY) * t * t
    local adjustedTargetPos = targetPos + Vector3.new(0, gravDrop, 0)
    local relPos2 = adjustedTargetPos - origin
    
    local c2 = relPos2:Dot(relPos2)
    local b2 = 2 * relPos2:Dot(relVel)
    
    local disc2 = b2 * b2 - 4 * a * c2
    if disc2 >= 0 then
        local sqrtDisc2 = math.sqrt(disc2)
        local t1_2 = (-b2 - sqrtDisc2) / (2 * a)
        local t2_2 = (-b2 + sqrtDisc2) / (2 * a)
        
        if t1_2 > 0.001 and t2_2 > 0.001 then
            t = math.min(t1_2, t2_2)
        elseif t1_2 > 0.001 then
            t = t1_2
        elseif t2_2 > 0.001 then
            t = t2_2
        end
    end
    
    return math.clamp(t, 0, 2.0)
end

function Prediction.GetPredictedPosition(origin, targetModel, targetPos)
    if not currentWeaponData then
        return targetPos
    end
    
    local projectileSpeed = currentWeaponData.ProjectilePower
    if not projectileSpeed or projectileSpeed <= 0 then
        return targetPos
    end
    
    local targetVelocity = Prediction.UpdateTargetVelocity(targetModel, targetPos)
    
    if targetVelocity.Magnitude < MIN_VELOCITY_THRESHOLD then
        local distance = (targetPos - origin).Magnitude
        local flightTime = distance / projectileSpeed
        local gravDrop = 0.5 * math.abs(GRAVITY.Y) * flightTime * flightTime
        return targetPos + Vector3.new(0, gravDrop, 0)
    end
    
    local interceptTime = solveInterceptTime(origin, targetPos, targetVelocity, projectileSpeed, GRAVITY)
    
    if not interceptTime then
        local distance = (targetPos - origin).Magnitude
        local flightTime = distance / projectileSpeed
        local gravDrop = 0.5 * math.abs(GRAVITY.Y) * flightTime * flightTime
        return targetPos + targetVelocity * flightTime + Vector3.new(0, gravDrop, 0)
    end
    
    local predictedPos = targetPos + targetVelocity * interceptTime
    local gravDrop = 0.5 * math.abs(GRAVITY.Y) * interceptTime * interceptTime
    predictedPos = predictedPos + Vector3.new(0, gravDrop, 0)
    
    return predictedPos
end

function Prediction.GetCurrentWeaponName()
    return currentWeaponName
end

function Prediction.GetCurrentWeaponData()
    return currentWeaponData
end

function Prediction.GetProjectileSpeed()
    if currentWeaponData then
        return currentWeaponData.ProjectilePower
    end
    return nil
end

function Prediction.CleanupStaleData()
    local now = tick()
    for model, data in pairs(targetVelocities) do
        if not model or not model.Parent or (now - data.lastTime) > 5 then
            targetVelocities[model] = nil
        end
    end
end

return Prediction