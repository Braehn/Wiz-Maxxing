r"""Vision helper for AutoFarmer: finds cards in the hand and school badges on name plates.

AutoFarmer (AutoHotkey) starts this with pythonw and asks it over HTTP on 127.0.0.1. Instead of
ImageSearch's "found or not at this tolerance", every picture is matched at every position with a
distance (the RMS colour difference over the picture's solid pixels, see-through magenta left out), so
the best match wins and a threshold tells a real match from a near miss.

Pictures come from the same picture sets as AutoFarmer's (the main set at UI scale 1 and the ui<scale>
folders; see PicScale.ahk): each is resized from the cut set nearest above the UI size in use (a solid
<name>.raw.png next to a cut picture gives the colours to resize; the cut picture's magenta gives what to
leave out).

Requests (all GET, answers are plain text lines, "ERR <why>" on a problem):
  /ping                                   -> "OK <version>"
  /cards?x1=&y1=&x2=&y2=&scale=&pics=balance/hit1,resources/sharpen,... -> one line per card found: "dir/name|x|y|dist" (x, y = the
                                             picture's top left on screen, like ImageSearch's), best first
  /cards                                  -> (no rectangle) the cards in the wizard's hand and its pips, read from the
                                             game's memory (read-only, see vision\handmem.py) - only in a battle's
                                             planning phase with the hand settled (the cards shown are exactly the
                                             wizard's hand list), else one line "none|<why>" (why "hand changing": the
                                             game is dealing or laying out the cards - ask again in 100 ms; a card's been
                                             chosen and the round is waited for; not in a battle...). Settled:
                                               me|health|max|generic|power|balance|death|fire|ice|life|myth|storm|shadow|
                                                  school                     (my pips of each kind; school: my own)
                                               card|slot|x|name|display|school|type|pips|xpip|shadow|castable|tc|item|
                                                  enchantment|accuracy|value|kind|dot|school pips|enchantment's effect|
                                                  value with it|template id|text|heads|boosts
                                                                             (one a card, left to right as on screen:
                                                  slot the game's window (Card1-7, PetCard), x its left edge (the game's
                                                  units: only the order counts), name the spell's own name, display the
                                                  name on the card, school and type as the game names them (Damage, AOE,
                                                  Charm, Ward, Jinx...), pips (0 and xpip 1: an X-pip spell), shadow its
                                                  shadow pips, castable 1/0 - an estimate for the normal mode (not while
                                                  an enchantment or a target is being picked; "" not known: an astral
                                                  spell...), tc a treasure card, item an item card (a wand's...),
                                                  enchantment its enchantment's name ("" none), value its number as the
                                                  bot keeps it - a hit "lo-hi" (every head added), "N/pip" (X pips), a
                                                  heal "N", "N%" (shield, blade, trap, aura, bubble, weakness), "+N" (an enchant)
                                                  - the card's own, without the enchantment, which is in the next fields
                                                  ("kModifyCardDamage +175", the value with it); kind the bot's name for
                                                  it: damage aoe heal ward blade trap aura bubble (a global) weakness
                                                  enchant dot stun dispel prism clear polymorph keep; dot the damage
                                                  (healing) over time besides; school pips the pips of a school it
                                                  wants besides "fire:1";
                                                  text about as the card says it; heads a damage card's damage by
                                                  school, every head of it, each its least: "fire:230,ice:230,storm:230"
                                                  (Hydra; the enchantment not added); boosts what a blade, trap, aura
                                                  or bubble boosts by school: "ice:35,storm:35,fire:35", "all:25" (every school);
                                                  either "?" when it can't be trusted (not all of the card read, a head
                                                  of an odd kind or school), "" none - handmem.heads_field /
                                                  boosts_field; an older helper has no fields 24-25);
                                                  l|t|r|b (26-29, v1.0.0) the card's box in the GUI's root, GUI units
                                                  (its m_Window plus every window's left / top on the way down - NOT
                                                  CHECKED against the screen yet: AutoFarmer's MemBoxCheck logs it
                                                  against /hand's boxes), "" not read
                                               root|<w>|<h>                  (v1.0.0: the GUI root's size in the same
                                                                             units - only when it's read)
                                               hand|<cards>|<ms>
                                             ?ptag=d<duel>r<round> (partyorders, a follower's bot): the hand also kept
                                             for the party's leader (party.py saw_hand)
  /badge?x1=&y1=&x2=&y2=&scale=&schools=  -> one line per school whose badge is there: "school|x|y|dist",
                                             best first ("unclear": two schools too close at the best spot)
  /hand?x1=&y1=&x2=&y2=&scale=&pics=&learned=<id>:<set folder>:<slot>,...&here=<set folder for this size>
                                          -> one line per card in hand, left to right: "card|left|top|w|h|
                                             known picture|its dist|grey|type|type dist|pips|pips score|same|liked|
                                             real|tc"
                                             (known "" = none of pics; grey 1 = greyed out, can't be cast now;
                                             type = cardicons\<type>.png that matches, "" none; pips "" unread;
                                             same = the number of an unknown card further left that
                                             it is a copy of, 0 none; liked 1 = a slot's learned picture
                                             was just written - made see-through where this copy
                                             differs, or cut at this UI size into here=<set folder> -
                                             so the plain search finds it if it looks again; real 1 = the box
                                             looks like a card (card_feats), 0 = something else where a card
                                             was expected (the deck's back, the floor, the timer, a popup): no
                                             learned picture names it, it's never compared, cut or made a copy
                                             of (and a learned card whose own .card.png isn't a card is never
                                             looked for at all); tc 1 = a lavender text box: a treasure card
                                             (an item card, e.g. a wand's, is lavender too; a greyed one never
                                             reads 1)
                                             &thumbs=<folder> also saves each card as it looks:
                                             <folder>\hand1.png, hand2.png... left to right (for the dashboard)
  /cut?left=&top=&scale=&out=<path>       -> saves the card at left, top: <out>.png (its picture, cut like
                                             hit1.png etc.) and .raw.png, .card.png (the whole card), .icon.png
                                             (its type icon), .pips.png (its pip cost): "OK"; when the box isn't a
                                             card nothing is saved: "NOTCARD eTxt=.. pipYel=.. white=.. iconD=.."
  /cardcheck?file=<a .card.png in the AutoFarmer folder>&scale=<the UI scale it was cut at>
                                          -> "real|tc|eTxt|pipYel|white|iconD|icon|pips|pipscore" for that saved
                                             card (the same check as /hand's real), or "fail <why>" when it can't
                                             be looked at (never ERR)
  /usable?rel=balance\hit2.png            -> "1" if a cut picture big enough to use is there for it, else "0"
  /forget                                 -> reads the picture folders again (after pictures were added)
  /globes?left=&bottom=&scale=            -> "health|<n>" and "mana|<n>" off the globes at the game's bottom
                                             left (n "" if it can't be read for sure)
  /plate?x1=&y1=&x2=&y2=                  -> a name plate's red health numbers in the rectangle, read by their shape
                                             (the cut pictures in ui<scale>\platedigits): "health|cur|max|worst glyph's
                                             distance", or "none|<why>" when they can't be read for sure
  /nav[?path=1][&route=1]                 -> where the wizard and its quest goal are, read from the game's memory
                                             (read-only, see vision\navmem.py), one line each:
                                               ok|1
                                               zone|<zone path, e.g. WizardCity/WC_Ravenwood>
                                               pos|x|y|z|yaw        (z up; yaw radians, forward = (-sin yaw, -cos yaw))
                                               target|x|y|z         (the node the on-screen arrow points at)
                                               goal|x|y|z|hops      (hops 0: the goal is in this zone; N: N zone changes
                                                                     away, and x|y|z is the teleporter to take here)
                                               dist|d               (the arrow's distance, along the path)
                                               quest|enabled|questid|goalid
                                               noplace|<1/0/>|<held s>   (1: the game shows no way to the goal - no
                                                                     arrow: its goal reads exactly 0, 0, 0 and the HUD's
                                                                     distance -1, a USAGE "Use Inactive Protector ..." -
                                                                     the goal| target| dist| above empty then and the
                                                                     on-screen arrow a phantom; held: seconds the 1 has
                                                                     held for this quest and goal, only with 1 - act on
                                                                     it once it has held. 0: the goal has a place. "":
                                                                     not known - another zone, the quest helper off, a
                                                                     goal change caught midway. An older helper sends no
                                                                     such line)
                                               path|x,y,z;x,y,z;... (only with path=1: the game's own path over the
                                                                     zone's nav graph, from the wizard to the goal)
                                               route|x|y|left       (only with route=1: where to steer - a point ahead on
                                                                     the route planned round the walls over the zone's
                                                                     map, vision\navroute.py - and how far is left to
                                                                     walk; route|||  with routewhy|<why> when there's
                                                                     none yet: the walker steers at the target then)
                                                    |jump|jx|jy     (5-7: right at a teleport on the game's path: the
                                                                     seconds waited there, where it is)
                                                    |mob|mx|my|name (8-11: a mob on the way the route can't go round: the
                                                                     seconds waited for it to move off, where, its name
                                                                     - or the gap in a line of mobs it would go
                                                                     through: the nearest of them)
                                                    |escape|arc     (12: inside a mob's ring or sight - its name; 13:
                                                                     turning round to the aim clear of the walls 1/0)
                                                    |duel|dx|dy     (14-16: another player's battle on the way the route
                                                                     can't go round - duels=1 -: the seconds waited for
                                                                     it, where; empty none. An older helper's line
                                                                     stops at 13)
                                             &avoid=1[&mobr=300][&shape=2][&cone=60][&goal=<the quest's goal line>] (with
                                             route=1): the route kept out of what each of the zone's mobs (navmem,
                                             read-only) sees, mobr far: shape 1 a circle all round, 2 a semi-circle in
                                             front, 3 a cone cone degrees wide in front (no shape: mobr all round and a
                                             cone= / sight= cone) - not those the quest's goal names, nor (a fight
                                             goal) one by the goal. The goal: the game's memory's (as /goal), else
                                             goal= (the line AutoFarmer OCRs off the screen). A walking mob (its last
                                             second of readings - navroute.MobMotion) is kept out of along its way,
                                             a line of mobs as one wall (vision\navroute.py's top)
                                             &duels=1 (with avoid=1 - the duelavoid setting, off by default): out of
                                             other players' battles too (the zone's duel circles - navmem.duels:
                                             not confirmed in the game yet)
                                             &walls=1 (with avoid=1 - the mobwall setting, off by default): a line of
                                             mobs' wall the route can't go round waited at as a mob on the way
                                             (fields 8-11); without it walked through its gap, as before
                                               goalline|text|type|status|count|total|shown   (last, always: the quest's
                                                                     goal from the game's memory as /goal's - all
                                                                     empty when it can't be read; an older bot
                                                                     doesn't look at it)
  /navto?x=&y=&z=[&avoid=1&mobr=300][&spare=700][&duels=1]
                                          -> where the wizard is and the route to a spot of the bot's own (the potion
                                             seller, a puzzle's guards): ok|1, zone|, pos|, route|x|y|left (all mobs kept
                                             away from with avoid=1 - but those within spare of the spot: the camp
                                             walked to, to fight it; duels=1 with it: other players' battles too, kept
                                             off where there's room - no wait)
  /blockers                               -> the doors, gates and collision walls of the wizard's zone, nearest first -
                                             what holds the walker at a blocked way (a dungeon's gate the zone's
                                             triggers open after two kills):
                                               door|template|x|y|z|distance|gid|src|state|start
                                             src mem: an object in the game's memory now (read-only - navmem.blockers:
                                             no name key, a template named like a door, a gate, a portcullis, a barrier,
                                             a collision - vision\puzzlefile.py's is_blocker:
                                             DynaTrigger_KT_DoorCollision; one gone from memory has been taken away: the
                                             way's open);
                                             state its state in the game's memory now (its ObjectStateBehavior's -
                                             vision\statemem.py, NOT CONFIRMED in the game yet: "" not read - a build it
                                             can't read, its reader being made). src file: where the zone's file places
                                             one (vision\placements.py, as /items?far=1 - built in its thread at each
                                             zone change: until then the memory's alone), state its starting state (On,
                                             Off, Open),
                                             gid "f:<template>:<n>" / "f:<template>@<where>" (the same every time).
                                             start (10): the zone file's starting state of the door - a memory one's:
                                             its template's placement nearest it within 400 (puzzlefile.match_start;
                                             "" none) - so a state that changed since the zone began reads without
                                             knowing its names. An older helper's lines stop at 9
                                             "none" when there are none; "ERR <why>" when the zone's objects can't be
                                             read now (a new zone being looked at) - never "none" then: not read isn't
                                             gone
  /zonepuzzle?zone=<zone path>            -> what the zone's own files (its triggers.xml - vision\puzzlefile.py; files
                                             only, no memory) say opens its blocked ways, one line each:
                                               kill|<template>      (a monster whose kill sets an object's state or fires
                                                                     an activation: CL-DeepOne-GreenHead-R10)
                                               spawn|<object>|x|y|z (an object a trigger makes -
                                                                     DynaTrigger_KT_DoorCollision instance - and where;
                                                                     x|y|z empty when the file doesn't say)
                                               hint|<volume>|x|y|z|r|<text>   (a dialogue a trigger plays as the wizard
                                                                     walks into the volume, its centre and radius: the
                                                                     game's own hint - NearGateVolume "The gate has
                                                                     defenders. ...")
                                               use|<event>|<targets>|<states>|<acts>   (another object event:
                                                                     PedestalUsed, UsedBook - and what its triggers do:
                                                                     the objects whose state they set, the states, the
                                                                     activations, each ; apart - empty none. An older
                                                                     bot reads the event alone)
                                               useobj|<event>|<template>|x|y|z|<how>   (a placement of the zone's file
                                                                     that may be what fires the event - no name key, not
                                                                     a door: a lever the game names nowhere; how "name":
                                                                     by the event's own words, a guess - puzzlefile.
                                                                     event_objects; none till placements' things are
                                                                     built for the zone)
                                             "none" when there's none of these; "ERR <why>" when the file can't be read.
                                             Kept per zone (read in placements' thread at each zone change)
  /navpass?fx=&fy=&fz=&tx=&ty=&tz=&vx=&vy=[&vr=200][&zone=<zone path>]
                                          -> does the way along the zone's nav graph (its walked links -
                                             vision\navroute.py, the zone's .wad: files only) from f to t go through
                                             the spot v:
                                               pass|<1/0>|<its nearest to v>|<its length>   (1: within vr of v, or
                                                                     across the line through v square to f -> v
                                                                     within 2 vr of v - the nav nodes can be far
                                                                     apart; both across the ground)
                                             or "ERR <why>" (no nav graph, no way, or the graph's way ends far from t).
                                             The zone: zone=, else the wizard's (the game's memory). fz= / tz= empty:
                                             not known - the floor under it (the nav graph's nearest node's height).
                                             Kept per question
  /snap?x1=&y1=&x2=&y2=&out=<...\Wiz-Maxxing logs\<PC>\snap_<when>.jpg>[&keep=15] -> the screen rectangle (the
                                             game: the bot checks it's on top) saved as a JPEG (half size when wider
                                             than 1600) - the log's OneDrive copy; that folder's oldest snap_*.jpg
                                             beyond keep removed: "ok|<file>" or "ERR <why>" (nowhere else: 400)
  /caught                                 -> the mob that started a battle (asked at its first round), off the mobs
                                             read lately (while walking with mob avoidance on): the one nearest the
                                             wizard, looked back to where it set off towards him (noticed him):
                                             caught|name|how far he was then|degrees off its facing then|came (1: it
                                             came for him, 0: he walked into it)|seconds before|quest (1: the helper
                                             took it as the quest's - not avoided)|walking (1: it was walking the
                                             second before it noticed him, 0 standing, "" not known - an older
                                             helper's line stops at 7); or "none (<why>)"
  /duels                                  -> the zone's duel circles (the game's memory, read-only - navmem.duels,
                                             bossmem's duel_of: NOT CONFIRMED in the game yet), nearest first:
                                             duel|template|x|y|z|distance|phase|parts|players|gid|active|mine (phase
                                             its name when decoded, else its number; parts the participants, players
                                             the wizards among them; active 1 a battle going on; mine 1 the wizard's
                                             own), or "none"; "ERR <why>" when they can't be read
  /mobs[?goal=<the quest's goal line>]    -> the zone's mobs (the game's memory, read-only), nearest first:
                                             mob|name|x|y|z|distance|quest (1: the quest's)|degrees from where it
                                             faces to the wizard (0: straight ahead of it)|title|rank|health|school|
                                             boss|gid|named|template, or "none (<why>)"
                                             (9-14, what the mob is - vision\bossmem.py: title as the game names it,
                                             Boss, Elite, Normal, Easy, Minion; rank the one the game shows ("Rank 9
                                             Boss"); health its starting - max - health; school its school of focus
                                             (Ice); boss 1 the game's own boss flag, 0 not; gid its global id. Each ""
                                             while not known - the reader being made once per game, about half a second,
                                             a build it can't read. 15, named: 1 the quest's by its name or its goal
                                             only - quest without the same-family match ("Gobbler King" for "Defeat
                                             Gobblers" is quest 1, named 0. 16, template: its template's name as the
                                             game's memory holds it - CL-DeepOne-GreenHead-R10 for a Water Lurker: the
                                             same in every instance, as the zone's triggers name it. 17-19, how it
                                             moves - once known (MobMotion, off the mobs read lately): vx|vy its
                                             speed along x and y (units / s)|moving 1 walking, 0 standing, "" not
                                             known. An older helper's lines stop at 8, 14, 15 or 16)
  /items[?goal=<the quest's goal line>][&far=1]
                                          -> the zone's things with a name that aren't mobs (the game's memory,
                                             read-only - an item lying about a quest has you collect, Piece Of Coral; an
                                             object to use, open, read, Inactive Protector; an NPC...), nearest first:
                                             item|name|x|y|z|distance|quest (1: the goal is about it)|gid|key|template|
                                             src|kind, or "none (<why>)" (none at all: plain "none")
                                             (9-12: key its display key - WizQst371C7_00000008 -, template its
                                             template's name, src mem (in the game's memory now) / file (where the
                                             zone's file places it - far=1 only), kind item / object / npc / ambient /
                                             use (name and key empty: an object with no name key a use event of the
                                             zone's triggers may be fired by - /zonepuzzle's useobj templates, a
                                             lever).
                                             An older helper's lines stop at 8. quest: the goal's own key (TALLYTEXT -
                                             /goal's itemkey) when any thing listed has it - then only those -, else (an
                                             exact goal) the goal's item - or a talk goal's NPC - as the thing's whole
                                             name ("Protector" isn't "Inactive Protector"), else the goal's line names
                                             it; an ambient one only by its key; one from the file never by the OCR's
                                             slips)
                                             far=1: also the things the zone's file places (vision\placements.py) that
                                             the memory doesn't hold now - it holds only those within ~6.7k (a live one
                                             of the same template within 400 stands for its placement; gid
                                             "f:<template>:<n>" or "f:<template>@<where>" - a far one becomes the live
                                             gid once in reach). The file is read in a thread at each zone change: until
                                             it's built only the live things (never read while asked). A used or
                                             picked-up one stays in the file - the bot remembers those itself
                                             (the quest's goal for both: the game's memory's, as /goal's; goal= only
                                             when that can't be read)
  /battle                                 -> the battle's participants, read from the game's memory (read-only, see
                                             vision\bossmem.py) - in a battle's planning phase - one line each, the
                                             wizard's own first:
                                               part|me|team|name|health|max|boss|title|rank|school|player|gid|x|
                                                  l|t|r|b|hide
                                                                     (me 1: the wizard's own; team the game's number -
                                                                     the wizard's side vs the enemies'; name the mob's
                                                                     ("" a wizard); health and max its health now and
                                                                     its most; boss 1 the game's own boss flag; title,
                                                                     rank, school its mob's template's (as /mobs');
                                                                     player 1 a wizard; gid its owner's global id; x
                                                                     the middle of its plate across the game's window,
                                                                     0..1 (its GUI rect over the root's); l|t|r|b
                                                                     (v1.0.0) its plate's box across and down the
                                                                     game's window, 0..1 each (NOT CHECKED against the
                                                                     screen yet); hide 1: the game hides its health
                                                                     (m_HideCurrentHP) - "" a field not read)
                                             or one line "none|<why>" (not in a battle's planning phase, the readers
                                             being made - once per game -, the game not running...)
  /phase                                  -> the round's phase from the game's memory, cheaply (read-only, no spell read
                                             - vision\handmem.py HandMem.phase, about a ms):
                                               phase|state|in battle|planning|shown|own|size|ms|why
                                                                     (state none: not in a battle; round: in one, out of
                                                                     the planning phase; waiting: planning, no card
                                                                     shown but cards in the hand list - one's chosen;
                                                                     changing: the cards shown not as many as the list;
                                                                     hand: as many - not checked card by card as /cards
                                                                     does; shown the card windows shown, own those but
                                                                     the pet's, size the hand list's; 1/0 flags, "" not
                                                                     read)
                                             or "none|<why>" when the game can't be read
  /uiroot                                 -> the game's GUI root's size in GUI units, read from the game's memory
                                             (read-only - navmem.ui_root): "root|<w>|<h>" (1827|1027 at 2560x1440,
                                             UI 1.144 - the window's pixels over it are the GUI's scale; AutoFarmer
                                             cross-checks its picture set's UI scale with it), or "none|<why>"
  /guitree[?under=Anc/Name][&all=1][&depth=N]
                                          -> EVERY window under the one named (the GUI root without under; all=1 the
                                             hidden ones too; depth=N that many levels below it, else 24) from the
                                             game's memory (read-only - vision\bagmem.py's tree / tree_lines: the
                                             discovery tool for windows nobody has looked at yet, and a list's rows):
                                             root|w|h, tree|under|matches|dups|rows|walked|capped|all, then one line a
                                             window depth|name|type|shown|l|t|r|b|text|key|greyed|checked|texture|kids|
                                             parent|flags (in the root's units; parent: its parent's line number among
                                             the window lines); or "none|<why>". The whole tree can take a while: ask
                                             under a window - only its windows are walked and described (every window
                                             is still read once to find it, as /gui does - not those in hidden ones
                                             without all=1); capped 1: cut short (with matches 0: the window may be past
                                             where finding it stopped - not "no such window")
  /gear[?school=&level=&role=hitter|healer|blader&weights=off:1,def:0.5,...&margin=2&sets=1&hp=&damage=&pierce=&crit=
       &block=&acc=&resist=&pp=&heal=&incheal=][&run=<name>&mark=1|&end=1&slots=hat,robe,...&stopafter=30&nomark=1]
                                          -> the worn gear and the backpack's from the game's memory (read-only -
                                             vision\gearmem.py: each piece's equip effects and requirements, NOT
                                             CONFIRMED in the game yet) and the swap plan for the wizard's totals given
                                             (vision\gearrank.py - advice: AutoFarmer's Gear.ahk equips nothing yet):
                                             gearrank.gear_lines - gear|..., stats|..., worn|slot|gid|tid|name|display|
                                             level|stats|sets, item|gid|tid|name|display|slot|verdict|delta|basis|why|
                                             stats|reqs|crowns|nosell|sets, plan|slot|gid|tid|name|worn gid|worn name|
                                             delta|basis|held|why, note|...; run= a dungeon run's drop log in
                                             AutoFarmer\learned\drops (mark=1 at its start: the backpack's ids kept;
                                             end=1 at its end: drop|tid|name|slot|display|count|first a new piece,
                                             run|name|runs|dry|stopafter|done|why|new|marked - slots none: the
                                             dungeon's from resources\dungeons_known.txt; nomark=1: its start wasn't
                                             noted - not counted, the backpack kept afresh); a piece whose template
                                             couldn't be read: item|...|<slot blank>|unknown|...; or "none|<why>"
  /pets[?want=Talent,Talent...][&hatch=1] -> the wizard's pets from the game's memory (read-only - vision\petmem.py: the worn
                                             one and the backpack's) and which to keep out of Quick Sell (vision\petplan.py -
                                             want: AutoFarmer\pets.txt's wanted talents; hatch=1: hatching on): petmem.pet_lines
                                             (pet|gid|where|level|level name|template id|object name|display|cards|xp|
                                             xp next|talents|derby|stats|max stats|behavior class - the values not
                                             confirmed in the game yet "" -, energy|cur|max, pets|n|whole|ms|why), then
                                             want|n|names|hatch and keep|gid|where|why (a pet whose talents aren't read is
                                             kept); or "none|<why>"
  /goal                                   -> the quest's active goal, read from the game's memory (read-only, see
                                             vision\questmem.py) - exact, unlike the OCR of the screen - one line each:
                                               text|<the goal line>|<from>   (as the game shows it under the arrow:
                                                                     "Defeat Crustacean Waverunner and Collect Foul
                                                                     Tasting Algae in The Grotto (0 of 3)"; from: data -
                                                                     built from the quest's data -, hud - the HUD's own
                                                                     text, when the data's names can't all be read)
                                               shown|<1/0>|<the HUD's line>|<the arrow's number>   (1 on screen, 0
                                                                     hidden - a battle; "" not known. A loading screen or
                                                                     a dialogue over it still reads 1)
                                               kind|<type>|<status>  (BOUNTY defeat, BOUNTYCOLLECT defeat and collect,
                                                                     USAGE collect / open / use / read, WAYPOINT go to,
                                                                     PERSONA talk to, SCAVENGE...; INCOMPLETE / COMPLETE -
                                                                     the quest moving on: ask again. "" not read)
                                               count|<count>|<total> ("" none: talk and go-to goals; the line shows
                                                                     "(count of total)" when total is over 1)
                                               mob|<name>            (the mob a defeat goal names - or its kind:
                                                                     "Gobblers")
                                               item|<name>           (what a collect / use / go-to goal names)
                                               npc|<name>            (who a talk goal names)
                                               place|<the place>
                                               quest|<title>|<quest id>|<goal id>|<ids: hud / thread>
                                               exact|<1/0>           (1: the line and the fields above are the goal's
                                                                     own data, every name found)
                                               itemkey|<key>         (the name-table key of what the goal names - its
                                                                     TALLYTEXT: WizQst371C7_00000008 = Inactive
                                                                     Protector, the display key of the zone's objects it
                                                                     means: /items' field 9; "" none, or words)
                                               mobkey|<key>          (the mob's - TALLYTEXT2: WizardMobs_00000883)
                                               npckeys|<first>|<last>  (a talk goal's NPC's - FIRSTNAME, LASTNAME:
                                                                     WC-NPCs_00000014|WC-NPCs_00000015)
                                               namekey|<key>         (the goal's own name: WizardQuestGoals_UseItem,
                                                                     _TalkNPC, _Kill...)
                                               kindnum|<n>           (the game's own number for the kind - USAGE 8: it
                                                                     may change between builds, for logs only)
                                                                     (the keys exact - no name looked up -, "" when the
                                                                     quest has moved on; an older helper has none of
                                                                     these five lines)
                                             or one line "none|<why>" (not in the game world, no quest, the game's quest
                                             classes being read - once, about a second -, the game not running...)
                                             A field that can't be read for sure is left empty (target|||): goal, target,
                                             dist and path while the quest helper is still on the last zone, target and
                                             dist while the arrow is behind the goal's hops. One line "ERR <why>" when the
                                             game can't be read: not running, being attached to (its code is looked through
                                             once per game process, under a second), or a signature isn't in this build
  /quests                                 -> EVERY quest in the game's quest manager (read-only, vision\questmem.py - the
                                             tracked one is /goal's): questmem.quest_lines - quest|id|title|tracked|goals|
                                             complete|title key|props (WizQuestData's other properties, name=value,... -
                                             all of them: what marks a spell quest isn't known yet), goal|quest id|goal
                                             id|kind|status|count|total|text|mob|item|npc|place|name key, then
                                             quests|n|tracked id|ms|why; or none|<why> (as /goal's)
  /navmap?w=&h=&out=<png path in the AutoFarmer folder>[&span=6000]
                                          -> "ok|<out>": a w x h top-down picture of the zone round the wizard, span game
                                             units across its shorter side (+X right, +Y up): the walkable floor, obstacles
                                             and the faint nav graph (the zone's .wad, decoded once per zone - see
                                             vision\navgeo.py - and drawn in tiles that are kept), then, drawn each time,
                                             the game's path, the route planned round the walls (green, with the point
                                             it steers at), the wizard as an arrow showing its facing, the arrow's target
                                             (a ring) and the goal (a diamond; a door with the number of zone changes when
                                             it's in another zone; on the edge, pointing, when off the picture), the mobs
                                             (red dots, faint rings while the walker keeps away from them; the quest's
                                             amber; the nearest named). No zone
                                             file: the overlay on a blank background. "ERR <why>" as /nav, or when the
                                             wizard's position can't be read
  /ovmap?gw=&gh=&mapat=&msize=&logat=&lines=&lw=&text=&back=&mdx=&mdy=&ldx=&ldy=&span=&seq=&force=0|1&out=<.wzov path>
                                          -> the overlay over the game's map as a .wzov frame (vision\overlay.py, for
                                             Overlay.ahk): /navmap's picture see-through - clear where nothing is, the
                                             floor, water and rim faint, a size bigger, in a rounded dark box (back %)
                                             - placed in the game's client by overlay.layout - "ok|<out>" (written),
                                             "same|<out>" (unchanged, nothing written - never with force=1) or "ERR
                                             <why>" (the map is off, the game or the wizard's position can't be read;
                                             status 400: a bad request). gw, gh the client's size in physical pixels;
                                             mapat, logat 1 Off, 2 top left, 3 top right, 4 bottom left, 5 bottom
                                             right; msize the map's side (% of the client's shorter side); lines,
                                             lw (% of gw), text (%) the log's; back the dark box (%); mdx, mdy, ldx,
                                             ldy nudges (pixels); span game units across the map; seq echoed in the
                                             frame; out in the AutoFarmer or the temp folder. The frame: a 32-byte
                                             header ('<4sIIIIIii': WZOV, 1, w, h, stride w*4, seq, x, y - the part's
                                             top left in the client), then h rows of premultiplied B,G,R,A, top-down
  POST /ovlog?<the /ovmap query>          -> the overlay's log as a .wzov frame (overlay.py): the body's lines (text/plain
                                             us-ascii, oldest first: RRGGBB<tab><the line as BattleRec.ahk BrecEsc
                                             escapes it><LF> - RRGGBB its dashboard colour) newest at the bottom, older
                                             ones fainter, one too long cut short with ...; replies as /ovmap's ("ERR
                                             <why>": the log is off, or there's no room for it with the map)
  POST /rec?ev=round|hello|who|state      -> the battle recorder (vision\battlerec.py - its docstring has the body's
                                             format and the record's): the bot's round lines and state, put on the
                                             recorder's queue as they are (64 KB at most; nothing parsed, written or
                                             read here) - "ok", or "off" when the recorder is off. Also GET
                                             /rec?ev=who&bot=&acting=&pfm=&tk= (who plays: a takeover, F6)
  /recstat                                -> rec|on|<recorded today>|<bytes>|<last result>|<why>|<orphan posts>|
                                             <queue drops>|<errors>|<records>|<waiting>|<log lines>|<posts>
  /deck[?fresh=1]                         -> the worn deck from the game's memory (read-only, vision\deckmem.py):
                                             deckmem.deck_lines (deck|..., card|..., item|..., excl|..., decks|...) of
                                             the last reading + deckage|<s>, or none|<why>; fresh=1 reads it now
                                             (paced, refused "none|in a battle" while a battle is on - and while the
                                             battle recorder isn't following the game's log)
  /decks[?fresh=1[&ob=1]]                 -> EVERY deck (the backpack's too) with its cards' kinds (deckmem, read-only - as
                                             /deck, fresh=1 refused in a battle - ob=1: the bot says it's out of
                                             battle, for when the battle recorder is off) and the bot deck profile each one in an
                                             Equipment Set would make (vision\battlesim.py learn_decks):
                                             deckmem.deck_lines + learn|gid|name|school|eqset|when|k=v,...|why lines +
                                             deckage|<s>, or none|<why>
  /book[?fresh=1[&ob=1][&kinds=1]]        -> the spellbook (the spells the wizard knows) and the treasure-card book from
                                             the game's memory (deckmem, read-only - Training.ahk's new spells):
                                             deckmem.book_lines - book|template id|name|display|school|type|pips|xpip|
                                             retired|tier|kind|value, tcbook|template id|count|name|display|school|type|
                                             pips|kind|value, books|spellbook n|treasure n|wizard gid hex|ms|why - +
                                             bookage|<s>, or none|<why>. The last book reading; fresh=1 reads now (as
                                             /decks, refused in a battle; ob=1 the bot says it's out of battle; never
                                             answered by the worn deck's signature - a spell learned doesn't change it);
                                             kinds=1 each spell's kind and value too (slower the first time). Its own
                                             reading: /deck's, /decks' and /sim's stay theirs
  /sim?foes=name~health~school~boss|...&deck=<gid hex>&school=&hp=&damage=&pierce=&crit=&block=&level=&acc=&resist=
       &team=&pp=&vals=k:v,...&boss=1&n=300[&fresh=1]
                                          -> "can this deck beat it": the battle simulator (vision\battlesim.py) - the
                                             deck (gid hex: one of /decks' - else the worn one) from the decks' last
                                             reading with their kinds (fresh=1: read now, out of battle only), the
                                             wizard's stats, the deck's settings (vals), each enemy (its health from the
                                             game's memory when given; resists, block and hits from the battles
                                             recorded; spells from the wiki) - n battles: battlesim.sim_lines (sim|...,
                                             verdict|word|text, foe|..., cast|..., note|...), or none|<why>
  /plan?school=&deck=<gid hex>&round=&blades=key~schools~%|...&traps=key~schools~%|...&trapmax=&aura=schools~%~rounds
       &boostrun=&first=1|0&vals=k:v,...&damage=&pierce=&crit=&block=&acc=&resist=&pp=&boss=1&budget=300&n=100
       [&foes=name~max~school~boss~health|...][&used=key~schools~%|...&draws=&drawoff=1&pshield=1]
                                          -> the round planner (vision\battlesim.py plan_round, Planner.ahk - advice
                                             only): every card in hand that can go now (and a pass) tried in the
                                             simulator from this very round - the hand, pips and health from the game's
                                             memory (/cards' read), the enemies' health (/battle's; else foes=), the
                                             blades (the bot's keys named as the hand's or deck's card: another copy of
                                             one on isn't tried), traps (on the enemy whose most health is trapmax, else
                                             the one with the most) and aura the bot counts, the blades and traps cast
                                             this battle (the bot's used flags - not sent: the blades on taken as cast),
                                             treasure cards drawn and drawing off (Draw.ahk), the worn deck's main side
                                             less the hand as the draw pile, its treasure side drawn the bot's way (the
                                             decks' last reading - never read in a battle), the rest of the battle
                                             played the bot's way (vals), learned plays a nudge (vision\battlelearn.py)
                                             - within budget ms, the reads included: battlesim.plan_lines
                                             (plan|i|slot|tid|kind|target|won %|rounds|score|why|name|target's name|n|hp
                                             left %|kill %, alt|... the next ones, chain|... the bot's own way,
                                             learned|, note|) + foe|index|name|health|max|boss|plate x (target: that
                                             index; i the card's place in the hand, -1 a pass) + planned|rollouts|ms|ms
                                             in all, or none|<why> (never an ERR)
       [&role=hitter|blader|healer&seat=4-7&mates=name~seat~school~hp~max~role~pips~power~hand|...&teamplan=1&charms=log]
                                             (v1.0.0 batch 3 - none given: as above) the team model: mates the party's
                                             other wizards on your side (hand: tid:kind:pips:school:value[:ench[:mark]];
                                             ...; each card's kind and value from cards.jsonl's facts when known; empty:
                                             not known, its role's way), each with its own hand, pips and health in your
                                             side's cast order (seat), the enemies' single hits on one of you at random;
                                             role / seat yours. teamplan=1: also a play for each wizard whose hand is
                                             known (battlesim.plan_team: order|who|seat|name|i|tid|kind|target|won %|
                                             why|card, teamnote|) - advice. charms=log: the blades, traps, shields,
                                             weaknesses and absorbs on you and each enemy rebuilt from the game's log
                                             (battlerec.charms_now - the party's and the enemies' too) instead of the
                                             bot's own count (the enemies matched by their gid; note| says how many)
       [&hands=party]                        (partyorders, the leader's: each mate's blank hand, pips, power and health
                                             from its own bot's hand for this round - party.py fill_mates; teamplan
                                             implied when a mate's hand was filled in - none filled: no team plan even
                                             with teamplan=1, plan_round held to 300 ms; each follower's order kept for
                                             its next beat - set_orders; teamnote| why a mate's hand wasn't used)
  /partyorder?tag=d<duel>r<round>         -> order|state|round|card|tid|kind|target|won|n|age|why (party.py order_line -
                                             the leader's card for this wizard's hand, advice only; state ok / wait /
                                             none; a marker's none: kind mark); ?lead=1 -> lead|<followers' hands held>
                                             (the leader's bot); ?noplan=<round> -> noplan|<followers told> (the
                                             leader's bot at its round's end: those with a hand for the round and no
                                             order told it wasn't planned). This helper's own server only - never the
                                             LAN's
  /deckfor?zone=<zone path>[&foes=name~name|name...]&school=&hp=&damage=&pierce=&crit=&block=&acc=&resist=&n=60
       [&vals=k:v,...&dvals=<gid>~k:v,...|...]
                                          -> decks matched to a zone's enemies (battlesim.best_decks): each in-game deck
                                             in an Equipment Set (the decks' last reading - never read here), its
                                             settings your settings (vals), and each in-game deck's bot deck profile's
                                             own (dvals) on top - a deck with none: the settings its cards call for on
                                             top -, simulated against the enemy groups fought most in that zone (the
                                             battles recorded - else foes=, one group a |) - deckfor|gid|name|won
                                             %|rounds|hp left %|lost %|groups|battles|why best first,
                                             group|battles|names, zone|, note|; worked out in a thread and kept 10
                                             minutes: the first ask answers none|working it out - ask again; an ask
                                             after the 10 minutes gets the old lines (and a note|) while they're worked
                                             out again (Decks.ahk DeckForZone, Settings: deckzone, off). Every deck
                                             rolls the same dice against a group: the same main deck scores the same
  /quit                                   -> stops
Add &file=<path> to /cards, /badge, /hand, /cut or /plate to look at a saved screenshot instead of the screen (for
tests; the rectangle is then in that picture's pixels).
/cards (memory) and /battle hand the battle recorder a copy of their reading (a queue put, no read): it writes every
battle down in AutoFarmer\learned\battles\ (battlerec.py) - it never slows a request.

Only numpy and Pillow (katsuba is used for a zone .wad only if installed and the built-in reader can't read
it). Stops by itself when the AutoFarmer process (--parent <pid>) is gone.
"""
import argparse
import collections, ctypes, functools, glob, json, math, os, re, struct, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import numpy as np
from PIL import Image

VERSION = '2'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # the AutoFarmer folder
PORT = 47128
# A card counts as there when its RMS distance is under this (calibrated on saved rounds at UI 0.87-1.5:
# the right card 0-6.3, the closest wrong one 9 - Epic's thin strip; see vision\calibrate.py)
CARD_DIST = 8.0
# A badge: the best school's distance under BADGE_DIST and BADGE_GAP better than the next (badges share
# their gold ring, so a resized badge is never close to exact; calibrated: the right badge 0-46 at UI
# 0.87-1.5, the next school 57+)
BADGE_DIST = 50.0
BADGE_GAP = 12.0
LOG = os.path.join(ROOT, 'vision', 'vision.log')


def log(msg):
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 512 * 1024:
            os.replace(LOG, LOG + '.old')
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(time.strftime('%H:%M:%S ') + msg + '\n')
    except OSError:
        pass


# ---------------------------------------------------------------- pictures

def picture_sets():
    """[(dir, scale)]: the main set (UI scale 1) and every hand-cut ui<scale> folder"""
    sets = [(ROOT, 1.0)]
    for d in glob.glob(os.path.join(ROOT, 'ui*')):
        m = re.fullmatch(r'ui(\d+(?:\.\d+)?)', os.path.basename(d))
        if m and os.path.isdir(d) and 0.5 <= float(m.group(1)) <= 3:
            sets.append((d, float(m.group(1))))
    return sets


def load_rgb_mask(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    mask = ~((a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255))
    return a, mask


class Library:
    """The pictures, resized to a UI scale on first use (cached)"""

    def __init__(self):
        self.sets = picture_sets()
        self.cache = {}
        self.lock = threading.Lock()

    def names_in(self, sub):
        """picture names (without .png) in a folder of any set"""
        names = set()
        for d, sc in self.sets:
            for p in glob.glob(os.path.join(d, sub, '*.png')):
                n = os.path.basename(p)[:-4]
                if not n.endswith('.raw'):
                    names.add(n)
        return sorted(names)

    def masters(self, rel, scale):
        """cut copies of rel, best first: one cut at this scale (within 1% - used as it is, make), the nearest
        first; then the sets truly at or above scale, smallest first (shrinking keeps detail); then the smaller
        ones, biggest first. (Till 2026-10-24 a set down to 3% smaller counted as at or above and came first: at
        1.144 ui1.121's Balanceblade enlarged 2% missed about half its copies, the ui1.144 cut found them)"""
        have = [(d, sc) for d, sc in self.sets if os.path.exists(os.path.join(d, rel))]
        near = sorted([x for x in have if abs(x[1] / scale - 1) < 0.01], key=lambda x: abs(x[1] - scale))
        up = sorted([x for x in have if x not in near and x[1] >= scale], key=lambda x: x[1])
        down = sorted([x for x in have if x not in near and x[1] < scale], key=lambda x: -x[1])
        return near + up + down

    def usable(self, rel):
        """whether rel has a cut copy big enough to use (the 8x8 placeholders of 2018 aren't). The folders
        are looked at again: a picture set made since (a card learned at a new UI size) counts"""
        for d, sc in picture_sets():
            p = os.path.join(d, rel)
            if os.path.exists(p):
                with Image.open(p) as im:
                    if im.width >= 12 and im.height >= 12:
                        return True
        return False

    def get(self, rel, scale):
        """(colours HxWx3, mask HxW bool) of picture rel at UI scale, or None if it can't be had"""
        key = (rel, round(scale, 3))
        with self.lock:
            if key in self.cache:
                return self.cache[key]
        made = None
        for d, sc in self.masters(rel, scale):
            made = self.make(os.path.join(d, rel), sc, scale)
            if made is not None:
                break
        with self.lock:
            self.cache[key] = made
        return made

    @staticmethod
    def make(path, from_scale, scale):
        tpl, mask = load_rgb_mask(path)
        h, w = mask.shape
        ratio = scale / from_scale
        # a tiny patch (the 8x8 placeholders cut at UI 1 in 2018) matches almost anything: never used
        if w < 12 or h < 12:
            return None
        if abs(ratio - 1) < 0.01:
            return (tpl, mask) if mask.sum() >= 12 else None
        raw = path[:-4] + '.raw.png'
        colours = np.asarray(Image.open(raw).convert('RGB')).astype(np.float32) if os.path.exists(raw) else tpl
        if colours.shape[:2] != mask.shape:
            colours = tpl
        tw, th = max(4, round(w * ratio)), max(4, round(h * ratio))
        m = mask.astype(np.float32)
        # colours: area average of the solid pixels only; mask: pixels that were (nearly) all solid
        num = np.stack([np.asarray(Image.fromarray(colours[..., c] * m).resize((tw, th), Image.BOX)) for c in range(3)], -1)
        den = np.asarray(Image.fromarray(m).resize((tw, th), Image.BOX))
        out = num / np.maximum(den, 1e-6)[..., None]
        keep = den >= 0.75
        # (the picture's own edge pixels mix with whatever is round it on screen)
        keep[0, :] = keep[-1, :] = False
        keep[:, 0] = keep[:, -1] = False
        if keep.sum() < 12:
            return None
        return out.astype(np.float32), keep


# ---------------------------------------------------------------- matching

def fast_len(n):
    """the smallest size >= n made of 2s, 3s and 5s (an FFT of such a size is quick; a big prime factor,
    e.g. 916 = 4 x 229, makes it slow)"""
    m = n
    while True:
        k = m
        for f in (2, 3, 5):
            while k % f == 0:
                k //= f
        if k == 1:
            return m
        m += 1


class Region:
    """A piece of screen, ready to have pictures matched against it (its FFTs, at a quick size, kept).
    The pictures' FFTs at that size are kept too (TPL_FFT), so after the first look a picture costs one
    multiply and one inverse FFT"""

    def __init__(self, img):
        self.img = img
        self.H, self.W = img.shape[:2]
        self.s = (fast_len(self.H), fast_len(self.W))
        self.fi = [np.fft.rfft2(img[..., c], s=self.s) for c in range(3)]
        self.fi2 = np.fft.rfft2((img ** 2).sum(axis=2), s=self.s)

    def distance_map(self, tpl, mask, key=None):
        """RMS colour distance over the mask at every position where the picture fits (top left). key: a
        name for the picture's FFTs to be kept under (None: not kept)"""
        th, tw = mask.shape
        if th > self.H or tw > self.W:
            return None
        ck = (key, self.s) if key is not None else None
        parts = tpl_cached(ck) if ck else None
        if parts is None:
            m = mask.astype(np.float32)
            tp = tpl.astype(np.float32)
            fm = np.conj(np.fft.rfft2(m, s=self.s)).astype(np.complex64)
            fmt = [np.conj(np.fft.rfft2(m * tp[..., c], s=self.s)).astype(np.complex64) for c in range(3)]
            const = float(sum((m.astype(np.float64) * tp[..., c].astype(np.float64) ** 2).sum() for c in range(3)))
            parts = (fm, fmt, const, float(m.sum()))
            if ck:
                tpl_keep(ck, parts)
        fm, fmt, const, count = parts
        acc = self.fi2 * fm - 2 * (self.fi[0] * fmt[0] + self.fi[1] * fmt[1] + self.fi[2] * fmt[2])
        d = np.fft.irfft2(acc, s=self.s)[:self.H - th + 1, :self.W - tw + 1] + const
        return np.sqrt(np.maximum(d, 0) / (3 * count))


# The pictures' FFTs, by (picture, UI scale, FFT size), least recently used first. Each is the size of
# the screen rectangle it was made for (a badge on the hitter strip: ~15 MB), so past TPL_BUDGET bytes
# the oldest go - a new window size or UI scale would otherwise add a full set every time
TPL_FFT = collections.OrderedDict()
TPL_BYTES = 0
TPL_BUDGET = 200 * 2 ** 20
TPL_LOCK = threading.Lock()


def tpl_cached(ck):
    with TPL_LOCK:
        parts = TPL_FFT.get(ck)
        if parts is not None:
            TPL_FFT.move_to_end(ck)
        return parts


def tpl_keep(ck, parts):
    global TPL_BYTES
    size = parts[0].nbytes + sum(a.nbytes for a in parts[1])
    with TPL_LOCK:
        if ck in TPL_FFT:
            return
        TPL_FFT[ck] = parts
        TPL_BYTES += size
        while TPL_BYTES > TPL_BUDGET and len(TPL_FFT) > 1:
            _, old = TPL_FFT.popitem(last=False)
            TPL_BYTES -= old[0].nbytes + sum(a.nbytes for a in old[1])


def local_minima(dmap, limit, size):
    """(x, y, dist) of every position under limit that is the best within size (w, h) round it"""
    ys, xs = np.nonzero(dmap < limit)
    if not len(ys):
        return []
    order = np.argsort(dmap[ys, xs])
    taken, out = [], []
    w, h = size
    for i in order:
        x, y = int(xs[i]), int(ys[i])
        if any(abs(x - tx) < w and abs(y - ty) < h for tx, ty in taken):
            continue
        taken.append((x, y))
        out.append((x, y, float(dmap[y, x])))
    return out


def grab_screen(x1, y1, x2, y2):
    """the screen rectangle as HxWx3 RGB floats, copied with GDI (only that rectangle)"""
    w, h = x2 - x1, y2 - y1
    u32, g32 = ctypes.windll.user32, ctypes.windll.gdi32
    vp = ctypes.c_void_p
    u32.GetDC.restype = vp; u32.GetDC.argtypes = [vp]
    u32.ReleaseDC.argtypes = [vp, vp]
    g32.CreateCompatibleDC.restype = vp; g32.CreateCompatibleDC.argtypes = [vp]
    g32.CreateDIBSection.restype = vp
    g32.CreateDIBSection.argtypes = [vp, vp, ctypes.c_uint, ctypes.POINTER(vp), vp, ctypes.c_uint]
    g32.SelectObject.restype = vp; g32.SelectObject.argtypes = [vp, vp]
    g32.BitBlt.argtypes = [vp, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, vp, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
    g32.DeleteObject.argtypes = [vp]; g32.DeleteDC.argtypes = [vp]
    bmi = (ctypes.c_uint32 * 10)()
    bmi[0] = 40
    bmi[1] = ctypes.c_uint32(w).value
    bmi[2] = ctypes.c_uint32(-h & 0xFFFFFFFF).value    # top-down rows
    bmi[3] = 1 | (32 << 16)                            # 1 plane, 32 bits
    sdc = u32.GetDC(None)
    mdc = g32.CreateCompatibleDC(sdc)
    bits = vp()
    hbm = g32.CreateDIBSection(mdc, ctypes.addressof(bmi), 0, ctypes.byref(bits), None, 0)
    try:
        if not hbm or not bits.value:
            raise OSError('CreateDIBSection failed')
        old = g32.SelectObject(mdc, hbm)
        g32.BitBlt(mdc, 0, 0, w, h, sdc, x1, y1, 0x00CC0020)
        buf = ctypes.string_at(bits.value, w * h * 4)
        g32.SelectObject(mdc, old)
    finally:
        if hbm:
            g32.DeleteObject(hbm)
        g32.DeleteDC(mdc)
        u32.ReleaseDC(None, sdc)
    return np.frombuffer(buf, np.uint8).reshape(h, w, 4)[..., 2::-1].astype(np.float32)


def snap_out_ok(out):
    """/snap writes only snap_<...>.jpg into a "Wiz-Maxxing logs\\<PC>" folder"""
    out = os.path.normpath(out)
    d = os.path.dirname(out)
    return (bool(re.match(r'^snap_[\w.-]+\.jpg$', os.path.basename(out), re.I))
            and os.path.basename(os.path.dirname(d)).lower() == 'wiz-maxxing logs' and os.path.isabs(out))


def snap(x1, y1, x2, y2, out, keep=15):
    """/snap: the screen rectangle into out (JPEG, half size when wider than 1600); the newest keep snap_*.jpg kept
    (by their time on disk)"""
    if x2 <= x1 or y2 <= y1:
        raise ValueError('an empty rectangle')
    a = grab_screen(x1, y1, x2, y2)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if im.width > 1600:
        im = im.resize((im.width // 2, im.height // 2), Image.BILINEAR)
    d = os.path.dirname(out)
    os.makedirs(d, exist_ok=True)
    im.save(out + '.tmp', 'JPEG', quality=70)
    os.replace(out + '.tmp', out)
    if keep > 0:
        for f in sorted(glob.glob(os.path.join(d, 'snap_*.jpg')), key=os.path.getmtime)[:-keep]:
            try:
                os.remove(f)
            except OSError:
                pass
    return out


def grab(x1, y1, x2, y2, file=None):
    if file:
        return np.asarray(Image.open(file).convert('RGB').crop((x1, y1, x2, y2))).astype(np.float32)
    return grab_screen(x1, y1, x2, y2)


LIB = None


def find_cards(x1, y1, x2, y2, scale, pics, file=None, missing=None):
    """where the card pictures pics ("dir/name", e.g. "balance/hit1") are in the rectangle: [(pic, x, y,
    dist)], best first. Where two pictures claim the same card, the closer one keeps it. missing (a list):
    gets the pictures that have a real cut copy but couldn't be looked for (it couldn't be made at this
    size, or it's bigger than the rectangle) - a picture with none (an 8x8 placeholder) is just absent"""
    region = Region(grab(x1, y1, x2, y2, file))
    found = []
    for want in pics:
        if '/' not in want:
            continue
        sub, name = want.split('/', 1)
        pic = LIB.get(f'{sub}\\{name}.png', scale)
        if pic is None:
            if missing is not None and LIB.usable(f'{sub}\\{name}.png'):
                missing.append(want)
            continue
        tpl, mask = pic
        dmap = region.distance_map(tpl, mask, (want, round(scale, 3)))
        if dmap is None:
            if missing is not None:
                missing.append(want)
            continue
        for x, y, dist in local_minima(dmap, CARD_DIST, (tpl.shape[1], tpl.shape[0])):
            found.append((want, x + x1, y + y1, dist, tpl.shape[1], tpl.shape[0]))
    found.sort(key=lambda f: f[3])
    kept = []
    for f in found:
        # the same spot (a card is about 3 pictures wide) taken by a better match already? (a learned
        # picture - cut from the whole card picture, so often the closer - never hides a hand-cut one)
        if any(abs(f[1] - k[1]) < max(f[4], k[4]) * 0.8 and abs(f[2] - k[2]) < max(f[5], k[5]) and f[0] != k[0]
               and not (k[0].startswith('learned/') and not f[0].startswith('learned/')) for k in kept):
            continue
        kept.append(f)
    return [(f[0], f[1], f[2], f[3]) for f in kept]


def round_only(mask):
    """a badge is round: its square picture's corners show whatever is behind the name plate"""
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = min(h, w) / 2 - 1
    return mask & ((xx + 0.5 - w / 2) ** 2 + (yy + 0.5 - h / 2) ** 2 <= r * r)


def find_badges(x1, y1, x2, y2, scale, schools, file=None):
    """the badges in the rectangle that are clearly one school: each school's best spot, kept if it's
    under BADGE_DIST, BADGE_GAP better than every other school's best at the same spot (badges share
    their gold ring, so a resized one is never close to exact - the ranking is what tells them apart).
    A team battle shows several plates: real badges came to 0-49, a school's best on no badge 55+.
    [(school, x, y, dist)] best first; [] none; None: the best spot is unclear (two schools too close)"""
    region = Region(grab(x1, y1, x2, y2, file))
    out = []
    for sch in schools:
        pic = LIB.get(f'{sch}\\{sch}.png', scale)
        if pic is None:
            continue
        tpl, mask = pic
        dmap = region.distance_map(tpl, round_only(mask), ('badge ' + sch, round(scale, 3)))
        if dmap is None:
            continue
        y, x = np.unravel_index(np.argmin(dmap), dmap.shape)
        out.append((sch, int(x) + x1, int(y) + y1, float(dmap[y, x]), tpl.shape[1], tpl.shape[0]))
    out.sort(key=lambda f: f[3])
    log('  badges: ' + (', '.join(f'{o[0]} {o[3]:.1f} at {o[1]},{o[2]}' for o in out) or 'none to compare'))
    kept = []
    for s in out:
        if s[3] >= BADGE_DIST:
            break
        rivals = [r for r in out if r is not s and abs(r[1] - s[1]) < s[4] and abs(r[2] - s[2]) < s[5]]
        if any(r[3] - s[3] < BADGE_GAP for r in rivals):
            if not kept and not any(r[3] < s[3] for r in rivals):
                return None
            continue
        kept.append(s)
    return [k[:4] for k in kept]


# ---------------------------------------------------------------- the hand, card by card

# A card in hand, in UI-scale-1 pixels (measured at UI 1.144 / 1440p: 81 x 135 px, 93.84 px apart, top
# 64 px above the middle of the screen)
CARD_W, CARD_H, CARD_PITCH, CARD_TOP = 70.8, 118.0, 82.03, -55.94
# from the card's top left: the picture cut for it (as hit1.png etc. were cut), the type icon's box (the
# cardicons pictures are cut from 1 px inside it), the pip cost's digit (in here), the part that's grey
# when the card is greyed out
ART_BOX = (19.23, 25.35, 28.85, 21.85)
ICON_BOX = (54.2, 55.9, 14.9, 14.9)
DIGIT_BOX = (3.5, 15.7, 12.2, 14.0)
GREY_BOX = (8.0, 18.0, 52.0, 34.0)
# A type icon matches under ICON_DIST, ICON_GAP better than the next type (saved rounds at UI 0.87-1.5:
# the right icon 0-36, a wrong one 42+); a digit with at least
# DIGIT_IOU of its pixels in common with the cut one (and DIGIT_GAP more than the next; at UI 1.144 the
# right digit 0.62+, a wrong one 0.55 at most - at other sizes the 8 px digits often go unread)
ICON_DIST, ICON_GAP = 40.0, 8.0
DIGIT_IOU, DIGIT_GAP = 0.6, 0.1
# Pip digits cut from learned cards (1-bit masks, <digit>_<UI scale they were cut at>.png), next to this file
DIGITS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'digits')
# A box is a card (real) when all four hold (card_feats; measured on the learned cards and 60 saved battle
# rounds at UI 0.807-1.5: real cards eTxt 1.0 (0.855 seen at UI 0.917; non-cards 0.71 at most), pipYel 0.055-0.267,
# white 0.024 at most, iconD 69 at most;
# the deck's back, empty spots, the floor, the timer and hint text, a popup over a card each fail one):
# the art / text box border right across (eTxt), some yellow pip digit and not a yellow banner or the timer
# (pipYel), no white popup over it (white), something like a type icon where it goes (iconD)
REAL_ETXT, REAL_PIP, REAL_WHITE, REAL_ICON = 0.80, (0.04, 0.30), 0.10, 90.0
# A Myth card's gold frame round the pip digit counts as its yellow: 0.33-0.46 (2026-10-24, 1440p - every Myth card was
# "not a card"). With the text box border clear right across (eTxt >= REAL_ETXT_SURE) up to REAL_PIP_GOLD is a card:
# of 147 saved 1440p screens, everything else with that much yellow had no border at all (eTxt 0.00 - the shop, a
# monitor's screen), and no real card of another school went over 0.26
REAL_ETXT_SURE, REAL_PIP_GOLD = 0.90, 0.60
# a treasure card: its text box is lavender, not parchment (median blue / median red: Sandstorm 1.59, deck
# cards 0.58-0.60; an item card - the wand's Minor Clash - is lavender too, 1.59)
TC_BR = 1.2
TEXT_BOX = (6.0, 78.0, 58.0, 26.0)
WHITE_BOX = (0.0, 15.0, 70.8, 60.0)


def box(b, sc, left, top):
    """a card box (UI-1 pixels from the card's top left) as integer x1, y1, x2, y2 at scale sc"""
    x, y, w, h = b
    return (int(round(left + x * sc)), int(round(top + y * sc)), int(round(left + (x + w) * sc)), int(round(top + (y + h) * sc)))


def card_lefts(img, sc, expect_top):
    """the cards' left edges and top in img (the hand rectangle) from the cards' top edges: (top, [left])"""
    H, W = img.shape[:2]
    cw, pitch = CARD_W * sc, CARD_PITCH * sc
    g = np.abs(np.diff(img.sum(axis=2), axis=0)) > 90           # row r -> r + 1 changes sharply
    t0 = int(round(expect_top))
    top, best = t0, -1.0
    for r in range(max(1, t0 - 8), min(H - 1, t0 + 9)):
        v = g[r - 1].mean()
        if v > best:
            best, top = v, r
    on = g[max(0, top - 4):top + 2].any(axis=0)
    k = max(1, round(3 * sc))
    on = np.convolve(on.astype(float), np.ones(2 * k + 1), 'same') > 0
    starts, x = [], 0
    while x < W:
        if not on[x]:
            x += 1
            continue
        s = x
        while x < W and on[x]:
            x += 1
        s, e = s + k, x - k
        if e - s < cw * 0.8:
            continue
        # touching cards (no gap seen between them): split by the pitch
        for i in range(max(1, round((e - s + pitch - cw) / pitch))):
            starts.append(s + i * pitch)
    return top, starts


def grid(starts, pitch, anchors=()):
    """the lefts on one grid (cards are exactly pitch apart): its phase from anchors (lefts known exactly,
    from known pictures) if any, else from starts"""
    pts = list(anchors) or list(starts)
    if not pts:
        return []
    base = pts[0]
    phase = base + float(np.median([(p - base) - round((p - base) / pitch) * pitch for p in pts]))
    ks = sorted(set(round((p - phase) / pitch) for p in list(starts) + list(anchors)))
    return [phase + k * pitch for k in ks]


def fit_lefts(img, lefts, sc, top):
    """the lefts moved together (within 5 px) to where the cards' left edges change most sharply"""
    if not lefts:
        return lefts
    g = np.abs(np.diff(img.sum(axis=2), axis=1))
    ya, yb = int(top + 10 * sc), int(top + (CARD_H - 10) * sc)
    best = (-1.0, 0.0)
    for off in np.arange(-5, 5.01, 0.5):
        s = 0.0
        for left in lefts:
            x = int(round(left + off)) - 1
            if 0 <= x < g.shape[1]:
                s += float(g[ya:yb, x].mean())
        if s > best[0]:
            best = (s, float(off))
    return [left + best[1] for left in lefts]


def yellow(p):
    """the pip digit's pixels: bright yellow (the art's tan has G well under R)"""
    r, g, b = p[..., 0], p[..., 1], p[..., 2]
    return (r > 130) & (g > 0.9 * r) & (b < 0.45 * r)


def digit_masks(sc):
    """the cut pip digits at scale sc: {digit: bool mask cropped to the digit}. A digit comes from a picture
    set's carddigits (solid where it isn't magenta) or vision\\digits\\<digit>_<scale>.png (a 1-bit mask);
    when there are several, the one cut at the UI scale nearest sc, resized to it"""
    have = {}
    for d, dsc in LIB.sets:
        for p in glob.glob(os.path.join(d, 'carddigits', '*.png')):
            n = os.path.basename(p)[:-4]
            if n.endswith('.raw') or n.startswith('unknown'):
                continue
            have.setdefault(n, []).append((dsc, p, False))
    for p in glob.glob(os.path.join(DIGITS, '*.png')):
        m = re.fullmatch(r'([0-9a-z]+)_(\d+(?:\.\d+)?)\.png', os.path.basename(p).lower())
        if m and 0.3 <= float(m.group(2)) <= 4:
            have.setdefault(m.group(1), []).append((float(m.group(2)), p, True))
    out = {}
    for n, srcs in have.items():
        dsc, p, bits = min(srcs, key=lambda s: abs(math.log(sc / s[0])))
        try:
            m = np.asarray(Image.open(p).convert('L')) > 127 if bits else load_rgb_mask(p)[1]
        except OSError:
            continue
        if abs(sc / dsc - 1) >= 0.01:
            h, w = m.shape
            m = np.asarray(Image.fromarray(m.astype(np.uint8) * 255).resize((max(1, round(w * sc / dsc)), max(1, round(h * sc / dsc))), Image.BILINEAR)) > 127
        if m.any():
            out[n] = m
    return out


def specks_out(m, least=3):
    """m without its specks - pieces of fewer than least pixels (8-connected): a treasure card's lavender frame and the
    art's tan put a yellow pixel or two by the pip digit, and every one counts against the digit's match (a Sharpened
    Blade's 0 at 0.57, under DIGIT_IOU: "? pips", 2026-10-23)"""
    m = m.copy()
    H, W = m.shape
    seen = np.zeros_like(m)
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        stack, piece = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            piece.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        if len(piece) < least:
            for y, x in piece:
                m[y, x] = False
    return m


def read_digit(patch, masks):
    """(digit, score) of the pip cost in patch: each cut digit slid over the patch's yellow pixels, scored
    by how many it shares with them over all of both (so a 1 inside a 4 scores low). ("", best score) if
    none matches clearly"""
    m = specks_out(yellow(patch))
    total = int(m.sum())
    if total < 4:
        return '', 0.0
    H, W = m.shape
    scores = []
    for d, t in masks.items():
        th, tw = t.shape
        best = 0.0
        tn = int(t.sum())
        for y in range(0, max(1, H - th + 1)):
            for x in range(0, max(1, W - tw + 1)):
                win = m[y:y + th, x:x + tw]
                if win.shape != t.shape:
                    continue
                both = int((win & t).sum())
                best = max(best, both / (tn + total - both))
        scores.append((best, d))
    scores.sort(reverse=True)
    if not scores or scores[0][0] < DIGIT_IOU or (len(scores) > 1 and scores[0][0] - scores[1][0] < DIGIT_GAP):
        return '', scores[0][0] if scores else 0.0
    return scores[0][1], scores[0][0]


def read_icon(img, sc, left, top):
    """(type, dist) of the card's type icon: the best cardicons picture within 4 px of where it should be"""
    x1, y1, x2, y2 = box(ICON_BOX, sc, left, top)
    pad = max(3, round(4 * sc))
    H, W = img.shape[:2]
    x1, y1, x2, y2 = max(0, x1 - pad), max(0, y1 - pad), min(W, x2 + pad + 2), min(H, y2 + pad + 2)
    if x2 - x1 < 8 or y2 - y1 < 8:
        return '', 99.0
    region = Region(img[y1:y2, x1:x2])
    out = []
    for n in LIB.names_in('cardicons'):
        if n.startswith('unknown'):
            continue
        pic = LIB.get(f'cardicons\\{n}.png', scale_key(sc))
        if pic is None:
            continue
        tpl, mask = pic
        dmap = region.distance_map(tpl, mask)
        if dmap is None:
            continue
        out.append((float(dmap.min()), n))
    out.sort()
    if not out or out[0][0] >= ICON_DIST or (len(out) > 1 and out[1][0] - out[0][0] < ICON_GAP):
        return '', out[0][0] if out else 99.0
    return out[0][1], out[0][0]


def scale_key(sc):
    return round(sc, 3)


def is_grey(img, sc, left, top):
    """greyed out (can't be cast now): nearly all of the card's middle has no colour"""
    x1, y1, x2, y2 = box(GREY_BOX, sc, left, top)
    p = img[max(0, y1):y2, max(0, x1):x2]
    if p.size == 0:
        return False
    return float(((p.max(axis=2) - p.min(axis=2)) <= 6).mean()) > 0.85


def card_feats(img, sc, left, top, icon_d):
    """what tells a card from something else in a card's place (img: the hand rectangle or a cut card; left,
    top: where the card's top left is in it; icon_d: read_icon's distance there): {eTxt, pipYel, white,
    iconD, br, tc} - see REAL_* and TC_BR"""
    H, W = img.shape[:2]

    def crop(b, dx=0.0, dy=0.0):
        x1, y1, x2, y2 = box((b[0] + dx, b[1] + dy, b[2], b[3]), sc, left, top)
        return img[max(0, y1):min(H, y2), max(0, x1):min(W, x2)]
    # the art / text box border: the share of columns 5-65 with a sharp row change in rows 68-80
    a, b = int(round(top + 68 * sc)), int(round(top + 80 * sc))
    c, d = int(round(left + 5 * sc)), int(round(left + 65 * sc))
    a, b, c, d = max(0, a), min(H - 1, b), max(0, c), min(W, d)
    if b > a and d > c:
        g = np.abs(np.diff(img[a:b + 1, c:d].sum(axis=2), axis=0)) > 90
        e_txt = float(g.any(axis=0).mean())
    else:
        e_txt = 0.0
    # the pip digit's yellow, the best of 3 UI px either way
    pip = 0.0
    for dy in (-3, 0, 3):
        for dx in (-3, 0, 3):
            q = crop(DIGIT_BOX, dx, dy)
            if q.size:
                pip = max(pip, float(yellow(q).mean()))
    # white (a popup or the floor's glare over the card)
    q = crop(WHITE_BOX)
    white = float(((q.min(axis=2) > 225) & ((q.max(axis=2) - q.min(axis=2)) < 20)).mean()) if q.size else 0.0
    # the text box's colour: lavender on a treasure card
    q = crop(TEXT_BOX)
    br = float(np.median(q[..., 2]) / max(1.0, float(np.median(q[..., 0])))) if q.size else 0.0
    return dict(eTxt=e_txt, pipYel=pip, white=white, iconD=float(icon_d), br=br, tc=int(br >= TC_BR))


def is_real(f):
    """a card (card_feats): see REAL_* (a Myth card's gold frame: REAL_PIP_GOLD)"""
    pip_hi = REAL_PIP_GOLD if f['eTxt'] >= REAL_ETXT_SURE else REAL_PIP[1]
    return (f['eTxt'] >= REAL_ETXT and REAL_PIP[0] <= f['pipYel'] <= pip_hi and f['white'] < REAL_WHITE
            and f['iconD'] < REAL_ICON)


def feats_text(f):
    return f"eTxt={f['eTxt']:.2f} pipYel={f['pipYel']:.3f} white={f['white']:.3f} iconD={f['iconD']:.1f}"


# learned card id -> its .card.png passes the card check (a learned picture cut from something that isn't a card -
# the timer, the deck's back - is never used: until AutoFarmer moves it away it would claim real cards)
LEARNED_OK = {}


def learned_is_card(cid):
    """whether learned card cid was cut from a card: its <set>\\learned\\<cid>.card.png passes is_real (looked at
    once; True when there's no .card.png to look at)"""
    if cid in LEARNED_OK:
        return LEARNED_OK[cid]
    ok = True
    for d, sc in LIB.sets:
        p = os.path.join(d, 'learned', cid + '.card.png')
        if not os.path.exists(p):
            continue
        try:
            img = np.asarray(Image.open(p).convert('RGB')).astype(np.float32)
        except OSError:
            break
        csc = img.shape[1] / CARD_W
        f = card_feats(img, csc, 0, 0, read_icon(img, csc, 0, 0)[1])
        ok = is_real(f)
        if not ok:
            log(f'  learned/{cid}: its card picture isn\'t a card ({feats_text(f)}) - never used to name a card')
        break
    LEARNED_OK[cid] = ok
    return ok


def read_hand(x1, y1, x2, y2, scale, pics, file=None, learned=None, here='', thumbs=''):
    """the cards in hand, left to right (see /hand). learned: the learned cards ("<id>:<picture set
    folder>:<slot>"), each also recognised as a copy that differs a little. here: the picture set folder
    for this UI size (a card learned at another size is cut into it)"""
    img = grab(x1, y1, x2, y2, file)
    # (a learned picture that wasn't cut from a card is never looked for: learned_is_card)
    pics = [p for p in pics if not (p.startswith('learned/') and not learned_is_card(p[8:]))]
    known = find_cards(x1, y1, x2, y2, scale, pics, file)
    pitch, cw, ch = CARD_PITCH * scale, CARD_W * scale, CARD_H * scale
    # the hand's height is fixed (y1 is ScreenY - 75 UI px, as AutoFarmer asks); the cards' lefts come
    # from their top edges, on one grid, then fitted to their left edges (the hand-cut pictures sit at
    # different places on their cards, so they can't place a card)
    top = int(round((75 + CARD_TOP) * scale))
    starts = card_lefts(img, scale, top)[1]
    lefts = fit_lefts(img, grid(starts, pitch), scale, top)
    masks = digit_masks(scale)
    cards = []
    for left in lefts:
        if left < -cw * 0.2 or left + cw > img.shape[1] + cw * 0.2:
            continue
        mine = [k for k in known if left - 0.15 * cw <= k[1] - x1 <= left + 0.85 * cw]
        # (a hand-cut or slot picture names the card before a learned one of the same card)
        mine = [k for k in mine if not k[0].startswith('learned/')] or mine
        best = min(mine, key=lambda k: k[3]) if mine else None
        kind, kd = read_icon(img, scale, left, top)
        # (is it a card at all? Something else where a card goes - the deck's back, the floor, the timer
        # when the rectangle is off - is never named by a learned picture: those were cut from cards)
        f = card_feats(img, scale, int(round(left)), top, kd)
        grey = is_grey(img, scale, left, top)
        real = is_real(f)
        # (a greyed-out card - not enough pips: its washed-out art reads as "white" (0.29, 2026-10-25: three Power Novas
        # "not a card"), so the white-popup test is left out for it; still the text box border right across and a type
        # icon where it goes. It's a card in hand for the counts - the flee check's, the game's hand's - never learned
        # or compared while grey)
        if not real and grey and f['eTxt'] >= REAL_ETXT and f['iconD'] < REAL_ICON:
            real = True
        if best and not real and best[0].startswith('learned/'):
            best = None
        dx1, dy1, dx2, dy2 = box(DIGIT_BOX, scale, left, top)
        pips, ps = read_digit(img[max(0, dy1):dy2, max(0, dx1):dx2], masks)
        cards.append(dict(left=int(round(left)) + x1, top=top + y1, w=int(round(cw)), h=int(round(ch)),
                          known=best[0] if best else '', kdist=best[3] if best else 0.0,
                          grey=grey, kind=kind, kinddist=kd, pips=pips, pipscore=ps,
                          real=int(real), tc=f['tc'], feats=f,
                          art=img[max(0, box(ART_BOX, scale, left, top)[1]):box(ART_BOX, scale, left, top)[3],
                                  max(0, box(ART_BOX, scale, left, top)[0]):box(ART_BOX, scale, left, top)[2]]))
    # Copies of a card differ a little (a shimmer: a few variants, 0-17 apart over the whole picture), so a
    # learned picture - cut solid from one copy - is compared leaving out the 20% of pixels that differ
    # most (LIKE_DIST); each time another copy is seen like that, the pixels that differ go see-through in
    # the learned picture (and its slot's copy), until it matches every copy as a hand-cut one does
    # A card learned at another UI size: its picture resized doesn't match closely enough, so this copy is
    # cut into the picture set for this size (here) - its learned picture and its slot's.
    # liked 1 = a slot's picture was just written (made see-through, or cut at this size): the battle's own
    # search finds the card if it looks again
    # (a box that isn't a card is never compared: no learned picture is written or named from it)
    for i, c in enumerate(cards):
        c['same'], c['liked'] = 0, 0
        if c['known'] or c['grey'] or not c['real'] or c['art'].size == 0:
            continue
        bx1, by1, bx2, by2 = box(ART_BOX, scale, c['left'] - x1, c['top'] - y1)
        around = img[max(0, by1 - LIKE_PAD):by2 + LIKE_PAD, max(0, bx1 - LIKE_PAD):bx2 + LIKE_PAD]
        # (every learned picture is compared - and every slot or hand-cut one the plain match missed, below - and the
        # closest names the box, not the first one under its limit: 2026-10-25 Balanceblade's picture, learned before
        # Bladestorm's, came to 16 on Bladestorm's copies and named 142 of 177 Bladestorm boxes - Bladestorm's learned
        # picture sits 8 px off the art box, out of reach here, while its slot's picture, resources\blade4, matches it at 7
        # below, never looked at once a learned picture had named the box. A slot's picture names the box over a learned
        # card in no slot that comes up less than LIKE_SLOT_GAP closer: two pictures of one card, the slot's the one the
        # bot plays it by)
        hits = []
        for ent in learned or ():
            if not learned_is_card(ent.split(':', 1)[0]):
                continue
            pic = learned_pic(ent, scale, here)
            if pic is None:
                continue
            d, (dy, dx), diff = like(around, pic['tpl'], pic['mask'])
            if d < LIKE_DIST:
                hits.append((d, len(hits), pic, dy, dx, diff))
        got = None
        if hits:
            got = min(hits, key=lambda h_: h_[:2])
            if not got[2]['slot']:
                slots = [h_ for h_ in hits if h_[2]['slot'] and h_[0] - got[0] < LIKE_SLOT_GAP]
                if slots:
                    got = min(slots, key=lambda h_: h_[:2])
        # (or a card the bot has a picture for that the plain match missed: never learned twice. A
        # hand-cut picture can be anywhere on its card: its best place by the plain match, then compared
        # there leaving out the pixels that differ most)
        L, T = c['left'] - x1, c['top'] - y1
        whole = img[max(0, T):T + int(round(ch)), max(0, L):L + int(round(cw))]
        region = Region(whole)
        cut = None
        for want in pics:
            if '/' not in want or want.startswith('learned/'):
                continue
            sub, name = want.split('/', 1)
            pic = LIB.get(f'{sub}{os.sep}{name}.png', scale)
            if pic is None:
                continue
            # (its FFTs kept, as find_cards' - every unknown card is looked at so now: a card-sized set per picture)
            dmap = region.distance_map(pic[0], pic[1], ('card ' + want, round(scale, 3)))
            if dmap is None:
                continue
            py, px = np.unravel_index(np.argmin(dmap), dmap.shape)
            h, w = pic[1].shape
            d = like(whole[max(0, py - 1):py + h + 1, max(0, px - 1):px + w + 1], pic[0], pic[1])[0]
            if d < LIKE_CUT and (cut is None or d < cut[0]):
                cut = (d, want)
        # (the slot or hand-cut picture when it's closer than the learned one - or it's the same slot's: the learned
        # picture then, made see-through as ever; a learned card in no slot gives way to it within LIKE_SLOT_GAP)
        if cut and got and cut[1] != got[2]['name'] and (cut[0] < got[0] or (not got[2]['slot'] and cut[0] - got[0] < LIKE_SLOT_GAP)):
            got = None
        if got:
            d, _, pic, dy, dx, diff = got
            c['known'], c['kdist'] = pic['name'], d
            if pic['files']:
                c['liked'] = int(refine(pic, diff) and pic['slot'] != '')
            elif here:
                h, w = pic['mask'].shape
                c['liked'] = int(cut_here(around[dy:dy + h, dx:dx + w], pic, here))
        elif cut:
            c['known'], c['kdist'] = cut[1], cut[0]
        if c['known']:
            continue
        # the same as a card further left nobody knows (two copies in hand): same = that one's number
        # (1 = the leftmost), so it isn't learned twice
        for j in range(i):
            o = cards[j]
            if o['known'] or o['grey'] or not o['real'] or o['art'].size == 0:
                continue
            if like(around, o['art'], np.ones(o['art'].shape[:2], bool))[0] < LIKE_DIST:
                c['same'] = o['same'] or j + 1
                break
    # each card as it looks, for the dashboard (thumbs: a folder)
    if thumbs:
        os.makedirs(thumbs, exist_ok=True)
        cw_i, ch_i = int(round(cw)), int(round(ch))
        for i, c in enumerate(cards, 1):
            L, T = c['left'] - x1, c['top'] - y1
            whole = img[max(0, T):T + ch_i, max(0, L):L + cw_i]
            if whole.size:
                Image.fromarray(np.clip(whole, 0, 255).astype(np.uint8)).save(os.path.join(thumbs, f'hand{i}.png'))
    return cards


# Two copies of the same card: under LIKE_DIST with the 20% of pixels that differ most left out (saved
# rounds: the same card 0-19, another card 37+), looked for within LIKE_PAD px; a pixel that differs by
# more than LIKE_PIXEL goes see-through in the learned picture (so the plain match, under CARD_DIST over the
# pixels left, finds the next copy like this one)
LIKE_DIST, LIKE_PAD, LIKE_PIXEL = 27.0, 3, 10.0
# Two learned pictures under LIKE_DIST on one box: the closest names it - but a slot's over one in no slot that's less than
# this closer (the learned cards' own cuts at 1.144, 2026-10-25: a card's two pictures 1.1-4.1 apart; Hex's picture came to
# 22.2 on an Ice card its own picture matched at 0.0)
LIKE_SLOT_GAP = 8.0
# A hand-cut picture (its shimmering pixels already see-through): under LIKE_CUT that way (another card
# came to 26 against a thin, resized one)
LIKE_CUT = 15.0
# A copy may make at most this share of a learned picture's solid pixels see-through, and this share of the picture
# always stays solid (refine); when a refine was last refused per picture, to log it once in a while
REFINE_MOST, REFINE_KEEP = 0.5, 0.25
REFINE_SAID = {}


def like(around, tpl, mask):
    """(distance leaving out the worst 20% of pixels, (dy, dx), each pixel's distance there) of picture tpl
    (solid where mask) at its best place in around"""
    H, W = around.shape[:2]
    h, w = tpl.shape[:2]
    best = (1e9, (0, 0), None)
    if mask.sum() < 12:
        return best
    for dy in range(H - h + 1):
        for dx in range(W - w + 1):
            per = np.sqrt(((around[dy:dy + h, dx:dx + w] - tpl) ** 2).mean(axis=2))
            d = np.sort(per[mask])
            v = float(np.sqrt((d[:max(1, int(len(d) * 0.8))] ** 2).mean()))
            if v < best[0]:
                best = (v, (dy, dx), per)
    return best


def set_scale(setdir):
    """a picture set folder's UI scale (ui1.144 -> 1.144; the main set 1)"""
    m = re.fullmatch(r'ui(\d+(?:\.\d+)?)', os.path.basename(setdir))
    return float(m.group(1)) if m else 1.0


def same_picture(a, b):
    """two picture files with the same pixels"""
    try:
        return np.array_equal(np.asarray(Image.open(a).convert('RGB')), np.asarray(Image.open(b).convert('RGB')))
    except OSError:
        return False


def learned_pic(ent, scale, here=''):
    """a learned card from /hand's learned= list ("<id>:<picture set folder>:<slot>", slot e.g.
    balance\\hit1 or blank) at UI scale: {tpl, mask, name it's known by, files (written when it's made
    see-through: [] when the picture is from another size, resized), cid, slot, setdir}. A copy cut at this
    size into here (the picture set for it) comes first. The slot counts only while its picture is still
    this card's (else the card is known by its own name, learned/<id>, and the slot is left alone)"""
    try:
        cid, setdir, slot = ent.split(':', 2)
    except ValueError:
        return None
    # (still its slot's card where it was learned?)
    if slot and not same_picture(os.path.join(ROOT, setdir, slot + '.png'), os.path.join(ROOT, setdir, 'learned', cid + '.png')):
        slot = ''
    if here and abs(scale / set_scale(here) - 1) < 0.01 and os.path.exists(os.path.join(ROOT, here, 'learned', cid + '.png')):
        setdir = here
    base = os.path.join(ROOT, setdir, 'learned', cid)
    if not os.path.exists(base + '.png'):
        return None
    slotfile = os.path.join(ROOT, setdir, slot + '.png') if slot else ''
    if slotfile and not same_picture(slotfile, base + '.png'):
        slotfile = ''
    name = slot.replace('\\', '/') if slot else 'learned/' + cid
    if abs(scale / set_scale(setdir) - 1) >= 0.01:
        pic = LIB.get(os.path.join('learned', cid + '.png'), scale)
        if pic is None:
            return None
        return dict(tpl=pic[0], mask=pic[1], name=name, files=[], cid=cid, slot=slot, setdir=setdir)
    tpl, mask = load_rgb_mask(base + '.png')
    return dict(tpl=tpl, mask=mask, name=name, files=[base + '.png'] + ([slotfile] if slotfile else []), cid=cid, slot=slot, setdir=setdir)


def pictures_changed():
    """picture files were written: the folders and every resized picture are looked at again"""
    with LIB.lock:
        LIB.sets = picture_sets()
        LIB.cache.clear()
    LEARNED_OK.clear()
    with TPL_LOCK:
        TPL_FFT.clear()
        globals()['TPL_BYTES'] = 0


def refine(pic, diff):
    """the pixels that differ in this copy go see-through in the learned picture (and its slot's copy) -
    unless too little would be left to tell the card apart. True if it wrote them"""
    if not pic['files'] or diff is None:
        return False
    tpl, mask = pic['tpl'], pic['mask']
    keep = mask & (diff <= LIKE_PIXEL)
    # (a copy this different is another size - or another card - not a shimmer: one copy takes away at most half
    # of what's solid, and a quarter of the picture always stays. 2026-10-21: a 1.121 picture compared with 1.144
    # cards lost 336 of its 418 pixels at once and never matched the card again)
    gone = int(mask.sum() - keep.sum())
    if gone == 0:
        return False
    if gone > REFINE_MOST * mask.sum():
        if time.time() - REFINE_SAID.get(pic['name'], 0) > 600:
            REFINE_SAID[pic['name']] = time.time()
            log(f"  {pic['name']}: not made see-through - {gone} of its {int(mask.sum())} pixels differ in this copy (another size or card, not a shimmer)")
        return False
    if keep.sum() < max(12, REFINE_KEEP * keep.size):
        return False
    out = tpl.astype(np.uint8).copy()
    out[~keep] = (255, 0, 255)
    for f in pic['files']:
        if os.path.exists(f):
            Image.fromarray(out).save(f)
    pictures_changed()
    log(f"  {pic['name']}: {int(mask.sum() - keep.sum())} pixels that differ between copies made see-through ({int(keep.sum())} of {keep.size} left)")
    return True


def cut_here(art, pic, here):
    """a learned card seen at a UI size it wasn't learned at: this copy (art, as big as its resized
    picture) saved into the picture set for this size, here - as its learned picture, and as its slot's if
    that set has none. True if the slot's picture was written"""
    dest = os.path.join(ROOT, here)
    os.makedirs(os.path.join(dest, 'learned'), exist_ok=True)
    a = Image.fromarray(np.clip(art, 0, 255).astype(np.uint8))
    for ext in ('.png', '.raw.png'):
        a.save(os.path.join(dest, 'learned', pic['cid'] + ext))
    slot_done = False
    if pic['slot'] and not os.path.exists(os.path.join(dest, pic['slot'] + '.png')):
        os.makedirs(os.path.dirname(os.path.join(dest, pic['slot'] + '.png')), exist_ok=True)
        for ext in ('.png', '.raw.png'):
            a.save(os.path.join(dest, pic['slot'] + ext))
        slot_done = True
    pictures_changed()
    log(f"  {pic['name']}: learned at another UI size - this copy cut into {here}" + (f" (and as {pic['slot']})" if slot_done else ''))
    return slot_done


def cut_card(left, top, scale, out, file=None):
    """saves the card whose top left is at left, top (screen): see /cut. (True, card_feats), or (False,
    card_feats) with nothing saved when the box isn't a card"""
    cw, ch = CARD_W * scale, CARD_H * scale
    # (room round the card for the type icon's search, as in the hand)
    pad = round(8 * scale)
    gx1, gy1 = int(left) - pad, int(top) - pad
    img = grab(gx1, gy1, int(round(left + cw)) + pad, int(round(top + ch)) + pad, file)
    lx, ly = left - gx1, top - gy1
    f = card_feats(img, scale, lx, ly, read_icon(img, scale, lx, ly)[1])
    if not is_real(f):
        return False, f
    os.makedirs(os.path.dirname(out), exist_ok=True)
    save = lambda a, p: Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(p)
    ax1, ay1, ax2, ay2 = box(ART_BOX, scale, lx, ly)
    save(img[ay1:ay2, ax1:ax2], out + '.png')
    save(img[ay1:ay2, ax1:ax2], out + '.raw.png')
    save(img[pad:pad + int(round(ch)), pad:pad + int(round(cw))], out + '.card.png')
    ix1, iy1, ix2, iy2 = box(ICON_BOX, scale, lx, ly)
    save(img[iy1 - 1:iy2 + 2, ix1 - 1:ix2 + 2], out + '.icon.png')
    dx1, dy1, dx2, dy2 = box(DIGIT_BOX, scale, lx, ly)
    save(img[dy1:dy2, dx1:dx2], out + '.pips.png')
    return True, f


def card_check(file, scale=''):
    """/cardcheck: a saved .card.png (whole card, top left at 0, 0) looked at as /hand looks at a card:
    "real|tc|eTxt|pipYel|white|iconD|icon|pips|pipscore", or "fail <why>" - never an error"""
    try:
        if not file:
            return 'fail no file given'
        p = file if os.path.isabs(file) else os.path.join(ROOT, file)
        if not inside_root(p):
            return 'fail the file must be in ' + ROOT
        if not os.path.isfile(p):
            return 'fail no such file'
        try:
            img = np.asarray(Image.open(p).convert('RGB')).astype(np.float32)
        except OSError:
            return "fail can't read the picture"
        H, W = img.shape[:2]
        if W < 20 or H < 30:
            return f'fail too small ({W}x{H})'
        # (the scale it was cut at; a .card.png is CARD_W x CARD_H at that scale, so its width says it too)
        by_w = W / CARD_W
        try:
            sc = float(scale)
        except ValueError:
            sc = 0.0
        if not (0.3 <= sc <= 4) or abs(sc / by_w - 1) > 0.05:
            if sc:
                log(f'/cardcheck {os.path.basename(p)}: scale {scale} but {W} px wide - {by_w:.3f} used')
            sc = by_w
        kind, kd = read_icon(img, sc, 0, 0)
        f = card_feats(img, sc, 0, 0, kd)
        dx1, dy1, dx2, dy2 = box(DIGIT_BOX, sc, 0, 0)
        pips, ps = read_digit(img[max(0, dy1):dy2, max(0, dx1):dx2], digit_masks(sc))
        return (f"{int(is_real(f))}|{f['tc']}|{f['eTxt']:.3f}|{f['pipYel']:.3f}|{f['white']:.3f}|{f['iconD']:.1f}|"
                f"{kind}|{pips}|{ps:.2f}")
    except Exception as e:  # noqa: BLE001 - answered, never counted as the helper failing
        return 'fail ' + repr(e).replace('\n', ' ')


# ---------------------------------------------------------------- the health and mana globes

# Where the numbers on the globes are, in UI-scale-1 pixels from the game's bottom left: (x, how far up
# their top is, w, h) - measured at UI 1.144 / 1440p
GLOBE_HEALTH = (24.0, 131.0, 100.0, 34.0)
# (mana from x 103, not 118: a three-figure mana - 370, 408 - starts left of where a two-figure one does, and its first
# figure was cut off - "no mana? ... the mana globe's number can't be read", 2026-10-23)
GLOBE_MANA = (103.0, 92.0, 66.0, 30.0)
# a digit is the cut one it's closest to, if under this (mean pixel difference at 10 x 14, plus half the
# width/height ratio's difference); saved shots: right 0-0.2, wrong 0.3+
GLOBE_DIGIT = 0.3
GLOBE_NORM = (10, 14)


def globe_digits():
    """the cut globe digits: [(digit, normalised picture, width/height)]"""
    out = []
    for d, sc in LIB.sets:
        for p in sorted(glob.glob(os.path.join(d, 'globedigits', '*.png'))):
            m = np.asarray(Image.open(p).convert('L')) > 127
            if m.any():
                out.append((os.path.basename(p)[0], np.asarray(Image.fromarray(m.astype(np.uint8) * 255).resize(GLOBE_NORM, Image.BILINEAR)) / 255.0, m.shape[1] / m.shape[0]))
    return out


def read_number(a, cut):
    """the yellow number in picture a ("" if a digit isn't clear): digits split by empty columns"""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = (r > 190) & (g > 0.82 * r) & (b < 0.55 * r)
    cols = m.any(axis=0)
    spans, x = [], 0
    while x < m.shape[1]:
        if not cols[x]:
            x += 1
            continue
        s = x
        while x < m.shape[1] and cols[x]:
            x += 1
        ys = np.nonzero(m[:, s:x].any(axis=1))[0]
        spans.append((s, x, ys.min(), ys.max()))
    # (each kept to the rows the digits share - the mana globe's yellow glow under the health's last figure joins it,
    # 33 rows against 28: 5926 wasn't read, 2026-10-18. The rows from the digit-tall ones, two or more of them)
    tall = [sp for sp in spans if 0.3 * m.shape[0] <= sp[3] - sp[2] + 1 < m.shape[0] - 1]
    top = int(np.median([sp[2] for sp in tall])) if len(tall) >= 2 else 0
    bottom = int(np.median([sp[3] for sp in tall])) if len(tall) >= 2 else m.shape[0] - 1
    text = ''
    for s, x, y1, y2 in spans:
        blob = m[:, s:x]
        if len(tall) >= 2:
            blob = blob[max(y1, top):min(y2, bottom) + 1]
            if not blob.size or not blob.any():
                continue
        ys = np.nonzero(blob.any(axis=1))[0]
        blob = blob[ys.min():ys.max() + 1]
        # (specks of the background, and anything as tall as the whole box isn't a digit)
        if blob.shape[0] < 0.3 * m.shape[0] or blob.sum() < 8 or blob.shape[0] >= m.shape[0] - 1:
            continue
        n = np.asarray(Image.fromarray(blob.astype(np.uint8) * 255).resize(GLOBE_NORM, Image.BILINEAR)) / 255.0
        ar = blob.shape[1] / blob.shape[0]
        best = min(((np.abs(n - t).mean() + abs(ar - tar) * 0.5, d) for d, t, tar in cut), default=(9, ''))
        if best[0] >= GLOBE_DIGIT:
            return ''
        text += best[1]
    return text if 0 < len(text) <= 5 else ''


def read_globes(left, bottom, scale, file=None):
    """(health, mana) off the globes ("" for one that can't be read)"""
    cut = globe_digits()
    out = []
    for gx, gtop, gw, gh in (GLOBE_HEALTH, GLOBE_MANA):
        x1, y1 = int(round(left + gx * scale)), int(round(bottom - gtop * scale))
        x2, y2 = int(round(left + (gx + gw) * scale)), int(round(bottom - (gtop - gh) * scale))
        out.append(read_number(grab(x1, y1, x2, y2, file).astype(int), cut))
    return out


# ---------------------------------------------------------------- the name plates' health numbers

# Windows' OCR misses the plates' red numbers more often than not at 1440p (2026-10-23: 1 of 48 sizes and boxes read
# 2,848/3,153, and a comma comes back as "r"). They're one bold font, so they're read by shape: the red ink (the
# numbers' pure red, as KillCalc.ahk HealthGlyphs), the commas (short ink sitting on the line) set aside, and the line
# cut into the windows that cost least - a window costs the pixels it doesn't share with the cut digit or "/" it's
# likest (both at 10 x 14, plus its width/height ratio's difference) plus PLATE_GLYPH*H*H a glyph; a column left out
# costs its ink. Taller than the digits' band: a "/" (the digits never are). Read for sure: every glyph under
# PLATE_WORST, one "/", and the commas where a thousands mark goes. The cut pictures are each glyph's band rows (cut at
# 1440p, UI 1.144, H 15: they read 1280x1024's H 11 too)
PLATE_NORM = (10, 14)
PLATE_GLYPH = 0.05
PLATE_WORST = 0.3
PLATE_CACHE = {}


def plate_ink(a):
    """the numbers' pure red (not a school icon's orange-red: its green well above its blue)"""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (r > 110) & (g < 45) & (b < 45) & (r - g > 80) & (g - b < 18)


def ink_runs(m):
    """runs of inked columns: [(first, last)]"""
    cols = np.concatenate([[False], m.any(axis=0), [False]]).astype(np.int8)
    d = np.diff(cols)
    return list(zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0] - 1))


def area_matrix(n, k):
    """k x n: each of k cells the mean of its share of n pixels (a box filter - the same for the cut pictures and
    the line's windows)"""
    m = np.zeros((k, n))
    for i in range(k):
        a, b = i * n / k, (i + 1) * n / k
        for j in range(int(a), min(n, int(np.ceil(b)))):
            m[i, j] = min(b, j + 1) - max(a, j)
        m[i] /= max(1e-9, m[i].sum())
    return m


def plate_digits():
    """the cut plate glyphs: (chars, their pictures at PLATE_NORM as rows, their width/height ratios) - each picture
    a band of one glyph, ink white; <digit>_<n>.png or slash_<n>.png"""
    key = tuple(d for d, sc in LIB.sets)
    if key in PLATE_CACHE:
        return PLATE_CACHE[key]
    cw, ch = PLATE_NORM
    chars, pics, ratios = [], [], []
    for d, sc in LIB.sets:
        for p in sorted(glob.glob(os.path.join(d, 'platedigits', '*.png'))):
            name = os.path.basename(p)
            c = '/' if name.lower().startswith('slash') else name[0]
            try:
                m = np.asarray(Image.open(p).convert('L')) > 127
            except OSError:
                continue
            if c not in '0123456789/' or not m.any():
                continue
            chars.append(c)
            pics.append((area_matrix(m.shape[0], ch) @ m.astype(float) @ area_matrix(m.shape[1], cw).T).ravel())
            ratios.append(m.shape[1] / m.shape[0])
    out = (chars, np.array(pics).reshape(len(pics), cw * ch), np.array(ratios))
    PLATE_CACHE[key] = out
    return out


def read_plate(a, cut):
    """(cur, max, worst glyph's distance) of the red health numbers in picture a, or (None, None, why)"""
    chars, pics, ratios = cut
    if not chars:
        return None, None, 'no cut plate digits (platedigits)'
    if not {'/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'} <= set(chars):
        return None, None, 'the cut plate digits are missing ' + ''.join(sorted(set('/0123456789') - set(chars)))
    m = plate_ink(a)
    runs = ink_runs(m)
    tops, bottoms = [], []
    for s, e in runs:
        ys = np.nonzero(m[:, s:e + 1].any(axis=1))[0]
        if ys[-1] - ys[0] >= 7:
            tops.append(ys[0])
            bottoms.append(ys[-1])
    if not tops:
        return None, None, 'no red numbers'
    t, b = int(np.median(tops)), int(np.median(bottoms))
    H = b - t + 1
    if H < 8:
        return None, None, f'too small ({H} px)'
    # (only the line's own rows from here: red under it - the school badge, the pips - would join a comma to its digits)
    r0, r1 = max(0, t - int(np.ceil(0.3 * H))), min(m.shape[0], b + int(np.ceil(0.45 * H)) + 1)
    m, t, b = m[r0:r1], t - r0, b - r0
    if H > 0.75 * a.shape[0]:
        return None, None, f'too tall ({H} px)'
    # (red on the line at the box's edge: a glyph cut by the box - a first digit lost reads 848 for 2,848, and no comma
    # check can tell; the bot's boxes leave room either side)
    edge = int(np.ceil(0.5 * H))
    if m[t:b + 1, :edge].any() or m[t:b + 1, -edge:].any():
        return None, None, 'red at the box edge (a glyph cut)'
    runs = ink_runs(m)
    # (commas - short ink sitting on the line - set aside, where they are kept)
    mm, commas = m.copy(), []
    for s, e in runs:
        ys = np.nonzero(m[:, s:e + 1].any(axis=1))[0]
        if ys[-1] - ys[0] + 1 < 0.6 * H and ys[0] > t + 0.5 * H and e - s + 1 <= 0.45 * H:
            mm[:, s:e + 1] = False
            commas.append((s + e) / 2)
    band, W = mm[t:b + 1].astype(float), mm.shape[1]
    colink = band.sum(axis=0)
    beyond = mm[:t].sum(axis=0) + mm[b + 1:].sum(axis=0)
    cw, ch = PLATE_NORM
    # (the rows' box filter once - each window then only its columns': H out of the windows' sums)
    rows = area_matrix(H, ch) @ band                                                # (14, W)
    lo, hi = max(3, int(0.3 * H)), int(1.0 * H)
    # cost[(x, w)] = (cost, char, distance) of the likeliest glyph in the window x..x+w-1
    best_at = {}
    slash = np.array([c == '/' for c in chars])
    for w in range(lo, hi + 1):
        if w > W:
            break
        rx = area_matrix(w, cw)
        ink_n = np.convolve(colink, np.ones(w), 'valid')                          # (W-w+1,)
        wins = np.lib.stride_tricks.sliding_window_view(rows, w, axis=1)          # (14, W-w+1, w)
        canon = np.einsum('inw,jw->nij', wins, rx).reshape(-1, cw * ch)           # (W-w+1, 140)
        d = np.abs(canon[:, None, :] - pics[None, :, :]).mean(axis=2) + 0.6 * np.abs(w / H - ratios)[None, :]
        ext = np.convolve(beyond, np.ones(w), 'valid')                             # ink above/below the band
        cost = d * w * H + PLATE_GLYPH * H * H
        cost += np.where(slash[None, :], np.where(ext[:, None] == 0, 0.15 * w * H, 0), ext[:, None])
        k = np.argmin(cost, axis=1)
        for x in np.nonzero(ink_n > 0)[0]:
            best_at[(int(x), w)] = (float(cost[x, k[x]]), chars[k[x]], float(d[x, k[x]]))
    INF = float('inf')
    best, back = [0.0] + [INF] * W, [None] * (W + 1)
    for x in range(W):
        if best[x] == INF:
            continue
        s = best[x] + colink[x] + beyond[x]
        if s < best[x + 1]:
            best[x + 1], back[x + 1] = s, (x, None, 0.0)
        for w in range(lo, hi + 1):
            g = best_at.get((x, w))
            if g and best[x] + g[0] < best[x + w]:
                best[x + w], back[x + w] = best[x] + g[0], (x, g[1], g[2])
    glyphs, x = [], W
    while x > 0:
        px, c, dd = back[x]
        if c:
            glyphs.append((px, x - 1, c, dd))
        x = px
    glyphs.reverse()
    if not glyphs:
        return None, None, 'no glyphs'
    text = ''.join(g[2] for g in glyphs)
    worst = max(g[3] for g in glyphs)
    if worst >= PLATE_WORST:
        return None, None, f'"{text}" not clear (a glyph {worst:.2f} off)'
    mt = re.fullmatch(r'([1-9]\d{0,5}|0)/([1-9]\d{0,5})', text)
    if not mt:
        return None, None, f'"{text}" is no cur/max'
    # (the commas where thousands marks go, and nowhere else: a digit dropped or added shows)
    slash_i = text.index('/')
    for part, first in ((mt.group(1), 0), (mt.group(2), slash_i + 1)):
        want = {first + len(part) - 3 * k for k in range(1, (len(part) - 1) // 3 + 1)}   # glyph index after each mark
        for k in range(first + 1, first + len(part)):
            gap = (glyphs[k - 1][1] + glyphs[k][0]) / 2
            has = any(glyphs[k - 1][1] - 1 <= c <= glyphs[k][0] + 1 for c in commas)
            if has != (k in want):
                return None, None, f'"{text}": a comma {"missing" if k in want else "where none goes"} at {gap:.0f}'
    cur, most = int(mt.group(1)), int(mt.group(2))
    if cur > most:
        return None, None, f'"{text}": more than its most'
    return cur, most, worst


def plate_health(x1, y1, x2, y2, file=None):
    """/plate: (cur, max, worst) or (None, None, why)"""
    if x2 - x1 < 8 or y2 - y1 < 8 or x2 - x1 > 1200 or y2 - y1 > 200:
        return None, None, 'a box of no use'
    return read_plate(grab(x1, y1, x2, y2, file).astype(int), plate_digits())


# ---------------------------------------------------------------- enemy spells (enemies.py)
ENEMY = {'wiki': None, 'casts': None, 'battle': None, 'key': None}


def enemy_state():
    """the wiki's data and the casts seen (AutoFarmer\\wiki), made on first use"""
    if ENEMY['wiki'] is None:
        import enemies
        folder = os.path.join(ROOT, 'wiki')
        ENEMY['wiki'], ENEMY['casts'] = enemies.Wiki(folder, log=log), enemies.Casts(folder, log=log)
    return ENEMY['wiki'], ENEMY['casts']


def enemy_lines(names, rnd, health, team, hist):
    """/enemies: round rnd's prediction for the enemies names (in their slots' order), worked out afresh from the
    battle's casts so far - hist: {round: {enemy index: the game log's spell name}} - with team wizards on your side"""
    import enemies
    wiki, casts = enemy_state()
    b = enemies.Battle(wiki, casts, names, team)
    seen = {}
    for r, d in hist.items():
        for i, raw in d.items():
            if 0 <= i < len(names):
                c = wiki.creature(names[i]) or {}
                seen.setdefault(r, {})[i] = enemies.clean_spell(raw, c.get('spells', ())) or None
    b.step(max(1, rnd), seen)
    pred, lethal = b.predict(health or None)

    def bare(s):
        return str(s or '').replace('|', ' ').replace(';', ' ').replace(':', ' ')

    def n(x):
        return '' if x is None else f'{x:g}'

    lines = []
    for i, e in enumerate(pred):
        c = wiki.creature(e['name'])
        state = 'pending' if c is None else ('missing' if c.get('missing') else 'ok')
        top = ';'.join(f"{bare(s)}:{p:.2f}:{bare(br)}" for s, p, br in e['top'])
        # (9-12, the dashboard's Cards tab: its school, rank and health off the wiki; every spell of it -
        # spell:chance:brief:seen before (weighed):rounds it cast it this battle (r/r) - likeliest first, a pass among
        # them, a spell it cast this battle that its wiki page hasn't added at 0)
        mine = {}
        for r in sorted(seen):
            if i in seen[r]:
                mine.setdefault(seen[r][i] or 'pass', []).append(str(r))
        deck = list(e['deck'])
        extra = [s for s in mine if not any(d[0] == s for d in deck)]
        if extra:
            before = b._seen(e['name'], (c or {}).get('spells', ()))
            before['pass'] = float(casts.counts(e['name']).get('_pass', 0))
            for s in extra:
                deck.append((s, 0.0, wiki.brief(s) if wiki.spell(s) else '', before.get(s, 0.0)))
        cs = c if state == 'ok' else {}
        cards = ';'.join(f"{bare(s)}:{p:.2f}:{bare(br)}:{w:g}:{'/'.join(mine.get(s, []))}" for s, p, br, w in deck)
        lines.append(f"enemy|{i}|{e['name']}|{state}|{e['pips']:.1f}|{e['hit']:.2f}|{e['max']}|{top}"
                     f"|{bare(cs.get('school'))}|{n(cs.get('rank'))}|{n(cs.get('health'))}|{cards}")
    lines.append('lethal|' + ('' if lethal is None else f'{lethal:.2f}'))
    return lines


def enemy_seen(name, raw, rnd=0):
    """/enemyseen: one enemy's cast at round rnd, off the game's log (raw: its spell name there, None for a pass) -
    counted for its creature under the wiki's name for it, weighed 1 / the chance (the plain model's) it could afford it
    then: the model's own "can't afford it, so it passes" isn't counted twice. The name counted ('' a pass)"""
    import enemies
    wiki, casts = enemy_state()
    c = wiki.creature(name) or {}
    s = enemies.clean_spell(raw, c.get('spells', ()))
    weight = 1.0
    if s and c.get('spells') and rnd >= 1:
        b = enemies.Battle(wiki, enemies.NoCasts(), [name])
        b.step(rnd)
        weight = 1.0 / max(0.1, b.afford(0, enemies.Battle._cost(wiki.spell(s) or {})))
    casts.add(name, s, weight)
    return s


# ---------------------------------------------------------------- quest markers over NPCs
# An NPC a quest has something for wears a marker over its head: a gold "?" (or "!") in a red swirl, its name in bright
# green under it (measured 2026-10-22 at 2560x1440, UI 1.144: Shalek the Wise's - gold 56x83 px with its dot, the red
# swirl round it, the name's green letters right under). Found by colour: gold blobs (the hook and dot merged) with red
# round them; the green under one is its name - its rectangle sent back for the walker to read (Windows OCR)
QM_GOLD_MIN = 30        # a marker: at least 4 times this many gold pixels (one about 12 px tall on the screen at the least)


def _qm_blobs(mask):
    """the 8-connected blobs of a small boolean mask: [(count, y1, x1, y2, x2)]"""
    pts = set(map(tuple, np.argwhere(mask)))
    out = []
    while pts:
        seed = pts.pop()
        stack, n, y1, x1, y2, x2 = [seed], 0, seed[0], seed[1], seed[0], seed[1]
        while stack:
            y, x = stack.pop()
            n += 1
            y1, x1, y2, x2 = min(y1, y), min(x1, x), max(y2, y), max(x2, x)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    q = (y + dy, x + dx)
                    if q in pts:
                        pts.remove(q)
                        stack.append(q)
        out.append((n, y1, x1, y2, x2))
    return out


def find_qmarks(x1, y1, x2, y2, file=None):
    """the quest markers in the rectangle: [{'kind': '?' or '!', 'x', 'y', 'w', 'h' (the gold, screen pixels),
    'label': (x, y, w, h) of the green name under it, or None}], biggest first. kind: the gold's top part wide (a "?"'s
    hook) or narrow (a "!"'s bar)"""
    a = grab(x1, y1, x2, y2, file)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    gold = (R >= 200) & (G >= 150) & (B <= 110) & (R - B >= 110) & (G - B >= 70)
    red = (R >= 160) & (G <= 80) & (B <= 80)
    green = (G >= 180) & (R <= 150) & (B <= 150) & (G - R >= 80) & (G - B >= 80)
    # (in 4 x 4 blocks - any gold in one counts - grown a block: the "?"'s dot joins its hook; a quarter the size, the
    # blobs found quickly)
    hq, wq = gold.shape[0] // 4, gold.shape[1] // 4
    g4 = gold[:hq * 4, :wq * 4].reshape(hq, 4, wq, 4).any(axis=(1, 3))
    pad = np.pad(g4, 1)
    grown = np.zeros_like(g4)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            grown |= pad[dy:dy + hq, dx:dx + wq]
    out = []
    for n, by1, bx1, by2, bx2 in _qm_blobs(grown):
        gy1, gx1, gy2, gx2 = by1 * 4, bx1 * 4, by2 * 4 + 4, bx2 * 4 + 4
        gh, gw = gy2 - gy1, gx2 - gx1
        if gh < 12 or gh > 400 or gw > 3 * gh or gh > 3 * gw + 20:
            continue
        cnt = int(gold[gy1:gy2, gx1:gx2].sum())
        if cnt < QM_GOLD_MIN * 4:
            continue
        # (its red swirl: round the gold, half its size again each way)
        ry1, ry2 = max(0, gy1 - gh // 2), min(a.shape[0], gy2 + gh // 2)
        rx1, rx2 = max(0, gx1 - gw // 2), min(a.shape[1], gx2 + gw // 2)
        if red[ry1:ry2, rx1:rx2].sum() < 0.25 * cnt:
            continue
        # (a "?": its top half's gold spans most of its height across; a "!": a narrow bar)
        top = gold[gy1:gy1 + gh // 2, gx1:gx2]
        cols = np.nonzero(top.any(axis=0))[0]
        span = (cols[-1] - cols[0] + 1) if len(cols) else 0
        # (cut off at the top of the rectangle - an NPC at talk range: its top half isn't the hook - a "?")
        kind = '?' if by1 == 0 or span >= 0.45 * gh else '!'
        # (its name: green letters under it, starting within half its height, up to its height down, 5 times its
        # width either side)
        ly1, ly2 = gy2, min(a.shape[0], gy2 + max(gh, 30))
        lx1, lx2 = max(0, (gx1 + gx2) // 2 - 5 * max(gw, 20)), min(a.shape[1], (gx1 + gx2) // 2 + 5 * max(gw, 20))
        gm = green[ly1:ly2, lx1:lx2]
        label = None
        if gm.sum() >= 40:
            ys, xs = np.nonzero(gm)
            if ys.min() <= gh // 2 + 6:
                label = (x1 + lx1 + int(xs.min()) - 4, y1 + ly1 + int(ys.min()) - 4,
                         int(xs.max() - xs.min()) + 9, int(ys.max() - ys.min()) + 9)
        out.append({'kind': kind, 'x': x1 + gx1, 'y': y1 + gy1, 'w': gw, 'h': gh, 'label': label, 'gold': cnt})
    out.sort(key=lambda m: -m['h'])
    return out


# ---------------------------------------------------------------- walking: the game's memory and the zone map

# Where the wizard and the quest goal are comes from the game's memory, read-only (vision\navmem.py: it opens
# the game with PROCESS_VM_READ | PROCESS_QUERY_INFORMATION and only ever calls ReadProcessMemory on it); the
# zone's floor, obstacles and nav graph from its .wad (vision\navgeo.py). Both are imported on the first
# /nav or /navmap, so nothing else here depends on them
NAV = None
NAV_LOCK = threading.Lock()
NAV_SPAN = 6000.0           # /navmap: game units across the picture's shorter side
NAV_TILE = 256              # the static layers are drawn in tiles this many pixels square, kept per zone and scale
NAV_SS = 2                  # drawn this many times bigger, then shrunk (smooth edges)
NAV_TILES_KEPT = 64         # tiles kept, all zones (64 x 192 KB)
NAV_ZONES_KEPT = 3
# colours, to sit on the dashboard (1B1D22 / 111317, accent 8AB4F8)
MAP_BG = (17, 19, 23)
MAP_FLOOR = (44, 48, 56)
MAP_FLOOR_LOW = (34, 38, 46)        # (the floor's grey shading by height, before the colours below)
MAP_FLOOR_HIGH = (104, 112, 130)
# the floor coloured by height as maps are: blue (the zone's lowest, cold) through cyan, green and yellow to red (its
# highest, hot) - muted, so the route, mobs and markers drawn over it stand out (you asked, 2026-10-23)
MAP_HEIGHT_STOPS = (0.0, 0.25, 0.5, 0.75, 1.0)
MAP_HEIGHT_RGB = ((38, 64, 140), (34, 112, 142), (52, 124, 72), (148, 138, 50), (150, 56, 46))
MAP_RIM = (72, 78, 90)
MAP_WATER = (28, 52, 74)
MAP_OBST = (204, 112, 74)
MAP_NAV = (138, 180, 248)
MAP_PATH = (138, 180, 248)
MAP_TARGET = (242, 193, 78)
MAP_GOAL = (123, 216, 143)
MAP_ROUTE = (110, 231, 183)
MAP_DOOR = (197, 138, 249)
MAP_ME = (242, 242, 242)
MAP_TEXT = (154, 160, 166)
MAP_MOB = (240, 82, 82)             # a mob kept away from
MAP_MOB_QUEST = (245, 166, 35)      # ...one the quest is about (walked to)
MAP_ITEM = (120, 200, 140)          # a thing lying about the zone a quest has you collect
MAP_ITEM_QUEST = (60, 235, 110)     # ...one the goal wants (walked to and picked up)
ITEMS_SHOWN = {}                    # the walker's last /items: {'quest': {gids}, 'at': time} - for the map
QUEST_NEAR = 400.0                  # a mob this near the quest's goal (in this zone) is what the goal is
MOBS_SHOWN = {}                     # the last /nav's split, for the map: {'quest': {gids}, 'near': mob radius, 'at': time}
DUELS_SHOWN = {}                    # the last /nav's other players' battles kept out of, for the map: {'list', 'at'}
MAP_DUEL = (186, 120, 255)          # another player's battle kept out of (duelavoid)
MAP_WALL = (240, 82, 82)            # a line of mobs' gaps closed (a wall)
OV_FLOOR_A, OV_WATER_A, OV_RIM_A = 120, 110, 170   # the overlay map's (clear) floor, water and rim alpha
OV_UNIT_DIV = 170   # its markers and names one size bigger than the dashboard's /240
OV_TILES_KEPT = 36  # its RGBA tiles kept (256 KB each) - or one picture's, if more (render_navmap)


# ---------------------------------------------------------------- the Network tab (netmon.py)
NETMON = None


def netmon():
    """this PC's part of the Network tab, made on first use (its sockets open only while it's on - Settings: neton)"""
    global NETMON
    if NETMON is None:
        import netmon as netmon_mod
        NETMON = netmon_mod.NetMon(grab_screen, os.path.join(ROOT, 'debug.log'), log=log)
    return NETMON


# ---------------------------------------------------------------- party (party.py)
PARTY = None


def party():
    """this PC's part of the party, made on first use (its thread reads the wizard's place only while the party's on)"""
    global PARTY
    if PARTY is None:
        import party as party_mod

        def read():
            # (navmem's read() answers (reading, why): the reading - the pair itself, taken for one, failed on .get several
            # times a second all of 2026-10-25's evening, and the party never had the wizard's place)
            try:
                r, _why = nav_reader().read(path=False, wait=0.2)
                return r
            except Exception:  # noqa: BLE001 - no game, no place
                return None
        PARTY = party_mod.Party(read, log=log)
    return PARTY


def partyorder_answer(q):
    """/partyorder (partyorders - TODO goal 3, advice only; this helper's own server, never the LAN): ?tag= - the
    follower's: the leader's card for its hand (party.py order_line); ?lead=1 - the leader's: lead|<followers' fresh
    hands held> (lead_count); ?noplan=<round> - the leader's at its round's end: noplan|<followers told the round wasn't
    planned> (no_plan - the round the battle recorder's, else the one given). Never raises"""
    try:
        if 'lead' in q:
            return 'lead|%d' % (PARTY.lead_count() if PARTY is not None else 0)
        if 'noplan' in q:
            v = str(q.get('noplan') or '').strip()
            if PARTY is None or not re.fullmatch(r'\d{1,3}', v):
                return 'noplan|0'
            loc = rec_local()
            return 'noplan|%d' % PARTY.no_plan(loc[1] if loc else int(v))
        if PARTY is None:
            import party as party_mod
            return party_mod.order_cells('none', why="the party isn't on in this helper")
        return PARTY.order_line(q.get('tag', ''))
    except Exception as e:  # noqa: BLE001 - never into the server
        why = "the party couldn't be asked (%s)" % re.sub(r'[|\r\n]+', ' ', repr(e))
        return '|'.join(['order', 'none'] + [''] * 8 + [why])


def party_stop():
    if PARTY is not None:
        PARTY.stop()
    if NETMON is not None:
        NETMON.stop()
    if REC is not None:
        try:
            REC.stop()          # (the battle in progress kept in learned\battles\current.json)
        except Exception:  # noqa: BLE001
            pass


def nav_reader():
    global NAV
    with NAV_LOCK:
        if NAV is None:
            import navmem
            NAV = navmem.NavMem(log=log)
        return NAV


CARDS_LOGGED = {'text': None}


def cards_answer(q=None):
    """/cards with no rectangle: the hand and my pips from the game's memory (navmem's reader, read-only -
    vision\\handmem.py), logged when the answer changes. ptag=d<duel>r<round> (partyorders, a follower's bot): the hand
    also kept for the party's leader (party.py saw_hand - the round the battle recorder's: rec_local)"""
    import handmem
    r, why = nav_reader().cards()
    _rec_hook('saw_hand', r)
    if (q or {}).get('ptag') and PARTY is not None:
        try:
            PARTY.saw_hand(r, q['ptag'], rec_local())
        except Exception:  # noqa: BLE001 - the answer as it is
            pass
    text = handmem.answer(r, why)
    # (logged when the cards change - not their boxes, fields 26-29, nor the root line: a card zoomed up or the hand
    # sliding back isn't a new hand)
    key = '\n'.join('|'.join(ln.split('|')[:25]) for ln in text.split('\n') if not ln.startswith(('hand|', 'root|')))
    if key != CARDS_LOGGED['text']:
        CARDS_LOGGED['text'] = key
        if text.startswith('none|'):
            log('/cards (memory): ' + text)
        else:
            cards = [ln.split('|') for ln in text.split('\n') if ln.startswith('card|')]
            log(f"/cards (memory) {r['ms'] if r else '?'} ms: " + text.split('\n')[0] + ' | '
                + ', '.join(f"{c[4] or c[3]} ({c[16]}{' ' + c[15] if c[15] else ''}, {c[7]} pips{' X' if c[8] == '1' else ''}"
                            f"{', tc' if c[11] == '1' else ''}{', ' + c[13] if c[13] else ''}){cards_by_school(c)}" for c in cards))
    return text


BAG_LOGGED = {'key': None}


def bag_answer():
    """/bag: the backpack from the game's memory (navmem's reader, read-only - vision\\bagmem.py) as lines, logged when
    its count, size, N/M or the tips change"""
    import bagmem
    r, why = nav_reader().bag(wait=0.3)
    lines = bagmem.bag_lines(r, why)
    key = '\n'.join(ln for ln in lines if ln.split('|')[0] in ('none', 'bag', 'space', 'tip'))
    key = re.sub(r'^(bag\|[^|]*\|[^|]*\|[^|]*\|)[^|]*\|[^|]*', r'\1', key)          # (not every gold change)
    if key != BAG_LOGGED['key']:
        BAG_LOGGED['key'] = key
        log('/bag (memory): ' + ' / '.join(ln for ln in lines if not ln.startswith(('cat|', 'set|', 'setitem|', 'crownshop|')))[:600])
    return lines


def gear_lines_for(q):
    """/gear: the gear from the game's memory (navmem's reader, read-only - vision\\gearmem.py) through gearrank.answer -
    the swap plan for the totals in q, and with run= the run's drop log in AutoFarmer\\learned\\drops (the catalogue,
    resources\\dungeons_known.txt, for a run with no slots); its gear|, plan| and run| lines logged. Never raises"""
    import gearrank
    try:
        r, why = nav_reader().gear(wait=2.0)
        known = ''
        try:
            with open(os.path.join(ROOT, 'resources', 'dungeons_known.txt'), encoding='utf-8', errors='replace') as f:
                known = f.read()
        except OSError:
            pass
        lines = gearrank.answer(r, why, q, os.path.join(ROOT, 'learned', 'drops'), known)
        log('/gear (memory): ' + ' / '.join(ln for ln in lines if ln.startswith(('gear|', 'plan|', 'run|', 'none|')))[:600])
        return lines
    except Exception as e:  # noqa: BLE001 - never into the server
        return ["none|the gear couldn't be read (%r)" % (e,)]


def cards_by_school(c):
    """a card line's heads or boosts (fields 24-25) for the log: " [fire 230 + ice 230 + storm 230]", " [blade
    ice,storm,fire 35%]", " [heads ?]"; "" none (or an older line)"""
    if len(c) > 23 and c[23]:
        return ' [heads ?]' if c[23] == '?' else ' [' + ' + '.join(h.replace(':', ' ') for h in c[23].split(',')) + ']'
    if len(c) > 24 and c[24]:
        if c[24] == '?':
            return f' [{c[16]} ?]'
        parts = [p.split(':') for p in c[24].split(',')]
        pct = sorted({p[1] for p in parts if len(p) == 2})
        return f" [{c[16]} {','.join(p[0] for p in parts)} {'/'.join(pct)}%]"
    return ''


def word_forms(w):
    """a word and its plurals: Soul / Souls, Fairy / Fairies, Wolf / Wolves, Axeman / Axemen"""
    out = {w, w + 's', w + 'es'}
    if w.endswith('y'):
        out.add(w[:-1] + 'ies')
    if w.endswith('f'):
        out.add(w[:-1] + 'ves')
    if w.endswith('man'):
        out.add(w[:-3] + 'men')
    return out


def mob_name_re(name):
    """a regex for a mob's name as a goal line writes it - any of its words plural (Lost Souls, Keepers of the Fang)"""
    words = re.sub(r'[^a-z0-9 ]', ' ', name.lower()).split()
    if not words:
        return None
    return re.compile(r'\b' + r'\s+'.join('(?:' + '|'.join(sorted(map(re.escape, word_forms(w)), key=len, reverse=True)) + ')'
                                           for w in words) + r'\b')


def mob_plural(name):
    """(kept for the tests) the whole name and its plurals"""
    return word_forms(name.lower())


FIGHT_GOAL = re.compile(r'\b(defeat|destroy|kill|hunt|vanquish|beat|fight|battle|slay|collect|gather|obtain|retrieve|recover)\b'
                        r'|\(\s*\d+\s*(of|/)\s*\d+\s*\)', re.I)


def _ocr_letters(s):
    """a name's or an OCR'd line's letters, in capitals - the OCR's usual digit-for-letter slips put right"""
    s = (s or '').upper().translate(str.maketrans('0158', 'OISB'))
    return re.sub(r'[^A-Z]', '', s)


def _approx_in(k, s, tol):
    """True if k is within s with at most tol letters added, dropped or changed (one pass: the match may start and end
    anywhere in s)"""
    prev = [0] * (len(s) + 1)
    for i, ck in enumerate(k, 1):
        cur = [i] + [0] * len(s)
        for j, cs in enumerate(s, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ck != cs))
        prev = cur
    return min(prev) <= tol


@functools.lru_cache(maxsize=1024)
def name_in_line(name, line):
    """the mob's name in an OCR'd goal line: as its words (plurals too), or - the OCR runs words together and slips a
    letter (2026-10-23: the quest's own Optio Agenor waited for as a mob on the way) - its letters within the line's,
    one slip in six letters at most (names of 5 letters or more)"""
    clean = re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9 ]', ' ', (line or '').lower()))
    rx = mob_name_re(name)
    if rx is not None and clean.strip() and rx.search(clean):
        return True
    k, L = _ocr_letters(name), _ocr_letters(line)
    if len(k) < 5 or not L:
        return False
    return k in L or _approx_in(k, L, max(1, len(k) // 6))


# Words of a mob's name that say nothing about its kind (a goal line's "Defeat the Dark ..." mustn't take every Dark one)
FAMILY_SKIP = {'the', 'of', 'and', 'lord', 'lady', 'king', 'queen', 'prince', 'princess', 'master', 'elder', 'great', 'grand',
               'young', 'old', 'dark', 'evil', 'giant', 'little', 'big', 'captain', 'chief', 'sir', 'dame', 'boss', 'mighty',
               # (ranks and titles: Optio Misemos isn't the Optio Agenor a goal names)
               'optio', 'centurion', 'decurion', 'legate', 'tribune', 'praetor', 'general', 'commander', 'sergeant', 'corporal',
               'private', 'baron', 'baroness', 'duke', 'duchess', 'count', 'countess', 'earl', 'admiral', 'colonel', 'major',
               'lieutenant', 'professor', 'doctor', 'madame', 'mister', 'father', 'mother', 'brother', 'sister', 'uncle', 'aunt'}


@functools.lru_cache(maxsize=1024)
def family_in_line(name, line):
    """one word of the mob's name - 4 letters or more, not a FAMILY_SKIP one - in the goal line as a word, plural too
    ("Gobbler Scavenger" in "Defeat Gobblers in Colossus Boulevard (0 of 4)")"""
    words = set(re.sub(r'[^a-z0-9 ]', ' ', (line or '').lower()).split())
    if not words:
        return False
    for w in re.sub(r'[^a-z0-9 ]', ' ', (name or '').lower()).split():
        if len(w) >= 4 and w not in FAMILY_SKIP and word_forms(w) & words:
            return True
    return False


@functools.lru_cache(maxsize=1024)
def name_matches(name, text):
    """the name in a clean text - the game's own words, read from its memory - as its words, plurals too ("Flame Gem" in
    "Flame Gems", "Jack O' Lantern" in "Use Jack O' Lantern ..."): no OCR slips allowed for"""
    rx = mob_name_re(name or '')
    clean = re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9 ]', ' ', (text or '').lower())).strip()
    return bool(rx is not None and clean and rx.search(clean))


# The game's goal kinds that are fights (GoalTemplate::GOAL_TYPE_*): a mob of the kind the goal names, or one by its goal,
# is the quest's too. Any other kind (USAGE collect / open / use, WAYPOINT go to, PERSONA talk to...): only a mob it names
GOAL_FIGHTS = {'BOUNTY', 'BOUNTYCOLLECT', 'COLLECTAFTERBOUNTY'}


def by_goal(m, r):
    """the mob stands by the quest's goal in this zone (a boss the arrow leads to)"""
    g = r.get('goal') if r else None
    return (g is not None and r.get('hops') == 0
            and math.hypot(m['pos'][0] - g[0], m['pos'][1] - g[1]) <= QUEST_NEAR and abs(m['pos'][2] - g[2]) <= 260)


def quest_mob(m, r, goal_line, goal=None):
    """the quest is about this mob. goal: the quest's goal from the game's memory (goal_now), when it's read - its own
    words decide, exactly: a mob, item or one to go to / talk to it names is the quest's ("Defeat Governor Nereus",
    "Go To Governor Nereus"), and - a fight goal (BOUNTY, BOUNTYCOLLECT) - a mob of the kind it names ("Gobblers" for a
    Gobbler Scavenger) or standing by its goal. Else goal_line (AutoFarmer's OCR of the screen): its name in the line
    ("Defeat 3 Lost Souls ...", OCR slips allowed for), or - the goal a fight (or no goal line read) - a mob of the kind
    the line names, or by the goal. Not a mob wandering by a "Talk to ..." goal"""
    if goal and goal.get('text'):
        if goal.get('exact'):
            if any(name_matches(m['name'], n) for n in (goal.get('mob'), goal.get('item'), goal.get('npc')) if n):
                return True
            if goal.get('type') not in GOAL_FIGHTS:
                return False
            return bool(goal.get('mob')) and family_in_line(m['name'], goal['mob']) or by_goal(m, r)
        # (the HUD's own line - the goal's names not all read: its words, exactly)
        line = goal['text']
        if name_matches(m['name'], line):
            return True
        if not FIGHT_GOAL.search(line):
            return False
        return family_in_line(m['name'], line) or by_goal(m, r)
    if goal_line and name_in_line(m['name'], goal_line):
        return True
    if goal_line and not FIGHT_GOAL.search(goal_line):
        return False
    # (a fight goal naming the mob's kind, not its whole name - "Defeat Gobblers" for a Gobbler Scavenger: 2026-10-24
    # the wizard waited and backed away from the very mobs its quest wanted)
    if goal_line and family_in_line(m['name'], goal_line):
        return True
    return by_goal(m, r)


def quest_named(m, r, goal_line, goal=None):
    """quest_mob without the family match: the quest's goal names this mob (its name, as quest_mob reads it), or - a
    fight goal (or no goal line read) - it stands by the goal. /mobs' field 15, for the boss deck's "the walker goes to
    it" (AutoFarmer's Decks.ahk): a "Gobbler King" anywhere in the zone is quest_mob's for "Defeat Gobblers", not this"""
    if goal and goal.get('text'):
        if goal.get('exact'):
            if any(name_matches(m['name'], n) for n in (goal.get('mob'), goal.get('item'), goal.get('npc')) if n):
                return True
            return bool(goal.get('type') in GOAL_FIGHTS and by_goal(m, r))
        line = goal['text']
        return bool(name_matches(m['name'], line) or (FIGHT_GOAL.search(line) and by_goal(m, r)))
    if goal_line:
        if name_in_line(m['name'], goal_line):
            return True
        if not FIGHT_GOAL.search(goal_line):
            return False
    return bool(by_goal(m, r))


TITLES_SAID = set()         # the bosses and elites logged (their gids)


def mobs_now(r, goal_line='', trail=False, goal=None):
    """(the zone's mobs [{name, pos, yaw, gid, template, quest, named, title, title_id, rank, health, school, boss,
    kind}], why) - none ([], why) when they can't be read. trail: the reading goes on MOB_TRAIL too (the walker's route
    asks); goal: the memory's goal (goal_now) - goal_line (the OCR's) only without it. named: the quest's by its name or
    its goal only (quest_named - no family match). title...kind: navmem's (bossmem.py - None while not known)"""
    mobs, why = nav_reader().mobs()
    if mobs is None:
        return [], why
    for m in mobs:
        m['quest'] = quest_mob(m, r, goal_line, goal)
        m['named'] = quest_named(m, r, goal_line, goal) if m['quest'] else False
        # (a boss or an elite in the zone: in the log once each - its title, rank and health from the game's memory)
        if m.get('kind') in ('boss', 'elite') and m['gid'] not in TITLES_SAID:
            if len(TITLES_SAID) > 2000:
                TITLES_SAID.clear()
            TITLES_SAID.add(m['gid'])
            whose = " - the quest's" if m['quest'] else ''
            log(f"mobs: {m['kind']} {m['name']!r} in the zone - {m.get('title')} rank {m.get('rank')}, {m.get('health')} "
                f"health, {m.get('school')} (boss flag {m.get('boss')}){whose}")
    now = time.time()
    if trail and r is not None and r.get('pos') is not None:
        MOB_TRAIL.append((now, tuple(r['pos']), {m['gid']: (m['name'], m['pos'][0], m['pos'][1], m['pos'][2], m.get('yaw'))
                                                 for m in mobs}))
    # (which way and how fast each walks - every reading feeds it: the walker's asks, /navto's, /mobs', the map's)
    motion_feed(now, mobs, r.get('pos') if r is not None else None)
    return mobs, ''


def mob_cell(v):
    """a field of a /mobs or /battle line: no | or line breaks in it; None as empty; a flag as 1/0"""
    if v is None:
        return ''
    if isinstance(v, bool):
        return '1' if v else '0'
    return re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def mob_line(m, me):
    """/mobs' line for a mob m (mobs_now's) seen from me (the wizard's x, y, z): mob|name|x|y|z|distance|quest|degrees
    off its facing|title|rank|health|school|boss|gid|named|template - 9-14 what it is (navmem / bossmem: each "" while
    not known), 15 the quest's by its name or its goal only (quest_named: 1/0, "" not known), 16 its template's name
    (navmem's - "" not read; a mob with no template field at all, an older reader's, ends at 15 as before); 17-19 how it
    moves (motion_feed - only once its motion is known, the template's field then always there): vx|vy (units / s, its
    straight line over the last second) |moving (1 walking, 0 standing, "" not known)"""
    off = ''
    if m.get('yaw') is not None:
        dx, dy = me[0] - m['pos'][0], me[1] - m['pos'][1]
        d = math.hypot(dx, dy) or 1.0
        c = (dx * -math.sin(m['yaw']) + dy * -math.cos(m['yaw'])) / d
        off = f"{math.degrees(math.acos(max(-1.0, min(1.0, c)))):.0f}"
    fit, moving = m.get('fit'), m.get('moving')
    known = fit is not None or moving is not None
    motion_cells = ''
    if known:
        motion_cells = (f"|{fit[0]:.1f}|{fit[1]:.1f}|" if fit is not None else "|||") + mob_cell(moving)
    return (f"mob|{mob_cell(m['name'])}|{m['pos'][0]:.1f}|{m['pos'][1]:.1f}|{m['pos'][2]:.1f}|"
            f"{math.hypot(m['pos'][0] - me[0], m['pos'][1] - me[1]):.0f}|{1 if m.get('quest') else 0}|{off}|"
            + '|'.join(mob_cell(m.get(k)) for k in ('title', 'rank', 'health', 'school', 'boss', 'gid'))
            + '|' + mob_cell(m.get('named'))
            + ('|' + mob_cell(m.get('template')) if 'template' in m or known else '')
            + motion_cells)


def plate_x(p):
    """the middle of a participant's plate across the client, 0..1 (its box - in the root, bossmem's GUI units - over the
    root's width), '' not read"""
    b, r = p.get('box'), p.get('root')
    try:
        w = r[2] - r[0]
        return f'{(b[0] + b[2]) / 2 / w:.4f}' if w > 0 and b[2] > b[0] else ''
    except (TypeError, IndexError):
        return ''


def plate_box(p):
    """a participant's plate as fractions of the client: [left, top, right, bottom], each 0..1 (its box - in the root,
    bossmem's GUI units - over the root's width / height, as plate_x), four '' when it isn't read (the wizard's own when
    no window holds it: source handmem) or is empty. NOT CHECKED against the screen yet (v1.0.0)"""
    b, r = p.get('box'), p.get('root')
    try:
        w, h = r[2] - r[0], r[3] - r[1]
        if w > 0 and h > 0 and b[2] > b[0] and b[3] > b[1]:
            return [f'{b[0] / w:.4f}', f'{b[1] / h:.4f}', f'{b[2] / w:.4f}', f'{b[3] / h:.4f}']
    except (TypeError, IndexError):
        pass
    return ['', '', '', '']


def battle_lines(parts, why=''):
    """/battle's answer for navmem.battle's reading: part|me|team|name|health|max|boss|title|rank|school|player|gid|x|
    l|t|r|b|hide a participant (the wizard's own first), or none|<why> - x (plate_x) the 13th: an older bot reads the
    first 12; l|t|r|b (plate_box: the plate's box across and down the client, 0..1) and hide (1: the game hides its
    health - m_HideCurrentHP - its health field may not be what the plate shows; 0 not, '' not read) after it (v1.0.0):
    a bot before that reads its 13"""
    if not parts:
        return ['none|' + mob_cell(why or 'not in a battle')]
    out = []
    for p in sorted(parts, key=lambda p: not p.get('me')):
        mob = p.get('mob') or {}
        out.append('|'.join(['part', mob_cell(bool(p.get('me'))), mob_cell(p.get('team')), mob_cell(p.get('name')),
                             mob_cell(p.get('health')), mob_cell(p.get('max_health')), mob_cell(p.get('boss')),
                             mob_cell(mob.get('title')), mob_cell(mob.get('rank')),
                             mob_cell(mob.get('school') or (p.get('school') or '').capitalize() or None),
                             mob_cell(p.get('player')), mob_cell(p.get('owner')), plate_x(p)]
                            + plate_box(p) + [mob_cell(p.get('hide_hp'))]))
    return out


@functools.lru_cache(maxsize=1024)
def whole_name(name, item):
    """the name is the whole of item - a goal's item as the game's memory gives it ("Inactive Protector"), any of its
    words plural ("Flame Gem" / "Flame Gems", "Piece of Coral" / "Pieces of Coral"), a "The" / "A" / "An" before either
    ("History of Magic" / "The History of Magic") - never a part of it: name_matches took 'Teleporter' for 'To Teleporter
    Hub', 'Urn' for 'Urn Piece', 'Portal Piece' for 'Third Portal Piece' (68 such pairs in the zones' files)"""
    rx = mob_name_re(name or '')
    clean = re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9 ]', ' ', (item or '').lower())).strip()
    clean = re.sub(r'^(the|a|an) ', '', clean)
    return bool(rx is not None and clean and (rx.fullmatch(clean) or rx.fullmatch('the ' + clean)))


def thing_keys(t):
    """a thing's name keys: a placement's display and title keys, a live one's display key"""
    return [k for k in (t.get('keys') or [t.get('key')]) if k]


def quest_item(thing, goal_line, goal=None, key_hit=None):
    """the quest's goal is about this thing - thing: {name, key, keys, kind, src} (a live one or a placement), or its name.
    The memory's goal (goal_now):
      - its own key (item_key, the TALLYTEXT) is the thing's: when any thing listed has it (key_hit - the caller's, over
        its whole list; None: this thing's alone), only those are (the 4 Inactive Protectors: exact, whatever names say)
      - else an exact goal: its item - a talk goal's NPC, for an NPC - is the thing's whole name (whole_name); an ambient
        one (a mob's name on something that doesn't fight) never by its name
      - else the goal's line (the HUD's) names it
    Without it goal_line (the OCR's): slips allowed for (name_in_line) - not for one from the zone's file (src "file":
    the whole zone's things, far ones too - exact words only)"""
    t = thing if isinstance(thing, dict) else {'name': thing}
    name, kind = t.get('name') or '', t.get('kind') or ''
    if goal and goal.get('text'):
        ik = goal.get('item_key') or ''
        has = bool(ik) and ik in thing_keys(t)
        if key_hit is None:
            key_hit = has
        if key_hit or kind == 'ambient':
            return bool(has)
        if not name:
            return False
        if goal.get('exact'):
            want = [goal.get('item')] + ([goal.get('npc')] if kind == 'npc' else [])
            return any(whole_name(name, w) for w in want if w)
        return name_matches(name, goal['text'])
    if not goal_line or not name or kind == 'ambient':
        return False
    return name_matches(name, goal_line) if t.get('src') == 'file' else name_in_line(name, goal_line)


ITEM_NEAR = 400.0           # a live thing this near a placement of its template stands for it (the file's left out)


def merge_things(live, placed, uses=None):
    """/items?far=1's things: every live one (src mem) and every placement of the zone's file with a name key (src file -
    placements.built_things) that no live thing of the same template stands within ITEM_NEAR of (the game moves few: a
    live one is where it is now; a used or picked-up one is gone from memory but still in the file). A placement's gid:
    "f:<template>:<n>" by its "instance (n)", else - or taken - "f:<template>@<where its record is in the file>": the
    same every time the file is. uses: the templates the zone's triggers' use events may be fired by
    (puzzlefile.use_templates): a placement of one with no name key is a thing too - kind "use", name and key ""
    (a lever the game names nowhere); none: as before"""
    out = [dict(t, src=t.get('src') or 'mem') for t in live]
    gids = set()
    for p in placed or ():
        use = not p.get('key') and bool(uses) and bool(p.get('template')) and p['template'] in uses and not p.get('kind')
        if not p.get('key') and not use:
            continue
        if any(t.get('template') == p['template'] and math.hypot(t['pos'][0] - p['pos'][0], t['pos'][1] - p['pos'][1])
               <= ITEM_NEAR for t in live):
            continue
        gid = f"f:{p['template']}:{p['n']}" if p.get('n') is not None else ''
        if not gid or gid in gids:
            gid = f"f:{p['template']}@{p.get('at')}"
        gids.add(gid)
        if use:
            out.append({'name': '', 'pos': tuple(p['pos']), 'yaw': p.get('yaw'), 'gid': gid, 'template': p['template'],
                        'key': '', 'keys': [], 'kind': 'use', 'src': 'file'})
            continue
        out.append({'name': p.get('text') or '', 'pos': tuple(p['pos']), 'yaw': p.get('yaw'), 'gid': gid,
                    'template': p['template'], 'key': p['key'], 'keys': list(p.get('keys') or [p['key']]),
                    'kind': p.get('kind') or '', 'src': 'file'})
    return out


PLACES_SAID = {'at': 0.0}   # (when a failure to read the zone's file may be logged again)
PUZZLE_WANTED = {}          # (the zone whose triggers were last asked for - places_want)


# The requests that read the game's memory with the walker waiting (/nav's timeout is 150 ms): placements' builds wait
# for them (placements.busy), and so does the battle recorder (GATE)
GATED = {'/nav', '/mobs', '/goal', '/battle', '/navto', '/items', '/uiroot', '/blockers', '/navpass', '/deck', '/decks',
         '/sim', '/guitree', '/duels', '/plan'}


class Gate:
    """the gated requests in flight (memory /cards too) and when the last one ended: the battle recorder's own reads and
    file writes wait for idle(), and its Python work stops while busy() - so a request the bot waits on gets the
    GIL and navmem's lock at once"""

    def __init__(self):
        self.lock = threading.Lock()
        self.n = 0
        self.entered = 0
        self.ended = 0.0

    def enter(self):
        with self.lock:
            self.n += 1
            self.entered += 1

    def leave(self):
        with self.lock:
            self.n -= 1
            self.ended = time.monotonic()

    def busy(self):
        return self.n > 0

    def idle(self, d=0.1, own=0):
        """nothing gated in flight (but own - the caller's own request) and nothing ended in the last d s"""
        return self.n <= own and time.monotonic() - self.ended >= d


GATE = Gate()
REC = None      # the battle recorder (vision\battlerec.py), started by main(); None: off, the hooks do nothing
# s a fresh deck read asked by a gated request (/deck, /decks, /sim, /book) waits for another fresh read to end - navmem
# reads the decks one at a time (NavMem.deck's queue): the one in progress (the recorder's, say) gives way to a gated
# request within its DECK_IDLE (1 s), its idle() seeing it in flight; not ended by then: none|gave way ... (read again)
DECK_QUEUE_S = 1.5


def _rec_hook(name, *a):
    """hands the recorder a copy of what a request already read (no read, no write: a queue put) - never raises"""
    try:
        REC and getattr(REC, name)(*a)
    except Exception:  # noqa: BLE001 - the answer as it is
        pass


def rec_local(ctx=None):
    """(partyorders) the battle recorder's duel in its planning phase - the local player's own duel only, which AHK's log
    reader can't tell from other wizards' nearby: (its duel number as text, its round n), else None (the recorder off or
    broken, no duel, not in Planning - lagging -, no round yet). ctx['duel']: a test's stand-in (as plan_charms). Read
    from the request's thread, as plan_charms reads it; never raises"""
    try:
        if ctx is not None and 'duel' in ctx:
            d = ctx['duel']
        else:
            rec = REC
            d = rec.parser.duel if rec is not None and rec.on and not rec.broken else None
        if not isinstance(d, dict) or d.get('phase') != 'Planning':
            return None
        rounds = d.get('rounds')
        if not isinstance(rounds, list) or not rounds or not isinstance(rounds[-1], dict):
            return None
        n = rounds[-1].get('n')
        if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= 999:
            return None
        return str(d.get('num') if d.get('num') is not None else ''), n
    except Exception:  # noqa: BLE001 - not known
        return None


def deck_lines(fresh):
    """/deck's answer: deckmem.deck_lines of the worn deck's last reading plus deckage|<s>, or none|<why>"""
    import deckmem
    # (a fresh read only while the recorder follows the game's log - on, not broken, its log found - and sees no duel:
    # off, its parser isn't fed and in_duel() would say no in a battle too)
    rec = REC if REC is not None and REC.on and not REC.broken and REC.started and REC.tail is not None else None
    if fresh and (rec is None or rec.in_duel()):
        return ['none|' + ('in a battle' if rec is not None else "the battle recorder isn't following the game's log (a "
                                                                   "battle can't be ruled out)")]
    r, why = nav_reader().deck(fresh=fresh, wait=0.3 if fresh else 0.0, idle=lambda d: GATE.idle(d, own=1),
                               stop=rec.in_duel if fresh else None, queue=DECK_QUEUE_S if fresh else 0.0)
    if r is None:
        return ['none|' + mob_cell(why or 'not read')]
    return deckmem.deck_lines(r) + ['deckage|%.1f' % max(0.0, time.monotonic() - (r.get('read_at') or time.monotonic()))]


# ---------------------------------------------------------------- the battle simulator (battlesim.py)
SIM = {'book': None, 'facts': None, 'at': 0.0, 'refreshing': 0}    # refreshing: paced reads of the battles running
SIM_LOCK = threading.Lock()
SIM_BOOK_S = 600        # the battles recorded read again this often


def gate_wait():
    """(a background thread's pure-Python work) wait while a gated request is in flight - the bot's and the walker's
    reads go first: a thread holding the GIL pushed a live /nav read past its 150 ms (placements.py) - up to 10 s"""
    waited = 0
    while GATE.busy() and waited < 200:
        time.sleep(0.05)
        waited += 1


def sim_book(paced=False):
    """(FoeBook, facts): the battles recorded by enemy and cards.jsonl's card facts (AutoFarmer\\learned\\battles) -
    read again every SIM_BOOK_S. paced (a background thread's - /deckfor's): read again pausing for each battle while a
    gated request is in flight (gate_wait), OUTSIDE SIM_LOCK - a gated /decks or /sim waiting on that lock is in flight
    itself, so a pause under it would only wait it out. While a paced read runs (SIM refreshing - _plan_load's too) the
    old book answers: a gated /sim or /decks never reads the whole archive again meanwhile (none yet: read here)"""
    import battlesim
    base = os.path.join(ROOT, 'learned', 'battles')
    with SIM_LOCK:
        if SIM['book'] is not None and (time.monotonic() - SIM['at'] <= SIM_BOOK_S or SIM['refreshing']):
            return SIM['book'], SIM['facts']
        if not paced:
            SIM['book'], SIM['facts'] = battlesim.FoeBook(base), battlesim.load_facts(os.path.join(base, 'cards.jsonl'))
            SIM['at'] = time.monotonic()
            return SIM['book'], SIM['facts']
        SIM['refreshing'] += 1

    def feed():
        for b in battlesim.FoeBook._read(base, 120):
            gate_wait()
            yield b
    try:
        book = battlesim.FoeBook(battles=feed())
        facts = battlesim.load_facts(os.path.join(base, 'cards.jsonl'))
        with SIM_LOCK:
            SIM['book'], SIM['facts'], SIM['at'] = book, facts, time.monotonic()
    finally:
        with SIM_LOCK:
            SIM['refreshing'] -= 1
    return book, facts


def decks_reading(fresh, out=False):
    """(every deck's reading with the cards' kinds, why) - the last one, or (fresh) one read now: only while the battle
    recorder follows the game's log and sees no duel (deck_lines' rule) - or, the recorder off, when the bot says it's out
    of battle (out: its own battle check and the game's log)"""
    rec = REC if REC is not None and REC.on and not REC.broken and REC.started and REC.tail is not None else None
    if fresh and ((rec is None and not out) or (rec is not None and rec.in_duel())):
        return None, ('in a battle' if rec is not None else "the battle recorder isn't following the game's log (a "
                                                             "battle can't be ruled out)")
    # (the recorder off - out: nothing to stop the read by, rec None - book_answer's way)
    return nav_reader().deck(fresh=fresh, wait=0.3 if fresh else 0.0, idle=lambda d: GATE.idle(d, own=1),
                             stop=rec.in_duel if fresh and rec is not None else None, only_equipped=False, kinds=True,
                             queue=DECK_QUEUE_S if fresh else 0.0)


def decks_lines(fresh, out=False):
    """/decks' answer: every deck (deckmem.deck_lines) + the profiles they'd make (battlesim.learn_lines) + deckage"""
    import battlesim
    import deckmem
    r, why = decks_reading(fresh, out)
    if r is None:
        return ['none|' + mob_cell(why or 'not read')]
    # (the profiles never cost the decks' own lines: a deck they can't be made of is said, the rest still answered)
    try:
        _book, facts = sim_book()
        learn = battlesim.learn_lines(battlesim.learn_decks(r, facts))
    except Exception as e:  # noqa: BLE001
        learn = ['nolearn|%s' % mob_cell('the deck profiles failed (%r)' % (e,))]
    return (deckmem.deck_lines(r) + learn
            + ['deckage|%.1f' % max(0.0, time.monotonic() - (r.get('read_at') or time.monotonic()))])


def book_answer(fresh, out=False, kinds=False):
    """/book's answer: deckmem.book_lines of the books' reading (navmem's deck(books=True) - its own cache) + bookage, or
    none|<why>. fresh: read now, only as decks_reading allows it (the battle recorder following the game's log and seeing
    no duel - or, the recorder off, out: the bot says it's out of battle); the worn deck only (the books are what's
    asked for)"""
    import deckmem
    rec = REC if REC is not None and REC.on and not REC.broken and REC.started and REC.tail is not None else None
    if fresh and ((rec is None and not out) or (rec is not None and rec.in_duel())):
        return ['none|' + ('in a battle' if rec is not None else "the battle recorder isn't following the game's log (a "
                                                                   "battle can't be ruled out)")]
    # (the recorder off - out: nothing to stop the read by, rec None)
    r, why = nav_reader().deck(fresh=fresh, wait=0.3 if fresh else 0.0, idle=lambda d: GATE.idle(d, own=1),
                               stop=rec.in_duel if fresh and rec is not None else None, only_equipped=True, kinds=kinds,
                               books=True, queue=DECK_QUEUE_S if fresh else 0.0)
    if r is None:
        return ['none|' + mob_cell(why or 'not read')]
    return deckmem.book_lines(r) + ['bookage|%.1f' % max(0.0, time.monotonic() - (r.get('read_at') or time.monotonic()))]


def quests_answer():
    """/quests' answer: questmem.quest_lines of every quest in the game's quest manager (navmem's quests()), or none|<why>
    - never raises"""
    try:
        import questmem
        t0 = time.perf_counter()
        rows, why = nav_reader().quests(wait=0.3)
        return questmem.quest_lines(rows, why, (time.perf_counter() - t0) * 1000)
    except Exception as e:  # noqa: BLE001 - never into the server
        return ['none|' + mob_cell('reading the quests failed (%r)' % (e,))]


# (/book and /quests read the game's memory as /deck and /goal do: gated the same way - placements' builds and the battle
# recorder wait for them, and the book read's own request is the one GATE.idle(own=1) leaves out)
GATED |= {'/book', '/quests'}


def _usehit_off(vals):
    """True when vals ({key: str}) switch every hit off - usehit1-4 all 0 (Decks.ahk DeckSimVals sends them, DeckKeys;
    the bot's DeckFilterHand then plays no hit): /sim, /deckfor and /plan play that as Opts.usehit False, one rule"""
    return all(str(vals.get('usehit%d' % i)) == '0' for i in range(1, 5))


def sim_lines_for(q):
    """/sim's answer (see the docstring) - never raises"""
    import battlesim as B
    try:
        r, why = decks_reading(q.get('fresh') == '1', q.get('ob') == '1')
        if r is None:
            return ['none|' + mob_cell(why or "the decks haven't been read with their cards yet (/decks?fresh=1)")]
        want = (q.get('deck') or '').strip().lower()
        decks = r.get('decks') or []
        if want:
            deck = next((d for d in decks if '%x' % d['gid'] == want), None)
        else:
            deck = next((d for d in decks if d.get('equipped')), None)
        if deck is None:
            return ['none|' + ("deck %s isn't among the decks read" % want if want else 'no deck worn')]
        book, facts = sim_book()
        notes = []
        cards = B.deck_cards(deck, facts, notes)

        def fl(k, d=0.0):
            try:
                return float(q.get(k) or d)
            except ValueError:
                return d
        me = B.Me(q.get('school') or deck.get('school'), fl('hp', 3000), damage=fl('damage'), pierce=fl('pierce'),
                  crit=fl('crit'), block=fl('block'), level=fl('level', 100), accuracy=fl('acc'), resist=fl('resist'),
                  power_pip=fl('pp', 0.4), team=fl('team', 1))
        vals = {}
        for kv in (q.get('vals') or '').split(','):
            k, _, v = kv.partition(':')
            if k.strip():
                vals[k.strip().lower()] = v.strip()
        wiki, casts = enemy_state()
        foes = []
        for spec in (q.get('foes') or '').split('|'):
            bits = (spec.split('~') + ['', '', '', ''])[:4]
            name = bits[0].strip()
            if not name:
                continue
            hp = int(float(bits[1])) if re.fullmatch(r'\d+(\.\d+)?', bits[1].strip()) else None
            foes.append(book.foe(name, wiki, casts, hp=hp, school=bits[2].strip() or None,
                                 boss=True if bits[3].strip() == '1' else None))
        if not foes:
            return ['none|no enemies named (foes=)']
        boss = q.get('boss') == '1' or any(f.boss for f in foes)
        opts = B.Opts.of(vals, boss=boss)
        if _usehit_off(vals):
            opts.usehit = False
        res = B.simulate(cards, me, foes, opts, n=int(fl('n', 300)))
        res['why'] = notes + res['why']
        if any(not f.spells and 'pending' not in f.src and wiki.creature(f.name) is None for f in foes):
            res['why'].append("the wiki is still being asked about an enemy: ask again in a moment")
        return B.sim_lines(res, B.verdict(res, cards, me, foes, opts), foes) + [
            'deck|%x|%s' % (deck['gid'], str(deck.get('display') or deck.get('object_name') or '').replace('|', '/'))]
    except Exception as e:  # noqa: BLE001 - never into the server
        return ['none|the simulation failed (%r)' % (e,)]


# ---------------------------------------------------------------- decks matched to a zone's enemies (battlesim.best_decks)
DECKFOR = {'cache': {}, 'thread': None}
DECKFOR_LOCK = threading.Lock()
DECKFOR_S = 600         # an answer kept this long (the battles recorded are read again as often - SIM_BOOK_S)


def deckfor_lines_for(q, ctx=None, wait=False):
    """/deckfor's answer (see the docstring) - never raises. Worked out in a thread (each deck against each group: a
    few seconds), kept DECKFOR_S for the same question: the first ask answers none|working it out, an ask after it the
    lines; an ask after DECKFOR_S the old lines (a note| saying so) while the thread works them out again. ctx {book,
    facts, wiki, casts, decks} and wait (work it out here) - a test's"""
    import battlesim as B
    try:
        zone = (q.get('zone') or '').strip()
        foes_q = (q.get('foes') or '').strip()
        if ctx is None:
            # (the decks' last reading now - never read here; the battles recorded and the wiki in the thread below)
            r, why = decks_reading(False)
            ctx = {'decks': r, 'why': why}
        reading = ctx.get('decks') or {}
        decks = [d for d in reading.get('decks') or [] if d.get('sets') or d.get('equipped')]
        if not decks:
            return ['none|' + mob_cell(ctx.get('why') or "the decks haven't been read with their cards yet (the Cards "
                                       "tab's From game)")]
        sig = tuple(sorted((d.get('gid'), d.get('main_n'), d.get('item_n')) for d in decks))
        key = (zone, foes_q, q.get('school') or '', q.get('hp') or '', q.get('damage') or '', q.get('vals') or '',
               q.get('n') or '', sig, q.get('dvals') or '')
        now = time.monotonic()
        with DECKFOR_LOCK:
            hit = DECKFOR['cache'].get(key)
            if hit is not None and now - hit[0] < DECKFOR_S:
                return hit[1]
            # (an answer kept past DECKFOR_S: handed back as it was while it's worked out again - the bot re-asks every
            # 10 minutes too, and a "working it out" then would drop the zone's deck for a moment - Decks.ahk
            # DeckForZone keeps its rows through one as well)
            stale = list(hit[1]) + ['note|worked out %d minutes ago - being worked out again' % ((now - hit[0]) // 60)] \
                if hit is not None else None
            busy = DECKFOR['thread'] is not None and DECKFOR['thread'].is_alive()
            if busy and not wait:
                return stale or ['none|working out another zone\'s decks - ask again in a few seconds']

        def fl(k, d=0.0):
            try:
                v = float(q.get(k) or d)
                return v if math.isfinite(v) else d
            except (TypeError, ValueError):
                return d

        def work():
            try:
                if 'book' in ctx:
                    book, facts = ctx.get('book') or B.FoeBook(battles=[]), ctx.get('facts') or {}
                    wiki, casts = ctx.get('wiki'), ctx.get('casts')
                else:
                    # (the battles recorded read again, and each deck simulated, pausing for the gated reads: this
                    # thread runs while the bot walks the zone it was asked at - the walker's /nav goes first)
                    book, facts = sim_book(paced=True)
                    wiki, casts = enemy_state()
                if foes_q:
                    groups = [[x.strip() for x in g.split('~') if x.strip()] for g in foes_q.split('|')]
                else:
                    groups = (book.groups or {}).get(zone) or {}
                vals = {}
                for kv in (q.get('vals') or '').split(','):
                    k, _, v = kv.partition(':')
                    if k.strip():
                        vals[k.strip().lower()] = v.strip()
                # (each in-game deck's bot deck profile's own settings - Decks.ahk DeckForZone: gid~k:v,...|... - the
                # first profile per in-game deck that fits your school; "gid~": a profile with none of its own. Junk
                # entries skipped)
                dvals = {}
                for ent in (q.get('dvals') or '').split('|'):
                    gid, sep, kvs = ent.partition('~')
                    if sep and gid.strip():
                        own = {}
                        for kv in kvs.split(','):
                            k, _, v = kv.partition(':')
                            if k.strip():
                                own[k.strip().lower()] = v.strip()
                        dvals[gid.strip().lower()] = own
                specs = []
                for d in decks:
                    cards = B.deck_cards(d, facts)
                    gk = '%x' % d['gid'] if isinstance(d.get('gid'), int) else str(d.get('gid') or '')
                    dv = dict(vals)
                    if gk.lower() in dvals:
                        # (the bot deck profile it would be played with - Decks.ahk DeckSet / Stat: its own over yours)
                        dv.update(dvals[gk.lower()])
                    else:
                        # (no profile: the settings its cards call for - learn_deck's - on top of yours)
                        try:
                            dv.update({k: str(v) for k, v in B.learn_deck(d, facts, len(decks))['vals'].items()})
                        except Exception:  # noqa: BLE001 - your settings alone
                            pass
                    o = B.Opts.of(dv)
                    if _usehit_off(dv):
                        # (a profile - or your settings - with every hit off: played with none, as /sim and /plan do)
                        o.usehit = False
                    specs.append((gk, str(d.get('display') or d.get('object_name') or 'deck'), cards, o))
                sch = (q.get('school') or '').lower()
                me = B.Me(sch, fl('hp', 3000), damage=fl('damage'), pierce=fl('pierce'), crit=fl('crit'),
                          block=fl('block'), accuracy=fl('acc'), resist=fl('resist'), power_pip=fl('pp', 0.4))
                res = B.best_decks(specs, groups, lambda names: [book.foe(nm, wiki, casts) for nm in names], me,
                                   n=int(min(300, max(10, fl('n', B.DECKFOR_N)))), budget_ms=20000, pause=gate_wait)
                lines = B.deckfor_lines(res, zone)
            except Exception as e:  # noqa: BLE001 - said, not kept
                lines = ['none|the decks couldn\'t be simulated (%r)' % (e,)]
            with DECKFOR_LOCK:
                if len(DECKFOR['cache']) > 32:
                    DECKFOR['cache'].clear()
                DECKFOR['cache'][key] = (time.monotonic(), lines)
            return lines
        if wait:
            return work()
        with DECKFOR_LOCK:
            DECKFOR['thread'] = threading.Thread(target=work, name='deckfor', daemon=True)
            DECKFOR['thread'].start()
        return stale or ['none|working it out - ask again in a few seconds']
    except Exception as e:  # noqa: BLE001 - never into the server
        return ['none|the decks couldn\'t be simulated (%r)' % (e,)]


# ---------------------------------------------------------------- the round planner (battlesim.plan_round, battlelearn)
PLAN = {'plays': None, 'at': 0.0, 'thread': None}
PLAN_LOCK = threading.Lock()


def _plan_load():
    """(the planner's thread) the battles recorded read once - pausing while a gated request is in flight (the bot's and
    the walker's reads go first) - into the simulator's FoeBook (SIM: as sim_book keeps it) and the learned plays
    (battlelearn; saved to learned\\battles\\plays.json); cards.jsonl's facts with them. One pass feeds both: an odd
    record the FoeBook can't take is skipped there (counted in its why), the pass and the learned plays go on"""
    import battlelearn
    import battlesim
    base = os.path.join(ROOT, 'learned', 'battles')
    plays = battlelearn.Plays()
    # (a paced read running: sim_book's callers keep the old book meanwhile)
    with SIM_LOCK:
        SIM['refreshing'] += 1
    try:
        def feed():
            for b in battlelearn.read(base, days=120):
                gate_wait()
                plays.add(b)
                yield b
        book = battlesim.FoeBook(battles=feed())
        facts = battlesim.load_facts(os.path.join(base, 'cards.jsonl'))
        with SIM_LOCK:
            SIM['book'], SIM['facts'], SIM['at'] = book, facts, time.monotonic()
        plays.made = time.strftime('%Y-%m-%d %H:%M:%S')
        plays.save(os.path.join(base, battlelearn.PLAYS_FILE))
        log('/plan: %d battles recorded read (%d rounds learned)%s' % (plays.battles, plays.rounds,
                                                                      ('; ' + book.why) if book.why else ''))
    except Exception as e:  # noqa: BLE001 - planned with what there is
        log('/plan: the battles recorded could not be read (%r)' % (e,))
    finally:
        with SIM_LOCK:
            SIM['refreshing'] -= 1
    PLAN['plays'], PLAN['at'] = plays, time.monotonic()


def plan_book():
    """{book, facts, plays, why} for /plan without waiting: the simulator's FoeBook and card facts (as sim_book keeps
    them) and the learned plays as last read - none read yet or SIM_BOOK_S old: read again in a thread (_plan_load), this
    round planned with what there is (nothing learned yet: why says so)"""
    import battlesim
    now = time.monotonic()
    with PLAN_LOCK:
        stale = (SIM['book'] is None or now - SIM['at'] > SIM_BOOK_S or PLAN['plays'] is None
                 or now - PLAN['at'] > SIM_BOOK_S)
        if stale and (PLAN['thread'] is None or not PLAN['thread'].is_alive()):
            PLAN['thread'] = threading.Thread(target=_plan_load, name='planbook', daemon=True)
            PLAN['thread'].start()
    book, facts = SIM['book'], SIM['facts']
    if book is None:
        return {'book': battlesim.FoeBook(battles=[]), 'facts': {}, 'plays': PLAN['plays'],
                'why': 'the battles recorded are still being read - nothing learned from them this round'}
    return {'book': book, 'facts': facts or {}, 'plays': PLAN['plays'], 'why': ''}


def plan_mates(text, facts):
    """/plan's mates= (name~seat~school~hp~max~role~pips~power~hand|... - hand: tid:kind:pips:school:value[:ench[:mark]];...
    each card's kind and value from cards.jsonl's facts when it has none, ench a hit's damage enchant already on it, mark
    what the simulator reads off its name - resh, tower, an enchant's word: partyorders' hands, party.py hand_of -; empty:
    not known) as [battlesim.Mate] - a field it can't read the default, a card it can't make left out (a hand given
    with no card made: not known, never an empty hand); never raises"""
    import battlesim as B
    out = []
    # (a mark as the card's name, so the simulator's name checks see it: Tower Shield, Reshuffle, a bot enchant's word)
    mark_names = dict({'tower': 'Tower Shield', 'resh': 'Reshuffle'}, **{w: w.capitalize() for w in B.ENCHANT_WORDS})
    try:
        for spec in (text or '').split('|')[:12]:
            bits = (spec.split('~') + [''] * 9)[:9]
            if not any(b.strip() for b in bits):
                continue
            if len(out) >= 3:
                break

            def num(v, d=None):
                v = (v or '').strip()
                return int(v) if re.fullmatch(r'\d{1,6}', v) else d
            hand = None
            if bits[8].strip():
                hand = []
                for item in bits[8].split(';')[:9]:
                    f = (item.split(':') + [''] * 7)[:7]
                    # (a template id of up to 10 digits - the game's; the other numbers num()'s 6)
                    tid = f[0].strip()
                    c = {'template_id': int(tid) if re.fullmatch(r'\d{1,10}', tid) else None,
                         'kind': f[1].strip().lower() or None, 'pips': num(f[2]),
                         'school': f[3].strip().lower(), 'value': f[4].strip() or None,
                         'value_text': f[4].strip() or None}
                    if re.fullmatch(r'\d{1,4}', f[5].strip()):
                        c['ench'] = int(f[5].strip())
                    if mark_names.get(f[6].strip()):
                        c['name'] = mark_names[f[6].strip()]
                    card = B.card_of(c, facts)
                    if card is not None:
                        hand.append(card)
                # (a hand given but no card made of it: not known - its role's way -, not one holding nothing)
                hand = hand or None
            school = bits[2].strip().lower()
            me = B.Me(school, num(bits[4], 3000), hp=num(bits[3]))
            out.append(B.Mate(re.sub(r'[^\w .\'-]', '', bits[0])[:24], num(bits[1]), me, bits[5].strip().lower(), hand,
                              [c for c in hand for _ in range(2)] if hand else [], num(bits[6], 0), num(bits[7], 0),
                              num(bits[3])))
    except Exception:  # noqa: BLE001 - the ones read so far
        pass
    return out


def plan_charms(state, plates, facts, ctx):
    """(/plan's charms=log) the charms on now from the game's log (battlerec.charms_now on the battle recorder's open
    duel - ctx['duel'] a test's) put in state (State.charms_from: the enemies matched to the memory's plates by gid) -
    [notes]; never raises"""
    try:
        import battlerec
        if 'duel' in ctx:
            d = ctx['duel']
        else:
            rec = REC
            d = rec.parser.duel if rec is not None and rec.on and not rec.broken else None
        if not isinstance(d, dict):
            return ["the log's charms not read (the battle recorder isn't following this battle) - the bot's own count"]
        ch = battlerec.charms_now(d, facts)
        gids = {str(p.get('gid')): sc for sc, p in list((d.get('parts') or {}).items())
                if isinstance(p, dict) and p.get('gid')}
        scs = [gids.get(str(p.get('owner'))) if isinstance(p, dict) and p.get('owner') else None for p in plates]
        n = state.charms_from(ch, d.get('me_sc'), scs if any(s is not None for s in scs) else None)
        return ["%d charm%s on from the game's log (%d of %d enemies matched by gid)" % (
            n, '' if n == 1 else 's', sum(1 for s in scs if s is not None), len(scs))] + list(ch.get('why') or [])
    except Exception as e:  # noqa: BLE001 - the bot's own count then
        return ["the log's charms couldn't be read (%r) - the bot's own count" % (e,)]


def plan_lines_for(q, cards_reader=None, battle_reader=None, ctx=None):
    """/plan's answer (see the docstring) - never raises (a 'none|why' line), and within budget (ms, default 300) as far
    as it can: the game's memory read first (the hand and pips: cards_reader; the enemies: battle_reader - navmem's
    reads, a test's stand-ins), the rollouts in the time left. ctx: {book, facts, plays, wiki, casts, decks} (a test's -
    else plan_book, enemy_state and the decks' last reading: decks_reading, never a fresh read in a battle)"""
    import battlesim as B
    t0 = time.monotonic()

    def fl(k, d=0.0):
        try:
            v = float(q.get(k) or d)
            return v if math.isfinite(v) else d
        except (TypeError, ValueError):
            return d
    try:
        budget = int(min(5000, max(50, fl('budget', 300))))
        cards_reader = cards_reader or (lambda: nav_reader().cards())
        battle_reader = battle_reader or (lambda: nav_reader().battle(wait=0.3))
        r, why = cards_reader()
        # (the game dealing or laying the cards out - the bot's discards just made: asked again for 40 % of the budget)
        while r is not None and r.get('state') == 'changing' and (time.monotonic() - t0) * 1000 < 0.4 * budget:
            time.sleep(0.04)
            r, why = cards_reader()
        if r is None:
            return ['none|' + mob_cell(why or "the game can't be read")]
        if not (r.get('in_battle') and r.get('planning') and r.get('settled')):
            return ['none|' + mob_cell(r.get('why') or 'not a settled hand in a planning phase')]
        _rec_hook('saw_hand', r)
        # (each card with its place in the game's hand - 0 the leftmost, counted over every card read: plan|'s i)
        raw = [(gi, c) for gi, c in enumerate(r.get('cards') or []) if isinstance(c, dict) and c.get('name')]
        if not raw:
            return ['none|no card in hand']
        mer = r.get('me') or {}
        ctx = dict(ctx) if ctx is not None else None
        if ctx is None:
            ctx = plan_book()
            ctx['wiki'], ctx['casts'] = enemy_state()
            try:
                ctx['decks'] = decks_reading(False)[0]
            except Exception:  # noqa: BLE001 - no deck then
                ctx['decks'] = None
        book, facts, notes = ctx.get('book') or B.FoeBook(battles=[]), ctx.get('facts') or {}, []
        if ctx.get('why'):
            notes.append(ctx['why'])
        wiki, casts = ctx.get('wiki'), ctx.get('casts')
        # (the enemies: the game's memory - /battle's reading - else foes= name~health~school~boss~health now)
        parts, pwhy = battle_reader()
        foes, fhp, plates, team = [], [], [], 1
        if parts:
            _rec_hook('saw_battle', parts)
            mine = next((p for p in parts if p.get('me')), None)
            myteam = mine.get('team') if mine else None
            team = max(1, len([p for p in parts if p.get('team') == myteam and p.get('player')])) if mine else 1
            for k, p in enumerate(p for p in parts if not p.get('me') and (mine is None or p.get('team') != myteam)):
                mob = p.get('mob') or {}
                name = p.get('name') or mob.get('title') or 'Enemy %d' % (k + 1)
                foes.append(book.foe(name, wiki, casts, hp=p.get('max_health') or None,
                                     school=(mob.get('school') or p.get('school') or '').lower() or None,
                                     boss=bool(p.get('boss'))))
                fhp.append(p.get('health'))
                plates.append(p)
        else:
            for spec in (q.get('foes') or '').split('|'):
                bits = (spec.split('~') + [''] * 5)[:5]
                if not bits[0].strip():
                    continue
                num = [int(float(x)) if re.fullmatch(r'\d+(\.\d+)?', x.strip()) else None for x in (bits[1], bits[4])]
                foes.append(book.foe(bits[0].strip(), wiki, casts, hp=num[0], school=bits[2].strip() or None,
                                     boss=True if bits[3].strip() == '1' else None))
                fhp.append(num[1])
                plates.append(None)
            if foes:
                notes.append("the enemies as the bot named them (the game's memory: %s)" % (pwhy or 'no battle read'))
        if not foes:
            return ['none|' + mob_cell('no enemies (%s)' % (pwhy or 'no battle read'))]
        # (my side: the hand - each card's kind from the memory, else cards.jsonl's facts -, pips, health, the stats)
        hand, ids = [], []
        for gi, c in raw:
            card = B.card_of(dict(c, side='treasure' if c.get('treasure') else 'main', item=bool(c.get('item_card'))),
                             facts)
            if card is not None:
                hand.append(card)
                ids.append((gi, c.get('slot') or '', c.get('template_id') if c.get('template_id') is not None else ''))
        if len(hand) < len(raw):
            notes.append('%d card%s in hand with no kind known left out' % (len(raw) - len(hand),
                                                                            '' if len(raw) - len(hand) == 1 else 's'))
        school = (q.get('school') or mer.get('school') or '').lower()
        me = B.Me(school, mer.get('max_health') or fl('hp', 3000), hp=mer.get('health'), damage=fl('damage'),
                  pierce=fl('pierce'), crit=fl('crit'), block=fl('block'), level=fl('level', 100), accuracy=fl('acc'),
                  resist=fl('resist'), power_pip=fl('pp', 0.4), team=fl('team', team))
        pp = mer.get('pips') or {}

        def pip(k):
            v = pp.get(k)
            return v if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 else 0
        pips = pip('generic') + pip('power') + sum(pip(s) for s in B.SCHOOLS)
        power = pip('power') + (pip(me.school) if me.school else 0)
        # (the bot's own bookkeeping: blades on me, traps on one enemy, the aura - key~schools~% |...)
        def boosts(text):
            out = []
            for spec in (text or '').split('|'):
                bits = (spec.split('~') + ['', '', ''])[:3]
                try:
                    pct = float(bits[2])
                except ValueError:
                    continue
                sch = [s.strip().lower() for s in bits[1].split(',') if s.strip().lower() in B.SCHOOLS + ('all',)]
                if bits[0].strip() and sch and pct > 0:
                    out.append((bits[0].strip(), {s: pct for s in sch}))
            return out
        blades = boosts(q.get('blades'))
        traps = [[]] * len(foes)
        tl = [b for _n, b in boosts(q.get('traps'))]
        if tl:
            # (the enemy they're on: the one whose most health the bot noted - one only -, else the most health now)
            want = fl('trapmax', 0)
            at = [k for k, f in enumerate(foes) if want and f.maxhp == int(want)]
            k = at[0] if len(at) == 1 else max(range(len(foes)), key=lambda j: fhp[j] if fhp[j] is not None
                                               else foes[j].maxhp)
            traps = [tl if j == k else [] for j in range(len(foes))]
        # (aura=schools~%~rounds left, this one counted)
        aura = None
        ab = (q.get('aura') or '').split('~')
        if len(ab) >= 3 and re.fullmatch(r'\d+', ab[2].strip()) and int(ab[2]) > 0:
            ar = boosts('aura~%s~%s' % (ab[0], ab[1]))
            if ar:
                aura = (ar[0][1], int(ab[2]))
        first = q.get('first')
        # (the draw pile: the worn deck - deck= its gid hex - less the hand; not read: more of the hand's cards)
        reading = ctx.get('decks') or {}
        want = (q.get('deck') or '').strip().lower()
        decks = reading.get('decks') or []
        deck = next((d for d in decks if want and isinstance(d.get('gid'), int) and '%x' % d['gid'] == want), None) \
            or next((d for d in decks if d.get('equipped')), None)
        pile = B.deck_cards(deck, facts) if deck else []
        if not pile:
            pile = [c for c in hand for _ in range(3)]
            notes.append("the deck isn't read (the Cards tab's From game, out of battle): the draw pile taken as more "
                         "of the hand's cards")
        # (the bot's keys for the blades on - storm/blade, blade3 - named as the hand's or deck's card: a copy in hand
        # of one on is then 'on already', never cast again or stacked in the rollouts - the bot's used flags hold it)
        blades = B.bot_blades(blades, hand + pile)
        # (the bot's own bookkeeping of this battle: the blades and traps cast that its used flags hold back -
        # key~schools~% |..., "-" none; not sent - an older AutoFarmer: None, the blades on taken as cast -, the
        # treasure cards drawn - Draw.ahk DrawsBattle -, drawing off now, a support's PartyShield gone - used19)
        draws = max(0, int(fl('draws', 0)))
        drawoff = q.get('drawoff') == '1'
        uq = q.get('used')
        boosts_used = B.bot_boosts_used(boosts(uq)) if uq is not None else None
        pshield = q.get('pshield') == '1'
        state = B.State.of_deck(hand, pile, pips=pips, power=power, hp=mer.get('health'), fhp=fhp, blades=blades,
                                traps=traps, aura=aura, rnd=int(fl('round', 1)), boosts_run=int(fl('boostrun', 0)),
                                me_first=None if first not in ('0', '1') else first == '1', draws=draws,
                                drawoff=drawoff, boosts_used=boosts_used, pshield_used=pshield)
        vals = {}
        for kv in (q.get('vals') or '').split(','):
            k, _, v = kv.partition(':')
            if k.strip():
                vals[k.strip().lower()] = v.strip()
        opts = B.Opts.of(vals, boss=q.get('boss') == '1' or any(f.boss for f in foes))
        if _usehit_off(vals):
            opts.usehit = False
        # (batch 3 - the team model and the log's charms; none asked: as before) my party battle role and seat, the
        # party's other wizards on my side
        role = (q.get('role') or '').strip().lower()
        if role in ('blader', 'healer'):
            opts.role = role
        if re.fullmatch(r'[4-7]', (q.get('seat') or '').strip()):
            state.seat = int(q['seat'])
        # (partyorders - hands=party, the leader's: each mate's blank hand, pips, power and health from the hand its own
        # bot sent for this round - party.py fill_mates; the round the battle recorder's - its own duel only -, else the
        # bot's. P: a test's stand-in, else this helper's party)
        hands_party = q.get('hands') == 'party'
        mtext, used, party_notes, P, prnd = q.get('mates'), [], [], None, None
        if hands_party:
            P = ctx['party'] if 'party' in ctx else PARTY
            loc = rec_local(ctx)
            prnd = loc[1] if loc else int(fl('round', 1))
            if P is None:
                party_notes = ["the party isn't running in this helper - the mates' hands not known"]
                mtext = q.get('mates') or ''
            else:
                mtext, used, party_notes = P.fill_mates(q.get('mates'), prnd)
        mates = plan_mates(mtext, facts)
        if mates:
            state.mates = mates
            notes.append('the team model: %d mate%s on your side (%s)' % (len(mates), '' if len(mates) == 1 else 's',
                                                                          ', '.join('%s %s%s' % (
                                                                              m.name or 'seat %s' % m.seat, m.role,
                                                                              '' if m.hand is not None else
                                                                              ' - its hand not known') for m in mates)))
        if q.get('charms') == 'log':
            notes.extend(plan_charms(state, plates, facts, ctx))
        plays = ctx.get('plays')
        prior = plays.prior_fn(me.school) if plays is not None and getattr(plays, 'rounds', 0) else None
        left = budget - int((time.monotonic() - t0) * 1000) - 15
        if left < 20:
            return ['none|' + mob_cell('no time left to plan (the game read %d ms of the %d ms)' % (
                budget - left - 15, budget))]
        # (hands=party: the team planned only when a mate's hand was filled in - teamplan implied; none filled: no team
        # plan, and plan_round at today's 300 ms - AutoFarmer's 1500 asked for nothing)
        filled = any(u and u.get('tag') for u in used)
        skip = hands_party and not filled
        teamplan = (q.get('teamplan') == '1' or filled) and not skip
        if skip:
            pbudget = max(20, min(left, 300 - int((time.monotonic() - t0) * 1000) - 15))
        else:
            pbudget = int(left * 0.6) if teamplan else left
        plan = B.plan_round(state, me, foes, opts, n=int(fl('n', B.PLAN_N)),
                            horizon=int(fl('horizon')) if fl('horizon') > 0 else None,
                            budget_ms=pbudget, seed=int(fl('seed')) if q.get('seed') else None, prior=prior)
        plan['why'] = notes + plan['why']
        out = B.plan_lines(plan, foes, ids)
        if out and out[0].startswith('none|'):
            return out
        tp = None
        if teamplan:
            tleft = budget - int((time.monotonic() - t0) * 1000) - 15
            tp = B.plan_team(state, me, foes, opts, n=int(fl('n', B.PLAN_N)), budget_ms=max(20, tleft),
                             seed=int(fl('seed')) if q.get('seed') else None)
            out += B.team_lines(tp, foes)
        if hands_party:
            # (why a mate's hand wasn't used; each follower's order - or marker - kept for its next beat: advice only)
            out += ['teamnote|' + mob_cell(n) for n in party_notes]
            if P is not None:
                P.set_orders(tp['orders'] if tp else [], used, [f.name for f in foes], prnd)
        for k, f in enumerate(foes):
            out.append('|'.join(['foe', str(k), mob_cell(f.name), mob_cell(fhp[k]), str(f.maxhp), '1' if f.boss else '0',
                                 plate_x(plates[k]) if plates[k] else '']))
        out.append('planned|%d|%d|%d' % (plan.get('n') or 0, plan.get('ms') or 0, int((time.monotonic() - t0) * 1000)))
        return out
    except Exception as e:  # noqa: BLE001 - never into the server
        return ['none|the plan failed (%r)' % (e,)]


def places_busy(on):
    try:
        import placements
        placements.busy(on)
    except Exception:  # noqa: BLE001 - the request all the same
        pass


def places_want(r, game_dir=''):
    """the zone of reading r: its file's things built in placements' worker thread (once per zone: nothing when it's
    the zone last asked for) - /nav's, so /items?far=1 has them by the time the walker asks"""
    if not r or not r.get('zone'):
        return
    try:
        import placements
        placements.want_zone(r['zone'], game_dir)
        # (and its triggers - /zonepuzzle's -, read in the same thread: once per zone)
        if PUZZLE_WANTED.get('zone') != (r['zone'], game_dir):
            PUZZLE_WANTED['zone'] = (r['zone'], game_dir)
            import puzzlefile
            puzzlefile.want_zone(r['zone'], game_dir, zone_volumes)
    except Exception as e:  # noqa: BLE001 - never into /nav (said once a minute)
        if time.monotonic() >= PLACES_SAID['at']:
            PLACES_SAID['at'] = time.monotonic() + 60.0
            log(f"placements: the zone's file couldn't be asked for ({e!r})")


def items_now(goal_line='', goal=None, r=None, far=False):
    """(the zone's things [{name, pos, yaw, gid, template, key, keys, kind, src, quest}], why) - the game's memory's
    (navmem: items(), every thing with a name key that isn't a mob), and with far the zone's file's too (merge_things -
    placements.built_things for r's zone: as built so far, never read here). quest: the goal is about it (quest_item,
    its key over the whole list). None ([], why) when neither can be read"""
    items, why = nav_reader().items()
    things = items or []
    if far and r and r.get('zone'):
        placed = None
        try:
            import placements
            placed = placements.built_things(r['zone'], nav_reader().game_dir)
        except Exception as e:  # noqa: BLE001 - the live things alone (said once a minute)
            if time.monotonic() >= PLACES_SAID['at']:
                PLACES_SAID['at'] = time.monotonic() + 60.0
                log(f"/items: the zone's file couldn't be read ({e!r})")
        if placed is not None:
            # (the memory's not read - a new zone being looked at -: the file's things all the same; and the things the
            # zone's triggers' use events may be fired by - puzzlefile's as kept, never built here)
            try:
                import puzzlefile
                uses = puzzlefile.use_templates(r['zone'], nav_reader().game_dir)
            except Exception:  # noqa: BLE001 - none: as before
                uses = None
            things = merge_things(things, placed, uses)
        elif items is None:
            return [], why
        elif not things:
            why = "the zone's file is being read"
    elif items is None:
        return [], why
    ik = goal.get('item_key') if goal and goal.get('text') else ''
    key_hit = bool(ik) and any(ik in thing_keys(t) for t in things)
    for it in things:
        it['quest'] = quest_item(it, goal_line, goal, key_hit)
    return things, '' if things else why


def item_cell(v):
    """a field of an /items line: no | or line breaks in it; None as empty"""
    return '' if v is None else re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def item_line(it, me):
    """/items' line for a thing seen from me (the wizard's x, y, z): item|name|x|y|z|distance|quest|gid|key|template|src|
    kind - the first 8 as an older helper's"""
    return (f"item|{item_cell(it['name'])}|{it['pos'][0]:.1f}|{it['pos'][1]:.1f}|{it['pos'][2]:.1f}|"
            f"{math.hypot(it['pos'][0] - me[0], it['pos'][1] - me[1]):.0f}|{1 if it.get('quest') else 0}|"
            + '|'.join(item_cell(it.get(k)) for k in ('gid', 'key', 'template', 'src', 'kind')))


# ---------------------------------------------------------------- the quest's goal (vision\questmem.py)
# The goal line under the quest arrow and what it names, read from the game's memory (read-only) - exact, where the line
# AutoFarmer OCRs off the screen (&goal=) slips letters (2026-10-24: "Opiio (jn -rhe" for "Defeat Optio Agenor ..." - the
# quest's own mob kept away from); that one only when the memory's can't be read
GOAL_FRESH = 1.0            # s a goal reading is used again (the walker's /nav comes every step)
GOAL_LOCK = threading.Lock()
GOAL_LAST = {'at': -1e9, 'g': None, 'why': 'not read yet', 'said': None}


def goal_now(r=None, max_age=GOAL_FRESH, wait=0.0):
    """(g, why): the quest's active goal from the game's memory (navmem.goal - questmem.QuestMem.resolve: text, from,
    exact, shown, visible, distance, type, status, count, total, name, mob, item, npc, place, quest, quest_id, goal_id,
    ids_from) - a reading up to max_age s old used again; r: the navmem reading this request made (its quest helper ids
    stand in for the HUD's); wait: s its reader may take to be made (0: not waited for - the first one is, in a thread).
    None and why when it can't be read. Logged when the line, its kind or status change"""
    now = time.monotonic()
    with GOAL_LOCK:
        if now - GOAL_LAST['at'] < max_age:
            return GOAL_LAST['g'], GOAL_LAST['why']
    g, why = nav_reader().goal(r, wait=wait)
    with GOAL_LOCK:
        GOAL_LAST.update(at=time.monotonic(), g=g, why=why)
        said = (g['text'], g['type'], g['status'], g['from']) if g else ('', why)
        if said != GOAL_LAST['said']:
            GOAL_LAST['said'] = said
            if g:
                log(f"goal (memory, {g['ms']:.1f} ms): {g['text']!r} - {g['type'] or '?'} {g['status'] or ''}"
                    + (f" {g['count']}/{g['total']}" if g['total'] is not None else '')
                    + ''.join(f', {k} {g[k]!r}' for k in ('mob', 'item', 'npc') if g[k])
                    + ''.join(f', {k} {g[k]}' for k in ('item_key', 'mob_key') if g.get(k))
                    + f" (from {g['from']}{'' if g['exact'] else ', not exact'}; {g['ids_from']} ids)"
                    + ('' if g['shown'] in (None, g['text']) else f" - the HUD shows {g['shown']!r}")
                    + (f" - {g['why']}" if g['why'] else ''))
            else:
                log(f'goal (memory): none ({why})')
    return g, why


def goal_cell(v):
    """a field of /goal's and /nav's goal lines: no | or line breaks in it; None as empty"""
    return '' if v is None else re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def goal_lines(g, why):
    """/goal's answer (see the top) for a goal_now reading - the first ten lines byte for byte an older helper's, then
    itemkey|, mobkey|, npckeys|, namekey|, kindnum| (an older bot's NavGoal skips lines it doesn't know)"""
    if not g:
        return ['none|' + goal_cell(why or 'no goal line')]
    vis = '' if g['visible'] is None else ('1' if g['visible'] else '0')
    nk = tuple(g.get('npc_keys') or ('', '')) + ('', '')
    return [f"text|{goal_cell(g['text'])}|{g['from']}",
            f"shown|{vis}|{goal_cell(g['shown'])}|{goal_cell(g['distance'])}",
            f"kind|{goal_cell(g['type'])}|{goal_cell(g['status'])}",
            f"count|{goal_cell(g['count'])}|{goal_cell(g['total'])}",
            f"mob|{goal_cell(g['mob'])}", f"item|{goal_cell(g['item'])}", f"npc|{goal_cell(g['npc'])}",
            f"place|{goal_cell(g['place'])}",
            f"quest|{goal_cell(g['quest'])}|{goal_cell(g['quest_id'])}|{goal_cell(g['goal_id'])}|{g['ids_from']}",
            f"exact|{1 if g['exact'] else 0}",
            f"itemkey|{goal_cell(g.get('item_key'))}",
            f"mobkey|{goal_cell(g.get('mob_key'))}",
            f"npckeys|{goal_cell(nk[0])}|{goal_cell(nk[1])}",
            f"namekey|{goal_cell(g.get('name_key'))}",
            f"kindnum|{goal_cell(g.get('type_raw'))}"]


def goal_nav_line(g):
    """/nav's last line: goalline|text|type|status|count|total|shown - empty fields when the goal can't be read"""
    if not g:
        return 'goalline||||||'
    vis = '' if g['visible'] is None else ('1' if g['visible'] else '0')
    return '|'.join(['goalline'] + [goal_cell(g[k]) for k in ('text', 'type', 'status', 'count', 'total')] + [vis])


# The mobs read lately: (time, the wizard's x, y, z, {gid: (name, x, y, z, yaw)}) - /caught looks back along it
MOB_TRAIL = collections.deque(maxlen=400)
# Which way and how fast each mob walks (navroute.MobMotion - pure, no memory of its own), fed every mobs reading
MOTION = None


def motion():
    """the mobs' motion (navroute.MobMotion), made on first use"""
    global MOTION
    with NAV_LOCK:
        if MOTION is None:
            import navroute
            MOTION = navroute.MobMotion()
        return MOTION


def motion_feed(t, mobs, me):
    """a mobs reading at t (mobs_now's; me the wizard's x, y, z) into MOTION, and onto each mob: fit - (vx, vy) units /
    s, its straight line fitted (None not known) -, moving (True walking, False standing, None not known), speed, and vel
    - fit while it walks, else None: the route sweeps only a walking one (navroute's 'vel' and 'moving'). Never raises"""
    try:
        mm = motion()
        mm.update(t, mobs, me)
        for m in mobs:
            i = mm.info(m.get('gid'))
            m['fit'], m['moving'], m['speed'] = i.get('vel'), i.get('moving'), i.get('speed')
            m['vel'] = i.get('vel') if i.get('moving') else None
    except Exception as e:  # noqa: BLE001 - no motion: the mobs as they stand, as before
        for m in mobs:
            m.setdefault('fit', None), m.setdefault('moving', None), m.setdefault('vel', None)
        if time.time() - MOTION_SAID['at'] > 60:
            MOTION_SAID['at'] = time.time()
            log(f'mobs: their motion couldn\'t be worked out ({e!r})')


MOTION_SAID = {'at': 0.0}
CAUGHT_FRESH = 20.0     # the last reading at most this old (s) when a battle's first round is up
CAUGHT_NEAR = 450.0     # the mob that started it: the nearest, at most this far from the wizard in the last reading
CAUGHT_GAP = 2.0        # readings further apart than this (s) aren't followed back across


def caught_line(now=None):
    """/caught (see the top): which mob started the battle, and how far and how far off its facing the wizard was
    when it set off towards him - its steps followed back while each went his way"""
    trail = list(MOB_TRAIL)
    now = time.time() if now is None else now
    if not trail or now - trail[-1][0] > CAUGHT_FRESH:
        return 'none (no mobs read lately - they are read while walking with mob avoidance on)'
    _, me, mobs = trail[-1]
    near = sorted((math.hypot(v[1] - me[0], v[2] - me[1]), g) for g, v in mobs.items() if abs(v[3] - me[2]) <= 200)
    if not near:
        return 'none (no mob near)'
    d, gid = near[0]
    if d > CAUGHT_NEAR:
        return f'none (the nearest mob was {d:.0f} away)'
    k, came = len(trail) - 1, False
    # (standing in the battle already - neither moving: back to where they last moved)
    while (k > 0 and gid in trail[k - 1][2] and trail[k][0] - trail[k - 1][0] <= CAUGHT_GAP
           and math.dist(trail[k][1][:2], trail[k - 1][1][:2]) < 4
           and math.dist(trail[k][2][gid][1:3], trail[k - 1][2][gid][1:3]) < 4):
        k -= 1
    while k > 0:
        prev, cur = trail[k - 1], trail[k]
        if gid not in prev[2] or cur[0] - prev[0] > CAUGHT_GAP:
            break
        a, b = prev[2][gid], cur[2][gid]
        sx, sy = b[1] - a[1], b[2] - a[2]
        step = math.hypot(sx, sy)
        tx, ty = prev[1][0] - a[1], prev[1][1] - a[2]
        if step < 4 or (sx * tx + sy * ty) / (step * (math.hypot(tx, ty) or 1.0)) < 0.7:
            break
        came, k = True, k - 1
    # (where it stood when it noticed him: the reading before its first step his way - it turns to him first)
    if came and k > 0 and gid in trail[k - 1][2] and trail[k][0] - trail[k - 1][0] <= CAUGHT_GAP:
        k -= 1
    t0, me0, mobs0 = trail[k]
    name, x, y, _, yaw = mobs0[gid]
    dist = math.hypot(me0[0] - x, me0[1] - y)
    walked = caught_walking(trail, k, gid)
    off = ''
    if yaw is not None and dist > 1:
        c = ((me0[0] - x) * -math.sin(yaw) + (me0[1] - y) * -math.cos(yaw)) / dist
        off = f'{math.degrees(math.acos(max(-1.0, min(1.0, c)))):.0f}'
    # (and whether the helper took it as the quest's - the last /nav's own split, by the game's memory's goal: its name, its
    # kind, or one by a fight goal - left off the avoid list: the walker went into it for the quest)
    qs = MOBS_SHOWN.get('quest') or set()
    quest = 1 if gid in qs and now - (MOBS_SHOWN.get('at') or 0) <= CAUGHT_FRESH else 0
    return (f"caught|{name.replace('|', ' ')}|{dist:.0f}|{off}|{1 if came else 0}|{now - t0:.1f}|{quest}|"
            + ('' if walked is None else str(int(walked))))


def caught_walking(trail, k, gid):
    """was the mob gid walking (navroute.walking: MOVE_MIN, two squares) over the second of readings up to trail[k] -
    where it was when it noticed the wizard: True / False, None not known (too few readings)"""
    try:
        import navroute
        track, j = [], k
        while j >= 0 and gid in trail[j][2] and trail[k][0] - trail[j][0] <= navroute.MOTION_FIT + 0.2:
            if track and track[0][0] - trail[j][0] > CAUGHT_GAP:
                break
            v = trail[j][2][gid]
            track.insert(0, (trail[j][0], v[1], v[2], v[3]))
            j -= 1
        return navroute.walking(track, navroute.fit_velocity(track, navroute.MOTION_FIT + 0.2))
    except Exception:  # noqa: BLE001 - not known
        return None


ROUTER = None


def router(game_dir=''):
    """the route planner (vision\navroute.py: the zone's map from its .wad, read-only), made on first use"""
    global ROUTER
    with NAV_LOCK:
        if ROUTER is None:
            import navroute
            ROUTER = navroute.Planner(log=log, game_dir=game_dir)
        return ROUTER


ROUTER_TO = None


def router_to(game_dir=''):
    """a second route planner, for /navto (a walk to a spot of the bot's own: the potion seller) - the walker's
    (router) keeps its field, its carrot and its teleport waits"""
    global ROUTER_TO
    with NAV_LOCK:
        if ROUTER_TO is None:
            import navroute
            ROUTER_TO = navroute.Planner(log=log, game_dir=game_dir)
        return ROUTER_TO


# The potion sellers: the NPC templates with a PotionShopBehavior (the potion shop's window) - found by looking
# through every ObjectData template in Root.wad: Hilda Brewer in Wizard City's Commons and one in the Arcanum.
# Where each stands is read from the zone's own gamedata.bin (its placements - vision\placements.py: each one's
# template by the template id it carries), so a seller the game moves is still found
POTION_SELLERS = ('WC_PotionShopkeeper', 'AR-ARC-NPC13')
SELLERS_SEEN = {}


def potion_sellers(zone, game_dir=''):
    """[(name, (x, y, z)), ...] - the potion sellers placed in zone (from its gamedata.bin; read-only), kept; None
    when the zone's file can't be read"""
    if zone in SELLERS_SEEN:
        return SELLERS_SEEN[zone]
    import placements
    try:
        rows = placements.zone_placements(zone, game_dir)
    except Exception as e:  # noqa: BLE001 - not kept: asked again next time
        log(f'/seller {zone}: {e!r}')
        return None
    if rows is None:
        log(f"/seller {zone}: the zone's file can't be read")
        return None                                    # (not kept: asked again next time)
    out = [(r['template'], tuple(r['pos'])) for r in rows if r['template'] in POTION_SELLERS
           and all(math.isfinite(v) and abs(v) < 1e6 for v in r['pos'])]
    SELLERS_SEEN[zone] = out
    return out


# A zone's volumes - the spheres that do something when walked into (a door's teleport, a quest's goal): from its
# volumes.xml (read-only), each a name (hash 8b 04 e6 c6, then its length x2 in a byte - or x2+1 in a u32 - and the
# letters) and after it the centre (hashes 28/29/2a f8 b3 7d, each then a float) and the radius (df 33 f9 3a). The
# Dorm's way out is "Teleport_Out"; Ravenwood's door to the Commons "TeleportVol_Teleport location (to Commons)"
VOL_NAME, VOL_X, VOL_Y, VOL_Z, VOL_R = (struct.pack('<I', h) for h in (0xc6e6048b, 0x7db3f828, 0x7db3f829, 0x7db3f82a, 0x3af933df))
VOLUMES_SEEN = {}


def zone_volumes(zone, game_dir=''):
    """[(name, (x, y, z), radius), ...] - zone's volumes with a centre, kept; None when the zone's file can't be read"""
    if zone in VOLUMES_SEEN:
        return VOLUMES_SEEN[zone]
    import navgeo
    try:
        b = navgeo.read_wad_files(navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR), ['volumes.xml']).get('volumes.xml')
    except (OSError, ValueError) as e:
        log(f'/volumes {zone}: {e!r}')
        return None                                    # (not kept: asked again next time)
    b = b or b''
    out = []
    starts = [m.start() for m in re.finditer(re.escape(VOL_NAME), b)]
    for i, k in enumerate(starts):
        p = k + 4
        if p + 4 > len(b):
            continue
        n, p = (b[p] >> 1, p + 1) if not b[p] & 1 else (struct.unpack_from('<I', b, p)[0] >> 1, p + 4)
        name = b[p:p + n].decode('latin-1', 'replace').replace('|', '/').strip()
        seg = b[p + n:starts[i + 1] if i + 1 < len(starts) else len(b)]

        def num(h):
            j = seg.find(h)
            return struct.unpack_from('<f', seg, j + 4)[0] if 0 <= j and j + 8 <= len(seg) else None
        x, y, z, r = num(VOL_X), num(VOL_Y), num(VOL_Z), num(VOL_R)
        if name and None not in (x, y, z) and all(math.isfinite(v) and abs(v) < 1e6 for v in (x, y, z)):
            out.append((name, (x, y, z), r if r is not None and math.isfinite(r) else 0.0))
    VOLUMES_SEEN[zone] = out
    return out


def navto_lines(target, game_dir, avoid=False, mob_near=None, cone=None, spare=0.0, duels=False):
    """/navto's answer: where the wizard is (the game's memory, read-only) and the route to target - a spot of the
    bot's own - planned by router_to along the zone's nav graph; avoid: kept mob_near away from every mob - but those
    within spare of target (a puzzle's guard camp walked to, to fight it: its mobs aren't routed round); duels (with
    avoid): out of other players' battles too (duels_now - kept off where there's room; /navto doesn't wait)"""
    nm = nav_reader()
    r, why = nm.read(path=False, wait=3.0)
    if r is None:
        return ['ERR ' + why]
    if r['pos'] is None or r['yaw'] is None or not r['zone']:
        return ['ERR the game\'s memory can\'t say where the wizard is']
    lines = ['ok|1', 'zone|' + r['zone'], 'pos|' + '|'.join(f'{c:.2f}' for c in r['pos']) + f"|{r['yaw']:.4f}"]
    try:
        p = router_to(nm.game_dir or game_dir)
        geo = p._geo(r['zone'])
        # (walked links only - no teleports on the way to a spot of the bot's own: nothing there to wait at one)
        if geo.why or geo.navgraph() is None:
            path = None
        else:
            P, adj = geo.navgraph()
            jumps = {(a, b) for a in range(len(P)) for b, _, j in adj[a] if j}
            path = geo.nav_path(r['pos'], target, jumps)
        # (all the mobs kept away from - avoid: mobavoid - on the way to the potion seller none is the quest's)
        import navroute
        # (kept on the map's rings and in the trail /caught looks back along, as /nav's)
        mobs = mobs_now(r, '', trail=True)[0] if avoid else None
        spared = set()
        if mobs and spare and spare > 0:
            # (the camp walked to: not kept away from - on the map as the ones walked to)
            spared = {m['gid'] for m in mobs if math.hypot(m['pos'][0] - target[0], m['pos'][1] - target[1]) <= spare}
            mobs = [m for m in mobs if math.hypot(m['pos'][0] - target[0], m['pos'][1] - target[1]) > spare]
        if avoid:
            MOBS_SHOWN.update(quest=spared, near=mob_near or navroute.MOB_NEAR, avoid=True, at=time.time(), cone=cone or navroute.MOB_CONE)
        res = p.route(dict(r, goal=tuple(target), hops=0, path=path or []), wait=False, mobs=mobs or None,
                      mob_near=mob_near or navroute.MOB_NEAR, cone=cone or navroute.MOB_CONE,
                      duels=(duels_now()[0] or None) if avoid and duels else None, speed=my_speed())
    except Exception as e:  # noqa: BLE001 - no route: the bot steers straight at the spot
        log(f'/navto: {e!r}')
        res = {'why': f'the planner failed ({e!r})'}
    if res.get('aim') is None:
        return lines + ['route|||', 'routewhy|' + (res.get('why') or '?')]
    return lines + [f"route|{res['aim'][0]:.1f}|{res['aim'][1]:.1f}|{res['left']:.0f}"]


# ---------------------------------------------------------------- a blocked way (vision\puzzlefile.py)
# What holds the walker in front of a dungeon's gate, what the zone's triggers say opens it, and whether a route goes
# through it - for AutoFarmer's Puzzle.ahk (the way to the goal blocked for good at one spot: before telling the user, it
# tries what usually opens one). Memory read-only (navmem's objects thread), files read-only; the answers kept, so the
# walker's 1 s steps aren't slowed: /blockers reads only the few objects it lists, /zonepuzzle and /navpass are kept
BLOCKERS_SAID = {'at': 0.0}     # (when a failure to read the zone's file's blockers may be logged again)


def blocker_cell(v):
    return '' if v is None else re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def blockers_now(r, nm):
    """(the doors of reading r's zone [{template, pos, gid, src, state, start}], why) - the game's memory's
    (navmem.blockers, src mem: state its ObjectStateBehavior's now - statemem.py, "" not known) and the zone's file's
    (placements.built_things, src file: a placement whose template is a blocker's - puzzlefile.is_blocker - not an NPC;
    as built so far, never built here; state its starting one). start: the file's starting state (a memory door's: its
    template's placement nearest it - puzzlefile.match_start; "" none). None and why when the memory's can't be read
    (not read isn't gone: the walker takes a door missing from memory for the way opening)"""
    import puzzlefile
    live, why = nm.blockers()
    if live is None:
        return None, why or "the zone's objects can't be read"
    out = [{'template': b.get('template') or b.get('name') or '', 'pos': tuple(b['pos']), 'gid': b.get('gid'),
            'src': 'mem', 'state': b.get('state') or '', 'start': ''} for b in live]
    placed = None
    try:
        import placements
        placed = placements.built_things(r['zone'], nm.game_dir) if r.get('zone') else None
    except Exception as e:  # noqa: BLE001 - the memory's alone (said once a minute)
        if time.monotonic() >= BLOCKERS_SAID['at']:
            BLOCKERS_SAID['at'] = time.monotonic() + 60.0
            log(f"/blockers: the zone's file couldn't be read ({e!r})")
    gids = set()
    files = []
    for p in placed or ():
        tpl = p.get('template') or ''
        if not puzzlefile.is_blocker(tpl) or p.get('kind') == 'npc':
            continue
        gid = f"f:{tpl}:{p['n']}" if p.get('n') is not None else ''
        if not gid or gid in gids:
            gid = f"f:{tpl}@{p.get('at')}"
        gids.add(gid)
        files.append({'template': tpl, 'pos': tuple(p['pos']), 'gid': gid, 'src': 'file', 'state': p.get('state') or '',
                      'start': p.get('state') or ''})
    # (each memory door's starting state by the file - its template's placement nearest it)
    for d, start in zip(out, puzzlefile.match_start(out, files, ITEM_NEAR)):
        d['start'] = start
    return out + files, ''


def blocker_lines(r, nm):
    """/blockers' answer for reading r: door|template|x|y|z|distance|gid|src|state|start each, nearest first; none; ERR
    <why>"""
    doors, why = blockers_now(r, nm)
    if doors is None:
        return ['ERR ' + blocker_cell(why)]
    me = r.get('pos') or (0.0, 0.0, 0.0)
    doors.sort(key=lambda d: math.hypot(d['pos'][0] - me[0], d['pos'][1] - me[1]))
    return [f"door|{blocker_cell(d['template'])}|{d['pos'][0]:.1f}|{d['pos'][1]:.1f}|{d['pos'][2]:.1f}|"
            f"{math.hypot(d['pos'][0] - me[0], d['pos'][1] - me[1]):.0f}|{blocker_cell(d['gid'])}|{d['src']}|"
            f"{blocker_cell(d['state'])}|{blocker_cell(d.get('start'))}" for d in doors] or ['none']


def use_cells(vals):
    """a /zonepuzzle use line's list field: its values ; apart (no |, ; or line breaks in one)"""
    return ';'.join(blocker_cell(v).replace(';', ',') for v in vals or ())


def zonepuzzle_lines(zone, game_dir=''):
    """/zonepuzzle's answer: the zone's triggers (puzzlefile.zone_triggers - files only, kept per zone): kill|template,
    spawn|object|x|y|z, hint|volume|x|y|z|r|text, use|event|targets|states|acts, useobj|event|template|x|y|z|how; none;
    ERR <why>"""
    import puzzlefile
    t = puzzlefile.zone_triggers(zone, game_dir, zone_volumes)
    if t['why'] and t['why'] != 'no triggers.xml':
        return ['ERR ' + blocker_cell(t['why'])]
    out = ['kill|' + blocker_cell(k) for k in t['kills']]
    for name, pos in t['spawns']:
        out.append('spawn|' + blocker_cell(name) + '|' + ('||' if pos is None else '|'.join(f'{c:.1f}' for c in pos)))
    for vol, (x, y, z), rad, text in t['hints']:
        out.append(f'hint|{blocker_cell(vol)}|{x:.1f}|{y:.1f}|{z:.1f}|{rad:.0f}|{blocker_cell(text)}')
    # (the event first: an older bot reads it alone; then what its triggers do)
    did = {u[0]: u[1:] for u in t.get('usedo') or ()}
    for e in t['uses']:
        tg, st, ac = did.get(e, ((), (), ()))
        out.append(f'use|{blocker_cell(e)}|{use_cells(tg)}|{use_cells(st)}|{use_cells(ac)}')
    for u in t.get('useobjs') or ():
        x, y, z = u['pos'][:3]
        out.append(f"useobj|{blocker_cell(u['event'])}|{blocker_cell(u['template'])}|{x:.1f}|{y:.1f}|{z:.1f}|"
                   f"{blocker_cell(u.get('how'))}")
    return out or ['none']


NAVPASS_REACH = 800.0       # the nav graph's way ending further than this from where it's asked to go: it doesn't go there
NAVPASS_KEPT = 512
NAVPASS = collections.OrderedDict()     # (zone, game folder, the question rounded) -> answer
NAVPASS_LOCK = threading.Lock()
NAVPASS_JUMPS = {}                       # (zone, id of its nav graph's links) -> its teleport links


def navpass_lines(q, nm):
    """/navpass's answer: pass|1/0|nearest|length - the way along the zone's nav graph (walked links only, as /navto's)
    from f to t, and whether it goes through v (puzzlefile.path_pass: within vr of it, or across its line square to f -> v
    within 2 vr) - or ERR <why>. The zone: zone=, else the wizard's (the game's memory, read-only). Kept per question"""
    import puzzlefile
    try:
        f = [float(q[k]) for k in ('fx', 'fy')]
        t = [float(q[k]) for k in ('tx', 'ty')]
        vx, vy = float(q['vx']), float(q['vy'])
        vr = float(q.get('vr') or 200.0)
        # (a height not known - fz= / tz= empty: the floor under it, the nav graph's nearest node's, below)
        fz, tz = (float(q[k]) if q.get(k, '') != '' else None for k in ('fz', 'tz'))
    except (KeyError, ValueError):
        return ['ERR fx, fy, fz, tx, ty, tz, vx, vy wanted'], 400
    if not all(math.isfinite(c) and abs(c) < 1e6 for c in f + t + [vx, vy, vr] + [c for c in (fz, tz) if c is not None]):
        return ['ERR the numbers must be finite'], 400
    zone = q.get('zone', '')
    if not zone:
        r, why = nm.read(path=False)
        if r is None:
            return ['ERR ' + why], 200
        zone = r.get('zone') or ''
        if not zone:
            return ['ERR the game\'s memory can\'t say which zone the wizard is in'], 200
    gd = nm.game_dir
    key = (zone, gd) + tuple(round(c) for c in f + t + [vx, vy, vr]) + tuple(None if c is None else round(c) for c in (fz, tz))
    with NAVPASS_LOCK:
        got = NAVPASS.get(key)
        if got is not None:
            NAVPASS.move_to_end(key)
            return list(got), 200
    try:
        geo = router_to(gd)._geo(zone)
        g = None if geo.why else geo.navgraph()
        if g is None:
            ans = ['ERR the zone has no nav graph' + (f' ({geo.why})' if geo.why else '')]
        else:
            P, adj = g
            jk = (zone, id(adj))
            jumps = NAVPASS_JUMPS.get(jk)
            if jumps is None:
                # (walked links only - a teleport isn't a way through a gate)
                jumps = {(a, b) for a in range(len(P)) for b, _, j in adj[a] if j}
                if len(NAVPASS_JUMPS) > 8:
                    NAVPASS_JUMPS.clear()
                NAVPASS_JUMPS[jk] = jumps

            def floor_z(x, y):
                """the height of the nav graph's node nearest (x, y) across the ground"""
                return float(P[int(np.argmin(np.hypot(P[:, 0] - x, P[:, 1] - y))), 2])
            f = (f[0], f[1], fz if fz is not None else floor_z(f[0], f[1]))
            t = (t[0], t[1], tz if tz is not None else floor_z(t[0], t[1]))
            path = geo.nav_path(f, t, jumps)
            if not path:
                ans = ['ERR no way on the nav graph from there']
            elif math.hypot(path[-1][0] - t[0], path[-1][1] - t[1]) > NAVPASS_REACH:
                ans = [f'ERR the nav graph\'s way ends {math.hypot(path[-1][0] - t[0], path[-1][1] - t[1]):.0f} from there']
            else:
                ok, near, length = puzzlefile.path_pass(list(path) + [t], vx, vy, vr, f[0], f[1])
                ans = [f'pass|{1 if ok else 0}|{near:.0f}|{length:.0f}']
    except Exception as e:  # noqa: BLE001 - not known: the bot's own fallback (its half-plane test)
        log(f'/navpass: {e!r}')
        return ['ERR ' + blocker_cell(repr(e))], 200
    with NAVPASS_LOCK:
        NAVPASS[key] = list(ans)
        while len(NAVPASS) > NAVPASS_KEPT:
            NAVPASS.popitem(last=False)
    return ans, 200


def mob_cone(q):
    """the mobs' sight cone asked for: (degrees wide, long) from cone= / sight= (0 wide: none), else the planner's"""
    import navroute
    try:
        wide = float(q['cone']) if q.get('cone', '') != '' else navroute.MOB_CONE[0]
        far = float(q['sight']) if q.get('sight', '') != '' else navroute.MOB_CONE[1]
    except ValueError:
        return navroute.MOB_CONE
    return (min(180.0, max(0.0, wide)), min(3000.0, max(0.0, far)))


def mob_avoid(q):
    """(how far all round, (degrees wide, long) in front) to keep from the mobs, as asked: mobr= how far they notice
    you; shape= 1 a circle all round, 2 a semi-circle in front, 3 a cone in front cone= degrees wide (a semi-circle or
    cone: navroute.MOB_BODY all round as well). No shape=: mobr all round and the cone= / sight= cone (mob_cone)"""
    import navroute

    def num(k, default, lo, hi):
        try:
            v = float(q.get(k) or 0) or default
        except ValueError:
            v = default
        return min(hi, max(lo, v))
    rng = num('mobr', 300.0, 100.0, 3000.0)
    shape = q.get('shape', '')
    # (a semi-circle or cone's reach all round: body= - the bot raises it when a mob catches the wizard from the side)
    body = min(rng, num('body', navroute.MOB_BODY, 40.0, 1500.0))
    if shape == '1':
        return rng, (0.0, 0.0)
    if shape == '2':
        return body, (180.0, rng)
    if shape == '3':
        return body, (num('cone', 60.0, 5.0, 180.0), rng)
    return min(1500.0, rng), mob_cone(q)


def my_speed():
    """the wizard's walking speed (units / s - MobMotion's, off the readings), None not known yet"""
    try:
        return motion().my_speed()
    except Exception:  # noqa: BLE001 - not known: navroute's WIZ_SPEED
        return None


def route_lines(r, game_dir, avoid=None, mob_near=None, cone=None, arc_r=0.0, duels=None, wall_wait=False):
    """/nav's route lines for a reading r (made with path=True); avoid: the mobs to keep away from - mob_near round
    them, out of their sight cone (degrees wide, long) in front, a walking one's swept along its way; arc_r: the
    wizard's turning circle - field 13 says whether turning walking on round to the aim stays clear of the walls;
    duels: other players' battles to keep out of (duels_now - duelavoid) - fields 14-16 the wait for one on the way;
    wall_wait: a line of mobs' wall with no way round is waited at as a mob on the way (fields 8-11 - the mobwall
    setting; off: walked through its gap at once, as before)"""
    speed = my_speed()
    try:
        import navroute
        res = router(game_dir).route(r, mobs=avoid or None, mob_near=mob_near or navroute.MOB_NEAR, cone=cone or navroute.MOB_CONE,
                                     duels=duels or None, speed=speed, wall_wait=wall_wait)
    except Exception as e:  # noqa: BLE001 - no route: the walker steers at the target
        log(f'route: {e!r}')
        res = {'why': f'the planner failed ({e!r})'}
    # (blind|ahead|behind|in: the mob whose ring or sight the straight line to the quest's target - the arrow's way -
    # comes into, backing up would, the wizard's in now: for the walker's moves off the route; names, empty none)
    blind = []
    if avoid:
        try:
            import navroute
            a, b, c = router(game_dir).blind(r, avoid, mob_near or navroute.MOB_NEAR, cone or navroute.MOB_CONE, speed=speed)
            blind = ['blind|' + '|'.join(s.replace('|', ' ') for s in (a, b, c))]
        except Exception as e:  # noqa: BLE001 - no check: as before
            log(f'blind: {e!r}')
    if res.get('aim') is None:
        return ['route|||', 'routewhy|' + (res.get('why') or '?')] + blind
    # (fields 5-7: right at a teleport on the game's path - the seconds waited there, and where it is; 8-11: a mob
    # on the way the route can't go round - the seconds waited for it to move off, where it is, its name; 12: the
    # wizard inside a mob's ring or sight - its name - the aim leads out of it)
    jump = res.get('jump')
    tail = '||' if jump is None else f"{jump:.0f}|{res['jump_at'][0]:.0f}|{res['jump_at'][1]:.0f}"
    mob = res.get('mob')
    tail += '||||' if mob is None else f"|{mob:.0f}|{res['mob_at'][0]:.0f}|{res['mob_at'][1]:.0f}|{res['mob_name'].replace('|', ' ')}"
    tail += '|' + (res.get('escape') or '').replace('|', ' ')
    arc = None
    if arc_r and arc_r > 0:
        try:
            arc = router(game_dir).arc_clear(r, res['aim'], arc_r)
        except Exception as e:  # noqa: BLE001 - not known: the walker's own limit
            log(f'arc: {e!r}')
    tail += '|' + ('' if arc is None else str(arc))
    # (14-16: another player's battle on the way the route can't go round - the seconds waited for it, where it is)
    duel = res.get('duel')
    tail += '|||' if duel is None else f"|{duel:.0f}|{res['duel_at'][0]:.0f}|{res['duel_at'][1]:.0f}"
    return [f"route|{res['aim'][0]:.1f}|{res['aim'][1]:.1f}|{res['left']:.0f}|" + tail] + blind


def map_route(r, game_dir, avoid, duels):
    """/navmap's route: the walker's own planner (router) asked as the walker last asked it - its mobs (avoid: the
    ones kept away from, None not), MOBS_SHOWN's reach and cone, the battles it kept out of (duels: DUELS_SHOWN's,
    None not known) and the wizard's speed - so the map's asks (every second while the dashboard's Map is open) never
    hand the walker a field made for other mobs or battles than its own (one with no battle in it: its next ask walked
    at the battle, or stood waiting for it with a way round - the field flipping each second). Not a wait (wait=False);
    None when it fails (the map without it)"""
    try:
        import navroute
        return router(game_dir).route(r, wait=False, mobs=avoid, mob_near=MOBS_SHOWN.get('near') or navroute.MOB_NEAR,
                                      cone=MOBS_SHOWN.get('cone') or navroute.MOB_CONE, duels=duels or None,
                                      speed=my_speed())
    except Exception:  # noqa: BLE001 - the map without it
        return None


def duels_now():
    """(the other players' battles to keep out of [{pos, gid, template, phase, players, ...}], why) - navmem's duels():
    the zone's duel circles that are active, not the wizard's own, with a player in them (or not known); ([], why) when
    they can't be read (an older reader, the zone being looked at): nothing kept out of, as before. Never raises"""
    try:
        nm = nav_reader()
        if not hasattr(nm, 'duels'):
            return [], 'the reader has no duels'
        got, why = nm.duels()
    except Exception as e:  # noqa: BLE001 - none: as before
        return [], f'the battles couldn\'t be read ({e!r})'
    if got is None:
        return [], why or '?'
    return [d for d in got if d.get('active', True) and not d.get('mine') and d.get('players') != 0], ''


def duel_lines(duels, r):
    """/duels' answer: duel|template|x|y|z|distance|phase|parts|players|gid|active|mine one a duel circle in the zone
    (nearest first), or none"""
    me = (r or {}).get('pos') or (0.0, 0.0, 0.0)
    out = []
    for d in sorted(duels or [], key=lambda d: math.hypot(d['pos'][0] - me[0], d['pos'][1] - me[1])):
        out.append('|'.join(['duel', mob_cell(d.get('template')), f"{d['pos'][0]:.1f}", f"{d['pos'][1]:.1f}",
                             f"{d['pos'][2]:.1f}", f"{math.hypot(d['pos'][0] - me[0], d['pos'][1] - me[1]):.0f}",
                             mob_cell(d.get('phase_name') or d.get('phase')), mob_cell(d.get('parts')),
                             mob_cell(d.get('players')), mob_cell(d.get('gid')), mob_cell(d.get('active')),
                             mob_cell(d.get('mine'))]))
    return out or ['none']


def noplace_line(r):
    """/nav's noplace|<1 no place / 0 a place / "" not known>|<s the 1 has held for this quest and goal - with 1 only>"""
    np_, held = r.get('noplace'), r.get('noplace_s')
    return (f"noplace|{'' if np_ is None else int(np_)}|"
            + (f'{held:.1f}' if np_ == 1 and isinstance(held, (int, float)) else ''))


def nav_lines(r, with_path):
    """/nav's answer from a navmem reading (fields that can't be read for sure left empty)"""
    def xyz(v):
        return '|'.join(f'{c:.2f}' for c in v) if v is not None else '||'
    have_pos = r['pos'] is not None and r['yaw'] is not None
    have_goal = r['goal'] is not None and r['hops'] is not None
    lines = ['ok|1',
             'zone|' + (r['zone'] or ''),
             'pos|' + (xyz(r['pos']) + f"|{r['yaw']:.4f}" if have_pos else '|||'),
             'target|' + xyz(r['target']),
             'goal|' + (xyz(r['goal']) + f"|{r['hops']}" if have_goal else '|||'),
             'dist|' + ('' if r['dist'] is None else f"{r['dist']:.1f}"),
             'quest|' + '|'.join('' if r[k] is None else str(r[k]) for k in ('enabled', 'quest', 'goalid')),
             noplace_line(r)]
    if with_path:
        lines.append('path|' + ';'.join(f'{x:.1f},{y:.1f},{z:.1f}' for x, y, z in (r['path'] or ())))
    return lines


NAV_RETRY = 30


class ZoneLayers:
    """One zone's static map layers - walkable floor, water, obstacles, the nav graph - decoded once, drawn
    in NAV_TILE tiles on first use at a scale (upp: game units per pixel). Pixel (px, py) of the zone's
    picture at a scale is world (px * upp, -py * upp): +X to the right, +Y up. No zone file: no layers
    (why says why), the map is the overlay on a blank background. step (the overlay's map - zone_layers): called
    before each collision shape is decoded and drawn into the layers - it may wait there (gate_wait)"""

    def __init__(self, zone, game_dir='', step=None):
        self.zone, self.why = zone, ''
        self.tris = {}          # 'floor' / 'water': (F, 3, 2) world XY triangles, with (F, 4) bounds
        self.polys = {}         # 'floor' / 'obst': [(k, 2) polygon], with (n, 4) bounds
        self.tz = {}            # 'floor': (F,) each floor triangle's height; 'floorpoly': each walkable box's top
        self.zlo = self.zhi = 0.0  # the floor's height range (for its shading)
        self.segs = np.zeros((0, 2, 2))
        self.nodes = np.zeros((0, 2))
        self.bounds = None      # x1, y1, x2, y2 of everything
        try:
            import navgeo
            d = navgeo.load_zone(zone, game_dir or navgeo.GAME_DIR, step=step)
        except Exception as e:  # noqa: BLE001 - no map, just the overlay
            self.why = str(e) if isinstance(e, FileNotFoundError) else f"the zone file can't be read ({e!r})"
            return
        nav, bcd = d['nav'], d['bcd'] or []
        P = nav['positions'].astype(np.float64) if nav is not None and len(nav['positions']) else np.zeros((0, 3))
        if nav is not None and len(nav['edges']):
            self.segs = P[nav['edges']][:, :, :2]
        self.nodes = P[:, :2]
        tris = {'floor': [], 'water': []}
        polys = {'floor': [], 'obst': []}
        tz = {'floor': [], 'floorpoly': []}
        for s in bcd:
            if step is not None:
                step()
            cat = s['category_flags']
            if s['type'] == 'mesh':
                kind = 'floor' if cat & 0x2 else 'water' if cat & 0x40 else None
                if kind and len(s['mesh']['faces']):
                    v, f = navgeo.mesh_world(s)
                    tris[kind].append(v[f][:, :, :2])
                    if kind == 'floor':
                        tz['floor'].append(v[f][:, :, 2].mean(1))
            elif cat & 0x2:                                          # a walkable box (a platform)
                ps = [p for p in navgeo.footprint(s, 24) if len(p) >= 3]
                ab = navgeo.aabb(s)
                polys['floor'] += ps
                tz['floorpoly'] += [ab[1][2] if ab is not None else 0.0] * len(ps)
            elif cat & 0x81 and s['type'] in ('box', 'cylinder', 'sphere', 'tube'):
                # an obstacle - unless it hangs over the floor (an arch's top, a roof): its bottom higher
                # than a wizard over every nav node round it
                ab = navgeo.aabb(s)
                if ab is not None and len(P):
                    lo, hi = ab
                    near = (P[:, 0] > lo[0] - 300) & (P[:, 0] < hi[0] + 300) & (P[:, 1] > lo[1] - 300) & (P[:, 1] < hi[1] + 300)
                    if near.any() and lo[2] > P[near, 2].max() + 180:
                        continue
                polys['obst'] += [p for p in navgeo.footprint(s, 28) if len(p) >= 3]
        self.tz = {'floor': np.concatenate(tz['floor']) if tz['floor'] else np.zeros(0), 'floorpoly': np.array(tz['floorpoly'])}
        allz = np.concatenate([self.tz['floor'], self.tz['floorpoly']])
        if len(allz):
            self.zlo, self.zhi = float(np.percentile(allz, 2)), float(np.percentile(allz, 98))
        allb = []
        for k, t in tris.items():
            t = np.concatenate(t) if t else np.zeros((0, 3, 2))
            b = np.concatenate([t.min(1), t.max(1)], 1) if len(t) else np.zeros((0, 4))
            self.tris[k] = (t, b)
            allb.append(b)
        for k, ps in polys.items():
            b = np.array([[*p.min(0), *p.max(0)] for p in ps]) if ps else np.zeros((0, 4))
            self.polys[k] = (ps, b)
            allb.append(b)
        if len(self.nodes):
            allb.append(np.concatenate([self.nodes, self.nodes], 1))
        allb = np.concatenate(allb) if allb else np.zeros((0, 4))
        if len(allb):
            self.bounds = (allb[:, 0].min(), allb[:, 1].min(), allb[:, 2].max(), allb[:, 3].max())
        else:
            self.why = 'the zone file has no floor or nav graph'

    def tile(self, upp, i, j, clear=False):
        """tile (i, j) at upp as an RGB picture, or None if nothing is in it; clear (the overlay over the game -
        overlay.py): RGBA instead, clear where nothing is, the floor, water and rim see-through (OV_FLOOR_A,
        OV_WATER_A, OV_RIM_A), the nav graph and obstacles over them as on the dashboard's"""
        T, S = NAV_TILE, NAV_SS
        pad = 3                                                  # (for the floor's rim, then cut off)
        wx1, wx2 = (i * T - pad) * upp, ((i + 1) * T + pad) * upp
        wy1, wy2 = -((j + 1) * T + pad) * upp, -(j * T - pad) * upp
        if self.bounds is None or wx2 < self.bounds[0] or wx1 > self.bounds[2] or wy2 < self.bounds[1] or wy1 > self.bounds[3]:
            return None
        size = (T + 2 * pad) * S

        def px(a):
            """world XY (..., 2) -> this tile's big pixels, as a flat list for ImageDraw"""
            a = np.asarray(a, dtype=np.float64)
            return np.stack([(a[..., 0] / upp - i * T + pad) * S, (-a[..., 1] / upp - j * T + pad) * S], -1)

        def inside(b):
            return (b[:, 2] >= wx1) & (b[:, 0] <= wx2) & (b[:, 3] >= wy1) & (b[:, 1] <= wy2)

        from PIL import ImageDraw, ImageFilter
        ground = Image.new('L', (size, size), 0)                  # 0 nothing, 1 floor, 2 water
        dg = ImageDraw.Draw(ground)
        shade = Image.new('L', (size, size), 0)                   # the floor's height, 0-255 over the zone's range
        dsh = ImageDraw.Draw(shade)
        span = max(1.0, self.zhi - self.zlo)

        def level(z):
            return int(round(255 * min(1.0, max(0.0, (z - self.zlo) / span))))
        for kind, val in (('floor', 1), ('water', 2)):
            t, b = self.tris[kind]
            sel = np.nonzero(inside(b))[0]
            if kind == 'floor' and len(sel):
                sel = sel[np.argsort(self.tz['floor'][sel], kind='stable')]          # higher floors over lower
            for k, tri in zip(sel.tolist(), px(t[sel]).tolist()):
                dg.polygon([tuple(q) for q in tri], fill=val, outline=val)
                if kind == 'floor':
                    dsh.polygon([tuple(q) for q in tri], fill=level(self.tz['floor'][k]), outline=level(self.tz['floor'][k]))
            if kind == 'floor':
                ps, b = self.polys['floor']
                for k in np.nonzero(inside(b))[0] if len(b) else ():
                    dg.polygon([tuple(q) for q in px(ps[k]).tolist()], fill=val, outline=val)
                    lv = level(self.tz['floorpoly'][k]) if k < len(self.tz['floorpoly']) else 0
                    dsh.polygon([tuple(q) for q in px(ps[k]).tolist()], fill=lv, outline=lv)
        g = np.asarray(ground)
        sh = np.asarray(shade).astype(np.float32)[..., None] / 255.0
        solid = Image.fromarray(((g > 0) * 255).astype(np.uint8))
        rim = (np.asarray(solid.filter(ImageFilter.MaxFilter(2 * S + 1))) > 0) & (g == 0)
        rgb = np.empty((size, size, 3), np.uint8)
        rgb[:] = MAP_BG
        floor_rgb = height_rgb(sh[..., 0])
        rgb[g == 1] = floor_rgb[g == 1]
        rgb[g == 2] = MAP_WATER
        rgb[rim] = MAP_RIM
        img = Image.fromarray(rgb).convert('RGBA')
        if clear:
            a = np.zeros((size, size), np.uint8)
            a[g == 1] = OV_FLOOR_A
            a[g == 2] = OV_WATER_A
            a[rim] = OV_RIM_A
            img.putalpha(Image.fromarray(a))
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        dl = ImageDraw.Draw(layer)
        segs = self.segs
        if len(segs):
            b = np.concatenate([segs.min(1), segs.max(1)], 1)
            for (x1, y1), (x2, y2) in px(segs[inside(b)]).tolist():
                dl.line([(x1, y1), (x2, y2)], fill=MAP_NAV + (46,), width=S)
        nb = np.concatenate([self.nodes, self.nodes], 1) if len(self.nodes) else np.zeros((0, 4))
        r = 1.2 * S
        for x, y in px(self.nodes[inside(nb)]).tolist() if len(nb) else ():
            dl.ellipse([x - r, y - r, x + r, y + r], fill=MAP_NAV + (70,))
        img.alpha_composite(layer)
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        dl = ImageDraw.Draw(layer)
        ps, b = self.polys['obst']
        for k in np.nonzero(inside(b))[0] if len(b) else ():
            dl.polygon([tuple(q) for q in px(ps[k]).tolist()], fill=MAP_OBST + (105,), outline=MAP_OBST + (215,), width=S)
        img.alpha_composite(layer)
        # (Pillow premultiplies before an RGBA BOX resize, so the clear one's edges get no dark halo)
        img = (img if clear else img.convert('RGB')).resize((T + 2 * pad, T + 2 * pad), Image.BOX)
        return img.crop((pad, pad, pad + T, pad + T))


NAV_ZONES = collections.OrderedDict()       # zone -> ZoneLayers
NAV_TILES = collections.OrderedDict()       # (zone, upp, i, j) -> picture or None
OV_TILES = collections.OrderedDict()        # the overlay's (render_navmap clear=True): the same keys -> RGBA or None
MAP_LOCK = threading.Lock()
MAP_FONTS = {}


def drop_tiles(zone):
    """a zone's kept tiles let go - the dashboard map's (NAV_TILES) and the overlay's (OV_TILES)"""
    for tiles in (NAV_TILES, OV_TILES):
        for k in [k for k in tiles if k[0] == zone]:
            del tiles[k]


def zone_layers(zone, game_dir, step=None):
    """zone's ZoneLayers (kept: the last NAV_ZONES_KEPT zones) - read now if it isn't kept, with step (ZoneLayers')"""
    z = NAV_ZONES.get(zone)
    # (a zone whose file couldn't be read - still downloading or being written while it loads - is tried
    # again after NAV_RETRY seconds rather than kept as 'no map' for the whole visit)
    if z is not None and z.why and time.time() - getattr(z, 'made', 0) > NAV_RETRY:
        NAV_ZONES.pop(zone, None)
        drop_tiles(zone)
        z = None
    if z is None:
        t0 = time.perf_counter()
        z = NAV_ZONES[zone] = ZoneLayers(zone, game_dir, step)
        z.made = time.time()
        log(f'/navmap: zone {zone} read in {(time.perf_counter() - t0) * 1000:.0f} ms' + (f' - {z.why}' if z.why else ''))
        while len(NAV_ZONES) > NAV_ZONES_KEPT:
            old, _ = NAV_ZONES.popitem(last=False)
            drop_tiles(old)
    NAV_ZONES.move_to_end(zone)
    return z


def map_font(size):
    from PIL import ImageFont
    if size not in MAP_FONTS:
        for name in ('segoeuib.ttf', 'segoeui.ttf', 'arialbd.ttf', 'arial.ttf'):
            try:
                MAP_FONTS[size] = ImageFont.truetype(name, size)
                break
            except OSError:
                pass
        else:
            MAP_FONTS[size] = ImageFont.load_default()
    return MAP_FONTS[size]


def height_rgb(level):
    """the floor's colour for its height (0 the zone's lowest - blue - to 1 its highest - red; MAP_HEIGHT_*), per pixel:
    level (H, W) floats -> (H, W, 3) uint8"""
    lv = np.clip(np.asarray(level, np.float32), 0.0, 1.0)
    cols = np.array(MAP_HEIGHT_RGB, np.float32)
    return np.stack([np.interp(lv, MAP_HEIGHT_STOPS, cols[:, c]) for c in range(3)], -1).astype(np.uint8)


def render_navmap(r, w, h, game_dir='', span=NAV_SPAN, route=None, mobs=None, rings_on=False, items=None, duels=None,
                  walls=None, clear=False):
    """the /navmap picture (RGB, w x h) round the wizard for a navmem reading r (r['pos'] known); route: the
    planned route's answer (navroute) to draw, if any; mobs: the zone's mobs (mobs_now) - red dots, the quest's
    amber, and (rings_on: the walker keeps away from them) a faint ring round the others, mob_near across - a walking
    one (its 'vel') with an arrow the way it walks, as far as it's swept, and its ring's outline there; items: the
    things lying about it a quest has you collect (items_now) - green diamonds, the goal's brighter and named; duels:
    other players' battles kept out of (duels_now) - a violet circle each; walls: the walker's planner field
    (navroute.Field) - its line of mobs' gaps closed (fill), faintly red. clear (the overlay over the game - /ovmap,
    overlay.py): RGBA instead, clear where nothing is - its tiles tile(clear=True), kept apart in OV_TILES (at most
    OV_TILES_KEPT, or one picture's tiles if that's more) -, the markers and names a size bigger (min(w, h) /
    OV_UNIT_DIV), the scale bar and "no map for this zone" further in from the edges (the overlay's rounded corners),
    and a zone not read yet read pausing at each step while a gated request is in flight (gate_wait - the walker's /nav
    goes first); the default picture is as it always was"""
    from PIL import ImageDraw
    import navroute
    upp = span / min(w, h)
    ukey = round(upp, 4)
    x0, y0 = r['pos'][0], r['pos'][1]
    ox, oy = int(math.floor(x0 / upp - w / 2)), int(math.floor(-y0 / upp - h / 2))
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)) if clear else Image.new('RGB', (w, h), MAP_BG)
    tiles, kept = (OV_TILES, OV_TILES_KEPT) if clear else (NAV_TILES, NAV_TILES_KEPT)
    zone = r['zone'] or ''
    # (the overlay's map asks every second, whatever the walker does: a zone file read at a zone change - pure Python -
    # waits at each shape while a /nav is in flight, as placements' builds do; the dashboard's as it always was)
    layers = zone_layers(zone, game_dir, gate_wait if clear else None) if zone else None
    T = NAV_TILE
    if clear:
        # (never fewer than one picture's tiles: a big map would push each one out just before it's drawn again - every
        # tile drawn afresh every frame)
        kept = max(kept, ((w + T - 1) // T + 1) * ((h + T - 1) // T + 1))
    if layers is not None and not layers.why:
        for j in range(oy // T, (oy + h - 1) // T + 1):
            for i in range(ox // T, (ox + w - 1) // T + 1):
                key = (zone, ukey, i, j)
                if key in tiles:
                    tiles.move_to_end(key)
                else:
                    tiles[key] = layers.tile(upp, i, j, clear=True) if clear else layers.tile(upp, i, j)
                    while len(tiles) > kept:
                        tiles.popitem(last=False)
                if tiles[key] is not None:
                    img.paste(tiles[key], (i * T - ox, j * T - oy))
    # the overlay, drawn big and shrunk
    S = NAV_SS
    ov = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    unit = max(1.0, min(w, h) / (OV_UNIT_DIV if clear else 240)) * S      # line width / marker size unit (big pixels)

    def at(p):
        return ((p[0] / upp - ox) * S, (-p[1] / upp - oy) * S)

    def on_pic(q, m=0):
        return m <= q[0] <= w * S - m and m <= q[1] <= h * S - m

    def edge_pointer(q, col):
        """a point off the picture: a small triangle on its edge pointing at it"""
        cx, cy = w * S / 2, h * S / 2
        dx, dy = q[0] - cx, q[1] - cy
        n = math.hypot(dx, dy) or 1.0
        dx, dy = dx / n, dy / n
        m = 7 * unit
        k = min((cx - m) / abs(dx) if dx else 1e9, (cy - m) / abs(dy) if dy else 1e9)
        tx, ty = cx + dx * k, cy + dy * k
        L = 6 * unit
        d.polygon([(tx + dx * L, ty + dy * L), (tx - dy * L * 0.7, ty + dx * L * 0.7), (tx + dy * L * 0.7, ty - dx * L * 0.7)],
                  fill=col + (235,), outline=MAP_BG + (255,))

    me = at(r['pos'])
    path = r.get('path') or []
    if path:
        pts = [me] + [at(p) for p in path]
        if r['goal'] is not None and r['hops'] == 0:
            d.line([pts[-1], at(r['goal'])], fill=MAP_PATH + (120,), width=int(unit))
        d.line(pts, fill=MAP_PATH + (230,), width=int(2 * unit), joint='curve')
        for q in pts[1:]:
            d.ellipse([q[0] - 1.6 * unit, q[1] - 1.6 * unit, q[0] + 1.6 * unit, q[1] + 1.6 * unit], fill=MAP_PATH + (255,))
    if route and route.get('route'):
        pts = [me] + [at(p) for p in route['route'][1:]]
        if len(pts) >= 2:
            d.line(pts, fill=MAP_ROUTE + (235,), width=int(2 * unit), joint='curve')
        q = at(route['aim'])
        d.ellipse([q[0] - 2.2 * unit, q[1] - 2.2 * unit, q[0] + 2.2 * unit, q[1] + 2.2 * unit], fill=MAP_ROUTE + (255,), outline=MAP_BG + (255,))
    if r['goal'] is not None:
        q = at(r['goal'])
        door = (r['hops'] or 0) > 0
        col = MAP_DOOR if door else MAP_GOAL
        if on_pic(q, 4 * unit):
            s = 5 * unit
            if door:
                d.rectangle([q[0] - s, q[1] - s * 1.2, q[0] + s, q[1] + s * 1.2], fill=col + (255,), outline=MAP_BG + (255,), width=int(unit))
                f = map_font(int(7 * unit))
                d.text((q[0] + s * 1.5, q[1]), str(r['hops']), fill=col + (255,), font=f, anchor='lm', stroke_width=int(unit), stroke_fill=MAP_BG + (255,))
            else:
                d.polygon([(q[0], q[1] - s * 1.3), (q[0] + s * 1.3, q[1]), (q[0], q[1] + s * 1.3), (q[0] - s * 1.3, q[1])],
                          fill=col + (255,), outline=MAP_BG + (255,))
        else:
            edge_pointer(q, col)
    # the mobs: a red dot each (the quest's amber), faintly the shape they're kept out of - a circle all round, or a
    # semi-circle / cone in front with their body's small circle (its facing unknown: the whole circle) - on a layer
    # under everything else drawn (a see-through fill would wipe out what's under it here); names by the nearest few
    near_r = (MOBS_SHOWN.get('near') or 300.0) / upp * S
    cone = MOBS_SHOWN.get('cone')
    sector = bool(cone and cone[0] > 0 and cone[1] > 0)
    sight_r = cone[1] / upp * S if sector else 0.0
    by_dist = sorted(mobs or [], key=lambda m: math.hypot(m['pos'][0] - r['pos'][0], m['pos'][1] - r['pos'][1]))
    fm = map_font(int(5.5 * unit))
    rings = None
    for k, m in enumerate(by_dist):
        q = at(m['pos'])
        if not on_pic(q, -max(near_r, sight_r)):
            continue
        col = MAP_MOB_QUEST if m.get('quest') else MAP_MOB
        if not m.get('quest') and rings_on:
            if rings is None:
                rings = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
                dr = ImageDraw.Draw(rings)
            ring_r = sight_r if sector and m.get('yaw') is None else near_r
            dr.ellipse([q[0] - ring_r, q[1] - ring_r, q[0] + ring_r, q[1] + ring_r], fill=col + (34,), outline=col + (120,), width=max(1, int(unit * 0.7)))
            # (its sight in front of it: forward = (-sin yaw, -cos yaw); the picture's y is -Y)
            if sector and m.get('yaw') is not None:
                face = math.degrees(math.atan2(math.cos(m['yaw']), -math.sin(m['yaw'])))
                dr.pieslice([q[0] - sight_r, q[1] - sight_r, q[0] + sight_r, q[1] + sight_r], face - cone[0] / 2, face + cone[0] / 2,
                            fill=col + (34,), outline=col + (120,), width=max(1, int(unit * 0.7)))
        # (walking: an arrow the way it walks, as far as the route sweeps it - and its ring's outline there)
        vel = m.get('vel') if m.get('moving') else None
        if vel is not None:
            ahead, along = navroute.sweep_of(vel)
            if along > 0:
                e = at((m['pos'][0] + vel[0] * ahead, m['pos'][1] + vel[1] * ahead))
                d.line([q, e], fill=col + (200,), width=max(1, int(unit)))
                ux, uy = (e[0] - q[0]) / (math.hypot(e[0] - q[0], e[1] - q[1]) or 1.0), (e[1] - q[1]) / (math.hypot(e[0] - q[0], e[1] - q[1]) or 1.0)
                L = 3.5 * unit
                d.polygon([(e[0], e[1]), (e[0] - ux * L - uy * L * 0.6, e[1] - uy * L + ux * L * 0.6),
                           (e[0] - ux * L + uy * L * 0.6, e[1] - uy * L - ux * L * 0.6)], fill=col + (220,))
                if not m.get('quest') and rings_on:
                    ring_r = sight_r if sector and m.get('yaw') is None else near_r
                    d.ellipse([e[0] - ring_r, e[1] - ring_r, e[0] + ring_r, e[1] + ring_r], outline=col + (110,),
                              width=max(1, int(unit * 0.6)))
        s = 2.8 * unit
        d.ellipse([q[0] - s, q[1] - s, q[0] + s, q[1] + s], fill=col + (255,), outline=MAP_BG + (255,), width=max(1, int(unit * 0.7)))
        if k < 6 and on_pic(q, 4 * unit):
            d.text((q[0] + s * 1.6, q[1]), m['name'], fill=col + (235,), font=fm, anchor='lm', stroke_width=max(1, int(unit * 0.8)), stroke_fill=MAP_BG + (255,))
    # a line of mobs' wall (the walker's field: the gaps between them closed) - faintly, on the rings' layer
    fill = getattr(walls, 'fill', None) if walls is not None and rings_on else None
    if fill is not None and fill.any() and getattr(walls, 'zone', None) == r.get('zone'):
        if rings is None:
            rings = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
            dr = ImageDraw.Draw(rings)
        sq = navroute.CELL
        for j, i in np.argwhere(fill)[:20000]:
            xa, ya = walls.x0 + i * sq, walls.y0 + j * sq
            a, b = at((xa, ya + sq)), at((xa + sq, ya))
            if b[0] >= 0 and b[1] >= 0 and a[0] <= w * S and a[1] <= h * S:
                dr.rectangle([a, b], fill=MAP_WALL + (60,))
    # other players' battles kept out of: a violet circle each
    for du in duels or []:
        q = at(du['pos'])
        rr = float(du.get('r') or navroute.DUEL_R) / upp * S
        if not on_pic(q, -rr):
            continue
        if rings is None:
            rings = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
            dr = ImageDraw.Draw(rings)
        dr.ellipse([q[0] - rr, q[1] - rr, q[0] + rr, q[1] + rr], fill=MAP_DUEL + (40,), outline=MAP_DUEL + (160,), width=max(1, int(unit)))
        s = 3.0 * unit
        d.rectangle([q[0] - s, q[1] - s, q[0] + s, q[1] + s], fill=MAP_DUEL + (255,), outline=MAP_BG + (255,))
    # the quest items: a green diamond each (the goal's brighter, named); the goal's off the picture: a pointer
    for it in sorted(items or [], key=lambda it: bool(it.get('quest'))):
        q = at(it['pos'])
        col = MAP_ITEM_QUEST if it.get('quest') else MAP_ITEM
        if not on_pic(q, 3 * unit):
            if it.get('quest'):
                edge_pointer(q, col)
            continue
        s = 3.4 * unit
        d.polygon([(q[0], q[1] - s), (q[0] + s, q[1]), (q[0], q[1] + s), (q[0] - s, q[1])], fill=col + (255,), outline=MAP_BG + (255,))
        if it.get('quest'):
            d.text((q[0] + s * 1.5, q[1]), it['name'], fill=col + (235,), font=fm, anchor='lm', stroke_width=max(1, int(unit * 0.8)), stroke_fill=MAP_BG + (255,))
    if r['target'] is not None:
        q = at(r['target'])
        if on_pic(q, 4 * unit):
            s = 4.5 * unit
            d.ellipse([q[0] - s, q[1] - s, q[0] + s, q[1] + s], outline=MAP_TARGET + (255,), width=int(1.6 * unit))
            d.ellipse([q[0] - unit, q[1] - unit, q[0] + unit, q[1] + unit], fill=MAP_TARGET + (255,))
        else:
            edge_pointer(q, MAP_TARGET)
    # the wizard: an arrow pointing where it faces (forward = (-sin yaw, -cos yaw); picture y is -Y)
    fx, fy = -math.sin(r['yaw']), math.cos(r['yaw'])
    nx, ny = -fy, fx
    L = 8 * unit
    d.polygon([(me[0] + fx * L, me[1] + fy * L),
               (me[0] - fx * L * 0.7 + nx * L * 0.62, me[1] - fy * L * 0.7 + ny * L * 0.62),
               (me[0] - fx * L * 0.3, me[1] - fy * L * 0.3),
               (me[0] - fx * L * 0.7 - nx * L * 0.62, me[1] - fy * L * 0.7 - ny * L * 0.62)],
              fill=MAP_ME + (255,), outline=MAP_BG + (255,), width=max(1, int(unit * 0.8)))
    # a scale bar, bottom left
    bar = 1000 if 1000 / upp <= w * 0.4 else 500
    edge = 10 if clear else 6
    bx, by, bl = edge * unit, h * S - edge * unit, bar / upp * S
    d.line([(bx, by), (bx + bl, by)], fill=MAP_TEXT + (200,), width=int(unit))
    d.line([(bx, by - 2.5 * unit), (bx, by)], fill=MAP_TEXT + (200,), width=int(unit))
    d.line([(bx + bl, by - 2.5 * unit), (bx + bl, by)], fill=MAP_TEXT + (200,), width=int(unit))
    f = map_font(int(6 * unit))
    d.text((bx + bl + 2.5 * unit, by), str(bar), fill=MAP_TEXT + (220,), font=f, anchor='lm')
    if layers is None or layers.why:
        tedge = 10 if clear else 4
        d.text((w * S - tedge * unit, h * S - tedge * unit), 'no map for this zone', fill=MAP_TEXT + (200,), font=f, anchor='rs')
    out = img.convert('RGBA')
    if rings is not None:
        out.alpha_composite(rings.resize((w, h), Image.BOX))
    out.alpha_composite(ov.resize((w, h), Image.BOX))
    return out if clear else out.convert('RGB')


def map_picture(w, h, span=NAV_SPAN, clear=False):
    """the map round the wizard, w x h, span game units across its shorter side (render_navmap - the dashboard's
    /navmap; clear: the overlay's /ovmap, RGBA) with the mobs, duels, items, route and walls as the walker last
    asked: (picture, '') - or (None, why) when the game or the wizard's position can't be read"""
    nm = nav_reader()
    r, why = nm.read(path=True)
    if r is None:
        return None, why
    if r['pos'] is None or r['yaw'] is None:
        return None, "the wizard's position can't be read (" + (r.get('why_player') or '?') + ')'
    # (the mobs as the walker's last ask split them - the quest's, the ones kept away from)
    mobs, _ = mobs_now(r)
    fresh = time.time() - (MOBS_SHOWN.get('at') or 0) < 10
    for m in mobs:
        m['quest'] = m['gid'] in MOBS_SHOWN.get('quest', ()) if fresh else False
    # (other players' battles as the walker's last ask kept out of them - drawn, and in the map's route ask:
    # the field it may make is the walker's own - map_route)
    duels = DUELS_SHOWN.get('list') if time.time() - (DUELS_SHOWN.get('at') or 0) < 10 else None
    route = map_route(r, nm.game_dir, [m for m in mobs if not m['quest']] if fresh and MOBS_SHOWN.get('avoid') else None,
                      duels)
    # (the quest items as the walker's last /items split them - the items lying about, and any other
    # thing it took as the quest's: not every object and NPC of the zone)
    items, _ = items_now()
    ifresh = time.time() - (ITEMS_SHOWN.get('at') or 0) < 10
    for it in items:
        it['quest'] = it['gid'] in ITEMS_SHOWN.get('quest', ()) if ifresh else False
    items = [it for it in items if it.get('kind', 'item') == 'item' or it['quest']]
    # (the walker's field's line-of-mobs walls)
    walls = ROUTER.field if ROUTER is not None else None
    with MAP_LOCK:
        img = render_navmap(r, w, h, nm.game_dir, span, route, mobs, bool(fresh and MOBS_SHOWN.get('avoid')), items,
                            duels, walls, clear=clear)
    return img, ''


def save_png(img, out):
    """written whole, then put in place (the dashboard may be reading the last one)"""
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    tmp = out + '.tmp'
    img.save(tmp, 'PNG', compress_level=1)
    for _ in range(10):
        try:
            os.replace(tmp, out)
            return
        except PermissionError:
            time.sleep(0.02)
    img.save(out, 'PNG', compress_level=1)
    try:
        os.remove(tmp)
    except OSError:
        pass


def inside_temp(path):
    """whether path is inside the temp folder"""
    tmp = os.path.normcase(os.path.abspath(tempfile.gettempdir()))
    p = os.path.normcase(os.path.abspath(path))
    return p.startswith(tmp + os.sep)


def inside_root(path):
    p = os.path.normcase(os.path.abspath(path))
    return p.startswith(os.path.normcase(ROOT) + os.sep)


# ---------------------------------------------------------------- the overlay over the game (overlay.py, Overlay.ahk)

def ov_path_ok(path):
    """where the overlay's frame files may go: the AutoFarmer folder or the temp folder (as /navmap's pictures)"""
    return inside_root(path) or inside_temp(path)


def ov_yield(limit=0.5):
    """the overlay's pictures wait (limit s at most) while a request the bot waits on is in flight or just ended
    (GATE - /nav's 150 ms): its drawing would hold the GIL"""
    t0 = time.monotonic()
    while not GATE.idle(0.05) and time.monotonic() - t0 < limit:
        time.sleep(0.02)


def ovmap_reply(q):
    """/ovmap: (reply text, status) - the overlay's map drawn into its .wzov frame (overlay.py)"""
    import overlay as OV
    p, err = OV.parse_request(q, ov_path_ok)
    if p is None:
        return err, 400
    ov_yield()
    lay = OV.layout(p['gw'], p['gh'], p['args'])
    if lay['map'] is None:
        return 'ERR the map is off', 200
    x, y, w, h = lay['map']
    img, why = map_picture(w, h, float(p['args']['span']), clear=True)
    if img is None:
        return 'ERR ' + why, 200
    img = OV.finish_map(img, OV.back_alpha(p['args']['back']))
    out = os.path.abspath(p['out'])
    return OV.write_frame(out, img, x, y, p['seq'], p['force']) + '|' + out, 200


def ovlog_reply(q, body):
    """POST /ovlog: (reply text, status) - the overlay's log lines (the body) drawn into its .wzov frame (overlay.py)"""
    import overlay as OV
    p, err = OV.parse_request(q, ov_path_ok)
    if p is None:
        return err, 400
    ov_yield()
    lay = OV.layout(p['gw'], p['gh'], p['args'])
    if lay['log'] is None:
        return 'ERR ' + (lay['why'] or 'the log is off'), 200
    x, y, w, h = lay['log']
    img = OV.render_log(OV.parse_log_body(body), w, h, lay['px'], lay['line_h'], lay['pad'],
                        OV.back_alpha(p['args']['back']))
    out = os.path.abspath(p['out'])
    return OV.write_frame(out, img, x, y, p['seq'], p['force']) + '|' + out, 200


# ---------------------------------------------------------------- the server

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def reply(self, text, code=200):
        body = text.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        # (a read of the game's memory the walker waits on: placements' builds in their thread wait at their next step
        # meanwhile - the GIL: a cold zone file read in another thread took a /nav past its 150 ms)
        gated = u.path in GATED or u.path == '/phase' or (u.path == '/cards' and 'x1' not in q)
        if gated:
            places_busy(True)
            GATE.enter()
        try:
            if u.path == '/ping':
                return self.reply('OK ' + VERSION)
            if u.path == '/forget':
                global LIB
                LIB = Library()
                LEARNED_OK.clear()
                PLATE_CACHE.clear()
                with TPL_LOCK:
                    TPL_FFT.clear()
                    globals()['TPL_BYTES'] = 0
                log('pictures read again: ' + ', '.join(f'{os.path.basename(d) or "main"}={sc}' for d, sc in LIB.sets))
                return self.reply('OK')
            if u.path == '/enemies':
                # (names: the enemies in their slots' order; hist: round:enemy index:spell|... - the casts so far)
                names = [n.strip() for n in q.get('names', '').split('|')]
                hist = {}
                for part in q.get('hist', '').split('|'):
                    bits = part.split(':', 2)
                    if len(bits) == 3 and bits[0].isdigit() and bits[1].isdigit():
                        hist.setdefault(int(bits[0]), {})[int(bits[1])] = bits[2]
                lines = enemy_lines(names, int(float(q.get('round') or 1)), float(q.get('health') or 0),
                                    int(float(q.get('team') or 1)), hist)
                return self.reply('\n'.join(lines))
            if u.path == '/enemyseen':
                s = enemy_seen(q.get('name', ''), q.get('spell', ''), int(float(q.get('round') or 0)))
                return self.reply('seen|' + (s or 'pass'))
            if u.path == '/qmark':
                # (qmark|kind|x|y|w|h|label x|y|w|h - the label's fields empty when no green name was found under it)
                x1, y1, x2, y2 = (int(round(float(q[k]))) for k in ('x1', 'y1', 'x2', 'y2'))
                t0 = time.perf_counter()
                found = find_qmarks(x1, y1, x2, y2, q.get('file'))
                log(f'/qmark {(time.perf_counter() - t0) * 1000:.0f} ms: ' + (', '.join(
                    f"{m['kind']} {m['w']}x{m['h']} at {m['x']},{m['y']}" + ('' if m['label'] else ' (no name)') for m in found) or 'none'))
                return self.reply('\n'.join('qmark|{kind}|{x}|{y}|{w}|{h}|'.format(**m) + ('|'.join(map(str, m['label'])) if m['label'] else '|||')
                                            for m in found) or 'none')
            if u.path == '/globes':
                hp, mp = read_globes(float(q['left']), float(q['bottom']), float(q['scale']), q.get('file'))
                return self.reply(f'health|{hp}\nmana|{mp}')
            if u.path == '/plate':
                x1, y1, x2, y2 = (int(round(float(q[k]))) for k in ('x1', 'y1', 'x2', 'y2'))
                # (a reader's slip answered as "can't read" - OCR then - not as ERR, which counts against the helper)
                try:
                    cur, most, worst = plate_health(x1, y1, x2, y2, q.get('file'))
                except Exception as e:  # noqa: BLE001
                    log('/plate failed: ' + repr(e))
                    cur, most, worst = None, None, 'failed: ' + repr(e)
                if cur is None:
                    return self.reply('none|' + str(worst).replace('\n', ' '))
                return self.reply(f'health|{cur}|{most}|{worst:.3f}')
            if u.path == '/usable':
                return self.reply('1' if LIB.usable(q['rel'].replace('/', os.sep)) else '0')
            if u.path == '/hand':
                x1, y1, x2, y2 = (int(round(float(q[k]))) for k in ('x1', 'y1', 'x2', 'y2'))
                scale = float(q['scale'])
                t0 = time.perf_counter()
                thumbs = q.get('thumbs', '')
                if thumbs and not os.path.abspath(thumbs).lower().startswith(ROOT.lower()):
                    return self.reply('ERR thumbs must be in ' + ROOT, 400)
                cards = read_hand(x1, y1, x2, y2, scale, [p for p in q.get('pics', '').split(',') if p], q.get('file'),
                                  [e for e in q.get('learned', '').split(',') if e], q.get('here', ''), thumbs)
                lines = ['card|{left}|{top}|{w}|{h}|{known}|{kdist:.1f}|{g}|{kind}|{kinddist:.1f}|{pips}|{pipscore:.2f}|{same}|{liked}|{real}|{tc}'.format(g=int(c['grey']), **c) for c in cards]
                # (a box that isn't a card: "!" and what it measured)
                log(f'/hand scale {scale} {(time.perf_counter() - t0) * 1000:.0f} ms: ' + ', '.join(
                    (c['known'].split('/')[-1] or f"?{c['kind'] or 'type?'}") + ('(grey)' if c['grey'] else '')
                    + ('(tc)' if c['tc'] and c['real'] else '') + ('' if c['real'] else ' !not a card (' + feats_text(c['feats']) + ')')
                    for c in cards))
                if cards and not any(c['real'] for c in cards):
                    log(f'  no real card among {len(cards)} boxes - the hand rectangle may be off ({x1},{y1} {x2},{y2})')
                # (how many: an empty hand - the deck used up - answers hand|0, not nothing)
                lines.append(f'hand|{len(cards)}')
                return self.reply('\n'.join(lines))
            if u.path == '/cut':
                out = q['out']
                if not os.path.abspath(out).lower().startswith(ROOT.lower()):
                    return self.reply('ERR out must be in ' + ROOT, 400)
                ok, f = cut_card(float(q['left']), float(q['top']), float(q['scale']), out, q.get('file'))
                # (not a card: nothing saved - answered plainly, it isn't the helper failing)
                if not ok:
                    log(f'/cut {out}: not a card, nothing saved ({feats_text(f)})')
                    return self.reply('NOTCARD ' + feats_text(f))
                log(f'/cut {out}')
                return self.reply('OK')
            if u.path == '/cardcheck':
                ans = card_check(q.get('file', ''), q.get('scale', ''))
                log(f"/cardcheck {os.path.basename(q.get('file', ''))}: {ans}")
                return self.reply(ans)
            if u.path == '/seller':
                zone = q.get('zone', '')
                # (the game's folder comes from its running .exe: attached first, so another install is found)
                nm = nav_reader()
                nm.read(path=False, wait=3.0)
                found = potion_sellers(zone, nm.game_dir) if zone else []
                if found is None:
                    return self.reply("ERR the zone's file can't be read")
                return self.reply('\n'.join(f'seller|{n}|{x:.1f}|{y:.1f}|{z:.1f}' for n, (x, y, z) in found) or 'none')
            if u.path == '/volumes':
                zone = q.get('zone', '')
                nm = nav_reader()
                nm.read(path=False, wait=3.0)
                found = zone_volumes(zone, nm.game_dir) if zone else []
                if found is None:
                    return self.reply("ERR the zone's file can't be read")
                return self.reply('\n'.join(f'vol|{n}|{x:.1f}|{y:.1f}|{z:.1f}|{r:.0f}' for n, (x, y, z), r in found) or 'none')
            if u.path == '/navto':
                try:
                    target = (float(q['x']), float(q['y']), float(q['z']))
                except (KeyError, ValueError):
                    return self.reply('ERR x, y, z wanted', 400)
                avoid = q.get('avoid', '0') not in ('', '0')
                near, cone = mob_avoid(q)
                # (spare=<r>: the mobs within r of the spot not kept away from - the camp walked to, to fight it)
                try:
                    spare = min(5000.0, max(0.0, float(q.get('spare') or 0)))
                except ValueError:
                    spare = 0.0
                return self.reply('\n'.join(navto_lines(target, nav_reader().game_dir, avoid, near, cone, spare,
                                                        q.get('duels', '0') not in ('', '0'))))
            if u.path == '/blockers':
                nm = nav_reader()
                r, why = nm.read(path=False)
                if r is None:
                    return self.reply('ERR ' + why)
                return self.reply('\n'.join(blocker_lines(r, nm)))
            if u.path == '/zonepuzzle':
                zone = q.get('zone', '')
                if not zone:
                    return self.reply('ERR zone wanted', 400)
                # (files only: the game's folder as last attached - none yet: the usual one)
                return self.reply('\n'.join(zonepuzzle_lines(zone, nav_reader().game_dir)))
            if u.path == '/navpass':
                lines, code = navpass_lines(q, nav_reader())
                return self.reply('\n'.join(lines), code)
            if u.path == '/snap':
                if not snap_out_ok(q.get('out', '')):
                    return self.reply('ERR out must be a snap_*.jpg in a Wiz-Maxxing logs\\<PC> folder', 400)
                try:
                    return self.reply('ok|' + snap(int(q['x1']), int(q['y1']), int(q['x2']), int(q['y2']), q['out'],
                                                   max(1, int(q.get('keep') or 15))))
                except Exception as e:
                    return self.reply('ERR ' + repr(e))
            if u.path == '/caught':
                return self.reply(caught_line())
            if u.path == '/duels':
                nm = nav_reader()
                r, why = nm.read(path=False)
                if r is None:
                    return self.reply('ERR ' + why)
                if not hasattr(nm, 'duels'):
                    return self.reply('ERR the reader has no duels')
                got, why = nm.duels()
                if got is None:
                    return self.reply('ERR ' + (why or '?'))
                return self.reply('\n'.join(duel_lines(got, r)))
            if u.path == '/cards' and 'x1' not in q:
                return self.reply(cards_answer(q))
            if u.path == '/phase':
                # (the round's phase alone - no spell read, about a ms: vision\handmem.py HandMem.phase, read-only; gated
                # as memory /cards is)
                import handmem
                p, why = handmem.nav_phase(nav_reader(), wait=0.3)
                return self.reply(handmem.phase_line(p, why))
            if u.path == '/mobs':
                nm = nav_reader()
                r, why = nm.read(path=False)
                if r is None:
                    return self.reply('ERR ' + why)
                mobs, why = mobs_now(r, q.get('goal', ''), goal=goal_now(r)[0])
                if not mobs:
                    return self.reply('none' + (' (' + why + ')' if why else ''))
                me = r['pos'] or (0.0, 0.0, 0.0)
                # (what each is at the end - title, rank, health, school, boss flag, gid, named: an older bot reads the
                # first 8)
                return self.reply('\n'.join(
                    mob_line(m, me) for m in sorted(mobs, key=lambda m: math.hypot(m['pos'][0] - me[0], m['pos'][1] - me[1]))))
            if u.path == '/battle':
                parts, why = nav_reader().battle(wait=0.3)
                _rec_hook('saw_battle', parts)
                return self.reply('\n'.join(battle_lines(parts, why)))
            if u.path == '/rec':
                # (the bot's who-state as a GET: onto the battle recorder's queue - vision\battlerec.py)
                return self.reply(REC.post(q, b'') if REC is not None else 'off')
            if u.path == '/recstat':
                return self.reply(REC.stat() if REC is not None else "rec|off|0|0||the battle recorder isn't running")
            if u.path == '/deck':
                return self.reply('\n'.join(deck_lines(q.get('fresh') == '1')))
            if u.path == '/decks':
                return self.reply('\n'.join(decks_lines(q.get('fresh') == '1', q.get('ob') == '1')))
            if u.path == '/book':
                # (the spellbook and treasure book - vision\deckmem.py, read-only: Training.ahk's new spells)
                return self.reply('\n'.join(book_answer(q.get('fresh') == '1', q.get('ob') == '1', q.get('kinds') == '1')))
            if u.path == '/quests':
                # (every quest in the game's quest manager - vision\questmem.py, read-only)
                return self.reply('\n'.join(quests_answer()))
            if u.path == '/sim':
                return self.reply('\n'.join(sim_lines_for(q)))
            if u.path == '/plan':
                return self.reply('\n'.join(plan_lines_for(q)))
            if u.path == '/deckfor':
                return self.reply('\n'.join(deckfor_lines_for(q)))
            if u.path == '/uiroot':
                size, why = nav_reader().ui_root(wait=0.3)
                return self.reply(f'root|{size[0]}|{size[1]}' if size else 'none|' + mob_cell(why or 'not read'))
            if u.path == '/bag':
                # (the backpack, the HUD's tips, the backpack page's N/M - vision\bagmem.py, read-only: AutoFarmer's
                # QuickSell.ahk)
                return self.reply('\n'.join(bag_answer()))
            if u.path == '/gear':
                # (the worn gear and the backpack's with their equip effects and requirements - vision\gearmem.py,
                # read-only - and gearrank.py's swap plan; run=&mark=1 / end=1: a dungeon run's drop log in
                # learned\drops - AutoFarmer's Gear.ahk)
                return self.reply('\n'.join(gear_lines_for(q)))
            if u.path == '/gui':
                # (the game's windows by name - w=Anc/Name,... - and the message box up: where QuickSell.ahk may click)
                import bagmem
                paths = bagmem.gui_paths(q.get('w', ''))
                if paths is None:
                    return self.reply('ERR w: at most %d window paths (Anc/Name - letters, digits and _)' % bagmem.PATHS_CAP,
                                      400)
                g, why = nav_reader().gui(paths, wait=0.3)
                return self.reply('\n'.join(bagmem.gui_lines(g, why, paths)))
            if u.path == '/guitree':
                # (every window under one - under=Anc/Name, the GUI root without; all=1 the hidden ones too; depth=N -
                # one line each: the discovery tool for windows not looked at yet and a list's rows, vision\bagmem.py's
                # tree - read-only)
                import bagmem
                under = bagmem.tree_under(q.get('under', ''))
                if under is None:
                    return self.reply('ERR under: one window path (Anc/Name - letters, digits and _)', 400)
                dep = q.get('depth', '')
                t, why = bagmem.nav_tree(nav_reader(), under, q.get('all', '0') in ('', '0'),
                                         int(dep) if dep.isdigit() else None, wait=0.3)
                return self.reply('\n'.join(bagmem.tree_lines(t, why)))
            if u.path == '/pets':
                # (the wizard's pets and the ones to keep - vision\petmem.py / petplan.py, read-only: QuickSell.ahk
                # QsPetGuard leaves the Pet group out while a pet to keep is in the backpack)
                import petplan
                r, why = nav_reader().pets(wait=1.0)     # (its reader made once a game: about half a second)
                return self.reply('\n'.join(petplan.pets_answer(r, why, q.get('want', ''),
                                                                 q.get('hatch', '0') not in ('', '0'))))
            if u.path == '/items':
                nm = nav_reader()
                r, why = nm.read(path=False)
                if r is None:
                    return self.reply('ERR ' + why)
                far = q.get('far', '0') not in ('', '0')
                items, why = items_now(q.get('goal', ''), goal_now(r)[0], r, far)
                ITEMS_SHOWN.update(quest={it['gid'] for it in items if it['quest']}, at=time.time())
                if not items:
                    return self.reply('none' + (' (' + why + ')' if why else ''))
                me = r['pos'] or (0.0, 0.0, 0.0)
                # (fields 9-12 - key, template, src, kind - at the end: an older bot reads the first 8)
                return self.reply('\n'.join(
                    item_line(it, me) for it in sorted(items, key=lambda it: math.hypot(it['pos'][0] - me[0],
                                                                                         it['pos'][1] - me[1]))))
            if u.path == '/nav':
                with_path = q.get('path', '0') not in ('', '0')
                with_route = q.get('route', '0') not in ('', '0')
                # (the walker walked on with F8: teleports given up get another go - something may have opened one)
                if q.get('unblock', '0') not in ('', '0') and ROUTER is not None:
                    ROUTER.blocked.clear()
                    ROUTER.jwait, ROUTER._round = None, None
                    log('route: teleports given up forgotten (walking on with F8)')
                nm = nav_reader()
                r, why = nm.read(path=with_path or with_route)
                if r is None:
                    return self.reply('ERR ' + why)
                lines = nav_lines(r, with_path)
                # (a zone the walker's in: its file's things built in a thread - for /items?far=1 - once per zone)
                places_want(r, nm.game_dir)
                # (the quest's goal from the game's memory - the line the mobs are matched against, and /nav's last line;
                # its reader made in a thread the first time: not waited for here)
                goal, _ = goal_now(r)
                if with_route:
                    # (the mobs kept away from: all but the quest's - asked for with avoid=1)
                    avoid, near, cone, duels = None, None, None, None
                    if q.get('avoid', '0') not in ('', '0'):
                        near, cone = mob_avoid(q)
                        mobs, _ = mobs_now(r, q.get('goal', ''), trail=True, goal=goal)
                        avoid = [m for m in mobs if not m['quest']]
                        MOBS_SHOWN.update(quest={m['gid'] for m in mobs if m['quest']}, near=near, avoid=True, at=time.time(),
                                          cone=cone)
                        # (other players' battles kept out of too - duels=1: the duelavoid setting)
                        if q.get('duels', '0') not in ('', '0'):
                            duels, _ = duels_now()
                        DUELS_SHOWN.update(list=duels or [], at=time.time())
                    else:
                        MOBS_SHOWN.update(quest=set(), avoid=False, at=time.time())
                        DUELS_SHOWN.update(list=[], at=time.time())
                    try:
                        arc_r = min(1200.0, max(0.0, float(q.get('arcr') or 0)))
                    except ValueError:
                        arc_r = 0.0
                    # (this ask's own cone - not MOBS_SHOWN's, which a /navto running alongside may have changed; a line
                    # of mobs' wall with no way round waited at only with walls=1 - the mobwall setting)
                    lines += route_lines(r, nm.game_dir, avoid, near, cone, arc_r, duels,
                                         bool(avoid) and q.get('walls', '0') not in ('', '0'))
                lines.append(goal_nav_line(goal))
                return self.reply('\n'.join(lines))
            if u.path == '/goal':
                nm = nav_reader()
                r, why = nm.read(path=False, wait=0.3)
                if r is None:
                    return self.reply('none|' + goal_cell(why))
                # (asked fresh - the walker asks every 3 s at most; its reader waited for a moment the first time)
                return self.reply('\n'.join(goal_lines(*goal_now(r, max_age=0.0, wait=0.3))))
            if u.path == '/navmap':
                w, h = int(q['w']), int(q['h'])
                out = q['out']
                if not (16 <= w <= 4000 and 16 <= h <= 4000):
                    return self.reply('ERR w and h must be 16-4000', 400)
                # (the temp folder too: the dashboard's map is rewritten every second, which OneDrive would
                # keep uploading if it were in the bot's folder)
                if not out.lower().endswith('.png') or not (inside_root(out) or inside_temp(out)):
                    return self.reply('ERR out must be a .png in ' + ROOT + ' or the temp folder', 400)
                span = min(100000.0, max(500.0, float(q.get('span', NAV_SPAN))))
                img, why = map_picture(w, h, span)
                if img is None:
                    return self.reply('ERR ' + why)
                save_png(img, os.path.abspath(out))
                return self.reply('ok|' + os.path.abspath(out))
            if u.path == '/ovmap':
                return self.reply(*ovmap_reply(q))
            if u.path == '/quit':
                self.reply('OK bye')
                party_stop()
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            if u.path == '/net':
                # (AutoFarmer's network settings and state in - on, port, pin, pc, ver, wiz, school, zone, bot, pfm,
                # doing, hp, mana, deaths, dall, up, status, last, front, gx, gy, gw, gh; out: net|state|why, me|id|port,
                # peer|id|ip|age|pc|ver|wiz|school|zone|bot|pfm|doing|hp|mana|deaths|dall|up|status|last, cmd|c|from)
                return self.reply('\n'.join(netmon().update(q)))
            if u.path == '/netpeer':
                # (the bot picked on the Network tab - /net's sel: its log and game as the fetch thread has them)
                return self.reply('\n'.join(netmon().picked(q.get('id', ''))))
            if u.path == '/netcmd':
                return self.reply(netmon().command(q.get('id', ''), q.get('c', '')))
            if u.path == '/partyorder':
                # (partyorders - this helper's own server only, never the LAN's: the leader's card for this wizard's hand
                # - a follower's AutoFarmer -, or the leader's AutoFarmer's lead=1 / noplan=<round> - party.py)
                return self.reply(partyorder_answer(q))
            if u.path == '/party':
                # (AutoFarmer's party settings and state in - role, name, leader, port, battle, hp, ready, walk, bot,
                # loading, hold, brole, wiz, school, hits, hitr, plan, lasthit, tp, tpwhy, hitat, seat, orders, plans
                # (partyorders: 1 - plans the leader's, while it can plan); the party as this PC sees it out: party|..,
                # me|.., leader|.., member|.. - party.py)
                return self.reply('\n'.join(party().update(q)))
            if u.path in ('/cards', '/badge'):
                x1, y1, x2, y2 = (int(round(float(q[k]))) for k in ('x1', 'y1', 'x2', 'y2'))
                scale = float(q['scale'])
                file = q.get('file')
                t0 = time.perf_counter()
                extra = []
                if u.path == '/cards':
                    missing = []
                    res = find_cards(x1, y1, x2, y2, scale, [p for p in q.get('pics', '').split(',') if p], file, missing)
                    if missing:
                        extra.append('missing|' + ','.join(missing))
                else:
                    res = find_badges(x1, y1, x2, y2, scale, [s for s in q.get('schools', '').split(',') if s], file)
                    if res is None:
                        res, extra = [], ['unclear']
                ms = (time.perf_counter() - t0) * 1000
                lines = [f'{r[0]}|{r[1]}|{r[2]}|{r[3]:.1f}' for r in res] + extra
                log(f'{u.path} scale {scale} ({x2 - x1}x{y2 - y1}) {ms:.0f} ms: ' + (', '.join(f'{r[0]} {r[3]:.1f}' for r in res) or 'nothing') + (' | ' + ' '.join(extra) if extra else ''))
                return self.reply('\n'.join(lines))
            return self.reply('ERR unknown request ' + u.path, 404)
        except Exception as e:  # noqa: BLE001 - any problem goes back to AutoFarmer, which falls back
            log(f'ERR {self.path}: {e!r}')
            return self.reply('ERR ' + repr(e), 500)
        finally:
            if gated:
                GATE.leave()
                places_busy(False)

    def do_POST(self):
        """/rec and /ovlog. /rec: the bot's round, hello, who and state posts (vision\\battlerec.py) - its body (64 KB at
        most) put on the recorder's queue as it is - no parsing, file or memory read here - "ok", or "off" when the
        recorder is off. /ovlog: the overlay's log lines (Overlay.ahk) drawn into its frame file - ovlog_reply"""
        try:
            u = urlparse(self.path)
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            try:
                n = int(self.headers.get('Content-Length') or 0)
            except ValueError:
                n = 0
            body = self.rfile.read(min(max(n, 0), 64 * 1024)) if n > 0 else b''
            if n > 64 * 1024:
                left = n - 64 * 1024
                while left > 0:
                    got = self.rfile.read(min(left, 65536))
                    if not got:
                        break
                    left -= len(got)
            if u.path == '/ovlog':
                return self.reply(*ovlog_reply(q, body))
            if u.path != '/rec':
                return self.reply('ERR unknown request ' + u.path, 404)
            return self.reply(REC.post(q, body) if REC is not None else 'off')
        except Exception as e:  # noqa: BLE001 - the bot never waits on this
            if not self.path.startswith('/rec'):
                log(f'ERR {self.path}: {e!r}')
            try:
                return self.reply('ERR ' + repr(e), 500)
            except Exception:  # noqa: BLE001
                return None


def parent_alive(pid):
    PROCESS_QUERY_LIMITED_INFORMATION, STILL_ACTIVE = 0x1000, 259
    h = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return False
    code = ctypes.c_ulong()
    ok = ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(h)
    return bool(ok) and code.value == STILL_ACTIVE


def rec_start():
    """the battle recorder (vision\\battlerec.py) started - its thread idle till the bot's hello says on. Any problem:
    REC stays None, the hooks do nothing and /rec answers off (one vision.log line)"""
    global REC
    try:
        import battlerec
        REC = battlerec.start(root=ROOT, nav=nav_reader, log=log, gate=GATE)
    except Exception as e:  # noqa: BLE001
        REC = None
        log(f"battlerec: couldn't start ({e!r}) - no battle is recorded")
    return REC


def main():
    global LIB
    ap = argparse.ArgumentParser()
    ap.add_argument('--parent', type=int, default=0, help='stop when this process is gone')
    ap.add_argument('--port', type=int, default=PORT)
    args = ap.parse_args()
    try:
        ctypes.windll.user32.SetProcessDPIAware()   # screen pixels, like AutoHotkey's
    except Exception:  # noqa: BLE001
        pass
    LIB = Library()
    try:
        server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    except OSError as e:
        log(f'port {args.port} taken ({e}) - another copy is running')
        return
    log(f'started (version {VERSION}, port {args.port}, parent {args.parent}, sets: ' + ', '.join(f'{os.path.basename(d) or "main"}={sc}' for d, sc in LIB.sets) + ')')
    # (the game's template files - Root.wad's table, the template manifest - read once now, in placements' thread, before
    # the walker's first zone wants them for /items?far=1)
    try:
        import placements
        placements.set_log(log)
        placements.warm()
    except Exception as e:  # noqa: BLE001 - /items without the zone files
        log(f"placements: couldn't start ({e!r})")
    try:
        import puzzlefile
        puzzlefile.set_log(log)
    except Exception as e:  # noqa: BLE001 - /zonepuzzle answers ERR
        log(f"puzzlefile: couldn't start ({e!r})")
    rec_start()
    if args.parent:
        def watch():
            while parent_alive(args.parent):
                time.sleep(5)
            log('AutoFarmer is gone - stopping')
            party_stop()
            server.shutdown()
        threading.Thread(target=watch, daemon=True).start()
    server.serve_forever()
    log('stopped')


if __name__ == '__main__':
    main()
