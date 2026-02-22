local isAdmin = false
local god = false
local noclip = false

RegisterCommand('adminhelp', function() TriggerServerEvent('prestonadmin:checkperm') end, false)

RegisterNetEvent('prestonadmin:permgranted')
AddEventHandler('prestonadmin:permgranted', function()
    isAdmin = true
    TriggerEvent('chat:addMessage', { args = { '^2Admin ON - Commands: /kick /ban /tp /bring /god /noclip /car /fix /del /plist' } })
end)

-- KICK
RegisterCommand('kick', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local id = tonumber(args[1])
    local reason = table.concat(args, " ", 2) or "No reason"
    if id then TriggerServerEvent('prestonadmin:kick', id, reason) end
end, false)

-- BAN
RegisterCommand('ban', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local id = tonumber(args[1])
    local reason = table.concat(args, " ", 2) or "No reason"
    if id then TriggerServerEvent('prestonadmin:ban', id, reason) end
end, false)

-- TP to player
RegisterCommand('tp', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local id = tonumber(args[1])
    if id then
        local ped = GetPlayerPed(id)
        local c = GetEntityCoords(ped)
        SetEntityCoords(PlayerPedId(), c.x, c.y, c.z + 1)
    end
end, false)

-- BRING player
RegisterCommand('bring', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local id = tonumber(args[1])
    if id then
        local my = GetEntityCoords(PlayerPedId())
        SetEntityCoords(GetPlayerPed(id), my.x, my.y, my.z + 1)
    end
end, false)

-- GOD toggle
RegisterCommand('god', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    god = not god
    SetEntityInvincible(PlayerPedId(), god)
    TriggerEvent('chat:addMessage', { args = { god and '^2God ON' or '^1God OFF' } })
end, false)

-- NOCLIP toggle
RegisterCommand('noclip', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    noclip = not noclip
    TriggerEvent('chat:addMessage', { args = { noclip and '^2Noclip ON (WASD + space/ctrl)' or '^1Noclip OFF' } })
end, false)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        if noclip then
            local ped = PlayerPedId()
            local x,y,z = table.unpack(GetEntityCoords(ped))
            local speed = 5.0
            if IsControlPressed(0, 32) then z = z + speed end     -- W
            if IsControlPressed(0, 269) then z = z - speed end   -- S
            if IsControlPressed(0, 34) then x = x - speed end    -- A
            if IsControlPressed(0, 35) then x = x + speed end    -- D
            if IsControlPressed(0, 22) then z = z + speed end    -- space
            if IsControlPressed(0, 36) then z = z - speed end    -- ctrl
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        end
    end
end)

-- CAR spawn
RegisterCommand('car', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local m = args[1] or 'adder'
    local h = GetHashKey(m)
    RequestModel(h)
    while not HasModelLoaded(h) do Wait(10) end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local v = CreateVehicle(h, c.x+3, c.y, c.z, GetEntityHeading(ped), true, false)
    SetPedIntoVehicle(ped, v, -1)
end, false)

-- FIX car
RegisterCommand('fix', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v ~= 0 then SetVehicleFixed(v) SetVehicleDeformationFixed(v) end
end, false)

-- DEL car
RegisterCommand('del', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v ~= 0 then DeleteVehicle(v) end
end, false)
