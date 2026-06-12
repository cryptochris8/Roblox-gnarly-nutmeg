-- InputController (client)
-- Reads input and forwards INTENTS to the server over RemoteEvents (the server
-- validates + acts). Movement uses the built-in Humanoid controller. Bindings use
-- ContextActionService so mobile gets on-screen touch buttons for free, and
-- gamepad works too.
--   Shoot  : hold LMB / R2 / touch -> charge, release to fire
--   Pass   : E / L1 / touch
--   Tackle : F / X / touch
--   Nutmeg : Q / Y / touch (poke the ball through a close defender)
--   Sprint : LeftShift / L2 / touch (hold)
--   Skills : R = Elastico Dash, T = Roulette, G = Rainbow Flick (level-gated
--            server-side; locked presses get a teaching toast)

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Skills = require(Shared:WaitForChild("Skills"))

local InputController = {}

local CHARGE_SECONDS = GameConfig.Kick.ChargeSeconds
local passEvent, shootEvent, tackleEvent, nutmegEvent, sprintEvent, skillEvent
local chargeStart = nil
local hudRef = nil

-- The roulette spin is played by US (the client owns its character's physics;
-- a server-driven per-frame spin would stutter). The server grants the actual
-- tackle immunity.
local function spinLocal()
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	task.spawn(function()
		hum.AutoRotate = false
		local t0 = os.clock()
		local startCf = root.CFrame - root.CFrame.Position
		while os.clock() - t0 < 0.45 do
			local a = math.clamp((os.clock() - t0) / 0.45, 0, 1) * math.pi * 2
			root.CFrame = CFrame.new(root.Position) * startCf * CFrame.Angles(0, a, 0)
			task.wait()
		end
		hum.AutoRotate = true
	end)
end

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

local function onNutmeg(_, state)
	if state == Enum.UserInputState.Begin then
		nutmegEvent:FireServer()
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
	nutmegEvent = Remotes.get(Remotes.RequestNutmeg)
	sprintEvent = Remotes.get(Remotes.SetSprint)
	skillEvent = Remotes.get(Remotes.RequestSkill)

	ContextActionService:BindAction("GN_Shoot", onShoot, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("GN_Pass", onPass, true, Enum.KeyCode.E, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("GN_Tackle", onTackle, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("GN_Nutmeg", onNutmeg, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("GN_Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

	ContextActionService:SetTitle("GN_Shoot", "Shoot")
	ContextActionService:SetTitle("GN_Pass", "Pass")
	ContextActionService:SetTitle("GN_Tackle", "Tackle")
	ContextActionService:SetTitle("GN_Nutmeg", "Nutmeg")
	ContextActionService:SetTitle("GN_Sprint", "Sprint")

	-- friendly one-word touch titles: a 7-year-old should guess the move
	local TOUCH_TITLES = { elastico = "Dash", roulette = "Spin", rainbow = "Flick", chop = "Chop", fakeshot = "Fake" }

	-- the unlockable skill moves (bound from shared data)
	for _, s in ipairs(Skills.List) do
		local id = s.id
		ContextActionService:BindAction("GN_Skill_" .. id, function(_, state)
			if state == Enum.UserInputState.Begin then
				skillEvent:FireServer(id)
				if id == "roulette" then
					spinLocal()
				end
			end
			return Enum.ContextActionResult.Pass
		end, true, s.key, s.pad)
		ContextActionService:SetTitle("GN_Skill_" .. id, TOUCH_TITLES[id] or string.split(s.name, " ")[1])
	end

	-- TOUCH LAYOUT: with 8 actions the default auto-arc overlaps itself, so
	-- they're arranged deliberately — Shoot biggest by the thumb, the core
	-- four fanned around it, skills in a smaller row above. Button sizes are
	-- PIXELS but the CAS button frame is much smaller on phones than tablets,
	-- so everything sizes down on short viewports and the rows spread wider
	-- than the frame (fractions outside 0..1 are legal and standard).
	if UserInputService.TouchEnabled then
		pcall(function()
			local cam = workspace.CurrentCamera
			local shortSide = cam and math.min(cam.ViewportSize.X, cam.ViewportSize.Y) or 720
			local phone = shortSide < 600
			local big = phone and 60 or 78
			local mid = phone and 46 or 60
			local small = phone and 36 or 44
			local layout = {
				{ "GN_Shoot", 0.50, 0.38, big },
				{ "GN_Pass", 0.14, 0.58, mid },
				{ "GN_Tackle", -0.06, 0.22, mid },
				{ "GN_Nutmeg", 0.22, -0.02, mid },
				{ "GN_Sprint", 0.62, -0.08, mid },
			}
			local skillStep = 1.16 / math.max(#Skills.List, 1)
			for i, s in ipairs(Skills.List) do
				layout[#layout + 1] = { "GN_Skill_" .. s.id, -0.14 + (i - 1) * skillStep, -0.36, small }
			end
			for _, it in ipairs(layout) do
				local name = it[1] :: string
				ContextActionService:SetPosition(name, UDim2.new(it[2] :: number, 0, it[3] :: number, 0))
				local btn = ContextActionService:GetButton(name)
				if btn then
					local px = it[4] :: number
					btn.Size = UDim2.fromOffset(px, px)
				end
			end
		end)

		-- locked skills LOOK locked on touch: dimmed with the unlock level as
		-- the title until the player reaches it (desktop learns via the toast)
		pcall(function()
			local progEv = Remotes.get(Remotes.ProgressionSync)
			progEv.OnClientEvent:Connect(function(data)
				local level = tonumber(data and data.level) or 1
				for _, s in ipairs(Skills.List) do
					local btn = ContextActionService:GetButton("GN_Skill_" .. s.id)
					if btn then
						local locked = level < s.unlockLevel
						btn.ImageTransparency = locked and 0.65 or 0
						ContextActionService:SetTitle("GN_Skill_" .. s.id,
							locked and ("Lv" .. s.unlockLevel) or (TOUCH_TITLES[s.id] or string.split(s.name, " ")[1]))
					end
				end
			end)
		end)
	end

	-- Live-update the charge meter while holding shoot.
	RunService.RenderStepped:Connect(function()
		if chargeStart and hudRef then
			hudRef.setCharge(math.clamp((os.clock() - chargeStart) / CHARGE_SECONDS, 0, 1))
		end
	end)
end

return InputController
