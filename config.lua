--[[
    push_gates
    by XanderP
    discord.gg/cMqazwj6c7

    Gates you push open by hand instead of them opening by themselves.
    Works on any framework, or none.
]]

Config = {}

-- ============================================================
-- HOW YOU GRAB A GATE
-- ============================================================

--[[ 'hold'   hold a key near the gate. needs nothing else, works anywhere
     'ox'     ox_target
     'qb'     qb-target
     'bs19'   BS19 target
     'auto'   pick whichever target script is running, hold key if none

     Default is 'hold' on purpose. It works the second you start the resource
     with nothing installed and nothing configured, which is what you want out
     of the box. 'auto' grabbing whatever target script happens to be on the
     server is a surprise, and on somebody elses server its a surprise they
     didnt ask for.

     If you want it on a target script, pick it here or in /PushgateDebug. ]]
Config.interact = 'hold'

-- key held to push. 38 = E
Config.grabControl = 38

Config.grabDistance    = 2.4   -- forgiving interaction; IK grips only within safe reach
Config.releaseDistance = 3.6   -- let go only after clearly walking away

-- ============================================================
-- GATES
-- ============================================================

-- how often we look around for gates (ms) and how far
Config.scanInterval = 500
Config.scanRadius   = 25.0

-- Models that count as gates.
--
-- MOST OF THESE ARE EMPTY TABLES ON PURPOSE.
--
-- travel and axis used to be numbers you typed in and hoped were right, and
-- getting one wrong meant a gate that stopped short or slid through a wall.
-- They are both read off the model's own bounding box now: a gate is wider
-- than it is deep, so the long side is the way it slides, and the distance it
-- needs to move to be out of the way is its own width.
--
-- So an empty table means "work it out", which is right for nearly everything.
-- Fill one in only when you disagree with what it worked out:
--   ['some_gate'] = { travel = 6.5 },              -- slide further
--   ['some_gate'] = { axis = 'forward' },          -- built turned 90 degrees
--
-- Names in here that do not exist in your build cost nothing - the hash just
-- never matches anything. And anything missing is usually picked up by the
-- auto-detection below anyway.
--   travel = how far it slides in metres
--   axis   = 'right' for a gate in a fence line, 'forward' if the model
--            was built turned 90 degrees
--
-- These numbers are a starting point, tune them in game with /gatetravel
-- Nothing breaks if one is wrong, the gate just stops short
-- or slides too far.
Config.models = {
    -- Chainlink fence gates. The big one - these are most of the gates in the
    -- game, and they come in matched _l / _r pairs wherever a gateway has two
    -- leaves.
    ['prop_fnclink_02gate1']       = {},
    ['prop_fnclink_02gate2']       = {},   -- in this map
    ['prop_fnclink_02gate3']       = {},
    ['prop_fnclink_02gate3_l']     = {},
    ['prop_fnclink_02gate3_r']     = {},
    ['prop_fnclink_02gate4']       = {},
    ['prop_fnclink_02gate5']       = {},   -- in this map
    ['prop_fnclink_02gate6']       = {},
    ['prop_fnclink_02gate6_l']     = {},   -- in this map
    ['prop_fnclink_02gate6_r']     = {},
    ['prop_fnclink_03gate1']       = {},   -- in this map
    ['prop_fnclink_03gate2']       = {},
    ['prop_fnclink_03gate3']       = {},
    ['prop_fnclink_03gate4']       = {},
    ['prop_fnclink_03gate5']       = {},
    ['prop_fnclink_04gate1']       = {},   -- in this map
    ['prop_fnclink_04gate2']       = {},
    ['prop_fnclink_04gate3']       = {},
    ['prop_fnclink_05gate1']       = {},
    ['prop_fnclink_05gate2']       = {},
    ['prop_fnclink_05gate3']       = {},
    ['prop_fnclink_05gate4']       = {},
    ['prop_fnclink_05gate5']       = {},
    ['prop_fnclink_05gate6']       = {},
    ['prop_fnclink_06gate1']       = {},
    ['prop_fnclink_06gate2']       = {},   -- in this map
    ['prop_fnclink_06gate3']       = {},   -- in this map

    -- Factory and yard gates.
    ['prop_facgate_01']            = {},
    ['prop_facgate_02']            = {},
    ['prop_facgate_03']            = {},
    ['prop_facgate_03_l']          = {},
    ['prop_facgate_03_r']          = {},   -- in this map
    ['prop_facgate_03b']           = {},
    ['prop_facgate_03b_l']         = {},   -- in this map
    ['prop_facgate_03b_r']         = {},
    ['prop_facgate_04']            = {},

    -- The big industrial sliders.
    ['prop_lrggate_01a']           = {},
    ['prop_lrggate_01b']           = {},
    ['prop_lrggate_02a']           = {},
    ['prop_lrggate_02b']           = {},
    ['prop_lrggate_03a']           = {},
    ['prop_lrggate_03b']           = {},
    ['prop_lrggate_04a']           = {},
    ['prop_lrggate_05a']           = {},

    -- Security gates, the kind on a car park barrier arm's big brother.
    ['prop_sec_gate_01']           = {},
    ['prop_sec_gate_01b']          = {},
    ['prop_sec_gate_01c']          = {},
    ['prop_sec_gate_01d']          = {},
    ['prop_sec_gate_02']           = {},

    -- Named one-offs. Airport, prison, the base, the docks.
    ['ch_prop_ch_gate_01a']        = {},
    ['hei_prop_hei_bankgate']      = {},
    ['hei_prop_station_gate']      = {},   -- in this map
    ['prop_arm_gate_l']            = {},   -- in this map
    ['prop_arm_gate_r']            = {},
    ['prop_gate_airport_01']       = {},   -- in this map
    ['prop_gate_cult_01']          = {},
    ['prop_gate_docks_ld']         = {},
    ['prop_gate_military_01']      = {},   -- in this map
    ['prop_gate_prison_01']        = {},   -- in this map
    ['prop_sc1_06_gate_l']         = {},   -- in this map
    ['prop_sc1_06_gate_r']         = {},   -- in this map
    ['v_serv_metro_stationgate']   = {},   -- in this map
}

--[[ THERE IS NO OPEN DIRECTION TO CONFIGURE, AND THAT IS DELIBERATE.

     Earlier versions tried to work out which side each gate should open on -
     from the model name, from a second leaf stood next to it, from a ray
     fired down the rail. All three are guesses, all three are wrong
     sometimes, and a gate that opens into a fence is the most obvious bug a
     player can find.

     A gate on a rail can physically slide either way, so now it does. You
     push it the way you push it. The way that opens the gap is the way that
     looks right, and a player works that out in half a second without being
     told. No direction to set, to get wrong, or to have to fix with a
     command - and no /gateflip, because there is nothing to flip. ]]

--[[ Gates the script has never seen before are picked up by name.

     The model list above will always be out of date - there are gates in DLC
     maps, in custom maps, and in whatever somebody adds next week. So as well
     as the list, the script reads the model NAME of things near you: if it
     says gate, it is a gate, and how far it slides comes off its own
     bounding box.

     Needs GetEntityArchetypeName, which is not on every build. Where it is
     missing this quietly does nothing and the list above still works. ]]
Config.autoDetect = true

Config.autoMatch = { 'gate' }

--[[ ...and the ones that are lying about it. prop_gate_frame_02 is the FRAME
     a gate hangs in, prop_inflategate_01 is an inflatable arch you drive
     under. Both have "gate" in the name, neither slides anywhere, and being
     able to grab a doorframe and walk off down the road with it is the sort
     of thing that ends up in a video with your server's name on it. ]]
Config.autoIgnore = {
    'frame', 'inflate', 'gatehouse', 'gatepost', 'gate_post',
    'floodgate', 'stargate', 'gateleg',
}

-- Anything narrower than this is a bracket or a sign, not a gate.
Config.autoMinSize = 1.5

--[[ How far a gate slides, as a multiple of its own width. 1.0 means a four
     metre gate slides four metres, which puts the gap fully open. Drop it to
     0.9 if gates in your map slide into scenery at the far end. ]]
Config.travelScale = 1.0

--[[ When two gates are both within arms reach, how much the one youre looking
     at is favoured over the one thats a bit nearer. 0 means nearest always
     wins, which is how it used to be and why double gates were a lottery.
     0.9 is about a metre of leeway. ]]
Config.aimBias = 0.9

-- ============================================================
-- PUSHING
-- ============================================================

-- how much of your walking turns into gate movement.
-- under 1.0 feels heavier, you walk further than the gate moves
Config.pushScale = 1.0

-- Per-frame arm IK keeps both hands at the moving gate instead of merely
-- playing a push clip in empty air. Disable if a custom animation supplies
-- its own hand placement.
Config.gripIk = true           -- single near-side hand; the other arm stays free
Config.gripChestOffset = 0.0   -- from the ped's Spine2 bone, not entity origin
Config.gripHandSpacing = 0.36  -- distance between hands along the rail
Config.gripFaceGate = false    -- do not lock walking direction to the gate
Config.gripTurnRate = 0.28     -- smooth turn per frame, not an instant snap
Config.gatePose = 'bare'       -- avoid the two-arm box-carry pose
Config.gripDebug = false      -- /gategripdebug draws actual hand targets

Config.deadzone     = 0.0015  -- ignore tiny movement so the gate dont creep
Config.syncInterval = 100     -- ms between updates to other players
Config.smoothing    = 0.25    -- how fast other players see it catch up

-- turn to face the gate while pushing. looks better with the lean anim
-- but you lose heading control while holding it
--[[ Turn to face the gate and side-step along it, rather than walking
     normally and dragging it behind you.

     This is what taking hold of a gate actually looks like: you stand square
     to it, both hands on it, and walk sideways. GTA will not do that by
     itself - a ped turns to face wherever it is walking - so the script locks
     your heading onto the gate and applies a strafe clipset, which is the
     same mechanism the game uses when you are aiming.

     Set it to false and you get the old behaviour: walk normally, gate
     follows. ]]
Config.faceGate = true

-- How hard the heading snaps onto the gate. 1.0 is instant and looks robotic,
-- 0.3 turns you over a few frames.
Config.faceSnap = 0.3

-- The clipset that makes the ped side-step instead of turning. If your server
-- has a nicer one, put it here.
Config.strafeClipset = 'move_strafe@generic'

--[[ Hold the player onto the gate while pushing.

     You keep walking normally, but you cant wander off sideways and you cant
     walk past the point the gate stops at. So when the gate hits the end of
     its rail, or something is in the way, you stop with it - like your
     actually holding the thing instead of standing near it.

     Its not AttachEntityToEntity. That parents you to the gate and takes your
     legs away, you end up being carried along. This just corrects your
     position back to where your hands should be.

     NOTE this forces pushScale to 1.0 while your holding a gate. Cant be
     helped - if the gate moves less than you do then you and it are drifting
     apart by design, and theres nothing to hold onto. ]]

-- how hard you get pulled back, per frame. 1.0 is instant and feels stiff,
-- lower is softer but lets you drift a bit first
-- how far you can get from the gate before it pulls you back, and how hard
-- it pulls. Small slack with a soft snap, otherwise it writes your position
-- every frame and the walk animation never gets to finish a step - thats what
-- made the character stand there stiff with his arms out in 1.5.

-- ============================================================
-- UI
-- ============================================================

-- how far up the screen the "hold E" prompt sits, in vh from the bottom
Config.promptY = 8

-- ============================================================
-- ANIMATION
-- ============================================================

-- First one that exists on your build gets used. Cycle them live with
-- /gateanim and keep the one you like.
--
-- These play upper body only so your legs still walk. The lean is in the
-- chest and shoulders so you still get it.
-- Tried a fair few of these. First one that actually exists on the build
-- wins, so leave the order alone unless you know what you want.
--
-- The dingy push_rock ones are the best fit by miles - both hands out at
-- chest height, gripping, body leaning into it. Which is exactly what pushing
-- a gate looks like. The pushcar ones are next, they read alright but the
-- hands sit low because hes meant to be on a car boot. The trash one is a
-- last resort, its a bin carry and it shows.
--[[ How long before the script will even consider re-applying the animation.

     An upper body anim gets dropped by the locomotion system now and then and
     has to be put back, but re-issuing it is a visible pop - so there is a
     floor on how often that can happen. Polling every frame is what made it
     stutter once a second. ]]
Config.animRecheck = 900

--[[ EVERY ONE OF THESE HAS BEEN CHECKED AGAINST THE GAME'S OWN CLIP TABLE.

     Not remembered, not copied off a forum - looked up in a dump of all
     20,179 animation dictionaries in the base game and confirmed to exist.

     That matters because the list that was here before contained
     missexile3 / ex03_dingy_push_rock_l and _r, which DO NOT EXIST. Not
     "missing on this build" - there is no clip called push_rock anywhere in
     GTA V. A made up clip name does not error. TaskPlayAnim just does
     nothing, silently, and you are left wondering why the animation never
     plays.

     Cycle them in game with /gateanim, or from the panel in /PushgateDebug,
     and keep whichever looks right. The order below is my ranking. ]]
Config.anim = {
    --[[ 1. Carrying a box. Forearms up and forward, hands apart, and it comes
         with a full idle/walk/run set so it never breaks stride. Reads as
         gripping the edge of a gate rather than pushing flat on it. This is
         the default because both prior push clips lifted fists overhead. ]]
    { dict = 'anim@heists@box_carry@', clip = 'walk' },

    -- 2/3. Optional live comparisons via /gatepose. Neither is default:
    -- both showed an overhead fist pose with this character.
    { dict = 'missheistpaletoscore1', clip = 'push_car_loop_player' },
    { dict = 'missbigscore2aig_5', clip = 'push_trolly_walk' },

    -- 4. Shoving the vault door out at the Big Score. Hands on a tall flat
    --    mass, driving forward. There is an _r variant too.
    { dict = 'missbigscore2big_11', clip = 'push_out_vault_l' },

    -- 5. The one that already worked on this build, kept as a safe fallback.
    { dict = 'missfinale_c2ig_11', clip = 'pushcar_offcliff_m' },

    --[[ 6. Your suggestion, and it does exist. It is the "carry the FIB
         agent" loop from Three's Company, so the arms are likely curled in
         holding a body rather than extended flat. Worth a look, but I would
         expect the trolley to beat it. ]]
    { dict = 'missheistfbi3b_ig7', clip = 'lift_fibagent_loop' },

    --[[ 7. An actual scripted gate-open animation. Built to be synced to a
         paired prop track, so it may want the gate moving on its own clock -
         but it is literally called gate_open, so it is worth trying. ]]
    { dict = 'anim@scripted@bty3@ig2_open_gate@male@', clip = 'gate_open' },

    -- 8. Hands flat on a tall vertical surface, body leaned in - it is the
    --    pat-down-against-the-wall pose. Faces the surface square on.
    { dict = 'missheistpaletoscore1', clip = 'pinned_against_wall_pro_loop_buddy' },

    -- 9. Forearms on a rail, tipped forward. Good for leaning on a gate,
    --    less good while walking.
    { dict = 'missstrip_club_lean', clip = 'player_lean_rail_loop' },

    -- 10. The engine's own door shove, one arm. Short, so it suits a single
    --     shove rather than a hold.
    { dict = 'doors@unarmed', clip = 'l_hand_barge' },

    -- 11. Standing version of the trolley push, for when the gate has stopped.
    { dict = 'missbigscore2aig_5', clip = 'push_trolly_stand' },
}

--[[ How long the prompt can go without a message before one is sent anyway.
     See the note on ui() in client/main.lua: the prompt is sent on change
     plus this heartbeat, rather than every frame. ]]
Config.uiHeartbeat = 500

--[[ Obstacles must not be able to stop a push.

     A player holding a gate is walking a line they did not choose, so "walk
     round the bin" is not available to them - a kerb or a post in the way is
     a gate you cannot finish opening. While you are holding a gate, collision
     between you and each PROP within pushClearRadius is switched off, one prop
     at a time, and put back when you let go. The ground, walls, vehicles and
     other players are untouched, so you do not fall through anything. ]]
Config.pushThroughProps = true
Config.pushClearRadius  = 3.5

--[[ How long to give an animation dictionary to stream in before deciding it
     is not there. A mission dict can take longer than a second, and writing a
     real clip off as missing is how you end up on a worse fallback for no
     reason. ]]
Config.animLoadWait = 3000

-- ============================================================
-- ADMIN
-- ============================================================

-- who can open /PushgateDebug.
-- ace permission first, then this list of identifiers as a fallback for
-- servers that dont use aces
-- checked in this order: this ace, the 'command' ace, the list below,
-- then whatever admin system the server already runs
Config.adminAce = 'pushgates.admin'

-- most server owners already have the 'command' ace so this saves setting
-- anything up. its FiveMs own permission system, nothing else needed.
-- turn off if you want it locked down tighter
Config.useCommandAce = true

--[[ Off by default because the script is standalone and should stay that way
     until you say otherwise. Turn it on and it'll also accept admins from
     bs_admin, ESX groups or QB permissions if any of those are running.

     Its all wrapped so a missing export cant error, but it is still the
     script reaching into other resources, so thats your call to make. ]]
Config.useFrameworkAdmin = false

Config.admins = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
}

Config.debug = false

-- ============================================================
-- DOOR SYSTEM
-- ============================================================

--[[ Gates registered in GTAs door system open by themselves when you walk
     up. We freeze them on sight so the engine stops driving them, which is
     why they dont auto open anymore.

     If a specific gate still fights you, put its door hash here and it gets
     taken off the door system properly. Empty by default, removing a door
     another script registered would break that script. ]]
--[[ No longer needed, and left here only so an old config does not error.

     This used to be a hand written list of door-system hashes to unregister,
     which was never going to work: the hash for a map door is not derivable
     from the object and is not written down anywhere you can read. The script
     now asks the engine directly with DoorSystemFindExistingDoor, which
     searches half a metre around the gate and hands back the id the map
     registered it under. Nothing to fill in. ]]
Config.unregisterDoors = {}
