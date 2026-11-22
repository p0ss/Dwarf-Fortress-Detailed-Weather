-- The time a frame that Detailed Weather's background work shares: reading the map for plans,
-- and making textures. (Drawing what's already worked out isn't counted: it has to happen every
-- frame whatever it costs.)
--
-- Each part used to have its own few milliseconds a frame, which is fine while one part is busy;
-- but a pan onto new snowy woodland made them all busy at once, and their times added up to several
-- times what any one of them was meant to take. Now they draw on one pool:
--
--     local allowed_ms = work_time.take(wanted_ms)   -- before the work
--     ... the work, for at most allowed_ms ...
--     work_time.done()                               -- after it
--
-- take() gives what was asked for while the pool lasts, then less, then nothing. The parts run in
-- a fixed order each frame (detailed_weather.lua), so the first ones would always drain the pool
-- and the last ones never work; so each stage of the frame is also sure of STAGE_LEAST_MS of its
-- own, however little is left. The work is charged from take() to done(); a take() or the end of
-- the stage also ends whatever was still under way, so a missed done() only overcharges.
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)

POOL_MS = POOL_MS or 6                  -- background work a frame, all parts together
STAGE_LEAST_MS = STAGE_LEAST_MS or 1    -- what each stage may do even with the pool used up

-- frames = frames drawn; used_up = frames that ended with the pool spent; work_ms = work charged
stats = stats or {frames = 0, used_up = 0, work_ms = 0}

local pool_left = POOL_MS
local stage_left = 0
local working_since   -- clock ms when the work under way was taken; nil between pieces of work

function done()
    if not working_since then return end
    local took = clock_ms() - working_since
    working_since = nil
    pool_left, stage_left = pool_left - took, stage_left - took
    stats.work_ms = stats.work_ms + took
end

function start_frame()
    done()
    stats.frames = stats.frames + 1
    if pool_left <= 0 then stats.used_up = stats.used_up + 1 end
    pool_left, stage_left = POOL_MS, 0
end

function start_stage()
    done()
    stage_left = STAGE_LEAST_MS
end

-- How long the work about to start may take, in ms: wanted_ms, or what's left if that's less.
function take(wanted_ms)
    done()
    working_since = clock_ms()
    return math.min(wanted_ms, math.max(pool_left, stage_left, 0))
end
