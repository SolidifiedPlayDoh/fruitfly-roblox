-- HUD only. Fly talks in the normal Roblox chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local player = Players.LocalPlayer
local rig = workspace:WaitForChild("Rig")
local ev = ReplicatedStorage:WaitForChild("FlyChat")

local gui = Instance.new("ScreenGui")
gui.Name = "FlyBrainHud"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
label.BackgroundTransparency = 0.25
label.BorderSizePixel = 0
label.Position = UDim2.fromOffset(16, 16)
label.Size = UDim2.fromOffset(620, 72)
label.Font = Enum.Font.GothamMedium
label.TextSize = 15
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextColor3 = Color3.fromRGB(255, 230, 140)
label.Text = "  Fruit fly"
label.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = label

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingTop = UDim.new(0, 10)
pad.Parent = label

local function postFlyChat(text)
	text = tostring(text or "")
	if text == "" then
		return
	end
	local line = "<font color='#ffcc66'>fruit fly:</font> " .. text
	local ok = pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		if not channels then
			channels = TextChatService:WaitForChild("TextChannels", 5)
		end
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			general:DisplaySystemMessage(line, "FlyNPC")
			return
		end
		error("no RBXGeneral")
	end)
	if not ok then
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = "fruit fly: " .. text,
				Color = Color3.fromRGB(255, 204, 102),
			})
		end)
	end
end

ev.OnClientEvent:Connect(postFlyChat)

TextChatService.MessageReceived:Connect(function(msg)
	if msg.Metadata == "FlyNPC" then
		return
	end
	local src = msg.TextSource
	if not src or src.UserId ~= player.UserId then
		return
	end
	local body = msg.Text or ""
	if body == "" or body:sub(1, 1) == "/" then
		return
	end
	ev:FireServer(body)
end)

while true do
	local st = rig:FindFirstChild("FlyBrainStatus")
	if st then
		label.Text = "  " .. st.Value .. "\n  Chat normally. The fly answers in chat."
	else
		label.Text = "  Fruit fly"
	end
	task.wait(0.15)
end
