-- Written by tools/weather/make_snow_sheet.py: the layout of the falling-snow sheets as drawn,
-- snow_1 to snow_4 (one per level: light, steady, heavy, blizzard).
-- The art itself is packed in falling/ (sheet_packing.py), a file per wind.
return {
    cells = 6, frames = 36,
    levels = 4,
    winds = {-2.4, -1.4, -0.6, 0.0, 0.6, 1.4, 2.4},
}
