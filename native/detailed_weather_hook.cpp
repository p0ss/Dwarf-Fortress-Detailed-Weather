// detailed_weather_dll.cpp
// =====================================================================
// DETAILED WEATHER'S NATIVE DRAWING HOOK
// DLL, layout 38: TEST 16A, the rustle painted and the grass's gust wave drawn here (2026-11-20)
// =====================================================================
// WHAT: a standalone DLL that DF loads through its dfhooks chain loader
// (any dfhooks_<name>.dll in DF's folder), the same way Stockhook loads.
// Test 4 draws all of snow_ramps.lua's snow: snowy ramps, snowy floors and
// their thin snow, joins, skirts and overhangs, snowy edges and corners,
// trunks, and what lies on the snow (THE SNOW, below). Every frame it
// works out every tile in view from the map, on the view's own level and
// every level seen below, and writes at the last moment before the game
// reads the screen. snow_ramps.lua works nothing out while its native_snow
// is on, and only bakes the textures this asks for (THE BAKES).
//
// IN PLAY:
//   * TEST 1 (2026-11-17), a square written over map tiles: hooked; held
//     through pans; 0.56 us a frame. Showed as bare grass (the blood
//     page's last cell is empty, and DF's own snow is in the same layer),
//     on the view's level only, and jittered on fast zooms;
//   * TEST 1B: with the page's full tile (vanilla graphics_spatters.txt:
//     BLOOD_CYAN 0:0), every level below written too, and the view's
//     corner read before DF draws (THE VIEW AS DRAWN): cyan on every
//     level, no shift or flicker through fast zooms; the view had moved
//     after DF drew it on 19 of 3257 frames;
//   * TEST 2: every revealed ramp marked from the map, every frame: all
//     there the moment they came into view, no drawing in, no stutter.
//     73440 viewport cells on 9 levels worked out in 225.7 us a frame
//     (against 9 to 19 us a tile in Lua). The levels below were drawn on
//     every frame, the frames of a move included, and showed nothing
//     wrong: the Lua's holding back of the levels below on the frame of a
//     move (snow_ramps.lua: UNDRAWN CELLS) is not carried over;
//   * TEST 3: the snowy ramps drawn here instead of by snow_ramps.lua,
//     looking the same ("Perfect"): 414 snowy ramps on 9 levels, 258.7 us
//     a frame to work out, 6.7 us to draw;
//   * TEST 4 (layout 5): all of the snow, drawn without fail everywhere,
//     nothing drawing in but the snowy edges, waiting on their bakes at 6
//     a frame (1993 asked, the ring full 8452 times; SNOWY EDGES AT ONCE).
//     8160 columns, 2988 snowy floors: 1113 us a frame to work out (worst
//     3566), 331 us to draw; 3.4 MB held. (The edges had never been drawn
//     before: grass.lua found no graphics files on Windows.)
//   * TEST 4B to 4D (layouts 6 and 7): snowy edges drawn at once (pieces
//     baked at start, edges kept on disk), trunks above the ground, and
//     blocks kept between frames: 333 us a frame to work out, worst 1302.
//   * TEST 5 (layout 8): colour.lua's per-tile swaps (THE COLOUR, below):
//     looking right through looks changes, workshops, items, zooms and
//     level changes; underground put back. 89 to 143 us a frame (Lua's
//     about 3 ms), 3690 questions all answered; over 11289 frames only
//     102 cells showed the game's colours for a frame while one waited.
//   * TEST 5B (layout 9): the trees' sway in wind (SWAY, below): trees and
//     grass swaying as before; 78 us a frame for all the colour.
//   * TEST 6 (layout 10): shade.lua's shade (THE SHADE, below): 28 us a
//     frame. The trees still drew in on the first view after loading: it
//     was colour's first copies (179 put off at 0.5 ms each in Lua).
//   * TEST 7 (layout 11): colour's per-tile copies painted here (PAINTING):
//     2342 painted, but 229 refused by a one-region readable check, left
//     blank on screen (the trees and ramps below drawing); 7B checks each
//     region the pixels span (readable_span).
//   * TEST 8 (colour.lua only): the trees' own pieces built first and
//     painted here. The trees "drawing in" since 5B were the wet look
//     making late changes visible (8% darker at average wetness, 16% at
//     wet, lighter when dry), not a regression.
//   * TEST 9 (layout 12): looks.lua's whole redraw with its dry and wet
//     effects (THE FULL REDRAW), for colour's ground copies and frost's
//     ramps: about 5 ms a copy in Lua in a wet look.
//   * TEST 14 (layout 13): murky.lua's tint over stagnant water (MURKY).
//     14B: the levels below into the spatter layer: not seen either.
//     14C: into the view's own designation layer: seen, but over the banks'
//     overhangs. 14D: the view's own ground layer: never empty there.
//     14E: the view's own layer above the spatter: seen, edges over it.
//     14F: there, over the water's own ripple too.
//     14G (layout 14): the banks' overhangs drawn back over the tint
//     (MURKY: EDGES OVER THE TINT).
//     14I (layout 15): what each frame's murky cells got, kept when it
//     changes (MURKY: FRAME BY FRAME), to see why the edges come late.
//     14J: the old bakes forgotten in tidy itself, so the first frame has
//     its edges (they waited a frame for the game thread, and the snow's
//     start, the frame after, held that frame on screen for seconds);
//     and (layout 16) a ring of 256 blanks, so a whole view's are ready.
//   15A (layout 17, no new fields): RAMPS IN THE LOOK (THE COLOUR). A ramp
//     is a picture the game puts together itself, which the tables never
//     reach, so frost.lua redrew each for the look in Lua, tile by tile, a
//     frame. Now the swap here takes them too: a ramp cell in the ground
//     layer is asked about with its class (grass, dirt or stone, from the
//     tiletype's material) and gets colour.lua's copy, made, kept by
//     picture, and made ahead for the next look as its other copies are.
//     To the ninth level down, as frost.lua went (the other layers to the
//     third, as before).
//   15B (layout 18): PATHS. paths.lua's worn paths through grass, worked
//     out and drawn here: the grass read from the map blocks (in the
//     prerender call, on the game thread), each worn tile's track and wash
//     worked out as paths.lua does, painted into blank textures Lua keeps
//     ready (the murky edges' ring, shared), and written in the ground
//     layer (in the hook). Lua only finds the soil to draw and says where
//     each grass picture's steady pixels are.
//   15C: MURKY: EDGES OVER THE TINT from every level between the view's
//     and the water's (seen from two levels up, the banks' edges are in a
//     lower viewport's floor_flag, and the tint covered them).
//   15D (layout 19): MURKY: THE HAZE. The game draws a see-through blue
//     haze (MULTILEVEL_AIR) in the ground layer of each open cell a lower
//     level is seen through, under that level's edges: each level down is
//     hazed once more. The tint goes in the view's layer above all that, so
//     it and the edges laid over it showed with no haze. Now each level's
//     haze goes over the tint too, then that level's edges, as the game
//     stacks them: the tint as if in the water, the rest as drawn.
//   15E (layout 20): the haze open air shows is colour.lua's copy of it (the
//     game draws it through the tables), so the DLL asks Lua about each
//     texture it meets there (THE HAZE: the rings), and Lua says whether
//     it's the haze page's, or a copy of one, with its pixels. And murky
//     water is drawn to 8 levels down (murky.lua drew 3), now its tint
//     takes each level's haze as the rest of that level does.
//   15F (layout 21): no texture in open air's ground layer was the haze
//     (15E: 0 of 80; the cell over the water holds the water's surface,
//     RIVER), so the game draws it some other way. It's laid here from
//     MULTILEVEL_AIR's own pixels (Lua finds them by graphics token), once
//     for each open level above the water, under that level's edges. And a
//     probe: one cell's layers on each level, for the report (MURKY: THE
//     PROBE), to see where the game keeps the haze.
//   15G: the probe showed the level just above the water holds the water's
//     surface (its ground layer) and the banks' edges (its floor_flag),
//     as the view's level does for water one level down, and no haze in any
//     layer (15H: wrong, the probe never read the interface layer, which
//     holds it). So the tint goes in that level's own layer above the ground
//     (its bg2), with that level's edges laid over it, as for water one level
//     down. The game then hazes it with the rest of that level, and draws the
//     levels above over it, their edges included. MULTILEVEL_AIR is no
//     longer laid here.
//   15H (layout 22): branches over the river and the pond were hazed a step
//     more than branches beside them on the same level, and the banks' edges
//     over the water too. The game lays one haze a cell, by the level at the
//     bottom of the cell, and water's bottom is a level under its surface
//     (FOG OVER WATER). Such cells now get the haze of their surface's level.
//     In play: the seams gone; the game's haze is one a cell, all in the
//     level just below the view's (the census: 1296 cells, none with two),
//     197 of 197 water cells set; 4 us planning, 4.5 us setting a frame.
//   15I (still layout 22): the snow's plan took 241 us a frame on a view
//     with no snow at all: every block it read was fingerprinted (2 to 3 KB
//     hashed each, BLOCKS KEPT). Now a block is fingerprinted only when a
//     kept block needs it, and a block with no SNOWY tile in it or the 8
//     round it gets no rules at all, only where the walk goes on down (NO
//     SNOW NEAR). The same records and screens in every simulated case.
//     In play: 60.8 us a frame (from 241) on a view 6 times bigger.
//   15K (layout 23): colour.lua checked, about 70 times a frame, that each
//     copy in view still showed the picture it was made from (16 sampled
//     pixels, through DFHack: about 1.3 ms a frame, the biggest Lua stage
//     left). The DLL now keeps each verified picture's fingerprint and
//     checks it itself (PICTURES CHECKED HERE); only a changed one goes to
//     colour.lua.
//   15L (layout 24): ramps and banks flipped between the game's picture
//     and their copy while panning a freshly revealed map (in play,
//     2026-11-20: 27,602 cells, summed, showed the game's picture while a
//     question waited; only 41 kept last frame's copy). HELD emptied every
//     held copy whenever the view moved, so a pan held nothing. HELD is now
//     kept by map tile (THE HELD SLOTS), through pans and level changes,
//     and on the levels of ramps alone too, which had no hold at all. New
//     counters split the waits: tiles new to the view, tiles shown last
//     frame with no copy held, and holds only possible since the view moved.
//   15M (layout 25): the rain and snow falling (RAIN AND SNOW FALLING).
//     detailed_weather.lua found every outdoor tile in view where it rained
//     or snowed, as a Lua table, four times a second and on every frame the
//     view moved (in play, 2026-11-20: 4.6 to 6.5 ms a rescan), and wrote
//     each one's sheet tile every frame (most of the "untimed" 2.7 to 3.9
//     ms a frame while raining). It wrote the game's flow layer and never
//     put it back. Now the DLL works out those tiles and draws them in the
//     hook, with put back; Lua hands over the sheets, the weather by map
//     block, and each frame's slant and animation frame.
//     In play: drawing 38.4 us a frame, the overlay 1.12 ms a frame (from
//     8 to 10), rain rescans 0.0 ms. But the put back list was found full
//     6,974,433 times in 24,105 frames, leaving cells undrawn (THE LIST).
//   15N (still layout 25; pad12 became rain_dropped): THE LIST. Entries for
//     arrays that were neither of the main viewport's buffers stayed in it
//     for good (put back only ever matched the buffer about to be drawn),
//     so it filled. Now only the last frame's written arrays are kept; any
//     other entry is let go without touching its array, and counted.
//     In play: list full 0; 802 entries let go.
//   15O (layout 26: PaintJob's last bytes): frost.lua's dry cracks painted
//     here (DRY CRACKS). In a dry look frost baked each cracked floor and
//     ramp in Lua: 2.05 to 3.50 ms a bake, hundreds of them (in play,
//     2026-11-20, a dry hot look: 301 to 389 bakes, 912 ramps waiting on
//     theirs with the game's colours showing, frost-draw 3.7 to 3.8 ms a
//     frame). A paint job can now ask for the cracks after its redraw.
//     In play: 0.03 to 0.04 ms a bake; ramps waiting 45 to 82; Lua memory
//     152 to 198 MB (from 347 to 432); overlay 2.5 ms (from 5.3 to 6).
//   15P (layout 27): BRANCHES PROBED (MURKY). Stagnant water seen through
//     a tree's branches or leaves wasn't tinted (seen in play, 2026-11-20):
//     murky.lua looked down through open space only, and the game shows the
//     levels below branches and leaves (15H). Before drawing there, which
//     layer holds the branch and where the water's surface is drawn under
//     it isn't known; this counts such water and probes one cell of it.
//     In play: 48 cells in view (50,544 summed); the probe, water 2 down
//     under a willow branch on the view's level: the branch in that level's
//     background_two; on the level between, the water's surface (RIVER) in
//     background, the banks' edges, the haze; its background_two empty.
//   15Q (layout 28): BRANCHES SEEN THROUGH (MURKY). The tint goes where the
//     open-air case puts it (background_two of the level just above the
//     water), below the branch's own level, so the branch draws over it as
//     over the river. Left untinted, counted and probed: water with a branch
//     or leaves on the level just above it, where the tint's layer may hold
//     the branch itself.
//     In play: 30,354 cells tinted through branches, none left; "looks good".
//   15R (layout 29): CRACKS IN PLACE. frost.lua still went over every
//     listed tile in a dry look, every frame, to put the cracked floors and
//     ramps in (frost-draw 1.35 to 1.84 ms a frame after 15O). frost.lua now
//     only works out which map tiles may crack (as before) and hands them
//     over; the DLL puts each one's cracked copy in, by what the game drew
//     there and the tile's piece of the heat patterns, asking frost.lua for
//     the copies it hasn't got.
//     In play: frost-draw 1.35 to 1.84 ms to 0.09 ms a frame; placing 70 us a frame. BUT ramps showed
//     the look's uncracked copy for a moment on first sight ("first view drawing").
//   15S (layout 30): THE RAMP HELD and THE TILES KEPT (CRACKS IN PLACE). A ramp waiting for its copy
//     under a new number keeps the cracked copy it showed last; the tiles are kept by level and block
//     with no most (the hash forgot them all when full, and frost.lua with it).
//     In play: 39 ramps held; frost.lua still forgot its tiles 7 times (REMEMBER_MOST), each clearing the
//     DLL's too; the cracks still came in tile by tile on a change to a dry look.
//   15T (layout 31): THE NEXT LOOK AHEAD (CRACKS IN PLACE). While colour.lua makes the next look, the
//     cells in view ask for that look's cracked copies too, and colour.lua waits for them before it
//     shows the look, so the cracks come with it. frost.lua's forgetting no longer clears the tiles here.
//     In play: cracks came with the change of look; ramps still drew in when panning in a dry look, never
//     in a wet one.
//   15U (layout 32): THE TILES WORKED OUT (CRACKS IN PLACE). Which tiles may crack is worked out here from
//     the map, a block at a time when first drawn, by frost.lua's rules, as THE COLOUR does its ramps:
//     no tile waits on Lua. frost.lua no longer plans in native mode; the ring of tiles is gone.
//     In play: frost-plan 0.01 ms; ramps still drew in when panning in a dry look.
//   15V (layout 33): THE PAINTING HERE, PICTURES, NOT NUMBERS (CRACKS IN PLACE). The copies were asked of
//     frost.lua and placed the frame after; a picture has 16 (one a piece), so panning kept finding ones
//     not made. Each is painted here in the frame it's first needed, from blanks Lua keeps ready, and kept
//     by picture, so a ramp's new number finds its copies. The question and answer rings are gone.
//     FLOORS AHEAD: the next look's floors are painted from the next look's own copy of their ground (each
//     look lists them, frost.lua from colour.lua's), so they're ready when it shows. Nothing is placed in
//     the frame Lua starts a new world, before the next prerender forgets the last one's (a stale copy was
//     placed there in the harness).
//     In play: "good enough"; overlay 1.14 ms a frame (stages 1.95, starts in); cracks placed 371 us a frame,
//     1,167 cells uncracked a frame while the frame's painting time was up (the first views); 233 grounds
//     that crack.
//   15W (layout 33): MURKY: FRAME BY FRAME records the view's level and the levels DF shows. (colour.lua no
//     longer reads the screen while the DLL answers it: its questions bring the new textures.)
//     In play: the colour stage 0.74 to 0.18 ms a frame; forced on, thick fog 2.56 ms a frame drawing and
//     2.8 ms a rescan, leaves and petals 1.58 to 1.72 ms a frame, all in Lua.
//   15X (layout 34): THE FOG AND THE LEAVES DRAWN HERE. detailed_weather.lua's fog (the main view's interface
//     layer, as its overlay painted it) and leaves.lua's falling leaves and petals (projectile) worked out
//     from the map and drawn each frame, with put back; Lua hands over the sheets once, and each frame the
//     fog's density and drift and what each tree raw is shedding. The leaves' trees found from DFHack's
//     plants (column_index, tree_info's body) as getPlantAtTile does.
//     In play (forced on): fog 31.9 us a frame for 1,978 outdoor cells, its Lua 0.03 ms; leaves and petals
//     18.9 us for 1,017 cells under shedding trees, their Lua 0.03 ms, but a 444 ms frame when the sheets
//     loaded (detailed_weather.lua: sheet_of timed its 100 ms between loads from a load's start).
//   15Y (layout 35): THE SPATTER DRAWN HERE. spatter.lua's spatter in the grass (thinned by the amount
//     fallen, shadowed; the grass's blades in front) worked out, painted and drawn here with put back; the
//     fallen amounts read in the prerender call. Lua hands over the grass originals and the item spatter
//     events' class. (sheet_of now times from a load's end: at most one sheet a frame.)
//   15Z (layout 36): THE WAITS TAKEN OUT. 15Y's report: 43,721 worn path cells and 20,640 colour cells
//     summed over the frames left as the game drew them while something was made; the snow's edges
//     baked in Lua at start (part of a 2.4 s freeze at load) and a few a frame after; and the colour's
//     pixel work for a change of look done in Lua (its sheet stage alone 50 frames). Now:
//     * PATHS HELD: each worn tile keeps the painting last drawn on it and shows that while its new one
//       waits (a new look's grass being asked about, no blank, the frame's painting time used up). New
//       paintings within 1.5 ms a frame (the worst frame was 4.6 ms). The list of grass pictures starts
//       over when full: it was never emptied, so once full every new picture was left undrawn for good. The
//       paintings are kept in two halves, so a full list no longer paints the whole screen again at once.
//     * BY PICTURE: a texture the colour hasn't answered yet whose picture already has a copy in the look
//       shown (the game hands freed numbers to the same pictures as the view moves) gets that copy in the
//       same frame. Each screen copy painted here is filed by its original's picture.
//     * THE SNOW'S BAKES HERE: thin snow faded, a piece with something over it and a snowy edge are
//       painted in the hook the moment one is wanted, into the shared blanks, and told to Lua after so
//       frost and the colour know them. Lua bakes one only when no blank is ready, and none at start.
//     * THE LOOK'S PIXEL WORK HERE: the sheet's partly see-through textures (their alpha divided back
//       out) and the grass's lean frames are painted here, as jobs in the colour's ring.
//   16A (layout 37): THE RUSTLE PAINTED HERE. In wind colour.lua made every leafy tree picture's 16
//     rustle frames, and the grass's, in Lua: each picture's pixels read through DFHack and kept (15Z's
//     report: 373 pictures, about 50 MB of Lua's memory), then each frame moved pixel by pixel, within
//     1.5 ms a frame for as long as it took. Lua now works out only which clumps move in a frame (14 of
//     them, from its own clump layout, handed over once) and sends the frame as a job (PJ_RUSTLE); the
//     pixels are moved here. Whether a tree picture is leaves or wood (wood doesn't rustle) is worked
//     out here too, as each is listed for its frames (SEEN_WOOD), so Lua never reads its pixels.
//     15Z, as built: five std::min calls broke under MSVC (windows.h's min and max macros); written out.
//     (layout 38) THE GRASS WAVE DRAWN HERE: in wind colour.lua's grass_wave read every cell of the main
//     view's ground layer through DFHack each frame and wrote each grass tile its own lean (the gust as
//     it was a moment earlier or later, by how far downwind the tile is) and rustle frame: about 0.5 ms
//     of Lua a frame in 15Z's report (colour-screen 0.86 ms in a breeze, 0.31 to 0.46 calm). The same
//     rules here: Lua hands over each grass picture's lean frames and rustle frames (in slots), the
//     gusts' lean as it keeps it (lean_history), and each frame's numbers; rustle frames not made yet
//     are asked of Lua, which sends each as a PJ_RUSTLE job.
//
//
// WHY NATIVE: the Lua version redraws thousands of tiles over the game's
// screen every frame, through DFHack, at 9 to 19 us a tile worked out
// (details, 2026-11-17: "snow costs"). That one design gave all three
// problems at once: about 15 ms of Lua a frame (lag), several frames to
// work out a new view (tiles drawing in), and every result kept to avoid
// working it out again (4 to 7 GB). Native code reads and writes the same
// memory directly, so a whole screen can be worked out and written inside
// one frame, keeping only small fixed tables.
//
// THE FRAME, AS DF RUNS IT (g_src, Putnam3145/Dwarf-Fortress--libgraphics--):
//   game thread, the render command (enabler.cpp):
//       renderer->swap_arrays()      every viewport buffer swapped with its
//                                    _old twin (STILL OURS, below)
//       render_things() (graphics.cpp):
//           hooks_prerender()        <- the chain loader's per-frame call
//           currentscreen->render()  DF fills the screen buffers
//           widgets.render()         DFHack's overlays (the Lua mod)
//   main thread, enablerst::do_frame() (enabler.cpp), after waiting for
//   the game thread to finish render_things:
//       reshape_viewports()          only on a zoom: buffers remade
//       renderer->tidy_tile_cache()  <- THE HOOK: a virtual function
//       renderer->display()          the buffers are read and drawn
// render_things is called from one place only, and the next render
// command is only sent after display, so the prerender call and the
// renderer call alternate strictly and never overlap. On a zoom DF skips
// that frame's tidy and display (must_do_render_things_before_display)
// until it has drawn into the new buffers.
//
// THE SLOT: tidy_tile_cache is the 12th virtual function of class renderer
// (index 11), in g_src's enabler.h and DFHack's df.g_src.enabler.xml
// (2026-11-09) alike. display() itself is not virtual, which is why the
// call just before it is the one hooked.
//
// PLAN AND WRITE: the work is split across the two calls.
//   * PLAN, in the prerender call, on the game thread: reads the view's
//     corner, the viewports and the map, and makes a record for each tile
//     that has snow to draw, with everything about it the map decides.
//     The game thread is the one that changes and unloads the map, so the
//     map is never read mid-change or mid-unload.
//   * WRITE, in the hook, on the main thread, after DF has drawn: reads
//     what DF drew in each recorded cell and its neighbours (some of the
//     choice depends on it: a ramp's walls, a floor's overhangs, the
//     game's own snow piece, what lies on it), decides everything first,
//     then writes. No map is read there.
// A plan is only written into the viewports it was made for, at the size
// it was made for; anything else and the frame is left as DF drew it.
//
// STILL OURS: what a buffer cell holds. Three facts decide it:
//   * swap_arrays swaps every viewport buffer with its _old twin each
//     frame, so there are two buffers per viewport, used in turn;
//   * DF doesn't redraw every cell every frame (snow_ramps.lua met it:
//     STILL OURS), so a cell it left holds what that same buffer held two
//     frames ago, this DLL's writes included, sometimes only some layers;
//   * the renderer only redraws a screen tile whose layers differ from
//     the _old twin's (g_src enabler.cpp, renderer::display: the per-cell
//     compare before update_viewport_tile), so a tile left alone on
//     screen keeps showing what was last drawn there.
// Reading a cell back and guessing which layers DF redrew can't work: DF
// can redraw a layer to the very value this wrote (no overhang, no skirt)
// and nothing tells the two apart (a simulation showed it: a wall left
// with a grass overhang put back on it). So this never leaves its writes
// for DF to find. PUT BACK: in the prerender call, before DF draws, every
// cell this changed in the buffer DF is about to draw (the one it wrote
// two frames ago) gets the game's own values back, as read just before
// that write. DF, and the overlays after it, only ever find their own
// drawing in the buffers, so what the hook reads is theirs alone, however
// much or little DF redraws. The other buffer keeps the snow until its own
// turn, so the renderer, comparing the two, still finds snow beside snow
// and redraws nothing that hasn't changed. Turning the snow off is the
// same put back, a buffer a frame. Only the changed cells are kept (their
// place and the game's five values), for the two buffers of each level.
// A zoom remakes the buffers: DF draws them afresh and the kept cells are
// dropped. At start a cell can still show the Lua's own drawing where DF
// hasn't redrawn it since; it's left as it is until DF does.
// (Simulated, check/sim.cpp: DF redrawing everything, only the layers that
// changed, or those and random others, gave the same screen frame for
// frame, through melts, falling fruit, pans, level changes and a zoom; and
// the game's own drawing everywhere two frames after turning it off.)
//
// THE BAKES: three textures need createTile, which only Lua can call:
// thin snow faded towards full snow, a snow piece with something painted
// over it, and a snowy edge. They're asked for through a ring of requests
// in the block, baked by snow_ramps.lua a few a frame (serve_native_bakes)
// and handed back through a ring of results; each is asked for once and
// kept for the session. Until one comes back, what snow_ramps.lua drew
// until its own bakes were done is drawn: the plain thin piece, the snow
// piece without what lies on it, no edge.
//
// HOW IT TALKS TO LUA (as Stockhook does): the DLL owns one fixed block of
// memory (THE BLOCK, below) and publishes its address in the environment
// variable DWHOOK_BLOCK. internal/detailed_weather/native.lua writes into it
// the addresses and offsets DFHack knows and snow_ramps.lua's tables
// (native_tables), so the DLL never assumes DF's layout itself; colour.lua
// writes THE COLOUR's two tables.
//
// SAFETY:
//   * the renderer's vtable slot is checked before it is patched: it and
//     the render slot must both be code inside DF's exe, and the vtable
//     itself must sit inside DF's exe;
//   * the patch is made from the prerender call, while the main thread is
//     waiting for render_things, so DF can't be inside tidy_tile_cache;
//   * every size read is checked before it is used: viewports, the map's
//     block counts, a block's event list, tiletype and texture numbers;
//   * a file named detailed_weather_hook.disable in DF's folder stops it;
//   * the original slot goes back at shutdown.
//
// BUILD, in this folder:
//   Windows (x64 Native Tools Command Prompt for VS 2022):
//     cl /nologo /O2 /EHsc /MD /LD detailed_weather_hook.cpp /Fe:dfhooks_detailed_weather.dll
//   Linux:
//     g++ -std=c++17 -O2 -shared -fPIC -fvisibility=hidden detailed_weather_hook.cpp -ldl -o libdfhooks_detailed_weather.so
// What differs between the two is in platform.h and its two files; the rest is the same source.
//
// INSTALL: copy the library into DF's folder (beside the exe; on Linux,
// beside libdfhooks.so). It does nothing until native.lua turns it on.
// =====================================================================

#include <algorithm>   // (std::sort: THE SPATTER DRAWN HERE, the blades; before platform.h, as on Windows it
                       //  brings in windows.h, whose min and max macros would otherwise break its declarations)
#include "platform.h"  // what differs between Windows and Linux: memory checks, the slot, the clock
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdarg>
#include <cstddef>
#include <cmath>

// =====================================================================
// CONSTANTS
// =====================================================================
static const uint32_t LAYOUT = 38;
static const size_t TIDY_SLOT = 11;     // renderer::tidy_tile_cache (THE SLOT, above)
static const size_t RENDER_SLOT = 13;   // renderer::render, only checked, never patched
static const int32_t MOST_DIM = 4096;   // a viewport side larger than this is not trusted
static const int32_t MOST_BLOCKS = 1024;   // map blocks a side larger than this are not trusted
static const int32_t MOST_LEVELS = 4096;   // map levels more than this are not trusted
static const ptrdiff_t MOST_EVENTS = 4096; // a block event list longer than this is not trusted
static const int MOST_DEPTH = 8;        // levels below the view looked at (snow_ramps.lua: MOST_DEPTH)
static const int SLOTS = MOST_DEPTH + 1;   // the main viewport and the levels below
static const uint32_t MAX_RECORDS = 1u << 18;
static const uint32_t MAX_WRITES = 1u << 20;
static const int RING = 256;            // slots in each bake ring
static const int BAKE_MAP = 1 << 16;    // bakes remembered (a power of 2)
static const int TEX_MAP = 1 << 20;     // texture numbers the texture map covers
static const int BC_SLOTS = 8192;       // blocks read in one frame, at most (a power of 2)
static const int TT_TABLE = 2048;       // tiletype numbers the tiletype table covers
static const int PLANTS = 4096;         // plant raws the edging table covers
static const int FULL = 20;             // the snow page's FULL pieces (snow_ramps.lua: FULL_PIECES)
static const int PAGE_MAX = 256, MADE_MAX = 16384;
static const int COL_RING = 1024;       // slots in each colour ring (THE COLOUR)
static const int RAIN_GRID = 64;        // RAIN AND SNOW FALLING: the weather grid's side, in map blocks
static const int CRACK_BLANKS = 512;    // CRACKS IN PLACE (15V): slots in the ring of blank textures Lua keeps ready
static const int CRACK_FLOORS = 4096;   // and the most originals whose ground cracks a look lists its copies of
                                        // (well over the game's own: vanilla names 96; room for the graphics mods')
static const int CRACK_DONE_RING = 2048; // and in the ring of copies painted here, for Lua to note
static const int RAIN_TEX = 16384;      // and the most tiles a falling sheet can hand over (rain 12,096; snow 9,072)
static const int WFOG_DEPTHS = 9;       // THE FOG DRAWN HERE (15X): depths 0 to 8 (detailed_weather.lua: FOG_MOST_DEPTH)
static const int WFOG_TEX = 16384;      // and the most tiles the fog sheet can hand over (art/fog.png: 12,288)
static const int LEAF_RAWS = 1024;      // THE LEAVES DRAWN HERE (15X): plant raws looked at (vanilla about 230)
static const int LEAF_SHEETS = 8;       // and sheets at once (art/leaves*.png 4, petals_*.png 4)
static const int LEAF_TEX = 10240;      // and the most tiles a sheet can hand over (8,640 each)
static const int COL_LAYERS = 7;        // the layers colour swaps in (colour.lua: SCREEN_LAYERS)
static const int COL_MOST_DEPTH = 3;    // levels colour looks at, the view's own and two below
static const int SWAY_PHASES = 16;      // frames in a leaf's rustle loop (colour.lua: RUSTLE_PHASES)
static const int SWAY_MAX = 8192;       // originals with rustle frames, at most
static const int SHADE_N = 625;         // shade tiles: 5 darknesses at each of 4 corners (THE SHADE)
static const int PAINT_RING = 256;      // copies Lua can ask to be painted in one frame (PAINTING)
// art/snow_thin_sheet.lua's layout (native.lua checks it is still this)
static const int THIN_COLUMNS = 20, THIN_LEVELS = 4, THIN_VARIANTS = 4, THIN_REPEAT = 4;
static const int INSIDE_VARIANTS = 2;
static const int THIN_N = THIN_COLUMNS * THIN_LEVELS * THIN_VARIANTS * THIN_REPEAT * THIN_REPEAT;   // 5120
static const int INSIDE_N = 256 * INSIDE_VARIANTS * THIN_REPEAT * THIN_REPEAT;                      // 8192

// The tiletype table's bits (native.lua fills it from DFHack's tiletype attributes)
enum : uint8_t {
    TT_RAMP = 1,    // shape RAMP
    TT_FLOOR = 2,   // basic shape Floor (snow_ramps.lua: floor_like)
    TT_OPEN = 4,    // shape EMPTY or RAMP_TOP: the level below shows through
    TT_TREE = 8,    // material TREE: any part of a tree (snow_ramps.lua: tree_part)
    TT_TRUNK = 16,  // shape WALL and material TREE (snow_ramps.lua: trunk)
    TT_GRASS = 32,  // material GRASS_LIGHT or GRASS_DARK (snow_ramps.lua: grassy_type)
    TT_SOIL = 64,   // material SOIL (frost.lua: class_of_tiletype, 'dirt')
    TT_GRASS_ANY = 128,   // material GRASS_LIGHT, _DARK, _DRY or _DEAD (frost.lua: grassy, 'grass')
};

// =====================================================================
// THE BLOCK: shared with native.lua, byte for byte
// =====================================================================
// The Lua file writes and reads these at the SAME offsets (its OFF table),
// and snow_ramps.lua serves the bake rings at theirs (NATIVE_RINGS).
// Change one side, change the others, and raise LAYOUT so a mismatch
// refuses rather than misreads.
#pragma pack(push, 1)
struct BakeRequest {            // 64 bytes
    uint32_t kind;              // 0   1 fade, 2 snow with, 3 snowy edge
    uint32_t n;                 // 4   pieces listed (kind 3)
    int32_t  a, b, c;           // 8   fade: thin, full, full sides; with: snow, top
    int32_t  pad;               // 20
    uint64_t key;               // 24  handed back with the result
    int32_t  pieces[8];         // 32  kind 3: the edge pieces, in order
};
struct PathAnswer {             // 16 bytes (PATHS: where a texture's steady picture's pixels are)
    int32_t  texpos;            // 0  the texture asked about
    int32_t  pad;               // 4
    uint64_t addr;              // 8  its steady picture's pixels (0: nothing drawn on it)
};
struct ColQuestion {            // 8 bytes (THE COLOUR: what a texture is)
    int32_t  texpos;            // 0
    uint8_t  where;             // 4   CW_* bits: where it was seen
    uint8_t  layer;             // 5   which of the seven layers (colour.lua: SCREEN_LAYERS, from 0)
    uint8_t  depth;             // 6   levels below the view
    uint8_t  pad;               // 7
};
struct PaintJob {               // 256 bytes (PAINTING: one copy to paint)
    uint64_t src;               // 0   the original's pixels: 32 x 32 words, rows unpadded
    uint64_t dst;               // 8   the blank texture's pixels, the same
    double   m[9];              // 16  the look's colour matrix, by rows (looks.lua: matrix)
    double   lean[3];           // 88  the lean's gains (has_lean)
    double   dark;              // 112
    double   lighten;           // 120
    uint32_t has_lean;          // 128
    uint32_t cls;               // 132 0: colour only; else THE FULL REDRAW's class (CL_*)
    double   soil[3];           // 136 the soil's gains (has_soil: dirt and sand)
    uint32_t has_soil;          // 160
    uint32_t weather;           // 164 WX_*: the wet effect's weather
    double   dryness;           // 168 0 to 1 (looks.lua: redraw's dryness)
    double   wet;               // 176 the wet effect's amount, 0 for none
    double   thaw;              // 184 ice: how near thawing (its glints)
    double   ice_k;             // 192 ice: how far towards frost
    double   ice_dark;          // 200 ice: its thaw's darkening
    uint64_t grain;             // 208 sand when dry: the grain piece's pixels (0: none, 0.5 each)
    uint32_t crack_kind;        // 216 DRY CRACKS (15O): 0 none, 1 dirt, 2 stone, 3 pebbles (CK_*)
    uint32_t crack_piece;       // 220 its place on the heat patterns' 4 x 4 grid (for the log only)
    double   crack_amount;      // 224 how cracked, 0.05 to 1 (frost.lua: crack_amount)
    uint64_t crack_here;        // 232 the heat patterns' piece for this tile: 32 x 32 words, rows unpadded
    uint64_t crack_north;       // 240 the piece north of it (the far wall of a crack in the top row)
    uint32_t kind;              // 248 (15Z) PJ_*: 0 the look's redraw (all of the above); PJ_UNPREMULTIPLY;
                                //     PJ_LEAN (m[0]: its lean in px at the tips, m[1] and m[2]: the way it leans);
                                //     (16A) PJ_RUSTLE (bytes 16 to 29: each clump's move, RM_*; byte 32: 1 if every
                                //     pixel moves, the grass's, else only the leafy ones, a tree's)
    int32_t  dst_tex;           // 252 (15Z, BY PICTURE) the blank's texture number, for a screen copy (0: not filed)
};
struct CrackLook {              // 33304 bytes (CRACKS IN PLACE, 15V: one look's cracks, for painting them here)
    uint32_t gen;               // 0   the look's number (crack_gen); 0: none
    uint32_t ready;             // 4   Lua: bit 0 once the rest is filled; bit 1 dirt ramps paintable, bit 2 stone
    double   amount;            // 8   how cracked, 0.05 to 1 (frost.lua: crack_amount)
    PaintJob ramp[2];           // 16  the redraw for the look of a dirt ramp (0) and a stone ramp (1): their numbers
                                //     only (colour.lua: native_template); pixels and cracks filled in here
    uint32_t floors_n;          // 528 FLOORS AHEAD: how many of the lists below are filled
    uint32_t floors_version;    // 532 Lua: raised whenever they're written
    int32_t  floor_orig[CRACK_FLOORS];   // 536  each original whose ground cracks...
    int32_t  floor_copy[CRACK_FLOORS];   // 16920 ...and what the game draws for it in this look (its table copy, or itself)
};
struct CrackBlank {             // 16 bytes (a blank texture made by Lua, never drawn yet)
    int32_t  tex;               // 0
    int32_t  pad;               // 4
    uint64_t addr;              // 8   its pixels: 32 x 32 words, rows unpadded
};
struct CrackDone {              // 16 bytes (a cracked copy painted here, for Lua to note as Detailed Weather's)
    int32_t  tex;               // 0
    int32_t  base;              // 4   the texture it was painted from (paths.lua's soil: frost.lua's uncracked)
    uint32_t gen;               // 8
    uint8_t  piece;             // 12
    uint8_t  code;              // 13  CRACK_FLOOR, or CRACK_RAMP | its kind
    uint16_t pad;               // 14
};
struct BakeHere {               // 16 bytes (15Z, THE SNOW'S BAKES HERE: one painted here, told to Lua)
    int32_t  tex;               // 0   the texture painted
    uint32_t kind;              // 4   1 a fade, 2 a piece with something over it, 3 a snowy edge
    uint64_t key;               // 8   its bake key (fade_key, with_key, edge_key)
};
struct WaveHist {               // 16 bytes (16A, THE GRASS WAVE DRAWN HERE: one entry of colour.lua's lean_history)
    double   clock;             // 0   the gusts' clock (lean_state.clock)
    double   amount;            // 8   the lean then, 0 to 1
};
struct BakeResult {             // 16 bytes
    uint64_t key;               // 0
    int32_t  texpos;            // 8   0: it couldn't be made
    int32_t  pad;               // 12
};
struct Block {
    // ---- HEADER ----
    char     magic[8];          // 0    "DWHOOK01"
    uint32_t layout;            // 8    LAYOUT
    uint32_t enabled;           // 12   Lua: 1 while the snow is drawn here
    uint32_t install;           // 16   Lua: 1 asks for the renderer hook
    uint32_t hooked;            // 20   DLL: 1 once the slot is patched
    uint32_t tables_ready;      // 24   Lua: bumped each time the tables below are filled
    uint32_t tables_built;      // 28   DLL: the tables_ready it last built from
    // ---- ADDRESSES, filled by Lua from DFHack's layout ----
    uint64_t renderer;          // 32   the renderer object (enabler.renderer)
    uint64_t main_viewport;     // 40   &gps.main_viewport (a pointer field)
    uint64_t lower_viewports;   // 48   &gps.lower_viewport[0] (an array of pointers)
    uint64_t window_x;          // 56   &window_x (int32 globals)
    uint64_t window_y;          // 64
    uint64_t window_z;          // 72
    uint64_t block_index;       // 80   &world.map.block_index (a pointer field)
    uint64_t x_count_block;     // 88   &world.map.x_count_block (int32)
    uint64_t y_count_block;     // 96
    uint64_t z_count_block;     // 104
    uint64_t spatter_vtable;    // 112  block_square_event_material_spatterst's vtable
    uint64_t grass_vtable;      // 120  block_square_event_grassst's vtable (0: no grass on the map)
    uint32_t lower_count;       // 128  slots in gps.lower_viewport
    uint32_t off_flag;          // 132  offsets inside graphic_viewportst (0 is a real offset)
    uint32_t off_dim_x;         // 136
    uint32_t off_dim_y;         // 140
    uint32_t off_background;    // 144  screentexpos_background (int32_t*): the ground
    uint32_t off_bg2;           // 148  screentexpos_background_two (int32_t*): the layer above the spatter
    uint32_t off_spatter;       // 152  screentexpos_spatter (int32_t*)
    uint32_t off_floor_flag;    // 156  screentexpos_floor_flag (uint64_t*): overhangs, bytes S, W, E, N
    uint32_t off_shadow_flag;   // 160  screentexpos_shadow_flag (uint32_t*): skirts and shadows
    uint32_t off_ramp_flag;     // 164  screentexpos_ramp_flag (uint64_t*): walls in the second byte
    uint32_t off_tiletype;      // 168  map_block.tiletype (uint16 [16][16], x major)
    uint32_t off_designation;   // 172  map_block.designation (uint32 [16][16], x major)
    uint32_t off_block_events;  // 176  map_block.block_events (a vector of event pointers)
    uint32_t off_ev_mat_type;   // 180  the material spatter event's mat_type (int16)
    uint32_t off_ev_mat_state;  // 184  its mat_state (int16)
    uint32_t off_ev_amount;     // 188  its amount (uint8 [16][16], x major)
    uint32_t off_gev_plant;     // 192  the grass event's plant_index (int32)
    uint32_t off_gev_amount;    // 196  its amount (uint8 [16][16], x major)
    uint32_t hidden_mask;       // 200  tile_designation's hidden bit
    uint32_t outside_mask;      // 204  tile_designation's outside bit
    int32_t  black_texpos;      // 208  gps.black_background_texpos[0]: a cell DF hasn't drawn yet
    int16_t  snow_mat_type;     // 212  6, WATER
    int16_t  snow_mat_state;    // 214  matter_state Powder
    int32_t  snowy_from;        // 216  100 (snow_ramps.lua: SNOWY)
    int32_t  edge_level;        // 220  art/snow_thin_sheet.lua's edge_level
    // ---- THE VIEW AS DRAWN, written by the DLL ----
    int32_t  drawn_x;           // 224
    int32_t  drawn_y;           // 228
    int32_t  drawn_z;           // 232
    uint32_t have_drawn;        // 236
    // ---- COUNTERS, written by the DLL ----
    int64_t  prerender_calls;   // 240
    int64_t  tidy_calls;        // 248
    int64_t  plans;             // 256  frames worked out
    int64_t  applies;           // 264  frames written
    int64_t  apply_skipped;     // 272  plans not written: their viewports had changed
    int64_t  view_moved;        // 280  frames the view had moved by the time the hook ran
    int64_t  ramps_written;     // 288  snowy ramps drawn
    int64_t  floors_written;    // 296  snowy floors changed
    int64_t  trunks_written;    // 304  trunks given snow
    int64_t  edges_written;     // 312  snowy edges drawn
    int64_t  cells_waiting;     // 320  cells showing this snow with the game's own not kept yet: left for the frame
    int64_t  bakes_asked;       // 328
    int64_t  bakes_done;        // 336
    int64_t  bakes_failed;      // 344
    int64_t  columns_last;      // 352  screen columns the last plan walked
    int64_t  records_last;      // 360  records it made
    int64_t  snowy_last;        // 368  snowy floors among them
    int64_t  events_capped;     // 376  blocks whose event list was too long to trust
    double   plan_us_total;     // 384
    double   plan_us_max;       // 392
    double   apply_us_total;    // 400
    double   apply_us_max;      // 408
    char     renderer_class[64];// 416
    uint32_t install_failed;    // 480
    uint32_t plan_overflow;     // 484  plans that ran out of room for records or writes
    uint32_t bake_ring_full;    // 488  bakes not asked for yet: the request ring was full
    uint32_t bake_map_full;     // 492  bakes not asked for: the DLL's list of them was full
    // ---- THE BAKE RINGS (snow_ramps.lua: NATIVE_RINGS) ----
    uint32_t req_head;          // 496  DLL: requests written
    uint32_t req_tail;          // 500  Lua: requests served
    uint32_t res_head;          // 504  Lua: results written
    uint32_t res_tail;          // 508  DLL: results taken
    BakeRequest req[RING];      // 512
    BakeResult  res[RING];      // 16896
    // ---- TABLES, filled by Lua (snow_ramps.lua: native_tables) ----
    uint8_t  tt_flags[TT_TABLE];        // 20992  TT_* by tiletype
    uint8_t  plant_edging[PLANTS];      // 23040  each plant's grass edging ID (0: none)
    int32_t  edge_art[256][8];          // 27136  by edging ID: pieces N, S, W, E, NW, NE, SW, SE
    int32_t  snow_ramp_tex[256];        // 35328  the snowy ramp texture for each walls byte
    int32_t  full_tex[FULL];            // 36352  the FULL pieces' textures
    uint8_t  full_sides[FULL];          // 36432  their sides joined: S 1, W 2, E 4, N 8
    uint8_t  full_col[FULL];            // 36452  their column on the thin sheet (255: none)
    uint8_t  full_inside[FULL];         // 36472  1: an inside piece (thin by its corners)
    uint8_t  pieces_n[16];              // 36492  for each set of sides, how many FULL pieces
    uint8_t  pad2[4];                   // 36508
    int32_t  pieces_tex[16][5];         // 36512  and which, in order
    int32_t  page_n;                    // 36832
    int32_t  made_n;                    // 36836
    int32_t  page_tex[PAGE_MAX];        // 36840  every texture on the snow page
    int32_t  made_tex[MADE_MAX];        // 37864  the other textures snow_ramps.lua had made (its bakes)
    int32_t  thin_tex[THIN_N];          // 103400 art/snow_thin.png, in order
    int32_t  inside_tex[INSIDE_N];      // 123880 art/snow_thin_inside.png, in order
    // ---- MORE COUNTERS, written by the DLL ----
    int64_t  cells_restored;    // 156648 cells put back to the game's own drawing (no snow to draw there now)
    uint32_t blocks_last;       // 156656 map blocks the last plan read
    uint32_t blocks_full;       // 156660 blocks not read: too many in one frame (BC_SLOTS)
    uint32_t tex_out_of_range;  // 156664 textures in the tables past the texture map (TEX_MAP)
    int32_t  texpos_most;       // 156668 the highest texture number in the tables
    uint32_t memory_kb;         // 156672 memory the DLL has allocated (put-back lists, block columns)
    uint32_t pad3;              // 156676
    // ---- MORE TABLES, filled by Lua (layout 6) ----
    int32_t  snowy_single[256][8];      // 156680 by edging ID: each edge piece's snowy version (0: none)
    // ---- MORE COUNTERS (layout 7: BLOCKS KEPT) ----
    uint32_t blocks_redone_last;        // 164872 blocks whose records the last plan worked out afresh
    uint32_t blocks_kept_last;          // 164876 blocks whose kept records it used
    int64_t  blocks_redone;             // 164880 blocks worked out afresh, summed over the frames
    int64_t  blocks_kept;               // 164888 blocks taken as kept, summed over the frames
    // ---- THE COLOUR (layout 8; THE COLOUR, below) ----
    uint32_t col_enabled;               // 164896 Lua: 1 while colour's swaps are done here
    uint32_t col_depths;                // 164900 Lua: levels looked at (colour.lua: SCREEN_DEPTHS), at most COL_MOST_DEPTH
    uint32_t off_building_one;          // 164904 graphic_viewportst offsets of the other four layers swapped
    uint32_t off_building_two;          // 164908
    uint32_t off_item;                  // 164912
    uint32_t off_vehicle;               // 164916
    uint64_t col_link;                  // 164920 DLL: &g_link[0], int32 by texture number
    uint64_t col_flags;                 // 164928 DLL: &g_cflag[0], uint8 by texture number
    uint32_t col_tex_map;               // 164936 DLL: texture numbers the two cover (TEX_MAP)
    uint32_t col_period;                // 164940 Lua: bumped each time it wants the copies in view listed again (SEEN)
    uint32_t subterranean_mask;         // 164944 tile_designation's subterranean bit
    uint32_t flow_mask;                 // 164948 its flow_size bits
    uint32_t col_reset;                 // 164952 Lua: bumped to have both tables emptied
    uint32_t col_reset_done;            // 164956 DLL: the col_reset it last emptied them for
    uint32_t col_req_head;              // 164960 DLL: questions written
    uint32_t col_req_tail;              // 164964 Lua: questions answered
    uint32_t col_seen_head;             // 164968 DLL: copies seen, written
    uint32_t col_seen_tail;             // 164972 Lua: taken
    ColQuestion col_req[COL_RING];      // 164976 8 bytes each
    int32_t  col_seen[COL_RING];        // 173168 originals shown through their copy, once a period
    int64_t  col_frames;                // 177264 frames swapped
    int64_t  col_swapped;               // 177272 cells given a copy, summed
    int64_t  col_put_back;              // 177280 cells given the game's own picture back, summed
    int64_t  col_held;                  // 177288 cells kept on last frame's copy while a question waits, summed
    int64_t  col_asked;                 // 177296 questions asked
    int64_t  col_waiting;               // 177304 cells left as the game drew them while a question waits, summed
    uint32_t col_ring_full;             // 177312 questions not asked yet: the ring was full
    uint32_t col_seen_full;             // 177316 copies not listed: the seen ring was full
    double   col_us_total;              // 177320
    double   col_us_max;                // 177328
    uint32_t col_cells_last;            // 177336 cells with something in them the last frame looked at
    uint32_t col_swapped_last;          // 177340 cells it gave a copy
    // ---- THE SWAY (layout 9; SWAY, below) ----
    int32_t  sway_playing;              // 177344 Lua: the loop's frame now, 0 to SWAY_PHASES - 1 (-1: still)
    uint32_t sway_reset;                // 177348 Lua: bumped to have the frames forgotten (new wind or look)
    uint32_t sway_reset_done;           // 177352 DLL: the sway_reset it last forgot them for
    int32_t  sway_waves;                // 177356 Lua: loop frames a tile downwind is behind (WAVE_PHASES_PER_TILE)
    double   sway_ux;                   // 177360 Lua: the wind's direction, a unit vector
    double   sway_uy;                   // 177368
    uint64_t sway_of;                   // 177376 DLL: &g_sway_of[0], uint16 by original (0: no frames)
    uint64_t sway_tex;                  // 177384 DLL: &g_sway_tex[0][0], SWAY_PHASES int32 a slot
    uint32_t sway_max;                  // 177392 DLL: SWAY_MAX
    uint32_t sway_phases;               // 177396 DLL: SWAY_PHASES
    int64_t  sway_swapped;              // 177400 cells given a rustle frame, summed
    uint8_t  col_tt[TT_TABLE];          // 177408 Lua: 1 for a tree's branches or twigs, by tiletype (canopy)
    // ---- THE SHADE (layout 10; THE SHADE, below) ----
    uint32_t shade_enabled;             // 179456 Lua: 1 while the shade is drawn here
    uint32_t off_designation_layer;     // 179460 graphic_viewportst: screentexpos_designation (int32_t*)
    int64_t  shade_frames;              // 179464 frames drawn
    int64_t  shade_written;             // 179472 cells given a shade tile, summed
    double   shade_us_total;            // 179480
    double   shade_us_max;              // 179488
    uint32_t shade_cells_last;          // 179496 screen cells shaded the last frame
    uint32_t pad4;                      // 179500
    int32_t  shade_tex[SHADE_N];        // 179504 Lua: the shade tile for each set of corner darknesses
    uint32_t pad5;                      // 182004
    // ---- PAINTING (layout 11) ----
    uint32_t paint_head;                // 182008 Lua: copies asked for
    uint32_t paint_tail;                // 182012 DLL: copies painted
    int64_t  paint_done;                // 182016 copies painted, summed
    double   paint_us_total;            // 182024
    double   paint_us_max;              // 182032 (the most in one frame)
    uint32_t paint_bad;                 // 182040 jobs refused: an address not readable
    uint32_t pad6;                      // 182044
    PaintJob paint[PAINT_RING];         // 182048
    // ---- MURKY (layout 13) ----
    uint32_t murky_enabled;             // 247584 Lua: 1 while murky water is drawn here
    uint32_t stagnant_mask;             // 247588 tile_designation's water_stagnant bit
    uint32_t magma_mask;                // 247592 and its liquid_type bit (set: magma)
    uint32_t murky_depths;              // 247596 levels below the view that get it (murky.lua: MOST_DEPTH)
    int32_t  murky_tex[16];             // 247600 art/murky.png's 4 x 4 cells, (y % 4) * 4 + x % 4
    int64_t  murky_frames;              // 247664
    int64_t  murky_written;             // 247672 cells tinted, summed
    double   murky_us_total;            // 247680
    double   murky_us_max;              // 247688
    uint32_t murky_drawn[4];            // 247696 cells tinted the last frame, by level down
    // ---- MURKY: EDGES OVER THE TINT (layout 14) ----
    uint32_t murky_blank_head;          // 247712 Lua: blanks given
    uint32_t murky_blank_tail;          // 247716 DLL: blanks used
    int32_t  murky_blank_tex[256];      // 247720 a ring of blank textures for the DLL to paint (never shown yet)
    uint64_t murky_blank_addr[256];     // 248744 and their pixels (32 x 32 words, rows unpadded)
    uint64_t murky_tint_addr[16];       // 250792 the tint cells' pixels (murky_tex)
    uint64_t edge_addr[256][8];         // 250920 each edge art piece's pixels (edge_art), 0: none
    int64_t  murky_baked;               // 267304 tints with edges painted
    uint32_t murky_bake_waits;          // 267312 cells drawn without their edges for a frame: no blank, or the list full
    uint32_t murky_corners;             // 267316 1: the corner pieces drawn back too (Lua: MURKY_CORNERS)
    uint32_t murky_bake_reset;          // 267320 Lua: raised at each start and new look, the made textures forgotten
    uint32_t murky_bake_reset_done;     // 267324 DLL: copied when done
    // ---- MURKY: FRAME BY FRAME (layout 15) ----
    uint32_t murky_hist_head;           // 267328 records written (the newest at (head - 1) % 128)
    uint32_t murky_empty_pieces;        // 267332 edge pieces painted in with no visible pixel (not painted yet?)
    uint32_t murky_hist[128][8];        // 267336 a record each time a frame's numbers differ from the last:
                                        //   frame, view x, view y, cells tinted from above, of them with
                                        //   overhangs (sides or corners), given their edges, plain while
                                        //   the bakes were being forgotten, plain with no bake (waiting)
    // ---- PATHS (layout 18; blanks from the murky edges' ring) ----
    uint32_t paths_enabled;             // 271432
    uint32_t paths_depths;              // 271436 levels below the view's that get paths (paths.lua: MOST_DEPTH)
    uint32_t paths_reset;               // 271440 Lua: a new soil, or colour's copies let go: paintings and answers forgotten
    uint32_t paths_reset_done;          // 271444 DLL (hook): copied when done
    uint32_t paths_plan_reset;          // 271448 Lua: a start: what's known of the map forgotten
    uint32_t paths_plan_reset_done;     // 271452 DLL (prerender): copied when done
    uint64_t paths_soil_addr;           // 271456 the soil's pixels (0: none yet, so nothing drawn)
    uint32_t paths_soil_ask;            // 271464 Lua: raised to have the bare soil in view counted
    uint32_t paths_soil_done;           // 271468 DLL: copied once counted
    int32_t  paths_soil_seen[4];        // 271472 the commonest textures on bare soil in view, most first (0: none)
    uint32_t paths_q_head;              // 271488 DLL: questions asked
    uint32_t paths_q_tail;              // 271492 Lua: answered
    int32_t  paths_q[256];              // 271496 textures under worn grass whose steady pixels are wanted
    uint32_t paths_a_head;              // 272520 Lua: answers given
    uint32_t paths_a_tail;              // 272524 DLL: taken
    PathAnswer paths_a[256];            // 272528
    uint8_t  paths_kind[2048];          // 276624 by tiletype: 1 grass floor, 2 bare soil floor (paths.lua: kind_of)
    int64_t  paths_frames;              // 278672 frames drawn
    int64_t  paths_baked;               // 278680 worn tiles painted (each combination once)
    uint32_t paths_waits;               // 278688 cells left as the game drew them for a frame: no blank, or a list full
    uint32_t paths_cells_last;          // 278692 worn cells drawn the last frame
    uint32_t paths_known;               // 278696 worn tiles in the view's blocks, the last plan
    uint32_t paths_blocks_last;         // 278700 blocks worked out the last plan
    int64_t  paths_blocks_total;        // 278704 blocks worked out in all
    double   paths_plan_us_total;       // 278712
    double   paths_plan_us_max;         // 278720
    double   paths_draw_us_total;       // 278728
    double   paths_draw_us_max;         // 278736
    int64_t  paths_plans;               // 278744 plans made
    uint32_t paths_q_full;              // 278752 questions put off, the ring full
    uint32_t pad9;                      // 278756
    // ---- MURKY: THE HAZE (layout 21) ----
    uint64_t haze_air_addr;             // 278760 (15F: MULTILEVEL_AIR's pixels; unused since 15G, the game hazes the tint)
    uint32_t haze_layers_last;          // 278768 (15F; unused since 15G: 0)
    // ---- MURKY: THE PROBE (layout 21) ----
    uint32_t probe_ask;                 // 278772 Lua: raised to have one cell's layers recorded
    uint32_t probe_done;                // 278776 DLL: copied once recorded
    int32_t  probe_d;                   // 278780 the cell's water, levels down (0: none recorded)
    int32_t  probe_x;                   // 278784 the cell's map position
    int32_t  probe_y;                   // 278788
    uint32_t off_probe[16];             // 278792 Lua: viewport fields to record, the offset | 8 << 24 for 8-byte ones (0: none)
    uint64_t probe_val[8][16];          // 278856 by level (0: the view's) and field: the cell's value
    // ---- FOG OVER WATER (layout 22) ----
    uint32_t fog_enabled;               // 279880 Lua: 1 while the haze over deep water is set to its surface's level
    uint32_t off_interface;             // 279884 screentexpos_interface (int32_t*): the layer the game lays its haze in
    uint64_t fog_tex_addr;              // 279888 &gps.texture_indices1[0]: the game's 8 hazes, read every frame
    int64_t  fog_frames;                // 279896 frames set right
    int64_t  fog_moved;                 // 279904 cells given their surface's haze, summed
    int64_t  fog_put_back;              // 279912 cells given the game's own haze back before it drew again, summed
    int64_t  fog_plans;                 // 279920 plans made
    double   fog_plan_us_total;         // 279928
    double   fog_plan_us_max;           // 279936
    double   fog_us_total;              // 279944
    double   fog_us_max;                // 279952
    uint32_t fog_marked_last;           // 279960 cells over deep water, the last plan
    uint32_t fog_moved_last;            // 279964 of them given their surface's haze, the last frame
    uint32_t fog_already_last;          // 279968 already holding it as the game laid it
    uint32_t fog_unmatched_last;        // 279972 holding no haze of the water's level (left as laid)
    uint32_t fog_dry_last;              // 279976 open space above the water with nothing drawn on it (left as laid)
    uint32_t fog_kept_full;             // 279980 cells left as laid: the list to put back was full
    int32_t  fog_odd_d;                 // 279984 the first unmatched cell the last frame: its water, levels down (0: none)
    int32_t  fog_odd_slot;              // 279988 the level below its haze was found in (0: none found)
    int32_t  fog_odd_haze;              // 279992 and which of the 8 (-1: none)
    uint32_t fog_census_ask;            // 279996 Lua: raised to have every haze in view counted
    uint32_t fog_census_done;           // 280000 DLL: copied once counted
    uint32_t fog_census_cells;          // 280004 cells with a haze in some level
    uint32_t fog_census_multi;          // 280008 cells with more than one
    uint32_t fog_census[9][8];          // 280012 hazes by level (0: the view's own) and which of the 8
    uint32_t fog_reset;                 // 280300 Lua: raised at each start: the plan's blocks forgotten (another map)
    uint32_t fog_reset_done;            // 280304 DLL (prerender): copied when done
    uint32_t fog_blocks_walked_last;    // 280308 map blocks walked down by the last plan (new, or old and done again)
    uint32_t fog_blocks_kept;           // 280312 blocks kept now
    uint32_t pad10;                     // 280316
    int64_t  fog_blocks_walked;         // 280320 summed
    // ---- THE COLOUR: PICTURES CHECKED HERE (layout 23) ----
    uint64_t col_raws;                  // 280328 &enabler.textures.raws (a std::vector of SDL_Surface pointers)
    uint32_t col_verified_head;         // 280336 Lua: originals it found still showing their copy's picture
    uint32_t col_verified_tail;         // 280340 DLL: taken (their fingerprints kept)
    int32_t  col_verified[1024];        // 280344 the ring (COL_RING)
    int64_t  col_pics_checked;          // 284440 copies in view checked here, summed
    int64_t  col_pics_changed;          // 284448 of them found changed (listed for colour.lua)
    uint32_t col_pics_kept;             // 284456 fingerprints kept now
    uint32_t pad11;                     // 284460
    // ---- THE COLOUR: THE HELD SLOTS (layout 24) ----
    int64_t  col_wait_new;              // 284464 of the waits (col_waiting): the tile wasn't in last frame's view
    int64_t  col_wait_nohold;           // 284472 of the waits: in last frame's view, but no copy held for it
    int64_t  col_held_moved;            // 284480 of the holds (col_held): the view had moved since (none before 15L)
    // ---- RAIN AND SNOW FALLING (layout 25) ----
    uint32_t rain_enabled;              // 284488 Lua: 1 while the DLL draws them
    uint32_t off_high_flow;             // 284492 screentexpos_high_flow (int32_t*): where a falling tile goes
    uint32_t off_top_shadow;            // 284496 screentexpos_top_shadow (int32_t*): where the game has a flow
    uint32_t pad13;                     // 284500 (magma_mask, at 247592, is shared with MURKY; rain's start fills it too)
    int32_t  rain_wz;                   // 284504 Lua: the level the weather grid is for (-1: none)
    int32_t  rain_wbx;                  // 284508 Lua: the grid's first map block column
    int32_t  rain_wby;                  // 284512 and row
    int32_t  rain_wnx;                  // 284516 its width in blocks (at most RAIN_GRID)
    int32_t  rain_wny;                  // 284520 and height
    uint32_t rain_weather_any;          // 284524 Lua: 1 when some block in the grid has rain or snow
    uint8_t  rain_weather[RAIN_GRID * RAIN_GRID];   // 284528 Lua: by block, x major: 0 none, 1 rain, 2 snow
    uint8_t  tt_empty[TT_TABLE];        // 288624 Lua: 1 for tiletype shape EMPTY (find_rain: open space over water)
    int32_t  rain_cells;                // 290672 Lua: art/rain_sheet.lua's cells (the patch's side, in tiles)
    int32_t  rain_anim;                 // 290676 and frames
    int32_t  rain_slants;               // 290680 and how many slants
    int32_t  rain_slant;                // 290684 Lua, each frame: the slant for the wind (1-based, slant_for_wind)
    int32_t  rain_frame;                // 290688 Lua, each frame: the animation frame (0-based)
    int32_t  snow_cells;                // 290692 Lua: art/snow_sheet.lua's cells
    int32_t  snow_anim;                 // 290696 and frames
    int32_t  snow_wind;                 // 290700 Lua, each frame: the wind's index (1-based)
    int32_t  snow_frame;                // 290704 Lua, each frame: the animation frame (0-based)
    int32_t  rain_tex_n;                // 290708 Lua: tiles of the rain sheet handed over (0: none yet)
    int32_t  snow_tex_n;                // 290712 and of the snow sheet
    int32_t  rain_tex[RAIN_TEX];        // 290716 Lua: the rain sheet's texpos by tile (0: nothing drawn in it)
    int32_t  snow_tex[RAIN_TEX];        // 356252 and the snow sheet's
    uint32_t rain_dropped;              // 421788 put back entries let go: their array was neither buffer (15N)
    int64_t  rain_frames;               // 421792 frames drawn
    int64_t  rain_drawn;                // 421800 cells given a falling tile, summed
    int64_t  rain_put_back;             // 421808 of them put back before the game drew again, summed
    double   rain_us_total;             // 421816
    double   rain_us_max;               // 421824
    uint32_t rain_cells_last;           // 421832 cells with rain or snow falling, the last frame
    uint32_t rain_drawn_last;           // 421836 given a tile in the flow layer
    uint32_t rain_over_flow_last;       // 421840 given it in top_shadow (the game had a flow there)
    uint32_t rain_no_room_last;         // 421844 left (both layers taken)
    uint32_t rain_kept_full;            // 421848 cells left: the list to put back was full
    uint32_t rain_skipped;              // 421852 frames not drawn: the grid wasn't for this view's level
    // ---- MURKY: BRANCHES PROBED (layout 27) ----
    uint32_t probe_through;             // 421856 the probed cell: bit k set if the level k down is a branch or leaves
    uint32_t murky_under_branch_last;   // 421860 stagnant water cells seen only through branches or leaves, the last frame
    int64_t  murky_under_branch;        // 421864 the same, summed (15Q: tinted; BRANCHES SEEN THROUGH)
    // ---- MURKY: BRANCHES SEEN THROUGH (layout 28) ----
    uint32_t murky_branch_above_last;   // 421872 of them, left untinted: a branch or leaves on the level just above the water
    uint32_t pad14;                     // 421876
    // ---- CRACKS IN PLACE (layout 32: the tiles worked out here, from the map; 29 to 31 took them from frost.lua) ----
    uint32_t crack_on;                  // 421880 Lua: 1 while the look cracks the ground and the DLL places the cracks
    uint32_t crack_gen;                 // 421884 Lua: the look's cracks now: copies are asked for under this number
    uint32_t crack_gen_prev;            // 421888 Lua: the look's before (0xffffffff: none): theirs held until the new are made
    uint32_t crack_gen_next;            // 421892 Lua: the next look's while colour.lua makes it (0 or 0xffffffff: none; THE NEXT LOOK AHEAD)
    uint32_t crack_next_walked;         // 421896 DLL: the crack_gen_next the count below is for
    uint32_t crack_next_missing_last;   // 421900 cells in view whose next look's copy isn't made yet
    uint32_t crack_depth;               // 421904 Lua: levels below the view looked at (frost.lua: MOST_DEPTH)
    uint32_t crack_world;               // 421908 Lua: raised on a new world: every cracked copy and tile forgotten
    uint32_t crack_recheck;             // 421912 Lua: frames between a block's tiles worked out again (temperature, snow, water, digging)
    uint32_t off_temperature;           // 421916 Lua: map_block's temperature_1 (uint16 [16][16])
    uint32_t crack_forced_on;           // 421920 Lua: 1 with crack_forced_c in place of every tile's temperature (`temperature N`)
    uint32_t crack_tables;              // 421924 Lua: raised when the settings and the tiletype table below are filled
    double   crack_band_c;              // 421928 Lua: degrees a temperature band (frost.lua: BAND_C)
    double   crack_cool_from;           // 421936 Lua: a band whose middle is from here...
    double   crack_warm_from;           // 421944 Lua: ...to here is mild, and cracks nothing (frost.lua: band_of)
    double   crack_forced_c;            // 421952
    uint8_t  crack_tt[TT_TABLE];        // 421960 Lua: by tiletype, CRACK_FLOOR, CRACK_RAMP | its kind, CRACK_OPEN, or 0
    // ---- CRACKS IN PLACE: THE PAINTING HERE (layout 33) ----
    CrackLook crack_look[2];            // 424008 Lua: the look showing's and the next look's (by gen; 33304 bytes each)
    uint64_t crack_heat[16];            // 490616 Lua: the heat patterns' 16 pieces' pixels (frost.lua: heat_pattern_handles)
    uint64_t crack_ground;              // 490744 DLL: its table by texture number of each original's ground, for Lua to fill
                                        //        (CK_*: 1 dirt, 2 stone, 3 pebbles; 0 doesn't crack)
    uint32_t crack_b_head;              // 490752 Lua: blank textures handed over
    uint32_t crack_b_tail;              // 490756 DLL: taken
    CrackBlank crack_b[CRACK_BLANKS];   // 490760
    uint32_t crack_d_head;              // 498952 DLL: copies painted
    uint32_t crack_d_tail;              // 498956 Lua: noted
    CrackDone crack_d[CRACK_DONE_RING]; // 498960
    int64_t  crack_frames;              // 531728 frames placed
    int64_t  crack_written;             // 531736 cells given their cracked copy, summed
    int64_t  crack_painted;             // 531744 copies painted for the look showing
    int64_t  crack_ahead_painted;       // 531752 copies painted for the next look (THE NEXT LOOK AHEAD)
    int64_t  crack_ramp_held;           // 531760 ramps given the cracked copy they showed last (THE RAMP HELD)
    int64_t  crack_blocks_worked;       // 531768 map blocks' tiles worked out (THE TILES WORKED OUT)
    int64_t  crack_waiting;             // 531776 cells left uncracked for a frame: no copy yet (drawing in), summed
    double   crack_us_total;            // 531784
    double   crack_us_max;              // 531792
    double   crack_paint_us_total;      // 531800 painting, within the above
    double   crack_paint_us_max;        // 531808
    uint32_t crack_cells_last;          // 531816 cells of tiles that may crack, the last frame
    uint32_t crack_written_last;        // 531820 given their cracked copy
    uint32_t crack_held_last;           // 531824 given the look before's while theirs is painted
    uint32_t crack_waiting_last;        // 531828 left uncracked: no copy yet
    uint32_t crack_ramp_held_last;      // 531832 ramps given the cracked copy they showed last
    uint32_t crack_tiles_kept;          // 531836 map blocks of tiles kept
    uint32_t crack_cleared;             // 531840 cells given their ground back when the cracks stopped
    uint32_t crack_worked_last;         // 531844 map blocks worked out the last frame
    uint32_t crack_painted_last;        // 531848 copies painted the last frame (both looks)
    uint32_t crack_no_blank;            // 531852 copies put off: no blank ready, summed
    uint32_t crack_over_time;           // 531856 copies put off: the frame's painting time used up, summed
    uint32_t crack_unreadable;          // 531860 copies not painted: the texture's pixels not readable, summed
    uint32_t crack_copies_kept;         // 531864 copies known (painted, or "doesn't crack")
    uint32_t crack_table_full;          // 531868 copies not painted: their table full, summed
    uint32_t crack_pics_kept;           // 531872 textures known by picture (PICTURES, NOT NUMBERS)
    uint32_t crack_done_full;           // 531876 copies painted but not noted by Lua: its ring full, summed
    // ---- THE FOG DRAWN HERE (layout 34, test 15X): detailed_weather.lua's fog, in the main view's interface ----
    uint32_t wfog_on;                   // 531880 Lua: 1 while the DLL draws the fog
    int32_t  wfog_level;                // 531884 Lua: this frame's density, 1 to levels x substeps (0: no fog)
    int32_t  wfog_patch;                // 531888 Lua: the sheet's layout (art/fog_sheet.lua: patch, frames)
    int32_t  wfog_frames;               // 531892
    int32_t  wfog_steps[WFOG_DEPTHS];   // 531896 Lua: each depth's drift this frame, in steps (steps_at)
    int32_t  wfog_tex_n;                // 531932 Lua: tiles handed over (0 while handing over)
    int32_t  wfog_tex[WFOG_TEX];        // 531936 Lua: the fog sheet's texpos by tile
    int64_t  wfog_frames_drawn;         // 597472 frames drawn
    int64_t  wfog_drawn;                // 597480 cells given fog, summed
    int64_t  wfog_put_back;             // 597488 cells given the game's own back, summed
    double   wfog_us_total;             // 597496
    double   wfog_us_max;               // 597504
    uint32_t wfog_cells_last;           // 597512 outdoor cells in view, the last frame
    uint32_t wfog_drawn_last;           // 597516 given fog
    uint32_t wfog_taken_last;           // 597520 left: the game or another overlay had something there
    uint32_t wfog_kept_full;            // 597524 cells not drawn: the list to put back full, summed
    uint32_t wfog_dropped;              // 597528 put back entries let go: their array neither buffer
    uint32_t off_projectile;            // 597532 screentexpos_projectile (int32_t*): the leaves' layer
    // ---- THE LEAVES DRAWN HERE (layout 34, test 15X): leaves.lua's falling leaves and petals, in projectile ----
    uint32_t leaf_on;                   // 597536 Lua: 1 while the DLL draws them
    uint32_t leaf_any;                  // 597540 Lua: 1 while a tree sheds now (else nothing is worked out or drawn)
    int32_t  leaf_cells;                // 597544 Lua: the sheets' layout (leaves_sheet.lua, petals_sheet.lua alike)
    int32_t  leaf_frames;               // 597548
    int32_t  leaf_winds;                // 597552
    int32_t  leaf_heavies;              // 597556
    int32_t  leaf_frame;                // 597560 Lua: this frame's animation frame (0-based; each tree adds its own)
    int32_t  leaf_wind;                 // 597564 Lua: this frame's wind, 1-based into the layout's winds
    uint32_t leaf_tables;               // 597568 Lua: raised when its tables change: every block worked out again
    uint32_t leaf_recheck;              // 597572 Lua: frames before a block is worked out again (trees grow, fall)
    uint64_t column_index;              // 597576 Lua: &world.map.column_index (map_block_column** by block x)
    uint32_t off_col_plants;            // 597584 map_block_column.plants (std::vector<df::plant*>)
    uint32_t off_plant_pos;             // 597588 df::plant.pos (int16_t x, y, z)
    uint32_t off_plant_material;        // 597592 df::plant.material (int16_t: the plant raw)
    uint32_t off_plant_tree;            // 597596 df::plant.tree_info (plant_tree_info*)
    uint32_t off_tree_body;             // 597600 plant_tree_info.body (uint16_t* by level, dim_x * dim_y each)
    uint32_t off_tree_height;           // 597604 plant_tree_info.body_height (int32_t)
    uint32_t off_tree_dim_x;            // 597608 plant_tree_info.dim_x
    uint32_t off_tree_dim_y;            // 597612 plant_tree_info.dim_y
    uint8_t  wl_tt[TT_TABLE];           // 597616 Lua: by tiletype: 1 a tree's canopy, 2 TREE, 4 open (EMPTY, RAMP_TOP)
    uint8_t  leaf_sheds[LEAF_RAWS];     // 599664 Lua: by plant raw: 1 if the tree sheds anything (leaves.lua: sheds)
    uint16_t leaf_spec[LEAF_RAWS];      // 600688 Lua: by plant raw, now: 0 nothing falling, else sheet 1-8 | heaviness << 8
    int32_t  leaf_tex_n[LEAF_SHEETS];   // 602736 Lua: each sheet's tiles handed over (0 while handing over)
    int32_t  leaf_tex[LEAF_SHEETS][LEAF_TEX];   // 602768 Lua: each sheet's texpos by tile (0: nothing drawn in it)
    int64_t  leaf_frames_drawn;         // 930448 frames drawn
    int64_t  leaf_drawn;                // 930456 cells given a leaf or petal, summed
    int64_t  leaf_put_back;             // 930464 cells given the game's own back, summed
    int64_t  leaf_blocks_worked;        // 930472 map blocks worked out, summed
    double   leaf_us_total;             // 930480
    double   leaf_us_max;               // 930488
    uint32_t leaf_cells_last;           // 930496 cells under a tree that sheds, the last frame
    uint32_t leaf_drawn_last;           // 930500 given a leaf or petal
    uint32_t leaf_maps_kept;            // 930504 blocks' maps kept (what falls; which tree)
    uint32_t leaf_pool_full;            // 930508 times every map was let go: the pool full
    uint32_t leaf_kept_full;            // 930512 cells not drawn: the list to put back full, summed
    uint32_t leaf_dropped;              // 930516 put back entries let go: their array neither buffer
    uint32_t leaf_trees_bad;            // 930520 trees passed over: sizes past belief (not a tree's)
    uint32_t leaf_worked_last;          // 930524 map blocks worked out the last frame
    // ---- THE SPATTER DRAWN HERE (layout 35, test 15Y): spatter.lua's spatter in the grass ----
    uint32_t spat_on;                   // 930528 Lua: 1 while the DLL puts the spatter in the grass
    uint32_t spat_blades;               // 930532 Lua: 1 for the grass's blades in front (spatter.lua: blades_mode)
    uint64_t spat_vtable;               // 930536 Lua: block_square_event_item_spatterst's vtable (0: not known)
    uint32_t off_isp_amount;            // 930544 its amount[16][16] (int32_t)
    uint32_t spat_tables;               // 930548 Lua: raised when the grass table changes: every bake let go
    uint64_t spat_grass;                // 930552 DLL: its table by texture number of the grass originals, for Lua to fill
    int64_t  spat_frames;               // 930560 frames drawn
    int64_t  spat_written;              // 930568 cells given their spatter thinned and shadowed, summed
    int64_t  spat_blades_written;       // 930576 cells given the grass's blades, summed
    int64_t  spat_put_back;             // 930584 cells given the game's own back, summed
    int64_t  spat_painted;              // 930592 textures painted here (pieces and blades)
    double   spat_us_total;             // 930600
    double   spat_us_max;               // 930608
    double   spat_paint_us_max;         // 930616 painting, within the above
    uint32_t spat_cells_last;           // 930624 cells of spatter on grass, the last frame
    uint32_t spat_written_last;         // 930628 given their spatter
    uint32_t spat_waiting_last;         // 930632 left as the game drew them: not painted yet (the frame's time)
    uint32_t spat_no_blank;             // 930636 paintings put off: no blank ready, summed
    uint32_t spat_over_time;            // 930640 paintings put off: the frame's painting time used up, summed
    uint32_t spat_unreadable;           // 930644 paintings not done: pixels not readable, summed
    uint32_t spat_bakes_kept;           // 930648 textures known (pieces and blades)
    uint32_t spat_bakes_full;           // 930652 times every one was let go: the table full
    uint32_t spat_kept_full;            // 930656 cells not drawn: the list to put back full, summed
    uint32_t spat_dropped;              // 930660 put back entries let go: their array neither buffer
    // ---- THE WAITS TAKEN OUT (layout 36, test 15Z) ----
    int64_t  paths_held;                // 930664 worn cells shown their last painting while the new one waited, summed
    int64_t  paths_put_off;             // 930672 new paintings put off to a later frame: the frame's painting time used, summed
    uint32_t paths_no_blank;            // 930680 new paintings put off: no blank ready, summed
    uint32_t paths_bases_dropped;       // 930684 times the list of grass pictures started over (full)
    uint32_t paths_bakes_halved;        // 930688 times the paintings' newer half became the older (full)
    uint32_t paths_held_last;           // 930692 worn cells shown their last painting, the last frame
    int64_t  col_by_picture;            // 930696 colour cells given a copy by picture while their question waited, summed
    uint32_t col_pics_filed;            // 930704 screen copies filed by picture (painted here)
    uint32_t col_pics_halved;           // 930708 times the filing's newer half became the older (full)
    int64_t  paint_unpremultiplied;     // 930712 PJ_UNPREMULTIPLY jobs painted, summed
    int64_t  paint_leans;               // 930720 PJ_LEAN jobs painted, summed
    uint32_t snow_bake_here;            // 930728 Lua: 1 while the snow's bakes are painted here
    uint32_t bake_here_head;            // 930732 DLL: bakes painted here, told to Lua
    uint32_t bake_here_tail;            // 930736 Lua: taken
    uint32_t bakes_here_put_off;        // 930740 bakes asked of Lua instead: no blank, a picture unreadable, or the list full
    int64_t  bakes_here;                // 930744 bakes painted here, summed
    double   bake_here_us_total;        // 930752 painting them
    BakeHere bake_here[256];            // 930760
    uint32_t bakes_here_over_time;      // 934856 bakes put off to the next frame: the frame's painting time used, summed
    uint32_t pad15z;                    // 934860
    // ---- THE RUSTLE PAINTED HERE (layout 37, test 16A) ----
    int64_t  paint_rustles;             // 934864 PJ_RUSTLE jobs painted, summed
    uint32_t rustle_of_ready;           // 934872 Lua: 1 once rustle_of is filled
    uint32_t canopy_wood;               // 934876 tree pictures listed for frames as wood (no frames), summed
    uint8_t  rustle_of[1024];           // 934880 Lua: each pixel's clump, 0 to 13 (colour.lua's clump_layout: of, less 1)
    // ---- THE GRASS WAVE DRAWN HERE (layout 38, test 16A) ----
    uint32_t wave_on;                   // 935904 Lua: 1 for this frame's wave; set back to 0 once drawn
    uint32_t wave_gen;                  // 935908 Lua: raised when its tables are let go (a new set of frames; the rustle's kind)
    uint32_t wave_gen_done;             // 935912 DLL: the gen its tables are emptied for (Lua writes them once it matches)
    uint32_t wave_built;                // 935916 Lua: raised once it has written the slots' lean frames (the map made again)
    uint32_t wave_slot_n;               // 935920 Lua: slots written
    int32_t  wave_x1;                   // 935924 Lua: the view's corner it worked from (colour.lua: viewport.x1, y1)
    int32_t  wave_y1;                   // 935928
    int32_t  wave_cols;                 // 935932 Lua: columns and rows of the view
    int32_t  wave_rows;                 // 935936
    int32_t  wave_playing;              // 935940 Lua: the rustle's place in its loop now; -1 none
    double   wave_cx;                   // 935944 Lua: the view's middle
    double   wave_cy;                   // 935952
    double   wave_reach;                // 935960 Lua: the distance downwind from the view's middle to its edge, in tiles
    double   wave_ux;                   // 935968 Lua: the way the wind blows (the set's ux, uy)
    double   wave_uy;                   // 935976
    double   wave_clock;                // 935984 Lua: the gusts' clock now (lean_state.clock)
    uint64_t wave_slots;                // 935992 DLL: &g_wave_slots[0], WaveSlot[WAVE_SLOTS], for Lua to fill
    uint32_t wave_slots_most;           // 936000 DLL: WAVE_SLOTS
    uint32_t wave_hist_head;            // 936004 Lua: entries written
    WaveHist wave_hist[2048];           // 936008 Lua: colour.lua's lean_history, entry by entry
    uint32_t wave_want_head;            // 968776 DLL: rustle frames wanted
    uint32_t wave_want_tail;            // 968780 Lua: taken
    uint32_t wave_want[256];            // 968784 slot << 8 | (even step / 2) << 4 | phase
    int64_t  wave_frames;               // 969808 frames drawn
    int64_t  wave_written;              // 969816 cells given their own lean or rustle frame, summed
    double   wave_us_total;             // 969824
    double   wave_us_max;               // 969832
    uint32_t wave_written_last;         // 969840 the last frame
    uint32_t wave_wants;                // 969844 rustle frames asked of Lua, summed
    uint32_t wave_map_full;             // 969848 pictures left out: the map full
    uint32_t wave_want_full;            // 969852 rustle frames not asked this frame: the ring full, summed
};                                      // 969856 bytes
#pragma pack(pop)

static_assert(sizeof(BakeRequest) == 64, "BakeRequest layout");
static_assert(sizeof(BakeResult) == 16, "BakeResult layout");
static_assert(offsetof(Block, renderer) == 32, "Block layout");
static_assert(offsetof(Block, lower_count) == 128, "Block layout");
static_assert(offsetof(Block, hidden_mask) == 200, "Block layout");
static_assert(offsetof(Block, drawn_x) == 224, "Block layout");
static_assert(offsetof(Block, prerender_calls) == 240, "Block layout");
static_assert(offsetof(Block, plan_us_total) == 384, "Block layout");
static_assert(offsetof(Block, renderer_class) == 416, "Block layout");
static_assert(offsetof(Block, req_head) == 496, "Block layout");
static_assert(offsetof(Block, req) == 512, "Block layout");
static_assert(offsetof(Block, res) == 16896, "Block layout");
static_assert(offsetof(Block, tt_flags) == 20992, "Block layout");
static_assert(offsetof(Block, edge_art) == 27136, "Block layout");
static_assert(offsetof(Block, full_tex) == 36352, "Block layout");
static_assert(offsetof(Block, pieces_tex) == 36512, "Block layout");
static_assert(offsetof(Block, page_tex) == 36840, "Block layout");
static_assert(offsetof(Block, made_tex) == 37864, "Block layout");
static_assert(offsetof(Block, thin_tex) == 103400, "Block layout");
static_assert(offsetof(Block, inside_tex) == 123880, "Block layout");
static_assert(offsetof(Block, cells_restored) == 156648, "Block layout");
static_assert(offsetof(Block, memory_kb) == 156672, "Block layout");
static_assert(offsetof(Block, snowy_single) == 156680, "Block layout");
static_assert(offsetof(Block, blocks_redone_last) == 164872, "Block layout");
static_assert(sizeof(ColQuestion) == 8, "ColQuestion layout");
static_assert(offsetof(Block, col_enabled) == 164896, "Block layout");
static_assert(offsetof(Block, col_req) == 164976, "Block layout");
static_assert(offsetof(Block, col_seen) == 173168, "Block layout");
static_assert(offsetof(Block, col_frames) == 177264, "Block layout");
static_assert(offsetof(Block, col_us_total) == 177320, "Block layout");
static_assert(offsetof(Block, sway_playing) == 177344, "Block layout");
static_assert(offsetof(Block, sway_ux) == 177360, "Block layout");
static_assert(offsetof(Block, col_tt) == 177408, "Block layout");
static_assert(offsetof(Block, shade_enabled) == 179456, "Block layout");
static_assert(offsetof(Block, shade_tex) == 179504, "Block layout");
static_assert(sizeof(PaintJob) == 256, "PaintJob layout");
static_assert(offsetof(PaintJob, cls) == 132, "PaintJob layout");
static_assert(offsetof(PaintJob, soil) == 136, "PaintJob layout");
static_assert(offsetof(PaintJob, grain) == 208, "PaintJob layout");
static_assert(offsetof(Block, paint_head) == 182008, "Block layout");
static_assert(offsetof(Block, paint) == 182048, "Block layout");
static_assert(offsetof(Block, murky_enabled) == 247584, "Block layout");
static_assert(offsetof(Block, murky_tex) == 247600, "Block layout");
static_assert(offsetof(Block, murky_drawn) == 247696, "Block layout");
static_assert(offsetof(Block, murky_blank_tex) == 247720, "Block layout");
static_assert(offsetof(Block, edge_addr) == 250920, "Block layout");
static_assert(offsetof(Block, murky_baked) == 267304, "Block layout");
static_assert(offsetof(Block, murky_hist) == 267336, "Block layout");
static_assert(offsetof(Block, paths_soil_addr) == 271456, "Block layout");
static_assert(offsetof(Block, paths_a) == 272528, "Block layout");
static_assert(offsetof(Block, paths_kind) == 276624, "Block layout");
static_assert(offsetof(Block, paths_plans) == 278744, "Block layout");
static_assert(offsetof(Block, off_probe) == 278792, "Block layout");
static_assert(offsetof(Block, probe_val) == 278856, "Block layout");
static_assert(offsetof(Block, fog_enabled) == 279880, "Block layout");
static_assert(offsetof(Block, fog_marked_last) == 279960, "Block layout");
static_assert(offsetof(Block, fog_census) == 280012, "Block layout");
static_assert(offsetof(Block, fog_blocks_walked) == 280320, "Block layout");
static_assert(offsetof(Block, col_verified) == 280344, "Block layout");
static_assert(offsetof(Block, col_pics_checked) == 284440, "Block layout");
static_assert(offsetof(Block, col_wait_new) == 284464, "Block layout");
static_assert(offsetof(Block, rain_enabled) == 284488, "Block layout");
static_assert(offsetof(Block, rain_weather) == 284528, "Block layout");
static_assert(offsetof(Block, tt_empty) == 288624, "Block layout");
static_assert(offsetof(Block, rain_tex) == 290716, "Block layout");
static_assert(offsetof(Block, snow_tex) == 356252, "Block layout");
static_assert(offsetof(Block, rain_frames) == 421792, "Block layout");
static_assert(offsetof(Block, probe_through) == 421856, "Block layout");
static_assert(offsetof(Block, murky_branch_above_last) == 421872, "Block layout");
static_assert(offsetof(Block, crack_on) == 421880, "Block layout");
static_assert(offsetof(Block, crack_tt) == 421960, "Block layout");
static_assert(offsetof(Block, crack_look) == 424008, "Block layout");
static_assert(offsetof(Block, crack_heat) == 490616, "Block layout");
static_assert(offsetof(Block, crack_b) == 490760, "Block layout");
static_assert(offsetof(Block, crack_d) == 498960, "Block layout");
static_assert(offsetof(Block, crack_frames) == 531728, "Block layout");
static_assert(offsetof(Block, wfog_on) == 531880 && offsetof(Block, wfog_tex) == 531936 && offsetof(Block, wfog_frames_drawn) == 597472, "Block layout");
static_assert(offsetof(Block, leaf_on) == 597536 && offsetof(Block, column_index) == 597576 && offsetof(Block, wl_tt) == 597616, "Block layout");
static_assert(offsetof(Block, leaf_tex) == 602768 && offsetof(Block, leaf_frames_drawn) == 930448, "Block layout");
static_assert(offsetof(Block, spat_on) == 930528 && offsetof(Block, spat_grass) == 930552 && offsetof(Block, spat_frames) == 930560, "Block layout");
static_assert(offsetof(Block, paths_held) == 930664 && offsetof(Block, col_by_picture) == 930696 && offsetof(Block, bake_here) == 930760, "Block layout");
static_assert(offsetof(Block, paint_rustles) == 934864 && offsetof(Block, rustle_of) == 934880, "Block layout");
static_assert(offsetof(Block, wave_on) == 935904 && offsetof(Block, wave_hist) == 936008 && offsetof(Block, wave_want) == 968784, "Block layout");
static_assert(sizeof(Block) == 969856, "Block layout");
static_assert(sizeof(BakeHere) == 16 && sizeof(PaintJob) == 256 && offsetof(PaintJob, kind) == 248, "15Z layout");
static_assert(sizeof(CrackLook) == 33304 && offsetof(CrackLook, floor_orig) == 536 && offsetof(CrackLook, floor_copy) == 16920, "CrackLook layout");

static Block g_block;   // zeroed at load: nothing happens until Lua fills it
static Block& B = g_block;

// =====================================================================
// STATE
// =====================================================================
typedef void (*tidy_fn)(void* self);    // x64: a member call is `this` in rcx
static tidy_fn  g_tidy_original = nullptr;
static void**   g_slot = nullptr;       // the vtable slot patched
static FILE*    g_log = nullptr;
static double   g_us_per_tick = 0;      // the clock's ticks to microseconds (platform.h)
static bool     g_disabled = false;
static uint32_t g_frame = 0;            // plans made: dates the per-frame block reads

// =====================================================================
// LOGGING, MEMORY CHECKS, TIMING
// =====================================================================
static void log_line(const char* fmt, ...) {
    if (!g_log) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(g_log, fmt, ap);
    va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
}

// Is [p, p + n) readable memory? Every pointer the hook follows before
// patching is checked this way first, so a wrong address from Lua refuses
// instead of faulting. (How it's asked differs by system: platform.h.)
static bool readable(const void* p, size_t n) { return plat_readable(p, n); }

// Whether n bytes from p are all readable, however many regions they span
// (a block of pixels can sit across two: test 7, in platform_windows.h).
static bool readable_span(const void* p, size_t n) { return plat_readable_span(p, n); }

static double ticks_now() { return plat_ticks_now(); }

// =====================================================================
// TEXTURES: which are the snow's
// =====================================================================
// A byte for every texture number, built from the tables when Lua hands
// them over (and added to as bakes come back):
//   1        a texture on the snow page: the game's own snow pieces
//   2        one of this snow's own (snow_ramps.lua: snow_made): the thin
//            sheets, the snowy ramps, everything baked
//   16 + k   FULL piece k (on the snow page too)
static uint8_t g_tex[TEX_MAP];
enum : uint8_t { TEX_PAGE = 1, TEX_OURS = 2, TEX_FULL = 16 };

static inline uint8_t tex_class(int32_t t) { return (t > 0 && t < TEX_MAP) ? g_tex[t] : 0; }
static inline bool is_ours(int32_t t) { return tex_class(t) == TEX_OURS; }
static inline bool is_page(int32_t t) { uint8_t c = tex_class(t); return c == TEX_PAGE || c >= TEX_FULL; }
static inline int full_index(int32_t t) { uint8_t c = tex_class(t); return c >= TEX_FULL ? c - TEX_FULL : -1; }
static void mark(int32_t t, uint8_t c) {
    if (t <= 0) return;
    if (t > B.texpos_most) B.texpos_most = t;
    if (t < TEX_MAP) g_tex[t] = c;
    else B.tex_out_of_range++;
}

// ---- THE BAKES REMEMBERED ----
// Each bake by its key: asked for (pending) or come back (done; texture 0
// if it couldn't be made). Never forgotten: a baked texture stays loaded
// for the session (grass.lua: NO TEXTURE IS EVER DELETED).
struct BakeSlot { uint64_t key; int32_t texpos; uint8_t state; uint8_t pad[3]; };
enum : uint8_t { BAKE_EMPTY = 0, BAKE_PENDING = 1, BAKE_DONE = 2 };
static BakeSlot g_bakes[BAKE_MAP];
static int g_bake_count = 0;

static BakeSlot* bake_slot(uint64_t key, bool add) {
    uint32_t h = (uint32_t)((key * 0x9E3779B97F4A7C15ull) >> 48) & (BAKE_MAP - 1);
    for (int n = 0; n < BAKE_MAP; n++, h = (h + 1) & (BAKE_MAP - 1)) {
        BakeSlot& s = g_bakes[h];
        if (s.state == BAKE_EMPTY) {
            if (!add) return nullptr;
            if (g_bake_count >= BAKE_MAP * 3 / 4) { B.bake_map_full++; return nullptr; }
            s.key = key;
            g_bake_count++;
            return &s;
        }
        if (s.key == key) return &s;
    }
    return nullptr;
}

// ---- THE SNOW'S BAKES HERE (15Z) ----
// snow_ramps.lua baked these in Lua (BAKES FOR THE DLL: within 3 ms a frame, each wanted texture drawn
// as its fallback until served) and every snowy edge at start (SNOWY EDGES AT ONCE, part of 15Y's 2.4 s
// freeze at load). Now they're painted here, with the same arithmetic, the moment one is wanted, into
// the shared blanks (crack_b), and each is told to Lua (bake_here), which files it as the snow's own
// (frost puts its rime under a snowy edge; the colour leaves it be). With no blank ready, a picture that
// can't be read, or the list to tell Lua full, it's asked of Lua as before.
static const double SNOW_THIN_FADE = 7;                  // (snow_ramps.lua: THIN_FADE) px over which thin snow thickens towards full
static const double SNOW_LIP[3] = {174, 190, 215};       // (SNOW_LIP) vanilla's snow shade, along an edge's open bottom
static const double SNOW_RIM[3] = {255, 255, 255};       // (SNOW_RIM) along its open top
static const uint32_t* crack_pixels(int32_t t, uint32_t* scratch);   // (CRACKS IN PLACE, below)
static void colour_leave(int32_t t);                                  // (THE COLOUR, below)
static inline uint32_t snow_round(double v) { return (uint32_t)floor(v + 0.5); }
static const double SNOW_BAKE_US = 2000;   // bakes painted here each frame within this long (the rest the next frame, the fallback drawn meanwhile)
static int64_t g_bake_here_frame = -1;     // the frame (tidy_calls) g_bake_here_us is for
static double g_bake_here_us = 0;          // time spent painting bakes this frame
// Kind 1 (bake_fade): thin piece `thin` thickening into full piece `full` towards sides `sides` (S 1, W 2,
// E 4, N 8), dithered; each pixel is one or the other's as it is.
static void bake_fade_px(const uint32_t* thin, const uint32_t* full, int sides, uint32_t* out) {
    for (int py = 0; py < 32; py++) {
        for (int px = 0; px < 32; px++) {
            const int n = py * 32 + px;   // (Lua's n is this plus 1)
            // (math.min written out: windows.h's min and max macros break std::min under MSVC)
            double reach = HUGE_VAL;
            if ((sides & 8) && py < reach) reach = py;
            if ((sides & 1) && 31 - py < reach) reach = 31 - py;
            if ((sides & 2) && px < reach) reach = px;
            if ((sides & 4) && 31 - px < reach) reach = 31 - px;
            const double dither = (double)((((int64_t)n + 1) * 2654435761LL) % 1000) / 1000;
            out[n] = ((reach + 0.5) / SNOW_THIN_FADE < dither * 0.6 + 0.4) ? full[n] : thin[n];
        }
    }
}
// Kind 2 (snow_with): `over` laid over `base` by its alpha.
static void bake_with_px(const uint32_t* base, const uint32_t* over, uint32_t* out) {
    for (int n = 0; n < 1024; n++) {
        const uint32_t b = base[n], t = over[n];
        const double ta = (double)(t >> 24) / 255, ba = (double)(b >> 24) / 255;
        const double a = ta + ba * (1 - ta);
        if (a <= 0) { out[n] = 0; continue; }
        uint32_t c[3];
        for (int k = 0; k < 3; k++) {
            const double tk = (double)((t >> (8 * k)) & 0xff), bk = (double)((b >> (8 * k)) & 0xff);
            c[k] = snow_round((tk * ta + bk * ba * (1 - ta)) / a);
        }
        out[n] = (snow_round(a * 255) << 24) | (c[2] << 16) | (c[1] << 8) | c[0];
    }
}
// Kind 3 (snowy_overhang): the pieces' shape (the most opaque of them at each pixel) filled with plain
// snow, its open bottom shaded and its open top lit.
static void bake_edge_px(const uint32_t* const* pieces, int n, const uint32_t* fill, uint32_t* out) {
    uint8_t alpha[1024];
    memset(alpha, 0, sizeof alpha);
    for (int k = 0; k < n; k++) {
        for (int i = 0; i < 1024; i++) {
            const uint8_t a = (uint8_t)(pieces[k][i] >> 24);
            if (a > alpha[i]) alpha[i] = a;
        }
    }
    for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
            const int i = y * 32 + x;
            if (alpha[i] == 0) { out[i] = 0; continue; }
            const uint32_t f = fill[i];
            double r = f & 0xff, g = (f >> 8) & 0xff, b = (f >> 16) & 0xff;
            const bool open_below = y == 31 || alpha[i + 32] == 0;
            const bool open_above = y == 0 || alpha[i - 32] == 0;
            const double* towards = nullptr;
            double amount = 0;
            if (open_below) { towards = SNOW_LIP; amount = 0.7; }
            else if (open_above) { towards = SNOW_RIM; amount = 0.5; }
            if (towards) {
                r = r + (towards[0] - r) * amount; g = g + (towards[1] - g) * amount; b = b + (towards[2] - b) * amount;
            }
            out[i] = ((uint32_t)alpha[i] << 24) | (snow_round(b) << 16) | (snow_round(g) << 8) | snow_round(r);
        }
    }
}
// Bake `kind` painted into a shared blank: 1 painted (tex), 2 an existing texture is the result (tex: a
// fade towards no side is the thin piece itself), 0 not here (no blank, or a picture unreadable).
static int bake_here(uint32_t kind, int32_t a, int32_t b, int32_t c, const int32_t* pieces, int n, int32_t& tex) {
    if (kind == 1 && !(c & 15)) { tex = a; return 2; }
    if (B.crack_b_tail == B.crack_b_head) return 0;
    static uint32_t s[9][1024];   // (pictures copied out of padded rows; the hook runs on one thread)
    uint32_t out[1024];
    if (kind == 1 || kind == 2) {
        const uint32_t* p1 = crack_pixels(a, s[0]);
        const uint32_t* p2 = crack_pixels(b, s[1]);
        if (!p1 || !p2) return 0;
        if (kind == 1) bake_fade_px(p1, p2, c, out); else bake_with_px(p1, p2, out);
    } else if (kind == 3) {
        if (n <= 0) return 0;
        if (n > 8) n = 8;
        const uint32_t* pp[8];
        for (int k = 0; k < n; k++) if (!(pp[k] = crack_pixels(pieces[k], s[k]))) return 0;
        const int32_t ft = B.pieces_n[15] ? B.pieces_tex[15][0] : 0;   // (plain snow: pieces_for.NSWE[1])
        const uint32_t* fill = ft ? crack_pixels(ft, s[8]) : nullptr;
        if (!fill) return 0;
        bake_edge_px(pp, n, fill, out);
    } else return 0;
    const CrackBlank bl = B.crack_b[B.crack_b_tail % CRACK_BLANKS];
    B.crack_b_tail++;   // (taken, painted or not: a blank that can't be painted is no use)
    if (!bl.addr || bl.tex <= 0 || !readable_span((const void*)(uintptr_t)bl.addr, 4096)) return 0;
    memcpy((void*)(uintptr_t)bl.addr, out, sizeof out);
    tex = bl.tex;
    return 1;
}

// A bake's texture, or 0 to draw the fallback for now: painted here (15Z), else asked for the first
// time it's wanted (if the ring has room), and drawn once it comes back.
static int32_t bake(uint64_t key, uint32_t kind, int32_t a, int32_t b, int32_t c,
                    const int32_t* pieces, int n) {
    BakeSlot* s = bake_slot(key, false);
    if (s) return s->state == BAKE_DONE ? s->texpos : 0;
    if (g_bake_count >= BAKE_MAP * 3 / 4) { B.bake_map_full++; return 0; }
    // (THE SNOW'S BAKES HERE) painted now, if it can be, and told to Lua after; the frame's painting time used
    // up, put off to the next frame (not asked of Lua, which is slower), the fallback drawn meanwhile
    if (B.snow_bake_here) {
        if (g_bake_here_frame != B.tidy_calls) { g_bake_here_frame = B.tidy_calls; g_bake_here_us = 0; }
        if (g_bake_here_us >= SNOW_BAKE_US) { B.bakes_here_over_time++; return 0; }
        int32_t tex = 0;
        const double t0 = ticks_now();
        const int got = (B.bake_here_head - B.bake_here_tail < (uint32_t)RING) ? bake_here(kind, a, b, c, pieces, n, tex) : 0;
        const double us = (ticks_now() - t0) * g_us_per_tick;
        B.bake_here_us_total += us;
        g_bake_here_us += us;
        if (got) {
            s = bake_slot(key, true);
            if (!s) return 0;
            s->state = BAKE_DONE;
            s->texpos = tex;
            if (got == 1) {
                mark(tex, TEX_OURS);
                colour_leave(tex);   // (never swapped by THE COLOUR)
                BakeHere& h = B.bake_here[B.bake_here_head % RING];
                h.tex = tex; h.kind = kind; h.key = key;
                B.bake_here_head++;
                B.bakes_here++;
            }
            return tex;
        }
        B.bakes_here_put_off++;
    }
    if (B.req_head - B.req_tail >= (uint32_t)RING) { B.bake_ring_full++; return 0; }
    s = bake_slot(key, true);
    if (!s) return 0;
    s->state = BAKE_PENDING;
    s->texpos = 0;
    BakeRequest& r = B.req[B.req_head % RING];
    r.kind = kind;
    r.n = (uint32_t)n;
    r.a = a; r.b = b; r.c = c;
    r.key = key;
    for (int k = 0; k < 8; k++) r.pieces[k] = k < n ? pieces[k] : 0;
    B.req_head++;
    B.bakes_asked++;
    return 0;
}

// The results snow_ramps.lua has handed back since the last frame. Some
// were never asked for: snowy edges kept from earlier sessions, made again
// at start (snow_ramps.lua: SNOWY EDGES KEPT), kept as if they had been.
static void take_bakes() {
    while (B.res_tail != B.res_head) {
        const BakeResult& r = B.res[B.res_tail % RING];
        BakeSlot* s = bake_slot(r.key, false);
        if (!s && r.texpos > 0) s = bake_slot(r.key, true);
        if (s) {
            s->state = BAKE_DONE;
            s->texpos = r.texpos > 0 ? r.texpos : 0;
            if (s->texpos) { mark(s->texpos, TEX_OURS); B.bakes_done++; }
            else B.bakes_failed++;
        }
        B.res_tail++;
    }
}

// Bake keys: the kind in the top bits, then what it's made of.
static inline uint64_t fade_key(int32_t thin, int32_t full, uint8_t sides) {
    return (1ull << 60) | ((uint64_t)(thin & 0xFFFFFF) << 28) | ((uint64_t)(full & 0xFFFFFF) << 4) | (sides & 15);
}
static inline uint64_t with_key(int32_t snow, int32_t top) {
    return (2ull << 60) | ((uint64_t)(snow & 0xFFFFFF) << 28) | ((uint64_t)(top & 0xFFFFFF) << 4);
}
static inline uint64_t edge_key(const int32_t* pieces, int n) {
    uint64_t h = 1469598103934665603ull;   // FNV-1a over the pieces, in order
    for (int k = 0; k < n; k++) { h ^= (uint32_t)pieces[k]; h *= 1099511628211ull; }
    return (3ull << 60) | (h & ((1ull << 60) - 1));
}

// The tables handed over (tables_ready bumped): the texture map built from
// them, and the bakes started afresh: the rings emptied, so nothing half
// served is waited on, and the list of bakes cleared, so each is asked for
// again. One already made comes straight back (snow_ramps.lua keeps its own
// bakes cached, and they're among the textures it made, marked below).
static void build_tables() {
    memset(g_tex, 0, sizeof g_tex);
    B.tex_out_of_range = 0;
    B.texpos_most = 0;
    int pn = B.page_n < PAGE_MAX ? B.page_n : PAGE_MAX;
    for (int k = 0; k < pn; k++) mark(B.page_tex[k], TEX_PAGE);
    for (int k = 0; k < FULL; k++) mark(B.full_tex[k], (uint8_t)(TEX_FULL + k));
    int mn = B.made_n < MADE_MAX ? B.made_n : MADE_MAX;
    for (int k = 0; k < mn; k++) mark(B.made_tex[k], TEX_OURS);
    for (int k = 0; k < THIN_N; k++) mark(B.thin_tex[k], TEX_OURS);
    for (int k = 0; k < INSIDE_N; k++) mark(B.inside_tex[k], TEX_OURS);
    for (int k = 0; k < 256; k++) mark(B.snow_ramp_tex[k], TEX_OURS);
    for (int id = 0; id < 256; id++) for (int k = 0; k < 8; k++) mark(B.snowy_single[id][k], TEX_OURS);
    for (int k = 0; k < BAKE_MAP; k++) if (g_bakes[k].state == BAKE_DONE && g_bakes[k].texpos) mark(g_bakes[k].texpos, TEX_OURS);
    memset(g_bakes, 0, sizeof g_bakes);
    g_bake_count = 0;
    B.req_head = B.req_tail = B.res_head = B.res_tail = 0;
    B.tables_built = B.tables_ready;
    log_line("tables %u built: %d page textures, %d made before, thin sheets %d and %d; highest texture %d,"
             " %u past the texture map.", B.tables_built, pn, mn, THIN_N, INSIDE_N, B.texpos_most,
             B.tex_out_of_range);
}

// =====================================================================
// READING DF'S DATA
// =====================================================================
// A viewport by slot: 0 the main one, n the level n below the view
// (gps.lower_viewport[n - 1]; the Lua mod's ports[depth]). Read fresh
// every time: a zoom remakes them.
static uint8_t* viewport_in(int32_t slot) {
    if (slot == 0) return *(uint8_t* const*)(uintptr_t)B.main_viewport;
    if (!B.lower_viewports || (uint32_t)slot > B.lower_count) return nullptr;
    return ((uint8_t* const*)(uintptr_t)B.lower_viewports)[slot - 1];
}

// One viewport's buffers, read once a plan (and checked again at write).
struct SlotBufs {
    uint8_t*  vp;
    int32_t   dx, dy;
    bool      usable;
    int32_t*  background;
    int32_t*  bg2;
    int32_t*  spatter;
    uint64_t* floor_flag;
    uint32_t* shadow;
    uint64_t* ramp_flag;
};
static SlotBufs g_sb[SLOTS];

static bool read_slot(int32_t slot, SlotBufs& s) {
    s.usable = false;
    s.vp = viewport_in(slot);
    if (!s.vp) return false;
    // a level below that DF isn't showing (GRAPHIC_VIEWPORT_FLAG_ACTIVE, BIT1 = 1)
    if (slot > 0 && !(*(const uint32_t*)(s.vp + B.off_flag) & 1)) return false;
    s.dx = *(const int32_t*)(s.vp + B.off_dim_x);
    s.dy = *(const int32_t*)(s.vp + B.off_dim_y);
    if (s.dx <= 0 || s.dy <= 0 || s.dx > MOST_DIM || s.dy > MOST_DIM) return false;
    s.background = *(int32_t* const*)(s.vp + B.off_background);
    s.bg2 = *(int32_t* const*)(s.vp + B.off_bg2);
    s.spatter = *(int32_t* const*)(s.vp + B.off_spatter);
    s.floor_flag = *(uint64_t* const*)(s.vp + B.off_floor_flag);
    s.shadow = *(uint32_t* const*)(s.vp + B.off_shadow_flag);
    s.ramp_flag = *(uint64_t* const*)(s.vp + B.off_ramp_flag);
    if (!s.background || !s.bg2 || !s.spatter || !s.floor_flag || !s.shadow || !s.ramp_flag) return false;
    s.usable = true;
    return true;
}

// ---- THE MAP ----
// world.map.block_index is three arrays of pointers, [block x][block y][z]
// (df.world.xml), each block 16 x 16 tiles of one level; read once a plan.
struct MapView { void* const* xs; int32_t bxn, byn, zn, x_end, y_end; };
static MapView g_map;

static inline const uint8_t* block_ptr(int32_t bx, int32_t by, int32_t z) {
    void* const* ys = (void* const*)g_map.xs[bx];
    if (!ys) return nullptr;
    void* const* zs = (void* const*)ys[by];
    if (!zs) return nullptr;
    return (const uint8_t*)zs[z];
}
static inline int tile_of(int32_t x, int32_t y) { return ((x & 15) << 4) | (y & 15); }   // [x][y] in a block
static inline uint16_t type_in(const uint8_t* blk, int t) { return ((const uint16_t*)(blk + B.off_tiletype))[t]; }
static inline uint32_t des_in(const uint8_t* blk, int t) { return ((const uint32_t*)(blk + B.off_designation))[t]; }
static inline uint8_t flags_of(uint16_t tt) { return tt < TT_TABLE ? B.tt_flags[tt] : 0; }

// A block's event list, as a std::vector of pointers (first and last at +0
// and +8, as Stockhook's vec_byte reads one); false if it isn't to be trusted.
static inline bool events_of(const uint8_t* blk, void* const*& first, void* const*& last) {
    first = *(void* const* const*)(blk + B.off_block_events);
    last = *(void* const* const*)(blk + B.off_block_events + 8);
    if (!first || last <= first) return false;
    if (last - first > MOST_EVENTS) { B.events_capped++; return false; }
    return true;
}

// ---- EACH BLOCK READ ONCE A FRAME ----
// A block's snow (grass.lua: snow_amount: of its events, every material
// spatter of WATER as Powder, the most any has on each tile; told by the
// event's vtable, as DFHack's is_instance does for a class with no
// subclasses), read the first time the frame needs the block, and, when
// first asked for, its grass edging (snow_ramps.lua: read_info: of the
// grass events, the first with the most on the tile; its plant's edging,
// on grass tiles only) and its neighbourhood (THE PADS, below). Kept by
// block position for the frame in a table probed in a line: an entry from
// an earlier frame is free, so one stays where it is for the whole frame
// (pointers to it stay good).
struct Pad;
struct BlockCache {
    int32_t bx, by, z;
    uint32_t frame;
    const uint8_t* blk;          // null: no block there
    uint64_t sig;                // its fingerprint this frame (BLOCKS KEPT), once sig_ready
    uint8_t sig_ready;           // 1 once the fingerprint is worked out this frame (only when a kept block needs it)
    int8_t  snow_near;           // -1 not looked at; 1 if it or any of the 8 round it has SNOWY anywhere (NO SNOW NEAR)
    void* memo;                  // its kept rules for this frame (a BlockMemo; BLOCKS KEPT)
    uint8_t memo_tried;          // 1 once they were looked for this frame
    Pad* pad;                    // its neighbourhood, once made this frame
    uint8_t has_edging;
    uint8_t max_snow;            // the most snow on any of its tiles
    int8_t  near_snowy;          // -1 not looked at; 1 if it or a block beside it has SNOWY anywhere
    uint8_t pad_tried;           // 1 once a pad was asked for (none if there was no room)
    uint8_t snow[256];
    uint8_t edging[256];
};
static BlockCache g_bc[BC_SLOTS];
static uint32_t g_bc_used = 0;   // entries filled this frame

// BLOCKS KEPT: a block's fingerprint, from everything the rules read of it:
// its snow, tile types, hidden and outside flags, and grass (each grass
// event's plant and amounts). Two frames with the same fingerprint have the
// same block, as far as the snow is concerned. Worked out only when a kept
// block asks for it (sig_of, test 15I).
static inline uint64_t mix(uint64_t h, uint64_t v) {
    h ^= v;
    h *= 0x9E3779B97F4A7C15ull;
    return h ^ (h >> 32);
}
// Bytes into a running fingerprint, four words at a time in four separate
// lanes (a single chain of multiplies was most of the plan's time once the
// blocks were kept). n a multiple of 32; `mask` is kept of each word.
static uint64_t mix_bytes(uint64_t h, const uint8_t* p, size_t n, uint64_t mask = ~0ull) {
    uint64_t a = h ^ 0xA0761D6478BD642Full, b = h ^ 0xE7037ED1A0B428DBull, c = h ^ 0x8EBC6AF09C88C6E3ull, d = h;
    for (size_t k = 0; k < n; k += 32) {
        uint64_t w[4];
        memcpy(w, p + k, 32);
        a = (a ^ (w[0] & mask)) * 0x9E3779B97F4A7C15ull;
        b = (b ^ (w[1] & mask)) * 0xC2B2AE3D27D4EB4Full;
        c = (c ^ (w[2] & mask)) * 0x165667B19E3779F9ull;
        d = (d ^ (w[3] & mask)) * 0xD6E8FEB86659FD93ull;
    }
    return mix(mix(mix(mix(h, a ^ (a >> 29)), b ^ (b >> 31)), c ^ (c >> 27)), d ^ (d >> 33));
}
static uint64_t block_sig(const struct BlockCache& c);

static BlockCache* bc_at(int32_t bx, int32_t by, int32_t z) {
    if (bx < 0 || by < 0 || z < 0 || bx >= g_map.bxn || by >= g_map.byn || z >= g_map.zn) return nullptr;
    uint32_t h = ((uint32_t)bx * 73856093u ^ (uint32_t)by * 19349663u ^ (uint32_t)z * 83492791u) & (BC_SLOTS - 1);
    for (;;) {
        BlockCache& c = g_bc[h];
        if (c.frame != g_frame) break;
        if (c.bx == bx && c.by == by && c.z == z) return c.blk ? &c : nullptr;
        h = (h + 1) & (BC_SLOTS - 1);
    }
    if (g_bc_used >= BC_SLOTS * 3 / 4) { B.blocks_full++; return nullptr; }
    BlockCache& c = g_bc[h];
    c.bx = bx; c.by = by; c.z = z; c.frame = g_frame;
    c.blk = block_ptr(bx, by, z);
    g_bc_used++;
    if (!c.blk) return nullptr;
    c.pad = nullptr;
    c.memo = nullptr;
    c.memo_tried = 0;
    c.has_edging = 0;
    c.near_snowy = -1;
    c.snow_near = -1;
    c.sig_ready = 0;
    c.pad_tried = 0;
    memset(c.snow, 0, sizeof c.snow);
    void* const* first;
    void* const* last;
    if (events_of(c.blk, first, last)) {
        for (void* const* p = first; p < last; p++) {
            const uint8_t* ev = (const uint8_t*)*p;
            if (!ev || *(const uint64_t*)ev != B.spatter_vtable) continue;
            if (*(const int16_t*)(ev + B.off_ev_mat_type) != B.snow_mat_type) continue;
            if (*(const int16_t*)(ev + B.off_ev_mat_state) != B.snow_mat_state) continue;
            const uint8_t* amount = ev + B.off_ev_amount;
            for (int i = 0; i < 256; i++) if (amount[i] > c.snow[i]) c.snow[i] = amount[i];
        }
    }
    uint8_t most = 0;
    for (int i = 0; i < 256; i++) if (c.snow[i] > most) most = c.snow[i];
    c.max_snow = most;
    return &c;   // (its fingerprint only when a kept block asks for it: sig_of)
}
static inline BlockCache* bc_of(int32_t x, int32_t y, int32_t z) { return bc_at(x >> 4, y >> 4, z); }

static uint64_t block_sig(const BlockCache& c) {
    uint64_t h = mix_bytes(0x243F6A8885A308D3ull, c.snow, 256);
    h = mix_bytes(h, c.blk + B.off_tiletype, 512);
    const uint64_t keep = B.hidden_mask | B.outside_mask;
    h = mix_bytes(h, c.blk + B.off_designation, 1024, keep | (keep << 32));
    void* const* first;
    void* const* last;
    if (B.grass_vtable && events_of(c.blk, first, last)) {
        for (void* const* p = first; p < last; p++) {
            const uint8_t* ev = (const uint8_t*)*p;
            if (!ev || *(const uint64_t*)ev != B.grass_vtable) continue;
            h = mix(h, (uint64_t)(uint32_t)*(const int32_t*)(ev + B.off_gev_plant));
            h = mix_bytes(h, ev + B.off_gev_amount, 256);
        }
    }
    return h;
}

// Each tile's grass edging ID (0: none) for block blk, into out[256].
static void edging_of(const uint8_t* blk, uint8_t* out) {
    uint8_t best[256];
    int32_t plant[256];
    memset(best, 0, sizeof best);
    for (int i = 0; i < 256; i++) plant[i] = -1;
    void* const* first;
    void* const* last;
    if (B.grass_vtable && events_of(blk, first, last)) {
        for (void* const* p = first; p < last; p++) {
            const uint8_t* ev = (const uint8_t*)*p;
            if (!ev || *(const uint64_t*)ev != B.grass_vtable) continue;
            int32_t pi = *(const int32_t*)(ev + B.off_gev_plant);
            const uint8_t* amount = ev + B.off_gev_amount;
            for (int i = 0; i < 256; i++) if (amount[i] > best[i]) { best[i] = amount[i]; plant[i] = pi; }
        }
    }
    for (int i = 0; i < 256; i++) {
        uint8_t id = 0;
        if ((flags_of(type_in(blk, i)) & TT_GRASS) && plant[i] >= 0 && plant[i] < PLANTS) id = B.plant_edging[plant[i]];
        out[i] = id;
    }
}
static void fill_edging(BlockCache& c) {
    edging_of(c.blk, c.edging);
    c.has_edging = 1;
}

// Whether any tile of a block or of the four blocks beside it has SNOWY
// snow: if not, no tile in it has a snowy side (open air far from snow
// needs no closer look).
// A block's fingerprint, worked out the first time a kept block asks for it this frame. (It was
// worked out for every block read: 2 KB hashed a block, about 390 us a frame on a 160 x 90 view,
// with snow or without.)
static uint64_t sig_of(BlockCache* c) {
    if (!c->sig_ready) { c->sig = block_sig(*c); c->sig_ready = 1; }
    return c->sig;
}

// NO SNOW NEAR: whether any tile in the block or the 8 round it is SNOWY. Without one, every rule in
// the block makes no record (tile_rule: a ramp or a floor needs its own SNOWY snow or a SNOWY side,
// a side's trunk needs SNOWY sides of its own, at most two tiles away; open air and a trunk need a
// SNOWY block beside), so the walk only needs to know where it goes on down (bare_walk).
static bool snow_near(BlockCache& c) {
    if (c.snow_near < 0) {
        const int snowy = B.snowy_from;
        bool any = c.max_snow >= snowy;
        for (int i = -1; i <= 1 && !any; i++)
            for (int j = -1; j <= 1 && !any; j++) {
                if (!i && !j) continue;
                const BlockCache* n = bc_at(c.bx + i, c.by + j, c.z);
                any = n && n->max_snow >= snowy;
            }
        c.snow_near = any ? 1 : 0;
    }
    return c.snow_near == 1;
}

static bool near_snowy(BlockCache& c) {
    if (c.near_snowy < 0) {
        const int snowy = B.snowy_from;
        bool any = c.max_snow >= snowy;
        static const int DX[4] = {0, -1, 1, 0}, DY[4] = {1, 0, 0, -1};
        for (int k = 0; k < 4 && !any; k++) {
            const BlockCache* n = bc_at(c.bx + DX[k], c.by + DY[k], c.z);
            any = n && n->max_snow >= snowy;
        }
        c.near_snowy = any ? 1 : 0;
    }
    return c.near_snowy == 1;
}

// The four sides, in floor_flag's byte order (snow_ramps.lua: OVERHANG_SIDES).
static const int SIDE_DX[4] = {0, -1, 1, 0};   // S, W, E, N
static const int SIDE_DY[4] = {1, 0, 0, -1};
static const int SIDE_PIECE[4] = {1, 2, 3, 0}; // each side's edge piece: S, W, E, N in edge_art
// The corners (grass.lua: CORNERS), with the two sides each sits between.
static const int CORNER_DX[4] = {-1, 1, -1, 1};   // NW, NE, SW, SE
static const int CORNER_DY[4] = {-1, -1, 1, 1};
static const int CORNER_SIDE1[4] = {1, 2, 0, 0};  // W, E, S, S
static const int CORNER_SIDE2[4] = {3, 3, 1, 2};  // N, N, W, E

// =====================================================================
// THE SNOW'S NUMBERS (snow_ramps.lua: lattice, drift, level_for, corner_level)
// =====================================================================
// The same arithmetic as the Lua, so every tile gets the same thin piece
// (checked: the same levels and versions on 7392 tiles and amounts).
// Lua 5.3 integers are 64-bit, as here; none of these products overflow.
static double lattice(int64_t ix, int64_t iy, int64_t seed) {
    uint64_t h = (uint64_t)(ix * 374761393LL + iy * 668265263LL + seed * 2246822519LL) & 0xffffffffull;
    h = ((h ^ (h >> 13)) * 1274126177ull) & 0xffffffffull;
    return (double)((h ^ (h >> 16)) & 0xffff) / 65535.0;
}

// A smooth noise over map tiles, -1 to 1, the same every time for a tile:
// two scales (DRIFT_TILES 11 and 5, weights 0.7 and 0.3).
static double drift(double x, double y) {
    static const int TILES[2] = {11, 5};
    static const double WEIGHTS[2] = {0.7, 0.3};
    double total = 0;
    for (int n = 0; n < 2; n++) {
        double fx = x / TILES[n], fy = y / TILES[n];
        double ixf = std::floor(fx), iyf = std::floor(fy);
        double tx = fx - ixf, ty = fy - iyf;
        tx = tx * tx * (3 - 2 * tx);
        ty = ty * ty * (3 - 2 * ty);
        int64_t ix = (int64_t)ixf, iy = (int64_t)iyf;
        double a = lattice(ix, iy, n + 1), b = lattice(ix + 1, iy, n + 1);
        double c = lattice(ix, iy + 1, n + 1), d = lattice(ix + 1, iy + 1, n + 1);
        double v = (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty;
        total += (v * 2 - 1) * WEIGHTS[n];
    }
    return total;
}

// The thin sheet's level (0-3) for an amount of snow and the noise at the
// place (`d`, from drift): from (amount - 100) / 155 with a little slow
// noise (LEVEL_SWAY 0.07), past each of LEVEL_FROM 0.16, 0.39 and 0.71.
static inline int level_from(double amount, double d) {
    const double snowy = B.snowy_from;
    double a = amount < snowy ? snowy : (amount > 255 ? 255 : amount);
    double v = (a - snowy) / (255 - snowy) + d * 0.07;
    return (v >= 0.16) + (v >= 0.39) + (v >= 0.71);
}

// ---- EACH BLOCK COLUMN'S FIXED NUMBERS, FOR THE SESSION ----
// The noise and the versions depend on the place alone, so they're worked
// out once for each 16 x 16 column of the map the view has shown (about
// 4.5 KB each) and kept: the noise at each tile and at each tile's top
// left corner, and its thin and inside versions (lattice seed 9).
struct ColStatic { double tile[256]; double corner[256]; uint8_t v_thin[256]; uint8_t v_inside[256]; };
static ColStatic** g_cols = nullptr;
static int32_t g_cols_bxn = 0, g_cols_byn = 0, g_cols_made = 0;

static void free_cols() {
    if (g_cols) {
        for (int32_t k = 0; k < g_cols_bxn * g_cols_byn; k++) free(g_cols[k]);
        free(g_cols);
    }
    g_cols = nullptr;
    g_cols_bxn = g_cols_byn = g_cols_made = 0;
}

static const ColStatic* col_static(int32_t bx, int32_t by) {
    if (g_cols_bxn != g_map.bxn || g_cols_byn != g_map.byn) {   // another map size: start afresh
        free_cols();
        g_cols = (ColStatic**)calloc((size_t)g_map.bxn * g_map.byn, sizeof(ColStatic*));
        if (!g_cols) return nullptr;
        g_cols_bxn = g_map.bxn;
        g_cols_byn = g_map.byn;
    }
    if (!g_cols || bx < 0 || by < 0 || bx >= g_cols_bxn || by >= g_cols_byn) return nullptr;
    ColStatic*& p = g_cols[bx * g_cols_byn + by];
    if (!p) {
        p = (ColStatic*)malloc(sizeof(ColStatic));
        if (!p) return nullptr;
        g_cols_made++;
        for (int t = 0; t < 256; t++) {
            const int32_t x = bx * 16 + (t >> 4), y = by * 16 + (t & 15);
            p->tile[t] = drift(x, y);
            p->corner[t] = drift(x - 0.5, y - 0.5);
            double l9 = lattice(x, y, 9);
            p->v_thin[t] = (uint8_t)((int)std::floor(l9 * THIN_VARIANTS) % THIN_VARIANTS);
            p->v_inside[t] = (uint8_t)((int)std::floor(l9 * INSIDE_VARIANTS) % INSIDE_VARIANTS);
        }
    }
    return p;
}

// ---- THE PADS: A BLOCK'S NEIGHBOURHOOD, ONCE A FRAME ----
// Every rule looks at a tile's neighbours, and the corners at tiles two
// away. Looked up one by one, through the block table, those were most of
// the plan's time (profiled: corners 28%, diagonals 17%, block lookups
// 15%). So for a block with snow to draw, its tiles and those round it are
// copied once a frame into plain grids, and every rule reads from them:
//   snow, info   the tiles and two rows round (20 x 20): snow, and the
//                tile's kind (TT_*), with P_PRESENT where its block exists
//                and P_OFFMAP off the edge of the map
//   edging       the tiles and one row round (18 x 18): grass edging
//   rim          the same tiles: less than SNOWY, or a side neighbour with
//                less (snow_ramps.lua: corner_level's test, tile by tile)
//   corner       the level at the top left corner of the tiles and one
//                more row and column (17 x 17): edge_level where any of
//                the four tiles meeting there is a rim, else from their
//                snow together (snow_ramps.lua: corner_level; kept 3 s
//                there), worked out for the whole block in one sweep.
// Grids are indexed from the block's own corner: [x + 2][y + 2] in the
// 20 x 20 ones, [x + 1][y + 1] in the 18 x 18 ones, [x][y] in the corners,
// with x and y counted from the block's first tile.
// (Simulated, a 160 x 90 view all snow over two open levels: the plan went
// from 28 to 14 million instructions a frame, about 1.8 ms to 1.0 ms on a
// 2.1 GHz VM, with every record the same as before, check/sim.cpp. The
// rest is spread thin; skipping blocks whose neighbourhood hasn't changed
// since the last frame is the next step if it's needed.)
enum : uint8_t { P_PRESENT = 64, P_OFFMAP = 128 };   // in Pad.info, above the TT_* bits it keeps
static const uint8_t TT_PAD_BITS = 63;   // the TT_* bits Pad.info keeps (TT_RAMP to TT_GRASS)
enum : uint8_t { PAD_EDGING = 1, PAD_CORNERS = 2 };
struct Pad {
    uint8_t snow[20][20];
    uint8_t info[20][20];
    uint8_t edging[18][18];
    uint8_t rim[18][18];
    int8_t  corner[17][17];
    uint8_t have;
    const ColStatic* cs;   // the block column's fixed numbers (null if they couldn't be made)
};
static const int PAD_MAX = 2048;
static Pad g_pads[PAD_MAX];
static uint32_t g_pads_used = 0;   // pads made this frame

// The neighbourhood of a block, with at least the parts in `need`; null if
// there's no room left this frame (counted as a block not read).
static Pad* pad_of(BlockCache& c, uint8_t need) {
    if (!c.pad) {
        if (c.pad_tried) return nullptr;
        c.pad_tried = 1;
        if (g_pads_used >= (uint32_t)PAD_MAX) { B.blocks_full++; return nullptr; }
        Pad& p = g_pads[g_pads_used++];
        p.have = 0;
        p.cs = col_static(c.bx, c.by);
        BlockCache* nb[3][3];
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++) nb[i][j] = (i == 1 && j == 1) ? &c : bc_at(c.bx + i - 1, c.by + j - 1, c.z);
        const int32_t x0 = c.bx * 16, y0 = c.by * 16;
        for (int lx = -2; lx < 18; lx++) {
            const int i = lx < 0 ? 0 : (lx > 15 ? 2 : 1);
            const int32_t x = x0 + lx;
            for (int ly = -2; ly < 18; ly++) {
                const int j = ly < 0 ? 0 : (ly > 15 ? 2 : 1);
                const int32_t y = y0 + ly;
                uint8_t snow = 0, info = 0;
                if (x < 0 || y < 0 || x >= g_map.x_end || y >= g_map.y_end) info = P_OFFMAP;
                else if (const BlockCache* n = nb[i][j]) {
                    const int t = tile_of(x, y);
                    snow = n->snow[t];
                    info = (uint8_t)((flags_of(type_in(n->blk, t)) & TT_PAD_BITS) | P_PRESENT);   // (TT_SOIL, TT_GRASS_ANY share P_*'s bits: left out)
                }
                p.snow[lx + 2][ly + 2] = snow;
                p.info[lx + 2][ly + 2] = info;
            }
        }
        c.pad = &p;
    }
    Pad& p = *c.pad;
    if ((need & PAD_EDGING) && !(p.have & PAD_EDGING)) {
        const int32_t x0 = c.bx * 16, y0 = c.by * 16;
        for (int lx = -1; lx < 17; lx++)
            for (int ly = -1; ly < 17; ly++) {
                uint8_t id = 0;
                if (p.info[lx + 2][ly + 2] & P_PRESENT) {
                    BlockCache* n = (lx >= 0 && lx < 16 && ly >= 0 && ly < 16) ? &c : bc_of(x0 + lx, y0 + ly, c.z);
                    if (n) {
                        if (!n->has_edging) fill_edging(*n);
                        id = n->edging[tile_of(x0 + lx, y0 + ly)];
                    }
                }
                p.edging[lx + 1][ly + 1] = id;
            }
        p.have |= PAD_EDGING;
    }
    if ((need & PAD_CORNERS) && !(p.have & PAD_CORNERS)) {
        const int snowy = B.snowy_from;
        for (int a = 1; a < 19; a++)          // tiles -1 to 16, in the 20 x 20 grids
            for (int b = 1; b < 19; b++)
                p.rim[a - 1][b - 1] = p.snow[a][b] < snowy || p.snow[a - 1][b] < snowy || p.snow[a + 1][b] < snowy ||
                                      p.snow[a][b - 1] < snowy || p.snow[a][b + 1] < snowy;
        const int32_t x0 = c.bx * 16, y0 = c.by * 16;
        // the noise at the corners: this block column's, and for the 17th row and column its neighbours'
        const ColStatic* cols[2][2] = {{p.cs, col_static(c.bx, c.by + 1)},
                                       {col_static(c.bx + 1, c.by), col_static(c.bx + 1, c.by + 1)}};
        for (int cx = 0; cx < 17; cx++)
            for (int cy = 0; cy < 17; cy++) {
                // the four tiles meeting at the corner: (cx - 1, cy - 1) to (cx, cy)
                if (p.rim[cx][cy] || p.rim[cx + 1][cy] || p.rim[cx][cy + 1] || p.rim[cx + 1][cy + 1]) {
                    p.corner[cx][cy] = (int8_t)B.edge_level;
                    continue;
                }
                const int total = p.snow[cx + 1][cy + 1] + p.snow[cx + 2][cy + 1] + p.snow[cx + 1][cy + 2] + p.snow[cx + 2][cy + 2];
                const int32_t x = x0 + cx, y = y0 + cy;
                const ColStatic* cs = cols[cx >> 4][cy >> 4];
                p.corner[cx][cy] = (int8_t)level_from(total / 4.0, cs ? cs->corner[tile_of(x, y)] : drift(x - 0.5, y - 0.5));
            }
        p.have |= PAD_CORNERS;
    }
    return &p;
}

// =====================================================================
// THE VIEW AS DRAWN
// =====================================================================
// The view's map corner is window_x, window_y, window_z (DFHack's
// guidm.Viewport.get reads the same globals). DF draws the buffers on the
// game thread with the corner as it is then; the hook runs on the main
// thread while the game thread goes on with its next tick, which can move
// the view (test 1: the square jittered on fast zooms). So the corner is
// read in the prerender call, just before DF draws, and the plan is made
// from that.
static void read_view_as_drawn() {
    if (!B.window_x || !B.window_y || !B.window_z) return;
    B.drawn_x = *(const int32_t*)(uintptr_t)B.window_x;
    B.drawn_y = *(const int32_t*)(uintptr_t)B.window_y;
    B.drawn_z = *(const int32_t*)(uintptr_t)B.window_z;
    B.have_drawn = 1;
}

// =====================================================================
// THE SNOW: THE PLAN (game thread; the rules of snow_ramps.lua's work_out_below)
// =====================================================================
// For each screen column, the levels are walked down from the view's own
// while the tile is open (EMPTY or RAMP_TOP: the level below shows
// through), up to MOST_DEPTH below. An open level with snowy neighbours
// gets their snowy edges (OPEN; snow_ramps.lua: work_out's open_levels, on
// levels above the deepest looked at). The first solid tile is the one
// shown:
//   * a ramp with SNOWY snow or more: its snowy cell (RAMP);
//   * a floor (any basic shape Floor) with SNOWY or more: a snowy floor
//     (FLOOR), with which sides its snow joins, whose overhangs it keeps
//     and which sides lie against full snow;
//   * a bare floor outdoors with a snowy neighbour: its snowy edges (BARE);
//   * a tree's lowest trunk tile with a snowy neighbour: thin snow under it
//     (TRUNK; TRUNKS ON THE GROUND).
// A hidden tile stops the walk (DF shows it black). Every level is looked
// at in its own viewport (slot n: the level n below the view), lined up
// with the main one: map tile (window_x + sx, window_y + sy) is index
// sx * dim_y + sy in every slot.
enum : uint8_t { K_RAMP = 1, K_FLOOR, K_BARE, K_TRUNK, K_OPEN };
enum : uint8_t { R_BRANCH = 1 };
struct Rec {
    int32_t x, y;        // the map tile
    int32_t index;       // its viewport cell
    uint8_t slot;        // which viewport (depth below the view)
    uint8_t kind;        // K_*
    uint8_t join;        // FLOOR: sides the snow joins (bits 1 S, 2 W, 4 E, 8 N)
    uint8_t snowy;       // sides with a snowy neighbour
    uint8_t full;        // FLOOR: sides against full snow (255)
    uint8_t keep;        // FLOOR, TRUNK: sides whose overhang byte is kept
    uint8_t flags;       // R_BRANCH: a tree's branch
    uint8_t amount;      // FLOOR: the tile's snow
    uint8_t level;       // the thin level (FLOOR: from its snow; TRUNK: from SNOWY)
    uint8_t combo;       // the inside piece's corner levels
    uint8_t vthin;       // the thin piece's version
    uint8_t vinside;     // the inside piece's version
    uint8_t block;       // the place on the thin sheet's repeat
    uint8_t own_edge;    // the tile's own grass edging (0: none)
    uint8_t diag[4];     // each corner's diagonal: its edging if snowy grass, else 0 (NW, NE, SW, SE)
    uint8_t pad[2];
};
static Rec      g_recs[MAX_RECORDS];
static uint32_t g_rec_n = 0;
static bool     g_plan_ready = false;
static int32_t  g_plan_x, g_plan_y, g_plan_z;   // the corner the plan was made for

// Which sides of tile (lx, ly) of a pad (-1 to 16 from the block's corner)
// have a neighbour with SNOWY snow or more.
static inline uint8_t snowy_sides(const Pad& p, int lx, int ly) {
    const int snowy = B.snowy_from;
    uint8_t sides = 0;
    for (int b = 0; b < 4; b++)
        if (p.snow[lx + SIDE_DX[b] + 2][ly + SIDE_DY[b] + 2] >= snowy) sides |= (uint8_t)(1 << b);
    return sides;
}

// TRUNKS ON THE GROUND (grungeisdead's copy, 2026-11-18): whether the trunk
// tile at (x, y, z) is a tree's lowest, standing on the ground (the tile
// below isn't part of the tree; roots are their own material, ROOT). The
// rule giving a trunk thin snow (Poss's: snow_ramps.lua, work_out_below)
// counted snowy branches beside it as ground, so every trunk tile up in the
// canopy got a square of snow behind it (seen in play, test 4B). That snow
// was covering the levels DF shows through those trunk tiles, so the walk
// now goes on down through them to the ground (walk_view).
static bool g_rule_looked_below = false;   // set when a rule reads the level below (BLOCKS KEPT)
static bool trunk_on_ground(int32_t x, int32_t y, int32_t z) {
    g_rule_looked_below = true;
    const BlockCache* below = bc_of(x, y, z - 1);
    return !below || !(flags_of(type_in(below->blk, tile_of(x, y))) & TT_TREE);
}

// For a snowy or bare floor outdoors, side by side (snow_ramps.lua,
// work_out_below):
//   * a neighbour off the edge of the map counts as this tile's own snow;
//   * a neighbour with no snow that's a trunk with a snowy side of its own
//     counts as SNOWY (it gets thin snow, TRUNK);
//   * below SNOWY: its overhang byte is kept; the snow still joins to a
//     ramp beside it (the slope's art takes over), and to an open
//     neighbour whose first solid tile below has SNOWY (full if 255);
//   * SNOWY or more: a snowy side, joined (full if 255).
static void floor_sides(const Pad& p, int lx, int ly, int32_t x, int32_t y, int32_t z, int amount, Rec& r) {
    const int snowy = B.snowy_from;
    for (int b = 0; b < 4; b++) {
        const uint8_t bit = (uint8_t)(1 << b);
        const int nlx = lx + SIDE_DX[b], nly = ly + SIDE_DY[b];
        int ns = p.snow[nlx + 2][nly + 2];
        const uint8_t info = p.info[nlx + 2][nly + 2];
        if (info & P_OFFMAP) ns = amount;
        else if ((info & P_PRESENT) && ns == 0 && (info & TT_TRUNK) && snowy_sides(p, nlx, nly) &&
                 trunk_on_ground(x + SIDE_DX[b], y + SIDE_DY[b], z)) ns = snowy;
        if (ns < snowy) {
            r.keep |= bit;
            if (!(info & P_PRESENT)) continue;
            if (info & TT_RAMP) {
                r.join |= bit;
            } else if (info & TT_OPEN) {
                // (BLOCKS KEPT) the ground seen below an open neighbour reaches further down than a
                // kept block looks: marked here, and worked out at every walk (below_ground)
                r.pad[1] |= bit;
            }
        } else {
            r.snowy |= bit;
            r.join |= bit;
            if (ns >= 255) r.full |= bit;
        }
    }
}

// An open neighbour (marked in pad[1] by floor_sides): followed down to the
// first solid tile; if that's snowy, the snow here runs to the lip (full if
// 255). Worked out at each walk, not kept.
static void below_ground(Rec& r, int32_t x, int32_t y, int32_t z) {
    const int snowy = B.snowy_from;
    for (int b = 0; b < 4; b++) {
        const uint8_t bit = (uint8_t)(1 << b);
        if (!(r.pad[1] & bit)) continue;
        const int32_t nx = x + SIDE_DX[b], ny = y + SIDE_DY[b];
        const int nt = tile_of(nx, ny);
        int below = 0;
        for (int down = 1; down <= MOST_DEPTH; down++) {
            const BlockCache* bc = bc_of(nx, ny, z - down);
            if (!bc) break;
            if (!(flags_of(type_in(bc->blk, nt)) & TT_OPEN)) { below = bc->snow[nt]; break; }
        }
        if (below >= snowy) {
            r.join |= bit;
            if (below >= 255) r.full |= bit;
        }
    }
}

// The corners' diagonals for the snowy edges: each one's grass edging,
// where it has SNOWY snow (snow_ramps.lua: add_snowy_edges).
static void corner_diagonals(const Pad& p, int lx, int ly, Rec& r) {
    const int snowy = B.snowy_from;
    r.own_edge = p.edging[lx + 1][ly + 1];
    for (int k = 0; k < 4; k++) {
        const int dlx = lx + CORNER_DX[k], dly = ly + CORNER_DY[k];
        r.diag[k] = p.snow[dlx + 2][dly + 2] >= snowy ? p.edging[dlx + 1][dly + 1] : 0;
    }
}

// The thin sheet's choices for a tile (snow_ramps.lua: thin_version): its
// level, its version, its place on the repeat, and (if `corners`, from the
// pad's corners) the inside piece's corner levels.
static void thin_place(const Pad* p, int lx, int ly, int32_t x, int32_t y, int amount, bool corners, Rec& r) {
    const int t = tile_of(x, y);
    const ColStatic* cs = p ? p->cs : col_static(x >> 4, y >> 4);
    r.level = (uint8_t)level_from(amount, cs ? cs->tile[t] : drift(x, y));
    if (cs) {
        r.vthin = cs->v_thin[t];
        r.vinside = cs->v_inside[t];
    } else {
        double l9 = lattice(x, y, 9);
        r.vthin = (uint8_t)((int)std::floor(l9 * THIN_VARIANTS) % THIN_VARIANTS);
        r.vinside = (uint8_t)((int)std::floor(l9 * INSIDE_VARIANTS) % INSIDE_VARIANTS);
    }
    r.block = (uint8_t)((y % THIN_REPEAT) * THIN_REPEAT + x % THIN_REPEAT);
    if (!corners || !p) return;
    const int nw = p->corner[lx][ly], ne = p->corner[lx + 1][ly];
    const int sw = p->corner[lx][ly + 1], se = p->corner[lx + 1][ly + 1];
    r.combo = (uint8_t)(((nw * THIN_LEVELS + ne) * THIN_LEVELS + sw) * THIN_LEVELS + se);
}

// ---- THE RULE FOR ONE TILE ----
// What the walk does at map tile t of block c, as a record with no place on
// screen yet: whether the walk stops there or goes on down (pad[0]: A_STOP
// or A_ON), and the record it makes there, if any (kind 0: none). Any
// record's fields are the map's alone, so the same tile gives the same
// record every frame until the map changes (BLOCKS KEPT). An open tile's
// record is only made by the walk above MOST_DEPTH; a floor's open sides
// are left in pad[1] for below_ground.
enum : uint8_t { A_STOP = 0, A_ON = 1 };
static void tile_rule(BlockCache& c, int t, Rec& r) {
    memset(&r, 0, sizeof r);
    const int snowy = B.snowy_from;
    const int lx = t >> 4, ly = t & 15;
    const int32_t x = c.bx * 16 + lx, y = c.by * 16 + ly, z = c.z;
    r.x = x; r.y = y;
    r.pad[0] = A_STOP;
    const uint32_t des = des_in(c.blk, t);
    if (des & B.hidden_mask) return;         // DF shows a hidden tile black
    const uint8_t f = flags_of(type_in(c.blk, t));

    // ---- an open level: the snowy edges its neighbours drop onto it ----
    if (f & TT_OPEN) {
        r.pad[0] = A_ON;
        if (!near_snowy(c)) return;
        const Pad* p = pad_of(c, 0);
        const uint8_t sides = p ? snowy_sides(*p, lx, ly) : 0;
        if (!sides) return;
        r.kind = K_OPEN;
        r.snowy = sides;
        corner_diagonals(*pad_of(c, PAD_EDGING), lx, ly, r);
        return;
    }

    // ---- a ramp or a floor ----
    if (f & (TT_RAMP | TT_FLOOR)) {
        const int amount = c.snow[t];
        if (f & TT_RAMP) {
            if (amount >= snowy) r.kind = K_RAMP;
            return;
        }
        // tiles under a tree's canopy count as indoors, but the game still lays snow on them
        const bool outdoors = (des & B.outside_mask) || amount > 0;
        if (!outdoors) return;
        const Pad* p = pad_of(c, 0);
        if (!p) return;
        Rec probe;
        memset(&probe, 0, sizeof probe);
        floor_sides(*p, lx, ly, x, y, z, amount, probe);
        if (amount >= snowy) {
            r.kind = K_FLOOR;
            r.join = probe.join; r.snowy = probe.snowy; r.full = probe.full; r.keep = probe.keep;
            r.pad[1] = probe.pad[1];
            r.amount = (uint8_t)amount;
            r.flags = (f & TT_TREE) ? R_BRANCH : 0;
            p = pad_of(c, PAD_EDGING | PAD_CORNERS);
            thin_place(p, lx, ly, x, y, amount, true, r);
            corner_diagonals(*p, lx, ly, r);
        } else if (probe.snowy) {
            r.kind = K_BARE;
            r.snowy = probe.snowy;
            r.flags = (f & TT_TREE) ? R_BRANCH : 0;
            corner_diagonals(*pad_of(c, PAD_EDGING), lx, ly, r);
        }
        return;
    }

    // ---- a tree's trunk: thin snow under its lowest tile, joined to its snowy sides ----
    if (f & TT_TRUNK) {
        // (TRUNKS ON THE GROUND) a trunk tile above the tree's lowest is see-through: DF shows the
        // levels below it (seen in play: with nothing drawn there, the bare grass at the tree's foot
        // showed round the trunk), so the walk goes on down, as for open air
        if (!trunk_on_ground(x, y, z)) { r.pad[0] = A_ON; return; }
        const Pad* p = near_snowy(c) ? pad_of(c, 0) : nullptr;
        const uint8_t sides = p ? snowy_sides(*p, lx, ly) : 0;
        if (!sides) return;
        r.kind = K_TRUNK;
        r.snowy = sides;
        r.keep = (uint8_t)(~sides & 15);
        // (no snow of its own: thin at SNOWY; the corners only for the inside piece)
        if (sides == 15) p = pad_of(c, PAD_CORNERS);
        thin_place(p, lx, ly, x, y, snowy, sides == 15, r);
        return;
    }
    // anything else solid hides what's below: the walk stops
}

// ---- BLOCKS KEPT ----
// The walk used to work out every tile in view from scratch every frame:
// about 1 ms a frame in play (test 4: 1070.8 us, worst 4144.7), against
// 0.26 ms for the ramps alone. A tile's rule reads only its own block, the
// 8 round it and, for trunks only, the 9 below (is the tile below part of
// the tree), so each block's 256 rules are kept, with the fingerprints of
// those blocks, and worked out again only when one of them changes. The 9
// below count only for a block whose rules looked there (a trunk in or
// beside it); one starting to need them has changed its own fingerprint or
// a neighbour's first. Kept by block position across frames; one in use
// this frame is never given up. (Simulated, 160 x 90 all snow: the plan
// from about 1.0 ms to 0.4 ms a frame on a 2.1 GHz VM, records the same.)
struct BlockMemo { int32_t bx, by, z; uint32_t used; uint64_t near_sig; uint8_t looks_below; Rec t[256]; };
static const int MEMO_SLOTS = 2048, MEMO_PROBE = 16;
static BlockMemo* g_memo[MEMO_SLOTS];
static int32_t g_memo_made = 0;

static uint64_t near_sig_of(BlockCache& c, bool below) {
    uint64_t h = 0x13198A2E03707344ull;
    int k = 0;
    for (int dz = 0; dz < (below ? 2 : 1); dz++)
        for (int i = -1; i <= 1; i++)
            for (int j = -1; j <= 1; j++, k++) {
                BlockCache* n = (dz == 0 && i == 0 && j == 0) ? &c : bc_at(c.bx + i, c.by + j, c.z - dz);
                h = mix(h, n ? sig_of(n) : 0x9E3779B97F4A7C15ull * (uint64_t)(k + 1));
            }
    return h;
}

// The kept rules for block c, worked out again if anything they read has
// changed; null if there's no room to keep them (worked out tile by tile).
static BlockMemo* find_memo(BlockCache& c);
static BlockMemo* memo_for(BlockCache& c) {   // (looked for once a frame for each block)
    if (!c.memo_tried) { c.memo_tried = 1; c.memo = find_memo(c); }
    return (BlockMemo*)c.memo;
}
static BlockMemo* find_memo(BlockCache& c) {
    const uint32_t h0 = ((uint32_t)c.bx * 73856093u ^ (uint32_t)c.by * 19349663u ^ (uint32_t)c.z * 83492791u) & (MEMO_SLOTS - 1);
    BlockMemo** slot = nullptr;
    for (int n = 0; n < MEMO_PROBE; n++) {
        BlockMemo*& e = g_memo[(h0 + n) & (MEMO_SLOTS - 1)];
        if (e && e->bx == c.bx && e->by == c.by && e->z == c.z) {
            if (e->near_sig == near_sig_of(c, e->looks_below)) { e->used = g_frame; B.blocks_kept_last++; return e; }
            slot = &e;
            break;
        }
        if (!e) { if (!slot || *slot) slot = &e; continue; }
        if (e->used != g_frame && (!slot || (*slot && (*slot)->used > e->used))) slot = &e;
    }
    if (!slot) return nullptr;
    if (!*slot) {
        *slot = (BlockMemo*)malloc(sizeof(BlockMemo));
        if (!*slot) return nullptr;
        g_memo_made++;
    }
    BlockMemo& m = **slot;
    m.bx = c.bx; m.by = c.by; m.z = c.z;
    m.used = g_frame;
    g_rule_looked_below = false;
    for (int t = 0; t < 256; t++) tile_rule(c, t, m.t[t]);
    m.looks_below = g_rule_looked_below ? 1 : 0;
    m.near_sig = near_sig_of(c, m.looks_below);
    B.blocks_redone_last++;
    return &m;
}

static void free_memos() {
    for (int k = 0; k < MEMO_SLOTS; k++) { free(g_memo[k]); g_memo[k] = nullptr; }
    g_memo_made = 0;
}

// The walk over every screen column (above), each level down from the
// view's own, from the kept rules. Out of room for records it stops where
// it is: what's made so far is still written, rather than the frame going
// without snow.
// NO SNOW NEAR: a tile's rule in a block with no SNOWY tile in it or the 8 round it makes no record;
// only whether the walk goes on down, as tile_rule decides it: on through open air and a trunk above
// a tree's lowest, stopped by a hidden tile and anything else.
static inline uint8_t bare_walk(const BlockCache& c, int t) {
    if (des_in(c.blk, t) & B.hidden_mask) return A_STOP;
    const uint8_t f = flags_of(type_in(c.blk, t));
    if (f & TT_OPEN) return A_ON;
    if ((f & TT_TRUNK) && !trunk_on_ground(c.bx * 16 + (t >> 4), c.by * 16 + (t & 15), c.z)) return A_ON;
    return A_STOP;
}

static void walk_view(int slots, int64_t& columns, int64_t& snowy_floors) {
    const int32_t wx = g_plan_x, wy = g_plan_y, wz = g_plan_z;
    const int32_t dx0 = g_sb[0].dx, dy0 = g_sb[0].dy;
    BlockCache* last[SLOTS] = {};   // each level's block for the last tile looked at: the next is mostly in it
    BlockMemo* last_memo[SLOTS] = {};
    bool last_bare[SLOTS] = {};     // NO SNOW NEAR: that block's rules all make no record
    Rec own;                        // a tile's rule, when its block's can't be kept
    for (int32_t sx = 0; sx < dx0; sx++) {
        const int32_t x = wx + sx;
        if (x < 0 || x >= g_map.x_end) continue;   // off the map: DF draws nothing there
        for (int32_t sy = 0; sy < dy0; sy++) {
            const int32_t y = wy + sy;
            if (y < 0 || y >= g_map.y_end) continue;
            columns++;
            const int t = tile_of(x, y);
            for (int d = 0; d < slots; d++) {
                const int32_t z = wz - d;
                if (z < 0) break;                      // below the bottom of the map
                const SlotBufs& sb = g_sb[d];
                if (sx >= sb.dx || sy >= sb.dy) break;
                BlockCache* c = last[d];
                if (!c || c->bx != (x >> 4) || c->by != (y >> 4)) {
                    c = last[d] = bc_of(x, y, z);
                    last_bare[d] = c && !snow_near(*c);   // (NO SNOW NEAR: no kept rules, no fingerprints)
                    last_memo[d] = c && !last_bare[d] ? memo_for(*c) : nullptr;
                }
                if (!c) break;
                if (last_bare[d]) {
                    if (bare_walk(*c, t) != A_ON) break;
                    continue;
                }
                const Rec* rule = last_memo[d] ? &last_memo[d]->t[t] : nullptr;
                if (!rule) { tile_rule(*c, t, own); rule = &own; }
                if (rule->kind && !(rule->kind == K_OPEN && d >= MOST_DEPTH)) {
                    if (g_rec_n >= MAX_RECORDS) { B.plan_overflow++; return; }
                    Rec& r = g_recs[g_rec_n++];
                    r = *rule;
                    r.index = sx * sb.dy + sy;
                    r.slot = (uint8_t)d;
                    if (r.pad[1]) below_ground(r, x, y, z);
                    if (r.kind == K_FLOOR) snowy_floors++;
                }
                if (rule->pad[0] != A_ON) break;
            }
        }
    }
}

static void plan_snow() {
    g_plan_ready = false;
    g_rec_n = 0;
    if (!B.enabled || !B.hooked || !B.have_drawn || !B.tables_built) return;
    if (!B.main_viewport || !B.block_index || !B.x_count_block || !B.y_count_block ||
        !B.z_count_block || !B.spatter_vtable || !B.off_dim_x || !B.off_dim_y ||
        !B.off_background || !B.off_bg2 || !B.off_spatter || !B.off_floor_flag ||
        !B.off_shadow_flag || !B.off_ramp_flag || !B.off_tiletype || !B.off_designation ||
        !B.off_block_events || !B.off_ev_amount) return;

    const double t0 = ticks_now();
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    g_frame++;
    g_bc_used = 0;
    g_pads_used = 0;
    B.blocks_redone_last = B.blocks_kept_last = 0;
    const int32_t wx = B.drawn_x, wy = B.drawn_y, wz = B.drawn_z;
    g_plan_x = wx; g_plan_y = wy; g_plan_z = wz;

    // ---- THE VIEWPORTS: the main one, then each level below DF shows ----
    int slots = 0;
    for (int s = 0; s < SLOTS; s++) {
        if (s > 0 && (!B.lower_viewports || (uint32_t)s > B.lower_count)) break;
        if (!read_slot(s, g_sb[s])) break;   // DF shows the levels below in order
        slots = s + 1;
    }
    for (int s = slots; s < SLOTS; s++) g_sb[s].usable = false;
    if (!slots) return;

    int64_t columns = 0, snowy_floors = 0;
    walk_view(slots, columns, snowy_floors);

    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.plans++;
    B.columns_last = columns;
    B.records_last = g_rec_n;
    B.snowy_last = snowy_floors;
    B.blocks_last = g_bc_used;
    B.blocks_redone += B.blocks_redone_last;
    B.blocks_kept += B.blocks_kept_last;
    B.plan_us_total += us;
    if (us > B.plan_us_max) B.plan_us_max = us;
    g_plan_ready = true;
}

// =====================================================================
// THE SNOW: STILL OURS (see the top)
// =====================================================================
// The five layers this writes, as one cell's values.
struct CellVals { uint64_t flag; int32_t bg, bg2, spatter; uint32_t shadow; };
static inline bool same(const CellVals& a, const CellVals& b) {
    return a.flag == b.flag && a.bg == b.bg && a.bg2 == b.bg2 && a.spatter == b.spatter && a.shadow == b.shadow;
}
// A cell this changed, with what it held before (the game's own drawing).
struct Saved { int32_t index; int32_t pad; CellVals df; };
// One buffer of one viewport, as this last wrote it: its arrays (the two
// buffers are swapped every frame, swap_arrays), and the cells it changed.
struct Bank {
    uint8_t*  vp;
    int32_t   dx, dy;
    int32_t*  bg;
    int32_t*  bg2;
    int32_t*  spatter;
    uint64_t* flag;
    uint32_t* shadow;
    Saved*    saved;
    uint32_t  n, cap;
    uint64_t  used;         // when last written, to pick one to reuse
};
static Bank     g_banks[SLOTS][2];
static uint64_t g_bank_clock = 0;

static inline bool same_buffer(const Bank& b, const SlotBufs& sb) {
    return b.vp == sb.vp && b.dx == sb.dx && b.dy == sb.dy && b.bg == sb.background && b.bg2 == sb.bg2 &&
           b.spatter == sb.spatter && b.flag == sb.floor_flag && b.shadow == sb.shadow;
}

static inline CellVals read_cell(const SlotBufs& sb, int32_t i) {
    CellVals v;
    v.flag = sb.floor_flag[i];
    v.bg = sb.background[i];
    v.bg2 = sb.bg2[i];
    v.spatter = sb.spatter[i];
    v.shadow = sb.shadow[i];
    return v;
}
static inline void write_cell(const SlotBufs& sb, int32_t i, const CellVals& v) {
    sb.floor_flag[i] = v.flag;
    sb.background[i] = v.bg;
    sb.bg2[i] = v.bg2;
    sb.spatter[i] = v.spatter;
    sb.shadow[i] = v.shadow;
}

// A viewport's buffers as they are, for putting back: as read_slot, but
// whether DF shows it or not (an inactive one keeps its buffers).
static bool read_slot_any(int32_t slot, SlotBufs& s) {
    s.usable = false;
    s.vp = viewport_in(slot);
    if (!s.vp) return false;
    s.dx = *(const int32_t*)(s.vp + B.off_dim_x);
    s.dy = *(const int32_t*)(s.vp + B.off_dim_y);
    if (s.dx <= 0 || s.dy <= 0 || s.dx > MOST_DIM || s.dy > MOST_DIM) return false;
    s.background = *(int32_t* const*)(s.vp + B.off_background);
    s.bg2 = *(int32_t* const*)(s.vp + B.off_bg2);
    s.spatter = *(int32_t* const*)(s.vp + B.off_spatter);
    s.floor_flag = *(uint64_t* const*)(s.vp + B.off_floor_flag);
    s.shadow = *(uint32_t* const*)(s.vp + B.off_shadow_flag);
    s.ramp_flag = *(uint64_t* const*)(s.vp + B.off_ramp_flag);
    return s.background && s.bg2 && s.spatter && s.floor_flag && s.shadow;
}

// PUT BACK, in the prerender call, before DF draws: the buffer DF is about
// to draw into is the one this wrote two frames ago, and every cell it
// changed there gets the game's own values back. So DF, and the overlays
// after it, only ever find their own drawing in the buffers, and what the
// hook reads is theirs alone, whatever DF redraws or leaves. The other
// buffer keeps this snow until its own turn, so the renderer, comparing
// the two, still finds snow beside snow.
// Only a buffer whose arrays are the viewport's own right now is written.
// A zoom keeps the viewport but frees and remakes all its arrays, both
// buffers (g_src graphics.cpp: reshape_viewports, set_dims_and_allocate):
// a kept buffer of another size is gone, and DF draws the new ones afresh.
static void put_back() {
    for (int s = 0; s < SLOTS; s++) {
        Bank* pair = g_banks[s];
        if (!pair[0].n && !pair[1].n) continue;
        SlotBufs now;
        if (!read_slot_any(s, now)) continue;
        for (int k = 0; k < 2; k++) {
            Bank& b = pair[k];
            if (!b.n) continue;
            if (b.vp != now.vp || b.dx != now.dx || b.dy != now.dy) { b.n = 0; continue; }   // remade
            if (!same_buffer(b, now)) continue;   // the other buffer: put back when it comes round
            for (uint32_t m = 0; m < b.n; m++) write_cell(now, b.saved[m].index, b.saved[m].df);
            B.cells_restored += b.n;
            b.n = 0;
        }
    }
}

// The bank for a viewport's buffer at this write: the one kept for that
// buffer, else the older of the two, taken for it.
static Bank* bank_for(int s, const SlotBufs& sb) {
    Bank* pair = g_banks[s];
    Bank* b;
    if (same_buffer(pair[0], sb)) b = &pair[0];
    else if (same_buffer(pair[1], sb)) b = &pair[1];
    else {
        b = pair[0].used <= pair[1].used ? &pair[0] : &pair[1];
        b->vp = sb.vp; b->dx = sb.dx; b->dy = sb.dy;
        b->bg = sb.background; b->bg2 = sb.bg2; b->spatter = sb.spatter; b->flag = sb.floor_flag; b->shadow = sb.shadow;
    }
    b->n = 0;   // (put back before DF drew; anything left is DF's now)
    b->used = ++g_bank_clock;
    return b;
}

static bool save_cell(Bank& b, int32_t i, const CellVals& df) {
    if (b.n >= b.cap) {
        uint32_t cap = b.cap ? b.cap * 2 : 4096;
        Saved* grown = (Saved*)realloc(b.saved, (size_t)cap * sizeof(Saved));
        if (!grown) return false;
        b.saved = grown;
        b.cap = cap;
    }
    Saved& v = b.saved[b.n++];
    v.index = i;
    v.df = df;
    return true;
}

// =====================================================================
// THE SNOW: THE WRITE (main thread, in the hook)
// =====================================================================
// Every record decided first, from the game's own drawing (STILL OURS),
// then every write made: a decision never reads another's write.
enum : uint8_t { W_BG = 1, W_BG2, W_SPATTER, W_FLOOR_FLAG, W_SHADOW };
struct Write { int32_t index; uint8_t slot; uint8_t field; uint16_t pad; uint64_t value; };
static Write    g_writes[MAX_WRITES];
static uint32_t g_write_n = 0;

static inline void put(int s, int32_t i, uint8_t field, uint64_t value) {
    if (g_write_n >= MAX_WRITES) { B.plan_overflow++; return; }
    Write& w = g_writes[g_write_n++];
    w.index = i; w.slot = (uint8_t)s; w.field = field; w.value = value;
}

// Each layer where `want` differs from the game's drawing, written.
static void put_cell(int s, int32_t i, const CellVals& df, const CellVals& want) {
    if (want.bg != df.bg) put(s, i, W_BG, (uint64_t)(uint32_t)want.bg);
    if (want.bg2 != df.bg2) put(s, i, W_BG2, (uint64_t)(uint32_t)want.bg2);
    if (want.spatter != df.spatter) put(s, i, W_SPATTER, (uint64_t)(uint32_t)want.spatter);
    if (want.flag != df.flag) put(s, i, W_FLOOR_FLAG, want.flag);
    if (want.shadow != df.shadow) put(s, i, W_SHADOW, want.shadow);
}

// The bytes of floor_flag for the sides in `sides` (bits 1 S, 2 W, 4 E, 8 N).
static inline uint64_t side_bytes(uint8_t sides) {
    uint64_t m = 0;
    for (int b = 0; b < 4; b++) if (sides & (1 << b)) m |= 0xffull << (8 * b);
    return m;
}

// The FULL piece joined on exactly these sides for map tile (x, y), as
// piece_joined_on chooses (the k of FULL_PIECES), or -1.
static int full_joined(uint8_t sides, int32_t x, int32_t y) {
    sides &= 15;
    int n = B.pieces_n[sides];
    if (n <= 0) return -1;
    if (n > 5) n = 5;
    return full_index(B.pieces_tex[sides][(x * 7 + y * 13) % n]);
}

// The thin version of FULL piece k for a record (snow_ramps.lua:
// thin_version): an inside piece by its corners' levels from
// art/snow_thin_inside.png, any other by its level from art/snow_thin.png;
// the piece itself where there's no thin art for it.
static int32_t thin_version(int k, const Rec& r) {
    const int32_t full = B.full_tex[k];
    int32_t t = 0;
    if (B.full_inside[k]) {
        const int index = (r.combo * INSIDE_VARIANTS + r.vinside) * THIN_REPEAT * THIN_REPEAT + r.block;
        if (index >= 0 && index < INSIDE_N) t = B.inside_tex[index];
    } else if (B.full_col[k] < THIN_COLUMNS) {
        const int row = (r.level * THIN_VARIANTS + r.vthin) * THIN_REPEAT * THIN_REPEAT + r.block;
        const int index = row * THIN_COLUMNS + B.full_col[k];
        if (index >= 0 && index < THIN_N) t = B.thin_tex[index];
    }
    return t ? t : full;
}

// snow_ramps.lua: thin_beside_full. An inside piece, or full snow, has
// nothing to fade towards; beside full snow the thin piece fades to the
// full one (a bake); otherwise the thin piece.
static int32_t thin_beside_full(int k, const Rec& r) {
    const int32_t full = B.full_tex[k];
    if (B.full_inside[k] || r.amount >= 255) return thin_version(k, r);
    const int32_t thin = thin_version(k, r);
    if (thin == full || !(r.full & 15)) return thin;
    const int32_t faded = bake(fade_key(thin, full, r.full), 1, thin, full, r.full & 15, nullptr, 0);
    return faded ? faded : thin;
}

// grass.lua: beats. Whether grass with edging `id` overhangs a tile whose
// own is `own` (0: not grass): custom edging beats generic grass, and
// between two customs the lower number wins.
static inline bool beats(int id, int own) {
    if (!own) return true;
    if (id == own) return false;
    if (id >= 10 && own >= 10) return id < own;
    return id >= 10;
}

// The snowy edge for a cell (snow_ramps.lua: add_snowy_edges, and its draw
// in apply): the edge pieces its snowy neighbours drop on it (sides_too:
// bare ground or an open level; on snow they're only cleared, FLOOR) and
// the corner pieces from snowy diagonals, by the game's own overhangs, in
// one baked texture in the layer above the spatter, if that layer is free
// once the floor's choice is made; with sides_too the overhangs it
// replaces are cleared. SNOWY EDGES AT ONCE: one piece is drawn from the
// snowy pieces baked at start (snowy_single), with no bake to wait for;
// several wait for their bake, the first piece standing in meanwhile.
static void decide_edges(const Rec& r, const CellVals& df, bool sides_too, CellVals& want) {
    int32_t pieces[8];
    int32_t singles[8];   // each piece's snowy version, baked at start (0: none)
    int n = 0;
    uint64_t kept = df.flag;
    uint8_t side_ids[4];
    for (int b = 0; b < 4; b++) {
        const uint8_t byte = (uint8_t)((df.flag >> (8 * b)) & 0xff);
        side_ids[b] = byte;
        if (sides_too && (r.snowy & (1 << b)) && byte) {
            const int32_t art = B.edge_art[byte][SIDE_PIECE[b]];
            if (art) { singles[n] = B.snowy_single[byte][SIDE_PIECE[b]]; pieces[n++] = art; kept &= ~(0xffull << (8 * b)); }
        }
    }
    for (int k = 0; k < 4; k++) {
        const int id = r.diag[k];
        if (id && beats(id, r.own_edge) && side_ids[CORNER_SIDE1[k]] != id && side_ids[CORNER_SIDE2[k]] != id) {
            const int32_t art = B.edge_art[id][4 + k];
            if (art) { singles[n] = B.snowy_single[id][4 + k]; pieces[n++] = art; }
        }
    }
    if (!n) return;
    int32_t tex = (n == 1 && singles[0]) ? singles[0] : bake(edge_key(pieces, n), 3, 0, 0, 0, pieces, n);
    for (int k = 0; k < n && !tex; k++) tex = singles[k];   // (until the bake comes back)
    if (!tex || want.bg2 != 0) return;
    if (sides_too) want.flag = kept;
    want.bg2 = tex;
    B.edges_written++;
}

// A snowy floor (snow_ramps.lua: plan_tile's snowy floors and apply's
// floors): skirts cleared, the overhangs from snowy sides cleared, and the
// game's full snow piece replaced by the one joined towards every snowy
// neighbour and towards bare ground this tile overhangs, thin below full
// snow; something else in the spatter (fallen fruit) lifted to the layer
// above if that's free, else painted over the snow (a bake).
static void decide_floor(const SlotBufs& sb, const Rec& r, const CellVals& df, CellVals& want) {
    const uint64_t overhangs = df.flag;
    const uint64_t kept = overhangs & side_bytes(r.keep);   // (the high bytes go too, as in the Lua)
    const int32_t piece = df.spatter;
    const int fi = full_index(piece);
    const bool other = piece != 0 && !is_page(piece) && !is_ours(piece);
    const int32_t lifted = (other && df.bg2 == 0) ? piece : 0;
    const int32_t under = (other && !lifted) ? piece : 0;
    int32_t joined = 0;
    if (lifted || under || fi >= 0) {
        uint8_t sides = r.join;
        const int32_t sx = r.x - g_plan_x, sy = r.y - g_plan_y;
        for (int b = 0; b < 4; b++) {
            if (sides & (1 << b)) continue;
            const int32_t nx = sx + SIDE_DX[b], ny = sy + SIDE_DY[b];
            if (nx < 0 || ny < 0 || nx >= sb.dx || ny >= sb.dy) continue;
            // the neighbour's byte for the side facing this tile (S and N, W and E): this tile
            // overhangs it (the game's own: nothing is written before every choice is made)
            if ((sb.floor_flag[nx * sb.dy + ny] >> (8 * (3 - b))) & 0xff) sides |= (uint8_t)(1 << b);
        }
        const int k = full_joined(sides, r.x, r.y);
        if (k >= 0) {
            joined = thin_beside_full(k, r);
            if (joined && under) {
                const int32_t w = bake(with_key(joined, under), 2, joined, under, 0, nullptr, 0);
                if (w) joined = w;
            }
            if (joined == piece) joined = 0;
        }
    }
    if (df.shadow != 0 || kept != overhangs || joined) {
        want.shadow = 0;
        want.flag = kept;
        const int32_t snow = joined ? joined : (fi >= 0 ? piece : 0);
        if (snow) {
            if (lifted) want.bg2 = lifted;
            want.spatter = snow;
        }
        B.floors_written++;
    }
}

// The snow for one record, from the game's own values: what the cell
// should hold (the game's values where nothing is to change).
static void decide(const SlotBufs& sb, const Rec& r, const CellVals& df, CellVals& want) {
    want = df;
    const int32_t black = B.black_texpos;
    if (black != 0 && df.bg == black) return;   // a cell DF hasn't drawn yet
    const bool branch = (r.flags & R_BRANCH) != 0;
    switch (r.kind) {
    case K_RAMP: {
        if (df.bg == 0) return;
        const int32_t tex = B.snow_ramp_tex[(sb.ramp_flag[r.index] >> 8) & 0xff];
        if (tex) { want.bg = tex; B.ramps_written++; }
        return;
    }
    case K_FLOOR:
        // (TREES) a branch the game drew no snow piece on is left as the game drew it
        if (branch) { if (full_index(df.spatter) < 0) return; }
        // (UNDRAWN CELLS) no ground drawn yet, or a snowy floor with the game's snow not drawn there yet
        else if (df.bg == 0 || df.spatter == 0) return;
        decide_floor(sb, r, df, want);
        decide_edges(r, df, false, want);
        return;
    case K_BARE:
        if (branch) { if (full_index(df.spatter) < 0) return; }
        else if (df.bg == 0) return;
        decide_edges(r, df, true, want);
        return;
    case K_TRUNK: {
        if (df.spatter != 0) return;   // (only where the game drew nothing in the spatter)
        const int k = full_joined(r.snowy, r.x, r.y);
        if (k < 0) return;
        want.shadow = 0;
        want.flag = df.flag & side_bytes(r.keep);
        want.spatter = thin_version(k, r);
        B.trunks_written++;
        return;
    }
    case K_OPEN:
        decide_edges(r, df, true, want);
        return;
    }
}

static void apply_writes() {
    for (uint32_t n = 0; n < g_write_n; n++) {
        const Write& w = g_writes[n];
        const SlotBufs& sb = g_sb[w.slot];
        switch (w.field) {
        case W_BG:         sb.background[w.index] = (int32_t)(uint32_t)w.value; break;
        case W_BG2:        sb.bg2[w.index] = (int32_t)(uint32_t)w.value; break;
        case W_SPATTER:    sb.spatter[w.index] = (int32_t)(uint32_t)w.value; break;
        case W_FLOOR_FLAG: sb.floor_flag[w.index] = w.value; break;
        case W_SHADOW:     sb.shadow[w.index] = (uint32_t)w.value; break;
        }
    }
}

static size_t held_bytes();   // (THE COLOUR, below)
static uint32_t memory_kb() {
    size_t bytes = (size_t)g_cols_made * sizeof(ColStatic) + (size_t)g_cols_bxn * g_cols_byn * sizeof(void*) +
                   (size_t)g_memo_made * sizeof(BlockMemo);
    for (int s = 0; s < SLOTS; s++)
        for (int k = 0; k < 2; k++) bytes += (size_t)g_banks[s][k].cap * sizeof(Saved);
    bytes += held_bytes();
    return (uint32_t)(bytes / 1024);
}

static void write_snow() {
    if (!g_plan_ready) return;
    g_plan_ready = false;   // one write per plan
    const double t0 = ticks_now();
    take_bakes();

    // ---- THE VIEWPORTS MUST BE THE ONES PLANNED ----
    for (int s = 0; s < SLOTS; s++) {
        SlotBufs& sb = g_sb[s];
        if (!sb.usable) continue;
        SlotBufs now;
        if (!read_slot(s, now) || now.vp != sb.vp || now.dx != sb.dx || now.dy != sb.dy ||
            now.background != sb.background || now.spatter != sb.spatter) {
            B.apply_skipped++;
            return;
        }
        sb = now;
    }

    // ---- DECIDE ----
    Bank* bank[SLOTS];
    for (int s = 0; s < SLOTS; s++) bank[s] = g_sb[s].usable ? bank_for(s, g_sb[s]) : nullptr;
    g_write_n = 0;
    for (uint32_t n = 0; n < g_rec_n; n++) {
        const Rec& r = g_recs[n];
        const int s = r.slot;
        if (!bank[s]) continue;
        const SlotBufs& sb = g_sb[s];
        const int32_t i = r.index;
        const CellVals df = read_cell(sb, i);
        // (at start, the Lua's own drawing, left where DF hasn't redrawn since: left as it is)
        if (is_ours(df.bg) || is_ours(df.bg2) || is_ours(df.spatter)) { B.cells_waiting++; continue; }
        CellVals want;
        decide(sb, r, df, want);
        if (same(want, df)) continue;
        if (!save_cell(*bank[s], i, df)) continue;   // (never changed unless it can be put back)
        put_cell(s, i, df, want);
    }

    // ---- WRITE ----
    apply_writes();

    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.applies++;
    B.apply_us_total += us;
    if (us > B.apply_us_max) B.apply_us_max = us;
    if ((B.applies & 255) == 1) B.memory_kb = memory_kb();
}

// =====================================================================
// THE COLOUR (test 5): colour.lua's per-tile swaps (main thread, in the hook)
// =====================================================================
// WHAT: colour.lua gives the trees, shrubs, buildings, items and the rest
// of what the game draws its look (the weather's colours) by swapping each
// screen cell's texture number for a recoloured copy. In Lua that took a
// plan of every cell (a layer a frame, every quarter second) and a pass
// over the plan every frame, about 3 ms a frame. Here every cell of the
// seven layers (SCREEN_LAYERS), on the view's level and the two below, is
// looked at every frame, after DF and the overlays have drawn, just before
// the snow is decided (colour.lua ran before the hook too, so the snow
// sees the same screen as before).
//
// WHAT LUA KEEPS: making the copies (createTile, only Lua can), and
// knowing what each texture is. That knowledge is two tables by texture
// number that Lua writes and this reads:
//   * g_cflag: CF_* bits, what the texture is;
//   * g_link: for an original with a copy in the look shown, the copy;
//     for a copy (a screen copy, or a copy DF draws through the tables
//     colour points at its copies), its original.
// A texture this has never heard of is asked about (THE QUESTIONS); until
// Lua answers, the cell keeps last frame's copy for a few frames if it had
// one (HELD), or else shows what the game drew.
//
// THE RULES, as colour.lua's plan_cell and put_back_underground:
//   * a copy is first taken back to its original, so a cell DF hasn't
//     redrawn since still counts as showing its picture, and a copy of an
//     earlier look goes to this look's;
//   * underground (the subterranean bit) keeps the game's own colours: any
//     copy there goes back to its original. colour.lua only put back the
//     view's own level; here the two below are put back too, as plan_cell
//     already never swapped them;
//   * in the ground layer only what's in the tables but isn't ground
//     (CF_OTHER: a wooden wall) and anything on a tree tile is swapped;
//   * otherwise an original with a copy in the look shown gets it.
// Copies DF draws through the tables (CF_TABLE) are only ever put back,
// underground, in the ground layer, the layer above it (a cavern tree's
// pieces) and the building layer where there's water (its flows).
//
// SEEN: colour.lua checked once a plan that a number still holds the
// picture its copy was made from (the game reuses numbers for new pictures
// of trees and buildings). Each original shown through its copy is listed
// once a period (col_period, which Lua bumps), for Lua to check.
//
// HELD: the game remakes its put-together pictures (trees, workshops)
// under new numbers as it goes, some 50 tiles a frame. A new number is
// asked about and answered on Lua's next frame, so the cell would show
// the game's colours for a frame: instead it keeps the copy this wrote
// there last frame, for up to HOLD_FRAMES frames, while the view hasn't
// moved.
enum : uint8_t {
    CF_ASKED = 1,       // DLL: asked about where it could be swapped
    CF_ASKED_ELSE = 2,  // DLL: asked about where it couldn't (underground, or plain ground)
    CF_COPY_FOR = 4,    // Lua: an original with a copy in the look shown (g_link: the copy)
    CF_SCREEN = 8,      // Lua: one of colour's screen copies, of any look (g_link: its original)
    CF_TABLE = 16,      // Lua: a copy DF draws through the tables (g_link: its original)
    CF_OTHER = 32,      // Lua: in the tables but not ground, swapped in the ground layer too
    CF_LEAVE = 64,      // Lua: never swapped (Detailed Weather's own, water, a tree piece)
    CF_NO_COPY = 128,   // Lua: can't be copied
};
static const uint8_t CF_ANSWERED = CF_COPY_FOR | CF_SCREEN | CF_TABLE | CF_LEAVE | CF_NO_COPY;
enum : uint8_t { CW_UNDER = 1, CW_PLAIN = 2, CW_TREE = 4, CW_WET = 8, CW_CANOPY = 16,   // ColQuestion.where
                 CW_RAMP = 32, CW_RGRASS = 64, CW_RSOIL = 128 };   // (RAMPS IN THE LOOK: a ramp; grass, else dirt, else stone)
static const uint8_t CW_RAMP_BITS = CW_RAMP | CW_RGRASS | CW_RSOIL;
static const int COL_RAMP_DEPTH = 9;     // RAMPS IN THE LOOK: levels ramps are swapped on, the view's and 8 below (frost.lua: MOST_DEPTH)
enum : int { L_BG = 0, L_BG2 = 1, L_SPATTER = 2, L_BUILDING_ONE = 3 };     // in SCREEN_LAYERS' order
static const int HOLD_FRAMES = 3;

static int32_t g_link[TEX_MAP];
static uint8_t g_cflag[TEX_MAP];
static void colour_leave(int32_t t) { if (t > 0 && t < TEX_MAP) g_cflag[t] = CF_LEAVE; }   // (15Z: the snow's bakes made here)
static uint8_t g_seen_period[TEX_MAP];   // the period an original was last listed in (SEEN)

// SWAY: colour.lua's trees rustle in wind, each leafy picture on a branch
// or twig tile (CW_CANOPY) shown through a loop of SWAY_PHASES frames made
// from its copy, a tile further downwind further behind in the loop, so
// waves run with the wind (colour.lua: update_sway, sway_texpos). Lua makes
// the frames and writes them here; this picks each cell's frame:
//   * g_sway_of: by original, its slot + 1 in g_sway_tex (0: none yet);
//   * g_sway_tex: a slot's frames in loop order (0: that frame is the copy
//     itself, as for wood, which stays put).
// Lua learns which originals need frames from the seen ring: an original
// shown on a canopy tile with no frames yet is listed there once, with
// SEEN_CANOPY added (g_canopy_listed). New wind or a new look makes new
// frames: Lua bumps sway_reset and both tables are emptied here first.
static const int32_t SEEN_CANOPY = 1 << 30;
static const int32_t SEEN_WOOD = 1 << 29;      // (16A, THE RUSTLE PAINTED HERE) with SEEN_CANOPY: its copy is wood, not leaves
static bool rustle_is_leaves(int32_t copy);    // (below)
static uint16_t g_sway_of[TEX_MAP];
static uint8_t  g_canopy_listed[TEX_MAP];
static int32_t  g_sway_tex[SWAY_MAX][SWAY_PHASES];

// HELD: the copy this wrote for each map tile in view, by level and layer,
// with when: the low 24 bits of the frame it was written (g_col_frame), and
// in the top byte for how many frames running it was held. An entry only
// counts when it's from the frame before, so nothing needs clearing where a
// cell empties. (24 bits: a slot left unwritten wraps round to "last frame"
// only after 16.7 million frames, about 77 hours at 60 frames a second; the
// 8 bits before 15L wrapped every 256 frames, harmless only while every
// move emptied the lot.)
//
// THE HELD SLOTS (test 15L): entries are kept by MAP TILE, not screen cell,
// so a pan or a level change keeps every held copy still in view. Before
// 15L they were by screen cell and emptied whenever the view moved (a cell
// is a different tile after a move), so nothing was held through a pan;
// in play that was nearly every wait on a freshly revealed map.
//   * a tile's slot: column (x mod dx), row (y mod dy) of an array the
//     view's size, and level z mod the levels held for that layer. Any
//     dx by dy stretch of tiles on one level fills every slot once, so no
//     two tiles in view share one;
//   * a slot from last frame belongs to this tile only if the tile was in
//     last frame's view (THE OLD VIEW, held_ready): otherwise it's another
//     tile's that shared the slot, and is not used;
//   * a change of the view's size empties everything, as before;
//   * the ground layer is held on every level ramps are swapped on
//     (COL_RAMP_DEPTH), the other layers on colour's own (COL_MOST_DEPTH).
//     Before 15L the levels of ramps alone had no hold at all.
struct Held { int32_t* tex; uint32_t* age; int32_t n; };
static const uint32_t HELD_FRAME = 0xFFFFFF;   // the frame's bits in an age; the run is the top byte
static uint32_t g_col_frame = 0;
static Held g_held[COL_RAMP_DEPTH][COL_LAYERS];
static uint8_t* g_facts = nullptr;   // FACTS, below: a byte a cell of one level of the view
static int32_t  g_facts_n = 0;
// THE OLD VIEW: the view the held entries were written for (INT32_MIN: none)
static int32_t g_held_x = INT32_MIN, g_held_y, g_held_z, g_held_dx, g_held_dy;
// Each screen cell's slot, and 1 where its tile was in last frame's view (the same for every level;
// level_old in swap_colour says whether the level itself was). Built in held_ready only when the view
// moves and on the frame after (when every cell is shown again), so a still view costs nothing; worked
// out per cell in the loop instead, the division it needs made the busiest colsim view 10 to 25%
// slower (PERF: 1.28 to 1.59 ms a frame before 15L, 1.72 to 1.78 with the division).
static int32_t* g_hslot = nullptr;
static uint8_t* g_shown = nullptr;
static int32_t  g_hslot_n = 0;
static bool     g_hslot_fresh = false;  // g_hslot and g_shown hold this view's (false: build them)
static bool     g_old_view = false;    // last frame's view was the same size: its entries can be used
static bool     g_view_moved = false;  // and it was somewhere else (counts col_held_moved)
static int32_t g_old_z = 0;
// The levels a layer is held on, and so its slots' modulus in z.
static inline int held_levels(int l) { return l == L_BG ? COL_RAMP_DEPTH : COL_MOST_DEPTH; }
static inline int32_t pos_mod(int32_t v, int32_t m) { const int32_t r = v % m; return r < 0 ? r + m : r; }

static void free_held() {
    for (int d = 0; d < COL_RAMP_DEPTH; d++)
        for (int l = 0; l < COL_LAYERS; l++) {
            free(g_held[d][l].tex); free(g_held[d][l].age);
            g_held[d][l] = Held{nullptr, nullptr, 0};
        }
    g_held_x = INT32_MIN;
    free(g_hslot); free(g_shown);
    g_hslot = nullptr; g_shown = nullptr; g_hslot_n = 0; g_hslot_fresh = false;
    free(g_facts);
    g_facts = nullptr;
    g_facts_n = 0;
}
// The held arrays for this view (THE HELD SLOTS): emptied only when the
// view's size changes. Works out this frame's slots and which of them were
// in last frame's view, then makes this view the old one for next frame.
static bool held_ready(int32_t dx, int32_t dy) {
    const int32_t n = dx * dy;
    const bool resized = g_held_dx != dx || g_held_dy != dy || g_held_x == INT32_MIN;
    for (int d = 0; d < COL_RAMP_DEPTH; d++)
        for (int l = 0; l < COL_LAYERS; l++) {
            if (d >= held_levels(l)) continue;   // (the other layers: colour's own levels only)
            Held& h = g_held[d][l];
            if (h.n < n) {
                free(h.tex); free(h.age);
                h.tex = (int32_t*)malloc((size_t)n * 4);
                h.age = (uint32_t*)malloc((size_t)n * 4);
                if (!h.tex || !h.age) {
                    free(h.tex); free(h.age); h = Held{nullptr, nullptr, 0};
                    g_held_x = INT32_MIN;   // (nothing kept can be trusted next frame)
                    return false;
                }
                h.n = n;
                memset(h.tex, 0, (size_t)n * 4);
                memset(h.age, 0, (size_t)n * 4);
            } else if (resized) {
                memset(h.tex, 0, (size_t)n * 4);
                memset(h.age, 0, (size_t)n * 4);
            }
        }
    // ---- THIS FRAME'S SLOTS, and which tiles were in THE OLD VIEW ----
    const bool was_moved = g_view_moved;
    g_old_view = !resized;
    const bool xy_moved = g_held_x != B.drawn_x || g_held_y != B.drawn_y;
    g_view_moved = g_old_view && (xy_moved || g_held_z != B.drawn_z);
    g_old_z = g_held_z;
    if (g_hslot_n < n) {
        free(g_hslot); free(g_shown);
        g_hslot = (int32_t*)malloc((size_t)n * 4);
        g_shown = (uint8_t*)malloc((size_t)n);
        if (!g_hslot || !g_shown) {
            free(g_hslot); free(g_shown); g_hslot = nullptr; g_shown = nullptr; g_hslot_n = 0;
            g_held_x = INT32_MIN;
            return false;
        }
        g_hslot_n = n;
        g_hslot_fresh = false;
    }
    // (a level change alone keeps every slot and shown cell: the columns and rows are the same tiles)
    if (resized || xy_moved || was_moved || !g_hslot_fresh) {
        // each row's slot and whether it was in the old view, once (a modulo per cell instead cost
        // 28 to 127 us a panning frame on views of 160 x 90 to 320 x 180)
        static int32_t row_slot[MOST_DIM];
        static uint8_t row_old[MOST_DIM];
        for (int32_t sy = 0; sy < dy; sy++) {
            const int32_t y = B.drawn_y + sy;
            row_slot[sy] = pos_mod(y, dy);
            row_old[sy] = (uint8_t)(g_old_view && y >= g_held_y && y < g_held_y + dy);
        }
        for (int32_t sx = 0; sx < dx; sx++) {
            const int32_t x = B.drawn_x + sx;
            const int32_t base = pos_mod(x, dx) * dy;
            const uint8_t col_old = (uint8_t)(g_old_view && x >= g_held_x && x < g_held_x + dx);
            int32_t* const slot = g_hslot + (size_t)sx * dy;
            uint8_t* const shown = g_shown + (size_t)sx * dy;
            for (int32_t sy = 0; sy < dy; sy++) {
                slot[sy] = base + row_slot[sy];
                shown[sy] = col_old & row_old[sy];
            }
        }
        g_hslot_fresh = true;
    }
    g_held_x = B.drawn_x; g_held_y = B.drawn_y; g_held_z = B.drawn_z; g_held_dx = dx; g_held_dy = dy;
    return true;
}

// Whether eight cells in a row hold nothing or the game's black (written
// so the compiler can test them all at once).
static inline bool empty8(const int32_t* p, int32_t black) {
    int32_t any = 0;
    for (int k = 0; k < 8; k++) any |= (p[k] != 0) & (p[k] != black);
    return !any;
}

static size_t held_bytes() {
    size_t bytes = 0;
    for (int d = 0; d < COL_RAMP_DEPTH; d++)
        for (int l = 0; l < COL_LAYERS; l++) bytes += (size_t)g_held[d][l].n * 8;
    return bytes + (size_t)g_facts_n + (size_t)g_hslot_n * 5;
}

// A question about a texture: false if the ring is full (asked again next frame).
static bool ask_colour(int32_t t, uint8_t where, int layer, int depth) {
    const uint32_t head = B.col_req_head;
    if (head - B.col_req_tail >= (uint32_t)COL_RING) { B.col_ring_full++; return false; }
    ColQuestion& q = B.col_req[head % COL_RING];
    q.texpos = t; q.where = where; q.layer = (uint8_t)layer; q.depth = (uint8_t)depth; q.pad = 0;
    B.col_req_head = head + 1;   // (the hook and Lua take turns, never at once: THE FRAME)
    B.col_asked++;
    return true;
}

// FACTS: what colour asks of the map, a byte a screen cell (CW_* bits:
// underground, a tree tile, water), worked out for a whole level of the
// view at once, a block's 16 tiles of a column at a time. Asked of the map
// tile by tile instead, for every cell of seven layers, it cost 1.7 ms a
// frame on a full view (check/colsim.cpp, PERF).
static bool level_facts(int32_t dx, int32_t dy, int32_t z) {
    const int32_t n = dx * dy;
    if (g_facts_n < n) {
        free(g_facts);
        g_facts = (uint8_t*)malloc((size_t)n);
        g_facts_n = g_facts ? n : 0;
        if (!g_facts) return false;
    }
    const uint32_t under_mask = B.subterranean_mask, wet_mask = B.flow_mask;
    for (int32_t sx = 0; sx < dx; sx++) {
        const int32_t x = B.drawn_x + sx;
        uint8_t* out = g_facts + (size_t)sx * dy;
        const bool col_on_map = x >= 0 && x < g_map.x_end && z >= 0 && z < g_map.zn;
        int32_t sy = 0;
        while (sy < dy) {
            const int32_t y = B.drawn_y + sy;
            // the rest of this block's column: up to the next multiple of 16 in y
            const int32_t run = (y >= 0) ? 16 - (y & 15) : 1;
            const int32_t end = sy + run < dy ? sy + run : dy;
            const uint8_t* blk = (col_on_map && y >= 0 && y < g_map.y_end) ? block_ptr(x >> 4, y >> 4, z) : nullptr;
            if (!blk) { memset(out + sy, 0, (size_t)(end - sy)); sy = end; continue; }
            const uint16_t* types = (const uint16_t*)(blk + B.off_tiletype) + ((x & 15) << 4);
            const uint32_t* des = (const uint32_t*)(blk + B.off_designation) + ((x & 15) << 4);
            for (; sy < end; sy++) {
                const int ly = (B.drawn_y + sy) & 15;
                const uint32_t d = des[ly];
                const uint16_t tt = types[ly];
                const uint8_t tf = flags_of(tt);
                out[sy] = (uint8_t)(((d & under_mask) ? CW_UNDER : 0) | ((d & wet_mask) ? CW_WET : 0) |
                                    ((tf & TT_TREE) ? CW_TREE : 0) |
                                    ((tt < TT_TABLE && B.col_tt[tt]) ? CW_CANOPY : 0) |
                                    // (RAMPS IN THE LOOK: a ramp and its class)
                                    ((tf & TT_RAMP) ? (CW_RAMP | ((tf & TT_GRASS_ANY) ? CW_RGRASS : (tf & TT_SOIL) ? CW_RSOIL : 0)) : 0));
            }
        }
    }
    return true;
}

// RAMPS IN THE LOOK: one tile's facts on a level of ramps alone: CW_RAMP and
// its class if it's a ramp above ground, else 0 (left as it is).
static uint8_t ramp_facts(int32_t x, int32_t y, int32_t z) {
    if (x < 0 || y < 0 || z < 0 || x >= g_map.x_end || y >= g_map.y_end || z >= g_map.zn) return 0;
    const uint8_t* blk = block_ptr(x >> 4, y >> 4, z);
    if (!blk) return 0;
    const int k = tile_of(x, y);
    const uint8_t tf = flags_of(((const uint16_t*)(blk + B.off_tiletype))[k]);
    if (!(tf & TT_RAMP) || (((const uint32_t*)(blk + B.off_designation))[k] & B.subterranean_mask)) return 0;
    return (uint8_t)(CW_RAMP | ((tf & TT_GRASS_ANY) ? CW_RGRASS : (tf & TT_SOIL) ? CW_RSOIL : 0));
}

// PICTURES CHECKED HERE (test 15K): the game reuses a texture number for a new picture (a tree's,
// a workshop's), so each original shown through its copy is checked once a period (SEEN). colour.lua
// did every check (16 sampled pixels through DFHack, about 70 a frame: 1.3 ms). Now, once colour.lua
// has found an original still showing its copy's picture, it lists it (col_verified) and the DLL
// keeps a fingerprint of that texture's pixels as they are then: the same 16 pixels, read straight
// from its surface. Each later check is made here; only a texture whose pixels have changed since
// is listed for colour.lua as before (and its fingerprint dropped), which then decides as it did.
// Whatever changed the pixels (the game's new picture, or a repaint of a tree picture for a new
// look), colour.lua sees it. Forgotten with THE COLOUR's tables.
struct PicPrint { int32_t t; uint32_t h; };   // t 0: empty, -1: removed
static const int PIC_SLOTS = 32768;           // (a power of 2; 256 KB)
static PicPrint g_pic[PIC_SLOTS];
static int32_t g_pic_used = 0;                // slots taken, removed ones included (all forgotten at 3/4)
static int32_t g_pic_kept = 0;
static const int PIC_TILE = 32;

// The 16 sampled pixels of texture t's surface, as colour.lua's sample_hash adds them up (a fully
// clear pixel adds no colour). False if t has no 32 x 32 surface.
static bool pic_print(int32_t t, uint32_t& out) {
    if (!B.col_raws || t <= 0) return false;
    const uint8_t* vec = (const uint8_t*)(uintptr_t)B.col_raws;
    void* const* first = *(void* const* const*)vec;
    void* const* last = *(void* const* const*)(vec + 8);
    if (!first || last < first || (size_t)t >= (size_t)(last - first)) return false;
    const uint8_t* surface = (const uint8_t*)first[t];
    if (!surface) return false;
    const int32_t w = *(const int32_t*)(surface + 16), h = *(const int32_t*)(surface + 20);
    const int32_t pitch = *(const int32_t*)(surface + 24);
    const uint32_t* px = *(const uint32_t* const*)(surface + 32);
    if (w != PIC_TILE || h != PIC_TILE || pitch <= 0 || pitch % 4 || !px) return false;
    const int32_t row = pitch / 4;
    uint32_t hash = 0;
    for (int k = 0; k < 16; k++) {
        const int n = (k * 389) % (PIC_TILE * PIC_TILE);
        const uint32_t v = px[(n / PIC_TILE) * row + n % PIC_TILE];
        hash = (v >> 24) ? hash * 31u + v : hash * 31u;
    }
    out = hash;
    return true;
}
static PicPrint* pic_find(int32_t t) {
    uint32_t h = ((uint32_t)t * 2654435761u) & (PIC_SLOTS - 1);
    for (int k = 0; k < 64; k++) {
        PicPrint& e = g_pic[(h + k) & (PIC_SLOTS - 1)];
        if (e.t == t) return &e;
        if (e.t == 0) return nullptr;
    }
    return nullptr;
}
static void pic_keep(int32_t t) {
    uint32_t print;
    if (!pic_print(t, print)) return;
    PicPrint* e = pic_find(t);
    if (e) { e->h = print; return; }
    if (g_pic_used >= PIC_SLOTS * 3 / 4) { memset(g_pic, 0, sizeof g_pic); g_pic_used = g_pic_kept = 0; }
    uint32_t h = ((uint32_t)t * 2654435761u) & (PIC_SLOTS - 1);
    for (int k = 0; k < 64; k++) {
        PicPrint& s = g_pic[(h + k) & (PIC_SLOTS - 1)];
        if (s.t == 0 || s.t == -1) {
            if (s.t == 0) g_pic_used++;
            s.t = t; s.h = print; g_pic_kept++;
            return;
        }
    }
}
// True if t's picture is checked here and unchanged; a changed one's fingerprint is dropped.
static bool pic_same(int32_t t) {
    PicPrint* e = pic_find(t);
    if (!e) return false;
    uint32_t print;
    B.col_pics_checked++;
    if (pic_print(t, print) && print == e->h) return true;
    e->t = -1; g_pic_kept--;
    B.col_pics_changed++;
    return false;
}

// ---- BY PICTURE (15Z) ----
// The game hands freed numbers to the pictures it builds as it draws (trees, shrubs, buildings), so the
// same picture comes back under a new number as the view moves. colour.lua gives such a number the copy
// already made for its picture (make_screen_copy: COPIES BY PICTURE), but only once asked, a frame
// later, and a tile new to the view has no HELD copy to show meanwhile: it showed the game's colours
// (15Y's report: 20,581 cells summed). Each screen copy painted here is filed by its original's picture
// (all 1024 pixels), and a texture not answered yet whose picture is filed with a copy that's still the
// look shown's gets that copy in the same frame. Its question still goes to Lua, which answers with the
// same copy. Filed in two halves: when the newer is 3/4 full it becomes the older, and a copy found in
// the older is filed again in the newer.
static uint64_t crack_hash_pixels(const uint32_t* px);   // (CRACKS IN PLACE, below)
struct ByPic { uint64_t pic; int32_t copy; int32_t pad; };
static const int BYPIC_SLOTS = 16384;   // each half (a power of 2; 256 KB)
static ByPic g_bypic_a[BYPIC_SLOTS], g_bypic_b[BYPIC_SLOTS];
static ByPic* g_bypic_new = g_bypic_a;  // filed into
static ByPic* g_bypic_old = g_bypic_b;  // the half before, looked in too
static int g_bypic_used = 0;
static bool g_bypic_any = false;        // (nothing filed: no picture worked out)
static void bypic_file(uint64_t pic, int32_t copy) {
    if (!pic || copy <= 0) return;
    if (g_bypic_used >= BYPIC_SLOTS * 3 / 4) {
        ByPic* t = g_bypic_old; g_bypic_old = g_bypic_new; g_bypic_new = t;
        memset(g_bypic_new, 0, sizeof(ByPic) * BYPIC_SLOTS);
        g_bypic_used = 0;
        B.col_pics_halved++;
    }
    uint32_t h = (uint32_t)(pic >> 40) & (BYPIC_SLOTS - 1);
    for (int k = 0; k < 64; k++, h = (h + 1) & (BYPIC_SLOTS - 1)) {
        ByPic& e = g_bypic_new[h];
        if (e.pic == pic && e.copy == copy) return;   // (filed already)
        if (!e.pic) { e.pic = pic; e.copy = copy; g_bypic_used++; B.col_pics_filed++; g_bypic_any = true; return; }
    }
}
// Whether copy c is the look shown's copy of some original (colour.lua: native_publish, both ways).
static inline bool bypic_shown(int32_t c) {
    if (c <= 0 || c >= TEX_MAP || !(g_cflag[c] & CF_SCREEN)) return false;
    const int32_t o = g_link[c];
    return o > 0 && o < TEX_MAP && (g_cflag[o] & CF_COPY_FOR) && g_link[o] == c;
}
static int32_t bypic_in(const ByPic* tab, uint64_t pic) {
    uint32_t h = (uint32_t)(pic >> 40) & (BYPIC_SLOTS - 1);
    for (int k = 0; k < 64; k++, h = (h + 1) & (BYPIC_SLOTS - 1)) {
        const ByPic& e = tab[h];
        if (!e.pic) return 0;
        if (e.pic == pic && bypic_shown(e.copy)) return e.copy;
    }
    return 0;
}
// The look shown's copy of picture `pic`, or 0.
static int32_t bypic_find(uint64_t pic) {
    if (!pic) return 0;
    int32_t c = bypic_in(g_bypic_new, pic);
    if (c) return c;
    c = bypic_in(g_bypic_old, pic);
    if (c) bypic_file(pic, c);
    return c;
}
// Texture t's picture (0: unreadable), worked out once a frame per number (a clash just works it out again).
struct PicNow { int32_t t; uint32_t frame; uint64_t pic; };
static const int PICNOW_SLOTS = 4096;   // (a power of 2)
static PicNow g_picnow[PICNOW_SLOTS];
static uint64_t pic_now(int32_t t) {
    const uint32_t frame = (uint32_t)B.tidy_calls;
    PicNow& e = g_picnow[((uint32_t)t * 2654435761u) & (PICNOW_SLOTS - 1)];
    if (e.t == t && e.frame == frame) return e.pic;
    uint32_t scratch[1024];
    const uint32_t* px = crack_pixels(t, scratch);
    e.t = t; e.frame = frame; e.pic = px ? crack_hash_pixels(px) : 0;
    return e.pic;
}

static void swap_colour() {
    if (!B.col_enabled || B.col_reset != B.col_reset_done || !B.col_depths) return;
    // PICTURES CHECKED HERE: those colour.lua found unchanged, fingerprinted as they are now
    while (B.col_verified_tail != B.col_verified_head) {
        pic_keep(B.col_verified[B.col_verified_tail % COL_RING]);
        B.col_verified_tail++;
    }
    B.col_pics_kept = (uint32_t)g_pic_kept;
    if (!B.main_viewport || !B.block_index || !B.x_count_block || !B.y_count_block || !B.z_count_block ||
        !B.off_dim_x || !B.off_dim_y || !B.off_tiletype || !B.off_designation || !B.have_drawn) return;
    const double t0 = ticks_now();
    // ---- THE MAP (as plan_snow reads it; the snow can be off) ----
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;

    const uint32_t offs[COL_LAYERS] = {B.off_background, B.off_bg2, B.off_spatter, B.off_building_one,
                                       B.off_building_two, B.off_item, B.off_vehicle};
    const int depths = (int)(B.col_depths < (uint32_t)COL_MOST_DEPTH ? B.col_depths : COL_MOST_DEPTH);
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t mdx = *(const int32_t*)(main + B.off_dim_x), mdy = *(const int32_t*)(main + B.off_dim_y);
    if (mdx <= 0 || mdy <= 0 || mdx > MOST_DIM || mdy > MOST_DIM) return;
    const bool hold = held_ready(mdx, mdy);
    const uint8_t period = (uint8_t)B.col_period;
    const int32_t black = B.black_texpos;
    const uint32_t last_frame = g_col_frame & HELD_FRAME;   // (HELD: entries written last frame carry this)
    g_col_frame++;
    const uint32_t this_frame = g_col_frame & HELD_FRAME;
    // SWAY: the loop's frame now (-1: still) and the wind's direction, as Lua gave them this frame
    const int32_t playing = (B.sway_reset == B.sway_reset_done && B.sway_playing < SWAY_PHASES) ? B.sway_playing : -1;
    const double ux = B.sway_ux, uy = B.sway_uy, waves = (double)B.sway_waves;
    uint32_t cells = 0, swapped = 0, put_back = 0, held = 0, waiting = 0, sway = 0;
    uint32_t wait_new = 0, wait_nohold = 0, held_moved = 0;   // (THE HELD SLOTS: the waits and holds split)
    uint32_t by_picture = 0;   // (BY PICTURE)

    // (RAMPS IN THE LOOK: past the levels colour looks at, on to COL_RAMP_DEPTH for ramps alone)
    for (int d = 0; d < COL_RAMP_DEPTH; d++) {
        const bool ramps_only = d >= depths;
        uint8_t* vp = viewport_in(d);
        if (!vp) break;
        if (d > 0 && !(*(const uint32_t*)(vp + B.off_flag) & 1)) break;   // a level below DF isn't showing
        const int32_t dx = *(const int32_t*)(vp + B.off_dim_x), dy = *(const int32_t*)(vp + B.off_dim_y);
        if (dx != mdx || dy != mdy) break;   // (the levels below line up with the main one)
        const int32_t z = B.drawn_z - d;
        // (RAMPS IN THE LOOK: a level of ramps alone has no facts worked out for the whole view: a
        // level below shows only through the openings above it, and its few cells with something in
        // them are looked up one by one, ramp_facts)
        if (!ramps_only && !level_facts(dx, dy, z)) break;
        for (int l = 0; l < COL_LAYERS; l++) {
            if (!offs[l]) continue;
            if (ramps_only && l != L_BG) continue;
            int32_t* buf = *(int32_t* const*)(vp + offs[l]);
            if (!buf) continue;
            // (locals throughout: a write through buf or g_cflag could otherwise make the compiler
            // read the block's fields again every cell)
            // HELD (THE HELD SLOTS): this level's slot arrays, and whether last frame's view showed it
            const int levels = held_levels(l);
            const bool held_here = hold && d < levels;
            const int hz = held_here ? (int)pos_mod(z, levels) : 0;
            int32_t* const ht = held_here ? g_held[hz][l].tex : nullptr;   // HELD: last frame's copies
            uint32_t* const ha = held_here ? g_held[hz][l].age : nullptr;
            const bool level_old = g_old_view && g_old_z - z >= 0 && g_old_z - z < levels;
            const int32_t* const hslot = g_hslot;   // (locals, as above)
            const uint8_t* const hshown = g_shown;
            const int32_t n = dx * dy;
            const uint8_t* const facts_of = g_facts;
            for (int32_t i = 0; i < n; i++) {
                // EMPTY STRETCHES: most cells of most layers hold nothing (0) or the game's black,
                // passed over eight at a time
                if ((i & 7) == 0 && i + 8 <= n && empty8(buf + i, black)) { i += 7; continue; }
                const int32_t t = buf[i];
                if (t <= 0 || t >= TEX_MAP || t == black) continue;   // (nothing, or the game's black)
                // (RAMPS IN THE LOOK: a ramp's class only in the ground layer, where the ramp is; the
                // levels past colour's own, ramps alone)
                const uint8_t facts = ramps_only ? ramp_facts(B.drawn_x + i / dy, B.drawn_y + i % dy, z)
                                    : (l == L_BG) ? facts_of[i] : (uint8_t)(facts_of[i] & ~CW_RAMP_BITS);
                if (ramps_only && !(facts & CW_RAMP)) continue;
                cells++;
                const uint8_t f = g_cflag[t];
                if (f & CF_TABLE) {
                    // a copy DF draws through the tables: only put back, underground
                    if ((facts & CW_UNDER) && (l == L_BG || l == L_BG2 || (l == L_BUILDING_ONE && (facts & CW_WET)))) {
                        buf[i] = g_link[t];
                        put_back++;
                    }
                    continue;
                }
                int32_t write = t;   // what the cell gets (t: left as it is)
                int32_t keep = 0;    // what HELD remembers for next frame (a copy written)
                uint32_t held_now = 0;   // HELD: the run, in the top byte, if held this frame
                if (f & CF_LEAVE) {
                    // (Detailed Weather's own, water, a tree piece: never swapped)
                } else {
                    // the original this cell shows (a copy, of any look, counts as its original)
                    const int32_t orig = (f & CF_SCREEN) ? g_link[t] : t;
                    const uint8_t fo = (orig == t) ? f : ((orig > 0 && orig < TEX_MAP) ? g_cflag[orig] : 0);
                    const bool under = facts & CW_UNDER;
                    const bool plain = l == L_BG && !(fo & CF_OTHER) && !(facts & (CW_TREE | CW_RAMP));
                    if (under || plain) {
                        if (orig != t) write = orig;   // no copy here: the game's own
                        else if (!(f & (CF_ANSWERED | CF_ASKED_ELSE))) {
                            const uint8_t where = facts | (plain ? CW_PLAIN : 0);
                            if (ask_colour(t, where, l, d)) g_cflag[t] = f | CF_ASKED_ELSE;
                        }
                    } else if (fo & CF_COPY_FOR) {
                        write = g_link[orig];
                        // SWAY: on a branch or twig, the frame of the loop this tile is at
                        if (facts & CW_CANOPY) {
                            const uint16_t slot = g_sway_of[orig];
                            if (slot && slot <= SWAY_MAX) {
                                if (playing >= 0) {
                                    const double mx = (double)(B.drawn_x + i / dy), my = (double)(B.drawn_y + i % dy);
                                    const int32_t start = (int32_t)floor((mx * ux + my * uy) * waves);
                                    int32_t phase = (playing - start) % SWAY_PHASES;
                                    if (phase < 0) phase += SWAY_PHASES;
                                    const int32_t frame = g_sway_tex[slot - 1][phase];
                                    if (frame > 0) { write = frame; sway++; }
                                }
                            } else if (!g_canopy_listed[orig]) {
                                // no frames yet: listed for Lua to make them (16A: and whether its copy, the
                                // look shown's, is wood, which never rustles: SEEN_WOOD)
                                const uint32_t sh = B.col_seen_head;
                                if (sh - B.col_seen_tail < (uint32_t)COL_RING) {
                                    const bool wood = !rustle_is_leaves(write);
                                    if (wood) B.canopy_wood++;
                                    B.col_seen[sh % COL_RING] = orig | SEEN_CANOPY | (wood ? SEEN_WOOD : 0);
                                    B.col_seen_head = sh + 1;
                                    g_canopy_listed[orig] = 1;
                                } else B.col_seen_full++;
                            }
                        }
                        keep = write;
                        // SEEN: listed once a period for Lua to check its picture (PICTURES CHECKED
                        // HERE: unless checked here and unchanged)
                        if (g_seen_period[orig] != period && pic_same(orig)) g_seen_period[orig] = period;
                        if (g_seen_period[orig] != period) {
                            const uint32_t sh = B.col_seen_head;
                            if (sh - B.col_seen_tail < (uint32_t)COL_RING) {
                                B.col_seen[sh % COL_RING] = orig;
                                B.col_seen_head = sh + 1;
                                g_seen_period[orig] = period;
                            } else B.col_seen_full++;
                        }
                    } else if (orig != t) {
                        write = orig;   // a copy whose original has none in this look
                    } else if (!(fo & CF_ANSWERED)) {
                        // never heard of where it could be swapped: asked, and HELD meanwhile
                        if (!(f & CF_ASKED)) {
                            if (ask_colour(t, facts, l, d)) g_cflag[t] = f | CF_ASKED;
                        }
                        // (THE HELD SLOTS: this tile's slot, used only if the tile was in last frame's view)
                        const bool shown = ht && level_old && hshown[i];
                        const int32_t j = ht ? hslot[i] : 0;
                        const uint32_t a = shown ? ha[j] : 0;
                        if (shown && ht[j] && (a & HELD_FRAME) == last_frame && (a >> 24) < (uint32_t)HOLD_FRAMES) {
                            write = ht[j];
                            keep = write;
                            held_now = ((a >> 24) + 1) << 24;
                            held++;
                            if (g_view_moved) held_moved++;
                        } else {
                            // (BY PICTURE, 15Z) else the look shown's copy of its picture, if one was painted here
                            const int32_t byp = g_bypic_any ? bypic_find(pic_now(t)) : 0;
                            if (byp) {
                                write = byp;
                                keep = write;
                                by_picture++;
                            } else {
                                waiting++;
                                if (shown) wait_nohold++; else wait_new++;
                            }
                        }
                    }
                }
                if (write != t) {
                    buf[i] = write;
                    if (keep) swapped++; else put_back++;
                }
                if (ht && keep) {
                    const int32_t j = hslot[i];   // (THE HELD SLOTS)
                    ht[j] = keep;
                    ha[j] = held_now | this_frame;
                }
            }
        }
    }
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.col_frames++;
    B.col_swapped += swapped;
    B.col_put_back += put_back;
    B.sway_swapped += sway;
    B.col_held += held;
    B.col_waiting += waiting;
    B.col_wait_new += wait_new;
    B.col_wait_nohold += wait_nohold;
    B.col_held_moved += held_moved;
    B.col_by_picture += by_picture;
    B.col_cells_last = cells;
    B.col_swapped_last = swapped;
    B.col_us_total += us;
    if (us > B.col_us_max) B.col_us_max = us;
    if ((B.col_frames & 255) == 1) B.memory_kb = memory_kb();
}

// =====================================================================
// THE SHADE (test 6): shade.lua's shade (main thread, in the hook)
// =====================================================================
// WHAT: the ground under a roof or a tree's branches drawn darker, as in
// shade: a see-through dark tile in the designation layer (which draws
// over everything on the map), with a soft edge a tile wide. shade.lua
// worked it out in Lua when the view moved, reading the map blocks and
// making each shade tile the first time it was needed; here it's worked
// out every frame from the map, on the view's own level, with the rules
// of shade.lua's make_plan:
//   * a tile is covered when it's neither outside (open to the sky) nor
//     underground; covered tiles are fully dark;
//   * a screen tile touching a covered tile (or one itself) gets the shade
//     tile for the darkness at its four corners, each the mean of the four
//     tiles meeting there: 0, 1, 2, 3 or 4 of them covered, so 5^4 = 625
//     tiles, all made by shade.lua at start (native_tables), so none is
//     ever made on first sight;
//   * tiles with water or magma are left out (the game draws the layer
//     oddly over liquid), and so is a cell where the game shows a mark of
//     its own (anything already in the designation layer).
// Like shade.lua, nothing is put back: the game redraws the layer itself.
static uint8_t* g_dark = nullptr;     // 1 for a covered tile, the view and a tile round it
static int32_t  g_dark_n = 0;

static void draw_shade() {
    if (!B.shade_enabled || !B.off_designation_layer || !B.have_drawn) return;
    if (!B.main_viewport || !B.block_index || !B.x_count_block || !B.y_count_block || !B.z_count_block ||
        !B.off_dim_x || !B.off_dim_y || !B.off_designation) return;
    const double t0 = ticks_now();
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    uint8_t* vp = viewport_in(0);
    if (!vp) return;
    const int32_t dx = *(const int32_t*)(vp + B.off_dim_x), dy = *(const int32_t*)(vp + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    int32_t* buf = *(int32_t* const*)(vp + B.off_designation_layer);
    if (!buf) return;
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;

    // ---- WHICH TILES ARE COVERED: the view and one tile round it (W x H, from x0, y0) ----
    const int32_t x0 = B.drawn_x - 1, y0 = B.drawn_y - 1, W = dx + 2, H = dy + 2;
    if (g_dark_n < W * H) {
        free(g_dark);
        g_dark = (uint8_t*)malloc((size_t)W * H);
        g_dark_n = g_dark ? W * H : 0;
        if (!g_dark) return;
    }
    const uint32_t open = B.outside_mask | B.subterranean_mask | B.hidden_mask, wet = B.flow_mask;
    const uint8_t* const wl_tt = B.wl_tt;
    bool any = false;
    for (int32_t gx = 0; gx < W; gx++) {
        const int32_t x = x0 + gx;
        uint8_t* col = g_dark + (size_t)gx * H;
        if (x < 0 || x >= g_map.x_end) { memset(col, 0, (size_t)H); continue; }
        int32_t gy = 0;
        while (gy < H) {
            const int32_t y = y0 + gy;
            const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
            const int32_t end = gy + run < H ? gy + run : H;
            const uint8_t* blk = (y >= 0 && y < g_map.y_end) ? block_ptr(x >> 4, y >> 4, z) : nullptr;
            if (!blk) { memset(col + gy, 0, (size_t)(end - gy)); gy = end; continue; }
            const uint32_t* des = (const uint32_t*)(blk + B.off_designation) + ((x & 15) << 4);
            const uint16_t* types = B.off_tiletype ? (const uint16_t*)(blk + B.off_tiletype) + ((x & 15) << 4) : nullptr;
            for (; gy < end; gy++) {
                const int ly = (y0 + gy) & 15;
                const uint32_t d = des[ly];
                // 1 covered (not outside, subterranean, hidden, or frozen ice wall / brook bed: WL_NO_FOG = 8);
                // 2 liquid (kept apart: only the cell itself is left out for it)
                const bool no_shade = types && types[ly] < TT_TABLE && (wl_tt[types[ly]] & 8) != 0;
                const uint8_t c = ((d & open) == 0 && !no_shade) ? 1 : 0;
                col[gy] = (uint8_t)(c | ((d & wet) ? 2 : 0));
                any = any || c;
            }
        }
    }
    uint32_t shaded = 0;
    if (any) {
        // ---- EACH SCREEN TILE: its corners' darkness, its shade tile ----
        // corner (gx, gy) is the top left of grid tile (gx, gy): the covered count of the
        // tiles (gx-1, gy-1), (gx, gy-1), (gx-1, gy), (gx, gy)
        auto dark = [&](int32_t gx, int32_t gy) -> int { return g_dark[(size_t)gx * H + gy] & 1; };
        auto corner = [&](int32_t gx, int32_t gy) -> int {
            return dark(gx - 1, gy - 1) + dark(gx, gy - 1) + dark(gx - 1, gy) + dark(gx, gy);
        };
        for (int32_t sx = 0; sx < dx; sx++) {
            const int32_t gx = sx + 1;
            for (int32_t sy = 0; sy < dy; sy++) {
                const int32_t gy = sy + 1;
                if (g_dark[(size_t)gx * H + gy] & 2) continue;   // water or magma here
                const int tl = corner(gx, gy), tr = corner(gx + 1, gy), bl = corner(gx, gy + 1), br = corner(gx + 1, gy + 1);
                const int k = ((tl * 5 + tr) * 5 + bl) * 5 + br;
                if (!k) continue;
                const int32_t i = sx * dy + sy;
                const int32_t tex = B.shade_tex[k];
                if (tex > 0 && buf[i] == 0) { buf[i] = tex; shaded++; }
            }
        }
    }
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.shade_frames++;
    B.shade_written += shaded;
    B.shade_cells_last = shaded;
    B.shade_us_total += us;
    if (us > B.shade_us_max) B.shade_us_max = us;
}

// =====================================================================
// PAINTING (test 7): colour's per-tile copies painted here (main thread)
// =====================================================================
// WHAT: colour.lua's copy of a picture (a trunk, a branch, a workshop, an
// item) is the picture recoloured for the look, pixel by pixel (looks.lua:
// colour_only, with recolourer's colour change). Lua took about 0.5 ms a
// copy, most of it reading the pixels into Lua tables, so on the first
// view after loading hundreds of new pictures waited frames for theirs
// and showed the game's colours meanwhile (the trees drawing in).
// HOW: Lua keeps a pool of blank textures made ahead (createTile, which
// only Lua can call). For a new picture it takes one, makes it the copy
// in its own books at once, and asks for it to be painted here: a job
// with both pixel addresses and the look's colour change. The jobs are
// painted at the start of the hook, before the swaps, so the copy shows
// in the frame it was asked for.
// WHY A BLANK, NEVER-SHOWN TEXTURE: the renderer keeps its own copy of a
// texture once it has drawn it, and reads the pixels again only on a zoom
// (grass.lua: REPAINTED PICTURES, dw-inplace-probe). A texture never drawn
// is read the first time it is, which is after this has painted it.
// THE COLOUR CHANGE, as looks.lua's recolourer, in the same order of
// operations so the result is the same to the bit: the matrix, then the
// lean's gains with the lightness kept, then the wet's darkening, then
// the lightening (towards white if positive, a scale if not), each channel
// clamped and rounded (floor of x + 0.5); the alpha kept.
static inline double lum_of(double r, double g, double b) { return r * 0.299 + g * 0.587 + b * 0.114; }
static inline uint32_t channel(double v) {
    return v < 0 ? 0u : v > 255 ? 255u : (uint32_t)floor(v + 0.5);
}

// ---------------------------------------------------------------------
// THE FULL REDRAW (test 9): looks.lua's redraw for grass, bare ground and
// ice, with its dry and wet effects (and ice's glints), as looks.lua does
// it, step for step and in the same order of operations, so the result is
// the same to the bit (check/paint/compare_full.py runs the real looks.lua
// against this). In Lua one copy with the wet effect took about 5 ms
// (frost's ramp bakes in a wet look, details 2026-11-18); here, microseconds.
// The constants are looks.lua's: change one there, change it here.
// ---------------------------------------------------------------------
enum : uint32_t { CL_GRASS = 1, CL_DIRT, CL_SAND, CL_STONE, CL_PEBBLES, CL_ICE };   // PaintJob.cls
enum : uint32_t { WX_COLD = 0, WX_MILD, WX_HOT };                                   // PaintJob.weather
static const int PN = 1024, PT = 32;

namespace looks {
// dry
static const double DRY_SHARE = 0.15, DRY_DARK = 0.65;
static const double GRASS_GAP[3] = {104, 80, 50};
static const double GRASS_GAP_STRENGTH = 0.5;
static const double SAND_CONTRAST = 0.25, SAND_GLINTS = 0.12, SAND_GRAINS = 0.12, SAND_GLINT_LIFT = 0.08, SAND_GRAIN_DARK = 0.08;
// wet
static const double OPACITY = 0.4;
struct WetKind { double glint, glint_strength, soak, sheen, rime; };
static const WetKind WET_GRASS = {0.10, 0.20, 0.13, 0.04, 0.35};
static const WetKind WET_DIRT = {0.06, 0.27, 0.30, 0.09, 0.25};
static const WetKind WET_STONE = {0.09, 0.37, 0.23, 0.11, 0.25};
static const WetKind WET_PEBBLES = {0.10, 0.33, 0.20, 0.07, 0.30};
static const WetKind WET_SAND = {0.05, 0.27, 0.23, 0.07, 0.22};
static const double GLINT[3] = {250, 250, 244}, WARM_GLINT[3] = {255, 246, 226}, SKY[3] = {150, 166, 188};
static const double RIME[3] = {234, 241, 249}, ICE_GLAZE[3] = {198, 214, 232}, WHITE[3] = {250, 252, 255};
static const double HOT_GLINTS = 1.6, HOT_SHEEN = 0.07, RIME_OPACITY = 0.35, GLAZE = 0.15;
static const double HIGHLIGHT[3] = {0.3, 0.12, 0.08};   // cold, mild, hot (SHADE is 0 for all: left out)
static const double HIGHLIGHT_SHARE = 1.0 / 8;
static const int SAND_VALLEY_ROWS = 4;
static const double SAND_VALLEY_DARK = 0.22, SAND_LINE_SHARE = 0.18;
static const double WET_CRACK[3] = {66, 46, 32}, WET_CRACK_STRENGTH = 0.55, WET_JOINT[3] = {50, 44, 39};
// ice
static const double ICE_FROST[3] = {232, 240, 250};
static const double ICE_GLINTS = 0.05, ICE_GLINT_STRENGTH = 0.55;

// The texture's see-through pixels (looks.lua: shown): any = it has some; shown[n] for those that show.
struct Shown { bool any; bool on[PN]; };

static inline double lum(double r, double g, double b) { return r * 0.299 + g * 0.587 + b * 0.114; }
static int cmp_double(const void* a, const void* b) {
    const double x = *(const double*)a, y = *(const double*)b;
    return x < y ? -1 : x > y ? 1 : 0;
}
// sorted: the pixels that show, sorted (one 0 if none); returns the count.
static int sorted(const double* f, const Shown& sh, double* s) {
    int m = 0;
    for (int n = 0; n < PN; n++) if (!sh.any || sh.on[n]) s[m++] = f[n];
    if (!m) s[m++] = 0;
    qsort(s, (size_t)m, sizeof(double), cmp_double);
    return m;
}
// filled: clear pixels at the mean of the rest (in place)
static void filled(double* l, const Shown& sh) {
    if (!sh.any) return;
    double sum = 0; int count = 0;
    for (int n = 0; n < PN; n++) if (sh.on[n]) { sum = sum + l[n]; count = count + 1; }
    const double mean = count > 0 ? sum / count : 0;
    for (int n = 0; n < PN; n++) if (!sh.on[n]) l[n] = mean;
}
// quantile: np.quantile's linear interpolation (looks.lua's, 1-based there)
static double quantile(const double* s, int m, double q) {
    const double pos = q * (m - 1) + 1;
    const double lo = floor(pos);
    if (lo >= m) return s[m - 1];
    if (lo < 1) return s[0];
    const int i = (int)lo;
    return s[i - 1] + (s[i] - s[i - 1]) * (pos - lo);
}
static inline int wrap(int v) { return ((v % PT) + PT) % PT; }
static inline double at(const double* f, int x, int y) { return f[wrap(y) * PT + wrap(x)]; }
// box: the mean over a (2r+1)^2 box, wrapping
static void box(const double* f, int r, double* out) {
    const double count = (double)((2 * r + 1) * (2 * r + 1));
    for (int y = 0; y < PT; y++)
        for (int x = 0; x < PT; x++) {
            double sum = 0;
            for (int dy = -r; dy <= r; dy++) for (int dx = -r; dx <= r; dx++) sum = sum + at(f, x + dx, y + dy);
            out[y * PT + x] = sum / count;
        }
}
// top_share: weights 0-1 for the top `share` of a field, fading in over the next bit (s, m: sorted, or null)
static void top_share(const double* f, double share, const double* s, int m, const Shown& sh, double* out) {
    if (share <= 0) { for (int n = 0; n < PN; n++) out[n] = 0; return; }
    static double own[PN];
    if (!s) { m = sorted(f, sh, own); s = own; }
    const double cut = quantile(s, m, 1 - share);
    const double soft = quantile(s, m, (1 - share * 1.6) > 0 ? 1 - share * 1.6 : 0);
    const double span = (cut - soft) > 1e-6 ? cut - soft : 1e-6;
    for (int n = 0; n < PN; n++) {
        const double v = (f[n] - soft) / span;
        out[n] = v < 0 ? 0 : v > 1 ? 1 : v;
    }
}
static void shifted(const double* f, int dx, int dy, double* out) {
    for (int y = 0; y < PT; y++) for (int x = 0; x < PT; x++) out[y * PT + x] = at(f, x + dx, y + dy);
}
static inline void blend(double* r, double* g, double* b, int n, const double* c, double k) {
    r[n] = r[n] + (c[0] - r[n]) * k;
    g[n] = g[n] + (c[1] - g[n]) * k;
    b[n] = b[n] + (c[2] - b[n]) * k;
}

// ---- dry ----
static void deepen(double* r, double* g, double* b, const Shown& sh, double share, double dark, const double* towards) {
    if (share <= 0) return;
    static double l[PN], s[PN], depth[PN];
    double before = 0; int count = 0;
    for (int n = 0; n < PN; n++) {
        l[n] = lum(r[n], g[n], b[n]);
        if (!sh.any || sh.on[n]) { before = before + l[n]; count = count + 1; }
    }
    const int m = sorted(l, sh, s);
    const double cut = quantile(s, m, share);
    double after = 0, rest_sum = 0;
    for (int n = 0; n < PN; n++) {
        double d = (cut - l[n]) / 18 + 0.5;
        d = d < 0 ? 0 : d > 1 ? 1 : d;
        if (sh.any && !sh.on[n]) d = 0;
        depth[n] = d;
        if (towards) {
            const double k = d * dark;
            r[n] = r[n] + (towards[0] - r[n]) * k;
            g[n] = g[n] + (towards[1] - g[n]) * k;
            b[n] = b[n] + (towards[2] - b[n]) * k;
        } else {
            const double f = 1 - d * (1 - dark);
            r[n] = r[n] * f; g[n] = g[n] * f; b[n] = b[n] * f;
        }
        if (!sh.any || sh.on[n]) {
            after = after + lum(r[n], g[n], b[n]);
            rest_sum = rest_sum + (1 - d);
        }
    }
    if (after <= 0 || rest_sum <= 0) return;
    const double spare = (before / after - 1) * count / rest_sum;
    for (int n = 0; n < PN; n++) {
        const double f = 1 + spare * (1 - depth[n]);
        r[n] = r[n] * f; g[n] = g[n] * f; b[n] = b[n] * f;
    }
}
static void dry_sand(double* r, double* g, double* b, const Shown& sh, double dryness, const double* grain) {
    double mean = 0; int count = 0;
    for (int n = 0; n < PN; n++) if (!sh.any || sh.on[n]) { mean = mean + lum(r[n], g[n], b[n]); count = count + 1; }
    mean = count > 0 ? mean / count : 0;
    const double contrast = 1 + SAND_CONTRAST * dryness;
    for (int n = 0; n < PN; n++) {
        const double gr = grain[n];
        const double f = gr > 1 - SAND_GLINTS * dryness ? 1 + SAND_GLINT_LIFT
                       : gr < SAND_GRAINS * dryness ? 1 - SAND_GRAIN_DARK : 1;
        r[n] = (mean + (r[n] - mean) * contrast) * f;
        g[n] = (mean + (g[n] - mean) * contrast) * f;
        b[n] = (mean + (b[n] - mean) * contrast) * f;
    }
}

// ---- wet ----
// structure: lit faces (0-1) and hollows (0-1) from the brightness
static void structure(const double* l, const Shown& sh, double* lit, double* hollow) {
    static double blurred[PN], height[PN], nw[PN], s[PN], around[PN];
    box(l, 1, blurred);
    for (int n = 0; n < PN; n++) height[n] = 0.6 * l[n] + 0.4 * blurred[n];
    shifted(height, -1, -1, nw);
    for (int n = 0; n < PN; n++) { const double v = height[n] - nw[n]; lit[n] = v > 0 ? v : 0; }
    const int m = sorted(lit, sh, s);
    const double q = quantile(s, m, 0.97);
    const double top = q > 1e-6 ? q : 1e-6;
    for (int n = 0; n < PN; n++) { const double v = lit[n] / top; lit[n] = v > 1 ? 1 : v; }
    box(l, 2, around);
    for (int n = 0; n < PN; n++) { const double v = (around[n] - l[n]) / 14; hollow[n] = v < 0 ? 0 : v > 1 ? 1 : v; }
}
static void sand_valleys(const double* l, const Shown& sh, double* valley) {
    static double lines[PN], moved[PN];
    top_share(l, SAND_LINE_SHARE, nullptr, 0, sh, lines);
    for (int n = 0; n < PN; n++) valley[n] = 0;
    for (int row = 1; row <= SAND_VALLEY_ROWS; row++) {
        shifted(lines, 0, row, moved);
        const double k = 1 - (double)(row - 1) / SAND_VALLEY_ROWS;
        for (int n = 0; n < PN; n++) { const double v = moved[n] * k; if (v > valley[n]) valley[n] = v; }
    }
    for (int n = 0; n < PN; n++) { const double v = valley[n] - lines[n]; valley[n] = v < 0 ? 0 : v; }
}
static void wet(double* r, double* g, double* b, const Shown& sh, uint32_t cls, uint32_t weather, double amount) {
    const WetKind& k = cls == CL_GRASS ? WET_GRASS : cls == CL_DIRT ? WET_DIRT : cls == CL_STONE ? WET_STONE
                     : cls == CL_PEBBLES ? WET_PEBBLES : WET_SAND;
    static double l[PN], lit[PN], hollow[PN], fr[PN], fg[PN], fb[PN], lit_sorted[PN], tmp[PN], tmp2[PN];
    static double out_r[PN], out_g[PN], out_b[PN];
    for (int n = 0; n < PN; n++) l[n] = lum(r[n], g[n], b[n]);
    filled(l, sh);
    structure(l, sh, lit, hollow);
    for (int n = 0; n < PN; n++) { fr[n] = r[n]; fg[n] = g[n]; fb[n] = b[n]; }
    if (cls == CL_SAND) {
        sand_valleys(l, sh, tmp);
        for (int n = 0; n < PN; n++) {
            const double f = 1 - tmp[n] * SAND_VALLEY_DARK * amount;
            fr[n] = fr[n] * f; fg[n] = fg[n] * f; fb[n] = fb[n] * f;
        }
    }
    const int lm = sorted(lit, sh, lit_sorted);
    if (weather == WX_COLD) {
        top_share(lit, k.rime * amount, lit_sorted, lm, sh, tmp);
        for (int n = 0; n < PN; n++) {
            blend(fr, fg, fb, n, ICE_GLAZE, hollow[n] * GLAZE * amount);
            blend(fr, fg, fb, n, RIME, tmp[n] * RIME_OPACITY);
        }
    } else {
        for (int n = 0; n < PN; n++) {
            const double f = 1 - hollow[n] * k.soak * amount;
            fr[n] = fr[n] * f; fg[n] = fg[n] * f; fb[n] = fb[n] * f;
            blend(fr, fg, fb, n, SKY, hollow[n] * k.sheen * amount);
        }
        double share = k.glint, sheen = 0;
        const double* colour = GLINT;
        if (weather == WX_HOT) { share = k.glint * HOT_GLINTS; colour = WARM_GLINT; sheen = HOT_SHEEN; }
        top_share(lit, share * amount, lit_sorted, lm, sh, tmp);
        for (int n = 0; n < PN; n++) {
            if (sheen > 0) blend(fr, fg, fb, n, colour, lit[n] * sheen * amount);
            blend(fr, fg, fb, n, colour, tmp[n] * k.glint_strength);
        }
    }
    for (int n = 0; n < PN; n++) {
        out_r[n] = r[n] + (fr[n] - r[n]) * OPACITY;
        out_g[n] = g[n] + (fg[n] - g[n]) * OPACITY;
        out_b[n] = b[n] + (fb[n] - b[n]) * OPACITY;
    }
    if (weather != WX_COLD) {
        if (cls == CL_DIRT) {
            for (int n = 0; n < PN; n++) {
                double c = ((r[n] < b[n] ? r[n] : b[n]) - g[n]) / 8;
                c = c < 0 ? 0 : c > 1 ? 1 : c;
                blend(out_r, out_g, out_b, n, WET_CRACK, c * WET_CRACK_STRENGTH * amount);
            }
        } else if (cls == CL_STONE || cls == CL_PEBBLES) {
            for (int n = 0; n < PN; n++) tmp2[n] = -l[n];
            top_share(tmp2, cls == CL_STONE ? 0.15 : 0.20, nullptr, 0, sh, tmp);
            for (int n = 0; n < PN; n++) blend(out_r, out_g, out_b, n, WET_JOINT, tmp[n] * WET_CRACK_STRENGTH * amount);
        }
    }
    top_share(lit, k.rime * amount * HIGHLIGHT_SHARE, lit_sorted, lm, sh, tmp);
    const double* colour = weather == WX_COLD ? WHITE : weather == WX_HOT ? WARM_GLINT : GLINT;
    const double kind_opacity = cls == CL_SAND ? 0.5 : 1;
    for (int n = 0; n < PN; n++) {
        blend(out_r, out_g, out_b, n, colour, tmp[n] * HIGHLIGHT[weather]);
        r[n] = r[n] + (out_r[n] - r[n]) * kind_opacity;
        g[n] = g[n] + (out_g[n] - g[n]) * kind_opacity;
        b[n] = b[n] + (out_b[n] - b[n]) * kind_opacity;
    }
}
}   // namespace looks

// One copy, the whole of looks.lua's redraw for grass, bare ground and ice
// (redraw with effects): the colour change per pixel (recolourer: the
// matrix, then the soil's and the lean's gains with the lightness kept,
// then the wet's darkening and the lightening; ice: the matrix, its frost,
// its thaw's darkening), then dry (sand's contrast and grain; grass's gaps
// towards dry earth; stone's and pebbles' darkest share deepened), then wet
// (past average), or ice's glints near thawing; each channel clamped and
// rounded, the alpha kept.
static void paint_full(const PaintJob& j, const uint32_t* src, uint32_t* dst) {
    using namespace looks;
    static double r[PN], g[PN], b[PN], grain[PN];
    static uint32_t a[PN];
    static Shown sh;
    const double* m = j.m;
    sh.any = false;
    for (int n = 0; n < PN; n++) {
        const uint32_t w = src[n];
        const double pr = (double)(w & 0xff), pg = (double)((w >> 8) & 0xff), pb = (double)((w >> 16) & 0xff);
        a[n] = w >> 24;
        double nr = m[0] * pr + m[1] * pg + m[2] * pb;
        double ng = m[3] * pr + m[4] * pg + m[5] * pb;
        double nb = m[6] * pr + m[7] * pg + m[8] * pb;
        if (j.cls == CL_ICE) {
            nr = nr + (ICE_FROST[0] - nr) * j.ice_k; ng = ng + (ICE_FROST[1] - ng) * j.ice_k; nb = nb + (ICE_FROST[2] - nb) * j.ice_k;
            nr = nr * j.ice_dark; ng = ng * j.ice_dark; nb = nb * j.ice_dark;
        } else {
            if (j.has_soil) {
                const double before = lum(nr, ng, nb);
                nr = nr * j.soil[0]; ng = ng * j.soil[1]; nb = nb * j.soil[2];
                const double after = lum(nr, ng, nb);
                const double k = after > 0 ? before / after : 1;
                nr = nr * k; ng = ng * k; nb = nb * k;
            }
            if (j.has_lean) {
                const double before = lum(nr, ng, nb);
                nr = nr * j.lean[0]; ng = ng * j.lean[1]; nb = nb * j.lean[2];
                const double after = lum(nr, ng, nb);
                const double k = after > 0 ? before / after : 1;
                nr = nr * k; ng = ng * k; nb = nb * k;
            }
            nr = nr * j.dark; ng = ng * j.dark; nb = nb * j.dark;
            if (j.lighten > 0) {
                nr = nr + (255 - nr) * j.lighten; ng = ng + (255 - ng) * j.lighten; nb = nb + (255 - nb) * j.lighten;
            } else {
                nr = nr * (1 + j.lighten); ng = ng * (1 + j.lighten); nb = nb * (1 + j.lighten);
            }
        }
        r[n] = nr; g[n] = ng; b[n] = nb;
        if (a[n] == 0) sh.any = true;
    }
    if (sh.any) for (int n = 0; n < PN; n++) sh.on[n] = a[n] > 0;
    if (j.cls == CL_ICE) {
        if (j.thaw > 0) {
            static double l[PN], lit[PN], hollow[PN], s[PN], glints[PN];
            for (int n = 0; n < PN; n++) l[n] = lum(r[n], g[n], b[n]);
            filled(l, sh);
            structure(l, sh, lit, hollow);
            const int lm = sorted(lit, sh, s);
            top_share(lit, ICE_GLINTS * j.thaw, s, lm, sh, glints);
            for (int n = 0; n < PN; n++) blend(r, g, b, n, WHITE, glints[n] * ICE_GLINT_STRENGTH);
        }
    } else {
        if (j.dryness > 0) {
            if (j.cls == CL_SAND) {
                const uint32_t* gsrc = (const uint32_t*)(uintptr_t)j.grain;
                for (int n = 0; n < PN; n++) grain[n] = gsrc ? (double)((gsrc[n] >> 16) & 0xff) / 255 : 0.5;
                dry_sand(r, g, b, sh, j.dryness, grain);
            } else if (j.cls == CL_GRASS) deepen(r, g, b, sh, DRY_SHARE * j.dryness, GRASS_GAP_STRENGTH, GRASS_GAP);
            else if (j.cls != CL_DIRT) deepen(r, g, b, sh, DRY_SHARE * j.dryness, DRY_DARK, nullptr);
        }
        if (j.wet > 0) wet(r, g, b, sh, j.cls, j.weather, j.wet);
    }
    for (int n = 0; n < PN; n++)
        dst[n] = (a[n] << 24) | (channel(b[n]) << 16) | (channel(g[n]) << 8) | channel(r[n]);
}

// =====================================================================
// DRY CRACKS (test 15O): frost.lua's cracked(), painted here
// =====================================================================
// WHAT: in a look drier than average, dirt and stone floors, and dirt and
// stone ramps, show drying cracks (frost.lua: Dry cracks). frost.lua baked
// each in Lua (2.05 to 3.50 ms a bake in play); a paint job can now ask for
// them after its redraw (PaintJob.crack_*), and they're done here on the
// job's result, bit for bit as frost.lua's cracked() (checked against it:
// check/crack/compare.py). Its rules:
//   * the ground's lightness per pixel; the colour of its own hollows (the
//     mean of its darkest tenth, 102nd of 1,024 sorted), darkened (dirt
//     CRACK_DARK * 1.3, else STONE_CRACK_DARK), for the cracks' floors;
//   * the crack at a pixel from the heat patterns (art/heat_patterns.png,
//     a 4 x 4 grid of tiles, each tile taking its piece by position so the
//     cracks join): the main network's distance (red / 16) and the fine
//     network's (green / 16), widening and deepening with the amount; on
//     pebbles only in the soil between the stones (darker than the median);
//   * a crack's far (south) wall catches the light (the crack a pixel north
//     less this one's; the top row looks into the piece north); dirt's
//     plates pale a little; then the plates (not the cracks) brighten so the
//     tile's mean lightness stays as it was;
//   * each channel rounded and clamped, the alpha kept.
enum : uint32_t { CK_NONE = 0, CK_DIRT = 1, CK_STONE = 2, CK_PEBBLES = 3 };
static const double CRACK_DARK = 0.55, CRACK_LIT = 1.3, PLATE_PALE = 0.06;   // (frost.lua's values)
static const double CRACK_THIN = 0.45, STONE_CRACK_DARK = 0.72;

static int cmp_dbl_asc(const void* a, const void* b) {
    const double x = *(const double*)a, y = *(const double*)b;
    return x < y ? -1 : x > y ? 1 : 0;
}
// Lua's math.floor(v + 0.5), clamped to a byte (frost.lua: round_byte)
static inline uint32_t round_byte(double v) {
    v = floor(v + 0.5);
    return v < 0 ? 0 : v > 255 ? 255 : (uint32_t)v;
}

// The cracks on px (1,024 words, as the paint leaves them), in place.
static void crack_in_place(uint32_t* px, uint32_t kind, double amount, const uint32_t* here, const uint32_t* north_piece) {

    static double red[PN], green[PN], blue[PN], lum[PN], sorted_l[PN], cracks[PN];
    static double out_r[PN], out_g[PN], out_b[PN];
    for (int n = 0; n < PN; n++) {
        const uint32_t w = px[n];
        red[n] = (double)(w & 0xff); green[n] = (double)((w >> 8) & 0xff); blue[n] = (double)((w >> 16) & 0xff);
        lum[n] = red[n] * 0.299 + green[n] * 0.587 + blue[n] * 0.114;
        sorted_l[n] = lum[n];
    }
    qsort(sorted_l, PN, sizeof(double), cmp_dbl_asc);
    // the colour of the ground's own hollows (its darkest tenth): Lua's sorted[floor(0.1 * 1024 + 0.5)]
    const double cut = sorted_l[(int)floor(0.1 * PN + 0.5) - 1];
    double hr = 0, hg = 0, hb = 0;
    int count = 0;
    for (int n = 0; n < PN; n++)
        if (lum[n] <= cut) { hr = hr + red[n]; hg = hg + green[n]; hb = hb + blue[n]; count++; }
    const double k = (kind == CK_DIRT ? CRACK_DARK * 1.3 : STONE_CRACK_DARK) / (double)(count > 1 ? count : 1);
    const double hollow[3] = {hr * k, hg * k, hb * k};
    const double depth = 0.2 + 0.8 * amount * amount;
    const double width = kind == CK_STONE ? 0.8 + 0.5 * amount : 1.0 + 0.9 * amount;
    const double fw = (amount - 0.5) * 2;
    const double fine_width = kind == CK_STONE ? 0 : (fw > 0 ? fw : 0) * 1.0;
    const double median = sorted_l[PN / 2 - 1];   // (Lua: sorted[#sorted // 2])
    // the crack at pixel idx of a pattern piece (Lua: crack_at; on pebbles by this texture's pixel idx)
    auto crack_at = [&](const uint32_t* pat, int idx) -> double {
        const uint32_t w = pat[idx];
        const double main_d = (double)(w & 0xff) / 16, fine_d = (double)((w >> 8) & 0xff) / 16;
        const double x1 = width - main_d, x2 = fine_width - fine_d;
        double a = ((x1 >= x2 ? x1 : x2) - CRACK_THIN) / (1 - CRACK_THIN);
        a = (a < 0 ? 0 : a > 1 ? 1 : a) * depth;
        if (kind == CK_PEBBLES && a > 0) {
            double gap = (median - lum[idx]) / 16 + 0.5;   // 1 in the soil, 0 on the stones
            a = a * (gap < 0 ? 0 : gap > 1 ? 1 : gap);
        }
        return a;
    };
    const double plate = kind == CK_DIRT ? 1 + PLATE_PALE * amount : 1;
    double lum_before = 0, lum_after = 0, open = 0;
    for (int n = 0; n < PN; n++) {
        const double crack = crack_at(here, n);
        const double north = n >= PT ? crack_at(here, n - PT) : crack_at(north_piece, n + PT * (PT - 1));
        double lit = north - crack;   // the far (south) wall catches the light
        lit = lit > 0 ? lit : 0;
        const double f = plate * (1 + lit * (CRACK_LIT - 1));
        double c0 = red[n] * f, c1 = green[n] * f, c2 = blue[n] * f;
        c0 = c0 + (hollow[0] - c0) * crack;
        c1 = c1 + (hollow[1] - c1) * crack;
        c2 = c2 + (hollow[2] - c2) * crack;
        out_r[n] = c0; out_g[n] = c1; out_b[n] = c2; cracks[n] = crack;
        lum_before = lum_before + lum[n];
        lum_after = lum_after + (c0 * 0.299 + c1 * 0.587 + c2 * 0.114);
        open = open + (1 - crack);
    }
    // keep the tile's mean lightness: the plates (not the cracks) brighten to make up for it
    // (Lua: (lum_before / lum_after - 1) * TILE * TILE / open, left to right)
    const double spare = (lum_after > 0 && open > 0) ? (lum_before / lum_after - 1) * PT * PT / open : 0;
    for (int n = 0; n < PN; n++) {
        const double f = 1 + spare * (1 - cracks[n]);
        px[n] = (px[n] & 0xff000000u) | (round_byte(out_b[n] * f) << 16) | (round_byte(out_g[n] * f) << 8) | round_byte(out_r[n] * f);
    }
}

// ---- THE LOOK'S PIXEL WORK HERE (15Z) ----
// colour.lua did these pixel by pixel in Lua, reading through DFHack, while a look was made (in play,
// 2026-11-20: a change of look's sheet stage was 50 frames of it). Lua sends them as jobs in the same
// ring now, by kind; a job's other numbers aren't theirs.
enum : uint32_t { PJ_LOOK = 0, PJ_UNPREMULTIPLY = 1, PJ_LEAN = 2, PJ_RUSTLE = 3 };
// PJ_UNPREMULTIPLY (colour.lua: unpremultiplied): a texture the game loaded (its colours multiplied by
// their alpha), with the alpha divided back out where it's partly see-through.
static void paint_unpremultiplied(const uint32_t* src, uint32_t* dst) {
    for (int n = 0; n < 1024; n++) {
        const uint32_t w = src[n];
        const uint32_t a = w >> 24;
        uint32_t r = w & 0xff, g = (w >> 8) & 0xff, b = (w >> 16) & 0xff;
        if (a > 0 && a < 255) {
            r = (r * 255 + a / 2) / a; if (r > 255) r = 255;
            g = (g * 255 + a / 2) / a; if (g > 255) g = 255;
            b = (b * 255 + a / 2) / a; if (b > 255) b = 255;
        }
        dst[n] = (a << 24) | (b << 16) | (g << 8) | r;
    }
}
// PJ_LEAN (colour.lua: clump_offset, then leaning). Where a grass texture sits from the clump it belongs
// to, in tiles: a clump fills its tile (0, 0); an edge piece's grass lies towards its clump's side.
// False if it has no pixels.
static const double LEAN_REACH_MOST = 1.5;   // (colour.lua) in half tiles from the clump's centre, past which pixels move no further
static bool lean_clump(const uint32_t* px, int& ox, int& oy) {
    double count = 0, mx = 0, my = 0;
    int opaque = 0;
    for (int i = 0; i < 1024; i++) {
        const uint32_t a = px[i] >> 24;
        if (a > 0) {
            count = count + a;
            if (a > 200) opaque++;
            const int x = i % 32, y = i / 32;
            mx = mx + (x - 15.5) * a; my = my + (y - 15.5) * a;
        }
    }
    if (count == 0) return false;
    ox = oy = 0;
    if (opaque > 1024 * 0.9) return true;
    mx = mx / count; my = my / count;
    const int sx = mx > 3 ? 1 : mx < -3 ? -1 : 0;
    const int sy = my > 3 ? 1 : my < -3 ? -1 : 0;
    ox = -sx; oy = -sy;   // (the grass is towards the clump: the tile is on the far side of it)
    return true;
}
// A grass texture's pixels leaning `amount` px at the tips towards (ux, uy). A clump wraps (its tile
// repeats seamlessly); an edge piece reads its own pixels mirrored at its border. Each pixel is read
// from a point a fraction of a pixel away, blended from the four round it, the colours weighted by
// their alpha. With no pixels there's nothing to lean (Lua makes no frames): all clear.
static void paint_lean(const uint32_t* px, uint32_t* out, double amount, double ux, double uy) {
    int ox = 0, oy = 0;
    if (!lean_clump(px, ox, oy)) { memset(out, 0, 4096); return; }
    const bool wrap = ox == 0 && oy == 0;
    const double half = 16;
    for (int y = 0; y < 32; y++) {
        const double cy = y + 0.5 + oy * 32 - half;
        for (int x = 0; x < 32; x++) {
            const double cx = x + 0.5 + ox * 32 - half;
            const double out_of = sqrt(cx * cx + cy * cy) / half;   // (math.min written out, as in bake_fade_px)
            const double reach = out_of > LEAN_REACH_MOST ? LEAN_REACH_MOST : out_of;
            const double shift = amount * reach;
            const double fx = x - ux * shift, fy = y - uy * shift;
            const double x0 = floor(fx), y0 = floor(fy);
            const double tx = fx - x0, ty = fy - y0;
            const int ix = (int)x0, iy = (int)y0;
            const int cxs[4] = {ix, ix + 1, ix, ix + 1}, cys[4] = {iy, iy, iy + 1, iy + 1};
            const double ws[4] = {(1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty};
            double r = 0, g = 0, b = 0, a = 0;
            for (int k = 0; k < 4; k++) {
                const double w = ws[k];
                if (!(w > 0)) continue;
                int sx = cxs[k], sy = cys[k];
                if (wrap) { sx = ((sx % 32) + 32) % 32; sy = ((sy % 32) + 32) % 32; }
                else {
                    sx = sx < 0 ? -sx - 1 : sx >= 32 ? 63 - sx : sx;
                    sy = sy < 0 ? -sy - 1 : sy >= 32 ? 63 - sy : sy;
                }
                const uint32_t p = px[sy * 32 + sx];
                const double wa = w * (double)(p >> 24);
                r = r + (double)(p & 0xff) * wa; g = g + (double)((p >> 8) & 0xff) * wa; b = b + (double)((p >> 16) & 0xff) * wa;
                a = a + wa;
            }
            if (a > 0) { r = r / a; g = g / a; b = b / a; }
            out[y * 32 + x] = ((uint32_t)floor(a + 0.5) << 24) | ((uint32_t)floor(b + 0.5) << 16)
                            | ((uint32_t)floor(g + 0.5) << 8) | (uint32_t)floor(r + 0.5);
        }
    }
}

// ---- THE RUSTLE PAINTED HERE (16A) ----
// colour.lua: leafy, is_leaves and rustle_frame's pixels. A frame of the rustle loop: each moving clump's
// pixels a whole pixel off, drawn over the picture as it was (a clump that moves leaves its edge behind,
// not a hole). Lua works out which of the 14 clumps move and which way (RM_* bits, a byte each), from its
// own clump layout, handed over once as each pixel's clump (rustle_of).
static const double RUSTLE_LEAF_SATURATION = 0.4;   // (colour.lua: LEAF_SATURATION) a pixel more saturated than this is leaf-coloured
static const double RUSTLE_OUTLINE_VALUE = 0.25;    // (OUTLINE_VALUE) and one darker than this an outline, which moves with them
static const double RUSTLE_LEAF_SHARE = 0.35;       // (LEAF_SHARE) of a picture's opaque pixels leaf-coloured, for it to be leaves
enum : uint8_t { RM_DX = 3, RM_DY = 12, RM_MOVES = 16 };   // a clump's byte: dx + 1 (bits 0-1), dy + 1 (bits 2-3), moving (bit 4)
static inline int rustle_most(uint32_t p, int& least) {
    const int r = p & 0xff, g = (p >> 8) & 0xff, b = (p >> 16) & 0xff;
    int most = r > g ? r : g; if (b > most) most = b;
    least = r < g ? r : g; if (b < least) least = b;
    return most;
}
// (leafy) a pixel leaf-coloured, or a dark outline
static inline bool rustle_leafy(uint32_t p) {
    int least;
    const int most = rustle_most(p, least);
    if (most < RUSTLE_OUTLINE_VALUE * 255) return true;
    return (double)(most - least) / most > RUSTLE_LEAF_SATURATION;
}
// (is_leaves) most of a picture's opaque pixels leaf-coloured
static bool rustle_is_leaves_px(const uint32_t* px) {
    int opaque = 0, leaf = 0;
    for (int i = 0; i < 1024; i++) {
        const uint32_t p = px[i];
        if ((p >> 24) > 128) {
            opaque++;
            int least;
            const int most = rustle_most(p, least);
            if (most > 0 && (double)(most - least) / most > RUSTLE_LEAF_SATURATION) leaf++;
        }
    }
    return opaque > 0 && (double)leaf / opaque >= RUSTLE_LEAF_SHARE;
}
// Texture `copy` is leaves (true also when its pixels can't be read: Lua decides then, as before).
static bool rustle_is_leaves(int32_t copy) {
    uint32_t scratch[1024];
    const uint32_t* px = crack_pixels(copy, scratch);
    return !px || rustle_is_leaves_px(px);
}
// (rustle_frame) frame of `src` with the clumps' moves; all: every pixel moves (the grass), else the leafy ones
static void paint_rustle(const uint32_t* src, uint32_t* out, const uint8_t* moves, bool all) {
    memcpy(out, src, 4096);
    const uint8_t* of = B.rustle_of;
    for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
            const int i = y * 32 + x;
            const uint8_t k = of[i];
            if (k >= 14) continue;
            const uint8_t m = moves[k];
            const uint32_t p = src[i];
            if (!(m & RM_MOVES) || !(p >> 24) || !(all || rustle_leafy(p))) continue;
            const int tx = x + (int)(m & RM_DX) - 1, ty = y + (int)((m & RM_DY) >> 2) - 1;
            if (tx >= 0 && tx < 32 && ty >= 0 && ty < 32) out[ty * 32 + tx] = p;
        }
    }
}

static void paint_one(const PaintJob& j) {
    const uint32_t* src = (const uint32_t*)(uintptr_t)j.src;
    uint32_t* dst = (uint32_t*)(uintptr_t)j.dst;
    if (!src || !dst || !readable_span(src, 4096) || !readable_span(dst, 4096)) { B.paint_bad++; return; }
    // (THE LOOK'S PIXEL WORK HERE, 15Z) the other kinds first: the rest of their job isn't theirs
    if (j.kind == PJ_UNPREMULTIPLY) { paint_unpremultiplied(src, dst); B.paint_unpremultiplied++; return; }
    if (j.kind == PJ_LEAN) { paint_lean(src, dst, j.m[0], j.m[1], j.m[2]); B.paint_leans++; return; }
    if (j.kind == PJ_RUSTLE) {   // (16A, THE RUSTLE PAINTED HERE)
        if (!B.rustle_of_ready) { B.paint_bad++; return; }
        const uint8_t* bytes = (const uint8_t*)&j;
        paint_rustle(src, dst, bytes + 16, bytes[32] != 0);
        B.paint_rustles++;
        return;
    }
    if (j.kind != PJ_LOOK) { B.paint_bad++; return; }
    if (j.grain && !readable_span((const void*)(uintptr_t)j.grain, 4096)) { B.paint_bad++; return; }
    // (DRY CRACKS: both pattern pieces readable, or the job is refused rather than cracked wrong)
    const uint32_t* crack_here = (const uint32_t*)(uintptr_t)j.crack_here;
    const uint32_t* crack_north = (const uint32_t*)(uintptr_t)j.crack_north;
    if (j.crack_kind && (j.crack_kind > CK_PEBBLES || !crack_here || !crack_north ||
                         !readable_span(crack_here, 4096) || !readable_span(crack_north, 4096))) { B.paint_bad++; return; }
    if (j.cls) {   // (THE FULL REDRAW)
        paint_full(j, src, dst);
        if (j.crack_kind) crack_in_place(dst, j.crack_kind, j.crack_amount, crack_here, crack_north);
        else if (j.dst_tex > 0) bypic_file(crack_hash_pixels(src), j.dst_tex);   // (BY PICTURE)
        B.paint_done++;
        return;
    }
    const double* m = j.m;
    for (int n = 0; n < 1024; n++) {
        const uint32_t w = src[n];
        const double r = (double)(w & 0xff), g = (double)((w >> 8) & 0xff), b = (double)((w >> 16) & 0xff);
        double nr = m[0] * r + m[1] * g + m[2] * b;
        double ng = m[3] * r + m[4] * g + m[5] * b;
        double nb = m[6] * r + m[7] * g + m[8] * b;
        if (j.has_lean) {
            const double before = lum_of(nr, ng, nb);
            nr = nr * j.lean[0]; ng = ng * j.lean[1]; nb = nb * j.lean[2];
            const double after = lum_of(nr, ng, nb);
            const double k = after > 0 ? before / after : 1;
            nr = nr * k; ng = ng * k; nb = nb * k;
        }
        nr = nr * j.dark; ng = ng * j.dark; nb = nb * j.dark;
        if (j.lighten > 0) {
            nr = nr + (255 - nr) * j.lighten; ng = ng + (255 - ng) * j.lighten; nb = nb + (255 - nb) * j.lighten;
        } else {
            nr = nr * (1 + j.lighten); ng = ng * (1 + j.lighten); nb = nb * (1 + j.lighten);
        }
        dst[n] = (w & 0xff000000u) | (channel(nb) << 16) | (channel(ng) << 8) | channel(nr);
    }
    if (j.crack_kind) crack_in_place(dst, j.crack_kind, j.crack_amount, crack_here, crack_north);   // (DRY CRACKS)
    else if (j.dst_tex > 0) bypic_file(crack_hash_pixels(src), j.dst_tex);   // (BY PICTURE)
    B.paint_done++;
}

static void paint_copies() {
    if (B.paint_tail == B.paint_head) return;
    const double t0 = ticks_now();
    while (B.paint_tail != B.paint_head) {
        paint_one(B.paint[B.paint_tail % PAINT_RING]);
        B.paint_tail++;
    }
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.paint_us_total += us;
    if (us > B.paint_us_max) B.paint_us_max = us;
}

// =====================================================================
// MURKY (test 14): murky.lua's tint over stagnant water (main thread)
// =====================================================================
// WHAT: the game marks still water gone bad as stagnant but draws it clear;
// murky.lua tinted it a pond's green with art/murky.png, a see-through
// patch 4 x 4 tiles big repeated across the map. Its rules, here every
// frame from the map: a tile with the water_stagnant bit, some water
// (flow_size), not magma and not hidden, on the view's level (into the
// layer above the spatter) or up to murky_depths levels below, where every
// level between is open (TT_OPEN: empty or a ramp's top); only a cell whose
// layer is empty (mud or blood, a dig mark or the shade left be).
// WATER SEEN FROM ABOVE: a pond seen from the level above is drawn as the
// water's surface over the level it's on, covering every layer of that
// lower view: the tint written into the lower view's item layer (test 14,
// as murky.lua did) and its spatter (14B) never showed, 56 and 109 cells
// written. In the view's own designation layer (14C) it showed, but over
// the banks' grass overhanging the water too, in hard squares. The view's
// own ground layer (14D) is never empty on open air (0 cells written). So
// the levels below are tinted in the view's own layer above the spatter at
// that cell (14E), the layer the tint uses on the water's own level, where
// the banks' edges drew over it. Drawn after the snow, which decides cells
// by what DF drew. On open air there the game draws the water's ripple, a
// new number each frame, and those cells were left blue (14E): above the
// water the tint replaces whatever is there but Detailed Weather's own
// drawing (a snowy edge), not only an empty cell (14F).
// Like murky.lua nothing is put back: the game redraws the layers itself.
// Drawn after colour's swaps, and its textures are marked as never to be
// swapped, so the look is never painted over the tint.
// MURKY: EDGES OVER THE TINT. On open air above the water the tint goes in
// the layer above the spatter, which draws over the banks' grass that
// overhangs the water: the edges went under the tint. So such a cell gets
// the tint with its overhang pieces drawn back over it, painted here once
// per combination into a blank texture Lua keeps ready, and kept:
//   * the side pieces: the cell's floor_flag, a byte per side (S, W, E, N),
//     each the edging ID of the neighbour overhanging it (edge_art);
//   * the corner pieces the game adds itself from grass on the diagonal
//     neighbours, by the snow's rule (decide_edges: a corner whose two
//     sides don't already carry that grass).
// Pieces are laid over the tint as frost.lua's as_drawn lays them: an
// opaque pixel replaces what's under it, a partly see-through one is
// blended in by its alpha, the alpha the greater of the two.
struct TintBake { uint64_t key; int32_t tint; int32_t tex; uint8_t used; uint8_t pad[7]; };   // (keyed by the tint's own texture too, so a new tint never reuses old bakes)
static const int MURKY_MOST_DEPTH = 8;     // levels down murky water is drawn to (15E; murky.lua: 3)
static const int MURKY_MOST_PIECES = 9 * MURKY_MOST_DEPTH;   // over one cell: a haze and 8 edges (4 sides, 4 corners) a level
static const uint16_t MURKY_HAZE_CODE = 0x8000;   // (15F: the code for a haze layer; none are made since 15G)
static const int TINT_BAKES = 4096;   // (a power of 2)
static TintBake g_tint_bakes[TINT_BAKES];
static int g_tint_used = 0;           // entries filled (all forgotten at 3/4, so lookups stay short)

// The tint cell k with the overhang pieces listed laid over it, in order (codes: edging ID * 8 +
// piece, edge_art's order), made once per combination and kept (0: no blank this frame).
static int32_t tint_with_edges(int k, const uint16_t* codes, int n_codes) {
    const int32_t tint_tex = B.murky_tex[k];
    // the combination's key: FNV-1a over the tint and the pieces (64 bits: a clash is beyond likely)
    uint64_t key = 1469598103934665603ull;
    key = (key ^ (uint32_t)tint_tex) * 1099511628211ull;
    for (int c = 0; c < n_codes; c++) key = (key ^ codes[c]) * 1099511628211ull;
    const uint64_t h = key * 0x9E3779B97F4A7C15ull;
    for (int probe = 0; probe < 32; probe++) {
        TintBake& e = g_tint_bakes[(h + probe) & (TINT_BAKES - 1)];
        if (e.used && e.key == key && e.tint == tint_tex) return e.tex;
        if (e.used) continue;
        // a new combination: painted into the next blank (the list full: started again, the old
        // textures left as they are, for the cells still showing them this frame)
        if (g_tint_used >= TINT_BAKES * 3 / 4) { memset(g_tint_bakes, 0, sizeof g_tint_bakes); g_tint_used = 0; }
        if (B.murky_blank_tail == B.murky_blank_head) { B.murky_bake_waits++; return 0; }
        const uint32_t slot = B.murky_blank_tail % 256;
        const int32_t tex = B.murky_blank_tex[slot];
        uint32_t* dst = (uint32_t*)(uintptr_t)B.murky_blank_addr[slot];
        const uint32_t* tint = (const uint32_t*)(uintptr_t)B.murky_tint_addr[k];
        if (!tex || !dst || !tint || !readable_span(dst, 4096) || !readable_span(tint, 4096)) { B.murky_bake_waits++; return 0; }
        B.murky_blank_tail++;
        // the layers: the tint, then the pieces as listed
        const uint32_t* layers[MURKY_MOST_PIECES];
        int n = 0;
        for (int c = 0; c < n_codes && n < MURKY_MOST_PIECES; c++) {
            const uint16_t code = codes[c];
            const uint32_t* piece = (code & MURKY_HAZE_CODE) ? (const uint32_t*)(uintptr_t)B.haze_air_addr
                                                              : (const uint32_t*)(uintptr_t)B.edge_addr[code >> 3][code & 7];
            if (piece && readable_span(piece, 4096)) layers[n++] = piece;
        }
        // (MURKY: FRAME BY FRAME: a piece with no pixel showing is likely a copy not painted yet)
        for (int L = 0; L < n; L++) {
            bool any = false;
            for (int px = 0; px < 1024 && !any; px++) any = (layers[L][px] >> 24) != 0;
            if (!any) B.murky_empty_pieces++;
        }
        for (int px = 0; px < 1024; px++) {
            const uint32_t w = tint[px];
            double r = (double)(w & 0xff), g = (double)((w >> 8) & 0xff), bl = (double)((w >> 16) & 0xff);
            uint32_t a = w >> 24;
            for (int L = 0; L < n; L++) {
                const uint32_t t = layers[L][px];
                const uint32_t ta = t >> 24;
                if (ta == 255) {
                    r = (double)(t & 0xff); g = (double)((t >> 8) & 0xff); bl = (double)((t >> 16) & 0xff); a = 255;
                } else if (ta > 0) {
                    const double kk = ta / 255.0;
                    r = (t & 0xff) * kk + r * (1 - kk);
                    g = ((t >> 8) & 0xff) * kk + g * (1 - kk);
                    bl = ((t >> 16) & 0xff) * kk + bl * (1 - kk);
                    if (ta > a) a = ta;
                }
            }
            dst[px] = (a << 24) | (channel(bl) << 16) | (channel(g) << 8) | channel(r);
        }
        e.key = key; e.tint = tint_tex; e.tex = tex; e.used = 1;
        g_tint_used++;
        if (tex > 0 && tex < TEX_MAP) g_cflag[tex] = CF_LEAVE;   // (never swapped by THE COLOUR)
        B.murky_baked++;
        return tex;
    }
    B.murky_bake_waits++;
    return 0;
}

// The corner pieces the game adds to open cell (x, y, z) from grass on its
// diagonal neighbours (snow's decide_edges rule), as four edging IDs (NW,
// NE, SW, SE; 0: none), given the cell's side bytes. The blocks' edging is
// worked out here, a few blocks kept for the frame (not the snow's block
// cache, which is the snow's, per its own frame, and may not be running).
struct EdgingMemo { const uint8_t* blk; int64_t frame; uint8_t id[256]; };
static EdgingMemo g_edging_memo[8];
static int g_edging_next = 0;
static const uint8_t* edging_in(const uint8_t* blk) {
    for (int m = 0; m < 8; m++)
        if (g_edging_memo[m].blk == blk && g_edging_memo[m].frame == B.murky_frames) return g_edging_memo[m].id;
    EdgingMemo& e = g_edging_memo[g_edging_next];
    g_edging_next = (g_edging_next + 1) & 7;
    edging_of(blk, e.id);
    e.blk = blk;
    e.frame = B.murky_frames;
    return e.id;
}
static uint32_t corner_ids(int32_t x, int32_t y, int32_t z, uint32_t sides) {
    if (!B.grass_vtable || !B.murky_corners) return 0;
    uint32_t out = 0;
    for (int c = 0; c < 4; c++) {
        const int32_t nx = x + CORNER_DX[c], ny = y + CORNER_DY[c];
        if (nx < 0 || ny < 0 || nx >= g_map.x_end || ny >= g_map.y_end) continue;
        const uint8_t* blk = block_ptr(nx >> 4, ny >> 4, z);
        if (!blk) continue;
        const uint8_t id = edging_in(blk)[tile_of(nx, ny)];
        if (!id) continue;
        const uint8_t s1 = (uint8_t)((sides >> (8 * CORNER_SIDE1[c])) & 0xff), s2 = (uint8_t)((sides >> (8 * CORNER_SIDE2[c])) & 0xff);
        if (beats(id, 0) && s1 != id && s2 != id) out |= (uint32_t)id << (8 * c);
    }
    return out;
}

// The banks' edges over cell i of water seen d levels down, as codes into codes, how many: those of
// the level just above the water (15G: where the tint goes, in its bg2, which draws over that level's
// edges): its sides (its floor_flag: S, W, E, N), then the corners the game adds (NW, NE, SW, SE),
// each edging ID * 8 + piece. (The levels above draw their own edges over it, and the game hazes it
// with the rest of its level; 15C to 15F laid all of those here, over a tint in the view's layer.) Seen from the level just above the water, the banks' edges are in the
// view's own floor_flag; seen from higher up, in a lower viewport's (15C: they went under the tint).
static int murky_pieces(int d, int32_t i, int32_t x, int32_t y, uint64_t* const* ffs, uint16_t* codes) {
    int n = 0;
    for (int k = d - 1; k >= d - 1 && k >= 0; k--) {   // (15G: the level just above the water only)
        if (!ffs[k]) continue;
        const uint32_t sides = (uint32_t)(ffs[k][i] & 0xffffffffull);
        const uint32_t corners = corner_ids(x, y, B.drawn_z - k, sides);
        for (int b = 0; b < 4 && n < MURKY_MOST_PIECES; b++) {
            const uint8_t id = (uint8_t)((sides >> (8 * b)) & 0xff);
            if (id && B.edge_addr[id][SIDE_PIECE[b]]) codes[n++] = (uint16_t)(id * 8 + SIDE_PIECE[b]);
        }
        for (int c = 0; c < 4 && n < MURKY_MOST_PIECES; c++) {
            const uint8_t id = (uint8_t)((corners >> (8 * c)) & 0xff);
            if (id && B.edge_addr[id][4 + c]) codes[n++] = (uint16_t)(id * 8 + 4 + c);
        }
    }
    return n;
}

static uint8_t* g_murky_see = nullptr;   // 1 where every level above, down to this one, is open
static int32_t  g_murky_n = 0;

static void draw_murky() {
    if (!B.murky_enabled || !B.have_drawn || !B.main_viewport || !B.block_index || !B.x_count_block ||
        !B.y_count_block || !B.z_count_block || !B.off_dim_x || !B.off_dim_y || !B.off_tiletype || !B.off_designation) return;
    const double t0 = ticks_now();
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    for (int k = 0; k < 16; k++) {   // (never swapped by THE COLOUR)
        const int32_t t = B.murky_tex[k];
        if (t > 0 && t < TEX_MAP) g_cflag[t] = CF_LEAVE;
    }
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    const int32_t n = dx * dy;
    if (g_murky_n < n) {
        free(g_murky_see);
        g_murky_see = (uint8_t*)malloc((size_t)n);
        g_murky_n = g_murky_see ? n : 0;
        if (!g_murky_see) return;
    }
    memset(g_murky_see, 1, (size_t)n);
    // MURKY: EDGES OVER THE TINT forgotten when Lua asks (a start: another world's textures; a new
    // look: the pieces in its colours). Done here, in tidy, their only user: Lua asks on the game
    // thread, which never runs alongside tidy, so this frame already has its edges (14J: done on the
    // game thread, the first frame went without, and the snow's start held it on screen)
    if (B.murky_bake_reset != B.murky_bake_reset_done) {
        memset(g_tint_bakes, 0, sizeof g_tint_bakes);
        g_tint_used = 0;
        B.murky_bake_reset_done = B.murky_bake_reset;
    }
    const bool bakes_ok = true;
    // (EDGES OVER THE TINT: each level's overhangs, the view's and those below it, for water further down)
    uint64_t* ffs[MURKY_MOST_DEPTH] = {};
    uint8_t* vps[MURKY_MOST_DEPTH] = {};   // (THE PROBE: each level's viewport)
    uint32_t levels_shown = 0;             // (MURKY: FRAME BY FRAME, 15W: how many levels DF shows, this one first)
    for (int k = 0; k < MURKY_MOST_DEPTH; k++) {
        uint8_t* vk = viewport_in(k);
        if (!vk) break;
        if (k > 0 && !(*(const uint32_t*)(vk + B.off_flag) & 1)) break;
        if (*(const int32_t*)(vk + B.off_dim_x) != dx || *(const int32_t*)(vk + B.off_dim_y) != dy) break;
        if (B.off_floor_flag) ffs[k] = *(uint64_t* const*)(vk + B.off_floor_flag);
        vps[k] = vk;
        levels_shown = (uint32_t)k + 1;
    }
    uint32_t haze_layers = 0;
    const uint32_t stag = B.stagnant_mask, flow = B.flow_mask, magma = B.magma_mask, hidden = B.hidden_mask;
    const int depths = (int)(B.murky_depths < (uint32_t)MURKY_MOST_DEPTH ? B.murky_depths : MURKY_MOST_DEPTH);
    for (int k = 0; k < 4; k++) B.murky_drawn[k] = 0;
    uint32_t total = 0;
    uint32_t h_above = 0, h_over = 0, h_edges = 0, h_not_ok = 0, h_wait = 0;   // (MURKY: FRAME BY FRAME)
    // BRANCHES SEEN THROUGH (15P, 15Q): g_murky_see's bits: SEE_OPEN, the cell is still seen; SEE_BRANCH,
    // a tree's branches or leaves were looked through on the way (the game shows the levels below them:
    // 15H); SEE_BRANCH_LAST, the level just walked was one. Water seen through branches higher up is
    // tinted as through open space (15P's probe: the tint's layer, background_two of the level just above
    // the water, was empty there, the branch a level higher). Water with a branch or leaves on the level
    // just above it is left, counted and probed: that level's background_two may hold the branch itself.
    // THE PROBE prefers it (probe_kind 3), then water seen through branches (2), then through air (1).
    enum : uint8_t { SEE_OPEN = 1, SEE_BRANCH = 2, SEE_BRANCH_LAST = 4 };
    uint32_t under_branch = 0, branch_above = 0;
    int probe_kind = 0;
    const bool probe_wanted = B.probe_ask != B.probe_done;
    // every level's fields at one cell, as they are before anything is written there this frame
    auto probe_cell = [&](int d, int32_t i, int32_t x, int32_t yy, uint8_t* vp, int kind) {
        memset(B.probe_val, 0, sizeof B.probe_val);
        for (int pk = 0; pk <= d && pk < 8; pk++) {
            uint8_t* pv = pk < MURKY_MOST_DEPTH ? (pk < d ? vps[pk] : vp) : nullptr;
            if (!pv) continue;
            for (int f = 0; f < 16; f++) {
                const uint32_t of = B.off_probe[f];
                if (!of) continue;
                const uint8_t* arr = *(const uint8_t* const*)(pv + (of & 0xffffff));
                if (!arr) continue;
                B.probe_val[pk][f] = (of >> 24) == 8 ? ((const uint64_t*)arr)[i] : (uint64_t)((const uint32_t*)arr)[i];
            }
        }
        // which levels between were branches or leaves (the map, at the cell)
        uint32_t through = 0;
        for (int pk = 0; pk < d && pk < 32; pk++) {
            const uint8_t* b = block_ptr(x >> 4, yy >> 4, B.drawn_z - pk);
            const uint8_t tf = b ? flags_of(((const uint16_t*)(b + B.off_tiletype))[tile_of(x, yy)]) : 0;
            if ((tf & TT_TREE) && !(tf & TT_TRUNK)) through |= 1u << pk;
        }
        B.probe_through = through;
        B.probe_d = d; B.probe_x = x; B.probe_y = yy;
        probe_kind = kind;
    };
    for (int d = 0; d <= depths; d++) {
        uint8_t* vp = viewport_in(d);
        if (!vp) break;
        if (d > 0 && !(*(const uint32_t*)(vp + B.off_flag) & 1)) break;
        if (*(const int32_t*)(vp + B.off_dim_x) != dx || *(const int32_t*)(vp + B.off_dim_y) != dy) break;
        // (WATER SEEN FROM ABOVE: into the layer above the ground of the level just above the water,
        // which holds the water's surface and the banks' edges: the view's own for water one level
        // down. 15G: for water further down, that level's, so the game hazes the tint with the rest of
        // that level, and draws the levels above over it, as it does the land beside it.)
        uint8_t* above = d == 0 ? vp : (d - 1 < MURKY_MOST_DEPTH ? vps[d - 1] : nullptr);
        if (!above) break;
        int32_t* layer = *(int32_t* const*)(above + B.off_bg2);
        if (!layer) break;
        const int32_t z = B.drawn_z - d;
        if (z < 0 || z >= g_map.zn) break;
        uint32_t drawn = 0;
        bool any_open = false;
        for (int32_t sx = 0; sx < dx; sx++) {
            const int32_t x = B.drawn_x + sx;
            if (x < 0 || x >= g_map.x_end) { memset(g_murky_see + (size_t)sx * dy, 0, (size_t)dy); continue; }
            int32_t sy = 0;
            while (sy < dy) {
                const int32_t y = B.drawn_y + sy;
                const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
                const int32_t end = sy + run < dy ? sy + run : dy;
                const uint8_t* blk = (y >= 0 && y < g_map.y_end) ? block_ptr(x >> 4, y >> 4, z) : nullptr;
                if (!blk) { memset(g_murky_see + (size_t)sx * dy + sy, 0, (size_t)(end - sy)); sy = end; continue; }
                const uint32_t* des = (const uint32_t*)(blk + B.off_designation) + ((x & 15) << 4);
                const uint16_t* types = (const uint16_t*)(blk + B.off_tiletype) + ((x & 15) << 4);
                for (; sy < end; sy++) {
                    const int32_t i = sx * dy + sy;
                    if (!g_murky_see[i]) continue;
                    const int ly = (B.drawn_y + sy) & 15;
                    const uint32_t f = des[ly];
                    const int32_t was = layer[i];
                    const bool stagnant = (f & stag) && (f & flow) && !(f & magma) && !(f & hidden);
                    const uint8_t see = g_murky_see[i];
                    if (stagnant && d > 0 && (see & SEE_BRANCH_LAST)) {   // (BRANCHES SEEN THROUGH: a branch just above: left)
                        branch_above++;
                        if (probe_wanted && probe_kind < 3) probe_cell(d, i, x, B.drawn_y + sy, vp, 3);
                    } else if (stagnant && (was == 0 || (d > 0 && !is_ours(was)))) {   // (above the water: over its ripple, and its last tint)
                        if (see & SEE_BRANCH) {   // (BRANCHES SEEN THROUGH: tinted as through air; counted, maybe probed)
                            under_branch++;
                            if (probe_wanted && probe_kind < 2 && d >= 1) probe_cell(d, i, x, B.drawn_y + sy, vp, 2);
                        }
                        const int32_t yy = B.drawn_y + sy;
                        const int k = (yy & 3) * 4 + (x & 3);
                        int32_t tex = B.murky_tex[k];
                        // (EDGES OVER THE TINT: above the water, each level's haze and the banks' overhangs laid back over it)
                        if (d > 0) {
                            h_above++;
                            uint16_t codes[MURKY_MOST_PIECES];
                            const int n_codes = murky_pieces(d, i, x, yy, ffs, codes);

                            // MURKY: THE PROBE: the first cell of water two or more levels down, every
                            // level's fields Lua listed, as they are before anything here is written
                            // (BRANCHES PROBED: unless one under branches is taken; done at the frame's end)
                            if (d >= 2 && probe_wanted && probe_kind < 1) probe_cell(d, i, x, yy, vp, 1);
                            if (n_codes) {
                                h_over++;
                                if (!bakes_ok) h_not_ok++;
                                else { const int32_t both = tint_with_edges(k, codes, n_codes); if (both) { tex = both; h_edges++; } else h_wait++; }
                            }
                        }
                        if (tex > 0) { layer[i] = tex; drawn++; }
                    }
                    // the levels below show only through this one if it's open (BRANCHES PROBED: or a
                    // tree's branches or leaves, which the game shows the levels below too; marked 2)
                    const uint8_t tf = flags_of(types[ly]);
                    if (tf & TT_OPEN) { any_open = true; g_murky_see[i] = (uint8_t)(see & ~SEE_BRANCH_LAST); }
                    else if ((tf & TT_TREE) && !(tf & TT_TRUNK)) {
                        g_murky_see[i] = (uint8_t)(see | SEE_BRANCH | SEE_BRANCH_LAST);
                        any_open = true;
                    }
                    else g_murky_see[i] = 0;
                }
            }
        }
        B.murky_drawn[d < 3 ? d : 3] += drawn;   // (the last: 3 levels down and more)
        total += drawn;
        if (!any_open) break;
    }
    // (BRANCHES PROBED: the probe, if one was taken, done; the count)
    if (probe_kind) {
        if (probe_kind == 1) B.probe_through = 0;
        B.probe_done = B.probe_ask;
    }
    B.murky_under_branch_last = under_branch;
    B.murky_under_branch += under_branch;
    B.murky_branch_above_last = branch_above;
    // MURKY: FRAME BY FRAME: a record when the numbers change. (15W: the view's level in y's top 16 bits and
    // the levels DF shows in x's, to tell a change of level, or the levels below not shown that frame, from
    // a tint missing: 15V's report had frames with nothing tinted at the same x,y)
    {
        const uint32_t rec[8] = {(uint32_t)B.murky_frames, ((uint32_t)B.drawn_x & 0xffffu) | (levels_shown << 16),
                                 ((uint32_t)B.drawn_y & 0xffffu) | ((uint32_t)B.drawn_z << 16),
                                 h_above, h_over, h_edges, h_not_ok, h_wait};
        const uint32_t* last = B.murky_hist_head ? B.murky_hist[(B.murky_hist_head - 1) % 128] : nullptr;
        if (!last || memcmp(last + 1, rec + 1, 7 * sizeof(uint32_t)) != 0) {
            memcpy(B.murky_hist[B.murky_hist_head % 128], rec, sizeof rec);
            B.murky_hist_head++;
        }
    }
    B.haze_layers_last = haze_layers;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.murky_frames++;
    B.murky_written += total;
    B.murky_us_total += us;
    if (us > B.murky_us_max) B.murky_us_max = us;
}

// =====================================================================
// FOG OVER WATER (test 15H): the game's haze over deep water set to the
// level its surface is drawn on
// =====================================================================
// THE GAME'S HAZE (g_src: graphics.cpp, renderer_2d.hpp; measured on
// screenshots a level apart, 2026-11-19):
//   * a cell seen down through open space gets ONE haze over everything
//     below the view's level in it, the ground and any branches between:
//     a texture laid in the interface layer of a level below (stone-tint's
//     depth probe found it there; 15F's probe never read that layer);
//   * the texture is gps.multilevel_depth_texpos[i] (DFHack: the first 8
//     of gps.texture_indices1): [0] is MULTILEVEL_AIR, light blue at alpha
//     96, and [i] the same at alpha 96 + 159 * i / 8 (graphics.cpp);
//   * i goes by the level at the bottom of the cell, i + 1 levels down:
//     ground one level down took alpha 96, a pond's water two levels down
//     115. Leaves one, two and three levels down took the haze of the
//     ground under them, not one for their own level.
// WHAT SHOWED (15G): the bottom of a water cell is the water's own level,
// but the game draws the water's surface, and the banks' edges over it, on
// the level above (15F's probe). So a water cell, and everything over it,
// took a haze a step deeper than the bank beside it on the same level:
// branches over the river or the pond, and the banks' edges over the water,
// hazed more than their neighbours, a seam along the shore on every level
// up (leaves over land kept 80 of 255 of their colour, over the river 60;
// a level higher, 60 and 40).
// HOW:
//   * THE PLAN (prerender, the game thread, which changes the map): each
//     tile walked down from the view's level, through open space and a
//     tree's branches and leaves (the game sees through those too), to the
//     first level that is neither. A tile whose bottom is full water (7 of
//     7, water or magma) two or more levels down is marked with its depth,
//     and whether the level just above the water is open space. Walked a
//     map block at a time and kept (THE PLAN'S BLOCKS), so a still or
//     panning view costs a copy a cell, not a walk.
//   * THE FIX (the hook, the main thread): a marked cell's haze, where it is
//     the water level's own, becomes the haze of the level above, the
//     surface's. Over open space, only where the game drew something on that
//     level (the surface). A haze the game chose any other way is left.
//   * PUT BACK, as the snow does (STILL OURS, at the top): before the game
//     draws into a buffer again, each cell changed in it gets the game's own
//     haze back, so the game only ever finds its own, and turned off, the
//     game's own is everywhere two frames later.
// Water one level down is left as the game hazes it: its surface is on the
// view's own level, drawn after any haze.
// STILL THE GAME'S: one haze a cell, by its bottom. Branches over a pit, a
// cliff, or a channel cut deeper than its banks still take the bottom's.
static const int FOG_HAZES = 8;           // the game's hazes (g_src: LOWER_VIEWPORT_MAX)
static const uint8_t FOG_DEPTH = 15;      // a mark's depth bits (2 to 8)
static const uint8_t FOG_OVER_AIR = 16;   // a mark's bit: open space just above the water
static uint8_t* g_fog_mark = nullptr;     // THE PLAN: a byte a cell, 0 or the water's depth | FOG_OVER_AIR
static int32_t  g_fog_n = 0;
static bool     g_fog_ready = false;      // a plan for the view the game is drawing this frame
static int32_t  g_fog_x, g_fog_y, g_fog_z, g_fog_dx, g_fog_dy;   // the view it was made for
struct FogKept { int32_t* arr; int32_t index; int32_t game; int32_t ours; };   // PUT BACK: one changed cell
static FogKept* g_fog_kept = nullptr;
static int32_t  g_fog_kept_n = 0, g_fog_kept_cap = 0;
static int32_t  g_fog_kept_dx = 0, g_fog_kept_dy = 0;   // the view's size they were changed at

// THE PLAN'S BLOCKS: a map block's 256 tiles walked down from one view level, their marks kept, as
// the ground and the water change slowly and a pan sees the same blocks again (walking every cell
// every frame cost 240 us on a 160 x 90 view looking down 7 open levels). Kept FOG_KEEP_FRAMES,
// then walked again within FOG_PLAN_US a frame (an old block is used until then). A block not kept
// yet is walked at once, so no cell in view is ever left unplanned. All forgotten at 3/4 full, and
// at each start (another map: the same block numbers, other tiles).
struct FogBlock { int32_t bx, by, z; uint8_t used; uint8_t pad[3]; int64_t made; uint8_t mark[256]; };
static const int FOG_BLOCKS = 1024;       // (a power of 2)
static const int FOG_PROBE = 16;
static const int FOG_KEEP_FRAMES = 90;    // a kept block walked again after this many plans
static const double FOG_PLAN_US = 40;     // old blocks walked again, at most this long a frame
static FogBlock* g_fog_blocks = nullptr;
static int g_fog_blocks_used = 0;
static int64_t g_fog_frame = 0;           // plans made (dates the blocks)
static uint32_t g_fog_walked = 0;         // blocks walked by this plan

// One block's tiles walked down from level z, each to its bottom (as THE PLAN, above, says).
static void fog_walk_block(FogBlock& e) {
    uint8_t walk[256];   // 0 stopped, 1 the last level open space, 2 a tree's branches or leaves
    memset(walk, 1, sizeof walk);
    memset(e.mark, 0, sizeof e.mark);
    const uint32_t flow = B.flow_mask, hidden = B.hidden_mask;
    const int most = (int)(B.lower_count < (uint32_t)MOST_DEPTH ? B.lower_count : MOST_DEPTH);   // (the levels below kept)
    for (int d = 0; d <= most; d++) {
        const int32_t z = e.z - d;
        if (z < 0 || z >= g_map.zn) break;
        const uint8_t* blk = block_ptr(e.bx, e.by, z);
        if (!blk) break;   // (no block on this level: nothing further down shows)
        const uint32_t* des = (const uint32_t*)(blk + B.off_designation);
        const uint16_t* types = (const uint16_t*)(blk + B.off_tiletype);
        bool walking = false;
        for (int t = 0; t < 256; t++) {
            const uint8_t was = walk[t];
            if (!was) continue;
            const uint32_t f = des[t];
            if (f & hidden) { walk[t] = 0; continue; }
            if (f & flow) {   // water or magma: the tile's bottom
                if (d >= 2 && (f & flow) == flow)   // (full, 7 of 7: its surface is on the level above)
                    e.mark[t] = (uint8_t)(d | (was == 1 ? FOG_OVER_AIR : 0));
                walk[t] = 0;
                continue;
            }
            const uint8_t fl = flags_of(types[t]);
            if (fl & TT_OPEN) { walk[t] = 1; walking = true; }
            else if ((fl & TT_TREE) && !(fl & TT_TRUNK)) { walk[t] = 2; walking = true; }   // (branches, leaves)
            else walk[t] = 0;   // (anything else is the bottom)
        }
        if (!walking) break;
    }
    e.made = g_fog_frame;
    g_fog_walked++;
}

// The block (bx, by) walked down from level z: kept, walked again once old if this frame has the
// time, or walked now. nullptr only if it can't be kept (then its cells are left unplanned).
static const FogBlock* fog_block(int32_t bx, int32_t by, int32_t z, double t0) {
    uint32_t h = ((uint32_t)bx * 73856093u) ^ ((uint32_t)by * 19349663u) ^ ((uint32_t)z * 83492791u);
    for (int k = 0; k < FOG_PROBE; k++) {
        FogBlock& e = g_fog_blocks[(h + k) & (FOG_BLOCKS - 1)];
        if (!e.used) {
            if (g_fog_blocks_used >= FOG_BLOCKS * 3 / 4) break;   // (full: all forgotten, below)
            e.used = 1; e.bx = bx; e.by = by; e.z = z;
            g_fog_blocks_used++;
            fog_walk_block(e);
            return &e;
        }
        if (e.bx == bx && e.by == by && e.z == z) {
            if (g_fog_frame - e.made >= FOG_KEEP_FRAMES && (ticks_now() - t0) * g_us_per_tick < FOG_PLAN_US) fog_walk_block(e);
            return &e;
        }
    }
    // full, or too many alike in a row: everything forgotten, this one walked into the empty table
    memset(g_fog_blocks, 0, sizeof(FogBlock) * FOG_BLOCKS);
    g_fog_blocks_used = 0;
    FogBlock& e = g_fog_blocks[h & (FOG_BLOCKS - 1)];
    e.used = 1; e.bx = bx; e.by = by; e.z = z;
    g_fog_blocks_used = 1;
    fog_walk_block(e);
    return &e;
}

// THE PLAN (game thread, each frame, after the view is read): each cell's mark, copied from its
// block's.
static void plan_fog() {
    g_fog_ready = false;
    if (!B.fog_enabled || !B.have_drawn || !B.main_viewport || !B.block_index || !B.x_count_block ||
        !B.y_count_block || !B.z_count_block || !B.off_dim_x || !B.off_dim_y || !B.off_tiletype ||
        !B.off_designation || !B.flow_mask) return;
    const double t0 = ticks_now();
    if (!g_fog_blocks) {
        g_fog_blocks = (FogBlock*)calloc(FOG_BLOCKS, sizeof(FogBlock));
        if (!g_fog_blocks) return;
    }
    if (B.fog_reset != B.fog_reset_done) {   // (a start: maybe another map, its blocks numbered alike)
        memset(g_fog_blocks, 0, sizeof(FogBlock) * FOG_BLOCKS);
        g_fog_blocks_used = 0;
        B.fog_reset_done = B.fog_reset;
    }
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    const int32_t n = dx * dy;
    if (g_fog_n < n) {
        free(g_fog_mark);
        g_fog_mark = (uint8_t*)malloc((size_t)n);
        g_fog_n = g_fog_mark ? n : 0;
        if (!g_fog_n) return;
    }
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;
    g_fog_frame++;
    g_fog_walked = 0;
    uint32_t marked = 0;
    for (int32_t sx = 0; sx < dx; sx++) {
        uint8_t* mark = g_fog_mark + (size_t)sx * dy;
        const int32_t x = B.drawn_x + sx;
        if (x < 0 || x >= g_map.x_end) { memset(mark, 0, (size_t)dy); continue; }
        int32_t sy = 0;
        while (sy < dy) {   // (a run of cells in one map block at a time)
            const int32_t y = B.drawn_y + sy;
            const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
            const int32_t end = sy + run < dy ? sy + run : dy;
            const FogBlock* e = (y >= 0 && y < g_map.y_end) ? fog_block(x >> 4, y >> 4, z, t0) : nullptr;
            if (!e) { memset(mark + sy, 0, (size_t)(end - sy)); sy = end; continue; }
            const uint8_t* from = e->mark + ((x & 15) << 4);
            for (; sy < end; sy++) {
                const uint8_t m = from[(B.drawn_y + sy) & 15];
                mark[sy] = m;
                if (m) marked++;
            }
        }
    }
    g_fog_x = B.drawn_x; g_fog_y = B.drawn_y; g_fog_z = z;
    g_fog_dx = dx; g_fog_dy = dy;
    g_fog_ready = true;
    B.fog_marked_last = marked;
    B.fog_blocks_walked_last = g_fog_walked;
    B.fog_blocks_walked += g_fog_walked;
    B.fog_blocks_kept = (uint32_t)g_fog_blocks_used;
    B.fog_plans++;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.fog_plan_us_total += us;
    if (us > B.fog_plan_us_max) B.fog_plan_us_max = us;
}

// PUT BACK (game thread, before the game draws): the game's own haze back in each cell changed in
// the buffer it is about to draw into (the one changed two frames ago). The other buffer's cells
// wait for their turn, the next frame. Runs whether the fix is on or not, so turning it off leaves
// nothing of it behind.
static void fog_put_back() {
    if (!g_fog_kept_n) return;
    uint8_t* main = viewport_in(0);
    const int32_t dx = main ? *(const int32_t*)(main + B.off_dim_x) : 0;
    const int32_t dy = main ? *(const int32_t*)(main + B.off_dim_y) : 0;
    if (dx != g_fog_kept_dx || dy != g_fog_kept_dy || !B.off_interface) { g_fog_kept_n = 0; return; }   // (a zoom: new buffers, drawn afresh)
    int32_t* now[SLOTS] = {};   // each level's interface buffer the game is about to draw into
    for (int s = 1; s < SLOTS; s++) {
        uint8_t* vp = viewport_in(s);
        if (!vp) break;
        now[s] = *(int32_t* const*)(vp + B.off_interface);
    }
    int32_t w = 0;
    for (int32_t k = 0; k < g_fog_kept_n; k++) {
        const FogKept e = g_fog_kept[k];
        bool drawing = false;
        for (int s = 1; s < SLOTS && !drawing; s++) drawing = now[s] == e.arr;
        if (!drawing) { g_fog_kept[w++] = e; continue; }   // (the other buffer)
        if (e.arr[e.index] == e.ours) e.arr[e.index] = e.game;
        B.fog_put_back++;
    }
    g_fog_kept_n = w;
}

// THE FIX (main thread, in the hook, after the game has drawn)
static void fix_water_fog() {
    if (!B.fog_enabled || !g_fog_ready || !B.fog_tex_addr || !B.off_interface || !B.off_background) return;
    const double t0 = ticks_now();
    int32_t haze[FOG_HAZES];   // the game's hazes, read fresh (a reload of the textures renumbers them)
    const int32_t* src = (const int32_t*)(uintptr_t)B.fog_tex_addr;
    for (int k = 0; k < FOG_HAZES; k++) { haze[k] = src[k]; if (haze[k] <= 0) return; }
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    // (only into the view the plan was made for, at its size)
    if (dx != g_fog_dx || dy != g_fog_dy || B.drawn_x != g_fog_x || B.drawn_y != g_fog_y || B.drawn_z != g_fog_z) return;
    int32_t* iface[SLOTS] = {};
    int32_t* drawn[SLOTS][3] = {};   // each level's ground, bg2 and building_one: what the game drew on it
    int slots = 0;
    for (int s = 0; s < SLOTS; s++) {
        uint8_t* vp = viewport_in(s);
        if (!vp) break;
        if (s > 0 && !(*(const uint32_t*)(vp + B.off_flag) & 1)) break;   // (a level the game isn't showing)
        if (*(const int32_t*)(vp + B.off_dim_x) != dx || *(const int32_t*)(vp + B.off_dim_y) != dy) break;
        iface[s] = *(int32_t* const*)(vp + B.off_interface);
        if (!iface[s]) break;
        drawn[s][0] = *(int32_t* const*)(vp + B.off_background);
        drawn[s][1] = B.off_bg2 ? *(int32_t* const*)(vp + B.off_bg2) : nullptr;
        drawn[s][2] = B.off_building_one ? *(int32_t* const*)(vp + B.off_building_one) : nullptr;
        slots = s + 1;
    }
    if (slots < 3) return;   // (no level two below: nothing marked can be shown)
    const int32_t n = dx * dy;
    // THE CENSUS, when Lua asks: every haze in view, by level and which, as the game laid them (PUT
    // BACK gave back the game's own before it drew)
    if (B.fog_census_ask != B.fog_census_done) {
        memset(B.fog_census, 0, sizeof B.fog_census);
        uint32_t cells = 0, multi = 0;
        for (int32_t i = 0; i < n; i++) {
            int found = 0;
            for (int s = 0; s < slots; s++) {
                const int32_t v = iface[s][i];
                if (v <= 0) continue;
                for (int k = 0; k < FOG_HAZES; k++) if (v == haze[k]) { B.fog_census[s][k]++; found++; break; }
            }
            if (found) cells++;
            if (found > 1) multi++;
        }
        B.fog_census_cells = cells;
        B.fog_census_multi = multi;
        B.fog_census_done = B.fog_census_ask;
    }
    // the list to put back: room for two frames of a whole view, dropped at a new size (new buffers)
    if (dx != g_fog_kept_dx || dy != g_fog_kept_dy) { g_fog_kept_n = 0; g_fog_kept_dx = dx; g_fog_kept_dy = dy; }
    if (g_fog_kept_cap < 2 * n) {
        FogKept* more = (FogKept*)realloc(g_fog_kept, sizeof(FogKept) * (size_t)(2 * n));
        if (!more) return;
        g_fog_kept = more;
        g_fog_kept_cap = 2 * n;
    }
    uint32_t moved = 0, already = 0, unmatched = 0, dry = 0;
    B.fog_odd_d = 0; B.fog_odd_slot = 0; B.fog_odd_haze = -1;
    for (int32_t i = 0; i < n; i++) {
        const uint8_t m = g_fog_mark[i];
        if (!m) continue;
        const int d = m & FOG_DEPTH;   // the water's level below (2 to 8); its surface's is d - 1
        if (d < 2 || d >= slots || d > FOG_HAZES) continue;
        // over open space: the game drew the surface on that level, in its ground, bg2 or building
        // layer (zz-swap-watch found the river's ripple in all three)
        if (m & FOG_OVER_AIR) {
            int32_t* const* a = drawn[d - 1];
            if (!((a[0] && a[0][i]) || (a[1] && a[1][i]) || (a[2] && a[2][i]))) { dry++; continue; }
        }
        const int32_t water = haze[d - 1], surface = haze[d - 2];   // (ground i + 1 levels down takes haze i)
        bool changed = false, holding = false;
        for (int s = 1; s < slots; s++) {
            int32_t* p = iface[s] + i;
            if (*p == water) {
                if (g_fog_kept_n >= g_fog_kept_cap) { B.fog_kept_full++; continue; }
                g_fog_kept[g_fog_kept_n++] = {iface[s], i, water, surface};
                *p = surface;
                changed = true;
            } else if (*p == surface) holding = true;
        }
        if (changed) moved++;
        else if (holding) already++;
        else {
            unmatched++;
            if (!B.fog_odd_d) {   // (the first, for the report: which haze it held, and where)
                B.fog_odd_d = d;
                for (int s = 0; s < slots && B.fog_odd_haze < 0; s++)
                    for (int k = 0; k < FOG_HAZES; k++)
                        if (iface[s][i] == haze[k]) { B.fog_odd_slot = s; B.fog_odd_haze = k; break; }
            }
        }
    }
    B.fog_moved_last = moved;
    B.fog_already_last = already;
    B.fog_unmatched_last = unmatched;
    B.fog_dry_last = dry;
    B.fog_moved += moved;
    B.fog_frames++;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.fog_us_total += us;
    if (us > B.fog_us_max) B.fog_us_max = us;
}

// =====================================================================
// THE HOOK
// =====================================================================
// Replaces renderer::tidy_tile_cache in the renderer's vtable. Swaps the
// colour's copies (THE COLOUR), writes this frame's snow plan, then runs
// DF's own tidy_tile_cache exactly as before.
// =====================================================================
// PATHS (test 15B; paths.lua: worn paths through grass)
// =====================================================================
// Creatures wear grass down (each tile's grass amount, 0 to 100, in the
// block's grass events) and the game draws a worn tile as lush as an
// untouched one until it turns to bare soil. paths.lua drew the wear in
// between, in Lua; this is the same, worked out and drawn here:
//   * PLAN, in the prerender call (the game thread, which changes the
//     map, so events are never read mid-change): each map block's grass
//     amounts read (PAmount, kept P_KEEP_FRAMES), and from a block and its
//     eight neighbours, what each of its worn grass tiles shows (PBlock,
//     worked out again every P_REPLAN_FRAMES), within P_PLAN_US a frame.
//     A worn tile joins its LINKS most worn neighbours: the wash (a soft
//     band of soil, light wear) and over it the track (bare soil, heavier
//     wear), each as a centre and arms of so many levels, packed in a key.
//   * DRAW, in the hook (the main thread): each worn tile in view gets its
//     grass texture (as the game drew it) swapped for a painting of that
//     grass with the wash and track in, made once per (grass, key) into a
//     blank texture from the murky edges' ring and kept. Where a track runs
//     straight onto bare soil, the grass edge the game drops on that soil
//     is worn off too (its floor_flag byte cleared).
// Lua says where each grass texture's steady picture's pixels are (worn
// grass doesn't lean in the wind; a lean frame is asked about like any
// other texture), and which soil to draw (the commonest on bare soil in
// view, counted here when Lua asks).
static const int P_WORN_BELOW = 70;          // grass amount under which a tile shows a track
static const int P_WASH_BELOW = 95;          // and under which it shows the wash
static const double P_WASH_MOST = 0.75;      // the wash's opacity on grass worn right away
static const double P_WASH_HALF_WIDTH = 8;   // px: the wash's band, either side of its line
static const double P_WASH_SOFT = 5;         // px over which the band's edge fades
static const int P_WASH_LEVELS = 6;          // opacity steps
static const int P_SPREADING_BARE = 7;       // grass with this many bare neighbours is spreading, not worn
static const int P_LEVELS = 4;               // track widths
static const double P_BAKE_US = 1500;        // (15Z, PATHS HELD) new paintings each frame within this long; the rest on later frames
static const int P_HOLD_FRAMES = 120;        // (15Z, PATHS HELD) frames a tile shows its last painting while its new one waits
static const double P_HALF_WIDTH[5] = {0, 1.5, 3, 5.5, 9};   // px, per level (1 to 4)
static const double P_SOFT = 1.2;            // px over which the track's edge blends into the grass
static const double P_HALO = 3;              // px of flattened grass beside the track
static const double P_HALO_LIFT = 0.10;      // how much paler (towards straw) the flattened grass is
static const double P_STRAW[3] = {196, 182, 120};
static const int P_MOST_DEPTH = 4;           // levels below seen through open space (paths.lua: MOST_DEPTH)
static const int P_KEEP_FRAMES = 240;        // a block's grass read again after this many frames (paths.lua: BLOCK_KEEP_MS)
static const int P_REPLAN_FRAMES = 120;      // a block's worn tiles worked out again (paths.lua: REPLAN_MS)
static const double P_PLAN_US = 500;         // planning, at most this a frame (the rest next frame)
// The arms: N, E, S, W, then NE, SE, SW, NW (paths.lua: ARMS)
static const int P_ARMS[8][2] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {1, 1}, {-1, 1}, {-1, -1}};
// For a side arm onto bare soil, the soil tile's floor_flag byte (1 to 4: S, W, E, N) holding
// this grass tile's edge (paths.lua: EDGE_BYTE_FOR_ARM)
static const int P_EDGE_BYTE[4] = {1, 2, 4, 3};
static inline int p_opposite(int k) { return k < 4 ? (k + 2) % 4 : 4 + (k - 4 + 2) % 4; }

// ---- A BLOCK'S GRASS ----
static const int8_t P_NONE = -2, P_SOIL = -1;   // (else 0..100: a grass amount)
struct PAmount {
    int32_t bx, by, z;
    uint8_t used, no_block, open_any, pad;
    int64_t frame;          // when read (g_pframe)
    int8_t  a[256];         // by tile_of: grass amount, P_SOIL for bare soil, P_NONE for neither
};
static const int P_AMOUNTS = 2048;   // (a power of 2)
static PAmount* g_pamount = nullptr;
static int g_pamount_used = 0;
static int64_t g_pframe = 0;         // plans made (the prerender's frames for paths)

static inline uint32_t p_hash(int32_t bx, int32_t by, int32_t z) {
    return (uint32_t)bx * 73856093u ^ (uint32_t)by * 19349663u ^ (uint32_t)z * 83492791u;
}
static void p_amount_read(PAmount& e) {
    memset(e.a, P_NONE, sizeof e.a);
    e.open_any = 0;
    e.frame = g_pframe;
    const uint8_t* blk = block_ptr(e.bx, e.by, e.z);
    e.no_block = blk ? 0 : 1;
    if (!blk) return;
    // the most any grass event has on each tile (paths.lua: read_block)
    uint8_t most[256];
    memset(most, 0, sizeof most);
    void* const* first;
    void* const* last;
    if (B.grass_vtable && events_of(blk, first, last)) {
        for (void* const* p = first; p < last; p++) {
            const uint8_t* ev = (const uint8_t*)*p;
            if (!ev || *(const uint64_t*)ev != B.grass_vtable) continue;
            const uint8_t* amount = ev + B.off_gev_amount;
            for (int i = 0; i < 256; i++) if (amount[i] > most[i]) most[i] = amount[i];
        }
    }
    const uint16_t* types = (const uint16_t*)(blk + B.off_tiletype);
    const uint32_t* des = (const uint32_t*)(blk + B.off_designation);
    for (int i = 0; i < 256; i++) {
        const uint16_t tt = types[i];
        if (flags_of(tt) & TT_OPEN) e.open_any = 1;
        const uint8_t kind = tt < TT_TABLE ? B.paths_kind[tt] : 0;
        if (!kind || !(des[i] & B.outside_mask)) continue;
        e.a[i] = kind == 1 ? (int8_t)(most[i] > 100 ? 100 : most[i]) : P_SOIL;
    }
}
// A block's grass, read now if it isn't kept or is old (nullptr: off the map or the list full).
static PAmount* p_amount(int32_t bx, int32_t by, int32_t z) {
    if (bx < 0 || by < 0 || z < 0 || bx >= g_map.bxn || by >= g_map.byn || z >= g_map.zn) return nullptr;
    if (!g_pamount) {
        g_pamount = (PAmount*)calloc(P_AMOUNTS, sizeof(PAmount));
        if (!g_pamount) return nullptr;
    }
    uint32_t h = p_hash(bx, by, z) & (P_AMOUNTS - 1);
    for (int probe = 0; probe < P_AMOUNTS; probe++, h = (h + 1) & (P_AMOUNTS - 1)) {
        PAmount& e = g_pamount[h];
        if (e.used && e.bx == bx && e.by == by && e.z == z) {
            if (g_pframe - e.frame >= P_KEEP_FRAMES) p_amount_read(e);
            return e.no_block ? nullptr : &e;
        }
        if (e.used) continue;
        if (g_pamount_used >= P_AMOUNTS * 3 / 4) return nullptr;   // (forgotten whole at the next plan)
        e.used = 1; e.bx = bx; e.by = by; e.z = z;
        g_pamount_used++;
        p_amount_read(e);
        return e.no_block ? nullptr : &e;
    }
    return nullptr;
}
// The same, only if kept (the hook reads, never reads the map's events).
static const PAmount* p_amount_kept(int32_t bx, int32_t by, int32_t z) {
    if (!g_pamount || bx < 0 || by < 0 || z < 0) return nullptr;
    uint32_t h = p_hash(bx, by, z) & (P_AMOUNTS - 1);
    for (int probe = 0; probe < P_AMOUNTS; probe++, h = (h + 1) & (P_AMOUNTS - 1)) {
        const PAmount& e = g_pamount[h];
        if (!e.used) return nullptr;
        if (e.bx == bx && e.by == by && e.z == z) return e.no_block ? nullptr : &e;
    }
    return nullptr;
}

// ---- A BLOCK'S WORN TILES ----
// edges: bit k, a worn edge onto side k. (15Z, PATHS HELD) held: the painting last drawn on the tile; held_age:
// frames in a row it's stood in for a new one that couldn't be made.
struct PCell { uint8_t tile; uint8_t edges; uint8_t held_age; uint8_t pad; int32_t held; uint64_t key; };
struct PBlock {
    int32_t bx, by, z;
    int32_t n;              // worn tiles
    int64_t frame;          // when worked out
    PCell*  cells;          // n of them (malloc'd; nullptr when none)
    uint8_t used, pad[7];
};
static const int P_BLOCKS = 2048;    // (a power of 2)
static PBlock* g_pblock = nullptr;
static int g_pblock_used = 0;

static void p_free_plans() {
    if (g_pblock) for (int i = 0; i < P_BLOCKS; i++) free(g_pblock[i].cells);
    free(g_pblock); g_pblock = nullptr; g_pblock_used = 0;
    free(g_pamount); g_pamount = nullptr; g_pamount_used = 0;
}
static const PBlock* p_block_kept(int32_t bx, int32_t by, int32_t z) {
    if (!g_pblock || bx < 0 || by < 0 || z < 0) return nullptr;
    uint32_t h = p_hash(bx, by, z) & (P_BLOCKS - 1);
    for (int probe = 0; probe < P_BLOCKS; probe++, h = (h + 1) & (P_BLOCKS - 1)) {
        const PBlock& e = g_pblock[h];
        if (!e.used) return nullptr;
        if (e.bx == bx && e.by == by && e.z == z) return &e;
    }
    return nullptr;
}

// 0..1 on grass worn below the threshold, 1 on bare soil, -1 for neither (paths.lua: wear)
static inline double p_wear(const int16_t* g, int n, int threshold) {
    const int a = g[n];
    if (a == P_NONE) return -1;
    if (a < 0) return 1;
    return a < threshold ? (double)(threshold - a) / threshold : -1;
}
static inline int p_level(double wear, int levels) {   // paths.lua: level_in
    int v = (int)ceil(wear * levels);
    return v < 1 ? 1 : v > levels ? levels : v;
}
static const int P_W = 20;   // the region: the block and two tiles round it, column by column
static int p_step(int k) { return P_ARMS[k][0] * P_W + P_ARMS[k][1]; }

// The links each worn grass tile chooses (paths.lua: links_for): its two most worn neighbours,
// sides before corners on a tie, a corner only where the two sides beside it aren't both worn;
// drawn from both sides. links[n]: bit k for arm k.
static void p_links(const int16_t* g, int threshold, uint8_t* links) {
    memset(links, 0, P_W * P_W);
    for (int i = 1; i < P_W - 1; i++) {
        for (int j = 1; j < P_W - 1; j++) {
            const int n = i * P_W + j;
            const int a = g[n];
            if (a == P_NONE || a < 0 || a >= threshold) continue;
            int best = -1, second = -1;
            double best_w = -1, second_w = -1;
            for (int k = 0; k < 8; k++) {
                double nw = p_wear(g, n + p_step(k), threshold);
                bool ok = nw >= 0;
                if (ok && k >= 4) {
                    if (p_wear(g, n + P_ARMS[k][0] * P_W, threshold) >= 0 && p_wear(g, n + P_ARMS[k][1], threshold) >= 0) ok = false;
                    else nw -= 0.01;
                }
                if (!ok) continue;
                if (nw > best_w) { second = best; second_w = best_w; best = k; best_w = nw; }
                else if (nw > second_w) { second = k; second_w = nw; }
            }
            const int pick[2] = {best, second};
            for (int m = 0; m < 2; m++) {
                const int k = pick[m];
                if (k < 0) break;
                links[n] |= (uint8_t)(1 << k);
                links[n + p_step(k)] |= (uint8_t)(1 << p_opposite(k));
            }
        }
    }
}

// The worn tiles of a block from its region's grass, g (paths.lua: block_entries): into found,
// how many.
static int p_entries(const int16_t* g, PCell* found) {
    uint8_t track_links[P_W * P_W], wash_links[P_W * P_W];
    p_links(g, P_WORN_BELOW, track_links);
    p_links(g, P_WASH_BELOW, wash_links);
    int n_found = 0;
    for (int i = 2; i < 18; i++) {
        for (int j = 2; j < 18; j++) {
            const int n = i * P_W + j;
            const int a = g[n];
            if (a == P_NONE || a < 0 || a >= P_WASH_BELOW) continue;
            // grass mostly ringed by bare soil is spreading onto it, not worn
            int bare = 0;
            for (int k = 0; k < 8; k++) if (g[n + p_step(k)] == P_SOIL) bare++;
            if (bare >= P_SPREADING_BARE) continue;
            const double ww = (double)(P_WASH_BELOW - a) / P_WASH_BELOW;
            uint64_t key = (uint64_t)p_level(ww, P_WASH_LEVELS);
            for (int k = 0; k < 8; k++) {
                const double nw = (wash_links[n] & (1 << k)) ? p_wear(g, n + p_step(k), P_WASH_BELOW) : -1;
                const int arm = nw >= 0 ? p_level(ww < nw ? ww : nw, P_WASH_LEVELS) : 0;
                key |= (uint64_t)arm << (3 + 3 * k);
            }
            uint8_t edges = 0;
            if (a < P_WORN_BELOW) {
                const double tw = (double)(P_WORN_BELOW - a) / P_WORN_BELOW;
                key |= 1ull << 27;
                key |= (uint64_t)p_level(tw, P_LEVELS) << 28;
                for (int k = 0; k < 8; k++) {
                    const double nw = (track_links[n] & (1 << k)) ? p_wear(g, n + p_step(k), P_WORN_BELOW) : -1;
                    const int arm = nw >= 0 ? p_level(tw < nw ? tw : nw, P_LEVELS) : 0;
                    key |= (uint64_t)arm << (31 + 3 * k);
                    // where the track runs straight onto bare soil, that soil's edge from here is worn off
                    if (k < 4 && arm > 0 && g[n + p_step(k)] == P_SOIL) edges |= (uint8_t)(1 << k);
                }
            }
            PCell& c = found[n_found++];
            c.tile = (uint8_t)(((i - 2) << 4) | (j - 2));
            c.edges = edges;
            c.held_age = 0; c.pad = 0; c.held = 0;
            c.key = key;
        }
    }
    return n_found;
}
// Works out block (bx, by, z)'s worn tiles into e: its region's grass, two tiles round it.
static void p_block_work(PBlock& e) {
    int16_t g[P_W * P_W];
    for (int i = 0; i < P_W; i++) {
        const int32_t x = e.bx * 16 - 2 + i;
        for (int j = 0; j < P_W; j++) {
            const int32_t y = e.by * 16 - 2 + j;
            const PAmount* pa = (x >= 0 && y >= 0) ? p_amount(x >> 4, y >> 4, e.z) : nullptr;
            g[i * P_W + j] = pa ? pa->a[tile_of(x, y)] : P_NONE;
        }
    }
    PCell found[256];
    const int n_found = p_entries(g, found);
    // (PATHS HELD, 15Z) a tile still worn the same way keeps the painting last drawn on it
    if (e.cells && e.n > 0) {
        int32_t held[256]; uint8_t age[256]; uint64_t key[256]; uint8_t had[256];
        memset(had, 0, sizeof had);
        for (int c = 0; c < e.n; c++) {
            const PCell& o = e.cells[c];
            had[o.tile] = 1; held[o.tile] = o.held; age[o.tile] = o.held_age; key[o.tile] = o.key;
        }
        for (int c = 0; c < n_found; c++) {
            PCell& f = found[c];
            if (had[f.tile] && key[f.tile] == f.key) { f.held = held[f.tile]; f.held_age = age[f.tile]; }
        }
    }
    free(e.cells);
    e.cells = nullptr;
    e.n = n_found;
    if (n_found) {
        e.cells = (PCell*)malloc(sizeof(PCell) * (size_t)n_found);
        if (e.cells) memcpy(e.cells, found, sizeof(PCell) * (size_t)n_found);
        else e.n = 0;
    }
    e.frame = g_pframe;
    B.paths_blocks_total++;
}
// The block's entry, made if new (nullptr: the list full); fresh is set when it's worked out.
static PBlock* p_block(int32_t bx, int32_t by, int32_t z) {
    if (!g_pblock) {
        g_pblock = (PBlock*)calloc(P_BLOCKS, sizeof(PBlock));
        if (!g_pblock) return nullptr;
    }
    uint32_t h = p_hash(bx, by, z) & (P_BLOCKS - 1);
    for (int probe = 0; probe < P_BLOCKS; probe++, h = (h + 1) & (P_BLOCKS - 1)) {
        PBlock& e = g_pblock[h];
        if (e.used && e.bx == bx && e.by == by && e.z == z) return &e;
        if (e.used) continue;
        if (g_pblock_used >= P_BLOCKS * 3 / 4) return nullptr;
        e.used = 1; e.bx = bx; e.by = by; e.z = z; e.n = 0; e.cells = nullptr; e.frame = INT64_MIN / 2;
        g_pblock_used++;
        return &e;
    }
    return nullptr;
}

static bool p_map_ready() {
    if (!B.block_index || !B.x_count_block || !B.y_count_block || !B.z_count_block || !B.off_tiletype || !B.off_designation) return false;
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return false;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    return true;
}

// PLAN, every prerender: the view's blocks on each level worked out, new ones first, then old ones.
static void plan_paths() {
    if (B.paths_plan_reset != B.paths_plan_reset_done) {
        p_free_plans();
        B.paths_plan_reset_done = B.paths_plan_reset;
    }
    if (!B.paths_enabled || !B.have_drawn || !B.main_viewport || !B.off_dim_x || !B.off_dim_y || !p_map_ready()) return;
    // (the lists full: forgotten whole and worked out again)
    if (g_pamount_used >= P_AMOUNTS * 3 / 4 || g_pblock_used >= P_BLOCKS * 3 / 4) p_free_plans();
    const double t0 = ticks_now();
    g_pframe++;
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    const int32_t bx1 = (B.drawn_x < 0 ? 0 : B.drawn_x) >> 4, by1 = (B.drawn_y < 0 ? 0 : B.drawn_y) >> 4;
    const int32_t bx2 = (B.drawn_x + dx - 1) >> 4, by2 = (B.drawn_y + dy - 1) >> 4;
    const int depths = (int)(B.paths_depths < (uint32_t)P_MOST_DEPTH ? B.paths_depths : P_MOST_DEPTH);
    uint32_t worked = 0, known = 0;
    bool out_of_time = false;
    for (int pass = 0; pass < 2 && !out_of_time; pass++) {   // (pass 0: blocks never worked out; 1: old ones)
        for (int d = 0; d <= depths && !out_of_time; d++) {
            const int32_t z = B.drawn_z - d;
            if (z < 0 || z >= g_map.zn) break;
            for (int32_t bx = bx1; bx <= bx2 && !out_of_time; bx++) {
                for (int32_t by = by1; by <= by2; by++) {
                    if (bx >= g_map.bxn || by >= g_map.byn) continue;
                    // a level below shows only through open tiles on the level above it
                    if (d > 0) {
                        const PAmount* above = p_amount(bx, by, z + 1);
                        if (!above || !above->open_any) continue;
                    }
                    PBlock* e = p_block(bx, by, z);
                    if (!e) continue;
                    const bool never = e->frame < 0;
                    if (pass == 1 && known < 0xffffffffu) known += (uint32_t)e->n;
                    if (pass == 0 ? !never : (g_pframe - e->frame < P_REPLAN_FRAMES)) continue;
                    if ((ticks_now() - t0) * g_us_per_tick >= P_PLAN_US) { out_of_time = true; break; }
                    p_block_work(*e);
                    worked++;
                }
            }
        }
    }
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.paths_plans++;
    B.paths_blocks_last = worked;
    if (!out_of_time) B.paths_known = known;
    B.paths_plan_us_total += us;
    if (us > B.paths_plan_us_max) B.paths_plan_us_max = us;
}

// ---- THE STEADY PICTURES' PIXELS (Lua's answers) ----
struct PBase { int32_t tex; uint8_t state; uint8_t pad[3]; uint64_t addr; };   // state 1: asked, 2: answered
static const int P_BASES = 4096;   // (a power of 2)
static PBase g_pbase[P_BASES];
static int g_pbase_used = 0;
static PBase* p_base_slot(int32_t t, bool make) {
    uint32_t h = ((uint32_t)t * 2654435761u) & (P_BASES - 1);
    for (int probe = 0; probe < 64; probe++, h = (h + 1) & (P_BASES - 1)) {
        PBase& e = g_pbase[h];
        if (e.state && e.tex == t) return &e;
        if (e.state) continue;
        if (!make) return nullptr;
        if (g_pbase_used >= P_BASES * 3 / 4) {
            // (15Z) full: started over. It was never emptied: once full (each look's grass and lean frames
            // are new numbers) every new grass picture was left undrawn for good. Those still showing are
            // asked about again, their tiles held meanwhile.
            memset(g_pbase, 0, sizeof g_pbase); g_pbase_used = 0;
            B.paths_bases_dropped++;
            PBase& f = g_pbase[((uint32_t)t * 2654435761u) & (P_BASES - 1)];
            f.tex = t; f.state = 0; f.addr = 0;
            return &f;
        }
        e.tex = t; e.state = 0; e.addr = 0;
        return &e;
    }
    return nullptr;
}
// The steady pixels under texture t, or 0 (asked about, not answered yet, or nothing drawn on it).
static uint64_t p_base_addr(int32_t t) {
    PBase* e = p_base_slot(t, true);
    if (!e) return 0;
    if (e->state == 2) return e->addr;
    if (e->state == 0) {
        const uint32_t head = B.paths_q_head;
        if (head - B.paths_q_tail >= 256u) { B.paths_q_full++; return 0; }
        B.paths_q[head % 256] = t;
        B.paths_q_head = head + 1;
        e->state = 1;
        g_pbase_used++;
    }
    return 0;
}

// ---- THE PAINTINGS ----
// (15Z) Kept in two halves: new ones go in the newer; once it's 3/4 full it becomes the older and a new
// one starts, and a painting found in the older half is filed again in the newer. It was one list
// emptied whenever full, so every worn tile on screen was painted again at once, each into a new blank.
struct PBake { uint64_t addr, key; int32_t tex; uint8_t used; uint8_t pad[3]; };
static const int P_BAKES = 4096;   // each half (a power of 2)
static PBake g_pbake_a[P_BAKES], g_pbake_b[P_BAKES];
static PBake* g_pbake = g_pbake_a;         // the newer half
static PBake* g_pbake_older = g_pbake_b;   // the half before
static int g_pbake_used = 0;
enum { P_MADE = 0, P_ASKING = 1, P_NO_BLANK = 2, P_OVER_TIME = 3, P_UNREADABLE = 4 };   // why a painting isn't there

// How far pixel (x, y) is from arm a's line (paths.lua: from_arm).
static double p_from_arm(int a, double x, double y) {
    const double M = 15.5;
    const double dx = P_ARMS[a][0] * (M + 0.5), dy = P_ARMS[a][1] * (M + 0.5);
    double t = ((x - M) * dx + (y - M) * dy) / (dx * dx + dy * dy);
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    const double ex = x - M - t * dx, ey = y - M - t * dy;
    return sqrt(ex * ex + ey * ey);
}
static inline double p_clamp01(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
static inline double p_band(double d) { return p_clamp01((P_WASH_HALF_WIDTH - d) / P_WASH_SOFT + 0.5); }

// The grass with the wash, then the track's halo and soil, painted in (paths.lua: bake, with
// track_mask and wash_mask worked out per pixel).
static void p_paint(const uint32_t* gp, const uint32_t* sp, uint64_t key, uint32_t* out) {
    const int wc = (int)(key & 7);
    int wa[8], ta[8];
    for (int k = 0; k < 8; k++) { wa[k] = (int)((key >> (3 + 3 * k)) & 7); ta[k] = (int)((key >> (31 + 3 * k)) & 7); }
    const bool track = (key >> 27) & 1;
    const int tc = (int)((key >> 28) & 7);
    const double wk = P_WASH_MOST / P_WASH_LEVELS;
    const double M = 15.5;
    for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
            const double r0 = sqrt((x - M) * (x - M) + (y - M) * (y - M));
            double arm_d[8];
            for (int k = 0; k < 8; k++) arm_d[k] = (wa[k] || (track && ta[k])) ? p_from_arm(k, x, y) : 0;
            // the wash: soil opacity
            double o = wc * p_band(r0);
            for (int k = 0; k < 8; k++) if (wa[k] > 0) { const double v = wa[k] * p_band(arm_d[k]); if (v > o) o = v; }
            const double w = o * wk;
            const int n = y * 32 + x;
            const uint32_t gpx = gp[n], spx = sp[n];
            const double sr = spx & 0xff, sg = (spx >> 8) & 0xff, sb = (spx >> 16) & 0xff;
            double r = gpx & 0xff, gr = (gpx >> 8) & 0xff, b = (gpx >> 16) & 0xff;
            if (w > 0) { r += (sr - r) * w; gr += (sg - gr) * w; b += (sb - b) * w; }
            if (track) {
                double inside = P_HALF_WIDTH[tc] - r0;
                for (int k = 0; k < 8; k++) if (ta[k] > 0) { const double v = P_HALF_WIDTH[ta[k]] - arm_d[k]; if (v > inside) inside = v; }
                const double cover = p_clamp01(inside / P_SOFT + 0.5);
                const double h = p_clamp01((inside + P_HALO) / P_HALO) * P_HALO_LIFT;
                r += (P_STRAW[0] - r) * h; gr += (P_STRAW[1] - gr) * h; b += (P_STRAW[2] - b) * h;
                r += (sr - r) * cover; gr += (sg - gr) * cover; b += (sb - b) * cover;
            }
            out[n] = (gpx & 0xff000000u) | (channel(b) << 16) | (channel(gr) << 8) | channel(r);
        }
    }
}
// A painting by its grass pixels and key in one half, or nullptr; `empty`, if given, gets the first free
// slot met on the way (nullptr if none within the probes).
static PBake* p_bake_in(PBake* tab, uint64_t addr, uint64_t key, uint64_t h, PBake** empty) {
    for (int probe = 0; probe < 32; probe++) {
        PBake& e = tab[(h + probe) & (P_BAKES - 1)];
        if (e.used && e.addr == addr && e.key == key) return &e;
        if (!e.used) { if (empty) *empty = &e; return nullptr; }
    }
    return nullptr;
}
// The painting of grass pixels addr with key: kept, or made now into the next blank of the murky edges'
// ring while the frame's painting time (deadline, in ticks) lasts. 0 when it can't be this frame (why).
static int32_t p_bake(uint64_t addr, uint64_t key, double deadline, int& why) {
    const uint64_t h = (addr * 0x9E3779B97F4A7C15ull) ^ (key * 0xC2B2AE3D27D4EB4Full);
    PBake* empty = nullptr;
    if (PBake* e = p_bake_in(g_pbake, addr, key, h, &empty)) return e->tex;
    const PBake* old = p_bake_in(g_pbake_older, addr, key, h, nullptr);
    int32_t tex = old ? old->tex : 0;
    if (!tex) {
        // new: painted into the next blank, if the frame's painting time isn't used up
        if (ticks_now() >= deadline) { why = P_OVER_TIME; return 0; }
        if (B.murky_blank_tail == B.murky_blank_head) { why = P_NO_BLANK; return 0; }
        const uint32_t slot = B.murky_blank_tail % 256;
        const int32_t btex = B.murky_blank_tex[slot];
        uint32_t* dst = (uint32_t*)(uintptr_t)B.murky_blank_addr[slot];
        if (!btex || !dst || !readable_span(dst, 4096)) { B.murky_blank_tail++; why = P_NO_BLANK; return 0; }   // (a blank of no use: passed over)
        const uint32_t* gp = (const uint32_t*)(uintptr_t)addr;
        const uint32_t* sp = (const uint32_t*)(uintptr_t)B.paths_soil_addr;
        if (!readable_span(gp, 4096) || !readable_span(sp, 4096)) { why = P_UNREADABLE; return 0; }
        B.murky_blank_tail++;
        p_paint(gp, sp, key, dst);
        tex = btex;
        mark(tex, TEX_OURS);                                     // (left be where it's still showing)
        if (tex > 0 && tex < TEX_MAP) g_cflag[tex] = CF_LEAVE;   // (never swapped by THE COLOUR)
        B.paths_baked++;
    }
    // filed in the newer half (from the older, or new); that half full, or crowded where this goes: it
    // becomes the older (`old` is read above, before its half is let go)
    if (!empty || g_pbake_used >= P_BAKES * 3 / 4) {
        PBake* t = g_pbake_older; g_pbake_older = g_pbake; g_pbake = t;
        memset(g_pbake, 0, sizeof(PBake) * P_BAKES);
        g_pbake_used = 0;
        B.paths_bakes_halved++;
        empty = &g_pbake[h & (P_BAKES - 1)];
    }
    empty->addr = addr; empty->key = key; empty->tex = tex; empty->used = 1;
    g_pbake_used++;
    return tex;
}

// Whether every level from the view's down to z + 1 is open at (x, y): level z shows there.
static bool p_shows(int32_t x, int32_t y, int32_t z) {
    for (int32_t zz = B.drawn_z; zz > z; zz--) {
        const uint8_t* blk = block_ptr(x >> 4, y >> 4, zz);
        if (!blk || !(flags_of(((const uint16_t*)(blk + B.off_tiletype))[tile_of(x, y)]) & TT_OPEN)) return false;
    }
    return true;
}

// The bare soil in view counted, when Lua asks: its four commonest textures.
static void p_count_soil(uint8_t* main, int32_t dx, int32_t dy) {
    int32_t tex[64]; uint32_t cnt[64];
    memset(tex, 0, sizeof tex); memset(cnt, 0, sizeof cnt);
    const int32_t* bg = *(int32_t* const*)(main + B.off_background);
    const int32_t black = B.black_texpos;
    if (bg) {
        for (int32_t sx = 0; sx < dx; sx++) {
            const int32_t x = B.drawn_x + sx;
            if (x < 0 || x >= g_map.x_end) continue;
            for (int32_t sy = 0; sy < dy; sy++) {
                const int32_t y = B.drawn_y + sy;
                if (y < 0 || y >= g_map.y_end) continue;
                const PAmount* pa = p_amount_kept(x >> 4, y >> 4, B.drawn_z);
                if (!pa || pa->a[tile_of(x, y)] != P_SOIL) continue;
                const int32_t t = bg[sx * dy + sy];
                if (t <= 0 || t == black || is_ours(t)) continue;
                uint32_t h = ((uint32_t)t * 2654435761u) & 63;
                for (int probe = 0; probe < 64; probe++, h = (h + 1) & 63) {
                    if (tex[h] == t) { cnt[h]++; break; }
                    if (!tex[h]) { tex[h] = t; cnt[h] = 1; break; }
                }
            }
        }
    }
    for (int k = 0; k < 4; k++) {
        int best = -1;
        for (int m = 0; m < 64; m++) if (tex[m] && (best < 0 || cnt[m] > cnt[best])) best = m;
        B.paths_soil_seen[k] = best >= 0 ? tex[best] : 0;
        if (best >= 0) tex[best] = 0;
    }
}

// DRAW, in the hook: the worn tiles in view, on each level, swapped for their paintings.
static void draw_paths() {
    if (!B.paths_enabled || !B.have_drawn || !B.main_viewport || !B.off_dim_x || !B.off_dim_y || !B.off_background || !p_map_ready()) return;
    const double t0 = ticks_now();
    // what Lua asks to have forgotten: a new soil, or colour's copies let go
    if (B.paths_reset != B.paths_reset_done) {
        memset(g_pbase, 0, sizeof g_pbase); g_pbase_used = 0;
        memset(g_pbake_a, 0, sizeof g_pbake_a); memset(g_pbake_b, 0, sizeof g_pbake_b); g_pbake_used = 0;   // (tiles keep their held paintings meanwhile)
        B.paths_q_tail = B.paths_q_head;   // (questions asked before are answered for the old pictures)
        B.paths_a_tail = B.paths_a_head;
        B.paths_reset_done = B.paths_reset;
    }
    // Lua's answers
    while (B.paths_a_tail != B.paths_a_head) {
        const PathAnswer& a = B.paths_a[B.paths_a_tail % 256];
        PBase* e = p_base_slot(a.texpos, false);
        if (e && e->state == 1) { e->state = 2; e->addr = a.addr; }
        B.paths_a_tail++;
    }
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    if (B.paths_soil_ask != B.paths_soil_done) {
        p_count_soil(main, dx, dy);
        B.paths_soil_done = B.paths_soil_ask;
    }
    uint32_t drawn = 0, held_now = 0;
    const double deadline = t0 + P_BAKE_US / (g_us_per_tick > 0 ? g_us_per_tick : 1);   // (PATHS HELD: new paintings until then)
    if (B.paths_soil_addr) {
        const int depths = (int)(B.paths_depths < (uint32_t)P_MOST_DEPTH ? B.paths_depths : P_MOST_DEPTH);
        const int32_t black = B.black_texpos;
        const int32_t bx1 = (B.drawn_x < 0 ? 0 : B.drawn_x) >> 4, by1 = (B.drawn_y < 0 ? 0 : B.drawn_y) >> 4;
        const int32_t bx2 = (B.drawn_x + dx - 1) >> 4, by2 = (B.drawn_y + dy - 1) >> 4;
        for (int d = 0; d <= depths; d++) {
            uint8_t* vp = viewport_in(d);
            if (!vp) break;
            if (d > 0 && !(*(const uint32_t*)(vp + B.off_flag) & 1)) break;   // a level below DF isn't showing
            if (*(const int32_t*)(vp + B.off_dim_x) != dx || *(const int32_t*)(vp + B.off_dim_y) != dy) break;
            int32_t* bg = *(int32_t* const*)(vp + B.off_background);
            uint64_t* ff = B.off_floor_flag ? *(uint64_t* const*)(vp + B.off_floor_flag) : nullptr;
            if (!bg) break;
            const int32_t z = B.drawn_z - d;
            if (z < 0 || z >= g_map.zn) break;
            for (int32_t bx = bx1; bx <= bx2; bx++) {
                for (int32_t by = by1; by <= by2; by++) {
                    PBlock* e = (PBlock*)p_block_kept(bx, by, z);   // (PATHS HELD writes each tile's painting back)
                    if (!e || !e->n || !e->cells) continue;
                    for (int c = 0; c < e->n; c++) {
                        PCell& cell = e->cells[c];
                        const int32_t x = bx * 16 + (cell.tile >> 4), y = by * 16 + (cell.tile & 15);
                        const int32_t sx = x - B.drawn_x, sy = y - B.drawn_y;
                        if (sx < 0 || sy < 0 || sx >= dx || sy >= dy) continue;
                        if (d > 0 && !p_shows(x, y, z)) continue;
                        // grass edges worn off where the track runs onto bare soil
                        if (cell.edges && ff) {
                            for (int k = 0; k < 4; k++) {
                                if (!(cell.edges & (1 << k))) continue;
                                const int32_t ex = sx + P_ARMS[k][0], ey = sy + P_ARMS[k][1];
                                if (ex < 0 || ey < 0 || ex >= dx || ey >= dy) continue;
                                if (d > 0 && !p_shows(x + P_ARMS[k][0], y + P_ARMS[k][1], z)) continue;
                                const uint64_t mask = 0xffull << (8 * (P_EDGE_BYTE[k] - 1));
                                uint64_t& f = ff[ex * dy + ey];
                                if (f & mask) f &= ~mask;
                            }
                        }
                        const int32_t i = sx * dy + sy;
                        const int32_t t = bg[i];
                        if (t <= 0 || t == black || is_ours(t)) continue;   // (nothing, not drawn yet, or ours already)
                        // (PATHS HELD, 15Z) this frame's painting, or else the one last drawn on the tile
                        int why = P_ASKING;
                        const uint64_t addr = p_base_addr(t);
                        const int32_t tex = addr ? p_bake(addr, cell.key, deadline, why) : 0;
                        if (tex > 0) { bg[i] = tex; drawn++; cell.held = tex; cell.held_age = 0; continue; }
                        if (why == P_OVER_TIME) B.paths_put_off++;
                        else if (why == P_NO_BLANK) B.paths_no_blank++;
                        if (cell.held > 0 && cell.held_age < P_HOLD_FRAMES) { bg[i] = cell.held; cell.held_age++; held_now++; continue; }
                        B.paths_waits++;   // (left as the game drew it: nothing painted on this tile yet)
                    }
                }
            }
        }
    }
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.paths_frames++;
    B.paths_cells_last = drawn;
    B.paths_held += held_now;
    B.paths_held_last = held_now;
    B.paths_draw_us_total += us;
    if (us > B.paths_draw_us_max) B.paths_draw_us_max = us;
}

// =====================================================================
// THE GRASS WAVE DRAWN HERE (test 16A): colour.lua's gusts sweeping across the grass
// =====================================================================
// colour.lua (Gusts sweeping across the grass): the tables lean every tile of a grass together, so on
// its own the whole field bends at once. On screen each grass tile in the main view's ground layer gets
// the lean the gust had a moment earlier or later instead, by how far downwind it is, so a gust runs
// across the field with the wind; and in wind strong enough its rustle frame, by its place downwind.
// The tables keep the lean at the middle of the view. Each tile here, as grass_wave does:
//   * which grass picture and lean it shows as the game drew it (the map, made from the slots: each
//     original's copy, step 0, and its lean frames, steps 1 to 10);
//   * d, its distance downwind from the view's upwind edge, in whole tiles; the lean the gusts had
//     d / WAVE_TILES_PER_S seconds back (lean_history as Lua keeps it: the last 5 seconds), as a step;
//   * while the rustle plays, the frame of its loop by its place downwind, from the lean frame of the
//     nearest even step: drawn if made, else asked of Lua (made as a PJ_RUSTLE job, in a later frame);
//   * else, if the step differs from what the game drew, that step's lean frame (step 0: the copy).
// The game rebuilds the ground layer every frame, so nothing is put back. Drawn after the colour's
// swaps (underground the game's own is back there, which isn't in the map) and before everything that
// reads the ground layer (the cracks, the snow, the paths, the spatter), as Lua drew it before them.
static const int WAVE_SLOTS = 1024;          // grass originals with lean frames, at most
static const int WAVE_STEPS = 11;            // a slot's frames by lean step: 0 the look's copy, 1 to 10 (colour.lua: LEAN_STEPS)
static const int WAVE_EVENS = 6;             // the rustle's frames by even lean step: 0, 2 .. 10
static const int WAVE_PHASES = 16;           // and by phase of its loop (colour.lua: RUSTLE_PHASES)
static const double WAVE_TILES_PER_S = 9;    // (colour.lua) how fast a gust crosses the field
static const double WAVE_HISTORY_S = 5;      // (colour.lua: LEAN_HISTORY_S) the gusts' lean kept, in seconds
static const int WAVE_PHASES_PER_TILE = 4;   // (colour.lua) the waves run downwind a tile every this many frames of the loop
static const int WAVE_HIST = 2048;           // the history's ring (wave_hist)
static const int WAVE_WANT_RING = 256;       // the wanted ring (wave_want)
// A slot (Lua writes it): rustle 0 not made, -1 none to be had, -2 asked of Lua.
struct WaveSlot { int32_t lean[WAVE_STEPS]; int32_t rustle[WAVE_EVENS][WAVE_PHASES]; };
static_assert(sizeof(WaveSlot) == 107 * 4, "WaveSlot: colour.lua's WAVE_SLOT_INTS");
static WaveSlot g_wave_slots[WAVE_SLOTS];
struct WaveTex { int32_t tex; uint16_t slot; uint8_t step; uint8_t used; };
static const int WAVE_MAP = 16384;           // (a power of 2)
static WaveTex g_wave_map[WAVE_MAP];
static int g_wave_map_n = 0;
static uint32_t g_wave_built = 0;            // the wave_built the map was made for
static const int WAVE_MOST_D = 4096;
static int32_t g_wave_step_at[WAVE_MOST_D];  // this frame's lean step at each distance downwind

static inline uint32_t wave_hash(int32_t t) { return ((uint32_t)t * 2654435761u) & (WAVE_MAP - 1); }
static const WaveTex* wave_find(int32_t t) {
    uint32_t h = wave_hash(t);
    for (int k = 0; k < 64; k++, h = (h + 1) & (WAVE_MAP - 1)) {
        const WaveTex& e = g_wave_map[h];
        if (!e.used) return nullptr;
        if (e.tex == t) return &e;
    }
    return nullptr;
}
// The map made again from the slots: each lean frame (and copy) by its texture.
static void wave_make_map() {
    memset(g_wave_map, 0, sizeof g_wave_map);
    g_wave_map_n = 0;
    const int n = B.wave_slot_n < (uint32_t)WAVE_SLOTS ? (int)B.wave_slot_n : WAVE_SLOTS;
    for (int s = 0; s < n; s++) {
        for (int step = 0; step < WAVE_STEPS; step++) {
            const int32_t t = g_wave_slots[s].lean[step];
            if (t <= 0) continue;
            if (g_wave_map_n >= WAVE_MAP * 3 / 4) { B.wave_map_full++; continue; }
            uint32_t h = wave_hash(t);
            for (int k = 0; k < 64; k++, h = (h + 1) & (WAVE_MAP - 1)) {
                WaveTex& e = g_wave_map[h];
                if (e.used && e.tex == t) break;   // (the first slot it's in keeps it, as Lua's step_of)
                if (!e.used) { e.tex = t; e.slot = (uint16_t)s; e.step = (uint8_t)step; e.used = 1; g_wave_map_n++; break; }
            }
        }
    }
}
// (colour.lua: lean_ago, for each distance) the lean step at distances 0 to dmax, in one pass back through
// the history: entries within the last WAVE_HISTORY_S seconds of the clock, as Lua keeps them; at each
// distance the newest no later than the clock less d / WAVE_TILES_PER_S, else the oldest kept, else 0.
static void wave_steps(int32_t dmax) {
    const double now = B.wave_clock;
    const uint32_t head = B.wave_hist_head;
    const uint32_t have = head < (uint32_t)WAVE_HIST ? head : (uint32_t)WAVE_HIST;
    // the oldest entry still within the window (entries come in with the clock rising)
    uint32_t first = head;   // (head: none)
    for (uint32_t k = 1; k <= have; k++) {
        const WaveHist& e = B.wave_hist[(head - k) % WAVE_HIST];
        if (e.clock < now - WAVE_HISTORY_S || e.clock > now) break;
        first = head - k;
    }
    uint32_t p = head - 1;   // (the newest)
    for (int32_t d = 0; d <= dmax; d++) {
        double lean = 0;
        if (first != head) {
            const double want = now - d / WAVE_TILES_PER_S;
            while (p != first && B.wave_hist[p % WAVE_HIST].clock > want) p--;
            lean = B.wave_hist[p % WAVE_HIST].amount;
        }
        int32_t step = (int32_t)floor(lean * (WAVE_STEPS - 1) + 0.5);
        g_wave_step_at[d] = step < 0 ? 0 : step > WAVE_STEPS - 1 ? WAVE_STEPS - 1 : step;
    }
}
static void draw_grass_wave() {
    if (!B.wave_on) return;
    B.wave_on = 0;
    if (B.wave_gen != B.wave_gen_done) {   // Lua let its tables go: emptied here, written again from its next frame
        memset(g_wave_slots, 0, sizeof g_wave_slots);
        memset(g_wave_map, 0, sizeof g_wave_map);
        g_wave_map_n = 0;
        g_wave_built = B.wave_built;
        B.wave_want_head = B.wave_want_tail;   // (wants for the old frames dropped)
        B.wave_gen_done = B.wave_gen;
        return;
    }
    if (B.wave_built != g_wave_built) { wave_make_map(); g_wave_built = B.wave_built; }
    if (!g_wave_map_n || !B.main_viewport || !B.off_dim_x || !B.off_dim_y || !B.off_background) return;
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    int32_t* const bg = *(int32_t* const*)(main + B.off_background);
    if (!bg) return;
    const double t0 = ticks_now();
    const int32_t cols = B.wave_cols < dx ? B.wave_cols : dx, rows = B.wave_rows < dy ? B.wave_rows : dy;
    const double ux = B.wave_ux, uy = B.wave_uy, cx = B.wave_cx, cy = B.wave_cy, reach = B.wave_reach;
    int32_t dmax = (int32_t)floor(2 * reach + 2);
    if (dmax < 0) dmax = 0;
    if (dmax >= WAVE_MOST_D) dmax = WAVE_MOST_D - 1;
    wave_steps(dmax);
    const int32_t playing = B.wave_playing;
    uint32_t written = 0, wants = 0, want_full = 0;
    for (int32_t sx = 0; sx < cols; sx++) {
        int32_t* const col = bg + (size_t)sx * dy;
        for (int32_t sy = 0; sy < rows; sy++) {
            const int32_t t = col[sy];
            if (t <= 0) continue;
            const WaveTex* w = wave_find(t);
            if (!w) continue;
            int32_t d = (int32_t)floor((sx - cx) * ux + (sy - cy) * uy + reach + 0.5);
            if (d < 0) d = 0;
            if (d > dmax) d = dmax;
            const int32_t step = g_wave_step_at[d];
            WaveSlot& s = g_wave_slots[w->slot];
            int32_t tex = 0;
            if (playing >= 0) {
                int32_t even = 2 * (int32_t)floor(step / 2.0 + 0.5);
                if (even > WAVE_STEPS - 1) even = WAVE_STEPS - 1;
                const double x = (double)(B.wave_x1 + sx), y = (double)(B.wave_y1 + sy);
                int32_t phase = (playing - (int32_t)floor((x * ux + y * uy) * WAVE_PHASES_PER_TILE)) % WAVE_PHASES;
                if (phase < 0) phase += WAVE_PHASES;
                int32_t& f = s.rustle[even / 2][phase];
                if (f > 0) tex = f;
                else if (f == 0) {   // (not made yet: asked of Lua, once)
                    const uint32_t wh = B.wave_want_head;
                    if (wh - B.wave_want_tail < (uint32_t)WAVE_WANT_RING) {
                        B.wave_want[wh % WAVE_WANT_RING] = ((uint32_t)w->slot << 8) | ((uint32_t)(even / 2) << 4) | (uint32_t)phase;
                        B.wave_want_head = wh + 1;
                        f = -2;
                        wants++;
                    } else want_full++;
                }
            }
            if (!tex && step != w->step) {
                const int32_t f = s.lean[step];
                if (f > 0) tex = f;
            }
            if (tex > 0) { col[sy] = tex; written++; }
        }
    }
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.wave_frames++;
    B.wave_written += written;
    B.wave_written_last = written;
    B.wave_wants += wants;
    B.wave_want_full += want_full;
    B.wave_us_total += us;
    if (us > B.wave_us_max) B.wave_us_max = us;
}

// =====================================================================
// RAIN AND SNOW FALLING (test 15M): detailed_weather.lua's falling
// rain and snow, drawn here (main thread, in the hook)
// =====================================================================
// WHAT: every outdoor tile in view where it rains or snows gets a tile of
// the falling sheet in the game's flow layer (screentexpos_high_flow,
// where mist and spray go), so detailed_weather.lua's fog, drawn later by
// its overlay over everything, still lies over it. The rules are
// detailed_weather.lua's (find_rain, rain_tile, snow_tile):
//   * a tile falls where its designation is outside and not hidden, on the
//     view's own level only, and the weather of its map block (Lua: the
//     weather grid, weather_at at the block's middle) is rain or snow;
//   * rain shows the WATER surface (ripples) where the tile holds liquid
//     that isn't magma, or is open space (shape EMPTY) over such liquid one
//     level down; GROUND (splashes) elsewhere. Snow has no surfaces;
//   * the sheet tile: cell (y mod cells) * cells + (x mod cells) of the
//     repeating patch; rain's row ((surface - 1) * slants + (slant - 1)) *
//     cells^2 + cell, snow's (wind - 1) * cells^2 + cell; tile row * frames
//     + frame (0-based here: Lua's index less 1). A tile with nothing drawn
//     in it is handed over as 0 and skipped.
//   * where the game already has a flow in the cell, the tile goes in
//     screentexpos_top_shadow, declared just after it in df-structures
//     (detailed_weather.lua drew it with its overlay there instead, under
//     the fog); a cell with both taken is left alone and counted.
// WHY HERE: Lua made a table of every such tile four times a second and on
// every frame the view moved (in play 4.6 to 6.5 ms a rescan), and wrote
// each one every frame (most of the "untimed" 2.7 to 3.9 ms a frame while
// raining). Worked out here from the map each frame instead, the plan and
// the drawing are one pass over the view.
// WHERE THE MAP IS READ: in the hook, on the main thread, as THE COLOUR
// reads it (level_facts). The weather grid Lua writes in its overlay, for
// the view as drawn, comes after the prerender call; planned there, every
// pan and level change would have drawn the old grid's blocks for a frame.
// PUT BACK, as FOG OVER WATER does: before the game draws into a buffer
// again, each cell written in it gets the game's own value back (only if it
// still holds ours). The game only ever finds its own drawing there, and
// turned off, nothing of it is left two frames later. (The Lua wrote only
// where the flow layer held 0 and never put back, so a cell the game didn't
// redraw kept an old frame's rain, which Lua then took for the game's flow.)
struct RainKept { int32_t* arr; int32_t index; int32_t game; int32_t ours; };
static RainKept* g_rain_kept = nullptr;
static int32_t  g_rain_kept_n = 0, g_rain_kept_cap = 0;
// THE LIST (15N): the arrays the last frame's drawing wrote into (the buffer the game drew last
// frame, which it draws again next frame). In play the list filled (6,974,433 times in 24,105
// frames): entries for arrays that were neither buffer any more were kept for good, as put back only
// matched the buffer about to be drawn, and it was never emptied of them. Which arrays they were was
// not measured: at a zoom the list is dropped already, so DF replaced or switched the main viewport's
// arrays some other time with its size the same. Only these two and the arrays about to be drawn
// are kept now; anything else is let go without touching its array (it may be freed) and counted.
static int32_t* g_rain_last_hf = nullptr;
static int32_t* g_rain_last_ts = nullptr;
static int32_t  g_rain_kept_dx = 0, g_rain_kept_dy = 0;   // the view's size they were written at
static int32_t  g_rain_col[MOST_DIM], g_rain_row[MOST_DIM];   // each screen column's x mod cells, row's y mod cells

// PUT BACK (game thread, prerender, before the game draws): the game's own value back in each cell
// written in the buffers it's about to draw into. Runs whether drawing is on or not.
static void rain_put_back() {
    if (!g_rain_kept_n) return;
    uint8_t* main = viewport_in(0);
    const int32_t dx = main ? *(const int32_t*)(main + B.off_dim_x) : 0;
    const int32_t dy = main ? *(const int32_t*)(main + B.off_dim_y) : 0;
    if (dx != g_rain_kept_dx || dy != g_rain_kept_dy || !B.off_high_flow) { g_rain_kept_n = 0; return; }   // (a zoom: new buffers, drawn afresh)
    int32_t* const hf = *(int32_t* const*)(main + B.off_high_flow);
    int32_t* const ts = B.off_top_shadow ? *(int32_t* const*)(main + B.off_top_shadow) : nullptr;
    int32_t w = 0;
    uint32_t dropped = 0;
    for (int32_t k = 0; k < g_rain_kept_n; k++) {
        const RainKept e = g_rain_kept[k];
        if (e.arr == hf || (ts && e.arr == ts)) {   // (the buffer about to be drawn: the game's own back)
            if (e.arr[e.index] == e.ours) e.arr[e.index] = e.game;
            B.rain_put_back++;
        } else if (e.arr == g_rain_last_hf || (g_rain_last_ts && e.arr == g_rain_last_ts)) {
            g_rain_kept[w++] = e;   // (the other buffer, drawn last frame: its turn next frame)
        } else dropped++;           // (THE LIST: neither; let go untouched)
    }
    g_rain_kept_n = w;
    B.rain_dropped += dropped;
}

// THE PLAN AND THE DRAWING (main thread, in the hook, after the game has drawn)
static void draw_rain() {
    if (!B.rain_enabled || !B.rain_weather_any || !B.have_drawn || !B.off_high_flow || !B.main_viewport ||
        !B.block_index || !B.x_count_block || !B.y_count_block || !B.z_count_block || !B.off_dim_x ||
        !B.off_dim_y || !B.off_tiletype || !B.off_designation || !B.outside_mask) return;
    const int32_t rcells = B.rain_cells, rframes = B.rain_anim, slants = B.rain_slants;
    const int32_t scells = B.snow_cells, sframes = B.snow_anim;
    const bool rain_ok = B.rain_tex_n > 0 && rcells > 0 && rframes > 0 && slants > 0 &&
                         B.rain_slant >= 1 && B.rain_slant <= slants && B.rain_frame >= 0 && B.rain_frame < rframes;
    const bool snow_ok = B.snow_tex_n > 0 && scells > 0 && sframes > 0 && B.snow_wind >= 1 &&
                         B.snow_frame >= 0 && B.snow_frame < sframes;
    if (!rain_ok && !snow_ok) return;
    const int32_t z = B.drawn_z;
    if (B.rain_wz != z) { B.rain_skipped++; return; }   // (the grid is for another level: Lua's frame missed)
    const double t0 = ticks_now();
    // ---- THE MAP (as swap_colour reads it) ----
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    if (z < 0 || z >= g_map.zn) return;
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    int32_t* const hf = *(int32_t* const*)(main + B.off_high_flow);
    int32_t* const ts = B.off_top_shadow ? *(int32_t* const*)(main + B.off_top_shadow) : nullptr;
    if (!hf) return;
    const int32_t n = dx * dy;
    // the list to put back: room for two frames of a whole view, dropped at a new size (new buffers)
    if (dx != g_rain_kept_dx || dy != g_rain_kept_dy) { g_rain_kept_n = 0; g_rain_kept_dx = dx; g_rain_kept_dy = dy; }
    if (g_rain_kept_cap < 2 * n) {
        RainKept* more = (RainKept*)realloc(g_rain_kept, sizeof(RainKept) * (size_t)(2 * n));
        if (!more) return;
        g_rain_kept = more;
        g_rain_kept_cap = 2 * n;
    }
    // ---- THE PATCH: each column's and row's place on the repeat, once (both sheets alike when their
    // cells agree; else worked out per kind below) ----
    const int32_t cells = rain_ok ? rcells : scells;
    for (int32_t sx = 0; sx < dx; sx++) { const int32_t x = B.drawn_x + sx; g_rain_col[sx] = ((x % cells) + cells) % cells; }
    for (int32_t sy = 0; sy < dy; sy++) { const int32_t y = B.drawn_y + sy; g_rain_row[sy] = ((y % cells) + cells) % cells; }
    const bool same_cells = !rain_ok || !snow_ok || rcells == scells;
    // each kind's row base for this frame: rain by surface (1 ground, 2 water), snow by wind
    const int32_t r2 = rcells * rcells, s2 = scells * scells;
    const int32_t rain_base[3] = {0, ((0 * slants) + (B.rain_slant - 1)) * r2, ((1 * slants) + (B.rain_slant - 1)) * r2};
    const int32_t snow_base = (B.snow_wind - 1) * s2;
    const int32_t* const rtex = B.rain_tex;
    const int32_t* const stex = B.snow_tex;
    const int32_t rn = B.rain_tex_n < RAIN_TEX ? B.rain_tex_n : RAIN_TEX, sn = B.snow_tex_n < RAIN_TEX ? B.snow_tex_n : RAIN_TEX;
    const int32_t rframe = B.rain_frame, sframe = B.snow_frame;
    const uint32_t outside = B.outside_mask, hidden = B.hidden_mask, flow = B.flow_mask, magma = B.magma_mask;
    const int32_t wbx = B.rain_wbx, wby = B.rain_wby;
    const int32_t wnx = B.rain_wnx < RAIN_GRID ? B.rain_wnx : RAIN_GRID, wny = B.rain_wny < RAIN_GRID ? B.rain_wny : RAIN_GRID;
    uint32_t falling = 0, drawn = 0, over_flow = 0, no_room = 0, full = 0;
    RainKept* const kept = g_rain_kept;
    int32_t kn = g_rain_kept_n;
    const int32_t cap = g_rain_kept_cap;
    for (int32_t sx = 0; sx < dx; sx++) {
        const int32_t x = B.drawn_x + sx;
        if (x < 0 || x >= g_map.x_end) continue;
        const int32_t bx = x >> 4, gx = bx - wbx;
        if (gx < 0 || gx >= wnx) continue;
        const int32_t col = g_rain_col[sx];
        int32_t sy = 0;
        while (sy < dy) {   // (a run of cells in one map block at a time)
            const int32_t y = B.drawn_y + sy;
            const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
            const int32_t end = sy + run < dy ? sy + run : dy;
            if (y < 0 || y >= g_map.y_end) { sy = end; continue; }
            const int32_t by = y >> 4, gy = by - wby;
            const uint8_t weather = (gy >= 0 && gy < wny) ? B.rain_weather[gx * wny + gy] : 0;
            const uint8_t* const blk = weather ? block_ptr(bx, by, z) : nullptr;
            if (!blk || (weather == 1 && !rain_ok) || (weather == 2 && !snow_ok) || weather > 2) { sy = end; continue; }
            const uint32_t* const des = (const uint32_t*)(blk + B.off_designation) + ((x & 15) << 4);
            const uint16_t* const types = (const uint16_t*)(blk + B.off_tiletype) + ((x & 15) << 4);
            const uint8_t* const below = (weather == 1 && z > 0) ? block_ptr(bx, by, z - 1) : nullptr;
            const uint32_t* const bdes = below ? (const uint32_t*)(below + B.off_designation) + ((x & 15) << 4) : nullptr;
            for (; sy < end; sy++) {
                const int ly = (B.drawn_y + sy) & 15;
                const uint32_t d = des[ly];
                if (!(d & outside) || (d & hidden)) continue;
                falling++;
                // the sheet tile (rain_tile, snow_tile)
                int32_t tex;
                if (weather == 2) {
                    const int32_t c = (same_cells ? g_rain_row[sy] * scells + col
                                                  : ((y % scells) * scells + (x % scells)));
                    const int32_t idx = (snow_base + c) * sframes + sframe;
                    tex = (idx >= 0 && idx < sn) ? stex[idx] : 0;
                } else {
                    // WATER: liquid that isn't magma here, or open space over such liquid just below
                    bool water = (d & flow) && !(d & magma);
                    const uint16_t tt = types[ly];
                    if (!water && bdes && tt < TT_TABLE && B.tt_empty[tt]) {
                        const uint32_t b = bdes[ly];
                        water = (b & flow) && !(b & magma);
                    }
                    const int32_t c = (same_cells ? g_rain_row[sy] * rcells + col
                                                  : ((y % rcells) * rcells + (x % rcells)));
                    const int32_t idx = (rain_base[water ? 2 : 1] + c) * rframes + rframe;
                    tex = (idx >= 0 && idx < rn) ? rtex[idx] : 0;
                }
                if (tex <= 0) continue;   // (nothing drawn in that tile of the sheet this frame)
                if (kn >= cap) { full++; continue; }
                const int32_t i = sx * dy + sy;
                if (hf[i] == 0) {
                    hf[i] = tex;
                    kept[kn++] = RainKept{hf, i, 0, tex};
                    drawn++;
                } else if (ts && ts[i] == 0) {
                    ts[i] = tex;
                    kept[kn++] = RainKept{ts, i, 0, tex};
                    over_flow++;
                } else no_room++;
            }
        }
    }
    g_rain_kept_n = kn;
    g_rain_last_hf = hf; g_rain_last_ts = ts;   // (THE LIST: kept for these next frame)
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.rain_frames++;
    B.rain_drawn += drawn + over_flow;
    B.rain_cells_last = falling;
    B.rain_drawn_last = drawn;
    B.rain_over_flow_last = over_flow;
    B.rain_no_room_last = no_room;
    B.rain_kept_full += full;
    B.rain_us_total += us;
    if (us > B.rain_us_max) B.rain_us_max = us;
}

// =====================================================================
// CRACKS IN PLACE (test 15R): frost.lua's dry cracks put in here (main
// thread, in the hook, after THE COLOUR's swaps)
// =====================================================================
// WHAT: in a look drier than average, frost.lua swapped each outdoor dirt,
// stone or pebble floor, and each dirt or stone ramp, for a copy with its
// piece of the heat patterns' cracks (by position: (y mod 4) * 4 + x mod
// 4, so the cracks join across tiles). It went over every listed tile in
// view every frame to do it: 1.35 to 1.84 ms a frame in play after 15O.
// WHICH TILES (15U): worked out here from the map, by frost.lua's rules
// (frost.lua: work_out): a floor, or a ramp of dirt or stone (grass doesn't
// crack), seen from the view down through open space (EMPTY, RAMP_TOP), up
// to MOST_DEPTH, outdoors or above ground, no water on it, under the snow
// that's drawn (SNOWY), and in a temperature band (not mild). 15R to 15T
// had frost.lua work them out in Lua, a few hundred a frame, and hand them
// over: a tile panned into view showed the look's uncracked ramp until its
// turn came (seen in play: ramps drawing in when panning in a dry look, never
// in a wet one, where THE COLOUR decides everything from the map itself), and
// that planning was frost's largest cost (0.7 to 1.8 ms a frame). Here a map
// block's 256 tiles are worked out together the first time a cell in it is
// drawn, and again every crack_recheck frames (THE TILES WORKED OUT).
// Each frame, each such tile's cell gets its copy:
//   * the texture drawn there is the base (a ramp's own picture, not its
//     copy in the look: THE COLOUR has swapped that in already; a cracked
//     copy put in earlier counts as its base again);
//   * its copy for (base's picture, piece, the tile's code, the look's
//     cracks now) is looked up, and if there isn't one it's painted here and
//     then, in the same frame (THE PAINTING HERE, 15V): a floor's ground as
//     drawn (in the look's colours already) with its piece of the cracks, if
//     its ground is dirt, stone or pebbles (frost.lua: ground_kind, handed
//     over by original in crack_ground); a ramp's own picture redrawn for the
//     look (colour.lua: native_template, by its kind) and cracked; both into
//     a blank texture Lua keeps ready (crack_b), and noted for Lua after
//     (crack_d). 15R to 15U asked frost.lua for each copy and placed it the
//     next frame: every cell needing a copy not made yet showed the look's
//     uncracked ground or ramp meanwhile, and there are 16 copies a picture
//     (one a piece), so panning kept finding pieces not made (seen in play:
//     ramps drawing in in dry looks; 2,202 copies asked for in one session).
//     frost.lua's own loop had made and placed each in the same frame. When
//     the frame's painting time is used up (a whole new view), the look
//     before's copy is shown if there is one, as frost.lua did;
//   * a cracked copy is told to THE COLOUR as a copy of its base (CF_SCREEN,
//     g_link), so its swaps treat it as one: when the cracks stop, a ramp's
//     goes back to its copy in the look on every level THE COLOUR swaps, and
//     floors' go back here (THE CRACKS STOPPED).
// Nothing is put back, as frost.lua put nothing back: the game redraws the
// ground layer itself.
enum : uint8_t { CRACK_OPEN = 0x20, CRACK_FLOOR = 0x40, CRACK_RAMP = 0x80 };   // (crack_tt's; a block's codes)
// THE TILES KEPT (15S): by level, then map block, each block's 256 tiles' codes. 15R kept them in a hash
// of 4,096 blocks, forgotten whole when it filled. Here there is no most: a block is 264 bytes plus 1 KB
// for one with ramps (THE RAMP HELD); only blocks with a cell drawn are made (15U: worked out here).
// A tile's code: CRACK_FLOOR or CRACK_RAMP | its kind (may crack), CRACK_OPEN (open space, seen through),
// or 0.
struct CrackCodes { uint8_t code[256]; int32_t* last; uint32_t stamp; uint32_t worked; };   // last: THE RAMP HELD
static CrackCodes*** g_crack_lv = nullptr;   // [z] -> [bx * byn + by] -> the block (nullptr: none yet)
static int32_t g_crack_bxn = 0, g_crack_byn = 0, g_crack_zn = 0;   // the map the table was made for
static int g_crack_blocks_used = 0;

// Every tile kept let go (frost.lua's forget, a new world, another map).
static void crack_free_tiles() {
    if (g_crack_lv) {
        for (int32_t z = 0; z < g_crack_zn; z++) {
            CrackCodes** dir = g_crack_lv[z];
            if (!dir) continue;
            for (int32_t k = 0; k < g_crack_bxn * g_crack_byn; k++)
                if (dir[k]) { free(dir[k]->last); free(dir[k]); }
            free(dir);
        }
        free(g_crack_lv);
    }
    g_crack_lv = nullptr;
    g_crack_bxn = g_crack_byn = g_crack_zn = 0;
    g_crack_blocks_used = 0;
}

// THE TILES WORKED OUT (15U): a map block's 256 tiles, by frost.lua's rules (work_out), from the map.
static uint32_t g_crack_frame = 0;        // frames walked (a block's stamp; a picture's last check)
static uint32_t g_crack_tables_seen = 0;  // crack_tables when the tiles were last let go
static int g_crack_worked = 0;            // blocks worked out this frame
static const int CRACK_REWORK_PER_FRAME = 32;   // blocks due a recheck worked out at most this many a frame
static void crack_work_block(CrackCodes* c, int32_t bx, int32_t by, int32_t z) {
    c->stamp = g_crack_frame;
    c->worked = 1;
    g_crack_worked++;
    B.crack_blocks_worked++;
    const uint8_t* blk = block_ptr(bx, by, z);
    if (!blk) { memset(c->code, 0, sizeof c->code); return; }
    // the snow on each tile (grass.lua: snow_amount: the most of any powder WATER spatter)
    uint8_t snow[256];
    memset(snow, 0, sizeof snow);
    void* const* first;
    void* const* last;
    if (B.spatter_vtable && events_of(blk, first, last)) {
        for (void* const* p = first; p < last; p++) {
            const uint8_t* ev = (const uint8_t*)*p;
            if (!ev || *(const uint64_t*)ev != B.spatter_vtable) continue;
            if (*(const int16_t*)(ev + B.off_ev_mat_type) != B.snow_mat_type) continue;
            if (*(const int16_t*)(ev + B.off_ev_mat_state) != B.snow_mat_state) continue;
            const uint8_t* amount = ev + B.off_ev_amount;
            for (int i = 0; i < 256; i++) if (amount[i] > snow[i]) snow[i] = amount[i];
        }
    }
    const uint16_t* types = (const uint16_t*)(blk + B.off_tiletype);
    const uint32_t* des = (const uint32_t*)(blk + B.off_designation);
    const uint16_t* temp = B.off_temperature ? (const uint16_t*)(blk + B.off_temperature) : nullptr;
    const uint32_t outside = B.outside_mask, under = B.subterranean_mask, flow = B.flow_mask;
    const int snowy = B.snowy_from > 0 ? B.snowy_from : 100;
    const double band_c = B.crack_band_c > 0 ? B.crack_band_c : 3.0;
    bool ramps = false;
    for (int i = 0; i < 256; i++) {
        const uint16_t t = types[i];
        const uint8_t k = t < (uint16_t)TT_TABLE ? B.crack_tt[t] : 0;
        uint8_t code = 0;
        if (k == CRACK_OPEN) code = CRACK_OPEN;
        else if (k & (CRACK_FLOOR | CRACK_RAMP)) {
            const uint32_t d = des[i];
            // above ground, not just "outside" (a tree's canopy is indoors); no water; under the drawn snow
            bool ok = !(!(d & outside) && (d & under)) && !(d & flow) && snow[i] < snowy;
            if (ok) {
                // its temperature band, as frost.lua's band_of: none (mild) when the band's middle is mild
                const double c = B.crack_forced_on ? B.crack_forced_c : temp ? ((double)temp[i] - 10000.0) * 5.0 / 9.0 : 15.0;
                const double band = floor(c / band_c);
                const double middle = (band + 0.5) * band_c;
                if (middle >= B.crack_cool_from && middle <= B.crack_warm_from) ok = false;
            }
            if (ok) code = k;
        }
        c->code[i] = code;
        if (code & CRACK_RAMP) ramps = true;
    }
    if (ramps && !c->last) c->last = (int32_t*)calloc(256, sizeof(int32_t));   // (THE RAMP HELD)
}

// A map tile's block, made if `make` and worked out (again when due); nullptr if outside the map, or
// none yet. The map's size is read each time: another map lets every tile go.
static CrackCodes* crack_codes(int32_t x, int32_t y, int32_t z, bool make) {
    if (x < 0 || y < 0 || z < 0) return nullptr;
    if (make) {
        if (!B.x_count_block || !B.y_count_block || !B.z_count_block) return nullptr;
        const int32_t bxn = *(const int32_t*)(uintptr_t)B.x_count_block, byn = *(const int32_t*)(uintptr_t)B.y_count_block,
                      zn = *(const int32_t*)(uintptr_t)B.z_count_block;
        if (bxn <= 0 || byn <= 0 || zn <= 0 || bxn > MOST_BLOCKS || byn > MOST_BLOCKS || zn > MOST_LEVELS) return nullptr;
        if (bxn != g_crack_bxn || byn != g_crack_byn || zn != g_crack_zn) {
            crack_free_tiles();
            g_crack_lv = (CrackCodes***)calloc(zn, sizeof(CrackCodes**));
            if (!g_crack_lv) return nullptr;
            g_crack_bxn = bxn; g_crack_byn = byn; g_crack_zn = zn;
        }
    }
    if (!g_crack_lv || z >= g_crack_zn || (x >> 4) >= g_crack_bxn || (y >> 4) >= g_crack_byn) return nullptr;
    CrackCodes**& dir = g_crack_lv[z];
    if (!dir) {
        if (!make) return nullptr;
        dir = (CrackCodes**)calloc((size_t)g_crack_bxn * g_crack_byn, sizeof(CrackCodes*));
        if (!dir) return nullptr;
    }
    CrackCodes*& blk = dir[(x >> 4) * g_crack_byn + (y >> 4)];
    if (!blk && make) {
        blk = (CrackCodes*)calloc(1, sizeof(CrackCodes));
        if (blk) g_crack_blocks_used++;
    }
    if (blk && make) {
        // worked out the first time (always: it's on screen now), again once due (a few a frame)
        const uint32_t recheck = B.crack_recheck ? B.crack_recheck : 600;
        if (!blk->worked || (g_crack_frame - blk->stamp >= recheck && g_crack_worked < CRACK_REWORK_PER_FRAME))
            crack_work_block(blk, x >> 4, y >> 4, z);
    }
    return blk;
}
// PICTURES, NOT NUMBERS (15V): a copy is kept by the picture it's painted from, not by the texture's number.
// The game gives a ramp's picture a new number after a zoom or on another level (frost.lua: RAMPS BY
// PICTURE), and a copy kept by number was missed under each new one. A number's picture is a hash of all
// its 1024 pixels, worked out when the number is first seen and again whenever its 16 sampled pixels
// (pic_print, as colour.lua's sample_hash) differ from last time; the sample is checked once a frame.
struct CrackPic { int32_t t; uint32_t fp; uint64_t id; uint32_t frame; uint32_t pad; };   // t 0: empty
static const int CRACK_PICS = 16384;      // (a power of 2; 384 KB; all forgotten at 3/4, worked out again as seen)
static CrackPic* g_crack_pics = nullptr;
static int g_crack_pics_used = 0;

// A texture's 32 x 32 pixels as one unpadded run: its surface's own, or copied into `scratch` when its rows
// are padded; nullptr if it has no such surface (as grass.lua's surface_of reads enabler.textures.raws).
static const uint32_t* crack_pixels(int32_t t, uint32_t* scratch) {
    if (!B.col_raws || t <= 0) return nullptr;
    const uint8_t* vec = (const uint8_t*)(uintptr_t)B.col_raws;
    void* const* first = *(void* const* const*)vec;
    void* const* last = *(void* const* const*)(vec + 8);
    if (!first || last < first || (size_t)t >= (size_t)(last - first)) return nullptr;
    const uint8_t* surface = (const uint8_t*)first[t];
    if (!surface) return nullptr;
    const int32_t w = *(const int32_t*)(surface + 16), h = *(const int32_t*)(surface + 20);
    const int32_t pitch = *(const int32_t*)(surface + 24);
    const uint32_t* px = *(const uint32_t* const*)(surface + 32);
    if (w != PIC_TILE || h != PIC_TILE || pitch < PIC_TILE * 4 || pitch % 4 || !px) return nullptr;
    if (!readable_span(px, (size_t)pitch * PIC_TILE)) return nullptr;
    if (pitch == PIC_TILE * 4) return px;
    for (int y = 0; y < PIC_TILE; y++) memcpy(scratch + y * PIC_TILE, px + y * (pitch / 4), PIC_TILE * 4);
    return scratch;
}
static uint64_t crack_hash_pixels(const uint32_t* px) {
    uint64_t h = 0xcbf29ce484222325ull;
    for (int n = 0; n < PIC_TILE * PIC_TILE; n++) { h ^= px[n]; h *= 0x100000001b3ull; }
    h ^= h >> 29; h *= 0xbf58476d1ce4e5b9ull; h ^= h >> 32;
    return h ? h : 1;
}
// Texture t's picture; 0 if its pixels can't be read.
static uint64_t crack_picture(int32_t t) {
    if (!g_crack_pics) {
        g_crack_pics = (CrackPic*)calloc(CRACK_PICS, sizeof(CrackPic));
        if (!g_crack_pics) return 0;
    }
    if (g_crack_pics_used >= CRACK_PICS * 3 / 4) {
        memset(g_crack_pics, 0, sizeof(CrackPic) * CRACK_PICS);
        g_crack_pics_used = 0;
    }
    const uint32_t h = ((uint32_t)t * 2654435761u) & (CRACK_PICS - 1);
    CrackPic* e = nullptr;
    for (int k = 0; k < CRACK_PICS; k++) {
        CrackPic& c = g_crack_pics[(h + k) & (CRACK_PICS - 1)];
        if (c.t == t) { e = &c; break; }
        if (c.t == 0) { c.t = t; c.id = 0; c.fp = 0; c.frame = g_crack_frame - 1; g_crack_pics_used++; e = &c; break; }
    }
    if (!e) return 0;
    if (e->id && e->frame == g_crack_frame) return e->id;
    uint32_t fp;
    if (!pic_print(t, fp)) { e->id = 0; return 0; }
    e->frame = g_crack_frame;
    if (e->id && e->fp == fp) return e->id;
    uint32_t scratch[PIC_TILE * PIC_TILE];
    const uint32_t* px = crack_pixels(t, scratch);
    if (!px) { e->id = 0; return 0; }
    e->id = crack_hash_pixels(px);
    e->fp = fp;
    return e->id;
}

// THE COPIES: by picture, piece, the tile's code and the look. Never forgotten while the world lasts: one
// forgotten would be painted again into another texture, and textures are never let go (grass.lua:
// discard). At 7/8 full no more are made (crack_table_full), and their cells keep the look's own.
struct CrackCopy { uint64_t pic; uint32_t gen; uint8_t piece, code, used, pad; int32_t tex; int32_t pad2; };   // tex 0: not
                                                                                                             // painted yet; -1: doesn't crack
static const int CRACK_COPIES = 65536;    // (a power of 2: 1 << 16, as crack_copy's hash; 1.5 MB)
static CrackCopy* g_crack_copies = nullptr;
static int g_crack_copies_used = 0;
static CrackCopy* crack_copy(uint64_t pic, int piece, uint8_t code, uint32_t gen, bool make) {
    if (!g_crack_copies) {
        if (!make) return nullptr;
        g_crack_copies = (CrackCopy*)calloc(CRACK_COPIES, sizeof(CrackCopy));
        if (!g_crack_copies) return nullptr;
    }
    uint64_t k = pic ^ ((uint64_t)gen * 0x9E3779B97F4A7C15ull) ^ ((uint64_t)(((uint32_t)code << 4) | (uint32_t)piece) * 0xC2B2AE3D27D4EB4Full);
    k ^= k >> 31; k *= 0xbf58476d1ce4e5b9ull; k ^= k >> 29;
    const uint32_t h = (uint32_t)(k >> 48);   // (16 bits: CRACK_COPIES)
    for (int i = 0; i < 128; i++) {
        CrackCopy& e = g_crack_copies[(h + i) & (CRACK_COPIES - 1)];
        if (!e.used) {
            if (!make) return nullptr;
            if (g_crack_copies_used >= CRACK_COPIES * 7 / 8) { B.crack_table_full++; return nullptr; }
            e.used = 1; e.pic = pic; e.gen = gen; e.piece = (uint8_t)piece; e.code = code; e.tex = 0;
            g_crack_copies_used++;
            return &e;
        }
        if (e.pic == pic && e.gen == gen && e.piece == piece && e.code == code) return &e;
    }
    if (make) B.crack_table_full++;
    return nullptr;
}
// (FLOORS AHEAD, below: each look's list of its copies of the grounds that crack, kept by original)
struct CrackFloorMap { uint32_t gen, version, n, pad; int32_t key[2 * CRACK_FLOORS]; int32_t val[2 * CRACK_FLOORS]; };
static CrackFloorMap g_floor_map[2];
static uint8_t g_crack_mark[TEX_MAP];     // 1 for a cracked copy made for this (its base: g_link)
static uint8_t g_ground[TEX_MAP];         // each original's ground (CK_*; 0 doesn't crack), filled by Lua (crack_ground)
// Every cracked copy made, with its base: told to THE COLOUR's tables again when they're emptied (a new
// start of the colour), as frost.lua's textures are never let go (grass.lua: discard) and still show.
struct CrackMade { int32_t tex, base; };
static CrackMade* g_crack_made = nullptr;
static int g_crack_made_n = 0, g_crack_made_cap = 0;
static uint32_t g_crack_world_done = 0;   // the crack_world last forgotten for
static int g_crack_clear_frames = 0;      // THE CRACKS STOPPED: frames left to give floors their ground back

// A cracked copy told to THE COLOUR as a copy of its base.
static inline void crack_tell_colour(int32_t tex, int32_t base) {
    g_link[tex] = base;
    g_cflag[tex] = (uint8_t)(g_cflag[tex] | CF_SCREEN);
}
// Every cracked copy forgotten (a new world: their numbers may be other pictures now).
static void crack_forget_all() {
    for (int k = 0; k < g_crack_made_n; k++) {
        const int32_t t = g_crack_made[k].tex;
        g_crack_mark[t] = 0;
        if (g_link[t] == g_crack_made[k].base) { g_link[t] = 0; g_cflag[t] = (uint8_t)(g_cflag[t] & ~CF_SCREEN); }
    }
    g_crack_made_n = 0;
    if (g_crack_copies) memset(g_crack_copies, 0, sizeof(CrackCopy) * CRACK_COPIES);
    g_crack_copies_used = 0;
    if (g_crack_pics) memset(g_crack_pics, 0, sizeof(CrackPic) * CRACK_PICS);
    g_crack_pics_used = 0;
    memset(g_floor_map, 0, sizeof g_floor_map);
    memset(g_ground, 0, sizeof g_ground);   // (Lua fills it again at the next start)
    crack_free_tiles();
}

// A painted copy noted: told to THE COLOUR as a copy of its base, listed to be told again after its
// tables are emptied, and handed to Lua (crack_d) to note as Detailed Weather's.
static void crack_note(int32_t tex, int32_t base, int piece, uint8_t code, uint32_t gen) {
    if (tex <= 0 || tex >= TEX_MAP || base <= 0 || base >= TEX_MAP) return;
    if (!g_crack_mark[tex]) {
        if (g_crack_made_n == g_crack_made_cap) {
            const int cap = g_crack_made_cap ? g_crack_made_cap * 2 : 4096;
            CrackMade* m = (CrackMade*)realloc(g_crack_made, sizeof(CrackMade) * cap);
            if (m) { g_crack_made = m; g_crack_made_cap = cap; }
        }
        if (g_crack_made_n < g_crack_made_cap) g_crack_made[g_crack_made_n++] = {tex, base};
    }
    g_crack_mark[tex] = 1;
    crack_tell_colour(tex, base);
    if (B.crack_d_head - B.crack_d_tail < (uint32_t)CRACK_DONE_RING) {
        CrackDone& d = B.crack_d[B.crack_d_head % CRACK_DONE_RING];
        d.tex = tex; d.base = base; d.gen = gen; d.piece = (uint8_t)piece; d.code = code; d.pad = 0;
        B.crack_d_head++;
    } else B.crack_done_full++;
}

// THE PAINTING HERE (15V). A look's cracks, by its number (crack_look: the look showing's and the next's).
static const CrackLook* crack_look_for(uint32_t gen) {
    for (int k = 0; k < 2; k++) if ((B.crack_look[k].ready & 1) && B.crack_look[k].gen == gen) return &B.crack_look[k];
    return nullptr;
}
// One copy painted: base's pixels (a floor's ground as drawn, already in the look's colours; a ramp's own
// picture, redrawn for the look by its kind's numbers) with its piece of the heat patterns' cracks, into
// the next blank. The texture; -1 if it doesn't crack (a floor whose ground isn't dirt, stone or pebbles,
// or a look with no redraw for the ramp's kind); 0 if not now (no blank ready, the patterns or the pixels
// not readable).
// `orig`: the original that decides a floor's ground (the base's own, or for THE NEXT LOOK AHEAD the
// original of the next look's copy painted from).
static inline int32_t crack_original(int32_t base) { return (g_cflag[base] & CF_TABLE) ? g_link[base] : base; }
static int32_t crack_paint(int32_t base, int32_t orig, int piece, uint8_t code, const CrackLook* look) {
    PaintJob j;
    uint32_t kind;
    if (code & CRACK_RAMP) {
        kind = code & 0x3f;   // (1 dirt, 2 stone: frost.lua's CRACK_KIND_CODE)
        if (kind < 1 || kind > 2 || !(look->ready & (1u << kind))) return -1;
        j = look->ramp[kind - 1];
    } else {
        // a floor: by its ground (a table copy's original: g_link)
        kind = (orig > 0 && orig < TEX_MAP) ? g_ground[orig] : 0;
        if (kind < CK_DIRT || kind > CK_PEBBLES) return -1;
        // its ground unchanged first (colour.lua: NO_CHANGE), then the cracks
        memset(&j, 0, sizeof j);
        j.m[0] = j.m[4] = j.m[8] = 1;
        j.lean[0] = j.lean[1] = j.lean[2] = 1;
        j.soil[0] = j.soil[1] = j.soil[2] = 1;
        j.dark = 1; j.ice_dark = 1;
    }
    const uint64_t here = B.crack_heat[piece & 15], north = B.crack_heat[(piece + 12) & 15];   // (north: piece - 4)
    if (!here || !north) { B.crack_unreadable++; return 0; }
    if (B.crack_b_tail == B.crack_b_head) { B.crack_no_blank++; return 0; }
    uint32_t scratch[PIC_TILE * PIC_TILE];
    const uint32_t* src = crack_pixels(base, scratch);
    if (!src) { B.crack_unreadable++; return 0; }
    const CrackBlank bl = B.crack_b[B.crack_b_tail % CRACK_BLANKS];
    B.crack_b_tail++;   // (taken, painted or not: a blank that can't be painted is no use)
    j.src = (uint64_t)(uintptr_t)src;
    j.dst = bl.addr;
    j.crack_kind = kind;
    j.crack_piece = (uint32_t)piece;
    j.crack_amount = look->amount;
    j.crack_here = here;
    j.crack_north = north;
    const int64_t done = B.paint_done;
    paint_one(j);
    if (B.paint_done == done) { B.crack_unreadable++; return 0; }   // (refused: paint_bad counted it)
    B.paint_done = done;   // (THE COLOUR's count of its own copies left as it was)
    return bl.tex > 0 ? bl.tex : 0;
}

// FLOORS AHEAD (15V): a floor's copy is painted from the ground as the game draws it in that look, which for
// the next look is the next look's own copy of the original (a table copy, made by colour.lua as it builds
// the look; or the original, where the look has none). Each look lists them (CrackLook: floor_orig and
// floor_copy) for the originals whose ground cracks; kept here by original, made again when the list changes.
// What the game will draw for original `orig` in `look`; 0 if the look hasn't listed it (yet).
static int32_t crack_floor_copy(const CrackLook* look, int32_t orig) {
    const int slot = look == &B.crack_look[0] ? 0 : 1;
    CrackFloorMap& m = g_floor_map[slot];
    const uint32_t mask = 2 * CRACK_FLOORS - 1;
    if (m.gen != look->gen || m.version != look->floors_version || m.n != look->floors_n) {
        memset(m.key, 0, sizeof m.key);
        const uint32_t n = look->floors_n < (uint32_t)CRACK_FLOORS ? look->floors_n : (uint32_t)CRACK_FLOORS;
        for (uint32_t k = 0; k < n; k++) {
            const int32_t o = look->floor_orig[k];
            if (o <= 0) continue;
            uint32_t h = ((uint32_t)o * 2654435761u) & mask;
            while (m.key[h] && m.key[h] != o) h = (h + 1) & mask;
            m.key[h] = o;
            m.val[h] = look->floor_copy[k];
        }
        m.gen = look->gen; m.version = look->floors_version; m.n = look->floors_n;
    }
    uint32_t h = ((uint32_t)orig * 2654435761u) & mask;
    for (uint32_t i = 0; i <= mask && m.key[h]; i++, h = (h + 1) & mask) if (m.key[h] == orig) return m.val[h];
    return 0;
}

static const double CRACK_PAINT_US = 2000;            // painting at most this long a frame (each copy about 30 to
                                                      // 100 us: a floor's cracks, a ramp's redraw and cracks)...
static const double CRACK_PAINT_NEW_VIEW_US = 12000;  // ...and this for the first frames of a new view
static const double CRACK_AHEAD_US = 1000;            // THE NEXT LOOK AHEAD: the next look's, up to this a frame
static int32_t g_crack_view_x = 0, g_crack_view_y = 0, g_crack_view_z = -1, g_crack_view_dx = 0, g_crack_view_dy = 0;
static int g_crack_new_view = 0;                      // frames left with the new view's painting time

static void place_cracks() {
    // (a new world started in Lua this frame: nothing placed until this side has forgotten the last world's
    // copies, tiles and blanks, in the next prerender; their texture numbers may be others' by now)
    if (B.crack_world != g_crack_world_done) return;
    // ---- THE COPIES MADE (answers), and the tiles let go when the settings change ----
    if (B.crack_tables != g_crack_tables_seen) {   // (the tiletype table or a forced temperature: worked out again)
        crack_free_tiles();
        g_crack_tables_seen = B.crack_tables;
    }
    g_crack_worked = 0;
    const bool on = B.crack_on != 0;
    // THE NEXT LOOK AHEAD (15T): while colour.lua makes the next look, the next look's copies painted too
    const uint32_t next = B.crack_gen_next;
    const CrackLook* const next_look = crack_look_for(next);
    const bool ahead = next != 0 && next != 0xffffffffu && !(on && next == B.crack_gen) && next_look;   // (0: none)
    if (on) g_crack_clear_frames = 2;
    if (!ahead) B.crack_next_missing_last = 0;
    if (!on && g_crack_clear_frames <= 0 && !ahead) return;
    if (!B.have_drawn || !B.main_viewport || !B.block_index || !B.x_count_block || !B.y_count_block ||
        !B.z_count_block || !B.off_dim_x || !B.off_dim_y || !B.off_background) return;
    const double t0 = ticks_now();
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    const int depth = (int)(B.crack_depth < (uint32_t)MOST_DEPTH ? B.crack_depth : MOST_DEPTH);
    const int32_t black = B.black_texpos;
    const uint32_t gen = B.crack_gen, prev = B.crack_gen_prev;
    const CrackLook* const look = on ? crack_look_for(gen) : nullptr;
    uint32_t cells = 0, written = 0, held = 0, waiting = 0, cleared = 0, ramp_held = 0;
    uint32_t next_missing = 0, painted = 0, painted_ahead = 0;
    // THE PAINTING HERE: the frame's painting time; more for the first frames of another level, a resize or
    // a jump of half the view or more, where a whole view of copies may be new (as frost.lua's NEW VIEW BAKES)
    if (B.drawn_z != g_crack_view_z || dx != g_crack_view_dx || dy != g_crack_view_dy ||
        abs(B.drawn_x - g_crack_view_x) * 2 >= dx || abs(B.drawn_y - g_crack_view_y) * 2 >= dy) g_crack_new_view = 3;
    g_crack_view_x = B.drawn_x; g_crack_view_y = B.drawn_y; g_crack_view_z = B.drawn_z;
    g_crack_view_dx = dx; g_crack_view_dy = dy;
    const double paint_budget = g_crack_new_view > 0 ? CRACK_PAINT_NEW_VIEW_US : CRACK_PAINT_US;
    if (g_crack_new_view > 0) g_crack_new_view--;
    double paint_us = 0, ahead_us = 0;   // (spent so far this frame)
    int32_t memo_base = 0;               // (the last base's picture)
    uint64_t memo_pic = 0;
    for (int d = 0; d <= depth; d++) {
        uint8_t* vp = viewport_in(d);
        if (!vp) break;
        if (d > 0 && !(*(const uint32_t*)(vp + B.off_flag) & 1)) break;   // (a level the game isn't drawing)
        if (*(const int32_t*)(vp + B.off_dim_x) != dx || *(const int32_t*)(vp + B.off_dim_y) != dy) break;
        int32_t* const bg = *(int32_t* const*)(vp + B.off_background);
        if (!bg) break;
        const int32_t z = B.drawn_z - d;
        if (z < 0 || z >= g_map.zn) break;
        if (!on && g_crack_clear_frames > 0) {
            // ---- THE CRACKS STOPPED: floors' copies given their ground back (THE COLOUR does ramps') ----
            const int32_t n = dx * dy;
            for (int32_t i = 0; i < n; i++) {
                const int32_t t = bg[i];
                if (t > 0 && t < TEX_MAP && g_crack_mark[t]) { bg[i] = g_link[t]; cleared++; }
            }
        }
        if (!on && !ahead) continue;
        for (int32_t sx = 0; sx < dx; sx++) {
            const int32_t x = B.drawn_x + sx;
            if (x < 0 || x >= g_map.x_end) continue;
            int32_t sy = 0;
            while (sy < dy) {   // (a run of cells in one map block at a time)
                const int32_t y = B.drawn_y + sy;
                const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
                const int32_t end = sy + run < dy ? sy + run : dy;
                CrackCodes* const b = (y >= 0 && y < g_map.y_end) ? crack_codes(x, y, z, true) : nullptr;
                if (!b) { sy = end; continue; }
                const uint8_t* codes = b->code + ((x & 15) << 4);
                // (seen down through open space: the levels above this one in this block's column)
                const uint8_t* above[MOST_DEPTH + 1];
                bool seen = true;
                for (int k = 0; k < d && seen; k++) {
                    const CrackCodes* a = crack_codes(x, y, B.drawn_z - k, true);
                    if (!a) seen = false; else above[k] = a->code + ((x & 15) << 4);
                }
                if (!seen) { sy = end; continue; }
                for (; sy < end; sy++) {
                    const int cy = (B.drawn_y + sy) & 15;
                    const uint8_t code = codes[cy];
                    if (!(code & (CRACK_FLOOR | CRACK_RAMP))) continue;
                    {
                        bool open = true;
                        for (int k = 0; k < d; k++) if (above[k][cy] != CRACK_OPEN) { open = false; break; }
                        if (!open) continue;
                    }
                    const int32_t i = sx * dy + sy;
                    const int32_t t = bg[i];
                    if (t <= 0 || t >= TEX_MAP || t == black) continue;   // (nothing, or not drawn yet)
                    int32_t base = t;
                    if (g_crack_mark[t] || (g_cflag[t] & CF_SCREEN)) base = g_link[t];   // (a copy: its base)
                    else if (is_ours(t)) continue;   // (Detailed Weather's own: a snowy ramp)
                    if (base <= 0 || base >= TEX_MAP) continue;
                    cells++;
                    const int32_t yy = B.drawn_y + sy;
                    const int piece = (yy & 3) * 4 + (x & 3);
                    // (PICTURES, NOT NUMBERS: the copies are kept by the base's picture; the last one looked up
                    // kept, as cells side by side mostly show the same texture)
                    if (base != memo_base) { memo_base = base; memo_pic = crack_picture(base); }
                    const uint64_t pic = memo_pic;
                    if (!pic) continue;   // (its pixels can't be read: left as drawn)
                    const int32_t orig = crack_original(base);
                    if (ahead) {
                        // THE NEXT LOOK AHEAD: its copy painted ahead, with what's left of its own time. A ramp's
                        // is painted from its own picture, as in any look; a floor's from the next look's own copy
                        // of its ground (FLOORS AHEAD), which is what the game draws there once the look shows.
                        int32_t src = base;
                        uint64_t apic = pic;
                        bool needed = true;
                        if (!(code & CRACK_RAMP)) {
                            needed = orig > 0 && orig < TEX_MAP && g_ground[orig];   // (a ground that cracks)
                            src = needed ? crack_floor_copy(next_look, orig) : 0;
                            apic = src == base ? pic : src > 0 ? crack_picture(src) : 0;
                        }
                        if (needed) {
                            CrackCopy* f = apic ? crack_copy(apic, piece, code, next, true) : nullptr;
                            if (f && f->tex == 0 && ahead_us < CRACK_AHEAD_US) {
                                const double p0 = ticks_now();
                                const int32_t made = crack_paint(src, orig, piece, code, next_look);
                                ahead_us += (ticks_now() - p0) * g_us_per_tick;
                                if (made) {
                                    f->tex = made;
                                    if (made > 0) { crack_note(made, src, piece, code, next); painted_ahead++; }
                                }
                            }
                            if (!f || f->tex == 0) next_missing++;
                        }
                    }
                    if (!on) continue;
                    CrackCopy* e = look ? crack_copy(pic, piece, code, gen, true) : nullptr;
                    if (e && e->tex == 0) {
                        // not painted yet: now, while the frame's painting time lasts
                        if (paint_us < paint_budget) {
                            const double p0 = ticks_now();
                            const int32_t made = crack_paint(base, orig, piece, code, look);
                            paint_us += (ticks_now() - p0) * g_us_per_tick;
                            if (made) {
                                e->tex = made;
                                if (made > 0) { crack_note(made, base, piece, code, gen); painted++; }
                            }
                        } else B.crack_over_time++;
                    }
                    int32_t tex = (e && e->tex > 0) ? e->tex : 0;
                    if (!tex && prev != 0xffffffffu) {   // (the look before's, until this one's is painted)
                        const CrackCopy* o = crack_copy(pic, piece, code, prev, false);
                        if (o && o->tex > 0) { tex = o->tex; held++; }
                    }
                    // THE RAMP HELD (15S): a ramp whose copy isn't painted yet (since 15V only when the frame's
                    // painting time is used up, or no blank is ready) keeps the cracked copy it showed last,
                    // as frost.lua's FROST HELD OVER did, until its own comes (or it turns out not to crack:
                    // then the ground as drawn).
                    int32_t* const last = (code & CRACK_RAMP) ? b->last : nullptr;
                    const int ti = ((x & 15) << 4) | (yy & 15);
                    if (!tex && last && !(e && e->tex < 0)) {
                        const int32_t l = last[ti];
                        if (l > 0 && l < TEX_MAP && g_crack_mark[l]) { tex = l; ramp_held++; }
                    }
                    if (tex > 0) {
                        if (bg[i] != tex) bg[i] = tex;
                        if (e && e->tex == tex) written++;
                        if (last) last[ti] = tex;
                    } else if (!(e && e->tex < 0)) waiting++;
                }
            }
        }
    }
    if (!on) g_crack_clear_frames--;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.crack_frames++;
    g_crack_frame++;
    B.crack_tiles_kept = (uint32_t)g_crack_blocks_used;
    B.crack_worked_last = (uint32_t)g_crack_worked;
    B.crack_written += written;
    B.crack_cells_last = cells;
    B.crack_written_last = written;
    B.crack_held_last = held;
    B.crack_waiting_last = waiting;
    B.crack_ramp_held_last = ramp_held;
    B.crack_ramp_held += ramp_held;
    B.crack_waiting += waiting;
    B.crack_painted += painted;
    B.crack_ahead_painted += painted_ahead;
    B.crack_painted_last = painted + painted_ahead;
    B.crack_copies_kept = (uint32_t)g_crack_copies_used;
    B.crack_pics_kept = (uint32_t)g_crack_pics_used;
    B.crack_paint_us_total += paint_us + ahead_us;
    if (paint_us + ahead_us > B.crack_paint_us_max) B.crack_paint_us_max = paint_us + ahead_us;
    if (ahead) {   // (THE NEXT LOOK AHEAD: what's left, for colour.lua to wait on, and for which look)
        B.crack_next_missing_last = next_missing;
        B.crack_next_walked = next;
    }
    B.crack_cleared += cleared;
    B.crack_us_total += us;
    if (us > B.crack_us_max) B.crack_us_max = us;
}

// =====================================================================
// THE FOG AND THE LEAVES DRAWN HERE (test 15X): detailed_weather.lua's fog
// and leaves.lua's falling leaves and petals, drawn here each frame from
// the map (main thread, in the hook, after the game has drawn)
// =====================================================================
// WHY HERE: both were drawn in Lua every frame, a write through DFHack for
// each tile: thick fog 2.56 ms a frame, and 2.8 ms each time the outdoor
// tiles were looked for again; leaves and petals 1.58 to 1.72 ms a frame
// (15W's report, both forced on). Leaves also wrote the projectile layer
// only where it held 0 and never put back, as the rain once did, so a cell
// the game didn't redraw kept an old frame's leaf.
// PUT BACK, as RAIN AND SNOW FALLING does (each in one layer of the main
// view): before the game draws into a buffer again, each cell written in
// it gets the game's own value back (if it still holds ours). Turned off,
// nothing of either is left two frames later.
struct Kept { int32_t* arr; int32_t index; int32_t game; int32_t ours; };
struct KeptList { Kept* e; int32_t n, cap, dx, dy; int32_t* last; };
static KeptList g_wfog_kept = {}, g_leaf_kept = {};

// (game thread, prerender, before the game draws) the game's own value back in each cell written in the
// buffer of `layer_off` it's about to draw into; the other buffer's wait their turn, the next frame
static void kept_put_back(KeptList& L, uint32_t layer_off, int64_t& put_back, uint32_t& dropped) {
    if (!L.n) return;
    uint8_t* main = viewport_in(0);
    const int32_t dx = main ? *(const int32_t*)(main + B.off_dim_x) : 0;
    const int32_t dy = main ? *(const int32_t*)(main + B.off_dim_y) : 0;
    if (dx != L.dx || dy != L.dy || !layer_off) { L.n = 0; return; }   // (a zoom: new buffers, drawn afresh)
    int32_t* const now = *(int32_t* const*)(main + layer_off);
    int32_t w = 0;
    for (int32_t k = 0; k < L.n; k++) {
        const Kept e = L.e[k];
        if (e.arr == now) {   // (the buffer about to be drawn)
            if (e.arr[e.index] == e.ours) e.arr[e.index] = e.game;
            put_back++;
        } else if (e.arr == L.last) L.e[w++] = e;   // (the other buffer, drawn last frame)
        else dropped++;                              // (neither: let go untouched, it may be freed)
    }
    L.n = w;
}
// (main thread) room for two frames of a whole view; the list dropped at a new size (new buffers)
static bool kept_ready(KeptList& L, int32_t dx, int32_t dy) {
    if (dx != L.dx || dy != L.dy) { L.n = 0; L.dx = dx; L.dy = dy; }
    const int32_t need = 2 * dx * dy;
    if (L.cap < need) {
        Kept* more = (Kept*)realloc(L.e, sizeof(Kept) * (size_t)need);
        if (!more) return false;
        L.e = more;
        L.cap = need;
    }
    return true;
}
static inline int32_t floor_div(int32_t a, int32_t b) {
    int32_t q = a / b;
    if ((a % b) != 0 && ((a < 0) != (b < 0))) q--;
    return q;
}
static bool map_ready() {   // (g_map from the game's map, as the others read it)
    if (!B.block_index || !B.x_count_block || !B.y_count_block || !B.z_count_block) return false;
    g_map.xs = *(void* const* const*)(uintptr_t)B.block_index;
    g_map.bxn = *(const int32_t*)(uintptr_t)B.x_count_block;
    g_map.byn = *(const int32_t*)(uintptr_t)B.y_count_block;
    g_map.zn = *(const int32_t*)(uintptr_t)B.z_count_block;
    if (!g_map.xs || g_map.bxn <= 0 || g_map.byn <= 0 || g_map.zn <= 0 ||
        g_map.bxn > MOST_BLOCKS || g_map.byn > MOST_BLOCKS || g_map.zn > MOST_LEVELS) return false;
    g_map.x_end = g_map.bxn * 16;
    g_map.y_end = g_map.byn * 16;
    return true;
}
enum : uint8_t { WL_CANOPY = 1, WL_TREE = 2, WL_OPEN = 4, WL_NO_FOG = 8 };   // (wl_tt, from native.lua; 8: ice wall / brook bed)

// ---------------------------------------------------------------------
// THE FOG (detailed_weather.lua: find_outdoors, fog_tile, the drawing)
// ---------------------------------------------------------------------
// WHICH TILES: at the view's level, above ground (outside, or not
// subterranean) and not hidden, or open sky with no map block; not under
// water (water with anything but open air above it: a lake, or ice over it).
// HOW DEEP: how many levels down the view shows there, through open space
// (EMPTY, RAMP_TOP), stopping at water, up to 8: the fog of lower ground
// drifts slower (Lua's steps_at, by depth) and shows other shapes (its row
// moved 3 a level).
// THE SHEET TILE: the patch drifted `steps` steps east (negative: west):
// frame steps mod frames; the cell moves a tile for each whole tile's worth;
// tile ((level - 1) * patch^2 + cy * patch + cx) * frames + frame (Lua's
// index less 1).
// WHERE: the main view's interface layer, where detailed_weather.lua's
// overlay painted it (DFHack's Screen.cpp: doSetTile_map), but only where
// the game and DFHack's other overlays left it empty (the overlay painted
// over them). FOG OVER WATER sets the levels below's interface, not this.
static void draw_weather_fog() {
    if (!B.wfog_on || B.wfog_level <= 0 || B.wfog_tex_n <= 0 || B.wfog_patch <= 0 || B.wfog_frames <= 0 ||
        !B.have_drawn || !B.off_interface || !B.main_viewport || !B.off_dim_x || !B.off_dim_y ||
        !B.off_tiletype || !B.off_designation || !B.outside_mask) return;
    if (!map_ready()) return;
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;
    const double t0 = ticks_now();
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
	int32_t* const itf = *(int32_t* const*)(main + B.off_interface);
    if (!itf || !kept_ready(g_wfog_kept, dx, dy)) return;
    // Detect a mode-wide interface fill (e.g., DF's Mining/Woodcutting tile)
    // so fog draws over it while still yielding to sparse cursors or overlays.
    int32_t fill_tex = 0;
    {
        const int32_t total = dx * dy;
        const int32_t step = total > 64 ? total / 64 : 1;
        int32_t cand = 0, votes = 0;
        for (int32_t k = 0; k < total; k += step) {
            const int32_t v = itf[k];
            if (v == 0) continue;
            if (v == cand) votes++;
            else if (votes == 0) { cand = v; votes = 1; }
            else votes--;
        }
        if (cand != 0) {
            int32_t seen = 0, sampled = 0;
            for (int32_t k = 0; k < total; k += step) {
                if (itf[k] == cand) seen++;
                sampled++;
            }
            if (seen * 2 >= sampled) fill_tex = cand;
        }
    }
    const int32_t patch = B.wfog_patch, frames = B.wfog_frames;
    const int32_t n_tex = B.wfog_tex_n < WFOG_TEX ? B.wfog_tex_n : WFOG_TEX;
    int32_t frame_at[WFOG_DEPTHS], moved_at[WFOG_DEPTHS];   // each depth's frame and whole tiles moved
    for (int d = 0; d < WFOG_DEPTHS; d++) {
        frame_at[d] = pos_mod(B.wfog_steps[d], frames);
        moved_at[d] = floor_div(B.wfog_steps[d], frames);
    }
    const int32_t row0 = (B.wfog_level - 1) * patch * patch;
    const uint32_t outside = B.outside_mask, under = B.subterranean_mask, hidden = B.hidden_mask, flow = B.flow_mask;
    const uint8_t* const tt = B.wl_tt;
    const int32_t* const bg = B.off_background ? *(int32_t* const*)(main + B.off_background) : nullptr;
    const int32_t black = B.black_texpos;
    uint32_t cells = 0, drawn = 0, taken = 0, full = 0;
    Kept* const kept = g_wfog_kept.e;
    int32_t kn = g_wfog_kept.n;
    const int32_t cap = g_wfog_kept.cap;
    for (int32_t sx = 0; sx < dx; sx++) {
        const int32_t x = B.drawn_x + sx;
        if (x < 0 || x >= g_map.x_end) continue;
        const int32_t bx = x >> 4;
        int32_t sy = 0;
        while (sy < dy) {   // (a run of cells in one map block at a time)
            const int32_t y = B.drawn_y + sy;
            const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
            const int32_t end = sy + run < dy ? sy + run : dy;
            if (y < 0 || y >= g_map.y_end) { sy = end; continue; }
            const int32_t by = y >> 4;
            // this column's blocks from the view's level down
            const uint8_t* col[WFOG_DEPTHS];
            for (int d = 0; d < WFOG_DEPTHS; d++) col[d] = z - d >= 0 ? block_ptr(bx, by, z - d) : nullptr;
            for (; sy < end; sy++) {
                const int32_t yy = B.drawn_y + sy;
                const int t = tile_of(x, yy);
                if (col[0]) {
                    const uint32_t d = des_in(col[0], t);
                    // Water/magma, underground, hidden, frozen water (ice walls), brook beds, and
                    // solid black wall interiors get no fog: surface fog draws on the open air/brook
                    // top level above them (flow == 0).
                    if (d & flow) continue;
                    if (!((d & outside) || !(d & under)) || (d & hidden)) continue;
                    const uint16_t bt0 = type_in(col[0], t);
                    const uint8_t wf0 = bt0 < TT_TABLE ? tt[bt0] : 0;
                    if (wf0 & WL_NO_FOG) continue;
                    if (!(wf0 & WL_OPEN) && bg && black != 0 && bg[sx * dy + sy] == black) continue;
                }
                int depth = 0;   // (how deep the view shows here)
                while (depth < WFOG_DEPTHS - 1) {
                    const uint8_t* const b = col[depth];
                    if (b) {
                        const uint16_t bt = type_in(b, t);
                        if (!(bt < TT_TABLE && (tt[bt] & WL_OPEN)) || (des_in(b, t) & flow)) break;
                    }
                    depth++;
                }
                cells++;
                const int32_t cx = pos_mod(x - moved_at[depth], patch), cy = pos_mod(yy + depth * 3, patch);
                const int32_t idx = (row0 + cy * patch + cx) * frames + frame_at[depth];
                const int32_t tex = (idx >= 0 && idx < n_tex) ? B.wfog_tex[idx] : 0;
                if (tex <= 0) continue;
                const int32_t i = sx * dy + sy;
                const int32_t prev = itf[i];
                if (prev != 0 && prev != fill_tex) { taken++; continue; }
                if (kn >= cap) { full++; continue; }
                itf[i] = tex;
                kept[kn++] = Kept{itf, i, prev, tex};
                drawn++;
            }
        }
    }
    g_wfog_kept.n = kn;
    g_wfog_kept.last = itf;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.wfog_frames_drawn++;
    B.wfog_drawn += drawn;
    B.wfog_cells_last = cells;
    B.wfog_drawn_last = drawn;
    B.wfog_taken_last = taken;
    B.wfog_kept_full += full;
    B.wfog_us_total += us;
    if (us > B.wfog_us_max) B.wfog_us_max = us;
}

// ---------------------------------------------------------------------
// THE LEAVES (leaves.lua: find_over, decide, sheet_tile, apply)
// ---------------------------------------------------------------------
// WHICH TILES: at the view's level, each tile under the canopy (BRANCH,
// TWIG, TRUNK_BRANCH) of a tree whose raws shed, at that level or up to 6
// above with nothing solid between (a tree that sheds nothing keeps the
// rest off); not hidden or subterranean; and a tile next to one, west,
// east, north, south in that order, if it's outside (they drift out from
// under the edge). Worked out a map block at a time when first drawn and
// kept, as leaves.lua kept each tile, and again after leaf_recheck frames
// (leaves.lua forgot all every 60 s, for growth and felling).
// WHICH TREE: as DFHack's getPlantAtTile, the first plant in the mid level
// tile's list (column_index at the tile's (x / 48) * 3, (y / 48) * 3) at
// that tile, or whose body covers it there (x index dim_x / 2 - pos.x % 48
// + x % 48, the level body_height high, a tile with any of its low 7 bits).
// Each block and level's trees are found once (TREE MAPS), a pass over the
// list, and kept alongside.
// WHERE THE PLANTS ARE READ: on the game thread, in the prerender call
// (plan_leaves), as PATHS reads the grass: the simulation runs on that
// thread between frames, so a sapling grown or a tree felled can move or
// free the plants while the main thread is in the hook. The hook only
// draws from the maps made there (draw_leaves).
// THE SHEET TILE: the tree's seed ((pos.x * 7919 + pos.y * 104729) mod
// 65521) shifts the patch and its place in the loop: x + seed mod cells,
// y + (seed / cells) mod cells, frame + seed / cells^2; tile (((heaviness -
// 1) * winds + wind - 1) * cells^2 + cell) * frames + frame. What falls on
// each tree, the sheet and heaviness, is leaves.lua's (leaf_spec, by raw).
static const int LEAF_LEVELS_ABOVE = 6;   // leaves.lua: LEVELS_ABOVE
static const int LEAF_SLOTS = 4096;       // the maps' hash (a power of 2)
static const int LEAF_POOL = 2048;        // maps kept at most (about 2 MB): all let go when full
enum : uint8_t { LEAF_FALLS = 1, LEAF_TREES = 2 };
// A map block's 256 tiles at one level, each (raw + 1) << 16 | seed, 0 for none: what falls on each tile
// (LEAF_FALLS, at the view's level), or which tree each tile belongs to (LEAF_TREES)
struct LeafMap { int32_t bx, by, z; uint8_t kind, pad[3]; uint32_t made; uint32_t v[256]; };
static LeafMap* g_leaf_pool = nullptr;
static int32_t* g_leaf_slot = nullptr;   // index + 1 into the pool, 0 empty
static int32_t  g_leaf_used = 0;
static uint32_t g_leaf_frame = 1, g_leaf_tables_seen = 0;
static int32_t  g_leaf_bxn = 0, g_leaf_byn = 0, g_leaf_zn = 0;   // the map's size the maps were made for
static uint32_t g_leaf_bad = 0;

static void leaf_forget() {
    if (g_leaf_slot) memset(g_leaf_slot, 0, sizeof(int32_t) * LEAF_SLOTS);
    g_leaf_used = 0;
}
static inline uint32_t leaf_hash(uint8_t kind, int32_t bx, int32_t by, int32_t z) {
    const uint32_t k = ((uint32_t)bx * 73856093u) ^ ((uint32_t)by * 19349663u) ^ ((uint32_t)z * 83492791u) ^ ((uint32_t)kind * 2654435761u);
    return (k ^ (k >> 15)) & (LEAF_SLOTS - 1);
}
// The map of `kind` for block (bx, by) at level z, made (zeroed, made = 0) if `make` and there's none
static LeafMap* leaf_find(uint8_t kind, int32_t bx, int32_t by, int32_t z, bool make) {
    if (!g_leaf_pool) {
        g_leaf_pool = (LeafMap*)calloc(LEAF_POOL, sizeof(LeafMap));
        g_leaf_slot = (int32_t*)calloc(LEAF_SLOTS, sizeof(int32_t));
        if (!g_leaf_pool || !g_leaf_slot) { free(g_leaf_pool); free(g_leaf_slot); g_leaf_pool = nullptr; g_leaf_slot = nullptr; return nullptr; }
    }
    uint32_t h = leaf_hash(kind, bx, by, z);
    for (int i = 0; i < LEAF_SLOTS; i++, h = (h + 1) & (LEAF_SLOTS - 1)) {
        const int32_t s = g_leaf_slot[h];
        if (!s) break;
        LeafMap& m = g_leaf_pool[s - 1];
        if (m.kind == kind && m.bx == bx && m.by == by && m.z == z) return &m;
    }
    if (!make) return nullptr;
    if (g_leaf_used >= LEAF_POOL || g_leaf_used >= LEAF_SLOTS * 3 / 4) {   // (full: all let go, made again as seen)
        leaf_forget();
        B.leaf_pool_full++;
        h = leaf_hash(kind, bx, by, z);
    }
    while (g_leaf_slot[h]) h = (h + 1) & (LEAF_SLOTS - 1);
    LeafMap& m = g_leaf_pool[g_leaf_used];
    g_leaf_slot[h] = ++g_leaf_used;
    m.bx = bx; m.by = by; m.z = z; m.kind = kind; m.made = 0;
    memset(m.v, 0, sizeof m.v);
    return &m;
}
// TREE MAPS: which tree each tile of a block belongs to at a level, from its mid level tile's plants
static void leaf_trees(LeafMap& m) {
    memset(m.v, 0, sizeof m.v);
    m.made = g_leaf_frame;
    if (!B.column_index || !B.off_col_plants || !B.off_plant_tree) return;
    void* const* cs = *(void* const* const*)(uintptr_t)B.column_index;
    const int32_t mbx = (m.bx / 3) * 3, mby = (m.by / 3) * 3;   // (getPlantAtTile: (x / 48) * 3)
    if (!cs || mbx >= g_map.bxn || mby >= g_map.byn) return;
    void* const* ys = (void* const*)cs[mbx];
    if (!ys) return;
    const uint8_t* col = (const uint8_t*)ys[mby];
    if (!col) return;
    const uint8_t* const* first = *(const uint8_t* const* const*)(col + B.off_col_plants);
    const uint8_t* const* last = *(const uint8_t* const* const*)(col + B.off_col_plants + 8);
    if (!first || last < first || last - first > 200000) return;
    const int32_t x0 = m.bx * 16, y0 = m.by * 16;
    for (const uint8_t* const* p = first; p < last; p++) {
        const uint8_t* plant = *p;
        if (!plant) continue;
        const int16_t* pos = (const int16_t*)(plant + B.off_plant_pos);
        const int32_t px = pos[0], py = pos[1], pz = pos[2];
        if (px < 0 || py < 0) continue;
        const int32_t raw = *(const int16_t*)(plant + B.off_plant_material);
        const uint32_t val = (raw >= 0 && raw < 65535) ? ((uint32_t)(raw + 1) << 16) | (uint32_t)((px * 7919 + py * 104729) % 65521) : 0;
        // (getPlantAtTile: a plant at the tile itself first, in the list's order)
        if (pz == m.z && px >= x0 && px < x0 + 16 && py >= y0 && py < y0 + 16) {
            const int t = tile_of(px, py);
            if (!m.v[t]) m.v[t] = val;
        }
        const uint8_t* ti = *(const uint8_t* const*)(plant + B.off_plant_tree);
        if (!ti) continue;
        const int32_t zd = m.z - pz;
        const int32_t height = *(const int32_t*)(ti + B.off_tree_height);
        const int32_t dimx = *(const int32_t*)(ti + B.off_tree_dim_x), dimy = *(const int32_t*)(ti + B.off_tree_dim_y);
        if (height <= 0 || height > 256 || dimx <= 0 || dimx > 256 || dimy <= 0 || dimy > 256) { g_leaf_bad++; continue; }
        if (zd < 0 || zd >= height) continue;
        // the tiles it covers: x index dim_x / 2 - pos.x % 48 + x % 48 (trees never cross a mid level tile)
        const int32_t tx0 = px - dimx / 2, ty0 = py - dimy / 2;   // (where its x and y index are 0: x - pos.x = x % 48 - pos.x % 48 within one)
        const int32_t ax = tx0 > x0 ? tx0 : x0, bxe = tx0 + dimx < x0 + 16 ? tx0 + dimx : x0 + 16;
        const int32_t ay = ty0 > y0 ? ty0 : y0, bye = ty0 + dimy < y0 + 16 ? ty0 + dimy : y0 + 16;
        if (ax >= bxe || ay >= bye) continue;
        const uint16_t* const* body = *(const uint16_t* const* const*)(ti + B.off_tree_body);
        if (!body) continue;
        const uint16_t* lvl = body[zd];
        if (!lvl) continue;
        for (int32_t x = ax; x < bxe; x++) {
            const int32_t xi = dimx / 2 - px % 48 + x % 48;
            if (xi < 0 || xi >= dimx) continue;
            for (int32_t y = ay; y < bye; y++) {
                const int32_t yi = dimy / 2 - py % 48 + y % 48;
                if (yi < 0 || yi >= dimy) continue;
                if (lvl[xi + yi * dimx] & 0x7F) {
                    const int t = tile_of(x, y);
                    if (!m.v[t]) m.v[t] = val;
                }
            }
        }
    }
}
// The shedding tree over (x, y) at level z, (raw + 1) << 16 | seed, or 0 (leaves.lua: find_over)
static uint32_t leaf_over(int32_t x, int32_t y, int32_t z) {
    if (x < 0 || y < 0 || x >= g_map.x_end || y >= g_map.y_end) return 0;
    const int32_t bx = x >> 4, by = y >> 4;
    const int t = tile_of(x, y);
    const uint8_t* blk = block_ptr(bx, by, z);
    if (blk && (des_in(blk, t) & (B.hidden_mask | B.subterranean_mask))) return 0;
    for (int32_t lv = z; lv <= z + LEAF_LEVELS_ABOVE && lv < g_map.zn; lv++) {
        const uint8_t* b = lv == z ? blk : block_ptr(bx, by, lv);
        if (!b) continue;
        const uint16_t tt = type_in(b, t);
        const uint8_t f = tt < TT_TABLE ? B.wl_tt[tt] : 0;
        if (f & WL_TREE) {
            if (f & WL_CANOPY) {
                LeafMap* m = leaf_find(LEAF_TREES, bx, by, lv, true);
                if (m && (!m->made || g_leaf_frame - m->made > B.leaf_recheck)) leaf_trees(*m);
                const uint32_t v = m ? m->v[t] : 0;
                if (v) {   // (a tree: it sheds, or it keeps the rest off)
                    const int32_t raw = (int32_t)(v >> 16) - 1;
                    return (raw >= 0 && raw < LEAF_RAWS && B.leaf_sheds[raw]) ? v : 0;
                }
            }
        } else if (lv > z && !(f & WL_OPEN)) return 0;   // (a floor or roof between)
    }
    return 0;
}
// A block's falls at the view's level (leaves.lua: decide), worked out whole
static void leaf_work_out(LeafMap& m) {
    uint32_t over[18][18];   // the block and a tile round it
    const int32_t x0 = m.bx * 16 - 1, y0 = m.by * 16 - 1;
    for (int i = 0; i < 18; i++) for (int j = 0; j < 18; j++) over[i][j] = leaf_over(x0 + i, y0 + j, m.z);
    const uint8_t* blk = block_ptr(m.bx, m.by, m.z);
    const uint32_t keep_off = B.hidden_mask | B.subterranean_mask;
    for (int i = 1; i <= 16; i++) {
        for (int j = 1; j <= 16; j++) {
            uint32_t v = over[i][j];
            const int t = tile_of(x0 + i, y0 + j);
            if (!v) {
                v = over[i - 1][j] ? over[i - 1][j] : over[i + 1][j] ? over[i + 1][j] : over[i][j - 1] ? over[i][j - 1] : over[i][j + 1];
                if (v && blk) {   // (only onto open ground: not under a roof or underground)
                    const uint32_t d = des_in(blk, t);
                    if ((d & keep_off) || !(d & B.outside_mask)) v = 0;
                }
            }
            m.v[t] = v;
        }
    }
    m.made = g_leaf_frame;
    B.leaf_blocks_worked++;
}
static const int LEAF_RECHECKS_A_FRAME = 8;   // blocks worked out again a frame at most (new ones: all)
// (game thread, prerender: the view as the game is about to draw it) every block in view worked out if it
// has no map yet, and up to LEAF_RECHECKS_A_FRAME whose map is older than leaf_recheck frames
static void plan_leaves() {
    g_leaf_frame++;
    if (!B.leaf_on || !B.leaf_any || !B.have_drawn || !B.main_viewport || !B.off_dim_x || !B.off_dim_y ||
        !B.off_tiletype || !B.off_designation || !B.outside_mask) return;
    if (!map_ready()) return;
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;
    // (another map's size, or Lua's tables changed: every map let go)
    if (g_map.bxn != g_leaf_bxn || g_map.byn != g_leaf_byn || g_map.zn != g_leaf_zn || B.leaf_tables != g_leaf_tables_seen) {
        leaf_forget();
        g_leaf_bxn = g_map.bxn; g_leaf_byn = g_map.byn; g_leaf_zn = g_map.zn;
        g_leaf_tables_seen = B.leaf_tables;
    }
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    const uint32_t recheck = B.leaf_recheck ? B.leaf_recheck : 3600;
    const int32_t bx0 = (B.drawn_x > 0 ? B.drawn_x : 0) >> 4, by0 = (B.drawn_y > 0 ? B.drawn_y : 0) >> 4;
    int32_t bx1 = (B.drawn_x + dx - 1) >> 4, by1 = (B.drawn_y + dy - 1) >> 4;
    if (bx1 >= g_map.bxn) bx1 = g_map.bxn - 1;
    if (by1 >= g_map.byn) by1 = g_map.byn - 1;
    uint32_t worked = 0;
    int rechecks = LEAF_RECHECKS_A_FRAME;
    for (int32_t bx = bx0; bx <= bx1; bx++) {
        for (int32_t by = by0; by <= by1; by++) {
            LeafMap* m = leaf_find(LEAF_FALLS, bx, by, z, true);
            if (!m) continue;
            if (m->made && !(g_leaf_frame - m->made > recheck && rechecks > 0)) continue;
            if (m->made) rechecks--;
            leaf_work_out(*m);
            worked++;
            m = leaf_find(LEAF_FALLS, bx, by, z, true);   // (the pool may have been let go while its trees were found)
            if (m && !m->made) { leaf_work_out(*m); worked++; }
        }
    }
    B.leaf_worked_last = worked;
    B.leaf_maps_kept = (uint32_t)g_leaf_used;
    B.leaf_trees_bad = g_leaf_bad;
}
// (main thread, in the hook) the leaves drawn from the maps made in the prerender call
static void draw_leaves() {
    if (!B.leaf_on || !B.leaf_any || !B.have_drawn || !B.off_projectile || !B.main_viewport || !B.off_dim_x ||
        !B.off_dim_y || !B.off_tiletype || !B.off_designation || !B.outside_mask) return;
    const int32_t cells_ = B.leaf_cells, frames = B.leaf_frames, winds = B.leaf_winds, heavies = B.leaf_heavies;
    const int32_t frame = B.leaf_frame, wind = B.leaf_wind;
    if (cells_ <= 0 || frames <= 0 || winds <= 0 || heavies <= 0 || wind < 1 || wind > winds || frame < 0 || frame >= frames) return;
    if (!map_ready()) return;
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;
    if (g_map.bxn != g_leaf_bxn || g_map.byn != g_leaf_byn || g_map.zn != g_leaf_zn) return;   // (not planned for this map)
    const double t0 = ticks_now();
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    int32_t* const prj = *(int32_t* const*)(main + B.off_projectile);
    if (!prj || !kept_ready(g_leaf_kept, dx, dy)) return;
    const int32_t c2 = cells_ * cells_;
    uint32_t cells = 0, drawn = 0, full = 0;
    Kept* const kept = g_leaf_kept.e;
    int32_t kn = g_leaf_kept.n;
    const int32_t cap = g_leaf_kept.cap;
    for (int32_t sx = 0; sx < dx; sx++) {
        const int32_t x = B.drawn_x + sx;
        if (x < 0 || x >= g_map.x_end) continue;
        const int32_t bx = x >> 4;
        int32_t sy = 0;
        while (sy < dy) {
            const int32_t y = B.drawn_y + sy;
            const int32_t run = y >= 0 ? 16 - (y & 15) : 1;
            const int32_t end = sy + run < dy ? sy + run : dy;
            if (y < 0 || y >= g_map.y_end) { sy = end; continue; }
            const int32_t by = y >> 4;
            const LeafMap* m = leaf_find(LEAF_FALLS, bx, by, z, false);
            if (!m || !m->made) { sy = end; continue; }   // (not worked out in the prerender call: none this frame)
            for (; sy < end; sy++) {
                const int32_t yy = B.drawn_y + sy;
                const uint32_t v = m->v[tile_of(x, yy)];
                if (!v) continue;
                cells++;
                const int32_t raw = (int32_t)(v >> 16) - 1;
                const uint16_t spec = (raw >= 0 && raw < LEAF_RAWS) ? B.leaf_spec[raw] : 0;
                const int32_t sheet = spec & 0xff, heavy = spec >> 8;
                if (sheet < 1 || sheet > LEAF_SHEETS || heavy < 1 || heavy > heavies) continue;
                const int32_t seed = (int32_t)(v & 0xffff);
                const int32_t lx = x + seed % cells_, ly = yy + seed / cells_ % cells_;
                const int32_t fr = (frame + seed / c2) % frames;
                const int32_t cell = (ly % cells_) * cells_ + lx % cells_;
                const int32_t idx = (((heavy - 1) * winds + (wind - 1)) * c2 + cell) * frames + fr;
                const int32_t n_tex = B.leaf_tex_n[sheet - 1] < LEAF_TEX ? B.leaf_tex_n[sheet - 1] : LEAF_TEX;
                const int32_t tex = (idx >= 0 && idx < n_tex) ? B.leaf_tex[sheet - 1][idx] : 0;
                if (tex <= 0) continue;   // (nothing drawn in that tile of the sheet this frame)
                const int32_t i = sx * dy + sy;
                if (prj[i] != 0) continue;   // (the game's own projectile there)
                if (kn >= cap) { full++; continue; }
                prj[i] = tex;
                kept[kn++] = Kept{prj, i, 0, tex};
                drawn++;
            }
        }
    }
    g_leaf_kept.n = kn;
    g_leaf_kept.last = prj;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.leaf_frames_drawn++;
    B.leaf_drawn += drawn;
    B.leaf_cells_last = cells;
    B.leaf_drawn_last = drawn;
    B.leaf_kept_full += full;
    B.leaf_us_total += us;
    if (us > B.leaf_us_max) B.leaf_us_max = us;
}

// =====================================================================
// THE SPATTER DRAWN HERE (test 15Y): spatter.lua's fallen fruit, nuts,
// leaves and blood in the grass, worked out and painted here each frame
// =====================================================================
// WHAT (spatter.lua): each piece of spatter on a grass tile is drawn in
// the grass rather than on it: in the spatter layer, thinned by how much
// has fallen there (the game draws the same picture however much) with a
// faint shadow under each piece; and in the item layer, if free, the
// tile's own grass cut down to its brightest pixels (its blades), so they
// stand in front of the fruit.
// WHY HERE: spatter.lua read the spatter layer every frame through DFHack
// (2.6 ms a frame in a snowy view, where nearly every cell has a piece),
// made its textures in Lua, and wrote both layers without ever putting
// them back (a cell the game didn't redraw kept an old frame's).
// WHICH CELLS: the main view's, whose spatter isn't Detailed Weather's own
// (the snow's page and textures; the colour's table copies; anything the
// colour leaves be) on a cell whose ground's original is grass (Lua's grass
// table, spat_grass). The colour's screen copy of a spatter (the fruit in
// the weather's colours) is what's drawn, through its original's mask.
// HOW MUCH HAS FALLEN (spatter.lua: fallen, share_for): the item spatter
// events of the tile's block at the view's level, their amounts summed per
// tile, read in the prerender call on the game thread (the simulation moves
// them meanwhile), kept 300 frames as spatter.lua kept them 5 s. The share
// of pieces kept: amount / 8000, from 0.05, in tenths; no item spatter
// there (blood, mud): all of them.
// THE PAINTING, as spatter.lua's, pixel for pixel: the original's pieces
// (runs of pixels with alpha 128 or more, touching diagonally too, soft
// edge pixels joined to the piece beside them), each kept or left out by a
// hash of its number and the pattern ((x * 7 + y * 13) mod 4); the shadow
// (70, or 35 two pixels down) under a kept pixel; the blades from the
// grass original's brightest 35% (fading in over 15%, covering 85%). Into
// blanks Lua keeps ready (THE BLANKS, shared with CRACKS IN PLACE), at most
// SPAT_PAINT_US a frame, kept by picture (PICTURES, NOT NUMBERS) so a look's
// copy with the same picture finds them.
static uint8_t g_spat_grass[TEX_MAP];   // each original that's grass (1), filled by Lua (spat_grass)
static const double SPAT_SHADOW_R = 18, SPAT_SHADOW_G = 22, SPAT_SHADOW_B = 10;
static const int SPAT_SHADOW_ALPHA = 70;
static const double SPAT_BLADES = 0.35, SPAT_BLADE_SOFT = 0.15, SPAT_BLADE_COVER = 0.85;
static const int SPAT_FULL_AMOUNT = 8000;
static const double SPAT_LEAST_SHARE = 0.05;
static const int SPAT_VARIANTS = 4;
static const double SPAT_PAINT_US = 3000;   // (spatter.lua: BAKE_MS)
static const uint32_t SPAT_AMOUNTS_FRAMES = 300;   // (spatter.lua: AMOUNTS_KEEP_MS, 5 s)
enum : uint8_t { LEAF_AMOUNTS = 3 };   // (a block's fallen amounts, in the leaves' maps)
static inline uint32_t spat_pack(int r, int g, int b, int a) { return ((uint32_t)a << 24) | ((uint32_t)b << 16) | ((uint32_t)g << 8) | (uint32_t)r; }

// The pieces of a picture (spatter.lua: pieces): each pixel's piece number, 0 where see-through
static void spat_pieces(const uint32_t* px, uint16_t* label) {
    static const int T = PIC_TILE;
    memset(label, 0, sizeof(uint16_t) * T * T);
    static int32_t stack[T * T * 9];
    uint16_t count = 0;
    for (int start = 0; start < T * T; start++) {
        if (label[start] != 0 || (px[start] >> 24) < 128) continue;
        count++;
        int sp = 0;
        stack[sp++] = start;
        label[start] = count;
        while (sp > 0) {
            const int i = stack[--sp];
            const int x = i % T, y = i / T;
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    const int nx = x + dx, ny = y + dy;
                    if (nx >= 0 && ny >= 0 && nx < T && ny < T) {
                        const int n = ny * T + nx;
                        if (label[n] == 0 && (px[n] >> 24) >= 128) { label[n] = count; stack[sp++] = n; }
                    }
                }
            }
        }
    }
    static const int D[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
    for (int i = 0; i < T * T; i++) {
        if (label[i] != 0 || (px[i] >> 24) == 0) continue;
        const int x = i % T, y = i / T;
        for (int d = 0; d < 4; d++) {
            const int nx = x + D[d][0], ny = y + D[d][1];
            if (nx >= 0 && ny >= 0 && nx < T && ny < T && (px[ny * T + nx] >> 24) >= 128) { label[i] = label[ny * T + nx]; break; }
        }
    }
}
// Whether piece n is kept for a share and a pattern (spatter.lua: kept)
static inline bool spat_kept(int n, double share, int variant) {
    if (share >= 1) return true;
    const uint64_t h = ((uint64_t)n * 2654435761ull + (uint64_t)variant * 40503ull) % 4294967296ull;
    return (double)(h % 1000) / 1000 < share;
}
// The spatter `t_px` (the weather's copy, or the game's own) through the mask of its original `o_px` for a share
// and pattern (spatter.lua: mask_for, bake_spatter), into `out`
static void spat_make_piece(const uint32_t* t_px, const uint32_t* o_px, double share, int variant, uint32_t* out) {
    static const int T = PIC_TILE;
    uint16_t label[T * T];
    const bool thin = share < 1;
    if (thin) spat_pieces(o_px, label);
    int alpha[T * T];
    for (int i = 0; i < T * T; i++) {
        const int n = thin ? label[i] : 0;
        alpha[i] = (n != 0 && !spat_kept(n, share, variant)) ? 0 : (int)(o_px[i] >> 24);
    }
    auto alpha_at = [&](int x, int y) -> int { return (x < 0 || y < 0 || x >= T || y >= T) ? 0 : alpha[y * T + x]; };
    for (int y = 0; y < T; y++) {
        for (int x = 0; x < T; x++) {
            const int i = y * T + x;
            const int oa = (int)(o_px[i] >> 24);
            const double show = oa > 0 ? (double)alpha[i] / oa : 0;
            int s = 0;
            if (alpha[i] < 128) {
                double above = (double)alpha_at(x, y - 1);
                const double l = alpha_at(x - 1, y - 1) * 0.5, r = alpha_at(x + 1, y - 1) * 0.5;
                if (l > above) above = l;
                if (r > above) above = r;
                s = above >= 128 ? SPAT_SHADOW_ALPHA : (alpha_at(x, y - 2) >= 128 ? SPAT_SHADOW_ALPHA / 2 : 0);
            }
            const uint32_t p = t_px[i];
            const double a = (double)(p >> 24) * show;
            if ((double)s > a) out[i] = spat_pack((int)SPAT_SHADOW_R, (int)SPAT_SHADOW_G, (int)SPAT_SHADOW_B, s);
            else out[i] = spat_pack((int)(p & 255), (int)((p >> 8) & 255), (int)((p >> 16) & 255), (int)floor(a + 0.5));
        }
    }
}
// The grass `g_px` showing (the look's copy, or a leaning frame) cut down to its blades, by the brightness of its
// original `o_px` (spatter.lua: blade_mask, bake_blades), into `out`
static void spat_make_blades(const uint32_t* g_px, const uint32_t* o_px, uint32_t* out) {
    static const int T = PIC_TILE;
    double values[T * T], sorted[T * T];
    for (int i = 0; i < T * T; i++) {
        const uint32_t p = o_px[i];
        values[i] = (double)(p & 255) * 0.299 + (double)((p >> 8) & 255) * 0.587 + (double)((p >> 16) & 255) * 0.114;
        sorted[i] = values[i];
    }
    std::sort(sorted, sorted + T * T);
    const int n = T * T;
    int fi = (int)floor(n * (1 - SPAT_BLADES));
    if (fi < 1) fi = 1;
    int ti = (int)floor(n * (1 - SPAT_BLADES + SPAT_BLADE_SOFT));
    if (ti > n) ti = n;
    if (ti < 1) ti = 1;
    const double from = sorted[fi - 1], to = sorted[ti - 1];
    const double span = to - from > 1 ? to - from : 1;
    for (int i = 0; i < T * T; i++) {
        double m = (values[i] - from) / span;
        m = m < 0 ? 0 : m > 1 ? 1 : m;
        const double mask = m * SPAT_BLADE_COVER * (double)(o_px[i] >> 24) / 255;
        const uint32_t p = g_px[i];
        out[i] = spat_pack((int)(p & 255), (int)((p >> 8) & 255), (int)((p >> 16) & 255), (int)floor(mask * 255 + 0.5));
    }
}

// THE BAKES: each painted texture by its pictures and what it's for (a piece's share and pattern; blades)
struct SpatBake { uint64_t a, b; uint32_t extra; int32_t tex; };
static const int SPAT_BAKES = 16384;   // (a power of 2; 384 KB; all let go at 3/4, painted again as seen)
static SpatBake* g_spat_bakes = nullptr;
static int g_spat_used = 0;
static uint32_t g_spat_tables_seen = 0, g_spat_world_seen = 0;
static SpatBake* spat_bake_find(uint64_t a, uint64_t b, uint32_t extra, bool make) {
    if (!g_spat_bakes) {
        g_spat_bakes = (SpatBake*)calloc(SPAT_BAKES, sizeof(SpatBake));
        if (!g_spat_bakes) return nullptr;
    }
    const uint64_t k = (a * 0x9E3779B97F4A7C15ull) ^ (b * 0xC2B2AE3D27D4EB4Full) ^ ((uint64_t)extra * 0x165667B19E3779F9ull);
    uint32_t h = (uint32_t)(k >> 50) & (SPAT_BAKES - 1);
    for (int i = 0; i < SPAT_BAKES; i++, h = (h + 1) & (SPAT_BAKES - 1)) {
        SpatBake& e = g_spat_bakes[h];
        if (!e.a && !e.b) {
            if (!make) return nullptr;
            if (g_spat_used >= SPAT_BAKES * 3 / 4) {   // (full: all let go; their textures are never freed, as in Lua)
                memset(g_spat_bakes, 0, sizeof(SpatBake) * SPAT_BAKES);
                g_spat_used = 0;
                B.spat_bakes_full++;
                return spat_bake_find(a, b, extra, make);
            }
            e.a = a; e.b = b ? b : 1; e.extra = extra; e.tex = 0;
            g_spat_used++;
            return &e;
        }
        if (e.a == a && e.b == (b ? b : 1) && e.extra == extra) return &e;
    }
    return nullptr;
}
// A blank painted with `px`: its texture number, or 0 (none ready)
static int32_t spat_paint(const uint32_t* px) {
    if (B.crack_b_tail == B.crack_b_head) { B.spat_no_blank++; return 0; }
    const CrackBlank bl = B.crack_b[B.crack_b_tail % CRACK_BLANKS];
    B.crack_b_tail++;
    if (!bl.addr || bl.tex <= 0) return 0;
    memcpy((void*)(uintptr_t)bl.addr, px, sizeof(uint32_t) * PIC_TILE * PIC_TILE);
    B.spat_painted++;
    return bl.tex;
}

// (game thread, prerender) each block in view's fallen amounts at the view's level, read again after 300 frames
static void plan_spatter() {
    if (!B.spat_on || !B.spat_vtable || !B.off_isp_amount || !B.off_block_events || !B.have_drawn ||
        !B.main_viewport || !B.off_dim_x || !B.off_dim_y) return;
    if (!map_ready()) return;
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;
    if (g_map.bxn != g_leaf_bxn || g_map.byn != g_leaf_byn || g_map.zn != g_leaf_zn) {   // (another map: the maps let go)
        leaf_forget();
        g_leaf_bxn = g_map.bxn; g_leaf_byn = g_map.byn; g_leaf_zn = g_map.zn;
    }
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    const int32_t bx0 = (B.drawn_x > 0 ? B.drawn_x : 0) >> 4, by0 = (B.drawn_y > 0 ? B.drawn_y : 0) >> 4;
    int32_t bx1 = (B.drawn_x + dx - 1) >> 4, by1 = (B.drawn_y + dy - 1) >> 4;
    if (bx1 >= g_map.bxn) bx1 = g_map.bxn - 1;
    if (by1 >= g_map.byn) by1 = g_map.byn - 1;
    for (int32_t bx = bx0; bx <= bx1; bx++) {
        for (int32_t by = by0; by <= by1; by++) {
            LeafMap* m = leaf_find(LEAF_AMOUNTS, bx, by, z, true);
            if (!m || (m->made && g_leaf_frame - m->made <= SPAT_AMOUNTS_FRAMES)) continue;
            memset(m->v, 0, sizeof m->v);
            m->made = g_leaf_frame ? g_leaf_frame : 1;
            const uint8_t* blk = block_ptr(bx, by, z);
            void* const* first; void* const* last;
            if (!blk || !events_of(blk, first, last)) continue;
            for (void* const* e = first; e < last; e++) {
                const uint8_t* ev = (const uint8_t*)*e;
                if (!ev || *(const uint64_t*)ev != B.spat_vtable) continue;
                const int32_t* amount = (const int32_t*)(ev + B.off_isp_amount);   // [x][y]
                for (int t = 0; t < 256; t++) {
                    const int32_t a = amount[t];
                    if (a > 0) m->v[t] += (uint32_t)a;
                }
            }
        }
    }
}

// (main thread, in the hook, after the colour's swaps and the snow) the spatter in the grass
static KeptList g_spat_kept = {}, g_blade_kept = {};
static void draw_spatter() {
    if (!B.spat_on || !B.have_drawn || !B.main_viewport || !B.off_dim_x || !B.off_dim_y || !B.off_spatter ||
        !B.off_background || !B.off_item) return;
    if (!map_ready()) return;
    const int32_t z = B.drawn_z;
    if (z < 0 || z >= g_map.zn) return;
    if (B.spat_tables != g_spat_tables_seen || B.crack_world != g_spat_world_seen) {   // (Lua's grass table again, or a
        if (g_spat_bakes) memset(g_spat_bakes, 0, sizeof(SpatBake) * SPAT_BAKES);       //  new world: every bake let go)
        g_spat_used = 0;
        g_spat_tables_seen = B.spat_tables;
        g_spat_world_seen = B.crack_world;
    }
    const double t0 = ticks_now();
    uint8_t* main = viewport_in(0);
    if (!main) return;
    const int32_t dx = *(const int32_t*)(main + B.off_dim_x), dy = *(const int32_t*)(main + B.off_dim_y);
    if (dx <= 0 || dy <= 0 || dx > MOST_DIM || dy > MOST_DIM) return;
    int32_t* const spat = *(int32_t* const*)(main + B.off_spatter);
    int32_t* const bg = *(int32_t* const*)(main + B.off_background);
    int32_t* const items = *(int32_t* const*)(main + B.off_item);
    if (!spat || !bg || !items || !kept_ready(g_spat_kept, dx, dy) || !kept_ready(g_blade_kept, dx, dy)) return;
    const bool blades_on = B.spat_blades != 0;
    const bool amounts_ok = B.spat_vtable && B.off_isp_amount && g_map.bxn == g_leaf_bxn && g_map.byn == g_leaf_byn && g_map.zn == g_leaf_zn;
    uint32_t cells = 0, written = 0, blades = 0, waiting = 0, full = 0;
    double paint_us = 0;
    uint32_t scratch_t[PIC_TILE * PIC_TILE], scratch_o[PIC_TILE * PIC_TILE], out[PIC_TILE * PIC_TILE];
    for (int32_t sx = 0; sx < dx; sx++) {
        const int32_t x = B.drawn_x + sx;
        const int32_t* const col = spat + sx * dy;
        for (int32_t sy = 0; sy < dy; sy++) {
            const int32_t t = col[sy];
            if (t <= 0 || t >= TEX_MAP) continue;
            if (is_page(t) || is_ours(t)) continue;   // (the snow's: Detailed Weather's own)
            const uint8_t f = g_cflag[t];
            if (f & (CF_TABLE | CF_LEAVE)) continue;   // (the colour's table copies, and what it leaves be)
            const int32_t i = sx * dy + sy;
            const int32_t ground = bg[i];
            if (ground <= 0 || ground >= TEX_MAP) continue;
            const uint8_t gf = g_cflag[ground];
            const int32_t gorig = (gf & (CF_TABLE | CF_SCREEN)) ? g_link[ground] : ground;
            if (gorig <= 0 || gorig >= TEX_MAP || !g_spat_grass[gorig]) continue;
            cells++;
            const int32_t sorig = (f & CF_SCREEN) ? g_link[t] : t;
            const int32_t y = B.drawn_y + sy;
            // how much has fallen here: the share of pieces kept (spatter.lua: share_for)
            double share = 1;
            if (amounts_ok && x >= 0 && y >= 0 && x < g_map.x_end && y < g_map.y_end) {
                const LeafMap* m = leaf_find(LEAF_AMOUNTS, x >> 4, y >> 4, z, false);
                const uint32_t amount = (m && m->made) ? m->v[tile_of(x, y)] : 0;
                if (amount > 0) {
                    double s = (double)amount / SPAT_FULL_AMOUNT;
                    if (s > 1) s = 1;
                    if (s < SPAT_LEAST_SHARE) s = SPAT_LEAST_SHARE;
                    share = floor(s * 10 + 0.5) / 10;
                    if (share < SPAT_LEAST_SHARE) share = SPAT_LEAST_SHARE;
                }
            }
            const int variant = pos_mod(x * 7 + y * 13, SPAT_VARIANTS);
            const uint32_t step = (uint32_t)floor(share * 20 + 0.5);
            // the spatter, thinned and shadowed
            const uint64_t tpic = crack_picture(t), opic = sorig == t ? tpic : crack_picture(sorig > 0 ? sorig : t);
            if (tpic && opic) {
                SpatBake* e = spat_bake_find(tpic, opic, (step << 8) | (uint32_t)variant | 0x10000u, true);
                if (e && e->tex == 0) {
                    if (paint_us < SPAT_PAINT_US) {
                        const double p0 = ticks_now();
                        const uint32_t* tp = crack_pixels(t, scratch_t);
                        const uint32_t* op = sorig == t ? tp : crack_pixels(sorig, scratch_o);
                        if (tp && op) {
                            spat_make_piece(tp, op, share, variant, out);
                            e->tex = spat_paint(out);
                        } else { B.spat_unreadable++; e->tex = -1; }   // (not tried again: as spatter.lua kept {})
                        paint_us += (ticks_now() - p0) * g_us_per_tick;
                    } else B.spat_over_time++;
                }
                if (e && e->tex > 0) {
                    if (g_spat_kept.n < g_spat_kept.cap) {
                        spat[i] = e->tex;
                        g_spat_kept.e[g_spat_kept.n++] = Kept{spat, i, t, e->tex};
                        written++;
                    } else full++;
                } else waiting++;
            }
            // the grass's blades over it, unless an item has the layer
            if (blades_on && items[i] == 0) {
                const uint64_t gpic = crack_picture(ground), gopic = gorig == ground ? gpic : crack_picture(gorig);
                if (gpic && gopic) {
                    SpatBake* e = spat_bake_find(gpic, gopic, 0x20000u, true);
                    if (e && e->tex == 0 && paint_us < SPAT_PAINT_US) {
                        const double p0 = ticks_now();
                        const uint32_t* gp = crack_pixels(ground, scratch_t);
                        const uint32_t* op = gorig == ground ? gp : crack_pixels(gorig, scratch_o);
                        if (gp && op) {
                            spat_make_blades(gp, op, out);
                            e->tex = spat_paint(out);
                        } else { B.spat_unreadable++; e->tex = -1; }
                        paint_us += (ticks_now() - p0) * g_us_per_tick;
                    }
                    if (e && e->tex > 0) {
                        if (g_blade_kept.n < g_blade_kept.cap) {
                            items[i] = e->tex;
                            g_blade_kept.e[g_blade_kept.n++] = Kept{items, i, 0, e->tex};
                            blades++;
                        } else full++;
                    }
                }
            }
        }
    }
    g_spat_kept.last = spat;
    g_blade_kept.last = items;
    const double us = (ticks_now() - t0) * g_us_per_tick;
    B.spat_frames++;
    B.spat_written += written;
    B.spat_blades_written += blades;
    B.spat_cells_last = cells;
    B.spat_written_last = written;
    B.spat_waiting_last = waiting;
    B.spat_kept_full += full;
    B.spat_bakes_kept = (uint32_t)g_spat_used;
    B.spat_us_total += us;
    if (us > B.spat_us_max) B.spat_us_max = us;
    if (paint_us > B.spat_paint_us_max) B.spat_paint_us_max = paint_us;
}

static void tidy_hook(void* self) {
    B.tidy_calls++;
    if (B.enabled && B.have_drawn && B.window_x && B.window_y) {
        int32_t live_x = *(const int32_t*)(uintptr_t)B.window_x;
        int32_t live_y = *(const int32_t*)(uintptr_t)B.window_y;
        if (live_x != B.drawn_x || live_y != B.drawn_y) B.view_moved++;
    }
    paint_copies();  // (first: copies asked for this frame are painted before they're swapped in)
    swap_colour();   // (the snow decides from the screen as colour leaves it, as before)
    draw_grass_wave();   // (THE GRASS WAVE DRAWN HERE: the ground layer's grass, before all that reads it, as Lua drew it)
    place_cracks();  // (CRACKS IN PLACE: over the colour's ramp copies, by the ramp's own picture)
    draw_shade();    // (the designation layer: nothing else here touches it)
    if (B.enabled) write_snow();
    draw_paths();    // (PATHS: the ground layer, after the colour's swaps, which leave plain ground be)
    draw_spatter();  // (THE SPATTER DRAWN HERE: the spatter and item layers, after the colour and the snow; before
                     // the murky tint, which may use the spatter layer of the level above water)
    fix_water_fog(); // (FOG OVER WATER: the interface layer, which nothing else here touches; before the
                     // murky tint, so the surface it looks for is the game's own drawing)
    draw_murky();    // (after the colour's swaps, which leave its tint be, and the snow)
    draw_rain();     // (RAIN AND SNOW FALLING: the flow layer and top_shadow, which nothing else here touches)
    draw_leaves();   // (THE LEAVES DRAWN HERE: the projectile layer, which nothing else here touches)
    draw_weather_fog();   // (THE FOG DRAWN HERE: the main view's interface layer, as the overlay painted it)
    g_tidy_original(self);
}

// Patches the slot, after the checks in SAFETY (top). Called only from the
// prerender call, when the main thread is waiting for render_things.
static bool install_hook() {
    uint8_t* obj = (uint8_t*)(uintptr_t)B.renderer;
    if (!readable(obj, 8)) { log_line("NOT HOOKING: the renderer address from Lua is not readable."); return false; }
    void** vt = *(void***)obj;
    if (!readable(vt, (RENDER_SLOT + 1) * sizeof(void*))) {
        log_line("NOT HOOKING: the renderer's vtable is not readable.");
        return false;
    }
    // (the checks that this is the game's own renderer, with tidy_tile_cache in the slot: platform.h)
    char why[200] = "";
    memcpy(B.renderer_class, "(unread)", 9);
    if (!plat_check_renderer(vt, TIDY_SLOT, RENDER_SLOT, B.renderer_class, sizeof B.renderer_class, why, sizeof why)) {
        log_line("NOT HOOKING: %s.", why);
        return false;
    }
    void* tidy = vt[TIDY_SLOT];
    g_tidy_original = (tidy_fn)tidy;
    if (!plat_patch_slot(&vt[TIDY_SLOT], (void*)&tidy_hook, why, sizeof why)) {
        g_tidy_original = nullptr;
        log_line("NOT HOOKING: %s.", why);
        return false;
    }
    g_slot = &vt[TIDY_SLOT];
    log_line("hooked: %s, slot %zu (tidy_tile_cache) at RVA 0x%llX.", B.renderer_class,
             TIDY_SLOT, (unsigned long long)((uintptr_t)tidy - plat_code_base(tidy)));
    return true;
}

// Puts DF's own function back, if the slot still holds ours. If something
// else has patched the slot over ours since, it is left alone: writing
// back would undo that patch too.
static void uninstall_hook() {
    if (!g_slot) return;
    if (*g_slot != (void*)&tidy_hook) {
        log_line("shutdown: the slot no longer holds this hook; left as it is.");
        return;
    }
    char why[200] = "";
    if (plat_patch_slot(g_slot, (void*)g_tidy_original, why, sizeof why)) {
        B.hooked = 0;
        log_line("shutdown: tidy_tile_cache put back.");
    } else {
        log_line("shutdown: tidy_tile_cache not put back: %s.", why);
    }
}

// =====================================================================
// THE DFHOOKS ENTRY POINTS
// =====================================================================
// The chain loader calls libraries with a lower priority first; DFHack
// exports 100, so 200 runs this one's per-frame call after DFHack's.
extern "C" DW_EXPORT const int32_t dfhooks_priority = 200;

extern "C" DW_EXPORT void dfhooks_init() {
    g_log = fopen("detailed_weather_hook.log", "w");
    g_us_per_tick = plat_us_per_tick();
    log_line("Detailed Weather hook library (%s), layout %u (test 16A, the wave).", DW_LIBRARY_NAME, LAYOUT);

    // ---- THE BLOCK, PUBLISHED ----
    // Published even when disabled, so Lua can say why nothing happens.
    memcpy(B.magic, "DWHOOK01", 8);
    B.layout = LAYOUT;
    B.col_link = (uint64_t)(uintptr_t)g_link;      // (THE COLOUR: Lua writes these two)
    B.col_flags = (uint64_t)(uintptr_t)g_cflag;
    B.col_tex_map = TEX_MAP;
    B.sway_of = (uint64_t)(uintptr_t)g_sway_of;   // (SWAY: and these two)
    B.sway_tex = (uint64_t)(uintptr_t)&g_sway_tex[0][0];
    B.sway_max = SWAY_MAX;
    B.sway_phases = SWAY_PHASES;
    B.sway_playing = -1;
    B.crack_ground = (uint64_t)(uintptr_t)g_ground;   // (CRACKS IN PLACE: Lua writes each original's ground)
    B.spat_grass = (uint64_t)(uintptr_t)g_spat_grass;   // (THE SPATTER DRAWN HERE: Lua writes the grass originals)
    B.wave_slots = (uint64_t)(uintptr_t)&g_wave_slots[0];   // (THE GRASS WAVE DRAWN HERE: Lua writes the slots)
    B.wave_slots_most = WAVE_SLOTS;
    char addr[32];
    snprintf(addr, sizeof addr, "%llX", (unsigned long long)(uintptr_t)&g_block);
    // (how the environment is set so DFHack's Lua reads it with os.getenv: platform.h)
    if (!plat_publish("DWHOOK_BLOCK", addr)) log_line("could not publish DWHOOK_BLOCK.");
    else log_line("block published at 0x%s (%u bytes).", addr, (unsigned)sizeof(Block));

    if (plat_file_exists("detailed_weather_hook.disable")) {
        g_disabled = true;
        log_line("detailed_weather_hook.disable present: doing nothing this session.");
    }
}

// Game thread, once a frame, before DF fills the buffers: reads the view's
// corner (THE VIEW AS DRAWN), patches the slot when Lua asks, builds the
// texture map when new tables come, puts back the game's own values in the
// buffer DF is about to draw (PUT BACK; also how turning the snow off
// clears it, a buffer a frame), and works out this frame (THE PLAN).
extern "C" DW_EXPORT void dfhooks_prerender() {
    B.prerender_calls++;
    if (g_disabled) return;
    read_view_as_drawn();
    if (B.install && !B.hooked && !B.install_failed) {
        if (install_hook()) B.hooked = 1;
        else B.install_failed = 1;
    }
    if (B.tables_ready && B.tables_ready != B.tables_built) build_tables();
    // CRACKS IN PLACE: a new world forgets every cracked copy (before THE COLOUR's tables, just below, are
    // emptied and told again of those kept)
    if (B.crack_world != g_crack_world_done) {
        crack_forget_all();
        B.crack_b_tail = B.crack_b_head;   // (blanks from before: their numbers may be others' now)
        B.crack_d_head = B.crack_d_tail;   // (copies not yet noted by Lua: forgotten with the rest)
        g_crack_world_done = B.crack_world;
    }
    // THE COLOUR's tables emptied when Lua asks (a new start: texture numbers
    // can mean other pictures in another world). Lua writes nothing into them
    // until it sees this done; the game thread is the one Lua runs on.
    if (B.col_reset != B.col_reset_done) {
        memset(g_link, 0, sizeof g_link);
        memset(g_cflag, 0, sizeof g_cflag);
        memset(g_seen_period, 0, sizeof g_seen_period);
        free_held();
        memset(g_tint_bakes, 0, sizeof g_tint_bakes);   // (MURKY: EDGES OVER THE TINT, made again)
        g_tint_used = 0;
        B.col_req_head = B.col_req_tail = B.col_seen_head = B.col_seen_tail = 0;
        memset(g_pic, 0, sizeof g_pic);   // (PICTURES CHECKED HERE)
        // (CRACKS IN PLACE: the cracked copies made are told to the emptied tables again: they're still
        // frost.lua's and still on screen. A new world forgets them first, just above)
        for (int k = 0; k < g_crack_made_n; k++) crack_tell_colour(g_crack_made[k].tex, g_crack_made[k].base);
        g_pic_used = g_pic_kept = 0;
        B.col_verified_head = B.col_verified_tail = 0;
        B.col_reset_done = B.col_reset;
        B.sway_reset_done = B.sway_reset - 1;   // (and the sway's, just below)
    }
    // SWAY: the frames forgotten when Lua asks (new wind, a new look)
    if (B.sway_reset != B.sway_reset_done) {
        memset(g_sway_of, 0, sizeof g_sway_of);
        memset(g_canopy_listed, 0, sizeof g_canopy_listed);
        B.sway_reset_done = B.sway_reset;
    }
    if (B.hooked) put_back();
    fog_put_back();  // (FOG OVER WATER: the game's own hazes back, on or off)
    rain_put_back(); // (RAIN AND SNOW FALLING: the game's own flow layer back, on or off)
    kept_put_back(g_wfog_kept, B.off_interface, B.wfog_put_back, B.wfog_dropped);    // (THE FOG DRAWN HERE)
    kept_put_back(g_leaf_kept, B.off_projectile, B.leaf_put_back, B.leaf_dropped);   // (THE LEAVES DRAWN HERE)
    kept_put_back(g_blade_kept, B.off_item, B.spat_put_back, B.spat_dropped);        // (THE SPATTER DRAWN HERE: after the
    kept_put_back(g_spat_kept, B.off_spatter, B.spat_put_back, B.spat_dropped);      //  others, as it was written before them)
    plan_snow();
    plan_paths();    // (PATHS: the grass read here, on the game thread)
    plan_fog();      // (FOG OVER WATER: the cells over deep water, from the map)
    plan_leaves();   // (THE LEAVES DRAWN HERE: the view's blocks worked out, the plants read on this thread)
    plan_spatter();  // (THE SPATTER DRAWN HERE: the fallen amounts read on this thread)
}

extern "C" DW_EXPORT void dfhooks_shutdown() {
    B.enabled = 0;
    uninstall_hook();
    log_line("shutdown: prerender %lld, renderer %lld, plans %lld, written %lld, not written %lld;"
             " ramps %lld, floors %lld, trunks %lld, edges %lld, cells waiting %lld, put back %lld;"
             " bakes asked %lld, done %lld, failed %lld; plan overflows %u; memory %u KB.",
             (long long)B.prerender_calls, (long long)B.tidy_calls, (long long)B.plans,
             (long long)B.applies, (long long)B.apply_skipped, (long long)B.ramps_written,
             (long long)B.floors_written, (long long)B.trunks_written, (long long)B.edges_written,
             (long long)B.cells_waiting, (long long)B.cells_restored, (long long)B.bakes_asked,
             (long long)B.bakes_done, (long long)B.bakes_failed, B.plan_overflow, memory_kb());
    for (int s = 0; s < SLOTS; s++)
        for (int k = 0; k < 2; k++) { free(g_banks[s][k].saved); memset(&g_banks[s][k], 0, sizeof(Bank)); }
    free_cols();
    free_memos();
    free_held();
    free(g_dark);
    g_dark = nullptr;
    g_dark_n = 0;
    free(g_murky_see);
    g_murky_see = nullptr;
    g_murky_n = 0;
    free(g_fog_mark);   // (FOG OVER WATER)
    free(g_fog_kept);
    free(g_fog_blocks);
    g_fog_mark = nullptr;
    g_fog_kept = nullptr;
    g_fog_blocks = nullptr;
    g_fog_n = g_fog_kept_n = g_fog_kept_cap = g_fog_blocks_used = 0;
    p_free_plans();
    crack_free_tiles(); free(g_crack_copies); free(g_crack_made);   // (CRACKS IN PLACE)
    g_crack_copies = nullptr; g_crack_made = nullptr;
    g_crack_copies_used = g_crack_made_n = g_crack_made_cap = 0;
    free(g_rain_kept);   // (RAIN AND SNOW FALLING)
    g_rain_kept = nullptr;
    g_rain_last_hf = g_rain_last_ts = nullptr;
    g_rain_kept_n = g_rain_kept_cap = 0;
    if (g_log) { fclose(g_log); g_log = nullptr; }
}
