-- The server's front door. Every request from a tablet comes in as one 'rpc' event: the server works
-- out who is asking (Bridge), checks they're allowed (shared/cad.lua's abilities), runs the request
-- (Records or Dispatch) and sends the answer back. Requests are rate limited, and a bug in one
-- request is logged here instead of breaking the CAD for everyone.

local C = CAD
local EVENT = C.EVENT

local RATE_LIMIT, RATE_WINDOW = 40, 10 -- requests per player in that many seconds
local rates = {}                         -- [src] = { start, count }
local ready = false

-- ------------------------------------------------------------------ who is asking

local function ctxOf(src)
    local roles = Bridge.roles(src)
    return {
        src = src, name = Bridge.name(src), roles = roles, abilities = C.abilities(Config, roles),
        license = Bridge.license(src), unit = Dispatch.unit(src),
    }
end

-- The departments a player can sign on with, including each department's own ACE.
local function departmentsOf(src, roles)
    local out = {}
    for _, key in ipairs(C.departmentsFor(Config, roles)) do
        local dept = C.byKey(Config.Departments, key)
        if type(dept.ace) ~= 'string' or dept.ace == '' or IsPlayerAceAllowed(src, dept.ace) then out[#out + 1] = key end
    end
    return out
end

-- What the tablet knows about you.
local function meOf(src)
    local ctx = ctxOf(src)
    return {
        id = src, name = ctx.name, roles = ctx.roles, abilities = ctx.abilities,
        unit = ctx.unit and Dispatch.unitOut(ctx.unit) or nil,
        departments = departmentsOf(src, ctx.roles), reportTypes = C.reportTypesFor(Config, ctx.roles),
    }
end
Dispatch.meOf = meOf

-- ------------------------------------------------------------------ requests

local handlers = {}
for name, fn in pairs(Records.handlers) do handlers[name] = fn end
for name, fn in pairs(Dispatch.handlers) do handlers[name] = fn end
handlers['session'] = function(ctx) return { me = meOf(ctx.src), config = C.publicConfig(Config) } end

local function limited(src)
    local t = os.time()
    local r = rates[src]
    if not r or t - r.start >= RATE_WINDOW then
        rates[src] = { start = t, count = 1 }
        return false
    end
    r.count = r.count + 1
    return r.count > RATE_LIMIT
end

RegisterNetEvent(EVENT .. 'rpc', function(reqId, action, payload)
    local src = C.toId(source)
    reqId = C.toInt(reqId, 0, 2147483647)
    if not src or not reqId then return end
    local function reply(ok, result) TriggerClientEvent(EVENT .. 'reply', src, reqId, ok, result) end
    if not ready then return reply(false, 'The CAD is still starting. Try again in a moment.') end
    if type(action) ~= 'string' or not handlers[action] then return reply(false, "The CAD doesn't know that request.") end
    if payload ~= nil and type(payload) ~= 'table' then return reply(false, 'Something was missing from that request.') end
    if limited(src) then return reply(false, 'Slow down a little.') end
    local ctx = ctxOf(src)
    -- Someone who lost their police (or fire, or dispatch) role while on duty is signed off.
    if ctx.unit and not ctx.abilities['unit.signon'] then
        Dispatch.signOff(src, 'lost access to the CAD')
        ctx.unit = nil
    end
    local ok, result = pcall(handlers[action], ctx, payload or {})
    if ok then return reply(true, result) end
    if type(result) == 'table' and result.userError then return reply(false, result.userError) end
    print(('[Prest_Sector-CAD] %s failed for player %d: %s'):format(action, src, tostring(result)))
    reply(false, 'Something went wrong on the server. Try again.')
end)

-- The tablet opened or closed: players who can see the board get live updates while it's open.
RegisterNetEvent(EVENT .. 'watch', function(open)
    local src = C.toId(source)
    if not src then return end
    Dispatch.watch(src, open == true, open == true and ctxOf(src).abilities['dispatch.view'] == true)
end)

RegisterNetEvent(EVENT .. '911', function(kind, text, street)
    local src = C.toId(source)
    if not src or not ready then return end
    Dispatch.emergency(src, kind, text, street, Bridge.name(src))
end)

RegisterNetEvent(EVENT .. 'panic', function(street)
    local src = C.toId(source)
    if not src or not ready then return end
    Dispatch.panic(src, street)
end)

RegisterNetEvent(EVENT .. 'location', function(street)
    local src = C.toId(source)
    if not src then return end
    Dispatch.location(src, street)
end)

AddEventHandler('playerDropped', function()
    local src = C.toId(source)
    if not src then return end
    Dispatch.dropped(src)
    rates[src] = nil
end)

-- ------------------------------------------------------------------ for other scripts

-- exports['Prest_Sector-CAD']:CreateCall({ title = 'Store robbery', code = '10-90', coords = GetEntityCoords(ped),
--   street = 'Innocence Blvd' }) puts a call on the board and alerts units. Returns the call number.
exports('CreateCall', function(data)
    if not ready or type(data) ~= 'table' then return nil end
    local location
    local coords = data.coords
    if coords ~= nil and (type(coords) == 'table' or type(coords) == 'vector3' or type(coords) == 'vector4') then
        location = Dispatch.locationField({ x = coords.x, y = coords.y, z = coords.z, street = data.street })
    elseif data.street then
        location = Dispatch.locationField({ street = data.street })
    end
    local code = C.byKey(Config.CallCodes, data.code, 'code') and data.code or '911'
    local service = C.byKey(Config.Services, data.service) and data.service or nil
    local call = Dispatch.newCall({
        code = code, title = C.text(data.title, 80), priority = data.priority ~= nil and C.toInt(data.priority, 1, 3) or nil,
        service = service, description = C.text(data.description, 2000), location = location,
        caller = data.caller and { name = C.text(data.caller, 40), anonymous = false } or nil,
        source = 'script', by = GetInvokingResource and GetInvokingResource() or 'script',
    })
    return call.id
end)

exports('AddCallNote', function(id, text)
    local call = Store.get('call', id)
    text = C.text(text, 500)
    if not call or text == '' then return false end
    Dispatch.note(call, GetInvokingResource and GetInvokingResource() or 'script', text, false)
    call.updatedAt = os.time()
    Store.save('call', call)
    Dispatch.pushCall(call)
    return true
end)

exports('CloseCall', function(id, disposition)
    local call = Store.get('call', id)
    if not call or call.status == 'closed' then return false end
    local chosen = Config.Dispositions[1]
    for _, d in ipairs(Config.Dispositions) do
        if d == disposition then chosen = d end
    end
    Dispatch.closeCall(call, chosen, GetInvokingResource and GetInvokingResource() or 'script')
    return true
end)

exports('GetUnit', function(src)
    local unit = Dispatch.unit(C.toId(src) or -1)
    return unit and Dispatch.unitOut(unit) or nil
end)

exports('GetUnits', function() return Dispatch.unitList() end)

exports('IsOnDuty', function(src) return Dispatch.onDuty(C.toId(src) or -1) end)

exports('SetUnitStatus', function(src, status)
    local unit = Dispatch.unit(C.toId(src) or -1)
    if not unit then return false end
    return (pcall(Dispatch.setStatus, unit, status))
end)

exports('LookupPlate', function(plate)
    local ok, result = pcall(Records.plateCheck, plate)
    return ok and result or nil
end)

-- ------------------------------------------------------------------ starting up

local function every(ms, fn)
    local function loop()
        fn()
        SetTimeout(ms, loop)
    end
    SetTimeout(ms, loop)
end

CreateThread(function()
    for _, problem in ipairs(C.checkConfig(Config)) do print(('[Prest_Sector-CAD] config problem: %s'):format(problem)) end
    local backend = Store.init()
    local framework = Bridge.init()
    local pruned = Store.prune(os.time())
    print(('[Prest_Sector-CAD] ready. People: %d, vehicles: %d, reports: %d, calls: %d (%s storage%s)%s'):format(
        Store.count('person'), Store.count('vehicle'), Store.count('report'), Store.count('call'), backend,
        framework and (', ' .. framework .. ' names and jobs') or '', pruned > 0 and (', removed %d old calls'):format(pruned) or ''))
    ready = true
    every(math.max(1, tonumber(Config.LocationSeconds) or 5) * 1000, Dispatch.tick)
    every(6 * 3600 * 1000, function() Store.prune(os.time()) end)
end)

-- A framework started after the CAD: look for it again.
AddEventHandler('onResourceStart', function(resource)
    if resource == 'qb-core' or resource == 'qbx_core' or resource == 'es_extended' then Bridge.init() end
end)
