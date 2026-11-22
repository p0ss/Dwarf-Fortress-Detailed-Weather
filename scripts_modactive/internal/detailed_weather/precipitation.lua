-- How hard it's raining or snowing, for Detailed Weather. The game only says whether rain or snow
-- is falling on each part of the map; how hard is worked out here, one level for the whole map:
--
--   1 drizzle / light snow   2 steady rain / snow   3 heavy rain / snow   4 a rainstorm / blizzard
--
-- The level comes from what the game itself keeps about the weather:
--   how much of the sky   the game's weather is a 5x5 grid of cells round the fort, each clear,
--                         raining or snowing. Fewer than STEADY_FROM_CELLS falling is level 1,
--                         more is level 2.
--   thick cloud           a weather front over the fort, or stratus or cumulus at 2 or more, makes
--                         it a level harder: heavy rain comes from the heavy cloud the hover box
--                         names.
--   wind                  a strong wind or a gale makes it a level harder again, and is the only
--                         way to level 4: a storm or a blizzard is rain or snow with wind. Under
--                         thick cloud, or with most of the sky falling (MOST_CELLS), wind makes a
--                         storm of it outright.
-- Two forts logged for some 200 game days each (tools/dfhack/weather_watch.lua) are behind this.
-- In one, 3 to 9 cells rained at a time and there was no cloud 98% of the time: mostly steady
-- rain, sometimes drizzle. In the other the whole grid rained whenever any of it did, under thick
-- cloud about half the time: steady and heavy rain in turn, and a storm about an eighth of the
-- time. (So how much of the sky is falling can't tell heavy from steady, as it first did: in the
-- second fort it never changed.)
-- and it builds: a spell is at most one level harder every BUILD_TICKS since it began, so a storm
-- comes on over a few days and doesn't start at full strength. (A game day passes in about twelve
-- seconds at normal speed, and spells of rain last from days to weeks; a level every two hours,
-- as it first was, went from nothing to heavy rain in two seconds: Poss. How long a spell has
-- lasted is kept in the save: THE SPELL SAVED, below.)
--@ module = true

local wind = reqscript('internal/detailed_weather/wind')
local grass = reqscript('internal/detailed_weather/grass')   -- (GROUND WEATHER)

LIGHTEST, HARDEST = 1, 4
local HEAVY = 3   -- as hard as it gets without wind
-- for the status: 'Weather  heavy rain'
NAMES = {
    rain = {'drizzle', 'rain', 'heavy rain', 'a rainstorm'},
    snow = {'light snow', 'snow', 'heavy snow', 'a blizzard'},
}
-- for the hover box: 'raining heavily; breezy wind from the east'
FALLING = {
    rain = {'drizzling', 'raining', 'raining heavily', 'pouring with rain'},
    snow = {'snowing lightly', 'snowing', 'snowing heavily', 'a blizzard blowing'},
}

local STEADY_FROM_CELLS = 5   -- of the weather grid's 25 cells with rain or snow
local MOST_CELLS = 13         -- more than half of them
local STRONG_WIND = 0.9       -- wind strength from which it's strong (as the grass's hard lean)
local BUILD_TICKS = 1200      -- a game day
local SPELL_GAP_TICKS = 300   -- rain or snow back within this long is the same spell carrying on
local TICKS_PER_YEAR = 403200

forced = forced or {}    -- `detailed_weather rain N` / `snow N`: a level for each, for testing
spell = spell or nil     -- the spell of rain or snow now: {started =, dry_since =} in game ticks

-- THE SPELL SAVED (grungeisdead's copy, 2026-11-20). The spell lived only in this script, so a fort
-- loaded in the rain started again at drizzle and built up a level a game day (in play: no rain seen
-- in a minute paused, as no ticks pass, and heavy rain only some 25 s after unpausing; the drizzle
-- sheet has something drawn in 26% of its tiles). It's now kept in the fort's own DFHack data
-- (dfhack.persistent site data: held in memory, written into the save when the game saves), saved
-- whenever it changes and read back at the first look after a fort loads. Both times are absolute game
-- ticks (now_ticks), so they mean the same after a load. Where there is no site to keep it in
-- (adventure mode), it goes unsaved as before.
local SPELL_KEY = 'detailed_weather_spell'
spell_loaded = spell_loaded or false   -- read back from the fort's data yet (forget empties it)
local function load_spell()
    spell_loaded = true
    local ok, saved = pcall(dfhack.persistent.getSiteData, SPELL_KEY)
    if ok and type(saved) == 'table' and type(saved.started) == 'number' then
        spell = {started = saved.started, dry_since = type(saved.dry_since) == 'number' and saved.dry_since or nil}
    end
end
local function save_spell()
    pcall(function()
        if spell then
            dfhack.persistent.saveSiteData(SPELL_KEY, {started = spell.started, dry_since = spell.dry_since})
        else
            dfhack.persistent.deleteSiteData(SPELL_KEY)
        end
    end)
end

local function fort_clouds()
    local map = df.global.world.map
    return df.global.world.world_data.region_map[map.region_x // 16]:_displace(map.region_y // 16).clouds
end

function thick_cloud()
    local clouds = fort_clouds()
    return clouds.front > 0 or clouds.stratus >= 2 or clouds.cumulus >= 2
end

-- The clouds over the fort in words, for the hover box: 'nimbostratus, a cold front', or nil for
-- none. (The game's own cloud types for the fort's world tile; most of the time there are none,
-- rain or no rain.)
local FRONTS = {'a warm front', 'a cold front', 'an occluded front'}
local CUMULUS = {'cumulus', 'towering cumulus', 'cumulonimbus'}
local STRATUS = {'altostratus', 'stratus', 'nimbostratus'}
function clouds_in_words()
    local clouds = fort_clouds()
    local words = {}
    words[#words + 1] = STRATUS[clouds.stratus]
    words[#words + 1] = CUMULUS[clouds.cumulus]
    if clouds.cirrus then words[#words + 1] = 'cirrus' end
    words[#words + 1] = FRONTS[clouds.front]
    return #words > 0 and table.concat(words, ', ') or nil
end

local function now_ticks() return df.global.cur_year * TICKS_PER_YEAR + df.global.cur_year_tick end

-- How many of the game's 5x5 weather cells round the fort have rain or snow falling.
function falling_cells()
    local cells = 0
    local grid = df.global.current_weather
    for x = 0, 4 do
        for y = 0, 4 do
            local weather = grid[x][y]
            if weather == df.weather_type.Rain or weather == df.weather_type.Snow then cells = cells + 1 end
        end
    end
    return cells
end

-- Whether rain or snow is falling anywhere on the map itself, for timing a spell: the map is only
-- part of the grid, so it's sampled at SAMPLES x SAMPLES points, again every RECHECK_TICKS.
-- (wetness.lua samples the same way, for the share of the map rain alone is falling on.)
local SAMPLES = 4
local RECHECK_TICKS = 50
local falling_now, falling_checked = false, nil
local function falling()
    local ticks = now_ticks()
    if falling_checked and ticks >= falling_checked and ticks - falling_checked < RECHECK_TICKS then return falling_now end
    falling_checked, falling_now = ticks, false
    local map = df.global.world.map
    local sky = map.z_count - 1
    for i = 0, SAMPLES - 1 do
        for j = 0, SAMPLES - 1 do
            local x = math.floor((i + 0.5) * map.x_count / SAMPLES)
            local y = math.floor((j + 0.5) * map.y_count / SAMPLES)
            -- (GROUND WEATHER, grass.lua: where the rain lands, not the sky's own biome)
            local weather = grass.ground_weather(x, y, sky)
            if weather == df.weather_type.Rain or weather == df.weather_type.Snow then falling_now = true end
        end
    end
    return falling_now
end

-- How long it has been raining or snowing on the map, in game ticks (0 when it isn't). A spell
-- ends once the map has been seen dry for SPELL_GAP_TICKS; time nobody was looking (the overlay
-- isn't drawn behind a full-screen menu) counts as part of the spell if it's still falling after.
local function spell_ticks()
    if not spell_loaded then load_spell() end   -- (THE SPELL SAVED)
    local now = now_ticks()
    if not falling() then
        if spell and not spell.dry_since then spell.dry_since = now save_spell() end
        return 0
    end
    local ended = spell and spell.dry_since and now - spell.dry_since > SPELL_GAP_TICKS
    if not spell or ended or now < spell.started then
        spell = {started = now}
        save_spell()
    elseif spell.dry_since then
        spell.dry_since = nil   -- (back within the gap: the same spell carrying on)
        save_spell()
    end
    return now - spell.started
end

-- The level now, 1 to 4, for kind 'rain' or 'snow' (they differ only in what's been forced).
-- full_strength: don't wait for the spell to build (weather forced on for testing has no spell
-- to time).
function level(kind, full_strength)
    if forced[kind] then return forced[kind] end
    local cells = falling_cells()
    local by_sky = cells >= STEADY_FROM_CELLS and 2 or LIGHTEST
    local thick = thick_cloud()
    local wanted = math.min(by_sky + (thick and 1 or 0), HEAVY)
    local _, _, strength = wind.get()
    if strength >= STRONG_WIND then
        wanted = (thick or cells >= MOST_CELLS) and HARDEST or wanted + 1
    end
    local built = full_strength and HARDEST or LIGHTEST + spell_ticks() // BUILD_TICKS
    return math.min(wanted, built, HARDEST)
end

-- A world unloading: the next fort's spell is read from its own data (THE SPELL SAVED).
function forget() spell, spell_loaded = nil, false end

function describe()
    local _, _, strength = wind.get()
    local forced_note = (forced.rain and (', rain forced to ' .. forced.rain) or '')
        .. (forced.snow and (', snow forced to ' .. forced.snow) or '')
    return ('level %d%s (%d of 25 weather cells falling, thick cloud %s, wind %.2f, falling for %.1f days)'):format(
        level(), forced_note, falling_cells(), thick_cloud() and 'yes' or 'no', strength,
        (dfhack.isMapLoaded() and spell_ticks() or 0) / 1200)
end
