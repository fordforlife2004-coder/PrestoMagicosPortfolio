-- A small fake of one player's game for the client tests: the natives the CAD's client scripts use,
-- kept in plain tables, with threads that wait and timers that run as the test moves the clock.
-- dofile it from a spec; G.load() loads the client scripts.

dofile('tests/json.lua')

local G = {}

local function reset()
    G.now = 1000                      -- game time in ms
    G.threads, G.timers = {}, {}
    G.handlers, G.nuiCallbacks, G.commands, G.keys, G.exports = {}, {}, {}, {}, {}
    G.nui, G.toServer, G.feed, G.sounds, G.suggestions = {}, {}, {}, {}, {}
    G.blips, G.nextBlip = {}, 1
    G.entities, G.nextEntity = {}, 1000
    G.focus, G.waypoint = false, nil
    G.anims, G.stoppedAnims = {}, {}
    G.ped = 1
    G.entities[G.ped] = { kind = 'ped', coords = { x = 100.0, y = 200.0, z = 30.0 }, dead = false, vehicle = 0 }
    G.forward = { x = 0.0, y = 1.0, z = 0.0 }
    G.street = { main = 'Strawberry Ave', cross = 'Davis Ave', zone = 'STRAW', zoneLabel = 'Strawberry' }
    G.rayHit = nil                    -- the entity a plate-reader ray hits
    G.modelsLoad = true
end
reset()

-- ------------------------------------------------------------------ threads and time

local function runThread(t)
    local ok, wait = coroutine.resume(t.co)
    if not ok then error(wait, 0) end
    if coroutine.status(t.co) == 'dead' then t.done = true else t.wakeAt = G.now + (wait or 0) end
end

function CreateThread(fn)
    local t = { co = coroutine.create(fn), wakeAt = G.now }
    G.threads[#G.threads + 1] = t
    runThread(t)
end
Citizen = { CreateThread = CreateThread }

function Wait(ms)
    if coroutine.isyieldable() then coroutine.yield(ms or 0) end
end

function SetTimeout(ms, fn) G.timers[#G.timers + 1] = { at = G.now + ms, fn = fn } end
function GetGameTimer() return G.now end

-- Moves the game clock forward, running timers and waking threads as their time comes.
function G.tick(ms)
    local target = G.now + (ms or 0)
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 100000 then error('the game never settles') end
        local nextAt, nextKind, nextItem = math.huge, nil, nil
        for _, t in ipairs(G.timers) do
            if t.at < nextAt then nextAt, nextKind, nextItem = t.at, 'timer', t end
        end
        for _, t in ipairs(G.threads) do
            if not t.done and t.wakeAt < nextAt then nextAt, nextKind, nextItem = t.wakeAt, 'thread', t end
        end
        if not nextItem or nextAt > target then break end
        G.now = math.max(G.now, nextAt)
        if nextKind == 'timer' then
            for i, t in ipairs(G.timers) do
                if t == nextItem then table.remove(G.timers, i) break end
            end
            nextItem.fn()
        else
            runThread(nextItem)
        end
    end
    G.now = target
end

-- ------------------------------------------------------------------ events, commands, NUI

function GetCurrentResourceName() return 'Prest_Sector-CAD' end
function AddEventHandler(name, fn)
    G.handlers[name] = G.handlers[name] or {}
    table.insert(G.handlers[name], fn)
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
    if name == 'chat:addSuggestion' then G.suggestions[#G.suggestions + 1] = (...) end
    for _, fn in ipairs(G.handlers[name] or {}) do fn(...) end
end
function TriggerServerEvent(name, ...) G.toServer[#G.toServer + 1] = { name = name, args = { ... } } end
function RegisterCommand(name, fn) G.commands[name] = fn end
function RegisterKeyMapping(command, description, mapper, key) G.keys[command] = { description = description, key = key } end
function RegisterNUICallback(name, fn) G.nuiCallbacks[name] = fn end
function SendNUIMessage(message) G.nui[#G.nui + 1] = message end
function SetNuiFocus(keyboard, mouse) G.focus = keyboard and mouse end
exports = setmetatable({}, { __call = function(_, name, fn) G.exports[name] = fn end })

-- ------------------------------------------------------------------ the player, models and props

function PlayerPedId() return G.ped end
function GetEntityCoords(e) return G.entities[e] and G.entities[e].coords or { x = 0.0, y = 0.0, z = 0.0 } end
function GetEntityForwardVector() return G.forward end
function IsEntityDead(e) return G.entities[e] and G.entities[e].dead == true end
function GetVehiclePedIsIn(ped) return G.entities[ped].vehicle or 0 end
function IsPedInAnyVehicle(ped) return (G.entities[ped].vehicle or 0) ~= 0 end
function DoesEntityExist(e) return G.entities[e] ~= nil end
function DeleteEntity(e) G.entities[e] = nil end
function GetEntityType(e) return G.entities[e] and (G.entities[e].kind == 'vehicle' and 2 or 3) or 0 end
function GetHashKey(name) return 'hash:' .. name end
function IsModelInCdimage() return true end
function RequestModel() end
function HasModelLoaded() return G.modelsLoad end
function SetModelAsNoLongerNeeded() end
function RequestAnimDict() end
function HasAnimDictLoaded() return true end
function GetPedBoneIndex(_, bone) return bone end
function CreateObject(model, x, y, z, networked)
    G.nextEntity = G.nextEntity + 1
    G.entities[G.nextEntity] = { kind = 'object', model = model, coords = { x = x, y = y, z = z }, networked = networked }
    return G.nextEntity
end
function AttachEntityToEntity(e, to, bone) G.entities[e].attachedTo, G.entities[e].bone = to, bone end
function TaskPlayAnim(_, dict, clip) G.anims[#G.anims + 1] = dict .. '/' .. clip end
function StopAnimTask(_, dict, clip) G.stoppedAnims[#G.stoppedAnims + 1] = dict .. '/' .. clip end
function SetNewWaypoint(x, y) G.waypoint = { x = x, y = y } end
function PlaySoundFrontend(_, name, set) G.sounds[#G.sounds + 1] = name .. '/' .. set end

-- A vehicle in the world with a plate.
function G.addVehicle(plate, coords)
    G.nextEntity = G.nextEntity + 1
    G.entities[G.nextEntity] = { kind = 'vehicle', plate = plate, coords = coords or { x = 0.0, y = 0.0, z = 30.0 } }
    return G.nextEntity
end
function GetVehicleNumberPlateText(v) return G.entities[v] and G.entities[v].plate or nil end
function GetGamePool(kind)
    local out = {}
    if kind == 'CVehicle' then
        for id, e in pairs(G.entities) do
            if e.kind == 'vehicle' then out[#out + 1] = id end
        end
        table.sort(out)
    end
    return out
end
function GetOffsetFromEntityInWorldCoords(e, x, y, z)
    local c = GetEntityCoords(e)
    return { x = c.x + x, y = c.y + y, z = c.z + z }
end
function StartShapeTestCapsule() return 7 end
function GetShapeTestResult()
    if G.rayHit then return 2, 1, nil, nil, G.rayHit end
    return 2, 0, nil, nil, 0
end

-- ------------------------------------------------------------------ streets and text

function GetStreetNameAtCoord() return 'main', G.street.cross and 'cross' or 0 end
function GetStreetNameFromHashKey(hash)
    if hash == 'main' then return G.street.main end
    if hash == 'cross' then return G.street.cross end
    return ''
end
function GetNameOfZone() return G.street.zone end
function GetLabelText(label) return label == G.street.zone and G.street.zoneLabel or 'NULL' end

-- One text buffer, as in the game: Begin..., Add... pieces, then End... uses it.
local text = {}
function BeginTextCommandThefeedPost() text = {} end
function BeginTextCommandSetBlipName() text = {} end
function AddTextComponentSubstringPlayerName(piece) text[#text + 1] = piece end
function EndTextCommandThefeedPostTicker(important)
    G.feed[#G.feed + 1] = { text = table.concat(text), pieces = #text, important = important }
end

-- ------------------------------------------------------------------ blips

local function blip(id) return G.blips[id] end
function AddBlipForCoord(x, y, z)
    local id = G.nextBlip
    G.nextBlip = G.nextBlip + 1
    G.blips[id] = { x = x, y = y, z = z, moves = 0 }
    return id
end
function DoesBlipExist(id) return G.blips[id] ~= nil end
function RemoveBlip(id) G.blips[id] = nil end
function SetBlipCoords(id, x, y, z) local b = blip(id) b.x, b.y, b.z, b.moves = x, y, z, b.moves + 1 end
function SetBlipSprite(id, v) blip(id).sprite = v end
function SetBlipColour(id, v) blip(id).colour = v end
function SetBlipScale(id, v) blip(id).scale = v end
function SetBlipAsShortRange(id, v) blip(id).shortRange = v end
function SetBlipRoute(id, v) blip(id).route = v end
function SetBlipRouteColour(id, v) blip(id).routeColour = v end
function SetBlipFlashes(id, v) blip(id).flashes = v end
function EndTextCommandSetBlipName(id) blip(id).name = table.concat(text) end

-- ------------------------------------------------------------------ helpers for the tests

function G.blipCount()
    local n = 0
    for _ in pairs(G.blips) do n = n + 1 end
    return n
end

function G.blipNamed(name)
    for id, b in pairs(G.blips) do
        if b.name == name then return b, id end
    end
    return nil
end

-- The last event sent to the server (optionally with a name).
function G.sent(name)
    for i = #G.toServer, 1, -1 do
        local m = G.toServer[i]
        if not name or m.name == name then return m end
    end
    return nil
end

function G.count(list, test)
    local n = 0
    for _, item in ipairs(list) do
        if test(item) then n = n + 1 end
    end
    return n
end

-- The server answering a request.
function G.reply(reqId, ok, result) TriggerEvent('Prest_Sector-CAD:reply', reqId, ok, result) end

-- The server pushing an update.
function G.push(kind, data) TriggerEvent('Prest_Sector-CAD:push', kind, data) end

-- The tablet calling one of the client's NUI callbacks. Returns whatever it answered (once it has).
function G.callNui(name, data)
    local answer
    G.nuiCallbacks[name](data, function(result) answer = result end)
    return function() return answer end
end

function G.command(name, ...) G.commands[name](0, { ... }, '') end

function G.load(configure)
    reset()
    Config, CAD, CadClient = nil, nil, nil
    dofile('config.lua')
    if configure then configure(Config) end
    dofile('shared/cad.lua')
    dofile('client/main.lua')
    dofile('client/dispatch.lua')
    dofile('client/plates.lua')
end

function G.stop() TriggerEvent('onResourceStop', 'Prest_Sector-CAD') end

G.runner = dofile('tests/runner.lua')

return G
