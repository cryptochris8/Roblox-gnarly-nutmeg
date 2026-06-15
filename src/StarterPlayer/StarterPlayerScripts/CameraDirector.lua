-- CameraDirector (client)
-- Broadcast-style camera moments. Everything here is CLIENT-side camera work —
-- it never touches the server simulation. Currently: a kickoff flyover that
-- sweeps down from above the bowl during the countdown, then hands the camera
-- back at GO.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local CameraDirector = {}

local flying = false
local mode = "none" -- "none" | "flyover" | "goal"
local activeTween: Tween? = nil

local function restore()
	local cam = Workspace.CurrentCamera
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if cam and flying then
		cam.CameraType = Enum.CameraType.Custom
		local char = Players.LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
	flying = false
	mode = "none"
end

-- Called with each countdown tick (3, 2, 1, then 0 = GO).
function CameraDirector.countdown(n)
	local ok = pcall(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		if n and n >= 3 then
			-- start the sweep: high above the bowl, gliding down toward the pitch
			flying = true
			mode = "flyover"
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = CFrame.lookAt(Vector3.new(190, 150, 190), Vector3.new(0, 0, 0))
			activeTween = TweenService:Create(
				cam,
				TweenInfo.new(2.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ CFrame = CFrame.lookAt(Vector3.new(0, 46, 132), Vector3.new(0, 2, 0)) }
			)
			;(activeTween :: Tween):Play()
		elseif n == 0 or n == nil then
			restore()
		end
	end)
	if not ok then
		restore()
	end
end

-- Safety: if anything interrupts the countdown, hand the camera back.
-- The goal replay AND a live penalty are exempt — MatchState broadcasts every
-- second, and it must not yank the camera off the replay/penalty; each hands the
-- camera back itself when it's done.
function CameraDirector.reset()
	if mode == "goal" or mode == "penalty" then
		return
	end
	restore()
end

-- A penalty is being taken: a broadcast camera planted behind the taker looking
-- down the spot toward the goal, so EVERY kick (both teams, near and far goal) is
-- framed up close. Holds until penaltyEnd(). `spot` and `goalCenter` are world
-- points sent by the server with each kick.
function CameraDirector.penalty(spot, goalCenter)
	local ok = pcall(function()
		local cam = Workspace.CurrentCamera
		if not (cam and typeof(spot) == "Vector3" and typeof(goalCenter) == "Vector3") then
			return
		end
		flying = true
		mode = "penalty"
		cam.CameraType = Enum.CameraType.Scriptable
		local behind = spot - goalCenter
		behind = Vector3.new(behind.X, 0, behind.Z)
		behind = behind.Magnitude > 0.1 and behind.Unit or Vector3.new(0, 0, 1)
		local camPos = spot + behind * 15 + Vector3.new(0, 8, 0)
		local focus = spot:Lerp(goalCenter, 0.5) + Vector3.new(0, 1.5, 0)
		cam.CFrame = CFrame.lookAt(camPos, focus)
		if activeTween then
			activeTween:Cancel()
		end
		-- a slow push-in toward goal for that big-moment broadcast feel
		activeTween = TweenService:Create(
			cam,
			TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(camPos - behind * 3 + Vector3.new(0, -1, 0), focus) }
		)
		;(activeTween :: Tween):Play()
	end)
	if not ok then
		restore()
	end
end

function CameraDirector.penaltyEnd()
	if mode == "penalty" then
		restore()
	end
end

-- A goal just went in: a slow broadcast dolly past the net while the
-- celebration plays. Focus is the ball (it's IN the net — the money shot),
-- pulled halfway toward the scorer when their character is findable.
function CameraDirector.goalReplay(info)
	local ok = pcall(function()
		local cam = Workspace.CurrentCamera
		local ball = Workspace:FindFirstChild("MatchBall")
		if not (cam and ball) then
			return
		end
		local focus = ball.Position
		local scorer = info and info.scorer
		local plr = scorer and Players:FindFirstChild(tostring(scorer))
		local char = plr and plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			-- favour the scorer and frame at chest height: the server turns the
			-- celebration to face the pitch, so this side films their FRONT
			focus = focus:Lerp(root.Position, 0.6) + Vector3.new(0, 2.2, 0)
		end
		flying = true
		mode = "goal"
		cam.CameraType = Enum.CameraType.Scriptable
		local towardCentre = Vector3.new(-focus.X, 0, -focus.Z)
		towardCentre = towardCentre.Magnitude > 1 and towardCentre.Unit or Vector3.new(0, 0, 1)
		local side = Vector3.new(-towardCentre.Z, 0, towardCentre.X)
		local from = focus + towardCentre * 13 - side * 11 + Vector3.new(0, 4, 0)
		local to = focus + towardCentre * 14 + side * 11 + Vector3.new(0, 6.5, 0)
		cam.CFrame = CFrame.lookAt(from, focus)
		activeTween = TweenService:Create(
			cam,
			TweenInfo.new(4.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = CFrame.lookAt(to, focus + Vector3.new(0, 2, 0)) }
		)
		;(activeTween :: Tween):Play()
		task.delay(4.8, function()
			-- hand back only if the kickoff flyover hasn't taken over since
			if mode == "goal" then
				restore()
			end
		end)
	end)
	if not ok then
		restore()
	end
end

return CameraDirector
