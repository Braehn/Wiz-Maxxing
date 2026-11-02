; MouseSteer.ahk - turning the wizard with the mouse while it walks: the right button held and the mouse slid left or
; right turns the wizard itself while W runs (you checked it, 2026-10-23), at once - no 400-unit arc as with A/D (the
; wizard walks ~1000 units a second and A/D turns ~145 degrees a second). AHK v1.1; #Included at the end of Walker.ahk.
;
; Only while walking (W held), steering by the game's memory (it reads the facing back as it turns: the turn is closed
; loop, and how far a mouse count turns the wizard is measured on the first turn - MsK), out of battle, Wizard101 in
; front, you away from the keyboard and mouse (3 s - its own moves don't count; you touching anything mid-turn ends it,
; the mouse left to you), above 5x the game at 1x for the turn (as A/D's), no window open over the middle of the game (a
; window's words there: Crowns, shop, buy, quest... - not the bot's own windows' - and the game itself under the point
; the button's pressed at). The right button is pressed at a point in the middle of the scene, the mouse slid, the button
; let go; the mouse back where it was. A right click that doesn't drag opens nothing (you checked it). Anything not sure:
; A/D as before (turns on the spot always A/D) - and why, in debug.log (MouseSteerNote). Setting: mousesteer (on unless
; 0). In AutoFarmer your mouse is locked for the turn (mouselock - Settings.ahk MouseLockOn): what it swallows doesn't end
; the turn, your keys still do.

;How far one mouse count turns the wizard (degrees, its sign the way it turns - "" not measured yet) and the WkNavSign it
;was measured under, off till (tick), probes that found no turn, the right button held by the bot, the window check
;(when, its answer, why), what was last said and when, the radius sent with the last route ask and whether it was the
;mouse's
global MsK, MsKSign, MsOffUntil, MsFails, MsHeld, MsWinAt, MsWinOk, MsWinWhy, MsSaid, MsSaidAt, WkArcSentR, WkArcMouse
;Measured mouse turns that didn't turn the wizard, in a row (two: the count's worth measured again - one alone is
;likely the moment's: a battle pulling him round, a window)
global MsMiss
;When a mouse turn last missed (it isn't tried again at once by another way round - Turn, BackUp, DgTurn); one that
;worked doesn't count
global MsTriedAt
;Turns from standing by the mouse that didn't turn the wizard, in a row, and till when they aren't tried (two: 10 minutes)
global MsStandMiss, MsStandOff
;How far the last turn from standing that missed did turn him (degrees, + right; "" none, not read, or it didn't miss) - the
;callers turn the rest, not the whole turn again on top (2026-10-25 11:42:26: 158 wanted, -168 by the mouse, then 158 by A/D)
global MsStandGot
;Why the last facing read failed (NavWhy then - MouseSteerYaw puts the walker's back), the right button pressed as a raw
;mouse_event for the rest of the run (1: the bot's own press didn't reach the game and that one turned him - MouseTurn,
;MouseSteerButton), and the last measuring miss in words: which half failed (MouseSteerGaveUp)
global MsYawWhy, MsRaw, MsMissWhy

;The setting (mousesteer, on unless 0) and the game's memory there to read the facing by
MouseSteerOn()
	{
	;(Stats: AutoFarmer's settings - blank in AutoQuester, as in v1)
	return V1IsFunc("NavRead") && !(IsObject(Stats) && Stats.Has("mousesteer") && !Stats["mousesteer"])
	}

;Whether a mouse turn may go now: why not ("" it may). needW: W held already (false: about to be). byMem false: a
;dungeon run, following the party's leader or walking to a quest item (AutoFarmer DgSteer) - steering by the game's
;memory, not the walker's arrow, and not at the walker's goal. slows: above 5x the turn drops the game to 1x first
;(MouseTurn, MouseStandTurn - as Turn's A/D): the speed no reason then; false where it can't - a turn walking on whose
;arc was looked at for the speed now (WalkStep's msWalk)
MouseSteerWhyNot(needW := true, byMem := true, slows := false)
	{
	if (!MouseSteerOn())
		return V1IsFunc("NavRead") ? "off (Settings: Turn with the mouse while walking)" : "off (no game memory read here)"
	if (MsOffUntil && A_TickCount < MsOffUntil)
		return "off for now (the mouse didn't turn the wizard)"
	if (!Walking || (needW && !HeldW) || inbattle)
		return "not walking"
	;(the wizard running already - the right button turns him while he runs; standing, it turns the camera)
	if (needW && WkWalkFrom && A_TickCount - WkWalkFrom < 600)
		return "just set off"
	if (!GameActive())
		return "Wizard101 not in front"
	if (byMem && (!WkNavUse || !WkNavOk))
		return "not steering by the game's memory"
	if (SpeedNow > 5 && !slows)
		return "sped up over 5x"
	if (byMem && WkArrived != 0 && WkArrived != 3 && WkArrived != 7)
		return "at the goal"
	if (PlayerActive || UserIdle() < 3000)
		return "you're at the keyboard or mouse"
	if (GetKeyState("RButton", "P") || GetKeyState("LButton", "P") || GetKeyState("Shift", "P") || GetKeyState("Ctrl", "P")
		|| GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
		return "a key or button of yours is down"
	if (!MouseSteerWindowClear())
		return MsWinWhy
	return ""
	}

;No window over the middle of the game - a shop, a quest offer, a Crown one: the game itself under the point the button's
;pressed at (not another program's window or one of the bot's own - its notice, the party window: the press would go to
;it), and none of a window's words where it's pressed (an OCR of the middle - a close-button search over the whole game
;takes seconds) - but for the words inside the bot's own windows over the game, which aren't the game's (nothing hidden
;for it: no flicker, and you still see them). Looked at once in 2.5 s - and afresh after the walker presses a key or
;clicks (PressKey, WalkClick: MsWinAt := 0)
MouseSteerWindowClear()
	{
	global MsWinOk, MsWinWhy, MsWinAt ; (v1 globals it sets)
	if (MsWinAt && A_TickCount - MsWinAt < 2500)
		return MsWinOk
	MsWinOk := 0, MsWinWhy := ""
	;(what the press would land on - read only, nothing sent to it)
	MouseSteerPoint(&mwPx, &mwPy)
	mwWhat := ""
	mwTop := MouseSteerUnder(mwPx, mwPy, &mwWhat)
	if (!mwTop || mwTop != GameActive())
		{
		MsWinWhy := "a window under the press point (" mwWhat " at " (mwPx - GameLeft) "," (mwPy - GameTop) " in the game)", MsWinAt := A_TickCount
		return 0
		}
	mwLines := ""  ; (v1: a ByRef output OcrRect may leave unset was blank)
	mwT := OcrRect(Round(GameLeft + GameW * 0.3), Round(GameTop + GameH * 0.15), Round(GameW * 0.4), Round(GameH * 0.3), "en", 1, &mwLines)
	if (ErrorLevel)
		{
		MsWinWhy := "the middle of the game couldn't be read", MsWinAt := A_TickCount
		return 0
		}
	mwRx := "i)cr[o0]wn|\bshop|\bbuy\b|\bsell\b|purchase|accept|decline|\bquest|reward|\btrade|upgrade|member|recipe|reagent|\bgold\b|friend|okay|\bok\b|cancel|confirm|\bclose\b"
	;(word by word, each by its own box: one inside a window of the bot's own over the game left out - where a word that
	;refuses is, said)
	mwOwn := MouseSteerOwnRects(), mwLeft := ""
	if (IsObject(mwLines))
		for mwI, mwL in mwLines
			{
			if (!IsObject(mwL.words))
				continue
			for mwJ, mwW in mwL.words
				{
				if (!RegExMatch(mwW.text, mwRx, &mwM))
					continue
				if (MouseSteerInRects(mwW.x + mwW.w // 2, mwW.y + mwW.h // 2, mwOwn))
					{
					mwLeft .= (mwLeft = "" ? "" : ", ") "`"" mwM[0] "`""
					continue
					}
				MsWinWhy := "a window over the game (`"" mwM[0] "`" at " (mwW.x - GameLeft) "," (mwW.y - GameTop) " in the game)", MsWinAt := A_TickCount
				return 0
				}
			}
	if (mwLeft != "")
		MouseSteerNote("a window of the bot's own over the middle of the game - its words left out (" mwLeft ")")
	;(no window of the bot's own there: the whole text too, as before - a line the OCR gave no word boxes)
	if (!mwOwn.Length && RegExMatch(mwT, mwRx, &mwM))
		{
		MsWinWhy := "a window over the game (`"" mwM[0] "`")", MsWinAt := A_TickCount
		return 0
		}
	MsWinOk := 1, MsWinAt := A_TickCount
	return 1
	}

;The window under screen point x, y: its top window (0 none) and, in what, the window in words - its class, program and
;title. Read only: nothing is sent to it
MouseSteerUnder(x, y, &what)
	{
	what := "no window"
	msHwnd := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
	if (!msHwnd)
		return 0
	;(GA_ROOT: a control's own window is its program's)
	msTop := DllCall("GetAncestor", "Ptr", msHwnd, "UInt", 2, "Ptr")
	msTop := msTop ? msTop : msHwnd
	msCls := "?", msExe := "?", msTitle := ""
	try msCls := WinGetClass("ahk_id " msTop)
	try msExe := WinGetProcessName("ahk_id " msTop)
	try msTitle := WinGetTitle("ahk_id " msTop)
	what := msCls " of " msExe (msTitle != "" ? " `"" SubStr(msTitle, 1, 60) "`"" : "")
	return msTop
	}

;The bot's own windows showing over the game now - its notice, the party window: any of this program's above Wizard101
;and not click-through (the overlay is - and the screen reading can't see it anyway): [[left, top, right, bottom], ...]
;on the screen. Read only: nothing hidden, moved or sent
MouseSteerOwnRects()
	{
	msOwn := [], msH := GameActive()
	if (!msH)
		return msOwn
	msPid := DllCall("GetCurrentProcessId", "UInt"), msRc := Buffer(16, 0)
	;(each window above the game's, the nearest first - GW_HWNDPREV)
	Loop 500
		{
		msH := DllCall("GetWindow", "Ptr", msH, "UInt", 3, "Ptr")
		if (!msH)
			break
		if (!DllCall("IsWindowVisible", "Ptr", msH) || DllCall("IsIconic", "Ptr", msH))
			continue
		msWin := 0
		DllCall("GetWindowThreadProcessId", "Ptr", msH, "UInt*", &msWin)
		;(WS_EX_TRANSPARENT 0x20: click-through)
		if (msWin != msPid || (DllCall("GetWindowLong", "Ptr", msH, "Int", -20, "Int") & 0x20))
			continue
		if (DllCall("GetWindowRect", "Ptr", msH, "Ptr", msRc))
			msOwn.Push([NumGet(msRc, 0, "Int"), NumGet(msRc, 4, "Int"), NumGet(msRc, 8, "Int"), NumGet(msRc, 12, "Int")])
		}
	return msOwn
	}

;Whether screen point x, y is inside one of rects ([[left, top, right, bottom], ...])
MouseSteerInRects(x, y, rects)
	{
	for msI, msR in rects
		if (x >= msR[1] && x < msR[3] && y >= msR[2] && y < msR[4])
			return true
	return false
	}

;Where the right button's pressed: the middle of the scene, a little high - not the hand, the arrow, the prompt or any
;corner's buttons
MouseSteerPoint(&x, &y)
	{
	x := Round(GameLeft + GameW * 0.5), y := Round(GameTop + GameH * 0.3)
	}

;The wizard's facing now off the game's memory (radians, "" not read - why in MsYawWhy) - a short ask without the route;
;a miss doesn't put the walker's own reads off (NavRead's wait after one is put back)
MouseSteerYaw()
	{
	global NavWait, NavWaitUntil, NavWhy, MsYawWhy ; (v1 globals it sets)
	mwWait := NavWait, mwUntil := NavWaitUntil, mwWhy := NavWhy
	nav := %"NavRead"%.Call(120)
	;(not read: why - NavRead's NavWhy, before the walker's is put back; no ask at all while its reads wait after a miss)
	MsYawWhy := IsObject(nav) ? (nav.yaw = "" ? "no facing in its answer" : "")
		: (NavWhy != "" ? NavWhy : "no answer") (V1Lt(A_TickCount, mwUntil) ? " - its reads wait a moment after a miss" : "")
	NavWait := mwWait, NavWaitUntil := mwUntil, NavWhy := mwWhy
	return (IsObject(nav) && nav.yaw != "") ? nav.yaw : ""
	}

;The mouse slid c counts sideways (+ right), in steps of at most 8, 2 ms apart - as a mouse sends them (Windows' pointer
;speed works on each step). With the right button held the game hides the cursor and puts it back where it was pressed
;every 25-40 ms, turning by how far it went meanwhile (watched 2026-10-23 on a drag of yours)
MouseSteerMove(c)
	{
	left := c
	DllCall("winmm\timeBeginPeriod", "UInt", 1)
	while (left != 0)
		{
		d := left > 8 ? 8 : left < -8 ? -8 : left
		DllCall("mouse_event", "UInt", 0x0001, "Int", d, "Int", 0, "UInt", 0, "UPtr", 0)
		left -= d
		if (left != 0)
			DllCall("Sleep", "UInt", 2)
		}
	DllCall("winmm\timeEndPeriod", "UInt", 1)
	}

;The right button down (1) or up (0) where the mouse is - sent by AutoHotkey itself (the same mouse_event the game sees,
;marked as the script's own): AutoFarmer's mouse lock swallows your right button with a hotkey, and a raw mouse_event
;call would look like yours to it (Settings.ahk MouseLockKeys). MsRaw (that press didn't reach the game, a raw one turned
;him - MouseTurn): a raw mouse_event, the lock's right-button hotkey off while it's down (Settings.ahk MouseLockRightFree -
;the rest of the lock as it was). Let go the way it was pressed (MsHeld 2: raw)
MouseSteerButton(down)
	{
	global MsHeld ; (v1 globals it sets)
	if (down ? MsRaw : (MsHeld = 2))
		{
		if (down && V1IsFunc("MouseLockRightFree"))
			%"MouseLockRightFree"%.Call(1)
		DllCall("mouse_event", "UInt", down ? 0x0008 : 0x0010, "Int", 0, "Int", 0, "UInt", 0, "UPtr", 0)
		if (!down && V1IsFunc("MouseLockRightFree"))
			%"MouseLockRightFree"%.Call(0)
		MsHeld := down ? 2 : 0
		return
		}
	Send("{Blind}{RButton " (down ? "down" : "up") "}")
	MsHeld := down ? 1 : 0
	}

;How far the wizard turned since yaw0 (degrees, positive to the right - as Turn's h)
MouseSteerTurned(yaw, yaw0)
	{
	return WkNavSign * ArrowWrap((yaw - yaw0) * 57.29578)
	}

;You touched the keyboard or mouse since from (the bot's own input doesn't count: the hooks), or Wizard101 isn't in front
MouseSteerYours(from)
	{
	return UserIdle() < A_TickCount - from || !GameActive()
	}

;Where the cursor is and whether it shows: "x,y shown" / "x,y hidden" (screen), "?" not known
MouseSteerCursor()
	{
	ci := Buffer(16 + A_PtrSize, 0), NumPut("UInt", 16 + A_PtrSize, ci, 0)
	if (!DllCall("GetCursorInfo", "Ptr", ci.Ptr))
		return "?"
	return NumGet(ci, 8 + A_PtrSize, "Int") "," NumGet(ci, 12 + A_PtrSize, "Int") (NumGet(ci, 4, "UInt") & 1 ? " shown" : " hidden")
	}

;Said in debug.log at most once a minute for the same thing - each thing its own minute (two reasons taking turns aren't
;said every time; what's said is kept for a minute: at most 50 things, then all forgotten). Where a window or word was
;seen (" at x,y in the game") isn't part of the thing: one moving about the scene is said once a minute, not at each look
MouseSteerNote(what)
	{
	static msNoted := Map()
	global MsSaid, MsSaidAt ; (v1 globals it sets)
	msKey := RegExReplace(what, " at -?\d+,-?\d+ in the game", "")
	if (msNoted.Has(msKey) && A_TickCount - msNoted[msKey] < 60000)
		return
	if (msNoted.Count >= 50)
		msNoted.Clear()
	msNoted[msKey] := A_TickCount, MsSaid := what, MsSaidAt := A_TickCount
	WalkLog("mouse steering: " what)
	}

;Turn the wizard h degrees (+ right) walking on, by the mouse: how far it turned ("" not done - A/D then). The first
;turn measures how far a count turns it (a few counts more each look till it turns 3 degrees - MouseSteerProbe); each
;turn after goes in up to 5 looks, to within 4 degrees (45 degrees' worth in the first, 90 after). A look turning it the
;wrong way: undone, and measured again next time; measured, but not turning him now (a window, the game's menu): A/D,
;which notices and deals with it, and measured again next time; no turn after 168 counts - or the facing not read on the
;way - three times: off for 10 minutes (said where you see it: MouseSteerGaveUp); a measuring try that missed: the next
;one 10 s after it at the soonest. Above 5x: the game to 1x for it first (as Turn). You touching anything meanwhile: the
;turn ends there, the mouse left where you have it. Each way it doesn't turn him is said in debug.log (MouseSteerNote)
MouseTurn(h, byMem := true)
	{
	global MsK, MsKSign, MsFails, MsOffUntil, MsTriedAt, MsMiss, WkTurnAt, MsRaw, MsMissWhy ; (v1 globals it sets)
	;(the memory's heading turned round since the count was measured: so is the count)
	if (MsK != "" && MsKSign != WkNavSign)
		MsK := -MsK, MsKSign := WkNavSign
	why := MouseSteerWhyNot(true, byMem, true)
	if (why != "")
		{
		MouseSteerNote("not now - " why)
		return ""
		}
	;(a measuring try that missed: the next one 10 s after it at the soonest - three misses within seconds would leave the
	;mouse alone for 10 minutes, and one whose facing read failed would come again at every small correction)
	if (MsK = "" && MsTriedAt && A_TickCount - MsTriedAt < 10000)
		{
		MouseSteerNote("not now - the last try missed (the next one 10 s after it)")
		return ""
		}
	;(sped up over 5x: the turn at 1x, as Turn's A/D - the walking speed back after it, SpeedWalking)
	if (SpeedNow > 5)
		SpeedSet(0, "a mouse turn")
	yaw0 := MouseSteerYaw()
	if (yaw0 = "")
		{
		MouseSteerNote("the facing couldn't be read (" MsYawWhy ") - A/D")
		return ""
		}
	wasCrit := A_IsCritical
	Critical()
	;(the window and the read let other threads run: F6, F8, you - looked at again before anything's pressed)
	if (!Walking || !HeldW || inbattle || !GameActive() || PlayerActive || UserIdle() < 3000)
		{
		if (!wasCrit)
			Critical("Off")
		MouseSteerNote("not now - " ((!Walking || !HeldW || inbattle) ? "not walking" : !GameActive() ? "Wizard101 not in front" : "you're at the keyboard or mouse") " (just before the press)")
		return ""
		}
	MouseGetPos(&msX0, &msY0)
	MouseSteerPoint(&msPx, &msPy)
	;(your mouse locked till it's back where it was, in AutoFarmer - Settings.ahk MouseLockOn; your keys still end the turn)
	if (V1IsFunc("MouseLockOn"))
		%"MouseLockOn"%.Call("turn")
	MouseMove(msPx, msPy, 0)
	;(your clicks swallowed too now the pointer's on the game - Settings.ahk MouseLockMoved: no tick runs in this Critical)
	if (V1IsFunc("MouseLockMoved"))
		%"MouseLockMoved"%.Call()
	sent := 0, turned := 0, probed := false, msUser := false, msFrom := A_TickCount, msY := "", msRetry := false, msGaveUp := false
	try
		{
		MouseSteerButton(1)
		Sleep(60)
		;(where the cursor is and whether it shows, before the slide and after: the game hiding it or putting it back
		;says it took the drag - for debug.log when the mouse doesn't turn him)
		msCur0 := MouseSteerCursor()
		;(how far a count turns it, not known: measured - MouseSteerProbe)
		if (MsK = "")
			{
			probed := true
			MouseSteerProbe(h, yaw0, msFrom, &sent, &turned, &msY, &msUser)
			msCur1 := MouseSteerCursor()
			;(the cursor shown before the slide and after - the game never took the drag: the press didn't reach it. Which
			;window is under the press point - once a run - and the try once more with the button pressed by a raw
			;mouse_event, the mouse lock's right-button hotkey off for it (MouseSteerButton): pressed so for the rest of
			;the run if that turns him)
			if (MsK = "" && msY != "" && !msUser && !MsRaw && InStr(msCur0, "shown") && InStr(msCur1, "shown"))
				{
				MouseSteerUnderSay(msPx, msPy, msCur0, msCur1)
				msRetry := true
				MouseSteerButton(0)
				Sleep(20)
				MouseMove(msPx, msPy, 0)
				if (V1IsFunc("MouseLockMoved"))
					%"MouseLockMoved"%.Call()
				MsRaw := 1
				MouseSteerButton(1)
				Sleep(60)
				msCur0 := MouseSteerCursor()
				;(from where he faces now - the first try turned him under 3 degrees - and its counts not his)
				yaw0 := msY, sent := 0, turned := 0
				MouseSteerProbe(h, yaw0, msFrom, &sent, &turned, &msY, &msUser)
				msCur1 := MouseSteerCursor()
				if (MsK != "")
					MouseSteerNote("the right button pressed as a raw mouse_event turned the wizard - pressed that way for the rest of the run")
				else
					MsRaw := 0
				}
			;(no turn, or the facing not read on the way - a miss either way: three, and the mouse is left alone for 10
			;minutes. Which half failed, for that: the cursor shown before the slide and after - the drag never reached
			;the game; hidden - the game took it but didn't turn him)
			if (MsK = "" && !msUser)
				{
				MsFails := (MsFails ? MsFails : 0) + 1
				MsMissWhy := msY = "" ? "the wizard's facing couldn't be read from the game's memory mid-turn (" MsYawWhy ")"
					: (InStr(msCur0, "shown") && InStr(msCur1, "shown")) ? "the game didn't take the right-button drag"
					: (InStr(msCur0, "hidden") || InStr(msCur1, "hidden")) ? "the game took the drag but the wizard didn't turn"
					: "the mouse didn't turn the wizard"
				if (msY = "")
					MouseSteerNote("the facing couldn't be read mid-turn (" MsYawWhy "; " Abs(sent) " counts sent) - A/D" (MsFails >= 3 ? ", and the mouse left alone for 10 minutes" : ""))
				else
					MouseSteerNote("the mouse didn't turn the wizard (" Abs(sent) " counts, " Round(turned, 1) " degrees; the cursor " msCur0 " before the slide, " msCur1 " after" (msRetry ? "; pressed as a raw mouse_event too" : "") ") - A/D" (MsFails >= 3 ? ", and the mouse left alone for 10 minutes" : ""))
				if (MsFails >= 3)
					MsFails := 0, MsOffUntil := A_TickCount + 600000, msGaveUp := true
				}
			}
		if (MsK != "" && !msUser)
			Loop 5
				{
				if (MouseSteerYours(msFrom))
					{
					msUser := true
					break
					}
				err := h - turned
				if (Abs(err) <= 4)
					break
				;(45 degrees' worth at most in the first look, 90 after: a count's worth measured wrong can't swing him far)
				;(and never more than a third of the game's width at once: should the game read where the cursor is, it
				;doesn't run off the screen)
				most := Min(Round((A_Index = 1 ? 45 : 90) / Abs(MsK)), Round(GameW * 0.3))
				msC := Round(err / MsK)
				msC := msC > most ? most : msC < -most ? -most : msC
				if (msC = 0)
					break
				MouseSteerMove(msC), sent += msC
				Sleep(35)
				msY := MouseSteerYaw()
				if (MouseSteerYours(msFrom))
					{
					if (msY != "")
						turned := MouseSteerTurned(msY, yaw0)
					msUser := true
					break
					}
				;(not read: taken as turned as far as the counts should have - said)
				if (msY = "")
					{
					MouseSteerNote("the facing couldn't be read mid-turn (" MsYawWhy ") - taken as turned as far as the counts should have")
					turned += msC * MsK
					break
					}
				;(summed look by look - this look's own turn, wrapped - so a turn past 180 isn't read as one the other way)
				got := ArrowWrap(MouseSteerTurned(msY, yaw0) - turned), now := turned + got
				want := msC * MsK
				;(turned the wrong way: measured again next time - the camera snapped, a battle pulled him round)
				if (want * got < 0 && Abs(got) >= 3)
					{
					MouseSteerNote("a look turned the wizard the wrong way (" Round(got) " degrees, " Round(want) " wanted) - undone, measured again next turn")
					MouseSteerMove(-msC), sent -= msC
					MsK := ""
					break
					}
				;(10 degrees' worth sent and nothing turned: the mouse isn't turning him now - no more counts after it)
				if (Abs(want) >= 10 && Abs(got) < 1)
					{
					turned := now
					break
					}
				;(the count's worth refined as it goes - a fifth each look)
				if (Abs(got) >= 2 && Abs(want) >= 2)
					MsK := MsK * 0.8 + (got / msC) * 0.2
				turned := now
				}
		}
	finally
		{
		MouseSteerButton(0)
		Sleep(20)
		;(the mouse back where it was - not if you've taken it meanwhile)
		if (!MouseSteerYours(msFrom))
			MouseMove(msX0, msY0, 0)
		if (V1IsFunc("MouseLockOff"))
			%"MouseLockOff"%.Call("turn")
		if (!wasCrit)
			Critical("Off")
		}
	;(the mouse left alone for 10 minutes: said where you see it - out of the Critical)
	if (msGaveUp)
		MouseSteerGaveUp()
	;(you took over: what it got to - not "", or the walker would turn him with A/D against you)
	if (msUser)
		{
		MouseSteerNote("you took the keyboard or mouse mid-turn (or Wizard101 went behind) - the turn left there, the mouse yours")
		return turned
		}
	;(nothing sent, or the measuring found no turn - not read, or none: A/D does this one)
	if (!sent || (probed && MsK = ""))
		{
		if (!sent && MsK != "")
			MouseSteerNote("too small a turn for a mouse count - A/D")
		;(a look that turned him the wrong way, undone - said above, MsK blank: measured again at the next turn half a
		;second on, not the 10 s a measuring try that missed waits)
		MsTriedAt := A_TickCount - ((!probed && MsK = "") ? 9500 : 0)
		return ""
		}
	;(measured before, and the mouse doesn't turn him now - a window, the game's menu: A/D, which notices and deals with
	;it; measured again next time - three of those with no turn switch the mouse off)
	if (!probed && Abs(h) > 6 && Abs(turned) < 2)
		{
		;(once: likely the moment's - a battle pulling him round, a window - the mouse again next turn; twice in a row:
		;measured again. The keyboard only for this turn either way - 2026-10-24: the mouse is the steadier)
		MsMiss := (MsMiss ? MsMiss : 0) + 1
		MouseSteerNote("the mouse didn't turn the wizard (" Abs(sent) " counts) - A/D this once" (MsMiss >= 2 ? ", measured again next time" : ""))
		if (MsMiss >= 2)
			MsK := "", MsMiss := 0
		MsTriedAt := A_TickCount
		return ""
		}
	MsMiss := 0
	if (IsObject(WkMet))
		WkMet.mturns := (WkMet.mturns ? WkMet.mturns : 0) + 1
	if (Abs(turned) >= 15)
		WkTurnAt := A_TickCount
	return turned
	}

;A measuring look (MouseTurn, no count's worth known yet - the right button down already): a few counts at a time, more
;each look, the way it should turn - mouse right taken to turn it right - till it's seen to turn 3 degrees: the count's
;worth measured (MsK). sent, turned: the counts sent and how far he turned since yaw0 (added to); msY: the last facing read
;("" not read - the look stops there); user: you touched something meanwhile (the look stops there too)
MouseSteerProbe(h, yaw0, from, &sent, &turned, &msY, &user)
	{
	global MsK, MsKSign, MsFails ; (v1 globals it sets)
	for msI, msC in [8, 24, 64, 72]
		{
		msC := h > 0 ? msC : -msC
		MouseSteerMove(msC), sent += msC
		Sleep(40)
		msY := MouseSteerYaw()
		if (MouseSteerYours(from))
			{
			if (msY != "")
				turned := MouseSteerTurned(msY, yaw0)
			user := true
			break
			}
		if (msY = "")
			break
		turned := MouseSteerTurned(msY, yaw0)
		if (Abs(turned) >= 3)
			{
			MsK := turned / sent, MsKSign := WkNavSign, MsFails := 0
			MouseSteerNote("a mouse count turns the wizard " Round(Abs(MsK), 3) " degrees (" (MsK > 0 ? "" : "the other way - ") "measured: " Round(Abs(turned)) " degrees for " Abs(sent) " counts" (MsRaw ? ", the right button pressed as a raw mouse_event" : "") ")")
			break
			}
		}
	}

;Said once a run, before the raw press is tried (MouseTurn): the cursor showed through a measuring try, before the slide
;and after - the right-button drag never reached the game - and which window is under the press point x, y (read only)
MouseSteerUnderSay(x, y, cur0, cur1)
	{
	static msUnderSaid := 0
	if (msUnderSaid)
		return
	msUnderSaid := 1
	msWhat := ""
	MouseSteerUnder(x, y, &msWhat)
	WalkLog("mouse steering: the cursor showed through the slide (" cur0 " before, " cur1 " after) - the right-button drag didn't reach the game. Under the press point (" x "," y "): " msWhat " - trying the press again as a raw mouse_event, the mouse lock's right-button hotkey off for it (said once a run)")
	}

;The mouse left alone for 10 minutes (three measuring tries missed - MouseTurn): said where you see it - the walker's
;status each time (its next step's status soon over it, but SetStatus puts it in debug.log and the Dashboard's log);
;once a run a tray tip and a line in debug.log - which half failed (MsMissWhy: off the cursor shown or hidden through
;the slide, or the facing not read) and what to try
MouseSteerGaveUp()
	{
	static msTold := 0
	msTry := InStr(MsMissWhy, "facing couldn't be read") ? "if it keeps happening, send debug.log's 'mouse steering:' and 'the game's memory' lines"
		: "check your wizard turns when you right-drag yourself" (V1IsFunc("MouseLockOn") ? "; or untick Settings > Lock my mouse while the bot uses it for one run" : "")
	SetStatus("mouse steering off for 10 minutes - " MsMissWhy " (A/D meanwhile)")
	if (msTold)
		return
	msTold := 1
	WalkLog("mouse steering: off for 10 minutes - " MsMissWhy " (A/D meanwhile). What to try: " msTry " (said once a run)")
	TrayTip(SubStr("Turning with the mouse is off for 10 minutes: " MsMissWhy ". " StrUpper(SubStr(msTry, 1, 1)) SubStr(msTry, 2) ".", 1, 250), "Wizard101 bot", 2)
	}

;A turn from standing by the mouse (2026-10-24: the keyboard only when the mouse fails): the right button held, the
;camera turned h degrees' worth of counts (the right button turns only the camera while he stands), then W tapped with
;the button still down - the wizard faces where the camera does (a step that way). Checked by the game's memory: within
;25 degrees of h - else "" (A/D then). He's left standing, as a turn on the spot leaves him. Only once a count's worth
;is measured. Two misses in a row: not tried for 10 minutes (said in the log). Above 5x: the game to 1x for it first (as
;Turn). Each way it doesn't turn him is said in debug.log (MouseSteerNote)
MouseStandTurn(h)
	{
	global MsStandGot, MsK, MsKSign, MsTriedAt, KeysDown, HeldW, WkWalkFrom, MsStandMiss, WkTurnAt, MsStandOff ; (v1 globals it sets)
	MsStandGot := ""
	;(the memory's heading turned round since the count was measured: so is the count - as MouseTurn)
	if (MsK != "" && MsKSign != WkNavSign)
		MsK := -MsK, MsKSign := WkNavSign
	why := ""
	;(switched off, or left alone for 10 minutes: that said, not the count's worth it left unmeasured)
	if (!MouseSteerOn() || (MsOffUntil && A_TickCount < MsOffUntil))
		why := MouseSteerWhyNot(false, false, true)
	else if (MsK = "")
		why := "a mouse count's worth not measured yet (a turn walking on measures it)"
	else if (Abs(h) < 3)
		why := "a turn under 3 degrees"
	else if (MsStandOff && A_TickCount < MsStandOff)
		why := "off for now (two turns from standing missed)"
	else if (MsTriedAt && A_TickCount - MsTriedAt < 500)
		why := "a mouse turn missed a moment ago"
	;(the heading's sign not checked yet: a mouse turn can't tell it turned the wrong way - A/D's check does)
	else if (!WkNavTrusted && !WkNavChecked)
		why := "the game's memory's heading not checked yet"
	;(the W tap is a step: not with a mob's reach or sight ahead - on the spot by A/D instead)
	else if (IsObject(WkNavObj) && WkNavObj.blindahead != "" && IsObject(WkNavPrev) && A_TickCount - WkNavPrev.at < 1500)
		why := WkNavObj.blindahead "'s reach or sight ahead (the W tap is a step)"
	else
		why := MouseSteerWhyNot(false, false, true)
	if (why != "")
		{
		MouseSteerNote("not now (from standing) - " why)
		return ""
		}
	;(sped up over 5x: the turn at 1x, as Turn's A/D)
	if (SpeedNow > 5)
		SpeedSet(0, "a mouse turn")
	yaw0 := MouseSteerYaw()
	if (yaw0 = "")
		{
		MouseSteerNote("the facing couldn't be read (" MsYawWhy ") - A/D from standing")
		return ""
		}
	MsTriedAt := A_TickCount
	wasCrit := A_IsCritical
	Critical()
	if (!Walking || inbattle || !GameActive() || PlayerActive || UserIdle() < 3000)
		{
		if (!wasCrit)
			Critical("Off")
		MouseSteerNote("not now (from standing) - " ((!Walking || inbattle) ? "not walking" : !GameActive() ? "Wizard101 not in front" : "you're at the keyboard or mouse") " (just before the press)")
		return ""
		}
	MouseGetPos(&msX0, &msY0)
	MouseSteerPoint(&msPx, &msPy)
	;(your mouse locked till it's back where it was, in AutoFarmer - Settings.ahk MouseLockOn)
	if (V1IsFunc("MouseLockOn"))
		%"MouseLockOn"%.Call("turn")
	MouseMove(msPx, msPy, 0)
	;(your clicks swallowed too now the pointer's on the game - Settings.ahk MouseLockMoved)
	if (V1IsFunc("MouseLockMoved"))
		%"MouseLockMoved"%.Call()
	yaw1 := ""
	try
		{
		MouseSteerButton(1)
		Sleep(60)
		;(the counts for h in looks of 90 degrees' worth at most, a third of the game's width at most each)
		want := Round(h / MsK), most := Min(Round(90 / Abs(MsK)), Round(GameW * 0.3))
		while (want != 0)
			{
			c := want > most ? most : want < -most ? -most : want
			MouseSteerMove(c), want -= c
			Sleep(35)
			}
		Sleep(40)
		;(W tapped here, inside the Critical - HoldW lets other threads in, with the button and W down - a short step at
		;any speed)
		KeysDown := 1
		Send("{Blind}{w down}")
		HeldW := 1, WkWalkFrom := A_TickCount
		Sleep(Max(40, Round(120 / (SpeedNow ? SpeedNow : 1))))
		Send("{Blind}{w up}")
		HeldW := 0
		Sleep(40)
		yaw1 := MouseSteerYaw()
		if (yaw1 = "")
			{
			Sleep(60)
			yaw1 := MouseSteerYaw()
			}
		}
	finally
		{
		MouseSteerButton(0)
		Sleep(20)
		if (!MouseSteerYours(A_TickCount - 1000))
			MouseMove(msX0, msY0, 0)
		if (V1IsFunc("MouseLockOff"))
			%"MouseLockOff"%.Call("turn")
		if (!wasCrit)
			Critical("Off")
		}
	turned := yaw1 != "" ? MouseSteerTurned(yaw1, yaw0) : ""
	;(off from h by the wrap - a turn of 180 reads -180 as often as 180)
	if (turned != "" && Abs(ArrowWrap(turned - h)) <= 25)
		{
		MsStandMiss := 0
		WkTurnAt := A_TickCount
		if (IsObject(WkMet))
			WkMet.mturns := (WkMet.mturns ? WkMet.mturns : 0) + 1
		return h + ArrowWrap(turned - h)
		}
	MsTriedAt := A_TickCount
	MsStandMiss := (MsStandMiss ? MsStandMiss : 0) + 1
	;(what it did turn him - the caller's A/D turns the rest: MsStandGot)
	MsStandGot := turned
	MouseSteerNote("a turn from standing by the mouse didn't turn the wizard (" Round(h) " wanted, " (turned = "" ? "not read: " MsYawWhy : Round(turned)) ") - A/D" (turned != "" && Abs(turned) >= 3 ? " for the rest" : "") (MsStandMiss >= 2 ? ", and not tried from standing for 10 minutes" : ""))
	if (MsStandMiss >= 2)
		MsStandMiss := 0, MsStandOff := A_TickCount + 600000
	return ""
	}

;Any turn by the mouse: running - MouseTurn; standing - MouseStandTurn (still standing after it). "" it couldn't
MouseTurnAny(h)
	{
	if (HeldW)
		return MouseTurn(h, false)
	return MouseStandTurn(h)
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
MouseSteerBlank()
	{
	global MsK := "", MsKSign := "", MsOffUntil := "", MsFails := "", MsHeld := "", MsWinAt := "", MsWinOk := "", MsWinWhy := "", MsSaid := ""
	global MsSaidAt := "", WkArcSentR := "", WkArcMouse := "", MsMiss := "", MsTriedAt := "", MsStandMiss := "", MsStandOff := "", MsStandGot := ""
	global MsYawWhy := "", MsRaw := "", MsMissWhy := ""
	}
