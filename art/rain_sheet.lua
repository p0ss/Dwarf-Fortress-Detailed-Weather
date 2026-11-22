-- Written by tools/weather/make_rain_sheet.py: the layout of the rain sheets as drawn, rain_1 to
-- rain_4 (one per level: drizzle, steady, heavy, storm).
-- The art itself is packed in falling/ (sheet_packing.py), a file per slant.
return {
    cells = 6, frames = 24,
    surfaces = {'ground', 'water'},
    levels = 4,
    slants = {-1.0, -0.55, -0.25, 0.0, 0.25, 0.55, 1.0},
}
