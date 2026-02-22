fx_version 'cerulean'
game 'gta5'

author 'Preston D'
description 'Vehicle Skins + Extras + Tune - Portfolio 2026'
version '1.0'

client_script 'client.lua'

-- SPAWN with skin (livery)
RegisterCommand('spawnskin', function(_, args)
    local model = args[1] or 'adder'
    local livery = tonumber(args[2]) or 0
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local v = CreateVehicle(hash, c.x+3, c.y, c.z, GetEntityHeading(ped), true, false)
    SetPedIntoVehicle(ped, v, -1)
    SetVehicleLivery(v, livery)
    SetVehicleNumberPlateText(v, "PRESTON")
    TriggerEvent('chat:addMessage', { args = { '^2Spawned ' .. model .. ' with livery ' .. livery } })
end, false)

-- SET livery on current car
RegisterCommand('setlivery', function(_, args)
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 then return end
    local liv = tonumber(args[1])
    if liv then
        SetVehicleLivery(v, liv)
        TriggerEvent('chat:addMessage', { args = { '^2Livery set to ' .. liv } })
    end
end, false)

-- SHOW liveries
RegisterCommand('liveries', function()
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 then return end
    local count = GetVehicleLiveryCount(v)
    local cur = GetVehicleLivery(v)
    TriggerEvent('chat:addMessage', { args = { '^2Liveries: ' .. count .. ' | Current: ' .. cur } })
end, false)

-- RANDOM livery
RegisterCommand('randomlivery', function()
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 then return end
    local count = GetVehicleLiveryCount(v)
    local r = math.random(0, count-1)
    SetVehicleLivery(v, r)
    TriggerEvent('chat:addMessage', { args = { '^2Random livery: ' .. r } })
end, false)

-- EXTRAS (toggle 1-12)
RegisterCommand('extra', function(_, args)
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 then return end
    local id = tonumber(args[1])
    if id and id >= 1 and id <= 12 then
        local on = IsVehicleExtraTurnedOn(v, id)
        SetVehicleExtra(v, id, not on)
        TriggerEvent('chat:addMessage', { args = { '^2Extra ' .. id .. (not on and ' ON' or ' OFF') } })
    end
end, false)

-- TUNE (max performance)
RegisterCommand('tune', function()
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 then return end
    SetVehicleModKit(v, 0)
    for i = 0, 16 do SetVehicleMod(v, i, GetNumVehicleMods(v, i)-1, false) end
    SetVehicleMod(v, 18, 1, false) -- turbo
    SetVehicleTyresCanBurst(v, false)
    SetVehicleWindowTint(v, 1)
    TriggerEvent('chat:addMessage', { args = { '^2Full tune applied' } })
end, false)

-- HELP
RegisterCommand('vehicleskins', function()
    TriggerEvent('chat:addMessage', { args = { '^2Commands: /spawnskin model livery   /setlivery num   /liveries   /randomlivery   /extra 1-12   /tune' } })
end, false)

