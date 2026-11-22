-- Grass and texture helpers for Detailed Weather, shared by the other modules: where the game's
-- grass edge art is, which grass overhangs which, the map blocks and their snow, and reading a
-- texture's pixels.
--
-- How the game draws grass (worked out in notes/handover.md):
--   * a grass tile's own clump is its screentexpos_background texture
--   * every overhang, grass or ground, comes from screentexpos_floor_flag: four bytes for the
--     tile's sides S, W, E, N, each the edging ID of the neighbour on that side (0 = none). 1 is
--     generic grass (the GRASS_1-9 tiles), 10 and up a grass with [CUSTOM_EDGING:n] (ID n + 9),
--     the rest soil and stone. The renderer picks the piece itself, and adds small corner pieces
--     where only a diagonal neighbour's grass reaches.
-- (This module once redrew the grass itself to sway it in the wind; the lean is now done by
-- swapping grass textures, in colour.lua.)
--@ module = true

-- The corners of a tile, with the two sides (S, W, E, N: floor_flag's byte order) each sits between.
CORNERS = {
    {name = 'NW', dx = -1, dy = -1, sides = {2, 4}},
    {name = 'NE', dx = 1, dy = -1, sides = {3, 4}},
    {name = 'SW', dx = -1, dy = 1, sides = {1, 2}},
    {name = 'SE', dx = 1, dy = 1, sides = {1, 3}},
}
-- Generic grass pieces: GRASS_1-9 are a 3x3 blob around a grass tile, so the piece for a tile
-- with grass to its north is the cell south of the centre, and so on.
GENERIC_PIECE = {N = 8, S = 2, W = 6, E = 4, NW = 9, NE = 7, SW = 3, SE = 1}
local GENERIC_GRASS = 1
local FIRST_CUSTOM = 10
local TILE = 32

----------------------------------------------------------------------------------------------
-- Where the edge art is: read from the active mods' graphics files
----------------------------------------------------------------------------------------------

function page_texpos(token, x, y)
    for _, page in ipairs(df.global.texture.page) do
        if page.token == token then
            local width = page.page_dim_x > 0 and page.page_dim_x or 1
            return page.texpos[y * width + x]
        end
    end
end

-- Mod paths are relative to the user data folder (installed mods) or the game folder (vanilla).
function graphics_files(mod_path)
    local dir
    for _, root in ipairs{dfhack.filesystem.getBaseDir(), dfhack.filesystem.getInstallDir(), ''} do
        if dfhack.filesystem.isdir(root .. mod_path) then dir = root .. mod_path:gsub('/$', '') .. '/graphics' break end
    end
    local files = {}
    for _, f in ipairs(dir and dfhack.filesystem.listdir_recursive(dir) or {}) do
        local path = f.path:sub(1, 1) == '/' and f.path or dir .. '/' .. f.path
        if not f.isdir and path:lower():match('%.txt$') then files[#files + 1] = path end
    end
    table.sort(files)
    return files
end

-- texpos -> the graphics token that names it (DIRT_FLOOR_5, SOIL_RAMP_WITH_WALL_N...), from every
-- active mod's graphics files; later mods override earlier ones, as the game does. Read once a
-- world (it reads every graphics file, ~200 ms).
local token_of
function texture_tokens()
    if token_of then return token_of end
    token_of = {}
    local pages = {}
    for _, page in ipairs(df.global.texture.page) do pages[page.token] = page end
    for _, mod in ipairs(require('script-manager').get_active_mods()) do
        for _, path in ipairs(graphics_files(mod.path)) do
            local file = io.open(path, 'r')
            local text = file and file:read('a') or ''
            if file then file:close() end
            for page, x, y, token in text:gmatch('%[TILE_GRAPHICS:([%w_]+):(%d+):(%d+):([%u_%d]+)') do
                local p = pages[page]
                local i = p and tonumber(y) * (p.page_dim_x > 0 and p.page_dim_x or 1) + tonumber(x)
                if i and i < #p.texpos then token_of[p.texpos[i]] = token end
            end
        end
    end
    return token_of
end
function forget_tokens() token_of = nil end

-- edges[id][piece name] = texpos, for every grass edging ID. Later mods override earlier ones,
-- as the game does.
function find_edge_art()
    local edges = {[GENERIC_GRASS] = {}}
    for _, mod in ipairs(require('script-manager').get_active_mods()) do
        for _, path in ipairs(graphics_files(mod.path)) do
            local file = io.open(path, 'r')
            local text = file and file:read('a') or ''
            if file then file:close() end
            for page, x, y, n in text:gmatch('%[TILE_GRAPHICS:([%w_]+):(%d+):(%d+):GRASS_(%d)%]') do
                for name, cell in pairs(GENERIC_PIECE) do
                    if cell == tonumber(n) then edges[GENERIC_GRASS][name] = page_texpos(page, tonumber(x), tonumber(y)) end
                end
            end
            -- each PLANT_GRAPHICS block: its CUSTOM_EDGING number and CUSTOM_EDGE_* pieces
            local starts = {}
            for at in text:gmatch('()%[PLANT_GRAPHICS:') do starts[#starts + 1] = at end
            starts[#starts + 1] = #text + 1
            for i = 1, #starts - 1 do
                local block = text:sub(starts[i], starts[i + 1] - 1)
                local number = tonumber(block:match('%[CUSTOM_EDGING:(%d+)%]'))
                if number then
                    local pieces = {}
                    for name, page, x, y in block:gmatch('%[CUSTOM_EDGE_(%u+):([%w_]+):(%d+):(%d+)%]') do
                        pieces[name] = page_texpos(page, tonumber(x), tonumber(y))
                    end
                    edges[number + FIRST_CUSTOM - 1] = pieces
                end
            end
        end
    end
    return edges
end

-- Each grass picture's edge pieces: grass texpos -> a list of the edge texposes the game draws
-- beside that grass (its PLANT_GRAPHICS block's custom edging, or the generic pieces if it has
-- none). The edges never show in a screen layer of their own, so a part that works from the
-- grasses seen on screen (colour.lua's leaning frames) finds a grass's edges here. Read once a
-- world, as it reads every graphics file.
local edges_by_grass
function edges_of_grass()
    if edges_by_grass then return edges_by_grass end
    edges_by_grass = {}
    local edges = find_edge_art()
    local function list_of(pieces)
        local list = {}
        for _, texpos in pairs(pieces or {}) do list[#list + 1] = texpos end
        return list
    end
    local generic = list_of(edges[GENERIC_GRASS])
    local lists = {}   -- edging ID -> list, shared by every grass with that edging
    for _, mod in ipairs(require('script-manager').get_active_mods()) do
        for _, path in ipairs(graphics_files(mod.path)) do
            local file = io.open(path, 'r')
            local text = file and file:read('a') or ''
            if file then file:close() end
            local starts = {}
            for at in text:gmatch('()%[PLANT_GRAPHICS:') do starts[#starts + 1] = at end
            starts[#starts + 1] = #text + 1
            for i = 1, #starts - 1 do
                local block = text:sub(starts[i], starts[i + 1] - 1)
                local number = tonumber(block:match('%[CUSTOM_EDGING:(%d+)%]'))
                local id = number and number + FIRST_CUSTOM - 1
                if id and not lists[id] then lists[id] = list_of(edges[id]) end
                for page, x, y in block:gmatch('%[GRASS_%d:([%w_]+):(%d+):(%d+)%]') do
                    local texpos = page_texpos(page, tonumber(x), tonumber(y))
                    if texpos then edges_by_grass[texpos] = id and lists[id] or generic end
                end
            end
        end
    end
    return edges_by_grass
end

----------------------------------------------------------------------------------------------
-- Which grass is where
----------------------------------------------------------------------------------------------

-- The map block holding a tile, or nil off the map. Blocks are kept between calls, as
-- dfhack.maps.getTileBlock costs ~50 us; they're pointers into the game, so the cache is dropped
-- whenever a map loads or unloads.
block_cache = block_cache or {}
function block_at(x, y, z)
    local key = ((z * 1024) + x // 16) * 1024 + (y // 16)
    local block = block_cache[key]
    if block == nil then
        block = dfhack.maps.getTileBlock(x, y, z) or false
        block_cache[key] = block
    end
    return block or nil
end
dfhack.onStateChange.detailed_weather_blocks = function(event)
    if event == SC_MAP_LOADED or event == SC_MAP_UNLOADED or event == SC_WORLD_UNLOADED then
        block_cache, block_snow = {}, {}
    end
end

-- The snow on a tile (0-255; the game draws it from about 100). Each block's snow is read in one go
-- (its events walked once, not once per tile) and kept for SNOW_KEPT_MS: snow comes and goes slowly.
local SNOW_KEPT_MS = 10000
local WATER = 6
block_snow = block_snow or {}   -- by block: {amounts (bx * 16 + by), due}
function snow_amount(x, y, z, now)
    local key = ((z * 1024) + x // 16) * 1024 + (y // 16)
    local kept = block_snow[key]
    if not kept or now >= kept.due then
        local block = block_at(x, y, z)
        if not block then return 0 end
        local amounts = {}
        for n = 0, 255 do amounts[n] = 0 end
        for _, event in ipairs(block.block_events) do
            if df.block_square_event_material_spatterst:is_instance(event) and event.mat_type == WATER
                    and event.mat_state == df.matter_state.Powder then
                for bx = 0, 15 do
                    local column = event.amount[bx]
                    for by = 0, 15 do
                        local a = column[by]
                        if a > amounts[bx * 16 + by] then amounts[bx * 16 + by] = a end
                    end
                end
            end
        end
        kept = {amounts = amounts, due = now + SNOW_KEPT_MS + math.random(0, SNOW_KEPT_MS // 2)}
        block_snow[key] = kept
    end
    return kept.amounts[(x % 16) * 16 + y % 16]
end
function forget_snow() block_snow = {} end

local grass_tiletype = {}   -- by tiletype: whether it's grass (df.tiletype.attrs costs ~40 us)

-- The edging ID of the grass on a tile, or nil if it isn't grass.
function grass_edging(x, y, z)
    local block = block_at(x, y, z)
    if not block then return nil end
    local tiletype = block.tiletype[x % 16][y % 16]
    local grassy = grass_tiletype[tiletype]
    if grassy == nil then
        local material = df.tiletype.attrs[tiletype].material
        grassy = material == df.tiletype_material.GRASS_LIGHT or material == df.tiletype_material.GRASS_DARK
        grass_tiletype[tiletype] = grassy
    end
    if not grassy then return nil end
    local best, amount = nil, 0
    for _, event in ipairs(block.block_events) do
        if df.block_square_event_grassst:is_instance(event) then
            local a = event.amount[x % 16][y % 16]
            if a > amount then best, amount = event.plant_index, a end
        end
    end
    local plant = best and df.global.world.raws.plants.all[best]
    if not plant then return nil end
    local custom = plant.texpos[5]   -- CUSTOM_EDGING minus one, or -1
    return custom >= 0 and custom + FIRST_CUSTOM or GENERIC_GRASS
end

-- Whether grass with edging `id` overhangs a tile whose own edging is `own` (nil: not grass).
-- Custom edging beats generic grass; between two customs the lower number wins.
function beats(id, own)
    if not own then return true end
    if id == own then return false end
    if id >= FIRST_CUSTOM and own >= FIRST_CUSTOM then return id < own end
    return id >= FIRST_CUSTOM
end

----------------------------------------------------------------------------------------------
-- Pixels
----------------------------------------------------------------------------------------------

-- A texture's pixels as {r, g, b, a} tables, row by row, or nil. The game's surfaces are SDL
-- ABGR8888: bytes R, G, B, A.
-- Kept by texture number, with what they were read from: the game builds some pictures as it
-- draws (trees, workshops, ramps) and gives a freed number to a new one, so a kept read is only
-- used while the number still has the same surface and a few of the same pixels.
--
-- Kept two ways, because the tables are what callers want but cost ~135 KB a texture (a table
-- for each of its 1,024 pixels), which over a few thousand textures is hundreds of megabytes:
--   packed_pixels   every texture read, as a string of its bytes (4 KB): reading a texture from
--                   the game is the slow part (a millisecond or two), so this is never thrown out
--   recent_pixels   the tables themselves, for the textures asked for lately only; unpacking a
--                   string into tables again takes about a tenth of a millisecond
-- Callers must not change the tables they're given.
local SIGNATURE_POINTS = {}
for k = 0, 15 do SIGNATURE_POINTS[#SIGNATURE_POINTS + 1] = (k * 389) % (TILE * TILE) end
local packed_pixels = {}             -- texpos -> {packed =, address =, sig =}
local RECENT_PIXELS = 128            -- tables kept: between this many textures' and twice it
local recent_pixels, older_pixels, recent_count = {}, {}, 0   -- texpos -> {px =, entry =}

-- Notes a texture's tables as asked for lately. When RECENT_PIXELS have been noted, the ones
-- noted before those are let go (anything still in use among them is noted again when asked for).
local function keep_recent(texpos, px, entry)
    recent_pixels[texpos] = {px = px, entry = entry}
    recent_count = recent_count + 1
    if recent_count >= RECENT_PIXELS then
        older_pixels, recent_pixels, recent_count = recent_pixels, {}, 0
    end
end

local function pack_pixels(px)
    local parts, char = {}, string.char
    for i = 1, #px do
        local p = px[i]
        parts[i] = char(p[1], p[2], p[3], p[4])
    end
    return table.concat(parts)
end

local function unpack_pixels(packed)
    local px, byte = {}, string.byte
    for i = 1, #packed // 4 do
        px[i] = {byte(packed, i * 4 - 3, i * 4)}
    end
    return px
end

local function surface_of(texpos)
    local surface = df.global.enabler.textures.raws[texpos]
    if not surface then return nil end
    local ints = df.reinterpret_cast('int32_t', surface)
    local w, h, pitch = ints:_displace(4)[0], ints:_displace(5)[0], ints:_displace(6)[0]
    if w ~= TILE or h ~= TILE then return nil end
    local address = df.reinterpret_cast('uint64_t', surface):_displace(4)[0]
    return df.reinterpret_cast('uint8_t', address), pitch, address
end

local function signature(bytes, pitch)
    local sum = 0
    for _, n in ipairs(SIGNATURE_POINTS) do
        local o = (n // TILE) * pitch + (n % TILE) * 4
        sum = (sum * 31 + bytes[o] + bytes[o + 1] * 7 + bytes[o + 2] * 13 + bytes[o + 3] * 17) % 2147483647
    end
    return sum
end

function pixels_of(texpos)
    if not texpos or texpos <= 0 then return nil end
    local bytes, pitch, address = surface_of(texpos)
    if not bytes then packed_pixels[texpos] = nil return nil end
    local sig = signature(bytes, pitch)
    local entry = packed_pixels[texpos]
    if entry and entry.address == address and entry.sig == sig then
        local recent = recent_pixels[texpos]
        if recent and recent.entry == entry then return recent.px end
        local older = older_pixels[texpos]
        local px = older and older.entry == entry and older.px
        if not px then
            px = unpack_pixels(entry.packed)
            pixels_unpacked = pixels_unpacked + 1
        end
        keep_recent(texpos, px, entry)
        return px
    end
    local px = {}
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            local o = y * pitch + x * 4
            px[#px + 1] = {bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]}
        end
    end
    entry = {packed = pack_pixels(px), address = address, sig = sig}
    pixels_read = pixels_read + 1
    packed_pixels[texpos] = entry
    keep_recent(texpos, px, entry)
    return px
end

-- Counts for `detailed_weather details`: textures read from the game, and kept strings unpacked
-- into tables again (each costs about a tenth of a millisecond).
pixels_read, pixels_unpacked = pixels_read or 0, pixels_unpacked or 0

-- How many textures' pixels are kept: as strings, and as tables.
function pixels_kept()
    local packed, tables = 0, 0
    for _ in pairs(packed_pixels) do packed = packed + 1 end
    for _ in pairs(recent_pixels) do tables = tables + 1 end
    for texpos in pairs(older_pixels) do
        if not recent_pixels[texpos] then tables = tables + 1 end
    end
    return packed, tables
end

-- Textures the modules have finished with go here (discard), and by default are never deleted:
-- they stay in memory until the game closes, about 4 KB each.
--
-- Why not delete them. Players on Windows have crashed inside dfhack.textures.deleteHandle, each
-- time at the same place in SDL, from three different callers: the world-unload handler, this
-- trash in the world after the one it was filled in (DFHack issue 6045), and a plain delete of a
-- tree's old copy in the middle of drawing a frame, in the world it was made in. The first two
-- have their own explanations (a handle outliving its world names freed memory); the third has
-- none but DFHack's deleteHandle itself, which frees a texture and then reads its memory once
-- more to see whether it's gone. If that memory has been handed to something else in between,
-- it frees it a second time. It has never crashed on Linux, where the mod is made, so it can't
-- be tested here, and a crash costs a player their unsaved fort where memory costs them
-- nothing they'll notice for hours. So: no deletes, until DFHack's own fix is out.
--
--   delete_textures   false (default): what's discarded is let go and counted (kept_count, and
--                     let_go_by for which part let it go).
--                     true (`detailed_weather textures free`, for testing): deleted a few at a
--                     time while a frame is drawn, as 1.3 did.
-- Since letting go costs memory for good, the modules keep what they can use again (a look's
-- copies, the grass's leaning frames for a wind direction, baked tiles) and no cache throws
-- anything out for being too big unless delete_textures is on: a kept texture costs what one
-- let go does, and can be used again.
-- Whatever the setting, nothing is deleted when a world unloads and nothing is kept across
-- worlds: abandon_trash() lets go of what's waiting, and each module's forget_world() drops its
-- textures the same way.
local TRASH_MS = 1
texture_trash = texture_trash or {}
if delete_textures == nil then delete_textures = false end
kept_count = kept_count or 0   -- textures let go without deleting, this session
let_go_by = let_go_by or {}    -- which part let them go -> how many
textures_at_load = textures_at_load or nil   -- how many textures the game had when this world's first frame was drawn

-- A texture a module has finished with. source: the part it was for, in words, for the count.
function discard(handle, source)
    if not handle then return end
    texture_trash[#texture_trash + 1] = handle
    source = source or 'other'
    let_go_by[source] = (let_go_by[source] or 0) + 1
end

function empty_trash()
    textures_at_load = textures_at_load or #df.global.enabler.textures.raws
    if not delete_textures then
        kept_count = kept_count + #texture_trash
        texture_trash = {}
        return
    end
    local started = dfhack.getTickCount()
    while #texture_trash > 0 and dfhack.getTickCount() - started < TRASH_MS do
        dfhack.textures.deleteHandle(table.remove(texture_trash))
    end
end

function abandon_trash()
    textures_at_load = nil   -- (called as a world unloads)
    kept_count = kept_count + #texture_trash
    texture_trash = {}
end

-- For `detailed_weather details`: how many textures the game holds now and how many more than
-- when the world loaded (the mod's and the game's own together), and what the mod has let go
-- without deleting, by part.
function describe_textures()
    local now = #df.global.enabler.textures.raws
    local lines = {('%d in the game, %s since this world loaded; %s'):format(now,
        textures_at_load and ('%+d (about %.0f MB)'):format(now - textures_at_load, (now - textures_at_load) * 4096 / 1e6)
            or 'not counted yet',
        delete_textures and 'deleted when finished with' or 'none deleted')}
    lines[#lines + 1] = ('    let go without deleting: %d, about %.0f MB'):format(kept_count, kept_count * 4096 / 1e6)
    local packed, tables = pixels_kept()
    lines[#lines + 1] = ('    pixels read and kept: %d textures (about %.0f MB), %d of them unpacked (about %.0f MB)'):format(
        packed, packed * 4200 / 1e6, tables, tables * 135000 / 1e6)
    lines[#lines + 1] = ('    read from the game %d times, unpacked again %d times'):format(pixels_read, pixels_unpacked)
    local sources = {}
    for source in pairs(let_go_by) do sources[#sources + 1] = source end
    table.sort(sources, function(a, b) return let_go_by[a] > let_go_by[b] end)
    for _, source in ipairs(sources) do
        lines[#lines + 1] = ('      %-34s %d'):format(source, let_go_by[source])
    end
    return table.concat(lines, '\n')
end

-- Another map or world loading: the next world's graphics may differ, so pixels and textures kept
-- by texture number could be another texture's.
function forget_world()
    block_cache, block_snow = {}, {}
    packed_pixels, recent_pixels, older_pixels, recent_count = {}, {}, {}, 0
    token_of, edges_by_grass = nil, nil
end
