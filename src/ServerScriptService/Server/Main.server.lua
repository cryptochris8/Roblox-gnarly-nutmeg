--!strict
-- Main (SERVER ENTRY POINT)
-- Wires Gnarly Nutmeg together in the right order and kicks off the match loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- 1) Create the RemoteEvents before anything tries to use them.
Remotes.setupServer()

-- 2) Load services (they live next to this script).
local PlayerDataService = require(script.Parent.PlayerDataService)
local TeamService = require(script.Parent.TeamService)
local PlayerService = require(script.Parent.PlayerService)
local WorldService = require(script.Parent.WorldService)
local BallService = require(script.Parent.BallService)
local AIService = require(script.Parent.AIService)
local MatchService = require(script.Parent.MatchService)

-- 3) Initialize, in dependency order.
PlayerDataService.init() -- leaderstats + persistence on join/leave
TeamService.init()       -- create the Red/Blue Teams
PlayerService.init()     -- stamina loop + character hooks

local world = WorldService.build() -- build the pitch from code
BallService.init(world)            -- spawn the ball + possession loop
AIService.init()                   -- bot decision loop (idle until a match is active)
MatchService.init(world)           -- match state machine + continuous match loop

-- 4) Wire client input intents. The server validates everything.
local STA = GameConfig.Stamina
local TACKLE = GameConfig.Tackle

Remotes.get(Remotes.RequestPass).OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and BallService.carrierIsPlayer(player) and PlayerService.tryAction(player, "pass", 0.35) then
		PlayerService.spendStamina(player, STA.PassCost)
		BallService.passFrom(char)
	end
end)

Remotes.get(Remotes.RequestShoot).OnServerEvent:Connect(function(player, charge)
	local char = player.Character
	if type(charge) ~= "number" then
		charge = 1
	end
	if char and BallService.carrierIsPlayer(player) and PlayerService.tryAction(player, "shoot", 0.3) then
		PlayerService.spendStamina(player, STA.ShootCost)
		BallService.shootFrom(char, charge)
	end
end)

Remotes.get(Remotes.RequestTackle).OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and not BallService.carrierIsPlayer(player) and PlayerService.tryAction(player, "tackle", TACKLE.Cooldown) then
		PlayerService.spendStamina(player, STA.TackleCost)
		BallService.tackleAttempt(char)
	end
end)

Remotes.get(Remotes.SetSprint).OnServerEvent:Connect(function(player, on)
	PlayerService.setSprint(player, on == true)
end)

Remotes.get(Remotes.SelectTeam).OnServerEvent:Connect(function(player, teamName)
	if type(teamName) == "string" then
		MatchService.selectTeam(player, teamName)
	end
end)

Remotes.get(Remotes.RequestInitialState).OnServerEvent:Connect(function(player)
	MatchService.sendStateTo(player)
end)

print("[Gnarly Nutmeg] Server ready — kickoff incoming! ⚽")
