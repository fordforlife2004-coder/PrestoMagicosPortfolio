-- Spectating. The server approves and logs it and sends the target's position. The admin's ped is then
-- hidden, frozen and kept just below the target (so the target streams in on far-away parts of the map),
-- and the camera follows the target. Backspace, or "Stop spectating" in the menu, puts everything back.

Spectate = { active = false, name = nil }

local returnTo
local STOP_CONTROL = 177 -- Backspace

local function targetPed(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return 0 end
    return GetPlayerPed(player)
end

local function parkBelow(ped, coords)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z - 12.0, false, false, false)
end

function Spectate.stop()
    if not Spectate.active then return end
    Spectate.active = false
    Spectate.name = nil
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    if returnTo then
        RequestCollisionAtCoord(returnTo.coords.x, returnTo.coords.y, returnTo.coords.z)
        SetEntityCoords(ped, returnTo.coords.x, returnTo.coords.y, returnTo.coords.z, false, false, false, false)
        SetEntityHeading(ped, returnTo.heading)
        returnTo = nil
    end
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    ApplyAdminModes()
    SendNUIMessage({ type = 'spectate', active = false })
    Rpc('spectateEnded')
end

-- data = { target = server id, name = ..., coords = { x, y, z } }. Returns ok, message.
function Spectate.start(data)
    if Spectate.active then Spectate.stop() end
    local ped = PlayerPedId()
    returnTo = { coords = GetEntityCoords(ped), heading = GetEntityHeading(ped) }
    Spectate.active = true
    Spectate.name = data.name

    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(data.coords.x, data.coords.y, data.coords.z)
    parkBelow(ped, data.coords)

    local target, waited = 0, 0
    while waited < 5000 do
        target = targetPed(data.target)
        if target ~= 0 and DoesEntityExist(target) then break end
        Wait(100)
        waited = waited + 100
    end
    if target == 0 or not DoesEntityExist(target) then
        Spectate.stop()
        return false, ("Couldn't load %s's area. Try again."):format(data.name)
    end

    NetworkSetInSpectatorMode(true, target)
    SendNUIMessage({ type = 'spectate', active = true, name = data.name })

    CreateThread(function()
        local lastMove, lostFor = 0, 0
        while Spectate.active do
            if IsControlJustPressed(0, STOP_CONTROL) or IsDisabledControlJustPressed(0, STOP_CONTROL) then
                Spectate.stop()
                break
            end
            local now = GetGameTimer()
            if now - lastMove > 500 then
                lastMove = now
                local current = targetPed(data.target)
                if current ~= 0 and DoesEntityExist(current) then
                    lostFor = 0
                    if current ~= target then -- the target respawned with a new ped
                        target = current
                        NetworkSetInSpectatorMode(true, target)
                    end
                    parkBelow(PlayerPedId(), GetEntityCoords(target))
                else
                    lostFor = lostFor + 500
                    if lostFor >= 3000 then
                        Spectate.stop()
                        Toast(('%s left or went out of range.'):format(data.name), 'warn')
                        break
                    end
                end
            end
            Wait(0)
        end
    end)
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not Spectate.active then return end
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    if returnTo then SetEntityCoords(ped, returnTo.coords.x, returnTo.coords.y, returnTo.coords.z, false, false, false, false) end
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
end)
