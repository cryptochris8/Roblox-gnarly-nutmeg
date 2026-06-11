--!strict
-- PlayerDataService (SERVER)
-- Persists each player's career stats (goals, wins, losses, draws, matches) with
-- DataStores: load on join, save on leave, periodic autosave, and a BindToClose
-- flush. Mirrors the robust pattern from Squishy Smash -- if DataStores are
-- unavailable (unpublished place / API access off) it falls back to an in-memory
-- session so the game still runs, it just won't persist.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local DATASTORE_NAME = "GnarlyNutmegData_v1"
local DATA_VERSION = 1
local MAX_RETRIES = 4
local AUTOSAVE_INTERVAL = 90

local store: DataStore? = nil
local storeEnabled = false
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
		storeEnabled = true
	else
		warn("[Gnarly Nutmeg] DataStore unavailable — stats will NOT persist this session. "
			.. "Publish the place + enable Studio Access to API Services to save. (" .. tostring(result) .. ")")
	end
end

local PlayerDataService = {}

export type Profile = {
	Goals: number,
	Wins: number,
	Losses: number,
	Draws: number,
	Matches: number,
	Nutmegs: number,
	Trophies: number,
}

local profiles: { [Player]: Profile } = {}
local loadedOk: { [Player]: boolean } = {}

local function newProfile(): Profile
	return { Goals = 0, Wins = 0, Losses = 0, Draws = 0, Matches = 0, Nutmegs = 0, Trophies = 0 }
end

local function serialize(p: Profile)
	return {
		version = DATA_VERSION,
		Goals = p.Goals, Wins = p.Wins, Losses = p.Losses, Draws = p.Draws, Matches = p.Matches,
		Nutmegs = p.Nutmegs, Trophies = p.Trophies,
	}
end

local function deserialize(data: any): Profile
	local p = newProfile()
	if type(data) == "table" then
		p.Goals = tonumber(data.Goals) or 0
		p.Wins = tonumber(data.Wins) or 0
		p.Losses = tonumber(data.Losses) or 0
		p.Draws = tonumber(data.Draws) or 0
		p.Matches = tonumber(data.Matches) or 0
		p.Nutmegs = tonumber(data.Nutmegs) or 0
		p.Trophies = tonumber(data.Trophies) or 0
	end
	return p
end

local function keyFor(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

local function loadData(player: Player): (boolean, any)
	local s = store
	if not (storeEnabled and s) then
		return false, nil
	end
	local key = keyFor(player)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return s:GetAsync(key)
		end)
		if ok then
			return true, result
		end
		warn(string.format("[Gnarly Nutmeg] load failed for %s (%d/%d): %s", player.Name, attempt, MAX_RETRIES, tostring(result)))
		task.wait(attempt * 1.5)
	end
	return false, nil
end

local function saveData(player: Player): boolean
	local p = profiles[player]
	if not p then
		return false
	end
	local s = store
	if not (storeEnabled and s) then
		return false
	end
	if loadedOk[player] == false then
		warn(string.format("[Gnarly Nutmeg] skipping save for %s — load failed, won't overwrite.", player.Name))
		return false
	end
	local key = keyFor(player)
	local payload = serialize(p)
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			s:UpdateAsync(key, function()
				return payload
			end)
		end)
		if ok then
			return true
		end
		warn(string.format("[Gnarly Nutmeg] save failed for %s (%d/%d): %s", player.Name, attempt, MAX_RETRIES, tostring(err)))
		task.wait(attempt * 1.5)
	end
	return false
end

local function setupLeaderstats(player: Player, p: Profile)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local goals = Instance.new("IntValue")
	goals.Name = "Goals"
	goals.Value = p.Goals
	goals.Parent = stats
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = p.Wins
	wins.Parent = stats
	local megs = Instance.new("IntValue")
	megs.Name = "Nutmegs"
	megs.Value = p.Nutmegs
	megs.Parent = stats
	local trophies = Instance.new("IntValue")
	trophies.Name = "Trophies"
	trophies.Value = p.Trophies
	trophies.Parent = stats
	stats.Parent = player
end

local function refresh(player: Player, p: Profile)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local goals = stats:FindFirstChild("Goals") :: IntValue?
	if goals then
		goals.Value = p.Goals
	end
	local wins = stats:FindFirstChild("Wins") :: IntValue?
	if wins then
		wins.Value = p.Wins
	end
	local megs = stats:FindFirstChild("Nutmegs") :: IntValue?
	if megs then
		megs.Value = p.Nutmegs
	end
	local trophies = stats:FindFirstChild("Trophies") :: IntValue?
	if trophies then
		trophies.Value = p.Trophies
	end
end

function PlayerDataService.get(player: Player): Profile?
	return profiles[player]
end

function PlayerDataService.addGoal(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	p.Goals += 1
	refresh(player, p)
end

function PlayerDataService.addNutmeg(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	p.Nutmegs += 1
	refresh(player, p)
end

function PlayerDataService.addTrophy(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	p.Trophies += 1
	refresh(player, p)
end

function PlayerDataService.recordResult(player: Player, outcome: string)
	local p = profiles[player]
	if not p then
		return
	end
	p.Matches += 1
	if outcome == "win" then
		p.Wins += 1
	elseif outcome == "loss" then
		p.Losses += 1
	else
		p.Draws += 1
	end
	refresh(player, p)
end

function PlayerDataService.init()
	local function onAdded(player: Player)
		local ok, data = loadData(player)
		if player.Parent == nil then
			return
		end
		loadedOk[player] = ok
		local profile = ok and deserialize(data) or newProfile()
		profiles[player] = profile
		setupLeaderstats(player, profile)
		if not ok and storeEnabled then
			warn(string.format("[Gnarly Nutmeg] %s on a temporary profile — stats won't save this session.", player.Name))
		end
	end

	Players.PlayerAdded:Connect(onAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveData(player)
		profiles[player] = nil
		loadedOk[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(saveData, player)
			end
		end
	end)

	game:BindToClose(function()
		local players = Players:GetPlayers()
		if #players == 0 then
			return
		end
		local remaining = #players
		for _, player in ipairs(players) do
			task.spawn(function()
				saveData(player)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return PlayerDataService
