--!strict
-- LeaderboardService (SERVER)
-- Weekly global leaderboards (goals + wins) on OrderedDataStores keyed by the
-- UTC week, rendered on a pitchside board. Writes are fire-and-forget and
-- pcall-guarded; in unpublished places the store is unavailable and the board
-- simply shows the offline note (same graceful fallback as PlayerDataService).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LeaderboardService = {}

local REFRESH_SECONDS = 75
local TOP_N = 8

local enabled = false
local nameCache: { [number]: string } = {}

local function weekKey(): string
	return tostring(math.floor(os.time() / 604800))
end

local function store(kind: string): OrderedDataStore?
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore("GN_Wk" .. kind .. "_" .. weekKey())
	end)
	return ok and s or nil
end

local function bump(kind: string, player: Player, amount: number)
	if not enabled then
		return
	end
	task.spawn(function()
		pcall(function()
			local s = store(kind)
			if s then
				s:IncrementAsync(tostring(player.UserId), amount)
			end
		end)
	end)
end

function LeaderboardService.addGoal(player: Player)
	bump("Goals", player, 1)
end

function LeaderboardService.addWin(player: Player)
	bump("Wins", player, 1)
end

local function nameFor(uid: number): string
	local cached = nameCache[uid]
	if cached then
		return cached
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(uid)
	end)
	local name = ok and n or ("#" .. uid)
	nameCache[uid] = name
	return name
end

local goalsLabel: TextLabel? = nil
local winsLabel: TextLabel? = nil

local function buildBoard()
	pcall(function()
		local pitch = Workspace:FindFirstChild("Pitch")
		if not pitch then
			return
		end
		local board = Instance.new("Part")
		board.Name = "WeeklyBoard"
		board.Anchored = true
		board.CanCollide = false
		board.Size = Vector3.new(20, 11, 1)
		board.Color = Color3.fromRGB(18, 20, 26)
		board.Material = Enum.Material.SmoothPlastic
		-- east apron edge, facing the pitch
		board.CFrame = CFrame.lookAt(Vector3.new(86, 7.5, 0), Vector3.new(0, 7.5, 0))
		board.Parent = pitch
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(800, 440)
		gui.LightInfluence = 0
		gui.Brightness = 1.6
		gui.Parent = board
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0.16, 0)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(245, 196, 60)
		title.Text = "🏆 THIS WEEK'S BEST"
		title.Parent = gui
		local function column(x: number, header: string): TextLabel
			local h = Instance.new("TextLabel")
			h.BackgroundTransparency = 1
			h.Position = UDim2.new(x, 0, 0.17, 0)
			h.Size = UDim2.new(0.48, 0, 0.1, 0)
			h.Font = Enum.Font.GothamBold
			h.TextScaled = true
			h.TextColor3 = Color3.fromRGB(200, 210, 230)
			h.Text = header
			h.Parent = gui
			local body = Instance.new("TextLabel")
			body.BackgroundTransparency = 1
			body.Position = UDim2.new(x, 0, 0.29, 0)
			body.Size = UDim2.new(0.48, 0, 0.69, 0)
			body.Font = Enum.Font.Gotham
			body.TextScaled = true
			body.TextColor3 = Color3.fromRGB(235, 238, 245)
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextYAlignment = Enum.TextYAlignment.Top
			body.Text = enabled and "…" or "(offline in Studio test)"
			body.Parent = gui
			return body
		end
		goalsLabel = column(0.02, "⚽ GOALS")
		winsLabel = column(0.52, "🏅 WINS")
	end)
end

local function renderTop(kind: string, label: TextLabel?)
	if not (enabled and label) then
		return
	end
	pcall(function()
		local s = store(kind)
		if not s then
			return
		end
		local page = s:GetSortedAsync(false, TOP_N):GetCurrentPage()
		local lines = {}
		for i, entry in ipairs(page) do
			lines[#lines + 1] = string.format("%d. %s — %d", i, nameFor(tonumber(entry.key) or 0), entry.value)
		end
		label.Text = (#lines > 0) and table.concat(lines, "\n") or "Be the first this week!"
	end)
end

function LeaderboardService.init()
	enabled = pcall(function()
		-- a cheap probe: creating the handle throws when the API is unavailable
		DataStoreService:GetOrderedDataStore("GN_Probe"):GetSortedAsync(false, 1)
	end)
	buildBoard()
	task.spawn(function()
		while true do
			renderTop("Goals", goalsLabel)
			renderTop("Wins", winsLabel)
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
