-- Tests for shared/els.lua and config.lua. Run from the resource folder with any Lua 5.3+:
--   lua tests/els_spec.lua

dofile('config.lua')
local E = dofile('shared/els.lua')

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print(('FAIL %s: %s'):format(name, tostring(err)))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
    end
end

local police = E.settingsFor(Config, nil)
local fire = E.settingsFor(Config, 'firetruk')
local extrasCar = E.settingsFor({ Tones = Config.Tones, Vehicles = { tahoe = { lights = 'extras', extras = { 3, 4 } } } }, 'tahoe')
local PATTERNS = #Config.Patterns

test('the shipped config has no problems', function()
    local problems = E.checkConfig(Config)
    eq(#problems, 0, table.concat(problems, '; '))
end)

test('checkConfig explains mistakes', function()
    local problems = E.checkConfig({
        Tones = { { label = 'Wail' } },
        Patterns = { { step = 5, frames = {} } },
        Vehicles = { Police3 = { lights = 'strobe' }, tahoe = { lights = 'extras', extras = { 0, 25 } } },
    })
    local text = table.concat(problems, '\n')
    for _, expected in ipairs({ 'tone 1 has no sound', 'step must be 20', 'needs at least one frame', 'lowercase', "'native' or 'extras'", 'extra 0', 'extra 25' }) do
        if not text:find(expected, 1, true) then error('missing problem: ' .. expected .. '\n' .. text) end
    end
end)

test('settings: unlisted vehicles use built-in lights and the default tones', function()
    eq(police.listed, false)
    eq(police.lights, 'native')
    eq(police.nativeLights, true)
    eq(police.tones, Config.Tones)
    eq(fire.listed, true)
    eq(fire.tones[1].label, 'Fire horn')
    eq(extrasCar.lights, 'extras')
    eq(extrasCar.nativeLights, false)
    eq(extrasCar.extras[2], 4)
end)

test('normalize fills in and cleans up', function()
    local s = E.normalize({ lights = 'yes', tone = 2.5, pattern = -1, seq = 9 })
    eq(s.lights, false, 'only true counts')
    eq(s.tone, 1)
    eq(s.pattern, 1)
    eq(s.seq, 9)
    eq(E.normalize(nil).siren, false)
end)

test('lights and siren rules', function()
    local s = E.applyChange(nil, { lights = true }, police, PATTERNS)
    eq(s.lights, true)
    eq(s.siren, false)
    s = E.applyChange(nil, { siren = true }, police, PATTERNS)
    eq(s.lights, true, 'siren on also turns the lights on')
    eq(s.siren, true)
    s = E.applyChange(s, { lights = false }, police, PATTERNS)
    eq(s.lights, false)
    eq(s.siren, false, 'lights off also stops the siren')
end)

test('tones and patterns must exist for that vehicle', function()
    eq(E.applyChange(nil, { tone = 3 }, police, PATTERNS).tone, 3)
    eq(select(2, E.applyChange(nil, { tone = 4 }, police, PATTERNS)), 'unknown siren tone')
    eq(select(2, E.applyChange(nil, { tone = 1.5 }, police, PATTERNS)), 'unknown siren tone')
    eq(select(2, E.applyChange(nil, { pattern = PATTERNS + 1 }, police, PATTERNS)), 'unknown light pattern')
    eq(E.applyChange(nil, { pattern = PATTERNS }, police, PATTERNS).pattern, PATTERNS)
end)

test('bad requests are refused', function()
    eq(E.applyChange(nil, {}, police, PATTERNS), nil, 'empty')
    eq(E.applyChange(nil, 'lights', police, PATTERNS), nil, 'not a table')
    eq(select(2, E.applyChange(nil, { lights = 1 }, police, PATTERNS)), 'lights must be true or false')
    eq(select(2, E.applyChange(nil, { boost = true }, police, PATTERNS)), 'unknown setting "boost"')
end)

test('a tone from another vehicle is reset when it does not fit', function()
    local s = E.applyChange({ tone = 3 }, { lights = true }, E.settingsFor(Config, 'ambulance'), PATTERNS)
    eq(s.tone, 1)
end)

test('onlyTurnsOff', function()
    eq(E.onlyTurnsOff({ siren = false, horn = false }), true)
    eq(E.onlyTurnsOff({ siren = true }), false)
    eq(E.onlyTurnsOff({ tone = 2 }), false)
    eq(E.onlyTurnsOff({}), false)
    eq(E.onlyTurnsOff(nil), false)
end)

test('patternFrame walks through the frames by time', function()
    local pattern = { step = 100, frames = { { 1 }, {}, { 2 } } }
    eq(E.patternFrame(pattern, 0), 1)
    eq(E.patternFrame(pattern, 99), 1)
    eq(E.patternFrame(pattern, 100), 2)
    eq(E.patternFrame(pattern, 250), 3)
    eq(E.patternFrame(pattern, 300), 1, 'loops')
    eq(E.patternFrame(pattern, -50), 1, 'clock went backwards')
    eq(E.patternFrame({ step = 1, frames = { {}, {} } }, 19), 1, 'steps under 20 ms are slowed to 20')
    eq(E.patternFrame({ frames = {} }, 500), 1)
end)

test('extrasForFrame maps light slots to the vehicle extras', function()
    local on = E.extrasForFrame({ 1, 2, 3 }, { 7, 9 })
    eq(on[7], true)
    eq(on[9], true)
    eq(on[3], nil, 'slot 3 does not exist on this vehicle')
end)

test('toneSound: none with the siren off or the horn held', function()
    eq(E.toneSound(E.normalize({ siren = true, tone = 2 }), police), 'VEHICLES_HORNS_SIREN_2')
    eq(E.toneSound(E.normalize({ siren = false }), police), nil)
    eq(E.toneSound(E.normalize({ siren = true, horn = true }), police), nil)
    eq(E.toneSound(E.normalize({ siren = true, tone = 9 }), police), 'VEHICLES_HORNS_SIREN_1', 'falls back to the first tone')
end)

test('same compares every field', function()
    eq(E.same({ lights = true, seq = 1 }, { lights = true, seq = 1 }), true)
    eq(E.same({ lights = true, seq = 1 }, { lights = true, seq = 2 }), false)
    eq(E.same(nil, {}), true)
end)

test('rate limiter', function()
    local allow = E.newRateLimiter(2, 1)
    eq(allow('a', 0), true)
    eq(allow('a', 0.5), true)
    eq(allow('a', 0.6), false)
    eq(allow('a', 1.1), true)
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d test(s) failed'):format(failed)) end
