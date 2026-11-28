; StatsRead.ahk - reads the wizard's stats off the Spellbook's stats pages, at any UI size. AHK v1.1,
; functions only. Shared by StatsReader.ahk (run by hand) and Autofarmer.ahk (which reads them by
; itself when the school it just fought with has none yet - see StatsAuto there).
;
; Needs from the including script: the super-globals GameLeft, GameTop, GameW, GameH (the game's client
; area) and UiScale (1 = a 1920x1080 window at UI Size Small), PicOpt() (PicScale.ahk: a picture at the
; UI size in use), OcrRect() (Ocr.ahk), DebugLog(), and CoordMode Pixel and Mouse set to Screen.
;
; Where things are on the book was measured at UI scale 1 from the middle of the game area; at another
; size it's that times UiScale (the book is drawn round the middle). Numbers are read with digit
; pictures cut from the stats page (resources\stats\digits.txt, resized to the UI size), checked with
; Windows OCR of the dark ink at two sizes (see SrNumber); a value that can't be read for sure keeps
; its old value, so a wrong one is never written.

global SrDigitsRaw, SrDigits, SrDigitsAt, SrSchools
;The character that fought the last battle AutoFarmer saw, and its school (StatsNoteSchool)
global SrBattleChar, SrBattleSchool
;SrHandsOff: 1 = stop if the user touches the mouse or keyboard (AutoFarmer reading by itself);
;SrStop: why it stopped ("" = carrying on)
global SrHandsOff, SrStop

;Reads the stats of school's column (fire ice storm myth life death balance shadow). school "" = the
;column with clearly the highest damage (a wizard's gear boosts its own school most) - school is then
;set to it. got gets {damage, accuracy, critical, block, pierce}, "" for one that couldn't be read for
;sure. Opens the Spellbook (out of battle only), turns to the two stats pages and closes it again.
;Returns "" if it got that far, else why not
StatsRead(&school, &got)
	{
	global SrStop, SrSchools ; (v1 globals it sets)
	got := V1Obj(), SrStop := ""
	SrSchools := ["fire", "ice", "storm", "myth", "life", "death", "balance", "shadow"]
	s := UiScale, cx := GameLeft + GameW // 2, cy := GameTop + GameH // 2
	if (school != "" && !SrColumn(school))
		return "unknown school `"" school "`""
	if (!SrLoadDigits())
		return "couldn't load resources\stats\digits.txt"
	;The Spellbook icon (bottom right) only shows out of battle
	V1ImageSearch(&bookX, &bookY, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundfinish.png"))
	if (ErrorLevel)
		return "the Spellbook icon isn't showing (in a battle, or something over it?)"
	;C opens the book straight at the character page (the game's ToggleCharStats key). If it doesn't (or
	;the book was open on another page already), the Spellbook icon and then the character tab - the
	;top red tab on the right of the book
	tabNeeded := SrBookOpen(cx, cy)
	if (!tabNeeded && SrOk())
		{
		Send("{c}")
		Loop 8
			{
			Sleep(300)
			if (SrBookOpen(cx, cy))
				break
			}
		}
	if (!SrBookOpen(cx, cy))
		{
		DebugLog("  stats: C didn't open the book - clicking the Spellbook icon")
		SrClick(bookX + Round(12 * s), bookY + Round(12 * s))
		Loop 10
			{
			Sleep(300)
			if (SrBookOpen(cx, cy))
				break
			}
		if (SrStop != "")
			return "stopped: " SrStop
		if (!SrBookOpen(cx, cy))
			return "the Spellbook didn't open"
		tabNeeded := true
		}
	Sleep(500)
	if (tabNeeded)
		SrClick(cx + Round(450 * s), cy - Round(325 * s))
	Sleep(1000)
	;Stats page 1: Damage / Resistance / Accuracy (the book turns its pages slowly, so it retries)
	if (!SrCategory(cx + Round(20 * s), cy - Round(290 * s), "header_damage", "RESISTANCE", cx, cy))
		{
		if (SrStop != "")
			return "stopped: " SrStop
		SrSnap("page1_failed")
		SrCloseBook(cx, cy)
		return "couldn't find the Damage table on the stats page"
		}
	SrSnap("page1")
	if (school = "")
		{
		school := SrGuessSchool(cx, cy)
		if (school = "")
			{
			SrCloseBook(cx, cy)
			return "couldn't tell which school this wizard is (no school has clearly the highest damage)"
			}
		}
	col := SrColumn(school) - 1
	got.damage := SrNumber("damage", cx + Round((6 + 46 * col) * s), cy - Round(124 * s), Round(46 * s), Round(34 * s))
	got.accuracy := SrNumber("accuracy", cx + Round((6 + 46 * col) * s), cy + Round(292 * s), Round(46 * s), Round(33 * s))
	;Stats page 2: Critical / Block / Armor Piercing
	if (SrStop != "")
		return "stopped: " SrStop
	if (!SrCategory(cx + Round(75 * s), cy - Round(290 * s), "header_pierce", "PIERCING", cx, cy))
		{
		if (SrStop != "")
			return "stopped: " SrStop
		SrSnap("page2_failed")
		SrCloseBook(cx, cy)
		return "couldn't find the Armor Piercing table on the stats page"
		}
	SrSnap("page2")
	got.critical := SrNumber("critical", cx + Round((18 + 44 * col) * s), cy - Round(100 * s), Round(44 * s), Round(30 * s))
	got.block := SrNumber("block", cx + Round((18 + 44 * col) * s), cy + Round(25 * s), Round(44 * s), Round(30 * s))
	got.pierce := SrNumber("pierce", cx + Round((18 + 44 * col) * s), cy + Round(148 * s), Round(44 * s), Round(30 * s))
	;(the numbers are read: they count even if closing the book was cut short)
	SrCloseBook(cx, cy)
	return ""
	}

;False (and SrStop says why) once the game isn't the active window any more, a battle has started, or
;- when AutoFarmer reads by itself (SrHandsOff) - the user has touched the mouse or keyboard: then it
;stops clicking
SrOk()
	{
	global SrStop ; (v1 globals it sets)
	if (SrStop != "")
		return false
	if (!WinActive("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe"))
		SrStop := "Wizard101 isn't the active window any more"
	else if (SrHandsOff && (V1IsFunc("UserIdle") ? %"UserIdle"%() : A_TimeIdlePhysical) < 500)
		SrStop := "you used the mouse or keyboard"
	else
		{
		;A battle started (its Pass button is up): no more clicks or C
		V1ImageSearch(&px, &py, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundstart.png"))
		if (ErrorLevel = 0)
			SrStop := "a battle started"
		}
	return SrStop = ""
	}

;1-based column of a school on the stats pages, 0 if it isn't one
SrColumn(school)
	{
	for i, name in ["fire", "ice", "storm", "myth", "life", "death", "balance", "shadow"]
		if (name = school)
			return i
	return 0
	}

;Writes what was read into PlayerStats.txt as <school>.<stat> lines (the kill check uses
;<school>.damage and <school>.pierce for that school's wizard, before the plain damage / pierce lines),
;and <school>.charid = the character they're from (AutoFarmer reads them again when another character
;of that school fights). Other lines are left alone. Returns a summary for the user
StatsWrite(got, school, charID := "")
	{
	path := A_ScriptDir "\PlayerStats.txt"
	text := V1FileRead(path)
	if (ErrorLevel || !InStr(text, ":"))
		return "Couldn't read PlayerStats.txt, so nothing was changed."
	lines := StrSplit(StrReplace(text, "`r"), "`n")
	if (lines.Length && lines[lines.Length] = "")
		lines.Pop()
	heading := "; ---- Read from your stats pages by StatsReader (per school: <school>.damage and .pierce are what the kill check uses for that school's wizard) ----"
	headAt := 0
	for i, ln in lines
		if (InStr(ln, "; ---- Read from your stats page"))
			headAt := i, lines[i] := heading
	if (!headAt)
		lines.Push(""), lines.Push(heading)
	summary := "", failed := ""
	for each, stat in ["damage", "pierce", "critical", "accuracy", "block"]
		{
		val := got[stat], key := school "." stat
		if (val = "")
			{
			failed .= "`n   " stat " (kept the old value)"
			continue
			}
		found := false
		for i, ln in lines
			if (RegExMatch(ln, "i)^\s*\Q" key "\E\s*:"))
				{
				lines[i] := key ":" val, found := true
				break
				}
		if (!found)
			lines.Push(key ":" val)
		summary .= "`n   " stat ": " val
		}
	if (charID != "" && summary != "")
		{
		got.charid := charID, found := false
		for i, ln in lines
			if (RegExMatch(ln, "i)^\s*\Q" school ".charid\E\s*:"))
				{
				lines[i] := school ".charid:" charID, found := true
				break
				}
		if (!found)
			lines.Push(school ".charid:" charID)
		}
	now := FormatTime(, "yyyy-MM-dd HH:mm")
	note := "; StatsReader last read your " school " stats on " now
	noteAt := 0, keepAt := 0
	for i, ln in lines
		{
		if (InStr(ln, "; StatsReader last read"))
			noteAt := i
		if (InStr(ln, "Keep these two lines first"))
			keepAt := i
		}
	if (noteAt)
		lines[noteAt] := note
	else
		{
		;(v1: InsertAt past the end left a gap - skipped when written; v2 throws)
		if ((keepAt ? keepAt + 1 : 3) > lines.Length + 1)
			lines.Push(note)
		else
			lines.InsertAt(keepAt ? keepAt + 1 : 3, note)
		}
	out := ""
	for i, ln in lines
		out .= ln "`r`n"
	;A temporary copy first, so a failed write can't leave PlayerStats.txt empty
	V1Do(FileDelete, path ".tmp")
	V1Do(FileAppend, out, path ".tmp")
	if (ErrorLevel)
		return "Couldn't write PlayerStats.txt (is it open in another program?). Nothing was changed."
	;(the copy gone meanwhile - another writer of the same .tmp: no move of nothing taken for a replace)
	if (!FileExist(path ".tmp"))
		return "Couldn't replace PlayerStats.txt (is it open in another program?). Nothing was changed."
	V1Do(FileMove, path ".tmp", path, 1)
	if (ErrorLevel)
		return "Couldn't replace PlayerStats.txt (is it open in another program?). Nothing was changed."
	return "Read the " school " wizard's stats into PlayerStats.txt:" (summary = "" ? "`n   (nothing)" : summary)
		. (failed = "" ? "" : "`n`nCouldn't read for sure:" failed)
	}

;---- Which wizard is logged in, and its school ----

;The logged-in character's id, from the game's log ("MSG_LoginComplete CharID:..." - the last one in it), "" if not
;found. Looked up again at most every 20 s, and only when the log has grown: the log gets to 2 GB in a long session
;(texture error spam, about 70 MB an hour - WizardClient.261124_0018.log, 2,146,435,246 bytes), and reading all of it
;stopped every thread for seconds each time (a walker holding W ran on blind, F6 waited). So it's read from its end
;backwards a MB at a time until a login line turns up, and after that only what's been added since
;again: look now, not waiting out the 20 s - StatsReader.exe, which looks once and exits, carries on down a big log so
StatsCharID(again := false)
	{
	static charNow := "", readAt := 0, logWas := "", headWas := "", sizeWas := 0, scanDown := 0, scanFloor := 0
	static svPend := "", svSavedId := "", svSavedSize := 0
	if (!again && readAt && A_TickCount - readAt < 20000)
		return charNow
	readAt := A_TickCount
	logPath := SrLogPath()
	;(v1: no log - blank. FileOpen gave 0 when it couldn't open it - v2 throws)
	try
		logFile := FileOpen(logPath, "r", "CP0")
	catch
		logFile := ""
	if (!IsObject(logFile))
		{
		charNow := "", logWas := "", headWas := "", sizeWas := 0, scanDown := 0, scanFloor := 0, svPend := ""
		return charNow
		}
	logSize := logFile.Length
	;The game starts a new log each time it starts (and at 2 GB), with a new time stamp on its first line: a new log
	;(or another game's, or a shorter one) is looked through from its end again, with nothing known yet
	logHead := logFile.Read(17)
	if (logPath != logWas || logHead != headWas || logSize < sizeWas)
		{
		charNow := "", logWas := logPath, headWas := logHead, sizeWas := 0, scanDown := 0, scanFloor := 0
		svPend := "", svSavedId := "", svSavedSize := 0
		;(this log's id as an earlier run of the bot (or StatsReader) found it - kept with the log's first line and its size
		;then, StatsCharSave: only what's been added since is looked through, and that id taken once it's all been looked
		;through with no newer login line in it (svPend, below) - not before: another character logged in meanwhile wins. A
		;restart on a long log isn't left without it while the 256 MB looks work their way down to the login line)
		svId := "", svSize := 0
		if (StatsCharSaved(logPath, logHead, logSize, &svId, &svSize))
			svPend := svId, sizeWas := svSize, svSavedId := svId, svSavedSize := svSize
		}
	else if (logSize = sizeWas && scanDown <= scanFloor)
		{
		logFile.Close()
		return charNow
		}
	;What's been added since last time first, down to what was read then (less 120 bytes, so a login line it ended in the
	;middle of is read whole) - all of a new log. At most 256 MB a look: when that runs out first, the part below where it
	;got to (scanDown, down to scanFloor) is still to look through, and the looks after carry on down it, 256 MB each, after
	;what's been added by then - a login line there is newer than any further down. Till then a new log's "" (a log
	;already read keeps the id it had), and "" for good only once it's all been looked through, as when the whole log was
	;searched (a 2 GB log in 9 looks, under 3 minutes - one whole read stopped everything for seconds)
	floorAt := sizeWas > 120 ? sizeWas - 120 : 0, readSum := 0, id := "", downTo := 0, newer := false
	if (StatsLoginScan(logFile, logSize, floorAt, &readSum, &id, &downTo))
		charNow := id, scanDown := 0, scanFloor := 0, newer := true
	else if (downTo > floorAt)
		{
		;(an older part still to do as well: one part, from the bottom of that up to here - some of it looked at twice)
		if (scanDown <= scanFloor)
			scanFloor := floorAt
		scanDown := downTo
		DebugLog("  stats: no login line in the last 256 MB of the game's log (" logSize " bytes) - looking further back 256 MB every 20 s, character id `"" charNow "`" till then")
		}
	else if (scanDown > scanFloor)
		{
		if (StatsLoginScan(logFile, scanDown, scanFloor, &readSum, &id, &downTo))
			charNow := id, scanDown := 0, scanFloor := 0, newer := true
		else
			scanDown := downTo  ; (scanFloor when it got to the bottom - nothing left to look through)
		}
	;(the id kept from an earlier run: taken once all that's been added since it was found has been looked through with no
	;newer login line in it; a newer one found drops it)
	if (svPend != "")
		{
		if (newer)
			svPend := ""
		else if (scanDown <= scanFloor)
			charNow := svPend, svPend := ""
		}
	;(kept for the next run - when it changes, and each 32 MB the log grows, so a restart looks through only what's been
	;added after that; only once nothing older is left to look through, when it's sure)
	if (charNow != "" && scanDown <= scanFloor && (charNow != svSavedId || logSize - svSavedSize >= 33554432))
		StatsCharSave(logPath, logHead, logSize, charNow), svSavedId := charNow, svSavedSize := logSize
	logFile.Close()
	sizeWas := logSize
	return charNow
	}

;StatsCharID's look through the log: backwards from readTo down to floorAt, a MB at a time, each MB overlapping the one
;after it by 120 bytes (the line and its id are under 80), till a login line turns up or what's been read this look
;(readSum, added to) gets to 256 MB. 1 if one did - the last one in that part, its id in id ("" if no id follows it) -
;else 0, with downTo where to carry on from next time (floorAt when it got all the way down)
StatsLoginScan(logFile, readTo, floorAt, &readSum, &id, &downTo)
	{
	while (readTo > floorAt && readSum < 268435456)
		{
		readFrom := Max(floorAt, readTo - 1048576)
		logFile.Pos := readFrom
		chunk := logFile.Read(readTo - readFrom)
		readSum += readTo - readFrom
		at := InStr(chunk, "MSG_LoginComplete CharID:", false, -1)
		if (at)
			{
			id := RegExMatch(SubStr(chunk, at, 80), "CharID:(\d+)", &m) ? m[1] : ""
			return 1
			}
		readTo := readFrom > floorAt ? readFrom + 120 : floorAt
		}
	downTo := readTo
	return 0
	}

;StatsCharID's last find kept for the next run (stats_char.ini beside the bot - a cache, nothing of yours): true, with its
;id and the log's size then, when it was found in this same log (its path and the start of its first line) and the log is
;no shorter since
StatsCharSaved(logPath, logHead, logSize, &id, &size)
	{
	f := A_ScriptDir "\stats_char.ini"
	try
		{
		if (IniRead(f, "log", "path", "") != logPath || IniRead(f, "log", "head", "") != StatsIniSafe(logHead))
			return false
		id := IniRead(f, "log", "id", ""), size := IniRead(f, "log", "size", "")
		}
	catch
		return false
	return id != "" && IsInteger(size) && size + 0 <= logSize
	}

;Keeps id, found in the log at logPath (logSize long then), for the next run - StatsCharSaved
StatsCharSave(logPath, logHead, logSize, id)
	{
	if (id = "")
		return
	f := A_ScriptDir "\stats_char.ini"
	try
		{
		IniWrite(logPath, f, "log", "path")
		IniWrite(StatsIniSafe(logHead), f, "log", "head")
		IniWrite(logSize, f, "log", "size")
		IniWrite(id, f, "log", "id")
		}
	}

;The log's first bytes as an ini value can hold them (no line breaks, no spaces the ini would trim)
StatsIniSafe(text)
	{
	return RegExReplace(text, "[^!-~]", "_")
	}

SrLogPath()
	{
	exePath := V1Try(WinGetProcessPath, "ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe")  ; (v1: no window - blank)
	if (exePath != "")
		{
		SplitPath(exePath, , &binDir)
		if (FileExist(binDir "\WizardClient.log"))
			return binDir "\WizardClient.log"
		}
	return "C:\ProgramData\KingsIsle Entertainment\Wizard101\Bin\WizardClient.log"
	}

;The school AutoFarmer saw this character fight with (resources\characters.txt), "" if never
StatsSchoolOf(charID)
	{
	if (charID = "")
		return ""
	Loop Read, A_ScriptDir "\resources\characters.txt"
		{
		if (RegExMatch(A_LoopReadLine, "^(\d+)\|(\w+)", &m) && m[1] = charID)
			return m[2]
		}
	else
		{
		;(v1: no characters.txt yet - the loop just didn't run; v2 throws without an Else)
		}
	return ""
	}

;Remembers the logged-in character's school (AutoFarmer calls it each round with the school of the
;hitter it found on the name plate): in resources\characters.txt, and which character fought this
;battle (SrBattleChar / SrBattleSchool)
StatsNoteSchool(school)
	{
	global SrBattleChar, SrBattleSchool ; (v1 globals it sets)
	if (school = "")
		return
	id := StatsCharID()
	SrBattleChar := id, SrBattleSchool := school
	if (id = "" || StatsSchoolOf(id) = school)
		return
	path := A_ScriptDir "\resources\characters.txt", out := ""
	Loop Read, path
		{
		if (!RegExMatch(A_LoopReadLine, "^" id "\|"))
			out .= A_LoopReadLine "`r`n"
		}
	else
		{
		;(v1: no characters.txt yet - the loop just didn't run; v2 throws without an Else)
		}
	;(written whole or not at all: to characters.txt.tmp first, moved over it only once all of it got there - deleted
	;and then written again, a kill, a full disk or a reader holding it in between lost every character's school)
	V1Do(FileDelete, path ".tmp")
	if (V1Do(FileAppend, (out = "" ? "; Wizard101 characters (CharID from the game's log) and the school AutoFarmer saw each fight with`r`n" : out) id "|" school "`r`n", path ".tmp")
		|| V1Do(FileMove, path ".tmp", path, 1))
		{
		V1Do(FileDelete, path ".tmp")
		DebugLog("  (character " id " is a " school " wizard - couldn't be saved in characters.txt, kept as it was)")
		return
		}
	DebugLog("  (character " id " is a " school " wizard - noted for StatsReader)")
	}

;---- Reading the book ----

SrClick(x, y)
	{
	if (!SrOk())
		return
	;(your mouse locked meanwhile, in AutoFarmer - Settings.ahk MouseLockOn; StatsReader has none)
	if (V1IsFunc("MouseLockOn"))
		%"MouseLockOn"%("stats")  ; (by name: StatsReader has no MouseLockOn - a plain reference would warn at load)
	MouseMove(x, y, 5)
	;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
	if (V1IsFunc("MouseLockMoved"))
		%"MouseLockMoved"%()
	Sleep(120)
	Click()
	if (V1IsFunc("MouseLockOff"))
		%"MouseLockOff"%("stats")
	Sleep(150)
	}

SrCloseBook(cx, cy)
	{
	;The red X tab at the bottom of the book's tabs, else C (it toggles the character page)
	Loop 2
		{
		SrClick(cx + Round(450 * UiScale), cy + Round(322 * UiScale))
		Sleep(600)
		if (!SrBookOpen(cx, cy))
			return
		}
	if (!SrOk())
		return
	DebugLog("  stats: the close tab didn't close the book - pressing C")
	Send("{c}")
	Sleep(600)
	if (SrBookOpen(cx, cy))
		DebugLog("  stats: the book is still open")
	}

;Is the Spellbook open? (its red X tab is showing)
SrBookOpen(cx, cy)
	{
	s := UiScale
	V1ImageSearch(&x, &y, cx + Round(380 * s), cy + Round(250 * s), cx + Round(520 * s), cy + Round(400 * s), PicOpt("resources\stats\tab_close.png", 30))
	return (ErrorLevel = 0)
	}

;Clicks a stats category icon until its header shows on the right-hand page (up to 3 tries). The
;header is looked for as a picture (made at the UI size in use), and if that doesn't match, as a word
;read by OCR (big clear letters: "RESISTANCE" on page 1 - OCR garbles the M of DAMAGE - and
;"PIERCING" on page 2)
SrCategory(x, y, header, word, cx, cy)
	{
	s := UiScale, x1 := cx + Round(60 * s), y1 := cy - Round(260 * s), x2 := cx + Round(400 * s), y2 := cy + Round(140 * s)
	Loop 3
		{
		if (!SrOk())
			return false
		SrClick(x, y)
		Loop 6
			{
			Sleep(250)
			V1ImageSearch(&hx, &hy, x1, y1, x2, y2, PicOpt("resources\stats\" header ".png", 30))
			if (ErrorLevel = 0)
				return true
			if (A_Index >= 3)
				{
				t := OcrRect(x1, y1, x2 - x1, y2 - y1)
				if (!ErrorLevel && InStr(t, word))
					{
					DebugLog("  stats: " header " found by its word '" word "' (not by its picture)")
					return true
					}
				}
			}
		}
	return false
	}

;The school whose damage (read with the digit pictures) is clearly the highest: 10 or more above
;the next, every column read. "" if none is
SrGuessSchool(cx, cy)
	{
	s := UiScale, best := "", bestVal := -1, runnerUp := -1, all := "", missed := 0
	for i, name in SrSchools
		{
		val := SrReadCell(cx + Round((6 + 46 * (i - 1)) * s), cy - Round(124 * s), Round(46 * s), Round(34 * s), &score)
		all .= " " name "=" (val = "" ? "?" : val)
		if (val = "" || score < 0.85)
			{
			missed += 1
			continue
			}
		val += 0
		if (val > bestVal)
			runnerUp := bestVal, bestVal := val, best := name
		else if (val > runnerUp)
			runnerUp := val
		}
	DebugLog("  stats: damage by school:" all)
	return (best != "" && !missed && bestVal - runnerUp >= 10) ? best : ""
	}

;One number cell. The digit pictures (resized to the UI size) read the numbers on this page reliably
;- every cell right at UI 1 and at 1.14 in tests - and a strong match (every digit's score 0.85 or
;more) is taken unless OCR, reading only the dark ink, reads a different number the same way at two
;sizes. A weaker match needs OCR to agree. A number with a digit there's no picture of (there's no 4
;yet) is taken from OCR when both sizes agree. "" unless sure
SrNumber(what, x, y, w, h)
	{
	pics := SrReadCell(x, y, w, h, &score, &marks)
	t := OcrRect(x, y, w, h, "en", 3, &lines, 2)
	o3 := ErrorLevel ? "" : RegExReplace(t, "\D")
	t := OcrRect(x, y, w, h, "en", 4, &lines, 2)
	o4 := ErrorLevel ? "" : RegExReplace(t, "\D")
	ocrSure := (o3 != "" && o3 = o4)
	val := ""
	if (pics != "" && (pics = o3 || pics = o4))
		val := pics
	else if (pics != "" && score >= 0.85 && !(ocrSure && o3 != pics))
		val := pics
	;(OCR alone: only with as many digits as there are separate marks of ink - a cell border read as
	;an extra 1 doesn't count)
	else if (pics = "" && ocrSure && StrLen(o3) = marks)
		val := o3
	DebugLog("  stats: " what " - digit pictures " (pics = "" ? "?" : pics " (score " Round(score, 2) ")") ", OCR " (o3 = "" ? "?" : o3) " / " (o4 = "" ? "?" : o4) " -> " (val = "" ? "not sure, not written" : val))
	return val
	}

;digits.txt: char|width|height|values (ink darkness 0-255, row by row), one line per sample. Kept as
;read (SrDigitsRaw); SrDigits is them resized to the UI size in use, ready for matching
SrLoadDigits()
	{
	global SrDigitsRaw, SrDigits, SrDigitsAt ; (v1 globals it sets)
	if (!IsObject(SrDigitsRaw))
		{
		SrDigitsRaw := []
		;(each sample a v2 object: every key set here and read as written - as v1's; V1Obj's lookups would slow the
		;digit matching several times over)
		Loop Read, A_ScriptDir "\resources\stats\digits.txt"
			{
			if (SubStr(A_LoopReadLine, 1, 1) = ";" || A_LoopReadLine = "")
				continue
			p := StrSplit(A_LoopReadLine, "|")
			SrDigitsRaw.Push({ch: p[1], w: p[2] + 0, h: p[3] + 0, v: StrSplit(p[4], ",")})
			}
		else
			{
			;(v1: no digits.txt - the loop just didn't run: "couldn't load" below; v2 throws without an Else)
			}
		}
	if (!SrDigitsRaw.Length)
		return false
	if (IsObject(SrDigits) && SrDigitsAt = UiScale)
		return true
	SrDigits := [], SrDigitsAt := UiScale
	for i, d in SrDigitsRaw
		{
		tw := Round(d.w * UiScale), th := Round(d.h * UiScale)
		vals := SrResample(d.v, d.w, d.h, tw, th)
		n := tw * th, sum := 0
		Loop n
			sum += vals[A_Index]
		mean := sum / n, ss := 0
		Loop n
			{
			vals[A_Index] -= mean
			ss += vals[A_Index] ** 2
			}
		SrDigits.Push({ch: d.ch, w: tw, h: th, v: vals, norm: Sqrt(ss)})
		}
	return true
	}

;A grey picture (1-based, row by row) resized from w x h to tw x th, each pixel the average of what it covers
SrResample(vals, w, h, tw, th)
	{
	if (tw = w && th = h)
		return vals.Clone()
	out := [], rx := w / tw, ry := h / th
	Loop th
		{
		y0 := (A_Index - 1) * ry, y1 := A_Index * ry
		Loop tw
			{
			x0 := (A_Index - 1) * rx, x1 := A_Index * rx, sum := 0, area := 0
			j := Floor(y0)
			while (j < y1 && j < h)
				{
				wy := (y1 < j + 1 ? y1 : j + 1) - (y0 > j ? y0 : j)
				i := Floor(x0)
				while (i < x1 && i < w)
					{
					wx := (x1 < i + 1 ? x1 : i + 1) - (x0 > i ? x0 : i)
					sum += vals[j * w + i + 1] * wx * wy, area += wx * wy
					i++
					}
				j++
				}
			out.Push(area ? sum / area : 0)
			}
		}
	return out
	}

;Reads one number cell with the digit pictures. Returns the digits, or "" if it couldn't be read for
;sure; score = the weakest chosen digit's match (0..1), marks = how many separate marks of ink (runs of
;columns with ink) the digit band has
SrReadCell(x, y, w, h, &score := "", &marks := "")
	{
	score := 0, marks := 0
	g := SrInk(x, y, w, h)
	if (!IsObject(g))
		return ""
	;The digit band: the tallest run of rows with black ink in them
	bestLen := 0, run := 0, start := 0
	Loop h + 1
		{
		r := A_Index - 1, cnt := 0
		if (r < h)
			Loop w
				cnt += g.black[r * w + A_Index]
		if (r < h && cnt >= 2)
			{
			if (run = 0)
				start := r
			run++
			}
		else
			{
			if (run > bestLen)
				bestLen := run, b0 := start, b1 := r - 1
			run := 0
			}
		}
	if (bestLen < 8 * UiScale)
		return ""
	;Which columns have ink in the band (a digit starts next to one)
	inkCol := V1Obj()  ; (v1: keyed from 0, and past the band's edge blank - inkCol[tx + 3])
	Loop w
		{
		colX := A_Index - 1, ink := 0, r := b0 - 1
		while (++r <= b1)
			if (g.black[r * w + colX + 1])
				ink := 1
		inkCol[colX] := ink
		if (ink && !(colX && inkCol[colX - 1]))
			marks += 1
		}
	;Sums of the ink (and of its square) over any window: integral images, (h + 1) x (w + 1)
	iw := w + 1, s1 := [], s2 := []
	Loop iw * (h + 1)
		s1.Push(0), s2.Push(0)  ; (v1: s1[A_Index] := 0 - v2's arrays grow by Push)
	Loop h
		{
		r := A_Index, rowSum := 0, rowSq := 0
		Loop w
			{
			v := g.gray[(r - 1) * w + A_Index], rowSum += v, rowSq += v * v
			s1[r * iw + A_Index + 1] := s1[(r - 1) * iw + A_Index + 1] + rowSum
			s2[r * iw + A_Index + 1] := s2[(r - 1) * iw + A_Index + 1] + rowSq
			}
		}
	;Slide every digit picture across the band and keep the good matches. The pictures are mean-free,
	;so the correlation is sum(ink x picture) / sqrt(spread of the window x spread of the picture)
	cands := [], up := Round(3 * UiScale)
	for i, d in SrDigits
		{
		n := d.w * d.h
		ty := b0 - up - 1
		while (++ty <= b0)
			{
			if (ty < 0 || ty + d.h > h)
				continue
			tx := -1
			while (++tx <= w - d.w)
				{
				if (!(inkCol[tx] || inkCol[tx + 1] || inkCol[tx + 2] || inkCol[tx + 3]))
					continue
				a := ty * iw + tx + 1, z := (ty + d.h) * iw + tx + 1
				sum := s1[z + d.w] - s1[a + d.w] - s1[z] + s1[a]
				sq := s2[z + d.w] - s2[a + d.w] - s2[z] + s2[a]
				spread := sq - sum * sum / n
				if (spread <= 0 || d.norm <= 0)
					continue
				dot := 0, k := 0
				Loop d.h
					{
					base := (ty + A_Index - 1) * w + tx
					Loop d.w
						dot += g.gray[base + A_Index] * d.v[++k]
					}
				ncc := dot / Sqrt(spread * d.norm ** 2)
				if (ncc >= 0.77)
					cands.Push({s: ncc, x: tx + 1, w: d.w - 2, ch: d.ch})
				}
			}
		}
	;Best matches first, no two overlapping (1 px allowed)
	chosen := []
	while (cands.Length)
		{
		bi := 1
		for i, c in cands
			if (c.s > cands[bi].s)
				bi := i
		c := cands.RemoveAt(bi), clash := false
		for j, k in chosen
			if !(c.x + c.w <= k.x + 1 || k.x + k.w <= c.x + 1)
				clash := true
		if (!clash)
			chosen.Push(c)
		}
	;Every column with ink in the band must belong to a recognised digit
	Loop w
		{
		colX := A_Index - 1
		if (!inkCol[colX])
			continue
		covered := false
		for j, k in chosen
			if (colX >= k.x - 1 && colX <= k.x + k.w)
				covered := true
		if (!covered)
			return ""
		}
	;Left to right
	text := "", used := V1Obj(), score := 1
	Loop chosen.Length
		{
		bi := 0
		for j, k in chosen
			if (!used[j] && (bi = 0 || k.x < chosen[bi].x))
				bi := j
		used[bi] := true, text .= chosen[bi].ch
		if (chosen[bi].s < score)
			score := chosen[bi].s
		}
	if (text = "")
		score := 0
	return text
	}

;Screen rectangle -> {gray: ink darkness 0-255 (1-based, row by row), black: 1 where near-black}
SrInk(x, y, w, h)
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
	gray := [], blk := []
	Loop w * h
		{
		c := NumGet(bits + (A_Index - 1) * 4, "UInt")
		r := (c >> 16) & 0xFF, gr := (c >> 8) & 0xFF, b := c & 0xFF
		gray.Push(255 - (r + gr + b) / 3)
		mx := r > gr ? r : gr
		mx := mx > b ? mx : b
		blk.Push(mx < 60 ? 1 : 0)
		}
	DllCall("SelectObject", "Ptr", mdc, "Ptr", obm), DllCall("DeleteObject", "Ptr", hbm)
	DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
	return {gray: gray, black: blk}
	}

;A picture of the game area (BMP) in the Windows temp folder ("Wizard101 bot rounds\stats_<what>_<time>.bmp"),
;so a stats page that didn't read right can be looked at. Keeps the newest 8
SrSnap(what)
	{
	dir := A_Temp "\Wizard101 bot rounds"
	V1Do(DirCreate, dir)  ; (v1: ErrorLevel when it fails - v2 throws)
	files := ""
	Loop Files, dir "\stats_*.bmp"
		files .= A_LoopFileTimeModified "|" A_LoopFileName "`n"
	files := Sort(files)
	list := StrSplit(Trim(files, "`n"), "`n")
	while (list.Length >= 8)
		Try FileDelete(dir "\" V1At(StrSplit(list.RemoveAt(1), "|"), 2))
	w := GameW, h := GameH
	hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
	bi := Buffer(40, 0)
	NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
	NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", GameLeft, "Int", GameTop, "UInt", 0x00CC0020)
		DllCall("GdiFlush")
		stamp := FormatTime(, "yyyyMMdd_HHmmss")
		bmp := V1Try(FileOpen, dir "\stats_" what "_" stamp ".bmp", "w")  ; (v1: 0 when it can't be opened - v2 throws)
		if (IsObject(bmp))
			{
			bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + w * h * 4), bmp.WriteUInt(0), bmp.WriteUInt(54)
			bmp.WriteUInt(40), bmp.WriteInt(w), bmp.WriteInt(-h), bmp.WriteUShort(1), bmp.WriteUShort(32)
			bmp.WriteUInt(0), bmp.WriteUInt(w * h * 4), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
			bmp.RawWrite(bits + 0, w * h * 4)
			bmp.Close()
			}
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm), DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
StatsReadBlank()
	{
	global SrDigitsRaw := "", SrDigits := "", SrDigitsAt := "", SrSchools := "", SrBattleChar := "", SrBattleSchool := "", SrHandsOff := ""
	global SrStop := ""
	}
