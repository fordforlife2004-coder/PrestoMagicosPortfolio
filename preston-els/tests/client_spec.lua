-- Runs client/sync.lua and client/main.lua in a small fake game, to check what a player's game does:
-- the keys, the sounds (started, swapped and always released), lights, extras flashing, and how it
-- handles the server's answers. Run from the resource folder with any Lua 5.3+:  lua tests/client_spec.lua

-- ---------------------------------------------------------------- fake game

local MY_ID, PED = 7, 1
local clockMs = 0
local threads, commands, netHandlers, eventHandlers, bagHandlers = {}, {}, {}, {}, {}
local vehicles, sounds = {}, {}
local toServer, nui, notifications = {}, {}, {}
local soundCount, clicks = 0, 0
local player = { vehicle = 0, coords = nil }

local Vector = {}
Vector.__index = Vector
Vector.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
Vector.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vector) end
player.coords = vector3(0, 0, 0)

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function GetGameTimer() return clockMs end
local function tick(times)
    for _ = 1, times or 1 do
        clockMs = clockMs + 50
        for _, co in ipairs(threads) do
            local ok, err = coroutine.resume(co)
            if not ok then error('thread crashed: ' .. tostring(err)) end
        end
    end
end

function RegisterCommand(name, fn) commands[name] = fn end
function RegisterKeyMapping() end
function RegisterNetEvent(name, fn) netHandlers[name] = fn end
function AddEventHandler(name, fn) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], fn) end
function TriggerEvent() end
function TriggerServerEvent(name, ...) toServer[#toServer + 1] = { name = name, args = { ... } } end
function SendNUIMessage(message) nui[#nui + 1] = message end
function GetCurrentResourceName() return 'preston-els' end
function GetResourceKvpInt() return 0 end
function SetResourceKvpInt() end
function GetControlInstructionalButton() return 't_X' end
function BeginTextCommandThefeedPost() end
function AddTextComponentSubstringPlayerName(text) notifications[#notifications + 1] = text end
function EndTextCommandThefeedPostTicker() end
function PlaySoundFrontend() clicks = clicks + 1 end
function DisableControlAction() end
function GetLabelText() return 'NULL' end
function GetDisplayNameFromVehicleModel() return 'POLICE3' end

function GetHashKey(name) -- any stable number works; the real game uses joaat
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 4294967296 end
    return h
end
function PlayerId() return 0 end
function PlayerPedId() return PED end
function GetPlayerServerId() return MY_ID end
function GetVehiclePedIsIn() return player.vehicle end

function DoesEntityExist(e) return e == PED or vehicles[e] ~= nil end
function GetEntityCoords(e) return e == PED and player.coords or vehicles[e].coords end
function GetEntityModel(v) return vehicles[v].model end
function GetVehicleClass(v) return vehicles[v].class end
function GetPedInVehicleSeat(v, seat) return vehicles[v].seats[seat] or 0 end
function GetGamePool() local out = {} for v in pairs(vehicles) do out[#out + 1] = v end table.sort(out) return out end
function NetworkGetEntityIsNetworked(v) return vehicles[v].networked end
function NetworkGetNetworkIdFromEntity(v) return v end
function NetworkGetEntityFromNetworkId(id) return vehicles[id] and id or 0 end
function SetVehicleSiren(v, on) vehicles[v].siren = on end
function IsVehicleSirenOn(v) return vehicles[v].siren end
function SetVehicleHasMutedSirens(v, muted) vehicles[v].muted = muted end
function SetVehicleAutoRepairDisabled(v, value) vehicles[v].noAutoRepair = value end
function DoesExtraExist(v, id) return vehicles[v].hasExtra[id] == true end
function SetVehicleExtra(v, id, disable) vehicles[v].extras[id] = not disable end

function GetSoundId() soundCount = soundCount + 1; sounds[soundCount] = { released = false } return soundCount end
function PlaySoundFromEntity(id, name, entity) sounds[id].name, sounds[id].entity, sounds[id].playing = name, entity, true end
function StopSound(id) sounds[id].playing = false end
function ReleaseSoundId(id) sounds[id].released = true end

function AddStateBagChangeHandler(key, _, fn) bagHandlers[#bagHandlers + 1] = { key = key, fn = fn } end
function GetEntityFromStateBagName(bag) local id = tonumber(bag:match('^entity:(%d+)$')) return vehicles[id] and id or 0 end
function Entity(v)
    return { state = setmetatable({}, { __index = function(_, key) return vehicles[v] and copy(vehicles[v].state[key]) end }) }
end
-- The server (or another player's approved change) updating a vehicle's state.
local function serverSets(v, value)
    for _, h in ipairs(bagHandlers) do h.fn('entity:' .. v, 'presEls', copy(value)) end
    vehicles[v].state.presEls = copy(value)
end

local function addVehicle(id, model, class, opts)
    opts = opts or {}
    vehicles[id] = {
        model = GetHashKey(model), class = class, coords = opts.coords or vector3(5, 0, 0), seats = {},
        networked = opts.networked ~= false, siren = false, muted = false, extras = {}, hasExtra = opts.hasExtra or {}, state = {},
    }
end
local function drive(v)
    player.vehicle = v
    if v ~= 0 then vehicles[v].seats[-1] = PED end
end

-- Sounds playing on a vehicle, and the number of sound IDs never given back.
local function playingOn(v)
    local names = {}
    for _, s in pairs(sounds) do if s.playing and s.entity == v then names[#names + 1] = s.name end end
    table.sort(names)
    return table.concat(names, ',')
end
local function leaked()
    local n = 0
    for _, s in pairs(sounds) do if not s.released and not s.playing then n = n + 1 end end
    return n
end
local function lastToServer() return toServer[#toServer] end
local function lastHud() for i = #nui, 1, -1 do if nui[i].type == 'hud' then return nui[i] end end end

-- ---------------------------------------------------------------- load the resource

dofile('config.lua')
Config.Vehicles.tahoe = { lights = 'extras', extras = { 1, 2 } }
dofile('shared/els.lua')
dofile('client/sync.lua')
dofile('client/main.lua')

local POLICE, TAHOE, ADDER, REMOTE, LOCAL_ONLY = 10, 11, 12, 13, 14
addVehicle(POLICE, 'police3', 18)
addVehicle(TAHOE, 'tahoe', 18, { hasExtra = { [1] = true, [2] = true } })
addVehicle(ADDER, 'adder', 7)
addVehicle(LOCAL_ONLY, 'police', 18, { networked = false })

-- ---------------------------------------------------------------- tests

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

test('keys do nothing outside an ELS vehicle', function()
    drive(ADDER)
    tick()
    commands.elslights()
    eq(#toServer, 0)
    eq(DrivingVehicle, 0)
    drive(0)
    tick()
end)

test('getting in shows the panel', function()
    drive(POLICE)
    tick()
    eq(DrivingVehicle, POLICE)
    eq(lastHud().visible, true)
    eq(lastHud().vehicle, 'POLICE3', 'falls back to the model name without a label')
    eq(lastHud().pattern, nil, 'built-in lights have no pattern to pick')
end)

test('lights: played right away and sent to the server', function()
    commands.elslights()
    local sent = lastToServer()
    eq(sent.name, 'preston-els:set')
    eq(sent.args[1], POLICE)
    eq(sent.args[2].lights, true)
    eq(sent.args[3], 1, 'request number')
    eq(vehicles[POLICE].siren, true, 'built-in lights on')
    eq(vehicles[POLICE].muted, true, "the game's own siren sound is muted")
    eq(playingOn(POLICE), '', 'no sound with only the lights')
    eq(lastHud().lights, true)
    eq(clicks, 1)
end)

test('siren and tones swap sounds cleanly', function()
    commands.elssiren()
    eq(playingOn(POLICE), 'VEHICLES_HORNS_SIREN_1')
    commands.elstone()
    eq(playingOn(POLICE), 'VEHICLES_HORNS_SIREN_2')
    eq(lastHud().tone, 'Yelp')
    eq(leaked(), 0)
end)

test('the air horn cuts through the siren while held', function()
    commands['+elshorn']()
    eq(playingOn(POLICE), 'SIRENS_AIRHORN')
    commands['-elshorn']()
    eq(playingOn(POLICE), 'VEHICLES_HORNS_SIREN_2')
    eq(leaked(), 0)
end)

test("the server's answer to an older key press doesn't undo a newer one", function()
    local newest = lastToServer().args[3]
    serverSets(POLICE, { lights = true, siren = true, tone = 1, seq = newest - 2, by = MY_ID })
    eq(playingOn(POLICE), 'VEHICLES_HORNS_SIREN_2', 'old echo ignored')
    serverSets(POLICE, { lights = true, siren = true, tone = 2, seq = newest, by = MY_ID })
    eq(playingOn(POLICE), 'VEHICLES_HORNS_SIREN_2')
end)

test('a refused request goes back to what the server approved', function()
    commands.elstone() -- tone 3, but the server says no
    eq(playingOn(POLICE), 'VEHICLES_HORNS_POLICE_WARNING')
    netHandlers['preston-els:refused'](POLICE, 'too many requests')
    eq(playingOn(POLICE), 'VEHICLES_HORNS_SIREN_2', 'back to the approved tone')
    eq(leaked(), 0)
end)

test('the pattern key explains itself on built-in lights', function()
    local before = #toServer
    commands.elspattern()
    eq(#toServer, before)
    eq(notifications[#notifications], 'This vehicle uses its own built-in light pattern.')
end)

test('getting out turns the siren off but leaves the lights on', function()
    drive(0)
    vehicles[POLICE].seats[-1] = nil
    tick()
    eq(DrivingVehicle, 0)
    local sent = lastToServer()
    eq(sent.args[2].siren, false)
    eq(sent.args[2].horn, false)
    eq(sent.args[2].lights, nil)
    eq(playingOn(POLICE), '')
    eq(vehicles[POLICE].siren, true)
    eq(lastHud().visible, false)
end)

test("other players' vehicles are played when near and let go when far", function()
    addVehicle(REMOTE, 'police2', 18, { coords = vector3(50, 0, 0) })
    vehicles[REMOTE].state.presEls = { lights = true, siren = true, tone = 3, seq = 4, by = 99 }
    tick()
    eq(playingOn(REMOTE), 'VEHICLES_HORNS_POLICE_WARNING')
    eq(vehicles[REMOTE].siren, true)
    vehicles[REMOTE].coords = vector3(Config.SyncDistance + 10, 0, 0)
    tick()
    eq(playingOn(REMOTE), '', 'out of range: sound stopped')
    eq(leaked(), 0)
    vehicles[REMOTE].coords = vector3(50, 0, 0)
    tick()
    eq(playingOn(REMOTE), 'VEHICLES_HORNS_POLICE_WARNING', 'back in range')
    serverSets(REMOTE, nil)
    eq(playingOn(REMOTE), '', 'state cleared')
end)

test('extras light bars flash with the pattern and switch off cleanly', function()
    drive(TAHOE)
    tick()
    eq(lastHud().pattern, 'Alternate')
    commands.elslights()
    eq(vehicles[TAHOE].siren, false, 'extras vehicles leave the built-in lights alone')
    eq(vehicles[TAHOE].noAutoRepair, true)
    local seen = {}
    for _ = 1, 20 do
        tick()
        seen[(vehicles[TAHOE].extras[1] and '1' or '-') .. (vehicles[TAHOE].extras[2] and '2' or '-')] = true
    end
    eq(seen['1-'], true, 'left on')
    eq(seen['-2'], true, 'right on')
    eq(seen['12'], nil, 'never both in Alternate')
    commands.elspattern()
    eq(lastHud().pattern, 'Fast strobe')
    commands.elslights()
    tick()
    eq(vehicles[TAHOE].extras[1], false)
    eq(vehicles[TAHOE].extras[2], false)
    drive(0)
    vehicles[TAHOE].seats[-1] = nil
    tick()
end)

test('a vehicle only this game knows about works without the server', function()
    drive(LOCAL_ONLY)
    tick()
    local before = #toServer
    commands.elssiren()
    eq(#toServer, before)
    eq(playingOn(LOCAL_ONLY), 'VEHICLES_HORNS_SIREN_1')
    drive(0)
    vehicles[LOCAL_ONLY].seats[-1] = nil
    tick()
    eq(playingOn(LOCAL_ONLY), '')
end)

test('stopping the resource stops every sound', function()
    tick()
    for _, fn in ipairs(eventHandlers.onResourceStop or {}) do fn('preston-els') end
    for _, s in pairs(sounds) do
        if s.playing then error('still playing: ' .. s.name) end
        if not s.released then error('never released: ' .. tostring(s.name)) end
    end
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d test(s) failed'):format(failed)) end
