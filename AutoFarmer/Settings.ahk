#Warn Unreachable, Off
; Settings.ahk - the Settings window (the dashboard's Settings button, or the tray menu): the mouse and the bot's
; waits, and how it plays its cards. AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Every setting is a line in PlayerStats.txt (key:value) - the window only shows them. Save writes the ones you
; changed there, each in its own line with its comment kept (one the file doesn't have yet goes at its end),
; and the bot uses them from its next click or round on: no restart. Point at a setting to see what it does.
;
; Also here: the mouse put back where it was when the bot took it (MouseGrab / MouseLetGo, mousereturn), and your mouse
; locked while the bot uses it (MouseLockOn / MouseLockOff, mouselock).

;The window; its help line and its note by the buttons; each setting's control (key -> hwnd), the value it
;showed (key -> value) and the help for each label and control (hwnd -> text); the help on show
global CfgHwnd, CfgHelpText, CfgNote, CfgCtls, CfgShownVals, CfgHelps, CfgHelpShown
;The view: simple (only the most used settings - CfgSimpleKeys) or all of them; changes not saved yet, kept across a
;switch of view ({key: value}); where the window was (the switch opens it there again)
global CfgSimple, CfgPending, CfgReopenX, CfgReopenY
;Where the mouse was when the bot took it (MouseGrab), whether that's kept, and when it was taken
global MouseHomeX, MouseHomeY, MouseHomeSet, MouseHomeAt
;Cards of kinds switched off discarded this round (RoundStart clears it; at most discardmax)
global DiscardOffCount

;Every setting in the window, in order: {key, label, kind: "check" (on/off), "num" (lo to hi) or "pick" (picks:
;1, 2, ...), def: its default, help}. {key: "-"} is a heading, {key: "|"} starts the second column. LoadStats
;(KillCalc.ahk) takes the defaults from here too, for a PlayerStats.txt without the line
CfgList()
	{
	static list := ""
	if (IsObject(list))
		return list
	list := []
	list.Push(V1Obj({key: "-", label: "THE MOUSE AND WAITS"}))
	list.Push(V1Obj({key: "handsoffon", label: "Wait for me while I play", kind: "check", def: 1
		, help: "While you use the keyboard or mouse yourself the bot waits: no battle rounds, no walking, no potions. (The dashboard's Wait for me button switches it too.) On again, with 3 seconds, every time the bot starts - it never takes the mouse from you as it starts."}))
	list.Push(V1Obj({key: "handsoff", label: "Wait for me: seconds after you stop", kind: "num", lo: 0, hi: 3600, def: 3
		, help: "How long after your last key press, click or mouse move the bot carries on. 0 = it never waits for you."}))
	list.Push(V1Obj({key: "mouselock", label: "Lock my mouse while the bot uses it", kind: "check", def: 1
		, help: "While the bot has the mouse - a battle round, a click, a mouse turn while walking, a potion, login or quick sell click - your mouse can't move the pointer, and over Wizard101 its buttons and wheel do nothing (what you do with it then doesn't count as you playing). The keyboard always stays free: {key:bot} stops the bot and frees the mouse, and with Wait for me on any key leaves the round to you. Freed at once when Wizard101 isn't the window in front (Alt+Tab), and if nothing's renewed it for 15 s. Off: your mouse always works - moving it makes the bot wait for you, as Wait for me says."}))
	list.Push(V1Obj({key: "gamefront", label: "Bring Wizard101 to the front when needed", kind: "check", def: 0
		, help: "When the quest arrow shows (walking) or a battle round is up and Wizard101 isn't the window in front, the bot brings it to the front - walking, only once you've left the keyboard and mouse alone 3 s. Off: click into it yourself. Also the dashboard's 'Game to front' button."}))
	list.Push(V1Obj({key: "hungload", label: "Restart Wizard101 stuck on a loading screen (minutes, 0 = never)", kind: "num", lo: 0, hi: 120, def: 5
		, help: "A zone change that never finishes - the game's log says it began this long ago and has written nothing but its memory notes for 3 minutes, and neither the spellbook nor a battle round has shown since: asks (yes in 60 s if nobody answers), closes Wizard101 and starts it again, logging in with the saved login (tray menu: Set Wizard101 login...). Needs Auto-reconnect on. 2026-10-23: a defeat's trip back hung 69 minutes."}))
	list.Push(V1Obj({key: "mousereturn", label: "Put the mouse back afterwards", kind: "check", def: 1
		, help: "When the bot takes the mouse - a battle round, a click out of battle - it goes back to where it was once the bot's done (not if you've used the mouse or keys meanwhile). Off: it's left in the middle of the game."}))
	list.Push(V1Obj({key: "mousespeed", label: "Mouse speed (0 = jump there)", kind: "num", lo: 0, hi: 100, def: 1
		, help: "How the mouse moves to what it clicks: 0 jumps straight there, 1 is the fastest glide, higher numbers glide slower (100 is the slowest)."}))
	list.Push(V1Obj({key: "clickwait", label: "Wait before each click (ms)", kind: "num", lo: 0, hi: 5000, def: 40
		, help: "Between the mouse getting there and the click. Raise it if the game misses clicks."}))
	list.Push(V1Obj({key: "clickrandom", label: "...plus a random wait up to (ms)", kind: "num", lo: 0, hi: 5000, def: 0
		, help: "A random 0 to this many ms more before each click, so the clicks aren't evenly timed. 0 = none."}))
	list.Push(V1Obj({key: "clickafter", label: "Wait after clicks (% of the usual)", kind: "num", lo: 0, hi: 1000, def: 50
		, help: "The wait after a card and after its target (300 ms at 100). Lower is faster - raise it if a target click gets missed after a card."}))
	list.Push(V1Obj({key: "roundwait", label: "Wait before playing a round (ms)", kind: "num", lo: 0, hi: 30000, def: 0
		, help: "From a round showing up (its Pass button) to the bot's first look at the hand. 0 = at once."}))
	list.Push(V1Obj({key: "discardafter", label: "Wait after each discard (ms)", kind: "num", lo: 250, hi: 5000, def: 400
		, help: "After each right-click that discards a card from the hand, while the rest slide together (250 at the least)."}))
	list.Push(V1Obj({key: "discardlook", label: "Wait before looking at the hand again (ms)", kind: "num", lo: 0, hi: 5000, def: 700
		, help: "After discarding, while the hand slides together, before the cards are looked at again."}))
	list.Push(V1Obj({key: "-", label: "HEALTH"}))
	list.Push(V1Obj({key: "healat", label: "Heal under this % of health (0 = never)", kind: "num", lo: 0, hi: 100, def: 40
		, help: "In battle: a healing card (the heal1 / heal2 pictures) on yourself when your health is under this %. 0 = never."}))
	list.Push(V1Obj({key: "enemyspells", label: "Predict the enemies' spells", kind: "check", def: 1
		, help: "Each round: what each enemy will most likely cast - its spells off the Wizard101 wiki (Fandom), looked up once and kept; its pips guessed from the round; what it was seen casting (the game's own log) - and the chance their hits kill you this round. In debug.log ('enemy spells:') and on the dashboard (Threat; each enemy's every spell on its Cards tab). Needs the vision helper."}))
	list.Push(V1Obj({key: "defendat", label: "...defend first at this % chance to die (0 = never)", kind: "num", lo: 0, hi: 100, def: 30
		, help: "When the chance this round's enemy hits kill you is this % or more and no hit in hand ends the battle: a heal on yourself (heal1 / heal2), else Tower Shield, before anything else. 0 = only show the odds."}))
	list.Push(V1Obj({key: "potionat", label: "Drink a potion under this % (0 = never)", kind: "num", lo: 0, hi: 100, def: 40
		, help: "Out of battle: a potion (Ctrl+O) when your health is under this % - out of potions, the bot buys more with gold. 0 = never."}))
	list.Push(V1Obj({key: "potionwalk", label: "Walk to the potion seller by the map", kind: "check", def: 1
		, help: "Out of potions: to Hilda Brewer in Wizard City's Commons by the zone's map - a Recall to your Mark (anywhere in the Commons) or End in Wizard City - X, Fill All, drink. No recording needed. Off: the recorded ways (tray menu Record potion buying)."}))
	list.Push(V1Obj({key: "fleeon", label: "Flee when out of cards", kind: "check", def: 1
		, help: "Completely out of cards (none in hand, two rounds running): flee and try again with a full deck. Never for no hit in hand or out of mana."}))
	list.Push(V1Obj({key: "-", label: "THE BACKPACK"}))
	list.Push(V1Obj({key: "quicksell", label: "Quick sell the backpack when it's full", kind: "check", def: 0
		, help: "After a battle, when the game shows the backpack full (Prospector Zeke's alert on the right - the game's memory, never a picture; the game's own N/M has to read full): B, Quick Sell, each gear group (hats, robes, shoes, weapons, athames, amulets, rings, decks) and the pets' with ALL - No to Crowns Items - and SELL, for gold. Never in a dungeon run or a dungeon zone (between a run's goes, back outside at its start, as after one), and not after one unless ticked below (with the gear pass, gearswap, on: the gear groups are, once it compared them - the Deck and Pet groups stay held) - a dungeon you walked into yourself isn't known as one: switch quick sell off there. A group an Equipment Set's item is in is left out. Locked items are never sold: lock gear you want to keep. Tray menu: Quick sell the backpack now, and a rehearsal that stops at the confirmation (quicksell:2 in PlayerStats.txt does that after battles, at most once an hour)."}))
	list.Push(V1Obj({key: "quicksellpets", label: "...pets too", kind: "check", def: 1
		, help: "On: the Pet group is sold too, with ALL - every pet in the backpack but the locked ones (the game never quick sells a locked item) and the Crowns items (No to the game's 'include Crowns Items?' box); Yes to the game's pets box only when its count is the confirmation's. A Crown-shop pet or an Equipment Set's pet in the backpack keeps the WHOLE group out (no pet is sold then), and so does a pet to keep for the wanted talents in pets.txt (README: Perfect pets - every pet, while the bot can't read their talents yet). Off: pets are kept."}))
	list.Push(V1Obj({key: "quicksellafterdungeon", label: "...even with a dungeon's drops in it", kind: "check", def: 0
		, help: "Off: after a dungeon (a dungeon run, or a zone entered through a sigil) the next full backpack is not sold - you're told, so you can look through it first; it's sold again once 10 items have gone from it (the bot's own sales not counted), or you ask from the tray. With the gear pass (gearswap) on, its gear groups are sold once every piece is compared and none is better - only the Deck and Pet groups stay held, you're told. On: sold like any other. Inside a dungeon it's never sold (a dungeon run, one the bot went into through its sigil and its deeper zones - not one you walked into yourself)."}))
	list.Push(V1Obj({key: "gearswap", label: "Compare gear before selling (advice only, untried)", kind: "check", def: 0
		, help: "New, not tried in the game yet. On: before a full backpack is quick sold, and after each dungeon run, your worn gear and the backpack's are read from the game's memory (read only - vision\gearmem.py) and, slot by slot (hat, robe, shoes, weapon, athame, amulet, ring - never decks, pets or mounts), a piece better for you is worked out (vision\gearrank.py: your damage, pierce, critical, block, accuracy and health from your stats; the gear's own stats aren't confirmed yet - a piece whose stat sizes aren't read goes by its level) - logged 'Gear: ...', a tray tip for a new one. A REHEARSAL: nothing is equipped or clicked - put the piece on yourself. A better piece in the backpack (or one it couldn't judge - its details not read) holds the quick sell, and you're told; every piece compared and none better: it's sold - after a dungeon too, but without the Deck and Pet groups (decks and pets are never compared): the dungeon's hold keeps them, you're told, till it ends as it would without this ('...even with a dungeon's drops in it' says how). A dungeon run's new pieces are logged in learned\drops\ (its 'Until its gear is swapped' box on the Dungeons tab needs this). Hidden in PlayerStats.txt: gearmargin:2 (the % a piece must be better by), gearweight.off:1, gearweight.def:0.5, gearweight.pip:0.3, gearweight.heal:0 (what counts - one number a line; each left out: your party battle role's), gearlevel:N (your level, if the game's memory doesn't give it). Off: quick sell and dungeon runs as before."}))
	list.Push(V1Obj({key: "gearsets", label: "...plan pieces of an Equipment Set too", kind: "check", def: 0
		, help: "Off: a better piece for a slot whose worn piece is in one of your Equipment Sets is shown as held, and you're asked once (Discord) to re-save that set after you swap it - else the set's Ctrl+N (a deck's Equipment Set) puts the old piece back; a backpack piece that's in a set is kept for it. On: those are planned like any other (you re-save your sets yourself). The bot never saves a set."}))
	list.Push(V1Obj({key: "-", label: "WALKING"}))
	list.Push(V1Obj({key: "battlesonly", label: "Battles only - never move the wizard", kind: "check", def: 0
		, help: "For a wizard riding another's mount (the driver takes it everywhere), or wherever the bot must only fight: out of battle it moves nothing - quest walking stays off at every start ({key:walk} says why and doesn't walk), no party following, dungeon run, puzzle try or potion run (a potion is still drunk when health is low; out of potions it only alerts; out of mana it alerts and plays on, no hold), no mob-loop, lore or afk move. It waits for battles and plays them as ever - the party's battle roles too. Quick sell can't tell a dungeon the driver takes it into: keep quick sell off on a passenger. Also the tray menu's Battles only."}))
	list.Push(V1Obj({key: "collectmem", label: "Collect quest items by the game's memory", kind: "check", def: 1
		, help: "A 'Collect N <things>' goal whose things lie about the zone (Piece Of Coral in The Grotto): their places are read from the game's memory (read-only) and the nearest is walked to round walls and mobs and picked up, then the next. None seen: it roams and walks into monsters as before. Off: only that. The dashboard's map shows them as green diamonds."}))
	list.Push(V1Obj({key: "speedhack", label: "Walk faster with Cheat Engine's speedhack", kind: "check", def: 0
		, help: "Cheat Engine speeds the game up: the bot presses its speedhack hotkeys - the walking key while it walks, the 1x key for battles, talking, dialogues, shops, near the goal, getting round an obstacle, when you play, {key:bot}, and when it stops. Setup.exe's 'Cheat Engine speedhack' sets it all up: installs Cheat Engine and puts the bot's script in it - it attaches itself to Wizard101 (again after the game restarts) and the two keys below set the speed - and the bot starts Cheat Engine when this is on. Without that, in Cheat Engine: Settings > Hotkeys - 'Speedhack speed' entries for the two keys below, one at the speed below, one at 1, 'Disable when released' unticked (the tray menu's Speedhack items press a key 3 s after you pick them, to set them there). Not set up by Setup, attach Cheat Engine again after Wizard101 restarts. The bot checks how fast the wizard turns and stops using the speedhack for the run if the game isn't sped up. Risky: KingsIsle may notice."}))
	list.Push(V1Obj({key: "speedfactor", label: "...the speed its walking key sets (2 = twice as fast)", kind: "num", lo: 1, hi: 50, def: 2
		, help: "The speed you gave Cheat Engine's walking key: the bot's turn and wait times are divided by it. 2-5 work best; above 5 turns are made at normal speed."}))
	list.Push(V1Obj({key: "speedkeyfast", label: "...Cheat Engine's walking key", kind: "pick", def: 2, picks: ["F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24"]
		, help: "The key you set in Cheat Engine for the walking speed."}))
	list.Push(V1Obj({key: "speedkeynormal", label: "...Cheat Engine's 1x key", kind: "pick", def: 1, picks: ["F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24"]
		, help: "The key you set in Cheat Engine for normal speed (1)."}))
	list.Push(V1Obj({key: "mousesteer", label: "Turn with the mouse while walking", kind: "check", def: 1
		, help: "Walking, the wizard is turned with the mouse (the right button held, the mouse slid) - at once, so it doesn't stop at corners - when you've left the keyboard and mouse alone 3 s, out of battle, by the game's memory, no window open over the game. The mouse goes back where it was. Turns on the spot stay A/D. Off: A/D only, as before."}))
	list.Push(V1Obj({key: "mobavoid", label: "Keep away from mobs (not the quest's)", kind: "check", def: 1
		, help: "Walking (quests, the potion seller): the route goes round the zone's mobs - read from the game's memory, read-only - so no battle starts on the way. Not the mobs the quest is about (named in its goal, or standing at it), and not while collecting. With no way round, it waits for the mob to move off (25 s at most). The dashboard's Map shows them: red dots."}))
	list.Push(V1Obj({key: "mobshape", label: "...what they see", kind: "pick", def: 2, picks: ["A circle all round", "A semi-circle in front", "A cone in front"]
		, help: "The shape round each mob the route keeps out of - a mob notices you there. In front: which way it faces is read from the game (unknown: the whole circle), and a little room is kept all round its body. The dashboard's Map draws it."}))
	list.Push(V1Obj({key: "mobradius", label: "...how far they notice you (game units)", kind: "num", lo: 100, hi: 3000, def: 300
		, help: "How far the shape reaches from a mob. More: safer, but narrow streets may leave no way round (then it waits for the mob to turn or move)."}))
	list.Push(V1Obj({key: "mobcone", label: "...the cone's width (degrees; a cone only)", kind: "num", lo: 5, hi: 180, def: 60
		, help: "With 'A cone in front': how wide the cone is. Players say 50 to 120."}))
	list.Push(V1Obj({key: "mobbody", label: "...their reach all round (semi-circle / cone)", kind: "num", lo: 60, hi: 1500, def: 120
		, help: "With a semi-circle or cone in front: how far round the rest of each mob the route keeps away too - a mob notices you beside or behind it from nearer than in front."}))
	list.Push(V1Obj({key: "mobgrow", label: "...more after each battle a mob not the quest's starts", kind: "check", def: 1
		, help: "Caught by a mob the quest doesn't need (not collecting, not one in the goal line, not right after X at the goal): the reach is raised to where it caught you from, and a bit - its front's (how far they notice you) when it caught you in front, its reach all round when from the side or behind. 1500 at most; set them back in Settings any time."}))
	list.Push(V1Obj({key: "mobshrink", label: "...less after 10 minutes walking without one", kind: "check", def: 1
		, help: "Every 10 minutes of walking without a mob the quest doesn't need catching the wizard, both reaches are made a tenth smaller - never below what you set yourself here (else 300 and 120) - so the routes don't go the long way round for nothing. A catch raises them again (the setting above)."}))
	list.Push(V1Obj({key: "mobwall", label: "...wait at a line of mobs with no way round (not tried yet)", kind: "check", def: 0
		, help: "Mobs standing in a line - gaps of less than 250 between what each one sees - count as one wall: the route goes all the way round its end where it can, on or off. With no way round (a street the line stands across): on, the wizard stands still till the line opens (25 s at most, then walks through the gap, still out of their reach and sight); off, it walks through the gap at once, out of their reach and sight, as before. Off by default: the gap's width hasn't been measured in the game yet. The dashboard's Map shades the closed gaps."}))
	list.Push(V1Obj({key: "duelavoid", label: "...and other players' battles (not tried yet)", kind: "check", def: 0
		, help: "With 'Keep away from mobs' on: the route also goes round other players' battles - the duel circles read from the game's memory, read-only - so the wizard doesn't walk into one and join it. With no way round, it waits for the battle to end (4 minutes at most), then walks on past it, round its edge where there's room. Off by default: how the game keeps those circles in its memory hasn't been checked in the game yet (vision\bossmem.py --duels). The dashboard's Map shows them: violet circles."}))
	list.Push(V1Obj({key: "puzzles", label: "Try to open a blocked way (puzzles)", kind: "check", def: 1
		, help: "The way to the goal blocked for good at one spot - a gate or a door that won't open (a door or gate object there by the game's memory, or still stuck there after the usual tries), in a dungeon or a building: before telling you, the bot tries what usually opens one, checking after each try - the enemies standing off to the sides fought (one camp at a time; never a boss, never one beyond the block), things with a prompt nearby X'd (never with Crowns, never a teleporter, sigil or shop), the zone's NPCs talked to. Then the notice, saying what it tried. At most twice an hour at one spot. Off: the notice at once, as before."}))
	list.Push(V1Obj({key: "puzzlelearn", label: "...learn from me when I solve one", kind: "check", def: 1
		, help: "After a 'needs you' notice (or while it waits at a blocked way), what you do to get past is recorded - the enemies you fight (which kind, where), what you press X at or talk to (its name, where), nothing else you type - and saved in learned\puzzles.txt once the way opens or the goal moves on. The next time (any character; copy the file to use it on another PC) the bot does it itself first. Mouse clicks on things aren't seen: press X."}))
	list.Push(V1Obj({key: "puzzlestate", label: "...go by a gate's state in the game's memory (not tried yet)", kind: "check", def: 0
		, help: "New, not tried in the game yet. A gate's or door's state (open / shut) read from the game's memory - its ObjectStateBehavior, read-only (vision\statemem.py). On: a state that changed since a try began counts as the way maybe open (the bot walks through to see; while it waits at the gate it looks once you're away a minute; a recording of what you do ends there), one still the same counts as shut, and a door in an open state (Open, Unlocked...) that isn't its zone file's starting one isn't taken as the block. Off: the state is only written in debug.log - doors and collision walls going from the game's memory decide, as before. Turn it on once python vision\statemem.py --watch at a gate shows its state change when it opens."}))
	list.Push(V1Obj({key: "puzzlelevers", label: "...try levers the game names nowhere (not tried yet)", kind: "check", def: 0
		, help: "New, not tried in the game yet. A lever, pedestal or book the game gives no name, found through the zone's own triggers: an object with no name whose template's name has the words of one of their use events ('PedestalUsed': CL-Pedestal-01 - a guess by the name), at most 2 of the things with a prompt, one whose trigger opens the gate at the block first. On: X'd with the things with a prompt - at any press prompt within 150 of it (never with Crowns on it, never a teleporter or shop), so it can be a neighbour's prompt. Off: only named in debug.log's plan line ('levers (zone's triggers - not tried...)'), the tries as before. Turn it on once python vision\puzzlefile.py --find <zone> <event> has shown which object fires the event."}))
	list.Push(V1Obj({key: "sigilhome", label: "Leave a sigil that won't start, and come back", kind: "check", def: 0
		, help: "New, not tried in the game yet. Off: a sigil that won't start stops the walking with a notice, nothing pressed. On: the quest's own sigil (the arrow leads to it - not one walked past) whose X doesn't start it - 30 s on, still in the same zone with no loading screen by the game's log - 3 times in a row (2 within 30 minutes of a relog): it's left and come back to - a Mark there (Page Down), Home, the Recall (Page Up) back, X again. Your Mark is never moved when it's the potion seller's (potionmark on, buying recorded at your Mark): the Commons (End) and the walk back instead. The Mark way needs the mana globe read at 20 or more. Once in 30 minutes at a sigil; still not starting: walking off and a notice. A dungeon run: after its second X that didn't load, the Mark way only (once a run)."}))
	list.Push(V1Obj({key: "|"}))
	list.Push(V1Obj({key: "-", label: "HOW IT PLAYS ITS CARDS"}))
	list.Push(V1Obj({key: "cardlogic", label: "Card logic", kind: "pick", def: 1, picks: ["Boost first, then hit", "Hit first (fast)", "Boss: boost first - mobs: hit first"]
		, help: "Boost first: traps on the boss, blades, the bubble and aura, then the biggest hit it can cast. Hit first: the biggest hit it can cast as soon as it has one, boosting only in rounds it has none (quick on weak mobs). Boss/mobs: boost first once you've picked a boss ({key:boss}), else hit first."}))
	list.Push(V1Obj({key: "boostmax", label: "Boosts before each hit (0 = all it has)", kind: "num", lo: 0, hi: 20, def: 0
		, help: "Boosting first: at most this many boost cards (blades, traps, bubble, aura) go before a hit it can cast. 0 = every one it has."}))
	list.Push(V1Obj({key: "healthocr", label: "Kill check: hit at once if that kills", kind: "check", def: 1
		, help: "Reads every enemy's health off the nameplates, and if a hit in hand already kills them all it's cast at once instead of more boosts. (Options > 2D Combat Display must be on.)"}))
	list.Push(V1Obj({key: "killmargin", label: "Kill check margin (%)", kind: "num", lo: 0, hi: 200, def: 15
		, help: "A hit only counts as a kill when its least damage is this % more than the health left (covers shields and misreads)."}))
	list.Push(V1Obj({key: "memclicks", label: "Click cards and plates where the game's memory has them (not tried yet)", kind: "check", def: 0
		, help: "New, not tried in the game yet. On: the cards are clicked where the game's memory (read-only) has them in your hand - the pictures only when it can't tell - but only at a window size where the memory's card boxes have been seen lining up with the ones the bot sees on the screen, 3 looks in a row (debug.log: 'Memory card boxes'); and your own plate (when no picture finds it) and the enemies' plates are clicked where the memory has them - the kill check then reads the enemies' health from the memory even with the kill check's OCR off (off the screen still for an Alt+1 boss or a boss whose health the game hides). Off (the default): the cards and plates are found on the screen as before; the memory's card boxes are only compared with the screen's in debug.log, so you can see whether they line up before switching this on. Read from the memory either way: your school, your health, the enemies' health, and in a party your wizards' health (who the healer heals) and the hitter's school (the blader's blades) - the screen's reading when it can't be read. All of it only with one game window open: with two or more the memory may be the other window's wizard, so everything comes off the screen as before."}))
	list.Push(V1Obj({key: "useblades", label: "Use blades (and Sharpen)", kind: "check", def: 1
		, help: "Off: blades and Sharpen aren't played (with Discard cards it never plays on, they're discarded)."}))
	list.Push(V1Obj({key: "usetraps", label: "Use traps and Feint on the boss (and Potent)", kind: "check", def: 1
		, help: "Off: traps, Feint and Potent aren't played (with Discard cards it never plays on, they're discarded). Traps only ever go on a boss you picked ({key:boss})."}))
	list.Push(V1Obj({key: "usebubble", label: "Use the bubble (global)", kind: "check", def: 1
		, help: "Off: your school's bubble isn't played (with Discard cards it never plays on, it's discarded)."}))
	list.Push(V1Obj({key: "useaura", label: "Use the aura", kind: "check", def: 1
		, help: "Off: your school's aura isn't played (with Discard cards it never plays on, it's discarded)."}))
	list.Push(V1Obj({key: "usewand", label: "Use the wand's hit", kind: "check", def: 1
		, help: "Off: the wand's own card (e.g. Minor Clash) isn't played - and isn't counted as a hit without mana when fleeing."}))
	list.Push(V1Obj({key: "usetower", label: "Use Tower Shield", kind: "check", def: 1
		, help: "Off: Tower Shield isn't played (with Discard cards it never plays on, it's discarded)."}))
	list.Push(V1Obj({key: "usereshuffle", label: "Use Reshuffle", kind: "check", def: 1
		, help: "Off: Reshuffle isn't played (with Discard cards it never plays on, it's discarded)."}))
	list.Push(V1Obj({key: "drawenchant", label: "Draw treasure cards for an enchant that kills", kind: "check", def: 0
		, help: "No hit in hand ends the battle, but one would with an enchant on it (any - Strong's +100 counted) and there's none in hand: Draw from your treasure-card deck till one comes. Draw is greyed out with 7 cards, so one card is discarded first - never a treasure card, the hit, or an enchant. Then the kill check again: the hit goes enchanted if it kills; else the enchant's kept. At most 3 draws a round, 6 a battle."}))
	list.Push(V1Obj({key: "reboost", label: "Boost again after each hit", kind: "check", def: 0
		, help: "After each hit its blades and traps may be cast again for the next one. Off: each is cast once a battle - its other copies are discarded (below)."}))
	list.Push(V1Obj({key: "solotraps", label: "I fight alone (count my traps)", kind: "check", def: 0
		, help: "Your traps and Feint go on the boss you picked (Alt+1), else - every battle - on the enemy with the most health. On: the kill check counts them on that enemy. Leave it off when others fight with you: their hits use your traps up without the bot seeing it."}))
	list.Push(V1Obj({key: "pipsave", label: "Save pips for a finishing hit (rounds)", kind: "num", lo: 0, hi: 20, def: 3
		, help: "Up to this many rounds, pips are saved for a hit in hand that ends the battle once it's affordable. 0 = never."}))
	list.Push(V1Obj({key: "discardunused", label: "Discard cards it never plays", kind: "check", def: 1
		, help: "Every round, cards in hand the bot doesn't play (and kinds switched off above) are discarded with a right-click so it draws ones it can use. Not treasure cards it learned (discarding one uses it up), nor spells set to Never discard on the dashboard's Spells tab."}))
	list.Push(V1Obj({key: "discardmax", label: "...at most this many a round", kind: "num", lo: 0, hi: 7, def: 3
		, help: "The most cards it never plays that are discarded in one round (not the blade and trap copies it can't cast again)."}))
	list.Push(V1Obj({key: "discardspent", label: "...and blade and trap copies it can't cast again (untried)", kind: "check", def: 1
		, help: "New, not tried in the game yet (LIVE_CHECKS.txt 3.11). With Boost again after each hit off, each blade and trap is cast once a battle (and once more sharpened, or made potent): its other copies in hand can't go, so they're discarded and the hand draws cards it can use. One is kept while a Sharpen (a Potent, for a trap) in hand or still in the deck could make it go. Needs the vision helper's read of the game's hand, and its card boxes seen lining up with the screen's. Never a treasure or item card's copy. Up to 3 copies of one blade or trap a round, not counted in the most a round above. Only as a Hitter (or with the party off), not in dual mode. Off: they wait in hand till a Reshuffle."}))
	list.Push(V1Obj({key: "discardunaffordable", label: "Discard hits it can't cast yet", kind: "check", def: 0
		, help: "A hit you haven't the pips for is discarded instead of kept for a later round."}))
	list.Push(V1Obj({key: "learnupgrade", label: "Make room for stronger learned hits", kind: "check", def: 1
		, help: "A learned hit 15% or more stronger than your weakest in hit1-3 takes its place, out of battle; hit1-3 stay weakest to strongest (the cheapest, your only all-enemies hit, X-pip and hitNkeep:1 slots stay put). Undo: Forget it or change its kind on the Spells tab. One school off: <school>.learnupgrade:0."}))
	list.Push(V1Obj({key: "planner", label: "Plan each round in the simulator (advice only, untried)", kind: "check", def: 0
		, help: "New, not tried in the game yet. In each round the bot plays itself - after the kill check, defending and the heals - every card in your hand (and a pass) is tried in the battle simulator from that very round on: your hand, pips and health and the enemies' health from the game's memory (read only), the blades, traps and aura the bot counts, the rest of your main deck shuffled and treasure cards drawn the bot's way, the rest of the battle played your settings' way - each play up to 100 times in 0.3 s. debug.log says what it would play and how often that won ('Plan: would play Tempest on all (won 92% in 3 rounds ...)'), and the battle recorder keeps it with what was played. Advice only: the bot still plays its own way - it never changes a card. Learned plays (from the battles recorded: per school, all schools' while yours has few) only tip near-equal plays. Needs navmem on and one game window open; not in dual mode or as a party's blader or healer (but a party leader's with partyorders on). Off: nothing asked."}))
	list.Push(V1Obj({key: "deckzone", label: "Put on the deck that fits the zone's enemies (untried)", kind: "check", def: 0
		, help: "New, not tried in the game yet. Out of battle, with no boss ahead, each in-game deck in an Equipment Set (the Cards tab's From game links them) is fought in the battle simulator against the enemy groups you've fought most in this zone (the battles recorded), each with the settings the bot would play it with (its deck profile's over yours; a deck with no profile: yours and those its cards call for; a group with a boss as a boss fight). Of your decks for the same use as the one the bot picked (collect, farming, dungeon, anything else - never a boss deck), the one that wins clearly more often (5 points, or as often in a round fewer) is put on instead - debug.log says so ('Deck: <name> - the simulator's pick for <zone>'s enemies: 92% won...'). Not the deck pinned on the Cards tab or a dungeon run's. A zone with no battle recorded yet: as now. Off: decks are picked as before."}))
	list.Push(V1Obj({key: "battlerec", label: "Record every battle (to learn from)", kind: "check", def: 1
		, help: "Every battle - yours too - is written down from the game's own log and memory (read only): the enemies, each round's hand, what was played, on whom and why, the damage, the result, your deck. Kept in learned\battles\ (about 5 MB a day of play; old months zipped), never sent anywhere. Off: nothing is recorded."}))
	list.Push(V1Obj({key: "-", label: "NEW SPELLS AND SPELL QUESTS (NOT BUILT YET)"}))
	list.Push(V1Obj({key: "deckadd", label: "Put new spells in the deck (not built yet)", kind: "check", def: 0
		, help: "New, NOT BUILT YET - leave it off. What's built either way (with navmem on and the vision helper running): out of battle, about every 10 minutes, the spells your wizard knows are read from the game's memory (read only) and kept in learned\spellbook_<wizard>.txt; a spell that wasn't there is written in debug.log once ('Spells: new spell Thunder Snake (Storm, 1 pip, Damage)') - the first look at a wizard only writes its file. On: a new spell is also announced - a tray tip and the Discord alert, to add it to a deck yourself - and kept for when the bot can put it in a deck itself (stronger hits, heals, blades and shields of your school, within the deck's limits: vision\spellplan.py); that needs the deck page's windows, not seen in the game yet. Treasure and item cards would never be touched."}))
	list.Push(V1Obj({key: "trainspells", label: "Spend training points at the trainers (not built yet)", kind: "check", def: 0
		, help: "New, NOT BUILT YET - leave it off: on, debug.log says once that it isn't built, nothing else happens. What it's for: the training points spent at the trainers, by a set plan per school (trainplans.txt - a draft, every spell name in it still to be checked in the game; your own copy in learned\trainplans.txt wins): the trainer walked to, the planned spell learned. It needs the training points and the trainer's window read from the game first. python vision\spellplan.py --school <yours> --live says what the plan would train next. Gold only: training points are never bought (that takes Crowns)."}))
	list.Push(V1Obj({key: "spellquests", label: "Take and do spell quests (not built yet)", kind: "check", def: 0
		, help: "New, NOT BUILT YET - leave it off: on, debug.log says once that it isn't built, nothing else happens. What it's for: a spell quest made the tracked quest in the quest book as soon as one is open - the walker then does it as any other - and the main quest tracked again once it's done. It needs to know what marks a spell quest (the helper's /quests lists every quest with all its properties) and the quest book's windows first. The walker already does the tracked quest; NPCs with a '!' (a quest on offer) aren't talked to."}))
	list.Push(V1Obj({key: "-", label: "NETWORK (THE DASHBOARD'S NETWORK TAB)"}))
	list.Push(V1Obj({key: "neton", label: "Show this bot to the others on your home network", kind: "check", def: 0
		, help: "Its state (PC, version, wizard, zone, on/off, Play for me, what it's doing, health, mana, deaths, last log line) goes to every bot on your home network with this on, and theirs shows on the dashboard's Network tab - with their log and game when you pick one. Windows asks once to let Python through its firewall: allow it on Private networks (your network has to be set to Private). Off: nothing sent or listened for."}))
	list.Push(V1Obj({key: "netport", label: "...on the port", kind: "num", lo: 1024, hi: 65535, def: 47150
		, help: "The same on every PC. UDP for finding each other, TCP for the log, the picture and commands."}))
	list.Push(V1Obj({key: "netpin", label: "...network PIN for commands (0 = none)", kind: "num", lo: 0, hi: 99999999, def: 0
		, help: "The Network tab's buttons (bot on, bot off, Play for me off, restart) only work between bots with the same PIN, not 0. Play for me can only be switched off from the network - on only at that PC (its dashboard's button or tray menu)."}))
	list.Push(V1Obj({key: "-", label: "UPDATES"}))
	list.Push(V1Obj({key: "autoupdate", label: "Update by itself: look every (minutes, 0 = never)", kind: "num", lo: 0, hi: 1440, def: 10
		, help: "A new version on GitHub is downloaded while the bot plays on, then installed with no question: the bot closes itself for it once it's out of battle, nothing's loading and you've left the keyboard and mouse alone a minute (Play for me: no wait) - not during a dungeon run or a recording - and starts again as it was: on, off or in standby, Play for me, walking ({key:walk}), auto-reconnect and Learn every card as they were. Your settings, learned cards and routes are kept, as with the Updates button. A version that won't install 3 times is left to the Updates button. 0: only when you click it."}))
	list.Push(V1Obj({key: "-", label: "ALERTS"}))
	list.Push(V1Obj({key: "logmirror", label: "Copy the log to OneDrive (help from another PC)", kind: "check", def: 0
		, help: "debug.log is also written to your OneDrive folder (Wiz-Maxxing logs\<this PC's name>), with a picture of the game every 2 minutes and at each alert (the newest 15) - OneDrive syncs it to your other PCs, so the bot can be followed from there. Nothing else is sent anywhere."}))
	list.Push(V1Obj({key: "alertson", label: "Discord alerts when the wizard needs you", kind: "check", def: 1
		, help: "Stuck, out of potions or mana, logged out, a quest that needs you...: a message to your Discord channel - once its webhook is set (tray menu: Discord alerts...). The same alert at most once in 10 minutes."}))
	list.Push(V1Obj({key: "-", label: "PARTY (ONE WIZARD PER PC, SAME HOME NETWORK)"}))
	list.Push(V1Obj({key: "partyrole", label: "This wizard in the party", kind: "pick", def: 1, picks: ["Off", "Leader - quests, the others follow", "Follower - goes where the leader goes"]
		, help: "Leader: quests as now, and waits while a follower is far, in another zone or not ready. Follower: goes where the leader goes instead of its own quest - to it, through the door it took, into its battles. Set this wizard's party name, and on a follower the leader PC's address, with the tray menu's Party.... The leader's PC asks once (Windows) to let Python through its firewall - allow it on Private networks."}))
	list.Push(V1Obj({key: "partyport", label: "...the party's port", kind: "num", lo: 1024, hi: 65535, def: 47140
		, help: "The leader's bot listens for its followers on this port of your home network; the same on every PC in the party."}))
	list.Push(V1Obj({key: "partynear", label: "...a follower stays this near the leader", kind: "num", lo: 80, hi: 2000, def: 250
		, help: "A follower walks to within this many game units of the leader, and walks again once the leader is twice as far."}))
	list.Push(V1Obj({key: "partywaitdist", label: "...the leader waits for one farther than", kind: "num", lo: 300, hi: 10000, def: 800
		, help: "The leader stops while a follower is farther than this (game units), in another zone, loading or not ready."}))
	list.Push(V1Obj({key: "partywaitmax", label: "...but for at most (s, 0 = no waiting)", kind: "num", lo: 0, hi: 900, def: 60
		, help: "How long the leader waits for one follower; after that it walks on without it till it's been near again. 0: it never waits. A follower that says it can't follow - the leader teleported (End, Home, a sigil, a potion run) or went through a door that didn't take it - isn't waited for either, till it's been near again."}))
	list.Push(V1Obj({key: "partytpdoors", label: "...a follower trusts the helper's teleport guess (untried)", kind: "check", def: 0
		, help: "The leader's helper tells a door the leader walked through from a teleport (End, Home, a sigil, a potion run - it stood still before its zone changed). On: a follower doesn't walk to where the leader teleported from - it says it can't follow and waits there, and the leader walks on without it. Off: it walks there all the same, as before, and gives the spot up after 3 tries; the guess only goes to debug.log. Not checked in the game yet: leave it off till the helper's log (party: A -> B: walked through a door / a teleport) has been right for your doors."}))
	list.Push(V1Obj({key: "partybattle", label: "...in a party battle this wizard is the", kind: "pick", def: 1, picks: ["Hitter - plays as now", "Blader - boosts the party's hitter", "Healer - heals the party, else boosts"]
		, help: "A battle with more of the party's wizards on your side: Hitter plays as now. Blader puts its blades on the party's hitter (the wizard set to Hitter, else the leader) and its traps on the enemy the hitter goes for, casting them again after each of its hits, Tower Shield on it, and hits only for a kill or with nothing else to do. Healer heals whichever of you is lowest under 'Heal under this %', shields them, else boosts as a blader. Each wizard's name has to be known: one battle on its own first. One school's wizard its own: <school>.partybattle:2 in PlayerStats.txt. {key:boost} on a plate: the boosts go there (a friend without the bot)."}))
	list.Push(V1Obj({key: "partyhitround", label: "...a blader or healer times its boosts to the hit (untried)", kind: "check", def: 0
		, help: "New, not tried in the game yet. The party's hitter says which round its planned hit goes out in (the earliest its pips allow) and each wizard its place in your side's cast order. On (on the blader's or healer's PC): its blades and traps wait till the hit is due - that very round when it casts before the hitter, else the round before - and meanwhile it plays as with none in hand (Tower Shield, a hit only with nothing else to do). debug.log says so ('party hit round: <hitter>'s hit is due in round 6 ...'). The hitter needs this version too (an older one says nothing: boosts as ever). Off: boosts go on as soon as they can, as before."}))
	list.Push(V1Obj({key: "partyorders", label: "...the leader plans the team's round (advice only, untried)", kind: "check", def: 0
		, help: "New, not tried in the game yet - on every PC of the party (each on this version), and planner on the leader's. Each follower's bot sends the leader's the hand its helper read from the game's memory (read only), with its pips and health. The leader's planner tries the whole team's round in the battle simulator with those hands (its round takes about 1.5 s longer) and sends each follower the card it would have it play. A follower waits up to 3 s in its round for it and only writes it to debug.log ('Plan: the leader would have you play Stormblade (won 80%, 12 tries) ...') - the battle recorder keeps it with what was played. Advice only: nothing is ever cast from it, the follower plays its own way as ever. A follower whose hand isn't in when the leader plans is played its role's way. A round the leader doesn't plan (a kill, a defence, a heal, its bot off) is told at once. No order (an older bot, the leader too slow): its own way - after two rounds in a row with none it stops waiting that battle, after six till an order comes. A blader or healer leader plans too, in a round a follower's hand is in. Off on a PC: it sends, waits for and writes nothing new."}))
	list.Push(V1Obj({key: "-", label: "THE OVERLAY (OVER THE GAME)"}))
	list.Push(V1Obj({key: "overlay", label: "Show the map and the log over the game (untried)", kind: "check", def: 0
		, help: "New, not tried in the game yet. The zone map round your wizard and the newest log lines (coloured as on the dashboard), drawn see-through over Wizard101 - borderless or windowed, not exclusive full screen - only while Wizard101 is the window in front and not minimised. Clicks go through it to the game, it never takes the focus, and Windows keeps it out of every screen capture: the bot's own screen reading can't see it (nor can your screenshots or recordings). Each time it's switched on a small pink square shows for a moment on the game - the bot checking that. Needs Windows 10 version 2004 or newer and the vision helper (it draws both) - otherwise it stays off and debug.log says why. {key:overlay} or the tray menu switches it too."}))
	list.Push(V1Obj({key: "overlaymapat", label: "...the map", kind: "pick", def: 2, picks: ["Off", "Top left", "Top right", "Bottom left", "Bottom right"]
		, help: "Where the map goes over the game, or Off: the dashboard's Map - you (the arrow, the way you face), the path, the planned route, the quest goal, mobs and quest items - see-through, its empty parts clear. With the log in the same corner the log goes next to it (under it at the top, above it at the bottom). dashboard.ini [overlay]: mapdx / mapdy move it by pixels, mapspan is how much of the zone it shows (game units across, 4000) - read when it's switched on."}))
	list.Push(V1Obj({key: "overlaymapsize", label: "...the map's size (% of the game's height)", kind: "num", lo: 15, hi: 60, def: 28
		, help: "The map is a square this tall: 28 is a little over a quarter of the game's height."}))
	list.Push(V1Obj({key: "overlaylogat", label: "...the log", kind: "pick", def: 2, picks: ["Off", "Top left", "Top right", "Bottom left", "Bottom right"]
		, help: "Where the log goes over the game, or Off: the newest lines of the dashboard's log in its colours (its Colours button), the newest at the bottom, older ones fainter, a line too long cut short. dashboard.ini [overlay]: logdx / logdy move it by pixels."}))
	list.Push(V1Obj({key: "overlaylines", label: "...the log's lines", kind: "num", lo: 3, hi: 30, def: 10
		, help: "How many of the newest lines it shows (fewer when they don't fit)."}))
	list.Push(V1Obj({key: "overlaylogwidth", label: "...the log's width (% of the game's width)", kind: "num", lo: 20, hi: 90, def: 38
		, help: "Longer lines are cut short with ..."}))
	list.Push(V1Obj({key: "overlaytext", label: "...the log's text size (%)", kind: "num", lo: 60, hi: 200, def: 100
		, help: "100 is about 15 pixels on a 1080-high game, bigger on a bigger one."}))
	list.Push(V1Obj({key: "overlayback", label: "...the dark box behind them (%, 0 none)", kind: "num", lo: 0, hi: 90, def: 35
		, help: "How dark the rounded box behind the map and the log is: 0 none (only the map's floor and the text), 90 almost solid."}))
	list.Push(V1Obj({key: "overlayopacity", label: "...how solid it is (%)", kind: "num", lo: 20, hi: 100, def: 90
		, help: "The map and the log as a whole: 100 as drawn, lower lets more of the game through."}))
	return list
	}

;The settings the simple view shows - the most used ones
CfgSimpleKeys()
	{
	static keys := ""
	if (!IsObject(keys))
		{
		keys := V1Obj()
		for each, k in ["handsoffon", "mouselock", "gamefront", "healat", "potionat", "potionwalk", "fleeon", "quicksell", "enemyspells", "defendat", "battlesonly", "mobavoid", "mousesteer", "speedhack"
			, "cardlogic", "healthocr", "drawenchant", "alertson", "partyrole", "partybattle", "overlay"]
			keys[k] := 1
		}
	return keys
	}

;CfgList as the view shows it: all of it, or (simple) only CfgSimpleKeys' settings, the headings that have some under
;them, no "|" column breaks (the window's height decides)
CfgViewList()
	{
	if (!CfgSimple)
		return CfgList()
	keys := CfgSimpleKeys(), out := [], head := ""
	for each, s in CfgList()
		{
		if (s.key = "-")
			head := s
		else if (s.key != "|" && keys.Has(s.key))
			{
			if (IsObject(head))
				out.Push(head), head := ""
			out.Push(s)
			}
		}
	return out
	}

;A help text's keys ({key:<id>}: {key:boss} -> Alt+1...) as they're set now - the Keys tab's, Hotkeys.ahk (CfgList is
;made once, the window afresh each time it opens)
CfgKeyWords(text)
	{
	while (RegExMatch(text, "\{key:(\w+)\}", &m))
		text := StrReplace(text, m[0], HkText(m[1]))
	return text
	}

;Opens the window - made afresh, with the values in use now - or brings it to the front if it's open
CfgShow()
	{
	static hooked := 0
	global CfgCtls, CfgShownVals, CfgHelps, CfgHelpShown, CfgSimple, Cfg, CfgHwnd, CfgReopenX, CfgPending ; (v1 globals it sets)
	if (CfgHwnd && WinExist("ahk_id " CfgHwnd))
		{
		WinActivate("ahk_id " CfgHwnd)
		return
		}
	;(the help line follows the mouse: WM_MOUSEMOVE)
	if (!hooked)
		OnMessage(0x200, CfgHover), hooked := 1
	CfgCtls := V1Obj(), CfgShownVals := V1Obj(), CfgHelps := V1Obj(), CfgHelpShown := ""
	CfgSimple := ViewSimple("settings")
	;(v1: Gui, Cfg:New destroyed a Cfg window still there)
	try Cfg.Destroy()
	Cfg := Gui("-MaximizeBox", "Wizard101 bot " BotVersion() " - settings"), CfgHwnd := Cfg.Hwnd
	Cfg.OnEvent("Close", CfgGuiClose)
	Cfg.OnEvent("Escape", CfgGuiEscape)
	;(v1: Gui, Cfg:Color, 1B1D22, 111317 - the window's colour, and 111317 behind every Edit and DropDownList: v2 gives
	;each of those its own Background111317 below)
	Cfg.BackColor := "1B1D22"
	Cfg.MarginX := 12, Cfg.MarginY := 10
	;(next to the dashboard when it's up, else in the middle of the main monitor - all of it on that monitor: the
	;settings in columns (CfgPlace) as tall and as many as fit it, with the help line and the buttons under them; more
	;columns than fit its width: a tab for each heading, its settings in columns inside it)
	cfgPos := "", cfgAtX := A_ScreenWidth // 2, cfgAtY := A_ScreenHeight // 2
	if (DashHwnd && DashShown)
		{
		;(not a minimised dashboard's place: -32000)
		;(v1: WinGet MinMax / WinGetPos of a window not found gave blanks - no place taken from it; v2 throws, and its
		;WinGetPos unsets the output variables first - the blanks are set in the catch)
		cfgMm := V1Try(WinGetMinMax, "ahk_id " DashHwnd)
		try WinGetPos(&cfgDx, &cfgDy, , , "ahk_id " DashHwnd)
		catch
			cfgDx := "", cfgDy := ""
		if (cfgDx != "" && cfgMm != -1)
			cfgPos := "x" cfgDx + 30 " y" cfgDy + 60 " ", cfgAtX := cfgDx + 30, cfgAtY := cfgDy + 60
		}
	;(the view switched: where the window was)
	if (CfgReopenX != "")
		cfgPos := "x" CfgReopenX " y" CfgReopenY " ", cfgAtX := CfgReopenX, cfgAtY := CfgReopenY, CfgReopenX := ""
	DashMonitorAt(cfgAtX, cfgAtY, &cfgML, &cfgMT, &cfgMR, &cfgMB)
	cfgMaxY := Max(300, Floor((cfgMB - cfgMT) * 96 / A_ScreenDPI) - 140)
	;(column n's right edge: 434 + 432 (n - 1), and the window's frame)
	cfgMaxCols := Max(1, (Floor((cfgMR - cfgML) * 96 / A_ScreenDPI) - 24 - 434) // 432 + 1)
	cfgPlan := CfgPlace(cfgMaxY, false)
	if (cfgPlan.cols > cfgMaxCols)
		{
		;(the tabs' buttons above the settings, its frame below them - as many rows of buttons as the names need at the
		;window's width: a narrow window (one column on a 1920x1080 screen) wraps them to 2 or 3 rows, so the settings
		;start under the last row, measured (CfgTabsTop) - not under the first, hidden behind the others)
		cfgTop := 44
		Loop 4
			{
			cfgPlan := CfgPlace(cfgMaxY - 10 - (cfgTop - 44), true, cfgTop)
			cfgTabNames := ""
			for each, cfgT in cfgPlan.tabs
				cfgTabNames .= (cfgTabNames = "" ? "" : "|") cfgT
			cfgNeed := CfgTabsTop(432 * cfgPlan.cols + 6, cfgTabNames)
			if (cfgNeed <= cfgTop || A_Index = 4)
				break
			cfgTop := cfgNeed
			}
		Cfg.SetFont("s9 w600 cF2F2F2", "Segoe UI")
		Tab := Cfg.Add("Tab3", "x6 y8 w" 432 * cfgPlan.cols + 6 " h" cfgPlan.bottom + 2 " +Buttons -Theme", StrSplit(cfgTabNames, "|"))
		}
	cfgTab := 0
	for each, cfgAt in cfgPlan.items
		{
		cfgS := cfgAt.s, cfgX := cfgAt.x, cfgY := cfgAt.y
		if (cfgAt.tab != cfgTab)
			{
			cfgTab := cfgAt.tab
			Tab.UseTab(cfgTab)
			}
		if (cfgS.key = "-")
			{
			Cfg.SetFont("s9 w600 c8AB4F8", "Segoe UI")
			Cfg.Add("Text", "x" cfgX " y" cfgY " w410 h18", cfgS.label)
			continue
			}
		cfgV := Stats.Has(cfgS.key) ? Stats[cfgS.key] : cfgS.def
		;(a wizard's own value - storm.killmargin... - is used when it fights as that school; the window doesn't
		;change it, so the help says where it is)
		cfgHelp := CfgKeyWords(cfgS.help)
		for each, cfgSch in ["storm", "fire", "ice", "life", "death", "myth", "balance"]
			if (Stats.Has(cfgSch "." cfgS.key))
				cfgHelp .= "  Your " cfgSch " wizard has its own: " cfgSch "." cfgS.key ":" Stats[cfgSch "." cfgS.key] " in PlayerStats.txt (change it there)."
		;(a label the mouse can be over - SS_NOTIFY - and its control right of it)
		cfgW := (cfgS.kind = "pick") ? 90 : 300
		Cfg.SetFont("s9 w400 cDADADA", "Segoe UI")
		cfgL := Cfg.Add("Text", "x" cfgX " y" cfgY + 3 " w" cfgW " h18 +0x100", cfgS.label).Hwnd
		cfgCx := cfgX + cfgW + 8
		;(a change not saved before the view was switched: shown, still to be saved - cfgV stays what's in use)
		cfgNew := (IsObject(CfgPending) && CfgPending.Has(cfgS.key)) ? CfgPending[cfgS.key] : ""
		if (cfgS.kind = "check")
			{
			cfgV := cfgV ? 1 : 0
			cfgC := Cfg.Add("Checkbox", "x" cfgCx " y" cfgY + 3 " w18 h18 Checked" (cfgNew != "" ? cfgNew : cfgV)).Hwnd
			}
		else if (cfgS.kind = "pick")
			{
			cfgV := Max(1, Min(cfgS.picks.Length, Round(cfgV)))
			;(v1's cfgList - cfgListVar: v2 has the function CfgList by that name)
			cfgListVar := ""
			for each, cfgP in cfgS.picks
				cfgListVar .= (cfgListVar = "" ? "" : "|") cfgP
			cfgC := Cfg.Add("DropDownList", "x" cfgCx " y" cfgY " w312 AltSubmit Background111317 Choose" (cfgNew != "" ? cfgNew : cfgV), StrSplit(cfgListVar, "|")).Hwnd
			}
		else
			{
			cfgV := Round(cfgV)
			cfgC := Cfg.Add("Edit", "x" cfgCx " y" cfgY " w70 h22 Number Right Background111317", cfgNew != "" ? cfgNew : cfgV).Hwnd
			;(0x80: no thousands commas)
			cfgU := Cfg.Add("UpDown", "Range" cfgS.lo "-" cfgS.hi " 0x80", cfgNew != "" ? cfgNew : cfgV).Hwnd
			CfgHelps[cfgU + 0] := cfgHelp
			}
		CfgCtls[cfgS.key] := cfgC, CfgShownVals[cfgS.key] := cfgV
		CfgHelps[cfgL + 0] := cfgHelp, CfgHelps[cfgC + 0] := cfgHelp
		}
	if (cfgTab)
		Tab.UseTab()
	cfgY := cfgPlan.bottom + (cfgTab ? 14 : 6)
	Cfg.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	cfgHelpW := 432 * cfgPlan.cols - 32
	CfgPending := ""
	Cfg.Add("Text", "x12 y" cfgY " w" cfgHelpW " h36 vCfgHelpText", "Point at a setting to see what it does. Each is a line in PlayerStats.txt: Save writes them there and the bot uses them at once - no restart." (CfgSimple ? " These are the most used ones - All settings shows the rest." : ""))
	cfgY += 44
	Cfg.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonSave := Cfg.Add("Button", "x12 y" . cfgY . " w90 h26 Default", "Save")
	ogcButtonSave.OnEvent("Click", CfgSave.Bind("Normal"))
	ogcButtonDefaults := Cfg.Add("Button", "x+8 yp w90 h26", "Defaults")
	ogcButtonDefaults.OnEvent("Click", CfgDefaults.Bind("Normal"))
	ogcButtonOpenPlayerStatstxt := Cfg.Add("Button", "x+8 yp w150 h26", "Open PlayerStats.txt")
	ogcButtonOpenPlayerStatstxt.OnEvent("Click", CfgOpenFile.Bind("Normal"))
	ogcButtonClose := Cfg.Add("Button", "x+8 yp w90 h26", "Close")
	ogcButtonClose.OnEvent("Click", CfgGuiClose.Bind("Normal"))
	Cfg.Add("Button", "x+8 yp w110 h26", CfgSimple ? "All settings" : "Fewer settings").OnEvent("Click", CfgViewToggle.Bind("Normal"))
	Cfg.SetFont("s9 w400 cB9E2B9", "Segoe UI")
	ogcTextCfgNote := Cfg.Add("Text", "x+14 yp+5 w370 h18 vCfgNote")
	Cfg.Title := "Wizard101 bot " BotVersion() " - settings"
	Cfg.Show(cfgPos "AutoSize")
	;(all of it on that monitor - its Save button too: moved up and left as far as it needs)
	;(v1: WinGetPos of a window not found - hidden, DetectHiddenWindows off - gave blanks: no move; v2 throws, and
	;unsets the output variables first - the blanks are set in the catch)
	try WinGetPos(&cfgWx, &cfgWy, &cfgWw, &cfgWh, "ahk_id " CfgHwnd)
	catch
		cfgWx := "", cfgWy := "", cfgWw := "", cfgWh := ""
	if (cfgWx != "")
		{
		cfgNx := Max(cfgML, Min(cfgWx, cfgMR - cfgWw)), cfgNy := Max(cfgMT, Min(cfgWy, cfgMB - cfgWh))
		if (cfgNx != cfgWx || cfgNy != cfgWy)
			try WinMove(cfgNx, cfgNy, , , "ahk_id " CfgHwnd)  ; (v1: WinMove on a window gone did nothing)
		}
	}

;Where each of CfgList's settings and headings goes in the window: {items: [{s: the setting, x, y, tab}], cols: the
;most columns, bottom: the lowest y used, tabs: their names}. Down in columns from the top, a new one at "|" and
;wherever the next wouldn't end above maxY (a heading goes with its first setting). tabbed: each heading starts a
;tab of its own (named after it; the heading itself not shown), the settings under the tabs' buttons (from top - one
;row of them: 44), "|" left out
CfgPlace(maxY, tabbed, top := "")
	{
	top := top != "" ? top : tabbed ? 44 : 12
	plan := V1Obj({items: [], cols: 1, bottom: top, tabs: []})
	x := 12, y := top, col := 1
	for each, s in CfgViewList()
		{
		if (s.key = "|")
			{
			if (!tabbed && y > top)
				x += 432, y := top, col += 1
			continue
			}
		if (s.key = "-" && tabbed)
			{
			name := s.label
			name := StrLower(name)
			plan.tabs.Push(Format("{:U}", SubStr(name, 1, 1)) SubStr(name, 2)), x := 12, y := top, col := 1
			continue
			}
		if (y > top && y + (s.key = "-" ? 8 + 26 + 28 : 28) > maxY)
			x += 432, y := top, col += 1
		;(a gap above a heading that isn't the first)
		if (s.key = "-" && y > top)
			y += 8
		plan.items.Push(V1Obj({s: s, x: x, y: y, tab: plan.tabs.Length}))
		y += (s.key = "-") ? 26 : 28
		plan.bottom := Max(plan.bottom, y), plan.cols := Max(plan.cols, col)
		}
	return plan
	}

;Where the settings start under the tabs' buttons (the window's units): the same Tab3 made in a window never shown, at
;width w with those names, its buttons' rows measured - they wrap when the names don't fit one row. 44 for one row
CfgTabsTop(w, names)
	{
	global CfgMGui ; (v1 globals it sets)
	;(v1's GUI CfgM - CfgMGui here: a v2 variable cfgM would be CfgWrite's match too, names being case-insensitive)
	CfgMGui := Gui()
	CfgMGui.SetFont("s9 w600", "Segoe UI")
	ctTab := CfgMGui.Add("Tab3", "x6 y8 w" w " h200 +Buttons -Theme", StrSplit(names, "|")).Hwnd
	;(TCM_GETITEMCOUNT, then each button's rect - TCM_GETITEMRECT - in the control's own pixels)
	ctN := DllCall("SendMessage", "Ptr", ctTab, "UInt", 0x1304, "Ptr", 0, "Ptr", 0, "Ptr"), ctBottom := 0
	ctRect := Buffer(16, 0)
	Loop ctN
		if (DllCall("SendMessage", "Ptr", ctTab, "UInt", 0x130A, "Ptr", A_Index - 1, "Ptr", ctRect.Ptr, "Ptr"))
			ctBottom := Max(ctBottom, NumGet(ctRect, 12, "Int"))
	CfgMGui.Destroy()
	;(v1: Gui, Cfg:Default after - v2 names the Gui each call works on)
	;(pixels to the window's units - 96 a inch, as Gui positions are given)
	return Max(44, 8 + Ceil(ctBottom * 96 / A_ScreenDPI) + 8)
	}

;The help for what the mouse is over: a label (SS_NOTIFY) or a control in the window
CfgHover(wParam, lParam, msg, hwnd)
	{
	global CfgHelpShown ; (v1 globals it sets)
	;(v1: A_Gui != "Cfg" - the message wasn't for the Settings window or one of its controls)
	cfgG := GuiFromHwnd(hwnd, true)
	if (!cfgG || cfgG.Hwnd != CfgHwnd || !IsObject(CfgHelps))
		return
	cfgT := CfgHelps.Has(hwnd + 0) ? CfgHelps[hwnd + 0] : ""
	if (cfgT = "" || cfgT == CfgHelpShown)
		return
	CfgHelpShown := cfgT
	Cfg["CfgHelpText"].Value := cfgT
	}

;Writes the settings changed in the window to PlayerStats.txt and reads them all again (used from now on).
;A number outside its range is brought into it; one that isn't a number is left as it was
CfgSaveNow()
	{
	cfgPairs := [], cfgSaid := "", cfgFixed := ""
	for each, cfgS in CfgList()
		{
		if (!CfgCtls.Has(cfgS.key))
			continue
		cfgC := CfgCtls[cfgS.key]
		;(v1: GuiControlGet by the control's hwnd - an Edit's text, a checkbox's 0 / 1, an AltSubmit list's position)
		cfgV := GuiCtrlFromHwnd(cfgC).Value
		if (cfgS.kind = "num")
			{
			cfgV := Trim(cfgV)
			if !IsInteger(cfgV)
				{
				cfgFixed .= ", " cfgS.key " (not a number - left as it was)"
				GuiCtrlFromHwnd(cfgC).Value := CfgShownVals[cfgS.key]
				continue
				}
			if (cfgV < cfgS.lo || cfgV > cfgS.hi)
				{
				cfgV := Max(cfgS.lo, Min(cfgS.hi, cfgV))
				cfgFixed .= ", " cfgS.key " (" cfgS.lo " to " cfgS.hi ": " cfgV ")"
				GuiCtrlFromHwnd(cfgC).Value := cfgV
				}
			}
		cfgV := V1N(cfgV) + 0
		if (cfgV != CfgShownVals[cfgS.key])
			cfgPairs.Push([cfgS.key, cfgV]), cfgSaid .= ", " cfgS.key " " CfgShownVals[cfgS.key] " -> " cfgV
		}
	if (!cfgPairs.Length)
		{
		Cfg["CfgNote"].Value := "Nothing changed" (cfgFixed = "" ? "" : " - " SubStr(cfgFixed, 3))
		return
		}
	;(the mobs' reach you set yourself: the least the shrink after quiet walking comes back down to - Vision.ahk
	;MobShrinkTick)
	for each, cfgKv in cfgPairs.Clone()
		if (cfgKv[1] = "mobradius" || cfgKv[1] = "mobbody")
			cfgPairs.Push([cfgKv[1] "floor", cfgKv[2]])
	if (!CfgWrite(cfgPairs))
		{
		Cfg["CfgNote"].Value := "Couldn't write PlayerStats.txt - nothing was saved"
		DebugLog("Settings: couldn't write PlayerStats.txt - nothing was saved")
		return
		}
	for each, cfgKv in cfgPairs
		CfgShownVals[cfgKv[1]] := cfgKv[2]
	;(the tray menu's tick and the dashboard's Wait for me button)
	HandsOffShow()
	DebugLog("Settings saved (used from now on): " SubStr(cfgSaid, 3) (cfgFixed = "" ? "" : " | " SubStr(cfgFixed, 3)))
	;(battles only switched: said, walking off - Autofarmer.ahk BattlesOnlyTick, the tray menu's tick)
	if (V1IsFunc("BattlesOnlyTick"))
		BattlesOnlyTick.Call()
	;(the battle recorder switched on or off at once, the helper told out of a round - BattleRec.ahk BrecHello)
	if (V1IsFunc("BrecHello"))
		BrecHello.Call("later")
	;(the speedhack switched on: Cheat Engine started, when Setup set it up - Autofarmer.ahk SpeedCheatEngine)
	for each, cfgKv in cfgPairs
		if (cfgKv[1] = "speedhack" && cfgKv[2] = 1 && V1IsFunc("SpeedCheatEngine"))
			SpeedCheatEngine.Call("the speedhack switched on in Settings")
	Cfg["CfgNote"].Value := "Saved " cfgPairs.Length " change" (cfgPairs.Length = 1 ? "" : "s") " - used from now on" (cfgFixed = "" ? "" : " (" SubStr(cfgFixed, 3) ")")
	}

;Every setting's default in the window (saved only with Save)
CfgFillDefaults()
	{
	for each, cfgS in CfgList()
		{
		if (!CfgCtls.Has(cfgS.key))
			continue
		cfgC := CfgCtls[cfgS.key]
		if (cfgS.kind = "pick")
			GuiCtrlFromHwnd(cfgC).Choose(cfgS.def)
		else
			GuiCtrlFromHwnd(cfgC).Value := cfgS.def
		}
	Cfg["CfgNote"].Value := "Defaults filled in - Save to use them"
	}

;Sets key:value lines in PlayerStats.txt - in their own lines (every one, if a key is in more than one), their
;comments kept; one the file doesn't have yet at its end, under a heading - and reads the settings again.
;False if the file couldn't be written
CfgWrite(pairs)
	{
	cfgWas := A_IsCritical
	Critical()
	cfgPath := A_WorkingDir "\PlayerStats.txt"
	cfgText := ""
	if (FileExist(cfgPath))
		{
		cfgText := V1FileRead(cfgPath)
		if (ErrorLevel)
			return CfgUncritical(cfgWas, false)
		}
	cfgLines := StrSplit(StrReplace(cfgText, "`r"), "`n")
	if (cfgLines.Length && cfgLines[cfgLines.Length] = "")
		cfgLines.Pop()
	cfgHead := "; ---- Set in the Settings window (the dashboard's Settings button) ----"
	for each, cfgKv in pairs
		{
		cfgFound := false
		for cfgI, cfgLn in cfgLines
			if (RegExMatch(cfgLn, "i)^(\s*\Q" cfgKv[1] "\E\s*:\s*)[^;\s]*(.*)$", &cfgM))
				cfgLines[cfgI] := cfgM[1] cfgKv[2] cfgM[2], cfgFound := true
		if (cfgFound)
			continue
		cfgHas := false
		for cfgI, cfgLn in cfgLines
			if (cfgLn == cfgHead)
				cfgHas := true
		if (!cfgHas)
			cfgLines.Push(""), cfgLines.Push(cfgHead)
		cfgLines.Push(cfgKv[1] ":" cfgKv[2])
		}
	cfgOut := ""
	for cfgI, cfgLn in cfgLines
		cfgOut .= cfgLn "`r`n"
	V1Do(FileDelete, cfgPath ".tmp")
	V1Do(FileAppend, cfgOut, cfgPath ".tmp")
	if (ErrorLevel)
		return CfgUncritical(cfgWas, false)
	V1Do(FileMove, cfgPath ".tmp", cfgPath, 1)
	if (ErrorLevel)
		return CfgUncritical(cfgWas, false)
	LoadStats(true)
	return CfgUncritical(cfgWas, true)
	}

;Critical off again unless it was on before (wasOn); returns result
CfgUncritical(wasOn, result)
	{
	if (!wasOn)
		Critical("Off")
	return result
	}

;---- The mouse back where it was ----

;Remembers where the mouse is as the bot takes it (a battle round, a click out of battle) - unless that's
;remembered already: it goes back once, when the bot's done (MouseLetGo). True if it was taken now. Not with
;mousereturn:0 (the Settings window's "Put the mouse back afterwards")
MouseGrab()
	{
	global MouseHomeX, MouseHomeY, MouseHomeSet, MouseHomeAt ; (v1 globals it sets)
	;(one taken over 10 minutes ago and never given back is stale: taken afresh)
	if ((MouseHomeSet && A_TickCount - MouseHomeAt < 600000) || !Stat("mousereturn"))
		return false
	MouseGetPos(&MouseHomeX, &MouseHomeY)
	MouseHomeSet := 1, MouseHomeAt := A_TickCount
	return true
	}

;Puts the mouse back where MouseGrab found it - not if you've used the keyboard or mouse since (you're there:
;it's yours) - and forgets it. 1 if it's back there, -1 if it was left to you, 0 if nothing was taken (or
;mousereturn:0)
MouseLetGo()
	{
	global MouseHomeSet ; (v1 globals it sets)
	if (!MouseHomeSet)
		return 0
	MouseHomeSet := 0
	if (!Stat("mousereturn"))
		return 0
	if (UserIdle() < A_TickCount - MouseHomeAt)
		return -1
	MouseGetPos(&mouseNowX, &mouseNowY)
	;(on the game, going off it: over the scene first - Wizard101 keeps showing the button the mouse last left it from
	;as hovered (Pass: white, and the next round's Pass isn't known by its picture)
	if ((mouseNowX != MouseHomeX || mouseNowY != MouseHomeY) && MouseOnGame(mouseNowX, mouseNowY) && !MouseOnGame(MouseHomeX, MouseHomeY))
		{
		MouseMove(ScreenX, GameTop + Round(GameH * 0.4), 0)
		Sleep(60)
		}
	if (mouseNowX != MouseHomeX || mouseNowY != MouseHomeY)
		MouseMove(MouseHomeX, MouseHomeY, 0)
	return 1
	}

;Whether screen point x, y is on the game's picture (GameLeft.. - its client area)
MouseOnGame(x, y)
	{
	;(v1: the game's place still blank - not found yet - compared as text, its sums blank: never on the game)
	return V1Ge(x, GameLeft) && V1Lt(x, V1Add(GameLeft, GameW)) && V1Ge(y, GameTop) && V1Lt(y, V1Add(GameTop, GameH))
	}

;---- Your mouse locked while the bot uses it ----

;While the bot has the mouse - a battle round (its first look to "Round done"), a click, a mouse turn while walking, the
;potion route's clicks, a login click - your own mouse is held off it (mouselock, on unless 0 - the Settings window's
;"Lock my mouse while the bot uses it"): its moves (BlockInput MouseMove) and, with the pointer over Wizard101 in front,
;its buttons and wheel (hook hotkeys that swallow them, on only while it's locked - not #If, which every click anywhere
;would wait on the busy bot for, and which a busy bot lets through after a second). The bot's own clicks and moves go
;through: a script's own input never sets off its hotkeys (SendLevel 0). The keyboard is never locked ({key:bot} stops
;the bot). Who has it: MouseLockOn / MouseLockOff by why (nested - each Off gives back one On). Let go at once, whoever
;has it (MouseLockRelease): the bot off, an error (OnError), the bot closing (OnExit), you playing, the round over (the
;main loop); not held while Wizard101 isn't in front (locked again if it comes back while still held), while you pick a
;boss or a plate (MouseLockPause) or record a route; the watchdog lets go once nobody's renewed it for 15 s, and of any
;one hold not renewed for 15 s - an Off that never came - whatever else holds it (MouseLockOn renews its own hold;
;MouseLockRenew - the bot's card and battle moves - every hold; MouseLockOn's ttl for longer). Whether your clicks are
;swallowed is looked at again after each of the bot's own moves (MouseLockMoved - onto the game or off it) and four times
;a second. Quick sell's moves, clicks and B (QuickSell.ahk's input block) hold it too - a run from the tray with the bot
;off as well (QsManual). mouselock:0: none of it
;Who has it ({why: how many}), when it was last renewed and how long it may go unrenewed, whether it's on now (moves held)
;and its clicks too, the span your mouse input isn't you (opened as it locks, kept through a pause: from, to - and your
;last mouse input before it), open now, the pauses, what's been said when, the first who took it, set up, locked since,
;the watchdog's timer running, each hold's own last taking and how long it may go unrenewed ({why: ms}), the last
;MouseLockRenew (every hold's renewal)
global MouseLockOwners, MouseLockAt, MouseLockTtl, MouseLocked, MouseLockClicks, MouseLockFrom, MouseLockTo, MouseLockPre
global MouseLockSpan, MouseLockHold, MouseLockSaid, MouseLockWhy, MouseLockReady, MouseLockOnAt, MouseLockTicking
global MouseLockOwnAt, MouseLockOwnTtl, MouseLockRenewAt

;(once, at the first lock: the failsafes for closing and errors)
MouseLockInit()
	{
	global MouseLockReady, MouseLockOwners, MouseLockAt, MouseLockTtl, MouseLocked, MouseLockClicks, MouseLockFrom, MouseLockTo ; (v1 globals it sets)
	global MouseLockPre, MouseLockSpan, MouseLockHold, MouseLockSaid, MouseLockWhy, MouseLockOnAt, MouseLockTicking ; (v1 globals it sets)
	global MouseLockOwnAt, MouseLockOwnTtl, MouseLockRenewAt ; (v1 globals it sets)
	if (MouseLockReady)
		return
	MouseLockReady := 1
	MouseLockOwners := V1Obj(), MouseLockAt := 0, MouseLockTtl := 15000, MouseLocked := 0, MouseLockClicks := 0
	MouseLockFrom := 0, MouseLockTo := 0, MouseLockPre := 0, MouseLockSpan := 0, MouseLockHold := 0, MouseLockSaid := V1Obj()
	MouseLockWhy := "", MouseLockOnAt := 0, MouseLockTicking := 0, MouseLockOwnAt := V1Obj(), MouseLockOwnTtl := V1Obj(), MouseLockRenewAt := 0
	OnExit(MouseLockOnExit, -1)
	OnError(MouseLockOnError, -1)
	}

;The bot takes the mouse for why ("round", "click", "turn"... - MouseLockWhat): your mouse held off it while it's held.
;Nested: each MouseLockOff(why) gives back one. ttl: how long it may go unrenewed (ms) before the watchdog lets go
MouseLockOn(why := "bot", ttl := 15000)
	{
	global MouseLockAt, MouseLockTtl, MouseLockWhy, MouseLockTicking ; (v1 globals it sets)
	MouseLockInit()
	;(its own hold's taking and ttl too - the watchdog lets go of it alone if it isn't renewed, whoever else takes the
	;mouse; counted on the same line as its times are set, so the watchdog's tick never sees it counted with old ones)
	mlHeld := MouseLockOwners.Has(why) ? MouseLockOwners[why] : 0
	mlTtl := mlHeld > 0 && MouseLockOwnTtl.Has(why) ? Max(MouseLockOwnTtl[why], ttl) : ttl
	MouseLockOwnTtl[why] := mlTtl, MouseLockOwnAt[why] := A_TickCount, MouseLockAt := A_TickCount, MouseLockTtl := Max(MouseLockTtl, ttl), MouseLockOwners[why] := mlHeld + 1
	if (MouseLockWhy = "")
		MouseLockWhy := why
	;(started once - SetTimer again would start its countdown over, and clicks a moment apart would keep it from ever
	;running)
	if (!MouseLockTicking)
		{
		MouseLockTicking := 1
		SetTimer(MouseLockTick,250)
		}
	MouseLockApply(why)
	}

;Gives back one MouseLockOn(why) - none held by why (let go already: a failsafe, the watchdog): nothing
MouseLockOff(why := "bot")
	{
	global MouseLockTtl, MouseLockWhy ; (v1 globals it sets)
	if (!IsObject(MouseLockOwners) || !MouseLockOwners.Has(why))
		return
	MouseLockOwners[why] -= 1
	if (MouseLockOwners[why] <= 0)
		MouseLockOwners.Delete(why)
	if (!MouseLockOwners.Count)
		MouseLockTtl := 15000
	MouseLockApply(why)
	;(who has it now, for the log: one still holding it, or nobody)
	if (!MouseLockOwners.Has(MouseLockWhy))
		{
		MouseLockWhy := ""
		for mlWho in MouseLockOwners
			{
			MouseLockWhy := mlWho
			break
			}
		}
	}

;Every hold let go at once (the failsafes) - because: for debug.log (only said when it was locked)
MouseLockRelease(because)
	{
	global MouseLockOwners, MouseLockTtl, MouseLockHold, MouseLockWhy ; (v1 globals it sets)
	if (!IsObject(MouseLockOwners))
		return
	MouseLockOwners := V1Obj(), MouseLockTtl := 15000, MouseLockHold := 0
	MouseLockApply("", because)
	MouseLockWhy := ""
	}

;Still at it (a long action - a battle round's card and target moves, lore farming): the watchdog's 15 s start again for
;every hold (one line: the watchdog's tick never sees half of it); and the bot's move just made: whether your clicks are
;swallowed (MouseLockMoved)
MouseLockRenew()
	{
	global MouseLockAt, MouseLockRenewAt ; (v1 globals it sets)
	if (IsObject(MouseLockOwners) && MouseLockOwners.Count)
		MouseLockAt := A_TickCount, MouseLockRenewAt := A_TickCount
	MouseLockMoved()
	}

;The bot's own move just put the pointer onto the game or off it: your clicks and wheel swallowed or let through now -
;not at the watchdog's next tick, which never comes in a Critical mouse turn. Renews nothing (a walk's clicks and turns
;don't keep a forgotten hold)
MouseLockMoved()
	{
	if (MouseLocked && MouseLockClicks != MouseLockOverGame())
		MouseLockApply()
	}

;You picking a boss or a plate (Alt+1, Alt+2, Windows+3 - pause 1): the lock let go meanwhile; pause 0: held again if
;it still is. Your click for it isn't you playing (the span stays open)
MouseLockPause(pause)
	{
	global MouseLockHold ; (v1 globals it sets)
	MouseLockInit()
	MouseLockHold := pause ? MouseLockHold + 1 : Max(0, MouseLockHold - 1)
	MouseLockApply("", pause ? "your pick (" HkText("boss") "...)" : "")
	}

;Whether your mouse is to be held off now; whyNot: why not ("free" - nobody has it)
MouseLockWanted(&whyNot)
	{
	whyNot := ""
	if (!IsObject(MouseLockOwners) || !MouseLockOwners.Count)
		whyNot := "free"
	else if (MouseLockHold > 0)
		whyNot := "your pick"
	else if (!StatOr("mouselock", 1))
		whyNot := "Lock my mouse is off (Settings)"
	else if (PotionRecording || DgRecording)
		whyNot := "a recording is on"
	;(the bot on, a potion run from the tray - BotIsOn - or a quick sell from the tray: QuickSell.ahk QsManual)
	else if (!BotIsOn() && !QsManual)
		whyNot := "the bot's off"
	else if (!GameActive())
		whyNot := "Wizard101 isn't in front"
	return whyNot = ""
	}

;The lock as it should be now - on (your moves held off; your clicks and wheel too while the pointer's over the game) or
;off - said in debug.log when it changes (a battle round's each time, the rest once a minute). why: who just took it or
;gave it back; because: why it's let go (a failsafe)
MouseLockApply(why := "", because := "")
	{
	global MouseLockPre, MouseLockFrom, MouseLockSpan, MouseLockClicks, MouseLocked, MouseLockOnAt, MouseLockTo ; (v1 globals it sets)
	;(not interrupted half done - by the watchdog's tick, F6; Critical's SetBatchLines -1 put back after - v2 has no
	;SetBatchLines: it always runs at full speed)
	mlCrit := A_IsCritical
	Critical()
	MouseLockInit()
	mlWant := MouseLockWanted(&mlNot)
	mlClicks := mlWant && MouseLockOverGame()
	if (mlWant && !MouseLocked)
		{
		;(the span your mouse input isn't you: from now - a pause's kept open; your last mouse input before it)
		if (!MouseLockSpan)
			MouseLockPre := MouseLockLastMouse(), MouseLockFrom := A_TickCount, MouseLockSpan := 1
		;(the hotkeys first: a Hotkey command after BlockInput could take the mouse hook it needs off)
		if (mlClicks)
			MouseLockKeys(1)
		MouseLockClicks := mlClicks
		MouseLockBlock(1)
		MouseLocked := 1, MouseLockOnAt := A_TickCount
		mlWho := MouseLockWhat(MouseLockWhy != "" ? MouseLockWhy : why)
		MouseLockSay("on " mlWho, "Mouse locked - " mlWho " (your keyboard stays free: " HkText("bot") " stops the bot)", mlWho = MouseLockWhat("round") ? 0 : 60000)
		}
	else if (!mlWant && MouseLocked)
		{
		MouseLockBlock(0)
		if (MouseLockClicks)
			MouseLockKeys(0)
		MouseLockClicks := 0, MouseLocked := 0
		mlHeld := Round((A_TickCount - MouseLockOnAt) / 1000, 1)
		mlBy := because != "" ? because : mlNot = "free" ? "" : mlNot
		if (mlBy != "")
			MouseLockSay("off " mlBy, "Mouse unlocked - " mlBy " (locked " mlHeld " s)", InStr(mlBy, "in front") || InStr(mlBy, "pick") ? 60000 : 0)
		else if (why = "round")
			MouseLockSay("off round", "Mouse unlocked - the round's done (locked " mlHeld " s)", 0)
		}
	else if (mlWant && mlClicks != MouseLockClicks)
		{
		;(the pointer onto the game or off it: its clicks swallowed or let through; the moves' block kept on)
		MouseLockKeys(mlClicks)
		MouseLockClicks := mlClicks
		MouseLockBlock(1)
		}
	;(the span closed once it's let go - not during a pause)
	if (!mlWant && MouseLockSpan && MouseLockHold <= 0)
		MouseLockSpan := 0, MouseLockTo := A_TickCount
	if (!mlCrit)
		Critical("Off")
	}

;Four times a second while anyone has it: Wizard101 still in front, the pointer still over it, the watchdog. Stops itself
;once nobody has it
MouseLockTick()
	{
	global MouseLockTicking ; (v1 globals it sets)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (!IsObject(MouseLockOwners) || !MouseLockOwners.Count)
		{
		SetTimer(MouseLockTick,0)
		MouseLockTicking := 0
		MouseLockApply()
		return
		}
	if (A_TickCount - MouseLockAt > MouseLockTtl)
		{
		mlList := ""
		for mlWho, mlN in MouseLockOwners
			mlList .= (mlList = "" ? "" : ", ") MouseLockWhat(mlWho) (mlN > 1 ? " x" mlN : "")
		MouseLockRelease("nobody renewed it for " Round((A_TickCount - MouseLockAt) / 1000) " s (the watchdog - held by " mlList ")")
		return
		}
	;(a hold not renewed for its own ttl - its Off never came: that one let go, however often the others take the mouse)
	mlStale := [], mlList := ""
	for mlWho, mlN in MouseLockOwners
		{
		mlOwn := Max(MouseLockOwnAt.Has(mlWho) ? MouseLockOwnAt[mlWho] : MouseLockAt, MouseLockRenewAt ? MouseLockRenewAt : 0)
		if (A_TickCount - mlOwn > (MouseLockOwnTtl.Has(mlWho) ? MouseLockOwnTtl[mlWho] : 15000))
			mlStale.Push(mlWho), mlList .= (mlList = "" ? "" : ", ") MouseLockWhat(mlWho) (mlN > 1 ? " x" mlN : "") " (" Round((A_TickCount - mlOwn) / 1000) " s)"
		}
	if (mlStale.Length)
		{
		mlMsg := "the watchdog let go of " mlList ": not renewed, never given back"
		if (mlStale.Length = MouseLockOwners.Count)
			{
			MouseLockRelease(mlMsg)
			return
			}
		DebugLog("Mouse lock: " mlMsg " - the others still hold it")
		for mlI, mlWho in mlStale
			MouseLockOwners[mlWho] := 1, MouseLockOff(mlWho)
		}
	MouseLockApply()
	}

;Your mouse's moves held off (on) or let through again - the bot's own moves aren't held (BlockInput MouseMove)
MouseLockBlock(on)
	{
	if (on)
		BlockInput("MouseMove")
	else
		BlockInput("MouseMoveOff")
	}

;Your mouse's buttons and wheel swallowed while Wizard101 is in front (on) - hook hotkeys (the hook decides, not the busy
;script) made the first time - or let through again. (A wheel spun hard is many hotkeys a second: the "hotkeys received"
;warning box only past 1000 in 2 s)
;(v1: #MaxHotkeysPerInterval 1000, a directive - in force from the start. v2's A_MaxHotkeysPerInterval := 1000 here, after
;the auto-execute section, would never run: set in MouseLockKeys, before any of its hotkeys is made; v1's from-the-start
;is the entry script's to set, at its start)
MouseLockKeys(on)
	{
	static made := 0, failSaid := 0
	A_MaxHotkeysPerInterval := 1000
	if (!on && !made)
		return
	HotIfWinActive("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe")
	for mlI, mlKey in MouseLockKeyList()
		{
		if (on)
			{
			;(v1: Hotkey, ..., On UseErrorLevel - HkTry, Hotkeys.ahk: ErrorLevel v1's number, no throw)
			HkTry(mlKey, MouseLockSwallow, "On")
			;(one the Hotkey command won't make: said once a run - that button isn't swallowed, the rest are)
			if (ErrorLevel && !failSaid)
				failSaid := 1, DebugLog("Mouse lock: " mlKey " couldn't be made a hotkey (ErrorLevel " ErrorLevel ") - that button isn't held off")
			}
		else
			HkTry(mlKey, "Off")
		}
	HotIfWinActive()
	made := 1
	}

;The bot's right button pressed as a raw mouse_event (MouseSteer.ahk MouseSteerButton - its own press didn't reach the
;game): the lock's right-button hotkey off while it's down (free 1 - it would take that press for yours and swallow it),
;on again once it's up (0). Only while the lock swallows clicks; the rest of the lock - your moves held, the other
;buttons and the wheel swallowed, the watchdog, the keyboard free (F6) - as it was
MouseLockRightFree(free)
	{
	if (!MouseLockClicks)
		return
	HotIfWinActive("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe")
	if (free)
		HkTry("*RButton", "Off")
	else
		HkTry("*RButton", MouseLockSwallow, "On")
	HotIfWinActive()
	}

MouseLockKeyList()
	{
	return ["*LButton", "*RButton", "*MButton", "*XButton1", "*XButton2", "*WheelUp", "*WheelDown", "*WheelLeft", "*WheelRight"]
	}

;Was that hotkey (A_ThisHotkey...) one of the lock's - a click or wheel turn of yours it swallowed?
MouseLockIsKey(hk)
	{
	return RegExMatch(hk, "i)^~?\*(LButton|RButton|MButton|XButton1|XButton2|WheelUp|WheelDown|WheelLeft|WheelRight)$")
	}

;(a click or wheel turn of yours while it's locked: nothing done - swallowed. *: v2 passes the hotkey's name)
MouseLockSwallow(*)
	{
	}

;The pointer over the game's picture (where the lock swallows your clicks - elsewhere, the tray, the dashboard and your
;other windows get them)
MouseLockOverGame()
	{
	MouseGetPos(&mlX, &mlY)
	return MouseOnGame(mlX, mlY)
	}

;When your last mouse input was (A_TickCount) that counts as you: what came while it was locked doesn't - the time
;before it does. (Nothing since the last lock let go: the time before that lock - MouseLockPre, taken as it locked,
;already leaves out what an earlier lock swallowed; a move swallowed in one mouse turn isn't you once the next one locks)
MouseLockLastMouse()
	{
	mlLast := A_TickCount - A_TimeIdleMouse
	if (MouseLockFrom && (MouseLockSpan || mlLast <= MouseLockTo + 100))
		return MouseLockPre
	return mlLast
	}

;How long you've left the keyboard and mouse alone (ms - Walker.ahk UserIdle; the bot's own input never counts): what
;the lock swallowed (your mouse moved, clicked or turned while it was locked) isn't you; your keys always are. Never
;locked this run: A_TimeIdlePhysical, as ever
MouseLockIdle()
	{
	if (!MouseLockFrom)
		return A_TimeIdlePhysical
	return A_TickCount - Max(A_TickCount - A_TimeIdleKeyboard, MouseLockLastMouse())
	}

;Who has it, in words (debug.log)
MouseLockWhat(why)
	{
	mlNames := V1Obj({round: "a battle round", click: "a click", turn: "a mouse turn while walking", route: "the potion route's click"
		, login: "a login click", walker: "a walker click", stats: "a click in the spellbook", lore: "lore farming"
		, dev: "dev mode's loop", quicksell: "quick selling the backpack"})
	return mlNames.Has(why) ? mlNames[why] : why
	}

;A line in debug.log - each kind at most once in every ms (0: each time)
MouseLockSay(kind, msg, every := 0)
	{
	if (every && MouseLockSaid.Has(kind) && A_TickCount - MouseLockSaid[kind] < every)
		return
	MouseLockSaid[kind] := A_TickCount
	DebugLog(msg (every ? " (said once a minute)" : ""))
	}

;The bot closing (OnExit): your mouse let go first
MouseLockOnExit(reason, code)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (MouseLocked)
		MouseLockRelease("the bot is closing")
	BlockInput("MouseMoveOff")
	BlockInput("Off")
	}

;An error the script didn't expect (OnError): your mouse let go before its box shows (and the bot's thread stops).
;(*: v2 passes the error's Mode too)
MouseLockOnError(e, *)
	{
	global MouseLockOwners, MouseLockHold, MouseLockClicks ; (v1 globals it sets)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (MouseLocked)
		MouseLockRelease("an error in the script (" (IsObject(e) ? e.Message " at line " e.Line : e) ")")
	else if (IsObject(MouseLockOwners))
		MouseLockOwners := V1Obj(), MouseLockHold := 0
	BlockInput("MouseMoveOff")
	BlockInput("Off")
	if (MouseLockClicks)
		MouseLockKeys(0), MouseLockClicks := 0
	return 0
	}

;---- How it plays its cards ----

;Hit first this round, before any boost? (cardlogic: 2 = hit first, 3 = hit first unless a boss is picked)
CardHitFirst()
	{
	cardWay := Stat("cardlogic")
	return (cardWay = 2 || (cardWay = 3 && BossChoosen != 1))
	}

;May a boost card go this round? Not once boostmax of them have gone since the last hit while a hit can be
;cast (boostmax 0: no limit; nothing to hit with: boosting is all it can do)
CardBoostOk()
	{
	cardMax := Stat("boostmax")
	if (cardMax <= 0 || V1Lt(BoostRun, cardMax) || !CardHitReady()) ; (v1: BoostRun blank till the first look out of battle - a bot started in a battle - compared as text: "" < 2 true)
		return true
	DebugLog("  " BoostRun " boost" (BoostRun = 1 ? "" : "s") " since the last hit (boostmax " cardMax "): hitting now")
	return false
	}

;A hit in hand (hit4 only on a picked boss) you can pay for and aren't saving pips against (not the wand's)
CardHitReady()
	{
	return (hit4 == 1 && BossChoosen = 1 && CardHitCanGo("hit4")) || (hit3 == 1 && CardHitCanGo("hit3"))
		|| (hit2 == 1 && CardHitCanGo("hit2")) || (hit1 == 1 && CardHitCanGo("hit1"))
		;(a learned hit in no slot: cast when none of these can go - CastLearnedHit)
		|| (PipsNow >= 0 && PipSaveFor = "" && LearnHitReady())
	}

;(pips unknown - your nameplate not found - isn't "can pay": boosting isn't held back for a hit that may not go)
CardHitCanGo(name)
	{
	return PipsNow >= 0 && Affordable(name) && (PipSaveFor = "" || PipSaveFor = name)
	}

;The biggest hit in hand it can cast (hit4 only on a picked boss) - not the wand's - else a learned hit in no slot
;(CastLearnedHit). True if one was cast. With the game's hand read this look, the planned hit first (KillCalc.ahk
;BoostPick - the one dealing the most with the boosts in hand and on, the user 2026-10-24), then the others as ever
CastBestHit()
	{
	global
	;(_title: the temporary a literal goes to UseHit's ByRef in - v1's was no variable at all, not a global)
	local cbhP, _title
	cbhP := PlanHit
	if (BoostMemOk && RegExMatch(cbhP, "^hit[1-4]$") && (cbhP != "hit4" || BossChoosen = 1))
		;(&%cbhP%: v1 passed the slot's own variable - hit1..hit4 - to UseHit's ByRef, not a copy)
		if (%cbhP% == 1 && UseHit(&cbhP, &%cbhP%, &hitschool))
			{
			BoostRun := 0
			return true
			}
	if ((hit4 == 1) && (BossChoosen = 1) && UseHit(&_title := "hit4", &hit4, &hitschool))
		|| ((hit3 == 1) && UseHit(&_title := "hit3", &hit3, &hitschool))
		|| ((hit2 == 1) && UseHit(&_title := "hit2", &hit2, &hitschool))
		|| ((hit1 == 1) && UseHit(&_title := "hit1", &hit1, &hitschool))
		|| CastLearnedHit()
		{
		BoostRun := 0
		return true
		}
	return false
	}

;Cards of a kind switched off in the Settings window (useblades, usetraps...) are never played: with
;discardunused on they're discarded like the others it never plays - at most discardmax a round, and not while
;you play. Returns how many were
DiscardSwitchedOff()
	{
	global
	local did := 0, dsoK
	;(V1Ge: DiscardOffCount is blank till the first round's start sets it - v1 compared that as text: not >= )
	if (Stat("discardunused") != 1 || V1Ge(DiscardOffCount, Stat("discardmax")) || PlayerActing())
		return 0
	;(each school's blades and traps found, the group's - KillCalc.ahk BoostSearch: SbFound, GbFound)
	if (!Stat("useblades"))
		{
		for dsoK in SbFound
			if (BoostKind(dsoK) = "blade")
				did += DiscardOffOne("blade", SubStr(dsoK, 1, InStr(dsoK, "/") - 1))
		for dsoK in GbFound
			if (BoostKind(dsoK) = "blade")
				did += DiscardOffOne(dsoK, "resources")
		if (blade3 == 1)
			did += DiscardOffOne("blade3", "resources")
		if (blade4 == 1)
			did += DiscardOffOne("blade4", "resources")
		if (sharpen == 1)
			did += DiscardOffOne("sharpen", "resources")
		}
	if (!Stat("usetraps"))
		{
		for dsoK in SbFound
			if (BoostKind(dsoK) = "trap")
				did += DiscardOffOne("trap", SubStr(dsoK, 1, InStr(dsoK, "/") - 1))
		for dsoK in GbFound
			if (BoostKind(dsoK) = "trap")
				did += DiscardOffOne(dsoK, "resources")
		if (trap3 == 1)
			did += DiscardOffOne("trap3", "resources")
		if (feint == 1)
			did += DiscardOffOne("feint", "resources")
		if (potent == 1)
			did += DiscardOffOne("potent", "resources")
		}
	if (!Stat("usebubble") && bubble == 1)
		did += DiscardOffOne("bubble", hitschool)
	if (!Stat("useaura") && aura == 1)
		did += DiscardOffOne("aura", hitschool)
	if (!Stat("usetower") && tower == 1)
		did += DiscardOffOne("tower", "resources")
	if (!Stat("usereshuffle") && reshuffle == 1)
		did += DiscardOffOne("reshuffle", "resources")
	if (did)
		DebugLog("  (discarded " did " card" (did = 1 ? "" : "s") " of kinds switched off in the Settings window)")
	return did
	}

;One card of a kind switched off discarded, while the round's discardmax allows (DiscardOffCount)
DiscardOffOne(title, dir)
	{
	global DiscardOffCount ; (v1 globals it sets)
	if (V1Ge(DiscardOffCount, Stat("discardmax")))
		return 0
	n := DiscardCard(title, dir)
	;(v1's DiscardOffCount += n on a line of its own: a blank counted as 0)
	DiscardOffCount := V1N(DiscardOffCount) + V1N(n)
	return n
	}

CfgSave:
CfgSave()
	return

CfgDefaults:
CfgDefaults()
	return

CfgOpenFile:
CfgOpenFile()
	return

;Simple / all settings (dashboard.ini [view] settings): the window made again in the other view, where it was - changes
;not saved yet kept (CfgPending), still to be saved
CfgViewToggle:
CfgViewToggle()
	return

CfgGuiClose:
CfgGuiClose()
return
CfgGuiEscape:
CfgGuiEscape()
	return

;###############  V1toV2 FUNCS  ###############
CfgSave(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(not halfway through while the bot writes PlayerStats.txt itself: StatsSet is Critical too)
	Critical()
	CfgSaveNow()
	return
}
;##############################################
CfgDefaults(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	CfgFillDefaults()
	return
}
;##############################################
CfgOpenFile(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	Run("notepad.exe `"" A_WorkingDir "\PlayerStats.txt`"")
	return
}
;##############################################
CfgViewToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - V1Do's IniWrite, CfgShow set it)
	CfgPending := V1Obj()
	for CfgVKey, CfgVC in CfgCtls
		{
		;(v1: GuiControlGet by the control's hwnd)
		CfgVVal := GuiCtrlFromHwnd(CfgVC).Value
		if (CfgVVal != CfgShownVals[CfgVKey])
			CfgPending[CfgVKey] := CfgVVal
		}
	;(to the simple view with changes to settings it doesn't show: saved or undone first - they'd be lost)
	CfgVHid := 0
	if (!CfgSimple)
		for CfgVKey in CfgPending
			CfgVHid += CfgSimpleKeys().HasKey(CfgVKey) ? 0 : 1
	if (CfgVHid)
		{
		Cfg["CfgNote"].Value := "Save first - " CfgVHid " change(s) to settings the simple view doesn't show"
		CfgPending := ""
		return
		}
	CfgVCount := CfgPending.Count
	;(v1: WinGetPos of a window not found gave blanks - CfgShow then took no place from them; v2 throws, and unsets
	;the output variables first - the blanks are set in the catch)
	try WinGetPos(&CfgReopenX, &CfgReopenY, , , "ahk_id " CfgHwnd)
	catch
		CfgReopenX := "", CfgReopenY := ""
	V1Do(IniWrite, CfgSimple ? 0 : 1, A_ScriptDir "\dashboard.ini", "view", "settings")
	Try Cfg.Destroy()
	CfgHwnd := 0
	CfgShow()
	if (CfgVCount)
		Cfg["CfgNote"].Value := CfgVCount " change(s) not saved yet - Save to use them"
	return
}
;##############################################
CfgGuiClose(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
global
CfgGuiEscape()
}
;##############################################
CfgGuiEscape(*) { ; V1toV2: Lbl->Func
	global
	Try Cfg.Destroy()
	CfgHwnd := 0
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
SettingsBlank()
	{
	global CfgHwnd := "", CfgHelpText := "", CfgNote := "", CfgCtls := "", CfgShownVals := "", CfgHelps := "", CfgHelpShown := "", CfgSimple := ""
	global CfgPending := "", CfgReopenX := "", CfgReopenY := "", MouseHomeX := "", MouseHomeY := "", MouseHomeSet := "", MouseHomeAt := ""
	global DiscardOffCount := "", MouseLockOwners := "", MouseLockAt := "", MouseLockTtl := "", MouseLocked := "", MouseLockClicks := ""
	global MouseLockFrom := "", MouseLockTo := "", MouseLockPre := "", MouseLockSpan := "", MouseLockHold := "", MouseLockSaid := ""
	global MouseLockWhy := "", MouseLockReady := "", MouseLockOnAt := "", MouseLockTicking := "", MouseLockOwnAt := "", MouseLockOwnTtl := ""
	global MouseLockRenewAt := "", PlanHit := "", BoostMemOk := "", BossChoosen := "", hit4 := "", hit3 := "", hit2 := "", hit1 := "", SbFound := ""
	global GbFound := "", blade3 := "", blade4 := "", sharpen := "", trap3 := "", feint := "", potent := "", bubble := "", hitschool := "", aura := ""
	global tower := "", reshuffle := ""
	}
