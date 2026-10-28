-- Draws the cuffs on every cuffed player this game can see, from what the server sets in GlobalState
-- (prestSectorCuffs:<id>). Each game makes its own copy of the cuffs and hangs it on that
-- player's wrist, so the cuffs move with their hands, nothing extra travels over the network, and no
-- cuffs are left lying around when someone leaves.

local C = Cuffs

CuffProps = {}
local props = {} -- [server ID] = { object, ped, key }

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    for _ = 1, 200 do
        if HasModelLoaded(hash) then return true end
        Wait(10)
    end
    return HasModelLoaded(hash)
end

-- Hangs a style's cuffs on a ped's hand bone. offset and rotation default to the style's own.
-- Only this game sees the object. Returns it, or nil if the model isn't in the game.
function CuffProps.attach(ped, style, offset, rotation)
    local hash = GetHashKey(style.prop)
    if not loadModel(hash) then return nil end
    local at = GetEntityCoords(ped)
    local object = CreateObject(hash, at.x, at.y, at.z - 2.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not object or object == 0 then return nil end
    SetEntityCollision(object, false, false)
    SetEntityCanBeDamaged(object, false)
    CuffProps.place(object, ped, style, offset, rotation)
    return object
end

-- Hangs (or moves) cuffs on a ped's hand. The last six values are the ones the shipped offsets were
-- measured with; changing them, the rotation order (0) above all, turns the cuffs a different way.
function CuffProps.place(object, ped, style, offset, rotation)
    local o, r = offset or style.offset, rotation or style.rotation
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, style.bone), o[1], o[2], o[3], r[1], r[2], r[3],
        true, false, false, false, 0, true)
end

local function remove(id)
    local p = props[id]
    props[id] = nil
    if p and DoesEntityExist(p.object) then DeleteEntity(p.object) end
end

local function update()
    local seen = {}
    for _, player in ipairs(GetActivePlayers()) do
        local id = GetPlayerServerId(player)
        local key = GlobalState[C.cuffsKey(id)]
        local style = key and Config.Styles[key]
        local ped = GetPlayerPed(player)
        if style and ped ~= 0 and DoesEntityExist(ped) then
            seen[id] = true
            local p = props[id]
            -- New cuffs, another style, or a new ped (the player respawned or changed model).
            if not p or p.ped ~= ped or p.key ~= key or not DoesEntityExist(p.object)
                or not IsEntityAttachedToEntity(p.object, ped) then
                remove(id)
                local object = CuffProps.attach(ped, style)
                if object then props[id] = { object = object, ped = ped, key = key } end
                p = props[id]
            end
            -- The cuffs disappear with the player (an admin going invisible, a cutscene).
            if p and IsEntityVisible(p.object) ~= IsEntityVisible(ped) then
                SetEntityVisible(p.object, IsEntityVisible(ped), false)
            end
        end
    end
    for id in pairs(props) do
        if not seen[id] then remove(id) end
    end
end

-- Puts cuffs on every cuffed player in view and takes them off everyone else. Safe to call any time:
-- a call made while one is already running just makes it go round once more.
local running, again = false, false
function CuffProps.refresh()
    if running then
        again = true
        return
    end
    running = true
    repeat
        again = false
        local ok, err = pcall(update)
        if not ok then print(('[Prest_Sector-Cuffs] drawing cuffs failed: %s'):format(tostring(err))) end
    until not again
    running = false
end

-- The server ID of every player this game is drawing cuffs on (for the tests and other scripts).
function CuffProps.drawn()
    local list = {}
    for id, p in pairs(props) do list[id] = p.object end
    return list
end

-- Cuffs going on or off show at once. FiveM runs this before it stores the new value, so wait a frame.
local PREFIX = C.CUFFS .. ':'
AddStateBagChangeHandler(nil, 'global', function(_, key)
    if type(key) ~= 'string' or key:sub(1, #PREFIX) ~= PREFIX then return end
    CreateThread(function()
        Wait(0)
        CuffProps.refresh()
    end)
end)

-- And every half second, for players coming into view, respawning or going invisible.
CreateThread(function()
    while true do
        CuffProps.refresh()
        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(props) do remove(id) end
end)
