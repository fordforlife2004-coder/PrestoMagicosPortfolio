-- A small fake FiveM server for the tests: only the natives the CAD's server scripts use, kept in plain
-- tables. dofile it from a spec; it loads the CAD and returns helpers for the tests.

dofile('tests/json.lua')

local F = {
    players = {}, entities = {}, toClients = {}, handlers = {}, timers = {}, exports = {}, others = {},
    kvp = {}, resources = {}, logs = {}, local_events = {},
    now = 1793750400, -- 2026-11-03 00:00 UTC
    gameMs = 1000000,
}
local nextEntity = 100

-- ------------------------------------------------------------------ the world

os.time = function() return F.now end
function vector3(x, y, z) return { x = x, y = y, z = z } end
function GetHashKey(name) return 'hash:' .. name end
function Wait() end
function CreateThread(fn) fn() end
function SetTimeout(ms, fn) F.timers[#F.timers + 1] = { at = F.gameMs + ms, fn = fn } end
function GetGameTimer() return F.gameMs end
function GetCurrentResourceName() return 'Prest_Sector-CAD' end
function GetInvokingResource() return F.invoking end
function GetResourceState(name) return F.resources[name] or 'missing' end

local realPrint = rawget(_G, 'realPrint') or print
_G.realPrint = realPrint
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    F.logs[#F.logs + 1] = table.concat(parts, ' ')
end
F.realPrint = realPrint

-- exports('Name', fn) registers this script's export; exports['other']:Fn() calls another script's.
exports = setmetatable({}, {
    __call = function(_, name, fn) F.exports[name] = fn end,
    __index = function(_, resource) return F.others[resource] end,
})

-- Promises for oxmysql: the fake answers at once, so Await just returns the value.
promise = { new = function()
    return { resolve = function(self, value) self.value, self.done = value, true end }
end }
Citizen = { Await = function(p) return p.value end }

function AddEventHandler(name, fn)
    F.handlers[name] = F.handlers[name] or {}
    table.insert(F.handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerClientEvent(name, target, ...) F.toClients[#F.toClients + 1] = { name = name, target = target, args = { ... } } end
function TriggerEvent(name, ...)
    F.local_events[#F.local_events + 1] = { name = name, args = { ... } }
    for _, fn in ipairs(F.handlers[name] or {}) do fn(...) end
end
function RegisterCommand() end

-- ------------------------------------------------------------------ players

local function playerOf(id)
    local n = tonumber(id)
    return n and F.players[math.floor(n)] or nil
end
function GetPlayers()
    local out = {}
    for id in pairs(F.players) do out[#out + 1] = tostring(id) end
    table.sort(out)
    return out
end
function GetPlayerName(id) local p = playerOf(id) return p and p.name or nil end
function GetPlayerPed(id) local p = playerOf(id) return p and p.ped or 0 end
function IsPlayerAceAllowed(id, ace)
    local p = playerOf(id)
    return p ~= nil and p.aces[ace] == true
end
function GetPlayerIdentifierByType(id, kind)
    local p = playerOf(id)
    return p and kind == 'license' and p.license or nil
end
function GetPlayerIdentifiers(id)
    local p = playerOf(id)
    return p and p.license and { p.license } or {}
end
function DoesEntityExist(e) return F.entities[e] ~= nil end
function GetEntityCoords(e) return F.entities[e] and F.entities[e].coords or vector3(0.0, 0.0, 0.0) end

-- ------------------------------------------------------------------ server storage (KVP)

function SetResourceKvp(key, value) F.kvp[key] = value end
function GetResourceKvpString(key) return F.kvp[key] end
function DeleteResourceKvp(key) F.kvp[key] = nil end
local finds = {}
function StartFindKvp(prefix)
    local keys = {}
    for k in pairs(F.kvp) do
        if k:sub(1, #prefix) == prefix then keys[#keys + 1] = k end
    end
    table.sort(keys)
    finds[#finds + 1] = { keys = keys, i = 0 }
    return #finds
end
function FindKvp(handle)
    local f = finds[handle]
    f.i = f.i + 1
    return f.keys[f.i]
end
function EndFindKvp(handle) finds[handle] = nil end

-- ------------------------------------------------------------------ helpers for the tests

local function fire(name, ...)
    for _, fn in ipairs(F.handlers[name] or {}) do fn(...) end
end
F.fire = fire

-- Runs every timer due within seconds (default: all that are due now), moving the clocks along.
function F.flush(seconds)
    local untilMs = F.gameMs + (seconds or 0) * 1000
    local guard = 0
    while true do
        table.sort(F.timers, function(a, b) return a.at < b.at end)
        local timer = F.timers[1]
        if not timer or timer.at > untilMs then break end
        guard = guard + 1
        if guard > 10000 then error('timers never settle') end
        table.remove(F.timers, 1)
        F.gameMs = math.max(F.gameMs, timer.at)
        timer.fn()
    end
    F.gameMs = untilMs
end

-- Moves both clocks forward (os.time and the game timer).
function F.advance(seconds)
    F.now = F.now + seconds
    F.gameMs = F.gameMs + seconds * 1000
end

function F.addPlayer(id, name, opts)
    opts = opts or {}
    nextEntity = nextEntity + 1
    F.entities[nextEntity] = { coords = opts.coords or vector3(100.0, 200.0, 30.0) }
    local aces = {}
    for _, ace in ipairs(opts.aces or {}) do aces[ace] = true end
    F.players[id] = { name = name, aces = aces, license = opts.license == nil and ('license:' .. name:lower()) or opts.license or nil, ped = nextEntity }
    return F.players[id]
end

function F.moveTo(id, x, y, z) F.entities[F.players[id].ped].coords = vector3(x, y, z or 30.0) end

-- A player's game sending a net event.
function F.send(src, name, ...)
    source = src
    fire(name, ...)
end

local reqId = 0
-- Sends a tablet request and returns ok, result (or ok=false and the error sentence).
function F.rpc(src, action, payload)
    reqId = reqId + 1
    F.send(src, 'Prest_Sector-CAD:rpc', reqId, action, payload)
    for i = #F.toClients, 1, -1 do
        local m = F.toClients[i]
        if m.name == 'Prest_Sector-CAD:reply' and m.target == src and m.args[1] == reqId then return m.args[2], m.args[3] end
    end
    error('no reply to ' .. action)
end

-- Like F.rpc, but fails the test if the request was refused, and returns the result.
function F.must(src, action, payload)
    local ok, result = F.rpc(src, action, payload)
    if not ok then error(('%s was refused: %s'):format(action, tostring(result)), 2) end
    return result
end

-- The error sentence for a request that should be refused.
function F.refused(src, action, payload)
    local ok, result = F.rpc(src, action, payload)
    if ok then error(action .. ' should have been refused', 2) end
    return result
end

-- Pushes of one kind sent to a player since the last F.clear().
function F.pushes(target, kind)
    local out = {}
    for _, m in ipairs(F.toClients) do
        if m.name == 'Prest_Sector-CAD:push' and m.target == target and m.args[1] == kind then out[#out + 1] = m.args[2] end
    end
    return out
end

function F.notes(target)
    local out = {}
    for _, m in ipairs(F.toClients) do
        if m.name == 'Prest_Sector-CAD:notify' and m.target == target then out[#out + 1] = m.args[1] end
    end
    return out
end

function F.clear() F.toClients = {} end

function F.drop(id)
    source = id
    fire('playerDropped', 'Exiting')
    F.players[id] = nil
end

local FILES = { 'config.lua', 'shared/cad.lua', 'server/store.lua', 'server/bridge.lua', 'server/records.lua', 'server/dispatch.lua', 'server/main.lua' }

-- Loads the CAD (a fresh copy of every script, as when the server starts it). configure(Config) can
-- change settings before the server scripts read them.
function F.load(configure)
    F.handlers, F.timers, F.exports, F.toClients = {}, {}, {}, {}
    Config, CAD, Store, Bridge, Records, Dispatch = nil, nil, nil, nil, nil, nil
    dofile('config.lua')
    if configure then configure(Config) end
    for i = 2, #FILES do dofile(FILES[i]) end
end

-- Restarts the CAD: the saved storage stays, everything in memory starts again.
F.restart = F.load

F.runner = dofile('tests/runner.lua')

return F
