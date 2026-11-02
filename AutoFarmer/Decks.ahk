; Decks.ahk - decks (v0.47.0, TODO goal 3, asked 2026-10-23/24): a "small" deck for weak collect mobs, a "large" one for
; bosses, and as many more as you like. Each is a set of settings that override yours while it's the deck in use - how
; it plays (card logic, blades, traps, healing, pips, discards, which hits and heals it plays) - with what it's used for
; (anything else, collect goals, bosses, dungeon runs, farming), the school it's for, and the game's Equipment Set
; (Ctrl+1..9) that puts its in-game deck on. The bot picks one before each fight from what's ahead (DeckPick) and presses
; that set's key out of battle (DeckEquip). No decks - or decks that set nothing - and it plays exactly as without.
; A boss is known before the fight from the game's memory (2026-10-25, "it doesn't change decks for the bosses" - Alt+1 only
; names it inside the battle, too late for the in-game deck): the zone's mobs' titles, ranks and health (the helper's
; /mobs, READ-ONLY - vision\bossmem.py) - a boss the quest's goal names, the walker goes to or the dungeon run's way leads
; to is "a boss ahead" (DeckBossLook), and the boss deck goes on before the fight (an Elite only when it takes 3 or more
; of your best hits); in the battle its enemies from the memory (/battle) - the boss deck's settings without Alt+1 (a
; boss ahead held: while its in-game deck is the one on). One only passed by isn't: the walker routes round it, and one
; walked into is found in the battle.
; One file per deck: decks\<id>.txt - yours (updates keep them). The dashboard's Cards tab shows and edits them
; (Dashboard.ahk). AutoHotkey v2 (ported from v1.1), #Included by Autofarmer.ahk.
; Decks learned from the game (v1.0.0, TODO goal 3, 2026-10-30): every in-game deck in an Equipment Set read from the
; game's memory (the helper's /decks - READ-ONLY, vision\deckmem.py) becomes a deck here - linked to it by its id (game|
; in the file), its Equipment Set, school and the settings its cards call for (no blades in it: blades off...; boost or
; hit first; for bosses or anything else - vision\battlesim.py learn_decks); a setting you set yourself is never changed
; (the learned ones are listed: learned| in the file). The Cards tab's "From game" button, and by itself every 30 minutes
; out of battle (DeckLearnTick). And "can this deck beat it": a boss ahead is fought in the battle simulator (the helper's
; /sim - vision\battlesim.py: the linked in-game deck's real cards, your stats, the boss's health from the game's memory,
; its resists from the battles recorded and its spells from the wiki) with each deck for bosses - logged, and the one
; most likely to win it picked (DeckBetter).

;The decks ([{id, file, name, school, eqset, when: {default, collect, boss, dungeon, farm}, priority, vals: {key: value}}]),
;the one in use ("" none - your Settings as they are) and why, read again soon (an edit on the tab), when an Equipment Set
;was last pressed, the battle it was picked for, the Cards tab's view (0 the hand, else a deck's number in DeckList)
global DeckList, DeckNow, DeckWhy, DeckDirty, DeckEqAt, DeckDuel, DeckView
;A boss ahead, out of battle, from the game's memory (DeckBossLook): {key (its gid, else its name), name, gid, title,
;rank, health, school, kind (boss, elite), text ("Governor Nereus, rank 9 boss"), why (the quest's goal names it, ...),
;order, dist, since, seenAt (last found ahead - or the end of a battle it wasn't in), battlesAt (the battle count then),
;battled (a battle seen while it was on), inBattle (1 the boss was in that battle by the game's memory, 0 not, "" not
;known), over (that battle over: let go at the next look unless it's still ahead), misses (the zone's mobs not read, in
;a row)} - "" none. A battle's boss ({name, kind, text, max, gid, from: memory - the
;battle's enemies read, walk - the boss ahead}, "" none), the rounds it's been looked for, 1 once the memory answered.
;Declared only (a top-level := never runs in an #Included file)
global DeckBoss, DeckFoe, DeckFoeTries, DeckFoeKnown
;Decks learned from the game: when they were last read (DeckLearnTick), what the last read said (the Cards tab); the
;simulator's last verdict for each deck ({deck id: {word, win, lost, rounds, text, boss}} - DeckBeat)
global DeckLearnAt, DeckLearnSaid, DeckBeats
;The deck being edited on the Cards tab (a copy - saved to its file by Save), the hand's pictures wanted (Dashboard.ahk
;DashCardShow), and the tab's controls (a control's variable has to be global)
global DeckEdit, DashCardWant
global DeckView0, DeckView1, DeckView2, DeckView3, DeckView4, DeckView5, DeckView6, DeckAddBtn
global DeckFNameT, DeckFName, DeckFSchoolT, DeckFSchool, DeckFSetT, DeckFSet, DeckFSetN, DeckFWhenT, DeckFWDefault, DeckFWCollect
global DeckFWBoss, DeckFWDungeon, DeckFWFarm, DeckFPriT, DeckFPri, DeckFPin, DeckFSave, DeckFCopy, DeckFDel, DeckFDmg, DeckFList
global DeckFValT, DeckFVal, DeckFValSet, DeckFValClear, DeckFNote, DeckGameBtn

;Where the decks are kept
DeckDir()
	{
	return A_ScriptDir "\decks"
	}

;What a deck may set: these Settings (Settings.ahk CfgList - how it plays) and which slots it plays
DeckKeys()
	{
	static keys := ""
	if (!IsObject(keys))
		{
		keys := []
		for i, k in ["cardlogic", "boostmax", "useblades", "usetraps", "usebubble", "useaura", "usewand", "usetower"
			, "usereshuffle", "reboost", "solotraps", "healthocr", "killmargin", "drawenchant", "pipsave", "discardunused"
			, "discardmax", "discardspent", "discardunaffordable", "healat", "defendat", "fleeon", "usehit1", "usehit2", "usehit3", "usehit4", "useheal"]
			keys.Push(k)
		}
	return keys
	}

;A deck setting's {label, kind, lo, hi, def, picks} - from the Settings window's list, or the deck's own (which slots)
DeckKeyInfo(key)
	{
	static own := ""
	if (!IsObject(own))
		own := V1Obj({usehit1: "Plays hit1", usehit2: "Plays hit2", usehit3: "Plays hit3", usehit4: "Plays hit4", useheal: "Plays its heals (heal1, heal2)"})
	if (own.Has(key))
		return V1Obj({key: key, label: own[key], kind: "check", def: 1})
	if (V1IsFunc("CfgList"))
		for i, s in CfgList.Call()
			if (s.key = key)
				return s
	return V1Obj({key: key, label: key, kind: "num", def: 0})
	}

;The decks read from the folder (DeckList) - the two to start with made if there are none
DeckLoadAll()
	{
	global DeckList, DeckNow ; (v1 globals it sets)
	V1Do(DirCreate, DeckDir())
	list := []
	Loop Files, DeckDir() "\*.txt"
		{
		d := DeckLoad(A_LoopFilePath)
		if (IsObject(d))
			list.Push(d)
		}
	if (!list.Length)
		{
		for i, s in [["small", "Small deck", "default,collect"], ["large", "Large deck", "boss"]]
			{
			d := V1Obj({id: s[1], file: DeckDir() "\" s[1] ".txt", name: s[2], school: "any", eqset: 0, when: DeckWhenOf(s[3]), priority: 0, vals: V1Obj()})
			DeckSave(d)
			list.Push(d)
			}
		DebugLog("Decks: made Small deck (used for collect goals and anything else) and Large deck (bosses) - they set nothing yet: set them on the Cards tab")
		}
	;(in a set order: Small, Large, then the others as they were made - a new deck's id is when; the files come
	;alphabetically, which put a new deck1 before both)
	order := []
	for i, id in ["small", "large"]
		for j, d in list
			if (d.id = id)
				order.Push(d)
	for j, d in list
		if (d.id != "small" && d.id != "large")
			{
			at := order.Length + 1
			Loop order.Length
				;(v1's < compared the ids - text - alphabetically; v2's throws on text: V1Lt)
				if (order[A_Index].id != "small" && order[A_Index].id != "large" && V1Lt(d.id, order[A_Index].id))
					{
					at := A_Index
					break
					}
			order.InsertAt(at, d)
			}
	DeckList := order
	;(the Cards tab's buttons named after them; the Dungeons tab's Deck box)
	if (DashHwnd)
		DeckButtonsShow()
	if (DashHwnd && V1IsFunc("DgDeckShow"))
		DgDeckShow.Call()
	;(the one in use, read afresh - or none if it's gone; not in a battle: the round goes on as it was planned, the edit
	;from the next battle - DeckTick picks afresh out of battle)
	if (IsObject(DeckNow) && inbattle != 1)
		{
		d := DeckById(DeckNow.id)
		DeckNow := IsObject(d) ? d : ""
		}
	return order
	}

;Deck id's place in DeckList (0 not there)
DeckIndexOf(id)
	{
	for i, d in IsObject(DeckList) ? DeckList : []
		if (d.id = id)
			return i
	return 0
	}

;{default: 1, collect: 1, ...} of a comma list
DeckWhenOf(text)
	{
	w := V1Obj()
	Loop Parse, text, ",", A_Space
		if (RegExMatch(A_LoopField, "^(default|collect|boss|dungeon|farm)$"))
			w[A_LoopField] := 1
	return w
	}

;One deck's file read ("" if it isn't one): field|value lines, then key:value settings - only those a deck may set
DeckLoad(file)
	{
	SplitPath(file, , , , &id)
	d := V1Obj({id: id, file: file, name: id, school: "any", eqset: 0, when: V1Obj(), priority: 0, vals: V1Obj(), game: "", learned: "", bossname: ""})
	allowed := V1Obj()
	for i, k in DeckKeys()
		allowed[k] := 1
	dropped := ""
	Loop Read, file
		{
		line := Trim(RegExReplace(A_LoopReadLine, "\s;.*$"))
		if (line = "" || SubStr(line, 1, 1) = ";")
			continue
		if (RegExMatch(line, "^(\w+)\|(.*)$", &m))
			{
			if (m[1] = "name")
				d.name := Trim(SubStr(RegExReplace(m[2], "[^\x20-\x7E]|\|", ""), 1, 30))
			else if (m[1] = "school")
				d.school := RegExMatch(Trim(m[2]), "i)^(storm|fire|myth|balance|ice|life|death)$") ? Format("{:L}", Trim(m[2])) : "any"
			else if (m[1] = "eqset")
				d.eqset := RegExMatch(Trim(m[2]), "^[0-9]$") ? Trim(m[2]) + 0 : 0
			else if (m[1] = "when")
				d.when := DeckWhenOf(m[2])
			else if (m[1] = "priority")
				d.priority := RegExMatch(Trim(m[2]), "^-?\d{1,3}$") ? Trim(m[2]) + 0 : 0
			;(the in-game deck it was learned from - its global id in hex - and the settings that learning set)
			else if (m[1] = "game")
				d.game := RegExMatch(Trim(m[2]), "i)^[0-9a-f]{1,16}$") ? StrLower(Trim(m[2])) : ""
			else if (m[1] = "learned")
				d.learned := RegExReplace(StrLower(m[2]), "[^a-z0-9,!]")
			;(v1.0.0: the boss it's for by name - "Kraken", several with a comma between - DeckPick: its deck for that boss, a
			;cheat-aware profile set with the deck's settings; edited in the file for now - older versions skip the line)
			else if (m[1] = "bossname")
				d.bossname := Trim(SubStr(RegExReplace(m[2], "[^\x20-\x7E]|\|", ""), 1, 80))
			continue
			}
		if (RegExMatch(line, "^([\w.]+)\s*:\s*(-?\d+(?:\.\d+)?)\s*\x25?$", &m))
			{
			k := StrLower(m[1])
			if (allowed.Has(k))
				d.vals[k] := DeckNum(m[2])
			else
				dropped .= (dropped = "" ? "" : ", ") k
			}
		}
	else
		{
		;(v1: a deck file that couldn't be read - gone since it was listed - gave no lines; v2 throws when the loop has no
		;Else. Empty or unreadable: nothing read, the deck as it starts)
		}
	if (dropped != "")
		DebugLog("Decks: " d.name " (" file "): not a deck's setting, left out - " dropped)
	if (d.name = "")
		d.name := id
	return d
	}

;A setting's number as v1 kept it (v2 port): text + 0 - one with a decimal point a float, which AutoHotkey v1 wrote out
;with 6 decimals ("1.5" -> "1.500000": in the deck's file and on the Cards tab); v2 would write "1.5"
DeckNum(s)
	{
	return InStr(s, ".") ? Format("{:.6f}", s) : s + 0
	}

;One deck written back to its file
DeckSave(d)
	{
	w := ""
	for k, v in d.when
		w .= (w = "" ? "" : ",") k
	text := "; Wiz-Maxxing deck (the dashboard's Cards tab). A setting not here: your Settings' (your school's, then the plain one)`r`n"
		. "name|" d.name "`r`nschool|" d.school "`r`neqset|" d.eqset "`r`nwhen|" w "`r`npriority|" d.priority "`r`n"
		. (d.game != "" ? "game|" d.game "`r`n" : "") (d.learned != "" ? "learned|" d.learned "`r`n" : "") (d.bossname != "" ? "bossname|" d.bossname "`r`n" : "")
	for i, k in DeckKeys()
		if (d.vals.Has(k))
			text .= k ":" d.vals[k] "`r`n"
	V1Do(DirCreate, DeckDir())
	;(v1's FileOpen gave 0 when the file couldn't be opened; v2 throws)
	f := V1Try(FileOpen, d.file ".tmp", "w", "UTF-8-RAW")
	if (!IsObject(f))
		return false
	f.Write(text)
	f.Close()
	V1Do(FileMove, d.file ".tmp", d.file, 1)
	return !ErrorLevel
	}

DeckById(id)
	{
	if (id = "" || !IsObject(DeckList))
		return ""
	for i, d in DeckList
		if (d.id = id)
			return d
	return ""
	}

;The deck to use now and why ({deck: d or "", why, boss: 1 when it's for a boss - DeckEquip puts it on sooner}): only
;decks for this wizard's school (or any) - the one fought as in a battle, else the one this character fought as before.
;First match wins: the dungeon run's deck, the one pinned on the Cards tab, the boss's (in a battle: your Alt+1 pick, or
;a boss among its enemies by the game's memory - or, that not read, the boss ahead it was walked into - or a boss ahead
;still held, its deck's Equipment Set the one on in the game: a fight on the way to it plays the cards that are in hand;
;out of battle, the bot on: a boss ahead - DeckBossLook), a collect goal's, farming's (loop or lore mode), a dungeon
;run's, anything else's - none: your Settings as they are. Of several for the same, the highest priority. noBoss: as if
;there were no boss (the deck an Elite is measured against - DeckBestHit)
DeckPick(inBattle, noBoss := false)
	{
	if (!IsObject(DeckList) || !DeckList.Length)
		return V1Obj({deck: "", why: "no decks"})
	sch := inBattle && hitschool != "" ? hitschool : V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	;(v1.0.0: the boss's name - a deck for it by name, a dungeon run's own deck for it: its boss|<name>|<deck id> lines, before
	;its deck| one - held in a battle it isn't known to be in: while that deck's Equipment Set is the one on)
	dpHeld := 0
	dpBoss := DeckBossName(inBattle, noBoss, &dpHeld)
	if (dpBoss != "" && IsObject(DgRun) && IsObject(DgRun.bosses))
		for dpI, dpB in DgRun.bosses
			{
			d := DeckNameMatch(dpB.name, dpBoss) ? DeckById(dpB.deck) : ""
			if (IsObject(d) && DeckFits(d, sch) && (!dpHeld || DeckHeldOn(d)))
				return V1Obj({deck: d, why: "the dungeon run " DgRun.name "'s for " dpBoss, boss: 1})
			}
	if (IsObject(DgRun) && DgRun.deck != "")
		{
		d := DeckById(DgRun.deck)
		if (IsObject(d))
			return V1Obj({deck: d, why: "the dungeon run " DgRun.name "'s"})
		}
	pin := IniRead(A_ScriptDir "\dashboard.ini", "decks", "pin", A_Space)
	if (pin != "")
		{
		d := DeckById(pin)
		if (IsObject(d) && DeckFits(d, sch))
			return V1Obj({deck: d, why: "pinned on the Cards tab"})
		}
	;(the boss's: your Alt+1 pick; in a battle a boss among its enemies - DeckFoe, DeckRound - or the boss ahead held,
	;while its deck is the one on in the game; out of battle a boss ahead)
	bossWhy := "", bossHeld := 0
	if (!noBoss && inBattle && BossChoosen)
		bossWhy := "a boss (your " HkText("boss") " pick)"
	else if (!noBoss && inBattle && IsObject(DeckFoe))
		bossWhy := (DeckFoe.from = "memory" ? "a boss in this battle: " : "a boss ahead: ") DeckFoe.text
	else if (!noBoss && inBattle && BotOn && IsObject(DeckBoss))
		bossWhy := "a boss ahead: " DeckBoss.text " (its deck is on)", bossHeld := 1
	else if (!noBoss && !inBattle && BotOn && IsObject(DeckBoss))
		bossWhy := "a boss ahead: " DeckBoss.text
	for i, use in [["boss", bossWhy != "", bossWhy]
		, ["collect", IsObject(WkCollect) && !WkCollect.gaveUp, "a collect goal"]
		, ["farm", loopmode || loremode, "farming"]
		, ["dungeon", IsObject(DgRun), "a dungeon run"]
		, ["default", 1, "anything else"]]
		{
		if (!use[2])
			continue
		best := "", dpNamed := 0
		;(v1.0.0: for a boss, a deck for it by name first - its bossname| line, "bosses" ticked or not)
		if (use[1] = "boss" && dpBoss != "")
			for j, d in DeckList
				if (DeckNamedFor(d, dpBoss) && DeckFits(d, sch) && DeckBetter(d, best, "boss"))
					best := d, dpNamed := 1
		if (!IsObject(best))
			for j, d in DeckList
				if (d.when[use[1]] && DeckFits(d, sch) && DeckBetter(d, best, use[1]))
					best := d
		;(a boss ahead held in a battle it isn't in: its deck's settings only while its in-game deck is on - the set put
		;on last, DeckEquip's; another set on: the deck for what this battle is)
		if (use[1] = "boss" && bossHeld && IsObject(best))
			{
			;(no Equipment Set: it puts no cards on - the deck for what this battle is)
			if (!best.eqset)
				continue
			onSet := IniRead(A_ScriptDir "\dashboard.ini", "decks", "eqset" (V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""), A_Space)
			if (onSet != "" && onSet != best.eqset)
				continue
			}
		if (IsObject(best))
			return V1Obj({deck: best, why: use[3] (dpNamed ? " - its deck by name" : ""), boss: use[1] = "boss" ? 1 : 0})
		}
	return V1Obj({deck: "", why: "no deck for this"})
	}

;(v1.0.0) The boss's name for DeckPick's by-name match ("" none): a boss in this battle by the game's memory (DeckFoe), else
;the boss ahead (DeckBoss, the bot on); held 1: in a battle and not known to be in it (DeckPick's bossHeld - its deck's
;settings only while its Equipment Set is the one on: DeckHeldOn). Your Alt+1 pick alone names nobody
DeckBossName(inBattle, noBoss, &held)
	{
	held := 0
	if (noBoss)
		return ""
	if (inBattle && IsObject(DeckFoe))
		return DeckFoe.name
	if (BotOn && IsObject(DeckBoss))
		{
		held := inBattle && !BossChoosen ? 1 : 0
		return DeckBoss.name
		}
	return ""
	}

;(v1.0.0) want (a deck's bossname or a run's boss| name) names the boss called name: its letters all of name's (Governor
;Nereus - "Governor Nereus"), or among them when it has 4 or more ("Nereus")
DeckNameMatch(want, name)
	{
	dnmW := DeckLetters(want), dnmN := DeckLetters(name)
	if (dnmW = "" || dnmN = "")
		return false
	return dnmW = dnmN || (StrLen(dnmW) >= 4 && InStr(dnmN, dnmW))
	}

;(v1.0.0) Deck d is for the boss called name by its bossname| line (several with a comma between)
DeckNamedFor(d, name)
	{
	if (d.bossname = "")
		return false
	Loop Parse, d.bossname, ","
		if (DeckNameMatch(A_LoopField, name))
			return true
	return false
	}

;(v1.0.0) A boss deck held in a battle may have its settings only while its in-game deck is the one on: it has an Equipment
;Set and that's the one put on last (DeckEquip's dashboard.ini [decks] eqset<CharID>), or none was put on yet (v1's blank -
;DeckPick's rule for a deck for bosses)
DeckHeldOn(d)
	{
	if (!d.eqset)
		return false
	dhoSet := Trim(IniRead(A_ScriptDir "\dashboard.ini", "decks", "eqset" (V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""), ""))
	return dhoSet = "" || dhoSet = d.eqset
	}

;A deck is for this wizard: its school, or any (school not known: only an 'any' one)
DeckFits(d, sch)
	{
	return d.school = "any" || (sch != "" && d.school = sch)
	}

;The deck in use set (said in the log and on the dashboard when it changes)
DeckSet(d, why)
	{
	global DeckNow, DeckWhy ; (v1 globals it sets)
	if ((IsObject(d) ? d.id : "") = (IsObject(DeckNow) ? DeckNow.id : ""))
		{
		;(the same deck for another reason - a boss ahead now in the battle: the dashboard's line says so, not the log)
		if (why != DeckWhy && IsObject(DashSees))
			DashSees.deck := IsObject(d) ? d.name " (" why ")" : "-"
		DeckNow := d, DeckWhy := why
		return false
		}
	DeckNow := d, DeckWhy := why
	n := 0
	if (IsObject(d))
		for k, v in d.vals
			n += 1
	DebugLog("Deck: " (IsObject(d) ? d.name " (" why ")" (n ? " - " n " setting" (n = 1 ? "" : "s") " of its own" : " - it sets nothing: your Settings") : "none - your Settings as they are (" why ")"))
	if (IsObject(DashSees))
		DashSees.deck := IsObject(d) ? d.name " (" why ")" : "-"
	return true
	}

;Out of battle, every 2 s (the main loop): the decks read again after an edit, a boss ahead looked for (the game's
;memory - DeckBossLook), the deck for what's ahead picked, and its Equipment Set put on (a boss's sooner)
DeckTick()
	{
	static lookAt := 0
	global DeckDirty ; (v1 globals it sets)
	if (lookAt && A_TickCount - lookAt < 2000)
		return
	lookAt := A_TickCount
	if (!IsObject(DeckList) || DeckDirty)
		DeckDirty := 0, DeckLoadAll()
	DeckLearnTick()
	DeckBossLook()
	p := DeckPick(false)
	;(Settings: deckzone, off - the deck the battle simulator says fits this zone's enemies best: DeckForZone)
	p := DeckForZone(p)
	DeckSet(p.deck, p.why)
	if (IsObject(p.deck))
		DeckEquip(p.deck, p.boss)
	}

;A battle round (once the school's known): a new battle - its deck picked; your Alt+1 boss pick - the boss's, if there's
;one; the battle's enemies from the game's memory (the helper's /battle - DeckFoeLook: a boss among them, the boss deck's
;settings without Alt+1; looked for in its first 3 rounds till the memory answers - not read: the boss ahead it was
;walked into). The in-game deck can't change in a battle: its settings only. A battle is told by its duel in the game's
;log (BlDuel), else by the battle count (constant within a battle) - not every round a new one
DeckRound()
	{
	global DeckFoe, DeckFoeTries, DeckFoeKnown, DeckDuel ; (v1 globals it sets)
	if (!IsObject(DeckList))
		DeckLoadAll()
	drKey := BlDuel != "" ? BlDuel : "#" battles
	drNew := drKey != DeckDuel
	if (drNew)
		DeckFoe := "", DeckFoeTries := 0, DeckFoeKnown := 0
	;(an Equipment Set pressed just before this battle - maybe in its start, which the game doesn't take: not kept as
	;the one on, so it's pressed again after the fight rather than skipped for 15 minutes. The spellbook - it only shows
	;out of battle - not seen half a second or more after the set was pressed (the main loop looks for it right after
	;DeckTick): pressed at the battle's start or under a dialog, maybe not taken)
	if (drNew && DeckEqAt && BookSeenAt < DeckEqAt + 500)
		{
		drWho := V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""
		V1Do(IniDelete, A_ScriptDir "\dashboard.ini", "decks", "eqset" drWho)
		}
	drFoe := 0
	;(DeckFoeTries starts blank: v1 compared a blank with 3 as text - TRUE - and its += counted it as 0)
	if (!DeckFoeKnown && V1Lt(DeckFoeTries, 3) && DeckBossWanted())
		{
		DeckFoeTries := V1N(DeckFoeTries) + 1
		drWas := IsObject(DeckFoe) ? DeckFoe.from "|" DeckFoe.name : ""
		DeckFoeLook()
		drFoe := drWas != (IsObject(DeckFoe) ? DeckFoe.from "|" DeckFoe.name : "")
		}
	if (!drNew && !drFoe && !(BossChoosen && !(IsObject(DeckNow) && DeckNow.when.boss)))
		return
	DeckDuel := drKey
	p := DeckPick(true)
	;(the zone's pick put on before the battle - deckzone: its settings, while its in-game deck is the one on)
	p := DeckForZone(p, true)
	DeckSet(p.deck, p.why)
	}

;The deck's in-game deck put on - its Equipment Set's key (Ctrl+1..9 - the game's own; also its gear, pet and mount, as
;you set the set up), out of battle only, with nothing loading, Wizard101 in front and you away from the keys and mouse
;(as long as "Wait while I play" waits - handsoff, 3 s at least; Play for me: never waited for), once a minute at most (the
;game says "Slow down!" past 10 changes in 2 minutes) - soon (a boss ahead: its fight is coming) 10 s after the last; the
;set put on last kept by character (dashboard.ini [decks] eqset<CharID>) and pressed again after 15 minutes (a press the
;game didn't take - a dialog up, a battle starting)
DeckEquip(d, soon := false)
	{
	static at := V1Obj()
	global DeckEqAt ; (v1 globals it sets)
	secs := Stats.Has("handsoff") ? Stats["handsoff"] : 3
	if (!d.eqset || !BotOn || inbattle = 1 || WkLoading || (V1IsFunc("BattleLogInBattle") && BattleLogInBattle.Call())
		|| !GameActive() || UserIdle() < Max(3, secs) * 1000 || (DeckEqAt && A_TickCount - DeckEqAt < (soon ? 10000 : 60000)))
		return false
	who := V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""
	was := IniRead(A_ScriptDir "\dashboard.ini", "decks", "eqset" who, A_Space)
	if (was = d.eqset && at.Has(who) && A_TickCount - at[who] < 900000)
		return false
	at[who] := A_TickCount
	DeckEqAt := A_TickCount
	if (KeysDown || HeldW)
		ReleaseKeys()
	Sleep(150)
	key := d.eqset
	Send("{Blind}^" key)
	V1Do(IniWrite, d.eqset, A_ScriptDir "\dashboard.ini", "decks", "eqset" who)
	DebugLog("Deck: " d.name "'s in-game deck put on - Equipment Set " d.eqset " (Ctrl+" d.eqset ")" (was = d.eqset ? " again" : ""))
	Sleep(400)
	return true
	}

;The hit, heal and wand slots the deck in use doesn't play, taken out of this round's hand (after the slots were looked for)
DeckFilterHand()
	{
	global hit1, hit2, hit3, hit4, heal1, heal2, wand ; (v1 globals it sets)
	if (!IsObject(DeckNow))
		return
	v := DeckNow.vals
	if (v.Has("usehit1") && !v.usehit1)
		hit1 := 0
	if (v.Has("usehit2") && !v.usehit2)
		hit2 := 0
	if (v.Has("usehit3") && !v.usehit3)
		hit3 := 0
	if (v.Has("usehit4") && !v.usehit4)
		hit4 := 0
	if (v.Has("useheal") && !v.useheal)
		heal1 := 0, heal2 := 0
	if (v.Has("usewand") && !v.usewand)
		wand := 0
	}

;A setting as deck d has it for school sch: its own, else your school's, else the plain one (0 none)
DeckStatFor(d, sch, key)
	{
	if (IsObject(d) && d.vals.Has(key))
		return d.vals[key]
	if (sch != "" && Stats.Has(sch "." key))
		return Stats[sch "." key]
	return Stats.Has(key) ? Stats[key] : 0
	}

;The settings the vision helper's simulator plays deck d by, for school sch (/sim, /deckfor and /plan's vals=):
;every deck setting (DeckKeys) and the ones only PlayerStats.txt or the Settings window set that it reads
;(enemyspells, useabsorb, drawneed, drawround, drawmax) - each as DeckStatFor has it (the deck's, your school's,
;the plain one), and only when set somewhere: useabsorb has no default (the helper's own is on, as StatOr's).
;drawenchant 0 while drawing is off for the run (Draw.ahk DrawForKill: DrawBroken, or Draw greyed out with room
;under 30 minutes ago - DrawEmptyAt). discardspent 0 in dual mode or as a Blader / Healer with the party on (v1.8.0).
;d "" (no deck): yours. "key:value,..."
DeckSimVals(d, sch)
	{
	dsvOut := ""
	;(a copy: DeckKeys' own list is the deck files' allowed keys too - these extra ones are never a deck's)
	dsvKeys := DeckKeys().Clone()
	for dsvI, dsvK in ["enemyspells", "useabsorb", "drawneed", "drawround", "drawmax"]
		dsvKeys.Push(dsvK)
	dsvNoDraw := (DrawBroken != "" || (DrawEmptyAt && A_TickCount - DrawEmptyAt < 1800000))
	for dsvI, dsvK in dsvKeys
		{
		dsvV := DeckStatFor(d, sch, dsvK)
		if (dsvK = "drawenchant" && dsvNoDraw)
			dsvV := 0
		;(v1.8.0: discardspent 0 where this bot never runs it this session - dual mode, a Blader or Healer with the party on
		;(Autofarmer.ahk DiscardSpentRole): the simulator then holds the copies, as the bot does)
		if (dsvK = "discardspent" && (dualmode == 1 || (V1IsFunc("DiscardSpentRole") && !DiscardSpentRole.Call())))
			dsvV := 0
		;(only a key set somewhere - DeckStatFor's 0 for one set nowhere would switch useabsorb off in the helper)
		if (dsvV != "" && ((IsObject(d) && IsObject(V1At(d, "vals")) && d.vals.Has(dsvK)) || Stats.Has(dsvK)
			|| (sch != "" && Stats.Has(sch "." dsvK))))
			dsvOut .= (dsvOut = "" ? "" : ",") dsvK ":" dsvV
		}
	return dsvOut
	}

;What a hit of deck d can deal, as a range (you asked 2026-10-24): {lo, hi, hiNoCrit, loName, hiName, boosts, guess, none,
;crit, damage}. lo: its weakest hit at the low end of its range with nothing on it and no critical; hi: its strongest at
;the top of its range with every blade, trap, aura and bubble the deck plays on it (each once) and a critical (x2 - its
;most, against no block: CritMult). Both with the wizard's own damage % for that school (StatsReader: <school>.damage,
;else damage - the game's curve: DamageMultiplier) - not the enemies' resist, your pierce or an enchant (a boss's: the
;fight's own numbers). The hits: hit1-4 of its school that it plays (their least damage in your Settings; the top of
;the range from the card learned into that slot, else its least: guess) and the learned hits in no slot (learnedhits).
;none: no hit known for it
DeckDamage(d)
	{
	sch := (IsObject(d) && d.school != "any") ? d.school : V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	out := V1Obj({lo: "", hi: "", loName: "", hiName: "", boosts: "", guess: false, none: true, school: sch})
	if (sch = "")
		return out
	hits := []
	;(the slots' hits it plays)
	for i, slot in ["hit1", "hit2", "hit3", "hit4"]
		{
		if (!DeckStatFor(d, sch, "use" slot) && (IsObject(d) && d.vals.Has("use" slot)))
			continue
		lo := Stats.Has(sch "." slot) ? Stats[sch "." slot] : 0
		;(none: its heads typed one line a head - balance.hit3fire, .hit3ice, .hit3storm for a Hydra - added up, as the kill
		;check counts them: KillCalc.ahk HitHeadsFind)
		if (lo <= 0)
			for ddI, ddS in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
				lo += Stats.Has(sch "." slot ddS) ? Stats[sch "." slot ddS] : 0
		if (lo <= 0)
			continue
		hi := DeckSlotHigh(sch, slot)
		name := V1IsFunc("DashShortName") ? DashShortName.Call(slot, sch) : slot
		;(an X-pip hit - its pips 0: its number a pip's - 1 pip at the least, 14 at the most: 7 power pips)
		if (Stats.Has(sch "." slot "pips") && Stats[sch "." slot "pips"] = 0 && slot != "wand")
			hits.Push(V1Obj({lo: lo, hi: (hi != "" ? hi : lo) * 14, guess: hi = "", name: name " (X pips)"}))
		else
			hits.Push(V1Obj({lo: lo, hi: hi != "" ? hi : lo, guess: hi = "", name: name}))
		}
	;(learned hits in no slot, when it casts them: learnedhits)
	if (DeckStatFor(d, sch, "learnedhits") != 0 && IsObject(LearnedCards))
		for i, c in LearnedCards
			if ((c.type = "damage" || c.type = "aoe") && c.sch = sch && c.slot = "" && !LearnHasFlag(c, "skip"))
				{
				lo := V1IsFunc("LearnHitBase") ? LearnHitBase.Call(c) : c.value
				if (lo = "" || lo <= 0)
					continue
				hi := DeckRangeTop(c.text)
				hi := hi != "" && hi >= lo ? hi : lo
				xp := LearnHasFlag(c, "xpip")
				hits.Push(V1Obj({lo: lo, hi: xp ? hi * 14 : hi, guess: hi = lo, name: (c.name != "" ? c.name : "a learned hit") (xp ? " (X pips)" : "")}))
				}
	if (!hits.Length)
		return out
	dmgPct := Stats.Has(sch ".damage") ? Stats[sch ".damage"] : Stats.Has("damage") ? Stats.damage : 0
	critR := Stats.Has(sch ".critical") ? Stats[sch ".critical"] : Stats.Has("critical") ? Stats.critical : 0
	mult := V1IsFunc("DamageMultiplier") ? DamageMultiplier.Call(dmgPct) : 1
	weak := "", strong := ""
	for i, h in hits
		{
		if (!IsObject(weak) || h.lo < weak.lo)
			weak := h
		if (!IsObject(strong) || h.hi > strong.hi)
			strong := h
		}
	;(every boost it plays, once each)
	;(the second blade and trap the school's: Elemental for fire, ice and storm, Spirit for life, death and myth - none
	;for balance. Balance's own blade and trap are Balanceblade and Hex - blade3, trap3: counted once, as the kill check
	;does - KillCalc.ahk BoostKey)
	boost := 1, names := ""
	grp := V1IsFunc("SchoolGroup") ? SchoolGroup.Call(sch) : ""
	b2 := grp = "elemental" ? "elementalblade" : grp = "spirit" ? "spiritblade" : ""
	t2 := grp = "elemental" ? "elementaltrap" : grp = "spirit" ? "spirittrap" : ""
	ddB := (sch = "balance") ? [b2, "blade3", "blade4"] : ["blade", b2, "blade3", "blade4"]
	ddT := (sch = "balance") ? [t2, "trap3", "trap4", "feint"] : ["trap", t2, "trap3", "trap4", "feint"]
	for i, b in [["useblades", ddB], ["usetraps", ddT], ["useaura", ["aura"]], ["usebubble", ["bubble"]]]
		{
		if (!DeckStatFor(d, sch, b[1]))
			continue
		for j, k in b[2]
			{
			pct := k != "" ? DeckStatFor(d, sch, k) : 0
			if (pct > 0)
				boost *= 1 + pct / 100, names .= (names = "" ? "" : ", ") k " " pct "%"
			}
		}
	out.lo := Floor(weak.lo * mult), out.hiNoCrit := Floor(strong.hi * mult * boost)
	out.hi := Floor(out.hiNoCrit * (critR > 0 ? CritMult(critR, 0) : 1))
	out.loName := weak.name, out.hiName := strong.name, out.boosts := names, out.guess := strong.guess, out.none := false
	out.crit := critR, out.damage := dmgPct
	return out
	}

;A critical's damage multiplier for your critical rating crit against an enemy's block rating block (PvE): 2 - 3B / (C +
;3B) - x2 against no block, x1.7 for 630 against 90. The community's model (multicalculators.com, Oct 2026 - KingsIsle
;doesn't publish it; checked against its worked example)
CritMult(crit, block)
	{
	if (crit <= 0)
		return 1
	return 2 - 3 * block / (crit + 3 * block)
	}

;The chance (0-1) your hit is a critical against block rating block (PvE): 3 L C / (3 C + B), L your level / 100 (at most
;1) - the same model as CritMult
CritChance(crit, block, level := 100)
	{
	if (crit <= 0)
		return 0
	lf := level > 0 ? Min(1, level / 100) : 1
	return Min(1, 3 * lf * crit / (3 * crit + block))
	}

;The top of a slot's hit's damage range: from the card learned into that slot (learned\cards.txt) - "" not known
DeckSlotHigh(sch, slot)
	{
	if (!IsObject(LearnedCards))
		return ""
	for i, c in LearnedCards
		if (c.slot = sch "\" slot)
			return DeckRangeTop(c.text)
	return ""
	}

;The top of every head's damage range on a card's text, added up ("295-335" -> 335; a Hydra's three heads summed), up to
;its "over N rounds" part; "" none
DeckRangeTop(text)
	{
	at := RegExMatch(text, "i)over\s*\d|r[o0]unds?\b")
	head := at ? SubStr(text, 1, at - 1) : text
	sum := 0, n := 0, p := 1
	while (p := RegExMatch(head, "(\d+)\s*-\s*(\d+)", &m, (p)<1 ? (p)-1 : (p)))
		{
		if (m[2] + 0 >= m[1] + 0)
			sum += m[2] + 0, n += 1
		p += StrLen(m[0])
		}
	return n ? sum : ""
	}

;The range in words, for the Cards tab
DeckDamageText(d)
	{
	r := DeckDamage(d)
	if (r.school = "")
		return "Damage: not known yet - the bot hasn't seen which school this wizard fights as"
	if (r.none)
		return "Damage: no " r.school " hit known for this deck - it would only boost and pass"
	return "Damage a hit (" r.school ", your damage " r.damage "%, critical " r.crit "): " r.lo " (" r.loName ", nothing on it, no critical) to " r.hi
		. (r.guess ? "+" : "") " (" r.hiName " at its best" (r.boosts != "" ? ", with " r.boosts : "") (r.crit > 0 ? ", a critical x2 - " r.hiNoCrit " without" : "") ")"
		. (r.guess ? " - its range's top isn't known: its least used" : "")
	}

;---- A boss ahead: the boss deck before the fight (the game's memory - read-only) ----
;
;Alt+1 names the boss inside the battle - too late for the in-game deck. The helper's /mobs (NavMobs in Vision.ahk, READ-
;ONLY: nothing in the game is written, injected or hooked) gives each of the zone's mobs its title as the game has it
;(Boss, Elite, Normal...), rank, max health and the game's own boss flag (vision\bossmem.py). A boss (or an Elite that
;takes 3 or more of your best hits) is "ahead" when the quest's goal names it, the walker goes to it (the helper's quest
;mob by its name or its goal - not one of the same family elsewhere in the zone) or the dungeon run's way leads to it -
;then the deck for bosses is picked and its Equipment Set pressed before the fight. One only passed by isn't (the walker
;routes round it; one walked into is found in the battle - DeckFoeLook). Kept till that battle's over, or 30 s after
;it's gone or far off - counted from the end of a battle it wasn't in (no switching back and forth); a missed reading
;changes nothing, but 60 in a row (2 minutes), the bot off or another zone let it go. Needs the bot on, out of battle,
;nothing loading, a deck for bosses, navmem on and the vision helper (no memory: your Alt+1 pick in the battle, as before)

;There's a deck for bosses (else there's nothing to look for)
DeckBossWanted()
	{
	;(v1.0.0: a deck for a boss by name, or a dungeon run's boss| lines, want the boss ahead looked for too)
	for dbwI, dbwD in IsObject(DeckList) ? DeckList : []
		if (dbwD.when.boss || dbwD.bossname != "")
			return true
	return IsObject(DgRun) && IsObject(DgRun.bosses) && DgRun.bosses.Length ? true : false
	}

;Out of battle (DeckTick, every 2 s): the zone's mobs read (NavMobs) and a boss ahead looked for - DeckBoss set, kept or
;let go (see above)
DeckBossLook()
	{
	global DeckBoss ; (v1 globals it sets)
	;(the zone from the game's log now: WkZoneAt and WkLoading up to date before the mobs are read)
	if (V1IsFunc("WalkZone"))
		WalkZone.Call(true)
	;(the bot off, or another zone since it was last found ahead: let go - not kept for a fight it won't be in)
	if (IsObject(DeckBoss) && (!BotOn || (WkZoneAt && WkZoneAt > DeckBoss.seenAt)))
		{
		DebugLog("Deck: no boss ahead now - " DeckBoss.name (!BotOn ? " (the bot's off)" : " (another zone)"))
		DeckBoss := ""
		}
	if (!DeckBossWanted() || !BotOn || inbattle = 1 || WkLoading || !V1IsFunc("NavMobs"))
		return
	if (V1IsFunc("BattleLogInBattle") && BattleLogInBattle.Call())
		return
	dblNow := A_TickCount
	;(a battle over while it was on - the boss's, or one the game's memory couldn't name: let go now unless it's still
	;ahead; one the memory says it wasn't in: kept, its 30 s from now - nothing was looked at in the battle)
	if (IsObject(DeckBoss) && (DeckBoss.battled || battles != DeckBoss.battlesAt))
		{
		if (DeckBoss.inBattle != 0)
			DeckBoss.over := 1
		DeckBoss.battled := 0, DeckBoss.battlesAt := battles, DeckBoss.inBattle := "", DeckBoss.seenAt := dblNow
		}
	dblGoal := (WkGoalLineAt && dblNow - WkGoalLineAt < 30000) ? WkGoalLine : ""
	dblMobs := NavMobs.Call(dblGoal)
	;(not read - the helper busy, an ERR, navmem off: as it is - no switching on a missed reading; 60 in a row, about 2
	;minutes - the helper stopped for good: let go)
	if (!IsObject(dblMobs))
		{
		if (IsObject(DeckBoss))
			{
			DeckBoss.misses := (DeckBoss.misses ? DeckBoss.misses : 0) + 1
			if (DeckBoss.misses >= 60)
				{
				DebugLog("Deck: no boss ahead now - " DeckBoss.name " (the zone's mobs not read for 2 minutes: " NavMobsWhy ")")
				DeckBoss := ""
				}
			}
		return
		}
	if (IsObject(DeckBoss))
		DeckBoss.misses := 0
	dblHit := DeckBossFind(dblMobs, IsObject(DeckBoss) ? DeckBoss.key : "")
	if (IsObject(dblHit))
		{
		if (IsObject(DeckBoss) && DeckBoss.key = dblHit.key)
			{
			DeckBoss.seenAt := dblNow, DeckBoss.over := 0, DeckBoss.dist := dblHit.dist, DeckBoss.misses := 0
			if (DeckBoss.why != dblHit.why)
				DeckBoss.why := dblHit.why, DeckBoss.order := dblHit.order
			return
			}
		dblHit.since := dblNow, dblHit.seenAt := dblNow, dblHit.battlesAt := battles, dblHit.battled := 0, dblHit.inBattle := "", dblHit.over := 0, dblHit.misses := 0
		if (IsObject(DeckBoss))
			DebugLog("Deck: no boss ahead now - " DeckBoss.name " (another one is: " dblHit.name ")")
		DeckBoss := dblHit
		DebugLog("Deck: a boss ahead - " dblHit.text " (" (dblHit.health != "" ? dblHit.health " health" : "health not known") (dblHit.school != "" ? ", " dblHit.school : "")
			. (dblHit.dist != "" ? ", " Round(dblHit.dist) " away" : "") "): " dblHit.why " (the game's memory)")
		DeckBeatBoss(dblHit)
		return
		}
	if (!IsObject(DeckBoss))
		return
	;(not ahead now: let go once that battle's over, else 30 s on - gone, or behind and far off)
	dblIn := DeckBossIn(dblMobs, DeckBoss)
	if (DeckBoss.over || dblNow - DeckBoss.seenAt >= 30000)
		{
		DebugLog("Deck: no boss ahead now - " DeckBoss.name (DeckBoss.over ? (dblIn ? " (its battle's over)" : " is gone (its battle's over)")
			: dblIn ? " is behind or far off (30 s)" : " is gone (30 s)"))
		DeckBoss := ""
		}
	}

;The boss ahead among the zone's mobs (NavMobs'), or "": a boss or a counted Elite (DeckMobKind) the quest's goal names
;(the walker's goal line - the game's memory's, else the screen's - read in the last 30 s), the helper's quest mob by
;its name or its goal (the walker goes to it - named: not 0; an older helper's, no named field: its quest flag alone),
;or one a dungeon run's way leads to (DeckDgAhead). Of several, the first of those reasons, a boss before an Elite, the
;one held already (holdKey: no swapping between two), then the nearest
DeckBossFind(dbfMobs, holdKey := "")
	{
	dbfGoal := (WkGoalLine != "" && WkGoalLineAt && A_TickCount - WkGoalLineAt < 30000) ? DeckLetters(WkGoalLine) : ""
	dbfBest := ""
	for dbfI, dbfM in dbfMobs
		{
		dbfNote := ""
		dbfKind := DeckMobKind(dbfM.boss, dbfM.title, dbfM.health, &dbfNote)
		if (dbfKind = "")
			continue
		dbfKey := DeckLetters(dbfM.name)
		dbfWhy := "", dbfOrder := 0
		if (dbfGoal != "" && StrLen(dbfKey) >= 4 && InStr(dbfGoal, dbfKey))
			dbfWhy := "the quest's goal names it", dbfOrder := 4
		;(the helper's quest flag takes a same-family mob anywhere in the zone too - "Gobbler King" for "Defeat Gobblers":
		;named 0 is that, not the walker's)
		else if (dbfM.quest && dbfM.named != 0)
			dbfWhy := "the quest's mob (the walker goes to it)", dbfOrder := 3
		else if (IsObject(DgRun) && DeckDgAhead(dbfM))
			dbfWhy := "the dungeon run's way leads to it", dbfOrder := 2
		if (!dbfOrder)
			continue
		dbfId := dbfM.gid != "" ? dbfM.gid : dbfM.name
		dbfScore := dbfOrder * 10 + (dbfKind = "boss" ? 2 : 0) + (holdKey != "" && dbfId = holdKey ? 1 : 0)
		if (IsObject(dbfBest) && (dbfScore < dbfBest.score || (dbfScore = dbfBest.score && (dbfM.dist = "" || (dbfBest.dist != "" && dbfM.dist >= dbfBest.dist)))))
			continue
		dbfBest := V1Obj({key: dbfId, name: dbfM.name, gid: dbfM.gid, title: dbfM.title, rank: dbfM.rank, health: dbfM.health, school: dbfM.school
			, kind: dbfKind, why: dbfWhy, order: dbfOrder, score: dbfScore, dist: dbfM.dist, x: dbfM.x, y: dbfM.y, text: DeckBossText(dbfM.name, dbfM.rank, dbfKind, dbfNote)})
		}
	return dbfBest
	}

;The boss b still among the zone's mobs (by its gid, else its name)
DeckBossIn(dbiMobs, dbiB)
	{
	for dbiI, dbiM in dbiMobs
		if ((dbiB.gid != "" && dbiM.gid = dbiB.gid) || (dbiB.gid = "" && dbiM.name = dbiB.name))
			return true
	return false
	}

;What a mob is for the decks: "boss" (the game's own boss flag, or its title Boss), "elite" (its title Elite and its max
;health takes 3 or more of your best hits - DeckBestHit: note says how many), else "" (an Elite under 3 hits, or your best
;hit not known: not counted)
DeckMobKind(dmkBoss, dmkTitle, dmkHealth, &dmkNote := "")
	{
	dmkNote := ""
	if (dmkBoss = 1 || dmkTitle = "Boss")
		return "boss"
	if (dmkTitle != "Elite" || dmkHealth = "" || dmkHealth <= 0)
		return ""
	dmkBest := DeckBestHit()
	if (dmkBest = "" || dmkBest <= 0)
		return ""
	dmkHits := Ceil(dmkHealth / dmkBest)
	if (dmkHits < 3)
		return ""
	dmkNote := " (" dmkHealth " health - " dmkHits " of your best hits, " dmkBest ")"
	return "elite"
	}

;Your best hit, as the deck you'd fight it with deals it - the deck picked as if there were no boss (DeckPick noBoss):
;its strongest hit at its best with the boosts it plays, no critical (DeckDamage hiNoCrit) - "" not known. Kept 30 s
DeckBestHit()
	{
	static dbhAt := 0, dbhKeep := ""
	if (dbhAt && A_TickCount - dbhAt < 30000)
		return dbhKeep
	dbhAt := A_TickCount
	dbhP := DeckPick(inbattle = 1, true)
	dbhR := DeckDamage(dbhP.deck)
	dbhKeep := (dbhR.none || dbhR.hiNoCrit = "") ? "" : dbhR.hiNoCrit
	return dbhKeep
	}

;"Governor Nereus, rank 9 boss" (note: an Elite's hits)
DeckBossText(dbtName, dbtRank, dbtKind, dbtNote := "")
	{
	return (dbtName != "" ? dbtName : "an enemy") (dbtRank != "" ? ", rank " dbtRank : "") " " dbtKind dbtNote
	}

;Just the letters of a name, in capitals (the walker's WalkLetters when it's there - OCR's digit slips put right)
DeckLetters(dlText)
	{
	if (V1IsFunc("WalkLetters"))
		return WalkLetters.Call(dlText)
	dlText := StrUpper(dlText)
	return RegExReplace(dlText, "[^A-Z]")
	}

;The dungeon run's way leads to mob m: a step still to walk in the zone of the one walked to (the steps in a row there)
;within 1000 of it
DeckDgAhead(ddaM)
	{
	if (!IsObject(DgRun) || !IsObject(DgRun.steps) || ddaM.x = "" || ddaM.y = "")
		return false
	;(v1: a blank i compared with 1 as text - not >= 1)
	ddaI := V1Ge(DgRun.i, 1) ? DgRun.i : 1
	if (ddaI > DgRun.steps.Length)
		return false
	ddaZone := DgRun.steps[ddaI].zone
	while (ddaI <= DgRun.steps.Length && DgRun.steps[ddaI].zone = ddaZone)
		{
		ddaS := DgRun.steps[ddaI]
		;(v1: a step with no x or y made the distance blank, and a blank <= 1000000 was TRUE - compared as text)
		ddaDx := V1Sub(ddaS.x, ddaM.x), ddaDy := V1Sub(ddaS.y, ddaM.y)
		if (V1Le(V1Add(V1Mul(ddaDx, ddaDx), V1Mul(ddaDy, ddaDy)), 1000000))
			return true
		ddaI += 1
		}
	return false
	}

;A battle round (DeckRound): the battle's enemies from the game's memory (NavBattle) - DeckFoe the boss among them (a boss
;first, then the Elite with the most health that counts - DeckMobKind), "" none; the boss ahead's place in it noted
;(DeckBoss.inBattle). Not read: the boss ahead it was walked into (DeckBoss), if any - DeckFoeKnown stays 0 (looked for
;again next round)
DeckFoeLook()
	{
	global DeckFoe, DeckFoeKnown ; (v1 globals it sets)
	dflB := V1IsFunc("NavBattle") ? NavBattle.Call() : ""
	if (!IsObject(dflB))
		{
		if (IsObject(DeckBoss))
			{
			DeckFoe := V1Obj({name: DeckBoss.name, kind: DeckBoss.kind, text: DeckBoss.text, max: DeckBoss.health, gid: DeckBoss.gid, from: "walk"})
			DeckBoss.battled := 1
			}
		return false
		}
	dflBest := "", dflSaid := "", dflAll := 1
	for dflI, dflF in dflB.foes
		{
		;(a foe whose title isn't known yet - its mob not joined: an Elite can't be told - looked at again next round)
		if (dflF.title = "" && dflF.boss != 1)
			dflAll := 0
		dflSaid .= (dflSaid = "" ? "" : ", ") (dflF.name != "" ? dflF.name : "?") " (" (dflF.title != "" ? dflF.title : dflF.boss = 1 ? "boss" : "?")
			. (dflF.rank != "" ? " rank " dflF.rank : "") ", " dflF.health "/" dflF.max ")"
		dflNote := ""
		dflKind := DeckMobKind(dflF.boss, dflF.title, dflF.max, &dflNote)
		if (dflKind = "")
			continue
		if (IsObject(dflBest) && (dflKind != dflBest.kind ? dflKind != "boss" : (dflF.max = "" || (dflBest.max != "" && dflF.max <= dflBest.max))))
			continue
		dflBest := V1Obj({name: dflF.name, kind: dflKind, max: dflF.max, gid: dflF.gid, from: "memory", text: DeckBossText(dflF.name, dflF.rank, dflKind, dflNote)})
		}
	DeckFoe := dflBest
	;(known: a boss among them, or every one's title read - else looked at again next round, its first 3 at most)
	DeckFoeKnown := (IsObject(dflBest) && dflBest.kind = "boss") || (dflAll && dflB.foes.Length) ? 1 : 0
	DebugLog("  Deck: the battle's enemies (the game's memory): " (dflSaid != "" ? dflSaid : "none read") (IsObject(dflBest) ? " - a " dflBest.kind ": " dflBest.name : "")
		. (DeckFoeKnown ? "" : " (not all known yet - looked at again next round)"))
	if (IsObject(DeckBoss))
		{
		dflIn := 0
		for dflI, dflF in dflB.foes
			if ((DeckBoss.gid != "" && dflF.gid = DeckBoss.gid) || (DeckBoss.gid = "" && dflF.name != "" && dflF.name = DeckBoss.name))
				dflIn := 1
		DeckBoss.inBattle := dflIn, DeckBoss.battled := 1
		}
	return true
	}

;---- The Cards tab's deck views (Dashboard.ahk makes the controls) ----

;The row's buttons named after the decks (at most 6 - "+ Deck" hidden then)
DeckButtonsShow()
	{
	if (!DashHwnd || !IsObject(DeckList))
		return
	Loop 6
		{
		if (A_Index <= DeckList.Length)
			{
			Dash["DeckView" A_Index].Text := SubStr(DeckList[A_Index].name, 1, 14)
			Dash["DeckView" A_Index].Visible := true
			}
		else
			Dash["DeckView" A_Index].Visible := false
		}
	Dash["DeckAddBtn"].Visible := (DeckList.Length >= 6) ? false : true
	}

DeckHandCtrls()
	{
	return ["DashHandHead", "DashLearnBtn", "DashFoeHead", "DashFoeList"]
	}

DeckFormCtrls()
	{
	return ["DeckFNameT", "DeckFName", "DeckFSchoolT", "DeckFSchool", "DeckFSetT", "DeckFSet", "DeckFSetN", "DeckFWhenT", "DeckFWDefault"
		, "DeckFWCollect", "DeckFWBoss", "DeckFWDungeon", "DeckFWFarm", "DeckFPriT", "DeckFPri", "DeckFPin", "DeckFSave", "DeckFCopy", "DeckFDel"
		, "DeckFDmg", "DeckFList", "DeckFValT", "DeckFVal", "DeckFValSet", "DeckFValClear", "DeckFNote", "DeckGameBtn"]
	}

;One of the Cards tab's views up: 0 the hand and the enemies, n the n-th deck (its form filled from a copy of it)
DeckViewShow(n)
	{
	global DeckView ; (v1 globals it sets)
	if (!DashHwnd)
		return
	if (!IsObject(DeckList))
		DeckLoadAll()
	if (n > DeckList.Length)
		n := 0
	DeckView := n
	;(v1's GuiControl on a control that isn't there - a 7th deck - did nothing; v2 throws)
	try Dash["DeckView" n].Value := 1
	for i, c in DeckHandCtrls()
		Dash[c].Visible := n ? false : true
	Loop 7
		{
		;(v1: IsObject(DashCardWant) && DashCardWant[...] - a missing one blank)
		p := V1At(DashCardWant, "p" A_Index), t := V1At(DashCardWant, "t" A_Index)
		Dash["DashCardPic" A_Index].Visible := (!n && p) ? true : false
		Dash["DashCardTxt" A_Index].Visible := (!n && t) ? true : false
		}
	for i, c in DeckFormCtrls()
		Dash[c].Visible := n ? true : false
	if (n)
		DeckFormFill(DeckCopy(DeckList[n]))
	}

;A deck's copy - edits go to it, not to the deck in use, till Save
DeckCopy(d)
	{
	c := d.Clone()
	c.when := d.when.Clone(), c.vals := d.vals.Clone()
	return c
	}

;The deck view's fields and settings list from deck d (the copy being edited)
DeckFormFill(d)
	{
	global DeckEdit ; (v1 globals it sets)
	DeckEdit := d
	Dash["DeckFName"].Value := d.name
	;(v1's ChooseString: no item starting so - nothing chosen, ErrorLevel 1; v2 may throw)
	try Dash["DeckFSchool"].Choose(d.school)
	Dash["DeckFSet"].Value := d.eqset
	Dash["DeckFPri"].Value := d.priority
	for k, c in V1Obj({default: "DeckFWDefault", collect: "DeckFWCollect", boss: "DeckFWBoss", dungeon: "DeckFWDungeon", farm: "DeckFWFarm"})
		Dash[c].Value := d.when[k] ? 1 : 0
	pin := IniRead(A_ScriptDir "\dashboard.ini", "decks", "pin", A_Space)
	Dash["DeckFPin"].Value := pin = d.id ? 1 : 0
	Dash["DeckFDmg"].Text := DeckDamageText(d) DeckBeatLine(d)
	DeckListFill(d)
	Dash["DeckFNote"].Text := IsObject(DeckNow) && DeckNow.id = d.id ? "In use now (" DeckWhy ")" : ""
	}

;A setting's value in words: on/off, a pick's name, a number
DeckValText(s, v)
	{
	if (v = "")
		return ""
	if (s.kind = "check")
		return v ? "on" : "off"
	;(v1's picks.HasKey(v): an item there by its number - V1At, not v2's Has, which takes 1.5 for 1. A float - "2.0" set,
	;a deck's "2.000000" - was a text key to v1's HasKey, never found: no "." in it)
	if (s.kind = "pick" && IsObject(s.picks) && !InStr(v, ".") && V1At(s.picks, v) != "")
		return v " - " V1At(s.picks, v)
	return v
	}

;The settings list: every setting a deck may have - this deck's ("" not its own), and everywhere else's (your school's or
;the plain one)
DeckListFill(d)
	{
	;(v1: Gui, Dash:Default, its ListView DeckFList made the default one and the one before put back after - v2 names the
	;control)
	LV := Dash["DeckFList"]
	LV.Opt("-Redraw")
	LV.Delete()
	sch := d.school != "any" ? d.school : V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	for i, k in DeckKeys()
		{
		s := DeckKeyInfo(k)
		mine := d.vals.Has(k) ? DeckValText(s, d.vals[k]) : ""
		other := (sch != "" && Stats.Has(sch "." k)) ? Stats[sch "." k] : Stats.Has(k) ? Stats[k] : s.def
		LV.Add("", s.label, mine, DeckValText(s, other), k)
		}
	LV.Opt("+Redraw")
	}

;The key of the setting picked in the list ("" none)
DeckListKey(&row := 0)
	{
	;(v1: Gui, Dash:Default and its ListView DeckFList, the one before put back after - v2 names the control)
	LV := Dash["DeckFList"]
	row := LV.GetNext(0), key := ""
	if (row)
		key := LV.GetText(row, 4)
	return key
	}

;The deck view's fields into the copy being edited
DeckFormRead()
	{
	d := DeckEdit
	if (!IsObject(d))
		return ""
	v := Dash["DeckFName"].Value
	d.name := Trim(SubStr(RegExReplace(v, "[^\x20-\x7E]|\|", ""), 1, 30))
	d.name := d.name != "" ? d.name : d.id
	;(a DropDownList without AltSubmit: v1's GuiControlGet gave its text)
	v := Dash["DeckFSchool"].Text
	d.school := v != "" ? v : "any"
	v := Dash["DeckFSet"].Value
	d.eqset := RegExMatch(v, "^[0-9]$") ? v + 0 : 0
	v := Dash["DeckFPri"].Value
	d.priority := RegExMatch(v, "^-?\d{1,3}$") ? v + 0 : 0
	d.when := V1Obj()
	for k, c in V1Obj({default: "DeckFWDefault", collect: "DeckFWCollect", boss: "DeckFWBoss", dungeon: "DeckFWDungeon", farm: "DeckFWFarm"})
		{
		v := Dash[c].Value
		if (v)
			d.when[k] := 1
		}
	return d
	}

DeckSay(text)
	{
	Dash["DeckFNote"].Text := text
	}

;A new deck's id (its file's name): when it was made - never a deleted deck's (a dungeon run naming that one would take
;the new one for it), and in the order made
DeckNewId()
	{
	id := "deck" A_Now
	Loop 99
		{
		if (!FileExist(DeckDir() "\" id ".txt"))
			return id
		id := "deck" A_Now "_" A_Index
		}
	return "deck" A_Now A_TickCount
	}

;---- The Cards tab's buttons (v1: g-labels - Dashboard.ahk's controls run them) ----
;(v2 port: each was a label - its own thread, in the global scope: global first, the interrupted thread's ErrorLevel kept
;as v1 did. Dashboard.ahk binds them as Fn.Bind("Normal") on Click - A_GuiControl is then the control - and DeckFList's
;as DeckListEvent.Bind("I") on ItemSelect)

DeckViewClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	global
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	A_GuiControl := V1GuiName(A_GuiControl)  ; (v1: the control's v-name, else its text)
	DeckViewShow(SubStr(A_GuiControl, 9) + 0)
	}

;(a setting picked: its value for this deck in the box. v1: the ListView's "I" event with S - or s: InStr isn't
;case-sensitive - in its ErrorLevel, an item selected or deselected; v2's ItemSelect, bound as "I")
DeckListEvent(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	global
	if (A_GuiEvent = "I" && IsObject(DeckEdit))
		{
		DeckKey := DeckListKey()
		Dash["DeckFVal"].Value := DeckKey != "" && DeckEdit.vals.Has(DeckKey) ? DeckEdit.vals[DeckKey] : ""
		}
	}

DeckValSet(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	DeckValSetClear("DeckValSet")
	}

DeckValClear(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	DeckValSetClear("DeckValClear")
	}

;(v1: the labels DeckValSet and DeckValClear - one body, told apart by A_ThisLabel)
DeckValSetClear(thisLabel)
	{
	global
	DeckKey := DeckListKey()
	if (DeckKey = "" || !IsObject(DeckEdit))
		{
		DeckSay("Pick a setting in the list first")
		return
		}
	;(yours from now on: never changed by learning from the game again - DeckUnlearn)
	DeckUnlearn(DeckEdit, DeckKey, thisLabel = "DeckValClear")
	if (thisLabel = "DeckValClear")
		DeckEdit.vals.Delete(DeckKey), DeckSay(DeckKey ": not set by this deck - Save to keep it")
	else
		{
		DeckV := Dash["DeckFVal"].Value
		DeckS := DeckKeyInfo(DeckKey)
		DeckV := Trim(DeckV)
		DeckLo := DeckS.kind = "check" ? 0 : DeckS.kind = "pick" ? 1 : DeckS.lo, DeckHi := DeckS.kind = "check" ? 1 : DeckS.kind = "pick" ? DeckS.picks.Length : DeckS.hi
		if (!RegExMatch(DeckV, "^-?\d+(\.\d+)?$") || (DeckLo != "" && DeckV < DeckLo) || (DeckHi != "" && DeckV > DeckHi))
			{
			DeckSay(DeckS.label ": " (DeckS.kind = "check" ? "1 (on) or 0 (off)" : DeckLo " to " DeckHi))
			return
			}
		DeckEdit.vals[DeckKey] := DeckNum(DeckV), DeckSay(DeckKey " " DeckNum(DeckV) " for this deck - Save to keep it")
		}
	DeckListFill(DeckEdit)
	Dash["DeckFDmg"].Text := DeckDamageText(DeckEdit)
	}

DeckSaveClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	global
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	DeckD := DeckFormRead()
	if (!IsObject(DeckD))
		return
	DeckPinOn := Dash["DeckFPin"].Value
	DeckPinWas := IniRead(A_ScriptDir "\dashboard.ini", "decks", "pin", A_Space)
	if (DeckPinOn)
		V1Do(IniWrite, DeckD.id, A_ScriptDir "\dashboard.ini", "decks", "pin")
	else if (DeckPinWas = DeckD.id)
		V1Do(IniDelete, A_ScriptDir "\dashboard.ini", "decks", "pin")
	if (DeckSave(DeckD))
		{
		;(read again from the files at once - the deck in use too - and the pick made afresh out of battle: DeckTick)
		DeckLoadAll(), DeckDirty := 0
		DeckButtonsShow()
		n := DeckIndexOf(DeckD.id)
		if (n)
			DeckFormFill(DeckCopy(DeckList[n]))
		DeckSay("Saved - " (inbattle = 1 ? "used from the next battle" : "used from now on"))
		DebugLog("Decks: " DeckD.name " saved (" DeckD.file ")")
		}
	else
		DeckSay("Couldn't write " DeckD.file)
	}

DeckCopyClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	DeckAddCopy("DeckCopyClick")
	}

DeckAddClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	DeckAddCopy("DeckAddClick")
	}

;(v1: the labels DeckCopyClick and DeckAddClick - one body, told apart by A_ThisLabel)
DeckAddCopy(thisLabel)
	{
	global
	if (!IsObject(DeckList))
		DeckLoadAll()
	if (DeckList.Length >= 6)
		{
		DeckSay("Six decks at most on the tab - delete one first")
		return
		}
	DeckId := DeckNewId()
	if (thisLabel = "DeckCopyClick" && IsObject(DeckEdit))
		DeckD := DeckCopy(DeckFormRead()), DeckD.name := SubStr(DeckD.name " copy", 1, 30), DeckD.game := "", DeckD.learned := ""
	else
		DeckD := V1Obj({name: "New deck", school: "any", eqset: 0, when: V1Obj(), priority: 0, vals: V1Obj()})
	DeckD.id := DeckId, DeckD.file := DeckDir() "\" DeckId ".txt"
	DeckSave(DeckD), DeckLoadAll(), DeckButtonsShow()
	DeckViewShow(DeckIndexOf(DeckId))
	DeckSay("Made - set what it's for and its settings, then Save")
	}

DeckDelClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	global
	local v1KeepG := V1Thread(), msgResult  ; (v1: a g-label - its own thread and ErrorLevel)
	if (!IsObject(DeckEdit))
		return
	msgResult := MsgBox("Delete the deck '" DeckEdit.name "'? Its file goes (" DeckEdit.file "); your Settings aren't touched.", "Decks", 262180)
	if (msgResult = "No")
		return
	V1Do(FileDelete, DeckEdit.file)
	DeckPinWas := IniRead(A_ScriptDir "\dashboard.ini", "decks", "pin", A_Space)
	if (DeckPinWas = DeckEdit.id)
		V1Do(IniDelete, A_ScriptDir "\dashboard.ini", "decks", "pin")
	DebugLog("Decks: " DeckEdit.name " deleted")
	DeckEdit := "", DeckLoadAll(), DeckButtonsShow()
	DeckViewShow(0)
	}

;---- Decks learned from the game (v1.0.0, TODO goal 3) ----
;
;The helper's /decks (READ-ONLY - vision\deckmem.py: every deck the wizard owns, the backpack's too, each card's kind
;from its effects; vision\battlesim.py learn_decks) answers a "learn" line for each in-game deck in an Equipment Set:
;learn|gid|name|school|eqset|when|k=v,...|why. Each becomes a deck here: the one linked to it (game|<gid> in its file),
;else one with no link on that Equipment Set (and its school, or any), else a new one (six decks at most on the tab: no
;room - said, not made). Linked: its Equipment Set follows the game's (the set that puts that deck on), its school is
;filled in when it's "any", and its learned settings (learned| in the file) follow the cards - a setting you set yourself
;(one not in learned|) is never changed or cleared; a new deck takes its name and what it's for too. manual: the Cards
;tab's button (said there; a refusal - in a battle, the helper off - too). Returns the lines it logged ("" none read)
DeckLearnGame(manual := false)
	{
	global DeckLearnAt, DeckLearnSaid ; (v1 globals it sets)
	DeckLearnAt := A_TickCount
	if (!IsObject(DeckList))
		DeckLoadAll()
	dlgWhy := ""
	if (!Stat("navmem"))
		dlgWhy := "navmem:0 in PlayerStats.txt"
	else if (!VisionOn)
		dlgWhy := "the vision helper isn't running"
	else if (dualmode == 1)
		dlgWhy := "dual mode: the game's memory is one client's"
	else if (inbattle = 1 || (V1IsFunc("BattleLogInBattle") && BattleLogInBattle.Call()))
		dlgWhy := "in a battle - out of battle only"
	if (dlgWhy != "")
		{
		DeckLearnSaid := "Decks from the game: not read - " dlgWhy
		if (manual)
			DebugLog(DeckLearnSaid)
		return ""
		}
	;(a fresh read - paced by the helper, refused in a battle; the first one reads every card's effects: a few seconds)
	dlgAns := VisionGet("/decks?fresh=1&ob=1", 9000, true)
	if (dlgAns = "" || SubStr(dlgAns, 1, 5) = "none|")
		{
		DeckLearnSaid := "Decks from the game: not read - " (dlgAns != "" ? SubStr(Trim(dlgAns, " `r`n"), 6) : VisionErr != "" ? VisionErr : "no answer")
		if (manual)
			DebugLog(DeckLearnSaid)
		return ""
		}
	dlgOut := "", dlgN := 0, dlgMade := 0, dlgChanged := 0, dlgFull := ""
	Loop Parse, dlgAns, "`n", "`r"
		{
		dlgF := StrSplit(A_LoopField, "|")
		if (V1At(dlgF, 1) != "learn" || dlgF.Length < 8)
			continue
		dlgN += 1
		dlgL := V1Obj({gid: StrLower(Trim(dlgF[2])), name: Trim(SubStr(RegExReplace(dlgF[3], "[^\x20-\x7E]"), 1, 30)), school: Trim(dlgF[4])
			, eqset: RegExMatch(Trim(dlgF[5]), "^[1-9]$") ? Trim(dlgF[5]) + 0 : 0, when: Trim(dlgF[6]), vals: V1Obj(), why: Trim(dlgF[8])})
		if (!RegExMatch(dlgL.gid, "^[0-9a-f]{1,16}$"))
			continue
		Loop Parse, dlgF[7], ","
			if (RegExMatch(A_LoopField, "^(\w+)=(-?\d+(?:\.\d+)?)$", &dlgM))
				dlgL.vals[StrLower(dlgM[1])] := dlgM[2] + 0
		dlgNew := false
		dlgSaid := DeckLearnOne(dlgL, &dlgNew)
		if (dlgSaid = "full")
			{
			dlgFull .= (dlgFull = "" ? "" : ", ") dlgL.name
			continue
			}
		if (dlgNew)
			dlgMade += 1
		else if (dlgSaid != "")
			dlgChanged += 1
		if (dlgSaid != "")
			{
			DebugLog("Decks from the game: " dlgSaid)
			dlgOut .= dlgSaid "`n"
			}
		}
	if (dlgFull != "")
		DebugLog("Decks from the game: no room for " dlgFull " (six decks at most on the Cards tab - delete one to make room)")
	DeckLearnSaid := "Decks from the game: " dlgN " in an Equipment Set read" (dlgMade ? ", " dlgMade " made" : "") (dlgChanged ? ", " dlgChanged " brought up to date" : "")
		. (!dlgMade && !dlgChanged ? " - nothing new" : "") (dlgFull != "" ? " (no room for " dlgFull ")" : "")
	if (manual || dlgMade || dlgChanged)
		DebugLog(DeckLearnSaid)
	if (dlgMade || dlgChanged)
		{
		DeckLoadAll()
		if (DashHwnd)
			DeckButtonsShow()
		}
	return dlgOut
	}

;One learned in-game deck L ({gid, name, school, eqset, when, vals, why}) into a deck here (see DeckLearnGame) - what
;changed in words ("" nothing), or "full" (a new one needed, six there already); isNew: it was made
DeckLearnOne(L, &isNew := false)
	{
	isNew := false
	dloD := ""
	for dloI, dloX in DeckList
		if (dloX.game = L.gid)
			dloD := dloX
	if (!IsObject(dloD) && L.eqset)
		for dloI, dloX in DeckList
			if (dloX.game = "" && dloX.eqset = L.eqset && (dloX.school = "any" || dloX.school = L.school))
				{
				dloD := dloX
				break
				}
	dloSay := []
	if (!IsObject(dloD))
		{
		if (DeckList.Length >= 6)
			return "full"
		dloId := DeckNewId()
		dloD := V1Obj({id: dloId, file: DeckDir() "\" dloId ".txt", name: L.name, school: L.school != "" ? L.school : "any", eqset: L.eqset
			, when: DeckWhenOf(L.when), priority: 0, vals: V1Obj(), game: L.gid, learned: ""})
		isNew := true
		;(on the list now: the six counted with it - DeckLoadAll reads them all again after)
		DeckList.Push(dloD)
		dloSay.Push("made " L.name " (Equipment Set " (L.eqset ? L.eqset : "none") ", for " (L.when != "" ? StrReplace(L.when, ",", ", ") : "nothing yet") ")")
		}
	else
		{
		;(work on a copy: the deck in use is only swapped for it by DeckLoadAll)
		dloD := DeckCopy(dloD)
		if (dloD.game != L.gid)
			dloD.game := L.gid, dloSay.Push(dloD.name " linked to the in-game deck " L.name)
		if (L.eqset && dloD.eqset != L.eqset)
			dloSay.Push(dloD.name "'s Equipment Set " dloD.eqset " -> " L.eqset " (the one that puts " L.name " on)"), dloD.eqset := L.eqset
		if (dloD.school = "any" && L.school != "" && L.school != "any")
			dloD.school := L.school, dloSay.Push(dloD.name " is for " L.school)
		}
	;(its settings: a learned one set or changed; a learned one the cards don't call for now cleared; yours never touched)
	dloLearned := V1Obj(), dloNo := V1Obj()
	Loop Parse, dloD.learned, ","
		if (SubStr(A_LoopField, 1, 1) = "!")
			dloNo[SubStr(A_LoopField, 2)] := 1
		else if (A_LoopField != "")
			dloLearned[A_LoopField] := 1
	dloKeys := V1Obj()
	for dloI, dloK in DeckKeys()
		dloKeys[dloK] := 1
	dloSet := ""
	for dloK, dloV in L.vals
		{
		if (!dloKeys.Has(dloK) || dloNo.Has(dloK))
			continue
		if (!dloD.vals.Has(dloK))
			dloD.vals[dloK] := dloV, dloLearned[dloK] := 1, dloSet .= (dloSet = "" ? "" : ", ") dloK ":" dloV
		else if (dloLearned.Has(dloK) && dloD.vals[dloK] != dloV)
			dloD.vals[dloK] := dloV, dloSet .= (dloSet = "" ? "" : ", ") dloK ":" dloV
		}
	dloGone := ""
	for dloK, dloV in dloLearned.Clone()
		if (!L.vals.Has(dloK))
			{
			dloD.vals.Delete(dloK), dloLearned.Delete(dloK)
			dloGone .= (dloGone = "" ? "" : ", ") dloK
			}
	if (dloSet != "")
		dloSay.Push(dloD.name ": " dloSet " (" L.why ")")
	if (dloGone != "")
		dloSay.Push(dloD.name ": " dloGone " back to your Settings (its cards call for them now)")
	dloList := ""
	for dloK, dloV in dloLearned
		dloList .= (dloList = "" ? "" : ",") dloK
	for dloK, dloV in dloNo
		dloList .= (dloList = "" ? "" : ",") "!" dloK
	dloD.learned := dloList
	if (!dloSay.Length)
		return ""
	DeckSave(dloD)
	dloText := ""
	for dloI, dloT in dloSay
		dloText .= (dloText = "" ? "" : "; ") dloT
	return dloText
	}

;A setting you set or cleared on the Cards tab is yours: taken out of deck d's learned list (learned|) - cleared, it's
;kept there as "!key": never learned again
DeckUnlearn(d, key, cleared)
	{
	duOut := ""
	Loop Parse, d.learned, ","
		if (A_LoopField != "" && A_LoopField != key && A_LoopField != "!" key)
			duOut .= (duOut = "" ? "" : ",") A_LoopField
	if (cleared && d.game != "")
		duOut .= (duOut = "" ? "" : ",") "!" key
	d.learned := duOut
	}

;Out of battle (DeckTick): the decks learned from the game once a while after the bot starts, then every 30 minutes - the
;bot on, the helper on, nothing loading, no dungeon run (a fresh read holds the helper a moment)
DeckLearnTick()
	{
	if (!BotOn || inbattle = 1 || WkLoading || IsObject(DgRun) || !VisionOn || !Stat("navmem"))
		return
	if (DeckLearnAt && A_TickCount - DeckLearnAt < 1800000)
		return
	DeckLearnGame(false)
	}

;The Cards tab's "From game" button
DeckGameClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *)
	{
	local v1KeepG := V1Thread()  ; (v1: a g-label - its own thread and ErrorLevel)
	DeckSay("Reading your decks from the game...")
	DeckLearnGame(true)
	DeckSay(DeckLearnSaid)
	if (DeckView)
		DeckViewShow(DeckView)
	}

;---- Can this deck beat it (v1.0.0, TODO goal 3) ----

;Deck d fought against foes ([{name, health, school, boss}]) in the battle simulator (the helper's /sim - vision\
;battlesim.py: its linked in-game deck's cards, your stats for its school, its settings): {word (yes / likely / risky /
;no), win, lost (0-1), rounds, text, boss (the first foe's name)} - kept in DeckBeats[d.id] - or "" (not linked to an
;in-game deck, the helper off, no answer: why says so)
DeckBeat(d, foes, &why := "")
	{
	global DeckBeats ; (v1 globals it sets)
	why := ""
	if (d.game = "")
		{
		why := "not linked to an in-game deck (the Cards tab's From game button)"
		return ""
		}
	if (!VisionOn || !Stat("navmem") || dualmode == 1)
		{
		why := !VisionOn ? "the vision helper isn't running" : dualmode == 1 ? "dual mode" : "navmem:0 in PlayerStats.txt"
		return ""
		}
	sch := d.school != "any" ? d.school : V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	dbF := ""
	for dbI, dbE in foes
		dbF .= (dbF = "" ? "" : "|") StrReplace(StrReplace(dbE.name, "|", " "), "~", " ") "~" dbE.health "~" dbE.school "~" (dbE.boss ? 1 : 0)
	dbHp := DeckStatFor(d, sch, "maxhealth")
	if (!dbHp && OwnHpMax)
		dbHp := OwnHpMax
	dbVals := DeckSimVals(d, sch)
	;(fresh=1: the decks read again only when the worn one changed - else the last reading; out of battle: ob=1)
	dbQ := "/sim?deck=" d.game "&foes=" NavUri(dbF) "&school=" sch "&n=300&vals=" NavUri(dbVals) (inbattle = 1 ? "" : "&fresh=1&ob=1")
	for dbI, dbK in [["hp", dbHp], ["damage", DeckStatFor(d, sch, "damage")], ["pierce", DeckStatFor(d, sch, "pierce")]
		, ["crit", DeckStatFor(d, sch, "critical")], ["block", DeckStatFor(d, sch, "block")], ["acc", DeckStatFor(d, sch, "accuracy")]]
		if (dbK[2] != "" && dbK[2] != 0)
			dbQ .= "&" dbK[1] "=" NavUri(dbK[2] "")
	dbAns := VisionGet(dbQ, 5000, true)
	if (dbAns = "" || SubStr(dbAns, 1, 5) = "none|")
		{
		why := dbAns != "" ? SubStr(Trim(dbAns, " `r`n"), 6) : VisionErr != "" ? VisionErr : "no answer"
		return ""
		}
	dbR := V1Obj({word: "", win: "", lost: "", rounds: "", text: "", boss: foes.Length ? foes[1].name : ""})
	Loop Parse, dbAns, "`n", "`r"
		{
		dbL := StrSplit(A_LoopField, "|")
		if (V1At(dbL, 1) = "sim" && dbL.Length >= 10)
			dbR.win := dbL[2] != "" ? dbL[2] / 100 : "", dbR.lost := dbL[3] != "" ? dbL[3] / 100 : "", dbR.rounds := dbL[5]
		else if (V1At(dbL, 1) = "verdict" && dbL.Length >= 3)
			dbR.word := dbL[2], dbR.text := dbL[3]
		}
	if (dbR.word = "" || dbR.win = "")
		{
		why := "the simulator's answer couldn't be read"
		return ""
		}
	if (!IsObject(DeckBeats))
		DeckBeats := V1Obj()
	DeckBeats[d.id] := dbR
	return dbR
	}

;A boss ahead b (DeckBossLook's): each deck for bosses linked to an in-game deck fought against it (DeckBeat) - logged,
;b.beat {deck id: result}; DeckPick then takes the one most likely to win it (DeckBetter). None likely to: said
DeckBeatBoss(b)
	{
	b.beat := V1Obj()
	sch := V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	dbbBest := "", dbbN := 0
	for dbbI, dbbD in IsObject(DeckList) ? DeckList : []
		{
		if (!dbbD.when.boss || dbbD.game = "" || !DeckFits(dbbD, sch))
			continue
		dbbR := DeckBeat(dbbD, [V1Obj({name: b.name, health: b.health, school: b.school, boss: b.kind = "boss" ? 1 : 0})], &dbbWhy)
		if (!IsObject(dbbR))
			{
			DebugLog("Deck: can " dbbD.name " beat " b.name "? not simulated - " dbbWhy)
			continue
			}
		dbbN += 1
		b.beat[dbbD.id] := dbbR
		DebugLog("Deck: can " dbbD.name " beat " b.name "? " dbbR.text)
		if (!IsObject(dbbBest) || dbbR.win > dbbBest.win)
			dbbBest := dbbR, dbbBest.deck := dbbD.name
		}
	if (dbbN && IsObject(dbbBest) && dbbBest.win < 0.65)
		DebugLog("Deck: no deck for bosses is likely to beat " b.name " - the best, " dbbBest.deck ", wins " Round(100 * dbbBest.win) "% in the simulator (a stronger deck, potions or a party?)")
	}

;Deck d's chance (0-1) to win against the boss ahead or in this battle (DeckBeatBoss's) - "" not simulated
DeckBeatWin(d)
	{
	dbwB := IsObject(DeckBoss) ? DeckBoss : ""
	if (!IsObject(dbwB) || !IsObject(V1At(dbwB, "beat")) || !dbwB.beat.Has(d.id))
		return ""
	return dbwB.beat[d.id].win
	}

;d is a better pick than best for use: a higher priority - for a boss, first a clearly better chance to win it (5 points
;or more in the simulator, both simulated against it: DeckBeatWin)
DeckBetter(d, best, use)
	{
	if (!IsObject(best))
		return true
	if (use = "boss")
		{
		dbW1 := DeckBeatWin(d), dbW2 := DeckBeatWin(best)
		if (dbW1 != "" && dbW2 != "" && Abs(dbW1 - dbW2) >= 0.05)
			return dbW1 > dbW2
		}
	return d.priority > best.priority
	}

;The Cards tab's line under a deck's damage: the simulator's last verdict for it ("" none), or that it isn't linked
DeckBeatLine(d)
	{
	if (IsObject(DeckBeats) && DeckBeats.Has(d.id))
		return "`nCan it beat " DeckBeats[d.id].boss ": " SubStr(DeckBeats[d.id].text, 1, 170)
	if (d.game = "")
		return "`nNot linked to an in-game deck - From game reads yours (the battle simulator needs its cards)"
	dblL := RegExReplace(RegExReplace(d.learned, "(^|,)![a-z0-9]+"), "^,+")
	return "`nLinked to its in-game deck (" d.game ") - learned from its cards: " (dblL != "" ? StrReplace(dblL, ",", ", ") : "nothing to set")
	}

;---- Decks matched to the zone's enemies (v1.0.0, TODO goal 3 - Settings: deckzone, off; not tried in the game) ----

;The deck DeckPick chose (p - {deck, why, boss}) swapped for the one the battle simulator says does best against the
;enemy groups fought most in this zone (the helper's /deckfor - vision\battlesim.py best_decks: each in-game deck in an
;Equipment Set fought against the battles recorded there, each with its deck profile's settings over yours
;- DeckSimVals; one with no profile: yours and the ones its cards call for): of your decks
;linked to an in-game deck (game| - the Cards tab's From game), for this school, for a use the one picked is for too
;(collect, farming, dungeon, anything else - none picked: any of those; never a boss's), the one that wins most often
;(1 point at least, else as often in a round fewer) - and only when it wins 5 points more than the one picked, or as
;often in a round fewer (the one picked not simulated: it's taken). Not: the setting off, the bot off, a boss ahead,
;the deck pinned on the Cards tab or a dungeon run's, the zone not known, no battle recorded there yet, the helper
;still working it out (asked again 10 s on - an answer kept for the zone 10 minutes, here and in the helper; a refresh
;keeps the last rows till new ones come, and the helper hands its old lines back while it works them out again). In a
;battle (inBattle - DeckRound): the answer kept only - nothing asked - and only while the pick's Equipment Set is the
;one put on last (its cards are the ones in hand). p as it was, else {deck, why, boss: 0}
DeckForZone(p, inBattle := false)
	{
	static dfzZone := "", dfzAt := 0, dfzAns := "", dfzSaid := "", dfzWait := 0
	if (!Stat("deckzone") || !BotOn || !IsObject(DeckList) || V1At(p, "boss") || !VisionOn || !Stat("navmem") || dualmode == 1)
		return p
	if (InStr(p.why, "pinned") || InStr(p.why, "dungeon run"))
		return p
	dfzZ := V1IsFunc("WalkZone") ? WalkZone.Call() : ""
	if (dfzZ = "")
		return p
	dfzSch := V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	;(asked again: another zone, 10 minutes on, or 10 s on while the helper was working it out - out of battle only)
	if (!inBattle && (dfzZ != dfzZone || A_TickCount - dfzAt > (dfzWait || SubStr(dfzAns, 1, 5) = "none|" || dfzAns = "" ? 10000 : 600000)))
		{
		dfzQ := "/deckfor?zone=" NavUri(dfzZ) "&school=" dfzSch "&n=60&vals=" NavUri(DeckSimVals("", dfzSch))
		;(each in-game deck's profile - the one this would put on, DeckSet: its own settings, laid over yours by the
		;helper - gid~key:value,... |...; the first profile per in-game deck that fits your school; its drawenchant
		;0 while drawing is off for the run, as DeckSimVals)
		dfzNoDraw := (DrawBroken != "" || (DrawEmptyAt && A_TickCount - DrawEmptyAt < 1800000))
		dfzDv := ""
		for dfzI, dfzD in DeckList
			{
			if (dfzD.game = "" || !DeckFits(dfzD, dfzSch) || InStr("|" dfzDv, "|" dfzD.game "~"))
				continue
			dfzOwn := ""
			if (IsObject(V1At(dfzD, "vals")))
				for dfzK2, dfzV2 in dfzD.vals
					dfzOwn .= (dfzOwn = "" ? "" : ",") dfzK2 ":" ((dfzK2 = "drawenchant" && dfzNoDraw) ? 0 : dfzV2)
			dfzDv .= (dfzDv = "" ? "" : "|") dfzD.game "~" dfzOwn
			}
		dfzQ .= "&dvals=" NavUri(dfzDv)
		for dfzI, dfzK in [["hp", "maxhealth"], ["damage", "damage"], ["pierce", "pierce"], ["crit", "critical"], ["block", "block"], ["acc", "accuracy"]]
			{
			dfzV := DeckStatFor("", dfzSch, dfzK[2])
			if (dfzK[1] = "hp" && !dfzV && OwnHpMax)
				dfzV := OwnHpMax
			if (dfzV != "" && dfzV != 0)
				dfzQ .= "&" dfzK[1] "=" NavUri(dfzV "")
			}
		dfzNew := VisionGet(dfzQ, 3000, true), dfzAt := A_TickCount
		;(the zone's last rows kept till an answer with rows replaces them: the helper still working it out
		;("none|working...") or no answer (a time-out while its thread works) keeps them - asked again 10 s on - so a
		;refresh never drops the zone's deck for a moment (DeckEquip would press DeckPick's set, then this one's again a
		;minute later); so does "none|not read yet" (the helper's decks not read since the game was started again - the
		;next /decks read answers); another zone, or the helper's own none| (nothing to simulate there), replaces them)
		dfzWait := (Trim(dfzNew) = "" || SubStr(dfzNew, 1, 12) = "none|working" || SubStr(dfzNew, 1, 17) = "none|not read yet") ? 1 : 0
		if (dfzZ != dfzZone || !dfzWait || !InStr("`n" dfzAns, "`ndeckfor|"))
			dfzAns := dfzNew
		dfzZone := dfzZ
		}
	if (dfzZ != dfzZone || dfzAns = "" || SubStr(dfzAns, 1, 5) = "none|")
		return p
	;(each in-game deck simulated: {its gid: {won (%), rounds, name}})
	dfzRes := V1Obj()
	Loop Parse, dfzAns, "`n", "`r"
		{
		dfzL := StrSplit(A_LoopField, "|")
		if (V1At(dfzL, 1) = "deckfor" && dfzL.Length >= 9 && V1IsNum(dfzL[4]))
			dfzRes[dfzL[2]] := V1Obj({won: dfzL[4] + 0, rounds: dfzL[5], name: dfzL[3]})
		}
	dfzCur := (IsObject(p.deck) && p.deck.game != "" && dfzRes.Has(p.deck.game)) ? dfzRes[p.deck.game] : ""
	dfzPick := "", dfzPickR := ""
	for dfzI, dfzD in DeckList
		{
		if (dfzD.game = "" || !dfzRes.Has(dfzD.game) || !DeckFits(dfzD, dfzSch))
			continue
		dfzSame := false
		for dfzJ, dfzU in ["collect", "farm", "dungeon", "default"]
			if (dfzD.when[dfzU] && (!IsObject(p.deck) || p.deck.when[dfzU]))
				dfzSame := true
		if (!dfzSame)
			continue
		if (!IsObject(dfzPickR) || DeckForBetter(dfzRes[dfzD.game], dfzPickR))
			dfzPick := dfzD, dfzPickR := dfzRes[dfzD.game]
		}
	if (!IsObject(dfzPick) || (IsObject(p.deck) && dfzPick.id = p.deck.id) || (IsObject(dfzCur) && !DeckForBetter(dfzPickR, dfzCur, 5)))
		return p
	;(in a battle: only while its in-game deck is the one on - the set put on last, DeckEquip's)
	if (inBattle)
		{
		dfzOn := IniRead(A_ScriptDir "\dashboard.ini", "decks", "eqset" (V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""), A_Space)
		if (!dfzPick.eqset || dfzOn = "" || dfzOn != dfzPick.eqset)
			return p
		}
	dfzWhy := "the simulator's pick for " dfzZ "'s enemies: " dfzPickR.won "% won" (dfzPickR.rounds != "" ? " in " dfzPickR.rounds " rounds" : "")
		. (IsObject(p.deck) ? " - " p.deck.name " " (IsObject(dfzCur) ? dfzCur.won "%" : "not simulated") : "") " (deckzone)"
	if (dfzSaid != dfzZ "|" dfzPick.id)
		dfzSaid := dfzZ "|" dfzPick.id, DebugLog("Deck: " dfzPick.name " - " dfzWhy)
	return V1Obj({deck: dfzPick, why: dfzWhy, boss: 0})
	}

;A /deckfor row r1 ({won (%), rounds}) beats r2 (DeckForZone): margin points (1 at least) more won, else about as many
;won (within that) in a round fewer
DeckForBetter(r1, r2, margin := 0)
	{
	dfbM := Max(margin, 1), dfbD := V1N(r1.won) - V1N(r2.won)
	if (dfbD >= dfbM)
		return true
	return Abs(dfbD) < dfbM && V1IsNum(r1.rounds) && V1IsNum(r2.rounds) && r2.rounds - r1.rounds >= 1
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
DecksBlank()
	{
	global DeckList := "", DeckNow := "", DeckWhy := "", DeckDirty := "", DeckEqAt := "", DeckDuel := "", DeckView := "", DeckBoss := ""
	global DeckLearnAt := "", DeckLearnSaid := "", DeckBeats := "", DeckGameBtn := ""
	global DeckFoe := "", DeckFoeTries := "", DeckFoeKnown := "", DeckEdit := "", DashCardWant := "", DeckView0 := "", DeckView1 := ""
	global DeckView2 := "", DeckView3 := "", DeckView4 := "", DeckView5 := "", DeckView6 := "", DeckAddBtn := "", DeckFNameT := "", DeckFName := ""
	global DeckFSchoolT := "", DeckFSchool := "", DeckFSetT := "", DeckFSet := "", DeckFSetN := "", DeckFWhenT := "", DeckFWDefault := ""
	global DeckFWCollect := "", DeckFWBoss := "", DeckFWDungeon := "", DeckFWFarm := "", DeckFPriT := "", DeckFPri := "", DeckFPin := ""
	global DeckFSave := "", DeckFCopy := "", DeckFDel := "", DeckFDmg := "", DeckFList := "", DeckFValT := "", DeckFVal := "", DeckFValSet := ""
	global DeckFValClear := "", DeckFNote := "", inbattle := ""
	}
