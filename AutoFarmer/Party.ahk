; Party.ahk - a party of up to 4 wizards, one per PC on the same home network (TODO goal 1, phase 1). AHK v1.1,
; functions and labels only; #Included by Autofarmer.ahk.
;
; Settings (PARTY): partyrole - Off, Leader (quests as now; waits while a follower is far, in another zone or not ready -
; partywaitdist, partywaitmax) or Follower (goes where the leader goes - partynear - instead of following its own quest
; arrow; into the leader's battles; through the door the leader took). The party's port: partyport. This wizard's party
; name and (a follower) the leader PC's address: the tray menu's Party... window (party.ini - not secret: a name, an
; address), with the role and the battle part too (the same settings as Settings > PARTY's).
;
; The vision helper does the talking (vision\party.py): every half second PartyTick tells it this bot's state (/party)
; and gets the party back - the leader's place, door and battle spot; the followers'; each one's battle part
; (partybattle), wizard's name, school and hits. State only: nothing one bot sends can make another press anything -
; a blader's or healer's boosts go to the party's hitter's plate, found on its own screen by the name the game's log
; gives for its own side. Phase 2 (teleport to friend across zones) isn't in yet: a follower whose leader went where it
; can't follow waits, and says so - "can't follow" (v1.0.0: the helper tells a door the leader walked through from a
; teleport - End, Home, a sigil, a potion run: it stood still before its zone changed; not checked in the game yet, so
; only acted on with Settings' partytpdoors on, else logged -, keeps its last 3 doors - a follower two zones behind
; walks door after door - and says when a teleport to the leader would be the way: its port_advice. A door that doesn't
; take the follower is given up after 3 tries - a try a battle cut short not counted, tried again 6 minutes on; one that
; can't follow tells the leader - tp -, which stops waiting for it. Where the Friends list's Teleport plugs in, once its
; windows are known: PartyCantFollow).
;
; Battle roles (phase 3 - Settings: partybattle): with more than one wizard on your side, a Blader puts its blades on the
; hitter (the wizard set to Hitter - the leader's first -, else the leader), its traps on the enemy the hitter goes for,
; casts them again after each of the hitter's hits, Tower Shield on it, and hits only for a kill or with nothing else to
; do; a Healer heals the one of you lowest under healat %, shields them, else boosts as a blader. Anything not sure (no
; party state, the hitter not on your side, its plate not read): this wizard hits, as ever.
; The party's hit round (v1.0.0, TODO goal 3 - Settings: partyhitround, off; not tried in the game): the hitter says the
; log round its planned hit goes out in (the earliest it can: KillCalc.ahk BoostPick) and each wizard its seat (its
; subcircle - our side's cast order); a blader's or healer's blades and traps wait for it - that round when its seat
; casts before the hitter's, else the round before (PartyHitHold). An older bot sends neither: as ever.
; The leader's orders (TODO goal 3 - Settings: partyorders, off; not tried in the game - advice only): each follower's
; helper keeps the hand its bot read (VisionCards, tagged with its duel and log round) and sends it once the leader's
; asks; the leader's planner (planner on) plans the team with those hands (vision\party.py fill_mates) and each
; follower's card comes back to it - PartyOrderRound waits up to 3 s for it in the round and logs it, nothing cast
; (named from its own hand and log - no text from the leader's PC is logged). The leader asks only while it can plan
; (&plans - planner on, its bot on, navmem, one window), and a round it doesn't plan is told at its end
; (PartyOrderSkip). The round compared is each helper's battle recorder's (its own duel only). An older bot, or one
; with it off: nothing sent, nothing waited for.

;The party as last heard: the role, the helper's state (off/serving/following/unreachable/error) and why; this wizard
;({zone, x, y, z, yaw} - the zone blank while it isn't read: a loading screen); the leader (a follower's view: {name, zone,
;x, y, z, yaw, battle, hp, ready, walk, age, dist, dzone, dx, dy, dz, ddx, ddy, dto, bx, by, bz, hold, ..., loading, dwalk,
;zage, dage, port, portwhy} - the door: its latest out of this wizard's zone; dwalk 1 walked through, 0 a teleport, blank
;not known (an older helper); zage its time in its zone, dage the door's age (ms); port 1: the helper says teleport to it,
;portwhy why or why not); the followers ([{name, zone, x, y, z, battle, hp, ready, age, dist, walk, loading, hold, ..., tp,
;tpwhy}]); when it was last asked
global PartyRole, PartyState, PartyWhy, PartyMe, PartyLeader, PartyMembers, PartyAskAt
;The leader's hold: why it's holding now, since when each follower's been held for ({name: tick}), the ones not waited
;for any more until they've been near ({name: 1})
global PartyHolding, PartyHeldFrom, PartySkip
;The follower: what it walks to now ({x, y, z, kind}), when its own place last moved, and the stuck tries
global PartyTgt, PartyStillAt, PartyStillX, PartyStillY, PartyTries, PartyPushUntil, PartyNear
;The follower that can't follow (TODO goal 1): what it tells the leader (PartyTp: "" following, "wait" it can't follow,
;"stuck" five stuck tries on the way - "porting" / "refused": the Friends list's teleport, not in yet) and why; since when
;it's waited, what was last logged (once a wait), the zone the helper's teleport advice was logged for, the Discord alert
;sent; the door tried (its key), the tries at it and the one given up; the zones last seen (this wizard's - the stuck and
;door tries start again when it changes -, the leader's - the stuck tries); when the stuck tries ran out (30 s, then
;they start again); when the door was given up (tried again 6 minutes on), the battle count at its last push (a battle
;since cut that try short: not counted), the door the helper called a teleport last logged (partytpdoors off)
global PartyTp, PartyTpWhy, PartyCantAt, PartyCantSaid, PartyPortSaid, PartyCantAlerted, PartyDoorKey, PartyDoorTries
global PartyDoorGave, PartyMyZone, PartyLdZone, PartyStuckAt, PartyDoorGaveAt, PartyDoorBattles, PartyDwalkSaid
;The party's hit round (v1.0.0, TODO goal 3 - not tried in the game): the log round this wizard's planned hit is
;likely to go out in, the earliest it can (KillCalc.ahk BoostPick sets it - the hitter's), and the battle it's for
;(BlDuel) - PartyTick sends it, with this wizard's seat, so a blader's or healer's blades and traps wait for it
;(Settings: partyhitround, off - PartyHitHold)
global PartyHitAt, PartyHitAtDuel
;The leader's orders (TODO goal 3 - Settings: partyorders, advice only - PartyOrderRound): the round last asked about
;(duel|log round|bot round); the rounds with no order from the leader ({duel, n: in a row this battle, run: in a row
;across battles} - two / six stop the wait); the notes said once a battle (a Map: duel|why). Each starts "" (PartyBlank):
;IsObject first
global PartyOrderAsked, PartyOrderMiss, PartyOrderSaid
;The lost follower's teleport by the game's Group button (Settings: partytp - PartyGroupPort): when it last tried, why it
;didn't (said once till it changes), till when it's left after a try that didn't work and for which of the leader's zones;
;riding the leader's mount (Settings: partyride - PartyRideCheck): when X was last pressed at its prompt, when the prompt
;was last read, the other prompts by the leader logged ({key: 1} - once each)
global PartyPortAt, PartyPortNot, PartyPortOffUntil, PartyPortOffZone, PartyRideAt, PartyRideLook, PartyRideSaid

;The role set in Settings: "off", "leader" or "follower"
PartyRoleSet()
	{
	r := Stat("partyrole")
	return r = 2 ? "leader" : r = 3 ? "follower" : "off"
	}

;A follower, on (the walking dispatch: PartyFollowStep instead of the quest's WalkStep)
PartyFollowing()
	{
	return PartyRoleSet() = "follower"
	}

;This PC's party name and (a follower) the leader's address: party.ini
PartyIni(key)
	{
	v := IniRead(A_ScriptDir "\party.ini", "party", key, A_Space)
	return Trim(v)
	}

;Every half second (a timer - on through battle rounds too): this bot's state to the helper, the party back
PartyTick()
	{
	static schoolAskAt := 0, schoolChar := ""
	global PartyMySchool, PartyAskAt, PartyState, PartyWhy, PartyLeader, PartyMembers, PartyRole, PartyMe ; (v1 globals it sets)
	role := PartyRoleSet()
	if (role = "off" && PartyRole = "off")
		return
	if (!VisionOn || !V1IsFunc("VisionGet"))
		return
	;(your health only as read this battle round - out of battle it's set to 0, before the first read it's blank)
	hp := (inbattle = 1 && OwnHpAt != "" && OwnHpRound = roundnumber && A_TickCount - OwnHpAt < 30000) ? OwnHpPct : ""
	;(your school for the party: off your plate - else the one this character fought as before, looked for once in 20 s)
	if (A_TickCount - schoolAskAt > 20000)
		{
		schoolAskAt := A_TickCount, psChar := StatsCharID()
		;(another character logged in: its school)
		if (PartyMySchool = "" || (psChar != "" && psChar != schoolChar))
			schoolChar := psChar, PartyMySchool := StatsSchoolOf(psChar)
		}
	;(not while it's quick selling the backpack - QuickSell.ahk: a leader waits for a follower that is)
	;(battles only - Autofarmer.ahk, Settings: battlesonly - is ready with walking off: it rides along and plays the battles; the
	;leader mustn't hold for it)
	ready := BotOn && (Walking || BattlesOnly()) && !PlayerActive && GameActive() && !PotionResting && !QsBusy ? 1 : 0
	;(plan: the hitter's planned hit's schools - a support boosts for them; lasthit: its last hit's - a support's blades that
	;fit none of those stay on it - KillCalc.ahk BoostPick, ConsumeBoosts)
	q := "/party?role=" role "&name=" NavUri(PartyIni("name")) "&leader=" NavUri(PartyIni("leader"))
		. "&port=" Stat("partyport") "&battle=" (inbattle = 1 ? 1 : 0) "&hp=" hp "&ready=" ready "&walk=" (Walking ? 1 : 0)
		. "&bot=" (BotOn ? 1 : 0) "&loading=" (WkLoading ? 1 : 0) "&hold=" NavUri(SubStr(PartyHolding, 1, 80))
		. "&brole=" PartyBattleSet() "&wiz=" NavUri(OwnName()) "&school=" PartyMySchool "&hits=" (PartyHits ? PartyHits : 0) "&hitr=" (PartyHitR ? PartyHitR : 0)
		. "&plan=" NavUri(PartySupport() ? "" : PlanList) "&lasthit=" NavUri(PartyLastSch)
	;(a follower that can't follow says so, and why - the leader stops waiting for it: PartyHoldWhy. Only the characters the
	;helper takes - vision\party.py HOLD_RE -, 80 at most)
	q .= "&tp=" (role = "follower" ? PartyTp : "") "&tpwhy=" (role = "follower" ? NavUri(SubStr(RegExReplace(PartyTpWhy, "[^\w .,'()/-]", " "), 1, 80)) : "")
	;(the party's hit round - v1.0.0: the log round this wizard's planned hit goes out in, the earliest it can, for this
	;battle only - KillCalc.ahk BoostPick, a hitter's; a blader's or healer's never -, and its seat: its subcircle in the
	;game's log, our side's cast order (PartySeat). Its supports time their blades and traps to it - PartyHitHold. Blank:
	;not known - as an older bot's)
	q .= "&hitat=" ((inbattle = 1 && PartyHitAtDuel != "" && PartyHitAtDuel = BlDuel && !PartySupport()) ? PartyHitAt : "")
		. "&seat=" (inbattle = 1 ? PartySeat() : "")
	;(partyorders: this PC in the team's plan - a follower sends its hand when the leader asks, the leader's server takes
	;it, and the leader asks - plans - only while it can plan: planner on, its bot on, navmem, one window...; off: not
	;sent - the party as before)
	if (PartyOrdersOn() && (role = "follower" || role = "leader"))
		q .= "&orders=1" ((role = "leader" && PartyOrdersCanPlan()) ? "&plans=1" : "")
	ans := VisionGet(q, 600, true)
	PartyAskAt := A_TickCount
	if (ans = "")
		{
		;(nothing heard: the party as last heard isn't kept - a support would go on boosting a hitter not heard from)
		PartyState := "error", PartyWhy := "the vision helper didn't answer", PartyLeader := "", PartyMembers := []
		return
		}
	members := []
	leader := ""
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		;(v1: a field the line doesn't have - blank. 32-37: the leader's loading flag, its door's walked, its time in its zone,
		;the door's age, the teleport advice and why; a member's 22-23: its tp and why - an older helper's lines haven't
		;them: blank. 38-39 / 24-25: the party's hit round - hitat and seat, v1.0.0)
		while (f.Length < 39)
			f.Push("")
		if (f[1] = "party")
			{
			if (PartyRole != f[2] || PartyState != f[3])
				DebugLog("Party: " f[2] " - " f[3] (f[4] != "" ? " (" f[4] ")" : ""))
			PartyRole := f[2], PartyState := f[3], PartyWhy := f[4]
			}
		else if (f[1] = "me")
			PartyMe := V1Obj({zone: f[2], x: f[3], y: f[4], z: f[5], yaw: f[6]})
		else if (f[1] = "leader")
			leader := V1Obj({name: f[2], zone: f[3], x: f[4], y: f[5], z: f[6], yaw: f[7], battle: f[8], hp: f[9], ready: f[10]
				, walk: f[11], age: f[12], dist: f[13], dzone: f[14], dx: f[15], dy: f[16], dz: f[17], ddx: f[18], ddy: f[19]
				, dto: f[20], bx: f[21], by: f[22], bz: f[23], hold: f[24], brole: f[25], wiz: f[26], school: f[27], hits: f[28], hitr: f[29]
				, plan: f[30], lasthit: f[31], loading: f[32], dwalk: f[33], zage: f[34], dage: f[35], port: f[36], portwhy: f[37]
				, hitat: f[38], seat: f[39]})
		else if (f[1] = "member")
			members.Push(V1Obj({name: f[2], zone: f[3], x: f[4], y: f[5], z: f[6], battle: f[7], hp: f[8], ready: f[9], age: f[10]
				, dist: f[11], walk: f[12], loading: f[13], hold: f[14], brole: f[15], wiz: f[16], school: f[17], hits: f[18], hitr: f[19]
				, plan: f[20], lasthit: f[21], tp: f[22], tpwhy: f[23], hitat: f[24], seat: f[25]}))
		}
	PartyLeader := leader, PartyMembers := members
	if (V1IsFunc("DashSee"))
		DashSee.Call("party", PartyText())
	}

;---- Battle roles ----

;This wizard's seat in the battle: its subcircle (4-7 - our side's cast order, the lowest first) by its name in the game's
;log (BlNames - one of our side so named, no two); "" not known
PartySeat()
	{
	pseMe := PartyKey(OwnName()), pseAt := ""
	if (StrLen(pseMe) < 3 || !IsObject(BlNames))
		return ""
	Loop 4
		{
		pseS := A_Index + 3
		if (!BlNames.Has(pseS) || PartyKey(BlNames[pseS]) != pseMe)
			continue
		if (pseAt != "")
			return ""
		pseAt := pseS
		}
	return pseAt
	}

;The party's hit round (Settings: partyhitround, off - v1.0.0, not tried in the game): a blader's or healer's blades and
;traps held this round while the party's hitter's hit isn't due - "" (cast as ever) or why they're held, for the log
;(KillCalc.ahk BoostPick then takes this round's blade and trap flags off). Due: the round the hitter says its planned
;hit goes out in (its hitat: the earliest it can - its pips -, its log's round), that very round when your seat casts
;before the hitter's (a lower subcircle: your blade lands before its hit - to check in the game: the log's
;AddHangingEffect before its ProcessTargets in one round), else the round before. Never held: the setting off, no party
;hitter on your side (PartyHitter), its hitat blank (an older bot, no hit planned, a learned hit's - not known) or not
;a number, either seat not known (yours, its - the log's names), or the hit 5 rounds off or more (a guess that far
;ahead isn't waited on)
PartyHitHold()
	{
	if (!Stat("partyhitround"))
		return ""
	phhH := PartyHitter()
	if (!IsObject(phhH) || !V1IsNum(phhH.hitat) || phhH.hitat < 1)
		return ""
	phhSeat := phhH.slot ? phhH.slot : V1IsNum(phhH.seat) ? phhH.seat : 0
	if (!MySlot || !phhSeat)
		return ""
	phhNow := V1N(BlRound) + 1
	phhDue := (MySlot < phhSeat) ? phhH.hitat : phhH.hitat - 1
	if (phhNow >= phhDue || phhDue - phhNow >= 5)
		return ""
	return "party hit round: " phhH.wiz "'s hit is due in round " phhH.hitat " (its seat " phhSeat ", yours " MySlot
		. (MySlot < phhSeat ? " - yours casts first: that round" : " - its casts first: the round before")
		. ") - this round's blades and traps held till round " phhDue " (partyhitround)"
	}

;This wizard's part in a party battle (Settings: partybattle - <school>.partybattle for one school's wizard): "hitter",
;"blader" or "healer"
PartyBattleSet()
	{
	k := (PartyMySchool != "" && Stats.Has(PartyMySchool ".partybattle")) ? PartyMySchool ".partybattle" : "partybattle"
	r := Stats.Has(k) ? Stats[k] : 1
	return r = 2 ? "blader" : r = 3 ? "healer" : "hitter"
	}

;A blader or healer this round: its boosts go to the party's hitter (PartyBattleRole)
PartySupport()
	{
	return BattleRole = "blader" || BattleRole = "healer"
	}

;A name as the plates and the log are matched by: its letters, in capitals (AutoQuester's WalkLetters)
PartyKey(name)
	{
	if (V1IsFunc("WalkLetters"))
		return WalkLetters.Call(name)
	name := StrUpper(name)
	return RegExReplace(name, "[^A-Z]")
	}

;This round's part (RoundStart, once the hitter's found): a party battle - more than one wizard on your side (the game's
;log), not dual mode - with this wizard set to Blader or Healer (partybattle) and the party's hitter on your side, its
;plate read: BattleRole that, the boosts to the hitter (hammerX/Y its plate, HammerSchool, HammerName). Else "hitter": as
;ever, each time it's not sure (logged once a battle). Alt+2's pick (Manual) is the hitter: a friend without the bot too
PartyBattleRole()
	{
	global
	local want, h, p, bx, by, pbrM
	BattleRole := "hitter", HammerName := "", HammerSlot := 0, HammerPlan := ""
	want := PartyBattleSet()
	if (want = "hitter" || DualBattle = 1 || BattleTeam() < 2)
		return
	if (Manual = 1)
		{
		BattleRole := want, HammerName := "the plate picked with " HkText("boost")
		return
		}
	if (PartyRoleSet() = "off")
		return PartyRoleNote("this wizard's a " want ", but the party's off (Settings, PARTY) - it hits")
	h := PartyHitter()
	if (!IsObject(h))
		return PartyRoleNote("this wizard's a " want ", but no party hitter is on your side of this battle (heard from in the last 5 s, its wizard's name known) - it hits")
	ReadSidePlates()
	p := V1At(SidePlates, h.slot)
	if (!IsObject(p))
		return PartyRoleNote(h.wiz "'s name plate wasn't read this round - this wizard hits")
	hammerX := p.x + Px(25), hammerY := p.y + Px(8)
	;(its school: as it says, else the game's memory's for the wizard at its plate (v1.0.0 - PartyMemAlly), else its plate's
	;badge - left of its name)
	pbrM := BadgeNumber(h.school) ? "" : PartyMemAlly(V1IsFunc("NavBattle") ? NavBattle.Call() : "", p.x, false)
	HammerSchool := BadgeNumber(h.school) ? h.school : (IsObject(pbrM) && BadgeNumber(pbrM.school)) ? pbrM.school
		: BestBadge(p.x - Px(100), p.y - Px(60), p.x + Px(10), p.y + Px(80), &bx, &by, p.x - Px(45), p.y + Px(15))
	BattleRole := want, HammerName := h.wiz, HammerSlot := h.slot
	;(its planned hit's schools - the boosts are for them: KillCalc.ahk BoostSearch, BoostPick)
	HammerPlan := PartySchools(h.plan)
	PartyNoteBoosts()
	PartyReblade(h)
	}

;The party's hitter in this battle, from the party's state - the leader's and the followers' (heard from in the last 5 s,
;in battle, its wizard's name one of your side's in the game's log, not yours, no two of your side so named): the one set
;to Hitter - the leader first, else the first by name, so every support picks the same -, else the leader.
;{wiz, school, hits, hitr, slot, plan, lasthit, hitat, seat - as it sent them} or "". MySlot: your slot (by your name in
;the log)
PartyHitter()
	{
	global MySlot ; (v1 globals it sets)
	phSlots := V1Obj(), phTwice := V1Obj(), MySlot := 0
	phMe := PartyKey(OwnName())
	Loop 4
		{
		phS := A_Index + 3
		if (!IsObject(BlNames) || !BlNames.Has(phS))
			continue
		phK := PartyKey(BlNames[phS])
		if (phSlots.Has(phK))
			phTwice[phK] := 1
		phSlots[phK] := phS
		if (phK != "" && phK = phMe)
			MySlot := phS
		}
	phAll := []
	if (IsObject(PartyLeader))
		phAll.Push(V1Obj({m: PartyLeader, lead: 1}))
	if (IsObject(PartyMembers))
		for each, phM in PartyMembers
			phAll.Push(V1Obj({m: phM, lead: 0}))
	phLead := "", phBest := "", phBestK := ""
	for each, phC in phAll
		{
		phM := phC.m, phK := PartyKey(phM.wiz)
		if (phM.age = "" || phM.age > 5000 || phM.battle != 1 || StrLen(phK) < 3 || phK = phMe || !phSlots.Has(phK) || phTwice.Has(phK))
			continue
		phW := V1Obj({wiz: phM.wiz, school: phM.school, hits: phM.hits, hitr: phM.hitr, slot: phSlots[phK], plan: phM.plan, lasthit: phM.lasthit
			, hitat: phM.hitat, seat: phM.seat})
		if (phC.lead)
			phLead := phW
		;(v1: the names compared alphabetically, as text - v2's < throws on text)
		if (phM.brole = "hitter" && (phC.lead || (!IsObject(phBest) || (phBestK != "lead" && V1Lt(phK, phBestK)))))
			phBest := phW, phBestK := phC.lead ? "lead" : phK
		}
	return IsObject(phBest) ? phBest : phLead
	}

;The schools in a comma list (a peer's plan / lasthit), the seven only, each once: "storm,fire,ice" ("" none)
PartySchools(list)
	{
	psOut := ","
	Loop Parse, list, ","
		{
		psS := Format("{:L}", Trim(A_LoopField))
		if (BadgeNumber(psS) && !InStr(psOut, "," psS ","))
			psOut .= psS ","
		}
	return Trim(psOut, ",")
	}

;A blader's or healer's boosts cast last round: each used flag (used0-52: UseBlade, UseTrap, PartyShield - KillCalc.ahk
;KeyFlags) newly set since the last look went out in the round noted then - the game's log's (PartyCastRound); each
;treasure or item card's copy newly cast (KillCalc.ahk BoostSrcUsed) the same (PartySrcRound). Called at each round's start
PartyNoteBoosts()
	{
	global
	local n, pnbK, pnbI, pnbGone
	if (PartyFlagDuel != BlDuel || !IsObject(PartyFlagRound))
		PartyFlagDuel := BlDuel, PartyFlagRound := V1Obj(), PartyCastRound := "", PartySrcRound := V1Obj()
	if (!IsObject(PartySrcRound))
		PartySrcRound := V1Obj()
	Loop 53
		{
		n := A_Index - 1
		if (used%n% = 1)
			{
			if (!PartyFlagRound.Has(n))
				PartyFlagRound[n] := PartyCastRound != "" ? PartyCastRound : 0
			}
		else
			PartyFlagRound.Delete(n)
		}
	pnbGone := []
	for pnbK in PartySrcRound
		if (!IsObject(BoostSrcUsed) || !BoostSrcUsed.Has(pnbK))
			pnbGone.Push(pnbK)
	for pnbI, pnbK in pnbGone
		PartySrcRound.Delete(pnbK)
	if (IsObject(BoostSrcUsed))
		for pnbK in BoostSrcUsed
			if (!PartySrcRound.Has(pnbK))
				PartySrcRound[pnbK] := PartyCastRound != "" ? PartyCastRound : 0
	;(this round's cast goes out in the log's next round)
	PartyCastRound := (BlRound ? BlRound : 0) + 1
	}

;A blader's or healer's boosts on the hitter are spent when it hits: its hits (shared) went up since last seen - once the
;round that hit goes out in is in the game's log, each of ours that went out before it (an earlier round, or that round
;before its hit in the log) is cast again - its used flag cleared; one after its hit is still on it. The first look in a
;battle only notes the count
PartyReblade(h)
	{
	global
	local ours, theirs, i, c, wait, n, at, spent, kept, prLast, prK, prGone
	if (h.hits = "")
		return
	if (PartyHitsDuel != BlDuel)
		{
		PartyHitsDuel := BlDuel, PartyHitsSeen := h.hits, PartyHitsWait := ""
		return
		}
	if (h.hits != PartyHitsSeen)
		{
		;(the round its hit goes out in - its log's; not said: the next one here)
		;(v1: a blank hitr - an older bot's - compared as text: not > 0)
		wait := V1Gt(h.hitr, 0) ? h.hitr : (BlRound ? BlRound : 0) + 1
		PartyHitsSeen := h.hits, PartyHitsWait := wait
		}
	if (PartyHitsWait = "")
		return
	BattleLogRead(true)
	if ((BlRound ? BlRound : 0) < PartyHitsWait)
		return
	ours := 0, theirs := 0
	;(v1: a for over a blank - no log's battle yet - did nothing)
	if (IsObject(BlCasts))
	for i, c in BlCasts
		if (c.round = PartyHitsWait && c.spell != "None")
			{
			if (MySlot && c.slot = MySlot)
				ours := i
			if (c.slot = h.slot)
				theirs := i
			}
	spent := 0, kept := 0
	;(the schools of its hit, as the hitter read them - "" not known: an older bot, or its heads weren't: every boost spent)
	prLast := PartySchools(h.lasthit)
	Loop 53
		{
		n := A_Index - 1
		if (used%n% != 1)
			continue
		at := (IsObject(PartyFlagRound) && PartyFlagRound.Has(n)) ? PartyFlagRound[n] : 0
		if (at > PartyHitsWait || (at = PartyHitsWait && ours && theirs && ours > theirs))
			kept += 1
		;(one that boosts none of its hit's schools is still on it: a Storm Blade through the hitter's Power Nova)
		else if (prLast != "" && (prK := FlagKey(n)) != "" && !BoostFitsAny(prK, prLast))
			kept += 1
		else
			{
			used%n% := 0, spent += 1
			if (IsObject(PartyFlagRound))
				PartyFlagRound.Delete(n)
			}
		}
	;(a treasure or item card's copy cast on it - KillCalc.ahk BoostSrcUsed: spent the same way - one cast after its hit, or
	;that boosts none of its hit's schools, is still on it: cast again, a second treasure card wouldn't stack with it)
	if (IsObject(BoostSrcUsed))
		{
		prGone := []
		for prK in BoostSrcUsed
			{
			at := (IsObject(PartySrcRound) && PartySrcRound.Has(prK)) ? PartySrcRound[prK] : 0
			if (at > PartyHitsWait || (at = PartyHitsWait && ours && theirs && ours > theirs))
				kept += 1
			else if (prLast = "" || BoostFitsAny(prK, prLast))
				prGone.Push(prK)
			else
				kept += 1
			}
		for i, prK in prGone
			{
			BoostSrcUsed.Delete(prK), spent += 1
			if (IsObject(PartySrcRound))
				PartySrcRound.Delete(prK)
			}
		}
	DebugLog("  " h.wiz " hit (" h.hits " hits so far, round " PartyHitsWait "): " spent " of our boosts on it spent - cast again" (kept ? "; " kept " still on it (cast after its hit)" : ""))
	PartyHitsWait := ""
	}

;The ally on your side lowest on health this round (the healer): each of your side's plates but yours read (Autofarmer.ahk
;PlateHealth - a low reading only with 3 of its 4 reads agreeing, as for your own). PartyLowX/Y: its plate (the name),
;PartyLowPct, PartyLowName ("" none read). Read once a round. True if one was read
;v1.0.0: each one's health from the game's memory first (PartyMemAlly - the wizard there by NavBattle, read for sure); the
;plates themselves, where a heal is clicked, still the ones read off the screen (ReadSidePlates)
PartyLowest()
	{
	global
	local i, p, r, pct, limit, key, plB
	key := BlDuel "|" roundnumber
	if (PartyLowKey = key)
		return PartyLowName != ""
	PartyLowKey := key, PartyLowX := "", PartyLowY := "", PartyLowPct := 101, PartyLowName := ""
	limit := StatOr("healat", 40)
	ReadSidePlates()
	plB := V1IsFunc("NavBattle") ? NavBattle.Call() : ""
	for i, p in SidePlates
		{
		if (p.me)
			continue
		r := PartyMemAlly(plB, p.x)
		if (!IsObject(r))
			r := PlateHealth(p.x, p.y)
		if (!IsObject(r))
			{
			DebugLog("  " p.name "'s health: not read for sure")
			continue
			}
		;(v1: a max of 0 made it blank, Round of a blank 0)
		pct := V1Round(V1Div(100 * r.cur, r.max))
		if (pct < limit && r.votes < 3)
			{
			DebugLog("  " p.name "'s health: read " r.cur "/" r.max " only " r.votes " times out of 4 - not sure enough to heal")
			continue
			}
		DebugLog("  " p.name "'s health: " r.cur "/" r.max " (" pct "%)" (V1At(r, "src") != "" ? " - " r.src : ""))
		if (pct < PartyLowPct)
			PartyLowPct := pct, PartyLowName := p.name, PartyLowX := p.x + Px(25), PartyLowY := p.y + Px(8)
		}
	return PartyLowName != ""
	}

;An ally in the game's memory (v1.0.0 - b: Vision.ahk NavBattle's battle, READ-ONLY) whose plate is at x (a side plate's
;name start, ReadSidePlates'): of the wizards on your side (player, your team, not you) the one whose plate's box holds x
;across (its l..r - one only), else - no boxes: an older helper - the one whose plate's middle is nearest, within Px(160).
;{cur, max, votes: 3 (read, not guessed: sure enough to heal on), school (its own, lower case - "" not read), src}; "" none
;there, or (health 1) its health not read, hidden, or 0 (out of the battle) - or two or more game windows running (Vision.ahk
;VisionMemOneClient, v1.0.0 review: navmem can be on another client, its battle's plates laid on yours)
PartyMemAlly(b, x, health := 1)
	{
	if (!IsObject(b) || !IsObject(b.me) || !IsObject(b.parts) || x = "" || b.me.team = "")
		return ""
	if (!V1IsFunc("VisionMemOneClient") || !VisionMemOneClient.Call())
		return ""
	pmaIn := [], pmaNear := "", pmaD := ""
	for pmaI, pmaP in b.parts
		{
		if (pmaP.me || !pmaP.player || pmaP.team != b.me.team)
			continue
		if (pmaP.l != "" && pmaP.r != "" && x >= GameLeft + pmaP.l * GameW && x <= GameLeft + pmaP.r * GameW)
			pmaIn.Push(pmaP)
		if (pmaP.x != "" && (pmaD = "" || Abs(GameLeft + pmaP.x * GameW - x) < pmaD))
			pmaNear := pmaP, pmaD := Abs(GameLeft + pmaP.x * GameW - x)
		}
	pmaA := (pmaIn.Length = 1) ? pmaIn[1] : (!pmaIn.Length && IsObject(pmaNear) && pmaNear.l = "" && pmaD <= Px(160)) ? pmaNear : ""
	if (!IsObject(pmaA))
		return ""
	if (health && (pmaA.health = "" || pmaA.max = "" || pmaA.max <= 0 || pmaA.health <= 0 || pmaA.health > pmaA.max || pmaA.hide = 1))
		return ""
	return V1Obj({cur: pmaA.health, max: pmaA.max, votes: 3, school: StrLower(Trim(pmaA.school)), src: "the game's memory"})
	}

;The healer: the ally lowest on health (PartyLowest) under healat % and lower than you - a heal for one wizard on it, or
;one that heals all of you (heal1, then heal2; not one known to heal only you: <school>.healNtarget:0; :2 heals all of
;you). True if one went out
PartyHealAlly()
	{
	global
	local limit, hcard, each
	limit := StatOr("healat", 40)
	if (!PartyLowest() || PartyLowPct >= limit)
		return false
	;(you lower - a reading your own heal acts on, 3 of its 4 reads agreeing: your own heal, next)
	if (OwnHpRound != roundnumber && playerX != "")
		OwnHealthLow(true)
	;(v1: a blank count of reads compared as text - not >= 3)
	if (OwnHpRound = roundnumber && OwnHpPct != "" && OwnHpPct <= PartyLowPct && V1Ge(OwnHpVotes, 3))
		return false
	DebugLog("  healer: " PartyLowName " at " PartyLowPct "% (under " limit "%) - a heal on " PartyLowName)
	for each, hcard in ["heal1", "heal2"]
		{
		if (%hcard% != 1 || (Stats.Has(hitschool "." hcard "target") && Stats[hitschool "." hcard "target"] = 0))
			continue
		;(v1: heal1 / heal2 itself passed ByRef - v2's reference to the variable that names)
		if UseHeal(hcard, &%hcard%, hitschool, PartyLowX, PartyLowY)
			return true
		}
	DebugLog("  healer: no heal in hand that goes on an ally")
	return false
	}

;Tower Shield (resources\tower, usetower on - one no picture finds at its card box by the game's hand: KillCalc.ahk
;TowerMem, Autofarmer.ahk UseMemAt) for the party: the healer's on the ally lowest on health while under twice healat %,
;else - and the blader's - on the hitter; once till the hitter's next hit (used19). True if it went out
PartyShield()
	{
	global
	local limit, tx, ty, who, _title, _dir
	if (tower != 1 || !Stat("usetower") || used19 = 1)
		return false
	limit := StatOr("healat", 40)
	if (BattleRole = "healer" && PartyLowest() && PartyLowPct < 2 * limit)
		tx := PartyLowX, ty := PartyLowY, who := PartyLowName " (" PartyLowPct "%)"
	else
		tx := hammerX, ty := hammerY, who := HammerName
	DebugLog("  " BattleRole ": Tower Shield on " who)
	if (UseOnHammer(&_title := "tower", &tower, &_dir := "resources", tx, ty) && CastWentOut())
		{
		used19 := 1
		if (V1IsFunc("DashCast"))
			DashCast.Call("tower")
		return true
		}
	return false
	}

;Where a blader's or healer's traps go (no boss picked with Alt+1): the enemy the hitter goes for - the one with the
;least health, as its hits pick (Autofarmer.ahk HitTarget); the enemies' plates as read in the last 8 s, else now
;(KillCalc.ahk ReadEnemyHealth). False: none read - no traps (nowhere sure to put them)
PartyTrapTarget(&x, &y)
	{
	;(v1: never read - blank - counted as just read: not read now)
	if (V1Gt(V1Ago(EnemyPlatesAt), 8000))
		ReadEnemyHealth()
	if (!IsObject(EnemyPlates) || !EnemyPlates.Length || !IsObject(EnemyHP) || EnemyHP.Length != EnemyPlates.Length)
		return false
	ptPick := 1
	for ptI, ptE in EnemyHP
		if (ptE.cur < EnemyHP[ptPick].cur)
			ptPick := ptI
	x := EnemyPlates[ptPick].x, y := EnemyPlates[ptPick].y
	return true
	}

;Why this wizard hits after all (a blader or healer that isn't sure): in debug.log once a battle
PartyRoleNote(why)
	{
	static saidDuel := "", saidWhy := ""
	if (saidDuel = BlDuel && saidWhy = why)
		return
	saidDuel := BlDuel, saidWhy := why
	DebugLog("  party battle: " why)
	}

;---- The leader's orders (partyorders - TODO goal 3, advice only: nothing cast) ----

;The setting (Settings: partyorders - on every PC of the party): 0 off, 1 on. Never throws
PartyOrdersOn()
	{
	pooOn := 0
	try pooOn := StatOr("partyorders", 0)
	return (V1IsNum(pooOn) && pooOn >= 1) ? 1 : 0
	}

;The party's leader in a party battle, partyorders and planner on: its planner round may plan the team (Planner.ahk) and
;its round's end tells its followers a round it didn't (PartyOrderSkip). False on any error
PartyOrdersLead()
	{
	try
		return PartyOrdersOn() && PartyRoleSet() = "leader" && PlannerMode() && BattleTeam() >= 2
	catch
		return false
	}

;The leader able to plan now - partyorders and planner on, its bot on, none of the planner's lasting rules against it
;(Planner.ahk PlannerBlock: dual mode, two game windows, the helper, navmem, learning every card, you took a round of
;this battle): only then does its helper ask the followers for their hands (PartyTick's &plans=1) - so no follower ever
;waits on a leader that can't plan. False on any error
PartyOrdersCanPlan()
	{
	try
		return PartyOrdersOn() && PartyRoleSet() = "leader" && PlannerMode() && BotOn && PlannerBlock() = ""
	catch
		return false
	}

;The leader's team plan this round: PartyOrdersLead and its helper holding at least one follower's fresh hand
;(PartyOrderHands) - else its /plan is as before (300 ms, no team plan) and a blader's or healer's isn't asked. False on
;any error
PartyOrdersTeam()
	{
	try
		return PartyOrdersLead() && PartyOrderHands() > 0
	catch
		return false
	}

;How many followers' fresh hands the leader's helper holds (/partyorder?lead=1 - lead|<n>), asked once a round (the log's
;round and the bot's, as PlannerAsked: PlannerOn, PlannerQuery and PlannerRound share it); 0 for anything else
PartyOrderHands()
	{
	static pohKey := "", pohN := 0
	try
		{
		pohK := BlDuel "|" BlRound "|" roundnumber
		if (pohK == pohKey)
			return pohN
		pohKey := pohK, pohN := 0
		pohA := Trim(VisionGet("/partyorder?lead=1", 300, true), " `r`n")
		if (RegExMatch(pohA, "^lead\|(\d{1,2})$", &pohM))
			pohN := pohM[1] + 0
		return pohN
		}
	catch
		return 0
	}

;(the leader's round's end - Autofarmer.ahk EndRound) a round it didn't plan the team in - a kill, a defence, a heal, a
;shield, you playing, no plan - told to its followers at once: those whose hand is for this round and have no order yet
;stop waiting (/partyorder?noplan=<round> - one it planned marks nothing). Never throws
PartyOrderSkip()
	{
	try
		{
		posR := V1Add(BlRound, 1)
		if (posR != "")
			VisionGet("/partyorder?noplan=" posR, 300, true)
		}
	}

;A follower's own key for its hand this round: d<duel>r<log round> (the game's log - BlDuel all digits), "" not known.
;Only this PC's key - its helper keeps the hand under it, its leader echoes it - never compared across PCs
PartyOrderTag()
	{
	try
		{
		potR := V1Add(BlRound, 1)
		if (RegExMatch(BlDuel, "^\d{1,9}$") && potR != "")
			return "d" BlDuel "r" potR
		}
	return ""
	}

;(Vision.ahk VisionCards) the query on a follower's own hand read with partyorders on, in battle, one game window
;(Vision.ahk VisionMemOneClient - with two navmem can be on another client's hand; asked last, so a PC with it off
;never counts the windows here): "?ptag=<its key>" - its helper keeps that hand for the leader; "" otherwise (/cards
;as ever)
PartyCardsTag()
	{
	try
		{
		if (!PartyOrdersOn() || PartyRoleSet() != "follower" || inbattle != 1 || !V1IsFunc("VisionMemOneClient") || !VisionMemOneClient.Call())
			return ""
		pctT := PartyOrderTag()
		return pctT != "" ? "?ptag=" pctT : ""
		}
	return ""
	}

;The party's leader in this battle on your side: heard from in the last 5 s, in battle, its wizard's name one of your
;side's in the game's log (exactly one of seats 4-7 so named - not yours). Else no order is waited for
PartyOrderLeaderHere()
	{
	try
		{
		if (!IsObject(PartyLeader) || PartyLeader.age = "" || PartyLeader.age > 5000 || PartyLeader.battle != 1 || !IsObject(BlNames))
			return false
		polK := PartyKey(PartyLeader.wiz)
		if (StrLen(polK) < 3 || polK = PartyKey(OwnName()))
			return false
		polN := 0
		Loop 4
			if (BlNames.Has(A_Index + 3) && PartyKey(BlNames[A_Index + 3]) = polK)
				polN += 1
		return polN = 1
		}
	catch
		return false
	}

;A party battle's round (the battle loop, after the planner - partyorders on): a follower asks its helper for the
;leader's card for its hand (/partyorder?tag=), waits for it 3 s at most and logs it - advice only: nothing is cast, no
;global the round reads is set, the round then goes on exactly as without it. Two rounds in a row with none: not
;waited for again this battle; six (across battles): not till one comes - still asked once a round, no wait. The
;leader: a note once a battle when planner is off. Never throws
PartyOrderRound()
	{
	global PartyOrderAsked, PartyOrderMiss ; (globals it sets)
	try
		{
		if (!PartyOrdersOn() || BattleTeam() < 2 || dualmode == 1 || !VisionOn)
			return
		porRole := PartyRoleSet()
		if (porRole = "leader")
			{
			if (!PlannerMode())
				PartyOrderNote("the team isn't planned - partyorders needs planner on on the leader's PC (Settings: planner)")
			return
			}
		if (porRole != "follower")
			return
		;(once a round: the log's round and the bot's, as PlannerAsked)
		porKey := BlDuel "|" BlRound "|" roundnumber
		if (porKey == PartyOrderAsked)
			return
		PartyOrderAsked := porKey
		porTag := PartyOrderTag()
		if (porTag = "" || !PartyOrderLeaderHere())
			return
		if (!IsObject(PartyOrderMiss))
			PartyOrderMiss := V1Obj({duel: BlDuel, n: 0, run: 0})
		if (PartyOrderMiss.duel != BlDuel)
			PartyOrderMiss.duel := BlDuel, PartyOrderMiss.n := 0
		;(0: asked once, no wait)
		porMax := (PartyOrderMiss.n >= 2 || PartyOrderMiss.run >= 6) ? 0 : 3000
		porAt := A_TickCount, porWhy := ""
		Loop
			{
			porF := StrSplit(Trim(VisionGet("/partyorder?tag=" porTag, 300, true), " `r`n"), "|")
			while (porF.Length < 11)
				porF.Push("")
			if (porF[1] = "order" && porF[2] = "ok")
				{
				PartyOrderMiss.n := 0, PartyOrderMiss.run := 0
				DebugLog("  " PartyOrderText(porF, A_TickCount - porAt))
				return
				}
			;(none - why in this PC's own helper's words, never the leader's: once a battle; a marker - kind "mark" - is the
			;leader answering: the misses start again. No answer from the helper: no wait)
			if (porF[1] != "order" || porF[2] != "wait")
				{
				if (porF[1] = "order" && porF[6] = "mark")
					PartyOrderMiss.n := 0, PartyOrderMiss.run := 0
				if (porF[1] = "order" && porF[11] != "")
					PartyOrderNote("no order from the leader - " porF[11])
				return
				}
			porWhy := porF[11]
			if (!BotOn || A_TickCount - porAt >= porMax)
				break
			Sleep(150)
			}
		;(F6: the battle loop's own check after this takes over; not waiting: nothing to say)
		if (!BotOn || porMax = 0)
			return
		PartyOrderMiss.n += 1, PartyOrderMiss.run += 1
		DebugLog("  Plan: no order from the leader in " (A_TickCount - porAt) " ms (" porWhy ") - your own way (partyorders)")
		if (PartyOrderMiss.n = 2)
			DebugLog("  Plan: not waiting for the leader's orders again this battle (two rounds in a row with none) - still asked once a round")
		if (PartyOrderMiss.run = 6)
			DebugLog("  Plan: not waiting for the leader's orders till one comes (six rounds in a row with none) - still asked once a round")
		}
	catch Any as e
		{
		try DebugLog("  Plan: the leader's order failed - " (IsObject(e) ? e.Message : e) " (the round goes on as ever)")
		}
	}

;The order's line (/partyorder's ok: f[4] the card - this wizard's own name for it, "tid N" or "pass" -, f[5] its tid, f[7]
;the enemy, f[8] won %, f[9] tries, f[10] ms since the leader planned, f[11] its own helper's note): "Plan: the leader
;would have you play <card> at <enemy> / on all (won N%, n tries) [tid T] - the leader's plan, advice only (partyorders,
;M ms after it planned, waited W ms)". The enemy named only as this PC's own log names it (PartyOrderFoe). Not the
;planner's "Plan: would play" (battlelearn.py's ADVICE_RX)
PartyOrderText(f, waited)
	{
	if (f[7] = "all")
		potAt := " on all"
	else if (PartyOrderFoe(f[7]) != "")
		potAt := " at " PartyOrderFoe(f[7])
	else if (f[7] != "")
		potAt := " at an enemy not named in this PC's log"
	else
		potAt := ""
	return "Plan: the leader would have you play " f[4] potAt " (won " f[8] "%, " f[9] " tries)"
		. (f[5] != "" ? " [tid " f[5] "]" : "")
		. " - the leader's plan, advice only (partyorders, " f[10] " ms after it planned, waited " waited " ms)"
		. (f[11] != "" ? " - " f[11] : "")
	}

;This PC's own log name for the enemy the leader named (one of BlNames 0-3 equal to it - case aside), "" none: the line
;names an enemy only in this PC's own words
PartyOrderFoe(name)
	{
	if (name = "" || !IsObject(BlNames))
		return ""
	Loop 4
		{
		pofK := A_Index - 1
		if (BlNames.Has(pofK) && BlNames[pofK] = name)
			return BlNames[pofK]
		}
	return ""
	}

;A partyorders note in debug.log, once a battle for each why ("  Plan: <why> (partyorders)")
PartyOrderNote(why)
	{
	global PartyOrderSaid ; (globals it sets)
	try
		{
		if (!IsObject(PartyOrderSaid) || PartyOrderSaid.Count >= 50)
			PartyOrderSaid := Map()
		ponK := BlDuel "|" why
		if (!PartyOrderSaid.Has(ponK))
			PartyOrderSaid[ponK] := 1, DebugLog("  Plan: " why " (partyorders)")
		}
	}

;The party in a line (the dashboard)
PartyText()
	{
	if (PartyRole = "off" || PartyRole = "")
		return ""
	if (PartyState = "unreachable" || PartyState = "error")
		return PartyRole " - " PartyWhy
	if (PartyRole = "leader")
		{
		t := ""
		for each, m in PartyMembers
			t .= (t = "" ? "" : ", ") (m.name != "" ? m.name : "?") " " (m.tp = "wait" ? "can't follow" : m.tp = "porting" ? "teleporting to you" : m.zone != V1At(PartyMe, "zone") ? "in another zone" : m.battle = 1 ? "in battle" : m.dist != "" ? m.dist " away" : "?")
		return "leader - " (t = "" ? "no followers yet" : t) (PartyHolding != "" ? " (waiting: " PartyHolding ")" : "")
		}
	L := PartyLeader
	if (!IsObject(L))
		return "follower - waiting to hear from the leader"
	;(PartyMe blank till the helper says where you are - v1: its zone blank. Can't follow, or stuck: said - PartyCantFollow)
	return "following " (L.name != "" ? L.name : "the leader") " - " (PartyTp = "wait" ? "can't follow (" PartyTpWhy ")" : PartyTp = "stuck" ? "stuck on the way" : L.zone != V1At(PartyMe, "zone") ? "in " L.zone : L.battle = 1 ? "in battle" : L.dist " away")
	}

;The leader's hold (the walker asks: Walker.ahk WalkStep): why it should wait now - a follower (heard from in the last 5 s)
;in another zone, farther than partywaitdist, or not ready; "" walk on. One held partywaitmax s isn't waited for again
;till it's been near once. (v1.0.0: partywaitmax 0 - no waiting at all, as Settings says: it waited for good before. One
;that says it can't follow - tp wait: the leader went where no door it walked through leads from its zone, or its door
;didn't take it - or that the game refused its teleport isn't waited for, till it's been near once: holding doesn't bring
;it. One teleporting to you is waited for; one stuck on its way as ever, said)
PartyHoldWhy()
	{
	global PartyHolding, PartyHeldFrom, PartySkip ; (v1 globals it sets)
	PartyHolding := ""
	if (PartyRoleSet() != "leader" || PartyState != "serving" || !IsObject(PartyMembers))
		return ""
	if (!IsObject(PartyHeldFrom))
		PartyHeldFrom := V1Obj(), PartySkip := V1Obj()
	maxS := Stat("partywaitmax"), far := Stat("partywaitdist")
	;(0: no waiting, as Settings says - it waited for good before: a follower that couldn't follow stalled the party)
	if (maxS <= 0)
		return ""
	why := ""
	for each, m in PartyMembers
		{
		if (m.age = "" || m.age > 5000)
			continue
		key := m.name != "" ? m.name : "a follower"
		;(near again: waited for again)
		phwNear := m.zone = V1At(PartyMe, "zone") && m.dist != "" && m.dist <= far / 2
		if (phwNear)
			PartySkip.Delete(key), PartyHeldFrom.Delete(key)
		if (PartySkip.Has(key))
			continue
		;(it can't follow - or the game refused its teleport: not waited for till it's near again, said once)
		if ((m.tp = "wait" || m.tp = "refused") && !phwNear)
			{
			PartySkip[key] := 1, PartyHeldFrom.Delete(key)
			DebugLog("Party: " key (m.tp = "refused" ? " can't teleport to you" : " can't follow") (m.tpwhy != "" ? " (" m.tpwhy ")" : "") " - walking on without them till they're near again")
			continue
			}
		w := m.loading = 1 ? key " is loading" : m.tp = "porting" ? key " is teleporting to you" : m.zone != V1At(PartyMe, "zone") ? key " is in another zone" : (m.dist != "" && m.dist > far) ? key " is " m.dist " away"
			: m.ready != 1 ? key " isn't ready (bot off, not walking, or played by hand)" : ""
		;(five stuck tries on its way: said - waited for as ever)
		if (w != "" && m.tp = "stuck")
			w .= " (stuck on its way)"
		if (w = "")
			{
			PartyHeldFrom.Delete(key)
			continue
			}
		if (!PartyHeldFrom.Has(key))
			PartyHeldFrom[key] := A_TickCount
		if (maxS > 0 && A_TickCount - PartyHeldFrom[key] > maxS * 1000)
			{
			PartySkip[key] := 1
			DebugLog("Party: waited " maxS " s for " key " - walking on without them till they're near again")
			continue
			}
		why .= (why = "" ? "" : "; ") w
		}
	PartyHolding := why
	return why
	}

;The follower's step (the walking dispatch, instead of WalkStep): to the leader - stopping partynear from it, walking
;again past twice that; into its battle (its battle spot, mobs not avoided - the battle's own are there); through the
;door it took (its last spot in this zone, then 400 on the way it was going). Stuck (its own place hardly moving with W
;down for 3 s): back up, turn 90, walk - 4 times at most, then it waits for the leader to come back near
;(v1.0.0 - TODO goal 1: the door is the leader's latest out of this wizard's zone - two zones behind, door after door; one
;the helper says the leader didn't walk through - a teleport: End, Home, a sigil, a potion run - isn't walked to with
;partytpdoors on (off, the default - the guess isn't checked in the game yet: logged, and walked to as ever); one that
;hasn't taken this wizard in 3 tries is given up till its zone changes, or for 6 minutes (a try a battle cut short not
;counted); wherever no door leads it waits and says so - PartyCantFollow, the leader told. Five stuck tries: it waits
;30 s, then they start again - before, they never did till it had stood by the leader: W 3 s, stop 1 s, for good. A new
;zone - its own or the leader's - starts them again at once: PartyZoneCheck)
PartyFollowStep()
	{
	global WkFrontLook, PartyNear, PartyTries, PartyStillAt, PartyPushUntil, PartyStillX, PartyStillY, PartyDoorKey, PartyDoorTries, PartyDoorGave, PartyStuckAt, PartyDoorGaveAt, PartyDoorBattles, PartyDwalkSaid ; (v1 globals it sets)
	;(battles only - Autofarmer.ahk, Settings: battlesonly: no following - the main loop doesn't ask then; never a step all the same)
	if (BattlesOnlyNo("following the party's leader"))
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		return
		}
	;(a new zone - this wizard's or the leader's: the stuck and door tries start again)
	PartyZoneCheck()
	if (!Walking || !GameActive() || inbattle = 1 || !BotNoBattle())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(Wizard101 behind another window, you away 5 minutes - or Play for me: brought to the front, as the walker does)
		;(v1: WkFrontLook never set - blank - compared as text: not > 1500)
		if (Walking && !GameActive() && inbattle != 1 && V1IsFunc("GameToFront") && UserIdle() > 300000 && V1Gt(V1Ago(WkFrontLook), 1500))
			WkFrontLook := A_TickCount, GameToFront.Call("following the leader", true, true)
		Sleep(150)
		return
		}
	L := PartyLeader
	if (PartyState != "following" || !IsObject(L) || L.age = "" || L.age > 5000)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("party: waiting for the leader" (PartyWhy != "" ? " - " PartyWhy : ""))
		Sleep(300)
		return
		}
	near := Stat("partynear"), pfKey := "", pfWho := L.name != "" ? L.name : "the leader"
	;(this wizard's zone not read - its own loading screen: nothing decided till it is)
	if (V1At(PartyMe, "zone") = "")
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("party: waiting - this wizard's zone isn't read (a loading screen?)")
		Sleep(300)
		return
		}
	;Where to: the leader's battle, the leader, or the door it took
	;(PartyMe blank till the helper says where you are - v1: its zone blank)
	if (L.zone = V1At(PartyMe, "zone") && L.battle = 1 && L.bx != "")
		tgt := V1Obj({x: L.bx, y: L.by, z: L.bz, kind: "battle", stop: 40})
	else if (L.zone = V1At(PartyMe, "zone") && L.x != "")
		{
		tgt := V1Obj({x: L.x, y: L.y, z: L.z, kind: "leader", stop: near})
		;(standing by it: still till it's twice as far)
		if (!PartyNear && L.dist != "" && L.dist <= near)
			PartyNear := 1
		if (PartyNear && L.dist != "" && L.dist > near * 2)
			PartyNear := 0
		if (PartyNear)
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			PartyTries := 0, PartyStillAt := 0, PartyStuckAt := 0
			PartyFollowOk(L)
			;(the leader's mount: X at its prompt to ride - Settings: partyride)
			PartyRideCheck(L)
			SetStatus("party: by " (L.name != "" ? L.name : "the leader") " (" L.dist " away)")
			Sleep(200)
			return
			}
		}
	;(the leader was here and its zone isn't read now - it's loading: the door it took isn't known yet, and an older one out
	;of here - from an earlier time it was here - mustn't be walked to meanwhile)
	else if ((L.zone = "" || L.loading = 1) && PartyLdZone = V1At(PartyMe, "zone"))
		return PartyWaitLoading(L)
	else if (L.dzone = V1At(PartyMe, "zone") && L.dx != "")
		{
		pfKey := L.dzone "|" Round(V1N(L.dx)) "|" Round(V1N(L.dy)) "|" L.dto
		;(not walked through - a teleport: End, Home, a sigil, a potion run (the leader stood still before its zone changed) -
		;nowhere to walk. Only with Settings' partytpdoors on: the helper's guess isn't checked in the game yet (vision\party.py
		;WALK_MIN, DOOR_WINDOW - a loading screen still in the old zone, its place frozen, would look like standing still,
		;and the leader walks on without one that says it can't follow). Off, the default: logged once a door, and walked to
		;as ever - the 3 tries below give a real teleport's spot up. Blank - an older helper: walked to as ever)
		if (L.dwalk = "0")
			{
			if (Stat("partytpdoors"))
				return PartyCantFollow(L, "the leader teleported from here to " L.dto " - no door to walk through")
			if (PartyDwalkSaid != pfKey)
				{
				PartyDwalkSaid := pfKey
				DebugLog("Party: the helper says " pfWho " teleported from here to " L.dto " (it stood still) - walking to its spot all the same (Settings: partytpdoors off)")
				}
			}
		;(given up - 3 tries didn't take this wizard: not again till its zone changes, or the leader takes a door again, or
		;6 minutes on - the Discord alert goes at 5 (PartyCantFollow): a try something passing spoilt - a dialog, the game
		;behind another window - doesn't keep it here for good)
		if (PartyDoorGave = pfKey && V1Lt(V1Ago(PartyDoorGaveAt), 360000))
			return PartyCantFollow(L, "the leader's door here to " L.dto " didn't take this wizard (3 tries)")
		if (PartyDoorGave = pfKey)
			{
			PartyDoorGave := "", PartyDoorTries := 0
			DebugLog("Party: trying " pfWho "'s door here to " L.dto " again (6 minutes after giving it up)")
			}
		tgt := V1Obj({x: L.dx, y: L.dy, z: L.dz, kind: "door", stop: 100})
		}
	else if (L.zone = "" || L.loading = 1)
		return PartyWaitLoading(L)
	else
		return PartyCantFollow(L, "no door the leader walked through leads to " L.zone " from here")
	;(stuck five times: it waits 30 s - the leader told -, then the tries start again; a zone change, or the leader near,
	;starts them again at once)
	pfWhat := tgt.kind = "leader" ? "the leader" : tgt.kind = "battle" ? "the leader's battle" : "the leader's door"
	if (PartyStuckAt && A_TickCount - PartyStuckAt < 30000)
		return PartyCantFollow(L, "stuck on the way to " pfWhat, "stuck")
	if (PartyStuckAt)
		{
		PartyStuckAt := 0, PartyTries := 0
		DebugLog("Party: trying the way to " pfWhat " again (30 s after five stuck tries)")
		}
	PartyFollowOk(L)
	;(through the door: walked on the way the leader went, for 4 s)
	;(v1: PartyPushUntil never set - blank - compared as text: the tick isn't < it; a blank way to go made a blank place)
	if (tgt.kind = "door" && V1Lt(A_TickCount, PartyPushUntil))
		tgt := V1Obj({x: V1Add(L.dx, V1Mul(400, L.ddx)), y: V1Add(L.dy, V1Mul(400, L.ddy)), z: L.dz, kind: "push", stop: 0})
	nav := PartyNavTo(tgt, tgt.kind = "leader" || tgt.kind = "door")
	if (!IsObject(nav))
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("party: the game's memory can't be read for the way to the leader")
		Sleep(300)
		return
		}
	;(v1: a blank place - a field the helper didn't give - made the sum blank, and Sqrt of a blank 0)
	pfDx := V1Sub(nav.x, tgt.x), pfDy := V1Sub(nav.y, tgt.y)
	d := Sqrt((pfDx = "" || pfDy = "") ? 0 : pfDx ** 2 + pfDy ** 2)
	if (tgt.kind = "door" && d <= tgt.stop)
		{
		;(a try at it: one more each time it's reached - the push on through after. The 4th time with no zone change between,
		;it's given up: it doesn't take this wizard - a door that needs more than walking, or one only the leader's quest
		;opens. It looped door, push, door for good before. A battle since the last push - a mob by the doorway: the push
		;isn't walked round mobs - cut that try short: not counted - Autofarmer.ahk's battles, as Dungeons.ahk's loadBattles)
		if (PartyDoorKey != pfKey)
			PartyDoorKey := pfKey, PartyDoorTries := 0
		else if (V1N(battles) != V1N(PartyDoorBattles))
			PartyDoorTries := Max(0, V1N(PartyDoorTries) - 1)
		PartyDoorTries := V1N(PartyDoorTries) + 1, PartyDoorBattles := battles
		if (PartyDoorTries > 3)
			{
			PartyDoorGave := pfKey, PartyDoorGaveAt := A_TickCount
			return PartyCantFollow(L, "the leader's door here to " L.dto " didn't take this wizard (3 tries)")
			}
		PartyPushUntil := A_TickCount + 4000
		DebugLog("Party: at the door " pfWho " took" (V1IsNum(L.dage) ? " " Round(L.dage / 1000) " s ago" : "") " - walking on through it (try " PartyDoorTries " of 3)")
		}
	if (d <= tgt.stop && tgt.kind != "door")
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		Sleep(150)
		return
		}
	;(stuck: its own place hardly moving for 3 s with W down)
	if (HeldW && PartyStillAt && Sqrt((nav.x - PartyStillX) ** 2 + (nav.y - PartyStillY) ** 2) < 60)
		{
		if (A_TickCount - PartyStillAt > 3000)
			{
			;(v1: += chained with a comma kept a blank PartyTries blank - set to 0 only once it's stood by the leader;
			;blank isn't > 4, and blank & 1 is blank: -90. v1.0.0: a new zone sets it to 0 too - PartyZoneCheck, the first
			;zone read among them - so it counts from the start)
			PartyTries := V1Add(PartyTries, 1), PartyStillAt := 0
			if (V1Gt(PartyTries, 4))
				{
				;(five: it waits 30 s - the leader told -, then they start again; it walked 3 s, stopped 1 s, for good before)
				PartyStuckAt := A_TickCount
				return PartyCantFollow(L, "stuck on the way to " pfWhat, "stuck")
				}
			DebugLog("Party: stuck on the way to the " tgt.kind " (" Round(d) " away) - backing up and turning, try " PartyTries)
			BackUp(700)
			DgTurn((V1IsNum(PartyTries) && (PartyTries & 1)) ? 90 : -90)
			HoldW(1)
			Sleep(900)
			return
			}
		}
	else
		PartyStillAt := A_TickCount, PartyStillX := nav.x, PartyStillY := nav.y
	SetStatus("party: following " (L.name != "" ? L.name : "the leader") " - to its " tgt.kind ", " Round(d) " away")
	DgSteer(nav, tgt, d)
	}

;A new zone - this wizard's or the leader's, each its last read (a blank - a loading screen - isn't a change): the stuck
;tries start again (v1.0.0 - before, they only started again by the leader: after five in one zone the back-ups and turns
;were never tried again). This wizard's own: the door tries too, and a door given up may be tried again (the leader's
;doesn't make a door out of here that didn't take it work - one it walked through again is a new door: tried)
PartyZoneCheck()
	{
	global PartyMyZone, PartyLdZone, PartyTries, PartyDoorKey, PartyDoorTries, PartyDoorGave, PartyStuckAt, PartyPushUntil, PartyStillAt ; (v1 globals it sets)
	pzcMe := V1At(PartyMe, "zone"), pzcLd := V1At(PartyLeader, "zone")
	pzcMine := pzcMe != "" && pzcMe != PartyMyZone
	if (!pzcMine && (pzcLd = "" || pzcLd = PartyLdZone))
		return
	if (pzcLd != "")
		PartyLdZone := pzcLd
	PartyTries := 0, PartyStuckAt := 0, PartyStillAt := 0
	if (pzcMine)
		PartyMyZone := pzcMe, PartyDoorKey := "", PartyDoorTries := 0, PartyDoorGave := "", PartyPushUntil := 0
	}

;The leader loading (its zone not read, or its loading flag - WizardClient.log's, as it sent it): the follower waits, keys
;up - the door it's taking isn't known till it's there (not "can't follow": that's decided once it is)
PartyWaitLoading(L)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	SetStatus("party: waiting - " (L.name != "" ? L.name : "the leader") " is loading")
	Sleep(300)
	}

;Following again (a way to walk, or standing by the leader): the leader told (tp blank), and said once when it couldn't
;follow before
PartyFollowOk(L)
	{
	global PartyTp, PartyTpWhy, PartyCantAt, PartyCantSaid, PartyPortSaid, PartyCantAlerted ; (v1 globals it sets)
	if (PartyTp = "wait")
		DebugLog("Party: following " (L.name != "" ? L.name : "the leader") " again")
	PartyTp := "", PartyTpWhy := "", PartyCantAt := 0, PartyCantSaid := "", PartyPortSaid := "", PartyCantAlerted := 0
	}

;The follower can't follow (TODO goal 1): the leader went where no door it walked through leads from here - it teleported
;(End, Home, a sigil, a potion run), or its door didn't take this wizard -, or (tp "stuck") five stuck tries on the way. It
;stands where it is and says so: the status, debug.log once a wait, the leader told (PartyTp - it stops waiting for one
;that can't follow: PartyHoldWhy), a Discord alert after 5 minutes of it. The helper's advice (vision\party.py
;port_advice: the leader's zone known, it not loading, there 3 s or more, no door it walked through leads on from here -
;L.port 1) logged once a wait and zone. tp: "wait" or "stuck"
PartyCantFollow(L, why, tp := "wait")
	{
	global PartyTp, PartyTpWhy, PartyCantAt, PartyCantSaid, PartyPortSaid, PartyCantAlerted ; (v1 globals it sets)
	if (KeysDown || HeldW)
		ReleaseKeys()
	pcfWho := L.name != "" ? L.name : "the leader"
	if (PartyTp != tp || !PartyCantAt)
		PartyCantAt := A_TickCount, PartyCantAlerted := 0
	PartyTp := tp, PartyTpWhy := why
	if (PartyCantSaid != why)
		{
		PartyCantSaid := why
		DebugLog("Party: " (tp = "stuck" ? why " five times - waiting 30 s, then trying again" : "can't follow " pcfWho " - " why " - waiting here") " (" pcfWho " is told)")
		}
	if (tp = "wait" && L.port = 1 && PartyPortSaid != L.zone)
		{
		PartyPortSaid := L.zone
		DebugLog("Party: teleporting to " (L.wiz != "" ? L.wiz : pcfWho) " would be the way now (" L.portwhy ")" (StatOr("partytp", 1) ? "" : " - Settings: partytp is off"))
		}
	;(lost: teleported to the leader by the game's Group button - Settings: partytp, on; PartyGroupPort says why not, once a
	;reason. True: it's teleporting - followed from where it lands)
	if (PartyGroupPort(L, why, tp))
		return
	if (tp = "wait" && !PartyCantAlerted && A_TickCount - PartyCantAt > 300000)
		{
		PartyCantAlerted := 1
		if (V1IsFunc("AlertSend"))
			AlertSend.Call("party", "a party follower can't follow", "Waiting 5 minutes: " why ". Bring it to " pcfWho " yourself"
				. (StatOr("partytp", 1) ? " - its teleport by the game's Group button didn't work (debug.log: `"Party: ... teleport`" says why; is it in the leader's group in the game?)." : " - Settings: partytp (teleport to the leader) is off."))
		}
	if (tp = "stuck")
		SetStatus("party: stuck on the way - waiting " Max(0, 30 - (A_TickCount - PartyStuckAt) // 1000) " s, then trying again")
	else
		SetStatus("party: can't follow - " why " - waiting here (" (A_TickCount - PartyCantAt) // 1000 " s)")
	Sleep(500)
	}

;---- A lost follower's teleport to the leader by the game's Group button; riding the leader's mount (untried in the game) ----

;Lost (PartyCantFollow: no door it walked through leads to the leader - tp "wait", with the helper's advice L.port 1 or the
;leader's door given up - or five stuck tries on the way - tp "stuck") and in a group in the game with the leader: teleported
;to it by the HUD's Group button (Settings: partytp, on). The button (windowHUD/GroupSystemButton, Button_Group.dds - the game
;shows it only while you're in a group) opens its row (GroupButtonLayout: Teleport, Roster, Follow - Button_Teleport_To_Friend,
;Button_Group, Button_Follow_Group_Leader) and its Teleport (GroupButtonLayout/GroupTeleportButton) is clicked - each click
;target from the game's memory (NavGui, read-only) as Quick Sell's are (PartyPortClick). Then up to 12 s (PartyPortWatch): a
;loading screen, a new zone or a jump of 400 units - teleported; a message box - answered (PartyPortBox); nothing - the
;windows that came up logged (what the bot doesn't know yet) and left for 5 minutes. A try at most once a minute; none in
;battle, loading, quick selling, with Wizard101 behind another window or you playing (PartyPortWhyNot). PartyTp "porting"
;meanwhile (the leader waits for it). True: it teleported, or is loading on the way - followed from where it lands
PartyGroupPort(L, why, tp)
	{
	global PartyTp, PartyTpWhy, PartyPortAt, PartyPortNot, PartyStuckAt, PartyTries, PartyPortOffUntil ; (globals it sets)
	ppWho := L.wiz != "" ? L.wiz : L.name != "" ? L.name : "the leader"
	ppNot := PartyPortWhyNot(L, tp)
	if (ppNot != "")
		{
		;(a reason said once till it changes - those that come and go by the second ("~...") never)
		if (SubStr(ppNot, 1, 1) != "~" && PartyPortNot != ppNot)
			DebugLog("Party: not teleporting to " ppWho " by the game's Group button - " ppNot)
		PartyPortNot := ppNot
		return false
		}
	PartyPortNot := "", PartyPortAt := A_TickCount
	ppZone := V1At(PartyMe, "zone"), ppX := V1At(PartyMe, "x"), ppY := V1At(PartyMe, "y")
	ppWas := PartyTp, ppWasWhy := PartyTpWhy
	PartyTp := "porting", PartyTpWhy := "teleporting by the game's Group button"
	SetStatus("party: lost - teleporting to " ppWho " by the game's Group button")
	DebugLog("Party: lost (" why ") - teleporting to " ppWho " by the game's Group button (Settings: partytp)")
	;(the windows shown before - to tell what the clicks brought up, when it's nothing the bot knows)
	ppBefore := PartyPortShown()
	g := NavGui(PartyPortPaths(), 600)
	if (!IsObject(g))
		return PartyPortFail(L, ppWas, ppWasWhy, "the game's windows can't be read (" NavGuiWhy ")", 60000)
	if (g.box.shown)
		return PartyPortFail(L, ppWas, ppWasWhy, "a game message is up (`"" g.box.caption "`")", 60000)
	if (!V1At(g.win["windowHUD/GroupSystemButton"], "shown"))
		return PartyPortFail(L, ppWas, ppWasWhy, "this wizard isn't in a group in the game (no Group button on the HUD) - invite it to " ppWho "'s group", 120000)
	;(the row open already - Teleport shown: clicked straight away)
	if (!V1At(g.win["GroupButtonLayout/GroupTeleportButton"], "shown"))
		{
		if (!PartyPortClick("windowHUD/GroupSystemButton", &ppWhy))
			return PartyPortFail(L, ppWas, ppWasWhy, "the Group button not clicked: " ppWhy, 60000)
		if (!PartyPortWaitShown("GroupButtonLayout/GroupTeleportButton", 2500))
			return PartyPortFail(L, ppWas, ppWasWhy, "the Group button's row didn't open (no Teleport button 2.5 s after it)" PartyPortNew(ppBefore), 300000)
		}
	if (!PartyPortClick("GroupButtonLayout/GroupTeleportButton", &ppWhy))
		{
		PartyPortCloseRow()
		return PartyPortFail(L, ppWas, ppWasWhy, "the Teleport button not clicked: " ppWhy (ppWhy = "greyed out" ? " - the game won't teleport to the leader from here" : ""), ppWhy = "greyed out" ? 300000 : 60000)
		}
	ppHow := PartyPortWatch(ppZone, ppX, ppY)
	if (ppHow = "")
		return PartyPortFail(L, ppWas, ppWasWhy, "nothing the bot knows happened in 12 s after Teleport" PartyPortNew(ppBefore) " - the windows are left to you", 300000)
	if (SubStr(ppHow, 1, 1) = "!")
		return PartyPortFail(L, ppWas, ppWasWhy, SubStr(ppHow, 2), 300000)
	DebugLog("Party: teleported to " ppWho " by the Group button (" ppHow ") - following again")
	PartyTp := "", PartyTpWhy := "", PartyStuckAt := 0, PartyTries := 0, PartyPortOffUntil := 0
	SetStatus("party: teleported to " ppWho " - following again")
	return true
	}

;Why a lost follower doesn't teleport now ("" it may - PartyGroupPort); a "~" first: one that comes and goes by the second,
;never logged
PartyPortWhyNot(L, tp)
	{
	if (!StatOr("partytp", 1))
		return "Settings: partytp is off"
	if (tp = "wait" && L.port != 1 && PartyDoorGave = "")
		return "~the helper doesn't say a teleport is the way yet (" L.portwhy ")"
	if (L.loading = 1 || L.zone = "")
		return "~the leader is loading"
	if (V1At(PartyMe, "zone") = "")
		return "~this wizard is loading"
	if (dualmode == 1)
		return "dual mode is on (the game's memory is one client's)"
	if (!Stat("navmem"))
		return "navmem:0 in PlayerStats.txt (the Group button is found in the game's memory)"
	if (!VisionOn)
		return "the vision helper isn't running"
	if (inbattle = 1 || !BotNoBattle())
		return "~in a battle (or the spellbook isn't on screen)"
	if (!GameActive())
		return "~Wizard101 isn't the window in front"
	if (PlayerActing())
		return "~you're playing"
	if (QsBusy)
		return "~quick selling"
	if (PartyPortAt && A_TickCount - PartyPortAt < 60000)
		return "~tried under a minute ago"
	if (PartyPortOffUntil && A_TickCount < PartyPortOffUntil && PartyPortOffZone = L.zone)
		return "~the last try didn't work - tried again in " (PartyPortOffUntil - A_TickCount) // 1000 " s (or once the leader's in another zone)"
	return ""
	}

;The Group button's windows by the game's memory (paths for NavGui)
PartyPortPaths()
	{
	return "windowHUD/GroupSystemButton,GroupSystemButton/GroupButtonLayout,GroupButtonLayout/GroupTeleportButton"
	}

;A try that didn't work: said (once till it changes), the leader's view put back as it was (it's told it can't follow
;again), not tried again for ms - or till the leader's in another zone. False (PartyGroupPort's answer)
PartyPortFail(L, was, wasWhy, why, ms)
	{
	global PartyTp, PartyTpWhy, PartyPortOffUntil, PartyPortOffZone, PartyPortNot ; (globals it sets)
	PartyTp := was, PartyTpWhy := wasWhy
	PartyPortOffUntil := A_TickCount + ms, PartyPortOffZone := L.zone
	if (PartyPortNot != why)
		DebugLog("Party: the teleport by the game's Group button didn't work - " why " (tried again in " ms // 60000 " min, or once the leader's in another zone)")
	PartyPortNot := why
	return false
	}

;A window the Group button's clicks may click, and its size in the game's .gui files (GUI units - the HUD's as read
;2026-11-08 at UI size 0.856, root 1827x1027), or ""
PartyPortTargetSize(path)
	{
	return path = "windowHUD/GroupSystemButton" ? [39, 39] : path = "GroupButtonLayout/GroupTeleportButton" ? [31, 31] : ""
	}

;A window fine to click (pure): one of the two, found and shown once, inside the root, its .gui size (3 units either way),
;not greyed. why: what's wrong
PartyPortTargetOk(path, w, rootW, rootH, &why)
	{
	why := ""
	ptSize := PartyPortTargetSize(path)
	if (!IsObject(ptSize))
		why := "not one the party's teleport clicks"
	else if (!IsObject(w) || !w.found)
		why := "not found in the game's windows"
	else if (!w.shown)
		why := "not shown"
	else if (w.dups != 1)
		why := "shown " w.dups " times - which one?"
	else if (w.l = "" || w.r = "" || w.t = "" || w.b = "" || w.r <= w.l || w.b <= w.t)
		why := "its rect is odd (" w.l "," w.t "," w.r "," w.b ")"
	else if (w.l < 0 || w.t < 0 || w.r > rootW || w.b > rootH)
		why := "off the game (" w.l "," w.t "," w.r "," w.b " in " rootW "x" rootH ")"
	else if (Abs(w.r - w.l - ptSize[1]) > 3 || Abs(w.b - w.t - ptSize[2]) > 3)
		why := "its size " w.r - w.l "x" w.b - w.t " isn't the game file's " ptSize[1] "x" ptSize[2]
	else if (w.greyed = 1)
		why := "greyed out"
	return why = ""
	}

;A click on one of the Group button's windows by the game's memory: read now, fine to click (PartyPortTargetOk), turned into
;pixels (QuickSell.ahk QsPx, QsJitter, QsPxOk - not the Crown shop's corner, not the right-hand column), no "Crown" read
;round it, you not playing - then the mouse onto it, a moment, and the click AT it while it's still there (PartyPortClickAt).
;why: what stopped it
PartyPortClick(path, &why)
	{
	why := ""
	g := NavGui(path, 600)
	if (!IsObject(g))
		{
		why := "the game's windows can't be read (" NavGuiWhy ")"
		return false
		}
	if (g.box.shown)
		{
		why := "a game message is up (`"" g.box.caption "`")"
		return false
		}
	w := g.win[path]
	if (!PartyPortTargetOk(path, w, g.rootW, g.rootH, &why))
		return false
	QsPx(w.l, w.t, w.r, w.b, g.rootW, g.rootH, &pcX, &pcY)
	QsJitter(w.l, w.t, w.r, w.b, g.rootW, g.rootH, &pcX, &pcY)
	if (!QsPxOk(pcX, pcY, &why))
		return false
	pcR := Round(Max(w.r - w.l, w.b - w.t) * GameW / g.rootW / 2) + 40
	if (!NoCrownsNear(pcX, pcY, pcR, "Party", "The party's teleport", "by the Group button", "it only teleports to the leader", "party teleport stopped"))
		{
		why := "`"Crown`" read round it (or the screen there couldn't be read)"
		return false
		}
	if (PlayerActing())
		{
		why := "you're playing"
		return false
		}
	if (!PartyPortClickAt(pcX, pcY, &why))
		return false
	DebugLog("Party: clicked " path " at " pcX - GameLeft "," pcY - GameTop)
	return true
	}

;The mouse onto x, y and a moment on it, then - no key or mouse of yours meanwhile, the mouse still on it - the click AT x, y,
;your mouse locked for it. why: what stopped it
PartyPortClickAt(x, y, &why)
	{
	why := ""
	pcaFrom := A_TickCount
	MouseLockOn("teleporting to the party's leader")
	MouseMove(x, y, MouseSpeedNow())
	MouseLockMoved()
	Sleep(V1N(V1Max(150, Stats.Has("clickwait") ? Stats["clickwait"] : 40)))
	MouseGetPos(&pcaX, &pcaY)
	if (A_TickCount - UserIdle() > pcaFrom)
		why := "you touched the mouse or keyboard"
	else if (Abs(pcaX - x) > 2 || Abs(pcaY - y) > 2)
		why := "the mouse moved off it before the click"
	if (why = "")
		Click(x, y)
	MouseLockOff("teleporting to the party's leader")
	return why = ""
	}

;Waits up to ms for the window at path to be shown (the game's memory, every 150 ms)
PartyPortWaitShown(path, ms)
	{
	pwT := A_TickCount
	Loop
		{
		g := NavGui(path, 600)
		if (IsObject(g) && V1At(g.win[path], "shown"))
			return true
		if (A_TickCount - pwT > ms)
			return false
		Sleep(150)
		}
	}

;The Group button's row closed again (its button clicked once more) when it's still open - nothing else
PartyPortCloseRow()
	{
	g := NavGui(PartyPortPaths(), 600)
	if (IsObject(g) && !g.box.shown && V1At(g.win["GroupButtonLayout/GroupTeleportButton"], "shown"))
		PartyPortClick("windowHUD/GroupSystemButton", &pcrWhy)
	}

;After Teleport, up to 12 s: how it went - "loading" (this wizard's zone not read: a loading screen), "to <zone>", "moved
;<n> units" (400 or more: a teleport in the same zone); a message box answered (PartyPortBox): a yes waits on (12 s more,
;once), any other answer "!<why>"; "" nothing the bot knows came of it
PartyPortWatch(zone, x, y)
	{
	pwEnd := A_TickCount + 12000, pwYes := 0
	Loop
		{
		Sleep(250)
		pwZ := V1At(PartyMe, "zone")
		if (pwZ = "")
			return "loading"
		if (pwZ != zone)
			return "to " pwZ
		pwX := V1At(PartyMe, "x"), pwY := V1At(PartyMe, "y")
		if (V1IsNum(pwX) && V1IsNum(pwY) && V1IsNum(x) && V1IsNum(y) && Sqrt((pwX - x) ** 2 + (pwY - y) ** 2) >= 400)
			return "moved " Round(Sqrt((pwX - x) ** 2 + (pwY - y) ** 2)) " units"
		g := NavGui("GroupButtonLayout/GroupTeleportButton", 600)
		if (IsObject(g) && g.box.shown)
			{
			pwA := PartyPortBox(g)
			if (pwA != "yes")
				return "!" pwA
			if (!pwYes)
				pwYes := 1, pwEnd := A_TickCount + 12000
			}
		if (A_TickCount > pwEnd)
			return ""
		}
	}

;A message box after Teleport (one up, its words logged): a question about teleporting (Yes and No, the word teleport, no
;Crown) - Yes ("yes"); any other question - No; a box with only an OK - OK (the game said no: its words); a Crown in it -
;nothing clicked. Each button by its label (Yes / No / OK, its word read off the screen too - QuickSell.ahk QsReadWord), the
;game file's size, no "Crown" read round it. The answer: "yes", else why it stopped
PartyPortBox(g)
	{
	pbText := Trim(g.box.title " " g.box.caption)
	DebugLog("Party: a game message after Teleport: `"" SubStr(RegExReplace(pbText, "\s+", " "), 1, 160) "`"")
	if (RegExMatch(pbText, "i)cr[o0]wn"))
		{
		if (V1IsFunc("AlertSend"))
			AlertSend.Call("crowns", "party teleport stopped", "A message about Crowns came up after the Group button's Teleport - nothing clicked: `"" SubStr(pbText, 1, 120) "`"")
		return "a message about Crowns came up (`"" SubStr(pbText, 1, 80) "`") - nothing clicked, it's left to you"
		}
	if (g.box["count"] != 1)
		return (g.box["count"] = "" ? "how many message boxes are up couldn't be read" : g.box["count"] " message boxes are up") " - none clicked"
	pbYes := PartyPortBtn(g.btns, "Yes"), pbNo := PartyPortBtn(g.btns, "No"), pbOk := PartyPortBtn(g.btns, "OK")
	if (IsObject(pbYes) && IsObject(pbNo))
		{
		if (RegExMatch(pbText, "i)teleport|port to|travel"))
			return PartyPortBoxClick(g, pbYes, "Yes", &pbWhy) ? "yes" : "its Yes not clicked: " pbWhy
		return PartyPortBoxClick(g, pbNo, "No", &pbWhy) ? "a question it doesn't know (`"" SubStr(pbText, 1, 80) "`") - answered No" : "a question it doesn't know - its No not clicked: " pbWhy
		}
	if (IsObject(pbOk) && g.btns.Length = 1)
		return "the game said no: `"" SubStr(pbText, 1, 100) "`"" (PartyPortBoxClick(g, pbOk, "OK", &pbWhy) ? " (OK clicked)" : " - its OK not clicked: " pbWhy)
	return "a message with buttons it doesn't know (`"" SubStr(pbText, 1, 80) "`") - nothing clicked"
	}

;The one button labelled label in a box's buttons, or "" (none, or more than one)
PartyPortBtn(btns, label)
	{
	pbB := "", pbN := 0
	for pbI, pbX in btns
		if (Trim(pbX.label) = label)
			pbB := pbX, pbN += 1
	return pbN = 1 ? pbB : ""
	}

;A box's button clicked: the game file's size (128x32, 2 either way), not greyed, on the game, its word read off the screen,
;no "Crown" read round it, you not playing. why: what stopped it
PartyPortBoxClick(g, b, say, &why)
	{
	why := ""
	if (V1Gt(V1Abs(V1Sub(V1Sub(b.r, b.l), 128)), 2) || V1Gt(V1Abs(V1Sub(V1Sub(b.b, b.t), 32)), 2) || b.greyed = 1)
		why := "it isn't as the game's file has it (" V1Sub(b.r, b.l) "x" V1Sub(b.b, b.t) (b.greyed = 1 ? ", greyed" : "") ")"
	else if (V1Lt(b.l, 0) || V1Lt(b.t, 0) || V1Gt(b.r, g.rootW) || V1Gt(b.b, g.rootH))
		why := "it's off the game"
	if (why != "")
		return false
	QsPx(b.l, b.t, b.r, b.b, g.rootW, g.rootH, &pbX, &pbY)
	if (!QsPxOk(pbX, pbY, &why))
		return false
	if (!QsReadWord(b.l, b.t, b.r, b.b, g, say))
		{
		why := "it doesn't read `"" say "`" on screen"
		return false
		}
	pbR := V1Round(V1Div(V1Div(V1Mul(V1Max(V1Sub(b.r, b.l), V1Sub(b.b, b.t)), GameW), g.rootW), 2)) + 40
	if (!NoCrownsNear(pbX, pbY, pbR, "Party", "The party's teleport", "by the game's message", "it only teleports to the leader", "party teleport stopped"))
		{
		why := "`"Crown`" read round it (or the screen there couldn't be read)"
		return false
		}
	if (PlayerActing())
		{
		why := "you're playing"
		return false
		}
	if (!PartyPortClickAt(pbX, pbY, &why))
		return false
	DebugLog("Party: clicked the message's " say " at " pbX - GameLeft "," pbY - GameTop)
	return true
	}

;The windows shown now, two levels down from the game's GUI root ({name: 1}), or "" when they can't be read (NavGuiTree)
PartyPortShown()
	{
	t := NavGuiTree("", false, 2, 1500)
	if (!IsObject(t))
		return ""
	psOut := V1Obj()
	for psI, psR in t.rows
		if (psR.name != "" && psR.shown)
			psOut[psR.name] := 1
	return psOut
	}

;" - new windows: A, B" (shown now, not before - before: PartyPortShown's), " - no new windows", or "" when it can't be told
PartyPortNew(before)
	{
	if (!IsObject(before))
		return ""
	now := PartyPortShown()
	if (!IsObject(now))
		return ""
	pnList := ""
	for pnK in now
		if (!before.Has(pnK))
			pnList .= (pnList = "" ? "" : ", ") pnK
	return pnList = "" ? " - no new windows" : " - new windows: " SubStr(pnList, 1, 200)
	}

;Standing by the leader (PartyFollowStep - Settings: partyride, on; untried in the game): the prompt at the bottom of the
;game read every 1.5 s (the walker's InteractPrompt), and one to ride the leader's mount (PartyRidePrompt) gets an X - at
;most once in 5 s: the mount takes its passenger again after a zone change, a battle, a dismount. Any other prompt by the
;leader is logged once (its words - what a ride prompt really says, should it be none of those) and left alone
PartyRideCheck(L)
	{
	global PartyRideAt, PartyRideLook, PartyRideSaid ; (globals it sets)
	global WkPromptText, WkPromptVerb, WkPromptDest ; (InteractPrompt's)
	if (!StatOr("partyride", 1) || !GameActive() || PlayerActing() || inbattle = 1)
		return
	if (PartyRideLook && A_TickCount - PartyRideLook < 1500)
		return
	PartyRideLook := A_TickCount
	if (InteractPrompt() != "press")
		return
	prWho := L.wiz != "" ? L.wiz : L.name != "" ? L.name : "the leader"
	prText := SubStr(RegExReplace(WkPromptText, "\s+", " "), 1, 100)
	if (PartyRidePrompt(WkPromptText, WkPromptVerb, L.wiz))
		{
		if (PartyRideAt && A_TickCount - PartyRideAt < 5000)
			return
		PartyRideAt := A_TickCount
		DebugLog("Party: pressed X to ride " prWho "'s mount - the prompt: `"" prText "`" (Settings: partyride)")
		PressKey("x")
		return
		}
	if (!IsObject(PartyRideSaid))
		PartyRideSaid := V1Obj()
	if (!PartyRideSaid.Has(WkPromptDest))
		{
		PartyRideSaid[WkPromptDest] := 1
		DebugLog("Party: a prompt by " prWho ": `"" prText "`" (Press X to " WkPromptVerb ") - not one to ride its mount: no X")
		}
	}

;A prompt's words one to ride the leader's mount (pure): its verb ride, mount, board, join or hop ("Press X to Ride"); the
;words mount, ride, riding or passenger; or the leader's wizard's name in it (its letters, 4 or more)
PartyRidePrompt(text, verb, wiz)
	{
	if (RegExMatch(verb, "i)^(ride|mount|board|join|hop)"))
		return true
	if (RegExMatch(text, "i)\b(mount|ride|riding|passenger)\b"))
		return true
	prK := PartyKey(wiz)
	return StrLen(prK) >= 4 && InStr(PartyKey(text), prK) > 0
	}

;The way to p ({x, y, z}) by the helper's route (/navto: round walls - and mobs, avoid); {x, y, z, yaw, ax, ay, left, why,
;zone} or ""
PartyNavTo(p, avoid)
	{
	;(v1: Round of a blank - a place the helper didn't give - 0.0)
	answer := VisionGet("/navto?x=" Round(V1N(p.x), 1) "&y=" Round(V1N(p.y), 1) "&z=" Round(V1N(p.z), 1) (avoid ? NavMobArgs() : ""), 2500, true)
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

;Tray menu "Party...": the party window - this wizard's name in the party, its part (Off / Leader / Follower: the
;Settings window's PARTY setting partyrole - the same one), the leader PC's address (a follower's; this PC's own shown,
;to type on the others) and its part in a party battle (partybattle). OK: the name and the address kept in party.ini,
;the settings written as the Settings window's Save writes them (PlayerStats.txt, read again at once - the party link
;takes them on its next tick). Open already: brought to the front. (v2: the two InputBoxes this was opened out of
;sight, behind the game - a window as the Settings one, always on top)
;(v1.2.1: Party... still did nothing on two PCs and nothing said why - every step is logged now: "Party: opening the
;party window (where the mouse is...)", "... made ... shown at", "... opened - hwnd, place, monitor, visible, always on
;top, active", an error MenuParty's; and the window comes up in the middle of the monitor the mouse is on - where the
;tray icon was just clicked -, always on top again, activated, with a tray tip)
PartySetup()
	{
	;(the window, and its hwnd: one at a time - the object kept, a window without one would be gone)
	static pwWin := "", pwHwnd := 0
	DebugLog("Party: opening the party window (" PartyWinWhere() ")")
	if (pwHwnd && GuiFromHwnd(pwHwnd) && WinExist("ahk_id " pwHwnd))
		{
		PartyWinFront(pwHwnd, "was open already - brought to the front", true)
		return
		}
	;(the name: party.ini's, else the wizard's in-game name if the bot knows it, else this PC's)
	pwName := PartyIni("name"), pwLeader := PartyIni("leader")
	if (pwName = "")
		pwName := OwnName()
	if (pwName = "")
		pwName := A_ComputerName
	;(the two settings as the Settings window shows them - PlayerStats.txt's value, else the default - with its words;
	;a school's own value is used when it fights as that school: said where it is, as the Settings window's help does)
	pwShown := V1Obj(), pwPicks := V1Obj(), pwOwn := ""
	for each, pwS in CfgList()
		if (pwS.key = "partyrole" || pwS.key = "partybattle")
			{
			pwV := (IsObject(Stats) && Stats.Has(pwS.key)) ? Stats[pwS.key] : pwS.def
			pwShown[pwS.key] := Max(1, Min(pwS.picks.Length, Round(pwV))), pwPicks[pwS.key] := pwS.picks
			for each, pwSch in ["storm", "fire", "ice", "life", "death", "myth", "balance"]
				if (IsObject(Stats) && Stats.Has(pwSch "." pwS.key))
					pwOwn .= " Your " pwSch " wizard has its own: " pwSch "." pwS.key ":" Stats[pwSch "." pwS.key] " in PlayerStats.txt (change it there)."
			}
	pwWin := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "Wizard101 bot " BotVersion() " - party"), pwHwnd := pwWin.Hwnd
	pwWin.OnEvent("Close", PartyWinClose)
	pwWin.OnEvent("Escape", PartyWinClose)
	;(the Settings window's colours: 111317 behind each Edit and DropDownList)
	pwWin.BackColor := "1B1D22"
	pwWin.MarginX := 12, pwWin.MarginY := 10
	pwWin.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	pwWin.Add("Text", "x12 y12 w480 h18", "PARTY - up to 4 wizards, one on each PC of your home network")
	pwWin.SetFont("s9 w400 cDADADA", "Segoe UI")
	pwWin.Add("Text", "x12 y+12 w170 h18", "This wizard's name in the party")
	pwWin.Add("Edit", "x190 yp-3 w302 h22 Background111317 vPartyWinName", pwName)
	pwWin.Add("Text", "x12 y+10 w170 h18", "This wizard in the party")
	pwWin.Add("DropDownList", "x190 yp-3 w302 AltSubmit Background111317 vPartyWinRole Choose" pwShown["partyrole"], pwPicks["partyrole"]).OnEvent("Change", PartyWinRoleChange)
	pwWin.Add("Text", "x12 y+10 w170 h18", "The leader PC's address")
	pwWin.Add("Edit", "x190 yp-3 w302 h22 Background111317 vPartyWinLeader" (pwShown["partyrole"] = 3 ? "" : " Disabled"), pwLeader)
	pwWin.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	pwWin.Add("Text", "x190 y+4 w302 vPartyWinIP", "Followers only: the leader PC's name or IP. This PC's address: " PartyMyAddresses() " (its name: " A_ComputerName ")")
	pwWin.SetFont("s9 w400 cDADADA", "Segoe UI")
	pwWin.Add("Text", "x12 y+10 w170 h18", "In a party battle it's the")
	pwWin.Add("DropDownList", "x190 yp-3 w302 AltSubmit Background111317 vPartyWinBattle Choose" pwShown["partybattle"], pwPicks["partybattle"])
	pwWin.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	pwWin.Add("Text", "x12 y+12 w480 vPartyWinHelp", "Its part and its battle part are the Settings window's (PARTY) - the same settings. OK keeps the name and the address in party.ini and the settings in PlayerStats.txt: used at once." pwOwn)
	pwWin.SetFont("s9 w400 c000000", "Segoe UI")
	pwWin.Add("Button", "x12 y+10 w90 h26 Default", "OK").OnEvent("Click", PartyWinOk.Bind(pwShown))
	pwWin.Add("Button", "x+8 yp w90 h26", "Cancel").OnEvent("Click", PartyWinCancel)
	pwWin.SetFont("s9 w400 cB9E2B9", "Segoe UI")
	pwWin.Add("Text", "x+14 yp+5 w280 h18 vPartyWinNote")
	;(v1.2.1: in the middle of the monitor the mouse is on - where the tray icon was just clicked -, all of it on that
	;monitor's work area. It opened next to the dashboard before (as the Settings window does), on the dashboard's
	;monitor - another one than the game's or the tray's on a PC with two. Laid out hidden first: its size is known
	;before it's placed, and it shows once, there)
	pwWin.Show("Hide AutoSize")
	PartyMouseMonitor(&pwMon, &pwML, &pwMT, &pwMR, &pwMB)
	PartyWinRect(pwHwnd, &pwWx, &pwWy, &pwWw, &pwWh)
	pwX := pwML + Max(0, (pwMR - pwML - pwWw) // 2), pwY := pwMT + Max(0, (pwMB - pwMT - pwWh) // 2)
	DebugLog("Party: the party window made (hwnd " Format("0x{:X}", pwHwnd) ", " pwWw "x" pwWh ") - shown at " pwX "," pwY ", the middle of monitor " pwMon)
	pwWin.Show("x" pwX " y" pwY)
	PartyWinFront(pwHwnd, "opened", false)
	}

;The party window brought up (v1.2.1): restored when it's minimised; an open one (move) moved to the middle of the
;monitor the mouse is on when it isn't on that one; always on top set again (that puts it first among the always-on-top
;windows too) and activated - then how it is logged (PartyWinState) and said in a tray tip
PartyWinFront(hwnd, what, move)
	{
	;(v1: WinGet MinMax of a window not found gave a blank - v2 throws)
	if (V1Try(WinGetMinMax, "ahk_id " hwnd) = -1)
		try WinRestore("ahk_id " hwnd)
	if (move)
		{
		PartyMouseMonitor(&pfMon, &pfML, &pfMT, &pfMR, &pfMB)
		PartyWinRect(hwnd, &pfX, &pfY, &pfW, &pfH)
		pfCx := pfX + pfW // 2, pfCy := pfY + pfH // 2
		if !(pfCx >= pfML && pfCx < pfMR && pfCy >= pfMT && pfCy < pfMB)
			try WinMove(pfML + Max(0, (pfMR - pfML - pfW) // 2), pfMT + Max(0, (pfMB - pfMT - pfH) // 2), , , "ahk_id " hwnd)  ; (v1: WinMove on a window gone did nothing)
		}
	try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
	;(in front, with the keyboard)
	try WinActivate("ahk_id " hwnd)
	DebugLog("Party: the party window " what " - " PartyWinState(hwnd))
	TrayTip(move ? "The party window was open already - it's in front now." : "The party window is open - in the middle of the screen the mouse is on.", "Wizard101 bot", 1)
	}

;Party... couldn't open the window (MenuParty caught it): why, logged and said in a tray tip - not the error's box,
;which could open out of sight behind the game as the InputBoxes did (v1.2.1)
PartyWinFailed(e)
	{
	;(an object's Type when nothing better can be said - this mustn't throw in its turn. Braces: v2's try takes an else
	;of its own)
	pxWhy := Type(e)
	if (e is Error)
		{
		try pxWhy := e.Message (e.Extra != "" ? " (" e.Extra ")" : "") " - " e.What " at line " e.Line
		}
	else
		{
		try pxWhy := String(e)
		}
	DebugLog("Party: the party window couldn't open - " pxWhy)
	TrayTip("The party window couldn't open: " pxWhy " (debug.log has it too)", "Wizard101 bot", 2)
	}

;Where things are as Party... is picked, for the log: the mouse (on which monitor, of how many), the dashboard, and
;the window in front
PartyWinWhere()
	{
	PartyMouseAt(&pwhX, &pwhY)
	pwhMon := PartyMonitorOf(pwhX, pwhY), pwhCount := "?", pwhFront := "?"
	try pwhCount := MonitorGetCount()
	try pwhFront := WinGetClass("A") " of " WinGetProcessName("A")
	return "the mouse at " pwhX "," pwhY " on monitor " (pwhMon ? pwhMon : "none") " of " pwhCount
		. ", the dashboard " (DashHwnd ? (DashShown ? "shown" : "hidden") : "not made") ", in front: " pwhFront
	}

;How the party window is now, for the log: its handle, its place and size, the monitor its middle is on (of how many,
;and that one's work area), visible, always on top, active - and the window in front when it isn't
PartyWinState(hwnd)
	{
	PartyWinRect(hwnd, &psX, &psY, &psW, &psH)
	psMon := PartyMonitorOf(psX + psW // 2, psY + psH // 2), psOn := "on no monitor"
	if (psMon)
		{
		try
			{
			MonitorGetWorkArea(psMon, &psL, &psT, &psR, &psB)
			psOn := "on monitor " psMon " of " MonitorGetCount() " (its work area " psL "," psT " to " psR "," psB ")"
			}
		}
	psFg := DllCall("GetForegroundWindow", "Ptr"), psFront := ""
	if (psFg != hwnd)
		{
		psFront := "?"
		try psFront := WinGetClass("ahk_id " psFg) " of " WinGetProcessName("ahk_id " psFg)
		psFront := ", in front: " psFront
		}
	return "hwnd " Format("0x{:X}", hwnd) ", at " psX "," psY " " psW "x" psH " " psOn
		. ", visible " (DllCall("IsWindowVisible", "Ptr", hwnd) ? 1 : 0)
		. ", always on top " ((DllCall("GetWindowLong", "Ptr", hwnd, "Int", -20, "Int") & 0x8) ? 1 : 0)
		. ", active " (psFg = hwnd ? 1 : 0) psFront
	}

;A window's place and size on the screen, in pixels (GetWindowRect: shown or not - WinGetPos can't see a hidden one)
PartyWinRect(hwnd, &x, &y, &w, &h)
	{
	prRc := Buffer(16, 0)
	DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", prRc)
	x := NumGet(prRc, 0, "Int"), y := NumGet(prRc, 4, "Int")
	w := NumGet(prRc, 8, "Int") - x, h := NumGet(prRc, 12, "Int") - y
	}

;The mouse on the screen (GetCursorPos - no CoordMode; it fails while the desktop is locked: the main monitor's middle)
PartyMouseAt(&x, &y)
	{
	pmPt := Buffer(8, 0)
	if (DllCall("GetCursorPos", "Ptr", pmPt))
		x := NumGet(pmPt, 0, "Int"), y := NumGet(pmPt, 4, "Int")
	else
		x := A_ScreenWidth // 2, y := A_ScreenHeight // 2
	}

;The monitor whose whole area holds x, y (the taskbar's part too - the tray icon is on it, outside the work area); 0 none
PartyMonitorOf(x, y)
	{
	try
		{
		Loop MonitorGetCount()
			{
			MonitorGet(A_Index, &pmL, &pmT, &pmR, &pmB)
			if (x >= pmL && x < pmR && y >= pmT && y < pmB)
				return A_Index
			}
		}
	return 0
	}

;The monitor the mouse is on (its number - the main one when it's on none) and its work area (the taskbar left out)
PartyMouseMonitor(&mon, &mLeft, &mTop, &mRight, &mBottom)
	{
	PartyMouseAt(&pmX, &pmY)
	mon := PartyMonitorOf(pmX, pmY)
	if (!mon)
		{
		try mon := MonitorGetPrimary()
		catch
			mon := 1
		}
	try MonitorGetWorkArea(mon, &mLeft, &mTop, &mRight, &mBottom)
	catch
		mLeft := 0, mTop := 0, mRight := A_ScreenWidth, mBottom := A_ScreenHeight
	}

;This PC's addresses on the home network - its IPv4s, not the loopback or a link-local (169.254) one: "a, b"
PartyMyAddresses()
	{
	pwOut := ""
	try pwAll := SysGetIPAddresses()
	catch
		pwAll := []
	for each, pwA in pwAll
		if !(InStr(pwA, "127.") = 1 || InStr(pwA, "169.254.") = 1 || pwA = "0.0.0.0")
			pwOut .= (pwOut = "" ? "" : ", ") pwA
	return pwOut = "" ? "none found (is the network connected?)" : pwOut
	}

;The party window's part changed: the leader's address is a follower's only
PartyWinRoleChange(pwCtl, *)
	{
	pwCtl.Gui["PartyWinLeader"].Enabled := (pwCtl.Value = 3)
	}

;The party window's OK: the name and the leader's address (cleaned as ever) to party.ini, the settings changed to
;PlayerStats.txt as the Settings window's Save writes them (CfgWrite - read again at once), the Settings window, open
;too, showing them. Closed then - not when PlayerStats.txt couldn't be written (nothing saved). pwShown: the settings'
;values as the window opened ({partyrole, partybattle})
PartyWinOk(pwShown, pwCtl, *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(not halfway through while the bot writes PlayerStats.txt itself: as the Settings window's Save)
	Critical()
	pwG := pwCtl.Gui
	pwName := RegExReplace(Trim(pwG["PartyWinName"].Value), "[^\w .'-]")
	pwLeader := RegExReplace(Trim(pwG["PartyWinLeader"].Value), "[^\w.-]")
	pwRole := pwG["PartyWinRole"].Value, pwBattle := pwG["PartyWinBattle"].Value
	;(only what was changed here, as Save writes only what was changed there: one changed in Settings meanwhile stays)
	pwPairs := [], pwSaid := ""
	for each, pwKv in [["partyrole", pwRole], ["partybattle", pwBattle]]
		if (pwKv[2] != pwShown[pwKv[1]])
			pwPairs.Push(pwKv), pwSaid .= ", " pwKv[1] " " pwShown[pwKv[1]] " -> " pwKv[2]
	if (pwPairs.Length && !CfgWrite(pwPairs))
		{
		pwG["PartyWinNote"].Value := "Couldn't write PlayerStats.txt - nothing was saved"
		DebugLog("Party: couldn't write PlayerStats.txt - nothing was saved")
		return
		}
	V1Do(IniWrite, pwName, A_ScriptDir "\party.ini", "party", "name")
	V1Do(IniWrite, pwLeader, A_ScriptDir "\party.ini", "party", "leader")
	;(the Settings window open too: it shows what's saved now - its Save won't take it back)
	if (CfgHwnd && WinExist("ahk_id " CfgHwnd) && IsObject(CfgCtls) && IsObject(CfgShownVals))
		for each, pwKv in pwPairs
			if (CfgCtls.Has(pwKv[1]))
				GuiCtrlFromHwnd(CfgCtls[pwKv[1]]).Choose(pwKv[2]), CfgShownVals[pwKv[1]] := pwKv[2]
	;(the role and the battle part in use now - as PartyRoleSet / PartyBattleSet read them; one not changed here may have
	;been changed in Settings meanwhile)
	pwRole := (IsObject(Stats) && Stats.Has("partyrole")) ? Stats["partyrole"] : pwRole
	pwBattle := (IsObject(Stats) && Stats.Has("partybattle")) ? Stats["partybattle"] : pwBattle
	DebugLog("Party: saved - name '" pwName "', role " (pwRole = 2 ? "leader" : pwRole = 3 ? "follower" : "off") ", leader '" pwLeader "'"
		. ", in battle the " (pwBattle = 2 ? "blader" : pwBattle = 3 ? "healer" : "hitter") (pwSaid = "" ? "" : " (PlayerStats.txt: " SubStr(pwSaid, 3) ")"))
	pwG.Destroy()
	}

;The party window's Cancel: closed, nothing saved
PartyWinCancel(pwCtl, *)
	{
	pwCtl.Gui.Destroy()
	}

;The party window's X or Esc: closed, nothing saved
PartyWinClose(pwWin, *)
	{
	pwWin.Destroy()
	}

;(v1: the label PartyTimer: - Autofarmer.ahk's SetTimer, PartyTimer, 500; it ran in the global scope)
PartyTimer() {
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
PartyTick()
return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
PartyBlank()
	{
	global PartyRole := "", PartyState := "", PartyWhy := "", PartyMe := "", PartyLeader := "", PartyMembers := "", PartyAskAt := ""
	global PartyHolding := "", PartyHeldFrom := "", PartySkip := "", PartyTgt := "", PartyStillAt := "", PartyStillX := "", PartyStillY := ""
	global PartyTries := "", PartyPushUntil := "", PartyNear := "", DualBattle := "", Manual := "", SidePlates := "", PartyFlagDuel := ""
	global BlDuel := "", PartyFlagRound := "", used := "", BoostSrcUsed := "", BlRound := "", PartyHitsDuel := "", BlCasts := "", MySlot := ""
	global PartySrcRound := "", roundnumber := "", PartyLowKey := "", PartyLowName := "", PartyLowPct := "", OwnHpRound := "", playerX := ""
	global OwnHpPct := "", OwnHpVotes := "", Stats := "", hitschool := "", PartyLowX := "", PartyLowY := "", tower := "", used19 := ""
	global BattleRole := "", hammerX := "", hammerY := "", HammerName := ""
	global PartyTp := "", PartyTpWhy := "", PartyCantAt := "", PartyCantSaid := "", PartyPortSaid := "", PartyCantAlerted := ""
	global PartyDoorKey := "", PartyDoorTries := "", PartyDoorGave := "", PartyMyZone := "", PartyLdZone := "", PartyStuckAt := ""
	global PartyDoorGaveAt := "", PartyDoorBattles := "", PartyDwalkSaid := "", PartyHitAt := "", PartyHitAtDuel := ""
	global PartyOrderAsked := "", PartyOrderMiss := "", PartyOrderSaid := ""
	global PartyPortAt := "", PartyPortNot := "", PartyPortOffUntil := "", PartyPortOffZone := "", PartyRideAt := "", PartyRideLook := ""
	global PartyRideSaid := ""
	}
