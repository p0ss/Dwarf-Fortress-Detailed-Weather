-- Shows the weather and wear the game simulates but graphics mode leaves out.
--[====[

detailed_weather
================

Tags: fort | graphics | map

Command: "detailed_weather"

  Shows the weather and wear the game simulates but graphics mode leaves out.

Part of the Detailed Weather mod, which needs Detailed Landscapes. It draws rain, snow, fog, falling leaves in autumn and blossom in spring, and gives the ground a look that follows the weather: darker after rain, paler and cracked in a dry spell, rimed in a hard freeze, warmer in the heat. Snow settles on ramps, grass wears into paths where dwarves walk, roofs and tree canopies cast shade, fallen fruit and nuts sit down in the grass, and in a strong wind gusts pass through the grass. The wind comes from how the game's clouds move. Underground keeps its own colours.

It all runs by itself as overlays (detailed_weather.rain, detailed_weather.map_drawn and detailed_weather.tile_info, on by default; see gui/overlay). The command shows what it's doing and can turn parts off, or force the weather to try it out. Hovering over a tile adds its grass, snow, temperature and weather to the hover box, and any leaves or petals falling there.

Usage
-----

    detailed_weather
        Show the weather, wind and ground look it's drawing, and any parts turned off.
    detailed_weather details
        The same in full, with how long each part takes (for working on the mod).
    detailed_weather rain|snow [1|2|3|4], off, auto
        Draw rain or snow everywhere, no rain or snow, or follow the game's weather (default). A number sets how hard it falls, from 1 (drizzle, light snow) to 4 (a rainstorm, a blizzard).
    detailed_weather fog 1|2|3|off|auto
        Mist, fog or thick fog everywhere, none, or the game's fog at the fort (default).
    detailed_weather leaves 1|2|3|off|auto
        Few, some or many leaves falling from deciduous trees whatever the season, none, or in late autumn as the trees shed (default).
    detailed_weather petals 1|2|3|off|auto
        The same for petals falling from fruit and nut trees, in their blossom's colour: whatever the season, none, or late in spring as the blossom gives way to fruit (default).
    detailed_weather wind calm|light|breezy|strong|gale [east|west|north|south]
    detailed_weather wind auto
        Force a wind (it blows east if no direction is given), or follow the clouds (default).
    detailed_weather wetness dry|average|wet|<0-1>|auto
        Force how wet the ground looks, or follow the climate and the rain (default).
    detailed_weather colour <-5 to 4>|auto
        Force the ground's look from coldest (-5) to hottest (4), or follow the temperature (default).
    detailed_weather profile off|low|medium|high
        Set every part at once. high draws everything. medium (the default, unless you've set something yourself) keeps the whole picture but still: trees in the look's colours without the sway, grass that leans without the sweeping gusts, and no fruit set into the grass. low is for slower machines: the ground's look, rain, snow and fog, falling leaves and blossom, and snow and the ground's look on ramps; trees and buildings keep the game's own colours. off draws nothing, which shows the game as it is without the mod.
    detailed_weather settings
        List each part, what it's set to and what that gives you.
    detailed_weather <part> off|low|high
        Set one part; see Settings below for the parts. What you choose is remembered for every fort.
    detailed_weather reload
        Load the art again.

Settings
--------

Each part can be set on its own, and the choices are kept in dfhack-config/detailed_weather.json, so they hold for every fort. low means the part does less work each frame: what it draws fills in a little more slowly as you move the view, and it drops its animation or finer detail where it has any. Parts marked off|high have no low.

colour   off|high       The ground's look by temperature and wetness. Nearly free once loaded; off shows the game's own colours.
weather  off|high       Falling rain and snow.
fog      off|high       Fog and mist.
trees    off|low|high   Trees and buildings in the look's colours. high: branches sway in wind. low: still. off: they keep the game's colours, which won't match the ground. The largest single cost when the view moves.
grass    off|low|high   Grass leaning in the wind. high: gusts sweep across it and the blades rustle. low: the whole field leans together. off: still.
ramps    off|low|high   Snow on ramps.
frost    off|low|high   Ramps drawn in the ground's look, and cracks in dry ground.
paths    off|low|high   Paths worn through grass where dwarves walk.
spatter  off|low|high   Fallen fruit, nuts and leaves on grass. high: set down among the blades. low: thinned and shadowed, lying on top. off: as the game draws them.
shade    off|high       Shade under roofs and tree canopies.
murky    off|high       Stagnant water tinted a pond's green.
leaves   off|high       Leaves falling in autumn.
petals   off|high       Blossom falling in spring.

The medium profile sets: trees, grass, ramps, frost and paths low, and spatter off. The low profile sets: ramps and frost low, and trees, grass, paths, spatter, shade and murky off. Most of the mod's cost comes while the view is moving, so that is where low helps most.

Examples
--------

"detailed_weather profile medium"
    The whole picture without the animation, for when scrolling feels heavy.
"detailed_weather grass off"
    Stop the grass leaning in the wind, and leave the rest as it is.

"detailed_weather rain"
    Make it rain over the whole map, to see it; "detailed_weather auto" goes back to the game's weather.
"detailed_weather wind strong west"
    A strong wind towards the west: rain, snow and leaves slant with it and gusts cross the grass.
"detailed_weather leaves 3"
    Leaves falling thickly under the deciduous trees, whatever the season.

]====]

-- Developer notes. Draws the game's rain and snow in graphics mode, and the snow lying and the
-- temperature on the ground.
--
-- The game decides the weather for each world tile (dfhack.maps.getCurrentWeather), and getting
-- caught in the rain upsets dwarves, but graphics mode doesn't show it. This overlay draws rain on
-- every outdoor tile in view where the game says it's raining: splashes on the ground, ripples on
-- water and a few falling streaks, slanted by the wind. Where it's snowing, it draws flakes
-- drifting down. Lying snow on floors is the game's own, drawn from this mod's art
-- (graphics/images/snow_cover.png); the game never draws snow on ramps, so this draws those
-- (internal/detailed_weather/snow_ramps.lua). Fog, which the game keeps per world tile but never
-- draws, is a drifting haze over every outdoor tile in view (the sheet 'fog', built by
-- tools/weather/make_fog_sheet.py; see there for how it drifts). The ground takes a look by the
-- map's temperature and wetness (internal/detailed_weather/colour.lua and looks.lua): its colour,
-- dry cracks and grain, and when wet rime, after-rain wet or a humid glisten. How wet the map is
-- follows its climate and the rain (wetness.lua). Ramps are redrawn to match
-- (internal/detailed_weather/frost.lua). An older, slower experiment that bakes snow, frost, a
-- temperature tint and heat shimmer into the ground is in internal/detailed_weather/ground.lua,
-- off by default.
--
-- The rain and the falling snow are seamless patches of art (art/rain_N.png and art/snow_N.png, built
-- by tools/weather/make_rain_sheet.py and make_snow_sheet.py) repeated across the map, so streaks
-- and flakes run across tile borders without a break.
--
-- Wind: from how the game's clouds drift over the world map (internal/detailed_weather/wind.lua).
-- It slants the rain and snow, drifts the fog and sends gusts through the grass.
--
--   detailed_weather                  show a short summary
--   detailed_weather details          show everything, with timings
--   detailed_weather rain|snow [1|2|3|4], off, auto
--                                    draw rain or snow everywhere, nothing, or what the game says
--                                    (default); the number forces how hard it falls (1 drizzle or
--                                    light snow to 4 a rainstorm or blizzard), and stays forced
--                                    for the game's own rain or snow until `auto`
--   detailed_weather ramps on|off     snow on snowy ramps (default on)
--   detailed_weather native [stop|start|fog|rain]  the drawing done by the hook DLL
--                                    (dfhooks_detailed_weather.dll): what it has counted; stop hands
--                                    it all back to the Lua; fog and rain turn its fog over water and
--                                    its falling rain and snow off and on
--   detailed_weather install          copy the hook DLL from this mod's folder into DF's now (done by
--                                    itself at a fort's load); it's used from DF's next start
--   detailed_weather uninstall        take it out of DF's folder (from DF's next start)
--   detailed_weather frost on|off     ramps redrawn for the look (default on)
--   detailed_weather frost old on|off  (testing) the old floor effects by each tile's temperature
--   detailed_weather colour on|off|auto|N
--                                    the ground's look (default on); N forces its temperature
--                                    from -4 (coldest) to 4 (hottest), auto follows again
--   detailed_weather shade on|off     the ground under a roof or tree branches in shade (default on)
--   detailed_weather paths on|off     worn paths through grass (default on)
--   detailed_weather spatter on|off   fallen fruit, nuts and leaves on grass drawn in the grass (default on)
--   detailed_weather murky on|off     stagnant water (the game's murky pools) tinted a pond's green (default on)
--   detailed_weather sway on|off      trees' branches swaying in the wind's gusts (default on)
--   detailed_weather leaves 1|2|3|off|auto
--                                    falling leaves under deciduous trees: few, some or many
--                                    whatever the season (for testing), none, or in late autumn
--                                    as the trees shed (default)
--   detailed_weather petals 1|2|3|off|auto
--                                    the same for petals falling from blossoming trees in spring
--   detailed_weather wetness dry|average|wet|N|auto
--                                    force how wet the map is (N from 0 to 1), or follow the
--                                    climate and the rain (default)
--   detailed_weather fog 1|2|3|off|auto
--                                    fog: mist, fog or thick fog everywhere, none, or what the
--                                    game says at the fort (default)
--   detailed_weather ground on|off    the older baked ground experiment (default off)
--   detailed_weather temperature N|auto
--                                    pretend every tile is N C (for testing), or use the game's
--                                    (frost and tint, and the old ground experiment)
--   detailed_weather wind calm|light|breezy|strong|gale [east|west|north|south]|auto
--                                    force a wind for testing, or follow the clouds (default)
--   detailed_weather marker LAYER|off  (testing) paint a translucent magenta square into that screen
--                                    layer (e.g. vehicle) in the middle of the view, to see what
--                                    draws above and below it
--   detailed_weather reload           reload the art, e.g. after rebuilding it
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)
local clock_s = reqscript('internal/detailed_weather/clock').s     -- and in seconds, for timing short work

local overlay = require('plugins.overlay')
local guidm = require('gui.dwarfmode')

local TICKS_PER_FRAME = 8     -- about 12 frames a second at normal speed
local MS_PER_TICK = 10        -- normal speed: the game's 100 ticks a second
local RESCAN_MS = 250         -- how often to work out again where it's raining in view
local FOG_CALM_PX = 6         -- px a second the fog drifts in still air (each px is a visible step)
local FOG_WIND_PX = 25        -- and the more it drifts in a strong wind (strength 1)
local FOG_DEPTH_SLOWING = 0.3 -- each level further down, the fog drifts this much slower (as 1 / (1 + n d))
local FOG_RESCAN_MS = 3000    -- where the outdoor tiles are only changes as the terrain does
local RAMP_RESCAN_MS = 1000   -- snow on ramps changes slowly; a moved view rescans at once
local GROUND_RESCAN_MS = 250  -- and what's on the ground (each tile is remembered a few seconds)
local LEAN_SLIGHT = 0.35      -- wind strength from which rain and snow lean a little
local LEAN_STRONG = 0.9       -- and from which they lean a lot
local LEAN_GALE = 1.3         -- and from which rain leans hardest (snow has no steeper slant)

force = force or 'auto'
falling_mode = falling_mode or 'on'   -- rain and snow drawn at all (the `weather` setting)
ramps_mode = ramps_mode or 'on'
frost_mode = frost_mode or 'on'
fog_mode = fog_mode or 'auto'
marker_layer = marker_layer or nil
fog_ms = fog_ms or 0   -- running average of the time spent drawing fog, per frame
scan_ms = scan_ms or {rain = 0, fog = 0}   -- and of the rescans, each time they run
-- Profiling: the whole overlay per frame (running average and worst since last shown), and what
-- caused each of the slowest frames.
profile = profile or {average = 0, worst = 0, worst_parts = '', frames = 0, rescans = {}}
ground_mode = ground_mode or 'off'   -- the overlay version of lying snow; graphics/snow_cover.png replaces it

local grass = reqscript('internal/detailed_weather/grass')
local wind = reqscript('internal/detailed_weather/wind')
local ground = reqscript('internal/detailed_weather/ground')
local snow_ramps = reqscript('internal/detailed_weather/snow_ramps')
local frost = reqscript('internal/detailed_weather/frost')
local colour = reqscript('internal/detailed_weather/colour')
local colour_looks = reqscript('internal/detailed_weather/looks')   -- its steps
local wetness = reqscript('internal/detailed_weather/wetness')
local precipitation = reqscript('internal/detailed_weather/precipitation')
local settings = reqscript('internal/detailed_weather/settings')
local shade = reqscript('internal/detailed_weather/shade')
local paths = reqscript('internal/detailed_weather/paths')
local spatter = reqscript('internal/detailed_weather/spatter')
local murky = reqscript('internal/detailed_weather/murky')
local leaves = reqscript('internal/detailed_weather/leaves')
local work_time = reqscript('internal/detailed_weather/work_time')   -- the frame's shared time for background work
-- NATIVE SNOW (grungeisdead's copy, 2026-11-18): all of the snow drawn by the hook DLL while it's in DF's
-- folder (native.lua); snow_ramps.lua then only bakes the textures it asks for
local native = reqscript('internal/detailed_weather/native')
-- THE HOOK DLL'S INSTALLER (grungeisdead's copy, 2026-11-20, test 16A): install.lua copies the hook DLL from
-- this mod's folder into DF's at a fort's load, as Stockhook does, and asks for a restart once. Looked up
-- with pcall, so a copy without the file runs as before.
local install_ok, install = pcall(reqscript, 'internal/detailed_weather/install')
if not install_ok then install = nil end

----------------------------------------------------------------------------------------------
-- Art
----------------------------------------------------------------------------------------------

local art_dir = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or '') .. '../art/'

reload_count = reload_count or 0

local function copy_file(from, to)
    local input = assert(io.open(from, 'rb'))
    local data = input:read('a')
    input:close()
    local output = assert(io.open(to, 'wb'))
    output:write(data)
    output:close()
end

-- DFHack caches tilesets by path for the whole session, so a reload loads a fresh copy.
local function art_path(name)
    if reload_count == 0 then return art_dir .. name end
    local copies = art_dir .. 'reloaded/'
    dfhack.filesystem.mkdir(copies)
    local flat = name:gsub('/', '-')   -- (a sheet in a folder of the art: falling/rain_3-4.png)
    local copy = copies .. reload_count .. '-' .. flat
    copy_file(art_dir .. name, copy)
    os.remove(copies .. (reload_count - 1) .. '-' .. flat)   -- the previous reload's copy
    return copy
end

local function load_art()
    return {
        -- (the rain's and the snow's sheets, one per level, are read by sheet_of as each level
        -- first falls)
        rain_layout = dofile(art_dir .. 'rain_sheet.lua'),
        snow_layout = dofile(art_dir .. 'snow_sheet.lua'),
        fog_layout = dofile(art_dir .. 'fog_sheet.lua'),
        sheets = {},   -- the falling art by name (sheet_of)
        indexes = {},  -- and each family's index of where its tiles are
        texpos = {},   -- handle -> texpos, so it isn't asked for every tile every frame
    }
end

-- The falling art: rain, snow, leaves and petals, a sheet each by name ('rain_3', 'snow_1',
-- 'leaves_red', 'petals_pink'...), and the fog ('fog', whose groups are its densities). A sheet as it's drawn has a tile for every wind, place and
-- frame, most of them never on screen together and many empty or alike, and the game keeps a
-- texture for every tile of a file it loads, for the whole session. So each sheet is packed
-- (tools/weather/sheet_packing.py) into art/falling/:
--   <sheet>-<group>.png   a file per group, a group being one slant of the wind (the only one
--                         showing at a time), with each different tile of it once
--   <family>.lua          for every tile number of the sheet as drawn, its place in its group's
--                         file, or 0 for a tile with nothing drawn. The sheets drawn alike in
--                         different colours (the leaves; the petals) are a family and share one.
-- sheet_of(name) reads the layout and that index, which is quick. sheet_tiles(sheet, group) gives
-- a group's textures, loading its file the first time: a file takes a few tens of milliseconds, so
-- at most one loads a frame and the caller draws nothing of it until it's there.
local function family_of(name)
    return name:match('^petals') and 'petals' or name:match('^leaves') and 'leaves' or name
end
local function layout_file_of(name)
    return name:match('^petals') and 'petals_sheet.lua' or name:match('^leaves') and 'leaves_sheet.lua'
        or name:match('^rain') and 'rain_sheet.lua' or name:match('^snow_%d') and 'snow_sheet.lua'
        or (name .. '_sheet.lua')
end

-- A sheet by name: {name =, layout =, at = (tile number -> place in its group's file, 0: empty),
-- groups = (group -> its textures, once loaded)}.
local function sheet_of(name)
    local sheet = art.sheets[name]
    -- (or one from before the art was packed, in a game running since: it has no groups)
    if not sheet or not sheet.groups then
        local family = family_of(name)
        art.indexes = art.indexes or {}
        art.indexes[family] = art.indexes[family] or dofile(art_dir .. 'falling/' .. family .. '.lua')
        sheet = {name = name, layout = dofile(art_dir .. layout_file_of(name)), at = art.indexes[family].at,
                 groups = {}}
        art.sheets[name] = sheet
    end
    return sheet
end

-- A group's textures (by place in its file), or nil while the file waits its turn to load.
local sheet_loaded_at = nil   -- when the last file finished loading (clock_ms)
local function sheet_tiles(sheet, group)
    local tiles = sheet.groups[group]
    if not tiles then
        -- (timed from the end of a load: from its start, a load longer than the wait let the next
        -- file asked for in the same frame straight through)
        if sheet_loaded_at and clock_ms() - sheet_loaded_at < 100 then return nil end
        tiles = dfhack.textures.loadTileset(art_path(('falling/%s-%d.png'):format(sheet.name, group)), 32, 32, true)
        sheet.groups[group] = tiles
        sheet_loaded_at = clock_ms()
    end
    return tiles
end

-- The sheet tile for a map tile: which cell of the repeating patch it shows, at this frame.
-- (Each level of rain has its own sheet, all laid out alike; so has each level of snow.)
local function rain_tile(layout, surface, slant, x, y, frame)
    local cells = layout.cells
    local cell = (y % cells) * cells + (x % cells)
    local row = ((surface - 1) * #layout.slants + (slant - 1)) * cells * cells + cell
    return row * layout.frames + frame + 1
end

-- The same for the falling-snow sheet, which has no surfaces: flakes just settle where they land.
local function snow_tile(layout, wind_index, x, y, frame)
    local cells = layout.cells
    local cell = (y % cells) * cells + (x % cells)
    local row = (wind_index - 1) * cells * cells + cell
    return row * layout.frames + frame + 1
end

----------------------------------------------------------------------------------------------
-- Weather
----------------------------------------------------------------------------------------------

local function fort_world_tile()
    local map = df.global.world.map
    local data = df.global.world.world_data
    return data.region_map[map.region_x // 16]:_displace(map.region_y // 16)
end

-- Which slant of a sheet suits the wind: an index into its list of slants (or winds), which
-- runs from strongly west through upright to strongly east.
local function slant_for_wind(slants)
    local middle = (#slants + 1) // 2
    local x = wind.get()
    local across = math.abs(x)   -- only the east-west part leans the streaks
    local lean = across >= LEAN_GALE and 3 or across >= LEAN_STRONG and 2 or across >= LEAN_SLIGHT and 1 or 0
    lean = math.min(lean, middle - 1)   -- a sheet with fewer slants leans its most
    return middle + (x < 0 and -lean or lean)
end

-- 'rain', 'snow' or nil.
local function weather_at(x, y, z)
    if force == 'rain' or force == 'snow' then return force end
    if force == 'off' or falling_mode == 'off' then return nil end
    -- (GROUND WEATHER, grass.lua: the weather where rain lands below this tile, not open air's own biome)
    local weather = grass.ground_weather(x, y, z)
    return weather == df.weather_type.Rain and 'rain' or weather == df.weather_type.Snow and 'snow' or nil
end

----------------------------------------------------------------------------------------------
-- Where to draw
----------------------------------------------------------------------------------------------

local GROUND, WATER = 1, 2

-- A tiletype's shape. df.tiletype.attrs costs ~40 us a lookup, so each is looked up once.
local shapes = {}
local function shape_of(tiletype)
    local shape = shapes[tiletype]
    if not shape then shape = df.tiletype.attrs[tiletype].shape shapes[tiletype] = shape end
    return shape
end

-- The weather in each map block in view, as one string: when it changes, the rain needs a rescan.
local function weather_key(viewport)
    local parts = {}
    local z = viewport.z
    for block_y = viewport.y1 - viewport.y1 % 16, viewport.y2, 16 do
        for block_x = viewport.x1 - viewport.x1 % 16, viewport.x2, 16 do
            parts[#parts + 1] = weather_at(block_x + 8, block_y + 8, z) or '-'
        end
    end
    return table.concat(parts, ',')
end

-- RAIN READ IN ONE COPY (grungeisdead's copy, 2026-11-19). A raining block's 16x16 designation flags
-- (1 KB, column by column as designation[dx][dy], so tile dx * 16 + dy) and tiletypes (512 bytes) are
-- copied out with one memmove each and the bits tested in Lua, as colour.lua's underground check and
-- shade.lua do. Each tile's flags were read through DFHack field by field: 14.4 ms a rescan, four
-- rescans a second, once rain was found in view (details, 2026-11-19).
-- The bits, set on a scratch word through DFHack's own layout (the fallbacks are df-structures').
local function designation_mask(name, value, fallback)
    local ok, mask = pcall(function()
        local raw = df.new('uint32_t')
        raw.value = 0
        local _, at = df.sizeof(raw)
        df.reinterpret_cast(df.tile_designation, at)[name] = value
        local m = raw.value
        df.delete(raw)
        return m
    end)
    return (ok and mask and mask ~= 0) and mask or fallback
end
local rain_bits = nil   -- {outside, hidden, flow, magma}: made once
local rain_des, rain_below, rain_types = nil, nil, nil   -- the block being read, its level below, its tiletypes
local function copy_field(block, name, buf, bytes)
    local _, at = df.sizeof(block:_field(name))
    dfhack.internal.memmove(buf, at, bytes)
end

-- Where rain or snow can land in one map block (16 x 16 tiles): its outdoor, revealed tiles, each
-- {x =, y =, surface = GROUND or WATER}. Reading a block's tiles from the game is the slow part of
-- finding the rain (some 4 ms for a view's worth), so each block read is kept: by block and level,
-- for FALL_BLOCK_KEEP_MS, as digging, building and freezing change it only slowly.
local FALL_BLOCK_KEEP_MS = 5000
local FALL_BLOCKS_MOST = 200         -- kept at most; past this they're all let go and read again
local STALE_BLOCKS_PER_SCAN = 2      -- old blocks read again in one scan (the rest wait, used as they are)
local fall_blocks, fall_block_count = {}, 0   -- block key -> {tiles =, read_at = clock ms}
local fall_blocks_map                         -- which map they're of (map_name)

local function forget_fall_blocks() fall_blocks, fall_block_count = {}, 0 end

-- The map loaded, by save and place in its world: what's kept of one map mustn't be used on the
-- next. (Checked here as well as dropped at unload: the unload handler belongs to whichever copy of
-- this script ran last, the overlay's or a command's, and each has its own kept blocks.)
local function map_name()
    local map = df.global.world.map
    return dfhack.world.ReadWorldFolder() .. ':' .. map.region_x .. ',' .. map.region_y
end

local function read_fall_block(block_x, block_y, z, now)
    if not rain_bits then
        rain_bits = {outside = designation_mask('outside', true, 1 << 16), hidden = designation_mask('hidden', true, 1 << 9),
                     flow = designation_mask('flow_size', 7, 7), magma = designation_mask('liquid_type', true, 1 << 21)}
        rain_des, rain_below = df.new('uint32_t', 256), df.new('uint32_t', 256)
        rain_types = df.new('uint16_t', 256)
    end
    local OUTSIDE, HIDDEN, FLOW, MAGMA = rain_bits.outside, rain_bits.hidden, rain_bits.flow, rain_bits.magma
    local EMPTY = df.tiletype_shape.EMPTY
    local des, below_des, types = rain_des, rain_below, rain_types
    local tiles = {}
    local block = dfhack.maps.getTileBlock(block_x, block_y, z)
    if block then
        -- (each field copied out once and read as plain numbers: a read through DFHack of every
        -- tile's flags one by one was most of a scan's time)
        copy_field(block, 'designation', des, 1024)
        copy_field(block, 'tiletype', types, 512)
        local below = dfhack.maps.getTileBlock(block_x, block_y, z - 1)
        if below then copy_field(below, 'designation', below_des, 1024) end
        for dx = 0, 15 do
            for dy = 0, 15 do
                local i = dx * 16 + dy
                local d = des[i]
                if d & OUTSIDE ~= 0 and d & HIDDEN == 0 then
                    -- on water (flowing liquid that isn't magma), or falling through open air onto
                    -- water just below
                    local surface = GROUND
                    if d & FLOW ~= 0 and d & MAGMA == 0 then
                        surface = WATER
                    elseif below and shape_of(types[i]) == EMPTY then
                        local b = below_des[i]
                        if b & FLOW ~= 0 and b & MAGMA == 0 then surface = WATER end
                    end
                    tiles[#tiles + 1] = {x = block_x + dx, y = block_y + dy, surface = surface}
                end
            end
        end
    end
    return {tiles = tiles, read_at = now}
end

-- Outdoor tiles in view where it's raining or snowing, with which (tile.weather), and whether it
-- lands on ground or water. The weather is the same across a map block, so it's looked up once per
-- block. A pan only reads the blocks it brings into view: the rest are as kept. (All read again on
-- every frame the view moved, as they first were, this was a third of the mod's time while panning
-- in rain or snow.) The tiles returned are the kept ones themselves, not copies.
local function find_rain(viewport)
    local now = clock_ms()
    local map = map_name()
    if map ~= fall_blocks_map or fall_block_count > FALL_BLOCKS_MOST then
        forget_fall_blocks()
        fall_blocks_map = map
    end
    local tiles = {}
    local x1, y1, x2, y2, z = viewport.x1, viewport.y1, viewport.x2, viewport.y2, viewport.z
    local stale_reads_left = STALE_BLOCKS_PER_SCAN
    for block_y = y1 - y1 % 16, y2, 16 do
        for block_x = x1 - x1 % 16, x2, 16 do
            local weather = weather_at(block_x + 8, block_y + 8, z)
            if weather then
                local key = (z * 4096 + block_x) * 4096 + block_y
                local kept = fall_blocks[key]
                local stale = kept and now - kept.read_at > FALL_BLOCK_KEEP_MS
                if not kept or (stale and stale_reads_left > 0) then
                    if stale then stale_reads_left = stale_reads_left - 1 else fall_block_count = fall_block_count + 1 end
                    kept = read_fall_block(block_x, block_y, z, now)
                    fall_blocks[key] = kept
                end
                -- a block at the view's edge is only partly in it
                local all_in_view = block_x >= x1 and block_x + 15 <= x2 and block_y >= y1 and block_y + 15 <= y2
                for _, tile in ipairs(kept.tiles) do
                    if all_in_view or (tile.x >= x1 and tile.x <= x2 and tile.y >= y1 and tile.y <= y2) then
                        tile.weather = weather
                        tiles[#tiles + 1] = tile
                    end
                end
            end
        end
    end
    return tiles
end

-- The fog at the fort: 0 none, 1 mist, 2 fog, 3 thick (df.fog_type), or as forced; in between
-- while it fades. The game's fog flickers on and off as its weather shifts (each flip flashed the
-- whole map, Poss), so the fog drawn follows it only once it's held FOG_SETTLE_MS, and then a step
-- at a time, FOG_STEP_MS apart: the sheet's densities between the levels (substeps a level), so it
-- thickens and thins over some seconds (a level at a time came and went too suddenly: Poss).
local FOG_SETTLE_MS = 4000
local FOG_STEP_MS = 2500
fog_shown = fog_shown or nil
local fog_wanted, fog_wanted_since, fog_stepped = nil, 0, 0
local function fog_level()
    if fog_mode == 'off' then fog_shown = 0 return 0 end
    if fog_mode ~= 'auto' then fog_shown = tonumber(fog_mode) or 0 return fog_shown end
    local game, now = fort_world_tile().clouds.fog, clock_ms()
    if not fog_shown then fog_shown = game end   -- (a fort just loaded: as it is)
    if game ~= fog_wanted then fog_wanted, fog_wanted_since = game, now end
    if fog_shown ~= game and now - fog_wanted_since >= FOG_SETTLE_MS and now - fog_stepped >= FOG_STEP_MS then
        local step = 1 / (art and art.fog_layout and art.fog_layout.substeps or 1)
        fog_shown = game > fog_shown and math.min(game, fog_shown + step) or math.max(game, fog_shown - step)
        fog_stepped = now
    end
    return fog_shown
end

-- Every outdoor tile in view, with its screen position and how many levels down it shows (through
-- open space), so fog over lower ground can drift slower, as if lying at that height. Open sky
-- high above the ground has no map block at all at this level; that's outdoors too.
local FOG_MOST_DEPTH = 8
-- what each map tile shows for the fog, by position and level: false (not outdoors) or its depth.
-- The terrain changes rarely; it's forgotten every FOG_FORGET_MS anyway, to catch digging.
local FOG_FORGET_MS = 30000
fog_memory = fog_memory or {tiles = {}, count = 0, forget_at = 0}
local function find_outdoors(viewport)
    local now = clock_ms()
    if now >= fog_memory.forget_at or fog_memory.count > 60000 then
        fog_memory.tiles, fog_memory.count, fog_memory.forget_at = {}, 0, now + FOG_FORGET_MS
    end
    local memory = fog_memory.tiles
    local tiles = {}
    local z = viewport.z
    local block_at = grass.block_at   -- kept between scans
    local EMPTY, RAMP_TOP = df.tiletype_shape.EMPTY, df.tiletype_shape.RAMP_TOP
    local WALL, BROOK_BED = df.tiletype_shape.WALL, df.tiletype_shape.BROOK_BED
    local FROZEN = df.tiletype_material.FROZEN_LIQUID
    local see_through, no_fog = {}, {}   -- by tiletype; attrs are slow to look up
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
          local key = (z * 4096 + x) * 4096 + y
          local known = memory[key]
          if known ~= nil then
            if known then tiles[#tiles + 1] = {x = x, y = y, depth = known} end
          else
            fog_memory.count = fog_memory.count + 1
            memory[key] = false
            local block = block_at(x, y, z)
            local flags = block and block.designation[x % 16][y % 16]
            -- above ground rather than 'outside': tiles under a tree's canopy count as indoors, and
            -- went without fog, standing out bright among the fogged ones. Not inside water or
            -- frozen water (ice walls, brook beds): surface fog draws on the level above instead.
            local submerged = false
            if block then
                if flags.flow_size > 0 then
                    submerged = true
                else
                    local tt = block.tiletype[x % 16][y % 16]
                    local nf = no_fog[tt]
                    if nf == nil then
                        local attrs = df.tiletype.attrs[tt]
                        nf = (attrs.material == FROZEN and attrs.shape == WALL) or attrs.shape == BROOK_BED
                        no_fog[tt] = nf
                    end
                    submerged = nf
                end
            end
            if not submerged and ((not block and dfhack.maps.isValidTilePos(x, y, z))
                    or (flags and (flags.outside or not flags.subterranean) and not flags.hidden)) then
                local depth, level = 0, z
                while depth < FOG_MOST_DEPTH do
                    local b = block_at(x, y, level)
                    if b then
                        local tiletype = b.tiletype[x % 16][y % 16]
                        local open = see_through[tiletype]
                        if open == nil then
                            local shape = shape_of(tiletype)
                            open = shape == EMPTY or shape == RAMP_TOP
                            see_through[tiletype] = open
                        end
                        -- the fog lies on a water surface: it isn't looked for below it
                        if not open or b.designation[x % 16][y % 16].flow_size > 0 then break end
                    end
                    depth, level = depth + 1, level - 1
                end
                tiles[#tiles + 1] = {x = x, y = y, depth = depth}
                memory[key] = depth
            end
          end
        end
    end
    return tiles
end

-- The fog sheet tile for a map tile: drifted `steps` steps east (negative: west). Each frame of
-- the art is the patch moved one more step; after a whole tile's worth the cell moves on by one.
local function fog_tile(layout, level, steps, x, y)
    local per_tile = layout.frames
    local frame = steps % per_tile
    local tiles_moved = steps // per_tile
    local cx, cy = (x - tiles_moved) % layout.patch, y % layout.patch
    local row = (level - 1) * layout.patch * layout.patch + cy * layout.patch + cx
    return row * layout.frames + frame + 1
end

FOG_PEN = dfhack.pen.parse{ch = 32}

local function texpos_of(handle)
    local texpos = art.texpos[handle]
    if not texpos then texpos = dfhack.textures.getTexposByHandle(handle) art.texpos[handle] = texpos end
    return texpos
end

-- A WHOLE SHEET FOR THE HOOK LIBRARY. The library's tables are by a sheet's tile numbers as drawn,
-- every group at once; the art is packed a file per group (sheet_of). Until the library knows the
-- groups itself, a sheet it's handed gets `tiles`: for every tile number its texture's handle, or
-- false for a tile with nothing drawn. Every group's file is loaded for it, in the one frame.
local function whole_sheet(name)
    local sheet = sheet_of(name)
    if not sheet.tiles then
        local layout = sheet.layout
        local side = layout.cells or layout.patch
        local tiles_a_group = side * side * layout.frames
        local group_count = art.indexes[family_of(name)].groups
        local tiles = {}
        for number, place in ipairs(sheet.at) do
            local handle = false
            if place > 0 then
                local group = (number - 1) // tiles_a_group % group_count + 1
                local handles = sheet.groups[group]
                if not handles then
                    handles = dfhack.textures.loadTileset(art_path(('falling/%s-%d.png'):format(name, group)), 32, 32, true)
                    sheet.groups[group] = handles
                end
                handle = handles[place] or false
            end
            tiles[number] = handle
        end
        sheet.tiles = tiles
    end
    return sheet
end
local function whole_texpos_of(handle) return handle and texpos_of(handle) or 0 end

----------------------------------------------------------------------------------------------
-- Changing map
----------------------------------------------------------------------------------------------

-- Loading another save in the same session: everything kept by map position belongs to the old
-- map, and everything kept by texture number may name other textures, as the next world's
-- graphics mods can differ. map_count tells the overlay to drop its own plans too.
map_count = map_count or 0
dfhack.onStateChange.detailed_weather = function(event)
    if event ~= SC_MAP_UNLOADED and event ~= SC_WORLD_UNLOADED then return end
    map_count = map_count + 1
    -- the texture numbers of what the modules made (all made again for the next world) would
    -- name the next world's own pictures, which would then be passed over as ours
    for texpos in pairs(_G.detailed_weather_made or {}) do _G.detailed_weather_made[texpos] = nil end
    forget_fall_blocks()
    grass.forget_world()
    snow_ramps.forget_world()
    native.forget_world()
    frost.forget_world()
    wind.forget_world()
    shade.forget_world()
    spatter.forget_world()
    murky.forget_world()
    leaves.forget_world()
    paths.forget_world()
    wetness.forget()
    precipitation.forget()
    ground.clear_cache()
    grass.abandon_trash()   -- what those just let go of: never deleted while a world unloads
    if art then art.texpos = {} end
end

----------------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------------

-- Hands each module its switches for what the player has chosen (settings.lua: each part off, low
-- or high). Called when this loads and after every change.
applied_settings = applied_settings or {}   -- part -> the level last handed out
function apply_settings()
    local level = settings.get
    local function on_unless_off(part) return level(part) == 'off' and 'off' or 'on' end
    local function on_at_high(part) return level(part) == 'high' and 'on' or 'off' end
    local function changed(part) return applied_settings[part] ~= nil and applied_settings[part] ~= level(part) end

    colour.mode = on_unless_off('colour')
    falling_mode = on_unless_off('weather')
    -- Fog, leaves and petals can also be forced for testing (`fog 2`, `leaves 3`), which the
    -- setting leaves alone: it only turns them off, and back to following the game.
    if level('fog') == 'off' then fog_mode = 'off' elseif fog_mode == 'off' then fog_mode = 'auto' end
    if level('leaves') == 'off' then leaves.mode = 'off' elseif leaves.mode == 'off' then leaves.mode = 'auto' end
    if level('petals') == 'off' then leaves.petals_mode = 'off' elseif leaves.petals_mode == 'off' then leaves.petals_mode = 'auto' end

    -- trees and buildings: their colours at low, and the sway too at high
    colour.screen_mode = on_unless_off('trees')
    colour.sway_mode = on_at_high('trees')
    colour.screen_allowance = settings.allowance('trees')
    -- grass: the lean at low, and the gusts' sweep and the rustle too at high
    colour.lean_mode = on_unless_off('grass')
    colour.wave_mode = on_at_high('grass')
    colour.rustle_grass_mode = on_at_high('grass')

    ramps_mode, snow_ramps.allowance = on_unless_off('ramps'), settings.allowance('ramps')
    frost_mode, frost.allowance = on_unless_off('frost'), settings.allowance('frost')
    paths.mode, paths.allowance = on_unless_off('paths'), settings.allowance('paths')
    -- spatter: thinned and shadowed at low, and the grass's blades in front of it at high
    spatter.mode, spatter.allowance = on_unless_off('spatter'), settings.allowance('spatter')
    spatter.blades_mode = on_at_high('spatter')
    shade.mode = on_unless_off('shade')
    murky.mode = on_unless_off('murky')

    -- what a change means working out again
    if changed('colour') and colour.state then colour.state.next_sample = 0 end
    if changed('ramps') then snow_ramps.forget() end
    if changed('frost') then frost.forget() end
    if changed('paths') then paths.plans = {} end
    if changed('shade') then shade.plan = nil end
    for _, part in ipairs(settings.PARTS) do applied_settings[part.name] = level(part.name) end
    stage_rests = {}   -- a part that kept failing gets a fresh try with the new settings
end
-- (Every time this file runs, as the overlay's module or for a command: handing out the same
-- settings twice changes nothing.)
apply_settings()

----------------------------------------------------------------------------------------------
-- The overlay
----------------------------------------------------------------------------------------------

-- The weather is drawn last, after every other mod's overlay on the map, so it's the same every
-- session. DFHack draws a screen's own widgets in no fixed order (a Lua pairs over them), then the
-- widgets for 'all' screens; Stone Tint, say, rewrites the same floor textures in the map's
-- background, so with both on the map's widgets, which of the two won changed from session to
-- session. So the weather is an 'all' widget, and the map's widget below only marks that the map
-- was just drawn: the weather draws once after it, and not over other screens (an 'all' widget is
-- drawn after every screen, a menu on top of the map included).
map_drawn = false

MapDrawnOverlay = defclass(MapDrawnOverlay, overlay.OverlayWidget)
MapDrawnOverlay.ATTRS{
    desc = 'Marks the map as drawn, so Detailed Weather draws its weather straight after it.',
    viewscreens = {'dwarfmode', 'dungeonmode'},   -- fortress and adventure mode
    default_enabled = true,
    fullscreen = true,
}

function MapDrawnOverlay:onRenderFrame() map_drawn = true end

RainOverlay = defclass(RainOverlay, overlay.OverlayWidget)
RainOverlay.ATTRS{
    desc = 'Draws the weather graphics mode otherwise leaves out: rain, snow, fog, frost and heat.',
    viewscreens = 'all',
    default_enabled = true,
    fullscreen = true,
}

function RainOverlay:init()
    self.tiles = {}
    self.fog_tiles = {}
    self.ground_tiles = {}
    self.next_scan = 0
end

function RainOverlay:onRenderFrame(dc)
    if dfhack.isMapLoaded() then native.sync_view() end
    if not map_drawn then return end
    map_drawn = false
    if not dfhack.screen.inGraphicsMode() or not dfhack.isMapLoaded() then return end
    local frame_started = clock_ms()
    local precise = clock_s()
    self.parts = {}
    self:draw_weather(dc)
    profile.precise_ms = (profile.precise_ms or 0) + (clock_s() - precise) * 1000
    _G.detailed_weather_frame_ms = (clock_s() - precise) * 1000   -- (colour.lua: CHANGES OF LOOK TIMED)
    local took = clock_ms() - frame_started
    profile.frames = profile.frames + 1
    profile.average = profile.average + (took - profile.average) * 0.05
    if took > profile.worst then profile.worst, profile.worst_parts = took, table.concat(self.parts, ' ') end
end

-- Notes what this frame did, for the profile.
function RainOverlay:note(what) self.parts[#self.parts + 1] = what end

-- Runs a stage of the frame, timed for the profile (noted with its ms when it took 1 ms or more).
-- A stage that fails doesn't stop the ones after it: an error in the grass's rustle once left the
-- rain, fog, shade and leaves undrawn too, and wrote the same error to the log every frame. Each
-- different failure is reported once, and listed by `detailed_weather`.
--
-- A stage that has just failed rests before it's tried again, twice as long after each failure in
-- a row (a second, two, four... up to a minute): tried again every frame, one that makes textures
-- before it fails would make them sixty times a second, and none are ever deleted (grass.lua).
-- One success ends it. The rests are forgotten when a setting changes (apply_settings) and on a
-- new map, so each gets a fresh try.
stage_errors = stage_errors or {}   -- 'stage: message' -> how many times
stage_rests = {}                    -- stage -> {failures = in a row, retry_at = clock ms}
local FIRST_REST_MS, LONGEST_REST_MS = 1000, 60000

local function rest_after_failure(name, now)
    local rest = stage_rests[name] or {failures = 0}
    rest.failures = rest.failures + 1
    -- (the doubling stops at 2^16: past the longest rest long before)
    local wait = math.min(LONGEST_REST_MS, FIRST_REST_MS * 2 ^ math.min(rest.failures - 1, 16))
    rest.retry_at = now + wait
    stage_rests[name] = rest
end

-- STAGE TIMING (grungeisdead's copy, 2026-11-16): each stage's time, added up in fractional ms
-- (clock.lua's seconds, not the whole-ms clock the notes use) since `detailed_weather details` last
-- showed them, and the whole frame's (profile.precise_ms), so details can give each stage's average a
-- frame and what ran outside every stage. The tile info overlay's own frames are added here too.
stage_ms = stage_ms or {}
function RainOverlay:timed(name, fn, ...)
    local started = clock_ms()
    local rest = stage_rests[name]
    if rest and started < rest.retry_at then return end
    work_time.start_stage()
    local precise = clock_s()
    local ok, problem = pcall(fn, ...)
    work_time.done()   -- whatever work the stage left under way ends with it
    stage_ms[name] = (stage_ms[name] or 0) + (clock_s() - precise) * 1000
    if ok then
        stage_rests[name] = nil
    else
        local report = name .. ': ' .. tostring(problem)
        if not stage_errors[report] then dfhack.printerr('detailed_weather: ' .. report) end
        stage_errors[report] = (stage_errors[report] or 0) + 1
        rest_after_failure(name, clock_ms())
    end
    local took = clock_ms() - started
    if took >= 1 then self:note(name .. '=' .. took) end
end

-- The fog's density (the sheet's level) and each depth's drift this frame, in steps (by depth: lower
-- levels drift slower, and show other shapes). The fog moves on real time, at a steady speed set by
-- the wind, and stands still while the game is paused. Its position builds up frame by frame, so a
-- change of wind changes its pace without a jump. (grungeisdead's copy, test 15X: taken out of the
-- drawing, unchanged, for the DLL's drawing too.)
function RainOverlay:fog_drift(now)
    local fog_layout = art.fog_layout
    local elapsed = self.fog_clock and math.min(now - self.fog_clock, 200) or 0
    self.fog_clock = now
    if df.global.pause_state then elapsed = 0 end
    -- the art only drifts east or west, so only that part of the wind moves it
    local across = wind.get()
    local px_per_ms = (FOG_CALM_PX + FOG_WIND_PX * math.abs(across)) / 1000 * (across < 0 and -1 or 1)
    self.fog_px = (self.fog_px or 0) + px_per_ms * elapsed
    local steps_at = {}
    for depth = 0, FOG_MOST_DEPTH do
        steps_at[depth] = math.floor(self.fog_px / (1 + FOG_DEPTH_SLOWING * depth) / fog_layout.step) + depth * 37
    end
    local level = math.max(1, math.floor(self.fog * (fog_layout.substeps or 1) + 0.5))   -- the sheet's density
    return level, steps_at
end

function RainOverlay:draw_weather(dc)
    local viewport = guidm.Viewport.get()
    if self.map_count ~= map_count then
        self:init()
        self.map_count, self.view_key, self.due = map_count, nil, nil
        self.ramp_tiles, self.frost_tiles, self.weather_key, self.fog = nil, nil, nil, nil
        stage_rests = {}   -- what failed on the last map may not here
    end

    local tick = df.global.cur_year_tick
    local now = clock_ms()
    work_time.start_frame()
    wind.update()
    self:timed('colour', colour.update, viewport)
    -- the plans are per screen position, so a moved view needs new ones straight away
    local view_key = table.concat({viewport.x1, viewport.y1, viewport.x2, viewport.y2, viewport.z}, ',')
    local view_moved = view_key ~= self.view_key
    self.view_key = view_key

    -- Rescans: each is only due when what it depends on may have changed, and at most one runs
    -- a frame, so their costs never pile into the same frame.
    self.due = self.due or {}
    if view_moved then
        self.due.rain, self.due.fog, self.due.ramps, self.due.frost = true, true, true, true
        -- the older ground experiment keeps buffer indexes in its plans, which are wrong (and
        -- may be past the end of the buffers) after a zoom or resize
        self.ground_tiles = {}
        self:note('view-moved')
        profile.rescans.view_moved = (profile.rescans.view_moved or 0) + 1
    end
    if now >= self.next_scan then
        self.next_scan = now + RESCAN_MS
        -- how hard it's falling, 1 to 4 (precipitation.lua)
        self.rain_level = precipitation.level('rain', force == 'rain')
        self.snow_level = precipitation.level('snow', force == 'snow')
        local key = weather_key(viewport)
        -- (NATIVE RAIN: a change asks the DLL's grid for every block again, not only those not kept)
        if key ~= self.weather_key then self.weather_key, self.due.rain, self.rain_full = key, true, true end
        local fog = fog_level()
        if fog ~= self.fog then self.fog, self.due.fog = fog, true end
        if now >= (self.next_ramp_scan or 0) then self.due.ramps = true end
        if now >= (self.next_frost_scan or 0) then self.due.frost = true end
    end
    if now >= (self.next_fog_scan or 0) and self.fog and self.fog > 0 then self.due.fog = true end
    local started = clock_ms()
    local scan_started = started
    -- NATIVE RAIN (grungeisdead's copy, test 15M): while the hook DLL draws the falling rain and snow
    -- (native.lua: RAIN AND SNOW FALLING), a rescan only hands it the weather by map block; the tiles
    -- are neither found nor drawn here. A switch either way rescans at once, so neither side draws
    -- the other's tiles for a frame.
    local native_rain = native.rain_running()
    if native_rain ~= self.native_rain then
        self.native_rain, self.due.rain, self.rain_full, self.tiles = native_rain, true, true, {}
    end
    -- THE FOG DRAWN BY THE DLL (test 15X): while it draws the fog, the outdoor tiles aren't looked for
    -- here; a switch either way looks again (or lets them go) at once
    local native_fog = native.wfog_running()
    if native_fog ~= self.native_fog then self.native_fog, self.due.fog, self.fog_tiles = native_fog, true, {} end
    local scanned_rain = self.due.rain
    if self.due.rain then
        self:note('rain-scan')
        if native_rain then
            native.rain_weather(viewport, weather_at, self.rain_full)
            self.tiles, self.rain_full = {}, nil
        else
            self.tiles = find_rain(viewport)
        end
        self.due.rain = nil
        scan_ms.rain = scan_ms.rain + (clock_ms() - started - scan_ms.rain) * 0.2
    end
    -- a moved view's fog can't wait its turn behind the rain: while panning the rain was due every
    -- frame, so the fog stayed on the old view's tiles and the strip panned in came in bare,
    -- fogging over only once the view stopped (a player's report)
    if self.due.fog and (view_moved or not scanned_rain) then
        self:note('fog-scan')
        local fog_started = clock_ms()   -- not `started`: the rain's scan may have run since
        self.fog_tiles = (self.fog or 0) > 0 and not native_fog and find_outdoors(viewport) or {}
        self.due.fog, self.next_fog_scan = nil, now + FOG_RESCAN_MS
        scan_ms.fog = scan_ms.fog + (clock_ms() - fog_started - scan_ms.fog) * 0.2
    end
    -- Snow and frost keep what they've worked out per map tile, and plan a little every frame
    -- within their own time budgets (new strips first, then rechecks, then round the view).
    -- (NATIVE SNOW) the hook DLL's snow started, or handed back, before snow_ramps.lua plans
    self:timed('native', native.update, ramps_mode == 'on')
    if ramps_mode == 'on' then self:timed('snow-plan', function() self.ramp_tiles = snow_ramps.plan(viewport) end) end
    if frost_mode == 'on' then self:timed('frost-plan', function() self.frost_tiles = frost.plan(viewport) end) end
    if clock_ms() - scan_started >= 1 then self:note('scan=' .. (clock_ms() - scan_started)) end

    -- the animations run on game time, so they stop when the game is paused; but adventure mode's
    -- time only moves as the adventurer acts, which left the rain hanging in the air between turns
    -- and lurching on with each step, so there they run on real time, at normal speed's pace
    local frame = dfhack.world.isAdventureMode() and now // (TICKS_PER_FRAME * MS_PER_TICK)
        or tick // TICKS_PER_FRAME
    if ramps_mode == 'on' and self.ramp_tiles then self:timed('snow-draw', snow_ramps.apply, self.ramp_tiles, viewport) end
    if frost_mode == 'on' and self.frost_tiles then self:timed('frost-draw', frost.apply, self.frost_tiles, viewport) end
    self:timed('paths', paths.apply, viewport)
    self:timed('colour-screen', colour.update_screen, viewport)   -- last: shifts what the snow and frost leave showing
    self:timed('spatter', spatter.apply, viewport)   -- the fruit and leaves on grass, in the colour's shades, set in the grass
    self:timed('murky', murky.apply, viewport, art_path)   -- stagnant water's tint, in the spatter layer
    self:timed('shade', shade.apply, viewport)   -- its own layer, over everything
    if leaves.mode ~= 'off' or leaves.petals_mode ~= 'off' then
        if not art then art = load_art() end
        local _, _, strength = wind.get()
        local wind_index_for = function(layout) return slant_for_wind(layout.winds) end
        if native.leaves_running() then
            -- (THE LEAVES DRAWN BY THE DLL, test 15X: what each tree sheds now, and the sheets, handed over)
            self:timed('leaves', function()
                native.leaves_frame({specs = leaves.native_frame(strength), frame = frame, wind_index_for = wind_index_for,
                                     sheet_of = whole_sheet, texpos_of = whole_texpos_of})
            end)
        else
            self:timed('leaves', leaves.apply, viewport, sheet_of, sheet_tiles, texpos_of, frame, wind_index_for, strength)
        end
    end
    if marker_layer then
        -- a magenta square, half see-through, with a solid rim, made once
        if not marker_texpos then
            local px = {}
            for y = 0, 31 do
                for x = 0, 31 do
                    local rim = x < 2 or y < 2 or x > 29 or y > 29
                    px[#px + 1] = ((rim and 255 or 128) << 24) | (255 << 16) | 255
                end
            end
            marker_texpos = dfhack.textures.getTexposByHandle(dfhack.textures.createTile(px, 32, 32))
        end
        local port = df.global.gps.main_viewport
        local layer = port['screentexpos_' .. marker_layer]
        local cx, cy = (viewport.x2 - viewport.x1) // 2, (viewport.y2 - viewport.y1) // 2
        for sx = math.max(0, cx - 4), math.min(port.dim_x - 1, cx + 4) do
            for sy = math.max(0, cy - 4), math.min(port.dim_y - 1, cy + 4) do layer[sx * port.dim_y + sy] = marker_texpos end
        end
    end
    if ground_mode == 'on' then
        if view_moved or now >= (self.next_ground_scan or 0) then
            self.ground_tiles = ground.plan(viewport)
            self.next_ground_scan = now + GROUND_RESCAN_MS
        end
        ground.apply(self.ground_tiles, frame)
    end

    -- NATIVE RAIN (test 15M): the DLL is handed each frame's slant and animation frame, and the
    -- sheets for how hard each kind falls, loaded (sheet_of) only for a kind falling in view
    if native_rain then
        self:timed('rain', function()
            if not art then art = load_art() end
            local has_rain, has_snow = native.rain_kinds()
            local layout, snow_layout = art.rain_layout, art.snow_layout
            local rain_level = self.rain_level or precipitation.LIGHTEST
            local snow_level = self.snow_level or precipitation.LIGHTEST
            native.rain_frame({
                rain_layout = layout, rain_level = rain_level, rain_name = 'rain_' .. rain_level,
                rain_sheet = has_rain and whole_sheet('rain_' .. rain_level) or nil,
                slant = slant_for_wind(layout.slants), rain_frame = frame % layout.frames,
                snow_layout = snow_layout, snow_level = snow_level, snow_name = 'snow_' .. snow_level,
                snow_sheet = has_snow and whole_sheet('snow_' .. snow_level) or nil,
                snow_wind = slant_for_wind(snow_layout.winds), snow_frame = frame % snow_layout.frames,
                texpos_of = whole_texpos_of,
            })
        end)
    end

    -- THE FOG DRAWN BY THE DLL (test 15X): this frame's density and drift handed over (0: none)
    if native_fog then
        self:timed('fog', function()
            if not art then art = load_art() end
            local level, steps = 0, nil
            if (self.fog or 0) > 0 then level, steps = self:fog_drift(now) end
            native.wfog_frame({level = level, steps = steps, layout = art.fog_layout,
                               handles = level > 0 and whole_sheet('fog').tiles or nil, texpos_of = whole_texpos_of})
        end)
    end

    if #self.tiles == 0 and #self.fog_tiles == 0 then return end

    if not art then art = load_art() end
    dc:map(true)

    -- Falling rain and snow go in the game's own flow layer (screentexpos_high_flow, where mist
    -- and spray go), so the fog, drawn by the overlay, can lie over them: the overlay only gets one
    -- texture a tile. Where a flow is already there, the rain is drawn by the overlay instead.
    local port = df.global.gps.main_viewport
    local flows, dim_y = port.screentexpos_high_flow, port.dim_y
    local layout, snow_layout = art.rain_layout, art.snow_layout
    -- The rain's and the snow's textures for how hard each is falling and the wind's slant, asked
    -- for at the frame's first tile of it (so snow alone never loads any rain). false for the
    -- moment a file takes to load the first time: nothing of it is drawn until then.
    local rain_level = self.rain_level or precipitation.LIGHTEST
    local snow_level = self.snow_level or precipitation.LIGHTEST
    local slant = slant_for_wind(layout.slants)
    local snow_wind = slant_for_wind(snow_layout.winds)
    -- While the file for a new slant or level loads, the one drawn last carries on (the rain
    -- would blink off for a moment each time the wind picked up otherwise).
    local falling = {}   -- 'rain' / 'snow' -> {tiles =, at =, group =}, or false with nothing loaded yet
    art.last_falling = art.last_falling or {}
    local function falling_art(kind, level, group)
        if falling[kind] == nil then
            local sheet = sheet_of(kind .. '_' .. level)
            local tiles = sheet_tiles(sheet, group)
            if tiles then art.last_falling[kind] = {tiles = tiles, at = sheet.at, group = group} end
            falling[kind] = art.last_falling[kind] or false
        end
        return falling[kind]
    end
    local rain_frame, snow_frame = frame % layout.frames, frame % snow_layout.frames
    local overlay_drawn = {}
    for _, tile in ipairs(self.tiles) do
        local index, drawn
        if tile.weather == 'snow' then
            drawn = falling_art('snow', snow_level, snow_wind)
            index = drawn and snow_tile(snow_layout, drawn.group, tile.x, tile.y, snow_frame)
        else
            drawn = falling_art('rain', rain_level, slant)
            index = drawn and rain_tile(layout, tile.surface, drawn.group, tile.x, tile.y, rain_frame)
        end
        -- the tile's place in the file loaded (0: nothing is drawn on it this frame)
        local place = drawn and drawn.at[index] or 0
        local sheet = drawn and drawn.tiles
        if place > 0 then
            local sx, sy = tile.x - viewport.x1, tile.y - viewport.y1
            local inside = sx >= 0 and sy >= 0 and sx < port.dim_x and sy < dim_y   -- raw memory: never past its end
            local i = sx * dim_y + sy
            if not inside then
                -- off the buffer (the view was just zoomed or resized): skip until the rescan
            elseif flows[i] == 0 then
                flows[i] = texpos_of(sheet[place])
            else
                overlay_drawn[tile.x * 4096 + tile.y] = true
                dc:seek(sx, sy):pen{tile = texpos_of(sheet[place])}:char(' ')
            end
        end
    end

    if #self.fog_tiles > 0 and (self.fog or 0) > 0 then
        local started = clock_ms()
        local fog_layout = art.fog_layout
        local level, steps_at = self:fog_drift(now)
        local paint, pen = dfhack.screen.paintTile, FOG_PEN
        -- that density's textures; while its file loads (the fog thickening a step), the density
        -- drawn last carries on
        local fog_sheet = sheet_of('fog')
        local fog_handles = sheet_tiles(fog_sheet, level)
        if fog_handles then art.fog_drawn = {tiles = fog_handles, level = level} end
        local fog_drawn = art.fog_drawn
        local fog_at = fog_sheet.at
        for _, tile in ipairs(fog_drawn and self.fog_tiles or {}) do
            if not overlay_drawn[tile.x * 4096 + tile.y] then
                local index = fog_tile(fog_layout, fog_drawn.level, steps_at[tile.depth], tile.x, tile.y + tile.depth * 3)
                local place = fog_at[index]
                if place > 0 then
                    paint(pen, tile.x - viewport.x1, tile.y - viewport.y1, nil, texpos_of(fog_drawn.tiles[place]), true)
                end
            end
        end
        fog_ms = fog_ms + (clock_ms() - started - fog_ms) * 0.05
        if clock_ms() - started >= 1 then self:note('fog-draw=' .. (clock_ms() - started)) end
    end

    dc:map(false)
end

----------------------------------------------------------------------------------------------
-- More about the hovered tile, under the game's hover box
----------------------------------------------------------------------------------------------

-- The lines themselves come from internal/detailed_weather/tile_info.lua (plant and tree state,
-- grass, snow depth, temperature). They go just under the game's own hover box ('A pile of
-- snow'), which the game draws itself: its place and size aren't exposed, so it's found by
-- reading the screen's text below the top bar (the first block of text rows there is the box).
-- That's a call per cell, so it's looked for a few times a second, not every frame. This is a
-- fullscreen overlay that only writes the cells of its own text: a positioned widget owns its
-- whole frame, and the map isn't drawn under it.

local tile_info = reqscript('internal/detailed_weather/tile_info')

local HOVER_TOP = 3            -- first screen row below the top bar
local HOVER_SEARCH_ROWS = 14   -- how far down to look for the box
local HOVER_FIND_MS = 250
-- How often the lines are worked out again while the mouse stays on one tile (grungeisdead's
-- copy, 2026-11-16): they were worked out afresh every frame, which with the module lookups in
-- tile_info.lua cost 4 to 7.7 ms a frame. They're still drawn every frame (the game redraws the
-- screen each frame); a new tile under the mouse works them out at once.
local INFO_REFRESH_MS = 250
local TILE_INFO_PEN = dfhack.pen.parse{fg = COLOR_WHITE, bg = COLOR_BLACK}

local function row_text_start(y, width)
    -- the hover box starts about halfway across, under the top bar; menus and build windows sit
    -- further left, and their text would be taken for it
    for x = math.floor(width * 0.42), width - 1 do
        local pen = dfhack.screen.readTile(x, y)
        if pen and pen.ch and pen.ch > 32 then return x end
    end
end

-- Where the game's hover box is: its text's left column and last row, or nil.
local function find_hover_box(width)
    local left, last
    for y = HOVER_TOP, HOVER_TOP + HOVER_SEARCH_ROWS do
        local x = row_text_start(y, width)
        if x then
            left, last = math.min(left or x, x), y
        elseif last then
            break   -- the row after the box's text: its bottom border
        end
    end
    return left, last
end

-- The text on one screen row from x, as far as it goes (two spaces end it), and each column's pen.
local function row_text(x, y, width)
    local chars, pens, blanks = {}, {}, 0
    for cx = x, width - 1 do
        local pen = dfhack.screen.readTile(cx, y)
        local ch = pen and pen.ch or 32
        if ch <= 32 then
            blanks = blanks + 1
            if blanks >= 2 then break end
        else
            blanks = 0
        end
        chars[#chars + 1] = string.char(ch < 256 and ch or 63)
        pens[#pens + 1] = pen
    end
    return table.concat(chars):gsub('%s+$', ''), pens
end

-- The hover box's line naming fallen fruit or seeds ("Sand pears"), shown as spatter ("Sand pear
-- spatter"): what lies there can't be gathered, though the game gives it the fruit's own name.
-- names: tile_info.spatter_names for the hovered tile, worked out with its lines (onRenderFrame).
function rename_spatter(dc, names, left, last)
    if #names == 0 then return end
    for y = HOVER_TOP, last do
        local text, pens = row_text(left, y, dc.width)
        local lower = text:lower()
        for _, name in ipairs(names) do
            local plural, singular = name[1]:lower(), name[2]
            local at = lower:find(plural, 1, true)
            if at then
                local shown = singular .. ' spatter'
                if text:sub(at, at):match('%u') then shown = shown:sub(1, 1):upper() .. shown:sub(2) end
                local new = text:sub(1, at - 1) .. shown .. text:sub(at + #plural)
                local pen = pens[at] or TILE_INFO_PEN
                dc:seek(left, y):string(new, {fg = pen.fg, bg = pen.bg, bold = pen.bold})
                break
            end
        end
    end
end

TileInfoOverlay = defclass(TileInfoOverlay, overlay.OverlayWidget)
TileInfoOverlay.ATTRS{
    desc = 'Adds plant, grass, snow and temperature lines under the game\'s hover box.',
    viewscreens = 'dwarfmode',
    default_enabled = true,
    fullscreen = true,
}

function TileInfoOverlay:onRenderFrame(dc)
    if not dfhack.isMapLoaded() then return end
    -- an alert's popup (the mouse on an alert button) would be taken for the hover box
    local interface = df.global.game.main_interface
    if interface.hover_announcement_alert or interface.current_hover_alert then return end
    -- nor while one of the game's panels is open (petitions, stocks, a unit...): its text would be
    -- taken for the hover box too. Each has an 'open' flag; which ones have one is found once.
    if not self.panels then
        self.panels = {}
        for name, panel in pairs(interface) do
            if type(panel) == 'userdata' then
                local ok, open = pcall(function() return panel.open end)
                if ok and open ~= nil then self.panels[#self.panels + 1] = name end
            end
        end
    end
    for _, name in ipairs(self.panels) do
        if interface[name].open then return end
    end
    local pos = dfhack.gui.getMousePos()
    if not pos then return end
    local now = clock_ms()
    if now >= (self.next_find or 0) then
        self.box_left, self.box_last = find_hover_box(dc.width)
        self.next_find = now + HOVER_FIND_MS
    end
    if not self.box_left then return end   -- no hover box showing: nothing to add to
    -- the lines and the spatter's names, worked out for a new tile or every INFO_REFRESH_MS
    local key = (pos.z * 4096 + pos.x) * 4096 + pos.y
    if key ~= self.info_key or now >= (self.info_due or 0) then
        self.info_key, self.info_due = key, now + INFO_REFRESH_MS
        self.info_lines, self.info_spatter = tile_info.describe(pos), tile_info.spatter_names(pos)
    end
    rename_spatter(dc, self.info_spatter, self.box_left, self.box_last)
    local lines = self.info_lines
    for n, line in ipairs(lines) do
        local text = ' ' .. line .. ' '
        dc:seek(self.box_left - 1, self.box_last + 1 + n):string(text:sub(1, dc.width - self.box_left), TILE_INFO_PEN)
    end
end

-- STAGE TIMING: the tile info overlay's frames, timed as a stage of their own. (A command running
-- this file again defines onRenderFrame afresh above, so it is only ever wrapped once.)
local draw_tile_info = TileInfoOverlay.onRenderFrame
function TileInfoOverlay:onRenderFrame(dc)
    local precise = clock_s()
    draw_tile_info(self, dc)
    stage_ms['tile-info'] = (stage_ms['tile-info'] or 0) + (clock_s() - precise) * 1000
end

OVERLAY_WIDGETS = {map_drawn = MapDrawnOverlay, rain = RainOverlay, tile_info = TileInfoOverlay}

if dfhack_flags.module then return end

----------------------------------------------------------------------------------------------
-- Command
----------------------------------------------------------------------------------------------

-- The overlay runs from the module copy of this script, so change settings there.
local module = reqscript('detailed_weather')
local command = ({...})[1]
local how = ({...})[2]
local showing = 'summary'   -- what's printed once the command is done

-- A part set to a level, or a profile: remembered (settings.lua) and handed to the modules.
local LEVEL_WORDS = {off = true, low = true, high = true, on = true}
local setting_changed = false
local function change_setting(ok, why_not)
    if ok then
        module.apply_settings()
        setting_changed = true
    else
        qerror(why_not)
    end
    showing = 'settings'
end
if command == 'profile' then
    change_setting(settings.set_profile(how))
elseif command == 'settings' then
    showing = 'settings'
elseif command == 'sway' then   -- the older name for the trees' sway
    change_setting(settings.set('trees', how == 'off' and 'low' or 'high'))
elseif settings.get(command) and LEVEL_WORDS[how] then
    change_setting(settings.set(command, how))
elseif (command == 'fog' or command == 'leaves' or command == 'petals') and how == 'auto' and settings.get(command) == 'off' then
    change_setting(settings.set(command, 'high'))
end

if setting_changed or showing == 'settings' then
    -- done above
elseif command == 'rain' or command == 'snow' or command == 'off' or command == 'auto' then
    module.force = command
    -- `rain 3`, `snow 4`: also how hard it falls; without a number, or with off or auto, that's
    -- worked out again
    local level = math.tointeger(tonumber(({...})[2]))
    if level and (level < precipitation.LIGHTEST or level > precipitation.HARDEST) then level = nil end
    precipitation.forced = {[command] = level}
elseif command == 'wind' then
    local STRENGTHS = {calm = 0, light = 0.3, breezy = 0.7, strong = 1.0, gale = 1.5}
    local how = ({...})[2]
    wind.force(STRENGTHS[how], ({...})[3])
elseif command == 'textures' then
    -- (testing) free: delete textures when finished with, as 1.3 did; keep (default): never delete
    grass.delete_textures = how == 'free'
elseif command == 'marker' then
    local layer = ({...})[2]
    module.marker_layer = (layer and layer ~= 'off') and layer or nil
elseif command == 'fog' then
    module.fog_mode = ({...})[2] or 'auto'
elseif command == 'colour' then
    if how == 'auto' then colour.forced_step = nil
    elseif tonumber(how) then colour.forced_step = math.max(-colour_looks.COLD_STEPS, math.min(colour_looks.WARM_STEPS, math.floor(tonumber(how)))) end
    if colour.state then colour.state.next_sample = 0 end
elseif command == 'frost' and how == 'old' then   -- (testing) the old floor effects
    frost.floor_effects = ({...})[3] ~= 'off'
    frost.forget()
elseif command == 'frost' and how == 'flips' then   -- (diagnostic, grungeisdead's copy) frost.lua: FLIPS KEPT TO LOOK AT
    frost.dump_flips()
elseif command == 'snowshot' then   -- (diagnostic, grungeisdead's copy, 2026-11-17) snow_ramps.lua: SNOWSHOT
    snow_ramps.arm_shot()
elseif command == 'native' then   -- (grungeisdead's copy, 2026-11-18) native.lua: the hook DLL's snow
    native.command(how)
    return
elseif command == 'install' or command == 'uninstall' then   -- (grungeisdead's copy, 2026-11-20, test 16A) install.lua
    if not install then
        print('detailed_weather: internal/detailed_weather/install.lua is missing from this copy')
        return
    end
    if command == 'uninstall' then
        local ok, why = install.uninstall()
        print(ok and 'detailed_weather: the hook DLL is out of DF\'s folder; DF loads it no more from its next start'
            or ('detailed_weather: not uninstalled: %s'):format(tostring(why)))
        return
    end
    local what, why = install.check(false)
    local said = {
        current = 'the hook DLL in DF\'s folder is already this copy\'s',
        installed = 'the hook DLL is installed in DF\'s folder; close DF completely and start it again to use it',
        updated = 'the hook DLL in DF\'s folder is updated; close DF completely and start it again to use it',
        newer = 'DF\'s folder holds a newer hook DLL than this copy\'s; left alone',
    }
    print('detailed_weather: ' .. (said[what] or ('not installed: %s (%s)'):format(tostring(why), install.log_path())))
    return
elseif command == 'leaves' then
    leaves.mode = ({...})[2] or 'auto'
elseif command == 'petals' then
    leaves.petals_mode = ({...})[2] or 'auto'
elseif command == 'wetness' then
    local how = ({...})[2] or 'auto'
    local LEVELS = {dry = 0, average = 0.5, wet = 1}
    wetness.forced = LEVELS[how] or (tonumber(how) and math.max(0, math.min(1, tonumber(how)))) or nil
    if colour.state then colour.state.next_sample = 0 end
elseif command == 'ground' then
    module.ground_mode = ({...})[2] or 'on'
    if module.ground_mode == 'off' then ground.clear_cache() end
elseif command == 'temperature' then
    ground.forced_celsius = tonumber(({...})[2])
    ground.clear_cache()
    frost.forced_celsius = tonumber(({...})[2])
    frost.forget()
elseif command == 'reload' then
    module.reload_count = module.reload_count + 1
    module.art = nil
    ground.clear_cache()
    snow_ramps.load_art(art_path('snow_ramps.png'))
    colour.reset()
    colour.forget_sheets()
    murky.clear_cache()
    frost.clear_cache()
    frost.forget()
    shade.clear_cache()
    paths.clear_cache()
end

-- The short summary: what it's showing now, in words, in lines narrow enough for the launcher.
local function show_summary()
    local function line(label, text) print(('  %-10s %s'):format(label, text)) end
    print('Detailed Weather')
    if not dfhack.isMapLoaded() then
        print('  No fort loaded.')
        return
    end
    local view = guidm.Viewport.get()
    local x, y = (view.x1 + view.x2) // 2, (view.y1 + view.y2) // 2
    -- 'heavy rain', 'a blizzard': what's falling and how hard
    local function falling_name(kind)
        return precipitation.NAMES[kind][precipitation.level(kind, module.force == kind)]
    end
    local game_weather = grass.ground_weather(x, y, view.z)   -- (GROUND WEATHER)
    local here = game_weather == df.weather_type.Rain and falling_name('rain')
        or game_weather == df.weather_type.Snow and falling_name('snow') or 'clear'
    local shown = here   -- following the game
    if settings.get('weather') == 'off' and module.force ~= 'rain' and module.force ~= 'snow' then
        shown = 'not drawn (weather is off)'
    elseif module.force == 'off' then
        shown = 'none drawn (forced)'
    elseif module.force == 'rain' or module.force == 'snow' then
        shown = falling_name(module.force) .. ' (forced)'
    end
    line('Weather', shown)
    line('Wind', wind.summary() .. (wind.is_forced() and ' (forced)' or ''))
    local FOG = {[0] = 'none', 'mist', 'fog', 'thick fog'}
    local fog_mode = module.fog_mode   -- the overlay's, not this command's copy
    local fog = fog_mode == 'auto' and fort_world_tile().clouds.fog or tonumber(fog_mode) or 0
    line('Fog', fog_mode == 'off' and 'off' or (FOG[fog] or 'none') .. (fog_mode ~= 'auto' and ' (forced)' or ''))
    local TEMPERATURE = {[-5] = 'freezing', [-4] = 'very cold', [-3] = 'cold', [-2] = 'chilly', [-1] = 'cool', [0] = 'mild',
                         [1] = 'warm', [2] = 'very warm', [3] = 'hot', [4] = 'scorching'}
    local look = colour.mode == 'off' and 'off' or 'starting'
    if colour.mode ~= 'off' and colour.state and colour.state.look then
        look = TEMPERATURE[colour.state.look.temperature] or tostring(colour.state.look.temperature)
        if colour.forced_step then look = look .. ' (forced)' end
    end
    line('Ground', look)
    local wet = wetness.level()
    line('Wetness', (wet < 0.25 and 'dry' or wet < 0.75 and 'average' or 'wet')
        .. (wetness.forced and ' (forced)' or ''))
    line('Leaves', leaves.summary('leaves'))
    line('Blossom', leaves.summary('petals'))
    -- the profile, and with a mix of settings the parts that aren't at high
    local profile = settings.profile()
    line('Profile', profile)
    if profile == 'custom' then
        local reduced = {}
        for _, part in ipairs(settings.PARTS) do
            local level = settings.get(part.name)
            if level ~= 'high' then reduced[#reduced + 1] = part.name .. ' ' .. level end
        end
        line('', table.concat(reduced, ', '))
    end
    line('Time', ('%.1f ms a frame'):format(module.profile.average))
    -- textures let go and kept, not deleted (grass.lua)
    line('Let go', ('%d textures kept, about %d MB'):format(grass.kept_count, grass.kept_count * 4 // 1024))
    for report, count in pairs(module.stage_errors) do
        print(('  A part failed %d time%s: %s'):format(count, count == 1 and '' or 's', report))
    end
    for name, rest in pairs(module.stage_rests) do
        print(('  %s is resting after %d failure%s in a row; it is tried again every so often.'):format(
            name, rest.failures, rest.failures == 1 and '' or 's'))
    end
    print('"detailed_weather settings" for what\'s on; "help detailed_weather" for commands.')
end

-- Each part, what it's set to and what that gives.
local function show_settings()
    print('Detailed Weather settings')
    for _, text in ipairs(settings.lines()) do print(text) end
    print('"detailed_weather <part> off|low|high" sets one; "detailed_weather profile off|low|medium|high" sets all.')
end

-- Everything, with timings, for working on the mod.
local function show_details()
    local here = 'no map loaded'
    if dfhack.isMapLoaded() then
        local view = guidm.Viewport.get()
        local x, y = (view.x1 + view.x2) // 2, (view.y1 + view.y2) // 2
        here = df.weather_type[grass.ground_weather(x, y, view.z)]   -- (GROUND WEATHER)
    end
    print(('detailed_weather: weather %s; ground %s (temperature %s); weather in view: %s'):format(
        module.force, module.ground_mode, ground.forced_celsius and (ground.forced_celsius .. ' C, forced') or 'the game\'s',
        here))
    print('  wind: ' .. wind.describe())
    print('  rain and snow: ' .. precipitation.describe())
    print(('  overlay: %.2f ms a frame on average, worst %d ms (%s) over %d frames; view moved %d times'):format(
        module.profile.average, module.profile.worst, module.profile.worst_parts, module.profile.frames,
        module.profile.rescans.view_moved or 0))
    -- STAGE TIMING: each stage's average a frame since last shown, costliest first; untimed is the
    -- frame's time outside every stage (tile-info is its own overlay, not part of the frame)
    local frames = math.max(1, module.profile.frames)
    local stages, inside = {}, 0
    for name, ms in pairs(module.stage_ms) do
        stages[#stages + 1] = {name, ms / frames}
        if name ~= 'tile-info' then inside = inside + ms end
    end
    stages[#stages + 1] = {'untimed', math.max(0, (module.profile.precise_ms or 0) - inside) / frames}
    table.sort(stages, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for _, st in ipairs(stages) do parts[#parts + 1] = ('%s %.2f'):format(st[1], st[2]) end
    print(('  stages, ms a frame on average: %.2f in all; %s'):format((module.profile.precise_ms or 0) / frames,
        table.concat(parts, ', ')))
    for k in pairs(module.stage_ms) do module.stage_ms[k] = nil end
    module.profile.precise_ms = 0
    module.profile.worst, module.profile.worst_parts, module.profile.frames, module.profile.rescans = 0, '', 0, {}
    print(('  fog %s (at the fort now: %s), %s'):format(module.fog_mode,
        dfhack.isMapLoaded() and df.fog_type[fort_world_tile().clouds.fog] or '-',
        native.wfog_running() and 'drawn by the hook DLL (detailed_weather native)' or ('drawing %.2f ms a frame'):format(module.fog_ms)))
    print(('  rescans (4 a second): rain %.1f ms, fog %.1f ms'):format(module.scan_ms.rain, module.scan_ms.fog))
    -- the shared time for planning and making textures (work_time.lua), since the last `details`
    local work = work_time.stats
    print(('  background work: %.2f ms a frame of the %d shared; all used in %d of %d frames'):format(
        work.work_ms / math.max(1, work.frames), work_time.POOL_MS, work.used_up, work.frames))
    work.frames, work.used_up, work.work_ms = 0, 0, 0
    print('  colour: ' .. colour.describe())
    print('  shade ' .. shade.describe())
    print('  spatter in the grass ' .. spatter.describe())
    print('  murky water ' .. murky.describe())
    print('  ' .. leaves.describe() .. (native.leaves_running() and ' (drawn by the hook DLL: detailed_weather native)' or ''))
    print('  paths ' .. paths.describe())
    print(('  frost %s (temperature %s): planning %.1f ms (once a second, new or due tiles only), drawing %.2f ms a frame'):format(
        module.frost_mode, frost.forced_celsius and (frost.forced_celsius .. ' C, forced') or 'the game\'s',
        frost.timing.plan, frost.timing.apply))
    -- COUNTS (grungeisdead's copy): what frost baked and why since last shown (frost.lua)
    local fc, parts = frost.counts or {}, {}
    for _, k in ipairs({'ramp bakes', 'crack bakes', 'other bakes', 'waited', 'new_base', 'ramp textures seen', 'clears'}) do
        parts[#parts + 1] = ('%s %d'):format(k, fc[k] or 0)
    end
    print(('  frost counts: %s; %d baked textures kept'):format(table.concat(parts, ', '), frost.baked_count or 0))
    -- (grungeisdead's copy, 2026-11-17) what the texture under the ramps changed from and to (frost.lua)
    local bases = {}
    for k, v in pairs(fc) do
        if type(k) == 'string' and k:find('^new base: ') then bases[#bases + 1] = ('%s %d'):format(k:sub(11), v) end
    end
    table.sort(bases)
    if #bases > 0 then print('  frost new bases: ' .. table.concat(bases, '; ')) end
    -- (grungeisdead's copy, 2026-11-17) the ramps' waits by what showed meanwhile, the bakes made ahead
    -- for the next look, and each bake's cost (frost.lua: WAITS BY WHAT SHOWED, THE NEXT LOOK AHEAD,
    -- BAKE COST)
    local waits = {}
    for k, v in pairs(fc) do
        if type(k) == 'string' and k:find('^ramp waits: ') then waits[#waits + 1] = ('%s %d'):format(k:sub(13), v) end
    end
    table.sort(waits)
    print(('  frost ramp waits: %s; baked ahead for the next look %d'):format(
        #waits > 0 and table.concat(waits, '; ') or 'none', fc['baked ahead'] or 0))
    local bm = frost.bake_ms
    if bm and bm.n > 0 then
        print(('  frost bake cost, %d bakes: %.2f ms each (redrawing %.2f, making the texture %.2f)'):format(
            bm.n, (bm.bake + bm.make) / bm.n, bm.bake / bm.n, bm.make / bm.n))
        bm.n, bm.bake, bm.make = 0, 0, 0
    end
    -- (grungeisdead's copy, 2026-11-17) the new bases sorted, and the ramps left showing one of colour's
    -- copies (frost.lua: NEW BASES SORTED, ALREADY IN THE LOOK)
    local nb = {}
    for k, v in pairs(fc) do
        if type(k) == 'string' and k:find('^nb ') then nb[#nb + 1] = ('%s %d'):format(k:sub(4), v) end
    end
    table.sort(nb)
    if #nb > 0 then print('  frost new bases sorted: ' .. table.concat(nb, '; ')) end
    print(('  frost ramps showing a copy already in the look, left as they are: %d'):format(
        fc['ramps showing a copy already in the look'] or 0))
    -- (grungeisdead's copy, 2026-11-17) frost.lua: LEVELS THE GAME DRAWS, NOT DRAWN YET, LEVELS BELOW ON A MOVE
    print(('  frost tiles left alone: on levels the game isn\'t drawing %d; the game hadn\'t drawn yet %d; below, kept for the frame of a move %d'):format(
        fc['tiles on levels the game isn\'t drawing'] or 0, fc['tiles the game hadn\'t drawn yet'] or 0,
        fc['tiles below kept for the frame of a move'] or 0))
    for k in pairs(fc) do if k ~= 'ramp_bases' then fc[k] = nil end end
    fc['ramp textures seen'] = nil
    -- COUNTS: why the trees', shrubs', boulders' and buildings' copies were made since last shown
    -- (colour.lua's own screen_counts, which only its profiling tool printed)
    local sc, list = colour.screen_counts or {}, {}
    for k, n in pairs(sc) do if k:find('^copies') then list[#list + 1] = ('%s %d'):format(k, n) end end
    table.sort(list)
    print('  screen copies: ' .. (#list > 0 and table.concat(list, '; ') or 'none'))
    for k in pairs(sc) do if k:find('^copies') then sc[k] = nil end end
    -- COPY TIMING: each copy's cost on average, by part (colour.lua's redrawn_copy)
    local cm = colour.copy_ms
    if cm and cm.n > 0 then
        print(('  copy cost, %d copies: %.2f ms each (reading %.2f, redrawing %.2f, making the texture %.2f)'):format(
            cm.n, (cm.read + cm.redraw + cm.make) / cm.n, cm.read / cm.n, cm.redraw / cm.n, cm.make / cm.n))
        cm.n, cm.read, cm.redraw, cm.make = 0, 0, 0, 0
    end
    print(('  ramps %s: planning %.1f ms (4 times a second, new or due tiles only), drawing %.2f ms a frame'):format(
        module.ramps_mode, snow_ramps.timing.plan, snow_ramps.timing.apply))
    -- (grungeisdead's copy, 2026-11-17) snow_ramps.lua: UNDRAWN CELLS, STILL OURS and HELD, what the
    -- snow kept, held and let go since last shown
    local nc = snow_ramps.counts or {}
    print(('  snow records: %d frames the view moved; made for tiles with none %d; taken from another level %d; let go %d; kept on the frame of a move %d; left for a frame %d (cell not drawn yet), %d (another texture of ours there); ramps seen under a new number %d'):format(
        nc['frames the view moved'] or 0, nc['records made for tiles with none'] or 0,
        nc['records taken from another level'] or 0, nc['records let go'] or 0,
        nc['records kept for the frame of a move'] or 0, nc['records left for a cell the game hadn\'t drawn yet'] or 0,
        nc['records left for a frame: another texture of ours there'] or 0, nc['ramps seen under a new number'] or 0))
    -- (grungeisdead's copy, 2026-11-17) snow_ramps.lua: ANY FULL PIECE
    print(('  snow floors drawn over another of the game\'s full pieces: %d'):format(nc['floors over another full piece'] or 0))
    print(('  snow held: cells still drawn from before %d; tiles held %d (cell still showed earlier drawing), %d (cell not drawn yet), %d (snowy, the game\'s snow not drawn there yet), %d (below, the frame of a move); held tiles worked out once drawn %d'):format(
        nc['cells still drawn from before'] or 0, nc['tiles left: their cell still showed earlier drawing'] or 0,
        nc['tiles left for a cell the game hadn\'t drawn yet'] or 0, nc['tiles left: snowy, the game\'s snow not drawn there yet'] or 0,
        nc['tiles below left for the frame of a move'] or 0, nc['held tiles worked out once drawn'] or 0))
    -- (grungeisdead's copy, 2026-11-17) snow_ramps.lua: KEEP THE VIEW'S, how much the snow keeps, and the
    -- memory of DFHack's Lua (all its scripts, the snow's records among them)
    print(('  snow kept: %d records, %d tiles worked out; past their most %d times (records), %d (tiles), all but the view\'s let go; Lua\'s memory %.0f MB'):format(
        snow_ramps.drawn_count or 0, snow_ramps.remembered_count or 0, nc['records past their most'] or 0,
        nc['worked-out tiles past their most'] or 0, collectgarbage('count') / 1024))
    -- (grungeisdead's copy, 2026-11-17) grass.lua: PIXELS KEPT, about 136 KB a texture (measured, Lua 5.3)
    print('  textures: ' .. grass.describe_textures())
    for k in pairs(nc) do nc[k] = nil end
    -- (grungeisdead's copy, 2026-11-17) snow_ramps.lua: COSTS, the time a tile took to work out
    local sc = snow_ramps.costs or {}
    local plan_n, work_n = sc.plan_n or 0, sc.work_n or 0
    print(('  snow costs: %d tiles planned, %.1f us each (with any working out); %d of them worked out from the map, %.1f us each'):format(
        plan_n, plan_n > 0 and (sc.plan_s or 0) / plan_n * 1e6 or 0, work_n, work_n > 0 and (sc.work_s or 0) / work_n * 1e6 or 0))
    -- (grungeisdead's copy, 2026-11-17) snow_ramps.lua: LEVELS SHARED, tiles new to a level tried against
    -- another level's records
    local tries = sc.adopt_tries or 0
    print(('  snow from other levels: %d tiles new to a level tried, %d took another level\'s record, %.1f us a try'):format(
        tries, sc.adopt_n or 0, tries > 0 and (sc.adopt_s or 0) / tries * 1e6 or 0))
    sc.plan_n, sc.plan_s, sc.work_n, sc.work_s = 0, 0, 0, 0
    sc.adopt_tries, sc.adopt_n, sc.adopt_s = 0, 0, 0
    print(('  ground: planning %.1f ms (4 times a second, new or due tiles only), drawing %.2f ms a frame, %d textures baked'):format(
        ground.timing.plan, ground.timing.apply, ground.baked_count))
end

if command == 'details' then show_details() elseif showing == 'settings' then show_settings() else show_summary() end
