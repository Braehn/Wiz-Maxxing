"""test_placements.py - a zone file's placements read (vision\\placements.py parse_placements, tid_at) from made-up
gamedata.bin bytes in both layouts: the template id 28 bytes before the location (the files before the 2026-11-12 patch)
and 44 (after it: a new u64 property, fe d9 63 5f, in between - every zone read 0 placements, so the potion runs found no
seller in the Commons). No game needed (navmem's Windows DLLs stood in for where there are none, as test_navroute.py does):
    python -m unittest test_placements   (from AutoFarmer\\vision)"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_navroute import import_navmem  # noqa: E402

import_navmem()
import placements as P  # noqa: E402


def prop(h, payload):
    """an ObjectProperty: its size in bits (size, hash and value), its hash, its value"""
    return struct.pack("<I", (8 + len(payload)) * 8) + h + payload


def text(h, s):
    """a u16-length string property"""
    b = s.encode("utf-8")
    return prop(h, struct.pack("<H", len(b)) + b)


def record(tid, pos, name, state="", yaw=1.5, new=True):
    """one placement's properties in the file's order - new: the 2026-11-12 layout (fe d9 63 5f between the template
    id and the location)"""
    out = prop(P.H_TID, struct.pack("<Q", tid))
    if new:
        out += prop(bytes.fromhex("fed9635f"), struct.pack("<Q", 0))
    out += prop(bytes.fromhex("1f289d2c"), struct.pack("<I", 114611))
    out += prop(P.H_LOC, struct.pack("<3f", *pos))
    out += prop(P.H_ORI, struct.pack("<3f", 0.0, 0.0, yaw))
    out += prop(P.H_SCALE, struct.pack("<f", 1.0))
    out += text(P.H_NAME, name)
    out += text(P.H_STATE, state)
    return out


class Layouts(unittest.TestCase):
    def check(self, new):
        b = (b"\x00" * 16 + record(4336, (-4427.5, 1009.9, 229.0), "WC_PotionShopkeeper instance", "Idle", new=new)
             + record(77, (10.0, -20.0, 3.0), "WC_MiniGameKiosk instance (1)", new=new))
        rows = P.parse_placements(b)
        self.assertEqual([r["name"] for r in rows], ["WC_PotionShopkeeper instance", "WC_MiniGameKiosk instance (1)"])
        self.assertEqual([r["tid"] for r in rows], [4336, 77])
        self.assertEqual(rows[0]["state"], "Idle")
        self.assertAlmostEqual(rows[0]["pos"][0], -4427.5, places=2)
        self.assertAlmostEqual(rows[0]["yaw"], 1.5, places=5)
        self.assertEqual(rows[1]["pos"], (10.0, -20.0, 3.0))

    def test_after_the_patch(self):
        self.check(True)

    def test_before_the_patch(self):
        self.check(False)

    def test_tid_at(self):
        old, new = record(5, (1.0, 2.0, 3.0), "A", new=False), record(5, (1.0, 2.0, 3.0), "A")
        self.assertEqual(old.find(P.H_LOC) - P.tid_at(old, old.find(P.H_LOC)), 28)
        self.assertEqual(new.find(P.H_LOC) - P.tid_at(new, new.find(P.H_LOC)), 44)

    def test_no_template_id(self):
        # (a location with no template id before it - or its hash without a u64 property's size: not a placement)
        b = record(5, (1.0, 2.0, 3.0), "A")
        k = b.find(P.H_TID)
        self.assertEqual(P.parse_placements(b[k + 12:]), [])
        bad = b[:k - 4] + struct.pack("<I", 96) + b[k:]
        self.assertEqual(P.parse_placements(bad), [])

    def test_too_far_back(self):
        # (more than TID_BACK's reach between the id and the location: not read - never the record before's id)
        b = record(5, (1.0, 2.0, 3.0), "A")
        k = b.find(P.H_LOC)
        pad = b"".join(prop(bytes.fromhex("01020304"), struct.pack("<Q", 0)) for _ in range(4))
        self.assertEqual(P.parse_placements(b[:k - 4] + pad + b[k - 4:]), [])


if __name__ == "__main__":
    unittest.main()
