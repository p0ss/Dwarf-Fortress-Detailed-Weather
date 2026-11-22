-- What each part of Detailed Weather is set to, for players choosing between how it looks and how
-- fast it runs. Each part is off, low or high (some have no low); `detailed_weather profile off`,
-- `low`, `medium` or `high` sets them all at once. The choices are kept in dfhack-config/detailed_weather.json,
-- so they hold for every fort and every session on this machine.
--
-- This file only knows the parts, their levels and the profiles, and keeps the file. What a level
-- does is in detailed_weather.lua (apply_settings), which hands each module its switches.
--
-- What low means: the part does less work each frame, so what it draws fills in a little more
-- slowly as the view moves (LOW_ALLOWANCE of its usual time a frame), and it drops its animation
-- or its finer layer where it has one. The `low` text below says which.
--@ module = true

local json = require('json')

local CONFIG_FILE = 'dfhack-config/detailed_weather.json'
LOW_ALLOWANCE = 0.5

-- The parts, in the order they're listed. levels: the ones a part has; high / low: what the player
-- gets at each, for `detailed_weather settings` and the help.
PARTS = {
    {name = 'colour', levels = {'off', 'high'},
     high = 'the ground takes a look by temperature and wetness'},
    {name = 'weather', levels = {'off', 'high'},
     high = 'falling rain and snow'},
    {name = 'fog', levels = {'off', 'high'},
     high = 'fog and mist'},
    {name = 'trees', levels = {'off', 'low', 'high'},
     high = 'trees and buildings in the look\'s colours, branches swaying in wind',
     low = 'in the look\'s colours, but still, and filling in more slowly'},
    {name = 'grass', levels = {'off', 'low', 'high'},
     high = 'grass leaning in gusts that sweep across it, blades rustling',
     low = 'the whole field leans together, no sweep or rustle'},
    {name = 'ramps', levels = {'off', 'low', 'high'},
     high = 'snow on ramps',
     low = 'snow on ramps, filling in more slowly'},
    {name = 'frost', levels = {'off', 'low', 'high'},
     high = 'ramps in the ground\'s look, cracks in dry ground',
     low = 'ramps in the ground\'s look and cracks in dry ground, filling in more slowly'},
    {name = 'paths', levels = {'off', 'low', 'high'},
     high = 'paths worn through grass',
     low = 'paths worn through grass, filling in more slowly'},
    {name = 'spatter', levels = {'off', 'low', 'high'},
     high = 'fallen fruit, nuts and leaves set down among the grass blades',
     low = 'thinned and shadowed, but lying on top of the grass'},
    {name = 'shade', levels = {'off', 'high'},
     high = 'shade under roofs and tree canopies'},
    {name = 'murky', levels = {'off', 'high'},
     high = 'stagnant water tinted a pond\'s green'},
    {name = 'leaves', levels = {'off', 'high'},
     high = 'leaves falling in autumn'},
    {name = 'petals', levels = {'off', 'high'},
     high = 'blossom falling in spring'},
}

-- low keeps what makes the map read as the weather (the ground's look, rain, snow and fog, snow
-- and the look on ramps) and the seasons (falling leaves and blossom: without those most of what
-- there is to see has gone, Poss), and drops the rest. The trees are off too, in the game's own
-- colours against the recoloured ground: they are the largest cost while the view moves, and the
-- profile is for machines that can't spare it (Poss).
-- medium is low with the picture made whole: trees and buildings in the look's colours (still),
-- the grass leaning (together), worn paths, shade and murky water. No sway, sweeping gusts,
-- rustle or spatter in the grass.
PROFILES = {
    high = {},   -- every part at high
    medium = {trees = 'low', grass = 'low', ramps = 'low', frost = 'low', paths = 'low', spatter = 'off'},
    low = {trees = 'off', grass = 'off', ramps = 'low', frost = 'low', paths = 'off', spatter = 'off',
           shade = 'off', murky = 'off'},
    off = {},    -- every part off: filled in below
}
PROFILE_NAMES = {'off', 'low', 'medium', 'high'}
for _, part in ipairs(PARTS) do PROFILES.off[part.name] = 'off' end

local part_named = {}
for _, part in ipairs(PARTS) do part_named[part.name] = part end

local function has_level(part, level)
    for _, known in ipairs(part.levels) do
        if known == level then return true end
    end
    return false
end

-- Every part's level for a profile.
local function profile_values(name)
    local values = {}
    for _, part in ipairs(PARTS) do values[part.name] = PROFILES[name][part.name] or 'high' end
    return values
end

-- The saved choices. With nothing saved, the DEFAULT_PROFILE: the file is only written when the
-- player sets something, so every install that never touched the settings follows the default,
-- including ones from 1.4, when it was high. (Medium since 1.5: high's sweeping gusts and rustle
-- in the grass looked jittery and cost the most, Poss.) A saved file is kept exactly as it is,
-- high included, since the player chose it; a part it doesn't mention takes the default's level.
DEFAULT_PROFILE = 'medium'
local function load()
    local ok, saved = pcall(json.decode_file, CONFIG_FILE)
    if not ok or type(saved) ~= 'table' then saved = {} end
    local values = profile_values(DEFAULT_PROFILE)
    for _, part in ipairs(PARTS) do
        if has_level(part, saved[part.name]) then values[part.name] = saved[part.name] end
    end
    return values
end

values = values or load()   -- part name -> 'off' | 'low' | 'high'

local function save()
    pcall(json.encode_file, values, CONFIG_FILE)
end

function get(name) return values[name] end

-- Sets one part. 'on' means high. Returns true, or false and why not.
function set(name, level)
    local part = part_named[name]
    if not part then return false, 'no part called ' .. tostring(name) end
    if level == 'on' then level = 'high' end
    if not has_level(part, level) then
        return false, ('%s can be %s'):format(name, table.concat(part.levels, ', '))
    end
    values[name] = level
    save()
    return true
end

-- Sets every part as a profile has it. Returns true, or false and why not.
function set_profile(name)
    if not PROFILES[name] then return false, 'the profiles are ' .. table.concat(PROFILE_NAMES, ', ') end
    values = profile_values(name)
    save()
    return true
end

-- The profile the parts are all at now: 'low', 'high', or 'custom'.
function profile()
    for _, name in ipairs(PROFILE_NAMES) do
        local wanted, same = profile_values(name), true
        for part, level in pairs(wanted) do
            if values[part] ~= level then same = false end
        end
        if same then return name end
    end
    return 'custom'
end

-- The share of its usual time a frame a part gets: 1, or LOW_ALLOWANCE at low.
function allowance(name)
    return values[name] == 'low' and LOW_ALLOWANCE or 1
end

-- The lines `detailed_weather settings` prints: each part, its level and what that gives.
function lines()
    local out = {('  profile    %s'):format(profile())}
    for _, part in ipairs(PARTS) do
        local level = values[part.name]
        local gives = level == 'off' and 'not drawn' or level == 'low' and part.low or part.high
        out[#out + 1] = ('  %-10s %-5s %s'):format(part.name, level, gives)
    end
    return out
end
