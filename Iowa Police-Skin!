-- HELP
RegisterCommand('iowahelp', function()
    TriggerEvent('chat:addMessage', { args = { '^2Iowa Police Commands: /isp (spawn ISP Tahoe)   /iowaskin (skin any car as Iowa PD)' } })
end, false)

-- SPAWN Iowa State Patrol vehicle
RegisterCommand('isp', function()
    local model = 'police3'  -- Tahoe style, common for ISP
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local v = CreateVehicle(hash, c.x+3, c.y, c.z, GetEntityHeading(ped), true, false)
    SetPedIntoVehicle(ped, v, -1)
    
    -- Iowa ISP colors (tan primary, black secondary, gold accents)
    SetVehicleColours(v, 101, 0)        -- 101 = beige/tan, 0 = black
    SetVehicleExtraColours(v, 37, 0)    -- 37 = gold pearlescent
    SetVehicleNumberPlateText(v, "ISP001")
    SetVehicleNumberPlateTextIndex(v, 4) -- blue plate
    SetVehicleDirtLevel(v, 0.0)
    
    -- Enable police extras (lights, lightbar etc)
    for i = 0, 12 do
        SetVehicleExtra(v, i, false)
    end
    TriggerEvent('chat:addMessage', { args = { '^2Spawned Iowa State Patrol Tahoe' } })
end, false)

-- SKIN ANY CURRENT VEHICLE as Iowa PD
RegisterCommand('iowaskin', function()
    local v = GetVehiclePedIsIn(PlayerPedId(), false)
    if v == 0 then 
        TriggerEvent('chat:addMessage', { args = { '^1Get in a vehicle first' } })
        return 
    end
    
    -- Iowa colors
    SetVehicleColours(v, 101, 0)        -- tan/black
    SetVehicleExtraColours(v, 37, 0)    -- gold
    SetVehicleNumberPlateText(v, "IOWA PD")
    SetVehicleNumberPlateTextIndex(v, 4)
    SetVehicleDirtLevel(v, 0.0)
    
    -- Extras on
    for i = 0, 12 do
        SetVehicleExtra(v, i, false)
    end
    
    -- If it has livery, set ISP style
    if GetVehicleLiveryCount(v) > 0 then
        SetVehicleLivery(v, 0)
    end
    
    TriggerEvent('chat:addMessage', { args = { '^2Applied Iowa State Patrol skin' } })
end, false)

