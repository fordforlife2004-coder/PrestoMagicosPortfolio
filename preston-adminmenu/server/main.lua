-- Every menu action goes through one server event. The server checks the ACE permission for that exact
-- action (never trusting the player's game), validates the input, does the work itself where it can,
-- and logs it. The player's game only does what can't be done from the server (like noclip movement).

local U = PrestonAdminUtil
local P = Config.Permissions

local MODES = { noclip = true, god = true, invisible = true }
local VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }
local VEHICLE_ACTIONS = { fix = true, flip = true, clean = true }

local allowRequest, forgetRequests = U.newRateLimiter(20, 2) -- at most 20 menu requests per 2 seconds per player
local allowDeniedLog, forgetDeniedLogs = U.newRateLimiter(3, 60) -- so a cheat spamming the event can't flood the logs
local modes = {}          -- [player] = { noclip = true, ... }: the server's record; players can't change it themselves
local frozen = {}
local joinedAt = {}
local previousPosition = {} -- where a player was before a teleport or bring, for "go back" and "send back"
local spawnedVehicle = {}
local pendingWarnings = {}  -- warnings a player hasn't clicked "I understand" on yet

local function allowed(src, key)
    local ace = P[key]
    return ace ~= nil and IsPlayerAceAllowed(src, ace)
end

local function fail(message)
    error({ userMessage = message }, 0)
end

local function nameOf(src)
    return GetPlayerName(src) or ('#' .. tostring(src))
end

local function targetOf(payload)
    local target = tonumber(payload.target)
    if not target or not GetPlayerName(target) then fail('That player is no longer online.') end
    return target
end

-- Staff with the immune permission can't be acted on, unless the admin has the bypass permission.
local function guardImmunity(src, target)
    if target ~= src and allowed(target, 'immune') and not allowed(src, 'bypassImmunity') then
        fail(('%s is protected from that action.'):format(nameOf(target)))
    end
end

local function reasonOf(payload)
    local reason = U.sanitize(payload.reason, 200)
    if #reason < 3 then fail('Write a reason (at least 3 characters).') end
    return reason
end

local function coordsOf(src)
    local coords = GetEntityCoords(GetPlayerPed(src))
    if coords.x == 0.0 and coords.y == 0.0 then fail(('%s is still loading in.'):format(nameOf(src))) end
    return coords
end

local function setCoords(src, coords)
    SetEntityCoords(GetPlayerPed(src), coords.x, coords.y, coords.z, false, false, false, false)
end

local function setMode(src, mode, enabled)
    modes[src] = modes[src] or {}
    modes[src][mode] = enabled or nil
    Player(src).state:set('presAdmin_' .. mode, enabled, true)
end

-- ---------------------------------------------------------------- actions

local Actions = {}

-- Asked when the menu key is pressed, by everyone; players without access just get allowed = false
-- (no log entry, since anyone can press the key by accident).
Actions.state = { public = true, run = function(src)
    if not allowed(src, 'open') then return { allowed = false } end
    local perms = {}
    for key in pairs(P) do perms[key] = allowed(src, key) end
    return {
        allowed = true, id = src, name = nameOf(src), perms = perms, modes = modes[src] or {},
        banDurations = Config.BanDurations, openReports = perms.reports and Reports.openCount() or 0,
        storage = Storage.backend, playerCount = #GetPlayers(), serverTime = os.time(),
    }
end }

Actions.players = { run = function(src)
    local showIds = allowed(src, 'identifiers')
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local n = tonumber(id)
        list[#list + 1] = {
            id = n, name = GetPlayerName(id), ping = GetPlayerPing(id), joinedAt = joinedAt[n], frozen = frozen[n] == true,
            staff = allowed(n, 'open'), identifiers = showIds and U.displayIdentifiers(GetPlayerIdentifiers(id)) or nil,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end }

Actions.kick = { perm = 'kick', run = function(src, p)
    local target = targetOf(p)
    guardImmunity(src, target)
    local reason = reasonOf(p)
    Logs.add(src, 'Kicked player', reason, target, 'warn')
    DropPlayer(target, ('Kicked by %s: %s'):format(nameOf(src), reason))
    return 'Player kicked.'
end }

Actions.warn = { perm = 'warn', run = function(src, p)
    local target = targetOf(p)
    local message = U.sanitize(p.message, 200)
    if #message < 3 then fail('Write the warning message.') end
    TriggerClientEvent('preston-admin:warn', target, { message = message, by = nameOf(src) })
    pendingWarnings[target] = (pendingWarnings[target] or 0) + 1
    Logs.add(src, 'Warned player', message, target, 'warn')
    return ('Warning shown to %s.'):format(nameOf(target))
end }

Actions.ban = { perm = 'ban', run = function(src, p)
    local target = targetOf(p)
    guardImmunity(src, target)
    local reason = reasonOf(p)
    local duration = U.parseDuration(p.duration)
    if duration == false then fail('Choose how long the ban lasts.') end
    local ban = Bans.banPlayer(target, reason, duration, nameOf(src))
    Logs.add(src, 'Banned player', ('#%d, %s: %s'):format(ban.id, duration and U.formatRemaining(duration) or 'permanent', reason), target, 'danger')
    DropPlayer(target, Bans.message(ban))
    return ('Banned (ban #%d).'):format(ban.id)
end }

Actions.banRecent = { perm = 'ban', run = function(src, p)
    local reason = reasonOf(p)
    local duration = U.parseDuration(p.duration)
    if duration == false then fail('Choose how long the ban lasts.') end
    local ban = Bans.banRecent(tonumber(p.leftId), reason, duration, nameOf(src))
    Logs.add(src, 'Banned player who left', ('%s, #%d, %s: %s'):format(ban.name, ban.id, duration and U.formatRemaining(duration) or 'permanent', reason), nil, 'danger')
    return ('%s is banned (ban #%d).'):format(ban.name, ban.id)
end }

Actions.unban = { perm = 'unban', run = function(src, p)
    local ban = Bans.unban(tonumber(p.id), nameOf(src))
    Logs.add(src, 'Unbanned player', ('%s (ban #%d: %s)'):format(ban.name, ban.id, ban.reason), nil, 'success')
    return ('%s is unbanned.'):format(ban.name)
end }

Actions.bans = { run = function(src)
    if not allowed(src, 'ban') and not allowed(src, 'unban') then fail("You don't have permission to see bans.") end
    return { active = Bans.active(), recentlyLeft = allowed(src, 'ban') and Bans.recentlyLeft() or {} }
end }

Actions.gotoPlayer = { perm = 'teleport', run = function(src, p)
    local target = targetOf(p)
    local there = coordsOf(target)
    previousPosition[src] = GetEntityCoords(GetPlayerPed(src))
    setCoords(src, vector3(there.x, there.y, there.z + 1.0))
    Logs.add(src, 'Went to player', nil, target)
    return ('Teleported to %s.'):format(nameOf(target))
end }

Actions.bring = { perm = 'bring', run = function(src, p)
    local target = targetOf(p)
    guardImmunity(src, target)
    local here = coordsOf(src)
    previousPosition[target] = GetEntityCoords(GetPlayerPed(target))
    setCoords(target, vector3(here.x + 1.0, here.y, here.z))
    Logs.add(src, 'Brought player', nil, target)
    return ('Brought %s to you.'):format(nameOf(target))
end }

Actions.sendBack = { perm = 'bring', run = function(src, p)
    local target = targetOf(p)
    local back = previousPosition[target]
    if not back then fail(("There's no earlier position for %s."):format(nameOf(target))) end
    previousPosition[target] = nil
    setCoords(target, back)
    Logs.add(src, 'Sent player back', nil, target)
    return ('Sent %s back.'):format(nameOf(target))
end }

Actions.goBack = { perm = 'teleport', run = function(src)
    local back = previousPosition[src]
    if not back then fail('There is no earlier position to go back to.') end
    previousPosition[src] = nil
    setCoords(src, back)
    return 'Back where you were.'
end }

-- Waypoint teleport: the server approves and remembers the old position; the game finds the ground there.
Actions.teleportCoords = { perm = 'teleport', run = function(src, p)
    local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
    if not U.validCoords(x, y, z) then fail('That spot is outside the map.') end
    previousPosition[src] = GetEntityCoords(GetPlayerPed(src))
    Logs.add(src, 'Teleported to waypoint', ('%.0f, %.0f'):format(x, y))
    return 'Teleported to your waypoint.'
end }

Actions.spectate = { perm = 'spectate', run = function(src, p)
    local target = targetOf(p)
    if target == src then fail("You can't spectate yourself.") end
    local coords = coordsOf(target)
    Logs.add(src, 'Started spectating', nil, target)
    return { target = target, name = nameOf(target), coords = { x = coords.x, y = coords.y, z = coords.z } }
end }

Actions.spectateEnded = { perm = 'spectate', run = function(src)
    Logs.add(src, 'Stopped spectating')
    return true
end }

Actions.freeze = { perm = 'freeze', run = function(src, p)
    local target = targetOf(p)
    guardImmunity(src, target)
    local enabled = p.enabled == true
    FreezeEntityPosition(GetPlayerPed(target), enabled)
    frozen[target] = enabled or nil
    TriggerClientEvent('preston-admin:freeze', target, enabled, nameOf(src))
    Logs.add(src, enabled and 'Froze player' or 'Unfroze player', nil, target, 'warn')
    return ('%s %s.'):format(nameOf(target), enabled and 'is frozen' or 'can move again')
end }

Actions.heal = { perm = 'heal', run = function(src, p)
    local target = targetOf(p)
    TriggerClientEvent('preston-admin:heal', target, nameOf(src))
    Logs.add(src, 'Healed or revived player', nil, target, 'success')
    return ('Healed %s.'):format(nameOf(target))
end }

Actions.setMode = { run = function(src, p)
    local mode = p.mode
    if not MODES[mode] then fail('Unknown mode.') end
    if not allowed(src, mode) then fail("You don't have permission for " .. mode .. '.') end
    local enabled = p.enabled == true
    setMode(src, mode, enabled)
    Logs.add(src, ('%s %s'):format(enabled and 'Turned on' or 'Turned off', mode))
    return enabled
end }

-- The known type of a model, looked up by the game's model hash so another name for the same model
-- gets the same answer: Config.VehicleTypes for add-ons, the built-in list, 'train' for trains, or
-- nil for a model nobody listed (an add-on car, or an add-on the owner hasn't listed).
local knownByHash
local function knownTypeOf(model)
    local hash = GetHashKey(model)
    for name, kind in pairs(Config.VehicleTypes or {}) do
        if GetHashKey(name) == hash then return kind end
    end
    if not knownByHash then
        knownByHash = {}
        for name, kind in pairs(KnownVehicleTypes) do knownByHash[GetHashKey(name)] = kind end
        for name in pairs(KnownTrains) do knownByHash[GetHashKey(name)] = 'train' end
    end
    return knownByHash[hash]
end

-- Whether a player other than src is sitting in the vehicle.
local function otherPlayerInside(vehicle, src)
    for _, id in ipairs(GetPlayers()) do
        local player = tonumber(id)
        if player ~= src and GetVehiclePedIsIn(GetPlayerPed(player), false) == vehicle then return true end
    end
    return false
end

-- An admin's last spawned car is removed when they spawn another or leave, unless someone else is in it.
local function releaseSpawnedVehicle(src)
    local previous = spawnedVehicle[src]
    spawnedVehicle[src] = nil
    if previous and DoesEntityExist(previous) and not otherPlayerInside(previous, src) then DeleteEntity(previous) end
end

-- The server creates the car (so it can't be faked and the server knows it exists) in the admin's
-- own world instance. The admin's game gets in once the car has reached it.
Actions.spawnVehicle = { perm = 'vehicle', run = function(src, p)
    local model = type(p.model) == 'string' and p.model:lower() or ''
    if not U.validModelName(model) then fail('Enter a vehicle model name, like adder or police3.') end
    if not VEHICLE_TYPES[p.vehicleType] then fail('Unknown vehicle type.') end
    -- A vehicle spawned as the wrong type is broken for everyone near it.
    local known = knownTypeOf(model)
    if known == 'train' then fail("Trains can't be spawned from the menu.") end
    if known and known ~= p.vehicleType then
        fail(('"%s" is a %s, so it can only be spawned as one.'):format(model, known))
    end
    local ped = GetPlayerPed(src)
    local at = coordsOf(src)
    local inside = GetVehiclePedIsIn(ped, false)
    -- Sitting in a car is only fine when it's your last spawned one and it's about to be removed;
    -- otherwise the new car would appear inside it.
    if inside ~= 0 and (inside ~= spawnedVehicle[src] or not Config.DeletePreviousSpawnedVehicle or otherPlayerInside(inside, src)) then
        fail('Get out of this vehicle first.')
    end
    if Config.DeletePreviousSpawnedVehicle then releaseSpawnedVehicle(src) end
    local vehicle = CreateVehicleServerSetter(GetHashKey(model), p.vehicleType, at.x, at.y, at.z + 0.5, GetEntityHeading(ped))
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then fail(('"%s" could not be spawned.'):format(model)) end
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, 'ADMIN')
    spawnedVehicle[src] = vehicle
    Logs.add(src, 'Spawned vehicle', model)
    return { netId = NetworkGetNetworkIdFromEntity(vehicle), model = model }
end }

-- The admin's game never received the new car (usually a model that isn't installed): remove it.
Actions.vehicleNotArrived = { perm = 'vehicle', run = function(src, p)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(p.netId) or -1)
    if vehicle ~= 0 and spawnedVehicle[src] == vehicle then
        spawnedVehicle[src] = nil
        DeleteEntity(vehicle)
    end
    return true
end }

-- Fix, flip and clean happen in the admin's own game after the server approves and logs them.
Actions.vehicleAction = { perm = 'vehicle', run = function(src, p)
    if not VEHICLE_ACTIONS[p.action] then fail('Unknown vehicle action.') end
    Logs.add(src, 'Vehicle ' .. p.action)
    return ({ fix = 'Vehicle fixed.', flip = 'Vehicle flipped.', clean = 'Vehicle cleaned.' })[p.action]
end }

Actions.deleteVehicle = { perm = 'vehicle', run = function(src, p)
    local entity = NetworkGetEntityFromNetworkId(tonumber(p.netId) or -1)
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then fail("Couldn't find that vehicle.") end
    DeleteEntity(entity)
    Logs.add(src, 'Deleted vehicle')
    return 'Vehicle deleted.'
end }

Actions.announce = { perm = 'announce', run = function(src, p)
    local message = U.sanitize(p.message, 300)
    if #message < 2 then fail('Write the announcement first.') end
    TriggerClientEvent('preston-admin:announce', -1, { message = message, by = nameOf(src) })
    Logs.add(src, 'Announcement', message, nil, 'info')
    return 'Announcement sent to everyone.'
end }

Actions.reports = { perm = 'reports', run = function()
    return Reports.forMenu()
end }

Actions.reportClaim = { perm = 'reports', run = function(src, p)
    local report = Reports.claim(p.id, src)
    Logs.add(src, 'Claimed report', ('#%d: %s'):format(report.id, report.message))
    return ('You claimed report #%d.'):format(report.id)
end }

Actions.reportClose = { perm = 'reports', run = function(src, p)
    local report = Reports.close(p.id, src)
    Logs.add(src, 'Closed report', ('#%d'):format(report.id), nil, 'success')
    return ('Report #%d closed.'):format(report.id)
end }

Actions.reportGoto = { perm = 'reports', run = function(src, p)
    if not allowed(src, 'teleport') then fail("You don't have permission to teleport.") end
    local report = Reports.get(p.id)
    return Actions.gotoPlayer.run(src, { target = report.reporter })
end }

Actions.logs = { perm = 'logs', run = function()
    return Logs.recent()
end }

-- ---------------------------------------------------------------- the one entry point

RegisterNetEvent('preston-admin:rpc', function(requestId, action, payload)
    local src = source
    if type(requestId) ~= 'number' then return end
    local function reply(ok, data)
        TriggerClientEvent('preston-admin:rpcResult', src, requestId, ok, data)
    end
    local now = GetGameTimer() / 1000
    if not allowRequest(src, now) then return reply(false, 'Slow down a little.') end
    local def = type(action) == 'string' and Actions[action] or nil
    if not def then return reply(false, 'Unknown action.') end
    if not def.public and not allowed(src, 'open') then
        if allowDeniedLog(src, now) then
            Logs.add(src, 'Denied', ('tried "%s" without admin menu access'):format(action), nil, 'danger')
        end
        return reply(false, "You don't have access to the admin menu.")
    end
    if def.perm and not allowed(src, def.perm) then
        if allowDeniedLog(src, now) then
            Logs.add(src, 'Denied', ('tried "%s" without permission'):format(action), nil, 'warn')
        end
        return reply(false, "You don't have permission to do that.")
    end
    local ok, result = pcall(def.run, src, type(payload) == 'table' and payload or {})
    if ok then return reply(true, result) end
    if type(result) == 'table' and result.userMessage then return reply(false, result.userMessage) end
    print(('[preston-admin] error in "%s": %s'):format(action, tostring(result)))
    reply(false, 'Something went wrong. Check the server console.')
end)

-- Noclip, god mode and invisibility are switched on only by the server. If a player's game changes
-- them itself (a cheat menu faking it), the server puts them back and logs the attempt.
for mode in pairs(MODES) do
    AddStateBagChangeHandler('presAdmin_' .. mode, nil, function(bagName, key, value)
        local src = GetPlayerFromStateBagName(bagName)
        if not src or src == 0 then return end
        local official = modes[src] ~= nil and modes[src][mode] == true
        if (value == true) ~= official then
            SetTimeout(0, function()
                if GetPlayerName(src) then Player(src).state:set(key, official, true) end
            end)
            Logs.add(src, 'Blocked tampering', ('tried to change %s without the server'):format(mode), nil, 'danger')
        end
    end)
end

-- The warned player clicked "I understand". Only counted when the server actually sent a warning.
RegisterNetEvent('preston-admin:warnSeen', function()
    local src = source
    if (pendingWarnings[src] or 0) < 1 then return end
    pendingWarnings[src] = pendingWarnings[src] - 1
    Logs.add(src, 'Read the warning', nil, nil, 'info')
end)

-- Server console: unban by ID, in case the staff who could do it are banned themselves.
RegisterCommand('adminunban', function(src, args)
    if src ~= 0 and not allowed(src, 'unban') then return end
    local ok, result = pcall(Bans.unban, tonumber(args[1]), src == 0 and 'Console' or nameOf(src))
    if ok then
        Logs.add(src, 'Unbanned player', ('%s (ban #%d)'):format(result.name, result.id), nil, 'success')
    else
        print(('[preston-admin] %s'):format(type(result) == 'table' and result.userMessage or tostring(result)))
    end
end, true)

-- Another script deleted an admin's car: forget it, so the old handle is never used again.
AddEventHandler('entityRemoved', function(entity)
    for player, vehicle in pairs(spawnedVehicle) do
        if vehicle == entity then spawnedVehicle[player] = nil end
    end
end)

AddEventHandler('playerJoining', function()
    joinedAt[source] = os.time()
end)

AddEventHandler('playerDropped', function()
    local src = source
    modes[src], frozen[src], joinedAt[src], previousPosition[src], pendingWarnings[src] = nil, nil, nil, nil, nil
    releaseSpawnedVehicle(src)
    forgetRequests(src)
    forgetDeniedLogs(src)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local n = tonumber(id)
        joinedAt[n] = joinedAt[n] or os.time()
        for mode in pairs(MODES) do Player(n).state:set('presAdmin_' .. mode, false, true) end
    end
    CreateThread(function()
        Storage.init()
        Bans.load()
        local count = 0
        for _ in pairs(Bans.list) do count = count + 1 end
        print(('[preston-admin] v2 ready: %d active bans, saved with %s.'):format(count, Storage.backend))
        if GetConvar('preston_admin_webhook', '') == '' then
            print('[preston-admin] Tip: set preston_admin_webhook in server.cfg to log actions to Discord.')
        end
    end)
end)
