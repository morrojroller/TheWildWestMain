local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local damageColorActive = true
local normalColor = Color3.fromRGB(0, 150, 50)       -- Dark Green for normal hits
local normalOutline = Color3.fromRGB(0, 20, 80)     -- Subtle Dark Blue outline
local critColor = Color3.fromRGB(255, 105, 180)     -- Bright Pink for critical hits
local critOutline = Color3.fromRGB(100, 0, 50)      -- Outline glow for crits
local crosshairHitColor = Color3.fromRGB(255, 105, 180)

local function styleDamageIndicator(gui)
    if not damageColorActive then return end
    if gui.Name == "DamageIndicator" and gui:IsA("BillboardGui") then
        for _, descendant in ipairs(gui:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                local col = descendant.TextColor3
                if col.R > 0.9 and col.G > 0.9 and col.B > 0.9 then
                    descendant.TextColor3 = normalColor
                    descendant.TextStrokeColor3 = normalOutline
                    descendant.TextStrokeTransparency = 0
                elseif col.R > 0.7 and col.G < 0.5 then
                    descendant.TextColor3 = critColor
                    descendant.TextStrokeColor3 = critOutline
                    descendant.TextStrokeTransparency = 0
                    
                    local originalSize = descendant.TextSize
                    if originalSize == 0 then originalSize = 18 end
                    descendant.TextSize = originalSize + 1
                    
                    local shrinkTween
                    shrinkTween = RunService.RenderStepped:Connect(function()
                        if not descendant or not descendant.Parent or not damageColorActive then
                            if shrinkTween then shrinkTween:Disconnect() end
                            return
                        end
                        if descendant.TextSize > originalSize then
                            descendant.TextSize = math.clamp(descendant.TextSize - 0.2, originalSize, originalSize + 1)
                        else
                            if shrinkTween then shrinkTween:Disconnect() end
                        end
                    end)
                    table.insert(_G.StealthConnections, shrinkTween)
                end
                
                local conn = descendant:GetPropertyChangedSignal("TextColor3"):Connect(function()
                    if not damageColorActive then return end
                    local current = descendant.TextColor3
                    if current.R > 0.9 and current.G > 0.9 and current.B > 0.9 then
                        if current ~= normalColor then
                            descendant.TextColor3 = normalColor
                            descendant.TextStrokeColor3 = normalOutline
                        end
                    elseif current.R > 0.7 and current.G < 0.5 then
                        if current ~= critColor then
                            descendant.TextColor3 = critColor
                            descendant.TextStrokeColor3 = critOutline
                        end
                    end
                end)
                table.insert(_G.StealthConnections, conn)
            end
        end
        
        local addConn = gui.DescendantAdded:Connect(function(descendant)
            if not damageColorActive then return end
            if descendant:IsA("TextLabel") then
                task.spawn(function()
                    task.wait()
                    local col = descendant.TextColor3
                    if col.R > 0.9 and col.G > 0.9 and col.B > 0.9 then
                        descendant.TextColor3 = normalColor
                        descendant.TextStrokeColor3 = normalOutline
                        descendant.TextStrokeTransparency = 0
                    elseif col.R > 0.7 and col.G < 0.5 then
                        descendant.TextColor3 = critColor
                        descendant.TextStrokeColor3 = critOutline
                        descendant.TextStrokeTransparency = 0
                        
                        local originalSize = descendant.TextSize
                        if originalSize == 0 then originalSize = 18 end
                        descendant.TextSize = originalSize + 1
                        
                        local shrinkTween
                        shrinkTween = RunService.RenderStepped:Connect(function()
                            if not descendant or not descendant.Parent or not damageColorActive then
                                if shrinkTween then shrinkTween:Disconnect() end
                                return
                            end
                            if descendant.TextSize > originalSize then
                                descendant.TextSize = math.clamp(descendant.TextSize - 0.2, originalSize, originalSize + 1)
                            else
                                if shrinkTween then shrinkTween:Disconnect() end
                            end
                        end)
                        table.insert(_G.StealthConnections, shrinkTween)
                    end
                end)
            end
        end)
        table.insert(_G.StealthConnections, addConn)
    end
end

local function styleCrosshair(cursorBarsFolder)
    local function setupBar(bar)
        if bar:IsA("GuiObject") then
            bar:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
                if not damageColorActive then return end
                local col = bar.BackgroundColor3
                if col.R > 0.7 and col.G < 0.4 and col.B < 0.4 then
                    if col ~= crosshairHitColor then
                        bar.BackgroundColor3 = crosshairHitColor
                    end
                end
            end)
        end
    end

    for _, child in ipairs(cursorBarsFolder:GetDescendants()) do
        setupBar(child)
    end

    local addConn = cursorBarsFolder.DescendantAdded:Connect(function(descendant)
        setupBar(descendant)
    end)
    table.insert(_G.StealthConnections, addConn)
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
if playerGui then
    local function checkCursorFolder(parentFolder)
        local cursorFolder = parentFolder:FindFirstChild("Cursor")
        if cursorFolder then
            local cursors = cursorFolder:FindFirstChild("Cursors")
            if cursors then
                local cursorBars = cursors:FindFirstChild("Cursor_Bars")
                if cursorBars then styleCrosshair(cursorBars) end
                local cursorsAddConn = cursors.ChildAdded:Connect(function(child)
                    if child.Name == "Cursor_Bars" then styleCrosshair(child) end
                end)
                table.insert(_G.StealthConnections, cursorsAddConn)
            end
        end
    end

    checkCursorFolder(playerGui)
    local pgAddConn = playerGui.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "Cursor_Bars" and descendant.Parent and descendant.Parent.Name == "Cursors" then
            styleCrosshair(descendant)
        end
    end)
    table.insert(_G.StealthConnections, pgAddConn)
end

local ignoreFolder = Workspace:WaitForChild("Ignore", 5)
if ignoreFolder then
    for _, child in ipairs(ignoreFolder:GetDescendants()) do
        styleDamageIndicator(child)
    end
    local ignoreAddConn = ignoreFolder.DescendantAdded:Connect(function(descendant)
        styleDamageIndicator(descendant)
    end)
    table.insert(_G.StealthConnections, ignoreAddConn)
end

local keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Semicolon then
        damageColorActive = not damageColorActive
    end
end)
table.insert(_G.StealthConnections, keyConn)
