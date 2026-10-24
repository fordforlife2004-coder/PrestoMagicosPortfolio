-- Preston Admin Menu v2 settings.
-- This file is shared with every player's game, so never put secrets here.
-- The Discord webhook goes in server.cfg instead:  set preston_admin_webhook "https://discord.com/api/webhooks/..."

Config = {}

-- Key that opens the menu. Players can rebind it in Settings > Key Bindings > FiveM.
Config.OpenKey = 'F10'

-- Key that toggles noclip for admins who have it. Empty means no default key (bind it in game).
Config.NoclipKey = ''

-- ACE permission for each part of the menu. Grant them in server.cfg, for example:
--   add_ace group.admin adminmenu allow            (everything below)
--   add_ace group.moderator adminmenu.open allow
--   add_ace group.moderator adminmenu.kick allow
Config.Permissions = {
    open = 'adminmenu.open',             -- open the menu and see the player list
    identifiers = 'adminmenu.identifiers', -- see license, Discord and Steam IDs
    kick = 'adminmenu.kick',
    warn = 'adminmenu.warn',
    ban = 'adminmenu.ban',
    unban = 'adminmenu.unban',
    teleport = 'adminmenu.teleport',     -- go to a player, a waypoint, or back
    bring = 'adminmenu.bring',
    spectate = 'adminmenu.spectate',
    freeze = 'adminmenu.freeze',
    heal = 'adminmenu.heal',             -- heal or revive
    noclip = 'adminmenu.noclip',
    god = 'adminmenu.god',
    invisible = 'adminmenu.invisible',
    vehicle = 'adminmenu.vehicle',       -- spawn, fix, flip and delete vehicles
    announce = 'adminmenu.announce',
    reports = 'adminmenu.reports',       -- see and handle player reports
    logs = 'adminmenu.logs',
    immune = 'adminmenu.immune',         -- can't be kicked, banned, frozen or brought...
    bypassImmunity = 'adminmenu.bypassimmune', -- ...unless the admin has this
}

-- Ban lengths offered in the menu ('perm' = permanent; otherwise a number with m, h, d or w).
Config.BanDurations = {
    { label = '1 hour', value = '1h' },
    { label = '1 day', value = '1d' },
    { label = '3 days', value = '3d' },
    { label = '1 week', value = '1w' },
    { label = '30 days', value = '30d' },
    { label = 'Permanent', value = 'perm' },
}

-- Also ban by IP address. Off by default: players on shared networks (dorms, cafes) would be caught too.
Config.BanIpAddresses = false

-- Shown to banned players when they try to join.
Config.BanAppealText = 'Appeal on our Discord.'

-- Where bans are saved: 'auto' uses MySQL through oxmysql when it's running, otherwise this
-- resource's built-in key-value storage. Set 'oxmysql' or 'kvp' to force one.
Config.Storage = 'auto'

-- Player reports (/report message).
Config.ReportCooldownSeconds = 60
Config.MaxOpenReportsPerPlayer = 3

-- Revive event for framework servers, sent to the player instead of the built-in revive.
-- QBCore: 'hospital:client:Revive'   ESX: 'esx_ambulancejob:revive'   Standalone: leave empty.
Config.ReviveEvent = ''

-- Delete an admin's previous spawned vehicle when they spawn another.
Config.DeletePreviousSpawnedVehicle = true

-- Noclip speeds: normal, holding Shift, holding Alt.
Config.NoclipSpeed = { normal = 1.0, fast = 4.0, slow = 0.25 }
