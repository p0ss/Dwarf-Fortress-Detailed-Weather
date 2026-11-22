-- What Detailed Weather adds to the hover description of a map tile.
--
-- The game's hover box gives one line ('A pile of snow', 'Peach Tree') where 0.47 listed what was
-- there in more detail. This works out a few extra lines for the hovered tile:
--   plant   a tree's or shrub's species and its state through the year: in leaf, leaves turning,
--           bare, in flower, with fruit; saplings and dead plants
--   leaves  leaves or petals falling there, and from which tree, as Detailed Weather draws them
--   spatter fallen fruit, nuts and seeds by kind, how much (the game's amounts), and the share
--           of a full tile's pieces drawn for it
--   grass   the species and how thick it is (the game's 0-100)
--   snow    how deep (the game's 0-255)
--   temperature, and ice on frozen water; 'underground' below the surface (where it sits at the
--            fort's steady 8 C), 'under cover' above ground under a roof or a tree's canopy
--   air      how humid the air is outside (the map's one wetness level: the region's rainfall and
--            recent rain, which sets the ground's look)
--   weather  rain or snow falling there (and how hard), fog, and the wind, as Detailed Weather
--            draws them (marked 'forced' when set by a command rather than the game)
-- Water depth isn't repeated: the game shows it.
--@ module = true

local WATER = 6
local SNOW_WORDS = {{255, 'deep snow'}, {100, 'snow'}, {1, 'a dusting of snow'}}
local GRASS_WORDS = {{75, 'lush'}, {50, 'thick'}, {25, 'thin'}, {1, 'sparse'}}
local AIR_WORDS = {{0.85, 'very humid'}, {0.6, 'humid'}, {0.4, 'average'}, {0.15, 'dry'}, {0, 'very dry'}}

local function words_for(table_of_words, amount)
    for _, words in ipairs(table_of_words) do
        if amount >= words[1] then return words[2] end
    end
end

local function plant_raw(index) return df.global.world.raws.plants.all[index] end

-- The growths a plant has now (leaves, flowers, fruit...), by the year's tick.
local function growths_now(raw)
    local tick = df.global.cur_year_tick
    local now = {}
    for _, growth in ipairs(raw.growths) do
        local from, to = growth.timing_1, growth.timing_2
        local present = (from < 0 or to < 0) or (from <= to and tick >= from and tick <= to)
            or (from > to and (tick >= from or tick <= to))   -- a span that wraps past new year
        if present then now[#now + 1] = growth end
    end
    return now
end

-- Which of a growth's colour stages it's at: 1 for the first (green leaves), more as it turns.
local function growth_stage(growth)
    local tick = df.global.cur_year_tick
    for n, print in ipairs(growth.prints) do
        if tick >= print.timing_start and tick <= print.timing_end then return n, #growth.prints end
    end
    return 1, #growth.prints
end

-- 'peach tree: leaves turning, with peaches' and the like.
local function plant_line(plant, tiletype)
    local raw = plant_raw(plant.material)
    if not raw then return nil end
    local attrs = df.tiletype.attrs[tiletype]
    local is_tree = raw.flags.TREE
    local kind = attrs.shape == df.tiletype_shape.SAPLING and 'sapling' or is_tree and 'tree' or 'shrub'
    -- (some raws' names already end in 'tree': 'apricot tree', not 'peach')
    local name = raw.name
    if kind ~= 'shrub' and not name:find(' ' .. kind .. '$') then name = name .. ' ' .. kind end
    if attrs.special == df.tiletype_special.DEAD or plant.damage_flags.dead then
        return name .. ': dead'
    end
    local states, has_leaves, leafy = {}, false, false
    for _, growth in ipairs(raw.growths) do
        if growth.id == 'LEAVES' then has_leaves = true end
    end
    for _, growth in ipairs(growths_now(raw)) do
        if growth.id == 'LEAVES' then
            leafy = true
            local stage, stages = growth_stage(growth)
            states[#states + 1] = (stages > 1 and stage > 1) and 'leaves turning' or 'in leaf'
        elseif growth.id:find('FLOWER') then
            states[#states + 1] = 'in flower'
        elseif growth.id ~= 'LEAVES' then
            states[#states + 1] = 'with ' .. growth.name_plural
        end
    end
    if is_tree and has_leaves and not leafy then table.insert(states, 1, 'bare') end
    if #states == 0 then return name end
    return name .. ': ' .. table.concat(states, ', ')
end

-- 'dog's tooth grass, thick (62/100)', for the grass on a tile with the most of it.
local function grass_line(block, x, y)
    local best, amount = nil, 0
    for _, event in ipairs(block.block_events) do
        if df.block_square_event_grassst:is_instance(event) then
            local a = event.amount[x % 16][y % 16]
            if a > amount then best, amount = event.plant_index, a end
        end
    end
    local raw = best and plant_raw(best)
    if not raw then return nil end
    -- the game's grass grows to 100; a few tiles hold more (up to 255), which looks no different
    return ('%s, %s (%d/100)'):format(raw.name, words_for(GRASS_WORDS, amount), math.min(100, amount))
end

local function snow_line(block, x, y)
    local amount = 0
    for _, event in ipairs(block.block_events) do
        if df.block_square_event_material_spatterst:is_instance(event) and event.mat_type == WATER
                and event.mat_state == df.matter_state.Powder then
            amount = math.max(amount, event.amount[x % 16][y % 16])
        end
    end
    if amount == 0 then return nil end
    return ('%s (%d/255)'):format(words_for(SNOW_WORDS, amount), amount)
end

local function temperature_line(block, x, y, tiletype)
    local celsius = (block.temperature_1[x % 16][y % 16] - 10000) * 5 / 9
    local ice = df.tiletype.attrs[tiletype].material == df.tiletype_material.FROZEN_LIQUID
    return ('%.0f C%s'):format(celsius, ice and ', ice' or '')
end

-- 'air dry (19%)': the map's wetness, one level for the whole map (not the tile's: a tile of
-- water reads the same), as the ground's look is drawn for it.
local function wetness_line()
    local wetness = reqscript('internal/detailed_weather/wetness')
    local level = wetness.level()
    return ('air %s (%d%%%s)'):format(words_for(AIR_WORDS, level), math.floor(level * 100 + 0.5),
        wetness.forced and ', forced' or '')
end

local function plain(name) return (name:gsub('^fog_', ''):gsub('_', ' ')) end

-- 'snowing lightly; nimbostratus; thick fog; breezy wind from the east', for where the tile is.
local function weather_line(pos)
    local main = reqscript('detailed_weather')
    local wind = reqscript('internal/detailed_weather/wind')
    local parts = {}
    local data = df.global.world.world_data
    local map = df.global.world.map
    local clouds = data.region_map[map.region_x // 16]:_displace(map.region_y // 16).clouds

    local falling
    local precipitation = reqscript('internal/detailed_weather/precipitation')
    if main.force == 'rain' or main.force == 'snow' then
        local kind = main.force
        falling = precipitation.FALLING[kind][precipitation.level(kind, true)] .. ' (forced)'
    elseif main.force ~= 'off' then
        local w = dfhack.maps.getCurrentWeather(pos)
        local kind = w == df.weather_type.Rain and 'rain' or w == df.weather_type.Snow and 'snow'
        if kind then falling = precipitation.FALLING[kind][precipitation.level(kind)] end
    end
    if falling then parts[#parts + 1] = falling end
    local cloud_words = precipitation.clouds_in_words()
    if cloud_words then parts[#parts + 1] = cloud_words end

    local fog = main.fog_mode
    if fog == 'auto' or fog == nil then
        -- (the fog as drawn, which follows the game's once it's settled)
        local level = main.fog_shown or clouds.fog
        if level > 0 then parts[#parts + 1] = plain(df.fog_type[level]) .. ' fog' end
    elseif fog ~= 'off' then
        parts[#parts + 1] = ({'mist', 'fog', 'thick fog'})[tonumber(fog)] .. ' (forced)'
    end

    local x, y, strength = wind.get()
    if strength >= 0.15 then
        local feel = strength < 0.5 and 'light' or strength < 1 and 'breezy' or strength < 1.3 and 'strong' or 'gale'
        local from = {}
        if y < -0.1 * strength then from[#from + 1] = 'south' elseif y > 0.1 * strength then from[#from + 1] = 'north' end
        if x < -0.1 * strength then from[#from + 1] = 'east' elseif x > 0.1 * strength then from[#from + 1] = 'west' end
        parts[#parts + 1] = ('%s wind from the %s%s'):format(feel, table.concat(from, '-'),
            wind.state.forced and ' (forced)' or '')
    else
        parts[#parts + 1] = 'calm'
    end
    return table.concat(parts, '; ')
end

-- The fallen fruit, nuts and seeds lying on a tile, as the hover box names them and as its
-- spatter should be called, and how much of each: {{plural, singular, amount}...}. The game names spatter by the fruit's own
-- name ("sand pears"), the same as the fruit a dwarf can pick, but it can't be gathered, so the
-- hover box's line is shown as "sand pear spatter" (Poss).
function spatter_names(pos)
    local block = dfhack.maps.getTileBlock(pos)
    if not block then return {} end
    local names, seen = {}, {}
    for _, event in ipairs(block.block_events) do
        local amount = df.block_square_event_item_spatterst:is_instance(event) and event.amount[pos.x % 16][pos.y % 16] or 0
        if amount > 0 then
            local info = dfhack.matinfo.decode(event.mattype, event.matindex)
            local plant = info and info.plant
            if plant then
                local plural, singular
                if event.item_type == df.item_type.PLANT_GROWTH then
                    for _, growth in ipairs(plant.growths) do
                        if growth.mat_type == event.mattype and growth.mat_index == event.matindex then
                            plural, singular = growth.name_plural, growth.name
                            break
                        end
                    end
                elseif event.item_type == df.item_type.SEEDS then
                    plural, singular = plant.seed_plural, plant.seed_singular
                end
                if plural and plural ~= '' then
                    if seen[plural] then
                        seen[plural][3] = seen[plural][3] + amount
                    else
                        seen[plural] = {plural, singular, amount}
                        names[#names + 1] = seen[plural]
                    end
                end
            end
        end
    end
    return names
end

-- 'spatter: sand pear 2400, plum 300 (30% of full)': how much has fallen, and the share of a
-- full tile's pieces Detailed Weather draws for it (all of them from the spatter module's
-- FULL_AMOUNT; the game's amounts run from 1 to past 8000).
local function spatter_line(pos)
    local names, parts, total = spatter_names(pos), {}, 0
    if #names == 0 then return nil end
    for _, name in ipairs(names) do
        parts[#parts + 1] = ('%s %d'):format(name[2], name[3])
        total = total + name[3]
    end
    local share = reqscript('internal/detailed_weather/spatter').share_for(total)
    return ('spatter: %s (%d%% of full)'):format(table.concat(parts, ', '), math.floor(share * 100 + 0.5))
end

-- The extra lines for a map position, or {} if there's nothing there.
function describe(pos)
    local block = dfhack.maps.getTileBlock(pos)
    if not block then return {} end
    local x, y = pos.x, pos.y
    local tiletype = block.tiletype[x % 16][y % 16]
    local lines = {}
    local plant = dfhack.maps.getPlantAtTile(pos)
    if plant then lines[#lines + 1] = plant_line(plant, tiletype) end
    local ok, falling = pcall(function()
        local _, _, strength = reqscript('internal/detailed_weather/wind').get()
        return reqscript('internal/detailed_weather/leaves').falling_at(pos, strength)
    end)
    if ok and falling then lines[#lines + 1] = falling end
    local ok, spatter = pcall(spatter_line, pos)
    if ok and spatter then lines[#lines + 1] = spatter end
    -- the game keeps a grass record under floors built over grass, so only on grass tiles
    local material = df.tiletype.attrs[tiletype].material
    if material == df.tiletype_material.GRASS_LIGHT or material == df.tiletype_material.GRASS_DARK
            or material == df.tiletype_material.GRASS_DRY or material == df.tiletype_material.GRASS_DEAD then
        lines[#lines + 1] = grass_line(block, x, y)
    end
    lines[#lines + 1] = snow_line(block, x, y)
    -- temperature and weather share a line, to keep the box compact
    local line = temperature_line(block, x, y, tiletype)
    local flags = block.designation[x % 16][y % 16]
    if not flags.outside then line = line .. (flags.subterranean and ' underground' or ' under cover') end
    if flags.outside or not flags.subterranean then
        local ok, wet = pcall(wetness_line)
        if ok then line = line .. ', ' .. wet end
        local ok, weather = pcall(weather_line, pos)
        if ok and weather ~= '' then line = line .. '; ' .. weather end
    end
    lines[#lines + 1] = line
    local out = {}
    for _, line in ipairs(lines) do if line then out[#out + 1] = line end end   -- drop the nils
    return out
end
