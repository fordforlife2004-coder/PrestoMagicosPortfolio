-- Prest_Sector Radar settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- ------------------------------------------------------------------ who can use it

-- Anyone with this ACE can use the radar and the plate reader. Grant it in server.cfg, for example:
--   add_ace group.police radar.use allow
--   add_principal identifier.license:THEIR_LICENSE group.police
-- Police on duty in Prest_Sector-CAD can use it too (cadRoles), with no ACE needed.
-- everyone = true lets every player use the radar, its plate checks and /hotlist: handy on a small
-- server or for testing.
Config.Access = {
    ace = 'radar.use',
    cadRoles = { 'police' },
    everyone = false,
}

-- Which vehicles have a radar: every emergency vehicle (police cars, ambulances, fire trucks), plus any
-- models listed here (spawn names, for example 'police4' or an add-on car). Only the driver and the
-- front passenger see it.
Config.Vehicles = {
    emergencyClass = true,
    models = {},
}

-- ------------------------------------------------------------------ the speed radar

Config.Units = 'mph' -- 'mph' or 'kmh'

Config.Radar = {
    range = 150.0,    -- how far the antennas reach, in meters
    angle = 6.0,      -- how wide the beam spreads, in degrees either side of straight ahead (or behind)
    nearWidth = 3.0,  -- the beam's half-width right at the car, in meters, so a car just ahead still counts
    height = 10.0,    -- targets more than this many meters above or below are ignored (bridges)
    minSpeed = 3,     -- slower targets aren't shown (in Config.Units)
    fastLimit = 75,   -- the fast limit a new officer starts with (in Config.Units); each officer can change theirs
    updateMs = 200,   -- how often the radar reads the road
}

-- ------------------------------------------------------------------ the plate reader

Config.PlateReader = {
    range = 40.0,         -- how far the cameras read plates, in meters
    angle = 14.0,         -- the cameras' spread, in degrees either side
    repeatSeconds = 300,  -- a plate already checked isn't checked again for this long
    checkCad = true,      -- check plates against Prest_Sector-CAD's records when it's running
    notices = true,       -- show lesser problems (expired registration or insurance) in amber, with no alarm
    lockOnHit = true,     -- freeze the camera on a hit, so the plate stays on screen
    hitCall = false,      -- also put a call on the CAD's dispatch board for every hit
    hitCallCode = '10-60',-- the CAD call code for that call
}

-- The built-in hotlist: plates officers add with /hotlist, checked by every plate reader. It works
-- with or without the CAD. Entries end on their own after `hours`.
Config.Hotlist = {
    hours = 12,
    max = 200,
}

-- ------------------------------------------------------------------ commands and keys

Config.Command = 'radar'              -- /radar shows or hides the radar
Config.RemoteCommand = 'radarremote'  -- /radarremote opens the remote (settings, locks, moving the display)
Config.HotlistCommand = 'hotlist'     -- /hotlist add PLATE reason, /hotlist remove PLATE, /hotlist

-- Default keys (each player can change them in Settings > Key Bindings > FiveM). '' means no default.
Config.Keys = {
    toggle = '',
    remote = '',
    lockFront = 'NUMPAD8',
    lockRear = 'NUMPAD2',
    lockPlates = 'NUMPAD5',
    reset = 'NUMPAD0',
    openCad = 'NUMPAD9',
}

-- ------------------------------------------------------------------ limits on the server

Config.Server = {
    lookupsPerMinute = 60, -- plate checks one player can ask for in a minute
    cacheSeconds = 20,     -- a plate checked moments ago is answered from memory
    recheckSeconds = 10,   -- how often the server looks again at who may use the radar
}
