--!strict
-- Remotes
-- One source of truth for our RemoteEvent names + helpers so server and client
-- never disagree. The SERVER calls setupServer() once at startup to build a folder
-- of RemoteEvents under ReplicatedStorage; either side calls get(name).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.FOLDER_NAME = "GnarlyRemotes"

-- client -> server (intents; the server validates everything)
Remotes.RequestInitialState = "RequestInitialState" -- "I'm ready, send me match state"
Remotes.SelectTeam = "SelectTeam"                    -- team: "Red" | "Blue" | "Auto"
Remotes.RequestPass = "RequestPass"                  -- pass to my best teammate
Remotes.RequestShoot = "RequestShoot"                -- charge: number 0..1 (release power)
Remotes.RequestTackle = "RequestTackle"              -- attempt a steal in front of me
Remotes.RequestNutmeg = "RequestNutmeg"              -- poke the ball through a close defender
Remotes.SetSprint = "SetSprint"                      -- on: boolean (hold to sprint)
Remotes.StartTournament = "StartTournament"          -- nationName: begin a Nutmeg Trophy run
Remotes.RequestSkill = "RequestSkill"                -- skillId: perform an unlocked skill move

-- server -> client
Remotes.MatchState = "MatchState"               -- full snapshot (phase, scores, time, your team/role)
Remotes.Countdown = "Countdown"                 -- n: 3,2,1 then 0 = GO
Remotes.GoalScored = "GoalScored"               -- { team = "Red"|"Blue", scorer = string }
Remotes.StaminaUpdate = "StaminaUpdate"         -- value: number 0..1 (this player)
Remotes.PossessionChanged = "PossessionChanged" -- userId: number (0 = loose ball / bot)
Remotes.Nutmeg = "Nutmeg"                       -- { name = string, byUserId = number }
Remotes.ProgressionSync = "ProgressionSync"     -- { xp, level, xpInto, xpNeed, quests, streak }
Remotes.Toast = "Toast"                         -- text: string (small friendly message)
Remotes.TournamentLobby = "TournamentLobby"     -- { open: boolean, seconds: number?, host: string? }

local ALL_EVENTS = {
	Remotes.RequestInitialState,
	Remotes.SelectTeam,
	Remotes.RequestPass,
	Remotes.RequestShoot,
	Remotes.RequestTackle,
	Remotes.RequestNutmeg,
	Remotes.SetSprint,
	Remotes.StartTournament,
	Remotes.RequestSkill,
	Remotes.ProgressionSync,
	Remotes.MatchState,
	Remotes.Countdown,
	Remotes.GoalScored,
	Remotes.StaminaUpdate,
	Remotes.PossessionChanged,
	Remotes.TournamentLobby,
	Remotes.Nutmeg,
	Remotes.Toast,
}

-- SERVER ONLY: build the folder + RemoteEvents, then parent the folder LAST so
-- clients never see a half-built tree.
function Remotes.setupServer(): Folder
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER_NAME
	for _, eventName in ipairs(ALL_EVENTS) do
		local event = Instance.new("RemoteEvent")
		event.Name = eventName
		event.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

-- EITHER SIDE: get a RemoteEvent by name (waits until it exists).
function Remotes.get(eventName: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	return folder:WaitForChild(eventName) :: RemoteEvent
end

return Remotes
