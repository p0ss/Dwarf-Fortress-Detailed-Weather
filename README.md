# Detailed Weather

The code of Detailed Weather, a Dwarf Fortress mod that draws the weather the game simulates but
graphics mode leaves out: rain, snow and fog, falling leaves and blossom, snow on ramps, and ground
that takes a look from the temperature and how wet it is.

The mod itself is on the Steam Workshop:
https://steamcommunity.com/sharedfiles/filedetails/?id=3838268998

It needs DFHack and the Detailed Landscapes mod.

## There is no art here

This repository holds the scripts and the text files only. The pictures are not in it, and should
not be added: part of the mod's art is edited from the game's own graphics, which can't be hosted
anywhere but the Workshop. `.gitignore` leaves every picture out.

To run the code from here you need the art from the Workshop copy:

1. Subscribe to Detailed Weather on the Workshop, so Steam downloads it.
2. Copy that mod folder somewhere to work in, and copy this repository's files over it. The
   pictures stay where they are, beside the code.
3. Put the result in the game's `mods` folder.

The game copies a mod into `data/installed_mods` once for each version number and never looks at
it again, so a changed copy only shows in a new world, or after raising `NUMERIC_VERSION` in
`info.txt`.

## What is where

- `info.txt`: the mod's name, version and what it needs.
- `scripts_modactive/detailed_weather.lua`: the overlays and the `detailed_weather` command. Its
  help text is at the top of the file.
- `scripts_modactive/internal/detailed_weather/`: a script for each part (colour, frost, snow on
  ramps, paths, shade and so on).
- `art/*.lua`: where each tile sits in the art's sheets. The sheets themselves are the pictures
  that aren't here.
- `graphics/*.txt`: the graphics definitions for the lying snow.
