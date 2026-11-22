-- Frost and a temperature tint for Detailed Weather.
--
-- The game knows each tile's temperature (block.temperature_1: 10000 is freezing, 9 units are
-- 5 C), but graphics mode only shows it once water freezes. This draws, over each bare outdoor
-- floor and ramp, rime that forms on the ground's own bright points (the crests of sand ripples,
-- the tops of pebbles, blade tips) below about 2 C, spreading the colder it gets, and a faint
-- cool or warm cast at the extremes.
--
-- The frost follows the texture under it, so it's made from it, baked once per look and cached
-- for the session (BAKE_MS of baking a frame, so new ground's frost fades in over a moment):
--
--   floors  a see-through frost tile, from the ground and the grass overhangs on it (Detailed
--           Landscapes' grass edges reach well onto neighbouring tiles), put in the layer shrubs
--           and boulders use (screentexpos_background_two). That draws over the overhangs and under
--           items, buildings and creatures; it's empty on plain ground. Tiles with a shrub,
--           sapling or boulder there, or with snow, blood or mud (the spatter layer), are left.
--           Where snow_ramps.lua has put a snowy grass edge in that layer, the frost goes under it
--           in one baked texture (the rime, then the snowy edge over it).
--   ramps   the game never draws the spatter layer on ramps, so a ramp's own texture is baked
--           with the frost on it and swapped in (snowy ramps are swapped for snow instead, in
--           snow_ramps.lua, first).
--
-- Heat, the warm half: where frost picks out the ground's bright points, heat deepens its shadows
-- (prototyped in tools/weather/heat_test.py), from HEAT_STARTS to HEAT_FULL:
--   dirt     drying cracks, a network of plates from art/heat_patterns.png (4 tiles across,
--            wrapping, each tile taking its piece by position so neighbours join), widening and
--            branching as it heats; thin, so only each crack's middle goes fully dark, its floor
--            the colour of the dirt's own hollows, its far (south) wall catching the light. The
--            plates make up for what the cracks take, so the tile's mean lightness stays as the
--            dirt's (the ground is matched by lightness in Detailed Landscapes and Rounded Hills)
--   stone,   the darkest pixels deepen, more the hotter
--   pebbles
--   sand     a little more ripple contrast, and a fine relative grain (glints and grain shadows)
-- Those pixels are baked opaque, with exactly the colour wanted, into the same frost tile. Which
-- ground a tile is comes from the graphics tokens its texture was named by (DIRT_FLOOR, ...).
-- Not yet: ramps, and keeping wet ground from cracking while it rains.
--
-- (The old floor effects above are off: the looks, colour.lua, replaced them. What's drawn on
-- floors now is the dry cracks: when the look is drier than average, each outdoor dirt and stone
-- floor's texture, already in the look's colours, is swapped for a copy with its piece of the
-- heat patterns' cracks, faint and thin at the first dry step, widest when very dry and hot.)
--
-- As with snow on ramps, the levels below seen through open space are in the lower viewports, and
-- tiles are remembered for a few seconds and worked out a few hundred a frame.
--
-- NATIVE CRACKS (grungeisdead's copy, 2026-11-20, test 15R): with the hook DLL swapping the colour, the
-- DLL puts the cracks in (detailed_weather_dll.cpp: CRACKS IN PLACE). This file still works out which
-- map tiles may crack and hands them over, and makes the cracked copies the DLL asks for; apply() no
-- longer goes over the view's tiles.
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)
local clock_s = reqscript('internal/detailed_weather/clock').s     -- and in seconds, for timing short work

local grass = reqscript('internal/detailed_weather/grass')   -- texture pixels, grass edge art
-- every texture Detailed Weather makes (frost, snow...), shared, so the colour swap leaves them be
_G.detailed_weather_made = _G.detailed_weather_made or {}
local made = _G.detailed_weather_made
local snow_ramps = reqscript('internal/detailed_weather/snow_ramps')   -- its snowy edges
local colour = reqscript('internal/detailed_weather/colour')           -- the look, for ramps
local looks = reqscript('internal/detailed_weather/looks')             -- how ramps are redrawn for it
local work_time = reqscript('internal/detailed_weather/work_time')   -- the frame's shared time for background work

local MOST_DEPTH = 8
local SNOWY = 100            -- snow amount from which the game draws snow (as snow_ramps.lua)
-- (grungeisdead's copy, 2026-11-17: was 3000) Each tile in view was worked out again every 3 to 4.5 s,
-- several DFHack reads each, to follow a ground temperature that changes over game hours: most of
-- frost's planning time (detailed_weather details: 1.5 ms a frame). A ramp now takes up to 15 s to
-- show a change of band or a thaw.
local REMEMBER_MS = 10000    -- temperatures change slowly
local WORK_PER_PLAN = 300
-- (grungeisdead's copy, 2026-11-16: was 60000) Past this many tiles kept, all are forgotten and the
-- view worked out again, every ramp in it showing the game's colour meanwhile. With the levels just
-- above and below kept too (plan: THE LEVELS BESIDE), 60000 came round quickly.
local REMEMBER_MOST = 150000
local BAKE_MS = 2
-- (grungeisdead's copy, 2026-11-16) When any tile waited for its bake last frame, this frame bakes
-- for this long instead, as colour.lua's BUSY_BUILD_MS does: a world's first look had 376 ramp
-- textures to bake, 2 ms a frame, and its ramps flipped one by one from the game's colour to the
-- look's over several seconds (13,577 waits counted). Back to BAKE_MS once nothing waits.
local BUSY_BAKE_MS = 8
-- (grungeisdead's copy, 2026-11-17) NEW VIEW BAKES: for the first frames on another level or after a
-- zoom (plan's new_view_left), this long, so a new level's ramps get their frost in its first frame.
-- At BAKE_MS they showed the game's colour and changed a moment later (seen in play on level changes).
local NEW_VIEW_BAKE_MS = 20
-- THE NEXT LOOK AHEAD: what's left of a frame's baking, up to this long, goes to the next look's ramps
local AHEAD_MS = 2
waited_last_frame = waited_last_frame or false
local BAKED_MOST = 6000      -- 4 KB each; past this, the cache starts afresh
local TEXPOS_RECHECK_FRAMES = 600
local TILE = 32

local BAND_C = 3                   -- degrees per temperature band
local FROST_STARTS, FROST_FULL = 2, -12
local FROST_MOST = 0.45            -- share of a tile's pixels rimed at the coldest
local FROST_OPACITY = 0.55
local FROST = {222, 233, 244}
local SPECKLE = 0.15               -- a little noise in which bright pixels go first, so ties break unevenly
local COOL_FROM, WARM_FROM, WARM_FULL = 10, 20, 38

-- heat (heat_test.py's values)
local HEAT_STARTS, HEAT_FULL = 24, 38
local HEAT_TILES = 4
local CRACK_DARK, CRACK_LIT, PLATE_PALE = 0.55, 1.3, 0.06
local CRACK_THIN = 0.45      -- share of a crack's width that fades in at its sides (crack_compare.py's E)
local ROCK_SHARE, ROCK_DARK = 0.15, 0.65   -- stone and pebbles: darkest share deepened (rock_compare.py's C)
local STONE_CRACK_DARK = 0.72              -- and stone's thin cracks along the main plates (its E)
local SAND_CONTRAST, SAND_GLINTS, SAND_GRAINS, SAND_GLINT_LIFT, SAND_GRAIN_DARK = 0.25, 0.12, 0.12, 0.08, 0.08
local TINT_MOST = 0.08
local COOL_TINT = {150, 178, 214}
local WARM_TINT = {255, 196, 138}

-- floor_flag: one byte per side, S, W, E, N, each the edging ID of the neighbour whose overhang
-- lands on that side of this tile (see grass.lua)
local SIDE_NAMES = {'S', 'W', 'E', 'N'}

forced_celsius = forced_celsius or nil   -- `detailed_weather temperature N`, for testing
-- The old floor effects by each tile's temperature band (tint, rime, heat): replaced by the looks
-- (colour.lua, looks.lua), kept behind this for comparison. Ramps are redrawn either way.
floor_effects = floor_effects or false

local function celsius(units) return (units - 10000) * 5 / 9 end

local function between(value, start, full)
    local share = (value - start) / (full - start)
    return share < 0 and 0 or share > 1 and 1 or share
end

-- A tile's temperature band, or nil if nothing is drawn at it (mild weather).
local function band_of(degrees)
    local band = math.floor(degrees / BAND_C)
    local middle = (band + 0.5) * BAND_C
    if middle >= COOL_FROM and middle <= WARM_FROM then return nil end
    return band
end

----------------------------------------------------------------------------------------------
-- Baking
----------------------------------------------------------------------------------------------

baked = baked or {}       -- key -> {handle, texpos, fetched} or false
baked_count = baked_count or 0
frame_number = frame_number or 0
local edge_art            -- grass edging ID -> side name -> texpos (grass.find_edge_art)

generation = generation or 0   -- bumped when the cache is cleared, so tiles drop what they kept
seen_generation = seen_generation or nil   -- colour.copies_generation when the bakes were made
allowance = allowance or 1   -- the share of its usual time a frame (settings.lua: less at low)

-- COUNTS (grungeisdead's copy, 2026-11-16), for `detailed_weather details`: what the drawing
-- baked and why, since details last showed them. Added to find why ramps and the ground change
-- shade as the view moves: bakes are keyed by the texture number the game drew, so if the game
-- gives a ramp a new number as the view moves, each new number is baked again, 2 ms a frame, and
-- the tile shows the game's own colour until its bake is made. new_base counts a ramp tile whose
-- game texture changed under it; ramp_bases the different ramp textures seen.
counts = counts or {}
local function count(what) counts[what] = (counts[what] or 0) + 1 end

function clear_cache()
    count('clears')
    generation = generation + 1
    for _, entry in pairs(baked) do
        if entry then grass.discard(entry.handle) end
    end
    baked, baked_count = {}, 0
    cracked_from = {}
    edge_art = nil
end

-- The look of a band: tint colour and amount, and the share of pixels rimed.
local function band_look(band)
    local degrees = (band + 0.5) * BAND_C
    local tint, tint_amount = COOL_TINT, 0
    if degrees < COOL_FROM then
        tint_amount = between(degrees, COOL_FROM, FROST_FULL) * TINT_MOST
    elseif degrees > WARM_FROM then
        tint, tint_amount = WARM_TINT, between(degrees, WARM_FROM, WARM_FULL) * TINT_MOST
    end
    return tint, tint_amount, between(degrees, FROST_STARTS, FROST_FULL) * FROST_MOST
end

local function pack(r, g, b, a) return (a << 24) | (b << 16) | (g << 8) | r end
local function round_byte(v) v = math.floor(v + 0.5) return v < 0 and 0 or v > 255 and 255 or v end

----------------------------------------------------------------------------------------------
-- Heat
----------------------------------------------------------------------------------------------

local art_dir = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or '') .. '../../../art/'

-- The heat patterns, per piece of the 4x4-tile grid: main and fine crack distances (px) and the
-- sand's grain rank (0-1), each 32 * 32.
local patterns
local pattern_handles   -- (DRY CRACKS: the pieces' textures, loaded once, for their pixels' addresses too)
local function heat_pattern_handles()
    if not pattern_handles then
        pattern_handles = dfhack.textures.loadTileset(art_dir .. 'heat_patterns.png', TILE, TILE, true)
    end
    return pattern_handles
end
local function heat_patterns()
    if patterns then return patterns end
    patterns = {}
    local handles = heat_pattern_handles()
    for piece = 0, HEAT_TILES * HEAT_TILES - 1 do
        local px = grass.pixels_of(dfhack.textures.getTexposByHandle(handles[piece + 1]))
        local main, fine, grain = {}, {}, {}
        for n, p in ipairs(px or {}) do main[n], fine[n], grain[n] = p[1] / 16, p[2] / 16, p[3] / 255 end
        patterns[piece] = {main = main, fine = fine, grain = grain}
    end
    return patterns
end

----------------------------------------------------------------------------------------------
-- Dry cracks
----------------------------------------------------------------------------------------------

-- Each cracked texture's ground, as drawn before the cracks (for paths.lua's soil).
cracked_from = cracked_from or {}
function uncracked(texpos) return cracked_from[texpos] or texpos end

-- How cracked the ground is in a look: 0 (average or wetter) to 1. The dry steps crack it, the
-- driest most, and heat opens the cracks further. nil if it isn't cracked.
local CRACK_FAINTEST = 0.25    -- at the first dry step, mild
local CRACK_HEAT = 0.2         -- full heat adds this much
local function crack_amount(look)
    if not look then return nil end
    local dryness = 1 - look.wet / (looks.WET_STEPS / 2)
    if dryness <= 0 then return nil end
    local heat = math.max(0, look.temperature / looks.WARM_STEPS)
    local amount = CRACK_FAINTEST + (1 - CRACK_FAINTEST - CRACK_HEAT) * (2 * dryness - 1) + CRACK_HEAT * heat
    return math.max(0.05, math.min(1, amount))
end

-- The cracks on one ground texture as drawn (already in the look's colours), for its place on the
-- heat patterns' grid (`piece`), so neighbouring tiles' cracks join. Dirt cracks into plates,
-- stone along thin joints (its darkest parts are already deepened by looks.lua), pebbles in the
-- soil between the stones (their darker half), the stones left whole. Faint cracks are
-- thin and shallow; the tile's mean lightness is kept. `px` is the texture's pixels ({r, g, b, a}
-- each); returns them cracked, packed.
local CRACK_KINDS = {dirt = true, stone = true, pebbles = true}
local function cracked(px, kind, amount, piece)
    local red, green, blue = {}, {}, {}
    for n = 1, TILE * TILE do red[n], green[n], blue[n] = px[n][1], px[n][2], px[n][3] end
    local lum = {}
    for n = 1, TILE * TILE do lum[n] = red[n] * 0.299 + green[n] * 0.587 + blue[n] * 0.114 end
    local sorted = {}
    for n = 1, TILE * TILE do sorted[n] = lum[n] end
    table.sort(sorted)
    -- the colour of the ground's own hollows (its darkest tenth), for the crack floors
    local cut = sorted[math.floor(0.1 * #sorted + 0.5)]
    local hr, hg, hb, count = 0, 0, 0, 0
    for n = 1, TILE * TILE do
        if lum[n] <= cut then hr, hg, hb, count = hr + red[n], hg + green[n], hb + blue[n], count + 1 end
    end
    local k = (kind == 'dirt' and CRACK_DARK * 1.3 or STONE_CRACK_DARK) / math.max(1, count)
    local hollow = {hr * k, hg * k, hb * k}
    local p = heat_patterns()[piece]
    local above = heat_patterns()[(piece - HEAT_TILES) % (HEAT_TILES * HEAT_TILES)]   -- the piece north
    -- faint cracks: the main network only, about a pixel wide and barely darker than the ground
    -- (hairlines); drier and hotter, wider, darker, and finer cracks branch between them
    local depth = 0.2 + 0.8 * amount * amount
    local width = kind == 'stone' and 0.8 + 0.5 * amount or 1.0 + 0.9 * amount
    local fine_width = kind == 'stone' and 0 or math.max(0, (amount - 0.5) * 2) * 1.0
    local median = sorted[#sorted // 2]
    local function crack_at(pattern, n)
        local a = (math.max(width - pattern.main[n], fine_width - pattern.fine[n]) - CRACK_THIN) / (1 - CRACK_THIN)
        a = (a < 0 and 0 or a > 1 and 1 or a) * depth
        if kind == 'pebbles' and a > 0 then
            local gap = (median - lum[n]) / 16 + 0.5   -- 1 in the soil, 0 on the stones
            a = a * (gap < 0 and 0 or gap > 1 and 1 or gap)
        end
        return a
    end
    local plate = kind == 'dirt' and 1 + PLATE_PALE * amount or 1
    local out, cracks = {}, {}
    local lum_before, lum_after, open = 0, 0, 0
    for n = 1, TILE * TILE do
        local crack = crack_at(p, n)
        local north = n > TILE and crack_at(p, n - TILE) or crack_at(above, n + TILE * (TILE - 1))
        local lit = north - crack       -- the far (south) wall catches the light
        lit = lit > 0 and lit or 0
        local f = plate * (1 + lit * (CRACK_LIT - 1))
        local c = {red[n] * f, green[n] * f, blue[n] * f}
        for ch = 1, 3 do c[ch] = c[ch] + (hollow[ch] - c[ch]) * crack end
        out[n], cracks[n] = c, crack
        lum_before = lum_before + lum[n]
        lum_after = lum_after + c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114
        open = open + (1 - crack)
    end
    -- keep the tile's mean lightness: the plates (not the cracks) brighten to make up for it
    local spare = (lum_after > 0 and open > 0) and (lum_before / lum_after - 1) * TILE * TILE / open or 0
    local packed = {}
    for n = 1, TILE * TILE do
        local f, c = 1 + spare * (1 - cracks[n]), out[n]
        packed[n] = pack(round_byte(c[1] * f), round_byte(c[2] * f), round_byte(c[3] * f), px[n][4])
    end
    return packed
end

-- DRY CRACKS (grungeisdead's copy, 2026-11-20, test 15O): the cracks painted by the hook DLL instead
-- (colour.lua: native_crack, native_redraw), bit for bit as cracked() above (the DLL's harness checks it
-- against this file's own cracked(): check/crack/compare.py). In a dry hot look in play, 301 to 389
-- bakes took 2.05 to 3.50 ms each here, and ramps showed the game's colours while they waited; the DLL
-- takes about 0.06 ms. What it needs: the kind, the amount, and where this tile's piece of the heat
-- patterns and the piece north of it keep their pixels (read again each time, never kept: an address
-- kept could outlive its texture). nil when either can't be read in one run: baked here as before.
local CRACK_KIND_CODE = {dirt = 1, stone = 2, pebbles = 3}
local function crack_spec(kind, amount, piece)
    local code = CRACK_KIND_CODE[kind]
    if not code then return nil end
    local handles = heat_pattern_handles()
    local function address_of(k)
        local h = handles and handles[k + 1]
        return h and grass.original_address(dfhack.textures.getTexposByHandle(h)) or nil
    end
    local here = address_of(piece)
    local north = address_of((piece - HEAT_TILES) % (HEAT_TILES * HEAT_TILES))
    if not here or not north then return nil end
    return {kind = code, amount = amount, piece = piece, here = here, north = north}
end

-- A ground texture with its cracks, or nil.
local function bake_cracks(base, kind, amount, piece)
    local px = grass.pixels_of(base)
    return px and cracked(px, kind, amount, piece)
end

-- Packed pixels (as looks.redraw returns) with the cracks on them, for ramps.
local function crack_packed(packed, kind, amount, piece)
    local px = {}
    for n = 1, TILE * TILE do
        local v = packed[n]
        px[n] = {v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff}
    end
    return cracked(px, kind, amount, piece)
end

-- The pre-rendered hot ground (art/heat_ground.png, built by tools/weather/make_heat_ground.py):
-- every full ground tile Detailed Landscapes draws, at each heat band, for each place on the heat
-- patterns' grid, in the colour look and tint for its temperature. A hot tile's ground texture is
-- swapped for its version, so nothing is baked as the view moves and the game draws the grass
-- edges over it as usual. Ground from other mods isn't in it, and is baked as before.
local hot_ground
local function load_hot_ground()
    local sheet = dofile(art_dir .. 'heat_ground_sheet.lua')
    local index_of = {}
    for n, g in ipairs(sheet.ground) do
        -- only where that page's tile is what the game draws for it (another mod may replace it)
        local texpos = grass.page_texpos(g.page, g.x, g.y)
        if texpos and not index_of[texpos] then index_of[texpos] = n end
    end
    local band_row = {}
    for n, band in ipairs(sheet.bands) do band_row[band] = n - 1 end
    hot_ground = {handles = dfhack.textures.loadTileset(art_dir .. 'heat_ground.png', TILE, TILE, true),
                  sheet = sheet, index_of = index_of, band_row = band_row, texpos = {}, kind_of = {},
                  first = sheet.bands[1], last = sheet.bands[#sheet.bands]}
end

-- The pre-rendered texture for ground texture `base` at `band` on map tile (x, y), or nil.
local function hot_ground_texpos(base, band, x, y)
    if not hot_ground then load_hot_ground() end
    local ground = hot_ground.index_of[colour.original_of(base)]
    if not ground or band < hot_ground.first then return nil end
    if band > hot_ground.last then band = hot_ground.last end
    local sheet = hot_ground.sheet
    local piece = (y % HEAT_TILES) * HEAT_TILES + x % HEAT_TILES
    local n = ((ground - 1) * #sheet.bands + hot_ground.band_row[band]) * sheet.pieces + piece + 1
    local texpos = hot_ground.texpos[n]
    if texpos == nil then
        local handle = hot_ground.handles[n]
        texpos = handle and dfhack.textures.getTexposByHandle(handle) or false
        hot_ground.texpos[n] = texpos
        if texpos then
            made[texpos] = true
            hot_ground.kind_of[texpos] = sheet.ground[ground].kind
        end
    end
    return texpos or nil
end

-- Which ground each of the game's floor textures is, from the tokens that name them.
local GROUND_TOKENS = {DIRT_FLOOR = 'dirt', SAND_FLOOR = 'sand', STONE_FLOOR = 'stone', PEBBLES = 'pebbles'}
local GROUND_CLASSES = {dirt = true, sand = true, stone = true, pebbles = true}
local kind_of_texpos
local function ground_kind(base)
    if not kind_of_texpos then
        kind_of_texpos = {}
        for _, mod in ipairs(require('script-manager').get_active_mods()) do
            for _, path in ipairs(grass.graphics_files(mod.path)) do
                local file = io.open(path, 'r')
                local text = file and file:read('a') or ''
                if file then file:close() end
                for page, x, y, token in text:gmatch('%[TILE_GRAPHICS:([%w_]+):(%d+):(%d+):([%u_]+)') do
                    -- every sand colour: SAND_FLOOR, SAND_RED_FLOOR, SAND_BLACK_FLOOR...
                    if token:match('^SAND_%u*_?FLOOR') then token = 'SAND_FLOOR' end
                    for prefix, kind in pairs(GROUND_TOKENS) do
                        if token:sub(1, #prefix) == prefix then
                            local texpos = grass.page_texpos(page, tonumber(x), tonumber(y))
                            if texpos then kind_of_texpos[texpos] = kind end
                        end
                    end
                end
            end
        end
    end
    local original = colour.original_of(base)
    local kind = kind_of_texpos[original] or (hot_ground and hot_ground.kind_of[base])
    if kind then return kind end
    -- else as the looks class it (some of Detailed Landscapes' dirt goes by other tokens)
    local class = colour.class_of(original)
    return GROUND_CLASSES[class] and class or nil
end

local function heat_of(band)
    local degrees = (band + 0.5) * BAND_C
    local heat = (degrees - HEAT_STARTS) / (HEAT_FULL - HEAT_STARTS)
    return heat < 0 and 0 or heat > 1 and 1 or heat
end

-- The heat's colour for each pixel that changes, as {n -> {r, g, b}}, from the tile as drawn.
local function heat_pixels(kind, heat, red, green, blue, piece)
    local out = {}
    local lum = {}
    for n = 1, TILE * TILE do lum[n] = red[n] * 0.299 + green[n] * 0.587 + blue[n] * 0.114 end
    local sorted
    local function quantile(share)
        if not sorted then
            sorted = {}
            for n = 1, TILE * TILE do sorted[n] = lum[n] end
            table.sort(sorted)
        end
        return sorted[math.max(1, math.min(#sorted, math.floor(share * #sorted + 0.5)))]
    end
    local function scale(n, f) out[n] = {red[n] * f, green[n] * f, blue[n] * f} end
    local function deepen(share, dark)
        if share <= 0 then return end
        local cut = quantile(share)
        for n = 1, TILE * TILE do
            local depth = (cut - lum[n]) / 18 + 0.5
            if depth > 0 then
                depth = depth > 1 and 1 or depth
                local f = 1 - depth * (1 - dark)
                local c = out[n] or {red[n], green[n], blue[n]}
                out[n] = {c[1] * f, c[2] * f, c[3] * f}
            end
        end
    end
    if kind == 'dirt' then
        local p = heat_patterns()[piece]
        local above = heat_patterns()[(piece - HEAT_TILES) % (HEAT_TILES * HEAT_TILES)]   -- the piece north
        local width = 0.2 + 0.8 * heat
        local fine_width = math.max(0, (heat - 0.5) * 2) * 0.6
        local function crack_at(pattern, n)
            local a = (math.max(width - pattern.main[n], fine_width - pattern.fine[n]) - CRACK_THIN) / (1 - CRACK_THIN)
            return a < 0 and 0 or a > 1 and 1 or a
        end
        -- the colour of the dirt's own hollows (its darkest tenth), for the crack floors
        local cut = quantile(0.1)
        local hr, hg, hb, count = 0, 0, 0, 0
        for n = 1, TILE * TILE do
            if lum[n] <= cut then hr, hg, hb, count = hr + red[n], hg + green[n], hb + blue[n], count + 1 end
        end
        local k = CRACK_DARK * 1.3 / math.max(1, count)
        local hollow = {hr * k, hg * k, hb * k}
        local plate = 1 + PLATE_PALE * heat
        local cracks = {}
        local lum_before, lum_after, open = 0, 0, 0
        for n = 1, TILE * TILE do
            local crack = crack_at(p, n)
            local north = n > TILE and crack_at(p, n - TILE) or crack_at(above, n + TILE * (TILE - 1))
            local lit = north - crack
            lit = lit > 0 and lit or 0
            local f = plate * (1 + lit * (CRACK_LIT - 1))
            local c = {red[n] * f, green[n] * f, blue[n] * f}
            for ch = 1, 3 do c[ch] = c[ch] + (hollow[ch] - c[ch]) * crack end
            out[n], cracks[n] = c, crack
            lum_before = lum_before + lum[n]
            lum_after = lum_after + c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114
            open = open + (1 - crack)
        end
        -- keep the tile's mean lightness: the plates (not the cracks) brighten to make up for it
        if lum_after > 0 and open > 0 then
            local spare = (lum_before / lum_after - 1) * TILE * TILE / open
            for n = 1, TILE * TILE do
                local f = 1 + spare * (1 - cracks[n])
                local c = out[n]
                c[1], c[2], c[3] = c[1] * f, c[2] * f, c[3] * f
            end
        end
    elseif kind == 'stone' or kind == 'pebbles' then
        -- the darkest share deepened, stone's thin cracks along the main plates, the rest
        -- brightened to keep the tile's mean lightness (as make_heat_ground.py)
        local cut = quantile(ROCK_SHARE * heat)
        local hr, hg, hb, count = 0, 0, 0, 0
        local hollow_cut = quantile(0.1)
        for n = 1, TILE * TILE do
            if lum[n] <= hollow_cut then hr, hg, hb, count = hr + red[n], hg + green[n], hb + blue[n], count + 1 end
        end
        local k = STONE_CRACK_DARK / math.max(1, count)
        local hollow = {hr * k, hg * k, hb * k}
        local p = heat_patterns()[piece]
        local above = heat_patterns()[(piece - HEAT_TILES) % (HEAT_TILES * HEAT_TILES)]
        local function crack_at(pattern, n)
            if kind ~= 'stone' then return 0 end
            local a = heat - pattern.main[n]
            a = a < 0 and 0 or a > 1 and 1 or a
            a = (a - CRACK_THIN) / (1 - CRACK_THIN)
            return a < 0 and 0 or a
        end
        local rests = {}
        local lum_after, rest_sum = 0, 0
        for n = 1, TILE * TILE do
            local depth = (cut - lum[n]) / 18 + 0.5
            depth = depth < 0 and 0 or depth > 1 and 1 or depth
            local f = 1 - depth * (1 - ROCK_DARK)
            local crack = crack_at(p, n)
            local north = n > TILE and crack_at(p, n - TILE) or crack_at(above, n + TILE * (TILE - 1))
            local lit = north - crack
            f = f * (1 + (lit > 0 and lit or 0) * (CRACK_LIT - 1))
            local c = {red[n] * f, green[n] * f, blue[n] * f}
            for ch = 1, 3 do c[ch] = c[ch] + (hollow[ch] - c[ch]) * crack end
            out[n] = c
            local rest = 1 - (crack > depth and crack or depth)
            rests[n], rest_sum = rest, rest_sum + rest
            lum_after = lum_after + c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114
        end
        local lum_before = 0
        for n = 1, TILE * TILE do lum_before = lum_before + lum[n] end
        if lum_after > 0 and rest_sum > 0 then
            local spare = (lum_before / lum_after - 1) * TILE * TILE / rest_sum
            for n = 1, TILE * TILE do
                local f, c = 1 + spare * rests[n], out[n]
                c[1], c[2], c[3] = c[1] * f, c[2] * f, c[3] * f
            end
        end
    elseif kind == 'sand' then
        local p = heat_patterns()[piece]
        local mean = 0
        for n = 1, TILE * TILE do mean = mean + lum[n] end
        mean = mean / (TILE * TILE)
        local contrast = 1 + SAND_CONTRAST * heat
        for n = 1, TILE * TILE do
            local c = {mean + (red[n] - mean) * contrast, mean + (green[n] - mean) * contrast,
                       mean + (blue[n] - mean) * contrast}
            local g = p.grain[n]
            local f = g > 1 - SAND_GLINTS * heat and 1 + SAND_GLINT_LIFT or g < SAND_GRAINS * heat and 1 - SAND_GRAIN_DARK or 1
            out[n] = {c[1] * f, c[2] * f, c[3] * f}
        end
    end
    return out
end

-- The tile as drawn, kept per look of it (`key`): its channels, and its visible pixels from the
-- brightest down (the speckle breaking ties unevenly), so a band's rime is the top of that list.
-- Below freezing every rimed pixel bakes to one colour and every other to another, so with this
-- kept, a new band's frost is two colours filled in. `layers` is the base's pixels then the pieces
-- painted over it; `m` a colour matrix for it, or nil.
local BUCKETS = 1024
local DRAWN_MOST = 600       -- ~50 KB each
drawn_cache, drawn_count = drawn_cache or {}, drawn_count or 0
local function as_drawn(key, layers, m)
    local d = drawn_cache[key]
    if d ~= nil then return d or nil end
    if drawn_count >= DRAWN_MOST then drawn_cache, drawn_count = {}, 0 end
    drawn_count = drawn_count + 1
    local red, green, blue, alpha = {}, {}, {}, {}
    for n = 1, TILE * TILE do red[n], green[n], blue[n], alpha[n] = 0, 0, 0, 0 end
    for _, texpos in ipairs(layers) do
        local top = grass.pixels_of(texpos)
        if top then
            for n = 1, TILE * TILE do
                local t = top[n]
                local a = t[4]
                if a == 255 then
                    red[n], green[n], blue[n], alpha[n] = t[1], t[2], t[3], 255
                elseif a > 0 then
                    local k = a / 255
                    red[n] = t[1] * k + red[n] * (1 - k)
                    green[n] = t[2] * k + green[n] * (1 - k)
                    blue[n] = t[3] * k + blue[n] * (1 - k)
                    if a > alpha[n] then alpha[n] = a end
                end
            end
        elseif _ == 1 and texpos ~= 0 then
            drawn_cache[key] = false
            return nil
        end
    end
    if m then
        for n = 1, TILE * TILE do
            local r, g, b = red[n], green[n], blue[n]
            local nr, ng, nb = m[1] * r + m[2] * g + m[3] * b, m[4] * r + m[5] * g + m[6] * b, m[7] * r + m[8] * g + m[9] * b
            red[n] = nr < 0 and 0 or nr > 255 and 255 or nr
            green[n] = ng < 0 and 0 or ng > 255 and 255 or ng
            blue[n] = nb < 0 and 0 or nb > 255 and 255 or nb
        end
    end
    -- brightest first: counted into buckets by brightness, each bucket in pixel order
    local buckets = {}
    for n = 1, TILE * TILE do
        if alpha[n] > 0 then
            local b = (red[n] * 0.299 + green[n] * 0.587 + blue[n] * 0.114) / 255
            local noise = ((n * 2654435761) % 1000) / 1000   -- fixed per pixel
            local bucket = math.floor((b + SPECKLE * noise) / (1 + SPECKLE) * (BUCKETS - 1))
            local list = buckets[bucket]
            if not list then list = {} buckets[bucket] = list end
            list[#list + 1] = n
        end
    end
    local order = {}
    for bucket = BUCKETS - 1, 0, -1 do
        local list = buckets[bucket]
        if list then for _, n in ipairs(list) do order[#order + 1] = n end end
    end
    d = {red = red, green = green, blue = blue, alpha = alpha, order = order}
    drawn_cache[key] = d
    return d
end

-- How many of a tile's pixels rime at `share`.
local function rimed_count(d, share) return math.floor(share * #d.order + 0.5) end


-- The two see-through colours a floor's frost is made of: the tint alone, and rime over the tint.
local function frost_colours(band)
    local tint, tint_amount, share = band_look(band)
    local plain = 0
    if tint_amount > 0 then
        plain = pack(round_byte(tint[1]), round_byte(tint[2]), round_byte(tint[3]), round_byte(tint_amount * 255))
    end
    local alpha = FROST_OPACITY + tint_amount * (1 - FROST_OPACITY)
    local rimed = pack(round_byte((FROST[1] * FROST_OPACITY + tint[1] * tint_amount * (1 - FROST_OPACITY)) / alpha),
                       round_byte((FROST[2] * FROST_OPACITY + tint[2] * tint_amount * (1 - FROST_OPACITY)) / alpha),
                       round_byte((FROST[3] * FROST_OPACITY + tint[3] * tint_amount * (1 - FROST_OPACITY)) / alpha),
                       round_byte(alpha * 255))
    return plain, rimed, share, tint, tint_amount
end

-- A floor's frost: see-through, made from the ground with its grass overhangs painted on
-- (`drawn_key` names that combination). In the heat, `kind` and `piece` (its place on the heat
-- patterns' grid) add the heat's pixels, opaque.
local function bake_floor(base, overhangs, drawn_key, band, kind, piece)
    local layers = {base}
    for _, texpos in ipairs(overhangs) do layers[#layers + 1] = texpos end
    local d = as_drawn(drawn_key, layers)
    if not d then return nil end
    local plain, rimed, share, tint, tint_amount = frost_colours(band)
    local out = {}
    for n = 1, TILE * TILE do out[n] = plain end
    local order = d.order
    for k = 1, rimed_count(d, share) do out[order[k]] = rimed end
    local heat = kind and heat_of(band) or 0
    if heat > 0 then
        -- the heat on the ground alone, so cracks don't cut through the grass edges over it; the
        -- edges are painted back over it, then the tint, opaque
        local ground = #overhangs > 0 and as_drawn(base .. ':0', {base}) or d
        if not ground then return out end
        local tops = {}
        for _, texpos in ipairs(overhangs) do tops[#tops + 1] = grass.pixels_of(texpos) end
        for n, h in pairs(heat_pixels(kind, heat, ground.red, ground.green, ground.blue, piece)) do
            local r, g, b = h[1], h[2], h[3]
            for _, top in ipairs(tops) do
                local t = top[n]
                local a = t[4]
                if a > 0 then
                    local k = a / 255
                    r, g, b = t[1] * k + r * (1 - k), t[2] * k + g * (1 - k), t[3] * k + b * (1 - k)
                end
            end
            out[n] = pack(round_byte(r + (tint[1] - r) * tint_amount),
                          round_byte(g + (tint[2] - g) * tint_amount),
                          round_byte(b + (tint[3] - b) * tint_amount), 255)
        end
    end
    return out
end

-- Whether a band rimes any pixels (below freezing), and the flat tint a floor gets otherwise.
local function band_rimes(band)
    local _, _, share = frost_colours(band)
    return share > 0
end
local function bake_tint(band)
    local plain = frost_colours(band)
    local out = {}
    for n = 1, TILE * TILE do out[n] = plain end
    return out
end

-- Rime on edge pieces alone (on an open tile, with no ground of its own under them): the pieces'
-- brightest pixels, see-through elsewhere.
local function bake_open_edges(pieces, drawn_key, band)
    local layers = {0}   -- nothing under them
    for _, texpos in ipairs(pieces) do layers[#layers + 1] = texpos end
    local d = as_drawn(drawn_key, layers)
    if not d then return nil end
    local plain, rimed, share = frost_colours(band)
    local out = {}
    local function scaled(colour, a)
        local alpha = math.floor(((colour >> 24) & 0xff) * a / 255 + 0.5)
        return (colour & 0xffffff) | (alpha << 24)
    end
    local alpha = d.alpha
    for n = 1, TILE * TILE do out[n] = alpha[n] > 0 and scaled(plain, alpha[n]) or 0 end
    local order = d.order
    for k = 1, rimed_count(d, share) do out[order[k]] = scaled(rimed, alpha[order[k]]) end
    return out
end

-- Frost with a snowy edge over it: both see-through, the edge painted over the rime.
local function bake_under_edge(frost_px, edge_texpos)
    local edge = grass.pixels_of(edge_texpos)
    if not edge then return nil end
    local out = {}
    for n = 1, TILE * TILE do
        local f, e = frost_px[n], edge[n]
        local fa, ea = ((f >> 24) & 0xff) / 255, e[4] / 255
        local alpha = ea + fa * (1 - ea)
        if alpha <= 0 then
            out[n] = 0
        else
            local k = fa * (1 - ea)
            out[n] = pack(round_byte((e[1] * ea + (f & 0xff) * k) / alpha),
                          round_byte((e[2] * ea + ((f >> 8) & 0xff) * k) / alpha),
                          round_byte((e[3] * ea + ((f >> 16) & 0xff) * k) / alpha), round_byte(alpha * 255))
        end
    end
    return out
end

-- The texpos for a baked look, baking it if it's new while the frame's baking time lasts
-- (BAKE_MS; one bake always goes ahead, so new ground fills in even on a slow frame).
-- RAMPS BY PICTURE (grungeisdead's copy, 2026-11-16). A ramp is a picture the game puts together
-- itself, and it gives the same picture a new number after a zoom or on another level. A ramp's
-- bake was kept by that number, so each new number was baked again, a few a frame, and the ramps
-- showed the game's colour and changed a moment later on every zoom and change of level (seen in
-- play). Now the bake is kept by the picture: a hash of all its pixels, worked out once per number
-- (grass.pixels_of keeps the pixels it read by number while the picture is unchanged).
-- (grungeisdead's copy, 2026-11-17) Known by colour.lua's picture filing first (colour.picture_of: 16
-- of its pixels, then one memcmp against each picture filed under them). The hash below reads all
-- 1024 pixels through DFHack, about half a millisecond, and the game hands its ramp pictures new
-- numbers one or two a frame (detailed_weather details: frost new bases, the game's own to the
-- game's own): reading each whole was much of frost's time, and its ramps waited meanwhile.
local picture_ids = setmetatable({}, {__mode = 'k'})   -- pixels table (grass.pixels_of's) -> its id
local function picture_id(texpos)
    local filed = colour.picture_of and colour.picture_of(texpos)
    if filed then return 'p' .. tostring(filed) end
    local px = grass.pixels_of(texpos)
    if not px then return 'n' .. texpos end
    local id = picture_ids[px]
    if not id then
        local h = 0
        for n = 1, #px do
            local p = px[n]
            h = (h * 31 + ((p[4] << 24) | (p[3] << 16) | (p[2] << 8) | p[1]) + n) % 2305843009213693951
        end
        id = 'p' .. h
        picture_ids[px] = id
    end
    return id
end
-- One bake made and kept under its key (false if it can't be made). BAKE COST (grungeisdead's copy,
-- 2026-11-17): each timed, the redraw and making the texture, for `detailed_weather details`. Shared by
-- baked_texpos and THE NEXT LOOK AHEAD (apply).
bake_ms = bake_ms or {n = 0, bake = 0, make = 0}
local function make_baked(key, bake)
    local kind = key:sub(1, 1)
    if grass.delete_textures and baked_count >= BAKED_MOST then clear_cache() end
    local t0 = clock_s()
    local px = bake()
    local t1 = clock_s()
    -- (NATIVE REDRAW: 'busy', the DLL has no room this frame: nothing kept, asked again next frame)
    if px == 'busy' then return nil end
    count(kind == 'r' and 'ramp bakes' or kind == 'c' and 'crack bakes' or 'other bakes')
    -- (NATIVE REDRAW: a bake can hand back a copy the hook DLL paints this frame, {handle, texpos})
    local entry
    if type(px) == 'table' and px.native then entry = {handle = px.handle}
    else entry = px and {handle = dfhack.textures.createTile(px, TILE, TILE)} or false end
    bake_ms.n = bake_ms.n + 1
    bake_ms.bake = bake_ms.bake + (t1 - t0) * 1000
    bake_ms.make = bake_ms.make + (clock_s() - t1) * 1000
    baked[key] = entry
    baked_count = baked_count + 1
    return entry
end

local function baked_texpos(key, bake, state)
    local entry = baked[key]
    if entry == nil then
        -- timed from the frame's first bake, so the drawing before it doesn't eat the budget
        -- (NEW VIEW BAKES: longer for the first frames on another level or after a zoom)
        -- (PANS BAKE BUSY, grungeisdead's copy, 2026-11-17: and BUSY_BAKE_MS from a pan's first frame, not
        -- only once something waited. A strip panned in got 2 ms, two bakes at 0.9 ms each, and its other
        -- new ramps showed the game's colour for a frame: detailed_weather details, ramp waits)
        if state.baked == 0 then
            state.bake_started = clock_ms()
            state.bake_ms = work_time.take((new_view_left > 0 and NEW_VIEW_BAKE_MS
                or (waited_last_frame or moved_this_frame) and BUSY_BAKE_MS or BAKE_MS) * allowance)
        elseif clock_ms() - state.bake_started >= state.bake_ms then
            count('waited')
            state.waited = true
            return nil
        end
        state.baked = state.baked + 1
        entry = make_baked(key, bake)
    end
    if not entry then return nil end
    if not entry.texpos or frame_number - entry.fetched > TEXPOS_RECHECK_FRAMES then
        entry.texpos, entry.fetched = dfhack.textures.getTexposByHandle(entry.handle), frame_number
        made[entry.texpos] = true
    end
    return entry.texpos
end

-- The grass overhang pieces a floor_flag puts on a tile (soil and stone edges aren't grass art,
-- and are left out; they're rimed by the ground under them).
local function overhang_pieces(flag)
    -- every edge art, ground (sand, dirt, pebbles, stone) as well as grass
    if not edge_art then edge_art = snow_ramps.all_edge_art() end
    local pieces = {}
    for b, side in ipairs(SIDE_NAMES) do
        local byte = (flag >> (8 * (b - 1))) & 0xff
        local art = byte ~= 0 and edge_art[byte]
        if art and art[side] then pieces[#pieces + 1] = art[side] end
    end
    return pieces
end

----------------------------------------------------------------------------------------------
-- Planning and drawing
----------------------------------------------------------------------------------------------

local EMPTY, RAMP_TOP, RAMP = df.tiletype_shape.EMPTY, df.tiletype_shape.RAMP_TOP, df.tiletype_shape.RAMP
local FLOOR_LIKE = df.tiletype_shape_basic.Floor
local GRASS_MATERIALS = {[df.tiletype_material.GRASS_LIGHT] = true, [df.tiletype_material.GRASS_DARK] = true,
                         [df.tiletype_material.GRASS_DRY] = true, [df.tiletype_material.GRASS_DEAD] = true}
local shape_of, floor_like, grassy, class_of_tiletype = {}, {}, {}, {}   -- by tiletype; df.tiletype.attrs costs ~40 us a lookup
local function shape(tiletype)
    local s = shape_of[tiletype]
    if not s then
        local attrs = df.tiletype.attrs[tiletype]
        s = attrs.shape
        shape_of[tiletype] = s
        floor_like[tiletype] = df.tiletype_shape.attrs[s].basic_shape == FLOOR_LIKE
        grassy[tiletype] = GRASS_MATERIALS[attrs.material] or false
        -- the class looks.lua redraws it as (for ramps, which colour.lua's tables don't reach)
        class_of_tiletype[tiletype] = grassy[tiletype] and 'grass'
            or attrs.material == df.tiletype_material.SOIL and 'dirt' or 'stone'
    end
    return s
end

-- The index of map tile (x, y) in a screen buffer, or nil if it's outside it. The buffers are
-- raw memory with no bounds checks, reallocated at a new size on a zoom or resize, so every
-- read and write goes through this.
local function screen_index(port, viewport, x, y)
    local sx, sy = x - viewport.x1, y - viewport.y1
    if sx < 0 or sy < 0 or sx >= port.dim_x or sy >= port.dim_y then return nil end
    return sx * port.dim_y + sy
end

local function viewport_at(depth)
    return depth == 0 and df.global.gps.main_viewport or df.global.gps.lower_viewport[depth - 1]
end

local function layers()
    local ports = {}
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        -- LEVELS THE GAME DRAWS (grungeisdead's copy, 2026-11-17): a level below is drawn only while its
        -- viewport is active (g_src enabler.cpp: the full redraw skips the others, and the change check
        -- passes over them). An inactive one's buffers aren't the game's drawing of this frame.
        ports[depth] = {port = port, background = port.screentexpos_background,
                        above = port.screentexpos_background_two, spatter = port.screentexpos_spatter,
                        floor_flag = port.screentexpos_floor_flag,
                        active = depth == 0 or port.flag.active}
    end
    return ports
end

remembered = remembered or {}
remembered_count = remembered_count or 0
timing = timing or {plan = 0, apply = 0}

-- DRAWN TILES LISTED (grungeisdead's copy, 2026-11-17): the tiles plan() gave a band (ramps and bare
-- floors, the only ones apply() can draw), by the same key as remembered, and a count bumped when one
-- is added, so apply() knows to list the view's again.
drawable = drawable or {}
drawable_version = drawable_version or 0

function forget()
    remembered, remembered_count = {}, 0
    drawable, drawable_version = {}, drawable_version + 1
    known_view = nil   -- (VIEW KNOWN: nothing is kept now)
end

----------------------------------------------------------------------------------------------
-- NATIVE CRACKS (grungeisdead's copy, 2026-11-20, test 15R)
----------------------------------------------------------------------------------------------
-- In a dry look apply() went over every tile listed in view, every frame, to put each one's cracked
-- copy in: 1.35 to 1.84 ms a frame in play after 15O (frost-draw), most of it reading and writing the
-- game's buffers through DFHack. With the DLL swapping the colour (RAMPS IN THE LOOK), the DLL puts them
-- in (detailed_weather_dll.cpp: CRACKS IN PLACE; started by native.lua, which hands over its views):
--   * which tiles may crack the DLL works out itself, from the map, by this file's rules (work_out),
--     handed over at start (crack_rules). 15R to 15T had plan() work them out here and hand them over:
--     a ramp panned into view showed the look's uncracked copy until its turn came (seen in play, in dry
--     looks only: in a wet one the DLL's colour decides everything from the map itself), and plan() was
--     frost's largest cost (0.7 to 1.8 ms a frame). plan() no longer runs while the DLL places them;
--   * each frame the DLL reads what the game drew at each such tile (a ramp's own picture under its
--     copy in the look), and puts in its cracked copy for that picture, the tile's piece of the heat
--     patterns and the look; a copy it hasn't got it paints itself, there and then (15V), from what
--     this file hands over: each look's numbers (crack_look: the cracks' amount, and a dirt and a stone
--     ramp's redraw, colour.lua's native_template), the heat patterns' pixels, each original's ground
--     (crack_ground_kinds), and blank textures (native.lua). 15R to 15U asked this file for each copy
--     and placed it the next frame, and with 16 copies a picture (one a piece) panning kept finding
--     pieces not made: ramps drew in, in dry looks only (seen in play). This file notes each copy
--     painted as Detailed Weather's (crack_d);
--   * the look's cracks are numbered (crack_gen): on a change of look the look before's copies are
--     shown until the new look's are made, as here before.
native_cv = native_cv or nil                       -- native.lua's views of the DLL's rings, while it runs
native_crack_counts = native_crack_counts or {}   -- for native.lua's report
local CRACK_OPEN, CRACK_FLOOR, CRACK_RAMP = 0x20, 0x40, 0x80   -- the DLL's codes (CRACK_OPEN, ...)
crack_slot_gen = crack_slot_gen or {}   -- the look's number in each of the DLL's two crack_look slots
crack_slot_floors = crack_slot_floors or {}   -- how many originals' copies each slot lists (FLOORS AHEAD)
crack_kinds = crack_kinds or {}          -- each original whose ground cracks -> its kind (crack_ground_kinds)
heat_sent_at = heat_sent_at or nil       -- clock_s() when the heat patterns' pixels were last handed over (nil: not yet)
crack_gens = crack_gens or {}            -- look key -> its number
crack_gen_look = crack_gen_look or {}    -- number -> {look, key, amount}
crack_gen_next = crack_gen_next or 0
crack_gen_shown, crack_gen_before = crack_gen_shown or nil, crack_gen_before or nil
crack_forced_sent = crack_forced_sent or false   -- the forced temperature the DLL was last told (false: none)

-- (native.lua) This file's rules for the DLL (THE TILES WORKED OUT, 15U), as work_out applies them: by
-- tiletype, CRACK_FLOOR for any floor, CRACK_RAMP with its kind for a ramp of dirt (its material SOIL)
-- or stone (any other but grass, which doesn't crack), CRACK_OPEN for open space seen through (EMPTY,
-- RAMP_TOP); and the temperature bands (band_of), how deep to look, and any forced temperature.
function crack_rules()
    local tiletype = {}
    for tt = 0, df.tiletype._last_item do
        if df.tiletype[tt] then
            local s = shape(tt)
            if floor_like[tt] then tiletype[tt] = CRACK_FLOOR
            elseif s == RAMP then
                local kind = CRACK_KIND_CODE[class_of_tiletype[tt]]   -- (grass: none)
                tiletype[tt] = kind and (CRACK_RAMP | kind) or 0
            elseif s == EMPTY or s == RAMP_TOP then tiletype[tt] = CRACK_OPEN
            else tiletype[tt] = 0 end
        end
    end
    crack_forced_sent = forced_celsius or false
    return {tiletype = tiletype, band_c = BAND_C, cool_from = COOL_FROM, warm_from = WARM_FROM,
            most_depth = MOST_DEPTH, forced_c = forced_celsius}
end
local function crack_new_numbers()
    crack_gens, crack_gen_look, crack_gen_shown, crack_gen_before = {}, {}, nil, nil
    crack_ahead_gen, crack_slot_gen, crack_slot_floors, heat_sent_at = nil, {}, {}, nil
end
-- A look's cracks' number, given the first time the look is seen (shown, or made next).
local function crack_gen_for(look, look_key, amount)
    local gen = crack_gens[look_key]
    if not gen then
        crack_gen_next = (crack_gen_next + 1) & 0x7fffffff
        gen = crack_gen_next
        crack_gens[look_key] = gen
        crack_gen_look[gen] = {look = look, key = look_key, amount = amount}
    end
    return gen
end

-- THE NEXT LOOK AHEAD (grungeisdead's copy, 2026-11-20, test 15T). After 15S the cracks still came in
-- tile by tile on a change to a dry look (seen in play): the DLL asked for each copy only once the look
-- showed. While colour.lua makes the next look (seconds), the DLL asks for the next look's copies too
-- (crack_gen_next), and colour.lua waits for them before it shows the look (colour.lua: CRACKS AHEAD),
-- so they change with it, as frost.lua's own THE NEXT LOOK AHEAD baked the ramps ahead.
crack_ahead_gen = crack_ahead_gen or nil   -- the next look's number while it's made, else nil
crack_ahead_at = crack_ahead_at or nil     -- clock_s() when apply last set it
-- (colour.lua) How many cells in view still wait for the next look's copy: 0 when all are made (or
-- none are needed); -1 while not known yet (the DLL hasn't looked for this look yet).
function cracks_ahead_left()
    local cv = native_cv
    -- (frost.lua not looking ahead this last half second: off, resting, or handed back)
    if not cv or not crack_ahead_gen or clock_s() - (crack_ahead_at or 0) > 0.5 then return 0 end
    if cv.next_walked.value ~= crack_ahead_gen then return -1 end
    return cv.next_missing.value
end
colour.cracks_ahead_left = cracks_ahead_left

-- native.lua: started, with the views; stopped.
function native_crack_begin(cv)
    native_cv = cv
    native_crack_counts = {}
    crack_kinds = {}   -- (FLOORS AHEAD: this world's, from native.lua's call to crack_ground_kinds next frame)
    crack_new_numbers()
end
function native_crack_end()
    native_cv = nil
    forget()   -- (plan() works the tiles out again for frost.lua's own drawing: nothing was kept meanwhile)
end

-- (native.lua) Each original's ground for the DLL (THE PAINTING HERE): {[texpos] = 1 dirt, 2 stone, 3
-- pebbles}, as ground_kind finds it, for every texture the colour's tables point at and every one the
-- graphics files name as ground. A floor's copy is painted only where its ground cracks.
function crack_ground_kinds()
    local kinds = {}
    local function add(t)
        if t and t > 0 and kinds[t] == nil then kinds[t] = CRACK_KIND_CODE[ground_kind(t)] or false end
    end
    ground_kind(0)   -- (reads the graphics files once: kind_of_texpos)
    for t in pairs(kind_of_texpos or {}) do add(t) end
    local st = colour.state
    for t in pairs(st and st.refs_of or {}) do add(t) end
    local out = {}
    for t, k in pairs(kinds) do if k then out[t] = k end end
    crack_kinds = out   -- (FLOORS AHEAD: the originals each look lists its copies of)
    return out
end

-- FLOORS AHEAD (15V): what the game draws for each original whose ground cracks in a look (colour.lua:
-- look_copy_of: its table copy, made as colour.lua builds the look), listed in the look's slot, so the DLL
-- paints the next look's floors from the ground as it will be drawn. Written again while the look is built
-- and some aren't made yet.
local function write_floors(slot, gen)
    local cv, g = native_cv, crack_gen_look[gen]
    if not g or not colour.look_copy_of then return end
    local sv = cv.looks[slot]
    local n = 0
    for orig in pairs(crack_kinds) do
        if n >= sv.floors_most then break end
        local copy = colour.look_copy_of(orig, g.key)
        if copy then sv.floor_orig[n], sv.floor_copy[n] = orig, copy n = n + 1 end
    end
    sv.floors_n.value = n
    sv.floors_version.value = (sv.floors_version.value + 1) & 0xffffffff
    crack_slot_floors[slot] = n
end
-- A look's numbers into one of the DLL's two crack_look slots: the cracks' amount, a dirt and a stone
-- ramp's redraw for the look (colour.lua: native_template; a kind it can't paint is left out, and its
-- ramps keep the look's own), and its floors' copies, marked ready last.
local function write_look(slot, gen)
    local cv, g = native_cv, crack_gen_look[gen]
    if not g or not colour.native_template then return end
    local sv = cv.looks[slot]
    sv.ready.value = 0
    sv.gen.value = gen
    sv.amount.value = g.amount
    local ready = 1
    if colour.native_template(sv.ramp[1], 'dirt', g.look) then ready = ready | 2 end
    if colour.native_template(sv.ramp[2], 'stone', g.look) then ready = ready | 4 end
    write_floors(slot, gen)
    sv.ready.value = ready
    crack_slot_gen[slot] = gen
end
-- The looks the DLL needs (showing, and next) each in a slot, the other kept for the one not written.
local function place_looks(gen, next_gen)
    local function has(g) return g and (crack_slot_gen[0] == g or crack_slot_gen[1] == g) end
    if gen and not has(gen) then write_look(crack_slot_gen[0] == next_gen and 1 or 0, gen) end
    if next_gen and not has(next_gen) then write_look(crack_slot_gen[0] == gen and 1 or 0, next_gen) end
end

-- apply()'s work while the DLL puts the cracks in: the look's number set (and the next look's), their
-- numbers handed over, a forced temperature told, the heat patterns' pixels kept current, and the copies
-- the DLL painted noted as Detailed Weather's.
local HEAT_EVERY = 5   -- seconds between the heat patterns' pixels handed over again (never kept long:
                       -- crack_spec reads them afresh each time, as an address kept could outlive its texture)
local function native_crack_frame(look, look_key, cracking, state)
    local cv = native_cv
    -- (`detailed_weather temperature N`: the DLL works every tile out again with it, or without it)
    if (forced_celsius or false) ~= crack_forced_sent then
        crack_forced_sent = forced_celsius or false
        cv.forced_on.value, cv.forced_c.value = forced_celsius and 1 or 0, forced_celsius or 0
        cv.tables.value = (cv.tables.value + 1) & 0xffffffff
    end
    -- the heat patterns' 16 pieces' pixels (crack_spec's here and north, all of them)
    if not heat_sent_at or clock_s() - heat_sent_at >= HEAT_EVERY then
        heat_sent_at = clock_s()
        local handles = heat_pattern_handles()
        for k = 0, HEAT_TILES * HEAT_TILES - 1 do
            local h = handles and handles[k + 1]
            cv.heat[k] = h and grass.original_address(dfhack.textures.getTexposByHandle(h)) or 0
        end
    end
    -- the copies painted since: Detailed Weather's own, and a floor's ground kept for paths.lua's soil
    local head, tail, ring = cv.d_head.value, cv.d_tail.value, cv.done_ring
    local d32, d8 = cv.d32, cv.d8
    while tail ~= head do
        local slot = tail % ring
        local tex, base, code = d32[slot * 4], d32[slot * 4 + 1], d8[slot * 16 + 13]
        made[tex] = true
        if code & CRACK_RAMP == 0 then cracked_from[tex] = base end
        native_crack_counts.painted = (native_crack_counts.painted or 0) + 1
        tail = (tail + 1) & 0xffffffff
    end
    cv.d_tail.value = tail
    -- (THE NEXT LOOK AHEAD: the look colour.lua is making, if it cracks)
    local next_look, next_key = nil, nil
    if colour.pending_look then next_look, next_key = colour.pending_look() end
    local next_amount = next_key and crack_amount(next_look)
    crack_ahead_gen = next_amount and crack_gen_for(next_look, next_key, next_amount) or nil
    crack_ahead_at = clock_s()
    local gen = cracking and crack_gen_for(look, look_key, cracking) or nil
    place_looks(gen, crack_ahead_gen)   -- (the numbers written before the numbers that name them)
    -- (FLOORS AHEAD: the next look's floors listed again every few frames while colour.lua builds it and
    -- some of their copies aren't made yet)
    if crack_ahead_gen then
        local slot = crack_slot_gen[0] == crack_ahead_gen and 0 or crack_slot_gen[1] == crack_ahead_gen and 1 or nil
        local total = 0
        for _ in pairs(crack_kinds) do total = total + 1 end
        if slot and (crack_slot_floors[slot] or 0) < total and frame_number % 10 == 0 then write_floors(slot, crack_ahead_gen) end
    end
    cv.gen_next.value = crack_ahead_gen or 0xffffffff
    cv.depth.value = MOST_DEPTH
    if not gen then cv.on.value = 0 return end
    if gen ~= crack_gen_shown then crack_gen_before, crack_gen_shown = crack_gen_shown, gen end
    cv.gen.value = gen
    cv.gen_prev.value = crack_gen_before or 0xffffffff
    cv.on.value = 1
end

-- The bare outdoor floors and ramps shown in view, on this level or below through open space,
-- with their temperature band. complete is false if some were left for the next plan.
-- Each map tile's frost is worked out once and kept by its position (remembered[key], with the
-- entry apply() resolves on it), so panning reuses it. Each frame plan() works out, within
-- SLICE_MS: the tiles in view it has nothing for (a newly shown strip), then a few that are due a
-- recheck, then the map side of tiles round the view (WARM_MARGIN), ready for a pan. apply() draws
-- the view's tiles straight from what's kept.
local SLICE_MS = 1.5
local NEW_TILES_MS = 4   -- more for a strip just panned into view, so it fills at once
-- (grungeisdead's copy, 2026-11-16) On another level or a resized view (a zoom), its tiles are worked
-- out in up to this much a frame for NEW_VIEW_FRAMES frames: at NEW_TILES_MS a level's ramps showed
-- the game's colour and changed over a second or so (seen in play on every change of level).
local NEW_VIEW_MS = 30
local NEW_VIEW_FRAMES = 4
plan_view = plan_view or nil
plan_x1, plan_y1 = plan_x1 or nil, plan_y1 or nil   -- JUMPS: the view's corner at the last plan
new_view_left = new_view_left or 0
known_view = known_view or nil   -- VIEW KNOWN: the view whose tiles are all kept (plan)
level_warm_at, level_warm_idle = level_warm_at or 0, level_warm_idle or 0
local WARM_MARGIN = 24
local REFRESH_PER_FRAME = 300
refresh_at = refresh_at or 0
warm_at = warm_at or 0
warm_view, warm_idle = warm_view or nil, warm_idle or 0

-- FROST AT REST (grungeisdead's copy, 2026-11-19, test 15A). With the hook DLL swapping the colour, it
-- swaps ramps into the look too (colour.lua: RAMPS IN THE LOOK), so with the old floor effects off and
-- a look that doesn't crack the ground, nothing is left for frost to draw: no planning, no drawing.
local function resting()
    if floor_effects or not (colour.native_ramps and colour.native_ramps()) then return false end
    if crack_amount((colour.shown_look())) then return false end
    -- (THE NEXT LOOK AHEAD: not while the next look cracks: its tiles worked out and copies made first)
    if native_cv and colour.pending_look and crack_amount((colour.pending_look())) then return false end
    return true
end

function plan(viewport)
    if resting() then return nil end   -- (FROST AT REST: apply isn't called either)
    -- NATIVE CRACKS (15U): the DLL works the tiles out itself; apply() only answers it
    if native_cv and not floor_effects and colour.native_ramps and colour.native_ramps() then
        return {z = viewport.z, complete = true, native = true}
    end
    local started = clock_ms()
    local block_at = grass.block_at   -- kept between plans

    -- one tile from scratch: which level it shows, and its band if it's an outdoor floor or ramp
    local now = clock_ms()
    local function work_out(x, y, view_z)
        local depth, z = 0, view_z or viewport.z
        while depth <= MOST_DEPTH do
            local block = block_at(x, y, z)
            if not block then return {depth = depth} end
            local tiletype = block.tiletype[x % 16][y % 16]
            local s = shape(tiletype)
            if floor_like[tiletype] or s == RAMP then
                -- above ground, not just 'outside': tiles under a tree's canopy count as indoors
                local flags = block.designation[x % 16][y % 16]
                if not flags.outside and flags.subterranean then return {depth = depth} end
                -- (grungeisdead's copy, 2026-11-16) under water: not bare ground, and the game draws
                -- the water over it. Its ramps were swapped too, and the river's submerged ramps
                -- changed shade on fast zooms (seen in play: squares at the river's shore corners)
                if flags.flow_size > 0 then return {depth = depth} end
                -- snow covers it (and snow_ramps.lua draws it): no frost to draw
                if grass.snow_amount(x, y, z, now) >= SNOWY then return {depth = depth} end
                local degrees = forced_celsius or celsius(block.temperature_1[x % 16][y % 16])
                return {depth = depth, band = band_of(degrees), ramp = s == RAMP,
                        grassy = s == RAMP and grassy[tiletype] or nil,
                        class = s == RAMP and class_of_tiletype[tiletype] or nil}
            end
            if s ~= EMPTY and s ~= RAMP_TOP then return {depth = depth} end
            depth, z = depth + 1, z - 1
        end
        return {depth = MOST_DEPTH}
    end

    -- the band on this level's open tile (the top of a slope): edges from floors beside it land
    -- on it, and get rime of their own
    local function open_band(x, y)
        local block = block_at(x, y, viewport.z)
        if not block then return nil end
        local degrees = forced_celsius or celsius(block.temperature_1[x % 16][y % 16])
        return band_of(degrees)
    end

    local ports = layers()
    if remembered_count > REMEMBER_MOST then forget() end
    local budget, complete = WORK_PER_PLAN, true
    local z = viewport.z
    -- another level, or the view resized: NEW_VIEW_MS for new tiles for a few frames
    local view_shape = ('%d:%d:%d'):format(z, viewport.x2 - viewport.x1, viewport.y2 - viewport.y1)
    -- JUMPS (grungeisdead's copy, 2026-11-17): a pan of half the view or more (a click on the map to go
    -- somewhere else) is a new view too. At NEW_TILES_MS its tiles were worked out over several frames,
    -- and its ramps showed the game's colour meanwhile (seen in play: the level's ramps flashed).
    local jumped = plan_x1 ~= nil and (math.abs(viewport.x1 - plan_x1) * 2 >= viewport.x2 - viewport.x1
        or math.abs(viewport.y1 - plan_y1) * 2 >= viewport.y2 - viewport.y1)
    plan_x1, plan_y1 = viewport.x1, viewport.y1
    if view_shape ~= plan_view or jumped then plan_view, new_view_left = view_shape, NEW_VIEW_FRAMES end
    -- (the strip a pan brought in gets the longer time; both come out of the one share)
    local new_tiles_ms = work_time.take((new_view_left > 0 and NEW_VIEW_MS or NEW_TILES_MS) * allowance)
    local slice_ms = math.min(SLICE_MS * allowance, new_tiles_ms)
    if new_view_left > 0 then new_view_left = new_view_left - 1 end
    local function out_of_time() return clock_ms() - started >= slice_ms end
    local function out_of_time_for_new() return clock_ms() - started >= new_tiles_ms end
    local function work(x, y, key, view_z)
        if not remembered[key] then remembered_count = remembered_count + 1 end
        local tile = work_out(x, y, view_z)
        tile.due = now + REMEMBER_MS + math.random(0, REMEMBER_MS // 2)
        remembered[key] = tile
        if tile.band and not drawable[key] then
            drawable[key] = true
            -- (DRAWN TILES LISTED: one in view has the view's list made again; one round the view or
            -- on a level beside waits until the view moves there. Every one bumped it, and warming
            -- round the view did so most frames, so the list was made again every frame)
            if not view_z and x >= viewport.x1 and x <= viewport.x2 and y >= viewport.y1 and y <= viewport.y2 then
                drawable_version = drawable_version + 1
            end
        end
    end
    -- first: tiles in view with nothing kept
    -- VIEW KNOWN (grungeisdead's copy, 2026-11-17): once a pass finds every tile in this view kept, it's
    -- skipped until the view moves or all is forgotten (forget(): nothing kept is let go otherwise).
    -- It looked up every tile in view every frame, some 8000 zoomed out, and found none to do.
    local view_now = ('%d:%d:%d:%d:%d'):format(z, viewport.x1, viewport.y1, viewport.x2, viewport.y2)
    if known_view ~= view_now then
        for x = viewport.x1, viewport.x2 do
            for y = viewport.y1, viewport.y2 do
                local key = (z * 4096 + x) * 4096 + y
                if not remembered[key] then
                    if out_of_time_for_new() then complete = false break end
                    work(x, y, key)
                end
            end
            if not complete then break end
        end
        if complete then known_view = view_now end
    end
    if complete then
        -- then: a few in view that are due a recheck (temperatures change slowly)
        local cols, rows = viewport.x2 - viewport.x1 + 1, viewport.y2 - viewport.y1 + 1
        for _ = 1, math.min(REFRESH_PER_FRAME, cols * rows) do
            if out_of_time() then break end
            refresh_at = (refresh_at + 1) % (cols * rows)
            local x, y = viewport.x1 + refresh_at // rows, viewport.y1 + refresh_at % rows
            local key = (z * 4096 + x) * 4096 + y
            local tile = remembered[key]
            if tile and now >= tile.due then
                local entry, open_entry = tile.entry, tile.open_entry
                work(x, y, key)
                -- what apply() resolved carries over while the tile looks the same
                remembered[key].entry, remembered[key].open_entry = entry, open_entry
            end
        end
        -- and with time to spare: tiles round the view, ready for a pan
        -- (once a whole sweep finds nothing to do, it rests until the view moves)
        local w, h = cols + 2 * WARM_MARGIN, rows + 2 * WARM_MARGIN
        local view_key = (((z * 4096 + viewport.x1) * 4096 + viewport.y1) * 512 + cols) * 512 + rows
        if warm_view ~= view_key then warm_view, warm_idle, level_warm_idle = view_key, 0, 0 end
        while warm_idle < w * h and not out_of_time() do
            warm_idle = warm_idle + 1
            warm_at = (warm_at + 1) % (w * h)
            local x, y = viewport.x1 - WARM_MARGIN + warm_at // h, viewport.y1 - WARM_MARGIN + warm_at % h
            local key = (z * 4096 + x) * 4096 + y
            if not remembered[key] and dfhack.maps.isValidTilePos(x, y, z) then
                work(x, y, key)
                warm_idle = 0
            end
        end
        -- THE LEVELS BESIDE (grungeisdead's copy, 2026-11-16): then, still with time to spare, the
        -- view's rectangle on the levels just below and above, ready for a change of level (they
        -- were worked out only once shown, and their ramps showed the game's colour meanwhile)
        local cells = cols * rows
        while warm_idle >= w * h and level_warm_idle < 2 * cells and not out_of_time() do
            level_warm_idle = level_warm_idle + 1
            level_warm_at = (level_warm_at + 1) % (2 * cells)
            local lz = level_warm_at < cells and z - 1 or z + 1
            local cell = level_warm_at % cells
            local x, y = viewport.x1 + cell // rows, viewport.y1 + cell % rows
            local key = (lz * 4096 + x) * 4096 + y
            if not remembered[key] and dfhack.maps.isValidTilePos(x, y, lz) then
                work(x, y, key, lz)
                level_warm_idle = 0
            end
        end
    end
    work_time.done()
    timing.plan = timing.plan + (clock_ms() - started - timing.plan) * 0.2
    return {z = viewport.z, complete = complete, open_band = open_band}
end

-- The ground a ramp is (dirt, sand, stone, pebbles), from the floors drawn beside it on its level:
-- the nearest first, then the corners. nil if none are bare ground.
local AROUND = {{0, 1}, {-1, 0}, {1, 0}, {0, -1}, {-1, 1}, {1, 1}, {-1, -1}, {1, -1}}
function ramp_ground(layer, viewport, x, y)
    for _, d in ipairs(AROUND) do
        local i = screen_index(layer.port, viewport, x + d[1], y + d[2])
        local texpos = i and layer.background[i] or 0
        local kind = texpos > 0 and ground_kind(texpos)
        if kind then return kind end
    end
    return nil
end

-- Buffer indexes are worked out afresh from the view as it is now, and checked against each
-- buffer's size. Run after snow_ramps.apply, so snowy ramps (already swapped) are left alone.
-- (grungeisdead's copy, 2026-11-17) What a texture under a ramp is, for counting what it changed from
-- and to: frost found some 8 ramps a frame on a new ground with nothing on screen changing
-- (detailed_weather details: new_base).
local function sort_of(texpos)
    if made[texpos] then return 'weather-made' end
    local st = colour.state
    if st and st.lean and st.lean.original and st.lean.original[texpos] then return 'a lean frame' end
    if (_G.detailed_weather_pointed_from or {})[texpos] then return 'a table copy' end
    if st and st.screen_original and st.screen_original[texpos] then return 'a per-tile copy' end
    return 'the game\'s own'
end

-- NEW BASES SORTED (grungeisdead's copy, 2026-11-17), for detailed_weather details. None of some 8,600 new
-- grounds under ramps was the same picture as before. Each is counted by when (the view moving or
-- still), where (the level shown or one below), whether it's the number this screen spot showed before a
-- pan (read from the wrong place), and how far the picture changed: 128 of its pixels against the old
-- picture's, both from colour.lua's filing, telling a picture the game really changed from one that
-- differs only where it's see-through.
local function picture_change(a, b)
    local bufs = colour.picture_buf
    local pa = bufs and a and bufs[a:sub(2)]
    local pb = bufs and b and bufs[b:sub(2)]
    if not (pa and pb) then return 'not compared' end
    local seen_differ, clear_differ = 0, 0
    for n = 0, TILE * TILE - 1, 8 do
        local wa, wb = pa[n], pb[n]
        if wa ~= wb then
            if (wa >> 24) == 0 and (wb >> 24) == 0 then clear_differ = clear_differ + 1
            else seen_differ = seen_differ + 1 end
        end
    end
    if seen_differ == 0 then
        return clear_differ == 0 and 'the same at every point read' or 'different only where see-through'
    end
    local share = seen_differ / (TILE * TILE / 8)
    return share < 0.05 and 'under 5% different' or share < 0.5 and 'partly different' or 'mostly different'
end

local function new_base_sorted(t, base, pic, tile, x, y, z, remembered)
    count(moved_this_frame and 'nb when: the view moved' or 'nb when: the view still')
    count(tile.depth == 0 and 'nb where: the level shown' or 'nb where: a level below')
    -- after a pan, the screen spot now holding (x, y) held (x - pan_dx, y - pan_dy) last frame
    if pan_dx ~= 0 or pan_dy ~= 0 then
        local o = remembered[(z * 4096 + x - pan_dx) * 4096 + y - pan_dy]
        if o and o.entry and o.entry.base == base then count('nb pan: the number this spot showed before') end
    end
    count('nb pictures: ' .. picture_change(t.pic, pic))
    -- (grungeisdead's copy, 2026-11-17) how long after the view last moved: none came with the view held
    -- still from the load (one reading), and four in five came with it still in play
    local since = frames_since_move
    count(since == 0 and 'nb since a move: the same frame' or since <= 5 and 'nb since a move: 1 to 5 frames'
        or since <= 30 and 'nb since a move: 6 to 30 frames' or 'nb since a move: over 30 frames')
    -- FLIPS KEPT TO LOOK AT: the first few, both pictures by their filed ids, for `detailed_weather frost
    -- flips` to write out (dump_flips): four on the frame the view moved, four 1 to 5 frames after, four
    -- later (the first round's twelve all came within a frame of a move)
    local moved = moved_this_frame
    local bucket = since == 0 and 1 or since <= 5 and 2 or 3
    local kept = 0
    for _, f in ipairs(flip_samples) do if f.bucket == bucket then kept = kept + 1 end end
    if kept < 4 then
        flip_samples[#flip_samples + 1] = {x = x, y = y, z = z, depth = tile.depth, since = since, moved = moved,
            bucket = bucket,
            old_base = t.base, new_base = base, old_pic = t.pic, new_pic = pic,
            old_sort = sort_of(t.base), new_sort = sort_of(base)}
    end
end

-- FLIPS KEPT TO LOOK AT (grungeisdead's copy, 2026-11-17): writes the kept flips' two pictures, old and new,
-- as 32 rows of 32 pixels (hex AARRGGBB), to a text file in the game's folder, and starts keeping afresh.
-- A diagnostic: `detailed_weather frost flips`.
function dump_flips()
    local path = dfhack.getDFPath() .. '/detailed_weather_ramp_flips.txt'
    local f = io.open(path, 'w')
    if not f then dfhack.printerr('detailed_weather: could not write ' .. path) return end
    local function picture(label, id)
        local buf = colour.picture_buf and id and colour.picture_buf[id:sub(2)]
        if not buf then f:write(label .. ': not filed\n') return end
        f:write(label .. ':\n')
        for row = 0, TILE - 1 do
            local line = {}
            for col = 0, TILE - 1 do
                local v = buf[row * TILE + col]
                -- the game's words are AABBGGRR; written AARRGGBB
                line[#line + 1] = ('%02x%02x%02x%02x'):format(v >> 24, v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF)
            end
            f:write(table.concat(line, ' ') .. '\n')
        end
    end
    for n, s in ipairs(flip_samples) do
        f:write(('flip %d: map %d,%d,%d, %s, %s, %d frames after the view moved; texture %d (%s) to %d (%s)\n'):format(
            n, s.x, s.y, s.z, s.depth == 0 and 'the level shown' or ('%d levels below'):format(s.depth),
            s.moved and 'the view moving' or 'the view still', s.since, s.old_base, s.old_sort, s.new_base, s.new_sort))
        picture('old', s.old_pic)
        picture('new', s.new_pic)
    end
    f:close()
    print(('detailed_weather: %d ramp flips written to %s'):format(#flip_samples, path))
    flip_samples = {}
end

-- DRAWN TILES LISTED: the view's tiles with a band, as a flat list {x, y, x, y...}, made again when
-- the view moves or plan() finds a new one. (With the old floor effects on, every tile: they draw
-- rime over open tiles too.)
drawn = drawn or {key = nil, version = -1, list = {}}
-- THE NEXT LOOK AHEAD (apply): the pass it's on (mark: the next look and the view's list) and where
-- it's got to in the list
ahead = ahead or {mark = nil, at = 1}
-- (grungeisdead's copy, 2026-11-17) Whether the view moved since last frame (a pan, a zoom or another
-- level), and how far it panned on the same level: PANS BAKE BUSY, and the new bases' count.
moved_this_frame = moved_this_frame or false
last_view = last_view or {x1 = nil, y1 = nil, x2 = nil, y2 = nil, z = nil}
pan_dx, pan_dy = pan_dx or 0, pan_dy or 0
frames_since_move = frames_since_move or 0   -- frames since the view last moved (new bases' count)
flip_samples = flip_samples or {}            -- FLIPS KEPT TO LOOK AT (new_base_sorted, dump_flips)
local function drawn_list(viewport, z)
    local view_key = ('%d:%d:%d:%d:%d'):format(z, viewport.x1, viewport.y1, viewport.x2, viewport.y2)
    if not floor_effects and drawn.key == view_key and drawn.version == drawable_version then return drawn.list end
    local list = {}
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
            if floor_effects or drawable[(z * 4096 + x) * 4096 + y] then
                list[#list + 1] = x
                list[#list + 1] = y
            end
        end
    end
    drawn.key, drawn.version, drawn.list = view_key, drawable_version, list
    return list
end
function apply(planned, viewport)
    local started = clock_ms()
    -- the colour's copies let go: cracks baked from them may now be keyed by other pictures' numbers
    if seen_generation ~= colour.copies_generation then
        if seen_generation then clear_cache() end
        seen_generation = colour.copies_generation
        crack_new_numbers()   -- (NATIVE CRACKS: the DLL's copies by the old numbers no longer shown)
    end
    frame_number = frame_number + 1
    local ports = layers()
    -- each buffer's size, read once a frame (every read of a game buffer is a slow userdata call)
    for _, layer in pairs(ports) do layer.dim_x, layer.dim_y = layer.port.dim_x, layer.port.dim_y end
    local function index_in(layer, x, y)
        local sx, sy = x - viewport.x1, y - viewport.y1
        if sx < 0 or sy < 0 or sx >= layer.dim_x or sy >= layer.dim_y then return nil end
        return sx * layer.dim_y + sy
    end
    local state = {started = started, baked = 0}
    -- the view against last frame's (moved_this_frame; pan_dx, pan_dy when it panned on the same level)
    local lv = last_view
    moved_this_frame = lv.x1 ~= viewport.x1 or lv.y1 ~= viewport.y1 or lv.x2 ~= viewport.x2
        or lv.y2 ~= viewport.y2 or lv.z ~= viewport.z
    if moved_this_frame and lv.z == viewport.z and lv.x1 then
        pan_dx, pan_dy = viewport.x1 - lv.x1, viewport.y1 - lv.y1
    else
        pan_dx, pan_dy = 0, 0
    end
    lv.x1, lv.y1, lv.x2, lv.y2, lv.z = viewport.x1, viewport.y1, viewport.x2, viewport.y2, viewport.z
    frames_since_move = moved_this_frame and 0 or frames_since_move + 1
    -- ALREADY IN THE LOOK: colour.lua's copies, looked up once a frame (see the ramp check below)
    local pointed = _G.detailed_weather_pointed_from or {}
    local cst = colour.state
    local screen_copy = cst and cst.screen_original or {}
    local lean_frame = cst and cst.lean and cst.lean.original or {}
    -- NOT DRAWN YET: the game's black background texture (see the ramp check below), read once a frame
    local black = df.global.gps.black_background_texpos[0]
    local look, look_key = colour.shown_look()
    local cracking = not floor_effects and crack_amount(look)   -- nil unless the look is dry
    -- NATIVE CRACKS: the DLL puts the cracks in, and the ramps are the colour's (RAMPS IN THE LOOK):
    -- nothing left to go over here (the old floor effects aren't drawn by the DLL: with them on, as before)
    -- (also while the look doesn't crack but the next does: THE NEXT LOOK AHEAD)
    if native_cv and not floor_effects and colour.native_ramps and colour.native_ramps() then
        native_crack_frame(look, look_key, cracking, state)
        waited_last_frame = state.waited or false
        timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
        return
    end

    -- One pass over the view's tiles, from what's kept for each: the frost for the level it shows,
    -- and for an open tile on this level, the rime on the edges over it. Each tile keeps the entry
    -- and texture it resolved to, so a frame is mostly a few reads and a write; it's worked out
    -- again only when what it depends on changes (the ground, the colour look, the overhangs on the
    -- tile, the snowy edge over it) or the cache is cleared (generation).
    local z = viewport.z
    local remembered, generation = remembered, generation   -- locals: read for every tile
    -- DRAWN TILES LISTED: only the view's ramps and bare floors are gone over. Every tile in view
    -- was looked up every frame, some 8000 zoomed out, for the few hundred that draw: most of
    -- frost's time (detailed_weather details: drawing 1.8 ms a frame).
    local list = drawn_list(viewport, z)
    -- RAMPS IN THE LOOK (test 15A): with the DLL swapping the colour, a ramp is its to swap, but one
    -- cracked in a dry look, which is still drawn here
    local native_ramps = colour.native_ramps and colour.native_ramps()
    for n = 1, #list, 2 do
        local x, y = list[n], list[n + 1]
        do
            local tile = remembered[(z * 4096 + x) * 4096 + y]
            local by_dll = native_ramps and tile and tile.ramp and not (cracking and CRACK_KINDS[tile.class or 'stone'])
            -- ramps always (redrawn for the look); floors when the look cracks them, or with the
            -- old floor effects
            if tile and not by_dll and (tile.ramp or (cracking and tile.ramp == false) or (floor_effects and tile.band))
                and tile.depth <= MOST_DEPTH then
                local layer = ports[tile.depth]
                -- (LEVELS THE GAME DRAWS: none of a level the game isn't drawing is read or written)
                local i = layer.active and index_in(layer, x, y) or nil
                if not layer.active then count('tiles on levels the game isn\'t drawing') end
                local shown = i and layer.background[i] or 0
                local base = shown
                local t = tile.entry
                -- a ramp shows its own frosted texture where it was drawn last frame and the game
                -- hasn't redrawn it: still the same ramp. Any other texture of ours there (a snowy
                -- ramp) is left be.
                if t and shown ~= 0 and (shown == t.ramp_texpos or shown == t.held or shown == t.hot_texpos
                        or shown == t.crack_texpos) then
                    base = t.base
                elseif made[shown] then base = 0
                elseif shown == black then
                    -- NOT DRAWN YET (grungeisdead's copy, 2026-11-17): the game's black background, which it fills
                    -- every cell with before drawing (g_src graphics.cpp, clear_screen). A cell still holding
                    -- it is one the game hasn't drawn yet, for a frame or more after a move (`detailed_weather
                    -- frost flips`: 8 of 12 new grounds were it). Taken for a new ground, it gave the ramp a
                    -- frost made from black, which was then held over onto its real ground while that one's
                    -- was made. Left as it is, and the ramp keeps what it had.
                    base = 0
                    count('tiles the game hadn\'t drawn yet')
                elseif moved_this_frame and t and tile.depth > 0 and t.depth == tile.depth and shown ~= 0
                        and shown ~= t.base then
                    -- LEVELS BELOW ON A MOVE (grungeisdead's copy, 2026-11-17): on the frame the view moves, a level
                    -- below can still show another view's drawing (frost flips: 4 of the 6 new grounds on a move
                    -- frame were below, each an unrelated picture, stone for grass). For that frame the tile keeps
                    -- the ground it had, and its frost, rather than being made again from what's there; a real
                    -- change is taken up on the next frame.
                    base = t.base
                    count('tiles below kept for the frame of a move')
                elseif tile.ramp and (pointed[shown] or screen_copy[shown] or lean_frame[shown]) then
                    -- ALREADY IN THE LOOK (grungeisdead's copy, 2026-11-17): one of colour.lua's copies under
                    -- a ramp (the tables', the per-tile pass's, a grass lean frame) is in the look's colours
                    -- already. It was taken for a new ground and redrawn for the look a second time, and
                    -- shown so until the game drew the ramp again (detailed_weather details: some 1,900 of
                    -- a minute's frost new bases were to or from a copy). Left as it is.
                    base = 0
                    count('ramps showing a copy already in the look')
                end
                if base > 0 then
                    if not (t and t.base == base and t.depth == tile.depth and t.band == tile.band) then
                        -- (the picture, worked out once an entry: the bake's key, and for the count; the
                        -- old base's own number may hold another picture by now, as the game reuses them)
                        local pic = tile.ramp and picture_id(base) or nil
                        if t and t.base ~= base and tile.ramp then
                            count('new_base')
                            -- (and what it changed from and to: printed by detailed_weather details)
                            count(('new base: %s to %s%s'):format(sort_of(t.base), sort_of(base),
                                t.pic and t.pic == pic and ', the same picture' or ''))
                            new_base_sorted(t, base, pic, tile, x, y, z, remembered)   -- (NEW BASES SORTED)
                        end
                        if tile.ramp then
                            counts.ramp_bases = counts.ramp_bases or {}
                            if not counts.ramp_bases[base] then
                                counts.ramp_bases[base] = true
                                count('ramp textures seen')
                            end
                        end
                        -- FROST HELD OVER (grungeisdead's copy, 2026-11-17): a ramp whose ground has a new
                        -- number keeps the frost it had until the new one's made, as a change of look
                        -- does. The new number is mostly the same picture again, and the game's own ramp
                        -- showed in between (seen in play: ramps redrawn on a change of level).
                        local held = t and t.depth == tile.depth and (t.ramp_texpos or t.held) or nil
                        t = {x = x, y = y, depth = tile.depth, band = tile.band, base = base, ramp = tile.ramp,
                             grassy = tile.grassy, class = tile.class, pic = pic, held = held}
                        tile.entry = t
                    end
                    t.seen = frame_number   -- (THE NEXT LOOK AHEAD bakes only from grounds seen this frame)
                    if t.gen ~= generation then
                        t.gen, t.ramp_look, t.floor_flag, t.edge_above, t.hot_band = generation, nil, nil, nil, nil
                        t.crack_look = nil
                    end
                    if cracking and not t.ramp then
                        -- dry dirt and stone: the ground (already in the look's colours) with its
                        -- piece of the cracks, by position so they join across tiles
                        if t.crack_look ~= look_key then
                            local kind = ground_kind(base)
                            if CRACK_KINDS[kind] then
                                local piece = (y % HEAT_TILES) * HEAT_TILES + x % HEAT_TILES
                                -- (grungeisdead's copy) the old look's cracks stay until the new
                                -- look's are made, rather than the bare ground showing meanwhile
                                local made_texpos = baked_texpos('c' .. base .. ':' .. look_key .. ':' .. piece,
                                    function()
                                        -- (DRY CRACKS: painted by the hook DLL, else baked here)
                                        local spec = colour.native_crack and crack_spec(kind, cracking, piece)
                                        if spec then
                                            local copy, busy = colour.native_crack(base, spec)
                                            if copy then return copy end
                                            if busy then return 'busy' end
                                        end
                                        return bake_cracks(base, kind, cracking, piece)
                                    end, state)
                                if made_texpos then
                                    t.crack_texpos, t.crack_look = made_texpos, look_key
                                    cracked_from[made_texpos] = base
                                end
                            else
                                t.crack_texpos, t.crack_look = nil, look_key
                            end
                        end
                        if t.crack_texpos and shown ~= t.crack_texpos then   -- the old look's until the new is made
                            layer.background[i] = t.crack_texpos
                        end
                    end
                    if floor_effects and not t.ramp and t.hot_band ~= t.band then
                        -- hot Detailed Landscapes ground: its pre-rendered version, in place of its own
                        t.hot_texpos, t.hot_band = heat_of(t.band) > 0 and hot_ground_texpos(base, t.band, x, y) or nil, t.band
                    end
                    if t.ramp then
                        if t.ramp_look ~= look_key then
                            if look then
                                -- the ramp redrawn for the look (dry and wet included), as colour.lua redraws the
                                -- ground, and in a dry look, dirt and stone ramps cracked as the floors are
                                local class = t.class or 'stone'
                                local crack = cracking and CRACK_KINDS[class]
                                local piece = (y % HEAT_TILES) * HEAT_TILES + x % HEAT_TILES
                                -- (grungeisdead's copy) the ramp keeps the old look's version until
                                -- the new look's is made: it used to show the game's own colour in
                                -- between, and on every change of look the ramps flipped to it and
                                -- back one by one
                                local key = 'r' .. (t.pic or picture_id(base)) .. ':' .. look_key .. ':' .. class
                                    .. (crack and ':' .. piece or '')
                                local made_texpos = baked_texpos(key,
                                    function()
                                        -- NATIVE REDRAW (grungeisdead's copy, 2026-11-18): redrawn by the hook DLL
                                        -- (colour.lua: native_redraw), about 0.1 ms there against about 5 ms here
                                        -- in a wet look; cracked ramps too since test 15O (DRY CRACKS), with
                                        -- their cracks; here only when the patterns' pixels can't be read
                                        local spec = crack and crack_spec(class, cracking, piece) or nil
                                        if colour.native_redraw and (not crack or spec) then
                                            local copy, busy = colour.native_redraw(base, class, look, spec)
                                            if copy then return copy end
                                            if busy then return 'busy' end
                                        end
                                        local px = looks.redraw(base, class, look, true)
                                        if px and crack then return crack_packed(px, class, cracking, piece) end
                                        return px
                                    end, state)
                                if made_texpos then t.ramp_texpos, t.ramp_look = made_texpos, look_key
                                elseif baked[key] == nil then
                                    -- WAITS BY WHAT SHOWED (grungeisdead's copy, 2026-11-17), for detailed_weather
                                    -- details: an older frost held meanwhile, or the game's own ramp (seen)
                                    count((t.ramp_texpos or t.held) and 'ramp waits: an older frost showing'
                                        or 'ramp waits: the game\'s own showing')
                                end
                            else
                                t.ramp_texpos, t.ramp_look = nil, nil   -- no look yet: the game's own
                            end
                        end
                        -- (FROST HELD OVER: the frost it had, until its own is made)
                        local frost_texpos = t.ramp_texpos or t.held
                        if frost_texpos and shown ~= frost_texpos then layer.background[i] = frost_texpos end
                    elseif not floor_effects then
                        -- (floors: only the cracks, above)
                    elseif t.hot_texpos then
                        if shown ~= t.hot_texpos then layer.background[i] = t.hot_texpos end
                    elseif layer.spatter[i] == 0 then
                        local above = layer.above[i]
                        local flag = layer.floor_flag[i]
                        if above == 0 then
                            if t.floor_flag ~= flag then
                                -- in the heat, dirt and sand take their piece of the heat patterns by position
                                local kind = heat_of(t.band) > 0 and ground_kind(base) or nil
                                local piece = (kind == 'dirt' or kind == 'sand')
                                    and (y % HEAT_TILES) * HEAT_TILES + x % HEAT_TILES or 0
                                if not kind and not band_rimes(t.band) then
                                    -- no rime and no heat: just the tint, one flat colour, the same for every floor
                                    t.floor_texpos = baked_texpos('tint:' .. t.band, function() return bake_tint(t.band) end, state)
                                else
                                    local heat_key = kind and (':' .. kind .. piece) or ''
                                    t.floor_texpos = baked_texpos(base .. ':' .. flag .. ':' .. t.band .. heat_key,
                                        function()
                                            return bake_floor(base, overhang_pieces(flag), base .. ':' .. flag, t.band, kind, piece)
                                        end, state)
                                end
                                if t.floor_texpos then t.floor_flag = flag end
                            end
                            if t.floor_texpos and t.floor_flag == flag then layer.above[i] = t.floor_texpos end
                        elseif above == t.edge_above or snow_ramps.snowy_edge_texpos[above] then
                            -- a snowy edge is there (and has cleared the overhangs it replaces): rime under it
                            if t.edge_above ~= above or t.edge_flag ~= flag then
                                t.edge_texpos = baked_texpos('e' .. above .. ':' .. base .. ':' .. flag .. ':' .. t.band,
                                    function()
                                        local frost_px = bake_floor(base, overhang_pieces(flag), base .. ':' .. flag, t.band)
                                        return frost_px and bake_under_edge(frost_px, above)
                                    end, state)
                                if t.edge_texpos then t.edge_above, t.edge_flag = above, flag end
                            end
                            if t.edge_texpos and t.edge_above == above then layer.above[i] = t.edge_texpos end
                        end
                    end
                end
            end
            if floor_effects and tile and tile.depth > 0 then
                -- rime on the edges over an open tile, where nothing else is in the layer above
                local layer = ports[0]
                local i = index_in(layer, x, y)
                local flag = i and layer.floor_flag[i] or 0
                if flag ~= 0 then
                    if tile.open_band == nil then tile.open_band = planned.open_band and planned.open_band(x, y) or false end
                    local band = tile.open_band
                    if band and layer.above[i] == 0 then
                        local o = tile.open_entry
                        if not (o and o.flag == flag and o.band == band and o.gen == generation) then
                            o = {flag = flag, band = band, gen = generation}
                            o.texpos = baked_texpos('o' .. flag .. ':' .. band,
                                function() return bake_open_edges(overhang_pieces(flag), 'o' .. flag, band) end, state)
                            if o.texpos then tile.open_entry = o end
                        end
                        if o.texpos then layer.above[i] = o.texpos end
                    end
                end
            end
        end
    end
    -- THE NEXT LOOK AHEAD (grungeisdead's copy, 2026-11-17). While colour.lua makes the next look (a few
    -- seconds, its copies made before it shows), the view's ramps are baked for it too, with what's
    -- left of AHEAD_MS, so they change in the same frame as the ground. They were baked only once it
    -- showed, a few a frame, each ramp changing a moment after the ground (detailed_weather details:
    -- 21,251 waits in a minute with one change of look). Not while ramps wait for this look's frost.
    local next_look, next_key = nil, nil
    if colour.pending_look then next_look, next_key = colour.pending_look() end
    if next_key and not state.waited then
        -- done once a pass over the view's list has gone by, until the list or the next look changes
        local mark = next_key .. '|' .. tostring(drawn.key) .. '|' .. drawn.version
        if ahead.mark ~= mark then ahead.mark, ahead.at = mark, 1 end
        if ahead.at <= #list then
            local next_cracking = not floor_effects and crack_amount(next_look)
            local ends = clock_ms() + AHEAD_MS * allowance
            local at = ahead.at
            while at <= #list and clock_ms() < ends do
                local x, y = list[at], list[at + 1]
                local tile = remembered[(z * 4096 + x) * 4096 + y]
                local t = tile and tile.ramp and tile.entry
                -- (a ground seen this frame: an older entry's number may hold another picture by now)
                if t and t.ramp and t.pic and t.seen == frame_number then
                    local base, class = t.base, t.class or 'stone'
                    local crack = next_cracking and CRACK_KINDS[class]
                    local piece = (y % HEAT_TILES) * HEAT_TILES + x % HEAT_TILES
                    local key = 'r' .. t.pic .. ':' .. next_key .. ':' .. class .. (crack and ':' .. piece or '')
                    if baked[key] == nil then
                        make_baked(key, function()
                            -- (NATIVE REDRAW and DRY CRACKS, as above)
                            local spec = crack and crack_spec(class, next_cracking, piece) or nil
                            if colour.native_redraw and (not crack or spec) then
                                local copy, busy = colour.native_redraw(base, class, next_look, spec)
                                if copy then return copy end
                                if busy then return 'busy' end
                            end
                            local px = looks.redraw(base, class, next_look, true)
                            if px and crack then return crack_packed(px, class, next_cracking, piece) end
                            return px
                        end)
                        count('baked ahead')
                    end
                end
                at = at + 2
            end
            ahead.at = at
        end
    end
    waited_last_frame = state.waited or false   -- BUSY_BAKE_MS next frame if any tile waited
    timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
end

-- Another map or world loading: what's kept by position belongs to the old map, and what's kept by
-- texture number may name other textures in the next world, whose graphics can differ.
function forget_world()
    forget()
    clear_cache()
    crack_new_numbers()   -- (NATIVE CRACKS)
    drawn_cache, drawn_count = {}, 0
    kind_of_texpos, patterns, hot_ground = nil, nil, nil
    refresh_at, warm_at, warm_view, warm_idle = 0, 0, nil, 0
end
