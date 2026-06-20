local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MIN_SELL_VALUE = 5
local PRESENT_NAMES = {
    Present = true, Present1 = true, Present2 = true,
    Present3 = true, Present4 = true, Present5 = true
}

local math_floor = math.floor
local Vector2_new = Vector2.new
local WTS = WorldToScreen
local pcall_ = pcall

local BoxEdges = {
    {1,2},{3,4},{1,3},{2,4},
    {5,6},{7,8},{5,7},{6,8},
    {1,5},{2,6},{3,7},{4,8}
}

local ESPCache = {} -- [model] = { lines, label, root, labelPrefix }

local function getCorners(part)
    local pos = part.Position
    local sx, sy, sz = part.Size.X/2, part.Size.Y/2, part.Size.Z/2
    local m = MemoryManager and MemoryManager.GetRotationMatrix(part)
    local r = m and Vector3.new(m[0],m[3],m[6])*sx or Vector3.new(sx,0,0)
    local u = m and Vector3.new(m[1],m[4],m[7])*sy or Vector3.new(0,sy,0)
    local b = m and Vector3.new(m[2],m[5],m[8])*sz or Vector3.new(0,0,sz)
    return {
        pos-r+u+b, pos+r+u+b, pos-r-u+b, pos+r-u+b,
        pos-r+u-b, pos+r+u-b, pos-r-u-b, pos+r-u-b
    }
end

local function createESPEntry(color)
    local entry = { lines = {}, label = nil }
    for i = 1, 12 do
        local l = Drawing.new("Line")
        l.Thickness = 1
        l.Color = color
        l.Visible = false
        entry.lines[i] = l
    end
    local t = Drawing.new("Text")
    t.Size = 16
    t.Center = true
    t.Outline = true
    t.Color = color
    t.Visible = false
    entry.label = t
    return entry
end

local function destroyESPEntry(entry)
    for i = 1, 12 do pcall_(function() entry.lines[i]:Remove() end) end
    pcall_(function() entry.label:Remove() end)
end

local function updateESP(cacheEntry)
    local root = cacheEntry.root
    if not root or not root.Parent then
        for i = 1, 12 do cacheEntry.lines[i].Visible = false end
        cacheEntry.label.Visible = false
        return
    end

    local okPos, pos = pcall_(function() return root.Position end)
    if not okPos or not pos then
        for i = 1, 12 do cacheEntry.lines[i].Visible = false end
        cacheEntry.label.Visible = false
        return
    end

    local corners = getCorners(root)
    local pts, allOn = {}, true
    for c = 1, 8 do
        local ok, sc, on = pcall_(WTS, corners[c])
        if not ok or not on or not sc then
            allOn = false
            break
        end
        pts[c] = Vector2_new(math_floor(sc.X+0.5), math_floor(sc.Y+0.5))
    end

    if allOn then
        for l = 1, 12 do
            local e = BoxEdges[l]
            cacheEntry.lines[l].From = pts[e[1]]
            cacheEntry.lines[l].To = pts[e[2]]
            cacheEntry.lines[l].Visible = true
        end

        local okLp, lp = pcall_(function()
            return Players.LocalPlayer.Character.HumanoidRootPart
        end)
        local dist = 0
        if okLp and lp then
            dist = (pos - lp.Position).Magnitude
        end

        local minX, minY = math.huge, math.huge
        for c = 1, 8 do
            if pts[c].X < minX then minX = pts[c].X end
            if pts[c].Y < minY then minY = pts[c].Y end
        end

        cacheEntry.label.Text = cacheEntry.labelPrefix .. math_floor(dist) .. "m]"
        cacheEntry.label.Position = Vector2_new(minX, minY - 16)
        cacheEntry.label.Visible = true
    else
        for i = 1, 12 do cacheEntry.lines[i].Visible = false end
        cacheEntry.label.Visible = false
    end
end

local function resolveRoot(model)
    return model:FindFirstChild("HitBox")
        or model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
        or model:FindFirstChildWhichIsA("MeshPart")
end

-- Build itemId -> {fullName, sellValue} lookup once, refreshed occasionally
local qualifyingItems = {}
local function buildQualifyingItems()
    qualifyingItems = {}
    local okInfo, itemInfo = pcall_(function() return ReplicatedStorage.ItemInfo end)
    if not okInfo or not itemInfo then return end

    for _, itemEntry in next, itemInfo:GetChildren() do
        local okFN, fullNameObj = pcall_(function() return itemEntry:FindFirstChild("FullName") end)
        local okSV, sellValueObj = pcall_(function() return itemEntry:FindFirstChild("SellValue") end)
        if okFN and fullNameObj and okSV and sellValueObj then
            local okFNV, fullName = pcall_(function() return fullNameObj.Value end)
            local okSVV, sellValue = pcall_(function() return sellValueObj.Value end)
            local okId, itemId = pcall_(function() return tonumber(itemEntry.Name) end)
            if okFNV and okSVV and okId and itemId and type(fullName) == "string" and type(sellValue) == "number" then
                if fullName ~= "" and sellValue >= MIN_SELL_VALUE then
                    qualifyingItems[itemId] = { fullName = fullName, sellValue = sellValue }
                end
            end
        end
    end
end

buildQualifyingItems()
task.spawn(function()
    while true do
        task.wait(15)
        buildQualifyingItems()
    end
end)

local running = true

-- SCAN LOOP: Spawners (Info.Item match) + workspace direct children (Present name match)
task.spawn(function()
    while running do
        local validModels = {}

        -- 1) Spawners tree: match via Info.Item -> ItemInfo lookup
        local okSpawners, spawnersFolder = pcall_(function() return workspace.Spawners end)
        if okSpawners and spawnersFolder and next(qualifyingItems) then
            for _, v in next, spawnersFolder:GetDescendants() do
                local okCheck, isMatch = pcall_(function()
                    return v:IsA("IntValue") and v.Name == "Item" and v.Parent and v.Parent.Name == "Info"
                end)

                if okCheck and isMatch then
                    local okVal, itemId = pcall_(function() return v.Value end)
                    if okVal and itemId then
                        local itemData = qualifyingItems[itemId]
                        if itemData then
                            local okModel, plantModel = pcall_(function() return v.Parent.Parent end)
                            if okModel and plantModel then
                                local root = resolveRoot(plantModel)
                                if root then
                                    validModels[plantModel] = true
                                    if not ESPCache[plantModel] then
                                        local entry = createESPEntry(Color3.fromRGB(255, 215, 0))
                                        entry.root = root
                                        entry.labelPrefix = itemData.fullName .. " [$" .. itemData.sellValue .. "] ["
                                        ESPCache[plantModel] = entry
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 2) Direct workspace children named Present, Present1..Present5
        for _, obj in next, workspace:GetChildren() do
            local okCheck, isPresent = pcall_(function()
                return PRESENT_NAMES[obj.Name] == true and obj:IsA("Model")
            end)

            if okCheck and isPresent then
                local root = resolveRoot(obj)
                if root then
                    validModels[obj] = true
                    if not ESPCache[obj] then
                        local entry = createESPEntry(Color3.fromRGB(0, 200, 255)) -- cyan for presents
                        entry.root = root
                        entry.labelPrefix = obj.Name .. " ["
                        ESPCache[obj] = entry
                    end
                end
            end
        end

        -- cleanup stale entries
        for model, entry in pairs(ESPCache) do
            if not validModels[model] then
                destroyESPEntry(entry)
                ESPCache[model] = nil
            end
        end

        task.wait(0.5)
    end
end)

-- RENDER LOOP
local renderConn = RunService.RenderStepped:Connect(function()
    if not running then return end
    for _, entry in pairs(ESPCache) do
        updateESP(entry)
    end
end)

-- To stop: running = false (then renderConn:Disconnect())
