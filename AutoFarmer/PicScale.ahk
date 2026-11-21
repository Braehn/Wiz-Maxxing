;Pictures for any UI size (included by Autofarmer.ahk)
;
;The pictures are cut at a few UI sizes: the main set at UI scale 1 and the ui<scale> folders (see
;LoadPicSets). At any other size the bot makes its own set from them: it measures the UI scale from a
;battle round's Pass and Flee buttons (DetectUiScale), then resizes each picture, the first time it's
;needed, from the cut set nearest above that size (PicPath -> PicMake) into generated\ui<scale>\ as a
;.bmp. A made picture is never pixel-exact, so it's searched for with at least GenTol colour tolerance,
;and it's see-through magenta (*TransFF00FF) wherever the resizing isn't sure of the colour (PicOpt).
;Made pictures are made again when the picture they came from changes; deleting generated\ makes
;them all again.

global GenTol, GenRoot, PassFleeDist
;Made pictures that were enlarged (from a smaller cut set): searched with a little more tolerance
global PicEnlarged
;The pictures PicMake has looked up (set dir|rel -> file, "" none); emptied when pictures are added
global PicMade
;The game window size the UI scale was last measured at (DetectUiScale, or a cut Pass button matched at the round
;start: "<w>x<h>"); the size the first rounds are being measured at and how many were tried (the main loop); why
;DetectUiScale last gave up
global PicMeasuredSize, PicMeasureSize, PicMeasureTries, PicMeasureWhy
;The colour tolerance the cut pictures needed on this screen (PicCutFind: 0 / 3 their usual *3 - 2026-10-25 from 22:44 the
;game, started on its DisplayLink adapter, drew the cut 1.144 Pass button a little off all evening); when and at which
;window size a cut set's own picture (the spellbook, the Pass button) last matched with that set in use, and that set's
;index (PicCutOk)
global PicCutTol, PicCutOkAt, PicCutOkSize, PicCutOkSet
;The picture PicCutTol was learned on (PicCutFind's "roundstart" / "roundstart_hover" - the Pass button - or "roundfinish" -
;the spellbook): only that one matching at *3 again puts *3 back (PicCutSlackSet - 2026-10-26 14:42 the cut 1.144 spellbook
;matched at *3 while its Pass button needed *16); when PicCutOk last looked at *3 again; the window size and set PicCutOk
;last looked up a kept tolerance for (generated\cutslack.txt - PicCutSlackLoad)
global PicCutTolPic, PicCutLowAt, PicCutSlackKey

;Called by LoadPicSets
PicScaleInit()
	{
	global GenTol, PicEnlarged, PicMade, PicCutTol, PicCutOkAt, PicCutOkSize, PicCutOkSet, PicCutTolPic, PicCutLowAt ; (v1 globals it sets)
	global PicCutSlackKey, GenRoot, PassFleeDist ; (v1 globals it sets)
	GenTol := 20, PicEnlarged := V1Obj(), PicMade := V1Obj(), PicCutTol := 0, PicCutOkAt := 0, PicCutOkSize := "", PicCutOkSet := ""
	PicCutTolPic := "", PicCutLowAt := 0, PicCutSlackKey := ""
	GenRoot := A_WorkingDir "\generated"
	;Distance between the middles of the Pass and Flee buttons at UI scale 1 (521 px at UI 1.144,
	;580 px at UI 1.265)
	PassFleeDist := 457
	}

;The main picture set plus every ui<scale> folder (e.g. ui1.265 = UI 1.265 times the main size),
;then the sets made before at other sizes (generated\ui<scale>, gen: 1)
LoadPicSets()
	{
	global PicSets ; (v1 globals it sets)
	PicScaleInit()
	PicSets := [V1Obj({dir: A_WorkingDir, scale: 1.0})]
	for each, root in [A_WorkingDir, GenRoot]
		{
		Loop Files, root "\ui*", "D"
			{
			sc := SubStr(A_LoopFileName, 3)
			if isNumber(sc)
				{
				if (sc >= 0.5 && sc <= 3)
					PicSets.Push(V1Obj({dir: A_LoopFilePath, scale: sc + 0, gen: (root = GenRoot)}))
				}
			}
		}
	;(a made set at a cut set's own size is that set's copy: its pictures resized 1:1 - PicCopySet. Only a cut set with its
	;own Pass button or spellbook - PicCutOwn: not one of the card learner's folders, which hold the cards learned at a made
	;size only, e.g. ui0.917 / ui1.121, and whose generated\ twin is an ordinary made set)
	for each, set in PicSets
		if (set.gen)
			for each2, cs in PicSets
				if (Abs(cs.scale - set.scale) < 0.0005 && PicCutOwn(cs))
					set.copy := 1
	;(the colour tolerance the cut set this window size was last played at needed here before - generated\cutslack.txt: a
	;restart searches with it at once, not first missing a round's Pass button)
	PicCutSlackLoad(GameW "x" GameH, PicScaleFor(GameW "x" GameH))
	}

;Cut set `set` has its own Pass button or spellbook picture (resources\roundstart.png, roundstart_hover.png or
;roundfinish.png) - not one of the card learner's folders (LearnSetDir) holding only the cards learned at that size
PicCutOwn(set)
	{
	return (IsObject(set) && !set.gen && (FileExist(set.dir "\resources\roundstart.png") || FileExist(set.dir "\resources\roundstart_hover.png") || FileExist(set.dir "\resources\roundfinish.png"))) ? 1 : 0   ; (v1: && || gave 1 / 0)
	}

;Looks for the spellbook (out of battle) or the Pass button (a battle round) with each picture set,
;and switches to the first set that finds one. skipCurrent: only try the other sets. True if found.
;The set in use a cut one at this window's own size, or its copy (PicCutHome): never left for a made set at another size
;on a made picture's match (2026-10-25 23:14:47: the cut 1.144 Pass button - drawn a little off all evening - missed, and
;the made, mostly see-through 1.121 one matched it twice: every picture was made at the wrong size from then on). Its own
;pictures are looked for again with more colour tolerance first (PicCutFind, every 9 s at most), then its copy made 1:1
;(PicCopySet) may take over; another cut set still can (it matches nearly pixel for pixel), and DetectUiScale measures
DetectPicSet(skipCurrent := false)
	{
	;(another set than the one in use: found twice, 3-20 s apart, before it's used - a made set's mostly see-through
	;pictures can match something else once)
	static cand := 0, candAt := 0, slackAt := 0, saidHome := ""
	home := skipCurrent && PicCutHome(), homeScale := home ? PicSets[PicSet].scale : ""
	if (home && !PicSets[PicSet].gen && PicCutTol < GenTol && (!slackAt || A_TickCount - slackAt > 9000))
		{
		slackAt := A_TickCount
		if (PicCutFind(PicSets[PicSet], ["roundfinish", "roundstart", "roundstart_hover"], GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, &dpsTol, &dpsPic, PicCutTol))
			{
			PicCutSlackSet(dpsTol, dpsPic)
			PicCutOk()
			cand := 0
			return true
			}
		;(not even so: its copy made 1:1, for the sets below)
		dpsCp := PicCopySet(PicSet)
		PicMake("resources\roundstart.png", PicSets[dpsCp]), PicMake("resources\roundfinish.png", PicSets[dpsCp])
		}
	if (home && saidHome != GameW "x" GameH "|" PicSet)
		{
		saidHome := GameW "x" GameH "|" PicSet
		DebugLog("Pictures: " PicSetName(PicSet) " is the set at this window's own size - held: another cut set or its own copy only can take over here, or the UI size measured from Pass and Flee")
		}
	;(the set this window size was last played at first - generated\scales.txt: a cut one before its copy)
	want := PicScaleFor(GameW "x" GameH), order := [], wantN := 0
	for i, set in PicSets
		if (want != "" && V1Lt(V1Abs(V1Sub(set.scale, want)), 0.002))   ; (v1: scales.txt's text compared as v1 did)
			order.InsertAt(set.gen ? wantN + 1 : 1, i), wantN += 1
		else
			order.Push(i)
	for each, i in order
		{
		set := PicSets[i]
		if (skipCurrent && i = PicSet)
			continue
		;(a cut set's own size held: no made set at another size)
		if (home && set.gen && Abs(set.scale - homeScale) >= 0.0005)
			continue
		for each2, pic in ["roundfinish", "roundstart"]
			{
			file := set.dir "\resources\" pic (set.gen ? ".bmp" : ".png")
			if (!FileExist(file))
				continue
			;(a made picture this see-through - the spellbook at a small UI size keeps 6-8% - matches nearly anything)
			if (PicTooThin(file))
				continue
			V1ImageSearch(&fx, &fy, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, (set.gen ? "*" GenTol : "*" (PicCutTol > 3 ? PicCutTol : 3)) " *TransFF00FF " file)
			if (ErrorLevel = 0)
				{
				if (skipCurrent && i != PicSet && !(cand = i && A_TickCount - candAt >= 2500 && A_TickCount - candAt <= 20000))
					{
					if (cand != i || A_TickCount - candAt > 20000)
						cand := i, candAt := A_TickCount
					return false
					}
				dpsGap := (skipCurrent && cand = i) ? Round((A_TickCount - candAt) / 1000, 1) : ""
				cand := 0
				if (i != PicSet || !skipCurrent)
					UsePicSet(i, "its " (pic = "roundstart" ? "Pass button" : "spellbook") " picture found on screen"
						. (dpsGap != "" ? " twice, " dpsGap " s apart, where " PicSetName(PicSet) "'s own wasn't" : "")
						. (want != "" && V1Lt(V1Abs(V1Sub(set.scale, want)), 0.002) ? " - the size this window was last played at" : "")
						. (set.gen ? " (made, " PicSolidPct(file) "% solid, *" GenTol ")" : ""))
				if (!set.gen)
					PicCutOk()
				return true
				}
			}
		;(the start: the cut set this window was last played at, not matching as cut - its own pictures with more colour
		;tolerance before any other set's. From the tolerance just used, not over it: the hovered Pass button wasn't looked
		;for above - drawn hovered on an exact screen it matches at *3, no tolerance learned for it)
		if (!skipCurrent && !set.gen && want != "" && V1Lt(V1Abs(V1Sub(set.scale, want)), 0.002)
			&& PicCutFind(set, ["roundfinish", "roundstart", "roundstart_hover"], GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, &dpsTol, &dpsPic, (PicCutTol > 3 ? PicCutTol : 3) - 1))
			{
			cand := 0
			UsePicSet(i, "its " (dpsPic = "roundfinish" ? "spellbook" : dpsPic = "roundstart_hover" ? "Pass button (drawn hovered)" : "Pass button") " picture found on screen at *" dpsTol " - the size this window was last played at")
			PicCutSlackSet(dpsTol, dpsPic)
			PicCutOk()
			return true
			}
		}
	return false
	}

;A made picture (.bmp, see-through magenta) under 20% solid: it matches nearly anything, so it never picks a picture
;set nor confirms the one in use. A cut .png never counts as thin
PicTooThin(file)
	{
	return PicSolidPct(file) < 20
	}

;How much of picture file is solid, in % - a made .bmp's pixels that aren't see-through magenta; 100 for anything
;else. Kept per file and its time
PicSolidPct(file)
	{
	static seen := V1Obj()
	if (SubStr(file, -4) != ".bmp")
		return 100
	t := V1Try(FileGetTime, file)   ; (v1: blank when it can't be read)
	key := file "|" t
	if (seen.Has(key))
		return seen[key]
	f := V1Try(FileOpen, file, "r")   ; (v1: 0 when it can't be opened)
	if (!IsObject(f))
		return 100
	f.Pos := 10, off := f.ReadUInt(), f.Pos := 18, w := f.ReadInt(), h := f.ReadInt(), f.Pos := 28, bpp := f.ReadUShort()
	if (bpp != 24 || w <= 0 || h = 0)
		{
		f.Close()
		return seen[key] := 100
		}
	hh := Abs(h), row := ((w * 3 + 3) // 4) * 4, solid := 0
	buf := Buffer(row * hh, 0)
	f.Pos := off
	f.RawRead(buf, row * hh)
	f.Close()
	Loop hh
		{
		r := (A_Index - 1) * row
		Loop w
			{
			p := r + (A_Index - 1) * 3
			if !(NumGet(buf, p, "UChar") = 0xFF && NumGet(buf, p + 1, "UChar") = 0 && NumGet(buf, p + 2, "UChar") = 0xFF)
				solid += 1
			}
		}
	return seen[key] := Round(100 * solid / (w * hh))
	}

;The UI scale a battle round's Pass button was last found with at window size size ("<w>x<h>"), from
;generated\scales.txt ("<w>x<h>=<scale>" lines) - "" none
PicScaleFor(size)
	{
	t := V1FileRead(GenRoot "\scales.txt")   ; (v1: blank when it isn't there)
	Loop Parse, t, "`n", "`r"
		if (InStr(A_LoopField, size "=") = 1)
			return SubStr(A_LoopField, (StrLen(size) + 2)<1 ? (StrLen(size) + 2)-1 : (StrLen(size) + 2))
	return ""
	}

;The picture set at the UI scale remembered for this window size (PicScaleFor), else 1 (the main set)
PicSetForSize()
	{
	want := PicScaleFor(GameW "x" GameH)
	if (want != "")
		for i, set in PicSets
			if (V1Lt(V1Abs(V1Sub(set.scale, want)), 0.002))   ; (v1: scales.txt's text compared as v1 did)
				return i
	return 1
	}

;The game's window another size than when last looked (the main loop, after UpdateGameRect), one it was played at before
;(generated\scales.txt) and nothing on screen has told the size since - okSize: the main loop's PicSetOkSize, the size the
;set in use last matched at; PicCutOkSize, PicMeasuredSize: its cut picture matched / the UI measured: that size's set, as
;at the start. Out of a battle nothing else would: a small UI size's made spellbook is too see-through to pick a set by
;(PicTooThin - 8% at 0.856). 2026-11-20 20:51: the bot started beside a full-screen Wizard101, minimized, kept the main set
;(UI 1) for 10 minutes at 1920x1080 (0.856). start: the start's own size, the set chosen for it there - only noted (the
;start calls it so; with no such call the first look counts as the start's). True if switched: those size marks then
;vouched for the set it left, not this one - PicCutOkSize and PicMeasuredSize emptied here, the main loop's PicSetOkSize
;there (else, back at a size the left set was seen at, this set would be kept there and the main loop's look for another
;set held off for 10 minutes)
PicSizeKept(okSize := "", start := false)
	{
	static seenSize := ""
	global PicCutOkSize, PicMeasuredSize ; (v1 globals it sets)
	size := GameW "x" GameH
	if (start || seenSize = "" || size = seenSize)
		{
		seenSize := size
		return false
		}
	seenSize := size
	if (okSize = size || PicCutOkSize = size || PicMeasuredSize = size || !IsObject(PicSets) || !IsObject(V1At(PicSets, PicSet)))
		return false
	want := PicScaleFor(size)
	if (want = "" || V1Lt(V1Abs(V1Sub(PicSets[PicSet].scale, want)), 0.002))   ; (v1: scales.txt's text compared as v1 did)
		return false
	UsePicSet(PicSetForSize(), "the window is " size " now - nothing on screen to tell the size by yet: the size this window was last played at (generated\scales.txt: " size "=" want ")")
	PicCutOkSize := "", PicMeasuredSize := ""
	return true
	}

;A round's Pass button was just found with the set in use: remembered for this window size (written only when it
;changes) - only once the UI size was measured at this size (DetectUiScale): a made set's Pass button, mostly
;see-through, matches at a size a little off too
PicRemember()
	{
	static said := ""
	size := GameW "x" GameH, sc := Round(PicSets[PicSet].scale, 3)
	if (PicMeasuredSize != size)
		return
	if (said = size "=" sc)
		return
	said := size "=" sc
	if (PicScaleFor(size) != "" && V1Lt(V1Abs(V1Sub(PicScaleFor(size), sc)), 0.002))   ; (v1: scales.txt's text compared as v1 did)
		return
	t := V1FileRead(GenRoot "\scales.txt")   ; (v1: blank when it isn't there)
	out := ""
	Loop Parse, t, "`n", "`r"
		if (A_LoopField != "" && InStr(A_LoopField, size "=") != 1)
			out .= A_LoopField "`r`n"
	V1Do(DirCreate, GenRoot)
	was := PicScaleFor(size)
	f := V1Try(FileOpen, GenRoot "\scales.txt", "w")   ; (v1: 0 when it can't be opened)
	if (IsObject(f))
		f.Write(out size "=" sc "`r`n"), f.Close()
	DebugLog("UI size: " size " remembered at UI scale " sc " (generated\scales.txt" (was != "" ? "; it was " was : "") ") - the set the bot starts with at this size")
	}

;The name of picture set i for the log: "the main set", "ui1.144", "generated\ui1.130"
PicSetName(i)
	{
	return (i = 1) ? "the main set" : IsObject(V1At(PicSets, i)) ? SubStr(PicSets[i].dir, (StrLen(A_WorkingDir) + 2)<1 ? (StrLen(A_WorkingDir) + 2)-1 : (StrLen(A_WorkingDir) + 2)) : "set " i
	}

;The set in use is a cut set (or its copy, PicCopySet) at this game window's own size: its own picture matched at this
;size in this run (PicCutOk), the size was measured with it (PicMeasuredSize), or it's the size remembered for this
;window (generated\scales.txt). DetectPicSet holds such a set - no made set at another size takes over from it
PicCutHome()
	{
	set := V1At(PicSets, PicSet), size := GameW "x" GameH   ; (v1: no such set - blank)
	;(a cut set with its own Pass button or spellbook - PicCutOwn - or such a set's copy)
	if (!IsObject(set) || (set.gen ? !set.copy : !PicCutOwn(set)))
		return false
	;(PicCutOk's window size only as noted with this very set - or, for a copy, with the cut set it's the copy of)
	pchOk := V1At(PicSets, PicCutOkSet)   ; (v1: blank - "" when none was noted yet)
	if ((PicCutOkSize = size && (PicCutOkSet = PicSet || (set.copy && IsObject(pchOk) && Abs(pchOk.scale - set.scale) < 0.0005))) || PicMeasuredSize = size)
		return true
	want := PicScaleFor(size)
	return (want != "" && V1Lt(V1Abs(V1Sub(set.scale, want)), 0.002))   ; (v1: scales.txt's text compared as v1 did)
	}

;A cut set's own picture just matched with it in use (the spellbook, a round's Pass button - the main loop, DetectPicSet,
;DetectUiScale): noted, with the window size and the set (PicCutHome, DetectUiScale). file: the picture that matched (the
;main loop's) - only the set's own cut .png counts, not one PicPath made for it at its size (a card learner's folder
;has no Pass button or spellbook of its own: the made, mostly see-through one would hold a size a little off)
PicCutOk(file := "")
	{
	global PicCutOkAt, PicCutOkSize, PicCutOkSet, PicCutSlackKey, PicCutLowAt ; (v1 globals it sets)
	pcoSet := V1At(PicSets, PicSet)   ; (v1: no such set - blank)
	if (IsObject(pcoSet) && !pcoSet.gen && (file != "" ? (InStr(file, pcoSet.dir "\resources\") = 1 && SubStr(file, -4) = ".png" && FileExist(file)) : PicCutOwn(pcoSet)))
		{
		PicCutOkAt := A_TickCount, PicCutOkSize := GameW "x" GameH, PicCutOkSet := PicSet
		;(a window size and cut set not looked up yet: the colour tolerance kept for them - generated\cutslack.txt - if more)
		if (PicCutSlackKey != GameW "x" GameH "|" PicSet)
			PicCutSlackKey := GameW "x" GameH "|" PicSet, PicCutSlackLoad(GameW "x" GameH, pcoSet.scale)
		;(more colour tolerance in use: the picture that just matched, if it's the one the tolerance was learned on - the Pass
		;button, or the spellbook - looked for at *3 again, once a minute at most: matching, the colours are drawn right again
		;and *3 is back - PicCutSlackSet. The spellbook never for the Pass button's: 2026-10-26 14:42 it matched at *3 while the
		;Pass button needed *16)
		if (file != "" && PicCutTol > 3 && A_TickCount - PicCutLowAt > 60000)
			{
			pcoPic := RegExReplace(file, "i)^.*\\|\.png$")
			if ((pcoPic = "roundfinish") = (PicCutTolPic = "roundfinish"))
				{
				PicCutLowAt := A_TickCount
				V1ImageSearch(&pcoX, &pcoY, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, "*3 *TransFF00FF " file)
				if (ErrorLevel = 0)
					PicCutSlackSet(3, pcoPic)
				}
			}
		}
	}

;Cut set `set`'s own pictures (names in its resources\, e.g. ["roundstart", "roundstart_hover"]) looked for in the
;rectangle at *3, then - the game drawing their colours a little off (2026-10-25 from 22:44: the game started on its
;DisplayLink adapter, and the cut 1.144 Pass button missed at *3 all evening while made ones matched) - at *8, *12, *16 and
;*20 (GenTol); a fully solid cut picture still only matches at its own size. Only the tolerances over `above` (one
;already tried). True if one matched: tolAt its least tolerance, picAt the picture
PicCutFind(set, pics, x1, y1, x2, y2, &tolAt, &picAt, above := 0)
	{
	tolAt := "", picAt := ""
	if (!IsObject(set) || set.gen)
		return false
	for each, tol in [3, 8, 12, 16, GenTol]
		{
		if (tol <= above)
			continue
		for each2, pic in pics
			{
			file := set.dir "\resources\" pic ".png"
			if (!FileExist(file))
				continue
			V1ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" tol " *TransFF00FF " file)
			if (ErrorLevel = 0)
				{
				tolAt := tol, picAt := pic
				return true
				}
			}
		}
	return false
	}

;The colour tolerance the cut pictures need on this screen (PicCutFind found picture pic at *tol): kept (PicCutTol - PicOptFile
;searches every cut picture with at least that), said once per change, and kept for this window size and the cut set in use
;(generated\cutslack.txt - PicCutSlackSave: a restart starts with it). The picture it was learned on matching at *3 again
;(tol 3 - PicCutOk, DetectUiScale) puts *3 back; another picture doesn't (the spellbook can match at *3 while the Pass button
;needs *16)
PicCutSlackSet(tol, pic)
	{
	global PicCutTol, PicCutTolPic, PicCutLowAt ; (v1 globals it sets)
	if (tol = "")
		return
	if (tol <= 3)
		{
		if (PicCutTol > 3 && (pic = "roundfinish") = (PicCutTolPic = "roundfinish"))
			{
			pcsWas := PicCutTol, PicCutTol := 0, PicCutTolPic := "", PicCutLowAt := A_TickCount
			PicCutSlackSave(0, pic)
			DebugLog("Pictures: " PicSetName(PicSet) "'s " (pic = "roundfinish" ? "spellbook" : pic = "roundstart_hover" ? "Pass button (drawn hovered)" : "Pass button") " cut picture matches at *3 again - the colours are drawn right again: the cut pictures are searched with *3 from now on (not *" pcsWas ")")
			}
		return
		}
	if (tol <= PicCutTol)
		return
	PicCutTol := tol, PicCutTolPic := pic, PicCutLowAt := A_TickCount
	DebugLog("Pictures: " PicSetName(PicSet) "'s " (pic = "roundfinish" ? "spellbook" : pic = "roundstart_hover" ? "Pass button (drawn hovered)" : "Pass button") " cut picture matches at *" tol " only - the game draws its colours a little off (another graphics adapter or display mode?): the cut pictures are searched with *" tol " from now on")
	PicCutSlackSave(tol, pic)
	}

;The colour tolerance kept for the cut set at UI scale `scale` at window size `size` ("<w>x<h>"), from generated\cutslack.txt
;("<w>x<h>|<scale>=<tol>|<picture>" lines - PicCutSlackSave) - "" none; pic: the picture it was learned on
PicCutSlackFor(size, scale, &pic)
	{
	pic := ""
	if (scale = "")
		return ""
	key := size "|" Format("{:.3f}", V1N(scale)) "="   ; (v1: scales.txt's text not a number - formatted as 0.000; v2 throws)
	t := V1FileRead(GenRoot "\cutslack.txt")   ; (v1: blank when it isn't there)
	Loop Parse, t, "`n", "`r"
		if (InStr(A_LoopField, key) = 1)
			{
			pcfF := StrSplit(SubStr(A_LoopField, StrLen(key) + 1), "|")
			pic := V1At(pcfF, 2)   ; (v1: blank past the end)
			return pcfF[1]
			}
	return ""
	}

;The colour tolerance just learned (tol, on picture pic) - or, tol 0, *3 back - kept for this window size and the cut set in
;use in generated\cutslack.txt (written only when it changes): PicCutSlackLoad takes it at the next start at this size
PicCutSlackSave(tol, pic)
	{
	global PicCutSlackKey ; (v1 globals it sets)
	pssSet := V1At(PicSets, PicSet)   ; (v1: no such set - blank)
	if (!IsObject(pssSet) || pssSet.gen)
		return
	PicCutSlackKey := GameW "x" GameH "|" PicSet
	key := GameW "x" GameH "|" Format("{:.3f}", pssSet.scale) "="
	t := V1FileRead(GenRoot "\cutslack.txt")   ; (v1: blank when it isn't there)
	out := "", had := ""
	Loop Parse, t, "`n", "`r"
		if (A_LoopField != "")
			{
			if (InStr(A_LoopField, key) = 1)
				had := A_LoopField
			else
				out .= A_LoopField "`r`n"
			}
	line := tol > 3 ? key tol "|" pic : ""
	if (had = line)
		return
	V1Do(DirCreate, GenRoot)
	f := V1Try(FileOpen, GenRoot "\cutslack.txt", "w")   ; (v1: 0 when it can't be opened)
	if (IsObject(f))
		f.Write(out (line != "" ? line "`r`n" : "")), f.Close()
	}

;The colour tolerance kept for window size `size` and the cut set at UI scale `scale` (PicCutSlackFor) taken when it's more
;than the one in use, and said: every cut picture searched with it from now on (the picture it was learned on matching at *3
;again puts *3 back - PicCutOk). LoadPicSets (the start: the set this window size was last played at - generated\scales.txt)
;and PicCutOk (a cut set's own picture matched at a window size and set not looked up yet)
PicCutSlackLoad(size, scale)
	{
	global PicCutTol, PicCutTolPic, PicCutLowAt ; (v1 globals it sets)
	pclTol := PicCutSlackFor(size, scale, &pclPic)
	if !IsInteger(pclTol)
		return
	pclTol := pclTol + 0
	if (pclTol <= 3 || pclTol > GenTol || pclTol <= PicCutTol)
		return
	PicCutTol := pclTol, PicCutTolPic := pclPic, PicCutLowAt := 0
	DebugLog("Pictures: the cut pictures are searched with *" PicCutTol " from now on - at this window size (" size ") the cut set at UI scale " Format("{:.3f}", V1N(scale)) "'s " (pclPic = "roundfinish" ? "spellbook" : pclPic = "roundstart_hover" ? "Pass button (drawn hovered)" : "Pass button") " matched at *" PicCutTol " only before (generated\cutslack.txt; it matching at *3 again puts *3 back)")
	}

;In a battle by the game's log, its round not seen (the main loop: after its mouse move onto the scene - force - or between):
;the set in use's own cut Pass button, as drawn and drawn hovered, looked for with more colour tolerance (PicCutFind from
;*3: one that matches as it is isn't taken for one that needs more), every 4 s at most. Matching only with more than the
;tolerance in use: looked for again 250 ms on (a button still changing as the mouse left it isn't taken for colours drawn
;off), then that tolerance is kept - PicCutSlackSet: said once, kept for this window size (generated\cutslack.txt) - and the
;round is seen from the next look on. Never another picture set. 2026-10-26 14:42: the remembered 1.144 set's spellbook
;matched at *3 at the start, its Pass button only at *16 - no round of two battles seen, the game passed every one. True if
;the Pass button is there
PicCutPassSlack(force := false)
	{
	static ppsAt := 0
	if (!force && ppsAt && A_TickCount - ppsAt < 4000)
		return false
	ppsAt := A_TickCount
	ppsSet := V1At(PicSets, PicSet), ppsPics := ["roundstart", "roundstart_hover"]   ; (v1: no such set - blank)
	if (!PicCutFind(ppsSet, ppsPics, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, &ppsTol, &ppsPic))
		return false
	ppsUse := PicCutTol > 3 ? PicCutTol : 3
	if (ppsTol <= ppsUse)
		return true
	Sleep(250)
	if (!PicCutFind(ppsSet, ppsPics, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, &ppsTol2, &ppsPic2))
		return false
	if (ppsTol2 <= ppsUse)
		return true
	PicCutSlackSet(ppsTol2 > ppsTol ? ppsTol2 : ppsTol, ppsTol2 > ppsTol ? ppsPic2 : ppsPic)
	return true
	}

;The copy of cut set i (a made set at its very size - generated\ui<scale>, copy: 1 - whose pictures are the cut ones
;resized 1:1: only the pixels every sub-pixel position of them agrees on kept, searched at *GenTol): for a screen that
;draws the cut set's size but not its pixels. Made in PicSets if it isn't there. Its index (i itself for a made set)
PicCopySet(i)
	{
	if (!IsObject(V1At(PicSets, i)) || PicSets[i].gen)   ; (v1: no such set - blank)
		return i
	sc := PicSets[i].scale
	for j, set in PicSets
		if (set.gen && Abs(set.scale - sc) < 0.0005)
			{
			set.copy := 1
			return j
			}
	dir := GenRoot "\ui" Round(sc, 3)
	V1Do(DirCreate, dir)
	PicSets.Push(V1Obj({dir: dir, scale: sc + 0, gen: 1, copy: 1}))
	return PicSets.Length
	}

;ImageSearch options and file for picture rel (e.g. "resources\player.png"): "*<tol> <file>", or for a
;made picture at least GenTol and *TransFF00FF
PicOpt(rel, tol := 3)
	{
	return PicOptFile(PicPath(rel), tol)
	}

;The same for a picture file already looked up with PicPath. An enlarged made picture (the cut one was
;smaller) gets 4 more: enlarging can't add back the detail the game draws at the bigger size
PicOptFile(p, tol := 3)
	{
	if (SubStr(p, -4) = ".bmp")
		return "*" (Max(tol, GenTol) + (PicEnlarged.Has(p) ? 4 : 0)) " *TransFF00FF " p
	;(a cut picture can have see-through parts too, e.g. the round badges; at least the colour tolerance this screen was
	;found to need for the cut pictures - PicCutTol)
	return "*" (PicCutTol > tol ? PicCutTol : tol) " *TransFF00FF " p
	}

;The picture rel for the made set `set`: generated\ui<scale>\<rel as .bmp>, made now if it isn't there
;yet or the picture it's made from has changed since. "" if no cut set has rel (or it couldn't be made)
PicMake(rel, set)
	{
	key := set.dir "|" rel
	if (PicMade.Has(key))
		return PicMade[key]
	dest := set.dir "\" RegExReplace(rel, "i)\.png$", ".bmp")
	srcs := PicMasters(rel, set.scale)
	if (!srcs.Length)
		return PicMade[key] := ""
	if (srcs[1].scale < set.scale * 0.97)
		PicEnlarged[dest] := 1
	;(cut at nearly this size - under 1% off: that picture as it is; resizing a mostly see-through one
	;that little only loses pixels. Not for a cut set's copy - PicCopySet: resized 1:1, that's what it's for)
	if (!set.copy && Abs(set.scale / srcs[1].scale - 1) < 0.01)
		return PicMade[key] := srcs[1].file
	if (FileExist(dest))
		{
		;(made before: kept unless a picture it could come from has changed since)
		destTime := V1Try(FileGetTime, dest)   ; (v1: blank when it can't be read)
		newer := false
		for each, src in srcs
			{
			srcTime := V1Try(FileGetTime, src.file)
			if (V1Gt(srcTime, destTime))   ; (v1: a blank time compared as text)
				newer := true
			}
		if (!newer)
			return PicMade[key] := dest
		}
	SplitPath(dest, , &destDir)
	V1Do(DirCreate, destDir)
	;From the best one; a picture that's mostly see-through can come out too thin to use, then the next
	for each, src in srcs
		{
		madeFrom := A_TickCount
		kept := PicResize(src.resize, dest, set.scale / src.scale)
		DebugLog("  made " rel " for UI size " Round(set.scale, 3) " from the one cut at " Round(src.scale, 3) " (" (kept ? kept "% of it kept" : "too little left to use") ", " A_TickCount - madeFrom " ms)")
		if (kept)
			return PicMade[key] := dest
		}
	V1Do(FileDelete, dest)
	return PicMade[key] := ""
	}

;The cut pictures to make rel from for UI scale `scale`, best first: [{file, scale}, ...]. Best is the
;cut set with the smallest scale at or above it (shrinking keeps the detail), then the bigger ones,
;then the smaller ones biggest first
PicMasters(rel, scale)
	{
	up := [], down := []
	for i, set in PicSets
		{
		if (set.gen || !FileExist(set.dir "\" rel))
			continue
		isUp := (set.scale >= scale * 0.97), list := isUp ? up : down, at := 1
		while (at <= list.Length && (isUp ? list[at].scale < set.scale : list[at].scale > set.scale))
			at++
		;(a cut card is mostly see-through - the parts that change between copies - which leaves too little
		;once resized; a solid copy saved next to it as <name>.raw.png is resized instead)
		raw := set.dir "\" RegExReplace(rel, "i)\.png$", ".raw.png")
		list.InsertAt(at, V1Obj({file: set.dir "\" rel, scale: set.scale, resize: FileExist(raw) ? raw : set.dir "\" rel}))
		}
	for each, m in down
		up.Push(m)
	return up
	}

;Resizes picture src by ratio into dest (a 24-bit BMP). Each pixel is the average of the solid (not
;see-through magenta) src pixels it covers, worked out for phases x phases sub-pixel positions of the
;picture; it's kept only if at least 40% of what it covers is solid and all positions agree within 10
;- so it doesn't matter where exactly the game lands the picture. The rest is magenta. Returns the %
;of pixels kept (at least 1), 0 if it failed or too little was left to tell the picture apart
PicResize(src, dest, ratio, phases := 4)
	{
	if (!PicRead(src, &pix, &w, &h))
		return 0
	tw := Floor(w * ratio) - 1, th := Floor(h * ratio) - 1
	if (tw < 4 || th < 4)
		return 0
	;(a tiny patch, e.g. the 8x8 placeholders cut at UI 1, matches almost anything once resized: the
	;next cut set's picture is used instead)
	if (w < 12 || h < 12)
		return 0
	;src colours and see-through pixels, flat (index y * w + x)
	;(v1: these [] are stores indexed from 0 - V1Obj, as v1's objects)
	SrcR := V1Obj(), SrcG := V1Obj(), SrcB := V1Obj(), SrcK := V1Obj()
	Loop w * h
		{
		i := A_Index - 1
		c := NumGet(pix, i * 4, "UInt")
		SrcR[i] := (c >> 16) & 0xFF, SrcG[i] := (c >> 8) & 0xFF, SrcB[i] := c & 0xFF
		SrcK[i] := !(SrcR[i] = 255 && SrcG[i] = 0 && SrcB[i] = 255)
		}
	;across: every src row resized to tw, for each phase (colour sums and solid share, of the solid
	;pixels only)
	PhR := V1Obj(), PhG := V1Obj(), PhB := V1Obj(), PhK := V1Obj()
	Loop phases
		{
		ph := A_Index, ar := V1Obj(), ag := V1Obj(), ab := V1Obj(), ak := V1Obj()
		Loop tw
			{
			u := A_Index - 1
			span := PicSpan(u, (ph - 1) / phases, ratio, w)
			Loop h
				{
				row := (A_Index - 1) * w, o := (A_Index - 1) * tw + u
				r := 0, g := 0, b := 0, k := 0
				for each, s in span
					{
					i := row + s[1]
					if (SrcK[i])
						wt := s[2], r += SrcR[i] * wt, g += SrcG[i] * wt, b += SrcB[i] * wt, k += wt
					}
				ar[o] := r, ag[o] := g, ab[o] := b, ak[o] := k
				}
			}
		PhR[ph] := ar, PhG[ph] := ag, PhB[ph] := ab, PhK[ph] := ak
		}
	;down: those resized to th, for each of the phases x phases; summed, and the spread of each colour
	n := tw * th, SR := V1Obj(), SG := V1Obj(), SB := V1Obj(), Keep := V1Obj(), LoR := V1Obj(), LoG := V1Obj(), LoB := V1Obj(), HiR := V1Obj(), HiG := V1Obj(), HiB := V1Obj()
	Loop n
		{
		o := A_Index - 1
		SR[o] := 0, SG[o] := 0, SB[o] := 0, Keep[o] := 1
		LoR[o] := 999, LoG[o] := 999, LoB[o] := 999, HiR[o] := -1, HiG[o] := -1, HiB[o] := -1
		}
	Loop phases
		{
		fy := (A_Index - 1) / phases
		Loop th
			{
			v := A_Index - 1
			span := PicSpan(v, fy, ratio, h)
			Loop phases
				{
				ar := PhR[A_Index], ag := PhG[A_Index], ab := PhB[A_Index], ak := PhK[A_Index]
				Loop tw
					{
					u := A_Index - 1, o := v * tw + u
					if (!Keep[o])
						continue
					r := 0, g := 0, b := 0, k := 0
					for each, s in span
						{
						i := s[1] * tw + u, wt := s[2]
						r += ar[i] * wt, g += ag[i] * wt, b += ab[i] * wt, k += ak[i] * wt
						}
					if (k < 0.39999)
						{
						Keep[o] := 0
						continue
						}
					r /= k, g /= k, b /= k
					SR[o] += r, SG[o] += g, SB[o] += b
					if (r < LoR[o])
						LoR[o] := r
					if (r > HiR[o])
						HiR[o] := r
					if (g < LoG[o])
						LoG[o] := g
					if (g > HiG[o])
						HiG[o] := g
					if (b < LoB[o])
						LoB[o] := b
					if (b > HiB[o])
						HiB[o] := b
					}
				}
			}
		}
	;24-bit BMP, bottom row first; magenta where not kept
	;(enlarging: only the steadiest pixels - the game draws more detail at the bigger size than the
	;enlarged picture has)
	agree := ratio > 1.03 ? 6 : 10
	stride := (tw * 3 + 3) & ~3, size := stride * th, cnt := phases * phases, kept := 0
	bits := Buffer(size, 0)
	Loop th
		{
		v := A_Index - 1, line := (th - 1 - v) * stride
		Loop tw
			{
			u := A_Index - 1, o := v * tw + u, at := line + u * 3
			if (Keep[o] && HiR[o] - LoR[o] <= agree && HiG[o] - LoG[o] <= agree && HiB[o] - LoB[o] <= agree)
				{
				kept++
				NumPut("UChar", Round(SB[o] / cnt), bits, at), NumPut("UChar", Round(SG[o] / cnt), bits, at + 1), NumPut("UChar", Round(SR[o] / cnt), bits, at + 2)
				}
			else
				NumPut("UChar", 255, bits, at), NumPut("UChar", 0, bits, at + 1), NumPut("UChar", 255, bits, at + 2)
			}
		}
	;(a picture that's nearly all see-through would match anything)
	if (kept < 12)
		return 0
	bmp := V1Try(FileOpen, dest, "w")   ; (v1: 0 when it can't be opened)
	if (!IsObject(bmp))
		return 0
	bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + size), bmp.WriteUInt(0), bmp.WriteUInt(54)
	bmp.WriteUInt(40), bmp.WriteInt(tw), bmp.WriteInt(th), bmp.WriteUShort(1), bmp.WriteUShort(24)
	bmp.WriteUInt(0), bmp.WriteUInt(size), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
	bmp.RawWrite(bits, size)
	bmp.Close()
	return Max(1, Round(100 * kept / n))
	}

;The src pixels (along one side) that pixel t of the resized picture covers at sub-pixel phase f:
;[[index, weight], ...], the weights adding up to 1
PicSpan(t, f, ratio, srcLen)
	{
	a := (t + f) / ratio, z := (t + 1 + f) / ratio, span := []
	i := Floor(a)
	while (i < z && i < srcLen)
		{
		part := Min(z, i + 1) - Max(a, i)
		if (part > 0.000001)
			span.Push([i, part * ratio])
		i++
		}
	return span
	}

;Reads a picture file (PNG, BMP...) into pix: 4 bytes a pixel (blue, green, red, alpha), rows top to
;bottom; w x h its size. True if it could
PicRead(file, &pix, &w, &h)
	{
	static token := 0
	if (!token)
		{
		DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
		si := Buffer(A_PtrSize = 8 ? 24 : 16, 0), NumPut("UInt", 1, si, 0)
		DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
		if (!token)
			return false
		}
	gbmp := 0
	if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", file, "Ptr*", &gbmp) || !gbmp)
		return false
	w := 0, h := 0   ; (v1: a blank UInt* was read as 0 - v2's DllCall needs a value)
	DllCall("gdiplus\GdipGetImageWidth", "Ptr", gbmp, "UInt*", &w)
	DllCall("gdiplus\GdipGetImageHeight", "Ptr", gbmp, "UInt*", &h)
	rect := Buffer(16, 0), NumPut("Int", w, rect, 8), NumPut("Int", h, rect, 12)
	;BitmapData: Width, Height, Stride, PixelFormat, Scan0, Reserved; read only, 32 bpp ARGB
	data := Buffer(16 + 2 * A_PtrSize, 0)
	ok := false
	if (!DllCall("gdiplus\GdipBitmapLockBits", "Ptr", gbmp, "Ptr", rect.Ptr, "UInt", 1, "Int", 0x26200A, "Ptr", data.Ptr))
		{
		stride := NumGet(data, 8, "Int"), scan := NumGet(data, 16, "Ptr")
		pix := Buffer(w * h * 4, 0)
		Loop h
			DllCall("RtlMoveMemory", "Ptr", pix.Ptr + (A_Index - 1) * w * 4, "Ptr", scan + (A_Index - 1) * stride, "Ptr", w * 4)
		DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", gbmp, "Ptr", data.Ptr)
		ok := true
		}
	DllCall("gdiplus\GdipDisposeImage", "Ptr", gbmp)
	return ok
	}

;No picture set finds anything: maybe the UI is a size there are no pictures for. If a battle round
;is up, measures the UI scale from its Pass and Flee buttons (read by OCR; they sit either side of the
;middle of the screen), fine-tunes it by making the Pass button at sizes up to 2% either side of that
;and keeping the one that matches closest, and switches to the made set for that size (new or made
;before). True if it did
DetectUiScale()
	{
	global PicMeasureWhy, PicMeasuredSize ; (v1 globals it sets)
	;Cheap look first: Pass and Flee are pure yellow words left and right of the middle (clear of the
	;middle, where the yellow quest arrow is)
	top := GameTop + Round(GameH * 0.45), bottom := GameTop + Round(GameH * 0.8)
	PicMeasureWhy := "no pure yellow words (Pass / Flee) on the screen"
	V1PixelSearch(&yx, &yy, GameLeft + Round(GameW * 0.2), top, GameLeft + Round(GameW * 0.45), bottom, 0xFFFF00, 0, "Fast RGB")
	if (ErrorLevel)
		return false
	V1PixelSearch(&yx, &yy, GameLeft + Round(GameW * 0.55), top, GameLeft + Round(GameW * 0.8), bottom, 0xFFFF00, 0, "Fast RGB")
	if (ErrorLevel)
		return false
	PicMeasureWhy := "OCR didn't work"
	OcrRect(GameLeft + GameW // 8, GameTop + Round(GameH * 0.4), GameW * 3 // 4, Round(GameH * 0.45), "en", GameH < 1000 ? 2 : 1, &lines)
	if (ErrorLevel || !IsObject(lines))
		return false
	pass := "", flee := "", looksLike := V1IsFunc("RcLooksLike") ? %"RcLooksLike"% : ""   ; (v1: Func() - 0 when the program hasn't it)
	if (!IsObject(looksLike))
		return false
	for i, line in lines
		for j, word in line.words
			{
			t := RegExReplace(word.text, "[^A-Za-z0-9|]")
			if (!IsObject(pass) && looksLike.Call(t, "PASS"))
				pass := word
			else if (!IsObject(flee) && looksLike.Call(t, "FLEE"))
				flee := word
			}
	PicMeasureWhy := "PASS and FLEE not both read" (IsObject(pass) ? " (PASS read)" : IsObject(flee) ? " (FLEE read)" : "")
	if (!IsObject(pass) || !IsObject(flee))
		return false
	passX := pass.x + pass.w / 2, passY := pass.y + pass.h / 2, fleeX := flee.x + flee.w / 2
	PicMeasureWhy := "PASS and FLEE read, but not level or not round the middle"
	if (Abs(passY - (flee.y + flee.h / 2)) > GameH * 0.02 || Abs((passX + fleeX) / 2 - ScreenX) > GameW * 0.03)
		return false
	guess := (fleeX - passX) / PassFleeDist
	PicMeasureWhy := "PASS and FLEE " Round(fleeX - passX) " px apart: no UI size"
	if (guess < 0.5 || guess > 3)
		return false
	;A cut set within 3% of the guess whose own Pass button (cut at its size: it only matches nearly pixel for pixel,
	;*3) is the one on screen: that's the size - exact, and quicker than making the button at sizes round the guess
	;(that missed at 1.141 twice and once came to 1.118 for a 1.144 screen). Not as drawn: as it's drawn hovered (the
	;mouse on it), then both with more colour tolerance (PicCutFind - 2026-10-25 23:15:26 the cut 1.144 one missed at *3,
	;the screen drawn a little off all evening, and a made 1.130 set was taken for a 1.144 screen)
	near := 0, duSaid := "Pass and Flee are " Round(fleeX - passX) " px apart (UI scale about " Round(guess, 3) ")"
	for i, set in PicSets
		{
		cutPass := set.dir "\resources\roundstart.png"
		if (set.gen || Abs(set.scale / guess - 1) > 0.03 || !FileExist(cutPass))
			continue
		if (!near || Abs(set.scale - guess) < Abs(PicSets[near].scale - guess))
			near := i
		duTol := (PicCutTol > 3 ? PicCutTol : 3), duPic := "roundstart"
		if (!PicPassAt(cutPass, "*" duTol " *TransFF00FF", passX, passY, set.scale)
			&& !PicCutFind(set, ["roundstart_hover", "roundstart"], passX - 110 * set.scale, passY - 45 * set.scale, passX + 110 * set.scale, passY + 45 * set.scale, &duTol, &duPic))
			continue
		DebugLog("UI size: " duSaid "; the Pass button cut at " Round(set.scale, 3) " matches" (duPic = "roundstart_hover" ? " (drawn hovered)" : "") (duTol > 3 ? " at *" duTol : "") " - UI scale " Round(set.scale, 3))
		PicMeasuredSize := GameW "x" GameH
		if (i != PicSet)
			UsePicSet(i, "measured: " duSaid " and the Pass button cut at that size matches")
		PicCutSlackSet(duTol, duPic)
		PicCutOk()
		PicPath("resources\roundstart.png"), PicPath("resources\roundfinish.png")
		return true
		}
	;A cut set within 1% of the guess - Pass and Flee's distance is read to a pixel or two in 500: that's its size - whose
	;Pass button isn't there even so (drawn differently tonight, or something over it): its copy made 1:1 (PicCopySet) if
	;that one's Pass button is there; never a made set fine-tuned to a size a little off (as 2026-10-25 23:15:26's 1.130 for a
	;1.144 screen - every picture made at the wrong size from then on)
	if (near && Abs(PicSets[near].scale / guess - 1) <= 0.01)
		{
		cp := PicCopySet(near)
		for each, rel in ["resources\roundstart.png", "resources\roundstart_hover.png"]
			{
			cpPass := PicMake(rel, PicSets[cp])
			if (cpPass = "" || SubStr(cpPass, -4) != ".bmp" || !PicPassAt(cpPass, "*" GenTol " *TransFF00FF", passX, passY, PicSets[cp].scale, 2))
				continue
			DebugLog("UI size: " duSaid "; the Pass button cut at " Round(PicSets[near].scale, 3) " doesn't match even at *" GenTol " (drawn a little differently), its copy made at that size does" (InStr(rel, "hover") ? " (drawn hovered)" : "") " - UI scale " Round(PicSets[cp].scale, 3))
			PicMeasuredSize := GameW "x" GameH
			if (cp != PicSet)
				UsePicSet(cp, "measured: " duSaid ", the size of the cut set " PicSetName(near) " - its own Pass button doesn't match, its copy's does")
			PicPath("resources\roundstart.png"), PicPath("resources\roundfinish.png")
			return true
			}
		PicMeasureWhy := duSaid " - the cut set " PicSetName(near) "'s size, but neither its Pass button nor its copy's is there (something over it?): " PicSetName(PicSet) " kept"
		return false
		}
	;Pass and Flee say another size than the cut set in use at this window's own size: only if its own pictures haven't
	;been seen at this size for 2 minutes (the spellbook, the Pass button - PicCutOk, with this very set) - else kept, not
	;measured
	if (PicCutHome() && !PicSets[PicSet].gen && PicCutOkSize = GameW "x" GameH && PicCutOkSet = PicSet && A_TickCount - PicCutOkAt < 120000)
		{
		PicMeasureWhy := duSaid " - but " PicSetName(PicSet) "'s own pictures were seen at this window size " Round((A_TickCount - PicCutOkAt) / 1000) " s ago: kept"
		return false
		}
	PicMeasureWhy := "no Pass button picture to measure with"
	;Fine-tune: the Pass button made at sizes from 3% under the guess to 3% over, 1% apart, looked for
	;around where OCR saw it. It matches over a range of sizes (a little off still fits); the middle of
	;that range is the size (more tolerance only if it matches at none)
	srcs := PicMasters("resources\roundstart.png", guess)
	if (!srcs.Length)
		return false
	src := srcs[1].file, srcScale := srcs[1].scale
	tmp := A_Temp "\Wizard101 bot pass.bmp"
	tuneFrom := A_TickCount, fits := V1Obj()
	Loop 7
		{
		step := A_Index - 4
		if (!PicResize(src, tmp, guess * (1 + step * 0.01) / srcScale))
			continue
		sc := guess * (1 + step * 0.01)
		for each, tol in [14, 20]
			{
			V1ImageSearch(&sx, &sy, passX - 110 * sc, passY - 45 * sc, passX + 110 * sc, passY + 45 * sc, "*" tol " *TransFF00FF " tmp)
			if (ErrorLevel = 0)
				{
				fits[step] := tol
				break
				}
			}
		}
	V1Do(FileDelete, tmp)
	best := "", fitList := ""
	for each, tol in [14, 20]
		{
		lo := "", hi := ""
		for step, fitTol in fits
			if (fitTol <= tol)
				lo := (lo = "" || step < lo) ? step : lo, hi := (hi = "" || step > hi) ? step : hi
		if (lo != "")
			{
			best := guess * (1 + (lo + hi) / 2 * 0.01)
			break
			}
		}
	for step, fitTol in fits
		fitList .= (fitList = "" ? "" : ", ") (step > 0 ? "+" : "") step "%: *" fitTol
	PicMeasureWhy := "the Pass button made at that size doesn't match"
	if (best = "")
		{
		DebugLog("UI size: Pass and Flee are " Round(fleeX - passX) " px apart (UI scale about " Round(guess, 3) "), but the Pass button made at that size doesn't match")
		return false
		}
	;(a set within 1.5% of it already: that one - the Pass button matches a range of sizes that wide)
	sc := Round(best, 3), found := PicSetFor(sc, 0.015)
	;...but only if its own Pass button matches the one on screen now (else it would detect again and
	;again, never playing the round): otherwise a set at exactly this size
	if (PicSets[found].scale != sc)
		{
		other := PicSets[found]
		p := other.gen ? PicMake("resources\roundstart.png", other) : other.dir "\resources\roundstart.png"
		if (!PicPassAt(p, other.gen ? "*" GenTol " *TransFF00FF" : "*" (PicCutTol > 3 ? PicCutTol : 3), passX, passY, sc))
			found := PicSetFor(sc, 0)
		}
	DebugLog("UI size: " duSaid "; the Pass button made at that size and a bit off matches at " fitList " - UI scale " sc " (" A_TickCount - tuneFrom " ms)")
	PicMeasuredSize := GameW "x" GameH
	UsePicSet(found, "measured: " duSaid ", the Pass button made at sizes round that fits best at " sc " (no cut set within 1% of it, nor one whose Pass button is there)")
	;made now, so the round start and the spellbook are known from here on
	PicPath("resources\roundstart.png"), PicPath("resources\roundfinish.png")
	return true
	}

;Pass button picture file (ImageSearch options opts) round where PASS was read (passX, passY, at UI scale sc) - looked
;for up to tries times, 150 ms apart: the button's look changes for a moment now and then (2026-10-21 20:42 the cut
;1.144 one missed once and a made 1.141 set was used instead). True if found
PicPassAt(file, opts, passX, passY, sc, tries := 5)
	{
	Loop tries
		{
		if (A_Index > 1)
			Sleep(150)
		V1ImageSearch(&sx, &sy, passX - 110 * sc, passY - 45 * sc, passX + 110 * sc, passY + 45 * sc, opts " " file)
		if (ErrorLevel = 0)
			return true
		}
	return false
	}

;No picture set finds the spellbook icon (out of battle, at a UI size never seen): finds the size from
;the icon. It's small and plain, so it matches over a range of sizes: every size from 0.6 to 2.2 (2%
;apart) is tried, the run of sizes that match is looked at again 0.5% apart with less colour
;tolerance, and the middle of what still matches is the size. Takes about 10 s. Less exact than
;DetectUiScale (the Pass button in a battle). Returns the UI scale, 0 if not found
PicScaleFromBook()
	{
	x1 := GameLeft + GameW * 3 // 5, y1 := GameTop + GameH * 3 // 5, x2 := GameLeft + GameW, y2 := GameTop + GameH
	tmp := A_Temp "\Wizard101 bot book.bmp"
	;Every size, smallest first; the longest run of sizes in a row that match
	sizes := [], sc := 0.6
	while (sc <= 2.2)
		sizes.Push(sc), sc *= 1.02
	bestLo := 0, bestHi := -1, runLo := 0
	for i, sc in sizes
		{
		if (PicScaleTry("resources\roundfinish.png", sc, tmp, x1, y1, x2, y2, 20))
			{
			if (!runLo)
				runLo := i
			if (i - runLo > bestHi - bestLo)
				bestLo := runLo, bestHi := i
			}
		else
			runLo := 0
		}
	if (!bestLo)
		{
		V1Do(FileDelete, tmp)
		return 0
		}
	;That run (and a step either side) again, 0.5% apart: the middle of what matches with the least
	;tolerance that matches anything there
	from := sizes[bestLo] / 1.02, to := sizes[bestHi] * 1.02, fine := []
	sc := from
	while (sc <= to)
		fine.Push(sc), sc *= 1.005
	for each, tol in [8, 12, 16, 20]
		{
		lo := 0, hi := 0
		for i, sc in fine
			if (PicScaleTry("resources\roundfinish.png", sc, tmp, x1, y1, x2, y2, tol))
				lo := lo ? lo : sc, hi := sc
		if (lo)
			break
		}
	V1Do(FileDelete, tmp)
	return lo ? Round(Sqrt(lo * hi), 3) : Round(Sqrt(sizes[bestLo] * sizes[bestHi]), 3)
	}

;Makes picture rel at UI scale sc into tmp and looks for it in the rectangle. True if it's there
PicScaleTry(rel, sc, tmp, x1, y1, x2, y2, tol)
	{
	srcs := PicMasters(rel, sc)
	if (!srcs.Length || !PicResize(srcs[1].file, tmp, sc / srcs[1].scale))
		return false
	V1ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" tol " *TransFF00FF " tmp)
	return (ErrorLevel = 0)
	}

;The set for UI scale sc: the nearest cut or made one there already is within the share `within` of
;it, else a new made one (generated\ui<sc>). Returns its index in PicSets
PicSetFor(sc, within := 0.005)
	{
	near := 0
	for i, set in PicSets
		if (Abs(set.scale - sc) <= sc * within && (!near || Abs(set.scale - sc) < Abs(PicSets[near].scale - sc)))
			near := i
	if (near)
		return near
	dir := GenRoot "\ui" Round(sc, 3)
	V1Do(DirCreate, dir)
	PicSets.Push(V1Obj({dir: dir, scale: Round(sc, 3) + 0, gen: 1}))
	return PicSets.Length
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
PicScaleBlank()
	{
	global GenTol := "", GenRoot := "", PassFleeDist := "", PicEnlarged := "", PicMade := "", PicMeasuredSize := "", PicMeasureSize := ""
	global PicMeasureTries := "", PicMeasureWhy := "", PicCutTol := "", PicCutOkAt := "", PicCutOkSize := "", PicCutOkSet := "", PicCutTolPic := ""
	global PicCutLowAt := "", PicCutSlackKey := ""
	}
