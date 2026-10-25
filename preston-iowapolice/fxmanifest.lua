fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-iowapolice'
author 'Preston D'
description 'Preston Iowa Police v2: spawn and style Iowa patrol vehicles with unit-number plates, checked by the server'
version '2.0.0'

shared_scripts {
    'config.lua',
    'shared/iowa.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'
