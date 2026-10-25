-- Preston Vehicle Spawn v2 settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- Leave empty so everyone can use /car, or set an ACE to limit it, for example 'vehiclespawn.use'
-- with this in server.cfg:  add_ace group.vip vehiclespawn.use allow
Config.AcePermission = ''

-- Players with this ACE skip the cooldown, can spawn blocked models and can /dv any vehicle.
--   add_ace group.admin vehiclespawn.staff allow
Config.StaffAce = 'vehiclespawn.staff'

-- Seconds a player waits between spawns.
Config.CooldownSeconds = 10

-- Delete a player's last spawned vehicle when they spawn another, and when they leave the server.
Config.DeletePreviousVehicle = true
Config.DeleteOnLeave = true

-- Plate text for spawned vehicles: up to 8 letters, numbers and spaces. Empty keeps a random plate.
Config.Plate = 'PRESTON'

-- How close (meters) a vehicle must be for /dv when you aren't sitting in it.
Config.DeleteDistance = 6.0

-- The vehicle type of add-on vehicles that aren't cars: 'bike', 'boat', 'heli', 'plane', 'submarine'
-- or 'trailer' (it must match the type in the vehicle's vehicles.meta). Built-in vehicles are already known.
-- Example: Config.VehicleTypes = { polmav2 = 'heli', policebike = 'bike' }
Config.VehicleTypes = {}

-- Models only staff can spawn: a starting list of armed and griefing vehicles. Add or remove to taste.
-- Matched by the game's model hash, so another name for the same model is caught too.
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
