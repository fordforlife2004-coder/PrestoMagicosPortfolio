fx_version 'cerulean'
game 'gta5'

author 'Preston'
description 'Simple /hello command'
version '1.0'

client_script 'client.lua'
RegisterCommand('hello', function()
    TriggerEvent('chat:addMessage', { args = { '^2Hello from my FiveM portfolio!' } })
end, false) 
