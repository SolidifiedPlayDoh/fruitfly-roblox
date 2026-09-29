local StarterPack = game:GetService("StarterPack")

local function tag(handle, text, color)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SmellTag"
	bb.Size = UDim2.fromOffset(140, 26)
	bb.StudsOffset = Vector3.new(0, 1.4, 0)
	bb.AlwaysOnTop = true
	bb.Parent = handle
	local t = Instance.new("TextLabel")
	t.BackgroundColor3 = color
	t.BackgroundTransparency = 0.2
	t.BorderSizePixel = 0
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 14
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = text
	t.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = t
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function baseTool(name, smell, tip)
	local old = StarterPack:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = true
	tool.RequiresHandle = true
	tool:SetAttribute("Smell", smell)
	tool.ToolTip = tip
	return tool
end

local banana = baseTool("Banana", "attract", "Ripe fruit. The fly should approach.")
local bh = Instance.new("Part")
bh.Name = "Handle"
bh.Size = Vector3.new(0.35, 0.35, 1.7)
bh.Color = Color3.fromRGB(245, 210, 55)
bh.Material = Enum.Material.SmoothPlastic
bh.CanCollide = false
bh.Massless = true
bh.Parent = banana
tag(bh, "ripe attract", Color3.fromRGB(80, 120, 20))
banana.Parent = StarterPack

local apple = baseTool("Apple", "attract", "Ripe fruit. The fly should approach.")
local ah = Instance.new("Part")
ah.Name = "Handle"
ah.Shape = Enum.PartType.Ball
ah.Size = Vector3.new(1, 1, 1)
ah.Color = Color3.fromRGB(200, 40, 45)
ah.Material = Enum.Material.SmoothPlastic
ah.CanCollide = false
ah.Massless = true
ah.Parent = apple
local stem = Instance.new("Part")
stem.Name = "Stem"
stem.Size = Vector3.new(0.12, 0.35, 0.12)
stem.Color = Color3.fromRGB(70, 45, 20)
stem.CanCollide = false
stem.Massless = true
stem.CFrame = ah.CFrame * CFrame.new(0, 0.55, 0)
stem.Parent = apple
weld(ah, stem)
tag(ah, "ripe attract", Color3.fromRGB(80, 120, 20))
apple.Parent = StarterPack

local grapes = baseTool("Grapes", "attract", "Ripe fruit. The fly should approach.")
local gh = Instance.new("Part")
gh.Name = "Handle"
gh.Shape = Enum.PartType.Ball
gh.Size = Vector3.new(0.45, 0.45, 0.45)
gh.Color = Color3.fromRGB(110, 40, 150)
gh.Material = Enum.Material.SmoothPlastic
gh.CanCollide = false
gh.Massless = true
gh.Parent = grapes
for i = 1, 6 do
	local g = Instance.new("Part")
	g.Name = "Grape"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.new(0.38, 0.38, 0.38)
	g.Color = Color3.fromRGB(90 + i * 6, 30, 140)
	g.CanCollide = false
	g.Massless = true
	g.CFrame = gh.CFrame * CFrame.new((i % 3 - 1) * 0.28, -0.2 - math.floor((i - 1) / 3) * 0.28, 0.15)
	g.Parent = grapes
	weld(gh, g)
end
tag(gh, "ripe attract", Color3.fromRGB(80, 120, 20))
grapes.Parent = StarterPack

local pine = baseTool("Pineapple", "repel", "Bad smell. The fly should flee.")
local ph = Instance.new("Part")
ph.Name = "Handle"
ph.Size = Vector3.new(0.9, 1.4, 0.9)
ph.Color = Color3.fromRGB(230, 170, 40)
ph.Material = Enum.Material.Sand
ph.CanCollide = false
ph.Massless = true
ph.Parent = pine
local crown = Instance.new("Part")
crown.Name = "Crown"
crown.Size = Vector3.new(0.7, 0.7, 0.7)
crown.Color = Color3.fromRGB(40, 130, 50)
crown.CanCollide = false
crown.Massless = true
crown.CFrame = ph.CFrame * CFrame.new(0, 1.05, 0)
crown.Parent = pine
weld(ph, crown)
tag(ph, "STENCH repel", Color3.fromRGB(90, 20, 20))
pine.Parent = StarterPack

return "ok"
