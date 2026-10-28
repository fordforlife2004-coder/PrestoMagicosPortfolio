-- The rules for Prest_Sector Cuffs, shared by the server, every player's game and the tests. No FiveM
-- natives here, so it runs in plain Lua:  lua tests/cuffs_spec.lua

Cuffs = {}
local C = Cuffs

-- Who is cuffed and who is held live in GlobalState, which every game can read and only the server
-- can write, under one key per player. Other scripts can read them too, for example
-- GlobalState['prestSectorCuffs:12'] to stop cuffed player 12 opening their phone.
C.CUFFS = 'prestSectorCuffs'   -- prestSectorCuffs:<id>  = the cuff style they wear ('rear' or 'front'), or nil
C.ESCORT = 'prestSectorEscort' -- prestSectorEscort:<id> = the server ID of the officer holding them by the arm, or nil

function C.cuffsKey(id) return ('%s:%d'):format(C.CUFFS, id) end
function C.escortKey(id) return ('%s:%d'):format(C.ESCORT, id) end

-- A player's server ID from a net event or an export: a whole number from 1 up, or nil. (A client
-- could send 2.5 or "2", which the game's own functions would still treat as player 2.)
function C.toId(value)
    local n = math.tointeger(tonumber(value))
    if n and n >= 1 and n <= 65535 then return n end
    return nil
end

-- Words players may type for a style, besides its own name.
C.ALIASES = { back = 'rear', behind = 'rear', infront = 'front' }

-- The style a player typed (any capitals, or an alias), or the default when they typed nothing.
function C.findStyle(config, name)
    if name == nil or name == '' then name = config.DefaultStyle end
    if type(name) ~= 'string' then return nil end
    name = name:lower()
    name = C.ALIASES[name] or name
    local style = (config.Styles or {})[name]
    if style then return name, style end
    return nil
end

function C.distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The direction GTA's heading points (0 is north, 90 is west).
local function forward(heading)
    local rad = math.rad(heading or 0)
    return -math.sin(rad), math.cos(rad)
end

-- Which side of the suspect the officer is standing on: 'front' or 'behind'.
function C.sideOf(suspect, suspectHeading, officer)
    local fx, fy = forward(suspectHeading)
    return (officer.x - suspect.x) * fx + (officer.y - suspect.y) * fy > 0 and 'front' or 'behind'
end

-- The style for a /cuff with nothing typed: in front when the officer faces the suspect (if
-- Config.ChooseByPosition is on and there is a front style), otherwise the default.
function C.styleFor(config, typed, suspect, suspectHeading, officer)
    if (typed == nil or typed == '') and config.ChooseByPosition and config.Styles.front
        and C.sideOf(suspect, suspectHeading, officer) == 'front' then
        return 'front', config.Styles.front
    end
    return C.findStyle(config, typed)
end

-- The animation for cuffs going on or coming off ('cuff' or 'uncuff'): the style's own, if it has
-- one (cuffing in front looks different), or the usual one.
function C.animationFor(config, kind, styleKey)
    local style = config.Styles[styleKey or '']
    return style and style[kind] or config.Animations[kind]
end

-- The player an officer means: the closest one within reach, preferring someone in front of them.
--   me       the officer's position { x, y, z }
--   heading  the officer's heading in degrees (GTA: 0 is north, 90 is west)
--   others   a list of { id = server ID, coords = { x, y, z } }
function C.pickTarget(me, heading, others, maxDistance)
    local fx, fy = forward(heading)
    local best, bestScore
    for _, other in ipairs(others) do
        local d = C.distance(me, other.coords)
        if d <= maxDistance then
            local dx, dy = other.coords.x - me.x, other.coords.y - me.y
            local flat = math.sqrt(dx * dx + dy * dy)
            local ahead = flat > 0.05 and (dx * fx + dy * fy) / flat or 1
            -- Someone behind the officer is only picked when nobody is in front.
            local score = d + (ahead < 0 and maxDistance or 0)
            if not bestScore or score < bestScore then best, bestScore = other.id, score end
        end
    end
    return best
end

-- ---------------------------------------------------------------- /cuffadjust

C.AXES = { 'x', 'y', 'z' }

-- The line /cuffadjust prints, to paste over a style's offset and rotation in config.lua.
function C.attachLine(offset, rotation)
    return ('offset = { %.3f, %.3f, %.3f }, rotation = { %.1f, %.1f, %.1f },'):format(
        offset[1], offset[2], offset[3], rotation[1], rotation[2], rotation[3])
end

-- One nudge from /cuffadjust: moves (or turns) one axis and returns new copies of both lists.
-- Positions are rounded to millimetres, angles to tenths of a degree and kept from 0 to 360.
function C.nudge(offset, rotation, what, axis, amount)
    local o, r = { offset[1], offset[2], offset[3] }, { rotation[1], rotation[2], rotation[3] }
    if what == 'move' then
        o[axis] = math.floor((o[axis] + amount) * 1000 + 0.5) / 1000
    else
        r[axis] = (math.floor((r[axis] + amount) * 10 + 0.5) / 10) % 360
    end
    return o, r
end

-- ---------------------------------------------------------------- config check

local function isList(value, count)
    if type(value) ~= 'table' or #value ~= count then return false end
    for i = 1, count do if type(value[i]) ~= 'number' then return false end end
    return true
end

local function isAnim(anim)
    return type(anim) == 'table' and type(anim.dict) == 'string' and type(anim.clip) == 'string'
        and (anim.flags == nil or type(anim.flags) == 'number')
end

-- Problems in a config, as readable lines (empty when it's fine). Printed when the server starts.
function C.checkConfig(config)
    local problems = {}
    local function add(...) problems[#problems + 1] = string.format(...) end
    local function checkAnimation(a, where)
        if type(a) ~= 'table' then return add('%s is missing', where) end
        if type(a.seconds) ~= 'number' or a.seconds <= 0 or a.seconds > 15 then add('%s.seconds must be between 0 and 15', where) end
        if not isAnim(a.officer) then add('%s.officer must be { dict = ..., clip = ... }', where) end
        if not isAnim(a.suspect) then add('%s.suspect must be { dict = ..., clip = ... }', where) end
        if a.lineUp and not isList(a.lineUp.offset, 3) then add('%s.lineUp.offset must be { x, y, z }', where) end
    end
    local count = 0
    for key, s in pairs(config.Styles or {}) do
        count = count + 1
        local where = 'Config.Styles.' .. tostring(key)
        if type(key) ~= 'string' or not key:match('^[%l%d_]+$') then add('%s: style names must be one lowercase word', where) end
        if C.ALIASES[key] then add('%s: "%s" is already a short name for %s', where, key, C.ALIASES[key]) end
        if type(s.label) ~= 'string' or s.label == '' then add('%s: label is missing', where) end
        if type(s.prop) ~= 'string' or not s.prop:match('^[%w_]+$') then add('%s: prop must be a model name', where) end
        if type(s.bone) ~= 'number' then add('%s: bone must be a bone ID number', where) end
        if not isList(s.offset, 3) then add('%s: offset must be { x, y, z }', where) end
        if not isList(s.rotation, 3) then add('%s: rotation must be { x, y, z }', where) end
        if not isAnim(s.anim) then add('%s: anim must be { dict = ..., clip = ... }', where) end
        if s.walk ~= nil and not isAnim(s.walk) then add('%s: walk must be { dict = ..., clip = ... }', where) end
        if s.cuff ~= nil then checkAnimation(s.cuff, where .. '.cuff') end
        if s.uncuff ~= nil then checkAnimation(s.uncuff, where .. '.uncuff') end
    end
    if count == 0 then add('Config.Styles: there are no cuff styles') end
    if not (config.Styles or {})[config.DefaultStyle or ''] then
        add('Config.DefaultStyle: "%s" is not a style', tostring(config.DefaultStyle))
    end
    if config.ChooseByPosition and not (config.Styles or {}).front then
        add('Config.ChooseByPosition needs a style called front')
    end
    if type(config.MaxDistance) ~= 'number' or config.MaxDistance < 0.5 or config.MaxDistance > 5 then
        add('Config.MaxDistance must be between 0.5 and 5 metres')
    end
    if type(config.VehicleDistance) ~= 'number' or config.VehicleDistance < 1 or config.VehicleDistance > 10 then
        add('Config.VehicleDistance must be between 1 and 10 metres')
    end
    if config.KeepCuffsMinutes ~= nil and (type(config.KeepCuffsMinutes) ~= 'number' or config.KeepCuffsMinutes < 0) then
        add('Config.KeepCuffsMinutes must be 0 or more')
    end
    for _, kind in ipairs({ 'cuff', 'uncuff' }) do
        checkAnimation((config.Animations or {})[kind], 'Config.Animations.' .. kind)
    end
    local e = config.Escort
    if type(e) ~= 'table' or type(e.bone) ~= 'number' or not isList(e.offset, 3) then
        add('Config.Escort needs a bone and an offset { x, y, z }')
    else
        for _, name in ipairs({ 'walk', 'run', 'officer' }) do
            if e[name] ~= nil and not isAnim(e[name]) then add('Config.Escort.%s must be { dict = ..., clip = ... }', name) end
        end
    end
    return problems
end

return C
