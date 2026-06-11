--!strict
-- AudioService (SERVER)
-- Stadium sound: an ambient crowd loop plus event one-shots (whistles, kick
-- thumps, goal roar + horn, a crowd "ooh" for nutmegs). Every asset is a free,
-- license-vetted Creator Store sound (the ProSoundEffects "(SFX)" library plus
-- one community goal horn), each verified loadable in Studio before being baked
-- in. Sounds are parented to SoundService (global, non-positional broadcast
-- feel). Cosmetic only: every call is pcall-safe and a missing sound can never
-- affect the match.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioService = {}

local IDS = {
	WhistleShort = 9118114608, -- Referee Whistle Interior Gymnasium 4 (SFX)
	WhistleLong = 9125803561,  -- Referee Whistle Interior Gymnasium Short Blo (SFX)
	Kicks = { 9119328794, 9119329117, 9119329315 }, -- Soccer Ball Kicks On Surfaces 25/28/30 (SFX)
	CrowdLoop = 9119562843,    -- Stadium Crowd 2 (SFX), 48s loop
	GoalRoar = 9120974911,     -- Wrestling Crowd 1 (SFX), big roar
	GoalHorn = 134429090011410, -- "Goal horn" (TheAwesomeOcelot111, free)
	CrowdOoh = 9120975564,     -- Wrestling Crowd 6 (SFX), reaction sting
}

local CROWD_BASE_VOLUME = 0.22

local crowd: Sound? = nil
local oneShots: { [string]: Sound } = {}
local kickVariants: { Sound } = {}

local function makeSound(name: string, id: number, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume
	s.Looped = looped
	s.Parent = SoundService
	return s
end

local function playOneShot(name: string)
	pcall(function()
		local s = oneShots[name]
		if s then
			s.TimePosition = 0
			s:Play()
		end
	end)
end

-- Referee whistle: "short" = kickoffs/dead balls, "long" = half/full time.
function AudioService.whistle(kind: string)
	playOneShot(kind == "long" and "WhistleLong" or "WhistleShort")
end

-- Ball-strike thump; power 0..1 sets volume, with a little pitch variety.
function AudioService.kick(power: number)
	pcall(function()
		if #kickVariants == 0 then
			return
		end
		local s = kickVariants[math.random(1, #kickVariants)]
		s.Volume = 0.3 + 0.4 * math.clamp(power or 0.5, 0, 1)
		s.PlaybackSpeed = 0.92 + math.random() * 0.16
		s.TimePosition = 0
		s:Play()
	end)
end

-- Goal: roar + horn together, and the ambient crowd swells then settles.
function AudioService.goal()
	playOneShot("GoalRoar")
	playOneShot("GoalHorn")
	pcall(function()
		local c = crowd
		if c then
			c.Volume = CROWD_BASE_VOLUME * 2.4
			TweenService:Create(c, TweenInfo.new(3.5), { Volume = CROWD_BASE_VOLUME }):Play()
		end
	end)
end

-- Crowd reaction sting (nutmegs, near misses).
function AudioService.ooh()
	playOneShot("CrowdOoh")
end

function AudioService.init()
	pcall(function()
		crowd = makeSound("StadiumCrowd", IDS.CrowdLoop, CROWD_BASE_VOLUME, true)
		;(crowd :: Sound):Play()
		oneShots.WhistleShort = makeSound("WhistleShort", IDS.WhistleShort, 0.5, false)
		oneShots.WhistleLong = makeSound("WhistleLong", IDS.WhistleLong, 0.5, false)
		oneShots.GoalRoar = makeSound("GoalRoar", IDS.GoalRoar, 0.6, false)
		oneShots.GoalHorn = makeSound("GoalHorn", IDS.GoalHorn, 0.45, false)
		oneShots.CrowdOoh = makeSound("CrowdOoh", IDS.CrowdOoh, 0.5, false)
		for i, id in ipairs(IDS.Kicks) do
			kickVariants[i] = makeSound("Kick" .. i, id, 0.5, false)
		end
	end)
end

return AudioService
