-- Spawning and styling police vehicles goes through the server: it checks the player's permission,
-- the cooldown and the department, creates the car itself and sets the unit-number plate. The player's
-- game then gets in once the car has reached it and applies the department's paint, livery and extras.

local I = IowaPolice

local lastSpawn, spawned, lastSkin = {}, {}, {}

local function allowed(src)
    return Config.AcePermission == '' or IsPlayerAceAllowed(src, Config.AcePermission)
end

local function tell(src, message, tone)
    TriggerClientEvent('preston-iowa:notify', src, message, tone or 'error')
end

-- Tells the player's game to style the vehicle; seat = also get in first (a freshly spawned car).
local function dress(src, vehicle, key, seat, message)
    TriggerClientEvent('preston-iowa:dress', src, NetworkGetNetworkIdFromEntity(vehicle), key, seat, message)
end

-- The unit number a player typed, or one from their server ID when they didn't type one.
local function unitFor(src, typed)
    if typed == nil or typed == '' then return (src - 1) % 9999 + 1 end
    return I.parseUnit(typed)
end

-- Whether a player other than src is sitting in the vehicle.
local function otherPlayerInside(vehicle, src)
    for _, id in ipairs(GetPlayers()) do
        local player = tonumber(id)
        if player ~= src and GetVehiclePedIsIn(GetPlayerPed(player), false) == vehicle then return true end
    end
    return false
end

-- A trooper's last car is removed when they spawn another or leave, unless a partner (or a suspect)
-- is in it: then it's left alone and no longer counted as theirs.
local function releasePrevious(src)
    local previous = spawned[src]
    spawned[src] = nil
    if previous and DoesEntityExist(previous) and not otherPlayerInside(previous, src) then DeleteEntity(previous) end
end

RegisterNetEvent('preston-iowa:spawn', function(departmentName, typedUnit)
    local src = source
    if not allowed(src) then return tell(src, "You aren't on the police whitelist.") end
    local key, department = I.findDepartment(Config, departmentName)
    if not key then return tell(src, 'Unknown department.') end
    local unit = unitFor(src, typedUnit)
    if not unit then return tell(src, 'Unit numbers go from 1 to 9999, like /' .. department.command .. ' 101') end
    local wait = I.cooldownLeft(lastSpawn[src], os.time(), Config.CooldownSeconds)
    if wait > 0 then return tell(src, ('Wait %ds before spawning another vehicle.'):format(wait)) end

    local ped = GetPlayerPed(src)
    local current = GetVehiclePedIsIn(ped, false)
    local previous = spawned[src]
    local previousStays = previous and DoesEntityExist(previous)
        and (not Config.DeletePreviousVehicle or otherPlayerInside(previous, src))
    if current ~= 0 and (current ~= previous or previousStays) then return tell(src, 'Get out of this vehicle first.') end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    if coords.x == 0.0 and coords.y == 0.0 then return tell(src, 'Wait until you have loaded in.') end

    lastSpawn[src] = os.time()
    if Config.DeletePreviousVehicle then releasePrevious(src) end

    local vehicle = CreateVehicleServerSetter(GetHashKey(department.model), department.vehicleType or 'automobile',
        coords.x, coords.y, coords.z + 0.5, heading)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return tell(src, ("The %s vehicle (%s) couldn't be spawned."):format(department.label, department.model))
    end
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src)) -- same instance as the player
    local plate = I.plateFor(department.plate, unit)
    SetVehicleNumberPlateText(vehicle, plate)
    spawned[src] = vehicle
    dress(src, vehicle, key, true, ('%s unit %s is on the road.'):format(department.label, plate))
end)

-- The player's game never received the new car (usually a model that isn't installed): remove it.
RegisterNetEvent('preston-iowa:seatFailed', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 and spawned[src] == vehicle then
        spawned[src] = nil
        DeleteEntity(vehicle)
    end
end)

-- /iowaskin: the department's look and a unit plate on the car the player is driving.
RegisterNetEvent('preston-iowa:skin', function(departmentName, typedUnit)
    local src = source
    if not allowed(src) then return tell(src, "You aren't on the police whitelist.") end
    local key, department = I.findDepartment(Config, departmentName or Config.DefaultDepartment)
    if not key then return tell(src, 'Unknown department.') end
    local unit = unitFor(src, typedUnit)
    if not unit then return tell(src, 'Unit numbers go from 1 to 9999.') end
    if I.cooldownLeft(lastSkin[src], os.time(), 2) > 0 then return tell(src, 'Slow down a little.') end
    lastSkin[src] = os.time()
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return tell(src, 'Get in the driver seat of a vehicle first.')
    end
    local plate = I.plateFor(department.plate, unit)
    SetVehicleNumberPlateText(vehicle, plate)
    dress(src, vehicle, key, false, ('Styled as %s unit %s.'):format(department.label, plate))
end)

-- Another script deleted a trooper's car: forget it, so the old handle is never used again.
AddEventHandler('entityRemoved', function(entity)
    for player, vehicle in pairs(spawned) do
        if vehicle == entity then spawned[player] = nil end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Config.DeletePreviousVehicle then releasePrevious(src) end
    spawned[src], lastSpawn[src], lastSkin[src] = nil, nil, nil
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, problem in ipairs(I.checkConfig(Config)) do print(('[preston-iowapolice] config problem: %s'):format(problem)) end
end)
