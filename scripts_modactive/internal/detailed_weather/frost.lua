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
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)

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
local REMEMBER_MS = 3000     -- temperatures change slowly
local WORK_PER_PLAN = 300
local REMEMBER_MOST = 60000
local BAKE_MS = 2
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

function clear_cache()
    generation = generation + 1
    for _, entry in pairs(baked) do
        if entry then grass.discard(entry.handle, 'frost and cracks') end
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
local function heat_patterns()
    if patterns then return patterns end
    patterns = {}
    local handles = dfhack.textures.loadTileset(art_dir .. 'heat_patterns.png', TILE, TILE, true)
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
local function baked_texpos(key, bake, state)
    local entry = baked[key]
    if entry == nil then
        -- timed from the frame's first bake, so the drawing before it doesn't eat the budget
        if state.baked == 0 then
            state.bake_started, state.bake_ms = clock_ms(), work_time.take(BAKE_MS * allowance)
        elseif clock_ms() - state.bake_started >= state.bake_ms then return nil end
        state.baked = state.baked + 1
        -- (the cache only starts afresh for its size when textures are being deleted: grass.lua)
        if grass.delete_textures and baked_count >= BAKED_MOST then clear_cache() end
        local px = bake()
        entry = px and {handle = dfhack.textures.createTile(px, TILE, TILE)} or false
        baked[key] = entry
        baked_count = baked_count + 1
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
        ports[depth] = {port = port, background = port.screentexpos_background,
                        above = port.screentexpos_background_two, spatter = port.screentexpos_spatter,
                        floor_flag = port.screentexpos_floor_flag}
    end
    return ports
end

remembered = remembered or {}
remembered_count = remembered_count or 0
timing = timing or {plan = 0, apply = 0}

function forget()
    remembered, remembered_count = {}, 0
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
local WARM_MARGIN = 24
local REFRESH_PER_FRAME = 300
refresh_at = refresh_at or 0
warm_at = warm_at or 0
warm_view, warm_idle = warm_view or nil, warm_idle or 0

function plan(viewport)
    local started = clock_ms()
    local block_at = grass.block_at   -- kept between plans

    -- one tile from scratch: which level it shows, and its band if it's an outdoor floor or ramp
    local now = clock_ms()
    local function work_out(x, y)
        local depth, z = 0, viewport.z
        while depth <= MOST_DEPTH do
            local block = block_at(x, y, z)
            if not block then return {depth = depth} end
            local tiletype = block.tiletype[x % 16][y % 16]
            local s = shape(tiletype)
            if floor_like[tiletype] or s == RAMP then
                -- above ground, not just 'outside': tiles under a tree's canopy count as indoors
                local flags = block.designation[x % 16][y % 16]
                if not flags.outside and flags.subterranean then return {depth = depth} end
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
    -- (the strip a pan brought in gets the longer time; both come out of the one share)
    local new_tiles_ms = work_time.take(NEW_TILES_MS * allowance)
    local slice_ms = math.min(SLICE_MS * allowance, new_tiles_ms)
    local function out_of_time() return clock_ms() - started >= slice_ms end
    local function out_of_time_for_new() return clock_ms() - started >= new_tiles_ms end
    local function work(x, y, key)
        if not remembered[key] then remembered_count = remembered_count + 1 end
        local tile = work_out(x, y)
        tile.due = now + REMEMBER_MS + math.random(0, REMEMBER_MS // 2)
        remembered[key] = tile
    end
    -- first: tiles in view with nothing kept
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
        if warm_view ~= view_key then warm_view, warm_idle = view_key, 0 end
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
function apply(planned, viewport)
    local started = clock_ms()
    -- the colour's copies let go: cracks baked from them may now be keyed by other pictures' numbers
    if seen_generation ~= colour.copies_generation then
        if seen_generation then clear_cache() end
        seen_generation = colour.copies_generation
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
    local look, look_key = colour.shown_look()
    local cracking = not floor_effects and crack_amount(look)   -- nil unless the look is dry

    -- One pass over the view's tiles, from what's kept for each: the frost for the level it shows,
    -- and for an open tile on this level, the rime on the edges over it. Each tile keeps the entry
    -- and texture it resolved to, so a frame is mostly a few reads and a write; it's worked out
    -- again only when what it depends on changes (the ground, the colour look, the overhangs on the
    -- tile, the snowy edge over it) or the cache is cleared (generation).
    local z = viewport.z
    local remembered, generation = remembered, generation   -- locals: read for every tile
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
            local tile = remembered[(z * 4096 + x) * 4096 + y]
            -- ramps always (redrawn for the look); floors when the look cracks them, or with the
            -- old floor effects
            if tile and (tile.ramp or (cracking and tile.ramp == false) or (floor_effects and tile.band))
                and tile.depth <= MOST_DEPTH then
                local layer = ports[tile.depth]
                local i = index_in(layer, x, y)
                local shown = i and layer.background[i] or 0
                local base = shown
                local t = tile.entry
                -- a ramp shows its own frosted texture where it was drawn last frame and the game
                -- hasn't redrawn it: still the same ramp. Any other texture of ours there (a snowy
                -- ramp) is left be.
                if t and shown ~= 0 and (shown == t.ramp_texpos or shown == t.hot_texpos or shown == t.crack_texpos) then
                    base = t.base
                elseif made[shown] then base = 0 end
                if base > 0 then
                    if not (t and t.base == base and t.depth == tile.depth and t.band == tile.band) then
                        t = {x = x, y = y, depth = tile.depth, band = tile.band, base = base, ramp = tile.ramp,
                             grassy = tile.grassy, class = tile.class}
                        tile.entry = t
                    end
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
                                t.crack_texpos = baked_texpos('c' .. base .. ':' .. look_key .. ':' .. piece,
                                    function() return bake_cracks(base, kind, cracking, piece) end, state)
                                if t.crack_texpos then
                                    t.crack_look = look_key
                                    cracked_from[t.crack_texpos] = base
                                end
                            else
                                t.crack_texpos, t.crack_look = nil, look_key
                            end
                        end
                        if t.crack_texpos and t.crack_look == look_key and shown ~= t.crack_texpos then
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
                                t.ramp_texpos = baked_texpos('r' .. base .. ':' .. look_key .. ':' .. class
                                        .. (crack and ':' .. piece or ''),
                                    function()
                                        local px = looks.redraw(base, class, look, true)
                                        if px and crack then return crack_packed(px, class, cracking, piece) end
                                        return px
                                    end, state)
                                if t.ramp_texpos then t.ramp_look = look_key end
                            else
                                t.ramp_texpos, t.ramp_look = nil, nil   -- no look yet: the game's own
                            end
                        end
                        if t.ramp_texpos and shown ~= t.ramp_texpos then layer.background[i] = t.ramp_texpos end
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
    timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
end

-- Another map or world loading: what's kept by position belongs to the old map, and what's kept by
-- texture number may name other textures in the next world, whose graphics can differ.
function forget_world()
    forget()
    clear_cache()
    drawn_cache, drawn_count = {}, 0
    kind_of_texpos, patterns, hot_ground = nil, nil, nil
    refresh_at, warm_at, warm_view, warm_idle = 0, 0, nil, 0
end
