--!strict
-- TournamentService (SERVER)
-- "THE NUTMEG TROPHY": an 8-nation knockout (QF/SF/F) that ANY player can host
-- and friends can JOIN. The first StartTournament opens a short claim lobby
-- (everyone's nation picker pops up); each player may claim one nation. When
-- the lobby closes, the bracket seeds with every claimed nation plus random
-- fillers. Any fixture with at least one claimed nation is played FOR REAL —
-- claim owners are placed on their nation's side (Red = first name in the tie,
-- Blue = second) and the painted identities make kits/scoreboard/confetti
-- follow. Everything else is simulated from nation strength between matches.
-- Win the final for the trophy ceremony and a persisted Trophies stat.
--
-- Wiring (in Main): MatchService.onMatchSetup = TournamentService.beforeMatch,
-- MatchService.onMatchFinished = TournamentService.afterMatch, and the
-- StartTournament remote calls TournamentService.start.
--
-- KEY GUARD (do not regress): fixtureLive — the exhibition we fast-forward at
-- cup start must never be scored as a fixture.

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
local LOBBY_SECONDS = 20

local TournamentService = {}

type Fixture = { a: Nations.Nation, b: Nations.Nation }

local active = false
local lobbyOpen = false
local lobbyToken = 0
local claims: { [string]: number } = {} -- nation name -> userId of its owner
local field: { Nations.Nation } = {}    -- this round's entrants, in pair order
local liveQueue: { Fixture } = {}       -- fixtures that involve a claimed nation
local roundWinners: { Nations.Nation } = {}
local current: Fixture? = nil
local round = 0
local board: { string } = {}
local fixtureLive = false

local toastEvent: RemoteEvent? = nil
local lobbyEvent: RemoteEvent? = nil

local function toast(text: string)
	if toastEvent then
		toastEvent:FireAllClients(text)
	end
end

local function ownerOf(n: Nations.Nation): Player?
	local uid = claims[n.name]
	if not uid then
		return nil
	end
	local plr = Players:GetPlayerByUserId(uid)
	if plr and plr.Parent then
		return plr
	end
	claims[n.name] = nil -- owner left the game; their nation plays on as bots
	return nil
end

local function ownerTag(n: Nations.Nation): string
	local plr = ownerOf(n)
	return plr and (" (" .. plr.Name .. ")") or ""
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

local function shuffle<T>(t: { T })
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
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
	part(Vector3.new(8, 2, 8), CFrame.new(0, y + 1, 0), Color3.fromRGB(40, 44, 60), Enum.Material.SmoothPlastic)
	part(Vector3.new(6, 1.2, 6), CFrame.new(0, y + 2.6, 0), gold, Enum.Material.Metal)
	part(Vector3.new(1, 2.4, 1), CFrame.new(0, y + 4.4, 0), gold, Enum.Material.Metal)
	local bowl = part(Vector3.new(3, 2.6, 3), CFrame.new(0, y + 6.6, 0), gold, Enum.Material.Metal)
	bowl.Shape = Enum.PartType.Ball
	part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, y + 8.2, 0), gold, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		part(Vector3.new(0.5, 2, 0.5), CFrame.new(sx * 1.9, y + 6.8, 0) * CFrame.Angles(0, 0, sx * 0.5), gold, Enum.Material.Metal)
	end
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

-- winnerTeam = the side that lifted it in the live final (dances + trophies).
local function ceremony(champion: Nations.Nation, winnerTeam: string?)
	pcall(function()
		AudioService.goal()
		toast(("🏆 %s%s WIN THE NUTMEG TROPHY!"):format(champion.name, ownerTag(champion)))
		local trophy = buildTrophy()
		if winnerTeam then
			for _, f in ipairs(BallService.listFootballers()) do
				if f.team == winnerTeam then
					BotAnimationService.celebrate(f.model, "dance")
				end
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
		if winnerTeam then
			for _, plr in ipairs(Players:GetPlayers()) do
				local a = TeamService.getAssignment(plr)
				if a and a.team == winnerTeam then
					PlayerDataService.addTrophy(plr)
				end
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
	lobbyOpen = false
	table.clear(claims)
	field = {}
	liveQueue = {}
	roundWinners = {}
	current = nil
	round = 0
end

-- Pair off the current field: claimed ties queue up to be PLAYED, the rest
-- resolve by simulation immediately.
local function startRound()
	table.insert(board, "— " .. (ROUND_NAMES[round] or "ROUND") .. " —")
	liveQueue = {}
	roundWinners = {}
	for i = 1, #field - 1, 2 do
		local a, b = field[i], field[i + 1]
		if claims[a.name] or claims[b.name] then
			table.insert(liveQueue, { a = a, b = b })
		else
			local winner, line = sim(a, b)
			table.insert(board, line)
			table.insert(roundWinners, winner)
		end
	end
	MatchService.board = board
	if #liveQueue > 0 then
		local f = liveQueue[1]
		toast(("%s: %s%s vs %s%s — next kickoff!"):format(
			ROUND_NAMES[round] or "NEXT", f.a.name, ownerTag(f.a), f.b.name, ownerTag(f.b)))
	end
end

-- Take the next live fixture whose claims still stand; dead ties get simmed.
local function popLiveFixture(): Fixture?
	while #liveQueue > 0 do
		local f = table.remove(liveQueue, 1) :: Fixture
		if ownerOf(f.a) or ownerOf(f.b) then
			return f
		end
		local winner, line = sim(f.a, f.b)
		table.insert(board, line)
		table.insert(roundWinners, winner)
	end
	return nil
end

-- Close a round once its queue is empty. Returns false when the cup is over.
local function finishRound(): boolean
	if #roundWinners == 1 then
		local champion = roundWinners[1]
		table.insert(board, ("🏆 CHAMPIONS: %s"):format(champion.name))
		MatchService.board = board
		-- no live final produced this champion (all claims died) — no ceremony
		toast(("🏆 %s win the Nutmeg Trophy."):format(champion.name))
		endTournament()
		return false
	end
	round += 1
	field = roundWinners
	shuffle(field)
	startRound()
	return true
end

-- Begin hosting OR claim a nation in an open lobby.
function TournamentService.start(player: Player, nationName: string)
	local nation = Nations.byName(nationName)
	if not nation then
		return
	end

	if active and not lobbyOpen then
		toast("A Nutmeg Trophy run is already underway!")
		return
	end

	if lobbyOpen then
		-- a claim (or a re-pick) during the lobby window
		if claims[nation.name] and claims[nation.name] ~= player.UserId then
			toast(("%s is already claimed — pick another nation!"):format(nation.name))
			return
		end
		for name, uid in pairs(claims) do
			if uid == player.UserId then
				claims[name] = nil -- re-pick: release the old nation
			end
		end
		claims[nation.name] = player.UserId
		toast(("⚽ %s will play as %s!"):format(player.Name, nation.name))
		return
	end

	-- fresh cup: open the claim lobby
	active = true
	lobbyOpen = true
	lobbyToken += 1
	local token = lobbyToken
	table.clear(claims)
	claims[nation.name] = player.UserId
	board = { "🏆 THE NUTMEG TROPHY" }
	toast(("🏆 %s is hosting THE NUTMEG TROPHY as %s! Pick a nation to JOIN — kickoff in %ds"):format(
		player.Name, nation.name, LOBBY_SECONDS))
	if lobbyEvent then
		lobbyEvent:FireAllClients({ open = true, seconds = LOBBY_SECONDS, host = player.Name })
	end

	task.delay(LOBBY_SECONDS, function()
		if lobbyToken ~= token or not lobbyOpen then
			return
		end
		lobbyOpen = false
		if lobbyEvent then
			lobbyEvent:FireAllClients({ open = false })
		end
		-- seed: claimed nations first (stable order), random fill to 8
		field = {}
		local pool: { Nations.Nation } = {}
		for _, n in ipairs(Nations.List) do
			if claims[n.name] then
				table.insert(field, n)
			else
				table.insert(pool, n)
			end
		end
		local challengers = #field
		shuffle(pool)
		while #field < 8 do
			table.insert(field, table.remove(pool) :: Nations.Nation)
		end
		shuffle(field)
		round = 1
		table.insert(board, ("%d nation%s answered the call"):format(challengers, challengers == 1 and "" or "s"))
		startRound()
		MatchService.abortMatch() -- wrap the running exhibition quickly
	end)
end

-- MatchService.onMatchSetup: stage the next live fixture (if any).
function TournamentService.beforeMatch()
	if not active or lobbyOpen then
		fixtureLive = false
		TeamService.setIdentity("Red", nil, nil)
		TeamService.setIdentity("Blue", nil, nil)
		MatchService.roundLabel = nil
		-- (the board deliberately persists so the final bracket stays readable
		-- after the run; the next tournament resets it)
		return
	end
	while current == nil do
		current = popLiveFixture()
		if current == nil then
			-- round complete with no live fixture to stage
			if not finishRound() then
				fixtureLive = false
				TeamService.setIdentity("Red", nil, nil)
				TeamService.setIdentity("Blue", nil, nil)
				MatchService.roundLabel = nil
				return
			end
		end
	end
	local cur = current :: Fixture
	fixtureLive = true
	-- claim owners play ON their nation's side (Red = a, Blue = b)
	local pa, pb = ownerOf(cur.a), ownerOf(cur.b)
	if pa then
		TeamService.unassign(pa)
		TeamService.assignHuman(pa, "Red")
	end
	if pb then
		TeamService.unassign(pb)
		TeamService.assignHuman(pb, "Blue")
	end
	TeamService.setIdentity("Red", cur.a.name, cur.a.color)
	TeamService.setIdentity("Blue", cur.b.name, cur.b.color)
	MatchService.roundLabel = ROUND_NAMES[round]
	MatchService.board = board
	toast(("%s: %s%s vs %s%s"):format(
		ROUND_NAMES[round] or "FIXTURE", cur.a.name, ownerTag(cur.a), cur.b.name, ownerTag(cur.b)))
end

-- MatchService.onMatchFinished: score the fixture, advance the bracket.
function TournamentService.afterMatch(winnerTeam: string?)
	if not active or not fixtureLive or not current then
		return
	end
	fixtureLive = false
	local cur = current :: Fixture
	current = nil

	local s = MatchService.getScore()
	table.insert(board, ("%s %d : %d %s"):format(cur.a.name, s.Red, s.Blue, cur.b.name))

	local winner = (winnerTeam == "Red") and cur.a or cur.b
	local loser = (winner == cur.a) and cur.b or cur.a
	claims[loser.name] = nil -- a beaten nation's owner becomes a neutral
	table.insert(roundWinners, winner)
	MatchService.board = board

	if #liveQueue > 0 then
		local nxt = liveQueue[1]
		toast(("%s%s advance! Up next: %s%s vs %s%s"):format(
			winner.name, ownerTag(winner), nxt.a.name, ownerTag(nxt.a), nxt.b.name, ownerTag(nxt.b)))
		return
	end

	if #roundWinners == 1 then
		-- that was the final
		table.insert(board, ("🏆 CHAMPIONS: %s"):format(winner.name))
		MatchService.board = board
		if claims[winner.name] then
			ceremony(winner, winnerTeam)
		else
			toast(("🏆 %s win the Nutmeg Trophy."):format(winner.name))
		end
		endTournament()
		return
	end

	round += 1
	field = roundWinners
	shuffle(field)
	startRound()
end

function TournamentService.init()
	toastEvent = Remotes.get(Remotes.Toast)
	lobbyEvent = Remotes.get(Remotes.TournamentLobby)
end

return TournamentService
