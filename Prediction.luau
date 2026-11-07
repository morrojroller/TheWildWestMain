local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local GRAVITY = Vector3.new(0, -32, 0)
local targetVelocities = {} -- [model] = { lastPos, lastTime, velocity, smoothVelocity }

local Prediction = {}

local currentWeaponName = nil
local currentWeaponData = nil
local AllGunData = nil

function Prediction.SetGunData(gunData)
    AllGunData = gunData
end

local function findWeaponModel(playerFolder)
    if not playerFolder then return nil end
    for _, child in ipairs(playerFolder:GetChildren()) do
        if child:IsA("Model") then
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

local function resolveWeaponData(weaponName)
    if not AllGunData or not weaponName then return nil end
    if AllGunData[weaponName] then return AllGunData[weaponName] end
    local stripped = weaponName:gsub("Item$", "")
    if AllGunData[stripped] then return AllGunData[stripped] end
    for gunName, data in pairs(AllGunData) do
        if weaponName:lower() == gunName:lower() then return data end
    end
    return nil
end

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
            if child:IsA("Model") then task.defer(function() onWeaponChanged(playerFolder) end) end
        end))
        table.insert(_G.StealthConnections, playerFolder.ChildRemoved:Connect(function(child)
            if child:IsA("Model") then task.defer(function() onWeaponChanged(playerFolder) end) end
        end))
    end
    
    if not playerFolder then
        table.insert(_G.StealthConnections, playersFolder.ChildAdded:Connect(function(child)
            if child.Name == LocalPlayer.Name then
                playerFolder = child
                task.defer(function()
                    onWeaponChanged(playerFolder)
                    table.insert(_G.StealthConnections, playerFolder.ChildAdded:Connect(function(c)
                        if c:IsA("Model") then task.defer(function() onWeaponChanged(playerFolder) end) end
                    end))
                    table.insert(_G.StealthConnections, playerFolder.ChildRemoved:Connect(function(c)
                        if c:IsA("Model") then task.defer(function() onWeaponChanged(playerFolder) end) end
                    end))
                end)
            end
        end))
    end
end

-- Enhanced velocity tracking with anti-jiggle damping
local VELOCITY_SMOOTH_FACTOR = 0.2 -- Lowered for smoother response against jerky strafes
local MIN_VELOCITY_THRESHOLD = 0.8
local MAX_VELOCITY_CAP = 45 -- Capped lower to prevent over-aiming when players jiggle fast

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
    if dt < 0.001 then return data.smoothVelocity end
    
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
    
    -- Cap prediction time at long range to prevent wild misses on jiggling targets
    t = math.clamp(t, 0, 1.0)
    
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
    
    return math.clamp(t, 0, 1.2) -- Strict clamp to avoid long-range prediction over-extension
end

function Prediction.GetPredictedPosition(origin, targetModel, targetPos, targetVelocity)
    if not currentWeaponData then return targetPos end
    
    -- Retrieve actual projectile power/speed from shared weapon data
    local projectileSpeed = currentWeaponData.ProjectilePower or 1000
    local relPos = targetPos - origin
    
    -- Quadratic coefficients for intercept time (t)
    local a = targetVelocity:Dot(targetVelocity) - (projectileSpeed * projectileSpeed)
    local b = 2 * relPos:Dot(targetVelocity)
    local c = relPos:Dot(relPos)
    
    local discriminant = (b * b) - (4 * a * c)
    if discriminant < 0 or math.abs(a) < 0.0001 then
        -- Fallback to linear travel time if discriminant fails
        local flightTime = relPos.Magnitude / projectileSpeed
        local gravDrop = 0.5 * 32 * (flightTime * flightTime)
        return targetPos + (targetVelocity * flightTime) + Vector3.new(0, gravDrop, 0)
    end
    
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
    
    if not t then return targetPos end
    
    -- Clamp prediction time to prevent wild over-aiming on jiggling targets
    t = math.clamp(t, 0, 1.2)
    
    -- Calculate precise predicted position with gravity drop (-32 studs/s^2)
    local predictedPos = targetPos + (targetVelocity * t)
    local gravDrop = 0.5 * 32 * (t * t)
    predictedPos = predictedPos + Vector3.new(0, gravDrop, 0)
    
    return predictedPos
end

function Prediction.GetCurrentWeaponName() return currentWeaponName end
function Prediction.GetCurrentWeaponData() return currentWeaponData end
function Prediction.GetProjectileSpeed() return currentWeaponData and currentWeaponData.ProjectilePower or nil end

function Prediction.CleanupStaleData()
    local now = tick()
    for model, data in pairs(targetVelocities) do
        if not model or not model.Parent or (now - data.lastTime) > 5 then
            targetVelocities[model] = nil
        end
    end
end

return Prediction
