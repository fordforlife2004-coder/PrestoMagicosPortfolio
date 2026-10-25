-- Runs server/main.lua against a small fake FiveM server, to check who may change a vehicle's ELS
-- and what gets shared. Run from the resource folder with any Lua 5.3+:  lua tests/server_spec.lua

local say = print
print = function() end -- keep the server's console lines out of the test output

-- ---------------------------------------------------------------- fake server

local handlers, bagHandlers, timeouts, toClients = {}, {}, {}, {}
local entities, players = {}, {}
local clockMs = 0

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

function GetHashKey(name) return 'hash:' .. name end
function GetGameTimer() return clockMs end
function SetTimeout(_, fn) timeouts[#timeouts + 1] = fn end
function GetCurrentResourceName() return 'preston-els' end
function AddEventHandler(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerClientEvent(name, target, ...) toClients[#toClients + 1] = { name = name, target = target, args = { ... } } end
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
local function runTimeouts() while #timeouts > 0 do table.remove(timeouts, 1)() end end

function GetPlayerPed(id) return players[id] and players[id].ped or 0 end
function IsPlayerAceAllowed(id, ace) return players[id] ~= nil and players[id].aces[ace] == true end

function NetworkGetEntityFromNetworkId(netId) return entities[netId] and netId or 0 end
function NetworkGetNetworkIdFromEntity(entity) return entity end
function DoesEntityExist(entity) return entities[entity] ~= nil end
function GetEntityType(entity) return entities[entity] and entities[entity].type or 0 end
function GetEntityModel(entity) return entities[entity].model end
function GetPedInVehicleSeat(vehicle, seat) return entities[vehicle].seats[seat] or 0 end

function AddStateBagChangeHandler(key, _, fn) bagHandlers[#bagHandlers + 1] = { key = key, fn = fn } end
function GetEntityFromStateBagName(bag) return tonumber(bag:match('^entity:(%d+)$')) or 0 end
local function setState(entity, key, value)
    for _, h in ipairs(bagHandlers) do
        if h.key == nil or h.key == key then h.fn('entity:' .. entity, key, copy(value)) end
    end
    if entities[entity] then entities[entity].state[key] = copy(value) end
end
function Entity(entity)
    return { state = setmetatable({
        set = function(_, key, value) setState(entity, key, value) end,
    }, { __index = function(_, key) return entities[entity] and copy(entities[entity].state[key]) end }) }
end

local function addPlayer(id, aces) players[id] = { ped = 1000 + id, aces = aces or {} } end
local function addVehicle(netId, model, driver)
    entities[netId] = { type = 2, model = GetHashKey(model), seats = { [-1] = driver and GetPlayerPed(driver) or nil }, state = {} }
end

-- Sends a key press like a driver's game does. Returns the refusal reason, or nil if accepted.
local seq = 0
local function press(src, netId, change)
    clockMs = clockMs + 200
    seq = seq + 1
    local before = #toClients
    source = src
    fire('preston-els:set', netId, change, seq)
    runTimeouts()
    for i = #toClients, before + 1, -1 do
        if toClients[i].name == 'preston-els:refused' and toClients[i].target == src then return toClients[i].args[2] end
    end
    return nil
end
local function els(netId) return entities[netId].state.presEls end

-- ---------------------------------------------------------------- load the resource

dofile('config.lua')
dofile('shared/els.lua')
dofile('server/main.lua')
fire('onResourceStart', 'preston-els')

local DRIVER, PASSENGER, OTHER = 1, 2, 3
addPlayer(DRIVER)
addPlayer(PASSENGER)
addPlayer(OTHER)
addVehicle(50, 'police3', DRIVER)
addVehicle(60, 'adder', OTHER)

-- ---------------------------------------------------------------- tests

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        say(('FAIL %s: %s'):format(name, tostring(err)))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
    end
end

test('the driver can turn the lights on, and the state records who asked', function()
    eq(press(DRIVER, 50, { lights = true }), nil)
    eq(els(50).lights, true)
    eq(els(50).by, DRIVER)
    eq(els(50).seq, seq)
end)

test('passengers and other players are refused', function()
    eq(press(PASSENGER, 50, { siren = true }), 'not the driver')
    eq(press(OTHER, 50, { lights = false }), 'not the driver', 'not even switching off: they never drove it')
    eq(els(50).siren, false)
end)

test('siren tones are checked against the vehicle', function()
    eq(press(DRIVER, 50, { siren = true, tone = 3 }), nil)
    eq(els(50).tone, 3)
    eq(press(DRIVER, 50, { tone = 4 }), 'unknown siren tone')
    eq(els(50).tone, 3, 'unchanged')
end)

test('bad requests are refused', function()
    eq(press(DRIVER, 50, { lights = 'on' }), 'lights must be true or false')
    eq(press(DRIVER, 50, { teleport = true }), 'unknown setting "teleport"')
    eq(press(DRIVER, 999, { lights = true }), 'that vehicle no longer exists')
    source = DRIVER
    local before = #toClients
    fire('preston-els:set', 'fifty', { lights = true }, 1)
    eq(toClients[#toClients].args[2], 'bad request')
    eq(#toClients, before + 1)
end)

test('after getting out, the last driver may only switch things off', function()
    entities[50].seats[-1] = nil
    eq(press(DRIVER, 50, { tone = 1 }), 'not the driver')
    eq(press(DRIVER, 50, { siren = false, horn = false }), nil)
    eq(els(50).siren, false)
    eq(els(50).lights, true, 'lights stay on, like a parked patrol car')
    entities[50].seats[-1] = GetPlayerPed(DRIVER)
end)

test("a cheat writing a vehicle's ELS state directly is put back", function()
    local before = els(50)
    setState(50, 'presEls', { lights = true, siren = true, horn = true, tone = 1, pattern = 1, seq = 999, by = OTHER })
    runTimeouts()
    eq(els(50).horn, false)
    eq(els(50).seq, before.seq)
    setState(60, 'presEls', { lights = true })
    runTimeouts()
    eq(els(60), nil, 'a vehicle the server never approved is cleared')
end)

test('requests are rate limited', function()
    clockMs = clockMs + 2000 -- start with a clean second
    local refused = 0
    for _ = 1, 20 do
        source = DRIVER
        local before = #toClients
        fire('preston-els:set', 50, { horn = true }, 1)
        if #toClients > before and toClients[#toClients].args[2] == 'too many requests' then refused = refused + 1 end
    end
    eq(refused, 8, '12 a second allowed')
    clockMs = clockMs + 2000
end)

test('an ACE permission can limit who uses ELS', function()
    Config.AcePermission = 'els.use'
    eq(press(DRIVER, 50, { horn = false }), 'no permission')
    players[DRIVER].aces['els.use'] = true
    eq(press(DRIVER, 50, { horn = false }), nil)
    Config.AcePermission = ''
end)

test('with AllEmergencyVehicles off, only listed vehicles are accepted', function()
    Config.AllEmergencyVehicles = false
    entities[60].seats[-1] = GetPlayerPed(OTHER)
    eq(press(OTHER, 60, { lights = true }), 'not an ELS vehicle')
    eq(press(DRIVER, 50, { lights = true }), nil, 'police3 is listed')
    Config.AllEmergencyVehicles = true
end)

test('removed vehicles and players who leave are forgotten', function()
    fire('entityRemoved', 50)
    entities[50] = nil
    addVehicle(50, 'police3', nil) -- the net id is reused for a new vehicle
    eq(press(DRIVER, 50, { siren = false }), 'not the driver', 'not the last driver of the new vehicle')
    source = OTHER
    fire('playerDropped', 'Exiting')
end)

say(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d test(s) failed'):format(failed)) end
