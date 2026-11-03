"""test_ahk_names.py - AutoHotkey v2 names that turn a function call into an unset variable - static checks on every
.ahk file in the repository, no AutoHotkey:  python3 -m unittest test_ahk_names  (from AutoFarmer\\vision)

AutoHotkey v2 keeps variables and functions in one name space, case-insensitive. In a function that assumes locals
(no bare "global" line), any assignment - :=, +=, .=, ++, a for-loop variable, catch ... as, an &out parameter - makes
the name local for the whole function. So in v1.1.0-v1.9.0's SpeedCheatEngine, "ceDir := CeDir()" made ceDir local
and CeDir() called that unset local: "This local variable has not been assigned a value" at every bot start with the
speedhack on. CI's load check can't see it - it only shows when the line runs. This test fails on any function that
calls (or hands over as a callback) a function whose name one of its own locals takes."""
import os
import re
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))   # the repository

# AutoHotkey v2's built-in functions and classes a script calls by name (a local named like one hides it the same way)
BUILTINS = set(n.lower() for n in """
Abs ACos ASin ATan BlockInput Buffer CallbackCreate CallbackFree CaretGetPos Ceil Chr Click ClipboardAll ClipWait
ComCall ComObjActive ComObjConnect ComObject ComObjFlags ComObjFromPtr ComObjGet ComObjQuery ComObjType ComObjValue
ComValue ControlAddItem ControlChooseIndex ControlChooseString ControlClick ControlDeleteItem ControlFindItem
ControlFocus ControlGetChecked ControlGetChoice ControlGetClassNN ControlGetEnabled ControlGetExStyle ControlGetFocus
ControlGetHwnd ControlGetIndex ControlGetItems ControlGetPos ControlGetStyle ControlGetText ControlGetVisible
ControlHide ControlHideDropDown ControlMove ControlSend ControlSendText ControlSetChecked ControlSetEnabled
ControlSetExStyle ControlSetStyle ControlSetText ControlShow ControlShowDropDown CoordMode Cos Critical DateAdd
DateDiff DetectHiddenText DetectHiddenWindows DirCopy DirCreate DirDelete DirExist DirMove DirSelect DllCall Download
DriveEject DriveGetCapacity DriveGetFileSystem DriveGetLabel DriveGetList DriveGetSerial DriveGetSpaceFree
DriveGetStatus DriveGetStatusCD DriveGetType DriveLock DriveRetract DriveSetLabel DriveUnlock Edit EditGetCurrentCol
EditGetCurrentLine EditGetLine EditGetLineCount EditGetSelectedText EditPaste EnvGet EnvSet Exit ExitApp Exp
FileAppend FileCopy FileCreateShortcut FileDelete FileEncoding FileExist FileGetAttrib FileGetShortcut FileGetSize
FileGetTime FileGetVersion FileInstall FileMove FileOpen FileRead FileRecycle FileRecycleEmpty FileSelect
FileSetAttrib FileSetTime Float Floor Format FormatTime GetKeyName GetKeySC GetKeyState GetKeyVK GetMethod
GroupActivate GroupAdd GroupClose GroupDeactivate Gui GuiCtrlFromHwnd GuiFromHwnd HasBase HasMethod HasProp HotIf
HotIfWinActive HotIfWinExist HotIfWinNotActive HotIfWinNotExist Hotkey Hotstring IL_Add IL_Create IL_Destroy
ImageSearch IniDelete IniRead IniWrite InputBox InputHook InstallKeybdHook InstallMouseHook InStr Integer IsLabel
IsObject IsSet IsSetRef KeyHistory KeyWait ListHotkeys ListLines ListVars ListViewGetContent Ln LoadPicture Log LTrim
Max MenuFromHandle MenuSelect Min Mod MonitorGet MonitorGetCount MonitorGetName MonitorGetPrimary MonitorGetWorkArea
MouseClick MouseClickDrag MouseGetPos MouseMove MsgBox Number NumGet NumPut ObjAddRef ObjBindMethod ObjFromPtr
ObjFromPtrAddRef ObjGetBase ObjGetCapacity ObjHasOwnProp ObjOwnPropCount ObjOwnProps ObjPtr ObjPtrAddRef ObjRelease
ObjSetBase ObjSetCapacity OnClipboardChange OnError OnExit OnMessage Ord OutputDebug Pause Persistent PixelGetColor
PixelSearch PostMessage ProcessClose ProcessExist ProcessGetName ProcessGetParent ProcessGetPath ProcessSetPriority
ProcessWait ProcessWaitClose Random RegCreateKey RegDelete RegDeleteKey RegExMatch RegExReplace RegRead RegWrite
Reload Round RTrim Run RunAs RunWait Send SendEvent SendInput SendLevel SendMessage SendMode SendPlay SendText
SetCapsLockState SetControlDelay SetDefaultMouseSpeed SetKeyDelay SetMouseDelay SetNumLockState SetRegView
SetScrollLockState SetStoreCapsLockMode SetTimer SetTitleMatchMode SetWinDelay SetWorkingDir Shutdown Sin Sleep Sort
SoundBeep SoundGetInterface SoundGetMute SoundGetName SoundGetVolume SoundPlay SoundSetMute SoundSetVolume SplitPath
Sqrt StatusBarGetText StatusBarWait StrCompare StrGet String StrLen StrLower StrPtr StrPut StrReplace StrSplit
StrTitle StrUpper SubStr Suspend SysGet SysGetIPAddresses Tan Thread ToolTip TraySetIcon TrayTip Trim Type
VarSetStrCapacity VerCompare WinActivate WinActivateBottom WinActive WinClose WinExist WinGetClass WinGetClientPos
WinGetControls WinGetControlsHwnd WinGetCount WinGetExStyle WinGetID WinGetIDLast WinGetList WinGetMinMax WinGetPID
WinGetPos WinGetProcessName WinGetProcessPath WinGetStyle WinGetText WinGetTitle WinGetTransColor WinGetTransparent
WinHide WinKill WinMaximize WinMinimize WinMinimizeAll WinMinimizeAllUndo WinMove WinMoveBottom WinMoveTop WinRedraw
WinRestore WinSetAlwaysOnTop WinSetEnabled WinSetExStyle WinSetRegion WinSetStyle WinSetTitle WinSetTransColor
WinSetTransparent WinShow WinWait WinWaitActive WinWaitClose WinWaitNotActive IsAlnum IsAlpha IsDigit IsFloat
IsInteger IsLower IsNumber IsSpace IsTime IsUpper IsXDigit Array Map Object Error Func Menu OSError TargetError
TimeoutError TypeError UnsetError MemberError PropertyError MethodError IndexError ValueError ZeroDivisionError
""".split())

KEYWORDS = set("""if else while loop for in return break continue try catch finally throw switch case default until
global local static and or not is unset goto class""".split())
ID = r'[A-Za-z_]\w*'
HEADER = re.compile(r'^\s*(?:static\s+)?(' + ID + r')\((.*)\)\s*(\{)?\s*$')
# a function handed over by name, not called: the callback's name is read as a variable too
CALLBACKS = (r'SetTimer\(\s*{n}\b', r'OnExit\(\s*{n}\b', r'OnError\(\s*{n}\b', r'OnClipboardChange\(\s*{n}\b',
             r'CallbackCreate\(\s*{n}\b', r'OnMessage\([^,()]+,\s*{n}\b', r'Hotkey\([^,()]+,\s*{n}\b',
             r'\.OnEvent\([^,()]+,\s*{n}\b', r'(?<![\w.]){n}\.Bind\(', r'ObjBindMethod\(\s*{n}\b')


def code_lines(text):
    """each line's code: strings blanked, ; comments and /* */ blocks dropped"""
    out, block = [], False
    for ln in text.splitlines():
        s = ln.strip()
        if block:
            block = not s.startswith('*/')
            out.append('')
            continue
        if s.startswith('/*'):
            block = True
            out.append('')
            continue
        ln = re.sub(r'"(?:[^"`]|`.)*"', '""', ln)
        ln = re.sub(r"'(?:[^'`]|`.)*'", "''", ln)
        out.append(re.sub(r'(^|\s);.*$', '', ln))
    return out


def functions(text):
    """[(name, params, header line number, [(line number, code), ...])] - every function and method body"""
    lines = code_lines(text)
    out, depth, i, classes = [], 0, 0, []
    while i < len(lines):
        s = lines[i]
        top = depth == 0 or (classes and depth == classes[-1])
        if top and re.match(r'^\s*class\s+' + ID, s, re.I):
            j = i
            while j < len(lines) - 1 and '{' not in lines[j]:
                j += 1
            depth += sum(lines[k].count('{') - lines[k].count('}') for k in range(i, j + 1))
            classes.append(depth)
            i = j + 1
            continue
        m = HEADER.match(s) if top else None
        if m and m.group(1).lower() not in KEYWORDS:
            j = i + 1
            if m.group(3) is None:
                while j < len(lines) and not lines[j].strip():
                    j += 1
                if j >= len(lines) or not lines[j].strip().startswith('{'):
                    depth += s.count('{') - s.count('}')
                    i += 1
                    continue
            d, body, k = 0, [], i
            while k < len(lines):
                d += lines[k].count('{') - lines[k].count('}')
                if k > i:
                    body.append((k + 1, lines[k]))
                if d <= 0 and (k > i or m.group(3)) and any('{' in t for _, t in body + [(0, s)]):
                    break
                k += 1
            out.append((m.group(1), m.group(2), i + 1, body))
            i = k + 1
            continue
        depth += s.count('{') - s.count('}')
        while classes and depth < classes[-1]:
            classes.pop()
        i += 1
    return out


def locals_of(params, body):
    """the names a function's code makes local ({lower name: line}), and whether it assumes globals"""
    names, declared_global, assume_global = {}, set(), False
    for p in re.findall(r'(?:^|,)\s*(?:ByRef\s+)?&?\s*(' + ID + r')', params):
        names.setdefault(p.lower(), 0)
    for n, t in body:
        st = t.strip()
        g = re.match(r'^global\b(.*)$', st, re.I)
        if g:
            if not g.group(1).strip():
                assume_global = True
            declared_global |= {x.lower() for x in re.findall(r'(?:^|,)\s*(' + ID + r')', re.sub(r':=[^,]*', '', g.group(1)))}
            continue
        d = re.match(r'^(?:local|static)\b(.*)$', st, re.I)
        if d:
            for x in re.findall(r'(?:^|,)\s*(' + ID + r')', re.sub(r':=[^,]*', '', re.sub(r'\([^()]*\)', '', d.group(1)))):
                names.setdefault(x.lower(), n)
        for x in re.findall(r'(?<![\w.\]\)%])(' + ID + r')\s*(?::=|\+=|-=|\*=|/=|//=|\.=|\|=|&=|\^=|>>=|<<=|\?\?=)(?!=)', t):
            names.setdefault(x.lower(), n)
        for x in re.findall(r'(?<![\w.%])(' + ID + r')(?:\+\+|--)', t):
            names.setdefault(x.lower(), n)
        f = re.match(r'^for\s+(' + ID + r')(?:\s*,\s*(' + ID + r'))?\s+in\b', st, re.I)
        if f:
            for x in f.groups():
                if x:
                    names.setdefault(x.lower(), n)
        c = re.search(r'\bcatch\b[^{]*?\bas\s+(' + ID + r')', st, re.I)
        if c:
            names.setdefault(c.group(1).lower(), n)
        for x in re.findall(r'&(' + ID + r')', t):
            names.setdefault(x.lower(), n)
    return {k: v for k, v in names.items() if k not in declared_global and k not in KEYWORDS}, assume_global


def hidden_calls(text, known):
    """[(header line, function, name, line it's made local, line it's called)] - a local named like a function in
    known (lower names) that the same function calls or hands over as a callback"""
    hits = []
    for fname, params, at, body in functions(text):
        names, assume_global = locals_of(params, body)
        if assume_global:
            continue
        code = '\n'.join(t for _, t in body)
        for name, made in names.items():
            if name not in known:
                continue
            pats = [r'(?<![\w.%])' + re.escape(name) + r'\('] + [p.format(n=re.escape(name)) for p in CALLBACKS]
            for n, t in body:
                if any(re.search(p, t, re.I) for p in pats):
                    hits.append((at, fname, name, made, n))
                    break
    return hits


def ahk_files():
    try:
        out = subprocess.run(['git', 'ls-files', '*.ahk'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        files = [os.path.join(ROOT, f) for f in out.split()]
    except (OSError, subprocess.CalledProcessError):
        files = []
    if not files:   # not a git checkout (an unzipped release): walk the folders
        for d, _, fs in os.walk(ROOT):
            files += [os.path.join(d, f) for f in fs if f.lower().endswith('.ahk')]
    return sorted(files)


def read(path):
    with open(path, encoding='utf-8-sig', errors='replace') as f:
        return f.read()


class HiddenCalls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = ahk_files()
        cls.texts = {p: read(p) for p in cls.files}
        cls.known = set(BUILTINS)
        for t in cls.texts.values():
            cls.known |= {f[0].lower() for f in functions(t)}

    def test_finds_the_files(self):
        names = {os.path.basename(p) for p in self.files}
        for must in ('Autofarmer.ahk', 'CheatEngine.ahk', 'Setup.ahk', 'Walker.ahk', 'V1Compat.ahk'):
            self.assertIn(must, names)
        self.assertGreater(sum(len(functions(t)) for t in self.texts.values()), 1500)

    def test_no_local_hides_a_function_it_calls(self):
        bad = []
        for p, t in self.texts.items():
            for at, fname, name, made, n in hidden_calls(t, self.known):
                bad.append('%s:%d %s(): local %r (line %d) hides the function it calls at line %d'
                           % (os.path.relpath(p, ROOT), at, fname, name, made, n))
        self.assertEqual(bad, [], '\n'.join(bad))

    def test_the_v190_speedhack_line_is_caught(self):
        """the checker itself: v1.9.0's SpeedCheatEngine, CeStart and a built-in's case"""
        known = {'cedir', 'ceexe', 'cescriptpath', 'round'}
        old = ('SpeedCheatEngine(why) {\nstatic saidNoScript := false\nceDir := CeDir()\n'
               'if (ceDir = "" || !FileExist(CeScriptPath(ceDir)))\n\treturn\n}\n'
               'CeStart(dir)\n\t{\n\tceExe := CeExe(dir)\n\treturn ceExe\n\t}\n'
               'Half(n)\n\t{\n\tfor i, round in [1, 2]\n\t\tn := Round(n / 2)\n\treturn n\n\t}\n')
        self.assertEqual([(h[1], h[2]) for h in hidden_calls(old, known)],
                         [('SpeedCheatEngine', 'cedir'), ('CeStart', 'ceexe'), ('Half', 'round')])
        ok = ('SpeedCheatEngine(why) {\nsceDir := CeDir()\nreturn sceDir\n}\n'
              'Glob()\n\t{\n\tglobal ceDir\n\tceDir := CeDir()\n\t}\n'
              'Assume()\n\t{\n\tglobal\n\tx := CeDir()\n\t}\n')
        self.assertEqual(hidden_calls(ok, known), [])

    def test_callbacks_count_as_calls(self):
        known = {'tick'}
        src = 'Start()\n\t{\n\ttick := 0\n\tSetTimer(Tick, 1000)\n\t}\n'
        self.assertEqual([h[2] for h in hidden_calls(src, known)], ['tick'])

    def test_speedhack_path_names(self):
        af = '\n'.join(code_lines(self.texts[os.path.join(ROOT, 'AutoFarmer', 'Autofarmer.ahk')]))
        ce = '\n'.join(code_lines(self.texts[os.path.join(ROOT, 'CheatEngine.ahk')]))
        self.assertRegex(af, r'\bsceDir := CeDir\(\)')
        self.assertNotRegex(af + ce, r'(?i)\bcedir\s*:=|\bceexe\s*:=')

    def test_cheat_engine_start(self):
        """v1.9.1: CeStart doesn't wait for Windows' admin question (Cheat Engine 7.4 / 7.5 run only as admin - a plain
        Run waits for the answer): cmd's start asks in its own hidden window. Then its own window is minimized once it
        shows ("Cheat Engine.exe" is a launcher: Run's "Min" never reaches that window) - on a timer, the way the
        taskbar does it, never one of its message boxes; the search runs only on the timer's own thread"""
        ce = '\n'.join(self.texts[os.path.join(ROOT, 'CheatEngine.ahk')].splitlines())
        start = re.search(r'(?ms)^CeStart\(dir\)\n\t\{\n(.*?)^\t\}', ce).group(1)
        self.assertIn('V1Run("`"" A_ComSpec "`" /c start `"`" `"" csExe "`"", dir, "Hide") != 0', start)
        self.assertRegex(start, r'(?m)^\tCeMinimizeSoon\(true\)\n\treturn true$')
        mini = re.search(r'(?ms)^CeMinimizeSoon\(start := false\)\n\t\{\n(.*?)^\t\}', ce).group(1)
        for must in ('SetTimer(CeMinimizeSoon, -500)', 'DetectHiddenWindows(false)', '!= "#32770"',
                     'PostMessage(0x0112, 0xF020, 0, , "ahk_id " cmsHwnd)', '"Cheat Engine"'):
            self.assertIn(must, mini)
        self.assertLess(mini.index('return'), mini.index('DetectHiddenWindows'))


if __name__ == '__main__':
    unittest.main()
