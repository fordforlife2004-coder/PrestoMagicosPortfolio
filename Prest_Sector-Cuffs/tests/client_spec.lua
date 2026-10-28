-- Runs the game scripts (client/*.lua) in tests/fake_game.lua: the cuffs on the wrists, what a cuffed
-- player can't do, being walked along, the officer's commands, the arrest itself and /cuffadjust.
-- Run from the resource folder with any Lua 5.3+:  lua tests/client_spec.lua

local G = dofile('tests/fake_game.lua')
local t = G.runner()

-- Me (the player whose game this is), a suspect a metre in front of me and a bystander behind me.
local ME, SUSPECT, OTHER = 1, 2, 3
local myPed = G.addPlayer(0, ME, G.vec(0, 0), 0.0)
local suspectPed = G.addPlayer(1, SUSPECT, G.vec(0, 1.0), 0.0)
local otherPed = G.addPlayer(2, OTHER, G.vec(0, -1.2), 0.0)

G.strict()
dofile('config.lua')
dofile('shared/cuffs.lua')
dofile('client/props.lua')
dofile('client/main.lua')
dofile('client/adjust.lua')
G.runFor(100)

local C = Cuffs
local function cuffsOn(id) return CuffProps.drawn()[id] end
local function playing(ped, dict, clip) return G.entity(ped).anims[dict .. '/' .. clip] end
-- The server changing GlobalState (with the change handlers), then a few frames.
local function setCuffs(id, style) G.setGlobal(C.cuffsKey(id), style) G.runFor(50) end
local function setEscort(id, officer) G.setGlobal(C.escortKey(id), officer) G.runFor(50) end
-- The same without the handlers, for the officer's commands that read it on the spot.
local function quietly(key, value) G.global[key] = value end

t.test("a cuffed player wears the game's handcuffs on the left wrist, made only in this game", function()
    t.eq(cuffsOn(SUSPECT), nil, 'nobody is cuffed yet')
    setCuffs(SUSPECT, 'rear')
    local cuffs = G.entity(cuffsOn(SUSPECT))
    t.eq(cuffs.model, 'hash:p_cs_cuffs_02_s')
    t.eq(cuffs.networked, false, 'each game draws its own')
    t.eq(cuffs.collision, false)
    t.eq(cuffs.attachedTo, suspectPed)
    t.eq(cuffs.attach.bone, 'bone:60309', 'the left hand')
    t.near(cuffs.attach.offset[1], -0.055)
    t.near(cuffs.attach.offset[2], 0.060)
    t.near(cuffs.attach.offset[3], 0.040)
    t.eq(cuffs.attach.rotation[1] .. ' ' .. cuffs.attach.rotation[2] .. ' ' .. cuffs.attach.rotation[3], '265.0 155.0 80.0')
    t.eq(table.concat({ tostring(cuffs.attach.rest[1]), tostring(cuffs.attach.rest[5]), tostring(cuffs.attach.rest[6]) }, ' '),
        'true 0 true', 'attached the way the offsets were measured (rotation order 0)')
end)

t.test('other GlobalState keys never redraw anything', function()
    local cuffs = cuffsOn(SUSPECT)
    G.setGlobal('somethingElse:2', 'x')
    G.setGlobal(C.escortKey(SUSPECT), nil)
    G.runFor(50)
    t.eq(cuffsOn(SUSPECT), cuffs)
end)

t.test('front cuffs move to the front pose, and taking them off removes them', function()
    local before = cuffsOn(SUSPECT)
    setCuffs(SUSPECT, 'front')
    t.eq(G.entity(before), nil, 'the old pair is deleted')
    local cuffs = G.entity(cuffsOn(SUSPECT))
    t.near(cuffs.attach.offset[3], 0.090)
    t.eq(cuffs.attach.rotation[1], 290.0)
    setCuffs(SUSPECT, nil)
    t.eq(cuffsOn(SUSPECT), nil)
    t.eq(G.entity(cuffs), nil)
end)

t.test('respawning gets new cuffs, invisible players hide theirs, and players out of view lose them', function()
    setCuffs(SUSPECT, 'rear')
    local newPed = G.newPed(1)
    G.runFor(600)
    t.eq(G.entity(cuffsOn(SUSPECT)).attachedTo, newPed, 'on the new ped')
    suspectPed = newPed
    G.entity(suspectPed).visible = false
    G.runFor(600)
    t.eq(G.entity(cuffsOn(SUSPECT)).visible, false)
    G.entity(suspectPed).visible = true
    G.runFor(600)
    t.eq(G.entity(cuffsOn(SUSPECT)).visible, true)
    local cuffs = cuffsOn(SUSPECT)
    local saved = G.players[1]
    G.removePlayer(1)
    G.runFor(600)
    t.eq(cuffsOn(SUSPECT), nil)
    t.eq(G.entity(cuffs), nil, 'deleted, not left floating')
    G.players[1] = saved
    G.runFor(600)
    t.eq(G.entity(cuffsOn(SUSPECT)).attachedTo, suspectPed, 'back in view, cuffed again')
    setCuffs(SUSPECT, nil)
end)

t.test('a cuff model missing from the game draws nothing and breaks nothing', function()
    G.models.p_cs_cuffs_02_s = nil
    setCuffs(SUSPECT, 'rear')
    G.runFor(600)
    t.eq(cuffsOn(SUSPECT), nil)
    G.models.p_cs_cuffs_02_s = true
    G.runFor(600)
    t.eq(cuffsOn(SUSPECT) ~= nil, true, 'drawn once it can be')
    setCuffs(SUSPECT, nil)
end)

t.test('cuffed myself: arms held behind my back, hands blocked, weapon away, cuffs on my wrists', function()
    setCuffs(ME, 'rear')
    G.runFor(300)
    local me = G.entity(myPed)
    t.eq(me.handcuffs, true)
    t.eq(me.flags[184], true, "can't shuffle over into the driver seat")
    t.eq(playing(myPed, 'mp_arresting', 'idle').flags, 49, 'arms only, so I can still walk')
    t.eq(me.weapon, 'hash:WEAPON_UNARMED')
    for _, control in ipairs({ 24, 25, 140, 37, 23, 22, 21, 27 }) do t.eq(G.disabled[control], true, 'control ' .. control) end
    t.eq(G.disabled[30], nil, 'walking is allowed')
    t.eq(G.firingDisabled, true)
    t.eq(G.entity(cuffsOn(ME)).attachedTo, myPed, 'I see my own cuffs')
    t.eq(G.exports.IsCuffed(), true)
    me.anims = {} -- something knocked the pose off
    me.handcuffs = false -- and a revive cleared the game's own handcuff flag
    G.runFor(300)
    t.eq(playing(myPed, 'mp_arresting', 'idle') ~= nil, true, 'the pose comes back')
    t.eq(me.handcuffs, true, 'so does the handcuff flag')
end)

t.test("cuffed myself: the officer's commands are refused", function()
    G.command('cuff')
    t.eq(G.lastNote(), "You can't do that with your own hands cuffed.")
end)

t.test('held by the arm: at the officer side, walking and running along, let go when it ends', function()
    setEscort(ME, OTHER)
    local me = G.entity(myPed)
    t.eq(me.attachedTo, otherPed)
    t.eq(me.attach.bone, 11816, 'passed straight in, like the tuned offsets expect')
    t.eq(me.attach.offset[1] .. ' ' .. me.attach.offset[2], '0.54 0.54')
    t.eq(G.disabled[30], true, "can't walk off while held")
    G.entity(otherPed).gait = 'walk'
    G.runFor(50)
    t.eq(playing(myPed, 'anim@move_m@prisoner_cuffed', 'walk').flags, 1)
    G.entity(otherPed).gait = 'run'
    G.runFor(50)
    t.eq(playing(myPed, 'anim@move_m@trash', 'run') ~= nil, true)
    t.eq(playing(myPed, 'anim@move_m@prisoner_cuffed', 'walk'), nil)
    G.entity(otherPed).gait = nil
    G.runFor(50)
    t.eq(playing(myPed, 'anim@move_m@trash', 'run'), nil, 'standing still')
    t.eq(playing(myPed, 'mp_arresting', 'idle') ~= nil, true, 'the cuffed pose stays on')
    setEscort(ME, nil)
    t.eq(me.attachedTo, nil)
end)

t.test('an officer who is far away (respawned) or behind a wall never pulls me to them', function()
    G.entity(otherPed).coords = G.vec(0, -40)
    setEscort(ME, OTHER)
    G.runFor(50)
    t.eq(G.entity(myPed).attachedTo, nil, 'too far')
    G.entity(otherPed).coords = G.vec(0, -1.2)
    G.entity(otherPed).behindWall = true
    G.runFor(50)
    t.eq(G.entity(myPed).attachedTo, nil, 'not through a wall')
    G.entity(otherPed).behindWall = nil
    G.runFor(50)
    t.eq(G.entity(myPed).attachedTo, otherPed, 'once nothing is in between')
    setEscort(ME, nil)
end)

t.test('as the cuffs come off, the cuffed pose stops so the uncuff animation can move the arms', function()
    G.runFor(300)
    t.eq(playing(myPed, 'mp_arresting', 'idle') ~= nil, true)
    G.event('Prest_Sector-Cuffs:animate', 'uncuff', 'suspect', OTHER, 'rear')
    t.eq(playing(myPed, 'mp_arresting', 'idle'), nil)
    t.eq(playing(myPed, 'mp_arresting', 'b_uncuff').flags, 0)
    G.runFor(1000)
    t.eq(playing(myPed, 'mp_arresting', 'idle'), nil, 'not put back while the cuffs come off')
    G.runFor(5000)
end)

t.test('taken out of the cuffs: hands free, pose gone, no cuffs drawn', function()
    setCuffs(ME, nil)
    local me = G.entity(myPed)
    t.eq(me.handcuffs, false)
    t.eq(me.flags[184], false)
    t.eq(playing(myPed, 'mp_arresting', 'idle'), nil)
    t.eq(cuffsOn(ME), nil)
    t.eq(G.exports.IsCuffed(), false)
    G.runFor(300)
    t.eq(G.disabled[24], nil)
end)

t.test("a player's game can't write GlobalState, so it can't uncuff itself there", function()
    local ok = pcall(function() GlobalState[C.cuffsKey(ME)] = nil end)
    t.eq(ok, false)
end)

t.test('/cuff picks the nearest free player in front of me that I can see; /uncuff the nearest cuffed one', function()
    G.command('cuff')
    t.eq(G.lastSent().name, 'Prest_Sector-Cuffs:cuff')
    t.eq(G.lastSent().args[1], SUSPECT, 'in front beats behind')
    t.eq(G.lastSent().args[2], nil, 'no style: the server picks from where I stand')
    G.command('cuff', 'front')
    t.eq(G.lastSent().args[2], 'front')
    quietly(C.cuffsKey(SUSPECT), 'rear')
    G.command('cuff')
    t.eq(G.lastSent().args[1], OTHER, 'someone already cuffed is skipped')
    quietly(C.cuffsKey(SUSPECT), nil)
    G.entity(suspectPed).behindWall = true
    G.command('cuff')
    t.eq(G.lastSent().args[1], OTHER, 'someone behind a wall is skipped')
    G.entity(suspectPed).behindWall = nil
    quietly(C.cuffsKey(OTHER), 'rear')
    G.command('uncuff')
    t.eq(G.lastSent().name, 'Prest_Sector-Cuffs:uncuff')
    t.eq(G.lastSent().args[1], OTHER)
    quietly(C.cuffsKey(SUSPECT), 'rear')
    G.command('cufftoggle')
    t.eq(G.lastSent().name, 'Prest_Sector-Cuffs:uncuff', 'one key: the nearest is cuffed, so uncuff')
    quietly(C.cuffsKey(SUSPECT), nil)
    G.command('cufftoggle')
    t.eq(G.lastSent().name, 'Prest_Sector-Cuffs:cuff')
    quietly(C.cuffsKey(OTHER), nil)
    local sent = #G.sent
    G.entity(suspectPed).coords = G.vec(0, 5)
    G.entity(otherPed).coords = G.vec(0, -5)
    G.command('cuff')
    t.eq(#G.sent, sent, 'nothing sent')
    t.eq(G.lastNote(), 'Nobody close enough to cuff.')
    G.entity(suspectPed).coords = G.vec(0, 1.0)
    G.entity(otherPed).coords = G.vec(0, -1.2)
    t.eq(G.keys.cufftoggle, '', 'key bindings exist, with no key until players pick one')
    t.eq(G.keys.escort, '')
end)

t.test('/escort takes the nearest cuffed player, or lets go; the server always hears it', function()
    G.command('escort')
    t.eq(G.lastSent().name, 'Prest_Sector-Cuffs:escort', 'nobody cuffed here: the server still hears it, to let go')
    t.eq(G.lastSent().args[1], nil)
    quietly(C.cuffsKey(SUSPECT), 'rear')
    G.command('escort')
    t.eq(G.lastSent().args[1], SUSPECT)
    quietly(C.escortKey(SUSPECT), ME)
    G.command('escort')
    t.eq(#G.lastSent().args, 0, 'let go')
end)

t.test("while I hold someone my hand rests on their arm and I can't get into a vehicle with them", function()
    G.runFor(600)
    t.eq(playing(myPed, 'amb@world_human_drinking@coffee@female@base', 'base').flags, 50)
    t.eq(G.disabled[23], true, 'getting into a vehicle is blocked')
    G.aiming = true
    G.runFor(600)
    t.eq(playing(myPed, 'amb@world_human_drinking@coffee@female@base', 'base'), nil, 'not while aiming')
    G.aiming = false
    G.runFor(600)
    t.eq(playing(myPed, 'amb@world_human_drinking@coffee@female@base', 'base') ~= nil, true)
    quietly(C.escortKey(SUSPECT), nil)
    G.runFor(600)
    t.eq(playing(myPed, 'amb@world_human_drinking@coffee@female@base', 'base'), nil)
    t.eq(G.disabled[23], nil)
    quietly(C.escortKey(SUSPECT), ME)
end)

t.test('/putin picks a back seat of the nearest vehicle others can see; /takeout finds the cuffed player', function()
    local far = G.addVehicle(G.vec(10, 0), 3)
    local mine = G.addVehicle(G.vec(3, 0), 3)
    local ghost = G.addVehicle(G.vec(1, 0), 3, { networked = false })
    G.seat(G.addPlayer(5, 9, G.vec(3, 0)), mine, 1)
    G.command('putin')
    local sent = G.lastSent()
    t.eq(sent.name, 'Prest_Sector-Cuffs:seat')
    t.eq(sent.args[1], SUSPECT, 'the one I hold')
    t.eq(sent.args[2], mine)
    t.eq(sent.args[3], 2, 'seat 1 is taken, so the other back seat')
    G.seat(suspectPed, mine, 2)
    G.command('takeout')
    t.eq(G.lastSent().name, 'Prest_Sector-Cuffs:unseat')
    t.eq(G.lastSent().args[1], SUSPECT)
    G.unseat(suspectPed)
    G.command('takeout')
    t.eq(G.lastNote(), 'No cuffed player in a vehicle close enough.')
    t.eq(far ~= ghost, true)
    G.entities[far], G.entities[mine], G.entities[ghost] = nil, nil, nil
    G.removePlayer(5)
    G.command('putin')
    t.eq(G.lastNote(), 'No vehicle with a free seat close enough.')
    quietly(C.escortKey(SUSPECT), nil)
    quietly(C.cuffsKey(SUSPECT), nil)
    G.runFor(600)
end)

t.test('the arrest, as the suspect: held against the officer for a moment, then free to pull away', function()
    local log = #G.attachLog
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'suspect', OTHER, 'rear')
    local held = G.attachLog[log + 1]
    t.eq(held.entity, myPed)
    t.eq(held.to, otherPed)
    t.eq(held.bone, 11816)
    t.eq(held.offset[1] .. ' ' .. held.offset[2] .. ' ' .. held.rotation[3], '-0.1 0.45 20.0')
    t.eq(G.entity(myPed).attachedTo, nil, 'let go after 950 ms')
    local anim = playing(myPed, 'mp_arrest_paired', 'crook_p2_back_left')
    t.eq(anim.flags .. ' ' .. anim.ms, '33 3800')
    G.tick()
    t.eq(G.disabled[30], nil, 'after the line-up I can try to pull away')
    G.runFor(3000)
end)

t.test('with Config.SuspectCanPullAway off, the suspect stands still for the whole arrest', function()
    Config.SuspectCanPullAway = false
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'suspect', OTHER, 'rear')
    G.tick()
    t.eq(G.disabled[30], true, 'held still')
    G.runFor(3000)
    G.tick()
    t.eq(G.disabled[30], nil, 'free to move once done')
    Config.SuspectCanPullAway = true
end)

t.test('the line-up never pulls a suspect through a wall or out of a vehicle door', function()
    local before = #G.attachLog
    G.entity(otherPed).behindWall = true
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'suspect', OTHER, 'rear')
    G.entity(otherPed).behindWall = nil
    G.entity(myPed).gettingIn = true
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'suspect', OTHER, 'rear')
    G.entity(myPed).gettingIn = nil
    t.eq(#G.attachLog, before, 'no line-up either time')
    t.eq(playing(myPed, 'mp_arrest_paired', 'crook_p2_back_left') ~= nil, true, 'the animation still plays')
    G.runFor(4000)
end)

t.test('the arrest, as the officer: I stand still the whole time; the face-to-face front cuffing', function()
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'officer', SUSPECT, 'rear')
    t.eq(playing(myPed, 'mp_arrest_paired', 'cop_p2_back_left').flags, 33)
    G.runFor(3000)
    G.tick()
    t.eq(G.disabled[30], true, 'still standing still near the end')
    G.runFor(1000)
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'suspect', OTHER, 'front')
    local held = G.attachLog[#G.attachLog]
    t.eq(held.offset[2] .. ' ' .. held.rotation[3], '0.65 180.0', 'turned to face the officer')
    t.eq(playing(myPed, 'anim@move_m@prisoner_cuffed', 'idle').flags, 49)
    local before = #G.attachLog
    G.event('Prest_Sector-Cuffs:animate', 'dance', 'suspect', OTHER, 'rear')
    G.event('Prest_Sector-Cuffs:animate', 'cuff', 'judge', OTHER, 'rear')
    t.eq(#G.attachLog, before, 'nonsense from the network is ignored')
    G.entity(myPed).anims = {}
    G.runFor(4000)
end)

t.test('put in: walked into the seat, or put straight in when that fails; ignored when not cuffed', function()
    local car = G.addVehicle(G.vec(2, 0), 3)
    G.event('Prest_Sector-Cuffs:seat', car, 1)
    t.eq(G.entity(myPed).vehicle, nil, 'not cuffed: ignored')
    setCuffs(ME, 'rear')
    G.event('Prest_Sector-Cuffs:seat', car, 1)
    t.eq(G.entity(myPed).vehicle, car)
    G.unseat(myPed)
    G.enterWorks = false
    G.event('Prest_Sector-Cuffs:seat', car, 2)
    t.eq(G.entity(car).seats[2], myPed, 'put in directly')
    G.unseat(myPed)
end)

t.test('put in never warps me into a vehicle that drove off, sped away, or after I was grabbed again', function()
    local car = G.addVehicle(G.vec(2, 0), 3)
    CreateThread(function()
        G.net['Prest_Sector-Cuffs:seat'](car, 1)
    end)
    G.runFor(100)
    G.entity(car).coords = G.vec(300, 0) -- the getaway car leaves while I walk to the door
    G.runFor(6000)
    t.eq(G.entity(myPed).vehicle, nil, 'too far away by then')
    G.entity(car).coords = G.vec(2, 0)
    G.entity(car).speed = 8.0
    G.event('Prest_Sector-Cuffs:seat', car, 1)
    t.eq(G.entity(myPed).vehicle, nil, 'moving')
    G.entity(car).speed = 0.0
    CreateThread(function()
        G.net['Prest_Sector-Cuffs:seat'](car, 1)
    end)
    G.runFor(100)
    quietly(C.escortKey(ME), OTHER) -- an officer took hold of me in the meantime
    G.runFor(6000)
    t.eq(G.entity(car).seats[1], nil, 'not while someone holds me')
    quietly(C.escortKey(ME), nil)
    G.entity(myPed).attachedTo = nil
    G.runFor(600)
    G.enterWorks = true
end)

t.test('a second /putin replaces the first instead of fighting over me', function()
    G.enterWorks = false
    local first = G.addVehicle(G.vec(2, 0), 3)
    local second = G.addVehicle(G.vec(-2, 0), 3)
    CreateThread(function() G.net['Prest_Sector-Cuffs:seat'](first, 1) end)
    G.runFor(100)
    G.event('Prest_Sector-Cuffs:seat', second, 1)
    G.runFor(6000)
    t.eq(G.entity(myPed).vehicle, second)
    t.eq(G.entity(first).seats[1], nil, 'never put into the first one too')
    G.enterWorks = true
end)

t.test('take out: climbs out, or straight out if the normal way is blocked', function()
    local car = G.entity(myPed).vehicle
    G.event('Prest_Sector-Cuffs:unseat')
    t.eq(G.entity(myPed).vehicle, nil)
    t.eq(G.entity(myPed).leaveFlags, 0)
    G.seat(myPed, car, 1)
    G.exitWorks = false
    G.event('Prest_Sector-Cuffs:unseat')
    t.eq(G.entity(myPed).vehicle, nil)
    t.eq(G.entity(myPed).leaveFlags, 16)
    G.exitWorks = true
    setCuffs(ME, nil)
end)

t.test('/cuffadjust: cuffs on my own wrists, nudged with the keys, Enter prints the config line', function()
    local saved = { Config.Styles.rear.offset, Config.Styles.rear.rotation }
    CreateThread(function() G.net['Prest_Sector-Cuffs:adjust']('rear') end)
    G.runFor(50)
    local me = G.entity(myPed)
    t.eq(me.frozen, true)
    local cuffs = G.attachLog[#G.attachLog]
    t.eq(cuffs.to, myPed)
    t.eq(G.entity(cuffs.entity).model, 'hash:p_cs_cuffs_02_s')
    t.contains(G.printed[#G.printed - 3], 'cuff, officer: mp_arrest_paired cop_p2_back_left is 3.80 s long (the config waits 3.8 s)')

    G.press(175) -- right arrow: x + 5 mm
    G.tick()
    G.release(175)
    t.near(G.attachLog[#G.attachLog].offset[1], -0.050)
    G.pressed[21] = true -- Shift: turn instead
    G.press(172) -- up arrow: y rotation + 5
    G.tick()
    G.release(172)
    G.pressed[21] = nil
    t.eq(G.attachLog[#G.attachLog].rotation[2], 160.0)
    G.pressed[36] = true -- Ctrl: small steps
    G.press(10) -- Page Up: z + 1 mm
    G.tick()
    G.release(10)
    G.pressed[36] = nil
    t.near(G.attachLog[#G.attachLog].offset[3], 0.041)

    local count = #G.attachLog
    G.press(173) -- hold the down arrow: it repeats
    G.runFor(700)
    G.release(173)
    t.eq(#G.attachLog - count > 2, true, 'held keys repeat')
    t.eq(#G.attachLog - count < 10, true, 'but not every frame')
    local y = G.attachLog[#G.attachLog].offset[2]

    G.press(191) -- Enter
    G.tick()
    t.eq(G.chat[#G.chat], ('rear: offset = { -0.050, %.3f, 0.041 }, rotation = { 265.0, 160.0, 80.0 },'):format(y))
    t.contains(G.printed[#G.printed], 'Config.Styles.rear: offset = { -0.050,')
    t.near(Config.Styles.rear.offset[1], -0.050, 'used on this game from now on')

    G.press(177) -- Backspace
    G.tick()
    G.tick()
    t.eq(G.entity(cuffs.entity), nil, 'the practice cuffs are gone')
    t.eq(me.frozen, false)
    Config.Styles.rear.offset, Config.Styles.rear.rotation = saved[1], saved[2]
end)

t.test("/cuffadjust with an animation that isn't in the game says so instead of freezing me", function()
    G.missingDicts['mp_arresting'] = true
    local chats = #G.chat
    CreateThread(function() G.net['Prest_Sector-Cuffs:adjust']('rear') end)
    G.runFor(100)
    G.missingDicts['mp_arresting'] = nil
    t.contains(G.chat[chats + 1], "mp_arresting animation isn't in the game")
    t.eq(G.entity(myPed).frozen, false)
end)

t.test('restarting the script while adjusting, or mid line-up, leaves me free to move', function()
    CreateThread(function() G.net['Prest_Sector-Cuffs:adjust']('rear') end)
    G.runFor(50)
    local cuffs = G.attachLog[#G.attachLog].entity
    t.eq(G.entity(myPed).frozen, true)
    G.fire('onResourceStop', 'Prest_Sector-Cuffs')
    t.eq(G.entity(myPed).frozen, false)
    t.eq(G.entity(cuffs), nil)
    G.press(177)
    G.runFor(50) -- (the old loop notices and ends)
    CreateThread(function() G.net['Prest_Sector-Cuffs:animate']('cuff', 'suspect', OTHER, 'rear') end)
    G.runFor(20)
    t.eq(G.entity(myPed).attachedTo, otherPed, 'held against the officer')
    G.fire('onResourceStop', 'Prest_Sector-Cuffs')
    t.eq(G.entity(myPed).attachedTo, nil, 'let go')
    G.runFor(4000)
end)

t.test("stopping the script takes every pair of cuffs off, frees my hands, and drops my hand-on-arm pose", function()
    setCuffs(SUSPECT, 'rear')
    setCuffs(ME, 'rear')
    G.runFor(300)
    local theirs, mine = cuffsOn(SUSPECT), cuffsOn(ME)
    G.fire('onResourceStop', 'Prest_Sector-Cuffs')
    t.eq(G.entity(theirs), nil)
    t.eq(G.entity(mine), nil)
    t.eq(G.entity(myPed).handcuffs, false)
    setCuffs(ME, nil)
    quietly(C.escortKey(SUSPECT), ME)
    G.runFor(600)
    t.eq(playing(myPed, 'amb@world_human_drinking@coffee@female@base', 'base') ~= nil, true)
    G.fire('onResourceStop', 'Prest_Sector-Cuffs')
    t.eq(playing(myPed, 'amb@world_human_drinking@coffee@female@base', 'base'), nil)
end)

t.finish()
