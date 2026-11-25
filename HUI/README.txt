HUI - minimalist dark UI for WoW 3.3.5a (12340)

INSTALL
  Copy the whole "HUI" folder into:
    <WoW folder>\Interface\AddOns\HUI\
  (the .toc must be at Interface\AddOns\HUI\HUI.toc)
  Enable "HUI" on the character screen (tick "Load out of date AddOns" if asked).

WHAT IT CHANGES
  - Player, Target, Target of Target, Focus and Pet frames (flat, dark, 1px borders)
  - Health text "465.1K | 100%", level/elite on target, class / reaction colored names
  - Target debuffs above (yours in color, others greyed), target buffs below
  - Combo points under the target, castbars for player / target / focus
  - Raid + party frames (top-left, one row per group): class-colored names,
    health deficit, aggro (red border), dispellable debuff (colored border),
    current target (white border), out-of-range fade, raid marks
  - Default buffs/debuffs near the minimap restyled (right-click to cancel still works)
  - Action bars: art removed, flat buttons, 5 bars + pet + stance, thin XP/rep bars,
    micro menu and bags moved bottom-right (turn bars 2-5 on in Interface > ActionBars)
  - Optional mouseover action bars (/hui > Action Bars > Mouseover: all bars or per bar)
  - Quality of life (from the retail essentials addon), all in /hui > Quality of Life:
      Automation: sell grey items, repair (guild funds first), accept invites / resurrects /
      summons, decline duels, role checks, accept + turn in quests, fast loot, confirm
      bind-on-pickup rolls, type DELETE for you, skip cinematics, hide red error text
      Cursor circle, low health screen-edge warning, combat timer, combat cross
      Move Blizzard windows (optionally remembered), Ctrl+C copy box, chat copy button
  - Chat: timestamps, short channel names, clickable links, class colored names, size,
    opacity, edit box position, fading, lines kept
  - Minimap: size, border, visibility, zone / coordinates / clock options, zoom reset,
    right-click tracking, middle-click calendar
  - Square minimap (mouse-wheel zoom), clean chat with a dark tab header
  - One-bag frame (all carried bags in one dark window), dark tooltips and menus
  - Blizzard player/target/focus/party frames and castbar are hidden
  - DK runes and shaman totems are moved under the player frame

CLICKS
  Left = target, Right = menu, Shift+Left = set focus. Clique-compatible.

SETTINGS WINDOW
  /hui   -> settings + "Unlock UI" button. In unlock mode drag the blue boxes,
            right-click a box to reset it, press Lock when done.
            Positions are saved in WTF\Account\<acc>\SavedVariables\HUI.lua

COMMANDS
  /hui           settings window
  /hui unlock    move frames
  /hui lock      lock frames

TWEAKING
  Font/texture: Core.lua -> A.media
  Colors:       Core.lua -> A.colors
  Frame sizes:  Units.lua -> BuildUnitFrames()
  Raid size:    Raid.lua (A.RAID_W/H) AND Templates.xml <Size> (keep them equal)

MEDIA
  media\bar.tga is the bar texture (from your EllesmereUI install, resized to 256x32
  because 3.3.5 needs power-of-two textures). All text uses the game's default font.
