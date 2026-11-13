; Vision.ahk - asks the Python vision helper (vision\vision.py) which cards are in the hand and whose
; school badge is on a name plate. AHK v1.1, functions only; #Included by Autofarmer.ahk.
;
; The helper matches every card picture at every position with a distance (how far its colours are
; from the screen's), so the best match wins instead of ImageSearch's found / not found at a fixed
; tolerance. It's started with AutoFarmer (pythonw, no window), answers on 127.0.0.1:47128, and stops
; when AutoFarmer does. Whenever it can't be asked (Python missing, not started, an error three times
; in a row), Find / Tri / FindEnchant / BestBadge use ImageSearch as before. debug.log: "Vision: ...";
; the helper's own log: vision\vision.log.
;
; Needs from the including script: GameLeft/GameTop/GameW/GameH, ScreenX/ScreenY, UiScale, HandHalf,
; Px(), hitschool, DebugLog(), Stat() (KillCalc.ahk).
;
; NavRead (at the bottom) asks the helper where the wizard is and where the quest arrow points, read from the
; game's memory - for the walker (Walker.ahk). Only ever read: see "The game's memory" below.

global VisionOn, VisionPid, VisionFails, VisionCardsVar, VisionCardsAt, VisionCardsKey, VisionMissing ;(v1 never ran: VisionOn := 0, VisionPid := 0, VisionFails := 0, VisionCards := "", VisionCardsAt := 0, VisionCardsKey := "", VisionMissing := "," - blank at start: VisionBlank)
;The helper's folder ("" = vision\ next to the script) and port (tests use another one, so they don't stop
;the bot's own helper); why the last VisionGet got nothing
global VisionDir, VisionPort, VisionErr ;(v1 never ran: VisionDir := "", VisionPort := 47128 - blank at start: VisionBlank)
;Why the last VisionPlate read nothing
global VisionPlateWhy
;Why the last VisionCards (the hand from the game's memory) got nothing; its last answer kept, its why and when
global VisionCardsWhy, VisionMemLast, VisionMemAt, VisionMemWhy
;Why the last VisionPhase (the round's phase from the game's memory) got nothing; asked again from (after a failure)
global VisionPhaseWhy, VisionPhaseWaitUntil
;How many fresh looks at the hand VisionFind has taken (CardLearn.ahk LearnBoostPicFix: one miss a look) - declared only:
;a top-level := never runs here
global VisionLookN

;Starts the helper (after stopping one left over from before, and waiting till it has stopped) and waits up to 8 s
;for it to answer - when it doesn't, debug.log says why: the line it wrote in vision\vision.log (VisionStartWhy)
VisionStart()
	{
	global VisionOn, VisionPort, VisionMissing, VisionPid, VisionFails, ErrorLevel ; (v1 globals it sets)
	VisionOn := 0
	;(a global's starting value in an #Included file never runs: set here)
	if (!VisionPort)
		VisionPort := 47128
	if (VisionMissing = "")
		VisionMissing := ","
	VisionGet("/quit", 300)
	;(the old one answers on the port till it has stopped - a new one started before that binds the port beside it
	;(Windows lets it: Python's server sets SO_REUSEADDR), and its pings may reach the old one: waited for till it no
	;longer answers, up to 5 s)
	vsQuitAt := A_TickCount
	vsOldUp := (SubStr(VisionGet("/ping", 250, true), 1, 2) = "OK")
	while (vsOldUp && A_TickCount - vsQuitAt < 5000)
		{
		Sleep(250)
		vsOldUp := (SubStr(VisionGet("/ping", 250, true), 1, 2) = "OK")
		}
	if (vsOldUp)
		DebugLog("Vision: the old helper still answers 5 s after it was told to stop - starting the new one anyway")
	else if (A_TickCount - vsQuitAt > 1500)
		DebugLog("Vision: the old helper took " Round((A_TickCount - vsQuitAt) / 1000, 1) " s to stop")
	Sleep(300)
	py := VisionPython()
	if (py = "")
		{
		DebugLog("Vision: no Python found (pythonw.exe) - cards are found with ImageSearch")
		return false
		}
	dir := VisionDir != "" ? VisionDir : A_ScriptDir "\vision"
	if (!FileExist(dir "\vision.py"))
		{
		DebugLog("Vision: " dir "\vision.py isn't there - cards are found with ImageSearch")
		return false
		}
	;(vision.log's size now - what the helper writes from here on says why, if it stops: vision.py's log is
	;vision.log next to it)
	vsLog := dir "\vision.log"
	vsLogAt := V1N(V1Try(FileGetSize, vsLog))
	V1Run("`"" py "`" `"" dir "\vision.py`" --parent " DllCall("GetCurrentProcessId") " --port " VisionPort, dir, "Hide", &VisionPid)
	if (ErrorLevel)
		{
		DebugLog("Vision: couldn't start " py " - cards are found with ImageSearch")
		return false
		}
	startedAt := A_TickCount
	vsGone := false
	while (A_TickCount - startedAt < 8000)
		{
		Sleep(400)
		if (SubStr(VisionGet("/ping", 500), 1, 2) = "OK")
			{
			VisionOn := 1, VisionFails := 0
			DebugLog("Vision: helper running (" py ", pid " VisionPid ")")
			return true
			}
		;(it stopped: no point waiting)
		ErrorLevel := ProcessExist(VisionPid)
		if (!ErrorLevel)
			{
			vsGone := true
			break
			}
		}
	;(why: the line it wrote in vision.log since it was started - none: Python couldn't even run vision.py)
	vsWhy := VisionStartWhy(vsLog, vsLogAt)
	if (vsGone && vsWhy != "")
		DebugLog("Vision: the helper stopped at start - vision\vision.log: " vsWhy " - cards are found with ImageSearch")
	else if (vsGone)
		DebugLog("Vision: the helper stopped at start without a line in vision\vision.log - the Python at " py " couldn't run it at all (repair or reinstall that Python - Windows Settings > Apps - Setup.exe's `"Python 3`" leaves a Python it finds alone) - cards are found with ImageSearch")
	else
		DebugLog("Vision: the helper is still starting after 8 s - vision\vision.log: " (vsWhy != "" ? vsWhy : "nothing yet") " - it's stopped, cards are found with ImageSearch")
	;(don't leave it running, holding the port)
	if (VisionPid)
		ErrorLevel := ProcessClose(VisionPid)
	VisionPid := 0
	return false
	}

;For debug.log when the helper stopped at start or didn't answer: what it wrote in vision.log (path) since the file was
;fromBytes long - its last "can't start", "port ... taken" or error line, else its last line, without its time, at most
;500 characters; "" nothing (no file, or it couldn't be read). The file shorter than that: moved to vision.log.old as the
;helper started (over 512 KB) - all of it is new
VisionStartWhy(vswPath, vswFrom)
	{
	vswIn := V1Try(FileOpen, vswPath, "r", "UTF-8")
	if (!IsObject(vswIn))
		return ""
	try
		{
		if (vswIn.Length >= vswFrom)
			vswIn.Seek(vswFrom)
		vswText := vswIn.Read()
		}
	catch
		vswText := ""
	vswIn.Close()
	vswLast := "", vswTold := ""
	Loop Parse, vswText, "`n", "`r"
		{
		vswLine := Trim(A_LoopField)
		if (vswLine = "")
			continue
		vswLast := vswLine
		if (RegExMatch(vswLine, "i)can't start|port \d+ taken|error|exception"))
			vswTold := vswLine
		}
	vswLine := RegExReplace(vswTold != "" ? vswTold : vswLast, "^\d\d:\d\d:\d\d ")
	return StrLen(vswLine) > 500 ? SubStr(vswLine, 1, 497) "..." : vswLine
	}

;Stops the helper (on exit)
VisionStop()
	{
	if (VisionPid)
		VisionGet("/quit", 300)
	}

;pythonw.exe to run the helper with: the one next to python.exe on the PATH, else the usual install folders
VisionPython()
	{
	pathVar := EnvGet("PATH")
	Loop Parse, pathVar, "`;"
		{
		dir := Trim(A_LoopField)
		if (dir != "" && !InStr(dir, "WindowsApps") && FileExist(dir "\pythonw.exe"))
			return dir "\pythonw.exe"
		}
	Loop Files, A_AppData "\..\Local\Programs\Python\Python3*", "D"
		if (FileExist(A_LoopFilePath "\pythonw.exe"))
			return A_LoopFilePath "\pythonw.exe"
	return ""
	}

;One request to the helper. Returns its answer, "" if it couldn't be asked (3 of those in a row and
;the helper is left alone - ImageSearch from then on; VisionErr says why). noCount: an ERR or no answer
;doesn't count towards that (/nav: the game not running is no reason to stop asking about cards)
VisionGet(path, timeoutMs := 1500, noCount := false)
	{
	global VisionErr, ErrorLevel, VisionOn, VisionFails ; (v1 globals it sets)
	VisionErr := ""
	;(the helper's gone: no point asking - a closed port costs 2 s)
	if (VisionOn && VisionPid)
		{
		ErrorLevel := ProcessExist(VisionPid)
		if (!ErrorLevel)
			{
			VisionOn := 0, VisionErr := "the helper has stopped"
			DebugLog("Vision: the helper has stopped - cards are found with ImageSearch from now on")
			return ""
			}
		}
	try
		{
		;(sent without waiting, then polled: a waiting Send ignores the time limit and freezes the bot 2-5 s)
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "http://127.0.0.1:" (VisionPort ? VisionPort : 47128) path, true)
		req.Send()
		sentAt := A_TickCount
		while (!req.WaitForResponse(0))
			{
			if (A_TickCount - sentAt > timeoutMs)
				{
				req.Abort()
				;(a timeout counts double: the second one turns the helper off)
				if (!noCount)
					VisionFails := V1N(VisionFails) + 1   ; (v1: a blank counted as 0)
				throw "no answer in " timeoutMs " ms"
				}
			Sleep(10)
			}
		text := req.ResponseText
		if (req.Status != 200 || SubStr(text, 1, 3) = "ERR")
			throw text
		if (!noCount)
			VisionFails := 0
		return text = "" ? " " : text
		}
	catch Any as e   ; (v1: catch caught anything thrown - the strings thrown above too)
		{
		VisionErr := Trim(IsObject(e) ? e.Message : e, " `t`r`n")
		if (VisionOn && !noCount && ++VisionFails >= 3)
			{
			VisionOn := 0
			DebugLog("Vision: the helper stopped answering (" (IsObject(e) ? e.Message : e) ") - cards are found with ImageSearch from now on")
			}
		return ""
		}
	}

;The card pictures the bot looks for, as "dir/name"
VisionPicList()
	{
	list := ""
	for each, name in ["hit1", "hit2", "hit3", "hit4", "blade", "trap", "aura", "bubble", "convert", "wand", "heal1", "heal2"]
		list .= hitschool "/" name ","
	;(and the other schools' blades and traps the planned hit wants this battle - KillCalc.ahk BoostSearch)
	Loop Parse, BoostExtra, ","
		if (A_LoopField != "" && A_LoopField != hitschool && A_LoopField != "balance")
			list .= A_LoopField "/blade," A_LoopField "/trap,"
	for each, name in ["sharpen", "potent", "blade3", "blade4", "trap3", "trap4", "tower", "absorb", "reshuffle", "feint", "epic", "colossal", "gargantuan", "monstrous", "giant", "strong", "elementalblade", "elementaltrap", "spiritblade", "spirittrap"]
		list .= "resources/" name ","
	return list "life/enchant"
	}

;Where the card dir\title is in the hand: X, Y = the picture's top left (like ImageSearch). 1 found,
;0 not there, -1 the helper can't be asked (use ImageSearch). One look at the hand serves all the
;questions of the next 0.4 s (FindCards asks about every card in one go)
VisionFind(dir, title, &X, &Y)
	{
	global VisionCardsVar, VisionCardsAt, VisionCardsKey, VisionMissing, VisionLookN ; (v1 globals it sets)
	if (!VisionOn || hitschool = "")
		return -1
	key := hitschool "|" BoostExtra "|" UiScale "|" ScreenX "|" ScreenY
	if (!IsObject(VisionCardsVar) || A_TickCount - VisionCardsAt > 400 || key != VisionCardsKey)
		{
		answer := VisionGet("/cards?x1=" Round(ScreenX - HandHalf) "&y1=" Round(ScreenY - Px(75)) "&x2=" Round(ScreenX + HandHalf) "&y2=" Round(ScreenY + Px(150)) "&scale=" Round(UiScale, 3) "&pics=" VisionPicList())
		if (answer = "")
			return -1
		VisionCardsVar := [], VisionCardsAt := A_TickCount, VisionCardsKey := key, VisionMissing := ",", VisionLookN := (VisionLookN ? VisionLookN : 0) + 1
		Loop Parse, answer, "`n", "`r"
			{
			p := StrSplit(A_LoopField, "|")
			if (p.Length = 4)
				VisionCardsVar.Push(V1Obj({pic: p[1], x: V1Add(p[2], 0), y: V1Add(p[3], 0), d: V1Add(p[4], 0)}))
			;(v1: a field that isn't there - an empty line's first - read blank)
			else if (V1At(p, 1) = "missing")
				VisionMissing .= V1At(p, 2) ","
			}
		}
	want := StrReplace(dir, "\", "/") "/" title
	;(a picture the helper wasn't asked about, or couldn't look for: ImageSearch's job)
	if (!InStr("," VisionPicList() ",", "," want ",") || InStr(VisionMissing, "," want ","))
		return -1
	for i, c in VisionCardsVar
		if (c.pic = want)
			{
			X := c.x, Y := c.y
			return 1
			}
	return 0
	}

;Forget the last look at the hand (it's changed: a card was cast or discarded)
VisionForget()
	{
	global VisionCardsAt, VisionMemAt ; (v1 globals it sets)
	VisionCardsAt := 0, VisionMemAt := 0
	}

;---- The cards in hand from the game's memory (vision\handmem.py) ----
;
;The helper's /cards without a rectangle reads the hand straight out of the game's memory, READ-ONLY as /nav (nothing in
;the game is written, injected or hooked; no key, click or window): each card's name, school, kind, pips (X pips),
;numbers, whether it's a treasure / item card and its enchantment, and your pips of each kind - only in a battle's
;planning phase, once the hand's settled (the cards on screen are exactly your hand). navmem:0 in PlayerStats.txt
;switches it off too (VisionCardsWhy, VisionMemLast... at the top)

;The hand from the game's memory, as an object - "" when there's none (VisionCardsWhy says why: navmem:0, the helper not
;running or an older one, not in a battle's planning phase, a card chosen, the hand still changing after waitMs...):
;  me     {health, max, generic, power, balance, death, fire, ice, life, myth, storm, shadow (your pips of each kind -
;         "" not read), school (yours, lower case; "" not known), ok (1: every pip count read)}
;  cards  left to right as on screen: [{slot (Card1-7, PetCard), name (the spell's own), display (the name on the card),
;         school (lower case), type (the game's: Damage, AOE, Charm, Ward, Jinx...), pips ("" unknown), xpip (1: X pips),
;         shadow, castable (1 / 0 - an estimate, the normal mode - "" unknown), tc, item, ench (its enchantment's name,
;         "" none), acc, value (as /cards writes it: "255-285", "45/pip", "35%", "+175", "" none), num (value's first
;         number, "" none), kind (vision\handmem.py KINDS - damage aoe heal ward absorb blade trap aura negaura bubble
;         weakness curse charm enchant sharpen potent enchantother mutate dot stun dispel prism clear polymorph shadow
;         minion pips manipulation keep), dot (damage over time besides, "" none), schoolpips ("fire:1"), enchfx, valueench, tid (the
;         template id), text (about as the card says it), heads (a damage card's damage by school, every head of it:
;         "fire:230,ice:230,storm:230" - KillCalc.ahk HeadsParse), boosts (what a blade, trap or aura boosts by school:
;         "ice:35,storm:35,fire:35", "all:25" - BoostsParse; either "?" not to be trusted, "" none or an older helper), nf
;         (the line's fields: 23 an older helper's, with no heads or boosts), l, t, r, b (v1.0.0: its box in the game's GUI
;         root, in the GUI's own units - rootW, rootH below; "" not read or an older helper - VisionCardPx turns it into
;         pixels. NOT CHECKED against the screen yet: KillCalc.ahk MemBoxCheck logs it against /hand's boxes)}]
;  ms     how long the read took in the helper
;  rootW, rootH  the GUI root's size in its own units (the cards' boxes are in it; "" not read or an older helper)
;  plateSchool   the school the badge by your plate said when it isn't the memory's (one game running: the badge was
;         another wizard's - a party battle; "" they agree)
;While the game says the hand is changing (dealing, laying the cards out) it's asked again every 100 ms, up to waitMs.
;maxAgeMs: the last answer (or its why) if it's no older than that - the hand doesn't change till a card's cast or
;discarded (VisionForget forgets it)
VisionCards(waitMs := 1500, maxAgeMs := 0)
	{
	;(when the last wait for a settled hand ran out: for 10 s after, asked once with no retries - the 1.5 s wait was paid
	;two to six times a round)
	static vcGaveUp := 0
	;(the memory's school and the plate's that disagreed, said once a pair)
	static vcSaid := V1Obj()
	global VisionCardsWhy, VisionMemLast, VisionMemAt, VisionMemWhy ; (v1 globals it sets)
	if (maxAgeMs > 0 && VisionMemAt && A_TickCount - VisionMemAt <= maxAgeMs)
		{
		VisionCardsWhy := VisionMemWhy
		return VisionMemLast
		}
	VisionCardsWhy := "", VisionMemLast := "", VisionMemAt := 0, VisionMemWhy := ""
	if (!Stat("navmem"))
		{
		VisionCardsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		VisionCardsWhy := "the vision helper isn't running"
		return ""
		}
	;(two clients - dual mode: the memory read is one client's, maybe not the one played)
	if (dualmode == 1)
		{
		VisionCardsWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (vcGaveUp && A_TickCount - vcGaveUp < 10000)
		waitMs := 0
	;(partyorders, a follower: the read tagged with its duel and round - its helper keeps the hand for the party's leader;
	;off: "/cards" as ever)
	vcTag := V1IsFunc("PartyCardsTag") ? PartyCardsTag.Call() : ""
	vcFrom := A_TickCount
	Loop
		{
		;(an older helper - /cards wants a rectangle there - answers ERR: never counted against the helper)
		vcAns := Trim(VisionGet("/cards" vcTag, 800, true), " `t`r`n")
		if (vcAns = "")
			{
			VisionCardsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
			return VisionCardsKeep("")
			}
		if (SubStr(vcAns, 1, 5) != "none|")
			break
		VisionCardsWhy := SubStr(vcAns, 6)
		if (VisionCardsWhy != "hand changing" || A_TickCount - vcFrom >= waitMs)
			{
			if (VisionCardsWhy = "hand changing" && waitMs > 0)
				vcGaveUp := A_TickCount
			return VisionCardsKeep("")
			}
		Sleep(100)
		}
	vcOut := V1Obj({me: "", cards: [], ms: "", rootW: "", rootH: "", plateSchool: ""})
	Loop Parse, vcAns, "`n", "`r"
		{
		vcF := StrSplit(A_LoopField, "|")
		;(v1: a field that isn't there - an empty line's first, an older helper's 18-25 - read blank)
		if (V1At(vcF, 1) = "me" && vcF.Length >= 14)
			{
			vcMe := V1Obj({health: NavNum(vcF[2]), max: NavNum(vcF[3]), school: Format("{:L}", Trim(vcF[14])), ok: 1})
			for vcI, vcKey in ["generic", "power", "balance", "death", "fire", "ice", "life", "myth", "storm", "shadow"]
				{
				vcMe[vcKey] := NavNum(vcF[vcI + 3])
				if (vcMe[vcKey] = "")
					vcMe.ok := 0
				}
			vcOut.me := vcMe
			}
		else if (V1At(vcF, 1) = "card" && vcF.Length >= 17)
			{
			vcCard := V1Obj({slot: vcF[2], x: NavNum(vcF[3]), name: vcF[4], display: vcF[5], school: Format("{:L}", vcF[6]), type: vcF[7]
				, pips: NavNum(vcF[8]), xpip: vcF[9] = 1, shadow: NavNum(vcF[10]), castable: vcF[11], tc: vcF[12] = 1, item: vcF[13] = 1
				, ench: vcF[14], acc: NavNum(vcF[15]), value: vcF[16], kind: vcF[17], dot: NavNum(V1At(vcF, 18)), schoolpips: V1At(vcF, 19)
				, enchfx: V1At(vcF, 20), valueench: V1At(vcF, 21), tid: V1At(vcF, 22), text: V1At(vcF, 23), heads: V1At(vcF, 24), boosts: V1At(vcF, 25), nf: vcF.Length
				, l: NavNum(V1At(vcF, 26)), t: NavNum(V1At(vcF, 27)), r: NavNum(V1At(vcF, 28)), b: NavNum(V1At(vcF, 29))})
			vcCard.num := RegExMatch(vcCard.value, "\d+", &vcNum) ? vcNum[0] + 0 : ""
			vcOut.cards.Push(vcCard)
			}
		else if (V1At(vcF, 1) = "hand")
			vcOut.ms := V1At(vcF, 3)
		;(v1.0.0: the GUI root's size the cards' boxes are in - an older helper has no such line)
		else if (V1At(vcF, 1) = "root")
			vcOut.rootW := NavNum(V1At(vcF, 2)), vcOut.rootH := NavNum(V1At(vcF, 3))
		}
	vcGaveUp := 0
	if (!IsObject(vcOut.me))
		{
		VisionCardsWhy := "an odd answer: " SubStr(RegExReplace(vcAns, "\s+", " "), 1, 60)
		return VisionCardsKeep("")
		}
	;(the wizard on screen another school than the game's memory's: another client's - not used. Only while more than one
	;game runs, though: with one, the memory's can't be another client's, and the badge read by your plate was another
	;wizard's - a party battle, where player.png can match a teammate's plate (PlayerPlates2) - so the hand is kept, said
	;once a pair (v1.0.0: before, the whole memory hand was thrown away for the round - every memory cast, false-match drop
	;and memory pip read lost))
	if (vcOut.me.school != "" && school != "" && V1IsFunc("BadgeNumber") && BadgeNumber.Call(school) && Format("{:L}", school) != vcOut.me.school)
		{
		if (VisionGameClients() != 1)
			{
			VisionCardsWhy := "another client's wizard (the game's memory: " vcOut.me.school ", the plate: " school ")"
			return VisionCardsKeep("")
			}
		vcOut.plateSchool := Format("{:L}", school)
		if (!vcSaid.Has(vcOut.me.school "|" vcOut.plateSchool))
			vcSaid[vcOut.me.school "|" vcOut.plateSchool] := 1, DebugLog("Vision: the game's memory says your school is " vcOut.me.school ", the badge read by your plate " vcOut.plateSchool " - one game running, so that badge was another wizard's (a party battle?): the memory's hand kept (said once)")
		}
	return VisionCardsKeep(vcOut)
	}

;How many game windows there are (VisionCards: not one - the game's memory may be another client's), 0 none found
VisionGameClients()
	{
	;(carry mode - two clients: the helper reads the one in front alone, so it's one as far as the memory goes - Carry.ahk)
	if (CarryPinnedFront())
		return 1
	try
		return WinGetCount("ahk_class " GameClass " ahk_exe " GameExe)
	catch
		return 0
	}

;Whether the game's memory can be this client's for sure - one game window (v1.0.0 review): navmem attaches to the
;foreground client, else the first it finds, and stays on it (vision\navmem.py _ensure), so with two or more running it can
;be reading another client's battle (dual mode is NavBattle's own refusal). The values the bot acts on that came in with
;TODO.md goal 3 ask this first: Autofarmer.ahk RoundBattleMem (your school and plate - written over the badge's, they'd also
;blind VisionCards' "another client's wizard" check, which compares the two) and OwnMemHealth, KillCalc.ahk EnemyMemHealth
;and MemBoxTrusted (memclicks), Party.ahk PartyMemAlly - not one window: read off the screen, as before. Said in debug.log
;when the count changes (one again: said again the next time it isn't)
VisionMemOneClient()
	{
	static vmoSaid := ""
	vmoN := VisionGameClients()
	if (vmoN = 1)
		{
		vmoSaid := 1
		return true
		}
	if (vmoN != vmoSaid)
		vmoSaid := vmoN, DebugLog("Vision: " vmoN " game window(s) found - the game's memory may be another client's: your school and plate, the battle's health and the memory's card boxes are taken off the screen (said once till that changes)")
	return false
	}

;A card of the hand from the game's memory (VisionCards' hand, card one of its cards) in screen pixels: x, y the middle
;of its box (QuickSell.ahk QsPx's rule: GameLeft + its GUI units over the root's width x GameW). False, x and y "": its
;box or the root not read (an older helper), the box not inside the root, or the pixel off the game window. It clicks
;nothing: a click there is KillCalc.ahk's (MemCardFind / MemEnchantFind / HandBoxes - memclicks, off, and only once
;MemBoxCheck has seen the boxes line up)
VisionCardPx(hand, card, &x, &y)
	{
	x := "", y := ""
	if (!IsObject(hand) || !IsObject(card) || hand.rootW = "" || hand.rootH = "" || hand.rootW <= 0 || hand.rootH <= 0 || GameW <= 0)
		return false
	if (card.l = "" || card.t = "" || card.r = "" || card.b = "" || card.r <= card.l || card.b <= card.t)
		return false
	if (card.l < -2 || card.t < -2 || card.r > hand.rootW + 2 || card.b > hand.rootH + 2)
		return false
	vcpX := Round(GameLeft + (card.l + card.r) / 2 * GameW / hand.rootW)
	vcpY := Round(GameTop + (card.t + card.b) / 2 * GameH / hand.rootH)
	if (vcpX < GameLeft || vcpY < GameTop || vcpX >= GameLeft + GameW || vcpY >= GameTop + GameH)
		return false
	x := vcpX, y := vcpY
	return true
	}

;VisionCards' answer kept, with its why, for its maxAgeMs
VisionCardsKeep(vckOut)
	{
	global VisionMemLast, VisionMemWhy, VisionMemAt ; (v1 globals it sets)
	VisionMemLast := vckOut, VisionMemWhy := VisionCardsWhy, VisionMemAt := A_TickCount
	return vckOut
	}

;Whose school badge is in the rectangle, by the helper: the school ("" none clearly), its top left in
;bx, by; -1 if the helper can't be asked or the best spot is unclear (two schools too close). With
;several plates (a team battle), the badge nearest nearX, nearY (0: the best match)
VisionBadge(x1, y1, x2, y2, &bx, &by, nearX := 0, nearY := 0)
	{
	if (!VisionOn)
		return -1
	;(v1: Round of a blank was 0 - Autofarmer's plate not found leaves playerX blank, and the badge is asked about 0, 0, 0, 0)
	answer := VisionGet("/badge?x1=" V1Round(x1) "&y1=" V1Round(y1) "&x2=" V1Round(x2) "&y2=" V1Round(y2) "&scale=" Round(UiScale, 3) "&schools=storm,fire,myth,balance,ice,life,death")
	if (answer = "" || InStr(answer, "unclear"))
		return -1
	sch := "", bestFar := ""
	Loop Parse, answer, "`n", "`r"
		{
		p := StrSplit(A_LoopField, "|")
		if (p.Length != 4)
			continue
		far := (nearX || nearY) ? (p[2] - nearX) ** 2 + (p[3] - nearY) ** 2 : A_Index
		if (bestFar = "" || far < bestFar)
			sch := p[1], bx := V1Add(p[2], 0), by := V1Add(p[3], 0), bestFar := far   ; (v1: not a number + 0 was blank)
		}
	return sch
	}

;A name plate's red health numbers in the rectangle, read by the helper by their shape (its /plate - Windows' OCR
;misses them more often than not at 1440p): {cur, max, worst} (worst: the least like its cut picture of the glyphs,
;0-0.3), or "" - why in VisionPlateWhy
VisionPlate(x1, y1, x2, y2)
	{
	global VisionPlateWhy ; (v1 globals it sets)
	VisionPlateWhy := ""
	if (!VisionOn)
		{
		VisionPlateWhy := "the vision helper isn't running"
		return ""
		}
	;(v1: Round of a blank was 0 - PlateHealth's nx, ny are blank when your plate wasn't found: the helper asked about 0, 0, 0, 0)
	answer := VisionGet("/plate?x1=" V1Round(x1) "&y1=" V1Round(y1) "&x2=" V1Round(x2) "&y2=" V1Round(y2), 1500)
	if (RegExMatch(answer, "^health\|(\d+)\|(\d+)\|([\d.]+)", &m) && m[2] > 0)
		return V1Obj({cur: m[1] + 0, max: m[2] + 0, worst: m[3] + 0})
	VisionPlateWhy := answer = "" ? (VisionErr = "" ? "no answer" : VisionErr) : RegExReplace(Trim(answer, " `r`n"), "^none\|")
	return ""
	}

;---- The game's memory: where the wizard is and where the quest arrow points (for Walker.ahk) ----
;
;The helper's /nav reads them straight out of the game's memory, READ-ONLY: the game is opened for reading
;only - nothing in it is ever written, nothing is injected or hooked, no keys are sent and its window isn't
;touched. navmem:0 in PlayerStats.txt switches it off (the walker then only reads the arrow off the screen).
;Why the last NavRead got nothing; when it may ask again, and how long it waited last time
global NavWhy, NavWaitUntil, NavWait
;Set by the walker's F8 (walking on): the next NavRead asks the helper to forget the teleports it gave up
global NavUnblock
;Why the last NavGoal got nothing; when it may ask again
global NavGoalWhy, NavGoalWaitUntil
;Why the last NavMobs / NavBattle got nothing; when each may ask again
global NavMobsWhy, NavMobsWaitUntil, NavBattleWhy, NavBattleWaitUntil
;Why the last NavBag / NavGui got nothing; when each may ask again (declared only: a top-level := never runs here)
global NavBagWhy, NavBagWaitUntil, NavGuiWhy, NavGuiWaitUntil
;Why the last NavGuiTree got nothing; when it may ask again (declared only: a top-level := never runs here)
global NavGuiTreeWhy, NavGuiTreeWaitUntil
;Why the last NavGear got nothing; when it may ask again (declared only: a top-level := never runs here)
global NavGearWhy, NavGearWaitUntil
;Why the last NavPets got nothing; when it may ask again (declared only: a top-level := never runs here)
global NavPetsWhy, NavPetsWaitUntil
;Why the last NavItems got nothing; when it may ask again
global NavItemsWhy, NavItemsWaitUntil
;Why the last NavUiScale got nothing; when it may ask again; the GUI root's width it read (GUI units)
global NavUiWhy, NavUiWaitUntil, NavUiRootW

;The wizard and the quest goal from the game's memory, as an object:
;  ok        1
;  zone      the zone, e.g. WizardCity/WC_Ravenwood (as the game's log names it)
;  x, y, z   the wizard (z is up), yaw its facing in radians: forward = (-sin yaw, -cos yaw)
;  tx, ty, tz  where the quest arrow points (a node on the game's own path to the goal)
;  gx, gy, gz  the goal (hops 0), or the way out of this zone to take (hops = zone changes to go)
;  dist      the arrow's distance along the game's path (game units, not the number printed on the arrow)
;  enabled   1 while the game's quest helper is on; questid, goalid the quest and goal (as text)
;  path      (withPath only) the game's path, [{x, y, z}, ...] in order
;  ax, ay    (withRoute only) where to steer: a point ahead on the route the helper planned round the walls
;            over the zone's map (vision\navroute.py); "" when it has none yet - routewhy says why
;  left      (withRoute only) how far is left to walk along that route and the game's path on from it (game units)
;  jump, jx, jy  (withRoute only) right at a teleport on the game's path (the route stops at it): the seconds
;            waited there, and where it is; "" otherwise
;  duel, duelx, duely  (withRoute, avoidMobs and duelavoid only) another player's battle on the way the route can't go
;            round (a duel circle in the game's memory - not confirmed in the game yet): the seconds waited for it, where
;            it is; "" otherwise (an older helper sends none)
;  goaltext, goaltype, goalstatus, goalcount, goaltotal, goalshown  the quest's goal line from the game's memory and its
;            kind, status, count, total, on screen (1/0) - as NavGoal's; "" when it can't be read (or an older helper)
;  noplace   1: the game shows no way to the goal - no arrow (its goal reads exactly 0, 0, 0 and the arrow's distance -1:
;            "Use Inactive Protector in District of the Stars (0 of 3)" - gx..dist are "" then and an arrow seen on the
;            screen is a phantom); 0: the goal has a place; "" not known (another zone, the quest helper off, a goal
;            change caught midway, an older helper). noplaceheld: seconds the 1 has held for this quest and goal (a
;            number - 3.000000: compare it as one), "" unless noplace is 1 - act on it once it has held (2 s, and the
;            same goalid two readings running: a goal change or a zone arrival can read 1 for a moment)
;A value that couldn't be read for sure is "". Returns "" when it can't be asked: navmem:0, the helper not
;running, an ERR (the game not running, at the login screen...) or no answer within timeoutMs - NavWhy says
;why, and after an ERR it isn't asked again for 1 s, doubling to 30 s while it keeps failing (no answer:
;1-4 s; the helper may be busy finding its way into a game it hasn't read yet)
;avoidMobs (with withRoute): the route kept out of what the zone's mobs see (mobshape, mobradius) - but not those named in
;goalLine, the quest's goal line (or a function giving it: called only if the ask is sent), nor one by the quest's
;goal (the helper decides)
NavRead(timeoutMs := 150, withPath := false, withRoute := false, avoidMobs := false, goalLine := "")
	{
	global NavWhy, NavUnblock, NavWait, NavWaitUntil ; (v1 globals it sets)
	if (!Stat("navmem"))
		{
		NavWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavWhy := "the vision helper isn't running"
		return ""
		}
	if (V1Lt(A_TickCount, NavWaitUntil))   ; (v1: blank - never failed - compared as text: not waiting)
		return ""
	unblock := (withRoute && NavUnblock) ? "&unblock=1" : ""
	if (withRoute && avoidMobs)
		{
		goalNow := IsObject(goalLine) ? goalLine.Call() : goalLine
		unblock .= NavMobArgs() "&goal=" NavUri(SubStr(goalNow, 1, 160))
		}
	;(the wizard's turning circle: the helper looks round its arc to the aim - walls on it or not)
	arcAsk := (withRoute && V1IsFunc("WalkTurnRadius")) ? "&arcr=" WalkTurnRadius.Call() : ""
	answer := VisionGet("/nav?path=" (withPath ? 1 : 0) "&route=" (withRoute ? 1 : 0) unblock arcAsk, timeoutMs, true)
	if (InStr(unblock, "&unblock=1") && answer != "")
		NavUnblock := 0
	if (answer = "")
		{
		NavWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavWait := V1Ge(NavWait, 1000) ? Min(NavWait * 2, InStr(VisionErr, "no answer") ? 4000 : 30000) : 1000
		NavWaitUntil := A_TickCount + NavWait
		return ""
		}
	nav := V1Obj({ok: "", zone: "", x: "", y: "", z: "", yaw: "", tx: "", ty: "", tz: "", gx: "", gy: "", gz: ""
		, hops: "", dist: "", enabled: "", questid: "", goalid: "", ax: "", ay: "", left: "", routewhy: "", jump: "", jx: "", jy: ""
		, mob: "", mx: "", my: "", mobname: "", escape: "", blindahead: "", blindback: "", blindin: "", arc: "", duel: "", duelx: "", duely: ""
		, goaltext: "", goaltype: "", goalstatus: "", goalcount: "", goaltotal: "", goalshown: "", noplace: "", noplaceheld: ""})
	Loop Parse, answer, "`n", "`r"
		{
		navLine := A_LoopField
		f := StrSplit(navLine, "|")
		if (V1At(f, 1) = "ok")
			nav.ok := NavNum(V1At(f, 2))
		else if (V1At(f, 1) = "zone")
			nav.zone := Trim(SubStr(navLine, 6))
		else if (V1At(f, 1) = "pos")
			nav.x := NavNum(V1At(f, 2)), nav.y := NavNum(V1At(f, 3)), nav.z := NavNum(V1At(f, 4)), nav.yaw := NavNum(V1At(f, 5))
		else if (V1At(f, 1) = "target")
			nav.tx := NavNum(V1At(f, 2)), nav.ty := NavNum(V1At(f, 3)), nav.tz := NavNum(V1At(f, 4))
		else if (V1At(f, 1) = "goal")
			nav.gx := NavNum(V1At(f, 2)), nav.gy := NavNum(V1At(f, 3)), nav.gz := NavNum(V1At(f, 4)), nav.hops := NavNum(V1At(f, 5))
		else if (V1At(f, 1) = "dist")
			nav.dist := NavNum(V1At(f, 2))
		else if (V1At(f, 1) = "quest")
			nav.enabled := NavNum(V1At(f, 2)), nav.questid := Trim(V1At(f, 3)), nav.goalid := Trim(V1At(f, 4))
		else if (V1At(f, 1) = "route" && withRoute)
			{
			nav.ax := NavNum(V1At(f, 2)), nav.ay := NavNum(V1At(f, 3)), nav.left := NavNum(V1At(f, 4)), nav.jump := NavNum(V1At(f, 5)), nav.jx := NavNum(V1At(f, 6)), nav.jy := NavNum(V1At(f, 7))
			;(8-11: a mob on the way the route can't go round - seconds waited for it, where it is, its name)
			nav.mob := NavNum(V1At(f, 8)), nav.mx := NavNum(V1At(f, 9)), nav.my := NavNum(V1At(f, 10)), nav.mobname := Trim(V1At(f, 11))
			;(12: inside a mob's ring or sight - its name: the aim leads out of it; 13: turning walking on round to the
			;aim - 1 its arc's clear of the walls, 0 not, "" not known)
			nav.escape := Trim(V1At(f, 12)), nav.arc := f.Length >= 13 ? Trim(V1At(f, 13)) : ""
			;(14-16: another player's battle on the way the route can't go round - the seconds waited for it, where it is;
			;an older helper's line stops at 13)
			if (f.Length >= 16)
				nav.duel := NavNum(V1At(f, 14)), nav.duelx := NavNum(V1At(f, 15)), nav.duely := NavNum(V1At(f, 16))
			}
		;(the mob whose ring or sight the arrow's straight way comes into, and backing up would - moves off the route)
		else if (V1At(f, 1) = "blind" && withRoute)
			nav.blindahead := Trim(V1At(f, 2)), nav.blindback := Trim(V1At(f, 3)), nav.blindin := Trim(V1At(f, 4))
		else if (V1At(f, 1) = "routewhy" && withRoute)
			nav.routewhy := Trim(SubStr(navLine, 10))
		;(no place: the game shows no way to the goal - 1, a place 0, "" not known; how long the 1 has held, s - an older
		;helper sends no such line)
		else if (V1At(f, 1) = "noplace")
			nav.noplace := NavNum(V1At(f, 2)), nav.noplaceheld := NavNum(V1At(f, 3))
		;(the quest's goal line from the game's memory - the helper's last line; an older one has none)
		else if (V1At(f, 1) = "goalline")
			nav.goaltext := Trim(V1At(f, 2)), nav.goaltype := Trim(V1At(f, 3)), nav.goalstatus := Trim(V1At(f, 4)), nav.goalcount := NavNum(V1At(f, 5))
				, nav.goaltotal := NavNum(V1At(f, 6)), nav.goalshown := NavNum(V1At(f, 7))
		else if (V1At(f, 1) = "path" && withPath)
			{
			nav.path := [], nodes := SubStr(navLine, 6)
			Loop Parse, nodes, "`;"
				{
				xyz := StrSplit(A_LoopField, ",")
				if (xyz.Length = 3 && NavNum(xyz[1]) != "" && NavNum(xyz[2]) != "" && NavNum(xyz[3]) != "")
					nav.path.Push(V1Obj({x: NavNum(xyz[1]), y: NavNum(xyz[2]), z: NavNum(xyz[3])}))
				}
			}
		}
	if (nav.ok != 1)
		{
		NavWhy := "an odd answer: " SubStr(RegExReplace(answer, "\s+", " "), 1, 60)
		NavWait := 1000, NavWaitUntil := A_TickCount + NavWait
		return ""
		}
	NavWhy := "", NavWait := 0, NavWaitUntil := 0
	return nav
	}

;Text for a URL: its UTF-8 bytes, all but letters, digits and -._~ as %XX (the helper reads it as UTF-8)
NavUri(text)
	{
	navUriBuf := Buffer(StrPut(text, "UTF-8"), 0)
	navUriLen := StrPut(text, navUriBuf.Ptr, "UTF-8") - 1
	navUriOut := ""
	Loop navUriLen
		{
		navUriByte := NumGet(navUriBuf, A_Index - 1, "UChar")
		navUriOut .= ((navUriByte >= 48 && navUriByte <= 57) || (navUriByte >= 65 && navUriByte <= 90) || (navUriByte >= 97 && navUriByte <= 122)
			|| navUriByte = 45 || navUriByte = 46 || navUriByte = 95 || navUriByte = 126) ? Chr(navUriByte) : "%" Format("{:02X}", navUriByte)
		}
	return navUriOut
	}

;The quest's active goal from the game's memory (the helper's /goal - READ-ONLY, vision\questmem.py: the line exactly as
;the game draws it under the quest arrow, where the OCR of the screen slips letters - 2026-10-24 "Opiio (jn -rhe" for
;"Defeat Optio Agenor ..."), as an object:
;  text      the goal line ("Defeat Crustacean Waverunner and Collect Foul Tasting Algae in The Grotto (0 of 3)")
;  from      data (built from the quest's own data) / hud (the HUD's own text: the data's names not all read)
;  shown     1 on screen, 0 hidden (a battle), "" not known; hudtext the HUD's own line, distance the arrow's number
;  type      BOUNTY (defeat), BOUNTYCOLLECT (defeat and collect), USAGE (collect / open / use / read), WAYPOINT (go to),
;            PERSONA (talk to), SCAVENGE...; status INCOMPLETE / COMPLETE (the quest moving on); "" not read
;  count, total  "(count of total)"; "" none (talk and go-to goals)
;  mob, item, npc, place  what it names: the mob (or its kind: "Gobblers"), the item / object / one to go to, the NPC
;  quest, questid, goalid  the quest's title and ids; exact 1: the line and the fields are the goal's own data
;  itemkey, mobkey  the name-table keys of what it names (the TALLYTEXT "WizQst371C7_00000008" = Inactive Protector - the
;            display key NavItems' things carry; the TALLYTEXT2 "WizardMobs_00000883"); npcfirst, npclast a talk goal's
;            NPC's (FIRSTNAME, LASTNAME "WC-NPCs_00000014"); namekey the goal's own ("WizardQuestGoals_UseItem"); typenum
;            the game's number for its kind (USAGE 8 - for logs only: it may change between builds). "" none, the quest
;            moved on, or an older helper. A key is exact, but a goal's key may be another table's for the same words:
;            a match candidate, never the only test
;"" when it can't be read - navmem:0 in PlayerStats.txt, the helper not running or older (no /goal), no quest, the game
;not read yet - NavGoalWhy says why (the walker reads the line off the screen then). After no answer or an ERR it isn't
;asked again for 10 s (an older helper: 60 s)
NavGoal(timeoutMs := 800)
	{
	global NavGoalWhy, NavGoalWaitUntil ; (v1 globals it sets)
	if (!Stat("navmem"))
		{
		NavGoalWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavGoalWhy := "the vision helper isn't running"
		return ""
		}
	if (NavGoalWaitUntil && A_TickCount < NavGoalWaitUntil)
		return ""
	answer := VisionGet("/goal", timeoutMs, true)
	if (answer = "")
		{
		NavGoalWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavGoalWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 10000)
		return ""
		}
	NavGoalWaitUntil := 0
	goal := V1Obj({text: "", from: "", shown: "", hudtext: "", distance: "", type: "", status: "", count: "", total: "", mob: ""
		, item: "", npc: "", place: "", quest: "", questid: "", goalid: "", exact: "", typenum: "", itemkey: "", mobkey: ""
		, npcfirst: "", npclast: "", namekey: ""})
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (V1At(f, 1) = "none")
			{
			NavGoalWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (V1At(f, 1) = "text")
			goal.text := Trim(V1At(f, 2)), goal.from := Trim(V1At(f, 3))
		else if (V1At(f, 1) = "shown")
			goal.shown := NavNum(V1At(f, 2)), goal.hudtext := Trim(V1At(f, 3)), goal.distance := Trim(V1At(f, 4))
		;(kind's number: a kindnum line - or a 4th field here, as a helper may send it)
		else if (V1At(f, 1) = "kind")
			goal.type := Trim(V1At(f, 2)), goal.status := Trim(V1At(f, 3)), goal.typenum := f.Length >= 4 ? NavNum(V1At(f, 4)) : goal.typenum
		else if (V1At(f, 1) = "count")
			goal["count"] := NavNum(V1At(f, 2)), goal.total := NavNum(V1At(f, 3))
		else if (V1At(f, 1) = "mob" || V1At(f, 1) = "item" || V1At(f, 1) = "npc" || V1At(f, 1) = "place")
			goal[V1At(f, 1)] := Trim(V1At(f, 2))
		else if (V1At(f, 1) = "quest")
			goal.quest := Trim(V1At(f, 2)), goal.questid := Trim(V1At(f, 3)), goal.goalid := Trim(V1At(f, 4))
		else if (V1At(f, 1) = "exact")
			goal.exact := NavNum(V1At(f, 2))
		;(the goal's raw keys - an older helper sends none of these lines)
		else if (V1At(f, 1) = "itemkey" || V1At(f, 1) = "mobkey" || V1At(f, 1) = "namekey")
			goal[V1At(f, 1)] := Trim(V1At(f, 2))
		else if (V1At(f, 1) = "npckeys")
			goal.npcfirst := Trim(V1At(f, 2)), goal.npclast := Trim(V1At(f, 3))
		else if (V1At(f, 1) = "kindnum")
			goal.typenum := NavNum(V1At(f, 2))
		}
	if (goal.text = "")
		{
		NavGoalWhy := "an odd answer: " SubStr(RegExReplace(answer, "\s+", " "), 1, 60)
		return ""
		}
	NavGoalWhy := ""
	return goal
	}

;The zone's mobs from the game's memory (the helper's /mobs - READ-ONLY, vision\navmem.py and vision\bossmem.py: nothing
;in the game is written, injected or hooked; no key, click or window), nearest first, as an array of {name, x, y, z, dist
;(from the wizard), quest (1: the quest's - the helper's verdict by the game's memory's goal: its name, its kind, one by
;a fight goal's goal; goalLine, the line read off the screen, only when the memory's can't be read), off (degrees from
;where it faces to the wizard, "" not known), title (as the game names it: Boss, Elite, Normal, Easy, Minion), rank (the
;one the game shows: "Rank 9 Boss"), health (its starting - max - health), school (Ice...), boss (1: the game's own boss
;flag, 0 not), gid, named (1: the quest's by its name or its goal only - quest without a same-family match elsewhere in
;the zone, 0 not), template (its template's name - "CL-DeepOne-GreenHead-R10": a newer helper's 16th field), vx, vy (how fast
;it walks along x and y, game units a second - its last second of readings), moving (1 walking, 0 standing: a newer helper's
;17th-19th fields)} - title...moving
;"" while not known (the helper's reader being made, a build it can't read, an older helper). [] when there are none (the helper's plain "none"); "" when they can't be read - navmem:0, the helper not
;running, dual mode (one client's memory), "none (<why>)" (not attached, a new zone being looked at...), an ERR or no
;answer: NavMobsWhy says why, and after an ERR or no answer it isn't asked again for 5 s
NavMobs(goalLine := "", timeoutMs := 400)
	{
	global NavMobsWhy, NavMobsWaitUntil ; (v1 globals it sets)
	NavMobsWhy := ""
	if (!Stat("navmem"))
		{
		NavMobsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavMobsWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavMobsWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavMobsWaitUntil && A_TickCount < NavMobsWaitUntil)
		{
		NavMobsWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nmAns := VisionGet("/mobs" (goalLine != "" ? "?goal=" NavUri(SubStr(goalLine, 1, 160)) : ""), timeoutMs, true)
	if (nmAns = "")
		{
		NavMobsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavMobsWaitUntil := A_TickCount + 5000
		return ""
		}
	NavMobsWaitUntil := 0
	nmOut := []
	Loop Parse, nmAns, "`n", "`r"
		{
		nmF := StrSplit(A_LoopField, "|")
		;(none: no mobs in the zone - "none (<why>)": they can't be read now)
		if (Trim(A_LoopField) = "none")
			{
			NavMobsWhy := "no mobs in the zone"
			return []
			}
		if (SubStr(A_LoopField, 1, 5) = "none ")
			{
			NavMobsWhy := Trim(RegExReplace(Trim(A_LoopField), "^none\s*\(?|\)$"))
			return ""
			}
		if (V1At(nmF, 1) != "mob" || nmF.Length < 8)   ; (v1: an empty line's first field read blank)
			continue
		nmM := V1Obj({name: Trim(nmF[2]), x: NavNum(nmF[3]), y: NavNum(nmF[4]), z: NavNum(nmF[5]), dist: NavNum(nmF[6]), quest: nmF[7] = 1 ? 1 : 0
			, off: NavNum(nmF[8]), title: "", rank: "", health: "", school: "", boss: "", gid: "", named: "", template: "", vx: "", vy: "", moving: ""})
		;(9-14: what it is - an older helper's lines have none)
		if (nmF.Length >= 14)
			nmM.title := Trim(nmF[9]), nmM.rank := NavNum(nmF[10]), nmM.health := NavNum(nmF[11]), nmM.school := Trim(nmF[12])
				, nmM.boss := (nmF[13] = "1" ? 1 : nmF[13] = "0" ? 0 : ""), nmM.gid := Trim(nmF[14])
		;(15: the quest's by its name or its goal - an older helper's lines stop at 14)
		if (nmF.Length >= 15)
			nmM.named := (Trim(nmF[15]) = "1" ? 1 : Trim(nmF[15]) = "0" ? 0 : "")
		;(16: its template's name - CL-DeepOne-GreenHead-R10; a blocked way's guards are known by it, Puzzle.ahk - an older helper's
		;lines stop at 15)
		if (nmF.Length >= 16)
			nmM.template := Trim(nmF[16])
		;(17-19: how it moves - its speed along x and y, walking 1 / standing 0, "" not known; an older helper's lines stop at 16)
		if (nmF.Length >= 19)
			nmM.vx := NavNum(nmF[17]), nmM.vy := NavNum(nmF[18]), nmM.moving := (Trim(nmF[19]) = "1" ? 1 : Trim(nmF[19]) = "0" ? 0 : "")
		nmOut.Push(nmM)
		}
	return nmOut
	}

;The zone's things from the game's memory (the helper's /items - READ-ONLY, vision\navmem.py; with far the zone's own file
;too, vision\placements.py), nearest first, as an array of {name, x, y, z, dist (from the wizard), quest (1: the quest's
;goal is about it - the helper's verdict: the goal's own key (NavGoal's itemkey), else - an exact goal - its item, or a
;talk goal's NPC, as the thing's whole name, else the goal's line naming it; goalLine, the line read off the screen, only
;when the memory's can't be read), gid (a number in memory; a placement of the file's "f:<template>:<n>" - it turns into
;the live gid once in reach: remember used or skipped ones by template and place, not gid), key (its display key),
;template, src (mem: in the game's memory now; file: where the zone's file places it - far only), kind (item: lying about,
;picked up on contact; object: used, opened, read - Inactive Protector; npc; ambient: a mob's name on something that
;doesn't fight)}. An older helper's lines (8 fields): key and template "", src mem, kind item (all it listed). far: the
;zone file's things the memory doesn't hold too (it holds only those within ~6.7k; the file is read in a thread at each
;zone change - till then the live ones only; a used or picked-up one stays in the file). [] when there are none; "" when
;they can't be read - navmem:0, the helper not running, "none (<why>)" (not attached, a new zone being looked at, the
;zone's file being read...), an ERR or no answer: NavItemsWhy says why, and after an ERR or no answer it isn't asked
;again for 5 s
NavItems(goalLine := "", far := false, timeoutMs := 2500)
	{
	global NavItemsWhy, NavItemsWaitUntil ; (v1 globals it sets)
	NavItemsWhy := ""
	if (!Stat("navmem"))
		{
		NavItemsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavItemsWhy := "the vision helper isn't running"
		return ""
		}
	if (NavItemsWaitUntil && A_TickCount < NavItemsWaitUntil)
		{
		NavItemsWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	niAns := VisionGet("/items?goal=" NavUri(SubStr(goalLine, 1, 160)) (far ? "&far=1" : ""), timeoutMs, true)
	if (niAns = "")
		{
		NavItemsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavItemsWaitUntil := A_TickCount + 5000
		return ""
		}
	NavItemsWaitUntil := 0
	niOut := []
	Loop Parse, niAns, "`n", "`r"
		{
		;(none: nothing in the zone - "none (<why>)": they can't be read now)
		if (Trim(A_LoopField) = "none")
			{
			NavItemsWhy := "nothing in the zone"
			return []
			}
		if (SubStr(A_LoopField, 1, 5) = "none ")
			{
			NavItemsWhy := Trim(RegExReplace(Trim(A_LoopField), "^none\s*\(?|\)$"))
			return ""
			}
		niF := StrSplit(A_LoopField, "|")
		if (V1At(niF, 1) != "item" || niF.Length < 8)   ; (v1: an empty line's first field read blank)
			continue
		niT := V1Obj({name: Trim(niF[2]), x: NavNum(niF[3]), y: NavNum(niF[4]), z: NavNum(niF[5]), dist: NavNum(niF[6])
			, quest: niF[7] = 1 ? 1 : 0, gid: Trim(niF[8]), key: "", template: "", src: "mem", kind: "item"})
		;(9-12: its key, template, where it's from, its kind - an older helper's lines stop at 8)
		if (niF.Length >= 11)
			niT.key := Trim(niF[9]), niT.template := Trim(niF[10]), niT.src := Trim(niF[11]), niT.kind := niF.Length >= 12 ? Trim(niF[12]) : ""
		niOut.Push(niT)
		}
	return niOut
	}

;The battle's participants from the game's memory (the helper's /battle - READ-ONLY, vision\bossmem.py), in a battle's
;planning phase: {me: the wizard's own (or ""), foes: the other side's, parts: all} - each {me (1 the wizard's own), team,
;name (the mob's - "" a wizard), health, max, boss (1: the game's own boss flag), title, rank, school (its mob's - "" not
;known), player (1 a wizard), gid, x (the middle of its plate across the game's window, 0..1 - "" not read or an older
;helper), l, t, r, b (v1.0.0: its plate's box across and down the game's window, 0..1 each - "" not read or an older
;helper; NavPlatePx turns it into pixels - NOT CHECKED against the screen yet), hide (1: the game hides its health -
;m_HideCurrentHP: its health may not be what the plate shows; 0 not, "" not read)}. "" when it can't be read - navmem:0,
;the helper not running or older (no /battle), dual
;mode, not in a battle's planning phase, the readers being made: NavBattleWhy says why (after an ERR or no answer not
;asked again for 5 s; an older helper's "unknown request": 60 s)
NavBattle(timeoutMs := 700)
	{
	global NavBattleWhy, NavBattleWaitUntil ; (v1 globals it sets)
	NavBattleWhy := ""
	if (!Stat("navmem"))
		{
		NavBattleWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavBattleWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavBattleWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavBattleWaitUntil && A_TickCount < NavBattleWaitUntil)
		{
		NavBattleWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nbAns := VisionGet("/battle", timeoutMs, true)
	if (nbAns = "")
		{
		NavBattleWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavBattleWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavBattleWaitUntil := 0
	nbOut := V1Obj({me: "", foes: [], parts: []})
	Loop Parse, nbAns, "`n", "`r"
		{
		nbF := StrSplit(A_LoopField, "|")
		;(v1: an empty line's first field read blank)
		if (V1At(nbF, 1) = "none")
			{
			NavBattleWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (V1At(nbF, 1) != "part" || nbF.Length < 12)
			continue
		nbP := V1Obj({me: nbF[2] = 1 ? 1 : 0, team: NavNum(nbF[3]), name: Trim(nbF[4]), health: NavNum(nbF[5]), max: NavNum(nbF[6])
			, boss: (nbF[7] = "1" ? 1 : nbF[7] = "0" ? 0 : ""), title: Trim(nbF[8]), rank: NavNum(nbF[9]), school: Trim(nbF[10])
			, player: nbF[11] = 1 ? 1 : 0, gid: Trim(nbF[12]), x: nbF.Length >= 13 ? NavNum(nbF[13]) : ""
			, l: NavNum(V1At(nbF, 14)), t: NavNum(V1At(nbF, 15)), r: NavNum(V1At(nbF, 16)), b: NavNum(V1At(nbF, 17))
			, hide: (V1At(nbF, 18) = "1" ? 1 : V1At(nbF, 18) = "0" ? 0 : "")})
		nbOut.parts.Push(nbP)
		if (nbP.me && !IsObject(nbOut.me))
			nbOut.me := nbP
		}
	if (!IsObject(nbOut.me))
		{
		NavBattleWhy := "an odd answer (no line for the wizard): " SubStr(RegExReplace(nbAns, "\s+", " "), 1, 60)
		return ""
		}
	;(the other side: another team than the wizard's - a team not read: not a wizard of the game's)
	for nbI, nbP in nbOut.parts
		if (!nbP.me && (nbOut.me.team = "" || nbP.team = "" ? !nbP.player : nbP.team != nbOut.me.team))
			nbOut.foes.Push(nbP)
	return nbOut
	}

;A participant's plate (NavBattle's, p one of its parts) in screen pixels: x, y the middle of its box (fractions of the game's
;window, as /battle gives them). False, x and y "": the box not read (an older helper, the wizard's own read without its
;window), not inside the window, or empty. It clicks nothing: a click there (memclicks, off) is the caller's
NavPlatePx(p, &x, &y)
	{
	x := "", y := ""
	if (!IsObject(p) || p.l = "" || p.t = "" || p.r = "" || p.b = "" || p.r <= p.l || p.b <= p.t || GameW <= 0)
		return false
	if (p.l < -0.002 || p.t < -0.002 || p.r > 1.002 || p.b > 1.002)
		return false
	x := Round(GameLeft + (p.l + p.r) / 2 * GameW), y := Round(GameTop + (p.t + p.b) / 2 * GameH)
	return true
	}

;The round's phase from the game's memory, cheaply (the helper's /phase - READ-ONLY, vision\handmem.py HandMem.phase: no
;spell read, about a ms): {state ("none" not in a battle, "round" in one out of the planning phase, "waiting" planning with
;no card shown but cards in the hand - one's chosen, "changing" the cards shown not as many as the hand, "hand" as many),
;inBattle, planning (1/0), shown, own (card windows shown, those but the pet's), size (the hand list's), ms, why}. ""
;when it can't be read - navmem:0, the helper not running or older (no /phase), dual mode, the game not read: VisionPhaseWhy
;says why (after an ERR or no answer not asked again for 5 s; an older helper's "unknown request": 60 s).
;v1.0.0: read for the log only (Autofarmer.ahk CastPhaseShadow) - nothing acts on it till what the hand does between a
;card's click and its target's, and after a cast goes out, has been seen in the game (TODO.md goal 3: the cast checks and
;the round's start from memory - TargetPending, CastWentOut, BattleLoop's TestRound)
VisionPhase(timeoutMs := 300)
	{
	global VisionPhaseWhy, VisionPhaseWaitUntil ; (v1 globals it sets)
	VisionPhaseWhy := ""
	if (!Stat("navmem") || !VisionOn || dualmode == 1)
		{
		VisionPhaseWhy := !Stat("navmem") ? "navmem:0 in PlayerStats.txt" : !VisionOn ? "the vision helper isn't running" : "dual mode: the game's memory is one client's"
		return ""
		}
	if (VisionPhaseWaitUntil && A_TickCount < VisionPhaseWaitUntil)
		{
		VisionPhaseWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	vpAns := Trim(VisionGet("/phase", timeoutMs, true), " `t`r`n")
	if (vpAns = "")
		{
		VisionPhaseWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		VisionPhaseWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	VisionPhaseWaitUntil := 0
	vpF := StrSplit(vpAns, "|")
	;(v1: a field that isn't there read blank)
	if (V1At(vpF, 1) = "none")
		{
		VisionPhaseWhy := Trim(SubStr(vpAns, 6))
		return ""
		}
	if (V1At(vpF, 1) != "phase" || vpF.Length < 8)
		{
		VisionPhaseWhy := "an odd answer: " SubStr(vpAns, 1, 60)
		return ""
		}
	return V1Obj({state: Trim(vpF[2]), inBattle: vpF[3] = "1" ? 1 : 0, planning: vpF[4] = "1" ? 1 : 0, shown: NavNum(vpF[5]), own: NavNum(vpF[6])
		, size: NavNum(vpF[7]), ms: NavNum(vpF[8]), why: Trim(V1At(vpF, 9))})
	}

;The game's UI scale from its memory (the helper's /uiroot - READ-ONLY: the GUI root's size in GUI units, vision\navmem.py
;ui_root): a card's pitch is 67 GUI units at any size and 82 px at UI scale 1 (HalfPitch 41), so UiScale = GameW / the
;root's width x 67 / 82 - 2560 / 1827 x 67 / 82 = 1.145 at 1440p borderless, where the cut pictures say 1.144. NavUiRootW
;the width read. "" when it can't be read (navmem:0, the helper not running or older, dual mode, the game not in the world
;yet): NavUiWhy says why - not asked again for 60 s after a failure
NavUiScale(timeoutMs := 500)
	{
	global NavUiWhy, NavUiWaitUntil, NavUiRootW ; (v1 globals it sets)
	NavUiWhy := ""
	if (!Stat("navmem") || !VisionOn || dualmode == 1)
		{
		NavUiWhy := !Stat("navmem") ? "navmem:0 in PlayerStats.txt" : !VisionOn ? "the vision helper isn't running" : "dual mode"
		return ""
		}
	if (NavUiWaitUntil && A_TickCount < NavUiWaitUntil)
		{
		NavUiWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nuAns := Trim(VisionGet("/uiroot", timeoutMs, true), " `t`r`n")
	nuF := StrSplit(nuAns, "|")
	;(v1: a field that isn't there - an empty answer's first - read blank)
	if (V1At(nuF, 1) != "root" || NavNum(V1At(nuF, 2)) = "" || NavNum(V1At(nuF, 2)) <= 0 || GameW <= 0)
		{
		NavUiWhy := nuAns = "" ? (VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")) : V1At(nuF, 1) = "none" ? Trim(SubStr(nuAns, 6)) : "an odd answer: " SubStr(nuAns, 1, 40)
		NavUiWaitUntil := A_TickCount + 60000
		return ""
		}
	NavUiWaitUntil := 0, NavUiRootW := NavNum(nuF[2])
	return GameW / NavUiRootW * 67 / 82
	}

;A cross-check of the picture set in use (UiScale) against the game's memory's UI scale (NavUiScale) - nothing is switched
;on it yet: a disagreement over 0.8% is logged, once per window size and set (tonight's 1.130 against the memory's 1.145
;would have been). Asked at a round's start (the main loop), till the memory answers for that size and set
PicMemCheck()
	{
	static done := V1Obj()
	pmcKey := GameW "x" GameH "|" PicSet
	if (done.Has(pmcKey) || !IsObject(PicSets) || !IsObject(V1At(PicSets, PicSet)))   ; (v1: no such set - blank)
		return
	pmcSc := NavUiScale()
	if (pmcSc = "")
		return
	done[pmcKey] := 1
	if (Abs(pmcSc / UiScale - 1) > 0.008)
		DebugLog("UI size: the game's memory says UI scale " Round(pmcSc, 3) " (its GUI " NavUiRootW " units wide in a " GameW " px window) - the pictures in use are at " Round(UiScale, 3) " (" (PicSet = 1 ? "the main set" : SubStr(PicDir, (StrLen(A_WorkingDir) + 2)<1 ? (StrLen(A_WorkingDir) + 2)-1 : (StrLen(A_WorkingDir) + 2))) "): they disagree - nothing switched on it (only a cross-check for now)")
	}

;The backpack from the game's memory (the helper's /bag - READ-ONLY, vision\bagmem.py: nothing in the game is written,
;injected or hooked; no key, click or window), as an object: items (the backpack list's own count - emotes too), allowed
;(its size: 150), extra, gold, goldMax (the pouch), gid (the character's id, hex), walked (items read), emotes, setsOk (1:
;every Equipment Set and its items read, every item walked - QuickSell.ahk sells nothing without it), space
;({n, m, text}: the backpack page's own "N/M" - only while that page is shown - else ""), cats ({kind: {n, crowns,
;nosell, plain}} - deck, hat, robe, shoes, weapon, athame, amulet, ring, pet, mount, emote...; ? not read; crowns: a Crowns
;item or a Crown-shop template's, or one whose name wasn't read; plain: neither crowns nor unsellable), crownShop ([{kind,
;name}]: Crown-shop templates without the game's Crowns flag, and items whose name wasn't read), tips ([{i, shown, l,
;t, r, b, image, button, name}]: the HUD's right-hand icons - Prospector Zeke's portrait: the backpack full, or the gold
;bag nearly full), sets ([{n, equipped, ids, name}]), setItems ([{set, equipped, gid, tid, name, kind, crowns}]: the
;Equipment Sets' items in the backpack), rootW, rootH (the game's GUI in its own units). "" when it can't be read -
;navmem:0, the helper not running or older (no /bag), dual mode, "none|<why>" (not in the world, the reader being
;made): NavBagWhy says why (after an ERR or no answer not asked again for 5 s; an older helper's "unknown request": 60 s)
NavBag(timeoutMs := 600)
	{
	global NavBagWhy, NavBagWaitUntil ; (v1 globals it sets)
	NavBagWhy := ""
	if (!Stat("navmem"))
		{
		NavBagWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavBagWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavBagWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavBagWaitUntil && A_TickCount < NavBagWaitUntil)
		{
		NavBagWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nbgAns := VisionGet("/bag", timeoutMs, true)
	if (nbgAns = "")
		{
		NavBagWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavBagWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavBagWaitUntil := 0
	nbgOut := V1Obj({items: "", allowed: "", extra: "", gold: "", goldMax: "", gid: "", walked: "", emotes: "", setsOk: 0, space: "", cats: V1Obj()
		, tips: [], sets: [], setItems: [], crownShop: [], rootW: "", rootH: ""})
	Loop Parse, nbgAns, "`n", "`r"
		{
		nbgF := StrSplit(A_LoopField, "|")
		if (V1At(nbgF, 1) = "none")
			{
			NavBagWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (V1At(nbgF, 1) = "bag" && nbgF.Length >= 7)
			nbgOut.items := NavNum(V1At(nbgF, 2)), nbgOut.allowed := NavNum(V1At(nbgF, 3)), nbgOut.extra := NavNum(V1At(nbgF, 4)), nbgOut.gold := NavNum(V1At(nbgF, 5))
				, nbgOut.goldMax := NavNum(V1At(nbgF, 6)), nbgOut.gid := Trim(V1At(nbgF, 7)), nbgOut.walked := NavNum(V1At(nbgF, 8)), nbgOut.emotes := NavNum(V1At(nbgF, 9))
				, nbgOut.setsOk := V1At(nbgF, 10) = "1" ? 1 : 0
		else if (V1At(nbgF, 1) = "space" && NavNum(V1At(nbgF, 2)) != "" && NavNum(V1At(nbgF, 3)) != "")
			nbgOut.space := V1Obj({n: NavNum(V1At(nbgF, 2)), m: NavNum(V1At(nbgF, 3)), text: Trim(V1At(nbgF, 4))})
		else if (V1At(nbgF, 1) = "cat" && Trim(V1At(nbgF, 2)) != "")
			nbgOut.cats[Trim(V1At(nbgF, 2))] := V1Obj({n: NavNum(V1At(nbgF, 3)), crowns: NavNum(V1At(nbgF, 4)), nosell: NavNum(V1At(nbgF, 5)), plain: NavNum(V1At(nbgF, 6))})
		else if (V1At(nbgF, 1) = "crownshop" && Trim(V1At(nbgF, 3)) != "")
			nbgOut.crownShop.Push(V1Obj({kind: Trim(V1At(nbgF, 2)), name: Trim(V1At(nbgF, 3))}))
		else if (V1At(nbgF, 1) = "tip")
			nbgOut.tips.Push(V1Obj({i: NavNum(V1At(nbgF, 2)), shown: V1At(nbgF, 3) = "1" ? 1 : 0, l: NavNum(V1At(nbgF, 4)), t: NavNum(V1At(nbgF, 5)), r: NavNum(V1At(nbgF, 6))
				, b: NavNum(V1At(nbgF, 7)), image: Trim(V1At(nbgF, 8)), button: Trim(V1At(nbgF, 9)), name: Trim(V1At(nbgF, 10))}))
		else if (V1At(nbgF, 1) = "set")
			nbgOut.sets.Push(V1Obj({n: NavNum(V1At(nbgF, 2)), equipped: V1At(nbgF, 3) = "1" ? 1 : 0, ids: NavNum(V1At(nbgF, 4)), name: Trim(V1At(nbgF, 5))}))
		else if (V1At(nbgF, 1) = "setitem")
			nbgOut.setItems.Push(V1Obj({set: NavNum(V1At(nbgF, 2)), equipped: V1At(nbgF, 3) = "1" ? 1 : 0, gid: Trim(V1At(nbgF, 4)), tid: NavNum(V1At(nbgF, 5))
				, name: Trim(V1At(nbgF, 6)), kind: Trim(V1At(nbgF, 7)), crowns: V1At(nbgF, 8) = "1" ? 1 : 0}))
		else if (V1At(nbgF, 1) = "root")
			nbgOut.rootW := NavNum(V1At(nbgF, 2)), nbgOut.rootH := NavNum(V1At(nbgF, 3))
		}
	if (nbgOut.items = "" || nbgOut.allowed = "")
		{
		NavBagWhy := "an odd answer (no backpack line): " SubStr(RegExReplace(nbgAns, "\s+", " "), 1, 60)
		return ""
		}
	return nbgOut
	}

;The game's windows from its memory (the helper's /gui - READ-ONLY, vision\bagmem.py), paths: "Anc/Name,..." (a window
;named Name with an ancestor named Anc - more ancestors allowed, in order; 40 at most). An object: rootW, rootH (the GUI
;in its own units - the game's client area), win ({path: {found, type, shown (VISIBLE on it and every ancestor), l, t, r,
;b (in the root's units), checked, greyed (1/0, "" not one), text (its words, the markup out), key (the .gui file's
;"<string;KEY>" when that's all its text), dups (its shown matches), pl, pt, pr, pb (its parent's), matches}}), box
;(the message box up: {shown, title, caption, titleKey, captionKey, count - how many are up}; shown 0 none), btns
;([{name, label, l, t, r, b, key, greyed}]: its shown buttons - centerButton, leftButton, rightButton). "" when it can't be
;read - as NavBag: NavGuiWhy
NavGui(paths, timeoutMs := 600)
	{
	global NavGuiWhy, NavGuiWaitUntil ; (v1 globals it sets)
	NavGuiWhy := ""
	if (!Stat("navmem"))
		{
		NavGuiWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavGuiWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavGuiWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavGuiWaitUntil && A_TickCount < NavGuiWaitUntil)
		{
		NavGuiWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nguAns := VisionGet("/gui?w=" paths, timeoutMs, true)
	if (nguAns = "")
		{
		NavGuiWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavGuiWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavGuiWaitUntil := 0
	nguOut := V1Obj({rootW: "", rootH: "", win: V1Obj(), box: V1Obj({shown: 0, title: "", caption: "", titleKey: "", captionKey: ""}), btns: []})
	Loop Parse, nguAns, "`n", "`r"
		{
		nguF := StrSplit(A_LoopField, "|")
		if (V1At(nguF, 1) = "none")
			{
			NavGuiWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (V1At(nguF, 1) = "root")
			nguOut.rootW := NavNum(V1At(nguF, 2)), nguOut.rootH := NavNum(V1At(nguF, 3))
		else if (V1At(nguF, 1) = "win" && nguF.Length >= 18)
			nguOut.win[Trim(V1At(nguF, 2))] := V1Obj({found: Trim(V1At(nguF, 3)) != "" ? 1 : 0, type: Trim(V1At(nguF, 3)), shown: V1At(nguF, 4) = "1" ? 1 : 0, l: NavNum(V1At(nguF, 5)), t: NavNum(V1At(nguF, 6))
				, r: NavNum(V1At(nguF, 7)), b: NavNum(V1At(nguF, 8)), checked: NavNum(V1At(nguF, 9)), greyed: NavNum(V1At(nguF, 10)), text: Trim(V1At(nguF, 11)), key: Trim(V1At(nguF, 12))
				, dups: NavNum(V1At(nguF, 13)), pl: NavNum(V1At(nguF, 14)), pt: NavNum(V1At(nguF, 15)), pr: NavNum(V1At(nguF, 16)), pb: NavNum(V1At(nguF, 17)), matches: NavNum(V1At(nguF, 18))})
		else if (V1At(nguF, 1) = "box")
			nguOut.box := V1Obj({shown: V1At(nguF, 2) = "1" ? 1 : 0, title: Trim(V1At(nguF, 3)), caption: Trim(V1At(nguF, 4)), titleKey: Trim(V1At(nguF, 5)), captionKey: Trim(V1At(nguF, 6)), count: NavNum(V1At(nguF, 7))})
		else if (V1At(nguF, 1) = "btn" && nguF.Length >= 9)
			nguOut.btns.Push(V1Obj({name: Trim(V1At(nguF, 2)), label: Trim(V1At(nguF, 3)), l: NavNum(V1At(nguF, 4)), t: NavNum(V1At(nguF, 5)), r: NavNum(V1At(nguF, 6)), b: NavNum(V1At(nguF, 7))
				, key: Trim(V1At(nguF, 8)), greyed: NavNum(V1At(nguF, 9))}))
		}
	if (nguOut.rootW = "" || nguOut.rootW <= 0 || nguOut.rootH = "" || nguOut.rootH <= 0)
		{
		NavGuiWhy := "an odd answer (no root line): " SubStr(RegExReplace(nguAns, "\s+", " "), 1, 60)
		return ""
		}
	return nguOut
	}

;Every window under one from the game's memory (the helper's /guitree - READ-ONLY, vision\bagmem.py's tree): the names
;of a window's buttons, lists and a box's keys nobody has looked at yet, and the rows of a list (a trainer's spells, the
;quest book's entries). Nothing calls it yet - it's there for the readers still to be written (pets, gear, quests,
;puzzles: TODO.md); "python vision\bagmem.py --tree --under Anc/Name" is the same reading for a person. under: "Anc/Name"
;(a window named Name with an ancestor named Anc - more ancestors allowed, in order; the first shown match), "" the GUI
;root (the whole tree can take a while: ask under a window - only its windows are walked and described, though every
;window is still read once to find it, as NavGui does); withHidden: hidden windows too (else only those shown - VISIBLE
;on it and every ancestor - and a hidden window's windows not even read); depth: that many levels below it at most
;("" 24 - deeper ones left out: capped). An object: rootW, rootH (the GUI in its own units), under, matches (windows
;under names among those read - 0 none: no rows), dups (its shown matches), walked (windows read), capped (1: cut
;short - under it: ask under a window lower down; with matches 0 the window may be past where finding it stopped -
;not "no such window"), all (1: hidden ones listed), rows ([{depth (0 the window
;asked for), name, type, shown, l, t, r, b (in the root's units), text (its words, the markup out), key (the .gui file's
;"<string;KEY>" when that's all its text), greyed, checked (1/0, "" not a button / check box), tex (a sprite's or a
;button's texture file), kids (its children, hidden ones too), parent (its parent's index in rows, 0 the top one), flags
;(m_Flags in hex, bit 0 VISIBLE)}] in the game's order: an ancestor before its windows). "" when it can't be read - as
;NavGui: NavGuiTreeWhy (after an ERR or no answer not asked again for 5 s; an older helper's "unknown request": 60 s)
NavGuiTree(under := "", withHidden := false, depth := "", timeoutMs := 1500)
	{
	global NavGuiTreeWhy, NavGuiTreeWaitUntil ; (v1 globals it sets)
	NavGuiTreeWhy := ""
	if (!Stat("navmem"))
		{
		NavGuiTreeWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavGuiTreeWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavGuiTreeWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavGuiTreeWaitUntil && A_TickCount < NavGuiTreeWaitUntil)
		{
		NavGuiTreeWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	ngtAns := VisionGet("/guitree?under=" NavUri(under) (withHidden ? "&all=1" : "") (depth != "" ? "&depth=" depth : ""), timeoutMs, true)
	if (ngtAns = "")
		{
		NavGuiTreeWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavGuiTreeWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavGuiTreeWaitUntil := 0
	ngtOut := V1Obj({rootW: "", rootH: "", under: "", matches: "", dups: "", walked: "", capped: 0, all: 0, rows: []})
	Loop Parse, ngtAns, "`n", "`r"
		{
		ngtF := StrSplit(A_LoopField, "|")
		if (V1At(ngtF, 1) = "none")
			{
			NavGuiTreeWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (V1At(ngtF, 1) = "root")
			ngtOut.rootW := NavNum(V1At(ngtF, 2)), ngtOut.rootH := NavNum(V1At(ngtF, 3))
		else if (V1At(ngtF, 1) = "tree" && ngtF.Length >= 8)
			ngtOut.under := Trim(V1At(ngtF, 2)), ngtOut.matches := NavNum(V1At(ngtF, 3)), ngtOut.dups := NavNum(V1At(ngtF, 4)), ngtOut.walked := NavNum(V1At(ngtF, 6))
				, ngtOut.capped := V1At(ngtF, 7) = "1" ? 1 : 0, ngtOut.all := V1At(ngtF, 8) = "1" ? 1 : 0
		else if (RegExMatch(V1At(ngtF, 1), "^\d+$") && ngtF.Length >= 16)   ; (a window's line: its depth first - every other line a word)
			ngtOut.rows.Push(V1Obj({depth: NavNum(V1At(ngtF, 1)), name: Trim(V1At(ngtF, 2)), type: Trim(V1At(ngtF, 3)), shown: V1At(ngtF, 4) = "1" ? 1 : 0
				, l: NavNum(V1At(ngtF, 5)), t: NavNum(V1At(ngtF, 6)), r: NavNum(V1At(ngtF, 7)), b: NavNum(V1At(ngtF, 8)), text: Trim(V1At(ngtF, 9)), key: Trim(V1At(ngtF, 10))
				, greyed: NavNum(V1At(ngtF, 11)), checked: NavNum(V1At(ngtF, 12)), tex: Trim(V1At(ngtF, 13)), kids: NavNum(V1At(ngtF, 14)), parent: NavNum(V1At(ngtF, 15))
				, flags: Trim(V1At(ngtF, 16))}))
		}
	if (ngtOut.rootW = "" || ngtOut.rootW <= 0 || ngtOut.matches = "")
		{
		NavGuiTreeWhy := "an odd answer (no root / tree line): " SubStr(RegExReplace(ngtAns, "\s+", " "), 1, 60)
		return ""
		}
	return ngtOut
	}

;The worn gear and the backpack's from the game's memory, with the helper's swap plan (its /gear - READ-ONLY,
;vision\gearmem.py and gearrank.py: nothing in the game is written, injected or hooked; no key, click or window - the
;stats are NOT CONFIRMED in the game yet: the plan is advice). query: /gear's arguments without the "?" (Gear.ahk
;GearQuery: school, level, role, the totals; run=&mark=1 / end=1 (nomark=1) for a dungeon run's drop log). An object:
;wornN, bagN (gear of the planned slots - and pieces whose template couldn't be read: verdict unknown, slot ""),
;bagItems (every item), level, school, role, setsOk, why (gear| line), worn ([{slot, gid, tid, name, display, level,
;stats, sets}]), items ([{gid, tid, name, display, slot, verdict (better, not better, can't wear, in a set, unknown),
;delta, basis, why, stats, reqs, crowns, nosell, sets}]), plan ([{slot, gid, tid, name, wornGid, wornName, delta (% -
;basis stats; levels - basis level), basis (stats, level, empty), held (1: the worn piece is in an Equipment Set),
;why}]), notes ([text]), drops ([{tid, name, slot, display, count, first}]: a run's new pieces - count read as V1At(d,
;"count"): d.count is the Map's own Count), run ({name, runs, dry, stopafter, done, why, new, marked} - "" without
;run=), better / unknown / judged (the items' verdicts counted: judged - every verdict but unknown). "" when it can't be
;read - navmem:0, the helper not running or older (no /gear), dual mode, "none|<why>" (not in the world, the reader
;being made - once a game, about a second): NavGearWhy says why (after an ERR or no answer not asked again for 5 s; an
;older helper's "unknown request": 60 s)
NavGear(query := "", timeoutMs := 5000)
	{
	global NavGearWhy, NavGearWaitUntil ; (v1 globals it sets)
	NavGearWhy := ""
	if (!Stat("navmem"))
		{
		NavGearWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavGearWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavGearWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavGearWaitUntil && A_TickCount < NavGearWaitUntil)
		{
		NavGearWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	ngrAns := VisionGet("/gear" (query != "" ? "?" query : ""), timeoutMs, true)
	if (ngrAns = "")
		{
		NavGearWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavGearWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavGearWaitUntil := 0
	ngrOut := V1Obj({wornN: "", bagN: "", bagItems: "", level: "", school: "", role: "", setsOk: 0, why: "", worn: [], items: [], plan: []
		, notes: [], drops: [], run: "", better: 0, unknown: 0, judged: 0})
	ngrGot := 0
	Loop Parse, ngrAns, "`n", "`r"
		{
		ngrF := StrSplit(A_LoopField, "|")
		ngrK := V1At(ngrF, 1)
		if (ngrK = "none")
			{
			NavGearWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (ngrK = "gear" && ngrF.Length >= 10)
			ngrGot := 1, ngrOut.wornN := NavNum(V1At(ngrF, 2)), ngrOut.bagN := NavNum(V1At(ngrF, 3)), ngrOut.bagItems := NavNum(V1At(ngrF, 4)), ngrOut.level := NavNum(V1At(ngrF, 5))
				, ngrOut.school := Trim(V1At(ngrF, 6)), ngrOut.role := Trim(V1At(ngrF, 7)), ngrOut.setsOk := V1At(ngrF, 8) = "1" ? 1 : 0, ngrOut.why := Trim(V1At(ngrF, 10))
		else if (ngrK = "worn" && ngrF.Length >= 9)
			ngrOut.worn.Push(V1Obj({slot: Trim(V1At(ngrF, 2)), gid: Trim(V1At(ngrF, 3)), tid: NavNum(V1At(ngrF, 4)), name: Trim(V1At(ngrF, 5)), display: Trim(V1At(ngrF, 6))
				, level: NavNum(V1At(ngrF, 7)), stats: Trim(V1At(ngrF, 8)), sets: Trim(V1At(ngrF, 9))}))
		else if (ngrK = "item" && ngrF.Length >= 15)
			{
			ngrV := Trim(V1At(ngrF, 7))
			ngrOut.items.Push(V1Obj({gid: Trim(V1At(ngrF, 2)), tid: NavNum(V1At(ngrF, 3)), name: Trim(V1At(ngrF, 4)), display: Trim(V1At(ngrF, 5)), slot: Trim(V1At(ngrF, 6))
				, verdict: ngrV, delta: NavNum(V1At(ngrF, 8)), basis: Trim(V1At(ngrF, 9)), why: Trim(V1At(ngrF, 10)), stats: Trim(V1At(ngrF, 11)), reqs: Trim(V1At(ngrF, 12))
				, crowns: V1At(ngrF, 13) = "1" ? 1 : 0, nosell: V1At(ngrF, 14) = "1" ? 1 : 0, sets: Trim(V1At(ngrF, 15))}))
			;(each verdict counted: better ones hold a quick sell, unknown ones too - Gear.ahk GearSellOk)
			if (ngrV = "better")
				ngrOut.better += 1
			if (ngrV = "unknown")
				ngrOut.unknown += 1
			else if (ngrV != "")
				ngrOut.judged += 1
			}
		else if (ngrK = "plan" && ngrF.Length >= 11)
			ngrOut.plan.Push(V1Obj({slot: Trim(V1At(ngrF, 2)), gid: Trim(V1At(ngrF, 3)), tid: NavNum(V1At(ngrF, 4)), name: Trim(V1At(ngrF, 5)), wornGid: Trim(V1At(ngrF, 6))
				, wornName: Trim(V1At(ngrF, 7)), delta: NavNum(V1At(ngrF, 8)), basis: Trim(V1At(ngrF, 9)), held: V1At(ngrF, 10) = "1" ? 1 : 0, why: Trim(V1At(ngrF, 11))}))
		else if (ngrK = "note")
			ngrOut.notes.Push(Trim(SubStr(A_LoopField, 6)))
		else if (ngrK = "drop" && ngrF.Length >= 7)
			ngrOut.drops.Push(V1Obj({tid: NavNum(V1At(ngrF, 2)), name: Trim(V1At(ngrF, 3)), slot: Trim(V1At(ngrF, 4)), display: Trim(V1At(ngrF, 5)), count: NavNum(V1At(ngrF, 6))
				, first: Trim(V1At(ngrF, 7))}))
		else if (ngrK = "run" && ngrF.Length >= 9)
			ngrOut.run := V1Obj({name: Trim(V1At(ngrF, 2)), runs: NavNum(V1At(ngrF, 3)), dry: NavNum(V1At(ngrF, 4)), stopafter: NavNum(V1At(ngrF, 5)), done: V1At(ngrF, 6) = "1" ? 1 : 0
				, why: Trim(V1At(ngrF, 7)), new: NavNum(V1At(ngrF, 8)), marked: V1At(ngrF, 9) = "1" ? 1 : 0})
		}
	if (!ngrGot)
		{
		NavGearWhy := "an odd answer (no gear line): " SubStr(RegExReplace(ngrAns, "\s+", " "), 1, 60)
		return ""
		}
	return ngrOut
	}

;The wizard's pets from the game's memory (the helper's /pets - READ-ONLY, vision\petmem.py: nothing in the game is
;written, injected or hooked; no key, click or window) and which of them to keep out of Quick Sell (vision\petplan.py -
;goal 6, perfect pets: QuickSell.ahk QsPetGuard). want: the wanted talents ("Spell-Proof, Mighty, ..." - pets.txt's
;want: line, QsPetWant); hatch: 1 hatching on (the pets still in training and the best pair of parents kept too). An
;object: pets ([{gid (hex), where (equipped / backpack), level (1 Baby ... 7 Ultra), levelName, tid, name (its template's
;object name: PET_SwordShield_01), display (as the game names it), cards (its level's power cards: "name*copies,..."),
;xp, xpNext, talents, derby (arrays of names; "" not read), stats, maxStats (as read), cls}] - the worn one first),
;energy, energyMax (the wizard's pet energy), whole (1: the worn items and the backpack both read whole, every item's id
;and behaviours too - no pet missed; QsPetGuard also checks the backpack's pets against NavBag's Pet count),
;n, why (what couldn't be read), want ([names] as the helper read them), hatch, keep ({gid: why} - the pets to keep, a pet
;whose talents aren't read among them), keepWhere ({gid: where}). The values not confirmed in the game yet (xp, xpNext,
;talents, derby, stats, maxStats, energy - vision\petmem.py PINS) are "" till they're pinned: nothing acts on them yet.
;"" when it can't be read - navmem:0, the helper not running or older (no /pets), dual mode, "none|<why>" (not in the
;world, the reader being made - once a game, the helper waits 1 s for it): NavPetsWhy says why (after an ERR or no
;answer not asked again for 5 s; an older helper's "unknown request": 60 s)
NavPets(want := "", hatch := 0, timeoutMs := 1500)
	{
	global NavPetsWhy, NavPetsWaitUntil ; (v1 globals it sets)
	NavPetsWhy := ""
	if (!Stat("navmem"))
		{
		NavPetsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavPetsWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavPetsWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavPetsWaitUntil && A_TickCount < NavPetsWaitUntil)
		{
		NavPetsWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	npsAns := VisionGet("/pets?want=" NavUri(want) (hatch ? "&hatch=1" : ""), timeoutMs, true)
	if (npsAns = "")
		{
		NavPetsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavPetsWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavPetsWaitUntil := 0
	npsOut := V1Obj({pets: [], energy: "", energyMax: "", whole: 0, n: "", why: "", want: [], hatch: 0, keep: V1Obj(), keepWhere: V1Obj()})
	Loop Parse, npsAns, "`n", "`r"
		{
		npsF := StrSplit(A_LoopField, "|")
		if (V1At(npsF, 1) = "none")
			{
			NavPetsWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (V1At(npsF, 1) = "pet" && npsF.Length >= 16)
			npsOut.pets.Push(V1Obj({gid: Trim(V1At(npsF, 2)), where: Trim(V1At(npsF, 3)), level: NavNum(V1At(npsF, 4)), levelName: Trim(V1At(npsF, 5)), tid: NavNum(V1At(npsF, 6))
				, name: Trim(V1At(npsF, 7)), display: Trim(V1At(npsF, 8)), cards: Trim(V1At(npsF, 9)), xp: NavNum(V1At(npsF, 10)), xpNext: NavNum(V1At(npsF, 11))
				, talents: NavPetList(V1At(npsF, 12)), derby: NavPetList(V1At(npsF, 13)), stats: Trim(V1At(npsF, 14)), maxStats: Trim(V1At(npsF, 15)), cls: Trim(V1At(npsF, 16))}))
		else if (V1At(npsF, 1) = "energy")
			npsOut.energy := NavNum(V1At(npsF, 2)), npsOut.energyMax := NavNum(V1At(npsF, 3))
		else if (V1At(npsF, 1) = "pets")
			npsOut.n := NavNum(V1At(npsF, 2)), npsOut.whole := V1At(npsF, 3) = "1" ? 1 : 0, npsOut.why := Trim(V1At(npsF, 5))
		else if (V1At(npsF, 1) = "want")
			npsOut.want := NavPetList(V1At(npsF, 3)), npsOut.hatch := V1At(npsF, 4) = "1" ? 1 : 0
		else if (V1At(npsF, 1) = "keep" && Trim(V1At(npsF, 2)) != "")
			npsOut.keep[Trim(V1At(npsF, 2))] := Trim(V1At(npsF, 4)), npsOut.keepWhere[Trim(V1At(npsF, 2))] := Trim(V1At(npsF, 3))
		}
	if (npsOut.n = "")
		{
		NavPetsWhy := "an odd answer (no pets line): " SubStr(RegExReplace(npsAns, "\s+", " "), 1, 60)
		return ""
		}
	return npsOut
	}

;A list field of /pets (talents, derby, want - names joined by commas): its names as an array - [] for "-" (read, none),
;"" not read (empty)
NavPetList(v)
	{
	v := Trim(v)
	if (v = "")
		return ""
	npl := []
	if (v = "-")
		return npl
	for each, nplName in StrSplit(v, ",")
		if (Trim(nplName) != "")
			npl.Push(Trim(nplName))
	return npl
	}

;A battle's first round: the mob that started it, off the mobs the helper read lately (while walking with mob
;avoidance on) - how far away you were and how far off its facing when it noticed you, into debug.log, to measure the
;mobs' real sight against the mobshape / mobradius settings
CaughtLog()
	{
	if (!VisionOn)
		return
	a := VisionGet("/caught", 600, true)
	f := StrSplit(Trim(a, " `r`n"), "|")
	if (V1At(f, 1) != "caught" || f.Length < 6)   ; (v1: an empty answer's first field read blank)
		return
	s := MobShape()
	if (s.wide >= 360)
		where := (V1Le(f[3], s.range) ? "inside" : "outside") " the circle set (" s.range " all round)"
	else if (f[4] = "")
		where := "its facing unknown"
	else
		where := ((V1Le(f[4], s.wide / 2) && V1Le(f[3], s.range)) ? "inside" : "outside") " the " s.name " set (" s.wide " degrees wide, " s.range " long)"
	;(8: it was walking - 1 - or standing - 0 - the second before it noticed you: a walking mob's sight swept ahead of it,
	;vision\navroute.py; an older helper's line stops at 7)
	clWalk := V1At(f, 8) = "1" ? ", walking" : V1At(f, 8) = "0" ? ", standing" : ""
	DebugLog("  Caught by " f[2] clWalk ": " (f[5] = 1 ? "it came for you from " f[3] " away" : "you walked into it (" f[3] " away)")
		. (f[4] != "" ? ", " f[4] " degrees off where it faced" : "") " (" f[6] " s before) - " where)
	MobGrow(f, s)
	}

;Caught by a mob the quest doesn't want (mobgrow, on unless 0): the reach the route keeps out of made bigger, so mobs
;are kept further off from now on - the shape's front (mobradius) when it caught the wizard in front of it (or all round:
;a circle, its facing unknown), its reach all round (mobbody) when from the side or behind - to where it caught him from
;and 25 more, 20 more at the least; 1500 at most (all round past the front: the front raised too). Left as it is when the battle was
;the quest's - collecting, a mob the helper took as the quest's (/caught's quest field: by the game's memory's goal), a mob
;named in the goal line, X pressed in the last 15 s (the goal's boss), a dungeon run that fights every battle - or you were
;playing. f: /caught's fields; s: MobShape()
MobGrow(f, s)
	{
	global MobWalkMs ; (v1 globals it sets)
	if (Stat("mobgrow") = 0 || (Stats.Has("mobavoid") && !Stats["mobavoid"]))
		return
	mgName := f[2], mgDist := V1Round(f[3]), mgOff := f[4]   ; (v1: Round of a blank or text was 0)
	;(collecting: walking into mobs is the point - but not on the way to a quest item lying about: Collect.ahk)
	mgWhy := (WkArrived = 7 && CiGid = "") ? "collecting" : (WkLastX && A_TickCount - WkLastX < 15000) ? "X was just pressed - the goal's battle?"
		: (IsObject(DgRun) && !DgRun.avoid) ? "a dungeon run" : (V1IsFunc("PuzzleFighting") && %"PuzzleFighting"%.Call(mgName)) ? "a puzzle's fight - the way's guards"
		: PlayerActive ? "you were playing" : ""
	;(the quest's mob by the helper's own verdict - the game's memory's goal: its name, its kind, or one by a fight goal -
	;left off the avoid list: /caught's 7th field; an older helper's has none)
	if (mgWhy = "" && V1At(f, 7) = 1)   ; (v1: an older helper's 6 fields - the 7th blank)
		mgWhy := "the quest's - the helper didn't keep it off"
	;(the quest's mob: its name in the goal line last read)
	if (mgWhy = "" && WkGoalLine != "" && V1IsFunc("WalkLetters"))
		{
		mgKey := WalkLetters.Call(mgName)
		if (StrLen(mgKey) >= 4 && InStr(WalkLetters.Call(WkGoalLine), mgKey))
			mgWhy := "the quest's - in its goal line"
		}
	if (mgWhy != "")
		{
		DebugLog("  (the mobs' reach left as it is: " mgWhy ")")
		return
		}
	;(caught: the 10 minutes before the reach is made smaller start again - MobShrinkTick)
	MobWalkMs := 0
	mgFront := s.wide >= 360 || mgOff = "" || V1Le(mgOff, s.wide / 2)
	mgSet := mgFront ? "mobradius" : "mobbody"
	mgWas := mgFront ? s.range : s.body
	mgTo := Min(1500, Max(mgWas + 20, mgDist + 25))
	mgWhat := mgFront ? "how far they notice you" : "their reach all round"
	if (mgTo <= mgWas)
		{
		DebugLog("  not the quest's mob - " mgWhat " is at its most already (" mgWas ")")
		return
		}
	;(all round further than in front: the front that far too)
	mgPairs := [[mgSet, mgTo]]
	if (!mgFront && mgTo > s.range)
		mgPairs.Push(["mobradius", mgTo]), mgWhat .= " (and how far they notice you, " s.range " -> " mgTo ")"
	if (V1IsFunc("CfgWrite") && CfgWrite.Call(mgPairs))
		DebugLog("  not the quest's mob - " mgWhat " raised " mgWas " -> " mgTo " (Settings: " mgSet ")")
	}

;Every 10 minutes of walking without a mob the quest doesn't want catching the wizard (mobshrink, on unless 0): the reach
;the route keeps out of made smaller - a tenth off how far they notice you (mobradius) and their reach all round
;(mobbody) - so routes aren't long ways round for nothing; a catch raises it again (MobGrow, which starts the 10 minutes
;again). Never below what you set yourself in the Settings window (mobradiusfloor, mobbodyfloor - written when you
;save them there; else 300 and 120). 2026-10-24: a fifth at a time down to 300 had the crabs of Survey Camp catching
;the wizard - you'd set 850. Counted while the bot's on and walking, out of battle, you not playing
MobShrinkTick()
	{
	static lastAt := 0
	global MobWalkMs ; (v1 globals it sets)
	now := A_TickCount
	if (lastAt && now - lastAt < 5000 && BotOn && Walking && inbattle != 1 && !PlayerActive)
		MobWalkMs := (MobWalkMs ? MobWalkMs : 0) + now - lastAt
	lastAt := now
	if (MobWalkMs < 600000)
		return
	MobWalkMs := 0
	if (Stat("mobshrink") = 0 || (Stats.Has("mobavoid") && !Stats["mobavoid"]))
		return
	s := MobShape()
	r := Max(Max(300, Stat("mobradiusfloor")), Round(s.range * 0.9)), b := Max(Max(120, Stat("mobbodyfloor")), Round(s.body * 0.9))
	if (r >= s.range && b >= s.body)
		return
	if (V1IsFunc("CfgWrite") && CfgWrite.Call([["mobradius", r], ["mobbody", b]]))
		DebugLog("Walk: 10 minutes walking without a mob catching the wizard - mobs kept off less far: how far they notice you " s.range " -> " r ", their reach all round " s.body " -> " b " (Settings: mobshrink)")
	}

;What the mobs see, as PlayerStats.txt says: {shape (mobshape: 1 a circle all round, 2 a semi-circle in front - the
;default, 3 a cone in front), wide (degrees: 360, 180, mobcone - 60), range (mobradius: how far, 300), name}
MobShape()
	{
	shape := Stats.Has("mobshape") ? V1Round(Stats["mobshape"]) : 2   ; (v1: Round of text was 0)
	shape := (shape >= 1 && shape <= 3) ? shape : 2
	cone := Stats.Has("mobcone") && V1Ge(Stats["mobcone"], 5) ? Min(180, V1Round(Stats["mobcone"])) : 60
	return V1Obj({shape: shape, wide: shape = 1 ? 360 : shape = 2 ? 180 : cone, range: V1Gt(Stat("mobradius"), 0) ? V1Round(Stat("mobradius")) : 300
		, body: V1Gt(Stat("mobbody"), 0) ? V1Round(Stat("mobbody")) : 120, name: shape = 1 ? "circle" : shape = 2 ? "semi-circle" : "cone"})
	}

;The helper's arguments for keeping a route out of what mobs see: mobavoid (on unless 0) and MobShape - "" when it's off;
;duelavoid (off unless 1 - the duel circles aren't confirmed in the game yet): out of other players' battles too (&duels=1);
;mobwall (off unless 1 - the gap's width isn't measured in the game yet): a line of mobs' wall with no way round waited at
;as a mob on the way (&walls=1 - /nav's; else walked through its gap at once, as before)
NavMobArgs()
	{
	if (Stats.Has("mobavoid") && !Stats["mobavoid"])
		return ""
	s := MobShape()
	return "&avoid=1&mobr=" s.range "&shape=" s.shape (s.shape = 3 ? "&cone=" s.wide : "") (s.shape > 1 ? "&body=" s.body : "")
		. (Stats.Has("duelavoid") && Stats["duelavoid"] = 1 ? "&duels=1" : "")
		. (Stats.Has("mobwall") && Stats["mobwall"] = 1 ? "&walls=1" : "")
	}

;A number off /nav ("" if it isn't one: empty, nan, inf). Python may write a tiny one as 1.5e-08
NavNum(v)
	{
	v := Trim(v)
	if (RegExMatch(v, "i)^([-+]?\d+(?:\.\d*)?|[-+]?\.\d+)(?:e([-+]?\d+))?$", &num))
		return num[2] = "" ? num[1] + 0 : (num[1] + 0.0) * (10.0 ** num[2])
	return ""
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
VisionBlank()
	{
	global VisionOn := "", VisionPid := "", VisionFails := "", VisionCardsVar := "", VisionCardsAt := "", VisionCardsKey := "", VisionMissing := ""
	global VisionDir := "", VisionPort := "", VisionErr := "", VisionPlateWhy := "", VisionCardsWhy := "", VisionMemLast := "", VisionMemAt := ""
	global VisionMemWhy := "", VisionLookN := "", NavWhy := "", NavWaitUntil := "", NavWait := "", NavUnblock := "", NavGoalWhy := ""
	global NavGoalWaitUntil := "", NavMobsWhy := "", NavMobsWaitUntil := "", NavBattleWhy := "", NavBattleWaitUntil := "", NavBagWhy := ""
	global NavBagWaitUntil := "", NavGuiWhy := "", NavGuiWaitUntil := "", NavItemsWhy := "", NavItemsWaitUntil := "", NavUiWhy := ""
	global NavUiWaitUntil := "", NavUiRootW := ""
	global NavGuiTreeWhy := "", NavGuiTreeWaitUntil := ""
	global NavGearWhy := "", NavGearWaitUntil := ""
	global NavPetsWhy := "", NavPetsWaitUntil := ""
	global VisionPhaseWhy := "", VisionPhaseWaitUntil := ""
	}
