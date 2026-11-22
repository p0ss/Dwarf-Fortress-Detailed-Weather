-- Falling leaves and blossom, for Detailed Weather: in autumn, leaves come loose from the
-- deciduous trees in view and drift down under them, and in spring petals fall from the fruit
-- trees' blossom, a few at first and more as the day the tree drops them nears.
--
-- When: a tree's raws give each growth a period. The game takes a deciduous tree's leaves (LEAVES,
-- timing 0 to 300000 for the oaks, maples, birches and orchard trees) away at the period's end,
-- late in Timber; leaves fall over the LEAF_TICKS before that. Evergreens (pine, cedar, willow,
-- the palms and tropical trees) have no end and never shed. Blossom (FLOWERS, 60000 to 119999 for
-- nearly every fruit and nut tree, evergreen or not) gives way to the fruit at its end, early in
-- Hematite; petals fall over the PETAL_TICKS before that. Each falls in HEAVINESS_FROM steps.
--
-- Leaves take the colour the tree's own leaves are at the time: the raws give each deciduous tree's
-- leaves a colour by season (green, then yellow, orange and red in the game's palette before they
-- drop; a ginkgo stays yellow), matched to the leaf sheets (leaf_sheet).
--
-- Petals take the colour the game gives the tree's flowers (cherry lavender blush, apple rose,
-- peach and plum pink, almond heliotrope, pear ivory...), grouped into the colours of the petal
-- sheets (petal_sheet). Green flowers (oak, maple, persimmon, lychee) aren't shown: they'd read as
-- leaves. Catkins (hazel, birch, willow...) aren't petals and aren't shown either.
--
-- Where: each tile in view under the canopy of a tree that sheds something, at the view's level or
-- up to LEVELS_ABOVE above it with nothing solid between, and the tiles next to those (they drift
-- out from under the edge). What's over each tile is worked out a little each frame (PLAN_MS) and
-- kept, as trees change slowly; it's forgotten every FORGET_MS to catch growth and felling.
--
-- The art is seamless patches of leaves or petals (art/leaves.png and art/petals_<colour>.png,
-- built by tools/weather/make_leaf_sheet.py) repeated across the map like the falling snow, drawn
-- in the game's projectile layer: over the trees and creatures, under the rain and snow (which use
-- the flow layer above it). A petal sheet is only loaded once a tree of its colour sheds.
--@ module = true

local grass = reqscript('internal/detailed_weather/grass')

local TICKS_PER_MONTH = 33600
local YEAR_TICKS = 12 * TICKS_PER_MONTH
local LEAF_TICKS = 2 * TICKS_PER_MONTH    -- leaves fall over the last two months before they're gone
local PETAL_TICKS = 24000                 -- petals over the last 40% of the blossom, about 3 weeks
-- share of the fall's time from which each heaviness starts: few, some, many
local HEAVINESS_FROM = {0, 0.4, 0.75}
local STRONG_WIND = 0.9        -- wind strength that shakes loose one heaviness more
local LEVELS_ABOVE = 6         -- canopy this many levels above the view still sheds into it
local PLAN_MS = 2              -- time each frame for working out what's over new tiles
local FORGET_MS = 60000

-- each: 'auto' (by the season), 'off', or a forced heaviness 1-3
mode = mode or 'auto'          -- leaves
petals_mode = petals_mode or 'auto'
-- map tile key -> raw index of the shedding tree over it, or false
over = over or {}
over_seed = over_seed or {}   -- map tile key -> that tree's seed (tree_at)
over_count = over_count or 0
forget_at = forget_at or 0
timing = timing or {apply = 0}

local function key_of(x, y, z) return (z * 4096 + x) * 4096 + y end

----------------------------------------------------------------------------------------------
-- Which trees shed, and when
----------------------------------------------------------------------------------------------

-- The petal sheet for a growth's flower colour, or nil for green flowers (they'd read as leaves).
local function petal_sheet(growth)
    local info = dfhack.matinfo.decode(growth.mat_type, growth.mat_index)
    local index = info and info.material.state_color.Solid
    local colour = index and index >= 0 and df.global.world.raws.descriptors.colors[index]
    if not colour then return 'petals_white' end
    local r, g, b = colour.red, colour.green, colour.blue
    if g > r + 0.05 and g > b then return nil end
    if r > 0.75 and g > 0.65 and b < 0.55 then return 'petals_yellow' end      -- saffron, buff
    if r - g > 0.15 then return g < 0.6 and 'petals_pink' or 'petals_pale_pink' end
    if r - g > 0.03 and b > g then return 'petals_pale_pink' end            -- lavender blush (cherry)
    return 'petals_white'                                                     -- white, ivory, cream
end

-- The leaf sheet for a colour from the game's palette (fg 0-7, bright 0/1): its leaves turn
-- yellow, then orange, then red in autumn (the colours vary with the palette in use), or nil
-- while they're green.
local function leaf_sheet(fg, bright)
    local colour = df.global.gps.uccolor[fg + 8 * bright]
    local r, g, b = colour[0], colour[1], colour[2]
    if g > r and g > b then return nil end           -- green
    if g > 0.7 * r then return 'leaves_yellow' end
    if g > 0.3 * r then return 'leaves_orange' end
    return 'leaves_red'
end

-- A LEAVES growth's colours through the year: a list of {from, to (year ticks), sheet}, the
-- sheet nil while green.
local function leaf_stages(growth)
    local stages = {}
    for _, p in ipairs(growth.prints) do
        stages[#stages + 1] = {from = p.timing_start, to = p.timing_end,
                               sheet = leaf_sheet(p.color[0], p.color[2])}
    end
    return stages
end

-- The sheet for a tree's leaves at a year tick: its colour then, or the autumn mix ('leaves')
-- while it's green or its raws give no colours (forced out of season).
local function leaf_sheet_at(shed, tick)
    for _, stage in ipairs(shed.stages or {}) do
        if tick >= stage.from and tick <= stage.to then return stage.sheet or 'leaves' end
    end
    return 'leaves'
end

-- plant raw index -> what the tree sheds: a list of {what = 'leaves'|'petals', sheet = art name,
-- ends = the year tick it's gone, span = ticks it falls over, stages = (leaves) their colours
-- through the year}. Only trees that shed something.
local shedding
local function sheds()
    if shedding then return shedding end
    shedding = {}
    for index, plant in ipairs(df.global.world.raws.plants.all) do
        if plant.flags.TREE then
            local list = {}
            for _, growth in ipairs(plant.growths) do
                local timed = growth.timing_1 >= 0 and growth.timing_2 > growth.timing_1
                    and growth.timing_2 < YEAR_TICKS
                if timed and growth.id == 'LEAVES' then
                    list[#list + 1] = {what = 'leaves', sheet = 'leaves', ends = growth.timing_2, span = LEAF_TICKS,
                                       stages = leaf_stages(growth)}
                elseif timed and growth.id == 'FLOWERS' then
                    local sheet = petal_sheet(growth)
                    if sheet then
                        list[#list + 1] = {what = 'petals', sheet = sheet, ends = growth.timing_2, span = PETAL_TICKS}
                    end
                end
            end
            if #list > 0 then shedding[index] = list end
        end
    end
    return shedding
end

local function mode_for(what) return what == 'petals' and petals_mode or mode end

-- How far into its fall a shedding is: 0 to 1, or nil when it isn't falling.
local function share_of(shed, tick)
    local share = (tick - (shed.ends - shed.span)) / shed.span
    if share >= 0 and share < 1 then return share end
end

-- What a tree is shedding now: the sheet's art name and how heavily (1 to #HEAVINESS_FROM), or nil.
local function falling_from(raw_index, tick, strength)
    for _, shed in ipairs(sheds()[raw_index] or {}) do
        local how = mode_for(shed.what)
        local heaviness = tonumber(how)
        if not heaviness and how ~= 'off' then
            local share = share_of(shed, tick)
            if share then
                for step, from in ipairs(HEAVINESS_FROM) do
                    if share >= from then heaviness = step end
                end
            end
        end
        if heaviness then
            if strength >= STRONG_WIND then heaviness = heaviness + 1 end
            local sheet = shed.what == 'leaves' and leaf_sheet_at(shed, tick) or shed.sheet
            return sheet, math.min(heaviness, #HEAVINESS_FROM)
        end
    end
end

----------------------------------------------------------------------------------------------
-- What's over each tile
----------------------------------------------------------------------------------------------

local TREE = df.tiletype_material.TREE
local EMPTY, RAMP_TOP = df.tiletype_shape.EMPTY, df.tiletype_shape.RAMP_TOP
local CANOPY = {[df.tiletype_shape.BRANCH] = true, [df.tiletype_shape.TWIG] = true,
                [df.tiletype_shape.TRUNK_BRANCH] = true}
local attrs_of = {}   -- tiletype -> its attrs, which are slow to look up
local function attrs(tiletype)
    local a = attrs_of[tiletype]
    if not a then
        local raw = df.tiletype.attrs[tiletype]
        a = {material = raw.material, shape = raw.shape}
        attrs_of[tiletype] = a
    end
    return a
end

-- Each tree's leaves are the patch shifted and started at a point of its own, from where its trunk
-- stands (its seed): every tree showed the same leaves falling at the same moment (Poss). Where
-- two trees' canopies meet, a leaf crossing from one to the other jumps.
local plant_raw, plant_seed = {}, {}   -- tree tile key -> raw index, or false; and its seed
local function tree_at(x, y, z)
    local key = key_of(x, y, z)
    local raw = plant_raw[key]
    if raw == nil then
        local plant = dfhack.maps.getPlantAtTile(x, y, z)
        raw = plant and plant.material or false
        plant_raw[key] = raw
        plant_seed[key] = plant and (plant.pos.x * 7919 + plant.pos.y * 104729) % 65521 or 0
    end
    return raw, plant_seed[key]
end

-- The shedding tree whose canopy is over a tile at level z (or at z itself), or false, and its seed. Indoors,
-- underground or hidden tiles, and tiles with a floor or wall between them and the canopy, get none.
local function find_over(x, y, z)
    local block_at = grass.block_at
    local block = block_at(x, y, z)
    if block then
        local flags = block.designation[x % 16][y % 16]
        if flags.hidden or flags.subterranean then return false end
    end
    local trees = sheds()
    for level = z, z + LEVELS_ABOVE do
        local b = block_at(x, y, level)
        if b then
            local a = attrs(b.tiletype[x % 16][y % 16])
            if a.material == TREE then
                if CANOPY[a.shape] then
                    local raw, seed = tree_at(x, y, level)
                    if raw and trees[raw] then return raw, seed end
                    if raw then return false end   -- a canopy that sheds nothing keeps the rest off
                end
            elseif level > z and a.shape ~= EMPTY and a.shape ~= RAMP_TOP then
                return false   -- a floor or roof between
            end
        end
    end
    return false
end

----------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------

-- (seed: the tree's, shifting the patch and where in the loop it is)
local function sheet_tile(layout, heaviness, wind_index, x, y, frame, seed)
    local cells = layout.cells
    x, y = x + seed % cells, y + seed // cells % cells
    frame = (frame + seed // (cells * cells)) % layout.frames
    local cell = (y % cells) * cells + (x % cells)
    local row = ((heaviness - 1) * #layout.winds + (wind_index - 1)) * cells * cells + cell
    return row * layout.frames + frame + 1
end

-- Is anything shedding now? Cheap enough to ask every frame: so the planning is skipped out of season.
local function in_season(tick, what)
    for _, list in pairs(sheds()) do
        for _, shed in ipairs(list) do
            if not what or shed.what == what then
                local how = mode_for(shed.what)
                if tonumber(how) or (how ~= 'off' and share_of(shed, tick)) then return true end
            end
        end
    end
    return false
end

-- What a map tile draws, once everything it rests on is known: {x, y, raw, seed} (raw the tree's
-- raw index), or false for nothing. Kept by tile, so a view that has moved looks each tile up
-- and doesn't work it out again (that was five lookups a tile for every tile in view on each step
-- of a pan, the second largest cost of the whole mod while the view moved). Forgotten with `over`.
decided = decided or {}

-- A tile's entry for `decided`, or nil while what's over it or its neighbours isn't known yet.
-- over_tile(x, y): the shedding tree over a tile (its raw and seed), false for none, nil for
-- not known yet.
local function decide(x, y, z, over_tile)
    -- the tile's own tree, or a neighbour's (leaves drift out past the canopy's edge)
    local raw, seed = over_tile(x, y)
    if raw == nil then return nil end
    if not raw then
        -- (written out, not a loop over a list of neighbours: that made five tables a tile)
        local west, west_seed = over_tile(x - 1, y)
        local east, east_seed = over_tile(x + 1, y)
        local north, north_seed = over_tile(x, y - 1)
        local south, south_seed = over_tile(x, y + 1)
        if west == nil or east == nil or north == nil or south == nil then return nil end
        if west then raw, seed = west, west_seed
        elseif east then raw, seed = east, east_seed
        elseif north then raw, seed = north, north_seed
        elseif south then raw, seed = south, south_seed end
        if not raw then return false end
        -- only onto open ground: not under a roof or underground
        local block = grass.block_at(x, y, z)
        local flags = block and block.designation[x % 16][y % 16]
        if flags and (flags.hidden or flags.subterranean or not flags.outside) then return false end
    end
    return {x = x, y = y, raw = raw, seed = seed or 0}
end

-- The tiles in view to draw leaves on. Worked out again when the view moves or more of what's
-- over the tiles has been found.
local shown = {key = nil, tiles = {}}
local function tiles_in_view(viewport, x2, y2, budget_ends)
    local z = viewport.z
    local found = over_count
    -- what's over a tile, worked out if there's time; nil if not yet
    local function over_tile(x, y)
        local key = key_of(x, y, z)
        local raw = over[key]
        if raw == nil and dfhack.getTickCount() < budget_ends then
            local seed
            raw, seed = find_over(x, y, z)
            over[key], over_seed[key], over_count = raw, seed, over_count + 1
        end
        return raw, over_seed[key]
    end
    local view_key = table.concat({viewport.x1, viewport.y1, x2, y2, z, found}, ',')
    if view_key == shown.key then return shown.tiles end
    local tiles = {}
    local level_key = z * 4096   -- (key_of, written out for the loop)
    for x = viewport.x1, x2 do
        local column_key = (level_key + x) * 4096
        for y = viewport.y1, y2 do
            local key = column_key + y
            local tile = decided[key]
            if tile == nil then
                tile = decide(x, y, z, over_tile)
                if tile ~= nil then decided[key] = tile end
            end
            if tile then tiles[#tiles + 1] = tile end
        end
    end
    -- kept only once nothing more was found while making it, so a list made part way through
    -- the planning is made again next frame
    if over_count == found then shown.key, shown.tiles = view_key, tiles else shown.key = nil end
    return tiles
end

-- Draws this frame's leaves and petals. sheet_of(name): the art by name, {layout =, at =} (at:
-- tile number -> its place among the textures for the wind, 0 where nothing is drawn);
-- sheet_tiles(sheet, wind): those textures, nil while their file waits its turn to load (those
-- trees wait); texpos_of: handle -> texpos; wind_index_for(layout): the layout's wind for the wind
-- now; strength: the wind's strength.
function apply(viewport, sheet_of, sheet_tiles, texpos_of, frame, wind_index_for, strength)
    local started = dfhack.getTickCount()
    local tick = df.global.cur_year_tick
    if not in_season(tick) then return end
    if started >= forget_at then
        over, over_seed, over_count, plant_raw, plant_seed, forget_at, shown.key = {}, {}, 0, {}, {}, started + FORGET_MS, nil
        decided = {}
    end

    local port = df.global.gps.main_viewport
    local layer, dim_x, dim_y = port.screentexpos_projectile, port.dim_x, port.dim_y
    local x1, y1 = viewport.x1, viewport.y1
    -- raw memory: never past the buffer's end (just after a zoom the viewport can be larger)
    local x2, y2 = math.min(viewport.x2, x1 + dim_x - 1), math.min(viewport.y2, y1 + dim_y - 1)
    local tiles = tiles_in_view(viewport, x2, y2, started + PLAN_MS)

    -- per tree raw index, this frame: false (nothing falling) or what to draw
    local drawing = {}
    for _, tile in ipairs(tiles) do
        local raw = tile.raw
        local how = drawing[raw]
        if how == nil then
            local name, heaviness = falling_from(raw, tick, strength)
            how = false
            local art = name and sheet_of(name)
            local wind = art and wind_index_for(art.layout)
            local textures = art and sheet_tiles(art, wind)
            if textures then
                how = {textures = textures, at = art.at, layout = art.layout, heaviness = heaviness, wind = wind,
                       frame = frame % art.layout.frames}
            end
            drawing[raw] = how
        end
        if how then
            local index = sheet_tile(how.layout, how.heaviness, how.wind, tile.x, tile.y, how.frame, tile.seed)
            local i = (tile.x - x1) * dim_y + (tile.y - y1)
            local place = how.at[index]   -- 0: nothing drawn on this tile this frame
            if place > 0 and layer[i] == 0 then layer[i] = texpos_of(how.textures[place]) end
        end
    end
    timing.apply = timing.apply + (dfhack.getTickCount() - started - timing.apply) * 0.05
end

-- What's falling on a tile, for the hover box ('a few maple leaves falling', 'many cherry petals
-- falling'), or nil: the same tiles and trees as apply() draws on.
function falling_at(pos, strength)
    local tick = df.global.cur_year_tick
    if not in_season(tick) then return nil end
    local x, y, z = pos.x, pos.y, pos.z
    local raw = find_over(x, y, z)
    if not raw then
        local block = grass.block_at(x, y, z)
        local flags = block and block.designation[x % 16][y % 16]
        if not flags or flags.hidden or flags.subterranean or not flags.outside then return nil end
        raw = find_over(x - 1, y, z) or find_over(x + 1, y, z) or find_over(x, y - 1, z) or find_over(x, y + 1, z)
    end
    if not raw then return nil end
    local sheet, heaviness = falling_from(raw, tick, strength)
    if not sheet then return nil end
    local plant = df.global.world.raws.plants.all[raw]
    local what = sheet:match('^leaves') and 'leaves' or 'petals'
    local name = plant.name:gsub(' tree$', '')   -- 'sand pear tree' -> 'sand pear leaves'
    return ('%s%s %s falling'):format(({'a few ', '', 'many '})[heaviness], name, what)
end

function forget_world()
    over, over_seed, over_count, plant_raw, plant_seed, forget_at, shedding, shown.key = {}, {}, 0, {}, {}, 0, nil, nil
    decided = {}
end

-- In a few words, for the leaves or the petals, e.g. 'falling' or 'out of season'.
function summary(what)
    local how = mode_for(what)
    if how == 'off' then return 'off' end
    if tonumber(how) then return ({'a few', 'some', 'many'})[tonumber(how)] .. ' falling (forced)' end
    return in_season(df.global.cur_year_tick, what) and 'falling' or 'out of season'
end

function describe()
    local trees, sheets = 0, {}
    for _, list in pairs(sheds()) do
        trees = trees + 1
        for _, shed in ipairs(list) do sheets[shed.sheet] = (sheets[shed.sheet] or 0) + 1 end
    end
    local counts = {}
    for name, count in pairs(sheets) do counts[#counts + 1] = name .. ' ' .. count end
    table.sort(counts)
    return ('falling leaves %s, petals %s: %d trees in the raws shed (%s), %d tiles worked out, %.2f ms a frame')
        :format(summary('leaves'), summary('petals'), trees, table.concat(counts, ', '), over_count, timing.apply)
end
