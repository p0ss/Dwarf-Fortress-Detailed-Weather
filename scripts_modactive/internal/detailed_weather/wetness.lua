-- How wet the map is, for Detailed Weather: 0 (dry) to 1 (wet), one value for the map, as the
-- look's colour is. Its resting point is the climate (the region's rainfall: a savanna sits dry,
-- a rainforest wet); rain on the map soaks it towards wet over a few days (light rain only part
-- way: drenched takes heavy rain), and afterwards it
-- dries back over about ten, faster in the heat. Game time, so it stops when the game's paused.
-- Not saved: a loaded fort starts at its climate's.
--@ module = true

local grass = reqscript('internal/detailed_weather/grass')   -- (GROUND WEATHER)

local RAIN_SOAK_DAYS = 3      -- rain takes it from dry to wet in about this (a shower only darkens it a step)
local DRY_DAYS = 10           -- and it dries back over about this, at mild temperatures
local HOT_DRYING = 1.0        -- in full heat it dries this much faster again
local LIGHT_RAIN_WET = 0.7    -- light rain soaks it only this far (a step short of drenched:
                              -- that takes heavy rain)
local LIGHT_RAIN_RATE = 0.5   -- and at this share of heavy rain's rate
local TICKS_PER_DAY = 1200
local TICKS_PER_YEAR = 403200

forced = forced or nil   -- `detailed_weather wetness ...`: a level, for testing
state = state or nil     -- {level, last}

-- The climate's level: the fort's region's rainfall (0-100) as 0-1.
function climate()
    local map = df.global.world.map
    local pos = xyz2pos(map.x_count // 2, map.y_count // 2, map.z_count - 1)   -- the sky: its block always exists
    local rx, ry = dfhack.maps.getTileBiomeRgn(pos)
    local region = rx and df.global.world.world_data.region_map[rx]:_displace(ry)
    return region and region.rainfall / 100 or 0.5
end

local function now_ticks() return df.global.cur_year * TICKS_PER_YEAR + df.global.cur_year_tick end

-- How much of the map it's raining on, 0 to 1: the game's weather is patchy (a grid of cells
-- round the fort), and the ground's look is one for the whole map, so a shower over part of it
-- soaks the ground that much more slowly. Sampled at RAIN_SAMPLES x RAIN_SAMPLES points over
-- the map, again every RAIN_RECHECK_TICKS.
local RAIN_SAMPLES = 4
local RAIN_RECHECK_TICKS = 50
local rain_share, rain_checked = 0, nil
local function raining()
    local ticks = now_ticks()
    if rain_checked and ticks >= rain_checked and ticks - rain_checked < RAIN_RECHECK_TICKS then return rain_share end
    rain_checked = ticks
    local map = df.global.world.map
    local wet, z = 0, map.z_count - 1
    for i = 0, RAIN_SAMPLES - 1 do
        for j = 0, RAIN_SAMPLES - 1 do
            local x = math.floor((i + 0.5) * map.x_count / RAIN_SAMPLES)
            local y = math.floor((j + 0.5) * map.y_count / RAIN_SAMPLES)
            -- (GROUND WEATHER, grass.lua: where the rain lands, not the sky's own biome)
            if grass.ground_weather(x, y, z) == df.weather_type.Rain then wet = wet + 1 end
        end
    end
    rain_share = wet / (RAIN_SAMPLES * RAIN_SAMPLES)
    return rain_share
end

-- Whether the rain is heavy: a front or thick cloud over the fort (as the rain is drawn heavier).
local function heavy_rain()
    local map = df.global.world.map
    local clouds = df.global.world.world_data.region_map[map.region_x // 16]:_displace(map.region_y // 16).clouds
    return clouds.front > 0 or clouds.stratus >= 2 or clouds.cumulus >= 2
end

-- Moves the level on by the game time since last called. heat: 0 (mild or cold) to 1 (hot).
function update(heat)
    if not dfhack.isMapLoaded() then return end
    local ticks = now_ticks()
    if not state then state = {level = climate(), last = ticks} end
    local days = (ticks - state.last) / TICKS_PER_DAY
    state.last = ticks
    if days <= 0 or days > 30 then return end   -- paused, or a jump (a loaded save)
    local rain = raining()
    local ceiling = rain > 0 and (heavy_rain() and 1 or LIGHT_RAIN_WET) or 0
    if rain > 0 and state.level < ceiling then
        local rate = ceiling < 1 and LIGHT_RAIN_RATE or 1
        state.level = math.min(ceiling, state.level + days / RAIN_SOAK_DAYS * rain * rate)
    else
        -- dry back towards the climate's level, or to what light rain keeps it at
        local target = math.max(climate(), ceiling)
        local step = days / DRY_DAYS * (1 + HOT_DRYING * (heat or 0))
        if state.level > target then state.level = math.max(target, state.level - step)
        else state.level = math.min(target, state.level + step) end
    end
end

function level()
    if forced then return forced end
    return state and state.level or climate()
end

function forget() state = nil end

function describe()
    local rain = dfhack.isMapLoaded() and raining() or 0
    return ('%.2f%s (climate %.2f%s)'):format(level(), forced and ', forced' or '', climate(),
        rain > 0 and (', raining on %d%% of the map'):format(math.floor(rain * 100 + 0.5)) or '')
end
