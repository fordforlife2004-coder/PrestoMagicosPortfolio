-- A small fake FiveM server for the radar's tests: only the natives server/main.lua uses, kept in plain
-- tables, plus a fake Prest_Sector-CAD whose exports the tests can set. dofile it from a spec.

dofile('tests/json.lua')

local F = {}

local realPrint = rawget(_G, 'realPrint') or print
_G.realPrint = realPrint

function F.reset()
    F.players, F.entities, F.toClients, F.handlers, F.timers = {}, {}, {}, {}, {}
    F.commands, F.exports, F.kvp, F.resources, F.logs, F.states = {}, {}, {}, {}, {}, {}
    F.now = 1793750400 -- 2026-11-03 00:00 UTC
    F.gameMs = 1000000
    F.cad = {}         -- the fake CAD's answers: units[src], plates[key], calls made
    F.cad.units, F.cad.plates, F.cad.calls, F.cad.lookups, F.cad.unitCalls = {}, {}, {}, 0, 0
    F.nextEntity = 100
    F.stateSets = 0
    F.deferThreads, F.threads = false, {}
end
F.reset()

-- ------------------------------------------------------------------ the world

os.time = function() return F.now end
function vector3(x, y, z) return { x = x, y = y, z = z } end
function Wait() end
-- Threads run at once, or (with F.deferThreads) wait for F.runThreads(), as on a real server, where they
-- start on the next tick.
function CreateThread(fn)
    if F.deferThreads then F.threads[#F.threads + 1] = fn else fn() end
end
function F.runThreads()
    local list = F.threads
    F.threads = {}
    for _, fn in ipairs(list) do fn() end
end
function SetTimeout(ms, fn) F.timers[#F.timers + 1] = { at = F.gameMs + ms, fn = fn } end
function GetGameTimer() return F.gameMs end
function GetCurrentResourceName() return 'Prest_Sector-Radar' end
function GetInvokingResource() return F.invoking end
function GetResourceState(name) return F.resources[name] or 'missing' end

print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    F.logs[#F.logs + 1] = table.concat(parts, ' ')
end

-- The fake CAD's exports, as another resource sees them: exports['Prest_Sector-CAD']:Name(...).
local cadExports = {
    GetUnit = function(_, src)
        F.cad.unitCalls = F.cad.unitCalls + 1
        return F.cad.units[tonumber(src)]
    end,
    LookupPlate = function(_, plate)
        F.cad.lookups = F.cad.lookups + 1
        if F.cad.broken then error('the CAD fell over') end
        return F.cad.plates[plate] or { plate = plate, found = false, alerts = { { text = 'No record of this plate.', tone = 'warning' } } }
    end,
    CreateCall = function(_, data)
        F.cad.calls[#F.cad.calls + 1] = data
        return #F.cad.calls
    end,
}

exports = setmetatable({}, {
    __call = function(_, name, fn) F.exports[name] = fn end,
    __index = function(_, resource)
        if resource == 'Prest_Sector-CAD' then return cadExports end
        return nil
    end,
})

function AddEventHandler(name, fn)
    F.handlers[name] = F.handlers[name] or {}
    table.insert(F.handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerClientEvent(name, target, ...) F.toClients[#F.toClients + 1] = { name = name, target = target, args = { ... } } end
function RegisterCommand(name, fn) F.commands[name] = fn end

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
function GetEntityCoords(e) return F.entities[e] and F.entities[e].coords or vector3(0.0, 0.0, 0.0) end

-- Player(src).state:set(key, value, replicated): kept in F.states[src][key].
function Player(src)
    local id = tonumber(src)
    return {
        state = {
            set = function(_, key, value, replicated)
                F.stateSets = F.stateSets + 1
                F.states[id] = F.states[id] or {}
                F.states[id][key] = value
                F.states[id].replicated = replicated
            end,
        },
    }
end

-- ------------------------------------------------------------------ server storage (KVP)

function SetResourceKvp(key, value) F.kvp[key] = value end
function GetResourceKvpString(key) return F.kvp[key] end

-- ------------------------------------------------------------------ helpers for the tests

local function fire(name, ...)
    for _, fn in ipairs(F.handlers[name] or {}) do fn(...) end
end
F.fire = fire

-- Runs every timer due within seconds, moving both clocks along.
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
        F.now = F.now + math.floor((timer.at - F.gameMs) / 1000)
        F.gameMs = math.max(F.gameMs, timer.at)
        timer.fn()
    end
    F.now = F.now + math.floor((untilMs - F.gameMs) / 1000)
    F.gameMs = untilMs
end

function F.advance(seconds)
    F.now = F.now + seconds
    F.gameMs = F.gameMs + seconds * 1000
end

function F.addPlayer(id, name, opts)
    opts = opts or {}
    F.nextEntity = F.nextEntity + 1
    F.entities[F.nextEntity] = { coords = opts.coords or vector3(100.0, 200.0, 30.0) }
    local aces = {}
    for _, ace in ipairs(opts.aces or {}) do aces[ace] = true end
    F.players[id] = { name = name, aces = aces, ped = F.nextEntity }
    return F.players[id]
end

-- A player's game sending a net event.
function F.send(src, name, ...)
    source = src
    fire(name, ...)
end

-- Runs a chat command as a player (0 is the server console).
function F.command(src, name, ...)
    F.commands[name](src, { ... }, name)
end

local reqId = 0
-- A plate check from a player's camera. Returns the server's answer.
function F.check(src, plate, camera)
    reqId = reqId + 1
    F.send(src, 'Prest_Sector-Radar:check', reqId, camera or 'front', plate)
    for i = #F.toClients, 1, -1 do
        local m = F.toClients[i]
        if m.name == 'Prest_Sector-Radar:result' and m.target == src and m.args[1] == reqId then return m.args[2] end
    end
    return nil
end

-- What a player was told with notifications since the last F.clear().
function F.notes(target)
    local out = {}
    for _, m in ipairs(F.toClients) do
        if m.name == 'Prest_Sector-Radar:notify' and m.target == target then out[#out + 1] = m.args[1] end
    end
    return out
end

function F.allowed(src) return F.states[src] and F.states[src].prestSectorRadar end

function F.logged(part)
    for _, line in ipairs(F.logs) do
        if line:find(part, 1, true) then return true end
    end
    return false
end

function F.clear() F.toClients = {} end

function F.drop(id)
    source = id
    fire('playerDropped', 'Exiting')
    F.players[id] = nil
end

-- Starts the radar (a fresh copy of every script). configure(Config) can change settings first. The
-- saved storage (F.kvp) stays, as on a real restart.
function F.load(configure)
    F.handlers, F.timers, F.exports, F.toClients, F.commands, F.states = {}, {}, {}, {}, {}, {}
    Config, Radar = nil, nil
    dofile('config.lua')
    if configure then configure(Config) end
    dofile('shared/radar.lua')
    dofile('server/main.lua')
end

F.runner = dofile('tests/runner.lua')

return F
