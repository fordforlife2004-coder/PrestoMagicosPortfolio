ensure preston-adminmenu
add_ace group.admin admin.menu allow
add_principal identifier.license:YOUR_LICENSE group.admin

fx_version 'cerulean'
game 'gta5'

author 'Preston D'
description 'Preston Admin Menu - Portfolio 2026'
version '1.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

Config = {}
Config.AdminPerm = "admin.menu"

RegisterServerEvent('prestonadmin:checkperm')
AddEventHandler('prestonadmin:checkperm', function()
    local src = source
    if IsPlayerAceAllowed(src, Config.AdminPerm) then
        TriggerClientEvent('prestonadmin:permgranted', src)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^1No admin perm' } })
    end
end)

RegisterServerEvent('prestonadmin:kick')
AddEventHandler('prestonadmin:kick', function(target, reason)
    if IsPlayerAceAllowed(source, Config.AdminPerm) then DropPlayer(target, "Kicked: "..reason) end
end)

RegisterServerEvent('prestonadmin:ban')
AddEventHandler('prestonadmin:ban', function(target, reason)
    if IsPlayerAceAllowed(source, Config.AdminPerm) then DropPlayer(target, "Banned: "..reason) end
end)

RegisterServerEvent('prestonadmin:announce')
AddEventHandler('prestonadmin:announce', function(msg)
    if IsPlayerAceAllowed(source, Config.AdminPerm) then
        TriggerClientEvent('chat:addMessage', -1, { args = { '^1[ADMIN] ^7'..msg } })
    end
end)

RegisterCommand('plist', function(source)
    if not IsPlayerAceAllowed(source, Config.AdminPerm) then return end
    local players = GetPlayers()
    local msg = "^2Players online:\n"
    for _, id in ipairs(players) do msg = msg .. id .. " - " .. GetPlayerName(id) .. "\n" end
    TriggerClientEvent('chat:addMessage', source, { args = { msg } })
end, false)

local isAdmin = false
local god = false
local noclip = false
local invis = false
local frozen = false

RegisterCommand('adminhelp', function() TriggerServerEvent('prestonadmin:checkperm') end, false)

RegisterNetEvent('prestonadmin:permgranted')
AddEventHandler('prestonadmin:permgranted', function()
    isAdmin = true
    TriggerEvent('chat:addMessage', { args = { '^2Admin ON - Commands: /kick /ban /tp /bring /god /noclip /car /fix /del /plist /heal /invis /announce /freeze /slap' } })
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

-- TP
RegisterCommand('tp', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local id = tonumber(args[1])
    if id then
        local c = GetEntityCoords(GetPlayerPed(id))
        SetEntityCoords(PlayerPedId(), c.x, c.y, c.z + 1)
    end
end, false)

-- BRING
RegisterCommand('bring', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local id = tonumber(args[1])
    if id then
        local my = GetEntityCoords(PlayerPedId())
        SetEntityCoords(GetPlayerPed(id), my.x, my.y, my.z + 1)
    end
end, false)

-- GOD
RegisterCommand('god', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    god = not god
    SetEntityInvincible(PlayerPedId(), god)
    TriggerEvent('chat:addMessage', { args = { god and '^2God ON' or '^1God OFF' } })
end, false)

-- NOCLIP
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
            local s = 5.0
            if IsControlPressed(0, 32) then z = z + s end
            if IsControlPressed(0, 269) then z = z - s end
            if IsControlPressed(0, 34) then x = x - s end
            if IsControlPressed(0, 35) then x = x + s end
            if IsControlPressed(0, 22) then z = z + s end
            if IsControlPressed(0, 36) then z = z - s end
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        end
    end
end)

-- CAR
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

-- FIX
RegisterCommand('fix', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v ~= 0 then SetVehicleFixed(v) SetVehicleDeformationFixed(v) end
end, false)

-- DEL
RegisterCommand('del', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v ~= 0 then DeleteVehicle(v) end
end, false)

-- HEAL
RegisterCommand('heal', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    SetEntityHealth(PlayerPedId(), 200)
    TriggerEvent('chat:addMessage', { args = { '^2Healed' } })
end, false)

-- INVIS
RegisterCommand('invis', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    invis = not invis
    SetEntityVisible(PlayerPedId(), not invis, false)
    TriggerEvent('chat:addMessage', { args = { invis and '^2Invisible ON' or '^1Invisible OFF' } })
end, false)

-- ANNOUNCE
RegisterCommand('announce', function(_, args)
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    local msg = table.concat(args, " ") or "Admin message"
    TriggerServerEvent('prestonadmin:announce', msg)
end, false)

-- FREEZE self
RegisterCommand('freeze', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    frozen = not frozen
    FreezeEntityPosition(PlayerPedId(), frozen)
    TriggerEvent('chat:addMessage', { args = { frozen and '^2Frozen ON' or '^1Frozen OFF' } })
end, false)

-- SLAP self
RegisterCommand('slap', function()
    if not isAdmin then TriggerServerEvent('prestonadmin:checkperm') return end
    ApplyForceToEntity(PlayerPedId(), 1, 0.0, 0.0, 50.0, 0.0, 0.0, 0.0, 0, false, false, false, false, false)
    TriggerEvent('chat:addMessage', { args = { '^2Slapped' } })
end, false)
