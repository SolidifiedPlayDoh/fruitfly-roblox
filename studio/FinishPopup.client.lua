-- Shows the saved finish popups. Does not build them.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FinishPopups")

local function clockText(seconds)
	local total = math.max(0, seconds)
	local minutes = math.floor(total / 60)
	local rest = total - minutes * 60
	return string.format("%d:%04.1f", minutes, rest)
end

local function watch(modelName, frameName, withCost)
	local frame = gui:WaitForChild(frameName)
	local timeLabel = frame:WaitForChild("Time")
	local costLabel = if withCost then frame:WaitForChild("Cost") else nil
	local model = workspace:WaitForChild(modelName)
	local function show()
		local seconds = model:GetAttribute("FinishSeconds")
		if typeof(seconds) ~= "number" then
			return
		end
		timeLabel.Text = clockText(seconds)
		if costLabel then
			local cost = model:GetAttribute("FinishCost")
			costLabel.Text = string.format("$%.4f", tonumber(cost) or 0)
		end
		frame.Visible = true
	end
	model:GetAttributeChangedSignal("FinishSeconds"):Connect(show)
	show()
end

watch("Jev", "Jev", true)
watch("Rig", "Fly", false)
