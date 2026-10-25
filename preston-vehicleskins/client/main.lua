-- The player's side: commands that only look at the vehicle (/liveries, /extras) run here, and
-- commands that change it ask the server first. When the server agrees, SkinApply below makes the change.

local S = VehicleSkins

local LIVERY_MOD = 48
local TURBO_MOD = 18

-- GTA notifications take at most 99 characters per piece of text, so longer ones go in pieces.
local function notify(message, tone)
    BeginTextCommandThefeedPost(#message > 99 and 'CELL_EMAIL_BCON' or 'STRING')
    for i = 1, #message, 99 do AddTextComponentSubstringPlayerName(message:sub(i, i + 98)) end
    EndTextCommandThefeedPostTicker(tone == 'error', false)
end

-- The vehicle the player is driving, or 0.
local function drivenVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then return vehicle end
    return 0
end

local function liveriesOf(vehicle)
    SetVehicleModKit(vehicle, 0) -- mod counts read 0 until a mod kit is set
    return S.liveryKind(GetVehicleLiveryCount(vehicle), GetNumVehicleMods(vehicle, LIVERY_MOD))
end

-- The livery the vehicle has now, 1-based (nil for none or the stock look).
local function currentLivery(vehicle, kind)
    local index = kind == 'classic' and GetVehicleLivery(vehicle) or GetVehicleMod(vehicle, LIVERY_MOD)
    return index >= 0 and index + 1 or nil
end

local function setLivery(vehicle, liveries, number)
    if liveries.kind == 'classic' then
        SetVehicleLivery(vehicle, number - 1)
    else
        SetVehicleMod(vehicle, LIVERY_MOD, number - 1, false)
    end
end

-- Each change the server can approve. Returns ok and a message for the player.
SkinApply = {}

function SkinApply.livery(vehicle, data)
    local liveries = liveriesOf(vehicle)
    if not liveries then return false, 'This vehicle has no liveries.' end
    if data.number > liveries.count then
        return false, ('This vehicle has %d liveries. Pick 1 to %d.'):format(liveries.count, liveries.count)
    end
    setLivery(vehicle, liveries, data.number)
    return true, ('Livery %d of %d.'):format(data.number, liveries.count)
end

function SkinApply.randomlivery(vehicle)
    local liveries = liveriesOf(vehicle)
    if not liveries then return false, 'This vehicle has no liveries.' end
    local number = S.randomLivery(liveries.count, currentLivery(vehicle, liveries.kind), math.random)
    setLivery(vehicle, liveries, number)
    return true, ('Random livery: %d of %d.'):format(number, liveries.count)
end

function SkinApply.extra(vehicle, data)
    if not DoesExtraExist(vehicle, data.number) then
        return false, ('This vehicle has no extra %d. See /extras.'):format(data.number)
    end
    -- Changing an extra repairs all damage unless this is off, which would make /extra a free repair.
    SetVehicleAutoRepairDisabled(vehicle, true)
    local on = IsVehicleExtraTurnedOn(vehicle, data.number)
    SetVehicleExtra(vehicle, data.number, on) -- the last value means "disable", so this flips it
    return true, ('Extra %d %s.'):format(data.number, on and 'off' or 'on')
end

function SkinApply.color(vehicle, data)
    ClearVehicleCustomPrimaryColour(vehicle)
    ClearVehicleCustomSecondaryColour(vehicle)
    SetVehicleColours(vehicle, data.primary, data.secondary)
    return true, ('Paint set to %d and %d.'):format(data.primary, data.secondary)
end

function SkinApply.plate(vehicle, data)
    SetVehicleNumberPlateText(vehicle, data.text)
    return true, ('Plate set to %s.'):format(data.text)
end

function SkinApply.tune(vehicle)
    if GetNumModKits(vehicle) == 0 then return false, "This vehicle can't be tuned." end
    SetVehicleModKit(vehicle, 0)
    local upgraded = 0
    for _, mod in ipairs(Config.TuneMods) do
        local levels = GetNumVehicleMods(vehicle, mod)
        if levels > 0 then
            SetVehicleMod(vehicle, mod, levels - 1, false)
            upgraded = upgraded + 1
        end
    end
    if Config.TuneTurbo then ToggleVehicleMod(vehicle, TURBO_MOD, true) end -- turbo is on/off, not a level
    local turbo = Config.TuneTurbo and IsToggleModOn(vehicle, TURBO_MOD)
    if upgraded == 0 and not turbo then return false, "This vehicle can't be tuned." end
    return true, ('Tuned %d parts to their best level%s.'):format(upgraded, turbo and ', plus turbo' or '')
end

-- ---------------------------------------------------------------- commands

local function request(action, args)
    if drivenVehicle() == 0 then return notify('Get in the driver seat of a vehicle first.', 'error') end
    TriggerServerEvent('preston-skins:request', action, args)
end

RegisterCommand('setlivery', function(_, args) request('livery', args) end, false)
RegisterCommand('randomlivery', function() request('randomlivery', {}) end, false)
RegisterCommand('extra', function(_, args) request('extra', args) end, false)
RegisterCommand('color', function(_, args) request('color', args) end, false)
RegisterCommand('plate', function(_, args) request('plate', args) end, false)
RegisterCommand('tune', function() request('tune', {}) end, false)

RegisterCommand('liveries', function()
    local vehicle = drivenVehicle()
    if vehicle == 0 then return notify('Get in the driver seat of a vehicle first.', 'error') end
    local liveries = liveriesOf(vehicle)
    if not liveries then return notify('This vehicle has no liveries.') end
    local current = currentLivery(vehicle, liveries.kind)
    notify(('%d liveries%s. Use /setlivery 1-%d or /randomlivery.'):format(
        liveries.count, current and (', on number ' .. current) or '', liveries.count))
end, false)

RegisterCommand('extras', function()
    local vehicle = drivenVehicle()
    if vehicle == 0 then return notify('Get in the driver seat of a vehicle first.', 'error') end
    local parts = {}
    for id = 1, S.MAX_EXTRA do
        if DoesExtraExist(vehicle, id) then
            parts[#parts + 1] = ('%d %s'):format(id, IsVehicleExtraTurnedOn(vehicle, id) and 'on' or 'off')
        end
    end
    notify(#parts > 0 and ('Extras: %s. Toggle with /extra number.'):format(table.concat(parts, ', ')) or 'This vehicle has no extras.')
end, false)

-- The type the server needs to spawn a model, or nil for trains (which it can't spawn).
local function vehicleTypeOf(model, hash)
    if S.isTrain(model) then return nil end
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

RegisterCommand('spawnskin', function(_, args)
    local model = S.normalizeModel(args[1])
    if model == '' then return notify('Type a model and livery, like /spawnskin police3 2', 'error') end
    local hash = GetHashKey(model)
    if not S.validModelName(model) or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return notify(('"%s" is not a vehicle in this game.'):format(model), 'error')
    end
    local vehicleType = vehicleTypeOf(model, hash)
    if not vehicleType then return notify("Trains can't be spawned.", 'error') end
    TriggerServerEvent('preston-skins:spawn', model, vehicleType, args[2])
end, false)

RegisterCommand('vehicleskins', function()
    local lines = {
        '/spawnskin model livery   /setlivery number   /liveries   /randomlivery',
        '/extra number   /extras   /color primary secondary   /plate text   /tune',
    }
    for _, line in ipairs(lines) do TriggerEvent('chat:addMessage', { args = { 'Skins', line } }) end
end, false)

-- ---------------------------------------------------------------- the server's answers

-- Waits until a vehicle the server knows about has reached this game (up to `seconds`).
local function waitForVehicle(netId, seconds)
    for _ = 1, seconds * 10 do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
        end
        Wait(100)
    end
    return nil
end

local function takeControl(vehicle)
    for _ = 1, 20 do
        if NetworkHasControlOfEntity(vehicle) then return true end
        NetworkRequestControlOfEntity(vehicle)
        Wait(50)
    end
    return NetworkHasControlOfEntity(vehicle)
end

RegisterNetEvent('preston-skins:apply', function(action, data)
    local change = SkinApply[action]
    if not change or type(data) ~= 'table' or type(data.netId) ~= 'number' then return end
    local vehicle = waitForVehicle(data.netId, 2)
    if not vehicle then return notify("Couldn't find the vehicle.", 'error') end
    if not takeControl(vehicle) then return notify("Couldn't take control of the vehicle. Try again.", 'error') end
    local ok, message = change(vehicle, data)
    notify(message, ok and 'success' or 'error')
end)

-- /spawnskin: the server created the car. Wait until it reaches this game, get in, then set the livery.
RegisterNetEvent('preston-skins:seat', function(netId, model, livery)
    local vehicle = waitForVehicle(netId, 10) -- add-on models can take a while to load
    if not vehicle then
        TriggerServerEvent('preston-skins:seatFailed', netId)
        return notify(("%s didn't arrive. Is the model installed on the server? Try again."):format(model), 'error')
    end
    local ped = PlayerPedId()
    for _ = 1, 20 do
        SetPedIntoVehicle(ped, vehicle, -1)
        if GetVehiclePedIsIn(ped, false) == vehicle then break end
        Wait(100)
    end
    if not livery then return notify(('Spawned %s.'):format(model), 'success') end
    if not takeControl(vehicle) then return notify(('Spawned %s, but the livery could not be set. Try /setlivery.'):format(model), 'error') end
    local ok, message = SkinApply.livery(vehicle, { number = livery })
    notify(ok and ('Spawned %s. %s'):format(model, message) or message, ok and 'success' or 'error')
end)

RegisterNetEvent('preston-skins:notify', function(message, tone)
    if type(message) == 'string' then notify(message, tone) end
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/vehicleskins', 'List the vehicle skin commands')
    TriggerEvent('chat:addSuggestion', '/spawnskin', 'Spawn a vehicle with a livery', { { name = 'model', help = 'Spawn name' }, { name = 'livery', help = 'Livery number (optional)' } })
    TriggerEvent('chat:addSuggestion', '/setlivery', 'Set your vehicle livery', { { name = 'number', help = 'See /liveries' } })
    TriggerEvent('chat:addSuggestion', '/extra', 'Turn a vehicle extra on or off', { { name = 'number', help = 'See /extras' } })
    TriggerEvent('chat:addSuggestion', '/color', 'Paint your vehicle', { { name = 'primary', help = '0-160' }, { name = 'secondary', help = '0-160 (optional)' } })
    TriggerEvent('chat:addSuggestion', '/plate', 'Change your plate text', { { name = 'text', help = 'Up to 8 letters and numbers' } })
    TriggerEvent('chat:addSuggestion', '/tune', 'Max out engine, brakes, transmission, suspension and turbo')
end)
