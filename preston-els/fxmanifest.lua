fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-els'
author 'Preston D'
description 'Preston ELS v2: emergency lights, siren tones and air horn, checked by the server and synced to every player'
version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/els.lua',
}

server_script 'server/main.lua'

client_scripts {
    'client/sync.lua',
    'client/main.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
