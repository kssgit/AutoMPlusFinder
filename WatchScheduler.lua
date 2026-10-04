local _, ns = ...

-- No timers or game APIs here: only a real input handler may call Begin().
function ns.NewWatchScheduler(clock)
    local s = { enabled = false, pending = false, nextAt = 0, failures = 0,
        interval = 30, timeout = 20, maxBackoff = 300 }

    function s:SetInterval(value)
        value = tonumber(value)
        if not value or value ~= value then return self.interval end
        value = math.max(10, math.min(300, math.floor(value)))
        if self.interval ~= value then
            self.interval = value
            -- Changing the setting must never bypass a pending cooldown/backoff.
            if self.enabled or self.pending then
                self.nextAt = math.max(self.nextAt, clock() + value)
            end
        end
        return self.interval
    end

    function s:Start()
        self.enabled = true
        -- Preserve an existing cooldown across repeated stop/start clicks.
    end

    function s:Stop()
        self.enabled = false
    end

    function s:Fail()
        if not self.pending then return end
        self.pending = false
        self.failures = math.min(self.failures + 1, 5)
        self.nextAt = clock() + math.min(self.maxBackoff, self.interval * 2 ^ self.failures)
    end

    function s:Tick()
        if self.pending and clock() - self.startedAt >= self.timeout then
            self:Fail()
        end
    end

    function s:Ready()
        self:Tick()
        return self.enabled and not self.pending and clock() >= self.nextAt
    end

    function s:Begin()
        if not self:Ready() then return false end
        self.pending = true
        self.startedAt = clock()
        self.nextAt = clock() + self.interval
        return true
    end

    function s:Success()
        if not self.pending then return false end
        self.pending = false
        self.failures = 0
        self.nextAt = clock() + self.interval
        return true
    end

    return s
end
