-- The player's side of /car and /dv: checks the model exists in the game, works out what kind of
-- vehicle it is, and asks the server. The server spawns and deletes; this game seats the player in
-- the new car once it has arrived here.

local R = VehicleSpawnRules

-- GTA notifications take at most 99 characters per piece of text, so longer ones go in pieces.
local function notify(message, tone)
    BeginTextCommandThefeedPost(#message > 99 and 'CELL_EMAIL_BCON' or 'STRING')
    for i = 1, #message, 99 do AddTextComponentSubstringPlayerName(message:sub(i, i + 98)) end
    EndTextCommandThefeedPostTicker(tone == 'error', false)
end

-- The type the server needs to spawn a model, or nil for trains (which it can't spawn).
local function vehicleTypeOf(model, hash)
    if R.isTrain(model) then return nil end
    local known = (Config.VehicleTypes or {})[model] or KnownVehicleTypes[model]
    if known then return known end
    -- An add-on vehicle: ask the game what it is.
    if IsThisModelAHeli(hash) then return 'heli' end
    if IsThisModelAPlane(hash) then return 'plane' end
    if IsThisModelABoat(hash) or IsThisModelAJetski(hash) then return 'boat' end
    if IsThisModelABike(hash) or IsThisModelABicycle(hash) then return 'bike' end
    if IsThisModelATrain(hash) then return nil end
    if IsThisModelACar(hash) or IsThisModelAQuadbike(hash) or IsThisModelAnAmphibiousCar(hash) then return 'automobile' end
    if GetVehicleClassFromName(hash) == 11 then return 'trailer' end
    return 'automobile'
end

RegisterCommand('car', function(_, args)
    local model = R.normalizeModel(args[1])
    if model == '' then return notify('Type a model name, like /car adder', 'error') end
    local hash = GetHashKey(model)
    if not R.validModelName(model) or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return notify(('"%s" is not a vehicle in this game.'):format(model), 'error')
    end
    local vehicleType = vehicleTypeOf(model, hash)
    if not vehicleType then return notify("Trains can't be spawned.", 'error') end
    TriggerServerEvent('preston-vehiclespawn:spawn', model, vehicleType)
end, false)

-- The vehicle the player is in, otherwise the closest one within Config.DeleteDistance.
local function targetVehicle()
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside ~= 0 then return inside end
    local here = GetEntityCoords(ped)
    local best, bestDistance = 0, Config.DeleteDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local distance = #(GetEntityCoords(vehicle) - here)
        if distance < bestDistance then best, bestDistance = vehicle, distance end
    end
    return best
end

-- The server also checks for the player's own car nearby, so it's asked even when nothing was found here.
RegisterCommand('dv', function()
    local vehicle = targetVehicle()
    local netId = (vehicle ~= 0 and NetworkGetEntityIsNetworked(vehicle)) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    TriggerServerEvent('preston-vehiclespawn:delete', netId)
end, false)

-- The server spawned the car; wait until it has reached this game, then get in.
RegisterNetEvent('preston-vehiclespawn:seat', function(netId, model)
    local vehicle
    for _ = 1, 100 do -- up to 10 seconds, for add-on models that take a while to load
        if NetworkDoesEntityExistWithNetworkId(netId) then
            vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then break end
            vehicle = nil
        end
        Wait(100)
    end
    if not vehicle then
        TriggerServerEvent('preston-vehiclespawn:seatFailed', netId)
        return notify(("%s didn't arrive. Is the model installed on the server? Try again."):format(model), 'error')
    end
    local ped = PlayerPedId()
    for _ = 1, 20 do
        SetPedIntoVehicle(ped, vehicle, -1)
        if GetVehiclePedIsIn(ped, false) == vehicle then break end
        Wait(100)
    end
    notify(('Spawned %s.'):format(model), 'success')
end)

RegisterNetEvent('preston-vehiclespawn:notify', function(message, tone)
    if type(message) == 'string' then notify(message, tone) end
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/car', 'Spawn a vehicle', { { name = 'model', help = 'Spawn name, like adder or sultan' } })
    TriggerEvent('chat:addSuggestion', '/dv', 'Delete the vehicle you spawned (the one you are in or next to)')
end)
