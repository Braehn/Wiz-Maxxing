AutoQuester
===========
NOTE: AutoFarmer\Autofarmer.ahk now does battles AND this walking in one script,
and starts by itself. Use this one only if you want walking without battles,
and never run both at once. The walking itself lives in Walker.ahk (settings at
its top), shared by both scripts.

Walks your wizard towards the current quest goal by following the yellow quest
arrow at the bottom of the Wizard101 window (the one with the distance printed
on it).

Keys
	F8        start / stop walking (also in the tray menu)
	Shift+F8  quit AutoQuester

How to use
	1. Close the OLD AutoQuester if it's still running (right-click its green
	   "H" in the tray > Exit). The old one grabbed Windows+1 and Esc.
	2. Double-click AutoQuester.ahk.
	3. Click into Wizard101 and press F8. Hover the green "H" in the tray to
	   see what it's doing.

What it does
	- Reads which way the arrow points and how far the goal is, about 5-10
	  times a second.
	- Arrow far off to the side: stops and turns on the spot (A / D).
	  Roughly ahead: walks forward (W), steering a little as it goes.
	- After every turn it waits half a second before steering on the arrow
	  again: the camera swings round after the wizard that much later, so
	  until then the arrow still shows part of the turn (steering on that made
	  it over-turn, zig-zag and walk in circles).
	- At the goal (the distance reads 15 or less twice in a row, or the
	  number stops being readable right after it read 30 or less - a lone
	  digit like "9" often won't read):
	    1. it stops and presses X to talk to whoever is there,
	    2. if a dialogue opens (it covers the arrow) it presses Space to
	       skip through it (a long one: it keeps going, more slowly), and as
	       soon as the arrow shows the next goal it walks on - even a close
	       one: the wizard stands still while talking, so any change in the
	       distance means a new goal,
	    3. if nothing opens (the arrow is still there after X and two Space
	       presses) there's nobody to talk to - it's a doorway or loading
	       point - so it walks on into it: it follows the arrow until it's
	       about 6 away, turns to face it if it's off to the side, then stops
	       steering and walks straight through, for up to 3 seconds (8
	       seconds for the whole push). If the door frame hides the arrow it
	       keeps walking straight on for 2 more seconds. A loading screen
	       ends it, and so does the arrow jumping to a new goal,
	    4. otherwise it waits until a new goal shows up (the distance
	       changing while it stands there). It tries a push at most twice
	       at the same spot, so it can't go back and forth.
	  In AutoFarmer it never presses X or Space while a battle is on.
	- World Gate (the quest is in another world, so the arrow leads to the
	  World Gate): once the gate's "World Gate - Press X to Interact" prompt
	  shows up with the arrow last 60 or less away, it stops, presses X, and
	  on the Spiral Map clicks Go To World (the map opens with the quest's
	  world picked). Then it waits out the loading screen and walks on in the
	  new world. Walking past a World Gate on the way somewhere else doesn't
	  count (the arrow is further off then). If the map doesn't open it
	  presses X once more, then walks on; if Go To World doesn't take after 3
	  clicks it stops (the tray tip says so) - pick the world yourself.
	  In AutoFarmer the Spiral Map is also found from the game's memory
	  (read-only): when X at a prompt read as an ordinary one opens it, or
	  the map is open with no arrow showing (left open, or the bot started
	  with it up), it clicks Go To World the same way - before, it pressed
	  Space at the map and then waited for an arrow that never came.
	- Sigil (a dungeon entrance: "Press X to Enter", with Team Up): once its
	  prompt shows up with the arrow last 60 or less away (or on arriving at
	  the goal with the prompt showing, or standing on the sigil with its
	  prompt covering the arrow for 2 seconds and no far-off goal shown in
	  the last 10 seconds), it stops, presses X, and stands still
	  for 30 seconds (SigilWait at the top of Walker.ahk) while the sigil
	  counts down and the dungeon loads, then walks on like after any loading
	  screen. A battle during the wait ends the wait. Walking past a sigil on
	  the way somewhere else doesn't count.
	- Boats and the like (a prompt titled e.g. "BOAT TO GOBBLERTON", "Press X
	  or click to Use") covering the arrow: the game's log says which zone the
	  quest's goal is in (e.g. Karamelle/Interiors/KM_Z10_UnderwaterGrotto -
	  KM_Z10 is Gobblerton). If the boat goes to that zone and you're not
	  there already, it presses X and stands still 15 seconds while it moves
	  you (TransportWait). Otherwise it steps out of the prompt so the arrow
	  shows again and walks on. If it can't tell where a boat goes (a zone
	  it has never been in), it uses it the second time it ends up there
	  without having got any closer. The same boat isn't used twice within 10
	  minutes. Zone names it has seen are kept in resources\known_zones.txt.
	- An NPC wearing a quest marker - a gold "?" in a red swirl over its head,
	  its name in green under it: another goal of this quest, or another
	  quest's: when its "Press X" prompt shows on the way, X is pressed (with
	  AutoFarmer's vision helper: the marker found by its colours, the green
	  name read and matched to the prompt's). A "!" (a new quest offered)
	  isn't followed, nor an NPC whose marker is off the screen (behind the
	  camera).
	- No arrow on screen (a battle, a loading screen, a dialogue box): it lets
	  go of the keys and waits. AutoFarmer can handle the battle meanwhile;
	  AutoQuester carries on when the arrow comes back. Still no arrow 4
	  seconds after a loading screen: it presses Space every 1.5 seconds
	  (40 times at most) in case the new area opened a dialogue by itself.
	- The arrow is drawn at the wizard's feet, so it gets darker in shadow
	  and can be pushed up the screen (e.g. by a talk prompt). The reader
	  handles both: a second colour test for dark arrows (and a third for an
	  arrow under the water when wading deep - a dark olive), and if the arrow
	  isn't in its usual spot it looks for it higher up.
	- Can't read the distance for 3 seconds: it stops and waits rather than
	  walking blind. If no number at all has read since the arrow came back
	  (after a battle, say), the goal must be under 10 away (lone digits
	  don't read), so it counts that as arriving.
	- Stuck: if it hasn't got any closer for 4 seconds while walking - or for
	  1.2 seconds when the picture has stopped moving too (with W held the
	  scenery should slide past; walking into a wall it stands still) - it
	  backs up, turns 75 degrees and walks along the obstacle, alternating
	  sides and going a bit further each time. Afterwards it keeps aiming off
	  to that side for 3 seconds, easing back towards the goal, so it doesn't
	  walk straight back into the same corner. After 5 tries it gives up and
	  stops (the tray tip says so); move the wizard a little and press F8 again.
	- It remembers obstacles: when a way round works (it gets clearly closer
	  afterwards) it notes the zone (from the game's log), the distance to the
	  goal where it got stuck and which side worked, in
	  resources\walk_memory.txt. Next time it gets stuck there it tries that
	  way first, and once that way has worked twice it keeps to that side as it
	  heads for a goal at about that distance, before it even gets there. A way that stops working is
	  forgotten. Delete the file (or a line of it) to make it forget.
	- Arrow hidden while walking (a pillar, arch or door frame between the
	  camera and the wizard, or the wizard's own mount when the arrow points
	  back towards the camera): it keeps walking for 1.5 seconds (usually
	  that's it through the arch), then backs up a little, then turns 70
	  degrees at a time - a full circle at most - until it shows again. Also
	  when it hasn't shown at all since walking was switched on.
	- AutoFarmer doesn't walk while its afk, mob-loop or lore modes are on.
	- "Collect / defeat N things" goals (the line under the arrow has a count
	  like "(2 of 5)" or says Collect / Defeat / Gather / Recover...): the arrow
	  only leads to the area, so once there (or stuck near it) it doesn't talk
	  or wait - it collects. Monster name labels on screen (the crimson ones,
	  e.g. FROST FIN / RANK 15 ELITE): it walks into the biggest (nearest) one
	  so a battle starts (AutoFarmer fights it), at most 12 s per monster.
	  None: it roams about the spot in a widening square (walking over things
	  picks them up, "Press X" prompts get X), heading back when it's 70 away.
	  After each battle it carries straight on. It stops when the goal line
	  changes (done, or the next goal) and follows the arrow again. When the
	  count ("2 of 5") hasn't gone up for 3 minutes (battles don't count) it's
	  an odd one: it stops, waits there (battles still get fought) and shows a
	  notice - Keep trying (3 more minutes) / Stop walking / OK. It closes by
	  itself once the quest moves on. debug.log: "collect: ...".
	- Right at the goal and the arrow vanishes (it isn't drawn on top of the
	  goal), or stuck within 20 of it (the thing itself in the way): that's
	  arrived - it presses X instead of backing up, turning or going round.
	  X opened nothing: it waits 2.5 s (no Space jumping), then steps back
	  once so the arrow shows again.
	  Stuck by something that isn't the goal (X opened nothing): it goes
	  round it as before.
	- Badly stuck - it gave up going round an obstacle after 5 tries, or
	  has walked 3 minutes (battles, talks, collecting left out) without
	  getting any closer to the goal: it teleports to the world's Commons
	  (End) and walks on from there - at most once every 10 minutes. Stuck
	  again sooner, or the teleport can't happen (a dungeon), or badly stuck
	  where it was before (same zone, the goal as far, the same quest line -
	  the Commons only brings it back there, a door it can't open, say): it
	  stops and shows the Stuck notice. ResetTeleport := 0 at the top of Walker.ahk
	  switches the teleport off.
	- Notices (a small window that doesn't take the focus from the game, a
	  sound and a tray tip; on another monitor if there is one, else beside
	  or at the top of the game; hidden during battles): stuck for good
	  (walking off); the collect goal above; no quest arrow for 45 s out of
	  battle - AutoFarmer only, which can tell a battle (first, if an X of
	  the bot's may have opened a window Space doesn't close, like a shop,
	  it presses Escape once - and Escape again if that opened the game's
	  menu); waiting at a goal for 3 minutes. One at a time, the most
	  important. Each closes by itself once it's sorted; OK or its X puts it
	  away. F8 off and on gives a collect goal another go. debug.log: "NEEDS
	  YOU - ...".
	- X at a "Press X to Enter" prompt that opens a dialogue (Back / Done /
	  More) instead of a dungeon: it presses Space through it and walks on.
	  The same prompt gets X once per 10 minutes even if OCR reads its text a
	  little differently each time.
	- Next to an NPC the "press X to talk" prompt pushes the arrow up the
	  screen and it jumps about as the prompt slides. While that's going on
	  it only acts on readings that agree and walks straight (no small
	  steering) until it's clear of the NPC.
	- In AutoFarmer every step worth knowing (talking, pushing on, World Gate,
	  stuck tries, the arrow being pushed up or hidden) goes into
	  AutoFarmer\debug.log.
	- It only presses keys while Wizard101 is the active window. Click away
	  and it pauses and lets go of every key; F8 stops it straight away.

Walking by the game's memory (AutoFarmer only, read-only)
	AutoFarmer's vision helper also reads, straight out of the game's
	memory, where the wizard is, which way it faces and where the quest
	arrow points (the game's own path to the goal, how far along it, and how
	many zone changes are left). It only ever READS the game's memory:
	nothing in the game is written or changed, nothing is injected, and it
	sends no keys or clicks of its own. The walker uses it for the same
	decisions it makes off the arrow, with better inputs:
	  - steering: the heading from the wizard's facing to where the arrow
	    points - once it's been checked: it agrees with the arrow on screen
	    (3 clear readings; if it's the arrow's mirror image its sign is
	    turned round and checked again), or, with no arrow to check it by,
	    a turn goes the way it says (any turn, timed or not, checks it).
	    Once checked it's kept (checked:1 in resources\nav_calibration.txt)
	    and used from the start next time, and an arrow that reads as its
	    mirror image doesn't turn it round any more (the arrow is misread
	    there - the dais in the Headmistress's office did that); turns go on
	    checking it.
	    debug.log: "the game's memory: its heading agrees with the arrow's"
	    / "holding d turned the wizard ... the way its heading said".
	  - distance: the memory's instead of the OCR'd number (which misses
	    lone digits like "9"). How the two compare differs from zone to zone
	    (about 41 game units per arrow unit in one, about 100 in Pigswick
	    Academy), so it's worked out in each zone from a few readings and
	    kept in resources\nav_calibration.txt (delete it to make it learn
	    again); a zone not worked out yet uses its world's other zones
	    (it seems to go by world), else all of them.
	  - no arrow on screen (scenery hides it, or a see-through arrow on a
	    floor its own colour - the gold carpet in Pigswick Academy - can't be
	    picked out): the memory stands in for the arrow, so it walks to the
	    goal, presses X there and carries on as usual, instead of backing up
	    and turning, or waiting with a "No quest arrow" notice. Dialogues and
	    prompts are still looked for meanwhile; not in a battle or at a
	    loading screen. debug.log: "no arrow on screen - the game's memory
	    stands in for it".
	  - the route round walls: the helper plans the way to the goal over
	    the zone's own map (its floor, walls and obstacles, from the zone's
	    file - the same map as the dashboard's Map window, where the plan is
	    drawn in green and the floor is shaded by height: brighter is
	    higher), following the game's own quest path but keeping
	    clear of walls, corners, ledges and the storeys above and below. The
	    wizard steers at a point a little way ahead on it, so it goes round
	    walls instead of walking into them; going round one isn't taken for
	    being stuck. Things that aren't in the zone's file - NPCs, other
	    players - are still met by the usual "stuck: back up and go round".
	    debug.log: "the route round walls (the zone's map): steering along
	    it" / "no route round walls (...) - steering at where the arrow
	    points" (it does that whenever there's no plan). NavRoute := 0 at the
	    top of Walker.ahk switches it off.
	  - teleports on the way: a zone's paths can jump from one spot to
	    another far off (a trolley, a hole down to the sewers, a portal), and
	    the game's quest path takes them - even one this character can't use
	    yet, or one the wrong way (most only go one way: a way out of the
	    sewers isn't a way in - the game's quest helper doesn't mind). The
	    route stops at a teleport (never past it, into the walls); the wizard
	    walks on into it for a second (X at its prompt, if it asks) and waits
	    there - no turning back and forth over it. One taken the wrong way is
	    gone round at once by the zone's own paths; one that hasn't taken the
	    wizard in 15 s is given up for 30 minutes and gone round - another
	    teleport, or a way walked. With none left, walking stops with a
	    "Stuck at a teleport" notice (F8 walks again, and gives the teleports
	    another go: you may have done what opens one). debug.log: "teleport on
	    the game's path at ...", "route: the game's path takes the teleport
	    at ... the wrong way", "... hasn't taken the wizard in 15 s".
	  - turns: it holds A / D until the wizard's facing has really turned
	    that far (within about 5 degrees), instead of guessing from the time.
	  - a goal in another zone: the arrow leads to the way out (a door, a
	    loading point), so it walks straight into it instead of pressing X
	    (unless a prompt asks for X).
	Talking, pushing into doorways, World Gates, sigils, prompts, collect
	goals and notices work as before.
	It falls back to the arrow on screen at once whenever the memory can't
	be used - the helper not running, an error or no answer, the game's
	quest helper off, a zone that isn't the one in the game's log - and
	comes back by itself; debug.log says so once each way ("the game's
	memory ... - following the on-screen arrow" / "... can be used").
	navmem:0 in AutoFarmer\PlayerStats.txt switches it off. AutoQuester.ahk
	on its own has no vision helper, so it always follows the arrow.
	Mobs (AutoFarmer, mobavoid:1): the route goes round the zone's mobs -
	read from the game's memory - out of what each sees (mobshape: a
	semi-circle in front, a circle or a cone; mobradius far), except the ones the quest is about (named
	in its goal line, or at its goal) and while collecting. With no way
	round it stands still till the mob moves off ("waiting - a mob on the
	way"), 25 s at most.

Settings are at the top of Walker.ahk (arrival distance, turn speed,
how long before it counts as stuck, how many Space presses at the goal,
how long it walks on into a doorway, how far it backs up and turns when
stuck, how close the arrow must be for a World Gate to count, for
collecting: how long before it starts, how far it roams, how long it chases
one monster, when it gives up, and for the game's memory: how many readings
must agree with the arrow, how close a turn must get).

Window size and UI size
	The arrow was captured at a 1920x1080 window with UI Size: Small. A
	different window size, Windows display scaling or UI Size draws it bigger
	or smaller (1920x1200 at 125% scaling: about 1.21 times). The reader
	works out the size from the arrow itself on the first readings (0.7 to
	1.8 times), so there's nothing to set. It's slowest for the first
	second or so, while it finds the size.

Files
	AutoQuester.ahk           walking only (F8 / Shift+F8)
	Walker.ahk                the walking itself, shared with AutoFarmer
	ArrowReader.ahk           reads the arrow's direction and distance off
	                          the screen (uses ..\AutoFarmer\Ocr.ahk)
	resources\arrow_refs.txt  the 16 captured arrow shapes (bright yellow)
	resources\arrow_refs_hue.txt  the same shapes for the shadow colour test
	resources\nav_calibration.txt  what it learned about the game's memory
	                          (made by itself; delete it to learn again)
	resources\testframes\     captured arrows for testing ArrowReader
	backups\                  the old 2018 AutoQuester, and copies from before
	                          each round of changes
