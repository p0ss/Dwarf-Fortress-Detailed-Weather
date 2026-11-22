--@ module = true
-- internal/detailed_weather/install.lua
-- ==========================================
-- THE HOOK DLL'S INSTALLER: puts dfhooks_detailed_weather.dll where DF loads it
-- ==========================================
-- (grungeisdead's copy, 2026-11-20, test 16A) Ported from Stockhook's installer
-- (stockhook-install.lua, as Refinish Metal's refinish-stockhook-install.lua carries it): the same
-- sequence, the same reasons.
--
-- WHAT: copies the hook DLL from Detailed Weather's own folder into DF's install folder as
-- dfhooks_detailed_weather.dll, the first time a fort with Detailed Weather in its load order is
-- loaded, and again whenever the mod's copy changes (an update, or a new build put in the mod's
-- folder). A copy made this session takes effect at the next launch, and a prompt says so once.
-- The player's whole install: load a fort with Detailed Weather, close DF, start it again. Without
-- the DLL everything still runs, drawn by the Lua as before (native.lua: each part runs natively
-- only while the DLL's block is found).
--
-- ACTIVE WORLDS ONLY: this file lives in scripts_modactive/, so nothing of it runs in a world
-- without Detailed Weather.
--
-- WHY A COPY, NOT AN .INI (Stockhook's findings: dfhooks, ChainLoader.cpp and LibWrapper.cpp, the
-- build DFHack 53.16-r3 ships):
--   * DF's chain-loader loads every dfhooks_*.dll in the install folder, and an .ini there may
--     instead name a DLL anywhere by its path.
--   * An .ini naming a missing file is fatal to EVERY hook library: the loader calls
--     std::filesystem::canonical on the path, which throws for a missing file, and DFHack itself
--     would not load. Unsubscribing the mod would leave such an .ini pointing at nothing.
--   * A copied DLL left behind after the mod is removed is harmless: with no Lua side its block
--     stays empty and it passes every call to DF unchanged (detailed_weather_dll.cpp: nothing is
--     drawn until Lua fills its block).
--
-- REPLACING A LOADED DLL: Windows won't overwrite or delete a DLL that's loaded, but will rename it
-- (Stockhook's test 14, in play). The old copy is renamed to dfhooks_detailed_weather.dll.old, or
-- .old1 to .old9 when an earlier one is still held (SET-ASIDE NAMES; the loader takes only .dll and
-- .ini, so all are ignored), and the new one written in its place; set-aside copies are deleted at a
-- later run, once nothing holds them.
--
-- THE HOOK VERSION (Stockhook's, for when more than one copy ships the DLL): one number for the DLL
-- this copy ships, written beside it in DF's folder (VERSION_NAME). DF's number higher: newer files
-- from another copy, left alone. The same or lower: the DLL is written whenever the bytes differ.
-- RAISE HOOK_VERSION with the DLL's LAYOUT (native.lua's must match the DLL's anyway).
--
-- WHERE THE MOD'S COPY IS: the mod's own folder, beside info.txt, found from this script's path
-- (dfhack.findScript): <mod>/scripts_modactive/internal/detailed_weather/install.lua. That works
-- wherever DF keeps the mod (the Workshop folder, mods/, data/installed_mods/).
--
-- COMMANDS (detailed_weather.lua): detailed_weather install, detailed_weather uninstall.
-- API: check(popup), uninstall(), log_path()

local DLL_NAME = 'dfhooks_detailed_weather.dll'
local HOOK_VERSION = 38   -- (the DLL's LAYOUT: detailed_weather_dll.cpp and native.lua)
local VERSION_NAME = 'detailed_weather_hook_version.txt'
local LOG_NAME = 'detailed_weather_install.log'

-- What this file keeps on _G, so a script reload doesn't check twice in a session.
_G.detailed_weather_install = _G.detailed_weather_install or {}
local G = _G.detailed_weather_install

-- ==========================================
-- PATHS
-- ==========================================
local function as_dir(p)
    p = tostring(p or ''):gsub('\\', '/')
    if p ~= '' and p:sub(-1) ~= '/' then p = p .. '/' end
    return p
end

-- The mod's own copy: <mod>/dfhooks_detailed_weather.dll. nil when this script isn't on the
-- script path (the mod isn't active in this world).
local function source_path()
    local me = dfhack.findScript('internal/detailed_weather/install')
    if not me then return nil end
    me = me:gsub('\\', '/')
    local mod_root = me:match('^(.*)/scripts_modactive/internal/detailed_weather/[^/]+$')
    if not mod_root then return nil end
    return mod_root .. '/' .. DLL_NAME
end

local function target_path(name)
    return as_dir(dfhack.filesystem.getInstallDir()) .. (name or DLL_NAME)
end

function log_path() return target_path(LOG_NAME) end

-- ==========================================
-- THE LOG: a line a step, in DF's folder (no console prints)
-- ==========================================
local function log_line(msg)
    pcall(function()
        local f = io.open(log_path(), 'a')
        if f then
            f:write(('[%s] %s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), msg))
            f:close()
        end
    end)
end

-- ==========================================
-- FILES
-- ==========================================
local function read_all(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function write_all(path, data)
    local f, err = io.open(path, 'wb')
    if not f then return false, err end
    local ok, werr = f:write(data)
    f:close()
    if not ok then return false, werr end
    return true
end

-- DF's folder's hook version (THE HOOK VERSION), or nil when it has none.
local function read_version()
    local f = io.open(target_path(VERSION_NAME), 'r')
    if not f then return nil end
    local n = tonumber((f:read('*l') or ''):match('%d+'))
    f:close()
    return n
end

-- Records this copy's version once DF's folder holds its DLL. had: the number read at the start of
-- the check, so an unchanged number isn't written again.
local function note_version(had)
    if had == HOOK_VERSION then return end
    local ok, err = write_all(target_path(VERSION_NAME), tostring(HOOK_VERSION) .. '\n')
    if not ok then log_line('could not write ' .. VERSION_NAME .. ': ' .. tostring(err)) end
end

-- ==========================================
-- SET-ASIDE NAMES
-- ==========================================
-- A DLL moved aside goes to the first free name of .old, .old1 ... .old9. Several may be needed in
-- one session: a copy renamed earlier in the session is still loaded, can't be deleted, and blocks
-- its name. The loader takes only .dll and .ini, so every one of these is ignored, and each is
-- deleted once nothing holds it.
local ASIDE = {'.old'}
for i = 1, 9 do ASIDE[#ASIDE + 1] = '.old' .. i end

-- Deletes every set-aside copy nothing holds any more (one still loaded fails quietly, and is tried
-- again at a later run).
local function clear_aside()
    local dst = target_path()
    for _, ext in ipairs(ASIDE) do os.remove(dst .. ext) end
end

-- Renames the installed DLL to the first free set-aside name: that path, or nil and why.
local function move_aside()
    local dst = target_path()
    clear_aside()
    for _, ext in ipairs(ASIDE) do
        if not dfhack.filesystem.exists(dst .. ext) then
            local ok, err = os.rename(dst, dst .. ext)
            if ok then return dst .. ext end
            return nil, tostring(err)
        end
    end
    return nil, 'every set-aside name is taken; restart DF and try again'
end

-- ==========================================
-- THE RESTART PROMPT
-- ==========================================
-- DF loads hook DLLs only when the program starts, so the text says to close DF completely
-- ("Restart" alone read as "back to the title screen" in Stockhook's test 14). what: 'installed'
-- or 'updated'.
local function restart_prompt(what)
    local text = ('Detailed Weather\'s drawing hook was %s. Close Dwarf Fortress completely and start it'
        .. ' again to finish. Until then Detailed Weather draws everything the slower way, as before.'):format(what)
    local ok, err = pcall(function() require('gui.dialogs').showMessage('Detailed Weather', text, COLOR_WHITE) end)
    if not ok then log_line('the restart prompt failed: ' .. tostring(err)) end
end

-- ==========================================
-- CHECK: install or update when the copies differ
-- ==========================================
-- Returns 'current', 'installed', 'updated', 'newer', or nil and why. popup: show the restart prompt
-- when the DLL changed this session.
function check(popup)
    -- copies set aside earlier are free to go once nothing holds them
    clear_aside()

    local src = source_path()
    if not src then return nil, 'Detailed Weather not active in this world' end
    local new = read_all(src)
    if not new or #new == 0 then
        log_line('no ' .. DLL_NAME .. ' in the mod folder (' .. src .. ')')
        return nil, 'no DLL in the mod folder'
    end

    -- ---- NEWER FILES ARE LEFT ALONE (THE HOOK VERSION) ----
    local had = read_version()
    if had and had > HOOK_VERSION then
        log_line(('DF\'s folder holds hook version %d, newer than this copy\'s %d; left alone.'):format(had, HOOK_VERSION))
        return 'newer'
    end

    local dst = target_path()
    local old = read_all(dst)
    if old == new then
        note_version(had)
        return 'current'
    end

    -- ---- MOVE THE OLD COPY ASIDE (a loaded DLL can be renamed, not overwritten) ----
    local aside = nil
    if old then
        local err
        aside, err = move_aside()
        if not aside then
            log_line('could not move the old DLL aside: ' .. tostring(err))
            return nil, 'old DLL not renamable: ' .. tostring(err)
        end
    end

    -- ---- WRITE THE NEW ONE ----
    -- Under a temporary name first, so a failed write never leaves a truncated DLL for the loader.
    local tmp = dst .. '.new'
    local ok, err = write_all(tmp, new)
    if ok then ok, err = os.rename(tmp, dst) end
    if not ok then
        os.remove(tmp)
        if aside then os.rename(aside, dst) end   -- (the old one put back)
        log_line('could not write ' .. dst .. ': ' .. tostring(err))
        return nil, 'install folder not writable'
    end

    note_version(had)
    local what = old and 'updated' or 'installed'
    log_line(('DLL %s at %s; takes effect at the next launch'):format(what, dst))
    if popup then restart_prompt(what) end
    return what
end

-- ==========================================
-- UNINSTALL
-- ==========================================
-- The DLL is moved to a set-aside name (deleted at a later check, or by the player once DF is
-- closed). From the next launch DF no longer loads it.
function uninstall()
    local dst = target_path()
    if not dfhack.filesystem.isfile(dst) then return false, 'not installed' end
    local aside, err = move_aside()
    if not aside then return false, err end
    os.remove(target_path(VERSION_NAME))      -- (THE HOOK VERSION: nothing installed now)
    log_line('uninstalled: DLL moved to ' .. aside .. '; not loaded from the next launch')
    return true
end

-- ==========================================
-- MAP LOAD: checked once a session, once a map is up
-- ==========================================
-- At a map load rather than the script's load, so the prompt has a screen to show on. Once a
-- session: a copy made earlier this session is already in place. A reload of this file with a map
-- already up checks then.
local function check_now()
    if G.checked then return end
    local ok, what, why = pcall(check, true)
    if not ok then
        log_line('check failed: ' .. tostring(what))
    elseif what then
        G.checked = true
    else
        log_line('not done: ' .. tostring(why))
    end
end

if dfhack_flags and dfhack_flags.module then
    dfhack.onStateChange['detailed_weather:install'] = function(code)
        if code == SC_MAP_LOADED and not G.checked then dfhack.timeout(1, 'frames', check_now) end
    end
    if dfhack.isMapLoaded() and not G.checked then dfhack.timeout(1, 'frames', check_now) end
end
