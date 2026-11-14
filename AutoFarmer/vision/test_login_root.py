"""test_login_root.py - the game's login box from its memory: handmem.HandMem.login_root (the GUI's root at the login box,
where root() has none - no windowHUD) and bagmem's gui / tree asking for it only for a LoginWindow path, never reading
what's typed in the fields - on made-up memory, no game, no Windows:  python -m unittest test_login_root   (from
AutoFarmer\\vision)"""
import os
import struct
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_handmem_boxes import import_handmem  # noqa: E402
from test_bagmem import World, reader, PROPS  # noqa: E402
import bagmem as B  # noqa: E402

H = import_handmem()


def login_world():
    """the login screen as read 2026-11-13 (the root 1827x1027, WorldView): BallonLayer, WizardPatchingWindow (hidden) and
    LoginWindow (GameLoginWindow) -> loginName / loginPassword (ControlEdit - something typed in both), accountText,
    passwordText, okButton, cancelButton. (world, hm, {name: address}); hm.root() 0 - no windowHUD - and hm.login_root()
    the root, counted"""
    wd, a = World(), {}
    a["name"] = wd.window("loginName", "ControlEdit", rect=(20, 84, 240, 103))
    a["pw"] = wd.window("loginPassword", "ControlEdit", rect=(19, 129, 239, 148))
    # (what's typed: put where a ControlText keeps its words - it must never come back)
    wd.p.put_wstring(a["name"] + PROPS["ControlText"]["m_sText"], "someuser")
    wd.p.put_wstring(a["pw"] + PROPS["ControlText"]["m_sText"], "secret")
    a["acct"] = wd.window("accountText", "ControlText", rect=(20, 67, 205, 85), text="Account:")
    a["pwt"] = wd.window("passwordText", "ControlText", rect=(19, 113, 105, 131), text="Password:")
    a["ok"] = wd.window("okButton", "ControlButton", rect=(23, 156, 122, 180), label="OK", greyed=False)
    a["cancel"] = wd.window("cancelButton", "ControlButton", rect=(138, 155, 237, 180), label="CANCEL", greyed=False)
    a["login"] = wd.window("LoginWindow", "GameLoginWindow", rect=(784, 415, 1044, 613),
                           kids=[a["acct"], a["name"], a["pwt"], a["pw"], a["ok"], a["cancel"]])
    a["patch"] = wd.window("WizardPatchingWindow", shown=False, rect=(0, 0, 127, 127))
    a["ballon"] = wd.window("BallonLayer", rect=(0, 0, 1827, 1027))
    a["root"] = wd.window("WorldView", rect=(0, 0, 1827, 1027), kids=[a["ballon"], a["patch"], a["login"]])
    calls = {"login_root": 0, "scan": []}
    found = {"root": a["root"]}

    def login_root(scan=True):
        calls["login_root"] += 1
        calls["scan"].append(scan)
        return found["root"]
    hm = types.SimpleNamespace(root=lambda: 0, login_root=login_root, lang_text=lambda k: None, st=wd, calls=calls,
                               found=found)
    return wd, hm, a


class Gui(unittest.TestCase):
    def setUp(self):
        self.wd, self.hm, self.a = login_world()
        self.bm = reader(self.wd)

    def test_the_fields_found_from_the_login_root(self):
        g, why = self.bm.gui(self.hm, ["LoginWindow/loginName", "LoginWindow/loginPassword", "LoginWindow/okButton"])
        self.assertEqual(why, "")
        w = g["wins"]
        self.assertEqual(g["root"], (1827, 1027))
        self.assertEqual(w["LoginWindow/loginName"]["rect"], (804, 499, 1024, 518))
        self.assertEqual(w["LoginWindow/loginName"]["type"], "ControlEdit")
        self.assertTrue(w["LoginWindow/loginName"]["shown"])
        self.assertEqual(w["LoginWindow/loginPassword"]["rect"], (803, 544, 1023, 563))
        self.assertEqual(w["LoginWindow/okButton"]["raw"], "OK")
        self.assertIsNone(g["box"])
        self.assertEqual(self.hm.calls["login_root"], 1)

    def test_whats_typed_never_read(self):
        g, _ = self.bm.gui(self.hm, ["LoginWindow/loginName", "LoginWindow/loginPassword"])
        self.assertIsNone(g["wins"]["LoginWindow/loginName"]["raw"])
        self.assertIsNone(g["wins"]["LoginWindow/loginPassword"]["raw"])
        lines = B.gui_lines(B.finish_gui(g, self.hm.lang_text), "", ["LoginWindow/loginName", "LoginWindow/loginPassword"])
        self.assertFalse(any("secret" in ln or "someuser" in ln for ln in lines), lines)
        t, _ = self.bm.tree(self.hm, "LoginWindow", shown_only=False)
        self.assertFalse(any(r["raw"] in ("secret", "someuser") for r in t["rows"]))
        self.assertEqual({r["name"]: r["raw"] for r in t["rows"]}["accountText"], "Account:")

    def test_not_asked_for_other_windows(self):
        self.assertEqual(self.bm.gui(self.hm, ["windowHUD/GoHomeButton"]), (None, "no GUI root (not in the game world)"))
        self.assertEqual(self.bm.tree(self.hm), (None, "no GUI root (not in the game world)"))
        self.assertEqual(self.bm.tree(self.hm, "windowHUD"), (None, "no GUI root (not in the game world)"))
        # ("LoginWindowX" or a name only containing it: not the login box)
        self.assertIsNone(self.bm.gui(self.hm, ["LoginWindowX/loginName"])[0])
        self.assertEqual(self.hm.calls["login_root"], 0)

    def test_in_the_world_root_used(self):
        # (root() has one - the world's - and there's no login root: a LoginWindow path just not found there, the login
        # root looked for at its usual places only - no scan)
        world_root = self.wd.window("", rect=(0, 0, 1827, 1027), kids=[self.wd.window("windowHUD")])
        self.hm.root = lambda: world_root
        self.hm.found["root"] = 0
        g, why = self.bm.gui(self.hm, ["LoginWindow/loginName"])
        self.assertEqual(why, "")
        self.assertIsNone(g["wins"]["LoginWindow/loginName"])
        self.assertEqual(self.hm.calls["scan"], [False])
        # (other windows: the login root never asked for)
        self.bm.gui(self.hm, ["windowHUD"])
        self.assertEqual(self.hm.calls["login_root"], 1)

    def test_login_root_first_with_a_hud_still_held(self):
        # (after a disconnect the GUI manager may still hold a windowHUD - root() gives the old root: the login screen's
        # found all the same)
        stale = self.wd.window("", rect=(0, 0, 1827, 1027), kids=[self.wd.window("windowHUD")])
        self.hm.root = lambda: stale
        g, why = self.bm.gui(self.hm, ["LoginWindow/loginName"])
        self.assertEqual(g["wins"]["LoginWindow/loginName"]["rect"], (804, 499, 1024, 518))
        self.assertEqual(self.hm.calls["scan"], [False])
        t, _ = self.bm.tree(self.hm, "LoginWindow")
        self.assertEqual(t["rows"][0]["name"], "LoginWindow")

    def test_scanned_for_without_a_world_root(self):
        self.bm.gui(self.hm, ["LoginWindow/loginName"])
        self.assertEqual(self.hm.calls["scan"], [True])

    def test_tree_under_the_login_box(self):
        t, why = self.bm.tree(self.hm, "LoginWindow")
        self.assertEqual(why, "")
        self.assertEqual([r["name"] for r in t["rows"]],
                         ["LoginWindow", "accountText", "loginName", "passwordText", "loginPassword", "okButton",
                          "cancelButton"])

    def test_no_login_root_either(self):
        self.hm.login_root = lambda scan=True: 0
        self.assertEqual(self.bm.gui(self.hm, ["LoginWindow/loginName"]), (None, "no GUI root (not in the game world)"))
        # (an older hand reader without login_root: as before)
        del self.hm.login_root
        self.assertEqual(self.bm.gui(self.hm, ["LoginWindow/loginName"]), (None, "no GUI root (not in the game world)"))


class FakeMem:
    """u64s and windows (name, kids) at made-up addresses - what HandMem.login_root reads"""

    def __init__(self):
        self.q, self.names, self.kidsof = {}, {}, {}
        self.next = 0x20000000

    def new(self, name, kids=()):
        a = self.next
        self.next += 0x1000
        self.names[a], self.kidsof[a] = name, list(kids)
        return a


class LoginRoot(unittest.TestCase):
    BASE, RVA_A, RVA_B = 0x140000000, 0x37634C0, 0x3762040

    def setUp(self):
        self.keep = dict(H.N.KNOWN)
        H.N.KNOWN.setdefault("guimgr_rva", 0x3322460)
        H.N.KNOWN.setdefault("gm_hud", 0x2D0)
        self.m = FakeMem()
        m = self.m
        self.login = m.new("LoginWindow")
        self.root = m.new("WorldView", [m.new("BallonLayer"), m.new("WizardPatchingWindow"), self.login])
        self.gm = 0x30000000
        st = types.SimpleNamespace(o={"gm_candidates": [(self.RVA_B, 0x21378), (self.RVA_A, 0x2D0)]},
                                   m=types.SimpleNamespace(base=self.BASE))
        self.me = types.SimpleNamespace(st=st, o={}, u64=lambda a: m.q.get(a, 0),
                                        kids=lambda w: m.kidsof.get(w, []), wname=lambda w: m.names.get(w))

    def tearDown(self):
        H.N.KNOWN.clear()
        H.N.KNOWN.update(self.keep)

    def find(self):
        return H.HandMem.login_root(self.me)

    def test_found_at_the_usual_place(self):
        # (the second candidate manager holds it at 0x118 - root()'s place; the first manager's pointer isn't one)
        self.m.q[self.BASE + self.RVA_A] = self.gm
        self.m.q[self.gm + H.KNOWN["root_in_gm"]] = self.root
        self.assertEqual(self.find(), self.root)
        self.assertEqual(self.me.o["login_gm"], self.RVA_A)

    def test_found_elsewhere_in_the_manager(self):
        self.m.q[self.BASE + self.RVA_A] = self.gm
        self.m.q[self.gm + 0x40] = self.root
        self.assertEqual(self.find(), self.root)
        # (not looked for there without scan - root() has a root then: its usual places only)
        self.me.o.clear()
        self.assertEqual(H.HandMem.login_root(self.me, scan=False), 0)

    def test_a_root_without_the_login_box_isnt_it(self):
        world = self.m.new("", [self.m.new("windowHUD")])
        self.m.q[self.BASE + self.RVA_A] = self.gm
        self.m.q[self.gm + H.KNOWN["root_in_gm"]] = world
        self.assertEqual(self.find(), 0)
        self.assertNotIn("login_gm", self.me.o)

    def test_nothing_readable(self):
        self.assertEqual(self.find(), 0)


if __name__ == "__main__":
    unittest.main()
