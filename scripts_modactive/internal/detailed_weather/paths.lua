-- Worn paths through grass, for Detailed Weather. Creatures walking (and grazing) wear the grass
-- down: the game keeps each tile's grass amount (0-100, lowered by each creature's GRASSTRAMPLE)
-- and turns grass worn right away into bare soil, but graphics mode draws a worn tile as lush as
-- an untouched one until then. This draws the wear in between, in two parts, both of the local
-- soil showing through the grass:
--
--   the wash   a broad, soft band of soil along the way the wear runs, see-through, more opaque
--              the more worn (from lightly grazed: WASH_BELOW), so light wear browns the grass
--              in the direction it's walked rather than as a patch
--   the track  over it, where the grass is properly worn (WORN_BELOW): bare soil, a thin line
--              widening as the grass goes, with a little flattened, paler grass beside it
--
-- Both run as a centre and arms towards each tile's LINKS most worn neighbours (worn grass, or
-- bare soil already), so worn tiles join up rather than making spots or a mesh: a link either
-- tile chooses is drawn by both, so nothing stops at a tile's edge, and an arm's width (track) or
-- opacity (wash) comes from the lighter wear of the two tiles it joins, the same on both sides of
-- the border. The tile's grass texture (already in the look's colours) is swapped for a copy with
-- these drawn in, made as needed and kept; the game draws grass edges over it as usual. The soil
-- is the commonest dirt texture on bare soil in view (the local soil), else the last one seen, else
-- the game's first dirt texture.
--
-- Paths are drawn on the level viewed and on the levels below it seen through open space (to
-- MOST_DEPTH). Grass amounts are read per map block and kept a few seconds, and what each block's
-- worn tiles show is worked out once and kept until its grass changes, so panning only works out
-- the blocks coming into view; planning stops at PLAN_MS a frame and carries on the next.
--@ module = true

local WORN_BELOW = 70          -- grass amount under which a tile shows a track
local WASH_BELOW = 95          -- and under which it shows the wash
local WASH_MOST = 0.75         -- the wash's opacity on grass worn right away
local WASH_HALF_WIDTH = 8      -- px: the wash's band, either side of its line
local WASH_SOFT = 5            -- px over which the band's edge fades
local WASH_LEVELS = 6          -- opacity steps
local LINKS = 2                -- each worn tile joins its most worn neighbours, this many
local SPREADING_BARE = 7       -- grass with this many of its 8 neighbours bare soil (a sprout, or
                               -- two side by side) is spreading onto bare ground (new grass starts
                               -- thin), not worn: not drawn. Path tiles beside bare ground have
                               -- about 3, 5 in the inside corner of an L of dirt.
local LEVELS = 4               -- track widths
local HALF_WIDTH = {1.5, 3, 5.5, 9}   -- px, per level: a trodden line to a wide bare track
local SOFT = 1.2               -- px over which the track's edge blends into the grass
local HALO = 3                 -- px of flattened grass beside the track
local HALO_LIFT = 0.10         -- how much paler (towards straw) the flattened grass is
local STRAW = {196, 182, 120}
local BLOCK_KEEP_MS = 4000
local REPLAN_MS = 2000
local PLAN_MS = 3              -- planning (reading blocks, working out new ones): at most this a frame
local MOST_DEPTH = 4           -- levels below seen through open space that get paths
local BAKE_MS = 2
local BAKED_MOST = 4000
local TILE = 32

mode = mode or 'on'
allowance = allowance or 1   -- the share of its usual time a frame (settings.lua: less at low)
blocks = blocks or {}          -- block key -> {amount = {[x * 16 + y] = n}, soil = {..= true}, at = ms}
masks = masks or {}            -- mask key -> per pixel 0..1 fields
baked = baked or {}            -- bake key -> texpos or false
baked_count = baked_count or 0
timing = timing or {plan = 0, apply = 0}

_G.detailed_weather_made = _G.detailed_weather_made or {}
local made = _G.detailed_weather_made
local grass = reqscript('internal/detailed_weather/grass')   -- texture pixels
local colour = reqscript('internal/detailed_weather/colour')   -- which textures are dirt
local frost = reqscript('internal/detailed_weather/frost')     -- the ground under its cracks

local GRASS_MATERIALS = {[df.tiletype_material.GRASS_LIGHT] = true, [df.tiletype_material.GRASS_DARK] = true,
                         [df.tiletype_material.GRASS_DRY] = true, [df.tiletype_material.GRASS_DEAD] = true}
local FLOOR = df.tiletype_shape.FLOOR
local tile_kind = {}   -- tiletype -> 'grass', 'soil' or false (df.tiletype.attrs is slow)
local function kind_of(tiletype)
    local k = tile_kind[tiletype]
    if k == nil then
        local attrs = df.tiletype.attrs[tiletype]
        k = attrs.shape == FLOOR and (GRASS_MATERIALS[attrs.material] and 'grass'
            or attrs.material == df.tiletype_material.SOIL and 'soil') or false
        tile_kind[tiletype] = k
    end
    return k
end

-- Whether the level below shows through a tile (open space, or the top of a ramp).
local see_through_of = {}
local function see_through(tiletype)
    local v = see_through_of[tiletype]
    if v == nil then
        local shape = df.tiletype.attrs[tiletype].shape
        v = shape == df.tiletype_shape.EMPTY or shape == df.tiletype_shape.RAMP_TOP
        see_through_of[tiletype] = v
    end
    return v
end

local function read_block(block, now)
    local amount, soil, open = {}, {}, {}
    local open_any = false
    local grass_events = {}
    for _, ev in ipairs(block.block_events) do
        if ev:getType() == df.block_square_event_type.grass then grass_events[#grass_events + 1] = ev end
    end
    for bx = 0, 15 do
        for by = 0, 15 do
            local tiletype = block.tiletype[bx][by]
            if see_through(tiletype) then open[bx * 16 + by] = true open_any = true end
            local k = kind_of(tiletype)
            if k and block.designation[bx][by].outside then
                if k == 'grass' then
                    local most = 0
                    for _, ev in ipairs(grass_events) do
                        local a = ev.amount[bx][by]
                        if a > most then most = a end
                    end
                    amount[bx * 16 + by] = most
                else
                    soil[bx * 16 + by] = true
                end
            end
        end
    end
    local sum = 0
    for i = 0, 255 do sum = (sum * 7 + (amount[i] or (soil[i] and 101) or 102)) % 4294967296 end
    return {amount = amount, soil = soil, open = open, open_any = open_any, at = now, sum = sum}
end

----------------------------------------------------------------------------------------------
-- Masks
----------------------------------------------------------------------------------------------

-- Arms run from the tile's middle to each side's middle (N, E, S, W) or each corner (NE, SE, SW, NW).
local ARMS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {1, 1}, {-1, 1}, {-1, -1}}
local MIDDLE = (TILE - 1) / 2

-- How far pixel (x, y) is from arm a's line (px).
local function from_arm(a, x, y)
    local dx, dy = ARMS[a][1] * (MIDDLE + 0.5), ARMS[a][2] * (MIDDLE + 0.5)
    local t = ((x - MIDDLE) * dx + (y - MIDDLE) * dy) / (dx * dx + dy * dy)
    t = t < 0 and 0 or t > 1 and 1 or t
    return math.sqrt((x - MIDDLE - t * dx) ^ 2 + (y - MIDDLE - t * dy) ^ 2)
end

local function clamp01(v) return v < 0 and 0 or v > 1 and 1 or v end

-- The track for a centre width and eight arm widths (levels, 0 = none): soil cover and halo.
local function track_mask(centre, arms)
    local key = 't' .. centre .. ':' .. table.concat(arms, '')
    local m = masks[key]
    if m then return m end
    local cover, halo = {}, {}
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            -- how far inside the track this pixel is (px; negative outside)
            local inside = HALF_WIDTH[centre] - math.sqrt((x - MIDDLE) ^ 2 + (y - MIDDLE) ^ 2)
            for a, level in ipairs(arms) do
                if level > 0 then
                    local v = HALF_WIDTH[level] - from_arm(a, x, y)
                    if v > inside then inside = v end
                end
            end
            local n = y * TILE + x + 1
            cover[n] = clamp01(inside / SOFT + 0.5)
            halo[n] = clamp01((inside + HALO) / HALO)
        end
    end
    m = {cover = cover, halo = halo}
    masks[key] = m
    return m
end

-- The wash for a centre opacity and eight arm opacities (levels, 0 = none): soil opacity per pixel.
local function wash_mask(centre, arms)
    local key = 'w' .. centre .. ':' .. table.concat(arms, '')
    local m = masks[key]
    if m then return m end
    local opacity = {}
    local k = WASH_MOST / WASH_LEVELS
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local band = function(d) return clamp01((WASH_HALF_WIDTH - d) / WASH_SOFT + 0.5) end
            local o = centre * band(math.sqrt((x - MIDDLE) ^ 2 + (y - MIDDLE) ^ 2))
            for a, level in ipairs(arms) do
                if level > 0 then
                    local v = level * band(from_arm(a, x, y))
                    if v > o then o = v end
                end
            end
            opacity[y * TILE + x + 1] = o * k
        end
    end
    masks[key] = opacity
    return opacity
end

----------------------------------------------------------------------------------------------
-- Baking
----------------------------------------------------------------------------------------------

local function pack(r, g, b, a)
    r = r < 0 and 0 or r > 255 and 255 or math.floor(r + 0.5)
    g = g < 0 and 0 or g > 255 and 255 or math.floor(g + 0.5)
    b = b < 0 and 0 or b > 255 and 255 or math.floor(b + 0.5)
    return (a << 24) | (b << 16) | (g << 8) | r
end

-- The grass with the wash, then the track's halo and soil, drawn in.
local function bake(base, soil, track, wash)
    local gp, sp = grass.pixels_of(base), grass.pixels_of(soil)
    if not gp or not sp then return nil end
    local out = {}
    local cover, halo = track and track.cover, track and track.halo
    for n = 1, TILE * TILE do
        local g, s = gp[n], sp[n]
        local r, gr, b = g[1], g[2], g[3]
        local w = wash and wash[n] or 0
        if w > 0 then r, gr, b = r + (s[1] - r) * w, gr + (s[2] - gr) * w, b + (s[3] - b) * w end
        if track then
            local h = halo[n] * HALO_LIFT
            r, gr, b = r + (STRAW[1] - r) * h, gr + (STRAW[2] - gr) * h, b + (STRAW[3] - b) * h
            local k = cover[n]
            r, gr, b = r + (s[1] - r) * k, gr + (s[2] - gr) * k, b + (s[3] - b) * k
        end
        out[n] = pack(r, gr, b, g[4])
    end
    return out
end

----------------------------------------------------------------------------------------------
-- Planning and drawing
----------------------------------------------------------------------------------------------

local function level_in(wear, levels)
    return math.max(1, math.min(levels, math.ceil(wear * levels)))
end

-- The opposite arm: N<->S, E<->W, NE<->SW, SE<->NW.
local function opposite(k) return k <= 4 and (k + 1) % 4 + 1 or (k - 5 + 2) % 4 + 5 end
-- For a side arm (N, E, S, W) onto bare soil: the soil tile's floor_flag byte (S, W, E, N: the
-- edge each neighbour drops on it) that holds this grass tile's edge
local EDGE_BYTE_FOR_ARM = {1, 2, 4, 3}

-- What's drawn on each worn grass tile of a map block: {x, y, track, wash, key}, worked out from
-- the grass round it (two tiles out: a tile's arms depend on the links its neighbours choose) and
-- kept until any of the nine blocks it reads changes, so panning only works out new blocks.
-- `block_at(bx, by)` gives a block's grass (false: no block), or nil if it isn't read yet, and
-- then this returns nil.
entries_cache = entries_cache or {}
local function block_entries(bx, by, z, block_at)
    local sum = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local b = block_at(bx + dx, by + dy)
            if b == nil then return nil end
            sum = (sum * 31 + (b and b.sum or 7)) % 4294967296
        end
    end
    local cache_key = (z * 1024 + bx) * 1024 + by
    local cached = entries_cache[cache_key]
    if cached and cached.sum == sum then return cached.entries end

    -- the region as a flat grid (column by column): the grass amount, -1 for bare soil, else nil
    local x1, y1 = bx * 16 - 2, by * 16 - 2
    local w, h = 20, 20
    local amount = {}
    for i = 0, w - 1 do
        local x = x1 + i
        for j = 0, h - 1 do
            local y = y1 + j
            local b = block_at(x // 16, y // 16)
            if b then
                local t = (x % 16) * 16 + y % 16
                amount[i * h + j] = b.amount[t] or (b.soil[t] and -1) or nil
            end
        end
    end
    local function wear(n, threshold)   -- 0..1 on grass worn below the threshold, 1 on bare soil, nil
        local a = amount[n]
        if not a then return nil end
        if a < 0 then return 1 end
        return a < threshold and (threshold - a) / threshold or nil
    end
    local step = {}   -- each arm's step in the grid
    for k, d in ipairs(ARMS) do step[k] = d[1] * h + d[2] end

    -- the links each worn grass tile chooses: its LINKS most worn neighbours, sides before corners
    -- on a tie, a corner only where the two sides beside it aren't both worn; drawn from both sides
    local function links_for(threshold)
        local links = {}
        for i = 1, w - 2 do
            for j = 1, h - 2 do
                local n = i * h + j
                local a = amount[n]
                if a and a >= 0 and a < threshold then
                    local best, best_w, second, second_w = nil, -1, nil, -1
                    for k = 1, 8 do
                        local nw = wear(n + step[k], threshold)
                        if nw and k > 4 then
                            local d = ARMS[k]
                            if wear(n + d[1] * h, threshold) and wear(n + d[2], threshold) then nw = nil
                            else nw = nw - 0.01 end
                        end
                        if nw then
                            if nw > best_w then best, best_w, second, second_w = k, nw, best, best_w
                            elseif nw > second_w then second, second_w = k, nw end
                        end
                    end
                    for _, k in ipairs({best, LINKS > 1 and second or nil}) do
                        links[n * 8 + k] = true
                        links[(n + step[k]) * 8 + opposite(k)] = true
                    end
                end
            end
        end
        return links
    end
    local track_links, wash_links = links_for(WORN_BELOW), links_for(WASH_BELOW)

    -- grass mostly ringed by bare soil is new grass spreading onto bare ground (it starts thin),
    -- not a path worn through grass: left as the game draws it
    local function spreading(n)
        local bare = 0
        for k = 1, 8 do if amount[n + step[k]] == -1 then bare = bare + 1 end end
        return bare >= SPREADING_BARE
    end
    local entries = {}
    for i = 2, 17 do
        for j = 2, 17 do
            local n = i * h + j
            local a = amount[n]
            if a and a >= 0 and a < WASH_BELOW and not spreading(n) then
                local ww = (WASH_BELOW - a) / WASH_BELOW
                local arms = {}
                for k = 1, 8 do
                    local nw = wash_links[n * 8 + k] and wear(n + step[k], WASH_BELOW)
                    arms[k] = nw and level_in(math.min(ww, nw), WASH_LEVELS) or 0
                end
                local centre = level_in(ww, WASH_LEVELS)
                local key = centre .. ':' .. table.concat(arms, '')
                local track   -- {centre, arms}, or nil
                if a < WORN_BELOW then
                    local tw = (WORN_BELOW - a) / WORN_BELOW
                    local t_arms = {}
                    for k = 1, 8 do
                        local nw = track_links[n * 8 + k] and wear(n + step[k], WORN_BELOW)
                        t_arms[k] = nw and level_in(math.min(tw, nw), LEVELS) or 0
                    end
                    local t_centre = level_in(tw, LEVELS)
                    track = {t_centre, t_arms}
                    key = key .. '/' .. t_centre .. ':' .. table.concat(t_arms, '')
                end
                -- where the track runs straight onto bare soil, the grass edge the game drops on
                -- that soil from this tile is worn away too: {x, y, byte} for each
                local worn_edges
                for k = 1, 4 do
                    if track and track[2][k] > 0 and amount[n + step[k]] == -1 then
                        worn_edges = worn_edges or {}
                        worn_edges[#worn_edges + 1] = {x1 + i + ARMS[k][1], y1 + j + ARMS[k][2], EDGE_BYTE_FOR_ARM[k]}
                    end
                end
                -- the masks are made when baking, within its time budget
                entries[#entries + 1] = {x1 + i, y1 + j, track, {centre, arms}, key, worn_edges}
            end
        end
    end
    entries_cache[cache_key] = {sum = sum, entries = entries}
    return entries
end

-- A plan for one level of the view (depth 0 the level viewed, 1 the one below seen through open
-- space, ...): each worn grass tile showing there, by its index in that level's screen buffers.
-- It's built a block at a time, as long as the frame's planning time lasts, and carries on where
-- it left off the next frame (done: the blocks it has), so a pan fills in over a few frames
-- rather than in one slow one, and nothing it has already drawn drops out meanwhile.
local function new_plan(viewport, port)
    return {x1 = viewport.x1, y1 = viewport.y1, z = viewport.z, dim_x = port.dim_x, dim_y = port.dim_y,
            cells = {}, worn_edges = {}, done = {}, complete = false}
end

-- Works on plan q for at most budget_ms; marks it complete once every block in view is in it.
local function continue_plan(q, viewport, port, depth, now, budget_ms)
    local started = dfhack.getTickCount()
    local top = viewport.z
    local z = top - depth
    local function out_of_time() return dfhack.getTickCount() - started >= budget_ms end
    -- a block's grass at level zz (default this plan's): nil if not read and no time to, false if
    -- there's no block there; a stale one is read again when there's time, else used as it is
    local function block_at(bx, by, zz)
        zz = zz or z
        local key = (zz * 1024 + bx) * 1024 + by
        local b = blocks[key]
        if b == false or (b and now - b.at <= BLOCK_KEEP_MS) then return b end
        if out_of_time() then return b end
        local block = dfhack.maps.getTileBlock(bx * 16, by * 16, zz)
        b = block and read_block(block, now) or false
        blocks[key] = b
        return b
    end
    local dim_y = port.dim_y
    local x2, y2 = math.min(viewport.x2, viewport.x1 + port.dim_x - 1), math.min(viewport.y2, viewport.y1 + dim_y - 1)
    -- a lower level only shows where every level above it is open there
    local function shows(x, y)
        for zz = top, z + 1, -1 do
            local b = block_at(x // 16, y // 16, zz)
            if not (b and b.open[(x % 16) * 16 + y % 16]) then return false end
        end
        return true
    end
    if depth > 0 and not q.open_checked then
        -- nothing open on the level above: nothing of this one shows
        local any = false
        for bx = viewport.x1 // 16, x2 // 16 do
            for by = viewport.y1 // 16, y2 // 16 do
                local b = block_at(bx, by, z + 1)
                if b == nil then return end   -- not read yet: next frame
                if b and b.open_any then any = true end
            end
        end
        q.open_checked = true
        if not any then
            q.complete, q.due = true, now + REPLAN_MS
            return
        end
    end
    local cells, done = q.cells, q.done
    for bx = viewport.x1 // 16, x2 // 16 do
        for by = viewport.y1 // 16, y2 // 16 do
            local block_key = bx * 1024 + by
            if not done[block_key] then
                if out_of_time() then return end
                local entries = block_entries(bx, by, z, block_at)
                if not entries then return end   -- blocks left to read: next frame
                for _, e in ipairs(entries) do
                    local x, y = e[1], e[2]
                    if x >= viewport.x1 and x <= x2 and y >= viewport.y1 and y <= y2 and (depth == 0 or shows(x, y)) then
                        cells[#cells + 1] = {(x - viewport.x1) * dim_y + (y - viewport.y1), e[3], e[4], e[5]}
                    end
                    for _, edge in ipairs(e[6] or {}) do
                        local ex, ey = edge[1], edge[2]
                        if ex >= viewport.x1 and ex <= x2 and ey >= viewport.y1 and ey <= y2 and (depth == 0 or shows(ex, ey)) then
                            local i = (ex - viewport.x1) * dim_y + (ey - viewport.y1)
                            q.worn_edges[i] = (q.worn_edges[i] or 0) | (0xff << (8 * (edge[3] - 1)))
                        end
                    end
                end
                done[block_key] = true
            end
        end
    end
    q.complete = true
    q.due = now + REPLAN_MS
end

-- The soil to draw: the most common dirt texture on the bare outdoor soil tiles on screen (as the
-- looks class it: the game counts sand floors as soil too). Kept once found.
-- One of the game's dirt textures (the first in its tables), or nil before they're read.
local function any_dirt()
    local first
    for texpos, class in pairs(colour.state and colour.state.class_of or {}) do
        if class == 'dirt' and (not first or texpos < first) then first = texpos end
    end
    return first
end

local function find_soil(port, viewport)   -- (the look's copy of it)
    local background = port.screentexpos_background
    local dim_x, dim_y = port.dim_x, port.dim_y
    local count, best, best_count = {}, nil, 0
    for x = viewport.x1, viewport.x2 do
        for y = viewport.y1, viewport.y2 do
            local b = blocks[(viewport.z * 1024 + x // 16) * 1024 + y // 16]
            local sx, sy = x - viewport.x1, y - viewport.y1
            if b and b.soil[(x % 16) * 16 + y % 16] and sx < dim_x and sy < dim_y then
                -- (dry dirt shows frost.lua's cracked copy: the ground it was made from)
                local texpos = frost.uncracked(background[sx * dim_y + sy])
                if texpos > 0 and not made[texpos] and colour.class_of(colour.original_of(texpos)) == 'dirt' then
                    local c = (count[texpos] or 0) + 1
                    count[texpos] = c
                    if c > best_count then best, best_count = texpos, c end
                end
            end
        end
    end
    -- with no bare dirt in view, the dirt last seen, or else any of the game's dirt
    if best then soil_original = colour.original_of(best) end
    local original = soil_original or any_dirt()
    if not original then return nil end
    -- in the look's colours, as the grass it's drawn into is (the dirt on screen may be the
    -- game's own where nothing has swapped it yet); nil until the look's copy is made
    local copy = colour.copy_of(original)
    if copy == original and colour.shown_look() then return nil end
    return copy
end

-- Draws one level's plan into its background buffer (looked up afresh: the game swaps each
-- buffer with its twin every frame), baking new textures while the frame's baking time lasts.
local function draw(p, port, soil_texpos, state)
    local background = port.screentexpos_background
    -- grass edges worn off where a track runs onto bare soil
    if next(p.worn_edges or {}) then
        local floor_flag = port.screentexpos_floor_flag
        for i, mask in pairs(p.worn_edges) do
            local flag = floor_flag[i]
            if flag & mask ~= 0 then floor_flag[i] = flag & ~mask end
        end
    end
    for _, cell in ipairs(p.cells) do
        local i = cell[1]
        -- worn grass is flattened: it doesn't lean in the wind (colour.lua), so it's baked upright
        local base = colour.steady_of(background[i])
        if base > 0 and not made[base] then
            local key = base .. ':' .. soil_texpos .. ':' .. cell[4]
            local texpos = baked[key]
            if texpos == nil then
                state.baking_from = state.baking_from or dfhack.getTickCount()
                if dfhack.getTickCount() - state.baking_from < BAKE_MS * allowance then
                    if grass.delete_textures and baked_count >= BAKED_MOST then clear_cache() end
                    local track = cell[2] and track_mask(cell[2][1], cell[2][2])
                    local px = bake(base, soil_texpos, track, wash_mask(cell[3][1], cell[3][2]))
                    local handle = px and dfhack.textures.createTile(px, TILE, TILE)
                    texpos = handle and dfhack.textures.getTexposByHandle(handle) or false
                    baked[key] = texpos
                    baked_count = baked_count + 1
                    if texpos then made[texpos] = true end
                end
            end
            if texpos then background[i] = texpos end
        end
    end
end

local function port_at(depth)
    return depth == 0 and df.global.gps.main_viewport or df.global.gps.lower_viewport[depth - 1]
end

plans = plans or {}   -- per depth
soil, soil_look = soil or nil, soil_look or nil   -- the soil texture, found again when the look changes
soil_original = soil_original or nil   -- the game's dirt texture last found on screen
seen_generation = seen_generation or nil   -- colour.copies_generation when the bakes were made
function apply(viewport)
    if mode ~= 'on' then return end
    local now = dfhack.getTickCount()
    local planning_left = PLAN_MS * allowance
    local _, look_key = colour.shown_look()
    if soil_look ~= look_key then soil, soil_look = nil, look_key end
    -- the colour's copies let go: the grass and soil textures baked from may now be other pictures
    if seen_generation ~= colour.copies_generation then
        seen_generation, soil = colour.copies_generation, nil
        clear_cache()
    end
    local state = {}
    for depth = 0, MOST_DEPTH do
        local port = port_at(depth)
        local p = plans[depth]
        if not p or p.x1 ~= viewport.x1 or p.y1 ~= viewport.y1 or p.z ~= viewport.z
                or p.dim_x ~= port.dim_x or p.dim_y ~= port.dim_y then
            -- another view: start afresh (the old plan's indexes are wrong here)
            p = new_plan(viewport, port)
            plans[depth] = p
        end
        -- the plan still being built, or (once it's due) its replacement, built alongside while
        -- the current one stays drawn
        local building = not p.complete and p or nil
        if p.complete and now >= (p.due or 0) then
            p.next = p.next or new_plan(viewport, port)
            building = p.next
        end
        if building and planning_left > 0 then
            local started = dfhack.getTickCount()
            continue_plan(building, viewport, port, depth, now, planning_left)
            local took = dfhack.getTickCount() - started
            planning_left = planning_left - took
            timing.plan = timing.plan + (took - timing.plan) * 0.2
            if building == p.next and building.complete then
                p.cells, p.due, p.next = building.cells, building.due, nil
            end
        end
        if #p.cells > 0 then
            if not soil and depth == 0 then soil = find_soil(port, viewport) end
            local started = dfhack.getTickCount()
            if soil then draw(p, port, soil, state) end
            timing.apply = timing.apply + (dfhack.getTickCount() - started - timing.apply) * 0.05
        end
    end
end

function clear_cache()
    for _, texpos in pairs(baked) do if texpos then made[texpos] = nil end end
    baked, baked_count, plans = {}, 0, {}
end

function forget_world()
    blocks, plans, entries_cache, soil, soil_original = {}, {}, {}, nil, nil
    clear_cache()
end

function describe()
    local shown = 0
    for _, p in pairs(plans) do shown = shown + #p.cells end
    return ('%s: planning %.1f ms (new blocks as the view moves, changed grass), drawing %.2f ms a frame, %d worn tiles showing, %d textures made'):format(
        mode, timing.plan, timing.apply, shown, baked_count)
end
