"""test_potion_count.py - the potions the wizard has in the helper's /bag answer (bagmem: WizGameStats.m_potionCharge /
m_potionMax read as floats - potion_count, fmt_count, bag_lines' potions| line) - no game, no Windows:
python -m unittest test_potion_count   (from AutoFarmer\vision)"""
import os
import struct
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_bagmem import World, reader  # noqa: E402
import bagmem as B  # noqa: E402


class Count(unittest.TestCase):
    def test_potion_count(self):
        self.assertEqual(B.potion_count(3.0), 3.0)
        self.assertEqual(B.potion_count(0.0), 0.0)
        self.assertIsNone(B.potion_count(None))
        self.assertIsNone(B.potion_count(float("nan")))
        self.assertIsNone(B.potion_count(-1.0))
        self.assertIsNone(B.potion_count(1e9))

    def test_fmt_count(self):
        self.assertEqual(B.fmt_count(3.0), "3")
        self.assertEqual(B.fmt_count(1.5), "1.5")
        self.assertEqual(B.fmt_count(0.0), "0")
        self.assertEqual(B.fmt_count(None), "")
        # (never rounded up to a whole potion that isn't there; a float's hair under one taken as it)
        self.assertEqual(B.fmt_count(0.996), "0.99")
        self.assertEqual(B.fmt_count(1.999), "1.99")
        self.assertEqual(B.fmt_count(2.9999999), "3")
        self.assertEqual(B.fmt_count(0.3), "0.3")

    def test_bag_lines(self):
        r = {"items": 10, "allowed": 150, "extra": 0, "gold": 147072, "gold_max": 200000, "player_gid": 0x1234,
             "walked": 5, "emotes": 0, "sets_ok": True, "potions": 3.0, "potions_max": 3.0, "root": (1827, 1027)}
        ln = B.bag_lines(r)
        self.assertIn("potions|3|3", ln)
        self.assertEqual(ln[-1], "potions|3|3")
        r["potions"], r["potions_max"] = 1.5, None
        self.assertEqual(B.bag_lines(r)[-1], "potions|1.5|")
        r["potions"] = None
        self.assertFalse(any(x.startswith("potions|") for x in B.bag_lines(r)))

    def test_f32(self):
        wd = World()
        bm = reader(wd)
        a = wd.p.alloc(0x100)
        wd.p.write(a + 0xAC, struct.pack("<f", 3.0))
        self.assertEqual(bm.f32(a + 0xAC), 3.0)
        self.assertIsNone(bm.f32(0))

    def test_optional_listed(self):
        self.assertIn("m_potionCharge", B.OPTIONAL["WizGameStats"])
        self.assertIn("m_potionMax", B.OPTIONAL["WizGameStats"])
        # (a build without them: listed as lacking, nothing raised)
        bm = reader(World())
        self.assertIn("WizGameStats.m_potionCharge", bm.lack)


if __name__ == "__main__":
    unittest.main()
