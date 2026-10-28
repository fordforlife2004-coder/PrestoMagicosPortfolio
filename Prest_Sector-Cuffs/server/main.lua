-- Everything that changes who is cuffed goes through the server. It checks the officer's permission,
-- that the suspect is really within reach and in the same world instance, and the cooldown. Then it
-- tells both players' games to play the arrest, and once the cuffs close it writes the suspect's
-- style to GlobalState, which every game reads to put the cuffs on their wrists. Only the server can
-- write GlobalState, so no player's game can uncuff itself or show cuffs that aren't there.

local C = Cuffs

-- How much further apart (metres) the server lets players be than Config.MaxDistance. The server
-- sees positions a moment late, so a suspect who was in reach on the officer's screen still counts.
local SLACK = 1.0

-- An officer and the suspect they hold who end up further apart than this (the officer died and
-- respawned, or got teleported) lose the hold, so the suspect is never pulled across the map.
local HOLD_REACH = 5.0

-- How long (ms) a suspect being put into a vehicle can't be grabbed, cuffed or seated again.
local SEATING_MS = 8000

local cuffed = {}     -- [suspect] = { style = 'rear', by = officer }
local escorts = {}    -- [suspect] = the officer holding them by the arm
local busy = {}       -- [suspect] = { officer, kind, token } while cuffs go on or come off
local seating = {}    -- [suspect] = game time until which they are getting into a vehicle
local lastAction = {} -- [officer] = game time (ms) of their last action
local published = {} -- [player] = true for every player whose keys the server has set
local remembered = {} -- [license] = { style, at } for players who left while cuffed
local nextToken = 0

local function allowed(src, ace)
    return ace == '' or IsPlayerAceAllowed(src, ace)
end

local function tell(src, message, tone)
    TriggerClientEvent('Prest_Sector-Cuffs:notify', src, message, tone or 'error')
end

local function online(id) return id ~= nil and GetPlayerName(id) ~= nil end

local function pedOf(id)
    local ped = GetPlayerPed(id)
    if ped and ped ~= 0 and DoesEntityExist(ped) then return ped end
    return nil
end

-- Whether two players are within `reach` metres of each other, in the same world instance.
local function within(a, b, reach)
    local pa, pb = pedOf(a), pedOf(b)
    if not pa or not pb or GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
    -- A held suspect hangs on the officer, and the server may not see an attached ped move, so
    -- being attached to each other counts as in reach.
    if GetEntityAttachedTo and (GetEntityAttachedTo(pb) == pa or GetEntityAttachedTo(pa) == pb) then return true end
    return C.distance(GetEntityCoords(pa), GetEntityCoords(pb)) <= reach
end

local function vehicleOf(id)
    local ped = pedOf(id)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    return vehicle ~= 0 and vehicle or nil
end

local function playerOfPed(ped)
    for _, id in ipairs(GetPlayers()) do
        if GetPlayerPed(id) == ped then return C.toId(id) end
    end
    return nil
end

-- The suspect an officer is holding by the arm, if any.
local function holdingOf(officer)
    for suspect, by in pairs(escorts) do
        if by == officer then return suspect end
    end
    return nil
end

-- The server's word on who is cuffed and held, written to GlobalState for every game to see.
local function publish(id)
    GlobalState:set(C.cuffsKey(id), cuffed[id] and cuffed[id].style or nil, true)
    GlobalState:set(C.escortKey(id), escorts[id], true)
    published[id] = (cuffed[id] or escorts[id]) and true or nil
end

-- Lets go of the suspect an officer holds, if any.
local function release(officer)
    local held = holdingOf(officer)
    if held then
        escorts[held] = nil
        publish(held)
    end
    return held
end

local function onCooldown(src)
    return lastAction[src] ~= nil and GetGameTimer() - lastAction[src] < Config.CooldownSeconds * 1000
end

-- Checks shared by every action. Returns why the officer can't go ahead, or nil if they can.
local function refuse(src, target, reach)
    if not allowed(src, Config.AcePermission) then return "You aren't allowed to use handcuffs." end
    if cuffed[src] then return "You can't do that with your own hands cuffed." end
    if busy[src] then return "You can't do that while you're being cuffed." end
    if not online(target) or target == src then return 'Nobody is close enough.' end
    if busy[target] then return 'Hold on, the cuffs are still going on or coming off.' end
    for _, b in pairs(busy) do
        if b.officer == src then return 'Finish what you are doing first.' end
        if b.officer == target then return 'They are busy.' end
    end
    if seating[target] and GetGameTimer() < seating[target] then return 'Hold on, they are getting into a vehicle.' end
    if onCooldown(src) then return 'Slow down a little.' end
    if not within(src, target, reach) then return 'Get closer to them first.' end
    return nil
end

-- Plays the cuffs going on or coming off on both players, then calls done() if the suspect is
-- still in reach when the animation ends.
local function animate(src, target, kind, styleKey, done)
    nextToken = nextToken + 1
    local token = nextToken
    busy[target] = { officer = src, kind = kind, token = token }
    lastAction[src] = GetGameTimer()
    TriggerClientEvent('Prest_Sector-Cuffs:animate', src, kind, 'officer', target, styleKey)
    TriggerClientEvent('Prest_Sector-Cuffs:animate', target, kind, 'suspect', src, styleKey)
    SetTimeout(math.floor(C.animationFor(Config, kind, styleKey).seconds * 1000), function()
        local b = busy[target]
        if not b or b.token ~= token then return end -- someone left in the meantime
        busy[target] = nil
        if not online(src) or not online(target) or cuffed[src] then return end
        if not within(src, target, Config.MaxDistance + SLACK + 1.0) then
            return tell(src, kind == 'cuff' and 'They pulled away before the cuffs closed.'
                or 'They moved away before the cuffs came off.')
        end
        done()
    end)
end

local function styleNames()
    local names = {}
    for key in pairs(Config.Styles) do names[#names + 1] = key end
    table.sort(names)
    return table.concat(names, ', ')
end

RegisterNetEvent('Prest_Sector-Cuffs:cuff', function(target, styleName)
    local src = source
    target = C.toId(target)
    local why = refuse(src, target, Config.MaxDistance + SLACK)
    if why then return tell(src, why) end
    if cuffed[target] then return tell(src, 'They are already cuffed.') end
    if holdingOf(src) then return tell(src, 'Let go of the person you are holding first (/escort).') end
    local suspectPed = pedOf(target)
    local key, style = C.styleFor(Config, styleName, GetEntityCoords(suspectPed), GetEntityHeading(suspectPed),
        GetEntityCoords(pedOf(src)))
    if not key then return tell(src, 'Unknown cuff style. Try one of: ' .. styleNames()) end
    if vehicleOf(src) or vehicleOf(target) then return tell(src, 'You both need to be on foot.') end
    animate(src, target, 'cuff', key, function()
        if vehicleOf(target) then return tell(src, 'They got into a vehicle.') end
        release(target) -- whoever they were holding is free now
        cuffed[target] = { style = key, by = src }
        publish(target)
        tell(src, ('Cuffed %s.'):format(style.label), 'success')
        tell(target, ('You have been handcuffed %s.'):format(style.label), 'info')
    end)
end)

RegisterNetEvent('Prest_Sector-Cuffs:uncuff', function(target)
    local src = source
    target = C.toId(target)
    local why = refuse(src, target, Config.MaxDistance + SLACK)
    if why then return tell(src, why) end
    if not cuffed[target] then return tell(src, "They aren't cuffed.") end
    local held = holdingOf(src)
    if held and held ~= target then return tell(src, 'Let go of the person you are holding first (/escort).') end
    if vehicleOf(target) then return tell(src, 'Take them out of the vehicle first.') end
    if vehicleOf(src) then return tell(src, 'Get out of the vehicle first.') end
    escorts[target] = nil -- let go of their arm to reach the cuffs
    publish(target)
    animate(src, target, 'uncuff', cuffed[target].style, function()
        cuffed[target] = nil
        publish(target)
        tell(src, 'Cuffs off.', 'success')
        tell(target, 'Your cuffs are off.', 'info')
    end)
end)

-- /escort: let go of the suspect you're holding, or take a cuffed suspect by the arm.
RegisterNetEvent('Prest_Sector-Cuffs:escort', function(target)
    local src = source
    if release(src) then return tell(src, 'You let go.', 'info') end
    target = C.toId(target)
    local why = refuse(src, target, Config.MaxDistance + SLACK)
    if why then return tell(src, why) end
    if not cuffed[target] then return tell(src, 'Cuff them first.') end
    if escorts[target] then return tell(src, 'Someone else is already holding them.') end
    if vehicleOf(target) then return tell(src, 'Take them out of the vehicle first.') end
    if vehicleOf(src) then return tell(src, 'Get out of the vehicle first.') end
    lastAction[src] = GetGameTimer()
    escorts[target] = src
    publish(target)
    tell(src, 'You have them by the arm. Use /escort again to let go.', 'success')
end)

-- /putin: seat the suspect you're holding (or the nearest cuffed one) in a free passenger seat.
RegisterNetEvent('Prest_Sector-Cuffs:seat', function(target, netId, seat)
    local src = source
    target = holdingOf(src) or C.toId(target)
    seat = math.tointeger(seat)
    if type(netId) ~= 'number' or not seat or seat < 0 or seat > 14 then return end
    local why = refuse(src, target, Config.MaxDistance + SLACK + 0.5)
    if why then return tell(src, why) end
    if not cuffed[target] then return tell(src, 'Cuff them first.') end
    if vehicleOf(target) then return tell(src, 'They are already in a vehicle.') end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then
        return tell(src, 'No vehicle close enough.')
    end
    if C.distance(GetEntityCoords(pedOf(src)), GetEntityCoords(vehicle)) > Config.VehicleDistance + SLACK then
        return tell(src, 'Get closer to the vehicle.')
    end
    if GetPedInVehicleSeat(vehicle, seat) ~= 0 then return tell(src, 'That seat is taken.') end
    -- Never into a getaway car: whoever drives must be the officer or someone allowed to use cuffs.
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver ~= 0 and driver ~= pedOf(src) then
        local who = playerOfPed(driver)
        if not who or not allowed(who, Config.AcePermission) then return tell(src, 'Someone else is driving that vehicle.') end
    end
    lastAction[src] = GetGameTimer()
    seating[target] = GetGameTimer() + SEATING_MS
    escorts[target] = nil
    publish(target)
    TriggerClientEvent('Prest_Sector-Cuffs:seat', target, netId, seat)
    tell(src, 'Seated them in the vehicle.', 'success')
end)

-- /takeout: bring a cuffed suspect out of the vehicle next to you, and take them by the arm.
RegisterNetEvent('Prest_Sector-Cuffs:unseat', function(target)
    local src = source
    target = C.toId(target)
    local why = refuse(src, target, Config.VehicleDistance + SLACK)
    if why then return tell(src, why) end
    if not cuffed[target] then return tell(src, "They aren't cuffed.") end
    local vehicle = vehicleOf(target)
    if not vehicle then return tell(src, "They aren't in a vehicle.") end
    if vehicleOf(src) then return tell(src, 'Get out of the vehicle first.') end
    if C.distance(GetEntityCoords(pedOf(src)), GetEntityCoords(vehicle)) > Config.VehicleDistance + SLACK then
        return tell(src, 'Get closer to the vehicle.')
    end
    lastAction[src] = GetGameTimer()
    if not holdingOf(src) and not escorts[target] then escorts[target] = src end
    publish(target)
    TriggerClientEvent('Prest_Sector-Cuffs:unseat', target)
    tell(src, 'Took them out of the vehicle.', 'success')
end)

-- /cuffadjust: the officer's own game lines the cuffs up on their own wrists; this only checks the ACE.
RegisterNetEvent('Prest_Sector-Cuffs:adjust', function(styleName)
    local src = source
    if not allowed(src, Config.AdjustPermission) then return tell(src, "You aren't allowed to use /cuffadjust.") end
    if cuffed[src] then return tell(src, "You can't do that with your own hands cuffed.") end
    local key = C.findStyle(Config, styleName)
    if not key then return tell(src, 'Unknown cuff style. Try one of: ' .. styleNames()) end
    TriggerClientEvent('Prest_Sector-Cuffs:adjust', src, key)
end)

-- For other scripts (jail, admin menus): exports['Prest_Sector-Cuffs']:IsCuffed(id), :Uncuff(id).
exports('IsCuffed', function(id)
    local entry = cuffed[C.toId(id) or -1]
    return entry ~= nil, entry and entry.style or nil
end)

exports('Uncuff', function(id)
    id = C.toId(id)
    if not id or not cuffed[id] then return false end
    cuffed[id], escorts[id], busy[id] = nil, nil, nil
    publish(id)
    return true
end)

-- Every second: an officer who got into a vehicle, or ended up far from the suspect they hold
-- (they died and respawned, or were teleported), lets go.
local function checkHolds()
    for suspect, officer in pairs(escorts) do
        if not online(officer) or not online(suspect) or vehicleOf(officer) or not within(officer, suspect, HOLD_REACH) then
            escorts[suspect] = nil
            publish(suspect)
            if online(officer) then tell(officer, 'You lost your hold on them.', 'info') end
        end
    end
    SetTimeout(1000, checkHolds)
end
SetTimeout(1000, checkHolds)

local function licenseOf(id)
    return GetPlayerIdentifierByType and GetPlayerIdentifierByType(id, 'license') or nil
end

-- Leaving the server doesn't take the cuffs off: a player who comes back within
-- Config.KeepCuffsMinutes is cuffed again.
AddEventHandler('playerDropped', function()
    local src = C.toId(source)
    if not src then return end
    if cuffed[src] and (Config.KeepCuffsMinutes or 0) > 0 then
        local license = licenseOf(src)
        if license then remembered[license] = { style = cuffed[src].style, at = os.time() } end
    end
    cuffed[src], escorts[src], busy[src], seating[src], lastAction[src] = nil, nil, nil, nil, nil
    release(src)
    for suspect, b in pairs(busy) do
        if b.officer == src then busy[suspect] = nil end
    end
    publish(src) -- clears their keys, so whoever gets this ID next starts free
end)

AddEventHandler('playerJoining', function()
    local src = C.toId(source)
    local license = src and licenseOf(src)
    local memory = license and remembered[license]
    if not memory then return end
    remembered[license] = nil
    if os.time() - memory.at <= (Config.KeepCuffsMinutes or 0) * 60 and Config.Styles[memory.style] then
        cuffed[src] = { style = memory.style }
        publish(src)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, problem in ipairs(C.checkConfig(Config)) do print(('[Prest_Sector-Cuffs] config problem: %s'):format(problem)) end
    -- After a restart nobody is cuffed as far as the server knows, so clear any keys left from before.
    for _, id in ipairs(GetPlayers()) do
        local player = C.toId(id)
        if player and (GlobalState[C.cuffsKey(player)] ~= nil or GlobalState[C.escortKey(player)] ~= nil) then
            publish(player)
        end
    end
end)

-- Stopping the script takes everyone's cuffs off, so no other script keeps treating them as cuffed.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(published) do
        GlobalState:set(C.cuffsKey(id), nil, true)
        GlobalState:set(C.escortKey(id), nil, true)
    end
end)
