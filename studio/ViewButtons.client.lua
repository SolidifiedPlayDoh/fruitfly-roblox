-- Jev and Fruit fly each cycle: eyes -> orbit -> home.
-- Home is the overhead shot while that button is on, otherwise your character.
-- Overhead is the Studio camera as it was framed over the maze, looking straight down.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local OVERHEAD = CFrame.new(
	200.491531, 75.599136, 112.993561,
	-0.999986, -0.001197, 0,
	0, 0, 1,
	-0.001197, 0.999986, 0
)

local savedMin = player.CameraMinZoomDistance
local savedMax = player.CameraMaxZoomDistance

local subjectName = nil
local mode = "player"
local overheadOn = false
local config = {
	Jev = { raysOverhead = true, open = false },
	Rig = { raysOverhead = true, open = false },
}

local gui = Instance.new("ScreenGui")
gui.Name = "ViewButtons"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.BackgroundTransparency = 1
bar.Position = UDim2.new(0.5, 0, 1, -20)
bar.Size = UDim2.fromOffset(460, 46)
bar.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.Parent = bar

local buttons = {}

local function makeButton(name, labelText, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(140, 46)
	button.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = color
	button.Text = labelText
	button.AutoButtonColor = true
	button.Parent = bar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	buttons[name] = button
	return button
end

makeButton("Jev", "Jev", Color3.fromRGB(232, 120, 196))
makeButton("Rig", "Fruit fly", Color3.fromRGB(255, 196, 90))
makeButton("Overhead", "Overhead", Color3.fromRGB(186, 214, 255))

local column = Instance.new("Frame")
column.Name = "ConfigPanels"
column.BackgroundTransparency = 1
column.Position = UDim2.fromOffset(16, 104)
column.Size = UDim2.fromOffset(230, 0)
column.AutomaticSize = Enum.AutomaticSize.Y
column.Parent = gui

local columnLayout = Instance.new("UIListLayout")
columnLayout.FillDirection = Enum.FillDirection.Vertical
columnLayout.Padding = UDim.new(0, 8)
columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnLayout.Parent = column

local function makePanel(order, key, title, accent)
	local panel = Instance.new("Frame")
	panel.Name = key
	panel.LayoutOrder = order
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Parent = column
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel
	local panelLayout = Instance.new("UIListLayout")
	panelLayout.FillDirection = Enum.FillDirection.Vertical
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Parent = panel

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 36)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 15
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = accent
	header.AutoButtonColor = true
	header.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.LayoutOrder = 2
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Visible = false
	body.Parent = panel
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 2)
	bodyLayout.Parent = body
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingLeft = UDim.new(0, 10)
	bodyPad.PaddingRight = UDim.new(0, 10)
	bodyPad.PaddingBottom = UDim.new(0, 8)
	bodyPad.Parent = body

	local function refreshHeader()
		local mark = if config[key].open then "▾" else "▸"
		header.Text = "   " .. title .. "    " .. mark
		body.Visible = config[key].open
	end

	header.MouseButton1Click:Connect(function()
		config[key].open = not config[key].open
		refreshHeader()
	end)
	refreshHeader()

	local function addToggle(labelText, field)
		local row = Instance.new("TextButton")
		row.Name = field
		row.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Text = ""
		row.AutoButtonColor = true
		row.Parent = body
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(10, 0)
		label.Size = UDim2.new(1, -70, 1, 0)
		label.Font = Enum.Font.Gotham
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(230, 230, 235)
		label.Text = labelText
		label.Parent = row

		local pill = Instance.new("TextLabel")
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.new(1, -8, 0.5, 0)
		pill.Size = UDim2.fromOffset(42, 20)
		pill.Font = Enum.Font.GothamBold
		pill.TextSize = 12
		pill.TextColor3 = Color3.fromRGB(16, 16, 18)
		pill.Parent = row
		local pillCorner = Instance.new("UICorner")
		pillCorner.CornerRadius = UDim.new(0, 5)
		pillCorner.Parent = pill

		local function refreshToggle()
			local on = config[key][field] == true
			pill.Text = if on then "On" else "Off"
			pill.BackgroundColor3 = if on then accent else Color3.fromRGB(90, 90, 98)
			pill.TextColor3 = if on then Color3.fromRGB(16, 16, 18) else Color3.fromRGB(210, 210, 215)
		end

		row.MouseButton1Click:Connect(function()
			config[key][field] = not config[key][field]
			refreshToggle()
		end)
		refreshToggle()
	end

	addToggle("Rays in overhead", "raysOverhead")
end

makePanel(1, "Jev", "Jev", Color3.fromRGB(232, 120, 196))
makePanel(2, "Rig", "Fruit fly", Color3.fromRGB(255, 196, 90))

local function buttonCaption(name, title)
	if subjectName ~= name or mode == "player" then
		return title
	end
	if mode == "eyes" then
		return title .. "  ·  eyes"
	end
	return title .. "  ·  orbit"
end

local function refreshButtons()
	buttons.Jev.Text = buttonCaption("Jev", "Jev")
	buttons.Rig.Text = buttonCaption("Rig", "Fruit fly")
	buttons.Overhead.Text = if overheadOn then "Overhead  ·  on" else "Overhead"
	buttons.Overhead.BackgroundColor3 = if overheadOn
		then Color3.fromRGB(42, 58, 88)
		else Color3.fromRGB(24, 24, 28)
end

local function modelFor(name)
	return workspace:FindFirstChild(name)
end

local function ownHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function showPlayer()
	subjectName = nil
	mode = "player"
	player.CameraMinZoomDistance = savedMin
	player.CameraMaxZoomDistance = savedMax
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = ownHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function showOverhead()
	subjectName = nil
	mode = "overhead"
	player.CameraMinZoomDistance = savedMin
	player.CameraMaxZoomDistance = savedMax
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = OVERHEAD
end

local function releaseCamera()
	if overheadOn then
		showOverhead()
	else
		showPlayer()
	end
	refreshButtons()
end

local function click(name)
	if subjectName ~= name then
		subjectName = name
		mode = "eyes"
	elseif mode == "eyes" then
		mode = "orbit"
	else
		releaseCamera()
		return
	end
	refreshButtons()
end

buttons.Jev.MouseButton1Click:Connect(function()
	click("Jev")
end)
buttons.Rig.MouseButton1Click:Connect(function()
	click("Rig")
end)
buttons.Overhead.MouseButton1Click:Connect(function()
	overheadOn = not overheadOn
	if overheadOn then
		showOverhead()
	else
		showPlayer()
	end
	refreshButtons()
end)

local raysFolder = Instance.new("Folder")
raysFolder.Name = "ViewRays"
raysFolder.Parent = camera

local pool = {}

local function rayPart(index)
	local part = pool[index]
	if part then
		return part
	end
	part = Instance.new("Part")
	part.Name = "Ray"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.45
	part.Parent = raysFolder
	pool[index] = part
	return part
end

local function hideRays()
	for _, part in ipairs(pool) do
		part.Transparency = 1
	end
end

local function drawRay(index, origin, direction, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local hit = workspace:Raycast(origin, direction, params)
	local length = if hit then hit.Distance else direction.Magnitude
	local part = rayPart(index)
	part.Transparency = 0.35
	local reach = math.clamp(length / math.max(direction.Magnitude, 0.05), 0, 1)
	if hit and (hit.Instance.Name == "MazeExit" or (hit.Instance.Parent and hit.Instance.Parent.Name == "MazeExit")) then
		part.Color = Color3.fromRGB(255, 210, 60)
	else
		part.Color = Color3.fromRGB(
			math.floor(255 * (1 - reach)),
			math.floor(70 + 170 * reach),
			math.floor(50 * (1 - reach))
		)
	end
	part.Size = Vector3.new(0.08, 0.08, math.max(length, 0.05))
	part.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -length / 2)
end

local function visionRays(model, startIndex)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return startIndex
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
	if look.Magnitude < 0.05 or right.Magnitude < 0.05 then
		return startIndex
	end
	look = look.Unit
	right = right.Unit
	local origin = root.Position + Vector3.new(0, 2, 0)
	local index = startIndex
	for deg = 0, 345, 15 do
		local rad = math.rad(deg)
		local dir = look * math.cos(rad) + right * math.sin(rad)
		index += 1
		drawRay(index, origin, dir * 48, model)
	end
	return index
end

local function hideRaysFrom(index)
	for cursor = index, #pool do
		pool[cursor].Transparency = 1
	end
end

RunService:BindToRenderStep("ViewButtonsCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if mode == "overhead" then
		local drawn = 0
		local function drawIf(name)
			if not config[name].raysOverhead then
				return
			end
			local model = modelFor(name)
			if model then
				drawn = visionRays(model, drawn)
			end
		end
		drawIf("Jev")
		drawIf("Rig")
		if drawn == 0 then
			hideRays()
		else
			hideRaysFrom(drawn + 1)
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = OVERHEAD
		return
	end
	local model = subjectName and modelFor(subjectName)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local head = model and model:FindFirstChild("Head")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if mode == "player" or not root or not head or not humanoid then
		hideRays()
		if mode ~= "player" then
			releaseCamera()
		end
		return
	end
	hideRaysFrom(visionRays(model, 0) + 1)
	if mode == "eyes" then
		local eye = head.Position + root.CFrame.LookVector * 0.55
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(eye, eye + root.CFrame.LookVector)
	else
		player.CameraMinZoomDistance = 10
		player.CameraMaxZoomDistance = 32
		camera.CameraType = Enum.CameraType.Custom
		if camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	end
end)

refreshButtons()
