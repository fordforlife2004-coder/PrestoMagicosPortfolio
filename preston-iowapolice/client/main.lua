-- The player's side: each department's spawn command, /iowaskin and /iowahelp ask the server, and
-- IowaDress applies a department's look once the server has approved it.

local I = IowaPolice

local LIVERY_MOD = 48

-- GTA notifications take at most 99 characters per piece of text, so longer ones go in pieces.
local function notify(message, tone)
    BeginTextCommandThefeedPost(#message > 99 and 'CELL_EMAIL_BCON' or 'STRING')
    for i = 1, #message, 99 do AddTextComponentSubstringPlayerName(message:sub(i, i + 98)) end
    EndTextCommandThefeedPostTicker(tone == 'error', false)
end

-- What kind of vehicle a model really is, to catch a department whose vehicleType doesn't match.
local function vehicleTypeOf(hash)
    if IsThisModelAHeli(hash) then return 'heli' end
    if IsThisModelAPlane(hash) then return 'plane' end
    if IsThisModelABoat(hash) or IsThisModelAJetski(hash) then return 'boat' end
    if IsThisModelABike(hash) or IsThisModelABicycle(hash) then return 'bike' end
    return 'automobile'
end

local function setLivery(vehicle, number)
    if GetVehicleLiveryCount(vehicle) >= number then
        SetVehicleLivery(vehicle, number - 1)
        return
    end
    SetVehicleModKit(vehicle, 0)
    if GetNumVehicleMods(vehicle, LIVERY_MOD) >= number then SetVehicleMod(vehicle, LIVERY_MOD, number - 1, false) end
end

-- Paint, plate style, livery and extras for a department.
function IowaDress(vehicle, department)
    if department.colors then
        ClearVehicleCustomPrimaryColour(vehicle)
        ClearVehicleCustomSecondaryColour(vehicle)
        SetVehicleColours(vehicle, department.colors[1], department.colors[2])
    end
    if department.pearl or department.wheels then
        local pearl, wheels = GetVehicleExtraColours(vehicle)
        SetVehicleExtraColours(vehicle, department.pearl or pearl, department.wheels or wheels)
    end
    if department.plateStyle then SetVehicleNumberPlateTextIndex(vehicle, department.plateStyle) end
    if department.livery then setLivery(vehicle, department.livery) end
    if department.extras then
        -- Changing extras repairs all damage unless this is off, which would make /iowaskin a free repair.
        SetVehicleAutoRepairDisabled(vehicle, true)
        for id = 1, 20 do
            if DoesExtraExist(vehicle, id) then
                local want = department.extras == 'all' or department.extras[id]
                if want ~= nil then SetVehicleExtra(vehicle, id, not want) end -- the last value means "disable"
            end
        end
    end
    SetVehicleDirtLevel(vehicle, 0.0)
end

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

-- The server approved a spawn (seat = true: get in first) or /iowaskin, and set the plate.
RegisterNetEvent('preston-iowa:dress', function(netId, key, seat, message)
    local department = Config.Departments[key]
    if not department or type(netId) ~= 'number' then return end
    local vehicle = waitForVehicle(netId, seat and 10 or 2) -- a new add-on model can take a while to load
    if not vehicle then
        if seat then TriggerServerEvent('preston-iowa:seatFailed', netId) end
        return notify(seat and ("The %s vehicle didn't arrive. Is %s installed on the server?"):format(department.label, department.model)
            or "Couldn't find the vehicle. Try /iowaskin again.", 'error')
    end
    if seat then
        local ped = PlayerPedId()
        for _ = 1, 20 do
            SetPedIntoVehicle(ped, vehicle, -1)
            if GetVehiclePedIsIn(ped, false) == vehicle then break end
            Wait(100)
        end
    end
    if not takeControl(vehicle) then return notify("Couldn't style the vehicle. Try /iowaskin.", 'error') end
    IowaDress(vehicle, department)
    if type(message) == 'string' then notify(message, 'success') end
end)

RegisterNetEvent('preston-iowa:notify', function(message, tone)
    if type(message) == 'string' then notify(message, tone) end
end)

-- ---------------------------------------------------------------- commands

for key, department in pairs(Config.Departments) do
    RegisterCommand(department.command, function(_, args)
        local hash = GetHashKey(department.model)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            return notify(('The %s vehicle (%s) is not installed on this server.'):format(department.label, department.model), 'error')
        end
        local configured, actual = department.vehicleType or 'automobile', vehicleTypeOf(hash)
        if configured ~= actual then
            return notify(('Config problem: %s is a %s, but the %s department says vehicleType = %s.'):format(
                department.model, actual, department.label, configured), 'error')
        end
        TriggerServerEvent('preston-iowa:spawn', key, args[1])
    end, false)
end

-- /iowaskin [department] [unit], /iowaskin [unit] for the default department, or /iowaskin [unit] [department].
RegisterCommand('iowaskin', function(_, args)
    local department, unit = args[1], args[2]
    if department and not I.findDepartment(Config, department) and tonumber(department) then
        if unit and I.findDepartment(Config, unit) then
            department, unit = unit, department
        else
            department, unit = nil, department
        end
    end
    TriggerServerEvent('preston-iowa:skin', department, unit)
end, false)

RegisterCommand('iowahelp', function()
    local lines = {}
    for _, department in pairs(Config.Departments) do
        lines[#lines + 1] = ('/%s [unit]  spawn a %s vehicle'):format(department.command, department.label)
    end
    table.sort(lines)
    lines[#lines + 1] = '/iowaskin [department] [unit]  style the car you are driving'
    for _, line in ipairs(lines) do TriggerEvent('chat:addMessage', { args = { 'Iowa Police', line } }) end
end, false)

CreateThread(function()
    for _, department in pairs(Config.Departments) do
        TriggerEvent('chat:addSuggestion', '/' .. department.command, 'Spawn a ' .. department.label .. ' vehicle',
            { { name = 'unit', help = 'Unit number for the plate, like 101 (optional)' } })
    end
    TriggerEvent('chat:addSuggestion', '/iowaskin', 'Style the car you are driving', {
        { name = 'department', help = 'isp or sheriff (optional)' }, { name = 'unit', help = 'Unit number (optional)' },
    })
    TriggerEvent('chat:addSuggestion', '/iowahelp', 'List the Iowa Police commands')
end)
