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

-- Function to safely execute LiveLua variable code
local function ExecuteLiveVariableCode(code, varName)
    local success, result = pcall(function()
        local func

        -- Try to load as complete function first (new format)
        func = loadstring(code)
        if func then
            -- Execute the function and get its result
            local compiledFunc = func()
            if type(compiledFunc) == "function" then
                return compiledFunc()
            else
                -- If it's not a function, return the value directly
                return compiledFunc
            end
        else
            -- Fallback to old format (expression with "return" prefix)
            func = loadstring("return " .. code)
            if func then
                return func()
            end
        end

        return nil
    end)

    if success then
        GSE.LiveVariableCache[varName] = {
            value = result,
            timestamp = GetTime(),
            error = nil
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
function GSE.CreateLiveVariableTimer(varName, code, updateInterval, debugMode)
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
        created = existingSettings and existingSettings.created or GetTime(),
        updated = GetTime(),
        Author = existingSettings and existingSettings.Author or GSE.GetCharacterName(),
        comments = existingSettings and existingSettings.comments or ""
    }
    GSEOptions.LiveVariableSettings = GSE.LiveVariableSettings

    -- Check variable count limit
    local currentCount = 0
    for _ in pairs(GSE.LiveVariableTimers) do
        currentCount = currentCount + 1
    end

    if currentCount >= GSEOptions.LiveVariables.maxLiveVariables then
        GSE.Print(L["LiveLua variable limit reached: "] .. GSEOptions.LiveVariables.maxLiveVariables, GNOME)
        return false
    end

    -- Initial execution to have a value immediately
    ExecuteLiveVariableCode(code, varName)

    -- Create timer with specified interval
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

        -- Clean up debug state and notify if it was in debug mode
        if GSE.LiveVariableDebug[varName] then
            print(string.format("[LiveVar Debug] Debug mode disabled for '%s' (variable deleted)", varName))
        end
        GSE.LiveVariableDebug[varName] = nil

        -- Clean up persistent settings
        GSE.LiveVariableSettings[varName] = nil
        GSEOptions.LiveVariableSettings = GSE.LiveVariableSettings

        GSE.PrintDebugMessage("LiveLua timer stopped for '" .. varName .. "'", GNOME)
    end
end

-- Function to get current value of a LiveLua variable
function GSE.GetLiveVariableValue(varName)
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
        GSEOptions.LiveVariableSettings = GSE.LiveVariableSettings
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
    if not GSE.LiveVariableSettings then
        return
    end

    for varName, settings in pairs(GSE.LiveVariableSettings) do
        if settings.code and settings.updateInterval then
            local success = GSE.CreateLiveVariableTimer(varName, settings.code, settings.updateInterval, settings.debugMode)
            if success then
                GSE.PrintDebugMessage("Restored LiveLua variable '" .. varName .. "'", GNOME)
            else
                GSE.PrintDebugMessage("Failed to restore LiveLua variable '" .. varName .. "'", GNOME)
            end
        end
    end
end

-- Restore variables after addon is fully loaded
local restoreFrame = CreateFrame("Frame")
restoreFrame:RegisterEvent("ADDON_LOADED")
restoreFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "GSE" then
        C_Timer.After(2, GSE.RestoreLiveVariables)  -- Small delay to ensure everything is loaded
        restoreFrame:UnregisterEvent("ADDON_LOADED")
    end
end)

GSE.PrintDebugMessage("LiveVariables system initialized", GNOME)