-- Fruit fly MaleCNS brain bridge.
-- Compound-eye raycasts go to the local Python MaleCNS process.
-- The NPC Rig is the fly body. Your player character is separate.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BRAIN_URL = "http://127.0.0.1:8765/see"
local RAY_DISTANCE = 90

local rig = workspace:WaitForChild("Rig")
local humanoid = rig:WaitForChild("Humanoid")
local root = rig:WaitForChild("HumanoidRootPart")
local head = rig:WaitForChild("Head")

humanoid.AutoRotate = true
humanoid.WalkSpeed = 26
humanoid.JumpPower = 50
humanoid.DisplayName = "Fruit Fly"
humanoid.Sit = false
humanoid.PlatformStand = false
humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
for _, part in ipairs(rig:GetDescendants()) do
	if part:IsA("BasePart") then
		part.Anchored = false
	end
end
root.Anchored = false
pcall(function()
	root:SetNetworkOwner(nil)
end)

local att = root:FindFirstChild("FlyAttach")
if not att then
	att = Instance.new("Attachment")
	att.Name = "FlyAttach"
	att.Parent = root
end
local flyVel = root:FindFirstChild("FlyVelocity")
if not flyVel then
	flyVel = Instance.new("LinearVelocity")
	flyVel.Name = "FlyVelocity"
	flyVel.Attachment0 = att
	flyVel.RelativeTo = Enum.ActuatorRelativeTo.World
	flyVel.MaxForce = 400000
	flyVel.VectorVelocity = Vector3.zero
	flyVel.Enabled = false
	flyVel.Parent = root
end

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local walkAnim = Instance.new("Animation")
walkAnim.AnimationId = "rbxassetid://180426354"
local walkTrack = animator:LoadAnimation(walkAnim)
walkTrack.Priority = Enum.AnimationPriority.Movement
walkTrack.Looped = true

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { rig }

local SENSE_RANGE = 48

local function refreshSenseIgnore()
	local ignore = { rig }
	local other = workspace:FindFirstChild("Jev")
	if other then
		table.insert(ignore, other)
	end
	rayParams.FilterDescendantsInstances = ignore
end

local REACH_APPLE = 7
local trail = {}
local trailClock = 0
local finished = false
local raceStart = os.clock()
local announced = false

local function announceFinish()
	if announced then
		return
	end
	announced = true
	rig:SetAttribute("FinishSeconds", os.clock() - raceStart)
end

local function markFinished()
	finished = true
	announceFinish()
end

local function trailKey(x, z)
	return string.format("%d:%d", math.floor(x / 8), math.floor(z / 8))
end

local function scentAt(x, z)
	return trail[trailKey(x, z)] or 0
end

local function scentToward(dir)
	local amount = 0
	for _, dist in ipairs({ 8, 16 }) do
		local point = root.Position + dir * dist
		amount = math.max(amount, scentAt(point.X, point.Z))
	end
	return amount
end

local function dropTrail(dt)
	trailClock += dt
	if trailClock < 0.25 then
		return
	end
	trailClock = 0
	for key, value in pairs(trail) do
		local faded = value * 0.985
		if faded < 0.05 then
			trail[key] = nil
		else
			trail[key] = faded
		end
	end
	local key = trailKey(root.Position.X, root.Position.Z)
	trail[key] = math.min((trail[key] or 0) + 0.35, 6)
end

local function applePosition()
	local maze = workspace:FindFirstChild("Maze")
	local apple = maze and maze:FindFirstChild("Apple")
	if apple and apple:IsA("Model") then
		local part = apple.PrimaryPart or apple:FindFirstChildWhichIsA("BasePart")
		if part then
			return part.Position
		end
	elseif apple and apple:IsA("BasePart") then
		return apple.Position
	end
	local exitPart = workspace:FindFirstChild("MazeExit")
	if not (exitPart and exitPart:IsA("BasePart")) and maze then
		exitPart = maze:FindFirstChild("MazeExit", true)
	end
	if exitPart and exitPart:IsA("BasePart") then
		return exitPart.Position
	end
	return nil
end

local function reachedApple()
	local pos = applePosition()
	if not pos then
		return false
	end
	local flat = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
	return flat.Magnitude <= REACH_APPLE
end

local function distanceRing()
	refreshSenseIgnore()
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
	if look.Magnitude < 0.05 or right.Magnitude < 0.05 then
		return {}
	end
	look = look.Unit
	right = right.Unit
	local origin = root.Position + Vector3.new(0, 2, 0)
	local distances = {}
	for deg = 0, 345, 15 do
		local rad = math.rad(deg)
		local dir = look * math.cos(rad) + right * math.sin(rad)
		local hit = workspace:Raycast(origin, dir * SENSE_RANGE, rayParams)
		local studs = if hit then hit.Distance else SENSE_RANGE
		table.insert(distances, {
			bearing = deg,
			distance = studs,
			trail = math.floor(scentToward(dir) * 100) / 100,
		})
	end
	return distances
end

local lastDrive = {
	forward = 0,
	turn = 0,
	jump = false,
	fly = 0,
	up = 0,
	bout = "rest",
	source = "offline",
	spikes = 0,
	neurons = {},
}
local pokeUntil = 0

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Poke the fly"
prompt.ObjectText = "Fruit fly"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.Parent = head
prompt.Triggered:Connect(function()
	pokeUntil = os.clock() + 1.2
end)

local function classifyHit(inst, hit)
	if inst.Name == "MazeExit" or (inst.Parent and inst.Parent.Name == "MazeExit") then
		return "fruit", "exit"
	end
	local tool = inst:FindFirstAncestorWhichIsA("Tool")
	if tool then
		local smell = string.lower(tostring(tool:GetAttribute("Smell") or ""))
		if smell == "repel" or tool.Name:lower():find("pineapple", 1, true) then
			return "repel", tool.Name
		end
		return "fruit", tool.Name
	end
	local model = inst:FindFirstAncestorWhichIsA("Model")
	if model and Players:GetPlayerFromCharacter(model) then
		return "player", "player"
	end
	local lower = inst.Name:lower()
	if lower:find("pineapple", 1, true) then
		return "repel", inst.Name
	end
	if lower:find("fruit", 1, true) or lower == "banana" or lower == "apple" or lower == "grape" or lower == "grapes" or lower == "lime" then
		return "fruit", inst.Name
	end
	if math.abs(hit.Normal.Y) > 0.65 then
		return "ground", inst.Name
	end
	if inst.CanCollide then
		return "wall", inst.Name
	end
	return "world", inst.Name
end

local function smellEntry(tool, handle)
	local rel = root.CFrame:PointToObjectSpace(handle.Position)
	local dist = (handle.Position - root.Position).Magnitude
	local smell = string.lower(tostring(tool:GetAttribute("Smell") or "attract"))
	local kind = if smell == "repel" then "repel" else "fruit"
	return {
		name = tool.Name,
		kind = kind,
		dx = rel.X * 6,
		size = 12,
		distance = dist,
		strength = math.clamp(1.15 - dist / 40, 0.05, 1.2),
		r = handle.Color.R,
		g = handle.Color.G,
		b = handle.Color.B,
	}
end

local function collectSmells()
	local smells = {}
	local function consider(tool)
		if not tool:IsA("Tool") then
			return
		end
		local handle = tool:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then
			return
		end
		if (handle.Position - root.Position).Magnitude > 48 then
			return
		end
		table.insert(smells, smellEntry(tool, handle))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			for _, child in ipairs(char:GetChildren()) do
				consider(child)
			end
		end
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			-- only equipped tools smell strongly; skip backpack
		end
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Tool") then
			consider(inst)
		end
	end
	return smells
end

local function findExit()
	local direct = workspace:FindFirstChild("MazeExit")
	if direct and direct:IsA("BasePart") then
		return direct
	end
	local maze = workspace:FindFirstChild("Maze")
	local nested = maze and maze:FindFirstChild("MazeExit", true)
	if nested and nested:IsA("BasePart") then
		return nested
	end
	return nil
end

local function findApple()
	local maze = workspace:FindFirstChild("Maze")
	local apple = maze and maze:FindFirstChild("Apple")
	if apple and apple:IsA("Model") then
		apple = apple.PrimaryPart or apple:FindFirstChildWhichIsA("BasePart")
	end
	if apple and apple:IsA("BasePart") then
		return apple
	end
	return findExit()
end

local function appleSmell()
	local apple = findApple()
	if not apple then
		return nil
	end
	local flat = Vector3.new(apple.Position.X - root.Position.X, 0, apple.Position.Z - root.Position.Z)
	if flat.Magnitude < 0.5 then
		return nil
	end
	local rel = root.CFrame:PointToObjectSpace(apple.Position)
	local bearing = math.deg(math.atan2(rel.X, -rel.Z))
	if bearing < 0 then
		bearing += 360
	end
	return {
		name = "apple",
		kind = "fruit",
		dx = rel.X * 6,
		bearing = math.floor(bearing + 0.5) % 360,
		apple_studs = math.floor(flat.Magnitude + 0.5),
		size = 18,
		distance = 14,
		strength = 1.5,
		r = 0.78,
		g = 0.16,
		b = 0.18,
	}
end

local function sampleVision()
	local objects = {}
	local seen = {}
	local eye = (root.CFrame * CFrame.new(0, 1.5, 0.45)).Position
	for iy = -2, 2 do
		for ix = -5, 5 do
			local look = (root.CFrame * CFrame.Angles(math.rad(iy * 7), math.rad(ix * 9), 0)).LookVector
			local hit = workspace:Raycast(eye, look * RAY_DISTANCE, rayParams)
			if hit and hit.Instance then
				local inst = hit.Instance
				local kind, labelName = classifyHit(inst, hit)
				if kind ~= "ground" then
					local id = inst:GetFullName() .. ":" .. kind
					if not seen[id] then
						seen[id] = true
						local rel = root.CFrame:PointToObjectSpace(hit.Position)
						table.insert(objects, {
							name = labelName,
							kind = kind,
							dx = rel.X * 6,
							size = math.clamp(inst.Size.Magnitude * 8 / math.max(hit.Distance, 1), 1, 40),
							distance = hit.Distance,
							r = inst.Color.R,
							g = inst.Color.G,
							b = inst.Color.B,
						})
					end
				end
			end
		end
	end
	table.sort(objects, function(a, b)
		return a.distance < b.distance
	end)
	local keep = {}
	for i = 1, math.min(8, #objects) do
		keep[i] = objects[i]
	end
	local ground = workspace:Raycast(root.Position, Vector3.new(0, -80, 0), rayParams)
	local altitude = if ground then ground.Distance else 80
	return {
		objects = keep,
		smells = (function()
			local smells = collectSmells()
			local smell = appleSmell()
			if smell then
				table.insert(smells, smell)
			end
			return smells
		end)(),
		heading = root.Orientation.Y,
		pose = {
			x = math.floor(root.Position.X * 10) / 10,
			z = math.floor(root.Position.Z * 10) / 10,
			facing = math.deg(math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)),
		},
		poke = os.clock() < pokeUntil,
		altitude = altitude,
		airborne = altitude > 4.5,
		distances = distanceRing(),
	}
end

local function askBrain(vision)
	local body = HttpService:JSONEncode(vision)
	local response = HttpService:PostAsync(BRAIN_URL, body, Enum.HttpContentType.ApplicationJson, false)
	return HttpService:JSONDecode(response)
end

local status = Instance.new("StringValue")
status.Name = "FlyBrainStatus"
status.Value = "waiting for MaleCNS on 127.0.0.1:8765"
status.Parent = rig

task.spawn(function()
	while true do
		if reachedApple() then
			markFinished()
		end
		if finished then
			lastDrive = { forward = 0, turn = 0, jump = false, bout = "idle", source = "finished" }
			status.Value = "ate the apple"
			task.wait(0.25)
			continue
		end
		local ok, result = pcall(function()
			return askBrain(sampleVision())
		end)
		if ok and typeof(result) == "table" then
			lastDrive = result
			status.Value = string.format(
				"%s  %s  F=%.2f T=%.2f  %s",
				tostring(result.source or "brain"),
				tostring(result.bout or ""),
				tonumber(result.forward) or 0,
				tonumber(result.turn) or 0,
				tostring(result.memory or "")
			)
		else
			status.Value = "brain offline -- run: uv run fruitfly-roblox"
		end
		task.wait(0.08)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	dropTrail(dt)
	if reachedApple() then
		markFinished()
	end
	if finished then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)
		if walkTrack.IsPlaying then
			walkTrack:Stop(0.2)
		end
		return
	end

	local forward = math.clamp(tonumber(lastDrive.forward) or 0, -1, 1)
	local turn = math.clamp(tonumber(lastDrive.turn) or 0, -1, 1)

	local bumperHit = workspace:Raycast(root.Position + Vector3.new(0, 2, 0), root.CFrame.LookVector * 4, rayParams)
	if bumperHit and math.abs(bumperHit.Normal.Y) < 0.55 and bumperHit.Distance < 2.2 and forward > 0 then
		forward = -0.2
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	flyVel.Enabled = false
	flyVel.VectorVelocity = Vector3.zero

	root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(turn * 120 * dt), 0)
	local intent = math.clamp(math.abs(forward), 0, 1)
	humanoid.WalkSpeed = 26 * intent
	if intent > 0.04 then
		humanoid:Move(root.CFrame.LookVector * math.sign(forward), false)
	else
		humanoid:Move(Vector3.zero, false)
	end

	if intent > 0.08 then
		if not walkTrack.IsPlaying then
			walkTrack:Play(0.15)
		end
		walkTrack:AdjustSpeed(0.4 + 1.4 * intent)
	elseif walkTrack.IsPlaying then
		walkTrack:Stop(0.2)
	end
end)
