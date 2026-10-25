-- Tests for shared/skins.lua. Run from the resource folder with any Lua 5.3+:  lua tests/skins_spec.lua

dofile('config.lua')
dofile('shared/vehicle_types.lua')
local S = dofile('shared/skins.lua')
local t = dofile('tests/fake_server.lua').runner()

t.test('parseNumber takes whole numbers in range only', function()
    t.eq(S.parseNumber('2', 1, 10), 2)
    t.eq(S.parseNumber(3, 1, 10), 3)
    t.eq(S.parseNumber('0', 1, 10), nil)
    t.eq(S.parseNumber('11', 1, 10), nil)
    t.eq(S.parseNumber('1.5', 1, 10), nil)
    t.eq(S.parseNumber('abc', 1, 10), nil)
    t.eq(S.parseNumber(nil, 1, 10), nil)
end)

t.test('formatPlate', function()
    t.eq(S.formatPlate('isp 101'), 'ISP 101')
    t.eq(S.formatPlate('<b>hi</b>'), 'BHIB')
    t.eq(S.formatPlate('   '), '')
    t.eq(S.formatPlate('123456789'), '12345678')
end)

t.test('liveryKind: classic liveries first, then mod-kit liveries, else none', function()
    local classic = S.liveryKind(4, 0)
    t.eq(classic.kind, 'classic')
    t.eq(classic.count, 4)
    local mod = S.liveryKind(-1, 6) -- -1 is what the game returns when there are no classic liveries
    t.eq(mod.kind, 'mod')
    t.eq(mod.count, 6)
    t.eq(S.liveryKind(-1, 0), nil)
    t.eq(S.liveryKind(0, 0), nil)
end)

t.test('randomLivery never picks the current one when there is a choice', function()
    t.eq(S.randomLivery(0, nil, math.random), nil)
    t.eq(S.randomLivery(1, 1, math.random), 1)
    for current = 1, 4 do
        for roll = 1, 3 do
            local pick = S.randomLivery(4, current, function() return roll end)
            t.eq(pick ~= current, true, ('current %d, roll %d'):format(current, roll))
            t.eq(pick >= 1 and pick <= 4, true)
        end
    end
    t.eq(S.randomLivery(3, nil, function() return 2 end), 2, 'no current livery')
    t.eq(S.randomLivery(4, nil, function(_, b) return b end), 4, 'with no current livery, the last one can be picked too')
end)

t.test('isBlocked compares hashes, so another name for the same model is caught', function()
    local hash = function(name) return name == 'zz_tank' and 'hash:rhino' or 'hash:' .. name end
    t.eq(S.isBlocked(Config, 'rhino', hash), true)
    t.eq(S.isBlocked(Config, 'zz_tank', hash), true)
    t.eq(S.isBlocked(Config, 'police3', hash), false)
end)

t.test('typeFor knows built-in vehicles that are not cars, and add-ons from the config', function()
    t.eq(S.typeFor(Config, 'police3'), 'automobile')
    t.eq(S.typeFor(Config, 'polmav'), 'heli')
    t.eq(S.typeFor(Config, 'policeb'), 'bike')
    t.eq(S.typeFor({ VehicleTypes = { mybike = 'bike' } }, 'mybike'), 'bike')
    t.eq(S.isTrain('metrotrain'), true)
end)

t.test('cooldownLeft', function()
    t.eq(S.cooldownLeft(nil, 50, 10), 0)
    t.eq(S.cooldownLeft(50, 52, 10), 8)
    t.eq(S.cooldownLeft(50, 61, 10), 0)
end)

t.test('every permission in the config is a string', function()
    for name, ace in pairs(Config.Permissions) do t.eq(type(ace), 'string', name) end
end)

t.finish()
