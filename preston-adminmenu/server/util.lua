-- Pure helper functions (no FiveM natives), so they can be tested with plain Lua: lua tests/util_spec.lua

PrestonAdminUtil = {}
local U = PrestonAdminUtil

local UNIT_SECONDS = { m = 60, h = 3600, d = 86400, w = 604800 }

-- "30m", "12h", "7d", "2w" -> seconds; "perm" -> nil (permanent); anything else -> false.
function U.parseDuration(text)
    if type(text) ~= 'string' then return false end
    text = text:lower():gsub('%s+', '')
    if text == 'perm' or text == 'permanent' then return nil end
    local amount, unit = text:match('^(%d+)([mhdw])$')
    amount = tonumber(amount)
    if not amount or amount <= 0 or amount > 100000 then return false end
    return amount * UNIT_SECONDS[unit]
end

-- 273600 -> "3d 4h"; 2700 -> "45m"; 20 -> "less than a minute".
function U.formatRemaining(seconds)
    if seconds == nil then return 'never' end
    if seconds < 60 then return 'less than a minute' end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then return hours > 0 and ('%dd %dh'):format(days, hours) or ('%dd'):format(days) end
    if hours > 0 then return minutes > 0 and ('%dh %dm'):format(hours, minutes) or ('%dh'):format(hours) end
    return ('%dm'):format(minutes)
end

-- Makes player-typed text safe to store and show: no FiveM color codes or control characters,
-- spaces collapsed, trimmed, and cut to maxLength characters without splitting a UTF-8 character.
function U.sanitize(text, maxLength)
    if type(text) ~= 'string' then return '' end
    text = text:gsub('%^%d', ''):gsub('%c', ' '):gsub('%s+', ' ')
    text = text:match('^%s*(.-)%s*$')
    if maxLength and #text > maxLength then
        local ok, cut = pcall(utf8.offset, text, maxLength + 1)
        text = (ok and cut) and text:sub(1, cut - 1) or text:sub(1, maxLength)
    end
    return text
end

-- The identifiers a ban should match on. IP addresses only when enabled.
function U.banIdentifiers(identifiers, includeIp)
    local out = {}
    for _, id in ipairs(identifiers or {}) do
        local kind = type(id) == 'string' and id:match('^(%w+):')
        if kind and (kind ~= 'ip' or includeIp) then out[#out + 1] = id end
    end
    return out
end

-- Identifiers safe to show admins in the menu (never IP addresses).
function U.displayIdentifiers(identifiers)
    local out = {}
    for _, id in ipairs(identifiers or {}) do
        local kind = id:match('^(%w+):')
        if kind == 'license' or kind == 'discord' or kind == 'steam' or kind == 'fivem' or kind == 'xbl' or kind == 'live' then
            out[#out + 1] = id
        end
    end
    return out
end

function U.isExpired(ban, now)
    return ban.expiresAt ~= nil and ban.expiresAt <= now
end

-- The first active, unexpired ban that matches any of a player's identifiers or hardware tokens.
function U.findBan(bans, identifiers, tokens, now, includeIp)
    local mine = {}
    for _, id in ipairs(U.banIdentifiers(identifiers, includeIp)) do mine[id] = true end
    for _, token in ipairs(tokens or {}) do mine['token:' .. token] = true end
    local best
    for _, ban in pairs(bans) do
        if ban.active and not U.isExpired(ban, now) then
            local hit = false
            for _, id in ipairs(ban.identifiers or {}) do
                if mine[id] then hit = true break end
            end
            if not hit then
                for _, token in ipairs(ban.tokens or {}) do
                    if mine['token:' .. token] then hit = true break end
                end
            end
            -- When several bans match, report the one that lasts longest.
            if hit and (not best or (best.expiresAt ~= nil and (ban.expiresAt == nil or ban.expiresAt > best.expiresAt))) then
                best = ban
            end
        end
    end
    return best
end

-- Allows at most maxCalls per key within windowSeconds. Returns allow(key, now) and forget(key).
function U.newRateLimiter(maxCalls, windowSeconds)
    local hits = {}
    local function allow(key, now)
        local fresh = {}
        for _, t in ipairs(hits[key] or {}) do
            if now - t < windowSeconds then fresh[#fresh + 1] = t end
        end
        if #fresh >= maxCalls then
            hits[key] = fresh
            return false
        end
        fresh[#fresh + 1] = now
        hits[key] = fresh
        return true
    end
    local function forget(key) hits[key] = nil end
    return allow, forget
end

-- A fixed-size list that keeps the newest items.
function U.newRing(size)
    local items = {}
    return {
        push = function(item)
            items[#items + 1] = item
            if #items > size then table.remove(items, 1) end
        end,
        list = function()
            local out = {}
            for i = #items, 1, -1 do out[#out + 1] = items[i] end
            return out
        end,
    }
end

-- Map coordinates are only accepted inside the playable area.
function U.validCoords(x, y, z)
    return type(x) == 'number' and type(y) == 'number' and type(z) == 'number'
        and x >= -8000 and x <= 8000 and y >= -8000 and y <= 9000 and z >= -500 and z <= 2500
end

-- Vehicle model names: letters, digits and underscores only.
function U.validModelName(model)
    return type(model) == 'string' and #model >= 2 and #model <= 32 and model:match('^[%w_]+$') ~= nil
end

return U
