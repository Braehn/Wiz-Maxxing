; EnemySpells.ahk - what each enemy will likely cast this round, and defending first when their hits could kill the
; wizard. AHK v1.1, functions only; #Included by Autofarmer.ahk.
;
; Who's fighting and what each cast: the game's own log (Bin\WizardClient.log - read only, the file Reconnect.ahk reads
; too, RcLog). Each planning phase names every slot ("CombatPlanningP Subcircle 1", then "MINION
; CombatantDataControlSmall, name:Ahnic Strider" - slots 0-3 the enemies, 4-7 your side), and each round each caster's
; spell ("CombatResolver::ResolveCombatRound. Duel ID:.. Round:3 Caster:1 Spell:Dark Sprite" - None: it passed); a new
; "Duel N: MSG_CombatPhase(...)" number is a new battle. Each enemy cast is counted for its creature (the vision helper's
; /enemyseen - wiki\casts.json), so the odds sharpen with every battle.
;
; The odds (the helper's /enemies - vision\enemies.py): each creature's spells off the Fandom wiki, its pips estimated by
; the round, the casts so far. Each round: logged ("  enemy spells: ...") and shown on the dashboard (WHAT IT SEES:
; Threat). Defending (EnemyDefend): when the chance this round's enemy hits kill the wizard is defendat % or more and no
; hit in hand kills them all (the kill check runs first) - a heal, else Tower Shield, before anything else.

;The battle log: where it was read to, its first line (a new log: from the top), the battle (its duel number), each
;slot's name ({slot: name}), the slot a name line is for, the casts ([{round, slot, spell}]), the last round resolved,
;when it was last read
global BlPos, BlHead, BlDuel, BlNames, BlSub, BlCasts, BlRound, BlReadAt
;The battle's last phase by the log (kPhase_Planning: a round up for your cards; kPhase_Execution: the spells) and when
global BlPhase, BlPhaseAt
;Fled this round (MSG_CombatFlee - the bot or you): the removal from the battle that follows isn't a defeat
global BlFled
;The duel whose end was said (defeated, or taken out after a flee) - its MSG_CombatMatchResult not said again; cleared
;at each planning phase (a circle's duel number comes again for the next battle there - 2026-11-14 one three times)
global BlOutDuel
;Knockouts at one quest goal (KoNote): the goal (the walker's goal line, else the zone) and when each was (the last 3 hours)
global KoGoal, KoTimes
;Your own wizard's name: the one wizard on your side of a battle with no other (learned this run - party.ini [me] keeps
;the last for the next), and the character it's for (the game's log's CharID - another character logged in: not its)
global BlMe, BlMeChar
;Your own health as last read (OwnHealthLow): now, most, when, how many of its 4 reads agreed
global OwnHpCur, OwnHpMax, OwnHpAt, OwnHpVotes, OwnHpWin
;This round's prediction (EnemyDanger): the chance their hits kill the wizard (0-1, "" unknown), for the round
global EnemyLethal, EnemyLethalRound

;What the game's log has said since the last read - at most every 500 ms (force: now). The first read starts at its end:
;only what happens from now on (a battle going on is picked up at its next planning phase, which names every slot)
BattleLogRead(force := false)
	{
	global BlReadAt, BlHead, BlPos ; (v1 globals it sets)
	if (!force && BlReadAt && A_TickCount - BlReadAt < 500)
		return
	BlReadAt := A_TickCount
	if (RcLog = "" || !FileExist(RcLog))
		return
	try
		blFile := FileOpen(RcLog, "r", "CP0")
	catch
		blFile := ""  ; (v1: FileOpen gave 0 when it couldn't open the log - v2 throws)
	if (!IsObject(blFile))
		return
	blSize := blFile.Length
	blTop := blFile.Read(17)
	if (BlHead = "")
		{
		BlHead := blTop, BlPos := blSize
		blFile.Close()
		return
		}
	;(a new log - the game restarted: from its top)
	if (blTop != BlHead || blSize < BlPos)
		BlHead := blTop, BlPos := 0
	if (blSize - BlPos > 1048576)
		BlPos := blSize - 1048576
	if (blSize <= BlPos)
		{
		blFile.Close()
		return
		}
	blFile.Pos := BlPos
	blChunk := blFile.Read(blSize - BlPos)
	blFile.Close()
	;(a line still being written is read next time)
	blNl := InStr(blChunk, "`n", false, -1)
	if (!blNl)
		return
	blChunk := SubStr(blChunk, 1, blNl)
	BlPos += StrLen(blChunk)
	;(each line to Puzzle.ahk's journal too, first - duels, the goal moving on, zones, prompts in reach: looked up once a read)
	pzLine := V1IsFunc("PuzzleLogLine") ? %"PuzzleLogLine"% : ""
	Loop Parse, blChunk, "`n", "`r"
		{
		if (pzLine)
			pzLine.Call(A_LoopField)
		BattleLogLine(A_LoopField)
		}
	}

;A battle on by the game's log: a combat phase in the last minute and the spellbook (it shows only out of battle) not
;seen since - one whose round the bot hasn't seen yet counts (2026-10-23 17:22: its Pass drawn hovered, the walker took
;it for no arrow out of battle and pressed Escape: the game's menu over the round)
BattleLogInBattle()
	{
	return (BlPhaseAt && A_TickCount - BlPhaseAt < 60000 && BookSeenAt < BlPhaseAt) ? 1 : 0  ; (v1: && gave 1 or 0 - v2 an operand, "" here)
	}

;A round up for your cards by the game's log - its planning phase begun at least ms ago (and 90 s at most), in a battle
;(BattleLogInBattle)
BattleLogPlanning(ms)
	{
	return (BlPhase = "kPhase_Planning" && BlPhaseAt && A_TickCount - BlPhaseAt >= ms && A_TickCount - BlPhaseAt < 90000 && BookSeenAt < BlPhaseAt) ? 1 : 0  ; (v1: 1 or 0)
	}

;One line of the game's log, for the battle
BattleLogLine(blLine)
	{
	global BlFled, BlPhase, BlPhaseAt, BlDuel, BlNames, BlCasts, BlRound, BlSub, BlMe, BlMeChar ; (v1 globals it sets)
	global BlOutDuel ; (v2-only: the port tools don't know it)
	if (!InStr(blLine, "Combat") && !InStr(blLine, "Subcircle"))
		return
	if (InStr(blLine, "MSG_CombatFlee"))
		BlFled := 1
	;(out of the battle - fled, or defeated: no phase line follows. Taken out with no flee before it: defeated - the
	;game sends you to a safe spot; a won battle never takes you out. The dashboard counts it: Deaths)
	if (InStr(blLine, "MSG_CombatRemove(Local Player)"))
		{
		if (!BlFled && BlOutDuel != BlDuel)
			BattleDefeated("taken out of duel " BlDuel " without fleeing")
		BlPhase := "", BlPhaseAt := 0, BlFled := 0, BlOutDuel := BlDuel
		}
	;(defeated - the match's result, MSG_CombatMatchResult(n): 0 your side won, else it lost. A knockout ends the duel so:
	;the game takes you out with no MSG_CombatRemove(Local Player) - 2026-11-07..14 41 knockouts, every one
	;MatchResult(1), none said. This battle's, once, not after a flee)
	if (RegExMatch(blLine, "Duel (\d+): MSG_CombatMatchResult\((-?\d+)\)", &blMr))
		{
		if (blMr[2] != 0 && blMr[1] = BlDuel && !BlFled && BlOutDuel != blMr[1])
			{
			BlOutDuel := blMr[1]
			BattleDefeated("duel " BlDuel " lost - MSG_CombatMatchResult(" blMr[2] ")")
			}
		}
	if (RegExMatch(blLine, "Duel (\d+): MSG_CombatPhase\((kPhase_\w+)\)", &blM))
		{
		BlPhase := blM[2], BlPhaseAt := A_TickCount
		;(a battle's rounds under way: its end not said yet - the next battle at a circle may have the last one's number)
		if (blM[2] = "kPhase_Planning" || blM[2] = "kPhase_PrePlanning")
			BlOutDuel := ""
		if (blM[1] != BlDuel)
			BlDuel := blM[1], BlNames := V1Obj(), BlCasts := [], BlRound := 0, BlSub := ""
		;(each planning phase names those still in the circle - one that died isn't: the names afresh)
		else if (blM[2] = "kPhase_Planning")
			BlNames := V1Obj(), BlSub := ""
		;(a new round: no flee chosen in it yet)
		if (blM[2] = "kPhase_Planning")
			BlFled := 0
		;(the planning over: one wizard on your side - that's you)
		else if (blM[2] = "kPhase_Execution" && IsObject(BlNames))
			{
			blOne := "", blN := 0
			Loop 4
				if (BlNames.Has(A_Index + 3))
					blN += 1, blOne := BlNames[A_Index + 3]
			if (blN = 1 && blOne != "" && blOne != BlMe)
				{
				BlMe := blOne, BlMeChar := StatsCharID()
				V1Do(IniWrite, blOne, A_ScriptDir "\party.ini", "me", "name")
				V1Do(IniWrite, BlMeChar, A_ScriptDir "\party.ini", "me", "char")
				DebugLog("Battle log: this wizard is " blOne " (the only one on your side)")
				}
			}
		return
		}
	if (RegExMatch(blLine, "CombatPlanningP\s+Subcircle (\d+)\s*$", &blM))
		{
		BlSub := blM[1] + 0
		return
		}
	if (BlSub != "" && RegExMatch(blLine, "CombatantDataControl(?:Small)?, name:(.*?)\s*$", &blM))
		{
		if (!IsObject(BlNames))
			BlNames := V1Obj()
		BlNames[BlSub] := blM[1], BlSub := ""
		return
		}
	if (RegExMatch(blLine, "ResolveCombatRound\. Duel ID:\d+ Round:(\d+) Caster:(\d+) Spell:(.*?)\s*$", &blM))
		{
		if (!IsObject(BlCasts))
			BlCasts := []
		blSlot := blM[2] + 0, blRnd := blM[1] + 0
		;(a second line for the same caster in a round - a pet's may-cast - isn't the enemy's own choice)
		for each, blC in BlCasts
			if (blC.round = blRnd && blC.slot = blSlot)
				return
		BlCasts.Push(V1Obj({round: blRnd, slot: blSlot, spell: blM[3]}))
		BlRound := Max(BlRound ? BlRound : 0, blRnd)
		;(an enemy's: counted for its creature - the odds learn)
		if (blSlot <= 3 && IsObject(BlNames) && BlNames.Has(blSlot) && VisionOn)
			VisionGet("/enemyseen?name=" NavUri(BlNames[blSlot]) "&spell=" NavUri(blM[3]) "&round=" blRnd, 600, true)
		}
	}

;How many wizards are on your side of this battle (the game's log; 0 not known)
BattleTeam()
	{
	n := 0
	if (IsObject(BlNames))
		Loop 4
			n += BlNames.Has(A_Index + 3) ? 1 : 0
	return n
	}

;Your own wizard's name: learned from a battle with no other wizard on your side (this run, else the last one kept in
;party.ini) - for the character logged in now -, else the party name typed in (Party...); "" none
OwnName()
	{
	cid := StatsCharID()
	if (BlMe != "" && (BlMeChar = "" || cid = "" || BlMeChar = cid))
		return BlMe
	;(v1's %A_Space% default: a blank)
	n := IniRead(A_ScriptDir "\party.ini", "me", "name", "")
	nChar := IniRead(A_ScriptDir "\party.ini", "me", "char", "")
	if (Trim(n) = "" || (nChar != "" && cid != "" && nChar != cid))
		n := IniRead(A_ScriptDir "\party.ini", "party", "name", "")
	return Trim(n)
	}

;Your plate when more than one wizard is on your side: the name pictures (player.png...) would find whichever of your
;wizards' plates comes first - so your side's plates are read (ReadSidePlates) and yours (OwnName) picked. x, y: where
;its name starts (as the name picture's match would be). False: not a team battle, no name known, or not read
PlayerPlateByName(&x, &y)
	{
	if (BattleTeam() < 2 || OwnName() = "")
		return false
	ReadSidePlates()
	for ppSlot, ppP in SidePlates
		if (ppP.me)
			{
			x := ppP.x, y := ppP.y
			DebugLog("  your plate by its name (" ppP.name ", a battle with " BattleTeam() " of you) at " x - GameLeft "," y - GameTop)
			return true
			}
	DebugLog("  " OwnName() "'s plate not read among " BattleTeam() " wizards on your side - the name pictures instead")
	return false
	}

;Your side's name plates (a battle with more than one wizard on it): one OCR of the screen's bottom fifth, and each name
;the game's log gives for slots 4-7 found among its words - a plate's capitals first (the chat's "Joshua" mustn't take
;its place), then any word in the plates' row; each time the same letters (the whole name or its first word), then alike
;(WalkNameLike), then the nearest capitals in the row with half its first word's letters right (they read badly now and
;then: JOSHUA as "JOSWA"). Each word one name's at most ("JOSH" mustn't take JOSHUA's plate); a name's first word before
;its others (x, y: where the name starts). SidePlates: {slot: {name, x, y, me}} - me: yours (OwnName). MySlot: your slot
;(0 not found). Read once a round. How many were found
ReadSidePlates()
	{
	global SidePlatesKey, SidePlates, MySlot ; (v1 globals it sets)
	rsKey := BlDuel "|" roundnumber "|" BattleTeam()
	if (rsKey = SidePlatesKey && IsObject(SidePlates))
		return SidePlates.Count
	SidePlatesKey := rsKey, SidePlates := V1Obj(), MySlot := 0
	if (BattleTeam() < 2 || !V1IsFunc("WalkLetters"))
		return 0
	rsT := OcrRect(GameLeft, Round(GameTop + GameH * 0.8), GameW, Round(GameH * 0.2), "en", 2, &rsLines)
	if (ErrorLevel || !IsObject(rsLines))
		return 0
	rsWords := []
	for each, rsLine in rsLines
		for each, rsW in rsLine.words
			{
			rsK := WalkLetters.Call(rsW.text)
			if (StrLen(rsK) >= 3)
				rsWords.Push(V1Obj({k: rsK, x: rsW.x, y: rsW.y, caps: StrLen(RegExReplace(rsW.text, "[^A-Z]")) >= StrLen(RegExReplace(rsW.text, "[^a-z]")), used: 0}))
			}
	rsMe := WalkLetters.Call(OwnName())
	rsLike := V1IsFunc("WalkNameLike") && V1IsFunc("WalkEditDist")
	;(round 1: capitals only - the row the plates are in comes from the first found; round 2: any word, in that row.
	;Pass 1 the same letters, 2 alike, 3 - capitals in the row only - half the first word's letters)
	rsRowY := ""
	Loop 2
		{
		rsRound := A_Index
		Loop 3
			{
			rsPass := A_Index
			if ((rsRound = 2 && rsPass = 3) || (rsPass > 1 && !rsLike))
				continue
			Loop 4
				{
				rsSlot := A_Index + 3
				if (!IsObject(BlNames) || !BlNames.Has(rsSlot) || SidePlates.Has(rsSlot))
					continue
				rsName := WalkLetters.Call(BlNames[rsSlot]), rsFirst := WalkLetters.Call(V1At(StrSplit(Trim(BlNames[rsSlot]), " "), 1))
				if (StrLen(rsName) < 3 || (rsPass = 3 && StrLen(rsFirst) < 4))
					continue
				rsBest := 0, rsBestScore := ""
				for rsI, rsW in rsWords
					{
					if (rsW.used || ((rsRound = 1 || rsPass = 3) && !rsW.caps) || ((rsRound = 2 || rsPass = 3) && rsRowY != "" && Abs(rsW.y - rsRowY) > Px(12)))
						continue
					if (rsPass = 1)
						rsD := (rsW.k = rsName || rsW.k = rsFirst) ? 0 : ""
					else if (rsPass = 2)
						rsD := (WalkNameLike.Call(rsW.k, rsName) || WalkNameLike.Call(rsW.k, rsFirst)) ? Min(WalkEditDist.Call(rsW.k, rsName), WalkEditDist.Call(rsW.k, rsFirst)) : ""
					else
						{
						rsD := WalkEditDist.Call(rsW.k, rsFirst)
						rsD := (rsD <= StrLen(rsFirst) // 2) ? rsD : ""
						}
					if (rsD = "")
						continue
					;(where the name starts - its first word - before its others; lower on the screen the nearer the plates)
					rsScore := ((rsW.k = rsFirst || InStr(rsName, rsW.k) = 1) ? 0 : 500) + rsD * 10 - rsW.y / 10000
					if (rsBestScore = "" || rsScore < rsBestScore)
						rsBest := rsI, rsBestScore := rsScore
					}
				;(a later word of the name found - its first misread: the word just left of it in the same line is where the
				;name starts)
				if (rsBest && rsWords[rsBest].k != rsFirst && InStr(rsName, rsWords[rsBest].k) != 1)
					{
					rsLeft := 0
					for rsI, rsW in rsWords
						if (!rsW.used && rsI != rsBest && Abs(rsW.y - rsWords[rsBest].y) <= Px(6) && rsW.x < rsWords[rsBest].x && rsWords[rsBest].x - rsW.x < Px(220)
							&& (!rsLeft || rsW.x > rsWords[rsLeft].x))
							rsLeft := rsI
					if (rsLeft)
						rsWords[rsBest].used := 1, rsBest := rsLeft
					}
				if (rsBest)
					{
					rsWords[rsBest].used := 1
					SidePlates[rsSlot] := V1Obj({name: BlNames[rsSlot], x: rsWords[rsBest].x, y: rsWords[rsBest].y, me: rsName = rsMe})
					if (rsName = rsMe)
						MySlot := rsSlot
					if (rsWords[rsBest].caps && rsRowY = "")
						rsRowY := rsWords[rsBest].y
					}
				}
			}
		}
	rsSaid := ""
	for rsSlot, rsP in SidePlates
		rsSaid .= (rsSaid = "" ? "" : ", ") rsP.name (rsP.me ? " (you)" : "") " at " rsP.x - GameLeft "," rsP.y - GameTop
	DebugLog("  your side's plates: " (rsSaid = "" ? "none read" : rsSaid) " (" BattleTeam() " wizards in the log)")
	return SidePlates.Count
	}

;This round's odds - the enemies' likely spells and the chance their hits kill the wizard: logged, on the dashboard
;(Threat), EnemyLethal. True if that chance is defendat % or more. Needs the battle log (the game's), the vision helper
;and your own health (read here if this round hasn't yet)
EnemyDanger()
	{
	global EnemyLethal, EnemyLethalRound ; (v1 globals it sets)
	EnemyLethal := "", EnemyLethalRound := roundnumber
	if (!Stat("enemyspells") || !VisionOn)
		return false
	BattleLogRead(true)
	edNames := "", edSlots := [], edTeam := 0
	if (!IsObject(BlNames))
		return false
	Loop 4
		{
		edS := A_Index - 1
		if (BlNames.Has(edS))
			edNames .= (edNames = "" ? "" : "|") NavUri(BlNames[edS]), edSlots.Push(edS)
		}
	Loop 4
		if (BlNames.Has(A_Index + 3))
			edTeam += 1
	if (!edSlots.Length)
		return false
	;(your health: read this round already - the heal check - or now, quietly)
	if (!(OwnHpCur != "" && OwnHpRound = roundnumber && A_TickCount - OwnHpAt < 20000 && OwnHpWin = WinExist("A")) && playerX != "" && !(playerX = 0 && playerY = 0))
		OwnHealthLow(true)
	edHealth := (OwnHpCur != "" && OwnHpRound = roundnumber && OwnHpWin = WinExist("A")) ? OwnHpCur : ""
	;(a low reading only 2 of its 4 reads agreed on - 775 read as 75 - isn't trusted: as for a heal)
	if (edHealth != "" && OwnHpVotes < 3 && 100 * OwnHpCur / OwnHpMax < StatOr("healat", 40))
		edHealth := ""
	;(the casts so far: round:enemy index (its place among the enemies):spell)
	edHist := ""
	for each, edC in (IsObject(BlCasts) ? BlCasts : [])  ; (v1: names read before any cast or new-duel line - BlCasts blank: no loop; v2 throws)
		for edI, edS in edSlots
			if (edC.slot = edS)
				edHist .= (edHist = "" ? "" : "|") edC.round ":" (edI - 1) ":" NavUri(edC.spell)
	edAns := VisionGet("/enemies?names=" edNames "&round=" V1Add(BlRound, 1) "&health=" edHealth "&team=" Max(1, edTeam) "&hist=" edHist, 1500, true)  ; (v1: BlRound blank - names read before a phase line - gave a blank round)
	if (edAns = "")
		return false
	edText := "", edDash := "", edLethal := ""
	Loop Parse, edAns, "`n", "`r"
		{
		edF := StrSplit(A_LoopField, "|")
		if (edF[1] = "lethal")
			edLethal := edF[2]
		if (edF[1] != "enemy")
			continue
		edTop := ""
		for each, edT in StrSplit(edF[8], ";")
			{
			edP := StrSplit(edT, ":")
			if (edP[1] != "" && A_Index <= 3)
				edTop .= (edTop = "" ? "" : ", ") edP[1] " " Round(edP[2] * 100) "%"
			}
		edWhat := edF[4] = "pending" ? "looking it up on the wiki" : edF[4] = "missing" ? "not on the wiki" : edTop
		edText .= (edText = "" ? "" : " | ") edF[3] " (~" Round(edF[5]) " pips): " edWhat
		edDash .= (edDash = "" ? "" : " | ") edF[3] ": " (edF[4] = "ok" ? V1At(StrSplit(edTop, ","), 1) : edWhat)
		}
	EnemyLethal := edLethal
	edRisk := edLethal = "" ? "your health unknown" : Round(edLethal * 100) "% chance their hits kill you this round"
	DebugLog("  enemy spells: " edText " - " edRisk)
	if (V1IsFunc("DashSee"))
		DashSee.Call("threat", edDash (edLethal = "" ? "" : " - " Round(edLethal * 100) "% lethal"))
	;(the Cards tab: every spell of each enemy and its chance)
	if (V1IsFunc("DashFoesSeen"))
		DashFoesSeen.Call(edAns, edLethal, edHealth, V1Add(BlRound, 1))
	edAt := Stat("defendat")
	return edLethal != "" && edAt > 0 && edLethal * 100 >= edAt
	}

;Defending first (EnemyDanger said so): a heal on yourself (heal1, heal2), else Tower Shield (resources\tower, usetower
;on - one no picture finds at its card box by the game's hand: KillCalc.ahk TowerMem, Autofarmer.ahk UseMemAt). True if
;one went out
EnemyDefend()
	{
	global
	local edWhy, _title, _dir  ; (v2 port: the ByRef temporaries below this call's own, as v1's were)
	edWhy := "  defending: " Round(EnemyLethal * 100) "% chance this round's enemy hits kill you"
	;(a heal only with health to restore - at full, Tower Shield)
	if ((heal1 == 1 || heal2 == 1) && OwnHpCur != "" && OwnHpCur < OwnHpMax * 0.9)
		{
		DebugLog(edWhy " - a heal first")
		if (heal1 == 1) && UseHeal("heal1", &heal1, hitschool)
			return true
		if (heal2 == 1) && UseHeal("heal2", &heal2, hitschool)
			return true
		}
	if (tower == 1 && Stat("usetower"))
		{
		DebugLog(edWhy " - Tower Shield first")
		UseOnSelf(&_title := "tower", &tower, &_dir := "resources")
		if (tower == 1 && CastWentOut())
			{
			if (V1IsFunc("DashCast"))
				DashCast.Call("tower")
			return true
			}
		}
	;(no Tower Shield went: an absorb - it soaks N damage - on you, whatever it costs: by its picture (resources\absorb), else
	;at its card box by the game's hand - KillCalc.ahk AbsorbMem, 2026-10-26)
	if (absorb == 1 && V1IsFunc("AbsorbOn") && AbsorbOn.Call())
		{
		DebugLog(edWhy " - an absorb")
		UseOnSelf(&_title := "absorb", &absorb, &_dir := "resources")
		if (absorb == 1 && CastWentOut())
			{
			if (V1IsFunc("DashCast"))
				DashCast.Call("absorb")
			return true
			}
		}
	DebugLog(edWhy " - nothing to heal or shield with in hand")
	return false
	}

;Knocked out (BattleLogLine; how: what the game's log said): said - the dashboard counts the line (Deaths) - and counted
;at the quest goal (KoNote)
BattleDefeated(how)
	{
	DebugLog("Defeated: the wizard was knocked out of the battle (the game's log: " how ")")
	KoNote()
	}

;A knockout counted at the quest goal it happened at (the walker's goal line, else the zone - each goal's own count: KoTimes
;{goal: [when]}, the last 3 hours; KoGoal the last one's). The bot on only (F6 off, or never started: your own knockouts
;aren't its to count). The 3rd at one goal while walking: walking stopped, a notice (and a Discord alert, if set up) - the
;deck isn't winning that fight, and every knockout costs a potion run (2026-11-13/14: 12 knockouts in a night at the same
;Nastrond bosses, a run of 5400-7200 gold after each, till you moved the wizard). Walking on (F8) counts that goal afresh
KoNote()
	{
	global KoGoal, KoTimes, Walking ; (v1 globals it sets)
	global WkGoalLine, BotOn ; (read: the walker's goal line, the bot on)
	if (!BotOn)
		return
	koG := Trim(WkGoalLine)
	if (koG = "")
		koG := "somewhere in " (V1IsFunc("WalkZone") ? WalkZone.Call() : "this zone")
	if (!IsObject(KoTimes))
		KoTimes := KoLoad()
	koKeep := []
	for koT in (KoTimes.Has(koG) ? KoTimes[koG] : [])
		if (A_TickCount - koT < 10800000)
			koKeep.Push(koT)
	koKeep.Push(A_TickCount)
	KoTimes[koG] := koKeep, KoGoal := koG
	KoSave("ko", koG)
	koN := koKeep.Length
	DebugLog("Knockouts: " koN " in the last 3 hours at the quest goal '" SubStr(KoGoal, 1, 100) "'" (koN < 3 ? "" : Walking ? " - walking stopped" : " - walking is off already"))
	if (koN < 3 || !Walking)
		return
	Walking := 0
	ReleaseKeys()
	KoTimes.Delete(koG)
	KoSave("reset", koG)
	koKey := V1IsFunc("HkText") ? HkText.Call("walk") : "F8"
	koText := "Knocked out " koN " times in 3 hours at the quest goal '" SubStr(KoGoal, 1, 100) "' - the deck isn't winning that fight, and every knockout costs a potion run. Walking is stopped: a stronger deck (hits that cost few pips), a party, or another quest - then press " koKey " to walk on."
	if (V1IsFunc("SetStatus"))
		SetStatus.Call("stopped - knocked out " koN " times at the same quest goal: press " koKey " to walk on")
	if (V1IsFunc("WalkNotify"))
		WalkNotify.Call("ko", "Knocked out again and again", koText)
	;(made in the battle - the knockout's read while it's still on: shown once it's over. The walker's next step would show it,
	;but a follower's, a dungeon run's or a puzzle run's never comes with walking off)
	SetTimer(KoNoteShow, -2000)
	}

;The knockout counts' file: kept over a restart of the bot - one line a knockout or a stop's reset ("when|ko|goal",
;"when|reset|goal"; when: A_Now)
KoFile()
	{
	return A_ScriptDir "\learned\knockouts.txt"
	}

;A line onto it (kind: "ko" or "reset") - never in the way if it can't be written
KoSave(kind, goal)
	{
	try
		FileAppend(A_Now "|" kind "|" StrReplace(StrReplace(goal, "`r"), "`n", " ") "`n", KoFile(), "UTF-8")
	}

;The counts as the file has them: {goal: [when, as A_TickCount]}, the last 3 hours - a goal's reset drops those before it.
;The file cut down to them when it's grown over 32 KB. Nothing there, or unreadable: none
KoLoad()
	{
	klOut := V1Obj()
	try
		klText := FileRead(KoFile(), "UTF-8")
	catch
		return klOut
	klKeep := ""
	Loop Parse, klText, "`n", "`r"
		{
		klF := StrSplit(A_LoopField, "|", , 3)
		if (klF.Length < 3 || !RegExMatch(klF[1], "^\d{14}$") || klF[3] = "")
			continue
		try
			klAge := DateDiff(A_Now, klF[1], "Seconds")
		catch
			continue
		if (klAge < 0 || klAge >= 10800)
			continue
		if (klF[2] = "reset")
			klOut.Delete(klF[3])
		else if (klF[2] = "ko")
			{
			if (!klOut.Has(klF[3]))
				klOut[klF[3]] := []
			klOut[klF[3]].Push(A_TickCount - klAge * 1000)
			}
		else
			continue
		klKeep .= A_LoopField "`n"
		}
	if (StrLen(klText) > 32768)
		try
			{
			FileDelete(KoFile())
			FileAppend(klKeep, KoFile(), "UTF-8")
			}
	return klOut
	}

;The knockout notice shown once the battle's over (KoNote) - not if it's gone, shown already or put away (OK)
KoNoteShow()
	{
	global WkNoteKind, WkNoteShown, WkNoteOff, inbattle ; (read: the walker's notice, the battle)
	if (WkNoteKind != "ko" || WkNoteShown || WkNoteOff)
		return
	if (inbattle)
		{
		SetTimer(KoNoteShow, -2000)
		return
		}
	if (V1IsFunc("WalkNoteShow"))
		WalkNoteShow.Call()
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
EnemySpellsBlank()
	{
	global KoGoal := "", KoTimes := ""
	global BlPos := "", BlHead := "", BlDuel := "", BlNames := "", BlSub := "", BlCasts := "", BlRound := "", BlReadAt := "", BlPhase := ""
	global BlOutDuel := ""
	global BlPhaseAt := "", BlFled := "", BlMe := "", BlMeChar := "", OwnHpCur := "", OwnHpMax := "", OwnHpAt := "", OwnHpVotes := "", OwnHpWin := ""
	global EnemyLethal := "", EnemyLethalRound := "", heal1 := "", heal2 := "", hitschool := "", tower := "", absorb := ""
	}
