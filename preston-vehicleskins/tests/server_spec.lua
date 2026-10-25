-- Runs server/main.lua against tests/fake_server.lua, to check what the server lets through.
-- Run from the resource folder with any Lua 5.3+:  lua tests/server_spec.lua

local F = dofile('tests/fake_server.lua')
dofile('config.lua')
dofile('shared/vehicle_types.lua')
dofile('shared/skins.lua')
dofile('server/main.lua')
local t = F.runner()

local DRIVER, PASSENGER, VIP = 1, 2, 3
F.addPlayer(DRIVER, 'Driver')
F.addPlayer(PASSENGER, 'Passenger')
F.addPlayer(VIP, 'Vip', { aces = { vehicleskins = true } })
local car = F.addVehicle('police3', vector3(0, 0, 30), GetPlayerPed(DRIVER))
F.entities[GetPlayerPed(PASSENGER)].vehicle = car
F.entities[car].seats[0] = GetPlayerPed(PASSENGER)
local vipCar = F.addVehicle('sultan', vector3(50, 0, 30), GetPlayerPed(VIP))

-- Sends a command's request; returns what the server sent back: ('apply', action, data) or ('notify', message).
local function ask(src, action, ...)
    F.now = F.now + 5 -- stay under the rate limit
    local before = #F.toClients
    F.send(src, 'preston-skins:request', action, { ... })
    local reply = F.toClients[#F.toClients]
    if #F.toClients == before then return nil end
    if reply.name == 'preston-skins:apply' then return 'apply', reply.args[1], reply.args[2] end
    return 'notify', reply.args[1]
end

t.test('livery numbers are checked and sent for the driven vehicle', function()
    local kind, action, data = ask(DRIVER, 'livery', '2')
    t.eq(kind, 'apply')
    t.eq(action, 'livery')
    t.eq(data.number, 2)
    t.eq(data.netId, car)
    local _, message = ask(DRIVER, 'livery', 'blue')
    t.contains(message, 'Use a livery number')
end)

t.test('passengers and people on foot are refused', function()
    local _, message = ask(PASSENGER, 'livery', '1')
    t.eq(message, 'Get in the driver seat of a vehicle first.')
end)

t.test('extras and paint numbers are kept in range', function()
    t.eq(select(3, ask(DRIVER, 'extra', '3')).number, 3)
    t.contains(select(2, ask(DRIVER, 'extra', '21')), 'from 1 to 20')
    local _, _, paint = ask(DRIVER, 'color', '27', '0')
    t.eq(paint.primary, 27)
    t.eq(paint.secondary, 0)
    t.eq(select(3, ask(DRIVER, 'color', '12')).secondary, 12, 'one number paints both')
    t.contains(select(2, ask(DRIVER, 'color', '200')), 'from 0 to 160')
end)

t.test('custom plates and tuning need their permission', function()
    t.eq(select(2, ask(DRIVER, 'plate', 'hello')), "You aren't allowed to use that command.")
    t.eq(select(2, ask(DRIVER, 'tune')), "You aren't allowed to use that command.")
    local _, _, plate = ask(VIP, 'plate', 'isp', '101!')
    t.eq(plate.text, 'ISP 101')
    t.eq(plate.netId, vipCar)
    t.eq(ask(VIP, 'tune'), 'apply')
end)

t.test('unknown actions are ignored and odd values are cleaned', function()
    t.eq(ask(DRIVER, 'explode'), nil)
    F.now = F.now + 5
    F.send(VIP, 'preston-skins:request', 'plate', { 'ok', { 'nested' }, 'never' })
    t.eq(F.toClients[#F.toClients].args[2].text, 'OK', 'stops at the first value that is not text')
end)

t.test('requests are rate limited', function()
    F.now = F.now + 5
    local slowed = 0
    for _ = 1, 10 do
        F.send(DRIVER, 'preston-skins:request', 'livery', { '1' })
        if F.toClients[#F.toClients].args[1] == 'Slow down a little.' then slowed = slowed + 1 end
    end
    t.eq(slowed, 4, '6 every 2 seconds')
end)

local WALKER, PARTNER = 4, 5
F.addPlayer(WALKER, 'Walker', { bucket = 2 })
F.addPlayer(PARTNER, 'Partner')

-- /spawnskin. Returns the new vehicle and the seat event's arguments, or nil and the message.
local function spawnskin(src, model, kind, livery)
    F.now = F.now + 20
    local before = #F.toClients
    F.send(src, 'preston-skins:spawn', model, kind or 'automobile', livery)
    local reply = F.toClients[#F.toClients]
    if #F.toClients == before then return nil, 'no answer' end
    if reply.name ~= 'preston-skins:seat' then return nil, reply.args[1] end
    local vehicle = NetworkGetEntityFromNetworkId(reply.args[1])
    F.seat(src, vehicle)
    return vehicle, reply.args
end

t.test('/spawnskin creates the car in your instance and tells your game to get in and set the livery', function()
    local vehicle, seat = spawnskin(WALKER, 'Police3', 'automobile', '3')
    t.eq(F.entities[vehicle].model, 'hash:police3')
    t.eq(F.entities[vehicle].plate, 'PRESTON')
    t.eq(F.entities[vehicle].bucket, 2)
    t.eq(seat[2], 'police3')
    t.eq(seat[3], 3, 'livery number')
end)

t.test('/spawnskin: cooldown, blocked models (by hash), and the vehicle type must match', function()
    F.leaveVehicle(WALKER)
    F.send(WALKER, 'preston-skins:spawn', 'adder', 'automobile')
    t.contains(F.last(WALKER).args[1], 'Wait ')
    t.eq(select(2, spawnskin(WALKER, 'hydra', 'plane')), 'hydra is not allowed on this server.')
    F.hashAlias['zz_jet'] = 'hydra'
    t.eq(select(2, spawnskin(WALKER, 'zz_jet', 'automobile')), 'zz_jet is not allowed on this server.')
    t.contains(select(2, spawnskin(WALKER, 'polmav', 'automobile')), "polmav can't be spawned here")
    F.hashAlias['zz_heli'] = 'polmav'
    t.contains(select(2, spawnskin(WALKER, 'zz_heli', 'automobile')), "zz_heli can't be spawned here", 'another name for the same helicopter')
    t.eq(spawnskin(WALKER, 'polmav', 'heli') ~= nil, true)
    F.leaveVehicle(WALKER)
end)

t.test('/spawnskin replaces your last car, unless someone else is in it', function()
    local first = spawnskin(WALKER, 'police3')
    F.leaveVehicle(WALKER)
    local second = spawnskin(WALKER, 'police2')
    t.eq(DoesEntityExist(first), false, 'replaced')
    F.leaveVehicle(WALKER)
    F.seat(PARTNER, second)
    local third = spawnskin(WALKER, 'sheriff')
    t.eq(DoesEntityExist(second), true, 'kept for the partner')
    F.leaveVehicle(PARTNER)
    F.leaveVehicle(WALKER)
    F.seat(PARTNER, third)
    F.drop(WALKER)
    t.eq(DoesEntityExist(third), true, 'kept when the spawner leaves, because the partner is in it')
end)

t.test('a /spawnskin car that never reaches the player is removed, and only by its owner', function()
    F.addPlayer(6, 'Six')
    F.now = F.now + 20
    F.send(6, 'preston-skins:spawn', 'police3', 'automobile')
    local netId = F.last(6, 'preston-skins:seat').args[1]
    F.send(PARTNER, 'preston-skins:seatFailed', netId)
    t.eq(DoesEntityExist(netId), true)
    F.send(6, 'preston-skins:seatFailed', netId)
    t.eq(DoesEntityExist(netId), false)
end)

t.test('a spawned car removed by another script is forgotten, so a reused handle is never deleted', function()
    local car = spawnskin(6, 'police3')
    F.leaveVehicle(6)
    DeleteEntity(car)
    F.fire('entityRemoved', car)
    F.entities[car] = { type = 2, model = 'hash:taxi', seats = {}, coords = vector3(0, 0, 30) } -- the game reuses the handle
    spawnskin(6, 'police2')
    t.eq(DoesEntityExist(car), true, "someone else's taxi survives")
end)

t.finish()
