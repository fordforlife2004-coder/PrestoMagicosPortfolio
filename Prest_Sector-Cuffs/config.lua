-- Prest_Sector Cuffs settings. This file is shared with every player's game, so never put secrets here.

Config = {}

-- Who can cuff, uncuff, escort and seat people. Grant it to your police in server.cfg:
--   add_ace group.police cuffs.use allow
--   add_principal identifier.license:THEIR_LICENSE group.police
-- Set to '' to let everyone carry cuffs.
Config.AcePermission = 'cuffs.use'

-- Who can use /cuffadjust to line the cuffs up on the wrists. It only changes what they see while
-- they adjust, so it's safe to give to your developers. Set to '' to let everyone use it.
Config.AdjustPermission = 'cuffs.adjust'

-- How close (in metres) an officer must be to the suspect, and to a vehicle for /putin and /takeout.
Config.MaxDistance = 1.5
Config.VehicleDistance = 4.0

-- Seconds between one officer's actions, so the animations can't be spammed.
Config.CooldownSeconds = 2

-- Whether cuffed players can sprint. Walking is always allowed.
Config.CuffedCanRun = false

-- Whether a suspect can pull away while the cuffs go on. They're held against the officer for a
-- moment as it starts; after that they can walk off, and if they get out of reach before the cuffs
-- close they stay free. Set to false to hold them still for the whole arrest.
Config.SuspectCanPullAway = true

-- A cuffed player who leaves and comes back within this many minutes is cuffed again, so leaving
-- isn't a way out of the cuffs. Set to 0 to turn this off.
Config.KeepCuffsMinutes = 10

-- /cuff with no style cuffs in front when the officer is facing the suspect, and behind the back
-- when the officer is behind them. Set to false to always use Config.DefaultStyle.
Config.ChooseByPosition = true

-- The cuff styles. /cuff front or /cuff rear picks one.
--   label     how messages describe it ("Cuffed behind the back.")
--   prop      the model on the wrists (p_cs_cuffs_02_s is the game's own pair of handcuffs)
--   bone      the hand bone it hangs from (60309 is the left hand)
--   offset    x, y, z in metres from that bone
--   rotation  x, y, z in degrees
--   anim      the pose the cuffed player holds; it moves the arms only, so they can still walk
--   walk      what their legs do while an officer walks them along (optional)
--   cuff, uncuff  this style's own animations, instead of Config.Animations (optional)
-- To move the cuffs, run /cuffadjust <style> in game and paste the line it prints over offset and rotation.
Config.Styles = {
    rear = {
        label = 'behind the back',
        prop = 'p_cs_cuffs_02_s',
        bone = 60309,
        offset = { -0.055, 0.060, 0.040 }, rotation = { 265.0, 155.0, 80.0 },
        anim = { dict = 'mp_arresting', clip = 'idle' },
    },
    front = {
        label = 'in front',
        prop = 'p_cs_cuffs_02_s',
        bone = 60309,
        offset = { -0.058, 0.005, 0.090 }, rotation = { 290.0, 95.0, 120.0 },
        anim = { dict = 'anim@move_m@prisoner_cuffed', clip = 'idle' },
        -- Face to face: the suspect turns to the officer, who works the cuffs on in front of them.
        cuff = {
            seconds = 2.0,
            officer = { dict = 'mp_arresting', clip = 'a_uncuff', flags = 49 },
            suspect = { dict = 'anim@move_m@prisoner_cuffed', clip = 'idle', flags = 49 },
            lineUp = { offset = { 0.0, 0.65, 0.0 }, heading = 180.0, ms = 500 },
        },
        uncuff = {
            seconds = 2.0,
            officer = { dict = 'mp_arresting', clip = 'a_uncuff', flags = 49 },
            suspect = { dict = 'anim@move_m@prisoner_cuffed', clip = 'idle', flags = 49 },
            lineUp = { offset = { 0.0, 0.65, 0.0 }, heading = 180.0, ms = 500 },
        },
    },
}
Config.DefaultStyle = 'rear'

-- What the officer and the suspect play while cuffs go on and come off (behind the back).
--   seconds  how long it takes; the cuffs close (or open) at the end, if the suspect is still in reach
--   flags    TaskPlayAnim flags (optional)
--   lineUp   where the suspect stands against the officer as it starts (x right, y forward, z up,
--            and a turn in degrees), so the officer's hands meet the suspect's wrists
Config.Animations = {
    cuff = {
        seconds = 3.8,
        officer = { dict = 'mp_arrest_paired', clip = 'cop_p2_back_left', flags = 33 },
        suspect = { dict = 'mp_arrest_paired', clip = 'crook_p2_back_left', flags = 33 },
        lineUp = { offset = { -0.1, 0.45, 0.0 }, heading = 20.0, ms = 950 },
    },
    uncuff = {
        seconds = 5.5,
        officer = { dict = 'mp_arresting', clip = 'a_uncuff', flags = 0 },
        suspect = { dict = 'mp_arresting', clip = 'b_uncuff', flags = 0 },
        lineUp = { offset = { -0.1, 0.45, 0.0 }, heading = 20.0, ms = 950 },
    },
}

-- /escort holds a cuffed suspect at the officer's side: 0.54 m to the right and 0.54 m in front.
-- (11816 is passed to the game as it is, which holds them to the officer's middle; the offset is
-- tuned for that.) Their legs walk or run along with the officer, and the officer's arm holds theirs.
Config.Escort = {
    bone = 11816,
    offset = { 0.54, 0.54, 0.0 },
    walk = { dict = 'anim@move_m@prisoner_cuffed', clip = 'walk' },
    run = { dict = 'anim@move_m@trash', clip = 'run' },
    officer = { dict = 'amb@world_human_drinking@coffee@female@base', clip = 'base', flags = 50 },
}

-- Keys players can bind in Settings > Key Bindings > FiveM. '' means no key until they pick one.
Config.Keys = {
    cuff = '',   -- cuff the nearest player, or uncuff them if they're cuffed
    escort = '', -- take the nearest cuffed player by the arm, or let go
}
