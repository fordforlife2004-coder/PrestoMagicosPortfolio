-- 911 and 311 calls, the panic button, telling the server where you are while on duty, and map blips
-- for units and calls with a route to the call you're on.

local C = CAD
local K = CadClient
local EVENT = C.EVENT

local onDuty = false
local locationLoop = 0   -- bumped to stop the old loop when a new one starts
local unitBlips = {}     -- [unitId] = blip
local callBlips = {}     -- [callId] = blip
local flashing = {}      -- [callId] = game time to stop flashing

-- ------------------------------------------------------------------ where you are

-- "Strawberry Ave / Davis Ave, Strawberry" for where the player stands.
function K.street()
    local c = GetEntityCoords(PlayerPedId())
    local main, cross = GetStreetNameAtCoord(c.x, c.y, c.z)
    local out = GetStreetNameFromHashKey(main) or ''
    if cross and cross ~= 0 then
        local name = GetStreetNameFromHashKey(cross)
        if name and name ~= '' then out = out .. ' / ' .. name end
    end
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    if zone and zone ~= '' and zone ~= 'NULL' then out = out ~= '' and (out .. ', ' .. zone) or zone end
    return out
end

-- ------------------------------------------------------------------ 911, 311 and anonymous tips

local function callCommand(kind, usage)
    return function(_, args)
        local text = table.concat(args or {}, ' ')
        if text:match('^%s*$') then return K.notify(usage, 'error') end
        TriggerServerEvent(EVENT .. '911', kind, text, K.street())
    end
end

local E = Config.Emergency or {}
if E.command and E.command ~= '' then
    RegisterCommand(E.command, callCommand('911', ('Say what is happening, for example: /%s a car crashed on Route 68'):format(E.command)), false)
    TriggerEvent('chat:addSuggestion', '/' .. E.command, 'Call emergency services', { { name = 'what happened', help = 'Tell them what is going on' } })
end
if E.nonEmergencyCommand and E.nonEmergencyCommand ~= '' then
    RegisterCommand(E.nonEmergencyCommand, callCommand('311', ('Say what is happening, for example: /%s loud music next door'):format(E.nonEmergencyCommand)), false)
    TriggerEvent('chat:addSuggestion', '/' .. E.nonEmergencyCommand, 'Call the police about something that is not an emergency',
        { { name = 'what happened', help = 'Tell them what is going on' } })
end
if E.anonymousCommand and E.anonymousCommand ~= '' then
    RegisterCommand(E.anonymousCommand, callCommand('anon', ('Say what you saw, for example: /%s drugs being sold at the park'):format(E.anonymousCommand)), false)
    TriggerEvent('chat:addSuggestion', '/' .. E.anonymousCommand, 'Give the police an anonymous tip', { { name = 'tip', help = 'What you saw' } })
end

-- ------------------------------------------------------------------ the panic button

function K.panic()
    if not onDuty then return K.notify('The panic button works while you are on duty.', 'error') end
    TriggerServerEvent(EVENT .. 'panic', K.street())
end

RegisterCommand('panic', function() K.panic() end, false)
RegisterKeyMapping('panic', 'CAD panic button (on duty)', 'keyboard', Config.Keys.panic or '')

-- ------------------------------------------------------------------ blips

-- Blip colours close to a department colour from config.lua ('#3b82f6' and so on).
local PALETTE = {
    { 3, 93, 173, 226 }, { 38, 38, 92, 218 }, { 1, 224, 50, 50 }, { 2, 114, 204, 114 }, { 5, 240, 200, 20 },
    { 17, 240, 147, 46 }, { 27, 171, 60, 230 }, { 4, 240, 240, 240 }, { 56, 173, 125, 69 }, { 18, 100, 210, 230 },
}

function K.blipColour(hex)
    local r, g, b = tostring(hex or ''):match('^#?(%x%x)(%x%x)(%x%x)$')
    if not r then return 3 end
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    local best, bestDist = 3, math.huge
    for _, p in ipairs(PALETTE) do
        local d = (p[2] - r) ^ 2 + (p[3] - g) ^ 2 + (p[4] - b) ^ 2
        if d < bestDist then best, bestDist = p[1], d end
    end
    return best
end

local function setName(blip, name)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(name)
    EndTextCommandSetBlipName(blip)
end

local function removeAll(blips)
    for key, blip in pairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        blips[key] = nil
    end
end

-- Other units on the map, moved in place as they drive.
local function drawUnits()
    if not onDuty or not Config.UnitBlips then return removeAll(unitBlips) end
    local seen = {}
    local myId = K.me and K.me.id
    for _, u in ipairs(K.units or {}) do
        local loc = u.location
        if u.id ~= myId and loc and loc.x and loc.y then
            seen[u.id] = true
            local blip = unitBlips[u.id]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(loc.x + 0.0, loc.y + 0.0, (loc.z or 0) + 0.0)
                SetBlipSprite(blip, 1)
                SetBlipScale(blip, 0.8)
                SetBlipAsShortRange(blip, false)
                unitBlips[u.id] = blip
            else
                SetBlipCoords(blip, loc.x + 0.0, loc.y + 0.0, (loc.z or 0) + 0.0)
            end
            local dept = C.byKey(Config.Departments, u.department)
            SetBlipColour(blip, u.status == 'panic' and 1 or K.blipColour(dept and dept.color))
            setName(blip, u.callsign)
        end
    end
    for id, blip in pairs(unitBlips) do
        if not seen[id] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            unitBlips[id] = nil
        end
    end
end

-- Open calls on the map, coloured by priority, with a route to the one you're on.
local function drawCalls()
    if not onDuty then return removeAll(callBlips) end
    local cfg = Config.CallBlips or {}
    local mine = K.me and K.me.unit and K.me.unit.callId
    local seen = {}
    for id, call in pairs(K.calls or {}) do
        local loc = call.location
        if call.status ~= 'closed' and loc and loc.x and loc.y then
            seen[id] = true
            local blip = callBlips[id]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(loc.x + 0.0, loc.y + 0.0, (loc.z or 0) + 0.0)
                callBlips[id] = blip
            else
                SetBlipCoords(blip, loc.x + 0.0, loc.y + 0.0, (loc.z or 0) + 0.0)
            end
            SetBlipSprite(blip, call.source == 'panic' and (cfg.panicSprite or 161) or (cfg.sprite or 280))
            SetBlipColour(blip, (cfg.colours or {})[call.priority] or 5)
            SetBlipScale(blip, call.priority == 1 and 1.0 or 0.85)
            setName(blip, ('#%d %s %s'):format(call.id, call.code or '', call.title or ''))
            SetBlipRoute(blip, mine == id)
            if mine == id then SetBlipRouteColour(blip, (cfg.colours or {})[call.priority] or 5) end
            SetBlipFlashes(blip, flashing[id] ~= nil and GetGameTimer() < flashing[id])
        end
    end
    for id, blip in pairs(callBlips) do
        if not seen[id] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            callBlips[id] = nil
            flashing[id] = nil
        end
    end
end

K.drawUnits, K.drawCalls = drawUnits, drawCalls
K.unitBlips, K.callBlips = unitBlips, callBlips

-- ------------------------------------------------------------------ on duty

-- While on duty: tell the server where you are every Config.LocationSeconds.
local function startLocationLoop()
    locationLoop = locationLoop + 1
    local mine = locationLoop
    CreateThread(function()
        while onDuty and locationLoop == mine do
            TriggerServerEvent(EVENT .. 'location', K.street())
            Wait(math.max(1, tonumber(Config.LocationSeconds) or 5) * 1000)
        end
    end)
end

K.on('me', function(me)
    local now = me.unit ~= nil
    if now and not onDuty then
        onDuty = true
        startLocationLoop()
    elseif not now and onDuty then
        onDuty = false
        locationLoop = locationLoop + 1
    end
    drawUnits()
    drawCalls()
end)

K.on('units', drawUnits)
K.on('call', drawCalls)
K.on('calls', drawCalls)

-- Alerts for units on duty: a sound, a notification, and a flashing blip for a panic.
K.on('alert', function(alert)
    if not onDuty or type(alert) ~= 'table' or type(alert.call) ~= 'table' then return end
    local call = alert.call
    K.calls[call.id] = call
    local sound = (Config.Sounds or {})[alert.kind == 'panic' and 'panic' or alert.kind == 'attached' and 'attached' or 'newCall']
    if sound then PlaySoundFrontend(-1, sound.name, sound.set, true) end
    local where = call.location and call.location.street and call.location.street ~= '' and (' - ' .. call.location.street) or ''
    local what = alert.kind == 'panic' and 'PANIC' or alert.kind == 'attached' and 'You were put on' or 'New call'
    K.notify(('%s #%d %s %s%s'):format(what, call.id, call.code or '', call.title or '', where), alert.kind == 'panic' and 'error' or 'info')
    if alert.kind == 'panic' then flashing[call.id] = GetGameTimer() + (Config.Panic.blipSeconds or 120) * 1000 end
    if alert.kind == 'attached' and call.location and call.location.x then
        SetNewWaypoint(call.location.x + 0.0, call.location.y + 0.0)
    end
    drawCalls()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    onDuty = false
    locationLoop = locationLoop + 1
    removeAll(unitBlips)
    removeAll(callBlips)
end)
