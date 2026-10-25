-- /car and /dv. The server spawns and deletes vehicles itself, after checking the player's permission,
-- the cooldown, blocked models, the vehicle type, and that they aren't sitting in someone else's vehicle.
-- The new car is created here; the player's own game seats them once the car has reached it.

local R = VehicleSpawnRules

local lastSpawn = {} -- [player] = os.time() of their last spawn
local spawned = {}   -- [player] = the vehicle they spawned last
local owner = {}     -- [vehicle] = the player who spawned it

local function allowed(src)
    return Config.AcePermission == '' or IsPlayerAceAllowed(src, Config.AcePermission)
end

local function isStaff(src)
    return Config.StaffAce ~= '' and IsPlayerAceAllowed(src, Config.StaffAce)
end

local function tell(src, message, tone)
    TriggerClientEvent('preston-vehiclespawn:notify', src, message, tone or 'error')
end

local function forgetVehicle(vehicle)
    local by = owner[vehicle]
    owner[vehicle] = nil
    if by and spawned[by] == vehicle then spawned[by] = nil end
end

local function deleteVehicle(vehicle)
    forgetVehicle(vehicle)
    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

-- Whether a player other than src is sitting in the vehicle.
local function otherPlayerInside(vehicle, src)
    for _, id in ipairs(GetPlayers()) do
        local player = tonumber(id)
        if player ~= src and GetVehiclePedIsIn(GetPlayerPed(player), false) == vehicle then return true end
    end
    return false
end

-- A player's last car is removed when they spawn another or leave, unless someone else is in it:
-- then it's left for them and simply no longer counted as the player's.
local function releasePrevious(src)
    local previous = spawned[src]
    if not previous then return end
    if DoesEntityExist(previous) and otherPlayerInside(previous, src) then
        forgetVehicle(previous)
    else
        deleteVehicle(previous)
    end
end

RegisterNetEvent('preston-vehiclespawn:spawn', function(model, vehicleType)
    local src = source
    if not allowed(src) then return tell(src, "You aren't allowed to spawn vehicles.") end
    model = R.normalizeModel(model)
    if not R.validModelName(model) or not R.VEHICLE_TYPES[vehicleType] then
        return tell(src, 'That is not a vehicle you can spawn.')
    end
    local staff = isStaff(src)
    if not staff and R.isBlocked(Config, model, GetHashKey) then
        return tell(src, ('%s is not allowed on this server.'):format(model))
    end
    -- A vehicle spawned as the wrong type is broken for everyone near it, so only trust the type
    -- the player's game sent when it matches the known one (staff may spawn unlisted add-ons).
    if not staff and vehicleType ~= R.typeFor(Config, model, GetHashKey) then
        return tell(src, ("%s can't be spawned here. If it's an add-on, add its type to Config.VehicleTypes."):format(model))
    end
    local wait = R.cooldownLeft(lastSpawn[src], os.time(), Config.CooldownSeconds)
    if not staff and wait > 0 then
        return tell(src, ('Wait %ds before spawning another vehicle.'):format(wait))
    end

    local ped = GetPlayerPed(src)
    local current = GetVehiclePedIsIn(ped, false)
    local previous = spawned[src]
    local previousStays = previous and DoesEntityExist(previous)
        and (not Config.DeletePreviousVehicle or otherPlayerInside(previous, src))
    if current ~= 0 and (current ~= previous or previousStays) then
        return tell(src, 'Get out of this vehicle first.')
    end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    if coords.x == 0.0 and coords.y == 0.0 then return tell(src, 'Wait until you have loaded in.') end

    lastSpawn[src] = os.time()
    if Config.DeletePreviousVehicle then releasePrevious(src) end -- otherwise older cars stay theirs for /dv

    local vehicle = CreateVehicleServerSetter(GetHashKey(model), vehicleType, coords.x, coords.y, coords.z + 0.5, heading)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return tell(src, ("%s couldn't be spawned."):format(model))
    end
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src)) -- same instance as the player
    local plate = R.formatPlate(Config.Plate)
    if plate ~= '' then SetVehicleNumberPlateText(vehicle, plate) end
    spawned[src], owner[vehicle] = vehicle, src
    TriggerClientEvent('preston-vehiclespawn:seat', src, NetworkGetNetworkIdFromEntity(vehicle), model)
end)

-- The player's game never received the new car (usually a model that isn't installed): remove it.
RegisterNetEvent('preston-vehiclespawn:seatFailed', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 and owner[vehicle] == src then deleteVehicle(vehicle) end
end)

RegisterNetEvent('preston-vehiclespawn:delete', function(netId)
    local src = source
    local ped = GetPlayerPed(src)
    local staff = isStaff(src)
    local vehicle = type(netId) == 'number' and NetworkGetEntityFromNetworkId(netId) or 0
    local valid = vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntityType(vehicle) == 2

    -- On foot, /dv means "my car": if the nearest vehicle isn't theirs, use their own car when it's close.
    if not staff and (not valid or owner[vehicle] ~= src) and GetVehiclePedIsIn(ped, false) == 0 then
        local mine = spawned[src]
        if mine and DoesEntityExist(mine) and #(GetEntityCoords(mine) - GetEntityCoords(ped)) <= Config.DeleteDistance + 3.0 then
            vehicle, valid = mine, true
        end
    end

    if not valid then return tell(src, 'There is no vehicle to delete.') end
    if #(GetEntityCoords(vehicle) - GetEntityCoords(ped)) > Config.DeleteDistance + 3.0 then
        return tell(src, 'That vehicle is too far away.')
    end
    if not staff and owner[vehicle] ~= src then
        return tell(src, 'You can only delete vehicles you spawned.')
    end
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if not staff and driver ~= 0 and driver ~= ped then
        return tell(src, 'Someone else is driving it.')
    end
    deleteVehicle(vehicle)
    tell(src, 'Vehicle deleted.', 'success')
end)

AddEventHandler('entityRemoved', function(entity)
    if owner[entity] then forgetVehicle(entity) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Config.DeleteOnLeave then releasePrevious(src) end
    spawned[src], lastSpawn[src] = nil, nil
    for vehicle, by in pairs(owner) do
        if by == src then owner[vehicle] = nil end
    end
end)
