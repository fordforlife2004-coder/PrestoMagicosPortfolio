-- Tests for the CAD's client scripts, run in a fake game. From the resource folder:
--   lua tests/client_spec.lua

local G = dofile('tests/fake_game.lua')
local T = G.runner()
local test, eq, ok, contains = T.test, T.eq, T.ok, T.contains

local ME = 7

local function unit(fields)
    local u = { id = ME, name = 'Sam Ortiz', callsign = 'A-1', department = 'lspd', role = 'police', status = 'available',
        location = { x = 100.0, y = 200.0, z = 30.0, street = 'Strawberry Ave' } }
    for k, v in pairs(fields or {}) do u[k] = v end
    return u
end

local function onDuty(fields) G.push('me', { id = ME, name = 'Sam Ortiz', unit = unit(fields) }) end
local function offDuty() G.push('me', { id = ME, name = 'Sam Ortiz', unit = nil }) end

local function lastNui(kind)
    for i = #G.nui, 1, -1 do
        if G.nui[i].type == kind then return G.nui[i] end
    end
    return nil
end

local function props()
    local n = 0
    for _, e in pairs(G.entities) do
        if e.kind == 'object' then n = n + 1 end
    end
    return n
end

local function lastFeed() return G.feed[#G.feed] and G.feed[#G.feed].text end

-- ------------------------------------------------------------------ the tablet

test('/cad opens the tablet with a tablet in your hands, and closes it again', function()
    G.load()
    G.command('cad')
    eq(G.focus, true)
    eq(lastNui('open').page, nil)
    eq(G.sent('Prest_Sector-CAD:watch').args[1], true)
    eq(props(), 1, 'the tablet prop')
    local prop
    for id, e in pairs(G.entities) do
        if e.kind == 'object' then prop = e end
    end
    eq(prop.attachedTo, G.ped)
    eq(prop.bone, Config.TabletProp.bone)
    eq(G.anims[1], Config.TabletProp.anim.dict .. '/' .. Config.TabletProp.anim.clip)
    G.command('cad')
    eq(G.focus, false)
    ok(lastNui('close'), 'the page is told to close')
    eq(G.sent('Prest_Sector-CAD:watch').args[1], false)
    eq(props(), 0, 'the prop is gone')
    eq(#G.stoppedAnims, 1)
    eq(G.keys.cad.key, 'F6')
end)

test('/civ opens on your civilian records; opening again only changes page', function()
    G.load()
    G.command('civ')
    eq(lastNui('open').page, 'civilian')
    local watches = G.count(G.toServer, function(m) return m.name == 'Prest_Sector-CAD:watch' end)
    G.callNui('close', {})
    eq(G.focus, false)
    G.load()
    G.command('cad')
    G.command('civ')
    eq(lastNui('open').page, 'civilian')
    eq(G.count(G.toServer, function(m) return m.name == 'Prest_Sector-CAD:watch' end), 1, 'only one watch for one opening')
    eq(props(), 1, 'and one prop')
    ok(watches == 1)
end)

test('no tablet prop in a vehicle; put away on death or getting into a vehicle', function()
    G.load()
    G.entities[G.ped].vehicle = G.addVehicle('CAR1')
    G.command('cad')
    eq(props(), 0, 'not in a vehicle')
    eq(G.focus, true, 'but the tablet still opens')
    G.command('cad')
    G.entities[G.ped].vehicle = 0
    G.command('cad')
    eq(props(), 1)
    G.entities[G.ped].dead = true
    G.tick(300)
    eq(props(), 0, 'put away when they die')
    G.entities[G.ped].dead = false
    G.command('cad')
    G.command('cad')
    eq(props(), 1)
    G.entities[G.ped].vehicle = G.addVehicle('CAR2')
    G.tick(300)
    eq(props(), 0, 'put away when they get into a vehicle')
end)

test('a tablet closed while its model is still loading never appears', function()
    G.load()
    G.modelsLoad = false
    G.command('cad')
    G.command('cad')
    G.modelsLoad = true
    G.tick(3500)
    eq(props(), 0)
end)

-- ------------------------------------------------------------------ the tablet's requests

test('requests go to the server and the answer comes back to the tablet', function()
    G.load()
    local answer = G.callNui('rpc', { action = 'person.search', payload = { query = 'bell' } })
    local sent = G.sent('Prest_Sector-CAD:rpc')
    local reqId = sent.args[1]
    eq(sent.args[2], 'person.search')
    eq(sent.args[3].query, 'bell')
    eq(answer(), nil, 'nothing until the server answers')
    G.reply(reqId + 100, true, 'not mine')
    eq(answer(), nil, 'answers to other requests are ignored')
    G.reply(reqId, true, { { first = 'Marcus' } })
    eq(answer().ok, true)
    eq(answer().result[1].first, 'Marcus')
    local refused = G.callNui('rpc', { action = 'person.delete', payload = { id = 1 } })
    G.reply(G.sent('Prest_Sector-CAD:rpc').args[1], false, "You aren't allowed to do that.")
    eq(refused().ok, false)
    eq(refused().error, "You aren't allowed to do that.")
    eq(G.callNui('rpc', 'garbage')().ok, false, 'a broken request is refused here')
end)

test('a request the server never answers fails after 10 seconds', function()
    G.load()
    local answer = G.callNui('rpc', { action = 'session' })
    G.tick(9999)
    eq(answer(), nil)
    G.tick(1)
    eq(answer().ok, false)
    contains(answer().error, "didn't answer")
    G.reply(G.sent('Prest_Sector-CAD:rpc').args[1], true, {})
    eq(answer().ok, false, 'a late answer changes nothing')
end)

test('pushes reach the tablet only while it is open, and are kept for the blips', function()
    G.load()
    G.push('units', { unit({ id = 2, callsign = 'A-2' }) })
    eq(lastNui('push'), nil, 'closed: nothing sent to the page')
    eq(#CadClient.units, 1, 'but kept')
    G.command('cad')
    G.push('call', { id = 1001, status = 'pending', title = 'Crash', priority = 2 })
    eq(lastNui('push').kind, 'call')
    eq(CadClient.calls[1001].title, 'Crash')
    G.push('call', { id = 1001, status = 'closed' })
    eq(CadClient.calls[1001], nil, 'closed calls are dropped')
end)

test('notifications: above the map, on the tablet when open, long ones in pieces', function()
    G.load()
    TriggerEvent('Prest_Sector-CAD:notify', 'Your call was sent to dispatch (#1004).', 'success')
    eq(lastFeed(), 'Your call was sent to dispatch (#1004).')
    eq(lastNui('push'), nil)
    G.command('cad')
    TriggerEvent('Prest_Sector-CAD:notify', ('x'):rep(250), 'error')
    eq(G.feed[#G.feed].pieces, 3, '99 characters per piece')
    eq(G.feed[#G.feed].important, true)
    eq(lastNui('push').kind, 'notify')
end)

test('waypoints from the tablet', function()
    G.load()
    G.callNui('waypoint', { x = 25, y = -1345.5 })
    eq(G.waypoint.x, 25.0)
    eq(G.waypoint.y, -1345.5)
    G.waypoint = nil
    G.callNui('waypoint', { x = 'here' })
    eq(G.waypoint, nil)
end)

test('exports for other scripts', function()
    G.load()
    G.exports.OpenCAD('people')
    eq(lastNui('open').page, 'people')
    eq(G.exports.IsOpen(), true)
    G.exports.CloseCAD()
    eq(G.exports.IsOpen(), false)
end)

-- ------------------------------------------------------------------ 911 and panic

test('/911, /311 and anonymous tips send what happened and where', function()
    G.load()
    G.command('911')
    contains(lastFeed(), 'Say what is happening')
    eq(G.sent('Prest_Sector-CAD:911'), nil)
    G.command('911', 'a', 'car', 'crashed')
    local sent = G.sent('Prest_Sector-CAD:911')
    eq(sent.args[1], '911')
    eq(sent.args[2], 'a car crashed')
    eq(sent.args[3], 'Strawberry Ave / Davis Ave, Strawberry')
    G.command('311', 'loud', 'music')
    eq(G.sent('Prest_Sector-CAD:911').args[1], '311')
    G.command('911a', 'drugs', 'at', 'the', 'park')
    eq(G.sent('Prest_Sector-CAD:911').args[1], 'anon')
    G.street = { main = 'Route 68', cross = nil, zone = 'DESRT', zoneLabel = 'Grand Senora Desert' }
    G.command('911', 'fire')
    eq(G.sent('Prest_Sector-CAD:911').args[3], 'Route 68, Grand Senora Desert', 'no cross street')
    eq(#G.suggestions, 3, 'chat suggestions for the commands')
end)

test('the panic button only works on duty', function()
    G.load()
    G.command('panic')
    contains(lastFeed(), 'while you are on duty')
    eq(G.sent('Prest_Sector-CAD:panic'), nil)
    onDuty()
    G.command('panic')
    eq(G.sent('Prest_Sector-CAD:panic').args[1], 'Strawberry Ave / Davis Ave, Strawberry')
    G.toServer = {}
    G.callNui('panic', {})
    ok(G.sent('Prest_Sector-CAD:panic'), 'from the tablet too')
end)

-- ------------------------------------------------------------------ on duty

test('on duty, your street is sent every few seconds; off duty it stops', function()
    G.load()
    G.tick(20000)
    eq(G.sent('Prest_Sector-CAD:location'), nil, 'nothing while off duty')
    onDuty()
    eq(G.count(G.toServer, function(m) return m.name == 'Prest_Sector-CAD:location' end), 1, 'straight away')
    G.tick(Config.LocationSeconds * 1000 * 3)
    eq(G.count(G.toServer, function(m) return m.name == 'Prest_Sector-CAD:location' end), 4)
    onDuty({ status = 'busy' })
    G.tick(Config.LocationSeconds * 1000)
    eq(G.count(G.toServer, function(m) return m.name == 'Prest_Sector-CAD:location' end), 5, 'still one loop after another update')
    offDuty()
    G.toServer = {}
    G.tick(30000)
    eq(G.sent('Prest_Sector-CAD:location'), nil)
end)

test('signing on through the tablet starts duty here too', function()
    G.load()
    local answer = G.callNui('rpc', { action = 'unit.signOn', payload = { callsign = 'A-1', department = 'lspd' } })
    G.reply(G.sent('Prest_Sector-CAD:rpc').args[1], true, { id = ME, unit = unit() })
    eq(answer().ok, true)
    ok(G.sent('Prest_Sector-CAD:location'), 'the location loop started')
    eq(CadClient.me.unit.callsign, 'A-1')
end)

test('other units on the map: one blip each, moved in place, gone when they go', function()
    G.load()
    G.push('units', { unit({ id = 2, callsign = 'A-2', location = { x = 1.0, y = 2.0, z = 3.0 } }) })
    eq(G.blipCount(), 0, 'no blips off duty')
    onDuty()
    eq(G.blipCount(), 1)
    local b = G.blipNamed('A-2')
    eq(b.colour, CadClient.blipColour('#3b82f6'))
    eq(b.sprite, 1)
    G.push('units', {
        unit(),
        unit({ id = 2, callsign = 'A-2', location = { x = 5.0, y = 6.0, z = 7.0 } }),
        unit({ id = 3, callsign = 'E-1', department = 'ems', status = 'panic', location = { x = 9.0, y = 9.0, z = 9.0 } }),
    })
    eq(G.blipCount(), 2, 'not your own unit')
    eq(G.blipNamed('A-2').x, 5.0)
    eq(G.blipNamed('A-2').moves, 1, 'moved, not made again')
    eq(G.blipNamed('E-1').colour, 1, 'a unit in panic is red')
    G.push('units', { unit() })
    eq(G.blipCount(), 0)
    G.push('units', { unit({ id = 2, callsign = 'A-2' }) })
    offDuty()
    eq(G.blipCount(), 0, 'all gone off duty')
end)

test('department colours turn into the nearest blip colour', function()
    G.load()
    eq(CadClient.blipColour('#ef4444'), 1, 'red')
    eq(CadClient.blipColour('#22c55e'), 2, 'green')
    eq(CadClient.blipColour('#eab308'), 5, 'yellow')
    eq(CadClient.blipColour('not a colour'), 3)
end)

test('calls on the map, coloured by priority, with a route to your call', function()
    G.load()
    onDuty()
    G.push('call', { id = 1001, status = 'pending', code = '10-50', title = 'Crash', priority = 2, source = '911',
        location = { x = 10.0, y = 20.0, z = 0.0, street = 'Route 68' } })
    G.push('call', { id = 1002, status = 'pending', code = '311', title = 'Music', priority = 3, source = '311' })
    eq(G.blipCount(), 1, 'calls without a position have no blip')
    local b = G.blipNamed('#1001 10-50 Crash')
    eq(b.colour, Config.CallBlips.colours[2])
    eq(b.sprite, Config.CallBlips.sprite)
    eq(b.route, false)
    onDuty({ callId = 1001 })
    eq(G.blipNamed('#1001 10-50 Crash').route, true, 'route to the call you are on')
    G.push('call', { id = 1001, status = 'closed' })
    eq(G.blipCount(), 0)
end)

test('the tablet loading the board fills in the call blips', function()
    G.load()
    onDuty()
    G.callNui('rpc', { action = 'call.list', payload = {} })
    G.reply(G.sent('Prest_Sector-CAD:rpc').args[1], true, {
        { id = 1001, status = 'active', code = '10-50', title = 'Crash', priority = 1, location = { x = 1.0, y = 1.0, z = 1.0 } },
        { id = 1002, status = 'closed', code = '10-50', title = 'Old', priority = 1, location = { x = 2.0, y = 2.0, z = 1.0 } },
    })
    eq(G.blipCount(), 1)
    ok(G.blipNamed('#1001 10-50 Crash'))
end)

test('alerts: a sound, a notification, a flashing blip for a panic, and GPS when you are put on a call', function()
    G.load()
    local call = { id = 1003, status = 'active', code = '10-99', title = 'PANIC: A-2 needs help', priority = 1, source = 'panic',
        location = { x = 50.0, y = 60.0, z = 0.0, street = 'Grove St' } }
    G.push('alert', { kind = 'panic', call = call })
    eq(#G.sounds, 0, 'nothing off duty')
    onDuty()
    G.push('alert', { kind = 'panic', call = call })
    eq(G.sounds[1], Config.Sounds.panic.name .. '/' .. Config.Sounds.panic.set)
    contains(lastFeed(), 'PANIC #1003 10-99 PANIC: A-2 needs help - Grove St')
    local b = G.blipNamed('#1003 10-99 PANIC: A-2 needs help')
    eq(b.flashes, true)
    eq(b.sprite, Config.CallBlips.panicSprite)
    G.tick(Config.Panic.blipSeconds * 1000 + 1)
    G.push('call', call)
    eq(G.blipNamed('#1003 10-99 PANIC: A-2 needs help').flashes, false, 'stops flashing after a while')
    G.push('alert', { kind = 'attached', call = { id = 1004, status = 'active', code = '10-50', title = 'Crash', priority = 2,
        location = { x = 7.0, y = 8.0, z = 0.0 } } })
    eq(G.waypoint.x, 7.0, 'GPS to the call you were put on')
    eq(G.sounds[2], Config.Sounds.attached.name .. '/' .. Config.Sounds.attached.set)
    G.push('alert', { kind = 'new', call = { id = 1005, status = 'pending', code = '10-66', title = 'Shots', priority = 1 } })
    eq(G.sounds[3], Config.Sounds.newCall.name .. '/' .. Config.Sounds.newCall.set)
end)

-- ------------------------------------------------------------------ the plate reader

test('/plate runs the vehicle ahead and shows what comes back', function()
    G.load()
    local car = G.addVehicle('  46EEK572 ')
    G.entities[G.ped].vehicle = G.addVehicle('MYCAR')
    G.command('plate')
    contains(lastFeed(), 'no vehicle in front')
    G.rayHit = car
    G.command('plate')
    local sent = G.sent('Prest_Sector-CAD:rpc')
    eq(sent.args[2], 'plate.check')
    eq(sent.args[3].plate, '46EEK572', 'trimmed')
    G.command('cad')
    G.reply(sent.args[1], true, { plate = '46EEK572', found = true, vehicle = { model = 'Sultan', color = 'Silver' },
        owner = { first = 'Marcus', last = 'Bell' }, alerts = { { text = 'Reported STOLEN.', tone = 'error' } } })
    eq(G.feed[#G.feed - 1].text, 'Plate 46EEK572: Silver Sultan - owner Marcus Bell')
    eq(lastFeed(), 'Reported STOLEN.')
    eq(lastNui('push').kind, 'plate', 'and on the tablet')
    G.command('plate')
    G.reply(G.sent('Prest_Sector-CAD:rpc').args[1], false, "You aren't allowed to do that.")
    eq(lastFeed(), "You aren't allowed to do that.")
end)

test('on foot, /plate picks the nearest vehicle in front of you', function()
    G.load()
    G.addVehicle('BEHIND', { x = 100.0, y = 197.0, z = 30.0 })
    G.addVehicle('FAR', { x = 100.0, y = 215.0, z = 30.0 })
    G.addVehicle('NEAR', { x = 101.0, y = 204.0, z = 30.0 })
    G.command('plate')
    eq(G.sent('Prest_Sector-CAD:rpc').args[3].plate, 'NEAR')
end)

test('the automatic reader: police in a vehicle, hits only, each plate once in a while', function()
    G.load(function(c) c.PlateReader.auto = true end)
    local car = G.addVehicle('ABC123')
    G.rayHit = car
    G.entities[G.ped].vehicle = G.addVehicle('MYCAR')
    G.tick(5000)
    eq(G.sent('Prest_Sector-CAD:rpc'), nil, 'off duty: not reading')
    onDuty({ role = 'fire', department = 'ems' })
    G.tick(5000)
    eq(G.sent('Prest_Sector-CAD:rpc'), nil, 'not for Fire/EMS')
    onDuty()
    G.tick(2000)
    local sent = G.sent('Prest_Sector-CAD:rpc')
    eq(sent.args[2], 'plate.check')
    local before = #G.feed
    G.reply(sent.args[1], true, { plate = 'ABC123', found = false, alerts = { { text = 'No record of this plate.', tone = 'warning' } } })
    eq(#G.feed, before, 'quiet on a plate that is not in the CAD')
    G.toServer = {}
    G.tick(60000)
    eq(G.sent('Prest_Sector-CAD:rpc'), nil, 'the same plate is not run again for a while')
    -- Just past the wait (and before the request's own 10 second timeout).
    G.tick(Config.PlateReader.repeatMinutes * 60000 - 60000 + 2500)
    sent = G.sent('Prest_Sector-CAD:rpc')
    ok(sent, 'run again later')
    G.reply(sent.args[1], true, { plate = 'ABC123', found = true, vehicle = { model = 'Asea', color = 'Red' },
        alerts = { { text = 'No registered owner.', tone = 'warning' }, { text = 'Registration: Expired.', tone = 'warning' } } })
    eq(lastFeed(), 'Registration: Expired.', 'a hit is shown')
    eq(G.count(G.feed, function(f) return f.text == 'No registered owner.' end), 0)
end)

-- ------------------------------------------------------------------ stopping

test('stopping the script lets go of the mouse, puts the tablet away and clears the map', function()
    G.load()
    onDuty()
    G.push('units', { unit({ id = 2, callsign = 'A-2' }) })
    G.push('call', { id = 1001, status = 'pending', code = '10-50', title = 'Crash', priority = 2, location = { x = 1.0, y = 1.0, z = 0.0 } })
    G.command('cad')
    eq(G.blipCount(), 2)
    G.stop()
    eq(G.focus, false)
    eq(props(), 0)
    eq(G.blipCount(), 0)
    G.toServer = {}
    G.tick(30000)
    eq(G.sent('Prest_Sector-CAD:location'), nil, 'no more locations')
end)

test('OpenPlate (for Prest_Sector-Radar) opens the tablet on the vehicle search and runs the plate', function()
    G.load()
    eq(G.exports.OpenPlate('!!'), false, 'not a plate')
    eq(G.exports.OpenPlate('abc 123'), true, 'opened')
    local open = lastNui('open')
    eq(open.page, 'vehicles', 'the vehicle page')
    eq(open.params.query, 'ABC123', 'searching for the plate')
    eq(G.focus, true, 'with the mouse')
    local sent = G.sent('Prest_Sector-CAD:rpc')
    eq(sent.args[2], 'plate.check')
    eq(sent.args[3].plate, 'ABC123')
    G.reply(sent.args[1], true, { plate = 'ABC123', found = true, alerts = { { text = 'Reported STOLEN.', tone = 'error' } } })
    eq(lastNui('push').kind, 'plate', 'the alerts on the tablet')
    G.exports.OpenPlate('XYZ1')
    G.reply(G.sent('Prest_Sector-CAD:rpc').args[1], false, "You aren't allowed to do that.")
    eq(lastFeed(), "You aren't allowed to do that.", 'a refusal is shown')
end)

T.finish()
