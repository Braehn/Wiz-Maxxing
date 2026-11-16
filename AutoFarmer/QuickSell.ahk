; QuickSell.ahk - the backpack quick sold for gold when it's full (asked 2026-10-25: "when your backpack is full a circular
; alert icon with prospector zeke shows up on the right hand side of the screen ... we should have the bot look for that
; after a battle and if its there i'd like to to quick sell our entire inventory" - "of course this should be a setting
; to be turned on and off because dungeons would cause good gear to be sold"). AutoHotkey v2 (ported from v1.1), functions
; only; #Included by Autofarmer.ahk. Needs the vision helper and the game's memory (vision\bagmem.py - /bag and /gui,
; READ-ONLY): without them it does nothing (no picture is ever trusted for this - Zeke's portrait also means "the gold bag
; is nearly full").
;
; Settings > THE BACKPACK: quicksell (off by default), quicksellpets (pets too - on), quicksellafterdungeon (off). Hidden
; (PlayerStats.txt): quicksellfree:N - sell with N slots or fewer left (0); quicksell:2 - a REHEARSAL: everything up to the
; confirmation window, read, logged and closed - nothing sold (after battles at most once an hour). Tray menu: "Quick sell
; the backpack now" and "Quick sell rehearsal (stops at the confirmation)".
;
; When: after a battle the bot played (the main loop's spellbook block - QsBattleEnd, QsTick), three looks at the game's
; memory (0, 3 and 8 s after it): the backpack's count against its size (calibrated by the game's own "N/M"), and Zeke's
; icon in the HUD's right-hand column. Full - or Zeke's icon with the gold bag not near full - is a look: B, the game's
; own N/M read; full by it: the sale. Never in a dungeon run, a dungeon being recorded, a zone the walker entered through a
; sigil or a zone that one leads on to (QsZoneChange); after a dungeon the next full backpack is held (you're told) until
; you've sorted it, unless quicksellafterdungeon - with the gear pass on (Gear.ahk, gearswap) its gear groups are sold once
; compared, only the Deck and Pet groups held (QsLook). A dungeon you walked into yourself isn't known as one.
;
; The sale - every click target from the game's memory (name and ancestors, shown, its rect, its size against the .gui
; file's, its label), on an allow-list, turned into pixels: B (the backpack page), Quick Sell, each gear group (Hat,
; Robe, Shoes, Weapon, Athame, Amulet, Ring, Deck) and the Pet group (quicksellpets) with ALL - never the All group (it
; takes housing and jewels too) - and No to "Would you like to include Crowns Items in the selected items?" (the one
; Crown box it may ever click, only No, only when its game key in the log, its caption, its button's label and an OCR
; of "No" agree), SELL, the confirmation's numbers read (Crown rows, furniture, jewels, reagents, treasure cards 0; no
; pets unless quicksellpets; its total its rows'), SELL, Yes to the pets box only when its count is the confirmation's,
; then the backpack's count falling checked. A group an Equipment Set's item in the backpack is in is left out (the boss
; deck's deck), and every such item is checked to be there after - one gone turns quick sell off. Before each click:
; no key or mouse of yours since the run began, the bot on, Wizard101 in front, no battle, no "Crown" read round it - and
; after the hover, none of yours still and the mouse still on it: the click goes AT the target, never where the mouse is.
; Anything else - a box it doesn't know, a timeout (60 s for the whole run) - backs out window by window (each close
; checked); a Crown box stops it with nothing clicked. A key of yours stops it at once - no more input -, and so does
; your mouse between its clicks: each move and hover, click and B holds your mouse off (Settings.ahk's mouse lock -
; mouselock, "quicksell"), and what it swallowed then isn't you (UserIdle: QsOk, QsClickAt).
; debug.log: "Backpack: ..."; the dashboard counts the sales (Quick sells).

;Declared only (a top-level := never runs in an #Included file - numbers made with X := X ? X : 0)
;A run under way (Party.ahk's ready waits), when the bot's last battle ended and the looks after it, when a sale may be
;tried again, failures in a row, given up (3 in a row: till a restart or the setting toggled), when the last look that
;found it not full was, the last look found it full and not sold (QsStillFull - the mob loop), the setting as last seen,
;the character (its global id, hex - quicksell.ini's section)
global QsBusy, QsBattleEndAt, QsLooks, QsTryAt, QsFails, QsBlocked, QsLookAt, QsStill, QsSetWas, QsGid
;What's been said when ({key: tick}), the no-memory alert sent, windows a battle left open (closed at the next look) and
;the tries and when, the run's start (no input of yours after it), a run from the tray, the steps clicked
global QsSaidAt, QsMemSaid, QsLeftover, QsLeftoverTries, QsLeftoverAt, QsSince, QsManual, QsStep
;The game's log read by the run itself (where to, its first line, what it said since the run began: [{kind, key, msg}]);
;the backpack before the run ({items, gold, pouch, sets: {gid: set item}}), the last /bag read
global QsLogPos, QsLogHead, QsLogEvents, QsBefore, QsLastBag
;Why the last back-out stopped (user, battle, unread, box, click, stuck); a dungeon's deeper zones (entered from one of its
;zones - {zone: 1}) and the zone it was entered from (its way out)
global QsBackKind, QsDgZones, QsDgOut

;---- The settings ----

;quicksell: 0 off, 1 on, 2 the rehearsal (up to the confirmation, nothing sold)
QsMode()
	{
	qm := Stats.Has("quicksell") ? V1Round(Stats["quicksell"]) : 0  ; (v1: Round of a blank or text: 0)
	return (qm = 1 || qm = 2) ? qm : 0
	}

;quicksellpets: pets sold too (on unless 0)
QsPets()
	{
	return !(Stats.Has("quicksellpets") && !Stats["quicksellpets"])
	}

;quicksellafterdungeon: a backpack holding a dungeon's drops sold like any other (off)
QsAfterDungeon()
	{
	return (Stats.Has("quicksellafterdungeon") && Stats["quicksellafterdungeon"]) ? 1 : 0
	}

;quicksellfree: sold with this many slots or fewer left (0: only when the game's own N/M reads full)
QsFree()
	{
	qf := Stats.Has("quicksellfree") ? V1Round(Stats["quicksellfree"]) : 0  ; (v1: Round of a blank or text: 0)
	return qf > 0 ? Min(qf, 30) : 0
	}

QsLog(msg)
	{
	DebugLog("Backpack: " msg)
	}

;Said once in every ms (10 minutes) for its key; true when said now
QsSay(key, msg, every := 600000)
	{
	global QsSaidAt ; (v1 globals it sets)
	if (!IsObject(QsSaidAt))
		QsSaidAt := V1Obj()
	if (QsSaidAt.Has(key) && A_TickCount - QsSaidAt[key] < every)
		return false
	QsSaidAt[key] := A_TickCount
	QsLog(msg)
	return true
	}

;---- What's kept per character (quicksell.ini: [<the character's global id>] uncounted, cap, dungeon, markitems) ----

QsIniPath()
	{
	return A_ScriptDir "\quicksell.ini"
	}

QsIni(key, def := "")
	{
	qSec := QsGid != "" ? QsGid : "pending"
	qv := IniRead(QsIniPath(), qSec, key, "")  ; (v1's %A_Space% default: a blank - v2's A_Space would be a space)
	return (qv = "" || qv = "ERROR") ? def : qv
	}

QsIniSet(key, value)
	{
	qSec := QsGid != "" ? QsGid : "pending"
	if (value = "")
		V1Do(IniDelete, QsIniPath(), qSec, key)  ; (v1: ErrorLevel when it fails - v2 throws)
	else
		V1Do(IniWrite, value, QsIniPath(), qSec, key)
	}

;What the count goes by: the backpack list's items the game's own N/M leaves out (emotes...), its size by that N/M, the
;slots left at which it's sold
QsState()
	{
	return V1Obj({uncounted: V1Add(QsIni("uncounted", 0), 0), cap: V1Add(QsIni("cap", 0), 0), free: QsFree()})  ; (v1: text + 0 - blank)
	}

;A dungeon run started or stopped, a dungeon recorded, a zone entered through a sigil (Dungeons.ahk, Walker.ahk): this
;character's next full backpack is held - a dungeon's drops are the good gear (quicksellafterdungeon off) - until it's been
;sorted (10 items fewer than its most since), quicksellafterdungeon is ticked, or a quick sell is asked for from the tray
QsDungeonMark(zone := "")
	{
	qWas := QsIni("dungeon")
	QsIniSet("dungeon", A_Now)
	QsIniSet("markitems", "")
	;(the mark's kept with quick sell off too - said only with it on)
	if (qWas = "" && QsMode())
		QsLog("a dungeon (" (IsObject(DgRun) ? "the run '" DgRun.name "'" : DgRecording ? "being recorded" : "entered through its sigil" (zone != "" ? ": " zone : "")) ")"
			. (QsAfterDungeon() ? " - its drops sold like any others ('...even with a dungeon's drops in it' is ticked)" : (V1IsFunc("GearMode") && GearMode.Call()) ? " - the next full backpack is held (its drops are the good gear): its gear sold once the gear pass compared it, its decks and pets kept - you're told" : " - the next full backpack is held (its drops are the good gear): you're told, nothing's sold"))
	}

QsMarkClear(why)
	{
	if (QsIni("dungeon") = "")
		return
	QsIniSet("dungeon", ""), QsIniSet("markitems", "")
	QsLog("the dungeon's hold dropped: " why)
	}

;The full backpack held for a dungeon's drops
QsHeld()
	{
	return QsIni("dungeon") != "" && !QsAfterDungeon()
	}

;A /bag read: the character, the game's own N/M when the backpack page shows it (whoever opened it), the dungeon mark's
;count
QsNoteBag(bag)
	{
	global QsLastBag, QsGid ; (v1 globals it sets)
	QsLastBag := bag
	if (bag.gid != "" && bag.gid != QsGid)
		{
		QsGid := bag.gid
		;(a mark made before the character was known: its own now)
		qPend := IniRead(QsIniPath(), "pending", "dungeon", "")  ; (v1's %A_Space% default: a blank)
		if (qPend != "")
			{
			QsIniSet("dungeon", qPend), QsIniSet("markitems", "")
			V1Do(IniDelete, QsIniPath(), "pending")
			}
		}
	if (IsObject(bag.space) && bag.space.m > 0)
		QsCalibrate(bag.items, bag.space.n, bag.space.m)
	if (QsIni("dungeon") = "")
		return
	if (QsAfterDungeon())
		{
		QsMarkClear("'...even with a dungeon's drops in it' is ticked")
		return
		}
	qMost := QsIni("markitems")
	if (bag.items = "")
		return
	;(the bot's own sale - QsBusy: under a dungeon's hold only with the gear pass on, its Deck and Pet groups kept (QsLook) -
	;isn't a sort: the hold stays, the count noted from here)
	if (QsBusy)
		QsIniSet("markitems", bag.items)
	else if (qMost = "" || V1Gt(bag.items, qMost))  ; (v1: quicksell.ini's value compared as text when it isn't a number)
		QsIniSet("markitems", bag.items)
	else if (V1Le(bag.items, V1Sub(qMost, 10)))
		QsMarkClear("the backpack went from " qMost " down to " bag.items " items (sorted)")
	}

;The game's own N/M against the backpack list's count: what the count leaves out (emotes...) and the backpack's size
QsCalibrate(items, n, m)
	{
	if (items = "" || n = "" || m = "" || m <= 0)
		return
	qUnc := items - n
	if (qUnc < 0 || qUnc > 300)
		return
	if (QsIni("uncounted") != qUnc || QsIni("cap") != m)
		{
		QsIniSet("uncounted", qUnc), QsIniSet("cap", m)
		QsLog("the game's own count " n "/" m " - " items " items in the backpack's list, " qUnc " of them not counted (emotes...)")
		}
	}

;---- When it's looked for (Autofarmer.ahk's spellbook block) ----

;A battle the bot played just ended (inbattle was 1)
QsBattleEnd()
	{
	global QsBattleEndAt, QsLooks ; (v1 globals it sets)
	QsBattleEndAt := A_TickCount, QsLooks := 0
	}

;Each pass of the spellbook block (after PotionCheck): a battle's windows left open closed; three looks after the bot's
;battle, 0, 3 and 8 s after it (the loot can come a moment after the spellbook shows). Nothing at all with quicksell off
QsTick()
	{
	static qDue := [0, 3000, 8000]
	global QsBlocked, QsFails, QsTryAt, QsLookAt, QsSetWas, QsStill, QsLeftover, QsLooks ; (v1 globals it sets)
	qMode := QsMode()
	if (qMode != QsSetWas)
		{
		;(switched on: the gave-up and the waits forgotten)
		if (qMode && QsSetWas != "")
			QsBlocked := 0, QsFails := 0, QsTryAt := 0, QsLookAt := 0
		QsSetWas := qMode
		}
	if (!qMode)
		{
		QsStill := 0, QsLeftover := 0
		return
		}
	if (QsBusy)
		return
	if (QsLeftover)
		{
		QsLeftoverTick()
		return
		}
	QsLooks := QsLooks ? QsLooks : 0
	;(a blank time: "A_TickCount - blank < N" would be true)
	if (!QsBattleEndAt || A_TickCount - QsBattleEndAt >= 12000 || QsLooks >= 3)
		return
	if (A_TickCount < QsBattleEndAt + qDue[QsLooks + 1])
		return
	QsLooks += 1
	QsLook("look " QsLooks " of 3 after the battle")
	}

;Windows a battle (or a run that stopped) left open: closed - at most every 3 s, 3 tries
QsLeftoverTick()
	{
	global QsLeftoverAt, QsLeftoverTries, QsBusy, QsSince, QsManual, QsLeftover ; (v1 globals it sets)
	QsLeftoverAt := QsLeftoverAt ? QsLeftoverAt : 0, QsLeftoverTries := QsLeftoverTries ? QsLeftoverTries : 0
	if (A_TickCount - QsLeftoverAt < 3000)
		return
	QsLeftoverAt := A_TickCount
	if (!QsMayRun(&qWhy))
		return
	QsLeftoverTries += 1
	QsBusy := 1, QsSince := A_TickCount, QsManual := 0
	qDone := QsBackOut("a battle cut the quick sell short")
	QsBusy := 0
	if (qDone || QsLeftoverTries >= 3)
		QsLeftover := 0, QsLeftoverTries := 0
	}

;The last after-battle look found the backpack full and it wasn't sold (held, failed, waiting): the mob loop stops. Not in
;a rehearsal (quicksell:2 never sells - farming goes on as with quick sell off)
QsStillFull()
	{
	return QsMode() = 1 && QsStill
	}

;A look: the backpack from the game's memory, and what to do about it
QsLook(why)
	{
	global QsMemSaid, QsStill, QsTryAt, QsLookAt ; (v1 globals it sets)
	bag := NavBag()
	if (!IsObject(bag))
		{
		QsSay("nomem", "no look (" why ") - " NavBagWhy " (quick sell goes by the game's memory only)")
		if (!QsMemSaid && RegExMatch(NavBagWhy, "i)isn't running|navmem:0|dual mode"))
			{
			QsMemSaid := 1
			AlertSend("inventory", "quick sell can't look", "Quick sell needs the game's memory (the vision helper) - it's off (" NavBagWhy "). Nothing is sold.")
			}
		return
		}
	QsNoteBag(bag)
	d := QsDecide(bag, QsState())
	if (d.act = "none")
		{
		QsStill := 0
		return
		}
	if (d.act = "gold")
		{
		QsStill := 0
		if (QsSay("gold", d.why " - not looked at"))
			AlertSend("gold", "gold bag nearly full", "Prospector Zeke's alert: the gold bag is " Round(100 * bag.gold / bag.goldMax) "% full (" bag.gold " of " bag.goldMax ") - gold over it is lost.")
		return
		}
	;(full by the count - or Zeke's alert: a look)
	qDg := QsDungeonNow()
	if (qDg != "")
		{
		if (d.full)
			QsStill := 1
		if (QsSay("dungeon", d.why " in " qDg " - not sold (a dungeon's drops are the good gear)"))
			AlertSend("inventory", "backpack full", "The backpack is full in a dungeon - not sold (good gear). Drops go to the bank until it's full.")
		return
		}
	;(Settings: gearswap on - the gear pass first (Gear.ahk GearSellOk): a backpack piece better than what's worn, or one it
	;couldn't judge, holds the sale (a rehearsal equips nothing: you're told to put it on); every gear piece judged and none
	;better - it looked through the gear: sold. Under a dungeon's hold the pass never compares decks or pets
	;(vision\gearrank.py): sold without the Deck and Pet groups (bag.dgKeep - QsCategories), the hold kept - it ends as
	;without the pass (10 items gone - the bot's own sales not counted, QsNoteBag -, the tray, the tick box) - and said
	;after the sale (QsAfter). Off: as before)
	if (V1IsFunc("GearMode") && GearMode.Call() && V1IsFunc("GearSellOk"))
		{
		qGear := GearSellOk.Call(d.why)
		if (qGear != "")
			{
			if (d.full)
				QsStill := 1
			QsSay("gear", d.why " - not sold: " qGear)
			return
			}
		if (QsHeld())
			bag.dgKeep := "a dungeon's drops - the gear pass compares gear only, never decks or pets"
		}
	if (QsHeld() && bag.dgKeep = "")
		{
		if (d.full)
			QsStill := 1
		if (QsSay("held", d.why " - held: it holds a dungeon's drops (not quick sold - look through it, sell it yourself, or tick '...even with a dungeon's drops in it')"))
			AlertSend("inventory", "backpack full", "The backpack is full and holds a dungeon's drops - not quick sold. Look through it, then sell it yourself, or tick '...even with a dungeon's drops in it' (Settings: THE BACKPACK).")
		return
		}
	if (QsBlocked)
		{
		QsStill := d.full ? 1 : QsStill
		QsSay("blocked", d.why " - quick sell gave up after 3 failures in a row (switch it off and on, or restart the bot)")
		return
		}
	QsTryAt := QsTryAt ? QsTryAt : 0, QsLookAt := QsLookAt ? QsLookAt : 0
	if (QsTryAt && A_TickCount < QsTryAt)
		{
		QsStill := d.full ? 1 : QsStill
		QsSay("wait", d.why " - not tried again for " Ceil((QsTryAt - A_TickCount) / 60000) " more minutes")
		return
		}
	;(Zeke's alert with the count not full: one look in 10 minutes - it calibrates the count)
	if (!d.full && QsLookAt && A_TickCount - QsLookAt < 600000)
		return
	if (!QsMayRun(&qWhy))
		{
		QsSay("skip " qWhy, d.why " - not now: " qWhy)
		return
		}
	QsRun(d, bag, false, QsMode() = 2)
	}

;What to do about a /bag reading (pure): {act: "look" (the backpack page opened and its own N/M read - the count says full,
;or Zeke's alert with the gold bag not near full), "gold" (Zeke's alert with the gold bag 95% full or more: the gold bag's
;alert - no look), "none"; full (by the count), zeke, gold, counted, cap, why}. s: QsState's {uncounted, cap, free}
QsDecide(bag, s)
	{
	qUnc := V1Gt(s.uncounted, 0) ? s.uncounted : 0  ; (v1: a blank - text in quicksell.ini - compared as text)
	qCap := V1Gt(s.cap, 0) ? s.cap : (V1Gt(bag.allowed, 0) ? bag.allowed : 0)
	qFree := V1Gt(s.free, 0) ? s.free : 0
	qCounted := (bag.items != "" && bag.items >= 0) ? bag.items - qUnc : ""
	qFull := (qCounted != "" && qCap > 0 && qCounted >= qCap - qFree) ? 1 : 0
	qZeke := QsZekeUp(bag.tips)
	qGold := (V1Gt(bag.goldMax, 0) && bag.gold != "" && bag.gold >= 0.95 * bag.goldMax) ? 1 : 0
	qNow := (qCounted = "" ? "?" : qCounted) "/" (qCap ? qCap : "?")
	qOut := V1Obj({act: "none", full: qFull, zeke: qZeke, gold: qGold, counted: qCounted, cap: qCap, why: "the backpack is " qNow " by the count"})
	if (qFull)
		qOut.act := "look", qOut.why := "the count says full (" qNow (qUnc ? ", " qUnc " not counted" : "") ")" (qZeke ? " and Zeke's alert is up" : "")
	else if (qZeke && !qGold)
		qOut.act := "look", qOut.why := "Prospector Zeke's alert is up (the count says " qNow ")"
	else if (qZeke)
		qOut.act := "gold", qOut.why := "Zeke's alert is up and the gold bag is " Round(100 * bag.gold / bag.goldMax) "% full (" bag.gold "/" bag.goldMax ") - the gold bag's alert, the backpack is " qNow
	return qOut
	}

;Prospector Zeke's portrait on a shown icon of the HUD's right-hand column (the backpack full - or the gold bag nearly)
QsZekeUp(tips)
	{
	if (!IsObject(tips))
		return 0
	for qi, qt in tips
		if (qt.shown && (InStr(qt.image, "Portrait_Human_Zeke") || InStr(qt.button, "Portrait_Human_Zeke")))
			return 1
	return 0
	}

;In a dungeon: a dungeon run, one being recorded, a zone the walker entered through a sigil or one entered from such a zone
;(its deeper zones) - why, else "". A dungeon you went into yourself isn't known as one. A dungeon run between two runs -
;back at its start spot outside (Dungeons.ahk's DgRun.between, set when a run that ends where it starts is done, gone at
;its first X or another zone) - isn't in the dungeon: a full backpack may be sold there (v1.0.0 - it used to read "in the
;dungeon run" for the whole of it, so with "Run it 0 times" a full backpack was never sold); the zone's own checks below
;still hold, and so does the dungeon's hold (QsHeld)
QsDungeonNow()
	{
	if (DgRecording)
		return "a dungeon being recorded"
	if (IsObject(DgRun) && !DgRun.between)
		return "the dungeon run '" DgRun.name "'"
	qZone := WalkZone()
	if (qZone != "" && IsObject(WkSigilZones) && WkSigilZones.Has(qZone))
		return "a dungeon (" qZone " - entered through its sigil)"
	if (qZone != "" && IsObject(QsDgZones) && QsDgZones.Has(qZone))
		return "a dungeon (" qZone " - one of its deeper zones)"
	return ""
	}

;A zone a dungeon's own zones lead to (the walker's WalkZone, at each zone change): one entered from a dungeon's zone is
;its next zone - not the way back out (the zone it was entered from, the sigil's) - and is a dungeon too (its drops held).
;At most 4 deeper zones (a teleport out of a dungeon isn't seen: the chain then ends there)
QsZoneChange(from, to)
	{
	global QsDgZones, QsDgOut ; (v1 globals it sets)
	if (!IsObject(QsDgZones))
		QsDgZones := V1Obj()
	qFromDg := QsDgZone(from), qToDg := QsDgZone(to)
	if (qToDg)
		{
		if (!qFromDg)
			QsDgOut := from
		return
		}
	if (!qFromDg || to = "")
		return
	qDeep := 0
	for qz in QsDgZones
		qDeep += 1
	if (to = QsDgOut || to = WkSigilFromZone || qDeep >= 4)
		{
		if (qDeep && QsMode())
			QsLog("out of the dungeon (" from " -> " to ")" (to = QsDgOut || to = WkSigilFromZone ? "" : " - taken as out after 4 deeper zones"))
		QsDgZones := V1Obj(), QsDgOut := ""
		return
		}
	QsDgZones[to] := 1
	;(kept with quick sell off too - said only with it on)
	if (QsMode())
		QsLog("a dungeon's deeper zone: " to " (from " from ") - never quick sold in")
	QsDungeonMark(to)
	}

QsDgZone(zone)
	{
	return zone != "" && ((IsObject(WkSigilZones) && WkSigilZones.Has(zone)) || (IsObject(QsDgZones) && QsDgZones.Has(zone)))
	}

;May a run start now: why not ("" it may). manual: asked for from the tray (the bot may be off, you've just used the mouse)
QsMayRun(&why, manual := false)
	{
	why := ""
	qSecs := Stats.Has("handsoff") ? Stats["handsoff"] : 3
	if (!BotOn && !manual)
		why := "the bot is off"
	else if (afkVar)
		why := "holding (afk)"
	else if (dualmode)
		why := "dual mode"
	else if (LearnAll)
		why := "Learn every card is on"
	else if (PotionRecording)
		why := "potion buying being recorded"
	else if (PotionResting)
		why := "resting for health"
	else if (WkLoading)
		why := "a loading screen"
	else if (V1IsFunc("BattleLogInBattle") && BattleLogInBattle.Call())
		why := "a battle"
	else if (WkNoteKind != "")
		why := "a `"needs you`" notice is up (" WkNoteKind ")"
	else if (!manual && V1Lt(UserIdle(), V1Mul(V1Max(3, qSecs), 1000)))  ; (v1: a handsoff that isn't a number - Max blank, compared as text)
		why := "you're at the keyboard or mouse"
	else if (!GameActive() && !(V1IsFunc("GameToFront") && GameToFront.Call("quick sell", !manual)))
		why := "Wizard101 isn't the window in front"
	return why = ""
	}

;---- The run ----

;The quick sell (a look, the tray): d - QsDecide's (why); bag - the /bag read before; manual - from the tray (sold
;whether the game says full or not; the bot may be off); rehearse - up to the confirmation, read, logged, closed. The
;result ({res: sold, notfull, rehearsed, nothing, stopped, failed, crowns; why...})
QsRun(d, bag, manual := false, rehearse := false)
	{
	global QsBusy, QsSince, QsManual, QsLeftover, QsStep, QsBefore ; (v1 globals it sets)
	if (QsBusy)
		return ""
	QsBusy := 1, QsSince := A_TickCount, QsManual := manual ? 1 : 0, QsLeftover := 0, QsStep := 0
	UpdateGameRect()
	qOwn := MouseGrab()
	SetStatus("Quick selling the backpack")
	ReleaseKeys()
	QsLogOpen()
	QsBefore := V1Obj({items: bag.items, gold: bag.gold, pouch: bag.goldMax, sets: V1Obj(), dgKeep: bag.dgKeep})
	for qi, qs in bag.setItems
		QsBefore.sets[qs.gid] := qs
	QsLog((rehearse ? "REHEARSAL (nothing is sold) - " : "") (manual ? "asked for from the tray" : d.why) " - opening the backpack")
	qRes := QsSteps(bag, manual, rehearse)
	qRes := QsFinish(qRes)
	;(a run that failed after SELL under a dungeon's hold - QsConfirmSell's note standing - with every window closed
	;(QsBackKind "": the sale no longer pending): the backpack read again - down by the sale, it went through: that count
	;noted; not down, it didn't: the count before SELL put back, so your sort is measured from it. A window still up or
	;the back-out stopped (you, a battle - a box or the confirmation left up, so a sale may still land) or no read: the
	;note kept - the safe side: at worst 10 more items to sort, never the bot's own late sale taken for your sort)
	if (IsObject(qRes) && qRes.res = "failed" && QsIni("dungeon") != "" && IsObject(QsBefore) && QsBefore.marked && QsBackKind = "")
		{
		qNow := NavBag()
		if (IsObject(qNow) && V1IsNum(qNow.items) && V1IsNum(QsBefore.soldN))
			QsIniSet("markitems", qNow.items <= QsBefore.items - QsBefore.soldN + 1 && qNow.items < QsBefore.items ? qNow.items : V1IsNum(QsBefore.markWas) ? Max(QsBefore.markWas, qNow.items) : qNow.items)
		}
	QsBusy := 0, QsManual := 0
	SetStatus("")
	if (qOwn)
		MouseLetGo()
	WalkResume()
	QsAfter(qRes, manual)
	return qRes
	}

;The steps; the result as QsRun's - a step that fails returns its failure (QsFinish backs out)
QsSteps(bag, manual, rehearse)
	{
	;(0. the groups: the gear's and the pets' - less any an Equipment Set's item or a Crown-shop item in the backpack is
	;in; none at all when the sets can't be read)
	qCats := QsCategories(bag, &qWhyNot)
	if (!IsObject(qCats))
		return QsFail(qWhyNot)
	QsBefore.shopLeft := qCats.shopLeft
	;(1. the backpack open, on its page)
	qr := QsOpenBook()
	if (IsObject(qr))
		return qr
	;(2. its own N/M)
	g := QsGui("InventorySpellbookPage/inventorySpace")
	qSp := IsObject(g) ? QsParseSpace(V1At(g.win["InventorySpellbookPage/inventorySpace"], "text")) : ""
	if (!IsObject(qSp))
		{
		qb := NavBag()
		qSp := IsObject(qb) ? qb.space : ""
		}
	if (!IsObject(qSp))
		return QsFail("the backpack's count (N/M) couldn't be read")
	QsCalibrate(bag.items, qSp.n, qSp.m)
	if (!manual && qSp.n < qSp.m - QsFree())
		{
		QsLog("the game's own count is " qSp.n "/" qSp.m " - not full: closing it, nothing sold")
		qr := QsCloseBook()
		return IsObject(qr) ? qr : V1Obj({res: "notfull", why: qSp.n "/" qSp.m})
		}
	QsLog("the game's own count is " qSp.n "/" qSp.m (qSp.n >= qSp.m - QsFree() ? " - full" : "") ": quick selling (" (QsPets() ? "gear and pets" : "gear") ", for gold)")
	;(4. Quick Sell - on its BACKPACK tab)
	qr := QsOpenQuickSell()
	if (IsObject(qr))
		return qr
	;(5. each group with ALL)
	qPicked := 0
	for qi, qc in qCats.list
		{
		qr := QsSelectGroup(qc, &qn)
		if (IsObject(qr))
			return qr
		qPicked += qn
		}
	if (!qPicked)
		{
		QsLog("nothing Quick Sell can sell in " (qCats.list.Length ? "the groups" : "any group left") " - closing")
		return V1Obj({res: "nothing", why: "nothing Quick Sell can sell in the gear" (QsPets() ? " and pet" : "") " groups", back: 1})
		}
	;(6. SELL: the confirmation)
	qr := QsClickWait("buyWindow/sellAction", "SELL", "QuickSellConfirmationWindow", 3000, "the confirmation window")
	if (IsObject(qr))
		return qr
	;(7. its numbers, from the game's memory)
	qr := QsConfirm(qCats, &qNums)
	if (IsObject(qr))
		return qr
	if (rehearse)
		{
		QsSnap("the confirmation")
		QsLog("rehearsal - not sold: closing the confirmation and the windows")
		return V1Obj({res: "rehearsed", why: "the rehearsal stops at the confirmation", nums: qNums, back: 1})
		}
	;(8. SELL in the confirmation)
	qr := QsConfirmSell(qNums)
	if (IsObject(qr))
		return qr
	;(9. the sale checked in the game's memory)
	return QsVerify(qNums)
	}

;A step's end: a failure backed out of (window by window); windows a battle left open closed at the next look
QsFinish(r)
	{
	global QsLeftover, QsLeftoverTries, QsLeftoverAt ; (v1 globals it sets)
	if (!IsObject(r))
		return V1Obj({res: "failed", why: "?"})
	if (r.res = "stopped" && r.kind = "cap")
		r.res := "failed"
	if (r.res = "failed")
		QsLog("quick sell failed: " r.why " - backing out")
	if ((r.res = "failed" || r.back) && !r.backed)
		{
		r.backed := 1
		QsBackOut(r.why)
		}
	if (r.res = "stopped")
		{
		QsLog("quick sell stopped: " r.why (r.kind = "user" ? "" : r.kind = "battle" ? " (its windows closed after the battle)" : ""))
		if (r.kind = "battle" || r.kind = "front")
			QsLeftover := 1, QsLeftoverTries := 0, QsLeftoverAt := 0
		}
	return r
	}

;The result into the waits: a sale at most every 10 minutes, 15 after a failure, 3 failures in a row given up; 60 when it
;freed under 5 slots and is still full, or there's nothing to sell
QsAfter(r, manual)
	{
	global QsFails, QsTryAt, QsStill, QsLookAt, QsBlocked ; (v1 globals it sets)
	QsFails := QsFails ? QsFails : 0
	now := A_TickCount
	;(groups left out for a Crown-shop item in them: said in the alerts - banking those items has the groups sold)
	qLeft := (IsObject(QsBefore) && QsBefore.shopLeft != "") ? " Not quick sold at all: the groups " QsBefore.shopLeft " - a Crown-shop item is in each (never sold, nor its group). Bank those items to have the rest of those groups sold." : ""
	;(a dungeon's hold, the gear pass's sale (QsLook - dgKeep): the Deck and Pet groups weren't tried - said, and how to free them)
	qDgKeep := IsObject(QsBefore) && QsBefore.dgKeep != ""
	if (qDgKeep)
		qLeft .= " The Deck and Pet groups were kept for a dungeon's drops (the gear pass never compares decks or pets) - look through them, then remove 10 items, quick sell from the tray, or tick '...even with a dungeon's drops in it' (Settings: THE BACKPACK)."
	if (r.res = "sold")
		{
		QsFails := 0, QsTryAt := now + 600000
		qAfter := r.after, qd := IsObject(qAfter) ? QsDecide(qAfter, QsState()) : ""
		QsStill := IsObject(qd) && qd.full ? 1 : 0
		if (QsStill && QsBefore.items - qAfter.items < 5)
			{
			QsTryAt := now + 3600000
			QsLog("still full after the sale (it freed " QsBefore.items - qAfter.items " slots) - not tried again for 60 minutes")
			AlertSend(qDgKeep ? "dgkeep" : "inventory", "backpack still full", "Quick sell freed only " QsBefore.items - qAfter.items " slots - the rest can't be quick sold (emotes, mounts, Crowns items, locked or set items). Drops go to the bank; tried again in 60 minutes." qLeft)
			}
		if (QsAfterDungeon())
			QsMarkClear("sold with '...even with a dungeon's drops in it' ticked")
		;(a dungeon's hold, the gear pass's sale: the Deck and Pet groups kept - said once an hour, with how to free them -
		;its own alert kind: an in-dungeon "backpack full" minutes before mustn't swallow it; the still-full alert above says
		;it already, on the same kind)
		else if (qDgKeep && !(QsStill && QsBefore.items - qAfter.items < 5) && QsSay("dgkeep", "the gear sold, the Deck and Pet groups kept: a dungeon's hold (the gear pass never compares decks or pets) - look through them, then remove 10 items, quick sell from the tray, or tick '...even with a dungeon's drops in it'", 3600000))
			AlertSend("dgkeep", "decks and pets held", "The full backpack was quick sold without its Deck and Pet groups: a dungeon's hold keeps them (the gear pass never compares decks or pets). Look through them, then remove 10 items, quick sell from the tray, or tick '...even with a dungeon's drops in it' (Settings: THE BACKPACK).")
		}
	;(not full by the game's own N/M: Zeke's alert not looked at again for 10 minutes (QsLookAt); a full count waits 10
	;minutes only when the look's /bag (QsLastBag) still counts full with the calibration QsSteps just made - it didn't stick)
	else if (r.res = "notfull")
		{
		QsLookAt := now, QsStill := 0
		if (IsObject(QsLastBag) && QsDecide(QsLastBag, QsState()).full)
			QsTryAt := now + 600000
		}
	;(a rehearsal - quicksell:2 - at most once an hour after battles; the mob loop not stopped for it)
	else if (r.res = "rehearsed")
		{
		QsStill := 0
		if (!manual)
			QsTryAt := now + 3600000
		}
	else if (r.res = "nothing")
		{
		QsTryAt := now + 3600000, QsStill := 1
		AlertSend("inventory", "backpack full", "The backpack is full, but Quick Sell finds nothing it may sell in the gear" (QsPets() && !qDgKeep ? " and pet" : "") " groups. Drops go to the bank; tried again in 60 minutes." qLeft)
		}
	else if (r.res = "stopped")
		QsTryAt := now + 600000, QsStill := 1
	else if (r.res = "crowns")
		QsTryAt := now + 3600000, QsStill := 1
	else
		{
		QsFails += 1, QsTryAt := now + 900000, QsStill := 1
		if (QsFails >= 3 && !manual)
			{
			QsBlocked := 1
			QsLog("quick sell failed 3 times in a row - given up till it's switched off and on, or the bot restarts")
			AlertSend("inventory", "quick sell gave up", "The backpack is full and quick sell failed 3 times in a row (last: " r.why "). Drops go to the bank. Switch quick sell off and on (Settings: THE BACKPACK) to try again.")
			}
		else
			AlertSend("inventory", "backpack full", "Couldn't quick sell the full backpack: " r.why " - drops go to the bank; tried again in 15 minutes.")
		}
	}

;---- The steps ----

;The backpack open on its page: the book open on another page - its backpack tab; closed - B (it toggles: read first).
;Quick Sell's windows left open from before (a run cut short) closed first
QsOpenBook()
	{
	qPaths := "DeckConfiguration,InventorySpellbookPage,DeckConfiguration/Inventory,shopGUI,buyWindow,QuickSellConfirmationWindow,QuickSellWaitingWindow"
	g := QsGui(qPaths)
	if (!IsObject(g))
		return QsFail("the game's windows can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message is up before the run (`"" g.box.caption "`")")
	qLeft := ""
	for qi, qp in ["shopGUI", "buyWindow", "QuickSellConfirmationWindow", "QuickSellWaitingWindow"]
		if (V1At(g.win[qp], "shown"))
			qLeft .= (qLeft = "" ? "" : ", ") qp
	if (qLeft != "")
		{
		QsLog("windows left open from before (" qLeft ") - closing them first")
		if (!QsBackOut("windows left open from before"))
			return V1Obj({res: "failed", why: "windows left open from before (" qLeft ") couldn't be closed", backed: 1})
		g := QsGui(qPaths)
		if (!IsObject(g))
			return QsFail("the game's windows can't be read (" NavGuiWhy ")")
		}
	;(the backpack's page shown: the book's open on it - whatever the book's own window is called)
	if (V1At(g.win["InventorySpellbookPage"], "shown"))
		return ""
	if (V1At(g.win["DeckConfiguration"], "shown"))
		return QsClickWait("DeckConfiguration/Inventory", "", "InventorySpellbookPage", 3000, "the backpack page")
	qr := QsKeyB("to open the backpack", 0)
	if (IsObject(qr))
		return qr
	return QsWaitFor("InventorySpellbookPage", "shown", 1, 3000, "the backpack page")
	}

;The book closed again after a look (B - it was opened with B), checked. Its windows not read: left for the next look to
;close (QsLeftover)
QsCloseBook()
	{
	g := QsGui("DeckConfiguration,InventorySpellbookPage")
	if (!IsObject(g))
		{
		QsLog("the book can't be read (" NavGuiWhy ") - closed at the next look if it's still open")
		QsLeftoverSet()
		return ""
		}
	if (!QsBookOpen(g))
		return ""
	qr := QsKeyB("to close the backpack", 1)
	if (IsObject(qr))
		return qr
	qr := QsWaitFor("DeckConfiguration", "shown", 0, 1500, "the book to close")
	return IsObject(qr) ? qr : QsWaitFor("InventorySpellbookPage", "shown", 0, 1500, "the book to close")
	}

;The book open (g: a QsGui read with DeckConfiguration and InventorySpellbookPage): its window or its backpack page shown
QsBookOpen(g)
	{
	return IsObject(g) && (V1At(g.win["DeckConfiguration"], "shown") || V1At(g.win["InventorySpellbookPage"], "shown"))
	}

;Windows left open: closed at the next look (QsLeftoverTick) - tries counted afresh unless they're already being closed
QsLeftoverSet()
	{
	global QsLeftover, QsLeftoverTries, QsLeftoverAt ; (v1 globals it sets)
	if (!QsLeftover)
		QsLeftover := 1, QsLeftoverTries := 0, QsLeftoverAt := A_TickCount
	}

;Quick Sell opened from the backpack page, on its BACKPACK tab (never the bank's)
QsOpenQuickSell()
	{
	qr := QsClickWait("InventorySpellbookPage/QuickSell_Item", "", "buyWindow", 3000, "the Quick Sell window")
	if (IsObject(qr))
		return qr
	g := QsGui("shopGUI,shopGUI/sellTab,shopGUI/bankSellTab,buyWindow")
	if (!IsObject(g))
		return QsFail("the Quick Sell window can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message after Quick Sell: `"" g.box.caption "`"")
	if (V1At(g.win["shopGUI/sellTab"], "checked") != 1 || V1At(g.win["shopGUI/bankSellTab"], "checked") = 1)
		return QsFail("Quick Sell isn't on its BACKPACK tab (never the bank's - BACKPACK " V1At(g.win["shopGUI/sellTab"], "checked") ", BANK " V1At(g.win["shopGUI/bankSellTab"], "checked") ")")
	return ""
	}

;The groups sold - the gear's eight and the pets' (quicksellpets), never the All group - less any group an Equipment
;Set's item or a Crown-shop item in the backpack is in, and the pets' while a pet to keep is (pets.txt - QsPetGuard):
;{list: [{name, kind, path, memPlain, memCrowns}], skipped, gearMax,
;petMax (the most each can sell - the backpack's plain items of those kinds: not Crowns items, Crown-shop ones or
;unsellable, by the game's memory), crownShop (the Crown-shop gear in them the game's memory doesn't flag as Crowns items),
;shopLeft (the groups left out for a Crown-shop item, with those items - for the alerts)};
;"" and why when a set item's or a Crown-shop item's kind isn't one the game's memory names
QsCategories(bag, &why)
	{
	static qKnown := V1Obj({hat: 1, robe: 1, shoes: 1, weapon: 1, athame: 1, amulet: 1, ring: 1, deck: 1, pet: 1, mount: 1, jewel: 1
		, emote: 1, elixir: 1, housing: 1, treasurecard: 1, reagent: 1})
	why := ""
	;(the sets not all read: an item of one could be sold - nothing is)
	if (!bag.setsOk)
		{
		why := "the Equipment Sets couldn't all be read from the game's memory - nothing sold (a set's item could be)"
		return ""
		}
	qAll := [["Hat", "hat"], ["Robe", "robe"], ["Shoes", "shoes"], ["Weapon", "weapon"], ["Athame", "athame"], ["Amulet", "amulet"], ["Ring", "ring"], ["Deck", "deck"]]
	if (QsPets())
		qAll.Push(["Pet", "pet"])
	qGuard := V1Obj()
	for qi, qs in bag.setItems
		{
		qName := qs.name != "" ? qs.name : "id " qs.tid
		;(a kind the game's memory doesn't name - another adjective, a list read in part: it could be in any group)
		if (!qKnown.Has(qs.kind))
			{
			why := "an Equipment Set's item in the backpack (" qName ", set " qs["set"] ") is of a kind the bot can't tell - lock or equip it, or Quick Sell could sell it"
			if (V1IsFunc("WalkNotify"))
				WalkNotify.Call("quicksell", "lock or equip " qName, "It's in Equipment Set " qs["set"] " and in the backpack - quick sell could sell it, so it doesn't sell at all till it's locked or equipped.")
			return ""
			}
		qGuard[qs.kind] := (qGuard.Has(qs.kind) ? qGuard[qs.kind] ", " : "") qName " (set " qs["set"] ")"
		}
	;(a Crown-shop item the game doesn't flag as a Crowns item - "Crown-S05-Robe-093": the game's Quick Sell may take it for
	;plain gear, and locked items - the bot can't read locks - keep the confirmation's gear count from showing it: its
	;group left out. One of a kind the bot can't tell: nothing sold)
	qShop := V1Obj()
	if (IsObject(bag.crownShop))
		for qi, qx in bag.crownShop
			{
			if (!qKnown.Has(qx.kind))
				{
				why := "a Crown-shop item in the backpack (" qx.name ") is of a kind the bot can't tell - nothing sold (never a Crowns item)"
				return ""
				}
			qGuard[qx.kind] := (qGuard.Has(qx.kind) ? qGuard[qx.kind] ", " : "") qx.name " (Crown shop)"
			qShop[qx.kind] := (qShop.Has(qx.kind) ? qShop[qx.kind] ", " : "") qx.name
			}
	;(pets to keep - goal 6, perfect pets: pets.txt's wanted talents, QsPetGuard. A pet to keep in the backpack - or the
	;pets not read whole, or fewer read in the backpack than its Pet count here - leaves the Pet group out whole: the bot
	;can't read locks, so it can't sell round one pet. No pets.txt, or no pet in the backpack: nothing asked, sold as before)
	if (QsPets() && (bag.cats.Has("pet") || bag.cats.Has("?")))
		{
		qPetKeep := QsPetGuard(bag)
		if (qPetKeep != "")
			qGuard["pet"] := (qGuard.Has("pet") ? qGuard["pet"] ", " : "") "kept: " qPetKeep
		}
	;(a dungeon's hold with the gear pass's sale (QsLook - bag.dgKeep): its decks and pets never compared - the Deck and Pet
	;groups left out, the gear groups sold)
	if (bag.dgKeep != "")
		for qi, qk in ["deck", "pet"]
			qGuard[qk] := (qGuard.Has(qk) ? qGuard[qk] ", " : "") bag.dgKeep
	;(shopLeft: the groups left out for a Crown-shop item - for the alerts)
	qOut := V1Obj({list: [], skipped: "", shopLeft: "", gearMax: 0, petMax: 0, crownShop: ""})
	for qi, qc in qAll
		{
		if (qGuard.Has(qc[2]))
			{
			qOut.skipped .= (qOut.skipped = "" ? "" : "; ") qc[1] " (" qGuard[qc[2]] ")"
			if (qShop.Has(qc[2]) && StrLen(qOut.shopLeft) < 300)
				qOut.shopLeft .= (qOut.shopLeft = "" ? "" : "; ") qc[1] " (" qShop[qc[2]] ")"
			continue
			}
		qc2 := bag.cats.Has(qc[2]) ? bag.cats[qc[2]] : ""
		;(memPlain: its items that are neither Crowns items (nor Crown-shop ones) nor unsellable, by the game's memory - each
		;item counted once; an older helper's line without it: worked out)
		qn := !IsObject(qc2) ? 0 : qc2.plain != "" ? qc2.plain : V1Max(0, V1Sub(V1Sub(qc2.n, qc2.crowns), qc2.nosell))  ; (v1: an older helper's count not read - blank)
		qOut.list.Push(V1Obj({name: qc[1], kind: qc[2], path: "BackpackStuff/ShopCategory_" qc[1], memPlain: qn, memCrowns: IsObject(qc2) ? qc2.crowns : 0}))
		if (qc[2] = "pet")
			qOut.petMax := V1Add(qOut.petMax, qn)  ; (v1: an expression - a blank qn made it blank)
		else
			qOut.gearMax := V1Add(qOut.gearMax, qn)
		if (IsObject(bag.crownShop))
			for qj, qx in bag.crownShop
				if (qx.kind = qc[2] && StrLen(qOut.crownShop) < 400)
					qOut.crownShop .= (qOut.crownShop = "" ? "" : ", ") qx.name
		}
	;(items whose kind wasn't read may be in any group)
	if (bag.cats.Has("?"))
		qOut.gearMax := V1Add(qOut.gearMax, bag.cats["?"].n), qOut.petMax := V1Add(qOut.petMax, bag.cats["?"].n)  ; (v1: a blank count made them blank)
	if (qOut.skipped != "")
		QsLog("left out - an Equipment Set's or a Crown-shop item is in the group, or a pet to keep (bank Crown-shop items to have their group sold): " qOut.skipped)
	if (qOut.crownShop != "")
		QsLog("Crown-shop gear in the groups without the game's Crowns flag (not counted as plain gear - kept out if the game takes them for Crowns items or they're locked; if the confirmation's equipment goes over the plain gear, nothing's sold): " qOut.crownShop)
	return qOut
	}

;Pets to keep out of the sale (goal 6, perfect pets - vision\petplan.py keepers): "" none (the Pet group sold as before),
;else which and why - QsCategories leaves the whole Pet group out for it. Asked only when pets.txt names wanted talents
;(QsPetWant - no file, no want: line: "" at once, nothing asked). Then the helper's /pets (NavPets): a pet in the backpack
;it keeps - one with every wanted talent (you're told: lock it), or one whose talents aren't read (not confirmed in the
;game yet - every pet, for now) - keeps the group out; so do the pets not read, or not read whole (a pet could be missed),
;fewer pets read in the backpack than bag (NavBag's reading) counts in its Pet group, and a pets.txt that's there but
;can't be read (fails safe).
;TODO (goal 6 steps 9-11 - they need the game's pet windows first): the pet program's own switches (training, hatching)
;plug in here - hatching on keeps the group out whole too (its parents and babies) and is passed on: NavPets(want, 1)
QsPetGuard(bag)
	{
	qpgWant := QsPetWant(&qpgBad)
	if (qpgBad != "")
		return "pets.txt can't be read (" qpgBad ") - every pet"
	if (qpgWant = "")
		return ""
	qpgPets := NavPets(qpgWant, 0)
	if (!IsObject(qpgPets))
		return "the pets can't be read from the game's memory (" NavPetsWhy ") - every pet"
	if (!qpgPets.whole)
		return "the pets not all read (" (qpgPets.why != "" ? qpgPets.why : "the backpack read in part") ") - every pet"
	;(the backpack's pets /pets read checked against its Pet group's count in bag - NavBag's own reading, from the items'
	;"Pet" adjective: fewer read - a pet whose behaviour petmem doesn't know, or one missed as the backpack changed - and
	;the one not read could be sold with the group: every pet kept. More read is fine: an item whose kind bag couldn't
	;read ("?") may be a pet)
	qpgBagPets := bag.cats.Has("pet") ? bag.cats["pet"].n : 0
	qpgRead := 0
	for qpgI, qpgP in qpgPets.pets
		if (qpgP.where = "backpack")
			qpgRead += 1
	if (qpgBagPets = "" || qpgRead < qpgBagPets)
		return "the pets not all read (" (qpgBagPets = "" ? "the backpack's pet count not read" : qpgBagPets " in the backpack, " qpgRead " read") ") - every pet"
	qpgNames := V1Obj()
	for qpgI, qpgP in qpgPets.pets
		qpgNames[qpgP.gid] := qpgP.display != "" ? qpgP.display : qpgP.name != "" ? qpgP.name : "pet " qpgP.gid
	qpgOut := "", qpgDone := ""
	for qpgGid, qpgWhy in qpgPets.keep
		{
		if (V1At(qpgPets.keepWhere, qpgGid) != "backpack")
			continue
		qpgName := V1At(qpgNames, qpgGid) != "" ? qpgNames[qpgGid] : "pet " qpgGid
		if (InStr(qpgWhy, "every wanted talent"))
			qpgDone .= (qpgDone = "" ? "" : ", ") qpgName
		if (StrLen(qpgOut) < 300)
			qpgOut .= (qpgOut = "" ? "" : ", ") qpgName " (" qpgWhy ")"
		}
	;(a perfect pet in the backpack: lock it - quick sell sells no pet till it's locked or worn; once in 10 minutes)
	if (qpgDone != "" && QsSay("petdone", "a pet with every wanted talent is in the backpack: " qpgDone " - lock it in the game"))
		AlertSend("pets", "a perfect pet is in the backpack", qpgDone " has every talent pets.txt wants. Lock it in the game (or wear it) - till then quick sell sells no pets.")
	return qpgOut
	}

;pets.txt's wanted talents (goal 6, perfect pets): the file next to PlayerStats.txt, written by you - a line "want:
;Spell-Proof, Spell-Defying, Mighty, Pain-Giver, Pain-Bringer" (; starts a comment; more want: lines add to it) - as one
;text for /pets ("" none: no file, no want: line). bad: why the file is there but can't be read ("" it could)
QsPetWant(&bad)
	{
	bad := ""
	qpwPath := A_WorkingDir "\pets.txt"
	if (!FileExist(qpwPath))
		return ""
	qpwText := V1FileRead(qpwPath)
	if (ErrorLevel)
		{
		bad := "FileRead failed"
		return ""
		}
	qpwOut := ""
	Loop Parse, qpwText, "`n", "`r"
		{
		if (RegExMatch(RegExReplace(A_LoopField, ";.*"), "i)^\s*want\s*:\s*(.*\S)", &qpwM))
			qpwOut .= (qpwOut = "" ? "" : ", ") qpwM[1]
		}
	return qpwOut
	}

;One group: its button, then ALL (the "include Crowns Items?" box answered No), the shown rows checked - every row
;selected but the Crowns items'. picked: its rows selected (0: none to sell)
QsSelectGroup(c, &picked)
	{
	picked := 0
	;(its button clicked unless it's the group shown already - a second click could take it off)
	g := QsGui(c.path)
	if (!IsObject(g) || !IsObject(g.win[c.path]) || !(V1At(g.win[c.path], "shown") && V1At(g.win[c.path], "checked") = 1))
		{
		qr := QsClickWait(c.path, "", c.path, 3000, c.name "'s group", "checked")
		if (IsObject(qr))
			return qr
		}
	qRows := QsRows()
	if (!IsObject(qRows))
		return QsFail(c.name ": its rows can't be read (" NavGuiWhy ")")
	if (!qRows.shown)
		{
		QsLog(c.name ": none to sell")
		return ""
		}
	;(its first page only Crowns items: left alone - unless the game's memory has plain ones in it too, on a later page)
	if (!qRows.plain && V1Le(c.memPlain, 0))  ; (v1: a blank count compared as text - "" <= 0 is true)
		{
		QsLog(c.name ": only Crowns items (" qRows.shown ") - left alone")
		return ""
		}
	qr := QsAll(c)
	if (IsObject(qr))
		return qr
	qRows := QsRows()
	if (!IsObject(qRows))
		return QsFail(c.name ": its rows can't be read after ALL")
	;(ALL took nothing - it toggles? once more. Not when the page shows only Crowns items: none of them is to be selected)
	if (qRows.checked = 0 && qRows.plain)
		{
		QsLog(c.name ": ALL selected nothing - once more")
		qr := QsAll(c)
		if (IsObject(qr))
			return qr
		qRows := QsRows()
		if (!IsObject(qRows))
			return QsFail(c.name ": its rows can't be read after ALL")
		}
	if (qRows.crownsChecked)
		{
		AlertSend("crowns", "quick sell stopped", "`"Crowns`" items got selected in the Quick Sell window (" c.name ") - nothing sold, the windows closed (gold only).")
		return QsFail(c.name ": a Crowns item's row is selected - nothing sold")
		}
	if (qRows.plainChecked != qRows.plain)
		return QsFail(c.name ": " qRows.plainChecked " of its " qRows.plain " rows selected after ALL - not sure what it would sell")
	;(a first page of Crowns items only: the plain ones the memory counts, on later pages - the confirmation's numbers check it)
	picked := qRows.plain ? qRows.plainChecked : c.memPlain
	QsLog(c.name ": ALL - " picked " selected on its first page" (qRows.shown > picked ? " (" qRows.shown - picked " Crowns items left out)" : "") (qRows.names != "" ? ": " qRows.names : ""))
	return ""
	}

;The Quick Sell list's shown rows (its first page, 10): {shown, plain (not a Crowns item), checked, plainChecked,
;crownsChecked, names} - "" when they can't be read
QsRows()
	{
	qPaths := ""
	Loop 10
		qPaths .= (qPaths = "" ? "" : ",") "buyWindow/shoplist" A_Index - 1 ",buyWindow/num" A_Index - 1 "/Selected,buyWindow/shoplist" A_Index - 1 "/CrownsIcon"
	g := QsGui(qPaths)
	if (!IsObject(g) || g.box.shown)
		return ""
	qOut := V1Obj({shown: 0, plain: 0, checked: 0, plainChecked: 0, crownsChecked: 0, names: ""})
	Loop 10
		{
		qRow := g.win["buyWindow/shoplist" A_Index - 1], qSel := g.win["buyWindow/num" A_Index - 1 "/Selected"], qCr := g.win["buyWindow/shoplist" A_Index - 1 "/CrownsIcon"]
		if (!V1At(qRow, "shown"))
			continue
		qOut.shown += 1
		qCrown := V1At(qCr, "shown") ? 1 : 0
		qOn := V1At(qSel, "checked") = 1 ? 1 : 0
		qOut.plain += !qCrown, qOut.checked += qOn
		qOut.plainChecked += (qOn && !qCrown), qOut.crownsChecked += (qOn && qCrown)
		if (qRow.text != "" && StrLen(qOut.names) < 300)
			qOut.names .= (qOut.names = "" ? "" : ", ") qRow.text (qCrown ? " (Crowns)" : "")
		}
	return qOut
	}

;ALL, and within 1.2 s the box it raises answered - only the "include Crowns Items?" box (No); no box and rows selected
;for 0.45 s in a group the game's memory has no Crowns item in: none coming
QsAll(c)
	{
	qMark := QsLogMark()
	qr := QsClickTarget("buyWindow/AllAction", "ALL")
	if (IsObject(qr))
		return qr
	qt := A_TickCount
	while (A_TickCount - qt < 1200)
		{
		Sleep(150)
		g := QsGui("buyWindow,buyWindow/num0/Selected,buyWindow/num1/Selected,buyWindow/num2/Selected")
		if (IsObject(g) && !g.box.shown && A_TickCount - qt >= 450 && !c.memCrowns
			&& (V1At(g.win["buyWindow/num0/Selected"], "checked") = 1 || V1At(g.win["buyWindow/num1/Selected"], "checked") = 1 || V1At(g.win["buyWindow/num2/Selected"], "checked") = 1))
			return ""
		if (IsObject(g) && g.box.shown)
			{
			qr := QsAnswerBox(g, "select", qMark, "", &qSaid)
			if (IsObject(qr))
				return qr
			if (qSaid != "No")
				return QsFail("a game message after ALL was answered " qSaid)
			return ""
			}
		if (!QsOk(&qWhy, &qKind))
			return QsStop(qKind, qWhy)
		}
	return ""
	}

;The confirmation's numbers read from the game's memory and checked (QsConfirmOk), its SELL read on screen. nums: {name:
;{n, gold}} - Equipment, CrownEquipment, Furniture, CrownFurniture, Jewels, Reagents, TreasureCards, Pet, Total - and
;lost: the gold over the pouch (sold all the same: you said so)
QsConfirm(cats, &nums)
	{
	nums := V1Obj()
	qPaths := "QuickSellConfirmationWindow/SellButton"
	for qi, qn in QsConfirmNames()
		qPaths .= ",QuickSellConfirmationWindow/" qn "Number,QuickSellConfirmationWindow/" qn "Gold"
	g := QsGui(qPaths)
	if (!IsObject(g))
		return QsFail("the confirmation can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message over the confirmation: `"" g.box.caption "`"")
	;(AHK names aren't case-sensitive: the windows' variables named apart from the loop's qn)
	for qi, qn in QsConfirmNames()
		{
		qNumW := g.win["QuickSellConfirmationWindow/" qn "Number"], qGoldW := g.win["QuickSellConfirmationWindow/" qn "Gold"]
		nums[qn] := V1Obj({n: V1At(qNumW, "shown") ? QsDigits(qNumW.text) : "", gold: V1At(qGoldW, "shown") ? QsDigits(qGoldW.text) : ""})
		}
	qOk := QsConfirmOk(nums, QsPets(), QsBefore.gold, QsBefore.pouch, cats.gearMax, cats.petMax, &qWhy, &qLost)
	nums.lost := qLost
	QsLog("confirmation - equipment " nums.Equipment.n " (" QsThousands(nums.Equipment.gold) " gold), pets " nums.Pet.n " (" QsThousands(nums.Pet.gold) "), Crown equipment " nums.CrownEquipment.n
		. ", Crown furniture " nums.CrownFurniture.n ", furniture " nums.Furniture.n ", jewels " nums.Jewels.n ", reagents " nums.Reagents.n ", treasure cards " nums.TreasureCards.n
		. " - total " nums.Total.n " for " QsThousands(nums.Total.gold) " gold" (qLost > 0 ? " (" QsThousands(qLost) " of it over the gold pouch's " QsThousands(QsBefore.pouch) " - lost, sold all the same)" : "")
		. " (the groups chosen hold up to " cats.gearMax " gear" (QsPets() ? " and " cats.petMax " pets" : "") " by the game's memory)")
	if (!qOk)
		{
		if (InStr(qWhy, "Crown"))
			AlertSend("crowns", "quick sell stopped", "The Quick Sell confirmation listed Crowns items - closed, nothing sold (gold only).")
		return QsFail("the confirmation: " qWhy)
		}
	w := g.win["QuickSellConfirmationWindow/SellButton"]
	if (!QsReadWord(V1At(w, "l"), V1At(w, "t"), V1At(w, "r"), V1At(w, "b"), g, "SELL"))  ; (v1: its window not in the answer - blank)
		return QsFail("the confirmation's SELL button doesn't read SELL on screen - not clicked")
	return ""
	}

QsConfirmNames()
	{
	static qNames := ["Equipment", "CrownEquipment", "Furniture", "CrownFurniture", "Jewels", "Reagents", "TreasureCards", "Pet", "Total"]
	return qNames
	}

;The confirmation's numbers fine to sell (pure): every one read; Crown Equipment and Crown Furniture 0; pets 0 unless
;pets; furniture, jewels, reagents, treasure cards 0; a total of 1 or more that is its rows' (count and gold); no more
;gear / pets than the groups chosen hold (gearMax, petMax - "" not known). why: what's wrong; lost: the gold over the pouch
QsConfirmOk(nums, pets, gold, pouch, gearMax, petMax, &why, &lost)
	{
	why := "", lost := 0
	for qi, qn in QsConfirmNames()
		if (!IsObject(nums[qn]) || nums[qn].n = "" || nums[qn].gold = "")
			{
			why := "its numbers couldn't all be read (" qn ")"
			return false
			}
	if (nums.CrownEquipment.n != 0 || nums.CrownFurniture.n != 0)
		{
		why := "Crown items in it (Crown Equipment " nums.CrownEquipment.n ", Crown Furniture " nums.CrownFurniture.n ")"
		return false
		}
	if (!pets && nums.Pet.n != 0)
		{
		why := nums.Pet.n " pets in it - quicksellpets is off"
		return false
		}
	for qi, qn in ["Furniture", "Jewels", "Reagents", "TreasureCards"]
		if (nums[qn].n != 0)
			{
			why := "not gear: " qn " " nums[qn].n
			return false
			}
	qSumN := 0, qSumG := 0
	for qi, qn in QsConfirmNames()
		if (qn != "Total")
			qSumN += nums[qn].n, qSumG += nums[qn].gold
	if (nums.Total.n < 1)
		{
		why := "nothing in it"
		return false
		}
	if (nums.Total.n != qSumN || nums.Total.gold != qSumG)
		{
		why := "its total (" nums.Total.n " for " nums.Total.gold ") isn't its rows' (" qSumN " for " qSumG ") - misread"
		return false
		}
	if (gearMax != "" && nums.Equipment.n > gearMax)
		{
		why := nums.Equipment.n " gear in it - more than the plain gear the groups chosen hold (" gearMax ") - a Crowns or Crown-shop item may be in it"
		return false
		}
	if (petMax != "" && nums.Pet.n > petMax)
		{
		why := nums.Pet.n " pets in it - more than the backpack holds (" petMax ")"
		return false
		}
	if (V1Gt(pouch, 0) && gold != "")  ; (v1: the pouch not read - blank - compared as text)
		lost := Max(0, gold + nums.Total.gold - pouch)
	return true
	}

;SELL in the confirmation, and within 2 s: the waiting window or the sale in the game's log (the pets box first: Yes
;when its count is the confirmation's and quicksellpets is on, else No). A Crowns box: nothing clicked, stopped
QsConfirmSell(nums)
	{
	;(the sale looked for in the game's log from SELL on; a box's key from its own mark - moved on after a Yes)
	qMark := QsLogMark(), qBoxMark := qMark
	g := QsGui("QuickSellConfirmationWindow/SellButton")
	w := IsObject(g) ? g.win["QuickSellConfirmationWindow/SellButton"] : ""
	;(the Crown check round it kept tight: the window's own "Crown Equipment" / "Crown Furniture" labels are above it -
	;the memory's numbers are its Crown check)
	qRad := IsObject(w) && w.found ? V1Round(V1Div(V1Div(V1Mul(V1Max(V1Sub(w.r, w.l), V1Sub(w.b, w.t)), GameW), g.rootW), 2)) + 40 : ""  ; (v1: its rect not read - blank math, Round 0)
	qr := QsClickTarget("QuickSellConfirmationWindow/SellButton", "SELL", qRad)
	if (IsObject(qr))
		return qr
	;(under a dungeon's hold, SELL clicked: the count it should come to noted - a sale that goes through unconfirmed (the
	;2 s here or QsVerify giving up) isn't taken for your sort at the next look (QsNoteBag); put back where it surely
	;didn't sell (a box answered other than Yes, or stopped); a failed run with every window closed reads the backpack
	;again after (QsRun))
	qMarkWas := QsIni("markitems")
	if (QsIni("dungeon") != "" && QsBefore.items != "")
		QsIniSet("markitems", V1Sub(QsBefore.items, nums.Total.n)), QsBefore.marked := 1, QsBefore.markWas := qMarkWas, QsBefore.soldN := nums.Total.n
	qt := A_TickCount
	while (A_TickCount - qt < 2000)
		{
		Sleep(150)
		QsLogNew()
		if (QsLogHas("sold", qMark) || QsLogHas("gui", qMark, "QuickSellWaitingWindow"))
			return ""
		g := QsGui("QuickSellWaitingWindow,QuickSellConfirmationWindow")
		if (!IsObject(g))
			continue
		if (V1At(g.win["QuickSellWaitingWindow"], "shown"))
			return ""
		if (g.box.shown)
			{
			qr := QsAnswerBox(g, "sell", qBoxMark, nums.Pet.n, &qSaid)
			if (IsObject(qr) || qSaid != "Yes")
				if (QsIni("dungeon") != "")
					QsIniSet("markitems", qMarkWas), QsBefore.marked := 0
			if (IsObject(qr))
				return qr
			if (qSaid != "Yes")
				return QsFail("the box after SELL was answered " qSaid " - not sold")
			;(a box after this one needs its own fresh key in the game's log - never the box just answered's; the sale's
			;lines since SELL still count, so qMark stays)
			qBoxMark := QsLogMark()
			qt := A_TickCount
			}
		}
	return QsFail("no sale after the confirmation's SELL (no waiting window, nothing in the game's log in 2 s)")
	}

;The sale checked: the backpack's count down by the total (one off allowed), the gold up by it (or at the pouch) - in
;15 s; the book closed; every Equipment Set item that was in the backpack still there (one gone: quick sell off)
QsVerify(nums)
	{
	qt := A_TickCount, qb := ""
	qWant := V1Gt(QsBefore.pouch, 0) ? V1Min(QsBefore.pouch, V1Add(QsBefore.gold, nums.Total.gold)) : V1Add(QsBefore.gold, nums.Total.gold)  ; (v1: the pouch or gold not read - blank)
	while (A_TickCount - qt < 15000)
		{
		Sleep(300)
		qb := NavBag()
		if (IsObject(qb) && qb.items != "" && qb.items <= QsBefore.items - nums.Total.n + 1 && qb.gold != "" && V1Ge(qb.gold, V1Sub(qWant, 1)))  ; (v1: the gold before not read - blank - compared as text)
			break
		qb := ""
		}
	if (!IsObject(qb))
		return QsFail("the sale didn't go through - the backpack's count and gold didn't change in 15 s")
	QsNoteBag(qb)
	qr := QsCloseAfterSale()
	;(the set items only checked with every Equipment Set read - a read without them isn't "they're gone": read again)
	qSets := qb
	Loop 5
		{
		if (IsObject(qSets) && qSets.setsOk)
			break
		Sleep(300)
		qSets := NavBag()
		}
	qHave := V1Obj(), qGone := ""
	if (!IsObject(qSets) || !qSets.setsOk)
		QsLog("the Equipment Sets couldn't be read after the sale - their items in the backpack not checked")
	else
		{
		for qi, qs in qSets.setItems
			qHave[qs.gid] := 1
		for qg, qs in QsBefore.sets
			if (!qHave.Has(qg))
				qGone .= (qGone = "" ? "" : ", ") (qs.name != "" ? qs.name : "id " qs.tid) " (set " qs["set"] ")"
		}
	QsLog("quick sold " nums.Total.n " items for " QsThousands(nums.Total.gold) " gold (bag " QsBefore.items " -> " qb.items " of " qb.allowed
		. ", gold " QsThousands(QsBefore.gold) " -> " QsThousands(qb.gold) ")" (nums.lost > 0 ? " - " QsThousands(nums.lost) " gold lost over the pouch" : ""))
	QsTray("Quick sold " nums.Total.n " items for " QsThousands(nums.Total.gold) " gold - the backpack was full.")
	if (qGone != "")
		{
		if (!StatsSet([["quicksell", 0]], "quick sell turned itself off " A_YYYY "-" A_MM "-" A_DD ": an Equipment Set's item was sold (" qGone ")"))
			Stats["quicksell"] := 0
		QsLog("an Equipment Set's item is gone after the sale: " qGone " - quick sell turned OFF")
		WalkNotify("quicksell", "an Equipment Set lost an item", "Quick sell sold " qGone " - it has turned itself off (Settings: THE BACKPACK). Lock the items your Equipment Sets use, then switch it on again.")
		AlertSend("inventory", "Equipment Set item sold", "Quick sell sold " qGone " from an Equipment Set - it has turned itself off.")
		}
	return V1Obj({res: "sold", why: "", n: nums.Total.n, gold: nums.Total.gold, lost: nums.lost, after: qb, gone: qGone})
	}

;After the sale the game closes the book itself; still open: its close button
QsCloseAfterSale()
	{
	qt := A_TickCount
	while (A_TickCount - qt < 1500)
		{
		g := QsGui("DeckConfiguration,InventorySpellbookPage,QuickSellWaitingWindow")
		if (IsObject(g) && !QsBookOpen(g) && !V1At(g.win["QuickSellWaitingWindow"], "shown") && !g.box.shown)
			return ""
		Sleep(300)
		}
	return QsBackOut("the book left open after the sale") ? "" : V1Obj({res: "failed", why: "the book stayed open"})
	}

;---- Backing out ----

;Closes the run's windows, the topmost first - a box (No; OK only on the safe list; any other left to you), the
;confirmation, Quick Sell, the book - each close checked within 1.5 s; 3 rounds. True when they're all closed. Your mouse or
;keys, a battle, the bot off stop it at once (the windows are yours / closed after the battle). Not all closed for any
;other reason (the windows not read, a close that failed): tried again at the next look (QsLeftover). QsBackKind: why not
QsBackOut(why)
	{
	global QsBackKind, NavGuiWaitUntil, QsLeftover ; (v1 globals it sets)
	qPaths := "QuickSellConfirmationWindow,QuickSellConfirmationWindow/QuickSellConfirmationCloseButton,QuickSellWaitingWindow,shopGUI,buyWindow,buyWindow/exit,DeckConfiguration,InventorySpellbookPage,DeckConfiguration/Close_Button"
	qClosed := "", QsBackKind := ""
	Loop 8
		{
		g := QsGui(qPaths)
		if (!IsObject(g))
			{
			;(not read - the helper's back-off after a read that failed, most likely: once more straight away, the windows
			;mustn't be left open)
			NavGuiWaitUntil := 0
			Sleep(300)
			g := QsGui(qPaths)
			}
		if (!IsObject(g))
			{
			QsLog("backing out (" why "): the game's windows can't be read (" NavGuiWhy ") - tried again at the next look")
			QsBackKind := "unread"
			QsLeftoverSet()
			return false
			}
		qWhat := g.box.shown ? "box" : V1At(g.win["QuickSellConfirmationWindow"], "shown") ? "confirmation" : V1At(g.win["QuickSellWaitingWindow"], "shown") ? "waiting"
			: V1At(g.win["buyWindow"], "shown") || V1At(g.win["shopGUI"], "shown") ? "quicksell" : QsBookOpen(g) ? "book" : ""
		if (qWhat = "")
			{
			if (qClosed != "")
				QsLog("quick sell stopped (" why ") - closed: " qClosed)
			return true
			}
		if (A_Index > 6)
			break
		if (qWhat = "waiting")
			{
			Sleep(500)
			continue
			}
		if (!QsOk(&qWhy, &qKind, true))
			{
			QsLog("backing out (" why ") stopped: " qWhy)
			QsBackKind := qKind
			if (qKind = "battle")
				QsLeftover := 1
			else if (qKind != "user")
				QsLeftoverSet()
			return false
			}
		if (qWhat = "box")
			{
			QsLogNew()
			qAns := QsBoxAnswer(g.box, QsLogBoxKey(""), g.btns, "backout", 0, "", QsLogBoxMsg(""))
			if (qAns.say != "No" && qAns.say != "OK")
				{
				QsLog("backing out (" why "): a game message I won't answer - `"" g.box.caption "`" (" qAns.why ") - left to you")
				if (qAns.crown)
					AlertSend("crowns", "quick sell stopped", "A Crowns box came up in the Quick Sell window - nothing clicked (gold only): `"" g.box.caption "`"")
				WalkNotify("window", "a game message is up", g.box.caption " - quick sell left it to you.")
				QsBackKind := "box"
				QsLeftoverSet()
				return false
				}
			qr := QsClickBox(g, qAns.say, qAns.crownSel)
			qGone := "box"
			}
		else if (qWhat = "confirmation")
			qr := QsClickTarget("QuickSellConfirmationWindow/QuickSellConfirmationCloseButton", ""), qGone := "QuickSellConfirmationWindow"
		else if (qWhat = "quicksell")
			qr := QsClickTarget("buyWindow/exit", ""), qGone := "buyWindow"
		else if (V1At(g.win["DeckConfiguration/Close_Button"], "shown"))
			qr := QsClickTarget("DeckConfiguration/Close_Button", ""), qGone := "DeckConfiguration,InventorySpellbookPage"
		else
			qr := QsKeyB("to close the book (its close button not read)", 1), qGone := "DeckConfiguration,InventorySpellbookPage"
		if (IsObject(qr))
			{
			QsLog("backing out (" why "): " qr.why)
			QsBackKind := qr.res = "stopped" ? qr.kind : "click"
			if (qr.res = "stopped" && qr.kind = "battle")
				QsLeftover := 1
			else if (QsBackKind != "user")
				QsLeftoverSet()
			if (qr.res != "stopped")
				WalkNotify("window", "the Quick Sell window won't close", "Quick sell stopped (" why ") and couldn't close its windows: " qr.why)
			return false
			}
		qClosed .= (qClosed = "" ? "" : ", ") qWhat
		;(each close checked: gone within 1.5 s)
		qt := A_TickCount
		while (A_TickCount - qt < 1500)
			{
			Sleep(150)
			g2 := QsGui(qGone = "box" ? "buyWindow" : qGone)
			if (IsObject(g2) && (qGone = "box" ? !g2.box.shown : QsAllHidden(g2, qGone)))
				break
			}
		}
	QsLog("backing out (" why "): still open after 3 rounds - left to you")
	WalkNotify("window", "the Quick Sell window won't close", "Quick sell stopped (" why ") and its windows are still open.")
	QsBackKind := "stuck"
	QsLeftoverSet()
	return false
	}

;None of the windows at paths ("A,B") shown in the read g
QsAllHidden(g, paths)
	{
	for qi, qp in StrSplit(paths, ",")
		if (V1At(g.win[qp], "shown"))
			return false
	return true
	}

;---- Message boxes ----

;What to answer a game message box (pure): {say: "No" / "Yes" / "OK" / "" (none - back out), why, crown (a Crowns box:
;stopped, nothing clicked), crownSel (the "include Crowns Items?" box)}. box: {caption, title, captionKey}; logKey and
;logMsg: the game's log's DisplayMessageBox for it (key, message); btns: its shown buttons' {label}; stage: select (after
;ALL), sell (after the confirmation's SELL), backout; pets: quicksellpets; petCount: the confirmation's pets
QsBoxAnswer(box, logKey, btns, stage, pets, petCount, logMsg := "")
	{
	qCap := Trim(box.caption), qTitle := Trim(box.title), qCk := Trim(box.captionKey)
	;(the one Crown box it may click: "include Crowns Items in the selected items?" - only No, only when the game's log's key,
	;the caption and the button's label agree; never Yes)
	if (logKey = "GUI2_00001001" && (qCk = "" || qCk = "GUI2_00001001")
		&& RegExMatch(qCap, "i)^Would you like to include Crowns Items in the selected items\?$"))
		{
		if (QsHasLabel(btns, "No") = 1)
			return V1Obj({say: "No", crownSel: 1, why: "the `"include Crowns Items?`" box - No: they stay out"})
		return V1Obj({say: "", crown: 1, why: "the `"include Crowns Items?`" box without one No button"})
		}
	;(any other Crown box - by its words, or by a Crowns box's key in the game's memory or its log: nothing clicked)
	if (RegExMatch(qCap " " qTitle " " logMsg, "i)cr[o0]wn") || RegExMatch(qCk " " Trim(box.titleKey) " " logKey, "GUI2_0000098[67]|GUI2_0000100[01]"))
		return V1Obj({say: "", crown: 1, why: "a Crowns box (" (logKey != "" ? logKey : "no key in the log") (qCk != "" ? ", " qCk : "") ")"})
	;(the pets box after the confirmation's SELL: Yes only with quicksellpets and the confirmation's own count - read off the
	;shown box's own caption (the game's memory: its key, if any, a pets box's); the log's message, when it's there, the same)
	if (logKey = "GUI2_00000988" || logKey = "GUI2_00000989")
		{
		qN := QsPetsCount(qCap), qLogN := QsPetsCount(logMsg)
		;(the shown box's own words must be a pets box's - the log's key alone may be an earlier box's: nothing clicked)
		if (qN = "")
			return V1Obj({say: "", why: "a pets box by the game's log, but the shown box's own words aren't a pets box's (`"" qCap "`")"})
		if (stage = "sell" && pets && qN != "" && petCount != "" && qN = petCount && (logMsg = "" || qLogN = qN)
			&& (qCk = "" || qCk = "GUI2_00000988" || qCk = "GUI2_00000989") && QsHasLabel(btns, "Yes") = 1)
			return V1Obj({say: "Yes", why: "the pets box (" qN ", as the confirmation counted) - Yes: quicksellpets is on"})
		if (QsHasLabel(btns, "No") = 1)
			return V1Obj({say: "No", why: "the pets box (" (qN = "" ? "its caption not read as one" : qN) (logMsg != "" && qLogN != qN ? ", the game's log " (qLogN = "" ? "?" : qLogN) : "")
				. (petCount != "" ? ", the confirmation " petCount : "") (pets ? "" : ", quicksellpets off") ") - No"})
		return V1Obj({say: "", why: "the pets box without one No button"})
		}
	;(an OK-only box that's safe to OK - its own words shown, never the log's key alone)
	qKey := box.captionKey != "" ? box.captionKey : logKey
	if (qCap != "" && RegExMatch(qKey, "^(GUI_NoQuickSell|GUI_NoQuickSellWhileShopping|GUI_00001109|GUI2_00001002|Housing_18)$") && btns.Length = 1 && QsHasLabel(btns, "OK") = 1)
		return V1Obj({say: "OK", why: "a message to OK (" qKey ")"})
	return V1Obj({say: "", why: "a game message it doesn't know (" (qKey != "" ? qKey : "no key") ")"})
	}

;The pets box's count in its words ("You are selling 3 Pets. Are you sure you want to sell these Pets?" - a Pet: 1), else ""
QsPetsCount(text)
	{
	if (RegExMatch(Trim(text), "i)^You are selling (a|\d+) Pets?\. Are you sure you want to sell (a|these) Pets?\?$", &qm))
		return (qm[1] = "a") ? 1 : qm[1] + 0
	return ""
	}

;How many of the buttons have the label (exactly, case aside)
QsHasLabel(btns, label)
	{
	qn := 0
	for qi, qb in btns
		if (Trim(qb.label) = label)
			qn += 1
	return qn
	}

;A box answered (QsBoxAnswer) and its button clicked; gone within 1.5 s. said: the answer clicked
QsAnswerBox(g, stage, mark, petCount, &said)
	{
	said := ""
	QsLogNew()
	qKey := QsLogBoxKey(mark)
	;(the box can be in the game's memory a moment before its line is in the game's log: up to 1.5 s for it - else the
	;"include Crowns Items?" box would be taken for another Crown box)
	qt := A_TickCount
	while (qKey = "" && QsLogPos != "" && A_TickCount - qt < 1500)
		{
		Sleep(150)
		QsLogNew()
		qKey := QsLogBoxKey(mark)
		}
	qMsg := QsLogBoxMsg(mark)
	qAns := QsBoxAnswer(g.box, qKey, g.btns, stage, QsPets(), petCount, qMsg)
	QsLog("box: `"" g.box.caption "`" (" (qKey != "" ? qKey : "no key in the game's log") ") - " qAns.why)
	if (qAns.crown)
		return QsCrownBox(g.box, qAns.why)
	if (qAns.say = "")
		return QsFail("a game message: `"" g.box.caption "`" - " qAns.why)
	qr := QsClickBox(g, qAns.say, qAns.crownSel)
	if (IsObject(qr))
		return qr
	said := qAns.say
	qt := A_TickCount
	while (A_TickCount - qt < 1500)
		{
		Sleep(150)
		g2 := QsGui("buyWindow")
		if (IsObject(g2) && !g2.box.shown)
			return ""
		}
	return QsFail("the box didn't go after " said)
	}

;A box's button clicked by its label (never by its place): one box up, one button with it, its size, its word read off the
;screen, no "Crown" round it (but for the "include Crowns Items?" box's No - its own words say Crowns), then the click (a
;Yes inside the run's 60 s)
QsClickBox(g, say, crownSel)
	{
	global QsStep ; (v1 globals it sets)
	;(two boxes up: the one read may not be the one on top - none clicked)
	if (g.box["count"] != 1)
		return V1Obj({res: "failed", why: (g.box["count"] = "" ? "how many message boxes are up couldn't be read" : g.box["count"] " message boxes are up") " - none clicked"})
	qb := "", qn := 0
	for qi, qx in g.btns
		if (Trim(qx.label) = say)
			qb := qx, qn += 1
	if (qn != 1)
		return V1Obj({res: "failed", why: "the box has " qn " `"" say "`" buttons"})
	if (V1Gt(V1Abs(V1Sub(V1Sub(qb.r, qb.l), 128)), 2) || V1Gt(V1Abs(V1Sub(V1Sub(qb.b, qb.t), 32)), 2) || qb.greyed = 1)  ; (v1: a rect not read - blank math, compared as text)
		return V1Obj({res: "failed", why: "the box's `"" say "`" button isn't as the game's file has it (" V1Sub(qb.r, qb.l) "x" V1Sub(qb.b, qb.t) (qb.greyed = 1 ? ", greyed" : "") ")"})
	if (V1Lt(qb.l, 0) || V1Lt(qb.t, 0) || V1Gt(qb.r, g.rootW) || V1Gt(qb.b, g.rootH))
		return V1Obj({res: "failed", why: "the box's `"" say "`" button is off the game"})
	QsPx(qb.l, qb.t, qb.r, qb.b, g.rootW, g.rootH, &qx, &qy)
	if (!QsPxOk(qx, qy, &qWhyPx))
		return V1Obj({res: "failed", why: "the box's `"" say "`" button: " qWhyPx})
	if (!QsReadWord(qb.l, qb.t, qb.r, qb.b, g, say))
		return V1Obj({res: "failed", why: "the box's button doesn't read `"" say "`" on screen - not clicked"})
	;(the Crown check round it kept tight - the button and 40 px: the box's own words are checked in memory and the log
	;(QsBoxAnswer), and over the confirmation its "Crown Equipment" label shows just above the box)
	qRad := V1Round(V1Div(V1Div(V1Mul(V1Max(V1Sub(qb.r, qb.l), V1Sub(qb.b, qb.t)), GameW), g.rootW), 2)) + 40
	if (!crownSel && !NoCrownsNear(qx, qy, qRad, "Backpack", "Quick sell", "by the Quick Sell window", "it only sells for gold", "quick sell stopped"))
		return V1Obj({res: "failed", why: "`"Crown`" read by the box's button (or the screen couldn't be read) - not clicked"})
	Critical()
	if (!QsOk(&qWhy, &qKind, say != "Yes"))
		{
		Critical("Off")
		return QsStop(qKind, qWhy)
		}
	if (!QsClickAt(qx, qy, &qWhy))
		{
		Critical("Off")
		return QsStop("user", qWhy)
		}
	Critical("Off")
	QsStep += 1
	QsLog("step " QsStep ": the box's `"" say "`" at " qx - GameLeft "," qy - GameTop)
	return ""
	}

;A Crown box it may not click (any but "include Crowns Items?"'s No): stopped, nothing clicked - left to you, quick sell off
QsCrownBox(box, why)
	{
	QsLog("a Crowns box: `"" box.caption "`" - nothing clicked (gold only), quick sell turned OFF; the windows are left to you")
	if (!StatsSet([["quicksell", 0]], "quick sell turned itself off " A_YYYY "-" A_MM "-" A_DD ": a Crowns box came up (" SubStr(box.caption, 1, 60) ")"))
		Stats["quicksell"] := 0
	AlertSend("crowns", "quick sell stopped", "A Crowns box came up in the Quick Sell window - nothing clicked (gold only), quick sell turned off: `"" box.caption "`"")
	WalkNotify("window", "a Crowns box is up in Wizard101", "`"" box.caption "`" - quick sell clicked nothing and turned itself off. Answer it yourself (No).")
	QsTray("Quick sell saw a Crowns box and stopped without clicking - it's turned itself off.", 2)
	return V1Obj({res: "crowns", why: why})
	}

;---- Clicks, keys and checks ----

;Fine to give the game input now: the bot on (or a run from the tray), no key or mouse of yours since the run began,
;Wizard101 in front, no battle; the whole run 60 s at most (not while backing out). kind: off, user, front, battle, cap
QsOk(&why, &kind, backingOut := false)
	{
	why := "", kind := ""
	if (!(BotOn || QsManual))
		why := "the bot was turned off", kind := "off"
	else if (QsSince && A_TickCount - UserIdle() > QsSince)
		why := "you touched the mouse or keyboard - the windows are yours", kind := "user"
	else if (!GameActive())
		why := "Wizard101 isn't the window in front", kind := "front"
	else if (QsBattleNow())
		why := "a battle started", kind := "battle"
	else if (!backingOut && QsSince && A_TickCount - QsSince > 60000)
		why := "the whole run took over 60 s", kind := "cap"
	return why = ""
	}

;A battle on: by the game's log, or its round's Pass button on screen
QsBattleNow()
	{
	BattleLogRead()
	return BattleLogInBattle() || QsBattlePic()
	}

QsStop(kind, why)
	{
	return V1Obj({res: "stopped", kind: kind, why: why})
	}

QsFail(why)
	{
	return V1Obj({res: "failed", why: why})
	}

;/gui for paths ("" when it can't be read - NavGuiWhy)
QsGui(paths)
	{
	return NavGui(paths, 600)
	}

;Waits up to ms for the window at path to have prop (shown, checked) = want, polling the game's memory every 150 ms; a
;box coming up, your input, a battle stop it
QsWaitFor(path, prop, want, ms, what)
	{
	qt := A_TickCount
	Loop
		{
		g := QsGui(path)
		if (IsObject(g))
			{
			if (g.box.shown)
				return QsFail("a game message came up waiting for " what ": `"" g.box.caption "`"")
			w := g.win[path], qv := 0
			if (IsObject(w))
				qv := (prop = "checked") ? ((w.shown && w.checked = 1) ? 1 : 0) : (w.shown ? 1 : 0)
			if (qv = want)
				return ""
			}
		if (A_TickCount - qt > ms)
			return QsFail("timed out waiting for " what " (" Round(ms / 1000, 1) " s)")
		if (!QsOk(&qWhy, &qKind))
			return QsStop(qKind, qWhy)
		Sleep(150)
		}
	}

;A click (QsClickTarget), then a wait for waitPath's prop
QsClickWait(path, label, waitPath, ms, what, prop := "shown")
	{
	qr := QsClickTarget(path, label)
	if (IsObject(qr))
		return qr
	return QsWaitFor(waitPath, prop, 1, ms, what)
	}

;A click on a window of the allow-list, by the game's memory: read now - shown once, inside its parent and the game, its
;size the .gui file's, not greyed, its label, no window shown over it (SELL's hidden BUY MORE...) - turned into pixels (not
;the Crown shop's corner, the right-hand column or off the game), no "Crown" read round it (r: how far - 260 at UI 1.144 by
;default; a close button's: the button and 40 px), the run still fine (QsOk) right before
QsClickTarget(path, label, r := "")
	{
	global QsStep ; (v1 globals it sets)
	qOver := QsTargetOver(path)
	g := QsGui(path (qOver != "" ? "," qOver : ""))
	if (!IsObject(g))
		return QsFail("the game's windows can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message is up (`"" g.box.caption "`")")
	w := g.win[path]
	if (!QsTargetOk(path, w, g.rootW, g.rootH, label, &qWhy))
		return QsFail(path " not clicked: " qWhy)
	for qi, qp in StrSplit(qOver, ",")
		if (qp != "" && V1At(g.win[qp], "shown"))
			return QsFail(path " not clicked: " qp " is shown over it (never clicked)")
	QsPx(w.l, w.t, w.r, w.b, g.rootW, g.rootH, &qx, &qy)
	QsJitter(w.l, w.t, w.r, w.b, g.rootW, g.rootH, &qx, &qy)
	if (!QsPxOk(qx, qy, &qWhy))
		return QsFail(path " not clicked: " qWhy)
	;(a close button: the Crown check round it kept tight - closing never spends anything, and an item named "...Crown..."
	;in the list beside it mustn't keep the windows open)
	if (r = "" && path ~= "exit|Close")
		r := Round(Max(w.r - w.l, w.b - w.t) * GameW / g.rootW / 2) + 40
	if (!NoCrownsNear(qx, qy, r, "Backpack", "Quick sell", "by the Quick Sell window", "it only sells for gold", "quick sell stopped"))
		return QsFail(path " not clicked: `"Crown`" read round it (or the screen there couldn't be read)")
	Critical()
	if (!QsOk(&qWhy, &qKind, path ~= "exit|Close"))
		{
		Critical("Off")
		return QsStop(qKind, qWhy)
		}
	if (!QsClickAt(qx, qy, &qWhy))
		{
		Critical("Off")
		return QsStop("user", qWhy)
		}
	Critical("Off")
	QsStep += 1
	QsLog("step " QsStep ": " path " at " qx - GameLeft "," qy - GameTop)
	return ""
	}

;Windows that, shown, lie over a target (never clicked): SELL's "BUY MORE..." (hidden by the game's file, on top of it)
QsTargetOver(path)
	{
	return path = "buyWindow/sellAction" ? "buyWindow/buyMoreAction" : ""
	}

;The click: the mouse onto x, y and a moment on it (the potion run's hover rule), then - no key or mouse of yours since the
;run began, the mouse still on it (you may have taken it during the hover) - clicked AT x, y. why: what stopped it
QsClickAt(x, y, &why)
	{
	why := ""
	QsInputMove(x, y)
	if (QsSince && A_TickCount - UserIdle() > QsSince)
		why := "you touched the mouse or keyboard - the windows are yours"
	else if (!QsInputMouseAt(x, y))
		why := "the mouse moved off the button before the click - the windows are yours"
	if (why != "")
		return false
	QsInputClickAt(x, y)
	return true
	}

;B (the game's backpack key - it toggles the book: open read first, by the caller): the run still fine right before
QsKeyB(what, open)
	{
	global QsStep ; (v1 globals it sets)
	Critical()
	if (!QsOk(&qWhy, &qKind, open = 1))  ; (v1: open = 1 - a comparison)
		{
		Critical("Off")
		return QsStop(qKind, qWhy)
		}
	QsInputKeyB()
	Critical("Off")
	QsStep += 1
	QsLog("step " QsStep ": B " what)
	return ""
	}

;The windows it may click (nothing else, ever) and their size in the game's .gui files (GUI units), or ""
QsTargetSize(path)
	{
	static qSizes := ""
	if (!IsObject(qSizes))
		{
		;(v1 {"key": v} - v2's literal takes no quoted keys: the same keys and values as pairs)
		qSizes := V1Obj("InventorySpellbookPage/QuickSell_Item", [50, 50], "buyWindow/AllAction", [57, 32], "buyWindow/sellAction", [254, 32]
			, "buyWindow/exit", [47, 47], "QuickSellConfirmationWindow/SellButton", [177, 32]
			, "QuickSellConfirmationWindow/QuickSellConfirmationCloseButton", [47, 47], "DeckConfiguration/Close_Button", [40, 37]
			, "DeckConfiguration/Inventory", [40, 37])
		for qi, qc in ["Hat", "Robe", "Shoes", "Weapon", "Athame", "Amulet", "Ring", "Deck", "Pet"]
			qSizes["BackpackStuff/ShopCategory_" qc] := [49, 49]
		}
	return qSizes.Has(path) ? qSizes[path] : ""
	}

;A window fine to click (pure): on the allow-list, found and shown once, inside its parent and the root, its .gui size
;(2 units either way), not greyed, its label (case aside; or its .gui key's) when one's given. why: what's wrong
QsTargetOk(path, w, rootW, rootH, label, &why)
	{
	why := ""
	qSize := QsTargetSize(path)
	if (!IsObject(qSize))
		why := "not on the allow-list"
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
	else if (w.pl != "" && (V1Lt(w.l, V1Sub(w.pl, 1)) || V1Lt(w.t, V1Sub(w.pt, 1)) || V1Gt(w.r, V1Add(w.pr, 1)) || V1Gt(w.b, V1Add(w.pb, 1))))  ; (v1: a parent rect read in part - blank math, compared as text)
		why := "outside its parent (" w.l "," w.t "," w.r "," w.b " in " w.pl "," w.pt "," w.pr "," w.pb ")"
	else if (Abs(w.r - w.l - qSize[1]) > 2 || Abs(w.b - w.t - qSize[2]) > 2)
		why := "its size " w.r - w.l "x" w.b - w.t " isn't the game file's " qSize[1] "x" qSize[2]
	else if (w.greyed = 1)
		why := "greyed out"
	else if (label != "" && w.text != label && !(label = "SELL" && w.key = "GUI_00006338") && !(label = "ALL" && w.key = "GUI_00006368"))
		why := "its label is `"" w.text "`", not " label
	return why = ""
	}

;The middle of a GUI rect (the root's units) in screen pixels (pure)
QsPx(l, t, r, b, rootW, rootH, &x, &y)
	{
	;(v1: a rect not read - blank math, and Round of a blank: 0)
	x := V1Round(V1Add(GameLeft, V1Div(V1Mul(V1Div(V1Add(l, r), 2), GameW), rootW)))
	y := V1Round(V1Add(GameTop, V1Div(V1Mul(V1Div(V1Add(t, b), 2), GameH), rootH)))
	}

;A random bit off the middle (clickrandom on): inside the rect's middle 40%
QsJitter(l, t, r, b, rootW, rootH, &x, &y)
	{
	if (V1Le(Stat("clickrandom"), 0))  ; (v1: a blank or text setting compared as text)
		return
	qw := Floor((r - l) * GameW / rootW * 0.2), qh := Floor((b - t) * GameH / rootH * 0.2)
	qdx := Random(-qw, qw)
	qdy := Random(-qh, qh)
	x += qdx, y += qdy
	}

;A pixel fine to click (pure): on the game, not in the Crown shop's corner (TargetClick's), not in the right-hand column
;of tips (Zeke, the Crown Shop's offers...)
QsPxOk(x, y, &why)
	{
	why := ""
	if (x < GameLeft || y < GameTop || x >= GameLeft + GameW || y >= GameTop + GameH)
		why := "off the game window (" x "," y ")"
	else if (x < GameLeft + Px(185) && y < GameTop + Px(110))
		why := "in the Crown shop's corner"
	else if (x > GameLeft + GameW - Round(130 * GameW / 2560))
		why := "in the right-hand column (the tips: never clicked)"
	return why = ""
	}

;A button's word read off the screen, 3 times bigger, plain, white or yellow ink (yellow-on-red reads badly at 1:1):
;No, Yes, OK, SELL (SEL, 5ELL)
QsReadWord(l, t, r, b, g, word)
	{
	static qRe := V1Obj({No: "i)^n[o0]$", Yes: "i)^y[e3]s$", OK: "i)^[o0]k(ay)?$", SELL: "i)^(sell|sel|5ell|seli|seil|5el)$"})
	QsPx(l, t, l, t, g.rootW, g.rootH, &qx1, &qy1)
	QsPx(r, b, r, b, g.rootW, g.rootH, &qx2, &qy2)
	qPad := Round(3 * GameW / g.rootW)
	qRead := ""
	for qi, qMode in [0, 3, 4]
		{
		qText := QsOcr(qx1 - qPad, qy1 - qPad, qx2 - qx1 + 2 * qPad, qy2 - qy1 + 2 * qPad, 3, qMode)
		if (ErrorLevel)
			continue
		qText := RegExReplace(qText, "[\s.!]+")
		qRead .= (qRead = "" ? "" : " / ") qText
		if (RegExMatch(qText, qRe[word]))
			return true
		}
	QsLog("the button doesn't read `"" word "`" on screen (read: " (qRead = "" ? "nothing" : qRead) ")")
	return false
	}

;"150/150" -> {n, m}, else ""
QsParseSpace(text)
	{
	if (RegExMatch(text, "(\d{1,4})\s*/\s*(\d{1,4})", &qm))
		return V1Obj({n: qm[1] + 0, m: qm[2] + 0})
	return ""
	}

;The digits of a number as the game shows it ("12,345" -> 12345), "" none
QsDigits(text)
	{
	qd := RegExReplace(text, "\D")
	return qd = "" ? "" : qd + 0
	}

QsThousands(n)
	{
	if (n = "" || !RegExMatch(n, "^-?\d+$"))
		return n
	qs := "", qn := Abs(n)
	while (qn >= 1000)
		qs := "," SubStr("00" Mod(qn, 1000), -3) qs, qn := Floor(qn / 1000)
	return (n < 0 ? "-" : "") qn qs
	}

;---- The game's log, read by the run itself (its own place; short opens, 1 MB at most a read - never held open) ----

QsLogOpen()
	{
	global QsLogEvents, QsLogPos, QsLogHead ; (v1 globals it sets)
	QsLogEvents := [], QsLogPos := "", QsLogHead := ""
	if (RcLog = "" || !FileExist(RcLog))
		return
	qf := V1Try(FileOpen, RcLog, "r", "CP0")  ; (v1: 0 when it can't be opened - v2 throws)
	if (!IsObject(qf))
		return
	QsLogHead := qf.Read(17), QsLogPos := qf.Length
	qf.Close()
	}

;What the game's log said since the last read: DisplayMessageBox (box: key, msg), Loaded GUI (gui: its name),
;MSG_QuickSellRequest (sold)
QsLogNew()
	{
	global QsLogHead, QsLogPos, QsLogEvents ; (v1 globals it sets)
	if (QsLogPos = "" || RcLog = "")
		return
	qf := V1Try(FileOpen, RcLog, "r", "CP0")  ; (v1: 0 when it can't be opened - v2 throws)
	if (!IsObject(qf))
		return
	qSize := qf.Length, qTop := qf.Read(17)
	if (qTop != QsLogHead || qSize < QsLogPos)
		QsLogHead := qTop, QsLogPos := 0
	if (qSize - QsLogPos > 1048576)
		QsLogPos := qSize - 1048576
	if (qSize <= QsLogPos)
		{
		qf.Close()
		return
		}
	qf.Pos := QsLogPos
	qChunk := qf.Read(qSize - QsLogPos)
	qf.Close()
	qNl := InStr(qChunk, "`n", false, -1)
	if (!qNl)
		return
	qChunk := SubStr(qChunk, 1, qNl)
	QsLogPos += StrLen(qChunk)
	if (!IsObject(QsLogEvents))
		QsLogEvents := []
	Loop Parse, qChunk, "`n", "`r"
		{
		if (InStr(A_LoopField, "DisplayMessageBox("))
			{
			qOk := RegExMatch(A_LoopField, "msg = (.*?), title = (.*?), msg string key = (\w*)(?:, title string key = (\w*))?", &qm)
			QsLogEvents.Push(V1Obj({kind: "box", key: !qOk ? "" : qm[3] != "" ? qm[3] : qm[4], msg: qOk ? qm[1] : "", title: qOk ? qm[2] : ""}))  ; (v1: no match - qm1..qm4 blank)
			}
		else if (RegExMatch(A_LoopField, "Loaded GUI '(?:.*[\\/])?([\w]+)\.gui'", &qm))
			QsLogEvents.Push(V1Obj({kind: "gui", key: qm[1]}))
		else if (InStr(A_LoopField, "MSG_QuickSellRequest"))
			QsLogEvents.Push(V1Obj({kind: "sold", key: ""}))
		}
	}

;Where the events are now (a step's own come after it)
QsLogMark()
	{
	QsLogNew()
	return IsObject(QsLogEvents) ? QsLogEvents.Length : 0
	}

;The newest box event's key / message since mark ("" from the run's start)
QsLogBoxKey(mark)
	{
	qe := QsLogLastBox(mark)
	return IsObject(qe) ? qe.key : ""
	}

QsLogBoxMsg(mark)
	{
	qe := QsLogLastBox(mark)
	return IsObject(qe) ? qe.msg : ""
	}

QsLogLastBox(mark)
	{
	if (!IsObject(QsLogEvents))
		return ""
	qi := QsLogEvents.Length
	while (qi > (mark = "" ? 0 : mark))
		{
		if (QsLogEvents[qi].kind = "box")
			return QsLogEvents[qi]
		qi -= 1
		}
	return ""
	}

;An event of kind (and key) since mark
QsLogHas(kind, mark, key := "")
	{
	if (!IsObject(QsLogEvents))
		return false
	for qi, qe in QsLogEvents
		if (qi > mark && qe.kind = kind && (key = "" || qe.key = key))
			return true
	return false
	}

;---- The tray menu ----

;"Quick sell the backpack now" / "Quick sell rehearsal (stops at the confirmation)": straight away, sold whether the game
;says full or not (never in a dungeon); the dungeon's hold dropped (a sale asked for)
QsMenuNow(rehearse := false)
	{
	if (QsBusy)
		{
		QsTray("A quick sell is already under way.")
		return
		}
	qDg := QsDungeonNow()
	if (qDg != "")
		{
		QsLog("asked for from the tray - not in " qDg " (a dungeon's drops are the good gear)")
		QsTray("No quick sell in a dungeon (" qDg ").")
		return
		}
	QsActivateGame()
	UpdateGameRect()
	bag := NavBag()
	if (!IsObject(bag))
		{
		QsLog("asked for from the tray - the game's memory can't be read: " NavBagWhy)
		QsTray("Quick sell needs the game's memory (the vision helper): " NavBagWhy, 2)
		return
		}
	QsNoteBag(bag)
	if (!QsMayRun(&qWhy, true))
		{
		QsLog("asked for from the tray - not now: " qWhy)
		QsTray("Quick sell: not now - " qWhy ".", 2)
		return
		}
	if (!rehearse)
		QsMarkClear("a quick sell was asked for from the tray")
	QsRun(V1Obj({why: "asked for from the tray"}), bag, true, rehearse)
	}

;---- The only places this file gives the game input or looks at the screen (tests put recorders here) ----
;QS-INPUT-BEGIN
;The mouse onto x, y and a moment on it - the game takes a hovered click better (the potion run's rule). Your mouse
;locked meanwhile (Settings.ahk MouseLockOn; your clicks swallowed once the pointer's on the game - MouseLockMoved) and
;let go after the hover - each of these holds and gives back its own (no hold left whatever QsClickAt does next)
QsInputMove(x, y)
	{
	MouseLockOn("quicksell")
	MouseMove(x, y, MouseSpeedNow())
	MouseLockMoved()
	Sleep(V1N(V1Max(150, Stats.Has("clickwait") ? Stats["clickwait"] : 40)))  ; (v1: a clickwait that isn't a number - Max blank, Sleep 0)
	MouseLockOff("quicksell")
	}

;The mouse still at x, y (2 px either way)
QsInputMouseAt(x, y)
	{
	MouseGetPos(&qmX, &qmY)
	return Abs(qmX - x) <= 2 && Abs(qmY - y) <= 2
	}

;The click itself - at x, y, never wherever the mouse happens to be; your mouse locked for it (the bot's own click
;goes through - the lock's hotkeys never take the script's own input: the include-Crowns No, SELL...)
QsInputClickAt(x, y)
	{
	MouseLockOn("quicksell")
	Click(x, y)
	MouseLockOff("quicksell")
	}

;B - your mouse locked for it too
QsInputKeyB()
	{
	MouseLockOn("quicksell")
	Send("{Blind}b")
	MouseLockOff("quicksell")
	}

QsBattlePic()
	{
	V1ImageSearch(&qbX, &qbY, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundstart.png"))
	return ErrorLevel = 0
	}

QsOcr(x, y, w, h, scale, mode)
	{
	return OcrRect(x, y, w, h, "en", scale, &qoLines, mode)
	}

QsTray(text, icon := 1)
	{
	TrayTip(text, "Wizard101 bot", icon)
	}

QsSnap(step)
	{
	if (V1IsFunc("LogMirrorSnap"))
		LogMirrorSnap.Call(0, "quicksell")
	}

QsActivateGame()
	{
	global ErrorLevel ; (v1 globals it sets)
	V1Try(WinActivate, GameWT())  ; (v1: no window - nothing; v2 throws)
	ErrorLevel := !WinWaitActive(GameWT(), , 2)
	Sleep(800)
	}
;QS-INPUT-END

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
QuickSellBlank()
	{
	global QsBusy := "", QsBattleEndAt := "", QsLooks := "", QsTryAt := "", QsFails := "", QsBlocked := "", QsLookAt := "", QsStill := ""
	global QsSetWas := "", QsGid := "", QsSaidAt := "", QsMemSaid := "", QsLeftover := "", QsLeftoverTries := "", QsLeftoverAt := "", QsSince := ""
	global QsManual := "", QsStep := "", QsLogPos := "", QsLogHead := "", QsLogEvents := "", QsBefore := "", QsLastBag := "", QsBackKind := ""
	global QsDgZones := "", QsDgOut := ""
	}
