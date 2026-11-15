"""test_battlehist.py - the Battles tab's history (vision\\battlehist.py) from made-up recorder files: a battle in
progress (current.json, from stand-in log lines fed to battlerec's Parser - test_battlerec's Log), recorded battles (a
day file, read again only for what was added to it), the list, the names (You, numbered enemies, a stranger by side) and
what each cast did. No game, temp folders only:
    python -m unittest test_battlehist      (from AutoFarmer\\vision)"""
import json
import os
import shutil
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlehist as H  # noqa: E402
import battlerec as R  # noqa: E402
from test_battlerec import Log  # noqa: E402

NOW = time.mktime((2026, 11, 15, 17, 0, 0, 0, 0, -1))


def record(id_, t0, result="won", casts=None, parts=None, rounds_n=1, died=None, fx=None):
    parts = parts if parts is not None else [
        {"sc": 0, "side": "enemy", "name": "Winter Skull"}, {"sc": 1, "side": "enemy", "name": "Winter Skull"},
        {"sc": 4, "side": "me", "name": "Ned Stormblade"}, {"sc": 5, "side": "ally", "name_h": "abcdef0123"}]
    return {"rec": "battle", "v": 1, "id": id_, "t0": t0, "result": result, "rounds_n": rounds_n,
            "zone": "Grizzleheim/GH_Nastrond", "parts": parts,
            "rounds": [{"n": 1, "casts": casts or [], "died": died or [], "fx": fx or {}}]}


class Base(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.base = H.battles_dir(self.root)
        os.makedirs(os.path.join(self.base, "2026-11"))
        H._DAYS.clear()
        H._CUR.update(key=None, duel=None)
        H._NAMES.update(key=None, map={})

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def day(self, recs, name="2026-11-15.jsonl", mode="w"):
        with open(os.path.join(self.base, "2026-11", name), mode, encoding="utf-8", newline="\n") as f:
            if mode == "w":
                f.write(json.dumps({"rec": "header", "v": 1}) + "\n")
            for r in recs:
                f.write(json.dumps(r, separators=(",", ":")) + "\n")

    def rows(self, text):
        lines = text.split("\n")
        return lines[0].split("\t"), [ln.split("\t") for ln in lines[1:]]


class Names(Base):
    def test_who(self):
        who = H.who_names(record("x", "")["parts"])
        self.assertEqual(who[4], ("me", "You"))
        self.assertEqual((who[0][1], who[1][1]), ("Winter Skull 1", "Winter Skull 2"))
        self.assertEqual(who[5], ("ally", "Ally"))
        self.assertEqual(H.enemies_text(who), "Winter Skull x2")
        self.assertEqual(H.who_names([{"sc": 2, "side": "enemy", "obj": "CL_Rat-R3"}])[2], ("enemy", "Rat"))

    def test_pretty(self):
        self.assertEqual(H.pretty("HeckHoundIce_Trainable"), "Heck Hound Ice")
        self.assertEqual(H.pretty("Pet - Infallible - Trigger"), "Pet: Infallible")
        self.assertEqual(H.pretty("Storm Lord"), "Storm Lord")
        self.assertEqual(H.pretty("SL_Storm", {"SL_Storm": "Storm Lord"}), "Storm Lord")
        with open(os.path.join(self.base, "cards.jsonl"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"rec": "card", "name": "GH_Frost", "display": "Frost Giant"}) + "\n{torn\n")
        self.assertEqual(H.card_names(self.base), {"GH_Frost": "Frost Giant"})


class Casts(Base):
    def test_what_each_did(self):
        who = H.who_names(record("x", "")["parts"])
        hit = {"sc": 4, "spell": "Sandstorm", "pips": [4, 0, 0, 0], "fx": [[0, "kDamage", 383], [1, "kDamage", 383]],
               "hp": [[0, 1690, -1688], [1, 1690, -766]], "crit": [[844, 2, 0, 1688]]}
        self.assertEqual(H.cast_line(hit, who, {}),
                         ("Sandstorm", "4", "all enemies", "1,688 to Winter Skull 1; 766 to Winter Skull 2; critical"))
        feint = {"sc": 4, "spell": "Feint", "pips": [1, 0, 1, 0],
                 "fx": [[0, "kModifyIncomingDamage", 70], [4, "kModifyIncomingDamage", 30]]}
        self.assertEqual(H.cast_line(feint, who, {})[2:], ("Winter Skull 1, You", "trap +70% on Winter Skull 1; trap +30% on You"))
        self.assertEqual(H.cast_line({"sc": 0, "spell": None, "pass": True}, who, {}), ("Pass", "", "", ""))
        self.assertEqual(H.cast_line({"sc": 1, "spell": "Blizzard", "missed": True}, who, {})[3], "fizzled")
        heal = {"sc": 5, "spell": "Pixie", "pips": [2, 0, 3, 0], "fx": [[4, "kHeal", 400]], "hp": [[4, 1000, 400]]}
        self.assertEqual(H.cast_line(heal, who, {})[2:], ("You", "healed You 400"))
        shield = {"sc": 0, "spell": "Tower Shield", "pips": [0, 1, 0, 0], "fx": [[0, "kModifyIncomingDamage", -50]]}
        self.assertEqual(H.cast_line(shield, who, {})[1:], ("0+1 shadow", "Winter Skull 1", "shield -50% on Winter Skull 1"))
        blocked = {"sc": 0, "spell": "Blizzard", "fx": [[4, "kDamage", 300]]}
        self.assertEqual(H.cast_line(blocked, who, {})[3], "300 to You (no health lost)")

    def test_rows_with_ticks_and_knockouts(self):
        rec = record("20261115-162258-1", "2026-11-15 16:22:58", died=[0], fx={"hp": [[4, 2000, -120]]},
                     casts=[{"sc": 4, "spell": "Ra", "hp": [[0, 900, -900]]}, {"sc": 4, "spell": "Pet - Spritely - Trigger", "pet": True}])
        head, rows = self.rows(H.record_answer(rec, {}))
        self.assertEqual(head, ["h", "20261115-162258-1", "0", "won", "1", "Grizzleheim/GH_Nastrond", "Winter Skull x2", "16:22"])
        self.assertEqual([r[4] for r in rows], ["Ra", "Pet: Spritely", "(over time)", "(knocked out)"])
        self.assertEqual(rows[2][7], "120 to You")
        self.assertEqual(rows[3][6], "Winter Skull 1")
        self.assertTrue(all(len(r) == 8 for r in rows))


class Files(Base):
    def test_list_and_one_battle(self):
        self.day([record("20261115-101000-1", "2026-11-15 10:10:00", "lost"),
                  record("20261115-120000-2", "2026-11-15 12:00:00", "won")])
        self.day([record("20261114-230000-3", "2026-11-14 23:00:00", "fled")], name="2026-11-14.jsonl")
        lst = [ln.split("\t") for ln in H.reply(self.root, {"list": "1"}, NOW).split("\n")]
        self.assertEqual([x[1] for x in lst], ["20261115-120000-2", "20261115-101000-1", "20261114-230000-3"])
        self.assertEqual(lst[0], ["b", "20261115-120000-2", "12:00", "won", "1", "Winter Skull x2"])
        head, _ = self.rows(H.reply(self.root, {"b": "20261115-101000-1"}, NOW))
        self.assertEqual(head[1:4], ["20261115-101000-1", "0", "lost"])
        # (no battle in progress: "cur" is the last one recorded)
        head, _ = self.rows(H.reply(self.root, {"b": "cur"}, NOW))
        self.assertEqual(head[1], "20261115-120000-2")
        self.assertTrue(H.reply(self.root, {"b": "nope"}, NOW).startswith("none\t"))

    def test_read_on_from_where_it_stopped(self):
        self.day([record("20261115-101000-1", "2026-11-15 10:10:00")])
        self.assertEqual(len(H.recent(self.base, NOW)), 1)
        pos = H._DAYS[os.path.join(self.base, "2026-11", "2026-11-15.jsonl")]["pos"]
        # (a battle added, and a torn line still being written: the torn one waits)
        self.day([record("20261115-110000-2", "2026-11-15 11:00:00")], mode="a")
        with open(os.path.join(self.base, "2026-11", "2026-11-15.jsonl"), "a", encoding="utf-8") as f:
            f.write('{"rec":"battle","id":"half')
        items = H.recent(self.base, NOW)
        self.assertEqual([i["id"] for i in items], ["20261115-110000-2", "20261115-101000-1"])
        self.assertGreater(H._DAYS[os.path.join(self.base, "2026-11", "2026-11-15.jsonl")]["pos"], pos)
        head, _ = self.rows(H.reply(self.root, {"b": "20261115-110000-2"}, NOW))
        self.assertEqual(head[1], "20261115-110000-2")

    def test_nothing_recorded(self):
        self.assertTrue(H.reply(self.root, {"list": "1"}, NOW).startswith("none\t"))
        self.assertTrue(H.reply(self.root, {"b": "cur"}, NOW).startswith("none\t"))


class InProgress(Base):
    def checkpoint(self, parser):
        with open(os.path.join(self.base, "current.json"), "w", encoding="utf-8") as f:
            f.write(R.dumps({"v": 1, "parser": R.Parser.save(parser)}))

    def test_the_battle_in_progress(self):
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0)])
        L.cast(1, 4, "Stormblade")
        L.hang(4, "kModifyOutgoingDamage", True, 35)
        L.cast(1, 0, "Rat Bite")
        L.target(0, 4, "kDamage", 120)
        L.hp(21, 3000, -120)
        L.resolution()
        self.checkpoint(L.p)
        self.day([record("20261115-101000-1", "2026-11-15 10:10:00")])
        head, rows = self.rows(H.reply(self.root, {"b": "cur"}, NOW))
        self.assertEqual(head[2:4], ["1", "in progress"])
        self.assertEqual(head[6], "Rat")
        self.assertEqual([r[2:5] for r in rows], [["me", "You", "Stormblade"], ["enemy", "Rat", "Rat Bite"]])
        self.assertEqual(rows[1][6:], ["You", "120 to You"])
        # (the next round, checkpointed: read again)
        L.planning()
        L.execution([(11, 1, 501, 2, 0), (21, 0, 2880, 2, 0)])
        L.cast(2, 4, "Storm Lord")
        L.target(4, 0, "kDamage", 900)
        L.hp(11, 501, -501)
        L.resolution()
        self.checkpoint(L.p)
        st = os.stat(os.path.join(self.base, "current.json"))
        os.utime(os.path.join(self.base, "current.json"), ns=(st.st_atime_ns, st.st_mtime_ns + 1000000))
        _, rows = self.rows(H.reply(self.root, {"b": "cur"}, NOW))
        self.assertEqual(rows[-2][4], "Storm Lord")
        self.assertEqual(rows[-1][4:7], ["(knocked out)", "", "Rat"])
        # (over: no open duel - the last battle recorded)
        L.win()
        self.checkpoint(L.p)
        os.utime(os.path.join(self.base, "current.json"), ns=(st.st_atime_ns, st.st_mtime_ns + 2000000))
        head, _ = self.rows(H.reply(self.root, {"b": "cur"}, NOW))
        self.assertEqual(head[1:3], ["20261115-101000-1", "0"])


if __name__ == "__main__":
    unittest.main()
