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
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


class RelogLabel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rc = read("..", "Reconnect.ahk")

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

    def test_the_game_logs_replayed(self):
        # (the lines of 2026-11-22 through the same rule: one relog - the 17:05 select - and three server transfers)
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
        char_at, sel_at, relogs = 0, 0, []
        for k, line in enumerate(lines, 1):
            if "WizardCharacterSelect: The scene has been loaded successfully" in line:
                char_at = k
            elif "MSG_CharacterSelected: Error=0" in line:
                if char_at:
                    sel_at = k
                char_at = 0
            elif "ConnectComplete destination Zone=" in line:
                if sel_at:
                    relogs.append(line[:8])
                sel_at = 0
        self.assertEqual(relogs, ["17:06:07"])


if __name__ == "__main__":
    unittest.main()
