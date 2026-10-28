-- Tests the shared rules: styles, picking who to cuff, /cuffadjust's nudges and the config checker.
-- Run from the resource folder with any Lua 5.3+:  lua tests/cuffs_spec.lua

local t = dofile('tests/runner.lua')()
dofile('config.lua')
local C = dofile('shared/cuffs.lua')

local function at(x, y, z) return { x = x, y = y, z = z or 0 } end

t.test('styles by name, any capitals or a short name; nothing typed gives the default', function()
    t.eq(C.findStyle(Config, 'FRONT'), 'front')
    t.eq(C.findStyle(Config, 'infront'), 'front')
    t.eq(C.findStyle(Config, 'back'), 'rear')
    t.eq(C.findStyle(Config, nil), 'rear')
    t.eq(C.findStyle(Config, ''), 'rear')
    t.eq(C.findStyle(Config, 'chains'), nil)
    t.eq(C.findStyle(Config, 42), nil)
    local _, style = C.findStyle(Config, 'rear')
    t.eq(style.prop, 'p_cs_cuffs_02_s')
end)

t.test('the target is the closest player in reach, preferring someone in front', function()
    local me = at(0, 0)
    -- Heading 0 faces north (+y). One player 1.2 m ahead, one 0.8 m behind.
    local others = { { id = 7, coords = at(0, 1.2) }, { id = 8, coords = at(0, -0.8) } }
    t.eq(C.pickTarget(me, 0, others, 1.5), 7, 'in front beats closer behind')
    t.eq(C.pickTarget(me, 180, others, 1.5), 8, 'turn around and the other one is in front')
    t.eq(C.pickTarget(me, 0, { { id = 8, coords = at(0, -0.8) } }, 1.5), 8, 'behind is fine when nobody is in front')
    t.eq(C.pickTarget(me, 0, { { id = 9, coords = at(0, 3) } }, 1.5), nil, 'out of reach')
    t.eq(C.pickTarget(me, 90, { { id = 10, coords = at(-1, 0) }, { id = 11, coords = at(0.5, 0) } }, 1.5), 10,
        'heading 90 faces west')
    t.eq(C.pickTarget(me, 0, { { id = 12, coords = at(0, 0, 1.4) } }, 1.5), 12, 'right on top counts as in front')
end)

t.test('which side the officer stands on picks front or behind-the-back cuffs', function()
    local suspect = at(0, 0)
    t.eq(C.sideOf(suspect, 0, at(0, 1)), 'front', 'heading 0 faces north, officer to the north')
    t.eq(C.sideOf(suspect, 0, at(0.3, -1)), 'behind')
    t.eq(C.sideOf(suspect, 90, at(-1, 0)), 'front', 'heading 90 faces west')
    t.eq(C.styleFor(Config, nil, suspect, 0, at(0, 1)), 'front')
    t.eq(C.styleFor(Config, '', suspect, 0, at(0, -1)), 'rear')
    t.eq(C.styleFor(Config, 'rear', suspect, 0, at(0, 1)), 'rear', 'a typed style wins')
    Config.ChooseByPosition = false
    t.eq(C.styleFor(Config, nil, suspect, 0, at(0, 1)), 'rear', 'switched off: always the default')
    Config.ChooseByPosition = true
end)

t.test('front cuffs have their own animations; the rest use the usual ones', function()
    t.eq(C.animationFor(Config, 'cuff', 'front'), Config.Styles.front.cuff)
    t.eq(C.animationFor(Config, 'uncuff', 'rear'), Config.Animations.uncuff)
    t.eq(C.animationFor(Config, 'cuff', nil), Config.Animations.cuff)
end)

t.test('player IDs: whole numbers from 1 up, from numbers or text; anything else is nil', function()
    t.eq(C.toId(12), 12)
    t.eq(C.toId('12'), 12)
    t.eq(math.type(C.toId(12.0)), 'integer', '12.0 becomes the whole number 12')
    for _, bad in ipairs({ 12.5, 0, -1, 70000, 'twelve', {}, true }) do t.eq(C.toId(bad), nil, tostring(bad)) end
    t.eq(C.toId(nil), nil)
    t.eq(C.cuffsKey(12), 'prestSectorCuffs:12')
    t.eq(C.escortKey(C.toId(12.0)), 'prestSectorEscort:12')
end)

t.test('/cuffadjust nudges one axis and keeps angles from 0 to 360', function()
    local o, r = C.nudge({ -0.055, 0.06, 0.04 }, { 265, 155, 80 }, 'move', 2, 0.005)
    t.near(o[2], 0.065)
    t.eq(r[1], 265, 'moving leaves the rotation alone')
    o, r = C.nudge(o, r, 'turn', 1, 5)
    t.eq(r[1], 270.0)
    t.near(o[1], -0.055)
    o, r = C.nudge(o, r, 'turn', 3, -1)
    t.eq(r[3], 79.0)
    o, r = C.nudge(o, { 358, 0, 0 }, 'turn', 1, 5)
    t.eq(r[1], 3.0, 'past 360 it starts again')
    o, r = C.nudge(o, { 2, 0, 0 }, 'turn', 1, -5)
    t.eq(r[1], 357.0, 'below 0 too')
    o = C.nudge({ 0.1, 0, 0 }, { 0, 0, 0 }, 'move', 1, -0.0004)
    t.near(o[1], 0.1, 'rounded to millimetres')
end)

t.test('the line it prints can be pasted into config.lua', function()
    local line = C.attachLine({ -0.055, 0.06, 0.04 }, { 265, 155, 80 })
    t.eq(line, 'offset = { -0.055, 0.060, 0.040 }, rotation = { 265.0, 155.0, 80.0 },')
    local style = load('return {' .. line .. '}')()
    t.near(style.offset[1], -0.055)
    t.eq(style.rotation[3], 80.0)
end)

t.test('the config checker finds mistakes', function()
    local bad = {
        Styles = {
            rear = { label = 'x', prop = 'p_cs_cuffs_02_s', bone = 60309, offset = { 0, 0 }, rotation = { 0, 0, 0 }, anim = { dict = 'a' } },
            back = {
                label = 'x', prop = 'bad name!', bone = 'hand', offset = { 0, 0, 0 }, rotation = { 0, 0, 0 },
                anim = { dict = 'a', clip = 'b' }, cuff = { seconds = 3, officer = { dict = 'a', clip = 'b' } },
            },
        },
        DefaultStyle = 'cuffs',
        ChooseByPosition = true,
        MaxDistance = 20,
        VehicleDistance = 4,
        Animations = { cuff = { seconds = 0, officer = { dict = 'a', clip = 'b' }, suspect = {} } },
        Escort = { bone = 11816, offset = { 0, 0, 0 }, walk = { dict = 'a' } },
    }
    local text = table.concat(C.checkConfig(bad), '\n')
    for _, part in ipairs({
        'Config.Styles.rear: offset must be { x, y, z }',
        'Config.Styles.rear: anim must be',
        'Config.Styles.back: "back" is already a short name for rear',
        'Config.Styles.back: prop must be a model name',
        'Config.Styles.back: bone must be a bone ID number',
        'Config.Styles.back.cuff.suspect must be',
        'Config.DefaultStyle: "cuffs" is not a style',
        'Config.ChooseByPosition needs a style called front',
        'Config.Escort.walk must be',
        'Config.MaxDistance must be between 0.5 and 5 metres',
        'Config.Animations.cuff.seconds must be between 0 and 15',
        'Config.Animations.cuff.suspect must be',
        'Config.Animations.uncuff is missing',
    }) do t.contains(text, part) end
    t.contains(table.concat(C.checkConfig({ Styles = {}, Escort = { bone = 11816 } }), '\n'),
        'Config.Escort needs a bone and an offset')
    t.eq(#C.checkConfig(Config), 0, 'the shipped config is fine')
end)

t.finish()
