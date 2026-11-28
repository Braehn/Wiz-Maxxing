; Puzzle.ahk - the way to the quest's goal blocked for good at one spot (a gate, a door that won't open - 2026-10-26 Storm
; Lord's Temple: its gate opens only once the two guards standing off to the sides are beaten): before telling you, the bot
; tries what usually opens one, looking after each try whether the way's open - the enemies standing off to the sides
; fought, things with a prompt nearby X'd, the zone's NPCs talked to. What you do to get past after a notice is recorded
; and saved in learned\puzzles.txt once the way opens or the goal moves on; the bot does it itself first the next time
; (any character, any PC with the file). A journal of what happened in the game lately (the game's own log, your X key)
; feeds both.
; AutoHotkey v2, written for v2 (v1 never had this: nothing here is ported); #Included by Autofarmer.ahk only - AutoQuester
; has none of it, so every call from the shared files (Walker.ahk, Vision.ahk, EnemySpells.ahk, Dungeons.ahk) asks
; V1IsFunc first.
;
; Reads only: the game's memory through the vision helper (/nav, /mobs, /items, /blockers - READ-ONLY: nothing in the game
; is ever written, injected or hooked; a door's state from its ObjectStateBehavior - vision\statemem.py, not confirmed in the
; game yet: acted on only with puzzlestate on, else said in the log), the zone's own files (/zonepuzzle - its kills, hints and
; the use events of its triggers with the things that may fire them, a lever the game names nowhere -, /navpass - files
; only) and the game's log
; (WizardClient.log, as EnemySpells.ahk reads it). Your X key is watched by a pass-through hotkey (the key still goes to
; the game; nothing else you type is looked at). No web page is ever fetched. Nothing with Crowns on it is ever X'd or
; clicked: a prompt is read right before each X, and one naming Crowns is never X'd.
;
; Settings (PlayerStats.txt, the Settings window's WALKING): puzzles (the tries - on unless 0), puzzlelearn (the recording
; and the replay - on unless 0), puzzlestate (a door's state in the game's memory acted on - off unless 1), puzzlelevers
; (the levers the game names nowhere tried - off unless 1: else only named in the plan's log line). Files, all A_ScriptDir's:
; learned\puzzles.txt (the ways learned - kept by updates, yours to edit), resources\puzzles_known.txt (the seed that ships
; with the bot - replaced by updates; a learned entry for the same spot or goal wins), learned\puzzle_recording.txt (a
; recording under way - a restart carries on with it), generated\puzzle_journal.txt (the journal and a duel under way - a
; restart keeps them), generated\puzzle_hold.txt (the wait at a blocked way and the hour's tries - a restart keeps them).

;(v2-only globals - the port tools don't know them: declared here with no value - a top-level := in an #Included file never
;runs - and every one set in PuzzleInit; each public function asks PuzzleReady first, so nothing throws before StartBot)
;Set up (1); the run under way ("" none); the walker's evidence of a block ([{at, zone, x, y, z, yaw, r, kind, goalid, goal, line,
;tx, ty, tz}] - the last 6 minutes); not used (the least distance is worked out from the walker's own reading - PzEvTick); the
;runs so far ([{at, zone, x, y, tried}] - the caps); the hold at a blocked way ("" none); the recording ("" none); the journal
;(the last 40 entries, 30 minutes); the duel going on by the game's log ("" none); fled flag (not used: the duel's own); a prompt
;in reach by the game's log ({open, openAt, closeAt, want, prompt}); X presses not looked at yet ([ticks])
global PzReady, PzRun, PzEv, PzMinR, PzHist, PzHeld, PzRec, PzJ, PzDuelNow, PzFled, PzInter, PzXPend
;The ways learned (the file's and the seed's entries, in use); the four files; the blockers last read (when, which zone); the zones'
;hints ({zone: {ok, at, kills, spawns, hints, uses}}); the zone the game's log last connected to, when; what was said once
global PzLearned, PzFile, PzSeedFile, PzRecFile, PzJFile, PzDoors, PzDoorsAt, PzDoorsZone, PzHints, PzZoneNow, PzZoneAt, PzSaid
;The learned file as read, in blocks (text and puzzles - written back as they were); work for the main thread asked by a timer, a
;hotkey or a button ({forget, holdEnd, keep, reprobe}); the spot's hour count cleared once (Keep trying); the X hotkey made;
;dialogue ends seen ([ticks]); X presses looked at ([ticks] - typing in chat); what each mob template was seen as ({template:
;{name, boss, quest}})
global PzBlocks, PzMain, PzKeepFree, PzXHook, PzDlgEnds, PzXRecent, PzTpl
;The learned file's text as last read or written (an edit of yours since then: the file read again before the bot changes it); the
;hold and the hour's runs kept for a restart (generated\puzzle_hold.txt)
global PzFileText, PzHoldFile
;The numbers (section 1-3 of the design): a stop this far off the goal or more counts; a cluster's reach; a door / gate this near;
;past the stop by this much; side guards within; things within; camps, things, NPCs, levers (of those things) at most; battles a
;run; a run's time (ms, not battles, not you); runs an hour at a spot / in a zone; a spot's reach; a recording's time at most; out
;of the zone at most; held this long before a look again
global PzMinRDist, PzClusterR, PzDoorR, PzPastBy, PzGuardR, PzObjR, PzCampMax, PzObjMax, PzNpcMax, PzUseMax, PzMaxFights, PzTimeCap
global PzRunsHour, PzRunsZoneHour, PzSpotR, PzRecCap, PzAwayCap, PzReprobe

;Everything set, the files read, a recording under way carried on, the X hotkey made (a pass-through: the key still goes to
;the game), and - timers - the half-second tick. Called by StartBot (and again by a test: everything starts afresh)
PuzzleInit(timers := true)
	{
	global PzReady, PzRun, PzEv, PzMinR, PzHist, PzHeld, PzRec, PzJ, PzDuelNow, PzFled, PzInter, PzXPend
	global PzLearned, PzFile, PzSeedFile, PzRecFile, PzJFile, PzDoors, PzDoorsAt, PzDoorsZone, PzHints, PzZoneNow, PzZoneAt, PzSaid
	global PzBlocks, PzMain, PzKeepFree, PzXHook, PzDlgEnds, PzXRecent, PzTpl, PzFileText, PzHoldFile
	global PzMinRDist, PzClusterR, PzDoorR, PzPastBy, PzGuardR, PzObjR, PzCampMax, PzObjMax, PzNpcMax, PzUseMax, PzMaxFights, PzTimeCap
	global PzRunsHour, PzRunsZoneHour, PzSpotR, PzRecCap, PzAwayCap, PzReprobe
	PzMinRDist := 400, PzClusterR := 400, PzDoorR := 500, PzPastBy := 150, PzGuardR := 4000, PzObjR := 3000
	PzCampMax := 4, PzObjMax := 6, PzNpcMax := 4, PzUseMax := 2, PzMaxFights := 6, PzTimeCap := 720000
	PzRunsHour := 2, PzRunsZoneHour := 4, PzSpotR := 600, PzRecCap := 2700000, PzAwayCap := 600000, PzReprobe := 300000
	PzRun := "", PzEv := [], PzMinR := "", PzHist := [], PzHeld := "", PzRec := "", PzJ := [], PzDuelNow := "", PzFled := 0
	PzInter := V1Obj({open: 0, openAt: 0, closeAt: 0, want: 0, prompt: ""}), PzXPend := [], PzXRecent := []
	PzFile := A_ScriptDir "\learned\puzzles.txt", PzSeedFile := A_ScriptDir "\resources\puzzles_known.txt"
	PzRecFile := A_ScriptDir "\learned\puzzle_recording.txt", PzJFile := A_ScriptDir "\generated\puzzle_journal.txt"
	PzHoldFile := A_ScriptDir "\generated\puzzle_hold.txt"
	PzDoors := "", PzDoorsAt := 0, PzDoorsZone := "", PzHints := V1Obj(), PzZoneNow := "", PzZoneAt := 0, PzSaid := V1Obj()
	PzBlocks := [], PzLearned := [], PzMain := V1Obj({forget: "", holdEnd: "", keep: 0, reprobe: 0}), PzKeepFree := 0, PzXHook := 0
	PzDlgEnds := [], PzTpl := V1Obj(), PzFileText := ""
	PzReady := 1
	PuzzleLoad()
	PzJLoad()
	PzRecResume()
	PzHoldLoad()
	;(one hotkey for the whole bot - the dungeon recorder's X goes through it too: two of the same variant would replace each other)
	HotIf()
	try
		{
		Hotkey("~*x", PzXKey, "On")
		PzXHook := 1
		}
	catch as e
		PzLog("the X key can't be watched (" e.Message ") - nothing you X is recorded")
	if (timers)
		SetTimer(PzTick, 500)
	}

PuzzleReady() => IsSet(PzReady) && PzReady
PuzzleOn() => PuzzleReady() && Stat("puzzles") != 0
PuzzleLearnOn() => PuzzleReady() && Stat("puzzlelearn") != 0
PuzzleHeld() => PuzzleReady() && IsObject(PzHeld)
PuzzleXHook() => PuzzleReady() && PzXHook

;A puzzle run under way: the main loop's step is PuzzleStep instead of WalkStep. main: the main loop asking - the work timers,
;hotkeys and buttons left for it done first (a hold ending, Keep trying, a look again, F8)
PuzzleRunning(main := false)
	{
	if (!PuzzleReady())
		return false
	if (main)
		try
			PzMainWork()
		catch as e
			PzFail("the main thread's work", e)
	return IsObject(PzRun)
	}

;Is name (a mob's) in the camp the run is fighting now? (Vision.ahk MobGrow: the mobs' reach isn't raised for the way's guards)
PuzzleFighting(name)
	{
	if (!PuzzleReady() || !IsObject(PzRun) || !IsObject(PzRun.cur) || PzRun.cur.kind != "camp" || !IsObject(PzRun.cur.names))
		return false
	pfKey := WalkLetters(name)
	for i, pfN in PzRun.cur.names
		if (pfKey != "" && WalkLetters(pfN) = pfKey)
			return true
	return false
	}

;---- small helpers ----

PzLog(t) => DebugLog("Puzzle: " t)
;A line said at most once (ms: once in that long; 0: once a run of the bot). True if said now
PzSay(key, t, ms := 0)
	{
	global PzSaid
	if (PzSaid.Has(key) && (!ms || A_TickCount - PzSaid[key] < ms))
		return false
	PzSaid[key] := A_TickCount
	PzLog(t)
	return true
	}
;An error the code didn't expect (where: which entry): logged - never a box (the bot's own error box stops its main loop) - and
;the run under way dropped, the walker on as before
PzFail(where, e)
	{
	global PzRun
	PzSay("err|" where "|" e.Line, "an error in " where " (" e.Message " - " e.What " line " e.Line ") - " (IsObject(PzRun) ? "the tries given up, " : "")
		. "the walker on as before", 60000)
	if (IsObject(PzRun))
		{
		PzRun := ""
		try ReleaseKeys()
		}
	}
PzD(ax, ay, bx, by) => Sqrt((ax - bx) ** 2 + (ay - by) ** 2)
PzXY(o) => IsObject(o) && V1IsNum(o.x) && V1IsNum(o.y)
PzRd(v) => V1IsNum(v) ? Round(v) : "?"
PzF1(v) => V1IsNum(v) ? Format("{:.1f}", v) : ""
PzF2(v) => V1IsNum(v) ? Format("{:.2f}", v) : ""
PzNumOf(v) => V1Add(Trim(v), 0)
PzNow() => FormatTime(, "yyyyMMddHHmmss")
PzStamp() => FormatTime(, "yyyy-MM-dd HH:mm")
;A value for the file: | and line breaks become / and a space
PzCell(v) => RegExReplace(StrReplace(v "", "|", "/"), "\R", " ")
;The goal's letters with its count left out (UseBegin's cut): "2 of 3" matches "0 of 3"
PzGoalLetters(goal) => WalkLetters(RegExReplace(goal, "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?"))
;You in control: the bot off, walking off, or you playing (the bot's own presses never count)
PzPlayerControl() => !BotOn || !Walking || PlayerActive
;Who did it: you - the bot off, walking off, you playing or at the keyboard or mouse in the last 4 s - else the bot
PzWho() => (!BotOn || !Walking || PlayerActive || UserIdle() < 4000) ? "you" : "bot"
PzQuest() => IsSet(WkGoalQuest) ? WkGoalQuest : ""
PzIn(arr, v)
	{
	for i, xe in arr
		if (xe = v)
			return true
	return false
	}

;What the walker's and the helper's state hold, kept round a read from a timer or the hotkey (the walker's own reads, waits and
;prompt aren't touched: it may be mid-step)
PzSaveQuiet()
	{
	return V1Obj({navWhy: NavWhy, navWait: NavWait, navUntil: NavWaitUntil, goalWhy: NavGoalWhy, goalUntil: NavGoalWaitUntil
		, verr: VisionErr, dest: WkPromptDest, verb: WkPromptVerb, ptext: WkPromptText, el: ErrorLevel
		, itemsWhy: NavItemsWhy, itemsUntil: NavItemsWaitUntil, mobsWhy: NavMobsWhy, mobsUntil: NavMobsWaitUntil})
	}
PzRestoreQuiet(s)
	{
	global NavWhy, NavWait, NavWaitUntil, NavGoalWhy, NavGoalWaitUntil, VisionErr, WkPromptDest, WkPromptVerb, WkPromptText
	global ErrorLevel, NavItemsWhy, NavItemsWaitUntil, NavMobsWhy, NavMobsWaitUntil
	NavWhy := s.navWhy, NavWait := s.navWait, NavWaitUntil := s.navUntil, NavGoalWhy := s.goalWhy, NavGoalWaitUntil := s.goalUntil
	VisionErr := s.verr, WkPromptDest := s.dest, WkPromptVerb := s.verb, WkPromptText := s.ptext, ErrorLevel := s.el
	NavItemsWhy := s.itemsWhy, NavItemsWaitUntil := s.itemsUntil, NavMobsWhy := s.mobsWhy, NavMobsWaitUntil := s.mobsUntil
	}

;The wizard by the game's memory now - {zone, x, y, z, yaw, goalid, at}, "" not read (the main thread: PuzzleStep)
PzPosRead(ms := 300)
	{
	nr := NavRead(ms)
	if (!IsObject(nr) || !V1IsNum(nr.x) || !V1IsNum(nr.y))
		return ""
	return V1Obj({zone: nr.zone, x: nr.x, y: nr.y, z: nr.z, yaw: nr.yaw, goalid: nr.goalid, at: A_TickCount})
	}
;...from a timer: the run's own last reading while one is on, the walker's while the bot walks, else one read with the walker's
;state put back
PzPosQuiet(ms := 300)
	{
	if (IsObject(PzRun) && PzXY(PzRun.pos) && A_TickCount - PzRun.pos.at < 3000)
		return PzRun.pos
	if (!PzPlayerControl() && PzXY(WkNavObj))
		return V1Obj({zone: WkNavObj.zone, x: WkNavObj.x, y: WkNavObj.y, z: WkNavObj.z, yaw: WkNavObj.yaw, goalid: WkNavObj.goalid, at: A_TickCount})
	sq := PzSaveQuiet()
	p := PzPosRead(ms)
	PzRestoreQuiet(sq)
	return p
	}

;Past the stop (s: a run, the hold or a recording - {zone, x, y, dx, dy, kind}): in its zone, over PzPastBy beyond it the way
;on and within 3000 of it; a way out of the zone (kind door): the zone changed
PzPast(s, pos)
	{
	if (!IsObject(s) || !PzXY(pos))
		return false
	if (s.kind = "door")
		return pos.zone != "" && pos.zone != s.zone
	if (pos.zone != "" && pos.zone != s.zone)
		return false
	return (pos.x - s.x) * s.dx + (pos.y - s.y) * s.dy > PzPastBy && PzD(pos.x, pos.y, s.x, s.y) < 3000
	}

;---- 1. Is the way blocked? ----

;Where the walker was going (the goal in this zone, else the game's target - the way out; tx...: given), {x, y, z} or ""
PzTargetOf(tx := "", ty := "", tz := "")
	{
	if (V1IsNum(tx) && V1IsNum(ty))
		return V1Obj({x: tx, y: ty, z: tz})
	nw := WkNavObj
	if (!IsObject(nw))
		return ""
	if (nw.hops = 0 && V1IsNum(nw.gx) && V1IsNum(nw.gy))
		return V1Obj({x: nw.gx, y: nw.gy, z: nw.gz})
	if (V1IsNum(nw.tx) && V1IsNum(nw.ty))
		return V1Obj({x: nw.tx, y: nw.ty, z: nw.tz})
	return ""
	}

;An event where the walker is now (its own last reading - no read made), t its target
PzEvent(kind, r := "", t := "")
	{
	nw := WkNavObj
	if (!PzXY(nw) || nw.zone = "")
		return ""
	ev := V1Obj({at: A_TickCount, zone: nw.zone, x: nw.x, y: nw.y, z: nw.z, yaw: nw.yaw, r: r, kind: kind, goalid: nw.goalid
		, goal: PzGoalLetters(WkGoalLine), line: WkGoalLine, tx: "", ty: "", tz: "", said: 0})
	if (PzXY(t))
		ev.tx := t.x, ev.ty := t.y, ev.tz := t.z, ev.r := PzD(nw.x, nw.y, t.x, t.y)
	return ev
	}

;The way on from p: towards its target, else the way it faces ({dx, dy}, a unit vector; 0, 0 not known)
PzDir(p)
	{
	if (V1IsNum(p.dx) && V1IsNum(p.dy) && (p.dx != 0 || p.dy != 0))
		return V1Obj({dx: p.dx, dy: p.dy})
	if (V1IsNum(p.tx) && V1IsNum(p.ty))
		{
		d := PzD(p.x, p.y, p.tx, p.ty)
		if (d >= 1)
			return V1Obj({dx: (p.tx - p.x) / d, dy: (p.ty - p.y) / d})
		}
	if (V1IsNum(p.yaw))
		return V1Obj({dx: -Sin(p.yaw), dy: -Cos(p.yaw)})
	return V1Obj({dx: 0, dy: 0})
	}

PzKindSay(kind)
	{
	return kind = "approach" ? "approach blocked" : kind = "short" ? "short wait" : kind = "stuck" ? "stuck" : kind = "door" ? "the way out didn't load"
		: kind = "use" ? "stuck on the way to the thing" : kind = "wait" ? "waiting at the goal" : kind = "collect" ? "the goal given up on"
		: kind = "teleport" ? "a teleport that doesn't take" : kind
	}

;The walker's evidence of a block at one of its points (Walker.ahk / Collect.ahk): approach - stopped by something walking up
;to the goal; stuck - held against something; short - "arrived" well short of the goal; door - the way out pushed into twice;
;use - use mode stuck on the way to its thing (tx...: the thing). r: how far off the goal (game units). True when the puzzle
;takes over (the walker returns at once)
PuzzleEvidence(kind, r := "", tx := "", ty := "", tz := "")
	{
	try
		return PzEvidenceDo(kind, r, tx, ty, tz)
	catch as e
		{
		PzFail("the walker's evidence", e)
		return false
		}
	}
PzEvidenceDo(kind, r, tx, ty, tz)
	{
	global PzEv
	if (!PuzzleReady() || !PuzzleOn() || IsObject(PzRun) || IsObject(PzHeld))
		return false
	if ((kind = "approach" || kind = "short") && !(V1IsNum(r) && r > PzMinRDist))
		return false
	if (kind = "short" && WalkRouteRound(r))
		return false
	PzDlgNote()
	ev := PzEvent(kind, r, PzTargetOf(tx, ty, tz))
	if (!IsObject(ev))
		return false
	keep := []
	for i, e in PzEv
		if (A_TickCount - e.at <= 360000)
			keep.Push(e)
	keep.Push(ev)
	PzEv := keep
	return PzBlockNow(kind, ev)
	}

;Never a puzzle: why not now ("" it may be)
PzRefuse()
	{
	if (!PuzzleOn())
		return "puzzles off"
	if (IsObject(PzRun))
		return "a try is under way"
	if (IsObject(PzHeld))
		return "held at a blocked way"
	;(battles only - Autofarmer.ahk, Settings: battlesonly: no tries - they move the wizard)
	if (V1IsFunc("BattlesOnly") && %"BattlesOnly"%.Call())
		return "battles only (Settings)"
	if (V1IsFunc("PartyFollowing") && %"PartyFollowing"%.Call())
		return "a party's follower"
	if (IsObject(DgRun))
		return "a dungeon run"
	if (DgRecording)
		return "a dungeon run being recorded"
	if (PotionRecording)
		return "the potion buying being recorded"
	if (inbattle = 1 || (V1IsFunc("BattleLogInBattle") && %"BattleLogInBattle"%.Call()))
		return "a battle"
	;(the 21:44 case: a sigil that never started after a relog - no gate, no guards; WalkZone sets WkSigilAt 0 once its dungeon's in)
	if (WkWaitWhat = "sigil" && WkSigilAt && A_TickCount - WkSigilAt < 300000)
		return "a sigil X'd " Round((A_TickCount - WkSigilAt) / 1000) " s ago"
	if (WkNoteKind = "shop" || WkNoteKind = "window" || WkNoteKind = "quicksell")
		return "a notice about a window up"
	return ""
	}

;Dialogue ends the walker Spaced through, kept (WkDlgEndAt holds only the last)
PzDlgNote()
	{
	global PzDlgEnds
	if (!WkDlgEndAt)
		return
	if (!PzDlgEnds.Length || PzDlgEnds[PzDlgEnds.Length] != WkDlgEndAt)
		PzDlgEnds.Push(WkDlgEndAt)
	while (PzDlgEnds.Length > 30)
		PzDlgEnds.RemoveAt(1)
	}
;A dialogue Spaced through round an event at at: 0.5 s before to 3 s after (it froze the wizard - a narrator's)
PzDlgNear(at)
	{
	PzDlgNote()
	for i, t in PzDlgEnds
		if (t >= at - 500 && t <= at + 3000)
			return true
	return false
	}

PzSameGoal(a, b) => (a.goalid != "" && b.goalid != "") ? a.goalid = b.goalid : a.goal = b.goal

;The events of ev's zone and goal in the last 6 minutes within PzClusterR of it (oldest first)
PzClusterAll(ev)
	{
	out := []
	for i, e in PzEv
		if (e.zone = ev.zone && PzSameGoal(e, ev) && A_TickCount - e.at <= 360000 && PzD(e.x, e.y, ev.x, ev.y) <= PzClusterR)
			out.Push(e)
	return out
	}
;...those that count: not one a dialogue froze the wizard at
PzCounted(all)
	{
	out := []
	for i, e in all
		{
		if (PzDlgNear(e.at))
			{
			if (!e.said)
				e.said := 1, PzLog("not counted - a dialogue right after it (" PzKindSay(e.kind) " " PzRd(e.r) " off)")
			continue
			}
		out.Push(e)
		}
	return out
	}

;Is the zone one a puzzle can be in? "interior", "sigil" (entered through one), "door" (a blocker by the spot), "learned" (a way
;learned here) - "" not (the open world, no door or gate by it). The zone's kill hints are no reason on their own - they only rank
;the tries (63 open-world zones have some: Storm Haven's triggers name 5 kills, 4 of them bosses - a stuck at any wall there would
;have been a run at its boss camps instead of the Commons)
PzEligible(zone, p, door)
	{
	if (InStr(zone, "/Interiors/"))
		return "interior"
	if (IsObject(WkSigilZones) && WkSigilZones.Has(zone))
		return "sigil"
	if (IsObject(door))
		return "door"
	if (PuzzleFind(zone, p, p.goal, "", true).Length)
		return "learned"
	return ""
	}

;The block rule: fast - a door or gate near and the walker stopped there twice (once, a short wait, a way out or use mode); an
;interior's - stopped there 3 times over a minute or more. True when a run starts
PzBlockNow(kind, ev)
	{
	why := PzRefuse()
	if (why != "")
		{
		PzSay("refuse|" why, "not now - " why " (" PzKindSay(kind) " at " PzRd(ev.x) ", " PzRd(ev.y) ")", 60000)
		return false
		}
	all := PzClusterAll(ev), cl := PzCounted(all)
	nc := cl.Length
	door := PzDoorNear(ev, PzDir(ev))
	PzLog("stopped short of the goal at " PzRd(ev.x) ", " PzRd(ev.y) " (" PzRd(ev.r) " off; " PzKindSay(kind) ") - " nc " of " all.Length " there"
		. (IsObject(door) ? ", " door.name " " Round(door.ahead) " ahead (" (door.src = "mem" ? "the game's memory" : "the zone's file") ")" : ""))
	elig := PzEligible(ev.zone, ev, door)
	if (elig = "")
		{
		PzNotHere(ev, kind)
		return false
		}
	fast := IsObject(door) && (nc >= 2 || (nc >= 1 && (kind = "short" || kind = "door" || kind = "use")))
	inter := (elig = "interior" || elig = "sigil") && nc >= 3 && cl[nc].at - cl[1].at >= 60000
	if (!fast && !inter)
		return false
	return PuzzleStart(fast ? "fast" : "interior", kind, ev, door, cl)
	}

PzNotHere(ev, kind)
	{
	PzSay("nothere|" ev.zone "|" Round(ev.x / 400) "|" Round(ev.y / 400), "not a puzzle here - " (InStr(ev.zone, "/Interiors/") ? "" : "open world and ")
		. "no door or gate by it (" PzKindSay(kind) " at " PzRd(ev.x) ", " PzRd(ev.y) ")", 360000)
	}

;At the walker's own give-up points - stuck (its tries used up, or no closer in minutes), waiting at the goal, a teleport that
;doesn't take, a collect / use goal given up on: the puzzle first, when the zone may hold one and the goal's still well off.
;False when it doesn't take over (off, a cap's hold elsewhere, not a zone for it): the walker carries on as before
PuzzleBeforeNotice(kind, why, r := "")
	{
	try
		return PzBeforeNoticeDo(kind, why, r)
	catch as e
		{
		PzFail("a give-up point", e)
		return false
		}
	}
PzBeforeNoticeDo(kind, why, r)
	{
	if (!PuzzleReady() || !PuzzleOn())
		return false
	ref := PzRefuse()
	if (ref != "")
		{
		PzSay("refuse|" ref, "not now - " ref " (" PzKindSay(kind) ")", 60000)
		return false
		}
	t := (kind = "use" && IsObject(UsIt) && PzXY(UsIt)) ? V1Obj({x: UsIt.x, y: UsIt.y, z: UsIt.z}) : PzTargetOf()
	ev := PzEvent(kind, r, t)
	if (!IsObject(ev))
		return false
	door := PzDoorNear(ev, PzDir(ev))
	elig := PzEligible(ev.zone, ev, door)
	if (elig = "")
		{
		PzNotHere(ev, kind)
		return false
		}
	if (!(V1IsNum(ev.r) && ev.r > PzMinRDist) && kind != "collect" && kind != "use" && kind != "door" && kind != "teleport")
		return false
	PzLog("the walker gives up here (" why ") - " PzKindSay(kind) " at " PzRd(ev.x) ", " PzRd(ev.y) " (" PzRd(ev.r) " off the goal)")
	return PuzzleStart("give-up", kind, ev, door)
	}

;---- blockers and the zone's own hints ----

;The doors, gates and collision objects (the helper's /blockers - the game's memory's with no display key, mem, and the zone file's,
;file, with their starting state): [{name, x, y, z, dist, gid, src, state, start}], [] none, "" not read (an older helper). Kept 5 s.
;state: a memory door's state now (its ObjectStateBehavior - "" not read: an older helper, a build it can't read), a file door's
;starting one; start (10th): the zone file's starting state of the door ("" none, or an older helper)
PzBlockers(fresh := false)
	{
	global PzDoors, PzDoorsAt, PzDoorsZone
	zone := IsObject(WkNavObj) ? WkNavObj.zone : ""
	if (!fresh && PzDoorsAt && A_TickCount - PzDoorsAt < 5000 && PzDoorsZone = zone)
		return PzDoors
	ans := VisionGet("/blockers", 1500, true)
	PzDoorsAt := A_TickCount, PzDoorsZone := zone
	if (ans = "" || SubStr(ans, 1, 3) = "ERR")
		{
		PzDoors := ""
		return ""
		}
	out := []
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (V1At(f, 1) != "door" || f.Length < 8)
			continue
		out.Push(V1Obj({name: Trim(f[2]), x: NavNum(f[3]), y: NavNum(f[4]), z: NavNum(f[5]), dist: NavNum(f[6]), gid: Trim(f[7])
			, src: Trim(f[8]), state: f.Length >= 9 ? Trim(f[9]) : "", start: f.Length >= 10 ? Trim(f[10]) : ""}))
		}
	PzDoors := out
	return out
	}

;The door by spot p, the way on dir: the nearest blocker within PzDoorR, on its floor, not behind it - the game's memory's before
;the file's. {name, x, y, z, gid, src, state, start, d, ahead, others: [the other near ones]}, "" none. puzzlestate on: a memory
;door whose state reads open (PzOpenLike) and isn't its zone file's starting one any more (open already) isn't one - any other
;change (Open -> Closed: shut as the zone began) still is
PzDoorNear(p, dir)
	{
	bl := PzBlockers()
	if (!IsObject(bl) || !PzXY(p))
		return ""
	near := []
	for i, b in bl
		{
		if (!PzXY(b))
			continue
		dd := PzD(b.x, b.y, p.x, p.y)
		if (dd > PzDoorR || (V1IsNum(b.z) && V1IsNum(p.z) && Abs(b.z - p.z) > 260))
			continue
		ahead := (b.x - p.x) * dir.dx + (b.y - p.y) * dir.dy
		if (ahead <= -150)
			continue
		;(a state other than the file's start isn't open by itself - a trigger can shut a gate as the zone begins (EnterZone): only
		;an open-like one from a start that isn't is open already)
		if (b.src = "mem" && b.state != "" && b.start != "" && b.state != b.start)
			{
			if (!PzOpenLike(b.state) || PzOpenLike(b.start))
				PzSay("doorkeep|" b.name "|" b.state "|" b.start, b.name " is " b.state " (it starts " b.start ") - not an open state: still the block")
			else if (PzStateOn())
				{
				PzSay("doorskip|" b.gid "|" b.state, b.name " is " b.state " (it starts " b.start ") - open already: not the block", 60000)
				continue
				}
			else
				PzSay("doorskipoff|" b.name "|" b.state "|" b.start, b.name " is " b.state " (it starts " b.start ") - open already? (not acted on: puzzlestate is off)")
			}
		near.Push(V1Obj({name: b.name, x: b.x, y: b.y, z: b.z, gid: b.gid, src: b.src, state: b.state, start: b.start, d: dd
			, ahead: (dir.dx = 0 && dir.dy = 0) ? dd : ahead}))
		}
	best := ""
	for i, b in near
		if (!IsObject(best) || (b.src = "mem" && best.src != "mem") || (b.src = best.src && b.d < best.d))
			best := b
	if (IsObject(best))
		{
		best.others := []
		for i, b in near
			if (b != best)
				best.others.Push(b)
		}
	return best
	}

;The zone's own puzzle hints (the helper's /zonepuzzle - its triggers.xml, files only): {kills: [templates whose kill opens
;something], spawns: [objects its triggers make], hints: [{vol, x, y, z, r, text} - a dialogue on entering a volume], uses: [events],
;usedo: [{event, targets, states, acts} - what a use event's triggers do: the objects whose state they set, the states, the
;activations - an older helper's: empty], useobjs: [{event, template, x, y, z, how} - a placement that may fire it: a lever the game
;names nowhere, how "name" a guess by the event's words]}. Kept per zone (not read: asked again after a minute). Only ranks the tries
;and words the notice - never a filter
PzZoneHints(zone)
	{
	global PzHints
	if (PzHints.Has(zone))
		{
		h := PzHints[zone]
		if (h.ok || A_TickCount - h.at < 60000)
			return h
		}
	h := V1Obj({ok: 0, at: A_TickCount, kills: [], spawns: [], hints: [], uses: [], usedo: [], useobjs: []})
	if (zone != "")
		{
		ans := VisionGet("/zonepuzzle?zone=" NavUri(zone), 2500, true)
		if (ans != "" && SubStr(ans, 1, 3) != "ERR")
			{
			h.ok := 1
			Loop Parse, ans, "`n", "`r"
				{
				f := StrSplit(A_LoopField, "|")
				k := V1At(f, 1)
				if (k = "kill" && f.Length >= 2 && Trim(f[2]) != "")
					h.kills.Push(Trim(f[2]))
				else if (k = "spawn" && f.Length >= 2)
					h.spawns.Push(Trim(f[2]))
				else if (k = "use" && f.Length >= 2)
					{
					h.uses.Push(Trim(f[2]))
					;(3-5, a newer helper's: what its triggers do - each a list ; apart)
					if (f.Length >= 5)
						h.usedo.Push(V1Obj({event: Trim(f[2]), targets: PzSemiList(f[3]), states: PzSemiList(f[4]), acts: PzSemiList(f[5])}))
					}
				else if (k = "useobj" && f.Length >= 7 && Trim(f[3]) != "")
					h.useobjs.Push(V1Obj({event: Trim(f[2]), template: Trim(f[3]), x: NavNum(f[4]), y: NavNum(f[5]), z: NavNum(f[6]), how: Trim(f[7])}))
				else if (k = "hint" && f.Length >= 7)
					{
					txt := f[7]
					Loop f.Length - 7
						txt .= "|" f[A_Index + 7]
					h.hints.Push(V1Obj({vol: Trim(f[2]), x: NavNum(f[3]), y: NavNum(f[4]), z: NavNum(f[5]), r: NavNum(f[6]), text: Trim(txt)}))
					}
				}
			}
		}
	PzHints[zone] := h
	return h
	}

;A /zonepuzzle list field (values ; apart) as an array - [] empty
PzSemiList(s)
	{
	out := []
	for i, v in StrSplit(s, ";")
		if (Trim(v) != "")
			out.Push(Trim(v))
	return out
	}

;Is a template one the zone's triggers name (its kill opens something)?
PzKillHint(zone, tpl)
	{
	for i, k in PzZoneHints(zone).kills
		if (k = tpl)
			return true
	return false
	}

;---- 2. Tries ----

;The runs at this spot in the last hour: "" none over a cap, else why not (twice here, 4 times in the zone)
PzCapped(r)
	{
	global PzKeepFree
	if (PzKeepFree)
		return ""
	nSpot := 0, nZone := 0
	for i, h in PzHist
		{
		if (A_TickCount - h.at > 3600000 || h.zone != r.zone)
			continue
		nZone += 1
		if (PzD(h.x, h.y, r.x, r.y) <= PzSpotR)
			nSpot += 1
		}
	if (nSpot >= PzRunsHour)
		return "tried twice in the last hour here"
	if (nZone >= PzRunsZoneHour)
		return "tried " nZone " times in the last hour in this zone"
	return ""
	}

;What the last run at this spot tried (for a capped notice)
PzHistTried(r)
	{
	t := []
	for i, h in PzHist
		if (h.zone = r.zone && PzD(h.x, h.y, r.x, r.y) <= PzSpotR && IsObject(h.tried))
			t := h.tried
	return t
	}

PzDoorsSay(door)
	{
	if (!IsObject(door))
		return "no door or gate known"
	out := ""
	for i, d in PzDoorList(door)
		out .= (out = "" ? "" : ", ") d.name " (" (d.src = "mem" ? "memory" (d.state != "" ? ", now " d.state : "") (d.start != "" && d.start != d.state ? ", starts " d.start : "")
			: "zone file" (d.state != "" ? ", starts " d.state : "")) ", " Round(d.ahead) ")"
	return out
	}
PzDoorList(door)
	{
	l := [door]
	if (IsObject(door.others))
		for i, d in door.others
			l.Push(d)
	return l
	}

;---- the way's doors in the game's memory: gone, still there, their state ----

;The puzzlestate setting (off unless 1 - a door's state in the game's memory isn't confirmed in the game yet: vision\statemem.py
;--watch at a gate first): on, a door's state changed is the way maybe open (the check walks through, the hold looks, the recording
;ends), one known and unchanged is shut, and a memory door in an open state (PzOpenLike) that isn't its starting one isn't taken
;as the block; off, a state is only said in the log - the doors gone or there decide, as before
PzStateOn() => Stats.Has("puzzlestate") && Stats["puzzlestate"] = 1

;Does a state's name read open (Open, Opened, Unlocked, Lowered, Off, Disabled...) - never one that says shut too (Closed, Unopened)?
PzOpenLike(s) => s != "" && RegExMatch(s, "i)open|unlock|lower|disable|remove|deactivat|destroy|\boff\b") && !RegExMatch(s, "i)unopen|not.?open|clos|shut")

;The game's memory's doors of door (the door itself first, then its near others - PzDoorList - with a gid): what can go, or change
;state. [] none (no door, or only the zone file's)
PzMemDoors(door)
	{
	out := []
	if (IsObject(door))
		for i, d in PzDoorList(door)
			if (d.src = "mem" && d.gid != "")
				out.Push(d)
	return out
	}

;The blocker in bl (/blockers just read) that is d: the one with d's gid, else - a new instance gives every object a new gid (the
;dungeon left and come back to: PzAwayCap keeps a hold or a recording that long; its name and place stay) - the game's memory's of
;d's name nearest where d was, within 300, on its floor. That only while none of mine (the way's doors - mems, kept by their gid) is
;there by its gid: in the same instance a door missing is gone, whatever of its name stands by (a twin, another collision wall).
;"" none (gone from the game's memory)
PzBlockerOf(bl, d, mine := "")
	{
	for i, b in bl
		if (b.gid = d.gid)
			return b
	if (!PzXY(d) || d.name = "" || PzAnyThere(mine, bl))
		return ""
	pboBest := "", pboD := 0
	for i, b in bl
		{
		if (b.src != "mem" || b.name != d.name || !PzXY(b) || (V1IsNum(b.z) && V1IsNum(d.z) && Abs(b.z - d.z) > 260))
			continue
		pboDd := PzD(b.x, b.y, d.x, d.y)
		if (pboDd <= 300 && (!IsObject(pboBest) || pboDd < pboD))
			pboBest := b, pboD := pboDd
		}
	return pboBest
	}
;(is one of ds - the way's doors - in bl by its gid? none given: false)
PzAnyThere(ds, bl)
	{
	if (IsObject(ds))
		for i, d in ds
			if (d.gid != "")
				for j, b in bl
					if (b.gid = d.gid)
						return true
	return false
	}

;The first of mems (PzMemDoors - the door itself first) not in bl, "" all still there. mine: the way's doors (PzBlockerOf: one of
;them there by its gid - the same instance - no name-and-place match) - mems, unless more: a recording's others, its door too
PzGoneOf(mems, bl, mine := "")
	{
	if (!IsObject(mine))
		mine := mems
	for i, d in mems
		if (!IsObject(PzBlockerOf(bl, d, mine)))
			return d
	return ""
	}

;The first of mems still in bl named a collision wall (DynaTrigger_KT_DoorCollision - what holds the wizard: a gate's model can stay
;in the game's memory once open, its collision goes), "" none
PzCollisionOf(mems, bl)
	{
	for i, d in mems
		if (InStr(d.name, "collision") && IsObject(PzBlockerOf(bl, d, mems)))
			return d
	return ""
	}

;Has the state of one of mems changed (bl: /blockers just read)? "" none, or not known; else what - "CL-Gate Closed -> Open". Changed:
;not the state it had when the run began (state0 - PzStateKeep), or - none read then - not the zone file's starting one (start)
PzStateMoved(mems, bl)
	{
	for i, d in mems
		{
		b := PzBlockerOf(bl, d, mems)
		if (!IsObject(b) || b.state = "")
			continue
		was := d.state0 != "" ? d.state0 : b.start
		if (was != "" && b.state != was)
			return d.name " " was " -> " b.state
		}
	return ""
	}

;...one of mems whose state is known now and still the one it began with (or the file's starting one): "<name> still <state> (the
;game's memory)", "" none
PzStateSame(mems, bl)
	{
	for i, d in mems
		{
		b := PzBlockerOf(bl, d, mems)
		if (!IsObject(b) || b.state = "")
			continue
		was := d.state0 != "" ? d.state0 : b.start
		if (was != "" && b.state = was)
			return d.name " still " b.state " (the game's memory)"
		}
	return ""
	}

;Each of door's memory doors' state as read now kept as the one it began with (once: a hold's look again keeps the first)
PzStateKeep(door)
	{
	for i, d in PzMemDoors(door)
		if (d.state0 = "")
			d.state0 := d.state
	}

;True the first time key is seen for door (a near door gone, a state changed: looked at once each - the door outlives the holds)
PzSeenOnce(door, key)
	{
	if (!IsObject(door.seen))
		door.seen := V1Obj()
	if (door.seen.Has(key))
		return false
	door.seen[key] := 1
	return true
	}

;A run starts at the block (ev: the newest event, or the hold's spot; door: the door there; cl: the counted events; probeOnly: only
;a look whether it's open now - the hold's every 5 minutes; keepP: ev is the block's own spot already). True: the puzzle has taken
;over (a run, or - over a cap - the hold and the notice at once)
PuzzleStart(how, kind, ev, door := "", cl := "", probeOnly := false, keepP := false)
	{
	global PzRun, PzHist, PzKeepFree
	if (IsObject(PzRun))
		return true
	wd := PzDir(ev)
	bpx := ev.x, bpy := ev.y
	if (IsObject(door) && !keepP)
		bpx := door.x - wd.dx * 150, bpy := door.y - wd.dy * 150
	if (V1IsNum(ev.tx) && V1IsNum(ev.ty) && PzD(bpx, bpy, ev.tx, ev.ty) >= 1)
		dd := PzD(bpx, bpy, ev.tx, ev.ty), wd := V1Obj({dx: (ev.tx - bpx) / dd, dy: (ev.ty - bpy) / dd})
	r := V1Obj({how: how, kind: kind, zone: ev.zone, x: bpx, y: bpy, z: ev.z, dx: wd.dx, dy: wd.dy, tx: ev.tx, ty: ev.ty, tz: ev.tz
		, rP: V1IsNum(ev.tx) ? PzD(bpx, bpy, ev.tx, ev.ty) : "", goalid: ev.goalid, goal: ev.goal, line: ev.line, quest: PzQuest()
		, door: door, startAt: A_TickCount, lastStep: A_TickCount, active: 0, phase: "next", cands: [], ci: 0, cur: "", tried: []
		, fights: 0, battles: 0, probeOnly: probeOnly, learned: "", learnedOut: 0, tiers: "", gkey: "", goalAt: 0, zoneOffAt: 0, pos: ""
		, hint: "", last: "", resume: 0, pb: "", missAt: 0, missGid: "", done: V1Obj(), capped: "", passCache: V1Obj(), held: "", battleAt: 0})
	r.hint := PzHintNear(PzZoneHints(r.zone).hints, bpx, bpy)
	;(the doors' states now: what "changed" is measured from - "" not read: nothing changes)
	PzStateKeep(door)
	goalSay := r.line != "" ? r.line : "the quest's goal"
	capWhy := probeOnly ? "" : PzCapped(r)
	if (capWhy != "")
		{
		PzLog("the way to '" goalSay "' is blocked at " PzRd(bpx) ", " PzRd(bpy) " (" r.zone ") - " capWhy ": no tries, telling you")
		r.capped := capWhy, r.tried := PzHistTried(r)
		PzRun := r
		PuzzleEnd("tried")
		return true
		}
	if (!probeOnly)
		PzHist.Push(V1Obj({at: A_TickCount, zone: r.zone, x: bpx, y: bpy, tried: r.tried})), PzHoldWrite()
	PzKeepFree := 0
	if (KeysDown || HeldW)
		ReleaseKeys()
	PzGoalKey(r)
	PzRun := r
	nSay := IsObject(cl) && cl.Length ? "stopped there " cl.Length " time" (cl.Length = 1 ? "" : "s") " in " PzMinSec(cl[cl.Length].at - cl[1].at) : PzKindSay(kind)
	PzLog("the way to '" goalSay "' is blocked at " PzRd(bpx) ", " PzRd(bpy) " (" r.zone "): " nSay "; ahead: " PzDoorsSay(door)
		. " - " (probeOnly ? "looking whether it's open now" : how = "keep" ? "trying again (Keep trying)" : "trying what usually opens it"))
	if (probeOnly)
		{
		r.phase := "probe"
		return true
		}
	PzPlan(r)
	PzRecStart("spot", "a blocked way - its tries", r)
	return true
	}

PzMinSec(ms) => Floor(ms / 60000) ":" Format("{:02}", Mod(Floor(ms / 1000), 60))

;What the game said by the stop (x, y): the hint whose volume is nearest it, within the volume's reach and 1500 more - "" none
;there (a zone's hints can stand far apart - Wizard City's sunken city has two 59849 apart; the file's first may be another room's)
PzHintNear(hints, x, y)
	{
	best := "", bd := ""
	for i, h in hints
		{
		if (!V1IsNum(h.x) || !V1IsNum(h.y))
			continue
		d := PzD(h.x, h.y, x, y)
		if (d <= V1N(h.r) + 1500 && (bd = "" || d < bd))
			best := h, bd := d
		}
	return IsObject(best) ? best.text : ""
	}

;The goal now (id, count, status - the walker's waits kept as they were): a change ends the run
PzGoalKey(r)
	{
	sq := PzSaveQuiet()
	g := NavGoal(800)
	PzRestoreQuiet(sq)
	r.goalAt := A_TickCount
	if (!IsObject(g) || g.goalid = "")
		return ""
	key := g.goalid "|" V1At(g, "count") "|" g.status
	if (r.gkey = "")
		r.gkey := key
	return key
	}

;The plan, once at the start (tiers: "0" a way learned here first - tiers 1-3 only if it doesn't open it; else "123"), on one line
PzPlan(r, tiers := "")
	{
	if (tiers = "")
		{
		;(learned\puzzles.txt as it is now - you may have edited it since it was read)
		if (PuzzleLearnOn())
			PzFreshen()
		ents := PuzzleLearnOn() ? PuzzleFind(r.zone, r, r.goal, "") : []
		if (ents.Length)
			{
			e := ents[1]
			r.learned := e, r.tiers := "0"
			for i, st in e.steps
				{
				if (st.kind = "fight")
					r.cands.Push(V1Obj({kind: "camp", tier: 0, step: st, built: 0, label: PzStepLabel(st), x: st.x, y: st.y, z: st.z}))
				else if (st.kind = "x" || st.kind = "talk")
					r.cands.Push(V1Obj({kind: st.kind = "talk" ? "npc" : "thing", tier: 0, step: st, built: 0, name: st.name, template: st.template
						, x: st.x, y: st.y, z: st.z, plet: st.plet}))
				}
			walks := []
			for i, st in e.steps
				if (st.kind = "walk")
					walks.Push(st)
			if (walks.Length)
				r.cands.Push(V1Obj({kind: "walk", tier: 0, pts: walks, wi: 1}))
			r.cands.Push(V1Obj({kind: "check", tier: 0}))
			PzLog("learned (from " e.from ", " SubStr(e.learned, 1, 10) ", worked " e.ok " / failed " e.failed "): " PzStepsSay(e.steps) " - doing them first")
			return
			}
		if (PuzzleLearnOn())
			PzLog("no learned way here")
		}
	r.tiers .= "123"
	hints := PzZoneHints(r.zone)
	kills := V1Obj()
	for i, k in hints.kills
		kills[k] := 1
	;Tier 1: the side guards - an interior, a sigil's zone, a kill hint or a door by it
	camps := [], left := [], says := []
	tier1 := InStr(r.zone, "/Interiors/") || (IsObject(WkSigilZones) && WkSigilZones.Has(r.zone)) || hints.kills.Length || IsObject(r.door)
	if (tier1)
		{
		ms := NavMobs(r.line, 600)
		if (IsObject(ms))
			{
			PzTplNote(ms)
			keep := [], out := [], bigMobs := []
			for i, m in ms
				{
				if (!PzXY(m) || PzD(m.x, m.y, r.x, r.y) > PzGuardR)
					continue
				named := kills.Has(m.template)
				why := ""
				floorOut := V1IsNum(m.z) && V1IsNum(r.z) && Abs(m.z - r.z) > 260
				if (floorOut)
					why := "another floor"
				;(never a boss, never the quest's own mob - a kill hint naming it or not: many zones' triggers name their bosses; a
				;named mob only when the triggers name its kind)
				bossOut := m.boss = 1 || m.quest = 1 || (!named && m.named = 1)
				if (bossOut)
					why .= (why = "" ? "" : "; ") (m.boss = 1 ? "a boss" : "the quest's")
				if (PzBeyond(r, m))
					why := "beyond the block" (why = "" ? "" : "; " why)
				m.pzWhy := why, m.pzNamed := named
				if (why = "")
					keep.Push(m)
				else
					out.Push(m)
				if (bossOut && !floorOut)
					bigMobs.Push(m)
				}
			camps := PzCamps(keep, kills)
			left := PzCamps(out, kills)
			;(a camp standing by a boss or the quest's mob - within 700, the camps' own reach - is left out too: its battle would
			;take that one in)
			if (bigMobs.Length)
				{
				kept := []
				for i, c in camps
					{
					by := ""
					for j, m in c.mobs
						for k, b in bigMobs
							if (!IsObject(by) && PzD(m.x, m.y, b.x, b.y) <= 700)
								by := b
					if (IsObject(by))
						c.why := "by " (by.name != "" ? by.name : by.template) " - " (by.boss = 1 ? "a boss" : "the quest's"), left.Push(c)
					else
						kept.Push(c)
					}
				camps := kept
				}
			;(kill-named first, then by the way there from the block - the zone's nav graph, else straight)
			for i, c in camps
				{
				pc := PzPassOf(r, c)
				c.len := (IsObject(pc) && V1IsNum(pc.len)) ? pc.len : PzD(c.x, c.y, r.x, r.y)
				}
			camps := PzSort(camps, (a, b) => (a.named != b.named) ? b.named - a.named : a.len - b.len)
			while (camps.Length > PzCampMax)
				camps.Pop()
			}
		}
	for i, c in camps
		{
		c.tier := 1
		r.cands.Push(c)
		says.Push(c.label " at " Round(c.x) ", " Round(c.y) " (" Round(c.len) (i = 1 ? " off" : "") (c.named ? (i = 1 ? "; the zone's triggers name " c.namedName : "; named") : "") ")")
		}
	planSay := "plan - learned: " (IsObject(r.learned) ? "didn't open it" : "none") "; side guards: " (says.Length ? PzJoin(says, ", ") : tier1 ? "none" : "not looked for (open world, no door)")
	if (left.Length)
		{
		ls := []
		for i, c in left
			ls.Push(c.label " at " Round(c.x) ", " Round(c.y) " (" c.why ")")
		planSay .= "; left out: " PzJoin(ls, ", ")
		}
	;Tier 2: things with a prompt within PzObjR, the same floor, not the goal's own, not beyond, never a teleporter, a sigil, a lock or a
	;shop - and the things with no name the zone's triggers' use events may be fired by (a lever: /items' kind use), one whose trigger
	;opens the door at the block first - with puzzlelevers on (off: the levers only named here, not tried)
	usOff := []
	things := PzThings(r, "object", usOff)
	ts := [], us := []
	for i, t in things
		{
		r.cands.Push(t)
		if (t.use)
			us.Push(PzCandName(t) " (" Round(t.x) ", " Round(t.y) (t.opens != "" ? "; its trigger: " t.opens : "") ")")
		else
			ts.Push(t.name " (" Round(t.x) ", " Round(t.y) ")")
		}
	for i, t in usOff
		us.Push(PzCandName(t) " (" Round(t.x) ", " Round(t.y) (t.opens != "" ? "; its trigger: " t.opens : "") ")")
	planSay .= "; things with a prompt: " (ts.Length ? PzJoin(ts, ", ") : "none")
	if (us.Length || hints.useobjs.Length)
		planSay .= "; levers (zone's triggers" (PzLeversOn() ? "" : " - not tried: puzzlelevers is off") "): " (us.Length ? PzJoin(us, ", ") : "none near")
	;Tier 3: the zone's NPCs
	npcs := PzThings(r, "npc")
	ns := []
	for i, t in npcs
		r.cands.Push(t), ns.Push(t.name " (" Round(t.x) ", " Round(t.y) ")")
	planSay .= "; NPCs: " (ns.Length ? PzJoin(ns, ", ") : "none")
	PzLog(planSay)
	}

PzJoin(arr, sep)
	{
	out := ""
	for i, v in arr
		out .= (i = 1 ? "" : sep) v
	return out
	}

;An array sorted by less(a, b) < 0 first (insertion sort: a handful of items) - a new array
PzSort(arr, cmp)
	{
	out := []
	for i, v in arr
		{
		j := out.Length + 1
		while (j > 1 && cmp(v, out[j - 1]) < 0)
			j -= 1
		out.InsertAt(j, v)
		}
	return out
	}

;What each template was seen as (its name, a boss, the quest's): the notice's and the file's names, the recording's filters
PzTplNote(ms)
	{
	global PzTpl
	for i, m in ms
		if (m.template != "")
			PzTpl[m.template] := V1Obj({name: m.name, boss: m.boss, quest: m.quest})
	}
PzTplName(t) => PzTpl.Has(t) ? PzTpl[t].name : ""

;The zone's mobs read once for a recording (all: as it starts; else: as it's saved, only if one of its fights' templates is still
;unknown) - the templates no read has named yet noted. PzTpl is filled only by a run's own reads: a recording begun by a walker's
;notice, or carried on after a restart, had fights with no names, and the goal's own mob ('Defeat Greyhorn Mercenary') was saved
;as a step of the way (PzFightIsGoal). As it starts every one read is noted afresh (PzTplNote): PzTpl lasts the whole session,
;and a template marked the quest's hours ago, on another quest, made PzFightIsGoal drop your fight with it now. As it's saved
;one noted already keeps what it was seen as (the goal may have moved on - its mob no longer marked)
PzTplFill(rec, all := false)
	{
	global PzTpl
	if (!all)
		{
		miss := false
		for i, e in rec.steps
			if (e.kind = "fight")
				for j, t in e.foes
					if (!PzTpl.Has(t))
						miss := true
		if (!miss)
			return
		}
	sq := PzSaveQuiet()
	ms := NavMobs(rec.line, 600)
	PzRestoreQuiet(sq)
	if (!IsObject(ms))
		return
	if (all)
		{
		PzTplNote(ms)
		return
		}
	for i, m in ms
		if (m.template != "" && !PzTpl.Has(m.template))
			PzTpl[m.template] := V1Obj({name: m.name, boss: m.boss, quest: m.quest})
	}

;Mobs grouped into camps (single link, 700 apart at most): [{kind: "camp", mobs, names, tpls, tpl: {t: 1}, gids: {gid: 1}, x, y, z,
;named (holds a kill-hint template), namedName, label, why (left out: why)}]
PzCamps(mobs, kills)
	{
	camps := [], seen := V1Obj()
	Loop mobs.Length
		{
		i := A_Index
		if (seen.Has(i))
			continue
		member := [i], seen[i] := 1, k := 1
		while (k <= member.Length)
			{
			a := mobs[member[k]]
			Loop mobs.Length
				if (!seen.Has(A_Index) && PzD(a.x, a.y, mobs[A_Index].x, mobs[A_Index].y) <= 700)
					seen[A_Index] := 1, member.Push(A_Index)
			k += 1
			}
		c := V1Obj({kind: "camp", mobs: [], names: [], tpls: [], tpl: V1Obj(), gids: V1Obj(), x: 0, y: 0, z: "", named: 0, namedName: "", why: "", fought: 0})
		whys := []
		;(the kill-named first in the camp's names)
		order := []
		for j, idx in member
			{
			if (kills.Has(mobs[idx].template))
				order.InsertAt(1, idx)
			else
				order.Push(idx)
			}
		for j, idx in order
			{
			m := mobs[idx]
			c.mobs.Push(m), c.x += m.x, c.y += m.y
			if (V1IsNum(m.z))
				c.z := m.z
			if (m.name != "" && !PzIn(c.names, m.name))
				c.names.Push(m.name)
			if (m.template != "" && !c.tpl.Has(m.template))
				c.tpl[m.template] := 1, c.tpls.Push(m.template)
			c.gids[PzMobKey(m)] := 1
			if (kills.Has(m.template) && !c.named)
				c.named := 1, c.namedName := m.name != "" ? m.name : m.template
			if (m.pzWhy != "")
				for each, w in StrSplit(m.pzWhy, "; ")
					if (!PzIn(whys, w))
						whys.Push(w)
			}
		c.x /= c.mobs.Length, c.y /= c.mobs.Length
		c.why := PzJoin(whys, "; ")
		c.label := PzCampLabel(c)
		camps.Push(c)
		}
	return camps
	}
;A mob's key: its gid, else its template and place
PzMobKey(m) => m.gid != "" ? m.gid : "t:" m.template "@" Round(m.x / 100) "," Round(m.y / 100)
PzCampLabel(c)
	{
	lab := PzJoin(c.names, " + ")
	return lab != "" ? lab : PzJoin(c.tpls, " + ")
	}
PzStepLabel(s)
	{
	nm := []
	for i, v in s.names
		if (v != "" && !PzIn(nm, v))
			nm.Push(v)
	return nm.Length ? PzJoin(nm, " + ") : PzJoin(s.tpls, " + ")
	}

;Things with a prompt (kind object - and use: a thing with no name the zone's triggers' use events may be fired by, a lever) or the
;zone's NPCs (npc) for tiers 2 and 3, nearest the block first - a lever whose trigger opens the door at the block before them all.
;Never a teleporter, a portal, a sigil, a lock (a whole word "lock", or "...Lock" - not a Block, a Clock, a Warlock), a chest, a shop
;or with Crowns. Levers: only with puzzlelevers on (PzLeversOn - off: none, the things as before; off - put in off, an array, when
;given: the plan's log names them), at most PzUseMax of the PzObjMax (the named things keep the rest), and only one by a placement
;/zonepuzzle's useobj lines name (USE_CAP an event, the best first - the helper's /items marks every object of the template)
PzThings(r, kind, off := "")
	{
	its := NavItems(r.line, true)
	if (!IsObject(its))
		return []
	hints := kind = "object" ? PzZoneHints(r.zone) : ""
	got := []
	for i, t in its
		{
		use := kind = "object" && t.kind = "use"
		if ((t.kind != kind && !use) || !PzXY(t) || t.quest = 1)
			continue
		if (RegExMatch(t.name " " t.template, "(?i)teleport|portal|sigil|skeleton\s*key|key\s*lock|padlock|lockbox|(?-i:(?<![A-Za-z])(?:[Ll]ock|LOCK)(?![a-z])|(?<=[a-z0-9])Lock(?![a-z]))|chest|shop|vendor|mail|crown"))
			continue
		d := PzD(t.x, t.y, r.x, r.y)
		;(an NPC too - within PzGuardR and on the floor: 2026-11-14 13:16 the Icy Wall's block sent the wizard to Truda 5615 off and
		;Ymir 16506 off, 1:39 and 3 stuck episodes before a false "Way blocked")
		if ((kind = "object" || kind = "npc") && (d > (kind = "npc" ? PzGuardR : PzObjR) || (V1IsNum(t.z) && V1IsNum(r.z) && Abs(t.z - r.z) > 260)))
			continue
		if (PzBeyond(r, t))
			continue
		c := V1Obj({kind: kind = "npc" ? "npc" : "thing", tier: kind = "npc" ? 3 : 2, name: t.name, template: t.template, x: t.x, y: t.y, z: t.z
			, key: t.key, src: t.src, d: d, plet: "", use: use ? 1 : 0, label: "", event: "", opens: "", pri: 1})
		if (use)
			{
			PzUseNote(r, c, hints)
			if (c.outCap)
				continue
			if (!PzLeversOn())
				{
				if (IsObject(off))
					off.Push(c)
				continue
				}
			}
		got.Push(c)
		}
	;(no use things: every pri 1 - nearest first, as before)
	got := PzSort(got, (a, b) => (a.pri != b.pri) ? a.pri - b.pri : a.d - b.d)
	got := PzUseCap(got)
	cap := kind = "npc" ? PzNpcMax : PzObjMax
	while (got.Length > cap)
		got.Pop()
	if (IsObject(off) && off.Length)
		{
		pthOff := PzUseCap(PzSort(off, (a, b) => (a.pri != b.pri) ? a.pri - b.pri : a.d - b.d))
		off.Length := 0
		for i, c in pthOff
			off.Push(c)
		}
	return got
	}
;(things in order with no more than PzUseMax use things - the first of them kept)
PzUseCap(things)
	{
	pucOut := [], pucN := 0
	for i, c in things
		{
		if (c.use)
			{
			pucN += 1
			if (pucN > PzUseMax)
				continue
			}
		pucOut.Push(c)
		}
	return pucOut
	}

;The puzzlelevers setting (off unless 1 - a lever the game names nowhere is a guess by its template's name, X'd at any press prompt
;within 150: not tried in the game yet): on, PzThings' levers are tried with the things with a prompt; off, only named in the plan's
;log line
PzLeversOn() => Stats.Has("puzzlelevers") && Stats["puzzlelevers"] = 1

;A use thing c (no name - its name stays "": PzPromptOk's blank-name rule, any press prompt within 150, decides its X): its label for
;the log and the notice (its template, the event its trigger fires - /zonepuzzle's useobj lines, hints), and first (pri 0) when that
;event's triggers set the state of the door at the block (its name among their targets) or set an open-like state (Open, Unlock, Off).
;c.outCap 1: its template is in the useobj lines but none of their placements of it is by c (within 400 - the helper's ITEM_NEAR: a
;live thing stands for its placement there) - beyond the helper's USE_CAP an event (decoration of the same template); the template in
;none (they weren't built yet when the zone was asked): kept
PzUseNote(r, c, hints)
	{
	ev := "", punIn := 0, punBy := 0
	if (IsObject(hints))
		for i, u in hints.useobjs
			{
			if (u.template != c.template)
				continue
			punIn := 1
			if (PzXY(u) && PzD(u.x, u.y, c.x, c.y) <= 400)
				{
				ev := u.event, punBy := 1
				break
				}
			if (ev = "")
				ev := u.event
			}
	c.event := ev
	c.outCap := punIn && !punBy ? 1 : 0
	c.label := "the " c.template (ev != "" ? " (" ev ")" : "")
	if (ev = "" || !IsObject(hints))
		return
	for i, u in hints.usedo
		{
		if (u.event != ev)
			continue
		if (IsObject(r.door))
			for j, tg in u.targets
				for k, d in PzDoorList(r.door)
					if (tg != "" && d.name != "" && (tg = d.name || InStr(d.name, tg) || InStr(tg, d.name)))
						c.pri := 0, c.opens := c.opens != "" ? c.opens : tg
		for j, s in u.states
			if (PzOpenLike(s))
				c.pri := 0, c.opens := c.opens != "" ? c.opens : s
		}
	}

;Is c beyond the block? The navmesh ignores the gate, so whatever is reached through it has a nav path through it: the zone's
;nav graph from behind the stop, through the gate side of it (the helper's /navpass) - and not right at the gate. An older helper
;(no answer): beyond the stop's line on the way on. A way out of the zone has nothing beyond it in the zone
PzBeyond(r, c)
	{
	if (r.kind = "door" || !PzXY(c))
		return false
	p := PzPassOf(r, c)
	dP := PzD(c.x, c.y, r.x, r.y)
	if (IsObject(p))
		return p.pass = 1 && dP > 400
	return (c.x - r.x) * r.dx + (c.y - r.y) * r.dy > 300 && dP > 400
	}
;...the helper's answer for c ({pass, near, len}, "" none), kept for the run
PzPassOf(r, c)
	{
	key := Round(c.x) "," Round(c.y)
	if (r.passCache.Has(key))
		return r.passCache[key]
	p := PzPass(V1Obj({x: r.x - r.dx * 600, y: r.y - r.dy * 600, z: r.z}), c, V1Obj({x: r.x + r.dx * 150, y: r.y + r.dy * 150}), 200, r.zone)
	r.passCache[key] := p
	return p
	}
;The zone's nav graph from from to to: through the circle via (r) or not - {pass 1/0, near (the path's nearest to via), len}
PzPass(from, to, via, vr, zone := "")
	{
	z := (v) => V1IsNum(v) ? Round(v, 1) : ""
	ans := VisionGet("/navpass?fx=" Round(from.x, 1) "&fy=" Round(from.y, 1) "&fz=" z(from.z) "&tx=" Round(to.x, 1) "&ty=" Round(to.y, 1)
		. "&tz=" z(to.z) "&vx=" Round(via.x, 1) "&vy=" Round(via.y, 1) "&vr=" vr (zone != "" ? "&zone=" NavUri(zone) : ""), 1500, true)
	if (ans = "" || SubStr(ans, 1, 3) = "ERR")
		return ""
	f := StrSplit(Trim(V1At(StrSplit(ans, "`n"), 1), " `t`r"), "|")
	if (V1At(f, 1) != "pass" || f.Length < 4)
		return ""
	return V1Obj({pass: Trim(f[2]) = "1" ? 1 : 0, near: NavNum(f[3]), len: NavNum(f[4])})
	}

;The way to p round walls and mobs (the helper's /navto, as a follower walks to its leader - Party.ahk PartyNavTo): every mob kept
;off but those within spare of p (the camp walked into). {x, y, z, yaw, ax, ay, left, why, zone, at}, "" no answer
PzNavTo(p, spare := 0)
	{
	args := NavMobArgs()
	ans := VisionGet("/navto?x=" Round(V1N(p.x), 1) "&y=" Round(V1N(p.y), 1) "&z=" Round(V1N(p.z), 1) args (args != "" && spare > 0 ? "&spare=" spare : ""), 2500, true)
	if (ans = "" || SubStr(ans, 1, 3) = "ERR")
		return ""
	nav := V1Obj({x: "", y: "", z: "", yaw: "", ax: "", ay: "", left: "", why: "", zone: "", at: A_TickCount, goalid: ""})
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		while (f.Length < 5)
			f.Push("")
		if (f[1] = "pos")
			nav.x := NavNum(f[2]), nav.y := NavNum(f[3]), nav.z := NavNum(f[4]), nav.yaw := NavNum(f[5])
		else if (f[1] = "zone")
			nav.zone := Trim(f[2])
		else if (f[1] = "route")
			nav.ax := NavNum(f[2]), nav.ay := NavNum(f[3]), nav.left := NavNum(f[4])
		else if (f[1] = "routewhy")
			nav.why := Trim(SubStr(A_LoopField, 10))
		}
	return (nav.x = "" || nav.yaw = "") ? "" : nav
	}

;The run's own reading of the wizard (from a walk there, or read now)
PzSetPos(r, nav)
	{
	r.pos := V1Obj({zone: nav.zone != "" ? nav.zone : r.zone, x: nav.x, y: nav.y, z: nav.z, yaw: nav.yaw, goalid: r.goalid, at: A_TickCount})
	return r.pos
	}

;The duel by the game's log under way (the spellbook not seen since it began)
PzDuelOn() => IsObject(PzDuelNow) && PzDuelNow.result = "" && A_TickCount - PzDuelNow.at < 900000 && V1Lt(BookSeenAt, PzDuelNow.at)

;One step of a run (the main loop's, instead of WalkStep - at most about a second)
PuzzleStep()
	{
	try
		return PzStepDo()
	catch as e
		{
		PzFail("a step", e)
		return ""
		}
	}
PzStepDo()
	{
	r := PzRun
	if (!IsObject(r) || !Walking)
		return
	if (!GameActive())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("puzzle: paused - click into Wizard101")
		r.lastStep := A_TickCount
		Sleep(300)
		return
		}
	;(a battle: the main loop plays its rounds - battle time never counts against a budget)
	if (inbattle = 1 || (V1IsFunc("BattleLogInBattle") && %"BattleLogInBattle"%.Call()) || PzDuelOn())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		if (r.phase != "battle")
			r.phaseWas := r.phase, r.phase := "battle", r.battleAt := A_TickCount, r.battleOff := 0
		r.inBattle := 1, r.lastStep := A_TickCount
		SetStatus("puzzle: in a battle" ((IsObject(r.cur) && r.cur.kind = "camp") ? " with the way's guards" : ""))
		Sleep(150)
		return
		}
	;(a party's leader: waiting for the followers, as the walker does)
	pWhy := V1IsFunc("PartyHoldWhy") ? %"PartyHoldWhy"%.Call() : ""
	if (pWhy != "")
		{
		if (KeysDown || HeldW)
			ReleaseKeys(true)
		SetStatus("party: waiting - " pWhy)
		r.lastStep := A_TickCount
		Sleep(300)
		return
		}
	SpeedSet(0, "a puzzle")
	now := A_TickCount, dt := now - r.lastStep, r.lastStep := now
	;(a gap - a battle, you playing, F8 off - moves every budget on by it: the clocks are the run's own time, r.active)
	if (dt > 5000)
		dt := 0
	r.active += dt
	WalkZone(true)
	if (WkLoading)
		{
		r.active -= dt
		Sleep(300)
		return
		}
	if (DgDialogs())
		return
	if (now - r.goalAt >= 3000)
		{
		gk := PzGoalKey(r)
		if (gk != "" && r.gkey != "" && gk != r.gkey)
			{
			PuzzleEnd("goal", "the goal moved on")
			return
			}
		if (IsObject(r.pos) && r.pos.zone != "" && r.pos.zone != r.zone && r.kind != "door")
			{
			if (!r.zoneOffAt)
				r.zoneOffAt := now
			else if (now - r.zoneOffAt > 20000)
				{
				PuzzleEnd("zone", "out of " r.zone " (" r.pos.zone ")")
				return
				}
			}
		else
			r.zoneOffAt := 0
		}
	if (r.active > PzTimeCap)
		{
		r.tried.Push("12 minutes of tries - the time's up")
		PuzzleEnd("tried")
		return
		}
	switch r.phase
		{
		case "next":
			PzNext(r)
		case "battle":
			PzBattleStep(r)
		case "go":
			if (r.cur.kind = "camp")
				PzFightStep(r, r.cur)
			else
				PzThingStep(r, r.cur)
		case "walk":
			PzWalkStep(r, r.cur)
		case "afterx":
			PzAfterX(r)
		case "check":
			PzCheckStep(r)
		case "probe":
			PzProbeStep(r)
		case "back":
			PzBackStep(r)
		default:
			r.phase := "next"
		}
	}

;The next try ("" all done: the hold and the notice)
PzNext(r)
	{
	Loop
		{
		r.ci += 1
		if (r.ci > r.cands.Length)
			{
			;(the learned way's steps all tried and it didn't open: tiers 1-3 now - planned only now)
			if (r.tiers = "0")
				{
				PzPlan(r, "123")
				;(a step back first: continue goes round to r.ci += 1 again, and the first new try - the camp the zone's
				;triggers name, or the nearest side guard - was jumped over)
				if (r.ci <= r.cands.Length)
					{
					r.ci -= 1
					continue
					}
				}
			PuzzleEnd("tried")
			return
			}
		c := r.cands[r.ci]
		c.from := r.active, c.budget := 0, c.engages := 0, c.byAt := 0, c.nearAt := 0, c.promptAt := 0, c.stillAt := 0, c.tries := 0
		c.mobsAt := 0, c.live := "", c.sawPress := 0
		r.cur := c, r.resume := 0, r.missAt := 0
		if (c.kind = "check")
			{
			r.phase := "check"
			return
			}
		if (c.kind = "camp" && c.tier = 0 && !c.built && !PzStepCamp(r, c))
			{
			r.tried.Push("the learned " c.label " - not here now")
			PzLog("the step's " c.label " isn't here now - done already? (next)")
			continue
			}
		if ((c.kind = "thing" || c.kind = "npc") && c.tier = 0 && !c.built)
			PzStepThing(r, c)
		;(camps and things done already in this run - the learned way's - left out)
		if (c.kind = "camp" && c.tier > 0 && PzCampDone(r, c))
			continue
		if ((c.kind = "thing" || c.kind = "npc") && r.done.Has(PzThingKey(c)))
			continue
		r.phase := c.kind = "walk" ? "walk" : "go"
		return
		}
	}

PzThingKey(c) => c.template "@" Round(c.x / 100) "," Round(c.y / 100)
PzCampDone(r, c)
	{
	for g, v in c.gids
		if (!r.done.Has("g:" g))
			return false
	return true
	}

;A learned fight step's camp now: the live mobs of its templates within 8000 of its spot, on the block's floor, not beyond it,
;grouped - the camp holding most of its templates, then the one nearest the spot (a new instance puts the guards on either
;side: by template, the spot only a preference). False: none alive
PzStepCamp(r, c)
	{
	ms := NavMobs("", 600)
	if (!IsObject(ms))
		return false
	PzTplNote(ms)
	stp := c.step
	want := V1Obj()
	for i, t in stp.tpls
		want[t] := 1
	got := []
	for i, m in ms
		if (PzXY(m) && want.Has(m.template) && PzD(m.x, m.y, stp.x, stp.y) <= 8000 && !(V1IsNum(m.z) && V1IsNum(r.z) && Abs(m.z - r.z) > 260)
			&& !PzBeyond(r, m))
			m.pzWhy := "", got.Push(m)
	if (!got.Length)
		return false
	camps := PzCamps(got, V1Obj())
	for i, k in camps
		k.nT := k.tpls.Length, k.dS := PzD(k.x, k.y, stp.x, stp.y)
	camps := PzSort(camps, (a, b) => (a.nT != b.nT) ? b.nT - a.nT : a.dS - b.dS)
	k := camps[1]
	for each, f in ["mobs", "names", "tpls", "tpl", "gids", "x", "y", "z", "named", "label"]
		c[f] := k[f]
	c.built := 1
	PzLog("the learned " PzStepLabel(stp) " (recorded at " Round(stp.x) ", " Round(stp.y) ") is at " Round(k.x) ", " Round(k.y) " now")
	return true
	}

;A learned X / talk step's thing now: the same template within 600 of its spot (the game's memory, the zone's file), else the spot
PzStepThing(r, c)
	{
	c.built := 1
	its := NavItems(r.line, true)
	if (!IsObject(its))
		return
	for i, t in its
		if (t.template = c.template && c.template != "" && PzXY(t) && PzD(t.x, t.y, c.x, c.y) <= 600)
			{
			c.x := t.x, c.y := t.y, c.z := t.z, c.name := t.name != "" ? t.name : c.name
			return
			}
	}

;Stuck on the way to a try's place (UseStuck's way, its own counts): 3 s hardly moving with W down - backed up and turned
;("moved"); a fifth time - "skip"; "" walking on
PzStuck(c, nav, d)
	{
	if (HeldW && c.stillAt && (nav.x - c.stillX) ** 2 + (nav.y - c.stillY) ** 2 < 3600)
		{
		if (A_TickCount - c.stillAt <= 3000)
			return ""
		c.tries += 1, c.stillAt := 0
		if (c.tries > 4)
			return "skip"
		PzLog("stuck on the way to " PzCandName(c) " (" Round(d) " away) - backing up and turning, try " c.tries)
		BackUp(700)
		DgTurn(c.tries & 1 ? 90 : -90)
		HoldW(1)
		Sleep(900)
		return "moved"
		}
	c.stillAt := A_TickCount, c.stillX := nav.x, c.stillY := nav.y
	return ""
	}

;(a thing with no name - a lever the zone's triggers point at: its label, else its template)
PzCandName(c)
	{
	if (c.kind = "camp")
		return c.label
	if (c.kind = "walk")
		return "the way you walked"
	return c.name != "" ? c.name : c.label != "" ? c.label : c.template != "" ? c.template : "a thing"
	}

;A try given up (why) - on to the next
PzSkip(r, c, why)
	{
	r.tried.Push((c.kind = "camp" ? "fought " c.label " (" Round(c.x) ", " Round(c.y) ")" : c.kind = "walk" ? "walked your way" : (c.kind = "npc" ? "talk to " : "X at ") PzCandName(c)) " - " why)
	PzLog((c.kind = "camp" ? c.label : PzCandName(c)) ": " why " - next")
	ReleaseKeys()
	r.phase := "next"
	}

;go - a camp: walked into (its nearest live mob; the mobs read every 1.5 s), every other mob kept off
PzFightStep(r, c)
	{
	if (!c.mobsAt || A_TickCount - c.mobsAt >= 1500)
		{
		c.mobsAt := A_TickCount
		ms := NavMobs("", 400)
		if (IsObject(ms))
			{
			PzTplNote(ms)
			live := []
			for i, m in ms
				if (c.gids.Has(PzMobKey(m)) && PzXY(m))
					live.Push(m)
			c.live := live
			}
		}
	if (IsObject(c.live) && !c.live.Length)
		{
		for g, v in c.gids
			r.done["g:" g] := 1
		PzSkip(r, c, "not there now - done already?")
		return
		}
	if (!IsObject(c.live))
		{
		ReleaseKeys()
		Sleep(200)
		return
		}
	me := IsObject(r.pos) ? r.pos : c
	t := c.live[1]
	for i, m in c.live
		if (PzD(m.x, m.y, me.x, me.y) < PzD(t.x, t.y, me.x, me.y))
			t := m
	nav := PzNavTo(t, 700)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		Sleep(200)
		return
		}
	PzSetPos(r, nav)
	d := PzD(nav.x, nav.y, t.x, t.y)
	if (!c.budget)
		c.budget := 30000 + Round(((V1IsNum(nav.left) && nav.left > 0) ? nav.left : d) / 600 * 1000)
	if (r.active - c.from > c.budget)
		{
		PzSkip(r, c, "not got to in " Round(c.budget / 1000) " s (" Round(d) " off)")
		return
		}
	if (d <= 600)
		c.nearAt := c.nearAt ? c.nearAt : r.active
	else
		c.nearAt := 0
	;(walked right into it with no battle: once more, then left)
	if (d <= 150 || (c.nearAt && r.active - c.nearAt >= 12000))
		{
		c.engages += 1
		if (c.engages >= 2)
			{
			PzSkip(r, c, "walked into it - no battle came")
			return
			}
		PzLog("walked into " c.label " - no battle came; once more")
		BackUp(600)
		c.nearAt := 0
		return
		}
	st := PzStuck(c, nav, d)
	if (st = "skip")
		{
		PzSkip(r, c, "stuck on the way (" Round(d) " off)")
		return
		}
	if (st = "moved")
		return
	nCamps := 0, iCamp := 0
	for i, k in r.cands
		if (k.kind = "camp")
			nCamps += 1, iCamp := (i <= r.ci) ? nCamps : iCamp
	SetStatus("puzzle: walking to " c.label " - " iCamp " of " nCamps " camp" (nCamps = 1 ? "" : "s") ", " Round(d) " away")
	DgSteer(nav, V1Obj({x: t.x, y: t.y}), d)
	}

;The last duel by the journal since a moment ("" none)
PzLastDuel(since)
	{
	if (IsObject(PzDuelNow) && PzDuelNow.at >= since)
		return PzDuelNow
	Loop PzJ.Length
		{
		e := PzJ[PzJ.Length - A_Index + 1]
		if (e.kind = "fight" && e.at >= since)
			return e
		if (e.at < since)
			break
		}
	return ""
	}

;battle - its end: the spellbook seen since it began, the journal's duel's outcome; lost: the run's over; the camp's mobs in
;it (or its gids gone): that camp's fought. Then the check
PzBattleStep(r)
	{
	if (!r.battleOff)
		r.battleOff := A_TickCount
	if (!V1Gt(BookSeenAt, r.battleAt) && A_TickCount - r.battleOff < 20000)
		{
		Sleep(150)
		return
		}
	duel := PzLastDuel(r.battleAt - 20000)
	if (IsObject(duel) && duel.result = "" && A_TickCount - r.battleOff < 5000)
		{
		Sleep(150)
		return
		}
	res := IsObject(duel) ? (duel.result != "" ? duel.result : "won") : "won?"
	r.inBattle := 0, r.battles += 1
	c := r.cur
	if (res = "lost")
		{
		r.tried.Push("a battle " (IsObject(c) && c.kind = "camp" ? "with " c.label " " : "") "- lost")
		PuzzleEnd("lost", "the battle was lost")
		return
		}
	fought := false
	if (IsObject(c) && c.kind = "camp")
		{
		if (IsObject(duel))
			for i, t in duel.foes
				if (c.tpl.Has(t))
					fought := true
		if (!fought)
			{
			ms := NavMobs("", 400)
			if (IsObject(ms))
				{
				have := V1Obj()
				for i, m in ms
					have[PzMobKey(m)] := 1
				for g, v in c.gids
					if (!have.Has(g))
						fought := true
				}
			}
		}
	if (fought)
		{
		r.fights += 1, c.fought := 1
		for g, v in c.gids
			r.done["g:" g] := 1
		r.last := "fighting " c.label
		r.tried.Push("fought " c.label " (" Round(c.x) ", " Round(c.y) " - " res ")")
		PzLog("fought " c.label " (" res ") - looking whether the way's open")
		r.resume := 0
		}
	else
		{
		PzLog("a battle on the way" (IsObject(duel) && duel.foes.Length ? " (" PzJoin(duel.foes, " + ") ")" : "") " - looking whether the way's open")
		r.resume := (IsObject(c) && c.kind != "check") ? 1 : 0
		}
	r.phase := "check", r.missAt := 0, r.checkAt := 0
	}

;go - a thing or an NPC: walked to; within 400 its prompt read every 0.7 s - X only at a press prompt naming it (an NPC's to talk),
;never with Crowns on it, never a teleporter's or a shop's; no prompt by it in 3 s: left (never a blind X)
PzThingStep(r, c)
	{
	nav := PzNavTo(c, 0)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		Sleep(200)
		return
		}
	PzSetPos(r, nav)
	d := PzD(nav.x, nav.y, c.x, c.y)
	if (!c.budget)
		c.budget := 30000 + Round(((V1IsNum(nav.left) && nav.left > 0) ? nav.left : d) / 600 * 1000)
	if (r.active - c.from > c.budget)
		{
		PzSkip(r, c, "not got to in " Round(c.budget / 1000) " s (" Round(d) " off)")
		return
		}
	if (d <= 400 && (!c.promptAt || A_TickCount - c.promptAt >= 700))
		{
		c.promptAt := A_TickCount
		p := InteractPrompt()
		if (p = "press")
			{
			ok := PzPromptOk(c, d)
			if (ok = "crown")
				{
				r.done[PzThingKey(c)] := 1
				PzSkip(r, c, "Crowns on its prompt - never an X")
				return
				}
			if (ok = "x")
				{
				PzPressX(r, c)
				return
				}
			}
		}
	held := HeldW && c.stillAt && A_TickCount - c.stillAt > 1500 && d <= 300 && (nav.x - c.stillX) ** 2 + (nav.y - c.stillY) ** 2 < 3600
	if (d <= 150 || held)
		c.byAt := c.byAt ? c.byAt : A_TickCount
	else if (d > 350)
		c.byAt := 0
	if (c.byAt)
		{
		if (A_TickCount - c.byAt >= 3000)
			{
			r.done[PzThingKey(c)] := 1
			PzSkip(r, c, "no prompt")
			return
			}
		ReleaseKeys()
		SetStatus("puzzle: by " PzCandName(c) " - looking for its prompt")
		Sleep(150)
		return
		}
	st := PzStuck(c, nav, d)
	if (st = "skip")
		{
		PzSkip(r, c, "stuck on the way (" Round(d) " off)")
		return
		}
	if (st = "moved")
		return
	SetStatus("puzzle: walking to " PzCandName(c) " (" Round(d) " away)")
	DgSteer(nav, V1Obj({x: c.x, y: c.y}), d)
	}

;The prompt just read (InteractPrompt's) at thing c, d off: "x" (it names the thing - its recorded prompt letters, else its name;
;a blank name: any press prompt within 150), "crown" (Crowns on it), "teleport", "shop", "verb" (an NPC's not to talk), "other"
PzPromptOk(c, d)
	{
	dest := WkPromptDest, verb := WkPromptVerb, txt := WkPromptText
	if (RegExMatch(txt, "i)cr[o0]wn"))
		return "crown"
	if (InStr(dest, "TELEPORT"))
		return "teleport"
	if (RegExMatch(verb, "i)^(shop|buy|sell|trade|browse|craft)"))
		return "shop"
	if (c.kind = "npc" && !RegExMatch(verb, "i)^(talk|speak)"))
		return "verb"
	named := (c.plet != "" && WalkNameLike(dest, c.plet)) || (c.name != "" ? WalkNameLike(dest, WalkLetters(c.name), c.name) : d <= 150)
	return named ? "x" : "other"
	}

;X at the thing (its prompt read just now, every guard passed) - then what it opened is looked at
PzPressX(r, c)
	{
	global WkPreXText, WkAfterXLooked, WkLastX
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	dest := WkPromptDest, verb := WkPromptVerb
	WkPreXText := WalkAfterXText(&pzPre), WkAfterXLooked := 0
	PressKey("x"), WkLastX := A_TickCount
	r.done[PzThingKey(c)] := 1
	r.last := "X at " PzCandName(c)
	r.tried.Push((c.kind = "npc" ? "talked to " : "X at ") PzCandName(c))
	PzLog("X at " PzCandName(c) " (its prompt '" SubStr(dest, 1, 30) "', " verb ")")
	SetStatus("puzzle: X at " (dest != "" ? dest : StrUpper(PzCandName(c))))
	PzJournal(V1Obj({kind: c.kind = "npc" ? "talk" : "x", at: A_TickCount, time: PzNow(), zone: r.zone, x: r.pos.x, y: r.pos.y, z: r.pos.z
		, dest: dest, verb: verb, crown: 0, tname: c.name, ttpl: c.template, tkind: c.kind = "npc" ? "npc" : c.use ? "use" : "object", tx: c.x, ty: c.y, tz: c.z
		, tquest: 0, who: "bot"}))
	r.phase := "afterx", r.xAt := A_TickCount, r.closed := 0, r.dlgAt := 0
	}

;afterx (8 s): a dialogue Spaced through; at 0.7 s, once, a window X opened closed (WalkCloseAfterX: Escape for a shop - an OK
;never with Crowns in sight); then the check
PzAfterX(r)
	{
	if (WalkDialogOpen())
		{
		WalkSkipDialog()
		r.dlgAt := A_TickCount
		return
		}
	if (!r.closed && A_TickCount - r.xAt >= 700)
		{
		r.closed := 1
		WalkCloseAfterX()
		return
		}
	if (A_TickCount - r.xAt >= 8000 || (r.dlgAt && A_TickCount - r.dlgAt >= 1500))
		{
		r.phase := "check", r.missAt := 0, r.checkAt := 0
		return
		}
	Sleep(150)
	}

;check: is the way open? The memory's door gone (two reads 1.5 s apart, in the zone within 6000 of it), past the stop, a way out
;loaded. A near memory door gone instead (a gate's collision goes while its model stays - 2026-10-26 Storm Lord's Temple): the probe
;walks through to see. All still there: a collision wall among them - shut (no walk back to look); only a gate's model (it can stay
;in the game's memory once open) - the probe. puzzlestate on: a door's state changed - the probe; known and unchanged - shut (off:
;said in the log only). None known: the probe
PzCheckStep(r)
	{
	pos := PzPosRead(300)
	if (IsObject(pos))
		PzSetPos(r, pos)
	if (IsObject(pos) && PzPast(r, pos))
		{
		PuzzleEnd("solved", "past the block")
		return
		}
	door := r.door
	mems := PzMemDoors(door)
	if (mems.Length)
		{
		bl := PzBlockers(true)
		if (IsObject(bl))
			{
			gone := PzGoneOf(mems, bl)
			if (!IsObject(gone))
				{
				r.missAt := 0
				moved := PzStateMoved(mems, bl)
				if (moved != "" && PzStateOn())
					{
					PzLog("the way may be open - " moved " (the game's memory) - walking through to see")
					r.phase := "probe", r.pb := ""
					return
					}
				if (moved != "")
					PzSay("stateoff|" moved, "a door's state changed - " moved " (the game's memory; not acted on: puzzlestate is off)", 60000)
				col := PzCollisionOf(mems, bl)
				if (IsObject(col))
					{
					SetStatus("puzzle: checking the way (" col.name " still there)")
					PzShut(r, col.name " still there (the game's memory)")
					return
					}
				same := PzStateOn() ? PzStateSame(mems, bl) : ""
				if (same != "")
					{
					SetStatus("puzzle: checking the way (" door.name " still shut)")
					PzShut(r, same)
					return
					}
				PzLog(door.name " still there (the game's memory) - a gate's model can stay once it's open: walking through to see")
				r.phase := "probe", r.pb := ""
				return
				}
			;(two reads 1.5 s apart missing the same door - another one missing now starts its own)
			if (!r.missAt || r.missGid != gone.gid)
				{
				r.missAt := A_TickCount, r.missGid := gone.gid
				Sleep(200)
				return
				}
			if (A_TickCount - r.missAt < 1500)
				{
				Sleep(200)
				return
				}
			if (IsObject(pos) && pos.zone = r.zone && PzD(pos.x, pos.y, gone.x, gone.y) <= 6000)
				{
				if (gone.gid = door.gid)
					{
					PuzzleEnd("solved", door.name " gone (the game's memory)")
					return
					}
				PzLog(gone.name " gone (the game's memory), by " door.name " - walking through to see")
				}
			}
		}
	r.phase := "probe", r.pb := ""
	}

;The way still shut after a try (why): the learned way's end counted failed; on to the next try (or back to the camp a battle on
;the way took it from); the battles' cap: the hold
PzShut(r, why)
	{
	c := r.cur
	PzLog("the way's still shut - " why)
	ReleaseKeys()
	r.pb := "", r.missAt := 0
	PzRecShut(r)
	if (IsObject(c) && c.kind = "check")
		{
		PzLearnedResult(r.learned, false)
		PzLog("the learned way didn't open it - the usual tries now")
		r.learnedOut := 1
		}
	if (r.battles >= PzMaxFights)
		{
		r.tried.Push(PzMaxFights " battles - the most a run fights")
		PuzzleEnd("tried")
		return
		}
	if (r.probeOnly)
		{
		PuzzleEnd("tried")
		return
		}
	r.phase := (r.resume && IsObject(c) && c.kind != "check" && !c.fought) ? (c.kind = "walk" ? "walk" : "go") : "next"
	r.resume := 0
	}

;probe: walked back to the stop and on through it (400 past): past it - open; stopped within 350 of it (under 60 units in 1.5 s with W
;down) - shut. A way out: pushed straight on into it 3 s - a load is open. A teleport: the helper's given-up ones tried again
PzProbeStep(r)
	{
	global NavUnblock
	if (!IsObject(r.pb))
		{
		r.pb := V1Obj({x: r.x + r.dx * 400, y: r.y + r.dy * 400, z: r.z}), r.pbFrom := r.active, r.pbBudget := 0, r.pbStillAt := 0, r.pushAt := 0
		;(back to the stop itself first - from a camp off to the side the straight way meets the wall well off it - then on through it)
		r.pbAt := PzXY(r.pos) && PzD(r.pos.x, r.pos.y, r.x, r.y) > 200 ? 1 : 2
		if (r.kind = "teleport")
			NavUnblock := 1
		SetStatus("puzzle: walking back to the block to see if it's open")
		}
	if (r.pbAt = 1 && PzXY(r.pos) && PzD(r.pos.x, r.pos.y, r.x, r.y) <= 150)
		r.pbAt := 2, r.pbStillAt := 0
	nav := PzNavTo(r.pbAt = 1 ? V1Obj({x: r.x, y: r.y, z: r.z}) : r.pb, 0)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		Sleep(200)
		return
		}
	PzSetPos(r, nav)
	if (PzPast(r, nav))
		{
		PuzzleEnd("solved", r.kind = "door" ? "the way out loaded" : "walked through it")
		return
		}
	dP := PzD(nav.x, nav.y, r.x, r.y)
	if (!r.pbBudget)
		r.pbBudget := 20000 + Round(((V1IsNum(nav.left) && nav.left > 0) ? nav.left : PzD(nav.x, nav.y, r.pb.x, r.pb.y)) / 600 * 1000)
	if (r.active - r.pbFrom > r.pbBudget)
		{
		PzShut(r, "not got through in " Round(r.pbBudget / 1000) " s")
		return
		}
	;(a way out of the zone: pushed straight on into it 3 s)
	if (r.kind = "door" && dP <= 150)
		{
		r.pushAt := r.pushAt ? r.pushAt : A_TickCount
		if (A_TickCount - r.pushAt >= 3000)
			{
			PzShut(r, "pushed into the way out 3 s, nothing loaded")
			return
			}
		HoldW(1)
		Sleep(100)
		return
		}
	if (dP <= 350 && HeldW)
		{
		if (!r.pbStillAt || PzD(nav.x, nav.y, r.pbStillX, r.pbStillY) >= 60)
			r.pbStillAt := A_TickCount, r.pbStillX := nav.x, r.pbStillY := nav.y
		else if (A_TickCount - r.pbStillAt >= 1500)
			{
			PzShut(r, "stopped at it again (" Round(dP) " from the stop)")
			return
			}
		}
	else
		r.pbStillAt := 0
	aim := r.pbAt = 1 ? V1Obj({x: r.x, y: r.y}) : r.pb
	DgSteer(nav, aim, PzD(nav.x, nav.y, aim.x, aim.y))
	}

;back: every try done - walked back to the stop (within 200; a minute at most), then the hold there
PzBackStep(r)
	{
	nav := PzNavTo(V1Obj({x: r.x, y: r.y, z: r.z}), 0)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		Sleep(200)
		return
		}
	PzSetPos(r, nav)
	d := PzD(nav.x, nav.y, r.x, r.y)
	if (d <= 200 || r.active - r.backFrom > 60000)
		{
		PuzzleEnd("tried")
		return
		}
	SetStatus("puzzle: back to the blocked way (" Round(d) " away)")
	DgSteer(nav, V1Obj({x: r.x, y: r.y}), d)
	}

;walk (a learned walk route): each point in turn (within 120), then the probe
PzWalkStep(r, c)
	{
	if (c.wi > c.pts.Length)
		{
		r.phase := "probe", r.pb := ""
		return
		}
	pt := c.pts[c.wi]
	nav := PzNavTo(pt, 0)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		Sleep(200)
		return
		}
	PzSetPos(r, nav)
	d := PzD(nav.x, nav.y, pt.x, pt.y)
	if (d <= 120)
		{
		c.wi += 1, c.stillAt := 0
		return
		}
	if (!c.budget)
		c.budget := 60000 + Round(c.pts.Length * 5000)
	if (r.active - c.from > c.budget)
		{
		PzSkip(r, c, "not walked in " Round(c.budget / 1000) " s")
		return
		}
	st := PzStuck(c, nav, d)
	if (st = "skip")
		{
		PzSkip(r, c, "stuck on the way")
		return
		}
	if (st = "moved")
		return
	SetStatus("puzzle: walking your way through (" c.wi " of " c.pts.Length ")")
	DgSteer(nav, pt, d)
	}

;---- the end of a run, the hold, the notice ----

;A run ends: solved (the way's open - learned or saved, the walker walks on), goal / zone / lost (the walker takes it from here),
;tried (every try and cap - the hold at the stop and the notice)
PuzzleEnd(how, why := "")
	{
	global PzRun, PzHeld, NavUnblock, WkArrived, WkArrDist
	r := PzRun
	if (!IsObject(r))
		return
	ReleaseKeys()
	if (how = "solved")
		{
		PzRun := ""
		PzLog("the way's open after " (r.last != "" ? r.last : r.probeOnly ? "a while held there" : "a look") " (" why ")")
		learnedWay := IsObject(r.learned) && !r.learnedOut
		if (learnedWay)
			PzLearnedResult(r.learned, true)
		if (IsObject(PzRec) && PzRec.kind = "spot" && PzRec.zone = r.zone)
			{
			PzRec.openAt := A_TickCount
			;(the run's own tries opened it - not a look while held: its tries that came before are kept, they may have been
			;needed together (both side guards); PzSolution)
			PzRec.byRun := r.probeOnly ? 0 : 1
			;(a learned way that worked: its counts are what's new - not a second entry of the same)
			if (learnedWay)
				PzRecEnd(false, "the learned way opened it (its count kept in learned\puzzles.txt)")
			else
				PzRecEnd(true, "the way's open (" why ")")
			}
		WalkNotifyClose("puzzle")
		if (IsObject(r.held) && r.held.gaveUp && IsObject(WkCollect))
			WkCollect.gaveUp := 0, WkCollect.from := A_TickCount, WkCollect.progressAt := A_TickCount, WkCollect.stepAt := A_TickCount
		NavUnblock := 1
		PzHoldWrite()
		WalkReset()
		SetStatus("puzzle: the way's open - walking on")
		return
		}
	if (how = "goal" || how = "zone" || how = "lost")
		{
		PzRun := ""
		PzLog("tries over - " why)
		PzHoldWrite()
		WalkReset()
		return
		}
	;tried: back to the stop first - the last try may have ended far off it (a camp, a lever) - then the hold there
	if (!r.probeOnly && r.capped = "" && !r.backDone && PzXY(r.pos) && PzD(r.pos.x, r.pos.y, r.x, r.y) > 300 && Walking)
		{
		r.backDone := 1, r.phase := "back", r.backFrom := r.active, r.cur := ""
		PzLog("the tries are over - back to the stop to wait there")
		return
		}
	;the hold - the wizard waits at the stop (battles fought, the recording on) - and the notice
	PzRun := ""
	;(a learned way whose tries ran out before its check - the battle cap, the time's up: it didn't open it either, counted as
	;failed - else it was replayed first every time, never set aside)
	if (IsObject(r.learned) && !r.learnedOut)
		{
		r.learnedOut := 1
		PzLearnedResult(r.learned, false)
		PzLog("the learned way's tries ran out before it opened - counted as failed")
		}
	;(the hold: none of the run's tries opened it - those since its last check too (the time's up, the battle cap, before a check):
	;the recording's count of them moved on, as PzShut's (PzRecShut) - else they were saved ahead of your step)
	PzRecShut(r)
	h := V1Obj({zone: r.zone, x: r.x, y: r.y, z: r.z, dx: r.dx, dy: r.dy, tx: r.tx, ty: r.ty, tz: r.tz, kind: r.kind, door: r.door
		, goalid: r.goalid, goal: r.goal, line: r.line, at: A_TickCount, probeAt: A_TickCount, offAt: 0, gaveUp: 0, tried: r.tried
		, tickAt: 0, doorAt: 0, missAt: 0, missGid: ""})
	if (IsObject(r.held))
		h.at := r.held.at, h.gaveUp := r.held.gaveUp
	PzHeld := h
	PzHoldWrite()
	WkArrived := 1, WkArrDist := ""
	if (IsObject(WkCollect) && !WkCollect.gaveUp)
		WkCollect.gaveUp := 1, h.gaveUp := 1
	PzLog(r.probeOnly ? "still shut - held there again" : "nothing it tried opened the way - waiting there, telling you" (r.capped != "" ? " (" r.capped ")" : ""))
	if (!r.probeOnly)
		WalkNotify("puzzle", "Way blocked - the quest needs you", PuzzleNoticeText(r), true)
	SetStatus("waiting at the blocked way - do what opens it" (PuzzleLearnOn() ? " (the bot watches and learns it)" : ""))
	}

;The notice's text: where, what blocks it, what was tried (6 at most), what the game said there, what to do
PuzzleNoticeText(r := "")
	{
	r := IsObject(r) ? r : PzHeld
	if (!IsObject(r))
		return ""
	mem := "", fileDoor := ""
	if (IsObject(r.door))
		for i, d in PzDoorList(r.door)
			{
			if (d.src = "mem" && mem = "")
				mem := d.name
			else if (d.src != "mem" && fileDoor = "")
				fileDoor := d.name
			}
	t := "The way to '" (r.line != "" ? r.line : "the quest's goal") "' is blocked at " PzRd(r.x) ", " PzRd(r.y) " (" r.zone ") - a door or gate the bot can't get through"
		. ((mem != "" || fileDoor != "") ? " (" (mem != "" ? "the game's memory: " mem " there" : "") (mem != "" && fileDoor != "" ? "; " : "") (fileDoor != "" ? "the zone's file: " fileDoor : "") ")" : "") "."
	items := ""
	for i, it in r.tried
		if (i <= 6)
			items .= (i = 1 ? "" : "; ") it
	if (r.tried.Length > 6)
		items .= "; and " (r.tried.Length - 6) " more"
	if (r.capped != "")
		t .= " It " r.capped (items != "" ? ": " items : "") "."
	else
		t .= items != "" ? " It tried: " items ". None opened it." : " It found nothing to try here."
	if (r.hint != "")
		t .= " The game said: `"" r.hint "`""
	t .= PuzzleLearnOn() ? " Do what opens it - the bot watches and learns it for next time. It walks on by itself once the way is open."
		: " Do what opens it - it walks on by itself once the way is open."
	return t "`n`nKeep trying: the tries once more. Stop walking: walking off."
	}

;Keep trying (the notice's button - its own thread): a fresh run, the spot's hour count cleared once (the main thread does it)
PuzzleKeep()
	{
	global PzMain
	if (PuzzleReady())
		PzMain.keep := 1
	}

;F8 walking on (its own thread): the hold and any run forgotten - the walker walks on (the main thread ends a run)
PuzzleForget(why)
	{
	global PzHeld, PzMain
	if (!PuzzleReady() || (!IsObject(PzHeld) && !IsObject(PzRun)))
		return
	PzHeld := ""
	PzMain.forget := why
	;(no hold carried over a restart either - the main loop may not run again before one: the bot off)
	try PzHoldWrite(true)
	}

;The main thread's share: what a timer, a hotkey or a button asked for - between two steps, never in the middle of one
PzMainWork()
	{
	global PzRun, PzHeld, PzMain, PzKeepFree, WkArrived, WkArrDist
	if (PzMain.forget != "")
		{
		why := PzMain.forget, PzMain.forget := "", PzMain.holdEnd := "", PzMain.keep := 0, PzMain.reprobe := 0
		if (IsObject(PzRun))
			PzRun := "", ReleaseKeys()
		PzHeld := ""
		PzHoldWrite()
		WalkNotifyClose("puzzle")
		PzLog("forgotten - " why)
		}
	if (PzMain.holdEnd != "")
		{
		why := PzMain.holdEnd, PzMain.holdEnd := ""
		if (IsObject(PzHeld))
			PzHoldEnd(why)
		}
	if (PzMain.keep)
		{
		PzMain.keep := 0
		if (IsObject(PzHeld) && !IsObject(PzRun))
			{
			h := PzHeld, PzHeld := "", PzKeepFree := 1
			PzLog("Keep trying - the tries once more")
			PuzzleStart("keep", h.kind, h, h.door, "", false, true)
			if (IsObject(PzRun))
				PzRun.held := h
			PzHoldWrite()
			}
		}
	if (PzMain.reprobe)
		{
		PzMain.reprobe := 0
		if (IsObject(PzHeld) && !IsObject(PzRun))
			{
			h := PzHeld, PzHeld := ""
			PzLog("held " Round((A_TickCount - h.at) / 60000) " minutes - looking whether the way's open now")
			PuzzleStart("reprobe", h.kind, h, h.door, "", true, true)
			if (IsObject(PzRun))
				PzRun.held := h
			PzHoldWrite()
			}
		}
	;(held: a walker's reset - you stopping playing, F6 on - doesn't walk it back into the gate)
	if (IsObject(PzHeld) && !IsObject(PzRun) && WkArrived = 0 && PzXY(WkNavObj) && WkNavObj.zone = PzHeld.zone
		&& PzD(WkNavObj.x, WkNavObj.y, PzHeld.x, PzHeld.y) <= 600 && (PzHeld.goalid = "" || WkNavObj.goalid = "" || WkNavObj.goalid = PzHeld.goalid))
		WkArrived := 1, WkArrDist := ""
	}

;The hold over (why): the notice closed, the walker walks on
PzHoldEnd(why)
	{
	global PzHeld
	h := PzHeld
	PzHeld := ""
	PzHoldWrite()
	PzLog("the hold's over - " why " - walking on")
	WalkNotifyClose("puzzle")
	if (h.gaveUp && IsObject(WkCollect))
		WkCollect.gaveUp := 0, WkCollect.from := A_TickCount, WkCollect.progressAt := A_TickCount, WkCollect.stepAt := A_TickCount
	WalkReset()
	SetStatus("the way's open - walking on")
	}

;The hold (also one a Keep trying or a look again under way holds - unless forgetting: noRun) and the runs of the last hour, into
;generated\puzzle_hold.txt: a restart (an update, you) carries on with them - else the walker walks back into the gate and the
;tries start afresh, the hour's caps forgotten, while you solve it (2026-10-26: the bot restarted three times during your solve)
PzHoldWrite(noRun := false)
	{
	h := IsObject(PzHeld) ? PzHeld : (!noRun && IsObject(PzRun) && IsObject(PzRun.held)) ? PzRun.held : ""
	t := "; Wiz-Maxxing - the hold at a blocked way and the tries of the last hour (Puzzle.ahk) - a restart carries on with them`r`n"
	for i, pzRun1 in PzHist
		if (A_TickCount - pzRun1.at <= 3600000)
			t .= "tries|" PzAgoStamp(pzRun1.at) "|" PzCell(pzRun1.zone) "|" PzF1(pzRun1.x) "|" PzF1(pzRun1.y) "`r`n"
	if (IsObject(h))
		{
		d := h.door
		t .= "hold|" PzAgoStamp(h.at) "|" PzCell(h.zone) "|" PzF1(h.x) "|" PzF1(h.y) "|" PzF1(h.z) "|" PzF2(h.dx) "|" PzF2(h.dy) "|" PzF1(h.tx) "|" PzF1(h.ty)
			. "|" PzF1(h.tz) "|" h.kind "|" PzCell(h.goalid) "|" PzCell(h.goal) "|" PzCell(h.line) "|" (IsObject(d) ? PzCell(d.name) "|" PzCell(d.gid) "|" d.src
			. "|" PzF1(d.x) "|" PzF1(d.y) "|" PzF1(d.z) : "|||||") "|" (h.gaveUp ? 1 : 0) "`r`n"
		}
	PzWriteFile(PzHoldFile, t)
	}
;A tick count as the time it was (yyyyMMddHHmmss)
PzAgoStamp(at) => FormatTime(DateAdd(A_Now, -Round((A_TickCount - at) / 1000), "Seconds"), "yyyyMMddHHmmss")
;...read back at the start: the runs of the last hour (the caps), and the hold - its zone, goal and door looked at again by the tick
PzHoldLoad()
	{
	global PzHist, PzHeld
	t := PzReadFile(PzHoldFile)
	if (t = "")
		return
	for i, hl in PzLines(t)
		{
		f := StrSplit(hl.t, "|")
		if (f.Length < 5 || !RegExMatch(f[2], "^\d{14}$"))
			continue
		try
			age := DateDiff(A_Now, f[2], "Seconds")
		catch
			continue
		if (age < 0)
			continue
		at := A_TickCount - age * 1000
		if (f[1] = "tries" && age <= 3600)
			PzHist.Push(V1Obj({at: at, zone: f[3], x: PzNumOf(f[4]), y: PzNumOf(f[5]), tried: []}))
		else if (f[1] = "hold" && f.Length >= 22 && PzNumOf(f[4]) != "" && PzNumOf(f[5]) != "")
			{
			door := f[16] = "" ? "" : V1Obj({name: f[16], gid: f[17], src: f[18], x: PzNumOf(f[19]), y: PzNumOf(f[20]), z: PzNumOf(f[21]), state: "", d: 0, ahead: 0})
			PzHeld := V1Obj({zone: f[3], x: PzNumOf(f[4]), y: PzNumOf(f[5]), z: PzNumOf(f[6]), dx: V1N(PzNumOf(f[7])), dy: V1N(PzNumOf(f[8])), tx: PzNumOf(f[9])
				, ty: PzNumOf(f[10]), tz: PzNumOf(f[11]), kind: f[12], door: door, goalid: f[13], goal: f[14], line: f[15], at: at, probeAt: A_TickCount
				, offAt: 0, gaveUp: 0, tried: [], tickAt: 0, doorAt: 0, missAt: 0, missGid: ""})
			PzLog("held at the blocked way at " PzRd(PzHeld.x) ", " PzRd(PzHeld.y) " (" PzHeld.zone ") since " Round(age / 60) " minutes before - carried on after a restart")
			}
		}
	}

;The hold, every second (the tick): the door gone, past the stop, the goal moved on, out of the zone 10 minutes - over (the main
;thread ends it); every 5 minutes with you away a minute, out of battle, the bot on and walking: a look whether it's open
PzHoldTick()
	{
	global PzMain
	h := PzHeld
	if (!IsObject(h) || IsObject(PzRun) || PzMain.holdEnd != "")
		return
	now := A_TickCount
	if (now - h.tickAt < 1000)
		return
	h.tickAt := now
	pos := PzPosQuiet(300)
	if (IsObject(pos) && pos.zone != "")
		{
		if (pos.zone != h.zone)
			{
			if (h.kind = "door")
				{
				PzMain.holdEnd := "through the way out"
				return
				}
			if (!h.offAt)
				h.offAt := now
			else if (now - h.offAt > PzAwayCap)
				{
				PzMain.holdEnd := "out of the zone for 10 minutes"
				return
				}
			}
		else
			{
			h.offAt := 0
			if (PzPast(h, pos))
				{
				PzMain.holdEnd := "past the block"
				return
				}
			}
		if (h.goalid != "" && pos.goalid != "" && pos.goalid != h.goalid)
			{
			PzMain.holdEnd := "the goal moved on"
			return
			}
		}
	;(the door gone: over. A near memory door gone - a gate's collision while its model stays -, or - puzzlestate on - a door's state
	;changed: a look whether it's open as soon as you're away a minute, once for each)
	mems := PzMemDoors(h.door)
	if (mems.Length && now - h.doorAt >= 3000)
		{
		h.doorAt := now
		sq := PzSaveQuiet()
		bl := PzBlockers(true)
		PzRestoreQuiet(sq)
		if (IsObject(bl) && IsObject(pos) && pos.zone = h.zone)
			{
			;(the miss time is the door's that's missing: a near one gone for good keeps its own, so the door itself missing from one
			;read still needs a second 1.5 s on)
			gone := PzGoneOf(mems, bl)
			if (!IsObject(gone))
				h.missAt := 0
			else if (!h.missAt || h.missGid != gone.gid)
				h.missAt := now, h.missGid := gone.gid
			else if (now - h.missAt >= 1500 && PzD(pos.x, pos.y, gone.x, gone.y) <= 6000)
				{
				if (gone.gid = h.door.gid)
					{
					PzMain.holdEnd := h.door.name " gone (the game's memory)"
					return
					}
				if (PzSeenOnce(h.door, "gone|" gone.gid))
					{
					PzLog(gone.name " gone (the game's memory), by " h.door.name " - a look whether the way's open once you're away a minute")
					h.lookSoon := 1
					}
				}
			moved := PzStateMoved(mems, bl)
			if (moved != "" && PzSeenOnce(h.door, "state|" moved))
				{
				if (PzStateOn())
					{
					PzLog("the way may be open - " moved " (the game's memory) - a look once you're away a minute")
					h.lookSoon := 1
					}
				else
					PzLog("a door's state changed - " moved " (the game's memory; not acted on: puzzlestate is off)")
				}
			}
		}
	if ((now - h.probeAt >= PzReprobe || h.lookSoon) && !PzMain.reprobe && UserIdle() >= 60000 && inbattle != 1
		&& !(V1IsFunc("BattleLogInBattle") && %"BattleLogInBattle"%.Call()) && BotOn && Walking && !PlayerActive)
		h.probeAt := now, h.lookSoon := 0, PzMain.reprobe := 1
	}

;---- 3. The journal: what happened in the game lately ----

;One line of the game's log (EnemySpells.ahk BattleLogRead, each line before the battle's own reading): duels (their foes'
;templates, where, who started it, won / lost / fled), the goal moving on, zones, prompts coming into reach
PuzzleLogLine(line)
	{
	try
		return PzLogLineDo(line)
	catch as e
		{
		PzFail("the game's log", e)
		return ""
		}
	}
PzLogLineDo(line)
	{
	global PzDuelNow, PzZoneNow, PzZoneAt, PzInter
	if (!PuzzleReady())
		return
	if (InStr(line, "Duel "))
		{
		if (RegExMatch(line, "Duel (\d+): MSG_CombatAdd\((.+?)\)", &m))
			{
			;(Non-local Player: another wizard - an ally who joined, or the one whose battle this is - not a mob: no foe's template,
			;and the "won" count of the foes taken out never reached it)
			if (m[2] = "Local Player" || m[2] = "Non-local Player")
				return
			d := PzDuelGet(m[1])
			d.foes.Push(m[2])
			;(the duel under way kept in the journal's file too: a restart in the middle of it - the real case had two - carries on
			;with it, and its end still reaches the journal)
			PzJSave()
			return
			}
		if (RegExMatch(line, "Duel (\d+): Local Player Entering Combat at \(([-\d.]+), ([-\d.]+), ([-\d.]+)\)", &m))
			{
			d := PzDuelGet(m[1])
			d.x := m[2] + 0, d.y := m[3] + 0, d.z := m[4] + 0, d.who := PzWho()
			PzJSave()
			return
			}
		if (InStr(line, "MSG_CombatFlee"))
			{
			if (IsObject(PzDuelNow))
				PzDuelNow.fled := 1, PzJSave()
			return
			}
		;(the match's result - 0 your side won, else it lost: a knockout ends the duel so, with no MSG_CombatRemove(Local
		;Player) - 2026-11-07..14 41 knockouts, each MatchResult(1): a duel still without a result was taken as won. One
		;already closed as won - "Leaving state: Sigil" comes as the first enemy goes, mid-battle (2026-11-14 12:29, the
		;12:40 knockout's battle) - is put right in the journal: the last fight of that duel, ended in the last 30 minutes)
		if (RegExMatch(line, "Duel (\d+): MSG_CombatMatchResult\((-?\d+)\)", &m))
			{
			if (m[2] = 0)
				return
			d := PzDuelNow
			if (IsObject(d) && d.duel = m[1] && d.result = "")
				{
				d.result := d.fled ? "fled" : "lost"
				PzDuelEnd(d)
				return
				}
			if (IsObject(d) && d.duel = m[1])
				return
			global PzJ ; (read: the journal)
			pzI := IsObject(PzJ) ? PzJ.Length : 0
			while (pzI >= 1)
				{
				e := PzJ[pzI], pzI -= 1
				if (e.kind != "fight" || e.duel != m[1])
					continue
				;(its end - a fight read back from the journal's file at a restart (PzJLoad) has none: its start)
				pzEnd := (e.endAt != "" && e.endAt) ? e.endAt : e.at
				if (InStr(e.result, "won") = 1 && pzEnd != "" && A_TickCount - pzEnd < 1800000)
					{
					e.result := e.fled ? "fled" : "lost"
					PzJSave()
					}
				break
				}
			return
			}
		if (RegExMatch(line, "Duel (\d+): MSG_CombatRemove\((.+?)\)", &m))
			{
			d := PzDuelNow
			if (!IsObject(d) || d.duel != m[1])
				return
			if (m[2] = "Local Player")
				{
				d.result := d.fled ? "fled" : "lost"
				PzDuelEnd(d)
				return
				}
			;(another wizard leaving isn't a foe taken out - not among the foes either)
			if (m[2] = "Non-local Player")
				return
			d.outs += 1
			if (d.outs >= d.foes.Length)
				{
				d.result := "won"
				PzDuelEnd(d)
				}
			else
				PzJSave()
			return
			}
		return
		}
	if (InStr(line, "MSG_CombatFlee"))
		{
		if (IsObject(PzDuelNow))
			PzDuelNow.fled := 1, PzJSave()
		return
		}
	if (InStr(line, "Leaving state: Sigil"))
		{
		if (IsObject(PzDuelNow) && PzDuelNow.result = "")
			PzDuelNow.result := PzDuelNow.fled ? "fled" : "won", PzDuelEnd(PzDuelNow)
		return
		}
	if (InStr(line, "SetActiveGoal()"))
		{
		PzJournal(V1Obj({kind: "goal", at: A_TickCount, time: PzNow(), zone: PzZoneNow}))
		return
		}
	if (RegExMatch(line, "ConnectComplete destination Zone=(.+?)\s*$", &m))
		{
		PzZoneNow := m[1], PzZoneAt := A_TickCount
		PzJournal(V1Obj({kind: "zone", at: A_TickCount, time: PzNow(), zone: m[1]}))
		return
		}
	if (InStr(line, "InteractionManager::NewNPCInteraction"))
		{
		PzInter.open := 1, PzInter.openAt := A_TickCount, PzInter.want := 1
		return
		}
	if (InStr(line, "------ CloseInteraction"))
		PzInter.open := 0, PzInter.closeAt := A_TickCount
	}

;The duel under way with that number - a new one made (an old one still open: closed as it stood)
PzDuelGet(id)
	{
	global PzDuelNow
	if (IsObject(PzDuelNow) && PzDuelNow.duel = id)
		return PzDuelNow
	if (IsObject(PzDuelNow) && PzDuelNow.result = "")
		PzDuelNow.result := "won?", PzDuelEnd(PzDuelNow)
	zone := PzZoneNow != "" ? PzZoneNow : (IsObject(WkNavLast) && WkNavLast.zone != "") ? WkNavLast.zone : IsObject(WkNavObj) ? WkNavObj.zone : ""
	PzDuelNow := V1Obj({kind: "fight", at: A_TickCount, time: PzNow(), zone: zone, foes: [], names: [], outs: 0, x: "", y: "", z: ""
		, who: PzWho(), result: "", duel: id, fled: 0, endAt: 0})
	return PzDuelNow
	}

;A duel over: its names filled (what each template was seen as), into the journal
PzDuelEnd(d)
	{
	global PzDuelNow
	if (IsObject(PzDuelNow) && PzDuelNow = d)
		PzDuelNow := ""
	d.endAt := A_TickCount
	d.names := []
	for i, t in d.foes
		d.names.Push(PzTplName(t))
	PzJournal(d)
	}

;An entry into the journal (the last 40, 30 minutes - and its file), and the recording
PzJournal(e)
	{
	global PzJ
	PzJ.Push(e)
	keep := []
	for i, xe in PzJ
		if (A_TickCount - xe.at <= 1800000)
			keep.Push(xe)
	while (keep.Length > 40)
		keep.RemoveAt(1)
	PzJ := keep
	PzJSave()
	PzRecOnEntry(e)
	}

;A journal entry as a line of generated\puzzle_journal.txt
PzJLine(e)
	{
	b := e.kind "|" e.time "|" PzCell(e.zone)
	if (e.kind = "fight")
		return b "|" PzF1(e.x) "|" PzF1(e.y) "|" PzF1(e.z) "|" e.who "|" e.result "|" PzCell(PzJoin(e.foes, "+")) "|" PzCell(PzJoin(e.names, "+")) "|" e.duel
	if (e.kind = "x" || e.kind = "talk")
		return b "|" PzF1(e.x) "|" PzF1(e.y) "|" PzF1(e.z) "|" e.who "|" PzCell(e.dest) "|" PzCell(e.verb) "|" e.crown "|" PzCell(e.tname) "|" PzCell(e.ttpl)
			. "|" e.tkind "|" PzF1(e.tx) "|" PzF1(e.ty) "|" PzF1(e.tz) "|" e.tquest
	return b
	}
PzJSave()
	{
	t := "; Wiz-Maxxing - the puzzle journal (Puzzle.ahk): what happened in the game lately - duels, X presses, goals, zones. Rewritten`r`n"
		. "; by itself; a restart keeps it. kind|yyyyMMddHHmmss|zone|...`r`n"
	for i, e in PzJ
		t .= PzJLine(e) "`r`n"
	;(the duel under way, if any: a fight line's fields as "duel", then its foes out so far and its fled flag)
	if (IsObject(PzDuelNow) && PzDuelNow.result = "")
		t .= "duel" SubStr(PzJLine(PzDuelNow), 6) "|" V1N(PzDuelNow.outs) "|" (PzDuelNow.fled ? 1 : 0) "`r`n"
	PzWriteFile(PzJFile, t)
	}
PzJLoad()
	{
	global PzJ, PzDuelNow
	t := PzReadFile(PzJFile)
	if (t = "")
		return
	for i, jl in PzLines(t)
		{
		f := StrSplit(jl.t, "|")
		if (f.Length < 3 || !RegExMatch(f[2], "^\d{14}$"))
			continue
		try
			age := DateDiff(A_Now, f[2], "Seconds")
		catch
			continue
		if (age < 0 || age > 1800)
			continue
		;(the duel that was under way at a restart - begun under 15 minutes ago: open again, its end lines close it)
		if (f[1] = "duel")
			{
			if (f.Length >= 13 && age <= 900)
				PzDuelNow := V1Obj({kind: "fight", at: A_TickCount - age * 1000, time: f[2], zone: f[3], foes: f[9] = "" ? [] : StrSplit(f[9], "+"), names: []
					, outs: V1N(PzNumOf(f[12])), x: PzNumOf(f[4]), y: PzNumOf(f[5]), z: PzNumOf(f[6]), who: f[7], result: "", duel: f[11], fled: f[13] = 1 ? 1 : 0, endAt: 0})
			continue
			}
		e := V1Obj({kind: f[1], time: f[2], at: A_TickCount - age * 1000, zone: f[3]})
		if (e.kind = "fight" && f.Length >= 11)
			e.x := PzNumOf(f[4]), e.y := PzNumOf(f[5]), e.z := PzNumOf(f[6]), e.who := f[7], e.result := f[8], e.foes := f[9] = "" ? [] : StrSplit(f[9], "+")
				, e.names := f[10] = "" ? [] : StrSplit(f[10], "+"), e.duel := f[11]
		else if ((e.kind = "x" || e.kind = "talk") && f.Length >= 17)
			e.x := PzNumOf(f[4]), e.y := PzNumOf(f[5]), e.z := PzNumOf(f[6]), e.who := f[7], e.dest := f[8], e.verb := f[9], e.crown := f[10]
				, e.tname := f[11], e.ttpl := f[12], e.tkind := f[13], e.tx := PzNumOf(f[14]), e.ty := PzNumOf(f[15]), e.tz := PzNumOf(f[16]), e.tquest := f[17]
		else if (e.kind != "goal" && e.kind != "zone")
			continue
		PzJ.Push(e)
		}
	}

;The X key (a pass-through hotkey, ~*x: your X goes to the game as it is; the bot's own presses never come here): the dungeon
;recorder's X, and an X noted for the tick - nothing more in the hotkey's thread
PzXKey(ThisHotkey := "", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel - the dungeon recorder's X sets it)
	if (!PuzzleReady())
		return
	if (DgRecording && V1IsFunc("DgRecX"))
		%"DgRecX"%.Call()
	if (GameActive())
		PzXPend.Push(A_TickCount)
	}

;X presses (the tick): each, half a second on, into the journal - only with a prompt in reach (the game's log) or read in the 3 s
;before it, and not one of more than 3 in 2 s (typing in chat): where, the prompt, the nearest thing within 400
PzXTick()
	{
	global PzXRecent
	now := A_TickCount
	while (PzXPend.Length && now - PzXPend[1] >= 500)
		{
		at := PzXPend.RemoveAt(1)
		PzXRecent.Push(at)
		while (PzXRecent.Length && now - PzXRecent[1] > 5000)
			PzXRecent.RemoveAt(1)
		nx := 0
		for i, t in PzXRecent
			nx += (t >= at - 2000 && t <= at + 500) ? 1 : 0
		for i, t in PzXPend
			nx += (t >= at - 2000 && t <= at + 500) ? 1 : 0
		if (nx > 3)
			continue
		PzXEntry(at)
		}
	}
PzXEntry(at)
	{
	pr := PzInter.prompt
	if (!(PzInter.open || (IsObject(pr) && at - pr.at <= 3000 && pr.at <= at + 500)))
		return
	pos := PzPosQuiet(400)
	if (!IsObject(pos))
		return
	sq := PzSaveQuiet()
	its := NavItems("", false, 1500)
	PzRestoreQuiet(sq)
	best := ""
	if (IsObject(its))
		for i, t in its
			if (PzXY(t) && PzD(t.x, t.y, pos.x, pos.y) <= 400 && (!IsObject(best) || PzD(t.x, t.y, pos.x, pos.y) < PzD(best.x, best.y, pos.x, pos.y)))
				best := t
	e := V1Obj({kind: "x", at: at, time: PzNow(), zone: pos.zone, x: pos.x, y: pos.y, z: pos.z, dest: IsObject(pr) ? pr.dest : ""
		, verb: IsObject(pr) ? pr.verb : "", crown: IsObject(pr) ? pr.crown : 0, tname: "", ttpl: "", tkind: "", tx: "", ty: "", tz: "", tquest: 0, who: "you"})
	if (IsObject(best))
		e.tname := best.name, e.ttpl := best.template, e.tkind := best.kind, e.tx := best.x, e.ty := best.y, e.tz := best.z, e.tquest := best.quest
	if (e.tkind = "npc" || RegExMatch(e.verb, "i)^(talk|speak)"))
		e.kind := "talk"
	PzJournal(e)
	}

;A prompt come into reach by the game's log while you're in control: read once (the walker's prompt state put back) - never while the
;bot drives (the walker's own read could be mid-run)
PzPromptTick()
	{
	if (!PzInter.want)
		return
	if (A_TickCount - PzInter.openAt > 5000)
		{
		PzInter.want := 0
		return
		}
	if (!PzPlayerControl())
		return
	PzInter.want := 0
	sq := PzSaveQuiet()
	p := InteractPrompt()
	pr := V1Obj({kind: p, dest: WkPromptDest, verb: WkPromptVerb, text: WkPromptText, crown: RegExMatch(WkPromptText, "i)cr[o0]wn") ? 1 : 0, at: A_TickCount})
	PzRestoreQuiet(sq)
	if (p != "")
		PzInter.prompt := pr
	}

;The evidence's watch (the tick): a stop the wizard got well past since (300 nearer the goal than there) is forgotten
PzEvTick()
	{
	global PzEv
	if (!PzEv.Length || !PzXY(WkNavObj))
		return
	ev := PzEv[PzEv.Length]
	if (A_TickCount - ev.at > 360000)
		{
		PzEv := []
		return
		}
	if (WkNavObj.zone != ev.zone || (ev.goalid != "" && WkNavObj.goalid != "" && WkNavObj.goalid != ev.goalid) || !V1IsNum(ev.tx) || !V1IsNum(ev.r))
		return
	if (PzD(WkNavObj.x, WkNavObj.y, ev.tx, ev.ty) < ev.r - 300)
		PzEv := []
	}

;Every half second (a timer): X presses, a prompt to read, the game's log while the bot's off (the main loop doesn't read it
;then), the evidence's watch, the recording, the hold. Never a box: a failure is logged and the tick goes on
PzTick(*)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	static busy := 0
	if (!PuzzleReady() || busy)
		return
	busy := 1
	try
		{
		PzDlgNote()
		if (!BotOn && V1IsFunc("BattleLogRead"))
			%"BattleLogRead"%.Call()
		PzPromptTick()
		PzXTick()
		if (!IsObject(PzRun) && !IsObject(PzHeld))
			PzEvTick()
		PzRecTick()
		PzHoldTick()
		}
	catch as e
		PzSay("tick", "a tick failed (" e.Message " - " e.What " line " e.Line ") - carried on", 60000)
	busy := 0
	}

;---- the recording ----

;A notice the walker gave (WalkNotify - stuck, collect, wait, puzzle): what you do now is recorded, if nothing is yet - at the
;spot of a block known here (the hold, the walker's stops), else for the goal
PuzzleNoticed(kind, title)
	{
	try
		return PzNoticedDo(kind, title)
	catch as e
		{
		PzFail("a notice", e)
		return ""
		}
	}
PzNoticedDo(kind, title)
	{
	if (!PuzzleReady() || !PuzzleLearnOn() || IsObject(PzRec))
		return
	if (kind != "stuck" && kind != "collect" && kind != "wait" && kind != "puzzle")
		return
	nw := WkNavObj
	if (!PzXY(nw) || nw.zone = "")
		return
	if (IsObject(PzHeld) && PzHeld.zone = nw.zone)
		{
		PzRecStart("spot", "a notice: " title, PzHeld)
		return
		}
	ev := ""
	for i, e in PzEv
		if (e.zone = nw.zone && A_TickCount - e.at <= 360000)
			ev := e
	if (IsObject(ev))
		{
		wd := PzDir(ev)
		door := PzDoorNear(ev, wd)
		bpx := IsObject(door) ? door.x - wd.dx * 150 : ev.x, bpy := IsObject(door) ? door.y - wd.dy * 150 : ev.y
		PzRecStart("spot", "a notice: " title, V1Obj({zone: ev.zone, x: bpx, y: bpy, z: ev.z, dx: wd.dx, dy: wd.dy, kind: ev.kind, door: door}))
		return
		}
	PzRecStart("goal", "a notice: " title)
	}

;The recording starts (kind spot: at s's stop - {zone, x, y, z, dx, dy, kind, door}; goal: for the goal, where the wizard is);
;the journal's fights and X's near it since the zone was entered come in at once (you may have started before the notice)
PzRecStart(kind, why, s := "")
	{
	global PzRec
	if (!PuzzleLearnOn() || IsObject(PzRec))
		return
	nw := IsObject(s) ? s : WkNavObj
	if (!PzXY(nw) || nw.zone = "")
		return
	door := IsObject(s) ? s.door : ""
	rec := V1Obj({kind: kind, why: why, zone: nw.zone, x: nw.x, y: nw.y, z: nw.z, dx: IsObject(s) ? s.dx : 0, dy: IsObject(s) ? s.dy : 0
		, spotKind: IsObject(s) ? s.kind : "", door: IsObject(door) ? door.name : "", doorGid: IsObject(door) ? door.gid : ""
		, doorSrc: IsObject(door) ? door.src : "", doorX: IsObject(door) ? door.x : "", doorY: IsObject(door) ? door.y : ""
		, goalid: IsObject(WkNavObj) ? WkNavObj.goalid : "", goal: PzGoalLetters(WkGoalLine), line: WkGoalLine, quest: PzQuest()
		, start: PzNow(), startAt: A_TickCount, steps: [], walks: [], tickAt: 0, goalAt: 0, gkey: "", awayAt: 0, openAt: 0, missAt: 0, missGid: ""
		, doorAt: 0, check: 0, run: IsObject(PzRun) ? 1 : 0, pulled: 0, shut: 0, byRun: 0, mems: PzMemDoors(door)})
	;(the door's near memory doors too - not kept by a restart: the door alone then, as before)
	rec.others := []
	for i, d in rec.mems
		if (i > 1 || d.gid != rec.doorGid)
			rec.others.Push(d)
	;(their states now - kept already when a run began - are what "changed" is measured from, not the zone file's start: a trigger
	;can change a gate's state as the zone begins)
	PzStateKeep(door)
	since := A_TickCount - 1800000
	for i, e in PzJ
		if (e.kind = "zone" && e.zone = rec.zone && e.at > since)
			since := e.at
	pulled := 0
	for i, e in PzJ
		if (e.at >= since && e.zone = rec.zone && (e.kind = "fight" || e.kind = "x" || e.kind = "talk") && PzXY(e)
			&& PzD(e.x, e.y, rec.x, rec.y) <= PzGuardR)
			rec.steps.Push(e), pulled += 1
	;(the first pulled steps came from the journal - from before the recording: the bot's own among them are no part of a solve)
	rec.pulled := pulled
	PzRec := rec
	;(not a run's: its reads never named this zone's mobs)
	if (!rec.run)
		PzTplFill(rec, true)
	PzRecWrite()
	PzLog("recording what " (kind = "spot" ? "gets past " Round(rec.x) ", " Round(rec.y) : "moves '" rec.line "' on") " (" rec.zone ") - " why
		. (pulled ? " (" pulled " from the journal already)" : ""))
	}

;The recording's file: the entry's header (puzzles.txt's form), its rec line, the steps and walked points so far - written whole at
;the start, and again when the way's found still shut (PzRecShut: the walks too, else that rewrite lost them for a restart)
PzRecWrite()
	{
	rec := PzRec
	t := "; Wiz-Maxxing - a recording under way (Puzzle.ahk) - a restart carries on with it; deleted when it's saved or dropped`r`n"
		. PzHeadLine(PzRecEntry(rec)) "`r`n"
		. "rec|" rec.start "|" PzCell(rec.why) "|" rec.goalid "|" rec.doorGid "|" rec.doorSrc "|" PzF1(rec.doorX) "|" PzF1(rec.doorY) "|" rec.spotKind "|" rec.run
		. "|" V1N(rec.pulled) "|" V1N(rec.shut) "`r`n"
	for i, e in rec.steps
		t .= PzRecLine(e) "`r`n"
	for i, w in rec.walks
		t .= PzRecLine(w) "`r`n"
	PzWriteFile(PzRecFile, t)
	}
;A journal entry as a recording's line (a step line; the fight's result after it)
PzRecLine(e)
	{
	if (e.kind = "fight")
		return "fight|" PzCell(PzJoin(e.foes, "+")) "|" PzCell(PzJoin(e.names, "+")) "|" PzF1(e.x) "|" PzF1(e.y) "|" PzF1(e.z) "|" e.who "|" e.result
	if (e.kind = "x" || e.kind = "talk")
		return e.kind "|" PzCell(WalkLetters(e.dest)) "|" PzCell(e.ttpl) "|" PzCell(e.tname) "|" e.tkind "|" PzF1(V1IsNum(e.tx) ? e.tx : e.x)
			. "|" PzF1(V1IsNum(e.ty) ? e.ty : e.y) "|" PzF1(V1IsNum(e.tz) ? e.tz : e.z) "|" e.who "|" PzCell(e.verb) "|" e.crown "|" e.tquest
	if (e.kind = "walk")
		return "walk|" PzF1(e.x) "|" PzF1(e.y) "|" PzF1(e.z)
	return ""
	}

;A recording under way at the start (a restart): carried on if under 45 minutes old (its zone and goal checked at the first reading)
PzRecResume()
	{
	global PzRec
	t := PzReadFile(PzRecFile)
	if (t = "")
		return
	lines := PzLines(t)
	head := "", recL := "", steps := []
	for i, rl in lines
		{
		if (SubStr(rl.t, 1, 7) = "puzzle|")
			head := rl.t
		else if (SubStr(rl.t, 1, 4) = "rec|")
			recL := rl.t
		else if (RegExMatch(rl.t, "^(fight|x|talk|walk)\|"))
			steps.Push(rl.t)
		}
	f := StrSplit(recL, "|")
	age := ""
	if (f.Length >= 2 && RegExMatch(f[2], "^\d{14}$"))
		try
			age := DateDiff(A_Now, f[2], "Seconds")
	e := head != "" ? PzEntryOf(V1Obj({raw: [V1Obj({t: head, eol: ""})]}), true) : ""
	if (!IsObject(e) || age = "" || age < 0 || age * 1000 > PzRecCap)
		{
		PzLog("an old recording dropped" (age != "" ? " (" Round(age / 60) " minutes old)" : ""))
		V1Do(FileDelete, PzRecFile)
		return
		}
	rec := V1Obj({kind: e.key, why: V1At(f, 3), zone: e.zone, x: e.x, y: e.y, z: e.z, dx: V1N(e.dx), dy: V1N(e.dy), spotKind: V1At(f, 9)
		, door: e.door, doorGid: V1At(f, 5), doorSrc: V1At(f, 6), doorX: PzNumOf(V1At(f, 7)), doorY: PzNumOf(V1At(f, 8))
		, goalid: V1At(f, 4), goal: e.goal, line: e.line, quest: e.quest, start: f[2], startAt: A_TickCount - age * 1000, steps: [], walks: []
		, tickAt: 0, goalAt: 0, gkey: "", awayAt: 0, openAt: 0, missAt: 0, missGid: "", doorAt: 0, check: 1, run: V1At(f, 10) = 1 ? 1 : 0
		, pulled: V1N(PzNumOf(V1At(f, 11))), shut: V1N(PzNumOf(V1At(f, 12))), byRun: 0})
	for i, sl in steps
		{
		g := StrSplit(sl, "|")
		if (g[1] = "fight" && g.Length >= 7)
			rec.steps.Push(V1Obj({kind: "fight", at: A_TickCount, foes: g[2] = "" ? [] : StrSplit(g[2], "+"), names: g[3] = "" ? [] : StrSplit(g[3], "+")
				, x: PzNumOf(g[4]), y: PzNumOf(g[5]), z: PzNumOf(g[6]), who: g[7], result: V1At(g, 8), zone: rec.zone}))
		else if ((g[1] = "x" || g[1] = "talk") && g.Length >= 9)
			rec.steps.Push(V1Obj({kind: g[1], at: A_TickCount, dest: g[2], ttpl: g[3], tname: g[4], tkind: g[5], tx: PzNumOf(g[6]), ty: PzNumOf(g[7])
				, tz: PzNumOf(g[8]), x: PzNumOf(g[6]), y: PzNumOf(g[7]), z: PzNumOf(g[8]), who: g[9], verb: V1At(g, 10), crown: V1At(g, 11) = 1 ? 1 : 0
				, tquest: V1At(g, 12) = 1 ? 1 : 0, zone: rec.zone}))
		else if (g[1] = "walk" && g.Length >= 4)
			rec.walks.Push(V1Obj({kind: "walk", at: A_TickCount, x: PzNumOf(g[2]), y: PzNumOf(g[3]), z: PzNumOf(g[4])}))
		}
	;(the door's gid: a new instance gives it a new one - its name and place stay: PzRecTick looks for it by those too)
	PzRec := rec
	PzLog("a recording carried on after a restart (" Round(age / 60) " minutes old, " rec.steps.Length " steps so far)")
	}

;A journal entry while recording: a step (in the recording's zone), or the goal moving on
PzRecOnEntry(e)
	{
	rec := PzRec
	if (!IsObject(rec))
		return
	if (e.kind = "goal")
		{
		PzRecGoalMoved("the goal moved on (the game's log)")
		return
		}
	if (e.kind != "fight" && e.kind != "x" && e.kind != "talk")
		return
	if (e.zone != "" && e.zone != rec.zone)
		return
	;(a fight with no place - no "Local Player Entering Combat at" for its duel: another player's battle nearby, which the game logs
	;too - isn't yours: saved, it was a step line the bot can't read, as PzRecStart's pulled ones need a place too)
	if (e.kind = "fight" && !PzXY(e))
		return
	rec.steps.Push(e)
	PzAppend(PzRecLine(e) "`r`n", PzRecFile)
	}
;The way found still shut (PzShut): the bot's steps recorded up to now didn't open it - a run's recording at r's stop keeps how
;many there were then (its rec line - a restart keeps it), and PzSolution leaves them out
PzRecShut(r)
	{
	rec := PzRec
	if (!IsObject(rec) || !rec.run || rec.kind != "spot" || rec.zone != r.zone || rec.shut = rec.steps.Length)
		return
	rec.shut := rec.steps.Length
	PzRecWrite()
	}
;(a line added to a file, no error if it can't be)
PzAppend(text, path)
	{
	try
		FileAppend(text, path, "UTF-8-RAW")
	}

;The goal moved on: a goal's recording is saved; a spot's only once the way past it was walked (else dropped)
PzRecGoalMoved(why)
	{
	rec := PzRec
	if (!IsObject(rec))
		return
	if (rec.kind = "goal" || rec.openAt)
		PzRecEnd(true, why)
	else
		PzRecEnd(false, why ", the way past " Round(rec.x) ", " Round(rec.y) " was never walked")
	}

;A walked point while you're in control (every 300 units, 200 at most) - a walk route's
PzRecWalk(rec, pos)
	{
	if (rec.walks.Length >= 200)
		return
	if (rec.walks.Length && PzD(pos.x, pos.y, rec.walks[rec.walks.Length].x, rec.walks[rec.walks.Length].y) < 300)
		return
	w := V1Obj({kind: "walk", at: A_TickCount, x: pos.x, y: pos.y, z: pos.z})
	rec.walks.Push(w)
	PzAppend(PzRecLine(w) "`r`n", PzRecFile)
	}

;The recording's watch, every second (the tick): past the stop / the door gone / through the way out - saved; out of the zone 10
;minutes, 45 minutes in all - dropped; the goal moving on (every 3 s by the game's memory)
PzRecTick()
	{
	rec := PzRec
	if (!IsObject(rec))
		return
	now := A_TickCount
	if (now - rec.tickAt < 1000)
		return
	rec.tickAt := now
	if (!PuzzleLearnOn())
		{
		PzRecEnd(false, "puzzlelearn is off")
		return
		}
	if (now - rec.startAt > PzRecCap)
		{
		PzRecEnd(false, "45 minutes and the way never opened")
		return
		}
	;(a run under way ends it itself - its check is the one that counts)
	running := IsObject(PzRun)
	pos := PzPosQuiet(300)
	if (IsObject(pos) && pos.zone != "")
		{
		if (rec.check)
			{
			rec.check := 0
			if (pos.zone != rec.zone && !(rec.goalid != "" && pos.goalid = rec.goalid))
				{
				PzRecEnd(false, "an old recording dropped - another zone and goal now")
				return
				}
			}
		if (pos.zone = rec.zone)
			{
			rec.awayAt := 0
			if (!running && rec.kind = "spot" && rec.spotKind != "door" && PzPast(rec, pos))
				{
				rec.openAt := rec.openAt ? rec.openAt : now
				PzRecEnd(true, "past the block")
				return
				}
			if (PzPlayerControl())
				PzRecWalk(rec, pos)
			}
		else
			{
			if (!running && rec.kind = "spot" && rec.spotKind = "door")
				{
				rec.openAt := now
				PzRecEnd(true, "through the way out")
				return
				}
			if (!rec.awayAt)
				rec.awayAt := now
			else if (now - rec.awayAt > PzAwayCap)
				{
				PzRecEnd(false, "out of the zone for 10 minutes")
				return
				}
			}
		}
	if (!running && rec.kind = "spot" && rec.doorSrc = "mem" && rec.door != "" && now - rec.doorAt >= 3000 && IsObject(pos) && pos.zone = rec.zone)
		{
		rec.doorAt := now
		sq := PzSaveQuiet()
		bl := PzBlockers(true)
		PzRestoreQuiet(sq)
		if (IsObject(bl))
			{
			;(the door by its gid, else - a new instance: new gids, none of its way's doors there by theirs - by its name within 300 of
			;its spot: PzBlockerOf. rec.mems "" after a restart: by its name and place whenever its gid is missing, as before)
			there := IsObject(PzBlockerOf(bl, V1Obj({name: rec.door, gid: rec.doorGid, x: rec.doorX, y: rec.doorY}), rec.mems))
			;(a near memory door gone counts too - a gate's collision goes while its model stays; each found as the door is. The miss
			;time is the missing one's: another missing starts its own 1.5 s)
			goneO := there && IsObject(rec.others) ? PzGoneOf(rec.others, bl, rec.mems) : ""
			missK := !there ? "door" : IsObject(goneO) ? goneO.gid : ""
			if (missK = "")
				rec.missAt := 0
			else if (!rec.missAt || rec.missGid != missK)
				rec.missAt := now, rec.missGid := missK
			else if (now - rec.missAt >= 1500)
				{
				gName := IsObject(goneO) ? goneO.name : rec.door, gx := IsObject(goneO) ? goneO.x : rec.doorX, gy := IsObject(goneO) ? goneO.y : rec.doorY
				if (!V1IsNum(gx) || !V1IsNum(gy) || PzD(pos.x, pos.y, gx, gy) <= 6000)
					{
					rec.openAt := rec.missAt
					PzRecEnd(true, gName " gone (the game's memory)")
					return
					}
				}
			;(puzzlestate on: a door's state changed is the way opening; off: said only)
			moved := there && !IsObject(goneO) && IsObject(rec.mems) ? PzStateMoved(rec.mems, bl) : ""
			if (moved != "")
				{
				if (PzStateOn())
					{
					rec.openAt := now
					PzRecEnd(true, moved " (the game's memory)")
					return
					}
				PzSay("recstate|" moved, "a door's state changed - " moved " (the game's memory; not acted on: puzzlestate is off)", 60000)
				}
			}
		}
	if (now - rec.goalAt >= 3000)
		{
		rec.goalAt := now
		sq := PzSaveQuiet()
		g := NavGoal(400)
		PzRestoreQuiet(sq)
		if (IsObject(g) && g.goalid != "")
			{
			key := g.goalid "|" V1At(g, "count") "|" g.status
			if (rec.gkey = "")
				rec.gkey := key
			else if (key != rec.gkey && !running)
				PzRecGoalMoved("the goal moved on")
			}
		}
	}

;The recording over: save (the steps kept - PzSolution - into learned\puzzles.txt), or dropped (why)
PzRecEnd(save, why)
	{
	global PzRec
	rec := PzRec
	if (!IsObject(rec))
		return
	PzRec := ""
	if (!save)
		{
		V1Do(FileDelete, PzRecFile)
		PzLog("the recording dropped - " why)
		return
		}
	PzTplFill(rec)
	e := PzSolution(rec)
	if (!IsObject(e))
		{
		V1Do(FileDelete, PzRecFile)
		PzLog((rec.kind = "spot" ? "past " Round(rec.x) ", " Round(rec.y) : "the goal moved on") " (" why ") - you walked through, nothing to learn")
		return
		}
	PzLearnedAdd(e)
	PuzzleSave()
	where := e.key = "spot" ? "how to get past " Round(e.x) ", " Round(e.y) " in " e.zone : "how to get '" e.line "' moving in " e.zone
	PzLog("learned from " (e.from = "you" ? "you" : "its own tries") " " where ": " PzStepsSay(e.steps) " - saved (learned\puzzles.txt) (" why ")")
	TrayTip("Learned " where " - next time the bot does it itself.", "Wizard101 bot", 1)
	PuzzleLoad()
	V1Do(FileDelete, PzRecFile)
	}

;What a recording learned: its steps up to the moment the way opened - fights won (not the goal's own mob, not a boss the zone's
;triggers don't name), X's and talks (not with Crowns, not a door's / teleporter's / shop's, not the goal's own thing); only walking:
;a walk route if your path strayed over 500 off the straight way. An entry, or "" nothing to learn
PzSolution(rec)
	{
	steps := [], you := 0
	;(the bot's tries the way was found still shut after are left out only if a step of yours came after them - else, opened by
	;itself or at a held look (a gate that opens late, a dialogue after the battle the check didn't wait out), the bot's tries are
	;all that could have opened it: kept, as before PzRecShut. After the last of those tries (lastBot), not after rec.shut: a
	;still-shut look in the hold moves rec.shut past your own steps too. And only a step of yours this keeps (PzStepKept) - a
	;fight lost or fled, a Crown X, an enter or teleport X opened nothing)
	shut := 0
	if (rec.run && !rec.byRun && V1N(rec.shut))
		{
		lastBot := 0
		for i, e in rec.steps
			if (i <= V1N(rec.shut) && e.who = "bot")
				lastBot := i
		for i, e in rec.steps
			if (i > lastBot && e.who = "you" && (!rec.openAt || e.at <= rec.openAt) && PzStepKept(e, rec))
				{
				shut := V1N(rec.shut)
				break
				}
		}
	for i, e in rec.steps
		{
		if (rec.openAt && e.at > rec.openAt)
			continue
		if (!rec.run && e.who = "bot")
			continue
		;(a run's recording: the bot's own fights and X's from before it - pulled in from the journal, mobs fought on the way in - are
		;no part of the way past; yours are: you may have begun before the block was seen. Nor - when it wasn't the run's own tries
		;that opened it - are the bot's tries the way was found still shut after (PzRecShut): a failed run's 4 camps and levers kept
		;ahead of your step made its replay fight its battle cap before it got to yours)
		if (rec.run && e.who = "bot" && (i <= V1N(rec.pulled) || i <= shut))
			continue
		if (e.kind = "fight")
			{
			;(no place: a recording from before PzRecOnEntry left those out - not a step the bot can read)
			if (!PzXY(e))
				continue
			if (e.result != "won" && e.result != "won?" && e.result != "")
				continue
			if (PzFightIsGoal(e, rec))
				continue
			names := []
			for j, t in e.foes
				names.Push((IsObject(e.names) && j <= e.names.Length && e.names[j] != "") ? e.names[j] : PzTplName(t))
			steps.Push(V1Obj({kind: "fight", tpls: e.foes, names: names, x: e.x, y: e.y, z: e.z, who: e.who}))
			}
		else if (e.kind = "x" || e.kind = "talk")
			{
			if (e.crown || RegExMatch(e.verb, "i)^(enter|teleport|shop|buy|sell)") || e.tquest = 1 || InStr(WalkLetters(e.dest), "TELEPORT"))
				continue
			tx := V1IsNum(e.tx) ? e.tx : e.x, ty := V1IsNum(e.ty) ? e.ty : e.y, tz := V1IsNum(e.tz) ? e.tz : e.z
			if (e.kind = "talk")
				steps.Push(V1Obj({kind: "talk", name: e.tname, template: e.ttpl, x: tx, y: ty, z: tz, who: e.who}))
			else
				steps.Push(V1Obj({kind: "x", plet: WalkLetters(e.dest), template: e.ttpl, name: e.tname, tkind: e.tkind, x: tx, y: ty, z: tz, who: e.who}))
			}
		else
			continue
		you += e.who = "you" ? 1 : 0
		}
	if (!steps.Length && rec.kind = "spot")
		{
		;(only walking: from the last point near the stop to past it - over 500 off the straight way: a walk route)
		pts := [], far := 0, from := 0
		for i, w in rec.walks
			if (PzD(w.x, w.y, rec.x, rec.y) <= 600)
				from := i
		if (from)
			for i, w in rec.walks
				if (i >= from)
					{
					pts.Push(V1Obj({kind: "walk", x: w.x, y: w.y, z: w.z}))
					far := Max(far, Abs((w.x - rec.x) * rec.dy - (w.y - rec.y) * rec.dx))
					}
		if (far > 500 && pts.Length >= 2)
			steps := pts, you := 1
		}
	if (!steps.Length)
		return ""
	e := PzRecEntry(rec)
	e.steps := steps, e.from := you ? "you" : "bot", e.learned := PzStamp(), e.dirty := 1, e.fresh := 1
	return e
	}

;Would PzSolution keep recorded step e (of rec) as a step of the way past: a fight won (won? or no result) with a place, not the
;goal's own mob nor a boss the zone's triggers don't name (PzFightIsGoal); an X or talk with no Crowns on it, not an enter /
;teleport / shop one, not the quest's own thing's nor a teleporter's - its loop's own tests
PzStepKept(e, rec)
	{
	if (e.kind = "fight")
		return PzXY(e) && (e.result = "won" || e.result = "won?" || e.result = "") && !PzFightIsGoal(e, rec)
	if (e.kind = "x" || e.kind = "talk")
		return !(e.crown || RegExMatch(e.verb, "i)^(enter|teleport|shop|buy|sell)") || e.tquest = 1 || InStr(WalkLetters(e.dest), "TELEPORT"))
	return false
	}

;Is a recorded fight the goal's own (its mob in the goal's letters, a template seen as the quest's) or a boss - the bot's own boss
;fight never a step (it never picks one), yours only when the zone's triggers name that boss (you showed it opens the way)?
PzFightIsGoal(e, rec)
	{
	for i, t in e.foes
		{
		nm := (IsObject(e.names) && i <= e.names.Length) ? e.names[i] : ""
		nm := nm != "" ? nm : PzTplName(t)
		k := WalkLetters(nm)
		if (StrLen(k) >= 4 && InStr(rec.goal, k))
			return true
		if (PzTpl.Has(t) && PzTpl[t].quest = 1)
			return true
		if ((RegExMatch(t, "i)boss") || (PzTpl.Has(t) && PzTpl[t].boss = 1)) && !(e.who = "you" && PzKillHint(rec.zone, t)))
			return true
		}
	return false
	}

;A recording's entry (no steps yet)
PzRecEntry(rec)
	{
	return V1Obj({zone: rec.zone, key: rec.kind, x: rec.x, y: rec.y, z: rec.z, dx: rec.dx, dy: rec.dy, goal: rec.goal, quest: rec.quest
		, line: rec.line, door: rec.door, from: "you", learned: PzStamp(), ok: 0, failed: 0, last: "", steps: [], bad: [], block: "", src: "learned"})
	}

PzStepsSay(steps)
	{
	nF := 0, nX := 0, nT := 0, nW := 0
	for i, st in steps
		nF += st.kind = "fight", nX += st.kind = "x", nT += st.kind = "talk", nW += st.kind = "walk"
	p := []
	if (nF)
		p.Push(nF " fight" (nF = 1 ? "" : "s"))
	if (nX)
		p.Push(nX " X" (nX = 1 ? "" : "'s"))
	if (nT)
		p.Push(nT " talk" (nT = 1 ? "" : "s"))
	if (nW)
		p.Push("a walk route (" nW " points)")
	return p.Length ? PzJoin(p, ", ") : "nothing"
	}

;---- learned\puzzles.txt ----

;Text a file holds ("" none or unreadable), UTF-8 (its BOM, if it has one, left out)
PzReadFile(path)
	{
	if (!FileExist(path))
		return ""
	try
		{
		f := FileOpen(path, "r", "UTF-8")
		t := f.Read()
		f.Close()
		;(a BOM read as text, if the file had one: the file's own - written back with it, PzFileBom)
		return SubStr(t, 1, 1) = Chr(0xFEFF) ? SubStr(t, 2) : t
		}
	catch
		return ""
	}
;Text into a file: a .tmp first, then moved over it (UTF-8, no BOM; the folder made if missing). True if done
PzWriteFile(path, text, bom := false)
	{
	SplitPath(path, , &fdir)
	try
		{
		if (!DirExist(fdir))
			DirCreate(fdir)
		tmp := path ".tmp"
		f := FileOpen(tmp, "w", bom ? "UTF-8" : "UTF-8-RAW")
		f.Write(text)
		f.Close()
		FileMove(tmp, path, 1)
		return true
		}
	catch as e
		{
		PzSay("write|" path, "couldn't write " path " (" e.Message ")", 600000)
		return false
		}
	}
;Has the file a UTF-8 BOM?
PzFileBom(path)
	{
	;(its raw bytes: FileOpen would skip the BOM by itself)
	try
		{
		b := FileRead(path, "RAW")
		return b.Size >= 3 && NumGet(b, 0, "UChar") = 239 && NumGet(b, 1, "UChar") = 187 && NumGet(b, 2, "UChar") = 191
		}
	catch
		return false
	}

;Lines as they are: [{t: the text, eol: its own line end - CRLF, LF or "" (the last line without one)}]
PzLines(text)
	{
	out := [], pos := 1, tl := StrLen(text)
	while (pos <= tl)
		{
		nl := InStr(text, "`n", true, pos)
		if (!nl)
			{
			out.Push(V1Obj({t: SubStr(text, pos), eol: ""}))
			break
			}
		lt := SubStr(text, pos, nl - pos), eol := "`n"
		if (SubStr(lt, -1) = "`r")
			lt := SubStr(lt, 1, -1), eol := "`r`n"
		out.Push(V1Obj({t: lt, eol: eol}))
		pos := nl + 1
		}
	return out
	}

;The file as blocks, in order: text (notes, blanks - written back as they are) and puzzles ("puzzle|" to "end" - a block with no end
;runs to the next puzzle| line or the file's end), each puzzle's entry read (one the bot can't read: "" - kept as it is, never used)
PzParse(text, from := "learned")
	{
	blocks := [], cur := ""
	for i, pl in PzLines(text)
		{
		if (SubStr(pl.t, 1, 7) = "puzzle|")
			{
			if (IsObject(cur) && cur.type = "p" && !cur.closed)
				cur.noend := 1
			cur := V1Obj({type: "p", raw: [pl], e: "", closed: 0, noend: 0})
			blocks.Push(cur)
			continue
			}
		if (IsObject(cur) && cur.type = "p" && !cur.closed)
			{
			cur.raw.Push(pl)
			if (Trim(pl.t) = "end")
				cur.closed := 1
			continue
			}
		if (!IsObject(cur) || cur.type != "t")
			{
			cur := V1Obj({type: "t", raw: []})
			blocks.Push(cur)
			}
		cur.raw.Push(pl)
		}
	if (IsObject(cur) && cur.type = "p" && !cur.closed)
		cur.noend := 1
	for i, b in blocks
		if (b.type = "p")
			{
			b.e := PzEntryOf(b)
			if (IsObject(b.e))
				b.e.src := from
			if (b.noend)
				PzSay("noend|" from "|" b.raw[1].t, "a puzzle in " (from = "seed" ? "puzzles_known.txt" : "puzzles.txt") " has no 'end' - read to the next puzzle: " SubStr(b.raw[1].t, 1, 80))
			}
	return blocks
	}

;A puzzle block's entry: its header's 17 fields, its steps (a line the bot can't read - an unknown kind, a field missing or too many:
;kept as it is, left out of the replay - said once). "" the header can't be read (quiet: no line said)
PzEntryOf(b, quiet := false)
	{
	h := StrSplit(b.raw[1].t, "|")
	bad := (h.Length != 17) ? "its first line has " h.Length " fields, not 17" : ""
	if (bad = "" && Trim(h[2]) = "")
		bad := "no zone"
	if (bad = "" && Trim(h[3]) != "spot" && Trim(h[3]) != "goal")
		bad := "neither spot nor goal"
	if (bad = "" && Trim(h[3]) = "spot" && (PzNumOf(h[4]) = "" || PzNumOf(h[5]) = ""))
		bad := "no spot"
	if (bad != "")
		{
		if (!quiet)
			PzSay("badhead|" b.raw[1].t, "a puzzle the bot can't read is left as it is (" bad "): " SubStr(b.raw[1].t, 1, 80))
		return ""
		}
	e := V1Obj({zone: Trim(h[2]), key: Trim(h[3]), x: PzNumOf(h[4]), y: PzNumOf(h[5]), z: PzNumOf(h[6]), dx: PzNumOf(h[7]), dy: PzNumOf(h[8])
		, goal: Trim(h[9]), quest: h[10], line: h[11], door: h[12], from: Trim(h[13]), learned: Trim(h[14]), ok: V1N(PzNumOf(h[15]))
		, failed: V1N(PzNumOf(h[16])), last: Trim(h[17]), steps: [], bad: [], block: b, src: "", dirty: 0, fresh: 0})
	Loop b.raw.Length - 1
		{
		sx := Trim(b.raw[A_Index + 1].t)
		if (sx = "" || SubStr(sx, 1, 1) = ";")
			continue
		if (sx = "end")
			break
		f := StrSplit(sx, "|"), k := f[1], st := ""
		if (k = "fight" && f.Length = 7)
			st := V1Obj({kind: "fight", tpls: StrSplit(f[2], "+"), names: StrSplit(f[3], "+"), x: PzNumOf(f[4]), y: PzNumOf(f[5]), z: PzNumOf(f[6]), who: Trim(f[7])})
		else if (k = "x" && f.Length = 9)
			st := V1Obj({kind: "x", plet: Trim(f[2]), template: Trim(f[3]), name: Trim(f[4]), tkind: Trim(f[5]), x: PzNumOf(f[6]), y: PzNumOf(f[7]), z: PzNumOf(f[8]), who: Trim(f[9])})
		else if (k = "talk" && f.Length = 7)
			st := V1Obj({kind: "talk", name: Trim(f[2]), template: Trim(f[3]), x: PzNumOf(f[4]), y: PzNumOf(f[5]), z: PzNumOf(f[6]), who: Trim(f[7])})
		else if (k = "walk" && f.Length = 4)
			st := V1Obj({kind: "walk", x: PzNumOf(f[2]), y: PzNumOf(f[3]), z: PzNumOf(f[4])})
		if (IsObject(st) && (st.kind = "fight" ? st.tpls.Length && st.tpls[1] != "" : true) && PzXY(st))
			e.steps.Push(st)
		else
			{
			e.bad.Push(sx)
			if (!quiet)
				PzSay("badstep|" sx, "a puzzle step the bot can't read is left as it is (not replayed): " SubStr(sx, 1, 80))
			}
		}
	return e
	}

;An entry's header line
PzHeadLine(e)
	{
	return "puzzle|" PzCell(e.zone) "|" e.key "|" PzF1(e.x) "|" PzF1(e.y) "|" PzF1(e.z) "|" PzF2(e.dx) "|" PzF2(e.dy) "|" PzCell(e.goal) "|" PzCell(e.quest)
		. "|" PzCell(e.line) "|" PzCell(e.door) "|" e.from "|" e.learned "|" e.ok "|" e.failed "|" e.last
	}
;A step's line
PzStepLine(s)
	{
	if (s.kind = "fight")
		return "fight|" PzCell(PzJoin(s.tpls, "+")) "|" PzCell(PzJoin(s.names, "+")) "|" PzF1(s.x) "|" PzF1(s.y) "|" PzF1(s.z) "|" s.who
	if (s.kind = "x")
		return "x|" PzCell(s.plet) "|" PzCell(s.template) "|" PzCell(s.name) "|" s.tkind "|" PzF1(s.x) "|" PzF1(s.y) "|" PzF1(s.z) "|" s.who
	if (s.kind = "talk")
		return "talk|" PzCell(s.name) "|" PzCell(s.template) "|" PzF1(s.x) "|" PzF1(s.y) "|" PzF1(s.z) "|" s.who
	return "walk|" PzF1(s.x) "|" PzF1(s.y) "|" PzF1(s.z)
	}
;An entry's whole block, as lines (CRLF)
PzFormat(e)
	{
	out := [V1Obj({t: PzHeadLine(e), eol: "`r`n"})]
	for i, st in e.steps
		out.Push(V1Obj({t: PzStepLine(st), eol: "`r`n"}))
	for i, st in e.bad
		out.Push(V1Obj({t: st, eol: "`r`n"}))
	out.Push(V1Obj({t: "end", eol: "`r`n"}))
	return out
	}

PzFileHead()
	{
	t := "; Wiz-Maxxing - puzzles: ways past a blocked spot (a gate, a door) or a goal that didn't move on, learned from you`r`n"
		. "; and from the bot's own tries. The bot does them itself next time - any character, any PC with this file. Kept by`r`n"
		. "; updates. Edit freely: a puzzle is a `"puzzle|`" line, its steps, then `"end`"; `; starts a note. A puzzle the bot can't`r`n"
		. "; read is left as it is. Positions are the zone's own (game units) - the same in every instance; ids are never kept.`r`n"
		. ";   puzzle|zone|key (spot / goal)|x|y|z|dir x|dir y|goal letters|quest title|goal line|door template|from (you / bot)|learned|ok|failed|last used`r`n"
		. ";   fight|mob templates (+)|names (+)|x|y|z|you / bot`r`n"
		. ";   x|prompt letters|thing template|thing name|kind|x|y|z|you / bot`r`n"
		. ";   talk|npc name|npc template|x|y|z|you / bot`r`n"
		. ";   walk|x|y|z`r`n"
		. ";   end`r`n"
	return t
	}

;The ways learned: learned\puzzles.txt (its blocks kept for writing back) and the seed (resources\puzzles_known.txt - one the learned
;file has for the same spot or goal left out)
PuzzleLoad()
	{
	global PzBlocks, PzLearned, PzFileText
	if (!PuzzleReady())
		return
	t := PzReadFile(PzFile)
	PzFileText := t
	PzBlocks := t != "" ? PzParse(t, "learned") : []
	PzLearned := []
	for i, b in PzBlocks
		if (b.type = "p" && IsObject(b.e))
			PzLearned.Push(b.e)
	st := PzReadFile(PzSeedFile)
	if (st != "")
		for i, b in PzParse(st, "seed")
			if (b.type = "p" && IsObject(b.e) && !PzShadowed(b.e))
				PzLearned.Push(b.e)
	}

;Has the learned file an entry for the same spot (the zone, within PzSpotR) or goal (the zone, the letters)?
PzShadowed(e)
	{
	for i, xe in PzLearned
		if (xe.src = "learned" && PzSameEntry(xe, e))
			return true
	return false
	}
PzSameEntry(a, b)
	{
	if (a.zone != b.zone || a.key != b.key)
		return false
	if (a.key = "goal")
		return a.goal = b.goal
	return PzD(a.x, a.y, b.x, b.y) <= PzSpotR
	}

;learned\puzzles.txt written back: text blocks as they were, puzzles as read unless changed (ok, failed, last used: the header only;
;new steps: the whole block). Nothing changed: not written at all
PuzzleSave()
	{
	global PzBlocks, PzFileText
	if (!PuzzleReady())
		return false
	changed := false
	for i, b in PzBlocks
		if (b.type = "p" && IsObject(b.e) && b.e.dirty)
			{
			changed := true
			if (b.e.fresh)
				b.raw := PzFormat(b.e)
			else
				b.raw[1] := V1Obj({t: PzHeadLine(b.e), eol: b.raw[1].eol != "" ? b.raw[1].eol : "`r`n"})
			b.e.dirty := 0, b.e.fresh := 0
			}
	if (!changed)
		return true
	t := ""
	for i, b in PzBlocks
		for j, pl in b.raw
			t .= pl.t pl.eol
	if (!PzWriteFile(PzFile, t, PzFileBom(PzFile)))
		return false
	PzFileText := t
	return true
	}

;learned\puzzles.txt changed since the bot last read or wrote it (you edited it - "Edit freely" - while the bot ran): read again,
;so the bot's change goes onto your edit and never writes the old copy back over it. True if it was read again
PzFreshen()
	{
	if (!PuzzleReady() || PzReadFile(PzFile) == PzFileText)
		return false
	PuzzleLoad()
	PzSay("edited", "learned\puzzles.txt changed since it was read (edited?) - read again, the bot's changes go onto it", 60000)
	return true
	}
;An entry as it is in the ways read now (the file read again since e was taken): the same kind (learned / seed), zone and spot or
;goal - the one whose first line is e's own first, else the first such - "" gone (you took it out)
PzRefind(e)
	{
	if (!IsObject(e) || PzIn(PzLearned, e))
		return e
	head := (IsObject(e.block) && IsObject(e.block.raw) && e.block.raw.Length) ? e.block.raw[1].t : ""
	best := ""
	for i, xe in PzLearned
		if (xe.src = e.src && PzSameEntry(xe, e))
			{
			if (head != "" && IsObject(xe.block) && xe.block.raw.Length && xe.block.raw[1].t == head)
				return xe
			if (!IsObject(best))
				best := xe
			}
	return best
	}

;A new way learned (3.5): the same zone and spot (or goal) as one there - its steps replaced when that one was set aside or the
;bot's own; else a second entry (the better by ok - failed is replayed first)
PzLearnedAdd(e)
	{
	global PzBlocks
	PzFreshen()
	if (!PzBlocks.Length)
		PzBlocks.Push(V1Obj({type: "t", raw: PzLines(PzFileHead())}))
	for i, b in PzBlocks
		if (b.type = "p" && IsObject(b.e) && PzSameEntry(b.e, e) && (PzSetAside(b.e) || b.e.from = "bot"))
			{
			b.e.steps := e.steps, b.e.bad := [], b.e.from := e.from, b.e.learned := e.learned, b.e.ok := 0, b.e.failed := 0, b.e.last := ""
			b.e.door := e.door, b.e.dx := e.dx, b.e.dy := e.dy, b.e.line := e.line, b.e.quest := e.quest, b.e.goal := e.goal
			b.e.dirty := 1, b.e.fresh := 1
			return
			}
	last := PzBlocks[PzBlocks.Length]
	if (last.raw.Length && last.raw[last.raw.Length].eol = "")
		last.raw[last.raw.Length].eol := "`r`n"
	nb := V1Obj({type: "p", raw: [], e: e, closed: 1, noend: 0})
	e.block := nb, e.src := "learned", e.dirty := 1, e.fresh := 1
	PzBlocks.Push(nb)
	}

;A learned entry's result: worked (ok + 1) or not (failed + 1), last used now - written (a seed entry: copied into the learned file)
PzLearnedResult(e, worked)
	{
	global PzBlocks
	if (!IsObject(e))
		return
	;(the file as it is now - an edit of yours kept - and the entry as it is in it)
	PzFreshen()
	e := PzRefind(e)
	if (!IsObject(e))
		{
		PzLog("the learned way isn't in learned\puzzles.txt any more (taken out?) - its " (worked ? "worked" : "failed") " count not kept")
		return
		}
	if (worked)
		e.ok += 1
	else
		e.failed += 1
	e.last := PzStamp()
	if (e.src = "seed")
		{
		c := V1Obj()
		for k, v in e
			c[k] := v
		c.src := "learned", c.fresh := 1
		PzLearnedAddCopy(c)
		PuzzleSave()
		;(the copy shadows the seed's from now on)
		PuzzleLoad()
		return
		}
	e.dirty := 1
	PuzzleSave()
	}
PzLearnedAddCopy(e)
	{
	global PzBlocks
	if (!PzBlocks.Length)
		PzBlocks.Push(V1Obj({type: "t", raw: PzLines(PzFileHead())}))
	last := PzBlocks[PzBlocks.Length]
	if (last.raw.Length && last.raw[last.raw.Length].eol = "")
		last.raw[last.raw.Length].eol := "`r`n"
	nb := V1Obj({type: "p", raw: [], e: e, closed: 1, noend: 0})
	e.block := nb, e.dirty := 1
	PzBlocks.Push(nb)
	}

;Set aside: failed 3 times and more than twice as often as it worked - kept in the file, not replayed
PzSetAside(e) => e.failed >= 3 && e.failed > e.ok * 2

;The learned ways for zone, spot p and goal letters (3.6): a spot entry - the same zone, its spot within 600 and 260 up or down; a
;goal entry - the same zone and letters. Same letters first, then ok - failed, then the newest; set-aside ones left out (said once
;a run). A recording from another zone is never used. any: the eligibility's look (nothing said)
PuzzleFind(zone, p, goalLetters, kind := "", any := false)
	{
	out := []
	if (!PuzzleReady() || !IsObject(PzLearned))
		return out
	for i, e in PzLearned
		{
		if (e.zone != zone || (kind != "" && e.key != kind))
			continue
		if (e.key = "spot")
			{
			if (!PzXY(p) || PzD(e.x, e.y, p.x, p.y) > PzSpotR || (V1IsNum(e.z) && V1IsNum(p.z) && Abs(e.z - p.z) > 260))
				continue
			}
		else if (e.goal = "" || e.goal != goalLetters)
			continue
		if (!e.steps.Length)
			continue
		if (PzSetAside(e))
			{
			if (!any)
				PzSay("aside|" e.zone "|" e.x "|" e.y "|" e.goal "|" (IsObject(PzRun) ? PzRun.startAt : 0), "learned puzzle at " PzRd(e.x) ", " PzRd(e.y) " (" e.zone ") set aside - it failed " e.failed " times")
			continue
			}
		e.pzSame := (goalLetters != "" && e.goal = goalLetters) ? 1 : 0
		out.Push(e)
		}
	return PzSort(out, (a, b) => (a.pzSame != b.pzSame) ? b.pzSame - a.pzSame : ((b.ok - b.failed) != (a.ok - a.failed)) ? (b.ok - b.failed) - (a.ok - a.failed) : StrCompare(b.learned, a.learned))
	}
