-- Last observed player positions. No Roblox APIs; values are immutable Vector3s.
-- Age is time since the player was last observed as an eligible world model,
-- not proof that the server supplied a fresh position at that moment.
local LastSeen = {}

function LastSeen.new(maxAge)
    assert(type(maxAge) == "number" and maxAge > 0, "invalid last-seen lifetime")
    local records = {}
    local tracker = {}

    function tracker.remember(target, character, generation, position, now)
        if not target or not character or not position or type(now) ~= "number" then return end
        local record = records[target]
        if not record then
            record = {}
            records[target] = record
        end
        record.character, record.generation = character, generation
        record.position, record.at = position, now
    end

    function tracker.get(target, character, generation, now)
        local record = records[target]
        if not record then return nil end
        if not character or record.character ~= character or record.generation ~= generation
            or type(now) ~= "number" or now < record.at or now - record.at > maxAge then
            records[target] = nil
            return nil
        end
        return record.position, now - record.at
    end

    function tracker.forget(target)
        records[target] = nil
    end

    function tracker.clear()
        records = {}
    end

    return tracker
end

return LastSeen
