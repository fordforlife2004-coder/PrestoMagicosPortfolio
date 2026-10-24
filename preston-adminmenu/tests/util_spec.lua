-- Tests for server/util.lua. Run them from the resource folder with any Lua 5.3+:  lua tests/util_spec.lua

local U = dofile('server/util.lua')

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(('FAIL %s: %s'):format(name, tostring(err)))
    end
end

local function eq(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label or 'value', tostring(expected), tostring(actual)), 2)
    end
end

test('parseDuration reads minutes, hours, days and weeks', function()
    eq(U.parseDuration('30m'), 1800)
    eq(U.parseDuration('12h'), 43200)
    eq(U.parseDuration('7d'), 604800)
    eq(U.parseDuration('2w'), 1209600)
    eq(U.parseDuration(' 1 D '), 86400, 'spaces and capitals')
end)

test('parseDuration: perm is permanent, everything else invalid', function()
    eq(U.parseDuration('perm'), nil)
    eq(U.parseDuration('Permanent'), nil)
    eq(U.parseDuration('0d'), false)
    eq(U.parseDuration('-1d'), false)
    eq(U.parseDuration('1y'), false)
    eq(U.parseDuration('abc'), false)
    eq(U.parseDuration(''), false)
    eq(U.parseDuration(5), false)
    eq(U.parseDuration(nil), false)
    eq(U.parseDuration('100001m'), false, 'too long')
end)

test('formatRemaining', function()
    eq(U.formatRemaining(273600), '3d 4h')
    eq(U.formatRemaining(86400), '1d')
    eq(U.formatRemaining(5400), '1h 30m')
    eq(U.formatRemaining(3600), '1h')
    eq(U.formatRemaining(2700), '45m')
    eq(U.formatRemaining(20), 'less than a minute')
    eq(U.formatRemaining(nil), 'never')
end)

test('sanitize strips color codes and control characters', function()
    eq(U.sanitize('^1Hello^7 world'), 'Hello world')
    eq(U.sanitize('a\nb\tc'), 'a b c')
    eq(U.sanitize('   spaced    out  '), 'spaced out')
    eq(U.sanitize(nil), '')
    eq(U.sanitize({}), '')
end)

test('sanitize cuts to a length without splitting UTF-8 characters', function()
    eq(U.sanitize(('x'):rep(10), 4), 'xxxx')
    eq(U.sanitize('h\195\169llo', 2), 'h\195\169', 'cut after the accented letter')
    eq(U.sanitize('h\195\169llo', 5), 'h\195\169llo', '5 characters fit in 5')
end)

test('banIdentifiers leaves out IP addresses unless asked', function()
    local ids = { 'license:abc', 'ip:1.2.3.4', 'discord:1', 'not-an-id' }
    eq(#U.banIdentifiers(ids, false), 2)
    eq(#U.banIdentifiers(ids, true), 3)
    eq(#U.banIdentifiers(nil, false), 0)
end)

test('displayIdentifiers never shows IP addresses', function()
    local shown = U.displayIdentifiers({ 'license:a', 'ip:1.2.3.4', 'steam:b', 'discord:c', 'fivem:d', 'xbl:e', 'live:f' })
    eq(#shown, 6)
    for _, id in ipairs(shown) do eq(id:sub(1, 3) ~= 'ip:', true, id) end
end)

test('isExpired', function()
    eq(U.isExpired({ expiresAt = 100 }, 99), false)
    eq(U.isExpired({ expiresAt = 100 }, 100), true)
    eq(U.isExpired({ expiresAt = nil }, 1e12), false, 'permanent bans never expire')
end)

test('findBan matches identifiers and hardware tokens', function()
    local now = 1000
    local bans = {
        [1] = { id = 1, active = true, identifiers = { 'license:a' }, tokens = {}, expiresAt = now + 100 },
        [2] = { id = 2, active = true, identifiers = { 'discord:9' }, tokens = {}, expiresAt = nil },
        [3] = { id = 3, active = true, identifiers = { 'steam:x' }, tokens = {}, expiresAt = now - 1 },
        [4] = { id = 4, active = false, identifiers = { 'license:z' }, tokens = {} },
        [5] = { id = 5, active = true, identifiers = {}, tokens = { '3:abc' }, expiresAt = now + 50 },
    }
    eq(U.findBan(bans, { 'license:a' }, {}, now).id, 1)
    eq(U.findBan(bans, { 'license:a', 'discord:9' }, {}, now).id, 2, 'the permanent ban wins')
    eq(U.findBan(bans, { 'steam:x' }, {}, now), nil, 'expired')
    eq(U.findBan(bans, { 'license:z' }, {}, now), nil, 'unbanned')
    eq(U.findBan(bans, { 'license:new' }, { '3:abc' }, now).id, 5, 'new license, same PC')
    eq(U.findBan(bans, { 'license:nobody' }, { '3:other' }, now), nil)
end)

test('findBan prefers the ban that lasts longest', function()
    local now = 1000
    local bans = {
        { id = 1, active = true, identifiers = { 'license:a' }, expiresAt = now + 100 },
        { id = 2, active = true, identifiers = { 'license:a' }, expiresAt = now + 500 },
    }
    eq(U.findBan(bans, { 'license:a' }, {}, now).id, 2)
end)

test('findBan only matches IP bans when IP banning is on', function()
    local bans = { { id = 1, active = true, identifiers = { 'ip:1.1.1.1' } } }
    eq(U.findBan(bans, { 'ip:1.1.1.1' }, {}, 0, false), nil)
    eq(U.findBan(bans, { 'ip:1.1.1.1' }, {}, 0, true).id, 1)
end)

test('rate limiter', function()
    local allow, forget = U.newRateLimiter(2, 10)
    eq(allow('a', 0), true)
    eq(allow('a', 1), true)
    eq(allow('a', 2), false, 'third call inside the window')
    eq(allow('b', 2), true, 'other players are separate')
    eq(allow('a', 10.5), true, 'first call has left the window')
    forget('a')
    eq(allow('a', 10.6), true)
    eq(allow('a', 10.7), true)
end)

test('ring keeps the newest items, newest first', function()
    local ring = U.newRing(3)
    for i = 1, 5 do ring.push(i) end
    local items = ring.list()
    eq(#items, 3)
    eq(items[1], 5)
    eq(items[3], 3)
end)

test('validCoords', function()
    eq(U.validCoords(0, 0, 0), true)
    eq(U.validCoords(-1000.5, 2000.25, 30), true)
    eq(U.validCoords(9000, 0, 0), false)
    eq(U.validCoords('1', 0, 0), false)
    eq(U.validCoords(0, 0, 3000), false)
    eq(U.validCoords(nil, 0, 0), false)
end)

test('validModelName', function()
    eq(U.validModelName('adder'), true)
    eq(U.validModelName('police3'), true)
    eq(U.validModelName('a'), false)
    eq(U.validModelName('bad name'), false)
    eq(U.validModelName('x;drop'), false)
    eq(U.validModelName(('a'):rep(33)), false)
    eq(U.validModelName(nil), false)
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d test(s) failed'):format(failed)) end
