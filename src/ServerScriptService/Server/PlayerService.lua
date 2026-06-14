--!strict
-- PlayerService (SERVER)
-- Owns each HUMAN player's body state: stamina (server-authoritative, drives
-- WalkSpeed), sprint, action cooldowns, stun, freeze (for the kickoff countdown),
-- team colouring, and repositioning to a role's home spot. Movement itself uses
-- the built-in Humanoid controller (free desktop + mobile + gamepad).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TeamService = require(script.Parent.TeamService)

local PLAYER = GameConfig.Player
local STA = GameConfig.Stamina
local DEFAULT_JUMP_HEIGHT = 7.2
local FOOTBALLER_TAG = "Footballer"

local PlayerService = {}

-- Set by Main: PlayerService.onSprintEmpty(player) -- fired ONCE when a player
-- holds Sprint with no stamina left, so getting gassed isn't a silent slowdown.
PlayerService.onSprintEmpty = nil :: (((player: Player) -> ())?)

local sprintOn: { [Player]: boolean } = {}
local frozen: { [Player]: boolean } = {}
local stunnedUntil: { [Player]: number } = {}
local stamina: { [Player]: number } = {}
local lastAction: { [Player]: { [string]: number } } = {}
local lastStaminaSend: { [Player]: number } = {}
local burstUntil: { [Player]: number } = {}
local burstMult: { [Player]: number } = {}
-- one-shot latch so the "out of breath" nudge fires once per gassed spell, not
-- every frame; clears when stamina has recovered to half
local sprintEmptyWarned: { [Player]: boolean } = {}

local staminaEvent: RemoteEvent

-- (character, humanoid, root) or nils if not fully spawned.
local function rig(player: Player): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, hum, root
end

PlayerService.rig = rig

function PlayerService.getRoot(player: Player): BasePart?
	local _, _, root = rig(player)
	return root
end

local function applyTeamLook(character: Model, team: string)
	local info = TeamService.info(team)
	if not info then
		return
	end
	local hl = character:FindFirstChild("TeamLook") :: Highlight?
	if not hl then
		hl = Instance.new("Highlight")
		hl.Name = "TeamLook"
	end
	hl.FillColor = info.color
	hl.FillTransparency = 0.55
	hl.OutlineColor = info.color
	hl.OutlineTransparency = 0
	hl.Parent = character
end

local function tagFootballer(character: Model, team: string, role: string, userId: number)
	character:SetAttribute("Team", team)
	character:SetAttribute("Role", role)
	character:SetAttribute("IsBot", false)
	character:SetAttribute("UserId", userId)
	CollectionService:AddTag(character, FOOTBALLER_TAG)
end

-- Tag a human's current character as a footballer (so BallService/AIService see
-- them) and colour them. Safe to call again after a respawn or (re)assignment.
function PlayerService.registerFootballer(player: Player)
	local char = player.Character
	local a = TeamService.getAssignment(player)
	if not char or not a then
		return
	end
	applyTeamLook(char, a.team)
	tagFootballer(char, a.team, a.role, player.UserId)
end

local function onCharacter(player: Player, character: Model)
	stamina[player] = STA.Max
	sprintOn[player] = false
	stunnedUntil[player] = 0
	local hum = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if hum then
		hum.WalkSpeed = PLAYER.WalkSpeed
	end
	local a = TeamService.getAssignment(player)
	if a then
		applyTeamLook(character, a.team)
		tagFootballer(character, a.team, a.role, player.UserId)
	end
end

-- Sprint intent from the client (validated/throttled here).
function PlayerService.setSprint(player: Player, on: boolean)
	sprintOn[player] = on and true or false
end

-- Returns true if `cost` stamina was available; always spends what it can.
function PlayerService.spendStamina(player: Player, cost: number): boolean
	local cur = stamina[player] or 0
	local enough = cur >= cost
	stamina[player] = math.max(0, cur - cost)
	return enough
end

-- Simple per-action cooldown gate. Returns true if the action may run now.
function PlayerService.tryAction(player: Player, key: string, cooldown: number): boolean
	local t = lastAction[player]
	if not t then
		t = {}
		lastAction[player] = t
	end
	local now = os.clock()
	if t[key] and now - t[key] < cooldown then
		return false
	end
	t[key] = now
	return true
end

function PlayerService.isStunned(player: Player): boolean
	return (stunnedUntil[player] or 0) > os.clock()
end

-- Short speed burst on top of the normal walk/sprint speed (the nutmeg reward).
function PlayerService.burst(player: Player, mult: number, seconds: number)
	burstMult[player] = mult
	burstUntil[player] = os.clock() + seconds
end

function PlayerService.stun(player: Player, seconds: number)
	stunnedUntil[player] = os.clock() + seconds
end

function PlayerService.setFrozen(player: Player, isFrozen: boolean)
	frozen[player] = isFrozen and true or false
end

function PlayerService.freezeAll(isFrozen: boolean)
	for _, player in ipairs(Players:GetPlayers()) do
		frozen[player] = isFrozen and true or false
	end
end

-- Teleport a player to their role's home position (used at kickoff).
function PlayerService.positionAtHome(player: Player)
	local a = TeamService.getAssignment(player)
	if not a then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local pos = TeamService.homePosition(a.team, a.role)
	-- Face the centre of the pitch.
	local look = Vector3.new(GameConfig.Field.CenterX, pos.Y, GameConfig.Field.CenterZ)
	pcall(function()
		char:PivotTo(CFrame.lookAt(pos, look))
	end)
end

-- Per-frame: resolve each human's WalkSpeed from frozen/stun/sprint/stamina, and
-- push a throttled StaminaUpdate to their client.
local function step(dt: number)
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local _, hum = rig(player)
		if hum then
			local st = stamina[player] or STA.Max
			if frozen[player] then
				hum.WalkSpeed = 0
				hum.JumpHeight = 0
			elseif (stunnedUntil[player] or 0) > now then
				hum.WalkSpeed = 0
				hum.JumpHeight = 0
			else
				hum.JumpHeight = DEFAULT_JUMP_HEIGHT
				if sprintOn[player] and st > 0 then
					st = math.max(0, st - STA.DrainPerSecond * dt)
					hum.WalkSpeed = (st > 0) and PLAYER.SprintSpeed or PLAYER.LowStaminaSpeed
				else
					st = math.min(STA.Max, st + STA.RegenPerSecond * dt)
					hum.WalkSpeed = PLAYER.WalkSpeed
				end
				if (burstUntil[player] or 0) > now then
					hum.WalkSpeed *= burstMult[player] or 1
				end
				stamina[player] = st

				-- Gassed: holding Sprint with the tank near-empty gives no boost.
				-- Nudge once so the sudden slow-down isn't a mystery, then wait
				-- until they've recovered to half before it can fire again.
				if sprintOn[player] and st <= STA.Max * 0.1 then
					if not sprintEmptyWarned[player] then
						sprintEmptyWarned[player] = true
						local cb = PlayerService.onSprintEmpty
						if cb then
							cb(player)
						end
					end
				elseif st >= STA.Max * 0.5 then
					sprintEmptyWarned[player] = nil
				end
			end

			-- throttle stamina pushes to ~5/sec
			local last = lastStaminaSend[player] or 0
			if now - last >= 0.2 then
				lastStaminaSend[player] = now
				staminaEvent:FireClient(player, (stamina[player] or STA.Max) / STA.Max)
			end
		end
	end
end

function PlayerService.init()
	staminaEvent = Remotes.get(Remotes.StaminaUpdate)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		sprintOn[player] = nil
		frozen[player] = nil
		stunnedUntil[player] = nil
		stamina[player] = nil
		lastAction[player] = nil
		lastStaminaSend[player] = nil
		sprintEmptyWarned[player] = nil
		burstUntil[player] = nil
		burstMult[player] = nil
	end)

	RunService.Heartbeat:Connect(step)
end

return PlayerService
