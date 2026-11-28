"""test_relog_label.py - Reconnect.ahk tells a relog from a zone change onto another of the game's servers. Standard library
only: python -m unittest test_relog_label  (from AutoFarmer\\vision)

2026-11-22 (JSHSRVRWINB): "Reconnect: in the world after a character select (Zafaria/ZF_Z00_Hub) - a relog" at zone changes
17:22:12, 17:42:13 and 17:42:38 - none a relog. The game's log writes "MSG_CharacterSelected: Error=0, PrepPhase=0" and a
"SERVER TRANSFER" at every zone change onto another of its servers; a real character select has its scene loaded first
("WizardCharacterSelect: The scene has been loaded successfully" - 17:05:30, then PrepPhase=1, PrepPhase=0, SERVER
TRANSFER). Pins: the character's pick counted only with the select's scene up before it - the walker's RcBackAgo (a
relog: a sigil that won't start) and the log line go by it - and the scene's mark cleared after."""
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from test_tray import ahk_code  # noqa: E402  (AutoHotkey lines without their comments)


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def code(src):
    """src's AutoHotkey code (test_tray's ahk_code): comment lines and /* */ blocks gone, each line cut at its ' ;' - a
    pinned line commented out is gone, not still there for assertIn and index"""
    return "".join(ln.rstrip() + "\n" for ln in ahk_code(src.split("\n")) if ln.strip())


class RelogLabel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rc = code(read("..", "Reconnect.ahk"))  # (comments gone: a pinned line commented out fails)

    def test_pick_needs_the_select_scene(self):
        m = re.search(r'\tif \(InStr\(logLine, "MSG_CharacterSelected: Error=0"\)\)\n\t\t\{\n(.*?)\n\t\treturn\n\t\t\}\n', self.rc, re.S)
        self.assertIsNotNone(m)
        body = m.group(1)
        self.assertIn("\t\tif (!RcScanning && RcCharAt)\n\t\t\tRcCharSelAt := A_TickCount\n\t\tRcCharAt := 0\n", body)
        # (cleared after it's looked at - the scene's PrepPhase=1 line first, its PrepPhase=0 one after: the first counts)
        self.assertLess(body.index("RcCharSelAt := A_TickCount"), body.index("RcCharAt := 0"))
        self.assertIn('if (RcOn && RcState = "select")\n\t\t\tRcSet("enter"', body)

    def test_scene_marks_it(self):
        self.assertIn('\tif (InStr(logLine, "WizardCharacterSelect: The scene has been loaded successfully"))\n'
                      '\t\t{\n\t\tRcCharAt := A_TickCount\n\t\treturn\n\t\t}\n', self.rc)

    def test_off_lets_the_scene_through(self):
        # (review: auto-reconnect off reads only a relog's lines - the scene's has to be one, or no relog is ever noticed)
        self.assertIn('\tif (!RcOn && !InStr(logLine, "MSG_CharacterSelected: Error=0") && !InStr(logLine, "ConnectComplete destination Zone=")\n'
                      '\t\t&& !InStr(logLine, "WizardCharacterSelect: The scene has been loaded successfully"))\n\t\treturn\n', self.rc)
        self.assertLess(self.rc.index('&& !InStr(logLine, "WizardCharacterSelect: The scene has been loaded successfully"))'),
                        self.rc.index('\tif (InStr(logLine, "WizardCharacterSelect: The scene has been loaded successfully"))\n'))

    def test_the_game_logs_replayed(self):
        """the lines of 2026-11-22 through Reconnect.ahk's own rule - RcLogLine from its auto-reconnect-off filter on, run
        line by line (run_ahk below), not a copy of it kept here: one relog - the 17:05 select - and three server transfers"""
        lines = [
            "17:05:30 WizardCharacterSelect: The scene has been loaded successfully.",
            "17:06:04 GameClient::MSG_CharacterSelected: Error=0, PrepPhase=1",
            "17:06:05 GameClient::MSG_CharacterSelected: Error=0, PrepPhase=0",
            "17:06:05 GameClient::MSG_CharacterSelected: SERVER TRANSFER: IP: lpcwizardprod09",
            "17:06:07 GameClient::ConnectComplete destination Zone=Zafaria/ZF_Z00_Hub",
            "17:21:45 GameClient::MSG_CharacterSelected: Error=0, PrepPhase=0",
            "17:21:47 GameClient::ConnectComplete destination Zone=Zafaria/ZF_Z00_Hub",
            "17:42:02 GameClient::MSG_CharacterSelected: Error=0, PrepPhase=0",
            "17:42:12 GameClient::ConnectComplete destination Zone=Zafaria/ZF_Z00_Hub",
            "17:42:35 GameClient::MSG_CharacterSelected: Error=0, PrepPhase=0",
            "17:42:36 GameClient::ConnectComplete destination Zone=Zafaria/ZF_Z03_Savannah",
        ]
        for rc_on in (1, 0):
            self.assertEqual(self.replay(lines, rc_on), ["17:06:07"], rc_on)
        # (the start's replay of the log - RcScanning - is never a relog)
        self.assertEqual(self.replay(lines, 1, scanning=1), [])
        if "RcOffRead" in self.log_line():
            # (the bot off - F6 - its log read quietly meanwhile, ReconnectOff: a relog then counted all the same)
            self.assertEqual(self.replay(lines, 1, scanning=1, off_read=1), ["17:06:07"])
        # (a pick more than 2 minutes before the world: not taken for that relog)
        late = [lines[0], lines[1], "17:08:05 GameClient::ConnectComplete destination Zone=Zafaria/ZF_Z00_Hub"]
        self.assertEqual(self.replay(late, 0), [])
        # (the pick's mark gone once in the world: a server transfer a minute after the relog isn't another)
        soon = lines[:5] + ["17:06:50 GameClient::MSG_CharacterSelected: Error=0, PrepPhase=0",
                            "17:07:01 GameClient::ConnectComplete destination Zone=Zafaria/ZF_Z01_Baobab"]
        self.assertEqual(self.replay(soon, 1), ["17:06:07"])
        # (and nowhere else in Reconnect.ahk is the pick or the relog's time set - only in RcLogLine, run above)
        for set_it in ("RcCharSelAt := A_TickCount", "RcBackAt := A_TickCount"):
            self.assertGreater(self.log_line().count(set_it), 0, set_it)
            self.assertEqual(self.rc.count(set_it), self.log_line().count(set_it), set_it)

    def log_line(self):
        """RcLogLine's body (comments gone)"""
        return re.search(r"(?ms)^RcLogLine\(logLine\)\n\t\{\n(.*?)^\t\}\n", self.rc).group(1)

    def replay(self, lines, rc_on, scanning=0, off_read=0):
        """the relogs (each line's time where RcBackAt was set) RcLogLine finds in lines - the bot itself not reconnecting
        (RcState blank), auto-reconnect on or off"""
        body = self.log_line().split("\n")
        # (a condition's && / || lines joined to its first)
        merged = []
        for ln in body:
            if merged and re.match(r"\t+(?:&&|\|\|) ", ln):
                merged[-1] += " " + ln.strip()
            else:
                merged.append(ln)
        start = next(k for k, ln in enumerate(merged) if ln.startswith("\tif (!RcOn && "))
        tail = [ln for ln in merged[start:] if ln.strip()]
        env = {"RcOn": rc_on, "RcState": "", "RcScanning": scanning, "RcOffRead": off_read, "RcCharAt": 0, "RcCharSelAt": 0, "RcBackAt": 0}
        relogs = []
        for line in lines:
            h, m, sec = (int(x) for x in line[:8].split(":"))
            env["A_TickCount"], env["logLine"] = ((h * 60 + m) * 60 + sec) * 1000, line
            was = env["RcBackAt"]
            run_ahk(tail, env)
            if env["RcBackAt"] != was:
                relogs.append(line[:8])
        return relogs


def ahk_eval(e, env):
    """one of RcLogLine's plain AutoHotkey expressions as Python: InStr(logLine, "..."), !, &&, ||, =, numbers, "" (a name
    or a call it doesn't know fails - the test with it)"""
    out = []
    for k, part in enumerate(re.split(r'("[^"]*")', e)):    # (the quoted strings - odd k - as they are)
        if k % 2 == 0:
            part = re.sub(r"(?<![!:<>=])=(?!=)", "==", part)
            part = re.sub(r"!(?!=)", " not ", part.replace("&&", " and ").replace("||", " or "))
        out.append(part)
    e = re.sub(r'InStr\(logLine, ("[^"]*")\)', r"(\1 in logLine)", "".join(out))
    return eval(e, {"__builtins__": {}}, env)


def ahk_body(lines, k):
    """an if's / else's body starting at lines[k] - a { } block, else the one line and any more indented under it (an if
    in it) - and where the code after it starts"""
    if lines[k].strip() == "{":
        close = lines[k].replace("{", "}")
        end = next(n for n in range(k + 1, len(lines)) if lines[n] == close)
        return lines[k + 1:end], end + 1
    tabs = len(lines[k]) - len(lines[k].lstrip("\t"))
    end = k + 1
    while end < len(lines) and len(lines[end]) - len(lines[end].lstrip("\t")) > tabs:
        end += 1
    return lines[k:end], end


def run_ahk(lines, env):
    """runs AutoHotkey code lines (comments gone) the way RcLogLine is written - if (...) / else if (...) / else with a
    one-line or a { } body, name := value (comma lists too), return; other calls (RcSet, RcLogMsg, RegExMatch,
    TrayTip...) left out. "return" if it returned"""
    k = 0
    while k < len(lines):
        s = lines[k].strip()
        m = re.fullmatch(r"if \((.*)\)", s)
        if m:
            chain, cond = [], m.group(1)
            while True:
                block, k = ahk_body(lines, k + 1)
                chain.append((cond, block))
                nxt = lines[k].strip() if k < len(lines) else ""
                em = re.fullmatch(r"else if \((.*)\)", nxt)
                if em:
                    cond = em.group(1)
                    continue
                if nxt == "else":
                    block, k = ahk_body(lines, k + 1)
                    chain.append((None, block))
                elif nxt.startswith("else "):
                    chain.append((None, [nxt[5:]]))
                    k += 1
                break
            for cond, block in chain:
                if cond is None or ahk_eval(cond, env):
                    if run_ahk(block, env) == "return":
                        return "return"
                    break
            continue
        if s == "return":
            return "return"
        if re.match(r"\w+ := ", s):
            for part in re.split(r", (?=\w+ := )", s):
                name, value = part.split(" := ", 1)
                try:
                    env[name] = ahk_eval(value, env)
                except (NameError, SyntaxError, TypeError):
                    # (a value the model can't work out - only for what the rule doesn't read)
                    assert name not in ("RcCharAt", "RcCharSelAt", "RcBackAt", "RcState"), part
        k += 1


if __name__ == "__main__":
    unittest.main()
