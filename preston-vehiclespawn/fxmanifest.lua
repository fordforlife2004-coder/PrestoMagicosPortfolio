fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-vehiclespawn'
author 'Preston D'
description 'Preston Vehicle Spawn v2: /car and /dv, spawned and checked by the server'
version '2.0.0'

shared_scripts {
    'config.lua',
    'shared/vehicle_types.lua',
    'shared/rules.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'
