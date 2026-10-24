-- Saved bans, checked when players connect. A ban matches a player's license, Discord, Steam and
-- other identifiers plus their hardware tokens, so a new name or a cleared cache doesn't get around it.

Bans = { list = {} }

local U = PrestonAdminUtil
local recentlyLeft = {} -- the last 30 players to leave, so someone who quits mid-incident can still be banned
local nextLeftId = 1

local function tokensOf(src)
    local tokens = {}
    for i = 0, GetNumPlayerTokens(src) - 1 do
        tokens[#tokens + 1] = GetPlayerToken(src, i)
    end
    return tokens
end

function Bans.load()
    Bans.list = {}
    for _, ban in ipairs(Storage.loadBans()) do Bans.list[ban.id] = ban end
end

function Bans.message(ban)
    local lines = {
        'You are banned from this server.',
        ('Reason: %s'):format(ban.reason),
        ban.expiresAt and ('Ends in: %s'):format(U.formatRemaining(ban.expiresAt - os.time())) or 'This ban is permanent.',
        ('Ban ID: #%d'):format(ban.id),
    }
    if Config.BanAppealText ~= '' then lines[#lines + 1] = Config.BanAppealText end
    return table.concat(lines, '\n')
end

-- Bans from stored details (an online player's, or one who recently left). durationSeconds nil = permanent.
local function create(details, reason, durationSeconds, bannedBy)
    local now = os.time()
    local ban = {
        name = U.sanitize(details.name, 64),
        reason = reason,
        identifiers = U.banIdentifiers(details.identifiers, Config.BanIpAddresses),
        tokens = details.tokens or {},
        bannedBy = bannedBy,
        createdAt = now,
        expiresAt = durationSeconds and (now + durationSeconds) or nil,
        active = true,
    }
    if #ban.identifiers == 0 and #ban.tokens == 0 then error({ userMessage = 'That player has no identifiers to ban.' }) end
    ban.id = Storage.insertBan(ban)
    Bans.list[ban.id] = ban
    return ban
end

-- Saves a ban for an online player. The caller logs it and then drops the player with Bans.message(ban).
function Bans.banPlayer(target, reason, durationSeconds, bannedBy)
    return create({ name = GetPlayerName(target), identifiers = GetPlayerIdentifiers(target), tokens = tokensOf(target) },
        reason, durationSeconds, bannedBy)
end

function Bans.banRecent(leftId, reason, durationSeconds, bannedBy)
    for i, left in ipairs(recentlyLeft) do
        if left.id == leftId then
            table.remove(recentlyLeft, i)
            return create(left, reason, durationSeconds, bannedBy)
        end
    end
    error({ userMessage = 'That player is no longer in the recently-left list.' })
end

function Bans.unban(id, unbannedBy)
    local ban = Bans.list[id]
    if not ban then error({ userMessage = ('Ban #%s is not active.'):format(tostring(id)) }) end
    Storage.deactivateBan(id, unbannedBy)
    Bans.list[id] = nil
    return ban
end

-- Active bans for the menu, newest first.
function Bans.active()
    local now = os.time()
    local out = {}
    for _, ban in pairs(Bans.list) do
        if not U.isExpired(ban, now) then
            out[#out + 1] = {
                id = ban.id, name = ban.name, reason = ban.reason, bannedBy = ban.bannedBy, createdAt = ban.createdAt,
                remaining = ban.expiresAt and U.formatRemaining(ban.expiresAt - now) or 'Permanent',
            }
        end
    end
    table.sort(out, function(a, b) return a.createdAt > b.createdAt end)
    return out
end

function Bans.recentlyLeft()
    local out = {}
    for i = #recentlyLeft, 1, -1 do
        local left = recentlyLeft[i]
        out[#out + 1] = { id = left.id, name = left.name, leftAt = left.leftAt, reason = left.reason }
    end
    return out
end

AddEventHandler('playerDropped', function(reason)
    local src = source
    recentlyLeft[#recentlyLeft + 1] = {
        id = nextLeftId,
        name = GetPlayerName(src) or 'unknown',
        identifiers = GetPlayerIdentifiers(src),
        tokens = tokensOf(src),
        leftAt = os.time(),
        reason = U.sanitize(reason or '', 80),
    }
    nextLeftId = nextLeftId + 1
    if #recentlyLeft > 30 then table.remove(recentlyLeft, 1) end
end)

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Checking the ban list...')
    local ban = U.findBan(Bans.list, GetPlayerIdentifiers(src), tokensOf(src), os.time(), Config.BanIpAddresses)
    if ban then
        deferrals.done(Bans.message(ban))
        Logs.add(nil, 'Blocked a banned player', ('%s tried to join (ban #%d: %s)'):format(GetPlayerName(src) or 'unknown', ban.id, ban.reason), nil, 'warn')
    else
        deferrals.done()
    end
end)
