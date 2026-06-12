-- ClientController (client entry point)
-- Boots the UI, wires server -> client events, starts input, and tells the server
-- we're ready. Respawn-safe: this runs once and the UI uses ResetOnSpawn = false.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local scripts = script.Parent
local HudUI = require(scripts:WaitForChild("HudUI"))
local MenuUI = require(scripts:WaitForChild("MenuUI"))
local QuestUI = require(scripts:WaitForChild("QuestUI"))
local InputController = require(scripts:WaitForChild("InputController"))
local CameraDirector = require(scripts:WaitForChild("CameraDirector"))
local CarryController = require(scripts:WaitForChild("CarryController"))
local GoalFx = require(scripts:WaitForChild("GoalFx"))

HudUI.mount(playerGui)
MenuUI.mount(playerGui)
QuestUI.mount(playerGui)
InputController.start(HudUI)

Remotes.get(Remotes.MatchState).OnClientEvent:Connect(function(snap)
	HudUI.updateMatch(snap)
end)
Remotes.get(Remotes.Countdown).OnClientEvent:Connect(function(n)
	HudUI.countdown(n)
	CameraDirector.countdown(n)
end)
-- if we respawn or the match state jumps, never leave the camera stranded
Remotes.get(Remotes.MatchState).OnClientEvent:Connect(function(snap)
	if snap and snap.phase ~= "Countdown" then
		CameraDirector.reset()
	end
end)
player.CharacterAdded:Connect(function()
	CameraDirector.reset()
end)
-- HUMANS celebrate from their OWN client: server-played tracks replicate for
-- server-owned bots but NOT for player characters, so without this the human
-- scorer stood frozen while the bots danced around them.
local DANCE_IDS = { 507771019, 507776043, 507777268 }
local CHEER_ID = 507770677
local function celebrateLocally(isScorer)
	pcall(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		local id = isScorer and DANCE_IDS[math.random(#DANCE_IDS)] or CHEER_ID
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. id
		local track = animator:LoadAnimation(a)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.15)
		task.delay(5.2, function()
			track:Stop(0.4)
			track:Destroy()
		end)
	end)
end

Remotes.get(Remotes.GoalScored).OnClientEvent:Connect(function(info)
	task.spawn(CameraDirector.goalReplay, info)
	task.spawn(GoalFx.goal, info)
	if info and player.Team and player.Team.Name == info.team then
		task.spawn(celebrateLocally, info.scorer == player.DisplayName)
	end
	HudUI.goal(info)
end)
Remotes.get(Remotes.StaminaUpdate).OnClientEvent:Connect(function(frac)
	HudUI.stamina(frac)
end)
Remotes.get(Remotes.PossessionChanged).OnClientEvent:Connect(function(userId, team)
	HudUI.possession(userId == player.UserId, team)
	CarryController.possession(userId == player.UserId)
end)
Remotes.get(Remotes.Nutmeg).OnClientEvent:Connect(function(info)
	HudUI.nutmeg(info)
end)
Remotes.get(Remotes.ProgressionSync).OnClientEvent:Connect(function(data)
	HudUI.progression(data)
	QuestUI.progression(data)
end)
Remotes.get(Remotes.Toast).OnClientEvent:Connect(function(text)
	HudUI.toast(text)
end)

-- Tell the player their job in plain words whenever it changes.
local ROLE_CALLOUTS = {
	goalkeeper = "🧤 You're the GOALKEEPER — guard your net!",
	striker = "⚽ You're the STRIKER — go score!",
}
local lastRole = nil
local function announceRole()
	local role = player:GetAttribute("GNRole")
	if type(role) ~= "string" or role == lastRole then
		return
	end
	lastRole = role
	HudUI.toast(ROLE_CALLOUTS[role] or ("📣 You're playing " .. role:upper():gsub("-", " ") .. "!"))
end
player:GetAttributeChangedSignal("GNRole"):Connect(announceRole)
task.delay(3, announceRole)

-- First-ever visit: a six-second welcome that explains the whole game.
local welcomed = false
Remotes.get(Remotes.ProgressionSync).OnClientEvent:Connect(function(data)
	if welcomed or not data or not data.career then
		return
	end
	welcomed = true
	if (tonumber(data.career.matches) or 0) > 0 then
		return -- they already know the drill
	end
	HudUI.toast("👋 Welcome to GNARLY NUTMEG!")
	task.delay(2.2, function()
		HudUI.toast("⚽ Score more goals than the other team!")
	end)
	task.delay(4.4, function()
		HudUI.toast("Pass to friends, hold Shoot to power up, have a blast!")
	end)
end)

-- We're ready: ask the server for the current match state.
Remotes.get(Remotes.RequestInitialState):FireServer()
