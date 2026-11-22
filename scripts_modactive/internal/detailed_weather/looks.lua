-- The looks, for Detailed Weather: how a texture is redrawn for the weather, by its class (grass,
-- dirt, sand, stone, pebbles, or anything else) and the look (temperature and wetness, each in
-- steps). colour.lua makes a copy of each texture this way for the look showing; frost.lua does
-- ramps. Worked out with Poss in tools/weather/look_grid.py and wet_looks.py, which these follow:
--
--   temperature  sets saturation (richer when hot, paler when cold), with a cool or warm lean.
--                Grass is drawn as its mild look; bare ground (dirt, sand, stone, pebbles) as its
--                hot, dry look, so it only gets paler from there.
--   wetness      darkens everything alike (keeping Detailed Landscapes' even lightness between
--                grounds), lighter when dry and darker when wet. Grass turns from yellow (dry) to
--                green (wet); dirt and sand lose some green as they wet, so they go browner.
--   dry          grass's gaps between stalks deepen; stone and pebbles' darkest parts deepen;
--                sand gets more contrast and a fine grain. (Dirt's and stone's cracks join
--                across tiles, so they're drawn per tile by frost.lua.)
--   wet          past average: an overlay per ground type, from its own structure (the lit faces
--                of raised parts, and the hollows): rime in the cold, wet after rain in the mild,
--                a humid glisten in the heat.
--@ module = true

local grass = reqscript('internal/detailed_weather/grass')   -- texture pixels

COLD_STEPS = 5          -- below mild (one more than above: a temperate winter, a few degrees
                        -- above freezing, wanted a gentler first step: Poss)
WARM_STEPS = 4          -- above mild
WET_STEPS = 4           -- from dry (0) to wet (WET_STEPS); average is WET_STEPS / 2

local TILE = 32
local N = TILE * TILE

-- colour
local DRY_HUE, WET_HUE = -12, 10                 -- grass, degrees at the driest and wettest
local HOT_SATURATION, COLD_SATURATION = 0.20, -0.25
local EXTRA_SATURATION = 0.10                    -- cold: this much less again; hot: this much more
local WARM = {1.05, 1.0, 0.925}                  -- hot: the lean (red-yellow), keeping lightness
local COOL = {0.95, 1.0, 1.075}                  -- cold: towards blue
local WET_DARK = 0.16                            -- everything at its wettest: this much darker
-- ice (its floors and walls): no wet look (it doesn't soak, and it darkened with the ground: Poss);
-- frostier deep in the cold, glassier near thawing
local ICE_FROST = {232, 240, 250}                -- cold: towards this
local ICE_FROST_STRENGTH = 0.30                  -- at the coldest
local ICE_COLD_SATURATION = -0.30
local ICE_THAW_FROM = -0.5                       -- t from which it starts to look glassy
local ICE_THAW_DARK = 0.14                       -- at its glassiest: this much darker
local ICE_THAW_SATURATION = 0.25                 -- and this much more saturated
local ICE_GLINTS, ICE_GLINT_STRENGTH = 0.05, 0.55   -- the share of brightest pixels that shine, how much
local EXTRA_LIGHTNESS = 0.10                     -- dry: this far towards white; wet: towards black
local WET_RICHER = 0.10                          -- bare ground at its wettest: this much more saturated
local WET_SOIL = {1.0, 0.88, 0.78}               -- dirt and sand at their wettest: less green, browner

-- dry
local DRY_SHARE, DRY_DARK = 0.15, 0.65           -- stone, pebbles: darkest share deepened
local GRASS_GAP = {104, 80, 50}                  -- dry grass: its darkest share (the gaps between
local GRASS_GAP_STRENGTH = 0.5                   -- stalks) turns this far towards dry earth
local SAND_CONTRAST, SAND_GLINTS, SAND_GRAINS, SAND_GLINT_LIFT, SAND_GRAIN_DARK = 0.25, 0.12, 0.12, 0.08, 0.08

-- wet
local OPACITY = 0.4
local KIND_OPACITY = {sand = 0.5}
local WET_KINDS = {   -- share of pixels that glint, how strongly, how much hollows soak and shine, rime share
    grass =   {glint = 0.10, glint_strength = 0.20, soak = 0.13, sheen = 0.04, rime = 0.35},
    dirt =    {glint = 0.06, glint_strength = 0.27, soak = 0.30, sheen = 0.09, rime = 0.25},
    stone =   {glint = 0.09, glint_strength = 0.37, soak = 0.23, sheen = 0.11, rime = 0.25},
    pebbles = {glint = 0.10, glint_strength = 0.33, soak = 0.20, sheen = 0.07, rime = 0.30},
    sand =    {glint = 0.05, glint_strength = 0.27, soak = 0.23, sheen = 0.07, rime = 0.22},
}
local GLINT = {250, 250, 244}
local WARM_GLINT = {255, 246, 226}
local SKY = {150, 166, 188}
local RIME = {234, 241, 249}
local ICE_GLAZE = {198, 214, 232}
local WHITE = {250, 252, 255}
local HOT_GLINTS, HOT_SHEEN = 1.6, 0.07
local RIME_OPACITY, GLAZE = 0.35, 0.15
local HIGHLIGHT = {cold = 0.3, mild = 0.12, hot = 0.08}
local SHADE = {cold = 0, mild = 0, hot = 0}         -- a shade under each lit point: read as embossing (Poss, 2026-11-09)
local HIGHLIGHT_SHARE = 1 / 8
local SAND_VALLEY_ROWS, SAND_VALLEY_DARK, SAND_LINE_SHARE = 4, 0.22, 0.18
local WET_CRACK, WET_CRACK_STRENGTH = {66, 46, 32}, 0.55
local WET_JOINT = {50, 44, 39}
local JOINT_SHARE = {stone = 0.15, pebbles = 0.20}

----------------------------------------------------------------------------------------------
-- Helpers on 32 x 32 fields (1-based, row by row)
----------------------------------------------------------------------------------------------

local function lum_of(r, g, b) return r * 0.299 + g * 0.587 + b * 0.114 end

-- The texture being redrawn's see-through pixels: nil if it has none, else shown[n] for those
-- that show. Grass edges, ramps and the like are partly see-through; what they measure (their
-- darkest share, their mean, their raised parts) is of the pixels that show, and their clear
-- pixels count as the mean of those (not as black: a cut-out's outline would read as a cliff).
local shown

-- A sorted copy of the pixels that show, for quantiles.
local function sorted(field)
    local s = {}
    for n = 1, N do if not shown or shown[n] then s[#s + 1] = field[n] end end
    if #s == 0 then s[1] = 0 end
    table.sort(s)
    return s
end

-- A brightness field with its clear pixels at the mean of the rest.
local function filled(lum)
    if not shown then return lum end
    local sum, count = 0, 0
    for n = 1, N do if shown[n] then sum, count = sum + lum[n], count + 1 end end
    local mean = count > 0 and sum / count or 0
    for n = 1, N do if not shown[n] then lum[n] = mean end end
    return lum
end

-- np.quantile's linear interpolation.
local function quantile(sorted_field, q)
    local M = #sorted_field
    local pos = q * (M - 1) + 1
    local lo = math.floor(pos)
    if lo >= M then return sorted_field[M] end
    if lo < 1 then return sorted_field[1] end
    return sorted_field[lo] + (sorted_field[lo + 1] - sorted_field[lo]) * (pos - lo)
end

local function at(field, x, y) return field[(y % TILE) * TILE + (x % TILE) + 1] end

-- Mean over a (2r+1)^2 box, wrapping.
local function box(field, r)
    local out = {}
    local count = (2 * r + 1) ^ 2
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local sum = 0
            for dy = -r, r do for dx = -r, r do sum = sum + at(field, x + dx, y + dy) end end
            out[y * TILE + x + 1] = sum / count
        end
    end
    return out
end

-- Weights 0-1 for the top `share` of a field, fading in over the next bit.
local function top_share(field, share, s)
    local out = {}
    if share <= 0 then for n = 1, N do out[n] = 0 end return out end
    s = s or sorted(field)
    local cut = quantile(s, 1 - share)
    local soft = quantile(s, math.max(0, 1 - share * 1.6))
    local span = math.max(1e-6, cut - soft)
    for n = 1, N do
        local v = (field[n] - soft) / span
        out[n] = v < 0 and 0 or v > 1 and 1 or v
    end
    return out
end

-- The same field moved: shifted(field, 0, -1)[y] = field[y + 1] (the value from the row below).
local function shifted(field, dx, dy)
    local out = {}
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do out[y * TILE + x + 1] = at(field, x + dx, y + dy) end
    end
    return out
end

local function blend(r, g, b, n, colour, k)
    r[n] = r[n] + (colour[1] - r[n]) * k
    g[n] = g[n] + (colour[2] - g[n]) * k
    b[n] = b[n] + (colour[3] - b[n]) * k
end

----------------------------------------------------------------------------------------------
-- Colour
----------------------------------------------------------------------------------------------

-- CSS hue-rotate then saturate, as colour matrices (3x3, row-major).
local function matrix(hue, saturation)
    local c, s = math.cos(math.rad(hue)), math.sin(math.rad(hue))
    local h = {
        0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928,
        0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283,
        0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072,
    }
    local k = 1 + saturation
    local sat = {
        0.213 + 0.787 * k, 0.715 - 0.715 * k, 0.072 - 0.072 * k,
        0.213 - 0.213 * k, 0.715 + 0.285 * k, 0.072 - 0.072 * k,
        0.213 - 0.213 * k, 0.715 - 0.715 * k, 0.072 + 0.928 * k,
    }
    local m = {}
    for row = 0, 2 do
        for col = 0, 2 do
            local sum = 0
            for k2 = 0, 2 do sum = sum + sat[row * 3 + k2 + 1] * h[k2 * 3 + col + 1] end
            m[row * 3 + col + 1] = sum
        end
    end
    return m
end

-- The look's numbers: t (-1 cold .. 1 hot), w (0 dry .. 1 wet).
local function shares(look)
    local t = look.temperature
    return t / (t < 0 and COLD_STEPS or WARM_STEPS), look.wet / WET_STEPS
end

-- The temperature's name for the wet overlay.
local function weather_of(t)
    if t <= -0.75 then return 'cold' end   -- a few degrees below freezing: rime (from -0.5, at about
                                           -- freezing, it showed in the rain and read as embossing)
    if t >= 0.5 then return 'hot' end
    return 'mild'
end

local GROUND = {dirt = true, sand = true, stone = true, pebbles = true}
local SOIL = {dirt = true, sand = true}

-- Per class, the look's colour change as a function of (r, g, b) -> r, g, b.
local recolour_cache = {}
-- NATIVE COPIES (grungeisdead's copy, 2026-11-18): the same change's numbers, by the same key
-- (recolour_numbers, below)
local recolour_params = {}
function recolourer(class, look)
    local key = class .. ':' .. look.temperature .. ':' .. look.wet
    local f = recolour_cache[key]
    if f then return f end
    local t, w = shares(look)
    local sat_t = t < 0 and COLD_SATURATION * -t or HOT_SATURATION * t
    local extra = 1 + EXTRA_SATURATION * t
    local m
    if class == 'ice' then
        local frost = t < 0 and -t or 0
        local thaw = math.max(0, math.min(1, (t - ICE_THAW_FROM) / -ICE_THAW_FROM))
        m = matrix(0, (1 + ICE_COLD_SATURATION * frost) * (1 + ICE_THAW_SATURATION * thaw) - 1)
        local k, dark = ICE_FROST_STRENGTH * frost, 1 - ICE_THAW_DARK * thaw
        f = function(r, g, b)
            local nr, ng, nb = m[1] * r + m[2] * g + m[3] * b, m[4] * r + m[5] * g + m[6] * b, m[7] * r + m[8] * g + m[9] * b
            nr, ng, nb = nr + (ICE_FROST[1] - nr) * k, ng + (ICE_FROST[2] - ng) * k, nb + (ICE_FROST[3] - nb) * k
            return nr * dark, ng * dark, nb * dark
        end
        recolour_cache[key] = f
        -- (NATIVE REDRAW: ice's numbers too, for native_numbers)
        recolour_params[key] = {ice = true, m = m, k = k, dark = dark}
        return f
    elseif class == 'grass' then
        m = matrix(DRY_HUE + (WET_HUE - DRY_HUE) * w, (1 + sat_t) * extra - 1)
    elseif GROUND[class] then
        m = matrix(0, (1 + sat_t) / (1 + HOT_SATURATION) * (1 + w * WET_RICHER) * extra - 1)
    else
        m = matrix(0, (1 + sat_t) * extra - 1)
    end
    local soil = SOIL[class] and {1 + (WET_SOIL[1] - 1) * w, 1 + (WET_SOIL[2] - 1) * w, 1 + (WET_SOIL[3] - 1) * w}
    local lean_from = t > 0 and WARM or COOL
    local amount = math.abs(t)
    local lean = amount > 0 and {1 + (lean_from[1] - 1) * amount, 1 + (lean_from[2] - 1) * amount,
                                 1 + (lean_from[3] - 1) * amount}
    local dark = 1 - w * WET_DARK
    local lighten = EXTRA_LIGHTNESS * (1 - 2 * w)
    recolour_params[key] = {m = m, soil = soil, lean = lean, dark = dark, lighten = lighten}
    local function balance(r, g, b, gains)
        local before = lum_of(r, g, b)
        local nr, ng, nb = r * gains[1], g * gains[2], b * gains[3]
        local after = lum_of(nr, ng, nb)
        local k = after > 0 and before / after or 1
        return nr * k, ng * k, nb * k
    end
    f = function(r, g, b)
        local nr, ng, nb = m[1] * r + m[2] * g + m[3] * b, m[4] * r + m[5] * g + m[6] * b, m[7] * r + m[8] * g + m[9] * b
        if soil then nr, ng, nb = balance(nr, ng, nb, soil) end
        if lean then nr, ng, nb = balance(nr, ng, nb, lean) end
        nr, ng, nb = nr * dark, ng * dark, nb * dark
        if lighten > 0 then
            return nr + (255 - nr) * lighten, ng + (255 - ng) * lighten, nb + (255 - nb) * lighten
        end
        return nr * (1 + lighten), ng * (1 + lighten), nb * (1 + lighten)
    end
    recolour_cache[key] = f
    return f
end

-- NATIVE COPIES (grungeisdead's copy, 2026-11-18): the numbers behind a class's colour change for a
-- look, for the hook DLL, which paints colour.lua's per-tile copies with them the way the function
-- above changes each pixel (detailed_weather_dll.cpp: PAINTING): {m = the matrix (9, by rows), soil
-- = gains or nil, lean = gains or nil, dark, lighten}. nil for ice, whose change is another sum.
function recolour_numbers(class, look)
    recolourer(class, look)
    return recolour_params[class .. ':' .. look.temperature .. ':' .. look.wet]
end

-- Whether a class's copy is its colour change alone (redraw's COLOUR ONLY, BY COLOUR): no dry or wet
-- effects, so the DLL can paint it.
function colour_only_class(class)
    return not (class == 'grass' or GROUND[class] or class == 'ice')
end


----------------------------------------------------------------------------------------------
-- Dry
----------------------------------------------------------------------------------------------

-- The darkest share deepened (or, given `towards`, turned that far towards it), the rest
-- brightened to keep the mean lightness.
local function deepen(r, g, b, share, dark, towards)
    if share <= 0 then return end
    local lum = {}
    local before = 0
    local count = 0
    for n = 1, N do
        lum[n] = lum_of(r[n], g[n], b[n])
        if not shown or shown[n] then before, count = before + lum[n], count + 1 end
    end
    local cut = quantile(sorted(lum), share)
    local depth, after, rest_sum = {}, 0, 0
    for n = 1, N do
        local d = (cut - lum[n]) / 18 + 0.5
        d = d < 0 and 0 or d > 1 and 1 or d
        if shown and not shown[n] then d = 0 end
        depth[n] = d
        if towards then
            local k = d * dark
            r[n] = r[n] + (towards[1] - r[n]) * k
            g[n] = g[n] + (towards[2] - g[n]) * k
            b[n] = b[n] + (towards[3] - b[n]) * k
        else
            local f = 1 - d * (1 - dark)
            r[n], g[n], b[n] = r[n] * f, g[n] * f, b[n] * f
        end
        if not shown or shown[n] then
            after = after + lum_of(r[n], g[n], b[n])
            rest_sum = rest_sum + (1 - d)
        end
    end
    if after <= 0 or rest_sum <= 0 then return end
    local spare = (before / after - 1) * count / rest_sum
    for n = 1, N do
        local f = 1 + spare * (1 - depth[n])
        r[n], g[n], b[n] = r[n] * f, g[n] * f, b[n] * f
    end
end

local grain   -- sand's grain rank per pixel (0-1), from art/heat_patterns.png's first piece
local grain_texpos   -- (NATIVE REDRAW) that piece's texture, whose pixels the DLL reads
local art_dir = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or '') .. '../../../art/'
local function sand_grain()
    if grain then return grain end
    grain = {}
    local handles = dfhack.textures.loadTileset(art_dir .. 'heat_patterns.png', TILE, TILE, true)
    grain_texpos = dfhack.textures.getTexposByHandle(handles[1])
    local px = grass.pixels_of(grain_texpos)
    for n = 1, N do grain[n] = px and px[n][3] / 255 or 0.5 end
    return grain
end

local function dry_sand(r, g, b, dryness)
    local mean, count = 0, 0
    for n = 1, N do
        if not shown or shown[n] then mean, count = mean + lum_of(r[n], g[n], b[n]), count + 1 end
    end
    mean = count > 0 and mean / count or 0
    local contrast = 1 + SAND_CONTRAST * dryness
    local gr = sand_grain()
    for n = 1, N do
        local f = gr[n] > 1 - SAND_GLINTS * dryness and 1 + SAND_GLINT_LIFT
            or gr[n] < SAND_GRAINS * dryness and 1 - SAND_GRAIN_DARK or 1
        r[n] = (mean + (r[n] - mean) * contrast) * f
        g[n] = (mean + (g[n] - mean) * contrast) * f
        b[n] = (mean + (b[n] - mean) * contrast) * f
    end
end

----------------------------------------------------------------------------------------------
-- Wet
----------------------------------------------------------------------------------------------

-- (lit faces 0-1, hollows 0-1), from the brightness: bright parts are the raised ones, lit from
-- the north-west.
local function structure(lum)
    local blurred = box(lum, 1)
    local height = {}
    for n = 1, N do height[n] = 0.6 * lum[n] + 0.4 * blurred[n] end
    local north_west = shifted(height, -1, -1)
    local lit = {}
    for n = 1, N do local v = height[n] - north_west[n] lit[n] = v > 0 and v or 0 end
    local top = math.max(1e-6, quantile(sorted(lit), 0.97))
    for n = 1, N do local v = lit[n] / top lit[n] = v > 1 and 1 or v end
    local around = box(lum, 2)
    local hollow = {}
    for n = 1, N do local v = (around[n] - lum[n]) / 14 hollow[n] = v < 0 and 0 or v > 1 and 1 or v end
    return lit, hollow
end

-- Sand: the valley directly above each light line (the shade of a dune ridge), fading off.
local function sand_valleys(lum)
    local lines = top_share(lum, SAND_LINE_SHARE)
    local valley = {}
    for n = 1, N do valley[n] = 0 end
    for row = 1, SAND_VALLEY_ROWS do
        local moved = shifted(lines, 0, row)
        local k = 1 - (row - 1) / SAND_VALLEY_ROWS
        for n = 1, N do local v = moved[n] * k if v > valley[n] then valley[n] = v end end
    end
    for n = 1, N do local v = valley[n] - lines[n] valley[n] = v < 0 and 0 or v end
    return valley
end

local function wet(r, g, b, kind, weather, amount)
    local k = WET_KINDS[kind]
    local lum = {}
    for n = 1, N do lum[n] = lum_of(r[n], g[n], b[n]) end
    lum = filled(lum)
    local lit, hollow = structure(lum)
    local fr, fg, fb = {}, {}, {}   -- the overlay at full strength
    for n = 1, N do fr[n], fg[n], fb[n] = r[n], g[n], b[n] end
    if kind == 'sand' then
        local valley = sand_valleys(lum)
        for n = 1, N do
            local f = 1 - valley[n] * SAND_VALLEY_DARK * amount
            fr[n], fg[n], fb[n] = fr[n] * f, fg[n] * f, fb[n] * f
        end
    end
    local lit_sorted = sorted(lit)
    if weather == 'cold' then
        local rime = top_share(lit, k.rime * amount, lit_sorted)
        for n = 1, N do
            blend(fr, fg, fb, n, ICE_GLAZE, hollow[n] * GLAZE * amount)
            blend(fr, fg, fb, n, RIME, rime[n] * RIME_OPACITY)
        end
    else
        for n = 1, N do
            local f = 1 - hollow[n] * k.soak * amount
            fr[n], fg[n], fb[n] = fr[n] * f, fg[n] * f, fb[n] * f
            blend(fr, fg, fb, n, SKY, hollow[n] * k.sheen * amount)
        end
        local share, colour, sheen = k.glint, GLINT, 0
        if weather == 'hot' then share, colour, sheen = k.glint * HOT_GLINTS, WARM_GLINT, HOT_SHEEN end
        local glints = top_share(lit, share * amount, lit_sorted)
        for n = 1, N do
            if sheen > 0 then blend(fr, fg, fb, n, colour, lit[n] * sheen * amount) end
            blend(fr, fg, fb, n, colour, glints[n] * k.glint_strength)
        end
    end
    -- the overlay at OPACITY, over the tile as it was
    local out_r, out_g, out_b = {}, {}, {}
    for n = 1, N do
        out_r[n] = r[n] + (fr[n] - r[n]) * OPACITY
        out_g[n] = g[n] + (fg[n] - g[n]) * OPACITY
        out_b[n] = b[n] + (fb[n] - b[n]) * OPACITY
    end
    if weather ~= 'cold' then
        if kind == 'dirt' then
            -- its reddish-purple cracks turn a dark, wet brown
            for n = 1, N do
                local c = (math.min(r[n], b[n]) - g[n]) / 8
                c = c < 0 and 0 or c > 1 and 1 or c
                blend(out_r, out_g, out_b, n, WET_CRACK, c * WET_CRACK_STRENGTH * amount)
            end
        elseif JOINT_SHARE[kind] then
            local negative = {}
            for n = 1, N do negative[n] = -lum[n] end
            local joints = top_share(negative, JOINT_SHARE[kind])
            for n = 1, N do blend(out_r, out_g, out_b, n, WET_JOINT, joints[n] * WET_CRACK_STRENGTH * amount) end
        end
    end
    -- the most lit points catch the light, each with a faint shade above it
    local points = top_share(lit, k.rime * amount * HIGHLIGHT_SHARE, lit_sorted)
    local colour = weather == 'cold' and WHITE or weather == 'hot' and WARM_GLINT or GLINT
    if SHADE[weather] > 0 then
        local below = shifted(points, 0, 1)
        for n = 1, N do
            local s = below[n] - points[n]
            if s > 0 then
                local f = 1 - s * SHADE[weather]
                out_r[n], out_g[n], out_b[n] = out_r[n] * f, out_g[n] * f, out_b[n] * f
            end
        end
    end
    local kind_opacity = KIND_OPACITY[kind] or 1
    for n = 1, N do
        blend(out_r, out_g, out_b, n, colour, points[n] * HIGHLIGHT[weather])
        r[n] = r[n] + (out_r[n] - r[n]) * kind_opacity
        g[n] = g[n] + (out_g[n] - g[n]) * kind_opacity
        b[n] = b[n] + (out_b[n] - b[n]) * kind_opacity
    end
end

-- NATIVE REDRAW (grungeisdead's copy, 2026-11-18): everything the hook DLL needs to redraw a texture of
-- a class for a look as redraw does with its effects (detailed_weather_dll.cpp: THE FULL REDRAW): the
-- colour change's numbers, and cls (1 grass, 2 dirt, 3 sand, 4 stone, 5 pebbles, 6 ice; 0: colour only),
-- dryness, wet (the wet effect's amount, 0 for none), weather (0 cold, 1 mild, 2 hot), thaw (ice), grain
-- (sand: the address of the grain piece's pixels, or nil). nil if there are no numbers for it.
local CLASS_IDS = {grass = 1, dirt = 2, sand = 3, stone = 4, pebbles = 5, ice = 6}
local WEATHER_IDS = {cold = 0, mild = 1, hot = 2}
function native_numbers(class, look)
    local p = recolour_numbers(class, look)
    if not p then return nil end
    local t, w = shares(look)
    local out = {m = p.m, soil = p.soil, lean = p.lean, dark = p.dark, lighten = p.lighten,
                 cls = 0, dryness = 0, wet = 0, weather = 1, thaw = 0}
    if p.ice then
        out.ice_k, out.ice_dark, out.dark, out.lighten = p.k, p.dark, 1, 0
        out.cls = CLASS_IDS.ice
        out.thaw = math.max(0, math.min(1, (t - ICE_THAW_FROM) / -ICE_THAW_FROM))
    elseif class == 'grass' or GROUND[class] then
        out.cls = CLASS_IDS[class]
        out.dryness = w < 0.5 and 1 - 2 * w or 0
        out.wet = w > 0.5 and (w - 0.5) * 2 or 0
        out.weather = WEATHER_IDS[weather_of(t)]
        if class == 'sand' and out.dryness > 0 then
            sand_grain()
            out.grain = grain_texpos and grass.original_address(grain_texpos) or nil
        end
    end
    return out
end

----------------------------------------------------------------------------------------------
-- A whole texture
----------------------------------------------------------------------------------------------

-- COLOUR ONLY, BY COLOUR (grungeisdead's copy, 2026-11-16). With no dry, wet or ice effects to
-- apply (trees, shrubs, boulders, buildings, wood: every class but grass, bare ground and ice, and
-- any class asked for colour only), a pixel's new colour depends on its own colour alone. It was
-- worked out for all 1024 pixels of every picture: 0.75 of the 0.82 ms each copy of a tree's part
-- took (measured 2026-11-16), so a level of new trees filled in a few pictures a frame. A picture
-- has a few dozen colours, so each is worked out once per class and look and kept: the same
-- numbers, rounded and clamped as below. [class:temperature:wet] = {[rgb] = packed bgr}.
local colour_memo = {}
local function colour_only(px, class, look)
    local key = class .. ':' .. look.temperature .. ':' .. look.wet
    local memo = colour_memo[key]
    if not memo then memo = {} colour_memo[key] = memo end
    local recolour = recolourer(class, look)
    local out = {}
    for n = 1, N do
        local p = px[n]
        local rgb = (p[3] << 16) | (p[2] << 8) | p[1]
        local v = memo[rgb]
        if not v then
            local nr, ng, nb = recolour(p[1], p[2], p[3])
            nr = nr < 0 and 0 or nr > 255 and 255 or math.floor(nr + 0.5)
            ng = ng < 0 and 0 or ng > 255 and 255 or math.floor(ng + 0.5)
            nb = nb < 0 and 0 or nb > 255 and 255 or math.floor(nb + 0.5)
            v = (nb << 16) | (ng << 8) | nr
            memo[rgb] = v
        end
        out[n] = (p[4] << 24) | v
    end
    return out
end

-- The texture's pixels redrawn for the look, packed for dfhack.textures.createTile, or nil.
-- `effects` false leaves out the dry and wet effects (colour only).
function redraw(texpos, class, look, effects)
    local px = grass.pixels_of(texpos)
    if not px then return nil end
    -- COLOUR ONLY, BY COLOUR: nothing below but the colour for these
    if effects == false or not (class == 'grass' or GROUND[class] or class == 'ice') then
        return colour_only(px, class, look)
    end
    local recolour = recolourer(class, look)
    local r, g, b, a = {}, {}, {}, {}
    shown = nil
    for n = 1, N do
        local p = px[n]
        r[n], g[n], b[n] = recolour(p[1], p[2], p[3])
        a[n] = p[4]
        if a[n] == 0 and not shown then shown = {} end
    end
    if shown then for n = 1, N do shown[n] = a[n] > 0 end end
    if effects ~= false and (class == 'grass' or GROUND[class]) then
        local t, w = shares(look)
        local dryness = w < 0.5 and 1 - 2 * w or 0
        if dryness > 0 then
            if class == 'sand' then dry_sand(r, g, b, dryness)
            elseif class == 'grass' then deepen(r, g, b, DRY_SHARE * dryness, GRASS_GAP_STRENGTH, GRASS_GAP)
            elseif class ~= 'dirt' then deepen(r, g, b, DRY_SHARE * dryness, DRY_DARK) end
        end
        if w > 0.5 then wet(r, g, b, class, weather_of(t), (w - 0.5) * 2) end
    elseif effects ~= false and class == 'ice' then
        -- glints on its brightest points as it nears thawing, as on wet glass
        local t = shares(look)
        local thaw = math.max(0, math.min(1, (t - ICE_THAW_FROM) / -ICE_THAW_FROM))
        if thaw > 0 then
            local lum = {}
            for n = 1, N do lum[n] = lum_of(r[n], g[n], b[n]) end
            local lit = structure(filled(lum))
            local glints = top_share(lit, ICE_GLINTS * thaw, sorted(lit))
            for n = 1, N do blend(r, g, b, n, WHITE, glints[n] * ICE_GLINT_STRENGTH) end
        end
    end
    local out = {}
    for n = 1, N do
        local nr, ng, nb = r[n], g[n], b[n]
        nr = nr < 0 and 0 or nr > 255 and 255 or math.floor(nr + 0.5)
        ng = ng < 0 and 0 or ng > 255 and 255 or math.floor(ng + 0.5)
        nb = nb < 0 and 0 or nb > 255 and 255 or math.floor(nb + 0.5)
        out[n] = (a[n] << 24) | (nb << 16) | (ng << 8) | nr
    end
    return out
end

-- A look's name, for keys and the status line.
function look_key(look) return look.temperature .. ':' .. look.wet end
