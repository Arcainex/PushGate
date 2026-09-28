--[[
    push_gates - chat commands
    the same things the menu does, for people who prefer typing
    by XanderP  -  discord.gg/cMqazwj6c7
]]

local function reach()
    local g = PG.inReach()
    if not g then print('[push_gates] stand next to a gate first') end
    return g
end

RegisterCommand('gateinfo', function()
    local g = reach()
    if not g then
        print('[push_gates] gates near you:')
        for _, x in pairs(PG.scanned()) do
            print(('   %s  %.0f%% open'):format(x.name, math.abs((PG.ratios()[x.key] or 0)) * 100))
        end
        return
    end

    print(('[push_gates] %s'):format(g.name))
    print(('   key     %s'):format(g.key))
    print(('   travel  %.1fm on %s'):format(g.def.travel or 5.0, g.def.axis or 'right'))
    print(('   open    %.0f%%'):format(math.abs((PG.ratios()[g.key] or 0)) * 100))
    print('   there is no open direction to set - push it whichever way you want')
end, false)

RegisterCommand('gatetravel', function(_, args)
    local g = reach()
    if not g then return end

    local n = tonumber(args and args[1])
    if not n then
        print(('[push_gates] %s travels %.1fm. use /gatetravel 6.5'):format(
            g.name, g.def.travel or 5.0))
        return
    end

    g.def.travel = math.max(0.5, math.min(30.0, n))
    print(("[push_gates] ['%s'] = { travel = %.1f, axis = '%s' },"):format(
        g.name, g.def.travel, g.def.axis or 'right'))
end, false)

RegisterCommand('gateaxis', function()
    local g = reach()
    if not g then return end

    g.def.axis = (g.def.axis == 'forward') and 'right' or 'forward'
    g.rail = PG.railFor(g.obj, g.def)
    PG.resetShown(g.key)
    TriggerServerEvent('push_gates:push', g.key, 0.0)

    print(("[push_gates] ['%s'] = { travel = %.1f, axis = '%s' },"):format(
        g.name, g.def.travel or 5.0, g.def.axis))
end, false)

RegisterCommand('gateanim', function(_, args)
    local list = Config.anim or {}
    if #list == 0 then print('[push_gates] no animations configured') return end

    local start = tonumber(args and args[1]) or (PG.animIndex() + 1)

    for step = 0, #list - 1 do
        local i = ((start - 1 + step) % #list) + 1
        local a = PG.animAt(i)
        if a then
            PG.setAnim(i, a)
            PG.playAnim(a)
            print(('[push_gates] %d/%d  %s / %s'):format(i, #list, a.dict, a.clip))
            return
        end
        print(('[push_gates] %d/%d %s / %s isnt on this build'):format(
            i, #list, list[i].dict, list[i].clip))
    end
end, false)

-- Fast visual comparison without a resource restart. Use 0 to see whether
-- IK alone can hold the hands against the gate, 1 for chest-level carry,
-- 2/3 for the original push clips.
RegisterCommand('gatepose', function(_, args)
    local n = tonumber(args and args[1])
    if n == nil then
        print('[push_gates] /gatepose 0 (IK only), 1 (chest grip), 2/3 (old push clips)')
        return
    end
    if n < 0 or n > 3 or n ~= math.floor(n) then return end
    PG.stopAnim()
    if n == 0 then
        PG.setAnim(0, nil)
        print('[push_gates] pose: IK only')
        return
    end
    local a = PG.animAt(n)
    if not a then
        print(('[push_gates] pose %d unavailable on this build'):format(n))
        return
    end
    PG.setAnim(n, a)
    if PG.isHeld() then PG.playAnim(a) end
    print(('[push_gates] pose %d: %s / %s'):format(n, a.dict, a.clip))
end, false)

RegisterCommand('gategripdebug', function()
    Config.gripDebug = not Config.gripDebug
    print(('[push_gates] hand-target markers %s'):format(
        Config.gripDebug and 'ON (red left, green right)' or 'OFF'))
end, false)

--[[ When somebody says "theres no prompt at my gate" it is almost always
     because the model is not recognised, so the script never saw it. This
     lists everything stood around you and says which ones it knows about,
     with a line you can paste into the config for the ones it does not. ]]
RegisterCommand('gatescan', function(_, args)
    local at = GetEntityCoords(PlayerPedId())
    local radius = tonumber(args and args[1]) or 8.0

    local seen, ent = {}, {}

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) then
            local d = #(at - GetEntityCoords(obj))
            if d <= radius then
                local hash = GetEntityModel(obj)
                if not seen[hash] or d < seen[hash] then
                    seen[hash] = d
                    -- the model NAME comes off an entity, not a hash, so the
                    -- entity has to be kept as well
                    ent[hash] = obj
                end
            end
        end
    end

    print(('[push_gates] objects within %.1fm:'):format(radius))

    local any = false
    for hash, d in pairs(seen) do
        any = true
        local known = PG.defFor(hash)
        local real  = PG.archName(ent[hash])

        if known then
            print(('   %.1fm  %s  - gate'):format(d, real or known))
        elseif real then
            print(('   %.1fm  %s  - NOT a gate. to add it:'):format(d, real))
            print(("        ['%s'] = {},"):format(real))
        else
            print(('   %.1fm  hash %d  - not a gate, and this build will not '
                .. 'tell me its name'):format(d, hash))
        end
    end

    if not any then print('   nothing here') end

    local n = 0
    for _ in pairs(PG.scanned()) do n = n + 1 end

    print('[push_gates] grab method right now: ' .. PG.mode())
    print(('[push_gates] gates being tracked: %d'):format(n))
end, false)
