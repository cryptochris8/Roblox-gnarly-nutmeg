--!strict
-- TournamentService (SERVER)
-- "THE NUTMEG TROPHY": an 8-nation knockout — Quarterfinal, Semifinal, Final.
-- The starter picks a nation; their fixtures are played FOR REAL by painting
-- nation identities onto the Red/Blue sides (kits, highlights, scoreboard and
-- confetti all follow the identity automatically). Every other fixture is
-- simulated from the nations' strength ratings between rounds. Lose and you're
-- eliminated (the bracket plays itself out to a champion); win the final for
-- the trophy ceremony and a persisted Trophies stat.
--
-- Wiring (in Main): MatchService.onMatchSetup = TournamentService.beforeMatch,
-- MatchService.onMatchFinished = TournamentService.afterMatch, and the
-- StartTournament remote calls TournamentService.start.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Nations = require(Shared:WaitForChild("Nations"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TeamService = require(script.Parent.TeamService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local AudioService = require(script.Parent.AudioService)
local BallService = require(script.Parent.BallService)
local BotAnimationService = require(script.Parent.BotAnimationService)

local ROUND_NAMES = { "QUARTERFINAL", "SEMIFINAL", "FINAL" }

local TournamentService = {}

local active = false
local fixtureLive = false -- the CURRENT match is a staged tournament fixture
local starterTeam: string = "Blue"
local playerNation: Nations.Nation? = nil
local currentOpponent: Nations.Nation? = nil
local othersAlive: { Nations.Nation } = {}
local round = 0
local board: { string } = {}

local toastEvent: RemoteEvent? = nil

local function toast(text: string)
	if toastEvent then
		toastEvent:FireAllClients(text)
	end
end

-- Simulated fixture: strengths shape the score; knockouts always get a winner.
local function sim(a: Nations.Nation, b: Nations.Nation): (Nations.Nation, string)
	local diff = (a.strength - b.strength) * 0.06
	local ga = math.max(0, math.floor(math.random() * 2.4 + 0.8 + diff))
	local gb = math.max(0, math.floor(math.random() * 2.4 + 0.8 - diff))
	if ga == gb then
		if math.random() < 0.5 + diff * 0.08 then
			ga += 1
		else
			gb += 1
		end
	end
	local winner = (ga > gb) and a or b
	return winner, ("%s %d : %d %s"):format(a.name, ga, gb, b.name)
end

-- Simulate one whole round among the non-player survivors.
local function simRound(): { Nations.Nation }
	local survivors: { Nations.Nation } = {}
	for i = 1, #othersAlive - 1, 2 do
		local winner, line = sim(othersAlive[i], othersAlive[i + 1])
		table.insert(board, line)
		table.insert(survivors, winner)
	end
	return survivors
end

-- Bot-vs-bot bracket completion after the player is knocked out.
local function simulateToChampion(startRound: number, firstSurvivors: { Nations.Nation }): Nations.Nation
	local field = firstSurvivors
	local r = startRound
	while #field > 1 do
		table.insert(board, "— " .. (ROUND_NAMES[r] or "Round") .. " —")
		local nextField: { Nations.Nation } = {}
		for i = 1, #field - 1, 2 do
			local winner, line = sim(field[i], field[i + 1])
			table.insert(board, line)
			table.insert(nextField, winner)
		end
		field = nextField
		r += 1
	end
	return field[1]
end

-- The golden cup on a podium at the centre spot.
local function buildTrophy(): Instance?
	local model = Instance.new("Model")
	model.Name = "NutmegTrophy"
	local gold = Color3.fromRGB(245, 196, 60)
	local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local y = GameConfig.Field.GroundY
	-- podium
	part(Vector3.new(8, 2, 8), CFrame.new(0, y + 1, 0), Color3.fromRGB(40, 44, 60), Enum.Material.SmoothPlastic)
	part(Vector3.new(6, 1.2, 6), CFrame.new(0, y + 2.6, 0), gold, Enum.Material.Metal)
	-- cup: stem, bowl, lid ball + handles
	part(Vector3.new(1, 2.4, 1), CFrame.new(0, y + 4.4, 0), gold, Enum.Material.Metal)
	local bowl = part(Vector3.new(3, 2.6, 3), CFrame.new(0, y + 6.6, 0), gold, Enum.Material.Metal)
	bowl.Shape = Enum.PartType.Ball
	part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, y + 8.2, 0), gold, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		part(Vector3.new(0.5, 2, 0.5), CFrame.new(sx * 1.9, y + 6.8, 0) * CFrame.Angles(0, 0, sx * 0.5), gold, Enum.Material.Metal)
	end
	-- glow + confetti
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Range = 24
	light.Brightness = 2
	light.Parent = bowl
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(gold, Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 40
	emitter.Parent = bowl
	model.Parent = Workspace
	return model
end

local function ceremony(champion: Nations.Nation)
	pcall(function()
		AudioService.goal()
		toast(("🏆 %s WIN THE NUTMEG TROPHY!"):format(champion.name))
		local trophy = buildTrophy()
		-- the champions dance; the crowd flashes go wild
		for _, f in ipairs(BallService.listFootballers()) do
			if f.team == starterTeam then
				BotAnimationService.celebrate(f.model, "dance")
			end
		end
		local pitch = Workspace:FindFirstChild("Pitch")
		if pitch then
			for _, inst in ipairs(pitch:GetChildren()) do
				if inst.Name == "CrowdFlash" then
					local e = inst:FindFirstChildOfClass("ParticleEmitter")
					if e then
						task.delay(math.random() * 2.5, function()
							e:Emit(math.random(2, 4))
						end)
					end
				end
			end
		end
		-- trophies for the humans who lifted it
		for _, plr in ipairs(Players:GetPlayers()) do
			local a = TeamService.getAssignment(plr)
			if a and a.team == starterTeam then
				PlayerDataService.addTrophy(plr)
			end
		end
		task.delay(12, function()
			if trophy then
				trophy:Destroy()
			end
		end)
	end)
end

local function endTournament()
	active = false
	playerNation = nil
	currentOpponent = nil
	othersAlive = {}
	round = 0
end

-- Begin a run: draw 7 opponents, queue the quarterfinal, fast-forward the
-- current exhibition so the bracket starts at the next kickoff.
function TournamentService.start(player: Player, nationName: string)
	if active then
		toast("A Nutmeg Trophy run is already underway!")
		return
	end
	local nation = Nations.byName(nationName)
	if not nation then
		return
	end
	local a = TeamService.getAssignment(player)
	starterTeam = a and a.team or "Blue"
	playerNation = nation

	-- draw 7 distinct rivals
	local pool: { Nations.Nation } = {}
	for _, n in ipairs(Nations.List) do
		if n.name ~= nation.name then
			table.insert(pool, n)
		end
	end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	currentOpponent = pool[1]
	othersAlive = { pool[2], pool[3], pool[4], pool[5], pool[6], pool[7] }
	round = 1
	board = { "🏆 THE NUTMEG TROPHY", ("%s's road begins!"):format(nation.name) }
	active = true

	toast(("🏆 %s enter THE NUTMEG TROPHY! Quarterfinal vs %s — next kickoff!"):format(nation.name, (currentOpponent :: Nations.Nation).name))
	MatchService.abortMatch() -- wrap the running exhibition quickly
end

-- MatchService.onMatchSetup: paint identities for the upcoming fixture.
function TournamentService.beforeMatch()
	if not active or not playerNation or not currentOpponent then
		fixtureLive = false
		TeamService.setIdentity("Red", nil, nil)
		TeamService.setIdentity("Blue", nil, nil)
		MatchService.roundLabel = nil
		-- (the board deliberately persists so the final bracket stays readable
		-- after the run; the next tournament resets it)
		return
	end
	fixtureLive = true
	local other = (starterTeam == "Red") and "Blue" or "Red"
	TeamService.setIdentity(starterTeam, (playerNation :: Nations.Nation).name, (playerNation :: Nations.Nation).color)
	TeamService.setIdentity(other, (currentOpponent :: Nations.Nation).name, (currentOpponent :: Nations.Nation).color)
	MatchService.roundLabel = ROUND_NAMES[round]
	MatchService.board = board
	toast(("%s: %s vs %s"):format(ROUND_NAMES[round], (playerNation :: Nations.Nation).name, (currentOpponent :: Nations.Nation).name))
end

-- MatchService.onMatchFinished: advance or eliminate, then sim the rest.
-- Only counts matches that beforeMatch actually staged — the exhibition we
-- fast-forward when a tournament starts must never be scored as a fixture.
function TournamentService.afterMatch(winnerTeam: string?)
	if not active or not fixtureLive or not playerNation or not currentOpponent then
		return
	end
	fixtureLive = false
	local me = playerNation :: Nations.Nation
	local opp = currentOpponent :: Nations.Nation
	local s = MatchService.getScore()
	local myScore = (starterTeam == "Red") and s.Red or s.Blue
	local oppScore = (starterTeam == "Red") and s.Blue or s.Red
	table.insert(board, ("%s %d : %d %s"):format(me.name, myScore, oppScore, opp.name))

	local playerWon = winnerTeam == starterTeam
	if playerWon then
		local survivors = simRound()
		if round >= 3 then
			ceremony(me)
			table.insert(board, ("🏆 CHAMPIONS: %s"):format(me.name))
			MatchService.board = board
			endTournament()
			return
		end
		round += 1
		-- next opponent from the surviving half of the bracket
		local idx = math.random(1, #survivors)
		currentOpponent = table.remove(survivors, idx)
		othersAlive = survivors
		toast(("%s march on! %s vs %s — next kickoff!"):format(me.name, ROUND_NAMES[round], (currentOpponent :: Nations.Nation).name))
	else
		-- eliminated: the rest of the bracket plays itself out
		toast(("%s are OUT — %s advance."):format(me.name, opp.name))
		local survivors = simRound()
		table.insert(survivors, 1, opp)
		local champion = simulateToChampion(round + 1, survivors)
		table.insert(board, ("🏆 CHAMPIONS: %s"):format(champion.name))
		MatchService.board = board
		toast(("🏆 %s win the Nutmeg Trophy."):format(champion.name))
		endTournament()
	end
end

function TournamentService.init()
	toastEvent = Remotes.get(Remotes.Toast)
end

return TournamentService
