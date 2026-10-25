-- The server checks every ELS change before anyone else sees it: the player must be driving that
-- vehicle (or have just got out of it, to switch things off), the values must be valid and requests
-- are rate limited. Approved changes go into the vehicle's state ("presEls"), which every nearby
-- player's game then plays. Changes to that state that didn't come from here are put back.

local E = PrestonEls

local MODEL_NAMES = {} -- [model hash] = spawn name, for vehicles listed in Config.Vehicles
for name in pairs(Config.Vehicles) do MODEL_NAMES[GetHashKey(name)] = name end

local allowRequest, forgetRequests = E.newRateLimiter(12, 1) -- 12 key presses a second is plenty
local approved = {}   -- [vehicle net id] = the last state the server set
local lastDriver = {} -- [vehicle net id] = the player who last drove it with ELS

local function refuse(src, netId, reason)
    TriggerClientEvent('preston-els:refused', src, netId, reason)
end

RegisterNetEvent('preston-els:set', function(netId, change, seq)
    local src = source
    if not allowRequest(src, GetGameTimer() / 1000) then return refuse(src, netId, 'too many requests') end
    if type(netId) ~= 'number' or type(change) ~= 'table' or type(seq) ~= 'number' then
        return refuse(src, netId, 'bad request')
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return refuse(src, netId, 'that vehicle no longer exists')
    end
    if Config.AcePermission ~= '' and not IsPlayerAceAllowed(src, Config.AcePermission) then
        return refuse(src, netId, 'no permission')
    end

    local settings = E.settingsFor(Config, MODEL_NAMES[GetEntityModel(vehicle)])
    -- The server can't read a vehicle's class, so "every emergency vehicle" is checked by the
    -- driver's game; with AllEmergencyVehicles off, only listed vehicles are accepted.
    if not settings.listed and not Config.AllEmergencyVehicles then
        return refuse(src, netId, 'not an ELS vehicle')
    end

    local driving = GetPedInVehicleSeat(vehicle, -1) == GetPlayerPed(src)
    if not driving and not (lastDriver[netId] == src and E.onlyTurnsOff(change)) then
        return refuse(src, netId, 'not the driver')
    end

    local new, why = E.applyChange(Entity(vehicle).state.presEls, change, settings, #Config.Patterns)
    if not new then return refuse(src, netId, why) end
    new.seq, new.by = seq, src
    if driving then lastDriver[netId] = src end
    approved[netId] = new
    Entity(vehicle).state:set('presEls', new, true)
end)

-- Players' games may write to state on vehicles they control. If anything other than the server
-- changes a vehicle's ELS state, put the approved value back.
AddStateBagChangeHandler('presEls', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local official = approved[netId]
    if official == nil and value == nil then return end
    if official ~= nil and value ~= nil and E.same(official, value) then return end
    SetTimeout(0, function()
        if DoesEntityExist(vehicle) then Entity(vehicle).state:set('presEls', official, true) end
    end)
end)

AddEventHandler('entityRemoved', function(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    approved[netId], lastDriver[netId] = nil, nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    forgetRequests(src)
    for netId, driver in pairs(lastDriver) do
        if driver == src then lastDriver[netId] = nil end
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local problems = E.checkConfig(Config)
    for _, problem in ipairs(problems) do print(('[preston-els] config problem: %s'):format(problem)) end
    local listed = 0
    for _ in pairs(Config.Vehicles) do listed = listed + 1 end
    print(('[preston-els] v2 ready: %d tones, %d patterns, %d listed vehicles%s.'):format(
        #Config.Tones, #Config.Patterns, listed, Config.AllEmergencyVehicles and ' plus every emergency vehicle' or ''))
end)
