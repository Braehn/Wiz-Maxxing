#Requires AutoHotkey v2.0
#SingleInstance Force
; StreamView.ahk - "Wiz-Maxxing stream view": a window to share in Discord (or OBS) that shows Wizard101 with the bot's
; overlay (the map and the log) drawn over it, as you see it.
;
; Why it's needed: the overlay's windows are kept out of every screen capture (SetWindowDisplayAffinity
; WDA_EXCLUDEFROMCAPTURE - AutoFarmer\Overlay.ahk) so the bot never reads its own drawing as part of the game. Discord
; captures the screen the same way, so a stream never shows the overlay - and a copy of an excluded window comes out
; black (tried 2026-11-08: a DWM thumbnail of one reads 000000).
;
; What it does: this window is the game's size, placed right behind the game's window (you never see it, nor does the
; bot - it reads the screen, where the game is in front). In it, Windows itself (DWM thumbnails - nothing read or copied
; by this script) draws a live copy of the game's window and, over it, copies of the overlay's two pictures: the files
; the bot's helper writes for the overlay (%TEMP%\Wizard101 bot map\overlay-map.wzov, overlay-log.wzov - read here,
; never written) put into two see-through windows of this script's own, kept far off the screen (-20000) where nothing
; sees them but their copies here. A part is drawn while the bot's own overlay shows it (and while you're in another
; window, as it was when you left the game). Given the focus, it hands it straight back to the game; follows the game's
; window each 150 ms.
;
; Use: run it (with the bot running and the overlay on - Settings, THE OVERLAY), then in Discord share a window and
; pick "Wiz-Maxxing stream view". Its tray icon: Exit. Nothing in the bot changes; closing this changes nothing either.

global TITLE := "Wiz-Maxxing stream view"
global FRAMES := A_Temp "\Wizard101 bot map"
global STATS := A_ScriptDir "\AutoFarmer\PlayerStats.txt"
global View := "", Game := 0, GameThumb := 0, Parts := Map(), Op := 230, OpAt := 0, Last := ""

A_TrayMenu.Delete()
A_TrayMenu.Add("Wiz-Maxxing stream view - share this window in Discord", (*) => 0)
A_TrayMenu.Disable("1&")
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_IconTip := TITLE
OnExit(Cleanup)

; The window you share: an ordinary window with a title bar (Discord lists only those - a borderless never-activated one
; wasn't, 2026-11-08), in the taskbar (WS_EX_APPWINDOW 0x40000), its inside the game's size, its title bar above the
; screen; black where the game's copy isn't. Closing it ends this
View := Gui("-MinimizeBox -MaximizeBox -DPIScale +E0x40000", TITLE)
View.BackColor := "000000"
View.OnEvent("Close", (*) => ExitApp())
for part in ["map", "log"]
	Parts[part] := PartMake(part)
SetTimer(Tick, 150)
Tick()
return

; One overlay part's copy: a see-through window (layered, click-through, never activated: 0x08080020), a tool window
; (not in Alt+Tab or the taskbar), off the screen; its thumbnail in the view; the last frame drawn (seq) and if shown
PartMake(part)
	{
	g := Gui("-Caption +ToolWindow -DPIScale +E0x08080020", "Wiz-Maxxing stream view (" part ")")
	hdc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
	return {part: part, gui: g, hwnd: g.Hwnd, hdc: hdc, hbm: 0, bits: 0, w: 0, h: 0, x: 0, y: 0, seq: -1, thumb: 0,
		shown: 0, wasOn: 0, op: -1, put: 0, offY: part = "map" ? 0 : 2000}
	}

Tick()
	{
	global Game, GameThumb, Last
	try
		{
		g := WinExist("ahk_exe WizardGraphicalClient.exe")
		if (!g || DllCall("IsIconic", "Ptr", g))
			{
			if (Game)
				ViewHide()
			return
			}
		; (the game's inside on the screen)
		rc := Buffer(16, 0), DllCall("GetClientRect", "Ptr", g, "Ptr", rc)
		w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")
		pt := Buffer(8, 0), DllCall("ClientToScreen", "Ptr", g, "Ptr", pt)
		x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
		if (w < 50 || h < 50)
			return
		if (g != Game)
			{
			; (a new game window - the game restarted: the copies made again, the game's first, so the overlay's
			; are drawn over it)
			ThumbsDrop()
			Game := g
			}
		if (!View.Hwnd || !DllCall("IsWindowVisible", "Ptr", View.Hwnd))
			View.Show("x" x " y" y " w" w " h" h " NoActivate")
		; (given the focus - its taskbar button clicked, or Discord starting the share: back to the game, so the bot's
		; keys and your own go to it)
		if (WinActive("ahk_id " View.Hwnd))
			try WinActivate("ahk_id " g)
		; (right behind the game, its inside on the game's inside - the window round it from its frame
		; (AdjustWindowRectEx): 0x10 SWP_NOACTIVATE | 0x40 SWP_SHOWWINDOW)
		fr := Buffer(16, 0), NumPut("Int", w, fr, 8), NumPut("Int", h, fr, 12)
		DllCall("AdjustWindowRectEx", "Ptr", fr, "UInt", DllCall("GetWindowLong", "Ptr", View.Hwnd, "Int", -16, "UInt"), "Int", 0
			, "UInt", DllCall("GetWindowLong", "Ptr", View.Hwnd, "Int", -20, "UInt"))
		fl := NumGet(fr, 0, "Int"), ft := NumGet(fr, 4, "Int")
		DllCall("SetWindowPos", "Ptr", View.Hwnd, "Ptr", g, "Int", x + fl, "Int", y + ft, "Int", NumGet(fr, 8, "Int") - fl
			, "Int", NumGet(fr, 12, "Int") - ft, "UInt", 0x50, "Int")
		if (!GameThumb)
			GameThumb := ThumbMake(g)
		key := w "x" h
		if (key != Last)
			ThumbPlace(GameThumb, 0, 0, w, h, 255, true, true), Last := key
		OpRead()
		gameFront := WinActive("ahk_id " g)
		for part, p in Parts
			PartTick(p, gameFront)
		}
	catch as e
		{
		; (each different error once, in StreamView.log beside this script)
		static said := Map()
		msg := e.Message " (" e.What ", line " e.Line ")"
		if (!said.Has(msg))
			{
			said[msg] := 1
			try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", A_ScriptDir "\StreamView.log", "UTF-8")
			}
		}
	}

; A part: its newest frame put into its window, its thumbnail where the bot's overlay has it (the frame's x, y in the
; game's inside), shown while the bot's own overlay window for it is up - or, with the game not in front (you're in
; Discord, say), as it was when you left the game
PartTick(p, gameFront)
	{
	DetectHiddenWindows(true)
	real := WinExist("Wiz-Maxxing overlay (" p.part ") ahk_class AutoHotkeyGUI")
	DetectHiddenWindows(false)
	on := real && DllCall("IsWindowVisible", "Ptr", real)
	if (gameFront)
		p.wasOn := on
	else
		on := p.wasOn
	if (on)
		FrameLoad(p)
	if (on && p.put)
		{
		if (!p.thumb)
			p.thumb := ThumbMake(p.hwnd)
		ThumbPlace(p.thumb, p.x, p.y, p.x + p.w, p.y + p.h, 255, true, false)
		p.shown := 1
		}
	else if (p.shown)
		{
		ThumbPlace(p.thumb, 0, 0, 1, 1, 0, false, false)
		p.shown := 0
		}
	}

; The part's file, when it has a newer frame (its seq): checked, put into the window's 32-bit DIB, and the window drawn
; from it off the screen with the overlay's own solidity (UpdateLayeredWindow). A frame cut short (being written) waits
; for the next tick
FrameLoad(p)
	{
	path := FRAMES "\overlay-" p.part ".wzov"
	try f := FileOpen(path, "r")
	catch
		return
	if (!IsObject(f))
		return
	head := Buffer(32, 0)
	got := f.RawRead(head, 32)
	if (got < 32 || NumGet(head, 0, "UInt") != 0x564F5A57 || NumGet(head, 4, "UInt") != 1)
		return f.Close()
	w := NumGet(head, 8, "UInt"), h := NumGet(head, 12, "UInt"), stride := NumGet(head, 16, "UInt"), seq := NumGet(head, 20, "UInt")
	x := NumGet(head, 24, "Int"), y := NumGet(head, 28, "Int")
	if (seq = p.seq && Op = p.op)
		return f.Close()
	if (w < 1 || h < 1 || w > 8000 || h > 8000 || stride != w * 4)
		return f.Close()
	if (seq != p.seq)
		{
		px := Buffer(stride * h)
		got := f.RawRead(px, stride * h)
		f.Close()
		if (got < stride * h)
			return
		if (!p.hbm || w != p.w || h != p.h)
			{
			bi := Buffer(40, 0)
			NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
			NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
			bits := 0
			hbm := DllCall("gdi32\CreateDIBSection", "Ptr", p.hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
			if (!hbm || !bits)
				return
			DllCall("gdi32\SelectObject", "Ptr", p.hdc, "Ptr", hbm, "Ptr")
			if (p.hbm)
				DllCall("gdi32\DeleteObject", "Ptr", p.hbm)
			p.hbm := hbm, p.bits := bits, p.w := w, p.h := h
			}
		DllCall("gdi32\GdiFlush")
		DllCall("RtlMoveMemory", "Ptr", p.bits, "Ptr", px, "Ptr", w * h * 4)
		}
	else
		f.Close()
	p.x := x, p.y := y, p.seq := seq
	pt := Buffer(8, 0), NumPut("Int", -20000, pt, 0), NumPut("Int", p.offY, pt, 4)
	sz := Buffer(8, 0), NumPut("Int", p.w, sz, 0), NumPut("Int", p.h, sz, 4)
	src := Buffer(8, 0)
	bf := Buffer(4, 0), NumPut("UChar", 0, bf, 0), NumPut("UChar", 0, bf, 1), NumPut("UChar", Op, bf, 2), NumPut("UChar", 1, bf, 3)
	if (DllCall("UpdateLayeredWindow", "Ptr", p.hwnd, "Ptr", 0, "Ptr", pt, "Ptr", sz, "Ptr", p.hdc, "Ptr", src, "UInt", 0, "Ptr", bf, "UInt", 2, "Int"))
		{
		p.op := Op
		if (!p.put)
			DllCall("ShowWindow", "Ptr", p.hwnd, "Int", 8), p.put := 1
		}
	}

; How solid the overlay is - PlayerStats.txt overlayopacity (%, 90 if it's not there), read every 5 s
OpRead()
	{
	global Op, OpAt
	if (A_TickCount - OpAt < 5000)
		return
	OpAt := A_TickCount
	pct := 90
	try
		if (RegExMatch(FileRead(STATS), "m)^\s*overlayopacity\s*:\s*(\d+)", &m))
			pct := Max(20, Min(100, Integer(m[1])))
	Op := Round(pct * 255 / 100)
	}

; A thumbnail of window src in the view (0 when Windows wouldn't make it)
ThumbMake(src)
	{
	h := 0
	r := DllCall("dwmapi\DwmRegisterThumbnail", "Ptr", View.Hwnd, "Ptr", src, "Ptr*", &h, "Int")
	return r = 0 ? h : 0
	}

; Where a thumbnail goes in the view (l, t, r, b), how solid, shown or not, and whether it copies its window's inside
; only (DWM_THUMBNAIL_PROPERTIES: dwFlags, rcDestination, rcSource, opacity, fVisible, fSourceClientAreaOnly)
ThumbPlace(h, l, t, r, b, opacity, visible, clientOnly)
	{
	if (!h)
		return
	p := Buffer(48, 0)
	NumPut("UInt", 0x1 | 0x4 | 0x8 | 0x10, p, 0)
	NumPut("Int", l, p, 4), NumPut("Int", t, p, 8), NumPut("Int", r, p, 12), NumPut("Int", b, p, 16)
	NumPut("UChar", opacity, p, 36), NumPut("Int", visible ? 1 : 0, p, 40), NumPut("Int", clientOnly ? 1 : 0, p, 44)
	DllCall("dwmapi\DwmUpdateThumbnailProperties", "Ptr", h, "Ptr", p, "Int")
	}

ThumbsDrop()
	{
	global GameThumb, Last
	if (GameThumb)
		DllCall("dwmapi\DwmUnregisterThumbnail", "Ptr", GameThumb)
	GameThumb := 0, Last := ""
	for part, p in Parts
		{
		if (p.thumb)
			DllCall("dwmapi\DwmUnregisterThumbnail", "Ptr", p.thumb)
		p.thumb := 0, p.shown := 0
		}
	}

; The game gone or minimised: the view hidden, the copies dropped (made again with the game)
ViewHide()
	{
	global Game
	ThumbsDrop()
	Game := 0
	try View.Hide()
	}

Cleanup(*)
	{
	try ThumbsDrop()
	}
