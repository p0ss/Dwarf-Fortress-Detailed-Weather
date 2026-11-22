-- Ground for Detailed Weather: lying snow, frost, a temperature tint and heat shimmer, all baked
-- into the ground layer (screentexpos_background) so creatures and buildings stay on top.
--
-- Snow: the game keeps how much snow lies on each tile (a powder-water spatter, 0-255), and
-- vanilla draws it in screentexpos_spatter as outlined blobs. Here each tile's snow is blended
-- with its neighbours' at the tile corners, so patches have soft, ragged edges rather than tile
-- edges; the ground's bright points (blade tips, pebble tops) catch it first, so a thin cover
-- still shows the ground's texture; the snow itself is vanilla's own (its full-cover tiles), lit
-- from the north at patch edges, as in Rounded Hills. Where this
-- draws a tile's snow, the game's snow spatter on it is cleared (other spatters are left), and
-- the overhangs from neighbouring tiles' ground, which would draw over it.
--
-- Ramps hold snow too (the game keeps it on them) but vanilla never draws it there. A ramp's
-- texture already carries its slope's light and shade (e.g. Rounded Hills'), so snow on a ramp
-- takes on that light and shade, measured against the same material on flat ground nearby: a
-- slope facing away from the light stays darker than the flat snow beside it, as its skirt
-- shadow expects.
--
-- Temperature: each tile's own (block.temperature_1, in the game's units: 10000 is freezing and
-- each 9 is 5 C). Frost rime forms on the bright points below about 2 C; the ground takes a faint
-- cool or warm cast; above 25 C it shimmers, each row of pixels wavering sideways.
--
-- Prototyped offline in tools/weather/snow_test.py and temperature_test.py.
--@ module = true

local grass = reqscript('internal/detailed_weather/grass')

local TILE = 32
local NOISE_SIZE = 256        -- the noise repeats every 8 tiles
local VARIANTS = NOISE_SIZE // TILE

-- Snow
local COVER_STEPS = 8         -- snow at each tile corner is rounded to eighths, so bakes get reused
local RELIEF = 0.4            -- how much the ground's bright points lead the snow (0: noise only)
local RELIEF_GAIN = 2.5       -- how strongly a pixel's brightness (against its tile's) counts
local SOFT_EDGE = 0.07
local NORTH_LIGHT = 1.5
local SNOW_SHADOW = {196, 207, 224}   -- from vanilla's snow.png
-- vanilla's full-cover snow tiles (FULL_NSWE_A-E on the SNOW page), used to fill the snow
local SNOW_FILL_CELLS = {{0, 0}, {0, 4}, {1, 4}, {2, 4}, {3, 4}}
local SNOW_LIGHT = {255, 255, 255}
local RAMP_SHADING = 1.0      -- how much of a ramp's light and shade the snow on it takes

-- Frost and tint
local FROST_STARTS, FROST_FULL = 2, -12   -- C
local FROST_STEPS = 6
local FROST_MOST = 0.45       -- share of pixels rimed at the coldest
local FROST_RELIEF = 0.7      -- rime is mostly on the bright points; the rest is fine speckle
local FROST_OPACITY = 0.55
local FROST = {222, 233, 244}
local COOL_FROM, WARM_FROM, WARM_FULL = 10, 20, 38
local TINT_STEPS = 4
local TINT_MOST = 0.08
local COOL_TINT = {150, 178, 214}
local WARM_TINT = {255, 196, 138}

-- Heat shimmer
local SHIMMER_STARTS, SHIMMER_FULL = 25, 38
local SHIMMER_STEPS = 2
local SHIMMER_PX = 1.2        -- sideways waver at full heat
local SHIMMER_PHASES = 6      -- frames in one waver; each is a baked texture
local SHIMMER_BANDS = 0.55    -- radians per px down the tile

local BAKES_PER_FRAME = 4    -- each takes ~2.5 ms
local TEXPOS_RECHECK_FRAMES = 600
local REMEMBER_MS = 2000      -- how long a tile's plan is kept before it's worked out again
local REMEMBER_MOST = 40000   -- tiles remembered; past this the memory starts afresh

remembered = remembered or {}
remembered_count = remembered_count or 0
remembered_z = remembered_z or nil
local CACHE_LIMIT = 10000   -- 4 KB each; a busy hillside view needs several thousand

forced_celsius = forced_celsius or nil
-- Lying snow is drawn by the game from Detailed Weather's snow art now (graphics/snow_cover.png),
-- so by default this only draws frost, the temperature tint and heat shimmer.
draw_snow = draw_snow or false
-- running averages of how long planning and drawing take, in ms (`detailed_weather` shows them)
timing = timing or {plan = 0, apply = 0}
local TIMING_SMOOTHING = 0.05   -- set by `detailed_weather temperature N` for testing

----------------------------------------------------------------------------------------------
-- Noise: smooth value noise, tiling every NOISE_SIZE px, 0-1
----------------------------------------------------------------------------------------------

-- Re-maps values to 0-1 by rank, so that 'the lowest 30%' is exactly the values below 0.3. Summed
-- noise bunches up around the middle; without this, snow edges sit on the tile borders.
local function evenly_spread(values)
    local order = {}
    for i = 1, #values do order[i] = i end
    table.sort(order, function(a, b) return values[a] < values[b] end)
    local out = {}
    for rank, i in ipairs(order) do out[i] = (rank - 1) / (#values - 1) end
    return out
end

local function make_noise(seed, cells, weights)
    local rng = dfhack.random.new(seed)
    local total = {}
    for i = 1, NOISE_SIZE * NOISE_SIZE do total[i] = 0 end
    for n, cell in ipairs(cells) do
        local count = NOISE_SIZE // cell
        local grid = {}
        for i = 1, count * count do grid[i] = rng:drandom() end
        local function at(gx, gy) return grid[(gy % count) * count + (gx % count) + 1] end
        for y = 0, NOISE_SIZE - 1 do
            for x = 0, NOISE_SIZE - 1 do
                local fx, fy = x / cell, y / cell
                local gx, gy = math.floor(fx), math.floor(fy)
                local tx, ty = fx - gx, fy - gy
                tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)   -- smoothstep
                local top = at(gx, gy) + (at(gx + 1, gy) - at(gx, gy)) * tx
                local bottom = at(gx, gy + 1) + (at(gx + 1, gy + 1) - at(gx, gy + 1)) * tx
                local i = y * NOISE_SIZE + x + 1
                total[i] = total[i] + weights[n] * (top + (bottom - top) * ty)
            end
        end
    end
    return evenly_spread(total)
end

-- Snow: large shapes first, so patch edges meander across a tile or so rather than fizzing.
-- Frost: fine speckle, which doesn't show the noise repeating.
local noise, speckle
local function ensure_noise()
    if noise then return end
    noise = make_noise(3, {32, 16, 4}, {0.55, 0.3, 0.15})
    speckle = make_noise(4, {1}, {1})
end

----------------------------------------------------------------------------------------------
-- What's on each tile
----------------------------------------------------------------------------------------------

local WATER = 6   -- builtin material number of water

-- A map block's powder-water spatters (its snow), or nil. Their amounts are read only for the
-- tiles needed.
local function block_snow(block)
    local events
    for _, event in ipairs(block.block_events) do
        if df.block_square_event_material_spatterst:is_instance(event) and event.mat_type == WATER
                and event.mat_state == df.matter_state.Powder then
            events = events or {}
            events[#events + 1] = event.amount
        end
    end
    return events
end

local function celsius(units) return (units - 10000) * 5 / 9 end

local function between(value, start, full)
    local share = (value - start) / (full - start)
    return share < 0 and 0 or share > 1 and 1 or share
end

local function steps(share, count) return math.floor(share * count + 0.5) end

-- The game's snow spatter art: every texpos on its page (to know which spatters to clear), and
-- its full-cover tiles' pixels (to fill our snow with).
local snow_art, snow_fills
local function find_snow_art()
    snow_art, snow_fills = {}, {}
    for _, page in ipairs(df.global.texture.page) do
        if page.token == 'SNOW' then
            for _, t in ipairs(page.texpos) do snow_art[t] = true end
            for _, cell in ipairs(SNOW_FILL_CELLS) do
                local px = grass.pixels_of(page.texpos[cell[2] * page.page_dim_x + cell[1]])
                if px then snow_fills[#snow_fills + 1] = px end
            end
        end
    end
end

local function is_snow_art(texpos)
    if not snow_art then find_snow_art() end
    return snow_art[texpos]
end

----------------------------------------------------------------------------------------------
-- Baking
----------------------------------------------------------------------------------------------

baked = baked or {}
baked_count = baked_count or 0
frame_number = frame_number or 0

function clear_cache()
    remembered, remembered_count = {}, 0
    for _, entry in pairs(baked) do grass.discard(entry.handle, 'old ground experiment') end
    baked, baked_count = {}, 0
end

-- As in grass.lua: free the least recently shown once there are too many, keeping anything shown
-- in the last few frames (its texpos may still be in the buffers the game is about to draw).
local function trim_cache()
    -- (nothing is thrown out for the cache being big unless textures are being deleted: grass.lua)
    if not grass.delete_textures or baked_count <= CACHE_LIMIT then return end
    local old = {}
    for key, entry in pairs(baked) do
        if entry.used < frame_number - 2 then old[#old + 1] = {key = key, used = entry.used} end
    end
    table.sort(old, function(a, b) return a.used < b.used end)
    for n = 1, math.min(#old, baked_count - CACHE_LIMIT * 3 // 4) do
        local entry = baked[old[n].key]
        if entry.handle then grass.discard(entry.handle, 'old ground experiment') end
        baked[old[n].key] = nil
        baked_count = baked_count - 1
    end
end

-- The look of one tile, as pixels ready for createTile (one integer each: R, G, B, A in memory).
-- look: corners (snow at NW, NE, SW, SE, in COVER_STEPS), frost, tint (negative cool, positive
-- warm), shimmer (strength step and phase), variant (which part of the noise this tile uses, so
-- neighbouring tiles join up). Works on plain arrays of channels: this runs for every new
-- texture, so it avoids making a table per pixel.
function bake_pixels(base, look)
    local source = grass.pixels_of(base)
    if not source then return nil end
    ensure_noise()
    local PIXELS = TILE * TILE
    local red, green, blue, alpha = {}, {}, {}, {}

    -- Shimmer first: each row shifted sideways, sampled from the unshifted ground.
    local shift_px = look.shimmer > 0 and SHIMMER_PX * look.shimmer / SHIMMER_STEPS or 0
    for y = 0, TILE - 1 do
        local shift = 0
        if shift_px > 0 then
            shift = math.floor(math.sin(y * SHIMMER_BANDS + look.phase * 2 * math.pi / SHIMMER_PHASES) * shift_px + 0.5)
        end
        for x = 0, TILE - 1 do
            local s = source[y * TILE + (x - shift) % TILE + 1]
            local i = y * TILE + x + 1
            red[i], green[i], blue[i], alpha[i] = s[1], s[2], s[3], s[4]
        end
    end

    -- Which pixels whiten first: the bright points of this tile, broken up by noise.
    local brightness, mean = {}, 0
    for i = 1, PIXELS do
        local b = (red[i] * 0.299 + green[i] * 0.587 + blue[i] * 0.114) / 255
        brightness[i] = b
        mean = mean + b
    end
    mean = mean / PIXELS
    -- a ramp's light and shade is measured against its material on flat ground, if one is near
    local flat_mean = mean
    if look.ramp and look.flat_base then
        local flat = grass.pixels_of(look.flat_base)
        if flat then
            flat_mean = 0
            for _, p in ipairs(flat) do flat_mean = flat_mean + (p[1] * 0.299 + p[2] * 0.587 + p[3] * 0.114) / 255 end
            flat_mean = flat_mean / #flat
        end
    end
    -- On a ramp, brightness is the slope's light and shade, not the ground's bright points, so
    -- the snow goes by the noise alone.
    local relief_share = look.ramp and 0 or RELIEF
    local order, frost_order = {}, {}
    local nx0, ny0 = look.variant_x * TILE, look.variant_y * TILE
    for y = 0, TILE - 1 do
        local row = (ny0 + y) * NOISE_SIZE + nx0 + 1
        for x = 0, TILE - 1 do
            local i = y * TILE + x + 1
            local relief = 0.5 - (brightness[i] - mean) * RELIEF_GAIN
            order[i] = (1 - relief_share) * noise[row + x] + relief_share * relief
            frost_order[i] = FROST_RELIEF * relief + (1 - FROST_RELIEF) * speckle[row + x]
        end
    end

    -- Snow: cover blended between the corners, against the order.
    local c = look.corners
    local snow = {}
    for i = 1, PIXELS do snow[i] = 0 end
    if c[1] + c[2] + c[3] + c[4] > 0 then
        for y = 0, TILE - 1 do
            local v = (y + 0.5) / TILE
            local west = (c[1] * (1 - v) + c[3] * v) / COVER_STEPS
            local east = (c[2] * (1 - v) + c[4] * v) / COVER_STEPS
            for x = 0, TILE - 1 do
                local u = (x + 0.5) / TILE
                local i = y * TILE + x + 1
                local amount = (west + (east - west) * u - order[i]) / SOFT_EDGE
                snow[i] = amount < 0 and 0 or amount > 1 and 1 or amount
            end
        end
        if not snow_fills then find_snow_art() end
        -- which of vanilla's fill tiles: fixed by where the tile is, so it doesn't add to the cache
        local fill = snow_fills[(look.variant_x + look.variant_y * VARIANTS) % #snow_fills + 1]
        for y = 0, TILE - 1 do
            for x = 0, TILE - 1 do
                local i = y * TILE + x + 1
                local amount = snow[i]
                if amount > 0 then
                    -- lit from the north: brighter where the snow rises southward, shadowed where it falls
                    local above, below = 0, 0
                    for d = 1, 3 do
                        above = above + snow[(y - d < 0 and 0 or y - d) * TILE + x + 1]
                        below = below + snow[(y + d > TILE - 1 and TILE - 1 or y + d) * TILE + x + 1]
                    end
                    local facing = (below - above) / 3 * NORTH_LIGHT
                    local f_px = fill and fill[i] or {243, 245, 248}
                    local r, g, b = f_px[1], f_px[2], f_px[3]
                    if look.ramp then
                        -- the slope's light and shade, against the same material on flat ground
                        local shade = 1 + (brightness[i] / flat_mean - 1) * RAMP_SHADING
                        r, g, b = r * shade, g * shade, b * shade
                    end
                    local towards = facing > 0 and SNOW_LIGHT or SNOW_SHADOW
                    local f = facing > 0 and facing or -facing
                    if f > 1 then f = 1 end
                    r, g, b = r + (towards[1] - r) * f, g + (towards[2] - g) * f, b + (towards[3] - b) * f
                    red[i] = red[i] + (r - red[i]) * amount
                    green[i] = green[i] + (g - green[i]) * amount
                    blue[i] = blue[i] + (b - blue[i]) * amount
                end
            end
        end
    end

    -- Frost: rime on the bright points, the same order as the snow.
    if look.frost > 0 then
        local reach = look.frost / FROST_STEPS * FROST_MOST
        for i = 1, PIXELS do
            local amount = (reach - frost_order[i]) / 0.05
            if amount > 0 then
                amount = (amount > 1 and 1 or amount) * FROST_OPACITY * (1 - snow[i])
                red[i] = red[i] + (FROST[1] - red[i]) * amount
                green[i] = green[i] + (FROST[2] - green[i]) * amount
                blue[i] = blue[i] + (FROST[3] - blue[i]) * amount
            end
        end
    end

    -- Tint over everything, then pack.
    local tint = look.tint < 0 and COOL_TINT or WARM_TINT
    local tint_amount = math.abs(look.tint) / TINT_STEPS * TINT_MOST
    local out = {}
    for i = 1, PIXELS do
        local r = red[i] + (tint[1] - red[i]) * tint_amount
        local g = green[i] + (tint[2] - green[i]) * tint_amount
        local b = blue[i] + (tint[3] - blue[i]) * tint_amount
        r = r < 0 and 0 or r > 255 and 255 or math.floor(r + 0.5)
        g = g < 0 and 0 or g > 255 and 255 or math.floor(g + 0.5)
        b = b < 0 and 0 or b > 255 and 255 or math.floor(b + 0.5)
        out[i] = (alpha[i] << 24) | (b << 16) | (g << 8) | r
    end
    return out
end

local function look_key(base, look)
    local c = look.corners
    return table.concat({base, c[1], c[2], c[3], c[4], look.frost, look.tint, look.shimmer, look.phase,
                         look.variant_x, look.variant_y, look.ramp and ('r' .. (look.flat_base or '')) or ''}, ':')
end

local function texture(key, base, look, state)
    local entry = baked[key]
    if not entry then
        if state.budget <= 0 then return nil end
        state.budget = state.budget - 1
        local px = bake_pixels(base, look)
        entry = {handle = px and dfhack.textures.createTile(px, TILE, TILE) or false}
        baked[key] = entry
        baked_count = baked_count + 1
    end
    entry.used = frame_number
    if not entry.handle then return nil end
    -- the texpos is kept rather than asked for every frame, but checked now and then, since a
    -- reload of the game's textures can move it
    if not entry.texpos or frame_number - entry.fetched > TEXPOS_RECHECK_FRAMES then
        entry.texpos, entry.fetched = dfhack.textures.getTexposByHandle(entry.handle), frame_number
    end
    return entry.texpos
end

----------------------------------------------------------------------------------------------
-- Planning and drawing
----------------------------------------------------------------------------------------------

-- The game draws the levels below through open space from its lower viewports: lower_viewport[d - 1]
-- holds the ground d levels down, laid out like the main one. depth 0 is the main viewport.
local MOST_DEPTH = 8

local function viewport_at(depth)
    return depth == 0 and df.global.gps.main_viewport or df.global.gps.lower_viewport[depth - 1]
end

local EMPTY, RAMP_TOP, RAMP, FLOOR = df.tiletype_shape.EMPTY, df.tiletype_shape.RAMP_TOP,
    df.tiletype_shape.RAMP, df.tiletype_shape.FLOOR
local FLOOR_LIKE = df.tiletype_shape_basic.Floor

-- What matters about a tiletype, in a plain table. Looking up df.tiletype.attrs costs ~40 us a
-- time, so each tiletype is looked up once.
local tiletype_info = {}
local function info_of(tiletype)
    local info = tiletype_info[tiletype]
    if not info then
        local attrs = df.tiletype.attrs[tiletype]
        info = {shape = attrs.shape, material = attrs.material,
                floor_like = df.tiletype_shape.attrs[attrs.shape].basic_shape == FLOOR_LIKE}
        tiletype_info[tiletype] = info
    end
    return info
end

-- For every outdoor floor or ramp tile shown in view, on this level or below it through open
-- space: its ground texture and what to draw on it. Done every few frames; apply() draws it every
-- frame, since the game rebuilds its screen layers.
function plan(viewport)
    local started = dfhack.getTickCount()
    local main = df.global.gps.main_viewport

    -- Map blocks, and their snow amounts, looked up once each: reading tiles straight from the
    -- block saves several calls into the game per tile.
    local blocks, snow = {}, {}
    local function block_at(x, y, z)
        local key = ((z * 1024) + x // 16) * 1024 + (y // 16)
        local block = blocks[key]
        if block == nil then
            block = dfhack.maps.getTileBlock(x, y, z) or false
            blocks[key] = block
            snow[key] = block and block_snow(block) or false
        end
        return block or nil, key
    end
    local function attrs_at(x, y, z)
        local block = block_at(x, y, z)
        return block and info_of(block.tiletype[x % 16][y % 16])
    end
    local snow_seen = {}
    local function snow_at(x, y, z)
        local tile_key = (z * 4096 + x) * 4096 + y
        local amount = snow_seen[tile_key]
        if amount then return amount end
        local _, key = block_at(x, y, z)
        amount = 0
        for _, amounts in ipairs(snow[key] or {}) do
            local a = amounts[x % 16][y % 16]
            if a > amount then amount = a end
        end
        snow_seen[tile_key] = amount
        return amount
    end
    local function see_through(x, y, z)
        local attrs = attrs_at(x, y, z)
        return attrs and (attrs.shape == EMPTY or attrs.shape == RAMP_TOP)
    end
    local function corner(x, y, z)   -- the corner at the NW of tile (x, y)
        local total = snow_at(x - 1, y - 1, z) + snow_at(x, y - 1, z) + snow_at(x - 1, y, z) + snow_at(x, y, z)
        return steps(total / 4 / 255, COVER_STEPS)
    end

    -- A ramp's material on flat ground: the ground texture of the nearest flat tile of the same
    -- material, within two tiles, as the game drew it this frame at the same depth.
    local function flat_neighbour(x, y, z, port)
        local material = attrs_at(x, y, z).material
        for reach = 1, 2 do
            for dy = -reach, reach do
                for dx = -reach, reach do
                    local nx, ny = x + dx, y + dy
                    if (math.abs(dx) == reach or math.abs(dy) == reach)
                            and nx >= viewport.x1 and nx <= viewport.x2 and ny >= viewport.y1 and ny <= viewport.y2 then
                        local attrs = attrs_at(nx, ny, z)
                        if attrs and attrs.material == material and attrs.shape == FLOOR then
                            local base = port.screentexpos_background[(nx - viewport.x1) * port.dim_y + (ny - viewport.y1)]
                            if base > 0 then return base end
                        end
                    end
                end
            end
        end
    end

    -- Works out one tile from scratch: nil if there's nothing to draw on it.
    local function work_out(x, y, i)
        -- which level this screen tile shows
        local depth, z = 0, viewport.z
        while depth < MOST_DEPTH and see_through(x, y, z) do depth, z = depth + 1, z - 1 end
        local port = viewport_at(depth)
        local base = port.screentexpos_background[i]
        local block = base > 0 and block_at(x, y, z)
        local attrs = block and info_of(block.tiletype[x % 16][y % 16])
        local ramp = attrs and attrs.shape == RAMP
        if not (block and (ramp or attrs.floor_like) and block.designation[x % 16][y % 16].outside) then
            return {depth = depth, base = base, nothing = true}
        end
        local degrees = forced_celsius or celsius(block.temperature_1[x % 16][y % 16])
        local look = {
            corners = draw_snow and {corner(x, y, z), corner(x + 1, y, z), corner(x, y + 1, z), corner(x + 1, y + 1, z)}
                or {0, 0, 0, 0},
            frost = steps(between(degrees, FROST_STARTS, FROST_FULL), FROST_STEPS),
            tint = degrees < COOL_FROM and -steps(between(degrees, COOL_FROM, FROST_FULL), TINT_STEPS)
                or degrees > WARM_FROM and steps(between(degrees, WARM_FROM, WARM_FULL), TINT_STEPS) or 0,
            shimmer = steps(between(degrees, SHIMMER_STARTS, SHIMMER_FULL), SHIMMER_STEPS),
            phase = 0,
            variant_x = x % VARIANTS, variant_y = y % VARIANTS,
            ramp = ramp,
            flat_base = ramp and flat_neighbour(x, y, z, port) or nil,
        }
        local c = look.corners
        if c[1] + c[2] + c[3] + c[4] == 0 and look.frost == 0 and look.tint == 0 and look.shimmer == 0 then
            return {depth = depth, base = base, nothing = true}
        end
        local tile = {x = x, y = y, depth = depth, base = base, look = look,
                      snowy = c[1] + c[2] + c[3] + c[4] >= COVER_STEPS * 2}
        -- keys worked out once here, not every frame; one per shimmer phase
        if look.shimmer > 0 then
            tile.keys = {}
            for phase = 0, SHIMMER_PHASES - 1 do
                look.phase = phase
                tile.keys[phase] = look_key(base, look)
            end
        else
            tile.key = look_key(base, look)
        end
        return tile
    end

    -- Tiles are remembered by map position for a few seconds (snow and temperature change
    -- slowly), so a replan, or a pan of the view, only works out tiles that are new, changed or
    -- due. Each is due at a slightly different time, so the work is spread out.
    local now = dfhack.getTickCount()
    local backgrounds, floor_flags = {}, {}   -- each depth's screen layers, looked up once
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        backgrounds[depth], floor_flags[depth] = port.screentexpos_background, port.screentexpos_floor_flag
    end
    if remembered_z ~= viewport.z then remembered, remembered_count, remembered_z = {}, 0, viewport.z end
    if remembered_count > REMEMBER_MOST then remembered, remembered_count = {}, 0 end
    local tiles = {}
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
            local i = (x - viewport.x1) * main.dim_y + (y - viewport.y1)
            local key = x * 4096 + y
            local tile = remembered[key]
            if not tile or now >= tile.due or backgrounds[tile.depth][i] ~= tile.base then
                if not tile then remembered_count = remembered_count + 1 end
                local shown = tile and tile.shown
                tile = work_out(x, y, i)
                tile.due = now + REMEMBER_MS + math.random(0, REMEMBER_MS // 2)
                if tile.base == (remembered[key] or {}).base then tile.shown = shown end
                remembered[key] = tile
            end
            if not tile.nothing then
                tile.i = i
                tile.flag = floor_flags[tile.depth][i]
                tiles[#tiles + 1] = tile
            end
        end
    end
    timing.plan = timing.plan + (dfhack.getTickCount() - started - timing.plan) * TIMING_SMOOTHING * 4
    return tiles
end

-- frame: the animation frame, for the shimmer.
function apply(tiles, frame)
    local started = dfhack.getTickCount()
    -- each depth's screen layers, looked up once
    local backgrounds, spatters, floor_flags = {}, {}, {}
    for depth = 0, MOST_DEPTH do
        local port = viewport_at(depth)
        backgrounds[depth], spatters[depth], floor_flags[depth] =
            port.screentexpos_background, port.screentexpos_spatter, port.screentexpos_floor_flag
    end
    frame_number = frame_number + 1
    trim_cache()
    local state = {budget = BAKES_PER_FRAME}
    for _, t in ipairs(tiles) do
        local background = backgrounds[t.depth]
        if background[t.i] == t.base then
            local look = t.look
            local key = t.key
            if look.shimmer > 0 then
                look.phase = (frame + t.y) % SHIMMER_PHASES
                key = t.keys[look.phase]
            end
            -- a texture not baked yet keeps what the tile showed last, rather than flickering
            local shown = texture(key, t.base, look, state) or (look.shimmer == 0 and t.shown)
            if shown then
                background[t.i] = shown
                t.shown = shown
                local c = look.corners
                local spatter = spatters[t.depth]
                if c[1] + c[2] + c[3] + c[4] > 0 and is_snow_art(spatter[t.i]) then spatter[t.i] = 0 end
                -- overhangs from the ground next door (grass, soil, stone) would draw over the snow
                local floor_flag = floor_flags[t.depth]
                if t.snowy and floor_flag[t.i] == t.flag then floor_flag[t.i] = 0 end
            end
        end
    end
    timing.apply = timing.apply + (dfhack.getTickCount() - started - timing.apply) * TIMING_SMOOTHING
end
