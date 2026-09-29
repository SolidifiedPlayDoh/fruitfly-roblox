-- Jev, a separate grey player. The fruit fly keeps the Rig and port 8765.
-- Run: uv run jev-roblox

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local JEV_URL = "http://127.0.0.1:8766/see"
local RAY_DISTANCE = 80

local rig = workspace:WaitForChild("Jev")
local humanoid = rig:WaitForChild("Humanoid")
local root = rig:WaitForChild("HumanoidRootPart")
local head = rig:WaitForChild("Head")

humanoid.AutoRotate = true
humanoid.WalkSpeed = 16
humanoid.JumpPower = 50
humanoid.DisplayName = "Jev"
humanoid.NameDisplayDistance = 100
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
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

local spendGui = Instance.new("BillboardGui")
spendGui.Name = "JevSpend"
spendGui.AlwaysOnTop = true
spendGui.LightInfluence = 0
spendGui.MaxDistance = 200
spendGui.Size = UDim2.fromOffset(150, 28)
spendGui.StudsOffset = Vector3.new(0, 3.2, 0)
spendGui.Parent = head

local spendLabel = Instance.new("TextLabel")
spendLabel.Name = "Amount"
spendLabel.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
spendLabel.BackgroundTransparency = 0.25
spendLabel.BorderSizePixel = 0
spendLabel.Size = UDim2.fromScale(1, 1)
spendLabel.Font = Enum.Font.GothamBold
spendLabel.TextSize = 16
spendLabel.TextColor3 = Color3.fromRGB(236, 236, 236)
spendLabel.Text = "$0.00000 / $2"
spendLabel.Parent = spendGui

local spendCorner = Instance.new("UICorner")
spendCorner.CornerRadius = UDim.new(0, 6)
spendCorner.Parent = spendLabel

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

local turnToken = nil
local yawLeft = 0

local lastDrive = {
	forward = 0,
	turn = 0,
	jump = false,
	choice = "idle",
	source = "offline",
}
local jumpReady = 0

local function bearing(worldPos)
	local rel = root.CFrame:PointToObjectSpace(worldPos)
	local flat = Vector3.new(worldPos.X - root.Position.X, 0, worldPos.Z - root.Position.Z)
	local dist = flat.Magnitude
	local angle = math.deg(math.atan2(rel.X, -rel.Z))
	local where = if angle >= 0 then "behind right" else "behind left"
	if angle > -30 and angle < 30 then
		where = "ahead"
	elseif angle >= 30 and angle < 120 then
		where = "right"
	elseif angle <= -30 and angle > -120 then
		where = "left"
	end
	return where, dist
end

local function canSee(model, part)
	local delta = part.Position - head.Position
	if delta.Magnitude < 0.05 then
		return true
	end
	local hit = workspace:Raycast(head.Position, delta, rayParams)
	return hit == nil or hit.Instance:IsDescendantOf(model)
end

local function describeCharacter(model, label)
	if not model or model == rig then
		return nil
	end
	local part = model:FindFirstChild("HumanoidRootPart")
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local where, dist = bearing(part.Position)
	if dist > 90 then
		return nil
	end
	return {
		name = label,
		kind = "character",
		where = where,
		distance = dist,
		visible = canSee(model, part),
	}
end

local function classifyHit(inst, hit)
	local model = inst:FindFirstAncestorWhichIsA("Model")
	if model == rig then
		return "self", inst.Name
	end
	if model and Players:GetPlayerFromCharacter(model) then
		return "character", "the other player"
	end
	if model and model.Name == "Rig" then
		return "character", "fruit fly"
	end
	if math.abs(hit.Normal.Y) > 0.65 then
		return "ground", inst.Name
	end
	if inst.CanCollide then
		return "wall", "wall"
	end
	return "object", inst.Name
end

local function findExit()
	local direct = workspace:FindFirstChild("MazeExit")
	if direct then
		return direct
	end
	local maze = workspace:FindFirstChild("Maze")
	if maze then
		return maze:FindFirstChild("MazeExit", true)
	end
	return nil
end

local SENSE_RANGE = 48
local REACH_APPLE = 7
local trail = {}
local trailClock = 0
local finished = false
local raceStart = os.clock()
local spentAtStart = nil
local lastSpent = 0
local announced = false
local finishElapsed = 0

local function announceFinish()
	if not announced then
		announced = true
		finishElapsed = os.clock() - raceStart
	end
	local cost = 0
	if spentAtStart ~= nil then
		cost = math.max(0, lastSpent - spentAtStart)
	end
	rig:SetAttribute("FinishSeconds", finishElapsed)
	rig:SetAttribute("FinishCost", cost)
end

local function markFinished()
	finished = true
	announceFinish()
end
local stepping = false
local stepGoal = 0
local stepStart = nil

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
	local exitPart = findExit()
	if exitPart and exitPart:IsA("BasePart") then
		return exitPart.Position
	end
	if exitPart and exitPart:IsA("Model") then
		local part = exitPart.PrimaryPart or exitPart:FindFirstChildWhichIsA("BasePart")
		if part then
			return part.Position
		end
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

local function flatWalked(fromPos)
	local delta = root.Position - fromPos
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function flatBasis()
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
	if look.Magnitude < 0.05 or right.Magnitude < 0.05 then
		return nil, nil
	end
	return look.Unit, right.Unit
end

local function refreshSenseIgnore()
	local ignore = { rig }
	local other = workspace:FindFirstChild("Rig")
	if other then
		table.insert(ignore, other)
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function sampleMaze()
	local exitPart = findExit()
	if not exitPart then
		return nil
	end
	refreshSenseIgnore()
	local look, right = flatBasis()
	if not look then
		return nil
	end
	local origin = root.Position + Vector3.new(0, 2, 0)
	local distances = {}
	for deg = 0, 345, 15 do
		local rad = math.rad(deg)
		local dir = look * math.cos(rad) + right * math.sin(rad)
		local hit = workspace:Raycast(origin, dir * SENSE_RANGE, rayParams)
		local studs = SENSE_RANGE
		if hit then
			studs = hit.Distance
		end
		table.insert(distances, {
			bearing = deg,
			studs = math.floor(studs + 0.5),
			trail = math.floor(scentToward(dir) * 100) / 100,
		})
	end
	local applePart = exitPart
	local maze = workspace:FindFirstChild("Maze")
	local appleInst = maze and maze:FindFirstChild("Apple")
	if appleInst and appleInst:IsA("Model") then
		appleInst = appleInst.PrimaryPart or appleInst:FindFirstChildWhichIsA("BasePart")
	end
	if appleInst and appleInst:IsA("BasePart") then
		applePart = appleInst
	end
	local flat = Vector3.new(applePart.Position.X - root.Position.X, 0, applePart.Position.Z - root.Position.Z)
	local rel = root.CFrame:PointToObjectSpace(applePart.Position)
	local angle = math.deg(math.atan2(rel.X, -rel.Z))
	if angle < 0 then
		angle += 360
	end
	local appleStuds = math.floor(flat.Magnitude + 0.5)
	local appleWord = "ripe apple, the smell is good"
	if appleStuds < 6 then
		appleWord = "you are at the apple. eat it"
	end
	return {
		distances = distances,
		exit = appleWord,
		exit_degrees = math.floor(angle + 0.5) % 360,
		exit_studs = appleStuds,
		apple = appleWord,
		apple_degrees = math.floor(angle + 0.5) % 360,
		apple_studs = appleStuds,
	}
end

local function sampleVision()
	refreshSenseIgnore()
	local objects = {}
	local seen = {}
	local eye = (root.CFrame * CFrame.new(0, 1.2, -0.4)).Position
	for iy = -1, 1 do
		for ix = -4, 4 do
			local look = (root.CFrame * CFrame.Angles(math.rad(iy * 8), math.rad(ix * 12), 0)).LookVector
			local hit = workspace:Raycast(eye, look * RAY_DISTANCE, rayParams)
			if hit and hit.Instance then
				local kind, labelName = classifyHit(hit.Instance, hit)
				if kind ~= "ground" and kind ~= "self" and kind ~= "character" then
					local id = kind .. ":" .. labelName .. ":" .. tostring(math.floor(hit.Position.X)) 
					if not seen[id] then
						seen[id] = true
						local rel = root.CFrame:PointToObjectSpace(hit.Position)
						local where = "ahead"
						if rel.X > 3 then
							where = "right"
						elseif rel.X < -3 then
							where = "left"
						end
						table.insert(objects, {
							name = labelName,
							kind = kind,
							where = where,
							distance = hit.Distance,
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
	for i = 1, math.min(4, #objects) do
		keep[i] = objects[i]
	end

	local characters = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local described = describeCharacter(player.Character, "the other player")
		if described then
			table.insert(characters, described)
		end
	end
	local fly = describeCharacter(workspace:FindFirstChild("Rig"), "fruit fly")
	if fly then
		table.insert(characters, fly)
	end

	local ground = workspace:Raycast(root.Position, Vector3.new(0, -80, 0), rayParams)
	local altitude = if ground then ground.Distance else 80
	local look = root.CFrame.LookVector
	return {
		characters = characters,
		objects = keep,
		airborne = altitude > 4.5,
		pose = {
			x = math.floor(root.Position.X * 10) / 10,
			z = math.floor(root.Position.Z * 10) / 10,
			facing = math.floor(math.deg(math.atan2(look.X, look.Z)) + 0.5),
		},
		maze = sampleMaze(),
	}
end

local function askJev(vision)
	local body = HttpService:JSONEncode(vision)
	local response = HttpService:PostAsync(JEV_URL, body, Enum.HttpContentType.ApplicationJson, false)
	return HttpService:JSONDecode(response)
end

task.spawn(function()
	while true do
		if reachedApple() then
			markFinished()
		end
		if finished then
			lastDrive = { forward = 0, turn = 0, jump = false, choice = "idle", studs = 0, source = "finished" }
			stepping = false
			task.wait(0.25)
			continue
		end
		if stepping then
			task.wait(0.05)
			continue
		end
		local ok, result = pcall(function()
			return askJev(sampleVision())
		end)
		if ok and typeof(result) == "table" then
			local spent = tonumber(result.spent) or 0
			if spentAtStart == nil then
				spentAtStart = spent
			end
			lastSpent = spent
			if finished then
				announceFinish()
				continue
			end
			lastDrive = result
			local choice = tostring(result.choice or "")
			if choice == "forward" then
				stepping = true
				stepGoal = tonumber(result.studs) or 8
				stepStart = root.Position
			else
				stepping = false
				stepGoal = 0
				stepStart = nil
			end
			lastSpent = spent
			local cap = tonumber(result.cap) or 2
			local spentValue = rig:FindFirstChild("Spent")
			local capValue = rig:FindFirstChild("Cap")
			if spentValue and spentValue:IsA("NumberValue") then
				spentValue.Value = spent
			end
			if capValue and capValue:IsA("NumberValue") then
				capValue.Value = cap
			end
			spendGui.Size = UDim2.fromOffset(160, 44)
			spendLabel.Text = string.format(
				"%s\n$%.5f / $%g",
				tostring(result.choice or result.bout or ""),
				spent,
				cap
			)
		end
		task.wait(0.15)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	dropTrail(dt)
	if reachedApple() then
		markFinished()
	end
	if finished then
		stepping = false
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)
		if walkTrack.IsPlaying then
			walkTrack:Stop(0.2)
		end
		return
	end

	local forward = math.clamp(tonumber(lastDrive.forward) or 0, -1, 1)
	local turn = math.clamp(tonumber(lastDrive.turn) or 0, -1, 1)
	local choice = tostring(lastDrive.choice or "")

	local bumperHit = workspace:Raycast(root.Position + Vector3.new(0, 2, 0), root.CFrame.LookVector * 4, rayParams)
	local blocked = bumperHit and math.abs(bumperHit.Normal.Y) < 0.55 and bumperHit.Distance < 3.5 and choice == "forward"

	humanoid.AutoRotate = true
	humanoid.PlatformStand = false

	local intent = 0
	if choice == "turn_left" or choice == "turn_right" then
		humanoid.AutoRotate = false
		local token = tonumber(lastDrive.t) or 0
		if turnToken ~= token then
			turnToken = token
			yawLeft = 36
		end
		if yawLeft > 0 then
			local step = math.min(100 * dt, yawLeft)
			yawLeft -= step
			local yaw = if choice == "turn_left" then -1 else 1
			root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(yaw * step), 0)
		end
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)
	elseif choice == "forward" and stepping and stepStart then
		local walked = flatWalked(stepStart)
		if blocked or walked >= stepGoal then
			stepping = false
			humanoid.WalkSpeed = 0
			humanoid:Move(Vector3.zero, false)
		else
			intent = 1
			humanoid.WalkSpeed = 16
			humanoid:Move(root.CFrame.LookVector, false)
		end
	else
		local worldDir = (root.CFrame.LookVector * forward) + (root.CFrame.RightVector * turn)
		intent = math.clamp(worldDir.Magnitude, 0, 1)
		humanoid.WalkSpeed = 16 * intent
		if intent > 0.05 then
			humanoid:Move(worldDir.Unit, false)
		else
			humanoid:Move(Vector3.zero, false)
		end
	end

	if lastDrive.jump == true and os.clock() > jumpReady and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid.Jump = true
		jumpReady = os.clock() + 0.8
	end

	if intent > 0.08 then
		if not walkTrack.IsPlaying then
			walkTrack:Play(0.15)
		end
		walkTrack:AdjustSpeed(0.6 + intent)
	elseif walkTrack.IsPlaying then
		walkTrack:Stop(0.2)
	end
end)
