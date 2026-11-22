-- Written by tools/weather/make_snow_cover.py: art/snow_thin.png's layout. A column per
-- FULL piece (cells: the piece's cell on the snow page, row * 8 + column -> its column here,
-- from 0); a row per thin level, version and block, ((level * variants) + variant) *
-- repeat * repeat + block, block = (y % repeat) * repeat + x % repeat, all from 0.
return {
    columns = 20, levels = 4, variants = 4, repeat_tiles = 4,
    edge_level = 1, inside_variants = 2,
    cells = {[0]=0, [32]=1, [33]=2, [34]=3, [35]=4, [1]=5, [2]=6, [3]=7, [8]=8, [9]=9, [10]=10, [11]=11, [16]=12, [17]=13, [18]=14, [19]=15, [24]=16, [25]=17, [26]=18, [27]=19},
    -- art/snow_thin_inside.png: the plain inside piece by its corners' levels, a column per
    -- block, a row per ((((nw * levels + ne) * levels + sw) * levels + se) * inside_variants + variant)
    inside_cells = {[0]=true, [32]=true, [33]=true, [34]=true, [35]=true},
}
