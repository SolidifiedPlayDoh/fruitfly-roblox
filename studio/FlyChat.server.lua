-- Player Roblox chat goes to the fly. Python + local Ollama llama3.2 answers.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CHAT_URL = "http://127.0.0.1:8765/chat"

local ev = ReplicatedStorage:FindFirstChild("FlyChat")
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = "FlyChat"
	ev.Parent = ReplicatedStorage
end

local bubble = workspace:WaitForChild("Rig"):FindFirstChild("FlySpeech")
if not bubble then
	bubble = Instance.new("StringValue")
	bubble.Name = "FlySpeech"
	bubble.Parent = workspace.Rig
end

local busy = false
local recent = {}

local function askFly(player, text)
	text = tostring(text or "")
	text = text:sub(1, 200)
	if text == "" or text:sub(1, 1) == "/" then
		return
	end
	local now = os.clock()
	local rec = recent[player.UserId]
	if rec and rec.text == text and (now - rec.t) < 1.25 then
		return
	end
	recent[player.UserId] = { text = text, t = now }
	if busy then
		ev:FireClient(player, "...busy buzzing")
		return
	end
	busy = true
	local ok, raw = pcall(function()
		return HttpService:PostAsync(
			CHAT_URL,
			HttpService:JSONEncode({ text = text, player = player.Name }),
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)
	local reply = "zzz"
	if ok then
		local decoded = HttpService:JSONDecode(raw)
		if typeof(decoded) == "table" then
			reply = tostring(decoded.reply or "...")
		end
	else
		reply = "no mouth-brain"
	end
	bubble.Value = reply
	ev:FireAllClients(reply)
	busy = false
end

ev.OnServerEvent:Connect(askFly)

local function hook(player)
	player.Chatted:Connect(function(msg)
		askFly(player, msg)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	hook(player)
end
Players.PlayerAdded:Connect(hook)
