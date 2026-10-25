-- The ELS rules, shared by the server, every player's game and the tests. No FiveM natives here,
-- so it runs in plain Lua:  lua tests/els_spec.lua

PrestonEls = {}
local E = PrestonEls

local function isIndex(value, count)
    return type(value) == 'number' and value == math.floor(value) and value >= 1 and value <= count
end

-- A vehicle's ELS settings. name is its spawn name if it's listed in config.Vehicles, otherwise nil.
function E.settingsFor(config, name)
    local listed = name and config.Vehicles[name] or nil
    local lights = listed and listed.lights == 'extras' and 'extras' or 'native'
    local tones = listed and listed.tones
    return {
        listed = listed ~= nil,
        lights = lights,
        extras = lights == 'extras' and (listed.extras or {}) or {},
        nativeLights = lights == 'native' or (listed.nativeToo == true),
        tones = (type(tones) == 'table' and #tones > 0) and tones or config.Tones,
    }
end

-- A clean copy of a vehicle's ELS state, with anything missing or invalid switched off.
-- seq and by record which request made it (so a driver's game can tell its own old requests apart).
function E.normalize(state)
    state = type(state) == 'table' and state or {}
    local function count(value)
        return (type(value) == 'number' and value == math.floor(value) and value >= 1) and value or 1
    end
    return {
        lights = state.lights == true,
        siren = state.siren == true,
        horn = state.horn == true,
        tone = count(state.tone),
        pattern = count(state.pattern),
        seq = type(state.seq) == 'number' and state.seq or 0,
        by = type(state.by) == 'number' and state.by or 0,
    }
end

function E.same(a, b)
    a, b = E.normalize(a), E.normalize(b)
    for key, value in pairs(a) do
        if b[key] ~= value then return false end
    end
    return true
end

-- Applies a driver's change to the current state.
-- change can set lights, siren and horn (true/false), tone and pattern (1, 2, 3...).
-- Returns the new state, or nil and the reason it was refused.
function E.applyChange(current, change, settings, patternCount)
    if type(change) ~= 'table' or next(change) == nil then return nil, 'empty request' end
    local new = E.normalize(current)
    for key, value in pairs(change) do
        if key == 'lights' or key == 'siren' or key == 'horn' then
            if type(value) ~= 'boolean' then return nil, ('%s must be true or false'):format(key) end
            new[key] = value
        elseif key == 'tone' then
            if not isIndex(value, #settings.tones) then return nil, 'unknown siren tone' end
            new.tone = value
        elseif key == 'pattern' then
            if not isIndex(value, patternCount) then return nil, 'unknown light pattern' end
            new.pattern = value
        else
            return nil, ('unknown setting "%s"'):format(tostring(key))
        end
    end
    -- The siren only runs with the lights on: switching the siren on also switches the lights on,
    -- and switching the lights off also stops the siren.
    if change.siren == true then
        new.lights = true
    elseif not new.lights then
        new.siren = false
    end
    if new.tone > #settings.tones then new.tone = 1 end
    if new.pattern > patternCount then new.pattern = 1 end
    return new
end

-- True when a change only switches things off. The last driver may still do that after getting out.
function E.onlyTurnsOff(change)
    if type(change) ~= 'table' or next(change) == nil then return false end
    for key, value in pairs(change) do
        if not ((key == 'lights' or key == 'siren' or key == 'horn') and value == false) then return false end
    end
    return true
end

-- Which frame of a pattern is showing, elapsedMs after the lights came on. Returns its number and
-- the list of light slots that are on in it.
function E.patternFrame(pattern, elapsedMs)
    local frames = pattern and pattern.frames or {}
    if #frames == 0 then return 1, {} end
    local step = math.max(tonumber(pattern.step) or 100, 20)
    local index = math.floor(math.max(elapsedMs, 0) / step) % #frames + 1
    return index, frames[index]
end

-- The vehicle extras to turn on for a frame: light slots mapped to that vehicle's extra numbers.
function E.extrasForFrame(frame, extras)
    local on = {}
    for _, slot in ipairs(frame or {}) do
        if extras[slot] then on[extras[slot]] = true end
    end
    return on
end

-- The siren sound that should be playing: none with the siren off, and none while the air horn
-- is held (it cuts through the siren, like a real one).
function E.toneSound(state, settings)
    if not state.siren or state.horn then return nil end
    local tone = settings.tones[state.tone] or settings.tones[1]
    return tone and tone.sound or nil
end

-- Problems in a config, as a list of readable lines (empty when it's fine). Printed on start.
function E.checkConfig(config)
    local problems = {}
    local function add(...) problems[#problems + 1] = string.format(...) end
    local function checkTones(tones, where)
        if type(tones) ~= 'table' or #tones == 0 then return add('%s: needs at least one tone', where) end
        for i, tone in ipairs(tones) do
            if type(tone.sound) ~= 'string' or tone.sound == '' then add('%s: tone %d has no sound', where, i) end
            if type(tone.label) ~= 'string' or tone.label == '' then add('%s: tone %d has no label', where, i) end
        end
    end
    checkTones(config.Tones, 'Config.Tones')
    if type(config.Patterns) ~= 'table' or #config.Patterns == 0 then add('Config.Patterns: needs at least one pattern') end
    for i, pattern in ipairs(config.Patterns or {}) do
        if type(pattern.step) ~= 'number' or pattern.step < 20 then add('Config.Patterns[%d]: step must be 20 ms or more', i) end
        if type(pattern.frames) ~= 'table' or #pattern.frames == 0 then add('Config.Patterns[%d]: needs at least one frame', i) end
    end
    for name, vehicle in pairs(config.Vehicles or {}) do
        local where = 'Config.Vehicles.' .. tostring(name)
        if name ~= name:lower() then add('%s: use the spawn name in lowercase', where) end
        if vehicle.lights ~= 'native' and vehicle.lights ~= 'extras' then add("%s: lights must be 'native' or 'extras'", where) end
        if vehicle.lights == 'extras' then
            if type(vehicle.extras) ~= 'table' or #vehicle.extras == 0 then add('%s: list the light bar extras, like extras = { 1, 2 }', where) end
            for _, extra in ipairs(vehicle.extras or {}) do
                if not isIndex(extra, 20) then add('%s: extra %s is not between 1 and 20', where, tostring(extra)) end
            end
        end
        if vehicle.tones ~= nil then checkTones(vehicle.tones, where .. '.tones') end
    end
    return problems
end

-- Allows at most maxCalls per key within windowSeconds. Returns allow(key, now) and forget(key).
function E.newRateLimiter(maxCalls, windowSeconds)
    local hits = {}
    local function allow(key, now)
        local fresh = {}
        for _, t in ipairs(hits[key] or {}) do
            if now - t < windowSeconds then fresh[#fresh + 1] = t end
        end
        if #fresh >= maxCalls then
            hits[key] = fresh
            return false
        end
        fresh[#fresh + 1] = now
        hits[key] = fresh
        return true
    end
    local function forget(key) hits[key] = nil end
    return allow, forget
end

return E
