-- Audio Engine
-- Love2D adaptation following native Scratch architecture

local SimpleTimer = require("lib.SimpleTimer")
local log = require("lib.log")

---@class AudioManager
---@field soundPlayers table<string, AudioSound> Global soundId -> AudioSound mapping
---@field playerTargets table<string, table> soundId -> target (tracks which target last played this sound)
---@field soundEffects table<string, table> soundId -> {pitch, pan} effect state per sound
---@field playingSounds table<string, PlayingSound> soundId -> current PlayingSound instance
---@field waitingSounds table<table, table<PlayingSound, boolean>> target -> PlayingSound set for sounds waiting to complete
---@field masterVolume number
local AudioManager = {}
AudioManager.__index = AudioManager

---@class AudioSound
---@field id string Unique sound identifier (assetId or name)
---@field name string Sound name
---@field source love.Source Original source template
---@field duration number Sound duration in seconds
local AudioSound = {}
AudioSound.__index = AudioSound

---@class PlayingSound
---@field sound AudioSound
---@field source love.Source Cloned source for this playback
---@field target table
---@field startTime number
---@field pitch number
---@field pan number
---@field volume number
---@field waitTimer Timer|nil
---@field completed boolean
local PlayingSound = {}
PlayingSound.__index = PlayingSound


-- Utility -------------------------------------------------------------------

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end


-- PlayingSound ---------------------------------------------------------------

---@param sound AudioSound
---@param target table
---@param source love.Source
---@return PlayingSound
function PlayingSound:new(sound, target, source)
    return setmetatable({
        sound = sound,
        source = source,
        target = target,
        startTime = love.timer.getTime(),
        pitch = 1,
        pan = 0,
        volume = 1,
        waitTimer = nil,
        completed = false
    }, PlayingSound)
end

---Apply effects from the effect state
---@param effects table {pitch, pan} effect values
function PlayingSound:applyEffects(effects)
    local pitchSteps = (effects and effects.pitch) or 0
    local panValue = (effects and effects.pan) or 0

    -- Apply pitch (-360..360 => +/-3 octaves)
    self.pitch = clamp(math.pow(2, pitchSteps / 120), 0.1, 10)
    if self.source.setPitch then
        local ok = pcall(self.source.setPitch, self.source, self.pitch)
        if not ok then
            log.warn("AudioManager: Failed to set pitch for sound '%s'", self.sound.id)
        end
    end

    -- Apply pan (-100..100)
    -- Note: Only mono (1-channel) sources support spatial positioning
    self.pan = clamp(panValue, -100, 100)
    if self.source.setRelative and self.source.setPosition and self.source.getChannelCount then
        local ok, channels = pcall(self.source.getChannelCount, self.source)
        if ok and channels == 1 then
            -- Only apply spatial positioning to mono sources
            local positionX = clamp(self.pan / 100, -1, 1)
            local ok1 = pcall(self.source.setRelative, self.source, true)
            local ok2 = pcall(self.source.setPosition, self.source, positionX, 0, 0)
            if not ok1 or not ok2 then
                log.warn("AudioManager: Failed to set pan for sound '%s'", self.sound.id)
            end
        end
        if channels ~= 1 and self.pan ~= 0 then
            log.warn("AudioManager: Pan effect ignored for non-mono sound '%s'", self.sound.id)
        end
    end
end

---Apply volume from target and master volume
---@param targetVolume number Target volume (0-100)
---@param masterVolume number Master volume (0-1)
function PlayingSound:applyVolume(targetVolume, masterVolume)
    self.volume = clamp(targetVolume / 100, 0, 1)
    local applied = self.volume * (masterVolume or 1)
    if self.source.setVolume then
        local ok = pcall(self.source.setVolume, self.source, applied)
        if not ok then
            log.warn("AudioManager: Failed to set volume for sound '%s'", self.sound.id)
        end
    end
end

function PlayingSound:play()
    if not self.source then
        return false
    end

    if self.source.setLooping then
        local ok = pcall(self.source.setLooping, self.source, false)
        if not ok then
            log.warn("AudioManager: Failed to set looping for sound '%s'", self.sound.id)
        end
    end

    local ok = true
    if self.source.play then
        ok = pcall(self.source.play, self.source)
    elseif love and love.audio and love.audio.play then
        ok = pcall(love.audio.play, self.source)
    end

    if not ok then
        log.warn("AudioManager: Failed to play sound '%s'", self.sound.id)
        self.completed = true
    end

    return ok
end

function PlayingSound:stop()
    if self.completed then
        return
    end

    if self.source and self.source.stop then
        local ok = pcall(self.source.stop, self.source)
        if not ok then
            log.warn("AudioManager: Failed to stop sound '%s'", self.sound.id)
        end
    end

    self.completed = true
    if self.waitTimer then
        self.waitTimer.elapsed = self.waitTimer.duration
        self.waitTimer.status = SimpleTimer.Status.Completed
        self.waitTimer = nil
    end
end

function PlayingSound:isFinished()
    if self.completed then
        return true
    end

    if self.source and self.source.isPlaying then
        local ok, playing = pcall(self.source.isPlaying, self.source)
        if ok and playing then
            return false
        end
    end

    -- Fallback to time-based check
    local expectedDuration = self.sound.duration / self.pitch
    return (love.timer.getTime() - self.startTime) >= expectedDuration
end

-- Sound ----------------------------------------------------------------------

---@param soundData Sound
---@return AudioSound|nil
function AudioSound:new(soundData)
    local id = soundData.assetId or soundData.md5ext or soundData.name or "unknown_sound"
    local name = soundData.name or "Unknown"
    local source = soundData.source

    -- Log warning if no source available
    if not source then
        log.warn("AudioManager: Missing audio source for '%s'", id)
        return nil
    end

    return setmetatable({
        id = id,
        name = name,
        source = source,
        duration = soundData.duration or 0
    }, AudioSound)
end

---Create a playback instance for this sound
---@param target table
---@return PlayingSound|nil
function AudioSound:createPlayback(target)
    if not self.source then
        return nil
    end

    -- Clone source for concurrent playback
    local clonedSource = self.source
    if self.source.clone then
        local ok, clone = pcall(self.source.clone, self.source)
        if ok and clone then
            clonedSource = clone
        end
    end

    return PlayingSound:new(self, target, clonedSource)
end

-- AudioManager ---------------------------------------------------------------
-- Native Scratch equivalent: AudioEngine + SoundBank combined

---@return AudioManager
function AudioManager:new()
    local manager = setmetatable({
        soundPlayers = {},      -- soundId -> AudioSound (global)
        playerTargets = {},     -- soundId -> target (tracks current target for each sound)
        soundEffects = {},      -- soundId -> {pitch, pan} (per-sound effect state)
        playingSounds = {},     -- soundId -> PlayingSound (current playback instance)
        waitingSounds = {},     -- target -> Set<PlayingSound> (sounds waiting to complete)
        masterVolume = love.audio.getVolume()
    }, AudioManager)

    return manager
end

---Add a sound player to the bank
---@param soundData table Sound data from project
function AudioManager:addSoundPlayer(soundData)
    local sound = AudioSound:new(soundData)
    if sound then
        self.soundPlayers[sound.id] = sound
        -- Initialize effect state for this sound
        if not self.soundEffects[sound.id] then
            self.soundEffects[sound.id] = {pitch = 0, pan = 0}
        end
        log.debug("AudioManager: Added sound player '%s' (%s)", sound.name, sound.id)
    end
end

---Get a sound player by id
---@param soundId string
---@return AudioSound|nil
function AudioManager:getSoundPlayer(soundId)
    local player = self.soundPlayers[soundId]
    if not player then
        log.warn("AudioManager: Missing sound player for soundId '%s'", soundId)
    end
    return player
end

---Get effect state for a sound
---@param soundId string
---@return table Effect state {pitch, pan}
function AudioManager:getSoundEffects(soundId)
    if not self.soundEffects[soundId] then
        self.soundEffects[soundId] = {pitch = 0, pan = 0}
    end
    return self.soundEffects[soundId]
end

---Play a sound for a target
---@param target table
---@param soundId string
---@param waitForDone boolean
---@return Timer|nil
function AudioManager:playSound(target, soundId, waitForDone)
    local player = self:getSoundPlayer(soundId)
    if not player then
        return nil
    end

    -- If a different target is using this sound, stop the old playback
    local currentTarget = self.playerTargets[soundId]
    if currentTarget and currentTarget ~= target then
        log.debug("AudioManager: Forking sound '%s' from target '%s' to '%s'",
            soundId, currentTarget.name or "unknown", target.name or "unknown")
        -- Stop old playback
        local oldPlayback = self.playingSounds[soundId]
        if oldPlayback then
            oldPlayback:stop()
        end
    end

    -- Update target tracking
    self.playerTargets[soundId] = target

    -- Get/create effect state for this sound
    local effects = self:getSoundEffects(soundId)

    -- Create new playback instance
    local playback = player:createPlayback(target)
    if not playback then
        return nil
    end

    -- Set effects from target's soundEffects (if exists) or use sound's effect state
    local targetEffects = target.soundEffects or effects
    playback:applyEffects(targetEffects)
    playback:applyVolume(target.volume or 100, self.masterVolume)

    -- Start playback
    if not playback:play() then
        return nil
    end

    -- Track playing sound
    self.playingSounds[soundId] = playback

    -- Handle wait for completion
    if waitForDone then
        local duration = math.max(player.duration / playback.pitch, 1/60)
        local timer = SimpleTimer.delay(duration)
        playback.waitTimer = timer

        if not self.waitingSounds[target] then
            self.waitingSounds[target] = {}
        end
        self.waitingSounds[target][playback] = true

        return timer
    end

    return nil
end

---Stop a sound if it was last played by the given target
---@param target table
---@param soundId string
function AudioManager:stop(target, soundId)
    -- Only stop if this target was the last to play this sound
    if self.playerTargets[soundId] ~= target then
        return
    end

    local playback = self.playingSounds[soundId]
    if playback then
        playback:stop()
        self.playingSounds[soundId] = nil

        -- Clean up waiting sounds
        if self.waitingSounds[target] then
            self.waitingSounds[target][playback] = nil
        end
    end
end

---Stop all sounds for a target or globally
---@param target table|nil If nil, stop all sounds globally
function AudioManager:stopAllSounds(target)
    if not target then
        -- Stop all Love2D audio
        local ok = pcall(love.audio.stop)
        if not ok then
            log.warn("AudioManager: Failed to stop all audio")
        end

        -- Stop all tracked sounds
        for _, playback in pairs(self.playingSounds) do
            playback:stop()
        end
        self.playingSounds = {}
        self.playerTargets = {}
        self.waitingSounds = {}
        return
    end

    -- Stop sounds for specific target
    -- Iterate through playerTargets to find sounds this target is using
    for soundId, playerTarget in pairs(self.playerTargets) do
        if playerTarget == target then
            local playback = self.playingSounds[soundId]
            if playback then
                playback:stop()
                self.playingSounds[soundId] = nil
            end
            self.playerTargets[soundId] = nil
        end
    end

    -- Clean up waiting sounds for this target
    self.waitingSounds[target] = nil
end

---Set effects for all sounds currently played by target
---@param target table
function AudioManager:setEffects(target)
    -- Update effects for all sounds this target is currently playing
    for soundId, playerTarget in pairs(self.playerTargets) do
        if playerTarget == target then
            local playback = self.playingSounds[soundId]
            if playback then
                local targetEffects = target.soundEffects or self:getSoundEffects(soundId)
                playback:applyEffects(targetEffects)
            end
        end
    end
end

---Update volume for all sounds currently played by target
---@param target table
function AudioManager:updateVolume(target)
    -- Update volume for all sounds this target is currently playing
    for soundId, playerTarget in pairs(self.playerTargets) do
        if playerTarget == target then
            local playback = self.playingSounds[soundId]
            if playback then
                playback:applyVolume(target.volume or 100, self.masterVolume)
            end
        end
    end
end

---Set global master volume
---@param volume number Volume 0-1
function AudioManager:setGlobalVolume(volume)
    self.masterVolume = clamp(volume, 0, 1)
    local ok = pcall(love.audio.setVolume, self.masterVolume)
    if not ok then
        log.warn("AudioManager: Failed to set global volume")
    end

    -- Update all playing sounds
    for soundId, playback in pairs(self.playingSounds) do
        local target = self.playerTargets[soundId]
        if target then
            playback:applyVolume(target.volume or 100, self.masterVolume)
        end
    end
end

---Check if target has any sounds waiting to complete
---@param target table
---@return boolean
function AudioManager:hasWaitingSounds(target)
    local waiting = self.waitingSounds[target]
    if not waiting then
        return false
    end
    for _ in pairs(waiting) do
        return true
    end
    return false
end

---Update audio system - clean up finished sounds
function AudioManager:update()
    -- Clean up finished sounds
    for soundId, playback in pairs(self.playingSounds) do
        if playback:isFinished() then
            playback:stop()
            self.playingSounds[soundId] = nil

            local target = self.playerTargets[soundId]
            if target and self.waitingSounds[target] then
                self.waitingSounds[target][playback] = nil
            end
        end
    end

    -- Clean up empty waiting sound sets
    for target, waitingSet in pairs(self.waitingSounds) do
        if next(waitingSet) == nil then
            self.waitingSounds[target] = nil
        end
    end
end

return AudioManager
