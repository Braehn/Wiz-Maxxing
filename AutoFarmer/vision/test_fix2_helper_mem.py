"""test_fix2_helper_mem.py - the game-memory readers' fixes from the 2026-11-27 review (the helper's mem group): the deck
signature (worn items, exclusions, pet level), a GetType's name loaded far in, names right after other bytes (enum
options, reflect.py), the template map looked for again, a provisional participant dropped, SpellRank's range, a pet's
level list cut short, the readers built on the hand's retried when it is, the position alone lost without GETLOCATION,
the readers' broken() list, the mob names read again after a patch, an unread template said as that, one image shared:
    python -m unittest test_fix2_helper_mem   (from AutoFarmer\\vision)"""
import os
import struct
import sys
import tempfile
import time
import types
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_handmem_boxes import H  # noqa: E402
from test_reflect import D0, R0, T0, Image, _stub_navmem  # noqa: E402
import reflect as R  # noqa: E402


def src(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


# ============================================================================ handmem: GetType far in, names, the map
def far_game():
    """FarWindow: a GetType whose name LEA is 0x90 bytes in (a longer prologue); NearWindow: one at +0"""
    im = Image()
    im.klass("NearWindow", 0x100, 0x180, [("m_alpha", 0x58, "int")])
    gt = 0x1000
    code = b"\x90" * 0x90
    code += im.rip(gt + 0x90, b"\x48\x8D\x0D", im.string("FarWindow"))
    code += im.rip(gt + 0x97, b"\x48\x89\x05", D0 + 0x300)
    im.put(gt, code + b"\xC3")
    struct.pack_into("<Q", im.rdata, im.vt, T0 + gt)
    im.vt += 0x20
    return im


class FarGetType(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _stub_navmem()
        cls.im = far_game()
        cls.img = H.Image(cls.im.st())

    def test_far_name_found_within_the_wider_limit(self):
        self.assertEqual(H.types_at(self.img, self.img.strings("FarWindow"), 0x80), [])
        r = H.find_types(self.img, "FarWindow")
        self.assertEqual([(fn, st) for fn, st, _v in r], [(T0 + 0x1000, D0 + 0x300)])
        self.assertTrue(r[0][2])
        self.assertEqual(self.img.get_types("FarWindow"), r)

    def test_near_name_as_before(self):
        r = H.find_types(self.img, "NearWindow")
        self.assertEqual(r, H.types_at(self.img, self.img.strings("NearWindow"), 0x80))
        self.assertEqual(self.img.get_types("NoSuchWindow"), [])

    def test_questmem_leaves_the_image_alone(self):
        import questmem as Q
        Q.class_props(self.img, "NearWindow")
        self.assertNotIn("get_types", vars(self.img))     # (a shared image: never patched while others read it)

    def test_shared_image(self):
        st = self.im.st()
        a = H.shared_image(st)
        self.assertIs(H.shared_image(st), a)              # (held by a reader being made: the same one)
        aid = id(a)
        del a
        b = H.shared_image(st)                            # (dropped with the last: read anew)
        self.assertIsInstance(b, H.Image)
        self.assertIsNot(H.shared_image(self.im.st()), b)  # (another game: its own)
        del b, aid


class NameStarts(unittest.TestCase):
    def test_name_starts(self):
        buf = b"\x00kDamage\x00(@kHeal\x00xkTail\x00"
        self.assertTrue(H.name_starts(buf, 1))
        self.assertTrue(H.name_starts(buf, buf.index(b"kHeal")))          # (after a constant's bytes)
        self.assertFalse(H.name_starts(buf, buf.index(b"kTail")))         # (inside a longer name)
        self.assertFalse(H.name_starts(buf, 0))

    def test_loose_property_names_and_options(self):
        s = src("handmem.py")
        self.assertIn('addrs = img.strings(prop) + img.strings(prop, loose=True)', s)
        self.assertNotIn("rdata[tg - r0 - 1] != 0", s)
        self.assertNotIn("rdata[tg - r0 - 1] == 0", s)
        self.assertIn("set(img.strings(prop, loose=True))", src("bossmem.py"))
        self.assertIn('img.strings("m_madlibArgument", loose=True)', src("questmem.py"))


class FakeMem:
    """u64 / u8 / u32 over {address: bytes}"""

    def __init__(self):
        self.mem = {}

    def put(self, a, b):
        self.mem[a] = bytes(b)

    def read(self, a, n):
        for base, b in self.mem.items():
            if base <= a and a + n <= base + len(b):
                return b[a - base:a - base + n]
        return None


class TemplateMapLater(unittest.TestCase):
    def test_found_later(self):
        fm = FakeMem()
        hm = object.__new__(H.HandMem)
        hm.st = types.SimpleNamespace(m=types.SimpleNamespace(base=0x140000000))
        hm.p = types.SimpleNamespace(try_read=fm.read)
        hm.tm, hm.how, hm._next_scan, said = 0, {}, {}, []
        hm.log = said.append
        static, obj, head = 0x140100000, 0x20000000, 0x21000000
        hm._tm_cands, hm._tm_first, hm._tm_at = [(static, 0x30)], 1, 0
        fm.put(static, struct.pack("<Q", obj))
        fm.put(obj, bytes(0x30) + struct.pack("<QQ", head, 5))         # (a map, not filled yet)
        hm._lookup = lambda h, tid: 0x22000000 if h == head else 0
        hm.tname = lambda o: None
        isnil = bytearray(0x20)
        isnil[8:16] = struct.pack("<Q", head)
        isnil[0x19] = 1
        fm.put(head, bytes(isnil))
        self.assertEqual(hm.template_head(), 0)
        fm.put(obj, bytes(0x30) + struct.pack("<QQ", head, 22000))     # (filled)
        self.assertEqual(hm.template_head(), 0)                        # (not looked at again yet: RESCAN_EVERY)
        hm._next_scan.clear()
        self.assertEqual(hm.template_head(), head)
        self.assertEqual(hm.tm, head)
        self.assertIn("found later", hm.how["template_map"])
        self.assertTrue(any("template map found later" in m for m in said))
        self.assertEqual(hm.template(7), 0x22000000 if hm._lookup(head, 7) else 0)

    def test_every_small_map_kept_and_looked_at_in_turn(self):
        # (a moved static far down .data, past TM_CANDS empty maps of other singletons: still reached)
        fm = FakeMem()
        hm = object.__new__(H.HandMem)
        hm.st = types.SimpleNamespace(m=types.SimpleNamespace(base=0x140000000))
        hm.p = types.SimpleNamespace(try_read=fm.read)
        hm.tm, hm.how, hm._next_scan, said = 0, {}, {}, []
        hm.log = said.append
        head = 0x21000000
        isnil = bytearray(0x20)
        isnil[8:16] = struct.pack("<Q", head)
        isnil[0x19] = 1
        fm.put(head, bytes(isnil))
        n = H.TM_CANDS * 3
        others = [(0x140200000 + 8 * i, 0x30) for i in range(n)]
        real = (0x140300000, 0x30)
        obj = 0x20000000
        fm.put(real[0], struct.pack("<Q", obj))
        fm.put(obj, bytes(0x30) + struct.pack("<QQ", head, 22000))
        hm._tm_cands, hm._tm_first, hm._tm_at = [(0x140000000 + H.KNOWN["tm_rva"], 0x30)] + others + [real], 1, 0
        hm._lookup = lambda h, tid: 0x22000000 if h == head else 0
        looks = 0
        while not hm.template_head() and looks < 10:
            hm._next_scan.clear()
            looks += 1
        self.assertEqual(hm.tm, head)
        self.assertEqual(looks, 3)                                     # (the 4th look reaches the last batch)

    def test_no_cap_and_named_first(self):
        s = src("handmem.py")
        self.assertNotIn("if len(self._tm_cands) > TM_CANDS:", s)
        self.assertIn('(first if "Template" in (self.tname(obj) or "") else rest).extend(got)', s)


class ProvisionalParticipant(unittest.TestCase):
    def test_dropped_and_passed_over(self):
        fm = FakeMem()
        hm = object.__new__(H.HandMem)
        hm.build, hm.o, hm._next_scan, said = "OTHER-1", {}, {}, []
        hm._prov, hm._prov_miss, hm._prov_bad = {}, {}, {}
        hm.log = said.append
        hm.p = types.SimpleNamespace(try_read=fm.read)
        win, wrong, right = 0x20000000, 0x21000000, 0x22000000
        raw = bytearray(0x800)
        struct.pack_into("<Q", raw, 0x2F0, wrong)
        struct.pack_into("<Q", raw, 0x360, right)
        fm.put(win, bytes(raw))
        fm.put(wrong, struct.pack("<Q", 0x7FF600000100))
        fm.put(right, struct.pack("<Q", 0x7FF600000100))
        vts = {0x7FF600000100}
        self.assertEqual(hm._typed_in("ss_participant", win, vts), (wrong, 0x2F0))
        for _ in range(H.PROV_MISSES - 1):
            hm._prov_missed("ss_participant", 0x2F0)
        self.assertEqual(hm._prov.get("ss_participant"), 0x2F0)
        hm._prov_missed("ss_participant", 0x2F0)
        self.assertNotIn("ss_participant", hm._prov)
        self.assertTrue(any("dropped" in m for m in said))
        hm._next_scan.clear()
        self.assertEqual(hm._typed_in("ss_participant", win, vts), (right, 0x360))

    def test_counted_from_the_hand_check(self):
        s = src("handmem.py")
        self.assertIn('self._prov_missed("ss_participant", c_at)', s)
        # (a miss only when the cards shown read whole: a card's spell or name not read says nothing of the participant)
        i = s.index('self._prov_missed("ss_participant", c_at)')
        self.assertIn('0 not in gs and None not in gs', s[i - 400:i])
        self.assertIn('all(cd.get("name") for cd in shown)', s[i - 400:i])
        self.assertIn('self._prov_miss.pop(("ss_participant", c_at), None)', s)

    def test_spell_rank_read_to_its_last_field(self):
        self.assertIn('max(R[k][0] for k in NEED["SpellRank"]) + 1', src("handmem.py"))
        s = src("deckmem.py")
        self.assertIn('lo = min(SR[k] for k in OPTIONAL["SpellRank"])', s)
        self.assertIn('r["pips"] = rr[SR["m_spellRank"] - lo]', s)


# ============================================================================ reflect.py: names after other bytes
class ReflectLoose(unittest.TestCase):
    BUF = b"\x00m_level\x00(@CombatPlanningPhaseWindow\x00\x00Window\x00%s not found\x00"

    def test_grep_loose(self):
        self.assertEqual([n for _a, n, _c in R.grep_names(self.BUF, "Window")], ["Window"])
        got = R.grep_names(self.BUF, "Window", base=0x1000, loose=True)
        self.assertEqual([n for _a, n, _c in got], ["CombatPlanningPhaseWindow", "Window"])
        self.assertEqual(got[0][0], 0x1000 + self.BUF.index(b"Combat"))
        self.assertEqual(R.grep_names(self.BUF, "found", loose=True), [])          # (no space: not a tail of prose)

    def test_name_at_after_a_constant(self):
        i = self.BUF.index(b"Combat")
        self.assertEqual(R.name_at(self.BUF, 0x500, 0x500 + i), "CombatPlanningPhaseWindow")
        self.assertIsNone(R.name_at(self.BUF, 0x500, 0x500 + i + 6))              # (inside it)

    def test_report_uses_them(self):
        s = src("reflect.py")
        self.assertIn("grep_names(rdata, pattern, r0, case, loose=True)", s)
        self.assertIn("img.strings(name) + img.strings(name, loose=True)", s)


# ============================================================================ petmem: a list cut short
class PetLevels(unittest.TestCase):
    def test_cut_short_is_not_read(self):
        import petmem as M
        fm = FakeMem()
        tpl, head = 0x20000000, 0x21000000
        nodes = [0x22000000 + 0x100 * i for i in range(3)]
        fm.put(tpl, struct.pack("<QQ", head, 3))
        fm.put(head, struct.pack("<Q", nodes[0]))
        types_of = {}
        for i, n in enumerate(nodes):
            nxt = nodes[i + 1] if i + 1 < len(nodes) else head
            fm.put(n, struct.pack("<Q", nxt) + bytes(8) + bytes([0x30 + i]) + bytes(0x40))
            types_of[n + 0x10] = "PetLevelInfo"
        rd = types.SimpleNamespace(_rd=fm.read, pace=lambda: None, tname=types_of.get,
                                   u64=lambda a: struct.unpack("<Q", fm.read(a, 8) or bytes(8))[0],
                                   u8=lambda a: (fm.read(a, 1) or b"\0")[0])
        self.assertEqual(len(M.level_entries(rd, tpl, 0, 0)), 3)
        fm.put(nodes[1], bytes(8) + bytes(8) + bytes([0x31]) + bytes(0x40))       # (its next pointer 0 mid-walk)
        self.assertIsNone(M.level_entries(rd, tpl, 0, 0))


# ============================================================================ deckmem: the signature, the names' walk
def import_deckmem():
    from test_petmem import import_deckmem as imp
    return imp()


class DeckSignature(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.D = import_deckmem()

    def make(self):
        D = self.D
        dm = object.__new__(D.DeckMem)
        st = {"gids": [0x11, 0x22, 0x33], "excl": b"\x00\x00", "pet_lv": 3}
        P = {"CoreObject": {"m_globalID.m_full": 0x48}, "DeckBehavior": {"m_spellList": 0x10,
                                                                          "m_serializedExclusionList": 0x98},
             "SpellData": {"m_templateID": 0x48, "m_enchantment": 0x4C, "m_quantity": 0x50},
             "BasePetItemBehavior": {"m_level": 0x60}, "EquipmentSet": {}}
        items = [0x1000, 0x2000, 0x3000]
        dm.P, dm._pace = P, None
        dm.player = lambda: (0x500, "")
        dm.behaviors = lambda o: ({"WizEquipmentBehavior": 0x600} if o == 0x500 else
                                  {"DeckBehavior": 0x700} if o == 0x1000 else
                                  {"PetItemBehavior": 0x800} if o == 0x3000 else {})
        dm.items = lambda eq, cls, cap: (len(items), items)
        dm.u64 = lambda a: st["gids"][items.index(a - 0x48)] if a - 0x48 in items else 0
        dm.slist = lambda a, cap: (2, [0x9000, 0x9100])
        dm._rd = lambda a, n: bytes(n)
        dm.raw_string = lambda a: st["excl"]
        dm.u8 = lambda a: st["pet_lv"] if a == 0x860 else None
        dm.off = lambda c, p: None
        dm.hm = types.SimpleNamespace(template_head=lambda: st.get("tm", 0))
        return dm, st

    def test_changes_with_what_the_item_cards_come_from(self):
        dm, st = self.make()
        s0 = dm.signature()
        self.assertEqual(dm.signature(), s0)
        self.assertTrue(all(v is None or isinstance(v, int) for v in s0))          # (flat: the checkpoint's JSON list)
        st["gids"][1] = 0x44                                                       # (a wand swapped by hand)
        s1 = dm.signature()
        self.assertNotEqual(s1, s0)
        st["excl"] = b"\x01\x00\x05\x00\x00\x00\x01\x00"                           # (an item card turned off)
        s2 = dm.signature()
        self.assertNotEqual(s2, s1)
        st["pet_lv"] = 4                                                           # (the pet grown a level)
        self.assertNotEqual(dm.signature(), s2)
        self.assertEqual(dm.signature()[1], 0x11)                                  # (the worn deck's gid as before)
        s3 = dm.signature()
        st["tm"] = 0x21000000                                                      # (the template map found later)
        self.assertNotEqual(dm.signature(), s3)
        self.assertEqual(dm.signature()[-1], 1)

    def test_names_walk_waits_for_the_template_map(self):
        dm = object.__new__(self.D.DeckMem)
        dm.P = {"SpellTemplate": {"m_name": 0x40}}
        dm.by_name, dm._walk = None, None
        dm.hm = types.SimpleNamespace(template_head=lambda: 0)
        dm._walk_names()
        self.assertIsNone(dm.by_name)                     # (not {} for good: looked for again next time)
        self.assertIsNone(dm._walk)

    def test_names_cut_only_while_a_walk_goes_on(self):
        # (the template map never found: the reading isn't marked names_cut - kept, not read again every deck_sig)
        s = src("deckmem.py")
        i = s.index('out["names_cut"] = True')
        self.assertIn("if self._walk is not None:", s[i - 400:i])


# ============================================================================ navmem
def import_navmem():
    from test_navroute import import_navmem as imp
    return imp()


class Nav(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.N = import_navmem()

    def test_hand_failed_retried_when_the_hand_is(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace(alive=lambda: True)
        again = time.monotonic() + 250.0
        why = "the cards can't be read in this build: the spell effect names couldn't be read"
        nm._hand_fail = (st, again, why)
        nm._hand_reader = lambda s, wait: (None, why)
        said = []
        nm.log = said.append
        for make, fail in ((nm._deck_make, "_deckm_fail"), (nm._gear_make, "_gearm_fail"), (nm._pet_make, "_petm_fail")):
            with mock.patch.dict(sys.modules, {"deckmem": types.ModuleType("deckmem"),
                                               "gearmem": types.ModuleType("gearmem"),
                                               "petmem": types.ModuleType("petmem")}):
                make(st)
            fst, at, fwhy = getattr(nm, fail)
            self.assertIs(fst, st)
            self.assertEqual(at, again)                   # (the hand's own retry - not 5 s)
            self.assertIn("can't be made", fwhy)
            self.assertNotIn("isn't made yet", fwhy)
        # (still being made: 5 s)
        nm._hand_fail = (None, 0.0, "")
        nm._hand_reader = lambda s, wait: (None, "reading the game's card classes (once, about a second)")
        with mock.patch.dict(sys.modules, {"deckmem": types.ModuleType("deckmem")}):
            nm._deck_make(st)
        self.assertLess(nm._deckm_fail[1] - time.monotonic(), 6.0)
        self.assertIn("isn't made yet", nm._deckm_fail[2])

    def test_broken(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        self.assertEqual(nm.broken(), ("", []))
        nm._failed, nm._failed_sig = (42, time.monotonic() + 100, "the GameClient signature isn't in this game build"), True
        self.assertEqual(nm.broken()[1][0][0], "attach")
        st = types.SimpleNamespace(how={"location": "MISSING: the location signature isn't in this game build"},
                                   m=types.SimpleNamespace(build="B-1"))
        nm.st = st
        nm._bagm_fail = (st, time.monotonic() + 300, "the backpack can't be read in this build: x")
        nm._quest_fail = (st, time.monotonic() + 30, "the quest classes couldn't be read (OSError())")
        nm._obj_layout_why = "the zone's objects don't read in this build: 30 places"
        build, out = nm.broken()
        self.assertEqual(build, "B-1")
        self.assertEqual([k for k, _w in out], ["position", "backpack", "objects"])

    def test_position_alone_without_getlocation(self):
        N = self.N
        at = object.__new__(N._Attached)
        at.p = types.SimpleNamespace()
        at.o = {"co_anim": None, "anim_body": None, "body_pos": None, "co_location": None}
        at._member = lambda *a: 0x20000000
        pl, why = at.player(0x10000000)
        self.assertIsNone(pl)
        self.assertIn("location signature", why)
        s = src("navmem.py")
        self.assertNotIn('raise LookupError("the location signature', s)

    def test_mob_names_read_again_after_a_patch(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "Data", "GameData"))
            wad = os.path.join(d, "Data", "GameData", "Root.wad")
            with open(wad, "wb") as f:
                f.write(b"KIWAD1")
            nm.game_dir = d
            lang = "\r\n".join(["head", "1", "c", "Mob One", ""]).encode("utf-16")
            calls = []

            def read(path, wanted):
                calls.append(path)
                return {"Locale/en-US/WizardMobs.lang": lang}
            import navgeo
            with mock.patch.object(navgeo, "read_wad_files", read):
                self.assertEqual(nm._names().get("WizardMobs_1"), "Mob One")
                nm._names()
                self.assertEqual(len(calls), 1)               # (the same Root.wad: kept)
                with open(wad, "ab") as f:
                    f.write(b"patched")
                self.assertEqual(nm._names().get("WizardMobs_1"), "Mob One")
                self.assertEqual(len(calls), 2)               # (another: read again)

    def test_object_layout_said(self):
        s = src("navmem.py")
        self.assertIn("OBJ_LAYOUT_HITS", s)
        self.assertIn('self.log("navmem: " + self._obj_layout_why)', s)


# ============================================================================ bagmem: an unread template
class BagUnread(unittest.TestCase):
    def test_unread_flag_on_its_line(self):
        _stub_navmem()
        import bagmem as B
        lines = B.bag_lines({"crownshop": [("?", "template 5 (its name not read from the game's memory - maybe no "
                                                   "Crown-shop item at all)", True), ("robe", "Crown-S05-Robe-093", False)],
                             "player_gid": None})
        shop = [ln for ln in lines if ln.startswith("crownshop|")]
        self.assertEqual(shop[0].split("|")[3], "1")
        self.assertEqual(shop[1], "crownshop|robe|Crown-S05-Robe-093|0")
        self.assertIn("maybe no Crown-shop item", shop[0])


if __name__ == "__main__":
    unittest.main()
