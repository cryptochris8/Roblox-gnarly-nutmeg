-- InputController (client)
-- Reads input and forwards INTENTS to the server over RemoteEvents (the server
-- validates + acts). Movement uses the built-in Humanoid controller. Bindings use
-- ContextActionService so mobile gets on-screen touch buttons for free, and
-- gamepad works too.
--   Shoot  : hold LMB / R2 / touch -> charge, release to fire
--   Pass   : E / L1 / touch
--   Tackle : F / X / touch
--   Sprint : LeftShift / L2 / touch (hold)

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local InputController = {}

local CHARGE_SECONDS = GameConfig.Kick.ChargeSeconds
local passEvent, shootEvent, tackleEvent, sprintEvent
local chargeStart = nil
local hudRef = nil

local function onPass(_, state)
	if state == Enum.UserInputState.Begin then
		passEvent:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function onTackle(_, state)
	if state == Enum.UserInputState.Begin then
		tackleEvent:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

local function onSprint(_, state)
	if state == Enum.UserInputState.Begin then
		sprintEvent:FireServer(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		sprintEvent:FireServer(false)
	end
	return Enum.ContextActionResult.Pass
end

local function onShoot(_, state)
	if state == Enum.UserInputState.Begin then
		chargeStart = os.clock()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if chargeStart then
			local frac = math.clamp((os.clock() - chargeStart) / CHARGE_SECONDS, 0, 1)
			shootEvent:FireServer(frac)
			chargeStart = nil
			if hudRef then
				hudRef.setCharge(0)
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

function InputController.start(hud)
	hudRef = hud
	passEvent = Remotes.get(Remotes.RequestPass)
	shootEvent = Remotes.get(Remotes.RequestShoot)
	tackleEvent = Remotes.get(Remotes.RequestTackle)
	sprintEvent = Remotes.get(Remotes.SetSprint)

	ContextActionService:BindAction("GN_Shoot", onShoot, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("GN_Pass", onPass, true, Enum.KeyCode.E, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("GN_Tackle", onTackle, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("GN_Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

	ContextActionService:SetTitle("GN_Shoot", "Shoot")
	ContextActionService:SetTitle("GN_Pass", "Pass")
	ContextActionService:SetTitle("GN_Tackle", "Tackle")
	ContextActionService:SetTitle("GN_Sprint", "Sprint")

	-- Live-update the charge meter while holding shoot.
	RunService.RenderStepped:Connect(function()
		if chargeStart and hudRef then
			hudRef.setCharge(math.clamp((os.clock() - chargeStart) / CHARGE_SECONDS, 0, 1))
		end
	end)
end

return InputController
