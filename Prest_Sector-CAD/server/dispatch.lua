-- Dispatch: units on duty, calls, 911 and 311, the panic button and where units are. The server
-- keeps the only copy of who is on duty and on which call; players' tablets get updates pushed to
-- them: everyone on duty, and anyone allowed to see the board who has their tablet open.

Dispatch = { handlers = {} }
local D = Dispatch
local C = CAD
local H = D.handlers
local fail, need, copy = Records.fail, Records.need, Records.copy

local units = {}        -- [src] = the unit they signed on as
local watchers = {}     -- [src] = true while a player who can see the board has the tablet open
local lastCall = {}     -- [src] = when they last called 911 or 311 (os.time)
local lastPanic = {}    -- [src] = when they last pressed panic (os.time)
local lastLocation = {} -- [src] = when they last sent where they are (GetGameTimer ms)
local unitsDirty = false

D.units = units
D.watchers = watchers

local MAX_NOTES = 200

local function now() return os.time() end

-- Set by server/main.lua: the 'me' object for a player (their roles, abilities and unit).
D.meOf = function() return nil end

-- ------------------------------------------------------------------ sending updates

local function send(src, kind, data) TriggerClientEvent(C.EVENT .. 'push', src, kind, data) end
D.send = send

function D.notify(src, text, tone) TriggerClientEvent(C.EVENT .. 'notify', src, text, tone or 'info') end

-- Everyone who sees the board: units on duty and watchers.
local function audience()
    local out = {}
    for src in pairs(units) do out[src] = true end
    for src in pairs(watchers) do out[src] = true end
    return out
end

local function broadcast(kind, data)
    for src in pairs(audience()) do send(src, kind, data) end
end

local function unitOut(u)
    return {
        id = u.id, name = u.name, callsign = u.callsign, department = u.department, role = u.role, status = u.status,
        callId = u.callId, location = copy(u.location), since = u.since, signedOnAt = u.signedOnAt,
    }
end
D.unitOut = unitOut

function D.unitList()
    local out = {}
    for _, u in pairs(units) do out[#out + 1] = unitOut(u) end
    table.sort(out, function(a, b) return a.callsign < b.callsign end)
    return out
end

function D.pushUnits()
    unitsDirty = false
    broadcast('units', D.unitList())
end

local function pushMe(src)
    local me = D.meOf(src)
    if me then send(src, 'me', me) end
end

local function callOut(call) return copy(call) end
D.callOut = callOut

local function pushCall(call) broadcast('call', callOut(call)) end
D.pushCall = pushCall

-- Whether a unit takes calls for a service: dispatch hears everything, Fire/EMS fire and EMS calls.
local function serves(unit, service)
    if service == 'all' or unit.role == 'dispatch' then return true end
    if unit.role == 'police' then return service == 'police' end
    if unit.role == 'fire' then return service == 'fire' or service == 'ems' end
    return false
end
D.serves = serves

local function alertUnits(call, kind)
    for src, unit in pairs(units) do
        if kind == 'panic' or serves(unit, call.service) then send(src, 'alert', { kind = kind, call = callOut(call) }) end
    end
end

-- ------------------------------------------------------------------ units

function D.unit(src) return units[src] end
function D.onDuty(src) return units[src] ~= nil end

local function autoStatus(unit, status)
    if Config.AutoStatus and C.byKey(Config.Statuses, status) then
        unit.status = status
        unit.since = now()
    end
end

local function note(call, by, text, system)
    call.notes = call.notes or {}
    call.notes[#call.notes + 1] = { at = now(), by = by, text = text, system = system == true }
    while #call.notes > MAX_NOTES do table.remove(call.notes, 1) end
end
D.note = note

local function saveCall(call)
    call.updatedAt = now()
    Store.save('call', call)
    pushCall(call)
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- Takes a unit off its call. by is who did it (a callsign or name), for the notes.
local function detach(call, unit, by, quiet)
    local kept = {}
    for _, id in ipairs(call.units or {}) do
        if id ~= unit.id then kept[#kept + 1] = id end
    end
    call.units = kept
    if call.primary == unit.id then call.primary = kept[1] end
    if #kept == 0 and call.status == 'active' then call.status = 'pending' end
    if unit.callId == call.id then
        unit.callId = nil
        autoStatus(unit, 'available')
    end
    if not quiet then note(call, by, ('%s left the call.'):format(unit.callsign), true) end
end

-- Puts a unit on a call (moving it off any other call first).
local function attach(call, unit, by)
    if unit.callId and unit.callId ~= call.id then
        local old = Store.get('call', unit.callId)
        if old then
            detach(old, unit, by)
            saveCall(old)
        end
        unit.callId = nil
    end
    if contains(call.units, unit.id) then return false end
    call.units[#call.units + 1] = unit.id
    call.primary = call.primary or unit.id
    if call.status == 'pending' then call.status = 'active' end
    unit.callId = call.id
    autoStatus(unit, 'enroute')
    note(call, by, ('%s attached.'):format(unit.callsign), true)
    return true
end

local CALLSIGN = '^[A-Z0-9][A-Z0-9 %-]*$'

function D.signOn(ctx, callsign, department)
    callsign = C.text(callsign, 40):upper()
    if callsign == '' or #callsign > 12 or not callsign:match(CALLSIGN) then
        fail('Pick a callsign of up to 12 letters, numbers, spaces or dashes.')
    end
    for src, u in pairs(units) do
        if src ~= ctx.src and u.callsign == callsign then fail('Another unit already has that callsign.') end
    end
    local dept = C.byKey(Config.Departments, department)
    if not dept or not contains(C.departmentsFor(Config, ctx.roles), department)
        or (type(dept.ace) == 'string' and dept.ace ~= '' and not IsPlayerAceAllowed(ctx.src, dept.ace)) then
        fail("You can't sign on with that department.")
    end
    local unit = units[ctx.src]
    if unit then
        unit.callsign, unit.department, unit.role, unit.name = callsign, dept.key, dept.role, ctx.name
    else
        unit = {
            id = ctx.src, name = ctx.name, callsign = callsign, department = dept.key, role = dept.role,
            status = Config.Statuses[1].key, callId = nil, location = nil, since = now(), signedOnAt = now(),
        }
        units[ctx.src] = unit
    end
    D.pushUnits()
    return unit
end

function D.signOff(src, why)
    local unit = units[src]
    if not unit then return false end
    if unit.callId then
        local call = Store.get('call', unit.callId)
        if call then
            detach(call, unit, unit.callsign, true)
            note(call, unit.callsign, ('%s %s.'):format(unit.callsign, why or 'signed off'), true)
            saveCall(call)
        end
    end
    units[src] = nil
    lastLocation[src] = nil
    D.pushUnits()
    return true
end

function D.setStatus(unit, status)
    if not C.byKey(Config.Statuses, status) then fail('Pick a valid status.') end
    unit.status = status
    unit.since = now()
    D.pushUnits()
    pushMe(unit.id)
    return unit
end

-- ------------------------------------------------------------------ calls

local function roundCoord(v) return math.floor(v * 10 + 0.5) / 10 end

-- Where a player is, from the server's own view of their ped (never from their game).
function D.coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local c = GetEntityCoords(ped)
    return { x = roundCoord(c.x), y = roundCoord(c.y), z = roundCoord(c.z) }
end

local function locationField(input)
    if type(input) ~= 'table' then return nil end
    local street = C.text(input.street, 80)
    local x, y, z = tonumber(input.x), tonumber(input.y), tonumber(input.z)
    local out = { street = street }
    if x and y and math.abs(x) <= 20000 and math.abs(y) <= 20000 then
        out.x, out.y, out.z = roundCoord(x), roundCoord(y), roundCoord(z and math.abs(z) <= 5000 and z or 0)
    end
    if not out.x and street == '' then return nil end
    return out
end
D.locationField = locationField

-- Makes a call, tells the board and alerts the units it's for. fields are already checked.
function D.newCall(fields)
    local code = C.byKey(Config.CallCodes, fields.code, 'code') or C.byKey(Config.CallCodes, '911', 'code')
    local call = {
        id = Store.nextId('call'),
        title = (fields.title and fields.title ~= '') and fields.title or code.label,
        code = code.code,
        priority = fields.priority or code.priority,
        service = fields.service or code.service,
        status = 'pending',
        description = fields.description or '',
        location = fields.location,
        caller = fields.caller,
        units = {},
        primary = nil,
        notes = {},
        disposition = nil,
        source = fields.source or 'script',
        createdAt = now(),
        closedAt = nil,
    }
    note(call, fields.by or call.source, fields.firstNote or 'Call created.', true)
    call.updatedAt = call.createdAt
    Store.save('call', call)
    pushCall(call)
    alertUnits(call, fields.alert or 'new')
    TriggerEvent(C.EVENT .. 'callCreated', callOut(call))
    return call
end

local function callOr(id)
    local call = Store.get('call', C.toInt(id, 1, 2147483647))
    if not call then fail('That call could not be found.') end
    return call
end

local function openCallOr(id)
    local call = callOr(id)
    if call.status == 'closed' then fail('That call is closed.') end
    return call
end

local function by(ctx) return ctx.unit and ctx.unit.callsign or ctx.name end

-- The unit an action is about: your own, or another one (which needs dispatch.manage).
local function targetUnit(ctx, unitId)
    if unitId == nil or C.toId(unitId) == ctx.src then
        if not ctx.unit then fail("You aren't on duty.") end
        return ctx.unit
    end
    need(ctx, 'dispatch.manage')
    local unit = units[C.toId(unitId) or -1]
    if not unit then fail('That unit is not on duty.') end
    return unit
end

local function canWorkCall(ctx, call)
    return ctx.abilities['dispatch.manage'] or (ctx.unit ~= nil and contains(call.units, ctx.unit.id))
end

function D.closeCall(call, disposition, who)
    for _, id in ipairs(copy(call.units)) do
        local unit = units[id]
        if unit then
            detach(call, unit, who, true)
            pushMe(unit.id)
        end
    end
    call.units, call.primary = {}, nil
    call.status = 'closed'
    call.disposition = disposition
    call.closedAt = now()
    note(call, who, ('Closed: %s.'):format(disposition), true)
    saveCall(call)
    D.pushUnits()
    return call
end

local function sortCalls(list)
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.createdAt < b.createdAt
    end)
    return list
end

H['unit.signOn'] = function(ctx, p)
    need(ctx, 'unit.signon')
    p = type(p) == 'table' and p or {}
    local unit = D.signOn(ctx, p.callsign, p.department)
    ctx.unit = unit
    return D.meOf(ctx.src)
end

H['unit.signOff'] = function(ctx)
    D.signOff(ctx.src)
    return D.meOf(ctx.src)
end

H['unit.status'] = function(ctx, p)
    p = type(p) == 'table' and p or {}
    local unit = targetUnit(ctx, p.unit)
    D.setStatus(unit, p.status)
    return unitOut(unit)
end

H['unit.list'] = function(ctx)
    need(ctx, 'dispatch.view')
    return D.unitList()
end

H['call.list'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    local open, closed = {}, {}
    for _, call in ipairs(Store.list('call')) do
        if call.status == 'closed' then closed[#closed + 1] = call else open[#open + 1] = callOut(call) end
    end
    sortCalls(open)
    if type(p) == 'table' and p.closed then
        table.sort(closed, function(a, b) return (a.closedAt or 0) > (b.closedAt or 0) end)
        for i = 1, math.min(#closed, 50) do open[#open + 1] = callOut(closed[i]) end
    end
    return open
end

H['call.get'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    return callOut(callOr(type(p) == 'table' and p.id))
end

H['call.create'] = function(ctx, p)
    need(ctx, 'calls.create')
    p = type(p) == 'table' and p or {}
    local code = C.byKey(Config.CallCodes, p.code, 'code')
    if not code then fail('Pick a call type.') end
    local priority = code.priority
    if p.priority ~= nil then
        priority = C.toInt(p.priority, 1, 3)
        if not priority then fail('Pick a priority from 1 to 3.') end
    end
    local service = p.service ~= nil and p.service or code.service
    if not C.byKey(Config.Services, service) then fail('Pick who the call is for.') end
    local location
    if p.useMyLocation then
        location = D.coordsOf(ctx.src)
        if not location then fail("Your location couldn't be found.") end
        location.street = ctx.unit and ctx.unit.location and ctx.unit.location.street or ''
    else
        location = locationField(p.location)
    end
    local dispatcher = not ctx.unit or ctx.unit.role == 'dispatch'
    local call = D.newCall({
        code = code.code, title = C.text(p.title, 80), priority = priority, service = service,
        description = C.text(p.description, 2000), location = location, source = dispatcher and 'dispatch' or 'unit',
        by = by(ctx), firstNote = ('Call created by %s.'):format(by(ctx)),
    })
    -- A unit that makes a call (a traffic stop, say) is on it straight away.
    if not dispatcher then
        attach(call, ctx.unit, by(ctx))
        saveCall(call)
        D.pushUnits()
        pushMe(ctx.src)
    end
    return callOut(call)
end

H['call.update'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    p = type(p) == 'table' and p or {}
    local call = openCallOr(p.id)
    if not canWorkCall(ctx, call) then fail('Only units on the call or dispatch can change it.') end
    local changed = {}
    if p.code ~= nil then
        local code = C.byKey(Config.CallCodes, p.code, 'code')
        if not code then fail('Pick a call type.') end
        if code.code ~= call.code then call.code = code.code; changed[#changed + 1] = 'type' end
    end
    if p.title ~= nil then
        local title = C.text(p.title, 80)
        if title == '' then fail('Enter a title.') end
        if title ~= call.title then call.title = title; changed[#changed + 1] = 'title' end
    end
    if p.priority ~= nil then
        local priority = C.toInt(p.priority, 1, 3)
        if not priority then fail('Pick a priority from 1 to 3.') end
        if priority ~= call.priority then call.priority = priority; changed[#changed + 1] = 'priority' end
    end
    if p.service ~= nil then
        if not C.byKey(Config.Services, p.service) then fail('Pick who the call is for.') end
        if p.service ~= call.service then call.service = p.service; changed[#changed + 1] = 'service' end
    end
    if p.description ~= nil then
        local description = C.text(p.description, 2000)
        if description ~= call.description then call.description = description; changed[#changed + 1] = 'description' end
    end
    if p.location ~= nil then
        call.location = locationField(p.location)
        changed[#changed + 1] = 'location'
    end
    if #changed > 0 then
        note(call, by(ctx), ('%s changed the %s.'):format(by(ctx), table.concat(changed, ', ')), true)
        saveCall(call)
    end
    return callOut(call)
end

H['call.attach'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    p = type(p) == 'table' and p or {}
    local call = openCallOr(p.id)
    local unit = targetUnit(ctx, p.unit)
    if attach(call, unit, by(ctx)) then
        saveCall(call)
        D.pushUnits()
        pushMe(unit.id)
        if unit.id ~= ctx.src then send(unit.id, 'alert', { kind = 'attached', call = callOut(call) }) end
    end
    return callOut(call)
end

H['call.detach'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    p = type(p) == 'table' and p or {}
    local call = openCallOr(p.id)
    local unit = targetUnit(ctx, p.unit)
    if not contains(call.units, unit.id) then fail('That unit is not on this call.') end
    detach(call, unit, by(ctx))
    saveCall(call)
    D.pushUnits()
    pushMe(unit.id)
    return callOut(call)
end

H['call.note'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    p = type(p) == 'table' and p or {}
    local call = callOr(p.id)
    if not canWorkCall(ctx, call) then fail('Only units on the call or dispatch can add notes.') end
    local text = C.text(p.text, 500)
    if text == '' then fail('Write the note first.') end
    note(call, by(ctx), text, false)
    saveCall(call)
    return callOut(call)
end

H['call.close'] = function(ctx, p)
    need(ctx, 'dispatch.view')
    p = type(p) == 'table' and p or {}
    local call = openCallOr(p.id)
    local primary = ctx.unit ~= nil and call.primary == ctx.unit.id
    if not ctx.abilities['dispatch.manage'] and not primary then fail('Only dispatch or the primary unit can close a call.') end
    local disposition
    for _, d in ipairs(Config.Dispositions) do
        if d == p.disposition then disposition = d end
    end
    if not disposition then fail('Pick how the call ended.') end
    return callOut(D.closeCall(call, disposition, by(ctx)))
end

H['call.reopen'] = function(ctx, p)
    need(ctx, 'dispatch.manage')
    local call = callOr(type(p) == 'table' and p.id)
    if call.status ~= 'closed' then fail('That call is already open.') end
    call.status = 'pending'
    call.closedAt, call.disposition = nil, nil
    note(call, by(ctx), ('Reopened by %s.'):format(by(ctx)), true)
    saveCall(call)
    return callOut(call)
end

-- ------------------------------------------------------------------ 911, panic and locations

-- /911, /311 and anonymous tips from any player. The position comes from the server, not their game.
function D.emergency(src, kind, text, street, callerName)
    local cfg = Config.Emergency or {}
    if kind ~= '911' and kind ~= '311' and kind ~= 'anon' then return end
    if kind == 'anon' and (cfg.anonymousCommand or '') == '' then return end
    text = C.text(text, 300)
    if text == '' then return D.notify(src, 'Say what is happening, for example: /911 a car crashed on Route 68', 'error') end
    local wait = (cfg.cooldownSeconds or 30) - (now() - (lastCall[src] or -math.huge))
    if wait > 0 then return D.notify(src, ('Wait %d seconds before calling again.'):format(math.ceil(wait)), 'error') end
    lastCall[src] = now()
    local location = D.coordsOf(src)
    if location then location.street = C.text(street, 80) end
    local anonymous = kind == 'anon'
    local code = kind == '311' and (C.byKey(Config.CallCodes, '311', 'code') and '311' or '911') or '911'
    local call = D.newCall({
        code = code, title = C.text(text, 80), description = text, location = location,
        caller = { name = anonymous and 'Anonymous' or callerName, anonymous = anonymous },
        source = kind, by = kind == '311' and '311' or '911',
        firstNote = anonymous and 'Anonymous tip received.' or ('Call received from %s.'):format(callerName),
    })
    local anyone = next(units) ~= nil
    D.notify(src, anyone and ('Your call was sent to dispatch (#%d).'):format(call.id)
        or ('Your call was logged (#%d), but nobody is on duty right now.'):format(call.id), anyone and 'success' or 'warning')
    return call
end

-- The panic button: a priority 1 call where the unit is, every unit told.
function D.panic(src, street)
    local unit = units[src]
    if not unit then return D.notify(src, 'The panic button works while you are on duty.', 'error') end
    local wait = (Config.Panic.cooldownSeconds or 15) - (now() - (lastPanic[src] or -math.huge))
    if wait > 0 then return D.notify(src, ('Your panic alert went out. You can press it again in %d seconds.'):format(math.ceil(wait)), 'warning') end
    lastPanic[src] = now()
    local location = D.coordsOf(src) or (unit.location and copy(unit.location))
    if location then
        location.street = C.text(street, 80)
        if location.street == '' and unit.location then location.street = unit.location.street or '' end
    end
    local code = C.byKey(Config.CallCodes, '10-99', 'code') and '10-99' or '911'
    local call = D.newCall({
        code = code, title = ('PANIC: %s needs help'):format(unit.callsign), priority = 1, service = 'all',
        description = ('%s (%s) pressed the panic button.'):format(unit.callsign, unit.name), location = location,
        source = 'panic', by = unit.callsign, firstNote = ('%s pressed the panic button.'):format(unit.callsign), alert = 'panic',
    })
    attach(call, unit, unit.callsign)
    unit.status = 'panic'
    unit.since = now()
    saveCall(call)
    D.pushUnits()
    pushMe(src)
    return call
end

-- A unit on duty saying where they are. The server reads the coordinates itself; only the street
-- name comes from their game.
function D.location(src, street)
    local unit = units[src]
    if not unit then return end
    local t = GetGameTimer()
    if lastLocation[src] and t - lastLocation[src] < 2000 then return end
    lastLocation[src] = t
    local location = D.coordsOf(src)
    if not location then return end
    location.street = C.text(street, 80)
    unit.location = location
    unitsDirty = true
end

-- Called every Config.LocationSeconds: sends unit positions if any moved.
function D.tick()
    if unitsDirty then D.pushUnits() end
end

function D.watch(src, open, canView)
    watchers[src] = (open and canView) or nil
end

-- A player left: off duty, off the board.
function D.dropped(src)
    D.signOff(src, 'left the server')
    watchers[src], lastCall[src], lastPanic[src], lastLocation[src] = nil, nil, nil, nil
end
