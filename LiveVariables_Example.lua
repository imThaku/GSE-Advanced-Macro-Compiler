--[[
    LiveLua Variables Usage Examples for GSE

    This file shows how to create and use the new LiveLua variables
    that automatically update every X milliseconds.
]]

-- Example LiveLua variables you can create in the GSE interface:

--[[
    1. Variable to monitor Killing Machine (Death Knight)

    Name: KillingMachine
    Type: LiveLua
    Interval: 100 (ms)
    Code:
    local km = select(1, AuraUtil.FindAuraByName("Killing Machine", "player", "HELPFUL"))
    return km and select(3, AuraUtil.FindAuraByName("Killing Machine", "player", "HELPFUL")) or 0
]]

--[[
    2. Variable to monitor combo points (Rogue/Druid)

    Name: ComboPoints
    Type: LiveLua
    Interval: 50 (ms)
    Code:
    return GetComboPoints("player", "target")
]]

--[[
    3. Variable to monitor target health percentage

    Name: TargetHealthPct
    Type: LiveLua
    Interval: 200 (ms)
    Code:
    if UnitExists("target") then
        return math.floor((UnitHealth("target") / UnitHealthMax("target")) * 100)
    else
        return 0
    end
]]

--[[
    4. Variable to monitor if a specific buff is active

    Name: HasBloodlust
    Type: LiveLua
    Interval: 100 (ms)
    Code:
    local buffs = {"Bloodlust", "Heroism", "Time Warp", "Ancient Hysteria"}
    for _, buffName in ipairs(buffs) do
        if AuraUtil.FindAuraByName(buffName, "player", "HELPFUL") then
            return true
        end
    end
    return false
]]

--[[
    5. Variable to count nearby enemies

    Name: EnemiesNearby
    Type: LiveLua
    Interval: 150 (ms)
    Code:
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) and UnitHealth(unit) > 0 then
            if CheckInteractDistance(unit, 3) then -- Interaction distance (~10 yards)
                count = count + 1
            end
        end
    end
    return count
]]

--[[
    USAGE IN SEQUENCES:

    Once your LiveLua variables are created, you can use them in your sequences
    exactly like classic variables:

    /cast [nochanneling] =GSE.V["KillingMachine"]() > 0 and "Obliterate" or "Frost Strike"

    Or with more complex conditions:

    /cast [nochanneling] =GSE.V["ComboPoints"]() >= 5 and "Eviscerate" or "Sinister Strike"
    /cast [nochanneling] =GSE.V["TargetHealthPct"]() < 35 and "Execute" or "Mortal Strike"
    /cast [nochanneling] =GSE.V["HasBloodlust"]() and "Recklessness" or "Heroic Strike"
    /cast [nochanneling] =GSE.V["EnemiesNearby"]() >= 3 and "Whirlwind" or "Mortal Strike"
]]

--[[
    ADVANTAGES OF LIVELUA VARIABLES:

    1. REAL-TIME: Values update automatically without recompilation
    2. PERFORMANCE: Each variable has its own optimized timer
    3. FLEXIBILITY: Configurable intervals based on needs (50ms to 10 seconds)
    4. ROBUSTNESS: Built-in error handling and automatic cleanup
    5. COMPATIBILITY: Identical usage to classic variables in macros

    BEST PRACTICES:

    - Use longer intervals (200-500ms) for data that changes less frequently
    - Use short intervals (50-100ms) for critical data like buffs/debuffs
    - Avoid complex calculations in LiveLua code to maintain performance
    - Always test your code in the editor before saving
]]