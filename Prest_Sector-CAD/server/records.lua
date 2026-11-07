-- Records: people, vehicles, weapons, reports, warrants and BOLOs, and civilians' own characters.
-- Every request handler gets ctx (who is asking: src, name, roles, abilities, license, unit) and the
-- payload the tablet sent, which is never trusted: each field is checked here before it's saved.
-- A handler returns its result, or calls fail('...') with a sentence the player sees.

Records = { handlers = {} }
local R = Records
local C = CAD
local H = R.handlers

local function fail(message) error({ userError = message }, 0) end
R.fail = fail

local function need(ctx, ability)
    if not ctx.abilities[ability] then fail("You aren't allowed to do that.") end
end
R.need = need

local function now() return os.time() end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end
R.copy = copy

local function payloadOf(p, field)
    local value = type(p) == 'table' and p[field] or nil
    if type(value) ~= 'table' then fail('Something was missing from that request.') end
    return value
end

-- A record's number from the tablet ('12' or 12), or a failure.
local function idOf(value, what)
    local id = C.toInt(value, 1, 2147483647)
    if not id then fail(('That %s could not be found.'):format(what)) end
    return id
end

local function getOr(kind, id, what)
    local record = Store.get(kind, idOf(id, what))
    if not record then fail(('That %s could not be found.'):format(what)) end
    return record
end

-- A key from one of config.lua's lists, or a failure.
local function oneOf(list, value, what)
    if type(value) ~= 'string' or not C.byKey(list, value) then fail(('Pick a valid %s.'):format(what)) end
    return value
end

-- A list of keys from one of config.lua's lists, each once.
local function someOf(list, values, what)
    if values == nil then return {} end
    if type(values) ~= 'table' then fail(('Pick valid %s.'):format(what)) end
    local out, seen = {}, {}
    for _, value in ipairs(values) do
        if type(value) ~= 'string' or not C.byKey(list, value) then fail(('Pick valid %s.'):format(what)) end
        if not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    return out
end

local function required(value, maxLen, what)
    local text = C.text(value, maxLen)
    if text == '' then fail(('Enter %s.'):format(what)) end
    return text
end

-- ------------------------------------------------------------------ what the tablet is sent

-- Players never see who (by license) made a record or wrote a report.
local function public(record)
    if not record then return nil end
    local out = copy(record)
    out.owner = nil
    out.authorLicense = nil
    return out
end
R.public = public

local function personName(id)
    local p = id and Store.get('person', id)
    return p and ('%s %s'):format(p.first, p.last) or nil
end
R.personName = personName

function R.activeWarrants(personId)
    local n = 0
    for _, w in ipairs(Store.list('warrant')) do
        if w.personId == personId and w.status == 'active' then n = n + 1 end
    end
    return n
end

local function activeBolos(test)
    local out = {}
    for _, b in ipairs(Store.list('bolo')) do
        if b.active and test(b) then out[#out + 1] = public(b) end
    end
    return out
end

-- The short form of a person used in search results and links.
function R.summary(p)
    if not p then return nil end
    return {
        id = p.id, first = p.first, last = p.last, dob = p.dob, gender = p.gender, mugshot = p.mugshot,
        flags = copy(p.flags or {}), licenses = copy(p.licenses or {}), warrants = R.activeWarrants(p.id),
        bolo = #activeBolos(function(b) return b.personId == p.id end) > 0,
    }
end

-- A vehicle or weapon with its owner's name filled in.
local function withOwner(record)
    local out = public(record)
    out.ownerName = personName(record.ownerId)
    return out
end
R.withOwner = withOwner

-- ------------------------------------------------------------------ checking fields

-- Letters (any language), spaces, apostrophes, dashes and dots.
local NAME = "^[%a\128-\255][%a\128-\255 '%-%.]*$"

local function nameField(value, what)
    local text = required(value, 30, what)
    if not text:match(NAME) then fail(('%s can only have letters, spaces, apostrophes and dashes.'):format(what:gsub('^%l', string.upper))) end
    return text
end

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- A date of birth as 'YYYY-MM-DD', from 1900 to today.
function R.dob(value)
    if type(value) ~= 'string' then fail('Enter a date of birth.') end
    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 then fail('Enter the date of birth as YYYY-MM-DD.') end
    local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
    local most = (m == 2 and leap) and 29 or DAYS[m]
    if d > most then fail("That date of birth doesn't exist.") end
    local today = os.date('*t', now())
    if y < 1900 or y > today.year or (y == today.year and (m > today.month or (m == today.month and d > today.day))) then
        fail('Enter a date of birth between 1900 and today.')
    end
    return ('%04d-%02d-%02d'):format(y, m, d)
end

-- '' or an http(s) address with no spaces or quotes (it's only ever shown as an image).
local function urlField(value)
    local text = C.text(value, 300)
    if text == '' then return '' end
    if not text:match('^https?://[^%s"\'<>]+$') then fail('The photo must be a web address starting with http:// or https://.') end
    return text
end

local function phoneField(value)
    local text = C.text(value, 20)
    if text ~= '' and not text:match('^[%d%s%+%-%(%)%.]+$') then fail('The phone number can only have digits, spaces and + - ( ).') end
    return text
end

-- The identity part of a person: what a civilian may fill in for their own character.
local function identity(input, into)
    into.first = nameField(input.first, 'a first name')
    into.last = nameField(input.last, 'a last name')
    into.dob = R.dob(input.dob)
    local gender = input.gender
    local okGender = false
    for _, g in ipairs(Config.Genders) do
        if g == gender then okGender = true end
    end
    if not okGender then fail('Pick a gender.') end
    into.gender = gender
    into.address = C.text(input.address, 80)
    into.phone = phoneField(input.phone)
    into.height = C.text(input.height, 10)
    into.description = C.text(input.description, 300)
    into.mugshot = urlField(input.mugshot)
    return into
end

-- Licenses as { driver = 'valid', ... } with every license in config.lua. allowed (optional) limits
-- the states, e.g. a civilian making a character can only pick valid or none.
local function licensesField(input, old, allowed)
    local out = {}
    for _, license in ipairs(Config.Licenses) do
        local state = type(input) == 'table' and input[license.key] or nil
        if state == nil then state = old and old[license.key] or 'none' end
        oneOf(Config.LicenseStates, state, ('state for %s'):format(license.label))
        if allowed and not allowed[state] then fail(('%s can only be valid or none.'):format(license.label)) end
        out[license.key] = state
    end
    return out
end

-- ------------------------------------------------------------------ people

local function matchesPerson(p, q)
    local full = ('%s %s'):format(p.first, p.last):lower()
    local reverse = ('%s, %s'):format(p.last, p.first):lower()
    if full:find(q, 1, true) or reverse:find(q, 1, true) or (p.dob or ''):find(q, 1, true) then return true end
    local digits = (q:gsub('[^%d]', ''))
    if #digits >= 3 and not q:match('%a') then
        local phone = ((p.phone or ''):gsub('[^%d]', ''))
        return phone:find(digits, 1, true) ~= nil
    end
    return false
end

local function byName(a, b)
    if a.last:lower() ~= b.last:lower() then return a.last:lower() < b.last:lower() end
    return a.first:lower() < b.first:lower()
end

H['person.search'] = function(ctx, p)
    need(ctx, 'people.view')
    local q = C.text(type(p) == 'table' and p.query, 60):lower()
    if q == '' then return {} end
    local id = q:match('^p%-?(%d+)$')
    if id then
        local person = Store.get('person', tonumber(id))
        return person and { R.summary(person) } or {}
    end
    local found = {}
    for _, person in ipairs(Store.list('person')) do
        if matchesPerson(person, q) then found[#found + 1] = person end
    end
    table.sort(found, byName)
    local out = {}
    for i = 1, math.min(#found, 25) do out[i] = R.summary(found[i]) end
    return out
end

local function reportEntry(r)
    local names = {}
    for _, id in ipairs(r.persons or {}) do names[#names + 1] = personName(id) or 'Deleted person' end
    return {
        id = r.id, type = r.type, title = r.title, status = r.status, author = copy(r.author), persons = copy(r.persons or {}),
        personNames = names, vehicles = copy(r.vehicles or {}), callId = r.callId, totals = copy(r.totals),
        createdAt = r.createdAt, updatedAt = r.updatedAt, approvedBy = r.approvedBy,
    }
end
R.reportEntry = reportEntry

local function warrantOut(w)
    local out = public(w)
    out.requesterLicense = nil
    out.personName = personName(w.personId) or 'Deleted person'
    return out
end

local function newestFirst(a, b)
    if (a.updatedAt or 0) ~= (b.updatedAt or 0) then return (a.updatedAt or 0) > (b.updatedAt or 0) end
    return a.id > b.id
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

H['person.get'] = function(ctx, p)
    need(ctx, 'people.view')
    local person = getOr('person', type(p) == 'table' and p.id, 'person')
    local out = { person = public(person), summary = R.summary(person), vehicles = {}, weapons = {} }
    for _, v in ipairs(Store.list('vehicle')) do
        if v.ownerId == person.id then out.vehicles[#out.vehicles + 1] = withOwner(v) end
    end
    for _, w in ipairs(Store.list('weapon')) do
        if w.ownerId == person.id then out.weapons[#out.weapons + 1] = withOwner(w) end
    end
    out.bolos = activeBolos(function(b) return b.personId == person.id end)
    -- Reports and warrants are for police, dispatch and judges; Fire/EMS only see the person.
    if ctx.abilities['records.view'] then
        local reports, warrants = {}, {}
        for _, r in ipairs(Store.list('report')) do
            if contains(r.persons, person.id) then reports[#reports + 1] = r end
        end
        table.sort(reports, newestFirst)
        out.reports = {}
        for i, r in ipairs(reports) do out.reports[i] = reportEntry(r) end
        for _, w in ipairs(Store.list('warrant')) do
            if w.personId == person.id then warrants[#warrants + 1] = w end
        end
        table.sort(warrants, newestFirst)
        out.warrants = {}
        for i, w in ipairs(warrants) do out.warrants[i] = warrantOut(w) end
    end
    return out
end

H['person.save'] = function(ctx, p)
    need(ctx, 'records.edit')
    local input = payloadOf(p, 'person')
    local old = input.id ~= nil and getOr('person', input.id, 'person') or nil
    local person = old and copy(old) or {}
    identity(input, person)
    person.licenses = licensesField(input.licenses, old and old.licenses)
    person.flags = someOf(Config.PersonFlags, input.flags, 'flags')
    person.notes = C.text(input.notes, 2000)
    person.updatedAt = now()
    if not old then
        person.id = Store.nextId('person')
        person.createdAt = person.updatedAt
    end
    Store.save('person', person)
    return public(person)
end

-- Vehicles and weapons a deleted person owned are kept, with no owner.
local function unlinkOwner(personId)
    for _, kind in ipairs({ 'vehicle', 'weapon' }) do
        for _, record in ipairs(Store.list(kind)) do
            if record.ownerId == personId then
                record.ownerId = nil
                record.updatedAt = now()
                Store.save(kind, record)
            end
        end
    end
end

H['person.delete'] = function(ctx, p)
    need(ctx, 'records.delete')
    local person = getOr('person', type(p) == 'table' and p.id, 'person')
    unlinkOwner(person.id)
    Store.delete('person', person.id)
    return true
end

-- ------------------------------------------------------------------ vehicles and weapons

local function vehicleByPlate(key)
    for _, v in ipairs(Store.list('vehicle')) do
        if v.plateKey == key then return v end
    end
    return nil
end
R.vehicleByPlate = vehicleByPlate

local function ownerField(value)
    if value == nil or value == '' or value == false then return nil end
    return getOr('person', value, 'owner').id
end

local function plateField(value, selfId)
    local key = C.plateKey(value)
    if not key then fail('Enter a plate of 1 to 8 letters and numbers.') end
    local other = vehicleByPlate(key)
    if other and other.id ~= selfId then fail(('Plate %s is already registered to another vehicle.'):format(key)) end
    return key
end

local function serialField(value, selfId)
    local serial = type(value) == 'string' and value:upper():gsub('%s', '') or ''
    if not serial:match('^[A-Z0-9%-]+$') or #serial > 20 then fail('Enter a serial number of up to 20 letters, numbers and dashes.') end
    for _, w in ipairs(Store.list('weapon')) do
        if w.serial == serial and w.id ~= selfId then fail(('Serial %s is already registered.'):format(serial)) end
    end
    return serial
end

local function matchesText(value, q)
    return type(value) == 'string' and value:lower():find(q, 1, true)
end

H['vehicle.search'] = function(ctx, p)
    need(ctx, 'people.view')
    local q = C.text(type(p) == 'table' and p.query, 40):lower()
    if q == '' then return {} end
    local id = q:match('^v%-(%d+)$')
    local key = C.plateKey(q)
    local out = {}
    for _, v in ipairs(Store.list('vehicle')) do
        local hit
        if id then hit = v.id == tonumber(id)
        else
            hit = (key and v.plateKey:find(key, 1, true)) or matchesText(v.model, q) or matchesText(personName(v.ownerId), q)
        end
        if hit then out[#out + 1] = withOwner(v) end
        if #out >= 25 then break end
    end
    return out
end

H['vehicle.get'] = function(ctx, p)
    need(ctx, 'people.view')
    local v = getOr('vehicle', type(p) == 'table' and p.id, 'vehicle')
    return {
        vehicle = withOwner(v), owner = R.summary(v.ownerId and Store.get('person', v.ownerId)),
        bolos = activeBolos(function(b) return b.plate == v.plateKey end),
    }
end

H['vehicle.save'] = function(ctx, p)
    need(ctx, 'records.edit')
    local input = payloadOf(p, 'vehicle')
    local old = input.id ~= nil and getOr('vehicle', input.id, 'vehicle') or nil
    local v = old and copy(old) or {}
    v.plateKey = plateField(input.plate, old and old.id)
    v.plate = v.plateKey
    v.model = C.text(input.model, 30)
    v.color = C.text(input.color, 20)
    v.ownerId = ownerField(input.ownerId)
    v.registration = oneOf(Config.RegistrationStates, input.registration or 'valid', 'registration')
    v.insurance = oneOf(Config.InsuranceStates, input.insurance or 'valid', 'insurance')
    v.flags = someOf(Config.VehicleFlags, input.flags, 'vehicle flags')
    v.notes = C.text(input.notes, 1000)
    v.updatedAt = now()
    if not old then
        v.id = Store.nextId('vehicle')
        v.createdAt = v.updatedAt
    end
    Store.save('vehicle', v)
    return withOwner(v)
end

H['vehicle.delete'] = function(ctx, p)
    need(ctx, 'records.delete')
    local v = getOr('vehicle', type(p) == 'table' and p.id, 'vehicle')
    Store.delete('vehicle', v.id)
    return true
end

H['weapon.search'] = function(ctx, p)
    need(ctx, 'people.view')
    local q = C.text(type(p) == 'table' and p.query, 40):lower()
    if q == '' then return {} end
    local id = q:match('^w%-(%d+)$')
    local out = {}
    for _, w in ipairs(Store.list('weapon')) do
        local hit
        if id then hit = w.id == tonumber(id)
        else hit = matchesText(w.serial, q) or matchesText(w.kind, q) or matchesText(personName(w.ownerId), q) end
        if hit then out[#out + 1] = withOwner(w) end
        if #out >= 25 then break end
    end
    return out
end

H['weapon.get'] = function(ctx, p)
    need(ctx, 'people.view')
    local w = getOr('weapon', type(p) == 'table' and p.id, 'weapon')
    return { weapon = withOwner(w), owner = R.summary(w.ownerId and Store.get('person', w.ownerId)) }
end

H['weapon.save'] = function(ctx, p)
    need(ctx, 'records.edit')
    local input = payloadOf(p, 'weapon')
    local old = input.id ~= nil and getOr('weapon', input.id, 'weapon') or nil
    local w = old and copy(old) or {}
    w.serial = serialField(input.serial, old and old.id)
    w.kind = required(input.kind, 30, 'the kind of weapon')
    w.ownerId = ownerField(input.ownerId)
    w.status = oneOf(Config.WeaponStates, input.status or 'registered', 'weapon status')
    w.notes = C.text(input.notes, 1000)
    w.updatedAt = now()
    if not old then
        w.id = Store.nextId('weapon')
        w.createdAt = w.updatedAt
    end
    Store.save('weapon', w)
    return withOwner(w)
end

H['weapon.delete'] = function(ctx, p)
    need(ctx, 'records.delete')
    local w = getOr('weapon', type(p) == 'table' and p.id, 'weapon')
    Store.delete('weapon', w.id)
    return true
end

-- ------------------------------------------------------------------ running a plate

local function label(list, key)
    local item = C.byKey(list, key)
    return item and item.label or tostring(key)
end

-- Everything an officer should know about a plate, as a list of alerts.
function R.plateCheck(plate)
    local key = C.plateKey(plate)
    if not key then fail('That is not a plate.') end
    local v = vehicleByPlate(key)
    local result = { plate = key, found = v ~= nil, alerts = {} }
    local function alert(text, tone) result.alerts[#result.alerts + 1] = { text = text, tone = tone or 'warning' } end
    for _, b in ipairs(activeBolos(function(b) return b.plate == key end)) do alert('BOLO: ' .. b.title, 'error') end
    if not v then
        alert('No record of this plate.', 'warning')
        return result
    end
    result.vehicle = withOwner(v)
    if contains(v.flags, 'stolen') then alert('Reported STOLEN.', 'error') end
    if contains(v.flags, 'flagged') then alert(label(Config.VehicleFlags, 'flagged') .. '.', 'error') end
    if contains(v.flags, 'impounded') then alert('Marked as impounded.', 'warning') end
    if v.registration ~= 'valid' then alert('Registration: ' .. label(Config.RegistrationStates, v.registration) .. '.') end
    if v.insurance ~= 'valid' then alert('Insurance: ' .. label(Config.InsuranceStates, v.insurance) .. '.') end
    local owner = v.ownerId and Store.get('person', v.ownerId)
    if owner then
        result.owner = R.summary(owner)
        local warrants = R.activeWarrants(owner.id)
        if warrants > 0 then alert(('Owner has %d active warrant%s.'):format(warrants, warrants == 1 and '' or 's'), 'error') end
        local driver = owner.licenses and owner.licenses.driver or 'none'
        if driver ~= 'valid' then alert("Owner's driver's license: " .. label(Config.LicenseStates, driver) .. '.') end
        for _, flag in ipairs(owner.flags or {}) do
            if flag == 'armed' or flag == 'officer_safety' then alert('Owner: ' .. label(Config.PersonFlags, flag) .. '.', 'error') end
        end
    else
        alert('No registered owner.')
    end
    return result
end

H['plate.check'] = function(ctx, p)
    need(ctx, 'people.view')
    return R.plateCheck(type(p) == 'table' and p.plate)
end

-- ------------------------------------------------------------------ reports

local function canReadReport(ctx, r)
    return ctx.abilities['records.view'] or (ctx.license ~= nil and r.authorLicense == ctx.license)
end

H['report.list'] = function(ctx, p)
    if not ctx.abilities['records.view'] and not ctx.abilities['reports.write'] then fail("You aren't allowed to do that.") end
    p = type(p) == 'table' and p or {}
    local q = C.text(p.query, 60):lower()
    local id = q:match('^r%-?(%d+)$')
    local out = {}
    local list = Store.list('report')
    table.sort(list, newestFirst)
    for _, r in ipairs(list) do
        local entry = canReadReport(ctx, r) and reportEntry(r)
        local ok = entry ~= false and entry ~= nil
        if ok and type(p.type) == 'string' and p.type ~= '' and r.type ~= p.type then ok = false end
        if ok and type(p.status) == 'string' and p.status ~= '' and r.status ~= p.status then ok = false end
        if ok and p.mine and r.authorLicense ~= ctx.license then ok = false end
        if ok and q ~= '' then
            if id then ok = r.id == tonumber(id)
            else
                ok = matchesText(r.title, q) or matchesText(r.author and r.author.name, q) or matchesText(r.author and r.author.callsign, q)
                for _, name in ipairs(entry.personNames) do
                    if name:lower():find(q, 1, true) then ok = true end
                end
            end
        end
        if ok then out[#out + 1] = entry end
        if #out >= 50 then break end
    end
    return out
end

local function reportOut(r)
    local out = public(r)
    out.personsInfo = {}
    for _, id in ipairs(r.persons or {}) do
        out.personsInfo[#out.personsInfo + 1] = R.summary(Store.get('person', id)) or { id = id, first = 'Deleted', last = 'person', flags = {} }
    end
    out.vehiclesInfo = {}
    for _, id in ipairs(r.vehicles or {}) do
        local v = Store.get('vehicle', id)
        if v then out.vehiclesInfo[#out.vehiclesInfo + 1] = withOwner(v) end
    end
    return out
end

H['report.get'] = function(ctx, p)
    if not ctx.abilities['records.view'] and not ctx.abilities['reports.write'] then fail("You aren't allowed to do that.") end
    local r = getOr('report', type(p) == 'table' and p.id, 'report')
    if not canReadReport(ctx, r) then fail("You can only read your own reports.") end
    return reportOut(r)
end

-- Up to max record numbers of a kind that exist, each once.
local function idList(values, kind, max, what)
    if values == nil then return {} end
    if type(values) ~= 'table' then fail(('Pick valid %s.'):format(what)) end
    local out, seen = {}, {}
    for _, value in ipairs(values) do
        local record = getOr(kind, value, kind)
        if not seen[record.id] then
            seen[record.id] = true
            out[#out + 1] = record.id
        end
    end
    if #out > max then fail(('A report can name up to %d %s.'):format(max, what)) end
    return out
end

H['report.save'] = function(ctx, p)
    need(ctx, 'reports.write')
    local input = payloadOf(p, 'report')
    local old = input.id ~= nil and getOr('report', input.id, 'report') or nil
    if old then
        local mine = ctx.license ~= nil and old.authorLicense == ctx.license
        if not ctx.abilities['reports.approve'] and not (mine and old.status ~= 'approved') then
            fail(mine and 'This report is approved and can no longer be changed.' or 'You can only change your own reports.')
        end
    end
    local r = old and copy(old) or {}
    if not contains(C.reportTypesFor(Config, ctx.roles), input.type) then fail("You can't write that type of report.") end
    local reportType = C.byKey(Config.ReportTypes, input.type)
    r.type = input.type
    r.title = required(input.title, 80, 'a title')
    r.narrative = C.text(input.narrative, 8000)
    r.persons = idList(input.persons, 'person', 10, 'people')
    r.vehicles = idList(input.vehicles, 'vehicle', 10, 'vehicles')
    r.callId = (input.callId ~= nil and input.callId ~= '') and getOr('call', input.callId, 'call').id or nil
    local status = input.status or 'draft'
    if status ~= 'draft' and status ~= 'submitted' then fail('A report can be saved as a draft or submitted.') end
    r.charges, r.totals = {}, nil
    local charges = type(input.charges) == 'table' and input.charges or {}
    if #charges > 0 then
        if not reportType.charges then fail('This type of report has no charges.') end
        local totals, why = C.chargeTotals(Config, charges)
        if not totals then fail(why) end
        r.totals = totals
        for _, item in ipairs(totals.items) do r.charges[#r.charges + 1] = { code = item.code, count = item.count } end
    end
    if status == 'submitted' and reportType.charges then
        if #r.persons == 0 then fail('Name the person this is for before submitting it.') end
        if #r.charges == 0 then fail('Add at least one charge before submitting it.') end
    end
    r.status = (old and old.status == 'approved') and 'approved' or status
    r.updatedAt = now()
    if not old then
        r.id = Store.nextId('report')
        r.createdAt = r.updatedAt
        r.author = { name = ctx.name, callsign = ctx.unit and ctx.unit.callsign or nil }
        r.authorLicense = ctx.license
    end
    Store.save('report', r)
    return reportOut(r)
end

H['report.approve'] = function(ctx, p)
    need(ctx, 'reports.approve')
    local r = getOr('report', type(p) == 'table' and p.id, 'report')
    if r.status ~= 'submitted' then fail('Only submitted reports can be approved.') end
    r.status = 'approved'
    r.approvedBy = ctx.name
    r.updatedAt = now()
    Store.save('report', r)
    return reportOut(r)
end

H['report.delete'] = function(ctx, p)
    need(ctx, 'records.delete')
    local r = getOr('report', type(p) == 'table' and p.id, 'report')
    Store.delete('report', r.id)
    return true
end

-- ------------------------------------------------------------------ warrants

local WARRANT_STATUSES = { requested = true, active = true, served = true, recalled = true, denied = true }

H['warrant.list'] = function(ctx, p)
    need(ctx, 'records.view')
    local status = type(p) == 'table' and p.status or nil
    local list = Store.list('warrant')
    table.sort(list, newestFirst)
    local out = {}
    for _, w in ipairs(list) do
        if not WARRANT_STATUSES[status] or w.status == status then out[#out + 1] = warrantOut(w) end
        if #out >= 100 then break end
    end
    return out
end

H['warrant.save'] = function(ctx, p)
    need(ctx, 'warrants.request')
    local input = payloadOf(p, 'warrant')
    local old = input.id ~= nil and getOr('warrant', input.id, 'warrant') or nil
    if old then
        if old.status ~= 'requested' then fail('Only a warrant that is still waiting for approval can be changed.') end
        if not ctx.abilities['warrants.approve'] and old.requesterLicense ~= ctx.license then fail('You can only change warrants you asked for.') end
    end
    local w = old and copy(old) or {}
    w.personId = getOr('person', input.personId, 'person').id
    local totals, why = C.chargeTotals(Config, type(input.charges) == 'table' and input.charges or {})
    if not totals then fail(why) end
    if #totals.items == 0 then fail('Add at least one charge.') end
    w.totals = totals
    w.charges = {}
    for _, item in ipairs(totals.items) do w.charges[#w.charges + 1] = { code = item.code, count = item.count } end
    w.reason = required(input.reason, 1000, 'the reason for the warrant')
    w.updatedAt = now()
    if not old then
        w.id = Store.nextId('warrant')
        w.createdAt = w.updatedAt
        w.requestedBy = { name = ctx.name, callsign = ctx.unit and ctx.unit.callsign or nil }
        w.requesterLicense = ctx.license
        if Config.WarrantsNeedApproval and not ctx.abilities['warrants.approve'] then
            w.status = 'requested'
        else
            w.status = 'active'
            w.decidedBy = { name = ctx.name }
        end
    end
    Store.save('warrant', w)
    return warrantOut(w)
end

-- Which status changes are allowed, and the ability each needs.
local TRANSITIONS = {
    requested = { active = 'warrants.approve', denied = 'warrants.approve' },
    active = { served = 'warrants.request', recalled = 'warrants.approve' },
}

H['warrant.setStatus'] = function(ctx, p)
    p = type(p) == 'table' and p or {}
    local w = getOr('warrant', p.id, 'warrant')
    local ability = TRANSITIONS[w.status] and TRANSITIONS[w.status][p.status]
    if not ability then fail(("A %s warrant can't be marked %s."):format(w.status, tostring(p.status))) end
    need(ctx, ability)
    w.status = p.status
    if p.status == 'active' or p.status == 'denied' or p.status == 'recalled' then w.decidedBy = { name = ctx.name } end
    if p.status == 'served' then w.servedBy = { name = ctx.name, callsign = ctx.unit and ctx.unit.callsign or nil } end
    w.updatedAt = now()
    Store.save('warrant', w)
    return warrantOut(w)
end

-- ------------------------------------------------------------------ BOLOs

local BOLO_KINDS = { person = true, vehicle = true, other = true }

H['bolo.list'] = function(ctx, p)
    need(ctx, 'people.view')
    local active = type(p) == 'table' and p.active
    local list = Store.list('bolo')
    table.sort(list, newestFirst)
    local out = {}
    for _, b in ipairs(list) do
        if type(active) ~= 'boolean' or b.active == active then
            local entry = public(b)
            entry.personName = personName(b.personId)
            out[#out + 1] = entry
        end
    end
    return out
end

H['bolo.save'] = function(ctx, p)
    need(ctx, 'bolos.edit')
    local input = payloadOf(p, 'bolo')
    local old = input.id ~= nil and getOr('bolo', input.id, 'bolo') or nil
    local b = old and copy(old) or {}
    if not BOLO_KINDS[input.kind] then fail('Pick what the BOLO is for: a person, a vehicle or something else.') end
    b.kind = input.kind
    b.title = required(input.title, 80, 'a title')
    b.description = C.text(input.description, 1000)
    b.plate = nil
    if input.plate ~= nil and input.plate ~= '' then
        b.plate = C.plateKey(input.plate)
        if not b.plate then fail('Enter a plate of 1 to 8 letters and numbers.') end
    end
    b.personId = ownerField(input.personId)
    b.updatedAt = now()
    if not old then
        b.id = Store.nextId('bolo')
        b.createdAt = b.updatedAt
        b.active = true
        b.createdBy = { name = ctx.name, callsign = ctx.unit and ctx.unit.callsign or nil }
    end
    Store.save('bolo', b)
    local out = public(b)
    out.personName = personName(b.personId)
    return out
end

H['bolo.setActive'] = function(ctx, p)
    need(ctx, 'bolos.edit')
    p = type(p) == 'table' and p or {}
    local b = getOr('bolo', p.id, 'bolo')
    b.active = p.active == true
    b.updatedAt = now()
    Store.save('bolo', b)
    local out = public(b)
    out.personName = personName(b.personId)
    return out
end

-- ------------------------------------------------------------------ civilians: their own records

local function myLicense(ctx)
    if not ctx.license then fail("Your FiveM license couldn't be found, so you can't keep records.") end
    return ctx.license
end

local function myPersons(ctx)
    local out = {}
    for _, person in ipairs(Store.list('person')) do
        if person.owner == ctx.license then out[#out + 1] = person end
    end
    return out
end

local function myPerson(ctx, id, what)
    local person = getOr('person', id, what or 'character')
    if person.owner ~= myLicense(ctx) then fail('That is not one of your characters.') end
    return person
end

local function ownedBy(kind, personId)
    local out = {}
    for _, record in ipairs(Store.list(kind)) do
        if record.ownerId == personId then out[#out + 1] = record end
    end
    return out
end

H['civ.list'] = function(ctx)
    myLicense(ctx)
    local out = { persons = {}, vehicles = {}, weapons = {}, citations = {} }
    local mine = {}
    for _, person in ipairs(myPersons(ctx)) do
        mine[person.id] = true
        out.persons[#out.persons + 1] = public(person)
        for _, v in ipairs(ownedBy('vehicle', person.id)) do out.vehicles[#out.vehicles + 1] = withOwner(v) end
        for _, w in ipairs(ownedBy('weapon', person.id)) do out.weapons[#out.weapons + 1] = withOwner(w) end
    end
    local reports = Store.list('report')
    table.sort(reports, newestFirst)
    for _, r in ipairs(reports) do
        if (r.type == 'citation' or r.type == 'arrest') and (r.status == 'submitted' or r.status == 'approved') then
            for _, id in ipairs(r.persons or {}) do
                if mine[id] then
                    out.citations[#out.citations + 1] = {
                        reportId = r.id, type = r.type, title = r.title, createdAt = r.createdAt, totals = copy(r.totals), personId = id,
                    }
                end
            end
        end
    end
    return out
end

H['civ.savePerson'] = function(ctx, p)
    local license = myLicense(ctx)
    local input = payloadOf(p, 'person')
    local old = input.id ~= nil and myPerson(ctx, input.id) or nil
    if not old and #myPersons(ctx) >= Config.Civilian.maxCharacters then
        fail(('You can keep up to %d characters.'):format(Config.Civilian.maxCharacters))
    end
    local person = old and copy(old) or {}
    identity(input, person)
    if not old then
        -- A new character picks which licenses they hold; after that only police can change them.
        person.licenses = licensesField(input.licenses, nil, { valid = true, none = true })
        person.flags = {}
        person.notes = ''
        person.owner = license
        person.id = Store.nextId('person')
        person.createdAt = now()
    end
    person.updatedAt = now()
    Store.save('person', person)
    return public(person)
end

H['civ.deletePerson'] = function(ctx, p)
    local person = myPerson(ctx, type(p) == 'table' and p.id)
    -- Their own vehicles and weapons go with them; any the police filed against them are kept.
    for _, kind in ipairs({ 'vehicle', 'weapon' }) do
        for _, record in ipairs(ownedBy(kind, person.id)) do
            if record.owner == ctx.license then Store.delete(kind, record.id) end
        end
    end
    unlinkOwner(person.id)
    Store.delete('person', person.id)
    return true
end

local function myRecord(ctx, kind, id, what)
    local record = getOr(kind, id, what)
    if record.owner ~= myLicense(ctx) then fail(('That is not your %s.'):format(what)) end
    return record
end

H['civ.saveVehicle'] = function(ctx, p)
    local license = myLicense(ctx)
    local input = payloadOf(p, 'vehicle')
    local old = input.id ~= nil and myRecord(ctx, 'vehicle', input.id, 'vehicle') or nil
    local owner = myPerson(ctx, input.ownerId)
    if (not old or old.ownerId ~= owner.id) and #ownedBy('vehicle', owner.id) >= Config.Civilian.maxVehicles then
        fail(('Each character can register up to %d vehicles.'):format(Config.Civilian.maxVehicles))
    end
    local v = old and copy(old) or {}
    v.plateKey = plateField(input.plate, old and old.id)
    v.plate = v.plateKey
    v.model = required(input.model, 30, 'the model')
    v.color = C.text(input.color, 20)
    v.ownerId = owner.id
    if not old then
        local states = { valid = true, none = true }
        v.registration = states[input.registration] and input.registration or 'valid'
        v.insurance = states[input.insurance] and input.insurance or 'valid'
        v.flags = {}
        v.notes = ''
        v.owner = license
        v.id = Store.nextId('vehicle')
        v.createdAt = now()
    end
    v.updatedAt = now()
    Store.save('vehicle', v)
    return withOwner(v)
end

H['civ.deleteVehicle'] = function(ctx, p)
    local v = myRecord(ctx, 'vehicle', type(p) == 'table' and p.id, 'vehicle')
    Store.delete('vehicle', v.id)
    return true
end

H['civ.saveWeapon'] = function(ctx, p)
    local license = myLicense(ctx)
    local input = payloadOf(p, 'weapon')
    local old = input.id ~= nil and myRecord(ctx, 'weapon', input.id, 'weapon') or nil
    local owner = myPerson(ctx, input.ownerId)
    if (not old or old.ownerId ~= owner.id) and #ownedBy('weapon', owner.id) >= Config.Civilian.maxWeapons then
        fail(('Each character can register up to %d weapons.'):format(Config.Civilian.maxWeapons))
    end
    local w = old and copy(old) or {}
    w.serial = serialField(input.serial, old and old.id)
    w.kind = required(input.kind, 30, 'the kind of weapon')
    w.ownerId = owner.id
    if not old then
        w.status = 'registered'
        w.notes = ''
        w.owner = license
        w.id = Store.nextId('weapon')
        w.createdAt = now()
    end
    w.updatedAt = now()
    Store.save('weapon', w)
    return withOwner(w)
end

H['civ.deleteWeapon'] = function(ctx, p)
    local w = myRecord(ctx, 'weapon', type(p) == 'table' and p.id, 'weapon')
    if w.status == 'seized' then fail('This weapon was seized by the police.') end
    Store.delete('weapon', w.id)
    return true
end

H['civ.reportStolen'] = function(ctx, p)
    p = type(p) == 'table' and p or {}
    local stolen = p.stolen == true
    if p.vehicleId ~= nil then
        local v = myRecord(ctx, 'vehicle', p.vehicleId, 'vehicle')
        local flags = {}
        for _, flag in ipairs(v.flags or {}) do
            if flag ~= 'stolen' then flags[#flags + 1] = flag end
        end
        if stolen then flags[#flags + 1] = 'stolen' end
        v.flags = flags
        v.updatedAt = now()
        Store.save('vehicle', v)
        return withOwner(v)
    end
    local w = myRecord(ctx, 'weapon', p.weaponId, 'weapon')
    if w.status == 'seized' then fail('This weapon was seized by the police.') end
    w.status = stolen and 'stolen' or 'registered'
    w.updatedAt = now()
    Store.save('weapon', w)
    return withOwner(w)
end
