-- Preston Vehicle Skins v2 settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- ACE needed for each command. Empty means everyone can use it. Custom plates and performance
-- tuning are limited by default; grant them in server.cfg, for example:
--   add_ace group.vip vehicleskins.plate allow
--   add_ace group.vip vehicleskins.tune allow
-- ("add_ace group.admin vehicleskins allow" grants all of them.)
Config.Permissions = {
    spawnskin = '',
    livery = '',
    extra = '',
    color = '',
    plate = 'vehicleskins.plate',
    tune = 'vehicleskins.tune',
}

-- /spawnskin: seconds between spawns, and whether the last spawned car is removed.
Config.SpawnCooldownSeconds = 10
Config.DeletePreviousVehicle = true

-- Plate text for vehicles from /spawnskin (empty keeps a random plate).
Config.SpawnPlate = 'PRESTON'

-- /tune sets these to their best level: 11 engine, 12 brakes, 13 transmission, 15 suspension,
-- 16 armor. Turbo is switched on separately. Remove 16 if armor shouldn't be part of it.
Config.TuneMods = { 11, 12, 13, 15, 16 }
Config.TuneTurbo = true

-- The vehicle type of add-on vehicles that aren't cars: 'bike', 'boat', 'heli', 'plane', 'submarine'
-- or 'trailer' (it must match the type in the vehicle's vehicles.meta). Built-in vehicles are already known.
Config.VehicleTypes = {}

-- Models /spawnskin won't spawn: a starting list of armed and griefing vehicles (the same list as
-- Preston Vehicle Spawn). Matched by the game's model hash, so another name for the same model is caught too.
Config.BlockedModels = {
    -- tanks and armored
    'rhino', 'khanjali', 'apc', 'halftrack', 'minitank', 'insurgent', 'insurgent3', 'technical', 'technical2', 'technical3',
    'nightshark', 'caracara', 'limo2', 'boxville5', 'barrage', 'menacer', 'chernobog', 'trailersmall2', 'tampa3', 'dune3',
    'jb7002', 'ruiner2', 'vigilante', 'scramjet', 'deluxo', 'toreador', 'stromberg', 'ignus2', 'zr380', 'zr3802', 'zr3803',
    -- Arena War weapon vehicles
    'bruiser', 'bruiser2', 'bruiser3', 'brutus', 'brutus2', 'brutus3', 'cerberus', 'cerberus2', 'cerberus3',
    'deathbike', 'deathbike2', 'deathbike3', 'dominator4', 'dominator5', 'dominator6', 'impaler2', 'impaler3', 'impaler4',
    'imperator', 'imperator2', 'imperator3', 'issi4', 'issi5', 'issi6', 'monster3', 'monster4', 'monster5',
    'scarab', 'scarab2', 'scarab3', 'slamvan4', 'slamvan5', 'slamvan6',
    -- armed aircraft and boats
    'hydra', 'lazer', 'strikeforce', 'starling', 'mogul', 'bombushka', 'volatol', 'molotok', 'nokota', 'pyro', 'rogue',
    'tula', 'raiju', 'alkonost', 'avenger', 'avenger2', 'avenger3', 'avenger4',
    'hunter', 'savage', 'akula', 'annihilator', 'annihilator2', 'buzzard', 'valkyrie', 'valkyrie2', 'seasparrow', 'conada2',
    'patrolboat', 'dinghy5', 'kosatka',
    -- flying bikes and jetpacks
    'oppressor', 'oppressor2', 'thruster',
    -- huge aircraft (griefing)
    'cargoplane', 'cargoplane2', 'jet', 'titan', 'blimp',
}
