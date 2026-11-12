-- The radar's server (server/main.lua): who may use it, plate checks against the CAD and the hotlist,
-- limits, the /hotlist command, dispatch calls for hits, and the exports.

local F = dofile('tests/fake_server.lua')
local t = F.runner()

-- A fresh server with the CAD running, an officer with the ACE and a civilian.
local function start(configure, opts)
    F.reset()
    F.resources['Prest_Sector-CAD'] = (opts and opts.noCad) and 'missing' or 'started'
    F.addPlayer(1, 'Officer Bell', { aces = { 'radar.use' } })
    F.addPlayer(2, 'Civilian Joe')
    F.load(configure)
end

local BOLO = {
    plate = 'ABC123', found = true,
    alerts = { { text = 'BOLO: Robbery suspect', tone = 'error' }, { text = 'Registration: Expired.', tone = 'warning' } },
    vehicle = { color = 'Gray', model = 'Sultan' }, owner = { first = 'Ana', last = 'Diaz' },
}

t.test('starting up: it says it is ready and whether it checks the CAD', function()
    start()
    t.ok(F.logged('ready. Hotlist: 0 plates. Checking plates against Prest_Sector-CAD.'), 'with the CAD')
    start(nil, { noCad = true })
    t.ok(F.logged("Prest_Sector-CAD isn't running"), 'without the CAD')
end)

t.test('the ACE lets an officer use the radar; a civilian is told no', function()
    start()
    t.eq(F.allowed(1), true, 'officer')
    t.eq(F.allowed(2), false, 'civilian')
    t.eq(F.states[1].replicated, true, 'the state bag reaches their game')
end)

t.test('police on duty in the CAD can use it with no ACE, and lose it going off duty', function()
    start()
    F.cad.units[2] = { role = 'police', callsign = '1A-12' }
    F.flush(Config.Server.recheckSeconds)
    t.eq(F.allowed(2), true, 'on duty')
    F.cad.units[2] = { role = 'fire' }
    F.flush(Config.Server.recheckSeconds)
    t.eq(F.allowed(2), false, 'Fire/EMS is not in cadRoles')
    F.cad.units[2] = nil
    F.flush(Config.Server.recheckSeconds)
    t.eq(F.allowed(2), false, 'off duty')
end)

t.test('everyone = true lets anyone use it', function()
    start(function(c) c.Access.everyone = true end)
    t.eq(F.allowed(2), true, 'civilian')
end)

t.test('a player saying hello gets their answer at once', function()
    start()
    F.addPlayer(3, 'New Officer', { aces = { 'radar.use' } })
    F.send(3, 'Prest_Sector-Radar:hello')
    t.eq(F.allowed(3), true, 'new player')
end)

t.test('a CAD hit: the reasons, the car and the owner, and a line in the server log', function()
    start()
    F.cad.plates.ABC123 = BOLO
    local r = F.check(1, 'abc 123')
    t.eq(r.status, 'hit', 'status')
    t.eq(r.plate, 'ABC123', 'plate tidied')
    t.eq(r.reasons[1], 'BOLO: Robbery suspect', 'reason')
    t.eq(r.vehicle, 'Gray Sultan', 'vehicle')
    t.eq(r.owner, 'Ana Diaz', 'owner')
    t.ok(F.logged('Officer Bell (1): front camera hit on ABC123: BOLO: Robbery suspect'), 'logged')
end)

t.test('notices and clear plates', function()
    start()
    F.cad.plates.EXP1 = { plate = 'EXP1', found = true, alerts = { { text = 'Insurance: None.', tone = 'warning' } } }
    t.eq(F.check(1, 'EXP1').status, 'notice', 'notice')
    t.eq(F.check(1, 'NEW99').status, 'clear', 'unknown plate')
    start(function(c) c.PlateReader.notices = false end)
    F.cad.plates.EXP1 = { plate = 'EXP1', found = true, alerts = { { text = 'Insurance: None.', tone = 'warning' } } }
    t.eq(F.check(1, 'EXP1').status, 'clear', 'notices turned off')
end)

t.test('players who may not use the radar get no records', function()
    start()
    F.cad.plates.ABC123 = BOLO
    local r = F.check(2, 'ABC123')
    t.eq(r.error, 'not_allowed', 'refused')
    t.eq(r.status, nil, 'nothing about the plate')
    t.eq(F.cad.lookups, 0, 'the CAD was never asked')
end)

t.test('bad requests are refused without a lookup', function()
    start()
    t.eq(F.check(1, '!!!').error, 'bad_plate', 'not a plate')
    t.eq(F.check(1, 'ABC123', 'side').error, 'bad_request', 'no such camera')
    F.send(1, 'Prest_Sector-Radar:check', 'one', 'front', 'ABC123')
    t.eq(#F.toClients, 2, 'a request id that is not a number gets no answer')
    F.send(99, 'Prest_Sector-Radar:check', 1, 'front', 'ABC123')
    t.eq(#F.toClients, 2, 'nor does someone who is not a player')
    t.eq(F.cad.lookups, 0, 'no lookups')
end)

t.test('answers from moments ago are reused; then the CAD is asked again', function()
    start()
    F.check(1, 'ABC123')
    F.check(1, 'ABC123')
    t.eq(F.cad.lookups, 1, 'one lookup for two checks')
    F.advance(Config.Server.cacheSeconds + 1)
    F.check(1, 'ABC123')
    t.eq(F.cad.lookups, 2, 'asked again later')
end)

t.test('one player can only ask so often', function()
    start(function(c) c.Server.lookupsPerMinute = 3 end)
    for i = 1, 3 do t.ok(F.check(1, 'P' .. i).status, 'check ' .. i) end
    t.eq(F.check(1, 'P4').error, 'busy', 'the fourth is refused')
    F.advance(61)
    t.ok(F.check(1, 'P5').status, 'a minute later')
end)

t.test('the CAD failing or missing: hotlist plates still hit', function()
    start()
    F.cad.broken = true
    F.command(0, 'hotlist', 'add', 'HOT1', 'Stolen', 'from', 'Legion')
    local r = F.check(1, 'HOT1')
    t.eq(r.status, 'hit', 'hotlist hit with a broken CAD')
    t.eq(r.reasons[1], 'Hotlist: Stolen from Legion', 'reason')
    t.eq(F.check(1, 'OTHER').status, 'clear', 'and nothing else breaks')
    start(nil, { noCad = true })
    F.command(0, 'hotlist', 'add', 'HOT1', 'Stolen')
    t.eq(F.check(1, 'HOT1').status, 'hit', 'without the CAD')
    t.eq(F.cad.lookups, 0, 'the missing CAD is never called')
end)

t.test('/hotlist add, list and remove; the list survives a restart', function()
    start()
    F.command(1, 'hotlist', 'add', 'xyz999', 'Armed', 'suspect')
    t.contains(F.notes(1)[1], 'XYZ999 is on the hotlist for 12h 0m: Armed suspect', 'added')
    t.ok(F.logged('Officer Bell added XYZ999 to the hotlist'), 'logged')
    F.clear()
    F.command(1, 'hotlist')
    t.contains(F.notes(1)[1], 'Hotlist: 1 plate.', 'count')
    t.contains(F.notes(1)[2], 'XYZ999: Armed suspect (by Officer Bell', 'entry')
    F.load()
    t.eq(F.check(1, 'XYZ999').status, 'hit', 'still on after a restart')
    F.clear()
    F.command(1, 'hotlist', 'remove', 'XYZ999')
    t.contains(F.notes(1)[1], 'XYZ999 is off the hotlist.', 'removed')
    t.eq(F.check(1, 'XYZ999').status, 'clear', 'and no longer a hit at once')
    F.clear()
    F.command(1, 'hotlist', 'remove', 'XYZ999')
    t.contains(F.notes(1)[1], "isn't on the hotlist", 'removing twice')
end)

t.test('/hotlist checks what it is given, and civilians cannot use it', function()
    start()
    F.command(1, 'hotlist', 'add', 'ABC')
    t.contains(F.notes(1)[1], 'Give a reason', 'no reason')
    F.clear()
    F.command(1, 'hotlist', 'add', 'TOOLONGPLATE', 'x')
    t.contains(F.notes(1)[1], "isn't a plate", 'bad plate')
    F.clear()
    F.command(1, 'hotlist', 'shout')
    t.contains(F.notes(1)[1], 'Use /hotlist add PLATE reason', 'help')
    F.clear()
    F.command(2, 'hotlist', 'add', 'ABC', 'mine')
    t.contains(F.notes(2)[1], "aren't allowed", 'civilian')
    t.eq(F.check(1, 'ABC').status, 'clear', 'nothing was added')
end)

t.test('hotlist entries end on their own', function()
    start(function(c) c.Hotlist.hours = 1 end)
    F.command(0, 'hotlist', 'add', 'SHORT1', 'Briefly wanted')
    t.eq(F.check(1, 'SHORT1').status, 'hit', 'on')
    F.advance(3601)
    t.eq(F.check(1, 'SHORT1').status, 'clear', 'over after an hour')
end)

t.test('a full hotlist says so', function()
    start(function(c) c.Hotlist.max = 2 end)
    F.command(0, 'hotlist', 'add', 'A1', 'one')
    F.command(0, 'hotlist', 'add', 'A2', 'two')
    F.command(0, 'hotlist', 'add', 'A3', 'three')
    t.ok(F.logged('The hotlist is full (2 plates)'), 'full')
end)

t.test('a damaged saved hotlist is ignored, not fatal', function()
    F.reset()
    F.resources['Prest_Sector-CAD'] = 'started'
    F.addPlayer(1, 'Officer Bell', { aces = { 'radar.use' } })
    F.kvp['prestSectorRadar:hotlist'] = '{ not json'
    F.load()
    t.ok(F.logged('ready. Hotlist: 0 plates.'), 'started with an empty list')
    F.kvp['prestSectorRadar:hotlist'] = json.encode({ GOOD1 = { plate = 'GOOD1', reason = 'ok', by = 'x', at = F.now, ends = F.now + 60 },
        ['bad key'] = { reason = 'x', ends = F.now + 60 }, OLD1 = { plate = 'OLD1', reason = 'old', ends = F.now - 1 } })
    F.load()
    t.ok(F.logged('ready. Hotlist: 1 plate.'), 'only the good, current entry')
end)

t.test('dispatch calls for hits: off by default, then once per plate every 10 minutes', function()
    start()
    F.cad.plates.ABC123 = BOLO
    F.check(1, 'ABC123')
    t.eq(#F.cad.calls, 0, 'off by default')
    start(function(c) c.PlateReader.hitCall = true end)
    F.cad.plates.ABC123 = BOLO
    F.cad.units[1] = { role = 'police', callsign = '1A-12' }
    F.check(1, 'ABC123')
    t.eq(#F.cad.calls, 1, 'a call')
    local call = F.cad.calls[1]
    t.eq(call.title, 'Plate reader hit: ABC123', 'title')
    t.eq(call.code, '10-60', 'code')
    t.contains(call.description, 'Read by 1A-12', 'who read it')
    t.ok(call.coords and call.coords.x == 100.0, 'where')
    F.advance(Config.Server.cacheSeconds + 1)
    F.check(1, 'ABC123')
    t.eq(#F.cad.calls, 1, 'not again right away')
    F.advance(600)
    F.check(1, 'ABC123')
    t.eq(#F.cad.calls, 2, 'again after 10 minutes')
end)

t.test('exports for other scripts', function()
    start()
    F.cad.plates.ABC123 = BOLO
    t.eq(F.exports.IsAllowed(1), true, 'IsAllowed officer')
    t.eq(F.exports.IsAllowed(2), false, 'IsAllowed civilian')
    t.eq(F.exports.IsAllowed('nobody'), false, 'IsAllowed nonsense')
    t.eq(F.exports.CheckPlate('abc123').status, 'hit', 'CheckPlate')
    t.eq(F.exports.CheckPlate('!!'), nil, 'CheckPlate bad plate')
    F.invoking = 'my-script'
    local entry = F.exports.AddHotlist('NEW1', 'From another script', 2)
    t.eq(entry.by, 'my-script', 'who added it')
    t.eq(entry.ends - entry.at, 7200, 'their hours')
    t.eq(#F.exports.GetHotlist(), 1, 'GetHotlist')
    t.eq(F.exports.RemoveHotlist('new1'), true, 'RemoveHotlist')
    t.eq(F.exports.RemoveHotlist('new1'), false, 'RemoveHotlist twice')
end)

t.test('the CAD starting after the radar is noticed at once', function()
    start(nil, { noCad = true })
    F.cad.units[2] = { role = 'police' }
    F.resources['Prest_Sector-CAD'] = 'started'
    F.fire('onResourceStart', 'Prest_Sector-CAD')
    t.eq(F.allowed(2), true, 'on duty as soon as the CAD is up')
end)

t.test('a player leaving is forgotten', function()
    start(function(c) c.Server.lookupsPerMinute = 1 end)
    F.check(1, 'P1')
    F.drop(1)
    F.addPlayer(1, 'Officer Bell', { aces = { 'radar.use' } })
    t.ok(F.check(1, 'P2').status, 'a new player with the same number starts fresh')
end)

t.test('saying hello again and again changes nothing and sends nothing', function()
    start()
    local before = F.stateSets
    for _ = 1, 50 do F.send(2, 'Prest_Sector-Radar:hello') end
    t.eq(F.stateSets, before, 'no state bag updates when the answer is the same')
end)

t.test('a player over the limit costs the server nothing more', function()
    start(function(c) c.Server.lookupsPerMinute = 2 end)
    local before = F.cad.unitCalls
    for i = 1, 20 do F.check(2, 'SPAM' .. i) end
    t.ok(F.cad.unitCalls - before <= 2, 'the CAD was asked about them at most twice')
end)

t.test('the saved hotlist is loaded before other scripts can change it', function()
    F.reset()
    F.resources['Prest_Sector-CAD'] = 'started'
    F.addPlayer(1, 'Officer Bell', { aces = { 'radar.use' } })
    F.kvp['prestSectorRadar:hotlist'] = json.encode({
        OLD1 = { plate = 'OLD1', reason = 'one', by = 'x', at = F.now, ends = F.now + 3600 },
        OLD2 = { plate = 'OLD2', reason = 'two', by = 'x', at = F.now, ends = F.now + 3600 },
    })
    F.deferThreads = true
    F.load()
    F.exports.AddHotlist('NEW1', 'Added the moment the radar started')
    F.runThreads()
    t.eq(#F.exports.GetHotlist(), 3, 'the saved plates and the new one')
    F.load()
    F.runThreads()
    t.eq(#F.exports.GetHotlist(), 3, 'and all three were saved')
end)

t.finish()
