-- Opens the menu panel and passes its button presses to the server. Nothing here decides who is an
-- admin: the server checks every request, so editing or injecting into this file can't grant anything.

local pending = {}
local nextRequestId = 0
local menuOpen = false
local warningsShowing = 0

-- Sends one request to the server and waits for its answer: { ok = true/false, data = ... }.
function Rpc(action, payload)
    nextRequestId = nextRequestId + 1
    local id = nextRequestId
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('preston-admin:rpc', id, action, payload or {})
    SetTimeout(15000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve({ ok = false, data = 'The server did not answer. Try again.' })
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('preston-admin:rpcResult', function(id, ok, data)
    local p = pending[id]
    if not p then return end
    pending[id] = nil
    p:resolve({ ok = ok == true, data = data })
end)

function Toast(message, tone)
    SendNUIMessage({ type = 'toast', message = message, tone = tone or 'info' })
end

local function releaseFocus()
    if not menuOpen and warningsShowing == 0 then SetNuiFocus(false, false) end
end

local function closeMenu()
    menuOpen = false
    SendNUIMessage({ type = 'close' })
    releaseFocus()
end

local function openMenu()
    if menuOpen then return end
    local result = Rpc('state')
    if not result.ok or not result.data.allowed then return end
    menuOpen = true
    local state = result.data
    state.spectating = Spectate.active and Spectate.name or false
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', state = state })
end

RegisterCommand('adminmenu', openMenu, false)
RegisterKeyMapping('adminmenu', 'Open the admin menu', 'keyboard', Config.OpenKey)

RegisterCommand('adminnoclip', function()
    local result = Rpc('setMode', { mode = 'noclip', enabled = not AdminModes.noclip })
    if not result.ok then Toast(result.data, 'danger') end
end, false)
RegisterKeyMapping('adminnoclip', 'Admin menu: toggle noclip', 'keyboard', Config.NoclipKey)

-- ---------------------------------------------------------------- actions that need this game's help
-- The server approves and logs each one first; the game then does the part only it can do.

-- The type the server needs to spawn a model, or nil for trains (which it can't spawn).
local function vehicleTypeOf(model, hash)
    if KnownTrains[model] then return nil end
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

-- The vehicle the admin is driving or sitting in, otherwise the closest one within 6 meters.
local function nearbyVehicle()
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside ~= 0 then return inside end
    local here = GetEntityCoords(ped)
    local best, bestDistance = 0, 6.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local distance = #(GetEntityCoords(vehicle) - here)
        if distance < bestDistance then best, bestDistance = vehicle, distance end
    end
    return best
end

local function takeControl(entity)
    local tries = 0
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and tries < 20 do
        Wait(50)
        tries = tries + 1
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

local ClientActions = {}

ClientActions.teleportWaypoint = function()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return { ok = false, data = 'Set a waypoint on the map first.' } end
    local target = GetBlipInfoIdCoord(blip)
    local result = Rpc('teleportCoords', { x = target.x, y = target.y, z = target.z })
    if not result.ok then return result end

    local ped = PlayerPedId()
    DoScreenFadeOut(200)
    Wait(200)
    local landed = false
    for height = 950.0, 0.0, -50.0 do
        SetPedCoordsKeepVehicle(ped, target.x, target.y, height)
        RequestCollisionAtCoord(target.x, target.y, height)
        Wait(25)
        local found, groundZ = GetGroundZFor_3dCoord(target.x, target.y, height, false)
        if found then
            SetPedCoordsKeepVehicle(ped, target.x, target.y, groundZ + 1.0)
            landed = true
            break
        end
    end
    if not landed then SetPedCoordsKeepVehicle(ped, target.x, target.y, math.max(target.z, 50.0)) end
    DoScreenFadeIn(300)
    return result
end

ClientActions.spawnVehicle = function(p)
    local model = type(p.model) == 'string' and p.model:lower():gsub('%s+', '') or ''
    local hash = GetHashKey(model)
    if model == '' or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return { ok = false, data = ('"%s" is not a vehicle in this game.'):format(model) }
    end
    local vehicleType = vehicleTypeOf(model, hash)
    if not vehicleType then return { ok = false, data = "Trains can't be spawned from the menu." } end
    local result = Rpc('spawnVehicle', { model = model, vehicleType = vehicleType })
    if not result.ok then return result end

    -- The server created the car; wait until it reaches this game (add-on models can take a while), then get in.
    local netId, vehicle = result.data.netId, nil
    for _ = 1, 100 do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then break end
            vehicle = nil
        end
        Wait(100)
    end
    if not vehicle then
        Rpc('vehicleNotArrived', { netId = netId })
        return { ok = false, data = ('%s never arrived. Is the model installed on the server?'):format(model) }
    end
    local ped = PlayerPedId()
    for _ = 1, 20 do
        SetPedIntoVehicle(ped, vehicle, -1)
        if GetVehiclePedIsIn(ped, false) == vehicle then break end
        Wait(100)
    end
    return { ok = true, data = ('Spawned %s.'):format(model) }
end

ClientActions.vehicleAction = function(p)
    local vehicle = nearbyVehicle()
    if vehicle == 0 then return { ok = false, data = 'Get in or stand next to a vehicle first.' } end
    local result = Rpc('vehicleAction', { action = p.action })
    if not result.ok then return result end
    if not takeControl(vehicle) then return { ok = false, data = "Couldn't take control of that vehicle. Try again." } end
    if p.action == 'fix' then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleUndriveable(vehicle, false)
        SetVehicleEngineOn(vehicle, true, true, false)
    elseif p.action == 'flip' then
        local rotation = GetEntityRotation(vehicle, 2)
        SetEntityRotation(vehicle, 0.0, 0.0, rotation.z, 2, true)
        SetVehicleOnGroundProperly(vehicle)
    elseif p.action == 'clean' then
        SetVehicleDirtLevel(vehicle, 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
    end
    return result
end

ClientActions.deleteVehicle = function()
    local vehicle = nearbyVehicle()
    if vehicle == 0 then return { ok = false, data = 'Get in or stand next to a vehicle first.' } end
    if not NetworkGetEntityIsNetworked(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
        return { ok = true, data = 'Vehicle deleted.' }
    end
    return Rpc('deleteVehicle', { netId = NetworkGetNetworkIdFromEntity(vehicle) })
end

ClientActions.spectate = function(p)
    local result = Rpc('spectate', { target = p.target })
    if not result.ok then return result end
    closeMenu()
    local ok, message = Spectate.start(result.data)
    if not ok then Toast(message, 'danger') end
    return { ok = ok, data = ok and ('Spectating %s.'):format(result.data.name) or message }
end

ClientActions.stopSpectate = function()
    Spectate.stop()
    return { ok = true, data = 'Stopped spectating.' }
end

ClientActions.close = function()
    closeMenu()
    return { ok = true }
end

-- ---------------------------------------------------------------- panel callbacks

RegisterNUICallback('action', function(body, cb)
    local name = type(body) == 'table' and body.action or nil
    local payload = type(body) == 'table' and type(body.payload) == 'table' and body.payload or {}
    if type(name) ~= 'string' then return cb({ ok = false, data = 'Unknown action.' }) end
    local handler = ClientActions[name]
    local ok, result = pcall(function()
        if handler then return handler(payload) end
        return Rpc(name, payload)
    end)
    if not ok then
        print(('[preston-admin] %s failed: %s'):format(name, tostring(result)))
        result = { ok = false, data = 'Something went wrong in your game. Check F8.' }
    end
    cb(result)
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({})
end)

RegisterNUICallback('warnSeen', function(_, cb)
    warningsShowing = math.max(0, warningsShowing - 1)
    TriggerServerEvent('preston-admin:warnSeen')
    releaseFocus()
    cb({})
end)

-- ---------------------------------------------------------------- what the server sends this player

RegisterNetEvent('preston-admin:toast', function(data)
    if type(data) == 'table' then Toast(data.message, data.tone) end
end)

RegisterNetEvent('preston-admin:warn', function(data)
    warningsShowing = warningsShowing + 1
    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'warn', message = data.message, by = data.by })
end)

RegisterNetEvent('preston-admin:announce', function(data)
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
    SendNUIMessage({ type = 'announce', message = data.message, by = data.by })
end)

local frozen = false

RegisterNetEvent('preston-admin:freeze', function(enabled, by)
    frozen = enabled == true
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, frozen)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then FreezeEntityPosition(vehicle, frozen) end
    Toast(frozen and ('%s froze you.'):format(by) or 'You can move again.', frozen and 'warn' or 'success')
    if not frozen then return end
    CreateThread(function()
        while frozen do
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 75, true)  -- leave vehicle
            Wait(0)
        end
    end)
end)

RegisterNetEvent('preston-admin:heal', function(by)
    if Config.ReviveEvent ~= '' then
        TriggerEvent(Config.ReviveEvent)
    else
        local ped = PlayerPedId()
        if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
            local at = GetEntityCoords(ped)
            NetworkResurrectLocalPlayer(at.x, at.y, at.z, GetEntityHeading(ped), true, false)
            Wait(100)
        end
        ped = PlayerPedId()
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        ClearPedBloodDamage(ped)
        ClearPedTasksImmediately(ped)
    end
    Toast(('%s healed you.'):format(by), 'success')
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/report', 'Send a message to the staff team', {
        { name = 'message', help = 'What happened, and who was involved?' },
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if frozen then FreezeEntityPosition(PlayerPedId(), false) end
end)
