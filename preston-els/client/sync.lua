-- Plays ELS on every vehicle near this player: built-in lights, extras light bars, siren tones and
-- the air horn, from the state the server approved for each vehicle ("presEls"). Each game runs the
-- sounds and flashing itself, so only small state changes travel over the network.

local E = PrestonEls

local MODEL_NAMES = {} -- [model hash] = spawn name, for vehicles listed in Config.Vehicles
for name in pairs(Config.Vehicles) do MODEL_NAMES[GetHashKey(name)] = name end

local active = {}  -- [vehicle] = { state, settings, toneSound, toneName, hornSound, lightsSince, frame }
local sentSeq = {} -- [vehicle] = the number of the last request this player sent for it
local myServerId = GetPlayerServerId(PlayerId())

DrivingVehicle = 0 -- the ELS vehicle this player is driving (kept up to date by client/main.lua)

function ElsSettings(vehicle)
    return E.settingsFor(Config, MODEL_NAMES[GetEntityModel(vehicle)])
end

function IsElsVehicle(vehicle)
    if MODEL_NAMES[GetEntityModel(vehicle)] then return true end
    return Config.AllEmergencyVehicles and GetVehicleClass(vehicle) == 18
end

-- What this game is currently playing on a vehicle (off if nothing).
function ElsState(vehicle)
    local a = active[vehicle]
    return a and a.state or E.normalize(nil)
end

function RememberRequest(vehicle, seq)
    sentSeq[vehicle] = seq
end

-- A state the server sent back for an older request of ours, while a newer one is on its way.
local function isOldEcho(vehicle, state)
    return type(state) == 'table' and state.by == myServerId and (state.seq or 0) < (sentSeq[vehicle] or 0)
end

local function stopSound(id)
    if id then
        StopSound(id)
        ReleaseSoundId(id)
    end
end

local function playSound(name, vehicle)
    local id = GetSoundId()
    PlaySoundFromEntity(id, name, vehicle, 0, false, 0)
    return id
end

-- Turns a vehicle's light bar extras on or off. on = { [extra number] = true }.
local function setExtras(vehicle, settings, on)
    for _, extra in ipairs(settings.extras) do
        if DoesExtraExist(vehicle, extra) then
            SetVehicleExtra(vehicle, extra, not on[extra]) -- the native's last value means "disable"
        end
    end
end

-- Makes a vehicle look and sound like the given state. Safe to call again with the same state.
function ApplyEls(vehicle, state)
    if not DoesEntityExist(vehicle) then return end
    state = E.normalize(state)
    local a = active[vehicle]
    local first = a == nil
    if first then
        a = { settings = ElsSettings(vehicle), state = E.normalize(nil) }
        active[vehicle] = a
        SetVehicleHasMutedSirens(vehicle, true) -- the siren sounds come from here instead
        if a.settings.lights == 'extras' then
            SetVehicleAutoRepairDisabled(vehicle, true) -- changing extras would otherwise repair damage
        end
    end
    local was = a.state
    a.state = state

    if a.settings.nativeLights and IsVehicleSirenOn(vehicle) ~= state.lights then
        SetVehicleSiren(vehicle, state.lights)
    end

    if a.settings.lights == 'extras' then
        if state.lights and (first or not was.lights or was.pattern ~= state.pattern) then
            a.lightsSince, a.frame = GetGameTimer(), nil -- the flashing loop below takes it from here
        elseif not state.lights and (first or was.lights) then
            setExtras(vehicle, a.settings, {})
        end
    end

    local tone = E.toneSound(state, a.settings)
    if tone ~= a.toneName then
        stopSound(a.toneSound)
        a.toneSound, a.toneName = nil, nil
        if tone then a.toneSound, a.toneName = playSound(tone, vehicle), tone end
    end

    if state.horn and not a.hornSound then
        a.hornSound = playSound(Config.Horn, vehicle)
    elseif not state.horn and a.hornSound then
        stopSound(a.hornSound)
        a.hornSound = nil
    end
end

-- Stops this game's sounds for a vehicle (it left, went out of range, or the resource stopped).
local function forget(vehicle)
    local a = active[vehicle]
    if not a then return end
    stopSound(a.toneSound)
    stopSound(a.hornSound)
    active[vehicle], sentSeq[vehicle] = nil, nil
end

local function inRange(vehicle)
    return #(GetEntityCoords(vehicle) - GetEntityCoords(PlayerPedId())) <= Config.SyncDistance
end

-- A vehicle's ELS state changed somewhere (usually the server approving a driver's key press).
AddStateBagChangeHandler('presEls', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end -- not near us; the scan picks it up later
    if isOldEcho(vehicle, value) then return end
    if value == nil then
        if active[vehicle] and vehicle ~= DrivingVehicle then
            ApplyEls(vehicle, nil)
            forget(vehicle)
        end
        return
    end
    if inRange(vehicle) then ApplyEls(vehicle, value) end
end)

-- Every half second: pick up ELS vehicles that came into range and let go of ones that left.
CreateThread(function()
    while true do
        local seen = {}
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            local state = Entity(vehicle).state.presEls
            if vehicle == DrivingVehicle and active[vehicle] then
                seen[vehicle] = true -- the driver's own game is ahead of the server; don't undo it
            elseif state ~= nil and inRange(vehicle) then
                seen[vehicle] = true
                if not isOldEcho(vehicle, state) then ApplyEls(vehicle, state) end
            end
        end
        for vehicle in pairs(active) do
            if not seen[vehicle] then forget(vehicle) end
        end
        Wait(500)
    end
end)

-- Flashes extras light bars. Runs every frame only while one is flashing nearby.
CreateThread(function()
    while true do
        local flashing = false
        local now = GetGameTimer()
        for vehicle, a in pairs(active) do
            if a.settings.lights == 'extras' and a.state.lights and DoesEntityExist(vehicle) then
                flashing = true
                local pattern = Config.Patterns[a.state.pattern] or Config.Patterns[1]
                local index, frame = E.patternFrame(pattern, now - (a.lightsSince or now))
                if index ~= a.frame then
                    a.frame = index
                    setExtras(vehicle, a.settings, E.extrasForFrame(frame, a.settings.extras))
                end
            end
        end
        Wait(flashing and 0 or 250)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for vehicle, a in pairs(active) do
        if DoesEntityExist(vehicle) then
            if a.settings.nativeLights then SetVehicleSiren(vehicle, false) end
            if a.settings.lights == 'extras' then setExtras(vehicle, a.settings, {}) end
            SetVehicleHasMutedSirens(vehicle, false)
        end
        forget(vehicle)
    end
end)
