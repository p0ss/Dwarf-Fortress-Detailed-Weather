-- Shade, for Detailed Weather: the ground above it under a roof or a tree's branches drawn darker,
-- as in the shade. The game marks those tiles (above ground but not outside) yet graphics mode
-- draws them as bright as open ground. Underground is left alone: everything there is equally
-- dark, so a shade only muddied it (tried, 2026-11-09).
--
-- The shade is a see-through dark tile in the designation layer (the dig and chop marks), which
-- draws over everything on the map, so the things in the shade are shaded too; it's left out
-- wherever the game has a designation mark of its own to show. Covered tiles are fully shaded,
-- with a soft edge a tile wide: each screen tile's shade runs smoothly between the darkness at its
-- four corners (the mean of the four tiles meeting there), so it fades from the middle of the last
-- covered tile to the middle of the open one beside it. Those shade tiles are made as needed and kept.
--
-- Which tiles are covered is read per map block, a few blocks a frame (READ_MS), and kept a while
-- (cover only changes as trees grow and roofs are built). Only tiles near cover get a shade tile,
-- so a view with none costs next to nothing.
--@ module = true

local STRENGTH = 0.30          -- how much darker the shade is (the shade's opacity): a little lighter
                               -- than a ramp's shadowed side (0.6-0.67 of the flat ground), so a roofed
                               -- building isn't too dark inside
local SHADE = {2, 2, 6}        -- its colour: all but black (a bluer shade greyed the greens and browns)
local SPREAD = 1               -- blocks read this far round the view, for the edges just outside it
local LEVELS = 8               -- darkness steps at the corners
local BLOCK_KEEP_MS = 30000    -- how long a block's cover is kept
local READ_MS = 1.5            -- reading blocks: at most this long a frame (the rest wait a frame)
local REPLAN_MS = 5000
local TILE = 32

mode = mode or 'on'
textures = textures or {}       -- corner key -> texpos (or false)
blocks = blocks or {}           -- block key -> {covered = {[x * 16 + y] = true}, any = bool, at = ms}
plan = plan or nil
timing = timing or {plan = 0, apply = 0}

-- every texture Detailed Weather makes, shared, so the colour swap leaves them be
_G.detailed_weather_made = _G.detailed_weather_made or {}
local made = _G.detailed_weather_made

-- The shade tile for four corner darknesses (0..LEVELS each: top left, top right, bottom left,
-- bottom right), blended across the tile.
local function shade_texpos(tl, tr, bl, br)
    local key = ((tl * 16 + tr) * 16 + bl) * 16 + br
    local texpos = textures[key]
    if texpos ~= nil then return texpos or nil end
    local px = {}
    local most = STRENGTH * 255 / LEVELS
    local colour = (SHADE[3] << 16) | (SHADE[2] << 8) | SHADE[1]
    for y = 0, TILE - 1 do
        local v = (y + 0.5) / TILE
        local left, right = tl + (bl - tl) * v, tr + (br - tr) * v
        for x = 0, TILE - 1 do
            local u = (x + 0.5) / TILE
            local alpha = math.floor((left + (right - left) * u) * most + 0.5)
            px[y * TILE + x + 1] = (alpha << 24) | colour
        end
    end
    local handle = dfhack.textures.createTile(px, TILE, TILE)
    texpos = handle and dfhack.textures.getTexposByHandle(handle) or false
    textures[key] = texpos
    if texpos then made[texpos] = true end
    return texpos or nil
end

-- A block's covered tiles (above ground, not outside), and its tiles with water or magma on them,
-- read now.
local function read_block(block, now)
    local covered, liquid, any = {}, {}, false
    local designation = block.designation
    for bx = 0, 15 do
        local column = designation[bx]
        for by = 0, 15 do
            local flags = column[by]
            if not flags.outside and not flags.subterranean then
                covered[bx * 16 + by] = true
                any = true
            end
            if flags.flow_size > 0 then liquid[bx * 16 + by] = true end
        end
    end
    return {covered = covered, liquid = liquid, any = any, at = now}
end

-- The shade for the view: a flat list of buffer index, texpos, and whether every block in view
-- was read (if not, it's planned again next frame).
local function make_plan(viewport, port, now)
    local started = now
    local z = viewport.z
    local x1, y1, x2, y2 = viewport.x1 - SPREAD - 1, viewport.y1 - SPREAD - 1, viewport.x2 + SPREAD + 1, viewport.y2 + SPREAD + 1
    -- the blocks round the view: read the missing or stale ones while there's time
    local complete, any = true, false
    local in_view = {}
    for bx = x1 // 16, x2 // 16 do
        for by = y1 // 16, y2 // 16 do
            local key = (z * 1024 + bx) * 1024 + by
            local b = blocks[key]
            if not b or now - b.at > BLOCK_KEEP_MS then
                -- a stale block is used as it was until there's time to read it again
                if dfhack.getTickCount() - started < READ_MS then
                    local block = dfhack.maps.getTileBlock(bx * 16, by * 16, z)
                    if block then b = read_block(block, now) blocks[key] = b end
                else
                    complete = false
                end
            end
            if b then
                in_view[bx * 1024 + by] = b
                any = any or b.any
            end
        end
    end
    local cells = {}
    local p = {cells = cells, x1 = viewport.x1, y1 = viewport.y1, z = z, dim_x = port.dim_x, dim_y = port.dim_y,
               due = complete and now + REPLAN_MS or now}
    if not any then return p end

    local function covered(x, y)
        local b = in_view[(x // 16) * 1024 + y // 16]
        return b and b.covered[(x % 16) * 16 + y % 16] or false
    end
    -- the game draws the designation layer oddly over liquid (the shade showed as dark blots that
    -- flickered with the water), so water and magma go unshaded
    local function liquid(x, y)
        local b = in_view[(x // 16) * 1024 + y // 16]
        return b and b.liquid and b.liquid[(x % 16) * 16 + y % 16] or false
    end
    -- each covered tile fully dark; the edge's softness is the corners' blending
    local dark = {}
    local function at(x, y) return dark[(x - x1) * 4096 + (y - y1)] or 0 end
    local covered_tiles = {}
    for x = x1, x2 do
        for y = y1, y2 do
            if covered(x, y) then covered_tiles[#covered_tiles + 1] = x * 4096 + y end
        end
    end
    for _, xy in ipairs(covered_tiles) do
        dark[(xy // 4096 - x1) * 4096 + (xy % 4096 - y1)] = 1
    end
    -- the screen tiles touching a covered tile, each with its four corners' darkness
    local dim_x, dim_y = port.dim_x, port.dim_y
    local done = {}
    local function corner(x, y)   -- the corner at the top left of map tile (x, y)
        local sum = at(x - 1, y - 1) + at(x, y - 1) + at(x - 1, y) + at(x, y)
        return math.floor(sum / 4 * LEVELS + 0.5)
    end
    for _, xy in ipairs(covered_tiles) do
        local cx, cy = xy // 4096, xy % 4096
        for x = cx - 1, cx + 1 do
            for y = cy - 1, cy + 1 do
                local sx, sy = x - viewport.x1, y - viewport.y1
                if sx >= 0 and sy >= 0 and sx < dim_x and sy < dim_y and x <= viewport.x2 and y <= viewport.y2 then
                    local i = sx * dim_y + sy
                    if not done[i] and not liquid(x, y) then
                        done[i] = true
                        local tl, tr, bl, br = corner(x, y), corner(x + 1, y), corner(x, y + 1), corner(x + 1, y + 1)
                        if tl + tr + bl + br > 0 then
                            local texpos = shade_texpos(tl, tr, bl, br)
                            if texpos then
                                cells[#cells + 1] = i
                                cells[#cells + 1] = texpos
                            end
                        end
                    end
                end
            end
        end
    end
    return p
end

-- Draws the shade into this frame's designation buffer (looked up each frame: the game swaps it
-- with its twin every frame), planning again when the view has moved or the plan is due.
function apply(viewport)
    if mode ~= 'on' then return end
    local port = df.global.gps.main_viewport
    local now = dfhack.getTickCount()
    local p = plan
    if not p or now >= p.due or p.x1 ~= viewport.x1 or p.y1 ~= viewport.y1 or p.z ~= viewport.z
            or p.dim_x ~= port.dim_x or p.dim_y ~= port.dim_y then
        p = make_plan(viewport, port, now)
        plan = p
        timing.plan = timing.plan + (dfhack.getTickCount() - now - timing.plan) * 0.2
    end
    local started = dfhack.getTickCount()
    local cells = p.cells
    if #cells > 0 then
        local buffer = port.screentexpos_designation
        for k = 1, #cells, 2 do
            local i = cells[k]
            if buffer[i] == 0 then buffer[i] = cells[k + 1] end
        end
    end
    timing.apply = timing.apply + (dfhack.getTickCount() - started - timing.apply) * 0.05
end

-- Another world: what's kept by position belongs to the old map, and the shade tiles' texture
-- numbers name other pictures once the next world's graphics are loaded (they showed as
-- workshop parts), so they're made again.
function forget_world()
    textures, blocks, plan = {}, {}, nil
end

function clear_cache()
    for _, texpos in pairs(textures) do if texpos then made[texpos] = nil end end
    textures, blocks, plan = {}, {}, nil
end

function describe()
    return ('%s: planning %.1f ms (when the view moves, else every 5 s), drawing %.2f ms a frame, %d shade tiles on screen'):format(
        mode, timing.plan, timing.apply, plan and #plan.cells // 2 or 0)
end
