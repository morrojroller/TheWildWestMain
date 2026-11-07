local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local GRAVITY = Vector3.new(0, -32, 0)
local targetVelocities = {}

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

-- Safely convert anything to Vector3
local function toVector3(pos)
    local t = typeof(pos)
    if t == "Vector3" then
        return pos
    elseif t == "CFrame" then
        return pos.Position
    elseif t == "Instance" then
        if pos:IsA("Model") then
            return pos:GetPivot().Position
        elseif pos:IsA("BasePart") then
            return pos.Position
        end
    end
    return nil
end

local VELOCITY_SMOOTH_FACTOR = 0.2 
local MIN_VELOCITY_THRESHOLD = 0.8
local MAX_VELOCITY_CAP = 45 

function Prediction.UpdateTargetVelocity(model, currentPos)
    local posVec = toVector3(currentPos)
    if not posVec then return Vector3.zero end

    local now = tick()
    local data = targetVelocities[model]
    
    if not data then
        targetVelocities[model] = {
            lastPos = posVec,
            lastTime = now,
            velocity = Vector3.zero,
            smoothVelocity = Vector3.zero,
        }
        return Vector3.zero
    end
    
    local dt = now - data.lastTime
    if dt < 0.001 then return data.smoothVelocity end
    
    local rawVelocity = (posVec - data.lastPos) / dt
    if rawVelocity.Magnitude > MAX_VELOCITY_CAP then
        rawVelocity = rawVelocity.Unit * MAX_VELOCITY_CAP
    end
    
    local smoothed = data.smoothVelocity:Lerp(rawVelocity, VELOCITY_SMOOTH_FACTOR)
    if smoothed.Magnitude < MIN_VELOCITY_THRESHOLD then
        smoothed = Vector3.zero
    end
    
    data.lastPos = posVec
    data.lastTime = now
    data.velocity = rawVelocity
    data.smoothVelocity = smoothed
    
    return smoothed
end

function Prediction.CleanupTarget(model)
    targetVelocities[model] = nil
end

function Prediction.GetPredictedPosition(origin, targetModel, targetPos)
    local originVec = toVector3(origin)
    local targetVec = toVector3(targetPos)
    
    if not originVec or not targetVec then return targetPos end
    
    -- Extract and force projectile speed to be a clean number (default to 1000 if missing or string)
    local rawSpeed = currentWeaponData and currentWeaponData.ProjectilePower or 1000
    local projectileSpeed = tonumber(rawSpeed) or 1000
    if projectileSpeed <= 0 then projectileSpeed = 1000 end
    
    local targetVelocity = Prediction.UpdateTargetVelocity(targetModel, targetVec)
    local relPos = targetVec - originVec
    
    local a = targetVelocity:Dot(targetVelocity) - (projectileSpeed * projectileSpeed)
    local b = 2 * relPos:Dot(targetVelocity)
    local c = relPos:Dot(relPos)
    
    local discriminant = (b * b) - (4 * a * c)
    if discriminant < 0 or math.abs(a) < 0.0001 then
        local flightTime = relPos.Magnitude / projectileSpeed
        local gravDrop = 0.5 * math.abs(GRAVITY.Y) * (flightTime * flightTime)
        return targetVec + (targetVelocity * flightTime) + Vector3.new(0, gravDrop, 0)
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
    
    if not t then return targetVec end
    
    t = math.clamp(t, 0, 1.2)
    
    -- Force time and drop calculations to strictly be numbers
    local safeT = tonumber(t) or 0
    local predictedPos = targetVec + (targetVelocity * safeT)
    local gravDrop = 0.5 * math.abs(GRAVITY.Y) * (safeT * safeT)
    predictedPos = predictedPos + Vector3.new(0, tonumber(gravDrop) or 0, 0)
    
    return predictedPos
end

function Prediction.GetCurrentWeaponName() return currentWeaponName end
function Prediction.GetCurrentWeaponData() return currentWeaponData end
function Prediction.GetProjectileSpeed() return currentWeaponData and tonumber(currentWeaponData.ProjectilePower) or nil end

function Prediction.CleanupStaleData()
    local now = tick()
    for model, data in pairs(targetVelocities) do
        if not model or not model.Parent or (now - data.lastTime) > 5 then
            targetVelocities[model] = nil
        end
    end
end

return Prediction
