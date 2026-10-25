-- Runs server/main.lua against tests/fake_server.lua, to check who may spawn and delete what.
-- Run from the resource folder with any Lua 5.3+:  lua tests/server_spec.lua

local F = dofile('tests/fake_server.lua')
dofile('config.lua')
dofile('shared/vehicle_types.lua')
dofile('shared/rules.lua')
dofile('server/main.lua')
local t = F.runner()

local PLAYER, OTHER, ADMIN = 1, 2, 3
F.addPlayer(PLAYER, 'Player')
F.addPlayer(OTHER, 'Other', { bucket = 4 })
F.addPlayer(ADMIN, 'Admin', { aces = { ['vehiclespawn.staff'] = true } })

-- Asks for a car. Returns the new vehicle (after the player's game seats them), or nil and the message.
local function spawn(src, model, kind)
    local before = #F.toClients
    F.send(src, 'preston-vehiclespawn:spawn', model, kind or 'automobile')
    local reply = F.toClients[#F.toClients]
    if #F.toClients == before then return nil, 'no answer' end
    if reply.name == 'preston-vehiclespawn:seat' then
        local vehicle = NetworkGetEntityFromNetworkId(reply.args[1])
        F.seat(src, vehicle)
        return vehicle, reply.args[2]
    end
    return nil, reply.args[1]
end
local function delete(src, netId)
    F.send(src, 'preston-vehiclespawn:delete', netId)
    return F.last(src, 'preston-vehiclespawn:notify').args[1]
end
local function vehicleOf(src) return GetVehiclePedIsIn(GetPlayerPed(src)) end
local function later(seconds) F.now = F.now + (seconds or 20) end

t.test('a player spawns a car; their game is told which one to get in', function()
    local car, model = spawn(PLAYER, 'Adder')
    t.eq(model, 'adder')
    t.eq(F.entities[car].model, 'hash:adder')
    t.eq(F.entities[car].plate, 'PRESTON')
    t.eq(F.entities[car].bucket, 0)
end)

t.test('there is a cooldown between spawns', function()
    later(3)
    t.eq(select(2, spawn(PLAYER, 'sultan')), 'Wait 7s before spawning another vehicle.')
end)

t.test('spawning again replaces the last spawned car', function()
    local first = vehicleOf(PLAYER)
    later(10)
    local second = spawn(PLAYER, 'sultan')
    t.eq(DoesEntityExist(first), false, 'old car deleted')
    t.eq(F.entities[second].model, 'hash:sultan')
end)

t.test('blocked models are for staff only, even under another name with the same hash', function()
    later()
    t.eq(select(2, spawn(PLAYER, 'rhino')), 'rhino is not allowed on this server.')
    F.hashAlias['zz_secret_tank'] = 'rhino'
    t.eq(select(2, spawn(PLAYER, 'zz_secret_tank')), 'zz_secret_tank is not allowed on this server.')
    t.eq(F.entities[(spawn(ADMIN, 'rhino'))].model, 'hash:rhino')
    F.leaveVehicle(ADMIN)
    t.eq(spawn(ADMIN, 'adder') ~= nil, true, 'no cooldown for staff')
    F.leaveVehicle(ADMIN)
end)

t.test('the vehicle type must match the model', function()
    later()
    F.leaveVehicle(PLAYER)
    t.contains(select(2, spawn(PLAYER, 'buzzard2', 'automobile')), "buzzard2 can't be spawned here")
    t.contains(select(2, spawn(PLAYER, 'adder', 'heli')), "adder can't be spawned here")
    t.contains(select(2, spawn(PLAYER, 'myheli', 'heli')), 'Config.VehicleTypes', 'unknown add-on helicopter')
    Config.VehicleTypes.myheli = 'heli'
    local heli = spawn(PLAYER, 'myheli', 'heli')
    t.eq(F.entities[heli].vehicleType, 'heli')
    Config.VehicleTypes.myheli = nil
    F.leaveVehicle(PLAYER)
    later()
    F.hashAlias['zz_heli'] = 'buzzard2'
    t.contains(select(2, spawn(PLAYER, 'zz_heli', 'automobile')), "zz_heli can't be spawned here", 'another name for a helicopter')
    F.hashAlias['zz_train'] = 'freight'
    t.contains(select(2, spawn(PLAYER, 'zz_train', 'automobile')), "zz_train can't be spawned here", 'another name for a train')
    F.seat(PLAYER, heli) -- back in their last car for the tests below
end)

t.test('bad models and vehicle types are refused', function()
    t.eq(select(2, spawn(OTHER, 'x;drop')), 'That is not a vehicle you can spawn.')
    t.eq(select(2, spawn(OTHER, 'adder', 'rocket')), 'That is not a vehicle you can spawn.')
    t.eq(select(2, spawn(OTHER, 'freight', 'train')), 'That is not a vehicle you can spawn.')
end)

t.test('the car goes into the same instance (routing bucket) as the player', function()
    local car = spawn(OTHER, 'adder')
    t.eq(F.entities[car].bucket, 4)
    F.leaveVehicle(OTHER)
end)

t.test("you can't spawn while sitting in someone else's vehicle", function()
    later()
    local taxi = F.addVehicle('taxi', vector3(0, 0, 30), GetPlayerPed(OTHER))
    t.eq(select(2, spawn(OTHER, 'adder')), 'Get out of this vehicle first.')
    DeleteEntity(taxi)
end)

t.test("your last car isn't deleted while someone else is in it", function()
    later()
    local mine = vehicleOf(PLAYER)
    F.leaveVehicle(PLAYER)
    F.seat(OTHER, mine)
    local new = spawn(PLAYER, 'sultan')
    t.eq(DoesEntityExist(mine), true, 'left for the other player')
    t.eq(new ~= mine, true)
    F.leaveVehicle(OTHER)
end)

t.test('sitting in your own last car while someone else is in it: get out first', function()
    later()
    local mine = vehicleOf(PLAYER)
    F.leaveVehicle(PLAYER)
    F.seat(OTHER, mine, -1)
    F.seat(PLAYER, mine, 0)
    t.eq(select(2, spawn(PLAYER, 'adder')), 'Get out of this vehicle first.')
    F.leaveVehicle(OTHER)
    F.leaveVehicle(PLAYER)
end)

t.test('an ACE can limit who spawns', function()
    later()
    Config.AcePermission = 'vehiclespawn.use'
    t.eq(select(2, spawn(OTHER, 'adder')), "You aren't allowed to spawn vehicles.")
    F.players[OTHER].aces['vehiclespawn.use'] = true
    t.eq(spawn(OTHER, 'adder') ~= nil, true)
    F.leaveVehicle(OTHER)
    Config.AcePermission = ''
end)

t.test('/dv: only your own spawned vehicle, unless you are staff', function()
    later()
    F.leaveVehicle(PLAYER)
    local mine = spawn(PLAYER, 'adder')
    F.leaveVehicle(PLAYER)
    local theirs = F.addVehicle('taxi', vector3(9000, 0, 30))
    F.entities[GetPlayerPed(PLAYER)].coords = F.entities[theirs].coords
    t.eq(delete(PLAYER, theirs), 'You can only delete vehicles you spawned.')
    t.eq(delete(ADMIN, theirs), 'That vehicle is too far away.')
    F.entities[GetPlayerPed(ADMIN)].coords = F.entities[theirs].coords
    t.eq(delete(ADMIN, theirs), 'Vehicle deleted.')
    t.eq(DoesEntityExist(theirs), false)
    t.eq(delete(PLAYER, 99999), 'There is no vehicle to delete.')
    F.entities[GetPlayerPed(PLAYER)].coords = F.entities[mine].coords
    t.eq(delete(PLAYER, mine), 'Vehicle deleted.')
end)

t.test('/dv on foot picks your own car even when another one is closer', function()
    later()
    local mine = spawn(PLAYER, 'adder')
    F.leaveVehicle(PLAYER)
    local closer = F.addVehicle('taxi', F.entities[mine].coords)
    F.entities[GetPlayerPed(PLAYER)].coords = F.entities[mine].coords
    t.eq(delete(PLAYER, closer), 'Vehicle deleted.')
    t.eq(DoesEntityExist(mine), false)
    t.eq(DoesEntityExist(closer), true)
    later()
    mine = spawn(PLAYER, 'adder')
    F.leaveVehicle(PLAYER)
    t.eq(delete(PLAYER, nil), 'Vehicle deleted.', 'nothing found nearby by the game')
end)

t.test("/dv won't delete a car someone else is driving", function()
    later()
    local car = spawn(PLAYER, 'adder')
    F.leaveVehicle(PLAYER)
    F.seat(OTHER, car)
    F.entities[GetPlayerPed(PLAYER)].coords = F.entities[car].coords
    t.eq(delete(PLAYER, car), 'Someone else is driving it.')
    F.leaveVehicle(OTHER)
end)

t.test("a car that never reaches the player's game is removed", function()
    later()
    F.send(PLAYER, 'preston-vehiclespawn:spawn', 'adder', 'automobile')
    local netId = F.last(PLAYER, 'preston-vehiclespawn:seat').args[1]
    F.send(OTHER, 'preston-vehiclespawn:seatFailed', netId)
    t.eq(DoesEntityExist(netId), true, 'only the owner can report it')
    F.send(PLAYER, 'preston-vehiclespawn:seatFailed', netId)
    t.eq(DoesEntityExist(netId), false)
end)

t.test('a vehicle the game fails to create is reported', function()
    later()
    F.failSpawn = true
    t.eq(select(2, spawn(OTHER, 'adder')), "adder couldn't be spawned.")
    F.failSpawn = false
end)

t.test("a player's car is removed when they leave, unless someone else is in it", function()
    later()
    local car = spawn(OTHER, 'adder')
    F.leaveVehicle(OTHER)
    F.seat(PLAYER, car)
    F.drop(OTHER)
    t.eq(DoesEntityExist(car), true, 'kept: someone is in it')
    F.leaveVehicle(PLAYER)
    later()
    local mine = spawn(PLAYER, 'adder')
    F.drop(PLAYER)
    t.eq(DoesEntityExist(mine), false)
end)

t.finish()
