-- The rules for vehicle skins, shared by the server, every player's game and the tests. No FiveM
-- natives here, so it runs in plain Lua:  lua tests/skins_spec.lua

VehicleSkins = {}
local S = VehicleSkins

S.VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }
S.MAX_EXTRA = 20
S.MAX_COLOR = 160 -- GTA's paint numbers go from 0 to 160

-- A whole number typed by a player, within min..max, or nil.
function S.parseNumber(text, min, max)
    local n = tonumber(text)
    if not n or n ~= math.floor(n) or n < min or n > max then return nil end
    return math.floor(n)
end

function S.normalizeModel(text)
    if type(text) ~= 'string' then return '' end
    return (text:lower():gsub('%s+', ''))
end

function S.validModelName(model)
    return type(model) == 'string' and #model >= 2 and #model <= 32 and model:match('^[%w_]+$') ~= nil
end

-- Whether a model is blocked. Compared by hash (hash = GetHashKey), because that's what gets spawned:
-- another name with the same hash would otherwise get a blocked vehicle past a name check.
function S.isBlocked(config, model, hash)
    local wanted = hash(model)
    for _, blocked in ipairs(config.BlockedModels or {}) do
        if hash(blocked:lower()) == wanted then return true end
    end
    return false
end

local knownByHash = {} -- [hash function] = { [model hash] = type }

-- The type a model has to be spawned as (shared/vehicle_types.lua is loaded first): Config.VehicleTypes
-- for add-ons, the built-in list, 'train' for trains (which can't be spawned), or "automobile". Looked
-- up by model hash (hash = GetHashKey), so another name for a helicopter's model is still a helicopter.
function S.typeFor(config, model, hash)
    hash = hash or function(name) return name end
    local wanted = hash(model)
    for name, kind in pairs(config.VehicleTypes or {}) do
        if hash(name) == wanted then return kind end
    end
    local known = knownByHash[hash]
    if not known then
        known = {}
        for name, kind in pairs(KnownVehicleTypes) do known[hash(name)] = kind end
        for name in pairs(KnownTrains) do known[hash(name)] = 'train' end
        knownByHash[hash] = known
    end
    return known[wanted] or 'automobile'
end

function S.isTrain(model)
    return KnownTrains[model] == true
end

-- Plate text the game accepts: up to 8 capital letters, numbers and spaces.
function S.formatPlate(text)
    if type(text) ~= 'string' then return '' end
    local plate = text:upper():gsub('[^A-Z0-9 ]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return plate:sub(1, 8)
end

function S.cooldownLeft(lastAt, now, seconds)
    if not lastAt then return 0 end
    local left = lastAt + seconds - now
    return left > 0 and math.ceil(left) or 0
end

-- Vehicles have liveries one of two ways: the classic kind (GetVehicleLiveryCount, which is -1
-- when there are none) or as a "livery" mod in the mod kit (mod type 48). Returns which kind and
-- how many, or nil when the vehicle has none.
function S.liveryKind(classicCount, modCount)
    if classicCount and classicCount > 0 then return { kind = 'classic', count = classicCount } end
    if modCount and modCount > 0 then return { kind = 'mod', count = modCount } end
    return nil
end

-- A random livery number (1-based) that differs from the current one when there's a choice.
-- random(a, b) is math.random, passed in so the tests can control it.
function S.randomLivery(count, current, random)
    if count < 1 then return nil end
    if count == 1 then return 1 end
    if not current or current < 1 or current > count then return random(1, count) end
    local pick = random(1, count - 1) -- one fewer choice, then skip over the current one
    if pick >= current then pick = pick + 1 end
    return pick
end

-- Allows at most maxCalls per key within windowSeconds. Returns allow(key, now) and forget(key).
function S.newRateLimiter(maxCalls, windowSeconds)
    local hits = {}
    local function allow(key, now)
        local fresh = {}
        for _, t in ipairs(hits[key] or {}) do
            if now - t < windowSeconds then fresh[#fresh + 1] = t end
        end
        if #fresh >= maxCalls then
            hits[key] = fresh
            return false
        end
        fresh[#fresh + 1] = now
        hits[key] = fresh
        return true
    end
    local function forget(key) hits[key] = nil end
    return allow, forget
end

return S
