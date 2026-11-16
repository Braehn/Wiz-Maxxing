"""test_quests.py - every quest for /quests (questmem.py quest_props, quest_lines, QuestMem.quest_ids / quest_raw /
quests_resolve / read_kind, navmem.py NavMem.quests, vision.py quests_answer) on made-up readings - questmem imported with
navmem stood in for (its ctypes.WinDLL can't load here) and sys.modules put back afterwards:
    python -m unittest test_quests   (from AutoFarmer\\vision)"""
import os
import struct
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spellplan  # noqa: E402   (pure: reads the answer back)
from test_handmem_boxes import import_handmem  # noqa: E402


def import_questmem():
    """questmem with navmem and handmem as they are (the real ones when imported already), else stand-ins put in
    sys.modules for the import only; sys.modules left as it was found - questmem too when it wasn't there"""
    saved = {k: sys.modules.get(k) for k in ("navmem", "handmem", "questmem")}
    real = saved["questmem"]
    if real is not None and getattr(real, "__file__", None) and hasattr(real, "quest_lines"):
        return real
    try:
        H = import_handmem()
        if saved["navmem"] is None:
            nav = types.ModuleType("navmem")
            nav.ptr_ok = lambda v: 0x10000 <= v < 0x7FFFFFFF0000
            nav.ReadError = type("ReadError", (Exception,), {})
            nav.DATA, nav.KNOWN, nav.SIGS = {"window_name": 0x50}, {}, {}
            sys.modules["navmem"] = nav
        sys.modules["handmem"] = H
        sys.modules.pop("questmem", None)
        import questmem
        return questmem
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


Q = import_questmem()

# adders (AddProperty<T>) of the known properties: KIND_REF's
P = {"Window": {"m_sName": (0x50, 0x3200), "m_fAlpha": (0x90, 0x3600)},
     "ControlText": {"m_sText": (0x2C8, 0x3300), "m_bUseOutline": (0x300, 0x3400)},
     "SpellEffect": {"m_numRounds": (0x48, 0x3000)}, "Spell": {"m_templateID": (0x80, 0x3100)},
     "WizGoalData": {"m_goalID": (0x48, 0x3500)},
     "WizQuestData": {"m_id": (0x48, 0x3500), "m_title": (0x50, 0x3200), "m_questLevel": (0x70, 0x3000),
                      "m_mainline": (0x74, 0x3400), "m_goalList": (0x80, 0x9999), "m_name": (0x60, 0x3200),
                      "m_weight": (0x78, 0x3600), "m_permit": (0x88, None)}}


class Pure(unittest.TestCase):
    def test_adder_kinds(self):
        self.assertEqual(Q.adder_kinds(P), {0x3200: "string", 0x3300: "wstring", 0x3000: "int", 0x3100: "uint",
                                            0x3600: "float", 0x3500: "gid", 0x3400: "bool"})
        self.assertEqual(Q.adder_kinds({}), {})

    def test_quest_props(self):
        got = Q.quest_props(P["WizQuestData"], Q.adder_kinds(P))
        # (by offset; m_id / m_title read already; a list's or no adder's left out - none named here)
        self.assertEqual(got, [("m_name", 0x60, "string"), ("m_questLevel", 0x70, "int"), ("m_mainline", 0x74, "bool"),
                               ("m_weight", 0x78, "float")])
        self.assertEqual(Q.quest_props(P["WizQuestData"], Q.adder_kinds(P), cap=2), got[:2])
        self.assertEqual(Q.quest_props(None, {}), [])

    def test_quest_lines(self):
        rows = [{"id": 101, "title": "Main|Story", "title_key": "QuestTitle_1", "tracked": True,
                 "props": {"m_questLevel": 12, "m_mainline": True, "m_name": "a,b=c", "m_weight": None},
                 "goals": [{"gid": 11, "type": "BOUNTY", "status": "COMPLETE", "count": 3, "total": 3,
                            "text": "Defeat Gobblers (3 of 3)", "mob": "Gobblers", "item": "", "npc": "",
                            "place": "Triton Avenue", "name_key": "WizardQuestGoals_Kill"},
                           {"gid": 12, "type": "PERSONA", "status": "INCOMPLETE", "count": None, "total": None,
                            "text": None, "npc": "Merle Ambrose", "name_key": ""}]},
                {"id": 102, "title": "", "title_key": "", "tracked": False, "props": {}, "goals": []}]
        self.assertEqual(Q.quest_lines(rows, "", 12.34), [
            "quest|101|Main Story|1|2|1|QuestTitle_1|m_questLevel=12,m_mainline=1,m_name=a b c,m_weight=",
            "goal|101|11|BOUNTY|COMPLETE|3|3|Defeat Gobblers (3 of 3)|Gobblers|||Triton Avenue|WizardQuestGoals_Kill",
            "goal|101|12|PERSONA|INCOMPLETE||||||Merle Ambrose||",
            "quest|102||0|0|0||",
            "quests|2|101|12.3|"])
        self.assertEqual(Q.quest_lines(None, "no quests|here"), ["none|no quests here"])
        self.assertEqual(Q.quest_lines([], "x"), ["quests|0|||x"])

    def test_read_back(self):
        rows = [{"id": 7, "title": "Spell", "title_key": "k", "tracked": False, "props": {"m_flag": False},
                 "goals": [{"gid": 1, "type": "WAYPOINT", "status": "INCOMPLETE", "text": "Go to X", "place": "X"}]}]
        q = spellplan.parse_quests("\n".join(Q.quest_lines(rows, "why")))
        self.assertEqual([(x["id"], x["title"], x["tracked"], x["props"]) for x in q["quests"]],
                         [(7, "Spell", False, {"m_flag": "0"})])
        self.assertEqual((q["quests"][0]["goals"][0]["type"], q["quests"][0]["goals"][0]["place"]), ("WAYPOINT", "X"))
        self.assertEqual((q["n"], q["tracked"], q["why"]), (1, None, "why"))

    def test_persona_name_keys(self):
        # (a persona NPC's names are in the tables "Persona,First" and "Persona,Last" - with a comma; 2026-11-16 the goal line
        # said "Talk To Persona,First_00000025 Persona,Last_00000020" and Sir Reginald Baxby's prompt never matched it)
        for key, table in (("Persona,First_00000025", "Persona,First"), ("Persona,Last_00000020", "Persona,Last"),
                           ("Persona, First_00000012", "Persona, First"), ("WizardMobs_00000720", "WizardMobs"),
                           ("WC-NPCs_00000014", "WC-NPCs")):
            self.assertEqual(Q.raw_key(key), key)
            self.assertIn(table, Q.Lang.candidates(key))
        for words in ("Talk To", "Sir Reginald", "Baxby, Sir", "a, b"):
            self.assertEqual(Q.raw_key(words), "")
            self.assertEqual(Q.Lang.candidates(words), [])

        class Lang:
            def text(self, key):
                return {"Persona,First_00000025": "Sir Reginald", "Persona,Last_00000020": "Baxby"}.get(key)

        qm = Q.QuestMem.__new__(Q.QuestMem)
        qm.lang = Lang()
        self.assertEqual((qm.name("Persona,First_00000025"), qm.name("Persona,Last_00000020"), qm.name("Talk To")),
                         ("Sir Reginald", "Baxby", "Talk To"))


class FakeP:
    """made-up memory: {address: bytes}; strings at their own addresses"""

    def __init__(self, mem, strings=None):
        self.mem, self.strings = mem, strings or {}

    def try_read(self, a, n):
        for base, b in self.mem.items():
            if base <= a and a + n <= base + len(b):
                return b[a - base:a - base + n]
        return None

    def try_string(self, a):
        return self.strings.get(a)


QA, QB, QC = 0x10000000, 0x10001000, 0x10002000     # three quest objects
G1, G2, G3 = 0x20000000, 0x20001000, 0x20002000     # goals


def fake_qm(tracked_ok=True):
    """a QuestMem whose reads are made up: quests 101 (QA - two goals, G2 not a goal), 102 (QB - its m_id changed: gone)
    and 103 (QC - no goal map); WizQuestData's m_questLevel (int +0x70) and m_mainline (bool +0x74)"""
    qm = object.__new__(Q.QuestMem)
    qm.log = lambda m: None
    qm.P = {"WizQuestData": {"m_id": (0x48, 1), "m_title": (0x50, 2)}, "WizGoalData": {"m_goalID": (0x48, 3)}}
    qm.quest_extra = [("m_questLevel", 0x70, "int"), ("m_mainline", 0x74, "bool")]
    mem = {QA: struct.pack("<72xQ32xiB", 101, 12, 1), QB: struct.pack("<72xQ", 999), QC: struct.pack("<72xQ32xiB", 103, 30, 0)}
    qm.p = FakeP(mem, {QA + 0x50: "QuestTitle_A", QC + 0x50: "QuestTitle_C"})
    types_ = {QA: "WizQuestData", QB: "WizQuestData", QC: "WizQuestData", G1: "WizGoalData", G2: "WizThing",
              G3: "WizGoalData"}
    gids = {G1: 11, G3: 13}
    qm.tname = lambda a: types_.get(a)
    qm.u64 = lambda a: {QA + 0x48: 101, QB + 0x48: 999, QC + 0x48: 103, G1 + 0x48: 11, G3 + 0x48: 13}.get(a, 0)
    qm.how = {"qm": "known static"}
    qm.qmap = lambda: (0x1, 3)
    qm.map_nodes = lambda head, lim=5000: {0x1: [(103, QC), (101, QA), (102, QB)], 0x2: [(13, G3), (12, G2), (11, G1)]
                                           }.get(head, [])
    qm.goal_map = lambda q: (0x2, 3) if q == QA else None
    qm.goal_raw = lambda g: {"gid": gids[g], "name_key": "WizardQuestGoals_Kill", "status": "INCOMPLETE",
                             "type": "BOUNTY", "location_key": "ZoneLocName_1",
                             "madlibs": [("TALLYTEXT2", "string", "WizardMobs_1"), ("COUNT", "int", 0)]}
    loads = []

    class Lang:
        def load(self, keys, block=True):
            loads.append((sorted(keys), block))
    qm.lang = Lang()
    qm.loads = loads
    qm.name = lambda v: {"QuestTitle_A": "Quest A"}.get(v) if v else ""
    qm.resolve = lambda snap, block=True: {"text": "Defeat it (%s)" % snap["goal"]["gid"], "type": "BOUNTY",
                                           "status": snap["goal"]["status"], "count": 0, "total": 3, "mob": "M",
                                           "name_key": "WizardQuestGoals_Kill", "why": ""}
    return qm


class Reader(unittest.TestCase):
    def test_quest_ids(self):
        qm = fake_qm()
        self.assertEqual(qm.quest_ids(), ([(101, QA), (102, QB), (103, QC)], ""))
        qm.qmap = lambda: None
        self.assertEqual(qm.quest_ids(), (None, "no quests in the game's memory (known static)"))

    def test_quest_raw(self):
        qm = fake_qm()
        raw = qm.quest_raw(101, QA)
        self.assertEqual((raw["id"], raw["title_key"]), (101, "QuestTitle_A"))
        self.assertEqual([g["gid"] for g in raw["goals"]], [11, 13])         # (G2 isn't a goal: left out)
        self.assertEqual(raw["props"], {"m_questLevel": 12, "m_mainline": True})
        self.assertIsNone(qm.quest_raw(102, QB))                             # (its m_id isn't 102 any more)
        self.assertIsNone(qm.quest_raw(101, 0))
        self.assertEqual(qm.quest_raw(103, QC)["goals"], [])
        self.assertEqual(qm.quest_raw(103, QC)["props"], {"m_questLevel": 30, "m_mainline": False})

    def test_quests_resolve(self):
        qm = fake_qm()
        raws = [qm.quest_raw(101, QA), qm.quest_raw(103, QC), {"id": 104}]
        rows = qm.quests_resolve(raws, tracked=101, block=True)
        self.assertEqual([(r["id"], r["title"], r["tracked"]) for r in rows],
                         [(101, "Quest A", True), (103, "", False), (104, "", False)])
        self.assertEqual([(g["gid"], g["text"], g["status"]) for g in rows[0]["goals"]],
                         [(11, "Defeat it (11)", "INCOMPLETE"), (13, "Defeat it (13)", "INCOMPLETE")])
        self.assertEqual(rows[0]["props"], {"m_questLevel": 12, "m_mainline": True})
        # (every name table they need in one pass, before the goals are built)
        self.assertEqual(len(qm.loads), 1)
        self.assertEqual(qm.loads[0][1], True)
        self.assertTrue({"QuestTitle_A", "QuestTitle_C", "WizardMobs_1", "ZoneLocName_1", "Quest_x"} <= set(qm.loads[0][0]))
        # (a quest that fails is left out, the rest given)
        qm.resolve = lambda snap, block=True: 1 / 0
        self.assertEqual([r["id"] for r in qm.quests_resolve(raws, tracked=None)], [103, 104])

    def test_read_kind(self):
        qm = object.__new__(Q.QuestMem)
        A = 0x30000000
        qm.p = FakeP({A: struct.pack("<iIfQB", -5, 7, 1.5, 0x1122334455, 1)}, {A + 0x40: "str"})
        qm.wstr = lambda a: "w" if a == A else None
        qm.i32 = lambda a: struct.unpack("<i", qm.p.try_read(a, 4))[0]
        qm.u32 = lambda a: struct.unpack("<I", qm.p.try_read(a, 4))[0]
        self.assertEqual(qm.read_kind(A, "int"), -5)
        self.assertEqual(qm.read_kind(A + 4, "uint"), 7)
        self.assertEqual(qm.read_kind(A + 8, "float"), 1.5)
        self.assertEqual(qm.read_kind(A + 12, "gid"), 0x1122334455)
        self.assertEqual(qm.read_kind(A + 20, "bool"), True)
        self.assertEqual(qm.read_kind(A + 0x40, "string"), "str")
        self.assertEqual(qm.read_kind(A, "wstring"), "w")
        self.assertIsNone(qm.read_kind(0x40000000, "bool"))
        self.assertIsNone(qm.read_kind(A, "adder 0x1234"))


class NavQuests(unittest.TestCase):
    """navmem.NavMem.quests: the map under the lock, each quest under it on its own, the names outside it (the real
    navmem, its Windows DLLs stood in for - test_navroute's import)"""

    @classmethod
    def setUpClass(cls):
        from test_navroute import import_navmem
        cls.N = import_navmem()

    def test_quests(self):
        nm = self.N.NavMem(log=lambda m: None)
        st = object()
        held = []

        class QM:
            def snapshot(self, ids):
                held.append(("snap", nm.lock.locked(), ids))
                return {"ids": (101, 11), "why": ""}

            def quest_ids(self):
                return [(101, QA), (102, QB)], ""

            def quest_raw(self, qid, q):
                held.append(("raw", nm.lock.locked(), qid))
                return {"id": qid} if qid == 101 else None

            def quests_resolve(self, raws, tracked=None, block=True):
                held.append(("resolve", nm.lock.locked(), tracked, block))
                return [dict(r, tracked=r["id"] == tracked) for r in raws]
        qm = QM()
        nm.st = st
        nm._ensure = lambda wait: (st, "")
        nm._quest_reader = lambda s, wait: (qm, "")
        nm._read = lambda s, path: {"quest": 101, "goalid": 11}
        rows, why = nm.quests(wait=0.3)
        self.assertEqual(rows, [{"id": 101, "tracked": True}])
        self.assertEqual(why, "1 quest(s) left the map while it was read")
        self.assertEqual(held, [("snap", True, (101, 11)), ("raw", True, 101), ("raw", True, 102),
                                ("resolve", False, 101, True)])
        qm.quest_ids = lambda: (None, "no quests in the game's memory (x)")
        self.assertEqual(nm.quests(), (None, "no quests in the game's memory (x)"))
        nm._quest_reader = lambda s, wait: (None, "reading the game's quest classes")
        self.assertEqual(nm.quests(), (None, "reading the game's quest classes"))
        nm._ensure = lambda wait: 1 / 0
        self.assertEqual(nm.quests()[0], None)


class QuestsAnswer(unittest.TestCase):
    def test_answer(self):
        import vision as V
        keep = (V.nav_reader, sys.modules.get("questmem"))
        sys.modules["questmem"] = Q
        try:
            class Nav:
                def quests(self, wait=0.5):
                    return [{"id": 5, "title": "T", "tracked": True, "goals": [], "props": {}}], ""
            V.nav_reader = lambda: Nav()
            lines = V.quests_answer()
            self.assertEqual(lines[0], "quest|5|T|1|0|0||")
            self.assertTrue(lines[-1].startswith("quests|1|5|"))

            class Bad:
                def quests(self, wait=0.5):
                    return None, "the game is not running"
            V.nav_reader = lambda: Bad()
            self.assertEqual(V.quests_answer(), ["none|the game is not running"])
            V.nav_reader = lambda: 1 / 0
            self.assertTrue(V.quests_answer()[0].startswith("none|reading the quests failed (ZeroDivisionError"))
        finally:
            V.nav_reader, had = keep
            if had is None:
                sys.modules.pop("questmem", None)
            else:
                sys.modules["questmem"] = had


if __name__ == "__main__":
    unittest.main()
