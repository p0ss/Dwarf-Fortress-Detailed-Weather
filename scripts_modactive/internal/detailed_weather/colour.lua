-- The ground's look by the weather, for Detailed Weather: temperature and wetness, one look for
-- the whole map (looks.lua has the rules: colour by temperature and wetness, the dry effects, and
-- the wet overlays of rime, after-rain wet and humid glisten).
--
-- How: the game draws each ground texture through its own tables of texture numbers
-- (gps.texture_indices1-11, and each grass's raw texpos), which it reads as it draws; pointing an
-- entry at another texture changes that texture everywhere it's used, edges and every level
-- included (tested with magenta). Changing a texture's pixels in place does nothing (the game
-- draws from copies on the graphics card), nor does changing a tile page. So for each look, a
-- redrawn copy of every ground texture is needed, and once the set is complete every entry is
-- pointed at its copy at once. Nothing is drawn per frame; the cost is the copies (4 KB each, ~900
-- of them) and making them.
--
-- Detailed Landscapes' ground comes pre-rendered (art/looks/, made by tools/weather/make_looks.py
-- running looks.lua): a sheet per look, loaded when the look is first wanted, so it shows at once.
-- A sheet stays loaded for the session (DFHack keeps a loaded file's textures by its path, so a
-- freed one can't be loaded again). Each of its textures is only used where the game's texture is
-- the one it was made from (a hash of a few pixels). DFHack's loader premultiplies a see-through
-- pixel's colour by its alpha (the game's own textures aren't, so they'd draw too dark), so the
-- textures with partly see-through pixels (grass edges) are remade from the loaded ones with the
-- alpha divided back out (to within half a level on screen) before the look shows. Everything else (other mods' art, and what's
-- seen on screen below) is redrawn here, a few milliseconds a frame, in the background.
--
-- What's redrawn: the ground (every texture on its pages, since grass edges are drawn from them
-- without showing in any screen layer), and anything else seen on screen in the plant, building,
-- item and spatter layers (trees, shrubs, boulders, workshops, wagons, farm plots, blood...),
-- copied as it's first seen: there are some 74,000 textures on the game's pages, too many to copy
-- up front. Creature layers aren't looked at, so creatures keep their colours. Each texture's
-- class (grass, dirt, sand, stone, pebbles, or other) comes from the graphics token naming it.
--
-- Much of what's drawn isn't in those tables at all: the game composites trees (trunk, branches,
-- leaves), workshops, wagons and ramps from their parts as it draws, and blood, vomit and mud are
-- page textures no table points at. Those are swapped per tile on screen instead: a few times a
-- second the tiles in view (this level and SCREEN_DEPTHS - 1 below) are looked at, each texture
-- in their plant, building, item and spatter layers gets a redrawn copy the first time it's seen
-- (cached for the look), and every frame those copies are written into place. That costs a
-- lookup and a write per such tile. Detailed Weather's own snow, frost and snowy edges are left.
--
-- The look follows the temperature of the map's surface, not the view: the median of a grid of
-- points over the whole map, each the ground at the top of its column (the map keeps each
-- column's ground level), in steps each way from mild; and the map's wetness (wetness.lua). Each
-- moves only past some margin, so it doesn't flicker. Following the view made the colour swap
-- whenever it went underground (the fort and the inside of hills sit at 8 C) and back up.
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)
local clock_s = reqscript('internal/detailed_weather/clock').s     -- and in seconds, for timing short work

local grass = reqscript('internal/detailed_weather/grass')   -- texture pixels, graphics tokens
local looks = reqscript('internal/detailed_weather/looks')
local wetness = reqscript('internal/detailed_weather/wetness')
local wind = reqscript('internal/detailed_weather/wind')
_G.detailed_weather_made = _G.detailed_weather_made or {}   -- textures the other modules made
-- every texture the tables have been pointed at (a look's copy, a lean frame) -> the game's own,
-- kept in the global table so it outlives this script being loaded again (find_refs)
_G.detailed_weather_pointed_from = _G.detailed_weather_pointed_from or {}
local pointed_from = _G.detailed_weather_pointed_from
local made = _G.detailed_weather_made

local COLD_STEPS, WARM_STEPS = looks.COLD_STEPS, looks.WARM_STEPS   -- temperature steps each side of mild
local WET_STEPS = looks.WET_STEPS
local COLDEST, COOL_FROM = -14, 8     -- C: the full cold look at COLDEST, mild from COOL_FROM: the
                                       -- first, gentlest step from about 5.5 C, so 6 C stays mild (it
                                       -- looked cold at a stronger step: Poss) and a 2-5 C winter cools
local WARM_FROM, HOTTEST = 20, 38     -- mild up to WARM_FROM, the full warm look at HOTTEST
local MARGIN = 0.6                    -- steps a reading must move past before the look changes
local FIRST_BUILD_MS = 8              -- building the first look, with nothing shown yet
local SAMPLE_MS = 5000
local BUILD_MS_PER_FRAME = 3          -- time spent making copies each frame
-- (grungeisdead's copy, 2026-11-16: were 40 and 8) More than this many waiting on screen: this long
-- a frame. A copy took 0.82 ms when these were set and takes 0.14 ms now (looks.lua: COLOUR ONLY,
-- BY COLOUR), so a backlog of trees clears in a frame or two rather than trickling in over seconds.
local BUSY_FROM, BUSY_BUILD_MS = 10, 16
-- (grungeisdead's copy) A strip just panned into view: its copies made in the same frame, up to this.
local STRIP_BUILD_MS = 8
local SEEN_SCAN_MS = 500              -- how often the screen is looked at for new textures
local SEEN_LAYERS = {'background', 'background_two', 'spatter', 'building_one', 'building_two', 'item',
                     'vehicle'}
local SEEN_DEPTHS = 3                 -- this level and two below through open space
local SCREEN_PLAN_MS = 250            -- how often the per-tile swaps are worked out again
-- The ground layer only underground (below): above ground, what's composited there is ramps, and
-- frost.lua (which rebakes every ramp whenever the look isn't mild) shifts those in the same bake,
-- so they aren't fought over.
local SCREEN_LAYERS = {'background', 'background_two', 'spatter', 'building_one', 'building_two', 'item', 'vehicle'}
local UNDERGROUND_KEEP_MS = 30000     -- how long a block's underground tiles are kept
-- (grungeisdead's copy, 2026-11-16: was 15, with only BUILD_MS_PER_FRAME of copying in each pass)
-- On another level, its swaps planned and their copies made in the one frame, up to this: a level of
-- new trees showed the game's colours and changed over seconds; now it's one short hitch.
-- (2026-11-16: was 30. Levels seen for the first time took three frames to plan at 30 a frame, and
-- the levels below showed the game's colours for the first two: zz-swap-watch. new_level_ms keeps how
-- long they take.)
local NEW_LEVEL_PLAN_MS = 50
new_level_ms = new_level_ms or {n = 0, total = 0, worst = 0}   -- levels planned fresh: count, ms in all, worst
local UNDERGROUND_MASK_MS = 2000      -- which screen cells are underground, worked out again this often
-- (grungeisdead's copy, 2026-11-16: was 4) The plans of this many levels are kept, for coming back
-- to one. Past 4 a level's plan was made again from scratch on coming back, over several frames
-- zoomed out, and every tree and plant on it showed the game's colours meanwhile, then changed
-- together (seen in play). A plan is a small table a swapped tile: about 1 MB a level zoomed out.
local KEPT_LEVEL_PLANS = 16
local SCREEN_DEPTHS = 3               -- this level and two below: a tree's lower branches showed two
                                      -- levels down, uncoloured (Poss)
-- DIAGNOSTIC SWITCHES (grungeisdead's copy, 2026-11-16). Each turns off one part of the per-tile
-- swaps, to find which part a flicker comes from (all three flickers seen on zooms and new levels go
-- with the per-tile swaps, and only with them). Set by the zz-tree-switch script; every default is
-- the normal behaviour. Kept in a global so a reload of this file leaves them as set.
--   repaint      the game's own tree pictures repainted (make_screen_copy, switch_screen)
--   depths       how many levels the swaps cover, this one and those below (up to SCREEN_DEPTHS)
--   skip         layers left out of the swaps (by buffer name, 'screentexpos_background'...)
--   trees_only   only tree tiles swapped (walls, ramp tops, shrubs, boulders, buildings left be)
--   new_numbers  a planned cell showing another number follows it (apply_screen)
--   strip        what a pan or zoom brings into view planned at once (update_screen)
--   carry        KEPT THROUGH A BLANK: entries seen lately carried into the next plan (plan_screen)
-- (carry is read as on unless set to false, so a diag table kept from before it existed still has
-- it on)
diag = diag or {repaint = true, depths = SCREEN_DEPTHS, skip = {}, trees_only = false, new_numbers = true, strip = true,
                carry = true}
local ART_DIR = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or '') .. '../../../art/'
local TILE = 32

-- Tile pages whose textures are ground (not the snow, the slope shape maps, skirts or shadows).
local function is_ground_page(token)
    if token:find('OVERLAY') or token:find('SHADOW') or token:find('ARROW') or token:find('CAVERN')
            or token:find('WALL') or token:find('SNOW') or token:find('DETAILED_WEATHER') then
        return false
    end
    for _, word in ipairs({'GRASS', 'FLOORS', 'FLOOR_SAND', 'FLOOR_PEBBLES', 'FLOOR_FURROWED', 'RAMPS'}) do
        if token:find(word) then return true end
    end
    return false
end

forced_step = forced_step or nil   -- `detailed_weather colour N`: a temperature step from -COLD_STEPS to WARM_STEPS
mode = mode or 'on'
screen_mode = screen_mode or 'on'   -- the per-tile swaps on screen (`detailed_weather colour screen on|off`)
sway_mode = sway_mode or 'on'       -- trees swaying in the wind (`detailed_weather sway on|off`)
wave_mode = wave_mode or 'on'       -- gusts sweeping across the grass
rustle_grass_mode = rustle_grass_mode or 'on'   -- and its blades rustling
lean_mode = lean_mode or 'on'       -- the grass leaning in the wind at all
-- the share of its usual time a frame the trees' and buildings' swaps get (settings.lua: less at low)
screen_allowance = screen_allowance or 1

-- The pre-rendered looks' sheets loaded so far, by look key: their handles. Kept across reloads
-- and worlds (see the top).
sheets = sheets or {}
sheet_generation = sheet_generation or 0
local sheet_index   -- art/looks/index.lua, read once

-- After rebuilding the sheets while playing (`detailed_weather reload`): load them afresh. The ones
-- loaded stay in DFHack's cache, so they're loaded by another spelling of their path (looks/./).
function forget_sheets()
    sheets, sheet_index = {}, nil
    sheet_generation = sheet_generation + 1
end

-- A few pixels of a texture (looks at HASH_POINTS), as make_looks.py's pixel_hash has them.
local HASH_POINTS = {}
for k = 0, 15 do HASH_POINTS[#HASH_POINTS + 1] = (k * 389) % (TILE * TILE) end
-- (grungeisdead's copy, 2026-11-16) Read through grass.original_words, so a repainted tree picture
-- (grass.lua: REPAINTED PICTURES) still hashes as the game's own. Each pixel is one uint32, the
-- bytes R, G, B, A little-endian, so the value is the sum the byte reads added up to before.
local function sample_hash(texpos)
    local words, row = grass.original_words(texpos)
    if not words then return nil end
    local hash = 0
    for _, n in ipairs(HASH_POINTS) do
        local v = words[(n // TILE) * row + n % TILE]
        if (v >> 24) > 0 then
            hash = (hash * 31 + v) % 4294967296
        else
            hash = (hash * 31) % 4294967296   -- the game keeps no colour in a fully clear pixel
        end
    end
    return hash
end

-- slot[texpos] = its place in the sheets, for the game's textures that are the ones pre-rendered;
-- partly[texpos] for those partly see-through; and their class as drawn there.
-- art/looks/index.lua, read the first time it's wanted (again after this file is reloaded)
local function load_sheet_index()
    if sheet_index == nil then
        local ok, index = pcall(dofile, ART_DIR .. 'looks/index.lua')
        sheet_index = ok and index or false
    end
    return sheet_index
end

local function find_sheet_slots(refs_of, class_of)
    load_sheet_index()
    local slots, partly = {}, {}
    if not sheet_index then return slots, partly, 0 end
    local pages = {}
    for _, page in ipairs(df.global.texture.page) do pages[page.token] = page end
    local count = 0
    for n, entry in ipairs(sheet_index.textures) do
        local page = pages[entry[1]]
        local i = page and entry[3] * (page.page_dim_x > 0 and page.page_dim_x or 1) + entry[2]
        local texpos = i and i < #page.texpos and page.texpos[i]
        if texpos and refs_of[texpos] and not slots[texpos] and sample_hash(texpos) == entry[5] then
            slots[texpos] = n
            partly[texpos] = entry[6] or nil
            rawset(class_of, texpos, entry[4])
            count = count + 1
        end
    end
    return slots, partly, count
end

-- A copy of a loaded (premultiplied) texture with the alpha divided back out, or nil.
local function unpremultiplied(texpos)
    local surface = texpos and df.global.enabler.textures.raws[texpos]
    if not surface then return nil end
    local ints = df.reinterpret_cast('int32_t', surface)
    local w, h, pitch = ints:_displace(4)[0], ints:_displace(5)[0], ints:_displace(6)[0]
    if w ~= TILE or h ~= TILE then return nil end
    local bytes = df.reinterpret_cast('uint8_t', df.reinterpret_cast('uint64_t', surface):_displace(4)[0])
    local px = {}
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local o = y * pitch + x * 4
            local a = bytes[o + 3]
            local r, g, b = bytes[o], bytes[o + 1], bytes[o + 2]
            if a > 0 and a < 255 then
                r = math.min(255, (r * 255 + a // 2) // a)
                g = math.min(255, (g * 255 + a // 2) // a)
                b = math.min(255, (b * 255 + a // 2) // a)
            end
            px[#px + 1] = (a << 24) | (b << 16) | (g << 8) | r
        end
    end
    local handle = dfhack.textures.createTile(px, TILE, TILE)
    return {handle = handle, texpos = dfhack.textures.getTexposByHandle(handle)}
end

-- The handles of a look's sheet, loading it if it isn't yet; nil if there's none for it.
local function sheet_for(look, key)
    if sheets[key] then return sheets[key] end
    if not load_sheet_index() then return nil end
    local t, w = sheet_index.temperatures, sheet_index.wets
    if look.temperature < t[1] or look.temperature > t[2] or look.wet < w[1] or look.wet > w[2] then return nil end
    local path = ('%slooks/%s%d_%d.png'):format(ART_DIR, ('./'):rep(sheet_generation), look.temperature, look.wet)
    if not dfhack.filesystem.isfile(path) then return nil end
    local handles = dfhack.textures.loadTileset(path, TILE, TILE, false)
    if not handles or #handles == 0 then return nil end
    sheets[key] = handles
    return handles
end

-- state.refs_of[texture]: every table entry pointing at it, found once a world; state.originals: the
-- textures being redrawn; state.class_of[texture]; state.look: {temperature, wet} wanted, state.shown:
-- the key of the look showing (nil: the game's own); state.copies[key][original] = {handle, texpos}
state = state or nil

-- Every table entry pointing at a texture on a tile page, by texture; and the ground's textures,
-- which are shifted from the start.
-- A texture's class, from its graphics token, else its page's.
local CLASS_WORDS = {{'GRASS', 'grass'}, {'PEBBLES', 'pebbles'}, {'SAND', 'sand'}, {'DIRT', 'dirt'},
                     {'SOIL', 'dirt'}, {'FURROWED', 'dirt'}, {'STONE', 'stone'},
                     {'ROUGH_ICE', 'ice'}, {'SMOOTH_ICE', 'ice'}, {'ICE_WALL', 'ice'}, {'SMOOTHED_ICE', 'ice'}}
local function class_from(token)
    for _, word in ipairs(CLASS_WORDS) do
        if token:find('^' .. word[1]) then return word[2] end
    end
end
local function classify(texpos, page_token, tokens)
    local token = tokens[texpos]
    return token and class_from(token) or (page_token and page_token:find('GRASS') and 'grass') or 'other'
end

-- TREE PIECES (grungeisdead's copy, 2026-11-16). Trees are drawn two ways:
--   * species with tree graphics of their own (20 in the test world) straight from their pieces,
--     plant.tree_texture_info (df-structures: pmd_tree_texture_infost), texture numbers the game
--     reads as it draws, as it does the ground's: pointing every piece at magenta turned those
--     trees magenta at once (dw-tree-probe);
--   * the rest (52 there, plum and almond among them): leaves and twigs straight from the shared
--     tree art (tokens TREE_..., the TREES page), and trunks and branches from pictures the game
--     puts together itself from that art, on no tile page (dw-tile-probe, dw-shared-tree-probe),
--     remade under new numbers as it goes and after every zoom.
-- This file used to copy every finished tree picture on screen, tile by tile (plan_cell): the
-- trees shaded over in stages as the view moved, and again on coming back. Now the first kind's
-- pieces are recoloured once a look and pointed at, as the ground is, and change together. The
-- second kind goes tile by tile, and the game's own put-together pictures are repainted too
-- (grass.lua: REPAINTED PICTURES) for the frames after a zoom.
-- THE SHARED TREE ART IS NEVER TOUCHED (2026-11-16). It was pointed at the look's copies for a
-- while, and trees came out two colours at once: never in a vanilla world, and still with the
-- trees' per-tile swaps and repaints turned off, when nothing of Detailed Weather was left on the
-- trees but the tables. The game puts the trunk pictures together from the shared art through the
-- tables, so a picture it built while the art was pointed had the look baked in (and was then
-- coloured again by its copy), and one built before had not. So the shared art keeps the game's
-- own pixels and numbers: it is neither pointed at copies nor repainted (only pictures on no tile
-- page are, plan_cell), and everything built from it is coloured once.
-- Every int32 field and array of pmd_tree_texture_infost, as df-structures names them.
local TREE_FIELDS = {
    'texpos_tree_wood_tile', 'texpos_tree_twigs_full', 'texpos_tree_twigs', 'texpos_overleaves',
    'texpos_tree_overleaves_heavy_branch', 'texpos_tree_cap_pillar', 'texpos_tree_cap_wall_thick',
    'texpos_tree_cap_wall', 'texpos_tree_cap_thick_interior', 'texpos_tree_cap_floor',
    'texpos_tree_cap_ramp', 'texpos_tree_twigs_autumn', 'texpos_overleaves_trunk_autumn',
    'texpos_overleaves_heavy_branch_autumn', 'texpos_tree_core_trunk', 'texpos_tree_core_shadow',
}
-- fn(holder, key, plant_index) for every texture slot of every plant's tree pieces: a field that's
-- one number, an array of them, or (the autumn and core ones) an array of arrays.
local function each_tree_slot(fn)
    for index, plant in ipairs(df.global.world.raws.plants.all) do
        local ok, info = pcall(function() return plant.tree_texture_info end)
        if ok and info then
            for _, name in ipairs(TREE_FIELDS) do
                local got, v = pcall(function() return info[name] end)
                if got and v ~= nil then
                    if type(v) == 'number' then
                        fn(info, name, index)
                    else
                        for i = 0, #v - 1 do
                            local inner = v[i]
                            if type(inner) == 'number' then fn(v, i, index)
                            else for j = 0, #inner - 1 do fn(inner, j, index) end end
                        end
                    end
                end
            end
        end
    end
end

local function find_refs()
    -- the tables may still point at copies a previous run of this script made (the script
    -- loaded again from elsewhere while the game ran: its record was lost, the copies weren't
    -- recognised, and the look and the grass's lean stopped): put back first
    for n = 1, 11 do
        local array = df.global.gps['texture_indices' .. n]
        for i = 0, #array - 1 do
            local original = pointed_from[array[i]]
            if original then array[i] = original end
        end
    end
    for _, plant in ipairs(df.global.world.raws.plants.all) do
        for i = 0, #plant.texpos - 1 do
            local original = pointed_from[plant.texpos[i]]
            if original then plant.texpos[i] = original end
        end
    end
    -- TREE PIECES: and the trees' own pieces
    each_tree_slot(function(holder, key)
        local original = pointed_from[holder[key]]
        if original then holder[key] = original end
    end)
    local on_page, ground, page_of = {}, {}, {}
    for _, page in ipairs(df.global.texture.page) do
        local is_ground = is_ground_page(page.token)
        local excluded = page.token:find('SNOW') or page.token:find('DETAILED_WEATHER')
        for _, texpos in ipairs(page.texpos) do
            if not excluded then on_page[texpos] = true page_of[texpos] = page.token end
            if is_ground then ground[texpos] = true end
        end
    end
    local refs_of = {}
    local function note(array, index)
        local texpos = array[index]
        if on_page[texpos] then
            local list = refs_of[texpos]
            if not list then list = {} refs_of[texpos] = list end
            list[#list + 1] = {array = array, index = index}
        end
    end
    for n = 1, 11 do
        local array = df.global.gps['texture_indices' .. n]
        for i = 0, #array - 1 do note(array, i) end
    end
    for _, plant in ipairs(df.global.world.raws.plants.all) do
        for i = 0, #plant.texpos - 1 do note(plant.texpos, i) end
    end
    -- TREE PIECES: each plant's own, noted as entries like the tables', and marked as pieces with
    -- the shared tree art (by its graphics token, or a page named for trees)
    -- (seen in play 2026-11-16, zz-screen-meter: a level change still coloured up to ~600 tiles of
    -- canopy over the next 3 frames, pieces seen there for the first time.) So the pieces of the
    -- trees growing on this map, and the shared tree art, are copied ahead, in the background,
    -- like the ground: only this map's species, as the other species' pieces (~240 each) would
    -- only take time and texture memory.
    local on_map = {}
    for _, list in ipairs({df.global.world.plants.tree_dry, df.global.world.plants.tree_wet}) do
        for _, tree in ipairs(list) do on_map[tree.material] = true end
    end
    local tree_piece, ahead = {}, {}
    each_tree_slot(function(holder, key, plant_index)
        local texpos = holder[key]
        if texpos and texpos > 0 then
            note(holder, key)
            if on_page[texpos] then
                tree_piece[texpos] = true
                if on_map[plant_index] then ahead[texpos] = true end
            end
        end
    end)
    -- Not the shared tree art (graphics tokens TREE_..., the TREES page): the game builds the trunk
    -- pictures from it through the tables, so it must keep its own numbers (THE SHARED TREE ART IS
    -- NEVER TOUCHED, above). Its leaves and twigs go tile by tile.
    local originals, included, entries = {}, {}, 0
    -- TREE PIECES FIRST (grungeisdead's copy, 2026-11-18). They came after the ground, which shows from
    -- its sheet at once anyway: built after thousands of ground textures, a few a frame and pointed as
    -- they were made, the map's trees changed species by species with long pauses between, seconds
    -- after the first look showed (seen in play in a wet look, where the change is strong enough to see).
    for texpos in pairs(ahead) do
        if refs_of[texpos] and not included[texpos] then originals[#originals + 1] = texpos included[texpos] = true end
    end
    for texpos, list in pairs(refs_of) do
        entries = entries + #list
        if ground[texpos] and not included[texpos] then originals[#originals + 1] = texpos included[texpos] = true end
    end
    local tokens = grass.texture_tokens()
    -- (grungeisdead's copy, 2026-11-16) The shared tree art, listed: its tile-by-tile copies are
    -- made ahead for each look (update: SHARED ART AHEAD), as its numbers can't be pointed.
    local shared_art = {}
    for texpos in pairs(refs_of) do
        local token, page = tokens[texpos], page_of[texpos]
        if (token and token:find('^TREE_')) or page == 'TREES' then shared_art[#shared_art + 1] = texpos end
    end
    -- WATER LEFT ALONE (grungeisdead's copy, 2026-11-16). The river's and brooks' water (the pages
    -- RIVER, BROOK* and FLOWS*: the beds' ripples and the flows' arrows, 16 frames each) and the
    -- liquids' overlays (LIQUIDS) are never swapped tile by tile. zz-swap-watch found the river drawn
    -- in the ground, plant and building layers of the ramp tops and open space along it, under a new
    -- number every frame of its ripple; a swap a frame late there showed the game's colours: the whole
    -- river flashing on zooms, and squares at the shore where its ground and plant layers took turns
    -- (both gone with only trees swapped). Shade and frost leave water alone too. Found by page, and
    -- by graphics token for another mod's water art.
    local water, liquid_overlay = {}, {}
    for texpos, page in pairs(page_of) do
        if page == 'RIVER' or page == 'LIQUIDS' or page:find('^BROOK') or page:find('^FLOWS') then water[texpos] = true end
        if page == 'LIQUIDS' then liquid_overlay[texpos] = true end
    end
    for texpos, token in pairs(tokens) do
        if token:find('^RIVER_') or token:find('^BROOK_') or token:find('^UNDERWATER') or token:find('^UNDERMAGMA') then
            water[texpos] = true
        end
        if token:find('^UNDERWATER') or token:find('^UNDERMAGMA') then liquid_overlay[texpos] = true end
    end
    -- WATER THROUGH THE TABLES (grungeisdead's copy, 2026-11-17). The water takes the look again, as in
    -- Detailed Weather as it came, but through the tables, as the ground does, not tile by tile: the
    -- game then draws the copy itself in every frame of the ripple, at every level, and nothing can
    -- be late (1708 of its 1713 textures are in the tables, measured in play). Its copies are made
    -- after the look's own textures and pointed at all together (update, show). Not the liquids'
    -- depth overlays: the game draws those from the liquid flags (g_src renderer_2d.hpp,
    -- gps.underwater_texpos, undermagma_texpos), in no screen layer, so they couldn't be put back
    -- underground, and the tile-by-tile swaps never reached them either.
    local water_list = {}
    for texpos in pairs(water) do
        if refs_of[texpos] and not liquid_overlay[texpos] then water_list[#water_list + 1] = texpos end
    end
    table.sort(water_list)
    local class_of = setmetatable({}, {__index = function(t, texpos)
        -- (RAMPS IN THE LOOK: a ramp's class is its tiletype's, as the DLL asked about it)
        local class = ramp_class_of[texpos] or classify(texpos, page_of[texpos], tokens)
        rawset(t, texpos, class)
        return class
    end})
    local slots, partly, slotted = find_sheet_slots(refs_of, class_of)
    return {refs_of = refs_of, originals = originals, included = included, entries = entries, class_of = class_of,
            slots = slots, partly = partly, slotted = slotted, from_sheet = {}, remaking = {}, tree_piece = tree_piece,
            on_page = on_page,   -- textures on a tile page: never repainted (the game builds from them)
            urgent = {}, urgent_set = {},   -- tree pieces seen on screen before their turn: made first
            tree_pictures = {},   -- the game's own pictures seen in trees above ground (repainted)
            shared_art = shared_art, art_built = {},   -- the shared tree art, and how far its copies are made, by look
            water = water,   -- WATER LEFT ALONE: the water's textures, never swapped tile by tile
            -- WATER THROUGH THE TABLES: those pointed at copies, how far each look's copies are made,
            -- and the look the water points at now (nil: the game's own)
            water_list = water_list, water_built = {}, water_key = nil,
            plans_by_level = true,   -- PLANS BY MAP LEVEL: a plan entry's first field is its map level
            black = df.global.gps.black_background_texpos[0],   -- the game's empty ground layer: never swapped
            copies = {}, shown = nil, look = nil, next_sample = 0, next_seen = 0}
end

-- Adds anything new on screen (in SEEN_LAYERS, this level and the next) that the tables point at:
-- one layer of one level a call, so a pass is spread over frames. Returns true at a pass's end.
local function look_at_screen(viewport)
    local main = df.global.gps.main_viewport
    local cells = (viewport.x2 - viewport.x1 + 1) * main.dim_y
    local pass = state.seen_pass or 0
    local depth, layer = pass // #SEEN_LAYERS, SEEN_LAYERS[pass % #SEEN_LAYERS + 1]
    local port = depth == 0 and main or df.global.gps.lower_viewport[depth - 1]
    local count = math.min(cells, port.dim_x * port.dim_y)
    local values = port['screentexpos_' .. layer]
    local included, refs_of, originals = state.included, state.refs_of, state.originals
    for i = 0, count - 1 do
        local texpos = values[i]
        -- only the ground goes through the tables (they're shared by every tile, underground too):
        -- anything else (wood, furniture, workshops) is swapped per tile above ground, below
        if texpos > 0 and not included[texpos] and refs_of[texpos]
                and (state.class_of[texpos] ~= 'other' or state.tree_piece[texpos]) then   -- TREE PIECES too
            included[texpos] = true
            originals[#originals + 1] = texpos
        end
    end
    pass = pass + 1
    if pass >= SEEN_DEPTHS * #SEEN_LAYERS then state.seen_pass = nil return true end
    state.seen_pass = pass
    return false
end

-- A copy of a texture redrawn for a look, or nil. Ground (and grass) get the dry and wet effects;
-- anything else only the colour.
-- COPY TIMING (grungeisdead's copy, 2026-11-16), for `detailed_weather details`: every copy made,
-- in three parts, in fractional ms: reading the game's pixels, redrawing them for the look
-- (looks.redraw, which then finds the pixels already read), and making the texture. Added to find
-- what makes a level of new trees fill in slowly, a few copies a frame.
copy_ms = copy_ms or {n = 0, read = 0, redraw = 0, make = 0}
local function redrawn_copy(texpos, look)
    local class = state.class_of[texpos]
    local t0 = clock_s()
    grass.pixels_of(texpos)
    local t1 = clock_s()
    local px = looks.redraw(texpos, class, look, true)
    local t2 = clock_s()
    if not px then return nil end
    local handle = dfhack.textures.createTile(px, 32, 32)
    local copy = {handle = handle, texpos = dfhack.textures.getTexposByHandle(handle)}
    local t3 = clock_s()
    copy_ms.n = copy_ms.n + 1
    copy_ms.read = copy_ms.read + (t1 - t0) * 1000
    copy_ms.redraw = copy_ms.redraw + (t2 - t1) * 1000
    copy_ms.make = copy_ms.make + (t3 - t2) * 1000
    return copy
end

-- Points one texture's entries at its copy for a look (key; nil: back at the original).
local function point(original, key)
    local copy = key and state.copies[key] and state.copies[key][original]
    local texpos = copy and copy.texpos or original
    if texpos ~= original then pointed_from[texpos] = original end
    for _, ref in ipairs(state.refs_of[original]) do ref.array[ref.index] = texpos end
end

----------------------------------------------------------------------------------------------
-- Per tile, on screen: what the tables don't reach
----------------------------------------------------------------------------------------------

-- Textures that are Detailed Weather's own (snow, frost, snowy edges, colour copies), which are
-- left as they are. Gathered again now and then, as the other modules make new ones.
local function our_textures()
    local ours = {}
    for _, set in pairs(state.copies) do for _, c in pairs(set) do ours[c.texpos] = true end end
    for texpos in pairs(state.lean and state.lean.original or {}) do ours[texpos] = true end
    for _, set in pairs(state.screen_copies or {}) do for _, c in pairs(set) do if c then ours[c.texpos] = true end end end
    for _, page in ipairs(df.global.texture.page) do
        if page.token:find('SNOW') or page.token:find('DETAILED_WEATHER') then
            for _, t in ipairs(page.texpos) do ours[t] = true end
        end
    end
    local ok, frost = pcall(reqscript, 'internal/detailed_weather/frost')
    if ok then for _, e in pairs(frost.baked or {}) do if e and e.texpos then ours[e.texpos] = true end end end
    local ok2, snow = pcall(reqscript, 'internal/detailed_weather/snow_ramps')
    if ok2 then
        for _, e in pairs(snow.snowy_overhangs or {}) do if e and e.texpos then ours[e.texpos] = true end end
        for _, e in pairs(snow.thin_faded or {}) do if e and e.texpos then ours[e.texpos] = true end end
        for _, t in pairs(snow.thin_art and snow.thin_art.texpos or {}) do ours[t] = true end
        for t in pairs(snow.snow_made or {}) do ours[t] = true end
        for _, t in pairs(snow.art and snow.art.texpos or {}) do if t then ours[t] = true end end
    end
    return ours
end

local function viewport_at(depth)
    return depth == 0 and df.global.gps.main_viewport or df.global.gps.lower_viewport[depth - 1]
end

-- Works out, for the tiles in view, which layer cells show something to swap and what with:
-- state.screen_plan = {{level, layer, x, y, original, copy, canopy}...}. Not the buffer itself: the game
-- swaps each screen buffer with its _old twin every frame, so it's looked up as it's written. New copies are made while the frame's budget
-- lasts; cells waiting for one are picked up by a later plan.
-- One layer of one level is looked at per call (the whole set is SCREEN_DEPTHS x SCREEN_LAYERS
-- calls, in PASS ORDER), so the work is spread over frames; the plan being drawn is swapped for the
-- new one when it's complete. Returns true when a plan was finished.
-- Underground keeps the game's own colours: the weather is the surface's, but the tables the
-- look is shown through are shared by every tile on the map, so a wooden wall or a stone floor in
-- the fort took the rain's darkening too. So only the ground goes through the tables, and on
-- screen each underground tile gets the game's own ground back every frame; nothing else is
-- swapped there. Read per block, kept a while (it only changes as the fort digs out to the
-- surface).
underground_blocks = underground_blocks or {}
-- READ IN ONE COPY (grungeisdead's copy, 2026-11-16). A block's 16x16 designation flags (1 KB, column
-- by column as designation[bx][by]) are copied out with one memmove and the subterranean bit tested
-- in Lua. Reading each tile's flag through DFHack (a column, a bitfield and its field, per tile) cost
-- some 256 bridge crossings and objects a block, for every block of a level seen for the first time.
-- (grungeisdead's copy, 2026-11-17) Its water too (flow_size, the low three bits), for WATER THROUGH
-- THE TABLES: the second value returned.
local SUBTERRANEAN = 1 << 15   -- tile_designation's subterranean bit (df-structures, df.d_basics.xml)
local FLOW_SIZE = 7            -- and its flow_size, bits 0 to 2
local designation_copy = nil   -- 256 uint32: the block being read, made once
local function underground(x, y, z, now)
    local key = (z * 1024 + x // 16) * 1024 + y // 16
    local b = underground_blocks[key]
    if not b or now - b.at > UNDERGROUND_KEEP_MS then
        local block = dfhack.maps.getTileBlock(x, y, z)
        if not block then return false end
        designation_copy = designation_copy or df.new('uint32_t', 256)
        local _, at = df.sizeof(block:_field('designation'))
        dfhack.internal.memmove(designation_copy, at, 1024)
        local under, wet = {}, {}
        for i = 0, 255 do
            local d = designation_copy[i]
            under[i], wet[i] = d & SUBTERRANEAN ~= 0, d & FLOW_SIZE ~= 0
        end
        b = {under = under, wet = wet, at = now}
        underground_blocks[key] = b
    end
    local i = (x % 16) * 16 + y % 16
    return b.under[i], b.wet[i]
end

-- Textures let go in bulk (an old look's copies, the lean frames) go in grass.lua's trash, which
-- update() empties a few at a time.
local discard = grass.discard

-- For tools/dfhack/weather_profile.lua: where update_screen's time goes, and what it had to make
-- and why, added up since the game started.
screen_ms = screen_ms or {}           -- step of update_screen -> ms
screen_counts = screen_counts or {}   -- what happened -> how many times
pictures_copied = pictures_copied or {}   -- a picture's sample hash -> true once a copy was made of it
local function clocked(step, started)
    screen_ms[step] = (screen_ms[step] or 0) + (clock_ms() - started)
end
local function counted(what) screen_counts[what] = (screen_counts[what] or 0) + 1 end

-- A texture's copy for the screen, made now and kept (false if it can't be redrawn).
-- COPIES BY PICTURE (grungeisdead's copy, 2026-11-16). A whole picture's fingerprint: a hash of
-- all 1024 pixels, not the 16 sample_hash looks at to notice a change, since two of a tree's parts
-- could share those 16. nil if it can't be read.
local function picture_hash(t)
    local px = grass.pixels_of(t)
    if not px then return nil end
    local h = 0
    for n = 1, #px do
        local p = px[n]
        h = (h * 31 + ((p[4] << 24) | (p[3] << 16) | (p[2] << 8) | p[1]) + n) % 2305843009213693951
    end
    return h
end

-- PICTURES BY MEMCMP (grungeisdead's copy, 2026-11-16). Knowing a picture under a new number
-- meant reading all its 1024 pixels through DFHack and hashing them (picture_hash), about half a
-- millisecond each. The game gives its own put-together pictures new numbers after every zoom and on
-- a level not seen before, hundreds at a time, so only a few dozen were known again in the frame and
-- the rest showed the game's colours meanwhile: the river and valley flashing on a zoom out, squares
-- at the shore's corners, leaves on a new level (seen in play; all three gone with the per-tile
-- swaps off, and only then). Now each picture seen keeps a copy of its own pixels, filed by a hash of
-- HASH_POINTS of them; a new number reads those 16, and each picture filed under the same hash is
-- compared with it whole in one memcmp. Kept for the session, whatever the look (they're the game's
-- own pixels, 4 KB each), and let go when the world unloads.
picture_store = picture_store or {}   -- 16-point hash -> list of {buf = ref (the pixels), id = string}
picture_count = picture_count or 0
-- (grungeisdead's copy, 2026-11-17) id -> its filed pixels: for frost.lua's count of how far a ramp's
-- picture changed when its number did (detailed_weather details: frost new bases)
picture_buf = picture_buf or {}
local PICTURE_BYTES = TILE * TILE * 4
local function picture_id_of(t)
    local address = grass.original_address(t)
    if not address then return picture_hash(t) end   -- rows padded: the whole-picture hash, as before
    local px = df.reinterpret_cast('uint32_t', address)
    local h = 0
    for _, n in ipairs(HASH_POINTS) do h = (h * 31 + px[n]) % 4294967296 end
    local list = picture_store[h]
    if list then
        for _, filed in ipairs(list) do
            if dfhack.internal.memcmp(filed.buf, address, PICTURE_BYTES) == 0 then return filed.id end
        end
    else
        list = {}
        picture_store[h] = list
    end
    local buf = df.new('uint32_t', TILE * TILE)
    dfhack.internal.memmove(buf, address, PICTURE_BYTES)
    picture_count = picture_count + 1
    local id = 'm' .. picture_count
    list[#list + 1] = {buf = buf, id = id}
    picture_buf[id] = buf
    return id
end
-- (grungeisdead's copy, 2026-11-17) For frost.lua's ramps: a picture's id by the same filing, so the
-- same picture under a new number is known with 16 reads and a memcmp. nil if it can't be read.
function picture_of(t) return picture_id_of(t) end

dfhack.onStateChange.detailed_weather_pictures = function(event)
    if event == SC_WORLD_UNLOADED then
        for _, list in pairs(picture_store) do for _, filed in ipairs(list) do df.delete(filed.buf) end end
        picture_store, picture_count, picture_buf = {}, 0, {}
    end
end

local function make_screen_copy(t, copies)
    -- COPIES BY PICTURE: the game builds trees, shrubs, boulders and buildings as it draws and hands
    -- freed numbers to new pictures, so the same picture keeps coming back under new numbers as
    -- the view moves. Copies were kept by number, so each came back in the game's own colour and
    -- was made again a few a frame: trees' parts changing colour one by one as the view moved
    -- (seen in play 2026-11-16). Now a picture already copied for this look under another number
    -- gets that copy straight away; only a picture never copied before is redrawn.
    -- (SHOWN LOOK KEPT, grungeisdead's copy, 2026-11-17) Made in the look showing, whose copies these
    -- are. It used the look wanted: while the next look was made (seconds), whatever came on screen
    -- (a tree's remade parts, a new level's trees) showed in the next look's colours, a step off from
    -- the rest, and stayed in this look's copies (seen in play: trees flickering after colour -5).
    local look = state.shown_look or state.look
    local look_key = state.shown or looks.look_key(look)
    state.by_picture = state.by_picture or {}
    local seen = state.by_picture[look_key]
    if not seen then seen = {} state.by_picture[look_key] = seen end
    local picture = picture_id_of(t)
    local same = picture and seen[picture]
    local copy
    if same then
        copy = {handle = same.handle, texpos = same.texpos}
        counted('copies reused: the same picture under another number')
    else
        -- (NATIVE COPIES: painted by the hook DLL when it can, else redrawn here)
        -- WAIT FOR ROOM (grungeisdead's copy, 2026-11-18): with the DLL's pool or ring used up this frame,
        -- nothing is made and the caller tries again next frame (nil, true). It used to be redrawn here
        -- instead, at 0.5 ms each: 4596 copies in a session that way, most of colour's time a frame.
        local busy
        if native_colour then copy, busy = native_paint(t, look, true) end   -- (15Z: a screen copy, filed by picture)
        if busy then return nil, true end
        copy = copy or redrawn_copy(t, look) or false
        if copy and picture then seen[picture] = {handle = copy.handle, texpos = copy.texpos} end
    end
    copies[t] = copy
    -- why it had to be made: the picture under this number changed, or the number is new; and for a
    -- new number, whether the same picture has been copied before under another one
    local hash = sample_hash(t)
    local look_and_hash = hash and (tostring(state.shown) .. ':' .. hash)
    if same then
        -- (counted above)
    elseif state.stale[t] then counted('copies made: the picture under a number changed')
    elseif look_and_hash and pictures_copied[look_and_hash] then counted('copies made: new number, picture copied before')
    else counted('copies made: new number, new picture') end
    if look_and_hash then pictures_copied[look_and_hash] = true end
    local stale = state.stale[t]
    if stale then
        discard(stale.handle)
        state.screen_original[stale.texpos] = nil
        state.stale[t] = nil
    end
    if copy then
        copy.hash = sample_hash(t)
        state.ours[copy.texpos] = true
        state.screen_original[copy.texpos] = t
        -- (grungeisdead's copy) a tree picture of the look showing: the game's own picture repainted
        -- too, for the frames after a zoom (grass.lua: REPAINTED PICTURES)
        if diag.repaint and state.tree_pictures[t] and copies == (state.screen_copies and state.screen_copies[state.shown]) then
            -- (NATIVE COPIES: on the next frame, once the DLL has painted the copy; this frame its
            -- pixels can still be the blank's)
            if native_colour then native_repaints[#native_repaints + 1] = {t, copy.texpos}
            else grass.repaint(t, copy.texpos) end
        end
    end
    -- NATIVE COLOUR (below): a copy for the look showing, or none to be had, told to the hook DLL
    if native_colour and copies == (state.screen_copies and state.screen_copies[state.shown]) then
        native_copy_made(t, copy)
    end
    return copy
end

-- Textures seen on screen still waiting for a copy, made within the frame's budget whatever the
-- plan is looking at. (Copies were only made for the layer being planned, one of SCREEN_LAYERS a
-- frame, and none between plans: a view of trees took over a minute to fill in, Poss.) The plan
-- after picks them up; it's made again straight away while any wait.
local function make_wanted(copies, budget_ends)
    for t in pairs(state.wanted) do
        if clock_ms() >= budget_ends then return end
        -- (WAIT FOR ROOM: the rest wait for the next frame; cleared only once made, as a key can't be
        -- added to the table while it's walked)
        if copies[t] == nil then
            local _, busy = make_screen_copy(t, copies)
            if busy then return end
        end
        state.wanted[t] = nil
    end
end

-- What a tiletype is, worked out once each: df.tiletype.attrs costs ~40 us a lookup, and these are
-- asked for nearly every ground tile in view each time the trees' swaps are planned. (Looked up
-- every time, as they first were, a plan of one layer took some 65 ms: the long frames players
-- saw now and then, and most of what the trees cost while the view moved.)
local TREE = df.tiletype_material.TREE
local CANOPY_SHAPES = {[df.tiletype_shape.BRANCH] = true, [df.tiletype_shape.TWIG] = true}
local tree_tiletype, canopy_tiletype = {}, {}   -- tiletype -> whether it's part of a tree / its branches or twigs
local function remember_tiletype(tiletype)
    local attrs = df.tiletype.attrs[tiletype]
    tree_tiletype[tiletype] = attrs.material == TREE
    canopy_tiletype[tiletype] = attrs.material == TREE and CANOPY_SHAPES[attrs.shape] == true
end

-- ONE TILETYPE LOOKUP A CELL (grungeisdead's copy, 2026-11-16). A tile's tiletype, with whether it's
-- part of a tree and its branches or twigs (where its leaves rustle in the wind) worked out once per
-- tiletype; false off the map. plan_cell looks it up once and keeps it for each check that needs it
-- (it used to look it up again for each: is_tree, then canopy).
local function tiletype_at(x, y, z)
    local tiletype = dfhack.maps.getTileType(x, y, z)
    if tiletype == nil then return false end
    if tree_tiletype[tiletype] == nil then remember_tiletype(tiletype) end
    return tiletype
end

-- A plan entry's key, by level, layer, x and y (KEPT THROUGH A BLANK, plan_screen).
local LAYER_NO = {}
for i, layer in ipairs(SCREEN_LAYERS) do LAYER_NO['screentexpos_' .. layer] = i end
local function cell_key(z, name, x, y) return ((z * 8 + LAYER_NO[name]) * 4096 + x) * 4096 + y end

-- One cell: if it shows something to swap, its entry is added to the plan: {level, layer, x, y,
-- original, copy, canopy}, by map position, so a pan doesn't throw the plan out (the cell's place in
-- the buffer is worked out from the view as it's drawn). (keys: the plan being made's set of keys,
-- which a cell planned is added to.)
-- PLANS BY MAP LEVEL (grungeisdead's copy, 2026-11-16): an entry names its map level (z), not how far
-- below the view it was (depth), so a plan stays good for the levels it shares with the next view:
-- going up a level, the level left and the one below it are already planned as the two levels below
-- (apply_screen works out each entry's depth from the view as it's drawn).
local function plan_cell(plan, name, background, t, x, y, z, now, budget_ends, copies, checked, keys)
    -- (grungeisdead's copy, 2026-11-16) and the game's black, its empty ground layer (all that's
    -- hidden in the levels below), which is never swapped: it went on to the underground and tree
    -- checks below, a block and a tiletype lookup a cell
    if t <= 0 or t == state.black or diag.skip[name] then return end
    -- (grungeisdead's copy, 2026-11-16) What needs nothing is ruled out first, with table lookups
    -- only: the tables' copies (the ground) and Detailed Weather's own textures, unless it's one of
    -- this file's per-tile copies still showing (kept planned, below). Every ground cell used to go
    -- on to the underground check (a block lookup) and is_tree (a tiletype lookup) before being
    -- dropped, so a new level's plan, zoomed out, ran past its frame and the levels below filled in
    -- over the next frames (seen in play: leaves on a level seen for the first time).
    if (pointed_from[t] or made[t] or state.ours[t]) and not state.screen_original[t] then return end
    -- WATER LEFT ALONE (find_refs): the river's water, or a copy of it still showing
    if state.water and state.water[state.screen_original[t] or t] then return end
    -- underground keeps the game's own colours (the ground there is put back every frame:
    -- put_back_underground)
    if underground(x, y, z, now) then return end
    -- ONE TILETYPE LOOKUP A CELL: looked up by the first check below that needs it, kept for the rest
    local tiletype
    if diag.trees_only then   -- (DIAGNOSTIC SWITCHES)
        tiletype = tiletype_at(x, y, z)
        if not tree_tiletype[tiletype] then return end
    end
    -- a cell the game hasn't redrawn since still shows the copy: it stays planned
    -- (else it drops out, the game redraws it, it's planned again: a flicker)
    local was = state.screen_original[t]
    if was then t = was end
    -- in the ground layer, only what's in the tables but not ground (a wooden wall), and a tree's
    -- branches (the game draws some there, composited: they stayed pale, Poss): the ground's in
    -- the tables' look, and composited ramps are frost's
    if background and not (state.refs_of[t] and state.class_of[t] == 'other') then
        if tiletype == nil then tiletype = tiletype_at(x, y, z) end
        if not tree_tiletype[tiletype] then return end
    end
    if not was and (state.ours[t] or made[t]) then return end
    -- TREE PIECES: one seen here joins the look's list at once (not at the next screen scan, up to
    -- half a second off), is copied in the background and pointed at like the ground; and a
    -- look's own copy is never copied again
    if not was and state.tree_piece[t] then
        if not state.included[t] then
            state.included[t] = true
            state.originals[#state.originals + 1] = t
        end
        -- seen before its turn in the list came: made first (update), once
        local shown = state.copies[state.shown]
        if not (shown and shown[t]) and not state.urgent_set[t] then
            state.urgent_set[t] = true
            state.urgent[#state.urgent + 1] = t
        end
        return
    end
    if not was and pointed_from[t] then return end
    -- (grungeisdead's copy) a picture seen in a tree above ground: one to repaint (make_screen_copy)
    -- (only the game's own put-together pictures, on no tile page: a page's art is what the game
    -- builds them from, so repainting it would bake the look into what it builds next)
    if not state.tree_pictures[t] and state.on_page and not state.on_page[t] then
        if tiletype == nil then tiletype = tiletype_at(x, y, z) end
        if tree_tiletype[tiletype] then state.tree_pictures[t] = true end
    end
    local copy = copies[t]
    -- the game builds these pictures (trees, workshops) as it goes and gives a freed number to a
    -- new one: a copy is only used while its number still shows the picture it was made from
    -- (checked once a plan)
    if copy and not checked[t] then
        checked[t] = true
        if sample_hash(t) ~= copy.hash then
            -- (counted for zz-swap-watch: a number found holding another picture than its copy's)
            counted('numbers found holding another picture than their copy')
            -- the old copy stays showing until the new one's made (when the last leaves fell, every
            -- tree changed picture at once and flashed the game's own colours for two seconds: Poss)
            local stale = state.stale[t]
            if stale then discard(stale.handle) state.screen_original[stale.texpos] = nil end
            state.stale[t] = copy
            rawset(state.class_of, t, nil)
            copy, copies[t] = nil, nil
            -- and its sway frames, made from the old picture
            local frames = state.sway and state.sway.frames[t]
            if frames then
                for i, f in pairs(frames) do
                    if type(i) == 'number' and f then
                        -- let go, never deleted (grass.lua: NO TEXTURE IS EVER DELETED)
                        discard(f.handle)
                        state.screen_original[f.texpos] = nil
                    end
                end
                state.sway.frames[t] = nil
            end
        end
    end
    if copy == nil then
        local busy
        if clock_ms() < budget_ends then
            copy, busy = make_screen_copy(t, copies)
            checked[t] = true
        end
        if busy or clock_ms() >= budget_ends and copy == nil then
            state.wanted[t] = true   -- made in a later frame (make_wanted)
            copy = state.stale[t]    -- meanwhile the old picture's copy, if it had one
        end
    end
    -- (grungeisdead's copy, 2026-11-16) A cell whose copy is still to be made is planned too, with no
    -- copy yet: apply_screen finds the copy by the original's number each frame, so the cell is
    -- swapped the frame its copy is made. It used to join the plan only at the next plan's pass over
    -- its layer, up to 21 frames later, showing the game's colours meanwhile. (false: it can't be
    -- redrawn at all.)
    if copy ~= false then
        if tiletype == nil then tiletype = tiletype_at(x, y, z) end
        plan[#plan + 1] = {z, name, x, y, t, copy and copy.texpos or nil, canopy_tiletype[tiletype] or nil}
        if keys then keys[cell_key(z, name, x, y)] = true end
    end
end

-- A level's plan is kept when the view leaves it, so coming back shows the trees in the look's
-- colours at once and not in the game's own while 21 layers are planned again (going up and down
-- through a wood was the worst the mod ran, and the trees flashed pale each time: Poss). A kept
-- plan is by map position and names originals, not copies (apply_screen finds the copy), so one
-- that's out of date only misses what has changed, until the plan made straight after replaces it.
-- (grungeisdead's copy, 2026-11-16) With the view it covers, {x1, y1, cols, rows}: coming back with
-- more in view than that (zoomed out since), the rest is planned in that frame (update_screen).
local function keep_level_plan(z, plan, view)
    state.level_plans = state.level_plans or {}
    state.level_plans[z] = plan
    state.level_views = state.level_views or {}
    state.level_views[z] = view
    -- only the nearest few levels: a plan is a table a swapped tile
    local levels = {}
    for level in pairs(state.level_plans) do levels[#levels + 1] = level end
    if #levels > KEPT_LEVEL_PLANS then
        table.sort(levels, function(a, b) return math.abs(a - z) > math.abs(b - z) end)
        state.level_plans[levels[1]] = nil
        state.level_views[levels[1]] = nil
    end
end

local PLAN_CHUNK = 16   -- cells of a column compared with zeros at once (plan_screen, plan_new_strip)
local CARRY_FRAMES = 45   -- KEPT THROUGH A BLANK: an entry seen, and seen empty, this recently is kept
plan_zeros = plan_zeros or nil   -- PLAN_CHUNK zeros, made once

-- A screen buffer's address (the pointer in its field), or nil if it can't be read; and the
-- PLAN_CHUNK zeros a stretch of it is compared with.
local function buffer_base(port, name)
    local ok, slot = pcall(function() local _, at = df.sizeof(port:_field(name)) return at end)
    if ok and slot then return df.reinterpret_cast('uint64_t', slot).value end
end
local function zeros_chunk()
    if not plan_zeros then
        plan_zeros = df.new('int32_t', PLAN_CHUNK)
        for k = 0, PLAN_CHUNK - 1 do plan_zeros[k] = 0 end
    end
    return plan_zeros
end-- BLACK STRETCHES SKIPPED (grungeisdead's copy, 2026-11-16): the ground layer of the levels below is
-- the game's black wherever they're hidden (most of them), and each black cell was read and looked
-- at; a stretch all black is now passed over in one memcmp too. PLAN_CHUNK of the game's black.
plan_blacks = plan_blacks or nil
local function blacks_chunk()
    if not plan_blacks or plan_blacks.value ~= state.black then
        local buf = df.new('int32_t', PLAN_CHUNK)
        for k = 0, PLAN_CHUNK - 1 do buf[k] = state.black end
        plan_blacks = {buf = buf, value = state.black}
    end
    return plan_blacks.buf
end

-- PASS ORDER (grungeisdead's copy, 2026-11-16): the ground and plant layers of all the levels in view
-- first (where the trees' leaves and branches and the shrubs are), the other five layers after. A
-- level seen for the first time whose plan runs into a second frame then has its trees done on every
-- level, and only the buildings, items and spatter of the lowest wait: it went a level at a time, and
-- the trees of the levels below came in a frame or two late (zz-swap-watch: leaves on first sight).
local pass_orders = {}
local function pass_order(depths)
    local order = pass_orders[depths]
    if order then return order end
    order = {}
    for d = 0, depths - 1 do
        order[#order + 1] = {d, 'background'}
        order[#order + 1] = {d, 'background_two'}
    end
    for d = 0, depths - 1 do
        for _, layer in ipairs(SCREEN_LAYERS) do
            if layer ~= 'background' and layer ~= 'background_two' then order[#order + 1] = {d, layer} end
        end
    end
    pass_orders[depths] = order
    return order
end

local function plan_screen(viewport, key, budget_ends)
    local copies = state.screen_copies[key]
    local scan = state.screen_scan
    if not scan or scan.z ~= viewport.z then
        scan = {z = viewport.z, next = 0, plan = {}, checked = {}, keys = {}}
        state.screen_scan = scan
    end
    local plan = scan.plan
    local pass = scan.next
    scan.next = pass + 1
    local order = pass_order(math.min(SCREEN_DEPTHS, diag.depths))
    local depth, layer = order[pass + 1][1], order[pass + 1][2]
    local port = viewport_at(depth)
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, port.dim_y)
    local now, z = clock_ms(), viewport.z - depth
    local name = 'screentexpos_' .. layer
    local values, background = port[name], layer == 'background'
    -- EMPTY STRETCHES SKIPPED (grungeisdead's copy, 2026-11-16): most layers are mostly empty, and
    -- every cell was read through DFHack's bridge to find that out. Now each column is looked at
    -- PLAN_CHUNK cells at a time, compared with zeros in one memcmp, and only a stretch with
    -- something in it is read cell by cell. The buffer's address is the pointer in its field.
    local base = buffer_base(port, name)
    local zeros, memcmp = zeros_chunk(), dfhack.internal.memcmp
    local blacks = background and state.black and blacks_chunk()   -- (BLACK STRETCHES SKIPPED)
    for sx = 0, cols - 1 do
        local column = sx * port.dim_y
        for sy0 = 0, rows - 1, PLAN_CHUNK do
            local n = math.min(PLAN_CHUNK, rows - sy0)
            local at = base and base + (column + sy0) * 4
            if not at or (memcmp(zeros, at, n * 4) ~= 0 and not (blacks and memcmp(blacks, at, n * 4) == 0)) then
                for sy = sy0, sy0 + n - 1 do
                    plan_cell(plan, name, background, values[column + sy], viewport.x1 + sx, viewport.y1 + sy, z,
                        now, budget_ends, copies, scan.checked, scan.keys)
                end
            end
        end
    end
    if scan.next >= #order then
        -- KEPT THROUGH A BLANK (grungeisdead's copy, 2026-11-16). A layer is looked at once a plan, in
        -- one frame; one that showed nothing just then (in what Weather reads, plants go missing from
        -- a frame now and then after a zoom or pan, though not on screen: NOTHING WRITTEN WHERE IT
        -- ISN'T, apply_screen) left its cells out of the new plan, and they
        -- showed the game's colours until the plan after (zz-swap-watch: plants and leaves "not in the
        -- plan", 21 frames after a zoom). So an entry of the plan being replaced, on this level, that
        -- was seen and showed nothing in the last CARRY_FRAMES frames (cell[8], cell[9]: apply_screen)
        -- and isn't in the new plan, is carried into it.
        local old = state.screen_plan
        if diag.carry ~= false and old and old ~= plan and state.screen_z == viewport.z then
            local keys, recent, carried = scan.keys, screen_frame - CARRY_FRAMES, 0
            for _, cell in ipairs(old) do
                if (cell[9] or -1) >= recent and (cell[8] or -1) >= recent then
                    local k = cell_key(cell[1], cell[2], cell[3], cell[4])
                    if not keys[k] then
                        keys[k] = true
                        plan[#plan + 1] = cell
                        carried = carried + 1
                    end
                end
            end
            screen_counts['cells kept through a blank'] = (screen_counts['cells kept through a blank'] or 0) + carried
        end
        state.screen_plan, state.screen_z = plan, viewport.z
        state.screen_scan = nil
        local main = df.global.gps.main_viewport
        keep_level_plan(viewport.z, plan, {viewport.x1, viewport.y1, math.min(viewport.x2 - viewport.x1 + 1, main.dim_x),
            math.min(viewport.y2 - viewport.y1 + 1, main.dim_y)})
        return true
    end
    return false
end

-- The screen positions a pan or zoom has just brought into view, as runs down each column, a flat
-- list {sx, first row, last row, sx, first, last...} in column order. The part of the screen that
-- was already showing is left out, so a one-tile pan lists one column or row and not the whole view.
-- (grungeisdead's copy, 2026-11-16) Given the part of the screen that was already showing (screen
-- columns kept_x1..kept_x2, rows kept_y1..kept_y2), not how far the view moved, so a zoom out (the
-- view grows) is covered as well as a pan. (Runs, not single cells, so plan_new_strip can skip their
-- empty stretches as plan_screen does: it read every cell of every layer, and a zoom out brings in
-- most of the view at once.)
local function strip_runs(cols, rows, kept_x1, kept_x2, kept_y1, kept_y2)
    local any_rows_kept = kept_y1 <= kept_y2
    local runs = {}
    local function add_run(sx, first, last)
        if first > last then return end
        runs[#runs + 1] = sx
        runs[#runs + 1] = first
        runs[#runs + 1] = last
    end
    for sx = 0, cols - 1 do
        if any_rows_kept and sx >= kept_x1 and sx <= kept_x2 then
            add_run(sx, 0, kept_y1 - 1)          -- above what was showing
            add_run(sx, kept_y2 + 1, rows - 1)   -- and below it
        else
            add_run(sx, 0, rows - 1)
        end
    end
    return runs
end

-- After a pan: the cells just come into view, every layer and level, planned in this frame (the
-- rest of the plan is by map position, so it carries on as it was). Added to the plan being drawn,
-- and to one being made, if any.
-- old: the view before, {x1, y1, cols, rows} (map position of its corner, and its size).
local function plan_new_strip(viewport, key, old, budget_ends)
    local copies = state.screen_copies[key]
    local added = {}
    local checked = state.screen_scan and state.screen_scan.checked or {}
    local now = clock_ms()
    local zeros, memcmp = zeros_chunk(), dfhack.internal.memcmp
    for depth = 0, math.min(SCREEN_DEPTHS, diag.depths) - 1 do
        local port = viewport_at(depth)
        local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
        local rows = math.min(viewport.y2 - viewport.y1 + 1, port.dim_y)
        -- what was showing before, in this view's screen columns and rows
        local kept_x1, kept_x2 = math.max(0, old[1] - viewport.x1), math.min(cols, old[1] + old[3] - viewport.x1) - 1
        local kept_y1, kept_y2 = math.max(0, old[2] - viewport.y1), math.min(rows, old[2] + old[4] - viewport.y1) - 1
        local runs = strip_runs(cols, rows, kept_x1, kept_x2, kept_y1, kept_y2)
        local z = viewport.z - depth
        local dim_y = port.dim_y
        for _, layer in ipairs(SCREEN_LAYERS) do
            local name = 'screentexpos_' .. layer
            local values, background = port[name], layer == 'background'
            -- (EMPTY STRETCHES SKIPPED, and BLACK STRETCHES SKIPPED, as in plan_screen)
            local base = buffer_base(port, name)
            local blacks = background and state.black and blacks_chunk()
            for i = 1, #runs, 3 do
                local sx, first, last = runs[i], runs[i + 1], runs[i + 2]
                local column = sx * dim_y
                for sy0 = first, last, PLAN_CHUNK do
                    local n = math.min(PLAN_CHUNK, last - sy0 + 1)
                    local at = base and base + (column + sy0) * 4
                    if not at or (memcmp(zeros, at, n * 4) ~= 0 and not (blacks and memcmp(blacks, at, n * 4) == 0)) then
                        for sy = sy0, sy0 + n - 1 do
                            plan_cell(added, name, background, values[column + sy],
                                viewport.x1 + sx, viewport.y1 + sy, z, now, budget_ends, copies, checked)
                        end
                    end
                end
            end
        end
    end
    -- (the plan being drawn can be the one being made: a new level's, as it's made; added once then)
    local drawn, making = state.screen_plan, state.screen_scan and state.screen_scan.plan
    local function add_to(list) if list then for _, cell in ipairs(added) do list[#list + 1] = cell end end end
    add_to(drawn)
    if making ~= drawn then
        add_to(making)
        -- (and their keys, so KEPT THROUGH A BLANK doesn't carry them in twice)
        local keys = making and state.screen_scan.keys
        if keys then for _, cell in ipairs(added) do keys[cell_key(cell[1], cell[2], cell[3], cell[4])] = true end end
    end
end

-- Each frame: writes the planned copies, where the cell still shows what was planned. A cell
-- showing something else that has a copy gets that instead: an animated building (a windmill's
-- sails) shows a different picture each frame, and only swapping the one seen when planned made
-- it flash between the look and the game's own colours.
-- NOTHING WRITTEN WHERE IT ISN'T (grungeisdead's copy, 2026-11-17). A cell is only ever given the
-- copy of what it shows: its planned picture, a copy of it, or (below) another picture's own copy.
-- BLANKS FILLED (2026-11-16) gave a planned plant its copy in a frame where the cell showed nothing,
-- for blanks zz-swap-watch saw in what Weather reads at the end of its frame. Those blanks never
-- reach the screen: with trees off the watcher counted thousands and none were seen. The fill
-- itself made plants flicker on zooms in play, and with it off they didn't (2026-11-17), so it's
-- gone. Each entry still notes the frame it was last seen, cell[8], and the frame it last showed
-- nothing, cell[9] (KEPT THROUGH A BLANK, plan_screen).
screen_frame = screen_frame or 0   -- frames the per-tile pass has run (counted in update_screen)
local function apply_screen(viewport)
    local buffers, dims = {}, {}
    local copies = state.screen_copies and state.screen_copies[state.shown] or {}
    local screen_original = state.screen_original or {}
    local sway = state.sway
    local swaying = sway and sway.playing
    local x1, y1 = viewport.x1, viewport.y1
    local cols = viewport.x2 - viewport.x1 + 1
    local rows = viewport.y2 - viewport.y1 + 1
    -- remade pictures (below): copied within this, into the look's own list (not a stand-in table)
    local budget_ends = clock_ms() + STRIP_BUILD_MS * screen_allowance
    local live = state.screen_copies and state.screen_copies[state.shown]
    -- PLANS BY MAP LEVEL: each entry's depth below the view, as it's drawn now (an entry for a level
    -- out of view is passed over); and on a level being planned, its plan so far after the plan drawn
    -- (screen_also, update_screen), as one run of entries
    local view_z, depths, black, now_frame = viewport.z, math.min(SCREEN_DEPTHS, diag.depths), state.black, screen_frame
    local plan, also = state.screen_plan or {}, state.screen_also or {}
    local in_plan = #plan
    for n = 1, in_plan + #also do
        local cell = n <= in_plan and plan[n] or also[n - in_plan]
        local depth = view_z - cell[1]
        local dim = depth >= 0 and depth < depths and dims[depth]
        if depth >= 0 and depth < depths and not dim then
            local port = viewport_at(depth)
            dim = {math.min(cols, port.dim_x), math.min(rows, port.dim_y), port.dim_y}
            dims[depth] = dim
        end
        local sx, sy = cell[3] - x1, cell[4] - y1
        if dim and sx >= 0 and sy >= 0 and sx < dim[1] and sy < dim[2] then
            local name = depth .. cell[2]
            local values = buffers[name]
            if not values then
                values = viewport_at(depth)[cell[2]]
                buffers[name] = values
            end
            local i = sx * dim[3] + sy
            local t = values[i]
            local seen = t == cell[5] or (t ~= 0 and screen_original[t] == cell[5])
            if seen then cell[8] = now_frame elseif t == 0 or t == black then cell[9] = now_frame end
            -- (a cell the game hasn't redrawn still shows a copy or sway frame of it)
            if seen then
                -- (the copy as it is now, not the one noted in the plan: a kept plan can be older
                -- than a copy that was since made again)
                local frames = cell[7] and swaying and sway.frames[cell[5]]
                local texpos = frames and sway_texpos(sway, frames, cell[3], cell[4])
                if not texpos then
                    local copy = copies[cell[5]]
                    texpos = copy and copy.texpos
                end
                if texpos then values[i] = texpos end
            elseif diag.new_numbers then
                local copy = copies[t]
                -- (grungeisdead's copy, 2026-11-16) The game remakes its put-together tree pictures
                -- under new numbers as it goes: some 50 tiles a frame with the view still
                -- (zz-screen-meter, "other"). A new one showed the game's own colours until the
                -- next plan, up to SCREEN_PLAN_MS later, so trunks flickered. Now its copy is made
                -- here, the same frame (or an earlier copy of the same picture reused), and the
                -- cell follows the new number.
                -- (a remade tree picture is a tree picture too: repainted when copied)
                if state.tree_pictures[cell[5]] and t > 0 and state.on_page and not state.on_page[t] then
                    state.tree_pictures[t] = true
                end
                -- (grungeisdead's copy, 2026-11-16) and never the water or the game's black, which
                -- plan_cell leaves out (a planned cell's new number skipped those checks)
                if copy == nil and live and t > 0 and not screen_original[t] and not state.ours[t] and not made[t]
                        and not pointed_from[t] and not state.tree_piece[t] and t ~= state.black
                        and not (state.water and state.water[t]) and clock_ms() < budget_ends then
                    copy = make_screen_copy(t, copies)
                end
                if copy then
                    values[i] = copy.texpos
                    cell[5], cell[8] = t, now_frame
                end
            end
        end
    end
end

-- The trees' sway frames let go (another look, or another wind direction: they're made from the
-- look's copies, shifted downwind).
local function forget_sway()
    local sway = state and state.sway
    if not sway then return end
    for _, frames in pairs(sway.frames) do
        for i, f in pairs(frames) do
            if type(i) == 'number' and f then
                discard(f.handle)
                if state.screen_original then state.screen_original[f.texpos] = nil end
                if state.ours then state.ours[f.texpos] = nil end
            end
        end
    end
    state.sway = nil
    -- NATIVE COLOUR: the DLL forgets them too, and lists the canopy's originals again
    if native_colour then native_sway_forgotten() end
end

local function forget_screen(keep)
    -- (grungeisdead's copy) the game's own pixels back in every repainted tree picture
    grass.unpaint_all()
    -- and the shared art's copies made ahead go with the screen's copies (made again when needed)
    state.art_built = {}
    for key, set in pairs(state.screen_copies or {}) do
        if key ~= keep then
            for _, c in pairs(set) do
                if c then
                    discard(c.handle)
                    if state.screen_original then state.screen_original[c.texpos] = nil end
                end
            end
            state.screen_copies[key] = nil
        end
    end
    for _, c in pairs(state.stale or {}) do
        discard(c.handle)
        if state.screen_original then state.screen_original[c.texpos] = nil end
    end
    state.screen_plan, state.screen_scan, state.wanted, state.stale = nil, nil, {}, {}
    state.level_plans, state.level_views, state.screen_also = nil, nil, nil
    forget_sway()
end



----------------------------------------------------------------------------------------------
-- Grass leaning in the wind
----------------------------------------------------------------------------------------------
-- In wind the whole field leans together and recovers with the gusts: each grass texture in the
-- tables (the clumps and the edge pieces they drop on their neighbours) gets a few leaning frames,
-- made from the look's copy in the background, and the tables are pointed at the frame the gust
-- calls for, as a change of look is. Each pixel moves by its distance from the centre of the
-- clump it belongs to (an edge piece's clump is in the tile beside it), so clumps and their edges
-- lean as one (tools/grass-sway/sway_test.py, which Poss found convincing). Still in calm and
-- light air; a faint lean in a breeze; a hard lean in strong wind's gusts; in a gale, bent over all
-- the time and gusting to LEAN_MOST_PX at a clump's tips.
local LEAN_STEPS = 10              -- frames from upright to the most lean (blended between pixels, so
                                   -- each moves a fraction of one: whole-pixel steps looked juddery)
local LEAN_STEP_MS = 20            -- the lean moves a frame at a time, at most this often
local LEAN_HYSTERESIS = 0.6        -- and only once the gust is this many frames past it (no flicking
                                   -- between two frames as the gust hovers at their boundary)
local LEAN_MOST_PX = 6             -- px at a clump's outer tips, at the most lean (a gale's gust; 4
                                   -- left a gale's grass barely moving: Poss)
local LEAN_REACH_MOST = 1.5        -- in half tiles from the clump's centre, past which pixels move no further
local LEAN_BREEZE_FROM = 0.35      -- wind strength from which the grass leans a little in gusts
local LEAN_STRONG_FROM = 0.9       -- and from which it leans hard
local LEAN_GALE_FROM = 1.3         -- and from which it's bent over all the time, gusting further
local LEAN_STRONG_MOST = 0.42      -- strong wind's gusts lean it this share of the most (2.5 px)
local LEAN_GALE_BASE = 0.33        -- a gale holds it this share of the most between gusts (2 px)
local LEAN_BREEZE_MOST = 0.083     -- the breeze's gusts lean it this share of the most (0.5 px; 1 px was a
                                   -- little strong, Poss)

lean_state = lean_state or {clock = 0, last = nil}

-- Where a grass texture sits from the clump it belongs to, in tiles: a clump fills its tile (0, 0);
-- an edge piece's grass lies towards its clump's side. nil if it's neither (no pixels).
local function clump_offset(px)
    local count, opaque, mx, my = 0, 0, 0, 0
    for i, p in ipairs(px) do
        local a = p[4]
        if a > 0 then
            count = count + a
            if a > 200 then opaque = opaque + 1 end
            local x, y = (i - 1) % TILE, (i - 1) // TILE
            mx, my = mx + (x - (TILE - 1) / 2) * a, my + (y - (TILE - 1) / 2) * a
        end
    end
    if count == 0 then return nil end
    if opaque > #px * 0.9 then return 0, 0 end
    mx, my = mx / count, my / count
    local sx = mx > 3 and 1 or mx < -3 and -1 or 0
    local sy = my > 3 and 1 or my < -3 and -1 or 0
    if sx == 0 and sy == 0 then return 0, 0 end
    return -sx, -sy   -- the grass is towards the clump: the tile is on the far side of it
end

-- A grass texture's pixels leaning `amount` px at the tips towards (ux, uy), packed for createTile.
-- A clump wraps (its tile repeats seamlessly); an edge piece pulls in its own pixels mirrored at
-- its border. Stretching the border's pixels showed as streaks at 6 px (Poss); pulling in nothing
-- left a gap on the side facing its clump, the tile under it showing through as a thin line (Poss).
-- Mirrored, that side stays grass, and the far sides, see-through near the border, stay clear.
-- Each pixel is read from a point a fraction of a pixel away, blended from the four round it (the
-- colours weighted by their opacity, so see-through edge pixels don't darken what they touch).
local function leaning(px, ox, oy, amount, ux, uy)
    local out = {}
    local wrap = ox == 0 and oy == 0   -- clumps tile seamlessly; edge pieces mirror at their border
    local half = TILE / 2
    local function mirror(v)
        if v < 0 then return -v - 1 elseif v >= TILE then return 2 * TILE - v - 1 end
        return v
    end
    local function at(x, y)
        if wrap then x, y = x % TILE, y % TILE else x, y = mirror(x), mirror(y) end
        return px[y * TILE + x + 1]
    end
    for y = 0, TILE - 1 do
        local cy = y + 0.5 + oy * TILE - half
        for x = 0, TILE - 1 do
            local cx = x + 0.5 + ox * TILE - half
            local reach = math.min(LEAN_REACH_MOST, math.sqrt(cx * cx + cy * cy) / half)
            local shift = amount * reach
            local fx, fy = x - ux * shift, y - uy * shift
            local x0, y0 = math.floor(fx), math.floor(fy)
            local tx, ty = fx - x0, fy - y0
            local r, g, b, a = 0, 0, 0, 0
            for _, c in ipairs({{x0, y0, (1 - tx) * (1 - ty)}, {x0 + 1, y0, tx * (1 - ty)},
                                {x0, y0 + 1, (1 - tx) * ty}, {x0 + 1, y0 + 1, tx * ty}}) do
                local w = c[3]
                if w > 0 then
                    local p = at(c[1], c[2])
                    local wa = w * p[4]
                    r, g, b, a = r + p[1] * wa, g + p[2] * wa, b + p[3] * wa, a + wa
                end
            end
            if a > 0 then r, g, b = r / a, g / a, b / a end
            out[y * TILE + x + 1] = (math.floor(a + 0.5) << 24) | (math.floor(b + 0.5) << 16)
                | (math.floor(g + 0.5) << 8) | math.floor(r + 0.5)
        end
    end
    return out
end

-- A set no longer showing is kept by its key (look and wind direction), frames and all, and
-- new_lean hands it back when that look and wind come round again. Its textures are never deleted
-- (grass.lua: NO TEXTURE IS EVER DELETED), so remaking a set each time would only pile up
-- copies; kept, there is at most one set per look and direction.
local function free_lean(l)
    if not l or not state then return end
    state.lean_cache = state.lean_cache or {}
    state.lean_cache[l.key] = l
end

local function forget_lean()
    if not state then return end
    free_lean(state.lean)
    state.lean = nil
end

-- Also the set being made for a change of look or wind (a world unloading, the look turned off).
local function forget_all_lean()
    if not state then return end
    forget_lean()
    free_lean(state.next_lean)
    state.next_lean = nil
end

-- The lean the wind calls for now, 0 to 1, and its direction (a unit vector, eight ways).
-- Gusts, as passing events with stillness between (a field swaying all the time made Poss
-- seasick): every so often one comes through, builds, holds a moment and settles. Strong wind and
-- gales don't gust: they surge and ease all the time (RHYTHMS).
local GUSTS = {   -- seconds between gusts (from, to), and how hard they lean (share of the most)
    breeze = {every = {20, 40}, size = {0.6, 1.0}},
}
local GUST_RISE, GUST_HOLD, GUST_FALL = 0.6, 0.5, 1.2   -- seconds
local RHYTHMS = {gale = {surge = 2.6, flutter = 0.9}, strong = {surge = 3.4, flutter = 1.3}}   -- seconds
local STRONG_BASE = 0.2                                  -- strong wind holds this share of its most

local function between(range) return range[1] + math.random() * (range[2] - range[1]) end

local function wanted_lean()
    local wx, wy, strength = wind.get()
    if strength < LEAN_BREEZE_FROM then return 0 end
    -- game time: still when paused
    local now = clock_ms()
    if lean_state.last and not df.global.pause_state then
        lean_state.clock = lean_state.clock + math.min(100, now - lean_state.last) / 1000
    end
    lean_state.last = now
    local t = lean_state.clock
    local kind = strength < LEAN_STRONG_FROM and 'breeze' or strength < LEAN_GALE_FROM and 'strong' or 'gale'
    local angle = math.floor(math.atan(wy, wx) / (math.pi / 4) + 0.5) * (math.pi / 4)
    local direction = math.floor(angle / (math.pi / 4) + 0.5) % 8
    if kind == 'gale' or kind == 'strong' then
        -- strong wind and gales never let up: the grass rises and falls all the time, on two
        -- rhythms out of step (waiting between gusts left it still too long: Poss); strong wind
        -- slower and gentler
        local r = RHYTHMS[kind]
        local g = 0.5 + 0.3 * math.sin(2 * math.pi * t / r.surge) + 0.2 * math.sin(2 * math.pi * t / r.flutter + 1.3)
        g = math.max(0, math.min(1, g))
        local amount = kind == 'gale' and LEAN_GALE_BASE + (1 - LEAN_GALE_BASE) * g
            or LEAN_STRONG_MOST * (STRONG_BASE + (1 - STRONG_BASE) * g) * math.min(1, strength / 1.2)
        return amount, math.cos(angle), math.sin(angle), direction
    end
    local gusts = GUSTS[kind]
    local gust = lean_state.gust
    if not gust or t > gust.at + GUST_RISE + GUST_HOLD + GUST_FALL + 1 then
        -- the next one: a while off, the first a little sooner
        lean_state.gust = {at = t + (gust and between(gusts.every) or between(gusts.every) / 3), size = between(gusts.size)}
        gust = lean_state.gust
    end
    local into = t - gust.at
    local g
    if into < 0 then g = 0
    elseif into < GUST_RISE then g = 0.5 - 0.5 * math.cos(math.pi * into / GUST_RISE)
    elseif into < GUST_RISE + GUST_HOLD then g = 1
    elseif into < GUST_RISE + GUST_HOLD + GUST_FALL then
        g = 0.5 + 0.5 * math.cos(math.pi * (into - GUST_RISE - GUST_HOLD) / GUST_FALL)
    else g = 0 end
    g = g * gust.size
    local amount
    amount = LEAN_BREEZE_MOST * g
    local angle = math.floor(math.atan(wy, wx) / (math.pi / 4) + 0.5) * (math.pi / 4)
    return amount, math.cos(angle), math.sin(angle), math.floor(angle / (math.pi / 4) + 0.5) % 8
end

-- The lean this frame, worked out once (the gusts' clock moves each time it's asked) and shared
-- by the grass and the trees: amount, ux, uy, direction (nil in calm).
local lean_frame, frame_number = {}, 0   -- (frame_number: counted in update)
local LEAN_HISTORY_S = 5
lean_history = lean_history or {}       -- {clock, amount} each frame, the last LEAN_HISTORY_S seconds
local function lean_now()
    local frame = frame_number
    if lean_frame.at ~= frame then
        lean_frame = {at = frame, wanted_lean()}
        local clock, last = lean_state.clock, lean_history[#lean_history]
        if not last or last[1] ~= clock then
            lean_history[#lean_history + 1] = {clock, lean_frame[1] or 0}
            if lean_history[1][1] < clock - LEAN_HISTORY_S or lean_history[1][1] > clock then
                local kept = {}
                for _, h in ipairs(lean_history) do
                    if h[1] >= clock - LEAN_HISTORY_S and h[1] <= clock then kept[#kept + 1] = h end
                end
                lean_history = kept
            end
        end
    end
    return table.unpack(lean_frame)
end

-- The lean the gusts called for `ago` seconds back on their clock (the oldest kept, if longer).
local function lean_ago(ago)
    local want = lean_state.clock - ago
    for i = #lean_history, 1, -1 do
        if lean_history[i][1] <= want then return lean_history[i][2] end
    end
    return lean_history[1] and lean_history[1][2] or 0
end

-- Points the grass at frame `step` (0: the look's own copies).
local function show_lean(key, step)
    local l = state.lean
    for _, original in ipairs(l.grass) do
        local frame = step > 0 and l.frames[original] and l.frames[original][step]
        if frame then
            local texpos = frame.texpos
            pointed_from[texpos] = original
            for _, ref in ipairs(state.refs_of[original]) do ref.array[ref.index] = texpos end
        else
            point(original, key)
        end
    end
    l.shown = step
end

-- Each frame, once the look is showing and made: makes the frames for the wind's direction in the
-- background, and points the grass at the one the gust calls for.
-- A new set of leaning frames to make: for look `look` (its key), the wind towards (ux, uy).
local function new_lean(look, ux, uy, direction)
    local list = {}
    for _, original in ipairs(state.originals) do
        if state.class_of[original] == 'grass' and state.refs_of[original] then list[#list + 1] = original end
    end
    local key = look .. ':' .. direction
    -- this look and wind seen before: its set again, with the grass seen since added (build_lean
    -- passes over what already has its frames)
    local kept = state.lean_cache and state.lean_cache[key]
    if kept then
        state.lean_cache[key] = nil
        kept.grass, kept.position, kept.shown, kept.next_step = list, 1, 0, nil
        return kept
    end
    return {key = key, look = look, direction = direction, ux = ux, uy = uy, grass = list,
            frames = {}, position = 1, shown = 0, original = {}}
end

-- Makes a set's frames, a few a frame (one frame of one texture at a time: a texture's ten
-- together overran the frame's budget). True once they're all made.
local function build_lean(l, started, budget)
    local copies = state.copies[l.look] or {}
    while l.position <= #l.grass and clock_ms() - started < budget do
        local original = l.grass[l.position]
        local job = l.job
        if l.frames[original] then
            -- made when this set was last used (new_lean): passed over
            l.position = l.position + 1
        else
            if not job or job.original ~= original then
                local copy = copies[original]
                -- (15Z, THE LOOK'S PIXEL WORK HERE: with the hook DLL its frames are painted there from the copy's
                -- pixels, where clump_offset is worked out too; read here only without it)
                local px = copy and not native_colour and grass.pixels_of(copy.texpos)
                local ox, oy
                if px then ox, oy = clump_offset(px) end
                job = {original = original, copy = copy, px = px, ox = ox, oy = oy, step = 1, frames = {}}
                l.job = job
            end
            local native = native_colour and job.copy
            if (native or job.ox) and job.step <= LEAN_STEPS then
                local step = job.step
                local amount = LEAN_MOST_PX * step / LEAN_STEPS
                local frame
                if native then
                    local busy
                    frame, busy = native_pixels(2, job.copy.texpos, amount, l.ux, l.uy)
                    if busy then break end   -- (WAIT FOR ROOM: this step again next frame)
                else
                    local handle = dfhack.textures.createTile(leaning(job.px, job.ox, job.oy, amount, l.ux, l.uy), TILE, TILE)
                    if handle then frame = {handle = handle, texpos = dfhack.textures.getTexposByHandle(handle)} end
                end
                if frame then
                    job.frames[step] = frame
                    l.original[frame.texpos] = original
                end
                job.step = step + 1
            else
                if native or job.ox then l.frames[original] = job.frames end
                l.job, l.position = nil, l.position + 1
            end
        end
    end
    return l.position > #l.grass
end

-- The next set (for another wind direction, or the look about to show) is made while the one
-- showing carries on, and takes over at the same lean: the grass stood still for the seconds a
-- new set took whenever the snow went from light to heavy and the look changed (Poss).
local function take_over_lean(key, n, step)
    local l = state.lean
    step = step or (l and l.shown) or 0
    free_lean(l)
    state.lean, state.next_lean = n, nil
    show_lean(key, math.min(step, LEAN_STEPS))
    return n
end

local function update_lean(key, look_complete, started, budget)
    local amount, ux, uy, direction = lean_now()
    local l = state.lean
    -- (made whenever there's wind, not only in a breeze's gusts: they're ready for the next one)
    if not direction and not l then return end
    local want_key = direction and (key .. ':' .. direction) or (l and l.key)
    if not l or l.key ~= want_key then
        if not look_complete then return end
        local n = state.next_lean
        if not n or n.key ~= want_key then
            free_lean(n)
            n = new_lean(key, ux, uy, direction)
            state.next_lean = n
        end
        if build_lean(n, started, budget) then l = take_over_lean(key, n)
        elseif not l then return end
    end
    -- the wind turned and the new set isn't made yet: upright meanwhile, not leaning the old way
    state.lean_turning = direction ~= nil and l.direction ~= direction
    if state.lean_turning then amount = 0 end
    if l.position <= #l.grass then return end   -- all of them first, so the field leans as one
    -- (with the gust's sweep on screen, as the middle of the view: grass_wave)
    if wave_mode ~= 'off' and l.reach_s and not state.lean_turning then amount = lean_ago(l.reach_s) end
    local target, now = amount * LEAN_STEPS, clock_ms()
    if math.abs(target - l.shown) >= LEAN_HYSTERESIS and now >= (l.next_step or 0) then
        show_lean(key, l.shown + (target > l.shown and 1 or -1))
        l.next_step = now + LEAN_STEP_MS
    end
end

----------------------------------------------------------------------------------------------
-- Trees in the wind: rustling leaves
----------------------------------------------------------------------------------------------
-- The game draws a canopy tile's leaves and its wood as separate pictures (in the ground layers,
-- either of them), so the leaves can move while the wood stays put. A picture is leaves when most
-- of it is leaf-coloured (LEAF_SHARE; wood is greys and browns), and only its leaf pixels move
-- (with the dark outlines among them), not a twig's wood showing through. Each leaf picture on
-- screen (its look's copy) gets a loop of RUSTLE_PHASES frames in which
-- clumps of its leaves (a few pixels across) step a whole pixel downwind as a wave passes and back,
-- the waves running downwind through the canopy (each clump and each tile a little behind the one
-- upwind of it): the leaves ripple with the wind (Poss) and the branches hold still. (Shifting the whole tile, branches and all, half a pixel at a time
-- blurred it and shook like an earthquake: Poss.)
-- The wind's strength picks how much of each clump moves and how fast the loop plays: in a breeze
-- a third of the clumps stir in its gusts; in strong wind most of them, harder in the gusts; in a
-- gale all of them, all the time, pushed downwind most of the time and shaken across it too. The frames are made for the strength there is
-- (made again if it changes), within SWAY_MS a frame.
local RUSTLE_PHASES = 16           -- (8 looked steppy: Poss)
local LEAF_SHARE = 0.35            -- of a picture's pixels leaf-coloured, for it to be leaves
local LEAF_SATURATION = 0.4        -- a pixel more saturated than this is leaf-coloured
local OUTLINE_VALUE = 0.25         -- and one darker than this an outline, which moves with them
local CLUMP_SEEDS = 14             -- clumps in a tile's leaves
local SWAY_MS = 1.5                -- making frames: at most this long a frame
local WAVE_PHASES_PER_TILE = 4     -- the waves run downwind a tile every this many frames of the loop
-- share of the clumps that move, frames a second (at a gust's height; slower as it eases), how far
-- into a wave they're pushed (-1: all the time; 1: never), and whether they shake across the wind
local RUSTLE = {
    breeze = {moving = 0.35, fps = 10, push_from = 0.3, across = false},
    strong = {moving = 0.7, fps = 14, push_from = 0.0, across = false},
    gale = {moving = 1.0, fps = 18, push_from = -0.4, across = true},
}

-- Which clump each pixel of a tile belongs to (the nearest of CLUMP_SEEDS points, wrapping at the
-- edges), each clump's rank (it moves if rank < the share moving) and its two phases (along and
-- across the wind). The same for every tile; the tiles play the loop from different places.
local clumps
local function clump_layout()
    if clumps then return clumps end
    local rng = dfhack.random.new(4242)
    local seeds = {}
    for k = 1, CLUMP_SEEDS do
        seeds[k] = {x = rng:drandom() * TILE, y = rng:drandom() * TILE, rank = (k - 0.5) / CLUMP_SEEDS,
                    along = rng:drandom(), across = rng:drandom()}
    end
    local of = {}
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local best, nearest = math.huge, 1
            for k, sd in ipairs(seeds) do
                local dx = math.abs(x + 0.5 - sd.x) dx = math.min(dx, TILE - dx)
                local dy = math.abs(y + 0.5 - sd.y) dy = math.min(dy, TILE - dy)
                local d = dx * dx + dy * dy
                if d < best then best, nearest = d, k end
            end
            of[y * TILE + x + 1] = nearest
        end
    end
    clumps = {of = of, seeds = seeds}
    return clumps
end

local function pack(p) return (p[4] << 24) | (p[3] << 16) | (p[2] << 8) | p[1] end

-- Whether a pixel is leaf-coloured (or a dark outline), and whether most of a picture is.
local function leafy(p)
    local most = math.max(p[1], p[2], p[3])
    if most < OUTLINE_VALUE * 255 then return true end
    return (most - math.min(p[1], p[2], p[3])) / most > LEAF_SATURATION
end
local function is_leaves(px)
    local opaque, leaf = 0, 0
    for _, p in ipairs(px) do
        if p[4] > 128 then
            opaque = opaque + 1
            local most = math.max(p[1], p[2], p[3])
            if most > 0 and (most - math.min(p[1], p[2], p[3])) / most > LEAF_SATURATION then leaf = leaf + 1 end
        end
    end
    return opaque > 0 and leaf / opaque >= LEAF_SHARE
end

-- Which clumps move in frame `phase` of the loop, and which way: moves[clump] = {dx, dy} (whole
-- pixels), none for a clump that stays. (16A, THE RUSTLE PAINTED HERE: taken out of rustle_frame,
-- unchanged, so the hook DLL can be sent them and move the pixels itself: native_rustle.)
local function rustle_moves(phase, kind, sway)
    local layout = clump_layout()
    local how = RUSTLE[kind]
    local moves = {}
    for k, sd in ipairs(layout.seeds) do
        if sd.rank < how.moving then
            -- the wave reaches the clump later the further downwind it sits in the tile (the tile's
            -- own place downwind is its start in the loop: sway_texpos), give or take a little
            local downwind = ((sd.x * sway.ux + sd.y * sway.uy) / TILE) % 1
            local wave = (phase - downwind * WAVE_PHASES_PER_TILE) / RUSTLE_PHASES + 0.08 * sd.along
            local a = math.sin(2 * math.pi * wave)
            local c = math.sin(2 * math.pi * (wave * (k % 2 == 0 and 1 or 2) + sd.across))
            -- pushed downwind as the wave passes, and back; only a gale's shake them across too
            local along = a > how.push_from and 1 or 0
            local across = how.across and (c > 0.75 and 1 or c < -0.75 and -1 or 0) or 0
            local dx = math.floor(sway.ux * along - sway.uy * across + 0.5)
            local dy = math.floor(sway.uy * along + sway.ux * across + 0.5)
            if dx ~= 0 or dy ~= 0 then moves[k] = {dx, dy} end
        end
    end
    return moves
end

-- Frame `phase` of a leaf picture's rustle: each moving clump's pixels a whole pixel off (none,
-- one way or the other, by its phases), drawn over the picture as it was (so a clump that moves
-- leaves its edge behind rather than a hole).
local function rustle_frame(px, phase, kind, sway, moves_pixel)
    moves_pixel = moves_pixel or leafy
    local layout = clump_layout()
    local moves = rustle_moves(phase, kind, sway)
    local out = {}
    for i = 1, TILE * TILE do out[i] = pack(px[i]) end
    local of = layout.of
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local i = y * TILE + x + 1
            local m = moves[of[i]]
            if m and px[i][4] > 0 and moves_pixel(px[i]) then
                local tx, ty = x + m[1], y + m[2]
                if tx >= 0 and tx < TILE and ty >= 0 and ty < TILE then out[ty * TILE + tx + 1] = pack(px[i]) end
            end
        end
    end
    local handle = dfhack.textures.createTile(out, TILE, TILE)
    local texpos = handle and dfhack.textures.getTexposByHandle(handle)
    if not texpos then return false end
    return {handle = handle, texpos = texpos}
end

-- Each frame: the leaves' frames made in the background for the wind there is, and the loop's
-- place now (sway.playing: the phase, or nil while the leaves are still).
local function update_sway(key)
    local amount, ux, uy, direction = lean_now()
    local _, _, strength = wind.get()
    local kind = strength >= LEAN_GALE_FROM and 'gale' or strength >= LEAN_STRONG_FROM and 'strong'
        or strength >= LEAN_BREEZE_FROM and 'breeze' or nil
    local sway = state.sway
    if not kind then
        if sway then sway.playing = nil end
        return
    end
    if not sway or sway.direction ~= direction or sway.key ~= key or sway.kind ~= kind then
        forget_sway()
        sway = {key = key, direction = direction, kind = kind, ux = ux, uy = uy, frames = {}, clock = 0}
        state.sway = sway
    end
    local copies = state.screen_copies and state.screen_copies[key] or {}
    local started, ready = clock_ms(), true
    -- One original's frames made, if it has none yet; false once the frame's time is up.
    -- (a cell planned before its copy was made has no copy yet: its frames are made once it has)
    local function make_frames(original)
        if sway.frames[original] or not copies[original] then return true end
        -- (NATIVE COLOUR: none made while the DLL is still forgetting the last frames)
        if clock_ms() - started >= SWAY_MS * screen_allowance
                or (native_colour and native_sway_waiting()) then
            ready = false
            return false
        end
        local copy = copies[original]
        -- THE RUSTLE PAINTED HERE (grungeisdead's copy, 2026-11-20, test 16A): with the hook DLL each frame
        -- is a job it paints from the copy's pixels (native_rustle), so they're never read here, and the
        -- DLL said whether the copy is wood when it listed it (native_canopy: 'wood'). Sent all 16 at once,
        -- or none this frame. The DLL paints jobs in order, so a copy asked for this frame is painted first.
        if native_colour then
            local frames = {}
            if native_canopy[original] ~= 'wood' then
                if not native_room(RUSTLE_PHASES, 3) then
                    ready = false
                    return false
                end
                for phase = 1, RUSTLE_PHASES do
                    frames[phase] = native_rustle(copy.texpos, rustle_moves(phase - 1, kind, sway), false) or false
                    if frames[phase] then
                        state.ours[frames[phase].texpos] = true
                        state.screen_original[frames[phase].texpos] = original
                    end
                end
            else
                for phase = 1, RUSTLE_PHASES do frames[phase] = false end   -- (wood: stays put)
            end
            sway.frames[original] = frames
            native_sway_made(original, frames)   -- (told to the DLL)
            return true
        end
        -- (NATIVE COPIES: a copy asked for this frame is painted by the DLL after this runs; its
        -- pixels are the blank's until then, which would read as wood and never rustle)
        if copy and copy.native and copy.painted_frame == frame_number then
            ready = false
            return false
        end
        local px = copy and grass.pixels_of(copy.texpos)
        if px and not is_leaves(px) then px = nil end   -- wood: stays put
        local frames = {}
        for phase = 1, RUSTLE_PHASES do
            frames[phase] = px and rustle_frame(px, phase - 1, kind, sway) or false
            if frames[phase] then
                state.ours[frames[phase].texpos] = true
                state.screen_original[frames[phase].texpos] = original
            end
        end
        sway.frames[original] = frames
        if native_colour then native_sway_made(original, frames) end   -- (told to the DLL)
        return true
    end
    if native_colour then
        -- NATIVE COLOUR: the originals the DLL listed as shown on a branch or twig (there's no plan)
        for original in pairs(native_canopy) do
            if not make_frames(original) then break end
        end
    else
        for _, cell in ipairs(state.screen_plan or {}) do
            if cell[7] and not make_frames(cell[5]) then break end
        end
    end
    -- the loop plays at the gust's pace (a gale's never stops); still until every frame is made,
    -- so the canopy starts as one
    local pace = kind == 'gale' and 1 or kind == 'strong' and 0.7 or amount / LEAN_BREEZE_MOST
    local now = clock_ms()
    local dt = sway.last and math.min(100, now - sway.last) / 1000 or 0
    sway.last = now
    if not ready or pace <= 0.05 or df.global.pause_state then
        sway.playing = (ready and sway.playing) or nil
        if pace <= 0.05 then sway.playing = nil end
        return
    end
    sway.clock = sway.clock + dt * RUSTLE[kind].fps * math.min(1, pace)
    sway.playing = math.floor(sway.clock) % RUSTLE_PHASES
end

-- The frame a leaf cell at (x, y) shows now: its texpos, or nil for the look's copy.
function sway_texpos(sway, frames, x, y)
    -- tiles further downwind further behind in the loop: the waves run with the wind
    local start = math.floor((x * sway.ux + y * sway.uy) * WAVE_PHASES_PER_TILE)
    local frame = frames[(sway.playing - start) % RUSTLE_PHASES + 1]
    return frame and frame.texpos or nil
end

----------------------------------------------------------------------------------------------
-- Gusts sweeping across the grass
----------------------------------------------------------------------------------------------
-- The tables lean every tile of a grass together, so on its own the whole field bends at once. On
-- screen each grass tile (in the ground layer, at the view's level) is pointed at the lean the gust
-- had a moment earlier or later instead, by how far downwind it is, so a gust runs across the field
-- with the wind. The tables, which also draw the edges grass drops on its neighbours and the levels
-- below, keep the lean at the middle of the view: the edges are at most a frame or two from their
-- clump.
local WAVE_TILES_PER_S = 9          -- how fast a gust crosses the field
local GRASS_RUSTLE_MS = 1.5         -- making the grass's rustle frames: at most this long a frame

-- Each frame, after everything else is drawn: the grass tiles on screen at their own lean.
local function grass_wave(viewport)
    local l = state.lean
    if not l or l.position <= #l.grass or wave_mode == 'off' or state.lean_turning then return end
    local copies = state.copies[state.shown]
    if not copies then return end
    -- which frame (texpos -> original, step) every grass picture is, made once a set of frames is
    if not l.step_of then
        local step_of = {}
        for original, frames in pairs(l.frames) do
            local copy = copies[original]
            if copy then step_of[copy.texpos] = {original, 0} end
            for step, f in pairs(frames) do step_of[f.texpos] = {original, step} end
        end
        l.step_of = step_of
    end
    local step_of = l.step_of
    local port = df.global.gps.main_viewport
    local values, dim_y = port.screentexpos_background, port.dim_y
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, dim_y)
    local ux, uy = l.ux, l.uy
    -- the middle of the view is a reach behind the gust's clock; tiles upwind of it nearer the
    -- clock, downwind further behind
    local reach = (math.abs(ux) * cols + math.abs(uy) * rows) / 2
    l.reach_s = reach / WAVE_TILES_PER_S
    local cx, cy = (cols - 1) / 2, (rows - 1) / 2
    -- the rustle: clumps of blades pushed a pixel downwind as waves pass, as the leaves are, from
    -- the lean frame a tile shows (to the nearest even step, to keep the frames few), made for the
    -- grass on screen as it's needed
    local _, _, strength = wind.get()
    local kind = strength >= LEAN_GALE_FROM and 'gale' or strength >= LEAN_STRONG_FROM and 'strong'
        or strength >= LEAN_BREEZE_FROM and 'breeze' or nil
    -- (also a set that has none yet: one finished in wind too light to rustle had no tables at
    -- all, and the loop over the frames wanted, below, failed every frame from then on)
    if not l.rustle or l.rustle_kind ~= kind then
        for _, steps in pairs(l.rustle or {}) do
            for _, phases in pairs(steps) do for _, f in pairs(phases) do if f then discard(f.handle) end end end
        end
        l.rustle, l.rustle_kind, l.rustle_wanted = {}, kind, {}
    end
    local playing
    if kind and rustle_grass_mode ~= 'off' then
        local now = clock_ms()
        local dt = l.rustle_last and math.min(100, now - l.rustle_last) / 1000 or 0
        l.rustle_last = now
        local pace = kind == 'gale' and 1 or kind == 'strong' and 0.7 or lean_ago(0) / LEAN_BREEZE_MOST
        if pace > 0.05 then
            if not df.global.pause_state then l.rustle_clock = (l.rustle_clock or 0) + dt * RUSTLE[kind].fps * math.min(1, pace) end
            playing = math.floor(l.rustle_clock or 0) % RUSTLE_PHASES
        end
    end
    -- (16A, THE GRASS WAVE DRAWN HERE: with the hook DLL swapping the tiles, the DLL draws the wave from
    -- what native_wave hands it, and the work below is left to it; done here still the frame the DLL
    -- empties its tables for a new set, look or wind)
    if native_colour and native_wave(l, copies, playing, viewport, cols, rows, cx, cy, reach, kind) then return end
    local rustle, wanted = l.rustle, l.rustle_wanted
    -- the lean at each distance downwind, in whole tiles (worked out once a row of them)
    local at_distance = {}
    for sx = 0, cols - 1 do
        local column = sx * dim_y
        for sy = 0, rows - 1 do
            local i = column + sy
            local which = step_of[values[i]]
            if which then
                local d = math.floor((sx - cx) * ux + (sy - cy) * uy + reach + 0.5)
                local step = at_distance[d]
                if not step then
                    step = math.max(0, math.min(LEAN_STEPS, math.floor(lean_ago(d / WAVE_TILES_PER_S) * LEAN_STEPS + 0.5)))
                    at_distance[d] = step
                end
                local original = which[1]
                local texpos
                if playing then
                    local even = math.min(LEAN_STEPS, 2 * math.floor(step / 2 + 0.5))
                    local x, y = viewport.x1 + sx, viewport.y1 + sy
                    local phase = (playing - math.floor((x * ux + y * uy) * WAVE_PHASES_PER_TILE)) % RUSTLE_PHASES
                    local steps = rustle[original]
                    local phases = steps and steps[even]
                    local f = phases and phases[phase]
                    if f then texpos = f.texpos
                    elseif f == nil then wanted[(original * 16 + even) * 64 + phase] = true end
                end
                if not texpos and step ~= which[2] then
                    local frames = l.frames[original]
                    local f = step > 0 and frames and frames[step]
                    texpos = f and f.texpos or (step == 0 and copies[original] and copies[original].texpos)
                end
                if texpos then values[i] = texpos end
            end
        end
    end
    -- the rustle frames still wanted, a few a frame
    local started = clock_ms()
    for k in pairs(wanted) do
        if clock_ms() - started >= GRASS_RUSTLE_MS then break end
        -- (16A, THE RUSTLE PAINTED HERE: with the hook DLL painted there, every pixel moving; none
        -- this frame once its pool, ring or share of the frame is used, the rest wanted still)
        if native_colour and not native_room(1, 3) then break end
        wanted[k] = nil
        local phase, even, original = k % 64, (k // 64) % 16, k // 1024
        local base = even > 0 and l.frames[original] and l.frames[original][even]
        local source = base and base.texpos or (copies[original] and copies[original].texpos)
        local f
        if native_colour then
            f = source and native_rustle(source, rustle_moves(phase, kind, l), true) or false
        else
            local px = grass.pixels_of(source)
            f = px and rustle_frame(px, phase, kind, l, function(p) return true end) or false
        end
        rustle[original] = rustle[original] or {}
        rustle[original][even] = rustle[original][even] or {}
        rustle[original][even][phase] = f
        if f then
            step_of[f.texpos] = {original, even}
            l.original[f.texpos] = original
        end
    end
end

-- A leaning grass frame's upright copy (the texture itself if it isn't one): for paths, whose worn
-- grass is flattened and doesn't sway.
function steady_of(texpos)
    local l = state and state.lean
    local original = l and l.original[texpos]
    if not original then return texpos end
    local copy = state.copies[state.shown] and state.copies[state.shown][original]
    return copy and copy.texpos or original
end

-- Ahead of a change of look: the new look's copies of everything swapped on screen in the look
-- showing, made within the frame's budget. True once they're all made.
local function screen_ready(key, look, started, budget)
    local showing = state.screen_copies and state.screen_copies[state.shown]
    if not showing then return true end
    local set = state.screen_copies[key] or {}
    state.screen_copies[key] = set
    state.screen_original = state.screen_original or {}
    state.ours = state.ours or {}
    for t, old in pairs(showing) do
        if old and set[t] == nil then
            if clock_ms() - started >= budget then return false end
            -- (NATIVE COPIES: painted by the hook DLL when it can; with its pool or ring used up for
            -- this frame, the rest wait for the next)
            local copy, busy
            if native_colour then copy, busy = native_paint(t, look, true) end   -- (15Z: a screen copy, filed by picture)
            if busy then return false end
            copy = copy or redrawn_copy(t, look) or false
            if copy then
                copy.hash = old.hash
                state.ours[copy.texpos] = true
                state.screen_original[copy.texpos] = t
            end
            set[t] = copy
        end
    end
    return true
end

-- The look just shown: the screen's plan is pointed at its copies straight away. The other looks'
-- copies are kept, not let go: deleting them is what crashed DF (grass.lua: NO TEXTURE IS EVER
-- DELETED), and kept, a look that comes back has them already (screen_ready only makes what its
-- set lacks).
local function switch_screen(key)
    local copies = state.screen_copies and state.screen_copies[key]
    if not copies then return end
    -- (grungeisdead's copy) the repainted tree pictures given the new look's colours
    -- (grass.lua: REPAINTED PICTURES)
    for t, copy in pairs(copies) do
        if copy and diag.repaint and state.tree_pictures[t] then grass.repaint(t, copy.texpos) end
    end
    for _, cell in ipairs(state.screen_plan or {}) do
        local copy = copies[cell[5]]
        if copy then cell[6] = copy.texpos end
    end
    state.screen_scan = nil   -- a scan half done for the old look starts again
    forget_sway()
end

-- Points every entry at the look's copies (key; nil: back at the originals).
-- Goes up whenever the look's copies are let go: their texture numbers are then free for other
-- pictures, so what other modules made from them (paths' worn grass, frost's cracks) is made again.
copies_generation = copies_generation or 0

-- WATER THROUGH THE TABLES: all the water pointed at a look's copies (nil: back at the game's own),
-- together, so its ripple never shows some pictures in one look and some in another.
local function point_water(key)
    for _, t in ipairs(state.water_list or {}) do point(t, key) end
    state.water_key = key
end

-- Its copies for a look made while the frame's budget lasts: true once they all are.
local function build_water(key, set, look, started, budget)
    local list = state.water_list
    if not list then return true end
    local at = state.water_built[key] or 1
    while at <= #list and clock_ms() - started < budget do
        local t = list[at]
        -- (NATIVE COPIES, grungeisdead's copy, 2026-11-18: the water's 1700 or so copies were redrawn here
        -- at every reload and look, about 0.5 ms each; painted by the hook DLL now, waiting for room)
        if not set[t] then
            local copy, busy
            if native_colour then copy, busy = native_paint(t, look) end
            if busy then break end
            set[t] = copy or redrawn_copy(t, look)
        end
        at = at + 1
    end
    state.water_built[key] = at
    return at > #list
end

local function show(key)
    if key then forget_lean() else forget_all_lean() end
    for _, original in ipairs(state.originals) do point(original, key) end
    -- (the water too, once its copies for the look are all made; else it stays as it is until they
    -- are: update)
    if not key or (state.water_built and (state.water_built[key] or 1) > #(state.water_list or {})) then
        point_water(key)
    end
    state.shown = key
    -- SHOWN LOOK KEPT (grungeisdead's copy, 2026-11-17): the look just shown, with its key. state.look is
    -- the look wanted, which moves on to the next one as soon as it's asked for, seconds before it shows.
    state.shown_look = key and state.look or nil
    -- Every look's copies are kept (about 900 textures, 4 KB each, per look shown), so a look that
    -- comes back shows at once. They used to be let go but for the shown look and the one before,
    -- and deleting them is what crashed DF (grass.lua: NO TEXTURE IS EVER DELETED). Nothing is let
    -- go, so copies_generation no longer moves here.
end

local function celsius(units) return (units - 10000) * 5 / 9 end

-- Per tiletype: whether it's ground (a floor or ramp).
local ground_of = {}
local function is_ground(tiletype)
    local ground = ground_of[tiletype]
    if ground == nil then
        local basic = df.tiletype_shape.attrs[df.tiletype.attrs[tiletype].shape].basic_shape
        ground = basic == df.tiletype_shape_basic.Floor or basic == df.tiletype_shape_basic.Ramp
        ground_of[tiletype] = ground
    end
    return ground
end
local SURFACE_GRID = 12   -- points each way over the map

-- The look the map's surface temperature asks for, as a fractional step, or nil if no ground
-- was found (all dug out or built over).
local function wanted_step()
    local map = df.global.world.map
    local temps = {}
    for gx = 0, SURFACE_GRID - 1 do
        for gy = 0, SURFACE_GRID - 1 do
            local x = (2 * gx + 1) * map.x_count // (2 * SURFACE_GRID)
            local y = (2 * gy + 1) * map.y_count // (2 * SURFACE_GRID)
            local column = map.column_index[x // 16][y // 16]
            local z = column and column.elevation[x % 16][y % 16] - column.z_base
            local block = z and grass.block_at(x, y, z)
            if block and is_ground(block.tiletype[x % 16][y % 16]) then
                temps[#temps + 1] = celsius(block.temperature_1[x % 16][y % 16])
            end
        end
    end
    if #temps == 0 then return nil end
    table.sort(temps)
    local t = temps[(#temps + 1) // 2]
    surface_celsius = t
    if t < COOL_FROM then return -math.min(1, (COOL_FROM - t) / (COOL_FROM - COLDEST)) * COLD_STEPS end
    if t > WARM_FROM then return math.min(1, (t - WARM_FROM) / (HOTTEST - WARM_FROM)) * WARM_STEPS end
    return 0
end

-- A reading (fractional step) rounded to a step, if it's moved past MARGIN from `current`.
local function settled(reading, current, low, high)
    if not reading or (current and math.abs(reading - current) <= MARGIN) then return current end
    -- to the nearest step, halves away from mild (floor(reading - 0.5) took -0.7 to -2: every
    -- cold look showed a step colder than it should)
    local step = reading < 0 and -math.floor(-reading + 0.5) or math.floor(reading + 0.5)
    return math.max(low, math.min(high, step))
end

-- CHANGES OF LOOK TIMED (grungeisdead's copy, 2026-11-20, test 15S). A change of look is made whole
-- before it shows (everything on screen with it, then all in one frame), and it took a while in play.
-- Each change is timed from the frame the new look is wanted to the frame it shows, with the frames
-- spent on each part (the sheet's see-through textures, the textures, the water, the copies on screen,
-- the grass's lean) and how often the DLL's share of full redraws a frame (NATIVE_FULL_PER_FRAME) or
-- its pool or ring was used up meanwhile. The last few are shown by describe (`detailed_weather details`).
changes_timed = changes_timed or {}
local CHANGES_KEPT = 4
-- CRACKS AHEAD (grungeisdead's copy, 2026-11-20, test 15T): frost.lua's dry cracks for the next look are
-- made while it's made (frost.lua: THE NEXT LOOK AHEAD), and the look waits for them before it shows, so
-- they change with it; at most this long past the rest being ready.
local CRACKS_WAIT_MS = 5000
cracks_ahead_left = cracks_ahead_left or nil   -- frost.lua's, set when it loads: cells still waiting
local function change_phase(change, name) change.phase[name] = (change.phase[name] or 0) + 1 end
local function change_done(change)
    local nv = native_view
    changes_timed[#changes_timed + 1] = {ms = clock_ms() - change.ms, frames = change.frames, phase = change.phase,
        capped = (native_counts.capped or 0) - change.capped, busy = (native_counts.paint_busy or 0) - change.busy,
        overlay = change.overlay, overlay_worst = change.overlay_worst, gave_up = change.gave_up,
        dll_ms = (nv and nv.paint_us and change.dll_us) and (nv.paint_us.value + nv.col_us.value - change.dll_us) / 1000 or nil}
    while #changes_timed > CHANGES_KEPT do table.remove(changes_timed, 1) end
    state.change = nil
end

-- Each frame: works out the look now and then, builds its copies a little at a time, and swaps
-- them in when they're all made.
function update(viewport)
    frame_number = frame_number + 1
    grass.empty_trash()
    if not state then state = find_refs() end
    local now = clock_ms()
    if mode == 'off' then
        if state.shown then show(nil) forget_screen(nil) end
        return
    end
    wetness.update(state.look and math.max(0, state.look.temperature) / WARM_STEPS or 0)
    if now >= state.next_sample then
        state.next_sample = now + SAMPLE_MS
        local current = state.look or {}
        local temperature = forced_step or settled(wanted_step(), current.temperature, -COLD_STEPS, WARM_STEPS) or 0
        -- a forced wetness goes straight to its step, without the margin
        local current_wet = not wetness.forced and current.wet or nil
        local wet = settled(wetness.level() * WET_STEPS, current_wet, 0, WET_STEPS)
        if not state.look or temperature ~= state.look.temperature or wet ~= state.look.wet then
            state.look = {temperature = temperature, wet = wet}
        end
    end
    -- (THE SCREEN READ BY THE DLL, 15W: while the DLL swaps the tiles and this file answers it, the DLL asks
    -- about every texture it sees, in these layers and levels, and native_answer adds those the tables point
    -- at; the screen is read here only until the first look shows, or without the DLL)
    local dll_reads = native_colour and native_view and screen_mode ~= 'off' and state.shown
    if not dll_reads and (state.seen_pass or now >= state.next_seen) then
        if look_at_screen(viewport) then state.next_seen = now + SEEN_SCAN_MS end
    end
    local look = state.look
    local key = looks.look_key(look)
    -- (CHANGES OF LOOK TIMED: a change under way, from its first frame)
    local change = nil
    if state.shown and state.shown ~= key then
        change = state.change
        if not change or change.key ~= key then
            local nv = native_view
            change = {key = key, ms = clock_ms(), frames = 0, phase = {},
                      capped = native_counts.capped or 0, busy = native_counts.paint_busy or 0,
                      overlay = 0, overlay_worst = 0,
                      dll_us = nv and nv.paint_us and (nv.paint_us.value + nv.col_us.value) or nil}
            state.change = change
        end
        change.frames = change.frames + 1
        -- (the whole overlay's last frame, from detailed_weather.lua)
        local f = _G.detailed_weather_frame_ms or 0
        change.overlay = change.overlay + f
        if f > change.overlay_worst then change.overlay_worst = f end
    end
    -- build the look's copies, then show it
    local set = state.copies[key] or {}
    state.copies[key] = set
    -- the pre-rendered textures first, all at once: then the look can show straight away
    if state.from_sheet[key] == nil then
        local handles = state.slotted > 0 and sheet_for(look, key)
        state.from_sheet[key] = handles and true or false
        if handles then
            local remaking = {}
            for texpos, n in pairs(state.slots) do
                local made_texpos = handles[n] and dfhack.textures.getTexposByHandle(handles[n])
                if made_texpos then
                    if state.partly[texpos] then remaking[#remaking + 1] = {texpos, made_texpos}
                    else set[texpos] = {texpos = made_texpos} end
                end
            end
            state.remaking[key] = remaking
        end
    end
    local started = clock_ms()
    local budget = state.shown and BUILD_MS_PER_FRAME or FIRST_BUILD_MS
    -- the sheet's partly see-through textures, remade, before the look shows
    -- (15Z, THE LOOK'S PIXEL WORK HERE: painted by the hook DLL when it can, a job each, and the rest wait for
    -- room; here, pixel by pixel through DFHack, they took 50 frames of a change of look in play)
    local remaking = state.remaking[key]
    while remaking and #remaking > 0 and clock_ms() - started < budget do
        local item = remaking[#remaking]
        local copy, busy
        if native_colour then copy, busy = native_pixels(1, item[2]) end
        if busy then break end
        table.remove(remaking)
        set[item[1]] = copy or unpremultiplied(item[2])
    end
    if remaking and #remaking > 0 then
        if change then change_phase(change, 'sheet') end
        return
    end
    state.built = state.built or {}
    local position = state.built[key] or 1
    local originals = state.originals
    -- (grungeisdead's copy) TREE PIECES seen on screen before their turn: made first, with the busy
    -- budget, and pointed at as they're made
    if state.shown == key and #state.urgent > 0 then
        local urgent = state.urgent
        while #urgent > 0 and clock_ms() - started < BUSY_BUILD_MS do
            local t = urgent[#urgent]
            -- (NATIVE COPIES: painted by the hook DLL when it can; with its pool or ring used up, the
            -- rest wait for the next frame)
            if not set[t] then
                local copy, busy
                if native_colour then copy, busy = native_paint(t, look) end
                if busy then break end
                set[t] = copy or redrawn_copy(t, look)
            end
            table.remove(urgent)
            state.urgent_set[t] = nil
            point(t, key)
        end
        if #urgent > 0 then state.built[key] = position return end
    end
    while position <= #originals and clock_ms() - started < budget do
        local original = originals[position]
        -- (NATIVE COPIES: the tree pieces and anything else whose copy is its colour change alone,
        -- painted by the hook DLL, so the whole map's trees are done within the first frames)
        if not set[original] then
            local copy, busy
            if native_colour then copy, busy = native_paint(original, look) end
            if busy then break end
            set[original] = copy or redrawn_copy(original, look)
        end
        -- once the look is showing, things seen later are swapped in as their copies are made
        if state.shown == key then point(original, key) end
        position = position + 1
    end
    state.built[key] = position
    -- SHARED ART AHEAD (grungeisdead's copy, 2026-11-16). The shared tree art's tile-by-tile copies,
    -- made in the background for the look showing once its own textures are done, so a level seen
    -- for the first time has its leaves' copies waiting. They were made only as each was first seen,
    -- and the leaves on a new level showed the game's colours and changed a moment later (seen in
    -- play once the art was no longer pointed at copies). The look changing makes the next look's
    -- copies of everything the screen has before it switches (screen_ready), these included.
    if state.shown == key and position > #originals and state.shared_art then
        local copies = state.screen_copies and state.screen_copies[key]
        if copies then
            local list, at = state.shared_art, state.art_built[key] or 1
            while at <= #list and clock_ms() - started < budget do
                local t = list[at]
                if copies[t] == nil then
                    local _, busy = make_screen_copy(t, copies)
                    if busy then break end   -- (WAIT FOR ROOM)
                end
                at = at + 1
            end
            state.art_built[key] = at
        end
    end
    if state.shown == key then
        -- WATER THROUGH THE TABLES: the first look shows before its water is made (from its sheet):
        -- the water made once the look's own textures are, then pointed at all together
        if position > #originals and state.water_key ~= key and build_water(key, set, look, started, budget) then
            point_water(key)
        end
        if lean_mode ~= 'off' then
            update_lean(key, position > #originals, started, budget)
        elseif state.lean or state.next_lean then
            if state.lean then show_lean(key, 0) end   -- upright again before its frames go
            forget_all_lean()
        end
        return
    end
    if not state.shown then
        -- the first look: shown as soon as its sheet is in, the rest swapped in as it's made
        if position > #originals or state.from_sheet[key] then show(key) end
        return
    end
    -- a change of look: everything is made first, the trees and buildings on screen too, and then
    -- it all changes in one frame (shown as soon as the sheet was in, the walls and trees caught
    -- up a second later)
    if position <= #originals then change_phase(change, 'textures') return end
    -- (WATER THROUGH THE TABLES: the water's copies too, so it changes in the same frame)
    if not build_water(key, set, look, started, budget) then change_phase(change, 'water') return end
    if not screen_ready(key, look, started, budget) then change_phase(change, 'screen') return end
    -- and the grass's leaning frames in the new look, so it doesn't stop while they're made
    local l = state.lean
    if l and l.direction then
        local n = state.next_lean
        local want = key .. ':' .. l.direction
        if not n or n.key ~= want then
            free_lean(n)
            n = new_lean(key, l.ux, l.uy, l.direction)
            state.next_lean = n
        end
        if not build_lean(n, started, budget) then change_phase(change, 'lean') return end
    end
    -- CRACKS AHEAD: frost.lua's cracks for the look made too (at most CRACKS_WAIT_MS more)
    local left = cracks_ahead_left and cracks_ahead_left() or 0
    if left ~= 0 then
        change.crack_wait = change.crack_wait or clock_ms()
        if clock_ms() - change.crack_wait < CRACKS_WAIT_MS then change_phase(change, 'cracks') return end
        change.gave_up = left
    end
    change_phase(change, 'shown')
    change_done(change)   -- (CHANGES OF LOOK TIMED)
    local next_lean, step = state.next_lean, l and l.shown
    state.next_lean = nil
    show(key)
    switch_screen(key)
    if next_lean and next_lean.look == key then
        take_over_lean(key, next_lean, step)
    else
        free_lean(next_lean)
    end
end

-- The per-tile swaps on screen. Called last in the frame, after the snow and frost have written
-- theirs: they then always see the game's own textures, and this shifts whatever ends up showing
-- (fruit the snow lifted above it, say), leaving their own textures be.
----------------------------------------------------------------------------------------------
-- NATIVE COLOUR (grungeisdead's copy, 2026-11-18)
----------------------------------------------------------------------------------------------
-- The hook DLL (internal/detailed_weather/native.lua, detailed_weather_dll.cpp: THE COLOUR) swaps
-- the screen's tiles for their copies every frame, in native code, with the rules of plan_cell and
-- put_back_underground: no plan, no pass over a plan, no ground put back here. What only Lua can do
-- stays here: making the copies, and knowing what each texture is. The DLL keeps two tables by
-- texture number, written from here:
--   * flags (CF below): what a texture is;
--   * link: for an original with a copy in the look shown, the copy; for a copy, its original.
-- A texture the DLL has never heard of it asks about (a question: the texture and where it was
-- seen), and serve_native answers on the next frame, making the copy if one's needed (within the
-- frame's budget; else it's made by make_wanted later and told then). Each original shown through
-- its copy is listed back once a period, to check its number still holds the picture the copy was
-- made from (as plan_cell did once a plan).
native_colour = native_colour or false   -- native.lua: true while the DLL swaps the tiles
-- (frost.lua) Whether the DLL swaps ramps into the look's colours (RAMPS IN THE LOOK): while it swaps.
function native_ramps() return native_colour == true end
native_view = native_view or nil         -- native.lua: views of the DLL's tables and rings
native_published = native_published or {}   -- originals the DLL was given a copy for -> the copy
native_key = native_key or nil           -- the look those copies are of
native_counts = native_counts or {}      -- for native.lua's report
native_canopy = native_canopy or {}      -- SWAY: originals the DLL listed as shown on a branch or twig
native_sway_next = native_sway_next or 1 -- SWAY: the DLL's next free slot of frames (0: the empty one)
local SEEN_CANOPY = 1 << 30              -- (a seen original listed for its sway frames: the DLL's SEEN_CANOPY)
local SEEN_WOOD = 1 << 29                -- (16A: with it, its copy is wood and never rustles: the DLL's SEEN_WOOD)

-- NATIVE COPIES (test 7): a copy whose picture is its colour change alone (trunks, branches,
-- workshops, items: looks.lua's colour_only) is painted by the DLL into a blank texture from a pool
-- made ahead, in the frame it's asked for, instead of read and redrawn here (about 0.5 ms a copy).
-- The blanks are never shown before they're painted: the renderer reads a texture's pixels the
-- first time it draws it, and again only on a zoom (detailed_weather_dll.cpp: PAINTING).
native_pool = native_pool or {}          -- blank textures made ahead: {handle, texpos, address}
native_repaints = native_repaints or {}  -- tree pictures to repaint once their copy is painted: {t, copy}
local NATIVE_POOL = 512                  -- blanks kept ready (2 MB)
local NATIVE_POOL_MS = 1                 -- topping the pool up: at most this long a frame
local NATIVE_POOL_FIRST_MS = 50          -- and when the DLL takes over
local NATIVE_POOL_BUSY_MS = 8            -- and while it runs dry (about 160 blanks a frame)
local PAINT_JOB_BYTES = 256              -- the DLL's PaintJob
-- NATIVE REDRAW (test 9): copies with the dry or wet effects (grass, bare ground, ice) are redrawn by
-- the DLL too (detailed_weather_dll.cpp: THE FULL REDRAW), about 0.1 ms each there against about
-- 5 ms in Lua in a wet look. At most this many a frame, so the DLL's painting stays near 2 ms.
local NATIVE_FULL_PER_FRAME = 16
local blank_pixels = nil                 -- 1024 zeros, made once

-- A blank texture for the pool, or nil if one can't be made or painted (padded rows).
local function native_blank()
    if not blank_pixels then
        blank_pixels = {}
        for n = 1, TILE * TILE do blank_pixels[n] = 0 end
    end
    local handle = dfhack.textures.createTile(blank_pixels, TILE, TILE)
    local texpos = handle and dfhack.textures.getTexposByHandle(handle)
    local address = texpos and grass.original_address(texpos)
    if not address then
        if handle then discard(handle) end
        return nil
    end
    return {handle = handle, texpos = texpos, address = address}
end

-- The pool topped up, for at most `ms`.
local function native_fill_pool(ms)
    local ends = clock_ms() + ms
    while #native_pool < NATIVE_POOL and clock_ms() < ends do
        local b = native_blank()
        if not b then return end
        native_pool[#native_pool + 1] = b
    end
end

-- A copy of texture t (of `class`) for a look, painted by the DLL this frame: {handle, texpos, native =
-- true}. nil if the DLL can't paint it (redrawn in Lua then); nil, true if the pool or the ring is
-- used up for now, or this frame's share of full redraws is (NATIVE_FULL_PER_FRAME).
-- DRY CRACKS (grungeisdead's copy, 2026-11-20, test 15O): `crack` (frost.lua: crack_spec) has the DLL
-- crack the result as frost.lua's cracked() does: {kind = 1 dirt, 2 stone, 3 pebbles, amount, piece,
-- here, north (the heat patterns pieces' pixel addresses)}. With no class, t's own pixels are copied
-- unchanged first (a floor already in the look's colours). A crack counts against the frame's share
-- as a full redraw does (about 0.06 ms each in the DLL).
local NO_CHANGE = {cls = 0, m = {1, 0, 0, 0, 1, 0, 0, 0, 1}, dark = 1, lighten = 0,
                   dryness = 0, wet = 0, thaw = 0, weather = 0}
-- The numbers for redrawing `class` in `look` as the DLL paints them (looks.lua: native_numbers; no class:
-- NO_CHANGE), or nil if the DLL can't paint it (redrawn in Lua then).
local function paint_numbers(class, look)
    local p
    if class then p = looks.native_numbers and looks.native_numbers(class, look) else p = NO_CHANGE end
    if not p then return nil end
    if p.cls == 0 and p.soil then return nil end
    if p.cls ~= 0 and class == 'sand' and p.dryness > 0 and not p.grain then return nil end
    return p
end
-- A paint job's numbers (all but its pixels and cracks) written at `job`, the DLL's PaintJob: doubles
-- counted in 8 bytes from the job's start.
local function write_numbers(job, p)
    local d = df.reinterpret_cast('double', job)
    for k = 1, 9 do d[k + 1] = p.m[k] end
    local lean, soil = p.lean, p.soil
    d[11], d[12], d[13] = lean and lean[1] or 1, lean and lean[2] or 1, lean and lean[3] or 1
    d[14], d[15] = p.dark, p.lighten
    d[17], d[18], d[19] = soil and soil[1] or 1, soil and soil[2] or 1, soil and soil[3] or 1
    d[21], d[22], d[23], d[24], d[25] = p.dryness, p.wet, p.thaw, p.ice_k or 0, p.ice_dark or 1
    local u = df.reinterpret_cast('uint32_t', job)
    u[32], u[33], u[40], u[41] = lean and 1 or 0, p.cls, soil and 1 or 0, p.weather   -- (bytes 128, 132, 160, 164)
    df.reinterpret_cast('uint64_t', job + 208).value = p.grain or 0
end
-- (frost.lua, CRACKS IN PLACE: THE PAINTING HERE, 15V) The numbers of `class` redrawn for `look`, as a paint
-- job's, written at address `job` (a crack_look slot's ramp), for the DLL to paint copies from itself: its
-- pixels and cracks left empty, filled in there. False if the DLL can't paint the class in that look.
function native_template(job, class, look)
    local p = paint_numbers(class, look)
    if not p then return false end
    df.reinterpret_cast('uint64_t', job).value = 0
    df.reinterpret_cast('uint64_t', job + 8).value = 0
    write_numbers(job, p)
    local u = df.reinterpret_cast('uint32_t', job)
    u[54], u[55] = 0, 0
    df.reinterpret_cast('double', job)[28] = 0
    df.reinterpret_cast('uint64_t', job + 232).value = 0
    df.reinterpret_cast('uint64_t', job + 240).value = 0
    return true
end

local function native_job(t, class, look, crack, screen)
    local nv = native_view
    if not nv or not nv.paint_head then return nil end
    local p = paint_numbers(class, look)
    if not p then return nil end
    local full = p.cls ~= 0 or crack ~= nil
    local src = grass.original_address(t)   -- (the game's own pixels, even where it's repainted)
    if not src then return nil end
    if full then
        if native_counts.full_frame ~= frame_number then native_counts.full_frame, native_counts.full_n = frame_number, 0 end
        if native_counts.full_n >= NATIVE_FULL_PER_FRAME then
            native_counts.capped = (native_counts.capped or 0) + 1   -- (CHANGES OF LOOK TIMED)
            return nil, true
        end
    end
    local head = nv.paint_head.value
    if ((head - nv.paint_tail.value) & 0xffffffff) >= nv.paint_ring or #native_pool == 0 then
        native_counts.paint_busy = (native_counts.paint_busy or 0) + 1
        return nil, true
    end
    local blank = table.remove(native_pool)
    -- the job (the DLL's PaintJob): doubles counted in 8 bytes from the job's start
    local job = nv.paint_base + (head % nv.paint_ring) * PAINT_JOB_BYTES
    df.reinterpret_cast('uint64_t', job).value = src
    df.reinterpret_cast('uint64_t', job + 8).value = blank.address
    write_numbers(job, p)
    local d = df.reinterpret_cast('double', job)
    local u = df.reinterpret_cast('uint32_t', job)
    -- (DRY CRACKS: always written, so a ring slot reused never keeps an earlier job's cracks)
    u[54], u[55] = crack and crack.kind or 0, crack and crack.piece or 0   -- (bytes 216, 220)
    d[28] = crack and crack.amount or 0                                   -- (byte 224)
    df.reinterpret_cast('uint64_t', job + 232).value = crack and crack.here or 0
    df.reinterpret_cast('uint64_t', job + 240).value = crack and crack.north or 0
    -- (15Z) the job's kind, the look's redraw (0); and for a screen copy its blank's number, which the DLL
    -- files by its original's picture (BY PICTURE: a new number showing the same picture gets it at once)
    u[62], u[63] = 0, screen and blank.texpos or 0   -- (bytes 248, 252)
    nv.paint_head.value = (head + 1) & 0xffffffff
    native_counts.painted = (native_counts.painted or 0) + 1
    if full then
        native_counts.full_n = native_counts.full_n + 1
        native_counts.full = (native_counts.full or 0) + 1
    end
    return {handle = blank.handle, texpos = blank.texpos, native = true, painted_frame = frame_number}
end

-- A copy of t for a look, by its class here (colour's own copies); `screen`: one of the screen copies (15Z).
function native_paint(t, look, screen)
    if not state then return nil end
    return native_job(t, state.class_of[t], look, nil, screen)
end

-- (frost.lua) A texture redrawn for a look as looks.redraw does with its effects, painted by the DLL
-- this frame: {handle, texpos, native}; nil if it can't be (nil, true: not this frame). `crack`, if
-- given, cracks it after (DRY CRACKS: a dirt or stone ramp in a dry look).
function native_redraw(texpos, class, look, crack)
    if not native_colour then return nil end
    return native_job(texpos, class, look, crack)
end

-- (frost.lua, DRY CRACKS) A texture already in the look's colours (a floor's ground as drawn), copied
-- with its cracks by the DLL this frame: as native_redraw.
function native_crack(texpos, crack)
    if not native_colour then return nil end
    return native_job(texpos, nil, nil, crack)
end

-- THE LOOK'S PIXEL WORK HERE (15Z): a job of another kind in the DLL's ring, painted by it this frame
-- (detailed_weather_dll.cpp: paint_unpremultiplied, paint_lean). Kind 1: texture t with its alpha divided
-- back out (unpremultiplied). Kind 2: a lean frame of grass texture t, `amount` px at the tips towards
-- (ux, uy) (leaning, with clump_offset worked out there). {handle, texpos, native}; nil if t's pixels
-- can't be read in one run; nil, true: no room this frame, or this frame's share sent (the caller tries
-- again next frame).
local NATIVE_LEANS_PER_FRAME = 24            -- lean frames sent a frame (about 53 us each in the DLL)
local NATIVE_UNPREMULTIPLIED_PER_FRAME = 128 -- textures with their alpha divided out, sent a frame (about 4 us each there)
local NATIVE_RUSTLES_PER_FRAME = 128         -- (16A) rustle frames sent a frame (a few us each there): 8 trees' pictures
local NATIVE_SHARES = {NATIVE_UNPREMULTIPLIED_PER_FRAME, NATIVE_LEANS_PER_FRAME, NATIVE_RUSTLES_PER_FRAME}
-- (the DLL's painting kept short each frame: this frame's jobs of each kind, counted)
local function native_share(kind)
    if native_counts.pixel_frame ~= frame_number then native_counts.pixel_frame, native_counts.pixel_n = frame_number, {0, 0, 0} end
    return NATIVE_SHARES[kind] - native_counts.pixel_n[kind]
end
-- (16A) Whether n more jobs of `kind` fit this frame: the ring, the pool and the kind's share.
function native_room(n, kind)
    local nv = native_view
    if not nv or not nv.paint_head then return false end
    if ((nv.paint_head.value - nv.paint_tail.value) & 0xffffffff) + n > nv.paint_ring or #native_pool < n then return false end
    return native_share(kind) >= n
end
function native_pixels(kind, t, amount, ux, uy)
    local nv = native_view
    if not nv or not nv.paint_head then return nil end
    if native_share(kind) <= 0 then return nil, true end
    local src = grass.original_address(t)
    if not src then return nil end
    local head = nv.paint_head.value
    if ((head - nv.paint_tail.value) & 0xffffffff) >= nv.paint_ring or #native_pool == 0 then
        native_counts.paint_busy = (native_counts.paint_busy or 0) + 1
        return nil, true
    end
    local blank = table.remove(native_pool)
    local job = nv.paint_base + (head % nv.paint_ring) * PAINT_JOB_BYTES
    df.reinterpret_cast('uint64_t', job).value = src
    df.reinterpret_cast('uint64_t', job + 8).value = blank.address
    local d = df.reinterpret_cast('double', job)
    d[2], d[3], d[4] = amount or 0, ux or 0, uy or 0     -- (m[0], m[1], m[2]: bytes 16 to 39)
    local u = df.reinterpret_cast('uint32_t', job)
    u[62], u[63] = kind, 0                               -- (kind, dst_tex: bytes 248, 252)
    nv.paint_head.value = (head + 1) & 0xffffffff        -- (last: the DLL takes it once filled)
    native_counts.pixel_jobs = (native_counts.pixel_jobs or 0) + 1
    native_counts.pixel_n[kind] = native_counts.pixel_n[kind] + 1
    return {handle = blank.handle, texpos = blank.texpos, native = true, painted_frame = frame_number}
end

-- THE RUSTLE PAINTED HERE (grungeisdead's copy, 2026-11-20, test 16A): the clump layout handed to the DLL,
-- once a start (each pixel's clump, 0 to 13: detailed_weather_dll.cpp, rustle_of).
native_rustle_given = native_rustle_given or nil   -- the view it was handed to
local function native_rustle_layout(nv)
    if native_rustle_given == nv and nv.rustle_of_ready.value == 1 then return end
    local of = clump_layout().of
    for i = 1, TILE * TILE do nv.rustle_of[i - 1] = of[i] - 1 end
    nv.rustle_of_ready.value = 1   -- (last: the DLL paints rustle frames once it's set)
    native_rustle_given = nv
end
-- A rustle frame of texture t painted by the DLL (detailed_weather_dll.cpp: paint_rustle): `moves` as
-- rustle_moves gives them; `all`: every pixel moves (the grass), else only the leafy ones (a tree's).
-- {handle, texpos, native}; nil if t's pixels can't be read in one run; nil, true: no room this frame.
function native_rustle(t, moves, all)
    local nv = native_view
    if not nv or not nv.paint_head or not nv.rustle_of then return nil end
    if native_share(3) <= 0 then return nil, true end
    local src = grass.original_address(t)
    if not src then return nil end
    local head = nv.paint_head.value
    if ((head - nv.paint_tail.value) & 0xffffffff) >= nv.paint_ring or #native_pool == 0 then
        native_counts.paint_busy = (native_counts.paint_busy or 0) + 1
        return nil, true
    end
    native_rustle_layout(nv)
    local blank = table.remove(native_pool)
    local job = nv.paint_base + (head % nv.paint_ring) * PAINT_JOB_BYTES
    df.reinterpret_cast('uint64_t', job).value = src
    df.reinterpret_cast('uint64_t', job + 8).value = blank.address
    -- each clump's move, a byte (bit 4: it moves; bits 0-1: dx + 1; bits 2-3: dy + 1), four to a word
    local u = df.reinterpret_cast('uint32_t', job)
    local b = {}
    for k = 1, 16 do
        local m = moves[k]
        b[k] = m and (16 | (m[1] + 1) | ((m[2] + 1) << 2)) or 0
    end
    for w = 0, 3 do u[4 + w] = b[w * 4 + 1] | (b[w * 4 + 2] << 8) | (b[w * 4 + 3] << 16) | (b[w * 4 + 4] << 24) end
    u[8] = all and 1 or 0                                -- (byte 32)
    u[62], u[63] = 3, 0                                  -- (kind PJ_RUSTLE, dst_tex: bytes 248, 252)
    nv.paint_head.value = (head + 1) & 0xffffffff        -- (last: the DLL takes it once filled)
    native_counts.pixel_jobs = (native_counts.pixel_jobs or 0) + 1
    native_counts.pixel_n[3] = native_counts.pixel_n[3] + 1
    return {handle = blank.handle, texpos = blank.texpos, native = true, painted_frame = frame_number}
end
local CF = {ASKED = 1, ASKED_ELSE = 2, COPY_FOR = 4, SCREEN = 8, TABLE = 16, OTHER = 32, LEAVE = 64, NO_COPY = 128}
local CF_ANSWERED = CF.COPY_FOR | CF.SCREEN | CF.TABLE | CF.LEAVE | CF.NO_COPY
local CW = {UNDER = 1, PLAIN = 2, TREE = 4, WET = 8,   -- where a question's texture was seen
            RAMP = 32, RGRASS = 64, RSOIL = 128}         -- (RAMPS IN THE LOOK: a ramp; grass, else dirt, else stone)
-- RAMPS IN THE LOOK (grungeisdead's copy, 2026-11-19, test 15A). A ramp is a picture the game puts
-- together itself, which the tables never reach: frost.lua redrew each for the look, tile by tile, in
-- Lua every frame. With the DLL swapping, it asks about a ramp with its class (the tiletype's
-- material: grass, dirt or stone, frost.lua's class_of_tiletype), and the ramp is copied as any other
-- texture on screen: kept by picture, made ahead for the next look (screen_ready), painted by the DLL.
-- The class is kept by number here; a number found holding another picture (native_check) is asked
-- about again, as it may be another ramp, or no ramp.
ramp_class_of = ramp_class_of or {}
local NATIVE_PERIOD_MS = SCREEN_PLAN_MS   -- how often the copies in view are checked

-- A texture's flags: bits added, bits cleared.
local function native_flags(t, add, clear)
    local nv = native_view
    if t <= 0 or t >= nv.tex_map then return end
    nv.flags[t] = (nv.flags[t] & ~(clear or 0)) | (add or 0)
end

-- An original's copy in the look shown, told to the DLL both ways (and whether it's swapped in the
-- ground layer anywhere: in the tables but not ground, plan_cell's 'other').
local function native_publish(t, copy)
    local nv = native_view
    local c = copy.texpos
    if t <= 0 or t >= nv.tex_map or c <= 0 or c >= nv.tex_map then return end
    nv.link[c] = t   -- (the link first: the DLL reads the flags, then the link)
    native_flags(c, CF.SCREEN)
    nv.link[t] = c
    local other = state.refs_of[t] and state.class_of[t] == 'other'
    native_flags(t, CF.COPY_FOR | (other and CF.OTHER or 0), CF.NO_COPY)
    native_published[t] = c
end

-- (make_screen_copy) a copy just made for the look showing, or false: none can be made.
function native_copy_made(t, copy)
    if not native_view then return end
    if copy then native_publish(t, copy) else native_flags(t, CF.NO_COPY, CF.COPY_FOR) end
end

-- SWAY: whether the DLL is still forgetting the last frames (asked for by native_sway_forgotten).
function native_sway_waiting()
    local nv = native_view
    return nv and nv.sway_reset.value ~= nv.sway_reset_done.value
end

-- SWAY: (forget_sway) the frames let go: the DLL asked to forget its own, and to list the canopy's
-- originals again as they show.
function native_sway_forgotten()
    local nv = native_view
    if not nv then return end
    nv.sway_reset.value = (nv.sway_reset.value + 1) & 0xffffffff
    nv.sway_playing.value = -1
    native_canopy, native_sway_next = {}, 1
end

-- SWAY: (update_sway) an original's frames, in loop order, given to the DLL in its next slot. Wood's
-- frames are all false (it stays put): it gets slot 0, which has none, so it isn't listed again.
function native_sway_made(original, frames)
    local nv = native_view
    if not nv or nv.sway_phases ~= RUSTLE_PHASES then return end
    if original <= 0 or original >= nv.tex_map then return end
    local any = false
    for phase = 1, RUSTLE_PHASES do if frames[phase] then any = true break end end
    local slot = 0
    if any then
        if native_sway_next >= nv.sway_max then return end   -- (full: that original stays still)
        slot, native_sway_next = native_sway_next, native_sway_next + 1
        for phase = 1, RUSTLE_PHASES do
            local f = frames[phase]
            local tp = f and f.texpos or 0
            if tp > 0 and tp < nv.tex_map then
                nv.link[tp] = original   -- (each frame counts as its original, as a copy does)
                native_flags(tp, CF.SCREEN)
            else
                tp = 0
            end
            nv.sway_tex[slot * RUSTLE_PHASES + phase - 1] = tp
        end
    end
    nv.sway_of[original] = slot + 1
end

-- THE GRASS WAVE DRAWN HERE (grungeisdead's copy, 2026-11-20, test 16A). grass_wave's work on screen,
-- every grass tile in the main view's ground layer at its own lean and rustle frame, done by the DLL
-- (detailed_weather_dll.cpp: draw_grass_wave) from what's handed over here:
--   * slots, one a grass picture: its look copy and lean frames (step 0 to 10, as the set's step_of
--     looks them up), and its rustle frames as they're made. Written again whenever the set, its
--     step_of, its rustle (another kind of wind) or the look's copies change: the DLL empties its tables
--     first (wave_gen, answered in wave_gen_done), and grass_wave draws that frame itself;
--   * the gusts' lean, entry by entry as lean_history keeps it;
--   * each frame's numbers: the view's corner, size and middle, the reach, the wind's way, the gusts'
--     clock and the rustle's place in its loop.
-- Rustle frames the DLL finds not made are asked of this file (wave_want) and made here as grass_wave
-- made them, a few a frame. Each frame handed over counts as its original (a copy DF draws through the
-- tables, as the answer to a question about it says), which the DLL's spatter and cracks read: the DLL
-- draws the frames after the colour's swaps, where the frames were asked about before.
local WAVE_SLOT_INTS = 11 + 6 * 16   -- the DLL's WaveSlot: lean frames by step 0 to 10, rustle frames by even step and phase
local WAVE_HIST = 2048               -- the DLL's history ring (WAVE_HIST)
local WAVE_WANT_RING = 256           -- the DLL's ring of rustle frames wanted (WAVE_WANT_RING)
native_wave_for = native_wave_for or nil     -- what the DLL's slots are written from
native_wave_sent = native_wave_sent or nil   -- {view, the last lean_history entry sent}

-- A frame handed to the DLL: it counts as its original.
local function native_wave_frame(tp, original)
    local nv = native_view
    if tp <= 0 or tp >= nv.tex_map then return end
    nv.link[tp] = original   -- (the link first: the DLL reads the flags, then the link)
    native_flags(tp, CF.TABLE)
end

-- The slots written, once the DLL has emptied its tables: each picture's copy and lean frames as the set's
-- step_of looks them up (its rustle frames, already made there, left out), then the rustle frames made.
local function native_wave_write(w, l, copies)
    local nv = native_view
    local slots, most = nv.wave_slots, nv.wave_slots_most
    local slot_of, originals, left_out = {}, {}, 0
    for tp, which in pairs(l.step_of) do
        local original, step = which[1], which[2]
        local copy, frames = copies[original], l.frames[original]
        local lean = (step == 0 and copy and copy.texpos == tp)
            or (step > 0 and frames and frames[step] and frames[step].texpos == tp)
        if lean then
            local s = slot_of[original]
            if not s and #originals < most then
                s = #originals
                originals[s + 1], slot_of[original] = original, s
            end
            if s then
                slots[s * WAVE_SLOT_INTS + step] = tp
                native_wave_frame(tp, original)
            else
                left_out = left_out + 1
            end
        end
    end
    for original, steps in pairs(l.rustle) do
        local s = slot_of[original]
        if s then
            for even, phases in pairs(steps) do
                for phase, f in pairs(phases) do
                    slots[s * WAVE_SLOT_INTS + 11 + (even // 2) * 16 + phase] = f and f.texpos or -1
                    if f then native_wave_frame(f.texpos, original) end
                end
            end
        end
    end
    nv.wave_slot_n.value = #originals
    nv.wave_built.value = (nv.wave_built.value + 1) & 0xffffffff   -- (last: the DLL makes its map again once raised)
    w.originals, w.written, w.left_out = originals, true, left_out
    l.rustle_wanted = {}   -- (the DLL asks for the rustle frames it needs)
end

-- (grass_wave) This frame's wave handed to the DLL. True if the DLL draws it; false: grass_wave draws it.
function native_wave(l, copies, playing, viewport, cols, rows, cx, cy, reach, kind)
    local nv = native_view
    if not nv or not nv.wave_on then return false end
    local w = native_wave_for
    if not w or w.nv ~= nv or w.l ~= l or w.step_of ~= l.step_of or w.rustle ~= l.rustle or w.copies ~= copies then
        -- the DLL asked to empty its tables (it does so the next time it's asked to draw)
        local gen = (nv.wave_gen.value + 1) & 0xffffffff
        nv.wave_gen.value = gen
        native_wave_for = {nv = nv, l = l, step_of = l.step_of, rustle = l.rustle, copies = copies, gen = gen}
        nv.wave_on.value = 1
        return false
    end
    if not w.written then
        nv.wave_on.value = 1
        if nv.wave_gen_done.value ~= w.gen then return false end   -- (not emptied yet)
        native_wave_write(w, l, copies)
    end
    -- the gusts' lean as lean_history keeps it: the entries not sent yet (all of them, the last one sent
    -- no longer kept there)
    local sent = native_wave_sent
    if not sent or sent.nv ~= nv then
        sent = {nv = nv}
        native_wave_sent = sent
    end
    local hist = lean_history
    local n, from = #hist, 1
    if sent.last then
        for i = n, 1, -1 do
            if hist[i] == sent.last then from = i + 1 break end
        end
    end
    if from <= n then
        local head, out = nv.wave_hist_head.value, nv.wave_hist
        for i = from, n do
            local k = (head % WAVE_HIST) * 2
            out[k], out[k + 1] = hist[i][1], hist[i][2]
            head = (head + 1) & 0xffffffff
        end
        nv.wave_hist_head.value = head   -- (last: the DLL reads up to it)
        sent.last = hist[n]
    end
    -- the rustle frames the DLL asked for, made a few a frame, as grass_wave made them
    local rustle, step_of = l.rustle, l.step_of
    local started = clock_ms()
    local tail, head = nv.wave_want_tail.value, nv.wave_want_head.value
    while tail ~= head do
        if clock_ms() - started >= GRASS_RUSTLE_MS or not native_room(1, 3) then break end
        local e = nv.wave_want[tail % WAVE_WANT_RING]
        local slot, half, phase = e >> 8, (e >> 4) & 15, e & 15
        local original, even = w.originals[slot + 1], half * 2
        tail = (tail + 1) & 0xffffffff
        if original and kind then
            local base = even > 0 and l.frames[original] and l.frames[original][even]
            local source = base and base.texpos or (copies[original] and copies[original].texpos)
            local f = source and native_rustle(source, rustle_moves(phase, kind, l), true) or false
            rustle[original] = rustle[original] or {}
            rustle[original][even] = rustle[original][even] or {}
            rustle[original][even][phase] = f
            if f then
                step_of[f.texpos] = {original, even}
                l.original[f.texpos] = original
                native_wave_frame(f.texpos, original)
            end
            nv.wave_slots[slot * WAVE_SLOT_INTS + 11 + half * 16 + phase] = f and f.texpos or -1
        end
    end
    nv.wave_want_tail.value = tail
    -- this frame's numbers
    nv.wave_x1.value, nv.wave_y1.value = viewport.x1, viewport.y1
    nv.wave_cols.value, nv.wave_rows.value = cols, rows
    nv.wave_cx.value, nv.wave_cy.value, nv.wave_reach.value = cx, cy, reach
    nv.wave_ux.value, nv.wave_uy.value = l.ux, l.uy
    nv.wave_clock.value = lean_state.clock
    nv.wave_playing.value = playing or -1
    nv.wave_on.value = 1
    return true
end

-- A new look shown: every original the DLL has a copy for pointed at this look's (screen_ready made
-- them before the switch), or asked about again where it shows; and the look's copies DF draws
-- through the tables told, for the ground put back underground.
local function native_show(key)
    local nv = native_view
    local copies = state.screen_copies[key] or {}
    for t in pairs(native_published) do
        local c = copies[t]
        if c then native_publish(t, c)
        else
            native_published[t] = nil
            native_flags(t, c == false and CF.NO_COPY or 0, CF.COPY_FOR | CF.ASKED)
        end
    end
    for original, c in pairs(state.copies[key] or {}) do
        local tp = c.texpos
        if tp and tp > 0 and tp < nv.tex_map then
            nv.link[tp] = original
            native_flags(tp, CF.TABLE)
        end
    end
    native_key = key
end

-- One question: texture t, seen where (CW bits). The order is plan_cell's.
local function native_answer(t, where, copies, budget_ends)
    local nv = native_view
    if t <= 0 or t >= nv.tex_map or nv.flags[t] & CF_ANSWERED ~= 0 then return end
    -- THE SCREEN READ BY THE DLL (15W): a texture the tables point at, seen for the first time, joins the
    -- look's list as look_at_screen adds it (which costs 1 to 3 ms a frame for 21 frames of every pass, and
    -- no longer runs once the DLL answers here): copied in the background, then pointed at
    if not state.included[t] and state.refs_of[t] and (state.class_of[t] ~= 'other' or state.tree_piece[t]) then
        state.included[t] = true
        state.originals[#state.originals + 1] = t
    end
    -- one of this file's screen copies, of any look: its original
    local was = state.screen_original[t]
    if was then
        nv.link[t] = was
        native_flags(t, CF.SCREEN)
        return
    end
    -- a copy DF draws through the tables (the look shown's, or a grass lean frame): its original
    local original = original_of(t)
    if original ~= t then
        nv.link[t] = original
        native_flags(t, CF.TABLE)
        return
    end
    -- the game's black, Detailed Weather's own textures, the tables' originals, the water
    if t == state.black or pointed_from[t] or made[t] or state.ours[t] or (state.water and state.water[t]) then
        native_flags(t, CF.LEAVE)
        return
    end
    -- TREE PIECES: joins the look's list at once, copied first (update), and pointed at like the
    -- ground; never swapped here
    if state.tree_piece[t] then
        if not state.included[t] then
            state.included[t] = true
            state.originals[#state.originals + 1] = t
        end
        local shown = state.copies[state.shown]
        if not (shown and shown[t]) and not state.urgent_set[t] then
            state.urgent_set[t] = true
            state.urgent[#state.urgent + 1] = t
        end
        native_flags(t, CF.LEAVE)
        return
    end
    -- (RAMPS IN THE LOOK: a ramp's class, for its copy)
    if where & CW.RAMP ~= 0 then
        local class = where & CW.RGRASS ~= 0 and 'grass' or where & CW.RSOIL ~= 0 and 'dirt' or 'stone'
        if ramp_class_of[t] ~= class then
            ramp_class_of[t] = class
            rawset(state.class_of, t, class)
        end
    end
    -- seen only where it isn't swapped (underground, or the plain ground layer): nothing more to
    -- say; the DLL asks again if it shows where it could be
    if where & CW.UNDER ~= 0 then return end
    local other = state.refs_of[t] and state.class_of[t] == 'other'
    if where & CW.PLAIN ~= 0 and not other then return end
    -- (a picture seen in a tree above ground: one to repaint, make_screen_copy)
    if where & CW.TREE ~= 0 and not state.tree_pictures[t] and state.on_page and not state.on_page[t] then
        state.tree_pictures[t] = true
    end
    local copy = copies[t]
    if copy == nil then
        local busy
        if clock_ms() < budget_ends then
            busy = select(2, make_screen_copy(t, copies))   -- (told to the DLL there: native_copy_made)
        end
        if busy or clock_ms() >= budget_ends and copies[t] == nil then
            state.wanted[t] = true        -- made in a later frame (make_wanted), told then
            native_counts.put_off = (native_counts.put_off or 0) + 1
        end
        return
    end
    native_copy_made(t, copy)
end

-- A copy's original checked: if its number now holds another picture, the copy is made again (the
-- old one stays showing until then, as in plan_cell).
local function native_check(t, copies)
    local copy = copies[t]
    if not copy or sample_hash(t) == copy.hash then return end
    counted('numbers found holding another picture than their copy')
    local stale = state.stale[t]
    if stale then discard(stale.handle) state.screen_original[stale.texpos] = nil end
    state.stale[t] = copy
    rawset(state.class_of, t, nil)
    copies[t] = nil
    -- (RAMPS IN THE LOOK: a ramp's number holding another picture may be another ramp, or none: asked
    -- about again by the DLL, which holds the old copy for a few frames meanwhile)
    if ramp_class_of[t] then
        ramp_class_of[t] = nil
        native_flags(t, 0, CF_ANSWERED | CF.ASKED | CF.ASKED_ELSE)
        return
    end
    state.wanted[t] = true
end

-- Every frame while the DLL swaps the tiles (update_screen): the look shown told, the questions
-- answered, waiting copies made, the copies in view checked, and the grass's gusts (16A: handed to the
-- DLL, which draws them: native_wave).
local function serve_native(viewport, key)
    local nv = native_view
    local copies = state.screen_copies[key]
    local step_started = clock_ms()
    -- NATIVE COPIES: tree pictures repainted now their copies, asked for last frame, are painted
    if #native_repaints > 0 then
        if diag.repaint then
            for _, r in ipairs(native_repaints) do grass.repaint(r[1], r[2]) end
        end
        native_repaints = {}
    end
    if native_key ~= key then native_show(key) end
    -- FIRST SIGHT (test 5C): a texture is only asked about once, so copies are made for questions
    -- only when pictures are seen for the first time (a new level, the first view after loading).
    -- They get the budget plan_screen gave a new level (NEW_LEVEL_PLAN_MS): at BUILD_MS_PER_FRAME,
    -- about 6 copies a frame, the trees of a level seen for the first time filled in over several
    -- frames in the game's colours (seen in play, test 5B).
    local budget_ends = clock_ms() + NEW_LEVEL_PLAN_MS * screen_allowance
    -- ---- THE QUESTIONS ----
    local head, tail = nv.req_head.value, nv.req_tail.value
    local answered = 0
    while tail ~= head do
        local slot = tail % nv.ring
        native_answer(nv.q32[slot * 2], nv.q8[slot * 8 + 4], copies, budget_ends)
        tail = (tail + 1) & 0xffffffff
        answered = answered + 1
    end
    nv.req_tail.value = tail
    native_counts.answered = (native_counts.answered or 0) + answered
    clocked('native: answering the DLL', step_started)
    -- NATIVE COPIES: blanks made ahead for the next frames
    step_started = clock_ms()
    -- (faster while the pool ran dry since last frame: a change of look copies everything copied so far)
    local busy = native_counts.paint_busy or 0
    native_fill_pool((busy ~= (native_counts.busy_seen or 0) and NATIVE_POOL_BUSY_MS or NATIVE_POOL_MS) * screen_allowance)
    native_counts.busy_seen = busy
    clocked('native: blank textures made ahead', step_started)
    -- ---- COPIES WAITING ----
    -- (many at once, the trees all changing as their leaves fall: faster, as update_screen did)
    local count = 0
    for _ in pairs(state.wanted) do
        count = count + 1
        if count > BUSY_FROM then break end
    end
    if count > 0 then
        step_started = clock_ms()
        make_wanted(copies, clock_ms() + (count > BUSY_FROM and BUSY_BUILD_MS or BUILD_MS_PER_FRAME) * screen_allowance)
        clocked('making copies that were waiting', step_started)
    end
    -- ---- THE COPIES IN VIEW, CHECKED ----
    step_started = clock_ms()
    local check_ends = step_started + BUILD_MS_PER_FRAME * screen_allowance
    head, tail = nv.seen_head.value, nv.seen_tail.value
    while tail ~= head and clock_ms() < check_ends do
        local v = nv.seen[tail % nv.ring]
        if v >= SEEN_CANOPY then
            -- (SWAY: shown on a branch or twig, frames wanted; 16A: SEEN_WOOD, the DLL found its copy wood)
            local wood = v & SEEN_WOOD ~= 0
            native_canopy[v - SEEN_CANOPY - (wood and SEEN_WOOD or 0)] = wood and 'wood' or true
        else
            local had = copies[v]
            native_check(v, copies)
            native_counts.checked = (native_counts.checked or 0) + 1
            -- (PICTURES CHECKED HERE, native.lua and the DLL: still its copy's picture, so the DLL
            -- fingerprints it and checks it itself from now on, sending it back only once changed)
            if had and copies[v] == had and nv.verified then
                local vh = nv.verified_head.value
                if ((vh - nv.verified_tail.value) & 0xffffffff) < nv.ring then
                    nv.verified[vh % nv.ring] = v
                    nv.verified_head.value = (vh + 1) & 0xffffffff
                end
            end
        end
        tail = (tail + 1) & 0xffffffff
    end
    nv.seen_tail.value = tail
    local now = clock_ms()
    if now >= (native_counts.next_period or 0) then
        nv.period.value = (nv.period.value + 1) & 0xffffffff
        native_counts.next_period = now + NATIVE_PERIOD_MS
    end
    clocked('native: checking the copies in view', step_started)
    -- ---- SWAY: the frames made (update_sway), and where the loop is now told to the DLL ----
    step_started = clock_ms()
    if sway_mode == 'on' and nv.sway_phases == RUSTLE_PHASES then update_sway(key) elseif state.sway then forget_sway() end
    local sway = state.sway
    if sway and sway.playing and not native_sway_waiting() then
        nv.sway_ux.value, nv.sway_uy.value = sway.ux, sway.uy
        nv.sway_waves.value = WAVE_PHASES_PER_TILE
        nv.sway_playing.value = sway.playing
    else
        nv.sway_playing.value = -1
    end
    clocked('tree sway frames', step_started)
    step_started = clock_ms()
    grass_wave(viewport)
    clocked('grass wave and rustle', step_started)
end

-- (native.lua) The DLL takes over: its tables are empty, so what's known now is told at once (the
-- look shown's copies; the rest is asked about as it shows). The plan is let go.
function native_begin(view)
    native_view, native_published, native_key, native_counts = view, {}, nil, {}
    ramp_class_of = {}   -- (RAMPS IN THE LOOK: numbers can be other pictures since the last start)
    native_canopy, native_sway_next = {}, 1
    native_repaints = {}
    native_fill_pool(NATIVE_POOL_FIRST_MS)   -- (NATIVE COPIES: blanks ready for the first view)
    native_colour = true
    if state then
        forget_sway()   -- (SWAY: made again for the DLL, from the canopy's originals as it lists them)
        state.screen_plan, state.screen_scan, state.screen_also = nil, nil, nil
        state.level_plans, state.level_views = nil, nil
        local key = state.shown
        if key and state.screen_copies and state.screen_copies[key] then native_show(key) end
        if key then
            for t, c in pairs(state.screen_copies and state.screen_copies[key] or {}) do
                if c then native_publish(t, c) end
            end
        end
    end
end

-- (native.lua) Handed back: the plan starts again from nothing.
function native_end()
    native_colour, native_view = false, nil
    -- (NATIVE COPIES: the blanks dropped, not let go: at a world's unload the game has freed them)
    native_pool, native_repaints = {}, {}
    if state then
        state.screen_plan, state.screen_scan, state.screen_also = nil, nil, nil
        state.level_plans, state.level_views, state.screen_view, state.screen_z = nil, nil, nil, nil
    end
end

-- (native.lua) The levels the DLL looks at: this one and those below that plan_screen looks at.
function native_depths() return math.min(SCREEN_DEPTHS, diag.depths) end

function update_screen(viewport)
    if not state or mode == 'off' or not state.look then return end
    -- (NATIVE COLOUR: the hook DLL puts the ground back)
    if state.shown and not native_colour then put_back_underground(viewport) end
    -- the look showing, not the one wanted: while the next one's made (a few seconds) the trees and
    -- buildings keep this one's copies (they went back to the game's colours meanwhile: Poss)
    local key = state.shown
    if not key then return end
    if screen_mode == 'off' then
        if state.screen_plan then forget_screen(nil) end
        return
    end
    local now = clock_ms()
    screen_frame = screen_frame + 1   -- (KEPT THROUGH A BLANK)
    state.screen_copies = state.screen_copies or {}
    if not state.screen_copies[key] then forget_screen(nil) state.screen_copies[key] = {} end
    state.screen_original = state.screen_original or {}
    state.wanted, state.stale = state.wanted or {}, state.stale or {}
    state.tree_pictures = state.tree_pictures or {}
    if not state.ours or (not state.screen_scan and now >= (state.next_ours or 0)) then
        state.ours, state.next_ours = our_textures(), now + 10000
    end
    -- NATIVE COLOUR: the hook DLL swaps the tiles; this only answers it and makes the copies
    if native_colour and native_view then
        serve_native(viewport, key)
        return
    end
    -- another level: its swaps are planned in this frame, so they don't fill in over a few
    local new_level = state.screen_z ~= viewport.z
    -- a pan: the plan's by map position, so only the strip just come into view needs planning,
    -- this frame
    local view = state.screen_view
    local step_started = clock_ms()
    local came_back = false
    if new_level then
        counted('level changes')
        -- back on a level seen lately: its plan again at once, and a new one made in the
        -- background as for any view
        local kept = state.level_plans and state.level_plans[viewport.z]
        if kept then
            counted('level changes with the plan kept')
            state.screen_plan, state.screen_z, state.screen_scan, state.screen_also = kept, viewport.z, nil, nil
            state.next_screen_plan = now
            new_level = false
            -- (grungeisdead's copy, 2026-11-16) and what it doesn't cover (more in view than when it
            -- was made: zoomed out since) planned in this frame by the strip below, as for a pan. It
            -- waited for the next whole plan, 21 frames, in the game's colours (zz-swap-watch: leaves
            -- 21, 22 and 38 frames late after a level change).
            local kept_view = state.level_views and state.level_views[viewport.z]
            if kept_view then view, came_back = kept_view, true end
        else
            -- (counted for zz-swap-watch: in which frame a level with no kept plan had its plan done)
            local fresh = state.fresh_level
            if not fresh or fresh.z ~= viewport.z then
                fresh = {z = viewport.z, frames = 0, ms = 0}
                state.fresh_level = fresh
            end
            fresh.frames = fresh.frames + 1
        end
    end
    -- (grungeisdead's copy, 2026-11-16) and a zoom out: the view grows, often with its corner where
    -- it was, and only the corner was compared, so the new edges waited for the next plan (a
    -- quarter second, then a layer a frame) in the game's own colours: the trees' shades
    -- flickering in on a zoom, seen in play (gone with trees off)
    local port0 = df.global.gps.main_viewport
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port0.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, port0.dim_y)
    -- (a view noted before this change has no size: taken as this one's)
    if view and not view[3] then view = {view[1], view[2], cols, rows} end
    if diag.strip and not new_level and state.screen_plan and view
            and (view[1] ~= viewport.x1 or view[2] ~= viewport.y1 or view[3] ~= cols or view[4] ~= rows) then
        if came_back then counted('level changes with the plan kept and more in view to plan') end
        plan_new_strip(viewport, key, view, clock_ms() + STRIP_BUILD_MS * screen_allowance)
        clocked('planning the strip a pan or zoom brought in', step_started)
    end
    state.screen_view = {viewport.x1, viewport.y1, cols, rows}
    local waiting, count = false, 0
    for _ in pairs(state.wanted) do
        waiting, count = true, count + 1
        if count > BUSY_FROM then break end
    end
    -- many at once (the trees all changing as their leaves fall): faster, for a moment
    if waiting then
        step_started = clock_ms()
        make_wanted(state.screen_copies[key],
            clock_ms() + (count > BUSY_FROM and BUSY_BUILD_MS or BUILD_MS_PER_FRAME) * screen_allowance)
        clocked('making copies that were waiting', step_started)
    end
    step_started = clock_ms()
    local plan_started = clock_s()
    if state.screen_scan or now >= (state.next_screen_plan or 0) or new_level then
        repeat
            -- (grungeisdead's copy) on a new level every pass may copy until the level's whole budget
            -- is spent, not BUILD_MS_PER_FRAME a pass
            local finished = plan_screen(viewport, key, new_level and now + NEW_LEVEL_PLAN_MS * screen_allowance
                or clock_ms() + BUILD_MS_PER_FRAME * screen_allowance)
            if finished then
                -- straight away again while copies wait (they show once a plan has them)
                state.next_screen_plan = (waiting or next(state.wanted)) and now or now + SCREEN_PLAN_MS
            end
        until finished or not new_level or clock_ms() - now >= NEW_LEVEL_PLAN_MS
    end
    -- THE NEW LEVEL'S PLAN AS IT'S MADE (grungeisdead's copy, 2026-11-16). On a level with no kept
    -- plan, what's planned of it so far is drawn straight away (its own level first, then the two
    -- below), as well as the last view's plan: by map level (PLANS BY MAP LEVEL), it covers the
    -- levels the two views share, and nothing else. The new level used to wait in the game's colours
    -- until its whole plan was done, a frame or two later (zz-swap-watch: leaves on a level seen for
    -- the first time, 1 and 2 frames late), and going up, the levels below did again after that.
    if new_level then
        local fresh = state.fresh_level
        if fresh then fresh.ms = fresh.ms + (clock_s() - plan_started) * 1000 end
        if state.screen_z == viewport.z then
            state.screen_also = nil
            local frames = fresh and fresh.frames or 1
            counted(frames == 1 and 'new levels planned in their first frame'
                or frames == 2 and 'new levels planned in their second frame' or 'new levels planned later than that')
            -- (and how long they took, all frames together, for zz-swap-watch)
            local ms = fresh and fresh.ms or 0
            new_level_ms.n, new_level_ms.total = new_level_ms.n + 1, new_level_ms.total + ms
            new_level_ms.worst = math.max(new_level_ms.worst, ms)
            state.fresh_level = nil
        elseif state.screen_scan and state.screen_scan.z == viewport.z then
            state.screen_also = state.screen_scan.plan
        end
    end
    clocked('planning the view', step_started)
    step_started = clock_ms()
    if sway_mode == 'on' then update_sway(key) elseif state.sway then forget_sway() end
    clocked('tree sway frames', step_started)
    step_started = clock_ms()
    apply_screen(viewport)
    clocked('writing the copies to the screen', step_started)
    step_started = clock_ms()
    grass_wave(viewport)
    clocked('grass wave and rustle', step_started)
end

-- The game's own texture a colour copy was made from (or the texture itself, if it isn't one).
-- The lookup is rebuilt only when the look shown changes or more of its copies have been made
-- (frost asks for every tile still waiting to bake, every frame).
local original_by_copy, original_for_step, original_for_built
function original_of(texpos)
    if not state or not state.shown then original_by_copy = nil return texpos end
    local leaning_from = state.lean and state.lean.original[texpos]
    if leaning_from then return leaning_from end
    local built = state.built and state.built[state.shown]
    if original_for_step ~= state.shown or original_for_built ~= built or not original_by_copy then
        original_by_copy, original_for_step, original_for_built = {}, state.shown, built
        for original, copy in pairs(state.copies[state.shown] or {}) do original_by_copy[copy.texpos] = original end
    end
    return original_by_copy[texpos] or texpos
end

-- The screen cells (this level) that are underground, worked out again when the view moves and
-- every UNDERGROUND_MASK_MS (a pan's new cells are known the frame they show).
local function underground_cells(viewport, port)
    local now = clock_ms()
    local m = state.underground_mask
    if m and m.x == viewport.x1 and m.y == viewport.y1 and m.z == viewport.z and m.dim_x == port.dim_x
            and m.dim_y == port.dim_y and now < m.due then
        return m.cells, m.wet
    end
    -- (and of them, those with water: WATER THROUGH THE TABLES)
    local cells, wet = {}, {}
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, port.dim_y)
    for sx = 0, cols - 1 do
        for sy = 0, rows - 1 do
            local under, has_water = underground(viewport.x1 + sx, viewport.y1 + sy, viewport.z, now)
            if under then
                cells[#cells + 1] = sx * port.dim_y + sy
                if has_water then wet[#wet + 1] = sx * port.dim_y + sy end
            end
        end
    end
    state.underground_mask = {x = viewport.x1, y = viewport.y1, z = viewport.z, dim_x = port.dim_x,
                              dim_y = port.dim_y, due = now + UNDERGROUND_MASK_MS, cells = cells, wet = wet}
    return cells, wet
end

-- Every frame: the ground on underground tiles back to the game's own (the tables show the look
-- everywhere, and the weather is the surface's).
function put_back_underground(viewport)
    local port = df.global.gps.main_viewport
    local cells, wet = underground_cells(viewport, port)
    if #cells == 0 then return end
    original_of(0)   -- brings the lookup up to date
    local by_copy = original_by_copy
    if not by_copy then return end
    local ground = port.screentexpos_background
    -- TREE PIECES: cavern trees are drawn from the same pieces, partly in the layer above the
    -- ground, so that layer is put back too
    local above = port.screentexpos_background_two
    for k = 1, #cells do
        local i = cells[k]
        local original = by_copy[ground[i]]
        if original then ground[i] = original end
        original = by_copy[above[i]]
        if original then above[i] = original end
    end
    -- WATER THROUGH THE TABLES: the water's flows are drawn in the building layer (the river's beds in
    -- the two above), so on underground tiles with water that layer is put back too
    if #wet > 0 then
        local flows = port.screentexpos_building_one
        for k = 1, #wet do
            local i = wet[k]
            local original = by_copy[flows[i]]
            if original then flows[i] = original end
        end
    end
end

-- The look showing ({temperature, wet}) and its key, or nil: for other modules that redraw
-- textures themselves (frost's ramps), with looks.redraw.
function shown_look()
    if not state or not state.shown or mode == 'off' then return nil, nil end
    -- (SHOWN LOOK KEPT: it gave the look wanted with the key showing, so while the next look was made,
    -- frost baked ramps in the next look's colours and kept them under this look's key)
    return state.shown_look or state.look, state.shown
end

-- (grungeisdead's copy, 2026-11-17) The look being made to show next, and its key; nil while the look
-- wanted is the one showing. For frost.lua, which bakes the ramps in view for it ahead of time
-- (frost.lua: THE NEXT LOOK AHEAD).
function pending_look()
    if not state or not state.shown or not state.look or mode == 'off' then return nil, nil end
    local key = looks.look_key(state.look)
    if key == state.shown then return nil, nil end
    return state.look, key
end

-- (frost.lua: CRACKS IN PLACE, FLOORS AHEAD, 15V) What the game draws for `original` in the look `key` once it
-- shows: its table copy; the original itself where the look is built and has none; nil while the look is
-- still being built and has none yet.
function look_copy_of(original, key)
    if not state or not key then return nil end
    local set = state.copies[key]
    local copy = set and set[original]
    if copy then return copy.texpos end
    local built = state.built and state.built[key]
    if built and built > #state.originals then return original end
    return nil
end

-- The look's version of one of the game's textures (the texture itself if it has none yet).
function copy_of(original)
    local copy = state and state.shown and state.copies[state.shown] and state.copies[state.shown][original]
    return copy and copy.texpos or original
end

-- A texture's class (grass, dirt, sand, stone, pebbles or other), or nil before the tables are read.
function class_of(texpos) return state and state.class_of[texpos] end

-- Back to the game's own textures and forget everything (e.g. turned off, or reloaded).
function reset()
    if not state then return end
    show(nil)
    forget_screen(nil)
    for _, set in pairs(state.copies) do
        for _, copy in pairs(set) do discard(copy.handle) end
    end
    copies_generation = copies_generation + 1
    state = nil
end

-- A world unloading takes its tables with it: forget them without writing to them.
dfhack.onStateChange.detailed_weather_colour = function(event)
    if event == SC_WORLD_UNLOADED or event == SC_MAP_UNLOADED then
        state, underground_blocks = nil, {}
        copies_generation = copies_generation + 1
        for k in pairs(pointed_from) do pointed_from[k] = nil end   -- the next world's numbers mean other things
    end
end

function describe()
    if not state then return 'not started' end
    local key = state.look and looks.look_key(state.look)
    local built = key and state.built and state.built[key] or 1
    local look = state.look and ('temperature %d of -%d..%d (the ground at %s), wetness %d of 0..%d'):format(
        state.look.temperature, COLD_STEPS, WARM_STEPS, surface_celsius and ('%.1f C'):format(surface_celsius) or '?',
        state.look.wet, WET_STEPS) or 'none yet'
    local building = built - 1 < #state.originals and ('; building %d/%d'):format(built - 1, #state.originals) or ''
    -- (CHANGES OF LOOK TIMED: the last few, oldest first)
    local timed = {}
    for _, c in ipairs(changes_timed) do
        local p = c.phase
        timed[#timed + 1] = ('%.1f s, %d frames (sheet %d, textures %d, water %d, screen %d, lean %d, cracks %d%s; the DLL\'s full redraws used up %d times, its pool or ring %d; overlay %.1f ms a frame, worst %.1f; the DLL\'s painting and swapping %s)')
            :format(c.ms / 1000, c.frames, p.sheet or 0, p.textures or 0, p.water or 0, p.screen or 0, p.lean or 0, p.cracks or 0,
                    c.gave_up and (', gave up with %d cells waiting'):format(c.gave_up) or '', c.capped, c.busy,
                    (c.overlay or 0) / math.max(1, c.frames), c.overlay_worst or 0,
                    c.dll_ms and ('%.1f ms a frame'):format(c.dll_ms / math.max(1, c.frames)) or 'not read')
    end
    local changes = #timed > 0 and ('; changes of look: ' .. table.concat(timed, '; ')) or ''
    return ('%s; look %s (%s%s%s); wetness %s; %d textures redrawn (%d pre-rendered), %d table entries%s%s'):format(
        mode, look, state.shown == key and 'showing' or 'waiting', key and state.from_sheet[key] and ', from its sheet' or '',
        building, wetness.describe(), #state.originals, state.slotted, state.entries, (', %d tiles swapped on screen'):format(#(state.screen_plan or {})),
        changes)
end
