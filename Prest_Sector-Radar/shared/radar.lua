-- Prest_Sector Radar: the rules both sides share. Plain functions with no game calls, so the tests
-- can run them anywhere.
--   Geometry: where a car sits compared with the patrol car, and whether a beam sees it.
--   Readings: the closest and the fastest car in an antenna's beam, and the car a plate camera reads.
--   Plates: tidying a plate, and turning a records answer into a hit, a notice or all clear.
--   Settings: an officer's saved radar settings, checked and filled in.
--   The hotlist, and the server's limit on how often one player can ask.

Radar = {}
local R = Radar

R.EVENT = 'Prest_Sector-Radar:'
R.MODES = { same = true, opp = true, both = true }
R.ANTENNAS = { front = 1, rear = -1 } -- which way each one faces along the patrol car

-- ------------------------------------------------------------------ numbers and text

function R.round(n) return math.floor(n + 0.5) end

function R.clamp(n, lo, hi)
    n = tonumber(n)
    if not n or n ~= n then return nil end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- A speed in meters per second, in mph or km/h.
function R.toUnits(metersPerSecond, units)
    return (tonumber(metersPerSecond) or 0) * (units == 'kmh' and 3.6 or 2.2369363)
end

-- Text from a player, made safe to keep and show: one line, no control characters, at most max long.
function R.text(value, max)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if #value > max then value = value:sub(1, max):match('^(.-)%s*$') end
    return value
end

-- ------------------------------------------------------------------ plates

-- A plate as the records keep it: letters and digits only, upper case, 1 to 8 long (the same rule as
-- Prest_Sector-CAD). nil when it can't be a plate.
function R.plateKey(plate)
    if type(plate) ~= 'string' then return nil end
    local key = plate:upper():gsub('[^A-Z0-9]', '')
    if #key < 1 or #key > 8 then return nil end
    return key
end

-- The game's plate styles (0 to 5); anything else shows as the usual blue on white.
function R.plateStyle(index)
    index = math.floor(tonumber(index) or 0)
    if index < 0 or index > 5 then return 0 end
    return index
end

-- CAD answers that say nothing useful about a car passing by.
local QUIET = { ['No record of this plate.'] = true, ['No registered owner.'] = true }

-- What a plate reader shows for a plate:
--   key       the plate
--   cad       Prest_Sector-CAD's plate check (nil when the CAD isn't running or didn't answer)
--   hot       the plate's hotlist entry, if it has one
--   notices   whether lesser problems (expired papers) show at all
-- Returns { plate, status = 'hit' | 'notice' | 'clear', reasons = { ... }, vehicle, owner, inCad }.
function R.classify(key, cad, hot, notices)
    local result = { plate = key, status = 'clear', reasons = {}, inCad = false }
    local hits, lesser = {}, {}
    if hot then hits[#hits + 1] = 'Hotlist: ' .. hot.reason end
    if type(cad) == 'table' then
        result.inCad = cad.found == true
        for _, a in ipairs(type(cad.alerts) == 'table' and cad.alerts or {}) do
            local text = type(a) == 'table' and R.text(a.text, 120) or ''
            if text ~= '' and not QUIET[text] then
                if a.tone == 'error' then hits[#hits + 1] = text else lesser[#lesser + 1] = text end
            end
        end
        local v = type(cad.vehicle) == 'table' and cad.vehicle or nil
        if v then
            local what = R.text(((v.color or '') .. ' ' .. (v.model or '')), 40)
            if what ~= '' then result.vehicle = what end
        end
        local o = type(cad.owner) == 'table' and cad.owner or nil
        if o then
            local name = R.text(((o.first or '') .. ' ' .. (o.last or '')), 40)
            if name ~= '' then result.owner = name end
        end
    end
    if #hits > 0 then
        result.status, result.reasons = 'hit', hits
        if notices then
            for _, text in ipairs(lesser) do result.reasons[#result.reasons + 1] = text end
        end
    elseif notices and #lesser > 0 then
        result.status, result.reasons = 'notice', lesser
    end
    return result
end

-- ------------------------------------------------------------------ geometry

-- Where a point sits compared with the patrol car: meters ahead (negative: behind), to the right
-- (negative: left), and above. forward is the patrol car's heading (x and y are enough).
function R.relative(origin, forward, point)
    local fx, fy = forward.x or 0.0, forward.y or 0.0
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 1e-6 then return nil end
    fx, fy = fx / len, fy / len
    local dx, dy, dz = point.x - origin.x, point.y - origin.y, (point.z or 0.0) - (origin.z or 0.0)
    return { ahead = dx * fx + dy * fy, side = dx * fy - dy * fx, up = dz }
end

-- Whether a beam sees a point (from R.relative). dir is 1 for the front, -1 for the rear. The beam
-- starts nearWidth wide either side at the car and spreads by angle degrees each way.
function R.inBeam(rel, dir, beam)
    if not rel then return false end
    local along = rel.ahead * dir
    if along < (beam.minDistance or 2.5) or along > beam.range then return false end
    if math.abs(rel.up) > (beam.height or 10.0) then return false end
    local half = (beam.nearWidth or 0.0) + along * math.tan(math.rad(beam.angle))
    return math.abs(rel.side) <= half
end

-- Which way a car moves compared with where the patrol car faces: 'same', 'opp', or nil when it's
-- barely moving or crossing (a radar can't read a car driving across its beam).
function R.direction(forward, velocity)
    local fx, fy = forward.x or 0.0, forward.y or 0.0
    local flen = math.sqrt(fx * fx + fy * fy)
    local vx, vy = velocity.x or 0.0, velocity.y or 0.0
    local vlen = math.sqrt(vx * vx + vy * vy)
    if flen < 1e-6 or vlen < 0.5 then return nil end
    local cos = (vx * fx + vy * fy) / (vlen * flen)
    if cos > 0.5 then return 'same' end
    if cos < -0.5 then return 'opp' end
    return nil
end

function R.modeAllows(mode, direction)
    return direction ~= nil and (mode == 'both' or mode == direction)
end

-- Reads one antenna, like a traffic radar: the closest car in the beam (the strongest return) and,
-- when another car in the beam is faster, the fastest.
--   patrol  { id, pos, forward }
--   cars    list of { id, pos, vel, speed } (speed in meters per second)
--   dir     1 front, -1 rear;   mode 'same' | 'opp' | 'both'
-- Returns target, fast: each { id, speed (whole Config.Units), distance } or nil.
function R.readAntenna(patrol, cars, dir, mode, beam, units, minSpeed)
    local target, fast
    for _, car in ipairs(cars) do
        if car.id ~= patrol.id then
            local rel = R.relative(patrol.pos, patrol.forward, car.pos)
            if R.inBeam(rel, dir, beam) and R.modeAllows(mode, R.direction(patrol.forward, car.vel)) then
                local speed = R.round(R.toUnits(car.speed, units))
                if speed >= (minSpeed or 0) then
                    local reading = { id = car.id, speed = speed, distance = math.abs(rel.ahead) }
                    if not target or reading.distance < target.distance then target = reading end
                    if not fast or reading.speed > fast.speed then fast = reading end
                end
            end
        end
    end
    if fast and target and (fast.id == target.id or fast.speed <= target.speed) then fast = nil end
    return target, fast
end

-- The car a plate camera reads: the closest one in its beam, moving or not. Returns { id, distance } or nil.
function R.readCamera(patrol, cars, dir, camera)
    local best
    for _, car in ipairs(cars) do
        if car.id ~= patrol.id then
            local rel = R.relative(patrol.pos, patrol.forward, car.pos)
            if R.inBeam(rel, dir, camera) then
                local distance = math.abs(rel.ahead)
                if not best or distance < best.distance then best = { id = car.id, distance = distance } end
            end
        end
    end
    return best
end

-- ------------------------------------------------------------------ an officer's settings

-- Everything an officer can change on their radar, checked: wrong or missing values get the defaults.
function R.cleanSettings(saved, cfg)
    local s = type(saved) == 'table' and saved or {}
    local function antenna(a, defaultMode)
        a = type(a) == 'table' and a or {}
        return { on = a.on ~= false, mode = R.MODES[a.mode] and a.mode or defaultMode }
    end
    local out = {
        front = antenna(s.front, 'both'),
        rear = antenna(s.rear, 'both'),
        plates = s.plates ~= false,
        fastLimit = math.floor(R.clamp(s.fastLimit, 5, 250) or R.clamp(cfg.Radar.fastLimit, 5, 250) or 75),
        fastLock = s.fastLock == true,
        volume = math.floor(R.clamp(s.volume, 0, 100) or 60),
        scale = R.clamp(s.scale, 0.6, 1.6) or 1.0,
    }
    if type(s.pos) == 'table' then
        local x, y = R.clamp(s.pos.x, 0, 1), R.clamp(s.pos.y, 0, 1)
        if x and y then out.pos = { x = x, y = y } end
    end
    return out
end

-- ------------------------------------------------------------------ the hotlist

-- The hotlist is a table of plate key -> { plate, reason, by, at, ends } (times in os.time seconds).

-- Takes out entries that have ended. Returns how many went.
function R.hotlistPrune(list, now)
    local gone = 0
    for key, entry in pairs(list) do
        if type(entry) ~= 'table' or (tonumber(entry.ends) or 0) <= now then
            list[key] = nil
            gone = gone + 1
        end
    end
    return gone
end

function R.hotlistFind(list, key, now)
    local entry = key and list[key]
    if entry and (tonumber(entry.ends) or 0) > now then return entry end
    return nil
end

function R.hotlistCount(list)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    return n
end

-- Adds (or renews) a plate. Returns the entry, or nil and why not.
function R.hotlistAdd(list, plate, reason, by, now, hours, max)
    local key = R.plateKey(plate)
    if not key then return nil, "That isn't a plate. Plates are 1 to 8 letters and numbers." end
    reason = R.text(reason, 60)
    if reason == '' then return nil, 'Give a reason, for example: stolen from Legion Square.' end
    if not list[key] then
        R.hotlistPrune(list, now)
        if R.hotlistCount(list) >= max then return nil, ('The hotlist is full (%d plates). Remove one first.'):format(max) end
    end
    local entry = { plate = key, reason = reason, by = R.text(by, 40), at = now, ends = now + math.floor(hours * 3600) }
    list[key] = entry
    return entry
end

-- The entries still running, newest first.
function R.hotlistEntries(list, now)
    local out = {}
    for _, entry in pairs(list) do
        if type(entry) == 'table' and (tonumber(entry.ends) or 0) > now then out[#out + 1] = entry end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.plate < b.plate
    end)
    return out
end

-- ------------------------------------------------------------------ how often one player can ask

-- A fixed one-minute window per player. Returns true when this request is allowed.
function R.allowRequest(bucket, nowMs, perMinute)
    if not bucket.start or nowMs - bucket.start >= 60000 or nowMs < bucket.start then
        bucket.start, bucket.count = nowMs, 0
    end
    if bucket.count >= perMinute then return false end
    bucket.count = bucket.count + 1
    return true
end

-- ------------------------------------------------------------------ the settings file

-- Mistakes in config.lua, as sentences (printed by the server at start).
function R.checkConfig(cfg)
    local problems = {}
    local function need(ok, text) if not ok then problems[#problems + 1] = text end end
    need(cfg.Units == 'mph' or cfg.Units == 'kmh', "Config.Units must be 'mph' or 'kmh'.")
    for _, field in ipairs({ 'range', 'angle', 'updateMs', 'fastLimit' }) do
        need((tonumber(cfg.Radar[field]) or 0) > 0, ('Config.Radar.%s must be a number above 0.'):format(field))
    end
    for _, field in ipairs({ 'range', 'angle', 'repeatSeconds' }) do
        need((tonumber(cfg.PlateReader[field]) or 0) > 0, ('Config.PlateReader.%s must be a number above 0.'):format(field))
    end
    need((tonumber(cfg.Hotlist.hours) or 0) > 0, 'Config.Hotlist.hours must be a number above 0.')
    need((tonumber(cfg.Hotlist.max) or 0) >= 1, 'Config.Hotlist.max must be at least 1.')
    need((tonumber(cfg.Server.lookupsPerMinute) or 0) >= 1, 'Config.Server.lookupsPerMinute must be at least 1.')
    need(type(cfg.Access.cadRoles) == 'table', 'Config.Access.cadRoles must be a list, for example { "police" }.')
    need(type(cfg.Vehicles.models) == 'table', 'Config.Vehicles.models must be a list of spawn names.')
    return problems
end
