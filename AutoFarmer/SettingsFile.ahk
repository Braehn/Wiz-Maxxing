; SettingsFile.ahk - the dashboard's File menu: Save settings as... writes every setting of the Settings window to a
; file of your own (to keep, or for another PC); Load settings from... reads one - or another PC's PlayerStats.txt -,
; shows what it would change and sets only the ones you tick. AutoHotkey v2; functions only; #Included by
; Autofarmer.ahk. The settings and their checks are Settings.ahk's (CfgList), and so is setting them (CfgApply): this
; file reaches those, and every other file's functions, through V1IsFunc. Never in a settings file: your stats, the
; cards the bot learned, the network PIN (netpin), the Discord webhook and the Wizard101 login (those two aren't in
; PlayerStats.txt either - Credential Manager has them). debug.log gets a file's name only, never where it is.

;File > Save settings as...: a file picked (Documents, today's date in its name - .txt added to a name without one),
;every setting of the Settings window written to it in CfgList's order under its headings, as PlayerStats.txt has them
;(CfgFileText). Not over PlayerStats.txt, dashboard.ini or party.ini in the bot's folder
CfgSaveAs()
	{
	if (!V1IsFunc("CfgList"))
		return
	;(its boxes over the dashboard - a menu pick of yours: they may take the focus)
	csaDash := CfgFileDash()
	if (IsObject(csaDash))
		csaDash.Opt("+OwnDialogs")
	;(the dialog may move the working folder - CfgWrite and LoadStats go by it: put back)
	csaWd := A_WorkingDir
	try
		csaPath := FileSelect("S16", A_MyDocuments "\Wiz-Maxxing settings " FormatTime(, "yyyy-MM-dd") ".txt", "Save settings as", "Settings (*.txt)")
	catch
		csaPath := ""
	SetWorkingDir(csaWd)
	if (csaPath = "")
		return
	SplitPath(csaPath, , , &csaExt)
	csaAsk := false
	if (csaExt = "")
		csaPath := RTrim(csaPath, ". ") ".txt", csaAsk := true
	SplitPath(csaPath, &csaName)
	if (CfgFileOurs(csaPath))
		{
		MsgBox(csaName " is one of the bot's own files - save the settings under another name.", "Wizard101 bot - save settings", "Icon!")
		return
		}
	;(the dialog asked about the name as typed - with .txt added, it's asked here)
	if (csaAsk && FileExist(csaPath) && MsgBox(csaName " is there already. Replace it?", "Wizard101 bot - save settings", "YesNo Icon! Default2") != "Yes")
		return
	csaText := CfgFileText(&csaCount)
	if (!CfgFileWrite(csaPath, csaText))
		{
		CfgFileLog("Settings: couldn't write " csaName " - nothing was saved")
		MsgBox("Couldn't write " csaName " - nothing was saved.", "Wizard101 bot - save settings", "Icon!")
		return
		}
	CfgFileLog("Settings saved in " csaName " - " csaCount " settings (not the network PIN)")
	TrayTip(csaCount " settings saved in " csaName ".", "Wizard101 bot", 1)
	}

;File > Load settings from...: a file picked (one Save settings as wrote - or another PC's PlayerStats.txt: only the
;settings in it are taken), read and checked as the Settings window checks them (CfgFileParse), and the ones that
;would change shown in a window of their own (CfgFileShow): set only if you tick them and Apply. A setting the file
;doesn't have stays as it is. Not while the Settings window is open
CfgLoadFrom()
	{
	if (!V1IsFunc("CfgList") || !V1IsFunc("CfgApply"))
		return
	;(its boxes over the dashboard - a menu pick of yours: they may take the focus)
	clfDash := CfgFileDash()
	if (IsObject(clfDash))
		clfDash.Opt("+OwnDialogs")
	;(one at a time: a window of an earlier load still open goes)
	clfOld := CfgFileWin()
	if (IsObject(clfOld))
		{
		try clfOld.Destroy()
		CfgFileWin("")
		}
	if (CfgFileCfgOpen())
		{
		MsgBox("Close the Settings window first - then load the settings.", "Wizard101 bot - load settings", "Icon!")
		return
		}
	;(the dialog may move the working folder - CfgWrite and LoadStats go by it: put back)
	clfWd := A_WorkingDir
	try
		clfPath := FileSelect(3, A_MyDocuments, "Load settings from", "Settings (*.txt)")
	catch
		clfPath := ""
	SetWorkingDir(clfWd)
	if (clfPath = "")
		return
	SplitPath(clfPath, &clfName)
	try
		clfSize := FileGetSize(clfPath)
	catch
		clfSize := -1
	if (clfSize < 0 || clfSize > 256 * 1024)
		{
		MsgBox(clfName (clfSize < 0 ? " couldn't be read" : " is too big for a settings file (over 256 KB)") " - nothing was loaded.", "Wizard101 bot - load settings", "Icon!")
		return
		}
	try
		clfText := FileRead(clfPath, "UTF-8")
	catch
		{
		MsgBox(clfName " couldn't be read - nothing was loaded.", "Wizard101 bot - load settings", "Icon!")
		return
		}
	;(a BOM, and CRLF, LF or CR line ends - as whatever editor saved it)
	if (SubStr(clfText, 1, 1) = Chr(0xFEFF))
		clfText := SubStr(clfText, 2)
	clfGot := CfgFileParse(StrReplace(StrReplace(clfText, "`r`n", "`n"), "`r", "`n"))
	if (!clfGot.known)
		{
		CfgFileLog("Settings: " clfName " isn't a settings file - nothing loaded")
		MsgBox(clfName " isn't a settings file - none of the Settings window's settings is in it. Nothing was loaded.", "Wizard101 bot - load settings", "Icon!")
		return
		}
	clfItems := CfgFileChanges(clfGot)
	clfNotes := CfgFileNotes(clfGot, clfItems)
	if (!clfItems.Length)
		{
		;(the notes say a value it can't take, or the network PIN, isn't loaded: so the box speaks of what it can load)
		clfWhat := (clfGot.rejected.Count || clfGot.pin) ? "every setting it can load from " : "every setting in "
		CfgFileLog("Settings: " clfName " read - nothing it can load would change a setting")
		MsgBox("Nothing to change: " clfWhat clfName " is as it's set now." (clfNotes = "" ? "" : "`n`n" clfNotes), "Wizard101 bot - load settings", "Iconi")
		return
		}
	CfgFileLog("Settings: " clfName " read - " clfItems.Length " setting" (clfItems.Length = 1 ? "" : "s") " it would change, shown to tick")
	CfgFileShow(clfName, clfItems, clfNotes)
	}

;The window that shows what a settings file would change (CfgLoadFrom) - name: the file's name, items: CfgFileChanges',
;notes: CfgFileNotes'. Each setting with its label, as it's set now and as the file has it, ticked to be set (not the
;party's two). Apply sets the ticked ones (CfgFileApply), Cancel nothing. Owned by the dashboard
CfgFileShow(name, items, notes)
	{
	cfsDash := CfgFileDash()
	cfsWin := Gui((IsObject(cfsDash) ? "+Owner" cfsDash.Hwnd " " : "") "-MinimizeBox -MaximizeBox", "Wizard101 bot " CfgFileVersion() " - load settings")
	cfsData := {name: name, items: items, busy: 0}
	cfsWin.OnEvent("Close", CfgFileCancel.Bind(cfsData))
	cfsWin.OnEvent("Escape", CfgFileCancel.Bind(cfsData))
	cfsWin.BackColor := "1B1D22"
	cfsWin.MarginX := 12, cfsWin.MarginY := 10
	cfsWin.SetFont("s9 w400 cDADADA", "Segoe UI")
	;(0x80: an & in a name shown as it is)
	cfsWin.Add("Text", "x12 y10 w620 +0x80", name ": " items.Length " setting" (items.Length = 1 ? "" : "s") " not as they're set now. The ticked ones are set when you Apply - used at once, no restart.")
	;(NoSort: row n stays items[n])
	cfsLv := cfsWin.Add("ListView", "x12 y+8 w620 r" Min(14, Max(4, items.Length)) " Checked NoSort -Multi Background111317 cDADADA vCfgFileList", ["Setting", "Now", "From the file"])
	for each, cfsIt in items
		cfsLv.Add(cfsIt.tick ? "Check" : "", CfgFileLabel(cfsIt.s), CfgFileShown(cfsIt.s, cfsIt.now), CfgFileShown(cfsIt.s, cfsIt.from))
	cfsLv.ModifyCol(1, 330), cfsLv.ModifyCol(2, 130), cfsLv.ModifyCol(3, 130)
	if (notes != "")
		{
		cfsWin.SetFont("s9 w400 c9AA0A6", "Segoe UI")
		cfsWin.Add("Text", "x12 y+8 w620 +0x80", notes)
		}
	cfsWin.SetFont("s9 w400 c000000", "Segoe UI")
	cfsWin.Add("Button", "x12 y+10 w90 h26 Default", "Apply").OnEvent("Click", CfgFileApply.Bind(cfsData))
	cfsWin.Add("Button", "x+8 yp w90 h26", "Cancel").OnEvent("Click", CfgFileCancel.Bind(cfsData))
	CfgFileWin(cfsWin)
	cfsWin.Show("AutoSize")
	}

;Apply in that window: PlayerStats.txt kept as it is in backups\ (as CardLearn.ahk keeps what it changes), then the
;ticked settings not as the file has them now set (CfgApply - the bot or the tray menu may have changed one since the
;window opened), and a short note of what was done. Not while the Settings window is open
CfgFileApply(cfaData, cfaCtl, *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (cfaData.busy)
		return
	cfaWin := cfaCtl.Gui
	cfaWin.Opt("+OwnDialogs")
	if (CfgFileCfgOpen())
		{
		MsgBox("Close the Settings window first - then Apply.", "Wizard101 bot - load settings", "Icon!")
		return
		}
	cfaLv := cfaWin["CfgFileList"]
	cfaTicked := [], cfaRow := 0
	while (cfaRow := cfaLv.GetNext(cfaRow, "C"))
		if (cfaRow <= cfaData.items.Length)
			cfaTicked.Push(cfaData.items[cfaRow])
	if (!cfaTicked.Length)
		{
		MsgBox("Nothing is ticked - tick the settings to set, or Cancel.", "Wizard101 bot - load settings", "Iconi")
		return
		}
	cfaData.busy := 1
	cfaStats := A_WorkingDir "\PlayerStats.txt", cfaBack := ""
	if (FileExist(cfaStats))
		{
		cfaBack := "PlayerStats before settings load " FormatTime(, "yyyy-MM-dd HHmmss") ".txt"
		try
			{
			if (!DirExist(A_WorkingDir "\backups"))
				DirCreate(A_WorkingDir "\backups")
			FileCopy(cfaStats, A_WorkingDir "\backups\" cfaBack, 1)
			}
		catch
			{
			cfaData.busy := 0
			CfgFileLog("Settings: couldn't copy PlayerStats.txt to backups - nothing loaded from " cfaData.name)
			MsgBox("Couldn't keep a copy of PlayerStats.txt in backups - nothing was loaded.", "Wizard101 bot - load settings", "Icon!")
			return
			}
		}
	;(not halfway through while the bot writes PlayerStats.txt itself - no box while it's held)
	Critical()
	cfaPairs := V1Obj()
	for each, cfaIt in cfaTicked
		{
		cfaNow := Stats.Has(cfaIt.key) ? Stats[cfaIt.key] : cfaIt.s.def
		if (!V1IsNum(cfaNow) || cfaNow + 0 != cfaIt.from)
			cfaPairs[cfaIt.key] := cfaIt.from
		}
	cfaOk := true
	if (cfaPairs.Count)
		cfaOk := V1IsFunc("CfgApply") ? CfgApply.Call(cfaPairs, "Settings loaded from " cfaData.name, cfaBack = "" ? "" : "PlayerStats.txt as it was: backups\" cfaBack) : false
	Critical("Off")
	try cfaWin.Destroy()
	CfgFileWin("")
	cfaDash := CfgFileDash()
	if (IsObject(cfaDash))
		cfaDash.Opt("+OwnDialogs")
	if (!cfaOk)
		MsgBox("Couldn't write PlayerStats.txt - nothing was loaded.", "Wizard101 bot - load settings", "Icon!")
	else if (!cfaPairs.Count)
		MsgBox("Nothing changed: the ticked settings are as " cfaData.name " has them already.", "Wizard101 bot - load settings", "Iconi")
	else
		MsgBox(cfaPairs.Count " setting" (cfaPairs.Count = 1 ? "" : "s") " loaded from " cfaData.name " - used from now on." (cfaBack = "" ? "" : "`n`nPlayerStats.txt as it was is in backups\" cfaBack "."), "Wizard101 bot - load settings", "Iconi")
	}

;Cancel, the window's X or Esc: closed, nothing set
CfgFileCancel(cfxData, cfxWhat, *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(Apply at work: it closes the window itself)
	if (cfxData.busy)
		return true
	cfxWin := (cfxWhat is Gui) ? cfxWhat : cfxWhat.Gui
	try cfxWin.Destroy()
	CfgFileWin("")
	CfgFileLog("Settings: loading " cfxData.name " cancelled - nothing changed")
	}

;What Save settings as writes: a line saying what saved it and when, one saying what isn't in it, then CfgList's
;headings and settings in its order - key:value with its label as a comment, the value as it's stored (quicksell:2
;stays 2). Not the network PIN. mobradius / mobbody: the reach you set yourself (their floor), not what the bot
;learned on top (Vision.ahk MobGrow). Every line a comment or one LoadStats can read. ASCII, CRLF line ends. cftCount:
;how many settings
CfgFileText(&cftCount)
	{
	cftOut := "; Wiz-Maxxing settings file 1 - saved by Wizard101 bot " CfgFileVersion() " on " FormatTime(, "yyyy-MM-dd HH:mm") "`r`n"
		. "; Not in it: your stats, the cards the bot learned, the settings kept only in PlayerStats.txt, the network PIN, the Discord webhook and the login.`r`n"
		. "; The dashboard's File > Load settings from... reads it - only the settings you tick there are set.`r`n"
	cftCount := 0
	for each, cftS in CfgList.Call()
		{
		if (cftS.key = "-")
			{
			cftOut .= "`r`n; ---- " CfgFileAscii(cftS.label) " ----`r`n"
			continue
			}
		if (!cftS.Has("def") || cftS.key = "netpin")
			continue
		cftV := Stats.Has(cftS.key) ? Stats[cftS.key] : cftS.def
		if ((cftS.key = "mobradius" || cftS.key = "mobbody") && Stats.Has(cftS.key "floor") && V1IsNum(Stats[cftS.key "floor"]))
			cftV := Stats[cftS.key "floor"]
		cftT := CfgFileNum(cftV)
		if (cftT = "")
			continue
		;(Chr(59): the comment's semicolon - a space before one in a string would start a comment here)
		cftOut .= cftS.key ":" cftT "   " Chr(59) " " CfgFileAscii(cftS.label) "`r`n"
		cftCount += 1
		}
	return cftOut
	}

;text written to path whole: a .tmp beside it first, then moved over it - once more after 200 ms if that fails (a
;program reading the file just then). As it is, no BOM. False if it couldn't be written
CfgFileWrite(path, text)
	{
	try
		{
		cfwF := FileOpen(path ".tmp", "w", "UTF-8-RAW")
		cfwF.Write(text)
		cfwF.Close()
		}
	catch
		{
		cfwF := ""
		try FileDelete(path ".tmp")
		return false
		}
	Loop 2
		{
		try
			{
			FileMove(path ".tmp", path, 1)
			return true
			}
		if (A_Index = 1)
			Sleep(200)
		}
	try FileDelete(path ".tmp")
	return false
	}

;A settings file's text read - its lines as LoadStats reads PlayerStats.txt's (ParseStat's pattern), into a list of
;its own (ParseStat sets Stats): {vals: {key: value} - the settings it can set, checked as the Settings window checks
;them, the last line of a key deciding; fixed / rejected: {key: what was wrong}; skipped: keys not in the Settings
;window, in the file's order, each once; bad: lines it couldn't read (badLines: the first 2); known: setting lines
;seen; pin: netpin in it; version: the bot that saved it ("" without Save settings as' first line)}. Never taken:
;netpin, a CharID, the *floor lines (CfgApply writes them) - but the mobs' reach's floor taken as its value: the reach
;you set yourself, not the one the bot widened it to (Vision.ahk MobGrow) - a PlayerStats.txt from another PC holds both
CfgFileParse(text)
	{
	cfpGot := {vals: V1Obj(), fixed: V1Obj(), rejected: V1Obj(), skipped: [], bad: 0, badLines: [], known: 0, pin: 0, version: ""}
	cfpBy := V1Obj(), cfpSeen := V1Obj(), cfpFloor := V1Obj()
	for each, cfpS in CfgList.Call()
		if (cfpS.Has("def"))
			cfpBy[cfpS.key] := cfpS
	Loop Parse, text, "`n", "`r"
		{
		cfpLn := A_LoopField
		if (cfpGot.version = "" && RegExMatch(cfpLn, "i)^\s*;\s*Wiz-Maxxing settings file\b") && RegExMatch(cfpLn, "bot (v[\d.]+)", &cfpM))
			cfpGot.version := RTrim(cfpM[1], ".")
		cfpCode := RegExReplace(cfpLn, ";.*")
		if (Trim(cfpCode) = "")
			continue
		if (!RegExMatch(cfpCode, "^\s*([\w.]+)\s*:\s*(-?\d+(?:\.\d+)?)\s*\x25?\s*$", &cfpM))
			{
			cfpGot.bad += 1
			if (cfpGot.badLines.Length < 2)
				cfpGot.badLines.Push(SubStr(Trim(RegExReplace(cfpCode, "[^\x20-\x7E]", "?")), 1, 40))
			continue
			}
		cfpKey := StrLower(cfpM[1]), cfpRaw := cfpM[2]
		if (cfpKey = "netpin")
			{
			cfpGot.pin := 1
			continue
			}
		if (cfpKey = "mobradiusfloor" || cfpKey = "mobbodyfloor")
			{
			cfpFloor[SubStr(cfpKey, 1, -5)] := cfpRaw
			continue
			}
		if (RegExMatch(cfpKey, "floor$") || InStr(cfpKey, "charid"))
			continue
		if (!cfpBy.Has(cfpKey))
			{
			if (!cfpSeen.Has(cfpKey))
				cfpSeen[cfpKey] := 1, cfpGot.skipped.Push(cfpKey)
			continue
			}
		cfpGot.known += 1
		cfpS := cfpBy[cfpKey], cfpWhy := "", cfpFix := "", cfpV := 0
		if (!IsInteger(cfpRaw))
			cfpWhy := "not a whole number"
		else
			{
			cfpV := Integer(cfpRaw)
			;(a check's 0 / 1 - quicksell:2 the rehearsal, gearswap and planner 2 and up too; a pick's place in its list; a
			;number brought into its range)
			if (cfpS.kind = "check")
				{
				if (cfpV != 0 && cfpV != 1 && !(cfpV = 2 && cfpKey = "quicksell") && !(cfpV >= 2 && (cfpKey = "gearswap" || cfpKey = "planner")))
					cfpWhy := "on / off is 1 or 0"
				}
			else if (cfpS.kind = "pick")
				{
				if (cfpV < 1 || cfpV > cfpS.picks.Length)
					cfpWhy := "not one of its " cfpS.picks.Length " choices"
				}
			else if (cfpV < cfpS.lo || cfpV > cfpS.hi)
				{
				cfpV := Max(cfpS.lo, Min(cfpS.hi, cfpV))
				cfpFix := cfpKey ":" cfpRaw " (" cfpS.lo " to " cfpS.hi ": " cfpV ")"
				}
			}
		;(the last line of a key decides, as LoadStats reads one twice)
		cfpGot.rejected.Delete(cfpKey), cfpGot.fixed.Delete(cfpKey)
		if (cfpWhy != "")
			{
			cfpGot.rejected[cfpKey] := cfpKey ":" cfpRaw " (" cfpWhy ")"
			cfpGot.vals.Delete(cfpKey)
			continue
			}
		if (cfpFix != "")
			cfpGot.fixed[cfpKey] := cfpFix
		cfpGot.vals[cfpKey] := cfpV
		}
	;(the mobs' reach: its floor line's - brought into its range - over what the bot widened it to)
	for cfpKey, cfpRaw in cfpFloor
		if (IsInteger(cfpRaw) && cfpBy.Has(cfpKey))
			{
			cfpS := cfpBy[cfpKey]
			cfpGot.rejected.Delete(cfpKey), cfpGot.fixed.Delete(cfpKey)
			cfpGot.vals[cfpKey] := Max(cfpS.lo, Min(cfpS.hi, Integer(cfpRaw)))
			}
	return cfpGot
	}

;The settings a file read (CfgFileParse) would change - the ones not as they're set now (Stats), in CfgList's order:
;[{key, s: its CfgList entry, now, from: the file's, tick}] - the party's two unticked: this PC's own part
CfgFileChanges(got)
	{
	cfchItems := []
	for each, cfchS in CfgList.Call()
		{
		if (!cfchS.Has("def") || !got.vals.Has(cfchS.key))
			continue
		cfchNow := Stats.Has(cfchS.key) ? Stats[cfchS.key] : cfchS.def
		if (V1IsNum(cfchNow) && cfchNow + 0 = got.vals[cfchS.key])
			continue
		cfchItems.Push({key: cfchS.key, s: cfchS, now: cfchNow, from: got.vals[cfchS.key], tick: !(cfchS.key = "partyrole" || cfchS.key = "partybattle")})
		}
	return cfchItems
	}

;The notes under that window's list (or in the box when nothing would change): "- " lines. What isn't loaded - a
;value it can't take, keys not in the Settings window, lines it couldn't read, the network PIN, a newer bot's file -,
;what's left unticked, and what still wins over a plain setting as Stat (KillCalc.ahk) goes: the deck in use's own,
;then a school's own (storm.killmargin...); and Wait for me's reset at every start (Autofarmer.ahk)
CfgFileNotes(got, items)
	{
	cfnOut := [], cfnHas := V1Obj()
	for each, cfnIt in items
		cfnHas[cfnIt.key] := 1
	if (cfnHas.Has("partyrole") || cfnHas.Has("partybattle"))
		cfnOut.Push("The party's two are left unticked: they're this PC's own part (a follower needs the leader's address too - the tray menu's Party...).")
	cfnOwn := []
	for each, cfnIt in items
		for cfnI, cfnSch in ["storm", "fire", "ice", "life", "death", "myth", "balance"]
			if (Stats.Has(cfnSch "." cfnIt.key))
				cfnOwn.Push(cfnSch "." cfnIt.key)
	if (cfnOwn.Length)
		cfnOut.Push("A wizard's own line in PlayerStats.txt still wins when it fights as that school: " CfgFileFew(cfnOwn) ".")
	cfnDeck := [], cfnDeckName := ""
	try
		{
		if (IsObject(DeckNow) && IsObject(DeckNow.vals))
			{
			cfnDeckName := DeckNow.name
			for each, cfnIt in items
				if (DeckNow.vals.Has(cfnIt.key))
					cfnDeck.Push(cfnIt.key)
			}
		}
	if (cfnDeck.Length)
		cfnOut.Push("The deck in use (" cfnDeckName ") sets its own " CfgFileFew(cfnDeck) " - that still wins while it's on.")
	if (cfnHas.Has("handsoffon") || cfnHas.Has("handsoff"))
		cfnOut.Push("Wait for me goes back on, with 3 s, at every start of the bot.")
	cfnList := []
	for cfnK, cfnT in got.fixed
		cfnList.Push(cfnT)
	if (cfnList.Length)
		cfnOut.Push("Brought into its range: " CfgFileFew(cfnList) ".")
	cfnList := []
	for cfnK, cfnT in got.rejected
		cfnList.Push(cfnT)
	if (cfnList.Length)
		cfnOut.Push("Not loaded - not a value it can take: " CfgFileFew(cfnList) ".")
	if (got.skipped.Length)
		cfnOut.Push("Skipped - not in the Settings window (stats, learned cards, settings kept only in PlayerStats.txt, a newer bot's): " got.skipped.Length " (" CfgFileFew(got.skipped) ").")
	if (got.bad)
		cfnOut.Push("Lines it couldn't read: " got.bad " (" CfgFileFew(got.badLines) ").")
	if (got.pin)
		cfnOut.Push("The network PIN in it is never loaded.")
	cfnBot := CfgFileVersion(), cfnNewer := false
	if (got.version != "" && cfnBot != "")
		{
		try cfnNewer := VerCompare(LTrim(got.version, "vV"), LTrim(cfnBot, "vV")) > 0
		catch
			cfnNewer := false
		}
	if (cfnNewer)
		cfnOut.Push("Saved by a newer bot (" got.version " - this is " cfnBot "): its settings this one doesn't have are skipped.")
	cfnText := ""
	for each, cfnT in cfnOut
		cfnText .= (cfnText = "" ? "" : "`n") "- " cfnT
	return cfnText
	}

;A setting's value as that window shows it: on / off, a pick's words, a number
CfgFileShown(cfshS, cfshV)
	{
	if (!V1IsNum(cfshV))
		return cfshV ""
	if (cfshS.kind = "check")
		return (cfshV = 0) ? "off" : (cfshV = 1) ? "on" : "on (" CfgFileNum(cfshV) ")"
	if (cfshS.kind = "pick" && IsInteger(cfshV) && cfshV >= 1 && cfshV <= cfshS.picks.Length)
		return cfshS.picks[Integer(cfshV)]
	return CfgFileNum(cfshV)
	}

;A setting's label for that window - one that goes on from the one above it ("...on the port") with its key after it
CfgFileLabel(cflS)
	{
	return (SubStr(cflS.label, 1, 3) = "...") ? cflS.label " (" cflS.key ")" : cflS.label
	}

;A value as a settings file has it: a whole number as it is, another with up to 6 decimals; "" for one that isn't a
;number
CfgFileNum(cfnumV)
	{
	if (!V1IsNum(cfnumV))
		return ""
	if (IsInteger(cfnumV))
		return String(Integer(cfnumV))
	cfnumT := RTrim(RTrim(Format("{:.6f}", cfnumV + 0), "0"), ".")
	return (cfnumT = "-0") ? "0" : cfnumT
	}

;The first few of a list, for a note: "a, b, c and 4 more"
CfgFileFew(cffList, cffMost := 6)
	{
	cffOut := ""
	for cffI, cffT in cffList
		if (cffI <= cffMost)
			cffOut .= (cffI = 1 ? "" : ", ") cffT
	return cffOut (cffList.Length > cffMost ? " and " (cffList.Length - cffMost) " more" : "")
	}

;True for PlayerStats.txt, dashboard.ini or party.ini in the bot's own folder: Save settings as never writes over them
CfgFileOurs(path)
	{
	SplitPath(path, &cfoName, &cfoDir)
	cfoName := RTrim(cfoName, ". ")
	for cfoI, cfoAt in [A_ScriptDir, A_WorkingDir]
		if (cfoDir = cfoAt)
			for cfoJ, cfoOwn in ["PlayerStats.txt", "dashboard.ini", "party.ini"]
				if (cfoName = cfoOwn)
					return true
	return false
	}

;The dashboard's window (Dashboard.ahk's Gui), or "" before it's made: the owner of this file's boxes and window
CfgFileDash()
	{
	;(Dash unset till DashInit - reading it throws then)
	try
		{
		if (DashHwnd && GuiFromHwnd(DashHwnd) && IsObject(Dash))
			return Dash
		}
	return ""
	}

;The window of a settings file being loaded (CfgFileShow) while it's open - its Gui, else "". newWin: that window
;(kept here - one at a time), or "" once it's closed
CfgFileWin(newWin := "-")
	{
	static cfwinWin := "", cfwinHwnd := 0
	if (IsObject(newWin))
		cfwinWin := newWin, cfwinHwnd := newWin.Hwnd
	else if (newWin = "")
		cfwinWin := "", cfwinHwnd := 0
	return (cfwinHwnd && GuiFromHwnd(cfwinHwnd)) ? cfwinWin : ""
	}

;The Settings window open now (Settings.ahk CfgIsOpen)
CfgFileCfgOpen()
	{
	return V1IsFunc("CfgIsOpen") ? CfgIsOpen.Call() : 0
	}

;A line in debug.log (Autofarmer.ahk DebugLog)
CfgFileLog(msg)
	{
	if (V1IsFunc("DebugLog"))
		DebugLog.Call(msg)
	}

;This bot's version (Autofarmer.ahk BotVersion: v1.10.0...), "" if it isn't known
CfgFileVersion()
	{
	return V1IsFunc("BotVersion") ? BotVersion.Call() : ""
	}

;text with anything but plain ASCII made a "-" (a settings file is ASCII)
CfgFileAscii(text)
	{
	return RegExReplace(text, "[^\x20-\x7E]", "-")
	}
