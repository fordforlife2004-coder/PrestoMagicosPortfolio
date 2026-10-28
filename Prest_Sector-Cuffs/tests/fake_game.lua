-- A small fake game for the client tests: players, peds, objects and vehicles in plain tables, a clock,
-- and threads that run frame by frame. Reading a global nobody defined raises an error, so a misspelt
-- native or helper shows up in the tests instead of silently doing nothing.

local G = {
    now = 0, threads = {}, entities = {}, players = {}, me = 0, missingDicts = {},
    sent = {}, feed = {}, chat = {}, printed = {}, commands = {}, keys = {}, net = {}, handlers = {},
    bagHandlers = {}, exports = {}, disabled = {}, pressed = {}, justPressed = {},
    models = { p_cs_cuffs_02_s = true },
    enterWorks = true, exitWorks = true, firingDisabled = false,
}
local nextId = 1000
local realPrint = print

local function vec(x, y, z) return { x = x, y = y, z = z or 30.0 } end

local function new(kind, fields)
    nextId = nextId + 1
    fields.kind = kind
    fields.anims = fields.anims or {}
    fields.seats = fields.seats or {}
    G.entities[nextId] = fields
    return nextId
end

local function e(id) return G.entities[id] or error('no entity ' .. tostring(id), 2) end

-- ---------------------------------------------------------------- time and threads

function GetGameTimer() return G.now end
function Wait(ms) if coroutine.isyieldable() then coroutine.yield(ms or 0) end end
function CreateThread(fn) G.threads[#G.threads + 1] = { co = coroutine.create(fn), at = G.now } end
function SetTimeout(ms, fn) G.threads[#G.threads + 1] = { co = coroutine.create(fn), at = G.now + ms } end

-- Runs an event handler or command to the end; its Waits move the clock but nothing else runs.
function G.run(fn, ...)
    local co = coroutine.create(fn)
    local ok, ms = coroutine.resume(co, ...)
    while true do
        if not ok then error(ms, 0) end
        if coroutine.status(co) == 'dead' then return end
        G.now = G.now + (ms or 0)
        ok, ms = coroutine.resume(co)
    end
end

-- One frame: every thread that is due runs until its next Wait.
function G.tick(ms)
    G.now = G.now + (ms or 16)
    G.disabled = {}
    local list = G.threads
    for i = 1, #list do
        local th = list[i]
        if not th.dead and th.at <= G.now then
            local ok, wait = coroutine.resume(th.co)
            if not ok then error(wait, 0) end
            if coroutine.status(th.co) == 'dead' then th.dead = true else th.at = G.now + (wait or 0) end
        end
    end
    local alive = {}
    for _, th in ipairs(G.threads) do if not th.dead then alive[#alive + 1] = th end end
    G.threads = alive
    G.justPressed = {}
end

function G.runFor(ms)
    local stop = G.now + ms
    while G.now < stop do G.tick(16) end
end

-- ---------------------------------------------------------------- players and state

function G.addPlayer(index, serverId, coords, heading)
    local ped = new('ped', { coords = coords or vec(0, 0), heading = heading or 0.0, visible = true, weapon = 'hash:WEAPON_PISTOL', flags = {} })
    G.players[index] = { serverId = serverId, ped = ped }
    return ped
end

function G.removePlayer(index) G.players[index] = nil end -- out of this game's view (the state stays on the server)

function G.newPed(index) -- the player respawned or changed model
    local old = G.players[index].ped
    G.players[index].ped = new('ped', { coords = e(old).coords, heading = 0.0, visible = true, flags = {} })
    G.entities[old] = nil
    return G.players[index].ped
end

-- GlobalState as a player's game sees it: it can read it, and only the server (the tests, through
-- G.setGlobal) changes it. Change handlers run before the value is stored, like FiveM's.
G.global = {}
function G.setGlobal(key, value)
    for _, h in ipairs(G.bagHandlers) do
        if (h.key == nil or h.key == key) and (h.bag == nil or h.bag == 'global') then h.fn('global', key, value, 0, true) end
    end
    G.global[key] = value
end
GlobalState = setmetatable({}, {
    __index = function(_, key) return G.global[key] end,
    __newindex = function() error("a player's game can't write GlobalState", 2) end,
})

function AddStateBagChangeHandler(key, bag, fn) G.bagHandlers[#G.bagHandlers + 1] = { key = key, bag = bag, fn = fn } end

function PlayerId() return G.me end
function PlayerPedId() return G.players[G.me].ped end
function GetActivePlayers()
    local list = {}
    for index in pairs(G.players) do list[#list + 1] = index end
    table.sort(list)
    return list
end
function GetPlayerServerId(index) return G.players[index] and G.players[index].serverId or 0 end
function GetPlayerFromServerId(id)
    for index, p in pairs(G.players) do if p.serverId == id then return index end end
    return -1
end
function GetPlayerPed(index) return G.players[index] and G.players[index].ped or 0 end
function NetworkGetPlayerIndexFromPed(ped)
    for index, p in pairs(G.players) do if p.ped == ped then return index end end
    return -1
end
function IsPedAPlayer(ped) return NetworkGetPlayerIndexFromPed(ped) ~= -1 end

-- ---------------------------------------------------------------- entities

function GetHashKey(name) return 'hash:' .. name end
function IsModelInCdimage(hash) return G.models[hash:sub(6)] == true end
function RequestModel() end
function HasModelLoaded(hash) return IsModelInCdimage(hash) end
function SetModelAsNoLongerNeeded() end

function DoesEntityExist(id) return G.entities[id] ~= nil end
function GetEntityCoords(id) return e(id).coords end
function GetEntityHeading(id) return e(id).heading or 0.0 end
function CreateObject(hash, x, y, z, isNetwork, missionEntity, door)
    return new('object', { model = hash, coords = vec(x, y, z), networked = isNetwork, visible = true })
end
function DeleteEntity(id)
    G.entities[id] = nil
    for _, other in pairs(G.entities) do if other.attachedTo == id then other.attachedTo = nil end end
end
function SetEntityCollision(id, on) e(id).collision = on end
function SetEntityCanBeDamaged() end
function SetEntityVisible(id, visible) e(id).visible = visible end
function IsEntityVisible(id) return e(id).visible ~= false end
function FreezeEntityPosition(id, frozen) e(id).frozen = frozen end
function GetPedBoneIndex(_, boneId) return 'bone:' .. boneId end
G.attachLog = {} -- every attach, in order: { entity, to, bone, offset, rotation, rest }
function AttachEntityToEntity(a, b, bone, x, y, z, rx, ry, rz, ...)
    e(a).attachedTo = b
    e(a).attach = { entity = a, to = b, bone = bone, offset = { x, y, z }, rotation = { rx, ry, rz }, rest = { ... } }
    G.attachLog[#G.attachLog + 1] = e(a).attach
end
function DetachEntity(id) e(id).attachedTo = nil end
function IsEntityAttachedToEntity(a, b) return G.entities[a] ~= nil and G.entities[a].attachedTo == b end

-- ---------------------------------------------------------------- peds and animations

function DoesAnimDictExist(dict) return not G.missingDicts[dict] end
function RequestAnimDict() end
function HasAnimDictLoaded(dict) return not G.missingDicts[dict] end
function TaskPlayAnim(ped, dict, clip, _, _, ms, flags) e(ped).anims[dict .. '/' .. clip] = { flags = flags, ms = ms } end
function StopAnimTask(ped, dict, clip) e(ped).anims[dict .. '/' .. clip] = nil end
function IsEntityPlayingAnim(ped, dict, clip) return G.entities[ped] ~= nil and e(ped).anims[dict .. '/' .. clip] ~= nil end
function ClearPedTasksImmediately(ped) e(ped).anims = {} end
function GetAnimDuration() return 3.8 end
function IsEntityDead(id) return e(id).dead == true end
function IsPedRagdoll(id) return e(id).ragdoll == true end
function IsPedGettingUp() return false end
function IsPedWalking(id) return e(id).gait == 'walk' end
function IsPedRunning(id) return e(id).gait == 'run' end
function IsPedSprinting(id) return e(id).gait == 'sprint' end
function SetEnableHandcuffs(ped, on) e(ped).handcuffs = on end
function SetPedCanPlayGestureAnims(ped, on) e(ped).gestures = on end
function SetCurrentPedWeapon(ped, weapon) e(ped).weapon = weapon end
function GetSelectedPedWeapon(ped) return e(ped).weapon end
function DisablePlayerFiring(_, on) G.firingDisabled = on end
function IsPedCuffed(ped) return e(ped).handcuffs == true end
function SetPedConfigFlag(ped, flag, on) e(ped).flags[flag] = on end
function ClearPedTasks(ped) e(ped).anims = {} end
function IsPlayerFreeAiming() return G.aiming == true end
-- A ped marked behind a wall can't be seen by anyone, and can't see anyone.
function HasEntityClearLosToEntity(a, b) return not (e(a).behindWall or e(b).behindWall) end
function GetEntitySpeed(id) return e(id).speed or 0.0 end

-- ---------------------------------------------------------------- vehicles

function G.addVehicle(coords, passengers, opts)
    opts = opts or {}
    return new('vehicle', { coords = coords, passengers = passengers or 3, networked = opts.networked ~= false })
end

function G.seat(ped, vehicle, seat)
    e(ped).vehicle = vehicle
    e(vehicle).seats[seat] = ped
end

function G.unseat(ped)
    local vehicle = e(ped).vehicle
    if vehicle then
        for seat, p in pairs(e(vehicle).seats) do if p == ped then e(vehicle).seats[seat] = nil end end
    end
    e(ped).vehicle = nil
end

function GetGamePool(pool)
    local list = {}
    if pool == 'CVehicle' then
        for id, ent in pairs(G.entities) do if ent.kind == 'vehicle' then list[#list + 1] = id end end
    end
    table.sort(list)
    return list
end
function NetworkGetEntityIsNetworked(id) return e(id).networked ~= false end
function GetVehicleMaxNumberOfPassengers(id) return e(id).passengers end
function IsVehicleSeatFree(id, seat) return e(id).seats[seat] == nil end
function GetPedInVehicleSeat(id, seat) return e(id).seats[seat] or 0 end
-- atGetIn: also true while the ped is still climbing in.
function IsPedInAnyVehicle(ped, atGetIn) return e(ped).vehicle ~= nil or (atGetIn == true and e(ped).gettingIn == true) end
function GetVehiclePedIsIn(ped) return e(ped).vehicle or 0 end
function VehToNet(id) return id end
function NetworkDoesEntityExistWithNetworkId(id) return G.entities[id] ~= nil end
function NetToVeh(id) return G.entities[id] and id or 0 end
function TaskEnterVehicle(ped, vehicle, _, seat) if G.enterWorks then G.seat(ped, vehicle, seat) end end
function SetPedIntoVehicle(ped, vehicle, seat) G.seat(ped, vehicle, seat) end
function TaskLeaveVehicle(ped, _, flags)
    e(ped).leaveFlags = flags
    if G.exitWorks or flags == 16 then G.unseat(ped) end
end

-- ---------------------------------------------------------------- controls, text, events

function DisableControlAction(_, control) G.disabled[control] = true end
function IsDisabledControlPressed(_, control) return G.pressed[control] == true end
function IsDisabledControlJustPressed(_, control) return G.justPressed[control] == true end

function BeginTextCommandThefeedPost() end
function AddTextComponentSubstringPlayerName(text) G.feed[#G.feed + 1] = text end
function EndTextCommandThefeedPostTicker() end
function SetTextFont() end
function SetTextScale() end
function SetTextColour() end
function SetTextOutline() end
function BeginTextCommandDisplayText() end
function EndTextCommandDisplayText() end

function RegisterNetEvent(name, fn) G.net[name] = fn end
function AddEventHandler(name, fn)
    G.handlers[name] = G.handlers[name] or {}
    table.insert(G.handlers[name], fn)
end
function TriggerServerEvent(name, ...) G.sent[#G.sent + 1] = { name = name, args = { ... } } end
function TriggerEvent(name, data) if name == 'chat:addMessage' then G.chat[#G.chat + 1] = data.args[2] end end
function RegisterCommand(name, fn) G.commands[name] = fn end
function RegisterKeyMapping(command, _, _, key) G.keys[command] = key end
function exports(name, fn) G.exports[name] = fn end
function GetCurrentResourceName() return 'Prest_Sector-Cuffs' end

-- Messages the resource prints are kept for the tests; everything else (the test results) shows.
print = function(...)
    local text = table.concat({ ... }, ' ')
    if text:find('[Prest_Sector-Cuffs]', 1, true) == 1 then G.printed[#G.printed + 1] = text else realPrint(...) end
end

-- ---------------------------------------------------------------- helpers for the tests

G.vec = vec
G.runner = dofile('tests/runner.lua')
function G.entity(id) return G.entities[id] end
function G.event(name, ...) G.run(G.net[name], ...) end
function G.command(name, ...) G.run(G.commands[name], 0, { ... }, '') end
function G.fire(name, ...) for _, fn in ipairs(G.handlers[name] or {}) do G.run(fn, ...) end end
function G.lastSent() return G.sent[#G.sent] end
function G.lastNote() return G.feed[#G.feed] end
function G.press(control) G.pressed[control] = true G.justPressed[control] = true end
function G.release(control) G.pressed[control] = nil end

-- Anything the scripts read that the fake doesn't have is an error, not a silent nil.
function G.strict()
    setmetatable(_G, { __index = function(_, name) error('unknown global: ' .. tostring(name), 2) end })
end

return G
