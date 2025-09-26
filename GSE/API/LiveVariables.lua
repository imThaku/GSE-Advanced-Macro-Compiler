local GSE = GSE
local Statics = GSE.Static

local L = GSE.L

local GNOME = "LiveVariables"

-- Real-time variable management system
GSE.LiveVariables = {}
GSE.LiveVariableTimers = {}
GSE.LiveVariableCache = {}
GSE.LiveVariableDebug = {}  -- Store debug state for each variable
GSE.LiveVariableSettings = {}  -- Store persistent settings for each variable

local LiveVariableDefaults = {
    updateInterval = 100, -- ms
    maxUpdateInterval = 10000, -- 10 seconds maximum
    minUpdateInterval = 50, -- 50ms minimum
    maxLiveVariables = 50, -- Limit for number of real-time variables
    cacheTimeout = 30000, -- 30 seconds before cache cleanup
}

-- Load conditions for Live Variables (inspired by WeakAuras)
local LiveVariableLoadConditions = {
    ["Always"] = {
        name = L["Always"],
        check = function() return true end
    },
    ["In Combat"] = {
        name = L["In Combat"],
        check = function() return UnitAffectingCombat("player") end
    },
    ["Not In Combat"] = {
        name = L["Not In Combat"],
        check = function() return not UnitAffectingCombat("player") end
    },
    ["Alive"] = {
        name = L["Alive"],
        check = function() return not UnitIsDeadOrGhost("player") end
    },
    ["Dead"] = {
        name = L["Dead"],
        check = function() return UnitIsDeadOrGhost("player") end
    },
    ["In Group"] = {
        name = L["In Group"],
        check = function() return IsInGroup() end
    },
    ["In Raid"] = {
        name = L["In Raid"],
        check = function() return IsInRaid() end
    },
    ["In Instance"] = {
        name = L["In Instance"],
        check = function() return IsInInstance() end
    },
    ["In PvP"] = {
        name = L["In PvP"],
        check = function() return UnitIsPVP("player") end
    },
    ["Has Target"] = {
        name = L["Has Target"],
        check = function() return UnitExists("target") end
    },
    ["Target Is Enemy"] = {
        name = L["Target Is Enemy"],
        check = function() return UnitExists("target") and UnitCanAttack("player", "target") end
    },
    ["Mounted"] = {
        name = L["Mounted"],
        check = function() return IsMounted() end
    },
    ["Not Mounted"] = {
        name = L["Not Mounted"],
        check = function() return not IsMounted() end
    },
    ["In Vehicle"] = {
        name = L["In Vehicle"],
        check = function() return UnitInVehicle("player") end
    },
    ["Not In Vehicle"] = {
        name = L["Not In Vehicle"],
        check = function() return not UnitInVehicle("player") end
    }
}

-- Default configuration for options
if not GSEOptions then
    GSEOptions = {}
end
if not GSEOptions.LiveVariables then
    GSEOptions.LiveVariables = LiveVariableDefaults
end
if not GSEOptions.LiveVariableSettings then
    GSEOptions.LiveVariableSettings = {}
end

-- Initialize runtime settings from saved data
GSE.LiveVariableSettings = GSEOptions.LiveVariableSettings or {}

-- Function to force save Live Variable settings
function GSE.SaveLiveVariableSettings()
    if GSEOptions then
        GSEOptions.LiveVariableSettings = GSE.LiveVariableSettings
        GSE.PrintDebugMessage("Forced save of Live Variable settings", GNOME)
    end
end

-- Function to check if load conditions are met for a variable
local function CheckLoadConditions(varName)
    local settings = GSE.LiveVariableSettings[varName]
    if not settings or not settings.loadConditions or #settings.loadConditions == 0 then
        -- No conditions specified, always load
        return true
    end

    -- Check all specified conditions (AND logic - all must be true)
    for _, conditionKey in ipairs(settings.loadConditions) do
        local condition = LiveVariableLoadConditions[conditionKey]
        if condition and not condition.check() then
            return false
        end
    end

    return true
end

-- Function to get available load conditions
function GSE.GetLiveVariableLoadConditions()
    local conditions = {}
    for key, condition in pairs(LiveVariableLoadConditions) do
        conditions[key] = condition.name
    end
    return conditions
end

-- Utility function to validate Lua code
local function ValidateLuaCode(code)
    if not code or type(code) ~= "string" or code:trim() == "" then
        return false, L["LiveLua code cannot be empty"]
    end

    -- Test code compilation - try as complete function first
    local testFunc, err = loadstring(code)
    if not testFunc then
        -- If it fails, try with "return " prefix for backward compatibility
        testFunc, err = loadstring("return " .. code)
        if not testFunc then
            return false, L["Lua syntax error: "] .. tostring(err)
        end
    end

    return true, nil
end

-- Utility function to validate update interval
local function ValidateUpdateInterval(interval)
    if type(interval) ~= "number" then
        return false, L["Interval must be a number"]
    end

    -- Ensure GSEOptions.LiveVariables is initialized
    if not GSEOptions or not GSEOptions.LiveVariables then
        GSEOptions = GSEOptions or {}
        GSEOptions.LiveVariables = LiveVariableDefaults
    end

    if interval < GSEOptions.LiveVariables.minUpdateInterval then
        return false, string.format(L["Minimum interval is %dms"], GSEOptions.LiveVariables.minUpdateInterval)
    end

    if interval > GSEOptions.LiveVariables.maxUpdateInterval then
        return false, string.format(L["Maximum interval is %dms"], GSEOptions.LiveVariables.maxUpdateInterval)
    end

    return true, nil
end

-- Function to safely execute LiveLua variable code (using same logic as classic variables)
local function ExecuteLiveVariableCode(code, varName)
    -- Check load conditions before executing
    if not CheckLoadConditions(varName) then
        -- Store a special "not loaded" state in cache
        GSE.LiveVariableCache[varName] = {
            value = nil,
            timestamp = GetTime(),
            error = nil,
            notLoaded = true
        }

        -- Debug output if enabled for this variable
        if GSE.LiveVariableDebug[varName] then
            local debugMsg = string.format("[LiveVar Debug] %s = <not loaded> (conditions not met)", varName)
            print(debugMsg)
            GSE.PrintDebugMessage(debugMsg, GNOME)
        end

        return nil
    end

    local success, result = pcall(function()
        -- Use the exact same logic as classic GSE variables
        -- Create the function using loadstring("return " .. code) and execute it immediately
        local func = loadstring("return " .. code)
        if func then
            -- Execute to get the function, then call it to get the result
            local userFunc = func()
            if type(userFunc) == "function" then
                return userFunc()
            else
                -- Fallback for non-function returns
                return userFunc
            end
        end

        return nil
    end)

    if success then
        GSE.LiveVariableCache[varName] = {
            value = result,
            timestamp = GetTime(),
            error = nil,
            notLoaded = false
        }

        -- Debug output if enabled for this variable
        if GSE.LiveVariableDebug[varName] then
            local debugMsg = string.format("[LiveVar Debug] %s = %s", varName, tostring(result))
            print(debugMsg)  -- Print to chat
            GSE.PrintDebugMessage(debugMsg, GNOME)
        end

        return result
    else
        GSE.LiveVariableCache[varName] = {
            value = nil,
            timestamp = GetTime(),
            error = result
        }

        -- Debug output for errors if enabled for this variable
        if GSE.LiveVariableDebug[varName] then
            local errorMsg = string.format("[LiveVar Error] %s: %s", varName, tostring(result))
            print(errorMsg)  -- Print to chat
        end

        GSE.PrintDebugMessage("Error in LiveLua variable '" .. varName .. "': " .. tostring(result), GNOME)
        return nil
    end
end

-- Function to create a timer for a LiveLua variable
function GSE.CreateLiveVariableTimer(varName, code, updateInterval, debugMode, loadConditions)
    -- Ensure GSEOptions.LiveVariables is initialized
    if not GSEOptions or not GSEOptions.LiveVariables then
        GSEOptions = GSEOptions or {}
        GSEOptions.LiveVariables = LiveVariableDefaults
    end

    -- Validate parameters
    local isValidCode, codeError = ValidateLuaCode(code)
    if not isValidCode then
        GSE.Print(L["LiveLua variable error "] .. varName .. ": " .. codeError, GNOME)
        return false
    end

    local isValidInterval, intervalError = ValidateUpdateInterval(updateInterval)
    if not isValidInterval then
        GSE.Print(L["LiveLua variable error "] .. varName .. ": " .. intervalError, GNOME)
        return false
    end

    -- Stop existing timer if there is one
    GSE.StopLiveVariableTimer(varName)

    -- Set debug mode for this variable
    if debugMode ~= nil then
        GSE.LiveVariableDebug[varName] = debugMode
        if debugMode then
            print(string.format("[LiveVar Debug] Debug mode enabled for '%s'", varName))
        end
    else
        GSE.LiveVariableDebug[varName] = false
    end

    -- Store persistent settings (preserve existing comments and author if updating)
    local existingSettings = GSE.LiveVariableSettings[varName]
    GSE.LiveVariableSettings[varName] = {
        code = code,
        updateInterval = updateInterval,
        debugMode = GSE.LiveVariableDebug[varName] or false,
        loadConditions = loadConditions or {},
        created = existingSettings and existingSettings.created or GetTime(),
        updated = GetTime(),
        Author = existingSettings and existingSettings.Author or GSE.GetCharacterName(),
        comments = existingSettings and existingSettings.comments or ""
    }
    GSE.SaveLiveVariableSettings()

    -- Check variable count limit
    local currentCount = 0
    for _ in pairs(GSE.LiveVariableTimers) do
        currentCount = currentCount + 1
    end

    if currentCount >= GSEOptions.LiveVariables.maxLiveVariables then
        GSE.Print(L["LiveLua variable limit reached: "] .. GSEOptions.LiveVariables.maxLiveVariables, GNOME)
        return false
    end

    -- Create the function and add it to GSE.V exactly like classic variables
    local success, compileError = pcall(function()
        GSE.V[varName] = loadstring("return " .. code)()
    end)

    if not success then
        GSE.Print(L["LiveLua variable error "] .. varName .. ": " .. tostring(compileError), GNOME)
        return false
    end

    -- Initial execution to have a value immediately
    ExecuteLiveVariableCode(code, varName)

    -- Create timer with specified interval - this will keep updating the cached value
    GSE.LiveVariableTimers[varName] = C_Timer.NewTicker(updateInterval / 1000, function()
        ExecuteLiveVariableCode(code, varName)
    end)

    GSE.PrintDebugMessage("LiveLua timer created for '" .. varName .. "' with interval " .. updateInterval .. "ms", GNOME)
    return true
end

-- Function to stop the timer of a LiveLua variable
function GSE.StopLiveVariableTimer(varName)
    if GSE.LiveVariableTimers[varName] then
        GSE.LiveVariableTimers[varName]:Cancel()
        GSE.LiveVariableTimers[varName] = nil
        GSE.LiveVariableCache[varName] = nil

        -- Clean up from GSE.V like classic variables
        GSE.V[varName] = nil

        -- Clean up debug state and notify if it was in debug mode
        if GSE.LiveVariableDebug[varName] then
            print(string.format("[LiveVar Debug] Debug mode disabled for '%s' (variable deleted)", varName))
        end
        GSE.LiveVariableDebug[varName] = nil

        -- Clean up persistent settings
        GSE.LiveVariableSettings[varName] = nil
        GSE.SaveLiveVariableSettings()

        GSE.PrintDebugMessage("LiveLua timer stopped for '" .. varName .. "'", GNOME)
    end
end

-- Function to get current value of a LiveLua variable
function GSE.GetLiveVariableValue(varName)
    -- First try to get from GSE.V like classic variables
    if GSE.V[varName] and type(GSE.V[varName]) == "function" then
        local success, result = pcall(GSE.V[varName])
        if success then
            return result
        end
    end

    -- Fallback to cached value
    if GSE.LiveVariableCache[varName] then
        local cache = GSE.LiveVariableCache[varName]
        if cache.error then
            GSE.PrintDebugMessage("LiveLua variable '" .. varName .. "' in error: " .. cache.error, GNOME)
            return nil
        end
        return cache.value
    end
    return nil
end

-- Function to get persistent settings for a LiveLua variable
function GSE.GetLiveVariableSettings(varName)
    return GSE.LiveVariableSettings[varName]
end

-- Function to toggle debug mode for a LiveLua variable
function GSE.ToggleLiveVariableDebug(varName)
    if not GSE.LiveVariableTimers[varName] then
        return false, "Variable '" .. varName .. "' does not exist"
    end

    GSE.LiveVariableDebug[varName] = not GSE.LiveVariableDebug[varName]
    local isEnabled = GSE.LiveVariableDebug[varName]

    -- Update persistent settings
    if GSE.LiveVariableSettings[varName] then
        GSE.LiveVariableSettings[varName].debugMode = isEnabled
        GSE.SaveLiveVariableSettings()
    end

    local message = string.format("[LiveVar Debug] Debug mode %s for '%s'",
                                isEnabled and "enabled" or "disabled", varName)
    print(message)

    return true, message
end

-- Function to cleanup all timers (used on logout)
function GSE.CleanupLiveVariables()
    GSE.PrintDebugMessage("Cleaning up LiveLua variables...", GNOME)
    for varName in pairs(GSE.LiveVariableTimers) do
        GSE.StopLiveVariableTimer(varName)
    end
    GSE.LiveVariableTimers = {}
    GSE.LiveVariableCache = {}
    GSE.LiveVariableDebug = {}
    -- Note: GSE.LiveVariableSettings is kept for persistence across sessions
end

-- Function to get statistics on LiveLua variables
function GSE.GetLiveVariableStats()
    local stats = {
        activeCount = 0,
        cachedCount = 0,
        errorCount = 0
    }

    for _ in pairs(GSE.LiveVariableTimers) do
        stats.activeCount = stats.activeCount + 1
    end

    for varName, cache in pairs(GSE.LiveVariableCache) do
        stats.cachedCount = stats.cachedCount + 1
        if cache.error then
            stats.errorCount = stats.errorCount + 1
        end
    end

    return stats
end

-- Automatic cleanup of expired variable cache
local function CleanupExpiredCache()
    -- Ensure GSEOptions.LiveVariables is initialized
    if not GSEOptions or not GSEOptions.LiveVariables then
        GSEOptions = GSEOptions or {}
        GSEOptions.LiveVariables = LiveVariableDefaults
    end

    local currentTime = GetTime()
    local timeout = GSEOptions.LiveVariables.cacheTimeout / 1000

    for varName, cache in pairs(GSE.LiveVariableCache) do
        if not GSE.LiveVariableTimers[varName] and (currentTime - cache.timestamp) > timeout then
            GSE.LiveVariableCache[varName] = nil
            GSE.PrintDebugMessage("Expired cache cleaned for '" .. varName .. "'", GNOME)
        end
    end
end

-- Cache cleanup timer (every 5 minutes) - delayed initialization
local cacheCleanupTimer
local function InitializeCacheCleanupTimer()
    if not cacheCleanupTimer then
        -- Ensure GSEOptions.LiveVariables is initialized before creating the timer
        if not GSEOptions or not GSEOptions.LiveVariables then
            GSEOptions = GSEOptions or {}
            GSEOptions.LiveVariables = LiveVariableDefaults
        end
        cacheCleanupTimer = C_Timer.NewTicker(300, CleanupExpiredCache)
    end
end

-- Initialize timer after a small delay to ensure all options are loaded
C_Timer.After(1, InitializeCacheCleanupTimer)

-- Event handler for cleanup on logout
local liveVariableEventFrame = CreateFrame("Frame")
liveVariableEventFrame:RegisterEvent("PLAYER_LOGOUT")
liveVariableEventFrame:RegisterEvent("PLAYER_CAMPING")
liveVariableEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" or event == "PLAYER_CAMPING" then
        GSE.CleanupLiveVariables()
        if cacheCleanupTimer then
            cacheCleanupTimer:Cancel()
        end
    end
end)

-- Function to restore LiveLua variables from saved settings
function GSE.RestoreLiveVariables()
    -- Re-initialize from saved options to ensure we have the latest data
    if GSEOptions and GSEOptions.LiveVariableSettings then
        GSE.LiveVariableSettings = GSEOptions.LiveVariableSettings
    else
        GSE.PrintDebugMessage("No saved LiveVariable settings found", GNOME)
        return
    end

    local restoredCount = 0
    for varName, settings in pairs(GSE.LiveVariableSettings) do
        if settings.code and settings.updateInterval then
            local success = GSE.CreateLiveVariableTimer(
                varName,
                settings.code,
                settings.updateInterval,
                settings.debugMode,
                settings.loadConditions
            )
            if success then
                restoredCount = restoredCount + 1
                GSE.PrintDebugMessage("Restored LiveLua variable '" .. varName .. "'", GNOME)
            else
                GSE.PrintDebugMessage("Failed to restore LiveLua variable '" .. varName .. "'", GNOME)
            end
        else
            GSE.PrintDebugMessage("Skipping incomplete LiveVariable settings for '" .. varName .. "'", GNOME)
        end
    end

    if restoredCount > 0 then
        GSE.Print("Restored " .. restoredCount .. " Live Variables", "LiveVariables")
    end
end

-- Restore variables after addon is fully loaded and player has logged in
local restoreFrame = CreateFrame("Frame")
restoreFrame:RegisterEvent("ADDON_LOADED")
restoreFrame:RegisterEvent("PLAYER_LOGIN")

local addonLoaded = false
local playerLoggedIn = false

restoreFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "GSE" then
        addonLoaded = true
        GSE.PrintDebugMessage("GSE addon loaded, waiting for player login", GNOME)
    elseif event == "PLAYER_LOGIN" then
        playerLoggedIn = true
        GSE.PrintDebugMessage("Player logged in, checking if addon ready", GNOME)
    end

    -- Only restore when both conditions are met
    if addonLoaded and playerLoggedIn then
        C_Timer.After(3, function()  -- Increased delay to ensure everything is ready
            GSE.PrintDebugMessage("Attempting to restore Live Variables", GNOME)
            GSE.RestoreLiveVariables()
        end)
        restoreFrame:UnregisterEvent("ADDON_LOADED")
        restoreFrame:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Debug function to check Live Variable settings
function GSE.DebugLiveVariables()
    print("=== Live Variables Debug Info ===")
    print("GSEOptions exists:", GSEOptions and "YES" or "NO")
    print("GSEOptions.LiveVariableSettings exists:", GSEOptions and GSEOptions.LiveVariableSettings and "YES" or "NO")
    print("GSE.LiveVariableSettings exists:", GSE.LiveVariableSettings and "YES" or "NO")

    if GSE.LiveVariableSettings then
        local count = 0
        for k, v in pairs(GSE.LiveVariableSettings) do
            count = count + 1
            print("Saved variable:", k, "- Has code:", v.code and "YES" or "NO", "- Interval:", v.updateInterval)
        end
        print("Total saved variables:", count)
    end

    if GSE.LiveVariableTimers then
        local activeCount = 0
        for k, v in pairs(GSE.LiveVariableTimers) do
            activeCount = activeCount + 1
            print("Active variable:", k)
        end
        print("Total active variables:", activeCount)
    end
    print("=== End Debug Info ===")
end

-- Slash command for debugging
SLASH_GSELIVEDEBUG1 = "/gselivedebug"
SlashCmdList["GSELIVEDEBUG"] = GSE.DebugLiveVariables

GSE.PrintDebugMessage("LiveVariables system initialized", GNOME)