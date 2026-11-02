; BattleRec.ahk - the battle recorder's AutoHotkey side (TODO goal 3, the first step of learned battle play): for each
; battle round the bot looks at, its own reasons - every debug.log line of the round, verbatim - and its state go to the
; vision helper once the round's clicks are over; the helper (vision\battlerec.py) joins them with the game's own log
; and memory into one record per battle in learned\battles\ (the record's format: vision\battlerec.py's docstring).
; AutoHotkey v2, written for v2 (v1 never had this: nothing here is ported); #Included by Autofarmer.ahk only. Its hooks
; there are one call each; in a function that isn't assume-global (DebugLog, PlayerActing, BotToggle) and in the other
; files (Settings.ahk CfgSaveNow, Dashboard.ahk DashRefresh) by V1IsFunc + .Call, so a test copying one of them without
; this file runs it as before.
;
; It never slows a round: nothing here waits for anything. A line is one push onto an array (BrecNote, from DebugLog);
; a round's post goes out when the battle loop's next look for a round starts - after the round's last click, the mouse
; already unlocked - and without waiting for an answer (WinHttp asynchronous: Open(.., true), Send; at most 4 in flight,
; one more is dropped, never retried); nothing here reads the game, its log or its memory, and nothing costly runs in a
; round (Settings saved in a round: its hello waits for the round's end). It never changes how the bot plays: it only
; copies what the bot already has - no global of the bot's is ever set - and every function is wrapped in try: an error
; is logged once and the recorder stops (BrecFail) - the battles are played on as ever.
; Nothing typed goes out: the settings are a fixed list of numbers (BrecSetKeys), your wizard's name is the game's (the
; log's - never party.ini's typed [party] name), a deck's typed name isn't sent, a line with "http", "webhook", "token",
; "password" or "login" in it is left out and the names typed for decks and the party are cut out of the lines.
;
; Setting (PlayerStats.txt, the Settings window's HOW IT PLAYS ITS CARDS): battlerec - on unless 0 (a missing key: on).
; Off: no buffer, no post at all (a helper told "on" earlier in the run is told "off" once).
;
; What goes to the helper: POST http://127.0.0.1:<VisionPort>/rec?ev=<event>..., Content-Type text/plain; charset=us-ascii,
; ASCII only. The body: key<TAB>value lines (each value BrecEsc'd); a round's then one  L<TAB><ms><TAB><line>  per line
; (ms since the round opened; the line BrecEsc'd: \ -> \\, tab -> \t, LF -> \n, CR dropped, anything outside
; printable ASCII -> \uXXXX - UTF-16 code units). A key the helper doesn't know is skipped by it.
;   ev=hello            at the start (StartBot, after VisionStart) and after Settings are saved: on, log (the game's
;                       WizardClient.log), ver, navmem, dual, bot, acting, pfm, tk + the state below
;   ev=state&why=end    out of battle after each battle (the stats and the deck as they were): the same keys
;   ev=who&bot=&acting=&pfm=&tk=   (no body) a takeover by you or its end (PlayerActing), F6 (BotToggle), Play for me;
;                       one seen in a round the bot's playing is sent at the round's close, before its round post (tk:
;                       when it was seen)
;   ev=round            each round the bot looked at: duel (BlDuel), round (BlRound+1: the record's blround), botround (roundnumber),
;                       open, close (ticks: A_TickCount = GetTickCount64, the helper's clock), again (the round left to
;                       you, still up), bot, acting, took, left, pfm, role (BattleRole), hitschool, drop (lines over the
;                       cap), lost (a buffer opened over another), prole (Settings' partyrole: off/leader/follower),
;                       brole (partybattle: hitter/blader/healer), myslot (your plate's slot on your side), hslot /
;                       hschool (the hitter's - a party battle's support), pips (PipsNow), + the state on a duel's first
;                       round post; then the L lines - a cast that went out is the line "@cast <title>" (BrecCast)
;   the state:          char (CharID), school, name (the game's name of your wizard), stat.school, stat.damage,
;                       stat.pierce, stat.critical, stat.accuracy, stat.block, stat.maxhealth, stat.charid_ok (what
;                       Stat() gives for that school - PlayerStats.txt, StatsReader), set.<key> for each of BrecSetKeys
;                       (Stat(key): the deck in use's value included), deck.id, deck.school, deck.set (the deck's
;                       Equipment Set), deck.why (DeckWhy), deck.eqset (dashboard.ini: the set the bot last pressed for
;                       this character), party.mode, party.role_set, party.own (the wizards' names of your own party,
;                       | between)
; Caps: 120 lines / 40 KB a round (the rest counted in drop), 400 characters a line.

;(v2-only globals - the port tools don't know them: declared here with no value - a top-level := in an #Included file
;never runs - every one set in BrecInit, called by StartBot; each hook asks BrecInited first, so nothing throws before)
;Set up (1); recording on (the setting, told to the helper); a round's buffer open; its lines ("tick<TAB>line"), their
;size, the lines over the cap; when it opened; the round left to you seen again; the log's duel and round at its start
global BrecInited, BrecOn, BrecOpen, BrecBuf, BrecBytes, BrecDrop, BrecOpenAt, BrecAgain, BrecDuel, BrecRound
;The posts in flight ([{req, at}]); sent, skipped (the helper off, 4 in flight, a failed send); failed sends in a row;
;stopped by an error (1) and why; the helper told "on" this run; the battle count last told (BrecState "end"); the
;names typed for decks and the party (cut out of the lines); the CharID last read; the duel whose state went with a
;round post; a hello asked for later (Settings saved: sent once out of a round); buffers opened over an open one
global BrecReqs, BrecSent, BrecSkip, BrecSendErr, BrecDead, BrecDeadWhy, BrecTold, BrecEndN, BrecTyped, BrecChar
global BrecPostedDuel, BrecHelloPend, BrecLost
;A who change seen while a round's open (its post sent at the round's close: "" none); when the posts were last looked at
global BrecWhoPend, BrecPruneAt

;Everything set (StartBot, after ReconnectInit) - recording itself starts with the hello (BrecHello)
BrecInit()
	{
	global BrecInited, BrecOn, BrecOpen, BrecBuf, BrecBytes, BrecDrop, BrecOpenAt, BrecAgain, BrecDuel, BrecRound
	global BrecReqs, BrecSent, BrecSkip, BrecSendErr, BrecDead, BrecDeadWhy, BrecTold, BrecEndN, BrecTyped, BrecChar
	global BrecPostedDuel, BrecHelloPend, BrecLost, BrecWhoPend, BrecPruneAt, battles
	try
		{
		BrecOn := 0, BrecOpen := 0, BrecBuf := [], BrecBytes := 0, BrecDrop := 0, BrecOpenAt := 0, BrecAgain := 0
		BrecDuel := "", BrecRound := "", BrecReqs := [], BrecSent := 0, BrecSkip := 0, BrecSendErr := 0, BrecDead := 0
		BrecDeadWhy := "", BrecTold := 0, BrecEndN := 0, BrecTyped := [], BrecChar := "", BrecPostedDuel := ""
		BrecHelloPend := 0, BrecLost := 0, BrecWhoPend := "", BrecPruneAt := 0
		try BrecEndN := battles
		BrecInited := 1
		}
	}

;Set up and not stopped by an error
BrecUp() => IsSet(BrecInited) && BrecInited && !BrecDead

;The setting: on unless 0 (a PlayerStats.txt without the key - before an update added it: on)
BrecSettingOn()
	{
	try
		return StatOr("battlerec", 1) != 0
	return 0
	}

;A debug.log line (DebugLog's last line): kept for the round open, if one is - the round's reasons, verbatim
BrecNote(msg)
	{
	global BrecBuf, BrecBytes, BrecDrop
	if (!IsSet(BrecOpen) || !BrecOpen)
		return
	try
		{
		if (BrecBuf.Length >= 120 || BrecBytes >= 40960)
			{
			BrecDrop += 1
			return
			}
		brLine := SubStr(msg, 1, 400)
		BrecBuf.Push(A_TickCount "`t" brLine)
		BrecBytes += StrLen(brLine)
		}
	catch Any as e
		BrecFail(e, "BrecNote")
	}

;A round's buffer opened (the battle loop, just before "Round start: ..." - again: "Round start again ...", the round
;left to you still up). Not in dual mode (both windows write one game log)
BrecRoundOpen(again := 0)
	{
	global BrecOpen, BrecBuf, BrecBytes, BrecDrop, BrecOpenAt, BrecAgain, BrecDuel, BrecRound, BrecLost
	global dualmode, BlDuel, BlRound
	if (!BrecUp() || !BrecOn)
		return
	try
		{
		brDual := 0
		try brDual := (dualmode == 1)
		if (brDual)
			return
		if (BrecOpen)
			BrecLost += 1
		BrecBuf := [], BrecBytes := 0, BrecDrop := 0, BrecOpenAt := A_TickCount, BrecAgain := again ? 1 : 0
		BrecDuel := "", BrecRound := ""
		try BrecDuel := BlDuel
		try BrecRound := BlRound
		BrecOpen := 1
		}
	catch Any as e
		BrecFail(e, "BrecRoundOpen")
	}

;A cast that went out (CastResult, the Pass button gone): its title in the round's lines
BrecCast(title)
	{
	if (!IsSet(BrecOpen) || !BrecOpen)
		return
	BrecNote("@cast " title)
	}

;The battle loop's top (every pass, right after the round's mouse lock let go): a round open is closed and posted - its
;clicks are over, the next round can't be up for seconds (the spells' animations) - with a who change seen in it first.
;No round open: a hello asked for later sent out of battle, the posts that finished let go (4 times a second at most)
BrecRoundClose()
	{
	global BrecOpen, BrecBuf, BrecPostedDuel, BrecWhoPend
	global BlDuel, BlRound, roundnumber, BotOn, PlayerActive, PlayerTookRound, RoundLeft, PlayForMe, BattleRole
	global hitschool, MySlot, HammerSlot, HammerSchool, PipsNow
	if (!IsSet(BrecInited) || !BrecInited)
		return
	try
		{
		if (!BrecOpen)
			{
			if (BrecHelloPend && (BrecDead || !BrecInBattle()))
				BrecHello("now")
			else if (BrecReqs.Length && A_TickCount - BrecPruneAt >= 250)
				BrecPrune()
			return
			}
		brBuf := BrecBuf, BrecBuf := [], BrecOpen := 0, brClose := A_TickCount
		if (BrecDead || !BrecOn)
			{
			BrecWhoPend := ""
			return
			}
		if (BrecWhoPend != "")
			brWho := BrecWhoPend, BrecWhoPend := "", BrecSend(brWho)
		brDuel := BrecDuel
		if (brDuel = "")
			try brDuel := BlDuel
		brB := BrecKv("duel", brDuel)
		try brB .= BrecKv("round", (BrecRound = "" ? 0 : BrecRound) + 1)
		try brB .= BrecKv("botround", roundnumber)
		brB .= BrecKv("open", BrecOpenAt) BrecKv("close", brClose) BrecKv("again", BrecAgain)
		try brB .= BrecKv("bot", BotOn ? 1 : 0)
		try brB .= BrecKv("acting", PlayerActive ? 1 : 0)
		try brB .= BrecKv("took", PlayerTookRound ? 1 : 0)
		try brB .= BrecKv("left", RoundLeft ? 1 : 0)
		try brB .= BrecKv("pfm", PlayForMe ? 1 : 0)
		try brB .= BrecKv("role", BattleRole)
		try brB .= BrecKv("hitschool", hitschool)
		brB .= BrecKv("drop", BrecDrop) BrecKv("lost", BrecLost)
		try brB .= BrecKv("prole", PartyRoleSet())
		try brB .= BrecKv("brole", PartyBattleSet())
		try brB .= BrecKv("myslot", MySlot)
		try brB .= BrecKv("hslot", HammerSlot)
		try brB .= BrecKv("hschool", HammerSchool)
		try brB .= BrecKv("pips", PipsNow)
		;(a duel's first round post: the state with it - the stats, settings and deck this battle was played with)
		if (brDuel != BrecPostedDuel)
			{
			BrecPostedDuel := brDuel
			try brB .= BrecStateBody(false)
			}
		for brE in brBuf
			{
			brT := InStr(brE, "`t")
			brB .= "L`t" (SubStr(brE, 1, brT - 1) - BrecOpenAt) "`t" BrecEsc(BrecPriv(SubStr(brE, brT + 1))) "`n"
			}
		BrecSend("/rec?ev=round", brB)
		;(Settings saved during the round: its hello now - the round's over)
		if (BrecHelloPend)
			BrecHello("now")
		}
	catch Any as e
		BrecFail(e, "BrecRoundClose")
	}

;Who plays (PlayerActing, after PlayerActive is set: sent only on a change - a takeover by you, its end, Play for me;
;BotToggle: force - F6). The helper reads your hand itself only in a round the bot isn't playing. Seen in a round the
;bot's playing (a round open): kept - the latest - and sent at the round's close (BrecRoundClose: the bot leaves a round
;you took at once), so a post never goes out between the round's clicks
BrecWho(acting, force := 0)
	{
	static brLast := ""
	global BotOn, PlayForMe, BrecWhoPend
	if (!IsSet(BrecInited) || !BrecInited || BrecDead || !BrecOn)
		return
	try
		{
		brBot := 0, brPfm := 0
		try brBot := BotOn ? 1 : 0
		try brPfm := PlayForMe ? 1 : 0
		brKey := brBot (acting ? 1 : 0) brPfm
		if (!force && brKey == brLast)
			return
		brLast := brKey
		brQ := "/rec?ev=who&bot=" brBot "&acting=" (acting ? 1 : 0) "&pfm=" brPfm "&tk=" A_TickCount
		if (BrecOpen)
			BrecWhoPend := brQ
		else
			BrecSend(brQ)
		}
	catch Any as e
		BrecFail(e, "BrecWho")
	}

;The helper told whether to record, where the game's log is and the bot's state (StartBot, after VisionStart: "now";
;Settings.ahk CfgSaveNow: "later" - recording switched at once, the hello itself sent once out of a round, by
;BrecRoundClose). Off from the start: nothing is ever sent
BrecHello(when := "now")
	{
	global BrecOn, BrecOpen, BrecBuf, BrecTold, BrecHelloPend, BrecWhoPend
	if (!IsSet(BrecInited) || !BrecInited)
		return
	try
		{
		brOn := !BrecDead && BrecSettingOn()
		BrecOn := brOn
		if (!brOn)
			BrecOpen := 0, BrecBuf := [], BrecWhoPend := ""
		if (!brOn && !BrecTold)
			{
			BrecHelloPend := 0
			return
			}
		if (when != "now")
			{
			BrecHelloPend := 1
			return
			}
		BrecHelloPend := 0
		BrecSend("/rec?ev=hello", BrecHelloBody() (brOn ? BrecStateBody(true) : BrecKv("why", BrecDead ? "stopped" : "off")))
		BrecTold := brOn
		}
	catch Any as e
		BrecFail(e, "BrecHello")
	}

;The state after a battle (the battle loop, out of battle after StatsAuto - every pass: sent once a battle, the battle
;count told): the CharID, stats, settings and deck as they were
BrecState(why)
	{
	global BrecEndN, battles
	if (!IsSet(BrecInited) || !BrecInited || BrecDead || !BrecOn)
		return
	try
		{
		if (why = "end")
			{
			brN := ""
			try brN := battles
			if (brN = BrecEndN)
				return
			BrecEndN := brN
			}
		BrecSend("/rec?ev=state&why=" why, BrecHelloBody() BrecStateBody(true))
		}
	catch Any as e
		BrecFail(e, "BrecState")
	}

;The hello's own keys
BrecHelloBody()
	{
	global RcLog, dualmode, BotOn, PlayerActive, PlayForMe
	brB := BrecKv("on", BrecOn ? 1 : 0)
	try brB .= BrecKv("log", RcLog)
	try brB .= BrecKv("ver", BotVersion())
	try brB .= BrecKv("navmem", Stat("navmem"))
	try brB .= BrecKv("dual", dualmode == 1 ? 1 : 0)
	try brB .= BrecKv("bot", BotOn ? 1 : 0)
	try brB .= BrecKv("acting", PlayerActive ? 1 : 0)
	try brB .= BrecKv("pfm", PlayForMe ? 1 : 0)
	brB .= BrecKv("tk", A_TickCount)
	return brB
	}

;The state's keys (fresh: the CharID read again - out of a round only - and the typed names to cut out looked up again)
BrecStateBody(fresh)
	{
	global BrecChar, hitschool, Stats, DeckNow, DeckWhy
	if (fresh)
		{
		try BrecChar := StatsCharID()
		BrecTypedRefresh()
		}
	brB := BrecKv("char", BrecChar)
	brSch := ""
	try brSch := hitschool
	if (brSch = "")
		try brSch := StatsSchoolOf(BrecChar)
	brB .= BrecKv("school", brSch)
	try brB .= BrecKv("name", BrecMyName())
	;(the stats as Stat() has them for that school: PlayerStats.txt <school>.<key>, else the plain one)
	brB .= BrecKv("stat.school", brSch)
	for brK in ["damage", "pierce", "critical", "accuracy", "block", "maxhealth"]
		try brB .= BrecKv("stat." brK, (brSch != "" && Stats.Has(brSch "." brK)) ? Stats[brSch "." brK] : Stats.Has(brK) ? Stats[brK] : "")
	try brB .= BrecKv("stat.charid_ok", (brSch != "" && BrecChar != "" && Stats.Has(brSch ".charid")) ? (Stats[brSch ".charid"] = BrecChar ? 1 : 0) : "")
	for brK in BrecSetKeys()
		try brB .= BrecKv("set." brK, Stat(brK))
	;(the deck the bot believes is on - its id, never the name you typed for it)
	try brB .= BrecKv("deck.id", IsObject(DeckNow) ? DeckNow.id : "")
	try brB .= BrecKv("deck.school", IsObject(DeckNow) ? DeckNow.school : "")
	try brB .= BrecKv("deck.set", IsObject(DeckNow) ? DeckNow.eqset : "")
	try brB .= BrecKv("deck.why", BrecPriv(DeckWhy))
	try brB .= BrecKv("deck.eqset", IniRead(A_ScriptDir "\dashboard.ini", "decks", "eqset" BrecChar, ""))
	try brB .= BrecKv("party.mode", PartyRoleSet())
	try brB .= BrecKv("party.role_set", PartyBattleSet())
	try brB .= BrecKv("party.own", BrecOwnNames())
	return brB
	}

;The settings sent (a fixed list of numbers - never a webhook, token, login or anything typed): a deck's (DeckKeys)
;and these
BrecSetKeys()
	{
	static brKeys := ""
	if (!IsObject(brKeys))
		{
		brKeys := [], brSeen := Map()
		brSeen.CaseSense := false
		brAll := []
		try
			for brK in DeckKeys()
				brAll.Push(brK)
		for brK in ["enemyspells", "defendat", "healat", "learnedhits", "roundwait", "partybattle", "navmem", "handsoff", "handsoffon", "planner", "memclicks", "deckzone", "partyhitround", "partyorders"]
			brAll.Push(brK)
		for brK in brAll
			if (!brSeen.Has(brK))
				brSeen[brK] := 1, brKeys.Push(brK)
		}
	return brKeys
	}

;Your wizard's name as the game's log gives it (EnemySpells.ahk BlMe, else party.ini [me] - written from the log), for
;this character; never the [party] name you typed
BrecMyName()
	{
	global BlMe, BlMeChar
	brCid := BrecChar
	try
		{
		if (BlMe != "" && (BlMeChar = "" || brCid = "" || BlMeChar = brCid))
			return BlMe
		}
	try
		{
		brN := Trim(IniRead(A_ScriptDir "\party.ini", "me", "name", ""))
		brC := IniRead(A_ScriptDir "\party.ini", "me", "char", "")
		if (brN != "" && (brC = "" || brCid = "" || brC = brCid))
			return brN
		}
	return ""
	}

;The wizards of your own party (yours, the leader's and the followers' as the party heard them - Party.ahk): an ally's
;name is kept in a record only when it's one of them
BrecOwnNames()
	{
	global PartyLeader, PartyMembers
	brL := []
	try brL.Push(BrecMyName())
	try
		{
		if (IsObject(PartyLeader))
			brL.Push(PartyLeader.wiz)
		}
	try
		{
		if (IsObject(PartyMembers))
			for brM in PartyMembers
				brL.Push(brM.wiz)
		}
	brOut := ""
	for brN in brL
		{
		brN := Trim(brN)
		if (brN != "" && !InStr("|" brOut "|", "|" brN "|"))
			brOut .= (brOut = "" ? "" : "|") brN
		}
	return brOut
	}

;The names typed for decks (the Cards tab) and the party (party.ini [party] - the tray's Party... window): cut out of
;the lines sent (case as typed; 3 letters or more; not a school's name - "Storm" isn't cut out of "school=storm")
BrecTypedRefresh()
	{
	global BrecTyped, DeckList
	brT := []
	try brT.Push(IniRead(A_ScriptDir "\party.ini", "party", "name", ""))
	try brT.Push(IniRead(A_ScriptDir "\party.ini", "party", "leader", ""))
	try
		{
		if (IsObject(DeckList))
			for brD in DeckList
				if (brD.name != "Small deck" && brD.name != "Large deck")
					brT.Push(brD.name)
		}
	brOut := []
	for brS in brT
		{
		brS := Trim(brS)
		if (StrLen(brS) >= 3 && !RegExMatch(brS, "i)^(balance|death|fire|ice|life|myth|storm|shadow|sun|moon|star|astral)$"))
			brOut.Push(brS)
		}
	BrecTyped := brOut
	}

;A line as sent: left out when it could hold a secret, the names typed cut out
BrecPriv(s)
	{
	if (RegExMatch(s, "i)http|webhook|token|password|login"))
		return "(line left out)"
	try
		{
		for brT in BrecTyped
			if (InStr(s, brT, true))
				s := StrReplace(s, brT, "(typed)", true)
		}
	return s
	}

;key<TAB>value<LF>
BrecKv(k, v) => k "`t" BrecEsc(v) "`n"

;A value or line as sent - ASCII only: \ -> \\, tab -> \t, LF -> \n, CR dropped, anything else outside printable ASCII
;-> \uXXXX (UTF-16 code units, as JSON writes them)
BrecEsc(s)
	{
	s := String(s)
	if (!RegExMatch(s, "[^\x20-\x5B\x5D-\x7E]"))
		return s
	s := StrReplace(s, "\", "\\")
	s := StrReplace(s, "`t", "\t")
	s := StrReplace(s, "`n", "\n")
	s := StrReplace(s, "`r")
	;(only the characters outside printable ASCII looked at, one by one - the rest copied as it is)
	brO := "", brPos := 1
	while (brAt := RegExMatch(s, "[^\x20-\x7E]+", &brM, brPos))
		{
		brO .= SubStr(s, brPos, brAt - brPos)
		Loop Parse, brM[0]
			{
			brC := Ord(A_LoopField)
			if (brC > 0xFFFF)
				brO .= Format("\u{:04X}\u{:04X}", 0xD800 + ((brC - 0x10000) >> 10), 0xDC00 + ((brC - 0x10000) & 0x3FF))
			else
				brO .= Format("\u{:04X}", brC)
			}
		brPos := brAt + brM.Len
		}
	return brO SubStr(s, brPos)
	}

;One post to the helper, never waited for: WinHttp asynchronous (as Dashboard.ahk DashMapAsk asks /navmap), kept till
;it's done; 4 in flight - this one dropped. Not with the helper off (VisionOn); never counts towards VisionFails. 1 sent
BrecSend(path, body := "")
	{
	global BrecReqs, BrecSent, BrecSkip, BrecSendErr, VisionOn, VisionPort
	brVis := 0
	try brVis := VisionOn
	if (!brVis)
		{
		BrecSkip += 1
		return 0
		}
	if (BrecReqs.Length)
		BrecPrune()
	if (BrecReqs.Length >= 4)
		{
		BrecSkip += 1
		return 0
		}
	brPort := 47128
	try brPort := VisionPort ? VisionPort : 47128
	try
		{
		brReq := ComObject("WinHttp.WinHttpRequest.5.1")
		brReq.SetTimeouts(1000, 1000, 2000, 2000)
		brReq.Open("POST", "http://127.0.0.1:" brPort path, true)
		brReq.SetRequestHeader("Content-Type", "text/plain; charset=us-ascii")
		brReq.Send(body)
		}
	catch Any as e
		{
		BrecSkip += 1, BrecSendErr += 1
		;(the helper can't be posted to at all - WinHttp gone: stopped, said once)
		if (BrecSendErr >= 5)
			BrecFail(e, "BrecSend (5 posts in a row couldn't be sent)")
		return 0
		}
	BrecSendErr := 0
	BrecReqs.Push({req: brReq, at: A_TickCount})
	BrecSent += 1
	return 1
	}

;The posts that are done (answered, or failed - the helper not there) let go; one 5 s old given up
BrecPrune()
	{
	global BrecReqs, BrecPruneAt
	BrecPruneAt := A_TickCount
	brKeep := []
	for brR in BrecReqs
		{
		brDone := 1
		try brDone := brR.req.WaitForResponse(0)
		if (!brDone && A_TickCount - brR.at > 5000)
			{
			try brR.req.Abort()
			brDone := 1
			}
		if (!brDone)
			brKeep.Push(brR)
		}
	BrecReqs := brKeep
	}

;In a battle (the battle loop's inbattle)
BrecInBattle()
	{
	global inbattle
	try
		return inbattle = 1
	return 0
	}

;An error in the recorder: said once in debug.log, recording stopped till the next start (the helper told at the next
;look for a round); the bot plays on as ever - ErrorLevel left as it was (DebugLog's caller may be reading its own:
;the battle loop's startErr)
BrecFail(e, where)
	{
	global BrecDead, BrecDeadWhy, BrecOn, BrecOpen, BrecBuf, BrecHelloPend, BrecWhoPend, ErrorLevel
	try
		{
		if (BrecDead)
			return
		BrecDead := 1, BrecOn := 0, BrecOpen := 0, BrecBuf := [], BrecHelloPend := BrecTold ? 1 : 0, BrecWhoPend := ""
		BrecDeadWhy := where ": " (IsObject(e) ? e.Message (e.HasProp("Line") ? " (line " e.Line ")" : "") : e)
		brEl := ""
		try brEl := ErrorLevel
		try DebugLog("Battle recorder: stopped - " SubStr(BrecDeadWhy, 1, 200) " (the battles are played as ever; it records again from the next start)")
		ErrorLevel := brEl
		}
	}

;The dashboard's Statistics, after the Battles count (Dashboard.ahk DashRefresh): "   (recorded today: 12)" from the
;helper's learned\battles\today.txt (read at most every 30 s), "   (recorder: <why>)" when it's paused or stopped,
;"" when recording's off. fresh: read now (a test)
BrecToday(fresh := false)
	{
	static brAt := 0, brTxt := ""
	try
		{
		if (!IsSet(BrecInited) || !BrecInited)
			return ""
		if (BrecDead)
			return "   (recorder: stopped - " SubStr(BrecDeadWhy, 1, 50) ")"
		if (!BrecOn)
			return ""
		if (!fresh && brAt && A_TickCount - brAt < 30000)
			return brTxt
		brAt := A_TickCount
		brF := A_ScriptDir "\learned\battles\today.txt"
		if (!FileExist(brF))
			return brTxt := ""
		;(the helper replaces the file as it writes it: unreadable now - the last text kept)
		try
			brRaw := FileRead(brF)
		catch
			return brTxt
		brLn := Trim(StrSplit(brRaw, "`n", "`r")[1])
		if (RegExMatch(brLn, "^(\d{4}-\d\d-\d\d)\|(\d*)", &brM))
			{
			brP := StrSplit(brLn, "|")
			brWhy := brP.Length >= 8 ? Trim(brP[8]) : ""
			brTxt := "   (recorded today: " (brM[1] = FormatTime(, "yyyy-MM-dd") ? (brM[2] = "" ? 0 : brM[2]) : 0) (brWhy != "" ? "; recorder: " SubStr(brWhy, 1, 50) : "") ")"
			}
		else
			brTxt := brLn != "" ? "   (recorder: " SubStr(brLn, 1, 60) ")" : ""
		return brTxt
		}
	return ""
	}
