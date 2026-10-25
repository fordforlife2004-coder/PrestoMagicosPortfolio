fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-vehicleskins'
author 'Preston D'
description 'Preston Vehicle Skins v2: liveries, extras, colors, plates and performance tuning, checked by the server'
version '2.0.0'

shared_scripts {
    'config.lua',
    'shared/vehicle_types.lua',
    'shared/skins.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'
