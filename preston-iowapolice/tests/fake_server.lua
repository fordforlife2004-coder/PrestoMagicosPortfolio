-- A small fake FiveM server for the tests: only the natives these scripts use, kept in plain tables.
-- Load it with dofile before the resource's server scripts; it returns helpers for the tests.

local F = {
    players = {}, entities = {}, toClients = {}, handlers = {}, commands = {}, timeouts = {}, now = 1000000, failSpawn = false,
    hashAlias = {}, -- [name] = other name with the same hash, to test hash collisions
}
local nextEntity = 100

local Vector = {}
Vector.__index = Vector
Vector.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
Vector.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
Vector.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vector) end

local function newEntity(kind, fields)
    nextEntity = nextEntity + 1
    fields.type = kind
    fields.seats = fields.seats or {}
    F.entities[nextEntity] = fields
    return nextEntity
end

os.time = function() return F.now end
function GetHashKey(name) return 'hash:' .. (F.hashAlias[name] or name) end
function GetGameTimer() return F.now * 1000 end
function Wait() end
function CreateThread(fn) fn() end
function SetTimeout(_, fn) F.timeouts[#F.timeouts + 1] = fn end
function GetCurrentResourceName() return 'test-resource' end

function AddEventHandler(name, fn)
    F.handlers[name] = F.handlers[name] or {}
    table.insert(F.handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerClientEvent(name, target, ...) F.toClients[#F.toClients + 1] = { name = name, target = target, args = { ... } } end
function RegisterCommand(name, fn, restricted) F.commands[name] = { fn = fn, restricted = restricted } end

function GetPlayers()
    local out = {}
    for id in pairs(F.players) do out[#out + 1] = tostring(id) end
    table.sort(out)
    return out
end
local function playerOf(id) return F.players[tonumber(id)] end
function GetPlayerName(id) local p = playerOf(id) return p and p.name or nil end
function GetPlayerPed(id) local p = playerOf(id) return p and p.ped or 0 end
function IsPlayerAceAllowed(id, ace) -- ACEs are a tree: "vehiclespawn" also grants "vehiclespawn.use"
    local p = playerOf(id)
    if not p then return false end
    for granted in pairs(p.aces) do
        if ace == granted or ace:sub(1, #granted + 1) == granted .. '.' then return true end
    end
    return false
end

function DoesEntityExist(e) return F.entities[e] ~= nil end
function GetEntityType(e) return F.entities[e] and F.entities[e].type or 0 end
function GetEntityModel(e) return F.entities[e].model end
function GetEntityCoords(e) return F.entities[e] and F.entities[e].coords or vector3(0.0, 0.0, 0.0) end
function GetEntityHeading() return 90.0 end
function DeleteEntity(e)
    local entity = F.entities[e]
    if not entity then return end
    for _, ped in pairs(entity.seats) do
        if F.entities[ped] then F.entities[ped].vehicle = nil end
    end
    F.entities[e] = nil
end
function GetVehiclePedIsIn(ped) return F.entities[ped] and F.entities[ped].vehicle or 0 end
function GetPedInVehicleSeat(vehicle, seat) return F.entities[vehicle].seats[seat] or 0 end
function SetPedIntoVehicle(ped, vehicle, seat)
    F.entities[ped].vehicle = vehicle
    F.entities[vehicle].seats[seat] = ped
end
function CreateVehicleServerSetter(model, kind, x, y, z, heading)
    nextEntity = nextEntity + 1
    if F.failSpawn then return nextEntity end -- the game never creates it
    F.entities[nextEntity] = { type = 2, model = model, vehicleType = kind, coords = vector3(x, y, z), heading = heading, seats = {} }
    return nextEntity
end
function SetVehicleNumberPlateText(vehicle, text) F.entities[vehicle].plate = text end
function GetPlayerRoutingBucket(id) local p = playerOf(id) return p and p.bucket or 0 end
function SetEntityRoutingBucket(entity, bucket) F.entities[entity].bucket = bucket end
function NetworkGetEntityFromNetworkId(netId) return F.entities[netId] and netId or 0 end
function NetworkGetNetworkIdFromEntity(entity) return entity end

-- ---------------------------------------------------------------- helpers for the tests

function F.fire(name, ...)
    for _, fn in ipairs(F.handlers[name] or {}) do fn(...) end
    while #F.timeouts > 0 do table.remove(F.timeouts, 1)() end
end

-- A player's game sending a net event.
function F.send(src, name, ...)
    source = src
    F.fire(name, ...)
end

-- A player typing a server command.
function F.command(src, name, ...)
    local command = F.commands[name]
    if command.restricted and not IsPlayerAceAllowed(src, 'command.' .. name) then return end
    command.fn(src, { ... }, '/' .. name)
end

function F.addPlayer(id, name, opts)
    opts = opts or {}
    F.players[id] = { name = name, aces = opts.aces or {}, bucket = opts.bucket or 0, ped = newEntity(1, { coords = opts.coords or vector3(100.0 * id, 0.0, 30.0) }) }
    return F.players[id]
end

-- The player's game seating them in a vehicle (what the client does after the server spawns it).
function F.seat(id, vehicle, seat)
    SetPedIntoVehicle(F.players[id].ped, vehicle, seat or -1)
end

function F.leaveVehicle(id)
    local ped = F.players[id].ped
    local vehicle = F.entities[ped].vehicle
    if vehicle and F.entities[vehicle] then
        for seat, p in pairs(F.entities[vehicle].seats) do
            if p == ped then F.entities[vehicle].seats[seat] = nil end
        end
    end
    F.entities[ped].vehicle = nil
end

function F.addVehicle(model, coords, driverPed)
    local vehicle = newEntity(2, { model = GetHashKey(model), coords = coords or vector3(0.0, 0.0, 30.0) })
    if driverPed then SetPedIntoVehicle(driverPed, vehicle, -1) end
    return vehicle
end

function F.drop(id)
    source = id
    F.fire('playerDropped', 'Exiting')
    F.players[id] = nil
end

-- The last event sent to a player (optionally with a given name), as { name, target, args }.
function F.last(target, name)
    for i = #F.toClients, 1, -1 do
        local m = F.toClients[i]
        if m.target == target and (not name or m.name == name) then return m end
    end
end

-- A tiny test runner: test(name, fn), eq(actual, expected, label), contains(text, part), finish().
function F.runner()
    local passed, failed = 0, 0
    local t = {}
    function t.test(name, fn)
        local ok, err = pcall(fn)
        if ok then passed = passed + 1 else
            failed = failed + 1
            print(('FAIL %s: %s'):format(name, tostring(err)))
        end
    end
    function t.eq(actual, expected, label)
        if actual ~= expected then
            error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
        end
    end
    function t.contains(text, part, label)
        if type(text) ~= 'string' or not text:find(part, 1, true) then
            error(('%s: expected "%s" in "%s"'):format(label or 'text', part, tostring(text)), 2)
        end
    end
    function t.finish()
        print(('%d passed, %d failed'):format(passed, failed))
        if failed > 0 then error(('%d test(s) failed'):format(failed)) end
    end
    return t
end

return F
