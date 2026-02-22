RegisterServerEvent('prestonadmin:checkperm')
AddEventHandler('prestonadmin:checkperm', function()
    local src = source
    if IsPlayerAceAllowed(src, Config.AdminPerm) then
        TriggerClientEvent('prestonadmin:permgranted', src)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^1No admin perm' } })
    end
end)

RegisterServerEvent('prestonadmin:kick')
AddEventHandler('prestonadmin:kick', function(target, reason)
    local src = source
    if IsPlayerAceAllowed(src, Config.AdminPerm) then
        DropPlayer(target, "Kicked by admin: " .. reason)
    end
end)

RegisterServerEvent('prestonadmin:ban')
AddEventHandler('prestonadmin:ban', function(target, reason)
    local src = source
    if IsPlayerAceAllowed(src, Config.AdminPerm) then
        DropPlayer(target, "Banned by admin: " .. reason)
    end
end)

RegisterCommand('plist', function(source)
    if not IsPlayerAceAllowed(source, Config.AdminPerm) then return end
    local players = GetPlayers()
    local msg = "^2Players online:\n"
    for _, id in ipairs(players) do
        msg = msg .. id .. " - " .. GetPlayerName(id) .. "\n"
    end
    TriggerClientEvent('chat:addMessage', source, { args = { msg } })
end, false)
