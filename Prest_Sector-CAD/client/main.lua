-- The tablet in each player's game: opening and closing it (with a tablet in their hands), passing
-- the tablet's requests to the server and the answers back, and live updates from the server.
-- The other client files share CadClient: dispatch.lua (911, panic, blips) and plates.lua.

local C = CAD
local EVENT = C.EVENT

CadClient = { me = nil, units = {}, calls = {} }
local K = CadClient

local isOpen = false
local tablet = nil      -- the tablet prop while it's in their hands
local animPlaying = false
local nextReq = 0
local pending = {}      -- [reqId] = callback(ok, result)
local listeners = {}    -- [kind] = { fn, ... }

local TIMEOUT_MS = 10000

-- ------------------------------------------------------------------ messages

-- A notification above the map (and on the tablet when it's open). The game shows 99 characters per
-- piece of text, so longer messages are sent in pieces.
function K.notify(text, tone)
    text = tostring(text or '')
    if text == '' then return end
    BeginTextCommandThefeedPost('STRING')
    for i = 1, #text, 99 do AddTextComponentSubstringPlayerName(text:sub(i, i + 98)) end
    EndTextCommandThefeedPostTicker(tone == 'error', true)
    if isOpen then SendNUIMessage({ type = 'push', kind = 'notify', data = { text = text, tone = tone or 'info' } }) end
end

RegisterNetEvent(EVENT .. 'notify', function(text, tone) K.notify(text, tone) end)

-- ------------------------------------------------------------------ asking the server

-- Sends a request; cb(ok, result) runs with the answer, or with a failure after 10 seconds.
function K.rpc(action, payload, cb)
    nextReq = nextReq + 1
    local id = nextReq
    pending[id] = cb
    TriggerServerEvent(EVENT .. 'rpc', id, action, payload or {})
    SetTimeout(TIMEOUT_MS, function()
        local waiting = pending[id]
        if waiting then
            pending[id] = nil
            waiting(false, "The CAD server didn't answer. Try again.")
        end
    end)
end

RegisterNetEvent(EVENT .. 'reply', function(id, ok, result)
    local cb = pending[id]
    if not cb then return end
    pending[id] = nil
    cb(ok == true, result)
end)

-- ------------------------------------------------------------------ live updates

-- Other client files listen for pushes: K.on('units', fn).
function K.on(kind, fn)
    listeners[kind] = listeners[kind] or {}
    table.insert(listeners[kind], fn)
end

local function emit(kind, data)
    for _, fn in ipairs(listeners[kind] or {}) do fn(data) end
end

function K.setMe(me)
    if type(me) ~= 'table' then return end
    K.me = me
    emit('me', me)
end

-- Keeps the latest board here too, so blips are right even while the tablet is closed.
local function remember(kind, data)
    if kind == 'units' then
        K.units = type(data) == 'table' and data or {}
    elseif kind == 'call' and type(data) == 'table' and data.id then
        K.calls[data.id] = data.status ~= 'closed' and data or nil
    elseif kind == 'me' then
        K.me = type(data) == 'table' and data or K.me
    end
end

RegisterNetEvent(EVENT .. 'push', function(kind, data)
    remember(kind, data)
    emit(kind, data)
    if isOpen then SendNUIMessage({ type = 'push', kind = kind, data = data }) end
end)

-- Sends something to the tablet if it's open (the plate reader uses this).
function K.toTablet(kind, data)
    if isOpen then SendNUIMessage({ type = 'push', kind = kind, data = data }) end
end

-- ------------------------------------------------------------------ the tablet in their hands

local function loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local stop = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < stop do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local stop = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < stop do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function stopTablet()
    local cfg = Config.TabletProp
    if tablet then
        if DoesEntityExist(tablet) then DeleteEntity(tablet) end
        tablet = nil
    end
    if animPlaying and cfg and cfg.anim then
        StopAnimTask(PlayerPedId(), cfg.anim.dict, cfg.anim.clip, 1.0)
    end
    animPlaying = false
end
K.stopTablet = stopTablet

local function startTablet()
    local cfg = Config.TabletProp
    if not cfg then return end
    CreateThread(function()
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
        local hash = loadModel(cfg.model)
        local dictLoaded = cfg.anim and loadDict(cfg.anim.dict)
        -- Closed while the model loaded: nothing to show.
        if not isOpen or tablet then return end
        if hash then
            local c = GetEntityCoords(ped)
            tablet = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
            AttachEntityToEntity(tablet, ped, GetPedBoneIndex(ped, cfg.bone), cfg.offset[1], cfg.offset[2], cfg.offset[3],
                cfg.rotation[1], cfg.rotation[2], cfg.rotation[3], true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(hash)
        end
        if dictLoaded then
            TaskPlayAnim(ped, cfg.anim.dict, cfg.anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
            animPlaying = true
        end
        -- Put away when they die or get into a vehicle with the tablet still open.
        while isOpen and (tablet or animPlaying) do
            Wait(250)
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then stopTablet() end
        end
    end)
end

-- ------------------------------------------------------------------ opening and closing

function K.isOpen() return isOpen end

-- Opens the tablet, on a page if given ('civilian', 'people', ...). Open already: just changes page.
-- Opens the tablet (on a page, with that page's params, e.g. K.open('vehicles', { query = 'ABC123' })).
function K.open(page, params)
    if isOpen then
        SendNUIMessage({ type = 'open', page = page, params = params })
        return
    end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', page = page, params = params })
    TriggerServerEvent(EVENT .. 'watch', true)
    startTablet()
end

function K.close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
    TriggerServerEvent(EVENT .. 'watch', false)
    stopTablet()
end

function K.toggle(page)
    if isOpen then K.close() else K.open(page) end
end

RegisterCommand(Config.Command, function() K.toggle() end, false)
RegisterCommand(Config.CivilianCommand, function() K.open('civilian') end, false)
RegisterKeyMapping(Config.Command, 'Open or close the CAD tablet', 'keyboard', Config.Keys.open or '')

-- ------------------------------------------------------------------ the tablet's requests

-- Answers that change who you are on duty as, or what's on the board, are kept here too.
local function learnFrom(action, result)
    if type(result) ~= 'table' then return end
    if action == 'session' then
        K.setMe(result.me)
    elseif action == 'unit.signOn' or action == 'unit.signOff' then
        K.setMe(result)
    elseif action == 'unit.status' and K.me and K.me.unit and result.id == K.me.unit.id then
        K.me.unit = result
        K.setMe(K.me)
    elseif action == 'unit.list' then
        K.units = result
        emit('units', result)
    elseif action == 'call.list' then
        K.calls = {}
        for _, call in ipairs(result) do
            if call.status ~= 'closed' then K.calls[call.id] = call end
        end
        emit('calls', K.calls)
    end
end

RegisterNUICallback('rpc', function(data, cb)
    if type(data) ~= 'table' or type(data.action) ~= 'string' then return cb({ ok = false, error = 'That request was broken.' }) end
    local payload = type(data.payload) == 'table' and data.payload or {}
    K.rpc(data.action, payload, function(ok, result)
        if ok then
            learnFrom(data.action, result)
            cb({ ok = true, result = result })
        else
            cb({ ok = false, error = tostring(result) })
        end
    end)
end)

RegisterNUICallback('close', function(_, cb)
    K.close()
    cb({})
end)

RegisterNUICallback('waypoint', function(data, cb)
    local x, y = tonumber(type(data) == 'table' and data.x), tonumber(type(data) == 'table' and data.y)
    if x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
        K.notify('GPS set.', 'info')
    end
    cb({})
end)

RegisterNUICallback('notify', function(data, cb)
    if type(data) == 'table' then K.notify(data.text, data.tone) end
    cb({})
end)

RegisterNUICallback('panic', function(_, cb)
    if K.panic then K.panic() end
    cb({})
end)

-- ------------------------------------------------------------------ for other scripts

exports('OpenCAD', function(page) K.open(type(page) == 'string' and page or nil) end)
exports('CloseCAD', function() K.close() end)
exports('IsOpen', function() return isOpen end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    isOpen = false
    stopTablet()
end)
