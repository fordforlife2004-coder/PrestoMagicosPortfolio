fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Prest_Sector-Radar'
author 'Preston D'
description 'Prest_Sector Radar: police speed radar and plate reader, with plate hits from Prest_Sector CAD'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/radar.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
}
