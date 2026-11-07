-- Prest_Sector CAD settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- ------------------------------------------------------------------ who can do what

-- Roles come from ACE permissions. Grant them in server.cfg, for example:
--   add_ace group.police cad.police allow
--   add_ace group.fire cad.fire allow
--   add_ace group.dispatch cad.dispatch allow
--   add_ace group.supervisor cad.supervisor allow
--   add_ace group.judge cad.judge allow
--   add_ace group.admin cad.admin allow
--   add_principal identifier.license:THEIR_LICENSE group.police
-- Everyone is a civilian: they can call 911 and keep their own characters, vehicles and weapons.
Config.Roles = {
    police = 'cad.police',         -- go on duty as police, search records, write reports, request warrants
    fire = 'cad.fire',             -- go on duty as Fire/EMS, see dispatch, look people up, write medical and fire reports
    dispatch = 'cad.dispatch',     -- run the dispatch board: create, assign and close any call
    supervisor = 'cad.supervisor', -- everything police and dispatch can, plus approve reports and warrants, delete records
    judge = 'cad.judge',           -- read records, approve or deny warrants
    admin = 'cad.admin',           -- everything
}

-- On a QBCore, Qbox or ESX server, jobs can give roles too, so you don't need ACEs for them.
-- job name = the roles it gives. Players must be on duty in their job when Config.JobsNeedDuty is true.
Config.Jobs = {
    police = { 'police' },
    sheriff = { 'police' },
    statepolice = { 'police' },
    ambulance = { 'fire' },
    fire = { 'fire' },
    dispatch = { 'dispatch' },
    judge = { 'judge' },
}
Config.JobsNeedDuty = true

-- Use QBCore, Qbox or ESX character names (and the jobs above) when one of them is running.
-- Set to false to always use FiveM player names and ACEs only.
Config.UseFramework = true

-- Police and Fire/EMS units can create calls, edit them and assign other units, not just dispatchers.
-- Set to false on servers with full-time dispatchers.
Config.UnitsCanManageCalls = true

-- Fire/EMS can look people up (name, date of birth, flags, licenses), but not reports or warrants.
Config.FireCanSearchPeople = true

-- ------------------------------------------------------------------ storage

-- 'kvp' keeps everything in the server's own storage: nothing to set up.
-- 'oxmysql' keeps it in your MySQL database (start oxmysql before this script). The table is made
-- for you. Switching later doesn't move what's already saved.
Config.Storage = 'kvp'

-- Closed calls are deleted after this many days (0 keeps them forever). Records are never deleted
-- on their own.
Config.KeepClosedCallsDays = 14

-- ------------------------------------------------------------------ the tablet

Config.Command = 'cad'          -- /cad opens the tablet
Config.CivilianCommand = 'civ'  -- /civ opens it on your civilian records
Config.Keys = {
    open = 'F6',   -- open or close the tablet ('' for no default key)
    panic = '',    -- panic button for units on duty
    plate = '',    -- run the plate of the vehicle in front of you
}
-- Hold a tablet while it's open (not in a vehicle).
Config.TabletProp = { model = 'prop_cs_tablet', bone = 28422, offset = { 0.0, -0.03, 0.0 }, rotation = { 20.0, -90.0, 0.0 },
    anim = { dict = 'amb@world_human_seat_wall_tablet@female@base', clip = 'base' } }

-- ------------------------------------------------------------------ departments and units

-- role: who can sign on with it ('police', 'fire' or 'dispatch'). ace (optional) limits it further.
Config.Departments = {
    { key = 'lspd', label = 'Los Santos Police Department', short = 'LSPD', role = 'police', color = '#3b82f6' },
    { key = 'bcso', label = "Blaine County Sheriff's Office", short = 'BCSO', role = 'police', color = '#a16207' },
    { key = 'sahp', label = 'San Andreas Highway Patrol', short = 'SAHP', role = 'police', color = '#eab308' },
    { key = 'lsfd', label = 'Los Santos Fire Department', short = 'LSFD', role = 'fire', color = '#ef4444' },
    { key = 'ems', label = 'Emergency Medical Services', short = 'EMS', role = 'fire', color = '#f97316' },
    { key = 'comms', label = 'Communications (Dispatch)', short = 'COMMS', role = 'dispatch', color = '#8b5cf6' },
}

-- Unit statuses, in the order the status buttons show. The first is where units start.
Config.Statuses = {
    { key = 'available', code = '10-8', label = 'Available', color = '#22c55e' },
    { key = 'enroute', code = '10-97', label = 'En route', color = '#3b82f6' },
    { key = 'onscene', code = '10-23', label = 'On scene', color = '#a855f7' },
    { key = 'busy', code = '10-6', label = 'Busy', color = '#f59e0b' },
    { key = 'transport', code = '10-15', label = 'Transporting', color = '#06b6d4' },
    { key = 'break', code = '10-7', label = 'Out of service', color = '#64748b' },
}
-- Attaching to a call sets you en route; closing it sets everyone on it available again.
Config.AutoStatus = true

-- How often (seconds) units on duty send where they are, for the unit list and map.
Config.LocationSeconds = 5

-- Map blips for units on duty: other units, and calls.
Config.UnitBlips = true
Config.CallBlips = { sprite = 280, colours = { [1] = 1, [2] = 47, [3] = 5 }, panicSprite = 161 }

-- ------------------------------------------------------------------ calls

-- priority 1 = emergency, 2 = urgent, 3 = routine
Config.Priorities = {
    { level = 1, label = 'P1 Emergency', color = '#ef4444' },
    { level = 2, label = 'P2 Urgent', color = '#f59e0b' },
    { level = 3, label = 'P3 Routine', color = '#22c55e' },
}

-- Who a call is for. 911 calls go to everyone.
Config.Services = {
    { key = 'police', label = 'Police' },
    { key = 'fire', label = 'Fire' },
    { key = 'ems', label = 'EMS' },
    { key = 'all', label = 'All units' },
}

-- Call types dispatch can pick, with the priority and service they start with.
Config.CallCodes = {
    { code = '911', label = '911 call', priority = 2, service = 'all' },
    { code = '311', label = 'Non-emergency call', priority = 3, service = 'police' },
    { code = '10-10', label = 'Fight in progress', priority = 2, service = 'police' },
    { code = '10-16', label = 'Domestic disturbance', priority = 2, service = 'police' },
    { code = '10-31', label = 'Crime in progress', priority = 1, service = 'police' },
    { code = '10-32', label = 'Person with a gun', priority = 1, service = 'police' },
    { code = '10-38', label = 'Traffic stop', priority = 3, service = 'police' },
    { code = '10-50', label = 'Traffic collision', priority = 2, service = 'all' },
    { code = '10-55', label = 'Impaired driver', priority = 2, service = 'police' },
    { code = '10-60', label = 'Suspicious person or vehicle', priority = 3, service = 'police' },
    { code = '10-66', label = 'Shots fired', priority = 1, service = 'police' },
    { code = '10-70', label = 'Fire', priority = 1, service = 'fire' },
    { code = '10-80', label = 'Pursuit', priority = 1, service = 'police' },
    { code = '10-90', label = 'Robbery or alarm', priority = 1, service = 'police' },
    { code = '10-52', label = 'Medical emergency', priority = 1, service = 'ems' },
    { code = '10-99', label = 'Officer needs help (panic)', priority = 1, service = 'police' },
}

-- How a call can end, when it's closed.
Config.Dispositions = {
    'Report taken', 'Arrest made', 'Citation issued', 'Warning given', 'Gone on arrival',
    'Unfounded', 'Handled by caller', 'Transported', 'Cancelled', 'Duplicate call',
}

-- 911 and 311 from any player: /911 <what happened> and /311 <what happened>.
Config.Emergency = {
    command = '911',
    nonEmergencyCommand = '311',
    cooldownSeconds = 30,   -- per caller
    anonymousCommand = '911a', -- an anonymous tip ('' to turn it off)
}

-- The panic button for units on duty: a priority 1 call at your spot, with every unit told.
Config.Panic = { cooldownSeconds = 15, blipSeconds = 120 }

-- Sounds for units on duty: a new call, a call you're put on, and a panic.
Config.Sounds = {
    newCall = { name = 'Event_Message_Purple', set = 'GTAO_FM_Events_Soundset' },
    attached = { name = 'Text_Arrive_Tone', set = 'Phone_SoundSet_Default' },
    panic = { name = 'Lose_1st', set = 'GTAO_FM_Events_Soundset' },
}

-- ------------------------------------------------------------------ the plate reader

-- /plate (or Config.Keys.plate) runs the vehicle in front of you. auto = true also runs the plates
-- ahead of on-duty police every couple of seconds while they drive, and only speaks up on a hit
-- (stolen, BOLO, expired papers, an owner with a warrant).
Config.PlateReader = { command = 'plate', distance = 30.0, auto = false, autoSeconds = 2, repeatMinutes = 5 }

-- ------------------------------------------------------------------ records

Config.Genders = { 'Male', 'Female', 'Other' }

-- Licenses on a person, and the states each can be in.
Config.Licenses = {
    { key = 'driver', label = "Driver's license" },
    { key = 'commercial', label = 'Commercial (CDL)' },
    { key = 'motorcycle', label = 'Motorcycle' },
    { key = 'weapon', label = 'Weapon permit' },
    { key = 'pilot', label = 'Pilot' },
    { key = 'hunting', label = 'Hunting' },
    { key = 'fishing', label = 'Fishing' },
}
Config.LicenseStates = {
    { key = 'valid', label = 'Valid', color = '#22c55e' },
    { key = 'suspended', label = 'Suspended', color = '#f59e0b' },
    { key = 'revoked', label = 'Revoked', color = '#ef4444' },
    { key = 'expired', label = 'Expired', color = '#f97316' },
    { key = 'none', label = 'None', color = '#64748b' },
}

-- Flags officers can put on a person. They show as badges on every search.
Config.PersonFlags = {
    { key = 'armed', label = 'Armed and dangerous', color = '#ef4444' },
    { key = 'officer_safety', label = 'Officer safety caution', color = '#ef4444' },
    { key = 'gang', label = 'Gang affiliation', color = '#a855f7' },
    { key = 'mental', label = 'Mental health', color = '#06b6d4' },
    { key = 'probation', label = 'On probation', color = '#f59e0b' },
    { key = 'parole', label = 'On parole', color = '#f59e0b' },
    { key = 'missing', label = 'Missing person', color = '#3b82f6' },
}

Config.RegistrationStates = {
    { key = 'valid', label = 'Valid', color = '#22c55e' },
    { key = 'expired', label = 'Expired', color = '#f97316' },
    { key = 'suspended', label = 'Suspended', color = '#ef4444' },
    { key = 'none', label = 'Unregistered', color = '#64748b' },
}
Config.InsuranceStates = {
    { key = 'valid', label = 'Insured', color = '#22c55e' },
    { key = 'expired', label = 'Expired', color = '#f97316' },
    { key = 'none', label = 'Uninsured', color = '#ef4444' },
}
Config.VehicleFlags = {
    { key = 'stolen', label = 'Stolen', color = '#ef4444' },
    { key = 'impounded', label = 'Impounded', color = '#f59e0b' },
    { key = 'flagged', label = 'Flagged for stop', color = '#a855f7' },
}
Config.WeaponStates = {
    { key = 'registered', label = 'Registered', color = '#22c55e' },
    { key = 'stolen', label = 'Stolen', color = '#ef4444' },
    { key = 'seized', label = 'Seized', color = '#f59e0b' },
}

-- Report types, and which roles can write each.
Config.ReportTypes = {
    { key = 'incident', label = 'Incident report', roles = { 'police', 'dispatch' } },
    { key = 'arrest', label = 'Arrest report', roles = { 'police' }, charges = true },
    { key = 'citation', label = 'Citation', roles = { 'police' }, charges = true },
    { key = 'warning', label = 'Written warning', roles = { 'police' } },
    { key = 'field', label = 'Field interview', roles = { 'police' } },
    { key = 'medical', label = 'Patient care report', roles = { 'fire' } },
    { key = 'fire', label = 'Fire incident report', roles = { 'fire' } },
}

-- Warrants a police officer asks for wait for a judge or supervisor to approve them. Set to false
-- to make them active straight away.
Config.WarrantsNeedApproval = true

-- What civilians can keep, per player.
Config.Civilian = { maxCharacters = 5, maxVehicles = 10, maxWeapons = 10 }

-- ------------------------------------------------------------------ the penal code

-- class: 'infraction', 'misdemeanor' or 'felony'. fine in dollars, jail in months.
Config.PenalCode = {
    {
        title = 'Title 1 - Crimes against people',
        charges = {
            { code = '1-01', name = 'Assault', class = 'misdemeanor', fine = 750, jail = 10 },
            { code = '1-02', name = 'Assault with a deadly weapon', class = 'felony', fine = 2500, jail = 30 },
            { code = '1-03', name = 'Battery', class = 'misdemeanor', fine = 1000, jail = 15 },
            { code = '1-04', name = 'Kidnapping', class = 'felony', fine = 5000, jail = 45 },
            { code = '1-05', name = 'Attempted murder', class = 'felony', fine = 10000, jail = 60 },
            { code = '1-06', name = 'Murder', class = 'felony', fine = 25000, jail = 120 },
            { code = '1-07', name = 'Manslaughter', class = 'felony', fine = 7500, jail = 50 },
            { code = '1-08', name = 'Criminal threats', class = 'misdemeanor', fine = 500, jail = 5 },
        },
    },
    {
        title = 'Title 2 - Crimes against property',
        charges = {
            { code = '2-01', name = 'Petty theft', class = 'misdemeanor', fine = 300, jail = 0 },
            { code = '2-02', name = 'Grand theft', class = 'felony', fine = 1500, jail = 15 },
            { code = '2-03', name = 'Grand theft auto', class = 'felony', fine = 2000, jail = 20 },
            { code = '2-04', name = 'Burglary', class = 'felony', fine = 2500, jail = 25 },
            { code = '2-05', name = 'Robbery', class = 'felony', fine = 3000, jail = 30 },
            { code = '2-06', name = 'Armed robbery', class = 'felony', fine = 6000, jail = 45 },
            { code = '2-07', name = 'Vandalism', class = 'misdemeanor', fine = 500, jail = 0 },
            { code = '2-08', name = 'Arson', class = 'felony', fine = 5000, jail = 35 },
            { code = '2-09', name = 'Trespassing', class = 'misdemeanor', fine = 250, jail = 0 },
        },
    },
    {
        title = 'Title 3 - Crimes against public order',
        charges = {
            { code = '3-01', name = 'Disorderly conduct', class = 'misdemeanor', fine = 300, jail = 0 },
            { code = '3-02', name = 'Resisting arrest', class = 'misdemeanor', fine = 750, jail = 10 },
            { code = '3-03', name = 'Obstruction of justice', class = 'misdemeanor', fine = 1000, jail = 10 },
            { code = '3-04', name = 'Evading a peace officer', class = 'misdemeanor', fine = 1000, jail = 10 },
            { code = '3-05', name = 'Felony evading', class = 'felony', fine = 3000, jail = 25 },
            { code = '3-06', name = 'Impersonating a peace officer', class = 'felony', fine = 2500, jail = 20 },
            { code = '3-07', name = 'Bribery', class = 'felony', fine = 3000, jail = 20 },
            { code = '3-08', name = 'Failure to identify', class = 'infraction', fine = 250, jail = 0 },
        },
    },
    {
        title = 'Title 4 - Weapons and drugs',
        charges = {
            { code = '4-01', name = 'Carrying a weapon without a permit', class = 'misdemeanor', fine = 1500, jail = 10 },
            { code = '4-02', name = 'Brandishing a weapon', class = 'misdemeanor', fine = 1000, jail = 10 },
            { code = '4-03', name = 'Possession of an illegal weapon', class = 'felony', fine = 3000, jail = 25 },
            { code = '4-04', name = 'Discharging a firearm in public', class = 'felony', fine = 2000, jail = 15 },
            { code = '4-05', name = 'Possession of a controlled substance', class = 'misdemeanor', fine = 750, jail = 5 },
            { code = '4-06', name = 'Possession with intent to sell', class = 'felony', fine = 3500, jail = 25 },
            { code = '4-07', name = 'Drug trafficking', class = 'felony', fine = 10000, jail = 60 },
        },
    },
    {
        title = 'Title 5 - Vehicles and traffic',
        charges = {
            { code = '5-01', name = 'Speeding (up to 15 over)', class = 'infraction', fine = 150, jail = 0 },
            { code = '5-02', name = 'Speeding (16 to 30 over)', class = 'infraction', fine = 300, jail = 0 },
            { code = '5-03', name = 'Excessive speeding (over 30)', class = 'misdemeanor', fine = 750, jail = 0 },
            { code = '5-04', name = 'Running a red light or stop sign', class = 'infraction', fine = 200, jail = 0 },
            { code = '5-05', name = 'Reckless driving', class = 'misdemeanor', fine = 1000, jail = 5 },
            { code = '5-06', name = 'Driving under the influence', class = 'misdemeanor', fine = 1500, jail = 10 },
            { code = '5-07', name = 'Driving without a license', class = 'misdemeanor', fine = 500, jail = 0 },
            { code = '5-08', name = 'Driving on a suspended license', class = 'misdemeanor', fine = 1000, jail = 5 },
            { code = '5-09', name = 'Unregistered or uninsured vehicle', class = 'infraction', fine = 250, jail = 0 },
            { code = '5-10', name = 'Hit and run', class = 'felony', fine = 2500, jail = 20 },
            { code = '5-11', name = 'Illegal parking', class = 'infraction', fine = 100, jail = 0 },
        },
    },
}
