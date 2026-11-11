-- Prest_Sector Radar, the server: who may use the radar, plate checks (against Prest_Sector-CAD and the
-- hotlist), the hotlist itself, and an optional dispatch call for a hit. Speeds are read in each
-- officer's own game; anything that reveals records goes through here.

local R = Radar
local EVENT = R.EVENT
local CAD = 'Prest_Sector-CAD'
local KVP = 'prestSectorRadar:hotlist'
local STATE = 'prestSectorRadar' -- the player state bag key the radar reads

local hotlist = {}  -- [plate] = entry (see R.hotlistAdd)
local cache = {}    -- [plate] = { at = game ms, result }: answers from moments ago
local buckets = {}  -- [player] = their request window (R.allowRequest)
local granted = {}  -- [player] = what their state bag last said
local callsAt = {}  -- [plate] = os.time of the last dispatch call made for it

local function log(text) print(('[Prest_Sector-Radar] %s'):format(text)) end

local function cadRunning() return GetResourceState(CAD) == 'started' end

-- Calls one of the CAD's exports, safely: nil if the CAD isn't running or the call fails.
local function cad(name, ...)
    if not cadRunning() then return nil end
    local args = { ... }
    local ok, result = pcall(function() return exports[CAD][name](exports[CAD], table.unpack(args)) end)
    if ok then return result end
    return nil
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function playerId(src)
    local id = tonumber(src)
    if not id or id < 1 or id ~= math.floor(id) or not GetPlayerName(id) then return nil end
    return id
end

-- ------------------------------------------------------------------ who may use it

local function allowed(src)
    local a = Config.Access
    if a.everyone then return true end
    if a.ace and a.ace ~= '' and IsPlayerAceAllowed(src, a.ace) then return true end
    if #(a.cadRoles or {}) > 0 then
        local unit = cad('GetUnit', src)
        if type(unit) == 'table' and contains(a.cadRoles, unit.role) then return true end
    end
    return false
end

-- Tells a player's game whether its radar works (through their state bag), when that changes.
local function refresh(src)
    local now = allowed(src)
    if granted[src] ~= now then
        granted[src] = now
        Player(src).state:set(STATE, now, true)
    end
    return now
end

local function refreshAll()
    for _, id in ipairs(GetPlayers()) do
        local src = playerId(id)
        if src then refresh(src) end
    end
end

-- ------------------------------------------------------------------ the hotlist

local function saveHotlist() SetResourceKvp(KVP, json.encode(hotlist)) end

local function loadHotlist()
    local raw = GetResourceKvpString(KVP)
    local ok, data = pcall(function() return raw and json.decode(raw) end)
    hotlist = {}
    if ok and type(data) == 'table' then
        for key, entry in pairs(data) do
            if type(entry) == 'table' and R.plateKey(key) == key and type(entry.reason) == 'string' then hotlist[key] = entry end
        end
    end
    if R.hotlistPrune(hotlist, os.time()) > 0 then saveHotlist() end
end

local function addHotlist(plate, reason, by, hours)
    local entry, err = R.hotlistAdd(hotlist, plate, reason, by, os.time(), tonumber(hours) or Config.Hotlist.hours, Config.Hotlist.max)
    if not entry then return nil, err end
    cache[entry.plate] = nil
    saveHotlist()
    return entry
end

-- Loaded now, before the exports and commands below can change it, so nothing can save over it.
loadHotlist()

local function removeHotlist(plate)
    local key = R.plateKey(plate)
    if not key or not hotlist[key] then return false end
    hotlist[key] = nil
    cache[key] = nil
    saveHotlist()
    return true
end

-- ------------------------------------------------------------------ checking a plate

local function lookup(key)
    local now = GetGameTimer()
    local hit = cache[key]
    if hit and now - hit.at < (Config.Server.cacheSeconds or 0) * 1000 then return hit.result end
    local answer = Config.PlateReader.checkCad and cad('LookupPlate', key) or nil
    local result = R.classify(key, type(answer) == 'table' and answer or nil, R.hotlistFind(hotlist, key, os.time()), Config.PlateReader.notices)
    cache[key] = { at = now, result = result }
    return result
end

-- A dispatch call for a hit, at most once every 10 minutes for the same plate.
local function hitCall(src, result)
    local p = Config.PlateReader
    if not p.hitCall or not cadRunning() then return end
    local last = callsAt[result.plate]
    if last and os.time() - last < 600 then return end
    callsAt[result.plate] = os.time()
    local unit = cad('GetUnit', src)
    local who = type(unit) == 'table' and (unit.callsign or unit.name) or GetPlayerName(src)
    cad('CreateCall', {
        title = ('Plate reader hit: %s'):format(result.plate),
        code = p.hitCallCode,
        coords = GetEntityCoords(GetPlayerPed(src)),
        description = ('%s. Read by %s.'):format(table.concat(result.reasons, ' '), who or 'a unit'),
    })
end

RegisterNetEvent(EVENT .. 'check', function(reqId, camera, plate)
    local src = playerId(source)
    if not src or type(reqId) ~= 'number' then return end
    local function reply(result) TriggerClientEvent(EVENT .. 'result', src, reqId, result) end
    if camera ~= 'front' and camera ~= 'rear' then return reply({ error = 'bad_request' }) end
    buckets[src] = buckets[src] or {}
    if not R.allowRequest(buckets[src], GetGameTimer(), Config.Server.lookupsPerMinute) then return reply({ error = 'busy' }) end
    if not refresh(src) then return reply({ error = 'not_allowed' }) end
    local key = R.plateKey(plate)
    if not key then return reply({ error = 'bad_plate' }) end
    local result = lookup(key)
    reply(result)
    if result.status == 'hit' then
        log(('%s (%d): %s camera hit on %s: %s'):format(GetPlayerName(src) or '?', src, camera, key, table.concat(result.reasons, ' ')))
        hitCall(src, result)
    end
end)

-- A player's game starting the radar asks whether it works. The state bag only changes (and is only
-- sent) when the answer does.
RegisterNetEvent(EVENT .. 'hello', function()
    local src = playerId(source)
    if src then refresh(src) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    buckets[src], granted[src] = nil, nil
end)

-- ------------------------------------------------------------------ /hotlist

local function tell(src, text, tone)
    if src == 0 then print(text) else TriggerClientEvent(EVENT .. 'notify', src, text, tone or 'info') end
end

local function ago(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then return ('%dh %dm'):format(hours, minutes) end
    return ('%dm'):format(minutes)
end

RegisterCommand(Config.HotlistCommand, function(source, args)
    local src = tonumber(source) or 0
    if src ~= 0 and not refresh(src) then return tell(src, "You aren't allowed to use the plate reader's hotlist.", 'error') end
    local what = (args[1] or ''):lower()
    local by = src == 0 and 'Console' or (GetPlayerName(src) or 'Unknown')
    if what == 'add' then
        local entry, err = addHotlist(args[2], table.concat(args, ' ', 3), by)
        if not entry then return tell(src, err, 'error') end
        log(('%s added %s to the hotlist: %s'):format(by, entry.plate, entry.reason))
        return tell(src, ('%s is on the hotlist for %s: %s'):format(entry.plate, ago(entry.ends - entry.at), entry.reason), 'success')
    elseif what == 'remove' then
        local key = R.plateKey(args[2])
        if not removeHotlist(args[2]) then return tell(src, ('%s isn\'t on the hotlist.'):format(key or tostring(args[2] or '')), 'error') end
        log(('%s took %s off the hotlist'):format(by, key))
        return tell(src, ('%s is off the hotlist.'):format(key), 'success')
    elseif what == '' or what == 'list' then
        local now = os.time()
        local entries = R.hotlistEntries(hotlist, now)
        if #entries == 0 then return tell(src, ('The hotlist is empty. Add a plate with /%s add PLATE reason.'):format(Config.HotlistCommand)) end
        tell(src, ('Hotlist: %d plate%s.'):format(#entries, #entries == 1 and '' or 's'))
        for i = 1, math.min(#entries, 8) do
            local e = entries[i]
            tell(src, ('%s: %s (by %s, ends in %s)'):format(e.plate, e.reason, e.by, ago(e.ends - now)))
        end
        if #entries > 8 then tell(src, ('...and %d more.'):format(#entries - 8)) end
        return
    end
    tell(src, ('Use /%s add PLATE reason, /%s remove PLATE, or /%s to list it.'):format(Config.HotlistCommand, Config.HotlistCommand, Config.HotlistCommand), 'error')
end, false)

-- ------------------------------------------------------------------ for other scripts

-- exports['Prest_Sector-Radar']:IsAllowed(source)
exports('IsAllowed', function(src)
    src = playerId(src)
    return src ~= nil and allowed(src)
end)

-- exports['Prest_Sector-Radar']:CheckPlate('ABC123') -> { plate, status, reasons, vehicle, owner }
exports('CheckPlate', function(plate)
    local key = R.plateKey(plate)
    return key and lookup(key) or nil
end)

-- exports['Prest_Sector-Radar']:AddHotlist('ABC123', 'Stolen from Legion', 12) -> entry, or nil and why
exports('AddHotlist', function(plate, reason, hours)
    local by = GetInvokingResource and GetInvokingResource() or 'script'
    return addHotlist(plate, reason, by, hours)
end)

exports('RemoveHotlist', function(plate) return removeHotlist(plate) end)

exports('GetHotlist', function() return R.hotlistEntries(hotlist, os.time()) end)

-- ------------------------------------------------------------------ starting up

local function every(ms, fn)
    local function loop()
        fn()
        SetTimeout(ms, loop)
    end
    SetTimeout(ms, loop)
end

CreateThread(function()
    for _, problem in ipairs(R.checkConfig(Config)) do log('config problem: ' .. problem) end
    log(('ready. Hotlist: %d plate%s. %s'):format(R.hotlistCount(hotlist), R.hotlistCount(hotlist) == 1 and '' or 's',
        cadRunning() and 'Checking plates against Prest_Sector-CAD.' or 'Prest_Sector-CAD isn\'t running: plates are checked against the hotlist only.'))
    refreshAll()
    every(math.max(1, tonumber(Config.Server.recheckSeconds) or 10) * 1000, refreshAll)
    every(10 * 60 * 1000, function()
        if R.hotlistPrune(hotlist, os.time()) > 0 then saveHotlist() end
        local now = GetGameTimer()
        for key, hit in pairs(cache) do
            if now - hit.at > 60000 then cache[key] = nil end
        end
    end)
end)

-- The CAD started after the radar: who's on duty can change at once.
AddEventHandler('onResourceStart', function(resource)
    if resource == CAD then
        cache = {}
        refreshAll()
    end
end)
