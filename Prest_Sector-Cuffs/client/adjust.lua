-- /cuffadjust <style>: lines a style's cuffs up on your own wrists. Your character holds the cuffed
-- pose with the cuffs on (only you see them), you nudge them with the keys below, and Enter prints
-- the line to paste into config.lua. Cuffs put on after that use the new position on this game until
-- it restarts, so you can check it on a cuffed friend before you change the config.
--   Arrow keys       move left/right (x) and forward/back (y)
--   Page Up / Down   move up and down (z)
--   hold Shift       turn around those axes instead of moving
--   hold Ctrl        small steps
--   Enter            print the line for config.lua (in chat and the F8 console)
--   Backspace        stop

local C = Cuffs

local KEYS = {
    { control = 174, axis = 1, sign = -1 }, -- left arrow
    { control = 175, axis = 1, sign = 1 },  -- right arrow
    { control = 172, axis = 2, sign = 1 },  -- up arrow
    { control = 173, axis = 2, sign = -1 }, -- down arrow
    { control = 10, axis = 3, sign = 1 },   -- page up
    { control = 11, axis = 3, sign = -1 },  -- page down
}
local SHIFT, CTRL, ENTER, BACKSPACE = 21, 36, 191, 177
local ALSO_BLOCKED = { 24, 25, 30, 31, 22, 44, 140, 141, 142, 143, 199, 200 } -- attack, walking, jump, pause
local STEPS = { move = 0.005, turn = 5.0 }
local SMALL_STEPS = { move = 0.001, turn = 1.0 }
local FIRST_REPEAT_MS, REPEAT_MS = 400, 100

local adjusting = false
local current = nil -- { ped, object, style } while adjusting, so stopping the script can undo it

local function chat(text) TriggerEvent('chat:addMessage', { args = { 'Cuffs', text } }) end

local function drawLine(text, row)
    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.015, 0.30 + row * 0.03)
end

local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    for _ = 1, 200 do
        if HasAnimDictLoaded(dict) then return true end
        Wait(10)
    end
    return HasAnimDictLoaded(dict)
end

-- How long the cuff and uncuff animations really are, to check Config seconds against.
local function printLengths(key)
    for _, kind in ipairs({ 'cuff', 'uncuff' }) do
        local a = C.animationFor(Config, kind, key)
        for _, who in ipairs({ 'officer', 'suspect' }) do
            local anim = a[who]
            if loadDict(anim.dict) then
                print(('[Prest_Sector-Cuffs] %s, %s: %s %s is %.2f s long (the config waits %.1f s)'):format(
                    kind, who, anim.dict, anim.clip, GetAnimDuration(anim.dict, anim.clip), a.seconds))
            end
        end
    end
end

-- Keeps the pose on. The dictionary is loaded before the loop starts, so this never waits.
local function pose(ped, style)
    if not IsEntityPlayingAnim(ped, style.anim.dict, style.anim.clip, 3) and HasAnimDictLoaded(style.anim.dict) then
        TaskPlayAnim(ped, style.anim.dict, style.anim.clip, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end
end

local function finish()
    if not current then return end
    if DoesEntityExist(current.object) then DeleteEntity(current.object) end
    StopAnimTask(current.ped, current.style.anim.dict, current.style.anim.clip, 2.0)
    FreezeEntityPosition(current.ped, false)
    current = nil
end

local function cuffedNow() return GlobalState[C.cuffsKey(GetPlayerServerId(PlayerId()))] ~= nil end

RegisterNetEvent('Prest_Sector-Cuffs:adjust', function(key)
    local style = Config.Styles[key]
    if not style or adjusting or cuffedNow() then return end
    adjusting = true -- before anything waits, so a second /cuffadjust can't start another one
    if not loadDict(style.anim.dict) then
        adjusting = false
        return chat(("The %s animation isn't in the game. Check anim in config.lua."):format(style.anim.dict))
    end
    local ped = PlayerPedId()
    local offset = { style.offset[1], style.offset[2], style.offset[3] }
    local rotation = { style.rotation[1], style.rotation[2], style.rotation[3] }
    local object = CuffProps.attach(ped, style, offset, rotation)
    if not object then
        adjusting = false
        return chat(("The %s model isn't in the game."):format(style.prop))
    end
    current = { ped = ped, object = object, style = style }
    FreezeEntityPosition(ped, true)
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    pose(ped, style)
    printLengths(key)
    local nextRepeat = 0
    while adjusting do
        for _, k in ipairs(KEYS) do DisableControlAction(0, k.control, true) end
        for _, control in ipairs({ SHIFT, CTRL, ENTER, BACKSPACE }) do DisableControlAction(0, control, true) end
        for _, control in ipairs(ALSO_BLOCKED) do DisableControlAction(0, control, true) end

        local now = GetGameTimer()
        local what = IsDisabledControlPressed(0, SHIFT) and 'turn' or 'move'
        local step = (IsDisabledControlPressed(0, CTRL) and SMALL_STEPS or STEPS)[what]
        for _, k in ipairs(KEYS) do
            local first = IsDisabledControlJustPressed(0, k.control)
            if first or (IsDisabledControlPressed(0, k.control) and now >= nextRepeat) then
                offset, rotation = C.nudge(offset, rotation, what, k.axis, k.sign * step)
                DetachEntity(object, false, false)
                CuffProps.place(object, ped, style, offset, rotation)
                nextRepeat = now + (first and FIRST_REPEAT_MS or REPEAT_MS)
            end
        end
        pose(ped, style)

        if IsDisabledControlJustPressed(0, ENTER) then
            local line = C.attachLine(offset, rotation)
            print(('[Prest_Sector-Cuffs] Config.Styles.%s: %s'):format(key, line))
            chat(('%s: %s'):format(key, line))
            style.offset, style.rotation = offset, rotation
        end
        if IsDisabledControlJustPressed(0, BACKSPACE) or IsEntityDead(ped) or cuffedNow() then
            adjusting = false
        end

        drawLine(('Lining up the %s cuffs'):format(key), 0)
        drawLine(('offset    x %.3f   y %.3f   z %.3f'):format(offset[1], offset[2], offset[3]), 1)
        drawLine(('rotation  x %.1f   y %.1f   z %.1f'):format(rotation[1], rotation[2], rotation[3]), 2)
        drawLine('Arrows, PgUp/PgDn move | Shift turn | Ctrl small steps', 3)
        drawLine('Enter print the line for config.lua | Backspace stop', 4)
        Wait(0)
    end
    finish()
end)

-- Restarting the script while adjusting (to load the pasted line) must not leave you frozen.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    adjusting = false
    finish()
end)
