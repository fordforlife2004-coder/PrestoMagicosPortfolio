-- The spawn rules, shared by the server, every player's game and the tests. No FiveM natives here,
-- so it runs in plain Lua:  lua tests/rules_spec.lua  (shared/vehicle_types.lua is loaded first)

VehicleSpawnRules = {}
local R = VehicleSpawnRules

-- The vehicle types the server can spawn (trains need a different native, so they aren't here).
R.VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }

-- "  Adder " -> "adder"
function R.normalizeModel(text)
    if type(text) ~= 'string' then return '' end
    return (text:lower():gsub('%s+', ''))
end

-- Model names: letters, numbers and underscores, 2 to 32 characters.
function R.validModelName(model)
    return type(model) == 'string' and #model >= 2 and #model <= 32 and model:match('^[%w_]+$') ~= nil
end

local knownByHash = {} -- [hash function] = { [model hash] = type }

-- The type a model has to be spawned as: from Config.VehicleTypes for add-ons, the built-in list,
-- 'train' for trains (which can't be spawned), or "automobile" for everything else. Looked up by
-- model hash (hash = GetHashKey), so another name for a helicopter's model is still a helicopter.
function R.typeFor(config, model, hash)
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

function R.isTrain(model)
    return KnownTrains[model] == true
end

-- Whether a model is blocked. Compared by hash (hash = GetHashKey), because that's what gets spawned:
-- another name with the same hash would otherwise get a blocked vehicle past a name check.
function R.isBlocked(config, model, hash)
    local wanted = hash(model)
    for _, blocked in ipairs(config.BlockedModels or {}) do
        if hash(blocked:lower()) == wanted then return true end
    end
    return false
end

-- Whole seconds left before a player may spawn again (0 when they can).
function R.cooldownLeft(lastAt, now, seconds)
    if not lastAt then return 0 end
    local left = lastAt + seconds - now
    return left > 0 and math.ceil(left) or 0
end

-- Plate text the game accepts: up to 8 capital letters, numbers and spaces.
function R.formatPlate(text)
    if type(text) ~= 'string' then return '' end
    local plate = text:upper():gsub('[^A-Z0-9 ]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return plate:sub(1, 8)
end

return R
