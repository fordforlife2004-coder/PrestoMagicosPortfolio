-- Saves bans in MySQL through oxmysql when it's running, otherwise in this resource's key-value store
-- (the server's built-in KVP, no database needed). Both keep unbanned and expired bans for history.

Storage = { backend = 'kvp' }

local function useSql()
    if Config.Storage == 'oxmysql' then return true end
    if Config.Storage == 'kvp' then return false end
    return GetResourceState('oxmysql') == 'started'
end

-- Runs an oxmysql query and waits for it, failing instead of hanging if the database never answers.
local function sql(method, query, params)
    local p = promise.new()
    local finished = false
    exports.oxmysql[method](exports.oxmysql, query, params or {}, function(result)
        if finished then return end
        finished = true
        p:resolve(result)
    end)
    SetTimeout(10000, function()
        if finished then return end
        finished = true
        p:reject(('database query timed out: %s'):format(query:sub(1, 60)))
    end)
    return Citizen.Await(p)
end

local function rowToBan(row)
    return {
        id = row.id,
        name = row.name,
        reason = row.reason,
        identifiers = json.decode(row.identifiers) or {},
        tokens = row.tokens and json.decode(row.tokens) or {},
        bannedBy = row.banned_by,
        createdAt = row.created_at,
        expiresAt = row.expires_at,
        active = row.active == 1 or row.active == true,
    }
end

function Storage.init()
    if useSql() then
        Storage.backend = 'oxmysql'
        sql('query', [[
            CREATE TABLE IF NOT EXISTS preston_admin_bans (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(64) NOT NULL,
                reason VARCHAR(255) NOT NULL,
                identifiers LONGTEXT NOT NULL,
                tokens LONGTEXT NULL,
                banned_by VARCHAR(64) NOT NULL,
                created_at INT NOT NULL,
                expires_at INT NULL,
                active TINYINT(1) NOT NULL DEFAULT 1,
                unbanned_by VARCHAR(64) NULL
            )
        ]])
    else
        Storage.backend = 'kvp'
    end
end

-- Active bans only; expired ones are skipped by the ban check anyway.
function Storage.loadBans()
    local bans = {}
    if Storage.backend == 'oxmysql' then
        for _, row in ipairs(sql('query', 'SELECT * FROM preston_admin_bans WHERE active = 1') or {}) do
            bans[#bans + 1] = rowToBan(row)
        end
    else
        local handle = StartFindKvp('ban:')
        repeat
            local key = FindKvp(handle)
            if key then
                local ban = json.decode(GetResourceKvpString(key) or 'null')
                if ban and ban.active then bans[#bans + 1] = ban end
            end
        until not key
        EndFindKvp(handle)
    end
    return bans
end

-- Saves a new ban and returns its id.
function Storage.insertBan(ban)
    if Storage.backend == 'oxmysql' then
        return sql('insert', [[
            INSERT INTO preston_admin_bans (name, reason, identifiers, tokens, banned_by, created_at, expires_at, active)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1)
        ]], { ban.name, ban.reason, json.encode(ban.identifiers), json.encode(ban.tokens), ban.bannedBy, ban.createdAt, ban.expiresAt })
    end
    local id = GetResourceKvpInt('meta:nextBanId')
    if id < 1 then id = 1 end
    SetResourceKvpInt('meta:nextBanId', id + 1)
    ban.id = id
    SetResourceKvp(('ban:%d'):format(id), json.encode(ban))
    return id
end

function Storage.deactivateBan(id, unbannedBy)
    if Storage.backend == 'oxmysql' then
        sql('update', 'UPDATE preston_admin_bans SET active = 0, unbanned_by = ? WHERE id = ?', { unbannedBy, id })
        return
    end
    local key = ('ban:%d'):format(id)
    local ban = json.decode(GetResourceKvpString(key) or 'null')
    if ban then
        ban.active = false
        ban.unbannedBy = unbannedBy
        SetResourceKvp(key, json.encode(ban))
    end
end
