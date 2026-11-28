#Warn Unreachable, Off
; Spells.ahk - the dashboard's Spells tab: every card the bot learned by itself (learned\cards.txt), what it took
; each one for and where it uses it - and your corrections. AHK v1.1, functions and labels only; #Included by
; Autofarmer.ahk after Dungeons.ahk (Dashboard.ahk makes the tab's controls).
;
; Pick a spell (or several) and:
;   Change kind...   what it is: a hit on one enemy or on all, a heal, a shield, an absorb, a blade, a trap, an aura,
;                    a bubble (a global: your school's bubble slot, <school>\bubble), a negative aura, an enchant, a
;                    Sharpened Blade, a Potent Trap, a prism (your school's: <school>\convert) - or a kind the bot
;                    doesn't play (a weakness, a curse, a charm that isn't a blade, another enchantment, a mutation, a
;                    polymorph, a shadow form, a minion, pips, a manipulation spell, Not used: kept in the list, never
;                    cast - every battle spell type of the game's has one). It's taken out of its slot (a hit that made
;                    room for itself in hit1-3 puts the hits it moved back) and gets the slot the new kind fits, if
;                    one is free
;   Edit...          its name, its number (damage, heal, %) and its pips - a misread number, guessed pips
;   Forget           out of the list, its pictures to backups\learned forgotten. A real card is learned again the
;                    next time it's in hand: to keep one out of use, change its kind to "Not used" instead
;   Never discard    it stays in hand (the bot discards the cards it never plays - never a treasure card)
;   Show picture, Open folder, Moved away... (backups\: non-cards taken out of the list, forgotten spells, the hits
;                    moved to make room for a stronger one), Refresh (learned\cards.txt read again)
; A correction is only queued here (SpQueue). The bot applies it from its own loop, out of battle (SpApplyPending),
; through the card learner's own functions (CardLearn.ahk: LearnSetKind, LearnEdit, LearnForgetById, LearnToggleHold)
; - never in a round, where a slot's picture moving would change what the round's plan is about. What you set is
; marked yours (flag user): the learner never changes it by itself again.

;The tab's controls (Dashboard.ahk makes them)
global SpList, SpHelp, SpStatus, SpKindBtn, SpEditBtn, SpForgetBtn, SpHoldBtn, SpPicBtn, SpFolderBtn, SpMovedBtn, SpRefreshBtn
global SpPreview, SpPreviewTxt
;Corrections waiting for the bot's loop ([{op, arg, ids}]: SpQueue); the list to be filled again (LearnSave sets it);
;the kinds in the Change kind menu ([{kind, label, played}], in its order); the Moved away menu's folders; the note
;under the counts on the status line
global SpPending, SpDirty, SpKinds, SpMovedPaths, SpNoteText
;The Edit window: it, the spell it edits, its fields
global SpEdHwnd, SpEdId, SpEdName, SpEdValue, SpEdPips, SpEdNote
;(tests only: the answer to the Forget question without asking - blank: it's asked)
global SpAskAnswer
;A cell edited in the list itself (double-click - SpCellEdit): its little window, the spell, the column (name, value,
;pips), what's typed
global SpCellHwnd, SpCellId, SpCellCol, SpCellText, SpCellShown
;(a picked cell - Kind, School, TC: its dropdown's values by place, and whether its list was down at the last look)
global SpCellChoices, SpCellDropped
;(tests only: the cell's box made but not shown)
global SpCellHidden

;Called once by DashInit, after the other tabs are made: the queue, the Change kind menu, the list
SpInit()
	{
	global SpPending, SpDirty, SpNoteText, SpKinds, SpKindMenu ; (v1 globals it sets)
	;(declared without a value: an initializer in an #Included file never runs)
	if (!IsObject(SpPending))
		SpPending := []
	SpDirty := 0, SpNoteText := ""
	SpKinds := SpKindList()
	;(v1: Menu, SpKindMenu, Add - the menu made by its first item)
	SpKindMenu := Menu()
	for i, k in SpKinds
		SpKindMenu.Add(SpKindItem(k), SpKindChosen)
	SpListFill()
	}

;The kinds a learned spell can be set to, for the Change kind menu ([{kind, label, played}]): CardLearn.ahk's
;LearnTypes() - the ones it offers (menu) - else the ones the learner has always known. Not "" (unknown): "Not used"
;keeps one out of use
SpKindList()
	{
	list := []
	got := SpL("LearnTypes")
	if (IsObject(got))
		for i, t in got
			{
			if (!IsObject(t) || t.kind = "" || (t.Has("menu") && !t.menu))
				continue
			list.Push(V1Obj({kind: t.kind, label: t.label != "" ? t.label : t.kind, played: t.played ? 1 : 0}))
			}
	;(the learner's own kinds since 2026-10-26 - every battle spell type of the game's: CardLearn.ahk LearnTypes)
	if (!list.Length)
		for i, t in [["damage", "Hits one enemy"], ["aoe", "Hits all enemies"], ["heal", "Heals you"], ["ward", "Shield (cast on you)"]
			, ["absorb", "Absorb (soaks N damage - cast on you)"], ["blade", "Blade"], ["trap", "Trap"], ["aura", "Aura"]
			, ["bubble", "Bubble (a global spell - all of the battle)"], ["negaura", "Negative aura (on an enemy for 4 rounds)"]
			, ["enchant", "Enchant (+N damage on a hit)"], ["sharpen", "Sharpened Blade (+N% on a blade)"], ["potent", "Potent Trap (+N% on a trap)"]
			, ["prism", "Prism (converts the school)"], ["dot", "Damage over time"], ["stun", "Stun"], ["dispel", "Dispel"]
			, ["clear", "Removes shields or charms (N times Clear)"], ["weakness", "Weakness (-N% on an enemy's next hit)"]
			, ["curse", "Curse (an enemy's accuracy or healing down)"], ["charm", "Charm, not a blade (spear, accuracy, healing)"]
			, ["enchantother", "Enchantment, other (accuracy, protect, cloak...)"], ["mutate", "Mutation (turns a spell in hand into another)"]
			, ["polymorph", "Polymorph / shift (Moon)"], ["shadow", "Shadow form or creature (shadow pips)"], ["minion", "Minion (summons one, or works on yours)"]
			, ["pips", "Pips (gives you or an ally pips)"], ["manipulation", "Manipulation (steal charm / ward, aggro, push...)"], ["keep", "Not used (stays in the list)"]]
			list.Push(V1Obj({kind: t[1], label: t[2], played: InStr(",damage,aoe,heal,ward,absorb,blade,trap,aura,bubble,negaura,enchant,sharpen,potent,prism,", "," t[1] ",") ? 1 : 0}))
	return list
	}

;A kind's line in the Change kind menu: its label, "(not played)" for one the bot doesn't play
SpKindItem(k)
	{
	return StrReplace(k.label, "&", "and") (k.played ? "" : "   (not played)")
	}

;A kind's label for the list (CardLearn.ahk's LearnKindLabel: "unknown" for "")
;The schools for the School column's dropdown (CardLearn.ahk LearnSchools - the seven, Sun, Star, Moon, Shadow)
SpSchools()
	{
	got := SpL("LearnSchools")
	return IsObject(got) ? got : ["fire", "ice", "storm", "myth", "life", "death", "balance", "sun", "star", "moon", "shadow"]
	}

SpKindLabel(kind)
	{
	if (V1IsFunc("LearnKindLabel"))
		return LearnKindLabel.Call(kind)
	if (IsObject(SpKinds))
		for i, k in SpKinds
			if (k.kind = kind)
				return k.label
	return kind = "" ? "unknown" : kind
	}

;A function of the card learner (CardLearn.ahk) called by its name: "" when there's no such function, so this tab
;loads whatever the learner's functions are called
SpL(fn, args*)
	{
	return V1IsFunc(fn) ? %fn%.Call(args*) : ""
	}

;---- The list ----

;Fills the list from the catalog (the spells selected stay selected) and the status line. Only what the catalog
;says: never asks the vision helper or looks for a free slot (LearnSlotFor / LearnFree would)
SpListFill()
	{
	global SpDirty ; (v1 globals it sets)
	if (!DashHwnd)
		return
	;(a cell's box open over a row - SpCellOpen: filled again once it's closed, the next look (DashRefresh) - filled now,
	;the box would sit over another spell)
	if (SpCellHwnd)
		{
		SpDirty := 1
		return
		}
	wasCrit := A_IsCritical
	Critical()
	if (!IsObject(LearnedCards))
		SpL("LearnLoad")
	lv := SpListSelect()
	keep := V1Obj()
	row := 0
	while (row := lv.GetNext(row))
		{
		id := lv.GetText(row, 12)
		keep[id] := 1
		}
	;(where the list was scrolled to and the row with the focus, by id: kept - every catalog save filled it again from the
	;top, the list jumping back to row 1 while you looked further down)
	slTop := DllCall("SendMessage", "Ptr", lv.Hwnd, "UInt", 0x1027, "Ptr", 0, "Ptr", 0, "Ptr")       ; LVM_GETTOPINDEX
	slPage := DllCall("SendMessage", "Ptr", lv.Hwnd, "UInt", 0x1028, "Ptr", 0, "Ptr", 0, "Ptr")      ; LVM_GETCOUNTPERPAGE
	slTopId := (slTop >= 0 && slTop < lv.GetCount()) ? lv.GetText(slTop + 1, 12) : ""
	slFocus := lv.GetNext(0, "F"), slFocusId := slFocus ? lv.GetText(slFocus, 12) : ""
	slTopRow := 0, slFocusRow := 0
	lv.Opt("-Redraw")
	lv.Delete()
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			{
			row := lv.Add("", SpName(c), SpKindText(c), SpSchoolText(c), SpPipsText(c), SpValueText(c), SpSureText(c), SpInUse(c), c.text
				, SpFlag(c, "tc") ? "yes" : "", SpWhen(c.when), c.dir = "" ? "main" : c.dir, c.id)
			if (keep.Has(c.id))
				lv.Modify(row, "Select")
			if (slTopId != "" && c.id = slTopId)
				slTopRow := row
			if (slFocusId != "" && c.id = slFocusId)
				slFocusRow := row
			}
	lv.Opt("+Redraw")
	if (slFocusRow)
		lv.Modify(slFocusRow, "Focus")
	;(the top row as it was: the row a page below it scrolled into view - the list goes down till that's its last)
	if (slTopRow > 1 && slPage > 0)
		lv.Modify(Min(slTopRow + slPage - 1, lv.GetCount()), "Vis")
	SpListBack(lv)
	SpDirty := 0
	SpStatusShow()
	CfgUncritical(wasCrit, 0)
	}

;Makes SpList the ListView the LV_ functions work on (the window has two: the Dungeons tab's too) and returns the
;one that was - SpListBack puts it back, so a DgListFill this interrupted carries on in its own list.
;(v2: no default ListView - each call names its list: SpListSelect gives the Spells tab's, SpListBack has nothing to
;put back; an interrupted DgListFill keeps its own list as it is)
SpListSelect()
	{
	return Dash["SpList"]
	}

SpListBack(prevLV)
	{
	}

;The ids of the spells selected in the list ([] none)
SpSelectedIds()
	{
	ids := []
	if (!DashHwnd)
		return ids
	wasCrit := A_IsCritical
	Critical()
	lv := SpListSelect()
	row := 0
	while (row := lv.GetNext(row))
		{
		id := lv.GetText(row, 12)
		if (id != "")
			ids.Push(id)
		}
	SpListBack(lv)
	return CfgUncritical(wasCrit, ids)
	}

;The counts, the corrections waiting and the last note
SpStatusShow()
	{
	if (!DashHwnd)
		return
	n := 0, nUse := 0
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			n += 1, nUse += (c.slot != "")
	text := n " spell" (n = 1 ? "" : "s") " - " nUse " in use, " n - nUse " kept"
	junk := SpLineCount(A_WorkingDir "\backups\learned junk\cards.txt")
	if (junk)
		text .= " | " junk " non-card" (junk = 1 ? "" : "s") " moved away"
	waiting := IsObject(SpPending) ? SpPending.Length : 0
	if (waiting)
		text .= " | " waiting " change" (waiting = 1 ? "" : "s") " waiting (applied out of battle)"
	;(two lines, each cut to what fits the narrowest window: Consolas 9 is about 7 px a letter)
	note := StrLen(SpNoteText) > 100 ? SubStr(SpNoteText, 1, 99) "~" : SpNoteText
	Dash["SpStatus"].Value := text (note != "" ? "`n" note : "")
	}

;A line under the counts (what was queued, what was done)
SpNote(text)
	{
	global SpNoteText ; (v1 globals it sets)
	SpNoteText := text
	SpStatusShow()
	}

;How many lines that aren't comments a file has (0 if it isn't there)
SpLineCount(file)
	{
	n := 0
	if (!FileExist(file))
		return 0
	;(v1: a file Loop Read couldn't open - no lines; v2 throws)
	try
		Loop Read, file
			if (Trim(A_LoopReadLine) != "" && SubStr(A_LoopReadLine, 1, 1) != ";")
				n += 1
	return n
	}

;A learned spell's name: the one you gave it, else the first words of its text in brackets, else ? (LearnName)
SpName(c)
	{
	if (V1IsFunc("LearnName"))
		return LearnName.Call(c)
	if (!IsObject(c))
		return "?"
	return c.name != "" ? c.name : c.text != "" ? "(" c.text ")" : "?"
	}

;The Kind column: the kind's label (X-pip ones say so)
SpKindText(c)
	{
	return SpKindLabel(c.type) (SpFlag(c, "xpip") && c.type != "xpip" ? ", X pips" : "")
	}

;The School column: the card's own school (set here: flag school), else the wizard's it was learned for
SpSchoolText(c)
	{
	s := SpFlag(c, "school")
	return (s != "" && s != 1) ? s : c.sch
	}

;The Pips column: ? not known, 3? guessed (not read off the card)
SpPipsText(c)
	{
	;(an X-pip spell: all your pips)
	if (SpFlag(c, "xpip"))
		return "X"
	if (c.pips = "")
		return "?"
	return c.pips (c.guess ? "?" : "")
	}

;The Value column: its number (a hit's least damage, a heal, a %), with the part over time of a hit that has one
SpValueText(c)
	{
	dot := SpFlag(c, "dot")
	if (c.value = "")
		return (c.type = "" || c.type = "keep" || c.type = "stun" || c.type = "dispel" || c.type = "prism" || c.type = "clear" || c.type = "bubble"
			|| InStr(",curse,charm,enchantother,mutate,polymorph,shadow,minion,pips,manipulation,", "," c.type ",")) ? "" : "?"
	return c.value (dot != "" && dot != 1 ? " (+" dot " over time)" : "")
	}

;The Sure column: how sure the learner is of what it took it for (CardLearn.ahk LearnSure), as a %
SpSureText(c)
	{
	s := SpL("LearnSure", c)
	return IsObject(s) ? s.pct "%" : ""
	}

;The In use column: its slot, else why it's kept (LearnInUse: from the catalog alone - never asks the helper)
SpInUse(c)
	{
	if (V1IsFunc("LearnInUse"))
		return LearnInUse.Call(c)
	return c.slot != "" ? c.slot : "kept"
	}

;yyyyMMddHHmmss as yyyy-MM-dd HH:mm
SpWhen(when)
	{
	if (!RegExMatch(when, "^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)", &w))
		return when
	return w[1] "-" w[2] "-" w[3] " " w[4] ":" w[5]
	}

;Learned spell c's flag key (learned\cards.txt's last field, a comma list: ok, tc, hold, out=<id>...): its value
;(out=<id>: the id; one without a value: 1), "" when it hasn't it
SpFlag(c, key)
	{
	if (!IsObject(c))
		return ""
	fl := c.flags
	if (IsObject(fl))
		return fl.Has(key) ? (fl[key] = "" ? 1 : fl[key]) : ""
	Loop Parse, fl, ","
		{
		p := InStr(A_LoopField, "=")
		k := Trim(p ? SubStr(A_LoopField, 1, p - 1) : A_LoopField)
		if (k = key)
			return p ? SubStr(A_LoopField, (p + 1)<1 ? (p + 1)-1 : (p + 1)) : 1
		}
	return ""
	}

;Its picture: <set>\learned\<id>.card.png (the whole card), else .png - "" when neither is there
SpPicPath(c)
	{
	setDir := A_WorkingDir (c.dir = "" ? "" : "\" c.dir)
	for i, ext in [".card.png", ".png"]
		if (FileExist(setDir "\learned\" c.id ext))
			return setDir "\learned\" c.id ext
	return ""
	}

;What's under the picture: what the learner took it for, its text, when and at what size it was learned, its flags
SpAbout(c)
	{
	desc := SpL("LearnDescribe", c)
	t := SpName(c) (desc != "" ? ": " desc : "")
	t .= "`nText read: " (c.text = "" ? "-" : c.text)
	sure := SpL("LearnSure", c)
	if (IsObject(sure))
		t .= "`nSure: " sure.pct "% (" sure.why ")"
	t .= "`nLearned " SpWhen(c.when) (c.scale != "" ? " at UI " c.scale : "") " (" (c.dir = "" ? "main" : c.dir) ")"
	if (SpFlag(c, "tc"))
		t .= "`nA treasure card"
	if (SpFlag(c, "user"))
		t .= "`nSet by you - the learner leaves it as it is"
	if (SpFlag(c, "hold"))
		t .= "`nNever discarded"
	snap := SpFlag(c, "snap")
	if (snap != "" && snap != 1)
		t .= "`nMade room in hit1-3 - what was there: backups\" snap
	return t
	}

;The picture and what's under it, for the spell selected first
SpPreviewShow()
	{
	ids := SpSelectedIds()
	c := ids.Length ? SpL("LearnCardOf", ids[1]) : ""
	if (!IsObject(c))
		{
		Dash["SpPreview"].Visible := false
		Dash["SpPreviewTxt"].Value := ids.Length ? "" : "Pick a spell to see it."
		return
		}
	pic := SpPicPath(c)
	if (pic != "")
		{
		;(the control is sized for 100% display scaling; the picture is loaded at real pixels - as DashHandCard)
		;(v1's GuiControl: a picture it couldn't load only set ErrorLevel - v2 throws)
		try Dash["SpPreview"].Value := "*w" Round(140 * A_ScreenDPI / 96) " *h" Round(233 * A_ScreenDPI / 96) " " pic
		Dash["SpPreview"].Visible := true
		}
	else
		Dash["SpPreview"].Visible := false
	Dash["SpPreviewTxt"].Value := SpAbout(c) (ids.Length > 1 ? "`n(" ids.Length " selected)" : "")
	}

;The dashboard on the Spells tab (the tray menu's "Learned spells")
SpShowTab()
	{
	global SpDirty ; (v1 globals it sets)
	if (!DashHwnd)
		return
	if (!DashShown)
		DashToggle()
	;(minimised - put away - it's shown again)
	spMinMax := V1Try(WinGetMinMax, "ahk_id " DashHwnd)  ; (v1: WinGet MinMax of a window not found - blank, no restore)
	if (spMinMax = -1)
		WinRestore("ahk_id " DashHwnd)
	Dash["DashTabs"].Choose(3)
	SpDirty := 1
	DashRefresh()
	}

;---- Corrections: queued here, applied by the bot's loop ----

;Queues a correction (op: kind / edit / forget / hold / reload; arg: the new kind, the edit's {name, value, pips},
;never-discard on or off) for spells ids. Nothing in the catalog changes here: the GUI thread can interrupt the
;battle's in the middle of going through it
SpQueue(op, arg, ids)
	{
	global SpPending ; (v1 globals it sets)
	if (!IsObject(SpPending))
		SpPending := []
	SpPending.Push(V1Obj({op: op, arg: arg, ids: ids}))
	SpNote("Queued: " SpJobText(op, arg, ids) " - the bot applies it as soon as it's out of battle")
	}

;The newest edit of spell id still waiting in the queue ({name, value, pips, cols} - "" none): an edit made before the
;bot has made the one before builds on it, not on the catalog's old numbers (which would undo it)
;The pips to show for editing: X for an X-pip spell (or one a waiting edit made X), else the number
SpPipsEditText(c, b)
	{
	if (IsObject(b) && b != c)
		return (b.pips = "x" || b.pips = "X") ? "X" : (b.cols = "" || InStr(b.cols, "pips")) ? b.pips : SpFlag(c, "xpip") ? "X" : b.pips
	return SpFlag(c, "xpip") ? "X" : c.pips
	}

SpPendingEdit(id)
	{
	if (!IsObject(SpPending))
		return ""
	i := SpPending.Length
	while (i >= 1)
		{
		job := SpPending[i], i -= 1
		if (job.op = "edit" && job.ids.Length = 1 && job.ids[1] = id)
			return job.arg
		}
	return ""
	}

;A correction in words
SpJobText(op, arg, ids)
	{
	n := IsObject(ids) ? ids.Length : 0
	who := n = 1 ? SpName(SpL("LearnCardOf", ids[1])) : n " spells"
	if (op = "kind")
		return who " -> " SpKindLabel(arg)
	if (op = "school")
		return who " -> school " arg
	if (op = "tc")
		return who (arg ? " a treasure card" : " not a treasure card")
	if (op = "edit")
		return who " edited"
	if (op = "forget")
		return "forget " who
	if (op = "hold")
		return who (arg ? " never discarded" : " may be discarded again")
	if (op = "reload")
		return "the list read again"
	return op
	}

;The corrections queued on the tab, applied - called by the bot's loop (Autofarmer.ahk, the top of TestRound), out
;of battle only: a hit moved between slots mid-battle would leave the round's enchants and saved pips on the
;wrong card. Each goes through the card learner's own function for it (it saves the catalog, writes PlayerStats.txt,
;moves pictures and tells the vision helper)
SpApplyPending()
	{
	global SpPending, SpNoteText, SpDirty ; (v1 globals it sets)
	if (!IsObject(SpPending) || !SpPending.Length || inbattle = 1)
		return
	wasCrit := A_IsCritical
	Critical()
	todo := SpPending, SpPending := []
	if (!IsObject(LearnedCards))
		SpL("LearnLoad")
	said := []
	for i, job in todo
		{
		if (job.op = "reload")
			{
			;(what happened said - LearnLoad's 0: the file not read, the catalog read before kept, or none was: no learned
			;card used till it is - never "read again" for a read that failed)
			spGot := SpL("LearnLoad")
			if (spGot = 0)
				said.Push(LearnLoadFailed ? "learned\cards.txt couldn't be read - no learned card is used till it is (tried again each round)"
					: "learned\cards.txt couldn't be read - the list kept as it was read before")
			else
				said.Push("the list read again from learned\cards.txt")
			continue
			}
		for j, id in job.ids
			{
			c := SpL("LearnCardOf", id)
			if (!IsObject(c))
				continue
			who := SpName(c) " (" id ")"
			if (job.op = "kind")
				said.Push(who ": " SpDoKind(c, job.arg))
			else if (job.op = "edit")
				{
				;(cells - cols: only the columns typed in, the others as the card is now - the learner may have read its pips
				;or number meanwhile; guessed pips stay guessed unless Pips was typed. The Edit window: all three)
				e := job.arg, cols := e.cols
				eName := cols = "" || InStr(cols, "name") ? e.name : c.name
				eValue := cols = "" || InStr(cols, "value") ? e.value : c.value
				ePips := cols = "" || InStr(cols, "pips") ? e.pips : c.pips
				;(only the name typed: not marked yours - the learner never changes a name, and its number and pips stay
				;the learner's to read)
				nameOnly := cols != "" && !InStr(cols, "value") && !InStr(cols, "pips")
				said.Push(who ": " SpCallLearn("LearnEdit", id, eName, eValue, ePips, cols != "" && !InStr(cols, "pips"), nameOnly))
				}
			else if (job.op = "forget")
				said.Push(who ": " SpCallLearn("LearnForgetById", id))
			else if (job.op = "hold")
				said.Push(who ": " SpDoHold(c, job.arg))
			else if (job.op = "school")
				said.Push(who ": " SpCallLearn("LearnSetSchool", id, job.arg))
			else if (job.op = "tc")
				said.Push(who ": " SpCallLearn("LearnSetTc", id, job.arg))
			}
		}
	text := ""
	for i, t in said
		text .= (text = "" ? "" : "; ") t
	if (text = "")
		text := "nothing to change (not in the list any more)"
	DebugLog("Spells: " text)
	SpNoteText := "Done: " text
	SpDirty := 1
	CfgUncritical(wasCrit, 0)
	}

;Kind change (LearnSetKind: out of its slot - a hit that made room for itself puts what it moved back - the new kind,
;marked yours, then the slot it fits now). The kind it has already: only marked yours (so the learner leaves it), its
;slot kept
SpDoKind(c, kind)
	{
	if (kind = c.type)
		{
		SpL("LearnSetFlag", c, "user")
		SpL("LearnSave")
		return "kept as " SpKindLabel(kind) " - marked yours" (c.slot != "" ? ", still in use as " c.slot : "")
		}
	return SpCallLearn("LearnSetKind", c.id, kind)
	}

;Never discard on (holdOn) or off - LearnToggleHold, only when it isn't so already (several picked at once)
SpDoHold(c, holdOn)
	{
	if ((SpFlag(c, "hold") ? 1 : 0) = (holdOn ? 1 : 0))
		return holdOn ? "never discarded already" : "may be discarded already"
	got := SpCallLearn("LearnToggleHold", c.id)
	return got = 1 ? "never discarded" : got = 0 ? "may be discarded again" : got
	}

;fn of the card learner with args - its answer, or why it couldn't be (no such function in CardLearn.ahk)
SpCallLearn(fn, args*)
	{
	if (!V1IsFunc(fn))
		{
		DebugLog("Spells: CardLearn.ahk has no " fn "() - nothing changed")
		return "not changed (CardLearn.ahk has no " fn ")"
		}
	return %fn%.Call(args*)
	}

;---- The Edit window ----

;Opens it for the spell selected first (hidden: made but not shown - tests)
SpEditShow(hidden := false)
	{
	global SpEdId, SpEd, SpEdHwnd ; (v1 globals it sets)
	ids := SpSelectedIds()
	c := ids.Length ? SpL("LearnCardOf", ids[1]) : ""
	if (!IsObject(c))
		return SpNote("Pick a spell in the list first")
	if (SpEdHwnd)
		Try SpEd.Destroy()
	SpEdId := c.id
	;(an edit still waiting in the queue: shown as it will be)
	b := SpPendingEdit(c.id), b := IsObject(b) ? b : c
	;(v1's +OwnerDash: v2 takes the owner's hwnd)
	SpEd := Gui("+Owner" DashHwnd " -MaximizeBox -MinimizeBox", "Wizard101 bot " BotVersion() " - edit a learned spell"), SpEdHwnd := SpEd.Hwnd
	SpEd.OnEvent("Close", SpEdGuiClose)
	SpEd.OnEvent("Escape", SpEdGuiEscape)
	;(v1: Gui, SpEd:Color, 1B1D22, 111317 - 111317 behind the Edits: each gets Background111317)
	SpEd.BackColor := "1B1D22"
	SpEd.MarginX := 12, SpEd.MarginY := 10
	SpEd.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	SpEd.Add("Text", "x12 y12 w380 h18", SpName(c) " - " SpKindLabel(c.type) " (" c.sch ")")
	SpEd.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	SpEd.Add("Text", "x12 y34 w380 h62", "Text read: " (c.text = "" ? "-" : c.text) "`nThe number: a hit's least damage, a heal's amount, the % of a blade, trap, shield, aura or bubble. Blank: not known. What you set is kept - the learner never changes it by itself.")
	SpEd.SetFont("s9 w400 cDADADA", "Segoe UI")
	SpEd.Add("Text", "x12 y107 w80 h18", "Name")
	SpEd.Add("Text", "x12 y137 w80 h18", "Number")
	SpEd.Add("Text", "x12 y167 w80 h18", "Pips")
	SpEd.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	SpEd.Add("Edit", "x96 y104 w296 h22 Limit40 Background111317 vSpEdName", b.name)
	SpEd.Add("Edit", "x96 y134 w80 h22 Number Limit5 Background111317 vSpEdValue", b.value)
	SpEd.Add("Edit", "x96 y164 w50 h22 Limit2 Background111317 vSpEdPips", SpPipsEditText(c, b))
	SpEd.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	SpEd.Add("Text", "x156 y167 w236 h18", c.guess && c.pips != "" ? "(guessed - Save makes it read)" : "")
	SpEd.SetFont("s9 w400 cB9E2B9", "Segoe UI")
	SpEd.Add("Text", "x12 y196 w380 h32 vSpEdNote")
	SpEd.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonSave := SpEd.Add("Button", "x12 y234 w90 h26 Default", "Save")
	ogcButtonSave.OnEvent("Click", SpEdSave.Bind("Normal"))
	ogcButtonClose := SpEd.Add("Button", "x110 y234 w90 h26", "Close")
	ogcButtonClose.OnEvent("Click", SpEdGuiClose.Bind("Normal"))
	;(next to the dashboard when it's up, else in the middle of the screen)
	pos := ""
	if (DashHwnd && DashShown)
		{
		;(v1: WinGet MinMax / WinGetPos of a window not found gave blanks - no place taken from it; v2 throws, and its
		;WinGetPos unsets the output variables first - the blanks are set in the catch)
		mm := V1Try(WinGetMinMax, "ahk_id " DashHwnd)
		try WinGetPos(&dx, &dy, , , "ahk_id " DashHwnd)
		catch
			dx := "", dy := ""
		if (dx != "" && mm != -1)
			pos := "x" dx + 30 " y" dy + 60 " "
		}
	SpEd.Title := "Wizard101 bot " BotVersion() " - edit a learned spell"
	SpEd.Show(pos (hidden ? "Hide " : "") "AutoSize")
	}

;Save: what was typed checked, then queued (the window closes); a note in the window when it can't be
SpEdSaveNow()
	{
	global SpEdHwnd ; (v1 globals it sets)
	;(v1: Gui, SpEd:Submit, NoHide - the v-variables SpEdName, SpEdValue, SpEdPips set)
	V1GuiSubmit(SpEd, false)
	name := Trim(RegExReplace(SpEdName, "[^\x20-\x7E]|\|", "")), value := Trim(SpEdValue), pips := Trim(SpEdPips)
	c := SpL("LearnCardOf", SpEdId)
	if (!IsObject(c))
		return SpEdSay("That spell isn't in the list any more.")
	if (value != "" && !RegExMatch(value, "^\d{1,5}$"))
		return SpEdSay("The number: digits only (or blank: not known).")
	;(X: an X-pip spell - all your pips)
	if (pips != "" && !RegExMatch(pips, "^[xX]$") && !(RegExMatch(pips, "^\d{1,2}$") && pips <= 14))
		return SpEdSay("Pips: 0 to 14, or X for an X-pip spell (or blank: not known).")
	if (pips = "" && RegExMatch(c.slot, "\\hit\d$"))
		return SpEdSay("It's used as " c.slot ": a hit there needs its pips.")
	value := value = "" ? "" : value + 0, pips := pips = "" ? "" : RegExMatch(pips, "^[xX]$") ? "x" : pips + 0
	b := SpPendingEdit(SpEdId), b := IsObject(b) ? b : c
	;(the pips against what the window showed - SpPipsEditText: an X-pip spell's are 0 in the catalog, shown X - Save with
	;nothing typed queued an edit, the spell marked yours and no longer read from the game)
	bPips := SpPipsEditText(c, b), bPips := (bPips = "x" || bPips = "X") ? "x" : bPips
	if (name == b.name && value = b.value && pips = bPips && !(pips != "" && c.guess))
		return SpEdSay("Nothing changed.")
	SpQueue("edit", V1Obj({name: name, value: value, pips: pips}), [SpEdId])
	Try SpEd.Destroy()
	SpEdHwnd := 0
	}

SpEdSay(text)
	{
	SpEd["SpEdNote"].Value := text
	}

;---- A cell edited in the list itself, as in a spreadsheet (you asked, 2026-10-23) ----

;A double-click on the list: the cell under the mouse - Name, Value or Pips: a box over it to type in (Enter keeps it,
;Esc doesn't, clicking away keeps it); Kind: the Change kind menu there; any other: its picture, as before
SpCellEdit(row, scMx := "", scMy := "")
	{
	;(a box still open - another cell double-clicked before the click away was seen: what's typed there kept first)
	if (SpCellHwnd)
		SpCellCommit()
	scLv := Dash["SpList"].Hwnd
	if (!scLv)
		return SpOpenPic(false)
	;(where the double-click was - the mouse; tests: given)
	if (scMx = "")
		{
		CoordMode("Mouse", "Screen")
		MouseGetPos(&scMx, &scMy)
		}
	scPt := Buffer(8, 0), NumPut("Int", scMx, scPt, 0), NumPut("Int", scMy, scPt, 4)
	DllCall("ScreenToClient", "Ptr", scLv, "Ptr", scPt.Ptr)
	scHt := Buffer(24, 0), NumPut("Int", NumGet(scPt, 0, "Int"), scHt, 0), NumPut("Int", NumGet(scPt, 4, "Int"), scHt, 4)
	DllCall("SendMessage", "Ptr", scLv, "UInt", 0x1039, "Ptr", 0, "Ptr", scHt.Ptr)       ; LVM_SUBITEMHITTEST
	scItem := NumGet(scHt, 12, "Int"), scSub := NumGet(scHt, 16, "Int")
	;(the mouse moved off the double-clicked row before this ran - the bot busy: not another row's cell)
	if (scItem < 0 || scItem + 1 != row)
		return
	;(0 Name, 1 Kind, 2 School, 3 Pips, 4 Value, 8 TC - the list's columns)
	if (scSub != 0 && scSub != 1 && scSub != 2 && scSub != 3 && scSub != 4 && scSub != 8)
		return SpOpenPic(false)
	SpCellOpen(scItem + 1, scSub)
	}

;The box over row's cell in column sub - typed in: 0 Name, 3 Pips, 4 Value; picked from a dropdown: 1 Kind, 2 School,
;8 TC - the row scrolled into view and picked; false if there's no such spell
SpCellOpen(row, scSub)
	{
	global SpCellId, SpCellCol, SpCellShown, SpCell, SpCellHwnd ; (v1 globals it sets)
	scLv := Dash["SpList"].Hwnd
	if (!scLv)
		return false
	lv := SpListSelect()
	if (row < 1 || row > lv.GetCount())
		{
		SpListBack(lv)
		return false
		}
	scId := lv.GetText(row, 12)
	lv.Modify(0, "-Select")
	lv.Modify(row, "Select Focus Vis")
	SpListBack(lv)
	scItem := row - 1
	c := SpL("LearnCardOf", scId)
	if (!IsObject(c))
		return false
	scCol := scSub = 0 ? "name" : scSub = 4 ? "value" : scSub = 3 ? "pips" : scSub = 1 ? "kind" : scSub = 2 ? "school" : scSub = 8 ? "tc" : ""
	if (scCol = "")
		return false
	;(the cell's place on screen - for column 0 its label's, not the whole row's)
	scRc := Buffer(16, 0), NumPut("Int", scSub, scRc, 4), NumPut("Int", scSub = 0 ? 2 : 0, scRc, 0)
	DllCall("SendMessage", "Ptr", scLv, "UInt", 0x1038, "Ptr", scItem, "Ptr", scRc.Ptr)  ; LVM_GETSUBITEMRECT
	scP := Buffer(8, 0), NumPut("Int", NumGet(scRc, 0, "Int"), scP, 0), NumPut("Int", NumGet(scRc, 4, "Int"), scP, 4)
	DllCall("ClientToScreen", "Ptr", scLv, "Ptr", scP.Ptr)
	scX := NumGet(scP, 0, "Int"), scY := NumGet(scP, 4, "Int")
	scW := NumGet(scRc, 8, "Int") - NumGet(scRc, 0, "Int"), scH := NumGet(scRc, 12, "Int") - NumGet(scRc, 4, "Int")
	SpCellClose()
	SpCellId := c.id, SpCellCol := scCol
	;(Kind, School, TC: a dropdown of what it can be - its list down at once; picked with the mouse it's kept)
	if (scCol = "kind" || scCol = "school" || scCol = "tc")
		return SpCellPick(c, scCol, scX, scY, scW, scH)
	;(an edit of it still waiting in the queue: what it will be)
	scB := SpPendingEdit(c.id), scB := IsObject(scB) ? scB : c
	scNow := scCol = "name" ? scB.name : scCol = "value" ? scB.value : SpPipsEditText(c, scB)
	SpCellShown := scNow
	;(DPI: the window's sizes are scaled by Windows - given in 96-dpi pixels)
	scDpi := A_ScreenDPI / 96
	;(v1's +OwnerDash: v2 takes the owner's hwnd)
	SpCell := Gui("-Caption +ToolWindow +Owner" DashHwnd " +Border"), SpCellHwnd := SpCell.Hwnd
	SpCell.OnEvent("Close", SpCellGuiClose)
	SpCell.OnEvent("Escape", SpCellGuiEscape)
	SpCell.MarginX := 0, SpCell.MarginY := 0
	;(v1: Gui, SpCell:Color, 111317, 111317 - the window's, and behind the Edit: Background111317)
	SpCell.BackColor := "111317"
	SpCell.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	SpCell.Add("Edit", "x0 y0 w" Max(60, Round(scW / scDpi)) " h" Max(20, Round(scH / scDpi) + 4) " -E0x200 Background111317 vSpCellText" (scCol = "name" ? " Limit40" : scCol = "value" ? " Number Limit5" : " Limit2"), scNow)
	ogcButton := SpCell.Add("Button", "x0 y0 w0 h0 Hidden Default")
	ogcButton.OnEvent("Click", SpCellOk.Bind("Normal"))
	SpCell.Show("x" scX " y" scY - 2 " AutoSize" (SpCellHidden ? " Hide" : ""))
	SpSendMsg(0xB1, 0, -1, "Edit1", "ahk_id " SpCellHwnd)      ; EM_SETSEL: all of it, to type over
	;(clicked away: kept - looked at every 150 ms)
	SetTimer(SpCellWatch,150)
	return true
	}

;v1's SendMessage: ErrorLevel the answer, or FAIL when it couldn't be sent - the window not there (a hidden one too:
;DetectHiddenWindows off) or no answer in time; v2 throws there
SpSendMsg(msg, wParam, lParam, ctl, win)
	{
	global ErrorLevel ; (v1 globals it sets)
	try
		ErrorLevel := (ctl = "") ? SendMessage(msg, wParam, lParam, , win) : SendMessage(msg, wParam, lParam, ctl, win)
	catch
		ErrorLevel := "FAIL"
	return ErrorLevel
	}

;The dropdown over a Kind, School or TC cell (SpCellOpen): what it is now picked, the list down; SpCellChoices: the
;values by place in it
SpCellPick(c, col, scX, scY, scW, scH)
	{
	global SpCellChoices, SpCellShown, SpCell, SpCellHwnd, SpCellDropped ; (v1 globals it sets)
	items := "", SpCellChoices := [], now := 0
	if (col = "kind")
		{
		for i, k in IsObject(SpKinds) ? SpKinds : SpKindList()
			{
			items .= (items = "" ? "" : "|") StrReplace(k.label, "|", "/"), SpCellChoices.Push(k.kind)
			if (k.kind = c.type)
				now := i
			}
		}
	else if (col = "school")
		{
		cur := SpSchoolText(c)
		for i, s in SpSchools()
			{
			items .= (items = "" ? "" : "|") Format("{:T}", s), SpCellChoices.Push(s)
			if (s = cur)
				now := i
			}
		}
	else
		{
		items := "yes|no", SpCellChoices := [1, 0], now := SpFlag(c, "tc") ? 1 : 2
		}
	SpCellShown := now
	scDpi := A_ScreenDPI / 96
	;(v1's +OwnerDash: v2 takes the owner's hwnd)
	SpCell := Gui("-Caption +ToolWindow +Owner" DashHwnd " +Border"), SpCellHwnd := SpCell.Hwnd
	SpCell.OnEvent("Close", SpCellGuiClose)
	SpCell.OnEvent("Escape", SpCellGuiEscape)
	SpCell.MarginX := 0, SpCell.MarginY := 0
	;(v1: Gui, SpCell:Color, 111317, 111317 - the window's, and behind the DropDownList: Background111317)
	SpCell.BackColor := "111317"
	SpCell.SetFont("s9 w400 c000000", "Segoe UI")
	;(every kind shown at once - 29 since 2026-10-26, every spell type of the game's)
	scDdl := SpCell.Add("DropDownList", "x0 y0 w" Max(90, Round(scW / scDpi)) " R" Min(30, SpCellChoices.Length) " AltSubmit Background111317 vSpCellText", StrSplit(items, "|"))
	if (now)
		scDdl.Choose(now)
	SpCell.Show("x" scX " y" scY - 2 " AutoSize" (SpCellHidden ? " Hide" : ""))
	scCb := scDdl.Hwnd
	;(the list as wide as its longest - a Kind's label is longer than the column)
	SpSendMsg(0x160, Round(260 * scDpi), 0, "", "ahk_id " scCb)      ; CB_SETDROPPEDWIDTH
	SpCellDropped := 0
	if (!SpCellHidden)
		{
		SpSendMsg(0x14F, 1, 0, "", "ahk_id " scCb)                      ; CB_SHOWDROPDOWN
		SpCellDropped := 1
		}
	SetTimer(SpCellWatch,150)
	return true
	}

;A dropdown cell's value picked now ("" none picked)
SpCellPicked()
	{
	;(v1: GuiControlGet of the AltSubmit list - its position, 0 none)
	pos := SpCell["SpCellText"].Value
	return (pos >= 1 && IsObject(SpCellChoices) && pos <= SpCellChoices.Length) ? SpCellChoices[pos] : ""
	}

;A dropdown cell kept: queued as the Change kind button's, or as a school or treasure card set (applied out of battle),
;and shown in the list at once. Left as it was: nothing
SpCellPickCommit()
	{
	pos := SpCell["SpCellText"].Value
	v := SpCellPicked(), col := SpCellCol, id := SpCellId, was := SpCellShown
	SpCellClose()
	if (v = "" || pos = was)
		return
	c := SpL("LearnCardOf", id)
	if (!IsObject(c))
		return SpNote("That spell isn't in the list any more")
	if (col = "kind")
		SpQueue("kind", v, [id]), show := SpKindLabel(v), n := 2
	else if (col = "school")
		SpQueue("school", v, [id]), show := v, n := 3
	else
		SpQueue("tc", v, [id]), show := v ? "yes" : "", n := 9
	lv := SpListSelect()
	Loop lv.GetCount()
		{
		rowId := lv.GetText(A_Index, 12)
		if (rowId = id)
			{
			lv.Modify(A_Index, "Col" n, show " *")
			break
			}
		}
	SpListBack(lv)
	}

;Moving on from the cell, as in a spreadsheet: what's typed or picked kept, then the cell beside it - Tab right (Name,
;Kind, School, Pips, Value, TC; after TC the next row's Name), Shift+Tab left, Enter down, Shift+Enter up; past the first or
;last row: just kept. A guessed pips is made read only if you typed in its cell - passing through doesn't
SpCellMove(dRow, dCol)
	{
	if (!SpCellHwnd)
		return
	id := SpCellId, col := SpCellCol
	if (col = "kind" || col = "school" || col = "tc")
		SpCellPickCommit()
	else
		{
		SpSendMsg(0xB8, 0, 0, "Edit1", "ahk_id " SpCellHwnd)      ; EM_GETMODIFY: typed in
		typedIn := ErrorLevel != "FAIL" && ErrorLevel
		SpCellCommit(typedIn)
		}
	lv := SpListSelect()
	row := 0
	Loop lv.GetCount()
		{
		rowId := lv.GetText(A_Index, 12)
		if (rowId = id)
			{
			row := A_Index
			break
			}
		}
	n := lv.GetCount()
	SpListBack(lv)
	if (!row)
		return
	cols := [0, 1, 2, 3, 4, 8], at := col = "name" ? 1 : col = "kind" ? 2 : col = "school" ? 3 : col = "pips" ? 4 : col = "value" ? 5 : 6
	at += dCol, row += dRow
	if (at > cols.Length)
		at := 1, row += 1
	else if (at < 1)
		at := cols.Length, row -= 1
	if (row >= 1 && row <= n)
		SpCellOpen(row, cols[at])
	}

;What's typed in the cell kept - checked as the Edit window's Save checks it, then queued (applied out of battle),
;and shown in the list at once. byEnter: Enter pressed - guessed pips left as they were are made read (you said so);
;clicked away from a cell left as it was: nothing
SpCellCommit(byEnter := false)
	{
	if (!SpCellHwnd)
		return
	if (SpCellCol = "kind" || SpCellCol = "school" || SpCellCol = "tc")
		return SpCellPickCommit()
	;(v1: Gui, SpCell:Submit, NoHide - SpCellText set)
	V1GuiSubmit(SpCell, false)
	typed := Trim(SpCellText), col := SpCellCol
	SpCellClose()
	if (!byEnter && typed == Trim(SpCellShown))
		return
	c := SpL("LearnCardOf", SpCellId)
	if (!IsObject(c))
		return SpNote("That spell isn't in the list any more")
	;(the other two from an edit of it still waiting in the queue - else the catalog's)
	pend := SpPendingEdit(SpCellId), b := IsObject(pend) ? pend : c
	name := b.name, value := b.value, pips := b.pips
	if (col = "name")
		name := Trim(RegExReplace(typed, "[^\x20-\x7E]|\|", ""))
	else if (col = "value")
		{
		if (typed != "" && !RegExMatch(typed, "^\d{1,5}$"))
			return SpNote("The number: digits only (or blank: not known)")
		value := typed = "" ? "" : typed + 0
		}
	else
		{
		;(X: an X-pip spell - all your pips)
		if (typed != "" && !RegExMatch(typed, "^[xX]$") && !(RegExMatch(typed, "^\d{1,2}$") && typed <= 14))
			return SpNote("Pips: 0 to 14, or X for an X-pip spell (or blank: not known)")
		if (typed = "" && RegExMatch(c.slot, "\\hit\d$"))
			return SpNote("It's used as " c.slot ": a hit there needs its pips")
		pips := typed = "" ? "" : RegExMatch(typed, "^[xX]$") ? "x" : typed + 0
		}
	;(the columns typed in - this one and a waiting edit's; "" a waiting Edit window's: all three. Only those are changed
	;when the bot applies it, and guessed pips stay guessed unless Pips is one - the learner still corrects them from the
	;card's pip digit)
	cols := !IsObject(pend) ? col : pend.cols = "" ? "" : InStr(pend.cols, col) ? pend.cols : pend.cols " " col
	guessOpen := c.guess && (!IsObject(pend) || (pend.cols != "" && !InStr(pend.cols, "pips")))
	;(the Pips cell against what it showed - an X-pip spell's are 0 in the catalog, shown X: Enter on it untouched queued
	;an edit, as the Edit window's Save did)
	bPips := SpPipsEditText(c, b), bPips := (bPips = "x" || bPips = "X") ? "x" : bPips
	if (name == b.name && value = b.value && (col = "pips" ? pips = bPips : pips = b.pips) && !(col = "pips" && pips != "" && guessOpen)
		&& !(col = "pips" && (pips = "x") != SpFlag(c, "xpip")))
		return
	SpQueue("edit", V1Obj({name: name, value: value, pips: pips, cols: cols}), [SpCellId])
	;(the list shows it now - the bot's loop applies it out of battle and fills the list again)
	lv := SpListSelect()
	Loop lv.GetCount()
		{
		rowId := lv.GetText(A_Index, 12)
		if (rowId = SpCellId)
			{
			lv.Modify(A_Index, "Col" (col = "name" ? 1 : col = "value" ? 5 : 4), (col = "name" ? name : col = "value" ? value : pips) " *")
			break
			}
		}
	SpListBack(lv)
	}

;The cell's box gone (nothing kept)
SpCellClose()
	{
	global SpCellHwnd ; (v1 globals it sets)
	SetTimer(SpCellWatch,0)
	if (SpCellHwnd)
		Try SpCell.Destroy()
	SpCellHwnd := 0
	}

;---- The buttons' other work ----

;The Forget question; Yes queues it
SpForgetAsk()
	{
	ids := SpSelectedIds()
	if (!ids.Length)
		return SpNote("Pick one or more spells in the list first")
	n := ids.Length
	if (SpAsk("Forget " (n = 1 ? SpName(SpL("LearnCardOf", ids[1])) : n " spells") "? Their pictures go to backups\learned forgotten. A real card is learned again the next time it is in hand - to keep one out of use, change its kind to 'Not used' instead.") != "Yes")
		return
	SpQueue("forget", "", ids)
	}

;A Yes/No question on top of everything ("Yes" / "No"; SpAskAnswer: tests)
SpAsk(text)
	{
	if (SpAskAnswer != "")
		return SpAskAnswer
	msgResult := MsgBox(text, "Learned spells", 262436)
	if (msgResult = "Yes")
		return "Yes"
	return "No"
	}

;Never discard: on for all the selected if any of them hasn't it, else off for all
SpHoldToggle()
	{
	ids := SpSelectedIds()
	if (!ids.Length)
		return SpNote("Pick one or more spells in the list first")
	holdOn := 0
	for i, id in ids
		if (!SpFlag(SpL("LearnCardOf", id), "hold"))
			holdOn := 1
	SpQueue("hold", holdOn, ids)
	}

;The Change kind menu's pick (its position in SpKinds) for the spells selected
SpKindPick(pos)
	{
	ids := SpSelectedIds()
	if (!ids.Length || !IsObject(SpKinds) || !SpKinds.Has(pos))
		return
	SpQueue("kind", SpKinds[pos].kind, ids)
	}

;The picture of the spell selected first, or its folder (learned\ when none is selected)
SpOpenPic(folder)
	{
	ids := SpSelectedIds()
	c := ids.Length ? SpL("LearnCardOf", ids[1]) : ""
	pic := IsObject(c) ? SpPicPath(c) : ""
	if (folder && pic != "")
		Run("explorer.exe /select,`"" pic "`"")
	else if (folder)
		{
		;(v1's FileCreateDir: a failure only set ErrorLevel)
		V1Do(DirCreate, A_WorkingDir "\learned")
		Run("explorer.exe `"" A_WorkingDir "\learned`"")
		}
	else if (pic != "")
		Run("`"" pic "`"")
	else
		SpNote(ids.Length ? "That spell's picture isn't there any more" : "Pick a spell in the list first")
	}

;The Moved away menu: the folders in backups\ with what was taken out of use - non-cards, forgotten spells, stray
;copies, the hits moved to make room (newest first) - and backups\ itself. Shown when there's anything (show false:
;only made - tests); how many folders it lists
SpMovedMenu(show := true)
	{
	static made := 0
	global SpMovedPaths, SpMovedMenuVar ; (v1 globals it sets)
	SpMovedPaths := []
	;(v1's menu SpMovedMenu - SpMovedMenuVar here: v2 has the function SpMovedMenu by that name)
	if (made)
		SpMovedMenuVar.Delete()
	back := A_WorkingDir "\backups"
	items := []
	for i, f in [["learned junk", "Non-cards taken out of the list"], ["learned forgotten", "Spells you forgot"], ["learned strays", "Stray copies of learned pictures"]]
		if (InStr(FileExist(back "\" f[1]), "D"))
			items.Push([f[2] " (backups\" f[1] ")", back "\" f[1]])
	snaps := ""
	Loop Files, back "\hits *", "D"
		snaps .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"
	snaps := Sort(snaps, "R")
	Loop Parse, snaps, "`n"
		{
		if (A_LoopField = "" || A_Index > 10)
			continue
		f := SubStr(A_LoopField, (InStr(A_LoopField, "`t") + 1)<1 ? (InStr(A_LoopField, "`t") + 1)-1 : (InStr(A_LoopField, "`t") + 1))
		items.Push(["Hits moved to make room: " f, back "\" f])
		}
	if (InStr(FileExist(back), "D"))
		items.Push(["The backups folder", back])
	if (!items.Length)
		{
		SpNote("Nothing has been moved away yet")
		return 0
		}
	;(v1: the menu made by its first Add)
	if (!made)
		SpMovedMenuVar := Menu()
	for i, it in items
		{
		SpMovedMenuVar.Add(StrReplace(it[1], "&", "and"), SpMovedChosen)
		SpMovedPaths.Push(it[2])
		}
	made := 1
	if (show)
		SpMovedMenuVar.Show()
	return items.Length
	}

;---- The tab's buttons (labels run in the global scope: Sp-named variables only) ----

SpListEvent:
SpListEvent()
	return

;(the cell's box: Enter keeps what's typed, Esc doesn't, clicking away keeps it)
SpCellOk:
SpCellOk()
	return

SpCellGuiEscape:
SpCellGuiEscape()
return
SpCellGuiClose:
SpCellGuiClose()
	return

SpCellWatch:
SpCellWatch()
	return

;(after a moment: a select-all doesn't load the picture once per row)
SpPreviewTick:
SpPreviewTick()
	return

SpKindClick:
SpKindClick()
	return

SpKindChosen:
SpKindChosen()
	return

SpEditClick:
SpEditClick()
	return

SpEdSave:
SpEdSave()
	return

SpEdGuiClose:
SpEdGuiClose()
return
SpEdGuiEscape:
SpEdGuiEscape()
	return

SpForgetClick:
SpForgetClick()
	return

SpHoldClick:
SpHoldClick()
	return

SpPicClick:
SpPicClick()
	return

SpFolderClick:
SpFolderClick()
	return

SpMovedClick:
SpMovedClick()
	return

SpMovedChosen:
SpMovedChosen()
	return

;(learned\cards.txt read again - by the bot's loop, out of battle - and the list filled now)
SpRefreshClick:
SpRefreshClick()
	return

;The cell's keys while its box is in front: Tab / Shift+Tab right and left, Enter / Shift+Enter down and up (SpCellMove)
#HotIf SpCellHwnd && WinActive("ahk_id " SpCellHwnd)
Tab::HK1_Tab()
	return
+Tab::HK2_Tab()
	return
Enter::
NumpadEnter::HK4_NumpadEnter()
	return
+Enter::
+NumpadEnter::HK6_NumpadEnter()
	return
#HotIf

;###############  V1toV2 FUNCS  ###############
;(the Spells tab's buttons and list - g-labels in v1: Dashboard.ahk binds them, Fn.Bind("Normal"); the list:
;.OnEvent("ItemSelect", SpListEvent.Bind("I")) and .OnEvent("DoubleClick", SpListEvent.Bind("DoubleClick")); Info: v1's
;A_EventInfo. A callback below that gets to ErrorLevel only through a function called by its name (SpL, SpCallLearn)
;or a V1Compat helper (V1Do) has its own V1Thread: the port's tool doesn't follow those)
SpListEvent(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	local v1Own := V1Thread()  ; (v1: the list's thread had its own ErrorLevel - SpCellEdit's SendMessage, SpL set it)
	;(v1: "I" with ErrorLevel holding S or s - InStr isn't case-sensitive: picked or unpicked - v2's ItemSelect, both)
	if (A_GuiEvent = "I" || A_GuiEvent = "ItemSelect")
		SetTimer(SpPreviewTick,-60)
	else if (A_GuiEvent = "DoubleClick" && Info)
		SpCellEdit(Info)
	return
}
;##############################################
SpCellOk(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	SpCellMove(1, 0)
	return
}
;##############################################
SpCellGuiEscape(*) { ; V1toV2: Lbl->Func
global
SpCellGuiClose()
}
;##############################################
SpCellGuiClose(*) { ; V1toV2: Lbl->Func
	global
	SpCellClose()
	return
}
;##############################################
SpCellWatch() { ; V1toV2: Lbl->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(a dropdown cell: its list was down and is up now with another value picked - a click on it: kept, as Enter would)
	if (SpCellHwnd && (SpCellCol = "kind" || SpCellCol = "school" || SpCellCol = "tc"))
		{
		scWCb := SpCell["SpCellText"].Hwnd
		SpSendMsg(0x157, 0, 0, "", "ahk_id " scWCb)      ; CB_GETDROPPEDSTATE
		scWDown := ErrorLevel != "FAIL" && ErrorLevel
		scWPos := SpCell["SpCellText"].Value
		if (SpCellDropped && !scWDown && scWPos != SpCellShown)
			{
			SpCellPickCommit()
			return
			}
		SpCellDropped := scWDown
		}
	;(clicked away in the bot's own windows - the dashboard: kept. Another program in front - the bot bringing Wizard101
	;up for a round, or you in another window: the box waits, nothing half-typed kept)
	if (SpCellHwnd && !WinActive("ahk_id " SpCellHwnd))
		{
		;(v1's WinGet, PID, A: blank with no window in front - v2 throws)
		scActPid := V1Try(WinGetPID, "A")
		if (scActPid = DllCall("GetCurrentProcessId"))
			SpCellCommit()
		}
	return
}
;##############################################
SpPreviewTick() { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a timer's thread had its own ErrorLevel - the learner's functions, called by name)
	SpPreviewShow()
	return
}
;##############################################
SpKindClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	if (!SpSelectedIds().Length)
		SpNote("Pick one or more spells in the list first")
	else
		SpKindMenu.Show()
	return
}
;##############################################
SpKindChosen(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a menu item's thread had its own ErrorLevel - the learner's functions, called by name)
	SpKindPick(A_ThisMenuItemPos)
	return
}
;##############################################
SpEditClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - the learner's functions, called by name)
	SpEditShow()
	return
}
;##############################################
SpEdSave(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - the learner's functions, called by name)
	SpEdSaveNow()
	return
}
;##############################################
SpEdGuiClose(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
global
SpEdGuiEscape()
}
;##############################################
SpEdGuiEscape(*) { ; V1toV2: Lbl->Func
	global
	Try SpEd.Destroy()
	SpEdHwnd := 0
	return
}
;##############################################
SpForgetClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - the learner's functions, called by name)
	SpForgetAsk()
	return
}
;##############################################
SpHoldClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - the learner's functions, called by name)
	SpHoldToggle()
	return
}
;##############################################
SpPicClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - the learner's functions, called by name)
	SpOpenPic(false)
	return
}
;##############################################
SpFolderClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - V1Do, the learner's functions by name)
	SpOpenPic(true)
	return
}
;##############################################
SpMovedClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	SpMovedMenu()
	return
}
;##############################################
SpMovedChosen(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
	global
	if (IsObject(SpMovedPaths) && SpMovedPaths.Has(A_ThisMenuItemPos))
		Run("explorer.exe `"" SpMovedPaths[A_ThisMenuItemPos] "`"")
	return
}
;##############################################
SpRefreshClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - the learner's functions, called by name)
	SpQueue("reload", "", [])
	SpListFill()
	return
}
;##############################################
HK1_Tab() { ; V1toV2: HK->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	SpCellMove(0, 1)
	return
}
;##############################################
HK2_Tab() { ; V1toV2: HK->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	SpCellMove(0, -1)
	return
}
;##############################################
HK4_NumpadEnter() { ; V1toV2: HK->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	SpCellMove(1, 0)
	return
}
;##############################################
HK6_NumpadEnter() { ; V1toV2: HK->Func
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	SpCellMove(-1, 0)
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
SpellsBlank()
	{
	global SpList := "", SpHelp := "", SpStatus := "", SpKindBtn := "", SpEditBtn := "", SpForgetBtn := "", SpHoldBtn := "", SpPicBtn := ""
	global SpFolderBtn := "", SpMovedBtn := "", SpRefreshBtn := "", SpPreview := "", SpPreviewTxt := "", SpPending := "", SpDirty := "", SpKinds := ""
	global SpMovedPaths := "", SpNoteText := "", SpEdHwnd := "", SpEdId := "", SpEdName := "", SpEdValue := "", SpEdPips := "", SpEdNote := ""
	global SpAskAnswer := "", SpCellHwnd := "", SpCellId := "", SpCellCol := "", SpCellText := "", SpCellShown := "", SpCellChoices := ""
	global SpCellDropped := "", SpCellHidden := ""
	}
