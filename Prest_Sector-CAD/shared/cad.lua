-- The rules for Prest_Sector CAD, shared by the server, every player's game and the tests. No FiveM
-- natives here, so it runs in plain Lua:  lua tests/cad_spec.lua

CAD = {}
local C = CAD

-- Every network event is named 'Prest_Sector-CAD:<name>'.
C.EVENT = 'Prest_Sector-CAD:'

-- A player's server ID from a net event or an export: a whole number from 1 up, or nil.
function C.toId(value)
    local n = math.tointeger(tonumber(value))
    if n and n >= 1 and n <= 65535 then return n end
    return nil
end

-- A whole number between min and max, or nil.
function C.toInt(value, min, max)
    local n = math.tointeger(tonumber(value))
    if not n or (min and n < min) or (max and n > max) then return nil end
    return n
end

-- Cuts a UTF-8 string to at most maxLen bytes without splitting a character in half.
local function cut(s, maxLen)
    if #s <= maxLen then return s end
    local stop = maxLen
    -- Step back over continuation bytes (10xxxxxx) so the last character stays whole.
    while stop > 0 do
        local b = s:byte(stop + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        stop = stop - 1
    end
    return s:sub(1, stop)
end

-- Text a player typed: anything that isn't a string becomes '', control characters go (line breaks
-- stay in long text), spaces are trimmed and it's cut to maxLen.
function C.text(value, maxLen)
    if type(value) ~= 'string' then return '' end
    local keepLines = maxLen > 200
    local s = value:gsub('\r\n?', '\n')
    if keepLines then
        s = s:gsub('%c', function(c) return c == '\n' and c or '' end)
        s = s:gsub('\n\n\n+', '\n\n')
    else
        s = s:gsub('%c', ' ')
    end
    s = s:match('^%s*(.-)%s*$')
    return cut(s, maxLen)
end

-- A plate as the CAD files it: letters and digits only, upper case, 1 to 8 of them. ' ab-12 cd ' is 'AB12CD'.
function C.plateKey(plate)
    if type(plate) ~= 'string' then return nil end
    local key = plate:upper():gsub('[^A-Z0-9]', '')
    if #key < 1 or #key > 8 then return nil end
    return key
end

-- The item in a list whose [field] (default 'key') equals key.
function C.byKey(list, key, field)
    field = field or 'key'
    for _, item in ipairs(list or {}) do
        if item[field] == key then return item end
    end
    return nil
end

function C.distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ------------------------------------------------------------------ who can do what

-- Each ability and the roles that have it. supervisor and admin are added to everything below except
-- where noted, so a supervisor can always do what police and dispatch can.
local ABILITIES = {
    ['unit.signon'] = { 'police', 'fire', 'dispatch' },
    ['dispatch.view'] = { 'police', 'fire', 'dispatch' },
    ['dispatch.manage'] = { 'dispatch' },
    ['calls.create'] = { 'police', 'fire', 'dispatch' },
    ['people.view'] = { 'police', 'dispatch', 'judge' },
    ['records.view'] = { 'police', 'dispatch', 'judge' },
    ['records.edit'] = { 'police', 'dispatch' },
    ['records.delete'] = {},
    ['reports.write'] = { 'police', 'fire', 'dispatch' },
    ['reports.approve'] = {},
    ['warrants.request'] = { 'police' },
    ['warrants.approve'] = { 'judge' },
    ['bolos.edit'] = { 'police', 'dispatch' },
}
C.ABILITY_NAMES = {}
for name in pairs(ABILITIES) do C.ABILITY_NAMES[#C.ABILITY_NAMES + 1] = name end
table.sort(C.ABILITY_NAMES)

C.ROLE_NAMES = { 'police', 'fire', 'dispatch', 'supervisor', 'judge', 'admin' }

-- What a player with these roles ({ police = true, ... }) can do: { ['people.view'] = true, ... }.
function C.abilities(config, roles)
    roles = roles or {}
    local out = {}
    local boss = roles.supervisor or roles.admin
    for name, list in pairs(ABILITIES) do
        local yes = boss
        for _, role in ipairs(list) do
            if roles[role] then yes = true end
        end
        out[name] = yes or nil
    end
    if config.UnitsCanManageCalls and (roles.police or roles.fire) then out['dispatch.manage'] = true end
    if config.FireCanSearchPeople and roles.fire then out['people.view'] = true end
    return out
end

-- The report types these roles can write.
function C.reportTypesFor(config, roles)
    roles = roles or {}
    local out = {}
    for _, t in ipairs(config.ReportTypes or {}) do
        local yes = roles.supervisor or roles.admin
        for _, role in ipairs(t.roles or {}) do
            if roles[role] then yes = true end
        end
        if yes then out[#out + 1] = t.key end
    end
    return out
end

-- The departments these roles can sign on with. (A department's own ace is checked by the server.)
function C.departmentsFor(config, roles)
    roles = roles or {}
    local out = {}
    for _, d in ipairs(config.Departments or {}) do
        if roles.supervisor or roles.admin or roles[d.role] then out[#out + 1] = d.key end
    end
    return out
end

-- ------------------------------------------------------------------ the penal code

function C.findCharge(config, code)
    if type(code) ~= 'string' then return nil end
    for _, title in ipairs(config.PenalCode or {}) do
        for _, charge in ipairs(title.charges or {}) do
            if charge.code == code then return charge end
        end
    end
    return nil
end

-- Adds up a list of charges ({ { code = '1-01', count = 2 }, ... }): the fine, the months in jail and
-- each charge's line. Returns nil and a reason when the list isn't right.
function C.chargeTotals(config, charges)
    if type(charges) ~= 'table' then return nil, 'Pick the charges.' end
    if #charges > 30 then return nil, 'That is too many charges (30 at most).' end
    local counts, order = {}, {}
    for _, entry in ipairs(charges) do
        if type(entry) ~= 'table' then return nil, 'Pick the charges.' end
        local charge = C.findCharge(config, entry.code)
        if not charge then return nil, ('There is no charge %s in the penal code.'):format(tostring(entry.code)) end
        local count = C.toInt(entry.count == nil and 1 or entry.count, 1, 20)
        if not count then return nil, 'Each charge can be counted 1 to 20 times.' end
        if not counts[charge.code] then order[#order + 1] = charge end
        counts[charge.code] = math.min(20, (counts[charge.code] or 0) + count)
    end
    local totals = { fine = 0, jail = 0, items = {} }
    for _, charge in ipairs(order) do
        local count = counts[charge.code]
        local line = {
            code = charge.code, name = charge.name, class = charge.class, count = count,
            fine = (charge.fine or 0) * count, jail = (charge.jail or 0) * count,
        }
        totals.fine = totals.fine + line.fine
        totals.jail = totals.jail + line.jail
        totals.items[#totals.items + 1] = line
    end
    return totals
end

-- ------------------------------------------------------------------ the config, for the tablet

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

-- What the tablet needs from config.lua (lists only; nothing about storage or permissions).
function C.publicConfig(config)
    return {
        departments = copy(config.Departments), statuses = copy(config.Statuses), priorities = copy(config.Priorities),
        services = copy(config.Services), callCodes = copy(config.CallCodes), dispositions = copy(config.Dispositions),
        genders = copy(config.Genders), licenses = copy(config.Licenses), licenseStates = copy(config.LicenseStates),
        personFlags = copy(config.PersonFlags), registrationStates = copy(config.RegistrationStates),
        insuranceStates = copy(config.InsuranceStates), vehicleFlags = copy(config.VehicleFlags),
        weaponStates = copy(config.WeaponStates), reportTypes = copy(config.ReportTypes), penal = copy(config.PenalCode),
        civilian = copy(config.Civilian), warrantsNeedApproval = config.WarrantsNeedApproval == true,
        unitsCanManageCalls = config.UnitsCanManageCalls == true,
    }
end

-- Mistakes in config.lua, as sentences for the server console. An empty list means it's fine.
function C.checkConfig(config)
    local problems = {}
    local function problem(text, ...) problems[#problems + 1] = text:format(...) end
    local function uniqueKeys(listName, field)
        local list = config[listName]
        if type(list) ~= 'table' or #list == 0 then return problem('Config.%s is empty.', listName) end
        local seen = {}
        for i, item in ipairs(list) do
            local key = type(item) == 'table' and item[field or 'key'] or nil
            if type(key) ~= 'string' and type(key) ~= 'number' then problem('Config.%s[%d] has no %s.', listName, i, field or 'key')
            elseif seen[key] then problem('Config.%s has %s twice.', listName, tostring(key))
            else seen[key] = true end
        end
    end
    if config.Storage ~= 'kvp' and config.Storage ~= 'oxmysql' then problem("Config.Storage must be 'kvp' or 'oxmysql'.") end
    uniqueKeys('Departments')
    uniqueKeys('Statuses')
    uniqueKeys('Services')
    uniqueKeys('CallCodes', 'code')
    uniqueKeys('Licenses')
    uniqueKeys('LicenseStates')
    uniqueKeys('PersonFlags')
    uniqueKeys('RegistrationStates')
    uniqueKeys('InsuranceStates')
    uniqueKeys('VehicleFlags')
    uniqueKeys('WeaponStates')
    uniqueKeys('ReportTypes')
    for _, d in ipairs(config.Departments or {}) do
        if d.role ~= 'police' and d.role ~= 'fire' and d.role ~= 'dispatch' then
            problem("Department %s needs role 'police', 'fire' or 'dispatch'.", tostring(d.key))
        end
    end
    local levels = {}
    for _, p in ipairs(config.Priorities or {}) do levels[p.level] = true end
    for level = 1, 3 do
        if not levels[level] then problem('Config.Priorities needs priority %d.', level) end
    end
    for _, code in ipairs(config.CallCodes or {}) do
        if not levels[code.priority] then problem('Call code %s has priority %s, which is not 1, 2 or 3.', tostring(code.code), tostring(code.priority)) end
        if not C.byKey(config.Services, code.service) then problem('Call code %s has an unknown service %s.', tostring(code.code), tostring(code.service)) end
    end
    if not C.byKey(config.CallCodes, '911', 'code') then problem("Config.CallCodes needs a '911' code for 911 calls.") end
    for _, t in ipairs(config.ReportTypes or {}) do
        if type(t.roles) ~= 'table' or #t.roles == 0 then problem('Report type %s has no roles that can write it.', tostring(t.key)) end
    end
    if type(config.Dispositions) ~= 'table' or #config.Dispositions == 0 then problem('Config.Dispositions is empty.') end
    if not C.byKey(config.LicenseStates, 'valid') or not C.byKey(config.LicenseStates, 'none') then
        problem("Config.LicenseStates needs 'valid' and 'none'.")
    end
    local codes = {}
    for _, title in ipairs(config.PenalCode or {}) do
        for _, charge in ipairs(title.charges or {}) do
            if codes[charge.code] then problem('Penal code %s is listed twice.', tostring(charge.code)) end
            codes[charge.code] = true
            if charge.class ~= 'infraction' and charge.class ~= 'misdemeanor' and charge.class ~= 'felony' then
                problem("Penal code %s needs class 'infraction', 'misdemeanor' or 'felony'.", tostring(charge.code))
            end
        end
    end
    return problems
end
