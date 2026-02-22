RegisterCommand('car', function(source, args)
    local model = args[1] or 'adder'
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, coords.x + 2, coords.y, coords.z, GetEntityHeading(ped), true, false)
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
    TriggerEvent('chat:addMessage', { args = { '^2Spawned ' .. model } })
end, false)
