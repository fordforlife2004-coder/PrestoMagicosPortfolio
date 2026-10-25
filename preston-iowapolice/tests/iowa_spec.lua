-- Tests for shared/iowa.lua and config.lua. Run from the resource folder with any Lua 5.3+:  lua tests/iowa_spec.lua

dofile('config.lua')
local I = dofile('shared/iowa.lua')
local t = dofile('tests/fake_server.lua').runner()

t.test('the shipped config has no problems', function()
    local problems = I.checkConfig(Config)
    t.eq(#problems, 0, table.concat(problems, '; '))
end)

t.test('checkConfig explains mistakes', function()
    local text = table.concat(I.checkConfig({
        Departments = {
            a = { command = 'isp', model = 'police 3', plate = 'TOOLONG', colors = { 1 }, plateStyle = 9, extras = 'some' },
            b = { command = 'isp', model = 'police', plate = 'X', vehicleType = 'rocket' },
        },
        DefaultDepartment = 'nope',
    }), '\n')
    for _, expected in ipairs({ 'model must be a spawn name', 'used twice', '1 to 3 letters', 'colors must be', 'plateStyle must be', "'all' or a list", 'unknown vehicleType', '"nope" is not a department' }) do
        if not text:find(expected, 1, true) then error('missing problem: ' .. expected .. '\n' .. text) end
    end
end)

t.test('unit numbers', function()
    t.eq(I.parseUnit('101'), 101)
    t.eq(I.parseUnit(7), 7)
    t.eq(I.parseUnit('0'), nil)
    t.eq(I.parseUnit('10000'), nil)
    t.eq(I.parseUnit('1.5'), nil)
    t.eq(I.parseUnit('abc'), nil)
end)

t.test('plates fit in 8 characters', function()
    t.eq(I.plateFor('ISP', 101), 'ISP 101')
    t.eq(I.plateFor('ISP', 7), 'ISP 007')
    t.eq(I.plateFor('SO', 9999), 'SO 9999')
    t.eq(#I.plateFor('ISP', 9999), 8)
end)

t.test('departments are found by key or command, any capitals', function()
    t.eq(I.findDepartment(Config, 'ISP'), 'isp')
    t.eq(I.findDepartment(Config, 'sheriff'), 'sheriff')
    t.eq(I.findDepartment(Config, 'fbi'), nil)
    t.eq(I.findDepartment(Config, nil), nil)
end)

t.finish()
