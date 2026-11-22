-- The wind for Detailed Weather, from how the game's clouds drift over the world map.
--
-- The game keeps clouds per world tile (region_map[x][y].clouds) and moves them across the world,
-- but its own wind flags stay unset and the windmills always face the same way. Watching the
-- clouds round the fort showed the field shifting a world tile at a time, the same way, in some
-- hours, and in others staying put and only changing shape; whole weeks were near still and others
-- breezy (tools/dfhack/cloud_drift.lua). So:
--
--   - once an in-game hour, the cloud cover of the GRID x GRID world tiles round the fort is noted
--   - it's compared with the last hour's: the shift (up to MOST_SHIFT tiles each way) that lines
--     the two up best is how far the clouds moved, if it beats staying put
--   - the last HISTORY_HOURS of these give the wind: its direction is the way the clouds have been
--     moving, its strength how much (STRONG_DRIFT world tiles an hour on average is strength 1)
--   - with no clouds to watch, the wind keeps its direction and fades slowly to calm
--   - what the effects see eases towards that, so the wind picks up, drops and turns gradually
--
-- The wind is given as x, y (screen directions: +x east, +y south) of length `strength`: 0 calm,
-- 1 strong, up to 1.5 a gale.
--@ module = true

local GRID_RADIUS = 10        -- world tiles each side of the fort: a 21 x 21 grid
-- world tiles the clouds can be found to have moved in an hour: they move a tile at a time, and
-- 2-tile 'moves' were the field reforming (mostly east, against the drift)
local MOST_SHIFT = 1
local HISTORY_HOURS = 24
-- world tiles an hour, averaged over the history, for strength 1. Replayed over 7 months of the
-- test fort's clouds this gives calm 60% of the time, light 13%, breezy 12%, strong 6%, gale 7%
local STRONG_DRIFT = 0.5
local BEATS_STILL = 1.05      -- how much better a shift must line up than staying put
local TICKS_PER_HOUR = 50
local EASE_PER_SECOND = 0.15  -- share of the way to the new wind the effects move each second
local CALM_FADE = 0.97        -- each hour without clouds to watch, the wind keeps this much

-- forced: nil, or {x =, y =} set by `detailed_weather wind ...`
state = state or {last_grid = nil, last_hour = nil, history = {}, target = {x = 0, y = 0},
                  now = {x = 0, y = 0}, forced = nil, last_clock = nil, clouds_seen = false}

local function cloud_amount(clouds)
    return clouds.cumulus + clouds.stratus + clouds.front * 2 + (clouds.cirrus and 1 or 0)
        + (clouds.fog > 0 and 1 or 0)
end

-- The cloud cover round the fort: grid[row][col], rows north to south, 0 off the world's edge.
local function cloud_grid()
    local world = df.global.world
    local data = world.world_data
    local fort_x, fort_y = world.map.region_x // 16, world.map.region_y // 16
    local grid, total = {}, 0
    for row = -GRID_RADIUS, GRID_RADIUS do
        local cells = {}
        for col = -GRID_RADIUS, GRID_RADIUS do
            local x, y = fort_x + col, fort_y + row
            local amount = 0
            if x >= 0 and y >= 0 and x < data.world_width and y < data.world_height then
                amount = cloud_amount(data.region_map[x]:_displace(y).clouds)
            end
            cells[#cells + 1] = amount
            total = total + amount
        end
        grid[#grid + 1] = cells
    end
    return grid, total
end

-- How well two grids line up with `after` moved (dx, dy) from `before`: the mean product over
-- the cells they share.
local function match(before, after, dx, dy)
    local size = #before
    local sum, count = 0, 0
    for row = 1, size do
        for col = 1, size do
            local r2, c2 = row + dy, col + dx
            if r2 >= 1 and r2 <= size and c2 >= 1 and c2 <= size then
                sum, count = sum + before[row][col] * after[r2][c2], count + 1
            end
        end
    end
    return count > 0 and sum / count or 0
end

-- How far the clouds moved between two grids: dx, dy in world tiles (0, 0 if they stayed put).
local function drift(before, after)
    local still = match(before, after, 0, 0)
    local best, best_dx, best_dy = still * BEATS_STILL, 0, 0
    for dy = -MOST_SHIFT, MOST_SHIFT do
        for dx = -MOST_SHIFT, MOST_SHIFT do
            if dx ~= 0 or dy ~= 0 then
                local score = match(before, after, dx, dy)
                if score > best then best, best_dx, best_dy = score, dx, dy end
            end
        end
    end
    return best_dx, best_dy
end

local function length(v) return math.sqrt(v.x * v.x + v.y * v.y) end

-- Once an in-game hour: note the clouds, and work out the wind they've shown.
local function hourly()
    local grid, total = cloud_grid()
    local map = df.global.world.map
    local origin = map.region_x // 16 .. ',' .. map.region_y // 16
    -- an adventurer's map moves with them, and the grid round it with it: a grid from before a move
    -- would read their walk as the clouds drifting, so it's set aside and the watching starts again
    local last = state.last_origin == origin and state.last_grid or nil
    state.last_grid, state.last_origin = grid, origin
    state.clouds_seen = total > 0
    local history = state.history
    if last and total > 0 then
        local dx, dy = drift(last, grid)
        history[#history + 1] = {x = dx, y = dy}
        while #history > HISTORY_HOURS do table.remove(history, 1) end
    end
    if total == 0 or #history == 0 then
        state.target.x, state.target.y = state.target.x * CALM_FADE, state.target.y * CALM_FADE
        return
    end
    local sx, sy = 0, 0
    for _, step in ipairs(history) do sx, sy = sx + step.x, sy + step.y end
    local mean = {x = sx / #history, y = sy / #history}
    local drift_rate = length(mean)
    local strength = math.min(1.5, drift_rate / STRONG_DRIFT)
    if drift_rate > 0 then
        state.target.x, state.target.y = mean.x / drift_rate * strength, mean.y / drift_rate * strength
    else
        state.target.x, state.target.y = 0, 0
    end
end

-- Call every frame: does the hourly look when an hour has passed, and eases the wind the effects
-- see towards the latest, on real time.
function update()
    if not dfhack.isMapLoaded() then return end
    local hour = df.global.cur_year_tick // TICKS_PER_HOUR
    if hour ~= state.last_hour then
        state.last_hour = hour
        hourly()
    end
    local clock = dfhack.getTickCount()
    local seconds = state.last_clock and math.min(clock - state.last_clock, 500) / 1000 or 0
    state.last_clock = clock
    local target = state.forced or state.target
    local share = 1 - (1 - EASE_PER_SECOND) ^ seconds
    state.now.x = state.now.x + (target.x - state.now.x) * share
    state.now.y = state.now.y + (target.y - state.now.y) * share
end

-- The wind now: x, y (+x east, +y south), and its strength (0 calm, 1 strong).
function get()
    return state.now.x, state.now.y, length(state.now)
end

-- Force a wind for testing: strength 0-1.5 towards `towards` ('east', 'west', 'north', 'south'),
-- or nil to go back to the clouds.
local TOWARDS = {east = {1, 0}, west = {-1, 0}, north = {0, -1}, south = {0, 1}}
function force(strength, towards)
    if not strength then state.forced = nil return end
    local d = TOWARDS[towards or 'east'] or TOWARDS.east
    state.forced = {x = d[1] * strength, y = d[2] * strength}
end

-- The wind in a few words, e.g. 'breezy from the west'.
function summary()
    local x, y, strength = get()
    local feel = strength < 0.15 and 'calm' or strength < 0.5 and 'light' or strength < 1 and 'breezy'
        or strength < 1.3 and 'strong' or 'a gale'
    if strength < 0.15 then return feel end
    local names = {}
    if y < -0.1 * strength then names[#names + 1] = 'south' elseif y > 0.1 * strength then names[#names + 1] = 'north' end
    if x < -0.1 * strength then names[#names + 1] = 'east' elseif x > 0.1 * strength then names[#names + 1] = 'west' end
    return feel .. ' from the ' .. table.concat(names, '-')
end

function is_forced() return state.forced ~= nil end

-- The wind in words, with how it was found, for the details.
function describe()
    local x, y, strength = get()
    local feel = strength < 0.15 and 'calm' or strength < 0.5 and 'light' or strength < 1 and 'breezy'
        or strength < 1.3 and 'strong' or 'a gale'
    local from = ''
    if strength >= 0.15 then
        local names = {}
        if y < -0.1 * strength then names[#names + 1] = 'south' elseif y > 0.1 * strength then names[#names + 1] = 'north' end
        if x < -0.1 * strength then names[#names + 1] = 'east' elseif x > 0.1 * strength then names[#names + 1] = 'west' end
        from = ' from the ' .. table.concat(names, '-')
    end
    local moved = 0
    for _, step in ipairs(state.history) do if step.x ~= 0 or step.y ~= 0 then moved = moved + 1 end end
    local source = state.forced and 'forced' or ('clouds moved in %d of the last %d hours%s'):format(
        moved, #state.history, state.clouds_seen and '' or ', none in sight now')
    return ('%s%s (strength %.2f; %s)'):format(feel, from, strength, source)
end

-- Another map loading: the clouds watched were over the old one. A forced wind is kept.
function forget_world()
    state.last_grid, state.last_origin, state.last_hour, state.history = nil, nil, nil, {}
    state.target, state.now, state.last_clock, state.clouds_seen = {x = 0, y = 0}, {x = 0, y = 0}, nil, false
end
