-- GoalFx (client)
-- The goal-moment cocktail: a camera shake impulse, a white screen flash, and
-- a confetti burst out of the net. Three tiny layered effects, mobile-light
-- (one emitter burst, no loops), all torn down after themselves.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local GoalFx = {}

local shakeMag = 0
local shakeConn = nil

local function ensureShake()
	if shakeConn then
		return
	end
	shakeConn = RunService.RenderStepped:Connect(function(dt)
		if shakeMag <= 0.003 then
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		shakeMag *= math.pow(0.0005, dt) -- sharp hit, fast settle
		local function r()
			return (math.random() - 0.5) * 2 * shakeMag
		end
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(r()), math.rad(r()), 0)
	end)
end

function GoalFx.goal(info)
	pcall(function()
		ensureShake()
		shakeMag = 1.4

		-- white flash that settles inside half a second
		local cc = Lighting:FindFirstChild("GoalFlash") :: ColorCorrectionEffect?
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "GoalFlash"
			cc.Parent = Lighting
		end
		local flash = cc :: ColorCorrectionEffect
		flash.Brightness = 0.16
		TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()

		-- confetti out of the net (the ball is sitting in it)
		local ball = Workspace:FindFirstChild("MatchBall")
		if ball and ball:IsA("BasePart") then
			local teamColor = (info and info.team == "Red") and Color3.fromRGB(235, 90, 90) or Color3.fromRGB(110, 140, 245)
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(teamColor, Color3.fromRGB(255, 255, 255))
			e.Lifetime = NumberRange.new(0.7, 1.5)
			e.Speed = NumberRange.new(16, 34)
			e.SpreadAngle = Vector2.new(180, 180)
			e.RotSpeed = NumberRange.new(-220, 220)
			e.Size = NumberSequence.new(0.45, 0.2)
			e.LightEmission = 0.6
			e.Rate = 0
			e.Parent = ball
			e:Emit(70)
			task.delay(2.5, function()
				e:Destroy()
			end)
		end
	end)
end

return GoalFx
