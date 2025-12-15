-- Mock 'enemies' BEFORE requiring calculator
local mockEnemies = {}
mockEnemies.damageEnemy = function(state, e, dmg, knock, kForce, isCrit, opts)
    -- Minimal mock of existing enemies.damageEnemy logic
    opts = opts or {}
    local applied = dmg
    
    -- Simulator behavior: if not ignoreArmor, apply reduction (Legacy fallback)
    if not opts.ignoreArmor and e.armor and e.armor > 0 then
        local armor = e.armor
        local dr = armor / (armor + 300)
        applied = applied * (1 - dr)
    end

    -- Legacy Shield Logic in damageEnemy (for verification that we are bypassing it correctly)
    -- In the real game, enemies.damageEnemy handles shield if bypassShield is false.
    -- Calculator should set bypassShield=true and handle it itself.
    -- If calculator works, it calculates hp damage and passes bypassShield=true.
    -- If we see shield damage here, it might mean calculator didn't handle it?
    -- Actually, calculator calls damageEnemy for the *Health* portion.
    -- Wait, looking at calculator.lua logic:
    -- It does `enemy.shield = enemy.shield - shieldHit` directly in calculator.
    -- Then calls `enemies.damageEnemy` with the remaining health damage and `bypassShield=true`.
    
    e.health = e.health - applied
    -- Return accepted damage
    return applied, 0, applied 
end

mockEnemies.applyStatus = function() end 

package.loaded['enemies'] = mockEnemies

-- Now require calculator
local calculator = require('calculator')

-- Mock Love2D 
if not love then love = { math = math } end

local function runTests()
    print("Running Calculator Tests...")
    local fails = 0

    -- Helper to mock an enemy
    local function mockEnemy(hp, armor, shield)
        return {
            hp = hp or 1000,
            health = hp or 1000,
            maxHp = hp or 1000,
            armor = armor or 0,
            baseArmor = armor or 0,
            shield = shield or 0,
            maxShield = shield or 0,
            x = 0, y = 0,
            status = {}
        }
    end

    -- Mock State
    local mockState = {
        playSfx = function() end,
        augments = { dispatch = function() end },
        texts = {},
        player = {x=0, y=0}
    }

    -- 1. Base Damage Test (No Armor)
    print("Test 1: Base Damage (100 dmg vs 0 armor)...")
    local e1 = mockEnemy(1000, 0, 0)
    local inst1 = calculator.createInstance({damage = 100})
    local res1 = calculator.applyHit(mockState, e1, inst1)
    if math.abs(res1.damage - 100) < 0.1 then
        print("  PASS")
    else
        print(string.format("  FAIL: Expected 100, got %s", tostring(res1.damage)))
        fails = fails + 1
    end

    -- 2. Armor Reduction Test (100 dmg vs 300 armor -> 50% DR)
    print("Test 2: Armor Reduction (100 dmg vs 300 armor)...")
    local e2 = mockEnemy(1000, 300, 0)
    local inst2 = calculator.createInstance({damage = 100})
    local res2 = calculator.applyHit(mockState, e2, inst2)
    -- Expect 50. If 25, bug exists.
    if math.abs(res2.damage - 50) < 0.1 then
        print("  PASS")
    elseif math.abs(res2.damage - 25) < 0.1 then
        print("  FAIL: Double Reduction Detected (Got 25)")
        fails = fails + 1
    else
        print(string.format("  FAIL: Expected 50, got %s", tostring(res2.damage)))
        fails = fails + 1
    end

    -- 3. Shield Logic: damage vs Shield
    print("Test 3: Shield (100 dmg vs 50 shield)...")
    local e3 = mockEnemy(1000, 0, 50) -- 1000 HP, 50 Shield
    local inst3 = calculator.createInstance({damage = 100})
    
    -- Calculator updates e.shield in place.
    local res3 = calculator.applyHit(mockState, e3, inst3)
    
    -- Expected:
    -- 50 damage goes to shield (breaking it)
    -- 50 damage goes to health
    -- Total damage in result = 100
    -- e3.shield should be 0
    -- e3.health should be 950
    
    if math.abs(res3.damage - 100) < 0.1 and e3.shield <= 0 and math.abs(e3.health - 950) < 0.1 then
        print("  PASS")
    else
        print(string.format("  FAIL: Dmg %s, Shield %s (Exp 0), HP %s (Exp 950)", tostring(res3.damage), tostring(e3.shield), tostring(e3.health)))
        fails = fails + 1
    end

    -- 4. Toxin Bypass: Toxin damage ignores Shield
    print("Test 4: Toxin Bypass (100 Toxin vs 1000 Shield)...")
    local e4 = mockEnemy(1000, 0, 1000) -- Huge shield
    -- Create instance with TOXIN element
    local inst4 = calculator.createInstance({
        damage = 100,
        damageBreakdown = {TOXIN = 1},
        effectType = 'TOXIN',
        elements = {'TOXIN'}
    })
    
    local res4 = calculator.applyHit(mockState, e4, inst4)
    
    -- Expected:
    -- Shield ignored (remains 1000)
    -- 100 Toxin Damage -> * 1.5 vs Flesh = 150 Damage
    -- Health should be 850
    
    if math.abs(e4.shield - 1000) < 0.1 then
        print("  PASS: Shield ignored.")
    else
        print(string.format("  FAIL: Shield took damage! Rem: %s", tostring(e4.shield)))
        fails = fails + 1
    end
    
    -- 5. Viral Amplification Test (100 dmg vs Viral'd enemy)
    print("Test 5: Viral Amplification (10 Viral Stacks)...")
    local eViral = mockEnemy(1000, 0, 0)
    eViral.status = { viralStacks = 10 } -- Max viral = +225% damage (Total 3.25x)
    -- Actually code says: 2.0 multiplier? let's check code. 
    -- "bonus = math.min(2.25, 0.75 + stacks * 0.25)" -> 10 stacks = 0.75 + 2.5 = 3.25.
    -- viralMultiplier = 1 + bonus = 4.25? 
    -- Wait, let's check calculator.lua buildDamageMods lines 274-278
    -- bonus = math.min(2.25, 0.75 + stacks * 0.25)
    -- opts.viralMultiplier = 1 + bonus.
    -- If stacks=10, 0.75 + 2.5 = 3.25. Min(2.25, 3.25) = 2.25.
    -- Multiplier = 1 + 2.25 = 3.25x.
    
    local instViral = calculator.createInstance({damage = 100})
    local resViral = calculator.applyHit(mockState, eViral, instViral)
    
    -- Expected: 100 * 3.25 = 325.
    if math.abs(resViral.damage - 325) < 1 then
        print("  PASS: Viral amplifier correct (325).")
    else
        print(string.format("  FAIL: Viral Amp. Expected 325, got %s", tostring(resViral.damage)))
        fails = fails + 1
    end

    -- 6. Magnetic Shield Bonus
    print("Test 6: Magnetic vs Shield...")
    local eMag = mockEnemy(1000, 0, 1000)
    -- Magnetic Status active on enemy? Or just Magnetic Damage type?
    -- Magnetic Damage Type vs Shield: DEFENSE_MODIFIERS['SHIELD']['MAGNETIC'] = 1.75
    local instMag = calculator.createInstance({
        damage = 100,
        damageBreakdown = {MAGNETIC=1},
        elements = {'MAGNETIC'}
    })
    local resMag = calculator.applyHit(mockState, eMag, instMag)
    local shieldDmg = resMag.damage
    -- shield is subtracted in calculator, so we check damage result (which is totalApplied) or eMag.shield change.
    
    -- Expected: 100 * 1.75 = 175 shield damage.
    local actualShieldDmg = 1000 - eMag.shield
    if math.abs(actualShieldDmg - 175) < 1 then
        print("  PASS: Magnetic vs Shield (175).")
    else
        print(string.format("  FAIL: Magnetic. Expected 175, got %s", tostring(actualShieldDmg)))
        fails = fails + 1
    end

    -- 7. Element Combination Logic
    print("Test 7: Elemental Combo (Heat + Cold -> Blast)...")
    -- combineElements is internal, but we can verify via createInstance result
    local instCombo = calculator.createInstance({
        damage = 100,
        elements = {'HEAT', 'COLD'},
        damageBreakdown = {HEAT=50, COLD=50}
    })
    -- Check if elements list contains BLAST and not Heat/Cold
    local hasBlast = false
    for _, e in ipairs(instCombo.elements) do
        if e == 'BLAST' then hasBlast = true end
    end
    if hasBlast and #instCombo.elements == 1 then
        print("  PASS: Heat + Cold combined to Blast.")
    else
        print("  FAIL: Elements did not combine correctly: " .. table.concat(instCombo.elements, ","))
        fails = fails + 1
    end

    -- 8. Critical Hit Logic
    print("Test 8: Critical Hit (Force 100% Crit)...")
    local eCrit = mockEnemy(1000, 0, 0)
    local instCrit = calculator.createInstance({
        damage = 100,
        critChance = 2.0, -- Force crit
        critMultiplier = 2.0
    })
    local resCrit = calculator.applyHit(mockState, eCrit, instCrit)
    if resCrit.isCrit and resCrit.damage == 200 then
         print("  PASS: Crit applied (200).")
    else
         print(string.format("  FAIL: Crit. IsCrit=%s, Damage=%s", tostring(resCrit.isCrit), tostring(resCrit.damage)))
         fails = fails + 1
    end

    print(string.format("\nTests Completed. Fails: %d", fails))
    return fails
end

if arg and arg[0] then
    runTests()
end

return runTests
