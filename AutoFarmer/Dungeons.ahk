#Warn Unreachable, Off
; Dungeons.ahk - dungeon farming: a run you record once, walked again and again (the dashboard's Dungeons tab).
; AutoHotkey v2 (ported from v1.1), functions and labels; #Included by Autofarmer.ahk. Needs the vision helper and the
; game's memory (read-only: where the wizard is, which zone) - the same as walking by the map.
;
; Recording (Record a run): stand where the run starts - outside the dungeon, by its sigil - and play one run the
; way the bot should: X at the sigil, walk to the boss (fighting on the way), and walk back out to where you started.
; Then F9 (or Stop recording). Every 200 game units walked is a spot to walk to; each X you press is "press X here"
; (a sigil, a door, someone to talk to); a battle's start is "a battle here" (on the way back it waits a moment
; for one there); a loading screen starts the next zone's spots. Walking (F8) is off while you record. Saved as
; dungeons\<name>.txt - one step a line: kind|zone|x|y|z (walk, x, fight) - kept by updates.
;
; Running (pick one, Run): the bot walks from spot to spot by the zone's map (the route planner, round walls),
; presses X where you did, lets every battle be fought (the battle loop - the bot on, F6), Spaces through a
; dialogue, and at the end starts over - so many times (0: till you stop it). A loading screen into a zone further
; on: it carries on from there. Walking off (F8), you playing, a battle: it waits. Somewhere the recording doesn't
; go (another zone), stuck for good, or the game's memory unreadable: it stops and says why (debug.log "Dungeons: ...",
; the Dungeons tab, Discord). A defeat or a potion run that leaves the wizard in an earlier zone of the run (v1.0.0): on
; from the nearest step of that zone's first visit, 3 times a run at most - never on to its later visit on the way back out.
;
; Between runs (v1.0.0, TODO goal 5): a run that ends back where it starts is "between runs" from its end to its first X
; (or another zone) - its drops looked at and the gear pass (Gear.ahk - Settings: gearswap, a rehearsal: the plan logged,
; nothing equipped), and a full backpack quick sold there (QuickSell.ahk - quicksell on; the dungeon's hold still holds it
; - with the gear pass on, its Deck and Pet groups only - unless "...even with a dungeon's drops in it" is ticked). "Until its
; gear is swapped" (the tab's box - untilgear| in the run's file): once every slot it drops (slots|, else
; resources\dungeons_known.txt's) is worn with its own drop, or stopafter| runs (30) brought no upgrade, it goes on to its
; "then" run (next|) when that starts where the wizard stands - else it stops and says where to take the wizard
; (Discord). A boss's own deck: boss|<name>|<deck id> lines (Decks.ahk DeckPick). Older versions skip these lines.
; python vision\dglint.py checks a run's file.

;The run being walked: {name, file, steps [{kind, zone, x, y, z}], i (the step walked to), runs (done), want (0
;till stopped), the step's progress (best, bestLeft, bestAt, unstuck), fightUntil / fightBattles (waiting at a
;battle spot), loadUntil (waiting for a loading screen out of zone fromZone), push (a spot past a doorway to walk at
;meanwhile), misses, seen (battles at the last look); v1.0.0: between (1 a run just done back at its start - the pass
;due, 2 done, "" in the run), resumes (back in an earlier zone this run), slots, stopafter, next, untilgear, bosses
;([{name, deck}]), gearSaid, gearMarked (1 the backpack noted at this run's start - Gear.ahk GearRunMark / GearRunEnd)} - ""
;when none
global DgRun
;Recording: on, its steps so far, the last spot recorded, its zone, when the Pass button was last up
global DgRecording, DgRecSteps, DgRecLast, DgRecZone, DgRecBattleAt, DgRecPrev, DgRecOut
;The Dungeons tab's controls (Dashboard.ahk makes them)
global DashTabs, DgList, DgHelp, DgRecBtn, DgRecStopBtn, DgRunBtn, DgStopBtn, DgDelBtn, DgFolderBtn, DgTimes, DgTimesUD
global DgAvoid, DgStatus, DgTimesLabel, DgTimesNote, DgDeck, DgDeckT
;(the key that stops a recording - the Keys tab's, F9 out of the box - as it was when the recording began)
global DgRecKey
;(the Deck box's decks by their place in it - 2 on; 1 is "(none)")
global DgDeckIds
;(v1.0.0: the tab's "Until its gear is swapped" box, its "then" label and list - and the list's runs by their place in it,
;2 on; 1 is "(stop)")
global DgUntilGear, DgNextT, DgNextRun, DgNextNames

;The folder the runs are kept in
DgDir()
	{
	return A_ScriptDir "\dungeons"
	}

;A run's file read: {name, file, steps, deck, slots, stopafter, next, untilgear, bosses} - "" if it can't be read or has
;fewer than two steps
DgLoad(file)
	{
	steps := [], name := "", deck := "", slots := "", stopafter := "", nxt := "", untilgear := 0, bosses := []
	;(v1: a file that can't be read - the loop skipped; v2 throws)
	try
	Loop Read, file
		{
		line := Trim(A_LoopReadLine)
		if (line = "" || SubStr(line, 1, 1) = ";")
			continue
		f := StrSplit(line, "|")
		;(v1: a field the line doesn't have - blank; a coordinate that isn't a number + 0 - blank)
		if (f[1] = "name")
			name := V1At(f, 2)
		;(the deck the run's fought with - Decks.ahk; older versions skip the line)
		else if (f[1] = "deck")
			deck := RegExReplace(V1At(f, 2), "[^\w-]")
		;(v1.0.0 - older versions skip these: the gear slots the dungeon drops, the runs with no upgrade before its gear counts
		;as all swapped, the run after it, "until its gear is swapped", a boss's own deck - Gear.ahk, Decks.ahk DeckPick;
		;python vision\dglint.py checks them)
		else if (f[1] = "slots")
			slots := RegExReplace(StrLower(V1At(f, 2)), "[^a-z, `;/]")  ; (`; - a space and ; would start a comment)
		else if (f[1] = "stopafter")
			stopafter := RegExMatch(Trim(V1At(f, 2)), "^\d{1,5}$") ? Trim(V1At(f, 2)) + 0 : ""
		else if (f[1] = "next")
			nxt := Trim(V1At(f, 2))
		else if (f[1] = "untilgear")
			untilgear := Trim(V1At(f, 2)) = "1" ? 1 : 0
		else if (f[1] = "boss" && Trim(V1At(f, 2)) != "")
			bosses.Push(V1Obj({name: Trim(V1At(f, 2)), deck: RegExReplace(V1At(f, 3), "[^\w-]")}))
		else if (RegExMatch(f[1], "^(walk|x|fight)$") && f.Length >= 5 && f[3] f[4] f[5] != "")
			steps.Push(V1Obj({kind: f[1], zone: f[2], x: V1Add(f[3], 0), y: V1Add(f[4], 0), z: V1Add(f[5], 0)}))
		}
	if (steps.Length < 2)
		return ""
	if (name = "")
		SplitPath(file, , , , &name)
	return V1Obj({name: name, file: file, steps: steps, deck: deck, slots: slots, stopafter: stopafter, next: nxt, untilgear: untilgear, bosses: bosses})
	}

;The distance across (x, y) between two steps or spots - "" when a coordinate isn't a number (a step's blank: DgLoad keeps
;one with a coordinate or two)
DgDist(ddA, ddB)
	{
	if (!(V1IsNum(ddA.x) && V1IsNum(ddA.y) && V1IsNum(ddB.x) && V1IsNum(ddB.y)))
		return ""
	return Sqrt((ddA.x - ddB.x) ** 2 + (ddA.y - ddB.y) ** 2)
	}

;A run that ends back where it starts (the same zone, within 400 - Record a run's own warning): between two runs the wizard
;stands outside the dungeon
DgEndsAtStart(r)
	{
	deaD := DgDist(r.steps[1], r.steps[r.steps.Length])
	return r.steps[1].zone = r.steps[r.steps.Length].zone && deaD != "" && deaD <= 400
	}

;The run file named name in the folder (its name| - else its file's name -, not case-sensitive), "" none
DgFindRun(name)
	{
	if (name = "")
		return ""
	Loop Files, DgDir() "\*.txt"
		{
		SplitPath(A_LoopFilePath, , , , &dfrBase)
		if (dfrBase = name)
			return A_LoopFilePath
		dfrD := DgLoad(A_LoopFilePath)
		if (IsObject(dfrD) && dfrD.name = name)
			return A_LoopFilePath
		}
	return ""
	}

;A run's name as its drop log's file name (vision\gearrank.py run_file: no path characters, 80 at most) - not DgRunFile, the
;Run / Delete buttons' global (a function's name is a global too in v2)
DgDropFile(name)
	{
	drfS := Trim(SubStr(RegExReplace(Trim(name), "[^\w .()-]+", "-"), 1, 80), " .")
	return drfS != "" ? drfS : "run"
	}

;The Dungeons tab's Gear column for run name: its gear pass's state (learned\drops\<run>.state - written at each run's end
;with gearswap on): "done", "N runs, M dry", "" none yet - "(until swapped)" when its box is ticked
DgGearCell(name, untilgear)
	{
	dgcF := A_ScriptDir "\learned\drops\" DgDropFile(name) ".state"
	dgcU := untilgear ? "until swapped" : ""
	if (!FileExist(dgcF))
		return dgcU
	dgcRuns := IniRead(dgcF, "run", "runs", ""), dgcDry := IniRead(dgcF, "run", "dry", ""), dgcDone := IniRead(dgcF, "run", "done", "")
	dgcT := dgcDone = 1 ? "done" : dgcRuns != "" ? dgcRuns " run" (dgcRuns = 1 ? "" : "s") ", " dgcDry " dry" : ""
	return dgcT (dgcT != "" && dgcU != "" ? " - " : "") dgcU
	}

;The list on the Dungeons tab filled from the folder (the run being walked selected)
DgListFill()
	{
	if (!DashHwnd)
		return
	;(v1: Gui, Dash:Default / Gui, Dash:ListView, DgList - v2: the ListView itself)
	LV := Dash["DgList"]
	LV.Delete()
	Loop Files, DgDir() "\*.txt"
		{
		d := DgLoad(A_LoopFilePath)
		if (!IsObject(d))
			continue
		zones := V1Obj(), nx := 0, nf := 0
		for i, s in d.steps
			zones[s.zone] := 1, nx += (s.kind = "x"), nf += (s.kind = "fight")
		nz := 0
		for z in zones
			nz++
		when := FormatTime(A_LoopFileTimeModified, "yyyy-MM-dd HH:mm")
		;(v1.0.0: its gear pass's state after the hidden File column - DgSelected reads the 7th)
		row := LV.Add("", d.name, d.steps.Length, nz, nx, nf, when, A_LoopFilePath, DgGearCell(d.name, d.untilgear))
		if (IsObject(DgRun) && DgRun.file = A_LoopFilePath)
			LV.Modify(row, "Select Focus")
		}
	}

;The selected run's file ("" none)
DgSelected()
	{
	;(v1: Gui, Dash:Default / Gui, Dash:ListView, DgList - v2: the ListView itself; its 7th column the file)
	LV := Dash["DgList"]
	row := LV.GetNext(0)
	if (!row)
		return ""
	file := LV.GetText(row, 7)
	return file
	}

;The status line on the Dungeons tab (and the buttons that go with it)
DgShow(text := "")
	{
	if (!DashHwnd)
		return
	if (text = "")
		{
		if (DgRecording)
			text := "Recording: " DgRecSteps.Length " steps so far, in " DgRecZone ". Press " HkName(DgRecKey) " (or Stop recording) once you're back where you started."
		else if (IsObject(DgRun))
			text := "Running '" DgRun.name "': run " DgRun.runs + 1 (DgRun.want ? " of " DgRun.want : "") (DgRun.untilgear ? " (until its gear is swapped)" : "")
				. (DgRun.between ? ", between runs" : ", step " DgRun.i " of " DgRun.steps.Length) (Walking ? "" : " - paused (walking off: " HkText("walk") ")")
		else
			text := "Not running. Record a run, or pick one and click Run."
		}
	Dash["DgStatus"].Text := text
	Dash["DgRecBtn"].Enabled := !(DgRecording || IsObject(DgRun))
	Dash["DgRecStopBtn"].Enabled := DgRecording ? true : false
	Dash["DgRunBtn"].Enabled := !(DgRecording || IsObject(DgRun))
	Dash["DgStopBtn"].Enabled := IsObject(DgRun) ? true : false
	}

;---- Recording ----

DgRecordStart()
	{
	global Walking, DgRecSteps, DgRecZone, DgRecBattleAt, DgRecLast, DgRecPrev, DgRecOut, DgRecording, DgRecKey ; (v1 globals it sets)
	if (DgRecording || IsObject(DgRun))
		return
	if (PotionRecording)
		{
		msgResult := MsgBox("The potion buying is being recorded - finish that first (" HkName(PotionStopKey) ").", "Record a dungeon run", 262192)
		return
		}
	nav := VisionOn ? NavRead(2000) : ""
	if (!IsObject(nav) || nav.x = "" || nav.zone = "")
		{
		msgResult := MsgBox("The bot can't read where your wizard is from the game's memory (" (VisionOn ? NavWhy : "the vision helper isn't running") "). Be in the game, in the world (not loading), and try again.", "Record a dungeon run", 262192)
		return
		}
	msgResult := MsgBox("Recording from here (" nav.zone ").`n`nPlay one run the way the bot should: X at the dungeon's sigil, walk to the boss (fight on the way), and walk back out to here. Then press " HkText("record") " (or Stop recording on the Dungeons tab).`n`nWalk with the keyboard or the mouse, as you like. Quest walking (" HkText("walk") ") is off while you record.", "Record a dungeon run", 262177)
	if (msgResult = "Cancel")
		return
	if (Walking)
		Walking := 0, ReleaseKeys(), SetStatus("walking off - recording a dungeon run")
	DgRecSteps := [], DgRecZone := nav.zone, DgRecBattleAt := 0, DgRecLast := "", DgRecPrev := nav, DgRecOut := 1
	DgRecAdd("walk", nav)
	DgRecording := 1
	;(the X key's hotkey is Puzzle.ahk's when it has one - it calls DgRecX while recording: two hotkeys of the same variant would
	;replace each other)
	if (!(V1IsFunc("PuzzleXHook") && %"PuzzleXHook"%.Call()))
		Hotkey("~*x", DgRecXKey, "On")
	DgRecKey := HkKeyOf("record")
	;(v1's UseErrorLevel: a key that can't be a hotkey - nothing made, no error; v2 throws. Nothing here reads ErrorLevel)
	if (DgRecKey != "")
		try Hotkey("$" DgRecKey, DgRecF9, "On")
	SetTimer(DgRecTick,250)
	DebugLog("Dungeons: recording a run from " nav.zone " at " Round(nav.x) ", " Round(nav.y) " - " HkName(DgRecKey) " to finish")
	TrayTip("Recording a dungeon run from " nav.zone ". Play it, come back here, then press " HkName(DgRecKey) ".", "Wizard101 bot", 1)
	DgShow()
	;(a dungeon played: its drops held from quick selling too - QuickSell.ahk)
	if (V1IsFunc("QsDungeonMark"))
		QsDungeonMark.Call()
	}

;A step recorded where nav says the wizard is
DgRecAdd(kind, nav)
	{
	global DgRecLast ; (v1 globals it sets)
	DgRecSteps.Push(V1Obj({kind: kind, zone: nav.zone, x: nav.x, y: nav.y, z: nav.z}))
	DgRecLast := V1Obj({x: nav.x, y: nav.y, z: nav.z, zone: nav.zone})
	DgShow()
	}

;Every 250 ms while recording: a spot every 200 game units walked, the first in a new zone (a loading screen), a
;battle's start (the Pass button up after none for 15 s) - nothing while one's on
DgRecTickF()
	{
	global DgRecOut, DgRecBattleAt, DgRecZone, DgRecPrev ; (v1 globals it sets)
	if (!DgRecording)
		{
		SetTimer(DgRecTick,0)
		return
		}
	V1ImageSearch(&bx, &by, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundstart.png"))
	battle := (ErrorLevel = 0)
	;(out of battle again - the spellbook up - since the last: a new battle counts as one)
	if (!battle)
		{
		V1ImageSearch(&bx, &by, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
		if (ErrorLevel = 0)
			DgRecOut := 1
		}
	nav := NavRead(400)
	if (!IsObject(nav) || nav.x = "" || nav.zone = "")
		return
	if (battle)
		{
		if (DgRecOut)
			{
			DgRecOut := 0
			;(where the wizard was walking when it started: the last spot, as the battle moves it into the circle)
			last := DgRecSteps[DgRecSteps.Length]
			DgRecSteps.Push(V1Obj({kind: "fight", zone: last.zone, x: last.x, y: last.y, z: last.z}))
			DebugLog("Dungeons: recording - a battle (" DgRecSteps.Length " steps)")
			DgShow()
			}
		DgRecBattleAt := A_TickCount
		return
		}
	;(right after a battle the wizard stands where its circle was: carry on from there)
	if (nav.zone != DgRecZone)
		{
		;(the old zone's last spot - at its doorway - unless it's the last step already: the replay walks on past it. Not right
		;after an X there, within 100 (v1.0.0): that's the wizard drifting while a sigil counted down, not a doorway - the X took
		;him through, and a walk step after it had the replay walk on past it, off the sigil, which stops its countdown (DgNext
		;waits for the load at such a step in a run recorded before))
		drtDrift := IsObject(DgRecPrev) && DgRecPrev.zone = DgRecZone ? DgDist(DgRecPrev, DgRecLast) : ""
		drtAfterX := DgRecSteps.Length && DgRecSteps[DgRecSteps.Length].kind = "x"
		if (drtDrift != "" && drtDrift > 30 && !(drtAfterX && drtDrift <= 100))
			DgRecAdd("walk", DgRecPrev)
		DgRecZone := nav.zone
		DebugLog("Dungeons: recording - into " nav.zone)
		DgRecAdd("walk", nav)
		DgRecPrev := nav
		return
		}
	DgRecPrev := nav
	if (Sqrt((nav.x - DgRecLast.x) ** 2 + (nav.y - DgRecLast.y) ** 2) >= 200 || Abs(nav.z - DgRecLast.z) > 120)
		DgRecAdd("walk", nav)
	}

;X pressed in the game while recording: "press X here"
DgRecX()
	{
	if (!DgRecording || !GameActive())
		return
	nav := NavRead(400)
	if (!IsObject(nav) || nav.x = "" || nav.zone = "")
		return
	DgRecAdd("x", nav)
	DebugLog("Dungeons: recording - X pressed in " nav.zone " (" DgRecSteps.Length " steps)")
	}

;Recording ends: named and saved (save false: thrown away)
DgRecordStop(save := true)
	{
	global DgRecording, ErrorLevel ; (v1 globals it sets)
	if (!DgRecording)
		return
	DgRecording := 0
	SetTimer(DgRecTick,0)
	;(Puzzle.ahk's X hotkey stays on: it's the bot's own)
	if (!(V1IsFunc("PuzzleXHook") && %"PuzzleXHook"%.Call()))
		Hotkey("~*x", "Off")
	if (DgRecKey != "")
		V1Do(Hotkey, "$" DgRecKey, "Off")
	;(Stop recording's caption: the key set now again, if it was changed meanwhile)
	if (DgRecKey != HkKeyOf("record") && V1IsFunc("DashKeysChanged"))
		DashKeysChanged.Call()
	steps := DgRecSteps
	if (!save || steps.Length < 3)
		{
		DebugLog("Dungeons: recording " (save ? "too short - nothing saved" : "thrown away"))
		DgShow(save ? "The recording was too short - nothing saved." : "")
		return
		}
	first := steps[1], last := steps[steps.Length]
	away := Round(Sqrt((first.x - last.x) ** 2 + (first.y - last.y) ** 2))
	SplitPath(first.zone, &start)
	day := FormatTime(, "yyyy-MM-dd")
	IB := InputBox(steps.Length " steps recorded." (first.zone != last.zone || away > 400 ? "`n`nIt ends " (first.zone != last.zone ? "in another zone (" last.zone ")" : away " away from where it started") " - a run that's to start over should end back where it began." : "") "`n`nName it:", "Save the dungeon run", "w460 h190", start " " day), name := IB.Value, ErrorLevel := IB.Result="OK" ? 0 : IB.Result="CANCEL" ? 1 : IB.Result="Timeout" ? 2 : "ERROR"
	if (ErrorLevel || Trim(name) = "")
		{
		DebugLog("Dungeons: recording not saved (no name)")
		DgShow("Not saved.")
		return
		}
	name := Trim(RegExReplace(name, "[\\/:*?`"<>|]", "-"))
	V1Do(DirCreate, DgDir())
	file := DgDir() "\" name ".txt"
	text := "; Wiz-Maxxing dungeon run, recorded " A_Now ". One step a line: kind|zone|x|y|z`r`n"
		. "; walk: walk to this spot; x: press X here (a sigil, a door, someone to talk to); fight: a battle started here`r`n"
		. "name|" name "`r`n"
	for i, s in steps
		text .= s.kind "|" s.zone "|" Round(s.x, 1) "|" Round(s.y, 1) "|" Round(s.z, 1) "`r`n"
	V1Do(FileDelete, file)
	V1Do(FileAppend, text, file)
	DebugLog("Dungeons: saved '" name "' - " steps.Length " steps (" file ")")
	DgListFill()
	DgShow("Saved '" name "' (" steps.Length " steps). Pick it and click Run.")
	}

;---- Running ----

;The run in file started (times: how many - 0 till stopped; avoid: keep away from mobs on the way; quiet: no message box -
;a run started by the one before it, its gear all swapped (DgGearDone): why it couldn't start into the log). True started
DgRunStart(file, times, avoid, quiet := false)
	{
	global DgRun, Walking ; (v1 globals it sets)
	if (DgRecording || IsObject(DgRun))
		return false
	;(battles only - Settings: battlesonly: no run - it walks the wizard; said on the tab and in the log)
	if (BattlesOnly())
		{
		DebugLog("Dungeons: no run - battles only is on (Settings): the bot moves nothing out of battle")
		DgShow("Battles only is on (Settings): the bot moves nothing out of battle - switch it off to run a dungeon.")
		return false
		}
	d := DgLoad(file)
	if (!IsObject(d))
		return DgRunNot(quiet, "Couldn't read " file " (a run needs at least two steps).")
	if (!WkNavChecked && !WkNavTrusted)
		return DgRunNot(quiet, "The game's memory hasn't been checked against the quest arrow yet - walk a quest for a minute first (" HkText("walk") "), then run the dungeon.")
	nav := NavRead(2000)
	if (!IsObject(nav) || nav.x = "" || nav.zone = "")
		return DgRunNot(quiet, "The bot can't read where your wizard is from the game's memory (" NavWhy ").")
	;(v1: a blank times + 0 - blank: till stopped)
	DgRun := V1Obj({name: d.name, file: file, steps: d.steps, i: 1, runs: 0, want: V1Add(times, 0), avoid: avoid, misses: 0, seen: battles
		, fightUntil: 0, loadUntil: 0, push: "", deck: d.deck, between: 0, resumes: 0, slots: d.slots, stopafter: d.stopafter, next: d.next
		, untilgear: d.untilgear, bosses: d.bosses, gearSaid: 0, gearMarked: 0})
	;(not at the start: on from the nearest spot in this zone)
	k := DgNearest(nav)
	if (!k)
		{
		DgRun := ""
		return DgRunNot(quiet, "The wizard is in " nav.zone " - the run '" d.name "' doesn't go there. Go to where it starts (" d.steps[1].zone ") and run it again.")
		}
	DgRun.i := k, DgRun.lastStep := A_TickCount, DgRun.loadTries := 0
	DgFresh()
	WalkNotifyClose()
	if (!Walking)
		Walking := 1
	ReleaseKeys()
	DebugLog("Dungeons: running '" d.name "' " (DgRun.want ? DgRun.want " times" : "till stopped") " - from step " k " of " d.steps.Length (avoid ? " (keeping away from mobs)" : "")
		. (d.untilgear ? " - until its gear is swapped" (d.next != "" ? ", then '" d.next "'" : "") : ""))
	if (d.untilgear && !(V1IsFunc("GearMode") && GearMode.Call()))
		DebugLog("Dungeons: '" d.name "' - until its gear is swapped needs the gear pass (Settings: gearswap): till it's on, it runs as 'Run it " (DgRun.want ? DgRun.want : 0) " times'")
	if (!DgEndsAtStart(DgRun))
		DebugLog("Dungeons: '" d.name "' doesn't end where it starts - no gear pass or quick sell between its runs")
	DgShow()
	;(its drops are the good gear: the next full backpack held, not quick sold - QuickSell.ahk)
	if (V1IsFunc("QsDungeonMark"))
		QsDungeonMark.Call()
	;(the backpack's items noted - its drops are the new ones at each run's end: Gear.ahk, gearswap on)
	if (V1IsFunc("GearRunMark"))
		GearRunMark.Call(DgRun)
	return true
	}

;A run that couldn't start (DgRunStart): why in a message box - quiet: into the log and on the tab. False
DgRunNot(quiet, why)
	{
	if (quiet)
		{
		DebugLog("Dungeons: no run - " why)
		DgShow(why)
		}
	else
		MsgBox(why, "Dungeons", 262192)
	return false
	}

;The step nearest the wizard in its zone (1 when it's the start's); 0 if no step is in its zone
DgNearest(nav)
	{
	best := 0, bestD := "", inBlock := false
	;(the first visit to this zone only - steps in a row there - so standing at the sigil starts on the way in, not
	;on the way back out)
	for i, s in DgRun.steps
		{
		if (s.zone != nav.zone)
			{
			if (inBlock)
				break
			continue
			}
		inBlock := true
		d := Sqrt((s.x - nav.x) ** 2 + (s.y - nav.y) ** 2)
		if (i = 1 && d < 300)
			return 1
		if (bestD = "" || d < bestD)
			best := i, bestD := d
		}
	return best
	}

;A new step: its progress afresh
DgFresh()
	{
	DgRun.best := "", DgRun.bestLeft := "", DgRun.bestAt := A_TickCount, DgRun.unstuck := 0
	}

;Stops the run (why: for the log and the tab; alert: also to Discord and the tray)
DgStop(why, alert := true)
	{
	global DgRun, Walking ; (v1 globals it sets)
	if (!IsObject(DgRun))
		return
	name := DgRun.name, runs := DgRun.runs
	;(the run's drops in the backpack: the next full one held, not quick sold - QuickSell.ahk)
	if (V1IsFunc("QsDungeonMark"))
		QsDungeonMark.Call()
	DgRun := ""
	ReleaseKeys()
	Walking := 0
	DebugLog("Dungeons: stopped '" name "' after " runs " run" (runs = 1 ? "" : "s") " - " why)
	DgShow("Stopped '" name "' after " runs " run" (runs = 1 ? "" : "s") ": " why)
	if (alert)
		{
		TrayTip("Dungeon run stopped: " why, "Wizard101 bot", 2)
		AlertSend("dungeon", "Dungeon run stopped", "'" name "' stopped after " runs " run" (runs = 1 ? "" : "s") ": " why)
		}
	}

;Where the wizard is and the route to spot p (the helper's /navto - the game's memory, read-only, and its route
;planner): {x, y, z, yaw, zone, ax, ay, left, why} - ax/ay "" with no route - or ""
DgNavTo(p)
	{
	answer := VisionGet("/navto?x=" Round(p.x, 1) "&y=" Round(p.y, 1) "&z=" Round(p.z, 1) (DgRun.avoid ? NavMobArgs() : ""), 2500, true)
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

;The first step after the one walked to that's in zone ("" none)
DgZoneAhead(zone)
	{
	Loop DgRun.steps.Length - DgRun.i
		if (DgRun.steps[DgRun.i + A_Index].zone = zone)
			return DgRun.i + A_Index
	return ""
	}

;On to the next step: into another zone after a walk - a doorway: walk on past the last spot for up to 10 s (push)
;till the loading screen; at the end, a run done
DgNext()
	{
	r := DgRun
	ci := r.i
	cur := r.steps[ci]
	r.i += 1
	DgFresh()
	if (r.i > r.steps.Length)
		{
		r.runs += 1
		DebugLog("Dungeons: '" r.name "' - run " r.runs " done")
		if (r.want && r.runs >= r.want)
			{
			;(the last run's drops logged and the gear plan too - Gear.ahk, gearswap on)
			if (V1IsFunc("GearRunEnd"))
				GearRunEnd.Call(r)
			DgStop("done - " r.runs " run" (r.runs = 1 ? "" : "s"), false)
			TrayTip("Dungeon runs done: " r.runs, "Wizard101 bot", 1)
			return
			}
		;(the next run: a sigil that won't start may be left and come back to once in it too - DungeonStep's r.sigilLeft; back in an
		;earlier zone 3 times again - r.resumes)
		r.i := 1, r.sigilLeft := 0, r.resumes := 0
		;(v1.0.0: back at the start spot outside - a run that ends where it starts: between runs till its first X or another zone -
		;the drops looked at, the gear pass and a full backpack sold there: DgBetweenRuns, at the next step)
		r.between := DgEndsAtStart(r) ? 1 : 0
		}
	nxt := r.steps[r.i]
	;(a walk step right after an X in the same zone, close by, into another zone - the recorder's doorway step after a sigil's X:
	;the wizard drifted while it counted down (recorded so before v1.0.0 - DgRecTickF): no walking on past it - walking off a
	;sigil stops its countdown -, the loading screen waited for as after the X itself, a try again pressing that X again)
	pv := ci > 1 ? r.steps[ci - 1] : ""
	pvD := IsObject(pv) ? DgDist(pv, cur) : ""
	if (nxt.zone != cur.zone && cur.kind = "walk" && IsObject(pv) && pv.kind = "x" && pv.zone = cur.zone && pvD != "" && pvD <= 100)
		{
		DebugLog("Dungeons: step " ci " - a walk " Round(pvD) " from the X before it, into " nxt.zone ": a sigil's countdown - waiting for the load, not walking on")
		r.push := "", r.loadUntil := A_TickCount + 30000, r.fromZone := cur.zone, r.loadStep := ci - 1, r.loadBattles := battles
		}
	else if (nxt.zone != cur.zone && cur.kind != "x")
		{
		;(the way the wizard walked to the last spot - from an earlier spot in that zone some way off, not a battle's
		;or an X's copy of it - 400 further on)
		prev := ""
		k := (r.i = 1 ? r.steps.Length : r.i - 1) - 1
		while (k >= 1 && r.steps[k].zone = cur.zone)
			{
			if (Sqrt((cur.x - r.steps[k].x) ** 2 + (cur.y - r.steps[k].y) ** 2) > 30)
				{
				prev := r.steps[k]
				break
				}
			k--
			}
		dx := IsObject(prev) ? cur.x - prev.x : 0, dy := IsObject(prev) ? cur.y - prev.y : 0, l := Sqrt(dx * dx + dy * dy)
		r.push := l > 1 ? V1Obj({x: cur.x + dx / l * 400, y: cur.y + dy / l * 400, z: cur.z}) : ""
		r.loadUntil := A_TickCount + 10000, r.fromZone := cur.zone, r.loadStep := (r.i = 1 ? r.steps.Length : r.i - 1)
		r.loadBattles := battles
		}
	DgShow()
	}

;Turns h degrees (+ right) walking on: by the game's memory when it can, else by time
DgTurn(h)
	{
	global MsStandGot ; (v1 globals it sets)
	;(by the mouse first - running or standing (MouseSteer.ahk MouseTurnAny); the keys only when it couldn't: 2026-10-24)
	MsStandGot := ""
	if (V1IsFunc("MouseTurnAny") && (WkNavTrusted || WkNavChecked) && !(MsTriedAt && A_TickCount - MsTriedAt < 500) && MouseTurnAny(h) != "")
		return
	;(a turn from standing by the mouse that missed but turned him: the rest by the keys, not h again on top)
	if (MsStandGot != "" && Abs(MsStandGot) >= 3)
		{
		h := ArrowWrap(h - MsStandGot)
		if (Abs(h) < 3)
			return
		}
	if ((WkNavTrusted || WkNavChecked) && NavTurn(h))
		return
	PotionTurnBy(h)
	}

;One step of a dungeon run (the main loop, out of a battle round, instead of the quest walker's)
DungeonStep()
	{
	global WkFrontLook ; (v1 globals it sets)
	r := DgRun
	if (!IsObject(r))
		return
	;(battles only - Settings: battlesonly: no step - the main loop doesn't ask then, and switching it on stops a run; never a step
	;all the same)
	if (BattlesOnlyNo("dungeon run's step"))
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		return
		}
	;(paused since the last step - a battle, F8, you playing, F6, the game not in front: the clocks wait too)
	gap := A_TickCount - r.lastStep
	if (r.lastStep && gap > 1000)
		{
		r.bestAt += gap
		if (r.loadUntil)
			r.loadUntil += gap
		if (r.fightUntil)
			r.fightUntil += gap
		}
	r.lastStep := A_TickCount
	;(a battle, walking off, the game not in front, the spellbook not up - a battle starting, a dialogue - or a
	;loading screen just over: not steering)
	;(the game's log read for a loading screen - the quest walker's look, which doesn't run meanwhile)
	WalkZone(true)
	loaded := WkLoading || (WkLoadedAt && A_TickCount - WkLoadedAt < 1500)
	if (!Walking || !GameActive() || inbattle = 1 || !BotNoBattle() || loaded)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(a dialogue or a quest offer up: through it)
		if (!loaded && Walking && GameActive() && inbattle != 1)
			DgDialogs()
		;(Wizard101 behind another window, you away 5 minutes - or Play for me: brought to the front, as the walker does)
		;(v1: WkFrontLook never set - blank - compared as text: not > 1500)
		if (Walking && !GameActive() && inbattle != 1 && V1IsFunc("GameToFront") && UserIdle() > 300000 && V1Gt(V1Ago(WkFrontLook), 1500))
			WkFrontLook := A_TickCount, GameToFront.Call("a dungeon run", true, true)
		r.bestAt := A_TickCount
		Sleep(150)
		return
		}
	;(a battle was fought since the last look: not stuck, and the wizard stands where its circle was)
	if (battles != r.seen)
		r.seen := battles, r.bestAt := A_TickCount
	st := r.steps[r.i]
	;Waiting at a battle spot: one comes, or 8 s
	if (r.fightUntil)
		{
		if (battles > r.fightBattles || A_TickCount > r.fightUntil)
			{
			r.fightUntil := 0
			DgNext()
			}
		else
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			Sleep(200)
			}
		return
		}
	;(v1.0.0: a run just done, back at its start spot outside: its drops looked at, the gear pass and a full backpack sold -
	;once a run, DgBetweenRuns)
	if (r.between = 1)
		{
		DgBetweenRuns()
		return
		}
	nav := DgNavTo(IsObject(r.push) ? r.push : st)
	if (!IsObject(nav))
		{
		r.misses += 1
		if (r.misses >= 20)
			DgStop("the game's memory can't be read (" VisionErr ")")
		else
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			Sleep(300)
			}
		return
		}
	r.misses := 0
	;(between runs till the run leaves its start zone - QuickSell.ahk's QsDungeonNow sells nothing from then on)
	if (r.between && nav.zone != r.steps[1].zone)
		r.between := 0
	if (nav.zone != st.zone)
		{
		;(a battle while waiting for the load: the countdown or the walk through was cut short - tried again)
		if (r.loadUntil && battles != r.loadBattles)
			r.loadUntil := 1
		;(walking through the doorway, or the sigil's loading screen - still in the zone it's leaving: a while)
		waiting := A_TickCount < r.loadUntil && nav.zone = r.fromZone
		if (waiting)
			{
			if (IsObject(r.push))
				DgSteer(nav, r.push, 999)
			else
				{
				if (KeysDown || HeldW)
					ReleaseKeys()
				DgDialogs()
				}
			Sleep(100)
			return
			}
		;(the load didn't come - still where it was: the step that should have taken the wizard on, again - twice,
		;then it stops; never on to the way back, which would count a run that didn't happen)
		if (r.loadUntil && nav.zone = r.fromZone && r.loadStep)
			{
			r.loadTries += 1
			;(its X twice for nothing at a sigil - 2026-10-26 21:44: one never started after a relog: left and come back to before the
			;last try, once a run (DgNext clears r.sigilLeft at each new one) - a Mark here, Home, the Recall back: the walker's
			;WalkSigilReset, which says why not - Settings: sigilhome, off unless you switch it on; only with the mana globe read, the
			;Mark seen taken. No Commons way, a run can't walk back from there. Back: the X step again as below.
			;TODO (needs the game): an inner X step - a door inside the dungeon: Home leaves the instance; whether a Mark takes in one,
			;and the Recall comes back into the same instance, isn't known yet - a Mark that doesn't take stops it before Home)
			if (r.loadTries = 2 && !r.sigilLeft && V1At(V1At(r.steps, r.loadStep), "kind") = "x")
				{
				r.sigilLeft := 1
				if (WalkSigilReset("step " r.loadStep "'s X didn't load twice ('" r.name "')", r.fromZone, false))
					DebugLog("Dungeons: back at step " r.loadStep " after Home and the Recall")
				}
			if (r.loadTries > 2)
				{
				;(counted badly stuck - the dashboard's STATISTICS, vision\stuckreport.py)
				WalkBadlyStuckCount("dungeon", "the way from " r.fromZone " into " st.zone " didn't load (3 tries) - '" r.name "'")
				DgStop("the way from " r.fromZone " into " st.zone " didn't load (3 tries)")
				return
				}
			DebugLog("Dungeons: no loading screen into " st.zone " - step " r.loadStep " again (try " r.loadTries + 1 ")")
			r.i := r.loadStep, r.push := "", r.loadUntil := 0
			DgFresh()
			DgShow()
			return
			}
		;(v1.0.0: an earlier zone of the run - its first visit is before this step: a defeat's respawn, a potion run's Recall back
		;(the main loop's PotionCheck has had its look before this step): on from the nearest step of that first visit (DgNearest -
		;its start when that's within 300), 3 times a run at most - a fourth: stopped (defeated again and again?). Looked at BEFORE
		;a zone further on: the recorder's "walk back out to where you started" brings the start zone, and often the inner ones,
		;again on the way back - DgZoneAhead would find that later step and walk out, counting a run whose boss wasn't beaten (as
		;the retry above, never on to the way back). Before v1.0.0 DgZoneAhead alone: the run stopped (or jumped to the way out).
		;(vision\dglint.py zone_choice is this rule in Python, tested - keep the two the same)
		k := DgNearest(nav)
		if (k && k < r.i)
			{
			if (V1N(r.resumes) >= 3)
				{
				DgStop("the wizard is in " nav.zone ", but the run's next step is in " st.zone " - back in an earlier zone of the run 3 times this run (defeated again and again?)")
				return
				}
			r.resumes := V1N(r.resumes) + 1
			DebugLog("Dungeons: in " nav.zone " - an earlier zone of the run (a defeat or a potion run?): on from step " k " (" r.resumes " of 3 this run)")
			r.i := k, r.push := "", r.loadUntil := 0, r.loadTries := 0, r.fightUntil := 0
			DgFresh()
			DgShow()
			return
			}
		;(loaded into a zone further on - one the run hasn't been in yet: on from its first step)
		k := DgZoneAhead(nav.zone)
		if (k && nav.zone != r.fromZone)
			{
			DebugLog("Dungeons: in " nav.zone " - on from step " k)
			r.i := k, r.push := "", r.loadUntil := 0, r.loadTries := 0
			DgFresh()
			DgShow()
			return
			}
		DgStop("the wizard is in " nav.zone ", but the run's next step is in " st.zone " (a potion run, a defeat, or a door that didn't load?)")
		return
		}
	if (r.loadUntil)
		r.loadTries := 0
	r.push := "", r.loadUntil := 0, r.fromZone := ""
	d := Sqrt((nav.x - st.x) ** 2 + (nav.y - st.y) ** 2)
	if (d <= (st.kind = "x" ? 100 : 160))
		{
		DgArrive(st)
		return
		}
	;(getting on: closer as the crow flies, or along the route round walls)
	if (r.best = "" || d < r.best - 40)
		r.best := d, r.bestAt := A_TickCount, r.unstuck := 0
	if (nav.left != "" && (r.bestLeft = "" || nav.left < r.bestLeft - 40 || nav.left > r.bestLeft + 300))
		r.bestLeft := nav.left, r.bestAt := A_TickCount, r.unstuck := 0
	;(not getting closer for 2 s: a dialogue or a quest offer holding the wizard? - looked for every 1.5 s)
	if (A_TickCount - r.bestAt > 2000 && DgDialogs())
		{
		r.bestAt := A_TickCount
		return
		}
	if (A_TickCount - r.bestAt > 7000)
		{
		r.unstuck += 1
		if (r.unstuck > 4)
			{
			;(counted badly stuck - the dashboard's STATISTICS, vision\stuckreport.py)
			WalkBadlyStuckCount("dungeon", "stuck " Round(d) " from step " r.i " (" st.zone ") - '" r.name "'")
			DgStop("stuck " Round(d) " from step " r.i " (" st.zone ") - no closer after backing up 4 times")
			return
			}
		DebugLog("Dungeons: no closer to step " r.i " in 7 s (" Round(d) " away) - backing up and turning")
		HoldW(0)
		BackUp(700)
		DgTurn(Mod(r.unstuck, 2) ? 90 : -90)
		HoldW(1)
		Sleep(900)
		r.bestAt := A_TickCount
		return
		}
	DgSteer(nav, st, d)
	}

;A dialogue up (Spaced through) or a quest offer's ACCEPT (clicked) - at most every 1.5 s. True if there was one
DgDialogs()
	{
	static lookAt := 0
	if (A_TickCount < lookAt)
		return false
	lookAt := A_TickCount + 1500
	if (WalkDialogOpen())
		{
		WalkSkipDialog()
		return true
		}
	return WalkAcceptQuest("a dungeon run")
	}

;Steers at spot p (the route's aim when there's one): a big turn close to it on the spot, else walking on
DgSteer(nav, p, d)
	{
	h := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.ax != "" ? nav.ax : p.x, nav.ay != "" ? nav.ay : p.y)
	h := (h = "") ? 0 : h
	;(close by and well off to one side: by the mouse while he's still running - its turn is tight, no circling round
	;it (2026-10-24: you asked); standing - the mouse turns only the camera then - or the mouse can't: on the spot, A/D)
	if (Abs(h) > 60 && d < 250)
		{
		if (HeldW && Abs(h) <= 150 && (WkNavTrusted || WkNavChecked) && MouseSteerWhyNot(true, false, true) = "" && MouseTurn(h, false) != "")
			{
			Sleep(60)
			return
			}
		;(standing, or the running turn missed: turned from standing - DgTurn: the mouse first, then the keys; closer than
		;150 the mouse's step from standing would overshoot it (a quest item: round and round) - on the spot)
		HoldW(0)
		if (d < 150)
			{
			if (!((WkNavTrusted || WkNavChecked) && NavTurn(h)))
				PotionTurnBy(h)
			}
		else
			DgTurn(h)
		}
	else
		{
		HoldW(1)
		;(by the mouse while he runs - steadier than A/D (2026-10-24); A/D only when the mouse can't: a turn of more than
		;150, the mouse off or failing, a window. Just set off - the mouse doesn't turn him yet - a small turn waits a step)
		if (Abs(h) > 12)
			{
			why := MouseSteerWhyNot(true, false)
			if (why = "just set off" && Abs(h) <= 45)
				h := 0
			else if (Abs(h) > 150 || !(WkNavTrusted || WkNavChecked) || MouseTurn(h, false) = "")
				DgTurn(h)
			}
		}
	Sleep(60)
	}

;At step st: a walk - on; X - pressed (then a loading screen, or a dialogue Spaced through and a quest accepted);
;a battle spot - waiting for one
DgArrive(st)
	{
	r := DgRun
	if (st.kind = "x")
		{
		;(the sigil: in the dungeon from here on - no more selling between runs)
		r.between := 0
		ReleaseKeys()
		Sleep(150)
		PressKey("x")
		DebugLog("Dungeons: X at step " r.i " (" st.zone ")")
		nxt := r.steps[r.i < r.steps.Length ? r.i + 1 : 1]
		if (nxt.zone != st.zone)
			{
			k := r.i
			DgNext()
			r.push := "", r.loadUntil := A_TickCount + 30000, r.fromZone := st.zone, r.loadStep := k, r.loadBattles := battles
			return
			}
		Sleep(1200)
		if (WalkDialogOpen())
			WalkSkipDialog()
		WalkAcceptQuest("a dungeon run")
		DgNext()
		return
		}
	if (st.kind = "fight")
		{
		ReleaseKeys()
		r.fightUntil := A_TickCount + 8000, r.fightBattles := battles
		return
		}
	DgNext()
	}

;---- Between runs (v1.0.0) ----

;A run done, back at its start spot outside (DungeonStep, once a run: DgRun.between 1): its drops looked at and the gear pass
;(Gear.ahk GearRunEnd - gearswap on: logged, nothing equipped), a full backpack quick sold here (QuickSell.ahk QsLook -
;quicksell on: QsDungeonNow lets it while between; the dungeon's hold still holds it - with the gear pass on, only its
;Deck and Pet groups: the gear groups sold - unless "...even with a dungeon's drops in it" is ticked), then "Until its gear is swapped": its gear all swapped - on to its
;next run, or stopped (DgGearDone). gearswap off: the quick sell's look only - as a battle's end looks
DgBetweenRuns()
	{
	r := DgRun
	r.between := 2
	if (KeysDown || HeldW)
		ReleaseKeys()
	dbrG := V1IsFunc("GearRunEnd") ? GearRunEnd.Call(r) : ""
	if (V1IsFunc("QsMode") && QsMode.Call() && V1IsFunc("QsLook"))
		QsLook.Call("between dungeon runs - back outside '" r.name "'")
	;(the run stopped meanwhile - F6, battles only, you: nothing more)
	if (!IsObject(DgRun) || DgRun != r)
		return
	;(the time the pass took isn't the step's: not stuck for it)
	r.lastStep := A_TickCount, r.bestAt := A_TickCount
	if (!r.untilgear)
		return
	if (!IsObject(dbrG) || !IsObject(dbrG.run))
		{
		if (!r.gearSaid)
			r.gearSaid := 1, DebugLog("Dungeons: '" r.name "' - until its gear is swapped: " (V1IsFunc("GearMode") && GearMode.Call() ? "the gear couldn't be read (" NavGearWhy ") - it runs on" : "the gear pass is off (Settings: gearswap) - it runs on as 'Run it " (r.want ? r.want : 0) " times'"))
		return
		}
	if (dbrG.run.done)
		DgGearDone(r, dbrG.run.why)
	}

;"Until its gear is swapped" done (DgBetweenRuns): its next run (next| - the tab's "then") started when it starts in the zone
;the wizard's in (its own "until" and "then" with it, as many times as this one was asked for); else stopped - its next
;run named in the why (Discord: where to take the wizard)
DgGearDone(r, why)
	{
	dgdFile := r.next != "" ? DgFindRun(r.next) : ""
	dgdN := dgdFile != "" ? DgLoad(dgdFile) : ""
	if (r.next = "")
		{
		DgStop("its gear is all swapped (" why ")")
		return
		}
	if (!IsObject(dgdN))
		{
		DgStop("its gear is all swapped (" why ") - its next run, '" r.next "', isn't in the dungeons folder")
		return
		}
	dgdNav := NavRead(2000)
	if (!(IsObject(dgdNav) && dgdNav.zone != "" && dgdNav.zone = dgdN.steps[1].zone))
		{
		DgStop("its gear is all swapped (" why ") - take the wizard to '" dgdN.name "' (it starts in " dgdN.steps[1].zone ") and run it")
		return
		}
	dgdTimes := r.want, dgdAvoid := r.avoid, dgdName := r.name
	DgStop("its gear is all swapped (" why ") - on to '" dgdN.name "'", false)
	if (!DgRunStart(dgdFile, dgdTimes, dgdAvoid, true))
		AlertSend("dungeon", "Dungeon run stopped", "'" dgdName "' - its gear is all swapped (" why "); its next run, '" dgdN.name "', didn't start (the Dungeons tab, debug.log `"Dungeons: ...`").")
	}

;---- The tab's buttons (labels run in the global scope: Dg-named variables only) ----

DgRecordClick:
DgRecordClick()
	return

DgRecStopClick:
DgRecF9:
DgRecF9()
	return

DgRecXKey:
DgRecXKey()
	return

DgRecTick:
DgRecTick()
	return

DgRunClick:
DgRunClick()
	return

DgStopClick:
DgStopClick()
	return

DgDeleteClick:
DgDeleteClick()
	return

DgFolderClick:
DgFolderClick()
	return

DgListEvent:
DgListEvent()
	return

;The Deck box picked: the run's file gets its deck| line (Decks.ahk picks that deck while the run's walked)
DgDeckPick:
DgDeckPick()
	return

;(v1.0.0) The "Until its gear is swapped" box or the "then" list changed: the run's file gets its untilgear| and next| lines
DgGearPick:
DgGearPick()
	return

;The Deck box filled with your decks (by place: two may share a name, one's name may start another's), the picked run's
;own chosen - again after a deck's saved, made or deleted on the Cards tab (DeckLoadAll)
DgDeckShow()
	{
	global DgDeckIds ; (v1 globals it sets)
	if (!DashHwnd)
		return
	if (!IsObject(DeckList) && V1IsFunc("DeckLoadAll"))
		DeckLoadAll.Call()
	;(v1 put the default ListView back after DgSelected - v2 has no default ListView)
	file := DgSelected()
	d := file != "" ? DgLoad(file) : ""
	items := "|(none)", want := 1, DgDeckIds := []
	for i, k in IsObject(DeckList) ? DeckList : []
		{
		items .= "|" k.name
		DgDeckIds.Push(k.id)
		if (IsObject(d) && d.deck = k.id)
			want := i + 1
		}
	;(v1: GuiControl, Dash:, DgDeck, |... - the list replaced)
	Dash["DgDeck"].Delete()
	Dash["DgDeck"].Add(StrSplit(SubStr(items, 2), "|"))
	Dash["DgDeck"].Choose(want)
	}

;The picked run's deck written into its file (deck|<id>; none: the line taken out) - its steps kept as they are
DgDeckSet()
	{
	global DeckDirty ; (v1 globals it sets)
	file := DgSelected()
	if (file = "" || !FileExist(file))
		return
	;(AltSubmit: the place picked)
	pos := Dash["DgDeck"].Value
	id := (IsObject(DgDeckIds) && pos >= 2 && pos - 1 <= DgDeckIds.Length) ? DgDeckIds[pos - 1] : ""
	pick := ""
	for i, k in IsObject(DeckList) ? DeckList : []
		if (k.id = id)
			pick := k.name
	if (!DgSetLine(file, "deck", id))
		return
	;(the run being walked: its deck from now on, not from its next start)
	if (IsObject(DgRun) && DgRun.file = file)
		DgRun.deck := id, DeckDirty := 1
	DebugLog("Dungeons: " file " - its deck " (id != "" ? pick : "none (the usual pick)"))
	}

;A run file's key| line set to value (deck|, untilgear|, next| - "": the line taken out), right after its name| line (else
;first) - its steps and other lines kept as they are. Written as it was read (the ANSI code page, as FileAppend recorded it)
;and its date kept (the list's Recorded). False when it couldn't be written (DgDeckSet's way, v1.0.0 for every such line)
DgSetLine(file, key, value)
	{
	;(v1: a file that can't be read - blank, ErrorLevel 1; v2 throws)
	made := V1Try(FileGetTime, file, "M")
	text := V1FileRead(file)
	;(v1's newline was `r`n only: in a file with bare `n lines its ^ didn't start a line there - (*CRLF) gives v1's)
	text := RegExReplace(text, "m)(*CRLF)^" key "\|[^\r\n]*\R?", "")
	;(a $ in the value - a run's name may have one - is a $ in the replacement, not a group)
	if (value != "")
		text := RegExMatch(text, "m)(*CRLF)^name\|") ? RegExReplace(text, "m)(*CRLF)^(name\|[^\r\n]*\R?)", "$1" key "|" StrReplace(value, "$", "$$") "`r`n", , 1)
			: key "|" value "`r`n" text
	;(v1's FileOpen gave no object when it couldn't open the file; v2 throws)
	f := V1Try(FileOpen, file ".tmp", "w", "CP0")
	if (!IsObject(f))
		return false
	f.Write(text)
	f.Close()
	V1Do(FileMove, file ".tmp", file, 1)
	if (made != "")
		V1Do(FileSetTime, made, file, "M")
	return true
	}

;The tab's "Until its gear is swapped" box and "then" list from the picked run's file (untilgear|, next|) - the list: (stop)
;and every other run by name
DgGearShow()
	{
	global DgNextNames ; (v1 globals it sets)
	if (!DashHwnd)
		return
	dgsFile := DgSelected()
	dgsD := dgsFile != "" ? DgLoad(dgsFile) : ""
	dgsItems := ["(stop)"], dgsWant := 1, DgNextNames := []
	Loop Files, DgDir() "\*.txt"
		{
		if (A_LoopFilePath = dgsFile)
			continue
		dgsO := DgLoad(A_LoopFilePath)
		if (!IsObject(dgsO))
			continue
		DgNextNames.Push(dgsO.name), dgsItems.Push(dgsO.name)
		if (IsObject(dgsD) && dgsD.next != "" && dgsO.name = dgsD.next)
			dgsWant := dgsItems.Length
		}
	Dash["DgUntilGear"].Value := IsObject(dgsD) && dgsD.untilgear ? 1 : 0
	Dash["DgNextRun"].Delete()
	Dash["DgNextRun"].Add(dgsItems)
	Dash["DgNextRun"].Choose(dgsWant)
	}

;The picked run's "Until its gear is swapped" and "then" written into its file (untilgear|1, next|<name> - off / (stop): the
;line taken out - DgSetLine); the run being walked: from now on
DgGearSet()
	{
	dgtFile := DgSelected()
	if (dgtFile = "" || !FileExist(dgtFile))
		return
	dgtU := Dash["DgUntilGear"].Value ? 1 : 0
	dgtPos := Dash["DgNextRun"].Value
	dgtN := (IsObject(DgNextNames) && dgtPos >= 2 && dgtPos - 1 <= DgNextNames.Length) ? DgNextNames[dgtPos - 1] : ""
	if (!DgSetLine(dgtFile, "untilgear", dgtU ? 1 : "") || !DgSetLine(dgtFile, "next", dgtN))
		return
	if (IsObject(DgRun) && DgRun.file = dgtFile)
		DgRun.untilgear := dgtU, DgRun.next := dgtN
	DebugLog("Dungeons: " dgtFile " - until its gear is swapped " (dgtU ? "on" : "off") (dgtN != "" ? ", then '" dgtN "'" : ""))
	if (dgtU && !(V1IsFunc("GearMode") && GearMode.Call()))
		DgShow("Until its gear is swapped needs the gear pass: Settings > THE BACKPACK, gearswap (a rehearsal: it logs the plan, equips nothing). Till then the run goes 'Run it N times'.")
	}

;###############  (v2 port: v1's labels, as functions)  ###############
;(the Dungeons tab's buttons - g-labels in v1: Dashboard.ahk's OnEvent("Click", Fn.Bind("Normal")); A_GuiEvent, A_GuiControl,
;Info as v1 had them)
DgRecordClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	DgRecordStart()
	return
}
;##############################################
;(v1: the label DgRecStopClick: ran on into DgRecF9: - the Stop recording button)
DgRecStopClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	DgRecordStop()
	return
}
;##############################################
DgRecF9(ThisHotkey:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	DgRecordStop()
	return
}
;##############################################
DgRecXKey(ThisHotkey:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	DgRecX()
	return
}
;##############################################
DgRecTick() { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	DgRecTickF()
	return
}
;##############################################
DgRunClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	;(v1: Gui, Dash:Submit, NoHide - DgTimes, DgAvoid... set)
	V1GuiSubmit(Dash, false)
	DgRunFile := DgSelected()
	if (DgRunFile = "")
		MsgBox("Pick a run in the list first (or record one).", "Dungeons", 262208)
	else
		DgRunStart(DgRunFile, DgTimes, DgAvoid)
	return
}
;##############################################
DgStopClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	DgStop("you stopped it", false)
	return
}
;##############################################
DgDeleteClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	DgRunFile := DgSelected()
	if (DgRunFile = "")
		return
	if (IsObject(DgRun) && DgRun.file = DgRunFile)
		{
		msgResult := MsgBox("That run is being walked - stop it first.", "Dungeons", 262192)
		return
		}
	SplitPath(DgRunFile, &DgRunName)
	msgResult := MsgBox("Delete the run '" DgRunName "'? (It goes to the Recycle Bin.)", "Dungeons", 262436)
	if (msgResult = "Yes")
		{
		;(v1: ErrorLevel 1 when it couldn't - v2 throws)
		V1Do(FileRecycle, DgRunFile)
		DebugLog("Dungeons: deleted " DgRunFile)
		DgListFill()
		}
	return
}
;##############################################
DgFolderClick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	V1Do(DirCreate, DgDir())
	Run(DgDir())
	return
}
;##############################################
;(the list's events - Dashboard.ahk: OnEvent("DoubleClick", DgListEvent.Bind("DoubleClick")) and OnEvent("ItemSelect",
;DgListEvent.Bind("I")); v1's AltSubmit "I" event with ErrorLevel holding S or s - InStr isn't case-sensitive: a row
;selected or unselected - is v2's ItemSelect)
DgListEvent(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (A_GuiEvent = "DoubleClick" && !DgRecording && !IsObject(DgRun))
		DgRunClick() ; (v1: Gosub DgRunClick - the same thread)
	;(a run picked: its deck in the Deck box; its "Until its gear is swapped" and "then")
	else if (A_GuiEvent = "I" || A_GuiEvent = "ItemSelect")
		DgDeckShow(), DgGearShow()
	return
}
;##############################################
;(the Deck box - v1's gDgDeckPick: Dashboard.ahk's OnEvent("Change", DgDeckPick.Bind("Normal")))
DgDeckPick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) { ; (v1: a label - its code ran in the global scope)
	global
	DgDeckSet()
	return
}
;##############################################
;(v1.0.0, written for v2: the "Until its gear is swapped" box and the "then" list - Dashboard.ahk's OnEvent("Click") /
;OnEvent("Change"), DgGearPick.Bind("Normal"))
DgGearPick(A_GuiEvent := "", A_GuiControl := "", Info := "", *) {
	global
	DgGearSet()
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
DungeonsBlank()
	{
	global DgRun := "", DgRecording := "", DgRecSteps := "", DgRecLast := "", DgRecZone := "", DgRecBattleAt := "", DgRecPrev := "", DgRecOut := ""
	global DashTabs := "", DgList := "", DgHelp := "", DgRecBtn := "", DgRecStopBtn := "", DgRunBtn := "", DgStopBtn := "", DgDelBtn := ""
	global DgFolderBtn := "", DgTimes := "", DgTimesUD := "", DgAvoid := "", DgStatus := "", DgTimesLabel := "", DgTimesNote := "", DgDeck := ""
	global DgDeckT := "", DgRecKey := "", DgDeckIds := ""
	global DgUntilGear := "", DgNextT := "", DgNextRun := "", DgNextNames := ""
	}
