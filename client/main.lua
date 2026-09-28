--[[
    push_gates - client
    by XanderP  -  discord.gg/cMqazwj6c7

    ------------------------------------------------------------------
    HOW THIS WORKS, AND WHY IT IS WRITTEN THIS WAY
    ------------------------------------------------------------------

    Three things about GTA gates that this script has to respect, and that
    earlier versions did not:

    1. THE ENGINE ALREADY OWNS MOST GATES.

       Base game gates are registered in the door system - that is what makes
       them swing open on their own when you walk up. The door system writes
       their transform every frame, so anything else setting their position is
       in a fight it loses, intermittently, in a way that looks like "the
       script is broken" rather than "two things are arguing".

       DoorSystemFindExistingDoor(x, y, z, model) hands back the door id the
       engine is using, and RemoveDoorFromSystem takes the gate off it. That
       has to happen BEFORE we move anything, and again every time the prop
       streams back in, because a fresh prop comes back under engine control.

    2. A MAP PROP IS A DIFFERENT HANDLE ON EVERY CLIENT.

       So nothing about a gate can be sent over the wire as an entity. What
       gets shared is a key made of model + rounded map position, and one
       number: how far open it is. Everyone applies that number to their own
       copy.

    3. A PROP THAT STREAMS BACK IN IS BACK AT ITS MAP POSITION.

       So the position has to be re-asserted, every frame, for any gate that
       is not fully shut. Setting it once is how you get a gate that is open
       until you look away.

    The push itself is deliberately NOT an attachment. The player walks
    normally and the gate is moved by however far they walked ALONG THE RAIL -
    their sideways movement is projected onto the gate's own axis. Two free
    bodies trying to hold station on each other is what drifts; one number
    derived from one body does not.
]]

local scanned   = {}     -- key -> gate, everything near us right now
local ratios    = {}     -- key -> how far open the server says it is
local shown     = {}     -- key -> how far open we are drawing it
local held      = nil    -- key of the gate in our hands
local pendingGate = nil  -- wait for server ownership before moving locally
local pendingAt = 0
local requestId = 0
local claimSession = nil
local grabAt    = nil    -- where we stood when we grabbed
local grabRatio = 0.0    -- how open it was when we grabbed
local promptUp  = false

local function dbg(...)
    if Config.debug then print('[push_gates]', ...) end
end

-- ============================================================
-- TALKING TO THE PAGE
-- ============================================================

--[[ Throttled. The prompt used to be sent every frame, which is sixty JSON
     encodes a second across the process boundary into the browser, for as
     long as somebody stands near a gate. Sent on change, plus a slow
     heartbeat so a dropped message still recovers. ]]
local lastSent, lastSentAt = nil, 0

local function ui(msg)
    msg.py = Config.promptY or 8

    if msg.action == 'prompt' then
        local now = GetGameTimer()
        local r = msg.ratio and math.floor(msg.ratio * 100) or -1
        local sig = ('%s|%s|%d|%s'):format(tostring(msg.show), tostring(msg.text),
                                           r, tostring(msg.py))
        if sig == lastSent and now - lastSentAt < (Config.uiHeartbeat or 500) then
            return
        end
        lastSent, lastSentAt = sig, now
    end

    SendNUIMessage(msg)
end

-- ============================================================
-- SAFE ENGINE READS
-- ============================================================

--[[ GetEntityModel on a handle that is not really there is not an error you
     can catch - it is an access violation inside gta-streaming-five.dll that
     takes the whole client down. Handles out of the object pool are a
     snapshot, and the entity a shape test hands back is not guaranteed to be
     a scripted entity at all. So nothing asks the engine directly. ]]
local function modelOf(ent)
    if not ent or ent == 0 then return nil end
    if not DoesEntityExist(ent) then return nil end
    return GetEntityModel(ent)
end

--[[ How wide the gate is and which way it lies, from the model's own box.

     A sliding gate is wider than it is deep - that is what makes it a gate
     rather than a post - so the longer horizontal side is the rail. And the
     distance it has to move to be out of the way is its own width.

     Both of those used to be numbers typed into a config and hoped about.
     Cached because this is read for every gate near you, every frame. ]]
local sizeCache = {}

local function sizeOf(hash)
    local c = sizeCache[hash]
    if c then return c end

    if not IsModelValid(hash) then
        c = { lo = vector3(-1.0, -0.2, 0.0), hi = vector3(1.0, 0.2, 2.0),
              span = 2.0, axis = 'right' }
        sizeCache[hash] = c
        return c
    end

    local lo, hi = GetModelDimensions(hash)
    local w, d = math.abs(hi.x - lo.x), math.abs(hi.y - lo.y)

    c = { lo = lo, hi = hi, span = math.max(w, d),
          axis = (w >= d) and 'right' or 'forward' }
    sizeCache[hash] = c
    return c
end

-- ============================================================
-- WHAT COUNTS AS A GATE
-- ============================================================

local modelDefs = {}
local autoDefs  = {}
local haveArchName = nil

CreateThread(function()
    for name, def in pairs(Config.models or {}) do
        modelDefs[GetHashKey(name)] = { name = name, def = def or {} }
    end
end)

local function archName(obj)
    if haveArchName == false then return nil end
    local ok, name = pcall(GetEntityArchetypeName, obj)
    if not ok then haveArchName = false return nil end
    haveArchName = true
    return (name and name ~= '') and tostring(name):lower() or nil
end

--[[ Returns name, def - and it is written as three plain statements rather
     than one clever expression ON PURPOSE.

         local name, def = hash and lookup(hash) or nil

     is the and/or trap: a two value return put in an expression slot keeps
     only the FIRST value, so def was nil for every object in the world, no
     gate was ever registered, and there was no prompt anywhere. It compiles,
     it runs, it does nothing. Do not make this clever again. ]]
local function defFor(obj, hash)
    local entry = modelDefs[hash]
    if entry then
        local def = entry.def
        if not def.travel then def.travel = sizeOf(hash).span * (Config.travelScale or 1.0) end
        if not def.axis then def.axis = sizeOf(hash).axis end
        return entry.name, def
    end

    if Config.autoDetect == false then return nil end

    local cached = autoDefs[hash]
    if cached == false then return nil end
    if cached then return cached.name, cached.def end

    local name = archName(obj)
    if not name then return nil end

    local hit = false
    for _, pat in ipairs(Config.autoMatch or { 'gate' }) do
        if name:find(pat, 1, true) then hit = true break end
    end
    if hit then
        for _, pat in ipairs(Config.autoIgnore or {}) do
            if name:find(pat, 1, true) then hit = false break end
        end
    end

    local size = sizeOf(hash)
    if not hit or size.span < (Config.autoMinSize or 1.5) then
        autoDefs[hash] = false
        return nil
    end

    local entry2 = {
        name = name,
        def  = { travel = size.span * (Config.travelScale or 1.0), axis = size.axis },
    }
    autoDefs[hash] = entry2
    dbg(('auto-detected %s, %.1fm on %s'):format(name, entry2.def.travel, entry2.def.axis))
    return entry2.name, entry2.def
end

local function knownModel(hash)
    if modelDefs[hash] then return true end
    local a = autoDefs[hash]
    return a ~= nil and a ~= false
end

-- ============================================================
-- IDENTITY
-- ============================================================

--[[ Model plus rounded map position. Read ONCE, on first sight, and never
     again: if we read it later the gate might already be slid open and we
     would be calling that its closed position. Every client works it out the
     same way from the same map, so it is the same string everywhere. ]]
local function gateKey(model, c)
    return ('%d:%d:%d:%d'):format(model,
        math.floor(c.x + 0.5), math.floor(c.y + 0.5), math.floor(c.z + 0.5))
end

--- The rail: a unit vector along the gate's own long axis.
local function railFor(obj, def)
    local h = math.rad(GetEntityHeading(obj))
    if def.axis == 'forward' then
        return vector3(-math.sin(h), math.cos(h), 0.0)
    end
    return vector3(math.cos(h), math.sin(h), 0.0)
end

-- ============================================================
-- TAKING A GATE OFF THE ENGINE
-- ============================================================

--[[ THE THING EVERY EARLIER VERSION OF THIS SCRIPT MISSED.

     Most gates in the base map are registered doors. The door system holds
     their transform and will happily put a gate back where it thinks it
     belongs, every frame, underneath whatever we just did - which is why
     freezing them and setting coords worked sometimes, on some gates, and
     looked like a script that could not make its mind up.

     DoorSystemFindExistingDoor searches a half metre around the coordinates
     you give it for a door of that model and hands back the id the engine
     knows it by. That id is not in any config and cannot be guessed; it is
     the only way to name a door the map registered.

     Locking it first (state 1) puts it back to shut before we read where shut
     actually is - otherwise a gate the engine had already swung open gives us
     a "closed" position that is halfway across the driveway. Then we take it
     off the system entirely and it is ours.

     Returns the closed position. ]]
local function takeOverDoor(obj, model)
    local at = GetEntityCoords(obj)

    local found, doorHash = DoorSystemFindExistingDoor(at.x, at.y, at.z, model)

    if found and doorHash then
        -- shut it, let the engine act on that, then read where shut is
        DoorSystemSetDoorState(doorHash, 1, false, true)
        DoorSystemSetOpenRatio(doorHash, 0.0, false, true)
        Wait(0)

        at = GetEntityCoords(obj)

        RemoveDoorFromSystem(doorHash)
        dbg(('took gate off the door system (door %s)'):format(doorHash))
    end

    --[[ Frozen so physics stops having an opinion, and so the engine's own
         door logic - if any of it is still attached - has nothing to push
         against. SetEntityCoordsNoOffset still moves a frozen object. ]]
    FreezeEntityPosition(obj, true)
    SetEntityCoordsNoOffset(obj, at.x, at.y, at.z, false, false, false)

    return at
end

-- ============================================================
-- FINDING GATES
-- ============================================================

local scanFailed = false

local function scanOnce()
    local at = GetEntityCoords(PlayerPedId())
    local radius = Config.scanRadius or 25.0
    local found = {}

    local byObj = {}
    for _, g in pairs(scanned) do byObj[g.obj] = g end

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) and #(at - GetEntityCoords(obj)) <= radius then
            local existing = byObj[obj]

            if existing then
                found[existing.key] = existing
            else
                local hash = modelOf(obj)
                local name, def
                if hash then
                    name, def = defFor(obj, hash)
                end

                if def then
                    --[[ Take it off the engine BEFORE reading its closed
                         position, because that call is what puts a gate the
                         engine had already opened back where it belongs. ]]
                    local base = takeOverDoor(obj, hash)
                    local key  = gateKey(hash, base)
                    local old  = scanned[key]

                    found[key] = {
                        key  = key,
                        obj  = obj,
                        name = name,
                        def  = def,
                        -- the first closed position we ever saw wins, so a
                        -- re-stream cannot redefine where shut is
                        base = old and old.base or base,
                        rail = railFor(obj, def),
                    }
                end
            end
        end
    end

    scanned = found
end

CreateThread(function()
    while true do
        Wait(Config.scanInterval or 500)

        --[[ An uncaught error in a CreateThread loop does not skip an
             iteration, it kills the thread for the rest of the session. This
             thread is the only thing that populates the gate list, so when it
             dies there are no gates, no prompt, and nothing on screen saying
             why. One line the first time, then it keeps trying. ]]
        local ok, err = pcall(scanOnce)
        if not ok and not scanFailed then
            scanFailed = true
            print('[push_gates] the gate scan threw and was caught: ' .. tostring(err))
            print('[push_gates] it keeps trying. /gatescan says what is around you.')
        elseif ok and scanFailed then
            scanFailed = false
            print('[push_gates] gate scan is happy again')
        end
    end
end)

-- ============================================================
-- PUTTING THE GATE WHERE IT BELONGS
-- ============================================================

--[[ Ratio runs -1 to 1, not 0 to 1, and that is the whole answer to "gates
     open the wrong way".

     Earlier versions tried to work out which side a gate should open on, from
     the model name, from a neighbouring leaf, from a ray fired down the rail.
     All three guess, all three are wrong sometimes, and a gate that opens
     into a fence is the most obvious bug a player can find.

     A gate on a rail can slide either way. So let it. You push it the way you
     push it, and the way that opens the gap is the way that looks right - the
     player works it out in half a second without being told, and there is no
     direction to configure, get wrong, or have to fix with a command. ]]
local function applyGate(gate, ratio)
    if not DoesEntityExist(gate.obj) then return end
    local p = gate.base + (gate.rail * ((gate.def.travel or 5.0) * ratio))
    SetEntityCoordsNoOffset(gate.obj, p.x, p.y, p.z, false, false, false)
end

--[[ Every frame, for any gate that is not shut. A map object belongs to the
     streamer, not to us, and it comes back at its map position every time it
     streams in - so setting it once gives you a gate that is open until you
     turn around. ]]
CreateThread(function()
    while true do
        Wait(0)
        local idle = true

        for key, gate in pairs(scanned) do
            local want = ratios[key] or 0.0
            local prev = shown[key]
            local have

            if prev == nil or key == held then
                have = want
            elseif math.abs(want - prev) > 0.0005 then
                have = prev + (want - prev) * (Config.smoothing or 0.25)
            else
                have = want
            end

            shown[key] = have

            -- the "or prev" matters: without it a gate pushed shut stops
            -- being written at exactly zero and stays where it was
            if math.abs(have) > 0.0005 or math.abs(prev or 0.0) > 0.0005 then
                idle = false
                applyGate(gate, have)
            end
        end

        if idle and not held then Wait(200) end
    end
end)

-- ============================================================
-- ANIMATION
-- ============================================================

--[[ GetAnimDuration is the only one of these that tells the truth about a
     clip being present. DoesAnimDictExist says yes for a dict that is missing
     the clip you asked for, and TaskPlayAnim on a clip that is not there does
     nothing and says nothing about it. ]]
local function animAt(i)
    local a = (Config.anim or {})[i]
    if not a then return nil end

    --[[ "Not on this build" and "has not finished streaming" look identical
         if you only wait a second, and a mission dict can take longer than
         that. Ask whether the dict exists at all first, then give it a proper
         window to arrive - so a real clip is never written off as missing. ]]
    if not DoesAnimDictExist(a.dict) then
        dbg(('dict %s does not exist'):format(a.dict))
        return nil
    end

    RequestAnimDict(a.dict)
    local waited = 0
    while not HasAnimDictLoaded(a.dict) and waited < (Config.animLoadWait or 3000) do
        Wait(50); waited = waited + 50
    end
    if not HasAnimDictLoaded(a.dict) then
        dbg(('dict %s exists but would not stream in time'):format(a.dict))
        return nil
    end

    local d = GetAnimDuration(a.dict, a.clip)
    if not d or d <= 0.0 then return nil end
    return a
end

local playing        = nil
local animIndex      = 0
local animPick       = nil
local animChecked    = false
local animCheckWorks = nil
local lastAnimAt     = 0
local wasRagdoll     = false

local function startAnim(a)
    TaskPlayAnim(PlayerPedId(), a.dict, a.clip, 8.0, -8.0, -1, 49, 0, false, false, false)
    lastAnimAt = GetGameTimer()
end

local function playAnim(a)
    if not a then return end
    RequestAnimDict(a.dict)
    if not HasAnimDictLoaded(a.dict) then return end

    animCheckWorks = nil
    wasRagdoll = false
    startAnim(a)
    playing = a
end

--[[ An upper body anim is not a task the game protects - walk, clip a kerb,
     get ragdolled for a frame and the locomotion system drops it silently.
     So it has to be put back.

     But the check for whether it is still on cannot be trusted: with flag 49
     the anim is a SECONDARY task and IsEntityPlayingAnim reads the primary
     slot, so it answers "not playing" for an anim that is playing fine.
     Polling that every frame and re-issuing on a no is what made it stutter
     once a second - every re-issue is a visible pop.

     So: establish once whether the check is honest on this build. If it is
     not, stop asking and only put the anim back after something we can see
     for ourselves actually interrupted it. ]]
local function keepAnim()
    local a = playing
    if not a then return end

    local ped = PlayerPedId()
    local ragdoll = IsPedRagdoll(ped)

    if wasRagdoll and not ragdoll then
        startAnim(a)
        wasRagdoll = false
        return
    end
    wasRagdoll = ragdoll
    if ragdoll then return end

    if GetGameTimer() - lastAnimAt < (Config.animRecheck or 900) then return end

    local on = IsEntityPlayingAnim(ped, a.dict, a.clip, 3)

    if animCheckWorks == nil then
        animCheckWorks = on
        if not on then
            print('[push_gates] IsEntityPlayingAnim is not reliable for upper body '
               .. 'anims on this build - the animation will be re-applied after a '
               .. 'ragdoll rather than polled')
        end
        lastAnimAt = GetGameTimer()
        return
    end

    if animCheckWorks and not on then startAnim(a) end
end

local function stopAnim()
    local a = playing
    playing = nil
    if not a then return end
    StopAnimTask(PlayerPedId(), a.dict, a.clip, 3.0)
end

local function resolveAnim()
    if animChecked then return animPick end
    animChecked = true

    if Config.gatePose == 'bare' then
        animPick, animIndex = nil, 0
        return nil
    end

    for i = 1, #(Config.anim or {}) do
        local a = animAt(i)
        if a then
            animPick, animIndex = a, i
            print(('[push_gates] using animation %d - %s / %s'):format(i, a.dict, a.clip))
            return a
        end
        print(('[push_gates] %s / %s isnt on this build, trying the next one')
            :format(Config.anim[i].dict, Config.anim[i].clip))
    end

    print('[push_gates] none of the animations exist here - gates still work without one')
    return nil
end

-- ============================================================
-- FACING THE GATE
-- ============================================================

--[[ WALKING SIDEWAYS WAS THE WRONG IDEA AND IT IS GONE.

     The plan was to hold your heading on the gate and apply a strafe clipset
     so you side-stepped along it. Two problems, and the second one is fatal.

     It did not reliably strafe - the clipset does not take on every ped state
     and you end up walking normally with your heading yanked sideways, which
     looks worse than doing nothing.

     And it made obstacles into walls. Facing the gate with your movement
     locked sideways means a bin, a post, or the gate's own frame stops you
     dead, and a gate you cannot finish opening because there is a kerb in the
     way is a broken gate.

     So you now walk normally. You face where you are going, the gate moves by
     however far you travelled ALONG ITS RAIL, and if you approach at an angle
     the projection just takes the component that counts. ]]

--[[ AND YOU DO NOT BUMP INTO THINGS WHILE YOU ARE HOLDING ONE.

     A player pushing a gate is walking a line they did not choose, so the
     usual "walk round it" answer is not available to them. Rather than
     switching the player's collision off entirely - which drops you through
     the floor - this turns off collision between the player and each PROP
     nearby, one at a time, and puts it back on release. The ground, walls and
     vehicles are all untouched.

     Refreshed while you push, because props stream in as you move. ]]
local noClip = {}

local function ignoreNearbyProps(ped)
    local at = GetEntityCoords(ped)
    local reach = Config.pushClearRadius or 3.5

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) and not noClip[obj] then
            if #(at - GetEntityCoords(obj)) <= reach then
                SetEntityNoCollisionEntity(ped, obj, false)
                noClip[obj] = true
            end
        end
    end
end

local function restoreProps(ped)
    for obj in pairs(noClip) do
        if DoesEntityExist(obj) then
            -- true = "reset when they separate", which is the engine putting
            -- collision back the moment you are clear of it
            SetEntityNoCollisionEntity(ped, obj, true)
        end
    end
    noClip = {}
end

-- ============================================================
-- WHICH GATE ARE WE AT
-- ============================================================

--[[ Measured to the nearest point ON the gate, not to its origin. Gate
     origins sit at one end of the model, so measuring to the origin makes one
     end of a gate feel miles away and the other end grabbable from inside the
     fence. Player position into the model's local space, clamped to its box,
     back out to the world. ]]
local function nearPoint(obj, at)
    local hash = modelOf(obj)
    if not hash then return at end

    local box = sizeOf(hash)
    local l = GetOffsetFromEntityGivenWorldCoords(obj, at.x, at.y, at.z)
    local cx = math.max(box.lo.x, math.min(box.hi.x, l.x))
    local cy = math.max(box.lo.y, math.min(box.hi.y, l.y))

    return GetOffsetFromEntityInWorldCoords(obj, cx, cy, 0.0)
end

local function flat(a, b)
    return math.sqrt(((a.x - b.x) ^ 2) + ((a.y - b.y) ^ 2))
end

-- Keep both hands on the moving surface. IK targets last one frame, so this
-- must run while held; no ped/gate attachment or scripted teleport is used.
local function placeHands(ped, gate, at)
    if Config.gripIk == false or not SetIkTarget then return end
    local contact = nearPoint(gate.obj, at)
    local dx, dy = contact.x - at.x, contact.y - at.y
    if Config.gripFaceGate ~= false and dx * dx + dy * dy > 0.04 then
        local desired = GetHeadingFromVector_2d(dx, dy)
        local current = GetEntityHeading(ped)
        local turn = (desired - current + 540.0) % 360.0 - 180.0
        SetEntityHeading(ped, current + turn * (Config.gripTurnRate or 0.28))
    end
    -- Ped entity origins vary between models and poses. Spine2 is the
    -- character's own chest, so the grip cannot drift up to forehead level.
    local chest = GetPedBoneCoords(ped, 24817, 0.0, 0.0, 0.0)
    local height = chest.z + (Config.gripChestOffset or 0.0)
    local rightPoint = GetOffsetFromEntityInWorldCoords(ped, 1.0, 0.0, 0.0)
    local rx, ry = rightPoint.x - at.x, rightPoint.y - at.y
    local forwardPoint = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
    local fx, fy = forwardPoint.x - at.x, forwardPoint.y - at.y
    local depth = (contact.x - chest.x) * fx + (contact.y - chest.y) * fy
    -- A hand behind the chest makes the solver fold the arm through the body.
    -- Let go of the visual grip for that frame instead of forcing a bad pose.
    if depth < 0.12 then return end
    local lateral = (contact.x - chest.x) * rx + (contact.y - chest.y) * ry
    local arm = lateral < 0.0 and 3 or 4
    local safeDepth = math.max(0.35, math.min(0.70, depth))
    local side = lateral < 0.0 and -1 or 1
    local safeLateral = side * math.max(0.15, math.min(0.48, math.abs(lateral)))
    local x = chest.x + fx * safeDepth + rx * safeLateral
    local y = chest.y + fy * safeDepth + ry * safeLateral
    local localGrip = GetOffsetFromEntityGivenWorldCoords(gate.obj, x, y, height)
    SetIkTarget(ped, arm, gate.obj, -1,
        localGrip.x, localGrip.y, localGrip.z, 0, 0, 0)
    if Config.gripDebug then
        DrawMarker(28, x, y, height, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.08, 0.08, 0.08,
            arm == 3 and 255 or 40, arm == 3 and 60 or 180,
            40, 230, false, false, 2, false, nil, nil, false)
    end
end

local stick, stickAt = nil, 0

local function gateInReach()
    local ped   = PlayerPedId()
    local at    = GetEntityCoords(ped)
    local reach = Config.grabDistance or 2.4

    local cam  = GetGameplayCamRot(2)
    local ch   = math.rad(cam.z)
    local look = vector3(-math.sin(ch), math.cos(ch), 0.0)

    local best, bestScore

    for key, gate in pairs(scanned) do
        if DoesEntityExist(gate.obj) then
            local np = nearPoint(gate.obj, at)
            local d  = flat(at, np)

            if d <= reach then
                local dx, dy = np.x - at.x, np.y - at.y
                local len = math.sqrt((dx * dx) + (dy * dy))
                local dot = (len > 0.01)
                    and (((dx / len) * look.x) + ((dy / len) * look.y)) or 1.0

                -- what you are looking at breaks a tie between two gates that
                -- are both at arms length, which is the double gate case
                local score = d - (dot * (Config.aimBias or 0.9))
                if key == stick then score = score - 0.5 end

                if not bestScore or score < bestScore
                   or (score == bestScore and key < best.key) then
                    best, bestScore = gate, score
                end
            end
        end
    end

    if best then
        stick, stickAt = best.key, GetGameTimer()
    elseif stick and GetGameTimer() - stickAt > 600 then
        stick = nil
    end

    return best
end

-- ============================================================
-- GRAB AND RELEASE
-- ============================================================

local function releaseHeld(why)
    if not held then return end
    local key = held
    held, grabAt, grabRatio = nil, nil, 0.0
    local oldSession = claimSession
    claimSession = nil

    -- Stop the one clip rather than ClearPedTasks, which throws away
    -- everything else the ped happened to be doing as well.
    stopAnim()
    restoreProps(PlayerPedId())

    if promptUp then
        ui({ action = 'prompt', show = false })
        promptUp = false
    end

    TriggerServerEvent('push_gates:release', key, ratios[key] or 0.0, oldSession)
    dbg('let go', key, why or '')
end

local function tryGrab(gate)
    if held or pendingGate or not gate then return end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end

    requestId = requestId + 1
    TriggerServerEvent('push_gates:claim', gate.key, requestId)
    pendingGate = gate.key
    pendingAt = GetGameTimer()
end

exports('Grab', function() tryGrab(gateInReach()) end)

-- ============================================================
-- HOW YOU GRAB
-- ============================================================

local function targetRunning(which)
    if which == 'ox' then return GetResourceState('ox_target') == 'started' end
    if which == 'qb' then return GetResourceState('qb-target') == 'started' end
    if which == 'bs19' then
        return GetResourceState('bs_interactions') == 'started'
            or GetResourceState('bs19_target') == 'started'
    end
    return false
end

--[[ Config.interact can be 'auto', which is not a mode you can compare
     against. This turns it into one. Got this wrong once: the push loop
     compared Config.interact directly, the default was 'auto', so the hold
     prompt never appeared and you could not let go of a gate either. ]]
local mode = 'hold'

local function resolveMode()
    local want = Config.interact or 'auto'
    if want ~= 'auto' then mode = want
    elseif targetRunning('ox') then mode = 'ox'
    elseif targetRunning('qb') then mode = 'qb'
    elseif targetRunning('bs19') then mode = 'bs19'
    else mode = 'hold' end
    return mode
end

exports('TargetRunning', targetRunning)
exports('GateInReach', function() return gateInReach() end)
exports('Mode', function() return mode end)

-- ============================================================
-- THE PUSH
-- ============================================================

CreateThread(function()
    local lastSync = 0
    local lastClear = 0
    local lastKeepalive = 0

    while true do
        Wait(0)
        local sleep = true
        local ped = PlayerPedId()

        if pendingGate and (GetGameTimer() - pendingAt > 3000
            or (mode == 'hold' and not IsControlPressed(0, Config.grabControl or 38))) then
            pendingGate = nil
        end

        if held then
            sleep = false
            local gate = scanned[held]

            if not gate or not DoesEntityExist(gate.obj) then
                releaseHeld('gate gone')

            elseif mode == 'hold' and not IsControlPressed(0, Config.grabControl or 38) then
                releaseHeld('let go of the key')

            --[[ On a target script there is no key held down to let go of, so
                 the grab is a toggle instead. Without this the only way out
                 was to walk away, which felt broken. ]]
            elseif mode ~= 'hold' and IsControlJustReleased(0, Config.grabControl or 38) then
                releaseHeld('pressed the key')

            elseif IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
                releaseHeld('cant push right now')

            else
                local at = GetEntityCoords(ped)

                if flat(at, nearPoint(gate.obj, at)) > (Config.releaseDistance or 2.0) then
                    releaseHeld('walked off')
                else
                    --[[ WORKED OUT FROM WHERE YOU ARE, NOT ADDED UP.

                         How far you have walked along the rail SINCE YOU
                         GRABBED, projected onto the gate's own axis. Adding
                         up per frame deltas drifts - every dropped frame is a
                         little error and they only ever accumulate, so after
                         a long push the gate is no longer where your hands
                         are. Measuring from the anchor cannot drift. ]]
                    local travel = gate.def.travel or 5.0
                    local anchor = grabAt or at

                    local walked = ((at.x - anchor.x) * gate.rail.x)
                                 + ((at.y - anchor.y) * gate.rail.y)

                    local nxt = grabRatio + (walked * (Config.pushScale or 1.0)) / travel

                    -- either way off closed: see the note on applyGate
                    if nxt < -1.0 then nxt = -1.0 elseif nxt > 1.0 then nxt = 1.0 end

                    --[[ Re-anchor at the ends. Without this, pushing a gate
                         to the stop and then walking back leaves the gate
                         stuck for as many metres as you overshot by. ]]
                    if nxt <= -1.0 or nxt >= 1.0 then
                        grabAt, grabRatio = at, nxt
                    end

                    if nxt ~= (ratios[held] or 0.0) then
                        ratios[held] = nxt

                        local now = GetGameTimer()
                        if now - lastSync >= (Config.syncInterval or 100) then
                            lastSync = now
                            TriggerServerEvent('push_gates:push', held, nxt, claimSession)
                        end
                    end

                    keepAnim()
                    placeHands(ped, gate, at)
                    local aliveAt = GetGameTimer()
                    if aliveAt - lastKeepalive > 1000 then
                        lastKeepalive = aliveAt
                        TriggerServerEvent('push_gates:keepalive', held, claimSession)
                    end

                    --[[ Props stream in as you walk, so the ones to
                         ignore are re-gathered while you push rather than
                         only at the moment you grabbed. Twice a second is
                         plenty and costs nothing. ]]
                    if Config.pushThroughProps ~= false then
                        local now2 = GetGameTimer()
                        if now2 - (lastClear or 0) > 500 then
                            lastClear = now2
                            ignoreNearbyProps(ped)
                        end
                    end

                    ui({ action = 'prompt', show = true, key = 'E',
                         text = (mode == 'hold') and 'Pushing' or 'Pushing - E to let go',
                         ratio = math.abs(ratios[held] or 0.0) })
                    promptUp = true
                end
            end

        else
            local gate = gateInReach()

            if gate and mode == 'hold' then
                sleep = false
                ui({ action = 'prompt', show = true, key = 'E', text = 'Push the gate' })
                promptUp = true

                if IsControlPressed(0, Config.grabControl or 38) then
                    tryGrab(gate)
                end

            elseif promptUp then
                ui({ action = 'prompt', show = false })
                promptUp = false
            end
        end

        if sleep then Wait(150) end
    end
end)

-- ============================================================
-- SERVER
-- ============================================================

RegisterNetEvent('push_gates:sync', function(key, ratio)
    if key == held then return end    -- dont echo our own push back at us
    ratios[key] = ratio
end)

RegisterNetEvent('push_gates:claimed', function(key, ratio, claimId, replyId)
    if pendingGate ~= key or held or replyId ~= requestId then
        TriggerServerEvent('push_gates:release', key, ratio, claimId)
        return
    end
    pendingGate = nil
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped)
        or (mode == 'hold' and not IsControlPressed(0, Config.grabControl or 38)) then
        TriggerServerEvent('push_gates:release', key, ratio, claimId)
        return
    end
    held = key
    claimSession = claimId
    ratios[key] = ratio
    grabAt = GetEntityCoords(ped)
    grabRatio = ratio
    if Config.pushThroughProps ~= false then ignoreNearbyProps(ped) end
    CreateThread(function()
        local selected = resolveAnim()
        if held == key and claimSession == claimId then playAnim(selected) end
    end)
end)

RegisterNetEvent('push_gates:all', function(all)
    for k, v in pairs(all or {}) do ratios[k] = v end
end)

RegisterNetEvent('push_gates:denied', function(key, reason, replyId, authoritativeRatio, deniedSession)
    if replyId and replyId ~= requestId then return end
    if deniedSession and deniedSession ~= claimSession then return end
    if pendingGate == key then pendingGate = nil end
    if held == key then releaseHeld(reason or 'gate unavailable') end
    if type(authoritativeRatio) == 'number' then ratios[key] = authoritativeRatio end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(reason or 'Gate unavailable')
    EndTextCommandThefeedPostTicker(false, false)
end)

RegisterNetEvent('push_gates:config', function(c)
    for k, v in pairs(c or {}) do Config[k] = v end
    resolveMode()
    SetupTarget()
    print(('[push_gates] config updated - grab method is now %s'):format(mode))
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('push_gates:request')
end)

-- ============================================================
-- TARGET SCRIPTS
-- ============================================================

local hooked = {}

function SetupTarget()
    resolveMode()
    if mode == 'hold' or hooked[mode] then return end
    hooked[mode] = true

    local models = {}
    for name in pairs(Config.models or {}) do models[#models + 1] = GetHashKey(name) end
    if #models == 0 then return end

    local done = false

    if mode == 'ox' and targetRunning('ox') then
        done = pcall(function()
            exports.ox_target:addModel(models, { {
                name = 'push_gates', icon = 'fa-solid fa-hand', label = 'Push gate',
                distance = Config.grabDistance or 2.4,
                onSelect = function() tryGrab(gateInReach()) end,
            } })
        end)

    elseif mode == 'qb' and targetRunning('qb') then
        done = pcall(function()
            exports['qb-target']:AddTargetModel(models, {
                options = { { icon = 'fas fa-hand', label = 'Push gate',
                              action = function() tryGrab(gateInReach()) end } },
                distance = Config.grabDistance or 2.4,
            })
        end)

    elseif mode == 'bs19' and targetRunning('bs19') then
        for _, try in ipairs({
            function()
                exports.bs_interactions:AddModel(models, {
                    label = 'Push gate', icon = 'hand',
                    distance = Config.grabDistance or 2.4,
                    onSelect = function() tryGrab(gateInReach()) end,
                })
            end,
            function()
                exports.bs19_target:AddModel(models, {
                    label = 'Push gate',
                    distance = Config.grabDistance or 2.4,
                    onSelect = function() tryGrab(gateInReach()) end,
                })
            end,
        }) do
            if pcall(try) then done = true break end
        end
    end

    --[[ If the target script is running but we could not hook into it -
         wrong export name, different version - then falling back to hold E
         means you still have a working gate. Without this you get neither:
         no target option because the hook failed, and no prompt because we
         thought we were in target mode. ]]
    if not done then
        print(('[push_gates] couldnt hook into %s, falling back to hold E'):format(mode))
        mode = 'hold'
        hooked[mode] = nil
    end
end

CreateThread(function()
    Wait(2500)
    SetupTarget()
    print(('[push_gates] ready - grab method: %s%s'):format(mode,
        mode == 'hold' and ' (hold E near a gate)' or ''))
end)

-- ============================================================
-- TIDY UP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    if held then stopAnim() end
    restoreProps(PlayerPedId())
    SetNuiFocus(false, false)

    -- put every gate back where the map had it and hand it back to the engine
    for _, gate in pairs(scanned) do
        if DoesEntityExist(gate.obj) then
            SetEntityCoordsNoOffset(gate.obj, gate.base.x, gate.base.y, gate.base.z,
                false, false, false)
            FreezeEntityPosition(gate.obj, false)
        end
    end
end)

-- shared with menu.lua and commands.lua
PG = {
    scanned    = function() return scanned end,
    ratios     = function() return ratios end,
    inReach    = gateInReach,
    railFor    = railFor,
    animAt     = animAt,
    playAnim   = playAnim,
    setAnim    = function(i, a) animPick, animIndex, animChecked = a, i, true end,
    stopAnim   = stopAnim,
    isHeld     = function() return held ~= nil end,
    animIndex  = function() return animIndex end,
    resetShown = function(k) shown[k] = 0.0 end,
    setupTarget = function() SetupTarget() end,
    mode       = function() return mode end,
    known      = knownModel,
    defFor     = function(hash)
        local e = modelDefs[hash]
        if e then return e.name, e.def end
        local a = autoDefs[hash]
        if a and a ~= false then return a.name, a.def end
        return nil
    end,
    archName   = function(obj) return archName(obj) end,

    --- Every configured animation with whether it is actually on this build,
    --- so the debug panel can grey out the ones that will never play.
    animList   = function()
        local out = {}
        for i, a in ipairs(Config.anim or {}) do
            out[i] = {
                dict = a.dict,
                clip = a.clip,
                missing = not DoesAnimDictExist(a.dict),
                on = (i == animIndex),
            }
        end
        return out
    end,
}
