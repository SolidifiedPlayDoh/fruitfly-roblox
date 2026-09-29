-- Ranks the saved Leaderboard. Does not build it.
-- Closer to the apple is higher. #1 gets the crown and the glow.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("Leaderboard")
local board = gui:WaitForChild("Board")

local rows = {
	{ frame = board:WaitForChild("Jev"), modelName = "Jev" },
	{ frame = board:WaitForChild("Rig"), modelName = "Rig" },
}

local function applePart()
	local maze = workspace:FindFirstChild("Maze")
	local apple = maze and maze:FindFirstChild("Apple")
	if apple and apple:IsA("Model") then
		return apple.PrimaryPart or apple:FindFirstChildWhichIsA("BasePart")
	end
	if apple and apple:IsA("BasePart") then
		return apple
	end
	local exitPart = workspace:FindFirstChild("MazeExit")
	if exitPart and exitPart:IsA("BasePart") then
		return exitPart
	end
	if maze then
		exitPart = maze:FindFirstChild("MazeExit", true)
		if exitPart and exitPart:IsA("BasePart") then
			return exitPart
		end
	end
	return nil
end

local function distanceTo(model, apple)
	if not model then
		return 100000
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return 100000
	end
	local delta = Vector3.new(apple.Position.X - root.Position.X, 0, apple.Position.Z - root.Position.Z)
	return delta.Magnitude
end

local pulse = 0
RunService.RenderStepped:Connect(function(dt)
	local apple = applePart()
	if not apple then
		return
	end
	local ranked = {}
	for _, row in ipairs(rows) do
		table.insert(ranked, {
			row = row,
			distance = distanceTo(workspace:FindFirstChild(row.modelName), apple),
		})
	end
	table.sort(ranked, function(a, b)
		return a.distance < b.distance
	end)
	pulse += dt
	local glow = 0.15 + 0.45 * (0.5 + 0.5 * math.sin(pulse * 4))
	for place, entry in ipairs(ranked) do
		local frame = entry.row.frame
		frame.LayoutOrder = place
		local rank = frame:FindFirstChild("Rank")
		local crown = frame:FindFirstChild("Crown")
		if rank and rank:IsA("TextLabel") then
			rank.Text = "#" .. tostring(place)
			local stroke = rank:FindFirstChildOfClass("UIStroke")
			if place == 1 then
				rank.TextColor3 = Color3.fromRGB(255, 214, 90)
				if stroke then
					stroke.Enabled = true
					stroke.Transparency = glow
				end
			else
				rank.TextColor3 = Color3.fromRGB(210, 210, 216)
				if stroke then
					stroke.Enabled = false
				end
			end
		end
		if crown and crown:IsA("GuiObject") then
			crown.Visible = place == 1
		end
	end
end)
