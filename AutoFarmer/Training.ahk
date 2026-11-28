; Training.ahk - TODO goal 4, card quests and spell learning (the AutoHotkey side): the spells your wizard knows watched,
; and the hooks where taking spell quests, spending training points at the trainers and putting new spells in the deck
; plug in once their windows have been seen in the game.
; AutoHotkey v2, written for v2 (v1 never had this: nothing here is ported); #Included by Autofarmer.ahk only.
;
; BUILT - READ ONLY (nothing is clicked, typed or sent to the game; nothing is spent): out of battle, the bot on, about
; every 10 minutes (Autofarmer.ahk's main loop, next to QsTick: TrainBookTick - the first ask 3 minutes in, none while a
; zone loads or a dungeon run is on, the walker's keys let go for it) the vision helper is asked for the
; spellbook - /book?fresh=1&ob=1, vision\deckmem.py book_lines: every spell the wizard knows, from the game's memory - and
; it's compared with learned\spellbook_<wizard>.txt (the wizard: its global id from the game's memory, /book's books|
; line - QuickSell.ahk's character key -, else the game's log's CharID). A spell that wasn't there is a NEW SPELL:
;   "Spells: new spell Thunder Snake (Storm, 1 pip, Damage) [tid 1001]"
; in debug.log, once, and it's added to the file (Damage: the spell's type as its template names it - /book is asked
; without kinds=1, which would look up every spell's effects the first time; a kind, handmem's, shown when there is one).
; The first look at a wizard only writes its file (nothing is new then); more than TrainBurst new at once are taken as
; known, quietly (one line: a misread, or another wizard's file).
;
; Settings (PlayerStats.txt, the Settings window's NEW SPELLS AND SPELL QUESTS - all three off by default, and none of
; their flows is built: each needs window names nobody has seen yet):
;   deckadd      new spells put in the deck - NOT BUILT (TrainDeckAdd's TODO). On: a new spell is also announced - a
;                tray tip and the Discord alert ("add it to a deck yourself") - and queued for the deck step
;                (TrainNewQueue). Off: the debug.log line only
;   trainspells  training points spent at the trainers by the plan (trainplans.txt, vision\spellplan.py) - NOT BUILT
;                (TrainRun's TODO): on, it's said once a run in debug.log, nothing else
;   spellquests  spell quests taken and done - NOT BUILT (TrainQuestTick's TODO): on, said once a run, nothing else
; With all three off the bot does exactly what it did before, but for the new-spell line and the file. With the spellbook
; not to be had (navmem:0, no helper or an older one, dual mode, a battle) nothing at all changes: said on the dashboard.
; Gold only, never Crowns: training points are never bought (the Crown Shop sells them), and no flow here may click a
; control with "Crowns" near it (Potions.ahk NoCrownsNear) - the TODOs below say where that check goes.

;(v2-only globals - declared here with no value: a top-level := in an #Included file never runs - TrainingBlank sets
;them blank, the entry script calls it first thing) When the spellbook was last asked for (A_TickCount) and how long till
;the next ask (ms); the dashboard's line; the wizard whose file was used last; the new spells last seen ("Thunder Snake
;(12:04)"); the new spells waiting for the deck step ([{tid, name, display, school, type, at}] - deckadd: their kinds
;asked for then, /book?kinds=1 - TrainDeckAdd's TODO; the wizard's own: emptied when another wizard is looked at); what
;was said once a run ({key: 1}); the reason the book wasn't read last logged (said again only when it changes)
global TrainBookAt, TrainBookWait, TrainBookSaid, TrainBookWho, TrainLastNew, TrainNewQueue, TrainSaidOnce, TrainBookWhy

;(v2 port, CONVENTIONS.md "Blank start": this file's globals start blank)
TrainingBlank()
	{
	global TrainBookAt := "", TrainBookWait := "", TrainBookSaid := "", TrainBookWho := "", TrainLastNew := ""
	global TrainNewQueue := "", TrainSaidOnce := "", TrainBookWhy := ""
	}

;(how often the spellbook is asked for: every 10 minutes; again in 2 when it couldn't be read; an older helper with no
;/book: in an hour; the first ask 3 minutes after the bot's first look out of battle - not on top of the start's other
;fresh reads, DeckLearnTick's /decks and the battle recorder's deck - and the most new spells at once that are said, more
;taken as known)
TrainEvery() => 600000
TrainRetry() => 120000
TrainFirst() => 180000
TrainBurst() => 8

;A setting of this file's on (1) - never throws
TrainOn(key)
	{
	tonV := 0
	try tonV := StatOr(key, 0)
	return V1IsNum(tonV) && tonV >= 1
	}

;The dashboard's Spells line ("" never asked): "142 known - new: Thunder Snake (12:04)", or "not read - <why>"
TrainStatus()
	{
	return TrainBookSaid
	}

;The main loop's tick out of battle (Autofarmer.ahk, next to QsTick - the bot on, the spellbook visible): the settings
;that aren't built said once a run, then - when it's time - the spellbook read and its new spells said. Never throws
TrainBookTick()
	{
	global TrainBookAt, TrainBookWait, TrainBookSaid, TrainBookWho, TrainLastNew, TrainNewQueue, TrainBookWhy ; (globals it sets)
	try
		{
		TrainNotBuilt()
		;(the first ask staggered - TrainFirst)
		if (TrainBookAt = "")
			{
			TrainBookAt := A_TickCount, TrainBookWait := TrainFirst()
			return
			}
		if (A_TickCount - TrainBookAt < V1N(TrainBookWait))
			return
		;(nothing loading, no dungeon run - DeckLearnTick's rule: a fresh read holds the main loop a moment; asked when
		;they're over, its time not moved)
		if (WkLoading || IsObject(DgRun))
			return
		TrainBookAt := A_TickCount, TrainBookWait := TrainRetry()
		tbtWhy := ""
		if (!Stat("navmem"))
			tbtWhy := "navmem:0 in PlayerStats.txt"
		else if (!VisionOn)
			tbtWhy := "the vision helper isn't running"
		else if (dualmode == 1)
			tbtWhy := "dual mode: the game's memory is one client's"
		else if (inbattle = 1 || (V1IsFunc("BattleLogInBattle") && BattleLogInBattle.Call()))
			tbtWhy := "in a battle - out of battle only"
		tbtBook := ""
		if (tbtWhy = "")
			{
			;(the walker's keys let go first - StatsAuto's and QsRun's way: W held through a read of a second or more is a
			;run nobody steers; the walker holds it again at its next step)
			if (KeysDown || HeldW)
				ReleaseKeys()
			tbtBook := TrainBookRead(&tbtWhy)
			}
		if (!IsObject(tbtBook))
			{
			;(an older helper - no /book: asked again in an hour; the reason logged only when it changes)
			if (InStr(tbtWhy, "unknown request"))
				TrainBookWait := 3600000
			if (tbtWhy != TrainBookWhy && !InStr(tbtWhy, "in a battle"))
				DebugLog("Spells: the spellbook not read - " tbtWhy)
			TrainBookWhy := tbtWhy, TrainBookSaid := "not read - " tbtWhy
			return
			}
		TrainBookWait := TrainEvery(), TrainBookWhy := ""
		tbtN := tbtBook.spells.Length
		;(whose spellbook: the wizard's global id from the game's memory, else the game's log's CharID)
		tbtWho := tbtBook.gid != "" ? tbtBook.gid : V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""
		if (tbtWho = "")
			{
			if (TrainBookSaid != tbtN " known (whose isn't known - not kept)")
				DebugLog("Spells: " tbtN " known, but whose spellbook it is isn't known (no wizard id in /book, no CharID in the game's log) - not kept, nothing said new")
			TrainBookSaid := tbtN " known (whose isn't known - not kept)"
			return
			}
		;(another wizard than the last one looked at - its first look too: the last one's new spells and deck queue aren't
		;this one's)
		if (tbtWho != TrainBookWho)
			TrainBookWho := tbtWho, TrainLastNew := "", TrainNewQueue := ""
		tbtPath := A_ScriptDir "\learned\spellbook_" tbtWho ".txt"
		tbtFailed := false
		tbtKnown := TrainBookLoad(tbtPath, &tbtFailed)
		;(its file there but not read - in use by another program a moment: not a first look - that wrote the whole book
		;again under a second note and took the newest spells as known; looked at again in TrainRetry's time, said once)
		if (tbtFailed)
			{
			TrainBookWait := TrainRetry()
			tbtSay := tbtN " known (learned\spellbook_" tbtWho ".txt couldn't be read - looked at again soon)"
			if (TrainBookSaid != tbtSay)
				DebugLog("Spells: " tbtN " known, but learned\spellbook_" tbtWho ".txt couldn't be read - nothing written, looked at again in " TrainRetry() // 60000 " minutes")
			TrainBookSaid := tbtSay
			return
			}
		if (!IsObject(tbtKnown))
			{
			;(the first look at this wizard: its file written, nothing new)
			tbtOk := TrainBookSave(tbtPath, tbtBook.spells, true)
			DebugLog("Spells: " tbtN " known - the first look at this wizard (" (tbtOk ? "learned\spellbook_" tbtWho ".txt written" : "learned\spellbook_" tbtWho ".txt couldn't be written") "); a new one is said from now on")
			TrainBookSaid := tbtN " known"
			return
			}
		tbtNew := []
		for tbtI, tbtS in tbtBook.spells
			if (!tbtKnown.Has(tbtS.tid))
				tbtNew.Push(tbtS)
		if (tbtNew.Length > TrainBurst())
			{
			TrainBookSave(tbtPath, tbtNew)
			DebugLog("Spells: " tbtNew.Length " new at once - taken as known, none said (a misread, or learned\spellbook_" tbtWho ".txt is another wizard's?)")
			}
		else if (tbtNew.Length)
			TrainNewSpells(tbtNew, tbtPath)
		TrainBookSaid := tbtN " known" (TrainLastNew != "" ? " - new: " TrainLastNew : "")
		}
	catch Any as e
		{
		try DebugLog("Spells: the spellbook look failed - " (IsObject(e) ? e.Message : e) " (nothing else changes)")
		TrainBookWait := TrainRetry()
		}
	}

;New spells (in the book's order) said and added to the wizard's file: each one's debug.log line; deckadd on - announced
;(a tray tip, the Discord alert) and queued for the deck step (TrainNewQueue, 20 at most - nothing reads it yet: the
;deck step isn't built)
TrainNewSpells(spells, path)
	{
	global TrainLastNew, TrainNewQueue ; (globals it sets)
	TrainBookSave(path, spells)
	tnsNames := "", tnsAt := FormatTime(, "HH:mm")
	tnsAdd := TrainOn("deckadd")
	if (!IsObject(TrainNewQueue))
		TrainNewQueue := []
	for tnsI, tnsS in spells
		{
		tnsName := tnsS.display != "" ? tnsS.display : tnsS.name
		tnsNames .= (tnsNames = "" ? "" : ", ") tnsName
		DebugLog("Spells: new spell " tnsName " (" (tnsS.school != "" ? tnsS.school : "?") ", " (tnsS.pips != "" ? tnsS.pips " pip" (tnsS.pips = 1 ? "" : "s") : "? pips") (tnsS.kind != "" ? ", " tnsS.kind : tnsS.type != "" ? ", " tnsS.type : "") ") [tid " tnsS.tid "]" (tnsAdd ? " - queued for the deck (deckadd: putting it in isn't built yet)" : ""))
		if (tnsAdd)
			{
			TrainNewQueue.Push(V1Obj({tid: tnsS.tid, name: tnsS.name, display: tnsS.display, school: tnsS.school, type: tnsS.type, at: A_Now}))
			while (TrainNewQueue.Length > 20)
				TrainNewQueue.RemoveAt(1)
			}
		}
	TrainLastNew := tnsNames " (" tnsAt ")"
	if (tnsAdd)
		{
		TrayTip("New spell" (spells.Length = 1 ? "" : "s") ": " tnsNames ". Putting new spells in the deck isn't built yet - add " (spells.Length = 1 ? "it" : "them") " to a deck yourself.", "Wizard101 bot", 1)
		AlertSend("spell", "a new spell", "Learned: " tnsNames ". The bot doesn't put spells in decks yet (deckadd isn't built) - add " (spells.Length = 1 ? "it" : "them") " to a deck yourself if you want " (spells.Length = 1 ? "it" : "them") " played.")
		}
	;TODO(deckadd - needs the game): TrainDeckAdd here, once the deck page's windows are known - see the TODOs at the end
	}

;The spellbook from the helper (/book?fresh=1&ob=1 - read now, out of battle: the bot's own check said so, ob=1): {spells
;[{tid, name, display, school, type, pips, kind}] in the game's order (kind blank: asked without kinds=1, which would look
;up every spell's effects the first time), n, gid (the wizard's global id, hex - "" not read), why}, or "" and why. A book
;of no spells is taken as not read (a wizard always knows some)
TrainBookRead(&why := "")
	{
	why := ""
	;(a fresh read - paced by the helper, refused in a battle; the first one looks up every spell's template: a second or
	;two - the next ones only the list)
	tbrAns := VisionGet("/book?fresh=1&ob=1", 9000, true)
	if (tbrAns = "")
		{
		why := VisionErr != "" ? RegExReplace(VisionErr, "^ERR\s*") : "no answer"
		return ""
		}
	tbr := V1Obj({spells: [], n: "", gid: "", why: ""})
	Loop Parse, tbrAns, "`n", "`r"
		{
		tbrF := StrSplit(A_LoopField, "|")
		tbrK := V1At(tbrF, 1)
		if (tbrK = "none")
			{
			why := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		;(book|tid|name|display|school|type|pips|xpip|retired|tier|kind|value - deckmem.book_lines)
		if (tbrK = "book" && tbrF.Length >= 12 && RegExMatch(Trim(tbrF[2]), "^\d+$"))
			tbr.spells.Push(V1Obj({tid: Trim(tbrF[2]), name: Trim(tbrF[3]), display: Trim(tbrF[4]), school: Trim(tbrF[5]), type: Trim(tbrF[6]), pips: Trim(tbrF[7]), kind: Trim(tbrF[11])}))
		;(books|spellbook n|treasure n|wizard gid hex|ms|why)
		else if (tbrK = "books" && tbrF.Length >= 6)
			tbr.n := Trim(tbrF[2]), tbr.gid := StrLower(Trim(tbrF[4])), tbr.why := Trim(tbrF[6])
		}
	if (!V1IsNum(tbr.n) || tbr.n < 1 || tbr.spells.Length < 1)
		{
		why := "the spellbook couldn't be read" (tbr.why != "" ? " (" tbr.why ")" : "")
		return ""
		}
	if (!RegExMatch(tbr.gid, "^[0-9a-f]{1,16}$"))
		tbr.gid := ""
	return tbr
	}

;The template ids a wizard's file holds ({tid: 1}), or "" when there's no file yet (its first look) - and "" with failed
;set when the file is there but couldn't be read (v2's Loop Read throws: in use by another program): never a first look
TrainBookLoad(path, &failed := false)
	{
	failed := false
	if (!FileExist(path))
		return ""
	tblK := V1Obj()
	try
		{
		Loop Read, path
			{
			if (RegExMatch(A_LoopReadLine, "^(\d+)\|", &tblM))
				tblK[tblM[1]] := 1
			}
		}
	catch
		{
		failed := true
		return ""
		}
	return tblK
	}

;Spells added to a wizard's file (first: the file begun, with its note - when each was first seen left blank: not
;known). True when written
TrainBookSave(path, spells, first := false)
	{
	tbsOut := first ? "; The spells this wizard knows, as the game's memory had them (Training.ahk - read only), one a line:`r`n; template id|name|display|school|first seen (blank: known at the first look)`r`n" : ""
	tbsAt := FormatTime(, "yyyy-MM-dd HH:mm")
	for tbsI, tbsS in spells
		tbsOut .= tbsS.tid "|" tbsS.name "|" tbsS.display "|" tbsS.school "|" (first ? "" : tbsAt) "`r`n"
	try
		{
		if (!DirExist(A_ScriptDir "\learned"))
			DirCreate(A_ScriptDir "\learned")
		FileAppend(tbsOut, path)
		return true
		}
	catch
		return false
	}

;spellquests / trainspells switched on: said once a run that they aren't built (nothing else happens)
TrainNotBuilt()
	{
	global TrainSaidOnce ; (globals it sets)
	if (!IsObject(TrainSaidOnce))
		TrainSaidOnce := V1Obj()
	if (TrainOn("spellquests") && !TrainSaidOnce.Has("spellquests"))
		TrainSaidOnce["spellquests"] := 1, DebugLog("Spells: spellquests is on, but taking spell quests isn't built yet (it needs the quest book's windows, seen in the game) - nothing is done")
	if (TrainOn("trainspells") && !TrainSaidOnce.Has("trainspells"))
		TrainSaidOnce["trainspells"] := 1, DebugLog("Spells: trainspells is on, but spending training points isn't built yet (it needs the trainer's window, seen in the game) - nothing is done; python vision\spellplan.py --live says what the plan would train")
	}

;---- Not built yet: where each flow plugs in (TODO.md goal 4 - each needs the game first) ----
;
;TODO(spellquests - needs the game): TrainQuestTick, called here from TrainBookTick (out of battle) when spellquests is on,
;every ~5 minutes: /quests (vision\questmem.py quest_lines - every quest, the tracked one marked, each WizQuestData
;property in its props field) and vision\spellplan.py pick_quest's rule (keep / track / back) - as a helper route
;(vision.py, e.g. /spellplan) or the same few lines here. Before it can: what marks a spell quest (python vision\reflect.py
;--class WizQuestData; /quests with a spell quest open - its props against the others' - then a spellquest| rule in
;trainplans.txt), and the quest book's windows (python vision\bagmem.py --tree --all with it open: the key that opens it,
;each quest row's title text and button, its pages, its close button; whether clicking a row makes it the tracked quest -
;/goal's quest id changes). Then: remember the main quest's id, open the book, find the spell quest's row by NavGuiTree
;(Vision.ahk) and click it the way QuickSell.ahk clicks a window found by memory (QsClickTarget / QsTargetOk / QsPx,
;each click after Potions.ahk NoCrownsNear), check /goal's quest id changed, close it; the walker does the quest as any
;other (AutoQuester\Walker.ahk follows the tracked quest). Its quest gone from /quests (done): back to the main one the
;same way.
;  The '!' markers: AutoQuester\Walker.ahk WalkQuestMarker presses X only at an NPC wearing a gold '?' -
;vision.py find_qmarks reports '!' (a new quest on offer) too, but the walker skips those on purpose. If the professors
;offer spell quests with a '!' (to see in the game: python vision\questmem.py --all before and after one shows up),
;TrainQuestTick is where a walk to that NPC and an X would go - the walker itself isn't changed for it.
;
;TODO(trainspells - needs the game): TrainRun, from TrainBookTick when trainspells is on and the training points read
;above 0 (or the level went up): vision\spellplan.py next_to_train (the plan: learned\trainplans.txt, else
;trainplans.txt) says which spell, its trainer and zone. Before it can: the training points and the wizard's level by
;memory (python vision\reflect.py --class WizGameStats --grep "rain|Level" - then bagmem.py's stats), the trainer's
;template (/npc, as vision.py potion_sellers finds Hilda Brewer), and the trainer's window (bagmem.py --tree --all with
;it open: each spell row's name, cost, level and greyed state, the Learn button, the close button, any "more training
;points" / Crowns control - never clicked, and the message box's caption and buttons). Then Potions.ahk PotionRunWalk's
;way: Mark (PgDn), the Commons and the zone's door, PotionWalkTo the trainer, X; the planned row clicked only when it
;isn't greyed and its cost is within the points, then Learn (allow-listed windows only, NoCrownsNear before each click,
;QuickSell.ahk QsAnswerBox's way for the box); /book must then hold exactly that spell's template; close, Recall (PgUp).
;Anything unknown: back out and say so. Gold only - training points are never bought.
;
;TODO(deckadd - needs the game): TrainDeckAdd, from TrainNewSpells when deckadd is on: vision\spellplan.py deck_changes on
;/decks (the decks with their kinds) and /book?kinds=1 (the new spells' kinds and values) says what to add or swap out
;within the deck's limits. Before it can: the deck page's windows (bagmem.py --tree --all with the deck open: the key
;or button that opens it, the spellbook grid's entries, the school tabs, the page arrows, the deck's own cards; how an
;entry maps to a template id - its texture or tooltip), and that a click adds a copy and a click on a deck card takes one
;out (checked after each click with /deck's signature - vision\deckmem.py signature). Then Decks.ahk DeckLearnGame
;learns the changed deck again and CardLearn.ahk LearnMemHand learns the new card the first time it's in hand.
