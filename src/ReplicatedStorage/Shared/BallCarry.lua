--!strict
-- BallCarry — the dribble-steering math (one source of truth).
-- The ball is steered to roll Dribble.Offset studs ahead of the carrier, in
-- their direction of travel. The same function runs in two places:
--   • on the SERVER for bot carriers (bots simulate there: zero lag), and
--   • on the carrying player's OWN CLIENT for human carriers — the client
--     network-owns the ball while dribbling (see BallService.setPossession),
--     so the lead is computed from zero-lag local state. A server-steered
--     ball renders ~0.3s in the past on the carrier's screen, which dragged
--     it visibly BEHIND the player (measured -5.6 studs at walking speed).
-- The server stays authoritative over WHO carries, every kick, and a leash
-- that force-releases a ball steered too far from its carrier.

export type Tuning = {
	Offset: number,
	Responsiveness: number,
	MaxSpeed: number,
	SprintKnockOn: number?, -- extra lead per (speed-16)/16 — sprint pushes it further
}

export type Pose = {
	ballPos: Vector3,
	rootPos: Vector3,
	moveDir: Vector3, -- Humanoid.MoveDirection
	lookDir: Vector3, -- root CFrame.LookVector (aim fallback while standing)
	carrierVel: Vector3, -- root AssemblyLinearVelocity
}

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local FIELD = GameConfig.Field
local LINE_MARGIN = 1.4 -- the carried ball hugs inside the lines, never over

local BallCarry = {}

-- New horizontal velocity for the carried ball (callers preserve its Y).
function BallCarry.steer(cfg: Tuning, p: Pose): Vector3
	-- lead in the direction of MOVEMENT, falling back to facing when still
	local dir = Vector3.new(p.moveDir.X, 0, p.moveDir.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(p.lookDir.X, 0, p.lookDir.Z)
	end
	dir = (dir.Magnitude > 0.001) and dir.Unit or Vector3.new(0, 0, 1)

	local carrierVel = Vector3.new(p.carrierVel.X, 0, p.carrierVel.Z)
	-- sprint knock-ons: the faster the run, the further the touch rolls out
	-- ahead — quicker ground covered, but more ball for a defender to nick
	local off = cfg.Offset
	local knock = cfg.SprintKnockOn
	if knock and knock > 0 then
		off += math.max(0, (carrierVel.Magnitude - 16) / 16) * knock
	end
	-- a dribbled ball NEVER rolls itself out of play: sprinting down the wing
	-- used to knock the lead point over the touchline and gift a throw-in
	local leadX = math.clamp(p.rootPos.X + dir.X * off, FIELD.MinX + LINE_MARGIN, FIELD.MaxX - LINE_MARGIN)
	local leadZ = math.clamp(p.rootPos.Z + dir.Z * off, FIELD.MinZ + LINE_MARGIN, FIELD.MaxZ - LINE_MARGIN)
	local toLead = Vector3.new(leadX - p.ballPos.X, 0, leadZ - p.ballPos.Z)
	-- feed-forward the carrier's speed: a pure P-controller cruises at
	-- v/Responsiveness BEHIND its target, so the faster the run the further
	-- the ball trailed — matching speeds first lets the P-term hold the full
	-- Offset at any pace
	local hv = carrierVel + toLead * cfg.Responsiveness
	if hv.Magnitude > cfg.MaxSpeed then
		hv = hv.Unit * cfg.MaxSpeed
	end
	return hv
end

-- Rolling spin matching a horizontal velocity (cosmetic, but sells the dribble).
function BallCarry.rollSpin(hv: Vector3, ballRadius: number): Vector3?
	if hv.Magnitude <= 1 then
		return nil
	end
	local axis = Vector3.yAxis:Cross(hv)
	if axis.Magnitude <= 0.001 then
		return nil
	end
	return axis.Unit * (hv.Magnitude / ballRadius)
end

return BallCarry
