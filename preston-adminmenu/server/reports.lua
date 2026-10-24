-- Player reports: /report <message> sends a ticket to online staff, who claim it, go to the player and close it.

Reports = { list = {} }

local U = PrestonAdminUtil
local nextId = 1
local lastReportAt = {}

local function notify(target, message, tone)
    TriggerClientEvent('preston-admin:toast', target, { message = message, tone = tone or 'info' })
end

function Reports.notifyStaff(message, tone)
    for _, id in ipairs(GetPlayers()) do
        if IsPlayerAceAllowed(id, Config.Permissions.reports) then notify(tonumber(id), message, tone) end
    end
end

function Reports.openCount()
    local n = 0
    for _, r in pairs(Reports.list) do
        if r.status ~= 'closed' then n = n + 1 end
    end
    return n
end

function Reports.forMenu()
    local out = {}
    for _, r in pairs(Reports.list) do
        out[#out + 1] = {
            id = r.id, reporter = r.reporter, reporterName = r.reporterName, message = r.message, createdAt = r.createdAt,
            status = r.status, claimedBy = r.claimedBy, online = GetPlayerName(r.reporter) ~= nil,
        }
    end
    -- Open first, then claimed, then closed; newest first within each.
    local order = { open = 1, claimed = 2, closed = 3 }
    table.sort(out, function(a, b)
        if a.status ~= b.status then return order[a.status] < order[b.status] end
        return a.createdAt > b.createdAt
    end)
    return out
end

function Reports.get(id)
    local report = Reports.list[tonumber(id) or -1]
    if not report then error({ userMessage = 'That report no longer exists.' }) end
    return report
end

function Reports.claim(id, adminSrc)
    local report = Reports.get(id)
    if report.status == 'closed' then error({ userMessage = 'That report is already closed.' }) end
    report.status = 'claimed'
    report.claimedBy = GetPlayerName(adminSrc)
    if GetPlayerName(report.reporter) then notify(report.reporter, ('%s is looking at your report.'):format(report.claimedBy), 'success') end
    return report
end

function Reports.close(id, adminSrc)
    local report = Reports.get(id)
    report.status = 'closed'
    report.claimedBy = report.claimedBy or GetPlayerName(adminSrc)
    if GetPlayerName(report.reporter) then notify(report.reporter, 'Your report was closed by staff. Thanks for letting us know.', 'success') end
    return report
end

RegisterCommand('report', function(src, args)
    if src == 0 then return end
    local message = U.sanitize(table.concat(args, ' '), 300)
    if #message < 3 then
        notify(src, 'Write what happened: /report someone is ramming cars at Legion Square', 'warn')
        return
    end
    local now = os.time()
    if lastReportAt[src] and now - lastReportAt[src] < Config.ReportCooldownSeconds then
        notify(src, ('Please wait %ds before sending another report.'):format(Config.ReportCooldownSeconds - (now - lastReportAt[src])), 'warn')
        return
    end
    local open = 0
    for _, r in pairs(Reports.list) do
        if r.reporter == src and r.status ~= 'closed' then open = open + 1 end
    end
    if open >= Config.MaxOpenReportsPerPlayer then
        notify(src, 'You already have reports waiting. Staff will get to them soon.', 'warn')
        return
    end
    lastReportAt[src] = now
    local report = { id = nextId, reporter = src, reporterName = GetPlayerName(src), message = message, createdAt = now, status = 'open' }
    Reports.list[report.id] = report
    nextId = nextId + 1
    notify(src, ('Report #%d sent to staff.'):format(report.id), 'success')
    Reports.notifyStaff(('New report #%d from %s: %s'):format(report.id, report.reporterName, message), 'warn')
    Logs.add(src, 'New report', ('#%d: %s'):format(report.id, message), nil, 'warn')
end, false)

AddEventHandler('playerDropped', function()
    lastReportAt[source] = nil
end)
