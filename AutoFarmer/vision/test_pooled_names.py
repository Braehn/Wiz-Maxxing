"""test_pooled_names.py - a reflected class whose name the game's code loads from a copy right after other bytes, not a
NUL (handmem.strings loose, find_types; questmem.get_types). Build 6AFBB954-37B4000 (2026-11-20): the only copy of
"CombatPlanningPhaseWindow" its GetType loads came right after "(@" (two bytes of a constant), the NUL-led copy was
loaded by nothing - "reflected classes not found in this build" - and the hand, the backpack, the decks and the GUI root
went unread from the game's patch on. On a made-up game image (test_reflect's):
    python -m unittest test_pooled_names   (from AutoFarmer\\vision)"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_reflect import BASE, D0, R0, T0, Image, _stub_navmem  # noqa: E402

POOLED_AT = 0x1000        # .rdata offset of the "(@" + name copy (the fixture's own strings start at 0x10)


def pooled_game():
    """WizThing as test_reflect makes it (its name NUL-led), and PooledWindow: a NUL-led copy of its name that nothing
    loads, and the copy its GetType loads right after "(@"; its vtable's slot 0 is that GetType"""
    im = Image()
    im.klass("WizThing", 0x100, 0x180, [("m_alpha", 0x58, "int")])
    im.string("PooledWindow")                                     # (the NUL-led copy - loaded by nothing)
    blob = b"(@PooledWindow\0"
    im.rdata[POOLED_AT:POOLED_AT + len(blob)] = blob
    at = R0 + POOLED_AT + 2
    gt = 0x400
    code = im.rip(gt, b"\x48\x8D\x0D", at)                      # lea rcx, "PooledWindow" (the copy after "(@")
    code += im.rip(gt + 7, b"\x48\x89\x05", D0 + 0x200)        # mov [rip+static], rax
    im.put(gt, code + b"\xC3")
    struct.pack_into("<Q", im.rdata, im.vt, T0 + gt)
    im.vt += 0x20
    return im, at


class PooledNames(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _stub_navmem()
        import handmem as H
        import questmem as Q
        cls.H, cls.Q = H, Q
        cls.im, cls.at = pooled_game()
        cls.img = H.Image(cls.im.st())

    def test_strings(self):
        """strict: the NUL-led copies only; loose: only the ones that aren't - each one's own start"""
        self.assertEqual(self.img.strings("PooledWindow"), [self.im.strs["PooledWindow"]])
        self.assertEqual(self.img.strings("PooledWindow", loose=True), [self.at])
        self.assertEqual(self.img.strings("WizThing", loose=True), [])
        # (a tail of a longer string is a copy after other bytes too - the C string there is still the name)
        self.assertEqual(self.img.strings("Window", loose=True), sorted([self.at + 6, self.im.strs["PooledWindow"] + 6]))

    def test_find_types(self):
        """the GetType that loads the copy after "(@": found, its static and vtable with it - by Image.get_types,
        handmem.class_props and questmem.get_types alike"""
        H = self.H
        r = self.img.get_types("PooledWindow")
        self.assertEqual(r, [(T0 + 0x400, D0 + 0x200, [R0 + 0x1820])])
        self.assertEqual(H.find_types(self.img, "PooledWindow"), r)
        self.assertEqual(self.Q.get_types(self.img, "PooledWindow"), r)
        props, gt, vts = H.class_props(self.img, "PooledWindow")
        self.assertEqual((gt, vts), (T0 + 0x400, [R0 + 0x1820]))

    def test_nul_led_first(self):
        """a class found through its NUL-led name never looks further (the copies after other bytes aren't asked for)"""
        H = self.H
        asked = []
        orig = self.img.strings

        def spy(s, loose=False):
            asked.append((s, loose))
            return orig(s, loose)
        self.img.strings = spy
        try:
            r = H.find_types(self.img, "WizThing")
        finally:
            del self.img.strings
        self.assertEqual(r, [(T0 + 0x100, D0 + 0x100 + 0x100 // 8, [R0 + 0x1800])])
        self.assertEqual(asked, [("WizThing", False)])

    def test_missing(self):
        """a name that isn't there: nothing, no error"""
        self.assertEqual(self.img.get_types("NoSuchWindow"), [])
        self.assertEqual(self.H.class_props(self.img, "NoSuchWindow"), ({}, None, []))


if __name__ == "__main__":
    unittest.main()
