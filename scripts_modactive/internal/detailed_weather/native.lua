-- Detailed Weather's native drawing: the hook DLL drawing all of the snow, and colour.lua's per-tile
-- swaps (grungeisdead's copy, 2026-11-18).
--
-- dfhooks_detailed_weather.dll (detailed_weather_dll.cpp) draws every frame all of snow_ramps.lua's
-- snow (snowy ramps, snowy floors and their thin snow, joins, skirts and overhangs, snowy edges and
-- corners, trunks, what lies on the snow), worked out from the map in native code. This module hands
-- it what it needs (the addresses and offsets DFHack knows, and snow_ramps.lua's tables) and turns
-- snow_ramps.lua's own planning and drawing off while it runs (its native_snow; it still bakes the
-- textures the DLL asks for). It was detailed_weather_hook_test.lua through the DLL's tests 1 to 4
-- (findings in DW_NATIVE_HOOK.md).
--
-- detailed_weather.lua calls update() every frame: the native snow starts on its own once a map is
-- loaded, while the ramps setting is on and the DLL is in DF's folder, and stops when the setting is
-- off or the world unloads. Without the DLL snow_ramps.lua draws the snow as before. A start that
-- can't go ahead (no snow on the map yet, say) is tried again every few seconds.
--
-- NATIVE COLOUR (test 5): the DLL also swaps the screen's tiles for colour.lua's copies every frame,
-- and puts the game's own ground back underground (detailed_weather_dll.cpp: THE COLOUR). colour.lua
-- still makes the copies and answers the DLL's questions about what each texture is (its NATIVE
-- COLOUR). It starts on its own once a map is loaded, while colour and its trees setting are on, and
-- stops when either is off; without the DLL colour.lua swaps the tiles as before.
--
-- NATIVE SHADE (test 6): the DLL also draws shade.lua's shade every frame (detailed_weather_dll.cpp:
-- THE SHADE), from all its shade tiles, made by shade.lua at start. It runs while the shade setting
-- is on; without the DLL shade.lua draws it as before.
--
-- FOG OVER WATER (test 15H): the game hazes everything seen down through open space with one haze a
-- cell, chosen by the level at the bottom of the cell. Water's bottom is a level under its surface,
-- so the water and everything over it (branches, the banks' edges) took a haze a step deeper than
-- the bank beside it on the same level. The DLL gives such cells their surface's haze
-- (detailed_weather_dll.cpp: FOG OVER WATER). It runs while the DLL is in DF's folder.
--
-- RAIN AND SNOW FALLING (test 15M): the DLL draws the falling rain and snow (detailed_weather_dll.cpp:
-- RAIN AND SNOW FALLING), working out from the map which tiles in view they fall on and writing the
-- sheet tiles, with put back. detailed_weather.lua still picks the sheets for how hard each falls, the
-- slant for the wind and the animation frame, and hands them over here each frame (rain_frame), with
-- the weather by map block when it rescans (rain_weather); it no longer finds the tiles or draws them.
-- It runs while the DLL is in DF's folder; without it detailed_weather.lua draws them as before.
--
-- CRACKS IN PLACE (test 15R; 15U; 15V): the DLL puts in frost.lua's dry cracks (detailed_weather_dll.cpp:
-- CRACKS IN PLACE), working out from the map which tiles may crack by frost.lua's rules (handed over
-- here at start: crack_rules), and painting each cracked copy itself the frame it's first needed, from
-- each look's numbers frost.lua hands over and blank textures made here. It runs while the DLL swaps the
-- colour (frost.lua: RAMPS IN THE LOOK); without it frost.lua plans and puts them in.
--
-- Commands (detailed_weather.lua): `detailed_weather native` prints what the DLL has counted since it
-- started; `native stop` hands the snow, the colour and the shade back to the Lua until `native start`;
-- `native fog` turns the fog over water off and on, to compare with the game's own; `native rain` hands
-- the falling rain and snow back to detailed_weather.lua and takes them again.
--@ module = true
local clock_ms = reqscript('internal/detailed_weather/clock').ms   -- the time in whole ms (clock.lua)
local clock_s = reqscript('internal/detailed_weather/clock').s     -- and in seconds, for timing short work

-- ==========================================
-- THE BLOCK (detailed_weather_dll.cpp: THE BLOCK)
-- ==========================================
-- Same offsets as the DLL's struct Block (and snow_ramps.lua's NATIVE_RINGS
-- for the bake rings). Change one side, change the others, and raise
-- LAYOUT in the DLL and here.
local LAYOUT = 38   -- (26: DRY CRACKS, test 15O: PaintJob carries a crack; 27: BRANCHES PROBED, 15P; 28: 15Q;
                    -- 29: CRACKS IN PLACE, 15R; 30: THE RAMP HELD, 15S; 31: THE NEXT LOOK AHEAD, 15T;
                    -- 32: THE TILES WORKED OUT by the DLL, 15U; 33: THE PAINTING HERE, 15V;
                    -- 34: THE FOG AND THE LEAVES DRAWN HERE, 15X; 35: THE SPATTER DRAWN HERE, 15Y;
                    -- 36: THE WAITS TAKEN OUT, 15Z: PaintJob's kind and blank number;
                    -- 37: THE RUSTLE PAINTED HERE, 16A; 38: THE GRASS WAVE DRAWN HERE, 16A)
local OFF = {
    magic = 0, layout = 8, enabled = 12, install = 16, hooked = 20,
    tables_ready = 24, tables_built = 28,
    renderer = 32, main_viewport = 40, lower_viewports = 48,
    window_x = 56, window_y = 64, window_z = 72,
    block_index = 80, x_count_block = 88, y_count_block = 96, z_count_block = 104,
    spatter_vtable = 112, grass_vtable = 120,
    lower_count = 128, off_flag = 132, off_dim_x = 136, off_dim_y = 140,
    off_background = 144, off_bg2 = 148, off_spatter = 152, off_floor_flag = 156,
    off_shadow_flag = 160, off_ramp_flag = 164, off_tiletype = 168, off_designation = 172,
    off_block_events = 176, off_ev_mat_type = 180, off_ev_mat_state = 184, off_ev_amount = 188,
    off_gev_plant = 192, off_gev_amount = 196,
    hidden_mask = 200, outside_mask = 204, black_texpos = 208,
    snow_mat_type = 212, snow_mat_state = 214, snowy_from = 216, edge_level = 220,
    drawn_x = 224, drawn_y = 228, drawn_z = 232, have_drawn = 236,
    prerender_calls = 240, tidy_calls = 248, plans = 256, applies = 264,
    apply_skipped = 272, view_moved = 280,
    ramps_written = 288, floors_written = 296, trunks_written = 304, edges_written = 312,
    cells_waiting = 320, bakes_asked = 328, bakes_done = 336, bakes_failed = 344,
    columns_last = 352, records_last = 360, snowy_last = 368, events_capped = 376,
    plan_us_total = 384, plan_us_max = 392, apply_us_total = 400, apply_us_max = 408,
    renderer_class = 416, install_failed = 480, plan_overflow = 484,
    bake_ring_full = 488, bake_map_full = 492,
    tt_flags = 20992, plant_edging = 23040, edge_art = 27136, snow_ramp_tex = 35328,
    full_tex = 36352, full_sides = 36432, full_col = 36452, full_inside = 36472,
    pieces_n = 36492, pieces_tex = 36512, page_n = 36832, made_n = 36836,
    page_tex = 36840, made_tex = 37864, thin_tex = 103400, inside_tex = 123880,
    cells_restored = 156648, blocks_last = 156656, blocks_full = 156660,
    tex_out_of_range = 156664, texpos_most = 156668, memory_kb = 156672,
    snowy_single = 156680,
    blocks_redone_last = 164872, blocks_kept_last = 164876, blocks_redone = 164880, blocks_kept = 164888,
    -- THE COLOUR (layout 8)
    col_enabled = 164896, col_depths = 164900, off_building_one = 164904, off_building_two = 164908,
    off_item = 164912, off_vehicle = 164916, col_link = 164920, col_flags = 164928, col_tex_map = 164936,
    col_period = 164940, subterranean_mask = 164944, flow_mask = 164948, col_reset = 164952,
    col_reset_done = 164956, col_req_head = 164960, col_req_tail = 164964, col_seen_head = 164968,
    col_seen_tail = 164972, col_req = 164976, col_seen = 173168,
    col_frames = 177264, col_swapped = 177272, col_put_back = 177280, col_held = 177288, col_asked = 177296,
    col_waiting = 177304, col_ring_full = 177312, col_seen_full = 177316, col_us_total = 177320,
    col_us_max = 177328, col_cells_last = 177336, col_swapped_last = 177340,
    -- THE SWAY (layout 9)
    sway_playing = 177344, sway_reset = 177348, sway_reset_done = 177352, sway_waves = 177356,
    sway_ux = 177360, sway_uy = 177368, sway_of = 177376, sway_tex = 177384, sway_max = 177392,
    sway_phases = 177396, sway_swapped = 177400, col_tt = 177408,
    -- THE SHADE (layout 10)
    shade_enabled = 179456, off_designation_layer = 179460, shade_frames = 179464, shade_written = 179472,
    shade_us_total = 179480, shade_us_max = 179488, shade_cells_last = 179496, shade_tex = 179504,
    -- PAINTING (layout 11)
    paint_head = 182008, paint_tail = 182012, paint_done = 182016, paint_us_total = 182024,
    paint_us_max = 182032, paint_bad = 182040, paint = 182048,
    -- MURKY (layout 13)
    murky_enabled = 247584, stagnant_mask = 247588, magma_mask = 247592, murky_depths = 247596,
    murky_tex = 247600, murky_frames = 247664, murky_written = 247672, murky_us_total = 247680,
    murky_us_max = 247688, murky_drawn = 247696,
    -- MURKY: EDGES OVER THE TINT (layout 14)
    murky_blank_head = 247712, murky_blank_tail = 247716, murky_blank_tex = 247720, murky_blank_addr = 248744,
    murky_tint_addr = 250792, edge_addr = 250920, murky_baked = 267304, murky_bake_waits = 267312,
    murky_corners = 267316, murky_bake_reset = 267320, murky_bake_reset_done = 267324,
    -- MURKY: FRAME BY FRAME (layout 15; moved in 16 by the wider ring)
    murky_hist_head = 267328, murky_empty_pieces = 267332, murky_hist = 267336,
    -- PATHS (layout 18)
    paths_enabled = 271432, paths_depths = 271436, paths_reset = 271440, paths_reset_done = 271444,
    paths_plan_reset = 271448, paths_plan_reset_done = 271452, paths_soil_addr = 271456,
    paths_soil_ask = 271464, paths_soil_done = 271468, paths_soil_seen = 271472,
    paths_q_head = 271488, paths_q_tail = 271492, paths_q = 271496, paths_a_head = 272520,
    paths_a_tail = 272524, paths_a = 272528, paths_kind = 276624, paths_frames = 278672,
    paths_baked = 278680, paths_waits = 278688, paths_cells_last = 278692, paths_known = 278696,
    paths_blocks_last = 278700, paths_blocks_total = 278704, paths_plan_us_total = 278712,
    paths_plan_us_max = 278720, paths_draw_us_total = 278728, paths_draw_us_max = 278736,
    paths_plans = 278744, paths_q_full = 278752,
    -- MURKY: THE HAZE and THE PROBE (layout 21)
    haze_air_addr = 278760, haze_layers_last = 278768, probe_ask = 278772, probe_done = 278776,
    probe_d = 278780, probe_x = 278784, probe_y = 278788, off_probe = 278792, probe_val = 278856,
    -- FOG OVER WATER (layout 22)
    fog_enabled = 279880, off_interface = 279884, fog_tex_addr = 279888, fog_frames = 279896,
    fog_moved = 279904, fog_put_back = 279912, fog_plans = 279920, fog_plan_us_total = 279928,
    fog_plan_us_max = 279936, fog_us_total = 279944, fog_us_max = 279952, fog_marked_last = 279960,
    fog_moved_last = 279964, fog_already_last = 279968, fog_unmatched_last = 279972, fog_dry_last = 279976,
    fog_kept_full = 279980, fog_odd_d = 279984, fog_odd_slot = 279988, fog_odd_haze = 279992,
    fog_census_ask = 279996, fog_census_done = 280000, fog_census_cells = 280004, fog_census_multi = 280008,
    fog_census = 280012, fog_reset = 280300, fog_reset_done = 280304, fog_blocks_walked_last = 280308,
    fog_blocks_kept = 280312, fog_blocks_walked = 280320,
    -- THE COLOUR: PICTURES CHECKED HERE (layout 23)
    col_raws = 280328, col_verified_head = 280336, col_verified_tail = 280340, col_verified = 280344,
    col_pics_checked = 284440, col_pics_changed = 284448, col_pics_kept = 284456,
    -- THE COLOUR: THE HELD SLOTS (layout 24)
    col_wait_new = 284464, col_wait_nohold = 284472, col_held_moved = 284480,
    -- RAIN AND SNOW FALLING (layout 25)
    rain_enabled = 284488, off_high_flow = 284492, off_top_shadow = 284496,
    rain_wz = 284504, rain_wbx = 284508, rain_wby = 284512, rain_wnx = 284516, rain_wny = 284520,
    rain_weather_any = 284524, rain_weather = 284528, tt_empty = 288624,
    rain_cells = 290672, rain_anim = 290676, rain_slants = 290680, rain_slant = 290684, rain_frame = 290688,
    snow_cells = 290692, snow_anim = 290696, snow_wind = 290700, snow_frame = 290704,
    rain_tex_n = 290708, snow_tex_n = 290712, rain_tex = 290716, snow_tex = 356252,
    rain_dropped = 421788,   -- (15N: was padding)
    rain_frames = 421792, rain_drawn = 421800, rain_put_back = 421808, rain_us_total = 421816,
    rain_us_max = 421824, rain_cells_last = 421832, rain_drawn_last = 421836, rain_over_flow_last = 421840,
    rain_no_room_last = 421844, rain_kept_full = 421848, rain_skipped = 421852,
    -- MURKY: BRANCHES PROBED (layout 27)
    probe_through = 421856, murky_under_branch_last = 421860, murky_under_branch = 421864,
    -- MURKY: BRANCHES SEEN THROUGH (layout 28)
    murky_branch_above_last = 421872,
    -- CRACKS IN PLACE (layout 33: the tiles worked out by the DLL from the map, their copies painted there)
    crack_on = 421880, crack_gen = 421884, crack_gen_prev = 421888, crack_gen_next = 421892,
    crack_next_walked = 421896, crack_next_missing_last = 421900, crack_depth = 421904, crack_world = 421908,
    crack_recheck = 421912, off_temperature = 421916, crack_forced_on = 421920, crack_tables = 421924,
    crack_band_c = 421928, crack_cool_from = 421936, crack_warm_from = 421944, crack_forced_c = 421952,
    crack_tt = 421960, crack_look = 424008, crack_heat = 490616, crack_ground = 490744,
    crack_b_head = 490752, crack_b_tail = 490756, crack_b = 490760,
    crack_d_head = 498952, crack_d_tail = 498956, crack_d = 498960,
    crack_frames = 531728, crack_written = 531736, crack_painted = 531744, crack_ahead_painted = 531752,
    crack_ramp_held = 531760, crack_blocks_worked = 531768, crack_waiting = 531776, crack_us_total = 531784,
    crack_us_max = 531792, crack_paint_us_total = 531800, crack_paint_us_max = 531808,
    crack_cells_last = 531816, crack_written_last = 531820, crack_held_last = 531824, crack_waiting_last = 531828,
    crack_ramp_held_last = 531832, crack_tiles_kept = 531836, crack_cleared = 531840, crack_worked_last = 531844,
    crack_painted_last = 531848, crack_no_blank = 531852, crack_over_time = 531856, crack_unreadable = 531860,
    crack_copies_kept = 531864, crack_table_full = 531868, crack_pics_kept = 531872, crack_done_full = 531876,
    -- THE FOG AND THE LEAVES DRAWN HERE (layout 34)
    wfog_on = 531880, wfog_level = 531884, wfog_patch = 531888, wfog_frames = 531892, wfog_steps = 531896,
    wfog_tex_n = 531932, wfog_tex = 531936, wfog_frames_drawn = 597472, wfog_drawn = 597480, wfog_put_back = 597488,
    wfog_us_total = 597496, wfog_us_max = 597504, wfog_cells_last = 597512, wfog_drawn_last = 597516,
    wfog_taken_last = 597520, wfog_kept_full = 597524, wfog_dropped = 597528, off_projectile = 597532,
    leaf_on = 597536, leaf_any = 597540, leaf_cells = 597544, leaf_frames = 597548, leaf_winds = 597552,
    leaf_heavies = 597556, leaf_frame = 597560, leaf_wind = 597564, leaf_tables = 597568, leaf_recheck = 597572,
    column_index = 597576, off_col_plants = 597584, off_plant_pos = 597588, off_plant_material = 597592,
    off_plant_tree = 597596, off_tree_body = 597600, off_tree_height = 597604, off_tree_dim_x = 597608,
    off_tree_dim_y = 597612, wl_tt = 597616, leaf_sheds = 599664, leaf_spec = 600688, leaf_tex_n = 602736,
    leaf_tex = 602768, leaf_frames_drawn = 930448, leaf_drawn = 930456, leaf_put_back = 930464,
    leaf_blocks_worked = 930472, leaf_us_total = 930480, leaf_us_max = 930488, leaf_cells_last = 930496,
    leaf_drawn_last = 930500, leaf_maps_kept = 930504, leaf_pool_full = 930508, leaf_kept_full = 930512,
    leaf_dropped = 930516, leaf_trees_bad = 930520, leaf_worked_last = 930524,
    -- THE SPATTER DRAWN HERE (layout 35)
    spat_on = 930528, spat_blades = 930532, spat_vtable = 930536, off_isp_amount = 930544, spat_tables = 930548,
    spat_grass = 930552, spat_frames = 930560, spat_written = 930568, spat_blades_written = 930576,
    spat_put_back = 930584, spat_painted = 930592, spat_us_total = 930600, spat_us_max = 930608,
    spat_paint_us_max = 930616, spat_cells_last = 930624, spat_written_last = 930628, spat_waiting_last = 930632,
    spat_no_blank = 930636, spat_over_time = 930640, spat_unreadable = 930644, spat_bakes_kept = 930648,
    spat_bakes_full = 930652, spat_kept_full = 930656, spat_dropped = 930660,
    -- THE WAITS TAKEN OUT (layout 36)
    paths_held = 930664, paths_put_off = 930672, paths_no_blank = 930680, paths_bases_dropped = 930684,
    paths_bakes_halved = 930688, paths_held_last = 930692, col_by_picture = 930696, col_pics_filed = 930704,
    col_pics_halved = 930708, paint_unpremultiplied = 930712, paint_leans = 930720, snow_bake_here = 930728,
    bake_here_head = 930732, bake_here_tail = 930736, bakes_here_put_off = 930740, bakes_here = 930744,
    bake_here_us_total = 930752, bake_here = 930760, bakes_here_over_time = 934856,
    -- THE RUSTLE PAINTED HERE (layout 37)
    paint_rustles = 934864, rustle_of_ready = 934872, canopy_wood = 934876, rustle_of = 934880,
    -- THE GRASS WAVE DRAWN HERE (layout 38)
    wave_on = 935904, wave_gen = 935908, wave_gen_done = 935912, wave_built = 935916, wave_slot_n = 935920,
    wave_x1 = 935924, wave_y1 = 935928, wave_cols = 935932, wave_rows = 935936, wave_playing = 935940,
    wave_cx = 935944, wave_cy = 935952, wave_reach = 935960, wave_ux = 935968, wave_uy = 935976,
    wave_clock = 935984, wave_slots = 935992, wave_slots_most = 936000, wave_hist_head = 936004,
    wave_hist = 936008, wave_want_head = 968776, wave_want_tail = 968780, wave_want = 968784,
    wave_frames = 969808, wave_written = 969816, wave_us_total = 969824, wave_us_max = 969832,
    wave_written_last = 969840, wave_wants = 969844, wave_map_full = 969848, wave_want_full = 969852,
}
local PAINT_RING = 256    -- the DLL's paint ring (PAINT_RING)
local MURKY_BLANKS = 256  -- the DLL's ring of blanks for murky's edges (murky_blank_tex; 64 before layout 16)
local SHADE_N = 625       -- the DLL's shade tiles (SHADE_N)
local COL_RING = 1024     -- the DLL's colour rings (COL_RING)
local CRACK_BLANKS = 512      -- CRACKS IN PLACE: the DLL's ring of blank textures kept ready (CRACK_BLANKS)
local CRACK_DONE_RING = 2048  -- and its ring of copies painted there (CRACK_DONE_RING)
local CRACK_LOOK_BYTES, PAINT_JOB_BYTES = 33304, 256   -- the DLL's CrackLook and PaintJob
local CRACK_FLOORS = 4096     -- the most originals a look lists its copies of (the DLL's CRACK_FLOORS)
local BLANK_MS, BLANK_LOW_MS, BLANK_FIRST_MS = 1, 4, 60   -- blanks made at most this long a frame (more when under a
                                                          -- quarter are left, after a new view; and at start)
local CRACK_RECHECK = 600     -- frames between a map block's tiles worked out again (frost.lua kept a tile 10 to 15 s)
local FLOW_BITS = 7       -- tile_designation's flow_size: bits 0 to 2 (df-structures; colour.lua: FLOW_SIZE)
local CLASS_BYTES = 64
local TT_TABLE, PLANTS, FULL, PAGE_MAX, MADE_MAX = 2048, 4096, 20, 256, 16384
-- art/snow_thin_sheet.lua's layout, as the DLL is built for
local SHEET = {columns = 20, levels = 4, variants = 4, repeat_tiles = 4, inside_variants = 2}
local THIN_N, INSIDE_N = 5120, 8192
local EDGE_NAMES = {'N', 'S', 'W', 'E', 'NW', 'NE', 'SW', 'SE'}   -- the DLL's edge_art order
local WATER = 6           -- the game's snow is powder WATER (grass.lua: snow_amount)
local SNOWY = 100         -- snow from which a tile is snowy (snow_ramps.lua: SNOWY)

-- Raw memory, through DFHack's typed views (as stockhook.lua does):
-- df.reinterpret_cast(type, address).value reads or writes one value.
local function peek(t, a) return df.reinterpret_cast(t, a).value end
local function poke(t, a, v) df.reinterpret_cast(t, a).value = v end

-- A DF object's address: the second value of :sizeof().
local function addr_of(ref) local _, a = ref:sizeof(); return a end

-- The block's address, or nil and why.
local function block()
    local s = os.getenv('DWHOOK_BLOCK')
    if not s or s == '' then
        return nil, "no hook DLL loaded (DWHOOK_BLOCK not set): dfhooks_detailed_weather.dll isn't in DF's folder"
    end
    local base = tonumber(s, 16)
    if not base then return nil, 'DWHOOK_BLOCK unreadable: ' .. s end
    local magic = {}
    for i = 0, 7 do magic[#magic + 1] = string.char(peek('uint8_t', base + i)) end
    if table.concat(magic) ~= 'DWHOOK01' then return nil, 'block magic wrong' end
    local layout = peek('uint32_t', base + OFF.layout)
    if layout ~= LAYOUT then
        return nil, ('block layout %d, this file speaks %d: update both together'):format(layout, LAYOUT)
    end
    return base
end

-- snow_ramps.lua, which owns the snow's art and tables and bakes for the DLL.
local function snow_module()
    local ok, sr = pcall(reqscript, 'internal/detailed_weather/snow_ramps')
    if not ok or not sr then return nil end
    return sr
end

-- ==========================================
-- WHAT THE DLL NEEDS TO KNOW
-- ==========================================
-- A tile_designation bit as a mask, set on a scratch word through DFHack's
-- own layout; the fallback is where df-structures puts it.
local function designation_mask(name, fallback)
    local ok, mask = pcall(function()
        local raw = df.new('uint32_t')
        raw.value = 0
        local d = df.reinterpret_cast(df.tile_designation, addr_of(raw))
        d[name] = true
        local m = raw.value
        df.delete(raw)
        return m
    end)
    if ok and mask and mask ~= 0 then return mask, 'read' end
    return fallback, 'fallback'
end

-- The DLL's tiletype table (detailed_weather_dll.cpp: TT_*), from DFHack's
-- tiletype attributes, as snow_ramps.lua's shape() reads them.
local function fill_tiletypes(base)
    local shape, basic, material = df.tiletype_shape, df.tiletype_shape_basic, df.tiletype_material
    local last = math.min(df.tiletype._last_item, TT_TABLE - 1)
    local ramps = 0
    for tt = 0, TT_TABLE - 1 do
        local f = 0
        if tt <= last and df.tiletype[tt] then
            local a = df.tiletype.attrs[tt]
            local s, m = a.shape, a.material
            if s == shape.RAMP then f = f | 1 ramps = ramps + 1 end
            if df.tiletype_shape.attrs[s].basic_shape == basic.Floor then f = f | 2 end
            if s == shape.EMPTY or s == shape.RAMP_TOP then f = f | 4 end
            if m == material.TREE then f = f | 8 end
            if s == shape.WALL and m == material.TREE then f = f | 16 end
            if m == material.GRASS_LIGHT or m == material.GRASS_DARK then f = f | 32 end
            -- (RAMPS IN THE LOOK, test 15A: a ramp's class, as frost.lua's class_of_tiletype)
            if m == material.SOIL then f = f | 64 end
            if m == material.GRASS_LIGHT or m == material.GRASS_DARK or m == material.GRASS_DRY
                or m == material.GRASS_DEAD then f = f | 128 end
        end
        poke('uint8_t', base + OFF.tt_flags + tt, f)
    end
    return ramps
end

-- An event of a class on the map, for its vtable and its fields' offsets:
-- the first found, block by block. nil when the map has none.
local function any_event(class)
    for _, blk in ipairs(df.global.world.map.map_blocks) do
        for _, ev in ipairs(blk.block_events) do
            if class:is_instance(ev) then return ev end
        end
    end
    return nil
end

-- snow_ramps.lua's tables (native_tables) into the block.
-- Whether snow_ramps.lua's tables are the shape the DLL is built for: checked before anything is let go,
-- so a start that can't go ahead leaves snow_ramps.lua drawing as it was.
local function check_tables(t)
    local layout = t.layout
    for k, v in pairs(SHEET) do
        if layout[k] ~= v then qerror(('art/snow_thin_sheet.lua has %s %s, the DLL is built for %s'):format(k, tostring(layout[k]), v)) end
    end
    if #t.thin ~= THIN_N or #t.inside ~= INSIDE_N then
        qerror(('the thin sheets have %d and %d textures, the DLL is built for %d and %d'):format(#t.thin, #t.inside, THIN_N, INSIDE_N))
    end
    if #t.full ~= FULL then qerror(('the snow page gave %d FULL pieces, the DLL is built for %d'):format(#t.full, FULL)) end
end

local function fill_snow_tables(base, t)
    local layout = t.layout
    poke('int32_t', base + OFF.edge_level, layout.edge_level)
    for byte = 0, 255 do poke('int32_t', base + OFF.snow_ramp_tex + byte * 4, t.ramps[byte] or 0) end
    for k, piece in ipairs(t.full) do
        local i = k - 1
        local col = layout.cells[piece.cell]
        poke('int32_t', base + OFF.full_tex + i * 4, piece.texpos or 0)
        poke('uint8_t', base + OFF.full_sides + i, piece.sides)
        poke('uint8_t', base + OFF.full_col + i, col or 255)
        poke('uint8_t', base + OFF.full_inside + i, layout.inside_cells[piece.cell] and 1 or 0)
    end
    for mask = 0, 15 do
        local list = t.pieces[mask] or {}
        poke('uint8_t', base + OFF.pieces_n + mask, math.min(#list, 5))
        for n = 1, 5 do poke('int32_t', base + OFF.pieces_tex + (mask * 5 + n - 1) * 4, list[n] or 0) end
    end
    local page_n = math.min(#t.page, PAGE_MAX)
    poke('int32_t', base + OFF.page_n, page_n)
    for n = 1, page_n do poke('int32_t', base + OFF.page_tex + (n - 1) * 4, t.page[n]) end
    -- the textures snow_ramps.lua made, less those handed over in their own tables (the thin sheets
    -- and snowy ramps): its bakes, which can still be on screen where DF hasn't redrawn since
    local known = {}
    for _, texpos in ipairs(t.thin) do known[texpos] = true end
    for _, texpos in ipairs(t.inside) do known[texpos] = true end
    for byte = 0, 255 do known[t.ramps[byte] or 0] = true end
    local bakes = {}
    for _, texpos in ipairs(t.made) do if not known[texpos] then bakes[#bakes + 1] = texpos end end
    local made_n = math.min(#bakes, MADE_MAX)
    poke('int32_t', base + OFF.made_n, made_n)
    for n = 1, made_n do poke('int32_t', base + OFF.made_tex + (n - 1) * 4, bakes[n]) end
    for n = 1, THIN_N do poke('int32_t', base + OFF.thin_tex + (n - 1) * 4, t.thin[n]) end
    for n = 1, INSIDE_N do poke('int32_t', base + OFF.inside_tex + (n - 1) * 4, t.inside[n]) end
    local edge_ids = 0
    for id = 0, 255 do
        local art = t.edges[id]
        if art then edge_ids = edge_ids + 1 end
        for n, name in ipairs(EDGE_NAMES) do
            poke('int32_t', base + OFF.edge_art + (id * 8 + n - 1) * 4, art and art[name] or 0)
        end
    end
    for plant = 0, PLANTS - 1 do
        local id = t.plant_edging[plant] or 0
        poke('uint8_t', base + OFF.plant_edging + plant, math.min(id, 255))
    end
    -- each edge piece's snowy version, baked at start (snow_ramps.lua: SNOWY EDGES AT ONCE)
    local singles = 0
    for id = 0, 255 do
        local row = t.edges_snowy and t.edges_snowy[id]
        for n, name in ipairs(EDGE_NAMES) do
            local texpos = row and row[name] or 0
            if texpos ~= 0 then singles = singles + 1 end
            poke('int32_t', base + OFF.snowy_single + (id * 8 + n - 1) * 4, texpos)
        end
    end
    return {page = page_n, made = made_n, made_all = #bakes, edge_ids = edge_ids, singles = singles, kept = t.edges_kept or 0}
end

-- ==========================================
-- COMMANDS
-- ==========================================
local COUNTS = {'prerender_calls', 'tidy_calls', 'plans', 'applies', 'apply_skipped', 'view_moved',
                'ramps_written', 'floors_written', 'trunks_written', 'edges_written', 'cells_waiting',
                'bakes_asked', 'bakes_done', 'bakes_failed', 'columns_last', 'records_last',
                'snowy_last', 'events_capped', 'cells_restored', 'blocks_redone', 'blocks_kept'}
local function reset_counts(base)
    for _, name in ipairs(COUNTS) do poke('int64_t', base + OFF[name], 0) end
    for _, name in ipairs({'plan_us_total', 'plan_us_max', 'apply_us_total', 'apply_us_max'}) do
        poke('double', base + OFF[name], 0)
    end
    for _, name in ipairs({'plan_overflow', 'bake_ring_full', 'bake_map_full', 'blocks_full'}) do poke('uint32_t', base + OFF[name], 0) end
end

started_note = started_note or nil   -- what the last start found, for the report
local fill_weather_tt                -- filled in fill_common so draw_shade always has wl_tt

-- What the snow and the colour both need: the viewports, the view's corner and the map. Filled again
-- by whichever starts (the same values). Returns what it found, in words.
local function fill_common(base)
    local gps = df.global.gps
    local vp = gps.main_viewport
    local map = df.global.world.map
    if not vp or not dfhack.isMapLoaded() or #map.map_blocks == 0 then qerror('no map: load a fort first') end
    local wx = dfhack.internal.getAddress('window_x')
    local wy = dfhack.internal.getAddress('window_y')
    local wz = dfhack.internal.getAddress('window_z')
    if not wx or not wy or not wz then qerror('DFHack has no address for window_x, window_y or window_z') end

    -- ---- THE VIEWPORTS ----
    -- gps.main_viewport's FIELD, not the viewport: the DLL reads the pointer
    -- fresh each frame, since a zoom remakes the viewports. The levels seen
    -- below are gps.lower_viewport (the Lua mod's ports[depth]).
    local vbase = addr_of(vp)
    local function voff(name) return addr_of(vp:_field(name)) - vbase end
    poke('uint64_t', base + OFF.renderer, addr_of(df.global.enabler.renderer))
    poke('uint64_t', base + OFF.main_viewport, addr_of(gps:_field('main_viewport')))
    poke('uint64_t', base + OFF.lower_viewports, addr_of(gps:_field('lower_viewport')))
    poke('uint32_t', base + OFF.lower_count, #gps.lower_viewport)
    poke('uint32_t', base + OFF.off_flag, voff('flag'))
    poke('uint32_t', base + OFF.off_dim_x, voff('dim_x'))
    poke('uint32_t', base + OFF.off_dim_y, voff('dim_y'))
    poke('uint32_t', base + OFF.off_background, voff('screentexpos_background'))
    poke('uint32_t', base + OFF.off_bg2, voff('screentexpos_background_two'))
    poke('uint32_t', base + OFF.off_spatter, voff('screentexpos_spatter'))
    poke('uint32_t', base + OFF.off_floor_flag, voff('screentexpos_floor_flag'))
    poke('uint32_t', base + OFF.off_shadow_flag, voff('screentexpos_shadow_flag'))
    poke('uint32_t', base + OFF.off_ramp_flag, voff('screentexpos_ramp_flag'))
    -- (the colour's other four layers: colour.lua's SCREEN_LAYERS)
    poke('uint32_t', base + OFF.off_building_one, voff('screentexpos_building_one'))
    poke('uint32_t', base + OFF.off_building_two, voff('screentexpos_building_two'))
    poke('uint32_t', base + OFF.off_item, voff('screentexpos_item'))
    poke('uint32_t', base + OFF.off_vehicle, voff('screentexpos_vehicle'))
    -- (the shade's layer, which draws over everything on the map)
    poke('uint32_t', base + OFF.off_designation_layer, voff('screentexpos_designation'))
    -- a cell the game hasn't drawn yet shows its black (snow_ramps.lua: UNDRAWN CELLS)
    poke('int32_t', base + OFF.black_texpos, gps.black_background_texpos[0])

    -- ---- THE VIEW'S CORNER ----
    poke('uint64_t', base + OFF.window_x, wx)
    poke('uint64_t', base + OFF.window_y, wy)
    poke('uint64_t', base + OFF.window_z, wz)

    -- ---- THE MAP ----
    local blk = map.map_blocks[0]
    local bbase = addr_of(blk)
    poke('uint64_t', base + OFF.block_index, addr_of(map:_field('block_index')))
    poke('uint64_t', base + OFF.x_count_block, addr_of(map:_field('x_count_block')))
    poke('uint64_t', base + OFF.y_count_block, addr_of(map:_field('y_count_block')))
    poke('uint64_t', base + OFF.z_count_block, addr_of(map:_field('z_count_block')))
    poke('uint32_t', base + OFF.off_tiletype, addr_of(blk:_field('tiletype')) - bbase)
    poke('uint32_t', base + OFF.off_designation, addr_of(blk:_field('designation')) - bbase)
    poke('uint32_t', base + OFF.off_block_events, addr_of(blk:_field('block_events')) - bbase)
    local hidden, hidden_how = designation_mask('hidden', 512)
    local outside, outside_how = designation_mask('outside', 1 << 16)
    local under, under_how = designation_mask('subterranean', 1 << 15)
    poke('uint32_t', base + OFF.hidden_mask, hidden)
    poke('uint32_t', base + OFF.outside_mask, outside)
    poke('uint32_t', base + OFF.subterranean_mask, under)
    poke('uint32_t', base + OFF.flow_mask, FLOW_BITS)
    local ramp_types = fill_tiletypes(base)
    if fill_weather_tt then fill_weather_tt(base) end
    return ('%d tiletypes are ramps; hidden bit %d (%s), outside bit %d (%s), subterranean bit %d (%s); map %d x %d blocks, %d levels.')
        :format(ramp_types, hidden, hidden_how, outside, outside_how, under, under_how,
                map.x_count_block, map.y_count_block, map.z_count_block)
end

local function start(base)
    local map = df.global.world.map
    if not df.global.gps.main_viewport or not dfhack.isMapLoaded() or #map.map_blocks == 0 then qerror('no map: load a fort first') end
    local sr = snow_module()
    if not sr or type(sr.native_tables) ~= 'function' or type(sr.serve_native_bakes) ~= 'function' then
        qerror('snow_ramps.lua has no NATIVE SNOW yet: apply its pairs first')
    end
    local spatter_ev = any_event(df.block_square_event_material_spatterst)
    if not spatter_ev then qerror('no material spatter anywhere on this map, so no snow to draw: try a snowy fort') end
    local grass_ev = any_event(df.block_square_event_grassst)

    -- ---- SNOW_RAMPS.LUA'S TABLES, CHECKED ----
    local tables_from = clock_s()   -- (test 14M: the start timed, for the note)
    -- (THE SNOW'S BAKES HERE, 15Z: the DLL paints each snowy edge when first wanted, so none is baked at start)
    local t = sr.native_tables(true)
    local tables_ms = (clock_s() - tables_from) * 1000
    check_tables(t)

    -- ---- OFF WHILE THE TABLES ARE FILLED ----
    poke('uint32_t', base + OFF.enabled, 0)
    -- everything snow_ramps.lua kept to draw (its records and block copies) let go. forget() also drops
    -- its thin sheets and fades, which the DLL draws with (made again, they'd be 13312 more textures,
    -- kept for the session): those are put back.
    sr.native_snow = false
    local art, layout, faded = sr.thin_art, sr.thin_layout, sr.thin_faded
    sr.forget()
    sr.thin_art, sr.thin_layout, sr.thin_faded = art, layout, faded or {}

    -- ---- THE VIEWPORTS, THE VIEW'S CORNER AND THE MAP ----
    local common = fill_common(base)

    -- ---- THE SNOW AND THE GRASS ----
    -- An event's vtable (its first 8 bytes, which is how the DLL tells the
    -- class) and its fields' offsets, read off a live one. The game's snow
    -- is the spatter of WATER as Powder (grass.lua: snow_amount).
    local ebase = addr_of(spatter_ev)
    poke('uint64_t', base + OFF.spatter_vtable, peek('uint64_t', ebase))
    poke('uint32_t', base + OFF.off_ev_mat_type, addr_of(spatter_ev:_field('mat_type')) - ebase)
    poke('uint32_t', base + OFF.off_ev_mat_state, addr_of(spatter_ev:_field('mat_state')) - ebase)
    poke('uint32_t', base + OFF.off_ev_amount, addr_of(spatter_ev:_field('amount')) - ebase)
    poke('int16_t', base + OFF.snow_mat_type, WATER)
    poke('int16_t', base + OFF.snow_mat_state, df.matter_state.Powder)
    poke('int32_t', base + OFF.snowy_from, SNOWY)
    if grass_ev then
        local gbase = addr_of(grass_ev)
        poke('uint64_t', base + OFF.grass_vtable, peek('uint64_t', gbase))
        poke('uint32_t', base + OFF.off_gev_plant, addr_of(grass_ev:_field('plant_index')) - gbase)
        poke('uint32_t', base + OFF.off_gev_amount, addr_of(grass_ev:_field('amount')) - gbase)
    else
        poke('uint64_t', base + OFF.grass_vtable, 0)   -- no grass on the map: no grass edges to draw
    end

    -- ---- SNOW_RAMPS.LUA'S TABLES ----
    local filled = fill_snow_tables(base, t)

    -- ---- THE SNOW'S BAKES HERE (15Z) ----
    -- The DLL paints the snow's bakes itself, from the textures' pixels (enabler.textures.raws, as the
    -- colour hands over), into the shared blanks, and tells each to update_snow, below. None told from
    -- before this start is taken.
    poke('uint64_t', base + OFF.col_raws, addr_of(df.global.enabler.textures:_field('raws')))
    poke('uint32_t', base + OFF.bake_here_tail, peek('uint32_t', base + OFF.bake_here_head))
    poke('uint32_t', base + OFF.snow_bake_here, 1)

    -- ---- ON ----
    reset_counts(base)
    poke('uint32_t', base + OFF.tables_ready, (peek('uint32_t', base + OFF.tables_ready) + 1) & 0xffffffff)
    sr.native_block = base
    sr.native_snow = true
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.enabled, 1)
    started_note = (common .. '\n'
        .. '  snow page %d textures; %d edging IDs with edge art, %d snowy edge pieces baked at start; %d snowy edges of more than one piece kept from earlier sessions (none: the DLL paints its bakes, 15Z).\n'
        .. '  snow_ramps.lua\'s tables took %.0f ms at start.')
        :format(filled.page, filled.edge_ids, filled.singles, filled.kept, tables_ms)
end

-- The DLL's counts, in words.
local function report(base)
    local hooked = peek('uint32_t', base + OFF.hooked) == 1
    local failed = peek('uint32_t', base + OFF.install_failed) == 1
    local chars = {}
    for i = 0, CLASS_BYTES - 1 do
        local c = peek('uint8_t', base + OFF.renderer_class + i)
        if c == 0 then break end
        chars[#chars + 1] = string.char(c)
    end
    local name = table.concat(chars)
    local function count(field) return peek('int64_t', base + OFF[field]) end
    local function us(field) return peek('double', base + OFF[field]) end
    local plans, applies = count('plans'), count('applies')

    if hooked then
        print(('native snow: hooked (%s, tidy_tile_cache)'):format(name ~= '' and name or 'class unread'))
    elseif failed then
        print("native snow: the DLL refused to hook; the reason is in detailed_weather_hook.log in DF's folder."
              .. ' Run "detailed_weather native stop" to give the snow back to snow_ramps.lua.')
    else
        print('native snow: not hooked yet (the DLL hooks on the frame after it starts)')
    end
    print(('  calls since start: per-frame %d, renderer %d'):format(count('prerender_calls'), count('tidy_calls')))
    print(('  frames worked out %d, written %d; the last walked %d screen columns, read %d map blocks and made %d records, %d of them snowy floors')
          :format(plans, applies, count('columns_last'), peek('uint32_t', base + OFF.blocks_last), count('records_last'), count('snowy_last')))
    print(('  drawn, summed over the frames: snowy ramps %d, snowy floors %d, trunks %d, snowy edges %d')
          :format(count('ramps_written'), count('floors_written'), count('trunks_written'), count('edges_written')))
    if applies > 0 then
        print(('  cells changed and put back before DF drew again: %.0f a frame on average'):format(count('cells_restored') / applies))
    end
    if plans > 0 then
        print(('  map blocks a frame on average: %.1f taken as kept, %.1f worked out afresh (the last frame %d and %d)')
              :format(count('blocks_kept') / plans, count('blocks_redone') / plans,
                      peek('uint32_t', base + OFF.blocks_kept_last), peek('uint32_t', base + OFF.blocks_redone_last)))
    end
    print(('  cells still showing snow_ramps.lua\'s drawing from before start, left as they were (summed over the frames): %d')
          :format(count('cells_waiting')))
    print(('  bakes painted by the DLL %d (%.1f us each on average; put off a frame, the frame\'s painting time used, %d); asked of snow_ramps.lua %d (%d of them as no blank was ready or a picture couldn\'t be read), made %d, couldn\'t be made %d; waits for room in the ring %d, for room in the list %d')
          :format(count('bakes_here'), count('bakes_here') > 0 and peek('double', base + OFF.bake_here_us_total) / count('bakes_here') or 0,
                  peek('uint32_t', base + OFF.bakes_here_over_time),
                  count('bakes_asked'), peek('uint32_t', base + OFF.bakes_here_put_off), count('bakes_done'), count('bakes_failed'),
                  peek('uint32_t', base + OFF.bake_ring_full), peek('uint32_t', base + OFF.bake_map_full)))
    if plans > 0 then
        print(('  working out the whole view: %.1f us a frame on average, worst %.1f us')
              :format(us('plan_us_total') / plans, us('plan_us_max')))
    end
    if applies > 0 then
        print(('  drawing it: %.1f us a frame on average, worst %.1f us')
              :format(us('apply_us_total') / applies, us('apply_us_max')))
    end
    print(('  frames not written because the viewports had changed since working out: %d'):format(count('apply_skipped')))
    print(('  frames where the view had moved between DF drawing it and the hook: %d'):format(count('view_moved')))
    print(('  memory the DLL holds beyond its fixed tables: %d KB; highest texture number %d')
          :format(peek('uint32_t', base + OFF.memory_kb), peek('int32_t', base + OFF.texpos_most)))
    local overflow, capped = peek('uint32_t', base + OFF.plan_overflow), count('events_capped')
    local full, out_of_range = peek('uint32_t', base + OFF.blocks_full), peek('uint32_t', base + OFF.tex_out_of_range)
    if overflow > 0 then print(('  plans that ran out of room for records or writes: %d'):format(overflow)) end
    if capped > 0 then print(('  blocks whose event list was too long to trust, read as no snow: %d'):format(capped)) end
    if full > 0 then print(('  blocks not read: too many in one frame: %d'):format(full)) end
    if out_of_range > 0 then print(('  textures past the DLL\'s texture map, not known as the snow\'s: %d'):format(out_of_range)) end
end

-- The DLL's colour counts, in words.
local function report_colour(base, col)
    local function count(field) return peek('int64_t', base + OFF[field]) end
    local frames = count('col_frames')
    print(('  frames swapped %d; the last looked at %d cells with something in them and gave %d a copy')
          :format(frames, peek('uint32_t', base + OFF.col_cells_last), peek('uint32_t', base + OFF.col_swapped_last)))
    if frames > 0 then
        print(('  a frame on average: %.0f cells given a copy, %.0f given the game\'s own back (underground, or no copy here)')
              :format(count('col_swapped') / frames, count('col_put_back') / frames))
        print(('  trees rustling in the wind: %.0f cells a frame on average given a frame of their loop')
              :format(count('sway_swapped') / frames))
        print(('  swapping: %.1f us a frame on average, worst %.1f us')
              :format(peek('double', base + OFF.col_us_total) / frames, peek('double', base + OFF.col_us_max)))
    end
    local nc = col and col.native_counts or {}
    print(('  questions asked %d, answered by colour.lua %d; copies in view checked by colour.lua %d')
          :format(count('col_asked'), nc.answered or 0, nc.checked or 0))
    print(('  copies in view checked by the DLL %d, %d of them changed (sent to colour.lua); pictures fingerprinted %d')
          :format(count('col_pics_checked'), count('col_pics_changed'), peek('uint32_t', base + OFF.col_pics_kept)))
    print(('  leafy pictures given rustle frames since the wind last changed: %d'):format((col and col.native_sway_next or 1) - 1))
    print(('  copies a question needed that were put off to a later frame (the frame\'s time was up): %d'):format(nc.put_off or 0))
    local done = peek('int64_t', base + OFF.paint_done)
    print(('  copies painted by the DLL %d (asked %d, %d of them with the dry or wet effects), refused %d; %.1f us painting a frame on average, worst %.1f us; pool or ring used up %d times; blanks ready %d')
          :format(done, nc.painted or 0, nc.full or 0, peek('uint32_t', base + OFF.paint_bad),
                  frames > 0 and peek('double', base + OFF.paint_us_total) / frames or 0, peek('double', base + OFF.paint_us_max),
                  nc.paint_busy or 0, col and #(col.native_pool or {}) or 0))
    print(('  cells waiting on an answer, summed over the frames: %d kept on last frame\'s copy, %d left as the game drew them')
          :format(count('col_held'), count('col_waiting')))
    -- (THE HELD SLOTS, layout 24: the holds only possible since a held copy follows its tile through a
    -- move, and the waits split by why nothing was held: the tile new to the view, or no copy held for it)
    print(('    kept through a move of the view %d; left as drawn: %d new to the view, %d shown last frame with no copy held')
          :format(count('col_held_moved'), count('col_wait_new'), count('col_wait_nohold')))
    -- (BY PICTURE, 15Z: a texture not answered yet given its picture's copy in the same frame)
    print(('    given the copy of their picture while asked about %d; screen copies filed by picture %d (the filing halved %d times)')
          :format(count('col_by_picture'), peek('uint32_t', base + OFF.col_pics_filed), peek('uint32_t', base + OFF.col_pics_halved)))
    -- (THE LOOK'S PIXEL WORK HERE, 15Z)
    print(('  the look\'s other pixel work painted by the DLL: %d textures with their alpha divided back out, %d grass lean frames, %d rustle frames (asked %d); tree pictures found wood, no frames, %d')
          :format(count('paint_unpremultiplied'), count('paint_leans'), count('paint_rustles'), nc.pixel_jobs or 0,
                  peek('uint32_t', base + OFF.canopy_wood)))
    -- (THE GRASS WAVE DRAWN HERE, 16A)
    local wf = peek('int64_t', base + OFF.wave_frames)
    local wave = col and col.native_wave_for
    local left_out, map_full = wave and wave.left_out or 0, peek('uint32_t', base + OFF.wave_map_full)
    print(('  the grass wave drawn by the DLL: %d frames, %.1f us a frame on average, worst %.1f us; %d cells a frame given their own lean or rustle frame (last frame %d); rustle frames asked of Lua %d (ring full %d times); grass pictures handed over %d%s')
          :format(wf, wf > 0 and peek('double', base + OFF.wave_us_total) / wf or 0, peek('double', base + OFF.wave_us_max),
                  wf > 0 and peek('int64_t', base + OFF.wave_written) // wf or 0, peek('uint32_t', base + OFF.wave_written_last),
                  peek('uint32_t', base + OFF.wave_wants), peek('uint32_t', base + OFF.wave_want_full),
                  peek('uint32_t', base + OFF.wave_slot_n),
                  (left_out > 0 or map_full > 0) and (' (frames left out: %d, the slots full; %d, the map full)'):format(left_out, map_full) or ''))
    local full, seen_full = peek('uint32_t', base + OFF.col_ring_full), peek('uint32_t', base + OFF.col_seen_full)
    if full > 0 or seen_full > 0 then
        print(('  rings full: questions put off %d times, copies not listed for checking %d times'):format(full, seen_full))
    end
end

-- ==========================================
-- RUNNING ON ITS OWN
-- ==========================================
running = running or false   -- the DLL is drawing the snow
held = held or false         -- stopped by `native stop`, until `native start`
why_not = why_not or nil     -- why the last start didn't go ahead
local next_try = 0           -- clock_s() of the next start tried
local TRY_EVERY = 5          -- seconds between starts tried that didn't go ahead

-- Hands the snow back to snow_ramps.lua: the DLL stops drawing (it puts the game's own drawing back,
-- a buffer a frame) and snow_ramps.lua plans and draws again from nothing.
local function hand_back()
    local base = block()
    if base then
        poke('uint32_t', base + OFF.enabled, 0)
        poke('uint32_t', base + OFF.snow_bake_here, 0)   -- (THE SNOW'S BAKES HERE: snow_ramps.lua's again)
    end
    local sr = snow_module()
    if sr then sr.native_snow = false end
    running = false
end

-- ==========================================
-- THE COLOUR, RUNNING ON ITS OWN (test 5)
-- ==========================================
col_running = col_running or false   -- the DLL is swapping colour's tiles
col_emptying = col_emptying or false -- started: waiting for the DLL to empty its tables
col_why_not = col_why_not or nil     -- why the last start didn't go ahead
col_note = col_note or nil           -- what the last start found, for the report
local col_next_try = 0

-- colour.lua, which makes the copies and answers the DLL. MODULES KEPT (grungeisdead's copy,
-- 2026-11-18): looked up once and kept. reqscript was called every frame for colour.lua and shade.lua
-- (update_colour, update_shade), and the native stage took 3.26 ms a frame against 0.27 before them
-- (details); a script changed on disk is only taken up after a full recycle anyway.
local colour_kept = nil
local function colour_module()
    if colour_kept then return colour_kept end
    local ok, col = pcall(reqscript, 'internal/detailed_weather/colour')
    if not ok or not col then return nil end
    colour_kept = col
    return col
end

-- Views of the DLL's colour tables and rings, for colour.lua (its native_view): DFHack's primitive
-- references take numeric indices, so view[i] is the i-th value from the address.
local function colour_view(base)
    local function at(t, off) return df.reinterpret_cast(t, base + off) end
    return {
        link = df.reinterpret_cast('int32_t', peek('uint64_t', base + OFF.col_link)),
        flags = df.reinterpret_cast('uint8_t', peek('uint64_t', base + OFF.col_flags)),
        tex_map = peek('uint32_t', base + OFF.col_tex_map),
        ring = COL_RING,
        req_head = at('uint32_t', OFF.col_req_head), req_tail = at('uint32_t', OFF.col_req_tail),
        q32 = at('int32_t', OFF.col_req), q8 = at('uint8_t', OFF.col_req),
        seen_head = at('uint32_t', OFF.col_seen_head), seen_tail = at('uint32_t', OFF.col_seen_tail),
        seen = at('int32_t', OFF.col_seen),
        period = at('uint32_t', OFF.col_period),
        -- (SWAY)
        sway_playing = at('int32_t', OFF.sway_playing), sway_waves = at('int32_t', OFF.sway_waves),
        sway_reset = at('uint32_t', OFF.sway_reset), sway_reset_done = at('uint32_t', OFF.sway_reset_done),
        sway_ux = at('double', OFF.sway_ux), sway_uy = at('double', OFF.sway_uy),
        sway_of = df.reinterpret_cast('uint16_t', peek('uint64_t', base + OFF.sway_of)),
        sway_tex = df.reinterpret_cast('int32_t', peek('uint64_t', base + OFF.sway_tex)),
        sway_max = peek('uint32_t', base + OFF.sway_max),
        sway_phases = peek('uint32_t', base + OFF.sway_phases),
        -- (PICTURES CHECKED HERE: originals colour.lua found unchanged, for the DLL to check from then on)
        verified_head = at('uint32_t', OFF.col_verified_head), verified_tail = at('uint32_t', OFF.col_verified_tail),
        verified = at('int32_t', OFF.col_verified),
        -- (PAINTING: colour.lua's native_paint)
        paint_head = at('uint32_t', OFF.paint_head), paint_tail = at('uint32_t', OFF.paint_tail),
        paint_base = base + OFF.paint, paint_ring = PAINT_RING,
        -- (CHANGES OF LOOK TIMED: the DLL's painting and swapping time, summed in us)
        paint_us = at('double', OFF.paint_us_total), col_us = at('double', OFF.col_us_total),
        -- (THE RUSTLE PAINTED HERE, 16A: the clump layout, handed over once a start)
        rustle_of = at('uint8_t', OFF.rustle_of), rustle_of_ready = at('uint32_t', OFF.rustle_of_ready),
        -- (THE GRASS WAVE DRAWN HERE, 16A: colour.lua's native_wave)
        wave_on = at('uint32_t', OFF.wave_on), wave_gen = at('uint32_t', OFF.wave_gen),
        wave_gen_done = at('uint32_t', OFF.wave_gen_done), wave_built = at('uint32_t', OFF.wave_built),
        wave_slot_n = at('uint32_t', OFF.wave_slot_n),
        wave_x1 = at('int32_t', OFF.wave_x1), wave_y1 = at('int32_t', OFF.wave_y1),
        wave_cols = at('int32_t', OFF.wave_cols), wave_rows = at('int32_t', OFF.wave_rows),
        wave_playing = at('int32_t', OFF.wave_playing),
        wave_cx = at('double', OFF.wave_cx), wave_cy = at('double', OFF.wave_cy), wave_reach = at('double', OFF.wave_reach),
        wave_ux = at('double', OFF.wave_ux), wave_uy = at('double', OFF.wave_uy), wave_clock = at('double', OFF.wave_clock),
        wave_slots = df.reinterpret_cast('int32_t', peek('uint64_t', base + OFF.wave_slots)),
        wave_slots_most = peek('uint32_t', base + OFF.wave_slots_most),
        wave_hist_head = at('uint32_t', OFF.wave_hist_head), wave_hist = at('double', OFF.wave_hist),
        wave_want_head = at('uint32_t', OFF.wave_want_head), wave_want_tail = at('uint32_t', OFF.wave_want_tail),
        wave_want = at('uint32_t', OFF.wave_want),
    }
end

-- SWAY: which tiletypes are a tree's branches or twigs, where the leaves rustle (colour.lua's
-- canopy_tiletype: material TREE, shape BRANCH or TWIG).
local function fill_canopy(base)
    local shape, material = df.tiletype_shape, df.tiletype_material
    local last = math.min(df.tiletype._last_item, TT_TABLE - 1)
    local n = 0
    for tt = 0, TT_TABLE - 1 do
        local canopy = 0
        if tt <= last and df.tiletype[tt] then
            local a = df.tiletype.attrs[tt]
            if a.material == material.TREE and (a.shape == shape.BRANCH or a.shape == shape.TWIG) then canopy, n = 1, n + 1 end
        end
        poke('uint8_t', base + OFF.col_tt + tt, canopy)
    end
    return n
end

-- Starts the colour: the addresses filled, and the DLL asked to empty its tables (texture numbers
-- can mean other pictures since its last start). colour.lua is told once that's done (update).
local function colour_start(base)
    local col = colour_module()
    if not col or type(col.native_begin) ~= 'function' then
        qerror('colour.lua has no NATIVE COLOUR yet: apply its pairs first')
    end
    poke('uint32_t', base + OFF.col_enabled, 0)
    col_note = fill_common(base)
    col_note = col_note .. (' %d tiletypes are branches or twigs.'):format(fill_canopy(base))
    poke('uint32_t', base + OFF.col_depths, col.native_depths())
    -- (PICTURES CHECKED HERE: where the DLL finds each texture's pixels, as grass.lua's surface_of does)
    poke('uint64_t', base + OFF.col_raws, addr_of(df.global.enabler.textures:_field('raws')))
    for _, name in ipairs({'col_pics_checked', 'col_pics_changed'}) do poke('int64_t', base + OFF[name], 0) end
    poke('int32_t', base + OFF.sway_playing, -1)
    poke('int64_t', base + OFF.sway_swapped, 0)
    for _, name in ipairs({'col_frames', 'col_swapped', 'col_put_back', 'col_held', 'col_asked', 'col_waiting',
                           'col_wait_new', 'col_wait_nohold', 'col_held_moved'}) do
        poke('int64_t', base + OFF[name], 0)
    end
    poke('double', base + OFF.col_us_total, 0)
    poke('double', base + OFF.col_us_max, 0)
    poke('uint32_t', base + OFF.col_ring_full, 0)
    poke('uint32_t', base + OFF.col_seen_full, 0)
    -- (PAINTING: nothing left in the ring from before)
    poke('uint32_t', base + OFF.paint_head, peek('uint32_t', base + OFF.paint_tail))
    poke('int64_t', base + OFF.paint_done, 0)
    poke('double', base + OFF.paint_us_total, 0)
    poke('double', base + OFF.paint_us_max, 0)
    poke('uint32_t', base + OFF.paint_bad, 0)
    poke('uint32_t', base + OFF.col_reset, (peek('uint32_t', base + OFF.col_reset) + 1) & 0xffffffff)
    poke('uint32_t', base + OFF.install, 1)
    col_emptying = true
end

-- Hands the colour back to colour.lua, which plans and swaps again from nothing.
local function colour_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.col_enabled, 0) end
    local col = colour_module()
    if col and col.native_end then col.native_end() end
    col_running, col_emptying = false, false
end

-- Every frame (update): the colour started, handed back or turned on once the DLL's tables are empty.
local function update_colour()
    local col = colour_module()
    local wanted = col and col.mode ~= 'off' and col.screen_mode ~= 'off' and not held
    if not wanted then
        if col_running or col_emptying then colour_hand_back() end
        return
    end
    if col_emptying then
        local base = block()
        if not base then col_emptying = false return end
        if peek('uint32_t', base + OFF.col_reset_done) ~= peek('uint32_t', base + OFF.col_reset) then return end
        if peek('uint32_t', base + OFF.hooked) ~= 1 then return end   -- (hooked on the frame after install)
        col.native_begin(colour_view(base))
        poke('uint32_t', base + OFF.col_enabled, 1)
        col_running, col_emptying = true, false
        return
    end
    if col_running or not dfhack.isMapLoaded() or clock_s() < col_next_try then return end
    col_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then col_why_not = why return end
    local ok, problem = pcall(colour_start, base)
    if ok then col_why_not = nil else col_why_not = tostring(problem) end
end

-- ==========================================
-- THE SHADE, RUNNING ON ITS OWN (test 6)
-- ==========================================
shade_running = shade_running or false   -- the DLL is drawing the shade
shade_why_not = shade_why_not or nil     -- why the last start didn't go ahead
local shade_next_try = 0

-- shade.lua, which makes the shade tiles (MODULES KEPT, as colour.lua's).
local shade_kept = nil
local function shade_module()
    if shade_kept then return shade_kept end
    local ok, sh = pcall(reqscript, 'internal/detailed_weather/shade')
    if not ok or not sh then return nil end
    shade_kept = sh
    return sh
end

-- Starts the shade: the addresses filled, every shade tile made by shade.lua and handed over.
local function shade_start(base)
    local sh = shade_module()
    if not sh or type(sh.native_tables) ~= 'function' then
        qerror('shade.lua has no NATIVE SHADE yet: apply its pairs first')
    end
    poke('uint32_t', base + OFF.shade_enabled, 0)
    fill_common(base)
    local list = sh.native_tables()
    if #list ~= SHADE_N then qerror(('shade.lua gave %d shade tiles, the DLL is built for %d'):format(#list, SHADE_N)) end
    for k = 1, SHADE_N do poke('int32_t', base + OFF.shade_tex + (k - 1) * 4, list[k]) end
    for _, name in ipairs({'shade_frames', 'shade_written'}) do poke('int64_t', base + OFF[name], 0) end
    poke('double', base + OFF.shade_us_total, 0)
    poke('double', base + OFF.shade_us_max, 0)
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.shade_enabled, 1)
    sh.native_shade = true
    shade_running = true
end

-- Hands the shade back to shade.lua, which plans and draws it again from nothing.
local function shade_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.shade_enabled, 0) end
    local sh = shade_module()
    if sh then sh.native_shade, sh.plan = false, nil end
    shade_running = false
end

-- Every frame (update): the shade started or handed back.
local function update_shade()
    local sh = shade_module()
    local wanted = sh and sh.mode == 'on' and not held
    if not wanted then
        if shade_running then shade_hand_back() end
        return
    end
    if shade_running or not dfhack.isMapLoaded() or clock_s() < shade_next_try then return end
    shade_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then shade_why_not = why return end
    local ok, problem = pcall(shade_start, base)
    if ok then shade_why_not = nil else shade_why_not = tostring(problem) end
end

-- The DLL's shade counts, in words.
local function report_shade(base)
    local frames = peek('int64_t', base + OFF.shade_frames)
    print(('  frames drawn %d; the last shaded %d cells'):format(frames, peek('uint32_t', base + OFF.shade_cells_last)))
    if frames > 0 then
        print(('  a frame on average: %.0f cells shaded, %.1f us, worst %.1f us')
              :format(peek('int64_t', base + OFF.shade_written) / frames,
                      peek('double', base + OFF.shade_us_total) / frames, peek('double', base + OFF.shade_us_max)))
    end
end

-- ==========================================
-- MURKY WATER, RUNNING ON ITS OWN (test 14)
-- ==========================================
murky_running = murky_running or false   -- the DLL is drawing murky water
murky_why_not = murky_why_not or nil
local murky_next_try = 0
local murky_kept = nil
local function murky_module()
    if murky_kept then return murky_kept end
    local ok, m = pcall(reqscript, 'internal/detailed_weather/murky')
    if not ok or not m then return nil end
    murky_kept = m
    return m
end

-- MURKY: EDGES OVER THE TINT (grungeisdead's copy, 2026-11-19). Above the water the tint covered the
-- banks' grass edges that overhang it, so the DLL paints the tint with those pieces laid back over it,
-- once for each combination, into blank textures kept ready here. It needs each edge piece's pixels
-- and each tint cell's, and to know the map's grass (the corners: decide_edges' rule).
local MURKY_CORNERS = 1   -- 0: only the side pieces (the floor_flag's); 1: the corners the game adds too
local murky_grass = nil
local function grass_module()
    if murky_grass then return murky_grass end
    local ok, g = pcall(reqscript, 'internal/detailed_weather/grass')
    if ok and g then murky_grass = g end
    return murky_grass
end
local murky_blank_pixels = nil   -- 1024 zeros, made once
murky_blanks_made = murky_blanks_made or {}   -- their handles, kept so the textures stay loaded
-- BLANKS AHEAD (test 14H): a new view could ask for hundreds of combinations at once, and making a
-- blank (createTile) is slow, so the edges took a couple of seconds to appear. Blanks are made ahead
-- into this pool in the background, and the DLL's ring is refilled from it each frame (only writes).
local MURKY_POOL = 512          -- blanks kept ready
local MURKY_MAKE_MS = 1         -- ms a frame making blanks
local MURKY_MAKE_BUSY_MS = 8    -- ms a frame while the ring ran dry (cells waiting)
murky_pool = murky_pool or {}   -- {texpos, address}
local murky_waits_seen = 0

-- Each edge piece's pixels as the banks show them: the look's copy where colour.lua has one (the game
-- draws edges through the tables it points at the copies), else the game's own. Done again at each
-- new look (update_murky), the DLL's bakes forgotten with them.
local murky_edges = nil      -- the edge art (snow_ramps.lua: all_edge_art), by edging ID and piece name
local murky_look_key = nil   -- the look the pieces were last read in
murky_reads = {}             -- the last few times they were read (the report)
local function murky_edge_pixels(base, g)
    local col = colour_module and colour_module()
    local copy_of = col and type(col.copy_of) == 'function' and col.copy_of or function(t) return t end
    for id = 0, 255 do
        local art = murky_edges and murky_edges[id]
        for n, name in ipairs(EDGE_NAMES) do
            local texpos = art and art[name] or 0
            local shown = texpos > 0 and copy_of(texpos) or 0
            poke('uint64_t', base + OFF.edge_addr + (id * 8 + n - 1) * 8,
                 shown > 0 and (g.original_address(shown) or g.original_address(texpos)) or 0)
        end
    end
    local _, key = nil, nil
    if col and type(col.shown_look) == 'function' then _, key = col.shown_look() end
    murky_look_key = key or false
    -- (MURKY: FRAME BY FRAME: when the pieces were read, and in which look)
    murky_reads[#murky_reads + 1] = ('frame %d: %s'):format(peek('int64_t', base + OFF.murky_frames), tostring(key or 'no look yet'))
    if #murky_reads > 10 then table.remove(murky_reads, 1) end
    poke('uint32_t', base + OFF.murky_bake_reset, (peek('uint32_t', base + OFF.murky_bake_reset) + 1) & 0xffffffff)
end

-- The edge art and grass tables the corners need, and every piece's pixels. The same values the snow
-- writes (fill_snow_tables, start), so writing them again while the snow runs changes nothing.
local function fill_murky_edges(base, g)
    local sr = snow_module()
    murky_edges = sr and type(sr.all_edge_art) == 'function' and sr.all_edge_art() or {}
    for id = 0, 255 do
        local art = murky_edges[id]
        for n, name in ipairs(EDGE_NAMES) do
            poke('int32_t', base + OFF.edge_art + (id * 8 + n - 1) * 4, art and art[name] or 0)
        end
    end
    murky_edge_pixels(base, g)
    for index, plant in ipairs(df.global.world.raws.plants.all) do
        if index >= PLANTS then break end
        local custom = plant.texpos[5]   -- its CUSTOM_EDGING minus one, or -1 (snow_ramps.lua: native_tables)
        poke('uint8_t', base + OFF.plant_edging + index, math.min(custom >= 0 and custom + 10 or 1, 255))
    end
    local grass_ev = any_event(df.block_square_event_grassst)
    if grass_ev then
        local gbase = addr_of(grass_ev)
        poke('uint64_t', base + OFF.grass_vtable, peek('uint64_t', gbase))
        poke('uint32_t', base + OFF.off_gev_plant, addr_of(grass_ev:_field('plant_index')) - gbase)
        poke('uint32_t', base + OFF.off_gev_amount, addr_of(grass_ev:_field('amount')) - gbase)
    end
end

-- The pool topped up for at most `ms`, then the ring filled from it. A blank is never drawn before the
-- DLL paints it, so the renderer reads the painted pixels on its first draw (as colour.lua's pool).
-- (14K: the pool first. At a start the pool is empty, so filling the ring first left it empty for the
-- first frame, and the snow's start then held that frame, edges missing, on screen for seconds.)
local function murky_fill_blanks(base, ms)
    local g = grass_module()
    if not g then return end
    if not murky_blank_pixels then
        murky_blank_pixels = {}
        for n = 1, 32 * 32 do murky_blank_pixels[n] = 0 end
    end
    -- the pool made up ahead
    local ends = clock_ms() + ms
    while #murky_pool < MURKY_POOL and clock_ms() < ends do
        local handle = dfhack.textures.createTile(murky_blank_pixels, 32, 32)
        local texpos = handle and dfhack.textures.getTexposByHandle(handle)
        local address = texpos and g.original_address(texpos)
        if not address then break end   -- (padded rows: none painted, the plain tint stays)
        murky_blanks_made[#murky_blanks_made + 1] = handle
        _G.detailed_weather_made = _G.detailed_weather_made or {}
        _G.detailed_weather_made[texpos] = true   -- (PATHS: Detailed Weather's own, never swapped by the colour)
        murky_pool[#murky_pool + 1] = {texpos = texpos, address = address}
    end
    -- the ring from the pool: writes only
    local head = peek('uint32_t', base + OFF.murky_blank_head)
    local tail = peek('uint32_t', base + OFF.murky_blank_tail)
    while ((head - tail) & 0xffffffff) < MURKY_BLANKS and #murky_pool > 0 do
        local b = table.remove(murky_pool)
        local slot = head % MURKY_BLANKS
        poke('int32_t', base + OFF.murky_blank_tex + slot * 4, b.texpos)
        poke('uint64_t', base + OFF.murky_blank_addr + slot * 8, b.address)
        head = (head + 1) & 0xffffffff
        poke('uint32_t', base + OFF.murky_blank_head, head)   -- (last: the DLL takes it only once filled)
    end
end

-- MURKY: THE HAZE (tests 15D to 15G). Since 15G the DLL draws the tint on the level just above the
-- water, which the game then hazes with the rest of that cell, so nothing is laid here. (15F's probe
-- found no haze because it never read the interface layer, where the game lays it: FOG OVER WATER,
-- below.) THE PROBE: the fields of one cell over murky water on each level, recorded by the DLL for
-- the report (kept for questions like that one).
-- THE PROBE's fields: the name, and 8 for an 8-byte one (15H: interface in vehicle's place, so the
-- probe shows the game's haze)
local PROBE_FIELDS = {{'background'}, {'floor_flag', 8}, {'background_two'}, {'liquid_flag'}, {'spatter_flag'},
                      {'spatter'}, {'ramp_flag', 8}, {'shadow_flag'}, {'building_one'}, {'item'}, {'interface'},
                      {'building_two'}, {'high_flow'}, {'top_shadow'}, {'signpost'}, {'designation'}}
local function fill_probe(base)
    local vp = df.global.gps.main_viewport
    local vbase = addr_of(vp)
    for f, field in ipairs(PROBE_FIELDS) do
        local ok, off = pcall(function() return addr_of(vp:_field('screentexpos_' .. field[1])) - vbase end)
        poke('uint32_t', base + OFF.off_probe + (f - 1) * 4, ok and (off | ((field[2] or 4) == 8 and (8 << 24) or 0)) or 0)
    end
    poke('uint32_t', base + OFF.probe_ask, (peek('uint32_t', base + OFF.probe_ask) + 1) & 0xffffffff)
end

-- A texture's page and place on it, in words ('MULTILEVEL_OVERLAY 3,3'; for colour.lua's copy, its
-- original's), or its number.
local function texture_name(texpos)
    -- (FOG OVER WATER) the game's hazes 1 to 7 are made at load, on no page: named by their place
    local indices = df.global.gps.texture_indices1
    for k = 1, 7 do
        if indices[k] == texpos then return ('the game\'s haze %d (ground %d levels down)'):format(k, k + 1) end
    end
    local col = colour_module and colour_module()
    local original = col and type(col.original_of) == 'function' and col.original_of(texpos) or texpos
    if original ~= texpos then return texture_name(original) .. ' (colour.lua\'s copy)' end
    for _, page in ipairs(df.global.texture.page) do
        for k, t in ipairs(page.texpos) do
            if t == texpos then
                local w = page.page_dim_x > 0 and page.page_dim_x or 1
                return ('%s %d,%d'):format(page.token, k % w, k // w)
            end
        end
    end
    return tostring(texpos)
end

-- Starts murky water: the addresses filled, the bits and murky.lua's 16 tint textures handed over.
local function murky_start(base)
    local m = murky_module()
    if not m or type(m.native_textures) ~= 'function' then qerror('murky.lua has no NATIVE MURKY yet: apply its pairs first') end
    local tex = m.native_textures()
    if not tex or #tex < 16 then qerror('murky.lua has not loaded its art yet') end
    poke('uint32_t', base + OFF.murky_enabled, 0)
    fill_common(base)
    poke('uint32_t', base + OFF.stagnant_mask, designation_mask('water_stagnant', 1 << 30))
    poke('uint32_t', base + OFF.magma_mask, designation_mask('liquid_type', 1 << 21))
    poke('uint32_t', base + OFF.murky_depths, 8)   -- (15E: to 8 levels down, as the DLL goes; murky.lua: 3)
    -- (THE PROBE)
    poke('uint64_t', base + OFF.haze_air_addr, 0)   -- (15F's haze, no longer laid by the DLL)
    poke('int32_t', base + OFF.probe_d, 0)
    fill_probe(base)
    for k = 1, 16 do poke('int32_t', base + OFF.murky_tex + (k - 1) * 4, tex[k] or 0) end
    -- EDGES OVER THE TINT: the pieces, the tint cells' pixels, the old bakes forgotten, blanks given
    local g = grass_module()
    if g then
        fill_murky_edges(base, g)
        for k = 1, 16 do
            poke('uint64_t', base + OFF.murky_tint_addr + (k - 1) * 8, tex[k] and g.original_address(tex[k]) or 0)
        end
    end
    poke('uint32_t', base + OFF.murky_corners, MURKY_CORNERS)
    poke('uint32_t', base + OFF.murky_bake_reset, (peek('uint32_t', base + OFF.murky_bake_reset) + 1) & 0xffffffff)   -- (old bakes forgotten)
    poke('uint32_t', base + OFF.murky_blank_head, peek('uint32_t', base + OFF.murky_blank_tail))   -- (the last start's blanks dropped)
    murky_pool, murky_waits_seen = {}, 0   -- (and the pool's: another world's textures)
    poke('uint32_t', base + OFF.murky_empty_pieces, 0)
    for _, name in ipairs({'murky_baked'}) do poke('int64_t', base + OFF[name], 0) end
    poke('uint32_t', base + OFF.murky_bake_waits, 0)
    if g then murky_fill_blanks(base, 50) end
    for _, name in ipairs({'murky_frames', 'murky_written'}) do poke('int64_t', base + OFF[name], 0) end
    poke('double', base + OFF.murky_us_total, 0)
    poke('double', base + OFF.murky_us_max, 0)
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.murky_enabled, 1)
    m.native_murky = true
    murky_running = true
end

local function murky_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.murky_enabled, 0) end
    local m = murky_module()
    if m then m.native_murky = false end
    murky_running = false
end

local function update_murky()
    local m = murky_module()
    local wanted = m and m.mode == 'on' and not held
    if not wanted then
        if murky_running then murky_hand_back() end
        return
    end
    if murky_running then
        local base = block()
        if not base then return end
        -- (EDGES OVER THE TINT: more time making blanks while cells wait for them; 15Z: the worn paths'
        -- new paintings too, which take theirs from this ring)
        local waits = (peek('uint32_t', base + OFF.murky_bake_waits) + peek('uint32_t', base + OFF.paths_no_blank)) & 0xffffffff
        murky_fill_blanks(base, waits ~= murky_waits_seen and MURKY_MAKE_BUSY_MS or MURKY_MAKE_MS)
        murky_waits_seen = waits
        -- a new look: the pieces read again in its colours
        local col = colour_module and colour_module()
        local key = false
        if col and type(col.shown_look) == 'function' then local _, k = col.shown_look() key = k or false end
        local g = grass_module()
        if g and murky_edges and key ~= murky_look_key then murky_edge_pixels(base, g) end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < murky_next_try then return end
    -- (14L: murky.lua loads its art in its own stage, which comes after this one in the overlay, so the
    -- first frame's try always failed and the next came TRY_EVERY (5 s) later, murky.lua drawing the
    -- tint itself meanwhile, over the edges. Now tried each frame until the art is loaded: a frame.)
    if type(m.native_textures) == 'function' and not m.native_textures() then return end
    murky_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then murky_why_not = why return end
    local ok, problem = pcall(murky_start, base)
    if ok then murky_why_not = nil else murky_why_not = tostring(problem) end
end

local function report_murky(base)
    local frames = peek('int64_t', base + OFF.murky_frames)
    local d = {}
    for k = 0, 3 do d[#d + 1] = peek('uint32_t', base + OFF.murky_drawn + k * 4) end
    print(('  frames drawn %d; the last tinted %s cells by level down (the last: 3 and more)'):format(frames, table.concat(d, '/')))
    print(('  tints with the banks\' edges over them: %d made; %d cells drawn plain for a frame while waiting'):format(
          peek('int64_t', base + OFF.murky_baked), peek('uint32_t', base + OFF.murky_bake_waits)))
    if frames > 0 then
        print(('  %.1f us a frame on average, worst %.1f us'):format(peek('double', base + OFF.murky_us_total) / frames,
              peek('double', base + OFF.murky_us_max)))
    end
    print(('  edge pieces painted in with no visible pixel: %d'):format(peek('uint32_t', base + OFF.murky_empty_pieces)))
    -- (BRANCHES SEEN THROUGH, tests 15P and 15Q: stagnant water the game shows through a tree's branches or leaves:
    -- tinted, unless a branch or leaves are on the level just above it, where the tint's layer may hold the branch)
    print(('  stagnant water seen through branches or leaves: %d tinted the last frame (%d summed); %d left, a branch or leaves just above the water')
          :format(peek('uint32_t', base + OFF.murky_under_branch_last), peek('int64_t', base + OFF.murky_under_branch),
                  peek('uint32_t', base + OFF.murky_branch_above_last)))
    print('  the levels\' haze: the game\'s own (the tint is drawn on the level just above the water and hazed with it; fog over water, below, sets that haze to the surface\'s level)')
    -- (THE PROBE: one cell, recorded once per report; asked again for the next)
    local pd = peek('int32_t', base + OFF.probe_d)
    if pd > 0 and peek('uint32_t', base + OFF.probe_done) == peek('uint32_t', base + OFF.probe_ask) then
        -- (BRANCHES PROBED: the levels between that are a tree's branches or leaves, if any)
        local through, levels = peek('uint32_t', base + OFF.probe_through), {}
        for k = 0, 31 do if through & (1 << k) ~= 0 then levels[#levels + 1] = tostring(k) end end
        print(('  the probe: cell %d,%d, its water %d levels down%s; each level\'s fields there (texture names where they are one):'):format(
              peek('int32_t', base + OFF.probe_x), peek('int32_t', base + OFF.probe_y), pd,
              #levels > 0 and (', seen through branches or leaves on the level(s) ' .. table.concat(levels, ', ') .. ' down') or ''))
        for level = 0, math.min(pd, 7) do
            local parts = {}
            for f, field in ipairs(PROBE_FIELDS) do
                local v = peek('uint64_t', base + OFF.probe_val + (level * 16 + f - 1) * 8)
                if v ~= 0 then
                    local texture = (field[2] or 4) == 4 and not field[1]:find('flag$') and v < 0x80000000
                    parts[#parts + 1] = field[1] .. '=' .. (texture and texture_name(v) or ('0x%x'):format(v))
                end
            end
            print(('    %d down%s: %s'):format(level, level == pd and ' (the water)' or '', #parts > 0 and table.concat(parts, ', ') or 'nothing'))
        end
    else
        print('  the probe: no cell of water under branches or leaves, or two or more levels down, seen since the last report (look down on some, then ask again)')
    end
    poke('uint32_t', base + OFF.probe_ask, (peek('uint32_t', base + OFF.probe_ask) + 1) & 0xffffffff)
    print('  edge pieces read (the old bakes forgotten) at: ' .. (#murky_reads > 0 and table.concat(murky_reads, '; ') or 'never'))
    -- MURKY: FRAME BY FRAME (test 14I): the frames whose numbers changed, oldest first
    local head = peek('uint32_t', base + OFF.murky_hist_head)
    local first = math.max(0, head - 40)
    if head > first then
        print('  murky frame by frame (a line each time the numbers changed), cells seen from above:')
        print('    frame: view x,y,z (levels DF shows) | tinted | with haze or edges | given them | plain, bakes forgotten | plain, waiting')
    end
    for n = first, head - 1 do
        local at = base + OFF.murky_hist + (n % 128) * 32
        local v = {}
        for k = 0, 7 do v[k] = peek('uint32_t', at + k * 4) end
        -- (15W: x's top 16 bits the levels DF shows, y's the view's level)
        print(('    %d: %d,%d,%d (%d) | %d | %d | %d | %d | %d'):format(v[0], v[1] & 0xffff, v[2] & 0xffff, v[2] >> 16,
              v[1] >> 16, v[3], v[4], v[5], v[6], v[7]))
    end
end

-- ==========================================
-- WORN PATHS, DRAWN BY THE DLL (test 15B)
-- ==========================================
-- detailed_weather_dll.cpp: PATHS. The DLL reads the grass, works out each worn tile's track and
-- wash as paths.lua does, paints them into blanks from the murky edges' ring (murky_fill_blanks
-- tops it up for both) and swaps them in. Here, each frame: the soil to draw (paths.lua picks it
-- from the textures the DLL counts on bare soil in view) and where each grass picture's steady
-- pixels are (paths.lua: native_base), for the textures the DLL asks about.
paths_running = paths_running or false
paths_why_not = paths_why_not or nil
local paths_next_try = 0
local paths_kept = nil
local paths_soil_asked, paths_soil_next = false, 0
local paths_no_blank_seen = 0   -- (15Z: the DLL's count when last seen, for topping the ring up faster)
local PATHS_RING = 256     -- the DLL's paths rings (paths_q, paths_a)
local PATHS_DEPTH = 4      -- levels below the view's that get paths (paths.lua: MOST_DEPTH)
local function paths_module()
    if paths_kept then return paths_kept end
    local ok, m = pcall(reqscript, 'internal/detailed_weather/paths')
    if not ok or not m then return nil end
    paths_kept = m
    return m
end

-- The DLL's tiletype table for paths (paths.lua: kind_of): 1 a grass floor, 2 a bare soil floor.
local function fill_paths_kinds(base)
    local shape, material = df.tiletype_shape, df.tiletype_material
    local grassy = {[material.GRASS_LIGHT] = true, [material.GRASS_DARK] = true,
                    [material.GRASS_DRY] = true, [material.GRASS_DEAD] = true}
    local last = math.min(df.tiletype._last_item, TT_TABLE - 1)
    for tt = 0, TT_TABLE - 1 do
        local k = 0
        if tt <= last and df.tiletype[tt] then
            local a = df.tiletype.attrs[tt]
            if a.shape == shape.FLOOR then k = grassy[a.material] and 1 or a.material == material.SOIL and 2 or 0 end
        end
        poke('uint8_t', base + OFF.paths_kind + tt, k)
    end
end

-- Starts the paths: the addresses and tables filled, the DLL's lists forgotten, blanks given.
local function paths_start(base)
    local pm = paths_module()
    if not pm or type(pm.native_base) ~= 'function' then qerror('paths.lua has no NATIVE PATHS yet: apply its pairs first') end
    poke('uint32_t', base + OFF.paths_enabled, 0)
    fill_common(base)
    fill_paths_kinds(base)
    -- the grass events' vtable and fields (as murky's corners and the snow read them)
    local grass_ev = any_event(df.block_square_event_grassst)
    if grass_ev then
        local gbase = addr_of(grass_ev)
        poke('uint64_t', base + OFF.grass_vtable, peek('uint64_t', gbase))
        poke('uint32_t', base + OFF.off_gev_plant, addr_of(grass_ev:_field('plant_index')) - gbase)
        poke('uint32_t', base + OFF.off_gev_amount, addr_of(grass_ev:_field('amount')) - gbase)
    end
    poke('uint32_t', base + OFF.paths_depths, PATHS_DEPTH)
    poke('uint64_t', base + OFF.paths_soil_addr, 0)   -- (nothing drawn until the soil is found)
    for _, name in ipairs({'paths_plan_reset', 'paths_reset'}) do
        poke('uint32_t', base + OFF[name], (peek('uint32_t', base + OFF[name]) + 1) & 0xffffffff)
    end
    for _, name in ipairs({'paths_frames', 'paths_baked', 'paths_blocks_total', 'paths_plans'}) do poke('int64_t', base + OFF[name], 0) end
    for _, name in ipairs({'paths_plan_us_total', 'paths_plan_us_max', 'paths_draw_us_total', 'paths_draw_us_max'}) do poke('double', base + OFF[name], 0) end
    for _, name in ipairs({'paths_waits', 'paths_q_full'}) do poke('uint32_t', base + OFF[name], 0) end
    paths_soil_asked, paths_soil_next = false, 0
    pm.native_start()
    murky_fill_blanks(base, 20)
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.paths_enabled, 1)
    pm.native_paths = true
    paths_running = true
end

local function paths_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.paths_enabled, 0) end
    local pm = paths_module()
    if pm then pm.native_paths = false end
    paths_running = false
end

local function update_paths()
    local pm = paths_module()
    local wanted = pm and pm.mode == 'on' and not held
    if not wanted then
        if paths_running then paths_hand_back() end
        return
    end
    if paths_running then
        local base = block()
        if not base then return end
        -- (else topped up there; 15Z: faster while new paintings wait for a blank)
        if not murky_running then
            local waits = peek('uint32_t', base + OFF.paths_no_blank)
            murky_fill_blanks(base, waits ~= paths_no_blank_seen and MURKY_MAKE_BUSY_MS or MURKY_MAKE_MS)
            paths_no_blank_seen = waits
        end
        -- the soil: the DLL counts what's on bare soil in view when asked, paths.lua picks from it
        if not paths_soil_asked and clock_s() >= paths_soil_next and pm.native_soil_wanted() then
            poke('uint32_t', base + OFF.paths_soil_ask, (peek('uint32_t', base + OFF.paths_soil_ask) + 1) & 0xffffffff)
            paths_soil_asked = true
        end
        if paths_soil_asked and peek('uint32_t', base + OFF.paths_soil_done) == peek('uint32_t', base + OFF.paths_soil_ask) then
            local seen = {}
            for k = 0, 3 do seen[#seen + 1] = peek('int32_t', base + OFF.paths_soil_seen + k * 4) end
            local addr = pm.native_soil(seen)
            if addr then
                poke('uint64_t', base + OFF.paths_soil_addr, addr)
                poke('uint32_t', base + OFF.paths_reset, (peek('uint32_t', base + OFF.paths_reset) + 1) & 0xffffffff)
            else
                paths_soil_next = clock_s() + 1   -- (none to draw yet: asked again in a second)
            end
            paths_soil_asked = false
        end
        -- the DLL's questions: a grass texture's steady pixels, at most 1 ms a frame
        local head, tail = peek('uint32_t', base + OFF.paths_q_head), peek('uint32_t', base + OFF.paths_q_tail)
        local ends = clock_s() + 0.001
        while tail ~= head and clock_s() < ends do
            local a_head = peek('uint32_t', base + OFF.paths_a_head)
            if ((a_head - peek('uint32_t', base + OFF.paths_a_tail)) & 0xffffffff) >= PATHS_RING then break end
            local t = peek('int32_t', base + OFF.paths_q + (tail % PATHS_RING) * 4)
            local at = base + OFF.paths_a + (a_head % PATHS_RING) * 16
            poke('int32_t', at, t)
            poke('uint64_t', at + 8, pm.native_base(t) or 0)
            poke('uint32_t', base + OFF.paths_a_head, (a_head + 1) & 0xffffffff)   -- (last: the DLL takes it once filled)
            tail = (tail + 1) & 0xffffffff
            poke('uint32_t', base + OFF.paths_q_tail, tail)
        end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < paths_next_try then return end
    paths_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then paths_why_not = why return end
    local ok, problem = pcall(paths_start, base)
    if ok then paths_why_not = nil else paths_why_not = tostring(problem) end
end

local function report_paths(base)
    local frames, plans = peek('int64_t', base + OFF.paths_frames), peek('int64_t', base + OFF.paths_plans)
    print(('  frames drawn %d; the last drew %d worn tiles, of %d in the view\'s blocks; the soil %s'):format(
          frames, peek('uint32_t', base + OFF.paths_cells_last), peek('uint32_t', base + OFF.paths_known),
          peek('uint64_t', base + OFF.paths_soil_addr) ~= 0 and 'found' or 'not found yet'))
    print(('  worn tiles painted %d; cells left as the game drew them (nothing painted on the tile yet) %d; questions put off %d'):format(
          peek('int64_t', base + OFF.paths_baked), peek('uint32_t', base + OFF.paths_waits), peek('uint32_t', base + OFF.paths_q_full)))
    -- (PATHS HELD, 15Z)
    print(('  cells shown their last painting while the new one waited %d (the last frame %d); new paintings put off a frame: the frame\'s time used %d, no blank %d'):format(
          peek('int64_t', base + OFF.paths_held), peek('uint32_t', base + OFF.paths_held_last),
          peek('int64_t', base + OFF.paths_put_off), peek('uint32_t', base + OFF.paths_no_blank)))
    print(('  the list of grass pictures started over %d times; the paintings\' newer half became the older %d times'):format(
          peek('uint32_t', base + OFF.paths_bases_dropped), peek('uint32_t', base + OFF.paths_bakes_halved)))
    if plans > 0 then
        print(('  planning: %.1f us a frame on average, worst %.1f us; blocks worked out %d (the last plan %d)'):format(
              peek('double', base + OFF.paths_plan_us_total) / plans, peek('double', base + OFF.paths_plan_us_max),
              peek('int64_t', base + OFF.paths_blocks_total), peek('uint32_t', base + OFF.paths_blocks_last)))
    end
    if frames > 0 then
        print(('  drawing: %.1f us a frame on average, worst %.1f us'):format(
              peek('double', base + OFF.paths_draw_us_total) / frames, peek('double', base + OFF.paths_draw_us_max)))
    end
end

-- ==========================================
-- FOG OVER WATER, SET BY THE DLL (test 15H)
-- ==========================================
-- detailed_weather_dll.cpp: FOG OVER WATER. The game's 8 hazes are the first 8 of
-- gps.texture_indices1 (g_src: gps.multilevel_depth_texpos); it lays one a cell in the interface
-- layer of a level below, by the level at the bottom of the cell. The DLL reads the 8 there every
-- frame; this hands it where they are and the interface layer's offset, and reports. A census of
-- every haze in view, by level, is taken at start and with each report (the last one done is shown).
fog_wanted = fog_wanted ~= false   -- `native fog` turns it off and on (on unless turned off)
fog_running = fog_running or false
fog_why_not = fog_why_not or nil
fog_note = fog_note or nil
local fog_next_try = 0
local FOG_HAZES = 8   -- the game's hazes (the DLL's FOG_HAZES)

-- Starts it: the addresses filled, the hazes checked and handed over.
local function fog_start(base)
    local gps = df.global.gps
    poke('uint32_t', base + OFF.fog_enabled, 0)
    fill_common(base)
    local vp = gps.main_viewport
    poke('uint32_t', base + OFF.off_interface, addr_of(vp:_field('screentexpos_interface')) - addr_of(vp))
    -- the hazes: 8 different textures, all made (0 until the game has loaded its art)
    local seen = {}
    for k = 0, FOG_HAZES - 1 do
        local t = gps.texture_indices1[k]
        if t <= 0 then qerror('the game\'s hazes aren\'t made yet') end
        if seen[t] then qerror('gps.texture_indices1 doesn\'t start with 8 different hazes in this DF') end
        seen[t] = true
    end
    poke('uint64_t', base + OFF.fog_tex_addr, addr_of(gps:_field('texture_indices1')))
    for _, name in ipairs({'fog_frames', 'fog_moved', 'fog_put_back', 'fog_plans'}) do poke('int64_t', base + OFF[name], 0) end
    for _, name in ipairs({'fog_plan_us_total', 'fog_plan_us_max', 'fog_us_total', 'fog_us_max'}) do
        poke('double', base + OFF[name], 0)
    end
    poke('uint32_t', base + OFF.fog_kept_full, 0)
    poke('int64_t', base + OFF.fog_blocks_walked, 0)
    poke('uint32_t', base + OFF.fog_reset, (peek('uint32_t', base + OFF.fog_reset) + 1) & 0xffffffff)   -- (the DLL's kept blocks forgotten)
    poke('uint32_t', base + OFF.fog_census_ask, (peek('uint32_t', base + OFF.fog_census_ask) + 1) & 0xffffffff)
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.fog_enabled, 1)
    fog_note = 'the game\'s nearest haze is ' .. texture_name(gps.texture_indices1[0])
    fog_running = true
end

-- Hands the hazes back to the game: the DLL puts back its own over the next two frames.
local function fog_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.fog_enabled, 0) end
    fog_running = false
end

-- Every frame (update): started or handed back.
local function update_fog()
    if not fog_wanted or held then
        if fog_running then fog_hand_back() end
        return
    end
    if fog_running or not dfhack.isMapLoaded() or clock_s() < fog_next_try then return end
    fog_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then fog_why_not = why return end
    local ok, problem = pcall(fog_start, base)
    if ok then fog_why_not = nil else fog_why_not = tostring(problem) end
end

-- The DLL's counts, in words, and the last census; a new census asked for the next report.
local function report_fog(base)
    local frames, plans = peek('int64_t', base + OFF.fog_frames), peek('int64_t', base + OFF.fog_plans)
    local function u32(name) return peek('uint32_t', base + OFF[name]) end
    print(('  frames set %d; the last plan marked %d cells over deep water (full, two or more levels down)'):format(
          frames, u32('fog_marked_last')))
    print(('  the last frame: %d given their surface\'s haze; left as the game laid them: %d already the surface\'s,'
          .. ' %d with no haze of the water\'s level, %d with nothing drawn above the water'):format(
          u32('fog_moved_last'), u32('fog_already_last'), u32('fog_unmatched_last'), u32('fog_dry_last')))
    local odd_d = peek('int32_t', base + OFF.fog_odd_d)
    if odd_d > 0 then
        local haze = peek('int32_t', base + OFF.fog_odd_haze)
        print(('    the first with no haze of the water\'s level: water %d levels down, %s'):format(odd_d,
              haze >= 0 and ('holding haze %d, in the level %d down'):format(haze, peek('int32_t', base + OFF.fog_odd_slot))
              or 'no haze at all'))
    end
    print(('  summed: %d cells given their surface\'s haze, %d given the game\'s back before it drew again; list full %d times'):format(
          peek('int64_t', base + OFF.fog_moved), peek('int64_t', base + OFF.fog_put_back), u32('fog_kept_full')))
    if plans > 0 then
        print(('  planning: %.1f us a frame on average, worst %.1f us; map blocks walked %.2f a frame on average'
              .. ' (the last plan %d), %d kept'):format(
              peek('double', base + OFF.fog_plan_us_total) / plans, peek('double', base + OFF.fog_plan_us_max),
              peek('int64_t', base + OFF.fog_blocks_walked) / plans, u32('fog_blocks_walked_last'), u32('fog_blocks_kept')))
    end
    if frames > 0 then
        print(('  setting: %.1f us a frame on average, worst %.1f us'):format(
              peek('double', base + OFF.fog_us_total) / frames, peek('double', base + OFF.fog_us_max)))
    end
    -- THE CENSUS: where the game lays its hazes, as it laid them
    if u32('fog_census_done') == u32('fog_census_ask') then
        print(('  the game\'s hazes in view (the last census): %d cells with one, %d with more than one;'
              .. ' by level down, haze:cells'):format(u32('fog_census_cells'), u32('fog_census_multi')))
        for level = 0, 8 do
            local parts = {}
            for k = 0, FOG_HAZES - 1 do
                local c = peek('uint32_t', base + OFF.fog_census + (level * FOG_HAZES + k) * 4)
                if c > 0 then parts[#parts + 1] = ('%d:%d'):format(k, c) end
            end
            if #parts > 0 then print(('    %d down%s: %s'):format(level, level == 0 and ' (the view\'s own)' or '', table.concat(parts, '  '))) end
        end
    else
        print('  the game\'s hazes in view: the census isn\'t done yet (ask again)')
    end
    poke('uint32_t', base + OFF.fog_census_ask, (peek('uint32_t', base + OFF.fog_census_ask) + 1) & 0xffffffff)
end

-- ==========================================
-- RAIN AND SNOW FALLING (test 15M)
-- ==========================================
-- detailed_weather.lua found every outdoor tile in view where it rained or snowed, as a Lua table, four
-- times a second and on every frame the view moved (4.6 to 6.5 ms a rescan in play), and wrote each
-- one's sheet tile every frame (most of its "untimed" 2.7 to 3.9 ms a frame while raining). The DLL now
-- works out the tiles from the map and draws them. This hands it:
--   * at start: the flow layer's and top_shadow's offsets, the designation bits, which tiletypes are
--     shape EMPTY (find_rain's open space over water);
--   * when detailed_weather.lua rescans (rain_weather): the weather of each map block in view, at the
--     view's level, from its weather_at. A block's weather is kept between rescans, so a pan only
--     looks up the blocks it brings in; detailed_weather.lua's quarter-second weather check finds any
--     change and asks for every block again (`full`);
--   * each frame (rain_frame): the slant and animation frame, and each sheet the first time it's
--     needed at a new level: every tile's texpos (0 where the sheet's layout says nothing is drawn),
--     copied into the block in one move.
local RAIN_GRID = 64        -- the DLL's RAIN_GRID: the weather grid's side, in map blocks
local RAIN_TEX = 16384      -- the DLL's RAIN_TEX: the most tiles a sheet can hand over
rain_wanted = rain_wanted ~= false   -- `native rain` turns it off and on (on unless turned off)
rain_running_now = rain_running_now or false
rain_why_not = rain_why_not or nil
local rain_next_try = 0
rain_handed = rain_handed or {rain = nil, snow = nil}   -- the sheet each kind's table holds (its name)
rain_held = rain_held or {rain = {}, snow = {}}          -- and which of its groups (hand_group)
rain_cache = rain_cache or {codes = {}, count = 0}   -- each block's weather code, by level and block
rain_any = rain_any or {rain = false, snow = false}   -- what the last grid held
rain_times = rain_times or {grids = 0, grid_ms = 0, lookups = 0, sheets = 0, sheet_ms = 0}
local rain_grid_buf = nil   -- scratch for the one-move copy
-- THE START, TIMED (15N): rain took a long while to show in play after loading, unmeasured. Each step
-- of its start is timed (os.clock) from native.lua's first frame on the map: the DLL drawing started,
-- rain or snow first in the weather grid, a sheet first handed over, and the first tile the DLL drew.
rain_clock = rain_clock or {}

local function rain_start(base)
    poke('uint32_t', base + OFF.rain_enabled, 0)
    fill_common(base)
    local vp = df.global.gps.main_viewport
    poke('uint32_t', base + OFF.off_high_flow, addr_of(vp:_field('screentexpos_high_flow')) - addr_of(vp))
    poke('uint32_t', base + OFF.off_top_shadow, addr_of(vp:_field('screentexpos_top_shadow')) - addr_of(vp))
    -- (magma_mask is shared with MURKY, which may be off)
    poke('uint32_t', base + OFF.magma_mask, designation_mask('liquid_type', 1 << 21))
    local EMPTY = df.tiletype_shape.EMPTY
    local last = math.min(df.tiletype._last_item, TT_TABLE - 1)
    for tt = 0, TT_TABLE - 1 do
        local empty = tt <= last and df.tiletype[tt] and df.tiletype.attrs[tt].shape == EMPTY
        poke('uint8_t', base + OFF.tt_empty + tt, empty and 1 or 0)
    end
    poke('int32_t', base + OFF.rain_wz, -1)
    poke('uint32_t', base + OFF.rain_weather_any, 0)
    poke('int32_t', base + OFF.rain_tex_n, 0)
    poke('int32_t', base + OFF.snow_tex_n, 0)
    rain_handed = {rain = nil, snow = nil}
    rain_held = {rain = {}, snow = {}}
    rain_cache = {codes = {}, count = 0}
    rain_any = {rain = false, snow = false}
    for _, name in ipairs({'rain_frames', 'rain_drawn', 'rain_put_back'}) do poke('int64_t', base + OFF[name], 0) end
    poke('double', base + OFF.rain_us_total, 0)
    poke('double', base + OFF.rain_us_max, 0)
    poke('uint32_t', base + OFF.rain_kept_full, 0)
    poke('uint32_t', base + OFF.rain_skipped, 0)
    rain_times = {grids = 0, grid_ms = 0, lookups = 0, sheets = 0, sheet_ms = 0}
    poke('uint32_t', base + OFF.rain_dropped, 0)
    rain_clock.started = rain_clock.started or clock_s()
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.rain_enabled, 1)
    rain_running_now = true
end

-- Hands the rain back to detailed_weather.lua: the DLL puts back the game's own flow layer over the
-- next two frames, and detailed_weather.lua rescans and draws from its next frame.
local function rain_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.rain_enabled, 0) end
    rain_running_now = false
end

-- Every frame (update): started or handed back.
local function update_rain()
    if not rain_wanted or held then
        if rain_running_now then rain_hand_back() end
        return
    end
    if rain_running_now or not dfhack.isMapLoaded() or clock_s() < rain_next_try then return end
    rain_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then rain_why_not = why return end
    local ok, problem = pcall(rain_start, base)
    if ok then rain_why_not = nil else rain_why_not = tostring(problem) end
end

-- Whether the DLL is drawing the falling rain and snow (detailed_weather.lua then neither finds the
-- tiles nor draws them).
function rain_running() return rain_running_now end

-- What the last grid held: whether any block in view has rain, and any snow (so a sheet is only
-- loaded for what's falling).
function rain_kinds() return rain_any.rain, rain_any.snow end

-- The weather of each map block in view, at the view's level, into the DLL's grid. `weather_at` is
-- detailed_weather.lua's (x, y, z -> 'rain', 'snow' or nil), asked at each block's middle tile as
-- find_rain did; `full` asks every block again, else only those not looked up since the last full.
function rain_weather(viewport, weather_at, full)
    if not rain_running_now then return end
    local base = block()
    if not base then return end
    local t0 = clock_s()
    -- (a new map starts afresh: forget_world hands the rain back, and rain_start empties the cache)
    if full or rain_cache.count > 16384 then rain_cache.codes, rain_cache.count = {}, 0 end
    local codes = rain_cache.codes
    local z = viewport.z
    local bx1, by1 = math.max(0, viewport.x1) // 16, math.max(0, viewport.y1) // 16
    local nx = math.min(viewport.x2 // 16 - bx1 + 1, RAIN_GRID)
    local ny = math.min(viewport.y2 // 16 - by1 + 1, RAIN_GRID)
    if nx < 1 or ny < 1 then
        poke('uint32_t', base + OFF.rain_weather_any, 0)
        poke('int32_t', base + OFF.rain_wz, z)
        rain_any.rain, rain_any.snow = false, false
        return
    end
    if not rain_grid_buf then rain_grid_buf = df.new('uint8_t', RAIN_GRID * RAIN_GRID) end
    local buf = rain_grid_buf
    local has_rain, has_snow, lookups = false, false, 0
    for gx = 0, nx - 1 do
        local bx = bx1 + gx
        for gy = 0, ny - 1 do
            local by = by1 + gy
            local key = (z * 1024 + bx) * 1024 + by
            local code = codes[key]
            if not code then
                local w = weather_at(bx * 16 + 8, by * 16 + 8, z)
                code = w == 'rain' and 1 or w == 'snow' and 2 or 0
                codes[key] = code
                rain_cache.count = rain_cache.count + 1
                lookups = lookups + 1
            end
            buf[gx * ny + gy] = code
            if code == 1 then has_rain = true elseif code == 2 then has_snow = true end
        end
    end
    -- (the grid first, then where it is and for which level: the hook only runs after this frame's Lua)
    local _, src = df.sizeof(buf)
    dfhack.internal.memmove(base + OFF.rain_weather, src, nx * ny)
    poke('int32_t', base + OFF.rain_wbx, bx1)
    poke('int32_t', base + OFF.rain_wby, by1)
    poke('int32_t', base + OFF.rain_wnx, nx)
    poke('int32_t', base + OFF.rain_wny, ny)
    poke('int32_t', base + OFF.rain_wz, z)
    poke('uint32_t', base + OFF.rain_weather_any, (has_rain or has_snow) and 1 or 0)
    rain_any.rain, rain_any.snow = has_rain, has_snow
    if (has_rain or has_snow) and not rain_clock.grid then rain_clock.grid = clock_s() end
    rain_times.grids = rain_times.grids + 1
    rain_times.lookups = rain_times.lookups + lookups
    rain_times.grid_ms = rain_times.grid_ms + (clock_s() - t0) * 1000
end

-- THE ART'S GROUPS. The DLL's tables are by a sheet's tile numbers as drawn, but it only ever reads
-- the tiles of the one group Lua tells it to draw (a slant of the rain, a wind of the snow or leaves, a
-- density of the fog), and the art is packed a file per group (detailed_weather.lua: sheet_of,
-- sheet_tiles). So a table is filled a group at a time, as each is first wanted, and only those
-- files are ever loaded.
--   held    what the table holds: {sheet =, groups = (group -> true once written), last = the group
--           last wanted that was there}. A new sheet empties the table first.
--   n       the sheet's tiles as drawn; f.sheet_tiles(sheet, group) gives a group's textures, or nil
--           while its file waits its turn to load; f.texpos_of(handle).
-- Returns the group to draw: the one wanted once it's written, until then the last one that was
-- (so nothing blinks off while a file loads), or nil with none yet; and whether it wrote one now.
-- Entries go from 0 (nothing drawn) to their texture one at a time, so the DLL can draw meanwhile.
local function hand_group(base, held, n_off, tex_off, most, sheet, group, n, f)
    if n > most then qerror(('the sheet %s has %d tiles, the DLL takes at most %d'):format(sheet.name, n, most)) end
    local wrote = false
    if held.sheet ~= sheet then
        poke('int32_t', base + n_off, 0)
        local entries = df.reinterpret_cast('int32_t', base + tex_off)
        for index = 0, n - 1 do entries[index] = 0 end
        held.sheet, held.groups, held.last = sheet, {}, nil
        poke('int32_t', base + n_off, n)
    end
    if not held.groups[group] then
        local tiles = f.sheet_tiles(sheet, group)
        if tiles then
            local layout = sheet.layout
            local side = layout.cells or layout.patch
            local tiles_a_group, group_count = side * side * layout.frames, sheet.group_count
            local entries, at, texpos_of = df.reinterpret_cast('int32_t', base + tex_off), sheet.at, f.texpos_of
            for number = 1, n do
                if (number - 1) // tiles_a_group % group_count + 1 == group then
                    local place = at[number]
                    local handle = place and place > 0 and tiles[place]
                    local texpos = handle and texpos_of(handle)
                    entries[number - 1] = (texpos and texpos > 0) and texpos or 0
                end
            end
            held.groups[group] = true
            wrote = true
        end
    end
    if held.groups[group] then held.last = group end
    return held.last, wrote
end

-- Each frame, from detailed_weather.lua's overlay: f holds both kinds' layouts (art/rain_sheet.lua,
-- art/snow_sheet.lua), levels, sheet names and sheets (nil while one loads, or when that kind isn't
-- falling in view), this frame's slant and wind index (slant_for_wind, 1-based), animation frames
-- (0-based), and texpos_of.
function rain_frame(f)
    if not rain_running_now then return end
    local base = block()
    if not base then return end
    local rl, sl = f.rain_layout, f.snow_layout
    local slant, snow_wind = f.slant, f.snow_wind
    local t0 = clock_s()
    local wrote_rain, wrote_snow = false, false
    if f.rain_sheet then
        if rain_handed.rain ~= f.rain_name then
            poke('int32_t', base + OFF.rain_cells, rl.cells)
            poke('int32_t', base + OFF.rain_anim, rl.frames)
            poke('int32_t', base + OFF.rain_slants, #rl.slants)
            rain_handed.rain = f.rain_name
        end
        local drawn
        drawn, wrote_rain = hand_group(base, rain_held.rain, OFF.rain_tex_n, OFF.rain_tex, RAIN_TEX, f.rain_sheet, f.slant,
                                       #rl.surfaces * #rl.slants * rl.cells * rl.cells * rl.frames, f)
        slant = drawn or slant
    end
    if f.snow_sheet then
        if rain_handed.snow ~= f.snow_name then
            poke('int32_t', base + OFF.snow_cells, sl.cells)
            poke('int32_t', base + OFF.snow_anim, sl.frames)
            rain_handed.snow = f.snow_name
        end
        local drawn
        drawn, wrote_snow = hand_group(base, rain_held.snow, OFF.snow_tex_n, OFF.snow_tex, RAIN_TEX, f.snow_sheet, f.snow_wind,
                                       #sl.winds * sl.cells * sl.cells * sl.frames, f)
        snow_wind = drawn or snow_wind
    end
    if wrote_rain or wrote_snow then
        rain_clock.sheet = rain_clock.sheet or clock_s()
        rain_times.sheets = rain_times.sheets + (wrote_rain and 1 or 0) + (wrote_snow and 1 or 0)
        rain_times.sheet_ms = rain_times.sheet_ms + (clock_s() - t0) * 1000
    end
    poke('int32_t', base + OFF.rain_slant, slant)
    poke('int32_t', base + OFF.rain_frame, f.rain_frame)
    poke('int32_t', base + OFF.snow_wind, snow_wind)
    poke('int32_t', base + OFF.snow_frame, f.snow_frame)
    -- (THE START, TIMED: the first frame the DLL has drawn a tile)
    if not rain_clock.drawn and peek('int64_t', base + OFF.rain_drawn) > 0 then rain_clock.drawn = clock_s() end
end

local function report_rain(base)
    local function u32(name) return peek('uint32_t', base + OFF[name]) end
    local frames = peek('int64_t', base + OFF.rain_frames)
    print(('  frames drawn %d; the last: %d cells with rain or snow falling, %d given a tile in the flow layer, %d over the game\'s flow (top_shadow), %d left (both taken)')
          :format(frames, u32('rain_cells_last'), u32('rain_drawn_last'), u32('rain_over_flow_last'), u32('rain_no_room_last')))
    print(('  summed: %d cells given a tile, %d put back before the game drew again; list full %d times; frames skipped (the weather for another level) %d')
          :format(peek('int64_t', base + OFF.rain_drawn), peek('int64_t', base + OFF.rain_put_back), u32('rain_kept_full'), u32('rain_skipped')))
    print(('  put back entries let go, their array no longer either of the view\'s buffers: %d'):format(u32('rain_dropped')))
    -- (THE START, TIMED)
    local first = rain_clock.loaded
    local function at(t) return (first and t) and ('%.1f s'):format(t - first) or 'not yet' end
    print(('  the start, after native.lua\'s first frame on this map: the DLL drawing %s; rain or snow in the weather grid %s; a sheet handed over %s; the first tile drawn %s')
          :format(at(rain_clock.started), at(rain_clock.grid), at(rain_clock.sheet), at(rain_clock.drawn)))
    if frames > 0 then
        print(('  drawing: %.1f us a frame on average, worst %.1f us')
              :format(peek('double', base + OFF.rain_us_total) / frames, peek('double', base + OFF.rain_us_max)))
    end
    print(('  sheets handed over: rain %s (%d tiles), snow %s (%d tiles); %d groups handed, %.1f ms each')
          :format(rain_handed.rain or 'none yet', peek('int32_t', base + OFF.rain_tex_n), rain_handed.snow or 'none yet',
                  peek('int32_t', base + OFF.snow_tex_n), rain_times.sheets,
                  rain_times.sheets > 0 and rain_times.sheet_ms / rain_times.sheets or 0))
    print(('  weather grids written %d, %.2f ms each; block weathers looked up %d (the rest kept); now %d x %d blocks at level %d, rain %s, snow %s')
          :format(rain_times.grids, rain_times.grids > 0 and rain_times.grid_ms / rain_times.grids or 0, rain_times.lookups,
                  peek('int32_t', base + OFF.rain_wnx), peek('int32_t', base + OFF.rain_wny), peek('int32_t', base + OFF.rain_wz),
                  rain_any.rain and 'yes' or 'no', rain_any.snow and 'yes' or 'no'))
end

-- ==========================================
-- CRACKS IN PLACE (test 15R)
-- ==========================================
-- frost.lua went over every tile it listed in view, every frame, to put in the cracked floors and ramps
-- of a dry look: 1.35 to 1.84 ms a frame in play after 15O (frost-draw). The DLL puts them in now
-- (detailed_weather_dll.cpp: CRACKS IN PLACE), and since 15U works out which tiles may crack itself, from
-- the map, by frost.lua's rules (as THE COLOUR does its ramps): no tile waits on Lua. Since 15V the DLL
-- also paints each cracked copy itself, in the frame it's first needed (it asked frost.lua and placed it
-- the frame after, and panning kept finding copies not made: ramps drew in). frost.lua hands over each
-- look's numbers and notes the copies painted (its NATIVE CRACKS); the blanks are made here.
crack_running = crack_running or false
crack_why_not = crack_why_not or nil
crack_base = crack_base or nil                     -- the block, while running
crack_world_pending = crack_world_pending or false -- started: the grounds and first blanks still to hand over
crack_note = crack_note or nil
local crack_next_try = 0

-- frost.lua (MODULES KEPT, as colour.lua's)
local frost_kept = nil
local function frost_module()
    if frost_kept then return frost_kept end
    local ok, f = pcall(reqscript, 'internal/detailed_weather/frost')
    if not ok or not f then return nil end
    frost_kept = f
    return f
end

-- Views of the DLL's crack settings and rings, for frost.lua (its native_cv).
local function crack_view(base)
    local function at(t, off) return df.reinterpret_cast(t, base + off) end
    -- (THE PAINTING HERE: the two looks' slots, each {gen, ready, amount, ramp = {dirt job, stone job}, and
    -- FLOORS AHEAD's floors_n, floors_version, floor_orig[], floor_copy[]})
    local looks = {}
    for k = 0, 1 do
        local slot = base + OFF.crack_look + k * CRACK_LOOK_BYTES
        looks[k] = {gen = df.reinterpret_cast('uint32_t', slot), ready = df.reinterpret_cast('uint32_t', slot + 4),
                    amount = df.reinterpret_cast('double', slot + 8),
                    ramp = {slot + 16, slot + 16 + PAINT_JOB_BYTES},
                    floors_n = df.reinterpret_cast('uint32_t', slot + 528),
                    floors_version = df.reinterpret_cast('uint32_t', slot + 532),
                    floor_orig = df.reinterpret_cast('int32_t', slot + 536),
                    floor_copy = df.reinterpret_cast('int32_t', slot + 536 + 4 * CRACK_FLOORS),
                    floors_most = CRACK_FLOORS}
    end
    return {
        on = at('uint32_t', OFF.crack_on), gen = at('uint32_t', OFF.crack_gen),
        gen_prev = at('uint32_t', OFF.crack_gen_prev), depth = at('uint32_t', OFF.crack_depth),
        -- (THE TILES WORKED OUT: a forced temperature, `detailed_weather temperature N`; raised to work all again)
        forced_on = at('uint32_t', OFF.crack_forced_on), forced_c = at('double', OFF.crack_forced_c),
        tables = at('uint32_t', OFF.crack_tables),
        -- (THE NEXT LOOK AHEAD: the next look's number; what the DLL found left of it, and for which)
        gen_next = at('uint32_t', OFF.crack_gen_next), next_walked = at('uint32_t', OFF.crack_next_walked),
        next_missing = at('uint32_t', OFF.crack_next_missing_last),
        looks = looks,
        heat = at('uint64_t', OFF.crack_heat),   -- (16 addresses)
        -- copies painted: CrackDone, 16 bytes {int32 tex, base; uint32 gen; uint8 piece, code}
        d_head = at('uint32_t', OFF.crack_d_head), d_tail = at('uint32_t', OFF.crack_d_tail),
        d32 = at('int32_t', OFF.crack_d), d8 = at('uint8_t', OFF.crack_d), done_ring = CRACK_DONE_RING,
    }
end

-- THE BLANKS (15V): blank textures for the DLL to paint copies into, kept ready in its ring (crack_b:
-- {int32 tex; int32; uint64 pixels}), each made as colour.lua makes its own (native_blank): a texture of
-- clear pixels whose rows aren't padded. Never drawn before the DLL paints it.
crack_blank_pixels = crack_blank_pixels or nil
crack_blank_failed = crack_blank_failed or false   -- a blank's pixels couldn't be painted (padded rows): none made
                                                   -- since, as each try leaves a texture behind (never deleted)
local function crack_blanks(base, ms)
    local g = grass_module()
    if not g or crack_blank_failed then return end
    local head = peek('uint32_t', base + OFF.crack_b_head)
    local room = CRACK_BLANKS - ((head - peek('uint32_t', base + OFF.crack_b_tail)) & 0xffffffff)
    if room <= 0 then return end
    if not crack_blank_pixels then
        crack_blank_pixels = {}
        for n = 1, 32 * 32 do crack_blank_pixels[n] = 0 end
    end
    local ends = clock_s() + ms / 1000
    local made = 0
    while made < room and clock_s() < ends do
        local handle = dfhack.textures.createTile(crack_blank_pixels, 32, 32)
        local texpos = handle and dfhack.textures.getTexposByHandle(handle)
        local address = texpos and g.original_address(texpos)
        if not address then crack_blank_failed = true break end
        local slot = base + OFF.crack_b + ((head + made) % CRACK_BLANKS) * 16
        poke('int32_t', slot, texpos)
        poke('uint64_t', slot + 8, address)
        made = made + 1
    end
    poke('uint32_t', base + OFF.crack_b_head, (head + made) & 0xffffffff)   -- (after the blanks: the DLL takes up to it)
end

-- Starts the cracks: the DLL forgets every cracked copy and tile it knew (from before this start), and is
-- handed frost.lua's rules: by tiletype, a floor, a ramp and its kind, or open space; the temperature
-- bands; how deep to look; where a block keeps its temperatures and its snow; each original's ground
-- (THE PAINTING HERE); and its first blanks.
local function crack_start(base)
    local f = frost_module()
    local col = colour_module()
    if not f or type(f.native_crack_begin) ~= 'function' or type(f.crack_rules) ~= 'function'
            or type(f.crack_ground_kinds) ~= 'function' or not col or type(col.native_template) ~= 'function' then
        qerror('frost.lua has no NATIVE CRACKS yet: apply its pairs first')
    end
    poke('uint32_t', base + OFF.crack_on, 0)
    poke('uint32_t', base + OFF.crack_gen_next, 0xffffffff)
    fill_common(base)
    -- ---- FROST.LUA'S RULES (THE TILES WORKED OUT) ----
    local rules = f.crack_rules()
    local last = math.min(df.tiletype._last_item, TT_TABLE - 1)
    for tt = 0, TT_TABLE - 1 do
        poke('uint8_t', base + OFF.crack_tt + tt, tt <= last and rules.tiletype[tt] or 0)
    end
    poke('double', base + OFF.crack_band_c, rules.band_c)
    poke('double', base + OFF.crack_cool_from, rules.cool_from)
    poke('double', base + OFF.crack_warm_from, rules.warm_from)
    poke('uint32_t', base + OFF.crack_depth, rules.most_depth)
    poke('uint32_t', base + OFF.crack_recheck, CRACK_RECHECK)
    poke('uint32_t', base + OFF.crack_forced_on, rules.forced_c and 1 or 0)
    poke('double', base + OFF.crack_forced_c, rules.forced_c or 0)
    local blk = df.global.world.map.map_blocks[0]
    poke('uint32_t', base + OFF.off_temperature, addr_of(blk:_field('temperature_1')) - addr_of(blk))
    -- the snow on a tile (grass.lua: snow_amount): as the snow's start reads it, if any spatter is about
    -- yet (the snow's own start fills the same when snow comes)
    local spatter_ev = any_event(df.block_square_event_material_spatterst)
    if spatter_ev then
        local ebase = addr_of(spatter_ev)
        poke('uint64_t', base + OFF.spatter_vtable, peek('uint64_t', ebase))
        poke('uint32_t', base + OFF.off_ev_mat_type, addr_of(spatter_ev:_field('mat_type')) - ebase)
        poke('uint32_t', base + OFF.off_ev_mat_state, addr_of(spatter_ev:_field('mat_state')) - ebase)
        poke('uint32_t', base + OFF.off_ev_amount, addr_of(spatter_ev:_field('amount')) - ebase)
        poke('int16_t', base + OFF.snow_mat_type, WATER)
        poke('int16_t', base + OFF.snow_mat_state, df.matter_state.Powder)
    end
    poke('int32_t', base + OFF.snowy_from, SNOWY)
    poke('uint32_t', base + OFF.crack_tables, (peek('uint32_t', base + OFF.crack_tables) + 1) & 0xffffffff)
    for _, name in ipairs({'crack_frames', 'crack_written', 'crack_painted', 'crack_ahead_painted', 'crack_ramp_held',
                           'crack_blocks_worked', 'crack_waiting'}) do poke('int64_t', base + OFF[name], 0) end
    for _, name in ipairs({'crack_us_total', 'crack_us_max', 'crack_paint_us_total', 'crack_paint_us_max'}) do
        poke('double', base + OFF[name], 0)
    end
    for _, name in ipairs({'crack_cleared', 'crack_no_blank', 'crack_over_time', 'crack_unreadable', 'crack_table_full',
                           'crack_done_full'}) do poke('uint32_t', base + OFF[name], 0) end
    -- ---- A NEW START: everything the DLL kept from before forgotten (in its next frame, before this one's
    -- grounds and blanks are taken), the looks' slots emptied ----
    poke('uint32_t', base + OFF.crack_world, (peek('uint32_t', base + OFF.crack_world) + 1) & 0xffffffff)
    for k = 0, 1 do poke('uint32_t', base + OFF.crack_look + k * CRACK_LOOK_BYTES + 4, 0) end
    crack_world_pending = true   -- (grounds and blanks once the DLL has forgotten: update_cracks)
    crack_blank_failed = false
    poke('uint32_t', base + OFF.install, 1)
    f.native_crack_begin(crack_view(base))
    crack_base = base
    crack_running = true
end

-- Hands the cracks back to frost.lua: the DLL gives the floors their ground back over the next frames
-- (THE COLOUR does ramps'), and frost.lua puts the cracks in itself from its next frame.
local function crack_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.crack_on, 0) end
    local f = frost_module()
    if f and f.native_crack_end then f.native_crack_end() end
    crack_running = false
end

-- Every frame (update): started or handed back; and the cracks off until frost.lua's apply turns them
-- on this frame (it isn't called while frost rests or is off: then they stop).
local function update_cracks()
    local f = frost_module()
    local wanted = col_running and not held and f and type(f.native_crack_begin) == 'function'
    if not wanted then
        if crack_running then crack_hand_back() end
        return
    end
    if crack_running then
        local cv = f.native_cv   -- (the view frost.lua was given: no lookup of the block a frame)
        if cv then cv.on.value, cv.gen_next.value = 0, 0xffffffff end   -- (and no next look ahead)
        local base = crack_base
        if crack_world_pending then
            -- (the DLL forgets in its prerender, which has run once the frame after the start: then each
            -- original's ground, and the first blanks)
            crack_world_pending = false
            local kinds = f.crack_ground_kinds()
            local table_ = df.reinterpret_cast('uint8_t', peek('uint64_t', base + OFF.crack_ground))
            local n = 0
            for t, k in pairs(kinds) do
                if t > 0 and t < peek('uint32_t', base + OFF.col_tex_map) then table_[t] = k n = n + 1 end
            end
            crack_note = ('%d originals\' grounds that crack handed over'):format(n)
            crack_blanks(base, BLANK_FIRST_MS)
        else
            local ready = (peek('uint32_t', base + OFF.crack_b_head) - peek('uint32_t', base + OFF.crack_b_tail)) & 0xffffffff
            crack_blanks(base, ready < CRACK_BLANKS // 4 and BLANK_LOW_MS or BLANK_MS)
        end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < crack_next_try then return end
    crack_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then crack_why_not = why return end
    local ok, problem = pcall(crack_start, base)
    if ok then crack_why_not = nil else crack_why_not = tostring(problem) end
end

local function report_cracks(base)
    local function u32(name) return peek('uint32_t', base + OFF[name]) end
    local function i64(name) return peek('int64_t', base + OFF[name]) end
    local frames = i64('crack_frames')
    if crack_note then print('  ' .. crack_note) end
    print(('  frames placed %d; the last: %d cells of tiles that may crack, %d given their cracked copy, %d the look before\'s, %d left uncracked (no copy yet)')
          :format(frames, u32('crack_cells_last'), u32('crack_written_last'), u32('crack_held_last'), u32('crack_waiting_last')))
    print(('  summed: %d cells given their copy; %d left uncracked for a frame (no copy yet); %d given their ground back when the cracks stopped')
          :format(i64('crack_written'), i64('crack_waiting'), u32('crack_cleared')))
    print(('  copies painted here: %d for the look showing, %d for the next look ahead (%d the last frame); %d known, %d textures known by picture')
          :format(i64('crack_painted'), i64('crack_ahead_painted'), u32('crack_painted_last'), u32('crack_copies_kept'), u32('crack_pics_kept')))
    print(('  copies put off: no blank ready %d, the frame\'s painting time up %d; not painted: pixels unreadable %d, the table full %d; painted but not noted by frost.lua %d')
          :format(u32('crack_no_blank'), u32('crack_over_time'), u32('crack_unreadable'), u32('crack_table_full'), u32('crack_done_full')))
    print(('  ramps given the cracked copy they showed last while their own waits: %d the last frame, %d summed; cells in view missing the next look\'s copy %d (the last look ahead)')
          :format(u32('crack_ramp_held_last'), i64('crack_ramp_held'), u32('crack_next_missing_last')))
    print(('  blanks ready %d of %d%s')
          :format((peek('uint32_t', base + OFF.crack_b_head) - u32('crack_b_tail')) & 0xffffffff, CRACK_BLANKS,
                  crack_blank_failed and '; NO MORE MADE: a blank\'s pixels couldn\'t be painted (padded rows)' or ''))
    if frames > 0 then
        print(('  placing: %.1f us a frame on average, worst %.1f us; painting %.1f us a frame on average, worst %.1f us; map blocks kept %d, worked out from the map %d (%d the last frame)')
              :format(peek('double', base + OFF.crack_us_total) / frames, peek('double', base + OFF.crack_us_max),
                      peek('double', base + OFF.crack_paint_us_total) / frames, peek('double', base + OFF.crack_paint_us_max),
                      u32('crack_tiles_kept'), i64('crack_blocks_worked'), u32('crack_worked_last')))
    end
    local f = frost_module()
    local fc = f and f.native_crack_counts
    if fc then
        -- (FLOORS AHEAD: how many originals' grounds crack, and how many each look slot lists so far)
        local total, listed = 0, f.crack_slot_floors or {}
        for _ in pairs(f.crack_kinds or {}) do total = total + 1 end
        print(('  frost.lua: copies noted as Detailed Weather\'s %d; originals whose ground cracks %d, floors listed by the looks %d and %d of %d')
              :format(fc.painted or 0, total, listed[0] or 0, listed[1] or 0, CRACK_FLOORS))
    end
end

-- PARTS TIMED (test 15J): each part of update's work, summed, to find where the native stage's
-- time goes. A frame where a part takes 50 ms or more (a start) is counted apart, so the frames in
-- between show. os.clock counts in whole ms on Windows: over many frames the averages still hold.
parts_timed = parts_timed or {}
local PART_NAMES = {'colour', 'shade', 'murky', 'paths', 'fog', 'rain', 'cracks', 'wfog', 'leaves', 'spatter', 'snow'}
local PART_START_MS = 50
local function timed_part(name, fn, ...)
    local t0 = clock_s()
    fn(...)
    local ms = (clock_s() - t0) * 1000
    local p = parts_timed[name]
    if not p then p = {ms = 0, frames = 0, starts = 0, start_ms = 0} parts_timed[name] = p end
    if ms >= PART_START_MS then p.starts, p.start_ms = p.starts + 1, p.start_ms + ms
    else p.ms, p.frames = p.ms + ms, p.frames + 1 end
end
local function report_parts()
    local out = {}
    for _, name in ipairs(PART_NAMES) do
        local p = parts_timed[name]
        if p and p.frames > 0 then
            out[#out + 1] = ('%s %.3f'):format(name, p.ms / p.frames)
                .. (p.starts > 0 and (' (+%d start%s, %.0f ms)'):format(p.starts, p.starts > 1 and 's' or '', p.start_ms) or '')
        end
    end
    print('native.lua\'s own work, ms a frame on average (starts apart): ' .. (#out > 0 and table.concat(out, ', ') or 'none yet'))
end

-- THE SNOW'S BAKES HERE (15Z): each bake the DLL painted, filed as the snow's own, as snow_ramps.lua files
-- its own: frost puts its rime under a snowy edge (snowy_edge_texpos), and the colour leaves them be
-- (detailed_weather_made, snow_made). And the shared blanks it paints into kept topped up, unless the
-- cracks or the spatter do that this frame.
local function snow_bakes_told(base)
    local head, tail = peek('uint32_t', base + OFF.bake_here_head), peek('uint32_t', base + OFF.bake_here_tail)
    if head ~= tail then
        local sr = snow_module()
        local made = _G.detailed_weather_made
        while tail ~= head do
            local at = base + OFF.bake_here + (tail % 256) * 16
            local tex, kind = peek('int32_t', at), peek('uint32_t', at + 4)
            if tex > 0 then
                if made then made[tex] = true end
                if sr and sr.snow_made then sr.snow_made[tex] = true end
                if sr and kind == 3 and sr.snowy_edge_texpos then sr.snowy_edge_texpos[tex] = true end
            end
            tail = (tail + 1) & 0xffffffff
        end
        poke('uint32_t', base + OFF.bake_here_tail, tail)
    end
    if not crack_running and not spat_running_now then
        local ready = (peek('uint32_t', base + OFF.crack_b_head) - peek('uint32_t', base + OFF.crack_b_tail)) & 0xffffffff
        crack_blanks(base, ready < CRACK_BLANKS // 4 and BLANK_LOW_MS or BLANK_MS)
    end
end

local function update_snow(snow_on)
    if not snow_on or held then
        if running then hand_back() end
        return
    end
    if running then
        local base = block()
        if base then snow_bakes_told(base) end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < next_try then return end
    next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then why_not = why return end
    local ok, problem = pcall(start, base)
    if ok then running, why_not = true, nil else why_not = tostring(problem) end
end

-- ==========================================
-- THE FOG AND THE LEAVES DRAWN BY THE DLL (test 15X)
-- ==========================================
-- detailed_weather.lua painted its fog with the overlay, a DFHack call for each outdoor tile in view
-- every frame (thick fog 2.56 ms a frame, and 2.8 ms each time it looked for the tiles again), and
-- leaves.lua wrote the falling leaves and petals into the projectile layer (1.58 to 1.72 ms a frame;
-- 15W's report, both forced on). The DLL draws both from the map each frame now
-- (detailed_weather_dll.cpp: THE FOG AND THE LEAVES DRAWN HERE). Lua hands over each sheet once, and
-- each frame the fog's density and drift, and what each tree is shedding.
wfog_wanted = wfog_wanted ~= false        -- `native wfog` turns the fog off and on
wfog_running_now = wfog_running_now or false
wfog_why_not = wfog_why_not or nil
local wfog_next_try = 0
wfog_handed = wfog_handed or nil          -- the fog sheet handed over
wfog_held = wfog_held or {}               -- and which of its groups (hand_group)
leaf_wanted = leaf_wanted ~= false        -- `native leaves`
leaf_running_now = leaf_running_now or false
leaf_why_not = leaf_why_not or nil
local leaf_next_try = 0
leaf_handed = leaf_handed or {}           -- sheet name -> its slot, 1 to LEAF_SHEETS, once it has one
leaf_held = leaf_held or {}               -- sheet name -> {sheet =, held = (hand_group), n = its tiles}
leaf_wind_sent = leaf_wind_sent or nil    -- the wind the DLL draws: the last one every shedding sheet had
leaf_layout = leaf_layout or nil          -- the first sheet's layout (the others must match it)
leaf_spec_sent = leaf_spec_sent or {}     -- plant raw -> the spec last written
local WFOG_TEX, WFOG_DEPTHS = 16384, 9    -- the DLL's WFOG_TEX, WFOG_DEPTHS
local LEAF_RAWS, LEAF_SHEETS, LEAF_TEX = 1024, 8, 10240   -- the DLL's LEAF_RAWS, LEAF_SHEETS, LEAF_TEX
local LEAF_RECHECK = 3600                 -- frames before a block's leaves are worked out again (leaves.lua
                                          -- forgot all every 60 s: FORGET_MS)

-- leaves.lua (MODULES KEPT, as colour.lua's)
local leaves_kept = nil
local function leaves_module()
    if leaves_kept then return leaves_kept end
    local ok, l = pcall(reqscript, 'internal/detailed_weather/leaves')
    if not ok or not l then return nil end
    leaves_kept = l
    return l
end

-- Each tiletype: 1 a tree's canopy (BRANCH, TWIG, TRUNK_BRANCH: leaves.lua's CANOPY), 2 TREE, 4 open
-- space (EMPTY, RAMP_TOP: find_outdoors, find_over), 8 no fog (frozen ice wall or brook bed)
fill_weather_tt = function(base)
    local shape, material = df.tiletype_shape, df.tiletype_material
    local last = math.min(df.tiletype._last_item, TT_TABLE - 1)
    for tt = 0, TT_TABLE - 1 do
        local v = 0
        if tt <= last and df.tiletype[tt] then
            local a = df.tiletype.attrs[tt]
            if a.material == material.TREE then
                v = v | 2
                if a.shape == shape.BRANCH or a.shape == shape.TWIG or a.shape == shape.TRUNK_BRANCH then v = v | 1 end
            end
            if a.shape == shape.EMPTY or a.shape == shape.RAMP_TOP then v = v | 4 end
            if (a.material == material.FROZEN_LIQUID and a.shape == shape.WALL)
                    or a.shape == shape.BROOK_BED then
                v = v | 8
            end
        end
        poke('uint8_t', base + OFF.wl_tt + tt, v)
    end
end

local function wfog_start(base)
    poke('uint32_t', base + OFF.wfog_on, 0)
    fill_common(base)
    local vp = df.global.gps.main_viewport
    poke('uint32_t', base + OFF.off_interface, addr_of(vp:_field('screentexpos_interface')) - addr_of(vp))
    fill_weather_tt(base)
    poke('int32_t', base + OFF.wfog_level, 0)
    poke('int32_t', base + OFF.wfog_tex_n, 0)
    wfog_handed, wfog_held = nil, {}
    for _, name in ipairs({'wfog_frames_drawn', 'wfog_drawn', 'wfog_put_back'}) do poke('int64_t', base + OFF[name], 0) end
    poke('double', base + OFF.wfog_us_total, 0)
    poke('double', base + OFF.wfog_us_max, 0)
    poke('uint32_t', base + OFF.wfog_kept_full, 0)
    poke('uint32_t', base + OFF.wfog_dropped, 0)
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.wfog_on, 1)
    wfog_running_now = true
end

-- The plants' fields, from a tree on the map (DFHack's own offsets for this build): nil if none yet
local function plant_fields(base)
    local tree
    for _, p in ipairs(df.global.world.plants.all) do
        if p.tree_info then tree = p break end
    end
    local map = df.global.world.map
    local col = map.column_index and map.column_index[0] and map.column_index[0][0]
    if not tree or not col then return false end
    poke('uint64_t', base + OFF.column_index, addr_of(map:_field('column_index')))
    poke('uint32_t', base + OFF.off_col_plants, addr_of(col:_field('plants')) - addr_of(col))
    local pb = addr_of(tree)
    poke('uint32_t', base + OFF.off_plant_pos, addr_of(tree:_field('pos')) - pb)
    poke('uint32_t', base + OFF.off_plant_material, addr_of(tree:_field('material')) - pb)
    poke('uint32_t', base + OFF.off_plant_tree, addr_of(tree:_field('tree_info')) - pb)
    local ti = tree.tree_info
    local tb = addr_of(ti)
    poke('uint32_t', base + OFF.off_tree_body, addr_of(ti:_field('body')) - tb)
    poke('uint32_t', base + OFF.off_tree_height, addr_of(ti:_field('body_height')) - tb)
    poke('uint32_t', base + OFF.off_tree_dim_x, addr_of(ti:_field('dim_x')) - tb)
    poke('uint32_t', base + OFF.off_tree_dim_y, addr_of(ti:_field('dim_y')) - tb)
    return true
end

local function leaf_start(base)
    poke('uint32_t', base + OFF.leaf_on, 0)
    local lv = leaves_module()
    if not lv or type(lv.shedding_raws) ~= 'function' or type(lv.native_frame) ~= 'function' then
        qerror('leaves.lua has no NATIVE LEAVES yet: apply its pairs first')
    end
    fill_common(base)
    if not plant_fields(base) then qerror('no tree on the map yet to read the plants\' fields from') end
    local vp = df.global.gps.main_viewport
    poke('uint32_t', base + OFF.off_projectile, addr_of(vp:_field('screentexpos_projectile')) - addr_of(vp))
    fill_weather_tt(base)
    local sheds = lv.shedding_raws()
    for raw = 0, LEAF_RAWS - 1 do
        poke('uint8_t', base + OFF.leaf_sheds + raw, sheds[raw] and 1 or 0)
        poke('uint16_t', base + OFF.leaf_spec + raw * 2, 0)
    end
    for k = 0, LEAF_SHEETS - 1 do poke('int32_t', base + OFF.leaf_tex_n + k * 4, 0) end
    leaf_handed, leaf_layout, leaf_spec_sent, leaf_held, leaf_wind_sent = {}, nil, {}, {}, nil
    poke('uint32_t', base + OFF.leaf_any, 0)
    poke('uint32_t', base + OFF.leaf_recheck, LEAF_RECHECK)
    poke('uint32_t', base + OFF.leaf_tables, (peek('uint32_t', base + OFF.leaf_tables) + 1) & 0xffffffff)
    for _, name in ipairs({'leaf_frames_drawn', 'leaf_drawn', 'leaf_put_back', 'leaf_blocks_worked'}) do
        poke('int64_t', base + OFF[name], 0)
    end
    poke('double', base + OFF.leaf_us_total, 0)
    poke('double', base + OFF.leaf_us_max, 0)
    for _, name in ipairs({'leaf_pool_full', 'leaf_kept_full', 'leaf_dropped'}) do poke('uint32_t', base + OFF[name], 0) end
    poke('uint32_t', base + OFF.install, 1)
    poke('uint32_t', base + OFF.leaf_on, 1)
    leaf_running_now = true
end

-- Handed back: the DLL puts back the game's own layers over the next two frames, and
-- detailed_weather.lua and leaves.lua draw them from their next frame.
local function wfog_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.wfog_on, 0) end
    wfog_running_now = false
end
local function leaf_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.leaf_on, 0) end
    leaf_running_now = false
end

-- Every frame (update): started or handed back; nothing drawn until this frame's numbers come (the
-- density and the shedding set to none here, so a frame detailed_weather.lua doesn't hand them over
-- draws nothing rather than an old frame's)
local function update_wfog()
    if not wfog_wanted or held then
        if wfog_running_now then wfog_hand_back() end
        return
    end
    if wfog_running_now then
        local base = block()
        if base then poke('int32_t', base + OFF.wfog_level, 0) end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < wfog_next_try then return end
    wfog_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then wfog_why_not = why return end
    local ok, problem = pcall(wfog_start, base)
    if ok then wfog_why_not = nil else wfog_why_not = tostring(problem) end
end
local function update_leaves()
    if not leaf_wanted or held then
        if leaf_running_now then leaf_hand_back() end
        return
    end
    if leaf_running_now then
        local base = block()
        if base then poke('uint32_t', base + OFF.leaf_any, 0) end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < leaf_next_try then return end
    leaf_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then leaf_why_not = why return end
    local ok, problem = pcall(leaf_start, base)
    if ok then leaf_why_not = nil else leaf_why_not = tostring(problem) end
end

function wfog_running() return wfog_running_now end
function leaves_running() return leaf_running_now end

-- Each frame, from detailed_weather.lua's overlay: f.level the density (0: no fog), which is also the
-- sheet's group; f.steps each depth's drift (0-based by depth), f.layout (art/fog_sheet.lua), f.sheet
-- the fog's (sheet_of), f.sheet_tiles, f.texpos_of.
function wfog_frame(f)
    if not wfog_running_now then return end
    local base = block()
    if not base then return end
    local L = f.layout
    local level = nil
    if f.level > 0 and f.sheet then
        if wfog_handed ~= f.sheet then
            poke('int32_t', base + OFF.wfog_patch, L.patch)
            poke('int32_t', base + OFF.wfog_frames, L.frames)
            wfog_handed = f.sheet
        end
        level = hand_group(base, wfog_held, OFF.wfog_tex_n, OFF.wfog_tex, WFOG_TEX, f.sheet, f.level,
                           L.levels * (L.substeps or 1) * L.patch * L.patch * L.frames, f)
    end
    if f.level <= 0 or not level then return end
    for d = 0, WFOG_DEPTHS - 1 do poke('int32_t', base + OFF.wfog_steps + d * 4, f.steps[d] or 0) end
    poke('int32_t', base + OFF.wfog_level, level)   -- (last: the DLL draws with this frame's drift)
end

-- Each frame, from detailed_weather.lua's overlay: f.specs what each tree raw sheds now ({sheet name,
-- heaviness}; nil out of season), f.frame the animation's frame, f.wind_index_for(layout), f.sheet_of(name)
-- (the art's layout and index), f.sheet_tiles (a group's textures, nil while its file waits), f.texpos_of.
function leaves_frame(f)
    if not leaf_running_now or not f.specs then return end
    local base = block()
    if not base then return end
    local wanted, wanted_sheets = {}, {}
    for raw, sp in pairs(f.specs) do
        local name, heaviness = sp[1], sp[2]
        local slot = leaf_handed[name]
        if not slot then
            local art = f.sheet_of(name)
            local L = art and art.layout
            local same = L and (not leaf_layout or (L.cells == leaf_layout.cells and L.frames == leaf_layout.frames
                and #L.winds == #leaf_layout.winds and L.heaviness == leaf_layout.heaviness))
            local count = 0
            for _ in pairs(leaf_handed) do count = count + 1 end
            if same and count < LEAF_SHEETS then
                local n = L.heaviness * #L.winds * L.cells * L.cells * L.frames
                slot = count + 1
                if n <= LEAF_TEX then
                    leaf_handed[name] = slot
                    leaf_held[name] = {sheet = art, held = {}, n = n}
                    if not leaf_layout then
                        leaf_layout = L
                        poke('int32_t', base + OFF.leaf_cells, L.cells)
                        poke('int32_t', base + OFF.leaf_frames, L.frames)
                        poke('int32_t', base + OFF.leaf_winds, #L.winds)
                        poke('int32_t', base + OFF.leaf_heavies, L.heaviness)
                    end
                else slot = nil end
            end
        end
        if slot and raw >= 0 and raw < LEAF_RAWS then wanted[raw] = slot | (heaviness << 8) wanted_sheets[name] = slot end
    end
    -- the specs written where they changed (a raw no longer shedding: 0)
    for raw in pairs(leaf_spec_sent) do
        if not wanted[raw] then poke('uint16_t', base + OFF.leaf_spec + raw * 2, 0) leaf_spec_sent[raw] = nil end
    end
    for raw, v in pairs(wanted) do
        if leaf_spec_sent[raw] ~= v then poke('uint16_t', base + OFF.leaf_spec + raw * 2, v) leaf_spec_sent[raw] = v end
    end
    if not leaf_layout then return end
    poke('int32_t', base + OFF.leaf_frame, f.frame % leaf_layout.frames)
    -- this wind's group of every sheet shedding now (a file a frame at most: sheet_tiles); the DLL
    -- keeps the wind before until they all have it, so no kind of leaf blinks off while it waits
    local wind, all_there = f.wind_index_for(leaf_layout), true
    for name, slot in pairs(wanted_sheets) do
        local kept = leaf_held[name]
        local drawn = hand_group(base, kept.held, OFF.leaf_tex_n + (slot - 1) * 4, OFF.leaf_tex + (slot - 1) * LEAF_TEX * 4,
                                 LEAF_TEX, kept.sheet, wind, kept.n, f)
        if drawn ~= wind then all_there = false end
    end
    if all_there or not leaf_wind_sent then leaf_wind_sent = wind end
    poke('int32_t', base + OFF.leaf_wind, leaf_wind_sent)
    poke('uint32_t', base + OFF.leaf_any, next(wanted) and 1 or 0)   -- (last)
end

local function report_wfog(base)
    local function u32(name) return peek('uint32_t', base + OFF[name]) end
    local frames = peek('int64_t', base + OFF.wfog_frames_drawn)
    print(('  frames drawn %d; the last: %d outdoor cells in view, %d given fog, %d left (the game or another overlay had something there)')
          :format(frames, u32('wfog_cells_last'), u32('wfog_drawn_last'), u32('wfog_taken_last')))
    print(('  summed: %d cells given fog, %d put back before the game drew again; list full %d times; put back entries let go %d')
          :format(peek('int64_t', base + OFF.wfog_drawn), peek('int64_t', base + OFF.wfog_put_back), u32('wfog_kept_full'), u32('wfog_dropped')))
    print(('  the sheet: %s'):format(wfog_handed and (peek('int32_t', base + OFF.wfog_tex_n) .. ' tiles handed over') or 'not handed over yet (no fog shown)'))
    if frames > 0 then
        print(('  drawing: %.1f us a frame on average, worst %.1f us')
              :format(peek('double', base + OFF.wfog_us_total) / frames, peek('double', base + OFF.wfog_us_max)))
    end
end
local function report_leaves(base)
    local function u32(name) return peek('uint32_t', base + OFF[name]) end
    local frames = peek('int64_t', base + OFF.leaf_frames_drawn)
    print(('  frames drawn %d; the last: %d cells under a tree that sheds, %d given a leaf or petal; map blocks worked out %d (%d the last frame), maps kept %d')
          :format(frames, u32('leaf_cells_last'), u32('leaf_drawn_last'), peek('int64_t', base + OFF.leaf_blocks_worked),
                  u32('leaf_worked_last'), u32('leaf_maps_kept')))
    print(('  summed: %d cells given a leaf or petal, %d put back before the game drew again; list full %d times; put back entries let go %d; maps all let go (pool full) %d; trees passed over (sizes past belief) %d')
          :format(peek('int64_t', base + OFF.leaf_drawn), peek('int64_t', base + OFF.leaf_put_back), u32('leaf_kept_full'),
                  u32('leaf_dropped'), u32('leaf_pool_full'), u32('leaf_trees_bad')))
    local names = {}
    for name, slot in pairs(leaf_handed) do names[#names + 1] = ('%s (%d tiles)'):format(name, peek('int32_t', base + OFF.leaf_tex_n + (slot - 1) * 4)) end
    table.sort(names)
    local shedding = 0
    for _ in pairs(leaf_spec_sent) do shedding = shedding + 1 end
    print(('  sheets handed over: %s; tree raws shedding now %d'):format(#names > 0 and table.concat(names, ', ') or 'none yet', shedding))
    if frames > 0 then
        print(('  drawing: %.1f us a frame on average, worst %.1f us (working out included)')
              :format(peek('double', base + OFF.leaf_us_total) / frames, peek('double', base + OFF.leaf_us_max)))
    end
end

-- ==========================================
-- THE SPATTER DRAWN BY THE DLL (test 15Y)
-- ==========================================
-- spatter.lua read the spatter layer every frame through DFHack (2.6 ms a frame in a snowy view), made its
-- thinned pieces and blades in Lua, and wrote both layers without putting them back. The DLL does all of it
-- now (detailed_weather_dll.cpp: THE SPATTER DRAWN HERE), painting into the blanks kept for the cracks. Lua
-- hands over which originals are grass (colour.lua's tables), the item spatter events' class and amounts'
-- place, and spatter.lua's two settings. It runs while the DLL swaps the colour (it needs the colour's copies
-- told apart from the game's own); without it spatter.lua draws it as before.
spat_wanted = spat_wanted ~= false        -- `native spatter` turns it off and on
spat_running_now = spat_running_now or false
spat_why_not = spat_why_not or nil
local spat_next_try = 0
spat_grass_for = spat_grass_for or nil    -- the colour state the grass table was written from
spat_grass_count = spat_grass_count or 0
local spatter_kept = nil
local function spatter_module()
    if spatter_kept then return spatter_kept end
    local ok, sp = pcall(reqscript, 'internal/detailed_weather/spatter')
    if not ok or not sp then return nil end
    spatter_kept = sp
    return sp
end

-- Which originals are grass (colour.lua's class), every one its tables point at, into the DLL's table
local function spat_fill_grass(base, col)
    local st = col.state
    if not st or not st.refs_of then return false end
    local tab = df.reinterpret_cast('uint8_t', peek('uint64_t', base + OFF.spat_grass))
    local most = peek('uint32_t', base + OFF.col_tex_map)
    local n = 0
    for t in pairs(st.refs_of) do
        if t > 0 and t < most then
            local grass = col.class_of(t) == 'grass'
            tab[t] = grass and 1 or 0
            if grass then n = n + 1 end
        end
    end
    spat_grass_for, spat_grass_count = st, n
    poke('uint32_t', base + OFF.spat_tables, (peek('uint32_t', base + OFF.spat_tables) + 1) & 0xffffffff)
    return true
end

local function spat_start(base)
    poke('uint32_t', base + OFF.spat_on, 0)
    local sp, col = spatter_module(), colour_module()
    if not sp or type(sp.apply) ~= 'function' or sp.native_spatter == nil then
        qerror('spatter.lua has no NATIVE SPATTER yet: apply its pairs first')
    end
    if not col or type(col.class_of) ~= 'function' then qerror('colour.lua not found') end
    fill_common(base)
    local vp = df.global.gps.main_viewport
    poke('uint32_t', base + OFF.off_spatter, addr_of(vp:_field('screentexpos_spatter')) - addr_of(vp))
    poke('uint32_t', base + OFF.off_item, addr_of(vp:_field('screentexpos_item')) - addr_of(vp))
    poke('uint32_t', base + OFF.off_background, addr_of(vp:_field('screentexpos_background')) - addr_of(vp))
    -- the item spatter events' class (their vtable: how the DLL tells them) and where their amounts are
    local isp = df.block_square_event_item_spatterst
    local vt = dfhack.internal.getVTable('block_square_event_item_spatterst')
    poke('uint64_t', base + OFF.spat_vtable, vt or 0)
    poke('uint32_t', base + OFF.off_isp_amount, isp._fields.amount.offset)
    -- (the blocks' event lists: fill_common)
    if not spat_fill_grass(base, col) then qerror('colour.lua has no tables yet') end
    for _, name in ipairs({'spat_frames', 'spat_written', 'spat_blades_written', 'spat_put_back', 'spat_painted'}) do
        poke('int64_t', base + OFF[name], 0)
    end
    for _, name in ipairs({'spat_us_total', 'spat_us_max', 'spat_paint_us_max'}) do poke('double', base + OFF[name], 0) end
    for _, name in ipairs({'spat_no_blank', 'spat_over_time', 'spat_unreadable', 'spat_bakes_full', 'spat_kept_full', 'spat_dropped'}) do
        poke('uint32_t', base + OFF[name], 0)
    end
    poke('uint32_t', base + OFF.install, 1)
    sp.native_spatter = true
    poke('uint32_t', base + OFF.spat_on, 1)
    spat_running_now = true
end

local function spat_hand_back()
    local base = block()
    if base then poke('uint32_t', base + OFF.spat_on, 0) end
    local sp = spatter_module()
    if sp then sp.native_spatter = false end
    spat_running_now = false
end

-- Every frame (update): started (while the DLL swaps the colour), handed back; spatter.lua's settings each
-- frame; the grass table again after the colour starts afresh; the blanks kept ready while the cracks don't
local function update_spatter()
    local sp = spatter_module()
    if not spat_wanted or held or not col_running or not sp then
        if spat_running_now then spat_hand_back() end
        return
    end
    if spat_running_now then
        local base = block()
        if not base then return end
        poke('uint32_t', base + OFF.spat_on, sp.mode == 'on' and 1 or 0)
        poke('uint32_t', base + OFF.spat_blades, sp.blades_mode ~= 'off' and 1 or 0)
        local col = colour_module()
        if col and col.state and col.state ~= spat_grass_for then spat_fill_grass(base, col) end
        if not crack_running then crack_blanks(base, BLANK_MS) end
        return
    end
    if not dfhack.isMapLoaded() or clock_s() < spat_next_try then return end
    spat_next_try = clock_s() + TRY_EVERY
    local base, why = block()
    if not base then spat_why_not = why return end
    local ok, problem = pcall(spat_start, base)
    if ok then spat_why_not = nil else spat_why_not = tostring(problem) end
end

local function report_spatter(base)
    local function u32(name) return peek('uint32_t', base + OFF[name]) end
    local function i64(name) return peek('int64_t', base + OFF[name]) end
    local frames = i64('spat_frames')
    print(('  frames drawn %d; the last: %d cells of spatter on grass, %d given theirs, %d left as the game drew them (not painted yet)')
          :format(frames, u32('spat_cells_last'), u32('spat_written_last'), u32('spat_waiting_last')))
    print(('  summed: %d cells given their spatter, %d their blades, %d put back before the game drew again; list full %d times; put back entries let go %d')
          :format(i64('spat_written'), i64('spat_blades_written'), i64('spat_put_back'), u32('spat_kept_full'), u32('spat_dropped')))
    print(('  textures painted here %d, %d known (all let go %d times); put off: no blank %d, out of time %d; pixels unreadable %d')
          :format(i64('spat_painted'), u32('spat_bakes_kept'), u32('spat_bakes_full'), u32('spat_no_blank'), u32('spat_over_time'), u32('spat_unreadable')))
    print(('  grass originals %d; item spatter %s'):format(spat_grass_count,
          peek('uint64_t', base + OFF.spat_vtable) ~= 0 and 'told apart by its class' or 'NOT known (its class not found): all of it drawn'))
    if frames > 0 then
        print(('  drawing: %.1f us a frame on average, worst %.1f us; painting at most %.1f us a frame')
              :format(peek('double', base + OFF.spat_us_total) / frames, peek('double', base + OFF.spat_us_max), peek('double', base + OFF.spat_paint_us_max)))
    end
end

-- Syncs the DLL's drawn view corner after currentscreen->render() (catches ZScreens like
-- gui/reveal that move window_x/y after dfhooks_prerender).
function sync_view()
    if not dfhack.isMapLoaded() then return end
    local base = block()
    if not base then return end
    poke('int32_t', base + OFF.drawn_x, df.global.window_x)
    poke('int32_t', base + OFF.drawn_y, df.global.window_y)
    poke('int32_t', base + OFF.drawn_z, df.global.window_z)
    poke('uint32_t', base + OFF.have_drawn, 1)
end

-- Every frame, from detailed_weather.lua's overlay: `snow_on` is the ramps setting. (The colour goes
-- by colour.lua's own settings: update_colour.)
function update(snow_on)
    if not rain_clock.loaded and dfhack.isMapLoaded() then rain_clock.loaded = clock_s() end   -- (RAIN: THE START, TIMED)
    timed_part('colour', update_colour)
    timed_part('shade', update_shade)
    timed_part('murky', update_murky)
    timed_part('paths', update_paths)
    timed_part('fog', update_fog)
    timed_part('rain', update_rain)
    timed_part('cracks', update_cracks)   -- (CRACKS IN PLACE: after the colour, which it needs running)
    timed_part('wfog', update_wfog)       -- (THE FOG AND THE LEAVES DRAWN HERE, 15X)
    timed_part('leaves', update_leaves)
    timed_part('spatter', update_spatter)  -- (THE SPATTER DRAWN HERE, 15Y: after the colour, which it needs running)
    timed_part('snow', update_snow, snow_on)
end

-- A world unloading: its textures and map go with it, so the snow and the colour are handed back,
-- and the next map starts afresh.
function forget_world()
    if running then hand_back() end
    if col_running or col_emptying then colour_hand_back() end
    if shade_running then shade_hand_back() end
    if murky_running then murky_hand_back() end
    if paths_running then paths_hand_back() end
    if fog_running then fog_hand_back() end
    if rain_running_now then rain_hand_back() end
    if crack_running then crack_hand_back() end
    if wfog_running_now then wfog_hand_back() end
    if leaf_running_now then leaf_hand_back() end
    if spat_running_now then spat_hand_back() end
    -- (CRACKS IN PLACE: the next world's texture numbers may be other pictures: every cracked copy forgotten)
    local base = block()
    if base then poke('uint32_t', base + OFF.crack_world, (peek('uint32_t', base + OFF.crack_world) + 1) & 0xffffffff) end
    rain_clock = {}   -- (the next map's start timed afresh)
    started_note, next_try = nil, 0
    col_note, col_next_try, shade_next_try, fog_next_try = nil, 0, 0, 0
    rain_next_try, crack_next_try = 0, 0
    wfog_next_try, leaf_next_try, spat_next_try = 0, 0, 0
end

-- `detailed_weather native [stop|start|fog|rain|wfog|leaves|spatter]`
function command(how)
    if how == 'stop' then
        held = true
        hand_back()
        if col_running or col_emptying then colour_hand_back() end
        if shade_running then shade_hand_back() end
        if murky_running then murky_hand_back() end
        if paths_running then paths_hand_back() end
        if fog_running then fog_hand_back() end
        if rain_running_now then rain_hand_back() end
        if crack_running then crack_hand_back() end
        if wfog_running_now then wfog_hand_back() end
        if leaf_running_now then leaf_hand_back() end
        if spat_running_now then spat_hand_back() end
    elseif how == 'start' then
        held, next_try, col_next_try, shade_next_try, murky_next_try, paths_next_try = false, 0, 0, 0, 0, 0
        fog_next_try, rain_next_try, crack_next_try, wfog_next_try, leaf_next_try, spat_next_try = 0, 0, 0, 0, 0, 0
        print('native snow, colour and shade: start on the next frame.')
        return
    elseif how == 'fog' then   -- (FOG OVER WATER: off and on, to compare with the game's own hazes)
        fog_wanted, fog_next_try = not fog_wanted, 0
        print(fog_wanted and 'native fog over water: on from the next frame.'
              or 'native fog over water: off; the game\'s own hazes are back within two frames.')
        return
    elseif how == 'wfog' then   -- (THE FOG DRAWN HERE: handed back to detailed_weather.lua and taken again)
        wfog_wanted, wfog_next_try = not wfog_wanted, 0
        print(wfog_wanted and 'native fog: drawn by the DLL from the next frame.'
              or 'native fog: handed back; detailed_weather.lua draws it from the next frame.')
        return
    elseif how == 'leaves' then   -- (THE LEAVES DRAWN HERE: handed back to leaves.lua and taken again)
        leaf_wanted, leaf_next_try = not leaf_wanted, 0
        print(leaf_wanted and 'native leaves and petals: drawn by the DLL from the next frame.'
              or 'native leaves and petals: handed back; leaves.lua draws them from the next frame.')
        return
    elseif how == 'spatter' then   -- (THE SPATTER DRAWN HERE: handed back to spatter.lua and taken again)
        spat_wanted, spat_next_try = not spat_wanted, 0
        print(spat_wanted and 'native spatter: drawn by the DLL from the next frame.'
              or 'native spatter: handed back; spatter.lua draws it from the next frame.')
        return
    elseif how == 'rain' then   -- (RAIN AND SNOW FALLING: handed back to detailed_weather.lua and taken again)
        rain_wanted, rain_next_try = not rain_wanted, 0
        print(rain_wanted and 'native rain and snow falling: drawn by the DLL from the next frame.'
              or 'native rain and snow falling: handed back; detailed_weather.lua draws them from the next frame.')
        return
    end
    local base, why = block()
    if not base then print('native snow: off, ' .. why .. '; snow_ramps.lua draws the snow.') return end
    if held then print('native snow: stopped (native start to start it again); snow_ramps.lua draws the snow.') end
    if not running and not held then print('native snow: not running' .. (why_not and (': ' .. why_not) or '') .. '.') end
    if started_note then print('  ' .. started_note) end
    report(base)
    -- the colour
    local col = colour_module()
    if col_running then print('native colour: swapping colour.lua\'s tiles')
    elseif col_emptying then print('native colour: starting (waiting for the DLL to empty its tables)')
    elseif held then print('native colour: stopped (native start to start it again); colour.lua swaps the tiles.')
    else print('native colour: not running' .. (col_why_not and (': ' .. col_why_not) or ' (colour or its trees setting is off)') .. '.') end
    if col_running and col_note then print('  ' .. col_note) end
    if col_running then report_colour(base, col) end
    -- the shade
    if shade_running then print('native shade: drawing shade.lua\'s shade')
    elseif held then print('native shade: stopped (native start to start it again); shade.lua draws it.')
    else print('native shade: not running' .. (shade_why_not and (': ' .. shade_why_not) or ' (the shade setting is off)') .. '.') end
    if shade_running then report_shade(base) end
    -- murky water
    if murky_running then print('native murky water: drawing murky.lua\'s tint')
    elseif held then print('native murky water: stopped; murky.lua draws it.')
    else print('native murky water: not running' .. (murky_why_not and (': ' .. murky_why_not) or ' (the murky setting is off)') .. '.') end
    if murky_running then report_murky(base) end
    -- worn paths
    if paths_running then print('native paths: drawing paths.lua\'s worn paths')
    elseif held then print('native paths: stopped; paths.lua draws them.')
    else print('native paths: not running' .. (paths_why_not and (': ' .. paths_why_not) or ' (the paths setting is off)') .. '.') end
    if paths_running then report_paths(base) end
    -- fog over water
    if fog_running then print('native fog over water: deep water hazed as its surface\'s level')
    elseif held then print('native fog over water: stopped; the game\'s own hazes.')
    elseif not fog_wanted then print('native fog over water: off (native fog to turn it on); the game\'s own hazes.')
    else print('native fog over water: not running' .. (fog_why_not and (': ' .. fog_why_not) or '') .. '.') end
    if fog_running and fog_note then print('  ' .. fog_note) end
    if fog_running then report_fog(base) end
    -- the rain and snow falling
    if rain_running_now then print('native rain and snow falling: drawn by the DLL')
    elseif held then print('native rain and snow falling: stopped; detailed_weather.lua draws them.')
    elseif not rain_wanted then print('native rain and snow falling: off (native rain to turn it on); detailed_weather.lua draws them.')
    else print('native rain and snow falling: not running' .. (rain_why_not and (': ' .. rain_why_not) or '') .. '.') end
    if rain_running_now then report_rain(base) end
    -- frost's dry cracks
    if crack_running then print('native cracks: frost.lua\'s dry cracks put in by the DLL')
    elseif held then print('native cracks: stopped; frost.lua puts them in.')
    else print('native cracks: not running' .. (crack_why_not and (': ' .. crack_why_not) or ' (the native colour isn\'t running)') .. '.') end
    if crack_running then report_cracks(base) end
    -- the fog, and the leaves and petals falling (15X)
    if wfog_running_now then print('native fog: drawn by the DLL')
    elseif held then print('native fog: stopped; detailed_weather.lua draws it.')
    elseif not wfog_wanted then print('native fog: off (native wfog to turn it on); detailed_weather.lua draws it.')
    else print('native fog: not running' .. (wfog_why_not and (': ' .. wfog_why_not) or '') .. '.') end
    if wfog_running_now then report_wfog(base) end
    if leaf_running_now then print('native leaves and petals: drawn by the DLL')
    elseif held then print('native leaves and petals: stopped; leaves.lua draws them.')
    elseif not leaf_wanted then print('native leaves and petals: off (native leaves to turn them on); leaves.lua draws them.')
    else print('native leaves and petals: not running' .. (leaf_why_not and (': ' .. leaf_why_not) or '') .. '.') end
    if leaf_running_now then report_leaves(base) end
    -- the spatter in the grass (15Y)
    if spat_running_now then print('native spatter: drawn by the DLL')
    elseif held then print('native spatter: stopped; spatter.lua draws it.')
    elseif not spat_wanted then print('native spatter: off (native spatter to turn it on); spatter.lua draws it.')
    else print('native spatter: not running' .. (spat_why_not and (': ' .. spat_why_not) or ' (the native colour isn\'t running)') .. '.') end
    if spat_running_now then report_spatter(base) end
    report_parts()
end