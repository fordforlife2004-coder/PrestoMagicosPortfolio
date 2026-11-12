-- A small fake of one player's game for the radar's client tests: the natives client/main.lua uses, kept
-- in plain tables, with threads that wait and timers that run as the test moves the clock.

dofile('tests/json.lua')

local G = {}

local function reset()
    G.now = 1000
    G.threads, G.timers = {}, {}
    G.handlers, G.nuiCallbacks, G.commands, G.keys, G.exports = {}, {}, {}, {}, {}
    G.nui, G.toServer, G.feed, G.kvp, G.suggestions = {}, {}, {}, {}, {}
    G.focus = false
    G.entities, G.nextEntity = {}, 1000
    G.ped = 1
    G.entities[G.ped] = { kind = 'ped', coords = { x = 0.0, y = 0.0, z = 30.0 }, vehicle = 0 }
    G.state = {}
    G.resources = { ['Prest_Sector-Radar'] = 'started' }
    G.blocked = {}         -- [entity] = true: the patrol car can't see it (no line of sight)
    G.cadOpened = {}
end
reset()

-- ------------------------------------------------------------------ threads and time

local function runThread(t)
    local ok, wait = coroutine.resume(t.co)
    if not ok then error(wait, 0) end
    if coroutine.status(t.co) == 'dead' then t.done = true else t.wakeAt = G.now + (wait or 0) end
end

function CreateThread(fn)
    local t = { co = coroutine.create(fn), wakeAt = G.now }
    G.threads[#G.threads + 1] = t
    runThread(t)
end

function Wait(ms)
    if coroutine.isyieldable() then coroutine.yield(ms or 0) end
end

function SetTimeout(ms, fn) G.timers[#G.timers + 1] = { at = G.now + ms, fn = fn } end
function GetGameTimer() return G.now end

-- Moves the game clock forward, running timers and waking threads as their time comes.
function G.tick(ms)
    local target = G.now + (ms or 0)
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 100000 then error('the game never settles') end
        local nextAt, nextKind, nextItem = math.huge, nil, nil
        for _, t in ipairs(G.timers) do
            if t.at < nextAt then nextAt, nextKind, nextItem = t.at, 'timer', t end
        end
        for _, t in ipairs(G.threads) do
            if not t.done and t.wakeAt < nextAt then nextAt, nextKind, nextItem = t.wakeAt, 'thread', t end
        end
        if not nextItem or nextAt > target then break end
        G.now = math.max(G.now, nextAt)
        if nextKind == 'timer' then
            for i, t in ipairs(G.timers) do
                if t == nextItem then table.remove(G.timers, i) break end
            end
            nextItem.fn()
        else
            runThread(nextItem)
        end
    end
    G.now = target
end

-- ------------------------------------------------------------------ events, commands, NUI, storage

function GetCurrentResourceName() return 'Prest_Sector-Radar' end
function GetResourceState(name) return G.resources[name] or 'missing' end
function AddEventHandler(name, fn)
    G.handlers[name] = G.handlers[name] or {}
    table.insert(G.handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
    if name == 'chat:addSuggestion' then G.suggestions[#G.suggestions + 1] = (...) end
    for _, fn in ipairs(G.handlers[name] or {}) do fn(...) end
end
function TriggerServerEvent(name, ...) G.toServer[#G.toServer + 1] = { name = name, args = { ... } } end
function RegisterCommand(name, fn) G.commands[name] = fn end
function RegisterKeyMapping(command, description, mapper, key) G.keys[command] = { description = description, key = key } end
function RegisterNUICallback(name, fn) G.nuiCallbacks[name] = fn end
function SendNUIMessage(message) G.nui[#G.nui + 1] = message end
function SetNuiFocus(keyboard, mouse) G.focus = keyboard and mouse end
function SetResourceKvp(key, value) G.kvp[key] = value end
function GetResourceKvpString(key) return G.kvp[key] end

-- exports('Name', fn) registers the radar's export; exports['Prest_Sector-CAD']:OpenPlate(...) is the CAD's.
local cadClient = {
    OpenPlate = function(_, plate)
        G.cadOpened[#G.cadOpened + 1] = plate
        return true
    end,
}
exports = setmetatable({}, {
    __call = function(_, name, fn) G.exports[name] = fn end,
    __index = function(_, resource) return resource == 'Prest_Sector-CAD' and cadClient or nil end,
})

LocalPlayer = { state = setmetatable({}, { __index = function(_, k) return G.state[k] end }) }

local text = {}
function BeginTextCommandThefeedPost() text = {} end
function AddTextComponentSubstringPlayerName(piece) text[#text + 1] = piece end
function EndTextCommandThefeedPostTicker(important)
    for _, piece in ipairs(text) do
        if #piece > 99 then error('a piece of notification text over 99 characters') end
    end
    G.feed[#G.feed + 1] = { text = table.concat(text), pieces = #text, important = important }
end

-- ------------------------------------------------------------------ the player and the cars

function GetHashKey(name) return 'hash:' .. name end
function PlayerPedId() return G.ped end
function GetVehiclePedIsIn(ped) return G.entities[ped].vehicle or 0 end
function GetPedInVehicleSeat(vehicle, seat)
    local v = G.entities[vehicle]
    return v and v.seats and v.seats[seat] or 0
end
function GetVehicleClass(v) return G.entities[v] and G.entities[v].class or 0 end
function GetEntityModel(v) return G.entities[v] and G.entities[v].model or 0 end
function GetEntityCoords(e) return G.entities[e] and G.entities[e].coords or { x = 0.0, y = 0.0, z = 0.0 } end
function GetEntityForwardVector(e) return G.entities[e] and G.entities[e].forward or { x = 0.0, y = 1.0, z = 0.0 } end
function GetEntityVelocity(e) return G.entities[e] and G.entities[e].velocity or { x = 0.0, y = 0.0, z = 0.0 } end
function GetEntitySpeed(e)
    local v = GetEntityVelocity(e)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end
function GetVehicleNumberPlateText(v) return G.entities[v] and G.entities[v].plate or nil end
function GetVehicleNumberPlateTextIndex(v) return G.entities[v] and G.entities[v].plateStyle or 0 end
function HasEntityClearLosToEntity(_, target) return not G.blocked[target] end
function GetGamePool(kind)
    local out = {}
    if kind == 'CVehicle' then
        for id, e in pairs(G.entities) do
            if e.kind == 'vehicle' then out[#out + 1] = id end
        end
        table.sort(out)
    end
    return out
end

-- A car on the road: at (x, y), moving north at speed (m/s, negative: south). Everything faces north.
function G.addCar(plate, x, y, speed, opts)
    opts = opts or {}
    G.nextEntity = G.nextEntity + 1
    G.entities[G.nextEntity] = {
        kind = 'vehicle', plate = plate, plateStyle = opts.plateStyle or 0, class = opts.class or 1, model = opts.model or 'hash:sultan',
        coords = { x = x, y = y, z = 30.0 }, forward = { x = 0.0, y = 1.0, z = 0.0 },
        velocity = { x = 0.0, y = speed or 0.0, z = 0.0 }, seats = {},
    }
    return G.nextEntity
end

-- The player in a police car (class 18) at the origin, going north at speed m/s.
function G.patrol(speed, opts)
    opts = opts or {}
    local car = G.addCar('LSPD01', 0.0, 0.0, speed or 0.0, { class = opts.class or 18, model = opts.model })
    G.entities[car].seats[opts.seat or -1] = G.ped
    G.entities[G.ped].vehicle = car
    return car
end

function G.leave()
    local car = G.entities[G.ped].vehicle
    if car ~= 0 then G.entities[car].seats = {} end
    G.entities[G.ped].vehicle = 0
end

function G.setSpeed(car, speed) G.entities[car].velocity = { x = 0.0, y = speed, z = 0.0 } end
function G.move(car, x, y) G.entities[car].coords = { x = x, y = y, z = 30.0 } end

-- ------------------------------------------------------------------ helpers for the tests

-- The last NUI message of a type.
function G.last(kind)
    for i = #G.nui, 1, -1 do
        if G.nui[i].type == kind then return G.nui[i] end
    end
    return nil
end

function G.count(list, test)
    local n = 0
    for _, item in ipairs(list) do
        if test(item) then n = n + 1 end
    end
    return n
end

function G.beeps(kind) return G.count(G.nui, function(m) return m.type == 'beep' and m.kind == kind end) end

-- Plate checks sent to the server since the start.
function G.checks()
    local out = {}
    for _, m in ipairs(G.toServer) do
        if m.name == 'Prest_Sector-Radar:check' then out[#out + 1] = { id = m.args[1], camera = m.args[2], plate = m.args[3] } end
    end
    return out
end

-- The server answering a plate check.
function G.answer(check, result) TriggerEvent('Prest_Sector-Radar:result', check.id, result) end

function G.callNui(name, data)
    local answer
    G.nuiCallbacks[name](data, function(result) answer = result end)
    return answer
end

function G.command(name) G.commands[name](0, {}, '') end

-- Starts the radar in this game. configure(Config) can change settings first. The saved settings
-- (G.kvp) stay unless keep is false.
function G.load(configure, opts)
    local kvp = G.kvp
    reset()
    if opts and opts.keepKvp then G.kvp = kvp end
    G.state.prestSectorRadar = not (opts and opts.denied)
    Config, Radar = nil, nil
    dofile('config.lua')
    if configure then configure(Config) end
    dofile('shared/radar.lua')
    dofile('client/main.lua')
end

G.runner = dofile('tests/runner.lua')

return G
