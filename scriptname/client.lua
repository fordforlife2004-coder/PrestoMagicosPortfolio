-- /hello: greets the player by name, in chat and as a notification above the minimap.

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterCommand('hello', function()
    local name = GetPlayerName(PlayerId())
    local message = ('Hi %s, welcome to my FiveM portfolio!'):format(name)
    TriggerEvent('chat:addMessage', { color = { 80, 200, 120 }, args = { 'Hello', message } })
    notify(message)
end, false)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/hello', 'Say hello')
end)
