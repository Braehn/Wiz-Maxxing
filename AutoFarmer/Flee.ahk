; Flee.ahk - out of mana or out of cards in a battle: flee, then try again. AHK v1.1, functions only;
; #Included by Autofarmer.ahk.
;
; Once a round, before casting (FleeCheck): the cards in hand (the vision helper's read of the hand) and your
; mana (the blue globe, Potions.ahk PotionGlobes). Two rounds in a row with no cards in hand - the deck used up -
; or no hit in a hand of fewer than 7 cards (a full hand's 7: the deck's used up, and heals and blades can't end
; the battle), or with less mana than the cheapest hit costs (every spell costs a mana a pip; a wand costs none,
; so not while one's in hand) and the bot can only pass for the rest of the battle: it clicks Flee (the word FLEE found by OCR
; under the hand, where Pass is on the left) and the battle's over. Out of battle again (FleeAfter): fled for
; mana, it drinks a potion (Ctrl+O) - none left, it goes and buys some (Potions.ahk PotionRun) and drinks one -
; then farms / walks on as usual, so the next battle starts with a full deck and mana. Not while you play, while
; learning every card, or on a manual round.
; PlayerStats.txt: fleeon:0 switches it off. debug.log: "fleeing: ...", "after fleeing: ...".

;Rounds in a row with no cards / too little mana / no hits left; why the last flee was ("mana" / "cards"; "" when
;dealt with). (this file is #Included at the bottom: an initializer here never runs - they start blank, made numbers
;in FleeCheck)
global FleeNoCards, FleeNoMana, FleeNoHits, FleeWhy
;The battle round (roundnumber) the no-hits count last looked at - "" a new battle (ResetVariables)
global FleeHitsRound

;True if it fled (the round's over: EndRound)
FleeCheck()
	{
	global
	local cards, g, mana, cheapest, why, w, fx, fy, fled, mh, memHit, mc, mcCard
	static FleeSaidRound := ""
	if (!Stat("fleeon") || LearnAll || Manual == 1)
		return false
	;(blank till now: made numbers - in an expression "" + 1 is "" in AHK v1, and so is a blank "+= 0" chained with a
	;comma: a count that started blank never reached 2, so no flee when the first rounds after a start were out of
	;mana or cards)
	FleeNoCards := FleeNoCards ? FleeNoCards : 0, FleeNoMana := FleeNoMana ? FleeNoMana : 0, FleeNoHits := FleeNoHits ? FleeNoHits : 0
	cards := FleeHandCount()
	;(the game's own hand when it was read this pass - its count, and a hit in it, greyed out or not: a greyed card the
	;pictures can't place, or one waiting for pips, is still a card and still a hit - 2026-10-25: fled twice holding
	;greyed Power Novas / Supernovas with 7 cards in hand)
	mh := V1IsFunc("VisionCards") ? VisionCards.Call(0, 5000) : "", memHit := ""
	if (IsObject(mh) && IsObject(mh.cards))
		{
		cards := mh.cards.Length, memHit := 0
		for mc, mcCard in mh.cards  ; (v1: mc the index - v2's one variable over an array is its value)
			if (mh.cards[mc].kind = "damage" || mh.cards[mc].kind = "aoe" || mh.cards[mc].xpip)
				memHit := 1
		}
	if (cards >= 0)
		FleeNoCards := (cards = 0) ? FleeNoCards + 1 : 0
	;(no hit in a hand of fewer than 7 cards - a full hand's 7, so the deck's used up: what's left can't end the
	;battle - 2026-10-21: a wizard passed 6 rounds holding 2 heals and a blade, and died. Once a battle round, on its
	;first look - a round left to you and looked at again holds what's left after its discards - and not in dual
	;mode, where two wizards' rounds take turns and the other one still hits)
	if (cards > 0 && !RoundAgain && dualmode != 1 && FleeHitsRound != roundnumber)
		FleeHitsRound := roundnumber, FleeNoHits := (cards < 7 && (memHit != "" ? !memHit : FleeHandHasHit() = 0)) ? FleeNoHits + 1 : 0
	;(a wand in hand costs no mana: it can still hit - unless it's switched off, usewand)
	cheapest := FleeCheapestHit()
	if ((wand == 1 && Stat("usewand")) || cheapest = "")
		FleeNoMana := 0
	else
		{
		g := PotionGlobes(), mana := g.mana
		if (mana != "")
			FleeNoMana := (mana + 0 < cheapest) ? FleeNoMana + 1 : 0
		}
	;(no hits left: not a party battle's blader or healer - it's there for its boosts, the hitter hits)
	;(only completely out of cards - no card in hand, two rounds running: you asked, 2026-10-25 - never for no hit in hand
	;or out of mana: it fled holding greyed hits and boosts. The other counts still go in the log)
	why := FleeNoCards >= 2 ? "no cards left (the deck's used up)" : ""
	if (why = "" && FleeSaidRound != roundnumber && ((FleeNoHits >= 2 && !PartySupport()) || FleeNoMana >= 2))
		FleeSaidRound := roundnumber, DebugLog("  " (FleeNoMana >= 2 ? "out of mana (" mana ", the cheapest hit costs " cheapest ")" : "no hit in a hand of " cards " card(s)") " - not fleeing: only out of cards")
	if (why = "")
		return false
	w := FleeWord()
	if (!IsObject(w))
		{
		DebugLog("  " why " - it would flee, but the Flee button can't be read")
		return false
		}
	DebugLog("  fleeing: " why " - Flee at " Round(w.x + w.w / 2) - GameLeft "," Round(w.y + w.h / 2) - GameTop " - to try again")
	ClickAt(Round(w.x + w.w / 2), Round(w.y + w.h / 2), 300)
	;(the game asks "Are you sure you want to flee? You will lose all your Mana..." - Yes / No: Yes)
	FleeConfirm()
	;(did it take? The round's Pass button goes with it. Not: once more, the mouse brought up from below the buttons -
	;on its way across, a card in hand zooms up under the mouse and can cover the button. Still not: the round goes on,
	;and the next tries again - the counts kept)
	if (!CastWentOut())
		{
		;(Wizard101 gone to the tray - Settings: traygame: not again - the click would land on the window behind it)
		if (GameInTray)
			return false
		fx := Round(w.x + w.w / 2), fy := Round(w.y + w.h / 2)
		MouseMove(fx, fy + Px(70), MouseSpeedNow())
		Sleep(150)
		MouseMove(fx, fy, MouseSpeedNow())
		Sleep(80)
		Click()
		FleeConfirm()
		fled := CastWentOut()
		DebugLog("  the Flee click didn't take - clicked it again from below: " (fled ? "fled" : "still in the battle - the round goes on"))
		if (!fled)
			{
			CenterMouse()
			return false
			}
		}
	;(out of mana as well: a potion after it, whatever else it fled for)
	FleeWhy := (InStr(why, "mana") || FleeNoMana >= 2) ? "mana" : "cards", FleeNoCards := 0, FleeNoMana := 0, FleeNoHits := 0
	TrayTip("Fled the battle: " why ". " (FleeWhy = "mana" ? "Drinking a potion (or buying some), then trying again." : "Trying again with a full deck."), "Wizard101 bot", 1)
	return true
	}

;The game's "Are you sure you want to flee?" box (COMBAT - "You will lose all your Mana and won't get credit...", Yes /
;No; 2026-10-23 08:24: never answered, the bot sat 15 minutes before it) answered Yes - read in the middle of the game,
;its Yes clicked where it's read; never with Crowns in sight. True if it was there and Yes was clicked
FleeConfirm()
	{
	Sleep(400)
	fcT := OcrRect(Round(GameLeft + GameW * 0.3), Round(GameTop + GameH * 0.3), Round(GameW * 0.4), Round(GameH * 0.42), "en", 1, &fcLines)
	if (ErrorLevel || !IsObject(fcLines) || !RegExMatch(fcT, "is)sure.{0,30}flee"))
		return false
	if (RegExMatch(fcT, "i)cr[o0]wn"))
		{
		DebugLog("  the game asks to be sure about fleeing, but Crowns are in sight - not clicked")
		return false
		}
	for fcI, fcLine in fcLines
		for fcJ, fcW in fcLine.words
			if (RegExMatch(Trim(fcW.text), "i)^yes[.!]?$"))
				{
				ClickAt(Round(fcW.x + fcW.w / 2), Round(fcW.y + fcW.h / 2), 300)
				DebugLog("  the game asks to be sure about fleeing - Yes at " Round(fcW.x + fcW.w / 2) - GameLeft "," Round(fcW.y + fcW.h / 2) - GameTop)
				return true
				}
	DebugLog("  the game asks to be sure about fleeing, but its Yes can't be read")
	return false
	}

;How many cards are in hand, by the vision helper's read of it this round - only boxes it calls cards (-1: not read
;this round, or there were boxes where the hand should be and none was a card - the hand looked for in the wrong
;place: can't tell; 0 only when the helper saw none at all, hand|0)
FleeHandCount()
	{
	if (LastHandAnswer = "")
		return -1
	n := 0, boxes := 0, none := 0
	Loop Parse, LastHandAnswer, "`n", "`r"
		{
		if (InStr(A_LoopField, "card|") = 1)
			{
			boxes += 1
			f := StrSplit(A_LoopField, "|")
			if (f.Length < 15 || f[15] != "0")
				n += 1
			}
		else if (A_LoopField = "hand|0")
			none := 1
		}
	if (!boxes)
		return none ? 0 : -1
	return n ? n : -1
	}

;Whether the hand holds a hit the bot can cast, or a card that may become one: 1 yes, 0 none, -1 can't tell (the
;hand not read). A hit: one the battle's own look found (hit1-3, hit4 in a boss fight - it's kept for the boss, a
;wand when wands are used), a card the vision helper knows by one of those pictures (greyed out: not enough pips
;yet), or a greyed-out card it doesn't know (learned - maybe into a hit's place - once it's in colour). A Reshuffle
;in hand (when used) counts too: it puts the used cards back in the deck. Not hits: a learned card in no slot (the
;bot never casts one) and a card in colour it doesn't know (it would have been learned). Not-cards (the deck's back,
;the floor) don't count
FleeHandHasHit()
	{
	global
	local n, f, k
	if (hit1 == 1 || hit2 == 1 || hit3 == 1 || (hit4 == 1 && BossChoosen == 1) || (wand == 1 && Stat("usewand")) || (reshuffle == 1 && Stat("usereshuffle")))
		return 1
	if (LastHandAnswer = "")
		return -1
	n := 0
	Loop Parse, LastHandAnswer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] != "card" || f.Length < 12 || (f.Length >= 15 && f[15] = "0"))
			continue
		n += 1, k := f[6]
		if ((k = "" && f[8] = 1) || RegExMatch(k, "i)/hit[123]$") || (RegExMatch(k, "i)/hit4$") && BossChoosen == 1)
			|| (RegExMatch(k, "i)/wand$") && Stat("usewand")) || (RegExMatch(k, "i)^resources/reshuffle$") && Stat("usereshuffle")))
			return 1
		;(a learned hit in no slot: cast when nothing else can go - CastLearnedHit)
		if (InStr(k, "learned/") = 1 && Stat("learnedhits") && LearnIsHit(LearnCardOf(SubStr(k, 9))))
			return 1
		}
	return n ? 0 : -1
	}

;The fewest pips (= mana) a hit of this school's costs (hit1-3; PlayerStats.txt <school>.hitNpips), "" if none
;is known
FleeCheapestHit()
	{
	least := ""
	Loop 3
		{
		k := hitschool ".hit" A_Index "pips"
		if (hitschool != "" && Stats.Has(k) && Stats[k] > 0 && (least = "" || Stats[k] < least))
			least := Stats[k]
		}
	return least
	}

;The Flee button's word under the hand ({x, y, w, h} on the screen), by OCR where DetectUiScale finds Pass and
;Flee; "" if it can't be read
FleeWord()
	{
	OcrRect(GameLeft + GameW // 8, GameTop + Round(GameH * 0.4), GameW * 3 // 4, Round(GameH * 0.45), "en", GameH < 1000 ? 2 : 1, &lines)
	if (ErrorLevel || !IsObject(lines))
		return ""
	for i, line in lines
		for j, word in line.words
			{
			t := RegExReplace(word.text, "[^A-Za-z0-9|]")
			;(right of the middle, where Flee is - Pass is left of it)
			if (RcLooksLike(t, "FLEE") && word.x > ScreenX)
				return word
			}
	return ""
	}

;Out of battle after fleeing (the main loop, spellbook visible): fled for mana - drink a potion, or buy some and
;drink one; fled for cards - nothing to do (the next battle deals a full deck)
FleeAfter()
	{
	global FleeWhy ; (v1 globals it sets)
	if (FleeWhy = "")
		return
	why := FleeWhy, FleeWhy := ""
	if (why != "mana")
		{
		DebugLog("after fleeing: out of cards - the next battle starts with a full deck")
		return
		}
	;(no mana and none to be had: it would only flee every battle - it stops, kept from timing out, as with an
	;empty mana globe: checkmana)
	if (!FleeRefillMana("after fleeing"))
		{
		;(battles only - Autofarmer.ahk, Settings: battlesonly: no hold - the driver takes this wizard into its battles all the
		;same, and a hold would only leave them unplayed: said and an alert, the battles played on - as checkmana)
		if (BattlesOnly())
			{
			DebugLog("after fleeing: no mana and no potion - not holding: battles only is on (Settings), the battles are played on")
			AlertSend("mana", "out of mana", "Fled out of mana, no potion left, and battles only is on (Settings): the bot doesn't go to buy any and plays the battles on - drink or buy some yourself.")
			return
			}
		Respond("Error, It Seems I Have No Mana. Preventing Timeout.")
		TrayTip("Out of mana and couldn't get potions - the bot has stopped (kept from timing out).", "Wizard101 bot", 2)
		AlertSend("mana", "out of mana", "Fled out of mana, and no potion to be had (none left, and buying didn't work) - the bot is holding (kept from timing out) and carries on by itself once there's mana again.")
		afk("mana")
		}
	}

;Mana back: a potion (Ctrl+O), and if that doesn't raise it - none left - a run to buy some, then one (unless
;the run already drank one: PotionAfterBuy). A run that failed isn't tried again for 10 minutes (PotionFailUntil,
;as PotionCheck). True if mana went up
FleeRefillMana(why)
	{
	global AfkRetries, PotionFailUntil ; (v1 globals it sets)
	before := PotionGlobes().mana
	if (FleeDrinkForMana(before))
		{
		DebugLog(why ": drank a potion for mana (" (before = "" ? "?" : before) " -> " PotionGlobes().mana ")")
		AfkRetries := 0
		return true
		}
	if (V1Lt(A_TickCount, PotionFailUntil))  ; (v1: no failed run yet - blank, Potions.ahk's initializer never ran - compared as text: false)
		{
		DebugLog(why ": no potion left, and the last run to buy some failed - not trying again yet")
		return false
		}
	;(battles only - Settings: battlesonly: no run to buy some - it moves nothing out of battle)
	if (BattlesOnly())
		{
		DebugLog(why ": no potion left - not going to buy any: battles only is on (Settings)")
		return false
		}
	DebugLog(why ": no potion left - going to buy some")
	if (PotionRun())
		{
		now := PotionGlobes().mana
		if ((before != "" && now != "" && now > before) || FleeDrinkForMana(now))
			{
			DebugLog(why ": bought potions and drank one for mana")
			AfkRetries := 0
			return true
			}
		}
	else
		PotionFailUntil := A_TickCount + 10 * 60000
	DebugLog(why ": couldn't get mana back (no potions, and the run to buy some didn't work)")
	return false
	}

;Ctrl+O; true if mana (or health, when mana can't be read) went up
FleeDrinkForMana(before)
	{
	ReleaseKeys()
	hpBefore := PotionGlobes().hp
	Send("{Blind}^o")
	Sleep(2500)
	g := PotionGlobes()
	if (before != "" && g.mana != "")
		return g.mana > before
	return (hpBefore != "" && g.hp != "" && g.hp > hpBefore)
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
FleeBlank()
	{
	global FleeNoCards := "", FleeNoMana := "", FleeNoHits := "", FleeWhy := "", FleeHitsRound := "", LearnAll := "", Manual := "", RoundAgain := ""
	global dualmode := "", roundnumber := "", wand := "", GameLeft := "", GameTop := "", hit1 := "", hit2 := "", hit3 := "", hit4 := ""
	global BossChoosen := "", reshuffle := "", LastHandAnswer := ""
	}
