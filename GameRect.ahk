; GameRect.ahk - where Wizard101 draws on the screen: GameClientRect. AutoHotkey v2, a function only; #Included by
; AutoFarmer\Autofarmer.ahk (UpdateGameRect), AutoFarmer\StatsReader.ahk and AutoQuester\AutoQuester.ahk (UpdateGameRect).

;The size last said in the log (unset or "": none yet - an #Included file's top lines aren't run, so no initializer here) -
;Autofarmer empties it once its debug.log is started, so a window still too big at the start is said in that run's own log
global GameRectSaid

;The part of the game's client area that Wizard101 draws (x, y its top left on screen, w, h): the client area - but a
;full-screen one (no title bar) that starts at its screen's top left and is bigger than that screen only on that screen.
;2026-11-21 16:18: Wizard101's Resolution setting was 1920x1200 (from a remote desktop session at that size) and the
;screen 1920x1080 - the game asked for 1920x1200, "Failed to find requested mode", fell back to 1920x1080 (its own
;WizardClient.log) and drew that (its GUI root 1827x1027 units, the game's memory), its window staying 1920x1200 with the
;bottom 120 px off the screen. The window's middle was 60 px below the game's, the hand looked for there and never found -
;every round passed. Said in the log once per window size (GameRectSaid). False: no client area (minimized or no window)
GameClientRect(hwnd, &x, &y, &w, &h)
	{
	global GameRectSaid
	rc := Buffer(16, 0), pt := Buffer(8, 0)
	if (!hwnd || !DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc, "Int") || !DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt, "Int"))
		return false
	x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int"), w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")
	if (w <= 0 || h <= 0)
		return false
	;(WS_CAPTION: a window with a title bar is the game windowed - the game draws all of it, on the screen or not)
	if ((DllCall("GetWindowLong", "Ptr", hwnd, "Int", -16, "Int") & 0xC00000) = 0xC00000)
		return true
	mi := Buffer(40, 0), NumPut("UInt", 40, mi, 0)
	mon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")   ; (MONITOR_DEFAULTTONEAREST)
	if (!mon || !DllCall("GetMonitorInfo", "Ptr", mon, "Ptr", mi, "Int"))
		return true
	mL := NumGet(mi, 4, "Int"), mT := NumGet(mi, 8, "Int"), mR := NumGet(mi, 12, "Int"), mB := NumGet(mi, 16, "Int")
	if (x != mL || y != mT || (w <= mR - mL && h <= mB - mT))
		return true
	gcSize := w "x" h " on " (mR - mL) "x" (mB - mT)
	w := Min(w, mR - mL), h := Min(h, mB - mT)
	if (!IsSet(GameRectSaid) || gcSize != GameRectSaid)
		{
		GameRectSaid := gcSize
		if (V1IsFunc("DebugLog"))
			{
			local gcKeep := V1Thread()  ; (the log line sets ErrorLevel - the caller's kept)
			%"DebugLog"%("Game window: full screen at " gcSize " - bigger than its screen: the game draws the part on the screen, " w "x" h ", and that's where it's looked at (Wizard101's Resolution setting is bigger than this screen offers - it falls back to the screen's; its options' Resolution set to " w "x" h " makes the window fit)")
			}
		}
	return true
	}
