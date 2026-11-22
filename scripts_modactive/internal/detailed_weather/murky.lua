-- Murky water, for Detailed Weather: the game marks still water that's gone bad as stagnant (its
-- murky pools; dwarves drink it unhappily), but graphics mode draws it as clear as a brook. This
-- tints it a pond's green.
--
-- Where: water tiles with the designation's water_stagnant flag, at the view's level and up to
-- MOST_DEPTH levels below where every level between is open. The game
-- draws water from its liquid flags rather than a texture, so it can't be recoloured; the tint
-- (art/murky.png, made by tools/weather/make_murky_sheet.py: a see-through patch CELLS x CELLS
-- tiles big, repeated across the map) goes over it in the spatter layer, which draws over the
-- water and under items and creatures. Water deep enough to stagnate carries no spatter of its own;
-- a tile whose spatter layer is already used (mud, blood) is left be.
--
-- Which tiles are stagnant water is worked out a block (16 x 16 tiles) at a time, within PLAN_MS a
-- frame, and kept for REMEMBER_MS: water stagnates, drains and fills slowly.
--@ module = true

local TILE = 32
local CELLS = 4
local PLAN_MS = 1
local REMEMBER_MS = 4000
local MOST_DEPTH = 3           -- levels below the view, seen through open space, that get it

mode = mode or 'on'
layer_name = layer_name or 'background_two'
lower_layer_name = lower_layer_name or 'item'
-- block key -> {checked = tick count, tiles = {local index (x % 16 * 16 + y % 16)...}}
blocks = blocks or {}
timing = timing or {apply = 0}
drawn = drawn or {}   -- tiles drawn last frame, per depth below the view
local textures   -- texpos of each cell, cell = (y % CELLS) * CELLS + (x % CELLS) + 1

local function load_textures(path)
    local handles = dfhack.textures.loadTileset(path, TILE, TILE, true)
    local out = {}
    for i, handle in ipairs(handles) do out[i] = dfhack.textures.getTexposByHandle(handle) end
    return out
end

local function block_key(bx, by, z) return (z * 1024 + bx) * 1024 + by end

local see_through_of = {}   -- by tiletype: df.tiletype.attrs costs ~40 us a lookup
local function see_through(tiletype)
    local open = see_through_of[tiletype]
    if open == nil then
        local shape = df.tiletype.attrs[tiletype].shape
        open = shape == df.tiletype_shape.EMPTY or shape == df.tiletype_shape.RAMP_TOP
        see_through_of[tiletype] = open
    end
    return open
end

-- What's needed of a block: its stagnant water tiles (local indexes, x % 16 * 16 + y % 16), and
-- which tiles are open (lower levels show through them).
local function read_block(block, now)
    local tiles, open = {}, {}
    local designation, tiletype = block.designation, block.tiletype
    for lx = 0, 15 do
        local column = designation[lx]
        for ly = 0, 15 do
            local flags = column[ly]
            if flags.water_stagnant and flags.flow_size > 0 and not flags.liquid_type and not flags.hidden then
                tiles[#tiles + 1] = lx * 16 + ly
            end
            if see_through(tiletype[lx][ly]) then open[lx * 16 + ly] = true end
        end
    end
    return {checked = now, tiles = tiles, open = open}
end

local function port_at(depth)
    return depth == 0 and df.global.gps.main_viewport or df.global.gps.lower_viewport[depth - 1]
end

-- Every frame: the tint over the stagnant water in view (art_path: the art's file name -> its path), at the view's level and the levels below
-- seen through open space (a pond is mostly looked down on from the ground beside it).
function apply(viewport, art_path)
    if mode ~= 'on' then return end
    local started = dfhack.getTickCount()
    if not textures then textures = load_textures(art_path('murky.png')) end
    local budget_ends = started + PLAN_MS
    -- a block's record, read again when it's old if there's time; nil if not read yet
    local function known(bx, by, z)
        local key = block_key(bx, by, z)
        local b = blocks[key]
        if (not b or started - b.checked > REMEMBER_MS) and dfhack.getTickCount() < budget_ends then
            local block = dfhack.maps.getTileBlock(bx * 16, by * 16, z)
            b = block and read_block(block, started) or {checked = started, tiles = {}, open = {}}
            blocks[key] = b
        end
        return b
    end
    local x1, y1, z = viewport.x1, viewport.y1, viewport.z
    drawn = {}
    for depth = 0, MOST_DEPTH do
        drawn[depth] = 0
        local port = port_at(depth)
        if not port then break end
        local layer, dim_y = port['screentexpos_' .. (depth == 0 and layer_name or lower_layer_name)], port.dim_y
        -- raw memory: never past the buffer's end (just after a zoom the viewport can be larger)
        local x2, y2 = math.min(viewport.x2, x1 + port.dim_x - 1), math.min(viewport.y2, y1 + dim_y - 1)
        for bx = x1 // 16, x2 // 16 do
            for by = y1 // 16, y2 // 16 do
                local b = known(bx, by, z - depth)
                if b and #b.tiles > 0 then
                    -- the levels above, which it must show through
                    local above = {}
                    for d = 0, depth - 1 do above[#above + 1] = known(bx, by, z - d) or false end
                    for _, index in ipairs(b.tiles) do
                        local x, y = bx * 16 + index // 16, by * 16 + index % 16
                        if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
                            local shows = true
                            for _, a in ipairs(above) do
                                if not (a and a.open[index]) then shows = false break end
                            end
                            local i = (x - x1) * dim_y + (y - y1)
                            if shows and layer[i] == 0 then
                                layer[i] = textures[(y % CELLS) * CELLS + (x % CELLS) + 1]
                                drawn[depth] = drawn[depth] + 1
                            end
                        end
                    end
                end
            end
        end
    end
    timing.apply = timing.apply + (dfhack.getTickCount() - started - timing.apply) * 0.05
end

-- The art loaded again next frame (after `detailed_weather reload`).
function clear_cache() textures = nil end

function forget_world()
    blocks = {}
end

function describe()
    local count = 0
    for _, known in pairs(blocks) do count = count + #known.tiles end
    local shown = {}
    for depth = 0, MOST_DEPTH do shown[#shown + 1] = drawn[depth] or 0 end
    return ('%s: %.2f ms a frame, %d stagnant tiles known, %s drawn by level down'):format(
        mode, timing.apply, count, table.concat(shown, '/'))
end
