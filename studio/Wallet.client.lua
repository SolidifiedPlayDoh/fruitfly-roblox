-- Updates the saved Wallet gui. Does not build it.
-- Each Jev charge clones the hidden Charge label, floats it, and fades it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("Wallet")
local balance = gui:WaitForChild("Panel"):WaitForChild("Balance")
local chargeTemplate = gui:WaitForChild("Charge")

local jev = workspace:WaitForChild("Jev")
local spentValue = jev:WaitForChild("Spent")
local capValue = jev:WaitForChild("Cap")

local lastSpent = spentValue.Value
local primed = false

local function moneyLeft()
	local cap = capValue.Value
	if cap <= 0 then
		cap = 2
	end
	return math.max(0, cap - spentValue.Value)
end

local function showBalance()
	balance.Text = string.format("$%.6f", moneyLeft())
end

local function floatCharge(amount)
	local label = chargeTemplate:Clone()
	label.Name = "ChargeFloat"
	label.Visible = true
	label.Text = string.format("-$%.6f", amount)
	label.TextTransparency = 0
	label.Parent = gui
	local start = chargeTemplate.Position
	local goal = UDim2.new(start.X.Scale, start.X.Offset, start.Y.Scale, start.Y.Offset - 56)
	local tween = TweenService:Create(
		label,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = goal, TextTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

local function onSpent()
	local delta = spentValue.Value - lastSpent
	lastSpent = spentValue.Value
	showBalance()
	if primed and delta > 0 and delta < 0.01 then
		floatCharge(delta)
	end
	primed = true
end

spentValue.Changed:Connect(onSpent)
capValue.Changed:Connect(showBalance)
showBalance()
primed = true
