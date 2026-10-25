-- Preston ELS v2 settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- Default keys. Players can change them in Settings > Key Bindings > FiveM.
Config.Keys = {
    lights = 'L',      -- emergency lights on/off (same key as v1)
    siren = 'LMENU',   -- siren on/off (Left Alt)
    tone = 'R',        -- next siren tone
    pattern = 'K',     -- next light pattern (vehicles with an extras light bar)
    horn = 'E',        -- air horn while held
}

-- Game controls switched off while driving an ELS vehicle, so the keys above don't also do the
-- game's own thing: 80 = cinematic camera (R), 86 = horn and the game's own siren toggle (E).
Config.DisabledControls = { 80, 86 }

-- ELS works on every emergency vehicle (police, ambulance, fire) plus anything in Config.Vehicles.
-- Set to false to only allow the vehicles listed in Config.Vehicles.
Config.AllEmergencyVehicles = true

-- Leave empty so anyone driving an emergency vehicle can use ELS, or set an ACE to limit it to
-- whitelisted players, for example 'els.use' with this in server.cfg:
--   add_ace group.police els.use allow
Config.AcePermission = ''

-- Turn the siren (not the lights) off when the driver gets out.
Config.SirenOffOnExit = true

-- Show the control panel while driving an ELS vehicle. Players can hide it with /elshud.
-- Position: 'bottom-right', 'bottom-center' or 'top-right'.
Config.ShowHud = true
Config.HudPosition = 'bottom-right'

-- A short click when the driver changes lights, siren, tone or pattern.
Config.ClickSounds = true

-- How far away (meters) other players hear sirens and see extras light bars flash.
Config.SyncDistance = 250.0

-- The air horn sound.
Config.Horn = 'SIRENS_AIRHORN'

-- Siren tones for vehicles that don't list their own.
Config.Tones = {
    { label = 'Wail', sound = 'VEHICLES_HORNS_SIREN_1' },
    { label = 'Yelp', sound = 'VEHICLES_HORNS_SIREN_2' },
    { label = 'Priority', sound = 'VEHICLES_HORNS_POLICE_WARNING' },
}

-- Light patterns for vehicles whose light bar is made of extras. Each frame lists which of the
-- vehicle's light slots are on (slot 1 = the first extra in that vehicle's "extras" list), and each
-- frame is shown for "step" milliseconds.
Config.Patterns = {
    { label = 'Alternate', step = 200, frames = { { 1 }, {}, { 2 }, {} } },
    { label = 'Fast strobe', step = 80, frames = { { 1 }, {}, { 2 }, {} } },
    { label = 'Solid flash', step = 300, frames = { { 1, 2 }, {} } },
    { label = 'Double flash', step = 70, frames = { { 1 }, {}, { 1 }, {}, { 2 }, {}, { 2 }, {} } },
}

-- Settings for specific vehicles, by spawn name.
--   lights = 'native'  uses the vehicle's own built-in emergency lights (the game keeps them in sync).
--   lights = 'extras'  flashes the listed extras with Config.Patterns, for add-on cars whose light bar
--                      is made of extras. nativeToo = true also turns on the built-in lights.
--   tones = { ... }    a list like Config.Tones, for vehicles that should sound different.
Config.Vehicles = {
    police3 = { lights = 'native' }, -- the Iowa State Patrol car from the Iowa Police script

    ambulance = {
        lights = 'native',
        tones = {
            { label = 'Wail', sound = 'VEHICLES_HORNS_AMBULANCE_WARNING' },
            { label = 'Yelp', sound = 'VEHICLES_HORNS_SIREN_2' },
        },
    },

    firetruk = {
        lights = 'native',
        tones = {
            { label = 'Fire horn', sound = 'VEHICLES_HORNS_FIRETRUCK_WARNING' },
            { label = 'Wail', sound = 'RESIDENT_VEHICLES_SIREN_FIRETRUCK_WAIL_01' },
            { label = 'Yelp', sound = 'RESIDENT_VEHICLES_SIREN_FIRETRUCK_QUICK_01' },
        },
    },

    -- An add-on car whose light bar is extras 1 (left) and 2 (right):
    -- iowatahoe = { lights = 'extras', extras = { 1, 2 } },
}
