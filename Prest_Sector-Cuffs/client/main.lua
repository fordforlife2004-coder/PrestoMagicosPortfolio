-- The player's side. An officer's commands find who they mean and ask the server. A cuffed player's
-- game holds them in the cuffed pose, blocks what cuffed hands can't do, walks along with the officer
-- holding them, and gets in and out of vehicles when the server says so. Who is cuffed comes from
-- GlobalState, which only the server writes; every action still goes through the server.

local C = Cuffs

local UNARMED = GetHashKey('WEAPON_UNARMED')

-- Controls cuffed hands can't use.
local BLOCKED = {
    24, 25, 257, 263, 264, 140, 141, 142, 143, -- attack, aim and melee
    37, 45, 47, 58,                           -- weapon wheel, reload, detonate, throw
    22, 44, 23, 75, 27,                       -- jump, take cover, get in or out of a vehicle, phone
}
local SPRINT = 21
local ENTER_VEHICLE = 23
local DRIVING = { 59, 60, 63, 64, 71, 72 } -- steer, accelerate and brake, in case they end up driving
local MOVING = { 30, 31, 21, 22, 23, 24, 25 } -- held still while the cuffs go on or come off

-- TaskPlayAnim flags: 1 loops, 16 moves the upper body only, 32 plays alongside walking.
local LOOP, UPPER, ALONGSIDE = 1, 16, 32
local POSE_FLAGS = LOOP + UPPER + ALONGSIDE

-- Attaching one player to another with 11816 passed straight in (not looked up as a bone) holds
-- them to the other player's middle. The line-up and escort offsets in config.lua are tuned for it.
local MIDDLE = 11816

-- How close (metres) the officer must be for a held player to take hold of their arm.
local HOLD_REACH = 3.0

-- Ped config flag that stops a passenger shuffling over into an empty driver seat.
local NO_SEAT_SHUFFLE = 184

-- GTA notifications take at most 99 characters per piece of text, so longer ones go in pieces.
local function notify(message, tone)
    BeginTextCommandThefeedPost(#message > 99 and 'CELL_EMAIL_BCON' or 'STRING')
    for i = 1, #message, 99 do AddTextComponentSubstringPlayerName(message:sub(i, i + 98)) end
    EndTextCommandThefeedPostTicker(tone == 'error', false)
end

local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    for _ = 1, 200 do
        if HasAnimDictLoaded(dict) then return true end
        Wait(10)
    end
    return HasAnimDictLoaded(dict)
end

-- Plays an animation from the config; its own flags win over the ones given here.
local function play(ped, anim, flags, ms)
    if not loadDict(anim.dict) then return false end
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, ms or -1, anim.flags or flags, 0.0, false, false, false)
    return true
end

local function myId() return GetPlayerServerId(PlayerId()) end

local function styleOf(id)
    local key = GlobalState[C.cuffsKey(id)]
    return key and Config.Styles[key] or nil
end

local function myStyle() return styleOf(myId()) end
local function isCuffed(id) return GlobalState[C.cuffsKey(id)] ~= nil end

-- The server ID of the cuffed player this officer is holding by the arm, if any.
local function holding()
    local me = myId()
    for _, player in ipairs(GetActivePlayers()) do
        local id = GetPlayerServerId(player)
        if GlobalState[C.escortKey(id)] == me then return id end
    end
    return nil
end

-- Whether nothing solid (a wall, a door, bars) is between two peds.
local function canSee(a, b) return HasEntityClearLosToEntity(a, b, 17) end

-- The player the officer means: the closest one in reach they can see (someone in front first) that
-- passes `want`.
local function target(want)
    local me = PlayerPedId()
    local others = {}
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        local id = GetPlayerServerId(player)
        if player ~= PlayerId() and ped ~= 0 and DoesEntityExist(ped) and want(id, ped) and canSee(me, ped) then
            others[#others + 1] = { id = id, coords = GetEntityCoords(ped) }
        end
    end
    return C.pickTarget(GetEntityCoords(me), GetEntityHeading(me), others, Config.MaxDistance)
end

local function onFoot(_, ped) return not IsPedInAnyVehicle(ped, false) end
local function freeOnFoot(id, ped) return not isCuffed(id) and onFoot(id, ped) end
local function cuffedOnFoot(id, ped) return isCuffed(id) and onFoot(id, ped) end

-- Vehicles other players can see (networked) within reach, closest first.
local function vehiclesNear(reach)
    local here = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local d = C.distance(here, GetEntityCoords(vehicle))
        if d <= reach and NetworkGetEntityIsNetworked(vehicle) then list[#list + 1] = { vehicle = vehicle, d = d } end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

-- A free seat for a suspect: the back seats first, then any other passenger seat, the front last.
local function freeSeat(vehicle)
    local passengers = GetVehicleMaxNumberOfPassengers(vehicle)
    local order = {}
    for seat = 1, passengers - 1 do order[#order + 1] = seat end
    if passengers >= 1 then order[#order + 1] = 0 end
    for _, seat in ipairs(order) do
        if IsVehicleSeatFree(vehicle, seat) then return seat end
    end
    return nil
end

-- ---------------------------------------------------------------- the officer's commands

local function handsFree()
    if myStyle() then
        notify("You can't do that with your own hands cuffed.", 'error')
        return false
    end
    return true
end

local function onFootMyself()
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        notify('Get out of the vehicle first.', 'error')
        return false
    end
    return true
end

RegisterCommand('cuff', function(_, args)
    if not handsFree() or not onFootMyself() then return end
    local id = target(freeOnFoot)
    if not id then return notify('Nobody close enough to cuff.', 'error') end
    TriggerServerEvent('Prest_Sector-Cuffs:cuff', id, args[1])
end, false)

RegisterCommand('uncuff', function()
    if not handsFree() or not onFootMyself() then return end
    local id = target(cuffedOnFoot)
    if not id then return notify('Nobody cuffed is close enough.', 'error') end
    TriggerServerEvent('Prest_Sector-Cuffs:uncuff', id)
end, false)

-- One key for both: cuff the nearest player, or take the cuffs off if they're already cuffed.
RegisterCommand('cufftoggle', function()
    if not handsFree() or not onFootMyself() then return end
    local id = target(onFoot)
    if not id then return notify('Nobody close enough.', 'error') end
    TriggerServerEvent(isCuffed(id) and 'Prest_Sector-Cuffs:uncuff' or 'Prest_Sector-Cuffs:cuff', id)
end, false)

-- Letting go always reaches the server, even when the held player is out of this game's view
-- (the server lets go first, before looking for anyone new to hold).
RegisterCommand('escort', function()
    if holding() then return TriggerServerEvent('Prest_Sector-Cuffs:escort') end
    if not handsFree() or not onFootMyself() then return end
    TriggerServerEvent('Prest_Sector-Cuffs:escort', target(cuffedOnFoot))
end, false)

RegisterCommand('putin', function()
    if not handsFree() or not onFootMyself() then return end
    local id = holding() or target(cuffedOnFoot)
    if not id then return notify('Nobody cuffed is close enough.', 'error') end
    for _, near in ipairs(vehiclesNear(Config.VehicleDistance)) do
        local seat = freeSeat(near.vehicle)
        if seat then return TriggerServerEvent('Prest_Sector-Cuffs:seat', id, VehToNet(near.vehicle), seat) end
    end
    notify('No vehicle with a free seat close enough.', 'error')
end, false)

RegisterCommand('takeout', function()
    if not handsFree() or not onFootMyself() then return end
    for _, near in ipairs(vehiclesNear(Config.VehicleDistance)) do
        for seat = -1, GetVehicleMaxNumberOfPassengers(near.vehicle) - 1 do
            local ped = GetPedInVehicleSeat(near.vehicle, seat)
            if ped ~= 0 and IsPedAPlayer(ped) then
                local id = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
                if isCuffed(id) then return TriggerServerEvent('Prest_Sector-Cuffs:unseat', id) end
            end
        end
    end
    notify('No cuffed player in a vehicle close enough.', 'error')
end, false)

RegisterCommand('cuffadjust', function(_, args)
    if not handsFree() or not onFootMyself() then return end
    TriggerServerEvent('Prest_Sector-Cuffs:adjust', args[1])
end, false)

RegisterCommand('cuffhelp', function()
    for _, line in ipairs({
        '/cuff [front|rear]  cuff the nearest player (in front if you face them, behind if you are behind)',
        '/uncuff  take the cuffs off the nearest cuffed player',
        '/escort  take the nearest cuffed player by the arm, or let go',
        '/putin  seat the player you are holding in the nearest vehicle',
        '/takeout  bring a cuffed player out of the nearest vehicle',
        '/cuffadjust [style]  line the cuffs up on the wrists (staff)',
    }) do TriggerEvent('chat:addMessage', { args = { 'Cuffs', line } }) end
end, false)

RegisterKeyMapping('cufftoggle', 'Cuff or uncuff the nearest player', 'keyboard', Config.Keys.cuff or '')
RegisterKeyMapping('escort', 'Hold a cuffed player by the arm, or let go', 'keyboard', Config.Keys.escort or '')

-- ---------------------------------------------------------------- the cuffed player's side

local busyUntil = 0      -- game time until which the cuffs are going on or coming off
local holdStillUntil = 0 -- game time until which this player can't walk (part of that, or all of it)
local cuffedPed = nil    -- the ped the cuffs were put on (it changes when the player respawns)
local attachedTo = nil   -- the officer's ped while they hold this player by the arm
local lineUpTo = nil     -- the officer's ped during the moment the suspect is held against them
local holdingNow = false -- this officer holds someone (checked every half second)
local posing = false     -- this officer's hand is resting on a held arm
local nextPose = 0
local pausePoseUntil = 0 -- getting in or out of a vehicle: don't play the pose over it
local seatToken = 0

local function letGo()
    if not attachedTo then return end
    local ped = PlayerPedId()
    if IsEntityAttachedToEntity(ped, attachedTo) then DetachEntity(ped, true, false) end
    attachedTo = nil
end

local function walkFor(style) return style.walk or Config.Escort.walk end

-- Keeps the arms in the cuffed pose: it's played again after falling over, getting up, or anything
-- else that stops it.
local function holdPose(ped, style)
    if IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedGettingUp(ped) or GetGameTimer() < pausePoseUntil then return end
    if not IsEntityPlayingAnim(ped, style.anim.dict, style.anim.clip, 3) then play(ped, style.anim, POSE_FLAGS, -1) end
end

-- Plays `want` on the legs (or nothing, when want is nil) and stops the other leg animation.
local function legs(ped, want, other)
    if other and IsEntityPlayingAnim(ped, other.dict, other.clip, 3) then StopAnimTask(ped, other.dict, other.clip, 2.0) end
    if want and not IsEntityPlayingAnim(ped, want.dict, want.clip, 3) then play(ped, want, LOOP, -1) end
end

-- While an officer holds this player by the arm: stay at their side, and walk or run when they do.
local function follow(ped, style)
    local officer = GlobalState[C.escortKey(myId())]
    local player = officer and GetPlayerFromServerId(officer) or -1
    local officerPed = player ~= -1 and GetPlayerPed(player) or 0
    if officerPed == 0 or not DoesEntityExist(officerPed) or IsPedInAnyVehicle(ped, false)
        or IsPedInAnyVehicle(officerPed, false) or IsEntityDead(ped) or IsEntityDead(officerPed) then
        return letGo()
    end
    if attachedTo ~= officerPed or not IsEntityAttachedToEntity(ped, officerPed) then
        letGo()
        -- Only take hold of an officer who is right here, with nothing in between: never pull this
        -- player across the map (an officer who respawned) or through a wall.
        if C.distance(GetEntityCoords(ped), GetEntityCoords(officerPed)) > HOLD_REACH or not canSee(ped, officerPed) then return end
        local o = Config.Escort.offset
        AttachEntityToEntity(ped, officerPed, Config.Escort.bone, o[1], o[2], o[3],
            0.0, 0.0, 0.0, false, false, false, false, 2, true)
        attachedTo = officerPed
    end
    local walk, run = walkFor(style), Config.Escort.run
    if IsPedRunning(officerPed) or IsPedSprinting(officerPed) then
        legs(ped, run or walk, run and walk or nil)
    elseif IsPedWalking(officerPed) then
        legs(ped, walk, run)
    else
        legs(ped, nil, walk)
        legs(ped, nil, run)
    end
end

-- When this player is cuffed and nobody holds them, stop any leg animation left from being walked along.
local function standAlone(ped, style)
    legs(ped, nil, walkFor(style))
    legs(ped, nil, Config.Escort.run)
end

local function putOn(ped)
    SetEnableHandcuffs(ped, true)
    SetCurrentPedWeapon(ped, UNARMED, true)
    SetPedCanPlayGestureAnims(ped, false)
    SetPedConfigFlag(ped, NO_SEAT_SHUFFLE, true)
    cuffedPed = ped
end

local function takeOff(ped)
    letGo()
    SetEnableHandcuffs(ped, false)
    SetPedCanPlayGestureAnims(ped, true)
    SetPedConfigFlag(ped, NO_SEAT_SHUFFLE, false)
    for _, style in pairs(Config.Styles) do
        StopAnimTask(ped, style.anim.dict, style.anim.clip, 2.0)
        standAlone(ped, style)
    end
    cuffedPed = nil
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local style = myStyle()
        local now = GetGameTimer()
        if now < holdStillUntil then
            for _, control in ipairs(MOVING) do DisableControlAction(0, control, true) end
        end
        if holdingNow then DisableControlAction(0, ENTER_VEHICLE, true) end -- /putin them first, or let go
        if style then
            if cuffedPed ~= ped then putOn(ped) end
            if not IsPedCuffed(ped) then SetEnableHandcuffs(ped, true) end -- a revive may have cleared it
            for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end
            if not Config.CuffedCanRun then DisableControlAction(0, SPRINT, true) end
            DisablePlayerFiring(PlayerId(), true)
            if GetSelectedPedWeapon(ped) ~= UNARMED then SetCurrentPedWeapon(ped, UNARMED, true) end
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                for _, control in ipairs(DRIVING) do DisableControlAction(0, control, true) end
            end
            if attachedTo then
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
            end
            if now >= busyUntil then follow(ped, style) end -- the uncuff animation has its own line-up
            if now >= nextPose and now >= busyUntil then
                nextPose = now + 250
                if not attachedTo then standAlone(ped, style) end
                holdPose(ped, style)
            end
            Wait(0)
        elseif cuffedPed then
            takeOff(ped)
            Wait(0)
        else
            Wait((now < holdStillUntil or holdingNow) and 0 or 200)
        end
    end
end)

-- The server started the cuffs going on or coming off. Both players play their half; the suspect is
-- first held against the officer for a moment, so the officer's hands meet the suspect's wrists.
-- The officer stands still for the whole animation; the suspect only while held, so they can
-- still pull away before the cuffs close (if Config.SuspectCanPullAway).
RegisterNetEvent('Prest_Sector-Cuffs:animate', function(kind, role, partner, styleKey)
    if (kind ~= 'cuff' and kind ~= 'uncuff') or (role ~= 'officer' and role ~= 'suspect') or type(partner) ~= 'number' then return end
    local a = C.animationFor(Config, kind, styleKey)
    if not a then return end
    local ped = PlayerPedId()
    local ms = math.floor(a.seconds * 1000)
    busyUntil = GetGameTimer() + ms
    if role == 'officer' then
        holdStillUntil = busyUntil
        SetCurrentPedWeapon(ped, UNARMED, true)
        play(ped, a.officer, 0, ms)
        return
    end
    local lineUpMs = a.lineUp and (a.lineUp.ms or 950) or 0
    holdStillUntil = Config.SuspectCanPullAway and GetGameTimer() + lineUpMs or busyUntil
    local player = GetPlayerFromServerId(partner)
    local officerPed = player ~= -1 and GetPlayerPed(player) or 0
    local wearing = myStyle()
    if wearing then -- coming off: the cuffed pose would hold the arms still over the animation
        StopAnimTask(ped, wearing.anim.dict, wearing.anim.clip, 1.0)
        standAlone(ped, wearing)
    end
    local lineUp = a.lineUp and officerPed ~= 0 and not IsEntityDead(ped) and not IsPedRagdoll(ped)
        and not IsPedInAnyVehicle(ped, true) and canSee(ped, officerPed)
    if lineUp then
        letGo()
        local o = a.lineUp.offset
        AttachEntityToEntity(ped, officerPed, MIDDLE, o[1], o[2], o[3],
            0.0, 0.0, a.lineUp.heading or 0.0, false, false, false, false, 2, false)
        lineUpTo = officerPed
    end
    play(ped, a.suspect, 0, ms)
    if lineUp then
        Wait(lineUpMs)
        if IsEntityAttachedToEntity(ped, officerPed) then DetachEntity(ped, true, false) end
        lineUpTo = nil
    end
end)

-- While holding someone by the arm, the officer's hand rests on it (not while cuffing, aiming or
-- in a vehicle), and getting into a vehicle is blocked so the held player isn't dragged in.
CreateThread(function()
    while true do
        local pose = Config.Escort.officer
        local ped = PlayerPedId()
        holdingNow = not myStyle() and holding() ~= nil
        if pose and holdingNow and GetGameTimer() >= busyUntil and not IsPlayerFreeAiming(PlayerId())
            and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
            if not IsEntityPlayingAnim(ped, pose.dict, pose.clip, 3) then play(ped, pose, UPPER + ALONGSIDE + 2, -1) end
            posing = true
        elseif posing then
            if pose then StopAnimTask(ped, pose.dict, pose.clip, 2.0) end
            posing = false
        end
        Wait(500)
    end
end)

-- Load the animations up front, so the first arrest doesn't wait for them.
CreateThread(function()
    local function load(anim) if anim then loadDict(anim.dict) end end
    for _, style in pairs(Config.Styles) do
        load(style.anim)
        load(style.walk)
        for _, kind in ipairs({ 'cuff', 'uncuff' }) do
            local a = style[kind]
            if a then load(a.officer) load(a.suspect) end
        end
    end
    for _, a in pairs(Config.Animations) do load(a.officer) load(a.suspect) end
    load(Config.Escort.walk)
    load(Config.Escort.run)
    load(Config.Escort.officer)
end)

local function vehicleFromNet(netId)
    for _ = 1, 20 do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
        end
        Wait(100)
    end
    return nil
end

-- /putin: get into the seat the officer picked. The suspect is walked in by the game, and put in
-- directly if that doesn't work within a few seconds (a door that's blocked, for example), but only
-- if they're still cuffed, nobody holds them, and the vehicle is still right here and standing still.
RegisterNetEvent('Prest_Sector-Cuffs:seat', function(netId, seat)
    if not myStyle() or type(netId) ~= 'number' or type(seat) ~= 'number' then return end
    seatToken = seatToken + 1
    local token = seatToken
    local vehicle = vehicleFromNet(netId)
    if not vehicle or token ~= seatToken then return end
    for _ = 1, 10 do -- the server let go of this player's arm just before; wait until that arrives
        if GlobalState[C.escortKey(myId())] == nil then break end
        Wait(100)
    end
    letGo()
    local ped = PlayerPedId()
    pausePoseUntil = GetGameTimer() + 6000
    TaskEnterVehicle(ped, vehicle, 5000, seat, 1.0, 1, 0)
    for _ = 1, 50 do
        if GetVehiclePedIsIn(ped, false) == vehicle or token ~= seatToken then break end
        Wait(100)
    end
    if token == seatToken and GetVehiclePedIsIn(ped, false) ~= vehicle and IsVehicleSeatFree(vehicle, seat)
        and myStyle() and GlobalState[C.escortKey(myId())] == nil
        and C.distance(GetEntityCoords(ped), GetEntityCoords(vehicle)) <= Config.VehicleDistance + 2.0
        and GetEntitySpeed(vehicle) < 1.0 then
        ClearPedTasksImmediately(ped)
        SetPedIntoVehicle(ped, vehicle, seat)
    end
    pausePoseUntil = 0
end)

-- /takeout: climb out (straight out if the normal way is blocked); the officer then has them by the arm.
RegisterNetEvent('Prest_Sector-Cuffs:unseat', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not myStyle() then return end
    pausePoseUntil = GetGameTimer() + 4000
    TaskLeaveVehicle(ped, vehicle, 0)
    for _ = 1, 30 do
        if not IsPedInAnyVehicle(ped, false) then break end
        Wait(100)
    end
    if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, vehicle, 16) end
    pausePoseUntil = 0
end)

RegisterNetEvent('Prest_Sector-Cuffs:notify', function(message, tone)
    if type(message) == 'string' then notify(message, tone) end
end)

-- For other scripts on this player's game: exports['Prest_Sector-Cuffs']:IsCuffed().
exports('IsCuffed', function() return myStyle() ~= nil end)

-- Stopping the script leaves nobody stuck: cuffs off, let go of any officer, the officer's hand pose off.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    if lineUpTo and IsEntityAttachedToEntity(ped, lineUpTo) then DetachEntity(ped, true, false) end
    lineUpTo = nil
    if cuffedPed then takeOff(ped) end
    local pose = Config.Escort.officer
    if posing and pose then StopAnimTask(ped, pose.dict, pose.clip, 2.0) end
    posing = false
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/cuff', 'Cuff the nearest player', {
        { name = 'style', help = 'front or rear (optional: picked from where you stand)' },
    })
    TriggerEvent('chat:addSuggestion', '/uncuff', 'Take the cuffs off the nearest cuffed player')
    TriggerEvent('chat:addSuggestion', '/escort', 'Hold the nearest cuffed player by the arm, or let go')
    TriggerEvent('chat:addSuggestion', '/putin', 'Seat the player you are holding in the nearest vehicle')
    TriggerEvent('chat:addSuggestion', '/takeout', 'Bring a cuffed player out of the nearest vehicle')
    TriggerEvent('chat:addSuggestion', '/cuffadjust', 'Line the cuffs up on the wrists', {
        { name = 'style', help = 'rear or front' },
    })
    TriggerEvent('chat:addSuggestion', '/cuffhelp', 'List the cuff commands')
end)
