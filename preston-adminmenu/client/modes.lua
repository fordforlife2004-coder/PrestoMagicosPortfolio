-- Noclip, god mode and invisibility. They follow the server-set player state "presAdmin_<mode>", so they
-- only turn on when the server has checked the admin's permission. If a cheat sets that state itself,
-- the server notices, puts it back and logs it.

AdminModes = { noclip = false, god = false, invisible = false }

local CONTROLS_USED_BY_NOCLIP = { 19, 21, 22, 30, 31, 32, 33, 34, 35, 36, 44, 63, 64, 71, 72, 75, 85 }
local noclipEntity

local function applyGod(ped)
    local god = AdminModes.god or AdminModes.noclip
    SetEntityInvincible(ped, god)
    SetPlayerInvincible(PlayerId(), god)
end

-- Makes the admin's ped match the current modes (also used when spectating ends).
function ApplyAdminModes()
    local ped = PlayerPedId()
    applyGod(ped)
    if Spectate.active then return end -- spectating keeps the ped hidden until it ends
    if AdminModes.invisible then
        SetEntityVisible(ped, false, false)
        SetEntityAlpha(ped, 140, false)
    else
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
    end
end

local function stopNoclip()
    local ped = PlayerPedId()
    for _, entity in ipairs({ ped, noclipEntity }) do
        if entity and DoesEntityExist(entity) then
            FreezeEntityPosition(entity, false)
            SetEntityCollision(entity, true, true)
            SetEntityInvincible(entity, AdminModes.god)
        end
    end
    noclipEntity = nil
end

local function noclipLoop()
    while AdminModes.noclip do
        if not Spectate.active then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local entity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped
            if noclipEntity and noclipEntity ~= entity and DoesEntityExist(noclipEntity) then
                FreezeEntityPosition(noclipEntity, false)
                SetEntityCollision(noclipEntity, true, true)
            end
            noclipEntity = entity

            for _, control in ipairs(CONTROLS_USED_BY_NOCLIP) do DisableControlAction(0, control, true) end
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, false, false)
            SetEntityInvincible(entity, true)

            local speed = Config.NoclipSpeed.normal
            if IsDisabledControlPressed(0, 21) then speed = Config.NoclipSpeed.fast end -- Shift
            if IsDisabledControlPressed(0, 19) then speed = Config.NoclipSpeed.slow end -- Alt

            -- Move where the camera points: W/S forward and back, A/D sideways, Space/Ctrl up and down.
            local rotation = GetGameplayCamRot(2)
            local yaw, pitch = math.rad(rotation.z), math.rad(rotation.x)
            local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
            local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
            local move = vector3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) or IsDisabledControlPressed(0, 71) then move = move + forward end
            if IsDisabledControlPressed(0, 33) or IsDisabledControlPressed(0, 72) then move = move - forward end
            if IsDisabledControlPressed(0, 34) or IsDisabledControlPressed(0, 63) then move = move - right end
            if IsDisabledControlPressed(0, 35) or IsDisabledControlPressed(0, 64) then move = move + right end
            if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end

            local step = speed * GetFrameTime() * 30.0
            local at = GetEntityCoords(entity) + move * step
            SetEntityCoordsNoOffset(entity, at.x, at.y, at.z, true, true, true)
            SetEntityHeading(entity, rotation.z)
        end
        Wait(0)
    end
    stopNoclip()
end

local function invisibleLoop()
    while AdminModes.invisible do
        -- Hidden from everyone else, but the admin still sees a see-through version of themselves.
        if not Spectate.active then SetEntityLocallyVisible(PlayerPedId()) end
        Wait(0)
    end
end

local function godLoop()
    while AdminModes.god do
        applyGod(PlayerPedId()) -- keeps it on after respawning (a new ped)
        Wait(500)
    end
end

local LOOPS = { noclip = noclipLoop, invisible = invisibleLoop, god = godLoop }
local LABELS = { noclip = 'Noclip', god = 'God mode', invisible = 'Invisible' }

AddStateBagChangeHandler(nil, nil, function(bagName, key, value)
    local mode = key:match('^presAdmin_(%a+)$')
    if not mode or AdminModes[mode] == nil then return end
    if GetPlayerFromStateBagName(bagName) ~= PlayerId() then return end
    local enabled = value == true
    if AdminModes[mode] == enabled then return end
    AdminModes[mode] = enabled
    -- The change handler runs before the value is stored, so wait a tick before acting on it.
    SetTimeout(0, function()
        ApplyAdminModes()
        if enabled then CreateThread(LOOPS[mode]) end
        Toast(('%s %s.'):format(LABELS[mode], enabled and 'on' or 'off'), enabled and 'success' or 'info')
        SendNUIMessage({ type = 'modes', modes = AdminModes })
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    AdminModes.noclip, AdminModes.god, AdminModes.invisible = false, false, false
    stopNoclip()
    ApplyAdminModes()
end)
