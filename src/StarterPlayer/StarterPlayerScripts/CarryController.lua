-- CarryController (client)
-- While WE carry the ball, our client network-owns it (granted by the server in
-- BallService.setPossession) and steers it each Heartbeat with the shared
-- BallCarry math from zero-lag local state — that is what keeps the ball
-- rolling visibly IN FRONT of us at any speed. A server-steered ball reaches
-- this screen ~0.3s late and looks dragged behind. The server still decides
-- who carries, validates every kick, and force-looses a ball steered too far.
-- Respawn-safe: character/ball are re-resolved every step, and the loop only
-- runs between PossessionChanged(me) and PossessionChanged(not me).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local BallCarry = require(Shared:WaitForChild("BallCarry"))

local DRIB = GameConfig.Dribble
local BALL = GameConfig.Ball

local CarryController = {}

local player = Players.LocalPlayer
local stepConn = nil

local function step()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local ball = Workspace:FindFirstChild("MatchBall")
	if not (root and hum and ball) or ball.Anchored or hum.Health <= 0 then
		return -- a restart/death is in motion; the server sorts possession out
	end
	local hv = BallCarry.steer(DRIB, {
		ballPos = ball.Position,
		rootPos = root.Position,
		moveDir = hum.MoveDirection,
		lookDir = root.CFrame.LookVector,
		carrierVel = root.AssemblyLinearVelocity,
	})
	local cur = ball.AssemblyLinearVelocity
	ball.AssemblyLinearVelocity = Vector3.new(hv.X, cur.Y, hv.Z)
	local spin = BallCarry.rollSpin(hv, BALL.Diameter / 2)
	if spin then
		ball.AssemblyAngularVelocity = spin
	end
end

-- Wired by ClientController off PossessionChanged (mine = the carrier is me).
function CarryController.possession(mine)
	if mine and not stepConn then
		stepConn = RunService.Heartbeat:Connect(step)
	elseif not mine and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

return CarryController
