-- Built by tools/weather/make_heat_ground.py: the ground tiles in art/heat_ground.png, in
-- order, each a row per band (bands), 16 pieces across. Bands hotter than the last use it.
return {
    bands = {8, 9, 10, 11, 12, 13},
    pieces = 16,
    ground = {
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 0, y = 0, kind = 'sand'},   -- SAND_FLOOR_5
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 1, y = 0, kind = 'sand'},   -- SAND_FLOOR_5B
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 2, y = 0, kind = 'sand'},   -- SAND_FLOOR_5C
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 3, y = 0, kind = 'sand'},   -- SAND_FLOOR_5D
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 0, y = 1, kind = 'sand'},   -- SAND_YELLOW_FLOOR_5
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 1, y = 1, kind = 'sand'},   -- SAND_YELLOW_FLOOR_5B
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 2, y = 1, kind = 'sand'},   -- SAND_YELLOW_FLOOR_5C
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 3, y = 1, kind = 'sand'},   -- SAND_YELLOW_FLOOR_5D
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 0, y = 2, kind = 'sand'},   -- SAND_WHITE_FLOOR_5
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 1, y = 2, kind = 'sand'},   -- SAND_WHITE_FLOOR_5B
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 2, y = 2, kind = 'sand'},   -- SAND_WHITE_FLOOR_5C
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 3, y = 2, kind = 'sand'},   -- SAND_WHITE_FLOOR_5D
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 0, y = 3, kind = 'sand'},   -- SAND_BLACK_FLOOR_5
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 1, y = 3, kind = 'sand'},   -- SAND_BLACK_FLOOR_5B
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 2, y = 3, kind = 'sand'},   -- SAND_BLACK_FLOOR_5C
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 3, y = 3, kind = 'sand'},   -- SAND_BLACK_FLOOR_5D
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 0, y = 4, kind = 'sand'},   -- SAND_RED_FLOOR_5
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 1, y = 4, kind = 'sand'},   -- SAND_RED_FLOOR_5B
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 2, y = 4, kind = 'sand'},   -- SAND_RED_FLOOR_5C
        {page = 'FLOOR_SAND_ROUND_DETAILED', x = 3, y = 4, kind = 'sand'},   -- SAND_RED_FLOOR_5D
        {page = 'FLOORS_ROUND_DETAILED', x = 1, y = 4, kind = 'stone'},   -- STONE_FLOOR_5
        {page = 'FLOORS_ROUND_DETAILED', x = 1, y = 7, kind = 'dirt'},   -- DIRT_FLOOR_5
        {page = 'ALT_FLOORS_ROUND_DETAILED', x = 7, y = 4, kind = 'stone'},   -- STONE_FLOOR_5B
        {page = 'ALT_FLOORS_ROUND_DETAILED', x = 7, y = 5, kind = 'stone'},   -- STONE_FLOOR_5C
        {page = 'ALT_FLOORS_ROUND_DETAILED', x = 7, y = 6, kind = 'stone'},   -- STONE_FLOOR_5D
        {page = 'ALT_FLOORS_ROUND_DETAILED', x = 7, y = 7, kind = 'dirt'},   -- DIRT_FLOOR_5B
        {page = 'ALT_FLOORS_ROUND_DETAILED', x = 7, y = 8, kind = 'dirt'},   -- DIRT_FLOOR_5C
        {page = 'ALT_FLOORS_ROUND_DETAILED', x = 7, y = 9, kind = 'dirt'},   -- DIRT_FLOOR_5D
        {page = 'FLOOR_PEBBLES', x = 0, y = 0, kind = 'pebbles'},   -- PEBBLES_FLOOR_5
        {page = 'FLOOR_PEBBLES', x = 1, y = 0, kind = 'pebbles'},   -- PEBBLES_FLOOR_5B
        {page = 'FLOOR_PEBBLES', x = 2, y = 0, kind = 'pebbles'},   -- PEBBLES_FLOOR_5C
        {page = 'FLOOR_PEBBLES', x = 3, y = 0, kind = 'pebbles'},   -- PEBBLES_FLOOR_5D
    },
}
