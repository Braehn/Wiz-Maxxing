#Warn Unreachable, Off
; BugReport.ahk - "Report a bug" (the dashboard's Help menu, the tray menu): a window where you say what went wrong.
; Send posts it as an issue on the Wiz-Maxxing repo on GitHub, with the bot's version and setup, what the dashboard's
; STATISTICS and WHAT IT SEES show, and the end of debug.log and of vision\vision.log (the vision helper's own log).
; AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Wiz-Maxxing.exe /report posts it (Updater.ahk UpReport), with the GitHub token in Windows Credential Manager - this
; never reads the token. The token needs Issues: Read and write on the repo, besides Contents for updates. The report
; waits in reports\ until Wiz-Maxxing answers: reports\report_<time>.txt (its first line the title), the answer in
; reports\report_<time>.txt.result. What looks secret (a Discord webhook, a GitHub token, a password=...) is blanked
; out of all of it. Closing the window keeps what you typed until it's sent.

;The window and its controls (vBugTitle...); the report waiting for Wiz-Maxxing's answer ("" none) and when it went
global BugHwnd, BugTitle, BugText, BugAddLog, BugSendBtn, BugStatus, BugFile, BugSentAt

;Opens the window (made once: what you typed stays when it's closed)
BugShow()
	{
	if (!BugHwnd)
		{
		BugBuild()
		;(the first time: next to the dashboard when it's up)
		bugPos := ""
		if (DashHwnd && DashShown)
			{
			;(v1: a window that isn't there - blank, no error; v2's WinGetPos unsets its output variables before it
			;throws - the blanks are set in the catch)
			bugMm := V1Try(WinGetMinMax, "ahk_id " DashHwnd)
			try WinGetPos(&bugDx, &bugDy, , , "ahk_id " DashHwnd)
			catch
				bugDx := "", bugDy := ""
			if (bugDx != "" && bugMm != -1)
				bugPos := "x" bugDx + 60 " y" bugDy + 80 " "
			}
		Bug.Title := "Wizard101 bot " BotVersion() " - report a bug"
		Bug.Show(bugPos "AutoSize")
		}
	else
		Bug.Show()
	Bug["BugText"].Focus()
	}

;Makes the window (not shown)
BugBuild()
	{
	global Bug, BugHwnd ; (v1 globals it sets)
	Bug := Gui("-MaximizeBox", "Wizard101 bot " BotVersion() " - report a bug"), BugHwnd := Bug.Hwnd
	Bug.OnEvent("Close", BugGuiClose)
	Bug.OnEvent("Escape", BugGuiEscape)
	Bug.BackColor := "1B1D22"
	;(v1's Gui Color's second colour, 111317, was the Edit controls' background - v2: their Background option)
	Bug.MarginX := 12, Bug.MarginY := 10
	Bug.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Bug.Add("Text", "x12 y12 w560 h18", "REPORT A BUG")
	Bug.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Bug.Add("Text", "x12 y34 w560 h32", "What went wrong, and what was the bot doing? Send posts it as an issue on the Wiz-Maxxing repo on GitHub, with the bot's version and what the dashboard shows.")
	Bug.SetFont("s9 w400 cDADADA", "Segoe UI")
	Bug.Add("Text", "x12 y74 w560 h18", "Title (a few words)")
	Bug.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditBugTitle := Bug.Add("Edit", "x12 y94 w560 h24 Limit120 vBugTitle Background111317")
	Bug.SetFont("s9 w400 cDADADA", "Segoe UI")
	Bug.Add("Text", "x12 y128 w560 h18", "What happened")
	Bug.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditBugText := Bug.Add("Edit", "x12 y148 w560 h220 Multi +VScroll Limit20000 vBugText Background111317")
	Bug.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcCheckboxBugAddLog := Bug.Add("Checkbox", "x12 y378 w560 h18 Checked vBugAddLog", "Add the end of debug.log (the last few hundred lines) and of vision\vision.log")
	Bug.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonBugSendBtn := Bug.Add("Button", "x12 y406 w90 h26 vBugSendBtn", "Send")
	ogcButtonBugSendBtn.OnEvent("Click", BugSend.Bind("Normal"))
	ogcButtonClose := Bug.Add("Button", "x+8 yp w90 h26", "Close")
	ogcButtonClose.OnEvent("Click", BugGuiClose.Bind("Normal"))
	;(the status under the buttons, room for three lines - the way to fix the token takes two)
	Bug.SetFont("s9 w400 cB9E2B9", "Segoe UI")
	ogcTextBugStatus := Bug.Add("Text", "x12 y440 w560 h48 vBugStatus")
	}

;Send: the report written to reports\ and Wiz-Maxxing started to post it; BugPoll waits for its answer
BugSendNow()
	{
	global BugFile, BugSentAt ; (v1 globals it sets)
	V1GuiSubmit(Bug, false)
	if (BugFile != "")
		return
	bugWhat := Trim(BugText, " `t`r`n")
	if (StrLen(bugWhat) < 5)
		return BugSay("Say what went wrong first.")
	bugHead := Trim(BugTitle, " `t`r`n")
	if (bugHead = "")
		bugHead := SubStr(Trim(V1At(StrSplit(bugWhat, "`n"), 1), " `t`r"), 1, 80)
	;(Wiz-Maxxing posts it: the exe - or, run as a script, Wiz-Maxxing.ahk by this AutoHotkey)
	if (A_IsCompiled && !FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe"))
		return BugSay("Not sent: Wiz-Maxxing.exe isn't in the bot's folder (it sends the report).")
	V1Do(DirCreate, A_ScriptDir "\reports")
	bugStamp := FormatTime(, "yyyyMMdd_HHmmss")
	bugF := A_ScriptDir "\reports\report_" bugStamp ".txt"
	V1Do(FileDelete, bugF ".result")
	;(v1's FileOpen gave no object when it couldn't open the file; v2 throws)
	bugOut := V1Try(FileOpen, bugF, "w", "UTF-8")
	if (!IsObject(bugOut))
		return BugSay("Not sent: couldn't write " bugF)
	bugOut.Write(BugRedact(StrReplace(bugHead, "`n", " ")) "`n" BugBody(bugWhat, BugAddLog))
	bugOut.Close()
	if (!BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/report `"" bugF "`"", A_ScriptDir "\.."))
		{
		bugErr := A_LastError
		V1Do(FileDelete, bugF)
		return BugSay("Not sent: Wiz-Maxxing couldn't be started (error " bugErr ").")
		}
	BugFile := bugF, BugSentAt := A_TickCount
	Bug["BugSendBtn"].Enabled := false
	BugSay("Sending...")
	SetTimer(BugPoll,500)
	}

;Wiz-Maxxing's answer (BugSendNow's report): "ok|<issue number>|<address>" or "err|<why>" - none in 45 s: given up
BugPollNow()
	{
	global BugFile ; (v1 globals it sets)
	if (BugFile = "")
		{
		SetTimer(BugPoll,0)
		return
		}
	bugAns := ""
	if (FileExist(BugFile ".result"))
		{
		bugIn := V1Try(FileOpen, BugFile ".result", "r", "UTF-8")
		if (IsObject(bugIn))
			bugAns := Trim(bugIn.Read(), " `t`r`n"), bugIn.Close()
		}
	;(not there yet - or not written all the way: looked at again)
	if (bugAns = "")
		{
		if (A_TickCount - BugSentAt < 45000)
			return
		bugAns := "err|no answer from Wiz-Maxxing in 45 s"
		}
	SetTimer(BugPoll,0)
	V1Do(FileDelete, BugFile ".result")
	V1Do(FileDelete, BugFile)
	BugFile := ""
	Bug["BugSendBtn"].Enabled := true
	bugP := StrSplit(bugAns, "|", , 3)
	;(v1: a part that isn't there - blank)
	if (bugP[1] = "ok")
		{
		Bug["BugTitle"].Value := ""
		Bug["BugText"].Value := ""
		BugSay("Sent: issue #" V1At(bugP, 2) " on GitHub. Thanks!")
		DebugLog("Bug report sent: issue #" V1At(bugP, 2) " on GitHub")
		return
		}
	bugWhy := (bugP[1] = "err" && V1At(bugP, 2) != "") ? bugP[2] : bugAns
	BugSay("Not sent: " bugWhy ". What you typed is still here.")
	DebugLog("Bug report not sent: " bugWhy)
	}

;The window's status line
BugSay(msg)
	{
	Bug["BugStatus"].Text := msg
	return ""
	}

;The issue's text (GitHub markdown): what you wrote; the bot's version and setup; what the dashboard's STATISTICS and
;WHAT IT SEES show now; and (addLog) as much of the end of debug.log as GitHub's 65536 characters leave room for, then
;the end of vision\vision.log (BugVisionTail). What looks secret is blanked out (BugRedact)
BugBody(what, addLog)
	{
	global DashShown ; (v1 globals it sets)
	;(the dashboard hidden: its texts aren't kept up - made now, the window staying hidden)
	if (DashHwnd && !DashShown && V1IsFunc("DashRefresh"))
		{
		Critical()
		DashShown := 1
		DashRefresh.Call()
		DashShown := 0
		Critical("Off")
		}
	bugNow := FormatTime(, "yyyy-MM-dd HH:mm:ss")
	bugB := what "`n`n---`n**" BotVersion() "** - " bugNow " - PC " A_ComputerName " - screen " A_ScreenWidth "x" A_ScreenHeight
		. " - UI " UiScale " - " (BotOn ? "bot on" : "bot off") (Walking ? ", walking" : "") (school != "" ? " - " school : "") "`n"
	;(v1's GuiControlGet: blank when the dashboard isn't there)
	bugStats := V1Try((*) => Dash["DashStatText"].Text)
	bugSees := V1Try((*) => Dash["DashSeeText"].Text)
	if (Trim(bugStats) != "")
		bugB .= BugFold("Statistics", bugStats)
	if (Trim(bugSees) != "")
		bugB .= BugFold("What it sees", bugSees)
	;(the log gets what's left: its fold's own lines, and what blanking out may add, kept free - debug.log is ANSI, a
	;byte a character)
	bugRoom := 64000 - StrLen(bugB) - 300
	if (addLog && bugRoom > 1000)
		{
		;(vision.log's end made first - a quarter of the room at most - and debug.log's gets the rest; shown after it)
		bugVis := BugVisionTail(Min(bugRoom // 4, 8000), &bugVisLines)
		bugVisFold := bugVis != "" ? BugFold("vision\vision.log, its last " bugVisLines " lines", bugVis) : ""
		bugLog := BugLogTail(Min(bugRoom - StrLen(bugVisFold), 45000), &bugLines)
		if (bugLog != "")
			bugB .= BugFold("debug.log, its last " bugLines " lines", bugLog)
		bugB .= bugVisFold
		}
	return BugRedact(bugB)
	}

;A folded block of text in the issue (title: what's on its fold)
BugFold(title, text)
	{
	bugFence := Chr(96) Chr(96) Chr(96)
	;(a fence in the text would end the block early)
	return "`n<details><summary>" title "</summary>`n`n" bugFence "text`n" StrReplace(Trim(StrReplace(text, "`r", ""), "`n"), bugFence, "'''") "`n" bugFence "`n</details>`n"
	}

;The end of debug.log: up to maxBytes, from the start of a line; lines: how many
BugLogTail(maxBytes, &lines)
	{
	lines := 0
	bugIn := V1Try(FileOpen, A_ScriptDir "\debug.log", "r")
	if (!IsObject(bugIn))
		return ""
	bugSize := bugIn.Length
	if (bugSize > maxBytes)
		bugIn.Seek(bugSize - maxBytes)
	bugT := bugIn.Read()
	bugIn.Close()
	;(from somewhere in a line: from the next one)
	if (bugSize > maxBytes)
		bugT := SubStr(bugT, InStr(bugT, "`n") + 1)
	bugT := StrReplace(bugT, "`r", "")
	StrReplace(Trim(bugT, "`n"), "`n", "`n", , &lines)
	lines += (Trim(bugT, "`n") != "")
	return bugT
	}

;The end of vision\vision.log (the vision helper's own log - why it stopped at start, the game's memory reads; UTF-8):
;its last 40 lines, up to maxBytes, from the start of a line; lines: how many
BugVisionTail(maxBytes, &lines)
	{
	lines := 0
	bugIn := V1Try(FileOpen, A_ScriptDir "\vision\vision.log", "r", "UTF-8")
	if (!IsObject(bugIn))
		return ""
	bugSize := bugIn.Length
	if (bugSize > maxBytes)
		bugIn.Seek(bugSize - maxBytes)
	bugT := bugIn.Read()
	bugIn.Close()
	;(from somewhere in a line: from the next one)
	if (bugSize > maxBytes)
		bugT := SubStr(bugT, InStr(bugT, "`n") + 1)
	bugT := Trim(StrReplace(bugT, "`r", ""), "`n")
	if (bugT = "")
		return ""
	bugL := StrSplit(bugT, "`n")
	bugFrom := Max(1, bugL.Length - 39)
	bugT := ""
	Loop bugL.Length - bugFrom + 1
		bugT .= bugL[bugFrom + A_Index - 1] "`n"
	lines := bugL.Length - bugFrom + 1
	return bugT
	}

;s with what looks secret blanked out: Discord webhook addresses, GitHub tokens, "Bearer ..." and password= / token= /
;secret= values
BugRedact(s)
	{
	s := RegExReplace(s, "i)https?://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\S+", "[a Discord webhook - left out]")
	s := RegExReplace(s, "\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,})", "[a GitHub token - left out]")
	s := RegExReplace(s, "i)\bBearer\s+\S+", "Bearer [left out]")
	;(the network PIN: "netpin 0 -> 1234" and "netpin (0 to 99999999: 99999999)" as the Settings window's Save logged
	;them before v1.10.0, or a netpin:1234 line)
	s := RegExReplace(s, "i)\bnetpin\b(?:\s*\(-?\d+ to -?\d+: -?\d+\)|[\s:]*-?\d+(?:\s*->\s*-?\d+)?)", "netpin [left out]")
	return RegExReplace(s, "i)\b(password|passwd|pwd|token|secret)(\s*[=:]\s*)\S+", "$1$2[left out]")
	}

BugSend:
BugSend()
	return

BugPoll:
BugPoll()
	return

;(closing it keeps what you typed - and a report on its way is still answered)
BugGuiClose:
BugGuiClose()
return
BugGuiEscape:
BugGuiEscape()
	return

;###############  (v2 port: v1's labels, as functions)  ###############
BugSend(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	BugSendNow()
	return
}
;##############################################
BugPoll() { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	BugPollNow()
	return
}
;##############################################
BugGuiClose(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
global
BugGuiEscape()
}
;##############################################
BugGuiEscape(*) { ; (v1: a label - its code ran in the global scope)
	global
	Bug.Hide()
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
BugReportBlank()
	{
	global BugHwnd := "", BugTitle := "", BugText := "", BugAddLog := "", BugSendBtn := "", BugStatus := "", BugFile := "", BugSentAt := ""
	}
