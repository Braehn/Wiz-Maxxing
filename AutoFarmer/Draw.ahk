; Draw.ahk - treasure cards drawn for an enchant that makes the kill. AHK v1.1, functions only; #Included by
; Autofarmer.ahk.
;
; The kill check (Autofarmer.ahk) found no hit in hand that ends the battle now, but one would with an enchant on it
; (+drawneed damage - PlayerStats.txt, 100 = Strong's, so any enchant does) and there's no enchant in hand: with
; drawenchant on (the Settings window, off unless you switch it on) the bot draws from your treasure-card deck - the
; DRAW button between Pass and Flee - until an enchant comes. Draw is greyed out with 7 cards in hand (the game refills
; the hand every round), so one card is right-clicked away first: never a treasure card (that would use it up), never
; the hit that makes the kill, nor an enchant; one that isn't a hit before one that is. A treasure card it doesn't
; know yet is learned on the spot (a Monstrous: CardLearn.ahk's "enchant" kind). The kill check then runs again with
; the enchant in hand - lethal: the hit goes enchanted; not: the enchant's kept for later and the round goes on as
; usual. At most drawround draws a round and drawmax a battle; Draw greyed out with room in hand (no treasure cards
; left) or a click that brings no card: no more this battle. Never with "Crown" read near the button, nor while you
; play. debug.log: "draw: ...".

;Treasure cards drawn this battle; why drawing's off for this battle ("" on); the run's (Draw ended the turn); the hit
;that would make the kill (kept when making room); when Draw was last greyed out with room in hand (no treasure cards
;left - not tried again for 30 minutes: a card's discarded to find out). (#Included at the bottom: no initializers -
;ResetVariables)
global DrawsBattle, DrawOff, DrawBroken, DrawKeep, DrawEmptyAt

;Would a hit in hand end the battle with an enchant of +drawneed on it (none in hand now)? DrawKeep := that hit
DrawWouldKill()
	{
	global
	local was, wasStat, h, e
	DrawKeep := ""
	if (!Stat("drawenchant") || V1Ge(enchant, 1))  ; (v1: enchant blank before the first look at the hand: none)
		return false
	;(the kill check with a made-up enchant - level 8, its damage drawneed - then put back)
	was := enchant, wasStat := Stats.Has("enchant8") ? Stats["enchant8"] : ""
	Stats["enchant8"] := Stat("drawneed") > 0 ? Stat("drawneed") : 100, enchant := 8
	if (FindLethalHit(&h, &e) && e)
		DrawKeep := h
	enchant := was
	if (wasStat = "")
		Stats.Delete("enchant8")
	else
		Stats["enchant8"] := wasStat
	return DrawKeep != ""
	}

;Draws treasure cards till an enchant's in hand (see the top). True if one is
DrawForKill()
	{
	global
	local ans, n, w, band, lit, t0, got, tries, made, n2
	DrawsBattle := DrawsBattle ? DrawsBattle : 0
	if (!Stat("drawenchant") || !VisionOn || DrawBroken != "" || DrawOff != "" || LearnAll || Manual == 1 || RoundAgain)
		{
		if (DrawOff != "" || DrawBroken != "")
			DebugLog("  draw: no draw - " (DrawBroken != "" ? DrawBroken : DrawOff))
		return false
		}
	if (DrawEmptyAt && A_TickCount - DrawEmptyAt < 1800000)
		{
		DebugLog("  draw: no draw - Draw was greyed out with room in hand " Round((A_TickCount - DrawEmptyAt) / 60000) " min ago (no treasure cards left?) - tried again after 30 min")
		return false
		}
	tries := 0
	while (tries < Stat("drawround") && DrawsBattle < Stat("drawmax"))
		{
		tries += 1
		if (!BotOn || PlayerActing())
			return false
		ans := LearnHandRead(), n := DrawHandCount(ans)
		if (n < 0)
			{
			DebugLog("  draw: no draw - the hand couldn't be read")
			return false
			}
		;(the button read first - and no "Crown" anywhere by it - before any card's discarded for it)
		w := DrawWord(&band)
		if (!IsObject(w))
			{
			DebugLog("  draw: no draw - the Draw button couldn't be read (OCR: " SubStr(band, 1, 80) ")")
			DrawOff := "the Draw button couldn't be read"
			return false
			}
		if (RegExMatch(band, "i)cr[o0]wn"))
			{
			DebugLog("  draw: no draw - `"Crown`" on the screen by the buttons")
			DrawOff := "Crown on the screen"
			return false
			}
		;(a full hand: one card away first - Draw's greyed out with 7)
		made := ""
		if (n >= 7)
			{
			if (!BotOn || PlayerActing())
				return false
			made := DrawMakeRoom(ans)
			if (made = "")
				{
				DebugLog("  draw: no draw - 7 cards in hand and none to spare (treasure cards, the hit, enchants)")
				return false
				}
			ans := LearnHandRead(), n2 := DrawHandCount(ans)
			n := (n2 >= 0) ? n2 : n - 1
			}
		lit := DrawLit(w)
		if (!lit)
			{
			DebugLog("  draw: no draw - Draw greyed out with " n " card(s) in hand (no treasure cards left?)" (made != "" ? " - " made " was discarded for it" : ""))
			DrawOff := "Draw greyed out with " n " cards in hand", DrawEmptyAt := A_TickCount
			return false
			}
		if (!BotOn || PlayerActing())
			return false
		DebugLog("  draw: " DrawKeep " would end the battle with an enchant - drawing a treasure card (" n " in hand" (made != "" ? ", " made " discarded for room" : "") ")")
		ClickAt(Round(w.x + w.w / 2), Round(w.y + w.h / 2), 100)
		VisionForget()
		;(the new card in: one more in hand - looked at every 200 ms for 2 s)
		got := -1, t0 := A_TickCount
		while (A_TickCount - t0 < 2000)
			{
			Sleep(200)
			got := DrawHandCount(LearnHandRead())
			if (got > n)
				break
			}
		if (got <= n)
			{
			DebugLog("  draw: Draw clicked, but no card came (" n " -> " got ") - no more drawing this battle")
			DrawOff := "Draw clicked but no card came"
			return false
			}
		DrawsBattle += 1
		;(the round still up: drawing doesn't end the turn - if it did, never again this run)
		if (!DrawRoundUp())
			{
			DrawBroken := "Draw ended the turn - off till the bot's restarted"
			DebugLog("  draw: the round ended with the draw - drawing off till the bot's restarted")
			return false
			}
		;(a card it doesn't know learned now - an enchant gets its place, so it's found; no boost slot picture counted as
		;missed against the round's look from before the draw - CardLearn.ahk LearnBoostPicFix)
		LearnCards(0)
		VisionForget(), FindEnchant()
		DebugLog("  draw: drew a treasure card (" DrawsBattle " this battle) - " (enchant >= 1 ? "an enchant now in hand (+" Stat("enchant" enchant) ")" : "not an enchant"))
		if (enchant >= 1)
			return true
		}
	return false
	}

;Cards in hand answer (a /hand read): only boxes the helper calls cards - -1 none read
DrawHandCount(ans)
	{
	if (ans = "")
		return -1
	n := 0, boxes := 0
	Loop Parse, ans, "`n", "`r"
		{
		if (InStr(A_LoopField, "card|") != 1)
			continue
		boxes += 1
		f := StrSplit(A_LoopField, "|")
		if (f.Length < 15 || f[15] != "0")
			n += 1
		}
	return (boxes || InStr(ans, "hand|0")) ? n : -1
	}

;One card right-clicked away to make room to draw - only one the bot knows, in colour: never a treasure card (the
;helper's read or the catalog's tc - a greyed-out one loses its colour, so a card it doesn't know or one greyed out is
;never taken), never one you said never to discard, never the hit that makes the kill (DrawKeep - by name, and where
;the battle's own search found it), never an enchant; one that isn't a hit (a heal, blade, shield...) before another
;hit. What it discarded ("" none)
DrawMakeRoom(ans)
	{
	global
	local best, bestRank, f, k, rank, x, y, lc, keepX
	best := "", bestRank := 9, keepX := (DrawKeep != "") ? %DrawKeep%X : ""
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length < 16 || f[1] != "card" || f[15] = "0" || f[16] = 1 || f[8] = 1 || f[6] = "")
			continue
		k := f[6]
		if (k = hitschool "/" DrawKeep || RegExMatch(k, "i)^resources/(epic|colossal|gargantuan|monstrous|giant|strong)$|^life/enchant$"))
			continue
		if (keepX != "" && keepX >= f[2] - 5 && keepX <= f[2] + f[4])
			continue
		lc := (InStr(k, "learned/") = 1) ? LearnCardOf(SubStr(k, 9)) : ""
		if (InStr(k, "learned/") = 1 && (!IsObject(lc) || lc.type = "enchant" || LearnHasFlag(lc, "tc") || LearnHasFlag(lc, "hold")))
			continue
		rank := (RegExMatch(k, "i)/(hit\d|wand)$") || LearnIsHit(lc)) ? 2 : 1
		if (rank < bestRank)
			best := f, bestRank := rank
		}
	if (!IsObject(best))
		return ""
	x := Round(best[2] + best[4] / 2), y := Round(best[3] + best[5] * 0.6)
	MoveToCard(x, y)
	s(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
	;(Wizard101 gone to the tray - Settings: traygame: not clicked - it would land on the window behind it)
	if (GameInTray)
		return ""
	Click("right")
	s(Stat("discardafter"))
	VisionForget(), CenterMouse()
	DebugLog("  draw: discarded " best[6] " to make room (right-click at " x - GameLeft "," y - GameTop ")")
	return best[6]
	}

;Whether the card under screen x in the hand is a treasure card - a fresh look at the hand (its text box's colour, or
;the catalog's tc for a learned one): never right-clicked away (DiscardCard), that uses it up
DiscardIsTc(x)
	{
	ans := V1IsFunc("LearnHandRead") ? LearnHandRead() : ""
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length < 16 || f[1] != "card" || x < f[2] - 5 || x > f[2] + f[4] + 5)
			continue
		if (f[16] = 1)
			return true
		lc := (InStr(f[6], "learned/") = 1) ? LearnCardOf(SubStr(f[6], 9)) : ""
		return IsObject(lc) && LearnHasFlag(lc, "tc")
		}
	return false
	}

;The DRAW button's word ({x, y, w, h} on the screen) under the hand, between PASS and FLEE - by OCR as FleeWord
;reads FLEE; band: all that was read there (for Crown). "" if not read. The mouse moved off it first (hovered, it
;greys and its tooltip "Discard to draw a treasure card" shows); level with PASS when PASS is read
DrawWord(&band)
	{
	band := ""
	MouseMove(ScreenX, ScreenY - Px(250), 0)
	Sleep(150)
	OcrRect(GameLeft + GameW // 8, GameTop + Round(GameH * 0.4), GameW * 3 // 4, Round(GameH * 0.45), "en", GameH < 1000 ? 2 : 1, &lines)
	if (ErrorLevel || !IsObject(lines))
		return ""
	for i, line in lines
		for j, word in line.words
			band .= word.text " "
	passY := ""
	for i, line in lines
		for j, word in line.words
			if (RcLooksLike(RegExReplace(word.text, "[^A-Za-z0-9|]"), "PASS") && word.x + word.w / 2 < ScreenX)
				passY := word.y + word.h / 2
	for i, line in lines
		for j, word in line.words
			{
			t := RegExReplace(word.text, "[^A-Za-z0-9|]")
			;(in the middle - Pass left of it, Flee right - and level with Pass: the tooltip's "draw" is lower)
			if (RcLooksLike(t, "DRAW") && Abs(word.x + word.w / 2 - ScreenX) <= Px(80) && word.h >= Px(10)
				&& (passY = "" || Abs(word.y + word.h / 2 - passY) <= Px(12)))
				return word
			}
	return ""
	}

;The DRAW button lit (pure yellow letters, as Pass and Flee) - not greyed out (7 in hand, or no treasure cards).
;The mouse moved off it first: hovered, its letters turn grey
DrawLit(w)
	{
	MouseMove(ScreenX, ScreenY - Px(250), 0)
	Sleep(120)
	;(v2 port: v1's px, py renamed - in v2 a local px would hide the Px() function it calls)
	V1PixelSearch(&dlX, &dlY, w.x - Px(4), w.y - Px(4), w.x + w.w + Px(4), w.y + w.h + Px(4), 0xFFFF00, 0, "Fast RGB")
	return ErrorLevel = 0
	}

;The round still up - its Pass button there (the picture the round start was found by), seen once in 1.2 s: it can
;blink out for a moment while the hand updates (CastWentOut)
DrawRoundUp()
	{
	t0 := A_TickCount
	while (A_TickCount - t0 < 1200)
		{
		Sleep(150)
		V1ImageSearch(&px, &py, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundstart.png"))
		if (ErrorLevel = 0)
			return true
		}
	return false
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
DrawBlank()
	{
	global DrawsBattle := "", DrawOff := "", DrawBroken := "", DrawKeep := "", DrawEmptyAt := "", enchant := "", Stats := "", VisionOn := ""
	global LearnAll := "", Manual := "", RoundAgain := "", BotOn := "", hitschool := "", GameLeft := "", GameTop := ""
	}
