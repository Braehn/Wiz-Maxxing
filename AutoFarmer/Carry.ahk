; Carry.ahk - two Wizard101 clients on one PC (asked 2026-11-11): the main wizard - the one being levelled - quests, walks,
; drinks and shops as ever, and the carry - a max-level wizard riding along on the main's mount - does the battles. Each
; battle round: the main passes at once (its Pass button), then the carry's window is brought to the front, its round
; played the bot's usual way, and the main's window brought back. A battle over: the carry's window comes up for a few
; seconds for its mount's prompt (X - Party.ahk PartyRidePrompt's words; untried in the game: its words logged), then the
; main's again. Out of battle nothing else touches the carry.
; The windows are told apart by their process: the main is the Wizard101 window in front when carry mode is switched on
; (its key, Alt+T - the dashboard's Keys tab), the carry the other one. The vision helper reads the game's memory of the
; client in front (/client - one reader each, vision.py nav_reader), so the walker, the hand and the health read stay that
; wizard's. Not with dual mode (Alt+D - its Alt+Tab after each round) or a third client. Kept in dashboard.ini [carry]
; (main, carry: their pids) - taken up again at the next start while both still run. A client gone (closed, restarted by
; a reconnect): carry mode off, said, and an alert.
; AutoHotkey v2 (the v1 port's conventions - CONVENTIONS.md), #Included by Autofarmer.ahk.

;On, the two windows and their processes; whose window is in front now (0 the main's, 1 the carry's) and since when;
;the helper's client as last set (its pid, "" not set); the dashboard.ini entry looked at (once a run); the mount's
;prompts said ({letters: 1}); the battles the carry played a round of (for the log) and the rounds this battle
global CarryOn, CarryMainHwnd, CarryMainPid, CarryHwnd, CarryPid, CarryTurn, CarryTurnAt, CarryPin, CarryRestored
global CarrySaidPrompts, CarryRounds, CarryMainRounds

CarryBlank()
	{
	global
	CarryOn := 0, CarryMainHwnd := 0, CarryMainPid := 0, CarryHwnd := 0, CarryPid := 0, CarryTurn := 0, CarryTurnAt := 0
	CarryPin := "", CarryRestored := 0, CarrySaidPrompts := Map(), CarryRounds := 0, CarryMainRounds := 0
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

;Alt+T (Hotkeys.ahk "carry"): carry mode on or off
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
	;(the main: the game window in front - you switched it on from the main's window; else the topmost)
	csMain := 1
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
	CarryOn := 0
	if (CarryTurn && wasMain && WinExist("ahk_id " wasMain))
		try WinActivate("ahk_id " wasMain)
	CarryTurn := 0
	VisionGet("/client?pid=0", 1500, true), CarryPin := ""
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
;why - for the log (said once a turn change). True if it's in front
CarryFront(which, why, quiet := false)
	{
	global CarryTurn, CarryTurnAt, CarryPin
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

;The helper reads the client whose window is in front (VisionGameClients: one client as far as the memory's concerned)
CarryPinnedFront()
	{
	if (!CarryOn || CarryPin = "")
		return false
	return CarryPin = (CarryTurn ? CarryPid : CarryMainPid)
	}

;RoundStart (Autofarmer.ahk): the main's turn - its Pass clicked at once (the carry does the battle). True: the round's
;done (EndRound switches to the carry)
CarryRoundMain()
	{
	global CarryMainRounds
	if (!CarryOn || CarryTurn)
		return false
	CarryMainRounds += 1
	cpOk := ClickPass()
	DebugLog("  Carry: the main " (cpOk ? "passes" : "couldn't find its Pass button") " - the carry plays this round")
	return true
	}

;Whether the round now starting is the main's own pass in carry mode (TestRound: the round count is the carry's)
CarryMainTurn()
	{
	return CarryOn && !CarryTurn
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
	DebugLog("Carry: the battle's over - the main passed " CarryMainRounds " round(s), the carry played " CarryRounds)
	CarryRounds := 0, CarryMainRounds := 0
	if (!StatOr("partyride", 1) || PlayerActing())
		return
	if (!CarryFront(1, "the battle's over - its mount's prompt"))
		{
		CarryFront(0, "back to the main")
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
	CarryFront(0, "back to the main")
	}
