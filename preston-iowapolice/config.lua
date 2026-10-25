-- Preston Iowa Police v2 settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- Who can spawn and style police vehicles. Grant it to your police players in server.cfg:
--   add_ace group.police iowapolice.use allow
--   add_principal identifier.license:THEIR_LICENSE group.police
-- Set to '' to let everyone use it (not recommended: anyone could spawn police cars).
Config.AcePermission = 'iowapolice.use'

-- Seconds between spawns, and whether a player's last spawned car is removed when they spawn
-- another or leave the server.
Config.CooldownSeconds = 15
Config.DeletePreviousVehicle = true

-- Departments. Each one gets its own spawn command (/isp, /sheriff) and can be applied to the car
-- you're driving with /iowaskin <department>.
--   model       the spawn name (use your add-on Tahoe's name here if you have one)
--   vehicleType 'automobile' for cars and SUVs, or 'bike', 'boat', 'heli' or 'plane'. It must match the
--               model (the type in its vehicles.meta); the game checks this before spawning.
--   plate       plate prefix of 1 to 3 letters; the unit number goes after it, like "ISP 101"
--   colors      { primary, secondary } paint numbers, or nil to keep the model's own paint
--   pearl/wheels  pearlescent and wheel paint numbers (optional)
--   plateStyle  0 blue/white, 1 yellow/black, 2 yellow/blue, 3 blue/white 2, 4 blue/white 3, 5 Yankton
--   livery      livery number (1 = first), or nil to keep the model's own
--   extras      'all' turns on every extra the vehicle has, or a list like { [1] = true, [2] = false }
Config.Departments = {
    isp = {
        command = 'isp',
        label = 'Iowa State Patrol',
        model = 'police3',
        vehicleType = 'automobile',
        plate = 'ISP',
        colors = { 101, 0 }, -- tan body, black trim
        pearl = 37,          -- gold
        wheels = 0,
        plateStyle = 4,
        livery = nil,
        extras = 'all',
    },
    sheriff = {
        command = 'sheriff',
        label = 'County Sheriff',
        model = 'sheriff2',
        vehicleType = 'automobile',
        plate = 'SO',
        colors = nil,
        plateStyle = 4,
        livery = nil,
        extras = 'all',
    },
}

-- The department /iowaskin uses when none is typed.
Config.DefaultDepartment = 'isp'
