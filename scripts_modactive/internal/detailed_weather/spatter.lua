-- Spatter in the grass, for Detailed Weather: fallen fruit, nuts and leaves (and blood and the
-- like) lying on a grass tile are drawn in the grass rather than on top of it. The game draws
-- spatter over the whole tile, so it looked laid on the grass, and once the grass leaned in the
-- wind it looked like the grass was sliding about under it (Poss).
--
-- Two layers, so neither has to be made for every pairing of the other:
--   the spatter   in its own layer, thinned (the game draws the same picture however much has
--                 fallen, so a tile with a little on it has some of its pieces left out, which by
--                 the tile's position so neighbours differ) and with a faint shadow under each
--                 piece where it touches the ground: one per spatter picture, tenth and pattern
--   the blades    in the layer above it (items', which draws over spatter but under creatures):
--                 the tile's own grass, just its brightest pixels (its blades), so they stand in
--                 front of the fruit. Over the grass they're cut from they change nothing; over
--                 the fruit they put it among the blades. One per grass picture, leaning frames
--                 too, so the blades lean with the grass while the fruit, on the ground, stays put.
--                 Left out where an item lies (it keeps the layer).
-- What's worked out from the game's own pictures (which pieces, the shadow, where the blades are)
-- is kept for good; only the recolouring is done again when the look changes.
--
-- Every frame the spatter layer in view is read and each piece on grass gets its versions (made
-- the first time they're needed, BAKE_MS a frame, and kept), so nothing waits on a plan when the
-- view moves.
--@ module = true

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)

local colour = reqscript('internal/detailed_weather/colour')
local grass = reqscript('internal/detailed_weather/grass')
local work_time = reqscript('internal/detailed_weather/work_time')   -- the frame's shared time for background work

local BLADES = 0.35            -- the brightest share of a grass's pixels count as blades in front
local BLADE_SOFT = 0.15        -- share of brightness over which a blade fades in
local BLADE_COVER = 0.85       -- how much a blade hides the spatter behind it
local SHADOW = {18, 22, 10}    -- the contact shadow's colour
local SHADOW_ALPHA = 70        -- and its opacity, just under a piece (half that a pixel further down)
-- the share of pieces kept, by the amount fallen on the tile: from LEAST_SHARE for a trace to
-- all of them at FULL_AMOUNT (amounts seen round a fort run from 1 to past 8000), in tenths
local FULL_AMOUNT = 8000
local LEAST_SHARE = 0.05
local VARIANTS = 4             -- patterns of which pieces are left out, by tile position
local AMOUNTS_KEEP_MS = 5000   -- how long a block's fallen amounts are kept
local BAKE_MS = 3
local BAKED_MOST = 6000
local TILE = 32

mode = mode or 'on'
blades_mode = blades_mode or 'on'   -- the grass's blades drawn in front of the spatter
allowance = allowance or 1          -- the share of its usual baking time a frame (settings.lua: less at low)
-- What's been made, each entry {handle =, texpos =}, or {} where there was nothing to make:
baked_pieces = baked_pieces or {}   -- piece_key(spatter texture, share, pattern) -> the thinned spatter
baked_blades = baked_blades or {}   -- grass texture showing -> its blades (also .original, .lean)
last_blades = last_blades or {}     -- grass original -> the blades last shown for it
baked_count = baked_count or 0
timing = timing or {apply = 0}

_G.detailed_weather_made = _G.detailed_weather_made or {}
local made = _G.detailed_weather_made

local function pack(r, g, b, a) return (a << 24) | (b << 16) | (g << 8) | r end

----------------------------------------------------------------------------------------------
-- The spatter, thinned and shadowed
----------------------------------------------------------------------------------------------

-- The pieces of a spatter picture: each pixel's piece (its run of solid pixels, touching
-- diagonally too), 0 where it's see-through; soft edge pixels go with the piece they touch.
local pieces_of = {}
local function pieces(spatter_texpos, px)
    local found = pieces_of[spatter_texpos]
    if found then return found end
    local label, count = {}, 0
    for i = 1, TILE * TILE do label[i] = 0 end
    for start = 1, TILE * TILE do
        if label[start] == 0 and px[start][4] >= 128 then
            count = count + 1
            local stack = {start}
            label[start] = count
            while #stack > 0 do
                local i = table.remove(stack)
                local x, y = (i - 1) % TILE, (i - 1) // TILE
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local nx, ny = x + dx, y + dy
                        if nx >= 0 and ny >= 0 and nx < TILE and ny < TILE then
                            local n = ny * TILE + nx + 1
                            if label[n] == 0 and px[n][4] >= 128 then label[n] = count stack[#stack + 1] = n end
                        end
                    end
                end
            end
        end
    end
    for i = 1, TILE * TILE do
        if label[i] == 0 and px[i][4] > 0 then
            local x, y = (i - 1) % TILE, (i - 1) // TILE
            for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                local nx, ny = x + d[1], y + d[2]
                if nx >= 0 and ny >= 0 and nx < TILE and ny < TILE and px[ny * TILE + nx + 1][4] >= 128 then
                    label[i] = label[ny * TILE + nx + 1]
                    break
                end
            end
        end
    end
    pieces_of[spatter_texpos] = label
    return label
end

-- Whether piece n is kept, for a share and a pattern (the same choice wherever it's asked).
local function kept(n, share, variant)
    if share >= 1 then return true end
    local h = (n * 2654435761 + variant * 40503) % 4294967296
    return (h % 1000) / 1000 < share
end

-- Per pixel, how much of the spatter shows and the shadow's opacity where it doesn't, from the
-- game's own spatter picture (so it holds for every look): kept.
masks = masks or {}
local function mask_for(spatter_original, share, variant)
    local key = spatter_original .. ':' .. share .. ':' .. variant
    local mask = masks[key]
    if mask ~= nil then return mask end
    local source = grass.pixels_of(spatter_original)
    if not source then masks[key] = false return false end
    local label = share < 1 and pieces(spatter_original, source)
    local alpha = {}
    for i, p in ipairs(source) do
        local n = label and label[i] or 0
        alpha[i] = (n ~= 0 and not kept(n, share, variant)) and 0 or p[4]
    end
    local function alpha_at(x, y)
        if x < 0 or y < 0 or x >= TILE or y >= TILE then return 0 end
        return alpha[y * TILE + x + 1]
    end
    local show, shadow = {}, {}
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local i = y * TILE + x + 1
            show[i] = source[i][4] > 0 and alpha[i] / source[i][4] or 0
            local s = 0
            if alpha[i] < 128 then
                local above = math.max(alpha_at(x, y - 1), alpha_at(x - 1, y - 1) * 0.5, alpha_at(x + 1, y - 1) * 0.5)
                s = above >= 128 and SHADOW_ALPHA or (alpha_at(x, y - 2) >= 128 and SHADOW_ALPHA // 2) or 0
            end
            shadow[i] = s
        end
    end
    mask = {show = show, shadow = shadow}
    masks[key] = mask
    return mask
end

-- The weather's copy of a piece of spatter (or the game's own) through its mask: one pass.
local function bake_spatter(spatter_texpos, mask)
    local px = grass.pixels_of(spatter_texpos)
    if not px then return nil end
    local show, shadow = mask.show, mask.shadow
    local out = {}
    for i = 1, TILE * TILE do
        local p = px[i]
        local a, s = p[4] * show[i], shadow[i]
        if s > a then out[i] = pack(SHADOW[1], SHADOW[2], SHADOW[3], s)
        else out[i] = pack(p[1], p[2], p[3], (a + 0.5) // 1) end
    end
    return out
end

----------------------------------------------------------------------------------------------
-- The blades over it
----------------------------------------------------------------------------------------------

-- How much each pixel of a grass is a blade in front (0..1), from its brightness, worked out from
-- the game's own grass picture and kept.
local blade_masks = {}
local function blade_mask(grass_original)
    local mask = blade_masks[grass_original]
    if mask ~= nil then return mask end
    local px = grass.pixels_of(grass_original)
    if not px then blade_masks[grass_original] = false return false end
    local values, sorted = {}, {}
    for i, p in ipairs(px) do
        values[i] = p[1] * 0.299 + p[2] * 0.587 + p[3] * 0.114
        sorted[i] = values[i]
    end
    table.sort(sorted)
    local from = sorted[math.max(1, (#sorted * (1 - BLADES)) // 1)]
    local to = sorted[math.max(1, math.min(#sorted, (#sorted * (1 - BLADES + BLADE_SOFT)) // 1))]
    local span = math.max(1, to - from)
    mask = {}
    for i, v in ipairs(values) do
        local m = (v - from) / span
        mask[i] = (m < 0 and 0 or m > 1 and 1 or m) * BLADE_COVER * px[i][4] / 255
    end
    blade_masks[grass_original] = mask
    return mask
end

-- The grass showing on a tile (the look's copy, or one of its leaning frames), just its blades.
local function bake_blades(grass_texpos, mask)
    local px = grass.pixels_of(grass_texpos)
    if not px then return nil end
    local out = {}
    for i = 1, TILE * TILE do
        local p = px[i]
        out[i] = pack(p[1], p[2], p[3], (mask[i] * 255 + 0.5) // 1)
    end
    return out
end

----------------------------------------------------------------------------------------------
-- Each frame
----------------------------------------------------------------------------------------------

-- Lets a made texture go. Through the shared trash (deleted a little each frame), not all at once:
-- deleting a few thousand in one frame holds the game up.
local function retire(entry)
    if not entry.handle then return end
    made[entry.texpos] = nil
    grass.discard(entry.handle, 'spatter in the grass')
    baked_count = baked_count - 1
end

local function clear_cache()
    for _, entry in pairs(baked_pieces) do retire(entry) end
    for _, entry in pairs(baked_blades) do retire(entry) end
    for _, entry in pairs(last_blades) do
        if entry.orphan then retire(entry) end   -- (the others are in baked_blades)
    end
    baked_pieces, baked_blades, last_blades = {}, {}, {}   -- (the masks hold for every look: kept)
end

-- The item spatter fallen on each tile of a block (all kinds together), read and kept a while.
local amounts = {}
local function fallen(x, y, z, now)
    local key = (z * 1024 + x // 16) * 1024 + y // 16
    local kept_block = amounts[key]
    if not kept_block or now - kept_block.at > AMOUNTS_KEEP_MS then
        local block = dfhack.maps.getTileBlock(x, y, z)
        local total = {}
        if block then
            for _, event in ipairs(block.block_events) do
                if df.block_square_event_item_spatterst:is_instance(event) then
                    for bx = 0, 15 do
                        local column = event.amount[bx]
                        for by = 0, 15 do
                            local a = column[by]
                            if a > 0 then total[bx * 16 + by] = (total[bx * 16 + by] or 0) + a end
                        end
                    end
                end
            end
        end
        kept_block = {total = total, at = now}
        amounts[key] = kept_block
    end
    return kept_block.total[(x % 16) * 16 + y % 16]
end

-- The share of pieces kept for an amount fallen (nil: not item spatter, e.g. blood: all of it).
-- (Also shown in the hover box.)
function share_for(amount)
    if not amount then return 1 end
    local share = math.max(LEAST_SHARE, math.min(1, amount / FULL_AMOUNT))
    return math.max(LEAST_SHARE, (share * 10 + 0.5) // 1 / 10)
end

-- Whether there's still time this frame to make a texture: BAKE_MS from the first one wanted.
local bake_started, bake_ms
local function time_to_bake()
    if not bake_started then
        bake_started, bake_ms = clock_ms(), work_time.take(BAKE_MS * allowance)
    end
    return clock_ms() - bake_started < bake_ms
end

-- A texture of these pixels, as a cache entry ({} if there were none to make one from).
local function new_entry(px)
    local handle = px and dfhack.textures.createTile(px, TILE, TILE)
    if not handle then return {} end
    local entry = {handle = handle, texpos = dfhack.textures.getTexposByHandle(handle)}
    made[entry.texpos] = true
    baked_count = baked_count + 1
    return entry
end

-- One number for a spatter texture, the share of its pieces kept and the pattern left out.
-- (A number, not a string put together for every tile every frame: with blossom down there are
-- several hundred spatter tiles in view.)
local SHARE_STEPS = 20   -- shares are LEAST_SHARE (a twentieth) or whole tenths
local function piece_key(spatter_texpos, share, variant)
    return (spatter_texpos * (SHARE_STEPS + 1) + math.floor(share * SHARE_STEPS + 0.5)) * VARIANTS + variant
end

-- The spatter texture thinned and shadowed: its entry, or nil if it's not made yet and there's
-- no time left this frame.
local function thinned_piece(spatter_texpos, share, variant, colour_copy)
    local key = piece_key(spatter_texpos, share, variant)
    local entry = baked_pieces[key]
    if entry == nil and time_to_bake() then
        local mask = mask_for(colour_copy[spatter_texpos] or spatter_texpos, share, variant)
        entry = new_entry(mask and bake_spatter(spatter_texpos, mask))
        baked_pieces[key] = entry
    end
    return entry
end

-- Notes the blades now showing for a grass original. The ones they replace are let go if they
-- were only being kept for this.
local function remember_blades(ground_original, entry)
    local previous = last_blades[ground_original]
    if previous == entry then return end
    if previous and previous.orphan then retire(previous) end
    last_blades[ground_original] = entry
end

-- The blades of the grass texture showing on a tile (the look's copy of ground_original, or one of
-- its leaning frames). Until that frame's blades are made, the ones last shown for the same grass
-- stand in: a frame or two of lean behind can't be seen, where no blades at all showed the fruit
-- lying on top of the grass each time the wind brought up a frame not yet seen (Poss).
local function blades_over(ground, ground_original, lean)
    local entry = baked_blades[ground]
    -- (the rustle's frames are freed when the wind changes strength, and the number may now be
    -- another grass's frame)
    if entry and entry.original ~= ground_original then
        if last_blades[entry.original] == entry then entry.orphan = true else retire(entry) end
        entry, baked_blades[ground] = nil, nil
    end
    if entry == nil and time_to_bake() then
        local mask = blade_mask(ground_original)
        entry = new_entry(mask and bake_blades(ground, mask))
        entry.original = ground_original
        entry.lean = lean and lean.original[ground] and lean or nil   -- the set a leaning frame is from
        baked_blades[ground] = entry
    end
    if entry and entry.texpos then
        remember_blades(ground_original, entry)
        return entry
    end
    return last_blades[ground_original]
end

local seen_generation   -- colour.copies_generation the bakes were made with

-- Every frame, after the colour's swaps: each piece of spatter on grass in view, in the grass.
function apply(viewport)
    if mode ~= 'on' then return end
    local started = clock_ms()
    bake_started = nil
    if seen_generation ~= colour.copies_generation then
        if seen_generation then clear_cache() end
        seen_generation = colour.copies_generation
    end
    -- (only for its size when textures are being deleted: grass.lua)
    if grass.delete_textures and baked_count >= BAKED_MOST then clear_cache() end
    -- (the leaning frames of a wind direction are kept by colour.lua once made, so the blades made
    -- from them hold too)
    local lean = colour.state and colour.state.lean or nil

    local port = df.global.gps.main_viewport
    local spatter, background, items = port.screentexpos_spatter, port.screentexpos_background, port.screentexpos_item
    local dim_y = port.dim_y
    local cols = math.min(viewport.x2 - viewport.x1 + 1, port.dim_x)
    local rows = math.min(viewport.y2 - viewport.y1 + 1, dim_y)
    -- Detailed Weather's own (snow, frost, ...) are left be; the colour's copies of the game's spatter
    -- (the fruit in the weather's colours) are what's put in the grass
    local ours = colour.state and colour.state.ours or {}
    local colour_copy = colour.state and colour.state.screen_original or {}
    local original_of, class_of = colour.original_of, colour.class_of
    for sx = 0, cols - 1 do
        local column = sx * dim_y
        for sy = 0, rows - 1 do
            local i = column + sy
            local t = spatter[i]
            if t > 0 and not made[t] and (not ours[t] or colour_copy[t]) then
                local ground = background[i]
                local ground_original = ground > 0 and original_of(ground)
                if ground_original and class_of(ground_original) == 'grass' then
                    local x, y = viewport.x1 + sx, viewport.y1 + sy
                    -- the spatter, thinned and shadowed
                    local share = share_for(fallen(x, y, viewport.z, started))
                    local variant = (x * 7 + y * 13) % VARIANTS
                    local piece = thinned_piece(t, share, variant, colour_copy)
                    if piece and piece.texpos then spatter[i] = piece.texpos end
                    -- the grass's blades over it, unless an item has the layer
                    if blades_mode ~= 'off' and items[i] == 0 then
                        local blades = blades_over(ground, ground_original, lean)
                        if blades then items[i] = blades.texpos end
                    end
                end
            end
        end
    end
    timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
end

function forget_world()
    baked_pieces, baked_blades, last_blades, baked_count, seen_generation = {}, {}, {}, 0, nil
    masks, blade_masks, pieces_of, amounts = {}, {}, {}, {}
end

function describe()
    return ('%s: %.2f ms a frame, %d pieces and blade layers made'):format(mode, timing.apply, baked_count)
end
