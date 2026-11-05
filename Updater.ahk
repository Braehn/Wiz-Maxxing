; Updater.ahk - checks GitHub for a newer Wiz-Maxxing release and, if you say so, installs it. AHK v1.1,
; functions only; #Included by Wiz-Maxxing.ahk (it checks every time you open the bot) and Setup.ahk (which
; stores the token). The tray menu's "Check for updates" runs Wiz-Maxxing.exe /check.
;
; The repo is private, so it reads it with a GitHub token (fine-grained, read-only Contents on the repo),
; kept in Windows Credential Manager as "Wiz-Maxxing GitHub" - never in a file, never in the log.
; This folder's version is version.txt (e.g. v0.10; none = older than any release). Releases are numbered
; v0.01, v0.02, ... v0.99, v1.00, v1.01.
;
; Updating: the release zip is downloaded, the bot is closed if it's running, and the zip's files are
; copied over this folder - except your own: PlayerStats.txt (only settings it doesn't have yet are added),
; learned cards (learned\ folders, and the slot pictures learned\cards.txt says they went into), dungeon runs, potion
; routes, the walker's memory, window positions, logs. A program that's in use (Wiz-Maxxing.exe, Setup.exe)
; is renamed out of the way and the new one put in its place. It's all or nothing: every file it replaces
; is copied aside first, and if any file can't be written the folder is put back as it was, version.txt
; and all. Only then is version.txt set to the release's tag. Log: updater.log.
;
; (v2 port: ported by hand from the v1.1 original - the converter couldn't. The v1 behaviours it keeps are
; V1Compat.ahk's: ErrorLevel set by V1Do / V1RunWait as v1's commands set it, reads that v2 throws on give v1's blank)

;(tests only: another address for GitHub's API, a token, and yes to the question)
global UpTestApi, UpTestToken, UpTestYes
;An update by itself (UpAuto): no window at all - nothing asked, no progress, failures only in updater.log. And whether
;the running bot was closed (UpCloseBots) - Wiz-Maxxing.ahk then starts it again even when the update didn't go in.
;UpHandedOver: the bot closed itself for an update by itself (UpAuto), UpHandArgs how to start it again (as it was)
global UpQuiet, UpBotsClosed, UpHandedOver, UpHandArgs

;(the repo, and the token's name in Credential Manager - functions, since a global's starting value in an
;#Included file never runs)
UpRepo()
	{
	return "Joshuasbraincells/Wiz-Maxxing"
	}

UpApi()
	{
	return UpTestApi != "" ? UpTestApi : "https://api.github.com"
	}

UpCredTarget()
	{
	return "Wiz-Maxxing GitHub"
	}

;---- the check ----

;Looks for a newer release and asks to install it. quiet: no message when there's nothing to do or it can't
;check (opening the bot). True if it updated (the bot's files were replaced)
UpCheck(quiet := true)
	{
	UpCleanup()
	token := UpToken()
	if (token = "")
		{
		if (!quiet)
			MsgBox("There's no GitHub token on this PC, so updates can't be checked.`n`nRun Setup.exe and tick `"GitHub updates`" to add one.", "Wiz-Maxxing updates", 262192)
		return false
		}
	rel := UpLatest(token, &err, &status)
	token := ""
	if (!IsObject(rel))
		{
		UpPeekSave("", err)
		UpLog("check failed: " err)
		;(an expired or revoked token: said once even when opening the bot, else updates stop unnoticed)
		warned := IniRead(A_ScriptDir "\updater.ini", "token", "warned", 0)
		if (!UpTestYes && (!quiet || ((status = 401 || status = 403) && !warned)))
			MsgBox("Couldn't check for updates:`n" err, "Wiz-Maxxing updates", 262192)
		if ((status = 401 || status = 403) && quiet)
			V1Do(IniWrite, 1, A_ScriptDir "\updater.ini", "token", "warned")
		return false
		}
	V1Do(IniWrite, 0, A_ScriptDir "\updater.ini", "token", "warned")
	UpPeekSave(rel.tag, "")
	have := UpVersion()
	UpLog("installed " (have = "" ? "(no version.txt)" : have) ", latest " rel.tag)
	if (UpCompare(rel.tag, have) <= 0)
		{
		if (!quiet)
			MsgBox("You're up to date (" (have = "" ? rel.tag : have) ").", "Wiz-Maxxing updates", 262208)
		return false
		}
	notes := rel.body
	notes := RegExReplace(notes, "\*\*|__|``", "")
	if (StrLen(notes) > 700)
		notes := SubStr(notes, 1, 700) "..."
	;(v1's IfMsgBox: this thread's last message box - in test mode (UpTestYes) none was shown: not No)
	msgResult := ""
	if (!UpTestYes)
		msgResult := MsgBox("A new version is out: " rel.name "`n(you have " (have = "" ? "an older one" : have) ")`n`n" notes "`n`nUpdate now? Your settings, learned cards and potion routes are kept.", "Wiz-Maxxing update", 262180)
	if (msgResult = "No")
		{
		UpLog("you chose not to update to " rel.tag " now")
		return false
		}
	;(installed meanwhile - by another check: nothing to do)
	if (UpCompare(rel.tag, UpVersion()) <= 0)
		return false
	return UpInstall(rel)
	}

;Only looks (Wiz-Maxxing /latest - the bot's dashboard runs it now and then): the latest release's tag, or why it
;couldn't be looked up, into updater.ini [latest] - no question, no install, no message
UpPeek()
	{
	token := UpToken()
	if (token = "")
		{
		UpPeekSave("", "no GitHub token on this PC (Setup.exe: GitHub updates)")
		return
		}
	rel := UpLatest(token, &err, &status)
	token := ""
	UpPeekSave(IsObject(rel) ? rel.tag : "", IsObject(rel) ? "" : err)
	}

;The latest release's tag (or why it couldn't be looked up) for the dashboard: updater.ini [latest]. A failed
;look-up keeps the tag it last found (a newer version is still out) and says why it can't check
UpPeekSave(tag, err)
	{
	if (tag != "")
		V1Do(IniWrite, tag, A_ScriptDir "\updater.ini", "latest", "tag")
	V1Do(IniWrite, RegExReplace(err, "[\r\n]+", " "), A_ScriptDir "\updater.ini", "latest", "err")
	V1Do(IniWrite, A_Now, A_ScriptDir "\updater.ini", "latest", "at")
	}

;One update check / install at a time, across all the bot's processes (the dashboard's button clicked twice, the
;watcher's check, the tray's): true when this one may go on - else the other one's question is brought forward
UpOnlyOne(bringForward := true)
	{
	static mutex := 0
	if (mutex)
		return true
	mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Wiz-Maxxing update", "Ptr")
	if (A_LastError != 183)
		return true
	DllCall("CloseHandle", "Ptr", mutex)
	mutex := 0
	;(an update by itself: nothing brought forward)
	if (!bringForward)
		return false
	;(v1: WinActivate of a window that isn't there did nothing - v2 throws)
	try WinActivate("Wiz-Maxxing update ahk_class #32770")
	try WinActivate("Wiz-Maxxing updates ahk_class #32770")
	return false
	}

;Wiz-Maxxing /check /auto (the bot, Settings: autoupdate): the latest release installed with no question and no window -
;nothing said when there's nothing to do or it fails (updater.log). One version is tried 3 times in 6 hours at most
;(updater.ini [auto]; the bot looks there too). True if it updated
UpAuto()
	{
	global UpQuiet, ErrorLevel, UpHandedOver, UpHandArgs ; (v1 globals it sets)
	UpCleanup()
	UpQuiet := true
	token := UpToken()
	if (token = "")
		{
		UpLog("auto: no GitHub token on this PC")
		return false
		}
	rel := UpLatest(token, &err, &status)
	token := ""
	if (!IsObject(rel))
		{
		UpPeekSave("", err)
		UpLog("auto: check failed: " err)
		return false
		}
	UpPeekSave(rel.tag, "")
	have := UpVersion()
	if (UpCompare(rel.tag, have) <= 0)
		{
		UpLog("auto: up to date (" have ")")
		return false
		}
	ini := A_ScriptDir "\updater.ini"
	triedTag := IniRead(ini, "auto", "tag", A_Space)
	tries := IniRead(ini, "auto", "tries", 0)
	triedAt := IniRead(ini, "auto", "at", A_Space)
	;(v1: EnvSub, age, %triedAt%, Hours - a blank triedAt counted as now, one that isn't a time made age blank)
	age := V1Try(DateDiff, A_Now, triedAt, "Hours")
	if (triedTag != rel.tag || age = "" || age >= 6)
		tries := 0
	;(v1: an ini value that isn't a number compared as text, and made "tries + 1" blank)
	if (V1Ge(tries, 3))
		{
		UpLog("auto: " rel.tag " already tried 3 times - left to the dashboard's Help > Check for updates")
		return false
		}
	V1Do(IniWrite, rel.tag, ini, "auto", "tag")
	V1Do(IniWrite, V1Add(tries, 1), ini, "auto", "tries")
	V1Do(IniWrite, A_Now, ini, "auto", "at")
	UpLog("auto: downloading " rel.tag " (you have " (have = "" ? "no version.txt" : have) ", try " V1Add(tries, 1) ")")
	if (!UpFetch(rel, &tmp, &src))
		return false
	;The bot closes itself for it at a safe point - out of battle, nothing loading, you away (AutoFarmer UpdAuto): told
	;it's ready and by which process; it writes how it was (handover, args). Never closed under it here. An hour at
	;most - then it's for another time (the try not counted). A bot started again meanwhile is waited for too
	V1Do(IniDelete, ini, "auto", "handover")
	V1Do(IniDelete, ini, "auto", "args")
	V1Do(IniDelete, ini, "auto", "now")
	;(ready last: whoever sees it sees by whom and since when too)
	V1Do(IniWrite, DllCall("GetCurrentProcessId"), ini, "auto", "readypid")
	V1Do(IniWrite, A_Now, ini, "auto", "readyat")
	V1Do(IniWrite, rel.tag, ini, "auto", "ready")
	waitUntil := A_TickCount + 3600000, said := false, extended := false, stuck := false
	while (!stuck && (pids := UpBotPids(A_ScriptDir, true)).Length)
		{
		if (!said)
			UpLog("auto: " rel.tag " ready - waiting for the bot to close itself at a safe point"), said := true
		for i, pid in pids
			{
			Loop
				{
				ErrorLevel := ProcessExist(pid)
				if (!ErrorLevel)
					break
				if (A_TickCount > waitUntil)
					{
					;(closing for it at this very moment - its handover written: 2 minutes more, then it's closed here
					;if it's stuck closing - UpApply - and started again)
					handing := IniRead(ini, "auto", "handover", 0)
					if (handing = 1 && !extended)
						{
						extended := true, waitUntil := A_TickCount + 120000
						continue
						}
					if (handing = 1)
						{
						stuck := true
						break
						}
					UpAutoReadyOff()
					V1Do(IniWrite, tries, ini, "auto", "tries")
					V1Do(DirDelete, tmp, 1)
					UpLog("auto: the bot didn't get to a safe point in an hour - " rel.tag " another time")
					return false
					}
				Sleep(2000)
				}
			if (stuck)
				break
			}
		}
	UpAutoReadyOff()
	handover := IniRead(ini, "auto", "handover", 0)
	handArgs := IniRead(ini, "auto", "args", A_Space)
	V1Do(IniDelete, ini, "auto", "handover")
	V1Do(IniDelete, ini, "auto", "args")
	;(not handed over - you closed the bot meanwhile: installed, and not started again)
	UpHandedOver := handover = 1, UpHandArgs := handArgs
	UpLog("auto: " (UpHandedOver ? "the bot closed itself" (handArgs = "" ? "" : " (" handArgs ")") : "the bot isn't running (closed by you)") " - installing " rel.tag)
	return UpApply(rel, tmp, src)
	}

;The waiting update by itself's marks gone from updater.ini (UpAuto): ready, by whom and since when, "now" asked
UpAutoReadyOff()
	{
	ini := A_ScriptDir "\updater.ini"
	for i, k in ["ready", "readypid", "readyat", "now"]
		V1Do(IniDelete, ini, "auto", k)
	}

;An update by itself downloaded and waiting for the bot to close for it (UpAuto - its process still running, under an
;hour old): true, its tag in tag
UpAutoWaiting(&tag)
	{
	ini := A_ScriptDir "\updater.ini"
	tag := IniRead(ini, "auto", "ready", A_Space)
	pid := IniRead(ini, "auto", "readypid", 0)
	at := IniRead(ini, "auto", "readyat", A_Space)
	;(v1: EnvSub, age, %at%, Minutes - a blank at counted as now, one that isn't a time made age blank)
	age := V1Try(DateDiff, A_Now, at, "Minutes")
	if (tag = "" || !RegExMatch(pid, "^\d+$") || age = "" || age >= 58)
		return false
	for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid)
		if (InStr(p.CommandLine, "/auto"))
			return true
	return false
	}

;The update's progress window - none for an update by itself (UpQuiet). text "Off" closes it; first: it's opened
;(v2 port: v2 has no Progress command - this window is made as v1's "Progress, b w360 zh0 fs10, text, Wiz-Maxxing
;update" looked: no border or title bar, always on top, no taskbar button, not activated, 360 wide, the title in bold
;over the text, both centered, no bar)
UpProgress(text, first := false)
	{
	static upWin := "", sub := ""
	if (UpQuiet)
		return
	if (text = "Off")
		{
		if (IsObject(upWin))
			upWin.Destroy()
		upWin := "", sub := ""
		}
	else if (first || !IsObject(upWin))
		{
		if (IsObject(upWin))
			upWin.Destroy()
		upWin := Gui("+AlwaysOnTop -Caption +Owner", A_ScriptName)
		upWin.MarginX := 10, upWin.MarginY := 10
		upWin.SetFont("s10 w600")
		upWin.Add("Text", "w340 Center", "Wiz-Maxxing update")
		upWin.SetFont("s10 w400")
		sub := upWin.Add("Text", "w340 Center", text)
		upWin.Show("w360 NoActivate")
		}
	else
		sub.Text := text
	}

;"v0.10" vs "v0.09": 1 newer, 0 same, -1 older ("" counts as older than any)
UpCompare(a, b)
	{
	if (b = "")
		return a = "" ? 0 : 1
	;(vMAJOR.MAIN.BUG - v0.14 is v0.14.0)
	if (!RegExMatch(a, "(\d+)\.(\d+)(?:\.(\d+))?", &x) || !RegExMatch(b, "(\d+)\.(\d+)(?:\.(\d+))?", &y))
		return a = b ? 0 : 1
	pa := [x[1] + 0, x[2] + 0, x[3] = "" ? 0 : x[3] + 0], pb := [y[1] + 0, y[2] + 0, y[3] = "" ? 0 : y[3] + 0]
	Loop 3
		if (pa[A_Index] != pb[A_Index])
			return pa[A_Index] > pb[A_Index] ? 1 : -1
	return 0
	}

;This folder's version (version.txt), "" if none
UpVersion()
	{
	v := V1FileRead(A_ScriptDir "\version.txt")
	return Trim(v, " `t`r`n")
	}

;The latest release: {tag, name, body, zipUrl, zipName}; "" and err on a problem
UpLatest(token, &err, &status := 0)
	{
	err := ""
	resp := UpHttp(UpApi() "/repos/" UpRepo() "/releases/latest", token, "application/vnd.github+json", &status, 8000)
	if (status = 401 || status = 403)
		{
		err := "GitHub refused the token (" status ") - it may have expired. Make a new one and add it with Setup.exe."
		return ""
		}
	if (status = 404)
		{
		err := "GitHub says there's no release - or the token can't see the repo (404)."
		return ""
		}
	if (status != 200)
		{
		err := (status = 0 ? "no answer from GitHub (offline?)" : "GitHub answered " status)
		return ""
		}
	rel := V1Obj()
	;(v1's m1: blank when it didn't match - V1At)
	RegExMatch(resp, '"tag_name":\s*"([^"]+)"', &m), rel.tag := V1At(m, 1)
	;(v1's newline was `r`n only: its . ran across the LF lines of GitHub's indented JSON - v2's stops at a lone `n;
	;(*CRLF) gives v1's)
	RegExMatch(resp, '(*CRLF)"tag_name":.*?"name":\s*"((?:[^"\\]++|\\.)*+)"', &m), rel.name := UpUnescape(V1At(m, 1))
	RegExMatch(resp, '"body":\s*"((?:[^"\\]++|\\.)*+)"', &m), rel.body := UpUnescape(V1At(m, 1))
	;(the zip among the assets: its API url downloads it)
	if (RegExMatch(resp, '"url":\s*"([^"]+/releases/assets/\d+)",\s*"id":\s*\d+,\s*"node_id":\s*"[^"]*",\s*"name":\s*"([^"]+\.zip)"', &m))
		rel.zipUrl := m[1], rel.zipName := m[2]
	if (rel.tag = "")
		{
		err := "couldn't read GitHub's answer"
		return ""
		}
	if (rel.name = "")
		rel.name := rel.tag
	return rel
	}

;---- installing ----

UpInstall(rel)
	{
	if (!UpFetch(rel, &tmp, &src))
		return false
	return UpApply(rel, tmp, src)
	}

;The release's zip downloaded and unpacked into tmp (the folder in it: src) - nothing changed yet. False (said) if it
;can't be
UpFetch(rel, &tmp, &src)
	{
	if (rel.zipUrl = "")
		{
		UpLog(rel.tag " has no zip to download")
		if (!UpQuiet)
			MsgBox(rel.tag " has no zip to download - get it from the GitHub Releases page.", "Wiz-Maxxing update", 48)
		return false
		}
	UpProgress("Downloading " rel.zipName "...", true)
	tmp := A_Temp "\wiz-maxxing-update"
	V1Do(DirDelete, tmp, 1)
	V1Do(DirCreate, tmp)
	zip := tmp "\" rel.zipName
	token := UpToken()
	ok := UpDownload(rel.zipUrl, token, zip, &err)
	token := ""
	if (!ok)
		{
		UpProgress("Off")
		UpLog("download failed: " err)
		if (!UpQuiet)
			MsgBox("The download failed: " err "`n`nNothing was changed.", "Wiz-Maxxing update", 48)
		return false
		}
	UpProgress("Unpacking...")
	V1RunWait("powershell -NoProfile -ExecutionPolicy Bypass -Command `"try { Expand-Archive -LiteralPath '" zip "' -DestinationPath '" tmp "\unzipped' -Force -ErrorAction Stop } catch { exit 1 }`"", , "Hide")
	unzipped := (ErrorLevel = 0)
	src := ""
	Loop Files, tmp "\unzipped\*", "D"
		src := A_LoopFilePath
	if (!unzipped || src = "" || !FileExist(src "\AutoFarmer\Autofarmer.ahk"))
		{
		UpProgress("Off")
		UpLog("the zip didn't unpack (" zip ")")
		if (!UpQuiet)
			MsgBox("The downloaded zip didn't unpack - nothing was changed.", "Wiz-Maxxing update", 48)
		V1Do(DirDelete, tmp, 1)
		return false
		}
	;(every exe a release carries there too: an antivirus that took one out of the unpacked files - Defender's
	;"Contebrew.A!ml" guess at a fresh Autofarmer.exe, 2026-10-25 - would leave the old exe beside the new scripts, or none)
	missing := ""
	for i, exe in ["Wiz-Maxxing.exe", "Setup.exe", "AutoFarmer\Autofarmer.exe", "AutoFarmer\StatsReader.exe", "AutoQuester\AutoQuester.exe"]
		if (!FileExist(src "\" exe))
			missing .= (missing = "" ? "" : ", ") exe
	if (missing != "")
		{
		UpProgress("Off")
		UpLog("the update to " rel.tag " has no " missing " after unpacking (an antivirus took it out?) - nothing was changed")
		if (!UpQuiet)
			MsgBox("The update to " rel.tag " is missing " missing " after unpacking - most likely your antivirus removed it (Windows Security > Virus & threat protection > Protection history). Nothing was changed.`n`nAdd exclusions for this folder (" A_ScriptDir ") and " tmp " (Windows Security > Virus & threat protection > Manage settings > Exclusions) - the update is offered again next time.", "Wiz-Maxxing update", 48)
		V1Do(DirDelete, tmp, 1)
		return false
		}
	return true
	}

;The unpacked release (UpFetch) put in: the bot closed if it's still running, the files copied - all or nothing - and
;version.txt set. False (said) if it couldn't be, everything put back
UpApply(rel, tmp, src)
	{
	UpProgress("Closing the bot...")
	UpCloseBots()
	UpProgress("Copying the new files...")
	res := UpCopy(src, A_ScriptDir, tmp "\rollback")
	if (res.failed.Length)
		{
		UpRollback(res)
		UpProgress("Off")
		list := ""
		for i, f in res.failed
			list .= "`n   " f
		UpLog("update to " rel.tag " failed - put back as it was; couldn't write: " SubStr(StrReplace(list, "`n   ", " | "), 4))
		if (!UpTestYes && !UpQuiet)
			MsgBox("The update couldn't replace these files, so everything was put back as it was:" list "`n`nClose anything that has them open (Setup, an editor, the bot, the 'Open with Wizard101' watcher: its tray icon > Stop watching) and try again - the update is offered again next time.", "Wiz-Maxxing update", 48)
		V1Do(DirDelete, tmp, 1)
		return false
		}
	UpMergeStats(src "\AutoFarmer\PlayerStats.txt", A_ScriptDir "\AutoFarmer\PlayerStats.txt", rel.tag)
	;(the version is the release's tag - only now, with every file in place)
	V1Do(FileDelete, A_ScriptDir "\version.txt")
	V1Do(FileAppend, rel.tag "`r`n", A_ScriptDir "\version.txt")
	V1Do(DirDelete, tmp, 1)
	UpProgress("Off")
	UpLog("updated to " rel.tag ": " res.copied " file(s) replaced or added, " res.kept " of yours kept")
	if (!UpQuiet)
		TrayTip("Updated to " rel.tag ".", "Wiz-Maxxing", 1)
	return true
	}

;Closes the bot's programs running from this folder (dir: another): its exes, or its scripts run by AutoHotkey -
;nothing else (an editor that has a script open is left alone). Politely first; forced only if it's an AutoHotkey
;program
UpCloseBots(dir := "")
	{
	global UpBotsClosed, ErrorLevel ; (v1 globals it sets)
	if (dir = "")
		dir := A_ScriptDir
	pids := UpBotPids(dir)
	UpBotsClosed := UpBotsClosed || pids.Length > 0
	;(v1: WinClose of a window that's gone meanwhile did nothing - v2 throws)
	for i, pid in pids
		try WinClose("ahk_pid " pid " ahk_class AutoHotkey")
	for i, pid in pids
		{
		ErrorLevel := ProcessWaitClose(pid, 10)
		if (ErrorLevel)
			ErrorLevel := ProcessClose(pid)
		UpLog("closed the running bot (pid " pid ")")
		}
	Sleep(pids.Length ? 1500 : 0)
	}

;The bot's programs running from dir (UpCloseBots): their pids. main: only the bot itself (AutoFarmer\Autofarmer -
;not the stats reader or the quester)
UpBotPids(dir, main := false)
	{
	DetectHiddenWindows(true)
	pids := []
	bots := main ? "i)^(AutoFarmer\\Autofarmer)\." : "i)^(AutoFarmer\\Autofarmer|AutoFarmer\\StatsReader|AutoQuester\\AutoQuester)\."
	for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, ExecutablePath, CommandLine FROM Win32_Process")
		{
		path := p.ExecutablePath, cmd := p.CommandLine
		if (p.ProcessId = DllCall("GetCurrentProcessId") || path = "")
			continue
		mine := false
		;(an exe of the bot, in this folder)
		if (InStr(path, dir "\") = 1 && RegExMatch(SubStr(path, StrLen(dir) + 2), bots "exe$"))
			mine := true
		;(AutoHotkey running one of the bot's scripts from this folder: the script is its first argument)
		else if (RegExMatch(path, "i)\\AutoHotkey[^\\]*\.exe$") && RegExMatch(cmd, 'i)"?([A-Z]:\\[^"]+?\.ahk)"?', &m)
			&& InStr(m[1], dir "\") = 1 && RegExMatch(SubStr(m[1], StrLen(dir) + 2), bots "ahk$"))
			mine := true
		if (mine && WinExist("ahk_pid " p.ProcessId " ahk_class AutoHotkey"))
			pids.Push(p.ProcessId)
		}
	return pids
	}

;Copies the new release's files over the folder, keeping yours (UpIsMine) - every file it replaces copied to
;rollback first, a file in use renamed out of the way. Returns {copied, kept, failed: [], backups: [],
;created: [], renamed: []} for UpRollback
UpCopy(src, dest, rollback)
	{
	res := V1Obj({copied: 0, kept: 0, failed: [], backups: [], created: [], renamed: []})
	slots := UpLearnedSlots(dest "\AutoFarmer\learned\cards.txt", src "\AutoFarmer\learned\cards.txt")
	Loop Files, src "\*", "FR"
		{
		rel := SubStr(A_LoopFilePath, StrLen(src) + 2)
		;(set from the release's tag once everything is in place)
		if (rel = "version.txt")
			continue
		target := dest "\" rel
		exists := FileExist(target) != ""
		;(nor one the bot took away itself, making room for a stronger learned hit: learned\slots_written.txt)
		if ((exists && UpIsMine(rel, slots)) || (!exists && InStr(rel, "AutoFarmer\") = 1 && slots.HasKey("file:" Format("{:L}", SubStr(rel, 12)))))
			{
			res.kept++
			continue
			}
		SplitPath(target, , &targetDir)
		V1Do(DirCreate, targetDir)
		if (exists)
			{
			V1Do(DirCreate, RegExReplace(rollback "\" rel, "\\[^\\]*$"))
			V1Do(FileCopy, target, rollback "\" rel, 1)
			if (ErrorLevel)
				{
				res.failed.Push(rel)
				continue
				}
			res.backups.Push(rel)
			}
		V1Do(FileCopy, A_LoopFilePath, target, 1)
		;(in use - a running program: moved aside, deleted next time. A .old still in use - the watcher's own image
		;from an earlier update - can't be replaced: another name)
		if (ErrorLevel && exists)
			{
			old := target ".old"
			if (FileExist(old))
				V1Do(FileDelete, old)
			if (FileExist(old))
				old := target "." A_TickCount ".old"
			V1Do(FileMove, target, old, 1)
			if (!ErrorLevel)
				{
				res.renamed.Push(V1Obj({rel: rel, old: old}))
				V1Do(FileCopy, A_LoopFilePath, target, 1)
				}
			}
		if (ErrorLevel)
			{
			res.failed.Push(rel)
			continue
			}
		if (!exists)
			res.created.Push(rel)
		res.copied++
		}
	return res
	}

;Puts the folder (dest: another) back as it was before UpCopy (rollback: the folder UpCopy was given)
UpRollback(res, dest := "", rollback := "")
	{
	if (dest = "")
		dest := A_ScriptDir
	if (rollback = "")
		rollback := A_Temp "\wiz-maxxing-update\rollback"
	for i, rel in res.created
		V1Do(FileDelete, dest "\" rel)
	for i, r in res.renamed
		{
		V1Do(FileDelete, dest "\" r.rel)
		V1Do(FileMove, r.old, dest "\" r.rel, 1)
		}
	for i, rel in res.backups
		V1Do(FileCopy, rollback "\" rel, dest "\" rel, 1)
	UpLog("put back: " res.backups.Length " file(s) restored, " res.created.Length " new one(s) removed")
	}

;The slots learned cards went into ("balance\hit2", ...), from this folder's and the release's catalog - and the slot
;pictures the bot moved itself (making room for a stronger learned hit: learned\slots_written.txt next to the
;catalog, paths in the AutoFarmer folder) as "file:<path>"
UpLearnedSlots(files*)
	{
	slots := V1Obj()
	for i, f in files
		{
		;(v1: Loop Read of a file that isn't there - or can't be opened - read nothing; v2 throws)
		try
			{
			Loop Read, f
				{
				if (SubStr(A_LoopReadLine, 1, 1) = ";")
					continue
				fld := StrSplit(A_LoopReadLine, "|")
				if (fld.Length >= 8 && fld[8] != "")
					slots[Format("{:L}", fld[8])] := 1
				}
			}
		catch OSError
			{
			}
		SplitPath(f, , &fdir)
		try
			{
			Loop Read, fdir "\slots_written.txt"
				if (Trim(A_LoopReadLine) != "")
					slots["file:" Format("{:L}", Trim(A_LoopReadLine))] := 1
			}
		catch OSError
			{
			}
		}
	return slots
	}

;Files that are yours: kept when they're here already
UpIsMine(rel, slots)
	{
	if (RegExMatch(rel, "i)^AutoFarmer\\(PlayerStats\.txt|dashboard\.ini|resources\\characters\.txt)$"))
		return true
	if (RegExMatch(rel, "i)(^|\\)(learned|routes|backups|generated|dungeons|decks)\\"))
		return true
	if (RegExMatch(rel, "i)^AutoQuester\\resources\\(walk_memory|known_zones)\.txt$"))
		return true
	if (RegExMatch(rel, "i)\.(log|ini)$"))
		return true
	;(a slot picture a card was learned into - in any picture set - and its solid copy)
	if (RegExMatch(rel, "i)^AutoFarmer\\(?:ui[\d.]+\\)?(\w+\\\w+?)(?:\.raw)?\.png$", &m) && slots.HasKey(Format("{:L}", m[1])))
		return true
	;(a slot picture the bot moved there itself: learned\slots_written.txt)
	if (InStr(rel, "AutoFarmer\") = 1 && slots.HasKey("file:" Format("{:L}", SubStr(rel, 12))))
		return true
	return false
	}

;The new release's PlayerStats.txt settings this one doesn't have yet are added at the end (with their
;comment); yours are left as they are
UpMergeStats(newFile, myFile, tag)
	{
	if (!FileExist(myFile) || !FileExist(newFile))
		return
	mine := V1FileRead(myFile)
	have := V1Obj()
	Loop Parse, mine, "`n", "`r"
		if (RegExMatch(A_LoopField, "^\s*([\w.]+)\s*:", &m))
			have[Format("{:L}", m[1])] := 1
	add := "", comment := ""
	;(v1: Loop Read of a file it can't open read nothing; v2 throws)
	try
		{
		Loop Read, newFile
			{
			line := A_LoopReadLine
			if (RegExMatch(line, "^\s*;"))
				{
				comment .= line "`r`n"
				continue
				}
			if (RegExMatch(line, "^\s*([\w.]+)\s*:", &m) && !have.HasKey(Format("{:L}", m[1])))
				add .= comment line "`r`n"
			comment := ""
			}
		}
	catch OSError
		{
		}
	if (add = "")
		return
	V1Do(FileAppend, "`r`n; ---- Added by the update to " tag " (new settings; yours above are kept) ----`r`n" add, myFile)
	UpLog("added new settings to PlayerStats.txt")
	}

;What a past update moved aside (programs that were in use)
UpCleanup()
	{
	Loop Files, A_ScriptDir "\*.old", "FR"
		V1Do(FileDelete, A_LoopFilePath)
	}

;---- GitHub and the token ----

;GET url with the token (or method - POST - with a JSON body); the answer's text, status in status (0 = no answer).
;Sent without waiting and polled, so the time limit holds
UpHttp(url, token, accept, &status, timeoutMs := 8000, method := "GET", body := "")
	{
	status := 0
	try
		{
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open(method, url, true)
		req.SetRequestHeader("User-Agent", "Wiz-Maxxing-updater")
		req.SetRequestHeader("Accept", accept)
		req.SetRequestHeader("X-GitHub-Api-Version", "2022-11-28")
		if (token != "")
			req.SetRequestHeader("Authorization", "Bearer " token)
		if (body != "")
			{
			req.SetRequestHeader("Content-Type", "application/json")
			req.Send(body)
			}
		else
			req.Send()
		t0 := A_TickCount
		while (!req.WaitForResponse(0))
			{
			if (A_TickCount - t0 > timeoutMs)
				{
				req.Abort()
				return ""
				}
			Sleep(20)
			}
		status := req.Status
		return req.ResponseText
		}
	catch
		return ""
	}

;Downloads a release asset (the API sends it on to a storage address, which mustn't get the token)
UpDownload(assetUrl, token, file, &err)
	{
	err := ""
	try
		{
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Option[6] := false
		req.Open("GET", assetUrl, true)
		req.SetRequestHeader("User-Agent", "Wiz-Maxxing-updater")
		req.SetRequestHeader("Accept", "application/octet-stream")
		if (token != "")
			req.SetRequestHeader("Authorization", "Bearer " token)
		req.Send()
		if (!UpWait(req, 20000))
			{
			err := "no answer from GitHub"
			return false
			}
		url := assetUrl
		if (req.Status = 302 || req.Status = 301 || req.Status = 307)
			{
			url := req.GetResponseHeader("Location")
			req := ComObject("WinHttp.WinHttpRequest.5.1")
			req.Open("GET", url, true)
			req.SetRequestHeader("User-Agent", "Wiz-Maxxing-updater")
			req.Send()
			if (!UpWait(req, 180000))
				{
				err := "the download took too long"
				return false
				}
			}
		if (req.Status != 200)
			{
			err := "GitHub answered " req.Status
			return false
			}
		stream := ComObject("ADODB.Stream")
		stream.Type := 1
		stream.Open()
		stream.Write(req.ResponseBody)
		stream.SaveToFile(file, 2)
		stream.Close()
		}
	catch as e
		{
		err := IsObject(e) ? e.Message : e
		return false
		}
	;(v1: FileGetSize of a file that isn't there - blank, and blank > 100000 compared as text: false)
	size := V1Try(FileGetSize, file)
	err := (V1Gt(size, 100000) ? "" : "the file came down empty")
	return V1Gt(size, 100000)
	}

UpWait(req, timeoutMs)
	{
	t0 := A_TickCount
	while (!req.WaitForResponse(0))
		{
		if (A_TickCount - t0 > timeoutMs)
			{
			req.Abort()
			return false
			}
		Sleep(30)
		}
	return true
	}

;The token from Windows Credential Manager ("" none)
UpToken()
	{
	if (UpTestToken != "")
		return UpTestToken
	credPtr := 0, token := ""
	is64 := (A_PtrSize = 8)
	targetW := Buffer((StrLen(UpCredTarget()) + 1) * 2, 0), StrPut(UpCredTarget(), targetW, "UTF-16")
	if (!DllCall("Advapi32\CredReadW", "Ptr", targetW, "UInt", 1, "UInt", 0, "Ptr*", &credPtr) || !credPtr)
		return ""
	blobSize := NumGet(credPtr, is64 ? 32 : 24, "UInt")
	blobPtr := NumGet(credPtr, is64 ? 40 : 28, "Ptr")
	if (blobPtr && blobSize)
		token := StrGet(blobPtr, blobSize // 2, "UTF-16")
	DllCall("Advapi32\CredFree", "Ptr", credPtr)
	return Trim(token)
	}

;Stores the token in Windows Credential Manager. True if it did
UpTokenSave(token)
	{
	is64 := (A_PtrSize = 8)
	user := "github-token"
	targetW := Buffer((StrLen(UpCredTarget()) + 1) * 2, 0), StrPut(UpCredTarget(), targetW, "UTF-16")
	userW := Buffer((StrLen(user) + 1) * 2, 0), StrPut(user, userW, "UTF-16")
	blobSize := StrLen(token) * 2
	blob := Buffer(blobSize + 2, 0), StrPut(token, blob, "UTF-16")
	cred := Buffer(is64 ? 80 : 52, 0)
	NumPut("UInt", 1, cred, 4)                              ;Type: CRED_TYPE_GENERIC
	NumPut("Ptr", targetW.Ptr, cred, 8)                     ;TargetName
	NumPut("UInt", blobSize, cred, is64 ? 32 : 24)          ;CredentialBlobSize
	NumPut("Ptr", blob.Ptr, cred, is64 ? 40 : 28)           ;CredentialBlob
	NumPut("UInt", 2, cred, is64 ? 48 : 32)                 ;Persist: CRED_PERSIST_LOCAL_MACHINE
	NumPut("Ptr", userW.Ptr, cred, is64 ? 72 : 48)          ;UserName
	saved := DllCall("Advapi32\CredWriteW", "Ptr", cred, "UInt", 0)
	DllCall("RtlZeroMemory", "Ptr", blob, "Ptr", blobSize + 2)
	return saved
	}

;Whether a token works: it can see the repo's releases ("" yes, else why not)
UpTokenTest(token)
	{
	UpHttp(UpApi() "/repos/" UpRepo() "/releases/latest", token, "application/vnd.github+json", &status, 8000)
	return status = 200 ? "" : status = 401 ? "GitHub doesn't accept that token (401)" : status = 404 ? "the token can't see the Wiz-Maxxing repo (404) - give it access to that repository" : status = 403 ? "GitHub refused it (403)" : status = 0 ? "no answer from GitHub (offline?)" : "GitHub answered " status
	}

;---- bug reports ----

;Posts a bug report as an issue on the repo - the dashboard's "Report a bug" (BugReport.ahk) runs Wiz-Maxxing.exe
;/report <file>. file: its first line the title, the rest the issue's text (GitHub markdown). The answer goes in
;<file>.result: "ok|<issue number>|<its address>" or "err|<why not>". The token needs Issues: Read and write on the repo
UpReport(file)
	{
	if (file = "")
		return
	ans := UpReportPost(file)
	;(v1's FileOpen gave no object when it couldn't open it - v2 throws)
	out := V1Try(FileOpen, file ".result", "w", "UTF-8")
	if (IsObject(out))
		out.Write(ans), out.Close()
	}

UpReportPost(file)
	{
	src := V1Try(FileOpen, file, "r", "UTF-8")
	if (!IsObject(src))
		return "err|the report's file couldn't be read"
	all := StrReplace(src.Read(), "`r", ""), src.Close()
	nl := InStr(all, "`n")
	head := Trim(nl ? SubStr(all, 1, nl - 1) : all), text := nl ? SubStr(all, nl + 1) : ""
	if (head = "")
		return "err|it has no title"
	token := UpToken()
	if (token = "")
		return "err|there's no GitHub token on this PC (Setup.exe: tick GitHub updates)"
	;(GitHub takes 65536 characters at most - not cut in the middle of a character made of two)
	cut := 65000
	if (StrLen(text) > cut && (NumGet(StrPtr(text), (cut - 1) * 2, "UShort") & 0xFC00) = 0xD800)
		cut -= 1
	json := '{"title": "' UpJson("Bug: " SubStr(head, 1, 200)) '", "body": "' UpJson(SubStr(text, 1, cut)) '", "labels": ["bug"]}'
	resp := UpHttp(UpApi() "/repos/" UpRepo() "/issues", token, "application/vnd.github+json", &status, 20000, "POST", json)
	token := ""
	if (status = 201 && RegExMatch(resp, '"number":\s*(\d+)', &m))
		{
		RegExMatch(resp, '"html_url":\s*"([^"]+/issues/\d+)"', &u)
		UpLog("Bug report sent: issue #" m[1])
		;(v1's u1: blank when it didn't match - V1At)
		return "ok|" m[1] "|" V1At(u, 1)
		}
	why := status = 401 ? "GitHub refused the token (401) - it may have expired: make a new one and add it with Setup.exe"
		: (status = 403 && InStr(resp, "rate limit")) ? "GitHub's limit for now (403) - try again in a while"
		: (status = 403 || status = 404) ? "the token can't make issues (" status "). github.com > Settings > Developer settings > Fine-grained tokens > the Wiz-Maxxing token > Edit > Issues: Read and write > Update, then Send again"
		: status = 410 ? "issues are off on the repo (GitHub: the repo's Settings > General > Features > Issues)"
		: status = 0 ? "no answer from GitHub (offline?)"
		: "GitHub answered " status
	UpLog("Bug report not sent: " why)
	return "err|" why
	}

;s for a JSON string, in ASCII: backslash, quote, line ends and tabs escaped, other control characters a space, the rest
;past ASCII as \uXXXX (so how WinHttp encodes the text doesn't matter)
UpJson(s)
	{
	s := StrReplace(s, "\", "\\"), s := StrReplace(s, '"', '\"'), s := StrReplace(s, "`r", "")
	s := StrReplace(s, "`n", "\n"), s := StrReplace(s, "`t", "\t")
	if (!RegExMatch(s, "[^\x20-\x7E]"))
		return s
	out := ""
	Loop StrLen(s)
		{
		c := NumGet(StrPtr(s), (A_Index - 1) * 2, "UShort")
		out .= (c >= 0x20 && c <= 0x7E) ? Chr(c) : (c < 0x20) ? " " : Format("\u{:04X}", c)
		}
	return out
	}

UpUnescape(s)
	{
	s := StrReplace(s, "\r\n", "`n"), s := StrReplace(s, "\n", "`n"), s := StrReplace(s, "\r", "")
	s := StrReplace(s, '\"', '"'), s := StrReplace(s, "\/", "/"), s := StrReplace(s, "\t", "`t")
	return StrReplace(s, "\\", "\")
	}

UpLog(text)
	{
	now := FormatTime(, "yyyy-MM-dd HH:mm:ss")
	V1Do(FileAppend, now " " text "`r`n", A_ScriptDir "\updater.log")
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
UpdaterBlank()
	{
	global UpTestApi := "", UpTestToken := "", UpTestYes := "", UpQuiet := "", UpBotsClosed := "", UpHandedOver := "", UpHandArgs := ""
	}
