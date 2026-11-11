-- Prest_Sector Radar, in the officer's game: reads the road around a radar-equipped car, keeps the
-- display up to date, sends new plates to the server to be checked, and handles the keys and the remote.

local R = Radar
local EVENT = R.EVENT
local CAD = 'Prest_Sector-CAD'
local SAVE = 'prestSectorRadar:settings'
local STATE = 'prestSectorRadar'
local P = Config.PlateReader

local settings = R.cleanSettings(nil, Config)
local shown = true          -- /radar hides and shows it
local active = false        -- on screen now: in a radar car, allowed, and not hidden
local remoteOpen = false
local locks = {}            -- [antenna] = { target, fast } frozen by the lock key
local over = {}             -- [antenna] = { [car] = true }: cars that set the alarm off and are still over the limit
local plates = {}           -- [camera] = { plate, style, status, reasons, vehicle, owner, locked }
local styles = {}           -- [plate] = its plate style, from when it was read
local results = {}          -- [plate] = the server's answer
local checkedAt = {}        -- [plate] = game time it was last sent to be checked
local pending = {}          -- [request id] = { camera, plate }
local nextRequest = 0
local lastHit = nil         -- the last plate that was a hit, for "open in CAD"
local lastSent = nil        -- the last display update, so only changes are sent
local current = {}          -- [antenna] = { target, fast } from the last reading

-- ------------------------------------------------------------------ small helpers

local function notify(text, tone)
    BeginTextCommandThefeedPost('STRING')
    -- The game cuts each piece of text at 99 characters, so long ones go in pieces.
    for i = 1, #text, 99 do AddTextComponentSubstringPlayerName(text:sub(i, i + 98)) end
    EndTextCommandThefeedPostTicker(tone == 'error', true)
end

RegisterNetEvent(EVENT .. 'notify', function(text, tone)
    if type(text) == 'string' then notify(text, tone) end
end)

local function beep(kind)
    if settings.volume > 0 then SendNUIMessage({ type = 'beep', kind = kind, volume = settings.volume }) end
end

local function save()
    SetResourceKvp(SAVE, json.encode(settings))
end

local function load()
    local raw = GetResourceKvpString(SAVE)
    local ok, saved = pcall(function() return raw and json.decode(raw) end)
    settings = R.cleanSettings(ok and saved or nil, Config)
end

local function allowed() return LocalPlayer.state[STATE] == true end

local function cadRunning() return GetResourceState(CAD) == 'started' end

-- The radar car the player sits in the front of, or nil.
local radarModels = {}
for _, name in ipairs(Config.Vehicles.models or {}) do radarModels[GetHashKey(name)] = true end

local function radarVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return nil end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped and GetPedInVehicleSeat(vehicle, 0) ~= ped then return nil end
    if Config.Vehicles.emergencyClass and GetVehicleClass(vehicle) == 18 then return vehicle end
    if radarModels[GetEntityModel(vehicle)] then return vehicle end
    return nil
end

local function plateText(vehicle)
    return ((GetVehicleNumberPlateText(vehicle) or ''):match('^%s*(.-)%s*$'))
end

-- ------------------------------------------------------------------ the display

local function antennaOut(name, reading)
    local a = settings[name]
    local lock = locks[name]
    local target, fast = reading and reading.target, reading and reading.fast
    if lock then target, fast = lock.target, lock.fast end
    return {
        on = a.on, mode = a.mode, locked = lock ~= nil,
        target = target and target.speed or nil, fast = fast and fast.speed or nil,
        over = ((fast or target) and (fast or target).speed >= settings.fastLimit) or false,
    }
end

local function plateOut(camera)
    local p = plates[camera]
    if not p then return nil end
    return { plate = p.plate, style = p.style, status = p.status, reasons = p.reasons, vehicle = p.vehicle, owner = p.owner, locked = p.locked }
end

local function send(patrolSpeed, readings)
    local update = {
        type = 'update', units = Config.Units, patrol = patrolSpeed, limit = settings.fastLimit, fastLock = settings.fastLock,
        front = antennaOut('front', readings.front), rear = antennaOut('rear', readings.rear),
        platesOn = settings.plates, plates = { front = plateOut('front'), rear = plateOut('rear') },
        canOpenCad = lastHit ~= nil and cadRunning(),
    }
    local text = json.encode(update)
    if text ~= lastSent then
        lastSent = text
        SendNUIMessage(update)
    end
end

local function sendSettings()
    SendNUIMessage({ type = 'settings', settings = settings, units = Config.Units })
end

local function setVisible(visible)
    if active == visible then return end
    active = visible
    lastSent = nil
    SendNUIMessage({ type = 'show', visible = visible })
    if not visible and remoteOpen then
        remoteOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ type = 'remote', open = false })
    end
end

-- ------------------------------------------------------------------ plates

local function applyResult(camera, result)
    local p = plates[camera]
    if result.status == 'hit' then
        -- A hit takes the camera's screen even if it has moved on to another car since.
        p = { plate = result.plate, style = styles[result.plate] or 0 }
        plates[camera] = p
        p.locked = P.lockOnHit == true
        lastHit = result.plate
        beep('hit')
        notify(('Plate reader hit: %s. %s'):format(result.plate, table.concat(result.reasons, ' ')), 'error')
    elseif not p or p.plate ~= result.plate then
        return
    end
    p.status, p.reasons, p.vehicle, p.owner = result.status, result.reasons, result.vehicle, result.owner
end

RegisterNetEvent(EVENT .. 'result', function(reqId, result)
    local req = pending[reqId]
    pending[reqId] = nil
    if not req or type(result) ~= 'table' then return end
    if result.error then
        -- Not checked (the server was busy, for example): try this plate again in 10 seconds.
        checkedAt[req.plate] = GetGameTimer() - P.repeatSeconds * 1000 + 10000
        return
    end
    if result.plate ~= req.plate then return end
    results[req.plate] = result
    applyResult(req.camera, result)
end)

local function check(camera, plate)
    local now = GetGameTimer()
    local last = checkedAt[plate]
    if last and now - last < P.repeatSeconds * 1000 then
        local known = results[plate]
        if known and plates[camera] and plates[camera].plate == plate then
            local p = plates[camera]
            p.status, p.reasons, p.vehicle, p.owner = known.status, known.reasons, known.vehicle, known.owner
        end
        return
    end
    checkedAt[plate] = now
    results[plate] = nil
    nextRequest = nextRequest + 1
    pending[nextRequest] = { camera = camera, plate = plate }
    TriggerServerEvent(EVENT .. 'check', nextRequest, camera, plate)
end

local function readPlates(vehicle, patrol, cars)
    for camera, dir in pairs(R.ANTENNAS) do
        local current = plates[camera]
        if not (current and current.locked) then
            local seen = R.readCamera(patrol, cars, dir, P)
            if seen and HasEntityClearLosToEntity(vehicle, seen.id, 17) then
                local text = plateText(seen.id)
                local key = R.plateKey(text)
                if key then
                    if not current or current.plate ~= key then
                        styles[key] = R.plateStyle(GetVehicleNumberPlateTextIndex(seen.id))
                        plates[camera] = { plate = key, style = styles[key], status = 'reading', reasons = {} }
                    end
                    check(camera, key)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ reading the road

local function nearbyCars(vehicle, origin)
    local reach = math.max(Config.Radar.range, P.range) + 10.0
    local cars = {}
    for _, other in ipairs(GetGamePool('CVehicle')) do
        if other ~= vehicle then
            local pos = GetEntityCoords(other)
            local dx, dy = pos.x - origin.x, pos.y - origin.y
            if dx * dx + dy * dy <= reach * reach then
                cars[#cars + 1] = { id = other, pos = pos, vel = GetEntityVelocity(other), speed = GetEntitySpeed(other) }
            end
        end
    end
    return cars
end

-- Forgets the cars that set an antenna's alarm off once they've slowed under the limit or left its
-- beam, so each car sounds the alarm once while it stays over the limit.
local function forgetSlowed(name, dir, patrol, byId)
    local seen = over[name] or {}
    for id in pairs(seen) do
        local car = byId[id]
        if not car or R.round(R.toUnits(car.speed, Config.Units)) < settings.fastLimit
            or not R.inBeam(R.relative(patrol.pos, patrol.forward, car.pos), dir, Config.Radar) then
            seen[id] = nil
        end
    end
    over[name] = seen
    return seen
end

local function scan(vehicle)
    local patrol = { id = vehicle, pos = GetEntityCoords(vehicle), forward = GetEntityForwardVector(vehicle) }
    local cars = nearbyCars(vehicle, patrol.pos)
    local byId = {}
    for _, car in ipairs(cars) do byId[car.id] = car end
    local readings = {}
    for name, dir in pairs(R.ANTENNAS) do
        local a = settings[name]
        if a.on then
            local target, fast = R.readAntenna(patrol, cars, dir, a.mode, Config.Radar, Config.Units, Config.Radar.minSpeed)
            readings[name] = { target = target, fast = fast }
            local seen = forgetSlowed(name, dir, patrol, byId)
            local top = fast or target
            if not locks[name] and top and top.speed >= settings.fastLimit and not seen[top.id] then
                seen[top.id] = true
                if settings.fastLock then
                    locks[name] = { target = target, fast = fast }
                    beep('lock')
                else
                    beep('fast')
                end
            end
        end
    end
    current = readings
    if settings.plates then readPlates(vehicle, patrol, cars) end
    send(R.round(R.toUnits(GetEntitySpeed(vehicle), Config.Units)), readings)
end

CreateThread(function()
    while true do
        local vehicle = shown and radarVehicle() or nil
        setVisible(vehicle ~= nil and allowed())
        if active then
            scan(vehicle)
            Wait(math.max(50, Config.Radar.updateMs))
        else
            Wait(500)
        end
    end
end)

-- ------------------------------------------------------------------ what the keys do

local function lockAntenna(name)
    if not active or not settings[name].on then return end
    if locks[name] then
        locks[name] = nil
    else
        -- Freeze what's on screen now.
        local reading = current[name]
        if not reading or not reading.target then return end
        locks[name] = { target = reading.target, fast = reading.fast }
    end
    beep('lock')
end

local function lockPlates()
    if not active then return end
    local any = false
    for _, p in pairs(plates) do any = any or p.locked end
    for _, p in pairs(plates) do p.locked = not any end
    beep('lock')
end

-- Clears the locks and the plates. A speeder that already set the alarm off doesn't lock again at once.
local function reset()
    if not active then return end
    locks, plates, current = {}, {}, {}
    lastSent = nil
    beep('lock')
end

local function openCad()
    if not allowed() then return end
    if not lastHit then return notify('There\'s no plate reader hit to open.', 'error') end
    if not cadRunning() then return notify('Prest_Sector CAD isn\'t running on this server.', 'error') end
    local ok = pcall(function() return exports[CAD]:OpenPlate(lastHit) end)
    if not ok then notify('The CAD couldn\'t open that plate.', 'error') end
end

local function openRemote()
    if not active then
        if not allowed() then return notify('You aren\'t allowed to use the radar.', 'error') end
        return notify('Get in the front of a radar-equipped car first.', 'error')
    end
    remoteOpen = true
    SetNuiFocus(true, true)
    sendSettings()
    SendNUIMessage({ type = 'remote', open = true })
end

local function closeRemote()
    if not remoteOpen then return end
    remoteOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'remote', open = false })
end

RegisterCommand(Config.Command, function()
    shown = not shown
    if shown and not allowed() then notify('You aren\'t allowed to use the radar.', 'error') end
end, false)
RegisterCommand(Config.RemoteCommand, openRemote, false)
RegisterCommand('radarlockfront', function() lockAntenna('front') end, false)
RegisterCommand('radarlockrear', function() lockAntenna('rear') end, false)
RegisterCommand('radarlockplates', lockPlates, false)
RegisterCommand('radarreset', reset, false)
RegisterCommand('radaropencad', openCad, false)

local K = Config.Keys
RegisterKeyMapping(Config.Command, 'Radar: show or hide', 'keyboard', K.toggle or '')
RegisterKeyMapping(Config.RemoteCommand, 'Radar: open the remote', 'keyboard', K.remote or '')
RegisterKeyMapping('radarlockfront', 'Radar: lock or unlock the front antenna', 'keyboard', K.lockFront or '')
RegisterKeyMapping('radarlockrear', 'Radar: lock or unlock the rear antenna', 'keyboard', K.lockRear or '')
RegisterKeyMapping('radarlockplates', 'Radar: lock or unlock the plate reader', 'keyboard', K.lockPlates or '')
RegisterKeyMapping('radarreset', 'Radar: clear all locks', 'keyboard', K.reset or '')
RegisterKeyMapping('radaropencad', 'Radar: open the last plate hit in the CAD', 'keyboard', K.openCad or '')

TriggerEvent('chat:addSuggestion', '/' .. Config.HotlistCommand, 'Plate reader hotlist', {
    { name = 'add | remove', help = 'add PLATE reason, remove PLATE, or nothing to list it' },
})

-- ------------------------------------------------------------------ the display and remote talking back

RegisterNUICallback('ready', function(_, cb)
    lastSent = nil
    sendSettings()
    SendNUIMessage({ type = 'show', visible = active })
    cb({})
end)

RegisterNUICallback('settings', function(data, cb)
    if type(data) == 'table' then
        local merged = {}
        for k, v in pairs(settings) do merged[k] = v end
        for _, k in ipairs({ 'front', 'rear', 'plates', 'fastLimit', 'fastLock', 'volume', 'scale', 'pos' }) do
            if data[k] ~= nil then merged[k] = data[k] end
        end
        if data.resetPos then merged.pos = nil end
        settings = R.cleanSettings(merged, Config)
        if not settings.front.on then locks.front = nil end
        if not settings.rear.on then locks.rear = nil end
        save()
        lastSent = nil
    end
    cb(settings)
end)

RegisterNUICallback('action', function(data, cb)
    local what = type(data) == 'table' and data.action or nil
    if what == 'lockFront' then lockAntenna('front')
    elseif what == 'lockRear' then lockAntenna('rear')
    elseif what == 'lockPlates' then lockPlates()
    elseif what == 'reset' then reset()
    elseif what == 'openCad' then openCad()
    end
    cb({})
end)

RegisterNUICallback('close', function(_, cb)
    closeRemote()
    cb({})
end)

-- ------------------------------------------------------------------ starting and stopping

exports('IsActive', function() return active end)
exports('GetLastHit', function() return lastHit end)

load()
TriggerServerEvent(EVENT .. 'hello')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if remoteOpen then SetNuiFocus(false, false) end
end)
