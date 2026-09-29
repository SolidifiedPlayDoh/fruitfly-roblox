-- Wires the ViewButtons gui. Does not create or restyle it.
-- Edit text, color, and layout on StarterGui.ViewButtons.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local OVERHEAD = CFrame.new(
	200.491531, 75.599136, 112.993561,
	-0.999986, -0.001197, 0,
	0, 0, 1,
	-0.001197, 0.999986, 0
)

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = OVERHEAD

local gui = player:WaitForChild("PlayerGui"):WaitForChild("ViewButtons")
local bar = gui:WaitForChild("Bar")
local buttons = {
	Jev = bar:WaitForChild("Jev"),
	Rig = bar:WaitForChild("Rig"),
	Overhead = bar:WaitForChild("Overhead"),
}
local panels = gui:WaitForChild("ConfigPanels")

local savedMin = player.CameraMinZoomDistance
local savedMax = player.CameraMaxZoomDistance

local subjectName = nil
local mode = "overhead"
local home = "overhead"
local savedFly = OVERHEAD
local flySpeed = 60
local looking = false
local held = {}

local panelRefs = {}
for _, key in ipairs({ "Jev", "Rig" }) do
	local panel = panels:WaitForChild(key)
	local header = panel:WaitForChild("Header")
	local body = panel:WaitForChild("Body")
	local row = body:WaitForChild("RaysOverhead")
	panelRefs[key] = {
		header = header,
		body = body,
		row = row,
	}
end

local function raysOn(key)
	return panelRefs[key].row:GetAttribute("On") == true
end

for _, key in ipairs({ "Jev", "Rig" }) do
	local refs = panelRefs[key]
	refs.header.MouseButton1Click:Connect(function()
		refs.body.Visible = not refs.body.Visible
	end)
	refs.row.MouseButton1Click:Connect(function()
		refs.row:SetAttribute("On", not raysOn(key))
	end)
end

local function modelFor(name)
	return workspace:FindFirstChild(name)
end

local function unlockLook()
	looking = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function conceal(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(0, -400, 0)
	end
	local function hide(inst)
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 1
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			inst.Transparency = 1
		elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
			inst.Enabled = false
		end
	end
	for _, inst in ipairs(character:GetDescendants()) do
		hide(inst)
	end
	character.DescendantAdded:Connect(hide)
end

task.spawn(function()
	local ok, playerModule = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and playerModule.GetControls then
		playerModule:GetControls():Disable()
	end
end)

if player.Character then
	conceal(player.Character)
end
player.CharacterAdded:Connect(conceal)

local function showOverhead()
	unlockLook()
	subjectName = nil
	home = "overhead"
	mode = "overhead"
	player.CameraMinZoomDistance = savedMin
	player.CameraMaxZoomDistance = savedMax
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = OVERHEAD
end

local function showFly()
	unlockLook()
	subjectName = nil
	home = "fly"
	mode = "fly"
	player.CameraMinZoomDistance = savedMin
	player.CameraMaxZoomDistance = savedMax
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = savedFly
end

local function releaseCamera()
	if home == "fly" then
		showFly()
	else
		showOverhead()
	end
end

local function click(name)
	if subjectName ~= name then
		subjectName = name
		mode = "eyes"
	elseif mode == "eyes" then
		mode = "orbit"
	else
		releaseCamera()
	end
end

buttons.Jev.MouseButton1Click:Connect(function()
	click("Jev")
end)
buttons.Rig.MouseButton1Click:Connect(function()
	click("Rig")
end)
buttons.Overhead.MouseButton1Click:Connect(function()
	if mode == "fly" then
		showOverhead()
	else
		showFly()
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		if mode == "fly" then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		held[input.KeyCode] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		unlockLook()
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		held[input.KeyCode] = nil
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if mode ~= "fly" then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		flySpeed = math.clamp(flySpeed * (1.18 ^ input.Position.Z), 4, 480)
	elseif looking and input.UserInputType == Enum.UserInputType.MouseMovement then
		local pos = savedFly.Position
		local prevY = math.abs(savedFly.LookVector.Y)
		local pitched = savedFly * CFrame.Angles(-input.Delta.Y * 0.003, 0, 0)
		local yawed = CFrame.Angles(0, -input.Delta.X * 0.003, 0) * pitched.Rotation
		local nextY = math.abs(yawed.LookVector.Y)
		if nextY < 0.995 or nextY < prevY then
			savedFly = CFrame.new(pos) * yawed
		else
			savedFly = CFrame.new(pos) * CFrame.Angles(0, -input.Delta.X * 0.003, 0) * savedFly.Rotation
		end
	end
end)

local function keyDown(code)
	return held[code] == true and UserInputService:GetFocusedTextBox() == nil
end

local function stepFly(dt)
	local wish = Vector3.zero
	if keyDown(Enum.KeyCode.W) then
		wish += Vector3.new(0, 0, -1)
	end
	if keyDown(Enum.KeyCode.S) then
		wish += Vector3.new(0, 0, 1)
	end
	if keyDown(Enum.KeyCode.A) then
		wish += Vector3.new(-1, 0, 0)
	end
	if keyDown(Enum.KeyCode.D) then
		wish += Vector3.new(1, 0, 0)
	end
	local lift = 0
	if keyDown(Enum.KeyCode.E) or keyDown(Enum.KeyCode.Space) then
		lift += 1
	end
	if keyDown(Enum.KeyCode.Q) or keyDown(Enum.KeyCode.LeftControl) then
		lift -= 1
	end
	local cf = savedFly
	local speed = flySpeed
	if keyDown(Enum.KeyCode.LeftShift) then
		speed *= 4
	end
	local step = Vector3.zero
	if wish.Magnitude > 0 then
		step += cf:VectorToWorldSpace(wish.Unit) * speed * dt
	end
	if lift ~= 0 then
		step += Vector3.yAxis * lift * speed * dt
	end
	if step.Magnitude > 0 then
		cf += step
	end
	savedFly = cf
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cf
end

local raysFolder = camera:FindFirstChild("ViewRays")
if not raysFolder then
	raysFolder = Instance.new("Folder")
	raysFolder.Name = "ViewRays"
	raysFolder.Parent = camera
end

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

RunService:BindToRenderStep("ViewButtonsCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if mode == "fly" then
		hideRays()
		stepFly(dt)
		return
	end
	if mode == "overhead" then
		local drawn = 0
		local function drawIf(name)
			if not raysOn(name) then
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
	if not root or not head or not humanoid then
		hideRays()
		releaseCamera()
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
