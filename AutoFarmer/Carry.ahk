; Carry.ahk - two Wizard101 clients on one PC (asked 2026-11-11): the main wizard - the one being levelled - quests, walks,
; drinks and shops as ever, and the carry - a max-level wizard riding along on the main's mount - fights alongside it. Each
; battle round the main plays first, on its own window, then the carry's window is brought to the front, its round played
; the bot's usual way, and the main's window brought back. What the main does (Settings: carrymain - asked 2026-11-15):
; plays its own hand as the bot plays any wizard (1, the default), Blader - its blades and traps on the carry, the party
; code's battle part with the carry as the hitter (2), Healer (3), or passes at once and leaves the battle to the carry (4,
; as before 2026-11-15). Each wizard's battle - its blades and traps cast, its planned hit, its deck, the round count, its
; plate - is its own: kept aside while the other plays (CarrySwap). A battle over: the carry's window comes up for a few
; seconds for its mount's prompt (X - Party.ahk PartyRidePrompt's words; untried in the game: its words logged), then the
; main's again. Out of battle nothing else touches the carry.
; The windows are told apart by their process: the main is the client picked as the main (Alt+M, below), else the Wizard101
; window in front when carry mode is switched on (its key, Alt+K - the dashboard's Keys tab; not Alt+T, the dashboard's
; Settings menu), the carry the other one. The vision helper reads the game's memory of the client whose turn it is
; (/client - one reader each, vision.py nav_reader), so the walker, the hand, the health and the wizard's name stay that
; wizard's - the game's log is no help there: both clients write the one WizardClient.log. Not with dual mode (Alt+D - its
; Alt+Tab after each round) or a third client. Kept in dashboard.ini [carry] (main, carry: their pids) - taken up again at
; the next start while both still run. A client gone (closed, restarted by a reconnect): carry mode off, said, and an alert.
; The main client (Alt+M - asked 2026-11-15): the Wizard101 client the bot plays, with two or more open - pressed in its
; window. Every window the bot finds, activates or measures is that one's (GameWT: ahk_pid), and the helper reads its
; memory; the others are left alone. Kept in dashboard.ini [main] (pid) while it runs. Its game gone (closed, crashed):
; nothing else is played meanwhile - a client that's new since it was picked (its game started again: the reconnect, you)
; is taken as the main.
; AutoHotkey v2 (the v1 port's conventions - CONVENTIONS.md), #Included by Autofarmer.ahk.

;On, the two windows and their processes; whose window is in front now (0 the main's, 1 the carry's) and since when;
;the helper's client as last set (its pid, "" not set); the dashboard.ini entry looked at (once a run); the mount's
;prompts said ({letters: 1}); the battles the carry played a round of (for the log) and the rounds this battle
global CarryOn, CarryMainHwnd, CarryMainPid, CarryHwnd, CarryPid, CarryTurn, CarryTurnAt, CarryPin, CarryRestored
global CarrySaidPrompts, CarryRounds, CarryMainRounds
;Each wizard's battle kept aside while the other plays (CarrySwap): [main's, carry's] - a Map of its battle's globals, ""
;none yet this battle; the battle they're for (BlDuel). Each wizard's name and school as its own client's memory has them
;(CarryNoteMe - the round's start): [main's, carry's]
global CarryState, CarryStateDuel, CarryNames, CarrySchools
;The main client (Alt+M): its process (0 none - the window in front, as ever), the other clients' when it was picked
;({pid: 1}), whether its game's being gone was said
global MainPid, MainOthers, MainGoneSaid

CarryBlank()
	{
	global
	CarryOn := 0, CarryMainHwnd := 0, CarryMainPid := 0, CarryHwnd := 0, CarryPid := 0, CarryTurn := 0, CarryTurnAt := 0
	CarryPin := "", CarryRestored := 0, CarrySaidPrompts := Map(), CarryRounds := 0, CarryMainRounds := 0
	CarryState := ["", ""], CarryStateDuel := "", CarryNames := ["", ""], CarrySchools := ["", ""]
	MainPid := 0, MainOthers := Map(), MainGoneSaid := 0
	}

;---- the main client (Alt+M) ----

;The Wizard101 client the bot works on now: carry mode's whose turn it is, else the main picked (Alt+M), else 0 - any (the
;window in front, else the topmost)
GamePid()
	{
	if (CarryOn)
		return CarryTurn ? CarryPid : CarryMainPid
	return MainPid
	}

;The game's window for the client the bot works on now, as a WinTitle: "ahk_class ... ahk_exe ...", with its ahk_pid when
;one's picked - the other clients' windows are never found, brought up or measured. The main's game gone: no window at all
GameWT()
	{
	gwP := GamePid()
	return "ahk_class " GameClass " ahk_exe " GameExe (gwP ? " ahk_pid " gwP : "")
	}

;The game running (Reconnect.ahk): the picked client's process when one's picked, else any Wizard101's - its pid, 0 none
GameRunning()
	{
	grP := GamePid()
	return grP ? ProcessExist(grP) : ProcessExist(GameExe)
	}

;Alt+M (Hotkeys.ahk "main"): the Wizard101 window in front is the main client from now on - the one the bot plays; pressed
;in the main's window again: none (the window in front, as ever)
HkMain(*)
	{
	hmP := 0, hmGame := 0
	try hmGame := WinActive("ahk_class " GameClass " ahk_exe " GameExe)
	if (!hmGame)
		{
		TrayTip("Click into the Wizard101 window the bot should play, then press " HkText("main") ".", "Wizard101 bot", 2)
		return
		}
	try hmP := WinGetPID("ahk_id " hmGame)
	if (!hmP)
		return
	if (hmP = MainPid)
		MainSet(0, HkText("main") " pressed in the main's window again")
	else
		MainSet(hmP, "picked with " HkText("main"))
	}

;The main client set - pid, 0 none: kept in dashboard.ini [main], said, the helper reading its memory; carry mode's main
;from now on (the other client the carry)
MainSet(pid, why, quiet := false)
	{
	global MainPid, MainOthers, MainGoneSaid, CarryMainHwnd, CarryMainPid, CarryHwnd, CarryPid
	MainPid := pid, MainOthers := Map(), MainGoneSaid := 0
	msN := 0
	for i, w in CarryGameWins()
		{
		msN += 1
		if (w.pid != pid)
			MainOthers[w.pid] := 1
		}
	try
		{
		if (pid)
			IniWrite(pid, A_ScriptDir "\dashboard.ini", "main", "pid")
		else
			IniDelete(A_ScriptDir "\dashboard.ini", "main")
		}
	;(carry mode on the other way round: the main and the carry swapped - the main's window brought up)
	if (CarryOn && pid && pid = CarryPid)
		{
		msH := CarryMainHwnd, msP := CarryMainPid
		CarryMainHwnd := CarryHwnd, CarryMainPid := CarryPid, CarryHwnd := msH, CarryPid := msP
		CarrySave()
		DebugLog("Carry: the main wizard's window is process " CarryMainPid " now, the carry's " CarryPid)
		CarryFront(0, "the main picked", true)
		}
	else if (!CarryOn)
		MainPin()
	DebugLog(pid ? "Main client: Wizard101 process " pid " (" why ") - the bot plays, walks and reads that one only" (msN > 1 ? "; the other " (msN - 1) " client" (msN > 2 ? "s are" : " is") " left alone" : "") : "Main client: none (" why ") - the Wizard101 window in front, as ever")
	if (!quiet)
		TrayTip(pid ? "This Wizard101 window is the main one - the bot plays only it. " HkText("main") " in it again: any window." : "No main Wizard101 window picked - the bot plays the one in front.", "Wizard101 bot", 1)
	}

;The helper reading the main's memory (carry mode off) - the window in front's with none picked
MainPin()
	{
	global CarryPin
	if (CarryOn)
		return
	mpAns := VisionGet("/client?pid=" MainPid, 1500, true)
	CarryPin := MainPid && SubStr(mpAns, 1, 2) = "OK" ? MainPid : ""
	UpdateGameRect()
	}

;Each pass of the loop (CarryTick): the main taken up again from dashboard.ini once a run while its game still runs; its game
;gone - nothing else played (said once), and a client new since it was picked (its game started again) taken as the main
MainTick()
	{
	global MainGoneSaid
	static restored := 0, lookAt := 0
	if (!restored)
		{
		restored := 1
		mtP := 0
		try mtP := Integer(IniRead(A_ScriptDir "\dashboard.ini", "main", "pid", 0))
		if (mtP && CarryWinOf(mtP))
			MainSet(mtP, "picked in the last run", true)
		else if (mtP)
			try IniDelete(A_ScriptDir "\dashboard.ini", "main")
		}
	if (!MainPid || A_TickCount - lookAt < 2000)
		return
	lookAt := A_TickCount
	if (CarryWinOf(MainPid))
		{
		MainGoneSaid := 0
		;(the helper not on it yet - it wasn't running when picked: pinned now)
		if (!CarryOn && CarryPin != MainPid && VisionOn)
			MainPin()
		return
		}
	for i, w in CarryGameWins()
		if (w.pid != MainPid && !MainOthers.Has(w.pid))
			{
			DebugLog("Main client: process " MainPid " is gone - the new Wizard101 window (process " w.pid ") is the main now")
			return MainSet(w.pid, "the main's game started again", true)
			}
	if (!MainGoneSaid)
		{
		MainGoneSaid := 1
		DebugLog("Main client: Wizard101 process " MainPid " is gone - the other client" (MainOthers.Count = 1 ? " isn't" : "s aren't") " played; a Wizard101 started from now on is the main (" HkText("main") " in another window picks that one)")
		}
	}

;The Wizard101 windows now: [{hwnd, pid}] (front to back)
CarryGameWins()
	{
	out := []
	try
		for cgH in WinGetList("ahk_class " GameClass " ahk_exe " GameExe)
			{
			cgP := 0
			try cgP := WinGetPID("ahk_id " cgH)
			out.Push({hwnd: cgH, pid: cgP})
			}
	return out
	}

;The window of process pid now ("" none) - a client restarted by the game itself keeps its pid, its window may be new
CarryWinOf(pid)
	{
	if (!pid)
		return 0
	for i, w in CarryGameWins()
		if (w.pid = pid)
			return w.hwnd
	return 0
	}

;Alt+K (Hotkeys.ahk "carry"): carry mode on or off
HkCarry(*)
	{
	if (CarryOn)
		CarryOff("switched off (" HkText("carry") ")")
	else
		CarryStart()
	}

;Carry mode on: two Wizard101 windows, the one in front (else the topmost) the main's. Said why not, else on. True if on
CarryStart(quiet := false)
	{
	global CarryOn, CarryMainHwnd, CarryMainPid, CarryHwnd, CarryPid, CarryRounds, CarryMainRounds
	csNo := ""
	wins := CarryGameWins()
	if (dualmode == 1)
		csNo := "dual mode (" HkText("dual") ") is on - it switches windows its own way"
	else if (wins.Length != 2)
		csNo := wins.Length " Wizard101 window" (wins.Length = 1 ? " is" : "s are") " open - carry mode needs exactly two (the main wizard's and the carry's)"
	if (csNo != "")
		{
		DebugLog("Carry: not on - " csNo)
		if (!quiet)
			TrayTip("Carry mode not on: " csNo ".", "Wizard101 bot", 2)
		return false
		}
	;(the main: the client picked as the main (Alt+M); else the game window in front - you switched it on from the main's
	;window; else the topmost)
	csMain := 1
	if (MainPid && (wins[1].pid = MainPid || wins[2].pid = MainPid))
		csMain := wins[2].pid = MainPid ? 2 : 1
	else
		try
			{
			csAct := WinActive("ahk_class " GameClass " ahk_exe " GameExe)
			if (csAct && csAct = wins[2].hwnd)
				csMain := 2
			}
	CarryMainHwnd := wins[csMain].hwnd, CarryMainPid := wins[csMain].pid
	CarryHwnd := wins[3 - csMain].hwnd, CarryPid := wins[3 - csMain].pid
	CarryOn := 1, CarryRounds := 0, CarryMainRounds := 0
	CarrySave()
	;(both clients' readers start attaching now - the first look through a client's code takes seconds)
	VisionGet("/client?pids=" CarryMainPid "," CarryPid, 1500, true)
	CarryFront(0, "carry mode on", true)
	DebugLog("Carry: on - the main wizard's window is process " CarryMainPid ", the carry's " CarryPid ". In a battle the main passes and the carry plays each round; " HkText("carry") " switches it off")
	if (!quiet)
		TrayTip("Carry mode on: the main passes in battles, the other window's wizard plays them. " HkText("carry") " switches it off.", "Wizard101 bot", 1)
	return true
	}

;Carry mode off (why - for the log): the main's window in front, the helper back to reading the foreground client
CarryOff(why, alert := false)
	{
	global CarryOn, CarryTurn, CarryPin
	if (!CarryOn)
		return
	wasMain := CarryMainHwnd
	;(in a battle on the carry's turn: the main's own battle back - CarrySwap)
	if (CarryTurn && inbattle == 1)
		CarrySwap(1, 0)
	CarryStateDrop()
	CarryOn := 0
	if (CarryTurn && wasMain && WinExist("ahk_id " wasMain))
		try WinActivate("ahk_id " wasMain)
	CarryTurn := 0
	;(the helper back on the main picked (Alt+M), else the window in front)
	CarryPin := "", MainPin()
	try IniDelete(A_ScriptDir "\dashboard.ini", "carry")
	DebugLog("Carry: off - " why)
	if (alert)
		{
		TrayTip("Carry mode off: " why ".", "Wizard101 bot", 2)
		AlertSend("carry", "carry mode off", "Carry mode (two clients) went off: " why ". Switch it on again from the main wizard's window (" HkText("carry") ").")
		}
	}

;Kept for the next start: dashboard.ini [carry]
CarrySave()
	{
	ini := A_ScriptDir "\dashboard.ini"
	try
		{
		IniWrite(CarryMainPid, ini, "carry", "main")
		IniWrite(CarryPid, ini, "carry", "carry")
		}
	}

;Once a run (CarryTick): carry mode taken up again from dashboard.ini while both processes still have their windows
CarryRestore()
	{
	global CarryRestored, CarryOn, CarryMainHwnd, CarryMainPid, CarryHwnd, CarryPid
	if (CarryRestored)
		return
	CarryRestored := 1
	ini := A_ScriptDir "\dashboard.ini"
	crMain := 0, crCarry := 0
	try crMain := Integer(IniRead(ini, "carry", "main", 0))
	try crCarry := Integer(IniRead(ini, "carry", "carry", 0))
	if (!crMain || !crCarry)
		return
	hM := CarryWinOf(crMain), hC := CarryWinOf(crCarry)
	if (!hM || !hC || dualmode == 1)
		{
		DebugLog("Carry: not taken up again - " (dualmode == 1 ? "dual mode is on" : "the clients it was on for (processes " crMain ", " crCarry ") aren't both open") " (" HkText("carry") " switches it on)")
		try IniDelete(ini, "carry")
		return
		}
	CarryMainHwnd := hM, CarryMainPid := crMain, CarryHwnd := hC, CarryPid := crCarry, CarryOn := 1
	VisionGet("/client?pids=" CarryMainPid "," CarryPid, 1500, true)
	DebugLog("Carry: on again from the last run - the main wizard's window is process " CarryMainPid ", the carry's " CarryPid)
	CarryFront(0, "carry mode on again", true)
	}

;Each pass of the battle loop (TestRound): taken up again once; both clients still there (a window replaced by its own
;process: followed), else off and said
CarryTick()
	{
	global CarryMainHwnd, CarryHwnd
	MainTick()
	CarryRestore()
	if (!CarryOn)
		return
	if (!WinExist("ahk_id " CarryMainHwnd))
		{
		h := CarryWinOf(CarryMainPid)
		if (!h)
			return CarryOff("the main wizard's client (process " CarryMainPid ") has closed", true)
		CarryMainHwnd := h
		}
	if (!WinExist("ahk_id " CarryHwnd))
		{
		h := CarryWinOf(CarryPid)
		if (!h)
			return CarryOff("the carry's client (process " CarryPid ") has closed", true)
		CarryHwnd := h
		}
	}

;Window which (0 the main's, 1 the carry's) in front, the game's rect measured on it and the helper reading its client;
;why - for the log (said once a turn change). In a battle each wizard's own battle goes with its turn (CarrySwap - swap
;false: not, the battle's over). True if it's in front
CarryFront(which, why, quiet := false, swap := true)
	{
	global CarryTurn, CarryTurnAt, CarryPin
	if (swap && inbattle == 1 && which != CarryTurn)
		CarrySwap(CarryTurn, which)
	cfH := which ? CarryHwnd : CarryMainHwnd
	cfP := which ? CarryPid : CarryMainPid
	cfOk := false
	try
		{
		if (!WinActive("ahk_id " cfH))
			{
			WinActivate("ahk_id " cfH)
			WinWaitActive("ahk_id " cfH, , 1)
			}
		cfOk := WinActive("ahk_id " cfH) ? true : false
		}
	CarryTurn := which, CarryTurnAt := A_TickCount
	UpdateGameRect()
	if (CarryPin != cfP)
		{
		cfAns := VisionGet("/client?pid=" cfP, 1500, true)
		CarryPin := SubStr(cfAns, 1, 2) = "OK" ? cfP : ""
		}
	if (!quiet)
		DebugLog("Carry: " (which ? "the carry's" : "the main's") " window " (cfOk ? "in front" : "couldn't be brought to the front") " - " why)
	return cfOk
	}

;The helper reads the client the bot plays now - carry mode's whose turn it is, else the main picked (Alt+M)
;(VisionGameClients: one client as far as the memory's concerned)
CarryPinnedFront()
	{
	if (CarryPin = "")
		return false
	if (!CarryOn)
		return MainPid && CarryPin = MainPid
	return CarryPin = (CarryTurn ? CarryPid : CarryMainPid)
	}

;What the main does in carry mode's battles (Settings: carrymain): "own" plays its own hand, "blader", "healer", "pass"
CarryMainSet()
	{
	cmR := StatOr("carrymain", 1)
	return cmR = 2 ? "blader" : cmR = 3 ? "healer" : cmR = 4 ? "pass" : "own"
	}

;RoundStart (Autofarmer.ahk): the main's turn - played as any round (carrymain: its own hand, Blader, Healer), or its Pass
;clicked at once (carrymain: Passes - the carry does the battle). True: the round's done (EndRound switches to the carry)
CarryRoundMain()
	{
	global CarryMainRounds
	if (!CarryOn || CarryTurn)
		return false
	CarryMainRounds += 1
	if (CarryMainSet() != "pass")
		{
		DebugLog("  Carry: the main's round (" CarryMainSet() (CarryMainSet() = "own" ? " hand" : "") ") - the carry's next")
		return false
		}
	cpOk := ClickPass()
	DebugLog("  Carry: the main " (cpOk ? "passes" : "couldn't find its Pass button") " - the carry plays this round")
	return true
	}

;Whether the round now starting is the main's own in carry mode
CarryMainTurn()
	{
	return CarryOn && !CarryTurn
	}

;Whether the round now starting is the main's pass in carry mode (carrymain: Passes - TestRound: not a round of its count)
CarryMainPassing()
	{
	return CarryMainTurn() && CarryMainSet() = "pass"
	}

;This round's wizard as its own client's memory has it (RoundStart - Autofarmer.ahk RoundBattleMem): its name and school
;kept for the round (OwnName: your plate found by it) and for the other's (the carry, the hitter its Blader or Healer
;boosts - CarryHitter)
CarryNoteMe(name, sch)
	{
	global CarryNames, CarrySchools
	if (!CarryOn)
		return
	cnI := CarryTurn + 1
	if (Trim(name) != "" && CarryNames[cnI] != Trim(name))
		{
		CarryNames[cnI] := Trim(name)
		DebugLog("  Carry: the " (CarryTurn ? "carry" : "main") " wizard is " CarryNames[cnI] " (its client's memory)")
		}
	if (sch != "")
		CarrySchools[cnI] := sch
	}

;Your own wizard's name in carry mode (EnemySpells.ahk OwnName): the one whose round it is, by its client's memory - the
;game's log can't tell, both clients write it. "" not carry mode, or not read yet
CarryOwnName()
	{
	return CarryOn ? CarryNames[CarryTurn + 1] : ""
	}

;The battle part this round (Party.ahk PartyBattleSet) in carry mode: the carry hits; the main's is carrymain's - Blader,
;Healer, else it hits. "" not carry mode: the party's setting
CarryBattlePart()
	{
	if (!CarryOn)
		return ""
	if (CarryTurn)
		return "hitter"
	cbS := CarryMainSet()
	return (cbS = "blader" || cbS = "healer") ? cbS : "hitter"
	}

;Carry mode (Party.ahk PartyHitter): on the main's turn the carry is the hitter its boosts go to - by its name (its client's
;memory, from the round it last played) among your side's in the game's log (slots: name key -> slot, twice: names two
;have). "" on the carry's own turn, or its name not read yet (its first round still to come) or not on your side
CarryHitter(slots, twice)
	{
	if (!CarryOn || CarryTurn)
		return ""
	chK := PartyKey(CarryNames[2])
	if (StrLen(chK) < 3 || !slots.Has(chK) || twice.Has(chK))
		return ""
	;(its hits so far and its last one's round - kept aside with its battle while the main plays: a Blader's boosts go on again
	;after each - Party.ahk PartyReblade)
	chS := CarryState[2], chHits := "", chHitR := ""
	if (IsObject(chS))
		chHits := chS.Has("PartyHits") ? chS["PartyHits"] : "", chHitR := chS.Has("PartyHitR") ? chS["PartyHitR"] : ""
	return V1Obj({wiz: CarryNames[2], school: CarrySchools[2], hits: chHits, hitr: chHitR, slot: slots[chK], plan: "", lasthit: ""
		, hitat: "", seat: ""})
	}

;---- each wizard's own battle ----

;The battle's globals each wizard keeps for itself (CarrySwap): every one ResetVariables starts a battle with but the
;battle's own (CarryShared), the boost flags (ResetUsed: used0-52), the plate's battle and the deck picked for the battle
;(Decks.ahk), the hits it cast (KillCalc.ahk - a Blader re-blades after each: CarryHitter). test_carry.py: each of
;ResetVariables' names here or in CarryShared
CarryStateNames()
	{
	static names := ""
	if (!IsObject(names))
		{
		names := ["roundnumber", "playerX", "playerY", "Player", "boosts", "BoostRun", "sharpen", "potent", "blade", "blade2", "blade3"
			, "blade4", "trap", "trap2", "trap3", "trap4", "feint", "aura", "enchant", "reshuffle", "hit1", "hit2", "hit3", "hit4"
			, "EnchantedHits", "PipSaveFor", "PipSaveRounds", "PipSaveGaveUp", "PipSaveTarget", "PipSaveStall", "PipSaveLastPips"
			, "PlayerTookRound", "RoundLeft", "RoundAgain", "FleeNoHits", "FleeHitsRound", "DrawsBattle", "DrawOff", "LearnHitFails"
			, "OwnHpPct", "OwnHpRound", "tower", "hitter", "hitschool", "hammerX", "hammerY", "hitterX", "hitterY", "school", "schoolX"
			, "schoolY", "bladetype", "traptype", "BattleRole", "HammerSchool", "HammerName", "HammerSlot", "HammerGroup"
			, "SidePlatesKey", "MySlot", "PartyHitsSeen", "PartyHitsDuel", "PartyHitsWait", "PartyLowKey", "PartyLowX", "PartyLowY"
			, "TrapOn", "TrapMine", "TrapAtMax", "TrapPick", "TrapWhy", "TrapFoeX", "TrapFoeY", "TrapFoeMax", "TrapFoeN", "TrapSlot"
			, "PartyFlagDuel", "PartyFlagRound", "PartyCastRound", "Manual", "ManualSchool", "AppliedBlades", "BossTraps"
			, "AuraRounds", "HeadsMemo", "BoostPctMem", "AuraSch", "PartyLastSch", "PlanHit", "PlanHeads", "PlanList", "BladeDir"
			, "TrapDir", "BladeU1", "BladeU2", "TrapU1", "TrapU2", "Blade2U1", "Blade2U2", "Trap2U1", "Trap2U2", "SbFound", "GbFound"
			, "BoostHand", "BoostSrcUsed", "BoostExtra", "HammerPlan", "BoostMemOk", "BoostSaid", "BoostMisfitDone", "DeckSharp"
			, "SpentOff", "BoostUnrec", "BoostOneOfOff", "BoostMemOnly", "BubbleUp", "NegAuraOn", "absorb", "AbsorbFreeOk"
			, "AbsorbOnlyFree", "negaura", "ConvertOn"
			, "PlateDuel", "DeckDuel", "DeckNow", "DeckFoe", "DeckFoeTries", "DeckFoeKnown", "PartyHits", "PartyHitR", "PartyMySchool"]
		Loop 53
			names.Push("used" (A_Index - 1))
		}
	return names
	}

;ResetVariables' names that are the battle's, not a wizard's: in it, the Alt+1 boss and its plate, the enemies' health,
;dual mode, the health shown
CarryShared()
	{
	return ["inbattle", "BossChoosen", "bossX", "bossY", "BossSlot", "BossMax", "EnemyHP", "DualBattle", "HealthStatus"]
	}

;The turn changing in a battle (CarryFront): the wizard leaving's battle kept aside (from: 0 the main, 1 the carry) and the
;other's put back - as a battle starts the first time it plays this battle (ResetVariables, the battle's own kept)
CarrySwap(from, to)
	{
	global
	local csNames, csN, csV, csSaved, csI, csShared, csKeep
	if (CarryStateDuel != BlDuel)
		CarryState := ["", ""], CarryStateDuel := BlDuel
	csNames := CarryStateNames()
	csSaved := Map()
	for csI, csN in csNames
		try csSaved[csN] := %csN%
	CarryState[from + 1] := csSaved
	if (IsObject(CarryState[to + 1]))
		{
		for csN, csV in CarryState[to + 1]
			%csN% := csV
		return
		}
	;(its first round of this battle: as a new battle's - the battle's own kept as they are)
	csShared := CarryShared(), csKeep := Map()
	for csI, csN in csShared
		try csKeep[csN] := %csN%
	ResetVariables()
	ResetUsed()
	PlateDuel := "", DeckDuel := "", DeckNow := "", DeckFoe := "", DeckFoeTries := 0, DeckFoeKnown := 0
	for csN, csV in csKeep
		%csN% := csV
	}

;A battle over (CarryBattleOver), the main's battle back: what was kept aside dropped
CarryStateDrop()
	{
	global CarryState, CarryStateDuel
	CarryState := ["", ""], CarryStateDuel := ""
	}

;EndRound (Autofarmer.ahk): the main just passed - the carry's window up for its round; the carry's round done - the
;main's window back
CarryRoundEnd()
	{
	global CarryRounds
	if (!CarryOn)
		return
	if (!CarryTurn)
		CarryFront(1, "its round")
	else
		{
		CarryRounds += 1
		CarryFront(0, "the carry's round is done")
		}
	}

;TestRound with the carry's window in front (bookSeen: its spellbook showing - it isn't in a battle): back to the main's
;window when the carry has no round to play - out of battle, or no Pass button within 6 s of coming up (the battle's
;spells still going, or the carry not in it). True: back to the main (the loop goes round again), or still waiting - nothing
;else done on the carry's window (no walking, potions or out-of-battle work on the wrong wizard)
CarryNoRound(bookSeen)
	{
	if (!CarryOn || !CarryTurn)
		return false
	if (bookSeen)
		{
		CarryFront(0, "the carry isn't in a battle (its spellbook shows)")
		return true
		}
	if (PassButtonAt(&cnX, &cnY) = 0)
		return false
	if (A_TickCount - CarryTurnAt > 6000)
		{
		CarryFront(0, "no round up on the carry's window for 6 s")
		return true
		}
	Sleep(200)
	return true
	}

;A battle over (the main's spellbook back - TestRound): the carry's window up for its mount's prompt - X at one to ride
;(PartyRidePrompt), looked for up to 6 s - then the main's again. Its prompt's words logged once each (what it really says)
CarryBattleOver()
	{
	global CarryRounds, CarryMainRounds
	global WkPromptText, WkPromptVerb, WkPromptDest ; (InteractPrompt's)
	if (!CarryOn)
		return
	DebugLog("Carry: the battle's over - the main " (CarryMainSet() = "pass" ? "passed " : "played ") CarryMainRounds " round(s), the carry played " CarryRounds)
	CarryRounds := 0, CarryMainRounds := 0
	;(the main's battle the one left - ResetVariables clears it next; the carry's dropped)
	if (CarryTurn)
		CarryFront(0, "the battle's over", true)
	CarryStateDrop()
	if (!StatOr("partyride", 1) || PlayerActing())
		return
	if (!CarryFront(1, "the battle's over - its mount's prompt", false, false))
		{
		CarryFront(0, "back to the main", false, false)
		return
		}
	cbEnd := A_TickCount + 6000, cbRode := false
	while (A_TickCount < cbEnd && !cbRode)
		{
		Sleep(700)
		if (!CarryOn || PlayerActing() || !WinActive("ahk_id " CarryHwnd))
			break
		if (InteractPrompt() != "press")
			continue
		cbText := SubStr(RegExReplace(WkPromptText, "\s+", " "), 1, 100)
		if (PartyRidePrompt(WkPromptText, WkPromptVerb, ""))
			{
			Send("{Blind}x")
			DebugLog("Carry: pressed X on the carry's window to ride the mount - the prompt: `"" cbText "`"")
			cbRode := true
			Sleep(1200)
			break
			}
		if (!CarrySaidPrompts.Has(WkPromptDest))
			{
			CarrySaidPrompts[WkPromptDest] := 1
			DebugLog("Carry: a prompt on the carry's window: `"" cbText "`" (Press X to " WkPromptVerb ") - not one to ride a mount: no X")
			}
		}
	if (!cbRode)
		DebugLog("Carry: no mount prompt on the carry's window in 6 s - left as it is")
	CarryFront(0, "back to the main", false, false)
	}
