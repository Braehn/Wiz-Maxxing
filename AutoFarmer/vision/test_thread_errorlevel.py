"""test_thread_errorlevel.py - every thread a script starts keeps the interrupted thread's ErrorLevel (the scripts' text
read, not run). Standard library only: python -m unittest test_thread_errorlevel  (from AutoFarmer\\vision)

2026-11-21 16:18 (JSHSRVRWINB, v1.14.4): "Error: Expected a Number but got an empty string" at the round start's
DebugLog("Round start: Pass button at " startX - GameLeft ...). The port's ErrorLevel is one global variable (v1's was
the thread's own); a callback that can change it starts with  local v1Keep := V1Thread()  (V1Compat.ahk), which puts
the interrupted thread's back when it returns. GamePriorityTick - the 5 s timer gamehigh added (v1.14.4) - had none: it
logged "Wizard101 (pid 18144) at High priority now" (DebugLog sets ErrorLevel 0) between the round start's Pass search
(not found: x, y blank, ErrorLevel 1) and its ErrorLevel check, so a Pass button that wasn't there was "found" with no
position. Pins: every timer, GUI event, menu item (Add and Insert), hotkey (Hotkey / HkTry, Key:: lines and blocks, HotIf
criteria), OnMessage / OnExit / OnError / OnNotify, InputHook callback whose function can reach ErrorLevel - directly,
through what it calls by name, or by calling something it can't name (%name%(), a function passed in) - starts with a
V1Thread; a callback the scan can't find the function of is named (a fat-arrow function counts as one with no V1Thread);
and the round start takes its answer from PassButtonAt's return, never a found Pass without its position."""
import os
import re
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def strip_code(line):
    """the line without its ; comment, strings' text kept (their quotes too) - a ; inside a string isn't a comment"""
    out, i, n, q = [], 0, len(line), None
    while i < n:
        c = line[i]
        if q:
            if c == "`" and i + 1 < n:
                out.append(line[i:i + 2])
                i += 2
                continue
            if c == q:
                q = None
            out.append(c)
            i += 1
            continue
        if c in "\"'":
            q = c
        elif c == ";" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(c)
        i += 1
    return "".join(out)


def no_strings(code):
    return re.sub(r'"(?:`.|[^"`])*"|\'(?:`.|[^\'`])*\'', '""', code)


PARAMS = r"([^()]*(?:\([^()]*\)[^()]*)*)"
FUNC_DEF = re.compile(r"^(\w+)\(" + PARAMS + r"\)\s*(\{)?\s*$")
FUNC_ARROW = re.compile(r"^(\w+)\(" + PARAMS + r"\)\s*=>\s*(.+)$")
KEYWORDS = {"if", "while", "for", "switch", "catch", "Loop", "return", "else", "until", "try", "finally"}


def param_names(params):
    """a definition's parameter names (&x, y := 1, z*, * - the name of each, a bare * none)"""
    out = []
    for p in params.split(","):
        m = re.match(r"\s*&?(\w+)", p)
        if m:
            out.append(m.group(1))
    return out


def load(root=ROOT):
    """{rel path: lines} of every .ahk, and {function name: [{rel, line, body, code, params, arrow}]} - top-level
    functions, a fat-arrow one (Name(...) => expr) too"""
    files, defs = {}, {}
    for d, subs, fs in os.walk(root):
        subs[:] = [s for s in subs if not s.startswith(".")]
        for f in fs:
            if f.lower().endswith(".ahk"):
                p = os.path.join(d, f)
                with open(p, encoding="utf-8-sig", errors="replace") as fh:
                    files[os.path.relpath(p, root)] = fh.read().replace("\r\n", "\n").split("\n")
    for rel, lines in files.items():
        i = 0
        while i < len(lines):
            head = strip_code(lines[i]).rstrip()
            a = FUNC_ARROW.match(head)
            if a and a.group(1) not in KEYWORDS:
                defs.setdefault(a.group(1), []).append(dict(rel=rel, line=i + 1, body=[lines[i]], code=a.group(3),
                                                            params=param_names(a.group(2)), arrow=True))
                i += 1
                continue
            m = FUNC_DEF.match(head)
            if m and m.group(1) not in KEYWORDS:
                depth, j, started, code = 0, i, False, []
                while j < len(lines):
                    sc = strip_code(lines[j])
                    ns = no_strings(sc)
                    if j > i or m.group(3):
                        depth += ns.count("{") - ns.count("}")
                        started = started or "{" in ns
                    code.append(sc)
                    if started and depth <= 0:
                        break
                    if not started and j > i + 2:
                        break
                    j += 1
                if started:
                    defs.setdefault(m.group(1), []).append(dict(rel=rel, line=i + 1, body=lines[i:j + 1], code="\n".join(code),
                                                                params=param_names(m.group(2)), arrow=False))
                    i = j + 1
                    continue
            i += 1
    return files, defs


KEEP = re.compile(r"local \w+ := V1Thread\(\)")
DECL = re.compile(r"(global|static|local)(\s|$)")


def first_statement(body_lines):
    """the function's (or a hotkey block's) first statement after its opening brace - declarations skipped: global / local
    ones without a call, static ones whatever their initializer (run once, the first time: static busy := 0, raised := Map())"""
    head = strip_code(body_lines[0])
    rest = [head.split("{", 1)[1]] if "{" in no_strings(head) else []
    for ln in rest + body_lines[1:]:
        s = strip_code(ln).strip()
        if s in ("{", ""):
            continue
        if re.match(r"static\s", s) or (DECL.match(s) and not re.search(r"\w\(", no_strings(s))):
            continue
        return s
    return ""


CALL = re.compile(r"(?<![\w.%])(\w+)\(|(?<![\w.])(\w+)\.Call\(|%\"(\w+)\"%")
DYNAMIC = re.compile(r"%(?!\")[^%\n]+%\s*(?:\(|\.Call\()")


def unnamed_calls(code, params):
    """what a body calls that the scan can't name: %name%() / %name%.Call() by a variable, a parameter called (a function
    passed in) - "" none"""
    m = DYNAMIC.search(code)
    if m:
        return "a call by a variable's name (" + m.group(0).strip() + ")"
    for p in params:
        if re.search(r"(?<![\w.%])" + p + r"\(|(?<![\w.])" + p + r"\.Call\(", code):
            return "a function passed in (" + p + ")"
    return ""


class Graph:
    def __init__(self, defs):
        self.defs, self.memo = defs, {}

    def keeps(self, name):
        """every definition of name starts with local <x> := V1Thread() (a fat-arrow function can't)"""
        return all(not d["arrow"] and KEEP.match(first_statement(d["body"])) for d in self.defs[name])

    def code_reach(self, code, skip=()):
        """the chain from a piece of code to ErrorLevel - itself, or a function it calls by name ([] none)"""
        if re.search(r"\bErrorLevel\b", no_strings(code)):
            return ["(itself)"]
        best = []
        for m in CALL.finditer(code):
            callee = m.group(1) or m.group(2) or m.group(3)
            if callee in skip or callee == "V1Thread" or callee not in self.defs:
                continue
            sub = self.reach(callee, tuple(skip))
            if sub and (not best or len(sub) < len(best)):
                best = sub
        return best

    def reach(self, name, stack=()):
        """the call chain from name to a function that reads or sets ErrorLevel, [] if none (functions called by name)"""
        if name in self.memo:
            return self.memo[name]
        if name in stack or name not in self.defs:
            return []
        best = []
        for d in self.defs[name]:
            sub = self.code_reach(d["code"], stack + (name,))
            if sub:
                best = [name] + ([] if sub == ["(itself)"] else sub)
                if len(best) == 1:
                    break
        if not stack or best:
            self.memo[name] = best
        return best

    def entry_reach(self, name):
        """reach() - or, for a callback itself, a call it makes that the scan can't name (it may reach anything)"""
        chain = self.reach(name)
        if chain:
            return chain
        for d in self.defs[name]:
            why = unnamed_calls(d["code"], d["params"])
            if why:
                return [name, why]
        return []


def call_args(s, start):
    """the arguments of the call whose ( ends at s[start - 1]"""
    depth, cur, out, i, q = 0, [], [], start, None
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == "`" and i + 1 < len(s):
                cur.append(s[i + 1])
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if c == '"':
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                out.append("".join(cur).strip())
                return out
            depth -= 1
        elif c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    out.append("".join(cur).strip())
    return out


def callback_funcs(expr, defs):
    """(functions, unknown): the functions a callback expression runs - Name, Name.Bind(...), %"Name"%, (*) => Name(...) -
    and unknown, a name shaped like a callback that isn't a top-level function here (a variable holding one, a method,
    a nested function: the scan can't follow it) - "" none. Neither: a string ("On", "Off", an option string), an
    expression"""
    expr = expr.strip()
    for rx in (r"%\"(\w+)\"%$", r"(\w+)\.Bind\(", r"(\w+)$"):
        m = re.match(rx, expr)
        if m:
            return ([m.group(1)], "") if m.group(1) in defs else ([], m.group(1))
    m = re.match(r"\([^)]*\)\s*=>\s*(.*)", expr, re.S)
    if m:
        return [c for c in re.findall(r"(?<![\w.])(\w+)\(", m.group(1)) if c in defs], ""
    return [], ""


# (the call, which argument is the callback - Menu.Insert(before, name, callback): its third)
ENTRIES = [("SetTimer", re.compile(r"(?<![\w.])SetTimer\("), 0),
           ("OnEvent", re.compile(r"\.OnEvent\("), 1),
           ("OnNotify", re.compile(r"\.On(?:Notify|Command)\("), 1),
           ("OnMessage", re.compile(r"(?<![\w.])OnMessage\("), 1),
           ("Hotkey", re.compile(r"(?<![\w.])(?:Hotkey|HkTry)\("), 1),
           ("HotIf", re.compile(r"(?<![\w.#])HotIf\("), 0),
           ("Menu", re.compile(r"\.Add\("), 1),
           ("Menu", re.compile(r"\.Insert\("), 2),
           ("OnExit", re.compile(r"(?<![\w.])OnExit\("), 0),
           ("OnError", re.compile(r"(?<![\w.])OnError\("), 0),
           ("OnClipboardChange", re.compile(r"(?<![\w.])OnClipboardChange\("), 0)]
HOOK_PROP = re.compile(r"\.On(?:KeyDown|KeyUp|Char|End)\s*:=\s*(.+)$")
HOTKEY_LABEL = re.compile(r"^([^\s;\"(][^\"]*?)::(.*)$")
HOTIF_DIRECTIVE = re.compile(r"^#HotIf\s+(.+)$", re.I)

# Callback-shaped names that aren't top-level functions, each where it's set (what the scan can't follow - checked by
# hand 2026-11-21): a variable holding the function, or an expression's word
UNKNOWN_OK = {
    "action": "Hotkeys.ahk HkTry(key, action, opts): its callers' action - HkRun.Bind(run) (checked) or \"Off\"",
}


def entries(files, defs):
    """[(kind, rel, line, callback function)] - every thread a script starts with a function of its own; a Key:: block
    is (HotkeyBlock, rel, line, None); one the scan can't follow is (Unknown, rel, line, its name)"""
    out = []
    for rel, lines in files.items():
        for no, line in enumerate(lines, 1):
            code = strip_code(line)
            menu_add = code.find(".Add(")
            for kind, rx, argi in ENTRIES:
                for m in rx.finditer(code):
                    a = call_args(code, m.end())
                    if len(a) <= argi:
                        continue
                    fs, unknown = callback_funcs(a[argi], defs)
                    # (a Gui's Add takes an option string there, a Map's or an Array's anything: a menu's only when its
                    # callback is a function - an unknown word there is no menu item)
                    if kind == "Menu" and not fs:
                        continue
                    out += [(kind, rel, no, f) for f in fs]
                    if unknown and kind != "Menu":
                        out.append(("Unknown", rel, no, unknown))
            m = HOOK_PROP.search(code)
            if m:
                fs, unknown = callback_funcs(m.group(1), defs)
                out += [("InputHook", rel, no, f) for f in fs]
                if unknown:
                    out.append(("Unknown", rel, no, unknown))
            m = HOTIF_DIRECTIVE.match(code.strip())
            if m:
                out += [("HotIf", rel, no, f) for f in callback_funcs("() => " + m.group(1), defs)[0]]
            m = HOTKEY_LABEL.match(line)
            if m and not line.startswith("::") and "(" not in m.group(1):
                body = strip_code(m.group(2)).strip()
                if body.startswith("{"):
                    out.append(("HotkeyBlock", rel, no, None))
                elif body:
                    out += [("HotkeyLabel", rel, no, f) for f in callback_funcs("() => " + body, defs)[0]]
                else:
                    out.append(("HotkeyBlock", rel, no, None))
    return out


def block_at(lines, no):
    """a Key:: block's lines - from its { (on the label's line or the next one) to its matching } - [] when it has none
    (a stacked hotkey: Enter:: falls to NumpadEnter::Fn())"""
    i = no - 1
    head = strip_code(lines[i]).split("::", 1)[1]
    if "{" not in no_strings(head):
        i += 1
        while i < len(lines) and not strip_code(lines[i]).strip():
            i += 1
        if i >= len(lines) or not strip_code(lines[i]).strip().startswith("{"):
            return []
    depth, j = 0, i
    while j < len(lines):
        ns = no_strings(strip_code(lines[j] if j != no - 1 else head))
        depth += ns.count("{") - ns.count("}")
        if depth <= 0 and "{" in no_strings("".join(strip_code(x) for x in lines[i:j + 1])):
            break
        j += 1
    return ["{"] + lines[i + 1 if j > i or "{" in no_strings(head) else i:j + 1] if "{" in no_strings(head) else lines[i:j + 1]


class ThreadsKeepErrorLevel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files, cls.defs = load()
        cls.g = Graph(cls.defs)
        cls.entries = entries(cls.files, cls.defs)

    def test_every_callback_that_reaches_errorlevel_keeps_it(self):
        bad = []
        for kind, rel, no, fn in self.entries:
            if fn is None or kind == "Unknown":
                continue
            chain = self.g.entry_reach(fn)
            if chain and not self.g.keeps(fn):
                bad.append("%s:%d %s %s - reaches ErrorLevel: %s" % (rel, no, kind, fn, " -> ".join(chain)))
        self.assertEqual(sorted(set(bad)), [], "a thread's callback without  local v1Keep := V1Thread()  first")

    def test_no_callback_the_scan_cant_follow(self):
        """a callback-shaped name that isn't a top-level function (a method, a nested function, a variable) is one the
        scan can't check: each known one is listed in UNKNOWN_OK with where it's set"""
        unknown = sorted({"%s:%d %s" % (rel, no, fn) for kind, rel, no, fn in self.entries
                          if kind == "Unknown" and fn not in UNKNOWN_OK})
        self.assertEqual(unknown, [], "a callback the scan can't follow: make it a top-level function, or list it")

    def test_hotkey_blocks(self):
        """a Key:: block (a thread of its own, its { on the label's line or the next) that reaches ErrorLevel keeps it - or
        is the pet trainer's, which starts no other thread (no timer, GUI, message or menu) that could be interrupted"""
        blocks = [(rel, no) for kind, rel, no, fn in self.entries if kind == "HotkeyBlock"]
        self.assertTrue(blocks, "the scan finds the Key:: blocks")
        for rel, no in blocks:
            lines = self.files[rel]
            blk = block_at(lines, no)
            if not blk:
                continue
            chain = self.g.code_reach("\n".join(strip_code(x) for x in blk))
            if not chain or KEEP.match(first_statement(blk)):
                continue
            self.assertTrue(rel.startswith("AutoPetTrainer"), "%s:%d - a Key:: block reaching ErrorLevel (%s) without its V1Thread"
                            % (rel, no, " -> ".join(chain)))
            pt = "\n".join(strip_code(x) for x in self.files[rel])
            self.assertNotRegex(pt, r"(?<![\w.])SetTimer\(|\.OnEvent\(|OnMessage\(|\.Add\(\"|Hotkey\(", "the pet trainer starts no other threads")

    def test_the_scan_sees_the_threads(self):
        """the scan isn't vacuous: it finds the bot's known threads, each kind"""
        got = {(k, f) for k, _r, _n, f in self.entries}
        for want in [("SetTimer", "GamePriorityTick"), ("SetTimer", "PartyTimer"), ("SetTimer", "NetTick"),
                     ("SetTimer", "GameTrayTick"), ("OnEvent", "DashGLabel"), ("OnEvent", "DashGuiSize"),
                     ("Menu", "MenuExit"), ("Menu", "MenuStats"), ("Menu", "MenuBotToggle"), ("Menu", "MenuDashShow"),
                     ("Menu", "MenuGameShow"), ("OnMessage", "StatsAsked"), ("OnError", "MouseLockOnError"),
                     ("Hotkey", "HkRun"), ("HotkeyLabel", "HK2_"), ("InputHook", "KeyCapEnd"), ("InputHook", "PotionRecKey"),
                     ("OnNotify", "DashLvItem"), ("OnEvent", "SuVerPick"), ("SetTimer", "SuVersionsLoad"),
                     ("OnEvent", "SuInstall")]:
            self.assertIn(want, got)
        self.assertGreater(len(self.entries), 200)
        # (and the chain finder follows calls by name: the timer that broke the round start reaches it through DebugLog)
        self.assertEqual(self.g.reach("GamePriorityTick")[:2], ["GamePriorityTick", "DebugLog"])
        # (a callback calling what it can't name counts: HkRun - every remappable key's action - runs %run%())
        self.assertIn("a call by a variable's name", self.g.entry_reach("HkRun")[-1])

    def test_round_start_takes_passbuttonats_answer(self):
        af = "\n".join(self.files[os.path.join("AutoFarmer", "Autofarmer.ahk")])
        start = af.index("\tstartErr := PassButtonAt(&startX, &startY)\n")
        self.assertNotIn("PassButtonAt(&startX, &startY)\n\t;Kept, since", af)
        # (and that answer is what starts the round - not ErrorLevel read again)
        use = af.index("\tIf (startErr = 0)\n", start)
        # (the search that couldn't run - 2: "&& !PicError" on it before 2026-11-27, inside it since)
        self.assertRegex(af[start:use], r"\n\tif \(startErr = 2(?: && !PicError)?\)\n")
        self.assertNotRegex(af[start:use], r"\bErrorLevel\b")
        self.assertLess(use, af.index('DebugLog("Round start: Pass button at "', start))
        pb = "\n".join(next(d["body"] for d in self.defs["PassButtonAt"] if d["rel"].endswith("Autofarmer.ahk")))
        # (a found Pass always has its position: one without - another thread's ErrorLevel - isn't a Pass found)
        m = re.search(r'if \(pbErr = 0 && \(x = "" \|\| y = ""\)\)\n\t+\{\n(.*?)\n\t+\}\n\tErrorLevel := pbErr\n\treturn pbErr', pb, re.S)
        self.assertIsNotNone(m, "a Pass 'found' without its x, y counts as not found, right before the return")
        self.assertIn("pbErr := 1, PassHover := 0", m.group(1))


if __name__ == "__main__":
    unittest.main()
