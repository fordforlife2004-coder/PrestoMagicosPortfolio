local elsOn = false
local pattern = 1

RegisterCommand('els', function()
    elsOn = not elsOn
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        SetVehicleSiren(veh, elsOn)
        SetVehicleLights(veh, elsOn and 2 or 0)
    end
    TriggerEvent('chat:addMessage', { args = { elsOn and '^2ELS ON (L key)' or '^1ELS OFF' } })
end, false)

RegisterKeyMapping('els', 'Toggle ELS Lights/Siren', 'keyboard', 'L')

RegisterCommand('pattern', function(_, args)
    pattern = tonumber(args[1]) or 1
    if pattern < 1 or pattern > 3 then pattern = 1 end
    TriggerEvent('chat:addMessage', { args = { '^2ELS Pattern set to ' .. pattern } })
end, false)

RegisterCommand('elshelp', function()
    TriggerEvent('chat:addMessage', { args = { '^2ELS Commands: /els (toggle)   /pattern 1-3   L key' } })
end, false)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if elsOn and veh ~= 0 then
            -- Pattern 1: Slow alternate (good for Iowa Tahoe)
            if pattern == 1 then
                SetVehicleExtra(veh, 1, false) Wait(200)
                SetVehicleExtra(veh, 1, true)  Wait(200)
                SetVehicleExtra(veh, 2, false) Wait(200)
                SetVehicleExtra(veh, 2, true)  Wait(200)
            -- Pattern 2: Fast strobe
            elseif pattern == 2 then
                SetVehicleExtra(veh, 1, false) Wait(80)
                SetVehicleExtra(veh, 1, true)  Wait(80)
                SetVehicleExtra(veh, 2, false) Wait(80)
                SetVehicleExtra(veh, 2, true)  Wait(80)
            -- Pattern 3: Solid + flash
            elseif pattern == 3 then
                SetVehicleExtra(veh, 1, false)
                SetVehicleExtra(veh, 2, false)
                Wait(300)
                SetVehicleExtra(veh, 1, true)
                SetVehicleExtra(veh, 2, true)
                Wait(300)
            end
            SetVehicleLights(veh, 2)
        else
            Wait(500)
        end
    end
end)

