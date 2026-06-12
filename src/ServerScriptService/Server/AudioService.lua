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

-- MATCH COMMENTARY: licensed announcer lines from the Notable Voices and
-- Apple Hill Studios packs (owned for the Hytopia original), re-uploaded to
-- this creator account via Open Cloud (tools/audio_pipeline/, manifest in
-- uploaded.json). One voice, broadcast-style: never talks over itself, and
-- priority lines (goals, full time) cut whatever else was being said.
local COMMENTARY_IDS: { [string]: { number } } = {
	kickoff = { 120845229617056 },  -- "Game Start"
	goal = { 104462952127702, 79267049967666, 91931519210036 }, -- What A Goal / What A Beauty / Crowd Goes Wild
	save = { 136618842417043 },     -- "Beautiful Save"
	nearMiss = { 98312663627363, 95682027071520 }, -- "Near Miss" / "So Close"
	bigShot = { 91152581781107 },   -- "What A Shot" (was still in review 2026-06-12; plays once approved)
	onFire = { 132313435848225 },   -- "He's On Fire Now"
	fullTime = { 136770975225532 }, -- "It's All Over"
}

-- licensed crowd chant beds (tools/audio_pipeline/upload_chants.ps1);
-- 0 = not uploaded yet, silently skipped
local CHANT_IDS = {
	melodic = 86240961980688, -- swells with late-half tension (was in review at bake time)
	ultras = 75352524812158, -- erupts on goals
}

local CROWD_BASE_VOLUME = 0.22
local COMMENTARY_GAP = 4 -- seconds between non-priority lines

local crowd: Sound? = nil
local chantMelodic: Sound? = nil
local chantUltras: Sound? = nil
local oneShots: { [string]: Sound } = {}
local kickVariants: { Sound } = {}
local commentaryPools: { [string]: { Sound } } = {}
local commentaryGapUntil = 0
local commentarySpeaking: Sound? = nil

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
-- streak = the scorer's goals this match: 2+ gets the "on fire" call instead.
function AudioService.goal(streak: number?)
	playOneShot("GoalRoar")
	playOneShot("GoalHorn")
	task.delay(0.55, function()
		local kind = (streak and streak >= 2 and #(commentaryPools.onFire or {}) > 0) and "onFire" or "goal"
		AudioService.commentary(kind, true)
	end)
	-- the ultras erupt, then settle over the celebration
	pcall(function()
		local u = chantUltras
		if u then
			u.Volume = 0.34
			TweenService:Create(u, TweenInfo.new(4.5, Enum.EasingStyle.Quad), { Volume = 0 }):Play()
		end
	end)
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

-- Crowd tension: the ambient loop leans in as the clock runs down
-- (0 = normal murmur, 1 = full final-minute buzz), and the melodic
-- chant bed rises with it.
function AudioService.tension(frac: number)
	pcall(function()
		frac = math.clamp(frac, 0, 1)
		local c = crowd
		if c then
			c.Volume = CROWD_BASE_VOLUME * (1 + 0.9 * frac)
			c.PlaybackSpeed = 1 + 0.06 * frac
		end
		if chantMelodic then
			chantMelodic.Volume = 0.16 * frac
		end
	end)
end

-- One commentator line of the given kind. Non-priority lines respect a gap
-- and never interrupt; priority lines (goal calls, full time) cut in.
function AudioService.commentary(kind: string, priority: boolean?)
	pcall(function()
		local pool = commentaryPools[kind]
		if not pool or #pool == 0 then
			return
		end
		local now = os.clock()
		local speaking = commentarySpeaking
		if priority then
			if speaking and speaking.IsPlaying then
				speaking:Stop()
			end
		else
			if now < commentaryGapUntil then
				return
			end
			if speaking and speaking.IsPlaying then
				return -- a good commentator finishes the sentence
			end
		end
		local s = pool[math.random(1, #pool)]
		commentaryGapUntil = now + COMMENTARY_GAP
		commentarySpeaking = s
		s.TimePosition = 0
		s:Play()
	end)
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
		for kind, ids in pairs(COMMENTARY_IDS) do
			local pool = {}
			for i, id in ipairs(ids) do
				pool[i] = makeSound("Commentary_" .. kind .. i, id, 0.9, false)
			end
			commentaryPools[kind] = pool
		end
		-- chant beds idle at zero volume until tension/goals raise them
		if CHANT_IDS.melodic ~= 0 then
			chantMelodic = makeSound("ChantMelodic", CHANT_IDS.melodic, 0, true)
			;(chantMelodic :: Sound):Play()
		end
		if CHANT_IDS.ultras ~= 0 then
			chantUltras = makeSound("ChantUltras", CHANT_IDS.ultras, 0, true)
			;(chantUltras :: Sound):Play()
		end
	end)
end

return AudioService
