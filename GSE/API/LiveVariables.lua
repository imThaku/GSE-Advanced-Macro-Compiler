local GSE = GSE
local Statics = GSE.Static

local L = GSE.L

local GNOME = "LiveVariables"

-- Real-time variable management system
GSE.LiveVariables = {}
GSE.LiveVariableTimers = {}
GSE.LiveVariableCache = {}

local LiveVariableDefaults = {
    updateInterval = 100, -- ms
    maxUpdateInterval = 10000, -- 10 seconds maximum
    minUpdateInterval = 50, -- 50ms minimum
    maxLiveVariables = 50, -- Limit for number of real-time variables
    cacheTimeout = 30000, -- 30 seconds before cache cleanup
}

-- Default configuration for options
if not GSEOptions.LiveVariables then
    GSEOptions.LiveVariables = LiveVariableDefaults
end

-- Utility function to validate Lua code
local function ValidateLuaCode(code)
    if not code or type(code) ~= "string" or code:trim() == "" then
        return false, L["LiveLua code cannot be empty"]
    end

    -- Test code compilation
    local testFunc, err = loadstring("return " .. code)
    if not testFunc then
        return false, L["Lua syntax error: "] .. tostring(err)
    end

    return true, nil
end

-- Utility function to validate update interval
local function ValidateUpdateInterval(interval)
    if type(interval) ~= "number" then
        return false, L["Interval must be a number"]
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
        local func = loadstring("return " .. code)
        if func then
            return func()
        end
        return nil
    end)

    if success then
        GSE.LiveVariableCache[varName] = {
            value = result,
            timestamp = GetTime(),
            error = nil
        }
        return result
    else
        GSE.LiveVariableCache[varName] = {
            value = nil,
            timestamp = GetTime(),
            error = result
        }
        GSE.PrintDebugMessage("Error in LiveLua variable '" .. varName .. "': " .. tostring(result), GNOME)
        return nil
    end
end

-- Function to create a timer for a LiveLua variable
function GSE.CreateLiveVariableTimer(varName, code, updateInterval)
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

-- Function to cleanup all timers (used on logout)
function GSE.CleanupLiveVariables()
    GSE.PrintDebugMessage("Cleaning up LiveLua variables...", GNOME)
    for varName in pairs(GSE.LiveVariableTimers) do
        GSE.StopLiveVariableTimer(varName)
    end
    GSE.LiveVariableTimers = {}
    GSE.LiveVariableCache = {}
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
    local currentTime = GetTime()
    local timeout = GSEOptions.LiveVariables.cacheTimeout / 1000

    for varName, cache in pairs(GSE.LiveVariableCache) do
        if not GSE.LiveVariableTimers[varName] and (currentTime - cache.timestamp) > timeout then
            GSE.LiveVariableCache[varName] = nil
            GSE.PrintDebugMessage("Expired cache cleaned for '" .. varName .. "'", GNOME)
        end
    end
end

-- Cache cleanup timer (every 5 minutes)
local cacheCleanupTimer = C_Timer.NewTicker(300, CleanupExpiredCache)

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

GSE.PrintDebugMessage("LiveVariables system initialized", GNOME)