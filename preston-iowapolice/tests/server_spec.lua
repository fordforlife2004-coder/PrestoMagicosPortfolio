-- Runs server/main.lua against tests/fake_server.lua, to check who can spawn and style police cars.
-- Run from the resource folder with any Lua 5.3+:  lua tests/server_spec.lua

local F = dofile('tests/fake_server.lua')
dofile('config.lua')
dofile('shared/iowa.lua')
dofile('server/main.lua')
local t = F.runner()

local TROOPER, CIVILIAN, PARTNER = 12, 2, 7
F.addPlayer(TROOPER, 'Trooper', { aces = { ['iowapolice.use'] = true }, bucket = 3 })
F.addPlayer(CIVILIAN, 'Civilian')
F.addPlayer(PARTNER, 'Partner', { aces = { ['iowapolice.use'] = true } })

local function lastMessage(src) return F.last(src, 'preston-iowa:notify').args[1] end
local function vehicleOf(src) return GetVehiclePedIsIn(GetPlayerPed(src)) end
local function later(seconds) F.now = F.now + (seconds or 30) end

-- Asks for a car. Returns the new vehicle (after the player's game gets in) and the dress event's
-- arguments, or nil and the server's message.
local function spawn(src, department, unit)
    local before = #F.toClients
    F.send(src, 'preston-iowa:spawn', department, unit)
    local reply = F.toClients[#F.toClients]
    if #F.toClients == before then return nil, 'no answer' end
    if reply.name ~= 'preston-iowa:dress' then return nil, reply.args[1] end
    local vehicle = NetworkGetEntityFromNetworkId(reply.args[1])
    F.seat(src, vehicle)
    return vehicle, reply.args
end

t.test('civilians are refused by default', function()
    t.eq(select(2, spawn(CIVILIAN, 'isp', '101')), "You aren't on the police whitelist.")
end)

t.test('a trooper gets an ISP car with a unit plate, in their instance; their game gets in and styles it', function()
    local car, dress = spawn(TROOPER, 'isp', '101')
    t.eq(F.entities[car].model, 'hash:police3')
    t.eq(F.entities[car].plate, 'ISP 101')
    t.eq(F.entities[car].bucket, 3)
    t.eq(dress[2], 'isp')
    t.eq(dress[3], true, 'get in first')
    t.eq(dress[4], 'Iowa State Patrol unit ISP 101 is on the road.')
end)

t.test('without a unit number, one comes from the server ID', function()
    later()
    F.leaveVehicle(TROOPER)
    local car = spawn(TROOPER, 'sheriff')
    t.eq(F.entities[car].plate, 'SO 012')
end)

t.test('there is a cooldown, and bad unit numbers and departments are refused', function()
    later(5)
    F.leaveVehicle(TROOPER)
    t.eq(select(2, spawn(TROOPER, 'isp', '5')), 'Wait 10s before spawning another vehicle.')
    t.eq(select(2, spawn(TROOPER, 'isp', '99999')), 'Unit numbers go from 1 to 9999, like /isp 101')
    t.eq(select(2, spawn(TROOPER, 'fbi', '1')), 'Unknown department.')
end)

t.test('spawning again replaces the last car', function()
    later()
    local old = F.entities[GetPlayerPed(TROOPER)].vehicle or select(1, spawn(TROOPER, 'isp', '100'))
    F.leaveVehicle(TROOPER)
    later()
    local new = spawn(TROOPER, 'isp', '102')
    t.eq(DoesEntityExist(old), false)
    t.eq(F.entities[new].plate, 'ISP 102')
end)

t.test("the last car isn't deleted while a partner is in it", function()
    later()
    local mine = vehicleOf(TROOPER)
    F.leaveVehicle(TROOPER)
    F.seat(PARTNER, mine)
    local new = spawn(TROOPER, 'isp', '103')
    t.eq(DoesEntityExist(mine), true, 'the partner keeps it')
    t.eq(new ~= mine, true)
end)

t.test('riding as a passenger in your own car while a partner drives: get out first', function()
    later()
    local mine = vehicleOf(TROOPER)
    F.leaveVehicle(TROOPER)
    F.leaveVehicle(PARTNER)
    F.seat(PARTNER, mine, -1)
    F.seat(TROOPER, mine, 0)
    t.eq(select(2, spawn(TROOPER, 'isp', '104')), 'Get out of this vehicle first.')
    F.leaveVehicle(PARTNER)
    F.leaveVehicle(TROOPER)
end)

t.test('a model that the game fails to create is reported clearly', function()
    later()
    F.failSpawn = true
    t.eq(select(2, spawn(TROOPER, 'isp', '105')), "The Iowa State Patrol vehicle (police3) couldn't be spawned.")
    F.failSpawn = false
end)

t.test("a car that never reaches the trooper's game is removed, only on the trooper's word", function()
    later()
    F.send(TROOPER, 'preston-iowa:spawn', 'isp', '106')
    local netId = F.last(TROOPER, 'preston-iowa:dress').args[1]
    F.send(PARTNER, 'preston-iowa:seatFailed', netId)
    t.eq(DoesEntityExist(netId), true)
    F.send(TROOPER, 'preston-iowa:seatFailed', netId)
    t.eq(DoesEntityExist(netId), false)
end)

t.test('a car removed by another script is forgotten, so a reused handle is never deleted', function()
    later()
    local car = spawn(TROOPER, 'isp', '107')
    F.leaveVehicle(TROOPER)
    DeleteEntity(car)
    F.fire('entityRemoved', car)
    F.entities[car] = { type = 2, model = 'hash:taxi', seats = {}, coords = vector3(0, 0, 30) }
    later()
    spawn(TROOPER, 'isp', '108')
    t.eq(DoesEntityExist(car), true, "someone else's taxi survives")
    F.leaveVehicle(TROOPER)
end)

t.test('/iowaskin styles the car you are driving, with the default department', function()
    local car = F.addVehicle('police', vector3(0, 0, 30), GetPlayerPed(CIVILIAN))
    F.send(CIVILIAN, 'preston-iowa:skin', nil, '200')
    t.eq(lastMessage(CIVILIAN), "You aren't on the police whitelist.")
    F.players[CIVILIAN].aces['iowapolice.use'] = true
    F.send(CIVILIAN, 'preston-iowa:skin', nil, '200')
    t.eq(F.entities[car].plate, 'ISP 200')
    local dress = F.last(CIVILIAN, 'preston-iowa:dress').args
    t.eq(dress[2], 'isp')
    t.eq(dress[3], false, 'already in the car')
    t.eq(dress[4], 'Styled as Iowa State Patrol unit ISP 200.')
    F.send(CIVILIAN, 'preston-iowa:skin', 'sheriff', '201')
    t.eq(lastMessage(CIVILIAN), 'Slow down a little.')
end)

t.test('/iowaskin needs the driver seat', function()
    later(5)
    F.leaveVehicle(CIVILIAN)
    F.send(CIVILIAN, 'preston-iowa:skin', 'isp', '1')
    t.eq(lastMessage(CIVILIAN), 'Get in the driver seat of a vehicle first.')
end)

t.test("a trooper's car is removed when they leave, unless a partner is in it", function()
    later()
    local car = spawn(PARTNER, 'isp', '300')
    F.leaveVehicle(PARTNER)
    F.seat(TROOPER, car)
    F.drop(PARTNER)
    t.eq(DoesEntityExist(car), true, 'kept: the trooper is in it')
    F.leaveVehicle(TROOPER)
    later()
    local mine = spawn(TROOPER, 'isp', '301')
    F.drop(TROOPER)
    t.eq(DoesEntityExist(mine), false)
end)

t.finish()
