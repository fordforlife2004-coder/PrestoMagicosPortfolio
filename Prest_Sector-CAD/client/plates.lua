-- The plate reader: /plate runs the vehicle in front of you through the CAD. With
-- Config.PlateReader.auto, police on duty in a vehicle have the plates ahead read for them, and only
-- hear about hits (stolen, BOLO, expired papers, an owner with a warrant).

local C = CAD
local K = CadClient
local R = Config.PlateReader or {}

local lastSeen = {} -- [plateKey] = game time it was last run by the automatic reader

-- The vehicle in front of the player: straight ahead of their car, or within 8 m in front on foot.
function K.vehicleAhead()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        local from = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 2.5, 0.3)
        local to = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (R.distance or 30.0) + 0.0, 0.3)
        local ray = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 2.0, 10, vehicle, 7)
        for _ = 1, 20 do
            local state, hit, _, _, entity = GetShapeTestResult(ray)
            if state ~= 1 then
                if hit == 1 and entity and entity ~= 0 and GetEntityType(entity) == 2 then return entity end
                return nil
            end
            Wait(0)
        end
        return nil
    end
    local pos = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local best, bestDist = nil, 8.0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local vp = GetEntityCoords(v)
        local dx, dy, dz = vp.x - pos.x, vp.y - pos.y, vp.z - pos.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist <= bestDist and dx * fwd.x + dy * fwd.y > 0 then best, bestDist = v, dist end
    end
    return best
end

-- Alerts that matter on a random car: everything except "not in the CAD" and "no owner".
local function hits(result)
    local out = {}
    for _, a in ipairs(result.alerts or {}) do
        if a.text ~= 'No record of this plate.' and a.text ~= 'No registered owner.' then out[#out + 1] = a end
    end
    return out
end

local function show(result, alerts)
    local v = result.vehicle
    local head = ('Plate %s'):format(result.plate)
    if v then
        head = head .. (': %s %s'):format(v.color or '', v.model or ''):gsub('%s+$', '')
        if result.owner then head = head .. (' - owner %s %s'):format(result.owner.first, result.owner.last) end
    end
    K.notify(head, #alerts > 0 and 'warning' or 'info')
    for _, a in ipairs(alerts) do K.notify(a.text, a.tone) end
end

-- Runs the plate ahead. auto = from the automatic reader (quiet unless there's a hit).
function K.runPlate(auto)
    local vehicle = K.vehicleAhead()
    if not vehicle then
        if not auto then K.notify('There is no vehicle in front of you.', 'error') end
        return
    end
    local plate = (GetVehicleNumberPlateText(vehicle) or ''):match('^%s*(.-)%s*$')
    local key = C.plateKey(plate)
    if not key then return end
    if auto then
        local last = lastSeen[key]
        if last and GetGameTimer() - last < (R.repeatMinutes or 5) * 60000 then return end
        lastSeen[key] = GetGameTimer()
    end
    K.rpc('plate.check', { plate = plate }, function(ok, result)
        if not ok then
            if not auto then K.notify(result, 'error') end
            return
        end
        local alerts = auto and hits(result) or (result.alerts or {})
        if auto and #alerts == 0 then return end
        show(result, alerts)
        K.toTablet('plate', result)
    end)
end

if R.command and R.command ~= '' then
    RegisterCommand(R.command, function() K.runPlate(false) end, false)
    RegisterKeyMapping(R.command, 'CAD: run the plate in front of you', 'keyboard', Config.Keys.plate or '')
end

-- The automatic reader, for police on duty in a vehicle.
CreateThread(function()
    while true do
        Wait(math.max(1, tonumber(R.autoSeconds) or 2) * 1000)
        local unit = K.me and K.me.unit
        if R.auto and unit and unit.role == 'police' and IsPedInAnyVehicle(PlayerPedId(), false) then
            K.runPlate(true)
        end
    end
end)
