# Wiz-Maxxing to-do

Gold only, never Crowns. Game memory is read-only (the one exception: Cheat Engine's speedhack keys).

**Built**: in the bot (v1.0.0 or later), not tried in the game yet - off behind its setting unless the line says on. **Half built** / **groundwork**: the main part still to write. Numbers like 3.5: the step in AutoFarmer\LIVE_CHECKS.txt that tries it.

## 1. Party of 4: synced quests
Four bots, one per PC, quest together: a leader picks the quest, the others follow it into its battles and through its doors, each with a battle role.
- [ ] Teleport to a friend when the leader is somewhere a door doesn't lead - **half built**: the door chain and the can't-follow wait, on in a party (2.7); the helper's teleport guess behind `partytpdoors` (3.7); the teleport itself and a `partytp` setting still to write, once the Friends list's windows are known (1.5, and below). The leader must be on each follower's Friends list.

Done: the home network link, following and waiting, each bot's own name plate in party battles, battle roles (hitter, healer, blader), battles only (Settings: the wizards riding the driver's 4-player mount play its battles and move nothing else).

## 2. Never stuck
The walker gets anywhere a quest sends it, without help.
- [ ] Pass behind moving mobs (sight cones projected along their way); a line of mobs routed round as one wall - **built**, on with `mobavoid`; only the wait at a line with no way round behind `mobwall` (3.5)
- [ ] Keep away from other players' battles (active duel circles in the game's memory) - **built** (`duelavoid`, 1.7, 3.5)
- [ ] Measure it: badly-stuck count and time lost per run - **built**, on (the Dashboard's Badly stuck row, stuckreport.py; 2.1)
- [ ] Puzzle things with no name key (a lever the game names nowhere), found by the zone's triggers' use events - **built**, matched by name for now (`puzzlelevers`, 1.6, 3.6); the exact object-to-event tie still to write
- [ ] A gate's open / shut read from its state in the game's memory, not only the door collision going - **built** (`puzzlestate`, 1.6, 3.6); the state's property and values still to pin; a gate model left in memory once open is walked through to see (on with `puzzles`)
- [ ] A sigil that never starts after a relog (2026-10-26 21:44): leave it, go home and come back - **built** (`sigilhome`, 2.2, 3.4); its thresholds are guesses till the game's "sigil: didn't start" lines are seen

Done: mob rings and sight cones avoided, the quest's goal and its kind read from the game's memory, walking up to goals, "Use ..." / go-to / talk goals with no map marker, the talk goal's NPC known through a garbled "Press X" name (v1.0.3), a blocked way (a gate) tried first - side guards, levers, NPCs - and learned from you after a notice; the quest's Wizard101 Central link in every notice.

## 3. Battles: reliable, then smart
Every card known from the game's memory and played well, with a deck that fits the fight.
- [ ] Every card cast by the game's memory, pictures only a fallback; every other on-screen check by memory where it can be - **half built**: the card and plate boxes (`memclicks`, 2.3, 2.4, 3.11 - last); still to write: acting on the cast checks (logged only now), round start / end (1.8), Pass / Flee / Draw (1.5's combat.txt), mana
- [ ] Battle logic learned (an enormous task), in steps:
  - [ ] Every battle recorded (enemies, hands, cards played and why, damage, rounds to the kill; school, deck, party seat and role) - **built**, `battlerec` on (battlereport.py); a memory snapshot each round (optional) not written yet
  - [ ] A battle simulator on the bot's damage maths, the deck's real cards, the wiki's spells and each enemy's cast history - **built**, on (it picks the boss deck); the bot's whole chain since v1.5.0: enchants, defending (`defendat`), Tower Shield, absorbs, Reshuffle; not in it yet: treasure cards drawn the bot's way (Draw.ahk), each blade and trap once a battle (`reboost`), the enemies' cheats
  - [ ] A planner trying the plays in the simulator each round, learned plays kept per school (all schools' data while a school has few battles); decks matched to each enemy - **built**: the plays as advice (`planner`, 3.1), the matched deck put on (`deckzone`, 3.3); playing the advice needs cards cast by memory and each enemy matched to its plate
  - [ ] In a party: the leader plans the whole team's round (each bot told its card), the hitter's hit round announced for the others' blades and traps - **built as advice**, untried: the hit round (`partyhitround`, 2.7, 3.8), each follower's hand sent over the party, the leader's team plan with them and each follower told its card - logged, never cast (`partyorders`, 3.10); still to write: a follower casting the leader's card (planner:2's cast by memory, each enemy matched to its plate), the orders' timing between PCs (3.10's numbers)
- [ ] "Can this deck beat it": the deck's damage against an enemy's health, block and resists - **built**, on: a boss ahead fought in the simulator with each boss deck, the likeliest winner put on
- [ ] Decks learned from the ones set up in the game - **built**, on (the Cards tab's From game, and every 30 minutes; decks in Equipment Sets)

Done: cards read from memory, blades and traps by damage school, traps on the enemy with the most health, deck profiles with the boss deck put on before the fight, the Spells and Keys tabs.

## 4. Card quests and spell learning, automatic
- [ ] Spell quests taken and done as they come up - **groundwork** (`spellquests`): every quest read from memory, spellplan.py's keep / track / back choice; still to write: telling a spell quest (1.4), tracking it in the quest book (1.5) and back
- [ ] Training points spent at trainers (a set plan per school) - **groundwork** (`trainspells`): a draft plan per school in trainplans.txt, to check (balance's own lines still to write), spellplan.py's next spell to train; still to write: the points read (1.4; the level is read already, 1.1), finding the trainer, the visit (1.5)
- [ ] New spells put in the deck and learned - **groundwork** (`deckadd`): new spells logged (2.5), the deck changes worked out; still to write: the deck edit (1.5); the new card is then learned as any other

Done: NPCs with a quest marker talked to when passed (v1.0.3: also when the prompt's name comes out garbled).

## 5. Gear dungeons until all gear is swapped
- [ ] Olympus, Waterworks, Hades, Darkmoor: routes, bosses, cheats - **groundwork**: dungeons_known.txt and dglint.py; still to do: the four runs recorded (1.9), the bosses' names (1.9) and drops (learned\drops\, 3.2) checked, each boss's cheats set as its deck's settings
- [ ] Gear read and compared to what's worn; better pieces equipped before anything is sold - **half built**: compared and the sale held (`gearswap`, `gearsets`, 3.2); still to write: the equip (1.2), a level table if the stats are indexes (1.1)
- [ ] Repeat each until its gear is all swapped; then the next - **built** (`gearswap`, 3.2); a next dungeon that starts in another zone still needs you to take the wizard there; "all swapped" only once the equip is in (till then by hand, or 30 dry runs)

Done: quick sell when the backpack's full.

## 6. Perfect pets, automatic
- [ ] Build on AutoPetTrainer: training, snacks (gold only) - **groundwork**: pets' level and cards read, a gold-only snack choice (petplan.py); still to write: XP / energy read (1.3), the snack bag, the pet game by memory
- [ ] Hatching for the wanted talents; stop when a pet has them all (pets kept out of quick sell by then) - **half built**: quick sell keeps every pet while one is wanted (2.6), the parents' choice and the stop rule written; still to write: talents read (1.3), the hatchery, the stop wired in

Done: AutoPetTrainer's mouse let go between rounds, and Esc closes it.

## Not in LIVE_CHECKS yet
What the game must still show, with no step for it:
- Window names (`python vision\bagmem.py --tree --all --out <name>.txt`, each one open): a friend's Teleport button, its Yes / No and the refusal; the pet game (can its moves be read?); the hatchery (its level rule, gold cost, Crowns controls); the snack bag (where memory keeps it, each snack's fields)
- `python vision\puzzlefile.py --find <zone> <event>` for a lever's event (from 1.6's uses.txt); `python vision\navmem.py --mobs --motion 60` near walking mobs, and the Map's shaded gaps at a real line of mobs; `python vision\reflect.py --grep mana --out mana.txt`
- A day of battles, then `python vision\battlereport.py` (and `--enemy "<boss>"` against a real fight); "Can this deck beat it" toward a boss; the Cards tab's From game
- A battle with a Reshuffle, an enchant and two Tower Shields in hand: what Reshuffle brings back, its pips, once a battle or not; whether the enchant goes on an X-pip or Hydra hit as the simulator adds it (once, on the weakest head); whether two Tower Shields on you stack
- Whether professors offer spell quests with '!' (`python vision\questmem.py --all` before and after); whether a click on a quest-book row tracks that quest; where trainers stand (http://127.0.0.1:47128/items?far=1 in Ravenwood); what a click on a spellbook entry and on a deck card does; http://127.0.0.1:47128/book?fresh=1&ob=1&kinds=1 (the spell kinds the deck changes use)
