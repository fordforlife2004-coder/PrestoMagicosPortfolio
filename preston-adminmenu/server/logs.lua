-- Records every admin action: in the server console, in the menu's Logs tab, and in Discord when a
-- webhook is set. The webhook URL is read from a server convar so it never reaches players' games.

Logs = {}

local U = PrestonAdminUtil
local recent = U.newRing(200)
local webhook = GetConvar('preston_admin_webhook', '')
local queue = {}

local COLORS = { info = 3447003, warn = 15105570, danger = 15158332, success = 3066993 }

local function playerLabel(src)
    if not src or src == 0 then return 'Console' end
    return ('%s (#%d)'):format(GetPlayerName(src) or 'unknown', src)
end

local function license(src)
    if not src or src == 0 then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return nil
end

-- tone: 'info', 'warn', 'danger' or 'success' (the Discord embed color).
function Logs.add(actorSrc, action, detail, targetSrc, tone)
    local entry = {
        time = os.time(),
        actor = playerLabel(actorSrc),
        action = action,
        detail = detail or '',
        target = targetSrc and playerLabel(targetSrc) or nil,
        tone = COLORS[tone or 'info'] and tone or 'info',
    }
    recent.push(entry)
    print(('[preston-admin] %s: %s%s%s'):format(entry.actor, action,
        entry.target and (' -> ' .. entry.target) or '', entry.detail ~= '' and (' (' .. entry.detail .. ')') or ''))

    if webhook == '' then return end
    local fields = { { name = 'By', value = entry.actor .. (license(actorSrc) and ('\n`' .. license(actorSrc) .. '`') or ''), inline = true } }
    if entry.target then
        fields[#fields + 1] = { name = 'Player', value = entry.target .. (license(targetSrc) and ('\n`' .. license(targetSrc) .. '`') or ''), inline = true }
    end
    queue[#queue + 1] = {
        title = action,
        description = entry.detail ~= '' and entry.detail or nil,
        color = COLORS[entry.tone],
        fields = fields,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', entry.time),
        footer = { text = 'Preston Admin Menu v2' },
    }
end

function Logs.recent()
    return recent.list()
end

-- Sends queued embeds one at a time, well under Discord's rate limit.
CreateThread(function()
    if webhook == '' then return end
    while true do
        Wait(1500)
        local embed = table.remove(queue, 1)
        if embed then
            PerformHttpRequest(webhook, function(status)
                if status ~= 200 and status ~= 204 then
                    print(('[preston-admin] Discord webhook returned %s'):format(tostring(status)))
                end
            end, 'POST', json.encode({
                username = 'Admin Menu',
                embeds = { embed },
                -- Player names can contain @everyone; never let them ping anyone.
                allowed_mentions = { parse = {} },
            }), { ['Content-Type'] = 'application/json' })
        end
    end
end)
