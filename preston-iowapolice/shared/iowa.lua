-- The rules for Iowa police vehicles, shared by the server, every player's game and the tests. No
-- FiveM natives here, so it runs in plain Lua:  lua tests/iowa_spec.lua

IowaPolice = {}
local I = IowaPolice

I.VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true }

-- A unit number typed by a player (1 to 9999), or nil.
function I.parseUnit(text)
    local n = tonumber(text)
    if not n or n ~= math.floor(n) or n < 1 or n > 9999 then return nil end
    return math.floor(n)
end

-- Plate text the game accepts: up to 8 capital letters, numbers and spaces.
function I.formatPlate(text)
    if type(text) ~= 'string' then return '' end
    local plate = text:upper():gsub('[^A-Z0-9 ]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return plate:sub(1, 8)
end

-- "ISP" and 7 -> "ISP 007"; numbers keep at least 3 digits, like real unit numbers.
function I.plateFor(prefix, unit)
    return I.formatPlate(('%s %03d'):format(prefix or '', unit))
end

function I.cooldownLeft(lastAt, now, seconds)
    if not lastAt then return 0 end
    local left = lastAt + seconds - now
    return left > 0 and math.ceil(left) or 0
end

-- The department a player typed (by key or command, any capitals), or nil.
function I.findDepartment(config, name)
    if type(name) ~= 'string' then return nil end
    name = name:lower()
    for key, department in pairs(config.Departments) do
        if key == name or department.command == name then return key, department end
    end
    return nil
end

-- Problems in a config, as readable lines (empty when it's fine). Printed when the server starts.
function I.checkConfig(config)
    local problems = {}
    local function add(...) problems[#problems + 1] = string.format(...) end
    local commands = {}
    for key, d in pairs(config.Departments or {}) do
        local where = 'Config.Departments.' .. key
        if type(d.model) ~= 'string' or not d.model:match('^[%w_]+$') then add('%s: model must be a spawn name', where) end
        if not I.VEHICLE_TYPES[d.vehicleType or 'automobile'] then add('%s: unknown vehicleType', where) end
        if type(d.command) ~= 'string' or not d.command:match('^[%w_]+$') then add('%s: command must be one word', where) end
        if commands[d.command] then add('%s: command /%s is used twice', where, tostring(d.command)) end
        commands[d.command or ''] = true
        -- 3 letters + a space + up to 4 digits is the 8 characters a plate holds.
        if I.formatPlate(d.plate) == '' or #I.formatPlate(d.plate) > 3 then add('%s: plate prefix must be 1 to 3 letters', where) end
        if d.colors ~= nil and (type(d.colors) ~= 'table' or #d.colors ~= 2) then add('%s: colors must be { primary, secondary }', where) end
        if d.plateStyle ~= nil and (type(d.plateStyle) ~= 'number' or d.plateStyle < 0 or d.plateStyle > 5) then add('%s: plateStyle must be 0 to 5', where) end
        if d.extras ~= 'all' and d.extras ~= nil and type(d.extras) ~= 'table' then add("%s: extras must be 'all' or a list", where) end
    end
    if config.DefaultDepartment and not (config.Departments or {})[config.DefaultDepartment] then
        add('Config.DefaultDepartment: "%s" is not a department', tostring(config.DefaultDepartment))
    end
    return problems
end

return I
