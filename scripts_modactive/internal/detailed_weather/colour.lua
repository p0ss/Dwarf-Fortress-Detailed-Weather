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
local BUSY_FROM, BUSY_BUILD_MS = 40, 8 -- more than this many waiting on screen: this long a frame
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
local NEW_LEVEL_PLAN_MS = 15          -- on another level, its swaps planned in the one frame up to this
local UNDERGROUND_MASK_MS = 2000      -- which screen cells are underground, worked out again this often
local KEPT_LEVEL_PLANS = 4            -- the plans of this many levels are kept, for coming back to one
local SCREEN_DEPTHS = 3               -- this level and two below: a tree's lower branches showed two
                                      -- levels down, uncoloured (Poss)
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
local function sample_hash(texpos)
    local surface = df.global.enabler.textures.raws[texpos]
    if not surface then return nil end
    local ints = df.reinterpret_cast('int32_t', surface)
    local w, h, pitch = ints:_displace(4)[0], ints:_displace(5)[0], ints:_displace(6)[0]
    if w ~= TILE or h ~= TILE then return nil end
    local bytes = df.reinterpret_cast('uint8_t', df.reinterpret_cast('uint64_t', surface):_displace(4)[0])
    local hash = 0
    for _, n in ipairs(HASH_POINTS) do
        local o = (n // TILE) * pitch + (n % TILE) * 4
        local alpha = bytes[o + 3]
        if alpha > 0 then
            hash = (hash * 31 + bytes[o] + bytes[o + 1] * 256 + bytes[o + 2] * 65536 + alpha * 16777216) % 4294967296
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
    local originals, included, entries = {}, {}, 0
    for texpos, list in pairs(refs_of) do
        entries = entries + #list
        if ground[texpos] then originals[#originals + 1] = texpos included[texpos] = true end
    end
    local tokens = grass.texture_tokens()
    local class_of = setmetatable({}, {__index = function(t, texpos)
        local class = classify(texpos, page_of[texpos], tokens)
        rawset(t, texpos, class)
        return class
    end})
    local slots, partly, slotted = find_sheet_slots(refs_of, class_of)
    return {refs_of = refs_of, originals = originals, included = included, entries = entries, class_of = class_of,
            slots = slots, partly = partly, slotted = slotted, from_sheet = {}, remaking = {},
            copies = {}, shown = nil, look = nil, next_sample = 0, next_seen = 0,
            edges_of_grass = grass.edges_of_grass()}
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
    local class_of = state.class_of
    state.seen_grass, state.seen_grass_list = state.seen_grass or {}, state.seen_grass_list or {}
    local seen_grass, seen_grass_list = state.seen_grass, state.seen_grass_list
    local function note_grass(original)
        if not seen_grass[original] and refs_of[original] and class_of[original] == 'grass' then
            seen_grass[original] = true
            seen_grass_list[#seen_grass_list + 1] = original
            return true
        end
    end
    for i = 0, count - 1 do
        local texpos = values[i]
        -- the grasses this map has, for the leaning frames (new_lean): what's showing is a copy or
        -- a leaning frame, so the picture it was made from is what's noted
        if texpos > 0 then
            local original = pointed_from[texpos] or texpos
            if note_grass(original) then
                -- and its edge pieces, which lean with it but never show in a layer themselves
                for _, edge in ipairs(state.edges_of_grass[original] or {}) do note_grass(edge) end
            end
        end
        -- only the ground goes through the tables (they're shared by every tile, underground too):
        -- anything else (wood, furniture, workshops) is swapped per tile above ground, below
        if texpos > 0 and not included[texpos] and refs_of[texpos] and state.class_of[texpos] ~= 'other' then
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
local function redrawn_copy(texpos, look)
    local class = state.class_of[texpos]
    local px = looks.redraw(texpos, class, look, true)
    if not px then return nil end
    local handle = dfhack.textures.createTile(px, 32, 32)
    return {handle = handle, texpos = dfhack.textures.getTexposByHandle(handle)}
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
-- state.screen_plan = {{depth, layer, x, y, original, copy}...}. Not the buffer itself: the game
-- swaps each screen buffer with its _old twin every frame, so it's looked up as it's written. New copies are made while the frame's budget
-- lasts; cells waiting for one are picked up by a later plan.
-- One layer of one level is looked at per call (the whole set is SCREEN_DEPTHS x SCREEN_LAYERS
-- calls), so the work is spread over frames; the plan being drawn is swapped for the new one when
-- it's complete. Returns true when a plan was finished.
-- Underground keeps the game's own colours: the weather is the surface's, but the tables the
-- look is shown through are shared by every tile on the map, so a wooden wall or a stone floor in
-- the fort took the rain's darkening too. So only the ground goes through the tables, and on
-- screen each underground tile gets the game's own ground back every frame; nothing else is
-- swapped there. Read per block, kept a while (it only changes as the fort digs out to the
-- surface).
underground_blocks = underground_blocks or {}
local function underground(x, y, z, now)
    local key = (z * 1024 + x // 16) * 1024 + y // 16
    local b = underground_blocks[key]
    if not b or now - b.at > UNDERGROUND_KEEP_MS then
        local block = dfhack.maps.getTileBlock(x, y, z)
        if not block then return false end
        local under, designation = {}, block.designation
        for bx = 0, 15 do
            local column = designation[bx]
            for by = 0, 15 do under[bx * 16 + by] = column[by].subterranean end
        end
        b = {under = under, at = now}
        underground_blocks[key] = b
    end
    return b.under[(x % 16) * 16 + y % 16]
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
    screen_ms[step] = (screen_ms[step] or 0) + (dfhack.getTickCount() - started)
end
local function counted(what) screen_counts[what] = (screen_counts[what] or 0) + 1 end

-- A texture's copy for the screen, made now and kept (false if it can't be redrawn).
local function make_screen_copy(t, copies)
    local copy = redrawn_copy(t, state.look) or false
    copies[t] = copy
    -- why it had to be made: the picture under this number changed, or the number is new; and for a
    -- new number, whether the same picture has been copied before under another one
    local hash = sample_hash(t)
    local look_and_hash = hash and (tostring(state.shown) .. ':' .. hash)
    if state.stale[t] then counted('copies made: the picture under a number changed')
    elseif look_and_hash and pictures_copied[look_and_hash] then counted('copies made: new number, picture copied before')
    else counted('copies made: new number, new picture') end
    if look_and_hash then pictures_copied[look_and_hash] = true end
    local stale = state.stale[t]
    if stale then
        discard(stale.handle, 'tree and building copies')
        state.screen_original[stale.texpos] = nil
        state.stale[t] = nil
    end
    if copy then
        copy.hash = sample_hash(t)
        state.ours[copy.texpos] = true
        state.screen_original[copy.texpos] = t
    end
    return copy
end

-- Textures seen on screen still waiting for a copy, made within the frame's budget whatever the
-- plan is looking at. (Copies were only made for the layer being planned, one of SCREEN_LAYERS a
-- frame, and none between plans: a view of trees took over a minute to fill in, Poss.) The plan
-- after picks them up; it's made again straight away while any wait.
local function make_wanted(copies, budget_ends)
    for t in pairs(state.wanted) do
        if dfhack.getTickCount() >= budget_ends then return end
        state.wanted[t] = nil
        if copies[t] == nil then make_screen_copy(t, copies) end
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

local function is_tree(x, y, z)
    local tiletype = dfhack.maps.getTileType(x, y, z)
    if tiletype == nil then return false end
    if tree_tiletype[tiletype] == nil then remember_tiletype(tiletype) end
    return tree_tiletype[tiletype]
end

-- A tree's branches and twigs (where its leaves are), whose leaves rustle in the wind.
local function canopy(x, y, z)
    local tiletype = dfhack.maps.getTileType(x, y, z)
    if not tiletype then return false end
    if canopy_tiletype[tiletype] == nil then remember_tiletype(tiletype) end
    return canopy_tiletype[tiletype]
end

-- One cell: if it shows something to swap, its entry is added to the plan: {depth, layer, x, y,
-- original, copy}, by map position, so a pan doesn't throw the plan out (the cell's place in the
-- buffer is worked out from the view as it's drawn).
local function plan_cell(plan, depth, name, background, t, x, y, z, now, budget_ends, copies, checked)
    -- underground keeps the game's own colours (the ground there is put back every frame:
    -- put_back_underground)
    if t <= 0 or underground(x, y, z, now) then return end
    -- a cell the game hasn't redrawn since still shows the copy: it stays planned
    -- (else it drops out, the game redraws it, it's planned again: a flicker)
    local was = state.screen_original[t]
    if was then t = was end
    -- in the ground layer, only what's in the tables but not ground (a wooden wall), and a tree's
    -- branches (the game draws some there, composited: they stayed pale, Poss): the ground's in
    -- the tables' look, and composited ramps are frost's
    if background and not (state.refs_of[t] and state.class_of[t] == 'other') and not is_tree(x, y, z) then return end
    if not was and (state.ours[t] or made[t]) then return end
    local copy = copies[t]
    -- the game builds these pictures (trees, workshops) as it goes and gives a freed number to a
    -- new one: a copy is only used while its number still shows the picture it was made from
    -- (checked once a plan)
    if copy and not checked[t] then
        checked[t] = true
        if sample_hash(t) ~= copy.hash then
            -- the old copy stays showing until the new one's made (when the last leaves fell, every
            -- tree changed picture at once and flashed the game's own colours for two seconds: Poss)
            local stale = state.stale[t]
            if stale then discard(stale.handle, 'tree and building copies') state.screen_original[stale.texpos] = nil end
            state.stale[t] = copy
            rawset(state.class_of, t, nil)
            copy, copies[t] = nil, nil
            -- and its sway frames, made from the old picture
            local frames = state.sway and state.sway.frames[t]
            if frames then
                for i, f in pairs(frames) do
                    if type(i) == 'number' and f then
                        discard(f.handle, 'tree sway frames')
                        state.screen_original[f.texpos] = nil
                    end
                end
                state.sway.frames[t] = nil
            end
        end
    end
    if copy == nil then
        if dfhack.getTickCount() < budget_ends then
            copy = make_screen_copy(t, copies)
            checked[t] = true
        else
            state.wanted[t] = true   -- made in a later frame (make_wanted)
            copy = state.stale[t]    -- meanwhile the old picture's copy, if it had one
        end
    end
    if copy then
        plan[#plan + 1] = {depth, name, x, y, t, copy.texpos, canopy(x, y, z) or nil}
    end
end

-- A level's plan is kept when the view leaves it, so coming back shows the trees in the look's
-- colours at once and not in the game's own while 21 layers are planned again (going up and down
-- through a wood was the worst the mod ran, and the trees flashed pale each time: Poss). A kept
-- plan is by map position and names originals, not copies (apply_screen finds the copy), so one
-- that's out of date only misses what has changed, until the plan made straight after replaces it.
local function keep_level_plan(z, plan)
    state.level_plans = state.level_plans or {}
    state.level_plans[z] = plan
    -- only the nearest few levels: a plan is a table a swapped tile
    local levels = {}
    for level in pairs(state.level_plans) do levels[#levels + 1] = level end
    if #levels > KEPT_LEVEL_PLANS then
        table.sort(levels, function(a, b) return math.abs(a - z) > math.abs(b - z) end)
        state.level_plans[levels[1]] = nil
    end
end

local function plan_screen(viewport, key, budget_ends)
    local copies = state.screen_copies[key]
    local scan = state.screen_scan
    if not scan or scan.z ~= viewport.z then
        scan = {z = viewport.z, next = 0, plan = {}, checked = {}}
        state.screen_scan = scan
    end
    local plan = scan.plan
    local pass = scan.next
    scan.next = pass + 1
    local depth = pass // #SCREEN_LAYERS
    local layer = SCREEN_LAYERS[pass % #SCREEN_LAYERS + 1]
    local port = viewport_at(depth)
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, port.dim_y)
    local now, z = dfhack.getTickCount(), viewport.z - depth
    local name = 'screentexpos_' .. layer
    local values, background = port[name], layer == 'background'
    for sx = 0, cols - 1 do
        local column = sx * port.dim_y
        for sy = 0, rows - 1 do
            plan_cell(plan, depth, name, background, values[column + sy], viewport.x1 + sx, viewport.y1 + sy, z,
                now, budget_ends, copies, scan.checked)
        end
    end
    if scan.next >= SCREEN_DEPTHS * #SCREEN_LAYERS then
        state.screen_plan, state.screen_z = plan, viewport.z
        state.screen_scan = nil
        keep_level_plan(viewport.z, plan)
        return true
    end
    return false
end

-- The screen positions a pan has just brought into view, as a flat list {sx, sy, sx, sy...} in
-- column order. The view moved by (moved_x, moved_y) tiles; the part of the screen that was
-- already showing is left out, so a one-tile pan lists one column or row and not the whole view.
local function strip_positions(cols, rows, moved_x, moved_y)
    local kept_x1, kept_x2 = math.max(0, -moved_x), math.min(cols, cols - moved_x) - 1
    local kept_y1, kept_y2 = math.max(0, -moved_y), math.min(rows, rows - moved_y) - 1
    local any_rows_kept = kept_y1 <= kept_y2
    local positions = {}
    local function add_rows(sx, first, last)
        for sy = first, last do
            positions[#positions + 1] = sx
            positions[#positions + 1] = sy
        end
    end
    for sx = 0, cols - 1 do
        if any_rows_kept and sx >= kept_x1 and sx <= kept_x2 then
            add_rows(sx, 0, kept_y1 - 1)          -- above what was showing
            add_rows(sx, kept_y2 + 1, rows - 1)   -- and below it
        else
            add_rows(sx, 0, rows - 1)
        end
    end
    return positions
end

-- After a pan: the cells just come into view, every layer and level, planned in this frame (the
-- rest of the plan is by map position, so it carries on as it was). Added to the plan being drawn,
-- and to one being made, if any.
local function plan_new_strip(viewport, key, old_x1, old_y1, budget_ends)
    local copies = state.screen_copies[key]
    local added = {}
    local checked = state.screen_scan and state.screen_scan.checked or {}
    local now = dfhack.getTickCount()
    for depth = 0, SCREEN_DEPTHS - 1 do
        local port = viewport_at(depth)
        local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
        local rows = math.min(viewport.y2 - viewport.y1 + 1, port.dim_y)
        local positions = strip_positions(cols, rows, viewport.x1 - old_x1, viewport.y1 - old_y1)
        local z = viewport.z - depth
        for _, layer in ipairs(SCREEN_LAYERS) do
            local name = 'screentexpos_' .. layer
            local values, background = port[name], layer == 'background'
            for i = 1, #positions, 2 do
                local sx, sy = positions[i], positions[i + 1]
                plan_cell(added, depth, name, background, values[sx * port.dim_y + sy],
                    viewport.x1 + sx, viewport.y1 + sy, z, now, budget_ends, copies, checked)
            end
        end
    end
    for _, list in ipairs({state.screen_plan, state.screen_scan and state.screen_scan.plan}) do
        if list then for _, cell in ipairs(added) do list[#list + 1] = cell end end
    end
end

-- Each frame: writes the planned copies, where the cell still shows what was planned. A cell
-- showing something else that has a copy gets that instead: an animated building (a windmill's
-- sails) shows a different picture each frame, and only swapping the one seen when planned made
-- it flash between the look and the game's own colours.
local function apply_screen(viewport)
    local buffers, dims = {}, {}
    local copies = state.screen_copies and state.screen_copies[state.shown] or {}
    local screen_original = state.screen_original or {}
    local sway = state.sway
    local swaying = sway and sway.playing
    local x1, y1 = viewport.x1, viewport.y1
    local cols = viewport.x2 - viewport.x1 + 1
    local rows = viewport.y2 - viewport.y1 + 1
    for _, cell in ipairs(state.screen_plan or {}) do
        local depth = cell[1]
        local dim = dims[depth]
        if not dim then
            local port = viewport_at(depth)
            dim = {math.min(cols, port.dim_x), math.min(rows, port.dim_y), port.dim_y}
            dims[depth] = dim
        end
        local sx, sy = cell[3] - x1, cell[4] - y1
        if sx >= 0 and sy >= 0 and sx < dim[1] and sy < dim[2] then
            local name = depth .. cell[2]
            local values = buffers[name]
            if not values then
                values = viewport_at(depth)[cell[2]]
                buffers[name] = values
            end
            local i = sx * dim[3] + sy
            local t = values[i]
            -- (a cell the game hasn't redrawn still shows a copy or sway frame of it)
            if t == cell[5] or (t ~= 0 and screen_original[t] == cell[5]) then
                -- (the copy as it is now, not the one noted in the plan: a kept plan can be older
                -- than a copy that was since made again)
                local frames = cell[7] and swaying and sway.frames[cell[5]]
                local texpos = frames and sway_texpos(sway, frames, cell[3], cell[4])
                if not texpos then
                    local copy = copies[cell[5]]
                    texpos = copy and copy.texpos
                end
                if texpos then values[i] = texpos end
            else
                local copy = copies[t]
                if copy then values[i] = copy.texpos end
            end
        end
    end
end

-- The trees' sway frames let go (another look, or another wind direction: they're made from the
-- look's copies, shifted downwind).
-- Every set of sway frames let go (the trees' copies they were made from are going).
local function forget_sway()
    if not state then return end
    for _, sway in pairs(state.sway_sets or {}) do
        for _, frames in pairs(sway.frames) do
            for i, f in pairs(frames) do
                if type(i) == 'number' and f then
                    discard(f.handle, 'tree sway frames')
                    if state.screen_original then state.screen_original[f.texpos] = nil end
                    if state.ours then state.ours[f.texpos] = nil end
                end
            end
        end
    end
    state.sway, state.sway_sets = nil, nil
end

local function forget_screen(keep)
    for key, set in pairs(state.screen_copies or {}) do
        if key ~= keep then
            for _, c in pairs(set) do
                if c then
                    discard(c.handle, 'tree and building copies')
                    if state.screen_original then state.screen_original[c.texpos] = nil end
                end
            end
            state.screen_copies[key] = nil
        end
    end
    for _, c in pairs(state.stale or {}) do
        discard(c.handle, 'tree and building copies')
        if state.screen_original then state.screen_original[c.texpos] = nil end
    end
    state.screen_plan, state.screen_scan, state.wanted, state.stale = nil, nil, {}, {}
    state.level_plans = nil
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

-- Leaning frames are kept once made: a set for each look and wind direction (state.lean_sets),
-- taken up again when the wind or the look comes back, and within a set the rustle frames for
-- each strength of wind. (They were let go and made again on every change, some thousands of
-- textures each time, which is far too many to throw away now that nothing is deleted:
-- grass.lua.) A set only has the grasses seen on this map (state.seen_grass_list), and more are
-- added as they're seen.

-- A set's textures let go.
local function free_lean(l)
    if not l then return end
    for _, frames in pairs(l.frames) do
        for _, f in pairs(frames) do discard(f.handle, 'grass leaning and rustle frames') end
    end
    for _, f in pairs(l.job and l.job.frames or {}) do discard(f.handle, 'grass leaning and rustle frames') end
    for _, kept in pairs(l.rustle_kept or {}) do
        for _, steps in pairs(kept.frames) do
            for _, phases in pairs(steps) do
                for _, f in pairs(phases) do if f then discard(f.handle, 'grass leaning and rustle frames') end end
            end
        end
    end
end

-- No set showing or being made; the sets themselves are kept.
local function rest_lean()
    if not state then return end
    state.lean, state.next_lean = nil, nil
end

-- Every set let go (the look's copies they were made from are going: the look turned off).
local function forget_all_lean()
    if not state then return end
    for _, l in pairs(state.lean_sets or {}) do free_lean(l) end
    state.lean_sets, state.lean, state.next_lean = nil, nil, nil
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
    local now = dfhack.getTickCount()
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
    return {key = look .. ':' .. direction, look = look, direction = direction, ux = ux, uy = uy, grass = {},
            in_set = {}, seen_count = 0, frames = {}, position = 1, shown = 0, original = {}}
end

-- Adds to a set the grasses seen on the map since it was last looked at (their frames are then
-- made by build_lean, as the first ones were).
local function add_seen_grass(l)
    local seen = state.seen_grass_list or {}
    if l.seen_count >= #seen then return end
    for i = l.seen_count + 1, #seen do
        local original = seen[i]
        if not l.in_set[original] then
            l.in_set[original] = true
            l.grass[#l.grass + 1] = original
        end
    end
    l.seen_count = #seen
end

-- The set for a look and wind direction: the one made before, or a new one.
local function lean_set(look, ux, uy, direction)
    state.lean_sets = state.lean_sets or {}
    local key = look .. ':' .. direction
    local l = state.lean_sets[key]
    if not l then
        l = new_lean(look, ux, uy, direction)
        state.lean_sets[key] = l
    end
    add_seen_grass(l)
    return l
end

-- Makes a set's frames, a few a frame (one frame of one texture at a time: a texture's ten
-- together overran the frame's budget). True once they're all made.
local function build_lean(l, started, budget)
    local copies = state.copies[l.look] or {}
    while l.position <= #l.grass and dfhack.getTickCount() - started < budget do
        local original = l.grass[l.position]
        local job = l.job
        if not job or job.original ~= original then
            local copy = copies[original]
            local px = copy and grass.pixels_of(copy.texpos)
            local ox, oy
            if px then ox, oy = clump_offset(px) end
            job = {original = original, px = px, ox = ox, oy = oy, step = 1, frames = {}}
            l.job = job
        end
        if job.ox and job.step <= LEAN_STEPS then
            local step = job.step
            local handle = dfhack.textures.createTile(
                leaning(job.px, job.ox, job.oy, LEAN_MOST_PX * step / LEAN_STEPS, l.ux, l.uy), TILE, TILE)
            if handle then
                job.frames[step] = {handle = handle, texpos = dfhack.textures.getTexposByHandle(handle)}
                l.original[job.frames[step].texpos] = original
            end
            job.step = step + 1
        else
            if job.ox then l.frames[original] = job.frames end
            l.job, l.position = nil, l.position + 1
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
    state.lean, state.next_lean = n, nil   -- (the set before stays in state.lean_sets)
    n.ready = true
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
            n = lean_set(key, ux, uy, direction)
            state.next_lean = n
        end
        if build_lean(n, started, budget) then l = take_over_lean(key, n)
        elseif not l then return end
    end
    -- a grass seen for the first time: its frames are made while the field leans on without it
    -- (it stands upright until they're done, then joins at the field's lean). Holding the whole
    -- field still for each newcomer made it stop and start every time the view found another
    -- grass: it jittered (Poss).
    add_seen_grass(l)
    local was_behind = l.position <= #l.grass
    if was_behind then build_lean(l, started, budget) end
    -- the wind turned and the new set isn't made yet: upright meanwhile, not leaning the old way
    state.lean_turning = direction ~= nil and l.direction ~= direction
    if state.lean_turning then amount = 0 end
    if l.position > #l.grass then
        if was_behind and l.ready then
            show_lean(key, l.shown)   -- the newcomers take the field's lean
            l.step_of = nil           -- and grass_wave lists the set's frames again, theirs included
        end
        l.ready = true
    elseif not l.ready then
        return   -- a set's first frames: all of them first, so the field leans as one
    end
    -- (with the gust's sweep on screen, as the middle of the view: grass_wave)
    if wave_mode ~= 'off' and l.reach_s and not state.lean_turning then amount = lean_ago(l.reach_s) end
    local target, now = amount * LEAN_STEPS, dfhack.getTickCount()
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

-- Frame `phase` of a leaf picture's rustle: each moving clump's pixels a whole pixel off (none,
-- one way or the other, by its phases), drawn over the picture as it was (so a clump that moves
-- leaves its edge behind rather than a hole).
local function rustle_frame(px, phase, kind, sway, moves_pixel)
    moves_pixel = moves_pixel or leafy
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
        -- the set for this look, wind direction and strength: the one made before, if there is one
        -- (a set is kept when the wind changes, not made again when it changes back)
        state.sway_sets = state.sway_sets or {}
        local id = table.concat({key, tostring(direction), kind}, ':')
        sway = state.sway_sets[id]
        if not sway then
            sway = {key = key, direction = direction, kind = kind, ux = ux, uy = uy, frames = {}, clock = 0}
            state.sway_sets[id] = sway
        end
        sway.last, sway.playing = nil, nil
        state.sway = sway
    end
    local copies = state.screen_copies and state.screen_copies[key] or {}
    local started, ready = dfhack.getTickCount(), true
    for _, cell in ipairs(state.screen_plan or {}) do
        local original = cell[5]
        local copy = copies[original]
        local made = sway.frames[original]
        -- (a kept set can have frames of what a texture number showed before the game gave it
        -- another picture: made again, as the copy was)
        local out_of_date = made and copy and made.hash ~= copy.hash
        if cell[7] and (not made or out_of_date) then
            if out_of_date then
                for i, f in pairs(made) do
                    if type(i) == 'number' and f then
                        discard(f.handle, 'tree sway frames')
                        state.screen_original[f.texpos] = nil
                    end
                end
                sway.frames[original] = nil
            end
            -- One frame of one texture at a time, carried over to the next call when the time
            -- runs out (a texture's sixteen together took several times the allowance).
            local job = sway.job
            if not job or job.original ~= original or job.hash ~= (copy and copy.hash) then
                if job then   -- left unfinished for a texture no longer in view
                    for _, f in pairs(job.frames) do
                        if f then
                            discard(f.handle, 'tree sway frames')
                            state.screen_original[f.texpos] = nil
                        end
                    end
                end
                local px = copy and grass.pixels_of(copy.texpos)
                if px and not is_leaves(px) then px = nil end   -- wood: stays put
                job = {original = original, hash = copy and copy.hash, px = px, frames = {}, phase = 1}
                sway.job = job
            end
            while job.phase <= RUSTLE_PHASES do
                if dfhack.getTickCount() - started >= SWAY_MS * screen_allowance then ready = false break end
                local frame = job.px and rustle_frame(job.px, job.phase - 1, kind, sway) or false
                if frame then
                    state.ours[frame.texpos] = true
                    state.screen_original[frame.texpos] = original
                end
                job.frames[job.phase] = frame
                job.phase = job.phase + 1
            end
            if not ready then break end
            job.frames.hash = job.hash
            sway.frames[original] = job.frames
            sway.job = nil
        end
    end
    -- the loop plays at the gust's pace (a gale's never stops); still until every frame is made,
    -- so the canopy starts as one
    local pace = kind == 'gale' and 1 or kind == 'strong' and 0.7 or amount / LEAN_BREEZE_MOST
    local now = dfhack.getTickCount()
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
    if not l or not l.ready or wave_mode == 'off' or state.lean_turning then return end
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
        for _, kept in pairs(l.rustle_kept or {}) do
            for original, steps in pairs(kept.frames) do
                for even, phases in pairs(steps) do
                    for _, f in pairs(phases) do if f then step_of[f.texpos] = {original, even} end end
                end
            end
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
        -- each strength's frames are kept, and taken up again when the wind is that strong again
        l.rustle_kept = l.rustle_kept or {}
        local kept = kind and l.rustle_kept[kind] or {frames = {}, wanted = {}}
        if kind then l.rustle_kept[kind] = kept end
        l.rustle, l.rustle_kind, l.rustle_wanted = kept.frames, kind, kept.wanted
    end
    local playing
    if kind and rustle_grass_mode ~= 'off' then
        local now = dfhack.getTickCount()
        local dt = l.rustle_last and math.min(100, now - l.rustle_last) / 1000 or 0
        l.rustle_last = now
        local pace = kind == 'gale' and 1 or kind == 'strong' and 0.7 or lean_ago(0) / LEAN_BREEZE_MOST
        if pace > 0.05 then
            if not df.global.pause_state then l.rustle_clock = (l.rustle_clock or 0) + dt * RUSTLE[kind].fps * math.min(1, pace) end
            playing = math.floor(l.rustle_clock or 0) % RUSTLE_PHASES
        end
    end
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
    local started = dfhack.getTickCount()
    for k in pairs(wanted) do
        if dfhack.getTickCount() - started >= GRASS_RUSTLE_MS then break end
        wanted[k] = nil
        local phase, even, original = k % 64, (k // 64) % 16, k // 1024
        local base = even > 0 and l.frames[original] and l.frames[original][even]
        local px = grass.pixels_of(base and base.texpos or (copies[original] and copies[original].texpos))
        local f = px and rustle_frame(px, phase, kind, l, function(p) return true end) or false
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
        -- (a kept look's copy of what this number showed before the game gave it another picture
        -- is made again)
        -- (`old` is false for a texture that couldn't be copied: nothing to make for those)
        local kept = set[t]
        local out_of_date = old and kept and kept.hash ~= old.hash
        if old and (kept == nil or out_of_date) then
            if dfhack.getTickCount() - started >= budget then return false end
            if out_of_date then
                discard(kept.handle, 'tree and building copies')
                state.screen_original[kept.texpos] = nil
            end
            local copy = redrawn_copy(t, look) or false
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
-- copies are kept for when the weather comes back to them.
local function switch_screen(key)
    local copies = state.screen_copies and state.screen_copies[key]
    if not copies then return end
    for _, cell in ipairs(state.screen_plan or {}) do
        local copy = copies[cell[5]]
        if copy then cell[6] = copy.texpos end
    end
    state.screen_scan = nil   -- a scan half done for the old look starts again
    state.sway = nil          -- (its set is kept: update_sway)
end

-- Points every entry at the look's copies (key; nil: back at the originals).
-- Goes up whenever the looks' copies are let go (the look turned off, a world unloading): what
-- other modules made from them (paths' worn grass, frost's cracks) is then made again.
copies_generation = copies_generation or 0

local function show(key)
    if key then rest_lean() else forget_all_lean() end
    for _, original in ipairs(state.originals) do point(original, key) end
    state.shown = key
    -- (every look's copies are kept, for when the weather comes back to it: only two were, and
    -- the rest let go, when letting go meant deleting)
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

-- Each frame: works out the look now and then, builds its copies a little at a time, and swaps
-- them in when they're all made.
function update(viewport)
    frame_number = frame_number + 1
    grass.empty_trash()
    if not state then state = find_refs() end
    local now = dfhack.getTickCount()
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
    if state.seen_pass or now >= state.next_seen then
        if look_at_screen(viewport) then state.next_seen = now + SEEN_SCAN_MS end
    end
    local look = state.look
    local key = looks.look_key(look)
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
    local started = dfhack.getTickCount()
    local budget = state.shown and BUILD_MS_PER_FRAME or FIRST_BUILD_MS
    -- the sheet's partly see-through textures, remade, before the look shows
    local remaking = state.remaking[key]
    while remaking and #remaking > 0 and dfhack.getTickCount() - started < budget do
        local item = table.remove(remaking)
        set[item[1]] = unpremultiplied(item[2])
    end
    if remaking and #remaking > 0 then return end
    state.built = state.built or {}
    local position = state.built[key] or 1
    local originals = state.originals
    while position <= #originals and dfhack.getTickCount() - started < budget do
        local original = originals[position]
        if not set[original] then set[original] = redrawn_copy(original, look) end
        -- once the look is showing, things seen later are swapped in as their copies are made
        if state.shown == key then point(original, key) end
        position = position + 1
    end
    state.built[key] = position
    if state.shown == key then
        if lean_mode ~= 'off' then
            update_lean(key, position > #originals, started, budget)
        elseif state.lean or state.next_lean then
            if state.lean then show_lean(key, 0) end   -- upright again
            rest_lean()
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
    if position <= #originals or not screen_ready(key, look, started, budget) then return end
    -- and the grass's leaning frames in the new look, so it doesn't stop while they're made
    local l = state.lean
    if l and l.direction then
        local n = state.next_lean
        local want = key .. ':' .. l.direction
        if not n or n.key ~= want then
            n = lean_set(key, l.ux, l.uy, l.direction)
            state.next_lean = n
        end
        if not build_lean(n, started, budget) then return end
    end
    local next_lean, step = state.next_lean, l and l.shown
    state.next_lean = nil
    show(key)
    switch_screen(key)
    if next_lean and next_lean.look == key then take_over_lean(key, next_lean, step) end
end

-- The per-tile swaps on screen. Called last in the frame, after the snow and frost have written
-- theirs: they then always see the game's own textures, and this shifts whatever ends up showing
-- (fruit the snow lifted above it, say), leaving their own textures be.
function update_screen(viewport)
    if not state or mode == 'off' or not state.look then return end
    if state.shown then put_back_underground(viewport) end
    -- the look showing, not the one wanted: while the next one's made (a few seconds) the trees and
    -- buildings keep this one's copies (they went back to the game's colours meanwhile: Poss)
    local key = state.shown
    if not key then return end
    if screen_mode == 'off' then
        if state.screen_plan then forget_screen(nil) end
        grass_wave(viewport)   -- the grass's gusts and rustle don't depend on the trees' swaps
        return
    end
    local now = dfhack.getTickCount()
    state.screen_copies = state.screen_copies or {}
    if not state.screen_copies[key] then
        state.screen_copies[key] = {}
        state.screen_scan = nil
    end
    state.screen_original = state.screen_original or {}
    state.wanted, state.stale = state.wanted or {}, state.stale or {}
    if not state.ours or (not state.screen_scan and now >= (state.next_ours or 0)) then
        state.ours, state.next_ours = our_textures(), now + 10000
    end
    -- another level: its swaps are planned in this frame, so they don't fill in over a few
    local new_level = state.screen_z ~= viewport.z
    -- a pan: the plan's by map position, so only the strip just come into view needs planning,
    -- this frame
    local view = state.screen_view
    local step_started = dfhack.getTickCount()
    if new_level then
        counted('level changes')
        -- back on a level seen lately: its plan again at once, and a new one made in the
        -- background as for any view
        local kept = state.level_plans and state.level_plans[viewport.z]
        if kept then
            counted('level changes with the plan kept')
            state.screen_plan, state.screen_z, state.screen_scan = kept, viewport.z, nil
            state.next_screen_plan = now
            new_level = false
        end
    end
    if not new_level and state.screen_plan and view and (view[1] ~= viewport.x1 or view[2] ~= viewport.y1) then
        plan_new_strip(viewport, key, view[1], view[2], dfhack.getTickCount() + BUILD_MS_PER_FRAME * screen_allowance)
        clocked('planning the strip a pan brought in', step_started)
    end
    state.screen_view = {viewport.x1, viewport.y1}
    local waiting, count = false, 0
    for _ in pairs(state.wanted) do
        waiting, count = true, count + 1
        if count > BUSY_FROM then break end
    end
    -- many at once (the trees all changing as their leaves fall): faster, for a moment
    if waiting then
        step_started = dfhack.getTickCount()
        make_wanted(state.screen_copies[key],
            dfhack.getTickCount() + (count > BUSY_FROM and BUSY_BUILD_MS or BUILD_MS_PER_FRAME) * screen_allowance)
        clocked('making copies that were waiting', step_started)
    end
    step_started = dfhack.getTickCount()
    if state.screen_scan or now >= (state.next_screen_plan or 0) or new_level then
        repeat
            local finished = plan_screen(viewport, key, dfhack.getTickCount() + BUILD_MS_PER_FRAME * screen_allowance)
            if finished then
                -- straight away again while copies wait (they show once a plan has them)
                state.next_screen_plan = (waiting or next(state.wanted)) and now or now + SCREEN_PLAN_MS
            end
        until finished or not new_level or dfhack.getTickCount() - now >= NEW_LEVEL_PLAN_MS
    end
    clocked('planning the view', step_started)
    step_started = dfhack.getTickCount()
    if sway_mode == 'on' then update_sway(key) else state.sway = nil end
    clocked('tree sway frames', step_started)
    step_started = dfhack.getTickCount()
    apply_screen(viewport)
    clocked('writing the copies to the screen', step_started)
    step_started = dfhack.getTickCount()
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
    local now = dfhack.getTickCount()
    local m = state.underground_mask
    if m and m.x == viewport.x1 and m.y == viewport.y1 and m.z == viewport.z and m.dim_x == port.dim_x
            and m.dim_y == port.dim_y and now < m.due then
        return m.cells
    end
    local cells = {}
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, port.dim_y)
    for sx = 0, cols - 1 do
        for sy = 0, rows - 1 do
            if underground(viewport.x1 + sx, viewport.y1 + sy, viewport.z, now) then
                cells[#cells + 1] = sx * port.dim_y + sy
            end
        end
    end
    state.underground_mask = {x = viewport.x1, y = viewport.y1, z = viewport.z, dim_x = port.dim_x,
                              dim_y = port.dim_y, due = now + UNDERGROUND_MASK_MS, cells = cells}
    return cells
end

-- Every frame: the ground on underground tiles back to the game's own (the tables show the look
-- everywhere, and the weather is the surface's).
function put_back_underground(viewport)
    local port = df.global.gps.main_viewport
    local cells = underground_cells(viewport, port)
    if #cells == 0 then return end
    original_of(0)   -- brings the lookup up to date
    local by_copy = original_by_copy
    if not by_copy then return end
    local ground = port.screentexpos_background
    for k = 1, #cells do
        local i = cells[k]
        local original = by_copy[ground[i]]
        if original then ground[i] = original end
    end
end

-- The look showing ({temperature, wet}) and its key, or nil: for other modules that redraw
-- textures themselves (frost's ramps), with looks.redraw.
function shown_look()
    if not state or not state.shown or mode == 'off' then return nil, nil end
    return state.look, state.shown
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
        for _, copy in pairs(set) do discard(copy.handle, 'ground copies') end
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
    return ('%s; look %s (%s%s%s); wetness %s; %d textures redrawn (%d pre-rendered), %d table entries%s'):format(
        mode, look, state.shown == key and 'showing' or 'waiting', key and state.from_sheet[key] and ', from its sheet' or '',
        building, wetness.describe(), #state.originals, state.slotted, state.entries, (', %d tiles swapped on screen'):format(#(state.screen_plan or {})))
end
