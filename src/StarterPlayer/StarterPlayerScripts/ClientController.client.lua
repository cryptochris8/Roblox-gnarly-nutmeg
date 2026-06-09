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
local InputController = require(scripts:WaitForChild("InputController"))

HudUI.mount(playerGui)
MenuUI.mount(playerGui)
InputController.start(HudUI)

Remotes.get(Remotes.MatchState).OnClientEvent:Connect(function(snap)
	HudUI.updateMatch(snap)
end)
Remotes.get(Remotes.Countdown).OnClientEvent:Connect(function(n)
	HudUI.countdown(n)
end)
Remotes.get(Remotes.GoalScored).OnClientEvent:Connect(function(info)
	HudUI.goal(info)
end)
Remotes.get(Remotes.StaminaUpdate).OnClientEvent:Connect(function(frac)
	HudUI.stamina(frac)
end)
Remotes.get(Remotes.PossessionChanged).OnClientEvent:Connect(function(userId)
	HudUI.possession(userId == player.UserId)
end)
Remotes.get(Remotes.Toast).OnClientEvent:Connect(function(text)
	HudUI.toast(text)
end)

-- We're ready: ask the server for the current match state.
Remotes.get(Remotes.RequestInitialState):FireServer()
