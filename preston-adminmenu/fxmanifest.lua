fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-adminmenu'
author 'Preston D'
description 'Preston Admin Menu v2: NUI admin panel with server-side permissions, saved bans, reports and Discord logs'
version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/vehicle_types.lua',
}

server_scripts {
    'server/util.lua',
    'server/storage.lua',
    'server/logs.lua',
    'server/bans.lua',
    'server/reports.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/modes.lua',
    'client/spectate.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
