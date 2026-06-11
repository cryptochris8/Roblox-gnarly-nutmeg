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
function CameraDirector.reset()
	restore()
end

return CameraDirector
