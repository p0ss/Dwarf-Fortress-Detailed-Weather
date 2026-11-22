-- Snow on ramps for Detailed Weather.
--
-- The game keeps snow on ramps (a powder-water spatter, like on floors) but never draws it there,
-- so a snowy hillside shows bare slopes between snowy floors. Lying snow on floors is drawn by the
-- game itself from graphics/images/snow_cover.png; this draws the ramps, by swapping each snowy
-- ramp's texture for the same ramp cell of art/snow_ramps.png (built by
-- tools/weather/make_snow_ramps.py the way Rounded Hills builds its ramps, in snow's colours, with
-- each slope ease into plain snow at its foot). No pixels are worked on here: it's a lookup and a
-- write per ramp.
--
-- Skirts: Rounded Hills' skirts (the tint on the floor beside a slope) are fitted to grass, soil
-- and stone, and over snow they show as grey bands. They're drawn by the renderer from bit flags
-- in screentexpos_shadow_flag, so they can't be swapped; on snowy floors they're cleared, and the
-- snowy slopes ease to plain snow instead.
--
-- Overhangs: a grass ramp (or any ground) drops its edge pieces onto the floor beside it, which
-- would draw green over the snow at the foot of a snowy slope. On a snowy floor, the overhang from
-- each snowy neighbour is cleared (screentexpos_floor_flag: one byte per side, S, W, E, N); one
-- from a bare neighbour stays, landing in the bare margin at the edge of the drift.
--
-- Snow pieces: the game picks a floor's snow piece by which neighbours it thinks have snow, and
-- misses some: it never counts a ramp (it draws no snow there), nor a tile whose snow is hidden
-- under something else (below). So each snowy floor's full piece is swapped for the one joined
-- towards all its snowy neighbours, from this mod's snow page (DETAILED_WEATHER_SNOW,
-- graphics/images/snow_cover.png). And the game draws any snow from 100/255 up as full: below
-- 255 the piece's thin version is used instead (the sheet snow_thin, the same edges with the ground
-- showing through gaps).
--
-- Snowy overhangs: on a bare tile beside snowy grass, the grass edge that grass drops onto it is
-- drawn as snow instead: the edge piece's own shape filled with vanilla's snow, lit like the rest
-- (a bright top, the blue-grey lip beneath), in the layer shrubs and boulders use, with the game's
-- green copy cleared from that tile. Baked once per set of edge pieces and cached.
--
-- Things lying on snow: the game gives each tile one spatter texture, and where something else
-- lies on a snowy tile (fallen berries under a fruit tree, say) it draws that instead of the snow,
-- so the tile looks bare. That texture is moved up to the layer shrubs and boulders use
-- (screentexpos_background_two, drawn over the spatter layer) when it's free, and the snow piece
-- the tile should have (joined towards its snowy neighbours) put back under it.
--
-- Which cell: the game picks a ramp's cell from which neighbours are walls, and keeps that in the
-- second byte of screentexpos_ramp_flag, one bit per neighbour: 1 N, 2 W, 4 E, 8 S, 16 NW, 32 NE,
-- 64 SW, 128 SE. A diagonal only counts when neither side beside it is a wall. The cell for each
-- set of walls is read from the RAMP_WITH_WALL_* tokens (Rounded Hills and vanilla share the
-- layout). Checked against 38 ramps matched pixel for pixel (tools/dfhack/ramp_cells.lua).
--
-- Ramps on the levels below, seen through open space, are in the game's lower viewports
-- (lower_viewport[d - 1] for d levels down), laid out like the main one.
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)
local clock_s = reqscript('internal/detailed_weather/clock').s     -- and in seconds, for timing short work

local SNOWY = 100            -- snow amount (0-255) from which a ramp is drawn snowy
local MOST_DEPTH = 8
local REMEMBER_MS = 2000     -- how long a tile's plan is kept before it's worked out again
-- (grungeisdead's copy, 2026-11-17) QUIET REFRESH: the same while no snow is falling anywhere on the map.
-- Without snowfall the snow only melts, slowly, and tiles in view were worked out again every 2 to 3 s
-- for nothing: most of the planning's time with no snow about (detailed_weather details: snow-plan).
local REMEMBER_QUIET_MS = 10000
-- QUIET REFRESH: when a tile worked out now is due to be worked out again, with snow falling and
-- without. Both are kept, so snow starting to fall brings the sooner one back at once.
local function set_due(tile, now)
    tile.due = now + REMEMBER_MS + math.random(0, REMEMBER_MS // 2)
    tile.due_quiet = now + REMEMBER_QUIET_MS + math.random(0, REMEMBER_QUIET_MS // 2)
end
local WORK_PER_PLAN = 300    -- tiles worked out from scratch at most per plan; a newly shown view
                             -- fills in over a few frames rather than stalling one
local REMEMBER_MOST = 200000 -- tiles remembered (across levels); past this the memory starts afresh
                             -- (60000 was soon passed on a snowy map, every tile snowy, and the whole
                             -- view swept in again from the game's full snow: Poss)
local TEXPOS_RECHECK_FRAMES = 600

local WALL_BITS = {{1, 'N'}, {2, 'W'}, {4, 'E'}, {8, 'S'}, {16, 'NW'}, {32, 'NE'}, {64, 'SW'}, {128, 'SE'}}
local BESIDE = {NW = {'N', 'W'}, NE = {'N', 'E'}, SW = {'S', 'W'}, SE = {'S', 'E'}}
local SHEET_WIDTH = 15
local OVERHANG_SIDES = {{0, 1}, {-1, 0}, {1, 0}, {0, -1}}   -- floor_flag bytes: S, W, E, N
local SIDE_NAMES = {'S', 'W', 'E', 'N'}                       -- the same sides, by name
local OPPOSITE_BYTE = {4, 3, 2, 1}                            -- the byte on the far side: S<->N, W<->E

-- The snow page's FULL pieces: which sides each is joined on (as in make_snow_cover.py).
local SNOW_PAGE = 'DETAILED_WEATHER_SNOW'
local FULL_PIECES = {
    {'NSWE', 0, 0}, {'NSWE', 0, 4}, {'NSWE', 1, 4}, {'NSWE', 2, 4}, {'NSWE', 3, 4},
    {'', 1, 0}, {'NS', 2, 0}, {'WE', 3, 0}, {'N', 0, 1}, {'S', 1, 1}, {'W', 2, 1}, {'E', 3, 1},
    {'NW', 0, 2}, {'NE', 1, 2}, {'SW', 2, 2}, {'SE', 3, 2},
    {'NSW', 0, 3}, {'NSE', 1, 3}, {'NWE', 2, 3}, {'SWE', 3, 3},
}
local OTHER_CELL = 28        -- RAMP_OTHER: no walls

local art_dir = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or '') .. '../../../art/'
local grass = reqscript('internal/detailed_weather/grass')   -- texture pixels, grass edge art
local work_time = reqscript('internal/detailed_weather/work_time')   -- the frame's shared time for background work
_G.detailed_weather_made = _G.detailed_weather_made or {}   -- shared: see frost.lua
local made = _G.detailed_weather_made

local OVERHANG_BAKES_PER_FRAME = 4
local THIN_BAKES_PER_PLAN = 8
local THIN_FADE = 7                -- px over which thin snow thickens to full towards a full neighbour
local grass_material = {[df.tiletype_material.GRASS_LIGHT] = true, [df.tiletype_material.GRASS_DARK] = true,
                        [df.tiletype_material.GRASS_DRY] = true, [df.tiletype_material.GRASS_DEAD] = true}
local SNOW_LIP = {174, 190, 215}   -- vanilla's snow shade
local SNOW_RIM = {255, 255, 255}

----------------------------------------------------------------------------------------------
-- Which cell each ramp_flag byte means
----------------------------------------------------------------------------------------------

-- The walls a byte names, as a sorted key like 'E_N_SW'.
local function walls_key(byte)
    local sides, walls = {}, {}
    for _, bit in ipairs(WALL_BITS) do
        if #bit[2] == 1 and byte & bit[1] ~= 0 then sides[bit[2]] = true walls[#walls + 1] = bit[2] end
    end
    for _, bit in ipairs(WALL_BITS) do
        local beside = BESIDE[bit[2]]
        if beside and byte & bit[1] ~= 0 and not sides[beside[1]] and not sides[beside[2]] then
            walls[#walls + 1] = bit[2]
        end
    end
    table.sort(walls)
    return table.concat(walls, '_')
end

-- byte -> cell, from vanilla's ramp tokens (the same layout as Rounded Hills').
local function cell_table()
    local path = dfhack.getDFPath() .. '/data/vanilla/vanilla_environment/graphics/graphics_tiles.txt'
    local file = io.open(path, 'r')
    local text = file and file:read('a') or ''
    if file then file:close() end
    local by_walls = {}
    for x, y, names in text:gmatch('%[TILE_GRAPHICS:STONE_RAMPS:(%d+):(%d+):STONE_RAMP_WITH_WALL_([%u_]+)%]') do
        local walls = {}
        for name in names:gmatch('%u+') do walls[#walls + 1] = name end
        table.sort(walls)
        by_walls[table.concat(walls, '_')] = tonumber(y) * SHEET_WIDTH + tonumber(x)
    end
    local cells = {}
    for byte = 0, 255 do cells[byte] = by_walls[walls_key(byte)] or OTHER_CELL end
    return cells
end

----------------------------------------------------------------------------------------------
-- Art
----------------------------------------------------------------------------------------------

art = art or nil
local cell_of_byte

-- reload: load a fresh copy of the art (DFHack caches tilesets by path for the session), and of
-- the thin snow's sheets the next time they're wanted.
function load_art(path)
    if path then thin_reloads, thin_art = (thin_reloads or 0) + 1, nil end
    art = {handles = dfhack.textures.loadTileset(path or (art_dir .. 'snow_ramps.png'), 32, 32, true),
           texpos = {}, fetched = {}}
end

-- RAMPS BY PICTURE (grungeisdead's copy, 2026-11-17). The game builds ramps' pictures as it draws and
-- hands freed numbers to new pictures, so a ramp can come back under a new number (frost.lua met the
-- same). A snowy ramp's record knew its ramp by number alone, so a new number let it go, and the ramp
-- showed bare until it was worked out again: the same slopes flickering at every zoom (seen in play:
-- the same strips in the same place). A record now keeps its ramp's picture too (colour.lua's filing:
-- the same pixels, the same id), and takes the new number when the picture is the same.
local colour_module   -- colour.lua, asked for on first use (it's loaded by then; not at the top, so
                      -- neither file waits on the other while loading)
local function picture_id(texpos)
    colour_module = colour_module or reqscript('internal/detailed_weather/colour')
    return colour_module.picture_of and colour_module.picture_of(texpos) or nil
end

local function snowy_texpos(cell, frame_number)
    local texpos = art.texpos[cell]
    if not texpos or frame_number - art.fetched[cell] > TEXPOS_RECHECK_FRAMES then
        local handle = art.handles[cell + 1]
        texpos = handle and dfhack.textures.getTexposByHandle(handle) or false
        art.texpos[cell], art.fetched[cell] = texpos, frame_number
        if texpos then made[texpos], snow_made[texpos] = true, true end   -- (STILL OURS)
    end
    return texpos or nil
end

-- texpos -> the sides that piece is joined on, and sides -> the pieces for them; nil until the
-- snow page is loaded (it isn't if Detailed Weather's graphics aren't in this world).
local piece_sides, pieces_for, snow_page_art, piece_cell
local SNOW_PAGE_WIDTH = 8
local function find_snow_pieces()
    piece_sides, pieces_for, snow_page_art, piece_cell = {}, {}, {}, {}
    for _, page in ipairs(df.global.texture.page) do
        if page.token == SNOW_PAGE then
            for _, texpos in ipairs(page.texpos) do snow_page_art[texpos] = true end
            for _, piece in ipairs(FULL_PIECES) do
                local texpos = page.texpos[piece[3] * page.page_dim_x + piece[2]]
                piece_cell[texpos] = piece[3] * SNOW_PAGE_WIDTH + piece[2]
                local sides = {}
                for side in piece[1]:gmatch('%u') do sides[side] = true end
                piece_sides[texpos] = sides
                local key = piece[1]
                pieces_for[key] = pieces_for[key] or {}
                table.insert(pieces_for[key], texpos)
            end
        end
    end
end

-- The full piece joined on exactly these sides (a set of 'N', 'S', 'W', 'E'), or nil.
local function piece_joined_on(sides, x, y)
    local key = ''
    for _, side in ipairs({'N', 'S', 'W', 'E'}) do
        if sides[side] then key = key .. side end
    end
    local choices = pieces_for[key]
    return choices and choices[(x * 7 + y * 13) % #choices + 1]
end

-- The thin version of a full piece for map tile (x, y) with `amount` snow, or the piece.
-- The sheet snow_thin (make_snow_cover.py; layout in art/snow_thin_sheet.lua) has each FULL piece cut
-- by a gap pattern repeat_tiles across, each tile taking the piece of the pattern for its place on
-- that grid so neighbours join. One pattern everywhere made a glacier's field of 100/255 snow a
-- single texture with its 4-tile repeat plain (Poss), so:
--   versions  each piece of the pattern comes in several, the same at the tile's border but with
--             their own gaps inside: any joins any neighbour, and each tile takes one at random
--   levels    lighter and heavier cuts of the same pattern; a tile's follows its snow and a slow
--             noise over the map that never repeats, so the snow gathers in drifts
local DRIFT_TILES = {11, 5}       -- tiles across the noise's two scales (drifts, and patches in them)
local DRIFT_WEIGHTS = {0.7, 0.3}
thin_art = thin_art or nil
thin_layout = thin_layout or nil   -- art/snow_thin_sheet.lua

local function lattice(ix, iy, seed)
    local h = (ix * 374761393 + iy * 668265263 + seed * 2246822519) & 0xffffffff
    h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
    return ((h ~ (h >> 16)) & 0xffff) / 0xffff
end

-- A smooth noise over map tiles, -1 to 1, the same every time for a tile.
local function drift(x, y)
    local total = 0
    for n, span in ipairs(DRIFT_TILES) do
        local fx, fy = x / span, y / span
        local ix, iy = math.floor(fx), math.floor(fy)
        local tx, ty = fx - ix, fy - iy
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        local a, b = lattice(ix, iy, n), lattice(ix + 1, iy, n)
        local c, d = lattice(ix, iy + 1, n), lattice(ix + 1, iy + 1, n)
        local v = (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
        total = total + (v * 2 - 1) * DRIFT_WEIGHTS[n]
    end
    return total
end

-- How much of the ground the snow covers follows its amount (0-255; the game draws all of it from
-- 100 up as full): about half at 100, full by about 160 ("full over halfway", Poss), and from
-- about 210 piles and drifts shaded on the full cover; the sheet's levels, from the amount with a
-- little slow noise, so a field at one amount doesn't change all at once as the snow builds.
local LEVEL_FROM = {0.16, 0.39, 0.71}   -- (amount - 100) / 155 where each level after the first starts
local LEVEL_SWAY = 0.07                 -- the noise's reach, in the same units
local function level_for(amount, nx, ny)
    local v = (math.max(SNOWY, math.min(255, amount)) - SNOWY) / (255 - SNOWY) + drift(nx, ny) * LEVEL_SWAY
    local level = 0
    for n, from in ipairs(LEVEL_FROM) do if v >= from then level = n end end
    return level
end

-- The level at the corner at the top left of tile (x, y), from the four tiles that meet there and
-- shared by them: the plain inside piece eases across each tile between its corners' levels, so
-- the snow thickens and thins with no line where tiles meet (a level per tile left hard edges,
-- Poss). A corner touching anything but snow-all-round (bare ground, an edge piece) is at the
-- level the other pieces' borders are cut at.
local CORNER_KEPT_MS = 3000
corner_levels = corner_levels or {}
local function corner_level(x, y, z, edge_level, now)
    local key = (z * 4096 + x) * 4096 + y
    local kept = corner_levels[key]
    if kept and now < kept.due then return kept.level end
    local level, total = nil, 0
    for _, t in ipairs({{x - 1, y - 1}, {x, y - 1}, {x - 1, y}, {x, y}}) do
        local tx, ty = t[1], t[2]
        local amount = grass.snow_amount(tx, ty, z, now)
        if amount < SNOWY then level = edge_level break end
        for _, step in ipairs(OVERHANG_SIDES) do
            if grass.snow_amount(tx + step[1], ty + step[2], z, now) < SNOWY then level = edge_level break end
        end
        if level then break end
        total = total + amount
    end
    level = level or level_for(total / 4, x - 0.5, y - 0.5)
    corner_levels[key] = {level = level, due = now + CORNER_KEPT_MS}
    return level
end

-- A thin-snow sheet: {handles =, at = (tile number as drawn -> its place among the handles),
-- texpos = {}}. The two are packed with each different tile once (tools/weather/sheet_packing.py:
-- art/falling/<name>-1.png and the index <name>.lua), and are still some 40 MB of pixels between
-- them. DFHack keeps every file it has loaded until the game closes, so they're loaded once a
-- session from their own path (which it hands back if asked again) and kept through forget().
-- Only after `detailed_weather reload` (thin_reloads, for art rebuilt while playing) is a fresh
-- copy loaded under another name, as DFHack wouldn't read the same path twice.
local function load_thin_sheet(name)
    local path = art_dir .. 'falling/' .. name .. '-1.png'
    if (thin_reloads or 0) > 0 then
        local copies = art_dir .. 'reloaded/'
        dfhack.filesystem.mkdir(copies)
        local copy = copies .. name .. '-' .. thin_reloads .. '.png'
        local input = assert(io.open(path, 'rb'))
        local output = assert(io.open(copy, 'wb'))
        output:write(input:read('a'))
        input:close() output:close()
        os.remove(copies .. name .. '-' .. (thin_reloads - 1) .. '.png')
        path = copy
    end
    return {handles = dfhack.textures.loadTileset(path, 32, 32, true),
            at = dofile(art_dir .. 'falling/' .. name .. '.lua').at, texpos = {}}
end

-- The thin version of a full piece for map tile (x, y, z) with `amount` snow, or the piece itself.
local function is_inside(texpos)
    local cell = piece_cell[texpos]
    if not thin_layout then thin_layout = dofile(art_dir .. 'snow_thin_sheet.lua') end
    return cell and thin_layout.inside_cells[cell]
end
local function thin_version(texpos, x, y, z, amount)
    local cell = piece_cell[texpos]
    if not cell then return texpos end
    if not thin_layout then thin_layout = dofile(art_dir .. 'snow_thin_sheet.lua') end
    -- (or sheets from before the art was packed, in a game running since: they have no index)
    if not thin_art or not thin_art.pieces.at then
        thin_art = {pieces = load_thin_sheet('snow_thin'), inside = load_thin_sheet('snow_thin_inside')}
    end
    local t = thin_layout
    local r = t.repeat_tiles
    local block = (y % r) * r + x % r
    local art, index
    if t.inside_cells[cell] and z then
        local now, levels, edge = clock_ms(), t.levels, t.edge_level
        local combo = ((corner_level(x, y, z, edge, now) * levels + corner_level(x + 1, y, z, edge, now)) * levels
            + corner_level(x, y + 1, z, edge, now)) * levels + corner_level(x + 1, y + 1, z, edge, now)
        local variant = math.floor(lattice(x, y, 9) * t.inside_variants) % t.inside_variants
        art, index = thin_art.inside, (combo * t.inside_variants + variant) * r * r + block + 1
    else
        local column = t.cells[cell]
        if not column then return texpos end
        local variant = math.floor(lattice(x, y, 9) * t.variants) % t.variants
        local row = (level_for(amount or SNOWY, x, y) * t.variants + variant) * r * r + block
        art, index = thin_art.pieces, row * t.columns + column + 1
    end
    local thin = art.texpos[index]
    if not thin then
        local handle = art.handles[art.at[index] or 0]
        thin = handle and dfhack.textures.getTexposByHandle(handle) or texpos
        art.texpos[index] = thin
        -- (STILL OURS: only a piece made here; with no art it's the game's own piece, which isn't)
        if handle then made[thin], snow_made[thin] = true, true end
    end
    return thin
end


-- A thin piece for (x, y) that thickens to the full piece towards neighbours with full snow, so
-- thin snow beside full snow has no edge: within THIN_FADE px of such a side each pixel takes the
-- full piece's, dithered so the change has no line. Baked per piece, place and set of full sides,
-- and cached; until it's baked the plain thin piece is used.
thin_faded = thin_faded or {}
function thin_beside_full(full, x, y, z, amount, full_sides, state)
    -- the inside piece goes by its corners, which join it to full snow beside it already; an edge
    -- piece at full snow is this mod's full cover too (the game's has one edge shape, so a long
    -- edge of it ran straight, and vanilla's body), with nothing to fade towards
    if is_inside(full) or amount >= 255 then return thin_version(full, x, y, z, amount) end
    local thin = thin_version(full, x, y, z, amount)
    if thin == full then return full end
    return bake_fade(thin, full, full_sides, state) or thin
end

-- (NATIVE SNOW, grungeisdead's copy, 2026-11-18) The fade itself, split out of thin_beside_full so the
-- native drawing hook can ask for one too (BAKES FOR THE DLL): thin piece `thin` thickening to full
-- piece `full` towards the sides in `full_sides` (a set of 'N', 'S', 'W', 'E'). Baked once per thin
-- piece and set of sides, and cached; nil until it's baked (or if it can't be), and with no full side
-- the thin piece itself.
function bake_fade(thin, full, full_sides, state)
    local sides = ''
    for _, side in ipairs({'N', 'S', 'W', 'E'}) do if full_sides[side] then sides = sides .. side end end
    if sides == '' then return thin end
    local key = thin .. ':' .. sides
    local entry = thin_faded[key]
    if entry == nil then
        if state.budget <= 0 then return nil end
        state.budget = state.budget - 1
        local thin_px, full_px = grass.pixels_of(thin), grass.pixels_of(full)
        if not (thin_px and full_px) then thin_faded[key] = false return nil end
        local out = {}
        for py = 0, 31 do
            for px = 0, 31 do
                local n = py * 32 + px + 1
                local reach = math.huge
                if full_sides.N then reach = math.min(reach, py) end
                if full_sides.S then reach = math.min(reach, 31 - py) end
                if full_sides.W then reach = math.min(reach, px) end
                if full_sides.E then reach = math.min(reach, 31 - px) end
                local dither = ((n * 2654435761) % 1000) / 1000
                local p = (reach + 0.5) / THIN_FADE < dither * 0.6 + 0.4 and full_px[n] or thin_px[n]
                out[n] = (p[4] << 24) | (p[3] << 16) | (p[2] << 8) | p[1]
            end
        end
        entry = {texpos = dfhack.textures.getTexposByHandle(dfhack.textures.createTile(out, 32, 32))}
        made[entry.texpos], snow_made[entry.texpos] = true, true   -- (STILL OURS)
        thin_faded[key] = entry
    end
    return entry and entry.texpos or nil
end

-- The edge art for every edging ID: grass (grass.find_edge_art) and the ground's own edges,
-- which come in the same 3x3 layout (SAND_FLOOR_1-9 and so on). Edging IDs as the game keeps them
-- in floor_flag, read in this fort: 2 dirt, 7 sand (soil that's sand), 8 pebbles, 9 stone floor.
local GROUND_EDGE_IDS = {DIRT_FLOOR = 2, SAND_FLOOR = 7, PEBBLES_FLOOR = 8, STONE_FLOOR = 9}
-- EDGE ART ONCE A WORLD (grungeisdead's copy, 2026-11-20, test 15Z). Every graphics file of every active mod
-- is read twice for this (grass.find_edge_art, then the ground's edges below; grass.lua puts one such read
-- at about 200 ms), and the snow's start, the murky water's start and frost each asked for it again, all
-- in the first frames after a load (15Y's report: a 2.4 s frame there). It's read once a world now and
-- kept (its readers only read it), and let go with the world (onStateChange below), as the texture numbers go.
edge_art_world = edge_art_world or nil
dfhack.onStateChange.detailed_weather_edge_art = function(event)
    if event == SC_WORLD_UNLOADED or event == SC_MAP_UNLOADED then edge_art_world, edge_art = nil, nil end
end
function all_edge_art()
    if edge_art_world then return edge_art_world end
    local edges = grass.find_edge_art()
    for _, mod in ipairs(require('script-manager').get_active_mods()) do
        for _, path in ipairs(grass.graphics_files(mod.path)) do
            local file = io.open(path, 'r')
            local text = file and file:read('a') or ''
            if file then file:close() end
            for page, x, y, family, n in text:gmatch('%[TILE_GRAPHICS:([%w_]+):(%d+):(%d+):(%u+_FLOOR)_(%d)%]') do
                local id = GROUND_EDGE_IDS[family]
                if id then
                    edges[id] = edges[id] or {}
                    for name, cell in pairs(grass.GENERIC_PIECE) do
                        if cell == tonumber(n) then edges[id][name] = grass.page_texpos(page, tonumber(x), tonumber(y)) end
                    end
                end
            end
        end
    end
    edge_art_world = edges
    return edges
end

-- A snow piece with something painted over it (fallen fruit under a sapling): one texture for the
-- spatter slot, which only holds one. Cached per pair.
-- texpos of every texture made here, so it isn't taken for fruit. STILL OURS (grungeisdead's copy,
-- 2026-11-17): only the pieces painted over fruit were in it, so a cell still showing one of the
-- snow's thin pieces (the game doesn't redraw every cell every frame) was planned as fruit lying on
-- the snow. Every texture made here is in it now, and it's how the drawing knows its own.
snow_made = snow_made or {}
local with_cache = {}
function snow_with(snow, top, state)
    local key = snow .. ':' .. top
    local entry = with_cache[key]
    if entry == nil then
        if state.budget <= 0 then return nil end
        state.budget = state.budget - 1
        local base, over = grass.pixels_of(snow), grass.pixels_of(top)
        if not (base and over) then with_cache[key] = false return nil end
        local out = {}
        for n = 1, 32 * 32 do
            local b, t = base[n], over[n]
            local ta, ba = t[4] / 255, b[4] / 255
            local a = ta + ba * (1 - ta)
            if a <= 0 then
                out[n] = 0
            else
                local c = {}
                for k = 1, 3 do c[k] = math.floor((t[k] * ta + b[k] * ba * (1 - ta)) / a + 0.5) end
                out[n] = (math.floor(a * 255 + 0.5) << 24) | (c[3] << 16) | (c[2] << 8) | c[1]
            end
        end
        entry = dfhack.textures.getTexposByHandle(dfhack.textures.createTile(out, 32, 32))
        with_cache[key] = entry
        snow_made[entry] = true
        made[entry] = true
    end
    return entry or nil
end

-- A snowy version of a set of grass edge pieces: their shape, filled with snow and lit.
edge_art = edge_art or nil
snowy_overhangs = snowy_overhangs or {}   -- key -> {handle, texpos} or false
-- every snowy edge texpos, so frost (drawn after) can put its rime under one rather than skip
snowy_edge_texpos = snowy_edge_texpos or {}

-- SNOWY EDGES KEPT (grungeisdead's copy, 2026-11-18). A snowy edge is baked the first time a cell needs
-- it, and an area's edges drew in visibly while they baked (test 4B: 1477 bakes in a session, a few a
-- frame). Every one baked is now written to a file outside the mod's folder (clearing the mod cache
-- leaves it), named by its pieces' edging IDs and piece names, which hold from one session to the
-- next (texture numbers don't). At start every one already in the file is made again at once and
-- handed to the native hook, so an area seen once has its edges ready ever after. Delete the file to
-- have them all baked afresh (after changing the edge art or the snow page, say).
-- Each record: the pieces' names ('10.N,13.NE'), as a 2-byte length and the text, then the 1024
-- pixels as 4-byte whole numbers, little-endian, as createTile takes them.
local EDGES_FILE = dfhack.getDFPath() .. '/dfhack-config/detailed_weather_snowy_edges.bin'
edge_piece_name = edge_piece_name or nil   -- texpos -> 'id.name', from edge_art
local function name_edge_pieces()
    edge_piece_name = {}
    for id, pieces in pairs(edge_art or {}) do
        for name, texpos in pairs(pieces) do
            if texpos and not edge_piece_name[texpos] then edge_piece_name[texpos] = id .. '.' .. name end
        end
    end
end

-- The native hook's key for a snowy edge of these pieces, in this order (detailed_weather_dll.cpp:
-- edge_key, FNV-1a over the texture numbers; Lua's whole numbers wrap as the DLL's do).
local function native_edge_key(pieces)
    local h = 1469598103934665603
    for _, texpos in ipairs(pieces) do h = (h ~ (texpos & 0xffffffff)) * 1099511628211 end
    return (3 << 60) | (h & 0x0fffffffffffffff)
end

-- A newly baked snowy edge, added to the file (nothing if a piece isn't edge art: no name for it).
local function keep_snowy_edge(pieces, out)
    if not edge_piece_name then
        if not edge_art then return end
        name_edge_pieces()
    end
    local names = {}
    for k, texpos in ipairs(pieces) do
        names[k] = edge_piece_name[texpos]
        if not names[k] then return end
    end
    local file = io.open(EDGES_FILE, 'ab')
    if not file then return end
    local parts = {string.pack('<s2', table.concat(names, ','))}
    for n = 1, 1024, 256 do parts[#parts + 1] = string.pack('<' .. ('I4'):rep(256), table.unpack(out, n, n + 255)) end
    file:write(table.concat(parts))
    file:close()
end

-- SNOWY EDGES KEPT, MADE WHEN FIRST NEEDED (grungeisdead's copy, 2026-11-19). The snowy edges kept
-- from earlier sessions were all made again at start (some 3941, a createTile and the pixels read for
-- each): a pause of about 1.6 s on every load. Now the file is only read through at start for where
-- each edge's pixels are (those whose pieces are all in this session's edge art), and an edge is made
-- from them the first time it's asked for (snowy_overhang): no bake, a read and a createTile.
kept_edges = kept_edges or nil   -- key -> where its pixels start in EDGES_FILE (0-based); made: removed
local kept_data = nil            -- the file read at start, kept only while the single pieces are made

-- Reads the file through for where each kept edge is. Returns how many of more than one piece.
local function index_snowy_edges()
    local found, several = {}, 0
    kept_edges = found
    local file = io.open(EDGES_FILE, 'rb')
    if not file then return 0 end
    local data = file:read('a')
    file:close()
    if not edge_piece_name then name_edge_pieces() end
    local by_name = {}
    for texpos, name in pairs(edge_piece_name) do by_name[name] = texpos end
    local at, size = 1, #data
    while at <= size do
        local ok, names, px_at = pcall(string.unpack, '<s2', data, at)
        if not ok or px_at + 4095 > size then break end   -- (a record cut short: the rest is left)
        at = px_at + 4096
        local pieces = {}
        for name in names:gmatch('[^,]+') do
            local texpos = by_name[name]
            if not texpos then pieces = nil break end
            pieces[#pieces + 1] = texpos
        end
        local key = pieces and table.concat(pieces, ':')
        if key and snowy_overhangs[key] == nil and not found[key] then
            found[key] = px_at - 1
            if #pieces > 1 then several = several + 1 end
        end
    end
    kept_data = data
    return several
end

-- The kept snowy edge under this key, made now ({handle}), or nil if none is kept.
local function kept_snowy_edge(key)
    local offset = kept_edges and kept_edges[key]
    if not offset then return nil end
    kept_edges[key] = nil
    local bytes = kept_data and kept_data:sub(offset + 1, offset + 4096)
    if not bytes then
        local file = io.open(EDGES_FILE, 'rb')
        if not file then return nil end
        file:seek('set', offset)
        bytes = file:read(4096)
        file:close()
    end
    if not bytes or #bytes < 4096 then return nil end
    local px = {}
    for n = 0, 3 do
        local values = {string.unpack('<' .. ('I4'):rep(256), bytes, 1 + n * 1024)}
        for k = 1, 256 do px[n * 256 + k] = values[k] end
    end
    local entry = {handle = dfhack.textures.createTile(px, 32, 32)}
    snowy_overhangs[key] = entry
    return entry
end
function snowy_overhang(key, pieces, state)
    local entry = snowy_overhangs[key]
    if entry == nil then entry = kept_snowy_edge(key) end   -- (KEPT, MADE WHEN FIRST NEEDED: no budget spent)
    if entry == nil then
        if state.budget <= 0 then return nil end
        state.budget = state.budget - 1
        if not piece_sides then find_snow_pieces() end
        local fill = grass.pixels_of(pieces_for.NSWE and pieces_for.NSWE[1])   -- plain snow
        local alpha = {}
        for n = 1, 32 * 32 do alpha[n] = 0 end
        for _, texpos in ipairs(pieces) do
            local px = grass.pixels_of(texpos)
            if px then for n, p in ipairs(px) do if p[4] > alpha[n] then alpha[n] = p[4] end end end
        end
        local out = {}
        for y = 0, 31 do
            for x = 0, 31 do
                local n = y * 32 + x + 1
                if alpha[n] == 0 or not fill then
                    out[n] = 0
                else
                    local f = fill[n]
                    local r, g, b = f[1], f[2], f[3]
                    local open_below = y == 31 or alpha[n + 32] == 0
                    local open_above = y == 0 or alpha[n - 32] == 0
                    local towards, amount = nil, 0
                    if open_below then towards, amount = SNOW_LIP, 0.7
                    elseif open_above then towards, amount = SNOW_RIM, 0.5 end
                    if towards then
                        r, g, b = r + (towards[1] - r) * amount, g + (towards[2] - g) * amount, b + (towards[3] - b) * amount
                    end
                    out[n] = (alpha[n] << 24) | (math.floor(b + 0.5) << 16) | (math.floor(g + 0.5) << 8) | math.floor(r + 0.5)
                end
            end
        end
        keep_snowy_edge(pieces, out)   -- (SNOWY EDGES KEPT)
        entry = {handle = dfhack.textures.createTile(out, 32, 32)}
        snowy_overhangs[key] = entry
    end
    if not entry then return nil end
    if not entry.texpos then entry.texpos = dfhack.textures.getTexposByHandle(entry.handle) end
    snowy_edge_texpos[entry.texpos] = true
    made[entry.texpos], snow_made[entry.texpos] = true, true   -- (STILL OURS)
    return entry.texpos
end

----------------------------------------------------------------------------------------------
-- NATIVE SNOW: the drawing done by the native hook (grungeisdead's copy, 2026-11-18)
----------------------------------------------------------------------------------------------
-- All of this file's drawing can be done by Detailed Weather's native drawing hook instead
-- (dfhooks_detailed_weather.dll, detailed_weather_dll.cpp): every frame it works out every tile in
-- view from the map, on every level shown, by these same rules (snowy ramps, snowy floors and their
-- thin snow, joins, skirts and overhangs, snowy edges and corners, trunks, what lies on the snow),
-- writes them at the last moment before the game reads the screen, and puts the game's own drawing
-- back before the game draws again. While native_snow is true, plan() works nothing out and apply()
-- only bakes the textures the DLL asks for (BAKES FOR THE DLL, below). detailed_weather_hook_test
-- turns it on and off, and hands the DLL native_tables().
native_snow = native_snow or false
native_block = native_block or nil   -- the DLL's block (detailed_weather_hook_test sets it)
native_kept = native_kept or nil     -- (SNOWY EDGES KEPT) edges made again at start, still to hand over

-- Everything the DLL is handed, from this file's own art and tables (the ones its drawing uses):
--   ramps[byte]      the snowy ramp texture for each walls byte (WHICH CELL), or 0
--   full[k]          the snow page's FULL pieces in FULL_PIECES' order: {texpos, sides, cell}, sides
--                    in floor_flag's byte order as bits: S 1, W 2, E 4, N 8
--   pieces[mask]     for each set of sides (as that mask), the FULL pieces joined on exactly them, in
--                    order (piece_joined_on chooses among them by place)
--   page             every texture on the snow page (the game's own snow pieces)
--   thin, inside     art/snow_thin.png's and art/snow_thin_inside.png's textures in order, and their
--   layout           layout (art/snow_thin_sheet.lua)
--   edges[id][name]  the edge art (all_edge_art), by edging ID and piece name
--   plant_edging[i]  each plant's grass edging ID, as read_info works it out (CUSTOM_EDGING + 9, else 1)
--   made             every texture this file has made (snow_made): the DLL counts them as its own
function native_tables(bakes_here)
    if not art then load_art() end
    if not cell_of_byte then cell_of_byte = cell_table() end
    if not piece_sides then find_snow_pieces() end
    if not thin_layout then thin_layout = dofile(art_dir .. 'snow_thin_sheet.lua') end
    if not thin_art or not thin_art.pieces.at then
        thin_art = {pieces = load_thin_sheet('snow_thin'), inside = load_thin_sheet('snow_thin_inside')}
    end
    if not edge_art then edge_art = all_edge_art() end
    local t = {ramps = {}, full = {}, pieces = {}, page = {}, thin = {}, inside = {}, edges = edge_art,
               layout = thin_layout, plant_edging = {}, made = {}}
    for byte = 0, 255 do t.ramps[byte] = snowy_texpos(cell_of_byte[byte], frame_number) or 0 end
    local SIDE_BIT = {S = 1, W = 2, E = 4, N = 8}
    for _, page in ipairs(df.global.texture.page) do
        if page.token == SNOW_PAGE then
            for _, texpos in ipairs(page.texpos) do t.page[#t.page + 1] = texpos end
            for _, piece in ipairs(FULL_PIECES) do
                local mask = 0
                for side in piece[1]:gmatch('%u') do mask = mask | SIDE_BIT[side] end
                t.full[#t.full + 1] = {texpos = page.texpos[piece[3] * page.page_dim_x + piece[2]],
                                       sides = mask, cell = piece[3] * SNOW_PAGE_WIDTH + piece[2]}
            end
        end
    end
    for mask = 0, 15 do
        local key = ''   -- piece_joined_on's order: N, S, W, E
        if mask & 8 ~= 0 then key = key .. 'N' end
        if mask & 1 ~= 0 then key = key .. 'S' end
        if mask & 2 ~= 0 then key = key .. 'W' end
        if mask & 4 ~= 0 then key = key .. 'E' end
        t.pieces[mask] = pieces_for[key] or {}
    end
    -- every thin piece is the DLL's to use, so all are this file's own from now on (STILL OURS)
    for _, sheet in ipairs({{thin_art.pieces, t.thin}, {thin_art.inside, t.inside}}) do
        -- (the sheets are packed, each different tile once: the DLL's tables are by the tile's number
        -- as drawn, so each number is given its tile's texture through the sheet's index)
        for n, place in ipairs(sheet[1].at) do
            local handle = sheet[1].handles[place]
            local texpos = handle and dfhack.textures.getTexposByHandle(handle)
            sheet[2][n] = texpos or 0
            if texpos then made[texpos], snow_made[texpos] = true, true end
        end
    end
    for index, plant in ipairs(df.global.world.raws.plants.all) do
        local custom = plant.texpos[5]   -- its CUSTOM_EDGING minus one, or -1
        t.plant_edging[index] = custom >= 0 and custom + 10 or 1
    end
    for texpos in pairs(snow_made) do t.made[#t.made + 1] = texpos end
    -- SNOWY EDGES AT ONCE (grungeisdead's copy, 2026-11-18): every edge piece's snowy version, baked now
    -- (at most 8 for each edging ID). A cell's snowy edge of one piece, most of them, then needs no
    -- bake at all, and one of several pieces stands in until their bake comes back. Waiting on every
    -- edge's bake at 6 a frame made each new area's edges draw in visibly (test 4: 1993 bakes asked,
    -- the ring full 8452 times).
    -- (SNOWY EDGES KEPT) those baked in earlier sessions found first, so these are mostly made from the
    -- file rather than baked; the rest of the kept edges are made when first asked for
    name_edge_pieces()
    native_kept = nil
    -- (THE SNOW'S BAKES HERE, grungeisdead's copy, 2026-11-20, test 15Z) with `bakes_here` the DLL paints each
    -- snowy edge in its hook the moment one is wanted (detailed_weather_dll.cpp: bake_here), so none is baked
    -- or read back from the kept file here: that was most of the rest of the snow's start. This file bakes
    -- one only when the DLL asks (no blank ready there), as before.
    t.edges_snowy = {}
    if bakes_here then
        t.edges_kept = 0
        return t
    end
    t.edges_kept = index_snowy_edges()
    local all = {budget = math.huge}
    for id, pieces in pairs(edge_art) do
        local row = {}
        for name, texpos in pairs(pieces) do
            if texpos then row[name] = snowy_overhang(tostring(texpos), {texpos}, all) end
        end
        t.edges_snowy[id] = row
    end
    kept_data = nil   -- (from now on an edge's pixels are read from the file when it's first asked for)
    return t
end

-- BAKES FOR THE DLL. Three of the snow's textures need createTile, which only Lua can call: thin snow
-- faded towards full snow (bake_fade), a snow piece with something painted over it (snow_with), and a
-- snowy edge (snowy_overhang). The DLL asks for them in a ring of requests in its block and takes them
-- back from a ring of results (detailed_weather_dll.cpp: THE BAKE RINGS; the offsets below are the
-- same). They're served here, a few a frame, from apply(), on the game thread; the DLL fills the ring
-- in its hook on the main thread, and the game runs the two in turn, never at once. Until a bake comes
-- back the DLL draws what this file drew until its own bakes were done: the plain thin piece, the snow
-- piece without what lies on it, no edge. A bake that can't be made comes back as 0, and the DLL keeps
-- drawing that fallback.
local NATIVE_RINGS = {req_head = 496, req_tail = 500, res_head = 504, res_tail = 508,
                      req = 512, res = 16896, slots = 256, req_size = 64, res_size = 16}
local NATIVE_BAKE_MS = 3   -- new bakes take about this long a frame at most; the rest wait their turn
local FADE_SIDE_BITS = {{1, 'S'}, {2, 'W'}, {4, 'E'}, {8, 'N'}}
local function peek(t, a) return df.reinterpret_cast(t, a).value end
local function poke(t, a, v) df.reinterpret_cast(t, a).value = v end
function serve_native_bakes()
    local base = native_block
    if not base then return end
    local R = NATIVE_RINGS
    -- (by time, not count: 6 a frame left new areas' edges drawing in. clock_s() is wall time in ms
    -- steps on Windows, grass.lua: THE CLOCK)
    -- (SNOWY EDGES KEPT) the edges made again at start handed over first, as results nothing asked for
    -- (the DLL keeps them as if it had asked), as many as the results ring has room for each frame
    local kept = native_kept
    while kept and kept.next <= #kept.list do
        local res_head = peek('uint32_t', base + R.res_head)
        if ((res_head - peek('uint32_t', base + R.res_tail)) & 0xffffffff) >= R.slots then break end
        local item = kept.list[kept.next]
        local out = base + R.res + (res_head % R.slots) * R.res_size
        poke('uint64_t', out, item[1])
        poke('int32_t', out + 8, item[2])
        poke('uint32_t', base + R.res_head, (res_head + 1) & 0xffffffff)
        kept.next = kept.next + 1
    end
    local state = {budget = math.huge}
    local started = clock_s()
    local head, tail = peek('uint32_t', base + R.req_head), peek('uint32_t', base + R.req_tail)
    while tail ~= head and clock_s() - started < NATIVE_BAKE_MS / 1000 do
        -- (the results ring full: the rest waits for the DLL to take what's there)
        local res_head = peek('uint32_t', base + R.res_head)
        if ((res_head - peek('uint32_t', base + R.res_tail)) & 0xffffffff) >= R.slots then break end
        local at = base + R.req + (tail % R.slots) * R.req_size
        local kind, n = peek('uint32_t', at), peek('uint32_t', at + 4)
        local a, b, c = peek('int32_t', at + 8), peek('int32_t', at + 12), peek('int32_t', at + 16)
        local texpos
        if kind == 1 then            -- a fade: thin piece a towards full piece b on sides c
            local sides = {}
            for _, bit in ipairs(FADE_SIDE_BITS) do if c & bit[1] ~= 0 then sides[bit[2]] = true end end
            texpos = bake_fade(a, b, sides, state)
        elseif kind == 2 then        -- snow piece a with b painted over it
            texpos = snow_with(a, b, state)
        elseif kind == 3 then        -- a snowy edge from the n edge pieces listed
            local pieces = {}
            for k = 0, math.min(n, 8) - 1 do pieces[#pieces + 1] = peek('int32_t', at + 32 + k * 4) end
            texpos = snowy_overhang(table.concat(pieces, ':'), pieces, state)
        end
        local out = base + R.res + (res_head % R.slots) * R.res_size
        poke('uint64_t', out, peek('uint64_t', at + 24))   -- the request's key
        poke('int32_t', out + 8, texpos or 0)
        poke('uint32_t', base + R.res_head, (res_head + 1) & 0xffffffff)
        tail = (tail + 1) & 0xffffffff
        poke('uint32_t', base + R.req_tail, tail)
    end
end

----------------------------------------------------------------------------------------------
-- Planning and drawing
----------------------------------------------------------------------------------------------

local WATER = 6
local EMPTY, RAMP_TOP, RAMP = df.tiletype_shape.EMPTY, df.tiletype_shape.RAMP_TOP, df.tiletype_shape.RAMP
local WALL = df.tiletype_shape.WALL
local FLOOR_LIKE = df.tiletype_shape_basic.Floor
local shape_of, floor_like, tree_wall = {}, {}, {}   -- by tiletype; df.tiletype.attrs costs ~40 us a lookup
local tree_part = {}   -- (TREES) by tiletype: any part of a tree (trunk, branch, twig)
local function shape(tiletype)
    local s = shape_of[tiletype]
    if not s then
        local attrs = df.tiletype.attrs[tiletype]
        s = attrs.shape
        shape_of[tiletype] = s
        floor_like[tiletype] = df.tiletype_shape.attrs[s].basic_shape == FLOOR_LIKE
        tree_wall[tiletype] = s == df.tiletype_shape.WALL and attrs.material == df.tiletype_material.TREE
        tree_part[tiletype] = attrs.material == df.tiletype_material.TREE
    end
    return s
end
-- (TREES) whether a tile type (or nil, off the map) is any part of a tree
local function tree_tile(tiletype)
    if tiletype == nil then return false end
    shape(tiletype)
    return tree_part[tiletype]
end
-- a tree's trunk
local function trunk(tiletype)
    shape(tiletype)
    return tree_wall[tiletype]
end

-- BLOCKS READ IN ONE COPY (grungeisdead's copy, 2026-11-17). Working a tile out read its tile type,
-- its outside flag and its neighbours' types through DFHack one at a time, and the grass edging by
-- walking all of the block's events, for the tile and its corners: a few hundred tiles a frame at
-- most, so a first load, a new level, or what a pan or zoom brought in filled in over many frames
-- (seen in play: blank rectangles filling in after a zoom out). Now each block's 256 tile types and
-- designation flags are copied out with one memmove each (map_block.tiletype, uint16 [16][16];
-- .designation, uint32 [16][16]: df-structures, df.block.xml) into plain Lua tables, with the grass
-- edging of its grass tiles worked out the way grass.lua's grass_edging does (of the grass events,
-- the first with the most there; its plant's custom edging + 10, else 1), and kept BLOCK_KEEP_MS.
-- A tile whose drawing goes stale (the game changed it) has its block read again at once.
local BLOCK_KEEP_MS = 4000
local BLOCK_INFO_MOST = 1500   -- blocks kept (about 12 KB each); past this the copies start afresh
block_info = block_info or {}   -- block key -> {types, outside, edging, due}, by index (x % 16) * 16 + y % 16
block_info_count = block_info_count or 0
local types_buf, flags_buf, amount_buf   -- scratch copies, made once
local grassy_type = {}   -- tiletype -> whether it's grass, GRASS_LIGHT or GRASS_DARK (as grass_edging)
local plant_edging = {}  -- plant raw index -> its grass's edging id, or false
local GRASS_LIGHT, GRASS_DARK = df.tiletype_material.GRASS_LIGHT, df.tiletype_material.GRASS_DARK
local OUTSIDE_BIT = 1 << 16   -- tile_designation's outside (df-structures, df.d_basics.xml)
local function info_key(x, y, z) return ((z * 1024) + x // 16) * 1024 + (y // 16) end

local function read_info(block, now)
    types_buf = types_buf or df.new('uint16_t', 256)
    flags_buf = flags_buf or df.new('uint32_t', 256)
    amount_buf = amount_buf or df.new('uint8_t', 256)
    local _, types_at = df.sizeof(block:_field('tiletype'))
    dfhack.internal.memmove(types_buf, types_at, 512)
    local _, flags_at = df.sizeof(block:_field('designation'))
    dfhack.internal.memmove(flags_buf, flags_at, 1024)
    local types, outside, grassy = {}, {}, nil
    for i = 0, 255 do
        local t = types_buf[i]
        types[i] = t
        outside[i] = flags_buf[i] & OUTSIDE_BIT ~= 0
        local g = grassy_type[t]
        if g == nil then
            local material = df.tiletype.attrs[t].material
            g = material == GRASS_LIGHT or material == GRASS_DARK
            grassy_type[t] = g
        end
        if g then
            grassy = grassy or {}
            grassy[#grassy + 1] = i
        end
    end
    -- each grass tile's edging: the grass with the most there
    local edging = {}
    if grassy then
        local best_amount, best_plant = {}, {}
        for _, event in ipairs(block.block_events) do
            if df.block_square_event_grassst:is_instance(event) then
                local _, amount_at = df.sizeof(event:_field('amount'))
                dfhack.internal.memmove(amount_buf, amount_at, 256)
                local plant = event.plant_index
                for _, i in ipairs(grassy) do
                    local a = amount_buf[i]
                    if a > (best_amount[i] or 0) then best_amount[i], best_plant[i] = a, plant end
                end
            end
        end
        for _, i in ipairs(grassy) do
            local plant, id = best_plant[i], false
            if plant then
                id = plant_edging[plant]
                if id == nil then
                    local raw = df.global.world.raws.plants.all[plant]
                    id = false
                    if raw then
                        local custom = raw.texpos[5]   -- its CUSTOM_EDGING minus one, or -1
                        id = custom >= 0 and custom + 10 or 1
                    end
                    plant_edging[plant] = id
                end
            end
            edging[i] = id
        end
    end
    return {types = types, outside = outside, edging = edging,
            due = now + BLOCK_KEEP_MS + math.random(0, BLOCK_KEEP_MS // 2)}
end

-- The copy of the block holding (x, y, z), read again when it's old; nil off the map.
local function info_at(x, y, z, now)
    local key = info_key(x, y, z)
    local info = block_info[key]
    if not info or now >= info.due then
        local block = grass.block_at(x, y, z)
        if not block then return nil end
        if not info then
            if block_info_count >= BLOCK_INFO_MOST then block_info, block_info_count = {}, 0 end
            block_info_count = block_info_count + 1
        end
        info = read_info(block, now)
        block_info[key] = info
    end
    return info
end

-- The index of map tile (x, y) in a screen buffer, or nil if it's outside it. The buffers are
-- raw memory with no bounds checks, and they're reallocated at a new size when the view is zoomed
-- or the window resized, so every read and write goes through this.
local function screen_index(port, viewport, x, y)
    local sx, sy = x - viewport.x1, y - viewport.y1
    if sx < 0 or sy < 0 or sx >= port.dim_x or sy >= port.dim_y then return nil end
    return sx * port.dim_y + sy
end

local function viewport_at(depth)
    return depth == 0 and df.global.gps.main_viewport or df.global.gps.lower_viewport[depth - 1]
end

remembered = remembered or {}
remembered_count = remembered_count or 0
frame_number = frame_number or 0
timing = timing or {plan = 0, apply = 0}

-- UNDRAWN CELLS (grungeisdead's copy, 2026-11-17). For a frame or so after the view moves (a pan, a
-- zoom, a change of level) the game hasn't drawn all of the new view yet: such a cell's background
-- is the game's black (gps.black_background_texpos[0], as frost.lua found), and on the frame of the
-- move a level below can still hold the old view's drawing. Every record on such a cell disagreed
-- with the screen and was let go, then was worked out again from the blank cell, where a snowy tile
-- came out with nothing to draw and stayed so until the rechecks came round, 30 tiles a frame: the
-- whole view's snow redrawn slowly after every move. Now such cells are left as they are for the
-- frame, and no tile is worked out from one.
-- STILL OURS (grungeisdead's copy, 2026-11-17). The game doesn't redraw every cell every frame: one it
-- leaves still shows what Detailed Weather drew there before (colour.lua and frost.lua allow for it).
-- The check against the screen took the snow's own drawing for a change and let the record go, and
-- the tile was worked out again from that drawing, wrongly (its thin pieces taken for fruit and lifted
-- over the snow, or nothing to draw). The next pan, zoom or change of level, when the game redraws
-- every cell, then failed every such record, and the view's snow was redrawn slowly (detailed_weather
-- details: 36521 records let go in 6094 frames, with the view moved 30 times). Now the snow's own
-- drawing counts as drawn, another Detailed Weather texture there is left for the frame, and no tile
-- is worked out from either (HELD).
counts = counts or {}   -- what was kept and let go, since `detailed_weather details` last showed it
local function count(what) counts[what] = (counts[what] or 0) + 1 end

-- SNOWSHOT (a diagnostic, grungeisdead's copy, 2026-11-17). `detailed_weather snowshot` arms it, and the
-- SHOT_FRAMES frames from the next one the view moves in are written to detailed_weather_snowshot_N.txt
-- in DF's folder: a map of the view for each frame, a character a tile, saying what the snow did there
-- (the legend is written at the top of the file). The drawn floors at the view's level are checked
-- the next frame against the finished frame, read from the game's _old copy of the spatter layer (the
-- game swaps each buffer with its _old twin every frame): '#' where the game drew over the snow after
-- its turn. Records made at the view's edge are marked, to see whether they're the strips.
local SHOT_FRAMES = 90   -- (SHORTER SHOTS: 24 before, under a second; this is about 3 s at 30 frames a second)
local SHOT_LEGEND = [[
Detailed Weather snowshot: what the snow did on each tile, frame by frame from a move of the view.
  '.' drawn                      ',' drawn, a record made at the view's edge
  ':' drawn, a record taken from another level (it shows the same ground from there)
  '#' drawn, but the finished frame showed something else there (the game drew after the snow)
  ' ' nothing to draw            '?' nothing kept for it yet (waiting to be worked out)
  'H' held: waiting for the game to draw its cell        'x' kept, but not in the list drawn
  'B' left for the frame: its cell not drawn yet (black)  'Z' left: its ground layer empty
  'O' left for the frame: another texture of Detailed Weather's there
  the screen disagreed with the record, on a frame the view moved (kept, not drawn):
      'f' floor flag   'p' floor piece   'e' edge flag   'r' ramp
  the screen disagreed with the record, on a frame it didn't move (let go): 'F' 'P' 'E' 'R'
]]
shot = shot or nil
shot_count = shot_count or 0
function arm_shot()
    shot = {frames = {}, started = false}
    print(('detailed_weather: snowshot armed. It records %d frames from the next move of the view (a pan, a zoom or a change of level), about 3 s.'):format(SHOT_FRAMES))
end
-- the value of one of a viewport's buffer pointers (which buffer it is this frame), or nil
local function pointer_of(port, name)
    local ok, slot = pcall(function() local _, at = df.sizeof(port:_field(name)) return at end)
    if ok and slot then return df.reinterpret_cast('uint64_t', slot).value end
end
-- the last shot frame's drawn floors against the finished frame: the game's _old copy of the spatter
-- layer now, if it's that frame's buffer
local function shot_check_last()
    local pending = shot.pending
    if not pending then return end
    shot.pending = nil
    local port = df.global.gps.main_viewport
    local frame = pending.frame
    if not pending.ptr or pointer_of(port, 'screentexpos_spatter_old') ~= pending.ptr then
        frame.finished = 'not readable (its buffer is not the _old one now)'
        return
    end
    local old = port.screentexpos_spatter_old
    local over = 0
    for _, c in ipairs(pending.cells) do
        if old[c.i] ~= c.j then
            local row = frame.map[c.y - frame.y1 + 1]
            if row then row[c.x - frame.x1 + 1] = '#' end
            over = over + 1
        end
    end
    frame.finished = ('read from _old: %d of %d drawn floors showed something else'):format(over, #pending.cells)
end
-- one shot frame: the view's map, a character a tile (status: what the drawing found, by tile key)
local function shot_frame(viewport, status, cells)
    local z = viewport.z
    local map_x, map_y = dfhack.maps.getTileSize()   -- (OFF THE MAP: nothing kept there; shown as nothing to draw)
    local map = {}
    for y = viewport.y1, viewport.y2 do
        local row = {}
        for x = viewport.x1, viewport.x2 do
            local key = (z * 4096 + x) * 4096 + y
            local c = status[key]
            if not c then
                local r = drawn[key]
                local off = x < 0 or y < 0 or x >= map_x or y >= map_y
                c = off and ' ' or r == nil and '?' or r == NOTHING_DRAWN and ' ' or r.held and 'H' or 'x'
            end
            row[#row + 1] = c
        end
        map[#map + 1] = row
    end
    local frame = {map = map, x1 = viewport.x1, y1 = viewport.y1, moved = frame_moved, finished = 'not read',
                   view = ('x %d..%d, y %d..%d, z %d'):format(viewport.x1, viewport.x2, viewport.y1, viewport.y2, z)}
    shot.frames[#shot.frames + 1] = frame
    shot.pending = {ptr = pointer_of(df.global.gps.main_viewport, 'screentexpos_spatter'), cells = cells, frame = frame}
end
local function shot_write()
    shot_count = shot_count + 1
    local path = dfhack.getDFPath() .. '/detailed_weather_snowshot_' .. shot_count .. '.txt'
    local f = io.open(path, 'w')
    if not f then
        print('detailed_weather: snowshot: could not write ' .. path)
        shot = nil
        return
    end
    f:write(SHOT_LEGEND)
    -- (SHORTER SHOTS, grungeisdead's copy, 2026-11-17) a frame whose map is the same as the one written before
    -- it, in the same view, is written as one line: a shot is long enough now for a few moves, and most of
    -- its frames, once a view has filled, are the same
    local last_text, last_view, last_n = nil, nil, nil
    for n, frame in ipairs(shot.frames) do
        local tally, lines = {}, {}
        for _, row in ipairs(frame.map) do
            for _, c in ipairs(row) do tally[c] = (tally[c] or 0) + 1 end
            lines[#lines + 1] = table.concat(row)
        end
        local parts = {}
        for c, k in pairs(tally) do parts[#parts + 1] = ("'%s' %d"):format(c, k) end
        table.sort(parts)
        local text = table.concat(lines, '\n')
        if text == last_text and frame.view == last_view and not frame.moved then
            f:write(('\nframe %d of %d: the same as frame %d; finished frame %s\n'):format(n, #shot.frames, last_n, frame.finished))
        else
            f:write(('\nframe %d of %d (the view moved this frame: %s), %s; finished frame %s\n  %s\n'):format(
                n, #shot.frames, frame.moved and 'yes' or 'no', frame.view, frame.finished, table.concat(parts, ', ')))
            f:write(text, '\n')
            last_text, last_view, last_n = text, frame.view, n
        end
    end
    f:close()
    print(('detailed_weather: snowshot: %d frames written to %s'):format(#shot.frames, path))
    shot = nil
end
frame_black = frame_black or 0         -- this frame's black (plan() reads it)
frame_moved = frame_moved or false     -- whether the view moved since the last frame (plan())
last_frame_view = last_frame_view or nil

function forget()
    grass.forget_snow()
    remembered, remembered_count = {}, 0
    drawn, drawn_count = {}, 0
    drawn_version, drawn_drops, known_view = drawn_version + 1, drawn_drops + 1, nil   -- (SNOWY TILES LISTED)
    -- the thin sheets stay loaded (load_thin_sheet); only where their textures are is asked again
    if thin_art then thin_art.pieces.texpos, thin_art.inside.texpos = {}, {} end
    thin_layout, thin_faded, corner_levels = nil, {}, {}
    block_info, block_info_count = {}, 0   -- (BLOCKS READ IN ONE COPY)
    if snowy_view then snowy_view.key = nil end   -- (FILL BY QUEUE: the view walked again)
    level_seen = {}   -- (LEVELS BY USE)
end

-- The snowy ramps shown in view, on this level or below through open space, and the snowy floors
-- with a skirt to clear: two lists.
-- What's drawn on each map tile is kept by its position (drawn[key]: the snowy ramp, the snowy
-- floor's changes, the snowy edges), so panning reuses it: each frame plan() works out, within
-- SLICE_MS, first the tiles in view it has nothing for (a newly shown strip), then refreshes the
-- rest a few at a time (REFRESH_PER_FRAME) in case the game changed something; with time to spare
-- it works out the map side of the tiles round the view (WARM_MARGIN), so they're ready when
-- panned to. apply() draws the view's tiles from what's kept.
local SLICE_MS = 1.5
local INLINE_PLAN_MS = 6   -- at most this long a frame planning tiles as they're drawn
local NEW_TILES_MS = 2   -- for a strip just panned into view (apply() plans the rest as it draws)
allowance = allowance or 1   -- the share of its usual time a frame (settings.lua: less at low)
local REFRESH_PER_FRAME = 30
-- (grungeisdead's copy, 2026-11-17) QUIET REFRESH: with no snow falling the snow only melts, which
-- the drawing sees as it happens (the game's piece changes under a record), so the refresh, there
-- for tiles that come to have snow, goes round this much slower
local REFRESH_QUIET_PER_FRAME = 6
-- NEW VIEW (grungeisdead's copy, 2026-11-17): for this many frames after the view moves, the tiles
-- new to it get more time and more working out a frame, so a new level, or what a pan or zoom brings
-- in, fills in within a few frames rather than many (a few heavier frames in place of watching it)
local NEW_VIEW_FRAMES = 8
local NEW_VIEW_TILES_MS = 12  -- in place of NEW_TILES_MS
local NEW_VIEW_INLINE_MS = 12 -- in place of INLINE_PLAN_MS
local NEW_VIEW_WORK = 2000    -- in place of WORK_PER_PLAN
new_view_left = new_view_left or 0
-- WHOLE LOAD (grungeisdead's copy, 2026-11-17): the larger budgets last until the new view's queue is worked
-- through, up to NEW_VIEW_MOST_FRAMES from the move, not a fixed NEW_VIEW_FRAMES (snowshot: a level's first
-- view filled at about 600 tiles a frame for 8 frames, then half that for the last third once they ran out),
-- and are half again larger (8 ms each before). A few heavier frames while a view first fills, rather than
-- watching it fill (grungeisdead: slower movement then is fine).
local NEW_VIEW_MOST_FRAMES = 40
new_view_age = new_view_age or 0   -- frames since the view last moved
-- TAKE TIME (grungeisdead's copy, 2026-11-17): the queue's first pass (TAKE FIRST: other levels' records) has
-- this long, in the plan and again as the snow is drawn, in place of the new view's 12 ms each. Taking is
-- a few lookups and a copy a tile, and it's what shows: with 12 ms it took two or three frames to bring a
-- level back (snowshot: 3 frames after a jump of two levels), and a fast scroll moved on first, so the
-- whole screen was seen to fill. About one frame now, at the cost of one or two heavier frames.
local TAKE_MS = 16
-- a frame's time for planning tiles as they're drawn
local function inline_ms()
    return (new_view_left > 0 and NEW_VIEW_INLINE_MS or INLINE_PLAN_MS) * allowance
end
-- COSTS (grungeisdead's copy, 2026-11-17): time spent working tiles out, for `detailed_weather
-- details`: plan_n tiles planned (plan_s seconds), of which work_n worked out from the map (work_s)
costs = costs or {plan_n = 0, plan_s = 0, work_n = 0, work_s = 0}
-- (LEVELS SHARED) tries at taking another level's record (adopt_tries), how many took one (adopt_n), and the
-- time all the tries took (adopt_s)
costs.adopt_tries, costs.adopt_n, costs.adopt_s = costs.adopt_tries or 0, costs.adopt_n or 0, costs.adopt_s or 0
local WARM_MARGIN = 24
local DRAWN_MOST = 200000   -- (as REMEMBER_MOST)
drawn = drawn or {}
drawn_count = drawn_count or 0
-- SNOWY TILES LISTED (grungeisdead's copy, 2026-11-17): bumped whenever a tile comes to have something
-- to draw or stops having it (or its record is let go), so apply() lists the view's tiles again
-- (snowy_list)
drawn_version = drawn_version or 0
drawn_drops = drawn_drops or 0   -- VIEW KNOWN: bumped whenever kept records are let go
known_view = known_view or nil   -- VIEW KNOWN: the view (and drops) whose tiles all have records (plan)
-- QUIET REFRESH: whether snow is falling anywhere on the map, and when that was last looked at
if snowing == nil then snowing = true end
weather_checked = weather_checked or 0
refresh_at = refresh_at or 0     -- the refresh cursor, through the tiles in view
warm_at = warm_at or 0           -- the warm-up cursor, through the margin round the view
NOTHING_DRAWN = NOTHING_DRAWN or {ramps = {}, floors = {}, edges = {}}
-- HELD (grungeisdead's copy, 2026-11-17): a tile with snow to draw whose cell wasn't the game's own
-- drawing when it was to be worked out (not drawn yet, a level below on the frame of a move, or still
-- showing what was drawn there before) is kept as {held = true, depth =, watch =}: listed, looked at
-- as it's drawn (one read of the layer its plan reads, `watch`), and worked out the frame the game
-- draws it. Before, it was worked out from whatever the cell showed.
-- Why a tile's cell, at index i of its level's layers, isn't the game's own drawing of the tile yet,
-- or nil when it is. watch: what the tile is, so what its plan reads ('ramp' the ground layer, 'floor'
-- and 'trunk' the spatter, 'bare' the layer above, 'branch' the spatter and the layer above (TREES),
-- 'open' none of them). A snowy floor whose snow piece
-- the game hasn't drawn yet, or a ramp or floor whose ground it hasn't, is held too (grungeisdead's
-- copy, 2026-11-17): worked out then, it came out with nothing to draw and stayed so until the refresh
-- came round, seconds at a wide zoom (seen in play: strips left plain, some of them for good).
local function not_drawn_why(watch, background, spatter, above, i)
    local bg = background[i]
    if bg == frame_black then return 'tiles left for a cell the game hadn\'t drawn yet' end
    if watch == 'open' then return nil end
    if watch == 'trunk' then
        local v = spatter[i]
        if v ~= 0 and made[v] then return 'tiles left: their cell still showed earlier drawing' end
        return nil
    end
    -- TREES (grungeisdead's copy, 2026-11-17): a tree's branch (df-structures: BRANCH and TRUNK_BRANCH are
    -- floors, so the plan takes one for ground) is often drawn with no snow piece in the spatter layer at
    -- all, and such a snowy branch was held for good, looked at every frame: in a forest seen from the
    -- treetops thousands of them (snowshot: 2835 'H' of a view's 8160 tiles, in rings round each trunk).
    -- Only a cell still showing Detailed Weather's own drawing is waited for on a branch.
    if watch == 'branch' then
        local v, a = spatter[i], above[i]
        if (v ~= 0 and made[v]) or (a ~= 0 and made[a]) then return 'tiles left: their cell still showed earlier drawing' end
        return nil
    end
    if bg == 0 then return 'tiles left for a cell the game hadn\'t drawn yet' end
    local v = watch == 'ramp' and bg or watch == 'floor' and spatter[i] or above[i]
    if v ~= 0 and made[v] then return 'tiles left: their cell still showed earlier drawing' end
    if watch == 'floor' and v == 0 then return 'tiles left: snowy, the game\'s snow not drawn there yet' end
    return nil
end

-- FILL BY QUEUE (grungeisdead's copy, 2026-11-17). The tiles in view with nothing kept were found each
-- frame by walking the whole view from its left edge, in the plan and again as the list was made,
-- and only the time left after the walk went to working them out: the further a new view had filled
-- in, the longer the walk to what was left, so the filling slowed as it went (seen in play: strips
-- slower the further along they were, a lot slower). Now the view is walked once when it moves: its
-- tiles with something kept to draw are listed, and those with nothing kept queued. Each frame works
-- through the queue from where it left off, in the plan (NEW_TILES_MS) and as it draws
-- (INLINE_PLAN_MS). A tile that comes to have something to draw is listed as its record is kept, and
-- one whose record is let go is queued again.
if not (snowy_view and snowy_view.queue) then
    snowy_view = {key = nil, list = {}, listed = {}, queue = {}, qpos = 1}
end
-- (TAKE FIRST) the queue's tiles no other level's record could be taken for, worked out after it
snowy_view.later, snowy_view.lpos = snowy_view.later or {}, snowy_view.lpos or 1
-- the view walked once: its tiles with something kept to draw listed ({x, y, x, y...}), those with
-- nothing kept queued (the same)
local function rebuild_view(viewport, view_key)
    local z = viewport.z
    local list, listed, queue = {}, {}, {}
    -- OFF THE MAP (grungeisdead's copy, 2026-11-17): only the tiles on the map are walked. A view at the map's
    -- edge runs on past it, where DF draws nothing and there's nothing to work out, and those tiles were
    -- queued with the rest (snowshot: the first frame of a change of level spent all its time on the 28
    -- columns past the map's west edge, and drew nothing).
    local map_x, map_y = dfhack.maps.getTileSize()
    for x = math.max(viewport.x1, 0), math.min(viewport.x2, map_x - 1) do
        for y = math.max(viewport.y1, 0), math.min(viewport.y2, map_y - 1) do
            local key = (z * 4096 + x) * 4096 + y
            local record = drawn[key]
            if not record then
                queue[#queue + 1] = x
                queue[#queue + 1] = y
            elseif record ~= NOTHING_DRAWN then
                list[#list + 1] = x
                list[#list + 1] = y
                listed[key] = true
            end
        end
    end
    snowy_view.key, snowy_view.list, snowy_view.listed = view_key, list, listed
    snowy_view.queue, snowy_view.qpos = queue, 1
    snowy_view.later, snowy_view.lpos = {}, 1   -- (TAKE FIRST)
end
-- a tile now kept with something to draw (or held), added to the list if it isn't in it
local function list_tile(key, x, y)
    if not snowy_view.listed[key] then
        local list = snowy_view.list
        list[#list + 1] = x
        list[#list + 1] = y
        snowy_view.listed[key] = true
    end
end
-- the queue worked through from where it left off, until the clock reaches `ends` or the plan's
-- working out runs out (plan_tile: this frame's plan_and_keep); true when it's empty
-- TAKE FIRST (grungeisdead's copy, 2026-11-17): in two passes. The first offers each tile another level's
-- record (LEVELS SHARED: a few lookups) and sets aside those none can be taken for; the second works the
-- set-aside ones out. Before, the two were done tile by tile across the view from its left edge, so after a
-- change of level what the level below had shown came back only as fast as the new ground to the left of
-- it was worked out (seen in play: a strip on the right of a level seen before redrawn after a change of
-- level). Now what other levels have seen is back across the whole view within a frame or two, and only
-- new ground fills in after.
-- (TAKE TIME) take_ends: when the first pass stops; ends: when the second does
local function fill_from_queue(plan_tile, z, ends, take_ends)
    local queue, n = snowy_view.queue, snowy_view.qpos
    local later = snowy_view.later
    take_ends = take_ends or ends
    -- first pass: other levels' records
    while n < #queue do
        local x, y = queue[n], queue[n + 1]
        local key = (z * 4096 + x) * 4096 + y
        if not drawn[key] then
            if not plan_tile or clock_ms() >= take_ends then break end
            if not plan_tile(x, y, 'take') then
                later[#later + 1] = x
                later[#later + 1] = y
            end
        end
        n = n + 2
    end
    snowy_view.qpos = n
    if n < #queue then return false end
    -- (worked through: started afresh, so tiles queued again later don't pile up behind it)
    if #queue > 0 then snowy_view.queue, snowy_view.qpos = {}, 1 end
    -- second pass: the tiles set aside, worked out
    local m = snowy_view.lpos
    while m < #later do
        local x, y = later[m], later[m + 1]
        local key = (z * 4096 + x) * 4096 + y
        if not drawn[key] then
            if not plan_tile or clock_ms() >= ends then break end
            plan_tile(x, y, 'work')
            if not drawn[key] then break end   -- (not worked out: this plan's working out ran out)
        end
        m = m + 2
    end
    snowy_view.lpos = m
    if m < #later then return false end
    if #later > 0 then snowy_view.later, snowy_view.lpos = {}, 1 end
    return true
end
-- (TAKE FIRST) whether the new view's queue still has tiles in either pass
local function queue_waiting()
    return snowy_view.qpos < #snowy_view.queue or snowy_view.lpos < #snowy_view.later
end
warm_view, warm_idle = warm_view or nil, warm_idle or 0   -- the view it's warming round; tiles since it last had work

-- KEEP THE VIEW'S (grungeisdead's copy, 2026-11-17). Past REMEMBER_MOST or DRAWN_MOST everything kept was let
-- go at once, and the whole view's snow redrawn from scratch (detailed_weather details: 371950 records made in
-- one session, so past the 200000 once or twice). Now what's kept for the tiles in view, on its level and the
-- levels either side (where LEVELS SHARED takes from), stays, and the rest is let go. The most stays where it
-- was: a snowy tile kept costs about 2.5 KB (Lua 5.3, measured: 1.5 KB worked out from the map, 1 KB for its
-- record), so 200000 of each can come to a few hundred MB. Returns the kept table and how many it holds.
local function keep_view(kept, viewport)
    local out, n = {}, 0
    for z = viewport.z - 1, viewport.z + 1 do
        for x = viewport.x1, viewport.x2 do
            for y = viewport.y1, viewport.y2 do
                local key = (z * 4096 + x) * 4096 + y
                local v = kept[key]
                if v ~= nil then out[key], n = v, n + 1 end
            end
        end
    end
    return out, n
end

-- LEVELS BY USE (grungeisdead's copy, 2026-11-17): past the most, what's let go is the levels looked at longest
-- ago, a whole level at a time, until three quarters of the most is left; the view's level and the levels
-- either side always stay. Only the view's own tiles on those three were kept before, so every other level
-- seen was redrawn from scratch when next visited (seen in play: the ground redrawn coming back down to it
-- from the top, after scrolling through a dozen levels). If the three alone are past the most (a great deal
-- panned on one level), it falls back to the view's own tiles on them (KEEP THE VIEW'S).
level_seen = level_seen or {}   -- view level -> frame_number it was last looked at (set in plan)
local TRIM_TO = 0.75
-- the level a key is on: keys are (z * 4096 + x) * 4096 + y, and x and y can be a little below 0 off the map
-- (right for x and y from -2048 to 2047; the largest map, a 16 by 16 embark, is 768 tiles across)
local function level_of(key) return (key + 8388608) // 16777216 end
local function trim_levels(kept, viewport, most)
    local per = {}
    for key in pairs(kept) do
        local z = level_of(key)
        per[z] = (per[z] or 0) + 1
    end
    local levels, total = {}, 0
    for z, n in pairs(per) do
        total = total + n
        if math.abs(z - viewport.z) > 1 then levels[#levels + 1] = z end
    end
    -- looked at longest ago first
    table.sort(levels, function(a, b) return (level_seen[a] or 0) < (level_seen[b] or 0) end)
    local drop, target = {}, most * TRIM_TO
    for _, z in ipairs(levels) do
        if total <= target then break end
        drop[z], total = true, total - per[z]
    end
    local out, n = {}, 0
    for key, v in pairs(kept) do
        if not drop[level_of(key)] then out[key], n = v, n + 1 end
    end
    if n > most then return keep_view(out, viewport) end
    return out, n
end

-- LEVELS SHARED: copies of a record's entries for a view `shift` levels higher (going up; going down, a
-- negative shift), each one's level below the view moved by that many; those that end up above the view
-- (edges onto open tiles between the two levels) are dropped, and (OUT OF REACH, grungeisdead's copy,
-- 2026-11-17) so are those past the deepest level shown, which the game doesn't draw either.
local function shifted_ramp(t, d) return {x = t.x, y = t.y, depth = d, base = t.base, cell = t.cell, picture = t.picture} end
local function shifted_floor(f, d)
    -- (skirt false: not read on this level yet; apply reads it the first time the cell is the game's drawing)
    return {x = f.x, y = f.y, depth = d, skirt = false, overhangs = f.overhangs, kept = f.kept, piece = f.piece,
            joined = f.joined, lifted = f.lifted}
end
local function shifted_edge(e, d)
    return {x = e.x, y = e.y, depth = d, overhangs = e.overhangs, kept = e.kept, pieces = e.pieces, key = e.key,
            texpos = e.texpos}
end
local function shifted_entries(list, shift, copy)
    local out = {}
    for k = 1, #list do
        local e = list[k]
        local d = e.depth + shift
        if d >= 0 and d <= MOST_DEPTH then out[#out + 1] = copy(e, d) end
    end
    return out
end
-- LEVELS SHARED: a tile as work_out left it, for a view `shift` levels higher (or lower): its depth and open
-- levels moved, those above the view dropped. Its edge slots (below, and each open level's) are left out, to
-- be worked out again on this level as it's next planned; the sides it keeps are only read once made.
-- (OUT OF REACH) one whose ground ends up past the deepest level shown is kept as work_out keeps a column
-- open all the way down: nothing of its ground, only its open levels still in reach. High above the
-- ground such tiles were worked out from scratch, every level down walked (snowshot: 1100 tiles a frame
-- on z 121, nearly all with nothing to draw).
local function shifted_tile(tile, shift)
    local copy = {}
    local depth = tile.depth + shift
    if depth > MOST_DEPTH then
        copy.depth, copy.due, copy.due_quiet = MOST_DEPTH, tile.due, tile.due_quiet
    else
        for k, v in pairs(tile) do copy[k] = v end
        copy.depth, copy.below = depth, nil
    end
    if tile.open_levels then
        local levels = {}
        for _, open in ipairs(tile.open_levels) do
            local d = open.depth + shift
            if d >= 0 and d < MOST_DEPTH then levels[#levels + 1] = {depth = d, sides = open.sides} end
        end
        copy.open_levels = levels[1] and levels or nil
    end
    return copy
end

function plan(viewport)
    -- (NATIVE SNOW: the DLL works everything out; apply() still runs, to serve its bakes)
    if native_snow then return {native = true} end
    local started = clock_ms()
    -- UNDRAWN CELLS: this frame's black, and whether the view moved since the last frame
    local frame_view = ('%d:%d:%d:%d:%d'):format(viewport.z, viewport.x1, viewport.y1, viewport.x2, viewport.y2)
    frame_moved, last_frame_view = frame_view ~= last_frame_view, frame_view
    level_seen[viewport.z] = frame_number   -- (LEVELS BY USE)
    -- (NEW VIEW) frames left with the larger budgets: NEW_VIEW_FRAMES from a move, and (WHOLE LOAD) on while
    -- the new view's queue isn't worked through, up to NEW_VIEW_MOST_FRAMES. Tiles held for their cell aren't
    -- in the queue, so the ones that wait for good (under a canopy) don't keep them on.
    if frame_moved then
        new_view_left, new_view_age = NEW_VIEW_FRAMES, 0
    else
        new_view_age = new_view_age + 1
        if new_view_left > 0 then
            new_view_left = new_view_left - 1
            if new_view_left == 0 and queue_waiting() and new_view_age < NEW_VIEW_MOST_FRAMES then
                new_view_left = 1
            end
        end
    end
    frame_black = df.global.gps.black_background_texpos[0]
    if frame_black == 0 then frame_black = -1 end   -- (none set: no cell is taken for undrawn)
    if frame_moved then count('frames the view moved') end
    -- QUIET REFRESH: whether snow is falling anywhere on the map, from the game's 5 by 5 weather cells
    -- (df.global.current_weather, the ones the map lies in), looked at once a second
    if started - weather_checked >= 1000 then
        weather_checked = started
        -- (if the cells can't be read, refreshed as often as ever)
        local ok, falling = pcall(function()
            local cells = df.global.current_weather
            for wx = 0, 4 do
                for wy = 0, 4 do
                    if cells[wx][wy] == df.weather_type.Snow then return true end
                end
            end
            return false
        end)
        snowing = not ok or falling
    end
    if not cell_of_byte then cell_of_byte = cell_table() end
    local main = df.global.gps.main_viewport
    if not piece_sides then find_snow_pieces() end
    local ports, backgrounds, ramp_flags, shadow_flags, floor_flags, spatters, aboves = {}, {}, {}, {}, {}, {}, {}
    local drawing = {}   -- (UNDRAWN CELLS) by depth: whether the game draws that level this frame
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        ports[depth] = port
        -- (UNDRAWN CELLS) a level below is the game's drawing of this frame only while its viewport is
        -- active (frost.lua: LEVELS THE GAME DRAWS); its cells aren't waited on otherwise
        drawing[depth] = depth == 0 or port.flag.active
        backgrounds[depth], ramp_flags[depth], shadow_flags[depth], floor_flags[depth], spatters[depth], aboves[depth] =
            port.screentexpos_background, port.screentexpos_ramp_flag, port.screentexpos_shadow_flag,
            port.screentexpos_floor_flag, port.screentexpos_spatter, port.screentexpos_background_two
    end

    local block_at = grass.block_at   -- kept between plans
    -- each tile's snow, from grass.lua's per-block reading
    local now_ms = clock_ms()
    local function snow_at(_, x, y, z) return grass.snow_amount(x, y, z, now_ms) end
    -- (BLOCKS READ IN ONE COPY) a tile's type, and whether it's outside, from its block's copy
    local function type_at(x, y, z)
        local info = info_at(x, y, z, now_ms)
        return info and info.types[(x % 16) * 16 + y % 16]
    end
    local function outside_at(x, y, z)
        local info = info_at(x, y, z, now_ms)
        return info and info.outside[(x % 16) * 16 + y % 16] or false
    end

    -- one tile from scratch: which level it shows, and whether that's a snowy ramp or floor
    -- The sides of (x, y, z) whose neighbour has snow, as a set, or nil if none.
    local function snowy_neighbours(x, y, z)
        local sides
        for b, side in ipairs(OVERHANG_SIDES) do
            local nx, ny = x + side[1], y + side[2]
            local neighbour = block_at(nx, ny, z)
            if neighbour and snow_at(neighbour, nx, ny, z) >= SNOWY then
                sides = sides or {}
                sides[SIDE_NAMES[b]] = true
            end
        end
        return sides
    end

    local work_out_below
    -- One tile from scratch. Where a level is open (the top of a slope, a drop) the tile shows a
    -- level further down, but edges from snowy floors on each open level still land on it, in
    -- that level's viewport: those are noted too (open_levels: depth and snowy sides), to draw as
    -- snow there.
    local function work_out(x, y)
        local tile = work_out_below(x, y)
        for depth = 0, math.min(tile.depth, MOST_DEPTH + 1) - 1 do
            local sides = snowy_neighbours(x, y, viewport.z - depth)
            if sides then
                tile.open_levels = tile.open_levels or {}
                tile.open_levels[#tile.open_levels + 1] = {depth = depth, sides = sides}
            end
        end
        return tile
    end

    -- Whether a trunk gets thin snow under it: when a side next to it is snowy (as below).
    local function trunk_snowed(x, y, z)
        for _, side in ipairs(OVERHANG_SIDES) do
            local nx, ny = x + side[1], y + side[2]
            local neighbour = block_at(nx, ny, z)
            if neighbour and snow_at(neighbour, nx, ny, z) >= SNOWY then return true end
        end
        return false
    end

    function work_out_below(x, y)
        local depth, z = 0, viewport.z
        while depth <= MOST_DEPTH do
            local block = block_at(x, y, z)
            if not block then return {depth = depth} end
            local tiletype = type_at(x, y, z)
            local s = shape(tiletype)
            if s == RAMP or floor_like[tiletype] then
                -- the snow itself says whether it's snowy: tiles under a tree's canopy count as
                -- indoors (not 'outside') but the game still lays snow on them
                local amount = snow_at(block, x, y, z)
                local outdoors = outside_at(x, y, z) or amount > 0
                local snowy = amount >= SNOWY
                -- (TREES: branch, a tree's branch, which the plan leaves as the game drew it unless the game
                -- drew a snow piece on it)
                local tile = {depth = depth, snowy_ramp = snowy and s == RAMP, snowy_floor = snowy and s ~= RAMP,
                              amount = snow_at(block, x, y, z), branch = (s ~= RAMP and tree_part[tiletype]) or nil}
                if s ~= RAMP and outdoors then
                    -- which sides' overhangs come from snowy neighbours (cleared on snow, drawn as
                    -- snow on bare ground), and which sides have a snowy ramp
                    tile.keep, tile.ramp_sides, tile.snowy_sides, tile.full_sides = 0, {}, {}, {}
                    -- join_sides: which way the snow piece joins. Towards snowy neighbours here; towards
                    -- bare ones the plan decides from who overhangs whom (see the snowy floors below)
                    tile.join_sides = {}
                    for b, side in ipairs(OVERHANG_SIDES) do
                        local nx, ny = x + side[1], y + side[2]
                        local neighbour = block_at(nx, ny, z)
                        local neighbour_snow = neighbour and snow_at(neighbour, nx, ny, z) or 0
                        local name = SIDE_NAMES[b]
                        if not neighbour and not dfhack.maps.isValidTilePos(nx, ny, z) then
                            -- off the edge of the map: snow runs right up to it
                            neighbour_snow = tile.amount
                        elseif neighbour and neighbour_snow == 0 then
                            -- a tree's trunk with a snowy neighbour has thin snow drawn under it
                            -- (below), so it counts as thinly snowy: its grass edges here are
                            -- cleared and the snow joins to it
                            local neighbour_type = type_at(nx, ny, z)
                            if trunk(neighbour_type) and trunk_snowed(nx, ny, z) then
                                neighbour_snow = SNOWY
                            end
                        end
                        if neighbour_snow < SNOWY then
                            tile.keep = tile.keep | (0xff << (8 * (b - 1)))
                            local neighbour_type = neighbour and type_at(nx, ny, z)
                            if neighbour and shape(neighbour_type) == RAMP then
                                -- the foot of a slope: ramps take no overhangs either way, so the
                                -- snow runs up to it and the slope's own art takes over
                                tile.join_sides[name] = true
                            elseif neighbour and (shape(neighbour_type) == RAMP_TOP or shape(neighbour_type) == EMPTY) then
                                -- open beside: the top of a slope, or a drop. Followed down to the
                                -- first solid tile; if that's snowy, snow here runs to the lip.
                                local below_snow = 0
                                for down = 1, MOST_DEPTH do
                                    local below = block_at(nx, ny, z - down)
                                    if not below then break end
                                    local below_shape = shape(type_at(nx, ny, z - down))
                                    if below_shape ~= EMPTY and below_shape ~= RAMP_TOP then
                                        below_snow = snow_at(below, nx, ny, z - down)
                                        break
                                    end
                                end
                                if below_snow >= SNOWY then
                                    tile.join_sides[name] = true
                                    if below_snow >= 255 then tile.full_sides[name] = true end
                                end
                            end
                        else
                            tile.snowy_sides[name], tile.join_sides[name] = true, true
                            if neighbour_snow >= 255 then tile.full_sides[name] = true end
                            if neighbour and shape(type_at(nx, ny, z)) == RAMP then
                                tile.ramp_sides[name] = true
                            end
                        end
                    end
                    tile.x, tile.y = x, y
                    tile.bare_floor = not snowy and next(tile.snowy_sides) ~= nil
                end
                return tile
            end
            if trunk(tiletype) then
                -- a tree's trunk: the game counts it as indoors and never puts snow there, so the
                -- snow round a tree stopped square at it. It gets thin snow joined to its snowy
                -- neighbours (lighter under the canopy), with their grass edges cleared; the trunk
                -- itself is drawn in the layer above, over it.
                local sides, keep = {}, 0
                for b, side in ipairs(OVERHANG_SIDES) do
                    local nx, ny = x + side[1], y + side[2]
                    local neighbour = block_at(nx, ny, z)
                    if neighbour and snow_at(neighbour, nx, ny, z) >= SNOWY then
                        sides[SIDE_NAMES[b]] = true
                    else
                        keep = keep | (0xff << (8 * (b - 1)))
                    end
                end
                if next(sides) then return {depth = depth, trunk = true, sides = sides, keep = keep, x = x, y = y} end
                return {depth = depth}
            end
            if s ~= EMPTY and s ~= RAMP_TOP then return {depth = depth} end
            depth, z = depth + 1, z - 1
        end
        return {depth = MOST_DEPTH}
    end

    local now = clock_ms()
    -- Tiles are remembered by map position and the view's level, so moving the view reuses what's
    -- known; going up or down a level, a tile new to that level takes what another level knows of the
    -- same ground (LEVELS SHARED, in plan_and_keep).
    if remembered_count > REMEMBER_MOST then
        remembered, remembered_count = trim_levels(remembered, viewport, REMEMBER_MOST)   -- (LEVELS BY USE)
        count('worked-out tiles past their most')
    end
    local budget, complete = new_view_left > 0 and NEW_VIEW_WORK or WORK_PER_PLAN, true   -- (NEW VIEW)
    local tiles, floors, bare_edges   -- the record being made for the current tile (set per tile)
    local undrawn = false   -- (UNDRAWN CELLS) set by plan_tile, to why, when it's left for a later frame
    local held_depth, held_watch = 0, 'background'   -- (HELD) where plan_tile looked: depth and layer
    local thin_state = {budget = THIN_BAKES_PER_PLAN}

    -- Snowy edges for a tile, drawn as snow in the layer above in place of the game's: the side
    -- pieces its snowy neighbours drop on it (if `sides_too`: on bare ground; on snow they're just
    -- cleared, above), and the small corner pieces the game adds itself from snowy diagonal
    -- neighbours (not in floor_flag, so they can't be cleared: they're covered instead), by the
    -- same rule grass.lua follows.
    local edging_seen = {}   -- each tile's grass edging, looked up once a plan
    local function edging_at(x, y, z)
        local key = (z * 4096 + x) * 4096 + y
        local id = edging_seen[key]
        if id == nil then
            -- (BLOCKS READ IN ONE COPY: from the block's copy, as grass.grass_edging works it out)
            local info = info_at(x, y, z, now_ms)
            id = info and info.edging[(x % 16) * 16 + y % 16] or false
            edging_seen[key] = id
        end
        return id or nil
    end

    -- The work is remembered on the tile (it's only redone when the tile is next due, or the
    -- game's overhangs on it change), so a plan mostly just re-adds what it found last time.
    local function add_snowy_edges(tile, x, y, z, depth, snowy_sides, sides_too)
        local i = screen_index(ports[depth], viewport, x, y)
        if not i then return end
        -- (whether the layer is free is checked as it's drawn, each frame)
        local overhangs = floor_flags[depth][i]
        local slot = sides_too and 'edges' or 'corners'
        local cached = tile[slot]
        if cached and cached.overhangs == overhangs and cached.depth == depth then
            if cached.entry then
                cached.entry.x, cached.entry.y = x, y
                bare_edges[#bare_edges + 1] = cached.entry
            end
            return
        end
        if not edge_art then edge_art = all_edge_art() end
        local kept, pieces, side_ids = overhangs, {}, {}
        for b, side in ipairs(SIDE_NAMES) do
            local byte = (overhangs >> (8 * (b - 1))) & 0xff
            side_ids[b] = byte
            local art = sides_too and snowy_sides[side] and edge_art[byte]
            if art and art[side] then
                pieces[#pieces + 1] = art[side]
                kept = kept & ~(0xff << (8 * (b - 1)))
            end
        end
        local own = edging_at(x, y, z)
        for _, corner in ipairs(grass.CORNERS) do
            local cx, cy = x + corner.dx, y + corner.dy
            local diagonal = block_at(cx, cy, z)
            local id = diagonal and snow_at(diagonal, cx, cy, z) >= SNOWY and edging_at(cx, cy, z)
            if id and grass.beats(id, own) and side_ids[corner.sides[1]] ~= id and side_ids[corner.sides[2]] ~= id
                    and edge_art[id] and edge_art[id][corner.name] then
                pieces[#pieces + 1] = edge_art[id][corner.name]
            end
        end
        local entry
        if #pieces > 0 then
            -- on snow, floor_flag is the snowy floor's to change (above), so it's left alone here
            entry = {x = x, y = y, depth = depth, overhangs = sides_too and overhangs or nil,
                     kept = kept, pieces = pieces, key = table.concat(pieces, ':')}
            bare_edges[#bare_edges + 1] = entry
        end
        tile[slot] = {overhangs = overhangs, depth = depth, entry = entry}
    end
    -- Works out what's drawn on one tile in view, from the map and the screen as they are now.
    local function plan_tile(x, y)
        local key = (viewport.z * 4096 + x) * 4096 + y
        local tile = remembered[key]
        -- (QUIET REFRESH: the sooner due time while snow is falling, the later one while none is)
        if not tile or now >= (snowing and tile.due or tile.due_quiet or tile.due) then
            if budget > 0 then
                budget = budget - 1
                if not tile then remembered_count = remembered_count + 1 end
                local clock = clock_s()   -- (COSTS)
                tile = work_out(x, y)
                costs.work_n, costs.work_s = costs.work_n + 1, costs.work_s + clock_s() - clock
                set_due(tile, now)
                remembered[key] = tile
            elseif not tile then
                complete = false   -- left for the next plan
            end
        end
        -- (UNDRAWN CELLS, STILL OURS) a tile with snow to draw is worked out only from the game's own
        -- drawing of its cell: not from a cell the game hasn't drawn yet, nor, on the frame the view
        -- moves, from a level below (it can still hold the old view's drawing), nor from a cell still
        -- showing a texture of Detailed Weather's. plan_and_keep keeps what it had, or holds the tile.
        if tile and (tile.trunk or tile.snowy_ramp or tile.snowy_floor or tile.bare_floor or tile.open_levels) then
            local d = tile.depth
            -- (HELD) what the tile is, so what its plan reads, looked at again while it's held
            held_depth = d
            held_watch = tile.snowy_ramp and 'ramp' or tile.branch and 'branch' or tile.snowy_floor and 'floor'
                or tile.trunk and 'trunk' or tile.bare_floor and 'bare' or 'open'
            if frame_moved and d > 0 then
                undrawn = 'tiles below left for the frame of a move'
                return
            end
            local i = screen_index(ports[d], viewport, x, y)
            if i and drawing[d] then
                local why = not_drawn_why(held_watch, backgrounds[d], spatters[d], aboves[d], i)
                if why then
                    undrawn = why
                    return
                end
            end
        end
        if tile and tile.trunk then
            local i = screen_index(ports[tile.depth], viewport, x, y)
            if i and spatters[tile.depth][i] == 0 then
                local full = piece_joined_on(tile.sides, x, y)
                if full then
                    local overhangs = floor_flags[tile.depth][i]
                    floors[#floors + 1] = {x = x, y = y, depth = tile.depth, skirt = shadow_flags[tile.depth][i],
                                           overhangs = overhangs, kept = overhangs & tile.keep,
                                           piece = 0, joined = thin_version(full, x, y, viewport.z - tile.depth, tile.amount)}
                end
            end
        end
        -- (TREES) a branch the game drew no snow piece on, snowy or bare, is left as the game drew it: its
        -- shadow, its edges and what lies on it as they are, and nothing kept for it (so nothing looked at
        -- each frame). One with a snow piece of the game's is a snowy floor like any other.
        local leave = false
        if tile and tile.branch then
            local i = screen_index(ports[tile.depth], viewport, x, y)
            leave = not (i and piece_sides[spatters[tile.depth][i]])
        end
        if not tile then
            -- not worked out yet
        elseif tile.snowy_ramp then
            local i = screen_index(ports[tile.depth], viewport, x, y)
            local base = i and backgrounds[tile.depth][i] or 0
            if base > 0 then
                local byte = (ramp_flags[tile.depth][i] >> 8) & 0xff
                tiles[#tiles + 1] = {x = x, y = y, depth = tile.depth, base = base, cell = cell_of_byte[byte],
                                     picture = picture_id(base)}   -- (RAMPS BY PICTURE)
            end
        elseif tile.snowy_floor and screen_index(ports[tile.depth], viewport, x, y) then
            local i = screen_index(ports[tile.depth], viewport, x, y)
            local skirt, overhangs = shadow_flags[tile.depth][i], floor_flags[tile.depth][i]
            local kept = overhangs & tile.keep
            local piece = spatters[tile.depth][i]
            -- something other than snow in the spatter slot: moved above it if there's room, else
            -- (a sapling or shrub is there) painted over the snow in one texture
            local other = piece ~= 0 and not snow_page_art[piece] and not snow_made[piece]
            local lifted = other and aboves[tile.depth][i] == 0 and piece or nil
            local under = other and not lifted and piece or nil
            -- the full piece joined towards every snowy neighbour, and towards bare ground this
            -- tile overhangs (its edge there is drawn as snow, so the snow runs on into it; where
            -- the bare neighbour overhangs this tile instead, the snow stays set back and that
            -- edge sits in the margin). Thin below full snow.
            local joined
            if lifted or under or piece_sides[piece] then
                local sides = {}
                for side in pairs(tile.join_sides) do sides[side] = true end
                for b, step in ipairs(OVERHANG_SIDES) do
                    local name = SIDE_NAMES[b]
                    local ni = not sides[name] and screen_index(ports[tile.depth], viewport, x + step[1], y + step[2])
                    if ni then
                        -- the neighbour's byte for the side facing this tile (S<->N, W<->E)
                        local facing = OPPOSITE_BYTE[b]
                        if (floor_flags[tile.depth][ni] >> (8 * (facing - 1))) & 0xff ~= 0 then sides[name] = true end
                    end
                end
                joined = piece_joined_on(sides, tile.x, tile.y)
                if joined then
                    joined = thin_beside_full(joined, tile.x, tile.y, viewport.z - tile.depth, tile.amount, tile.full_sides, thin_state)
                end
                if joined and under then joined = snow_with(joined, under, thin_state) or joined end
                if joined == piece then joined = nil end
            end
            if not leave and (skirt ~= 0 or kept ~= overhangs or joined) then
                floors[#floors + 1] = {x = x, y = y, depth = tile.depth, skirt = skirt, overhangs = overhangs,
                                       kept = kept, piece = piece, joined = joined, lifted = lifted}
            end
        end
        -- edges onto open tiles, from snowy floors beside them on that level
        for _, open in ipairs(tile and tile.open_levels or {}) do
            open.slots = open.slots or {}
            add_snowy_edges(open.slots, x, y, viewport.z - open.depth, open.depth, open.sides, true)
        end
        -- edges onto bare ground from snowy neighbours, and corners over any floor
        if tile and not leave and tile.depth <= MOST_DEPTH and (tile.bare_floor or tile.snowy_floor) then
            tile.below = tile.below or {}   -- its own slots, apart from the open tile's on this level
            add_snowy_edges(tile.below, x, y, viewport.z - tile.depth, tile.depth, tile.snowy_sides, tile.bare_floor)
        end
    end

    if drawn_count > DRAWN_MOST then
        drawn, drawn_count = trim_levels(drawn, viewport, DRAWN_MOST)   -- (LEVELS BY USE)
        count('records past their most')
        drawn_version, drawn_drops = drawn_version + 1, drawn_drops + 1   -- (SNOWY TILES LISTED, VIEW KNOWN)
        snowy_view.key = nil   -- (FILL BY QUEUE: the view walked again)
    end
    local z = viewport.z
    -- (grungeisdead's copy, 2026-11-17) A record's three lists are made only when the tile has something
    -- to draw: an empty one is kept and used for the next tile. Every tile looked at made a new one,
    -- four tables, 30 tiles a frame refreshed with nothing on them.
    local spare = nil

    -- (TREES) whether snowy edges could fall onto open tile (x, y, z): from a snowy neighbour beside it that
    -- isn't a tree's (a branch or twig drops no edge: there's no edge art for one), or from a snowy grass
    -- tile on a corner (add_snowy_edges looks at the corners whenever a neighbour beside it is snowy).
    -- Asked only where snowy_neighbours found one. Snowy branches beside an open tile stopped every record
    -- being taken there (snowshot: of the tiles drawn on the level below, 1329 worked out again rather than
    -- taken, in rings round each clearing and through the treetops).
    local function edges_could_fall(x, y, z)
        for _, side in ipairs(OVERHANG_SIDES) do
            local nx, ny = x + side[1], y + side[2]
            local neighbour = block_at(nx, ny, z)
            if neighbour and snow_at(neighbour, nx, ny, z) >= SNOWY and not tree_tile(type_at(nx, ny, z)) then return true end
        end
        for _, corner in ipairs(grass.CORNERS) do
            local cx, cy = x + corner.dx, y + corner.dy
            local diagonal = block_at(cx, cy, z)
            if diagonal and snow_at(diagonal, cx, cy, z) >= SNOWY and edging_at(cx, cy, z) then return true end
        end
        return false
    end

    -- LEVELS SHARED (grungeisdead's copy, 2026-11-17). What's kept for a tile is kept under the level the view
    -- is on, not the level its ground is on, so ground seen through open space from one level was worked out
    -- again from scratch from the next (seen in play: the levels below lose their snow going up a level, and
    -- a level's first view reloads the whole screen; snowshot: 5302 of a view's 8160 tiles with nothing kept
    -- the frame after a change of level, filled over 12 frames). A tile with nothing kept on this level now
    -- takes the record of the same place on another level, when that one shows the same ground:
    --   going down  the nearest level above with a record there, if its ground is at or below this level
    --   going up    the nearest level below with one, seen through open tiles on this level (and any
    --               between) that no snowy edges could fall onto (edges_could_fall: snowy branches beside
    --               them drop none), so with nothing from work_out's open levels to draw there
    -- The copy's levels are moved by the levels between, its edges onto open tiles above this level dropped,
    -- and its floors' skirts read again the first time their cell is the game's drawing (the one value off
    -- the screen the drawing doesn't check). The rest is checked against the screen every frame as before,
    -- so a record the game draws otherwise on this level is let go and the tile worked out afresh (it then
    -- has a plan here, so it isn't taken again). True if one was taken.
    local function adopt(x, y, key)
        local tile, record, shift
        -- going down: the nearest level above with a record here
        for up = 1, MOST_DEPTH do
            local k = ((z + up) * 4096 + x) * 4096 + y
            local t, r = remembered[k], drawn[k]
            if t and r then
                if not r.held and t.depth >= up then tile, record, shift = t, r, -up end
                break
            end
        end
        -- going up: the nearest level below with a record here, through open tiles with no snowy edges.
        -- FAIL FAST (grungeisdead's copy, 2026-11-17): the record is looked for first, by lookups alone, and
        -- only then the levels between checked. Each level down was checked first (its tile type, its
        -- neighbours' snow), so on ground no level had seen yet, where every try fails, the tries walked
        -- every open level down and cost more than working the tiles out: a pan into new ground at the
        -- treetops filled nothing for 3 frames (snowshot: the same 6660 tiles waiting 4 frames running).
        if not tile then
            local found
            for down = 1, MOST_DEPTH do
                local k = ((z - down) * 4096 + x) * 4096 + y
                if remembered[k] and drawn[k] then found = down break end
            end
            if found then
                -- every level from this one down to just above the record's is open, with no snowy edges
                local open = true
                for level = z, z - found + 1, -1 do
                    local tiletype = type_at(x, y, level)
                    local s = tiletype and shape(tiletype)
                    if not s or (s ~= EMPTY and s ~= RAMP_TOP)
                            or (snowy_neighbours(x, y, level) and edges_could_fall(x, y, level)) then   -- (TREES)
                        open = false
                        break
                    end
                end
                local k = ((z - found) * 4096 + x) * 4096 + y
                if open and not drawn[k].held then tile, record, shift = remembered[k], drawn[k], found end
            end
        end
        if not tile then return false end
        -- (going down, one at the deepest level shown may have ground further down that comes into reach: not
        -- taken. Going up, one whose ground goes out of reach is taken without it: OUT OF REACH)
        if shift < 0 and tile.depth >= MOST_DEPTH then return false end
        local copy = NOTHING_DRAWN
        if record ~= NOTHING_DRAWN then
            local ramps = shifted_entries(record.ramps, shift, shifted_ramp)
            local floors = shifted_entries(record.floors, shift, shifted_floor)
            local edges = shifted_entries(record.edges, shift, shifted_edge)
            if #ramps + #floors + #edges > 0 then
                -- (taken: for the snowshot)
                copy = {ramps = ramps, floors = floors, edges = edges, edge = record.edge, taken = true}
            end
        end
        remembered[key], remembered_count = shifted_tile(tile, shift), remembered_count + 1
        drawn[key], drawn_count = copy, drawn_count + 1
        if copy ~= NOTHING_DRAWN and snowy_view.key == last_frame_view then list_tile(key, x, y) end   -- (FILL BY QUEUE)
        count('records taken from another level')
        return true
    end

    -- mode (TAKE FIRST): 'take' only tries another level's record, and says whether one was taken; 'work'
    -- only works the tile out (it's been offered one already); nil does both, as the refresh and the held
    -- tiles want
    local function plan_and_keep(x, y, mode)
        local key = (z * 4096 + x) * 4096 + y
        -- (LEVELS SHARED) new to this level: another level's record taken, if one shows the same ground
        if mode ~= 'work' and not drawn[key] and not remembered[key] then
            local clock = clock_s()   -- (COSTS)
            local taken = adopt(x, y, key)
            costs.adopt_tries, costs.adopt_s = costs.adopt_tries + 1, costs.adopt_s + clock_s() - clock
            if taken then
                costs.adopt_n = costs.adopt_n + 1
                return true
            end
        end
        if mode == 'take' then return false end   -- (TAKE FIRST: worked out on the second pass)
        local record = spare or {ramps = {}, floors = {}, edges = {}}
        spare = nil
        tiles, floors, bare_edges = record.ramps, record.floors, record.edges
        undrawn = false
        local clock = clock_s()   -- (COSTS)
        plan_tile(x, y)
        costs.plan_n, costs.plan_s = costs.plan_n + 1, costs.plan_s + clock_s() - clock
        if not remembered[key] then spare = record return end   -- not worked out (this plan's budget ran out)
        -- (UNDRAWN CELLS) left for a later frame (plan_tile says why): what's kept stays, and a tile
        -- with nothing kept is held (HELD), to be worked out the frame the game draws its cell
        if undrawn then
            spare = record
            count(undrawn)
            local old = drawn[key]
            if not old then
                drawn[key] = {held = true, depth = held_depth, watch = held_watch}
                drawn_count, drawn_version = drawn_count + 1, drawn_version + 1
                if snowy_view.key == last_frame_view then list_tile(key, x, y) end   -- (FILL BY QUEUE)
            elseif old.held then
                old.depth, old.watch = held_depth, held_watch
            end
            return
        end
        local old = drawn[key]
        if not old then
            drawn_count = drawn_count + 1
            count('records made for tiles with none')
        elseif old.held then
            count('held tiles worked out once drawn')
        end
        -- most tiles draw nothing: one shared marker for those, quick to pass over
        if #record.ramps == 0 and #record.floors == 0 and #record.edges == 0 then
            spare, record = record, NOTHING_DRAWN
        else
            -- (SNOWSHOT) whether it was made at the view's edge
            record.edge = x <= viewport.x1 or x >= viewport.x2 or y <= viewport.y1 or y >= viewport.y2
        end
        -- (FILL BY QUEUE: a tile come to have something to draw is listed, if it's in the view being
        -- drawn; one that no longer has stays listed and is passed over until the view is walked again)
        drawn[key] = record
        if record ~= NOTHING_DRAWN and snowy_view.key == last_frame_view then list_tile(key, x, y) end
    end
    local slice_ms = SLICE_MS * allowance
    local new_tiles_ms = (new_view_left > 0 and NEW_VIEW_TILES_MS or NEW_TILES_MS) * allowance   -- (NEW VIEW)
    local function out_of_time() return clock_ms() - started >= slice_ms end
    local function out_of_time_for_new() return clock_ms() - started >= new_tiles_ms end

    -- first: tiles in view with nothing kept (a newly shown strip), from the queue where the last
    -- frame left off (FILL BY QUEUE). The frame the view moves, the drawing walks the new view and
    -- queues them; until then this has nothing of the new view's to work on.
    local complete = false
    if snowy_view.key == frame_view then
        complete = fill_from_queue(plan_and_keep, z, started + new_tiles_ms, started + TAKE_MS * allowance)   -- (TAKE TIME)
    end
    -- then: refresh a few in view, in case the game changed something there
    if complete then
        local cols, rows = viewport.x2 - viewport.x1 + 1, viewport.y2 - viewport.y1 + 1
        local cells = cols * rows
        for _ = 1, math.min(snowing and REFRESH_PER_FRAME or REFRESH_QUIET_PER_FRAME, cells) do   -- (QUIET REFRESH)
            if out_of_time() then break end
            refresh_at = (refresh_at + 1) % cells
            plan_and_keep(viewport.x1 + refresh_at // rows, viewport.y1 + refresh_at % rows)
        end
        -- and with time to spare: the map side of the tiles round the view, ready for a pan
        -- (once a whole sweep finds nothing to do, it rests until the view moves)
        local w, h = cols + 2 * WARM_MARGIN, rows + 2 * WARM_MARGIN
        local view_key = (((z * 4096 + viewport.x1) * 4096 + viewport.y1) * 512 + cols) * 512 + rows
        if warm_view ~= view_key then warm_view, warm_idle = view_key, 0 end
        while warm_idle < w * h and not out_of_time() and budget > 0 do
            warm_at = (warm_at + 1) % (w * h)
            warm_idle = warm_idle + 1
            local x, y = viewport.x1 - WARM_MARGIN + warm_at // h, viewport.y1 - WARM_MARGIN + warm_at % h
            local inside = x >= viewport.x1 and x <= viewport.x2 and y >= viewport.y1 and y <= viewport.y2
            local key = (z * 4096 + x) * 4096 + y
            if not inside and not remembered[key] and dfhack.maps.isValidTilePos(x, y, z) then
                budget = budget - 1
                warm_idle = 0
                remembered_count = remembered_count + 1
                local tile = work_out(x, y)
                set_due(tile, now)   -- (QUIET REFRESH)
                remembered[key] = tile
            end
        end
    end
    work_time.done()
    timing.plan = timing.plan + (clock_ms() - started - timing.plan) * 0.2
    -- the planner itself goes with the plan, so apply() can plan a tile it finds with nothing kept
    -- (just shown by a pan, or dropped as stale) and draw it the same frame
    return {z = viewport.z, x1 = viewport.x1, y1 = viewport.y1, complete = complete, plan_tile = plan_and_keep}
end

-- SNOWY TILES LISTED (grungeisdead's copy, 2026-11-17): the view's tiles with something to draw, as a flat
-- list {x, y, x, y...}. apply() looked up every tile in view every frame, some 8000 zoomed out, with
-- no snow anywhere to draw (detailed_weather details: snow-draw 1.1 ms a frame). The list is made
-- when the view moves and kept up as records are kept (FILL BY QUEUE); the tiles with nothing kept
-- are worked through from the queue here, within INLINE_PLAN_MS, as apply() did them.
local function snowy_list(viewport, plan_tile, started)
    local view_key = ('%d:%d:%d:%d:%d'):format(viewport.z, viewport.x1, viewport.y1, viewport.x2, viewport.y2)
    if snowy_view.key ~= view_key then rebuild_view(viewport, view_key) end
    -- (NEW VIEW: more time after a move; TAKE TIME: its own for the first pass)
    fill_from_queue(plan_tile, viewport.z, started + inline_ms(), started + TAKE_MS * allowance)
    return snowy_view.list
end

-- Each tile's buffer index is worked out afresh from the view as it is now, and checked against
-- the buffer's size: a plan from before a zoom or resize can't write outside it.
function apply(planned, viewport)
    local started = clock_ms()
    if not art then load_art() end
    frame_number = frame_number + 1
    -- (NATIVE SNOW: the DLL draws everything; this only bakes the textures it asks for)
    if native_snow then serve_native_bakes() return end
    -- this frame's planner, for tiles with nothing kept (only if planned for this very view)
    local plan_tile = planned and planned.z == viewport.z and planned.x1 == viewport.x1
        and planned.y1 == viewport.y1 and planned.plan_tile or nil
    -- (SNOWSHOT) a shot under way, or armed and the view moved: this frame is shot, after the last shot
    -- frame's drawn floors are checked against the finished frame; written once it has its frames
    local shooting = shot ~= nil and (shot.started or frame_moved)
    if shooting then
        shot.started = true
        shot_check_last()
        if #shot.frames >= SHOT_FRAMES then
            shot_write()
            shooting = false
        end
    end
    local status = shooting and {} or nil       -- (SNOWSHOT) what the drawing found, by tile key
    local shot_cells = shooting and {} or nil   -- (SNOWSHOT) the floors drawn at the view's level
    -- (SNOWY TILES LISTED: nothing to draw in view, nothing else to do this frame)
    local list = snowy_list(viewport, plan_tile, started)
    if #list == 0 then
        timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
        return
    end
    local backgrounds, shadow_flags, floor_flags, spatters, aboves, dims_x, dims_y = {}, {}, {}, {}, {}, {}, {}
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        backgrounds[depth], shadow_flags[depth], floor_flags[depth], spatters[depth], aboves[depth] =
            port.screentexpos_background, port.screentexpos_shadow_flag, port.screentexpos_floor_flag,
            port.screentexpos_spatter, port.screentexpos_background_two
        -- each buffer's size, read once a frame (every read of a game buffer is a userdata call)
        dims_x[depth], dims_y[depth] = port.dim_x, port.dim_y
        -- (grungeisdead's copy, 2026-11-17) LEVELS THE GAME DRAWS, as frost.lua: a level below is the
        -- game's drawing of this frame only while its viewport is active. Nothing is read or drawn on
        -- one that isn't (its records were checked against cells nobody draws, every frame).
        if depth > 0 and not port.flag.active then dims_x[depth], dims_y[depth] = 0, 0 end
    end
    local x1, y1 = viewport.x1, viewport.y1
    local function index_in(depth, x, y)
        local sx, sy = x - x1, y - y1
        if sx < 0 or sy < 0 or sx >= dims_x[depth] or sy >= dims_y[depth] then return nil end
        return sx * dims_y[depth] + sy
    end
    local state = {budget = OVERHANG_BAKES_PER_FRAME}
    -- One pass over the view's tiles with something drawn (SNOWY TILES LISTED), drawing each from what's
    -- kept for it: its snowy floor, then its snowy edges, then its snowy ramp (each only touches its
    -- own tile).
    local z = viewport.z
    local still_drawn = 0   -- (STILL OURS) cells this pass found still showing this snow's drawing
    local held_started = nil   -- (FILL BY QUEUE) when this pass first worked out a held tile
    local other_pieces = 0     -- (ANY FULL PIECE) floors where the game showed another of its full pieces
    for n = 1, #list, 2 do
        local x, y = list[n], list[n + 1]
        do
            local key = (z * 4096 + x) * 4096 + y
            local record = drawn[key]
            -- HELD: looked at as it's drawn (one read of the layer its plan reads), and worked out the
            -- frame the game draws its cell, within INLINE_PLAN_MS; until then it's left as it is
            if record and record.held then
                local d = record.depth
                local i = index_in(d, x, y)
                local waiting = (frame_moved and d > 0)
                    or (i and not_drawn_why(record.watch, backgrounds[d], spatters[d], aboves[d], i) ~= nil)
                -- (FILL BY QUEUE: a time of their own, from the first planned, not what the queue and the
                -- drawing before them left: they're in view already, and were held only a frame or so)
                if not waiting and plan_tile then
                    held_started = held_started or clock_ms()
                    if clock_ms() - held_started < inline_ms() then
                        plan_tile(x, y)
                        record = drawn[key]
                    end
                end
                if record and record.held then record = nil end   -- (still held: nothing drawn this frame)
            end
            if record and record ~= NOTHING_DRAWN then
                -- The record was made from the screen as it was then. If the screen now disagrees
                -- (it was planned from a frame mid-pan, or the game changed the tile) it's dropped,
                -- and plan() makes it again first thing next frame, as for a newly shown tile.
                local stale = false
                -- (UNDRAWN CELLS) a cell of the record's the game hasn't drawn yet: what goes there is
                -- left for a later frame, and a cell disagreeing with the record doesn't let it go
                local undrawn = false
                -- (STILL OURS) another of Detailed Weather's textures there: left for the frame too
                local other_ours = false
                local stale_part, undrawn_zero = nil, false   -- (SNOWSHOT) what disagreed; an empty ground layer
                local floors, edges, ramps = record.floors, record.edges, record.ramps
                -- (edges checked against the overhangs before this tile's floor changes them)
                for k = 1, #edges do
                    local e = edges[k]
                    if e.overhangs then
                        local i = index_in(e.depth, e.x, e.y)
                        -- (STILL OURS: e.kept is the flag as this edge drew it before)
                        local flag = i and floor_flags[e.depth][i]
                        if i and flag ~= e.overhangs and flag ~= e.kept then
                            if backgrounds[e.depth][i] == frame_black then
                                undrawn = true
                            else
                                stale, stale_part = true, stale_part or 'e'
                            end
                        end
                    end
                end
                for k = 1, #floors do
                    local f = floors[k]
                    local d = f.depth
                    local i = index_in(d, f.x, f.y)
                    if i then
                        local shadow_flag, floor_flag, spatter = shadow_flags[d], floor_flags[d], spatters[d]
                        -- (UNDRAWN CELLS) each read once; the black looked for only when the cell
                        -- disagrees, or for a trunk's snow, which has no piece of the game's to match
                        -- ANY FULL PIECE (grungeisdead's copy, 2026-11-17). The game picks a tile's snow
                        -- piece from the neighbours it's drawing, so a tile at the view's edge, or beside
                        -- cells it hasn't drawn yet, gets another of its full pieces than the same tile
                        -- in the middle of the view (snowshot: the floor pieces that disagreed were the
                        -- view's edges, and the line of the old view's edge after a pan or zoom). A
                        -- record checked the piece exactly, so a tile planned at an edge disagreed once
                        -- it was inside, and the other way round: kept but not drawn while the view
                        -- moved, it left a plain strip travelling with the map. Now any full piece of
                        -- the game's counts as its snow, and the record's own piece is drawn over it:
                        -- `want`, its joined piece, or the game's when the two were the same.
                        local want = f.joined or (piece_sides[f.piece] and f.piece) or nil
                        local flag_now, piece_now = floor_flag[i], want and spatter[i]
                        local other_full = want and piece_now ~= f.piece and piece_sides[piece_now] and piece_sides[f.piece]
                        if other_full then other_pieces = other_pieces + 1 end
                        local fits = flag_now == f.overhangs and (not want or piece_now == f.piece or other_full)
                        -- (STILL OURS) or the cell as this record drew it before, the game not having
                        -- redrawn it: its flag, and its piece or another of the snow's own (drawn over)
                        local drawn_before = not fits and (flag_now == f.kept or flag_now == f.overhangs)
                            and (not want or piece_now == want or snow_made[piece_now])
                        -- (the ground layer empty, but for a trunk's snow, is not drawn yet either)
                        local bg = (not fits or f.piece == 0) and backgrounds[d][i]
                        if bg and (bg == frame_black or (bg == 0 and f.piece ~= 0)) then
                            undrawn, undrawn_zero = true, undrawn_zero or bg == 0
                        elseif fits or drawn_before then
                            if drawn_before then still_drawn = still_drawn + 1 end
                            -- (a read saved where there's no skirt to clear, most snowy floors)
                            local skirt = f.skirt
                            if skirt ~= 0 then
                                local shadow = shadow_flag[i]
                                -- (LEVELS SHARED) taken from another level: this level's skirt is read the
                                -- first time the cell is the game's own drawing, as a plan here would have
                                if skirt == false and fits then f.skirt, skirt = shadow, shadow end
                                if shadow == skirt and shadow ~= 0 then shadow_flag[i] = 0 end
                            end
                            if flag_now ~= f.kept then floor_flag[i] = f.kept end
                            if want and piece_now ~= want then
                                -- what lay on the snow goes up a layer, over it, if that's still free
                                if not f.lifted then
                                    spatter[i] = want
                                elseif aboves[d][i] == 0 or aboves[d][i] == f.lifted then
                                    aboves[d][i] = f.lifted
                                    spatter[i] = want
                                end
                            end
                        elseif piece_now and piece_now ~= 0 and made[piece_now] then
                            other_ours = true
                        else
                            stale = true
                            stale_part = stale_part or ((flag_now ~= f.overhangs and flag_now ~= f.kept) and 'f' or 'p')
                        end
                    end
                end
                for k = 1, #edges do
                    local e = edges[k]
                    local d = e.depth
                    local i = index_in(d, e.x, e.y)
                    -- (STILL OURS: an edge of the snow's own there, an older one, is drawn over, and
                    -- the flag as this edge left it counts as the game's; this one there is drawn)
                    local above = i and aboves[d][i]
                    local flag = i and e.overhangs and floor_flags[d][i]
                    if above and above ~= 0 and above == e.texpos then still_drawn = still_drawn + 1 end
                    if i and (above == 0 or (snow_made[above] and above ~= e.texpos))
                            and (not e.overhangs or flag == e.overhangs or flag == e.kept) then
                        if backgrounds[d][i] == frame_black then
                            undrawn = true   -- (UNDRAWN CELLS: no edge put on a blank cell)
                        else
                            local texpos = e.texpos
                            if not texpos then
                                texpos = snowy_overhang(e.key, e.pieces, state)
                                e.texpos = texpos
                            end
                            if texpos then
                                if e.overhangs then floor_flags[d][i] = e.kept end
                                aboves[d][i] = texpos
                            end
                        end
                    end
                end
                for k = 1, #ramps do
                    local t = ramps[k]
                    local i = index_in(t.depth, t.x, t.y)
                    local shown = i and backgrounds[t.depth][i]
                    -- (STILL OURS: a snowy ramp of the snow's own there, the game not having redrawn
                    -- it, is drawn again as it is now)
                    if shown == t.base or (shown and snow_made[shown]) then
                        local texpos = snowy_texpos(t.cell, frame_number)
                        if texpos and shown ~= texpos then backgrounds[t.depth][i] = texpos end
                        if shown ~= t.base then still_drawn = still_drawn + 1 end
                    elseif shown == frame_black or shown == 0 then
                        undrawn, undrawn_zero = true, undrawn_zero or shown == 0   -- (UNDRAWN CELLS)
                    elseif shown and made[shown] then
                        other_ours = true   -- (STILL OURS: another of Detailed Weather's own, as frost's)
                    elseif shown and t.picture and picture_id(shown) == t.picture then
                        -- (RAMPS BY PICTURE) the same ramp under a new number: the record takes it
                        t.base = shown
                        count('ramps seen under a new number')
                        local texpos = snowy_texpos(t.cell, frame_number)
                        if texpos then backgrounds[t.depth][i] = texpos end
                    elseif i then
                        stale, stale_part = true, stale_part or 'r'
                    end
                end
                -- (SNOWSHOT) what the drawing found here, and the floors drawn at the view's level
                if status then
                    local c
                    if stale and frame_moved then c = stale_part or 'f'
                    elseif stale then c = (stale_part or 'f'):upper()
                    elseif undrawn then c = undrawn_zero and 'Z' or 'B'
                    elseif other_ours then c = 'O'
                    else c = record.taken and ':' or record.edge and ',' or '.' end   -- (LEVELS SHARED: ':')
                    status[key] = c
                    if c == '.' or c == ',' or c == ':' then
                        for k = 1, #floors do
                            local f = floors[k]
                            local i = f.depth == 0 and f.joined and index_in(0, f.x, f.y)
                            if i then shot_cells[#shot_cells + 1] = {i = i, j = f.joined, x = f.x, y = f.y} end
                        end
                    end
                end
                if stale and frame_moved then
                    -- (UNDRAWN CELLS) on the frame of a move the screen isn't the new view's yet
                    count('records kept for the frame of a move')
                elseif stale then
                    drawn[key], drawn_count = nil, drawn_count - 1
                    -- (SNOWY TILES LISTED, VIEW KNOWN: let go, so listed and planned again)
                    drawn_version, drawn_drops = drawn_version + 1, drawn_drops + 1
                    count('records let go')
                    -- (BLOCKS READ IN ONE COPY, QUIET REFRESH) the game changed the tile: its map is
                    -- read again at once, not when it's next due
                    local map_tile = remembered[key]
                    if map_tile then
                        map_tile.due, map_tile.due_quiet = 0, 0
                        block_info[info_key(x, y, z - (map_tile.depth or 0))] = nil
                    end
                    block_info[info_key(x, y, z)] = nil
                    -- (FILL BY QUEUE) and the tile queued, to be worked out again
                    local queue = snowy_view.queue
                    queue[#queue + 1] = x
                    queue[#queue + 1] = y
                elseif undrawn then
                    count('records left for a cell the game hadn\'t drawn yet')
                elseif other_ours then
                    count('records left for a frame: another texture of ours there')
                end
            end
        end
    end
    -- (STILL OURS: cells found still showing this snow's drawing, added once a frame)
    counts['cells still drawn from before'] = (counts['cells still drawn from before'] or 0) + still_drawn
    counts['floors over another full piece'] = (counts['floors over another full piece'] or 0) + other_pieces
    if status then shot_frame(viewport, status, shot_cells) end   -- (SNOWSHOT)
    timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
end

-- Another map or world loading: what's kept by position belongs to the old map, and what's kept by
-- texture number may name other textures in the next world, whose graphics can differ.
function forget_world()
    forget()
    for _, entry in pairs(snowy_overhangs) do
        if entry then grass.discard(entry.handle) end
    end
    snowy_overhangs, snowy_edge_texpos, snow_made, with_cache = {}, {}, {}, {}
    edge_art, cell_of_byte = nil, nil
    piece_sides, pieces_for, snow_page_art, piece_cell = nil, nil, nil, nil
    if art then art.texpos, art.fetched = {}, {} end
    for texpos in pairs(made) do made[texpos] = nil end
    refresh_at, warm_at, warm_view, warm_idle = 0, 0, nil, 0
end
