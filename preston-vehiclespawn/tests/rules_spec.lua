-- Tests for shared/rules.lua and shared/vehicle_types.lua. Run from the resource folder with any Lua 5.3+:
--   lua tests/rules_spec.lua

dofile('config.lua')
dofile('shared/vehicle_types.lua')
local R = dofile('shared/rules.lua')
local t = dofile('tests/fake_server.lua').runner()
local hash = function(name) return 'hash:' .. name end

t.test('normalizeModel', function()
    t.eq(R.normalizeModel('  Adder '), 'adder')
    t.eq(R.normalizeModel('Police 3'), 'police3')
    t.eq(R.normalizeModel(nil), '')
    t.eq(R.normalizeModel(42), '')
end)

t.test('validModelName', function()
    t.eq(R.validModelName('adder'), true)
    t.eq(R.validModelName('police3'), true)
    t.eq(R.validModelName('a'), false)
    t.eq(R.validModelName('x;drop'), false)
    t.eq(R.validModelName(('a'):rep(33)), false)
end)

t.test('isBlocked compares hashes, so another name for the same model is caught', function()
    t.eq(R.isBlocked(Config, 'rhino', hash), true)
    t.eq(R.isBlocked({ BlockedModels = { 'Hydra' } }, 'hydra', hash), true)
    t.eq(R.isBlocked(Config, 'adder', hash), false)
    local sameHash = function(name) return name == 'zz_secret_tank' and 'hash:rhino' or 'hash:' .. name end
    t.eq(R.isBlocked(Config, 'zz_secret_tank', sameHash), true)
end)

t.test('typeFor knows the built-in vehicles that are not cars', function()
    t.eq(R.typeFor(Config, 'adder'), 'automobile')
    t.eq(R.typeFor(Config, 'buzzard2'), 'heli')
    t.eq(R.typeFor(Config, 'luxor'), 'plane')
    t.eq(R.typeFor(Config, 'seashark'), 'boat')
    t.eq(R.typeFor(Config, 'kosatka'), 'submarine')
    t.eq(R.typeFor(Config, 'sanchez'), 'bike')
    t.eq(R.typeFor(Config, 'bmx'), 'bike')
    t.eq(R.typeFor(Config, 'policeb'), 'bike')
    t.eq(R.typeFor(Config, 'trailersmall2'), 'trailer')
    t.eq(R.typeFor({ VehicleTypes = { myheli = 'heli' } }, 'myheli'), 'heli', 'add-ons from the config')
    t.eq(R.isTrain('freight'), true)
    t.eq(R.isTrain('adder'), false)
    t.eq(R.typeFor(Config, 'freight'), 'train')
end)

t.test('typeFor goes by model hash, so another name for a helicopter is still a helicopter', function()
    local sameHash = function(name) return name == 'zz_heli' and 'h:buzzard2' or 'h:' .. name end
    t.eq(R.typeFor(Config, 'zz_heli', sameHash), 'heli')
    t.eq(R.typeFor(Config, 'adder', sameHash), 'automobile')
end)

t.test('the type list only uses types the server can spawn', function()
    for model, kind in pairs(KnownVehicleTypes) do t.eq(R.VEHICLE_TYPES[kind], true, model) end
end)

t.test('cooldownLeft', function()
    t.eq(R.cooldownLeft(nil, 100, 10), 0)
    t.eq(R.cooldownLeft(100, 100, 10), 10)
    t.eq(R.cooldownLeft(100, 105.5, 10), 5)
    t.eq(R.cooldownLeft(100, 110, 10), 0)
end)

t.test('formatPlate keeps what the game accepts', function()
    t.eq(R.formatPlate('preston'), 'PRESTON')
    t.eq(R.formatPlate(' isp-101! '), 'ISP101')
    t.eq(R.formatPlate('ABCDEFGHIJ'), 'ABCDEFGH')
    t.eq(R.formatPlate(''), '')
    t.eq(R.formatPlate(nil), '')
end)

t.test('every blocked model is a valid model name', function()
    for _, model in ipairs(Config.BlockedModels) do t.eq(R.validModelName(model:lower()), true, model) end
end)

t.finish()
