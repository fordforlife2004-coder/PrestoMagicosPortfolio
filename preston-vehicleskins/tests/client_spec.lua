-- Runs client/main.lua in a small fake game, to check what each approved change does to a vehicle.
-- Run from the resource folder with any Lua 5.3+:  lua tests/client_spec.lua

local t = dofile('tests/fake_server.lua').runner() -- only for its test runner; the game functions below replace its server ones

local PED, CAR = 1, 50
local commands, netHandlers, toServer, notes = {}, {}, {}, {}
local car

local function newCar(opts)
    opts = opts or {}
    return {
        classicLiveries = opts.classicLiveries or -1, livery = -1,
        modLiveries = opts.modLiveries or 0, modKit = -1, mods = {}, toggles = {},
        extras = opts.extras or {}, noAutoRepair = false, colours = nil, customCleared = 0, plate = 'XYZ',
        driver = PED, networked = true, controlled = true, modKits = opts.modKits or 1,
        playerInside = opts.playerInside ~= false, arrived = opts.arrived ~= false,
    }
end

function RegisterCommand(name, fn) commands[name] = fn end
function RegisterNetEvent(name, fn) netHandlers[name] = fn end
function TriggerServerEvent(name, ...) toServer[#toServer + 1] = { name = name, args = { ... } } end
function TriggerEvent() end
function CreateThread() end
function Wait() end
function BeginTextCommandThefeedPost() end
function AddTextComponentSubstringPlayerName(text) notes[#notes + 1] = text end
function EndTextCommandThefeedPostTicker() end
function GetHashKey(name) return 'hash:' .. name end

function PlayerPedId() return PED end
function GetVehiclePedIsIn() return (car and car.playerInside) and CAR or 0 end
function SetPedIntoVehicle(_, v) if v == CAR then car.playerInside = true end end
function GetPedInVehicleSeat(_, seat) return seat == -1 and car.driver or 0 end
function DoesEntityExist(v) return v == CAR and car ~= nil end
function NetworkDoesEntityExistWithNetworkId(id) return id == CAR and car ~= nil and car.arrived end
function NetToVeh(id) return id == CAR and CAR or 0 end
function GetNumModKits() return car.modKits end
function IsToggleModOn(_, modType) return car.toggles[modType] == true end
function NetworkHasControlOfEntity() return car.controlled end
function NetworkRequestControlOfEntity() end

function SetVehicleModKit(_, kit) car.modKit = kit end
function GetVehicleLiveryCount() return car.classicLiveries end
function GetVehicleLivery() return car.livery end
function SetVehicleLivery(_, index) car.livery = index end
function GetNumVehicleMods(_, modType) -- the game reports 0 until a mod kit is set
    if car.modKit ~= 0 then return 0 end
    if modType == 48 then return car.modLiveries end
    return 4
end
function GetVehicleMod(_, modType) return car.mods[modType] or -1 end
function SetVehicleMod(_, modType, index) car.mods[modType] = index end
function ToggleVehicleMod(_, modType, on) car.toggles[modType] = on end
function DoesExtraExist(_, id) return car.extras[id] ~= nil end
function IsVehicleExtraTurnedOn(_, id) return car.extras[id] == true end
function SetVehicleExtra(_, id, disable) car.extras[id] = not disable end
function SetVehicleAutoRepairDisabled(_, value) car.noAutoRepair = value end
function ClearVehicleCustomPrimaryColour() car.customCleared = car.customCleared + 1 end
function ClearVehicleCustomSecondaryColour() car.customCleared = car.customCleared + 1 end
function SetVehicleColours(_, primary, secondary) car.colours = { primary, secondary } end
function SetVehicleNumberPlateText(_, text) car.plate = text end

dofile('config.lua')
dofile('shared/vehicle_types.lua')
dofile('shared/skins.lua')
dofile('client/main.lua')

local function serverApproves(action, data)
    data.netId = CAR
    netHandlers['preston-skins:apply'](action, data)
    return notes[#notes]
end

t.test('classic liveries are set by number (1 = first)', function()
    car = newCar({ classicLiveries = 4 })
    t.eq(serverApproves('livery', { number = 2 }), 'Livery 2 of 4.')
    t.eq(car.livery, 1, "the game counts from 0")
    t.eq(serverApproves('livery', { number = 9 }), 'This vehicle has 4 liveries. Pick 1 to 4.')
end)

t.test('mod-kit liveries work too (the mod kit is set first)', function()
    car = newCar({ modLiveries = 6 })
    t.eq(serverApproves('livery', { number = 6 }), 'Livery 6 of 6.')
    t.eq(car.mods[48], 5)
end)

t.test('random livery on a vehicle with none says so instead of erroring', function()
    car = newCar()
    t.eq(serverApproves('randomlivery', {}), 'This vehicle has no liveries.')
    car = newCar({ classicLiveries = 3 })
    car.livery = 0
    for _ = 1, 20 do
        serverApproves('randomlivery', {})
        t.eq(car.livery >= 0 and car.livery <= 2, true)
    end
end)

t.test('extras toggle without repairing the vehicle', function()
    car = newCar({ extras = { [1] = true, [3] = false } })
    t.eq(serverApproves('extra', { number = 1 }), 'Extra 1 off.')
    t.eq(car.extras[1], false)
    t.eq(car.noAutoRepair, true, 'auto repair switched off first')
    t.eq(serverApproves('extra', { number = 3 }), 'Extra 3 on.')
    t.eq(car.extras[3], true)
    t.eq(serverApproves('extra', { number = 2 }), 'This vehicle has no extra 2. See /extras.')
end)

t.test('paint clears custom colors so the new paint shows', function()
    car = newCar()
    serverApproves('color', { primary = 27, secondary = 0 })
    t.eq(car.colours[1], 27)
    t.eq(car.colours[2], 0)
    t.eq(car.customCleared, 2)
end)

t.test('tune upgrades performance parts only, and switches turbo on properly', function()
    car = newCar()
    t.eq(serverApproves('tune', {}), 'Tuned 5 parts to their best level, plus turbo.')
    for _, mod in ipairs(Config.TuneMods) do t.eq(car.mods[mod], 3, 'mod ' .. mod) end
    t.eq(car.mods[0], nil, 'no spoilers or bumpers changed')
    t.eq(car.mods[18], nil, 'turbo is not set as a level...')
    t.eq(car.toggles[18], true, '...it is toggled on')
end)

t.test("/tune on a vehicle with no mod kit says it can't be tuned", function()
    car = newCar({ modKits = 0 })
    t.eq(serverApproves('tune', {}), "This vehicle can't be tuned.")
    t.eq(car.toggles[18], nil)
end)

t.test('/spawnskin: get in once the car arrives, then set the livery', function()
    car = newCar({ classicLiveries = 4, playerInside = false })
    netHandlers['preston-skins:seat'](CAR, 'police3', 2)
    t.eq(car.playerInside, true)
    t.eq(car.livery, 1)
    t.eq(notes[#notes], 'Spawned police3. Livery 2 of 4.')
    car = newCar({ playerInside = false })
    netHandlers['preston-skins:seat'](CAR, 'adder')
    t.eq(notes[#notes], 'Spawned adder.')
end)

t.test("/spawnskin: a car that never arrives is reported to the server so it's removed", function()
    car = newCar({ playerInside = false, arrived = false })
    netHandlers['preston-skins:seat'](CAR, 'addoncar')
    t.eq(car.playerInside, false)
    t.eq(toServer[#toServer].name, 'preston-skins:seatFailed')
    t.eq(toServer[#toServer].args[1], CAR)
    t.contains(notes[#notes], "addoncar didn't arrive")
end)

t.test('long notifications are sent in pieces the game accepts', function()
    car = newCar()
    for id = 1, 20 do car.extras[id] = id % 2 == 0 end
    local before = #notes
    commands.extras()
    t.eq(#notes - before >= 2, true, 'more than one piece')
    for i = before + 1, #notes do t.eq(#notes[i] <= 99, true, 'piece ' .. i) end
end)

t.test('plates', function()
    car = newCar()
    t.eq(serverApproves('plate', { text = 'ISP 101' }), 'Plate set to ISP 101.')
    t.eq(car.plate, 'ISP 101')
end)

t.test('if the vehicle cannot be controlled, nothing changes', function()
    car = newCar({ classicLiveries = 4 })
    car.controlled = false
    t.eq(serverApproves('livery', { number = 2 }), "Couldn't take control of the vehicle. Try again.")
    t.eq(car.livery, -1)
end)

t.test('commands ask the server, and /liveries and /extras just read the vehicle', function()
    car = newCar({ classicLiveries = 5, extras = { [1] = true, [2] = false } })
    car.livery = 2
    commands.liveries()
    t.eq(notes[#notes], '5 liveries, on number 3. Use /setlivery 1-5 or /randomlivery.')
    commands.extras()
    t.eq(notes[#notes], 'Extras: 1 on, 2 off. Toggle with /extra number.')
    commands.setlivery(nil, { '4' })
    t.eq(toServer[#toServer].args[1], 'livery')
    t.eq(toServer[#toServer].args[2][1], '4')
    car.driver = 99
    local sent = #toServer
    commands.tune()
    t.eq(#toServer, sent, 'not sent when you are not the driver')
    t.eq(notes[#notes], 'Get in the driver seat of a vehicle first.')
end)

t.finish()
