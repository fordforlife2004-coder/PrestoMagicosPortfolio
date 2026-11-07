-- Where the CAD keeps its records: people, vehicles, weapons, reports, warrants, BOLOs and calls.
-- Everything is loaded into memory when the script starts (so searches are instant) and every change
-- is written straight away, to the server's own storage (Config.Storage = 'kvp', nothing to set up)
-- or to MySQL through oxmysql (Config.Storage = 'oxmysql').

Store = {}
local S = Store

S.KINDS = { 'person', 'vehicle', 'weapon', 'report', 'warrant', 'bolo', 'call' }
-- Calls are numbered from 1001 so they don't look like record numbers; everything else from 1.
local FIRST_ID = { call = 1001 }

local data = {} -- data[kind][id] = record
local seq = {}  -- seq[kind] = the last number given out
local backend = 'kvp'

local TABLE = 'prest_sector_cad'

-- ------------------------------------------------------------------ the two kinds of storage

local function kvpKey(kind, id) return ('cad:%s:%d'):format(kind, id) end
local function seqKey(kind) return 'cad:seq:' .. kind end

-- Runs a query on oxmysql and waits for the answer.
local function sql(query, params)
    local p = promise.new()
    exports.oxmysql:query(query, params or {}, function(result) p:resolve(result or {}) end)
    return Citizen.Await(p)
end

-- The same, without waiting: writes happen in the order they're sent.
local function sqlLater(query, params)
    exports.oxmysql:query(query, params or {}, function() end)
end

local function decode(text)
    if type(text) ~= 'string' or text == '' then return nil end
    local ok, value = pcall(json.decode, text)
    if ok and type(value) == 'table' then return value end
    return nil
end

local function loadKvp()
    local handle = StartFindKvp('cad:')
    if handle == -1 then return end
    while true do
        local key = FindKvp(handle)
        if not key then break end
        local kind, id = key:match('^cad:(%a+):(%d+)$')
        local seqKind = key:match('^cad:seq:(%a+)$')
        if seqKind and data[seqKind] then
            seq[seqKind] = math.max(seq[seqKind], tonumber(GetResourceKvpString(key)) or 0)
        elseif kind and data[kind] then
            local record = decode(GetResourceKvpString(key))
            if record then
                record.id = tonumber(id)
                data[kind][record.id] = record
            end
        end
    end
    EndFindKvp(handle)
end

local function loadSql()
    sql(('CREATE TABLE IF NOT EXISTS `%s` (`kind` VARCHAR(16) NOT NULL, `id` INT NOT NULL, `data` LONGTEXT NOT NULL, '
        .. 'PRIMARY KEY (`kind`, `id`)) DEFAULT CHARSET=utf8mb4'):format(TABLE))
    for _, row in ipairs(sql(('SELECT `kind`, `id`, `data` FROM `%s`'):format(TABLE))) do
        local seqKind = type(row.kind) == 'string' and row.kind:match('^seq:(%a+)$')
        if seqKind and data[seqKind] then
            seq[seqKind] = math.max(seq[seqKind], tonumber(row.data) or 0)
        elseif data[row.kind] then
            local record = decode(row.data)
            if record then
                record.id = tonumber(row.id)
                data[row.kind][record.id] = record
            end
        end
    end
end

-- ------------------------------------------------------------------ starting up

-- Loads everything. Call once when the script starts.
function S.init()
    for _, kind in ipairs(S.KINDS) do
        data[kind] = {}
        seq[kind] = (FIRST_ID[kind] or 1) - 1
    end
    backend = 'kvp'
    if Config.Storage == 'oxmysql' then
        if GetResourceState('oxmysql') == 'started' then
            backend = 'oxmysql'
        else
            print('[Prest_Sector-CAD] Config.Storage is oxmysql, but oxmysql is not started (start it before this script). '
                .. 'Using the server storage (kvp) for now.')
        end
    end
    if backend == 'oxmysql' then loadSql() else loadKvp() end
    -- A number is never given out twice, even if the saved counter got lost.
    for _, kind in ipairs(S.KINDS) do
        for id in pairs(data[kind]) do
            if id > seq[kind] then seq[kind] = id end
        end
    end
    return backend
end

function S.backend() return backend end

-- ------------------------------------------------------------------ reading and writing

function S.get(kind, id)
    local n = math.tointeger(tonumber(id))
    return n and data[kind] and data[kind][n] or nil
end

-- Every record of a kind, lowest number first.
function S.list(kind)
    local out = {}
    for _, record in pairs(data[kind] or {}) do out[#out + 1] = record end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- How many records of a kind there are.
function S.count(kind)
    local n = 0
    for _ in pairs(data[kind] or {}) do n = n + 1 end
    return n
end

-- The next number for a new record. It's saved straight away.
function S.nextId(kind)
    seq[kind] = seq[kind] + 1
    if backend == 'oxmysql' then
        sqlLater(('INSERT INTO `%s` (`kind`, `id`, `data`) VALUES (?, 0, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)'):format(TABLE),
            { 'seq:' .. kind, tostring(seq[kind]) })
    else
        SetResourceKvp(seqKey(kind), tostring(seq[kind]))
    end
    return seq[kind]
end

-- Saves a record (it must have its id).
function S.save(kind, record)
    data[kind][record.id] = record
    local text = json.encode(record)
    if backend == 'oxmysql' then
        sqlLater(('INSERT INTO `%s` (`kind`, `id`, `data`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)'):format(TABLE),
            { kind, record.id, text })
    else
        SetResourceKvp(kvpKey(kind, record.id), text)
    end
    return record
end

function S.delete(kind, id)
    if not data[kind][id] then return false end
    data[kind][id] = nil
    if backend == 'oxmysql' then
        sqlLater(('DELETE FROM `%s` WHERE `kind` = ? AND `id` = ?'):format(TABLE), { kind, id })
    else
        DeleteResourceKvp(kvpKey(kind, id))
    end
    return true
end

-- Deletes calls that were closed more than Config.KeepClosedCallsDays ago. Returns how many.
function S.prune(now)
    local days = tonumber(Config.KeepClosedCallsDays) or 0
    if days <= 0 then return 0 end
    local before = now - days * 86400
    local gone = 0
    for _, call in ipairs(S.list('call')) do
        if call.status == 'closed' and (call.closedAt or call.updatedAt or 0) < before then
            S.delete('call', call.id)
            gone = gone + 1
        end
    end
    return gone
end
