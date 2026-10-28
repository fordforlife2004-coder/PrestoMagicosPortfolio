-- A small fake FiveM server for the tests: only the natives server/main.lua uses, kept in plain tables.
-- Load it with dofile before the resource's server scripts; it returns helpers for the tests.

local F = {
    players = {}, entities = {}, toClients = {}, handlers = {}, timers = {}, exports = {},
    now = 1000000,
}
local nextEntity = 100

local Vector = {}
Vector.__index = Vector
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vector) end

local function newEntity(fields)
    nextEntity = nextEntity + 1
    fields.seats = fields.seats or {}
    fields.bucket = fields.bucket or 0
    F.entities[nextEntity] = fields
    return nextEntity
end

os.time = function() return F.now end
function GetHashKey(name) return 'hash:' .. name end
function Wait() end
function CreateThread(fn) fn() end
-- Timers wait until the test calls F.flush(), so a test can move players while an animation plays.
function SetTimeout(ms, fn) F.timers[#F.timers + 1] = { at = F.now * 1000 + ms, fn = fn } end
function GetCurrentResourceName() return 'Prest_Sector-Cuffs' end
function exports(name, fn) F.exports[name] = fn end

function AddEventHandler(name, fn)
    F.handlers[name] = F.handlers[name] or {}
    table.insert(F.handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerClientEvent(name, target, ...) F.toClients[#F.toClients + 1] = { name = name, target = target, args = { ... } } end
function RegisterCommand(name, fn, restricted) end

function GetPlayers()
    local out = {}
    for id in pairs(F.players) do out[#out + 1] = tostring(id) end
    table.sort(out)
    return out
end
-- FiveM reads a player ID like C's atoi, so 3.5 or "3.9" still means player 3.
local function playerOf(id)
    local n = tonumber(id)
    return n and F.players[math.floor(n)] or nil
end
function GetPlayerName(id) local p = playerOf(id) return p and p.name or nil end
function GetPlayerPed(id) local p = playerOf(id) return p and p.ped or 0 end
function GetPlayerRoutingBucket(id) local p = playerOf(id) return p and p.bucket or 0 end
function IsPlayerAceAllowed(id, ace)
    local p = playerOf(id)
    return p ~= nil and p.aces[ace] == true
end

function DoesEntityExist(e) return F.entities[e] ~= nil end
function GetEntityType(e) return F.entities[e] and F.entities[e].type or 0 end
function GetEntityCoords(e) return F.entities[e] and F.entities[e].coords or vector3(0.0, 0.0, 0.0) end
function GetEntityHeading(e) return F.entities[e] and F.entities[e].heading or 0.0 end
function GetEntityRoutingBucket(e) return F.entities[e] and F.entities[e].bucket or 0 end
function GetVehiclePedIsIn(ped) return F.entities[ped] and F.entities[ped].vehicle or 0 end
function GetPedInVehicleSeat(vehicle, seat) return F.entities[vehicle].seats[seat] or 0 end
function NetworkGetEntityFromNetworkId(netId) return F.entities[netId] and netId or 0 end

function GetGameTimer() return F.now * 1000 end
function GetEntityAttachedTo(e) return F.entities[e] and F.entities[e].attachedTo or 0 end
function GetPlayerIdentifierByType(id, kind)
    local p = playerOf(id)
    return p and kind == 'license' and p.license or nil
end

-- ---------------------------------------------------------------- GlobalState

F.global = {} -- what the server has set, key = value
F.globalWrites = 0

GlobalState = setmetatable({
    set = function(_, key, value)
        F.globalWrites = F.globalWrites + 1
        F.global[key] = value
    end,
}, { __index = function(_, key) return F.global[key] end })

-- ---------------------------------------------------------------- helpers for the tests

local function fire(name, ...)
    for _, fn in ipairs(F.handlers[name] or {}) do fn(...) end
end

-- Runs every timer that is due within `seconds` (default: all of them), moving the clock along.
function F.flush(seconds)
    local untilMs = seconds and (F.now * 1000 + seconds * 1000) or math.huge
    while true do
        table.sort(F.timers, function(a, b) return a.at < b.at end)
        local timer = F.timers[1]
        if not timer or timer.at > untilMs then break end
        table.remove(F.timers, 1)
        if timer.at > F.now * 1000 then F.now = timer.at / 1000 end
        timer.fn()
    end
    if seconds then F.now = untilMs / 1000 end
end

-- A player's game sending a net event.
function F.send(src, name, ...)
    source = src
    fire(name, ...)
end

function F.start() fire('onResourceStart', 'Prest_Sector-Cuffs') end
function F.stop() fire('onResourceStop', 'Prest_Sector-Cuffs') end

function F.addPlayer(id, name, opts)
    opts = opts or {}
    F.players[id] = {
        name = name, aces = opts.aces or {}, bucket = opts.bucket or 0, license = opts.license or ('license:' .. name),
        ped = newEntity({ type = 1, coords = opts.coords or vector3(0.0, 0.0, 30.0) }),
    }
    return F.players[id]
end

-- A player connecting: FiveM fires playerJoining with their new server ID as the source.
function F.join(id, name, opts)
    local p = F.addPlayer(id, name, opts)
    source = id
    fire('playerJoining', 0)
    return p
end

function F.ped(id) return F.entities[F.players[id].ped] end

function F.moveTo(id, x, y, z) F.entities[F.players[id].ped].coords = vector3(x, y, z or 30.0) end
function F.turn(id, heading) F.entities[F.players[id].ped].heading = heading end

function F.addVehicle(coords, opts)
    opts = opts or {}
    return newEntity({ type = 2, coords = coords, bucket = opts.bucket })
end

function F.seat(id, vehicle, seat)
    local ped = F.players[id].ped
    F.entities[ped].vehicle = vehicle
    F.entities[vehicle].seats[seat] = ped
end

function F.leaveVehicle(id)
    local ped = F.players[id].ped
    local vehicle = F.entities[ped].vehicle
    if vehicle then
        for seat, p in pairs(F.entities[vehicle].seats) do
            if p == ped then F.entities[vehicle].seats[seat] = nil end
        end
    end
    F.entities[ped].vehicle = nil
end

function F.drop(id)
    source = id
    fire('playerDropped', 'Exiting')
    F.players[id] = nil
end

-- The last event sent to a player (optionally with a given name), as { name, target, args }.
function F.last(target, name)
    for i = #F.toClients, 1, -1 do
        local m = F.toClients[i]
        if m.target == target and (not name or m.name == name) then return m end
    end
end

F.runner = dofile('tests/runner.lua')

return F
