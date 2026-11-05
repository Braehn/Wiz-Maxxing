#Warn Unreachable, Off
; Potions.ahk - out of battle: drinks a potion when your health is low, and when there are none left goes
; to buy more with gold (never Crowns): Recall to your Mark at the potion seller and the buying you
; recorded there once. AHK v1.1, functions only; #Included by Autofarmer.ahk. Needs the vision helper
; (Vision.ahk) to read the globes.
;
; Health: the number on the red globe (vision.py /globes, digit pictures in ui1.144\globedigits), as a %
; of your most health (read off your name plate in battle - <school>.maxhealth in PlayerStats.txt - or
; the most the globe has shown). Under potionat % (PlayerStats.txt, default 40) it drinks (Ctrl+O, the
; game's Drink Potion key); health not going up after that means no potion was left.
;
; Out of potions (potionmark:1, the default): your Mark is at the potion seller - you leave it there
; (Page Down, right next to Hilda Brewer) and the bot never marks anywhere else:
;   1. Recall (Page Up) to the Mark - a recall keeps the Mark, so it's there for the next run too (none
;      when you're at the seller already)
;   2. the buying recorded there (routes\mark_<wizard>.txt - each wizard has its own Mark, so its own
;      recording: X to talk, the Fill All click, closing it), once the seller's "Press X" prompt with the
;      name read when recording (HILDA BREWER) shows - else it's the wrong place and nothing is clicked
;   3. drink, then carry on from there: walking follows the quest arrow from the seller (the walker
;      starts afresh). Mob-loop, lore and afk farming have no way back to their spot yet - it tells you
; Nothing recorded for this wizard yet: no recall (it would only pull you off your quest) - it tells you
; how to set it up. No Mark or too little mana (Page Up does nothing): it tells you and tries again 10
; minutes later. A Recall in the Mark's own zone may come without a loading screen: the seller's prompt
; showing, or mana going down (the Recall's cost), counts as arrived. The Mark somewhere else (another zone, or no seller's prompt there): no more
; recalls for this wizard till the bot restarts or you record the buying again. A run that ends without health going up (no gold, a missed click) waits 10 minutes
; too. Page Down / Page Up / Home / End are never recorded or replayed (Page Down while recording at the
; Mark: your Mark moved there, so the recording starts over from there).
;
; potionmark:0 - a refill run along a route (routes\<zone>.txt) instead, which moves your Mark:
;   1. Mark Location (Page Down) where you are
;   2. Go Home (the Home key) - you always land in the same spot there, and it's the same house from any
;      world, so one route does for all (potionfromhome:0 in PlayerStats.txt: the world's Commons (End)
;      instead - but you land somewhere different there each time); the game's log says which zone it is
;   3. the route recorded from there: your keys (walking, X to talk) and left clicks (Hilda
;      Brewer's "Fill All" etc.), replayed with the same timing; loading screens on the way are waited for
;   4. drink (now there are potions), then Recall (Page Up) back to the mark
; Before every click it reads the screen round it: any "Crown" there stops the run (it buys with gold
; only). A battle, you touching the mouse or keyboard, or a loading screen that doesn't come stops it too.
; No route from there: it recalls back and tells you to record one.
;
; By the zone's map (potionwalk:1, the default) - nothing recorded: the potion seller's spot is in the game's own
; files (the vision helper reads it: Hilda Brewer in Wizard City's Commons - the only one). Out of potions:
;   1. a Mark (Page Down) where the wizard is, to come back to (not in the Commons itself, nor in your house)
;   2. outside Wizard City Home (the Home key - your house in Wizard City), then the Commons (End); in Wizard City
;      the Commons straight away. End (the game's GoHub) goes nowhere inside the house (the Dorm), nor with no
;      mana (it seems to take some, as a Recall does - Home doesn't): out through the house's door first (its way
;      out is in the zone's files - the Dorm's into Ravenwood), then End; End not taking: walked through the zone's
;      door to the Commons (Ravenwood's)
;   3. walked to her by the zone's map (the route planner, the game's memory - read-only), X at her prompt, Fill All
;      (found by the words on it, never with "Crown" round it), the window closed
;   4. one drunk, then Fill All again - full again
;   5. Recall (Page Up) to the Mark, and on from there (the quest arrow)
; A way that doesn't get to her (no Commons after End - your house in another world?): back to the Mark, and it
; tells you. A Recall takes mana (up to 10): one that didn't work keeps the Mark for the next run. A buying you recorded at your Mark is still used when there is one; anything that can't be done by
; the map falls back to the recorded ways below.
;
; Recording (tray menu "Record potion buying..."): the bot recalls you to your Mark (Page Up); press X to
; talk, click Fill All (and whatever closes the window), then press F9. You stay at the seller.
; potionmark:0: the bot marks your spot and takes you Home (or to the Commons); walk to the potion seller
; with the keyboard (W A S D / arrows - not the mouse, a camera turn isn't recorded), press X to talk,
; click Fill All (and whatever closes the window), then press F9. It saves the route for that start and
; recalls you back. Record on the same mount you'll farm with: a route is a timing.

global PotionNextCheck, PotionMaxHp, PotionFailUntil, PotionRecording ;(v1 never ran: PotionNextCheck := 0, PotionMaxHp := 0, PotionFailUntil := 0, PotionRecording := 0 - blank at start: PotionsBlank)
;(the key that stops a recording, as it was when it began - the Keys tab's: Hotkeys.ahk)
global PotionStopKey
global PotionRec, PotionRecStop, PotionRecT0, PotionRecDown, PotionHook ;(v1 never ran: PotionRec := "", PotionRecStop := 0, PotionRecT0 := 0, PotionRecDown := "", PotionHook := "" - blank at start: PotionsBlank)
;A refill run that stopped half way (a battle on the route): its mark is still the right one, so the next
;run doesn't mark again (that would move it to the middle of the route)
global PotionMarkZone, PotionMarkAt ;(v1 never ran: PotionMarkZone := "", PotionMarkAt := 0 - blank at start: PotionsBlank)
;The Mark way: per wizard, where its Mark turned out to be when that's not where the buying was recorded
;(no more recalls for it till a restart or a new recording); recording at the Mark, and a Page Down during
;it (start over)
;(PotionMarkOff: made by PotionOff - an initializer here never runs, as this file is #Included at the bottom)
global PotionMarkOff, PotionRecAtMark, PotionRecRestart ;(v1 never ran: PotionRecAtMark := 0, PotionRecRestart := 0 - blank at start: PotionsBlank)
;(a potion shop that couldn't be closed: PotionCarryOn stops walking and says so)
global PotionShopLeft
;No potions and none to be bought (the run failed): resting - no walking - till health is back (PotionCheck); when
;the last drink found none (no Ctrl+O again for 2 minutes)
;(no starting values: this file is #Included at the bottom, where they never run - blank counts as 0)
global PotionResting, PotionNoneAt, PotionRestFrom

;Called out of battle from the main loop (every few seconds at most): low health -> drink, none -> run
PotionCheck()
	{
	;(when battles only last said there are none left - not bought: once in 10 minutes)
	static boSaidAt := 0
	global PotionNextCheck, PotionResting, PotionNoneAt, PotionRestFrom, PotionFailUntil ; (v1 globals it sets)
	;(not while a dungeon run is being recorded: you're playing it - Dungeons.ahk)
	;(v1: PotionNextCheck blank at first - the tick isn't < a blank, compared as text)
	if (V1Lt(A_TickCount, PotionNextCheck) || PotionRecording || DgRecording || !VisionOn || !GameActive())
		return
	PotionNextCheck := A_TickCount + 4000
	hp := PotionHealth()
	;(Wizard101 gone to the tray during the look - Settings: traygame: nothing more - Ctrl+O and a run's keys would go
	;to the window in front)
	if (hp = "" || GameInTray)
		return
	most := PotionMost()
	;(v1: most blank - PotionMaxHp never set - compared as text: hp is more)
	if (V1Gt(hp, most))
		PotionNoteMax(hp, false), most := hp
	limit := Stats.Has("potionat") ? Stats["potionat"] : 40
	pct := most ? 100 * hp / most : 100
	;(resting: on again once health is back over the limit + 20 %, or after 10 minutes all the same)
	if (PotionResting && (pct >= limit + 20 || A_TickCount - PotionRestFrom > 600000))
		{
		PotionResting := 0
		DebugLog("Potions: health " hp "/" most " (" Round(pct) "%) - " (pct >= limit + 20 ? "back up" : "10 minutes rested") ", walking on")
		}
	if (!most || pct >= limit)
		return
	;(no potion at the last drink, 2 minutes ago or less: not again yet)
	;(v1: PotionNoneAt blank - the sum blank, not > 120000; !blank true)
	if (V1Gt(V1Ago(PotionNoneAt), 120000) || !PotionNoneAt)
		{
		DebugLog("Potions: health " hp "/" most " (" Round(pct) "%) - under " limit "%: drinking a potion")
		if (PotionDrink(hp))
			{
			PotionNoneAt := 0
			return
			}
		PotionNoneAt := A_TickCount
		}
	;(battles only - Settings: battlesonly: no run to buy more - it moves nothing out of battle: an alert, why in the log -
	;once in 10 minutes; no rest either - there's no walking to hold back)
	if (BattlesOnly())
		{
		if (!boSaidAt || A_TickCount - boSaidAt > 600000)
			{
			boSaidAt := A_TickCount
			DebugLog("Potions: health " hp "/" most " (" Round(pct) "%) and no potion left - not going to buy any: battles only is on (Settings), the bot moves nothing out of battle")
			AlertSend("potions", "out of potions", "No potion left (health " Round(pct) "%), and battles only is on (Settings): the bot doesn't go to buy any - drink or buy some yourself.")
			}
		return
		}
	;(v1: PotionFailUntil blank till a run failed - the tick isn't < a blank, compared as text)
	if (V1Lt(A_TickCount, PotionFailUntil))
		{
		;(none, and buying failed lately: rest rather than walk into a battle this low)
		if (!PotionResting)
			{
			PotionResting := 1, PotionRestFrom := A_TickCount
			DebugLog("Potions: no potions, and buying failed lately - resting (no walking) till health is back over " limit + 20 "% (it comes back by itself)")
			}
		return
		}
	DebugLog("Potions: no potion left - going to buy some")
	if (PotionRun())
		PotionNoneAt := 0, PotionResting := 0
	else
		PotionFailUntil := A_TickCount + 10 * 60000
	}

;While resting (no walking - PotionCheck started it): health looked at every 4 s, from the main loop itself - on again
;once it's back over potionat + 20 %, or after 10 minutes all the same; how it's going said every minute
PotionRestCheck()
	{
	static saidAt := 0, lookAt := 0
	global PotionResting ; (v1 globals it sets)
	if (!PotionResting || A_TickCount < lookAt)
		return
	lookAt := A_TickCount + 4000
	hp := (VisionOn && GameActive()) ? PotionHealth() : ""
	most := PotionMost()
	limit := Stats.Has("potionat") ? Stats["potionat"] : 40
	pct := (hp != "" && most) ? 100 * hp / most : ""
	if ((pct != "" && pct >= limit + 20) || (PotionRestFrom && A_TickCount - PotionRestFrom > 600000))
		{
		PotionResting := 0
		DebugLog("Potions: " (pct != "" ? "health " hp "/" most " (" Round(pct) "%) - " : "") ((pct != "" && pct >= limit + 20) ? "back up" : "10 minutes rested") ", walking on")
		return
		}
	if (A_TickCount - saidAt > 60000)
		saidAt := A_TickCount, DebugLog("Potions: resting - health " (pct = "" ? "can't be read" : hp "/" most " (" Round(pct) "%)") ", walking on at " limit + 20 "%")
	}

;Health off the globe, read twice the same ("" if not)
PotionHealth()
	{
	a := PotionGlobes()
	Sleep(250)
	b := PotionGlobes()
	return (a.hp != "" && a.hp = b.hp) ? a.hp + 0 : ""
	}

;{hp, mana} off the globes ("" each that can't be read)
PotionGlobes()
	{
	answer := VisionGet("/globes?left=" GameLeft "&bottom=" GameTop + GameH "&scale=" Round(UiScale, 3), 1500)
	RegExMatch(answer, "health\|(\d*)", &h), RegExMatch(answer, "mana\|(\d*)", &m)
	;(v1: no match - h1, m1 blank)
	h1 := V1At(h, 1), m1 := V1At(m, 1)
	;(for the dashboard)
	if (h1 != "")
		DashSee("hp", h1 (PotionMost() ? "/" PotionMost() " (" Round(100 * h1 / PotionMost()) "%)" : ""))
	if (m1 != "")
		DashSee("mana", m1)
	return V1Obj({hp: h1, mana: m1})
	}

;Your most health: the name plate's max (battle) for this school's wizard, else the most the globe showed
PotionMost()
	{
	;(v1's Max with a blank - PotionMaxHp before any reading - is blank)
	if (school != "" && Stats.Has(school ".maxhealth"))
		return V1Max(Stats[school ".maxhealth"], PotionMaxHp)
	return PotionMaxHp
	}

;A most-health reading: exact (off the name plate in battle) is kept in PlayerStats.txt per school
PotionNoteMax(n, exact := true)
	{
	global PotionMaxHp ; (v1 globals it sets)
	if (!exact)
		{
		;(v1's Max with a blank is blank: PotionMaxHp stays blank till a name plate's reading)
		PotionMaxHp := V1Max(PotionMaxHp, n)
		return
		}
	PotionMaxHp := n
	if (school != "" && Stats[school ".maxhealth"] != n)
		StatsSet([[school ".maxhealth", n]], "your " school " wizard's most health (off its name plate in battle; Potions.ahk)")
	}

;Drinks a potion (Ctrl+O). True if health went up
PotionDrink(before)
	{
	;(Wizard101 gone to the tray - Settings: traygame: Ctrl+O would go to the window in front - none drunk)
	if (GameInTray)
		return false
	ReleaseKeys()
	Send("{Blind}^o")
	Sleep(2500)
	after := PotionHealth()
	;(v1: most health blank - the sum blank, and after compared with it as text: more)
	if (after != "" && V1Gt(after, V1Add(before, V1Max(5, V1FloorDiv(PotionMost(), 50)))))
		{
		DebugLog("Potions: drank one - health " before " -> " after)
		return true
		}
	DebugLog("Potions: health didn't go up (" before " -> " (after = "" ? "?" : after) ") - no potion left")
	return false
	}

;The refill run (see the top of this file). True if it came back with potions
PotionRun()
	{
	global PotionMarkZone, PotionMarkAt ; (v1 globals it sets)
	;(battles only - Settings: battlesonly: never a run - its Mark, Recall, Home / End and the walk move the wizard)
	if (BattlesOnlyNo("run to buy potions"))
		return false
	;(by the zone's map - potionwalk:1: "" when it can't be done that way here, or didn't work and there's a recorded
	;way to try - then the recorded ways)
	if (PotionWalkOn())
		{
		walked := PotionRunWalk()
		if (walked != "")
			return walked
		}
	if (PotionByMark())
		return PotionRunMark()
	ReleaseKeys()
	startZone := WalkZone(true)
	;1. Mark here (unless a run that stopped half way already did)
	if (!(PotionMarkZone != "" && A_TickCount - PotionMarkAt < 15 * 60000))
		{
		;(Wizard101 gone to the tray - Settings: traygame: no run - its keys would go to the window in front)
		if (GameInTray)
			return false
		Send("{Blind}{PgDn}")
		PotionMarkZone := startZone, PotionMarkAt := A_TickCount
		DebugLog("Potions: marked this spot (Page Down) in " startZone)
		Sleep(1500)
		}
	;2. Home (or this world's Commons)
	if (!PotionTeleport(PotionStartKey(), PotionStartName()))
		return false
	commons := WalkZone(true)
	route := PotionRouteFile(commons)
	if (!FileExist(route))
		{
		DebugLog("Potions: no potion route recorded from " commons " - going back (tray menu 'Record potion buying...')")
		TrayTip("Out of potions, and there's no route to the potion seller from " commons ".`nRecord one: tray menu 'Record potion buying...'", "Wizard101 bot", 2)
		AlertSend("potions", "out of potions", "No route to the potion seller from " commons " - record one (tray menu: Record potion buying...).")
		PotionRecall()
		return false
		}
	;3. The route
	if (!PotionReplay(route))
		{
		ReleaseKeys()
		return false
		}
	;4. Drink, back to the mark
	ok := PotionAfterBuy()
	PotionRecall()
	return ok
	}

;Whether your Mark is at the potion seller (potionmark:1, the default) - else potionmark:0, the route way
PotionByMark()
	{
	return !(Stats.Has("potionmark") && !Stats["potionmark"])
	}

;A sigil that won't start (the walker's WalkSigilReset - Settings: sigilhome): may a Mark (Page Down) be made there, to Recall back to
;after Home? Never moving your Mark kept at the potion seller - potionmark:1 with buying recorded at this wizard's Mark (PotionRunMark
;recalls to it); otherwise as the potion runs themselves Mark (potionmark:0's route way at every run, the map walk with nothing
;recorded). Never in battles only. taken: the sigil's Mark made - a potion run's own, kept for its Recall (PotionMarkKept), is gone
SigilMarkOk(taken := false)
	{
	global PotionMarkZone, PotionMarkAt ; (v1 globals it sets)
	if (taken)
		{
		PotionMarkZone := "", PotionMarkAt := 0
		return true
		}
	if (BattlesOnly())
		return false
	return !(PotionByMark() && PotionMarkFile(PotionWho()) != "")
	}

;The Mark way: Recall to the seller, the buying recorded there, drink, carry on from there. True if it
;bought (it never presses Page Down: that would move your Mark off the seller)
PotionRunMark()
	{
	ReleaseKeys()
	;(nothing recorded for this wizard: a recall would only pull you off your quest to wherever its Mark is)
	who := PotionWho(), route := PotionMarkFile(who)
	if (route = "")
		{
		DebugLog("Potions: out of potions, but no buying recorded at this wizard's Mark yet - not recalling. Leave a Mark (Page Down) right next to the potion seller (Hilda Brewer), then tray menu 'Record potion buying...'")
		TrayTip("Out of potions. To buy more: leave a Mark (Page Down) right next to the potion seller (Hilda Brewer, Wizard City's Commons), then tray menu 'Record potion buying...' (once for each wizard).", "Wizard101 bot", 2)
		AlertSend("potions", "out of potions", "Nothing set up to buy more: leave a Mark (Page Down) in Wizard City's Commons.")
		return false
		}
	marksOff := PotionOff()
	if (marksOff.Has(who))
		{
		DebugLog("Potions: out of potions - not recalling: this wizard's Mark was in " marksOff[who] ", not at the potion seller (Mark next to her again, then restart the bot - " HkText("restart") ")")
		return false
		}
	rec := PotionMarkInfo(route)
	if (PotionAtSeller(rec))
		DebugLog("Potions: at the potion seller already (" rec.prompt "'s prompt is up) - no Recall")
	else
		{
		g := PotionGlobes()
		DebugLog("Potions: Recall (Page Up) to your Mark at the potion seller")
		if (!PotionTeleport("{PgUp}", "your Mark", PotionArrived.Bind(rec, g.mana)))
			{
			low := (g.mana != "" && g.mana < 10)
			DebugLog("Potions: no Recall - " (low ? "mana is " g.mana ", and a Recall costs up to 10" : "no Mark, or too little mana for it? The Mark goes right next to the potion seller (Hilda Brewer)"))
			TrayTip("Out of potions, and Page Up (Recall) went nowhere.`n" (low ? "Mana is " g.mana " - a Recall costs up to 10." : "No Mark, or too little mana for the Recall. The Mark goes right next to the potion seller (Hilda Brewer)."), "Wizard101 bot", 2)
			AlertSend("potions", "out of potions", "The Recall to your Mark went nowhere - " (low ? "mana is " g.mana "." : "no Mark, or too little mana."))
			return false
			}
		}
	;(the right place: the zone the buying was recorded in, and the seller's prompt there if one was read)
	shop := WalkZone(true), there := (rec.zone = "" || shop = rec.zone)
	if (there && rec.prompt != "")
		{
		t0 := A_TickCount
		while (!(there := PotionAtSeller(rec)) && A_TickCount - t0 < 4000)
			Sleep(500)
		}
	if (!there)
		{
		marksOff[who] := shop
		DebugLog("Potions: this wizard's Mark is in " shop (shop = rec.zone ? " but not by " rec.prompt " (no prompt with that name)" : ", but the buying was recorded in " rec.zone) " - the Mark isn't at the potion seller. Nothing clicked; no more recalls till you Mark (Page Down) next to her again and restart the bot (" HkText("restart") "), or record the buying again")
		TrayTip("This wizard's Mark isn't at the potion seller (it's in " shop ").`nMark (Page Down) right next to Hilda Brewer again, then restart the bot (" HkText("restart") ").", "Wizard101 bot", 2)
		AlertSend("potions", "out of potions", "This wizard's Mark isn't at the potion seller (it's in " shop ") - Mark next to Hilda Brewer again and restart the bot.")
		PotionCarryOn(false)
		return false
		}
	if (!PotionReplay(route))
		{
		ReleaseKeys()
		PotionCarryOn(false)
		return false
		}
	ok := PotionAfterBuy()
	PotionCarryOn(ok)
	return ok
	}

;The per-wizard list of Marks found away from the seller (PotionMarkOff), made the first time it's needed
PotionOff()
	{
	global PotionMarkOff ; (v1 globals it sets)
	if (!IsObject(PotionMarkOff))
		PotionMarkOff := V1Obj()
	return PotionMarkOff
	}

;Which wizard is logged in (its CharID off the game's log; "anyone" if that can't be read): each one has
;its own Mark, so its own recording
PotionWho()
	{
	id := V1IsFunc("StatsCharID") ? StatsCharID.Call() : ""
	return id = "" ? "anyone" : id
	}

;routes\mark_<wizard>.txt, the buying recorded at that wizard's Mark (forSave: the name to save under;
;else "" if there's none). mark_anyone.txt (recorded while the game's log didn't say which wizard) is only
;used while it still doesn't - never for a wizard it can tell, whose Mark may be anywhere
PotionMarkFile(who, forSave := false)
	{
	file := A_WorkingDir "\routes\mark_" who ".txt"
	return (forSave || FileExist(file)) ? file : ""
	}

;{zone, prompt} off a Mark recording's start line (start|zone|scale|size|mark|prompt)
PotionMarkInfo(file)
	{
	;(v1: FileReadLine, its 2nd line - blank when the file or the line isn't there)
	line := V1At(StrSplit(V1FileRead(file), "`n", "`r"), 2)
	f := StrSplit(line, "|")
	;(v1: a field the line doesn't have - blank; no 2nd line - StrSplit of a blank is an empty Array: f[1] blank too)
	return V1Obj({zone: V1At(f, 1) = "start" ? V1At(f, 2) : "", prompt: V1At(f, 1) = "start" ? V1At(f, 6) : ""})
	}

;The name on the "Press X to ..." prompt showing now (the walker's reading of it, letters only), "" if none
PotionPrompt()
	{
	if (!V1IsFunc("InteractPrompt"))
		return ""
	return InteractPrompt.Call() = "press" ? WkPromptDest : ""
	}

;The prompt's name read the same twice running ("" if not: a reading that changes each time - no title line,
;just OCR letters - can't be checked against later)
PotionPromptSteady()
	{
	a := PotionPrompt()
	Loop 3
		{
		Sleep(400)
		b := PotionPrompt()
		if (a != "" && a = b)
			return a
		a := b
		}
	return ""
	}

;Arrived with no loading screen (a Recall in the same zone): the seller's prompt is up, or mana went down
;(read twice the same - the Recall's cost; nothing else costs mana out of battle)
PotionArrived(rec, manaBefore)
	{
	if (PotionAtSeller(rec))
		return true
	if (manaBefore = "")
		return false
	a := PotionGlobes().mana
	Sleep(250)
	b := PotionGlobes().mana
	return (a != "" && a = b && a < manaBefore)
	}

;Whether the prompt read when the buying was recorded is showing now (OCR: a letter or two may differ).
;False when none was read then
PotionAtSeller(rec)
	{
	if (rec.prompt = "")
		return false
	now := PotionPrompt()
	if (now = "")
		return false
	if (now = rec.prompt)
		return true
	return V1IsFunc("WalkEditDistance") && WalkEditDistance.Call(now, rec.prompt) <= Max(1, StrLen(rec.prompt) // 5)
	}

;After buying: drinks if health is still under potionat %. False if that drink didn't work - nothing was
;bought (no gold, a click that missed), so PotionCheck waits 10 minutes before another run
PotionAfterBuy(useOne := false)
	{
	hp := PotionHealth(), most := PotionMost()
	limit := Stats.Has("potionat") ? Stats["potionat"] : 40
	;(useOne: one drunk after buying, whatever the health - unless it's nearly full: then it'd only be wasted)
	limit := useOne ? 90 : limit
	if (hp = "")
		{
		DebugLog("Potions: can't read your health after buying - not drinking")
		return true
		}
	if (most && 100 * hp / most >= limit)
		return true
	if (PotionDrink(hp))
		return true
	DebugLog("Potions: still no potion after buying - nothing bought? (no gold, or a click missed - record the buying again)")
	return false
	}

;After the Mark way: the walker starts afresh from the seller (it's somewhere new); other farming can't get
;back to its spot yet, so you're told
PotionCarryOn(bought)
	{
	global PotionShopLeft, Walking ; (v1 globals it sets)
	PotionWalkFresh()
	;(the shop's window couldn't be closed: walking would only be stuck behind it)
	if (PotionShopLeft)
		{
		PotionShopLeft := 0
		wasWalking := Walking
		if (Walking)
			{
			Walking := 0
			ReleaseKeys()
			}
		DebugLog("Potions: " (bought ? "bought" : "didn't buy") " - the shop's window is still open" (wasWalking ? ": walking stopped" : ""))
		if (V1IsFunc("SetStatus"))
			SetStatus.Call("stopped - the potion shop's window is still open: close it" (wasWalking ? " and press " HkText("walk") : ""))
		if (V1IsFunc("WalkNotify"))
			WalkNotify.Call("shop", "Potion shop still open", "The potion shop's window couldn't be closed. Close it (its red X, bottom right)" (wasWalking ? " and press " HkText("walk") " to walk on." : "."))
		else
			TrayTip("The potion shop's window couldn't be closed. Close it (its red X).", "Wizard101 bot", 2)
		return
		}
	if (Walking && !afkVar && !loopmode && !loremode)
		{
		DebugLog("Potions: " (bought ? "bought" : "didn't buy") " - following the quest arrow on from here")
		return
		}
	why := afkVar ? "afk farming" : loopmode ? "mob-loop farming" : loremode ? "lore farming" : ""
	DebugLog("Potions: " (bought ? "bought" : "didn't buy") " - staying at your Mark (" (why = "" ? "walking is off - " HkText("walk") : why " has no way back to its spot yet") ")")
	if (bought)
		TrayTip("Bought potions - you're at the potion seller. " (why = "" ? "Walking is off (" HkText("walk") "), so the bot stays there." : "The bot can't get back to your " why " spot yet, so take it back yourself."), "Wizard101 bot", 1)
	}

;The walker starts afresh, and presses no X at a prompt for a while (DialogQuiet): it's standing by the
;seller, whose "Press X to talk" would reopen the shop
PotionWalkFresh()
	{
	global WkQuietUntil, WkQuietLogged ; (v1 globals it sets)
	if (!V1IsFunc("WalkReset"))
		return
	WalkReset.Call()
	WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
	}

;Recall (Page Up) to the mark, if this run made one
PotionRecall()
	{
	global PotionMarkZone, PotionMarkAt ; (v1 globals it sets)
	if (PotionMarkZone = "")
		return
	DebugLog("Potions: back to the mark (Page Up)")
	g := PotionGlobes()
	if (!PotionTeleport("{PgUp}", "the mark", PotionArrivedMana.Bind(g.mana)))
		{
		;(kept: the next run goes back to it once it has bought)
		DebugLog("Potions: the recall didn't work (mana " (g.mana = "" ? "?" : g.mana) " - a Recall takes up to 10) - the mark is kept for the next run")
		return
		}
	if (WalkZone(true) != PotionMarkZone)
		DebugLog("Potions: the recall went to " WalkZone(true) ", not " PotionMarkZone " where the mark was made - carrying on from here")
	PotionMarkZone := "", PotionMarkAt := 0
	}

;Presses a teleport key and waits for the loading screen to come and go (up to 60 s). True if it did.
;Nothing loading after 15 s with the spellbook still on screen (no Mark, too little mana): it gives up then;
;a battle starting stops it too. arrived (a Func, optional): true once there with no loading screen (a
;Recall in the same zone), looked at every second from 3 s on
PotionTeleport(key, what, arrived := "")
	{
	before := WalkZone(true)
	;(Wizard101 gone to the tray - Settings: traygame: not pressed - the key would go to the window in front)
	if (GameInTray)
		return false
	Send("{Blind}" key)
	t0 := A_TickCount, started := false
	while (A_TickCount - t0 < 60000)
		{
		Sleep(250)
		WalkZone(true)
		if (WkLoading)
			started := true
		;(v1: WkLoadedAt blank before any loading screen - compared as text: not >)
		if (!WkLoading && V1Gt(WkLoadedAt, t0 + 500))
			{
			Sleep(2500)
			DebugLog("Potions: at " what " (" WalkZone(true) ")")
			return true
			}
		if (started || Mod(A_Index, 4))
			continue
		if (IsObject(arrived) && A_TickCount - t0 > 3000 && arrived.Call())
			{
			DebugLog("Potions: at " what " - no loading screen (" WalkZone(true) ")")
			return true
			}
		V1ImageSearch(&bx, &by, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundstart.png"))
		if (ErrorLevel = 0)
			{
			DebugLog("Potions: a battle started instead of " key " for " what " - stopping")
			return false
			}
		if (A_TickCount - t0 > 15000)
			{
			V1ImageSearch(&bx, &by, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundfinish.png"))
			if (ErrorLevel = 0)
				break
			}
		}
	DebugLog("Potions: no loading screen after " key " for " what " (still in " before ") - stopping")
	return false
	}

;Where routes start: Home (the Home key; potionfromhome:1, the default) or the world's Commons (End)
PotionStartKey()
	{
	return (Stats.Has("potionfromhome") && !Stats["potionfromhome"]) ? "{End}" : "{Home}"
	}

PotionStartName()
	{
	return PotionStartKey() = "{Home}" ? "your house (Home)" : "the Commons (End)"
	}

;routes\<zone>.txt for the zone a route starts in (potionmark:0)
PotionRouteFile(zone)
	{
	return A_WorkingDir "\routes\" RegExReplace(zone, "[^\w-]", "_") ".txt"
	}

;Replays a recorded route. False if it was stopped (a battle, your hands, a Crown, a load that didn't come)
PotionReplay(route)
	{
	text := V1FileRead(route)
	t0 := A_TickCount, ok := true, down := V1Obj()
	DebugLog("Potions: replaying " route)
	Loop Parse, text, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length < 3 || f[1] = "start" || SubStr(A_LoopField, 1, 1) = ";")
			continue
		;(v1: a field the line doesn't have - blank)
		while (f.Length < 4)
			f.Push("")
		;(wait for the event's time, watching for trouble - v1: a time that isn't a number compared as text)
		while (V1Lt(V1Ago(t0), f[1]))
			{
			if (!PotionOk())
				{
				ok := false
				break
				}
			Sleep(10)
			}
		if (!ok)
			break
		if (f[2] = "key")
			{
			name := f[3]
			;(never Page Down / Page Up / Home / End: they'd move your Mark or teleport you off the route)
			if (RegExMatch(name, "i)^(Numpad)?(PgDn|PgUp|Home|End)$"))
				{
				if (f[4] = "down")
					DebugLog("Potions: " name " in the recording - skipped")
				continue
				}
			Send("{Blind}{" name (f[4] = "down" ? " down" : " up") "}")
			down[name] := (f[4] = "down")
			}
		else if (f[2] = "click")
			{
			;(v1: a place that isn't a number - the sum blank, Round of it 0)
			x := V1Round(V1Add(GameLeft + GameW / 2, V1Mul(f[3], UiScale))), y := V1Round(V1Add(GameTop + GameH / 2, V1Mul(f[4], UiScale)))
			if (!PotionNoCrowns(x, y))
				{
				ok := false
				break
				}
			;(the mouse back where it was afterwards, unless that's done at the end of the run: mousereturn)
			ownGrab := MouseGrab()
			;(your mouse locked meanwhile - Settings.ahk MouseLockOn; its clicks too, once the pointer's on the game -
			;MouseLockMoved)
			MouseLockOn("route")
			MouseMove(x, y, 3)
			MouseLockMoved()
			Sleep(120)
			Click()
			if (ownGrab)
				MouseLetGo()
			MouseLockOff("route")
			}
		else if (f[2] = "zone")
			{
			;a loading screen on the route: wait till it's done (the same zone as when recorded), then the
			;times go on from there (a key held through it stays held, as it was when recorded)
			w0 := A_TickCount
			while (WalkZone(true) != f[3] || WkLoading)
				{
				if (A_TickCount - w0 > 60000 || !PotionOk(false))
					{
					DebugLog("Potions: the route's loading screen to " f[3] " didn't come (in " WalkZone(true) ") - stopping")
					ok := false
					break
					}
				Sleep(50)
				}
			if (!ok)
				break
			t0 := V1Sub(A_TickCount, f[1])
			}
		}
	for name, isDown in down
		if (isDown)
			Send("{Blind}{" name " up}")
	ReleaseKeys()
	DebugLog("Potions: route " (ok ? "done" : "stopped"))
	return ok
	}

;Fine to carry on with a run: Wizard101 in front, your hands off, no battle
PotionOk(watchHands := true, since := 0)
	{
	;(Wizard101 behind another window: brought to the front if "Bring Wizard101 to the front" is on - without waiting for
	;you to leave the keyboard alone: the run's under way)
	if (!GameActive() && !(V1IsFunc("GameToFront") && GameToFront.Call("the potion run is under way", false)))
		{
		DebugLog("Potions: Wizard101 isn't the active window - stopping")
		return false
		}
	;(since: the run's start - any key or mouse of yours after it, not only in the last 400 ms. "Wait while I play" off:
	;the bot carries on while you play - the run too)
	if (watchHands && HandsOffOn() && (UserIdle() < 400 || (since && A_TickCount - UserIdle() > since)))
		{
		DebugLog("Potions: you touched the mouse or keyboard - stopping (the bot leaves it to you)")
		return false
		}
	V1ImageSearch(&bx, &by, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundstart.png"))
	if (ErrorLevel = 0)
		{
		DebugLog("Potions: a battle started - stopping the run (the next one won't mark again)")
		return false
		}
	return true
	}

;No "Crown" anywhere round a click (it only ever buys with gold). False (and stops) if there is
PotionNoCrowns(x, y)
	{
	return NoCrownsNear(x, y)
	}

;No "Crown" read in a box r px round a click (260 at UI 1.144 when r is "") - false if there is one (said: logAs in debug.log,
;who in the tray, where and how in the "crowns" alert, alertTitle its title), or if the screen there can't be read (it
;can't be sure there's none). The potion run's and quick sell's (QuickSell.ahk)
NoCrownsNear(x, y, r := "", logAs := "Potions", who := "The potion run", where := "by the potion seller", how := "it only buys with gold", alertTitle := "potion run stopped")
	{
	;(v1: UiScale or r not a number - Round of a blank 0: a box that can't be read, so no click)
	r := (r = "" || V1Le(r, 0)) ? V1Round(V1Mul(260, UiScale)) : V1Round(r)
	text := OcrRect(Max(GameLeft, x - r), Max(GameTop, y - r), 2 * r, 2 * r, "en", 1)
	;(the screen couldn't be read there: no click - it can't be sure there's no Crown)
	if (ErrorLevel)
		{
		DebugLog(logAs ": the screen round the next click couldn't be read - not clicking, stopping (gold only)")
		return false
		}
	if (RegExMatch(text, "i)cr[o0]wn"))
		{
		DebugLog(logAs ": `"Crown`" on screen by the next click - not clicking, stopping (gold only): " RegExReplace(text, "\s+", " "))
		TrayTip(who " saw `"Crowns`" on screen and stopped (" how ").", "Wizard101 bot", 2)
		AlertSend("crowns", alertTitle, "`"Crowns`" on screen " where " - it stopped without clicking (" how ").")
		return false
		}
	return true
	}

;---- To the potion seller by the zone's map (potionwalk:1) ----

;potionwalk in PlayerStats.txt (the Settings window), on unless it's 0
PotionWalkOn()
	{
	return !(Stats.Has("potionwalk") && !Stats["potionwalk"])
	}

;The potion seller placed in zone ({name, x, y, z}), from the zone's own file (the vision helper's /seller), or ""
PotionSellerIn(zone)
	{
	static seen := V1Obj()
	if (zone = "")
		return ""
	if (seen.Has(zone))
		return seen[zone]
	answer := VisionGet("/seller?zone=" LearnUri(zone), 5000, true)
	;(no answer, or the zone's file not read: asked again next time)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	s := ""
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "seller" && f.Length >= 5)
			{
			;(v1: a place that isn't a number + 0 - blank)
			s := V1Obj({name: f[2], x: V1Add(f[3], 0), y: V1Add(f[4], 0), z: V1Add(f[5], 0), zone: zone})
			break
			}
		}
	seen[zone] := s
	return s
	}

;Where the wizard is and the route to s (the vision helper's /navto: the game's memory, read-only, and its own
;route planner along the zone's map): {x, y, z, yaw, ax, ay, why} - ax/ay "" with no route - or ""
PotionNavTo(s)
	{
	;(kept away from the zone's mobs as the settings say: mobavoid, mobradius)
	answer := VisionGet("/navto?x=" Round(s.x, 1) "&y=" Round(s.y, 1) "&z=" Round(s.z, 1) NavMobArgs(), 2500, true)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	nav := V1Obj({x: "", y: "", z: "", yaw: "", ax: "", ay: "", left: "", why: "", zone: ""})
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		;(v1: a field the line doesn't have - blank)
		while (f.Length < 5)
			f.Push("")
		if (f[1] = "pos")
			nav.x := f[2], nav.y := f[3], nav.z := f[4], nav.yaw := f[5]
		else if (f[1] = "zone")
			nav.zone := f[2]
		else if (f[1] = "route")
			nav.ax := f[2], nav.ay := f[3], nav.left := f[4]
		else if (f[1] = "routewhy")
			nav.why := Trim(SubStr(A_LoopField, 10))
		}
	return (nav.x = "" || nav.yaw = "") ? "" : nav
	}

;W held down / let go (the walker's HoldW only works while walking is on)
PotionHoldW(on)
	{
	global KeysDown, HeldW ; (v1 globals it sets)
	if (on && !HeldW && GameActive())
		{
		KeysDown := 1
		Send("{Blind}{w down}")
		HeldW := 1
		}
	else if (!on && HeldW)
		{
		Send("{Blind}{w up}")
		HeldW := 0
		}
	}

;A turn of h degrees (+ right): A or D held for as long as the walker's TurnRate says
PotionTurnBy(h)
	{
	global KeysDown ; (v1 globals it sets)
	if (!GameActive())
		return
	key := h < 0 ? "a" : "d"
	;(v1: TurnRate blank till WalkerInit - not > 0)
	ms := Round(Abs(h) / (V1Gt(TurnRate, 0) ? TurnRate : 0.15))
	ms := ms < 30 ? 30 : ms > 800 ? 800 : ms
	KeysDown := 1
	Send("{Blind}{" key " down}")
	Sleep(ms)
	Send("{Blind}{" key " up}")
	}

;Walks to the potion seller s by the zone's map: steering at the route's aim (a point ahead on it, round walls)
;by the game's memory. Stuck (no closer in 6 s): backs up and turns, 3 times at most. True once within 140 of
;her. Stops for a battle, your hands on the keys or mouse, the game's memory unreadable, or 2.5 minutes.
;door: s is a way out of the zone (PotionDoor) - walked on into it: true once through it, in another zone
PotionWalkTo(s, since := 0, door := false)
	{
	what := door ? "the way out" : "the potion seller"
	;(steering by the game's memory needs its heading's sign checked - the walker does that as it walks quests)
	if (!WkNavChecked && !WkNavTrusted)
		{
		DebugLog("Potions: can't walk to " what " by the map yet - the game's memory hasn't been checked against the quest arrow (it is after a minute of walking a quest)")
		return false
		}
	ReleaseKeys()
	DebugLog("Potions: walking to " what " (" s.name ") by the zone's map - " s.zone " at " Round(s.x) ", " Round(s.y))
	t0 := A_TickCount, best := "", bestLeft := "", bestAt := A_TickCount, unstuck := 0, said := "", misses := 0, inSaid := false
	since := since ? since : t0
	Loop
		{
		;(a way out: its loading screen come since the walk began - through it, or stopped)
		if (door && (through := PotionThrough(s.zone, t0)))
			return through > 0
		if (!PotionOk(true, since))
			{
			ReleaseKeys()
			return false
			}
		nav := PotionNavTo(s)
		;(a moment with no answer - the helper busy - is asked again; three running: stop)
		if (!IsObject(nav))
			{
			misses += 1
			if (misses < 3)
				{
				Sleep(300)
				continue
				}
			ReleaseKeys()
			DebugLog("Potions: the game's memory can't be read (" VisionErr ") - not walking to " what)
			return false
			}
		misses := 0
		;(walked through a gateway into another zone: not where she is - a way out: that's it)
		if (nav.zone != "" && nav.zone != s.zone)
			{
			if (door)
				return PotionThrough(s.zone, t0, true) > 0
			ReleaseKeys()
			DebugLog("Potions: walked into " nav.zone " on the way to the potion seller - stopping")
			return false
			}
		if (nav.ax = "" && nav.why != said)
			said := nav.why, DebugLog("Potions: no route round walls (" nav.why ") - straight at " (door ? "it" : "her"))
		d := Sqrt((nav.x - s.x) ** 2 + (nav.y - s.y) ** 2)
		if (d <= 140 && !door)
			{
			ReleaseKeys()
			DebugLog("Potions: at the potion seller (" Round(d) " away, " Round((A_TickCount - t0) / 1000) " s)")
			return true
			}
		;(a way out: walked on into it - the loading screen comes once the wizard's in)
		if (d <= 140 && !inSaid)
			inSaid := true, DebugLog("Potions: at the way out (" Round(d) " away) - walking on into it")
		if (A_TickCount - t0 > 150000)
			{
			ReleaseKeys()
			DebugLog("Potions: " (door ? "not through the way out" : "not at the potion seller") " after 2.5 minutes (" Round(d) " away) - stopping")
			return false
			}
		;(getting on: closer as the crow flies, or along the route round walls - a detour isn't being stuck)
		if (best = "" || d < best - 40)
			best := d, bestAt := A_TickCount, unstuck := 0
		if (nav.left != "" && (bestLeft = "" || nav.left < bestLeft - 40 || nav.left > bestLeft + 300))
			bestLeft := nav.left, bestAt := A_TickCount, unstuck := 0
		if (A_TickCount - bestAt > 6000)
			{
			unstuck += 1
			if (unstuck > 3)
				{
				ReleaseKeys()
				DebugLog("Potions: stuck " Round(d) " from " what " (no closer after backing up 3 times) - stopping")
				return false
				}
			DebugLog("Potions: no closer in 6 s (" Round(d) " away) - backing up and turning")
			PotionHoldW(0)
			Send("{Blind}{s down}")
			Sleep(700)
			Send("{Blind}{s up}")
			PotionTurnBy(Mod(unstuck, 2) ? 90 : -90)
			if (!PotionOk(true, since))
				{
				ReleaseKeys()
				return false
				}
			PotionHoldW(1)
			Sleep(900)
			bestAt := A_TickCount
			continue
			}
		h := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.ax != "" ? nav.ax : s.x, nav.ay != "" ? nav.ay : s.y)
		h := (h = "") ? 0 : h
		;(a big turn close to her on the spot - walking on, it would circle round her; else turning walking on: the
		;game takes W and A/D at once)
		if (Abs(h) > 60 && d < 300)
			{
			PotionHoldW(0)
			PotionTurnBy(h)
			}
		else
			{
			PotionHoldW(1)
			if (Abs(h) > 12)
				PotionTurnBy(h)
			}
		Sleep(60)
		}
	}

;Walking through a way out of zone: 0 while there's no loading screen since t0 (or sure: the game's memory says
;another zone already) - else the keys let go and the loading screen waited out (a minute at most): 1 once in
;another zone, -1 if not
PotionThrough(zone, t0, sure := false)
	{
	now := WalkZone(true)
	;(v1: WkLoadedAt blank before any loading screen - compared as text: not >)
	if (!sure && !WkLoading && !V1Gt(WkLoadedAt, t0 + 500) && (now = "" || now = zone))
		return 0
	ReleaseKeys()
	t1 := A_TickCount
	while (A_TickCount - t1 < 60000)
		{
		now := WalkZone(true)
		if (!WkLoading && now != "" && now != zone)
			{
			Sleep(2500)
			DebugLog("Potions: through the way out - in " WalkZone(true))
			return 1
			}
		Sleep(250)
		}
	DebugLog("Potions: walked into the way out, but still in " zone " a minute on - stopping")
	return -1
	}

;The nearest of zone's ways out whose name matches want (a regular expression): its volumes - the spheres that do
;something when walked into, read by the vision helper from the zone's own files - not a quest's ("Activator").
;{name, x, y, z, zone}, or ""
PotionDoor(zone, want)
	{
	answer := VisionGet("/volumes?zone=" LearnUri(zone), 5000, true)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	here := PotionNavTo(V1Obj({x: 0, y: 0, z: 0}))
	best := "", bestD := ""
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] != "vol" || f.Length < 6 || !RegExMatch(f[2], want) || InStr(f[2], "Activator"))
			continue
		d := IsObject(here) ? Sqrt((here.x - f[3]) ** 2 + (here.y - f[4]) ** 2) : 0
		if (bestD = "" || d < bestD)
			best := V1Obj({name: f[2], x: f[3] + 0, y: f[4] + 0, z: f[5] + 0, zone: zone}), bestD := d
		}
	return best
	}

;Out of the house - End goes nowhere in there (the Dorm): walked out through its way out (the Dorm's
;"Teleport_Out", into Ravenwood). True once out, or not in a house
PotionLeaveHouse(since)
	{
	zone := WalkZone(true)
	if (!InStr(zone, "Housing"))
		return true
	;(a way out - not a house's own teleports between its floors: TeleportVol_To_UpperLevel ...)
	door := PotionDoor(zone, "i)teleport_?out|exit")
	if (!IsObject(door))
		{
		DebugLog("Potions: in the house (" zone "), and no way out of it found in its files - End from here all the same")
		return true
		}
	DebugLog("Potions: in the house - End goes nowhere in there: out through its door first (" door.name ")")
	return PotionWalkTo(door, since, true)
	}

;To the Commons: out of the house first, then End - End not taking (no loading screen; it seems to take mana, and
;the run is for mana as often as not): through this zone's door to
;the Commons, if it has one (Ravenwood's). True if it went somewhere
PotionToCommons(since)
	{
	if (!PotionLeaveHouse(since))
		return false
	if (IsObject(PotionSellerIn(WalkZone(true))))
		return true
	if (PotionTeleport("{End}", "the Commons"))
		return true
	door := PotionDoor(WalkZone(true), "i)\(to Commons\)")
	if (!IsObject(door) || !PotionOk(true, since))
		return false
	DebugLog("Potions: End went nowhere (it seems to take mana) - to the Commons through the door instead (" door.name ")")
	return PotionWalkTo(door, since, true)
	}
;The shop's BUY button when the whole window's read missed it: under COST (its cost line), read in a box just below it
;at 3x - a word ending in UY there ("C)UY", "BUY"). {x, y} of its middle, or ""; seen: what was read added to it
PotionFindBuy(&seen)
	{
	c := PotionFindWords("i)^cost$", "", &costSeen, false)
	if (!IsObject(c))
		return ""
	bx := c.x - Round(40 * UiScale), by := c.y + Round(30 * UiScale)
	bt := OcrRect(bx, by, Round(220 * UiScale), Round(70 * UiScale), "en", 3, &bLines)
	seen .= " | under COST: " bt
	if (ErrorLevel || !IsObject(bLines))
		return ""
	for i, line in bLines
		for j, w in line.words
			if (RegExMatch(Trim(w.text), "i)^.{0,3}uy[.!]?$"))
				{
				DebugLog("Potions: BUY read under COST (as `"" Trim(w.text) "`")")
				return V1Obj({x: Round(w.x + w.w / 2), y: Round(w.y + w.h / 2)})
				}
	return ""
	}

;The words firstRe (and nextRe right after it, if given) in the middle of the game window, by OCR: {x, y} (screen)
;of their middle, or "" - the first found, or with rightmost the one furthest right. text: what was read there
PotionFindWords(firstRe, nextRe := "", &text := "", lone := false, rightmost := false)
	{
	text := OcrRect(Round(GameLeft + GameW * 0.12), Round(GameTop + GameH * 0.08), Round(GameW * 0.76), Round(GameH * 0.84), "en", 1, &lines)
	if (ErrorLevel || !IsObject(lines))
		return ""
	best := ""
	for i, line in lines
		{
		ws := line.words
		if (!IsObject(ws))
			continue
		for j, w in ws
			{
			if (!RegExMatch(Trim(w.text), firstRe) || (lone && ws.Length != 1))
				continue
			at := ""
			if (nextRe = "")
				at := V1Obj({x: Round(w.x + w.w / 2), y: Round(w.y + w.h / 2)})
			else if (j < ws.Length && RegExMatch(Trim(ws[j + 1].text), nextRe))
				{
				v := ws[j + 1]
				at := V1Obj({x: Round((w.x + v.x + v.w) / 2), y: Round(w.y + w.h / 2)})
				}
			if (IsObject(at) && !rightmost)
				return at
			if (IsObject(at) && (!IsObject(best) || at.x > best.x))
				best := at
			}
		}
	return best
	}

;Where the potion shop's Fill All button is, by its words - one look, Fill All, else Fill One just above it (+77 at
;UI scale 1; Fill All is greyed once the potions are full) - or "" when neither is read. The rightmost: once Fill All is
;picked its name shows on the left too, over the cost and BUY - not a button. shopSeen: the shop's own words read at
;all (its title, a Fill button)
PotionShopAnchor(&shopSeen := "")
	{
	shopText := OcrRect(Round(GameLeft + GameW * 0.12), Round(GameTop + GameH * 0.08), Round(GameW * 0.76), Round(GameH * 0.84), "en", 1, &shopLines)
	shopSeen := !ErrorLevel && RegExMatch(shopText, "i)mystical|mixtures|\bfill\b")
	if (ErrorLevel || !IsObject(shopLines))
		return ""
	fillAll := "", fillOne := ""
	for i, line in shopLines
		{
		ws := line.words
		if (!IsObject(ws))
			continue
		for j, w in ws
			{
			if (j >= ws.Length || !RegExMatch(Trim(w.text), "i)^fill$"))
				continue
			v := ws[j + 1], mid := Round((w.x + v.x + v.w) / 2)
			if (RegExMatch(Trim(v.text), "i)^all[.!]?$") && (!IsObject(fillAll) || mid > fillAll.x))
				fillAll := V1Obj({x: mid, y: Round(w.y + w.h / 2)})
			if (RegExMatch(Trim(v.text), "i)^one[.!]?$") && (!IsObject(fillOne) || mid > fillOne.x))
				fillOne := V1Obj({x: mid, y: Round(w.y + w.h / 2) + Round(77 * UiScale)})
			}
		}
	return IsObject(fillAll) ? fillAll : fillOne
	}

;The potion shop's close button - the red X at its bottom right corner, (235, 359) from Fill All at UI scale 1,
;measured on the live game - found by its colour in a small box round there (nothing else in the shop is that red),
;its middle checked to be that red too (not a red robe or mount passing the corner): true and its middle in x, y
PotionShopXFind(anchor, &x, &y)
	{
	shopX := anchor.x + Round(235 * UiScale), shopY := anchor.y + Round(359 * UiScale), shopR := Round(32 * UiScale)
	V1PixelSearch(&x, &y, Max(GameLeft, shopX - shopR), Max(GameTop, shopY - shopR), Min(GameLeft + GameW - 1, shopX + shopR), Min(GameTop + GameH - 1, shopY + shopR), 0xD20805, 40, "Fast RGB")
	;(not there - the anchor read off the left panel's "Fill All" title, the button not read: 2026-10-23 08:43, the X looked
	;for 570 px left of it - the close button's picture, the red X in its brown ring, looked for in the window's lower right)
	if (ErrorLevel)
		{
		V1ImageSearch(&x, &y, Round(GameLeft + GameW * 0.45), Round(GameTop + GameH * 0.5), Round(GameLeft + GameW * 0.9), Round(GameTop + GameH * 0.92), PicOpt("resources\closewin.png", 50))
		if (ErrorLevel)
			return false
		x += Round(30 * UiScale / 1.144), y += Round(30 * UiScale / 1.144)
		return true
		}
	;(the first red pixel is near the top of its cross: its middle is a little right of and below that)
	x += Round(5 * UiScale), y += Round(13 * UiScale)
	V1PixelSearch(&midX, &midY, x - 4, y - 4, x + 4, y + 4, 0xD20805, 50, "Fast RGB")
	return !ErrorLevel
	}

;Clicks the potion shop's close button (PotionShopXFind), hovered a moment first - with no Crown near and only while
;the bot may act (WalkMenuMayAct, from). 1 if clicked, 0 if not, -1 if the bot mayn't act (you've taken over, it's
;off, the game isn't in front)
PotionShopX(anchor, from)
	{
	if (!PotionShopXFind(anchor, &redX, &redY))
		{
		DebugLog("Potions: the shop's close button (its red X) wasn't found by " anchor.x + Round(235 * UiScale) - GameLeft "," anchor.y + Round(359 * UiScale) - GameTop)
		return false
		}
	if (!PotionNoCrowns(redX, redY))
		return false
	Critical()
	if (!WalkMenuMayAct(false, from))
		{
		Critical("Off")
		return -1
		}
	DebugLog("Potions: closing the shop with its X at " redX - GameLeft "," redY - GameTop)
	TargetClick(redX, redY)
	Critical("Off")
	return 1
	}

;The shop's up - by its own words (its X's red alone could be a robe or a mount): where its Fill All is, from those
;words, else Fill All's place read before it was clicked (known) while some of the shop's words are read; or ""
PotionShopUp(known := "")
	{
	shop := PotionShopAnchor(&shopSeen)
	if (IsObject(shop))
		return shop
	return (shopSeen && IsObject(known)) ? known : ""
	}

;Closes the potion shop's window with its own close button (PotionShopX - Escape doesn't close Hilda's shop, it opens
;Wizard101's menu over it). Escape only when no shop was seen at all (X opened something else, or nothing), and the
;game's menu closed again if that opened it (Walker.ahk WalkCloseGameMenu). known: Fill All's place, read before it
;was clicked. Nothing pressed or clicked with Wizard101 not in front, the bot off (F6; a run from the tray counts as
;on) or once you've touched the mouse or keyboard (since: the run's start, else from now) - each checked right before
;it. False (and PotionShopLeft) when the shop's still up: it's left to you - PotionCarryOn stops walking and says so
PotionCloseShop(since := 0, known := "")
	{
	global PotionShopLeft ; (v1 globals it sets)
	from := since ? since : A_TickCount
	shop := PotionShopUp(known)
	xClicks := 0, xGot := 0
	while (IsObject(shop) && xClicks < 2)
		{
		xGot := PotionShopX(shop, from)
		if (xGot != 1)
			break
		xClicks += 1
		Sleep(1000)
		shop := PotionShopUp(known)
		}
	if (IsObject(shop))
		{
		;(you've taken over, or the bot's off: it's yours - no notice)
		if (xGot = -1)
			{
			DebugLog("Potions: the shop's window left to you (Wizard101 isn't in front, the bot is off or you've taken over)")
			return false
			}
		PotionShopLeft := 1
		DebugLog("Potions: the shop's window is still open - left to you (" (xClicks ? "its X clicked " xClicks " times" : "its X couldn't be clicked") ")")
		return false
		}
	if (!xClicks)
		{
		;(no shop seen: X opened something else - a dialogue - or nothing: Escape, as ever)
		Critical()
		if (!WalkMenuMayAct(false, from))
			{
			Critical("Off")
			DebugLog("Potions: not closing what's open (Wizard101 isn't in front, the bot is off or you've taken over)")
			return true
			}
		DebugLog("Potions: no shop's window seen - Escape")
		Send("{Blind}{Escape}")
		Critical("Off")
		Sleep(800)
		}
	menuNow := WalkCloseGameMenu(false, &menuSeen, from)
	if (menuNow = 1)
		DebugLog("Potions: Escape had opened the game's menu - closed it")
	else if (menuNow = 2)
		DebugLog("Potions: the game's menu is open and didn't close - left to you")
	else if (menuNow = -1)
		DebugLog("Potions: closed - not checked for the game's menu (Wizard101 isn't in front, the bot is off or you've taken over)")
	else
		DebugLog("Potions: shop closed (read after: " (menuSeen = "" ? "nothing" : SubStr(menuSeen, 1, 160)) ")")
	return true
	}

;At the potion seller: X at her prompt, Fill All in her window (never with "Crown" round it), a box asking to
;pay with gold OK'd (same rule), the window closed. True if Fill All was clicked
PotionBuyHere(s, since := 0)
	{
	ReleaseKeys()
	t0 := A_TickCount
	while ((name := PotionPrompt()) = "" && A_TickCount - t0 < 2500)
		Sleep(300)
	;(no prompt yet: a step closer - she may stand behind her stall)
	if (name = "")
		{
		nav := PotionNavTo(s)
		h := IsObject(nav) ? WalkNavHeading(nav.x, nav.y, nav.yaw, s.x, s.y) : ""
		if (h != "")
			{
			PotionTurnBy(h)
			PotionHoldW(1)
			Sleep(500)
			PotionHoldW(0)
			t0 := A_TickCount
			while ((name := PotionPrompt()) = "" && A_TickCount - t0 < 2000)
				Sleep(300)
			}
		}
	if (name = "")
		{
		DebugLog("Potions: by the potion seller, but no 'Press X' prompt shows - not buying")
		return false
		}
	if (!PotionOk(true, since))
		return false
	DebugLog("Potions: " name "'s prompt - X")
	Send("{Blind}x")
	Sleep(1800)
	;(the right panel's Fill All - the rightmost: once picked, its name shows on the left too)
	w := PotionFindWords("i)^fill$", "i)^all[.!]?$", &seen, false, true)
	;(Crowns anywhere in the window: nothing clicked)
	if (IsObject(w) && RegExMatch(seen, "i)cr[o0]wn"))
		{
		DebugLog("Potions: `"Crown`" in the shop's window - not clicking, stopping (gold only): " SubStr(RegExReplace(seen, "\s+", " "), 1, 160))
		TrayTip("The potion run saw `"Crowns`" on screen and stopped (it only buys with gold).", "Wizard101 bot", 2)
		AlertSend("crowns", "potion run stopped", "`"Crowns`" on screen by the potion seller - it stopped without clicking (it only buys with gold).")
		PotionCloseShop(since, w)
		return false
		}
	if (!IsObject(w))
		{
		DebugLog("Potions: no Fill All on screen after X (read: " SubStr(RegExReplace(seen, "\s+", " "), 1, 160) ") - closing, not buying")
		PotionCloseShop(since)
		return false
		}
	if (!PotionNoCrowns(w.x, w.y) || !PotionOk(true, since))
		{
		PotionCloseShop(since, w)
		return false
		}
	DebugLog("Potions: Fill All at " w.x - GameLeft "," w.y - GameTop " - clicking")
	ClickAt(w.x, w.y, 300)
	Sleep(1000)
	;(Fill All only picks what to buy: its BUY button - on the left, under the cost - buys it, with gold. Only with no
	;Crown anywhere in the window nor round the button)
	b := PotionFindWords("i)^buy[.!]?$", "", &seen, true)
	;(not read - yellow on red reads badly at 1:1, 2026-10-23 08:43: "C)UY", or nothing - the box under COST read 3x)
	if (!IsObject(b))
		b := PotionFindBuy(&seen)
	if (!IsObject(b) || RegExMatch(seen, "i)cr[o0]wn") || !PotionNoCrowns(b.x, b.y) || !PotionOk(true, since))
		{
		DebugLog("Potions: " (!IsObject(b) ? "no BUY button after Fill All" : RegExMatch(seen, "i)cr[o0]wn") ? "`"Crown`" in the shop's window - BUY not clicked" : "BUY not clicked") " (read: " SubStr(RegExReplace(seen, "\s+", " "), 1, 160) ") - not bought")
		PotionCloseShop(since, w)
		return false
		}
	RegExMatch(seen, "i)cost\s*(\d[\d,]*)", &cost)
	;(v1: no cost read - cost1 blank)
	DebugLog("Potions: BUY at " b.x - GameLeft "," b.y - GameTop (V1At(cost, 1) != "" ? " (cost " cost[1] " gold)" : "") " - clicking")
	ClickAt(b.x, b.y, 300)
	Sleep(1200)
	;(a box asking to pay with gold: its OK / Yes - only with "gold" in it and no Crown round it)
	c := PotionFindWords("i)^(ok|okay|yes)[.!]?$", "", &seen, true)
	;(what's on screen after it - the shop still up, a box asking to pay, or nothing: for debug.log)
	DebugLog("Potions: after BUY, read: " (seen = "" ? "(nothing)" : SubStr(RegExReplace(seen, "\s+", " "), 1, 200)))
	if (IsObject(c) && RegExMatch(seen, "i)gold") && !RegExMatch(seen, "i)cr[o0]wn") && PotionOk(true, since) && PotionNoCrowns(c.x, c.y))
		{
		DebugLog("Potions: a box asking to pay with gold - OK")
		ClickAt(c.x, c.y, 300)
		Sleep(1000)
		}
	PotionCloseShop(since, w)
	return true
	}

;Out of potions, by the zone's map: the potion seller in this zone - else, in Wizard City, the Commons (End), or
;a Recall (Page Up) to your Mark - walked to, Fill All, drink, then on with the quest from there. True / false
;(bought or not); "" when the recorded ways are for here: a buying recorded at your Mark, potionmark:0's route,
;farming (afk, mob-loop, lore) away from her, the map walk impossible (the game's memory off, unchecked or
;unreadable) - checked before any teleport - or this way failed with a recorded one to try
PotionRunWalk()
	{
	global PotionShopLeft, PotionMarkZone, PotionMarkAt ; (v1 globals it sets)
	ReleaseKeys()
	since := A_TickCount
	PotionShopLeft := 0
	who := PotionWho()
	;(potionmark:0's route way is always there to try - it says so itself when there's no route)
	recorded := PotionByMark() ? PotionMarkFile(who) != "" : true
	;(the map walk needs the game's memory - on, its heading checked by the walker, readable now)
	if ((Stats.Has("navmem") && !Stats["navmem"]) || (!WkNavChecked && !WkNavTrusted))
		{
		DebugLog("Potions: no walking to the potion seller by the map (the game's memory " ((Stats.Has("navmem") && !Stats["navmem"]) ? "is off: navmem:0" : "hasn't been checked against the quest arrow yet - it is after a minute of walking a quest") ") - the recorded ways")
		return ""
		}
	zone := WalkZone(true)
	s := PotionSellerIn(zone)
	marked := false
	;(at her in the Commons already, a Mark kept from a run whose Recall didn't work: back to it after buying - not
	;while farming here)
	if (IsObject(s) && !(afkVar || loopmode || loremode) && PotionMarkKept(zone))
		{
		marked := true
		DebugLog("Potions: back to the mark made before (in " PotionMarkZone ") after buying")
		}
	if (!IsObject(s))
		{
		;(the ways you set up - a buying recorded at your Mark, potionmark:0's routes - and farming, which has
		;no way back from the Commons: as before)
		if (recorded || !PotionByMark() || afkVar || loopmode || loremode)
			return ""
		if (!IsObject(PotionNavTo(V1Obj({x: 0, y: 0, z: 0}))))
			{
			DebugLog("Potions: the game's memory can't be read (" VisionErr ") - no walking to the potion seller by the map")
			return ""
			}
		;Only Wizard City's Commons has a potion seller (Hilda Brewer). A Mark here to come back to (Page Down) - it
		;takes mana (up to 10): only one that took (mana went down) is gone back to. On the way to her (your house,
		;Ravenwood) no Mark: the last run's, kept when its Recall didn't work (too little mana), is gone back to
		;instead. Then outside Wizard City Home (your house in Wizard City) and the Commons (End; out of the house
		;through its door first - End goes nowhere in there)
		reused := false
		if (PotionOnRoute(zone))
			{
			if (PotionMarkKept(zone))
				{
				marked := true, reused := true
				DebugLog("Potions: no potion seller in " zone " - back to the mark made before (in " PotionMarkZone ") after buying")
				}
			else
				DebugLog("Potions: no potion seller in " zone " - no mark here, it's on the way to her (on from the Commons after buying)")
			}
		else
			{
			g := PotionGlobes()
			Send("{Blind}{PgDn}")
			Sleep(1500)
			;(the globe's number given a moment more to go down)
			took := (g.mana = "")
			Loop 4
				{
				if (took || (took := PotionArrivedMana(g.mana)))
					break
				Sleep(500)
				}
			if (took)
				{
				PotionMarkZone := zone, PotionMarkAt := A_TickCount, marked := true
				DebugLog("Potions: no potion seller in " zone " - marked this spot (Page Down) to come back to")
				}
			else
				{
				;(none taken, none made - and the last run's Mark is no good from here: not gone back to)
				PotionMarkZone := "", PotionMarkAt := 0
				DebugLog("Potions: no potion seller in " zone " - the Mark (Page Down) didn't take (mana " g.mana ": a Mark takes up to 10) - no recall after buying, on from the Commons")
				}
			}
		if (InStr(zone, "WizardCity/") != 1)
			{
			DebugLog("Potions: Home (the Home key), then the Commons (End)")
			if (!PotionTeleport("{Home}", "home"))
				{
				;(still here: a Mark made here is here too - nothing to go back to)
				if (!reused)
					PotionMarkZone := "", PotionMarkAt := 0
				PotionCarryOn(false)
				return false
				}
			;(home is a house - a loading screen into somewhere else (walked through a door meanwhile, the key not taken)
			;isn't: Home once more; still not one, the run's no good from here)
			if (!InStr(WalkZone(true), "Housing"))
				{
				DebugLog("Potions: Home went to " WalkZone(true) " - not a house: Home again")
				if (!PotionTeleport("{Home}", "home") || !InStr(WalkZone(true), "Housing"))
					{
					DebugLog("Potions: Home doesn't lead to a house from here (" WalkZone(true) ") - back to the mark; buy potions by hand this time")
					AlertSend("potions", "out of potions", "The Home key didn't lead to your house (" WalkZone(true) ") - back to where it was.")
					PotionRecall()
					PotionCarryOn(false)
					return false
					}
				}
			}
		else
			DebugLog("Potions: to the Commons (End)")
		if (PotionToCommons(since))
			zone := WalkZone(true), s := PotionSellerIn(zone)
		if (!IsObject(s))
			{
			DebugLog("Potions: no potion seller in " WalkZone(true) " after Home and the Commons - back to the mark. (Only Wizard City's Commons has one: is your house in another world?)")
			TrayTip("Out of potions - Home and the Commons (End) didn't lead to the potion seller (" WalkZone(true) ").`nThe bot went back to where it was. Is your house in Wizard City?", "Wizard101 bot", 2)
			AlertSend("potions", "out of potions", "Home and the Commons didn't lead to Wizard City's potion seller (" WalkZone(true) ") - back to where it was. Is your house in Wizard City?")
			PotionRecall()
			PotionCarryOn(false)
			return false
			}
		}
	if (!PotionWalkTo(s, since) || !PotionBuyHere(s, since))
		{
		ReleaseKeys()
		;(a recorded way to try, and nothing's said stop - a battle, your hands): that one. Not behind a shop's window
		;that couldn't be closed: that stops the run (PotionCarryOn says so)
		if (!marked && recorded && !PotionShopLeft && WalkZone(true) = s.zone && PotionOk(true, since))
			{
			DebugLog("Potions: the walk to the potion seller didn't work - the recorded way instead")
			return ""
			}
		;(marked: back to it all the same - not behind a shop's window that's still open)
		if (marked && !PotionShopLeft)
			PotionRecall()
		PotionCarryOn(false)
		return false
		}
	;(one drunk - then filled up again, so the run leaves her with full potions)
	ok := PotionAfterBuy(true)
	;(not with the shop's window still open - it couldn't be closed: PotionCarryOn says so)
	if (ok && !PotionShopLeft && PotionOk(true, since))
		{
		DebugLog("Potions: filling up again after drinking one")
		Sleep(800)
		PotionBuyHere(s, since)
		}
	if (marked && !PotionShopLeft)
		{
		;(a Recall takes up to 10 mana: a run for mana gets here with none - and at full health none was drunk)
		manaLeft := PotionGlobes().mana
		if (ok && manaLeft != "" && manaLeft < 10 && FleeDrinkForMana(manaLeft))
			DebugLog("Potions: mana " manaLeft " - drank one for the Recall (now " PotionGlobes().mana ")")
		PotionRecall()
		}
	PotionCarryOn(ok)
	return ok
	}

;On the way to the potion seller (your house, Ravenwood): no Mark made there - it would only lead back
PotionOnRoute(zone)
	{
	return InStr(zone, "Housing") || zone = "WizardCity/WC_Ravenwood"
	}

;A Mark made by a run whose Recall didn't work (too little mana) - kept, gone back to by the next run within the hour
PotionMarkKept(zone)
	{
	return PotionMarkZone != "" && PotionMarkZone != zone && A_TickCount - PotionMarkAt < 3600000
	}

;A Recall with no loading screen (the Mark in this zone): mana went down - read twice the same (its cost)
PotionArrivedMana(manaBefore)
	{
	if (manaBefore = "")
		return false
	a := PotionGlobes().mana
	Sleep(250)
	b := PotionGlobes().mana
	return (a != "" && a = b && a < manaBefore)
	}

;---- Recording a route (tray menu) ----

PotionRecordStart()
	{
	global PotionRecording, PotionMarkZone, PotionMarkAt, PotionRec, PotionRecStop, PotionRecDown, PotionRecAtMark ; (v1 globals it sets)
	global PotionRecRestart, PotionHook, PotionStopKey, ErrorLevel, PotionRecT0 ; (v1 globals it sets)
	if (PotionRecording)
		return
	if (DgRecording)
		{
		msgResult := MsgBox("A dungeon run is being recorded - finish that first (" HkName(DgRecKey) ").", "Record potion buying", 262192)
		return
		}
	;(battles only - Settings: battlesonly: recording takes you to the seller - a Recall, or a Mark and Home / End)
	if (BattlesOnly())
		{
		DebugLog("Potions: no recording of the potion buying - battles only is on (Settings): the bot moves nothing out of battle")
		msgResult := MsgBox("Battles only is on (Settings): the bot moves nothing out of battle, and recording the potion buying takes you to the seller (a Recall). Switch battles only off first (Settings, or the tray menu).", "Record potion buying", 262192)
		return
		}
	if (!VisionOn)
		{
		msgResult := MsgBox("The vision helper isn't running, so the bot can't follow loading screens. Restart the bot (" HkText("restart") ") and try again.", "Record potion buying", 48)
		return
		}
	;(its only way to stop: the Stop recording key)
	if (HkKeyOf("record") = "")
		{
		msgResult := MsgBox("Stop recording has no key - give it one on the dashboard's Keys tab first.", "Record potion buying", 48)
		return
		}
	atMark := PotionByMark()
	if (atMark)
		msgResult := MsgBox("First leave a Mark (Page Down) right next to the potion seller (Hilda Brewer, Wizard City's Commons) - the bot recalls you there every time you're out of potions. Each wizard has its own Mark: do this once for each.`n`nThe bot now recalls you to your Mark (Page Up). Once its `"Recording`" message shows, press X to talk, click Fill All with GOLD (and close the window), and press " HkText("record") ". (Not right by her? Walk there and press Page Down - the recording starts over from there.)`n`nYou stay at the seller afterwards.", "Record potion buying", 65)
	else
		msgResult := MsgBox("The bot will mark your spot (Page Down) and take you to " PotionStartName() ".`n`nThen walk to the potion seller (Hilda Brewer) with the KEYBOARD only, press X to talk, click Fill All with GOLD (and close the window), and press " HkText("record") ".`n`nUse the mount you'll farm with. The bot recalls you back afterwards.", "Record potion buying", 65)
	if (msgResult = "Cancel")
		return
	try WinActivate("ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no game window - nothing; v2 throws)
	Sleep(500)
	PotionRecording := 1
	ReleaseKeys()
	if (atMark)
		{
		;(never Page Down here: your Mark stays at the seller)
		g := PotionGlobes()
		if (!PotionTeleport("{PgUp}", "your Mark", PotionArrived.Bind(V1Obj({prompt: ""}), g.mana)))
			{
			;(a Recall in the Mark's own zone may not show a loading screen)
			msgResult := MsgBox("Page Up (Recall) showed no loading screen - in the Mark's own zone it may not.`n`nAre you standing at your Mark, right next to the potion seller?`n`nYes: record here. No: stop (leave a Mark there first, with some mana for the Recall).", "Record potion buying", 36)
			if (msgResult = "No")
				{
				PotionRecording := 0
				return
				}
			try WinActivate("ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no game window - nothing; v2 throws)
			Sleep(500)
			}
		}
	else
		{
		startZone := WalkZone(true)
		Send("{Blind}{PgDn}")
		PotionMarkZone := startZone, PotionMarkAt := A_TickCount
		Sleep(1500)
		if (!PotionTeleport(PotionStartKey(), PotionStartName()))
			{
			PotionRecording := 0
			msgResult := MsgBox("The teleport to " PotionStartName() " didn't happen (no loading screen) - nothing recorded.", "Record potion buying", 48)
			return
			}
		}
	;(PotionRec: the events only - the start line is made when saving, with the prompt read meanwhile)
	commons := WalkZone(true), prompt := ""
	PotionRec := "", PotionRecStop := 0, PotionRecDown := V1Obj()
	PotionRecAtMark := atMark, PotionRecRestart := 0
	PotionHook := InputHook("V L0")
	PotionHook.KeyOpt("{All}", "N")
	PotionHook.OnKeyDown := PotionRecKey.Bind(1)
	PotionHook.OnKeyUp := PotionRecKey.Bind(0)
	Hotkey("~*LButton", PotionRecClick, "On")
	;(the key that stops it - the Keys tab's, F9 out of the box - as it was when the recording began)
	PotionStopKey := HkKeyOf("record")
	;(v1: Hotkey ... UseErrorLevel - ErrorLevel 0, or its code: 2 a key name that isn't one; v2 throws)
	if (PotionStopKey != "")
		{
		try
			Hotkey("$" PotionStopKey, PotionRecF9, "On"), ErrorLevel := 0
		catch as e
			ErrorLevel := InStr(e.Message, "Invalid key name") ? 2 : 1
		}
	if (PotionStopKey = "" || ErrorLevel)
		DebugLog("Potions: the Stop recording key " HkName(PotionStopKey) " couldn't be made (" ErrorLevel ") - the recording stops by itself after 15 minutes")
	PotionRecT0 := A_TickCount
	PotionHook.Start()
	TrayTip("Recording " (atMark ? "at your Mark in " commons ": X to talk" : "from " commons ": walk to the potion seller") ", buy Fill All, then press " HkName(PotionStopKey) ".", "Wizard101 bot", 1)
	DebugLog("Potions: recording " (atMark ? "the buying at your Mark in " : "a route from ") commons)
	;(the seller's prompt, read while the recording already runs - an X meanwhile is kept)
	if (atMark)
		prompt := PotionPromptSteady()
	lastZone := commons, t0 := A_TickCount
	;(a loading screen on the way: noted when it's done, as replaying waits for that and goes on from there)
	while (!PotionRecStop && A_TickCount - t0 < 15 * 60000)
		{
		Sleep(50)
		z := WalkZone(true)
		if (z != lastZone && !WkLoading)
			PotionRec .= (A_TickCount - PotionRecT0) "|zone|" z "`r`n", lastZone := z
		;(Page Down at the Mark way: your Mark is here now, so the recording starts here)
		;(PotionRecKey already started the events over, at the Page Down itself)
		if (PotionRecRestart)
			{
			PotionRecRestart := 0, commons := lastZone
			DebugLog("Potions: Page Down - your Mark is here now (" commons "): recording again from here")
			TrayTip("Your Mark is here now - the recording starts again from here. X to talk, Fill All, then " HkName(PotionStopKey) ".", "Wizard101 bot", 1)
			prompt := PotionPromptSteady()
			}
		}
	PotionHook.Stop()
	Hotkey("~*LButton", "Off")
	if (PotionStopKey != "")
		V1Do(Hotkey, "$" PotionStopKey, "Off")
	PotionRecording := 0, PotionRecAtMark := 0
	if (atMark)
		{
		;(no prompt read at the start - the shop may have been open: her prompt is back now it's closed)
		if (prompt = "")
			prompt := PotionPromptSteady()
		DebugLog("Potions: the prompt here: " (prompt = "" ? "none read (no check that a run is at the seller)" : prompt))
		;(the buying needs the X that opens her shop and the Fill All click)
		missing := (RegExMatch(PotionRec, "im)^\d+\|key\|x\|down") ? "" : "no X press (to talk to her)") (InStr(PotionRec, "|click|") ? "" : (RegExMatch(PotionRec, "im)^\d+\|key\|x\|down") ? "" : " and ") "no click (Fill All)")
		if (missing != "")
			{
			msgResult := MsgBox("The recording has " missing ".`n`nThe bot couldn't buy with it. Save it anyway?`n`n(No: nothing saved - record again, and press X once the `"Recording`" message shows.)", "Record potion buying", 308)
			if (msgResult = "No")
				{
				DebugLog("Potions: buying not saved (" missing ")")
				try WinActivate("ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no game window - nothing; v2 throws)
				PotionWalkFresh()
				return
				}
			}
		}
	V1Do(DirCreate, A_WorkingDir "\routes")
	who := PotionWho()
	file := atMark ? PotionMarkFile(who, true) : PotionRouteFile(commons)
	head := "start|" commons "|" Round(UiScale, 3) "|" GameW "x" GameH (atMark ? "|mark|" prompt : "")
	V1Do(FileDelete, file)
	V1Do(FileAppend, "; Potion " (atMark ? "buying at your Mark in " : "route from ") commons ", recorded " A_YYYY "-" A_MM "-" A_DD " " A_Hour ":" A_Min " (Potions.ahk): ms|key|name|down/up, ms|click|x|y (UI px from the window's middle), ms|zone|<zone after a loading screen>`r`n" head "`r`n" PotionRec, file)
	DebugLog("Potions: " (atMark ? "buying" : "route") " saved: " file)
	if (atMark)
		{
		PotionOff().Delete(who), PotionOff().Delete("anyone")
		msgResult := MsgBox("Saved the buying at this wizard's Mark in " commons (prompt = "" ? "" : " (by " prompt ")") ".`n`nOut of potions, the bot recalls here, buys, and walks on from here. Keep the Mark here (don't Page Down anywhere else)." (prompt = "" ? "`n`n(No `"Press X`" prompt was read here, so a run can't check it's at the seller - better to record standing where her prompt shows.)" : ""), "Record potion buying", 64)
		try WinActivate("ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no game window - nothing; v2 throws)
		PotionWalkFresh()
		return
		}
	msgResult := MsgBox("Saved the route from " commons ".`n`nThe bot now recalls you to where you were (Page Up).", "Record potion buying", 64)
	try WinActivate("ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no game window - nothing; v2 throws)
	Sleep(500)
	PotionRecall()
	}

;A key going down or up while recording (repeats of a held key and keys with Ctrl/Alt/Win aren't kept;
;F9 ends the recording)
PotionRecKey(isDown, hook, vk, sc)
	{
	global PotionRec, PotionRecDown, PotionRecT0, PotionRecRestart ; (v1 globals it sets)
	name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
	;(the stop key's own key left out only when it's a plain one - Ctrl/Alt/Win stop keys never come here as such, and a
	;plain X of the route must be kept even when the stop key is Ctrl+X)
	stopBase := RegExMatch(PotionStopKey, "[#^!]") ? "" : RegExReplace(PotionStopKey, "^[#^!+]*")
	if ((stopBase != "" && name = stopBase) || InStr(name, "Control") || InStr(name, "Alt") || InStr(name, "Win") || InStr(name, "Shift"))
		return
	;(teleport keys aren't part of a route; Page Down at the Mark way moves the Mark here: start over)
	if (RegExMatch(name, "i)^(Numpad)?(PgDn|PgUp|Home|End)$"))
		{
		if (isDown && PotionRecAtMark && RegExMatch(name, "i)PgDn$"))
			PotionRec := "", PotionRecDown := V1Obj(), PotionRecT0 := A_TickCount, PotionRecRestart := 1
		return
		}
	if (isDown && (GetKeyState("Ctrl") || GetKeyState("Alt") || GetKeyState("LWin") || GetKeyState("RWin")))
		return
	if (isDown && PotionRecDown[name])
		return
	if (!isDown && !PotionRecDown[name])
		return
	PotionRecDown[name] := isDown
	PotionRec .= (A_TickCount - PotionRecT0) "|key|" name "|" (isDown ? "down" : "up") "`r`n"
	}

PotionRecClick:
PotionRecClick()
	return

PotionRecF9:
PotionRecF9()
	return

;###############  (v2 port: v1's labels, as functions)  ###############
PotionRecClick(ThisHotkey:="") { ; (v1: a label - its code ran in the global scope)
	global
	CoordMode("Mouse", "Screen")
	MouseGetPos(&mx, &my)
	if (GameActive())
		PotionRec .= (A_TickCount - PotionRecT0) "|click|" Round((mx - GameLeft - GameW / 2) / UiScale, 1) "|" Round((my - GameTop - GameH / 2) / UiScale, 1) "`r`n"
	return
}
;##############################################
PotionRecF9(ThisHotkey:="") { ; (v1: a label - its code ran in the global scope)
	global
	PotionRecStop := 1
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
PotionsBlank()
	{
	global PotionNextCheck := "", PotionMaxHp := "", PotionFailUntil := "", PotionRecording := "", PotionStopKey := "", PotionRec := ""
	global PotionRecStop := "", PotionRecT0 := "", PotionRecDown := "", PotionHook := "", PotionMarkZone := "", PotionMarkAt := ""
	global PotionMarkOff := "", PotionRecAtMark := "", PotionRecRestart := "", PotionShopLeft := "", PotionResting := "", PotionNoneAt := ""
	global PotionRestFrom := "", GameLeft := "", GameW := "", UiScale := "", GameTop := "", GameH := ""
	}
