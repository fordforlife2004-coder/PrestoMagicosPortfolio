-- The driver's keys and control panel. Each key press is played in the driver's own game straight
-- away (so it feels instant) and sent to the server, which checks it and shares it with everyone.
-- If the server refuses, the driver's game goes back to the approved state.

local E = PrestonEls

local nextSeq = 0
local hudHidden = GetResourceKvpInt('hudHidden') == 1
local settings -- ELS settings of DrivingVehicle

local KEY_NAMES = { LMENU = 'L-Alt', RMENU = 'R-Alt', LSHIFT = 'Shift', LCONTROL = 'Ctrl', SPACE = 'Space', RETURN = 'Enter' }

-- The key a player has bound to a command (they may have changed it), for the panel.
local function keyFor(command, default)
    local ok, button = pcall(function()
        return GetControlInstructionalButton(0, GetHashKey(command) | 0x80000000, true)
    end)
    if ok and type(button) == 'string' and button:sub(1, 2) == 't_' then return button:sub(3) end
    return KEY_NAMES[default] or default
end

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function click()
    if Config.ClickSounds then PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
end

function UpdateHud()
    local vehicle = DrivingVehicle
    if vehicle == 0 or not Config.ShowHud or hudHidden then
        SendNUIMessage({ type = 'hud', visible = false })
        return
    end
    local state = ElsState(vehicle)
    local tone = settings.tones[state.tone] or settings.tones[1]
    local pattern = Config.Patterns[state.pattern] or Config.Patterns[1]
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(model)
    SendNUIMessage({
        type = 'hud',
        visible = true,
        position = Config.HudPosition,
        vehicle = (label ~= 'NULL' and label ~= '') and label or model,
        lights = state.lights,
        siren = state.siren,
        horn = state.horn,
        tone = tone and tone.label or '',
        pattern = settings.lights == 'extras' and pattern.label or nil,
        keys = {
            lights = keyFor('elslights', Config.Keys.lights),
            siren = keyFor('elssiren', Config.Keys.siren),
            tone = keyFor('elstone', Config.Keys.tone),
            pattern = keyFor('elspattern', Config.Keys.pattern),
            horn = keyFor('+elshorn', Config.Keys.horn),
        },
    })
end

-- Plays a change on a vehicle now and asks the server to share it.
local function send(vehicle, vehicleSettings, change)
    local new = E.applyChange(ElsState(vehicle), change, vehicleSettings, #Config.Patterns)
    if not new then return false end
    if not NetworkGetEntityIsNetworked(vehicle) then
        ApplyEls(vehicle, new) -- a vehicle only this game knows about: nobody else to tell
        return true
    end
    nextSeq = nextSeq + 1
    new.seq, new.by = nextSeq, GetPlayerServerId(PlayerId())
    RememberRequest(vehicle, nextSeq)
    ApplyEls(vehicle, new)
    TriggerServerEvent('preston-els:set', NetworkGetNetworkIdFromEntity(vehicle), change, nextSeq)
    return true
end

local function change(build, withClick)
    if DrivingVehicle == 0 then return end
    local state = ElsState(DrivingVehicle)
    if send(DrivingVehicle, settings, build(state)) then
        if withClick then click() end
        UpdateHud()
    end
end

RegisterCommand('elslights', function()
    change(function(s) return { lights = not s.lights } end, true)
end, false)

RegisterCommand('elssiren', function()
    change(function(s) return { siren = not s.siren } end, true)
end, false)

RegisterCommand('elstone', function()
    change(function(s) return { tone = s.tone % #settings.tones + 1 } end, true)
end, false)

RegisterCommand('elspattern', function()
    if DrivingVehicle ~= 0 and settings.lights ~= 'extras' then
        notify('This vehicle uses its own built-in light pattern.')
        return
    end
    change(function(s) return { pattern = s.pattern % #Config.Patterns + 1 } end, true)
end, false)

RegisterCommand('+elshorn', function()
    change(function() return { horn = true } end, false)
end, false)

RegisterCommand('-elshorn', function()
    if DrivingVehicle ~= 0 and ElsState(DrivingVehicle).horn then
        change(function() return { horn = false } end, false)
    end
end, false)

RegisterKeyMapping('elslights', 'ELS: emergency lights on/off', 'keyboard', Config.Keys.lights)
RegisterKeyMapping('elssiren', 'ELS: siren on/off', 'keyboard', Config.Keys.siren)
RegisterKeyMapping('elstone', 'ELS: next siren tone', 'keyboard', Config.Keys.tone)
RegisterKeyMapping('elspattern', 'ELS: next light pattern', 'keyboard', Config.Keys.pattern)
RegisterKeyMapping('+elshorn', 'ELS: air horn (hold)', 'keyboard', Config.Keys.horn)

RegisterCommand('elshud', function()
    hudHidden = not hudHidden
    SetResourceKvpInt('hudHidden', hudHidden and 1 or 0)
    UpdateHud()
    notify(hudHidden and 'ELS panel hidden. Type /elshud to show it.' or 'ELS panel shown.')
end, false)

RegisterCommand('elshelp', function()
    local lines = {
        ('%s lights   %s siren   %s next tone   %s next pattern   hold %s air horn'):format(
            keyFor('elslights', Config.Keys.lights), keyFor('elssiren', Config.Keys.siren), keyFor('elstone', Config.Keys.tone),
            keyFor('elspattern', Config.Keys.pattern), keyFor('+elshorn', Config.Keys.horn)),
        '/elshud shows or hides the panel. Change keys in Settings > Key Bindings > FiveM.',
    }
    for _, line in ipairs(lines) do TriggerEvent('chat:addMessage', { args = { 'ELS', line } }) end
end, false)

-- The server said no: go back to what it approved.
RegisterNetEvent('preston-els:refused', function(netId, reason)
    local vehicle = NetworkGetEntityFromNetworkId(netId or -1)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        RememberRequest(vehicle, 0)
        ApplyEls(vehicle, Entity(vehicle).state.presEls)
        UpdateHud()
    end
    if reason == 'no permission' then notify("You aren't allowed to use emergency lights.") end
end)

-- Watches whether the player is driving an ELS vehicle: shows the panel, frees the keys from the
-- game's own actions, and turns the siren off when they get out.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local driving = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and IsElsVehicle(vehicle)
        if driving then
            if DrivingVehicle ~= vehicle then
                DrivingVehicle, settings = vehicle, ElsSettings(vehicle)
                UpdateHud()
            end
            for _, control in ipairs(Config.DisabledControls) do DisableControlAction(0, control, true) end
            Wait(0)
        else
            if DrivingVehicle ~= 0 then
                local left, leftSettings = DrivingVehicle, settings
                DrivingVehicle = 0
                local state = ElsState(left)
                if DoesEntityExist(left) and (state.horn or (Config.SirenOffOnExit and state.siren)) then
                    send(left, leftSettings, Config.SirenOffOnExit and { siren = false, horn = false } or { horn = false })
                end
                UpdateHud()
            end
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        TriggerEvent('chat:addSuggestion', '/elshelp', 'Show the ELS keys')
        TriggerEvent('chat:addSuggestion', '/elshud', 'Show or hide the ELS control panel')
    end
end)
