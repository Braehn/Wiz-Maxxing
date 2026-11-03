Made By JoshuasBrainCells

One script for battles and walking:
Autofarmer.ahk now does both and starts by itself when you double-click it:
it fights whenever a battle round is up (the Pass button shows) and otherwise
walks your wizard towards the quest goal by following the yellow quest arrow
(the walking comes from ..\AutoQuester\Walker.ahk). Keys:
	F6           the bot on / off (off: no battles, walking, potions or
	             reconnecting - it waits; while it's off, F6 and F8 only work
	             in Wizard101, and the Alt+ keys aren't taken at all)
	F8           walking on / off
	Windows+1    restart (Alt+Esc too)
	Windows+Esc  quit
These are the keys out of the box - change any of them on the dashboard's Keys
tab (below); the messages then name your keys.
It only presses movement keys while Wizard101 is the active window. Don't run
AutoQuester.ahk at the same time.

New in v1.0.0 and not tried in the game yet: LIVE_CHECKS.txt
(next to this file) says what to try, in what order, and what to send back.

Discord alerts (tray menu "Discord alerts..."): when the wizard needs you, a
message goes to your Discord channel - stuck (walking stopped), a teleport that
doesn't work, no quest arrow, waiting at the quest goal, a collect quest that
needs you, out of potions with none to be had, "Crowns" seen in a potion run
or a quick sell, out of mana, a wizard it doesn't know, the backpack full and
not quick sold, the gold bag nearly full, or it can't get back
into the game (a login turned down, patching, the launcher). It says what's
wrong, the zone and the time - never a login or a screenshot. Set it up: in
Discord the channel's settings > Integrations > Webhooks > New Webhook > Copy
Webhook URL, then paste it into "Discord alerts..." (typed hidden; kept in
Windows Credential Manager as "Wiz-Maxxing Discord webhook", never in a file
or debug.log) - a test message is sent. Empty: another test; OFF: removed.
The same alert at most once in 10 minutes; alertson:0 (the Settings window)
switches them off. debug.log: "Discord: ...".

The log on OneDrive (Settings: "Copy the log to OneDrive", logmirror:1): debug.log
is also written to your OneDrive folder, Wiz-Maxxing logs\<this PC's name>\,
with a picture of the game every 2 minutes and at each alert (snap_*.jpg, the
newest 15) - OneDrive syncs it, so the bot on one PC can be followed from
another. Off by default; nothing else is sent anywhere.

Dungeon farming (the dashboard's Dungeons tab): record a run once - stand
outside the dungeon by its sigil, click "Record a run" and play it (X at the
sigil, to the boss, fighting on the way, back out to where you started), then
press F9 and name it. Pick it and click Run (so many times, or 0 = until you
stop it): the bot walks the same way by the zone's map, presses X where you
did, fights every battle (the bot on, F6), Spaces through dialogues and starts
over. F8 pauses it. A defeat or a potion run that leaves the wizard in an
earlier zone of the run: on from the nearest step of its first visit there,
never on to the way back out (3 times a run at most). Somewhere the run doesn't go, or stuck for good: it stops and says why
(the tab, debug.log "Dungeons: ...", Discord) - counted badly stuck on the
dashboard. An X at a sigil that didn't load twice: home and back first, once a
run, if you switch sigilhome on (see "A sigil that won't start").
Runs are kept in dungeons\<name>.txt (updates keep them). Needs the
vision helper and the game's memory, like walking by the map.
Between runs (a run that ends back where it starts, till its first X): with
quick sell on, a full backpack may be sold there, outside the dungeon (the
dungeon's hold still holds it - with the gear pass on, only its Deck and Pet
groups: the gear it compared is sold - unless "...even with a dungeon's
drops in it" is ticked); with the gear pass on (Settings: gearswap - see
"Gear" below) the run's new pieces are logged in learned\drops\<run>.txt and
the plan is logged. "Until its gear is swapped"
(the Dungeons tab's box, needs the gear pass): once every slot the dungeon
drops is worn with a piece it dropped - or 30 runs brought no upgrade - it
goes on to the run picked under "then" when that starts where the wizard
stands, else it stops and tells you where to take the wizard (Discord). The
Gear column shows each run's runs, dry runs and "done". In a run's file you
can also put (older versions skip them): slots|hat,robe,shoes (the slots it
drops - else resources\dungeons_known.txt's for a run named after one of
Olympus, Waterworks, Hades, Darkmoor), stopafter|30, boss|<boss name>|<deck
id> (that deck for that boss). Check a run's file with
	python vision\dglint.py
(every run in dungeons\, or name one): the steps it reads, a run that doesn't
end where it starts, a zone change right after a battle, a walk recorded
right after a sigil's X (the wizard drifted while it counted down: since
v1.0.0 the bot neither records such a step nor walks off the sigil for one
recorded before), and the lines above.

Open with Wizard101 (tray menu, or Setup.exe): a small watcher starts with
Windows (a shortcut in your Startup folder to Wiz-Maxxing.exe /watch - its
own tray icon) and opens the bot by itself when Wizard101 starts - in
standby: it does nothing till you press F6 in the game. Before that it checks
for updates (it asks only if there's a newer release). Never a second bot: one
already running is left alone. A bot opened this way and never turned on
closes when the game does, and opens again with it. The tray menu's tick (or
the watcher's own "Don't open with Wizard101 any more") turns it off.

Walking by the game's memory (navmem:1 in PlayerStats.txt, the default): the
vision helper also reads where the wizard is, which way it faces and where the
quest arrow points straight out of the game's memory - READ-ONLY: nothing in
the game is written or changed, and it sends no keys of its own. The walker
steers by it once it's checked (it agrees with the arrow on screen, or a turn
goes the way it says), uses its distance instead of the OCR'd number, walks on
by it when the arrow can't be seen (scenery, or Pigswick Academy's gold carpet,
which the see-through arrow can't be picked out from) and measures its turns.
It also follows a route the helper plans round the walls over the zone's map
(the Map window draws it in green), instead of walking into them. Whenever it can't be used it follows the arrow on screen as before
(debug.log: "the game's memory ..."). navmem:0 = only the arrow on screen.
More in ..\AutoQuester\README.txt.

Smoother walking: steering by the game's memory on its route, a big turn (up to
100 degrees) is made walking on when the helper says the wizard's turning arc
there is clear of walls and mobs (its turning circle is worked out from how
fast it walks); else, and by the bare arrow, it stops and turns on the spot as
before. It arrives on one memory reading, or when it has walked right past the
goal, instead of going to and fro over it. The speed stays as it is through its
own short stops (a mob or the party waited for), dropping to 1x once it has
stood 1.5 s, and goes fast only once W has been held a moment - no 1x/2x flips.
Talking, X, dialogues, sigils, gates, battles, you playing, F8 and exit are 1x
at once, as ever.
Near the goal by the game's memory (the goal in this zone, 1500 game units or
less, straight ahead, no mob on the way): the last bit is walked closed loop -
W up, 1x (from 2500 off; a zone's way out from 600), turned on the spot to
face the goal, then W held
while its place is read every ~40 ms and let go at it: a talk goal's NPC 300
off, anything else 150. Then X. It no longer walks over the goal and turns
round. A fence, wall or water between (the way round much longer than
straight): no straight walk - it goes round by the route. A goal on another
floor is never "walked past". A talk goal ("Talk To ..."): a prompt is the quest's only with its NPC's
name on it (no X at a vendor next to it); its prompt is X'd even just after a
dialogue (3 s after the last X, 3 tries in 2 minutes); the talk is done when
the game's goal changes, not by the arrow's number (it jumps by the goal); X
that opens nothing is tried again from close by - never walked on through the
NPC; a shop it opened is closed - and after 3 tries it waits by it (a notice, once) and tries again every
2 minutes. Its distance is always used (the arrow's 1 = 100 game units when
the scale isn't sure), learned only with the goal in the zone; no back-up for
a hidden arrow while it steers. debug.log: "Walk: approach: ...", and every X
says where the goal is ("the game's memory: the goal N units off").
Turning with the mouse (mousesteer:1 - Settings, on unless you switch it off):
walking, the wizard is turned with the mouse - the right button held in the
middle of the scene and the mouse slid, then let go - at once, so it doesn't
stop at corners; the mouse goes back where it was. Only while it walks by the
game's memory (it reads the facing back as it turns - how far a mouse count
turns the wizard is measured on the first turn), out of battle, Wizard101 in
front, you away from the keyboard and mouse 3 s, no window over the middle of
the game (its words: Crowns, shop, quest... - not the words of the bot's own
notice over it) and the game itself under the point the button is pressed at
(not the bot's notice or another window). Above 5x the game is put to 1x for
the turn, as for an A/D turn. You touching the keyboard or mouse mid-turn ends
it there, the mouse left to you. Not in the first 0.6 s after setting off (the
right button turns the wizard while he runs). Anything not sure: A/D as before.
A turn on the spot tries the mouse from standing (the camera turned, then W)
once a count's worth is measured; A/D when it misses. A measuring try that
didn't turn him waits 10 s before the next. The mouse not turning the wizard
three times (no turn, or his facing not read on the way): left alone for 10
minutes; debug.log and the Dashboard's log say so each time ("Walk: mouse
steering off for 10 minutes - ..."), the first time in a run a tray tip too -
with which half failed: "the game didn't take the right-button drag" (the
cursor stayed shown before and after the slide), "the game took the drag but
the wizard didn't turn" (it hid), or "the wizard's facing couldn't be read from
the game's memory mid-turn (<why>)" (then send the log lines it names). When
the cursor stays shown, the bot first tries that press once more with the right
button pressed the raw way (the mouse lock leaves that button alone for it) and
keeps that press for the run if it turns him. What to try: check your wizard
turns when you right-drag yourself; or untick Settings > Lock my mouse while
the bot uses it for one run. debug.log says why when a mouse turn is tried and
not made: "Walk: mouse steering: not now - <why>", "... the facing couldn't be
read (<why>) - A/D", "... the mouse didn't turn the wizard (N counts, N
degrees; the cursor x,y shown|hidden before the slide, x,y shown|hidden
after) - A/D", "... off (Settings: Turn with the mouse while walking)" or "...
waiting for the game's memory (<why>)" (it isn't walking by it, so the mouse
isn't tried), each at most once a minute. Once a minute after walking,
debug.log says how smooth it was: "Walk: the last minute: W held N% of N s out
walking, N stops, N turns on the spot, N turns walking on (N by the mouse), N
speed keys".

Faster walking with Cheat Engine's speedhack (Settings: "Walk faster with
Cheat Engine's speedhack", off unless you switch it on): Cheat Engine speeds
the game up; the bot only presses its speedhack hotkeys (F13-F24, keys no
keyboard has). Setup.exe's "Cheat Engine speedhack" sets Cheat Engine up for
it: installs it if it isn't there (its installer from cheatengine.org, opened
for you to click through - decline the other programs it recommends) and puts
the bot's script (CheatEngine\wiz-maxxing.lua) in its autorun folder (asks for
admin). Each time Cheat Engine starts, the script attaches it to Wizard101 -
again after the game restarts, never over a process you opened yourself - and
the bot's two keys set the speed, read from PlayerStats.txt (a change in
Settings needs no restart). With two game windows it stays on the one it has
and never moves onto one that ran beside it (another account): when the one
it has closes, it waits for a new one (to use the other, restart Cheat
Engine; started with two already open, it takes the newest). With the script
there, the bot starts Cheat Engine when it starts with the speedhack on, or
when you switch it on: Windows asks for admin first (Cheat Engine 7.4 and 7.5
run only as admin - the bot doesn't wait for your answer), then its window
opens: click back into the game. After an update that changes the script,
Setup.exe ticks "Cheat Engine speedhack" again: press Install to put the new
one in. Without the script, Cheat Engine is yours to install, attach and set
up as below. The keys: the walking key while it walks, the 1x key for battles
(pressed at every round), talking,
dialogues, shops, near the goal, collecting, dungeon runs, a teleport ahead,
getting round an obstacle, when you play, F6 and when it stops. Its turn and
wait times are divided by the speed; above 5x turns are made at 1x. In Cheat
Engine: Settings > Hotkeys, two "Speedhack speed" entries - the walking speed
(speedfactor) and 1 - with "Disable when released" unticked (not needed with
Setup's script); the tray menu's "Speedhack: press its ... key in 3 s" items
press a key while you're in its
hotkey box. If the wizard doesn't turn faster (Cheat Engine not attached after
Wizard101 restarts, the key not taking) the bot stops using it for the run
("speed: off for this run" in debug.log). Risky: KingsIsle may notice.
Mobs (mobavoid:1, the default - Settings: "Keep away from mobs"): the helper
also reads the zone's mobs out of the game's memory (read-only) and the route
keeps out of what each one sees, so no battle starts on the way: Settings,
"...what they see" (mobshape) - a semi-circle in front (the default), a
circle all round, or a cone in front (mobcone degrees wide) - mobradius (300)
far; which way each faces is read from the game too, and a little room is
kept all round its body. Players put the cone at 50 to 120 degrees; to
measure what they really see, each
battle's first round logs which mob started it, how far away you were and how
many degrees off its facing ("Caught by ..." in debug.log). Not
the mobs the quest is about: those named in its goal line ("Defeat 3 Lost
Souls"), or standing at its goal; and not while collecting. With no way round
(a narrow street), the wizard stands still till the mob moves off - 25 s at
most, then it walks on past it. Never inside one's reach or sight, though (a
mob walked up, or the wizard came out of a battle there): it walks out of it
first - along the route if that leads out, else the shortest way out (never
nearer the mob) on the quest's side - backing straight out when the way out is
behind, never standing still turning in it - and only then waits. A battle
starting (the wizard held or turned by the game) no longer stops it steering
by the game's memory; while it doesn't, it keeps to the route by the arrow, and
with no route at all it won't walk the arrow's straight way into a mob's reach
(20 s at most) or back up into one. The walk to the potion seller keeps away from
all of them. The dashboard's Map shows them: red dots with a faint ring (kept
away from: its shape), the quest's amber, the nearest ones named.

Mobs walking (v1.0.0 work, not tried in the game yet): the helper also works out
which way and how fast each mob walks from the readings of the last second, and
a walking one's ring and sight are kept out of along its way - where it will be
over the next 2.5 s (700 game units at most) - not behind it, so the route
passes behind a walking mob rather than in front. The wait for a mob on the way
looks at where each walking one will be by the time the wizard gets there: one
walking off the route no longer holds him, one walking onto it does. A mob read
standing still, or not read often enough to say, counts as before. The Map
draws an arrow from a walking mob along its way, and its ring's outline where
it will be. "Caught by ..." in debug.log now says whether the mob was walking
or standing when it noticed you. To tune the numbers (how fast mobs walk, how
long they stand): vision\navmem.py --mobs --motion 60 in the game.

A line of mobs (v1.0.0 work): a gap narrower than 250 game units between two
mobs' rings or sight is closed - the line is one wall - and the route goes all
the way round its end (the planned area is widened to take the whole line in;
a line too long for it - "too long to go round in one window" in vision.log -
is routed as before). Still no way but through a gap (a street the line stands
across), the wizard walks through it at once, out of the mobs' rings and sight,
as before - or, with mobwall:1 (off by default till the 250 is measured in the
game - Settings: "...wait at a line of mobs with no way round"), waits as for a
mob on the way (25 s at most), then walks on through the gap, still out of the
mobs' rings and sight. The Map shades the closed gaps.

Other players' battles (duelavoid:0, off by default - Settings: "...and other
players' battles", with "Keep away from mobs" on): the route also goes round
the zone's duel circles that have a battle going on - read from the game's
memory, read-only - so the wizard doesn't walk into one and join it; with no way
round it waits for the battle to end (4 minutes at most), then walks on past it
round its edge ("waiting - another player's battle on the way"). The Map shows
them as violet circles. Off till how the game keeps those circles in memory is
checked in the game: vision\bossmem.py --duels 30 next to someone else's
battle, at a dungeon's sigil and in your own battle (the helper's /duels lists
them too).

Mobs that catch you anyway (mobgrow:1): each battle a mob the quest doesn't
need starts (not collecting, not one named in the goal line, not right after X
at the goal, not a dungeon run that fights everything, not while you play)
widens the reach the route keeps out of - to where it caught you from, and 25
more (20 at the least; 1500 at most): how far they notice you (mobradius) when
it caught you in front of it, their reach all round (mobbody - a semi-circle or
cone's sides and back, 120 at first) when from the side or behind. debug.log
says so under "Caught by ..."; set them back in Settings any time.

Bring Wizard101 to the front (gamefront:0 - the dashboard's "Game to front"
button, the tray menu, Settings): with Wizard101 not the window in front, the
bot brings it there when the quest arrow shows (walking - once you've left the
keyboard and mouse alone 3 s, so what you type elsewhere doesn't end up in the
game) or a battle round is up. It brings the window forward; it never clicks in
it to do so. Left the PC with another window in front (nothing touched for 5
minutes): the game's brought forward all the same, setting or not - and after a
reconnect it's left in front - else the bot can't walk and the game logs out
for inactivity.

You playing: while you use the keyboard or mouse yourself, the bot waits - no
battle rounds, no walking, no potions; a walking key it held is let go at once.
It carries on 3 s after you stop (handsoff in PlayerStats.txt; 0 = it never
waits). If you take over during its turn, it leaves that round to you.
Switch it on/off with the tray menu "Wait while I play" (ticked = on) or the
dashboard's "Wait for me" button; it's kept in PlayerStats.txt (handsoffon).
It's on again, with 3 s, every time the bot starts - it never takes the mouse
from you as it starts; switched off or changed, that holds for the run.

Your mouse locked while the bot uses it (Settings > THE MOUSE AND WAITS, "Lock
my mouse while the bot uses it" - mouselock, on unless 0): while the bot has
the mouse - a battle round (from its first look at the hand to "Round done"),
a click out of battle, a mouse turn while walking, a potion route's, a login
or a quick sell's click - your mouse can't move the pointer, and with the
pointer over Wizard101 its buttons and wheel do nothing. What you do with the
mouse then doesn't count as you playing. The keyboard always stays free: F6
stops the bot and frees the mouse, and with "Wait for me" on any key leaves
the round to you (Alt+1 / Alt+2 / Windows+3 free the mouse for their pick).
It's freed at once when the bot's done, when Wizard101 isn't the window in
front (Alt+Tab), on an error and when the bot closes - and by itself if a hold
of the bot's hasn't been renewed for 15 s (one it forgot to give back too,
however busy the rest of the bot is). Off: your mouse always works (moving it
makes the bot wait for you, as "Wait for me" says). debug.log:
"Mouse locked - ..." / "Mouse unlocked - ...".

Play for me (the dashboard's button, or the tray menu): for leaving the PC for
days. Every check for you is off - it no longer waits while you use the
keyboard or mouse, gives the mouse back, keeps out of a window you're using or
leaves a shop's window to you; it brings Wizard101 to the front whenever it
needs it. One click turns it on - the button goes green, "PLAYING FOR ME" -
and another turns it off (red again). It's off at every start - the bot only
takes control once you've said so. F6 and F8 still stop it.

Updates: opening Wiz-Maxxing (Start menu, desktop, ..\Wiz-Maxxing.exe) checks
GitHub for a newer release and asks before installing it; tray menu "Check for
updates" does it any time - so does the dashboard's Updates button (top right),
which says live whether a newer version is out ("Update to v..."; it looks it up
45 s after the bot starts and every autoupdate minutes, out of the bot's way). The version
is in the windows' titles, the tray menu's first line and the dashboard's
STATISTICS. Needs a GitHub token once per PC (Setup.exe, "GitHub updates").
Your settings, learned cards, potion routes and pictures are kept.
updater.log (next to Wiz-Maxxing.exe) says what it did.
Collect quest items by the game's memory (Settings > WALKING, collectmem - on):
a "Collect N <things>" goal whose things lie about the zone (Piece Of Coral in
The Grotto, from the game's item names) - each one's place is read from the
game's memory (read-only), the nearest walked to round walls and mobs and
stepped onto (picked up; still there after a moment: X), then the next. One it
can't reach in a minute waits 3 minutes. None seen: it roams and walks into
monsters as before. A collect goal the game shows no arrow for (its goal has
no place) is read where its line sits and collected the same way. The
dashboard's map shows them as green diamonds (the goal's brighter, named).
debug.log: "Walk: collect: ...".
Goals the game shows no way to ("Use Inactive Protector in District of the
Stars (0 of 3)" stood there doing nothing): the game's memory (navmem:1,
read-only) says when the quest helper has no place for the goal - the arrow
seen on screen then is a phantom: not followed, no X at nothing, no pushing on,
no waiting there - and what kind of goal it is. A goal to use things (Use,
Read, a "Collect" of an object): its things are found in the game's memory and
in the zone's own file - all of them, even far off - the nearest walked to
round walls and mobs (mobs kept off, no monsters walked into), X at the prompt
naming it, the count watched: up, the next; not, X once more, then it's left
for 5 minutes. One that shows no prompt: one X in case, then left. None known:
it looks about, X only at a prompt naming the thing (never a teleporter), and
after 3 minutes shows a notice (Quest needs you); each one tried and the count
not rising: the notice at once. A go-to goal: the place by its name (a thing,
or one of the zone's volumes) walked to, no X; the same goal 5 s there: walked
through it, then the notice. A talk goal: the NPC by its name walked to, then
talked to as any talk goal (its own prompt, 3 tries, the wait by it). Anything
else ("Practice Photomancy"): left alone, nothing roamed for. Waiting at a goal:
its id and count are read every 3 s - moved on, it walks on at once. A use
goal's prompts on the way: X only at the ones naming its thing; collecting
never X's a teleporter's. An older helper (no "no place"): as before.
debug.log: "Walk: use: ...", "Walk: go: ...", "Walk: talk: ...".
Mobs kept off: a catch by a mob the quest doesn't need raises how far they're
kept off (mobgrow); every 10 minutes of walking without one it's made a tenth
smaller again - never below what you set yourself in Settings (mobshrink).
Puzzles: a blocked way (puzzles, puzzlelearn - Settings > WALKING, both on).
The way to the goal blocked for good at one spot - a gate or a door that won't
open (2026-10-26, Storm Lord's Temple: its gate opens only once the two guards
off to the sides are beaten): a door, gate or collision object by the spot in
the game's memory (read-only), or the wizard still stopped there after the
usual tries, in a dungeon or a building. Before telling you, the bot tries what
usually opens one, looking after each try whether the way's open: the enemies
standing off to the sides fought (one camp at a time, the ones the zone's own
file says open something first - never a boss, never one beyond the block or
on another floor), things with a prompt nearby X'd (never with Crowns on the
prompt, never a teleporter, sigil, lock or shop), the zone's NPCs talked to.
Then it waits at the spot and the notice "Way blocked - the quest needs you"
says what it tried and what the game said there (Keep trying: the tries once
more). At most twice an hour at one spot, 12 minutes of tries; at 1x; never
for a party's follower, in a dungeon run or a battle. What you do to get past
after a notice (or while it waits there) is recorded - the enemies you fight
(which kind, where), what you press X at or talk to (its name, where), nothing
else you type - and saved in learned\puzzles.txt once the way opens or the
goal moves on; the bot does it itself first the next time (any character; copy
the file to another PC). The file is yours to edit (its first lines say how),
even while the bot runs: it reads the file again before it changes it. Mouse
clicks on things aren't seen - press X. A restart keeps a recording under way
(learned\puzzle_recording.txt), a fight under way, and the wait at a blocked
way with the hour's tries (generated\puzzle_journal.txt, puzzle_hold.txt).
debug.log: "Puzzle: ...".
Puzzles, new in v1.0.0 (not tried in the game yet): a gate's model can stay
in the game's memory once it's open - its collision wall is what goes - so a
gate still there with no collision wall by it no longer counts as shut: the
bot walks through to see; any of the doors by the block going from memory
counts too. A lever or pedestal the game names nowhere is found through the
zone's own triggers: an object with no name whose template's name has the
words of one of their use events ("PedestalUsed": CL-Pedestal-01 - a guess
by the name; only the placements the zone's file ranks best, at most 2 of
the things tried), named in debug.log's plan line ("levers (zone's
triggers): ..."). With puzzlelevers (Settings > WALKING, off - not tried
yet) it's X'd with the things with a prompt (any press prompt within 150 -
never with Crowns, never a teleporter, lock or shop), one whose trigger
opens the gate at the block first. Off: named only, the tries as before.
A thing or NPC named Block, Clock or Warlock is no longer taken for a lock.
A gate's state (open / shut) is read from the game's memory and written in
debug.log ("now Closed" by each door); puzzlestate (Settings > WALKING, off)
goes by it: a state changed since a try began counts as the way maybe open,
one still the same as shut, and a gate already in an open state (Open,
Unlocked...) that isn't the zone file's starting one isn't the block (a gate
shut as the zone begins still is). Turn it on once vision\statemem.py
--watch (the discovery tools below) shows the gate's state change as it
opens. Leaving a dungeon and coming back (a new instance: every object's id
new) no longer counts as the doors by the block gone - they're found by
their name and place too.
The quest's page: every "needs you" notice about the quest (stuck, collect,
waiting, no arrow, a blocked way) has a link to the quest on Wizard101 Central
(and its search) - in the notice, in debug.log and in the Discord alert. A
click is yours: the bot never opens it.
Badly stuck, counted (TODO goal 2 "Measure it"): each time the walker gives up
- couldn't get round an obstacle in 5 tries, no closer to the goal in 3 minutes
of walking, the teleport to the Commons or "stuck at the same place again", a
teleport that doesn't take, a sigil that won't start, a "Stuck" notice - is
one badly-stuck episode (its first give-up names it; the Commons and the
notice after it don't count it again), and so is a dungeon run's stop for
being stuck. Each stuck episode's time lost - from when the wizard last got
closer to when it's clearly closer again (10 nearer the goal, or 30 on along
the route), in another zone, at the goal or at the Commons; the gaps between
the walker's steps only (a battle, a loading screen, the bot off: left out),
and the wait for you after a "Stuck" notice too - is logged when it ends. The
dashboard's STATISTICS: "Badly stuck N (12 min; all: M, 3.4 h)" - the time
lost this run, then all time (kept in dashboard.ini [stats] badstuck /
stucklost). debug.log:
"Walk: badly stuck #N (kind): why", "Walk: stuck over - N s lost (kind, T
tries, how)". No closer for 3 minutes with the Commons used in the last 10
(it goes on trying, the Commons once it may) was silent: now said once - the
log ("badly stuck, nothing takes over"), a tray tip and Discord (its own kind
of alert: the "Stuck" one when walking goes off still comes).
Past runs (and older logs - their figures estimated, said so):
	python vision\stuckreport.py              (debug.previous.log, debug.log)
	python vision\stuckreport.py "<OneDrive>\Wiz-Maxxing logs\<PC>\debug.log" --episodes
per run: badly stuck, time lost, unstick tries, give-ups, the Commons, notices,
dungeon back-ups, sigils X'd / started / didn't start (and which within 30
minutes of a relog), relogs; --json for all of it. Read only.
A sigil that won't start (2026-10-26 21:44: one never started after a relog
and was X'd again and again): after each X at a sigil the bot looks whether
it started - 30 s on, still in the same zone with no loading screen by the
game's log is "didn't start" (debug.log "Walk: sigil: didn't start - ... (N
in a row here; a relog M min ago)"; its 30 s counted as time lost); a sigil
that loads goes on as soon as its loading screen is over, not after the whole
30 s ("Walk: sigil: in <zone> N s after X"). 3 in a row at the same spot (2
within 30 minutes of a relog - yours or the bot's reconnect) at the quest's
own sigil (the arrow led to it): walking off and the notice "The sigil won't
start" - F8 tries it again. A sigil only walked past (the bot X's every sigil
it walks over) is never given up on: said, and walked on from as before.
Leave it and come back (sigilhome - Settings > WALKING, off unless you switch
it on: new, not tried in the game yet): before that notice, once in 30
minutes at a sigil, it leaves and comes back - a Mark there (Page Down),
Home, the Recall (Page Up) back, X again. Your Mark is never moved when it's
the potion seller's (potionmark on, buying recorded at your Mark): then the
Commons (End) and the walk back, as when badly stuck (not within 10 minutes
of the last). The Mark way needs the mana globe read at 20 or more (a Mark
and a Recall take up to 10 each; a globe that can't be read: not the Mark
way - a Mark that didn't take couldn't be told). Still not starting after it:
the notice. No X at a sigil 3 times in 10 minutes at its spot, whatever path
pressed it (the one at the goal used to go round that). Written without the
game - to be tried in it.
A collect goal keeps them off too (all but the mobs its goal line names).
The quest's goal line from the game's memory (navmem:1, read-only - the
helper's /goal, vision\questmem.py): the line under the quest arrow ("Defeat
Gobblers in Colossus Boulevard (0 of 4)") is read exactly as the game draws
it, with what it names - the mob or its kind, the item, the NPC - its kind
(defeat, collect, go to, talk to) and its count, instead of by OCR of the
screen, which slips letters ("Opiio (jn -rhe" for "Defeat Optio Agenor ...":
the quest's own mob was kept away from). Which mobs are the quest's (walked
into, not kept off), the quest items picked up, collecting and its count all
go by it; a mob whose name only shares a word with the place (Grotto Crab in
"... in The Grotto") is no longer taken for the quest's. When it can't be
read (navmem:0, an older helper, no quest) or the game hides the line (the
quest helper off), the line is OCR'd as before. The memory keeps the line
whatever is drawn over it, so collecting a goal with no arrow starts only
while the line shows on screen too (not over a dialogue or a window X
opened, nor a screen Remote Desktop doesn't draw), and never while X was
just pressed or the wizard's talking. A mob the helper took for the quest's
(its name, its kind - "Gobblers" for a Gobbler Scavenger - or one by a
fight goal) that catches the wizard doesn't make the mobs' reach bigger
(mobgrow). In a game build the helper doesn't know yet, the look for the
quest's data runs on its own, further apart while it finds nothing - the
card and position reads don't wait for it.
debug.log: "Walk: the quest's goal line: ... (from the game)" - "(from the
screen)" when OCR'd; vision\vision.log: "goal (memory): ...".
Turning: by the mouse - any turn while the wizard runs, backing up (turned
round, walked off, turned back - not the S key), getting out of a mob's reach,
walking to a quest item, following the party's leader, a dungeon run, close by
its target too - and from standing (the camera turned with the right button,
then W: he faces the camera's way). The keys (A/D, S) only when the mouse fails
(two misses from standing: not tried that way for 10 minutes - debug.log
"mouse steering: ...").
Decks (the dashboard's Cards tab - its row of buttons: Hand & enemies, your
decks, + Deck): a "Small deck" (collect goals and anything else) and a "Large
deck" (bosses) to start with, more with + Deck or Copy (6 at most). Each has:
its school (or any), what it's used for (anything else, collect goals, bosses -
see below, dungeon runs, farming - loop/lore mode), a priority (of
two for the same, the higher), the game's Equipment Set that puts its in-game
deck on (Ctrl+1-9: set the sets up in the game - they swap gear, pet and mount
too; pressed out of battle with you away, once a minute at most), and the
settings it has of its own (pick one in its list, type the value, Set - empty:
your Settings'): card logic, blades, traps, aura, bubble, healing, pips,
discards, which of hit1-4 and the heals it plays. Its damage a hit as a range:
its weakest hit with nothing on it to its strongest at its best roll with every
boost it plays and a critical (x2 - its most, against no block; with your
damage % and critical for that school - the community's crit model, KingsIsle
doesn't publish one). Save keeps it (decks\<name>.txt - updates keep them);
"pinned" uses it whatever's ahead. Before each fight the bot picks one - the
dungeon run's (its Deck box on the Dungeons tab), a pinned one, the boss's,
collect's, farming's, anything else's - and logs "Deck: <name> (why)" (the
dashboard's Deck line shows it too). No deck set up, or one that sets
nothing: it plays exactly as without. A deck for one boss by name (v1.0.0 -
a boss's cheats: no traps, one school, hit first... as that deck's own
settings): a bossname|<name> line in its file (decks\<id>.txt; several with a
comma between) - that deck for that boss, ahead or in the battle, before the
other decks for bosses ("Deck: ... - its deck by name"); a dungeon run's
boss|<name>|<deck id> line comes before even its own Deck box's deck.
Bosses before the fight, by the game's memory (navmem:1, read-only - vision\
bossmem.py, the helper's /mobs and /battle): each of the zone's mobs' title as
the game has it (Boss, Elite, Normal...), rank, max health and the game's own
boss flag. Out of battle, the bot on and nothing loading, a boss is "ahead"
when the quest's goal names it, the walker goes to it (the quest's mob by its
name or by its goal - not one of the same family elsewhere in the zone) or the
dungeon run's way leads to it - an Elite only when it takes 3 or more of your
best hits (its max health against the deck's strongest hit at its best, no
critical). One only passed by isn't (the walker routes round it; one walked
into is found in the battle). The deck for bosses is picked then and its
Equipment Set pressed before the fight (10 s after the last press, not the
minute) - "Deck: Large deck (a boss ahead: Governor Nereus, rank 9 boss)".
Kept till that battle's over, or 30 s after the boss is gone or far off (from
the end of a battle it wasn't in); a missed reading changes nothing (no
switching back and forth), but 2 minutes of them, the bot off or another zone
let it go. A set pressed just before a battle starts is pressed again after
it. In the battle its enemies are read from the memory: a boss among them gets
the boss deck's settings without Alt+1 ("a boss in this battle: ..."; not
read: the boss ahead it was walked into); a fight on the way to the boss keeps
the boss deck's settings while its Equipment Set is the one on ("(its deck is
on)"). Alt+1 works as before. No memory (navmem:0, no helper, dual mode):
Alt+1 only.
Decks from the game (the Cards tab's From game button, and by itself every 30
minutes out of battle, the bot on): every in-game deck that's in an Equipment
Set is read from the game's memory (read-only - all your decks, the
backpack's too, each card's kind from the game's own spell data) and made a
deck here, linked to it: its Equipment Set, its school, its name and what it's
for (big single hits and 4+ blades / traps: bosses; else anything else and
collect goals; your only deck: anything else) and the settings its cards call
for - no blades in it: blades off (traps, auras, bubbles, heals, Tower Shield,
Reshuffle the same), boost first with 4+ boosts and a big hit, hit first with
mostly AoEs. A deck already on that Equipment Set takes the link instead of a
new one; six decks at most on the tab. Read again later, a linked deck
follows its in-game deck (a set moved, cards changed) - but a setting you set
or clear yourself on the tab is yours: never changed again (the file's
learned| line lists the ones learning set).
Can this deck beat it (the battle simulator - vision\battlesim.py): when a boss
is ahead, each deck for bosses linked to an in-game deck is fought against it
300 times in the simulator - your real cards (the main deck shuffled, 7 in
hand, pips each round, power pips), the bot's way of playing (its card logic,
boosts before a hit - each blade and trap once a battle, and once more
sharpened (a trap made potent) with a Sharpen (a Potent) in hand, unless
reboost is on -, the kill check - first with no enchant, then with
the best one in hand - and that enchant on every other hit it casts,
treasure cards drawn for an enchant that makes the kill as the bot
draws them (drawenchant), defending when the enemies' hits could finish
you this round (enemyspells, defendat: a heal under 90% health, else
Tower Shield, else an absorb), heals under healat, and when nothing
else goes Tower Shield, an absorb that costs no pips or Reshuffle),
your damage, pierce and critical for that school, the boss's max health from
the game's memory, its resists and block from the battles recorded
(learned\battles\), its spells from the wiki (else its hits recorded on you).
Logged: "Deck: can Large deck beat Governor Nereus? likely: 78% won, 2% lost,
20% ran out (about 9 rounds; 300 battles) - Governor Nereus 9000 health: Kraken
at its best 2153 with Stormblade, Storm Trap - 5 hits"; the deck most likely to
win it is the one picked (5 points better or more; else the priority), and "no
deck for bosses is likely to beat it" when none wins 65%. The Cards tab shows
each deck's last verdict under its damage. In the simulator too (v1.0.0): a
hit's damage over time - its ticks at the start of the next 3 rounds; what each
enemy does besides hitting, as the battles recorded show it - its heals, its
shields and blades on itself, its traps, weaknesses and stuns on you, its
damage over time's ticks on you (an enemy with none recorded does none of it:
the verdict says "nothing learned yet of what X does besides hitting -
optimistic"); an enemy's heal spell heals its side (before v1.5.0 it counted as
a hit on you). Since v1.7.0 the simulator deals as the game does and casts as
the bot does: only the main deck is dealt, so a deck's treasure cards count
only with drawenchant on, and with reboost off (the default) each blade and
trap goes once a battle. Decks with treasure cards win less often than before
v1.7.0 - that is how the bot plays them. In v1.7.0 a second copy of a blade or
trap waited in hand till a Reshuffle. Since v1.8.0 the bot throws away the
copies it can't cast again (discardspent, on - see Discarding below) and the
simulator plays them that way, so decks with several copies of a blade or
trap win more often again (8 Storm Lord + 6 Stormblade + 6 Storm Trap against
a 6000-health boss: 56% won with the copies held, 93% thrown away). As a
party's Blader or Healer, or in dual mode, the bot keeps them and the
simulator is told so. Where the bot can't read the game's hand, or its card
boxes haven't lined up yet, it keeps them but the simulator still throws
them. Not in it yet (the bot doesn't play them either): minions, and the
stuns and damage-over-time-only cards you could cast.
Sharpen and Potent in the simulator (v1.9.0): played as the bot plays them - a
Sharpened Blade (a Potent Trap) goes on a blade (a trap) being cast while that
blade's sharpened cast is free: no pip, no turn, the card's +N% (10 when it has
none), never on a pet's or gear's copy, nor on the copy the bot casts instead
when the first copy in hand can't go (that one goes plain). So with reboost off
each blade and trap can go twice a battle, once plain and once sharpened. A
Sharpen is kept till a blade has been sharpened, then thrown once no blade in
hand can take one; a Potent is never thrown; with discardunused on, useblades
off throws the Sharpens away, usetraps off the Potents. A deck with Sharpens
and no blade holds them all battle and wins less often than before v1.9.0 -
that is how the bot plays it (the command line below says so). Measured on the
same dice (2000 battles each, discardspent on): 8 Storm Lord + 6 Stormblade +
6 Storm Trap + 2 Sharpened Blade + 2 Potent Trap against a 6000-health boss won
93.5% before, 96.9% now; 10 Thunder Snake + 6 Storm Lord + 4 Sharpened Blade
against 3 mobs 22.6% before, 18.9% now. Since v1.9.1, with reboost on, the
bot keeps a blade's copies once both its casts went (the next hit it fits
frees them - see Discarding below), and so does the simulator: 8 Storm Lord,
3 Stormblade and 3 Sharpened Blade against 3 mobs won 44.5% in v1.9.0, 57.0%
now (2000 battles each, the same dice).
Try it on the command line:
    python vision\battlesim.py --deck deck.json --foe "Governor Nereus:9000:ice"
Decks matched to the zone's enemies (deckzone - Settings, HOW IT PLAYS ITS
CARDS; off unless you switch it on, new and not tried in the game yet): out of
battle with no boss ahead, each in-game deck in an Equipment Set is fought in
the simulator against the enemy groups you've fought most in this zone (the
battles recorded there), each with the settings the bot would play it with (its
deck profile's, then yours - no profile: yours and those its cards call for; a
group with a boss as a boss fight); of your decks for the same use as the one
picked (collect, farming, dungeon, anything else - never a boss deck, the
pinned one or a dungeon run's), the one that wins clearly more often (5 points,
or as often in a round fewer) is put on - "Deck: Small deck - the simulator's
pick for WizardCity/WC_Streets's enemies: 96% won in 3.1 rounds - Large deck
88%". Worked out by the helper in the background (a few seconds), kept 10
minutes; while it's worked out again the zone's last pick stays on. Every deck
rolls the same dice against a group, so two decks with the same main deck (one
deck in two Equipment Sets) score the same and are never swapped for each
other. A zone with no battle recorded yet: as before.
The round planner (planner - Settings, HOW IT PLAYS ITS CARDS; off unless you
switch it on, new and not tried in the game yet): in each round the bot plays
itself - after the kill check, defending and the heals - every card in your
hand that can go now (a hit or trap at each enemy, and a pass) is tried in the
simulator from that very round on: your hand, pips and health and the enemies'
health from the game's memory (read only), the blades, traps and aura the bot
counts (a blade or trap it cast isn't tried till a Reshuffle - with reboost
on, a hit - frees it; since v1.9.0 one whose sharpened cast hasn't gone is
tried sharpened while a Sharpen (a Potent) is in hand: "with Sharpened Blade"
in the advice), the rest of your main deck shuffled and treasure
cards drawn the bot's way (the worn deck as every deck was last read out of
battle - else more of the hand's cards), the rest of the battle played your
settings' way; each play up to 100 times, in 0.3 s. It is advice only:
debug.log says "Plan: would play Tempest on all (won 92% in 3 rounds, 100
tries; ...) - your settings' way: Stormblade on you (won 85%) [tid ...] -
advice only" and the bot then plays its own way - it never changes a card.
The battle recorder keeps the advice with what was played; see how often they
agreed, and how those battles went:
    python vision\battlelearn.py --advice
Learned plays: what was played in each kind of round of the battles recorded
(your pips, enemies left, a boss, a hit you can pay for, your health) and how
those battles went - per school, all schools' together while yours has few
(yours weighs half after 20 such rounds) - only tip near-equal plays. The
helper remakes them every 10 minutes while the planner is on (learned\
battles\plays.json); look:
    python vision\battlelearn.py [--school storm]
In a party battle (v1.0.0) the party's other wizards on your side are in the
simulator too - each its seat (the cast order), school, health and battle
role from the party; the enemies' single hits land on one of you at random
(an enemy known only by its hits recorded on you: each of you takes them at
that rate), a wizard at 0 health stays down (no hit, no card), a hitter
whose hand isn't known hits as an unknown enemy does (100 a pip, every other
round), a blader or healer whose hand isn't known does nothing - and the
blades, traps and shields on you and on the enemies are read from the game's
log (the party's and the enemies' too), not only the bot's own count. Not
asked in dual mode, with two or more game windows open, as a party's blader
or healer, after you played a round of the battle, while learning every
card, or with navmem off. Playing the advised card itself (planner 2) isn't
built: it needs every card cast by the game's memory and each enemy's plate
matched first; the leader telling each bot its card (the helper can already
plan the whole team's round from their hands - /plan's teamplan) needs the
bots' hands sent over the party first.
New spells, training points and spell quests (Training.ahk - TODO goal 4;
mostly NOT BUILT yet). What runs now only reads: out of battle, the bot on,
about every 10 minutes (the first 3 minutes in; not while a zone loads or on
a dungeon run - the walker stops for the moment it takes) the spells your
wizard knows are read from the game's memory (read-only, the vision
helper's /book) and kept in learned\
spellbook_<wizard>.txt; a spell that wasn't there is written in debug.log once
- "Spells: new spell Thunder Snake (Storm, 1 pip, Damage) [tid 1001]" - and
the dashboard's What it sees shows "Spells  142 known - new: Thunder Snake
(12:04)". The first look at a wizard only writes its file. Nothing is
clicked, typed or spent. Three settings (Settings > NEW SPELLS AND SPELL
QUESTS), all off - leave them off for now:
	- deckadd (put new spells in the deck): on, a new spell is also announced
	  (a tray tip and the Discord alert - add it to a deck yourself); putting
	  it in the deck isn't built: it needs the deck page's windows.
	- trainspells (spend training points at the trainers, by a plan per
	  school): not built - needs the training points and the trainer's
	  window read from the game; on, debug.log says so once.
	- spellquests (take and do spell quests): not built - needs to know what
	  marks a spell quest and the quest book's windows; on, debug.log says so
	  once. The walker does the TRACKED quest as ever; NPCs offering a quest
	  with a '!' aren't talked to (only a '?').
	The training plan: trainplans.txt (a draft - every spell name, trainer,
	level and cost in it written from memory of the wikis, none checked in
	the game yet: each line says checked 0). The names must be the game's own
	display names. Keep your own copy in learned\trainplans.txt (updates
	replace trainplans.txt, never learned\). See what it would train next,
	with the bot (its helper) running:
	      python vision\spellplan.py --school storm --level 20 --tp 2 --live
	  (--fresh: the spellbook read now - the helper refuses it unless its
	  battle recorder rules a battle out; add --ob only when you're sure the
	  wizard is out of battle. Or --book book.txt --quests quests.txt for
	  saved answers). It also checks the file and names the plan's spells
	  your wizard doesn't know yet.
	The helper's answers, in a browser while the bot runs (read-only):
	  http://127.0.0.1:47128/book (?fresh=1 read now - refused unless the
	  battle recorder rules a battle out; &ob=1 too says you're out of
	  battle: only when you are; &kinds=1 each spell's kind and value) -
	  every spell known, and the treasure cards;
	  http://127.0.0.1:47128/quests - every quest you have, the tracked one
	  marked, each with all the properties the game keeps for it (to find
	  what marks a spell quest). From the command line:
	      python vision\deckmem.py --book
	      python vision\questmem.py --all
	To help build the rest, send: the /quests answer with a spell quest open
	(and say which one it is); python vision\reflect.py --class WizQuestData
	--class WizGameStats --grep "rain|Level" --out spells.txt; and with each
	window open - the quest book, a trainer's window (X at a professor), the
	deck page - python vision\bagmem.py --tree --all --out <name>.txt. Never
	click anything with Crowns on it: training points are never bought.
The Network tab (Settings > NETWORK - off till you switch it on, on each PC):
every bot on your home network - its PC, version, wizard, zone, on/off, Play
for me, what it's doing, health, mana, deaths. Pick one: its last 80 log lines
and a picture of its game (only while Wizard101 is the window in front there -
nothing else on its screen is sent), every 6 s. Its buttons turn that bot on
or off, switch its Play for me off, or restart it - only between bots with the
same network PIN (netpin, not 0); Play for me can't be switched on from the
network (only at that PC: its button). Windows asks once on each PC to let Python
through its firewall: allow it on Private networks. Both PCs' clocks have to
be right (2 minutes apart at most). debug.log: "Network: ...".
Updating by itself (Settings > UPDATES, autoupdate - on, every 10 minutes): the
bot looks for a newer release every that many minutes and downloads it while
it plays on; then it closes itself for it - never closed under it - once it's
out of battle, nothing's loading or logging in, no dungeon run or recording is
under way and you've left the keyboard and mouse alone a minute (Play for me:
no wait), and it's installed with no question and no window. The bot starts
again as it was: on, off or in standby, Play for me, walking (F8),
auto-reconnect and Learn every card as they were (not if you closed it
meanwhile). A version that won't install (a file in use) is put back and tried
3 times, then left to the Updates button. 0 = only when you click.
debug.log: "Updates: ..."; updater.log: "auto: ...".

Party (Settings > PARTY; tray menu Party...): up to 4 wizards, one per PC on the
same home network. One is the Leader - it quests as now, and stops while a
follower is far (partywaitdist), in another zone, loading or not ready, for
partywaitmax s at most. The others are Followers - instead of their own quest
they walk to the leader (stopping partynear from it), into its battles (where it
stood when the battle started), and through the door it took (its last spot in
the zone, then on the way it was going). The tray menu's Party... opens the
party window (in the middle of the screen the mouse is on - where you clicked
the tray icon -, in front of the game, always on top, with a tray tip; open
already: brought to the front, onto that screen; debug.log: "Tray: Party...
picked", then "Party: ..." - each step, where the window is and whether it's in
front): this wizard's name in the party (its in-game name is best - party.ini's,
else the one the bot has learned, else this PC's name is filled in), its role
(Off / Leader / Follower - the same setting as Settings > PARTY's), the leader
PC's address (a follower's only: the leader PC's name or IP - the window shows
this PC's own IP address, to type on the followers) and its part in a party
battle (Settings > PARTY's too). OK keeps the name and the address in party.ini
and the settings in PlayerStats.txt, used at once (no restart); Cancel keeps
nothing. The leader's PC asks once to let Python through Windows' firewall -
allow it on Private networks (the home network has to be set to Private). The
bots share where each wizard is and what it's doing, and each one's battle part,
its wizard's name, school and hits. Nothing one sends makes another press
anything: a blader's boosts go to the hitter's plate as its own screen shows it,
found by the name the game's own log gives for its side. Still to come: teleport
to friend when the leader is somewhere a door doesn't lead (the follower waits
and says so - below).
	- Doors and teleports (v1.0.0): the leader's helper tells a door the leader
	  walked through from a teleport (End, Home, a sigil, a potion run, a
	  friend's teleport - it stood still before its zone changed) and keeps its
	  last 3 doors, so a follower a zone or two behind walks door after door.
	  That guess isn't checked in the game yet, so a follower still walks to
	  where the leader teleported from ("Party: the helper says <leader>
	  teleported from here ... - walking to its spot all the same" in
	  debug.log) unless Settings' "...a follower trusts the helper's teleport
	  guess" (partytpdoors, off by default) is on. A door that hasn't taken the
	  follower in 3 tries is given up till its zone changes, or for 6 minutes
	  (a try a battle cut short isn't counted; it walked to it and pushed for
	  good before). Wherever no door leads - the leader teleported (with
	  partytpdoors on), or its door was given up - the follower
	  stands where it is and says so: "party: can't follow - <why> - waiting
	  here" on the dashboard, "Party: can't follow <leader> - <why>" in
	  debug.log once a wait, a Discord alert after 5 minutes of it. The leader
	  is told and doesn't wait for it ("Party: <name> can't follow (<why>) -
	  walking on without them till they're near again"). While the leader is
	  loading the follower waits ("party: waiting - <leader> is loading"). Five
	  stuck tries on the way: it waits 30 s, then tries again - at once in a new
	  zone or with the leader near (it walked 3 s, stopped 1 s, for good
	  before). The helper's log has a line at each zone change ("party: A -> B:
	  walked through a door - moved 1234 in the last 1.2 s", or "a teleport (it
	  stood still)"), and debug.log says when teleporting to the leader would
	  be the way ("Party: teleporting to <wizard> would be the way now ...") -
	  the teleport itself isn't in yet: the Friends list's clicks need its
	  window names from the game. partywaitmax 0: the leader never waits (it
	  waited for good, though the setting said 0 = no waiting).
	- Your own plate in a party battle: found by your wizard's name (learned
	  from a battle with no other wizard on your side - the game's log; one
	  such battle first), read off the plates along the bottom.
	- Battle roles (Settings > PARTY, "...in a party battle this wizard is
	  the"): Hitter plays as now. Blader puts its blades on the party's hitter
	  (the wizard set to Hitter - the leader's first -, else the leader), its
	  traps on the enemy the hitter goes for (the least health), casts them
	  again after each of the hitter's hits (once that round's out, by the
	  game's log), Tower Shield on the hitter, and hits only for a kill or with
	  nothing else to do. Healer heals whichever of you is lowest under 'Heal
	  under this %' (its plate read like yours), shields them, else boosts as a
	  blader. Your school's own blade, trap and bubble only go on a hitter of
	  your school; a support's aura isn't cast. One school's wizard its own
	  part: <school>.partybattle:2 in PlayerStats.txt. Not sure (the party off,
	  no hitter on your side heard from in 5 s, its plate not read, dual mode):
	  it hits, as ever - debug.log says why once a battle.
	- The party's hit round (Settings > PARTY, "...a blader or healer times
	  its boosts to the hit" - partyhitround, off; new, not tried in the game
	  yet): the hitter says which round its planned hit goes out in (the
	  earliest its pips allow) and each wizard its seat (the cast order of
	  your side); a blader's or healer's blades and traps wait till the hit is
	  due - that round when it casts before the hitter, else the round before -
	  "party hit round: Ned's hit is due in round 6 ... held till round 5". An
	  older bot says neither: boosts go on as before.
	- The leader's orders (Settings > PARTY, "...the leader plans the team's
	  round" - partyorders, off; new, not tried in the game yet; on every PC
	  of the party, and planner on the leader's): each follower's bot sends
	  the hand its helper read from the game's memory (its cards, pips and
	  health - read only, nothing new read) to the leader's; the leader's
	  planner tries the whole team's round in the battle simulator with those
	  hands (its round takes about 1.5 s instead of 0.3) and sends each
	  follower the card it would have it play. The follower waits up to 3 s
	  in its round for it and writes it to debug.log - "Plan: the leader
	  would have you play Stormblade (won 80%, 12 tries) [tid 104] - the
	  leader's plan, advice only ..." - then plays its own way: nothing is
	  cast from it (that needs planner:2's cast by memory, not built); the
	  battle recorder keeps the line with what was played. A follower whose
	  hand wasn't in when the leader planned is played its role's way; a
	  round the leader doesn't plan (a kill, a defence, a heal, its bot off)
	  is told to the followers at once; one with no order (the leader slower,
	  an older bot, its setting off) plays its own way as ever - after two
	  rounds in a row with none it stops waiting that battle, after six
	  (across battles) till an order comes. A blader or healer leader plans
	  too, in a round a follower's hand is in (not in one it heals or shields
	  in).
	- A heal on an ally that went out without asking who: one whose learned
	  text says it heals all of you is kept as <school>.healNtarget:2 (still
	  used for an ally); one that heals only you as :0, not tried on an ally
	  again (set :2 yourself for a heal picture you cut).
	- Alt+2 on a plate (a friend's wizard without the bot): the boosts go there
	  that battle; your own cards are still looked for in your school.
	- Ice's blades and traps are elemental now (they were taken for spirit).

Battles only (Settings > WALKING, "Battles only - never move the wizard";
battlesonly:1 in PlayerStats.txt; the tray menu's "Battles only"): for the
wizards riding another's mount - a 4-player mount whose driver takes the other
three everywhere - or wherever the bot must only fight. Out of battle the bot
moves nothing: quest walking stays off at every start (an update's restart
too) and F8 says why instead of walking; no party following (the party's link
and battle roles - hitter, blader, healer - keep working: that's battle play,
and a battles-only wizard counts as ready, so the leader doesn't wait for it),
no dungeon run (Run on the Dungeons tab says why), no puzzle try, no run to buy
potions (a potion is still drunk when health is low - Ctrl+O doesn't move the
wizard; out of potions it alerts and says why; out of mana with no potion it
alerts and plays on - no hold, the driver takes it into battles all the same),
no mob-loop, lore or afk step, no chat command's walk, sigil or teleport, no
developer loop or clicks. Switching it on stops walking, a dungeon run or a
puzzle try at once. Battles are played exactly as ever - rounds, cards, the
kill check, boosts, the deck for a boss, fleeing, potions - and auto-reconnect,
quick sell, alerts and the log's copy stay as set. Quick sell can't tell a
dungeon the driver takes this wizard into (it knows only the ones the bot went
into itself): keep quick sell off on a passenger. Wizard101 behind another
window is brought to the front once you've left the PC 5 minutes (with "Bring
Wizard101 to the front" on: as soon as a battle round is up), as walking did -
the driver waits for a passenger whose game isn't in front. Turn the bot on
(F6) and it waits for battles and plays them. The dashboard's top line says
"Battles only - waiting for a battle"; debug.log: "Battles only: on - the bot
plays battles and moves nothing else (Settings)" at the start and at each
switch, and "Battles only (Settings): no ..." once for each thing it kept from
moving.

Report a bug (the dashboard's button, top right, or the tray menu): say what
went wrong; Send posts it as an issue on the Wiz-Maxxing repo on GitHub, with
the version, this PC's name, the screen, what the dashboard's STATISTICS and
WHAT IT SEES show and (ticked) the end of debug.log - anything that looks
secret (a Discord webhook, a GitHub token, password=...) blanked out. It uses
the updates' GitHub token, which needs Issues: Read and write as well: on
github.com, Settings > Developer settings > Fine-grained tokens > the
Wiz-Maxxing token > Edit > Repository permissions > Issues: Read and write >
Update (the same token keeps working - nothing to change on the PCs). Closing
the window keeps what you typed until it's sent.

Simple and advanced views: the dashboard's bottom-right button switches it -
simple shows what the bot is doing and seeing (STATISTICS, WHAT IT SEES) with
the main buttons, advanced adds the live log and its buttons.
The Settings window's "All settings" / "Fewer settings" switches it between the
most used settings and all of them (changes not saved yet are kept). Each is
remembered (dashboard.ini [view]); a new install starts simple, one that ran
before starts advanced.

Dashboard (Dashboard.ahk): a window with statistics (battles, deaths - this run
and all time, from the game's log: taken out of a battle without fleeing -
badly stuck and the time lost to being stuck - this run and all time -,
rounds, cards cast per card, passes, discards, kill-check hits, potions, cards
learned),
what the bot sees right now (your health/mana/pips, the hand card by card - ?
for a card it doesn't know, * for a greyed-out one - enemies' health, zone,
the walker) and the log as it's written, coloured by what each line is about
(movement blue, battle orange, waits grey, problems red, potions, reconnect,
party, alerts, the bot itself - the Colours button over the log changes them,
kept in dashboard.ini [logcolors]). Windows+2 or the tray menu shows /
hides it; it opens on a monitor the game isn't on and remembers where you put
it (dashboard.ini). It never takes the focus by itself. Its X (close) stops
the bot; minimise it (or Windows+2) to just put it away. Next to STATISTICS:
the CPU and RAM in use, every second - the bot (with its vision helper), the
game and the whole PC (CPU share of all cores, RAM in use). Its tabs: Bot (all
that), Dungeons (below), Spells (the cards it learned - see "Learned spells"
under New cards; tray menu "Learned spells" opens it there) and Cards: your
hand as the bot read it this round (each card's picture, what it took it for,
its pips - white known, yellow new to it, grey can't cast) with the Learn every
card button, and the enemies' spells (see Enemy spells) - each enemy's school,
rank and health, the chance it hits you, its pips, and under it every spell it
has, likeliest first: the chance it casts it this round, its pips and damage,
the rounds it cast it this battle, and how often it was seen casting it.

The overlay (Settings > THE OVERLAY, "Show the map and the log over the game";
overlay:1 in PlayerStats.txt; the tray menu's "Overlay over the game on/off";
Windows+4, only with Wizard101 in front - elsewhere the key is your other
programs'): the zone map round your wizard (as the dashboard's Map draws it)
and the newest lines of the log (in the dashboard's colours) drawn see-through
over Wizard101 - borderless or windowed, not exclusive full screen - while
Wizard101 is the window in front; it hides as soon as another window is in
front or the game is minimised. Clicks go through it to the game and it never
takes the focus. Windows keeps it out of every screen capture: the bot's own
screen reading can't see it (so it can't confuse the bot), and neither can
your screenshots, recordings or the bug report's pictures - a phone photo
shows it. Needs Windows 10 version 2004 or newer (older: it stays off) and the
vision helper (it draws both). Each time it's switched on, a small pink square
shows for a moment on the game: the bot checking that its screen reading can't
see it; if it can, the overlay stays off. Settings: where each part goes (a
corner, or Off), the map's size, the log's lines, width and text size, the
dark box behind them and how solid it is. dashboard.ini [overlay] (read when
it's switched on): mapdx, mapdy, logdx, logdy move a part by pixels; mapspan
is how much of the zone the map shows (game units across, 4000). Off by
default; not tried in the game yet. debug.log: "Overlay: on", "Overlay:
checked - the bot's screen reading doesn't see it", "Overlay: map not shown -
..." / "Overlay: log not shown - ..." and, when it can't be used, "Overlay:
can't be shown - ..." / "Overlay: stopped - ...".

Settings (the dashboard's Settings button, or the tray menu "Settings..."):
the mouse and the bot's waits, and how it plays its cards, in one window -
point at a setting to see what it does. Save writes them to PlayerStats.txt
(each in its own line, comments kept) and the bot uses them at once - no
restart. Defaults fills in the defaults (Save to use them).
	- The mouse and waits: Wait for me (on/off, and the seconds after you
	  stop), put the mouse back (when the bot takes the mouse - a battle
	  round, a click out of battle - it goes back to where it was once it's
	  done, unless you used the mouse or keys meanwhile), mouse speed, the
	  wait before each click (plus a random bit, so clicks aren't evenly
	  timed), the wait after clicks, before playing a round, after a discard
	  and before looking at the hand again.
	- Health: heal under %, drink a potion under %, flee when out of cards.
	- The backpack: quick sell it when it's full, pets too, after a dungeon
	  too (see Quick sell below); compare gear before selling, and pieces of
	  an Equipment Set too (see Gear below).
	- Card logic: boost first (traps - on the boss, else on the enemy with
	  the most health -, blades, bubble, aura, then
	  the biggest hit it can cast - as always), hit first (the biggest hit it
	  can cast as soon as it has one; boosts only in rounds it has none -
	  quick on weak mobs), or boost first on a boss you picked (Alt+1) and
	  hit first otherwise. Boosts before each hit (0 = all it has), the kill
	  check and its margin, which kinds of cards it plays at all (blades,
	  traps/Feint, bubble, aura, the wand's hit, Tower Shield, Reshuffle - a
	  kind switched off is discarded when "Discard cards it never plays" is
	  on), boosting again after each hit, counting traps in the kill check
	  when you fight alone, saving pips for a finishing hit, and discarding
	  (cards it never plays, blade and trap copies it can't cast again).
	- The overlay: the map and the log see-through over the game - each
	  part's corner (or Off), the map's size, the log's lines, width and text
	  size, the dark box behind them, how solid (see The overlay above).

Smart App Control (Windows 11 - "Smart App Control blocked"): it blocks the
bot's exes (they aren't signed) and can't be told to allow them. Run the bot as
scripts instead: install AutoHotkey v2 from autohotkey.com (Download > v2),
then open ..\Wiz-Maxxing.ahk (not Wiz-Maxxing.exe) - and Setup.ahk for Setup.
Started as a script, everything the bot starts is a script too, by the same
AutoHotkey (the bot, the update check, "Open with Wizard101", Setup's
shortcuts) - never one of the exes. If the vision helper (Python) can't start
there either, cards are found the old way and walking follows the arrow on
screen; the only other way is turning Smart App Control off (Windows Security
> App & browser control - on most PCs it can't be turned back on).

Executables: ..\Wiz-Maxxing.exe starts the bot (Setup.exe puts it in the Start menu
and on the desktop). Autofarmer.exe (and StatsReader.exe here, AutoQuester.exe in
..\AutoQuester) do the same as the .ahk scripts without AutoHotkey installed.
Keep each exe in its folder - it reads the pictures, PlayerStats.txt and
vision\ from there (and AutoQuester\resources\). The vision helper still needs
Python 3 with numpy and Pillow (pip install numpy pillow katsuba - katsuba only
draws the zone's walls on the zone map; Setup.exe installs all three); without
it cards are found the old way (ImageSearch) and the walker follows the arrow on
screen. Rebuild after changing a script:
double-click ..\build.cmd (needs AutoHotkey v2 with its compiler; close the bot first).
Ready-built: the Releases page of the GitHub repo (a zip with everything). Hover the wizard icon in the tray to see what
the walker is doing; debug.log has the battle and walking decisions in order.

Auto-reconnect (Reconnect.ahk, on from the start):
	- Disconnected (e.g. "You have been disconnected due to inactivity." after
	  about 15 minutes idle outside battle, or "Connection Lost!"): it reads
	  the game's own log, finds RECONNECT on the box and clicks it - never
	  QUIT. That logs back in without a password and puts you back where you
	  were. It first clicks with the game left in the background; if the game
	  ignores that it brings the game to the front for a moment and gives
	  focus back. If the character select screen stays up, it clicks Play
	  (with the game brought to the front: that screen ignores background
	  clicks).
	  Failed tries wait longer each time (30 s, 1, 2, 4, then 10 minutes).
	- The game closed (a crash or Quit): it asks whether to start it again
	  (yes after 60 seconds if nobody answers), starts it, types your saved
	  login into the game's login box and goes back in. It only presses Enter
	  once it can read your username back in the login box (an OCR slip or
	  two allowed in a longer one), and stops for good if the game turns the
	  login down.
	- Stuck on a loading screen (hungload, Settings: 5 minutes, 0 = never): a
	  zone change the game's log says began that long ago, nothing but its
	  memory notes written for 3 minutes, Wizard101 in front and neither the
	  spellbook nor a battle round shown since: it asks (yes after 60 seconds
	  if nobody answers), closes Wizard101 and starts it again as above.
	  debug.log: "Reconnect: the game has been on a loading screen N minutes".
	- "Client is out of date" after maintenance: it starts the launcher so it
	  can patch (it fills in the launcher's login too - not tried yet).
	Tray menu: "Auto-reconnect on/off", and "Set Wizard101 login..." to save
	your username and password for when the game has to be started again.
	The login is kept encrypted in Windows Credential Manager as
	"Wizard101Bot" (Control Panel > Credential Manager > Windows Credentials
	to see or remove it), never in a file and never in debug.log. Without
	it, only the RECONNECT part works. debug.log lines start "Reconnect:".

Window size / UI size (any resolution):
The game draws its buttons and cards bigger or smaller depending on the
window size / resolution, the Windows display scaling and Options > UI Size,
and a picture only matches at the size it was cut at. Pictures are cut at a
few sizes:
	resources\, storm\, ...  the main set: 1920x1080 window, 100% scaling,
	                         UI Size Small (UI scale 1)
	ui1.265\                 1920x1200 window at 100% scaling (UI 1.265x):
	                         Storm and Myth cards, Pass, the spellbook, the
	                         name plate, the school icons (see its README)
At any other size the bot makes its own set (PicScale.ahk): in the first
battle round at that size it reads the Pass and Flee buttons (OCR) to measure
the UI scale, checks it by making the Pass button at sizes around that, then
resizes every picture it needs from the sharpest cut set into
generated\ui<scale>\ (debug.log: "UI size: ..." and "made ..."). That first
round takes ~10 s longer; the made set is kept, so later rounds and later
runs at that size start straight away. Seen working at 2560x1440 borderless
(UI 1.14). Made pictures are found with a little more colour tolerance and
remade by themselves when a cut picture changes; delete generated\ to make
them all again. Shrinking works best, so cut new pictures at the biggest size
you play at (a ui<scale> folder: the bot finds those by itself).
The script uses whichever set's Pass button or spellbook it can see (debug.log
says "Pictures: ..."), and sizes its search areas to match. A card with no
picture in any set just counts as not in hand (debug.log says which).

Sometimes we just need a break from all that farming in wizard101
or maybe you've been questing and are just sick of it, i have just
the solution for you. I thought I'd take some time out of my life
to create a program which basically plays the game for me. With this
program, I've been able to read so many books AND get Darkmoor gear
easily. Sound Good? You say you don't like to read? Well just endure
this much and then you'll be overpowered in Wizard101 in no time.

To begin install Autohotkey from https://www.autohotkey.com then 
open the AutoFarmer.ahk file. Once its open, you should be able to see 
it in the tab menu on the Taskbar. You can then activate the script 
by pressing the key combo "Windows+1".

Now whenever you join a battle the program will take over your
mouse and create a strategy based on the cards you have. Please
note however it only has a select few cards out of the many that 
are in Wizard101. so far it mainly uses hit all spells, blades,
traps, feints, auras, enchants, towers, and bubbles

This program prioritizes cards based on priority. The priority 
chart goes in this order, feint, trap, blade, aura, hit, tower,
reshuffle, and if no other move can be found, it'll pass. So what
this means is that if there's a blade and a tower in hand, it'll use
the blade first because it has a higher priority.

Now this program isn't smart enough to figure out where a 
boss might be(If it can't do that it can't trap, feint or convert!), 
so I've added a hotkey that allows you to manually set it, the 
key combo is Alt+1, A message box will appear instructing 
the player to click where the boss is. Please be careful where you click
if you click in the wrong spot, it'll remember it and won't work correctly.

Occasionally the program chooses a ally to blade which the player
using the program disagrees with, I've added a hotkey to 
solve this issue as well. Use the key combo Alt+2 to 
manually set the "Hammers" location. Works exactly like the 
boss location.

Saving pips (pipsave, pipsavehealth in PlayerStats.txt):
When nothing in hand ends the battle this round, but a hit that would end it
- an AoE that kills every enemy, or a hit that kills the last one - costs
more pips than you have, the bot saves up for it (up to pipsave rounds,
default 3): no other hit spends pips meanwhile (the wand's free hit, blades,
traps, healing and Pass still go), and the kill check casts it the round it's
affordable. Not while your health is under pipsavehealth % (default 50); it
gives up for the battle if the pips don't come. debug.log and the dashboard
say "saving pips for ...".

Enemy spells (enemyspells:1 - Settings, HEALTH): each round the bot works out
what each enemy will most likely cast and the chance their hits kill you this
round - in debug.log ("enemy spells: ..."), on the dashboard (Threat) and,
each enemy's every spell with its chance, on the dashboard's Cards tab.
	- Who's fighting and what each cast comes from the game's own log
	  (Bin\WizardClient.log, only read): it names every slot of the circle
	  and each caster's spell each round, passes too.
	- Each creature's spells, pips and damage come from the Wizard101 wiki on
	  Fandom (Wizard101 Central's blocks bots), looked up once and kept in
	  wiki\cache.json for a month; a creature's first battle may show
	  "looking it up". Its pips are guessed from the round (mobs pick a card
	  at random and pass if they can't afford it, so they save up).
	- Every enemy cast seen is counted for its creature (wiki\casts.json),
	  so the odds sharpen with every battle against it.
	- defendat (30): when the chance their hits kill you is that % or more
	  and no hit in hand ends the battle (the kill check goes first), a heal
	  on yourself, else Tower Shield, goes before anything else. 0 = only
	  show the odds. A hit at one target is counted at you 1 in however many
	  wizards are on your side.

Battle recorder (battlerec:1 - Settings, HOW IT PLAYS ITS CARDS): every battle,
the ones you play too, is written down so the bot can learn battles later.
	- From the game's own log (Bin\WizardClient.log, only read): every
	  caster's spell, its targets, damage, crits, blades, traps and shields
	  added and used, health after each round, deaths and the result.
	- From the game's memory (read only): your hand each round (the cards'
	  ids, enchants, treasure / item cards), your pips, the enemies' rank,
	  school, boss flag and health, and the deck you wear.
	- From the bot: which rule picked each card and why (its log lines for
	  the round), and whether you or the bot played the round.
	- Kept in learned\battles\ (one file a day, about 3-6 MB a day of play;
	  months older than two are zipped; it pauses at 1 GB). Updates keep it;
	  it is never sent anywhere. Read it with:
	      python vision\battlereport.py          (the last 7 days)
	      python vision\battlereport.py --days 30 --enemy "Bonestriker"
	- It never slows a round: the bot hands its lines over after its last
	  click, and the helper reads nothing extra while the bot plays a round.

Enchants (Strong, Giant, Monstrous, Gargantuan, Colossal, Epic - treasure cards
too) go on the hit about to be cast, a learned hit in no slot as well; an
enchant or a treasure card is never discarded.

Kill check:
At the start of every round the program reads each enemy's health off the
nameplates at the top of the screen and works out how much damage each hit
in your hand would do. If one of them kills every enemy it casts it right
away (the cheapest one that works - the wand's free hit first - and without
the enchant if it doesn't need it) instead of putting up more blades and
traps. A hit on one enemy (<school>.hitNtarget:1) only counts when one enemy
is left. When one is cast, it goes where it does the most - the least of its
damage and the enemy's health: a big hit isn't thrown at an enemy nearly dead
while another is at full; of those it kills, the healthiest; none, the
weakest. debug.log says after the kill check what it counts on from each hit
in hand ("your hits now: ..."). If it can't read the
health, or no hit is enough yet, it plays exactly like before.
	- Draw treasure cards for an enchant that kills (the Settings window, off
	  unless you switch it on): when no hit ends the battle but one would with
	  an enchant on it (any - Strong's +100 counted, drawneed) and there's none
	  in hand, it draws from your treasure-card deck (DRAW, between Pass and
	  Flee) till an enchant comes, then runs the kill check again. Draw is
	  greyed out with 7 cards, so one card it knows is discarded first - never
	  a treasure card, a card it doesn't know or a greyed one, the hit, an
	  enchant, or one you said never to discard. At most drawround (3) draws a
	  round, drawmax (6) a battle; Draw greyed out with room in hand (no treasure
	  cards left): not again for 30 minutes. Never with "Crown" read by the
	  buttons, nor while you play. debug.log: "draw: ...".
	- Enchants: Epic, Colossal, Gargantuan, Monstrous, Giant and Strong (the
	  damage each adds: enchant4, 3, 2, 7, 6, 5 in PlayerStats.txt) - the best
	  in hand goes on the hit. Monstrous, Giant and Strong are learned from the
	  card ("+175 to 1 spell") the first time one's in hand.
	- Turn on Options > Gameplay Options > "2D Combat Display" in Wizard101,
	  that's what shows the enemy nameplates.
	- The health numbers (the enemies' and your own) are read by the vision
	  helper by their digits' shape - the cut pictures in ui1.144\platedigits
	  (one of each digit and "/", cut at 1440p; they read other sizes too) -
	  and only when that can't read them for sure by Windows' OCR, which misses
	  the red numbers more often than not at 1440p. debug.log: "own health:
	  couldn't read it for sure (by shape: <why>)".
	- Needs Windows 10 or 11 (it uses the OCR built into Windows).
	- Open PlayerStats.txt and set your damage %, and the damage of the hit
	  spells in your deck. The numbers in there are only guesses.
	- When you set the boss with Alt+1, click the boss's nameplate at the top
	  of the screen. That way the program knows which enemy your traps and
	  feints are on. In a boss fight the kill check stays off until it can
	  find the boss's nameplate.
	- Statistic mode (Alt+S) shows a box beside the game window with the
	  health it read and the damage it thinks each hit will do, handy for
	  checking your settings. It needs room beside the window (it's never
	  drawn over the game); Windows+2 in developer mode shows the same info.
	- It plays it safe rather than wasting a hit: it assumes no crits, adds a
	  safety margin, only counts blades the program put on your own wizard,
	  only counts traps if you set solotraps to 1 in PlayerStats.txt (only do
	  that if you fight alone) - and then only on the enemy they went on
	  (the boss you picked, else the one with the most health) -, and never
	  counts bubbles (anyone's global replaces yours).
	- It's switched off in Dual mode, since both windows share what's been
	  cast and it can't tell what has landed yet.

Blades and traps by damage school (v0.50.0):
A hit can do damage of more than one school - Hydra hits with fire, ice and
storm heads. With the game's memory (navmem:1, read-only, as the cards
above) the bot knows each hit's heads and what each blade and trap in hand
boosts, and plays them by that:
	- The hit it boosts for (the planned hit) is the one that would deal the
	  most this round with the blades and traps in hand and those already on,
	  against the enemies left: an all-enemies hit counts on each enemy (no
	  more than its health), a one-enemy hit on one. hit4 only on a boss you
	  picked (Alt+1), only a hit you can pay for now (or the one pips are saved
	  for), and the kill check's own hit when it kills now. That hit is also
	  the one cast first when it's time to hit.
	- It looks for the blades and traps of every school the planned hit and
	  the other hits in hand need - not just your own school's: a Balance
	  wizard's Hydra gets the Elemental Blade, Balanceblade, and a pet's
	  Stormblade (storm head only). Balanceblade, Bladestorm, Hex and Feint
	  boost every school. On a hit of two or more schools it puts up the one
	  that adds the most first: Elemental Blade (all three heads) before
	  Balanceblade, before a Storm Blade (one head).
	- The kill check counts each head with only the blades, traps and aura
	  that fit it; an enchant on a hit of several heads is counted once, on the
	  head where it adds the least (the safe side).
	- A hit uses up only the boosts that fit its heads: a Power Nova leaves an
	  Elemental Blade on for the next Hydra.
	- The same blade from different places stacks: a deck Stormblade and a
	  pet's (or a treasure card's) both go on before one hit, and both count.
	- A pet's or gear's card (an item card) is never sharpened, made potent or
	  enchanted - the game doesn't allow it. The wand's own card is never
	  enchanted either.
	- The wand's free hit waits while it would use up a blade or trap meant
	  for the planned hit.
	- A blade picture that matches but isn't in the game's hand is a false
	  match: not used (debug.log says so once).
	- In a party battle the hitter tells its supports its planned hit's
	  schools: a Balance blader puts its pet's Stormblade on a Storm hitter, or
	  on a Balance hitter planning Hydra. A blader's blade that fits neither
	  the hitter's planned hit nor the blader's own school is thrown away -
	  only once the hitter has said which schools it plans for and is sure of
	  them (never a treasure card, never one you said never to discard). A
	  blade that doesn't fit the hitter's last hit, or that went on after it,
	  stays counted as on it.
	- New blades and traps learned from the game go in the slot their schools
	  say (resources\elementalblade, storm\blade, resources\blade3...).
	- A blade or trap the game has in hand that no picture finds (its slot
	  picture missing, an 8x8 placeholder, or one that matches only some
	  copies) is still played: the bot clicks it where it is - the card's box
	  in the hand, laid on the game's cards left to right - with the same
	  rules (a Sharpen / Potent, never on a pet's card, each copy once).
	  Only when that's sure: the hand settled, as many boxes as cards, no box
	  whose picture says another kind of card than the game has there, and
	  the card's own box not known as another card. debug.log: "boosts
	  searched for ...: blade3 (no picture)", "blade3: no picture found it -
	  the game's Balanceblade is card 2 of 6 in hand: cast at its box ...",
	  or "... not cast: <why>".
	- A copy that already carries a Sharpen or Potent (only the game's hand
	  finds one) never gets a second: a plain copy is sharpened first; that
	  one's cast as it is and counted with the enchantment it carries.
	- When the blade (or trap) kept for a Hydra can't be cast after all (its
	  box can't be sure), the one held back for it goes instead the same
	  round - even one before it in the battle's order (a pet's Stormblade).
	- A slot picture that doesn't find the game's card on two looks running
	  (the same box, two different looks at the hand) is replaced by the
	  card's own picture (the old one kept in backups\), so the pictures
	  work again, the game's memory read or not - never by a learned card
	  the game hasn't named so (or the learner is still checking), and
	  never over the slot's own card's picture. When the slot already has
	  the card's own picture, debug.log says why it still misses.
	- The pictures for your UI size: the set cut at that size (within 1%)
	  comes first, then the sets cut bigger (smallest first - shrinking keeps
	  detail), then the smaller ones (vision.py Library.masters). Till now a
	  set up to 3% smaller came first: at 1440p (UI 1.144) Balanceblade,
	  Locust Swarm and Helping Hands were looked for with ui1.121's pictures
	  enlarged 2%, and about half the Balanceblades weren't found.
	- Traps (Hex, Feint, Elemental and school traps - those that fit the
	  planned hit's schools, one a round) go on the boss you pick with Alt+1;
	  as a party battle's blader or healer, on the enemy the hitter goes
	  for; else - every battle (you asked, 2026-10-24) - on the enemy with
	  the most health, read off the plates as the kill check reads them. A
	  tie, or health that can't be read: where your planned hit goes (the
	  leftmost of them). debug.log: "trap3 on enemy 2 of 3 (3100/3100
	  health - the most) ...". The kill check counts them only on the enemy
	  they went on, and only with solotraps:1 ("I fight alone (count my
	  traps)" in Settings) - found again each round by its plate and its
	  most health; a trap on another enemy starts the count afresh, and one
	  whose enemy is gone goes with it.
	- Without the game's memory (navmem:0, an older helper, no helper) it
	  plays as before, by the pictures and PlayerStats.txt. Hits of more than
	  one school can then be typed in PlayerStats.txt, one line a head:
	  balance.hit3fire:230, balance.hit3ice:230, balance.hit3storm:230, with
	  balance.hit3 their sum (690) - heads that don't add up to it aren't
	  used. The card learner writes them for a learned hit.
	  Another school's blade or trap counts at blade.<school> / trap.<school>
	  (e.g. blade.storm:35 - storm.blade is your Storm wizard's own), else at
	  blade / trap.
	- debug.log: "plan: ...", "boosts searched for ...", "used up by ...;
	  still on: ...", "wand not cast: ...", and the hits' heads after "your
	  hits now:".

Stats reader (any window size, any wizard):
The kill check needs your wizard's Damage and Armor Piercing for the school it
hits with. They're read off the Spellbook's stats pages (it presses C, which
opens the book at the character page, reads Damage, Accuracy, Critical, Block
and Armor Piercing for that school, and closes the book) and kept in
PlayerStats.txt as <school>.damage, <school>.pierce, ... - one set per
school, with <school>.charid saying which character they're from. The plain
damage / pierce lines near the top are only used for a school with none.
	- AutoFarmer does it by itself: when it fights with a wizard whose
	  school has no stats yet, or whose stats are from another character of
	  that school, it reads them at the next quiet moment out of battle -
	  with Wizard101 in front and your hands off the mouse and keyboard for
	  5 s (it stops at once if you touch them, if the game loses focus or a
	  battle starts). At most once every 30 minutes per character.
	  debug.log: "Stats: ...". It knows each character's school from the
	  badge by its name plate in battle (resources\characters.txt) - and
	  when a battle shows no badge it knows (your plate in another slot can
	  show none), it goes by that: the school this character fought as
	  before, with your own plate (found by your name) as the hitter's.
	  debug.log: "no school badge found on the name plates - ..."
	- Tray menu "Read wizard stats now" (or double-click StatsReader.ahk;
	  while AutoFarmer runs, that just asks AutoFarmer to do it): read them
	  again, e.g. after changing gear.
	- StatsReader.ahk on its own (AutoFarmer not running): works out the UI
	  size and which character is logged in by itself; for a character
	  AutoFarmer has never seen fight, it takes the school with clearly the
	  highest damage. School at the top of StatsReader.ahk forces one.
Numbers are read with digit pictures resized to the UI size, checked with
Windows OCR; one that can't be read for sure keeps its old value, so it never
writes a wrong number (StatsReader.log / debug.log list every reading, and
pictures of the two pages go to %TEMP%\Wizard101 bot rounds\stats_*.bmp).

New cards (CardLearn.ahk - needs the Python vision helper):
Every round the bot reads the hand card by card. Only a box that looks like a
card is used (the edge between its picture and its text, the yellow pip digit,
no big white patch, a type icon the helper knows): the deck's back ("Cards 6 of
13"), the round's timer, the floor or a popup over the hand are never learned
or discarded (vision\vision.log lists each box it turned down, and why). A
card it has no picture for, shown in colour (a greyed-out one - not enough
pips - waits until it's castable), is learned:
	- its type from the icon at the bottom right of its picture
	  (ui1.144\cardicons: damage = hits one enemy, aoe = hits all, heal,
	  ward = a shield or a trap, charm = a blade, manip), its pip cost from
	  the yellow digit (ui1.144\carddigits and vision\digits - a digit read
	  is trusted over the pips you had), its kind and numbers from its text
	  (OCR at three sizes, two must agree: "65-105" -> 65; a misread range
	  like "805-345" is put right when only one fix makes sense)
	- kinds it knows: a hit on one enemy or all (with a part over time:
	  only the part up front counts), a heal, a shield (-50%), a trap (+N%
	  with the shield icon), a blade (+N% with the charm icon), an aura
	  (+N% to all spells, or your school's, for some rounds), a bubble (a
	  global spell - all of the battle, e.g. +25% Ice damage) - and kinds it
	  doesn't play: damage over time only, stun, dispel, prism (convert),
	  "Clear", X-pip spells, weaknesses. Those are kept and recognised, never
	  cast; one it can't be sure of is kept as "unsure" till it's seen at a
	  size where it reads
	- it's saved as <picture set>\learned\<id>.card.png (the whole card, for
	  you to look at) and .png (the picture the bot looks for)
	- it goes into a free slot (one whose picture was never cut), so the
	  battle code uses it like the hand-cut cards: a hit -> <school>\hit1-3,
	  only where they stay weakest to strongest (the battle casts hit3 first;
	  hit4 only for one stronger than all, as hit4 is only cast on bosses), no
	  pips -> wand, heal -> heal1/heal2, shield -> resources\tower, a trap ->
	  resources\trap3 (only "+N% to next spell" at the % PlayerStats.txt has
	  for trap3), an aura -> <school>\aura (only at its aura %), a blade as
	  before (blade3, or your school's blade, at their %), a bubble ->
	  <school>\bubble (one the game's memory says boosts your school's
	  damage, or one you set to Bubble on the Spells tab), an absorb ->
	  resources\absorb, a Sharpened Blade / Potent Trap -> resources\sharpen
	  / potent (at least the sharpen: / potent: % PlayerStats.txt has), your
	  school's prism -> <school>\convert (the game's memory says it's your
	  school's, or you set it to Prism on the Spells tab). Its numbers
	  go into PlayerStats.txt (<school>.hitN, hitNpips, hitNtarget, ...) under
	  "Cards the bot learned by itself". The damage is read at three sizes
	  and two must agree (and make sense, low-high); if not it's written as 0,
	  so the kill check never counts on it - fix the number by hand then.
	- cards are learned per school (each wizard's own), shields for all
	- seen at another UI size, a learned card is cut again at that size
	- no free slot or an unknown type: it's only kept and recognised from then
	  on (and tried for a slot again whenever it's in hand)
From the game's memory (vision\handmem.py, the helper's /cards - read-only
like the walker's: nothing in the game is ever written, no key or click):
in a battle's planning phase, once the cards on screen are exactly your
hand, the bot has each card's real name, school, kind, pips (X pips too),
numbers (a hit's least damage, every head added; a heal; a %), whether it's
a treasure or item card and its enchantment - and your pips of each kind.
When there are as many as the helper's card boxes, card 1 (from the left) is
box 1 and so on: a new card is learned with all that - no OCR, nothing
guessed (Sure 100%, "read from the game"; flags mem, game=<its name>) - its
picture still cut as above; a card it knows by its picture gets the game's
name (if you gave it none), kind, number and pips put right, but never what
you set yourself on the Spells tab. An enchanted card it doesn't know by its
picture waits till it shows up plain. Your pips each round are the game's
count then (generic 1, power and your school's pips 2, another school's 1),
the pip row under your name still read each round, for the log and in case the game can't be read (debug.log:
"pips=N (from the game; the pip row read M)" when they differ). navmem:0 in
PlayerStats.txt switches it off with the walker's memory reading.
Cards and plates by the game's memory (v1.0.0 work, not tried in the game
yet): the helper also gives each card's box in the game's window (/cards)
and each name plate's box (/battle), read from the memory the same way.
	- Read and used now, the screen's reading kept for when the memory
	  can't be read: your school (the badge by your plate can be a
	  teammate's in a party battle - debug.log "your school: the game's
	  memory says ..."), your own health ("own health: N/M (P%) - the
	  game's memory"), the enemies' health on the plates the screen shows
	  ("enemies' health from the game's memory: ..." - not a boss whose
	  health the game hides, nor with an Alt+1 boss), your party's
	  wizards' health and the party hitter's school. Only while one game
	  window is open: with two or
	  more the memory read can be the other window's wizard (debug.log
	  "Vision: N game window(s) found ..."), so all of it - and
	  memclicks below - is taken off the screen as before.
	- Clicks where the memory has them: only with memclicks:1 (Settings,
	  HOW IT PLAYS ITS CARDS - "Click cards and plates where the game's
	  memory has them", off). Every round the memory's card boxes are
	  compared with the ones the helper sees on the screen - log only,
	  whatever the setting: debug.log "Memory card boxes (log only): N
	  card(s), the largest gap ... they line up / they DON'T line up".
	  Once they line up 3 looks in a row at a window size, memclicks:1
	  casts the cards and enchants where the memory has them there (the
	  pictures the fallback); your plate when no picture finds it and the
	  enemies' plates are clicked where the memory has them too, and the
	  kill check then reads no health off the screen (also with its OCR
	  off - healthocr:0). Since v1.8.0 the blade and trap copies the bot
	  can't cast again (discardspent - see Discarding below) are
	  right-clicked away only at a window size where the boxes have lined
	  up 3 looks in a row, memclicks on or off.
	- Fixed whatever the setting: your plate not found no longer sends a
	  heal or Tower Shield's click onto the card just clicked (not cast -
	  said in debug.log); nor a blade's or Reshuffle's onto nowhere when
	  the hitter's school is known (the memory's, or the one this
	  character fought as before) but no plate was found - the round's
	  hits are still cast, the blades aren't ("the hitter's name plate
	  wasn't found this round"); with memclicks:1 a card that already
	  carries an enchantment is never sharpened, made potent or enchanted
	  again (a plain copy is taken first); the memory's hand is no longer
	  thrown away when the badge by your plate is another school's (one
	  game running); a spare blade only the memory found is discarded, at
	  its card box; a hit the game says is for one enemy gets its target
	  clicked without a hitNtarget:1 key.
	- Each cast check logs the round's phase from the memory beside the
	  Pass picture's verdict ("cast check (memory, log only)") - nothing
	  acts on it yet. To watch it yourself in a battle:
	      python vision\handmem.py --phase -n 100 -i 0.1
	  (a line every tenth of a second while you click a card, its target,
	  and the round plays).
Every battle spell type of the game's own list (its spells' type: Damage,
AOE, Steal, Heal, Charm, Curse, Ward, Jinx, Aura, AuraNegative, Global,
Manipulation, Enchantment, Mutate, Polymorph, Shadow) has a kind on the
Spells tab, read from the game's memory by what the card does:
	- played: a hit (Steal ones too), a heal, a shield, an absorb (soaks N
	  damage - Spirit Armor, Ice Armor, Legion Absorb: cast on you on Tower
	  Shield's turns, after it - when the bot defends you, and as the filler
	  when nothing else can go, there only one that costs no pips; usetower,
	  and useabsorb:0 in PlayerStats.txt switches absorbs off), a blade, a
	  trap (the Weaving traps that convert too - Heat Trap - are traps), an
	  aura, a bubble, a negative aura (Attenuate: +N% damage taken on one
	  enemy for 4 rounds - cast at its card box by the game's hand on the
	  enemy the traps go on (the Alt+1 boss, else the one with the most
	  health) before the traps and blades, once in 4 rounds an enemy, only
	  one that adds to the hit planned (a school's Attenuate for that
	  school's damage; usetraps); Starfall and Pathogen aren't played), an
	  enchant, Sharpened Blade and Potent Trap (resources\sharpen / potent),
	  your school's prism (<school>\convert: cast at the boss picked with
	  Alt+1 when the game's memory says it's of your school - it resists
	  your hits; one, then none till a hit of yours has gone out; at its
	  card box when no picture finds it)
	- not played, kept in the list: damage over time, stun, dispel, Clear,
	  a weakness, a curse (an enemy's accuracy or healing down - Black
	  Mantle, Infection), a charm that isn't a blade (spears, Guidance,
	  Guiding Light), another enchantment (Accurate, Aegis, Cloak...), a
	  mutation (Mutate Kraken), a polymorph, a shadow form (Shadow Shrike...),
	  a minion spell (Animate, Mend Minion), a pips spell (Donate Power,
	  Empower), another manipulation (Steal Ward, Taunt, Shift, Mana Burn),
	  Not used. Those are discarded as before (a Reshuffle never)
A kind an older version doesn't know (its cards.txt read by it) is simply
not played there.
Copies of a card shimmer a little, so a learned picture is cut solid from one
copy and the pixels that differ in the next copies turn see-through by
themselves. A pip cost that couldn't be read is guessed as the pips you had
(the card was castable), and brought down whenever it shows up castable with
fewer - a pip digit read off the card is never changed that way.
learned\cards.txt lists everything learned (with its name, if you gave it
one, and its flags: tc = a treasure card, user = set by you, hold = never
discarded...); debug.log: "learned a new card ...".
Put right by itself, once a run, as soon as the vision helper is up and the
bot is out of battle (nothing is ever deleted - it's moved to backups\):
	- every learned card not checked yet is checked like a card in hand; one
	  that isn't a card (the deck's back, the timer, an empty spot - older
	  versions learned some) is moved out of the list, pictures and line, to
	  backups\learned junk\. Its pips are put right from the digit too.
	- a copy of a learned card's picture in a slot that isn't its own is
	  taken out of that slot (what was there before put back, else the copy
	  moved to backups\learned strays\), with that slot's lines in
	  PlayerStats.txt.
Stronger hits (Settings: "Make room for stronger learned hits", learnupgrade,
on): a learned hit 15% or more stronger than the weakest of hit1-3 takes its
place - out of battle only, never in a round. hit1-3 are then kept weakest to
strongest (the battle casts hit3 first), the cheapest one stays when the new
one costs more, and so does your only all-enemies hit when the new one hits
one enemy. Only slots whose damage and pips are in PlayerStats.txt are
moved; X-pip slots (hitNpips:0) and ones you pin with <school>.hitNkeep:1
stay where they are; a treasure card may take a free slot but never pushes
out a deck spell; the new card needs two OCR reads that agreed (or the
number you typed on the Spells tab) and its pips read off it. Before anything
moves, the three slots' pictures (every picture set's) and their
PlayerStats.txt lines are copied to backups\hits <school> <date-time> (<card
id>)\. Forget the new card on the Spells tab, or change its kind, and it's
all put back while the slots still hold what it left there and you haven't
changed their numbers since (otherwise just the new card comes out, and
debug.log names the backup folder). <school>.learnupgrade:0
switches it off for one school. Updates keep the pictures it moved.
Learned spells (the dashboard's Spells tab, or tray menu "Learned spells"):
every card the bot learned, with its kind, school, pips (3? = guessed),
number, how sure it is (Sure), where it's used (or why not), the text it
read, whether it's a treasure card, when and at what size it was learned.
Sure, out of 100%: its kind (40 - read alike twice or the same as its icon;
25 read once), its number (35 - read alike twice; 15 once; a kind with no
number gets all 35) and its pips (25 read off the card or X; 10 guessed).
Read from the game's memory: 100%. What you set yourself counts as sure;
what's still blank doesn't. Under the
picture: why. Sort by Sure (click its heading) to find the ones to check.
Pick one to see its picture. Pick one or more and:
	- Change kind...: what it really is. It's taken out of its slot (a hit
	  that made room for itself puts the hits it moved back) and gets the
	  slot the new kind fits, if one is free. "Not used" keeps it in the list
	  and out of use.
	- Edit...: its name, its number (a hit's least damage, a heal, the % of a
	  blade, trap, shield or aura) and its pips - e.g. a misread number. X
	  for the pips: an X-pip spell (all your pips; its number then its damage
	  a pip) - learned as one by itself when its text says "per pip".
	  Or in the list itself, as in a spreadsheet: double-click a Name, Pips
	  or Value cell and type over it - Tab keeps it and goes right (Shift+Tab
	  left), Enter down (Shift+Enter up); clicking away keeps it too, Esc
	  doesn't. Kind, School and TC are dropdowns: double-click (or Tab
	  onto) one and pick - a click keeps it, or arrows then Enter / Tab.
	  School: the card's own school - Fire, Ice, Storm, Myth, Life, Death,
	  Balance, or Sun (enchants), Star (auras), Moon (polymorphs), Shadow;
	  the card stays in the deck of the wizard it was learned for. TC: no
	  stops the bot taking it for a treasure card again. Kind lists every
	  kind above (29 - "(not played)" in the Change kind menu for the ones
	  the bot never casts). Tab goes Name, Kind, School, Pips, Value,
	  TC. Other cells open the card's picture. A changed cell shows a * till
	  the bot has made the change.
	- Forget: out of the list, its pictures to backups\learned forgotten\. A
	  real card is learned again the next time it's in hand.
	- Never discard: it stays in hand even when the bot doesn't play it.
	- Show picture, Open folder, Moved away... (opens what's in backups\:
	  non-cards, forgotten spells, the hits moved to make room), Refresh.
	The bot makes these changes from its own loop as soon as it's out of
	battle (the status line says when some are waiting); what you set is
	never changed by the learner itself. debug.log: "Spells: ...".
Fleeing: only when completely out of cards - no card in hand (the deck used
up; a hand read where none of the boxes looked like a card doesn't count, and
the game's own hand is used when it can be read) for two rounds running. It
never flees for no hit in hand or for being out of mana (debug.log says so:
"... - not fleeing: only out of cards"). After fleeing it drinks a potion if
it's low on mana (none left: goes and buys some) and tries again.
PlayerStats.txt: fleeon:0 switches it off. debug.log: "fleeing: ...", "after
fleeing: ..."; the dashboard counts them next to Passed.
Learned hits in no slot: the bot casts by slot (hit1-4), and a treasure card
never gets one - so when no hit1-3 can go, it casts the strongest learned hit
in hand you can pay for (e.g. a Sandstorm treasure card), a target for a
one-enemy hit; one that doesn't go isn't tried again that battle till there
are more pips. Not thrown away while no hit1-3 can go. learnedhits:0 in
PlayerStats.txt switches it off.
Discarding in normal battles: every round, after it's read the hand, the bot
right-clicks away the cards it knows it never plays - learned cards of a kind
it doesn't play (stun, dispel, damage over time...) or one more card of a kind
whose slots are full - so the next round draws cards it can use; at most 3 a
round. Its own cards stay (also one it learned again at another UI size: where
the battle's own search finds one of its cards, nothing is discarded), and so
do cards it doesn't know yet and learned ones whose kind it couldn't tell.
Blade and trap copies it can't cast again go too (v1.8.0 - discardspent, on, a
deck's own too: "...and blade and trap copies it can't cast again (untried)"
under "Discard cards it never plays"; new, not tried in the game yet -
LIVE_CHECKS.txt 3.11). With reboost off each blade and trap is cast once a
battle, and once more sharpened (a trap made potent) while a Sharpen (a Potent)
is in hand or still in the worn deck - the helper's last reading of the deck
(/deckkinds), less the sharpened casts so far: not counted down once the bot
drew a treasure card this battle (the cast may have used its Sharpen or
Potent); not known, only one in hand counts. A treasure card's Sharpen or
Potent you drew in a round you played can make it throw a copy too early. Its
other copies in hand are right-clicked away, the weakest first (one with no
enchantment before one with one), up to 3 of one a round, not counted in
discardmax. Only once the vision helper reads the game's hand and the memory's
card boxes have lined up with the screen's 3 looks in a row (see Cards and
plates by the game's memory), as a Hitter (or with the party off), not in dual
mode; with reboost on nothing changes. Without all that a blade goes once both
its casts did, as before - but not with reboost on (v1.9.1), as a Hitter (or
with the party off) and not with Alt+2's pick: the next hit the blade fits
lets both its casts go again, so its copies stay in hand for them (debug.log,
once a battle: "storm/blade: its plain and sharpened casts both went - its
copies kept in hand ..."). A spare Sharpen goes once a sharpened blade was
used and no blade in hand still needs one, reboost or not. The simulator
plays those two rules too (v1.9.0), keeping the copies with reboost on when
the AutoFarmer says it does (v1.9.1). PlayerStats.txt: discardunused:0
switches off the cards it never plays and the blade and trap copies (a blade
whose casts both went - with reboost off -, and a spare Sharpen, still go),
discardmax: how many cards it never plays a round, discardspent:0 keeps the
copies, as v1.7.0 did.
Learned treasure cards are never discarded (that would use them up), nor a
treasure or item card's blade or trap, nor spells set to Never discard on the
Spells tab - but a blade left to the both-casts rule goes as before, and the
copies' rule sees Never discard only on a card the bot's look found by its
picture. debug.log: "Discarded learned card ... - a kind the bot doesn't play:
stun", "Discarded Stormblade - storm/blade: 3 of the deck's copies in hand, 1
cast left this battle ..." and once a battle "spent copies: the worn deck
holds 2 Sharpen and 0 Potent card(s) ...".
Learn every card (the dashboard's Cards tab, or the tray menu): for a deck you made
to be learned - one of every card. Switch it on and start a battle (an easy
one). Each round the bot learns what's in hand, right-clicks away every card
it knows so the next round draws new ones, keeps greyed-out cards it doesn't
know until there are pips to show them in colour, heals if your health is
low, and passes - it casts nothing else. It stops by itself when the deck is
used up (two rounds with an empty hand) or nothing new has come for three
rounds, and says how many it learned; then finish or flee that battle
yourself. debug.log: "learn every card: ...". The hand is read with the
mouse off it (a card under the mouse is drawn zoomed up); if you move the
mouse onto the hand meanwhile, no new card is learned that round.

Keys (the dashboard's Keys tab): every action that has a key - the bot on /
off (F6), walking (F8), the dashboard (Windows+2), the overlay over the game
(Windows+4), restart (Windows+1, Alt+Esc), quit (Windows+Esc), stop recording
(F9), the battle picks (Alt+1 the boss, Alt+2 who your boosts go to, Windows+3
your own plate) and the modes (Alt+E loop, Alt+L lore, Alt+D dual, Alt+C
command, Alt+S statistic, Alt+R response, Windows+Alt+D developer) - with its
key, its default and when it works. Pick one and click Change (or double-click
it), then press the new key, with Ctrl, Alt, Shift or Windows if you like
(8 s; Esc leaves it as it was). Its default and No key (switched off - not for
the bot on / off, quit or stop recording), All to defaults.
Kept in dashboard.ini [hotkeys]. Not taken: keys the bot presses in the game
(W A S D, X, Space, Ctrl+O potions, Ctrl+1-9 Equipment Sets), Cheat Engine's
F13-F24, plain letters, digits and numpad keys (typed in chat), Alt+F4,
Windows' own (Windows+L, D, E, R, G, Tab), the developer's Alt+0 and
Windows+`, a key another action has, and the key a recording going on now
stops with. A default you had already given another action (one new in an
update - the overlay's Windows+4, say) isn't taken from it: the new action
has no key (the Keys tab shows (none)) till one of the two is changed.

Potions (Potions.ahk - needs the Python vision helper):
Out of battle the bot reads your health off the red globe. Under potionat %
(PlayerStats.txt, default 40) of your most health (read off your name plate in
battle) it drinks a potion (Ctrl+O). If health doesn't go up, you're out, and
it goes to buy more WITH GOLD (never Crowns):
	- By the zone's map (potionwalk:1, the default - the Settings window's
	  "Walk to the potion seller by the map"): nothing to record. The only
	  potion seller is Hilda Brewer in Wizard City's Commons (her spot is in
	  the game's own files). Out of potions anywhere else, the bot leaves a
	  Mark (Page Down) where it is, goes Home (the Home key - outside Wizard
	  City) and to the Commons (End), walks to her by the zone's map (the same
	  route planner as the quest walking), presses X at her prompt, clicks
	  Fill All (found by the words on it - never with "Crown" round it),
	  drinks one, Fills All again, and Recalls (Page Up) back to the Mark to
	  carry on. In the Commons already: no Mark, no Recall. Your house must be
	  in Wizard City (the Dorm is) - else it goes back and tells you. End
	  goes nowhere inside the Dorm, so it walks out its door to Ravenwood
	  first (the way out is in the game's files); End going nowhere there
	  too (it seems to take mana), it walks through Ravenwood's door to the
	  Commons. A Recall takes mana: one that doesn't work keeps the Mark
	  for the next run. With no
	  potions and none to be had it rests (no walking) till health is back.
	  A buying you recorded at your Mark (below) is still used; potionwalk:0
	  for only that.
	  debug.log: "Potions: walking to the potion seller (...) by the zone's
	  map", "Fill All at ...".
	Or recorded, at your Mark:
	- Once: leave a Mark (Page Down) right next to the potion seller
	  (Hilda Brewer, Wizard City's Commons) and keep it there - don't
	  Page Down anywhere else. Then tray menu "Record potion buying...": the
	  bot recalls you to the Mark (Page Up); press X to talk, click Fill All
	  (and close the window), press F9. It's saved as routes\mark_<wizard>.txt
	  with the name on the seller's "Press X" prompt. Each wizard has its own
	  Mark, so do this once for each.
	- When out of potions: Recall (Page Up) to the Mark (none if you're at the
	  seller already), and once her prompt shows the buying, drink,
	  then walking follows the quest arrow on from the seller. Mob-loop, lore
	  and afk farming can't get back to their spot yet - it tells you. Before
	  each click it reads the screen round it - any "Crown" stops the run. A
	  battle, you touching the mouse or keyboard, or a missing loading screen
	  stops it too. Nothing recorded yet: no recall, a tray message says how
	  to set it up. No Mark or too little mana for the Recall: a tray message,
	  another try in 10 minutes. The Mark somewhere else (another zone, or no
	  seller's prompt there): nothing clicked, no more recalls for that wizard
	  till you Mark by the seller again and restart the bot (Windows+1). Not right by the seller when recording?
	  Walk there and press Page Down: the recording starts over from there.
	- Tray menu "Buy potions now" does a run straight away.
	- potionmark:0 in PlayerStats.txt: the old way instead - the bot marks your
	  spot (Page Down), goes Home (End with potionfromhome:0: the Commons),
	  walks a route you recorded with the KEYBOARD only (routes\<zone>.txt -
	  use the mount you'll farm with, a route is a timing) and recalls back.
Mark & Recall: since Nov 2024 they cost 1-10 mana and recalling keeps the
mark. Some places (dorms, houses, some dungeons) can't be marked.

Quick sell when the backpack is full (QuickSell.ahk - Settings > THE BACKPACK,
quicksell, off till you tick it; needs the vision helper - the game's memory,
read-only, never a picture):
	- After a battle the bot played it looks at the game's memory: the
	  backpack's count against its size, and Prospector Zeke's alert in the
	  right-hand column (the same portrait also means "the gold bag is nearly
	  full" - then you're only told). Full: B, the game's own N/M read (it has
	  to say full), Quick Sell, each gear group (hats, robes, shoes, weapons,
	  athames, amulets, rings, decks) and - "...pets too", on - the Pet group
	  with ALL, No to "include Crowns Items?", SELL, the confirmation's numbers
	  read (no Crown items, furniture, jewels, reagents or treasure cards), SELL,
	  then the backpack's count checked. Gold over the pouch is lost (logged).
	- Never in a dungeon run (between two runs, back at its start outside,
	  it may be), a dungeon being recorded, a zone the bot
	  entered through a sigil or a zone it leads on to. A dungeon you walked
	  into yourself isn't known as one: switch quick sell off before you start
	  the bot in it. With the gear pass on (gearswap, see "Gear" below) a full
	  backpack is sold only when every gear piece in it was compared with what
	  you wear and none is better - after a dungeon without its Deck and Pet
	  groups, the pass never comparing decks or pets: the hold below keeps
	  those, and you're told after the sale; a better one - or one it couldn't
	  judge - holds the sale and you're told. After a dungeon the next full
	  backpack is held - you're told, so you can look through the good gear
	  first - until 10 items have gone from it (the bot's own sale isn't
	  counted), you ask from the tray, or you tick "...even with a dungeon's
	  drops in it". A group an Equipment Set's item is in (the boss deck's
	  deck) is left out, and set items are checked after: one gone turns it
	  off. Lock what you want to keep - the game never quick sells locked
	  items.
	  The Pet group is left out too while pets.txt keeps a pet in the
	  backpack (Perfect pets, below).
	- Every click is a window the game's memory names, shown, its size as in
	  the game's files, on a short list; no key or mouse of yours since it
	  began, no battle, no "Crown" read round it. A Crown box other than that
	  No, or anything it doesn't know, stops it (it closes its windows or
	  leaves them to you); a key of yours stops it at once, and so does your
	  mouse between its clicks (while it moves to a button and clicks your
	  mouse is locked - "Lock my mouse while the bot uses it" - and what you
	  do with it then doesn't count).
	- Tray menu: "Quick sell the backpack now" (whether full or not) and "Quick
	  sell rehearsal (stops at the confirmation)" - everything up to the
	  confirmation, read and logged, closed, nothing sold (quicksell:2 in
	  PlayerStats.txt rehearses after battles, at most once an hour).
	  A group with Crown-shop gear ("Crown-..." or "Crowns-..." items) in the
	  backpack is left out - bank it to have that group sold (a full
	  backpack's alert names those groups and items).
	  quicksellfree:N sells with N slots or fewer left. debug.log:
	  "Backpack: ..."; the dashboard: Quick sells.

Gear (Gear.ahk - Settings > THE BACKPACK, gearswap, off till you tick it; new,
not tried in the game yet; needs the vision helper - the game's memory,
read-only):
	- Before a full backpack is quick sold and after each dungeon run, your
	  worn gear and the backpack's are read from the game's memory (each
	  piece's stats and what it needs to be worn - level, school) and, slot
	  by slot (hat, robe, shoes, weapon, athame, amulet, ring - never decks,
	  pets or mounts), a better piece for you is worked out: your damage,
	  pierce, critical, block, accuracy (your stats pages - StatsReader) and
	  health, with the worn piece's stats taken off and the new one's added,
	  weighed for your role (a hitter; in a party your party battle role).
	  The gear's own stats aren't confirmed yet: a piece whose stat sizes
	  aren't read is compared by the level it needs, and every result is
	  ADVICE - "Gear: ..." in debug.log, a tray tip for a new one.
	- A REHEARSAL: nothing is equipped and nothing is clicked - put the piece
	  on yourself (equipping needs the backpack's item windows, which haven't
	  been looked at in the game yet). Never anything that could spend Crowns.
	- A slot whose worn piece is in one of your Equipment Sets: the plan says
	  "held" and you're asked once (Discord) to re-save that set after you
	  swap - else its Ctrl+N (a deck's Equipment Set) puts the old piece back.
	  The bot never saves a set. "...plan pieces of an Equipment Set too"
	  (gearsets) plans them like any other.
	- PlayerStats.txt: gearmargin:2 (the % a piece must be better by),
	  gearlevel:N (your level, if the game's memory doesn't give it), and
	  what counts - one number a line, each left out keeps your role's:
	  gearweight.off:1, gearweight.def:0.5, gearweight.pip:0.3,
	  gearweight.heal:0, gearweight.cards:0.002, gearweight.eblock:200 (an
	  enemy's block rating, for a critical's worth).
	- A piece whose details couldn't be read from the game's memory is "not
	  judged": it holds the quick sell like a better one, and a dungeon run
	  with one among its new pieces isn't counted as a run with no upgrade.
	  A dungeon run whose start couldn't be noted (gearswap switched on
	  midway, the backpack not read then) has its drops left out once.
	- What it reads, from the command line (read-only, nothing sent):
	      python vision\gearmem.py --effects --out gear.txt
	  each piece you wear and each gear piece in the backpack, its stats and
	  requirements as read (send gear.txt back to have them confirmed).

Perfect pets (TODO.md goal 6 - being built: the pet game, snacks and the
hatchery come once their windows have been seen in the game):
	- Write the talents you want in pets.txt, next to PlayerStats.txt (the
	  AutoFarmer folder), in one line:
	      want: Spell-Proof, Spell-Defying, Mighty, Pain-Giver, Pain-Bringer
	  (case, spaces and dashes don't count; ; starts a comment).
	- Quick sell then never sells a pet with every one of them (you're told
	  - lock it in the game), nor a pet whose talents the bot can't read -
	  and it can't read them yet (not confirmed in the game), so for now,
	  with pets.txt there, quick sell sells no pets while any pet is in the
	  backpack: the bot can't read locks either, so it leaves the whole Pet
	  group out (debug.log: "Backpack: left out ... Pet (kept: ...)"). The
	  same when the pets can't all be read (an item in the backpack not read,
	  or fewer pets read than its Pet count). No pets.txt: pets are sold as
	  before ("...pets too").
	- Every pet you own, from the game's memory (read-only - nothing in the
	  game is written, clicked or typed):
	      python vision\petmem.py --out petread.txt
	  one line a pet (worn or in the backpack, its level - Baby ... Ultra -,
	  its name, its level's power cards). Its XP, talents, derby talents and
	  stats and your pet energy aren't read yet: their names first -
	      python vision\reflect.py --class BasePetItemBehavior,ClientPetItemBehavior,PetItemBehaviorTemplate,PetLevelInfo,WizGameStats --grep "XP|Exp|Talent|Stat|Energy|Snack" --out petclass.txt
	  then try a name with the pet's window open in the game (the number it
	  shows to compare with), e.g.
	      python vision\petmem.py --pin xp=BasePetItemBehavior.m_XP:u32 --out petread.txt
	  (field=Class.property:kind - python vision\petmem.py --help lists the
	  fields and kinds). Send the .txt files. Don't name one pets.txt.
	- AutoPetTrainer (Win+1 by the Pet Pavilion's sigil) is still the old
	  blind trainer, on its own: see its README for what it can't do.

Discovery tools (vision\bagmem.py --tree and vision\reflect.py - read-only):
to teach the bot pets, gear, card quests and puzzles it first has to know the
names the game uses for their windows and values. These two print them from
the game's memory. They only read - nothing in the game is written, clicked or
typed, and nothing is sent anywhere: you send the file back yourself. Run them
in a command prompt in the AutoFarmer folder while Wizard101 is running and
your wizard is in the world (the same Python as the vision helper):
	- The windows on screen, one a line (depth, name, type, shown, where, its
	  text): open the window you're asked about first (a battle's planning
	  phase, a trainer, the pet window, the quest book...) - only what's open
	  is shown - then
	      python vision\bagmem.py --tree --out tree.txt
	  --under <Window> for only that window and those in it (quicker - and
	  when a list was cut short, a 1 in the 7th field of its tree| line, ask
	  under the window you want), --all for the hidden ones too, --indent to
	  read it yourself. For a battle's Pass, Flee and Draw buttons, in a
	  battle's planning phase:
	      python vision\bagmem.py --tree --under CombatPlanningPhaseWindow --all --out combat.txt
	- Every property of one of the game's classes and where it is (--class,
	  repeated or A,B), and the names that match a word (--grep):
	      python vision\reflect.py --class WizGameStats --grep "Training|Level" --out stats.txt
	  --pid <n> picks the client when more than one is running.
	Send the .txt file. The vision helper gives the bot the same window list
	(/guitree); nothing the bot does uses it yet.
	For gear (also read-only): the classes the gear pass reads -
	    python vision\reflect.py --class StatisticEffectInfo --class GameEffectInfo --class ItemTemplate --class RequirementList --class ReqMagicLevel --class ReqSchoolOfFocus --class WizGameStats --grep "EffectInfo|^Req" --out gearclass.txt
	  what it reads of your gear (python vision\gearmem.py --effects --out
	  gear.txt - see "Gear"), and the backpack page's windows (open it with B
	  first): python vision\bagmem.py --tree --under InventorySpellbookPage --all --out bag.txt
	For puzzles (two more, also read-only):
	- A zone's own files (Wizard101 installed - it needn't be running):
	      python vision\puzzlefile.py --uses --out uses.txt
	  every zone's use events (a lever pulled, a pedestal used) and what each
	  one's triggers do; then, for one of them, where the game's files name it
	  (what ties a lever to its event):
	      python vision\puzzlefile.py --find <zone> <event> --out find.txt
	  (<zone> as uses.txt names it, e.g. WizardCity-WC_Ravenwood). --game
	  <folder> when the game isn't in the usual place.
	- A gate's state, live: stand by a gate (Storm Lord's Temple's, one a
	  lever opens) and open it - beat its guards, pull its lever - while
	      python vision\statemem.py --watch 180 --out state.txt
	  runs (--all: every object with a state - levers too - not only doors).
	  Before it, the classes it reads:
	      python vision\reflect.py --class ObjectStateBehavior --class ClientObjectStateBehavior --grep state --out stateclass.txt

Along side simply playing the game this program has certain modes
all of which include, command mode, response mode, dual mode and lore mode.
Just as a note, all of these can be turned off be re-inputing the
same key combo.

At any moment you can close the program with "Windows+Escape"

Dual mode:
Pressing the key combo Alt+D will activate this mode. When activated,
at the end of each round the program will tab out as to switch to another
instance of wizard101. Dual mode is only to be used when you're playing on
two accounts. For better consistency close everything but the two instances
of Wizard101.

Command mode:
This mode allows the use of commands from other players, especially used
for teleporting. To activate, use the key combo "Alt+C". When activated
all commands are available to other players. The phrases are as shown.
	Port: 
		When sent to the player running the program, it'll teleport to
		the playing calling.
	Afk: 
		When sent to the player running the program, it goes 
		into a "Timeout prevention sequence" which basically means it
		makes the player move so that you wont disconnect from timeout.
	Enter:
		When sent to the player running the program, 
		it'll press "X" and it's used for interacting with things, and 
		entering sigils.
	Walk:
		When sent to the player running the program, it walks
		the recipient exactly two seconds forward.
		
LoreMode:
When activated, this mode will proceed to farm lore infinitely
so long as the player has mana and or potions. The main way of getting back
to the sigil is by logging out and in, so don't get scared when it does so.
Every cycle, the program waits exactly 30 seconds for the player to regain health.
		
Response mode:
what this mode does is respond to the player issuing the command before 
initiating the command itself. I Primarily made it for shits and giggles but
it does have its uses. For instance, when a command cannot be achieved for 
whatever reason, response mode will report an error instead of it's 
normal phrase.
