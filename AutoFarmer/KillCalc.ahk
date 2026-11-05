; Kill calculator for AutoFarmer.ahk (AHK v1.1), #Included at the end of Autofarmer.ahk.
; Reads enemy health off the 2D Combat Display nameplates with Windows OCR (Ocr.ahk), predicts
; the minimum (no crit) damage of each hit in hand from PlayerStats.txt plus the boosts we've cast,
; and picks the cheapest hit that kills every enemy. Whenever something can't be trusted it claims
; no kill, so the normal battle code plays the round instead.
; Uses the super-globals declared at the top of #1:: in Autofarmer.ahk: Stats, EnemyHP, BossSlot,
; BossMax, HealthStatus, AppliedBlades, BossTraps (the traps on one enemy: TrapSlot, TrapFoe*), AuraRounds, EnchantedHits,
; PipsNow.

;The game's memory's card boxes against the ones the screen shows (MemBoxCheck - v1.0.0): {"<GameW>x<GameH>": {agree (looks
;in a row they lined up), trusted (3 such: with memclicks:1 the cards are clicked where the memory has them), lastOk}} -
;declared only (a top-level := never runs in an #Included file): blank at start, KillCalcBlank
global MemBox

;Reads PlayerStats.txt (key:value lines, ; starts a comment) on top of built-in defaults. quiet: lines
;that can't be read go to debug.log instead of a message box (reloading while the bot runs)
LoadStats(quiet := false)
	{
	global Stats ; (v1 globals it sets)
	defaults := "damage:130,pierce:0,enemyresist:15,killmargin:15,solotraps:0,reboost:0,discardunaffordable:0,discardunused:1,discardmax:3,learnedhits:1,fleeon:1,healthocr:1,ocrscale:2,platestrip:110"
		. ",blade:35,elementalblade:35,spiritblade:35,blade3:25,blade4:20,sharpen:10"
		. ",trap:40,elementaltrap:30,spirittrap:30,trap3:30,trap4:0,feint:70,potent:10"
		. ",aura:25,enchant1:100,enchant2:225,enchant3:275,enchant4:300,enchant5:100,enchant6:125,enchant7:175,drawneed:100,drawround:3,drawmax:6,pipsave:3,pipsavehealth:50,handsoff:10,handsoffon:1,potionmark:1,potionfromhome:1,navmem:1,planner:0"
		. ",storm.hit1:80,storm.hit2:520,storm.hit3:690,storm.hit4:805"
		. ",fire.hit1:305,fire.hit2:430,fire.hit3:540,fire.hit4:1265"
		. ",myth.hit1:275,myth.hit2:370,myth.hit3:700,myth.hit4:790"
		. ",storm.hit1pips:0,storm.hit2pips:5,storm.hit3pips:7,storm.hit4pips:9"
		. ",fire.hit1pips:4,fire.hit2pips:6,fire.hit3pips:7,fire.hit4pips:6"
		. ",myth.hit1pips:4,myth.hit2pips:6,myth.hit3pips:7,myth.hit4pips:5"
	Stats := V1Obj()
	Loop Parse, defaults, ","
		{
		ParseStat(A_LoopField)
		}
	;(and the Settings window's: Settings.ahk CfgList)
	if (V1IsFunc("CfgList"))
		for each, cfgS in CfgList.Call()
			if (cfgS.Has("def") && !Stats.Has(cfgS.key))
				Stats[cfgS.key] := cfgS.def
	bad := ""
	Loop Read, A_WorkingDir "\PlayerStats.txt"
		{
		if (!ParseStat(A_LoopReadLine))
			{
			bad .= A_LoopReadLine . "`n"
			}
		}
	else
		{
		;(v1: no PlayerStats.txt - no lines read, the defaults kept; v2's Loop Read throws for a missing file without an Else)
		}
	if (bad != "" && quiet)
		DebugLog("PlayerStats.txt lines that couldn't be read (built-in defaults used): " StrReplace(Trim(bad, "`n"), "`n", " | "))
	else if (bad != "")
		{
		MsgBox("These PlayerStats.txt lines couldn't be read, so their built-in defaults are used:`n`n" . bad, "AutoFarmer", 48)
		}
	}

;One key:value line (a trailing % is allowed). Returns false for a line that has something in it but doesn't parse
ParseStat(line)
	{
	line := RegExReplace(line, ";.*")
	if (RegExMatch(line, "^\s*([\w.]+)\s*:\s*(-?\d+(?:\.\d+)?)\s*\x25?\s*$", &m))
		{
		key := StrLower(m[1])
		Stats[key] := m[2] + 0
		return true
		}
	return (Trim(line) == "")
	}

Stat(key)
	{
	;The deck in use's own first (Decks.ahk - only the settings a deck may set)
	if (IsObject(DeckNow) && IsObject(DeckNow.vals) && DeckNow.vals.Has(key))
		return DeckNow.vals[key]
	;A value for one school's wizard first (e.g. myth.damage, myth.pierce for the Myth wizard - each
	;wizard has its own stats), when the battle is being fought as that school
	if (hitschool != "" && !InStr(key, ".") && Stats.Has(hitschool "." key))
		return Stats[hitschool "." key]
	return Stats.Has(key) ? Stats[key] : 0
	}

;A setting as Stat has it - the deck in use's, your school's, the plain one - else def (not in PlayerStats.txt at all)
StatOr(key, def)
	{
	if (IsObject(DeckNow) && IsObject(DeckNow.vals) && DeckNow.vals.Has(key))
		return DeckNow.vals[key]
	if (hitschool != "" && !InStr(key, ".") && Stats.Has(hitschool "." key))
		return Stats[hitschool "." key]
	return Stats.Has(key) ? Stats[key] : def
	}

;Outgoing damage % stat -> multiplier (PvE curve: linear to 150%, then limited towards +200%)
DamageMultiplier(D)
	{
	L := 2.0, k0 := 190, n0 := -40
	if (D <= k0 + n0)
		return 1 + D / 100
	k := Ln((100 * L) / (100 * L - k0)) / k0
	n := Ln(1 - (k0 + n0) / (100 * L)) + k * (k0 + n0)
	return 1 + L - L / Exp(k * D - n)
	}

;Remembers a blade/trap we cast, keyed by card so recasting the same card doesn't count twice: key is BoostKey's
;("storm/blade", "blade3", "elementalblade"...), src "tc" / "item" a treasure or item card's copy ("@tc", "@item" after it -
;the game stacks it with the deck's: a deck Stormblade and a pet's both count, the user 2026-10-24), "+" when it was
;sharpened / potent (bonus). Its % the game's (the card in hand, BoostPctMem) else PlayerStats.txt's (BoostPct)
AddBoost(list, key, bonus, src := "")
	{
	list[key (src != "" ? "@" src : "") (bonus ? "+" : "")] := BoostPctFor(key, src) + bonus
	}

BoostMult(list)
	{
	mult := 1
	for card, pct in list
		{
		mult *= 1 + pct / 100
		}
	return mult
	}

;---- Blades and traps by damage school (TODO.md goal 3, 2026-10-24) ----
;Each hit's damage schools head by head (HitHeads: Hydra's fire, ice and storm - the game's memory, vision\handmem.py,
;read-only), the boosts that fit the planned hit's schools found and cast (BoostSearch, BoostPick), the kill check by
;head (HitDamage: each head times the blades, traps and aura that fit it), the boosts a hit uses up by fit
;(ConsumeBoosts). Without the game's memory: PlayerStats.txt's <school>.hit<N><school> keys, else one head of your
;school - as before

;A boost card's key in AppliedBlades / BossTraps and the used flags (KeyFlags): its slot's name for one every school
;shares (resources\: blade3, blade4, elementalblade, spiritblade, trap3, elementaltrap, spirittrap, feint), "<school>/blade"
;/ "<school>/trap" for a school's own. Balance's own blade and trap are Balanceblade and Hex (balance\blade.png is
;resources\blade3.png): keyed as those, never counted twice
BoostKey(title, dir)
	{
	if (dir = "" || dir = "resources")
		return title
	if (dir = "balance" && (title = "blade" || title = "trap"))
		return (title = "blade") ? "blade3" : "trap3"
	return dir "/" title
	}

;A key without its copy ("@tc", "@item") and "+" (sharpened / potent): "storm/blade@item+" -> "storm/blade"
BoostBase(key)
	{
	return RegExReplace(key, "(@[a-z]+)?\+?$")
	}

;The kind of boost key: "blade" or "trap" ("" neither)
BoostKind(key)
	{
	bkB := BoostBase(key)
	;(trap3 and trap4 too - Hex is trap3: SubStr(bkB, -3) is its last four letters, "rap3")
	if (bkB = "feint" || RegExMatch(bkB, "trap[34]?$"))
		return "trap"
	return SubStr(bkB, -5) = "blade" || RegExMatch(bkB, "^blade[34]$") ? "blade" : ""
	}

;The schools boost card key fits: "all", or a comma list in a-z order, as the game has them (its memory, 2026-10-24:
;Balanceblade, Bladestorm, Hex and Feint boost every school - damage type All -, Elemental Blade / Trap fire, ice and
;storm, Spirit Blade / Trap death, life and myth, a school's blade and trap its own school; the aura: its card's as the
;game read it when cast - AuraSch -, else yours); "" not known (never multiplied, always used up)
BoostSchools(key)
	{
	global hitschool, AuraSch
	bsK := BoostBase(key)
	if (RegExMatch(bsK, "^([a-z]+)/(blade|trap)$", &bsM))
		return bsM[1]
	if (bsK = "elementalblade" || bsK = "elementaltrap")
		return "fire,ice,storm"
	if (bsK = "spiritblade" || bsK = "spirittrap")
		return "death,life,myth"
	if (bsK = "blade3" || bsK = "blade4" || bsK = "trap3" || bsK = "trap4" || bsK = "feint")
		return "all"
	if (bsK = "aura")
		return AuraSch != "" ? AuraSch : hitschool
	;(an older key with no school: your school's)
	if (bsK = "blade" || bsK = "trap")
		return hitschool
	return ""
	}

;Whether boost card key boosts a head of school sch
BoostFits(key, sch)
	{
	bfS := BoostSchools(key)
	return (bfS = "all" || (bfS != "" && sch != "" && InStr("," bfS ",", "," sch ","))) ? 1 : 0  ; (v1: || gave 1 or 0 - v2 InStr's position)
	}

;Whether boost card key fits any of the schools in list (a comma list)
BoostFitsAny(key, list)
	{
	Loop Parse, list, ","
		if (A_LoopField != "" && BoostFits(key, A_LoopField))
			return true
	return false
	}

;The % boost card key adds as PlayerStats.txt has it: a school's own blade / trap - your school's at blade / trap as Stat
;has it (the deck's, your school's, the plain one), another school's at blade.<school> / trap.<school> (a pet's Stormblade
;on a Balance wizard: blade.storm - storm.blade is the Storm wizard's own blade, as Stat has it), else the plain blade /
;trap -, the others at their slot's (blade3, elementalblade, trap3...) as before
BoostPct(key)
	{
	global hitschool
	bpK := BoostBase(key)
	if (!RegExMatch(bpK, "^([a-z]+)/(blade|trap)$", &bpM))
		return Stat(bpK)
	if (bpM[1] = hitschool)
		return Stat(bpM[2])
	return Stats.Has(bpM[2] "." bpM[1]) ? Stats[bpM[2] "." bpM[1]] : Stats.Has(bpM[2]) ? Stats[bpM[2]] : 0
	}

;The % boost key's copy src ("" the deck's, "tc", "item") adds: the least of its cards in the game's hand this look
;(BoostSearch - a pet's 40% Mythblade at 40), else PlayerStats.txt's (BoostPct)
BoostPctFor(key, src := "")
	{
	global BoostPctMem
	bpfK := BoostBase(key)
	if (IsObject(BoostPctMem))
		{
		if (BoostPctMem.Has(bpfK "@" (src = "" ? "deck" : src)))
			return BoostPctMem[bpfK "@" (src = "" ? "deck" : src)]
		if (BoostPctMem.Has(bpfK))
			return BoostPctMem[bpfK]
		}
	return BoostPct(bpfK)
	}

;The boosts in list that fit school sch, multiplied (BoostMult's, only those)
BoostMultFor(list, sch)
	{
	bmfMult := 1
	for bmfKey, bmfPct in list
		if (BoostFits(bmfKey, sch))
			bmfMult *= 1 + bmfPct / 100
	return bmfMult
	}

;"fire:230,ice:230,storm:230" (the helper's heads field; a learned card's flag heads= has + for ,) into out's heads
;({school: least damage}), total and sure (1). False - out untouched - when it isn't all known: "", "?", a school not one
;of the seven, nothing
HeadsParse(text, out)
	{
	if (text = "" || text = "?")
		return false
	hpHeads := V1Obj(), hpTotal := 0
	Loop Parse, text, ",+"
		{
		if (!RegExMatch(Trim(A_LoopField), "^([a-z]+):(\d+)$", &hpM) || !BadgeNumber(hpM[1]))
			return false
		hpHeads[hpM[1]] := (hpHeads.Has(hpM[1]) ? hpHeads[hpM[1]] : 0) + hpM[2], hpTotal += hpM[2]
		}
	if (hpTotal <= 0)
		return false
	out.heads := hpHeads, out.total := hpTotal, out.sure := 1
	return true
	}

;"ice:35,storm:35,fire:35" (the helper's boosts field) -> {sch: "fire,ice,storm" (a-z, as BoostSchools has them) or
;"all", pct: its least %}; "" when it isn't known ("", "?", a school that isn't one)
BoostsParse(text)
	{
	if (text = "" || text = "?")
		return ""
	bpaL := "", bpaPct := "", bpaAll := 0
	Loop Parse, text, ","
		{
		if (!RegExMatch(Trim(A_LoopField), "^([a-z]+):(\d+)$", &bpaM))
			return ""
		if (bpaM[1] = "all")
			bpaAll := 1
		else if (!BadgeNumber(bpaM[1]))
			return ""
		else if (!InStr("`n" bpaL "`n", "`n" bpaM[1] "`n"))
			bpaL .= (bpaL = "" ? "" : "`n") bpaM[1]
		if (bpaPct = "" || bpaM[2] + 0 < bpaPct)
			bpaPct := bpaM[2] + 0
		}
	if (bpaPct = "")
		return ""
	bpaL := Sort(bpaL)
	return V1Obj({sch: bpaAll ? "all" : StrReplace(bpaL, "`n", ","), pct: bpaPct})
	}

;A boost card's % in the game's hand (VisionCards' card): its boosts' least, else its number ("" none)
BoostCardPct(c)
	{
	bcpB := BoostsParse(c.boosts)
	return IsObject(bcpB) ? bcpB.pct : c.num
	}

;Which copy a card in the game's hand is: "" the deck's, "tc" a treasure card, "item" an item card (a pet's, gear's) -
;copies of one boost from each stack in the game
BoostSrcOf(c)
	{
	return c.item ? "item" : c.tc ? "tc" : ""
	}

;The cards of the game's hand (VisionCards' cards) that are boost key's card, as their numbers in cards: its kind (blade /
;trap) and schools (BoostSchools) - those whose boosts weren't read only when no card read for sure is (they match any of
;their kind); one every school shares (blade3, blade4, trap3, feint) only those at its % (PlayerStats.txt's: Balanceblade's
;25, Bladestorm's 20) when any are. Tower Shield (key tower - resources\tower): TowerMatches'. A school's bubble (key
;<school>/bubble - <school>\bubble, a global): BubbleMatches'
BoostMatches(key, cards)
	{
	if (key = "tower")
		return TowerMatches(cards)
	if (RegExMatch(key, "^([a-z]+)/bubble$", &bmBb))
		return BubbleMatches(cards, bmBb[1])
	;(2026-10-26: an absorb - resources\absorb -, a negative aura, your school's prism - <school>\convert)
	if (key = "absorb")
		return AbsorbMatches(cards)
	if (key = "negaura")
		return NegAuraMatches(cards)
	if (RegExMatch(key, "^([a-z]+)/convert$", &bmCv))
		return ConvertMatches(cards, bmCv[1])
	bmOut := [], bmKind := BoostKind(key), bmSch := BoostSchools(key), bmUnsure := []
	if (bmKind = "" || bmSch = "" || !IsObject(cards))
		return bmOut
	for bmI, bmC in cards
		{
		if (bmC.kind != bmKind)
			continue
		bmB := BoostsParse(bmC.boosts)
		if (!IsObject(bmB))
			bmUnsure.Push(bmI)
		else if (bmB.sch = bmSch)
			bmOut.Push(bmI)
		}
	if (!bmOut.Length)
		bmOut := bmUnsure
	if (bmSch = "all" && bmOut.Length)
		{
		bmAt := [], bmWant := BoostPct(key)
		for bmI, bmN in bmOut
			if (BoostCardPct(cards[bmN]) = bmWant)
				bmAt.Push(bmN)
		if (bmAt.Length)
			return bmAt
		}
	return bmOut
	}

;v1.8.0: whether card m of the game's hand (VisionCards' card) is boost key's copy for sure: its kind, its boosts read
;(BoostsParse) with the key's schools - an every-school key's (blade3, blade4, trap3, feint) at its % (BoostPct) -, not
;one of BoostMatches' fallbacks (boosts not read: any card of the kind; no card at an every-school key's %: every one).
;Autofarmer.ahk DiscardSpent counts and BoostMemDiscard(key, 1) clicks only these
BoostSureOf(key, m)
	{
	if (!IsObject(m) || m.kind != BoostKind(key))
		return false
	bsoB := BoostsParse(m.boosts)
	return IsObject(bsoB) && bsoB.sch = BoostSchools(key) && (bsoB.sch != "all" || bsoB.pct = BoostPct(key))
	}

;The cards of the game's hand (VisionCards' cards) that are a Tower Shield (resources\tower - cast on yourself or an ally
;as Tower Shield), as their numbers in cards: a shield (kind ward) the game names Tower Shield - the deck's, a treasure or
;an item card's; none so named: a shield card (the game's type Ward) for one wizard against every school - its text as
;the helper writes it, "-50% to next spell" (no school named, not "(all of you)"; a school's shield - Fire Shield, Spirit
;Shield - only stops that school's hits, and a ramp's shield is another kind of card). [] none
TowerMatches(cards)
	{
	twmOut := [], twmAny := []
	if (!IsObject(cards))
		return twmOut
	for twmI, twmC in cards
		{
		if (twmC.kind != "ward")
			continue
		if (RegExMatch(twmC.display "|" twmC.name, "i)\btower\s*shield\b"))
			twmOut.Push(twmI)
		else if (twmC.type = "ward" && RegExMatch(Trim(twmC.text), "i)^-\d+%\s*to next spell$"))
			twmAny.Push(twmI)
		}
	return twmOut.Length ? twmOut : twmAny
	}

;The slot a boost of kind ("blade" / "trap") boosting schools sch (BoostsParse's - "fire,ice,storm", "all") at pct % is
;cast from: "<school>\blade", "resources\elementalblade", "resources\blade3" (every school: by its % - Balanceblade's,
;Bladestorm's, Hex's, Feint's as PlayerStats.txt has them)... "" none (Balance alone - its own are blade3, trap3 -, two
;schools, another %). For school wsch's wizard (its numbers)
BoostSlotFor(kind, sch, pct, wsch := "")
	{
	if (sch = "fire,ice,storm")
		return "resources\elemental" kind
	if (sch = "death,life,myth")
		return "resources\spirit" kind
	if (sch = "all")
		{
		for bsfI, bsfK in (kind = "blade" ? ["blade3", "blade4"] : ["trap3", "feint"])
			if (pct != "" && pct + 0 = BoostStatOf(wsch, bsfK))
				return "resources\" bsfK
		return ""
		}
	return (BadgeNumber(sch) && sch != "balance") ? sch "\" kind : ""
	}

;PlayerStats.txt's key for school sch's wizard (<sch>.key), else the plain key ("" none)
BoostStatOf(sch, key)
	{
	if (sch != "" && Stats.Has(sch "." key))
		return Stats[sch "." key]
	return Stats.Has(key) ? Stats[key] : ""
	}

;The used flags of boost key (used<n>: UseBlade's / UseTrap's Use1 - sharpened / potent - and Use2 - plain - for its
;deck copy, cast once each a battle): [n1, n2], "" none. Every school's own blade and trap its pair (balance: blade3,
;trap3); 0, 3, 4, 11, 12 and 20 aren't used any more (19: Party.ahk PartyShield's)
KeyFlags(key)
	{
	static kfT := ""
	if (!IsObject(kfT))
		kfT := V1Obj({feint: [1, 2], elementaltrap: [5, 6], trap3: [7, 8], trap4: [9, 10], elementalblade: [13, 14], blade3: [15, 16]
			, blade4: [17, 18], spiritblade: [49, 50], spirittrap: [51, 52]})
	kfB := BoostBase(key)
	if (kfT.Has(kfB))
		return kfT[kfB]
	if (RegExMatch(kfB, "^([a-z]+)/(blade|trap)$", &kfM) && kfM[1] != "balance" && (kfN := BadgeNumber(kfM[1])))
		return (kfM[2] = "blade") ? [21 + 4 * (kfN - 1), 22 + 4 * (kfN - 1)] : [23 + 4 * (kfN - 1), 24 + 4 * (kfN - 1)]
	return ""
	}

;The boost key used flag n belongs to ("" none: 19 is the tower's)
FlagKey(n)
	{
	for fkI, fkK in ["feint", "elementaltrap", "trap3", "trap4", "elementalblade", "blade3", "blade4", "spiritblade", "spirittrap"
		, "storm/blade", "storm/trap", "fire/blade", "fire/trap", "myth/blade", "myth/trap", "ice/blade", "ice/trap"
		, "life/blade", "life/trap", "death/blade", "death/trap"]
		{
		fkF := KeyFlags(fkK)
		if (IsObject(fkF) && (fkF[1] = n || fkF[2] = n))
			return fkK
		}
	return ""
	}

;The battle code's used flag n (used<n>, a global: here so a function's own doesn't take its place)
UsedFlag(n)
	{
	global
	;(v2 port: v1 made used1..used52 dynamically - v2 reaches only a variable that exists: declared here, for this,
	;UsedFlagSet, Autofarmer.ahk ResetUsed and Party.ahk's used%n%)
	global used1, used2, used3, used4, used5, used6, used7, used8, used9, used10, used11, used12, used13, used14, used15, used16, used17, used18, used19, used20, used21, used22, used23, used24, used25, used26
		, used27, used28, used29, used30, used31, used32, used33, used34, used35, used36, used37, used38, used39, used40, used41, used42, used43, used44, used45, used46, used47, used48, used49, used50, used51, used52
	try
		return used%n%
	catch
		return ""  ; (v1: a flag not set yet read blank)
	}

UsedFlagSet(n, v)
	{
	global
	used%n% := v
	}

;A hit's damage by school - its heads (Hydra: fire, ice and storm, 230 each): {heads: {school: least damage}, total, sure
;(1: its schools are known - the game's or yours; 0: taken as your school's, as always), xpip (its numbers a pip's), src
;(for the log), one (1 one enemy, 0 all, "" not known), item (1 an item card - never enchanted)}. Looked at once a look at
;the hand (HeadsMemo, emptied at FindCards) - HitHeadsFind
HitHeads(hitName)
	{
	global hitschool, HeadsMemo
	if (!IsObject(HeadsMemo))
		HeadsMemo := V1Obj()
	if (!HeadsMemo.Has(hitName "|" hitschool))
		HeadsMemo[hitName "|" hitschool] := HitHeadsFind(hitName)
	return HeadsMemo[hitName "|" hitschool]
	}

;HitHeads' look, in this order: the game's memory - the card on the slot's picture (SlotGame: its name in the game, from
;CardLearn.ahk LearnCards' look at the hand; else the slot's learned card's flag game=), the card itself in the game's hand
;(VisionCards: its heads field); the slot's learned card's heads as the game had them (flag heads=); PlayerStats.txt's
;<school>.<hit><head's school> keys (balance.hit3fire:230, balance.hit3ice:230, balance.hit3storm:230) while they add up
;to <school>.<hit> (or it isn't set); else one head of your school, <school>.<hit> (sure 0). A learned card with a number
;you set on the Spells tab (flag user): the game's schools, your number (HeadsToYours)
HitHeadsFind(hitName)
	{
	global hitschool, SlotGame, BoostSaid
	hhOut := V1Obj({heads: V1Obj(), total: 0, sure: 0, xpip: 0, src: "", one: "", item: (hitName = "wand") ? 1 : 0})
	if (hitschool = "")
		return hhOut
	hhName := IsObject(SlotGame) ? SlotGame[hitschool "/" hitName] : ""
	hhLc := V1IsFunc("LearnCardInSlot") ? LearnCardInSlot.Call(hitschool "\" hitName) : ""
	if (hhName = "" && IsObject(hhLc))
		hhName := LearnFlag.Call(hhLc, "game")
	if (hhName != "" && V1IsFunc("VisionCards"))
		{
		;(the hand read this look - no new read)
		hhHand := VisionCards.Call(300, 5000)
		if (IsObject(hhHand))
			for hhI, hhM in hhHand.cards
				if ((V1IsFunc("LearnMemGame") ? LearnMemGame.Call(hhM) : hhM.name) = hhName && (hhM.kind = "damage" || hhM.kind = "aoe") && HeadsParse(hhM.heads, hhOut))
					{
					hhOut.xpip := (hhM.xpip && hitName != "wand") ? 1 : 0, hhOut.src := "the game", hhOut.one := (hhM.kind = "damage") ? 1 : 0
					hhOut.item := (hhM.item || hitName = "wand") ? 1 : 0
					;(the slot's learned card - this card, by its game name - with a number you set on the Spells tab: yours)
					if (IsObject(hhLc) && LearnHasFlag.Call(hhLc, "user") && V1IsFunc("LearnHitBase")
						&& (LearnFlag.Call(hhLc, "game") = "" || LearnFlag.Call(hhLc, "game") = hhName))
						HeadsToYours(hhOut, LearnHitBase.Call(hhLc))
					return hhOut
					}
		}
	if (IsObject(hhLc) && HeadsParse(LearnFlag.Call(hhLc, "heads"), hhOut))
		{
		hhOut.xpip := (LearnHasFlag.Call(hhLc, "xpip") && hitName != "wand") ? 1 : 0, hhOut.src := "the game (learned card)"
		hhOut.item := (LearnHasFlag.Call(hhLc, "item") || hitName = "wand") ? 1 : 0
		if (LearnHasFlag.Call(hhLc, "user") && V1IsFunc("LearnHitBase"))
			HeadsToYours(hhOut, LearnHitBase.Call(hhLc))
		return hhOut
		}
	hhOut.xpip := (hitName != "wand" && Stat(hitschool "." hitName "pips") = 0) ? 1 : 0
	;(PlayerStats.txt's heads only while they add up to <school>.<hit>, or it isn't set - the learner writes both, CardLearn.ahk
	;LearnStats: a number put there since - the Settings window, another card in the slot, the picture cut again - is the
	;slot's card now, not the old heads)
	hhSum := 0, hhPer := V1Obj()
	for hhI, hhS in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
		if ((hhV := Stat(hitschool "." hitName hhS)) > 0)
			hhPer[hhS] := hhV, hhSum += hhV
	hhV := Stat(hitschool "." hitName)
	if (hhSum > 0 && (hhV <= 0 || hhV = hhSum))
		{
		hhOut.heads := hhPer, hhOut.total := hhSum, hhOut.sure := 1, hhOut.src := "PlayerStats.txt"
		return hhOut
		}
	if (hhSum > 0 && IsObject(BoostSaid) && !BoostSaid.Has("heads|" hitschool "." hitName))
		BoostSaid["heads|" hitschool "." hitName] := 1, DebugLog("  PlayerStats.txt: the heads of " hitschool "." hitName " (" HeadsText(V1Obj({heads: hhPer}))
			. ") add up to " hhSum ", not its " hitschool "." hitName ":" hhV " - left out, one head of your school counted")
	if (hhV > 0)
		hhOut.heads[hitschool] := hhV, hhOut.total := hhV, hhOut.src := "your school's"
	return hhOut
	}

;A hit's heads (HitHeads') brought to number uv you set for its learned card on the Spells tab (flag user - never what you
;set, as CardLearn.ahk LearnHitBase): each head its share of uv, floored, what that leaves on the biggest - the game's
;schools, your number. Not when uv isn't a number above 0 or is their total already
HeadsToYours(hh, uv)
	{
	if (uv = "" || !(uv > 0) || hh.total <= 0 || uv = hh.total)
		return
	htyOut := V1Obj(), htySum := 0, htyBig := ""
	for htyS, htyB in hh.heads
		{
		htyOut[htyS] := Floor(htyB * uv / hh.total), htySum += htyOut[htyS]
		if (htyBig = "" || htyB > hh.heads[htyBig])
			htyBig := htyS
		}
	htyOut[htyBig] += uv - htySum
	hh.heads := htyOut, hh.total := uv + 0, hh.src := "your value (the game's schools)"
	}

;A learned hit's heads (LearnedHitDamage, ConsumeBoosts after one): as the game had them (flag heads=) - a number you set
;on the Spells tab (flag user) kept: the game's schools, your number (HeadsToYours) -, else one head of its own school
;(flag school=, the Spells tab - one of the seven) or yours, its least damage (LearnHitBase)
LearnHitHeads(c)
	{
	global hitschool
	lhOut := V1Obj({heads: V1Obj(), total: 0, sure: 0, xpip: 0, src: "", one: "", item: 0})
	if (!IsObject(c))
		return lhOut
	lhOut.xpip := (V1IsFunc("LearnHasFlag") && LearnHasFlag.Call(c, "xpip")) ? 1 : 0
	lhOut.item := (V1IsFunc("LearnHasFlag") && LearnHasFlag.Call(c, "item")) ? 1 : 0
	if (V1IsFunc("LearnFlag") && HeadsParse(LearnFlag.Call(c, "heads"), lhOut))
		{
		lhOut.src := "the game (learned card)"
		if (V1IsFunc("LearnHasFlag") && LearnHasFlag.Call(c, "user") && V1IsFunc("LearnHitBase"))
			HeadsToYours(lhOut, LearnHitBase.Call(c))
		return lhOut
		}
	lhBase := V1IsFunc("LearnHitBase") ? LearnHitBase.Call(c) : ""
	if (lhBase = "" || lhBase <= 0)
		return lhOut
	lhS := V1IsFunc("LearnFlag") ? LearnFlag.Call(c, "school") : ""
	lhS := BadgeNumber(lhS) ? lhS : hitschool
	lhOut.heads[lhS] := lhBase, lhOut.total := lhBase, lhOut.src := "its school's"
	return lhOut
	}

;Least damage of a hit with heads hh (HitHeads'): each head times per (an X-pip hit's pips) with the boosts that fit its
;school (HitDamageFrom), floored and added; the enchant's add (once - it's one card) on the head where it adds the least
HeadsDamage(hh, per, add, toBoss)
	{
	hdD := V1Obj(), hdSum := 0
	for hdS, hdB in hh.heads
		hdD[hdS] := HitDamageFrom(hdB * per, toBoss, hdS), hdSum += hdD[hdS]
	if (add <= 0)
		return hdSum
	hdBest := ""
	for hdS, hdB in hh.heads
		{
		hdT := hdSum - hdD[hdS] + HitDamageFrom(hdB * per + add, toBoss, hdS)
		if (hdBest = "" || hdT < hdBest)
			hdBest := hdT
		}
	return hdBest = "" ? 0 : hdBest
	}

;"fire 230 + ice 230 + storm 230 (the game)" - a hit's heads for the log
HeadsText(hh)
	{
	htOut := ""
	for htS, htB in hh.heads
		htOut .= (htOut = "" ? "" : " + ") htS " " htB
	return htOut (hh.src != "" ? " (" hh.src ")" : "")
	}

;The heads' schools, your school first, then as BadgeNumber orders them: [school...]
HeadsOrder(heads)
	{
	global hitschool
	hoOut := []
	if (IsObject(heads) && heads.Has(hitschool))
		hoOut.Push(hitschool)
	for hoI, hoS in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		if (hoS != hitschool && IsObject(heads) && heads.Has(hoS))
			hoOut.Push(hoS)
	return hoOut
	}

;The blade and trap groups of schools list: "elemental" (fire, ice, storm), "spirit" (myth, life, death), each once, in
;list's order - Balance has none
PlanGroups(list)
	{
	pgOut := [], pgSeen := ","
	for pgI, pgS in list
		{
		pgG := SchoolGroup(pgS)
		if ((pgG = "elemental" || pgG = "spirit") && !InStr(pgSeen, "," pgG ","))
			pgOut.Push(pgG), pgSeen .= pgG ","
		}
	return pgOut
	}

;Whether a copy of boost key (its src: "" the deck's, "tc", "item") can still be cast: the deck's sharpened (sharp: a
;Sharpen / Potent in hand; never an item card's) while use1 isn't set, plain while use2 isn't; a treasure or item card's
;once a battle (BoostSrcUsed) - it stacks with the deck's
BoostCopyCanGo(key, src, item, sharp, use1, use2)
	{
	global BoostSrcUsed
	if (src = "")
		return (sharp && !item && use1 != 1) || use2 != 1
	return !(IsObject(BoostSrcUsed) && BoostSrcUsed.Has(BoostBase(key) "@" src))
	}

;Whether boost key can still go this round: a copy of it in the game's hand that can (BoostHand, BoostCopyCanGo); without
;it, as ever - its sharpened cast (a Sharpen / Potent in hand) or its plain one not used this battle
BoostCanGo(key)
	{
	global
	local bcgF, bcgI, bcgC, bcgSharp
	bcgF := KeyFlags(key)
	if (!IsObject(bcgF))
		return false
	if (BoostKind(key) = "trap")
		{
		if (TrapOn != 1)
			return false
		bcgSharp := (potent == 1)
		}
	else
		bcgSharp := (sharpen == 1)
	if (IsObject(BoostHand) && BoostHand.Has(key))
		{
		for bcgI, bcgC in BoostHand[key]
			if (BoostCopyCanGo(key, bcgC.src, bcgC.item, bcgSharp, UsedFlag(bcgF[1]), UsedFlag(bcgF[2])))
				return true
		return false
		}
	return (bcgSharp && UsedFlag(bcgF[1]) != 1) || UsedFlag(bcgF[2]) != 1
	}

;The card boxes of a fresh look at the hand (CardLearn.ahk LearnHandRead), each with the game's card on it - VisionCards',
;left to right, only when they're as many: [{l, t, w, h, known, grey (1: greyed out), m, n (its number in the game's
;hand)}]; "" they aren't, or either isn't there. bbWait: how long the game's hand may still be changing (VisionCards)
BoostBoxes(bbWait := 300)
	{
	bbHand := V1IsFunc("VisionCards") ? VisionCards.Call(bbWait, 5000) : ""
	if (!IsObject(bbHand) || !V1IsFunc("LearnHandRead"))
		return ""
	bbAns := LearnHandRead.Call()
	bbOut := []
	Loop Parse, bbAns, "`n", "`r"
		{
		bbF := StrSplit(A_LoopField, "|")
		if (bbF.Length < 12 || bbF[1] != "card" || (bbF.Length >= 15 && bbF[15] = "0"))
			continue
		bbOut.Push(V1Obj({l: bbF[2] + 0, t: bbF[3] + 0, w: bbF[4] + 0, h: bbF[5] + 0, known: bbF[6], grey: bbF[8] = 1 ? 1 : 0}))
		}
	if (!bbOut.Length || bbOut.Length != bbHand.cards.Length)
		return ""
	for bbI, bbB in bbOut
		bbB.m := bbHand.cards[bbI], bbB.n := bbI
	return V1Obj({boxes: bbOut, hand: bbHand})
	}

;---- A boost no picture finds, cast where the game's memory has it (2026-10-24) ----
;The game's hand (read-only) names a blade or trap no picture found - the slot's picture missing, an 8x8 placeholder, or one
;the helper can't match on every copy (debug.log: "in hand (the game): Balanceblade ... no picture found it"): BoostSearch
;notes it (BoostMemOnly) when this look's search is for it, BoostPick plans with it as with any found, and UseBlade / UseTrap
;cast it at its card box (BoostMemBox) - only while the boxes and the game's cards line up for sure

;The key of the boost cast from slot ("resources\blade3" -> "blade3", "storm\blade" -> "storm/blade" - BoostKey's); "" none
BoostMemKey(slot)
	{
	if (slot = "")
		return ""
	SplitPath(slot, &bmkName, &bmkDir)
	return BoostKey(bmkName, bmkDir)
	}

;Whether this look's boost search (BoostSearch) is for boost key, the schools wanted being want: a school's own blade or
;trap of a school in it (not Balance's - its own are blade3, trap3), a group's (elemental, spirit) of a group of them, every
;school's (blade3, blade4, trap3, feint) always - as FindCards and BoostSearch look for them by their pictures
BoostMemWanted(key, want)
	{
	if (RegExMatch(key, "^([a-z]+)/(blade|trap)$", &bmwM))
		{
		for bmwI, bmwS in want
			if (bmwS = bmwM[1] && bmwS != "balance")
				return true
		return false
		}
	if (RegExMatch(key, "^(elemental|spirit)(blade|trap)$", &bmwM))
		{
		for bmwI, bmwG in PlanGroups(want)
			if (bmwG = bmwM[1])
				return true
		return false
		}
	return (key = "blade3" || key = "blade4" || key = "trap3" || key = "feint")
	}

;What kind of card a hand box the helper knows by picture known holds (/hand's known: "balance/hit3", "resources/blade3",
;"learned/<id>") - BoostMemBox's check that the boxes and the game's cards line up: "hit", "boost" (a blade, trap or aura),
;"heal", "ward", "enchant"; "" not known for sure (no picture, a kind it doesn't tell, a learned card whose kind was only
;read off it - flag mem: the game's)
BoostBoxSays(known)
	{
	if (known = "")
		return ""
	if (InStr(known, "learned/") = 1)
		{
		bxsC := V1IsFunc("LearnCardOf") ? LearnCardOf.Call(SubStr(known, 9)) : ""
		if (!IsObject(bxsC) || !V1IsFunc("LearnHasFlag") || !LearnHasFlag.Call(bxsC, "mem"))
			return ""
		return BoostKindSays(bxsC.type)
		}
	bxsN := SubStr(known, (InStr(known, "/", false, -1) + 1)<1 ? (InStr(known, "/", false, -1) + 1)-1 : (InStr(known, "/", false, -1) + 1))
	if (RegExMatch(bxsN, "^(hit[1-4]|wand)$"))
		return "hit"
	if (bxsN = "feint" || bxsN = "aura" || RegExMatch(bxsN, "(blade|trap)[34]?$"))
		return "boost"
	if (RegExMatch(bxsN, "^heal[12]$"))
		return "heal"
	if (bxsN = "tower")
		return "ward"
	if (RegExMatch(bxsN, "^(sharpen|potent|enchant|strong|giant|monstrous|gargantuan|colossal|epic)$"))
		return "enchant"
	;(2026-10-26: an absorb's learned slot - a shield's word, as its kind's: BoostKindSays)
	if (bxsN = "absorb")
		return "ward"
	return ""
	}

;The same for a kind (the game's - VisionCards' kind - or a learned card's): "hit" damage / aoe, "boost" blade / trap /
;aura, "heal", "ward", "enchant" (a Sharpened Blade / Potent Trap too - their pictures' word); "" any other (damage over
;time, keep - the game's effects cut short -...). An absorb says "ward" and a negative aura "boost" (the review,
;2026-10-26): they were keep and trap before they had kinds of their own, and a shield's or trap's picture on one -
;Tower Shield's on a Spirit Armor, Hex's on an Attenuate - isn't boxes out of line (that would stop every cast at a card
;box that round); which card is which is still told apart by the casts themselves (AbsorbMatches, NegAuraMatches)
BoostKindSays(kind)
	{
	if (kind = "damage" || kind = "aoe")
		return "hit"
	if (kind = "blade" || kind = "trap" || kind = "aura" || kind = "negaura")
		return "boost"
	if (kind = "sharpen" || kind = "potent")
		return "enchant"
	if (kind = "absorb")
		return "ward"
	return (kind = "heal" || kind = "ward" || kind = "enchant") ? kind : ""
	}

;Where boost key's card is in hand when no picture found it (UseBlade, UseTrap): a fresh look at the hand's card boxes laid
;on the game's cards (BoostBoxes: the game's hand settled, as many boxes as cards, left to right), the first box holding a
;copy of it (BoostMatches) that can go now (BoostCopyCanGo - sharp: a Sharpen / Potent in hand; use1, use2: its deck copy's
;used flags), not greyed out nor one the game says can't be cast - and only while the pairing is sure: no box the bot knows
;by a picture holds a card of another kind than the picture says (BoostBoxSays: a hit's picture on a blade - the boxes don't
;line up), and this box's own picture, if it has one, is this card's - or a card's the game's hand doesn't hold at all, a
;false match (BoostMemBoxOk). ench 1: only a copy with an
;enchantment on it (the one just sharpened - BoostSettleMem); wait: how long the game's hand may still be changing.
;{x, y (the box's middle - ClickAt goes there from above the hand: MoveToCard), n, of (the box's number, how many), src (""
;the deck's, "tc", "item"), item, name (the game's), ench (1: it carries an enchantment already), note (for the log: its
;box's false picture match, "" none)}; {x: "", why} none
BoostMemBox(key, sharp, use1, use2, ench := 0, wait := 300)
	{
	global VisionCardsWhy
	;(no card zoomed up under the mouse when the hand's boxes are read - CardLearn.ahk; the round's CenterMouse is off it)
	if (V1IsFunc("LearnMouseClear"))
		LearnMouseClear.Call()
	;(v1.0.0: the game's memory's own boxes with memclicks:1, once they've been seen lining up with the screen's at this window
	;size - HandBoxes; else a fresh look at the hand's boxes laid on the game's cards, as ever)
	bmbAll := HandBoxes(wait)
	if (!IsObject(bmbAll))
		return V1Obj({x: "", why: "the hand's card boxes and the game's cards don't line up (" (VisionCardsWhy != "" ? VisionCardsWhy : "not as many, or the hand not read") ")"})
	;(the boxes known by a picture: each one's card the kind its picture says - BoxesLineUp)
	if (!BoxesLineUp(bmbAll, &bmbOff))
		return V1Obj({x: "", why: bmbOff})
	bmbIdx := V1Obj()
	for bmbI, bmbN in BoostMatches(key, bmbAll.hand.cards)
		bmbIdx[bmbN] := 1
	bmbWhy := "no copy of it among the game's cards now", bmbEnc := "", bmbNote := ""
	for bmbI, bmbB in bmbAll.boxes
		{
		if (!bmbIdx.Has(bmbB.n))
			continue
		bmbM := bmbB.m, bmbNm := BoostMemName(bmbM)
		if (ench && bmbM.ench = "")
			{
			bmbWhy := "no copy of it with an enchantment on it"
			continue
			}
		if (!BoostMemBoxOk(key, bmbB.known, bmbNm, bmbAll.hand.cards))
			{
			bmbWhy := "its box (" bmbI ") is known as " bmbB.known " - another card's picture"
			continue
			}
		;(its box's picture another card's that the game's hand doesn't hold at all: a false match - said with the cast; a box
		;from the game's memory - memclicks - said so)
		bmbNote := BoostMemBoxOk(key, bmbB.known, bmbNm) ? "" : " - its box was known as " bmbB.known ", a card the game's hand doesn't hold (a false picture match)"
		bmbNote .= bmbAll.mem ? " - its box where the game's memory has it (memclicks)" : ""
		if (bmbB.grey || bmbM.castable = "0")
			{
			bmbWhy := "it's greyed out (not enough pips)"
			continue
			}
		bmbSrc := BoostSrcOf(bmbM), bmbItem := bmbM.item ? 1 : 0
		;(a copy already enchanted goes on its plain or its sharpened flag, whichever is free - as UseBlade / UseTrap cast it)
		if (!ench && !BoostCopyCanGo(key, bmbSrc, bmbItem, (bmbM.ench != "") ? 1 : sharp, use1, use2))
			{
			bmbWhy := "each copy's casts used this battle"
			continue
			}
		;(ench 0: a plain copy first - one that carries an enchantment already can't take a Sharpen / Potent: it's cast as it
		;is only when no plain copy can go - ench 1 in the answer, UseBlade / UseTrap)
		bmbAt := V1Obj({x: Round(bmbB.l + bmbB.w / 2), y: Round(bmbB.t + bmbB.h / 2), n: bmbI, of: bmbAll.boxes.Length, src: bmbSrc, item: bmbItem, name: bmbNm, ench: (bmbM.ench != "") ? 1 : 0, note: bmbNote})
		if (ench || !bmbAt.ench)
			return bmbAt
		if (!IsObject(bmbEnc))
			bmbEnc := bmbAt
		}
	return IsObject(bmbEnc) ? bmbEnc : V1Obj({x: "", why: bmbWhy})
	}

;Whether a hand box known as picture known can hold boost key's card the game names name (BoostMemBox): no picture; a
;learned card's the game named so (flag game=) or never named; a slot's - a learned card there the game named so, else the
;slot's own key is key (resources/blade3 for Balanceblade). cards (the game's hand, VisionCards' cards): a picture of a
;card the game's hand doesn't hold at all - no card of the name the game gave it, no copy of its slot's boost - is a false
;match, and doesn't keep the game's card from its box (2026-10-25: Balanceblade's picture named the Bladestorm box with no
;Balanceblade in hand - Bladestorm not cast in 41 rounds that day); the boxes still have to line up (BoostMemBox: as many as
;the cards, each known box's kind the game's)
BoostMemBoxOk(key, known, name, cards := "")
	{
	if (known = "")
		return true
	bmoC := ""
	if (InStr(known, "learned/") = 1)
		bmoC := V1IsFunc("LearnCardOf") ? LearnCardOf.Call(SubStr(known, 9)) : ""
	else if (V1IsFunc("LearnCardInSlot"))
		bmoC := LearnCardInSlot.Call(StrReplace(known, "/", "\"))
	bmoG := (IsObject(bmoC) && V1IsFunc("LearnFlag")) ? LearnFlag.Call(bmoC, "game") : ""
	if (bmoG != "")
		return (bmoG = name) || BoostMemNoneOf(bmoG, "", cards)
	if (InStr(known, "learned/") = 1)
		return true
	bmoK := BoostMemKey(StrReplace(known, "/", "\"))
	return (bmoK = key) || BoostMemNoneOf("", bmoK, cards)
	}

;Whether the game's hand (cards: VisionCards' cards) holds no card the game names name - or, name "", no copy of boost key
;(BoostMatches: a blade, trap or Tower Shield; one every school shares read for sure at another % than key's isn't it -
;Bladestorm's 20 isn't Balanceblade's 25; any other key can't be told - false). False without the game's cards
BoostMemNoneOf(name, key, cards)
	{
	if (!IsObject(cards) || !cards.Length)
		return false
	if (name != "")
		{
		for bmnI, bmnC in cards
			if (BoostMemName(bmnC) = name)
				return false
		return true
		}
	if (key = "" || (key != "tower" && BoostKind(key) = ""))
		return false
	bmnPct := (key = "tower") ? "" : BoostPct(key)
	for bmnI, bmnN in BoostMatches(key, cards)
		{
		bmnB := BoostsParse(cards[bmnN].boosts)
		if (bmnPct && IsObject(bmnB) && bmnB.sch = "all" && BoostCardPct(cards[bmnN]) != bmnPct)
			continue
		return false
		}
	return true
	}

;A card of the game's hand by its name, for the log (the name on it - CardLearn.ahk LearnMemGame -, else its own)
BoostMemName(m)
	{
	return V1IsFunc("LearnMemGame") ? LearnMemGame.Call(m) : m.name
	}

;Whether a look's hand boxes (BoostBoxes' or MemBoxes' {boxes, hand}) and the game's cards line up for sure - BoostMemBox,
;BoostMemDiscard: no box the bot knows by a picture holds a card of another kind than its picture says (BoostBoxSays: a
;hit's picture on a blade - the boxes don't line up). why: the box that doesn't
BoxesLineUp(all, &why)
	{
	why := ""
	for bluI, bluB in all.boxes
		{
		bluSays := BoostBoxSays(bluB.known), bluKind := BoostKindSays(bluB.m.kind)
		if (bluSays != "" && bluKind != "" && bluSays != bluKind)
			{
			why := "box " bluI " is known as " bluB.known ", the game has " BoostMemName(bluB.m) " (" bluB.m.kind ") there - the boxes and the game's cards may not line up"
			return false
			}
		}
	return true
	}

;---- Cards where the game's memory has them (v1.0.0, TODO.md goal 3: every card cast by the game's memory) ----
;The helper's /cards gives each card's box in the game's GUI (vision\handmem.py: its window's rect plus every window's
;place on the way down from the root - Vision.ahk VisionCardPx turns it into pixels). Never compared with the screen
;before, so: MemBoxCheck lays those boxes on the ones the helper's /hand saw this round (CardLearn.ahk LearnCards' look,
;LastHandAnswer) and logs the largest gap between their middles - ALWAYS, log only ("Memory card boxes" in debug.log: once
;a window size and picture set, and again when it changes). Three looks in a row within Px(10) at one window size: trusted
;there (MemBoxTrusted) - and only with memclicks:1 in PlayerStats.txt (the Settings window; off: not tried in the game yet)
;are the cards then clicked where the memory has them: Find (MemCardFind), FindEnchant (MemEnchantFind), every cast at a
;card's box (HandBoxes: UseBlade / UseTrap / UseMemAt / ClickBubble / UseNegAura / BoostSettleMem through BoostMemBox,
;BoostCopyPick), the slide after an enchant (MemSettle). One look out of line: not trusted at that size till three in a
;row line up again. memclicks:0 (the default): the screen's boxes and the pictures as before

;One look's check (after CardLearn.ahk LearnCards read the hand off the screen - ans its /hand answer): the game's memory's
;boxes (VisionCards' cards, this look's read) against the screen's, paired as BoostBoxes pairs them (as many, left to right):
;the largest gap between two middles - logged, MemBox kept. Clicks nothing
MemBoxCheck(ans)
	{
	global MemBox ; (v1 globals it sets)
	static said := V1Obj()
	if (ans = "" || !V1IsFunc("VisionCards") || !V1IsFunc("VisionCardPx"))
		return
	;(the look's own read - LearnCards' LearnMemHand read it, 3 s at most)
	mbcHand := VisionCards.Call(300, 3000)
	if (!IsObject(mbcHand) || !mbcHand.cards.Length)
		return
	mbcBoxes := []
	Loop Parse, ans, "`n", "`r"
		{
		mbcF := StrSplit(A_LoopField, "|")
		if (mbcF.Length < 12 || mbcF[1] != "card" || (mbcF.Length >= 15 && mbcF[15] = "0"))
			continue
		mbcBoxes.Push(V1Obj({x: mbcF[2] + mbcF[4] / 2, y: mbcF[3] + mbcF[5] / 2}))
		}
	mbcKey := GameW "x" GameH, mbcSay := mbcKey "|" PicSet
	if (!IsObject(MemBox))
		MemBox := V1Obj()
	if (!MemBox.Has(mbcKey))
		MemBox[mbcKey] := V1Obj({agree: 0, trusted: 0, lastOk: ""})
	mbcS := MemBox[mbcKey]
	;(not as many: a look that doesn't line up - the run of 3 starts again, as with a card that has no box (v1.0.0 review:
	;before, trust could build across a look the counts told apart))
	if (mbcBoxes.Length != mbcHand.cards.Length)
		{
		mbcWas := mbcS.trusted, mbcS.agree := 0, mbcS.trusted := 0
		if (!said.Has(mbcSay "|count") || mbcWas)
			said[mbcSay "|count"] := 1, DebugLog("  Memory card boxes (log only): the screen shows " mbcBoxes.Length " card box(es), the game's memory " mbcHand.cards.Length " card(s) - not compared this look"
				. (mbcWas ? ", and not clicked where the memory has them at this size again till 3 looks in a row line up" : "") " (said once a window size)")
		return
		}
	mbcGap := -1, mbcAt := 0, mbcDx := 0, mbcDy := 0, mbcNo := 0, mbcSays := ""
	for mbcI, mbcB in mbcBoxes
		{
		if (!VisionCardPx.Call(mbcHand, mbcHand.cards[mbcI], &mbcX, &mbcY))
			{
			mbcNo += 1
			continue
			}
		mbcD := Max(Abs(mbcX - mbcB.x), Abs(mbcY - mbcB.y))
		mbcDx += mbcX - mbcB.x, mbcDy += mbcY - mbcB.y
		if (mbcD > mbcGap)
			mbcGap := mbcD, mbcAt := mbcI, mbcSays := "memory " mbcX - GameLeft "," mbcY - GameTop " - screen " Round(mbcB.x - GameLeft) "," Round(mbcB.y - GameTop)
		}
	if (mbcNo)
		{
		mbcS.agree := 0, mbcS.trusted := 0
		if (!said.Has(mbcSay "|nobox"))
			said[mbcSay "|nobox"] := 1, DebugLog("  Memory card boxes (log only): " mbcNo " of " mbcBoxes.Length " cards have no box from the game's memory" (mbcHand.rootW = "" ? " (no root line: an older helper, or the GUI root not read)" : " (not read, or off the window)") " - not compared (said once a window size)")
		return
		}
	mbcN := mbcBoxes.Length, mbcOk := mbcGap <= Px(10), mbcWas := mbcS.trusted, mbcFirst := !said.Has(mbcSay)
	mbcS.agree := mbcOk ? Min(mbcS.agree + 1, 99) : 0
	mbcS.trusted := (mbcS.agree >= 3) ? 1 : 0
	if (mbcFirst || mbcS.trusted != mbcWas || (!mbcOk && mbcS.lastOk != 0))
		DebugLog("  Memory card boxes (log only" (Stat("memclicks") = 1 ? "" : " - memclicks off") "): " mbcN " card(s), the largest gap between the game's memory's box and the screen's "
			. Round(mbcGap) " px (card " mbcAt ": " mbcSays "), on average " Round(mbcDx / mbcN) "," Round(mbcDy / mbcN) " px off - a " GameW "x" GameH " window, the GUI " mbcHand.rootW "x" mbcHand.rootH ", UI " Round(UiScale, 3) ": "
			. (!mbcOk ? "they DON'T line up (more than " Px(10) " px)" (mbcWas ? " - not clicked where the memory has them at this size again till 3 looks in a row line up" : "")
			: mbcS.trusted ? "they line up, 3 looks in a row" (Stat("memclicks") = 1 ? " - cards are clicked where the game's memory has them at this window size from now on" : " - memclicks:1 would click the cards where the game's memory has them")
			: "they line up (" mbcS.agree " of 3 looks in a row)"))
	said[mbcSay] := 1, mbcS.lastOk := mbcOk ? 1 : 0
	}

;Whether cards may be clicked where the game's memory has them now: memclicks:1 and its boxes seen lining up with the
;screen's 3 looks in a row at this window size (MemBoxCheck) - and one game window running (Vision.ahk VisionMemOneClient,
;v1.0.0 review: with two or more navmem can be on another client, whose hand of as many cards lines up just as well)
MemBoxTrusted()
	{
	global MemBox
	if (Stat("memclicks") != 1 || !IsObject(MemBox))
		return false
	mbtS := V1At(MemBox, GameW "x" GameH)
	return IsObject(mbtS) && mbtS.trusted = 1 && V1IsFunc("VisionMemOneClient") && VisionMemOneClient.Call()
	}

;v1.8.0: whether the game's memory's card boxes have been seen lining up with the screen's 3 looks in a row at this window
;size (MemBoxCheck - whatever memclicks says) with one game window running: the screen's boxes laid on the game's cards
;by their place in the hand (BoostBoxes) are then each the card the memory says. Autofarmer.ahk DiscardSpent's
;right-clicks need it
MemBoxLinedUp()
	{
	global MemBox
	mbuS := IsObject(MemBox) ? V1At(MemBox, GameW "x" GameH) : ""
	return IsObject(mbuS) && mbuS.trusted = 1 && V1IsFunc("VisionMemOneClient") && VisionMemOneClient.Call()
	}

;The hand's card boxes from the game's memory alone, in BoostBoxes' shape ({boxes: [{l, t, w, h (pixels), known: "", grey:
;0, m (the game's card), n, mem: 1}], hand, mem: 1}) - every card's box read (VisionCardPx), else "". wait: how long the
;game's hand may still be changing (VisionCards); a read 0.4 s old at most, as VisionFind's look at the screen (places,
;not names: the hand moves after a Sharpen, a discard)
MemBoxes(wait := 300)
	{
	mbHand := (V1IsFunc("VisionCards") && V1IsFunc("VisionCardPx")) ? VisionCards.Call(wait, 400) : ""
	if (!IsObject(mbHand) || !mbHand.cards.Length || mbHand.rootW = "" || mbHand.rootH = "")
		return ""
	mbOut := []
	for mbI, mbM in mbHand.cards
		{
		if (!VisionCardPx.Call(mbHand, mbM, &mbX, &mbY))
			return ""
		mbW := (mbM.r - mbM.l) * GameW / mbHand.rootW, mbH := (mbM.b - mbM.t) * GameH / mbHand.rootH
		mbOut.Push(V1Obj({l: Round(mbX - mbW / 2), t: Round(mbY - mbH / 2), w: Round(mbW), h: Round(mbH), known: "", grey: 0, m: mbM, n: mbI, mem: 1}))
		}
	return V1Obj({boxes: mbOut, hand: mbHand, mem: 1})
	}

;The hand's card boxes for a cast at a card's box (BoostMemBox, BoostCopyPick, BoostMemDiscard): the game's memory's own
;(MemBoxes) while they may be clicked (MemBoxTrusted - memclicks:1), else a fresh look at the screen's laid on the game's
;cards (BoostBoxes), as ever
HandBoxes(wait := 300)
	{
	if (MemBoxTrusted())
		{
		hbMem := MemBoxes(wait)
		if (IsObject(hbMem))
			return hbMem
		}
	return BoostBoxes(wait)
	}

;Where the deck's copy of boost key is in hand to discard it - DiscardCard, for a spare blade no picture finds that the
;game's hand has (BoostMemOnly; before v1.0.0 one was never discarded and stayed in hand): a fresh look at the hand's boxes
;laid on the game's cards (HandBoxes), only while they line up for sure (BoxesLineUp), the first copy (BoostMatches) of the
;deck's - never a treasure card (discarding one uses it up) nor an item card - whose box's picture, if any, can be it
;(BoostMemBoxOk). {x, y (its box's middle), n, of, name, ench, pct}; {x: "", why} none. v1.8.0: weakest 1 (Autofarmer.ahk
;DiscardSpent): only the key's copies for sure (BoostSureOf), the one with no enchantment first, then the weakest
;(BoostCardPct), then the first - never one set to Never discard (the Spells tab: a learned card's hold, as
;BoostMisfitDiscard has it)
BoostMemDiscard(key, weakest := 0)
	{
	global VisionCardsWhy
	if (V1IsFunc("LearnMouseClear"))
		LearnMouseClear.Call()
	bmdAll := HandBoxes(300)
	if (!IsObject(bmdAll))
		return V1Obj({x: "", why: "the hand's card boxes and the game's cards don't line up (" (VisionCardsWhy != "" ? VisionCardsWhy : "not as many, or the hand not read") ")"})
	if (!BoxesLineUp(bmdAll, &bmdOff))
		return V1Obj({x: "", why: bmdOff})
	bmdIdx := V1Obj()
	for bmdI, bmdN in BoostMatches(key, bmdAll.hand.cards)
		bmdIdx[bmdN] := 1
	bmdBest := "", bmdHeld := 0
	for bmdI, bmdB in bmdAll.boxes
		{
		if (bmdB.m.tc || bmdB.m.item || !(weakest ? BoostSureOf(key, bmdB.m) : bmdIdx.Has(bmdB.n))
			|| !BoostMemBoxOk(key, bmdB.known, BoostMemName(bmdB.m), bmdAll.hand.cards))
			continue
		bmdAt := V1Obj({x: Round(bmdB.l + bmdB.w / 2), y: Round(bmdB.t + bmdB.h / 2), n: bmdI, of: bmdAll.boxes.Length
			, name: BoostMemName(bmdB.m), ench: (bmdB.m.ench != "") ? 1 : 0, pct: BoostCardPct(bmdB.m)})
		if (!weakest)
			return bmdAt
		;(DiscardSpent's: never a card you set to Never discard - its box known by a learned card's picture, or a slot's
		;with a learned card in it, flag hold)
		bmdLc := ""
		if (InStr(bmdB.known, "learned/") = 1 && V1IsFunc("LearnCardOf"))
			bmdLc := LearnCardOf.Call(SubStr(bmdB.known, 9))
		else if (bmdB.known != "" && V1IsFunc("LearnCardInSlot"))
			bmdLc := LearnCardInSlot.Call(StrReplace(bmdB.known, "/", "\"))
		if (IsObject(bmdLc) && V1IsFunc("LearnHasFlag") && LearnHasFlag.Call(bmdLc, "hold"))
			{
			bmdHeld += 1
			continue
			}
		;(one with no enchantment before one that carries one - the better cast -, then the weakest, then the first)
		if (!IsObject(bmdBest) || bmdAt.ench < bmdBest.ench || (bmdAt.ench = bmdBest.ench && V1IsNum(bmdAt.pct)
			&& V1IsNum(bmdBest.pct) && bmdAt.pct < bmdBest.pct))
			bmdBest := bmdAt
		}
	if (IsObject(bmdBest))
		return bmdBest
	return V1Obj({x: "", why: "no copy of it from the deck among the game's cards now" (bmdHeld ? " but " bmdHeld " set to Never discard (the Spells tab)" : "")})
	}

;Which card of the game's hand (VisionCards' hand) picture slot dir\title is - Find's look with memclicks (MemCardFind): its
;number in hand.cards, 0 none for sure. A boost slot - a blade, trap, Feint, Tower Shield, absorb, your school's bubble or
;prism (BoostKey): a copy of it (BoostMatches); Sharpen / Potent: a card of that kind; Reshuffle: one the game names so; any
;other slot whose card the game named - a hit's (SlotGame: CardLearn.ahk's look at the hand), else the learned card in the
;slot's (flag game=) - the card of that name (of a hit's kind for hit1-4 and the wand). Not one the game says can't be cast
;(castable 0 - its picture wouldn't match a greyed card either). ench 1: one with an enchantment on it first (after a
;Sharpen, Potent or enchant - MemSettle); ench 0: a plain one first - one that carries an enchantment already only when
;there's none (BoostMemBox's rule, v1.0.0 review: it can't take a Sharpen, Potent or enchant - the game takes no second
;one; its picture wouldn't match it either). An aura or heal no card's named for, an enchant (MemEnchantFind), Pass: 0 -
;by its picture, as before
MemCardFor(dir, title, hand, ench := 0)
	{
	global SlotGame
	if (!IsObject(hand) || !IsObject(hand.cards) || !hand.cards.Length)
		return 0
	mcfKey := BoostKey(title, dir), mcfIs := []
	if (mcfKey = "tower" || mcfKey = "absorb" || BoostKind(mcfKey) != "" || RegExMatch(mcfKey, "^[a-z]+/(bubble|convert)$"))
		mcfIs := BoostMatches(mcfKey, hand.cards)
	else if (title = "sharpen" || title = "potent")
		{
		for mcfI, mcfC in hand.cards
			if (mcfC.kind = title)
				mcfIs.Push(mcfI)
		}
	else if (title = "reshuffle")
		{
		for mcfI, mcfC in hand.cards
			if (RegExMatch(BoostMemName(mcfC) "|" mcfC.name, "i)\breshuffle\b"))
				mcfIs.Push(mcfI)
		}
	else
		{
		mcfName := (IsObject(SlotGame) && dir != "resources") ? V1At(SlotGame, dir "/" title) : ""
		if (mcfName = "" && V1IsFunc("LearnCardInSlot"))
			{
			mcfLc := LearnCardInSlot.Call(dir "\" title)
			if (IsObject(mcfLc))
				mcfName := LearnFlag.Call(mcfLc, "game")
			}
		if (mcfName = "")
			return 0
		mcfHit := RegExMatch(title, "^(hit[1-4]|wand)$")
		for mcfI, mcfC in hand.cards
			if (BoostMemName(mcfC) = mcfName && (!mcfHit || mcfC.kind = "damage" || mcfC.kind = "aoe"))
				mcfIs.Push(mcfI)
		}
	mcfAny := 0
	for mcfI, mcfN in mcfIs
		{
		if (hand.cards[mcfN].castable = "0")
			continue
		if (ench ? hand.cards[mcfN].ench != "" : hand.cards[mcfN].ench = "")
			return mcfN
		if (!mcfAny)
			mcfAny := mcfN
		}
	return mcfAny
	}

;Find's first look (Autofarmer.ahk) with memclicks:1: picture slot dir\title's card where the game's memory has it
;(MemCardFor), its box in pixels (VisionCardPx) - only while the memory's boxes may be clicked (MemBoxTrusted). True: X, Y
;its box's middle less Px(5) each way (Find's callers click X + Px(5), or X itself - a bit up and left of the middle: both on
;the card), ench 1 that copy carries an enchantment already (none plain in hand - UseBlade / UseTrap / UseHit put none on it);
;false, X and Y as they were: Find looks by its picture as ever
MemCardFind(dir, title, &X, &Y, &ench := 0)
	{
	ench := 0
	if (!MemBoxTrusted() || !V1IsFunc("VisionCards") || !V1IsFunc("VisionCardPx"))
		return false
	;(a read 0.4 s old at most - VisionFind's look at the screen serves 0.4 s too: one read for FindCards' every card)
	mcdHand := VisionCards.Call(300, 400)
	mcdN := MemCardFor(dir, title, mcdHand)
	if (!mcdN || !VisionCardPx.Call(mcdHand, mcdHand.cards[mcdN], &mcdX, &mcdY))
		return false
	X := mcdX - Px(5), Y := mcdY - Px(5), ench := (mcdHand.cards[mcdN].ench != "") ? 1 : 0
	return true
	}

;FindEnchant's first look with memclicks:1: the best enchant in the game's hand (EnchantList's order: the enchant card -
;kind enchant - whose name says that level's word: Epic, Colossal...; Epic only once a hitter's known, as FindEnchant has
;it; not one the game says can't be cast) where the memory has it - only while its boxes may be clicked (MemBoxTrusted).
;True: level its enchantN, x, y its box's middle less Px(5) (as MemCardFind's); false, nothing set: by the pictures
MemEnchantFind(&level, &x, &y)
	{
	global hitter
	if (!MemBoxTrusted() || !V1IsFunc("VisionCards") || !V1IsFunc("VisionCardPx") || !V1IsFunc("EnchantList"))
		return false
	mefHand := VisionCards.Call(300, 400)
	if (!IsObject(mefHand) || !mefHand.cards.Length)
		return false
	for mefI, mefE in EnchantList.Call()
		{
		if ((mefE[1] = 4 && hitter = 0) || mefE[3] = "enchant")
			continue
		for mefJ, mefC in mefHand.cards
			if (mefC.kind = "enchant" && mefC.castable != "0" && RegExMatch(BoostMemName(mefC) "|" mefC.name, "i)\b" mefE[3] "\b")
				&& VisionCardPx.Call(mefHand, mefC, &mefX, &mefY))
				{
				level := mefE[1], x := mefX - Px(5), y := mefY - Px(5)
				return true
				}
		}
	return false
	}

;A Sharpen, Potent or enchant was just put on the card dir\title found where the game's memory has it (Find - MemCardFind)
;and the hand re-centres: where the memory has that card once two reads 100 ms apart agree (the slide over - MemCardFor,
;one with the enchantment on it first) - as BoostSettle waits for its picture; not by 1.5 s: where it should be
;(RefindAfterBoost's guess). fx, fy as Find's (the box's middle less Px(5))
MemSettle(dir, title, &fx, &fy, boostX)
	{
	msExp := fx + (fx < boostX ? HalfPitch : -HalfPitch), msLast := "", msT0 := A_TickCount
	Sleep(250)
	while (A_TickCount - msT0 < 1500 && V1IsFunc("VisionCardPx"))
		{
		VisionForget.Call()
		msHand := VisionCards.Call(300, 0)
		msN := MemCardFor(dir, title, msHand, 1)
		if (msN && VisionCardPx.Call(msHand, msHand.cards[msN], &msX, &msY))
			{
			if (msLast = msX "," msY)
				{
				DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " msX - Px(5) - GameLeft "," msY - Px(5) - GameTop " (the game's memory: card " msN " of " msHand.cards.Length ", settled in " A_TickCount - msT0 " ms)")
				fx := msX - Px(5), fy := msY - Px(5)
				return true
				}
			msLast := msX "," msY
			}
		Sleep(100)
		}
	DebugLog("    card not settled in the game's memory after it moved, using where it should be: " msExp - GameLeft "," fy - GameTop)
	fx := msExp
	return false
	}

;Which copy of boost card key in hand the card at x, y is - UseBlade, UseTrap, with the game's hand read (BoostHand):
;{src ("" the deck's, "tc", "item"), item (1: an item card - never sharpened or made potent), moved (1: that copy can't go
;- its casts used this battle - so x, y are now another copy's that can, plain: one moved to is never sharpened)}; "" none
;that's in hand can go. Its copies all one kind (the same src, item card or not), or the boxes and the game's cards not
;lining up: the first kind of its copies that can go, the deck's first - never sharpened if any is an item card
BoostCopyPick(key, &x, &y, sharp, use1, use2)
	{
	;(every copy in hand one kind - as most often, one copy: a fresh look at the hand can't change which goes, so none is
	;asked for - each is a /hand read for the helper, about 0.1 s)
	bcpF := "", bcpOne := 1
	for bcpI, bcpC in BoostHand[key]
		bcpT := bcpC.src "|" (bcpC.item ? 1 : 0), bcpOne := bcpOne && (bcpF = "" || bcpT = bcpF), bcpF := bcpT
	;(and only while the game's hand holds no other blade or trap - a click found on another boost's box is then moved onto
	;the real card by the look; this look's cached hand: no read)
	bcpHand := bcpOne && V1IsFunc("VisionCards") ? VisionCards.Call(300, 5000) : "", bcpN := 0
	if (IsObject(bcpHand))
		for bcpI, bcpC in bcpHand.cards
			bcpN += (bcpC.kind = "blade" || bcpC.kind = "trap") ? 1 : 0
	bcpOne := bcpOne && IsObject(bcpHand) && bcpN = BoostHand[key].Length
	bcpAll := bcpOne ? "" : HandBoxes()
	if (IsObject(bcpAll))
		{
		bcpIs := V1Obj()
		for bcpI, bcpN in BoostMatches(key, bcpAll.hand.cards)
			bcpIs[bcpN] := 1
		bcpAt := "", bcpGo := ""
		for bcpI, bcpB in bcpAll.boxes
			{
			if (!bcpIs.Has(bcpB.n))
				continue
			bcpSrc := BoostSrcOf(bcpB.m), bcpItem := bcpB.m.item ? 1 : 0
			if (x >= bcpB.l - 5 && x <= bcpB.l + bcpB.w + 5)
				bcpAt := V1Obj({src: bcpSrc, item: bcpItem, can: BoostCopyCanGo(key, bcpSrc, bcpItem, sharp, use1, use2), moved: 0})
			;(another copy's box: only one that can go plain - UseBlade / UseTrap never sharpen or make potent a copy moved to)
			else if (!IsObject(bcpGo) && BoostCopyCanGo(key, bcpSrc, bcpItem, 0, use1, use2))
				bcpGo := V1Obj({src: bcpSrc, item: bcpItem, can: 1, moved: 1, x: Round(bcpB.l + bcpB.w / 2), y: Round(bcpB.t + bcpB.h * 0.45)})
			}
		if (IsObject(bcpAt) && bcpAt.can)
			return bcpAt
		if (IsObject(bcpGo))
			{
			x := bcpGo.x, y := bcpGo.y
			DebugLog("  " key ": the copy found can't go again this battle - its " (bcpGo.src = "" ? "deck" : bcpGo.src) " copy instead, at " x - GameLeft "," y - GameTop)
			return bcpGo
			}
		if (IsObject(bcpAt))
			return ""
		}
	;(one kind, or the boxes and the cards don't line up: by the copies BoostSearch saw - each kind of them in turn, the
	;deck's, then an item card's, then a treasure card's: the first that can go, as BoostCanGo has it)
	bcpSrcs := V1Obj(), bcpAny := 0
	for bcpI, bcpC in BoostHand[key]
		bcpSrcs[bcpC.src = "" ? "deck" : bcpC.src] := 1, bcpAny := bcpAny || bcpC.item
	for bcpS in bcpSrcs
		{
		bcpSrc := (bcpS = "deck") ? "" : bcpS
		if (BoostCopyCanGo(key, bcpSrc, bcpAny, sharp, use1, use2))
			return V1Obj({src: bcpSrc, item: bcpAny, can: 1, moved: 0})
		}
	return ""
	}

;The schools of the aura card just cast, as the game's hand has it (AuraSch: "all", "fire,ice" - one aura card in hand
;read for sure), else "" (yours)
BoostAuraSchools()
	{
	basHand := V1IsFunc("VisionCards") ? VisionCards.Call(300, 5000) : ""
	basOut := "", basN := 0
	if (IsObject(basHand))
		for basI, basC in basHand.cards
			if (basC.kind = "aura")
				basN += 1, basB := BoostsParse(basC.boosts), basOut := IsObject(basB) ? basB.sch : ""
	return basN = 1 ? basOut : ""
	}

;FindCards, once the pips are read (and before the hand's read for learning: the helper's /hand must know these pictures,
;or a pictured Storm Blade is learned again): the blades and traps of every school this round's hits need, by their
;pictures - SbFound {"<school>/blade" / "<school>/trap": {x, y}}, GbFound {"elementalblade"...: 1} - and blade, trap,
;blade2, trap2 for the log and the discards (BoostPick picks this round's). The schools: a party battle's blader's or
;healer's - and Alt+2's pick of another school's wizard - the hitter's: its planned hit's (HammerPlan, Party.ahk), else its
;school; else yours, every head of the hits in hand (HitHeads: a Balance Hydra's fire, ice and storm) and of every hit in
;the game's hand. Balance's own blade and trap are Balanceblade and Hex (resources\blade3, trap3): its folder isn't
;searched. With the game's hand read (VisionCards), a picture found for a card that isn't in it is a false match - not
;used -, each boost found counts at the % of its card in hand (BoostPctMem) and its copies are noted (BoostHand: a
;treasure or item card's stacks with the deck's). A blade or trap in the game's hand no picture found, that this search is
;for, is found all the same - by the game's hand (BoostMemOnly): UseBlade / UseTrap cast it at its card box (BoostMemBox)
BoostSearch()
	{
	global
	local bsHand, bsWant, bsSeen, bsI, bsS, bsH, bsHh, bsC, bsF, bsX, bsY, bsG, bsK, bsKeys, bsM, bsJ, bsN, bsP, bsSrc, bsLog, bsTr, bsHas, bsB, bsSlot, bsNm
	local bsMem, bsGo, bsMk
	;(v2 port: the targets of the dynamic %bsK% / %bsK%X / %bsK%Y below - v2 assigns only a variable that exists)
	global blade3, blade4, trap3, feint, Blade3X, Blade3Y, Blade4X, Blade4Y, trap3X, trap3Y, feintX, feintY
	SbFound := V1Obj(), GbFound := V1Obj(), BoostPctMem := V1Obj(), BoostHand := V1Obj(), BoostMemOk := 0, BoostMemOnly := V1Obj()
	blade := 0, trap := 0, blade2 := 0, trap2 := 0, BladeDir := "", TrapDir := "", bladetype := "", traptype := ""
	if (!IsObject(BoostSrcUsed))
		BoostSrcUsed := V1Obj()
	if (!IsObject(BoostSaid))
		BoostSaid := V1Obj()
	if (hitschool = "")
		return
	;(the game's hand as the helper read it this look - an older helper's, with no heads or boosts, isn't used here: the
	;cards are played as before)
	bsHand := VisionCards(300, 5000)
	BoostMemOk := (IsObject(bsHand) && (!bsHand.cards.Length || bsHand.cards[1].nf >= 25)) ? 1 : 0
	if (!BoostMemOk)
		bsHand := ""
	bsWant := [], bsSeen := ","
	if (PartySupport() || (Manual = 1 && HammerSchool != hitschool))
		{
		bsH := HammerPlan != "" ? HammerPlan : HammerSchool
		Loop Parse, bsH, ","
			if (BadgeNumber(A_LoopField) && !InStr(bsSeen, "," A_LoopField ","))
				bsWant.Push(A_LoopField), bsSeen .= A_LoopField ","
		}
	else
		{
		bsWant.Push(hitschool), bsSeen .= hitschool ","
		;(hit4 only on a picked boss - it's cast on bosses only)
		for bsI, bsH in ["hit4", "hit3", "hit2", "hit1"]
			if (%bsH% == 1 && (bsH != "hit4" || BossChoosen == 1))
				for bsS in HitHeads(bsH).heads
					if (!InStr(bsSeen, "," bsS ","))
						bsWant.Push(bsS), bsSeen .= bsS ","
		if (BoostMemOk)
			for bsI, bsC in bsHand.cards
				{
				bsHh := V1Obj()
				if ((bsC.kind = "damage" || bsC.kind = "aoe") && HeadsParse(bsC.heads, bsHh))
					for bsS in bsHh.heads
						if (!InStr(bsSeen, "," bsS ","))
							bsWant.Push(bsS), bsSeen .= bsS ","
				}
		}
	;(the wand's heads too, looked at now - the kill check asks)
	if (wand == 1)
		HitHeads("wand")
	;(the other schools' pictures the helper is asked about from now on this battle - Vision.ahk VisionPicList)
	for bsI, bsS in bsWant
		if (bsS != hitschool && bsS != "balance" && !InStr("," BoostExtra ",", "," bsS ","))
			BoostExtra .= (BoostExtra = "" ? "" : ",") bsS
	for bsI, bsS in bsWant
		{
		if (bsS = "balance")
			continue
		bsF := 0, bsX := "", bsY := ""
		Find("blade", &bsF, &bsX, &bsY, &bsS)
		if (bsF == 1)
			SbFound[bsS "/blade"] := V1Obj({x: bsX, y: bsY})
		bsF := 0, bsX := "", bsY := ""
		Find("trap", &bsF, &bsX, &bsY, &bsS)
		if (bsF == 1)
			SbFound[bsS "/trap"] := V1Obj({x: bsX, y: bsY})
		}
	for bsI, bsG in PlanGroups(bsWant)
		{
		if (Tri(bsG, "blade"))
			GbFound[bsG "blade"] := 1
		if (Tri(bsG, "trap"))
			GbFound[bsG "trap"] := 1
		}
	;(the game's hand read: a picture found for a card it doesn't have is a false match; each one's cards - their % and copies)
	if (BoostMemOk)
		{
		bsKeys := [], bsHas := V1Obj()
		for bsK in SbFound
			bsKeys.Push(bsK)
		for bsK in GbFound
			bsKeys.Push(bsK)
		for bsI, bsK in ["blade3", "blade4", "trap3", "feint"]
			if (%bsK% == 1)
				bsKeys.Push(bsK)
		for bsI, bsK in bsKeys
			{
			bsM := BoostMatches(bsK, bsHand.cards)
			if (!bsM.Length)
				{
				if (SbFound.Has(bsK))
					SbFound.Delete(bsK)
				else if (GbFound.Has(bsK))
					GbFound.Delete(bsK)
				else
					%bsK% := 0
				if (!BoostSaid.Has("false|" bsK))
					BoostSaid["false|" bsK] := 1, DebugLog("  the " bsK " picture matched, but the game has no such card in hand - a false match, not used")
				continue
				}
			BoostHand[bsK] := []
			;(v1.8.0: each copy's card in the game's hand - n - and whether it's this key's for sure - BoostSureOf, not one of
			;BoostMatches' fallbacks: Autofarmer.ahk DiscardSpent counts and throws away only those -, its enchantment too)
			for bsJ, bsN in bsM
				{
				bsC := bsHand.cards[bsN], bsP := BoostCardPct(bsC), bsSrc := BoostSrcOf(bsC), bsHas[bsN] := 1
				BoostHand[bsK].Push(V1Obj({src: bsSrc, item: bsC.item ? 1 : 0, pct: bsP, ench: (bsC.ench != "") ? 1 : 0, n: bsN, sure: BoostSureOf(bsK, bsC) ? 1 : 0}))
				if (bsP != "")
					{
					if (!BoostPctMem.Has(bsK) || bsP < BoostPctMem[bsK])
						BoostPctMem[bsK] := bsP
					bsS := bsK "@" (bsSrc = "" ? "deck" : bsSrc)
					if (!BoostPctMem.Has(bsS) || bsP < BoostPctMem[bsS])
						BoostPctMem[bsS] := bsP
					}
				}
			}
		;(the game's blades and traps in hand no picture found: found by the game's hand when this search is for them - their
		;slot's key by their schools and % (BoostSlotFor), not one the game says can't be cast now; cast at their card box -
		;UseBlade / UseTrap, BoostMemBox; said once a battle)
		bsMem := V1Obj()
		for bsI, bsC in bsHand.cards
			{
			if ((bsC.kind != "blade" && bsC.kind != "trap") || bsHas.Has(bsI))
				continue
			bsB := BoostsParse(bsC.boosts), bsNm := BoostMemName(bsC)
			if (!IsObject(bsB))
				continue
			bsSlot := BoostSlotFor(bsC.kind, bsB.sch, bsB.pct, hitschool), bsMk := BoostMemKey(bsSlot)
			bsGo := (bsMk != "" && bsC.castable != "0" && BoostMemWanted(bsMk, bsWant))
			if (bsGo)
				{
				if (!BoostHand.Has(bsMk))
					BoostHand[bsMk] := []
				bsP := BoostCardPct(bsC), bsSrc := BoostSrcOf(bsC), bsMem[bsMk] := 1
				BoostHand[bsMk].Push(V1Obj({src: bsSrc, item: bsC.item ? 1 : 0, pct: bsP, ench: (bsC.ench != "") ? 1 : 0, n: bsI, sure: BoostSureOf(bsMk, bsC) ? 1 : 0}))
				if (bsP != "")
					{
					if (!BoostPctMem.Has(bsMk) || bsP < BoostPctMem[bsMk])
						BoostPctMem[bsMk] := bsP
					bsS := bsMk "@" (bsSrc = "" ? "deck" : bsSrc)
					if (!BoostPctMem.Has(bsS) || bsP < BoostPctMem[bsS])
						BoostPctMem[bsS] := bsP
					}
				}
			if (BoostSaid.Has("miss|" bsNm))
				continue
			BoostSaid["miss|" bsNm] := 1
			DebugLog("  in hand (the game): " bsNm " (" bsC.kind " " bsB.sch " " bsB.pct "%) - no picture found it" (bsSlot = "" ? " (no slot is for it - not cast)"
				: " (" bsSlot ")" (bsGo ? ": cast at its card box when the hand's boxes and the game's cards line up" : bsC.castable = "0" ? ": greyed out now" : ": not for this round's hits")))
			}
		;(each found so: its school's (SbFound - no picture spot), its group's (GbFound), every school's (blade3...: its flag)
		for bsK in bsMem
			{
			BoostMemOnly[bsK] := 1
			if (InStr(bsK, "/"))
				SbFound[bsK] := V1Obj({x: "", y: "", mem: 1})
			else if (RegExMatch(bsK, "^(elemental|spirit)(blade|trap)$"))
				GbFound[bsK] := 1
			else
				%bsK% := 1, %bsK%X := "", %bsK%Y := ""
			}
		;(and Tower Shield the same way - TowerMem - and your school's bubble - BubbleMem)
		TowerMem(bsHand)
		BubbleMem(bsHand)
		;(an absorb, a negative aura, your school's prism - 2026-10-26: AbsorbMem, NegAuraMem, ConvertMem)
		AbsorbMem(bsHand)
		NegAuraMem(bsHand)
		ConvertMem(bsHand)
		}
	;(this look's: the first school blade and trap in the schools' order, the first group's)
	for bsI, bsS in bsWant
		{
		if (!blade && SbFound.Has(bsS "/blade"))
			blade := 1, BladeDir := bsS, BladeX := SbFound[bsS "/blade"].x, BladeY := SbFound[bsS "/blade"].y
		if (!trap && SbFound.Has(bsS "/trap"))
			trap := 1, TrapDir := bsS, trapX := SbFound[bsS "/trap"].x, trapY := SbFound[bsS "/trap"].y
		}
	for bsI, bsG in PlanGroups(bsWant)
		{
		if (!blade2 && GbFound.Has(bsG "blade"))
			blade2 := 1, bladetype := bsG "blade"
		if (!trap2 && GbFound.Has(bsG "trap"))
			trap2 := 1, traptype := bsG "trap"
		}
	;(said when it's more than your own school's - a plain one-school battle's log as before)
	if (bsWant.Length != 1 || bsWant[1] != hitschool || BoostMemOk)
		{
		;(one found by the game's hand alone - no picture: "(no picture)")
		bsLog := "", bsTr := ""
		for bsK in SbFound
			if (InStr(bsK, "/blade"))
				bsLog .= (bsLog = "" ? "" : ", ") bsK (BoostMemOnly.Has(bsK) ? " (no picture)" : "")
			else
				bsTr .= (bsTr = "" ? "" : ", ") bsK (BoostMemOnly.Has(bsK) ? " (no picture)" : "")
		for bsK in GbFound
			if (InStr(bsK, "blade"))
				bsLog .= (bsLog = "" ? "" : ", ") bsK (BoostMemOnly.Has(bsK) ? " (no picture)" : "")
			else
				bsTr .= (bsTr = "" ? "" : ", ") bsK (BoostMemOnly.Has(bsK) ? " (no picture)" : "")
		for bsI, bsK in ["blade3", "blade4"]
			if (%bsK% == 1)
				bsLog .= (bsLog = "" ? "" : ", ") bsK (BoostMemOnly.Has(bsK) ? " (no picture)" : "")
		for bsI, bsK in ["trap3", "feint"]
			if (%bsK% == 1)
				bsTr .= (bsTr = "" ? "" : ", ") bsK (BoostMemOnly.Has(bsK) ? " (no picture)" : "")
		bsS := ""
		for bsI, bsH in bsWant
			bsS .= (bsS = "" ? "" : ",") bsH
		DebugLog("  boosts searched for " (bsS = "" ? "no school (the hitter's isn't known: only every school's)" : bsS) ": " (bsLog = "" ? "no blade" : bsLog) "; traps: " (bsTr = "" ? "none" : bsTr) (BoostMemOk ? " (the game's hand)" : ""))
		}
	}

;---- Tower Shield by the game's hand (2026-10-25) ----
;Live 18:53 (1440p, UI 1.144): the game's hand held two Tower Shields while every round's "cards:" line said tower=0 -
;ui1.144\resources\tower.png is another card's picture (a Spirit Shield's, learned before Tower Shields were), so no picture
;found them, and the shield went out neither to defend you (EnemySpells.ahk EnemyDefend), on an ally or the hitter
;(Party.ahk PartyShield), nor as the filler when nothing else could go. BoostSearch, the game's hand read for sure (hand):
;the tower picture found with no shield in the game's hand at all is a false match - not used; a Tower Shield the game has
;(TowerMatches) that no picture found is found all the same when one can be cast now - tower 1, no picture spot,
;BoostMemOnly["tower"]: UseOnSelf / UseOnHammer cast it at its card box (Autofarmer.ahk UseMemAt - BoostMemBox, only while
;the hand's boxes and the game's cards line up for sure). Said once a battle. The slot's picture is put right by the
;learner meanwhile (CardLearn.ahk LearnBoostPicFix)
TowerMem(hand)
	{
	global tower, towerX, towerY, BoostMemOnly, BoostSaid
	twmWard := 0
	for twmI, twmC in hand.cards
		twmWard += (twmC.kind = "ward") ? 1 : 0
	twmM := TowerMatches(hand.cards)
	if (tower == 1)
		{
		if (!twmWard)
			{
			tower := 0
			if (!BoostSaid.Has("false|tower"))
				BoostSaid["false|tower"] := 1, DebugLog("  the tower picture matched, but the game has no shield in hand - a false match, not used")
			}
		;(a Tower Shield in hand and another shield too - a school's or a team's, which the picture may be on: as shipped at
		;UI 1.144 resources\tower is a Spirit Shield's - the Tower Shield at its card box when the boxes line up for sure,
		;else the picture's spot as before - Autofarmer.ahk UseMemAt, 2026-10-25)
		else if (twmM.Length && twmM.Length < twmWard)
			BoostMemOnly["tower"] := 1
		return
		}
	if (!twmM.Length)
		return
	twmGo := ""
	for twmI, twmN in twmM
		if (twmGo = "" && hand.cards[twmN].castable != "0")
			twmGo := twmN
	twmC := hand.cards[twmGo != "" ? twmGo : twmM[1]], twmNm := BoostMemName(twmC)
	if (twmGo != "")
		tower := 1, towerX := "", towerY := "", BoostMemOnly["tower"] := 1
	if (!BoostSaid.Has("miss|" twmNm))
		BoostSaid["miss|" twmNm] := 1, DebugLog("  in hand (the game): " twmNm " (" twmC.kind " " twmC.value ") - no picture found it (resources\tower)"
			. (twmGo != "" ? ": cast at its card box when the hand's boxes and the game's cards line up" : ": greyed out now"))
	}

;---- Your school's bubble (a global) by the game's hand (2026-10-26) ----
;A bubble - a global spell: all of the battle, everyone's spells - goes from <school>\bubble before a hit (usebubble;
;Autofarmer.ahk ClickBubble). The game's memory (read-only) names a global kind bubble (vision\handmem.py: an effect aimed at
;kGlobal) with the schools whose damage it adds to (its boosts). BoostSearch, the game's hand read for sure (BubbleMem): the
;bubble picture found with no global in the game's hand at all is a false match - not used; found while the global the bot
;put up this battle is in hand (BubbleUp - the game replaces a global with the next one cast: the same again is a card and
;pips for nothing; an enemy's global over ours isn't seen) and no other of the slot's is - not cast again, whatever else is
;in hand (a global that adds no damage, a card the memory couldn't tell); the slot's global (BubbleMatches) that no picture
;found is found all the same when one can be cast now - bubble 1, no picture spot, BoostMemOnly["<school>/bubble"]:
;ClickBubble casts it at its card box (BoostMemBox - only while the hand's boxes and the game's cards line up for sure).
;Your kinds on the Spells tab win (2026-10-26 review): a global you set to another kind (Not used...) is never the bubble,
;the card you set to Bubble yourself in the slot is one whatever the game calls it (BubbleUserOff, BubbleUserSlot). Said
;once a battle. Only for your own school's hits (another school's wizard's - Alt+2, a party's hitter - gets no bubble:
;FindCards) and with the bubble on

;The game's name of the card in school sch's bubble slot (<sch>\bubble): its learned card's - the game's name for it (flag
;game=), else the name it was given; "" none known (no learned card there - a picture cut by hand: any global that boosts
;sch's damage is its card)
BubbleSlotName(sch)
	{
	if (sch = "" || !V1IsFunc("LearnCardInSlot"))
		return ""
	bsnC := LearnCardInSlot.Call(sch "\bubble")
	if (!IsObject(bsnC))
		return ""
	bsnG := V1IsFunc("LearnFlag") ? LearnFlag.Call(bsnC, "game") : ""
	return (bsnG != "") ? bsnG : Trim(bsnC.name)
	}

;Whether a global boosting schools bs ("all", or schools joined with , or + - BoostsParse's sch, a learned card's flag
;boost=) adds to school sch's damage
BubbleHelps(bs, sch)
	{
	if (bs = "" || sch = "")
		return false
	return (bs = "all" || InStr("," StrReplace(bs, "+", ",") ",", "," sch ",")) ? true : false
	}

;The cards of the game's hand (VisionCards' cards) that are school sch's bubble slot's card, as their numbers in cards: a
;global (kind bubble) the game names as the slot's learned card (BubbleSlotName); none known: a global that boosts sch's
;damage (its boosts: sch's or every school's - not one that only changes healing or pierce, nor another school's). Never
;the global the bot put up this battle (BubbleUp), nor one you set to another kind on the Spells tab (Not used...:
;BubbleUserOff); the card you set to Bubble yourself in the slot is one whatever kind the game gives it (BubbleUserSlot). []
;none
BubbleMatches(cards, sch)
	{
	global BubbleUp
	bbmOut := []
	if (!IsObject(cards) || sch = "")
		return bbmOut
	bbmName := BubbleSlotName(sch)
	for bbmI, bbmC in cards
		{
		if (!BubbleIs(bbmC) && !BubbleUserSlot(bbmC, sch))
			continue
		if (BubbleUserOff(bbmC, sch))
			continue
		bbmNm := BoostMemName(bbmC)
		if (BubbleUp != "" && bbmNm = BubbleUp)
			continue
		if (bbmName != "")
			{
			if (bbmNm = bbmName || bbmC.name = bbmName || bbmC.display = bbmName)
				bbmOut.Push(bbmI)
			continue
			}
		bbmB := BoostsParse(bbmC.boosts)
		if (IsObject(bbmB) && BubbleHelps(bbmB.sch, sch))
			bbmOut.Push(bbmI)
		}
	return bbmOut
	}

;BoostSearch's look at your school's bubble by the game's hand (hand: VisionCards', read for sure) - see above
BubbleMem(hand)
	{
	global bubble, bubbleX, bubbleY, BoostMemOnly, BoostSaid, BubbleUp, hitschool, HammerSchool
	if (hitschool = "" || HammerSchool != hitschool || !Stat("usebubble") || !IsObject(hand) || !IsObject(hand.cards))
		return
	bbuKey := BoostKey("bubble", hitschool), bbuAll := 0, bbuUp := 0, bbuOdd := 0
	for bbuI, bbuC in hand.cards
		{
		;(a global - or the card you set to Bubble yourself in the slot: the game may call it another kind)
		if (BubbleIs(bbuC) || BubbleUserSlot(bbuC, hitschool))
			bbuAll += 1, bbuUp += (BubbleUp != "" && BoostMemName(bbuC) = BubbleUp) ? 1 : 0
		;(a card whose kind the game's memory couldn't tell - its effects cut short: it may be a global)
		else if (bbuC.kind = "")
			bbuOdd += 1
		}
	bbuM := BubbleMatches(hand.cards, hitschool)
	if (bubble == 1)
		{
		if (!bbuAll && !bbuOdd)
			{
			bubble := 0
			if (!BoostSaid.Has("false|bubble"))
				BoostSaid["false|bubble"] := 1, DebugLog("  the bubble picture matched, but the game has no global in hand - a false match, not used")
			}
		;(the global the bot put up in hand and none of the slot's to cast besides: the picture is on that one, on a global
		;that isn't the slot's - one that doesn't boost your school, one you set to another kind -, or on a card the game's
		;memory couldn't tell - not cast either way)
		else if (bbuUp && !bbuM.Length)
			{
			bubble := 0
			if (!BoostSaid.Has("up|" BubbleUp))
				BoostSaid["up|" BubbleUp] := 1, DebugLog("  the bubble in hand is " BubbleUp ", the global the bot put up this battle - not cast again")
			}
		;(the slot's global in hand and another global the picture may be on - the one up already, one that doesn't boost
		;your school, or another of the slot's (its name then not known by the picture): the slot's at its card box when the
		;boxes line up for sure, the one cast named (BubbleUp) - ClickBubble)
		else if (bbuM.Length && bbuAll > 1)
			BoostMemOnly[bbuKey] := 1
		return
		}
	if (!bbuM.Length)
		return
	bbuGo := ""
	for bbuI, bbuN in bbuM
		if (bbuGo = "" && hand.cards[bbuN].castable != "0")
			bbuGo := bbuN
	bbuC := hand.cards[bbuGo != "" ? bbuGo : bbuM[1]], bbuNm := BoostMemName(bbuC)
	if (bbuGo != "")
		bubble := 1, bubbleX := "", bubbleY := "", BoostMemOnly[bbuKey] := 1
	if (!BoostSaid.Has("miss|" bbuNm))
		BoostSaid["miss|" bbuNm] := 1, DebugLog("  in hand (the game): " bbuNm " (bubble " bbuC.value (bbuC.boosts != "" ? ", " bbuC.boosts : "") ") - no picture found it (" hitschool "\bubble)"
			. (bbuGo != "" ? ": cast at its card box when the hand's boxes and the game's cards line up" : ": greyed out now"))
	}

;Whether the game's hand (this look's - VisionCards) holds the global the bot put up this battle (BubbleUp)
BubbleUpHeld()
	{
	global BubbleUp
	if (BubbleUp = "" || !V1IsFunc("VisionCards"))
		return false
	buhHand := VisionCards.Call(300, 5000)
	if (IsObject(buhHand))
		for buhI, buhC in buhHand.cards
			if (BubbleIs(buhC) && BoostMemName(buhC) = BubbleUp)
				return true
	return false
	}

;Whether a card of the game's hand (VisionCards') is a global: kind bubble - or its type Global (the game's own word: an
;older helper called a global's kind "keep")
BubbleIs(c)
	{
	return IsObject(c) && (c.kind = "bubble" || c.type = "global")
	}

;Whether a card of the game's hand (VisionCards') is the card you put in school sch's bubble slot yourself - its learned
;card there flagged user (you set its kind to Bubble on the Spells tab; CardLearn.ahk LearnBubbleFits gives it the slot
;whatever the game says): your bubble, whatever kind the game gives it - never a false match of the slot's picture
BubbleUserSlot(c, sch)
	{
	if (!IsObject(c) || sch = "" || !V1IsFunc("LearnCardInSlot") || !V1IsFunc("LearnHasFlag"))
		return false
	busC := LearnCardInSlot.Call(sch "\bubble")
	if (!IsObject(busC) || !LearnHasFlag.Call(busC, "user"))
		return false
	busNm := BubbleSlotName(sch)
	return (busNm != "" && (BoostMemName(c) = busNm || c.name = busNm || c.display = busNm)) ? true : false
	}

;Whether you set a card of the game's hand (VisionCards') to a kind other than Bubble on the Spells tab - Not used, an
;aura...: the learned card it is (the game's name for it - flag game= -, else the name it was given) flagged user, that
;kind kept (the learner never changes it - LearnApplyMem): never cast as a bubble. The learned card for school sch first,
;of its own copy (the deck's, a treasure or an item card's) first
BubbleUserOff(c, sch)
	{
	global LearnedCards
	if (!IsObject(c) || !IsObject(LearnedCards) || !V1IsFunc("LearnHasFlag") || !V1IsFunc("LearnFlag"))
		return false
	buoNm := BoostMemName(c), buoBest := "", buoRank := 0
	for buoI, buoL in LearnedCards
		{
		buoG := LearnFlag.Call(buoL, "game"), buoLn := Trim(buoL.name)
		if (buoG != "" ? (buoG != buoNm) : (buoLn = "" || (buoLn != buoNm && buoLn != c.name && buoLn != c.display)))
			continue
		buoR := 1 + ((buoL.sch = sch) ? 2 : 0)
		buoR += (LearnHasFlag.Call(buoL, "tc") = (c.tc ? true : false) && LearnHasFlag.Call(buoL, "item") = (c.item ? true : false)) ? 1 : 0
		if (buoR > buoRank)
			buoRank := buoR, buoBest := buoL
		}
	return (IsObject(buoBest) && buoBest.type != "bubble" && LearnHasFlag.Call(buoBest, "user")) ? true : false
	}

;The game's name of the global about to be cast by its picture (ClickBubble): the one name every global in the game's hand
;has (this look's - VisionCards; the card you put in the slot yourself counted as one - BubbleUserSlot); several or none:
;the slot's learned card's (BubbleSlotName - the slot's picture is that card's own) when the hand holds a card of that
;name; the hand not read: the slot's learned card's; "" not known (several globals and no learned card in the slot - a
;picture cut by hand -, or the slot's card not in hand)
BubbleHandName()
	{
	global hitschool
	bhnSlot := BubbleSlotName(hitschool)
	bhnHand := V1IsFunc("VisionCards") ? VisionCards.Call(300, 5000) : ""
	if (!IsObject(bhnHand))
		return bhnSlot
	bhnOut := "", bhnMany := 0, bhnHas := 0
	for bhnI, bhnC in bhnHand.cards
		{
		bhnNm := BoostMemName(bhnC)
		if (bhnSlot != "" && (bhnNm = bhnSlot || bhnC.name = bhnSlot || bhnC.display = bhnSlot))
			bhnHas := 1
		if (BubbleIs(bhnC) || BubbleUserSlot(bhnC, hitschool))
			{
			if (bhnOut != "" && bhnOut != bhnNm)
				bhnMany := 1
			bhnOut := bhnNm
			}
		}
	return (bhnMany || bhnOut = "") ? (bhnHas ? bhnSlot : "") : bhnOut
	}

;---- Absorbs, negative auras and your school's prism by the game's hand (2026-10-26) ----
;Since every battle spell type of the game's has a kind (vision\handmem.py kind_of, the game's memory read-only):
;  absorb   soaks N damage (Spirit Armor, Legion Absorb; Ice Armor: N a pip): a shield on you, on Tower Shield's turns,
;           after it - defending (EnemySpells.ahk EnemyDefend) and the solo filler (Autofarmer.ahk AbsorbFiller: there
;           only one that costs no pips - an X-pip or 3-pip one spends what the next hit needs). By its picture in its learned
;           slot resources\absorb (CardLearn.ahk LearnSlotFor), else at its card box (AbsorbMem: absorb 1, no picture spot,
;           BoostMemOnly["absorb"] - UseOnSelf / UseMemAt, BoostMemBox - only while the boxes and the game's cards line up for
;           sure). With usetower, and useabsorb (PlayerStats.txt, on unless 0)
;  negaura  a negative aura - on one enemy for 4 rounds, not used up by a hit. The Attenuates (+N% damage taken: the game's
;           boosts, "fire:25", "all:20") go on the trap rule's enemy (NegAuraWhere: the boss picked with Alt+1, else the one
;           with the most health - TrapWhere / TrapTarget; a party support's: the hitter's target) before the traps and
;           blades, only one that adds to the planned hit's schools (NegAuraFits: a school's Attenuate for that school's
;           damage, the plain one for any), at most once in 4 rounds on an enemy (NegAuraOn), at its card box (NegAuraMem,
;           Autofarmer.ahk UseNegAura). Starfall and Pathogen (no damage taken) aren't played. With usetraps. The kill check
;           doesn't count it
;  prism    your school's (the card's school yours) in <school>\convert: cast at the boss picked with Alt+1 when the game's
;           memory says it's of your school - it resists your hits (ConvertNeedMem, Autofarmer.ahk NeedsConvert /
;           UseConvert); no picture for it: at its card box (ConvertMem). Once till a hit of yours goes out (ConvertUp)
;Your kinds on the Spells tab win (the review, 2026-10-26 - as the bubble's: BubbleUserOff, BubbleUserSlot): a card you set
;to another kind (Not used...) is never cast as one of these (MemUserOff), and the card you set to Absorb or Prism yourself
;in its slot is one whatever kind the game gives it (MemUserSlot)

;Whether you set a card of the game's hand (VisionCards') to a kind other than kind on the Spells tab - Not used, an aura...:
;the learned card it is (the game's name for it - flag game= -, else the name it was given; school sch's first, of its own
;copy - the deck's, a treasure or an item card's - first: BubbleUserOff's way) flagged user, that kind kept (the learner
;never changes it): never cast as kind
MemUserOff(c, sch, kind)
	{
	global LearnedCards
	if (!IsObject(c) || !IsObject(LearnedCards) || !V1IsFunc("LearnHasFlag") || !V1IsFunc("LearnFlag"))
		return false
	muoNm := BoostMemName(c), muoBest := "", muoRank := 0
	for muoI, muoL in LearnedCards
		{
		muoG := LearnFlag.Call(muoL, "game"), muoLn := Trim(muoL.name)
		if (muoG != "" ? (muoG != muoNm) : (muoLn = "" || (muoLn != muoNm && muoLn != c.name && muoLn != c.display)))
			continue
		muoR := 1 + ((sch != "" && muoL.sch = sch) ? 2 : 0)
		muoR += (LearnHasFlag.Call(muoL, "tc") = (c.tc ? true : false) && LearnHasFlag.Call(muoL, "item") = (c.item ? true : false)) ? 1 : 0
		if (muoR > muoRank)
			muoRank := muoR, muoBest := muoL
		}
	return (IsObject(muoBest) && muoBest.type != kind && LearnHasFlag.Call(muoBest, "user")) ? true : false
	}

;Whether a card of the game's hand (VisionCards') is the card you put in slot rel yourself (resources\absorb, <school>\convert):
;its learned card there of kind kind flagged user (you set its kind on the Spells tab; the learner gives it the slot whatever
;the game says), the game's name for it (flag game=, else the name it was given) this card's - that kind whatever kind the
;game gives it (another, or none: its effects cut short), never a false match of the slot's picture
MemUserSlot(c, rel, kind)
	{
	if (!IsObject(c) || rel = "" || !V1IsFunc("LearnCardInSlot") || !V1IsFunc("LearnHasFlag") || !V1IsFunc("LearnFlag"))
		return false
	musC := LearnCardInSlot.Call(rel)
	if (!IsObject(musC) || musC.type != kind || !LearnHasFlag.Call(musC, "user"))
		return false
	musG := LearnFlag.Call(musC, "game"), musNm := (musG != "") ? musG : Trim(musC.name)
	return (musNm != "" && (BoostMemName(c) = musNm || c.name = musNm || c.display = musNm)) ? true : false
	}

;The cards of the game's hand (VisionCards' cards) that are an absorb (key absorb - resources\absorb), as their numbers in
;cards: kind absorb, or the card you set to Absorb in resources\absorb (MemUserSlot) - not one you set to another kind
;(MemUserOff); with AbsorbOnlyFree set (the solo filler - AbsorbFiller) only one that costs no pips (AbsorbFreeCard). [] none
AbsorbMatches(cards)
	{
	global AbsorbOnlyFree, hitschool
	abmOut := []
	if (!IsObject(cards))
		return abmOut
	for abmI, abmC in cards
		if ((abmC.kind = "absorb" || MemUserSlot(abmC, "resources\absorb", "absorb")) && !MemUserOff(abmC, hitschool, "absorb")
			&& (!AbsorbOnlyFree || AbsorbFreeCard(abmC)))
			abmOut.Push(abmI)
	return abmOut
	}

;Whether a card of the game's hand costs no pips: 0 pips read, not X-pip, no shadow or school pips
AbsorbFreeCard(c)
	{
	return IsObject(c) && c.pips != "" && c.pips + 0 = 0 && !c.xpip && (c.shadow = "" || c.shadow + 0 = 0) && c.schoolpips = ""
	}

;Whether resources\absorb's card costs no pips by its learned card (pips 0 read, not guessed, not X-pip - the game's hand not
;read); a picture cut by hand: not known - no
AbsorbSlotFree()
	{
	if (!V1IsFunc("LearnCardInSlot") || !V1IsFunc("LearnHasFlag"))
		return 0
	asfC := LearnCardInSlot.Call("resources\absorb")
	return (IsObject(asfC) && asfC.pips != "" && asfC.pips + 0 = 0 && !asfC.guess && !LearnHasFlag.Call(asfC, "xpip")) ? 1 : 0
	}

;Whether resources\absorb has a picture to look for (FindCards): a learned card in it, or one cut by hand (the main set's,
;this UI size's) - none: never looked for by its picture (an ImageSearch of a file that isn't there)
AbsorbPicThere()
	{
	global PicDir
	if (V1IsFunc("LearnCardInSlot") && IsObject(LearnCardInSlot.Call("resources\absorb")))
		return true
	return (FileExist(A_WorkingDir "\resources\absorb.png") || (PicDir != "" && FileExist(PicDir "\resources\absorb.png"))) ? 1 : 0  ; (v1: 1 or 0 - v2 the attributes)
	}

;Whether absorbs are cast: Tower Shield on (usetower) and useabsorb (on unless 0)
AbsorbOn()
	{
	return (Stat("usetower") && StatOr("useabsorb", 1)) ? 1 : 0  ; (v1: && gave 1 or 0 - v2 the setting)
	}

;BoostSearch's look at absorbs by the game's hand (hand: VisionCards', read for sure): the absorb picture found with no absorb
;in the game's hand is a false match - not used; found with more than one absorb in hand: the one cast at its card box
;(BoostMemOnly - the picture may be on another); no picture found it: one that can be cast now is found all the same (absorb
;1, no picture spot). AbsorbFreeOk: one that costs no pips can be cast now. Said once a battle
AbsorbMem(hand)
	{
	global absorb, absorbX, absorbY, AbsorbFreeOk, BoostMemOnly, BoostSaid
	if (!IsObject(hand) || !IsObject(hand.cards))
		return
	abmM := AbsorbMatches(hand.cards), abmGo := "", abmFree := 0
	for abmI, abmN in abmM
		if (hand.cards[abmN].castable != "0")
			{
			if (abmGo = "")
				abmGo := abmN
			if (AbsorbFreeCard(hand.cards[abmN]))
				abmFree := 1
			}
	AbsorbFreeOk := abmFree
	if (absorb == 1)
		{
		if (!abmM.Length)
			{
			absorb := 0
			if (!BoostSaid.Has("false|absorb"))
				BoostSaid["false|absorb"] := 1, DebugLog("  the absorb picture matched, but the game has no absorb in hand - a false match, not used")
			}
		else if (abmM.Length > 1)
			BoostMemOnly["absorb"] := 1
		return
		}
	if (!abmM.Length)
		return
	abmC := hand.cards[abmGo != "" ? abmGo : abmM[1]], abmNm := BoostMemName(abmC)
	if (abmGo != "")
		absorb := 1, absorbX := "", absorbY := "", BoostMemOnly["absorb"] := 1
	if (!BoostSaid.Has("miss|" abmNm))
		BoostSaid["miss|" abmNm] := 1, DebugLog("  in hand (the game): " abmNm " (absorb " abmC.value ") - no picture found it (resources\absorb)"
			. (abmGo != "" ? ": cast at its card box on Tower Shield's turns (defending; the filler only one that costs no pips)" : ": greyed out now"))
	}

;Whether a negative aura boosting schools bs (its boosts as BoostsParse has them: "all", "fire", "death,ice") adds to the
;planned hit (PlanHeads - BoostPick's: some of its damage of those schools); every school's (Attenuate) always; the plan
;not made yet: the hitter's school (your own)
NegAuraFits(bs)
	{
	global PlanHeads, HammerSchool, hitschool
	if (bs = "")
		return false
	if (bs = "all")
		return true
	if (IsObject(PlanHeads) && PlanHeads.total > 0)
		{
		for nafS, nafV in PlanHeads.heads
			if (nafV > 0 && InStr("," bs ",", "," nafS ","))
				return true
		return false
		}
	nafS := (HammerSchool != "") ? HammerSchool : hitschool
	return (nafS != "" && InStr("," bs ",", "," nafS ",")) ? true : false
	}

;The cards of the game's hand that are a negative aura adding damage taken that fits the planned hit (key negaura -
;NegAuraFits), as their numbers in cards - not one you set to another kind on the Spells tab (MemUserOff). [] none
NegAuraMatches(cards)
	{
	global hitschool
	namOut := []
	if (!IsObject(cards))
		return namOut
	for namI, namC in cards
		{
		if (namC.kind != "negaura" || MemUserOff(namC, hitschool, "negaura"))
			continue
		namB := BoostsParse(namC.boosts)
		if (IsObject(namB) && NegAuraFits(namB.sch))
			namOut.Push(namI)
		}
	return namOut
	}

;BoostSearch's look at negative auras by the game's hand: negaura 1 when one that adds damage taken can be cast now (whether
;it fits the planned hit is asked when it's cast - BoostPick plans after this); one you set to another kind on the Spells
;tab never (MemUserOff). Said once a battle
NegAuraMem(hand)
	{
	global negaura, BoostSaid, hitschool
	negaura := 0
	if (!IsObject(hand) || !IsObject(hand.cards))
		return
	for namI, namC in hand.cards
		{
		if (namC.kind != "negaura")
			continue
		namB := BoostsParse(namC.boosts), namNm := BoostMemName(namC), namOff := MemUserOff(namC, hitschool, "negaura")
		if (IsObject(namB) && namC.castable != "0" && !namOff)
			negaura := 1
		if (!BoostSaid.Has("miss|" namNm))
			BoostSaid["miss|" namNm] := 1, DebugLog("  in hand (the game): " namNm " (a negative aura, " namC.value (namC.boosts != "" && namC.boosts != "?" ? ", " namC.boosts : "") ")"
				. (namOff ? " - you set it to another kind on the Spells tab: not played" : !IsObject(namB) ? " - adds no damage taken: not played" : namC.castable = "0" ? " - greyed out now"
				: " - cast at its card box on the trap target before the boosts, once in 4 rounds an enemy, when it adds to the planned hit"))
		}
	}

;Where this round's negative aura goes (UseNegAura): the trap rule's enemy - the boss picked with Alt+1; TrapWhere's pick when
;it made one (a party support's: the hitter's target; else the enemy with the most health); else that rule asked now (no trap
;in hand: TrapWhere didn't look - PartyTrapTarget, TrapTarget; TrapWhere's own pick left as it was). x, y: its plate; key:
;the enemy (NegAuraKey - once in 4 rounds an enemy: NegAuraWhen, NegAuraNote); who: for the log. False: no enemy found
NegAuraWhere(&x, &y, &key, &who)
	{
	global BossChoosen, bossX, bossY, TrapOn, TrapAtX, TrapAtY, TrapWhy, TrapPick, GameLeft
	nawMost := ""
	if (BossChoosen == 1)
		x := bossX, y := bossY, who := "the boss (Alt+1)"
	else if (TrapOn == 1 && TrapAtX != "")
		x := TrapAtX, y := TrapAtY, who := (TrapWhy != "") ? TrapWhy : "the trap target"
	else
		{
		nawPick := TrapPick, nawWhy := TrapWhy
		if (PartySupport())
			nawGot := PartyTrapTarget(&x, &y), who := "the hitter's target"
		else
			nawGot := TrapTarget(&x, &y, &nawMost), who := TrapWhy
		TrapPick := nawPick, TrapWhy := nawWhy
		if (!nawGot || x = "")
			return false
		}
	if (x = "" || y = "")
		return false
	key := NegAuraKey(x)
	return true
	}

;The enemy whose plate is at x, for the negative aura's once in 4 rounds (the review, 2026-10-26: the plate's place alone
;gave the same enemy a second one when the plates closed up round a dead one - TrapFoeSlot's "they may have moved along" -
;and kept it from the one that moved into its place): its identities, the surest first, joined with |: the game's memory's
;participant at that plate (g<gid> - BattleFoeAt), its most health off the plates (EnemyHP, read with EnemyPlates: m<max>,
;with its place when another enemy has that most health too - TrapFoeSlot's way), its plate's place (p<n>, always)
NegAuraKey(x)
	{
	global EnemyPlates, EnemyHP, GameLeft
	nakAt := "p" Round((x - GameLeft) / Px(60)), nakOut := ""
	nakF := BattleFoeAt(x)
	if (IsObject(nakF) && nakF.gid != "")
		nakOut .= "g" nakF.gid "|"
	if (IsObject(EnemyPlates) && IsObject(EnemyHP) && EnemyHP.Length && EnemyHP.Length = EnemyPlates.Length)
		{
		nakN := 0, nakD := ""
		for nakI, nakP in EnemyPlates
			if (nakP.x != "" && (nakD = "" || Abs(nakP.x - x) < nakD))
				nakN := nakI, nakD := Abs(nakP.x - x)
		nakMax := nakN ? EnemyHP[nakN].max : ""
		if (nakN && nakD <= Px(40) && nakMax != "" && nakMax > 0)
			{
			nakSame := 0
			for nakI, nakE in EnemyHP
				nakSame += (nakE.max = nakMax) ? 1 : 0
			nakOut .= "m" nakMax (nakSame > 1 ? "@" nakAt : "") "|"
			}
		}
	return nakOut nakAt
	}

;The round a negative aura last went on the enemy key names (NegAuraKey), by the surest of its identities known now - its
;first ("" none recorded: NegAuraOn, this battle's). Its participant read now but not when one was cast (NavBattle's
;back-off, the helper restarting - the v0.54.0 review: a second one a round later): that cast's most health ("nog m...")
NegAuraWhen(key)
	{
	global NegAuraOn
	if (!IsObject(NegAuraOn))
		return ""
	nawP := StrSplit(key, "|"), nawK := nawP[1]
	if (nawK != "" && NegAuraOn.Has(nawK))
		return NegAuraOn[nawK]
	if (SubStr(nawK, 1, 1) = "g" && SubStr(nawP[2], 1, 1) = "m" && NegAuraOn.Has("nog " nawP[2]))
		return NegAuraOn["nog " nawP[2]]
	return ""
	}

;A negative aura cast on the enemy key names in round rnd: noted under each of its identities (NegAuraOn) - the next look
;finds it by the surest one it knows then; one cast without its participant (no g first) also marked "nog " (NegAuraWhen)
NegAuraNote(key, rnd)
	{
	global NegAuraOn
	if (!IsObject(NegAuraOn))
		NegAuraOn := V1Obj()
	nanNoG := SubStr(key, 1, 1) != "g"
	for nanI, nanK in StrSplit(key, "|")
		if (nanK != "")
			{
			NegAuraOn[nanK] := rnd
			if (nanNoG)
				NegAuraOn["nog " nanK] := rnd
			}
	}

;The enemy of the game's memory (Vision.ahk NavBattle - the helper's /battle, READ-ONLY) whose plate is at x: the nearest by
;the helper's x (its plate's middle across the window) within Px(160), not one whose health is read as 0 (dead); "" none
;(not read, no enemy there)
BattleFoeAt(x)
	{
	global GameLeft, GameW
	if (x = "" || !V1IsFunc("NavBattle"))
		return ""
	bfaB := NavBattle.Call()
	if (!IsObject(bfaB) || !IsObject(bfaB.foes))
		return ""
	bfaBest := "", bfaD := ""
	for bfaI, bfaF in bfaB.foes
		if (bfaF.x != "" && (bfaF.health = "" || bfaF.health > 0))
			{
			bfaDx := Abs(GameLeft + bfaF.x * GameW - x)
			if (bfaD = "" || bfaDx < bfaD)
				bfaBest := bfaF, bfaD := bfaDx
			}
	return (IsObject(bfaBest) && bfaD <= Px(160)) ? bfaBest : ""
	}

;The cards of the game's hand that are school sch's prism (key <sch>/convert - <school>\convert): kind prism, the card's own
;school sch, or the card you set to Prism in <sch>\convert (MemUserSlot) - not one you set to another kind (MemUserOff). []
;none
ConvertMatches(cards, sch)
	{
	cvmOut := []
	if (!IsObject(cards) || sch = "")
		return cvmOut
	for cvmI, cvmC in cards
		if (((cvmC.kind = "prism" && cvmC.school = sch) || MemUserSlot(cvmC, sch "\convert", "prism")) && !MemUserOff(cvmC, sch, "prism"))
			cvmOut.Push(cvmI)
	return cvmOut
	}

;Whether your prism is on the boss already: one cast this battle (ConvertOn - Autofarmer.ahk UseConvert: your hits counted
;then) and no hit of yours has gone out since (PartyHits - ConsumeBoosts counts each). The review, 2026-10-26: a second and
;third went out the next rounds while the first waited for the hit
ConvertUp()
	{
	global ConvertOn, PartyHits
	return (IsObject(ConvertOn) && ConvertOn.hits = (PartyHits ? PartyHits : 0)) ? true : false
	}

;BoostSearch's look at your school's prism by the game's hand: the convert picture found with no prism of your school in the
;game's hand is a false match - not used; none found by its picture: one that can be cast now is found all the same (convert
;1, no picture spot, BoostMemOnly["<school>/convert"] - Autofarmer.ahk UseConvert, UseMemAt) - not while one is on the boss
;already (ConvertUp). Another school's wizard's hits (Alt+2, a party's hitter) get none. Said once a battle
ConvertMem(hand)
	{
	global convert, convertX, convertY, BoostMemOnly, BoostSaid, hitschool, HammerSchool
	if (hitschool = "" || !IsObject(hand) || !IsObject(hand.cards))
		return
	cvmKey := BoostKey("convert", hitschool), cvmM := ConvertMatches(hand.cards, hitschool)
	if (convert == 1)
		{
		if (!cvmM.Length)
			{
			convert := 0
			if (!BoostSaid.Has("false|convert"))
				BoostSaid["false|convert"] := 1, DebugLog("  the convert picture matched, but the game has no " hitschool " prism in hand - a false match, not used")
			}
		return
		}
	if (!cvmM.Length || HammerSchool != hitschool || ConvertUp())
		return
	cvmGo := ""
	for cvmI, cvmN in cvmM
		if (cvmGo = "" && hand.cards[cvmN].castable != "0")
			cvmGo := cvmN
	cvmC := hand.cards[cvmGo != "" ? cvmGo : cvmM[1]], cvmNm := BoostMemName(cvmC)
	if (cvmGo != "")
		convert := 1, convertX := "", convertY := "", BoostMemOnly[cvmKey] := 1
	if (!BoostSaid.Has("miss|" cvmNm))
		BoostSaid["miss|" cvmNm] := 1, DebugLog("  in hand (the game): " cvmNm " (a " hitschool " prism) - no picture found it (" hitschool "\convert)"
			. (cvmGo != "" ? ": cast at its card box at the boss picked with Alt+1 when it's of your school" : ": greyed out now"))
	}

;Whether the boss picked with Alt+1 is of your school - it resists your hits: your prism converts them (Autofarmer.ahk
;NeedsConvert) - by the game's memory (Vision.ahk NavBattle - the helper's /battle, READ-ONLY): the enemy whose plate is the
;boss's (BattleFoeAt: the helper's x within Px(160) of it, the nearest), its school. 1 yours, 0 another; "" not known (not
;read, no enemy there, its school not read)
ConvertNeedMem()
	{
	global bossX, hitschool
	if (hitschool = "")
		return ""
	cnmBest := BattleFoeAt(bossX)
	if (!IsObject(cnmBest) || cnmBest.school = "")
		return ""
	return (cnmBest.school = hitschool) ? 1 : 0
	}

;The planned hit's share of damage boost key fits (1: every school's boost)
BoostShare(key)
	{
	global PlanHeads
	if (BoostSchools(key) = "all")
		return 1
	if (!IsObject(PlanHeads) || PlanHeads.total <= 0)
		return 0
	bshN := 0
	for bshS, bshV in PlanHeads.heads
		if (BoostFits(key, bshS))
			bshN += bshV
	return bshN / PlanHeads.total
	}

;Of the boosts in list (SbFound / GbFound) of kind ("blade" / "trap"), the one that adds the most to the planned hit and
;can still go (BoostCanGo): its % (BoostPctFor) x the share of the hit's damage it fits (BoostShare) - ties: your school's,
;then as BadgeNumber orders them. "" none fits
BoostBest(list, kind)
	{
	global hitschool
	bbBest := "", bbGain := 0, bbRank := 99
	for bbK in list
		{
		if (BoostKind(bbK) != kind)
			continue
		bbG := BoostPctFor(bbK) * BoostShare(bbK)
		if (bbG <= 0 || !BoostCanGo(bbK))
			continue
		bbS := InStr(bbK, "/") ? SubStr(bbK, 1, InStr(bbK, "/") - 1) : ""
		bbR := (bbS != "" && bbS = hitschool) ? 0 : (bbS != "") ? BadgeNumber(bbS) : InStr(bbK, "elemental") ? 8 : 9
		if (bbG > bbGain || (bbG = bbGain && bbR < bbRank))
			bbBest := bbK, bbGain := bbG, bbRank := bbR
		}
	return bbBest
	}

;The hit planned, for the log: "Hydra (hit3)", "hit3", "the hitter's", "learned hit <id>"
PlanName()
	{
	global PlanHit, hitschool, PlanWait
	if (PlanHit = "hitter")
		return "the hitter's hit"
	if (InStr(PlanHit, "learned/") = 1)
		return "learned hit " SubStr(PlanHit, 9)
	pnN := (V1IsFunc("DashShortName") && RegExMatch(PlanHit, "^hit\d$")) ? DashShortName.Call(PlanHit, hitschool) : ""
	if (PlanHit = "" && PlanWait != "")
		return PlanWait ", waiting for its pips"
	return (pnN != "" && pnN != PlanHit) ? pnN " (" PlanHit ")" : PlanHit != "" ? PlanHit : "no hit"
	}

;The damage hit hitN would deal this round against the enemies left (PlanChoose: the planned hit deals the most) -
;HitDamage with the blades and traps on and those in hand that can still go (each once, at its %: SbFound, GbFound,
;blade3, blade4, trap3 - traps on the enemy this round's go on, TrapPick, else the one they're on: TrapSlot - the boss's,
;the one with the most health; counted with solotraps:1 only), an enchant in hand on it: an all-enemies hit on each enemy
;left (its health the most it can take), a one-enemy hit on the one it does the most to; their health not read: an
;all-enemies hit times the plates found
PlanProject(hitN)
	{
	global
	local ppKeepB, ppKeepT, ppB, ppT, ppK, ppL, ppI, ppJ, ppE, ppD, ppSum, ppBest, ppOne, ppUe, ppHh, ppKeys, ppTs
	ppKeepB := AppliedBlades, ppKeepT := BossTraps
	ppB := AppliedBlades.Clone(), ppT := BossTraps.Clone(), ppKeys := []
	for ppI, ppL in [SbFound, GbFound]
		for ppK in ppL
			ppKeys.Push(ppK)
	for ppI, ppK in ["blade3", "blade4", "trap3"]
		if (%ppK% == 1)
			ppKeys.Push(ppK)
	for ppI, ppK in ppKeys
		if (BoostCanGo(ppK) && !ppB.Has(ppK) && !ppT.Has(ppK))
			{
			if (BoostKind(ppK) = "trap")
				ppT[ppK] := BoostPctFor(ppK)
			else
				ppB[ppK] := BoostPctFor(ppK)
			}
	AppliedBlades := ppB, BossTraps := ppT
	ppHh := HitHeads(hitN), ppUe := (V1Ge(enchant, 1) && !ppHh.item)
	ppOne := (ppHh.one != "") ? ppHh.one : (Stat(hitschool "." hitN "target") = 1)
	if (IsObject(EnemyHP) && EnemyHP.Length)
		{
		ppSum := 0, ppBest := 0, ppTs := (BossChoosen != 1 && TrapPick) ? TrapPick : TrapSlot
		for ppI, ppE in EnemyHP
			{
			ppD := Min(HitDamage(hitN, ppUe, ppI == ppTs), ppE.cur)
			ppSum += ppD, ppBest := Max(ppBest, ppD)
			}
		ppD := ppOne ? ppBest : ppSum
		}
	else
		ppD := HitDamage(hitN, ppUe, BossChoosen == 1) * ((ppOne || EnemyPlates.Length < 1) ? 1 : EnemyPlates.Length)
	AppliedBlades := ppKeepB, BossTraps := ppKeepT
	return ppD
	}

;The hit this round's boosts are for (BoostPick) - the one CastBestHit casts first: the kill check's own pick when it can
;kill now; with the game's hand read this look (the user, 2026-10-24), the one dealing the most (PlanProject) of hit4 (a
;picked boss only), hit3, hit2, hit1 in hand you can pay for now (pips saved for one: that one), else of those in hand;
;without it as ever: the first of them you can pay for and aren't saving pips against, else the one pips are saved for,
;else the first in hand. None in hand: the strongest learned hit in no slot ("learned/<id>"); none: ""
PlanChoose()
	{
	global
	local pcL, pcI, pcH, pcBest, pcBestV, pcV, pcLh, pcPass
	if (RegExMatch(KillHit, "^hit[1-4]$"))
		if (%KillHit% == 1)
			return KillHit
	pcL := (BossChoosen == 1) ? ["hit4", "hit3", "hit2", "hit1"] : ["hit3", "hit2", "hit1"]
	if (BoostMemOk)
		{
		pcBest := "", pcBestV := -1
		Loop 2
			{
			pcPass := A_Index
			for pcI, pcH in pcL
				if (%pcH% == 1 && (pcPass = 2 || (PipSaveFor != "" ? PipSaveFor = pcH : Affordable(pcH))))
					{
					pcV := PlanProject(pcH)
					if (pcV > pcBestV)
						pcBest := pcH, pcBestV := pcV
					}
			if (pcBest != "")
				return pcBest
			}
		}
	else
		{
		for pcI, pcH in pcL
			if (%pcH% == 1 && Affordable(pcH) && (PipSaveFor = "" || PipSaveFor = pcH))
				return pcH
		if (RegExMatch(PipSaveFor, "^hit[1-4]$"))
			if (%PipSaveFor% == 1)
				return PipSaveFor
		for pcI, pcH in pcL
			if (%pcH% == 1)
				return pcH
		}
	if (V1IsFunc("LearnHitCards") && LastHandAnswer != "")
		{
		pcLh := LearnHitCards.Call(LastHandAnswer)
		if (pcLh.Length)
			return "learned/" pcLh[1].id
		}
	return ""
	}

;Right before the round's cards are played (after the kill check - it can name the hit, and PipSaveFor is this round's):
;the planned hit (PlanHit, PlanHeads, PlanList: its schools - a party's supports boost for them, Party.ahk) - a blader's or
;healer's, Alt+2's pick's: the hitter's -, and of the blades and traps found (BoostSearch) the ones the chain casts: the
;school blade and trap that add the most to it (blade, BladeDir and its flags BladeU1/2; trap, TrapDir, TrapU1/2), the
;group's (blade2, bladetype, Blade2U1/2; trap2, traptype, Trap2U1/2); every school's (blade3, blade4, trap3, feint) as
;found. A hit of two or more schools (Hydra): only the blade and the trap that add the most go this round - Elemental Blade
;(all three heads) before Balanceblade, before a Storm Blade (one head)
BoostPick()
	{
	global
	local bpL, bpS, bpK, bpF, bpN, bpBest, bpG, bpC, bpI, bpFit, bpNot, bpLog, bpLc, bpCand, bpMax, bpWho, bpHand, bpBestV, bpHh
	local bpHold, bpCost
	PlanHit := "", PlanHeads := "", PlanList := "", BoostOneOfOff := V1Obj(), PlanWait := ""
	;(the party's hit round - Party.ahk PartyTick sends it: none this round till the planned hit's known below)
	PartyHitAt := "", PartyHitAtDuel := BlDuel
	if (hitschool = "")
		return
	if (PartySupport() || (Manual = 1 && HammerSchool != hitschool))
		{
		PlanHit := "hitter", PlanHeads := V1Obj({heads: V1Obj(), total: 0, sure: 0, src: "the hitter's"})
		bpL := HammerPlan != "" ? HammerPlan : (BadgeNumber(HammerSchool) ? HammerSchool : "")
		Loop Parse, bpL, ","
			if (BadgeNumber(A_LoopField) && !PlanHeads.heads.Has(A_LoopField))
				PlanHeads.heads[A_LoopField] := 1, PlanHeads.total += 1
		}
	else
		{
		PlanHit := PlanChoose()
		if (InStr(PlanHit, "learned/") = 1)
			PlanHeads := LearnHitHeads(V1IsFunc("LearnCardOf") ? LearnCardOf.Call(SubStr(PlanHit, 9)) : "")
		else if (PlanHit != "")
			PlanHeads := HitHeads(PlanHit)
		;(no hit the pictures place or the pips pay for - a greyed Hydra waiting for its pips: the game's hand names it,
		;and the boosts go on for that one while the pips come - 2026-10-25: Elemental Blade and Trap held back two
		;rounds with Hydra greyed in hand. The strongest of the hand's hits; nothing's cast for it till it can be)
		if (PlanHit = "" && BoostMemOk && V1IsFunc("VisionCards"))
			{
			bpHand := VisionCards.Call(0, 5000), bpBestV := -1
			if (IsObject(bpHand) && IsObject(bpHand.cards))
				for bpI, bpC in bpHand.cards
					if ((bpC.kind = "damage" || bpC.kind = "aoe") && bpC.num != "" && bpC.num + 0 > bpBestV)
						{
						bpHh := V1Obj()
						if (HeadsParse(bpC.heads, bpHh))
							bpBestV := bpC.num + 0, PlanHeads := bpHh, PlanHeads.src := "the game's hand", PlanWait := (bpC.display != "" ? bpC.display : bpC.name)
						}
			}
		if (!IsObject(PlanHeads) || PlanHeads.total <= 0)
			{
			PlanHeads := V1Obj({heads: V1Obj(), total: 1, sure: 0, src: "your school's"})
			PlanHeads.heads[hitschool] := 1
			}
		;(its schools for the party's supports only when they're known - the game's, PlayerStats.txt's heads: one taken as
		;your school's goes out blank, so a support never throws a blade away for a guess - BoostMisfitDiscard)
		if (PlanHeads.sure)
			for bpI, bpS in HeadsOrder(PlanHeads.heads)
				PlanList .= (PlanList = "" ? "" : ",") bpS
		;(the party's hit round - v1.0.0: the log round the planned hit is likely to go out in, the earliest it can - this
		;round's when it's paid for, else when its pips can be there, a new pip a round worth 2 at most (a power pip, your
		;school's hit). Early is the safe side: a support's blade cast a round early stays on till the hit. A learned hit in
		;no slot, pips not read: not said - the supports cast as ever. Party.ahk PartyTick sends it, PartyHitHold reads it)
		if (RegExMatch(PlanHit, "^hit[1-4]$"))
			{
			bpCost := Stat(hitschool "." PlanHit "pips")
			if (PipsNow >= 0 && Affordable(PlanHit))
				PartyHitAt := V1N(BlRound) + 1
			else if (PipsNow >= 0 && V1IsNum(bpCost) && bpCost > PipsNow)
				PartyHitAt := V1N(BlRound) + 1 + Ceil((bpCost - PipsNow) / 2)
			}
		}
	;(the school blade and trap, the group's)
	blade := 0, BladeDir := "", BladeU1 := "", BladeU2 := ""
	bpK := BoostBest(SbFound, "blade")
	if (bpK != "")
		bpF := KeyFlags(bpK), blade := 1, BladeDir := SubStr(bpK, 1, InStr(bpK, "/") - 1), BladeU1 := bpF[1], BladeU2 := bpF[2]
	trap := 0, TrapDir := "", TrapU1 := "", TrapU2 := ""
	bpK := BoostBest(SbFound, "trap")
	if (bpK != "")
		bpF := KeyFlags(bpK), trap := 1, TrapDir := SubStr(bpK, 1, InStr(bpK, "/") - 1), TrapU1 := bpF[1], TrapU2 := bpF[2]
	blade2 := 0, Blade2U1 := "", Blade2U2 := ""
	bpK := BoostBest(GbFound, "blade")
	if (bpK != "")
		bpF := KeyFlags(bpK), blade2 := 1, bladetype := bpK, Blade2U1 := bpF[1], Blade2U2 := bpF[2]
	trap2 := 0, Trap2U1 := "", Trap2U2 := ""
	bpK := BoostBest(GbFound, "trap")
	if (bpK != "")
		bpF := KeyFlags(bpK), trap2 := 1, traptype := bpK, Trap2U1 := bpF[1], Trap2U2 := bpF[2]
	bpN := 0
	for bpS in PlanHeads.heads
		bpN += 1
	;(what fits the plan, for the log - said when it's more than one school, the game's hand was read, or for the hitter)
	bpWho := (bpN >= 2 || BoostMemOk || PlanHit = "hitter")
	if (bpWho)
		{
		bpFit := "", bpNot := ""
		for bpI, bpLc in [SbFound, GbFound]
			for bpK in bpLc
				{
				bpG := BoostShare(bpK)
				if (bpG > 0)
					bpFit .= (bpFit = "" ? "" : ", ") bpK " " BoostPctFor(bpK) "%" (bpG < 1 ? " (" BoostHeadsText(bpK) ")" : "")
				else
					bpNot .= (bpNot = "" ? "" : ", ") bpK
				}
		for bpI, bpK in ["blade3", "blade4", "trap3", "feint"]
			if (%bpK% == 1)
				bpFit .= (bpFit = "" ? "" : ", ") bpK " " BoostPctFor(bpK) "%"
		}
	;(a hit of two or more schools: the one blade and the one trap that add the most this round)
	if (bpN >= 2)
		{
		BoostOneOf([["blade", BladeDir "/blade"], ["blade2", bladetype], ["blade3", "blade3"], ["blade4", "blade4"]], "blade")
		BoostOneOf([["trap", TrapDir "/trap"], ["trap2", traptype], ["trap3", "trap3"]], "trap")
		}
	;(a party battle's blader or healer, the party's hit round - Settings: partyhitround, off: its blades and traps wait
	;for the round the hitter's hit is due - Party.ahk PartyHitHold. Held: none of them this round - the chain goes on
	;as with none in hand: Tower Shield, a hit only with nothing else to go, else a pass)
	if (PartySupport() && (bpHold := PartyHitHold()) != "")
		{
		for bpI, bpK in ["blade", "blade2", "blade3", "blade4", "trap", "trap2", "trap3", "trap4", "feint"]
			%bpK% := 0
		BoostOneOfOff := V1Obj()
		DebugLog("  " bpHold)
		}
	if (bpWho)
		{
		bpLog := ""
		for bpI, bpC in [["feint", "feint"], ["trap", TrapDir "/trap"], ["trap2", traptype], ["trap3", "trap3"], ["blade", BladeDir "/blade"], ["blade2", bladetype], ["blade3", "blade3"], ["blade4", "blade4"]]
			{
			bpS := bpC[1]
			if (%bpS% == 1 && (BoostKind(bpC[2]) = "blade" || TrapOn == 1) && BoostCanGo(bpC[2]))
				bpLog .= (bpLog = "" ? "" : ", ") bpC[2]
			}
		DebugLog("  plan: " PlanName() (PlanHeads.total > 0 && PlanHit != "hitter" ? ": " HeadsText(PlanHeads) : PlanList != "" ? " (" PlanList ")" : "")
			. (PlanHit = "hitter" ? " - its schools: " (HammerPlan != "" ? HammerPlan " (its planned hit)" : HammerSchool != "" ? HammerSchool : "not known") : "")
			. " - fits: " (bpFit = "" ? "nothing in hand" : bpFit) (bpNot != "" ? " - not for it: " bpNot : "") "; this round: " (bpLog = "" ? "none" : bpLog))
		}
	}

;"1 of 3 heads" - how many of the planned hit's heads boost key fits (BoostPick's log)
BoostHeadsText(key)
	{
	global PlanHeads
	bhtN := 0, bhtF := 0
	for bhtS in PlanHeads.heads
		bhtN += 1, bhtF += BoostFits(key, bhtS) ? 1 : 0
	return bhtF " of " bhtN " heads"
	}

;Of the battle code's flags in list ([its variable's name, its boost key]) of kind ("blade" / "trap") set (1) whose boost
;can go, only the one adding the most to the planned hit stays set this round (ties: list's order - the chain's); the
;others 0 - noted (BoostOneOfOff[kind]) and set again if the one kept can't be cast after all (BoostOneOfBack)
BoostOneOf(list, kind)
	{
	global
	local booI, booP, booV, booK, booG, booBest, booBestG, booOff
	booBest := "", booBestG := -1, booOff := []
	for booI, booP in list
		{
		booV := booP[1], booK := booP[2]
		if (%booV% != 1)
			continue
		if (!BoostCanGo(booK))
			{
			%booV% := 0
			continue
			}
		booG := BoostPctFor(booK) * BoostShare(booK)
		if (booG > booBestG)
			booBest := booV, booBestG := booG
		}
	for booI, booP in list
		{
		booV := booP[1]
		if (booV != booBest)
			{
			if (%booV% == 1)
				booOff.Push(booV)
			%booV% := 0
			}
		}
	if (!IsObject(BoostOneOfOff))
		BoostOneOfOff := V1Obj()
	BoostOneOfOff[kind] := booOff
	}

;The flags of kind ("blade" / "trap") BoostOneOf took off this round set again: the one it kept can't be cast after all
;(no copy of it in hand can go now - BoostCopyPick: UseBlade, UseTrap), so the chain goes on to the next that can
BoostOneOfBack(kind)
	{
	global
	local boobI, boobV, boobL
	if (!IsObject(BoostOneOfOff) || !IsObject(BoostOneOfOff[kind]) || !BoostOneOfOff[kind].Length)
		return
	boobL := ""
	for boobI, boobV in BoostOneOfOff[kind]
		%boobV% := 1, boobL .= (boobL = "" ? "" : ", ") boobV
	BoostOneOfOff[kind] := []
	DebugLog("  the " kind "s held back this round can go instead: " boobL)
	}

;The wand's card isn't cast while it would use up a blade or trap on you meant for the planned hit - both their heads the
;game's (or PlayerStats.txt's): a boost on that fits a head of each. Else (not known) it's cast, as before
WandWastes()
	{
	global
	local wwW, wwI, wwL, wwK, wwV, wwS, wwT
	if (!IsObject(PlanHeads) || !PlanHeads.sure || !RegExMatch(PlanHit, "^hit[1-4]$"))
		return false
	wwW := HitHeads("wand")
	if (!wwW.sure)
		return false
	for wwI, wwL in [AppliedBlades, BossTraps]
		for wwK, wwV in wwL
			for wwS in wwW.heads
				if (BoostFits(wwK, wwS))
					for wwT in PlanHeads.heads
						if (BoostFits(wwK, wwT))
							{
							DebugLog("  wand not cast: it would use up " BoostBase(wwK) " (" wwV "%) meant for " PlanName())
							return true
							}
	return false
	}

;A party battle's blader or healer (the user, 2026-10-24): a blade in hand - the game's - that boosts neither the hitter's
;planned hit (its schools as the hitter knows them for sure: HammerPlan, Party.ahk - not heard yet, round 1 before its
;first plan, a plan it isn't sure of, an older bot: nothing goes, a discard can't be undone) nor this wizard's own school
;is right-clicked away, by its box (a fresh look at the hand laid on the game's cards - BoostBoxes); never a treasure
;card, never one you said never to discard (Spells tab), nothing while you play; once a round, at most discardmax.
;Returns how many
BoostMisfitDiscard()
	{
	global
	local bmdAll, bmdWant, bmdI, bmdB, bmdP, bmdC, bmdLc, bmdDid, bmdMost, bmdS, bmdFits, bmdK, bmdO, bmdX, bmdY
	if (BoostMisfitDone || !BoostMemOk || !Stat("discardunused") || LearnAll)
		return 0
	BoostMisfitDone := 1
	;(the hitter's plan only - never its school taken for it)
	bmdWant := HammerPlan
	if (bmdWant = "" || hitschool = "" || (V1IsFunc("PlayerActing") && PlayerActing.Call()))
		return 0
	bmdAll := BoostBoxes()
	if (!IsObject(bmdAll))
		return 0
	bmdDid := 0, bmdMost := StatOr("discardmax", 3) + 0, bmdI := 1
	while (bmdI <= bmdAll.boxes.Length && bmdDid < bmdMost)
		{
		bmdB := bmdAll.boxes[bmdI], bmdC := bmdB.m, bmdP := BoostsParse(bmdC.boosts), bmdLc := ""
		if (InStr(bmdB.known, "learned/") = 1 && V1IsFunc("LearnCardOf"))
			bmdLc := LearnCardOf.Call(SubStr(bmdB.known, 9))
		else if (bmdB.known != "" && V1IsFunc("LearnCardInSlot"))
			bmdLc := LearnCardInSlot.Call(StrReplace(bmdB.known, "/", "\"))
		bmdFits := !IsObject(bmdP) || bmdP.sch = "all"
		if (!bmdFits)
			Loop Parse, bmdP.sch, ","
				if (A_LoopField = hitschool || InStr("," bmdWant ",", "," A_LoopField ","))
					bmdFits := true
		if (bmdC.kind != "blade" || bmdFits || bmdC.tc || (IsObject(bmdLc) && (LearnHasFlag.Call(bmdLc, "hold") || LearnHasFlag.Call(bmdLc, "tc"))))
			{
			bmdI += 1
			continue
			}
		bmdX := Round(bmdB.l + bmdB.w / 2), bmdY := Round(bmdB.t + bmdB.h * 0.6)
		MoveToCard(bmdX, bmdY)
		s(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
		;(Wizard101 gone to the tray - Settings: traygame: not clicked - it would land on the window behind it)
		if (GameInTray)
			break
		Click("right")
		bmdDid += 1
		DebugLog("  Discarded " (V1IsFunc("LearnMemGame") ? LearnMemGame.Call(bmdC) : bmdC.name) " - it boosts " bmdP.sch ", not the hitter's " bmdWant " nor your " hitschool " (right-click at " bmdX - GameLeft "," bmdY - GameTop ")")
		bmdAll.boxes.RemoveAt(bmdI)
		for bmdK, bmdO in bmdAll.boxes
			bmdO.l += (bmdK < bmdI ? HalfPitch : -HalfPitch)
		s(Stat("discardafter"))
		}
	if (bmdDid)
		CenterMouse(), VisionForget()
	return bmdDid
	}

;Blades only count toward our hits when they went on our own wizard: the hammer is our school icon
;(Bladestorm buffs the whole team). An ally hammer, a manual Alt+2 hammer or no player found -> not counted
BladeOnUs(card)
	{
	if (card = "blade4")
		return true
	;(v1: a place not read - blank: "" < 10 compared as text, true)
	return (school != "") && (school = hitschool) && V1Lt(V1Abs(V1Sub(hammerX, schoolX)), Px(10)) && V1Lt(V1Abs(V1Sub(hammerY, schoolY)), Px(10))
	}

;A hit uses up the hammer's blades and the boss's traps. With reboost:1 the battle code may also cast
;its blades/traps again for the next hit (normally each is cast once per battle). The hits counted, and the round of the
;last (the game's log): a party's bladers and healers see them - their blades on this wizard are spent (Party.ahk); a
;blader's or healer's own blades went on the hitter: cast again after the hitter's hit, not its own.
;hh: the hit's heads (HitHeads, LearnHitHeads). Known (the game's, or PlayerStats.txt's): only the blades and traps that
;fit one of its schools go - a Power Nova leaves an Elemental Blade on, a Hydra takes it; one whose schools aren't known
;goes - and the party's told its schools (PartyLastSch: a support's blades that fit none stay on); with reboost:1 only
;those are cast again, and the blades cast on you that weren't seen there (BoostUnrec: UseBlade) that fit it. Not known:
;all of them, as before. With reboost:1 Autofarmer.ahk DiscardSpare keeps a blade's copies in hand for that (v1.9.1 -
;ReboostKeepRole, inside this test; and while a hit can still free them - BoostFreeable, by the lists this frees the
;flags of: change them together)
ConsumeBoosts(hh := "")
	{
	global PartyLastSch, AppliedBlades, BossTraps, PartyHits, PartyHitR, BoostUnrec ; (v1 globals it sets)
	cbSure := IsObject(hh) && hh.sure && hh.total > 0
	cbGone := []
	if (cbSure)
		{
		cbStill := ""
		for cbI, cbList in [AppliedBlades, BossTraps]
			{
			cbOut := []
			for cbKey in cbList
				{
				cbFit := (BoostSchools(cbKey) = "")
				for cbS in hh.heads
					if (BoostFits(cbKey, cbS))
						cbFit := true
				if (cbFit)
					cbOut.Push(cbKey)
				else
					cbStill .= (cbStill = "" ? "" : ", ") cbKey
				}
			for cbJ, cbKey in cbOut
				cbList.Delete(cbKey), cbGone.Push(cbKey)
			}
		PartyLastSch := ""
		for cbS in hh.heads
			PartyLastSch .= (PartyLastSch = "" ? "" : ",") cbS
		if (cbStill != "")
			{
			cbText := ""
			for cbJ, cbKey in cbGone
				cbText .= (cbText = "" ? "" : ", ") cbKey
			DebugLog("  used up by " HeadsText(hh) ": " (cbText = "" ? "nothing" : cbText) "; still on: " cbStill)
			}
		}
	else
		{
		AppliedBlades := V1Obj()
		BossTraps := V1Obj()
		PartyLastSch := ""
		}
	PartyHits := (PartyHits ? PartyHits : 0) + 1, PartyHitR := (BlRound ? BlRound : 0) + 1
	if (Stat("reboost") == 1 && !PartySupport())
		{
		if (!cbSure)
			ResetUsed()
		else
			{
			;(and each blade cast on you that wasn't seen there - your plate or badge not read that round: BoostUnrec - that
			;fits one of its schools, or whose schools aren't known: used up with it as well)
			cbReset := cbGone.Clone(), cbLeft := []
			for cbJ, cbKey in (IsObject(BoostUnrec) ? BoostUnrec : [])
				{
				cbFit := (BoostSchools(cbKey) = "")
				for cbS in hh.heads
					if (BoostFits(cbKey, cbS))
						cbFit := true
				if (cbFit)
					cbReset.Push(cbKey)
				else
					cbLeft.Push(cbKey)
				}
			BoostUnrec := cbLeft
			for cbJ, cbKey in cbReset
				{
				;(a treasure or item card's copy: its own once-a-battle; the deck's: its sharpened or plain flag)
				if (RegExMatch(cbKey, "@([a-z]+)\+?$", &cbM))
					{
					if (IsObject(BoostSrcUsed))
						BoostSrcUsed.Delete(BoostBase(cbKey) "@" cbM[1])
					}
				else if (IsObject(cbF := KeyFlags(cbKey)))
					UsedFlagSet(SubStr(cbKey, -1) = "+" ? cbF[1] : cbF[2], 0)
				}
			}
		}
	}

;Returns [{cur, max}, ...] for every "current/max" in the OCR text, or "" if anything health-like couldn't be read
ParseHealth(text)
	{
	static pair := "(?<![\d,.])(\d{1,3}(?:,\d{3})+|\d+)/(\d{1,3}(?:,\d{3})+|\d+)(?![\d,])"
	text := RegExReplace(text, "(\d)\s*([,./])\s*(?=\d)", "$1$2")
	text := RegExReplace(text, "(\d)\.(?=\d{3}(?!\d))", "$1,")
	list := []
	pos := 1
	while (pos := RegExMatch(text, pair, &m, (pos)<1 ? (pos)-1 : (pos)))
		{
		cur := StrReplace(m[1], ",") + 0
		mx := StrReplace(m[2], ",") + 0
		if (mx <= 0) || (cur < 1) || (cur > mx)
			return ""
		list.Push(V1Obj({cur: cur, max: mx}))
		pos += StrLen((m&&m[0]))
		}
	;Anything but a space touching a pair, or a digit (or l/I/| standing in for a 1) near it, means part of a number was misread
	rest := RegExReplace(text, pair, "#")
	if (list.Length < 1 || list.Length > 4 || RegExMatch(rest, "\d{3,}|\d/|/\d|[^\s#]#|#[^\s#]|\d[ \t]*#|#[ \t]*\d|[lI|][ \t]*#"))
		return ""
	;A health line holds exactly one pair and nothing else
	Loop Parse, rest, "`n", "`r"
		{
		if (InStr(A_LoopField, "#")) && (RegExMatch(A_LoopField, "#.*#") || RegExMatch(A_LoopField, "[A-Za-z]"))
			return ""
		}
	return list
	}

;An OCR line of an enemy nameplate along the top: a name on the plates' row - its top ~27 and ~15 tall at UI scale 1,
;the same at 1440p (UI 1.144: top 31, 17 tall) and 1920x1200 (UI 1.265: top 34, 19 tall) - or a plate's health line
;under it (top ~47; OCR doesn't always read it). Not by where the plates sit across: their spacing differs with the
;window (511 at 1440p, 331 at 1920x1200, at UI scale 1). A mob's floating name over its head can reach up into the
;strip, but it's taller (~22) or lower; its RANK line never counts. rects: unused (the strip's lines)
OnPlateRow(r, rects := "")
	{
	if (RegExMatch(r.text, "i)^\W*RANK\b"))
		return false
	top := (r.y - GameTop) / UiScale, tall := r.h / UiScale
	if (IsHealthLine(r.text))
		return Abs(top - 47) <= 7 && tall <= 20
	return Abs(top - 27) <= 5 && Abs(tall - 15) <= 3
	}

;OCR line kinds: a plate's name line (letters, no digits) or its health line ("current/max")
IsNameLine(t)
	{
	return RegExMatch(t, "[A-Za-z]{2,}") && !RegExMatch(t, "\d")
	}

IsHealthLine(t)
	{
	return RegExMatch(t, "\d\s*/\s*\d|\d{3,}")
	}

;Two OCR line boxes overlap side to side (and, with sameRow, top to bottom too)
BoxesOverlap(a, b, sameRow)
	{
	if (a.x > b.x + b.w) || (b.x > a.x + a.w)
		return false
	return !sameRow || !((a.y > b.y + b.h) || (b.y > a.y + a.h))
	}

SameHealth(a, b)
	{
	if (!IsObject(a) || !IsObject(b) || a.Length != b.Length)
		return false
	for i, e in a
		{
		if (e.cur != b[i].cur) || (e.max != b[i].max)
			return false
		}
	return true
	}

;Reads every enemy's health off the nameplate strip. Windows OCR sometimes drops a line from a wide
;image, so: find the plates from every name and health line seen at two sizes, then read each plate's
;health on its own at both sizes. Anything that doesn't add up -> false (health unknown)
;v1.0.0: the game's memory's health first (EnemyMemHealth) - with memclicks:1 the plates from it too, no OCR at all; else
;the plates found on the screen as before and each one's health from the memory when every enemy sits on its own plate,
;the per-plate reads below skipped. memOnly (the kill check with healthocr:0 and memclicks:1): the memory's alone, no OCR
ReadEnemyHealth(memOnly := false)
	{
	global EnemyHP, EnemyPlates, EnemyPlatesAt, BossSlot, TrapSlot, HealthStatus, BossMax, BossTraps ; (v1 globals it sets)
	EnemyHP := "", EnemyPlates := [], EnemyPlatesAt := A_TickCount
	BossSlot := 0, TrapSlot := 0
	;(memclicks:1 - the plates and their health from the game's memory, where a hit or trap is clicked too: EnemyMemHealth)
	if ((Stat("memclicks") = 1 || memOnly) && EnemyMemHealth())
		{
		TrapSlot := TrapFoeSlot(EnemyHP, EnemyPlates)
		return true
		}
	if (memOnly)
		{
		EnemyHP := "", EnemyPlates := []
		HealthStatus := "Not read from the game's memory (healthocr:0 - no OCR)" (NavBattleWhy != "" ? ": " NavBattleWhy : "")
		return false
		}
	;platestrip is in pixels at UI scale 1: the plates grow with the UI
	stripH := Round(Stat("platestrip") * UiScale)
	if (stripH > GameH)
		stripH := GameH
	;OCR images can't be wider than 10000px, keep the two scales clearly different within that
	maxScale := 9900 / GameW
	scale1 := Stat("ocrscale")
	if (scale1 <= 0)
		scale1 := 1
	scale2 := scale1 + 1
	if (scale2 > maxScale)
		scale2 := maxScale
	if (scale1 > scale2 - 0.5)
		scale1 := scale2 - 0.5
	if (scale1 <= 0.5)
		{
		HealthStatus := "The game window is too wide to read health at two different sizes"
		return false
		}
	MouseMove(GameRight - 20, ScreenY, 0)

	;1) Plates: name lines (deduped across both reads), each with the health line under it if one was seen
	names := [], healths := [], seen := "", offRow := ""
	Loop 2
		{
		stripRead := A_Index
		seen := OcrRect(GameLeft, GameTop, GameW, stripH, "en", (A_Index == 1) ? scale1 : scale2, &rects)
		if (ErrorLevel)
			{
			HealthStatus := ErrorLevel
			return false
			}
		for i, r in rects
			{
			;(not the Shop button in the top left corner - its "SHOP" reads like an enemy's name)
			if (r.x + r.w / 2 < GameLeft + Px(85) || RegExMatch(r.text, "i)^\W*(SHOP|EARN\W*CROWNS|UPGRADE\W*NOW)\W*$"))
				continue
			;(only the plates' own row - not a mob's floating name over its head, which can reach into the strip)
			if (!OnPlateRow(r, rects))
				{
				if (stripRead = 1 && IsNameLine(r.text))
					offRow .= (offRow = "" ? "" : ", ") r.text " at " r.x - GameLeft "," r.y - GameTop
				continue
				}
			if (IsHealthLine(r.text))
				healths.Push(r)
			else if (IsNameLine(r.text))
				names.Push(r)
			}
		}
	plates := []
	for i, n in names
		{
		dupe := false
		for j, p in plates
			{
			if (BoxesOverlap(p.name, n, true))
				dupe := true
			}
		if (!dupe)
			plates.Push(V1Obj({name: n, health: ""}))
		}
	for i, hl in healths
		{
		owner := ""
		for j, p in plates
			{
			if (IsObject(p.name) && BoxesOverlap(p.name, hl, false) && hl.y > p.name.y && hl.y < p.name.y + p.name.h * 4)
				owner := p
			else if (IsObject(p.health) && BoxesOverlap(p.health, hl, true))
				owner := p
			}
		if (!IsObject(owner))
			plates.Push(owner := V1Obj({name: "", health: hl, votes: []}))
		else if (!IsObject(owner.health))
			owner.health := hl
		;(the strip's own read of the line only finds the plate - no vote: read plain, the red numbers on the
		;parchment come back empty or wrong; each plate's are read below with only their red)
		if (!IsObject(owner.votes))
			owner.votes := []
		}
	;Left to right, like the slots on screen
	Loop plates.Length - 1
		{
		Loop plates.Length - A_Index
			{
			a := plates[A_Index], b := plates[A_Index + 1]
			if ((IsObject(a.name) ? a.name.x : a.health.x) > (IsObject(b.name) ? b.name.x : b.health.x))
				plates[A_Index] := b, plates[A_Index + 1] := a
			}
		}
	if (offRow != "")
		DebugLog("  nameplates: not on the plates' row, left out: " SubStr(offRow, 1, 160))
	if (plates.Length < 1 || plates.Length > 4)
		{
		HealthStatus := "Couldn't find the enemy nameplates (" . plates.Length . " found): " . SubStr(RegExReplace(seen, "\s+", " "), 1, 60)
		;(none read: there's always a first plate - its box is where a single-target hit is clicked; not with the Crown
		;shop's buttons read up there - its Earn Crowns / Upgrade Now)
		if (plates.Length < 1 && !RegExMatch(seen, "i)cr[o0]wn|upgrade|earn"))
			EnemyPlates.Push(V1Obj({x: GameLeft + Px(205), y: GameTop + Px(36)}))
		return false
		}
	;Where each plate is (its name, else its health line), left to right: a single-target hit clicks one
	;(kept even if the health can't be read below; with the name OCR read on it - TrapMemHealth matches the game's memory
	;to the plates by it)
	for i, p in plates
		{
		b := IsObject(p.name) ? p.name : p.health
		EnemyPlates.Push(V1Obj({x: b.x + b.w // 2, y: b.y + b.h // 2, name: IsObject(p.name) ? p.name.text : ""}))
		}
	;(v1.0.0: the game's memory's health on these plates - every enemy on its own, left to right, where its plate is -
	;instead of reading each plate's off the screen: EnemyMemHealth. Each plate's box - TrapFoeSlot finds the traps' enemy by
	;it - worked out as the reads below work it out)
	if (EnemyMemHealth(EnemyPlates))
		{
		for i, p in plates
			{
			if (IsObject(p.health))
				b := p.health, cx := b.x - b.h, cy := b.y - b.h // 2, cw := b.w + b.h * 2, ch := b.h * 2
			else
				b := p.name, cx := b.x - b.h * 2, cy := b.y + b.h, cw := (b.w > b.h * 10 ? b.w : b.h * 10) + b.h * 4, ch := b.h * 3
			top := IsObject(p.name) ? p.name : b
			p.box := V1Obj({x1: (top.x < cx ? top.x : cx) - top.h * 5, y1: top.y - top.h * 2, x2: cx + cw + top.h, y2: cy + ch + top.h})
			}
		TrapSlot := TrapFoeSlot(EnemyHP, plates)
		return true
		}

	;2) Each plate's health also read on its own at both sizes. Every read is a vote: at least two must
	;agree and none may disagree (a misread digit that still looks like health won't repeat exactly)
	list := []
	for i, p in plates
		{
		if (!IsObject(p.votes))
			p.votes := []
		if (IsObject(p.health))
			{
			b := p.health
			cx := b.x - b.h, cy := b.y - b.h // 2, cw := b.w + b.h * 2, ch := b.h * 2
			}
		else
			{
			b := p.name
			cx := b.x - b.h * 2, cy := b.y + b.h, cw := (b.w > b.h * 10 ? b.w : b.h * 10) + b.h * 4, ch := b.h * 3
			}
		;(only the red pixels read - the numbers; just round their glyphs when they're found, not the whole box, which
		;can hold a bit of the plate's icon; their 3s and 5s told by their shape: HealthDigits)
		;(looked for a good way either side: the strip's read of the line can start or end a digit or two short)
		;(by the helper first, by the digits' shape - VisionPlate: two votes; else OCR)
		vp := VisionPlate(cx - b.h * 3, cy, cx + cw + b.h * 3, cy + ch)
		if (IsObject(vp))
			p.votes.Push([V1Obj({cur: vp.cur, max: vp.max})]), p.votes.Push([V1Obj({cur: vp.cur, max: vp.max})])
		gl := IsObject(vp) ? "" : HealthGlyphs(cx - b.h * 3, cy, cw + b.h * 6, ch)
		;(the plate's own box kept as it is - the boss click's matched against it below)
		gx := cx, gy := cy, gw := cw, gh := ch
		if (IsObject(gl) && gl.Length >= 3)
			GlyphsBox(gl, (gl[1].y2 - gl[1].y1) // 2 + 2, &gx, &gy, &gw, &gh)
		if (!IsObject(vp))
			{
			p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", scale1, &redLines, 1), gl)))
			p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", scale2, &redLines, 1), gl)))
			}
		;(the two don't make two agreeing reads - one came out short: a third, at a size between)
		got := 0
		for j, v in p.votes
			got += IsObject(v) ? 1 : 0
		if (got < 2)
			p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", (scale1 + scale2) / 2, &redLines, 1), gl)))
		agreed := "", count := 0
		for j, v in p.votes
			{
			if (!IsObject(v))
				continue
			if (v.Length != 1 || (IsObject(agreed) && !SameHealth(agreed, v)))
				{
				HealthStatus := "Conflicting health reads on nameplate " . i . " of " . plates.Length
				return false
				}
			agreed := v, count++
			}
		if (count < 2)
			{
			HealthStatus := "Couldn't read the health on nameplate " . i . " of " . plates.Length
			return false
			}
		list.Push(agreed[1])
		;Whole plate, for matching the Alt+1 boss click: the diamond sits left of the text, pips above it
		top := IsObject(p.name) ? p.name : b
		p.box := V1Obj({x1: (top.x < cx ? top.x : cx) - top.h * 5, y1: top.y - top.h * 2, x2: cx + cw + top.h, y2: cy + ch + top.h})
		}
	EnemyHP := list
	HealthStatus := ""
	;Boss clicked on its nameplate (Alt+1): the plate under the click is the boss, so traps only count against it
	if (BossChoosen == 1)
		{
		for i, p in plates
			{
			if (BossX >= p.box.x1 && BossX <= p.box.x2 && BossY >= p.box.y1 && BossY <= p.box.y2)
				BossSlot := BossSlot ? -1 : i
			}
		if (BossSlot < 0)
			BossSlot := 0
		;The boss keeps its max health, so a plate with a different max isn't it
		if (BossSlot)
			{
			if (!BossMax)
				BossMax := list[BossSlot].max
			else if (list[BossSlot].max != BossMax)
				BossSlot := 0
			}
		if (BossMax)
			{
			alive := 0
			for i, e in list
				{
				if (e.max == BossMax)
					alive++
				}
			if (alive == 0)
				{
				;Boss is gone, any traps we put on it went with it
				BossTraps := V1Obj()
				BossSlot := 0
				}
			else if (alive > 1)
				BossSlot := 0
			}
		}
	;The enemy our traps are on (the kill check counts them on it only): the boss's plate; else the plate of the one with the
	;most health they went on - TrapFoeSlot
	TrapSlot := (BossChoosen == 1) ? BossSlot : TrapFoeSlot(list, plates)
	return true
	}

;The enemies' health from the game's memory (v1.0.0, TODO.md goal 3) - ReadEnemyHealth's first try: NavBattle's enemies
;(the helper's /battle, READ-ONLY, read now), used only when every one alive has its health and most health read, none is
;hidden by the game (hide: a boss whose health it hides - its plate's number may not be the memory's), there are 1-4 of
;them, and no boss was picked with Alt+1 (its plate is the one under your click, by the boxes the screen's reads give - as
;ever). onScreen: the plates the OCR found (ReadEnemyHealth's, left to right) - each enemy put on one in the same order
;across, its plate's middle (the memory's x) within Px(160) of the plate's: every one, or none used. onScreen "": the
;plates from the game's memory too - memclicks:1 only (where a single-target hit and a trap are clicked: NOT TRIED in the
;game yet) - each one's box (Vision.ahk NavPlatePx), EnemyPlates [{x, y, name, box}]. Sets EnemyHP ({cur, max}, left to
;right) - and EnemyPlates with no onScreen - and HealthStatus: true. False: nothing set - read off the screen, as before
;Only while one game window runs (Vision.ahk VisionMemOneClient, v1.0.0 review: with two or more navmem can be on another
;client - another battle's enemies laid on these plates)
EnemyMemHealth(onScreen := "")
	{
	global EnemyHP, EnemyPlates, HealthStatus ; (v1 globals it sets)
	if (BossChoosen == 1 || !V1IsFunc("NavBattle") || !V1IsFunc("NavPlatePx") || !V1IsFunc("VisionMemOneClient") || !VisionMemOneClient.Call())
		return false
	emhB := NavBattle.Call()
	if (!IsObject(emhB) || !IsObject(emhB.foes))
		return false
	emhFoes := []
	for emhI, emhF in emhB.foes
		{
		;(one at 0: gone - its plate with it)
		if (emhF.health != "" && emhF.health <= 0)
			continue
		if (emhF.health = "" || emhF.max = "" || emhF.max <= 0 || emhF.health > emhF.max || emhF.hide = 1 || emhF.x = "")
			return false
		emhFoes.Push(emhF)
		}
	if (emhFoes.Length < 1 || emhFoes.Length > 4)
		return false
	;(left to right, as the plates are)
	Loop emhFoes.Length - 1
		Loop emhFoes.Length - A_Index
			if (emhFoes[A_Index].x > emhFoes[A_Index + 1].x)
				emhT := emhFoes[A_Index], emhFoes[A_Index] := emhFoes[A_Index + 1], emhFoes[A_Index + 1] := emhT
	emhAt := []
	if (IsObject(onScreen))
		{
		if (onScreen.Length != emhFoes.Length)
			return false
		for emhI, emhF in emhFoes
			if (onScreen[emhI].x = "" || Abs(GameLeft + emhF.x * GameW - onScreen[emhI].x) > Px(160))
				return false
		}
	else
		{
		if (Stat("memclicks") != 1)
			return false
		for emhI, emhF in emhFoes
			{
			if (!NavPlatePx.Call(emhF, &emhX, &emhY))
				return false
			emhAt.Push(V1Obj({x: emhX, y: emhY, name: emhF.name, box: V1Obj({x1: Round(GameLeft + emhF.l * GameW), y1: Round(GameTop + emhF.t * GameH)
				, x2: Round(GameLeft + emhF.r * GameW), y2: Round(GameTop + emhF.b * GameH)})}))
			}
		}
	EnemyHP := [], emhText := ""
	for emhI, emhF in emhFoes
		EnemyHP.Push(V1Obj({cur: emhF.health, max: emhF.max})), emhText .= (emhText = "" ? "" : ", ") (emhF.name != "" ? emhF.name " " : "") emhF.health "/" emhF.max
	if (!IsObject(onScreen))
		EnemyPlates := emhAt
	HealthStatus := ""
	DebugLog("  enemies' health from the game's memory: " emhText (IsObject(onScreen) ? " (on the plates the screen shows)" : " (their plates where the memory has them - memclicks)"))
	return true
	}

;---- Traps on the enemy with the most health (the user, 2026-10-24: "Can we have the wizard trap the enemy with the
;highest health always?") ----
;No boss picked with Alt+1 and not a party's blader or healer: every battle's traps (Hex, Feint, Elemental and school
;traps - those that fit the planned hit's schools: BoostPick) go on the enemy with the most health (TrapTarget); BossTraps
;holds the traps on that one enemy (TrapPut), found again each round by its plate and its most health (TrapFoeSlot), and
;the kill check counts them on it only - with solotraps:1 (you fight alone: another's hit uses them up unseen)

;Where this round's traps go (the battle code, right before BoostPick): TrapOn, TrapAtX / TrapAtY, TrapMine (noted for
;the kill check: TrapPut), TrapAtMax, TrapPick, TrapWhy. The boss picked with Alt+1: on it, as ever; a party battle's
;blader or healer: the enemy the hitter goes for (Party.ahk PartyTrapTarget - not noted, as ever); else - with traps on
;(usetraps) and one in hand - the enemy with the most health (TrapTarget). None found: no traps this round
TrapWhere()
	{
	global
	TrapOn := (BossChoosen == 1), TrapAtX := bossX, TrapAtY := bossY, TrapMine := TrapOn, TrapAtMax := "", TrapPick := 0, TrapWhy := ""
	if (TrapOn)
		return
	if (PartySupport())
		{
		if (PartyTrapTarget(&TrapAtX, &TrapAtY))
			TrapOn := 1
		return
		}
	if (Stat("usetraps") && TrapsInHand() && TrapTarget(&TrapAtX, &TrapAtY, &TrapAtMax))
		TrapOn := 1, TrapMine := 1
	}

;A trap in hand the chain could cast: a Feint, Hex (trap3), trap4, a school's or a group's trap found (SbFound, GbFound -
;BoostSearch: by its picture or the game's hand)
TrapsInHand()
	{
	global
	local tihI, tihL, tihK
	if (feint == 1 || trap3 == 1 || trap4 == 1)
		return true
	for tihI, tihL in [SbFound, GbFound]
		if (IsObject(tihL))
			for tihK in tihL
				if (BoostKind(tihK) = "trap")
					return true
	return false
	}

;Where a trap goes with no boss picked (TrapWhere): the enemy with the most health - the plates read as the kill check
;reads them (ReadEnemyHealth: the helper's digits, else OCR; read again when the last read is over 8 s old); their
;health not read, the game's memory's (TrapMemHealth - 2026-10-25 23:28:08 the Hex went on the planned hit's target,
;nameplate 2's health not read, while the memory had Gahlwok 3335 and the Water Lurker 1025); a tie, or neither read: the
;planned hit's target among them (TrapHitPick). x, y: its plate; most: its most health ("" not read); TrapPick its slot,
;TrapWhy which it is (the log). False: no plate found - nowhere sure to put it
TrapTarget(&x, &y, &most)
	{
	global
	local ttI, ttE, ttTop, ttTied, ttN, ttOne, ttMem
	most := "", TrapPick := 0, TrapWhy := ""
	if (A_TickCount - EnemyPlatesAt > 8000)
		ReadEnemyHealth()
	if (!IsObject(EnemyPlates) || !EnemyPlates.Length)
		return false
	if (IsObject(EnemyHP) && EnemyHP.Length && EnemyHP.Length = EnemyPlates.Length)
		{
		ttTop := "", ttTied := V1Obj(), ttN := 0, ttOne := ""
		for ttI, ttE in EnemyHP
			if (ttTop = "" || ttE.cur > ttTop)
				ttTop := ttE.cur
		for ttI, ttE in EnemyHP
			if (ttE.cur = ttTop)
				{
				ttTied[ttI] := 1, ttN += 1
				if (ttOne = "")
					ttOne := ttI
				}
		TrapPick := (ttN > 1) ? TrapHitPick(ttTied) : ttOne
		most := EnemyHP[TrapPick].max
		TrapWhy := "enemy " TrapPick " of " EnemyPlates.Length " (" EnemyHP[TrapPick].cur "/" most " health - "
			. (ttN > 1 ? ttN " have the most: the planned hit's target" : "the most") ")"
		}
	else
		{
		ttMem := TrapMemHealth()
		if (ttMem.pick)
			{
			TrapPick := ttMem.pick, most := ttMem.max
			TrapWhy := "enemy " TrapPick " of " EnemyPlates.Length " (" (ttMem.name != "" ? ttMem.name " " : "") ttMem.cur "/" most " health - "
				. (ttMem.tied > 1 ? ttMem.tied " have the most: the leftmost" : "the most") ", from the game's memory (put on its plate " ttMem.how "): the plates' health not read" (HealthStatus != "" ? " - " HealthStatus : "") ")"
			}
		else
			{
			TrapPick := TrapHitPick("")
			TrapWhy := "enemy " TrapPick " of " EnemyPlates.Length " (health not read" (HealthStatus != "" ? ": " HealthStatus : "") "; the game's memory: " ttMem.why " - the planned hit's target)"
			}
		}
	x := EnemyPlates[TrapPick].x, y := EnemyPlates[TrapPick].y
	return true
	}

;The plates' health not read (TrapTarget): the enemies' health from the game's memory (Vision.ahk NavBattle - the helper's
;/battle, READ-ONLY) put on the plates (EnemyPlates, left to right): by where its plate is (the helper's x - its plate's
;middle across the window - within Px(160) of the plate's), else by its name (the plate's OCR'd name against the mob's:
;PlateNameLike), else the one enemy and the one plate left over. {pick: the plate of the one with the most health now -
;a tie: the leftmost of them (equal health: HitPick's own rule) -, cur, max, name, tied (how many have that most), how
;(how it was put on its plate), why (what failed: pick 0)}
TrapMemHealth()
	{
	if (!V1IsFunc("NavBattle"))
		return V1Obj({pick: 0, why: "not asked (no Vision.ahk)"})
	tmhB := NavBattle.Call()
	if (!IsObject(tmhB))
		return V1Obj({pick: 0, why: "not read (" NavBattleWhy ")"})
	tmhFoes := []
	for tmhI, tmhF in tmhB.foes
		if (tmhF.health != "" && tmhF.health > 0)
			tmhFoes.Push(tmhF)
	if (!tmhFoes.Length)
		return V1Obj({pick: 0, why: "no enemy's health read"})
	;(each foe's plate: foe -> plate, plate -> foe, how)
	tmhPlate := V1Obj(), tmhFoe := V1Obj(), tmhHow := V1Obj()
	for tmhI, tmhF in tmhFoes
		if (tmhF.x != "")
			{
			tmhFx := GameLeft + tmhF.x * GameW, tmhBest := 0, tmhD := ""
			for tmhJ, tmhP in EnemyPlates
				if (!tmhFoe.Has(tmhJ) && (tmhD = "" || Abs(tmhP.x - tmhFx) < tmhD))
					tmhBest := tmhJ, tmhD := Abs(tmhP.x - tmhFx)
			if (tmhBest && tmhD <= Px(160))
				tmhPlate[tmhI] := tmhBest, tmhFoe[tmhBest] := tmhI, tmhHow[tmhI] := "by where it is"
			}
	for tmhI, tmhF in tmhFoes
		if (!tmhPlate.Has(tmhI) && tmhF.name != "")
			{
			tmhBest := 0
			for tmhJ, tmhP in EnemyPlates
				if (!tmhFoe.Has(tmhJ) && PlateNameLike(tmhP.name, tmhF.name))
					tmhBest := tmhBest ? -1 : tmhJ
			if (tmhBest > 0)
				tmhPlate[tmhI] := tmhBest, tmhFoe[tmhBest] := tmhI, tmhHow[tmhI] := "by its name"
			}
	;(the one left of each - not a plate whose name was read as another's)
	if (tmhFoes.Length - tmhPlate.Count = 1 && EnemyPlates.Length - tmhFoe.Count = 1)
		for tmhI, tmhF in tmhFoes
			if (!tmhPlate.Has(tmhI))
				for tmhJ, tmhP in EnemyPlates
					if (!tmhFoe.Has(tmhJ) && tmhP.name = "")
						tmhPlate[tmhI] := tmhJ, tmhFoe[tmhJ] := tmhI, tmhHow[tmhI] := "as the one left"
	;The most health now; the leftmost plate of those that have it
	tmhTop := ""
	for tmhI, tmhF in tmhFoes
		if (tmhTop = "" || tmhF.health > tmhTop)
			tmhTop := tmhF.health
	tmhPick := 0, tmhTied := 0, tmhLost := ""
	for tmhI, tmhF in tmhFoes
		if (tmhF.health = tmhTop)
			{
			tmhTied += 1
			if (!tmhPlate.Has(tmhI))
				tmhLost .= (tmhLost = "" ? "" : ", ") (tmhF.name != "" ? tmhF.name : "?")
			else if (!tmhPick || tmhPlate[tmhI] < tmhPlate[tmhPick])
				tmhPick := tmhI
			}
	if (tmhLost != "")
		return V1Obj({pick: 0, why: "the one with the most health (" tmhLost ", " tmhTop ") not found on a plate (" EnemyPlates.Length " plates, " tmhFoes.Length " enemies)"})
	tmhF := tmhFoes[tmhPick]
	return V1Obj({pick: tmhPlate[tmhPick], cur: tmhF.health, max: tmhF.max, name: tmhF.name, tied: tmhTied, how: tmhHow[tmhPick], why: ""})
	}

;A plate's OCR'd name (capitals, maybe cut short - "SELWYN SKYW...") is the mob's name: letters only (digits OCR swaps in
;for letters turned back), the shorter at least 3 letters and the longer one starting with it but for one letter in five
PlateNameLike(ocr, name)
	{
	pnlA := StrUpper(ocr)
	pnlB := StrUpper(name)
	pnlA := RegExReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(pnlA, "0", "O"), "1", "I"), "5", "S"), "8", "B"), "6", "G"), "|", "I"), "[^A-Z]")
	pnlB := RegExReplace(pnlB, "[^A-Z]")
	pnlN := StrLen(pnlA) < StrLen(pnlB) ? StrLen(pnlA) : StrLen(pnlB)
	if (pnlN < 3)
		return false
	pnlOff := 0
	Loop pnlN
		pnlOff += (SubStr(pnlA, (A_Index)<1 ? (A_Index)-1 : (A_Index), 1) != SubStr(pnlB, (A_Index)<1 ? (A_Index)-1 : (A_Index), 1))
	return pnlOff <= pnlN // 5
	}

;The planned hit's target among the enemies among ({slot: 1}; "" all) - TrapTarget's in a tie or with health not read:
;where the hit the round plans (PlanChoose) would be clicked - a hit on one enemy (<school>.<hit>target:1, a learned hit's
;card) the one HitTarget picks (Autofarmer.ahk HitPick: the one it does the most to); an all-enemies hit, the weakest of
;them. Among equal health, the leftmost; health not read, the leftmost plate
TrapHitPick(among)
	{
	global
	local thpP, thpD, thpC
	thpP := PlanChoose(), thpD := ""
	if (RegExMatch(thpP, "^hit[1-4]$") && Stats[hitschool "." thpP "target"] = 1)
		thpD := HitDamage(thpP, false, false)
	else if (InStr(thpP, "learned/") = 1 && V1IsFunc("LearnCardOf"))
		{
		thpC := LearnCardOf.Call(SubStr(thpP, 9))
		if (IsObject(thpC) && thpC.type = "damage" && thpC.target != 0)
			thpD := LearnedHitDamage(thpC, false)
		}
	return HitPick(thpD, among)
	}

;A trap cast this round noted for the kill check (UseTrap: the boss's, or TrapTarget's pick - TrapMine): BossTraps holds
;the traps on one enemy - the boss (BossSlot), else the one TrapFoeX / TrapFoeY (its plate) and TrapFoeMax (its most
;health) say, found again each round (TrapFoeSlot). One on another enemy starts them afresh: those on the last one aren't
;counted any more (still on it - left out is the safe side)
TrapPut(key, bonus, src)
	{
	global
	if (!IsObject(BossTraps))
		BossTraps := V1Obj()
	if (BossChoosen != 1)
		{
		if (TrapFoeX = "" || Abs(TrapAtX - TrapFoeX) > Px(40) || Abs(TrapAtY - TrapFoeY) > Px(40))
			{
			if (BossTraps.Count)
				DebugLog("  a trap on another enemy than the last ones - those aren't counted any more")
			BossTraps := V1Obj(), TrapFoeX := TrapAtX, TrapFoeY := TrapAtY, TrapFoeMax := TrapAtMax
			TrapFoeN := IsObject(EnemyPlates) ? EnemyPlates.Length : 0, TrapSlot := TrapPick
			}
		else if (TrapFoeMax = "" && TrapAtMax != "")
			TrapFoeMax := TrapAtMax
		DebugLog("  " key " on " (TrapWhy != "" ? TrapWhy : "the enemy with the most health") (Stat("solotraps") == 1 ? " - the kill check counts it there" : " - not counted (solotraps:0)"))
		}
	AddBoost(BossTraps, key, bonus, src)
	}

;The slot of the enemy the traps went on in this health read (ReadEnemyHealth: list its health, plates their boxes), no
;boss picked: the plate round where it was (TrapFoeX / TrapFoeY) with its most health (TrapFoeMax - an enemy keeps it;
;taken from this read if it wasn't read then). Its most health on no plate: it's gone, its traps with it. 0: none on, or
;not sure which - two with that most health and a plate fewer than then (they may have moved along)
TrapFoeSlot(list, plates)
	{
	global
	local tfsI, tfsP, tfsE, tfsAt, tfsSame
	if (TrapFoeX = "" || !IsObject(BossTraps) || !BossTraps.Count)
		return 0
	tfsAt := 0
	for tfsI, tfsP in plates
		if (IsObject(tfsP.box) && TrapFoeX >= tfsP.box.x1 && TrapFoeX <= tfsP.box.x2 && TrapFoeY >= tfsP.box.y1 && TrapFoeY <= tfsP.box.y2)
			tfsAt := tfsAt ? -1 : tfsI
	;(its most health not read when they went on: this read's of the plate where it was)
	if (TrapFoeMax = "" && tfsAt > 0)
		TrapFoeMax := list[tfsAt].max
	if (TrapFoeMax = "")
		return 0
	tfsSame := 0
	for tfsI, tfsE in list
		tfsSame += (tfsE.max = TrapFoeMax) ? 1 : 0
	if (!tfsSame)
		{
		DebugLog("  the enemy your traps went on is gone - they went with it")
		BossTraps := V1Obj(), TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0
		return 0
		}
	if (tfsAt <= 0 || list[tfsAt].max != TrapFoeMax)
		return 0
	if (tfsSame > 1 && plates.Length != TrapFoeN)
		return 0
	return tfsAt
	}

;---- The health numbers' 3s, 5s and 8s ----
;
;In the plates' font a 3 has a flat top like a 5, and Windows' OCR reads 395 as 595 (or 39S) - and an 8 as a 3 now and
;then. The numbers are pure red: their glyphs are found at 1:1, left to right (not a plate's school icon - not that
;red), a run wider than it is tall split at its thinnest column (a digit touching the "/"), only the digits' height
;kept (not a speck, nor the taller icon) with a comma joining those either side, and of them only the longest row close
;together (not a bit of the icon a gap away). A 5 and an 8 have ink down the left side under the top (a 3 at most a
;quarter, against over half), and only an 8 over the bottom too (all of it, against at most about half)

;The pure red numbers' glyphs in the screen box, left to right: [{x1, x2, y1, y2, band, low}] (screen) - how much of the
;glyph's left side is inked (0-1) under its top (band) and over its bottom (low). "" if it can't be captured
HealthGlyphs(x, y, w, h)
	{
	px := CaptureRGB(x, y, w, h)
	if (!IsObject(px))
		return ""
	;(v1: inkAt was sparse - a pixel not inked read blank, and so did one past the picture: the band / low look below
	;reads the row under a glyph 1-2 px high on the last row - so a V1Obj, not an Array, which throws outside its
	;length; colInk[A_Index] := 0 grew the array - v2 assigns an array's items only inside its length)
	inkAt := V1Obj(), colInk := []
	Loop w
		colInk.Push(0)
	Loop w * h
		{
		c := px[A_Index]
		r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
		;(the numbers' red - not the orange-red of a school icon: its green well above its blue)
		if (r > 110 && g < 45 && b < 45 && r - g > 80 && g - b < 18)
			inkAt[A_Index] := 1, colInk[Mod(A_Index - 1, w) + 1] += 1
		}
	;Runs of inked columns, and the usual width of one
	runs := [], start := 0, widths := ""
	Loop w + 1
		{
		has := (A_Index <= w && colInk[A_Index])
		if (has && !start)
			start := A_Index
		else if (!has && start)
			runs.Push([start, A_Index - 1]), widths .= (widths = "" ? "" : ",") A_Index - start, start := 0
		}
	if (!runs.Length)
		return []
	widths := Sort(widths, "N D,")
	ws := StrSplit(widths, ",")
	med := ws[(ws.Length + 1) // 2]
	parts := []
	for i, run in runs
		{
		a := run[1], z := run[2], wide := z - a + 1
		;(its height: the rows with ink in its columns)
		top := 0, bottom := 0
		Loop h
			{
			j := A_Index, row := (j - 1) * w
			Loop wide
				if (inkAt[row + a + A_Index - 1])
					{
					top := top ? top : j, bottom := j
					break
					}
			}
		;(two glyphs touching - a digit and the "/": wider than it is tall - a digit alone is about 0.7 of its height:
		;split at the thinnest column of its middle half)
		if (wide > (bottom - top + 1) && wide >= 6)
			{
			cut := a + wide // 4
			Loop (z - wide // 4) - (a + wide // 4) + 1
				{
				k := a + wide // 4 + A_Index - 1
				if (colInk[k] < colInk[cut])
					cut := k
				}
			parts.Push([a, cut]), parts.Push([cut + 1, z])
			}
		else
			parts.Push([a, z])
		}
	;Each glyph's top and bottom, and the usual height
	gl := [], heights := ""
	for i, q in parts
		{
		top := 0, bottom := 0
		Loop h
			{
			j := A_Index, row := (j - 1) * w
			Loop q[2] - q[1] + 1
				{
				if (inkAt[row + q[1] + A_Index - 1])
					{
					if (!top)
						top := j
					bottom := j
					break
					}
				}
			}
		if (top)
			gl.Push(V1Obj({x1: q[1], x2: q[2], y1: top, y2: bottom})), heights .= (heights = "" ? "" : ",") bottom - top + 1
		}
	if (!gl.Length)
		return []
	heights := Sort(heights, "N D,")
	hs := StrSplit(heights, ",")
	tall := hs[(hs.Length + 1) // 2]
	;(the digits' own height - not a speck, nor the taller icon or a mob's name - and a comma (short, low: it joins the
	;digits either side); then the longest row of them close together: the numbers, not a bit of the icon or anything
	;else a gap away)
	kept := [], gaps := "", bottoms := ""
	for i, g in gl
		{
		gh := g.y2 - g.y1 + 1
		if (gh >= 0.7 * tall && gh <= 1.35 * tall)
			gaps .= (gaps = "" ? "" : ",") g.x2 - g.x1 + 1, bottoms .= (bottoms = "" ? "" : ",") g.y2
		}
	if (gaps = "")
		return []
	gaps := Sort(gaps, "N D,")
	bottoms := Sort(bottoms, "N D,")
	gs := StrSplit(gaps, ","), bs := StrSplit(bottoms, ",")
	near := Max(2, 0.6 * gs[(gs.Length + 1) // 2]), base := bs[(bs.Length + 1) // 2]
	for i, g in gl
		{
		gh := g.y2 - g.y1 + 1
		if (gh >= 0.7 * tall && gh <= 1.35 * tall)
			g.digit := 1, kept.Push(g)
		else if (gh < 0.6 * tall && g.y1 >= base - tall * 0.5 && g.y2 <= base + tall * 0.5)
			g.digit := 0, kept.Push(g)
		}
	best := 1, bestN := 0, from := 1, n := 0
	for i, g in kept
		{
		if (i > 1 && g.x1 - kept[i - 1].x2 - 1 > near)
			from := i, n := 0
		n += g.digit
		if (n > bestN)
			best := from, bestN := n, last := i
		}
	;(too-tall red ink beside the row or in it - a red thing under the first digits joins their columns, and they'd be
	;left out, the number read short: none of it trusted)
	for i, g in gl
		if (g.y2 - g.y1 + 1 > 1.35 * tall && g.x2 >= kept[best].x1 - tall && g.x1 <= kept[last].x2 + tall)
			return []
	digits := []
	Loop last - best + 1
		if (kept[best + A_Index - 1].digit)
			digits.Push(kept[best + A_Index - 1])
	out := []
	lowRow := Round(base - tall * 0.4)
	for i, g in digits
		{
		;(a comma touching the digit: its columns, inked only low down, trimmed off its ends - else the left side measured
		;is the comma's)
		Loop 2
			{
			trim := 0, side := A_Index
			Loop g.x2 - g.x1 - 5
				{
				edge := side = 1 ? g.x1 + A_Index - 1 : g.x2 - A_Index + 1, high := 0
				Loop lowRow - g.y1
					{
					if (inkAt[(g.y1 + A_Index - 2) * w + edge])
						{
						high := 1
						break
						}
					}
				if (high)
					break
				trim := A_Index
				}
			if (trim >= 2 && side = 1)
				g.x1 += trim
			else if (trim >= 2)
				g.x2 -= trim
			}
		Loop h - g.y1 + 1
			{
			j := g.y1 + A_Index - 1, row := (j - 1) * w
			Loop g.x2 - g.x1 + 1
				{
				if (inkAt[row + g.x1 + A_Index - 1])
					{
					g.y2 := j
					break
					}
				}
			}
		gh := g.y2 - g.y1 + 1, gw := g.x2 - g.x1 + 1
		;(the left 30 %: from a quarter of the way down to under half way - band - and from just over half way to
		;three quarters - low)
		bw := Max(1, Round(gw * 0.3)), band := low := 0
		for k, rows in [[0.25, 0.45], [0.58, 0.75]]
			{
			y0 := g.y1 + Round(gh * rows[1]), y1 := g.y1 + Round(gh * rows[2]), inked := 0
			Loop y1 - y0 + 1
				{
				row := (y0 + A_Index - 2) * w
				Loop bw
					inked += inkAt[row + g.x1 + A_Index - 1] ? 1 : 0
				}
			if (k = 1)
				band := inked / (bw * (y1 - y0 + 1))
			else
				low := inked / (bw * (y1 - y0 + 1))
			}
		out.Push(V1Obj({x1: x + g.x1 - 1, x2: x + g.x2 - 1, y1: y + g.y1 - 1, y2: y + g.y2 - 1, band: band, low: low}))
		}
	return out
	}

;The screen box round glyphs (HealthGlyphs), pad pixels out
GlyphsBox(gl, pad, &bx, &by, &bw, &bh)
	{
	x1 := gl[1].x1, x2 := gl[gl.Length].x2, y1 := gl[1].y1, y2 := gl[1].y2
	for i, g in gl
		y1 := Min(y1, g.y1), y2 := Max(y2, g.y2)
	bx := x1 - pad, by := y1 - pad, bw := x2 - x1 + 1 + pad * 2, bh := y2 - y1 + 1 + pad * 2
	}

;An OCR'd health line (read with only its red) put right by its glyphs (HealthGlyphs): S read for 5, O for 0 and B for 8,
;then each 3, 5 or 8 by its shape. "" when the glyphs were found and don't line up with the characters (one each), or
;there's a 3, 5 or 8 to tell and they weren't - such a read isn't to be trusted
HealthDigits(text, gl)
	{
	;(only a thousands mark between digits and spaces round the "/" taken out - anything else left in for ParseHealth to
	;turn down, and to be counted against the glyphs)
	;(and an "r" for a comma - 1440p, 2026-10-23: 2r848/3r153)
	t := RegExReplace(text, "(?<=[\dSsOoB])\s*[,.']\s*(?=[\dSsOoB])|(?<=[\dSsOoB])r(?=[\dSsOoB]{3}(?![\dSsOoB]))|\s+(?=/)|(?<=/)\s+")
	t := RegExReplace(RegExReplace(RegExReplace(t, "[Ss]", "5"), "[Oo]", "0"), "B", "8")
	;(every read counted against the glyphs when they were found - a digit cut off or added shows)
	if (IsObject(gl) && gl.Length != StrLen(t))
		return ""
	if (!RegExMatch(t, "[358]"))
		return t
	if (!IsObject(gl))
		return ""
	out := ""
	Loop Parse, t
		out .= InStr("358", A_LoopField) ? (gl[A_Index].band < 0.4 ? "3" : gl[A_Index].low >= 0.75 ? "8" : "5") : A_LoopField
	return out
	}

;Minimum non-crit damage of a hit to one enemy, counting only boosts we know are applied.
;Bubbles aren't counted: anyone's global (enemies' too) replaces ours and we can't see it.
HitDamage(hitName, useEnchant, toBoss)
	{
	global hitschool, enchant
	;(head by head - HitHeads: Hydra's fire, ice and storm each with the blades and traps that fit it; one head of your
	;school - its PlayerStats.txt number - when they aren't known, as before)
	hdHh := HitHeads(hitName)
	if (hdHh.total <= 0)
		return 0
	;X-pip spells (pip cost 0) are stored as damage per pip: they spend all your pips (not the wand's card:
	;it costs nothing)
	hdPer := (hdHh.xpip && hitName != "wand") ? (PipsNow > 0 ? PipsNow : 1) : 1
	hdAdd := 0
	if (EnchantedHits[hitName])
		hdAdd := Stat("enchant" . EnchantedHits[hitName])
	;(never on an item card - a pet's, the wand's: it can't be enchanted)
	else if (useEnchant && V1Ge(enchant, 1) && !hdHh.item)
		hdAdd := Stat("enchant" . enchant)
	return HeadsDamage(hdHh, hdPer, hdAdd, toBoss)
	}

;A hit's least damage from its base (its card's, an enchant added): your damage %, the blades and aura on, the traps on
;the enemy they went on (solotraps:1 - toBoss: this is that enemy - the boss, or the one with the most health they went
;on: TrapSlot), the enemies' resist less your pierce - HitDamage's, and a learned hit's in no slot (HitTarget).
;sch: the head's school - only the blades, aura and traps that fit it count; "*" every one, as before
HitDamageFrom(base, toBoss := false, sch := "*")
	{
	if (base <= 0)
		return 0
	dmg := base * DamageMultiplier(Stat("damage")) * (sch = "*" ? BoostMult(AppliedBlades) : BoostMultFor(AppliedBlades, sch))
	if (AuraRounds > 0 && (sch = "*" || BoostFits("aura", sch)))
		dmg *= 1 + Stat("aura") / 100
	;Another player's hit on the enemy uses up our traps without us seeing it: counted only with solotraps:1 (you fight
	;alone), and only on the enemy they went on
	if (toBoss && Stat("solotraps") == 1)
		dmg *= (sch = "*" ? BoostMult(BossTraps) : BoostMultFor(BossTraps, sch))
	resist := Stat("enemyresist") - Stat("pierce")
	if (resist > 0)
		dmg *= 1 - resist / 100
	return Floor(dmg)
	}

;A learned hit's least damage in no slot (for its target: HitTarget) - every head of it (CardLearn.ahk LearnHitBase: a
;Hydra's three), the enchant put on it added (enchanted), then as HitDamage; "" its damage not known
LearnedHitDamage(c, enchanted)
	{
	global enchant, BossChoosen
	;(head by head: LearnHitHeads - the game's heads, else one of its school)
	lhdHh := LearnHitHeads(c)
	if (lhdHh.total <= 0)
		return ""
	;(an X-pip hit: its number is a pip's - all your pips go)
	return HeadsDamage(lhdHh, lhdHh.xpip ? Max(PipsNow, 1) : 1, (enchanted && V1Ge(enchant, 1)) ? Stat("enchant" . enchant) : 0, BossChoosen == 1)
	}

IsLethal(hitName, useEnchant)
	{
	if (!IsObject(EnemyHP))
		return false
	;Boss fight: the boss's plate must be among the ones read, or a missed plate could hide it
	if (BossChoosen == 1) && (BossSlot < 1)
		return false
	;A hit on one enemy (<school>.<hit>target:1, e.g. Scarab) only ends the battle when one enemy is left
	if (Stat(hitschool "." hitName "target") = 1 && EnemyHP.Length > 1)
		return false
	margin := 1 + Stat("killmargin") / 100
	;(the traps counted on the enemy they went on only - TrapSlot: the boss's slot, or the one with the most health they
	;went on; 0 none / its plate not found)
	for i, e in EnemyHP
		{
		if (HitDamage(hitName, useEnchant, i == TrapSlot) < e.cur * margin)
			return false
		}
	return true
	}

;Enemy health as text, or why it couldn't be read
HealthText()
	{
	if (!IsObject(EnemyHP))
		return HealthStatus
	text := ""
	for i, e in EnemyHP
		{
		text .= (text = "" ? "" : ", ") . e.cur . "/" . e.max . (i == BossSlot ? " (boss)" : (i == TrapSlot) ? " (your traps)" : "")
		}
	return text
	}

;Statistic mode (Alt+S): tooltip with the health read and what each hit in hand would do
ShowKillInfo()
	{
	global KillHit, KillEnchant
	if (statsmode != 1)
		return
	info := "Pips: " . PipsNow . "`nEnemy health: " . HealthText()
	if (IsObject(EnemyHP))
		{
		inHand := [hit1, hit2, hit3, hit4]
		Loop 4
			{
			if (inHand[A_Index] == 1)
				{
				info .= "`nhit" . A_Index . ": " . HitDamage("hit" . A_Index, 0, 0)
				if (TrapSlot)
					info .= " (" (TrapSlot == BossSlot ? "boss" : "trapped enemy") " " . HitDamage("hit" . A_Index, 0, 1) . ")"
				}
			}
		if (KillHit != "")
			info .= "`nCasting " . KillHit . (KillEnchant ? " with enchant" : "") . ", it kills everything"
		else if (BossChoosen == 1) && (BossSlot < 1)
			info .= "`nBoss nameplate not found, kill check off"
		else
			info .= "`nNo hit kills everything yet, boosting"
		}
	;The box must never sit over the game: ImageSearch would see it instead of the cards, and it would
	;catch the boss/hammer clicks. Put it beside the window, or don't show it (Win+2 still has the info)
	vLeft := SysGet(76)
	vWidth := SysGet(78)
	if (GameRight + 420 <= vLeft + vWidth)
		ToolTip(info, GameRight + 10, GameTop, 20)
	else if (GameLeft - 420 >= vLeft)
		ToolTip(info, GameLeft - 410, GameTop, 20)
	else
		{
		ToolTip(, , , 20)
		return
		}
	;ToolTip moves itself back on screen when it doesn't fit, so check where it really ended up
	tip := WinExist("ahk_class tooltips_class32 ahk_pid " . DllCall("GetCurrentProcessId"))
	if (tip)
		{
		try
			WinGetPos(&tx, &ty, &tw, &th, "ahk_id " tip)
		catch
			return  ; (v1: the tooltip gone already - its place read blank: nothing done)
		if (tx < GameRight) && (tx + tw > GameLeft) && (ty < GameBottom) && (ty + th > GameTop)
			ToolTip(, , , 20)
		}
	}

;Can you pay for this hit right now? (the game doesn't grey out cards you can't afford)
;Unknown pips (nameplate not found) counts as yes; the cast check in Autofarmer catches it
Affordable(hitName)
	{
	global hitschool
	if (PipsNow < 0)
		return true
	;(the wand's card costs no pips at all - not an X-pip spell)
	if (hitName = "wand")
		return true
	cost := Stat(hitschool . "." . hitName . "pips")
	return (cost = 0) ? (PipsNow >= 1) : (PipsNow >= cost)
	}

;Your pips this round (PipsNow): the game's own count from its memory when the hand's read there this round (Vision.ahk
;VisionCards - /cards' me line, read-only), else off the orbs under your name (PipValue). The game counts pips for a spell
;of your own school - the cards the bot plays - as:
;  generic pip                                  1
;  power pip                                    2
;  school pip of your own school                2   (a power pip in your school's colours: it pays as one)
;  school pip of another school                 1   (it pays as a power pip only for that school's spells)
;  shadow pip                                   0   (it pays only a spell's shadow pips)
;so PipsNow = generic + 2 x (power + your school's pips) + the other schools' pips. Your school: the game's, else the
;badge by your name (school). The orbs are read anyway, for the slots filled (PipOrbs, for saving pips: the game's pips
;counted one an orb when it read them) and for the log - pipsnote says "(from the game; the pip row read M)" when the
;two differ. -1 when neither can be read
PipsRead()
	{
	global school
	global PipsNote, PipOrbs ; (v1 globals it sets)
	prRow := PipValue(), PipsNote := ""
	prHand := VisionCards(1500)
	if (!IsObject(prHand) || !IsObject(prHand.me) || !prHand.me.ok)
		return prRow
	prOwn := prHand.me.school != "" ? prHand.me.school : Format("{:L}", school)
	prNum := prHand.me.generic + 2 * prHand.me.power, prOrbs := prHand.me.generic + prHand.me.power
	for prI, prSch in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
		prNum += prHand.me[prSch] * (prSch = prOwn ? 2 : 1), prOrbs += prHand.me[prSch]
	PipOrbs := Min(7, prOrbs)
	if (prNum != prRow)
		PipsNote := " (from the game; the pip row read " prRow ")"
	return prNum
	}

;Your pips, from the orbs under your name on your nameplate: white = 1, gold power pip = 2,
;gold with your school's symbol (school pip) = 2. Orbs fill from the left, 20 px apart at UI scale
;1 (11 px orbs). Returns -1 if your nameplate (resources\player.png) wasn't found this round
PipValue()
	{
	global playerX, playerY
	global PipOrbs ; (v1 globals it sets)
	if (playerX = "" || playerY = "" || (playerX = 0 && playerY = 0))
		return -1
	;(and how many of the 7 orb slots are filled, for saving pips: PipOrbs)
	PipOrbs := 0
	orb := Px(11), w := Round(20 * UiScale * 6) + orb, h := orb
	;(v2 port: v1's local px renamed pvPx - in v2 a local px would hide the Px() function it calls)
	pvPx := CaptureRGB(playerX - Px(6), playerY + Px(50), w, h)
	if (!IsObject(pvPx))
		return -1
	;The colour counts below are areas, so they grow with the square of the UI scale
	area := UiScale * UiScale
	total := 0
	Loop 7
		{
		slot := A_Index - 1, purple := 0, blue := 0, yellow := 0, white := 0, vivid := 0, dull := 0, grey := 0
		Loop h
			{
			row := (A_Index - 1) * w + Round(20 * UiScale * slot)
			Loop orb
				{
				c := pvPx[row + A_Index], r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
				if (b > 150 && r > 110 && g < 120)
					purple++
				;(a Myth school pip: gold with a big blue triangle, so not much gold shows)
				else if (b > 140 && r < 110 && g < 150)
					blue++
				else if (r > 200 && g > 170 && b < 120)
					yellow++
				else if (r > 215 && g > 205 && b > 180)
					white++
				;(each school's own pip - a gold rim round its school's sign, 2026-10-24 at 1440p: Fire's orange flame,
				;Ice's snowflake, Life's leaf, Balance's red-orange, Myth's triangle, the power pip's gold: strongly
				;coloured, 86+ px a slot where an empty one has 42 at most; Death's skull is dark grey in a grey glow -
				;dark scenery under an empty slot has the dark but not the glow)
				mx := Max(r, g, b), mn := Min(r, g, b)
				if (mx - mn > 90 && mx > 120)
					vivid++
				else if (mx < 110 && mx - mn < 25)
					dull++
				else if (mn > 140 && mx - mn < 30 && mx < 225)
					grey++
				}
			}
		if (purple + blue + yellow >= 30 * area || vivid >= 60 * area || (dull >= 70 * area && grey >= 8 * area))
			total += 2
		else if (white >= 50 * area)
			total += 1
		else
			break
		PipOrbs := A_Index
		}
	return total
	}

;Screen rectangle -> array of 0xRRGGBB colours, row by row (1-based)
CaptureRGB(x, y, w, h)
	{
	hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
	bi := Buffer(40, 0)
	NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
	NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (!hbm)
		{
		DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
		return ""
		}
	obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
	DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
	DllCall("GdiFlush")
	out := []
	Loop w * h
		out.Push(NumGet(bits + (A_Index - 1) * 4, "UInt") & 0xFFFFFF)
	DllCall("SelectObject", "Ptr", mdc, "Ptr", obm), DllCall("DeleteObject", "Ptr", hbm)
	DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
	return out
	}

;Cheapest hit in hand that kills every enemy, trying without the enchant first: the wand's card first (it
;costs nothing; never enchanted), then hit1-4
;The damage the kill check counts on from each hit in hand (HitDamage: the least it does - no crit - with the blades
;and traps known to be on, your damage %, the enemies' resist), for debug.log: "Sandstorm (hit1) 255 all enemies, 355
;with the enchant; wand 80 one enemy" ("" none in hand)
KillHitsText()
	{
	global enchant, wand, hit1, hit2, hit3, hit4, hitschool
	inHand := [hit1, hit2, hit3, hit4], out := ""
	for each, kh in ["wand", "hit1", "hit2", "hit3", "hit4"]
		{
		if (kh = "wand" ? !(wand == 1 && Stat("usewand")) : inHand[each - 1] != 1)
			continue
		khDmg := HitDamage(kh, false, false)
		if (khDmg <= 0)
			continue
		khName := V1IsFunc("DashShortName") && kh != "wand" ? DashShortName.Call(kh, hitschool) : ""
		;(a wand's hit is always one enemy's)
		khOne := kh = "wand" || Stat(hitschool "." kh "target") = 1
		khBoost := (kh != "wand" && V1Ge(enchant, 1)) ? HitDamage(kh, true, false) : 0
		;(its heads, when they're known - the game's: [fire 230 + ice 230 + storm 230 (the game)])
		khHh := HitHeads(kh)
		out .= (out = "" ? "" : "; ") (khName != "" && khName != kh ? khName " (" kh ")" : kh) " " khDmg (khOne ? " one enemy" : " all enemies")
			. (khBoost > khDmg ? ", " khBoost " with the enchant" : "") (khHh.sure ? " [" HeadsText(khHh) "]" : "")
		}
	return out
	}

FindLethalHit(&hitName, &withEnchant)
	{
	global enchant, wand
	inHand := [hit1, hit2, hit3, hit4]
	hitName := "", withEnchant := 0
	if (wand == 1 && Stat("usewand") && IsLethal("wand", 0))
		{
		hitName := "wand"
		return true
		}
	Loop (V1Ge(enchant, 1) ? 2 : 1)  ; (v1: enchant blank before the first look at the hand: once)
		{
		useEnchant := A_Index - 1
		Loop 4
			{
			;The strongest hit is saved for boss fights, same as the normal battle code
			if (inHand[A_Index] == 1) && (A_Index < 4 || BossChoosen == 1) && Affordable("hit" . A_Index) && IsLethal("hit" . A_Index, useEnchant)
				{
				hitName := "hit" . A_Index
				withEnchant := useEnchant
				return true
				}
			}
		}
	return false
	}

;---- Saving pips for a hit that ends the battle ----
;
;Called by the kill check when nothing in hand ends the battle this round. A hit in hand that would end it
;- an AoE that kills every enemy, a single-target hit that kills the last one - but costs more pips than
;you have, is worth saving for: pips come at 1 or more a round, so it's castable in (cost - pips) rounds
;at most. Within pipsave rounds (PlayerStats.txt, default 3; 0 = never save), PipSaveFor names it and
;UseHit casts no other hit meanwhile (the wand's free hit, boosts, healing and Pass still go). Not while
;your health is under pipsavehealth % (default 50), and given up for the battle if the pips don't come.
;The round it's affordable the kill check casts it.
PlanPips()
	{
	global hit1, hit2, hit3, hit4, BossChoosen, enchant, roundnumber, OwnHpPct, OwnHpRound, player
	global PipSaveFor, PipSaveBare, PipSaveRounds, PipSaveTarget, PipSaveStall, PipSaveLastPips, PipSaveGaveUp ; (v1 globals it sets)
	PipSaveFor := "", PipSaveBare := 0
	maxWait := Stat("pipsave")
	if (maxWait <= 0 || PipSaveGaveUp || PipsNow < 0 || !IsObject(EnemyHP) || !EnemyHP.Length)
		return
	inHand := [hit1, hit2, hit3, hit4]
	;(the most pips you can still reach: 7 orb slots, each new one worth at least 1)
	reach := PipsNow + Max(0, 7 - PipOrbs)
	best := "", bestWait := 99, bestCost := 0
	Loop 4
		{
		name := "hit" A_Index
		;(hit4 is only cast on bosses, as in the battle code)
		if (inHand[A_Index] != 1 || (A_Index = 4 && BossChoosen != 1))
			continue
		cost := Stat(hitschool "." name "pips")
		;(an X-pip spell, one you can pay for now, or one too far off: nothing to save for)
		if (cost <= 0 || cost <= PipsNow || cost - PipsNow > maxWait || cost > reach)
			continue
		;(lethal as it'll be when it's castable: the aura may have run out by then)
		wait := cost - PipsNow
		if (!PipLethalLater(name, wait))
			continue
		if (wait < bestWait)
			best := name, bestWait := wait, bestCost := cost
		}
	if (best = "")
		{
		PipSaveRounds := 0, PipSaveTarget := "", PipSaveStall := 0
		return
		}
	;Your health, off your name plate, read this round: no saving when it's low - or can't be read
	if (OwnHpRound != roundnumber && player == 1 && V1IsFunc("OwnHealthLow"))
		OwnHealthLow.Call()
	if (OwnHpRound != roundnumber)
		{
		DebugLog("  not saving pips for " best ": your health couldn't be read")
		return
		}
	if (OwnHpPct < Stat("pipsavehealth"))
		{
		DebugLog("  not saving pips for " best ": your health is " OwnHpPct "% (under pipsavehealth " Stat("pipsavehealth") "%)")
		return
		}
	;Rounds saved for this hit: a new game round shows as more pips (the bot can look at one round twice);
	;the same pips three looks running means they've stopped coming
	if (best != PipSaveTarget)
		PipSaveTarget := best, PipSaveRounds := 0, PipSaveStall := 0, PipSaveLastPips := -1
	if (PipsNow != PipSaveLastPips)
		PipSaveRounds++, PipSaveStall := 0, PipSaveLastPips := PipsNow
	else
		PipSaveStall++
	if (PipSaveRounds > maxWait + 1 || PipSaveStall >= 3)
		{
		PipSaveGaveUp := 1
		DebugLog("  saved pips for " best " " PipSaveRounds " round(s) and still can't cast it - spending them again this battle")
		return
		}
	PipSaveFor := best
	;(the wand's free hit meanwhile only if the saved hit kills without the blades, traps, aura and enchant
	;it would use up - and never with the enchant)
	PipSaveBare := PipLethalBare(best)
	DebugLog("  saving pips for " best " (" bestCost " pips, you have " PipsNow "): it ends the battle - no other hit spends pips for up to " bestWait " round" (bestWait = 1 ? "" : "s") (PipSaveBare ? "" : "; no wand hit meanwhile (it would use up the boosts the kill needs)"))
	}

;Whether hit name is lethal once castable in wait rounds: the aura counted only if it lasts that long;
;the enchant in hand may be used on it
PipLethalLater(name, wait)
	{
	global enchant
	global AuraRounds ; (v1 globals it sets)
	keep := AuraRounds
	AuraRounds := Max(0, AuraRounds - wait)
	lethal := IsLethal(name, 0) || (V1Ge(enchant, 1) && IsLethal(name, 1))
	AuraRounds := keep
	return lethal
	}

;Whether hit name is lethal with none of the boosts a wand hit would use up (blades, traps, aura, enchant)
PipLethalBare(name)
	{
	global AppliedBlades, BossTraps, AuraRounds ; (v1 globals it sets)
	keepBlades := AppliedBlades, keepTraps := BossTraps, keepAura := AuraRounds
	AppliedBlades := V1Obj(), BossTraps := V1Obj(), AuraRounds := 0
	lethal := IsLethal(name, 0)
	AppliedBlades := keepBlades, BossTraps := keepTraps, AuraRounds := keepAura
	return lethal
	}


;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
KillCalcBlank()
	{
	global towerX := "", towerY := "", bubbleX := "", bubbleY := "", convertX := "", convertY := "", enchant := "", used := "", TrapOn := ""
	global potent := "", sharpen := "", BoostHand := "", BoostSrcUsed := "", BoostSaid := "", hitschool := "", Manual := "", HammerSchool := ""
	global HammerPlan := "", BossChoosen := "", wand := "", BoostExtra := "", AppliedBlades := "", BossTraps := "", SbFound := "", GbFound := ""
	global EnemyHP := "", TrapPick := "", TrapSlot := "", EnemyPlates := "", KillHit := "", BoostMemOk := "", PipSaveFor := "", LastHandAnswer := ""
	global BoostOneOfOff := "", PlanHeads := "", PlanHit := "", BoostMisfitDone := "", LearnAll := "", Stats := "", GameLeft := "", GameTop := ""
	global HalfPitch := "", bossX := "", bossY := "", feint := "", trap3 := "", trap4 := "", EnemyPlatesAt := "", HealthStatus := "", TrapFoeX := ""
	global TrapAtX := "", TrapAtY := "", TrapFoeY := "", TrapAtMax := "", TrapWhy := "", TrapFoeMax := ""
	global MemBox := ""
	}
