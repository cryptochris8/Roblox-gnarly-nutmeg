-- MenuUI (client)
-- A compact team-picker (applies between matches), THE NUTMEG TROPHY nation
-- picker, and a controls hint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Nations = require(Shared:WaitForChild("Nations"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))

local UiTheme = require(script.Parent.UiTheme)
local C = UiTheme.Colors

local MenuUI = {}

-- refs to the between-match panels/buttons so MenuUI.matchActive can clear them
-- off-screen during live play (assigned in mount)
local refs = nil

function MenuUI.mount(playerGui)
	local gui = UiTheme.make("ScreenGui", {
		Name = "GnarlyMenu",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		Parent = playerGui,
	})

	-- mobile gets a compact top-left block (the buttons used between matches
	-- shouldn't crowd the pitch or the movement thumb-zone)
	local touch = UserInputService.TouchEnabled
	local panel = UiTheme.make("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(touch and 10 or 18, touch and 6 or 18),
		Size = UDim2.fromOffset(touch and 150 or 184, touch and 70 or 96),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.15,
		Parent = gui,
	})
	UiTheme.corner(14, panel)

	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = touch and 12 or 14,
		TextColor3 = C.Panel,
		Text = "PICK YOUR TEAM",
		Position = UDim2.fromOffset(0, touch and 5 or 8),
		Size = UDim2.new(1, 0, 0, touch and 14 or 18),
		Parent = panel,
	})

	local selectEvent = Remotes.get(Remotes.SelectTeam)

	local function teamButton(name, color, x)
		local b = UiTheme.make("TextButton", {
			Position = UDim2.fromOffset(x, touch and 26 or 34),
			Size = UDim2.fromOffset(touch and 66 or 78, touch and 46 or 46),
			BackgroundColor3 = color,
			Font = UiTheme.Header,
			TextSize = touch and 15 or 18,
			TextColor3 = C.Panel,
			Text = name,
			AutoButtonColor = true,
			Parent = panel,
		})
		UiTheme.corner(12, b)
		b.MouseButton1Click:Connect(function()
			selectEvent:FireServer(name)
		end)
		return b
	end

	teamButton("RED", C.Red, touch and 8 or 12)
	teamButton("BLUE", C.Blue, touch and 78 or 94)

	-- THE NUTMEG TROPHY: launch a tournament run as your chosen nation
	local startEvent = Remotes.get(Remotes.StartTournament)
	local gold = Color3.fromRGB(245, 196, 60)

	-- A kid-proof confirm gate for the only two SERVER-WIDE actions a player can
	-- trigger (start a tournament for everyone / flip shootout mode for everyone).
	-- Before this, one curious tap rerouted the whole server's match.
	local confirmBackdrop = UiTheme.make("Frame", {
		Name = "ConfirmBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		Active = true, -- swallow taps to the panels behind
		ZIndex = 60,
		Parent = gui,
	})
	local confirmModal = UiTheme.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(400, 220),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.02,
		ZIndex = 61,
		Parent = confirmBackdrop,
	})
	local confirmCap = Instance.new("UISizeConstraint")
	confirmCap.MaxSize = Vector2.new(440, 250)
	confirmCap.Parent = confirmModal
	UiTheme.corner(18, confirmModal)
	UiTheme.stroke(gold, 2, confirmModal)
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 20,
		TextColor3 = gold,
		Text = "⚠ THIS CHANGES THE GAME FOR EVERYONE",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 40),
		TextWrapped = true,
		ZIndex = 62,
		Parent = confirmModal,
	})
	local confirmLabel = UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 17,
		TextColor3 = C.Panel,
		Text = "",
		Position = UDim2.fromOffset(24, 60),
		Size = UDim2.new(1, -48, 0, 64),
		TextWrapped = true,
		ZIndex = 62,
		Parent = confirmModal,
	})
	local confirmAction: (() -> ())? = nil
	local confirmYes = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -16),
		Size = UDim2.new(0.5, -28, 0, 54),
		BackgroundColor3 = Color3.fromRGB(90, 200, 140),
		Font = UiTheme.Header,
		TextSize = 19,
		TextColor3 = C.Ink,
		Text = "✓ YES",
		AutoButtonColor = true,
		ZIndex = 62,
		Parent = confirmModal,
	})
	UiTheme.corner(12, confirmYes)
	local confirmCancel = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -16),
		Size = UDim2.new(0.5, -28, 0, 54),
		BackgroundColor3 = C.Track,
		Font = UiTheme.Header,
		TextSize = 19,
		TextColor3 = C.Panel,
		Text = "✕ CANCEL",
		AutoButtonColor = true,
		ZIndex = 62,
		Parent = confirmModal,
	})
	UiTheme.corner(12, confirmCancel)
	local function askConfirm(message: string, action: () -> ())
		confirmLabel.Text = message
		confirmAction = action
		confirmBackdrop.Visible = true
	end
	confirmYes.MouseButton1Click:Connect(function()
		confirmBackdrop.Visible = false
		local a = confirmAction
		confirmAction = nil
		if a then
			a()
		end
	end)
	confirmCancel.MouseButton1Click:Connect(function()
		confirmBackdrop.Visible = false
		confirmAction = nil
	end)

	-- mobile: 🏆 / 👕 / 📋 become a compact icon row under the team panel
	local trophyBtn = UiTheme.make("TextButton", {
		Position = UDim2.fromOffset(touch and 10 or 18, touch and 82 or 122),
		Size = UDim2.fromOffset(touch and 44 or 184, 40),
		BackgroundColor3 = gold,
		Font = UiTheme.Header,
		TextSize = touch and 20 or 15,
		TextColor3 = C.Ink,
		Text = touch and "🏆" or "🏆 NUTMEG TROPHY",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(12, trophyBtn)

	-- scale-based with a hard cap so the picker also fits phone screens
	local picker = UiTheme.make("Frame", {
		Name = "NationPicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 0),
		Size = UDim2.new(0.92, 0, 0.78, 0),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(540, 380)
	sizeCap.Parent = picker
	UiTheme.corner(18, picker)
	local pickerTitle = UiTheme.make("TextLabel", {
		Name = "PickerTitle",
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 20,
		TextColor3 = gold,
		Text = "🏆 PICK YOUR NATION",
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = picker,
	})
	local closeBtn = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.Track,
		Font = UiTheme.Header,
		TextSize = 16,
		TextColor3 = C.Panel,
		Text = "✕",
		Parent = picker,
	})
	UiTheme.corner(8, closeBtn)
	closeBtn.MouseButton1Click:Connect(function()
		picker.Visible = false
	end)

	local grid = UiTheme.make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 1, -64),
		Parent = picker,
	})
	local layout = Instance.new("UIGridLayout")
	-- scale cells: always a 4-wide grid, so the 16 nations fit ANY screen
	layout.CellSize = UDim2.new(0.25, -6, 0.25, -6)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid

	for _, nation in ipairs(Nations.List) do
		local c = nation.color
		local bright = c.R * 0.299 + c.G * 0.587 + c.B * 0.114 > 0.55
		local b = UiTheme.make("TextButton", {
			BackgroundColor3 = c,
			Font = UiTheme.Header,
			TextSize = 14,
			TextScaled = true,
			TextColor3 = bright and C.Ink or C.Panel,
			Text = nation.name,
			AutoButtonColor = true,
			Parent = grid,
		})
		UiTheme.corner(10, b)
		b.MouseButton1Click:Connect(function()
			askConfirm(("Start a NUTMEG TROPHY for EVERYONE as %s?"):format(nation.name), function()
				startEvent:FireServer(nation.name)
				picker.Visible = false
			end)
		end)
	end

	trophyBtn.MouseButton1Click:Connect(function()
		picker.Visible = not picker.Visible
	end)

	-- someone is hosting a cup: pop the picker for EVERYONE with a countdown,
	-- so friends in the server can claim their nation and join the bracket
	local lobbyGen = 0
	Remotes.get(Remotes.TournamentLobby).OnClientEvent:Connect(function(info)
		lobbyGen += 1
		local gen = lobbyGen
		if type(info) == "table" and info.open then
			picker.Visible = true
			local deadline = os.clock() + (tonumber(info.seconds) or 20)
			local host = tostring(info.host or "Someone")
			task.spawn(function()
				while gen == lobbyGen and picker.Parent do
					local left = math.max(0, math.ceil(deadline - os.clock()))
					pickerTitle.Text = ("🏆 %s IS HOSTING — CLAIM A NATION!  (%ds)"):format(host, left)
					if left <= 0 then
						break
					end
					task.wait(0.25)
				end
			end)
		else
			picker.Visible = false
			pickerTitle.Text = "🏆 PICK YOUR NATION"
		end
	end)

	-- 👕 THE LOCKER: equip earned boots / trails / celebrations
	local lockerBtn = UiTheme.make("TextButton", {
		Position = UDim2.fromOffset(touch and 60 or 18, touch and 82 or 170),
		Size = UDim2.fromOffset(touch and 44 or 184, 40),
		BackgroundColor3 = Color3.fromRGB(120, 200, 255),
		Font = UiTheme.Header,
		TextSize = touch and 20 or 15,
		TextColor3 = C.Ink,
		Text = touch and "👕" or "👕 LOCKER",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(12, lockerBtn)

	local locker = UiTheme.make("Frame", {
		Name = "Locker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 0),
		Size = UDim2.new(0.92, 0, 0.82, 0),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	local lockerCap = Instance.new("UISizeConstraint")
	lockerCap.MaxSize = Vector2.new(560, 430)
	lockerCap.Parent = locker
	UiTheme.corner(18, locker)
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(120, 200, 255),
		Text = "👕 YOUR LOCKER — earn it by playing",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = locker,
	})
	local lockerClose = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.Track,
		Font = UiTheme.Header,
		TextSize = 16,
		TextColor3 = C.Panel,
		Text = "✕",
		Parent = locker,
	})
	UiTheme.corner(8, lockerClose)
	lockerClose.MouseButton1Click:Connect(function()
		locker.Visible = false
	end)

	local equipEvent = Remotes.get(Remotes.RequestEquip)
	local lockerItems = {} -- { {btn, slot, item} } restyled on every sync
	local function lockerSection(yOff: number, height: number, title: string, slot: string, list, columns: number)
		UiTheme.make("TextLabel", {
			BackgroundTransparency = 1,
			Font = UiTheme.Header,
			TextSize = 14,
			TextColor3 = C.Sub,
			Text = title,
			Position = UDim2.fromOffset(16, yOff),
			Size = UDim2.new(1, -32, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = locker,
		})
		local grid = UiTheme.make("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, yOff + 18),
			Size = UDim2.new(1, -32, 0, height),
			Parent = locker,
		})
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(1 / columns, -6, 0.5, -6)
		if #list <= columns then
			layout.CellSize = UDim2.new(1 / columns, -6, 1, -4)
		end
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.Parent = grid
		for _, item in ipairs(list) do
			local b = UiTheme.make("TextButton", {
				BackgroundColor3 = (slot == "boots" and (item :: any).color)
					or (slot == "trail" and (item :: any).c1)
					or Color3.fromRGB(90, 200, 140),
				Font = UiTheme.Header,
				TextScaled = true,
				TextColor3 = Color3.fromRGB(20, 22, 28),
				Text = item.name,
				AutoButtonColor = true,
				Parent = grid,
			})
			UiTheme.corner(10, b)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 0
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.Parent = b
			b.MouseButton1Click:Connect(function()
				equipEvent:FireServer(slot, item.id)
			end)
			lockerItems[#lockerItems + 1] = { btn = b, stroke = stroke, slot = slot, item = item }
		end
	end
	lockerSection(44, 120, "BOOTS", "boots", Cosmetics.Boots, 4)
	lockerSection(196, 52, "BALL TRAILS", "trail", Cosmetics.Trails, 5)
	lockerSection(264, 52, "GOAL CELEBRATIONS", "celebration", Cosmetics.Celebrations, 3)
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = 13,
		TextColor3 = C.Sub,
		Text = "Locked items show their level — every match earns XP!",
		Position = UDim2.fromOffset(16, 330),
		Size = UDim2.new(1, -32, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = locker,
	})

	lockerBtn.MouseButton1Click:Connect(function()
		locker.Visible = not locker.Visible
	end)

	-- restyle from every ProgressionSync: lock overlays + the equipped tick
	function MenuUI.cosmetics(equipped, level)
		level = tonumber(level) or 1
		for _, e in ipairs(lockerItems) do
			local locked = level < e.item.unlockLevel
			local isOn = equipped and equipped[e.slot] == e.item.id
			e.btn.Text = locked and ("🔒 Lv" .. e.item.unlockLevel) or ((isOn and "✓ " or "") .. e.item.name)
			e.btn.BackgroundTransparency = locked and 0.55 or 0
			e.stroke.Thickness = isOn and 3 or 0
		end
	end

	-- ❓ HOW TO PLAY: a one-screen card for first-timers (and our youngest players).
	-- Auto-shows on the very first visit and reopens from this button. Like the
	-- other menus it clears off-screen during live play, so it never clutters.
	-- 4th button slot: mobile row x=10/60/110/160 (after 🏆/👕/📋), desktop column
	-- y=266 (below 🏆122/👕170/📋218). MUST clear QuestUI's 📋 toggle, which lives
	-- in a separate (higher DisplayOrder) ScreenGui — same coords would hide this.
	local helpBtn = UiTheme.make("TextButton", {
		Position = UDim2.fromOffset(touch and 160 or 18, touch and 82 or 266),
		Size = UDim2.fromOffset(touch and 44 or 184, 40),
		BackgroundColor3 = Color3.fromRGB(255, 150, 90),
		Font = UiTheme.Header,
		TextSize = touch and 20 or 15,
		TextColor3 = C.Ink,
		Text = touch and "❓" or "❓ HOW TO PLAY",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(12, helpBtn)

	local howto = UiTheme.make("Frame", {
		Name = "HowTo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 0),
		Size = UDim2.new(0.9, 0, 0.8, 0),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.03,
		Visible = false,
		Parent = gui,
	})
	local howtoCap = Instance.new("UISizeConstraint")
	howtoCap.MaxSize = Vector2.new(500, 380)
	howtoCap.Parent = howto
	UiTheme.corner(18, howto)
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Header,
		TextSize = 24,
		TextColor3 = gold,
		Text = "⚽ HOW TO PLAY",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = howto,
	})
	local controlsText = touch
			and "Use the buttons on the lower-right.\n\n⚽ HOLD the SHOOT button to power up, then let go to kick!\n\nTap PASS, TACKLE and NUTMEG. Drag the left side of the screen to run."
		or "MOVE:  W A S D        SPRINT:  hold Shift\n\nPASS:  E        SHOOT:  hold Left-Click\n\nTACKLE:  F        NUTMEG:  Q"
	UiTheme.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = UiTheme.Body,
		TextSize = touch and 16 or 17,
		TextColor3 = C.Panel,
		Text = "🥅 Score more goals than the other team to win!\n\n⭐ Shoot at the goal under the gold ⬇ SCORE sign.\n\n"
			.. controlsText
			.. "\n\nHave a blast! 🎉",
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.new(1, -40, 1, -116),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = howto,
	})
	local gotIt = UiTheme.make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(200, 44),
		BackgroundColor3 = gold,
		Font = UiTheme.Header,
		TextSize = 20,
		TextColor3 = C.Ink,
		Text = "GOT IT!",
		AutoButtonColor = true,
		Parent = howto,
	})
	UiTheme.corner(12, gotIt)
	gotIt.MouseButton1Click:Connect(function()
		howto.Visible = false
	end)
	helpBtn.MouseButton1Click:Connect(function()
		howto.Visible = not howto.Visible
	end)

	-- ClientController pops this once on a brand-new player's first sync.
	function MenuUI.showHowTo()
		howto.Visible = true
	end

	-- ⚡ PENALTY SHOOTOUT mode: skip full games and play shootouts back-to-back
	-- (also the fastest way to practise penalties). Server-wide toggle; the button
	-- reflects the live mode from the match snapshot. 5th slot: mobile x=210,
	-- desktop y=314 (below ❓ at 266).
	local shootoutBtn = UiTheme.make("TextButton", {
		Position = UDim2.fromOffset(touch and 210 or 18, touch and 82 or 314),
		Size = UDim2.fromOffset(touch and 44 or 184, 40),
		BackgroundColor3 = C.PanelDark,
		Font = UiTheme.Header,
		TextSize = touch and 20 or 15,
		TextColor3 = C.Panel,
		Text = touch and "⚡" or "⚡ SHOOTOUT",
		AutoButtonColor = true,
		Parent = gui,
	})
	UiTheme.corner(12, shootoutBtn)
	UiTheme.stroke(gold, 1, shootoutBtn)
	local shootoutEvent = Remotes.get(Remotes.RequestShootout)
	shootoutBtn.MouseButton1Click:Connect(function()
		askConfirm("Switch the WHOLE server between full matches and penalty shootouts?", function()
			shootoutEvent:FireServer()
		end)
	end)

	-- reflect the live server mode (called by ClientController from the snapshot)
	function MenuUI.setShootoutMode(on)
		on = on and true or false
		shootoutBtn.BackgroundColor3 = on and gold or C.PanelDark
		shootoutBtn.TextColor3 = on and C.Ink or C.Panel
		if not touch then
			shootoutBtn.Text = on and "⚡ SHOOTOUT  ✓" or "⚡ SHOOTOUT"
		end
	end

	refs = { panel = panel, picker = picker, locker = locker, trophyBtn = trophyBtn, lockerBtn = lockerBtn, helpBtn = helpBtn, howto = howto, shootoutBtn = shootoutBtn, confirmBackdrop = confirmBackdrop }

	-- Desktop controls hint (hidden on touch devices, which have on-screen buttons)
	if not UserInputService.TouchEnabled then
		UiTheme.make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -44),
			Size = UDim2.fromOffset(680, 22),
			BackgroundTransparency = 1,
			Font = UiTheme.Body,
			TextSize = 15,
			TextColor3 = C.Panel,
			Text = "Hold LMB = Shoot   •   E = Pass   •   Q = Nutmeg   •   F = Tackle   •   Shift = Sprint",
			Parent = gui,
		}).TextStrokeTransparency = 0.4
	end
end

-- Called by ClientController on every match-state change. During live play we
-- close any open panel and — on mobile — clear the whole menu so the pitch is
-- unobstructed; the menu returns between matches.
function MenuUI.matchActive(active)
	if not refs then
		return
	end
	if active then
		if refs.picker then
			refs.picker.Visible = false
		end
		if refs.locker then
			refs.locker.Visible = false
		end
		if refs.howto then
			refs.howto.Visible = false
		end
		-- NOTE: the confirm modal is intentionally NOT cleared here — matchActive
		-- fires every 1s broadcast, which would clobber a just-opened confirm. It's a
		-- modal; it persists until the player taps YES/CANCEL.
	end
	if UserInputService.TouchEnabled then
		local show = not active
		if refs.panel then
			refs.panel.Visible = show
		end
		if refs.trophyBtn then
			refs.trophyBtn.Visible = show
		end
		if refs.lockerBtn then
			refs.lockerBtn.Visible = show
		end
		if refs.helpBtn then
			refs.helpBtn.Visible = show
		end
		if refs.shootoutBtn then
			refs.shootoutBtn.Visible = show
		end
	end
end

return MenuUI
