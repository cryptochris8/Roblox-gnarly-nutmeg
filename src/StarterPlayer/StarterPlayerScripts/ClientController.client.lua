-- ClientController (client entry point)
-- Boots the UI, wires server -> client events, starts input, and tells the server
-- we're ready. Respawn-safe: this runs once and the UI uses ResetOnSpawn = false.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))

local scripts = script.Parent
local HudUI = require(scripts:WaitForChild("HudUI"))
local MenuUI = require(scripts:WaitForChild("MenuUI"))
local QuestUI = require(scripts:WaitForChild("QuestUI"))
local InputController = require(scripts:WaitForChild("InputController"))
local CameraDirector = require(scripts:WaitForChild("CameraDirector"))
local CarryController = require(scripts:WaitForChild("CarryController"))
local GoalFx = require(scripts:WaitForChild("GoalFx"))
local PhotoMode = require(scripts:WaitForChild("PhotoMode"))
local GoalMarker = require(scripts:WaitForChild("GoalMarker"))
local PenaltyUI = require(scripts:WaitForChild("PenaltyUI"))

HudUI.mount(playerGui)
MenuUI.mount(playerGui)
QuestUI.mount(playerGui)
PenaltyUI.mount(playerGui)
InputController.start(HudUI)
PhotoMode.init()
GoalMarker.init()

-- Roblox's chat window defaults to the TOP-LEFT — exactly where our between-match
-- buttons live (Team / 🏆 Trophy / 👕 Locker / 📋 Quests / ❓ Help), so an open chat
-- covered them. Move the chat to the TOP-RIGHT instead. The config object is created
-- automatically by TextChatService, so poll briefly for it on a fresh client.
task.spawn(function()
	local TextChatService = game:GetService("TextChatService")
	local cfg = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	local tries = 0
	while not cfg and tries < 25 do
		task.wait(0.2)
		cfg = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		tries += 1
	end
	if cfg then
		cfg.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
end)

Remotes.get(Remotes.MatchState).OnClientEvent:Connect(function(snap)
	HudUI.updateMatch(snap)
	-- keep the pitch clear during live play: menus close (and on mobile fully
	-- hide), returning only between matches
	if snap then
		local p = snap.phase
		local active = (p == "Countdown" or p == "Playing" or p == "GoalPause" or p == "Shootout")
		MenuUI.matchActive(active)
		QuestUI.matchActive(active)
		if MenuUI.setShootoutMode then
			MenuUI.setShootoutMode(snap.shootoutMode)
		end
		GoalMarker.refresh() -- team can flip between matches
	end
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
local equippedCelebration = "groove" -- updated from ProgressionSync (the locker)
local function celebrateLocally(isScorer)
	pcall(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		local picked = Cosmetics.celebration(equippedCelebration)
		local id = isScorer and ((picked and picked.animId) or DANCE_IDS[math.random(#DANCE_IDS)]) or CHEER_ID
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
	PhotoMode.exit() -- the replay takes the camera
	task.spawn(CameraDirector.goalReplay, info)
	task.spawn(GoalFx.goal, info)
	if info and player.Team and player.Team.Name == info.team then
		-- match the scorer by UserId, not DisplayName (names aren't unique)
		task.spawn(celebrateLocally, info.scorerUserId == player.UserId)
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
	if data and MenuUI.cosmetics then
		MenuUI.cosmetics(data.cosmetics, data.level)
	end
end)
Remotes.get(Remotes.Toast).OnClientEvent:Connect(function(text)
	HudUI.toast(text)
end)
Remotes.get(Remotes.XpGain).OnClientEvent:Connect(function(amount, label)
	HudUI.xpGain(amount, label)
end)
Remotes.get(Remotes.MatchSummary).OnClientEvent:Connect(function(data)
	HudUI.matchSummary(data)
end)
-- Shootout: frame every kick with the broadcast penalty camera; if it's MY kick,
-- raise the pick-a-corner aim UI. Clears when the server says the kick is done.
Remotes.get(Remotes.Penalty).OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then
		return
	end
	if info.active then
		CameraDirector.penalty(info.spot, info.goalCenter)
		if info.shooterUserId == player.UserId then
			PenaltyUI.show()
		end
	else
		CameraDirector.penaltyEnd()
		PenaltyUI.hide()
	end
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
	-- the locker keeps my goal celebration current
	if data and type(data.cosmetics) == "table" and type(data.cosmetics.celebration) == "string" then
		equippedCelebration = data.cosmetics.celebration
	end
	if welcomed or not data or not data.career then
		return
	end
	welcomed = true
	if (tonumber(data.career.matches) or 0) > 0 then
		return -- they already know the drill
	end
	HudUI.toast("👋 Welcome to GNARLY NUTMEG!")
	-- the full HOW-TO card (objective + controls) carries the rest, and stays
	-- reopenable from the ❓ button — better than a few toasts that scroll away
	if MenuUI.showHowTo then
		task.delay(1.0, MenuUI.showHowTo)
	end
end)

-- We're ready: ask the server for the current match state.
Remotes.get(Remotes.RequestInitialState):FireServer()
