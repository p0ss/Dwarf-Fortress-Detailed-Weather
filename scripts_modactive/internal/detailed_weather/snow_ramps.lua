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

local SNOWY = 100            -- snow amount (0-255) from which a ramp is drawn snowy
local MOST_DEPTH = 8
local REMEMBER_MS = 2000     -- how long a tile's plan is kept before it's worked out again
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

local function snowy_texpos(cell, frame_number)
    local texpos = art.texpos[cell]
    if not texpos or frame_number - art.fetched[cell] > TEXPOS_RECHECK_FRAMES then
        local handle = art.handles[cell + 1]
        texpos = handle and dfhack.textures.getTexposByHandle(handle) or false
        art.texpos[cell], art.fetched[cell] = texpos, frame_number
        if texpos then made[texpos] = true end
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
        made[thin] = true
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
    local sides = ''
    for _, side in ipairs({'N', 'S', 'W', 'E'}) do if full_sides[side] then sides = sides .. side end end
    if sides == '' then return thin end
    local key = thin .. ':' .. sides
    local entry = thin_faded[key]
    if entry == nil then
        if state.budget <= 0 then return thin end
        state.budget = state.budget - 1
        local thin_px, full_px = grass.pixels_of(thin), grass.pixels_of(full)
        if not (thin_px and full_px) then thin_faded[key] = false return thin end
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
        made[entry.texpos] = true
        thin_faded[key] = entry
    end
    return entry and entry.texpos or thin
end

-- The edge art for every edging ID: grass (grass.find_edge_art) and the ground's own edges,
-- which come in the same 3x3 layout (SAND_FLOOR_1-9 and so on). Edging IDs as the game keeps them
-- in floor_flag, read in this fort: 2 dirt, 7 sand (soil that's sand), 8 pebbles, 9 stone floor.
local GROUND_EDGE_IDS = {DIRT_FLOOR = 2, SAND_FLOOR = 7, PEBBLES_FLOOR = 8, STONE_FLOOR = 9}
function all_edge_art()
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
    return edges
end

-- A snow piece with something painted over it (fallen fruit under a sapling): one texture for the
-- spatter slot, which only holds one. Cached per pair.
snow_made = snow_made or {}   -- texpos of every texture made here, so it isn't taken for fruit
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
function snowy_overhang(key, pieces, state)
    local entry = snowy_overhangs[key]
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
        entry = {handle = dfhack.textures.createTile(out, 32, 32)}
        snowy_overhangs[key] = entry
    end
    if not entry then return nil end
    if not entry.texpos then entry.texpos = dfhack.textures.getTexposByHandle(entry.handle) end
    snowy_edge_texpos[entry.texpos] = true
    made[entry.texpos] = true
    return entry.texpos
end

----------------------------------------------------------------------------------------------
-- Planning and drawing
----------------------------------------------------------------------------------------------

local WATER = 6
local EMPTY, RAMP_TOP, RAMP = df.tiletype_shape.EMPTY, df.tiletype_shape.RAMP_TOP, df.tiletype_shape.RAMP
local WALL = df.tiletype_shape.WALL
local FLOOR_LIKE = df.tiletype_shape_basic.Floor
local shape_of, floor_like, tree_wall = {}, {}, {}   -- by tiletype; df.tiletype.attrs costs ~40 us a lookup
local function shape(tiletype)
    local s = shape_of[tiletype]
    if not s then
        local attrs = df.tiletype.attrs[tiletype]
        s = attrs.shape
        shape_of[tiletype] = s
        floor_like[tiletype] = df.tiletype_shape.attrs[s].basic_shape == FLOOR_LIKE
        tree_wall[tiletype] = s == df.tiletype_shape.WALL and attrs.material == df.tiletype_material.TREE
    end
    return s
end
-- a tree's trunk
local function trunk(tiletype)
    shape(tiletype)
    return tree_wall[tiletype]
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

function forget()
    grass.forget_snow()
    remembered, remembered_count = {}, 0
    drawn, drawn_count = {}, 0
    -- the thin sheets stay loaded (load_thin_sheet); only where their textures are is asked again
    if thin_art then thin_art.pieces.texpos, thin_art.inside.texpos = {}, {} end
    thin_layout, thin_faded, corner_levels = nil, {}, {}
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
local WARM_MARGIN = 24
local DRAWN_MOST = 200000   -- (as REMEMBER_MOST)
drawn = drawn or {}
drawn_count = drawn_count or 0
refresh_at = refresh_at or 0     -- the refresh cursor, through the tiles in view
warm_at = warm_at or 0           -- the warm-up cursor, through the margin round the view
NOTHING_DRAWN = NOTHING_DRAWN or {ramps = {}, floors = {}, edges = {}}
warm_view, warm_idle = warm_view or nil, warm_idle or 0   -- the view it's warming round; tiles since it last had work

function plan(viewport)
    local started = clock_ms()
    if not cell_of_byte then cell_of_byte = cell_table() end
    local main = df.global.gps.main_viewport
    if not piece_sides then find_snow_pieces() end
    local ports, backgrounds, ramp_flags, shadow_flags, floor_flags, spatters, aboves = {}, {}, {}, {}, {}, {}, {}
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        ports[depth] = port
        backgrounds[depth], ramp_flags[depth], shadow_flags[depth], floor_flags[depth], spatters[depth], aboves[depth] =
            port.screentexpos_background, port.screentexpos_ramp_flag, port.screentexpos_shadow_flag,
            port.screentexpos_floor_flag, port.screentexpos_spatter, port.screentexpos_background_two
    end

    local block_at = grass.block_at   -- kept between plans
    -- each tile's snow, from grass.lua's per-block reading
    local now_ms = clock_ms()
    local function snow_at(_, x, y, z) return grass.snow_amount(x, y, z, now_ms) end

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
            local tiletype = block.tiletype[x % 16][y % 16]
            local s = shape(tiletype)
            if s == RAMP or floor_like[tiletype] then
                -- the snow itself says whether it's snowy: tiles under a tree's canopy count as
                -- indoors (not 'outside') but the game still lays snow on them
                local amount = snow_at(block, x, y, z)
                local outdoors = block.designation[x % 16][y % 16].outside or amount > 0
                local snowy = amount >= SNOWY
                local tile = {depth = depth, snowy_ramp = snowy and s == RAMP, snowy_floor = snowy and s ~= RAMP,
                              amount = snow_at(block, x, y, z)}
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
                            local neighbour_type = neighbour.tiletype[nx % 16][ny % 16]
                            if trunk(neighbour_type) and trunk_snowed(nx, ny, z) then
                                neighbour_snow = SNOWY
                            end
                        end
                        if neighbour_snow < SNOWY then
                            tile.keep = tile.keep | (0xff << (8 * (b - 1)))
                            local neighbour_type = neighbour and neighbour.tiletype[nx % 16][ny % 16]
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
                                    local below_shape = shape(below.tiletype[nx % 16][ny % 16])
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
                            if neighbour and shape(neighbour.tiletype[nx % 16][ny % 16]) == RAMP then
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
    -- Tiles are remembered by map position and level, so moving the view or going up and down a
    -- level reuses what's known.
    if remembered_count > REMEMBER_MOST then remembered, remembered_count = {}, 0 end
    local budget, complete = WORK_PER_PLAN, true
    local tiles, floors, bare_edges   -- the record being made for the current tile (set per tile)
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
        if id == nil then id = grass.grass_edging(x, y, z) or false edging_seen[key] = id end
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
        if not tile or now >= tile.due then
            if budget > 0 then
                budget = budget - 1
                if not tile then remembered_count = remembered_count + 1 end
                tile = work_out(x, y)
                tile.due = now + REMEMBER_MS + math.random(0, REMEMBER_MS // 2)
                remembered[key] = tile
            elseif not tile then
                complete = false   -- left for the next plan
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
        if not tile then
            -- not worked out yet
        elseif tile.snowy_ramp then
            local i = screen_index(ports[tile.depth], viewport, x, y)
            local base = i and backgrounds[tile.depth][i] or 0
            if base > 0 then
                local byte = (ramp_flags[tile.depth][i] >> 8) & 0xff
                tiles[#tiles + 1] = {x = x, y = y, depth = tile.depth, base = base, cell = cell_of_byte[byte]}
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
            if skirt ~= 0 or kept ~= overhangs or joined then
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
        if tile and tile.depth <= MOST_DEPTH and (tile.bare_floor or tile.snowy_floor) then
            tile.below = tile.below or {}   -- its own slots, apart from the open tile's on this level
            add_snowy_edges(tile.below, x, y, viewport.z - tile.depth, tile.depth, tile.snowy_sides, tile.bare_floor)
        end
    end

    if drawn_count > DRAWN_MOST then drawn, drawn_count = {}, 0 end
    local z = viewport.z
    local function plan_and_keep(x, y)
        local record = {ramps = {}, floors = {}, edges = {}}
        tiles, floors, bare_edges = record.ramps, record.floors, record.edges
        plan_tile(x, y)
        local key = (z * 4096 + x) * 4096 + y
        if not remembered[key] then return end   -- not worked out (this plan's budget ran out)
        if not drawn[key] then drawn_count = drawn_count + 1 end
        -- most tiles draw nothing: one shared marker for those, quick to pass over
        if #record.ramps == 0 and #record.floors == 0 and #record.edges == 0 then record = NOTHING_DRAWN end
        drawn[key] = record
    end
    -- (the strip a pan brought in gets the longer time; both come out of the one share)
    local new_tiles_ms = work_time.take(NEW_TILES_MS * allowance)
    local slice_ms = math.min(SLICE_MS * allowance, new_tiles_ms)
    local function out_of_time() return clock_ms() - started >= slice_ms end
    local function out_of_time_for_new() return clock_ms() - started >= new_tiles_ms end

    -- first: tiles in view with nothing kept (a newly shown strip)
    local complete = true
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
            if not drawn[(z * 4096 + x) * 4096 + y] then
                if out_of_time_for_new() then complete = false break end
                plan_and_keep(x, y)
            end
        end
        if not complete then break end
    end
    -- then: refresh a few in view, in case the game changed something there
    if complete then
        local cols, rows = viewport.x2 - viewport.x1 + 1, viewport.y2 - viewport.y1 + 1
        local cells = cols * rows
        for _ = 1, math.min(REFRESH_PER_FRAME, cells) do
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
                tile.due = now + REMEMBER_MS + math.random(0, REMEMBER_MS // 2)
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

-- Each tile's buffer index is worked out afresh from the view as it is now, and checked against
-- the buffer's size: a plan from before a zoom or resize can't write outside it.
function apply(planned, viewport)
    local started = clock_ms()
    if not art then load_art() end
    frame_number = frame_number + 1
    local backgrounds, shadow_flags, floor_flags, spatters, aboves, dims_x, dims_y = {}, {}, {}, {}, {}, {}, {}
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        backgrounds[depth], shadow_flags[depth], floor_flags[depth], spatters[depth], aboves[depth] =
            port.screentexpos_background, port.screentexpos_shadow_flag, port.screentexpos_floor_flag,
            port.screentexpos_spatter, port.screentexpos_background_two
        -- each buffer's size, read once a frame (every read of a game buffer is a userdata call)
        dims_x[depth], dims_y[depth] = port.dim_x, port.dim_y
    end
    local x1, y1 = viewport.x1, viewport.y1
    local function index_in(depth, x, y)
        local sx, sy = x - x1, y - y1
        if sx < 0 or sy < 0 or sx >= dims_x[depth] or sy >= dims_y[depth] then return nil end
        return sx * dims_y[depth] + sy
    end
    local state = {budget = OVERHANG_BAKES_PER_FRAME}
    -- this frame's planner, for tiles with nothing kept (only if planned for this very view)
    local plan_tile = planned and planned.z == viewport.z and planned.x1 == viewport.x1
        and planned.y1 == viewport.y1 and planned.plan_tile or nil
    -- One pass over the view's tiles, drawing each from what's kept for it: its snowy floor, then
    -- its snowy edges, then its snowy ramp (each only touches its own tile).
    local z = viewport.z
    local inline_plan_ms
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
            local key = (z * 4096 + x) * 4096 + y
            local record = drawn[key]
            if not record and plan_tile then
                -- (its share of the frame's work time, taken at the first tile that needs it)
                inline_plan_ms = inline_plan_ms or work_time.take(INLINE_PLAN_MS * allowance)
                if clock_ms() - started < inline_plan_ms then
                    plan_tile(x, y)
                    record = drawn[key]
                end
            end
            if record and record ~= NOTHING_DRAWN then
                -- The record was made from the screen as it was then. If the screen now disagrees
                -- (it was planned from a frame mid-pan, or the game changed the tile) it's dropped,
                -- and plan() makes it again first thing next frame, as for a newly shown tile.
                local stale = false
                local floors, edges, ramps = record.floors, record.edges, record.ramps
                -- (edges checked against the overhangs before this tile's floor changes them)
                for k = 1, #edges do
                    local e = edges[k]
                    if e.overhangs then
                        local i = index_in(e.depth, e.x, e.y)
                        if i and floor_flags[e.depth][i] ~= e.overhangs then stale = true end
                    end
                end
                for k = 1, #floors do
                    local f = floors[k]
                    local d = f.depth
                    local i = index_in(d, f.x, f.y)
                    if i then
                        local shadow_flag, floor_flag, spatter = shadow_flags[d], floor_flags[d], spatters[d]
                        if shadow_flag[i] == f.skirt then shadow_flag[i] = 0 end
                        if floor_flag[i] == f.overhangs then floor_flag[i] = f.kept else stale = true end
                        if f.joined and spatter[i] ~= f.piece then stale = true end
                        if f.joined and spatter[i] == f.piece then
                            -- what lay on the snow goes up a layer, over it, if that's still free
                            if not f.lifted then
                                spatter[i] = f.joined
                            elseif aboves[d][i] == 0 then
                                aboves[d][i] = f.lifted
                                spatter[i] = f.joined
                            end
                        end
                    end
                end
                for k = 1, #edges do
                    local e = edges[k]
                    local d = e.depth
                    local i = index_in(d, e.x, e.y)
                    if i and aboves[d][i] == 0 and (not e.overhangs or floor_flags[d][i] == e.overhangs) then
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
                for k = 1, #ramps do
                    local t = ramps[k]
                    local i = index_in(t.depth, t.x, t.y)
                    if i and backgrounds[t.depth][i] == t.base then
                        local texpos = snowy_texpos(t.cell, frame_number)
                        if texpos then backgrounds[t.depth][i] = texpos end
                    elseif i then
                        stale = true
                    end
                end
                if stale then drawn[key], drawn_count = nil, drawn_count - 1 end
            end
        end
    end
    timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
end

-- Another map or world loading: what's kept by position belongs to the old map, and what's kept by
-- texture number may name other textures in the next world, whose graphics can differ.
function forget_world()
    forget()
    for _, entry in pairs(snowy_overhangs) do
        if entry then grass.discard(entry.handle, 'snow on ramps') end
    end
    snowy_overhangs, snowy_edge_texpos, snow_made, with_cache = {}, {}, {}, {}
    edge_art, cell_of_byte = nil, nil
    piece_sides, pieces_for, snow_page_art, piece_cell = nil, nil, nil, nil
    if art then art.texpos, art.fetched = {}, {} end
    for texpos in pairs(made) do made[texpos] = nil end
    refresh_at, warm_at, warm_view, warm_idle = 0, 0, nil, 0
end
