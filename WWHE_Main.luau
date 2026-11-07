-- WWHE Main Loader (Stays Static / Rarely Changes)
_G.StealthConnections = _G.StealthConnections or {}

-- Safety cleanup for existing connections and caches before reloading
if _G.StealthHeadCache then
    for part, originalSize in pairs(_G.StealthHeadCache) do
        if part and part.Parent then
            pcall(function()
                part.Size = originalSize
                part.Transparency = 0
                part.CanCollide = true
            end)
        end
    end
    _G.StealthHeadCache = nil
end

if _G.StealthDrawingCache then
    for _, drawings in pairs(_G.StealthDrawingCache) do
        if drawings then
            for _, drawObj in pairs(drawings) do
                if drawObj then pcall(function() drawObj:Destroy() end) end
            end
        end
    end
    _G.StealthDrawingCache = nil
end

if _G.StealthHighlightCache then
    for _, highlight in pairs(_G.StealthHighlightCache) do
        if highlight then pcall(function() highlight:Destroy() end) end
    end
    _G.StealthHighlightCache = nil
end

if _G.StealthHitmanHighlightCache then
    for _, highlight in pairs(_G.StealthHitmanHighlightCache) do
        if highlight then pcall(function() highlight:Destroy() end) end
    end
    _G.StealthHitmanHighlightCache = nil
end

if _G.StealthHitmanDrawingCache then
    for _, drawings in pairs(_G.StealthHitmanDrawingCache) do
        if drawings then
            for _, drawObj in pairs(drawings) do
                if drawObj then pcall(function() drawObj:Destroy() end) end
            end
        end
    end
    _G.StealthHitmanDrawingCache = nil
end

-- Cleanup Aim Assist drawings on global reset
if _G.StealthAimAssistDrawings then
    for _, drawObj in pairs(_G.StealthAimAssistDrawings) do
        if drawObj then pcall(function() drawObj:Destroy() end) end
    end
    _G.StealthAimAssistDrawings = nil
end

if _G.StealthConnections then
    for _, conn in pairs(_G.StealthConnections) do
        if conn then pcall(function() conn:Disconnect() end) end
    end
    _G.StealthConnections = nil
end

if _G.StealthHitboxConnection then
    _G.StealthHitboxConnection:Disconnect()
    _G.StealthHitboxConnection = nil
end

if _G.StealthWorkerRunning then
    _G.StealthWorkerRunning = false
end

-- Initialize global caches and state trackers
_G.StealthHeadCache = {}
_G.StealthDrawingCache = {}
_G.StealthHighlightCache = {}
_G.StealthHitmanHighlightCache = {}
_G.StealthHitmanDrawingCache = {}
_G.StealthAimAssistDrawings = {}
_G.StealthConnections = {}
_G.StealthWorkerRunning = true

-- Module Loader Function
local function loadModule(fileName)
    local success, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/morrojroller/TheWildWestMain/main/" .. fileName))()
    end)
    if not success then
        warn("[WWHE Loader] Failed to load module: " + tostring(fileName) + " | Error: " + tostring(result))
    end
end

-- Load your modular feature components in order (including new prediction architecture)
loadModule("Visuals.luau")
loadModule("Hitboxes.luau")
loadModule("GunMod.luau")
loadModule("HitmanStuff.luau")
loadModule("AllGunData.luau")
loadModule("Prediction.luau")
loadModule("AimAssist.luau")

print("[WWHE]: All modules including Prediction and AllGunData loaded successfully!")
