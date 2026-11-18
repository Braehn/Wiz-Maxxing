; Collect.ahk - "collect N things" goals whose things lie about the zone (2026-10-23: Piece Of Coral in The Grotto),
; collected by the game's memory: the vision helper's /items (read-only) gives each one's place; the nearest the goal
; line names is walked to round walls and mobs (/navto, as a follower walks to its leader) and stepped onto - picked up
; on contact, else X pressed once standing on it. The walker's collecting (AutoQuester\Walker.ahk CollectStep) asks
; here first at each step; none seen: it roams and walks into monsters as before. Settings: collectmem.
; Goals the game shows no way to, by the game's memory's kind (Walker.ahk WalkGoalKind - 2026-10-25 "Use Inactive Protector in
; District of the Stars (0 of 3)": the bot stood there doing nothing): a goal to use things (UseStep - the things by the game's
; memory and the zone's file, even far off: walked to, X at the prompt naming each, the count watched), to go to a place
; (GoStep - the place by its name, walked to, no X) or to talk to an NPC (TalkStep - the NPC by its keys or name, walked to,
; then the walker's own talk logic). None walks into monsters.
; AutoHotkey v1.1, #Included by Autofarmer.ahk.

;The item being walked to (its gid; "" none), since when; the items last read and when; items left for a while
;({gid: till when}); standing still (since when, where) and the tries at getting unstuck; when it was first stood on,
;when X was last pressed on it
global CiGid, CiFrom, CiItems, CiAskAt, CiSkip, CiStillAt, CiStillX, CiStillY, CiTries, CiOnAt, CiXAt
;The last step here (time away - a battle, a prompt, F8 - isn't counted on an item), and the last goal line that named
;one of its items (a garbled read meanwhile doesn't drop the item being walked to)
global CiStepAt, CiLine, CiLineAt
;Using, going to, talking to (UseStep, GoStep, TalkStep): the thing walked to ({name, x, y, z, template, src, key...} - "" none),
;since when and the time it's given (ms); the things last read and when; the ones used ({goal: [{t, x, y}]}) and the ones left for
;a while ([{t, x, y, until}]) - by template and place, not gid: a file spot's f:CL-DownedProtectors:3 turns into the game's own
;gid once the wizard is near; X at this one - how many, when the last went (0: none waiting - else the count is watched), the
;count and the goal id then, a blind one (no prompt at it), what it opened looked at; since when it's been right by it; since
;when nothing's been known to go for; the last prompt look and what it saw; standing still (since when, where) and the tries at
;it; the last step; the count's last look; the goal it's all for; the count at the last step and the distance to the thing then;
;the count read when the wizard first came within 600 of the thing ("" not yet, "-" not read); the ones tried and left, how many
;times ({goal: [{t, x, y, n}]} - twice: not gone for again)
global UsIt, UsFrom, UsBudget, UsThings, UsAskAt, UsDone, UsSkip, UsXs, UsXAt, UsCount0, UsGoalX, UsBlind, UsAfterX
global UsBareAt, UsNoneFrom, UsPromptAt, UsPrompt, UsStillAt, UsStillX, UsStillY, UsTries, UsStepAt, UsCountAt, UsGoalWas
global UsLastCount, UsD, UsNearCount, UsFails
;(the zone's volumes - /volumes: [{name, x, y, z, r}] - the zone they're for and when they were asked; at the place since when,
;walked through it since when; the notice given for this goal; X at a talk goal's NPC from here: [ticks]; when the walker's own
;talk logic was last handed the NPC)
global UsVols, UsVolsZone, UsVolsAt, UsAtFrom, UsThrough, UsNoted, UsTalkXs, UsHandAt
;(a fight goal's item: its prompt last looked at - CollectItemStep; a use goal's things near a prompt met outside its own step, the
;goal they were read for and when - UseOwnPromptNear)
global CiPromptAt, CiXn, UopnThings, UopnGoal, UopnAt

;The zone's quest items by the game's memory, for goal line goal: [{name, x, y, z, dist, quest, gid, key, template, src, kind}]
;nearest first (quest: the goal names it; key the thing's display key, template its template, src "mem" the game's memory's or
;"file" the zone file's, kind item / object / npc / ambient - a newer helper's fields 9-12, the kind by the key when there's no
;12th: CollectKeyKind; "" an older helper's); "" when they can't be read (no helper, the game's memory unreadable). far: the zone
;file's placements too - things far off, not in the game's memory yet (only for using things: a picked-up item's spot stays in
;the file)
CollectItems(goal, far := false)
	{
	answer := VisionGet("/items?goal=" NavUri(goal) (far ? "&far=1" : ""), 2500, true)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	out := []
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		;(v1: a field that isn't there - an empty line's first - and a field + 0 that isn't a number read blank)
		if (V1At(f, 1) = "item" && f.Length >= 8)
			out.Push(V1Obj({name: f[2], x: V1Add(f[3], 0), y: V1Add(f[4], 0), z: V1Add(f[5], 0), dist: V1Add(f[6], 0), quest: f[7] = 1, gid: f[8]
				, key: f.Length >= 11 ? Trim(f[9]) : "", template: f.Length >= 11 ? Trim(f[10]) : ""
				, src: f.Length >= 11 ? Trim(f[11]) : ""
				, kind: (f.Length >= 12 && Trim(f[12]) != "") ? Trim(f[12]) : f.Length >= 11 ? CollectKeyKind(Trim(f[9])) : ""}))
		}
	return out
	}

;What a thing's display key says it is (when the helper doesn't say): "mob" (a *Mobs table's - an ambient mob's too), "npc"
;(WizardNPC, NPCs, <world>-NPCs), "item" (WizItems), "object" (any other: WizQst371C7_00000008 Inactive Protector,
;WizardGameObjects_00000344), "" no key
CollectKeyKind(key)
	{
	if (key = "")
		return ""
	if (RegExMatch(key, "^\w*Mobs_\d+$"))
		return "mob"
	if (RegExMatch(key, "^(WizardNPC|NPCs|[A-Za-z0-9]+-NPCs)_\d+$"))
		return "npc"
	if (RegExMatch(key, "^WizItems_\d+$"))
		return "item"
	return "object"
	}

;One step of collecting goal's items by the game's memory: the nearest the goal names walked to, stood on (X pressed if
;it's still there), then the next. True when it did this step (walking to one, or at one); false when it sees none to go
;for - the walker does its own collecting (monsters, roaming)
CollectItemStep(goal)
	{
	global CiGid, CiSkip, CiFrom, CiOnAt, CiStillAt, CiXAt, CiStepAt, CiAskAt, CiItems, CiLine, CiLineAt, CiTries, CiStillX ; (v1 globals it sets)
	global CiStillY, CiPromptAt, CiXn, WkLastX ; (v1 globals it sets)
	if ((Stats.Has("collectmem") && !Stats["collectmem"]) || !VisionOn)
		{
		CiGid := ""
		return false
		}
	if (!IsObject(CiSkip))
		CiSkip := V1Obj()
	;(away from collecting meanwhile - a battle, a prompt, F8, you: not counted on the item)
	if (CiStepAt && A_TickCount - CiStepAt > 5000)
		CiFrom := V1Add(CiFrom, A_TickCount - CiStepAt), CiOnAt := 0, CiStillAt := 0, CiXAt := 0   ; (v1: += in a comma chain - a blank stayed blank)
	CiStepAt := A_TickCount
	if (!CiAskAt || A_TickCount - CiAskAt > 1500)
		{
		CiAskAt := A_TickCount
		got := CollectItems(goal)
		CiItems := IsObject(got) ? got : []
		named := false
		for i, x in CiItems
			named := named || x.quest
		;(a goal line read wrong this time - none of the items named - while walking to one: asked with the last line that
		;named one, up to 6 s back)
		if (named)
			CiLine := goal, CiLineAt := A_TickCount
		else if (CiGid != "" && CiLine != "" && CiLine != goal && A_TickCount - CiLineAt < 6000)
			{
			got := CollectItems(CiLine)
			CiItems := IsObject(got) ? got : CiItems
			}
		}
	;(only what lies there now - the game's memory's, never a zone file's spot: a picked-up one stays in the file - and never an
	;NPC or a mob a newer helper's key says it is)
	it := ""
	for i, x in CiItems
		if (x.quest && x.src != "file" && x.kind != "npc" && x.kind != "mob" && !(CiSkip.Has(x.gid) && A_TickCount < CiSkip[x.gid]))
			{
			it := x
			break
			}
	if (!IsObject(it))
		{
		if (CiGid != "")
			{
			;(only for a real item: a use / go / talk goal leaves its marker - "(use)" - behind, and a fight goal after it had none)
			if (SubStr(CiGid, 1, 1) != "(")
				WalkLog("collect: none of the goal's items left in the game's memory - roaming and looking for monsters")
			CiGid := ""
			ReleaseKeys()
			}
		return false
		}
	if (it.gid != CiGid)
		{
		CiGid := it.gid, CiFrom := A_TickCount, CiTries := 0, CiOnAt := 0, CiXAt := 0, CiStillAt := 0, CiXn := 0
		WalkLog("collect: " it.name " " Round(it.dist) " away (the game's memory, at " Round(it.x) ", " Round(it.y) ") - walking to it")
		}
	;(a minute on one without getting it - out of reach, or not one to pick up: another one first, this one again in 3
	;minutes)
	if (V1Gt(V1Ago(CiFrom), 60000))   ; (v1: CiFrom blank - not set yet - never counted as a minute)
		{
		CiSkip[it.gid] := A_TickCount + 180000, CiGid := ""
		WalkLog("collect: couldn't get " it.name " in a minute - another one first")
		ReleaseKeys()
		return true
		}
	nav := PartyNavTo(V1Obj({x: it.x, y: it.y, z: it.z}), true)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		return false
		}
	d := Sqrt((nav.x - it.x) ** 2 + (nav.y - it.y) ** 2)
	;By it - within 300 at its height: its prompt read every 0.7 s and X'd if it's the item's own - one naming it (WalkUseNames)
	;or by UseOwnPrompt's rule (the goal's verb or the plain "Interact", nothing else the game names nearer) - never a teleport's,
	;a shop's, an NPC's chatter, nor one with Crowns on it; every 4 s at most. A thing the wizard can't stand on - a pile of rocks
	;with a body of its own, a mount under the wizard - is never within 45 of its middle: 2026-11-17 "Collect Well Stones in
	;Savannah (0 of 3)", the wizard on its mount by a pile, "WELL STONES - Press X to Interact" up, no X. The walker's own look
	;X's a prompt once a minute by its title (Walker.ahk WalkPromptFree) - all six piles carry the same one. Not in the quiet time
	;after a dialogue (WkQuietUntil - as the walker's own X); X'd twice and still there: another one first, this one again in 3
	;minutes (the minute on an item, above, as ever)
	if (it.src != "file" && d <= 300 && (nav.z = "" || it.z = "" || Abs(nav.z - it.z) < 150) && A_TickCount - V1N(CiPromptAt) >= 700
		&& (!CiXAt || A_TickCount - CiXAt > 4000) && A_TickCount >= V1N(WkQuietUntil))
		{
		CiPromptAt := A_TickCount
		if (InteractPrompt() = "press" && !RegExMatch(WkPromptDest " " WkPromptText, "i)teleport") && !WalkPromptCrowns()
			&& !RegExMatch(WkPromptVerb, "i)^(talk|speak|chat|shop|trade|buy|sell|browse|craft|learn|train|ride|mount|board|join|enter)")
			&& (WalkUseNames(WkPromptDest, goal) || UseOwnPrompt(V1Obj({x: nav.x, y: nav.y}), d, goal, it, CiItems)))
			{
			ReleaseKeys()
			if (V1N(CiXn) >= 2)
				{
				CiSkip[it.gid] := A_TickCount + 180000, CiGid := ""
				WalkLog("collect: X twice at " it.name "'s prompt and it's still there - another one first")
				return true
				}
			CiXAt := A_TickCount, CiXn := V1N(CiXn) + 1
			WalkLog("collect: X at " it.name "'s prompt ('" SubStr(WkPromptDest, 1, 30) "' - to " (WkPromptVerb = "" ? "?" : WkPromptVerb) ", " Round(d) " off)")
			PressKey("x")
			WkLastX := A_TickCount
			SetStatus("collecting - X at " it.name)
			Sleep(300)
			return true
			}
		}
	;Standing on it (at its height - not under it on a ledge): picked up on contact - still there after 1.5 s: X pressed
	;(again after 4 s)
	if (d <= 45 && (nav.z = "" || Abs(nav.z - it.z) < 120))
		{
		ReleaseKeys()
		CiOnAt := CiOnAt ? CiOnAt : A_TickCount
		if (A_TickCount - CiOnAt > 1500 && (!CiXAt || A_TickCount - CiXAt > 4000))
			{
			CiXAt := A_TickCount
			WalkLog("collect: on " it.name " and it's still there - pressing X")
			PressKey("x")
			}
		SetStatus("collecting - at " it.name)
		Sleep(150)
		return true
		}
	CiOnAt := 0
	;(stuck: hardly moving for 3 s with W down - backed up and turned; after 4 tries another one first)
	if (HeldW && CiStillAt && Sqrt((nav.x - CiStillX) ** 2 + (nav.y - CiStillY) ** 2) < 60)
		{
		if (A_TickCount - CiStillAt > 3000)
			{
			CiTries := V1Add(CiTries, 1), CiStillAt := 0   ; (v1: += in a comma chain - a blank stayed blank)
			if (V1Gt(CiTries, 4))
				{
				CiSkip[it.gid] := A_TickCount + 180000, CiGid := ""
				WalkLog("collect: stuck on the way to " it.name " - another one first")
				ReleaseKeys()
				return true
				}
			WalkLog("collect: stuck on the way to " it.name " (" Round(d) " away) - backing up and turning, try " CiTries)
			BackUp(700)
			DgTurn(V1IsNum(CiTries) && CiTries & 1 ? 90 : -90)   ; (v1: a blank & 1 was blank)
			HoldW(1)
			Sleep(900)
			return true
			}
		}
	else
		CiStillAt := A_TickCount, CiStillX := nav.x, CiStillY := nav.y
	SetStatus("collecting - walking to " it.name " (" Round(d) " away)")
	DgSteer(nav, V1Obj({x: it.x, y: it.y}), d)
	return true
	}

;One of the goal's items in the game's memory left for a while (couldn't be reached) and waiting to be tried again: the
;walker doesn't give the goal up meanwhile (Walker.ahk CollectStep)
CollectItemsWaiting()
	{
	if (!IsObject(CiSkip) || !IsObject(CiItems))
		return false
	for i, x in CiItems
		if (x.quest && CiSkip.Has(x.gid) && A_TickCount < CiSkip[x.gid])
			return true
	return false
	}

;---- Goals the game shows no way to, by the game's memory's kind: using things, going to a place, talking to an NPC ----

;A use / go / talk step's start (UseStep, GoStep, TalkStep - kind): the goal's key for the things used (the kind and the walker's
;collect goal's id - the game's memory's - else its line's letters without the count); another goal: nothing carried over but
;what was used. Time away (a battle, a prompt, F8) isn't counted on the thing or the looking
UseBegin(kind)
	{
	global UsDone, UsSkip, UsTalkXs, UsFails, CiGid, UsGoalWas, UsIt, UsXAt, UsXs, UsBlind, UsBareAt, UsNoneFrom, UsLastCount ; (v1 globals it sets)
	global UsAtFrom, UsThrough, UsNoted, UsBudget, UsPromptAt, UsPrompt, UsD, UsAskAt, UsFrom, UsTries, UsStillAt, UsStepAt ; (v1 globals it sets)
	if (!IsObject(UsDone))
		UsDone := V1Obj()
	if (!IsObject(UsSkip))
		UsSkip := []
	if (!IsObject(UsTalkXs))
		UsTalkXs := []
	if (!IsObject(UsFails))
		UsFails := V1Obj()
	;(not collecting by walking into mobs: a mob that catches the wizard here gets its reach made bigger - Vision.ahk MobGrow)
	CiGid := "(" kind ")"
	ubKey := kind ":" (WkCollect.goalid != "" ? WkCollect.goalid : WalkLetters(RegExReplace(WkCollect.text, "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?")))
	if (!UsDone.Has(ubKey))
		UsDone[ubKey] := []
	if (UsGoalWas != ubKey)
		{
		UsGoalWas := ubKey, UsIt := "", UsXAt := 0, UsXs := 0, UsBlind := 0, UsBareAt := 0, UsNoneFrom := 0, UsLastCount := ""
		UsAtFrom := 0, UsThrough := 0, UsNoted := "", UsBudget := 0, UsPromptAt := 0, UsPrompt := "-", UsD := "", UsAskAt := 0
		UsFrom := 0, UsTries := 0, UsStillAt := 0
		}
	if (UsStepAt && A_TickCount - UsStepAt > 5000)
		{
		ubGap := A_TickCount - UsStepAt
		UsFrom := UsFrom ? UsFrom + ubGap : 0, UsNoneFrom := UsNoneFrom ? UsNoneFrom + ubGap : 0, UsXAt := UsXAt ? UsXAt + ubGap : 0
		UsBareAt := 0, UsStillAt := 0, UsPromptAt := 0, UsAtFrom := 0
		}
	UsStepAt := A_TickCount
	return ubKey
	}

;Forget what was left for a while, and the tries at each - Keep trying on the notice (Walker.ahk WalkNoteKeep), F8 off and on
UseForget()
	{
	global UsSkip, UsNoneFrom, UsIt, UsXAt, UsXs, UsTalkXs, UsNoted, UsAtFrom, UsThrough, UsFails ; (v1 globals it sets)
	UsSkip := [], UsNoneFrom := 0, UsIt := "", UsXAt := 0, UsXs := 0, UsTalkXs := [], UsNoted := "", UsAtFrom := 0, UsThrough := 0
	UsFails := V1Obj()
	}

;A thing's template (its name when an older helper gives none) - with its place, what tells one from another
UseT(x)
	{
	return x.template != "" ? x.template : x.name
	}

;Is thing x in list ([{t, x, y, gid, src}])? The same template within 400: a zone file's spot and the game's own object there are
;one - but two of the game's own objects (src mem) with gids of their own are two: a used one is gone from the game's memory, so
;one standing there now is another (2026-10-26 "Find Portal Piece in Stormriven (2 of 3)": the third X'd by the second's spot
;after the notice - by the used one's spot it was never gone for)
UseIn(list, x)
	{
	for i, e in list
		if (e.t = UseT(x) && (e.x - x.x) ** 2 + (e.y - x.y) ** 2 <= 160000
			&& !(e.src = "mem" && x.src = "mem" && e.gid != "" && x.gid != "" && e.gid "|" != x.gid "|"))
			return true
	return false
	}

;Is thing x left for a while (UsSkip, its time not up - the ones whose time is up dropped)?
UseSkipped(x)
	{
	global UsSkip ; (v1 globals it sets)
	usKeep := [], usHit := false
	for i, e in UsSkip
		if (A_TickCount < e.until)
			{
			usKeep.Push(e)
			if (e.t = UseT(x) && (e.x - x.x) ** 2 + (e.y - x.y) ** 2 <= 160000)
				usHit := true
			}
	UsSkip := usKeep
	return usHit
	}

;A thing used for this goal (key: UseBegin's), left for a while or tried twice within 400 of the wizard (the game's memory's last
;reading - WkNavLast; not read: true, no X on a guess)? A prompt naming the thing there is that one's. more: looking about for more
;of them with some used and the count not full - by a used one a prompt naming the thing may well be another one, one the game's
;memory doesn't hold (2026-10-26 "Find Portal Piece in Stormriven (2 of 3)": the third was X'd by the second's spot, after the
;notice): used ones don't count then
UseTriedNear(key, more := false)
	{
	if (!IsObject(WkNavLast) || WkNavLast.x = "" || WkNavLast.y = "")
		return true
	utMe := V1Obj({x: WkNavLast.x, y: WkNavLast.y})
	if (!more)
		for i, e in UsDone[key]
			if ((e.x - utMe.x) ** 2 + (e.y - utMe.y) ** 2 <= 160000)
				return true
	for i, e in UsSkip
		if (A_TickCount < e.until && (e.x - utMe.x) ** 2 + (e.y - utMe.y) ** 2 <= 160000)
			return true
	if (IsObject(UsFails) && IsObject(UsFails[key]))
		for i, e in UsFails[key]
			if (e.n >= 2 && (e.x - utMe.x) ** 2 + (e.y - utMe.y) ** 2 <= 160000)
				return true
	return false
	}

;How many times the thing (template t, at x, y) was tried for this goal (key: UseBegin's) and left - X did nothing, or it couldn't
;be got to - 0 never; 2 (twice): not gone for again for this goal, nor X'd at while looking about (Crowns on its prompt: 2 at once)
UseFails(key, t, x, y)
	{
	if (!IsObject(UsFails) || !IsObject(UsFails[key]))
		return 0
	for i, e in UsFails[key]
		if (e.t = t && (e.x - x) ** 2 + (e.y - y) ** 2 <= 160000)
			return e.n
	return 0
	}

;Thing it tried and left once more for this goal (key: UseBegin's; never: one never to be X'd - Crowns on its prompt - counted as
;twice at once): how many times now
UseFailMore(key, it, never := false)
	{
	global UsFails ; (v1 globals it sets)
	if (!IsObject(UsFails))
		UsFails := V1Obj()
	if (!IsObject(UsFails[key]))
		UsFails[key] := []
	for i, e in UsFails[key]
		if (e.t = UseT(it) && (e.x - it.x) ** 2 + (e.y - it.y) ** 2 <= 160000)
			{
			e.n := never ? 2 : e.n + 1, e.never := never ? 1 : e.never
			return e.n
			}
	UsFails[key].Push(V1Obj({t: UseT(it), x: it.x, y: it.y, n: never ? 2 : 1, never: never ? 1 : 0}))
	return never ? 2 : 1
	}

;The thing walked to (UsIt) left for 5 minutes; why: for the log; never: never to be X'd (Crowns on its prompt). A goal to use
;things counts the tries at each (UseFailMore): left the second time - or never - it isn't gone for again (UseStep). True (the
;step's done)
UseLeave(why, never := false)
	{
	global UsIt, UsXAt, UsXs, UsBlind, UsBareAt, UsBudget, UsD ; (v1 globals it sets)
	ulN := 0
	if (IsObject(UsIt))
		{
		UsSkip.Push(V1Obj({t: UseT(UsIt), x: UsIt.x, y: UsIt.y, until: A_TickCount + 300000}))
		if (SubStr(UsGoalWas, 1, 4) = "use:")
			ulN := UseFailMore(UsGoalWas, UsIt, never)
		}
	WalkLog("use: " (IsObject(UsIt) ? UsIt.name : "the thing") " - " why " - " (ulN < 2 ? "left for 5 minutes" : never ? "not gone for again"
		: "tried twice now - not gone for again"))
	UsIt := "", UsXAt := 0, UsXs := 0, UsBlind := 0, UsBareAt := 0, UsBudget := 0, UsD := ""
	ReleaseKeys()
	return true
	}

;The thing walked to (UsIt) used: kept as used for this goal (key: UseBegin's - its gid and where it was read from too: UseIn),
;on to the next; why: for the log. True
UseUsed(key, why)
	{
	global UsIt, UsXAt, UsXs, UsBlind, UsBareAt, UsNoneFrom, UsBudget, UsD ; (v1 globals it sets)
	if (IsObject(UsIt))
		UsDone[key].Push(V1Obj({t: UseT(UsIt), x: UsIt.x, y: UsIt.y, gid: UsIt.gid, src: UsIt.src}))
	WalkLog("use: " (IsObject(UsIt) ? UsIt.name : "the thing") " used - " why)
	SetStatus("using - " (IsObject(UsIt) ? UsIt.name : "the thing") " used")
	UsIt := "", UsXAt := 0, UsXs := 0, UsBlind := 0, UsBareAt := 0, UsNoneFrom := 0, UsBudget := 0, UsD := ""
	return true
	}

;The goal's count now: the game's memory's (Walker.ahk WalkGoalText keeps it, and the goal's id: WkGoalId), else the count in
;the line read off the screen; "" not known
UseCount()
	{
	ucLine := WalkGoalText()
	if (WkGoalId != "" && WkGoalCount != "")
		return V1Add(WkGoalCount, 0)   ; (v1: not a number + 0 was blank)
	return CollectCount(ucLine)
	}

;X at the thing (it: UsIt; "" a prompt naming it met while looking about - the thing's where the wizard stands) - never with
;Crowns on its prompt; the count and the goal's id noted first, then watched (UseWait). why: for the log; key: UseBegin's
UseX(it, why, key)
	{
	global UsFrom, UsBudget, UsXs, UsBlind, UsIt, UsCount0, UsGoalX, WkPreXText, UsAfterX, WkLastX, UsXAt, UsCountAt ; (v1 globals it sets)
	if (!IsObject(it))
		{
		uxMe := IsObject(WkNavLast) ? WkNavLast : V1Obj({x: 0, y: 0, z: 0})
		it := V1Obj({name: WalkGoalItemName(WkCollect.text), template: "prompt:" WkPromptDest, x: uxMe.x != "" ? V1Add(uxMe.x, 0) : 0
			, y: uxMe.y != "" ? V1Add(uxMe.y, 0) : 0, z: uxMe.z != "" ? V1Add(uxMe.z, 0) : 0, src: "prompt", dist: 0, quest: 1})
		UsFrom := A_TickCount, UsBudget := 60000, UsXs := 0, UsBlind := 0
		}
	UsIt := it
	;(Crowns on the prompt: never an X - left, not gone for again for this goal nor looked at again here)
	if (RegExMatch(WkPromptText, "i)cr[o0]wn"))
		return UseLeave("Crowns on its prompt - never an X there", true)
	ReleaseKeys()
	UsCount0 := UseCount(), UsGoalX := WkGoalId
	;(no prompt at it and the count risen since the wizard came near it: picked up on contact - used, no X at its empty spot. The
	;walker's look at the count is every 4 s: an X 3 s on took a count with the pickup in it - "didn't rise", left for 5 minutes)
	if (UsBlind && UsNearCount != "" && UsNearCount != "-" && UsCount0 != "" && UsCount0 > UsNearCount)
		return UseUsed(key, "picked up on contact (the count " UsCount0 ", " UsNearCount " when it came near)")
	;(what's on screen before X: what X opens is what's new - WalkCloseAfterX)
	WkPreXText := WalkAfterXText(&uxPre), UsAfterX := 0
	PressKey("x")
	WkLastX := A_TickCount, UsXAt := A_TickCount, UsCountAt := A_TickCount
	UsXs := UsXs ? UsXs + 1 : 1
	WalkLog("use: X at " it.name " (" why ") - the count " (UsCount0 = "" ? "not known" : UsCount0) ", watched for 8 s")
	SetStatus("using - X at " it.name)
	Sleep(300)
	return true
	}

;X pressed at the thing: what it opened - a dialogue Spaced through, a window (a shop) closed, nothing in it clicked (Walker.ahk
;WalkCloseAfterX) - and the goal's count watched every second for 8 s: risen, or the goal moved on - used, on to the next; not -
;X once more at its own prompt (not after a blind one), then left for 5 minutes (used already, or the quest's not there yet).
;key: UseBegin's. True
UseWait(key)
	{
	global UsAfterX, UsCountAt, WkGoalReadAt, UsXAt ; (v1 globals it sets)
	if (WalkDialogOpen())
		{
		WalkSkipDialog()
		return true
		}
	if (!UsAfterX && A_TickCount - UsXAt > 700)
		{
		UsAfterX := 1
		if (WalkCloseAfterX())
			return true
		}
	if (!UsCountAt || A_TickCount - UsCountAt >= 1000)
		{
		UsCountAt := A_TickCount
		uwN := UseCount()
		if (UsGoalX != "" && WkGoalId != "" && WkGoalId "|" != UsGoalX "|")
			{
			;(the walker's goal check at once - CollectStep)
			WkGoalReadAt := 0
			return UseUsed(key, "the goal moved on")
			}
		if (uwN != "" && UsCount0 != "" && uwN > UsCount0)
			return UseUsed(key, "the count is now " uwN " (was " UsCount0 ")")
		}
	if (A_TickCount - UsXAt < 8000)
		{
		SetStatus("using - X at " UsIt.name ", watching the count")
		Sleep(150)
		return true
		}
	UsXAt := 0
	if (UsXs < 2 && InteractPrompt() = "press" && ((!UsBlind && WalkUseNames(WkPromptDest, WkCollect.text))
		|| (UsD != "" && UsD <= 300 && UseOwnPrompt(WkNavLast, UsD, WkCollect.text))))
		return UseX(UsIt, "its prompt again - the count didn't rise", key)
	return UseLeave("X " UsXs " time" (UsXs = 1 ? "" : "s") " and the count didn't rise")
	}

;Nothing to go for (a use / go / talk goal the game shows no way to): looking about (the walker's roaming) - never the notice
;while a thing known is only left for a while (left: how many - its 5 minutes not up; then it's gone for again), and 3 minutes of
;looking about after the last of them, or after the last use, finding nothing new - then the notice, waiting there (Walker.ahk
;CollectGiveUp: Keep trying looks again); no endless roaming. 2026-10-26 "Find Portal Piece in Stormriven": a piece left at
;15:12, one used at 15:14:46, and the notice at once - "X at each did nothing". what: what was looked for; goal: the goal line
;now; used: how many were used for it, out: how many were tried twice (or have Crowns on their prompt) - for the notice. True if
;it gave up
UseNothing(left, what, goal := "", used := 0, out := 0)
	{
	global UsNoneFrom ; (v1 globals it sets)
	if (left)
		{
		UsNoneFrom := A_TickCount
		return false
		}
	if (!UsNoneFrom)
		UsNoneFrom := A_TickCount
	if (A_TickCount - UsNoneFrom <= 180000)
		return false
	UsNoneFrom := 0
	UseLine(goal)
	unLine := UseLine(WalkGoalText())
	;(the ones it found with Crowns on their prompt, never X'd, and the ones X'd twice for nothing - not a prompt met looking about,
	;"prompt:": by a used one it may be that one's own)
	unCrown := 0, unTwice := 0
	if (IsObject(UsFails) && IsObject(UsFails[UsGoalWas]))
		for i, e in UsFails[UsGoalWas]
			{
			if (SubStr(e.t, 1, 7) = "prompt:")
				continue
			if (e.never)
				unCrown += 1
			else if (e.n >= 2)
				unTwice += 1
			}
	;(some used: the ones found that weren't said too - the notice's "no more" is about new ones)
	unOut := (unTwice ? " - X at " unTwice " more it found did nothing, tried twice" : "")
		. (unCrown ? " - " unCrown " more it found " (unCrown = 1 ? "has" : "have") " Crowns on the prompt - never an X there" : "")
	unWhy := used ? "used " used " thing" (used = 1 ? "" : "s") " it names - the count is " UseCountText(unLine) unOut " - and found no more in 3 minutes of looking about (more may lie beyond the game's memory's reach, not in the zone's file)"
		: out && unCrown && !unTwice ? "each " what " the bot found has Crowns on its prompt - never an X there - and nothing more was found in 3 minutes of looking about"
		: out ? "X at each " what " the bot found did nothing, tried twice (the count didn't rise) - used already, or the quest isn't there yet" (unCrown ? " (Crowns on the prompt of " unCrown " - never an X there)" : "") " - and nothing more was found in 3 minutes of looking about"
		: "the game shows no way to it, and no " what " was found in the game's memory or the zone's file in 3 minutes of looking"
	WalkLog("use: '" unLine "' - " unWhy " - stopping here, telling you")
	CollectGiveUp("", unWhy, "Quest needs you")
	return true
	}

;The goal's line as it reads now (goal: the walker's last read of it) kept as the use goal's own (WkCollect.text) when it's the
;same goal letter for letter but the count: the notice (Walker.ahk CollectGiveUp) and the walker's log lines show the count now,
;not the one use mode began with (2026-10-26: "(0 of 3)" in the notice with 2 of 3 done). The goal's own line
UseLine(goal)
	{
	if (!IsObject(WkCollect))
		return goal
	ulCut := "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?"
	if (goal != "" && goal != WkCollect.text && CollectCount(goal) != ""
		&& WalkLetters(RegExReplace(goal, ulCut)) = WalkLetters(RegExReplace(WkCollect.text, ulCut)))
		WkCollect.text := goal
	return WkCollect.text
	}

;The goal's count for the notice: "2 of 3" from its line, else the game's memory's (UseCount, WkGoalTotal); "not known"
UseCountText(line)
	{
	if (RegExMatch(line, "i)(\d+)\s*(?:of|/)\s*(\d+)", &uc))
		return uc[1] " of " uc[2]
	ucN := UseCount()
	return ucN = "" ? "not known" : ucN (WkGoalTotal != "" ? " of " WkGoalTotal : "")
	}

;Walking to the thing (UsIt) and hardly moving for 3 s with W down: backed up and turned (true); after 4 tries left for a while
;(true). nav: PartyNavTo's; d: how far; what: the log's word
UseStuck(nav, d, what)
	{
	global UsTries, UsStillAt, UsStillX, UsStillY ; (v1 globals it sets)
	if (HeldW && UsStillAt && (nav.x - UsStillX) ** 2 + (nav.y - UsStillY) ** 2 < 3600)
		{
		if (A_TickCount - UsStillAt <= 3000)
			return false
		UsTries := UsTries ? UsTries + 1 : 1, UsStillAt := 0
		;(Puzzle.ahk: stuck on the way to the thing - a blocked way's evidence; it may take over)
		if (V1IsFunc("PuzzleEvidence") && IsObject(UsIt) && %"PuzzleEvidence"%.Call("use", d, UsIt.x, UsIt.y, UsIt.z))
			return true
		if (UsTries > 4)
			return UseLeave("stuck on the way (" Round(d) " off)")
		WalkLog(what ": stuck on the way to " UsIt.name " (" Round(d) " away) - backing up and turning, try " UsTries)
		BackUp(700)
		DgTurn(UsTries & 1 ? 90 : -90)
		HoldW(1)
		Sleep(900)
		return true
		}
	UsStillAt := A_TickCount, UsStillX := nav.x, UsStillY := nav.y
	return false
	}

;One step of using a goal's things (WkCollect.kind "use" - the game's memory's USAGE: "Use Inactive Protector in District of the
;Stars (0 of 3)", "Read The History of Magic", a "Collect X" object): every 1.5 s the things the goal names - the game's memory's
;and the zone file's, even far off (/items far) - and the nearest not used yet nor left for a while (never an NPC, a mob) walked
;to round walls and mobs (as a follower walks to its leader: /navto), 30 s and a second per 600 units of the way given; within 400
;its prompt read every 0.7 s - X at the one naming it (never a teleporter's, never with Crowns), the count watched (UseWait);
;right by it with no prompt at all for 3 s: one X in case. None to go for: the walker looks about (no monsters) while the prompts
;naming the thing are X'd; one left for a while is gone for again once its 5 minutes are up, one tried twice isn't; the notice
;only once none waits and 3 minutes of looking about found nothing new (UseNothing). goal: the goal line. True when it did this
;step; false when there's nothing to go for (the walker roams)
UseStep(goal)
	{
	global UsNoneFrom, UsLastCount, UsAskAt, UsThings, UsIt, UsD, UsPromptAt, UsFrom, UsBudget, UsXs, UsBlind, UsBareAt ; (v1 globals it sets)
	global UsTries, UsStillAt, UsPrompt, UsNearCount ; (v1 globals it sets)
	if ((Stats.Has("collectmem") && !Stats["collectmem"]) || !VisionOn)
		return false
	usKey := UseBegin("use")
	if (UsXAt)
		return UseWait(usKey)
	;(the count risen while right by it - picked up on contact: that one's used)
	usCount := WkCollect["count"]
	if (IsObject(UsIt) && UsLastCount != "" && usCount != "" && usCount > UsLastCount && UsD != "" && UsD <= 300)
		UseUsed(usKey, "the count rose to " usCount " by it")
	;(the count risen while looking about - an X at the goal's spot, Walker.ahk WalkUseSpotX: progress - its 3 minutes start again)
	if (UsLastCount != "" && usCount != "" && usCount > UsLastCount)
		UsNoneFrom := 0
	UsLastCount := usCount
	if (!UsAskAt || A_TickCount - UsAskAt > 1500)
		{
		UsAskAt := A_TickCount
		usGot := CollectItems(goal, true)
		UsThings := IsObject(usGot) ? usGot : []
		}
	;(the goal's line now kept as its own: its count in the notice and the walker's log lines)
	UseLine(goal)
	;(the one walked to while it's still there - a file spot read now as the game's own object is the same one; else the nearest; one
	;tried twice - or with Crowns on its prompt - not gone for again)
	usPick := "", usLeft := 0, usOut := 0
	for i, usX in UsThings
		{
		if (!usX.quest || usX.kind = "npc" || usX.kind = "mob" || UseIn(UsDone[usKey], usX))
			continue
		if (UseFails(usKey, UseT(usX), usX.x, usX.y) >= 2)
			{
			usOut += 1
			continue
			}
		if (UseSkipped(usX))
			{
			usLeft += 1
			continue
			}
		if (IsObject(UsIt) && UseT(usX) = UseT(UsIt) && (usX.x - UsIt.x) ** 2 + (usX.y - UsIt.y) ** 2 <= 160000)
			{
			usPick := usX
			break
			}
		if (!IsObject(usPick))
			usPick := usX
		}
	if (!IsObject(usPick))
		{
		usUsed := UsDone[usKey].Length
		if (IsObject(UsIt) || !UsNoneFrom)
			{
			WalkLog("use: none of the goal's things left to go for" (usLeft || usUsed || usOut ? " (" SubStr((usLeft ? ", " usLeft " left for a while" : "")
				. (usUsed ? ", " usUsed " used" : "") (usOut ? ", " usOut " tried twice" : ""), 3) ")" : "") " - looking about"
				. (usLeft ? " till the one left for a while is due again (its 5 minutes)" : usUsed ? " for more (the count isn't full)" : ""))
			UsIt := "", UsD := ""
			ReleaseKeys()
			}
		;(looking about meanwhile - the walker's roaming: X at a prompt that names the thing, never another's - nor one by a thing left
		;for a while or tried twice already: its own prompt, tried; by a used one only once some are used - it may be another one)
		if (!UsPromptAt || A_TickCount - UsPromptAt >= 700)
			{
			UsPromptAt := A_TickCount
			if (InteractPrompt() = "press" && (WalkUseNames(WkPromptDest, goal) || UseOwnPromptNear(goal, UsThings)) && !UseTriedNear(usKey, usUsed > 0))
				return UseX("", "its prompt, met looking about", usKey)
			}
		return UseNothing(usLeft, "thing it names", goal, usUsed, usOut)
		}
	UsNoneFrom := 0
	if (!IsObject(UsIt) || UseT(usPick) != UseT(UsIt) || (usPick.x - UsIt.x) ** 2 + (usPick.y - UsIt.y) ** 2 > 160000)
		{
		UsFrom := A_TickCount, UsBudget := 0, UsXs := 0, UsBlind := 0, UsBareAt := 0, UsTries := 0, UsStillAt := 0, UsPrompt := "-", UsNearCount := ""
		WalkLog("use: " usPick.name " " Round(usPick.dist) " away (" (usPick.src = "file" ? "the zone's file" : "the game's memory") ", at "
			. Round(usPick.x) ", " Round(usPick.y) ") - walking to it" (usLeft ? " (" usLeft " left for a while)" : ""))
		}
	UsIt := usPick
	usNav := PartyNavTo(V1Obj({x: UsIt.x, y: UsIt.y, z: UsIt.z}), true)
	if (!IsObject(usNav))
		{
		ReleaseKeys()
		Sleep(200)
		return true
		}
	usDist := Sqrt((usNav.x - UsIt.x) ** 2 + (usNav.y - UsIt.y) ** 2), UsD := usDist
	;(the count as the wizard first comes within 600 of it - a pickup on contact is told by it: UseX. 600: a step or two before
	;contact at 1x - a step can walk 200)
	if (usDist <= 600 && UsNearCount = "")
		UsNearCount := UseCount(), UsNearCount := (UsNearCount = "") ? "-" : UsNearCount
	;(the time it's given: 30 s and a second per 600 units of the way - the route's, else straight)
	if (!UsBudget)
		UsBudget := 30000 + Round(((usNav.left != "" && usNav.left > 0) ? usNav.left : usDist) / 600 * 1000)
	if (UsFrom && A_TickCount - UsFrom > UsBudget)
		return UseLeave("not got to in " Round(UsBudget / 1000) " s (" Round(usDist) " off)")
	;Close: its prompt read every 0.7 s - X at the one naming the thing
	if (usDist <= 400 && (!UsPromptAt || A_TickCount - UsPromptAt >= 700))
		{
		UsPromptAt := A_TickCount
		UsPrompt := InteractPrompt()
		if (UsPrompt = "press" && WalkUseNames(WkPromptDest, goal))
			return UseX(UsIt, "its prompt '" SubStr(WkPromptDest, 1, 30) "', " Round(usDist) " off", usKey)
		;(its title misread - 2026-11-14 Dulin's Hammer as "DTNTRSHANNER": 8 prompts in 33 s and no X, given up "570 off", 5 times
		;in a day: a "Press X to <the goal's verb>" within 300 of it, nothing else named nearer - its own: UseOwnPrompt)
		if (UsPrompt = "press" && usDist <= 300 && UseOwnPrompt(usNav, usDist, goal))
			return UseX(UsIt, "the prompt by it ('" SubStr(WkPromptDest, 1, 30) "' - to " WkPromptVerb ", nothing else named nearer), " Round(usDist) " off", usKey)
		}
	;Right by it (within 120, or held up within 300 - its body): stood there once stood on, held up, or 3 s by it; no prompt at all
	;on the last look - one X in case (never into another's prompt); another's prompt all the while (6 s) - not it: left
	usHeld := HeldW && UsStillAt && A_TickCount - UsStillAt > 1500 && usDist <= 300 && (usNav.x - UsStillX) ** 2 + (usNav.y - UsStillY) ** 2 < 3600
	if (usDist <= 120 || usHeld)
		UsBareAt := UsBareAt ? UsBareAt : A_TickCount
	else if (usDist > 350)
		UsBareAt := 0
	if (UsBareAt && (usDist <= 50 || usHeld || A_TickCount - UsBareAt >= 3000))
		{
		ReleaseKeys()
		if (A_TickCount - UsBareAt >= 3000 && UsPrompt = "" && UsPromptAt && A_TickCount - UsPromptAt < 1500)
			{
			UsBlind := 1
			return UseX(UsIt, "no prompt at it in 3 s - one X in case", usKey)
			}
		if (A_TickCount - UsBareAt >= 6000)
			return UseLeave("another prompt by it all the while ('" SubStr(WkPromptDest, 1, 30) "'), not its own")
		SetStatus("using - by " UsIt.name)
		Sleep(150)
		return true
		}
	if (UseStuck(usNav, usDist, "use"))
		return true
	SetStatus("using - walking to " UsIt.name " (" Round(usDist) " away)")
	DgSteer(usNav, V1Obj({x: UsIt.x, y: UsIt.y}), usDist)
	return true
	}

;Could the "Press X" prompt up now (InteractPrompt's - WkPromptDest, WkPromptVerb, WkPromptText) be a goal thing's own, by its words
;alone? Its verb the goal's ("Press X to Collect" for "Collect Dulin's Hammer in Nastrond") or the game's plain "Interact" (2026-11-17
;"Collect Well Stones in Savannah": "WELL STONES - Press X to Interact" - the goal's verb never on it, so a misread title was never
;X'd), no Crowns on it (Walker.ahk WalkPromptCrowns), no teleport (unless the thing is one - name: its name), no place's name for a
;title ("TO NEMEAN ROCK": a teleport stone's) nor a World Gate's, not a talk / shop / ride prompt. Never the quest line's words
;alone: that line sits over every prompt while the quest is tracked
UseOwnPromptText(goal, name := "")
	{
	if (StrLen(WkPromptDest) < 3 || WalkPromptCrowns())
		return false
	if (RegExMatch(WkPromptDest " " WkPromptText, "i)teleport") && !InStr(WalkLetters(name), "TELEPORT"))
		return false
	if (WkPromptVerb != "" && RegExMatch(WkPromptVerb, "i)^(talk|speak|chat|shop|trade|buy|sell|browse|craft|learn|train|ride|mount|board|join|enter)"))
		return false
	;(a title that's where it goes - a teleport stone's "TO NEMEAN ROCK", its own word "Teleport" not on the panel - or a World Gate's
	;read as a plain prompt: never)
	if (RegExMatch(WkPromptText, "m)^\s*TO\s+[A-Z]") || RegExMatch(WkPromptText, "i)w[o0]rld\s*gate|spiral"))
		return false
	;(the goal's verb on the prompt: read after "Press X ... to", else its letters "TO<verb>" in the prompt - the OCR can put "Press"
	;after "to Collect" (2026-11-14 17:24: "...DTNTRSCORTOCOLLECTPRESS", no verb read). The quest line over the prompt starts with
	;the verb, never "to" before it. Or "Interact", the game's word on any object that has no verb of its own)
	if (!RegExMatch(Trim(goal), "^([A-Za-z]{3,})", &uotG))
		return false
	return ((WkPromptVerb != "" && (WkPromptVerb = uotG[1] || WkPromptVerb = "Interact")) || InStr(WkPromptDest, "TO" StrUpper(uotG[1]))
		|| InStr(WkPromptDest, "TOINTERACT") || InStr(WalkLetters(WkPromptText), "TOINTERACT")) ? true : false
	}

;Is the "Press X" prompt up now the thing's own (it: UsIt when not given), its title misread? Its words could be (UseOwnPromptText),
;and no other thing the game names (things: UsThings when not given - not a mob, not another of the goal's) within 400 of the wizard
;and nearer than the thing (me: {x, y}, d: the wizard's distance to it)
UseOwnPrompt(me, d, goal, it := "", things := "")
	{
	uopIt := IsObject(it) ? it : UsIt
	uopThings := IsObject(things) ? things : IsObject(UsThings) ? UsThings : []
	if (!IsObject(uopIt) || !IsObject(me) || me.x = "" || me.y = "" || d = "" || !UseOwnPromptText(goal, uopIt.name))
		return false
	for i, uopT in uopThings
		{
		if (uopT.kind = "mob" || uopT.quest || uopT.x = "" || uopT.y = "")
			continue
		if (UseT(uopT) = UseT(uopIt) && (uopT.x - uopIt.x) ** 2 + (uopT.y - uopIt.y) ** 2 <= 160000)
			continue
		uopD := Sqrt((me.x - uopT.x) ** 2 + (me.y - uopT.y) ** 2)
		if (uopD <= 400 && uopD < d + 50)
			return false
		}
	return true
	}

;A use goal's prompt met outside UseStep's walk to a thing - waiting at the goal (Walker.ahk WalkPromptWanted: the wait's X, the
;walker's look), before use mode began, or looking about with nothing to go for: is it the own prompt (UseOwnPrompt) of the nearest of
;the goal's things standing there now - the game's memory's (things: UsThings when given, else /items far, read again every 3 s at
;most - asked only once the prompt's own words could be a thing's: UseOwnPromptText) - within 300 of the wizard (the game's memory's
;last reading - WkNavLast) on the same floor? Not when that nearest one was used, is left for a while or was tried twice for this
;goal: its prompt isn't one to X, nor is it the next one's. A zone file's spot within 300 is one used or picked up already (the
;memory holds all within ~6.7k): never what a prompt is by. A misread title "to Interact" by Well Stones (2026-11-17) was "not the
;quest's" there, by the name alone. goal: the goal line
UseOwnPromptNear(goal, things := "")
	{
	global UopnThings, UopnGoal, UopnAt ; (v1 globals it sets)
	if (goal = "" || !IsObject(WkNavLast) || WkNavLast.x = "" || WkNavLast.y = "" || (Stats.Has("collectmem") && !Stats["collectmem"]) || !VisionOn)
		return false
	if (!UseOwnPromptText(goal))
		return false
	if (IsObject(things))
		uonAll := things
	else
		{
		if (!IsObject(UopnThings) || UopnGoal != goal || A_TickCount - V1N(UopnAt) > 3000)
			{
			uonGot := CollectItems(goal, true)
			UopnThings := IsObject(uonGot) ? uonGot : [], UopnGoal := goal, UopnAt := A_TickCount
			}
		uonAll := UopnThings
		}
	uonBest := "", uonD := ""
	for i, uonX in uonAll
		{
		if (!uonX.quest || uonX.src = "file" || uonX.kind = "npc" || uonX.kind = "mob" || uonX.x = "" || uonX.y = "")
			continue
		if (uonX.z != "" && WkNavLast.z != "" && Abs(uonX.z - WkNavLast.z) >= 150)
			continue
		uonXd := Sqrt((WkNavLast.x - uonX.x) ** 2 + (WkNavLast.y - uonX.y) ** 2)
		if (uonD = "" || uonXd < uonD)
			uonBest := uonX, uonD := uonXd
		}
	if (!IsObject(uonBest) || uonD > 300)
		return false
	;(this goal's records - UseBegin's key, use mode having run for it: the nearest used, or tried twice)
	uonKey := SubStr(UsGoalWas, 1, 4) = "use:" ? UsGoalWas : ""
	if (uonKey != "" && ((IsObject(UsDone) && UsDone.Has(uonKey) && UseIn(UsDone[uonKey], uonBest))
		|| UseFails(uonKey, UseT(uonBest), uonBest.x, uonBest.y) >= 2))
		return false
	if (IsObject(UsSkip) && UseSkipped(uonBest))
		return false
	return UseOwnPrompt(V1Obj({x: WkNavLast.x, y: WkNavLast.y}), uonD, goal, uonBest, uonAll)
	}

;The zone's volumes (the helper's /volumes - its volumes.xml: a quest's places, doors' teleports): [{name, x, y, z, r}] - asked
;once a zone, again after 30 s if it couldn't be read
UseVolumes()
	{
	global UsVolsAt, UsVolsZone, UsVols ; (v1 globals it sets)
	uvZone := IsObject(WkNavLast) ? WkNavLast.zone : ""
	if (uvZone = "")
		return []
	if (uvZone = UsVolsZone && IsObject(UsVols))
		return UsVols
	if (uvZone = UsVolsZone && UsVolsAt && A_TickCount - UsVolsAt < 30000)
		return []
	UsVolsAt := A_TickCount, UsVolsZone := uvZone, UsVols := ""
	uvAns := VisionGet("/volumes?zone=" NavUri(uvZone), 2500, true)
	if (uvAns = "" || SubStr(uvAns, 1, 3) = "ERR")
		return []
	UsVols := []
	Loop Parse, uvAns, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		;(v1: an empty line's first field and a field + 0 that isn't a number read blank)
		if (V1At(f, 1) = "vol" && f.Length >= 6)
			UsVols.Push(V1Obj({name: f[2], x: V1Add(f[3], 0), y: V1Add(f[4], 0), z: V1Add(f[5], 0), r: V1Add(f[6], 0), src: "volume", dist: ""}))
		}
	return UsVols
	}

;One step of going to a place the game shows no way to (WkCollect.kind "go" - WAYPOINT: "Go To Damaged Monolith in ..."): the place
;by its name - a thing the goal names or so named (the game's memory's, the zone file's: /items far), else a volume of the zone's
;so named (/volumes) - walked to round walls and mobs, no X; the goal moving on is the walker's to see (CollectStep). Within 150
;for 5 s with the goal as it was: walked on through its middle, then the notice. None found: the walker looks about, 3 minutes,
;then the notice. goal: the goal line. True when it did this step
GoStep(goal)
	{
	global UsAskAt, UsThings, UsIt, UsD, UsNoneFrom, UsAtFrom, UsThrough, UsTries, UsStillAt ; (v1 globals it sets)
	if ((Stats.Has("collectmem") && !Stats["collectmem"]) || !VisionOn)
		return false
	gsKey := UseBegin("go")
	gsName := WalkLetters(WalkGoalItemName(goal))
	if (!UsAskAt || A_TickCount - UsAskAt > 1500)
		{
		UsAskAt := A_TickCount
		gsGot := CollectItems(goal, true)
		UsThings := IsObject(gsGot) ? gsGot : []
		}
	gsPick := ""
	for i, gsX in UsThings
		if (gsX.kind != "mob" && (gsX.quest || (StrLen(gsName) >= 4 && WalkLetters(gsX.name) = gsName)) && !UseSkipped(gsX))
			{
			gsPick := gsX
			break
			}
	if (!IsObject(gsPick) && StrLen(gsName) >= 6)
		{
		gsMe := IsObject(WkNavLast) ? WkNavLast : ""
		for i, gsV in UseVolumes()
			if (InStr(WalkLetters(gsV.name), gsName) && !UseSkipped(gsV))
				{
				gsV.dist := (IsObject(gsMe) && gsMe.x != "" && gsMe.y != "") ? Sqrt((gsV.x - gsMe.x) ** 2 + (gsV.y - gsMe.y) ** 2) : 0
				if (!IsObject(gsPick) || gsV.dist < gsPick.dist)
					gsPick := gsV
				}
		}
	if (!IsObject(gsPick))
		{
		if (IsObject(UsIt))
			{
			WalkLog("go: the place isn't known any more - looking about")
			UsIt := "", UsD := ""
			ReleaseKeys()
			}
		return UseNothing(0, "place by that name", goal)
		}
	UsNoneFrom := 0
	if (!IsObject(UsIt) || (gsPick.x - UsIt.x) ** 2 + (gsPick.y - UsIt.y) ** 2 > 160000)
		{
		UsAtFrom := 0, UsThrough := 0, UsTries := 0, UsStillAt := 0
		WalkLog("go: " gsPick.name " (" (gsPick.src = "volume" ? "a volume of the zone's" : gsPick.src = "file" ? "the zone's file" : "the game's memory")
			. ", at " Round(gsPick.x) ", " Round(gsPick.y) ") - walking to it, no X")
		}
	UsIt := gsPick
	gsNav := PartyNavTo(V1Obj({x: UsIt.x, y: UsIt.y, z: UsIt.z}), true)
	if (!IsObject(gsNav))
		{
		ReleaseKeys()
		Sleep(200)
		return true
		}
	gsD := Sqrt((gsNav.x - UsIt.x) ** 2 + (gsNav.y - UsIt.y) ** 2), UsD := gsD
	;(walked on through its middle: 2.5 s at most, then the notice)
	if (UsThrough)
		{
		if (A_TickCount - UsThrough < 2500)
			{
			if (gsD > 40)
				DgSteer(gsNav, V1Obj({x: UsIt.x, y: UsIt.y}), gsD)
			else
				HoldW(1)
			SetStatus("going - through " UsIt.name)
			return true
			}
		ReleaseKeys()
		UsThrough := 0, UsAtFrom := 0
		WalkLog("go: at " UsIt.name " and through it, the goal as it was - stopping here, telling you")
		CollectGiveUp("", "at " UsIt.name " (found by its name - the game shows no way to it), and the quest didn't move on: stood there 5 s, walked through it", "Quest needs you")
		return true
		}
	if (gsD <= 150)
		{
		UsAtFrom := UsAtFrom ? UsAtFrom : A_TickCount
		if (A_TickCount - UsAtFrom >= 5000)
			{
			UsThrough := A_TickCount
			WalkLog("go: at " UsIt.name " 5 s and the goal as it was - walking on through its middle")
			return true
			}
		ReleaseKeys()
		SetStatus("going - at " UsIt.name ", waiting for the goal to move on")
		Sleep(150)
		return true
		}
	if (gsD > 250)
		UsAtFrom := 0
	if (UseStuck(gsNav, gsD, "go"))
		return true
	SetStatus("going - walking to " UsIt.name " (" Round(gsD) " away)")
	DgSteer(gsNav, V1Obj({x: UsIt.x, y: UsIt.y}), gsD)
	return true
	}

;Fewer than 3 X at the talk goal's NPC from TalkStep in the last 2 minutes (the older ones dropped)
UseTalkTries()
	{
	global UsTalkXs ; (v1 globals it sets)
	utKeep := []
	for i, utAt in UsTalkXs
		if (A_TickCount - utAt < 120000)
			utKeep.Push(utAt)
	UsTalkXs := utKeep
	return UsTalkXs.Length < 3
	}

;X at the talk goal's NPC from TalkStep (never with Crowns on its prompt): the walker's own talk (Walker.ahk StartTalk -
;WkArrived 2: the dialogue Spaced through, X again or the wait by it); a try counted. d: how far, why: for the log. True
UseTalkX(d, why)
	{
	global UsBareAt ; (v1 globals it sets)
	if (RegExMatch(WkPromptText, "i)cr[o0]wn"))
		return UseLeave("Crowns on its prompt - never an X there")
	UsTalkXs.Push(A_TickCount)
	UsBareAt := 0
	WalkLog("talk: " UsIt.name " (" why ") - X")
	StartTalk(d, false)
	return true
	}

;One step of talking to an NPC the game shows no way to (WkCollect.kind "talk" - PERSONA): the NPC by its keys (the goal's first
;and last name's) or its whole name - the game's memory's or the zone file's (/items far) - walked to round walls and mobs; its
;place stands in for the goal's (Walker.ahk WalkNav, WkNpTarget), so near it with the game's memory steering, the walker's own
;approach and talk logic take over (X at its own prompt, 3 tries in 2 minutes, the wait by it); else X from here at its prompt
;naming it - or by it with none of its own for 3 s - 3 in 2 minutes, then waiting by it with the notice. None found: the walker
;looks about, 3 minutes, then the notice. goal: the goal line. True when it did this step
TalkStep(goal)
	{
	global UsAskAt, UsThings, UsIt, UsD, UsNoneFrom, UsTries, UsStillAt, UsBareAt, UsPrompt, WkNpTarget, UsHandAt, WkArrived ; (v1 globals it sets)
	global WkBestTime, WkLastRead, UsNoted, UsPromptAt ; (v1 globals it sets)
	if ((Stats.Has("collectmem") && !Stats["collectmem"]) || !VisionOn)
		return false
	tsKey := UseBegin("talk")
	tsNpc := WalkGoalItemName(goal), tsLetters := WalkLetters(tsNpc)
	if (!UsAskAt || A_TickCount - UsAskAt > 1500)
		{
		UsAskAt := A_TickCount
		tsGot := CollectItems(goal, true)
		UsThings := IsObject(tsGot) ? tsGot : []
		}
	tsPick := ""
	;(the helper's own verdict too: an NPC it takes for the goal's - the goal's NPC as its whole name; the template's key isn't
	;always the goal's: The Archivist's NPCs_01747544 for the goal's NPCs_01747545, live 2026-10-25)
	for i, tsX in UsThings
		if (tsX.kind != "mob" && ((tsX.key != "" && (tsX.key = WkGoalNpcFirst || tsX.key = WkGoalNpcLast)) || (tsX.quest && tsX.kind = "npc")
			|| (StrLen(tsLetters) >= 4 && WalkLetters(tsX.name) = tsLetters)) && !UseSkipped(tsX))
			{
			tsPick := tsX
			break
			}
	if (!IsObject(tsPick))
		{
		if (IsObject(UsIt))
			{
			WalkLog("talk: " tsNpc " isn't known any more - looking about")
			UsIt := "", UsD := ""
			ReleaseKeys()
			}
		return UseNothing(0, "NPC by that name", goal)
		}
	UsNoneFrom := 0
	tsGid := WkNpGoal != "" ? WkNpGoal : WkGoalId
	if (!IsObject(UsIt) || (tsPick.x - UsIt.x) ** 2 + (tsPick.y - UsIt.y) ** 2 > 160000)
		{
		UsTries := 0, UsStillAt := 0, UsBareAt := 0, UsPrompt := "-"
		WalkLog("talk: " tsPick.name " " Round(tsPick.dist) " away (" (tsPick.src = "file" ? "the zone's file" : "the game's memory") ", at "
			. Round(tsPick.x) ", " Round(tsPick.y) ") - walking to it; it stands in for the goal's place")
		}
	UsIt := tsPick
	WkNpTarget := V1Obj({goalid: tsGid, x: tsPick.x, y: tsPick.y, z: tsPick.z, name: tsPick.name})
	tsNav := PartyNavTo(V1Obj({x: UsIt.x, y: UsIt.y, z: UsIt.z}), true)
	if (!IsObject(tsNav))
		{
		ReleaseKeys()
		Sleep(200)
		return true
		}
	tsD := Sqrt((tsNav.x - UsIt.x) ** 2 + (tsNav.y - UsIt.y) ** 2), UsD := tsD
	;(near, the game's memory steering and the NPC standing in for the goal's place this step: the walker's own approach and talk
	;logic from here - WalkApproach, X at its own prompt, its tries, the wait by it. Back here within 15 s - the memory couldn't
	;stand in for the arrow after all: on from here, no handing back and forth)
	if (tsD <= ApproachUnits * 0.8 && WkNavUse && WkNavOk && IsObject(WkNavObj) && tsGid != "" && WkNavObj.goalid "|" = tsGid "|" && WkNavObj.hops = 0
		&& !(UsHandAt && A_TickCount - UsHandAt < 15000))
		{
		WalkLog("talk: " UsIt.name " " Round(tsD) " off - the walker's own talk logic takes it from here")
		UsHandAt := A_TickCount
		ReleaseKeys()
		WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
		return true
		}
	;(its tries used - 3 X in 2 minutes, these or the walker's: waiting where it is, the notice once)
	if (!UseTalkTries() || !WalkTalkTriesLeft())
		{
		ReleaseKeys()
		if (UsNoted != tsKey)
			{
			UsNoted := tsKey
			WalkLog("talk: X at " UsIt.name " 3 times in 2 minutes and nothing came of it - waiting, X again in a while")
			WalkNotify("collect", "Talking to " UsIt.name " didn't work", "X at " UsIt.name " (found by its name - the game shows no way to it) opened nothing 3 times, or its dialogue left the quest as it was, so the bot waits by it and tries again every 2 minutes. Talk to it yourself if it needs something the bot can't do - it walks on by itself once there's a new goal.")
			}
		SetStatus("finding - " UsIt.name ": X did nothing, waiting")
		Sleep(300)
		return true
		}
	;(within TalkReach: its prompt read every 0.7 s - X at the one naming it; within TalkUnits none of its own for 3 s: X there all
	;the same - the talk logic decides)
	if (tsD <= TalkReach && (!UsPromptAt || A_TickCount - UsPromptAt >= 700))
		{
		UsPromptAt := A_TickCount
		UsPrompt := InteractPrompt()
		if (UsPrompt = "press" && WalkUseNames(WkPromptDest, goal))
			return UseTalkX(Round(tsD), "its prompt '" SubStr(WkPromptDest, 1, 30) "', " Round(tsD) " off")
		}
	if (tsD <= TalkUnits)
		{
		UsBareAt := UsBareAt ? UsBareAt : A_TickCount
		ReleaseKeys()
		if (A_TickCount - UsBareAt >= 3000 && UsPrompt = "" && UsPromptAt && A_TickCount - UsPromptAt < 1500)
			return UseTalkX(Round(tsD), "by it, no prompt of its own in 3 s")
		SetStatus("finding - by " UsIt.name)
		Sleep(150)
		return true
		}
	UsBareAt := 0
	if (UseStuck(tsNav, tsD, "talk"))
		return true
	SetStatus("finding - walking to " UsIt.name " (" Round(tsD) " away)")
	DgSteer(tsNav, V1Obj({x: UsIt.x, y: UsIt.y}), tsD)
	return true
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
CollectBlank()
	{
	global CiGid := "", CiFrom := "", CiItems := "", CiAskAt := "", CiSkip := "", CiStillAt := "", CiStillX := "", CiStillY := "", CiTries := ""
	global CiOnAt := "", CiXAt := "", CiStepAt := "", CiLine := "", CiLineAt := "", UsIt := "", UsFrom := "", UsBudget := "", UsThings := ""
	global UsAskAt := "", UsDone := "", UsSkip := "", UsXs := "", UsXAt := "", UsCount0 := "", UsGoalX := "", UsBlind := "", UsAfterX := ""
	global UsBareAt := "", UsNoneFrom := "", UsPromptAt := "", UsPrompt := "", UsStillAt := "", UsStillX := "", UsStillY := "", UsTries := ""
	global UsStepAt := "", UsCountAt := "", UsGoalWas := "", UsLastCount := "", UsD := "", UsNearCount := "", UsFails := "", UsVols := ""
	global UsVolsZone := "", UsVolsAt := "", UsAtFrom := "", UsThrough := "", UsNoted := "", UsTalkXs := "", UsHandAt := ""
	global CiPromptAt := "", CiXn := "", UopnThings := "", UopnGoal := "", UopnAt := ""
	}
