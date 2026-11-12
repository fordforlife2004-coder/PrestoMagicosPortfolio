-- The shared rules (shared/radar.lua): geometry, readings, plates, settings, the hotlist and limits.

local t = dofile('tests/runner.lua')()
dofile('tests/json.lua')
dofile('config.lua')
dofile('shared/radar.lua')
local R = Radar

local function mph(n) return n / 2.2369363 end
local NORTH = { x = 0.0, y = 1.0 }
local beam = { range = 150.0, angle = 6.0, nearWidth = 3.0, height = 10.0 }
local patrol = { id = 1, pos = { x = 0.0, y = 0.0, z = 30.0 }, forward = NORTH }
local function car(id, x, y, speed) return { id = id, pos = { x = x, y = y, z = 30.0 }, vel = { x = 0.0, y = speed }, speed = math.abs(speed) } end

t.test('speeds in mph and km/h', function()
    t.eq(R.round(R.toUnits(mph(60), 'mph')), 60, 'mph')
    t.eq(R.round(R.toUnits(10, 'kmh')), 36, 'km/h')
    t.eq(R.toUnits(nil, 'mph'), 0, 'nothing')
end)

t.test('where a car sits compared with the patrol car, whichever way it faces', function()
    local rel = R.relative({ x = 0, y = 0, z = 0 }, NORTH, { x = 2, y = 50, z = 1 })
    t.near(rel.ahead, 50, 'ahead')
    t.near(rel.side, 2, 'to the right')
    t.near(rel.up, 1, 'above')
    -- Facing east, a car to the north is to the left.
    local east = R.relative({ x = 0, y = 0, z = 0 }, { x = 2, y = 0 }, { x = 10, y = 5 })
    t.near(east.ahead, 10, 'ahead facing east')
    t.near(east.side, -5, 'left facing east')
    t.eq(R.relative({ x = 0, y = 0 }, { x = 0, y = 0 }, { x = 1, y = 1 }), nil, 'no heading')
end)

t.test('the beam: in front or behind, in range, near the center line, not on a bridge', function()
    local function sees(x, y, z, dir) return R.inBeam(R.relative(patrol.pos, NORTH, { x = x, y = y, z = z or 30.0 }), dir or 1, beam) end
    t.ok(sees(0, 60), 'straight ahead')
    t.ok(sees(2.9, 5), 'just ahead in the next lane over')
    t.ok(not sees(5, 5), 'too far to the side up close')
    t.ok(sees(12, 100), 'the beam spreads with distance')
    t.ok(not sees(0, 160), 'out of range')
    t.ok(not sees(0, 1), 'too close: that is the patrol car itself')
    t.ok(not sees(0, -60), 'behind is not in front')
    t.ok(sees(0, -60, 30, -1), 'the rear antenna sees behind')
    t.ok(not sees(0, 60, 45), 'on a bridge above')
end)

t.test('which way a car is going: same, opposite, or crossing', function()
    t.eq(R.direction(NORTH, { x = 0, y = 20 }), 'same', 'same way')
    t.eq(R.direction(NORTH, { x = 0, y = -20 }), 'opp', 'oncoming')
    t.eq(R.direction(NORTH, { x = 20, y = 0 }), nil, 'crossing')
    t.eq(R.direction(NORTH, { x = 0, y = 0.2 }), nil, 'barely moving')
    t.ok(R.modeAllows('both', 'opp') and R.modeAllows('same', 'same') and not R.modeAllows('same', 'opp'), 'modes')
    t.ok(not R.modeAllows('both', nil), 'crossing cars never count')
end)

t.test('an antenna reads the closest car, and the fastest when it is faster', function()
    local cars = { car(2, 0, 40, mph(55)), car(3, 1, 110, mph(82)), car(4, 0, -30, mph(40)), car(1, 0, 0, mph(50)) }
    local target, fast = R.readAntenna(patrol, cars, 1, 'both', beam, 'mph', 3)
    t.eq(target.id, 2, 'closest in front')
    t.eq(target.speed, 55, 'its speed')
    t.eq(fast.id, 3, 'the fastest')
    t.eq(fast.speed, 82, 'its speed')
    local rear = R.readAntenna(patrol, cars, -1, 'both', beam, 'mph', 3)
    t.eq(rear.id, 4, 'the rear antenna')
end)

t.test('no fast reading when the closest car is also the fastest; slow cars are ignored', function()
    local target, fast = R.readAntenna(patrol, { car(2, 0, 40, mph(70)), car(3, 0, 90, mph(60)) }, 1, 'both', beam, 'mph', 3)
    t.eq(target.speed, 70, 'target')
    t.eq(fast, nil, 'no fast')
    local still = R.readAntenna(patrol, { car(2, 0, 40, 0.5) }, 1, 'both', beam, 'mph', 3)
    t.eq(still, nil, 'a parked car')
end)

t.test('same and opposite modes pick their cars', function()
    local cars = { car(2, 0, 30, mph(50)), car(3, -2, 60, -mph(65)) }
    t.eq(R.readAntenna(patrol, cars, 1, 'same', beam, 'mph', 3).id, 2, 'same direction')
    t.eq(R.readAntenna(patrol, cars, 1, 'opp', beam, 'mph', 3).id, 3, 'oncoming')
end)

t.test('a plate camera reads the closest car, moving or parked', function()
    local cam = { range = 40.0, angle = 14.0 }
    local cars = { car(2, 0, 35, 0), car(3, 0, 12, mph(30)), car(4, 0, 60, 0) }
    t.eq(R.readCamera(patrol, cars, 1, cam).id, 3, 'closest')
    t.eq(R.readCamera(patrol, { car(4, 0, 60, 0) }, 1, cam), nil, 'out of reach')
end)

t.test('plates are tidied like the CAD tidies them', function()
    t.eq(R.plateKey(' ab-12 3c '), 'AB123C', 'tidied')
    t.eq(R.plateKey('TOOLONG12'), nil, 'nine characters')
    t.eq(R.plateKey('  '), nil, 'blank')
    t.eq(R.plateKey(42), nil, 'not text')
    t.eq(R.plateStyle(3), 3, 'a style')
    t.eq(R.plateStyle(9), 0, 'unknown style')
    t.eq(R.plateStyle('x'), 0, 'not a number')
end)

t.test('a CAD answer becomes a hit, a notice, or clear', function()
    local hit = R.classify('ABC123', {
        found = true,
        alerts = { { text = 'BOLO: Robbery suspect', tone = 'error' }, { text = 'Registration: Expired.', tone = 'warning' } },
        vehicle = { color = 'Gray', model = 'Sultan' }, owner = { first = 'Ana', last = 'Diaz' },
    }, nil, true)
    t.eq(hit.status, 'hit', 'status')
    t.eq(hit.reasons[1], 'BOLO: Robbery suspect', 'the hit first')
    t.eq(hit.reasons[2], 'Registration: Expired.', 'then the notice')
    t.eq(hit.vehicle, 'Gray Sultan', 'vehicle')
    t.eq(hit.owner, 'Ana Diaz', 'owner')
    t.ok(hit.inCad, 'in the CAD')
    local notice = R.classify('ABC123', { found = true, alerts = { { text = 'Insurance: None.', tone = 'warning' } } }, nil, true)
    t.eq(notice.status, 'notice', 'a notice')
    t.eq(R.classify('ABC123', { found = true, alerts = { { text = 'Insurance: None.', tone = 'warning' } } }, nil, false).status, 'clear',
        'notices turned off')
    local unknown = R.classify('ZZZ1', { found = false, alerts = { { text = 'No record of this plate.', tone = 'warning' } } }, nil, true)
    t.eq(unknown.status, 'clear', 'a plate the CAD has never heard of')
    t.eq(#unknown.reasons, 0, 'with nothing to say')
end)

t.test('the hotlist makes a hit with or without the CAD', function()
    local r = R.classify('ABC123', nil, { reason = 'Stolen from Legion' }, true)
    t.eq(r.status, 'hit', 'hit')
    t.eq(r.reasons[1], 'Hotlist: Stolen from Legion', 'reason')
    t.eq(R.classify('ABC123', 'nonsense', nil, true).status, 'clear', 'a broken CAD answer is ignored')
end)

t.test('saved settings are checked and filled in', function()
    local s = R.cleanSettings(nil, Config)
    t.eq(s.front.mode, 'both', 'front mode')
    t.eq(s.fastLimit, Config.Radar.fastLimit, 'fast limit from the config')
    t.ok(s.plates and s.front.on and s.rear.on, 'everything on')
    local odd = R.cleanSettings({ front = { on = false, mode = 'sideways' }, fastLimit = 9999, volume = -5, scale = 'big',
        pos = { x = 0.5, y = 2 }, fastLock = 'yes' }, Config)
    t.eq(odd.front.on, false, 'off stays off')
    t.eq(odd.front.mode, 'both', 'unknown mode')
    t.eq(odd.fastLimit, 250, 'limit capped')
    t.eq(odd.volume, 0, 'volume floored')
    t.eq(odd.scale, 1.0, 'scale default')
    t.eq(odd.pos.y, 1, 'position kept on screen')
    t.eq(odd.fastLock, false, 'only true turns fast lock on')
end)

t.test('the hotlist: add, renew, find, end, and a limit on size', function()
    local list, now = {}, 1000
    local e = R.hotlistAdd(list, 'abc 123', '  Stolen   car ', 'Officer Bell', now, 2, 3)
    t.eq(e.plate, 'ABC123', 'plate')
    t.eq(e.reason, 'Stolen car', 'reason tidied')
    t.eq(e.ends, now + 7200, 'ends in two hours')
    t.ok(R.hotlistFind(list, 'ABC123', now + 7199), 'still on')
    t.eq(R.hotlistFind(list, 'ABC123', now + 7200), nil, 'over')
    local _, err = R.hotlistAdd(list, 'XYZ', '', 'x', now, 2, 3)
    t.contains(err, 'Give a reason', 'needs a reason')
    _, err = R.hotlistAdd(list, '!!!', 'x', 'x', now, 2, 3)
    t.contains(err, "isn't a plate", 'needs a plate')
    R.hotlistAdd(list, 'B1', 'one', 'x', now, 2, 3)
    R.hotlistAdd(list, 'B2', 'two', 'x', now, 2, 3)
    _, err = R.hotlistAdd(list, 'B3', 'three', 'x', now, 2, 3)
    t.contains(err, 'full', 'full')
    t.ok(R.hotlistAdd(list, 'ABC123', 'renewed', 'x', now + 10, 2, 3), 'renewing one already on it still works')
    t.ok(R.hotlistAdd(list, 'B3', 'three', 'x', now + 9000, 2, 3), 'room again once the others end')
    t.eq(R.hotlistCount(list), 1, 'the ended ones were cleared out')
end)

t.test('hotlist entries newest first', function()
    local list = {}
    R.hotlistAdd(list, 'OLD1', 'old', 'x', 100, 5, 10)
    R.hotlistAdd(list, 'NEW1', 'new', 'x', 200, 5, 10)
    local entries = R.hotlistEntries(list, 300)
    t.eq(entries[1].plate, 'NEW1', 'newest')
    t.eq(#R.hotlistEntries(list, 100 + 5 * 3600), 1, 'ended ones left out')
end)

t.test('one player can ask only so often in a minute', function()
    local bucket = {}
    for _ = 1, 3 do t.ok(R.allowRequest(bucket, 1000, 3), 'allowed') end
    t.ok(not R.allowRequest(bucket, 2000, 3), 'the fourth in the same minute')
    t.ok(R.allowRequest(bucket, 61000, 3), 'a new minute')
end)

t.test('text from players is made safe', function()
    t.eq(R.text('  a\nb\tc  ', 10), 'a b c', 'one line')
    t.eq(R.text('abcdefghij', 4), 'abcd', 'cut')
    t.eq(R.text(nil, 4), '', 'nothing')
end)

t.test('the shipped config has no problems, and mistakes are named', function()
    t.eq(#R.checkConfig(Config), 0, 'shipped config')
    local bad = { Units = 'knots', Radar = { range = 0, angle = 6, updateMs = 200, fastLimit = 75 }, PlateReader = { range = 40, angle = 14, repeatSeconds = 300 },
        Hotlist = { hours = 12, max = 0 }, Server = { lookupsPerMinute = 60 }, Access = { cadRoles = 'police' }, Vehicles = { models = {} } }
    local problems = table.concat(R.checkConfig(bad), ' ')
    t.contains(problems, 'Config.Units', 'units')
    t.contains(problems, 'Config.Radar.range', 'range')
    t.contains(problems, 'Config.Hotlist.max', 'max')
    t.contains(problems, 'cadRoles', 'roles')
end)

t.finish()
