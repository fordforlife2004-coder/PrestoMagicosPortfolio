-- Every command that changes a vehicle goes through the server first. It checks the command's
-- permission, that the player is driving the vehicle and that the values make sense, then tells the
-- player's game to apply it. /spawnskin vehicles are created by the server itself; the player's game
-- gets in once the car has reached it.

local S = VehicleSkins

local allowRequest, forgetRequests = S.newRateLimiter(6, 2)
local lastSpawn, spawned = {}, {}

-- Which permission in Config.Permissions each request needs.
local PERMISSION_OF = { livery = 'livery', randomlivery = 'livery', extra = 'extra', color = 'color', plate = 'plate', tune = 'tune' }

local function tell(src, message, tone)
    TriggerClientEvent('preston-skins:notify', src, message, tone or 'error')
end

local function allowed(src, permission)
    local ace = Config.Permissions[permission]
    return ace == '' or (type(ace) == 'string' and IsPlayerAceAllowed(src, ace))
end

-- The vehicle the player is driving, or nil.
local function drivenBy(src)
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then return vehicle end
    return nil
end

local function apply(src, vehicle, action, data)
    data.netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerClientEvent('preston-skins:apply', src, action, data)
end

-- Checks the values typed for each command. Returns the data for the player's game, or nil and why.
local Check = {}

function Check.livery(args)
    local number = S.parseNumber(args[1], 1, 100)
    if not number then return nil, 'Use a livery number, like /setlivery 2 (see /liveries).' end
    return { number = number }
end

function Check.randomlivery()
    return {}
end

function Check.extra(args)
    local number = S.parseNumber(args[1], 1, S.MAX_EXTRA)
    if not number then return nil, ('Use an extra number from 1 to %d, like /extra 1 (see /extras).'):format(S.MAX_EXTRA) end
    return { number = number }
end

function Check.color(args)
    local primary = S.parseNumber(args[1], 0, S.MAX_COLOR)
    local secondary = args[2] == nil and primary or S.parseNumber(args[2], 0, S.MAX_COLOR)
    if not primary or not secondary then
        return nil, ('Use paint numbers from 0 to %d, like /color 27 0 (red and black).'):format(S.MAX_COLOR)
    end
    return { primary = primary, secondary = secondary }
end

function Check.plate(args)
    local text = S.formatPlate(table.concat(args, ' '))
    if text == '' then return nil, 'Type the plate text, like /plate PRESTON (up to 8 letters and numbers).' end
    return { text = text }
end

function Check.tune()
    return {}
end

-- Keeps only short text values from what a player's game sent.
local function cleanArgs(args)
    local out = {}
    if type(args) ~= 'table' then return out end
    for i = 1, math.min(#args, 8) do
        local value = args[i]
        if type(value) ~= 'string' and type(value) ~= 'number' then break end
        out[i] = tostring(value):sub(1, 32)
    end
    return out
end

RegisterNetEvent('preston-skins:request', function(action, args)
    local src = source
    if not allowRequest(src, GetGameTimer() / 1000) then return tell(src, 'Slow down a little.') end
    if type(action) ~= 'string' or not Check[action] then return end
    if not allowed(src, PERMISSION_OF[action]) then return tell(src, "You aren't allowed to use that command.") end
    local vehicle = drivenBy(src)
    if not vehicle then return tell(src, 'Get in the driver seat of a vehicle first.') end
    local data, problem = Check[action](cleanArgs(args))
    if not data then return tell(src, problem) end
    apply(src, vehicle, action, data)
end)

-- Whether a player other than src is sitting in the vehicle.
local function otherPlayerInside(vehicle, src)
    for _, id in ipairs(GetPlayers()) do
        local player = tonumber(id)
        if player ~= src and GetVehiclePedIsIn(GetPlayerPed(player), false) == vehicle then return true end
    end
    return false
end

-- A player's last /spawnskin car is removed when they spawn another or leave, unless someone else is
-- in it: then it's left for them and no longer counted as the player's.
local function releasePrevious(src)
    local previous = spawned[src]
    spawned[src] = nil
    if previous and DoesEntityExist(previous) and not otherPlayerInside(previous, src) then DeleteEntity(previous) end
end

RegisterNetEvent('preston-skins:spawn', function(model, vehicleType, livery)
    local src = source
    if not allowed(src, 'spawnskin') then return tell(src, "You aren't allowed to use that command.") end
    model = S.normalizeModel(model)
    if not S.validModelName(model) or not S.VEHICLE_TYPES[vehicleType] then
        return tell(src, 'That is not a vehicle you can spawn.')
    end
    if S.isBlocked(Config, model, GetHashKey) then return tell(src, ('%s is not allowed on this server.'):format(model)) end
    -- A vehicle spawned as the wrong type is broken for everyone near it.
    if vehicleType ~= S.typeFor(Config, model, GetHashKey) then
        return tell(src, ("%s can't be spawned here. If it's an add-on, add its type to Config.VehicleTypes."):format(model))
    end
    livery = livery ~= nil and S.parseNumber(livery, 1, 100) or nil
    local wait = S.cooldownLeft(lastSpawn[src], os.time(), Config.SpawnCooldownSeconds)
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

    local vehicle = CreateVehicleServerSetter(GetHashKey(model), vehicleType, coords.x, coords.y, coords.z + 0.5, heading)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return tell(src, ("%s couldn't be spawned."):format(model))
    end
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src)) -- same instance as the player
    local plate = S.formatPlate(Config.SpawnPlate)
    if plate ~= '' then SetVehicleNumberPlateText(vehicle, plate) end
    spawned[src] = vehicle
    -- The player's game gets in once the car has reached it, then sets the livery.
    TriggerClientEvent('preston-skins:seat', src, NetworkGetNetworkIdFromEntity(vehicle), model, livery)
end)

-- The player's game never received the new car (usually a model that isn't installed): remove it.
RegisterNetEvent('preston-skins:seatFailed', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle ~= 0 and spawned[src] == vehicle then
        spawned[src] = nil
        DeleteEntity(vehicle)
    end
end)

-- Another script deleted a spawned car: forget it, so the old handle is never used again.
AddEventHandler('entityRemoved', function(entity)
    for player, vehicle in pairs(spawned) do
        if vehicle == entity then spawned[player] = nil end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Config.DeletePreviousVehicle then releasePrevious(src) end
    spawned[src], lastSpawn[src] = nil, nil
    forgetRequests(src)
end)
