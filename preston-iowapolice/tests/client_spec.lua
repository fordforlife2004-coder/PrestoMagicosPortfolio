-- Runs client/main.lua in a small fake game, to check what styling does to a vehicle.
-- Run from the resource folder with any Lua 5.3+:  lua tests/client_spec.lua

local t = dofile('tests/fake_server.lua').runner() -- only for its test runner; the game functions below replace its server ones

local CAR = 50
local commands, netHandlers, toServer, notes = {}, {}, {}, {}
local car
local installed = { police3 = true, sheriff2 = true }

local function newCar(opts)
    opts = opts or {}
    return {
        extras = opts.extras or {}, colours = { 5, 5 }, extraColours = { 9, 9 }, customCleared = 0,
        plateStyle = 0, liveryCount = opts.liveryCount or -1, livery = -1, modKit = -1, mods = {},
        modLiveries = opts.modLiveries or 0, dirt = 10.0, noAutoRepair = false, controlled = true,
        arrived = opts.arrived ~= false, playerInside = false,
    }
end
local helis = {}

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
function IsModelInCdimage(hash) return installed[hash:sub(6)] == true end
function IsModelAVehicle() return true end

function IsThisModelAHeli(hash) return helis[hash:sub(6)] == true end
function IsThisModelAPlane() return false end
function IsThisModelABoat() return false end
function IsThisModelAJetski() return false end
function IsThisModelABike() return false end
function IsThisModelABicycle() return false end

function PlayerPedId() return 1 end
function GetVehiclePedIsIn() return (car and car.playerInside) and CAR or 0 end
function SetPedIntoVehicle(_, v) if v == CAR then car.playerInside = true end end
function DoesEntityExist(v) return v == CAR and car ~= nil end
function NetworkDoesEntityExistWithNetworkId(id) return id == CAR and car ~= nil and car.arrived end
function NetToVeh(id) return id == CAR and CAR or 0 end
function NetworkHasControlOfEntity() return car.controlled end
function NetworkRequestControlOfEntity() end

function ClearVehicleCustomPrimaryColour() car.customCleared = car.customCleared + 1 end
function ClearVehicleCustomSecondaryColour() car.customCleared = car.customCleared + 1 end
function SetVehicleColours(_, a, b) car.colours = { a, b } end
function GetVehicleExtraColours() return car.extraColours[1], car.extraColours[2] end
function SetVehicleExtraColours(_, a, b) car.extraColours = { a, b } end
function SetVehicleNumberPlateTextIndex(_, style) car.plateStyle = style end
function GetVehicleLiveryCount() return car.liveryCount end
function SetVehicleLivery(_, index) car.livery = index end
function SetVehicleModKit(_, kit) car.modKit = kit end
function GetNumVehicleMods(_, modType) return (car.modKit == 0 and modType == 48) and car.modLiveries or 0 end
function SetVehicleMod(_, modType, index) car.mods[modType] = index end
function SetVehicleAutoRepairDisabled(_, value) car.noAutoRepair = value end
function DoesExtraExist(_, id) return car.extras[id] ~= nil end
function SetVehicleExtra(_, id, disable) car.extras[id] = not disable end
function SetVehicleDirtLevel(_, level) car.dirt = level end

dofile('config.lua')
dofile('shared/iowa.lua')
dofile('client/main.lua')

t.test('a new car: get in once it arrives, style it, then say so', function()
    car = newCar()
    netHandlers['preston-iowa:dress'](CAR, 'isp', true, 'Iowa State Patrol unit ISP 101 is on the road.')
    t.eq(car.playerInside, true)
    t.eq(car.colours[1], 101)
    t.eq(notes[#notes], 'Iowa State Patrol unit ISP 101 is on the road.')
end)

t.test("a new car that never arrives is reported, so the server removes it", function()
    car = newCar({ arrived = false })
    netHandlers['preston-iowa:dress'](CAR, 'isp', true, 'never shown')
    t.eq(toServer[#toServer].name, 'preston-iowa:seatFailed')
    t.eq(toServer[#toServer].args[1], CAR)
    t.contains(notes[#notes], "didn't arrive")
end)

t.test('ISP look: tan and black, gold pearl, blue plate, every extra on, clean', function()
    car = newCar({ extras = { [1] = false, [2] = false, [5] = true } })
    netHandlers['preston-iowa:dress'](CAR, 'isp', false)
    t.eq(car.colours[1], 101)
    t.eq(car.colours[2], 0)
    t.eq(car.extraColours[1], 37)
    t.eq(car.extraColours[2], 0)
    t.eq(car.plateStyle, 4)
    t.eq(car.extras[1], true)
    t.eq(car.extras[2], true)
    t.eq(car.extras[5], true)
    t.eq(car.extras[0], nil, 'no extra 0 (v1 tried 0 to 12)')
    t.eq(car.noAutoRepair, true, 'turning extras on does not repair damage')
    t.eq(car.dirt, 0.0)
end)

t.test("a department without colors keeps the model's paint", function()
    car = newCar()
    netHandlers['preston-iowa:dress'](CAR, 'sheriff')
    t.eq(car.colours[1], 5)
    t.eq(car.customCleared, 0)
end)

t.test('a listed extras setup only touches the extras it names', function()
    Config.Departments.isp.extras = { [1] = true, [2] = false }
    car = newCar({ extras = { [1] = false, [2] = true, [3] = true } })
    IowaDress(CAR, Config.Departments.isp)
    t.eq(car.extras[1], true)
    t.eq(car.extras[2], false)
    t.eq(car.extras[3], true, 'not in the list, left alone')
    Config.Departments.isp.extras = 'all'
end)

t.test('liveries: classic first, then mod-kit liveries', function()
    local d = { livery = 2 }
    car = newCar({ liveryCount = 3 })
    IowaDress(CAR, d)
    t.eq(car.livery, 1)
    car = newCar({ modLiveries = 4 })
    IowaDress(CAR, d)
    t.eq(car.mods[48], 1)
    car = newCar()
    IowaDress(CAR, d)
    t.eq(car.livery, -1, 'no liveries: nothing changes')
end)

t.test('nothing is styled without control of the vehicle', function()
    car = newCar()
    car.controlled = false
    netHandlers['preston-iowa:dress'](CAR, 'isp')
    t.eq(car.colours[1], 5)
    t.eq(notes[#notes], "Couldn't style the vehicle. Try /iowaskin.")
end)

t.test('spawn commands check the model is installed before asking the server', function()
    commands.isp(nil, { '101' })
    t.eq(toServer[#toServer].name, 'preston-iowa:spawn')
    t.eq(toServer[#toServer].args[1], 'isp')
    t.eq(toServer[#toServer].args[2], '101')
    installed.sheriff2 = nil
    local sent = #toServer
    commands.sheriff(nil, {})
    t.eq(#toServer, sent)
    t.eq(notes[#notes], 'The County Sheriff vehicle (sheriff2) is not installed on this server.')
end)

t.test("a department whose vehicleType doesn't match its model is caught before spawning", function()
    installed.polmav = true
    helis.polmav = true
    Config.Departments.air = { command = 'air', label = 'Air Unit', model = 'polmav', plate = 'AIR' } -- vehicleType missing
    dofile('client/main.lua') -- commands are registered per department when the script loads
    local sent = #toServer
    commands.air(nil, { '1' })
    t.eq(#toServer, sent, 'not sent')
    t.eq(notes[#notes], 'Config problem: polmav is a heli, but the Air Unit department says vehicleType = automobile.')
    Config.Departments.air = nil
end)

t.test('/iowaskin argument order', function()
    commands.iowaskin(nil, { '250' })
    t.eq(toServer[#toServer].args[1], nil)
    t.eq(toServer[#toServer].args[2], '250')
    commands.iowaskin(nil, { 'sheriff', '7' })
    t.eq(toServer[#toServer].args[1], 'sheriff')
    t.eq(toServer[#toServer].args[2], '7')
    commands.iowaskin(nil, { '7', 'sheriff' })
    t.eq(toServer[#toServer].args[1], 'sheriff', 'reversed order works too')
    t.eq(toServer[#toServer].args[2], '7')
    commands.iowaskin(nil, { '99999' })
    t.eq(toServer[#toServer].args[1], nil, 'an out-of-range number is still a unit, so the server explains the range')
    t.eq(toServer[#toServer].args[2], '99999')
end)

t.finish()
