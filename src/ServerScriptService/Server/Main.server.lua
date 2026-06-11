--!strict
-- Main (SERVER ENTRY POINT)
-- Wires Gnarly Nutmeg together in the right order and kicks off the match loop.

local Players = game:GetService("Players")
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
local BotAnimationService = require(script.Parent.BotAnimationService)
local AIService = require(script.Parent.AIService)
local MatchService = require(script.Parent.MatchService)

-- 3) Initialize, in dependency order.
PlayerDataService.init() -- leaderstats + persistence on join/leave
TeamService.init()       -- create the Red/Blue Teams
PlayerService.init()     -- stamina loop + character hooks

local world = WorldService.build() -- build the pitch from code
BallService.init(world)            -- spawn the ball + possession loop
BotAnimationService.init()         -- animates bot rigs (humans animate themselves)
AIService.init()                   -- bot decision loop (idle until a match is active)
MatchService.init(world)           -- match state machine + continuous match loop

-- 4) Cross-service hooks + client input intents. The server validates everything.
local STA = GameConfig.Stamina
local TACKLE = GameConfig.Tackle
local NUTMEG = GameConfig.Nutmeg

-- Dead-ball restarts: tell everyone what the whistle was for.
local toastRemote = Remotes.get(Remotes.Toast)
BallService.onRestart = function(kind, team)
	toastRemote:FireAllClients(kind .. " — " .. team)
end

-- A successful nutmeg: burst the dribbler past their victim, count the stat,
-- and let every client celebrate it.
local nutmegEvent = Remotes.get(Remotes.Nutmeg)
BallService.onNutmeg = function(byModel, _victimModel)
	local uid = (byModel:GetAttribute("UserId") :: number?) or 0
	local name: string
	if uid ~= 0 then
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			PlayerService.burst(plr, NUTMEG.BurstMultiplier, NUTMEG.BurstSeconds)
			PlayerDataService.addNutmeg(plr)
		end
		name = plr and plr.DisplayName or "Someone"
	else
		local team = (byModel:GetAttribute("Team") :: string?) or ""
		name = (team ~= "") and ("A " .. team .. " bot") or "A bot"
	end
	nutmegEvent:FireAllClients({ name = name, byUserId = uid })
end

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
		BallService.shootFrom(char, charge, GameConfig.Kick.HumanShotSpreadDeg)
	end
end)

Remotes.get(Remotes.RequestTackle).OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and not BallService.carrierIsPlayer(player) and PlayerService.tryAction(player, "tackle", TACKLE.Cooldown) then
		PlayerService.spendStamina(player, STA.TackleCost)
		BallService.tackleAttempt(char)
	end
end)

Remotes.get(Remotes.RequestNutmeg).OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and BallService.carrierIsPlayer(player) and PlayerService.tryAction(player, "nutmeg", NUTMEG.Cooldown) then
		PlayerService.spendStamina(player, STA.NutmegCost)
		BallService.nutmegFrom(char)
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

-- TEMP (Studio-only) test hook so the harness can place the ball to force
-- throw-in/corner/goal-kick scenarios. REMOVE BEFORE SHIPPING.
if game:GetService("RunService"):IsStudio() then
	local dbg = Instance.new("RemoteEvent")
	dbg.Name = "DebugBallTo"
	dbg.Parent = ReplicatedStorage
	dbg.OnServerEvent:Connect(function(_, pos, vel)
		local b = BallService.getBall()
		if b and not b.Anchored and typeof(pos) == "Vector3" and BallService.getCarrier() == nil then
			b.CFrame = CFrame.new(pos)
			b.AssemblyLinearVelocity = (typeof(vel) == "Vector3") and vel or Vector3.zero
		end
	end)
end

print("[Gnarly Nutmeg] Server ready — kickoff incoming! ⚽")
