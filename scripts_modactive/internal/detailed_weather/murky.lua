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

local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)

local work_time = reqscript('internal/detailed_weather/work_time')   -- the frame's shared time for background work

local TILE = 32
local CELLS = 4
local PLAN_MS = 1
-- (grungeisdead's copy, 2026-11-16) When the view has moved (a zoom, a pan, another level), blocks
-- not read yet are read in up to this much a frame for NEW_VIEW_FRAMES frames: at PLAN_MS (and the
-- slower block reads before READ BY WHOLE FLAGS, below) the tint came back over a second or two,
-- a block at a time, after every zoom or change of level (seen in play: the river flashing).
local NEW_VIEW_MS = 8
local NEW_VIEW_FRAMES = 4
local REMEMBER_MS = 4000
-- (grungeisdead's copy, 2026-11-17) DRY BLOCKS READ LESS: a block with no stagnant water, and none
-- under it in view, is read again after this long instead. Water rarely comes to a dry block, and
-- every block in view and the levels below, most of them dry, was read whole every 4 s
-- (detailed_weather details: murky 0.3 ms a frame). Stagnant water can take this long to show murky
-- where it first settles in a dry block.
local DRY_REMEMBER_MS = 30000
local MOST_DEPTH = 3           -- levels below the view, seen through open space, that get it

mode = mode or 'on'
-- NATIVE MURKY (grungeisdead's copy, 2026-11-19): true while the hook DLL draws the tint every frame
-- with these rules (internal/detailed_weather/native.lua; detailed_weather_dll.cpp: MURKY); apply
-- then only loads the art, which native.lua hands over (native_textures).
native_murky = native_murky or false
layer_name = layer_name or 'background_two'
-- WATER SEEN FROM ABOVE (grungeisdead's copy, 2026-11-19): a pond seen from the level above is drawn as
-- the water's surface over the level it's on, covering every layer of that lower view, so the tint
-- written into its item layer (then its spatter) was never seen (the hook DLL wrote 56, then 109 cells
-- there). In the view's own designation layer it showed, but over the banks' grass overhanging the
-- water in hard squares, and its ground layer is never empty on open air. The levels below are tinted in
-- the view's own layer above the spatter at that cell, as on the water's own level, where the banks'
-- edges draw over it.
lower_layer_name = 'background_two'
-- (grungeisdead's copy, 2026-11-19) and there, over whatever the game drew but Detailed Weather's own: on
-- open air above the water the game draws the water's ripple, a new number each frame, and those cells
-- were left untinted
local made = _G.detailed_weather_made or {}
-- block key -> {checked = tick count, tiles = {local index (x % 16 * 16 + y % 16)...}}
blocks = blocks or {}
timing = timing or {apply = 0}
drawn = drawn or {}   -- tiles drawn last frame, per depth below the view
last_view, new_view_left = last_view or nil, new_view_left or 0   -- (grungeisdead's copy) the view last frame
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
-- READ BY WHOLE FLAGS (grungeisdead's copy, 2026-11-16): each tile's designation is read once, as
-- the whole uint32 (DFHack's bitfield .whole), and its bits tested here, not four field reads a
-- tile through DFHack's bridge; and each column's tiletypes once. Bits as df-structures'
-- tile_designation names them: flow_size 0-2, hidden 9, liquid_type 21 (0 water, 1 magma),
-- water_stagnant 30.
local FLOW_SIZE, HIDDEN, MAGMA, STAGNANT = 7, 1 << 9, 1 << 21, 1 << 30
local function read_block(block, now)
    local tiles, open = {}, {}
    local designation, tiletype = block.designation, block.tiletype
    for lx = 0, 15 do
        local column, types = designation[lx], tiletype[lx]
        for ly = 0, 15 do
            local flags = column[ly].whole
            if flags & STAGNANT ~= 0 and flags & FLOW_SIZE ~= 0 and flags & MAGMA == 0 and flags & HIDDEN == 0 then
                tiles[#tiles + 1] = lx * 16 + ly
            end
            if see_through(types[ly]) then open[lx * 16 + ly] = true end
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
    local started = clock_ms()
    if not textures then textures = load_textures(art_path('murky.png')) end
    if native_murky then return end   -- (NATIVE MURKY: drawn by the DLL)
    -- the view moved: more time to read the blocks it brought in, for a few frames
    local view = ('%d,%d,%d,%d,%d'):format(viewport.x1, viewport.y1, viewport.x2, viewport.y2, viewport.z)
    if view ~= last_view then last_view, new_view_left = view, NEW_VIEW_FRAMES end
    local budget_ends = started + work_time.take(new_view_left > 0 and NEW_VIEW_MS or PLAN_MS)
    if new_view_left > 0 then new_view_left = new_view_left - 1 end
    -- a block's record, read again when it's old if there's time; nil if not read yet. Old is
    -- REMEMBER_MS for a block with stagnant water or over some (needed_often: which tiles are open
    -- matters), DRY_REMEMBER_MS for the rest (DRY BLOCKS READ LESS).
    local function known(bx, by, z, needed_often)
        local key = block_key(bx, by, z)
        local b = blocks[key]
        local old_ms = (needed_often or (b and #b.tiles > 0)) and REMEMBER_MS or DRY_REMEMBER_MS
        if (not b or started - b.checked > old_ms) and clock_ms() < budget_ends then
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
        -- (WATER SEEN FROM ABOVE: the levels below go into the view's own level, port_at(0))
        local layer = (depth == 0 and port or port_at(0))['screentexpos_' .. (depth == 0 and layer_name or lower_layer_name)]
        local dim_y = port.dim_y
        -- raw memory: never past the buffer's end (just after a zoom the viewport can be larger)
        local x2, y2 = math.min(viewport.x2, x1 + port.dim_x - 1), math.min(viewport.y2, y1 + dim_y - 1)
        for bx = x1 // 16, x2 // 16 do
            for by = y1 // 16, y2 // 16 do
                local b = known(bx, by, z - depth)
                if b and #b.tiles > 0 then
                    -- the levels above, which it must show through
                    local above = {}
                    for d = 0, depth - 1 do above[#above + 1] = known(bx, by, z - d, true) or false end
                    for _, index in ipairs(b.tiles) do
                        local x, y = bx * 16 + index // 16, by * 16 + index % 16
                        if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
                            local shows = true
                            for _, a in ipairs(above) do
                                if not (a and a.open[index]) then shows = false break end
                            end
                            local i = (x - x1) * dim_y + (y - y1)
                            local was = layer[i]
                            if shows and (was == 0 or (depth > 0 and not made[was])) then
                                layer[i] = textures[(y % CELLS) * CELLS + (x % CELLS) + 1]
                                drawn[depth] = drawn[depth] + 1
                            end
                        end
                    end
                end
            end
        end
    end
    timing.apply = timing.apply + (clock_ms() - started - timing.apply) * 0.05
end

-- (native.lua) The tint's 16 cells' textures, once apply has loaded them; nil before.
function native_textures() return textures end

-- The art loaded again next frame (after `detailed_weather reload`).
function clear_cache() textures = nil end

function forget_world()
    blocks = {}
end

function describe()
    if native_murky then return mode .. ': drawn by the hook DLL (detailed_weather native)' end
    local count = 0
    for _, known in pairs(blocks) do count = count + #known.tiles end
    local shown = {}
    for depth = 0, MOST_DEPTH do shown[#shown + 1] = drawn[depth] or 0 end
    return ('%s: %.2f ms a frame, %d stagnant tiles known, %s drawn by level down'):format(
        mode, timing.apply, count, table.concat(shown, '/'))
end
