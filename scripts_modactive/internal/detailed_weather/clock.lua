-- The time in whole milliseconds, for Detailed Weather's time budgets ("at most 2 ms of this a
-- frame") and its timers.
--
-- On Windows dfhack.getTickCount() is the system's GetTickCount(), which moves in steps of about
-- 15.6 ms. A budget timed with it ran until the clock's next step, up to 15.6 ms however little was
-- asked for, and several budgets run in a frame: stalls while panning and changing level or look,
-- and stage times of exactly 16 and 32 ms in `detailed_weather details` (found and measured on
-- Windows by grungeisdead). os.clock() there is the time since the game started, to the
-- millisecond. On Linux and macOS os.clock() counts processor time instead, across all the game's
-- threads, which is no use for this, and dfhack.getTickCount() is already to the millisecond.
--
-- Every part of the mod takes its time from here, so times kept by one part and compared by
-- another (when a block's snow is next due, say) are on the same clock.
--@ module = true

local function since_start_ms() return math.floor(os.clock() * 1000) end

local on_windows = dfhack.getOSType and dfhack.getOSType() == 'windows'

ms = on_windows and since_start_ms or dfhack.getTickCount
