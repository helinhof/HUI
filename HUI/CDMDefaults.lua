-- HUI - Cooldown manager: class defaults
--
-- The layout a spec starts with the first time it's used (and after "Reset
-- spec to class default"). One block per class, one entry per talent tree
-- ([1] [2] [3], the order of the talent tabs); healing trees are left out.
-- Each tree: { top row }, { bottom row }.
--
-- An entry is:
--   a spell id                       12294
--   alternatives (first one known)   { 2825, 32182 }   -- Bloodlust / Heroism
--   a table with options             { id = 1943, aura = "Rupture", rules = { { c = "aura_below", v = 2, a = "glow" } } }
--     rules: { c = condition, a = action, v = number, aura = name or spell id,
--              andPrev = true (joins the rule above), col = { r =, g =, b = } }
--   an item                          { t = "item", id = 40211 }
--
-- To replace a class: set it up in game (/hui cdm), press "Export class
-- layouts" on the Cooldown Manager page and paste the text over the class
-- block below.

local A = HUI
local BL = { 2825, 32182 }   -- Bloodlust (Horde) / Heroism (Alliance)

-- grey while the aura isn't up (your debuff on the target / your buff)
local GREY_MISSING = { c = "aura_missing", a = "desat" }

-- Hunter's Mark: anyone's mark counts; glows (in or out of combat) when the
-- enemy you target has none
local HM = { id = 1130, anyCaster = true, rules = { { c = "debuff_missing", a = "glow", ooc = true }, GREY_MISSING } }

-- Faerie Fire: anyone's, the caster and the feral version are the same debuff
local FF_ANY = { 770, 16857 }

-- Mirror Image: its buff is Quad Core (mage T10 4-piece), a big cooldown buff
local MIRROR = { id = 55342, aura = { 70747, "Quad Core" } }

-- the 5% spell crit debuff: Improved Scorch or Shadow Mastery (Improved
-- Shadow Bolt), anyone's; shows the one applied last, grey with neither
local CRIT5 = { 22959, 17800 }
-- warlocks: Shadow Bolt tracks the same debuff (like the fire mage's Scorch)
local SB_CRIT5 = { id = 686, aura = CRIT5, anyCaster = true, newest = true, rules = { GREY_MISSING } }

-- the armor debuff: Expose Armor (a rogue's) when it's up, else Sunder Armor
-- stacks, anyone's
local ARMOR_DEBUFF = { 8647, 7386 }

-- death knights: diseases (grey until yours is on the target), Horn of
-- Winter (the buff on you, anyone's, not your ghoul's; grey and glowing when
-- missing, even on cooldown), the presence you're in
local IT_GREY = { id = 45477, rules = { GREY_MISSING } }
local PS_GREY = { id = 45462, rules = { GREY_MISSING } }
local HOW = { id = 57330, anyCaster = true, noPet = true,
    rules = { { c = "aura_missing", a = "glow", ooc = true, evenCD = true }, GREY_MISSING } }
local PRESENCE = { id = 48265, presence = true }

-- a self buff to keep up (Vampiric Embrace, Inner Fire): in colour when up,
-- grey and glowing when missing (even on cooldown, out of combat too), no text
local function SELFBUFF(id)
    return { id = id, noText = true, noPet = true,
        rules = { { c = "aura_missing", a = "glow", ooc = true, evenCD = true }, GREY_MISSING } }
end

A.CDMClassDefaults = {
    WARRIOR = {
        [1] = {   -- Arms
            { 12294, 7384, 5308, { id = 772, rules = { GREY_MISSING } }, 1464, 46924 },
            { 2687, 12328, 1719, 78, 20252, 6552 },
        },
        [2] = {   -- Fury
            { { id = 23881, aura = "none", ignorePower = true, rules = { { c = "ready", a = "glow" } } },   -- Bloodthirst: only its cooldown; glows when ready (in combat)
              { id = 1680, ignorePower = true, rules = { { c = "ready", a = "glow" } } },           -- Whirlwind: glows when ready (in combat)
              { id = 1464, aura = 46916, countAlways = true },                 -- Slam: Slam! (Bloodsurge) charges, up to 2
              { id = 5308, rules = { { c = "target_hp", v = 20, a = "glow" } } },   -- Execute: glows with the target at 20% or less
              { id = 772, rules = { GREY_MISSING } },                          -- Rend: grey until it's on the target
              78,                                                              -- Heroic Strike (shows Cleave while Cleave is queued)
              { id = 7386, aura = ARMOR_DEBUFF, anyCaster = true, byName = true, rules = { GREY_MISSING } },   -- Sunder Armor: anyone's stacks (Expose Armor first); grey with neither
            },
            { 1719, { id = 12292, ignorePower = true }, 2687, 18499, 57755, 64382,                          -- Recklessness, Death Wish, Bloodrage, Berserker Rage, Heroic Throw, Shattering Throw
              { id = 6552, rules = {                                           -- Pummel: glows when there's nothing
                  { c = "spell_oncd", aura = 23881, a = "glow" },              --   better: Bloodthirst on cooldown
                  { c = "spell_oncd", aura = 1680, andPrev = true, a = "glow" },   -- and Whirlwind on cooldown
                  { c = "buff_missing", aura = 46916, andPrev = true, a = "glow" }, -- and no Bloodsurge (Slam!)
              } },
              { id = 7384, rules = { { c = "usable", a = "glow" } } },          -- Overpower: glows for 5 sec after a dodge
            },
        },
        [3] = {   -- Protection
            { 23922, 6572, { id = 20243, aura = ARMOR_DEBUFF, anyCaster = true, byName = true, rules = { GREY_MISSING } }, { id = 6343, rules = { GREY_MISSING } }, 46968, 12809 },
            { 2565, 871, 12975, 23920, 355, 72 },
        },
    },
    PALADIN = {
        [2] = {   -- Protection
            { 53595, 53600, { id = 20925, rules = { GREY_MISSING } }, 26573, 53408, 31935 },
            { 498, 62124, 54428, 31884, 853, 633 },
        },
        [3] = {   -- Retribution
            { 35395, 53408, 53385, 26573, 879, 24275 },
            { 31884, 54428, 853, 498, 62124, 633 },
        },
    },
    HUNTER = {
        [1] = {   -- Beast Mastery
            { 34026, 3044, 2643, { id = 1978, rules = { GREY_MISSING } }, 53351, 2973 },
            { 19574, 3045, 34477, 5384, HM, 19577 },
        },
        [2] = {   -- Marksmanship
            { 53209, { id = 19434, aura = "none" }, { id = 1978, rules = { GREY_MISSING } }, 53351, 13813, 2973 },
            { 3045, 23989, 34490, 34477, 5384, HM },
        },
        [3] = {   -- Survival
            { 53301, { id = 3674, rules = { GREY_MISSING } }, { id = 1978, rules = { GREY_MISSING } }, { id = 19434, aura = "none" }, 53351, 2973 },
            { 3045, 34477, 5384, HM, 13813, 781 },
        },
    },
    ROGUE = {
        [1] = {   -- Assassination
            { 1329, { id = 32645, rules = { GREY_MISSING } }, { id = 5171, rules = { GREY_MISSING } }, { id = 1943, rules = { GREY_MISSING } }, { id = 51662, rules = { GREY_MISSING } }, { id = 703, rules = { GREY_MISSING } } },
            { 14177, 1856, 57934, 1766, 31224, 408 },
        },
        [2] = {   -- Combat
            { 1752, { id = 5171, rules = { GREY_MISSING } }, { id = 1943, rules = { GREY_MISSING } }, 2098, 51690, 13877 },
            { 13750, 57934, 1856, 1766, 31224, 5277 },
        },
        [3] = {   -- Subtlety
            { { id = 16511, rules = { GREY_MISSING } }, 53, { id = 5171, rules = { GREY_MISSING } }, { id = 1943, rules = { GREY_MISSING } }, 2098, 51713 },
            { 36554, 14183, 14185, 1856, 1766, 31224 },
        },
    },
    PRIEST = {
        [3] = {   -- Shadow
            { { id = 34914, rules = { GREY_MISSING } }, { id = 589, rules = { GREY_MISSING } }, { id = 2944, rules = { GREY_MISSING } }, 8092, 15407, 32379 },
            { 34433, 47585, 14751, 586, 8122, SELFBUFF(15286), SELFBUFF(588) },   -- ..., Vampiric Embrace, Inner Fire
        },
    },
    DEATHKNIGHT = {
        [1] = {   -- Blood
            { 55050, 49998, IT_GREY, PS_GREY, 47541, 56815, PRESENCE },
            { 49028, 55233, 48982, 48792, 47528, 56222, HOW },
        },
        [2] = {   -- Frost
            { 45902, IT_GREY, PS_GREY, 49020, 49184, 45529, PRESENCE },   -- Blood Strike, Icy Touch, Plague Strike, Obliterate, Howling Blast, Blood Tap, presence
            { 51271, 47568, 47528, 48792, 49039, HOW },                    -- Unbreakable Armor, Empower Rune Weapon, Mind Freeze, Icebound Fortitude, Lichborne, Horn of Winter
        },
        [3] = {   -- Unholy
            { 45902,                                                           -- Blood Strike
              { id = 45477, rules = { GREY_MISSING } },                        -- Icy Touch: grey without your Frost Fever
              { id = 45462, rules = { GREY_MISSING } },                        -- Plague Strike: grey without your Blood Plague
              55090,                                                           -- Scourge Strike
              43265,                                                           -- Death and Decay
              { id = 66803, tracker = true, aura = { 66803, "Desolation" }, rules = { GREY_MISSING } },   -- Desolation buff: time left; grey when not up
              { id = 48265, presence = true },                                 -- the presence you're in
            },
            { 49206, 63560, 47568, 47528,                                      -- Gargoyle, Ghoul Frenzy, Empower Rune Weapon, Mind Freeze
              { id = 49222, stacksOnly = true, countAlways = true,             -- Bone Shield: your charges only; glows when missing
                rules = { { c = "aura_missing", a = "glow", ooc = true }, GREY_MISSING } },   -- grey when missing
              48792,                                                           -- Icebound Fortitude
              { id = 57330, anyCaster = true, noPet = true,   -- (on you only: your ghoul gets it too)                                  -- Horn of Winter: the buff on you, anyone's; time left;
                rules = { { c = "aura_missing", a = "glow", ooc = true, evenCD = true }, GREY_MISSING } },   --   grey and glowing when missing (even on cooldown)
            },
        },
    },
    SHAMAN = {
        [1] = {   -- Elemental
            { { id = 8050, rules = { GREY_MISSING } }, 51505, 403, 421, 8042, 51490 },
            { 16166, 2894, 57994, BL, 8190 },
        },
        [2] = {   -- Enhancement
            { { id = 17364, rules = { GREY_MISSING } }, 60103, 8042, { id = 8050, rules = { GREY_MISSING } }, 403, 1535 },
            { 51533, 30823, BL, 57994, 2894, 8190 },
        },
    },
    DRUID = {
        [1] = {   -- Balance
            { { id = 8921, rules = { GREY_MISSING } },                          -- Moonfire: grey when not on the target
              { id = 5570, rules = { GREY_MISSING } },                          -- Insect Swarm
              2912, 5176, 48505,                                                -- Starfire, Wrath, Starfall
              { id = 770, aura = FF_ANY, anyCaster = true, rules = { GREY_MISSING } },   -- Faerie Fire: anyone's
            },
            { 33831, 50516, 29166, 22812, 16914 },
        },
        [2] = {   -- Feral (cat and bear)
            { { id = 33876, aura = { 33876, 33878 }, anyCaster = true, rules = { GREY_MISSING } },   -- Mangle: cat or bear, anyone's
              { id = 1079, rules = { GREY_MISSING } },                          -- Rip
              { id = 1822, rules = { GREY_MISSING } },                          -- Rake
              { id = 52610, rules = { GREY_MISSING } },                         -- Savage Roar (your buff)
              22568,                                                            -- Ferocious Bite
              49376,                                                            -- Feral Charge - Cat
            },
            { 5217, 50334,                                                      -- Tiger's Fury, Berserk
              { id = 16857, aura = FF_ANY, anyCaster = true, rules = { GREY_MISSING } },  -- Faerie Fire (Feral): anyone's
              33745, 61336, 22812, 20484,                                       -- Lacerate, Survival Instincts, Barkskin, Rebirth
            },
        },
    },
    MAGE = {
        [1] = {   -- Arcane
            { 30451, 5143, 44425, 12042, 12043, 12051 },
            { MIRROR, 2139, 45438, 1953, 66 },
        },
        [2] = {   -- Fire
            { { id = 44457, rules = { GREY_MISSING } },                        -- Living Bomb: grey until it's on the target
              { id = 11366, aura = 48108, noGCD = true, rules = { { c = "buff_missing", aura = 48108, a = "desat" } } },   -- Pyroblast: Hot Streak's timer; grey without it
              { id = 70753, tracker = true, aura = { 70753, "Pushing the Limit" }, rules = { GREY_MISSING } },   -- Pushing the Limit (T10 2-piece haste buff): grey when not up
              { id = 12654, tracker = true, ignite = true, rules = { GREY_MISSING } },   -- Ignite: its last tick's damage, grey when not on the target
              11129,                                                           -- Combustion
              { id = 2948, aura = CRIT5, anyCaster = true, newest = true, rules = { GREY_MISSING } },   -- Scorch: the 5% crit debuff
            },
            { MIRROR, 2139, 45438, 1953, 31661, 12051 },
        },
        [3] = {   -- Frost
            { 116, 30455, 44572, 133, 12472, 11958 },
            { 31687, MIRROR, 2139, 45438, 1953, 122 },
        },
    },
    WARLOCK = {
        [1] = {   -- Affliction
            { { id = 48181, rules = { GREY_MISSING } }, { id = 30108, rules = { GREY_MISSING } }, { id = 172, rules = { GREY_MISSING } }, { id = 980, rules = { GREY_MISSING } }, SB_CRIT5, 1120 },
            { 6789, 1454, 29858, 5782, 5484, 1490 },
        },
        [2] = {   -- Demonology
            { SB_CRIT5, { id = 172, rules = { GREY_MISSING } }, { id = 348, rules = { GREY_MISSING } }, 29722, 6353, { id = 603, rules = { GREY_MISSING } } },
            { 47241, 47193, 50589, 1454, 29858, 6789 },
        },
        [3] = {   -- Destruction
            { { id = 348, rules = { GREY_MISSING } }, 17962, 50796, 29722, 17877, { id = 172, rules = { GREY_MISSING } } },
            { 30283, 1454, 29858, 6789, { id = 603, rules = { GREY_MISSING } }, 5782 },
        },
    },
}
