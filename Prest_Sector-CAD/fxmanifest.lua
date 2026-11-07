fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Prest_Sector-CAD'
author 'Preston D'
description 'Prest_Sector CAD: computer aided dispatch and records on an in-game tablet, checked by the server'
version '1.0.0'

-- The server reads where players are (911 calls, units on the map), which needs OneSync.
dependency '/onesync'

shared_scripts {
    'config.lua',
    'shared/cad.lua',
}

server_scripts {
    'server/store.lua',
    'server/bridge.lua',
    'server/records.lua',
    'server/dispatch.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/dispatch.lua',
    'client/plates.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
}
