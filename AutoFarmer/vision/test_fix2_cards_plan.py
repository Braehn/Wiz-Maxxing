"""test_fix2_cards_plan.py - the code review's (2026-11-27) card, kill-check and Spells-tab fixes (the scripts' text read,
not run). Standard library only: python -m unittest test_fix2_cards_plan  (from AutoFarmer\\vision)

Pins: the kill check, PlanProject, TrapHitPick and KillHitsText take one enemy or all by one rule (KillCalc.ahk HitOne:
the game's kind, the wand's, the target key - killcalc-2); a learned card in a slot, named by its slot, keeps its Never
discard and tc in DrawMakeRoom, DiscardIsTc and LearnAllRound (spells-misc-1); DiscardUnused keeps a learned hit queued
for room in hit1-3 only when room would really be made for it - LearnArrangePlan, LearnArrangeNow's own rule, asked
with nothing changed (killcalc-1, the Ra 'no free slot' discard; a weak one queued every battle isn't kept); LearnUri sends UTF-8 bytes (x-protocol-2); LearnLayout
moves the hits' head lines and LearnUndoLayout puts them back (cardlearn-4); a first pairing whose number or name the
game's disagree with, or whose own kind isn't known, waits for a second sighting (cardlearn-5); BoostMisfitDiscard
takes the screen's boxes (known: the learned card's Never discard), needs them to line up and the screen's treasure-card
look (killcalc-3); the Spells list keeps its scroll and waits for an open cell (spells-misc-4);
the Edit window's Save of an untouched X-pip spell changes nothing (spells-misc-3); a spellbook file that can't be read
isn't a first look (spells-misc-5); learned\\slots_written.txt is never written over after a failed read, the change
kept and tried again between battles once a minute, one try (extra-2); the Spells tab's reload says when learned\\cards.txt couldn't be read (extra-3)."""
import os
import re
import unittest
from urllib.parse import parse_qs

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
AF = os.path.join(ROOT, "AutoFarmer")
OWN = ("CardLearn.ahk", "KillCalc.ahk", "Draw.ahk", "Spells.ahk", "Training.ahk", "Planner.ahk")


def read(name):
    with open(os.path.join(AF, name), encoding="utf-8", errors="replace") as fh:
        return fh.read().replace("\r\n", "\n")


def body(text, name):
    """function name's text, from its line to its closing brace at one tab"""
    m = re.search(r"^" + re.escape(name) + r"\([^\n]*\)\n\t\{\n", text, re.M)
    if not m:
        raise AssertionError(name + " not found")
    end = re.search(r"^\t\}\n", text[m.end():], re.M)
    return text[m.start():m.end() + end.end()]


def code(s):
    """s without its whole-line comments"""
    return "\n".join(ln for ln in s.split("\n") if not ln.lstrip().startswith(";"))


def learn_uri(s):
    """CardLearn.ahk LearnUri, as Python: the UTF-8 bytes, letters, digits and -._~ as they are, the rest %XX"""
    out = ""
    for b in s.encode("utf-8"):
        out += chr(b) if (48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122 or b in (45, 46, 95, 126)) else "%%%02X" % b
    return out


class HitOneRule(unittest.TestCase):
    def setUp(self):
        self.kc = read("KillCalc.ahk")

    def test_hit_one(self):
        b = code(body(self.kc, "HitOne"))
        self.assertIn("hoHh := HitHeads(hitName)", b)
        self.assertLess(b.find("if (hoHh.one != \"\")"), b.find("if (hitName = \"wand\")"))
        self.assertIn('return (Stat(hitschool "." hitName "target") = 1) ? 1 : 0', b)

    def test_used_everywhere(self):
        self.assertIn("if (HitOne(hitName) && EnemyHP.Length > 1)", code(body(self.kc, "IsLethal")))
        self.assertIn("khOne := HitOne(kh)", code(body(self.kc, "KillHitsText")))
        self.assertIn('if (RegExMatch(thpP, "^hit[1-4]$") && HitOne(thpP))', code(body(self.kc, "TrapHitPick")))
        self.assertIn("ppOne := HitOne(hitN)", code(body(self.kc, "PlanProject")))
        self.assertNotRegex(code(self.kc), r'"target"\] = 1|"target"\) = 1 && EnemyHP')

    def test_name_free(self):
        for root, _d, files in os.walk(ROOT):
            for f in files:
                if f.endswith(".ahk") and f != "KillCalc.ahk":
                    with open(os.path.join(root, f), encoding="utf-8", errors="replace") as fh:
                        self.assertNotRegex(fh.read(), r"(?m)^HitOne\(", f)


class SlottedLearnedKept(unittest.TestCase):
    def test_draw(self):
        dr = read("Draw.ahk")
        mr = code(body(dr, "DrawMakeRoom"))
        self.assertIn('LearnCardInSlot(StrReplace(k, "/", "\\"))', mr)
        self.assertIn('if (IsObject(lc) && (lc.type = "enchant" || LearnHasFlag(lc, "tc") || LearnHasFlag(lc, "hold")))', mr)
        self.assertIn('if (InStr(k, "learned/") = 1 && !IsObject(lc))', mr)
        self.assertIn('LearnCardInSlot(StrReplace(f[6], "/", "\\"))', code(body(dr, "DiscardIsTc")))

    def test_learn_all(self):
        cl = code(body(read("CardLearn.ahk"), "LearnAllRound"))
        self.assertIn('LearnCardInSlot(StrReplace(c.known, "/", "\\"))', cl)


class QueuedHitKept(unittest.TestCase):
    def test_discard_unused(self):
        b = code(body(read("CardLearn.ahk"), "DiscardUnused"))
        self.assertIn("local cards, f, c, i, k, o, did, most, pid, why, lc, own, ox, queued", b)
        self.assertIn('if (o = "p|" pid)', b)
        self.assertNotIn("(queued || !((hit1 == 1", b)
        self.assertIn('|| (LearnIsHit(lc) && Stat("learnedhits") && (!((hit1 == 1', b)
        self.assertIn("|| (queued && LearnArrangeOk(lc) && IsObject(LearnArrangePlan(lc).place)))))", b)
        self.assertLess(b.find("queued := 0"), b.find("if (LearnSlotOf(pid)"))

    def test_plan_is_now_s_rule(self):
        cl = read("CardLearn.ahk")
        now, plan = code(body(cl, "LearnArrangeNow")), code(body(cl, "LearnArrangePlan"))
        # (the plan changes nothing and says nothing: asked in battle, every round)
        for bad in ("DebugLog(", "LearnLayout(", "LearnSave(", "FileCopy", "LearnStatsWrite("):
            self.assertNotIn(bad, plan)
        self.assertIn("nv < 1.15 * victim.value", plan)
        self.assertIn('return V1Obj({why: why, place: "", victim: ""})', plan)
        self.assertIn('return V1Obj({why: "", place: place, victim: victim})', plan)
        self.assertIn("p := LearnArrangePlan(c)", now)
        self.assertIn("return LearnLayout(c, p.place, p.victim)", now)
        self.assertIn('DebugLog("  learned card " c.id " (" LearnDescribe(c) "): no room made for it - " p.why)', now)
        self.assertNotIn("1.15", now)


class UriUtf8(unittest.TestCase):
    def test_source(self):
        b = code(body(read("CardLearn.ahk"), "LearnUri"))
        self.assertIn('Buffer(StrPut(s, "UTF-8"), 0)', b)
        self.assertIn('NumGet(luBuf, A_Index - 1, "UChar")', b)
        self.assertNotIn("Ord(A_LoopField)", b)

    def test_round_trip(self):
        for p in ("C:\\Users\\Jos\u00e9\\Programs\\Wiz-Maxxing\\AutoFarmer\\generated\\hand",
                  "C:\\Users\\O\u2019Neil\\x y", "plain-ascii_1.2~"):
            self.assertEqual(parse_qs("thumbs=" + learn_uri(p))["thumbs"][0], p)


class HeadLines(unittest.TestCase):
    def setUp(self):
        self.cl = read("CardLearn.ahk")

    def test_keys(self):
        b = code(body(self.cl, "LearnHitKeys"))
        self.assertIn('["", "pips", "target", "keep", "balance", "death", "fire", "ice", "life", "myth", "storm"]', b)

    def test_layout_moves_them(self):
        b = code(body(self.cl, "LearnLayout"))
        self.assertIn('edits.Push([kk lyS, (lyMany && lyHh.heads.Has(lyS)) ? kk lyS ":" lyHh.heads[lyS] : ""])', b)
        self.assertIn('before[sch ".hit" occ.from lyS]', b)
        self.assertLess(b.find("edits.Push([kk lyS"), b.find("if (!LearnStatsWrite(edits))"))

    def test_undo_old_snapshots(self):
        b = code(body(self.cl, "LearnUndoLayout"))
        self.assertIn('if (aft.Has(kk) || old.Has(kk) || !RegExMatch(kk, "\\.hit\\d(balance|death|fire|ice|life|myth|storm)$"))', b)
        self.assertLess(b.find("keys := ulKeys"), b.find("if (!aft.Has(kk) ||"))


class LookAlikeWait(unittest.TestCase):
    def test_number_and_name(self):
        b = code(body(read("CardLearn.ahk"), "LearnSeenAgain"))
        self.assertIn('|| (c.value != "" && memR.value != "" && c.value != memR.value)', b)
        self.assertIn('Trim(c.name) != memR.name && Trim(c.name) != memR.game', b)
        self.assertIn('|| (c.type = "" && memR.kind != "")', b)


class MisfitLinesUp(unittest.TestCase):
    def test_guards(self):
        b = code(body(read("KillCalc.ahk"), "BoostMisfitDiscard"))
        # (the screen's boxes: the memory's - HandBoxes under memclicks:1 - know no picture, so no hold, no line-up check)
        self.assertIn("bmdAll := BoostBoxes(300)", b)
        self.assertNotIn("HandBoxes(", b)
        self.assertIn('LearnHasFlag.Call(bmdLc, "hold")', b)
        self.assertIn("if (!IsObject(bmdAll) || !BoxesLineUp(bmdAll, &bmdOff))", b)
        self.assertIn("bmdOff", b.split("\n")[3])
        self.assertIn('(V1IsFunc("DiscardIsTc") && DiscardIsTc(Round(bmdB.l + bmdB.w / 2)))', b)


class SpellsTab(unittest.TestCase):
    def setUp(self):
        self.sp = read("Spells.ahk")

    def test_list_keeps_place(self):
        b = code(body(self.sp, "SpListFill"))
        self.assertLess(b.find("if (SpCellHwnd)"), b.find("lv.Delete()"))
        self.assertRegex(b, r"if \(SpCellHwnd\)\n\t\t\{\n\t\tSpDirty := 1\n\t\treturn")
        self.assertIn("0x1027", b)
        self.assertIn("0x1028", b)
        self.assertIn('lv.Modify(Min(slTopRow + slPage - 1, lv.GetCount()), "Vis")', b)
        self.assertLess(b.find('lv.Opt("+Redraw")'), b.find('"Vis")'))

    def test_xpip_save_unchanged(self):
        b = code(body(self.sp, "SpEdSaveNow"))
        self.assertIn('bPips := SpPipsEditText(c, b), bPips := (bPips = "x" || bPips = "X") ? "x" : bPips', b)
        self.assertIn("pips = bPips", b)
        c = code(body(self.sp, "SpCellCommit"))
        self.assertIn('(col = "pips" ? pips = bPips : pips = b.pips)', c)

    def test_reload_note(self):
        b = code(body(self.sp, "SpApplyPending"))
        self.assertIn('spGot := SpL("LearnLoad")', b)
        self.assertIn("if (spGot = 0)", b)
        self.assertIn("couldn't be read", b)


class SpellbookRead(unittest.TestCase):
    def test_failed_not_first_look(self):
        tr = read("Training.ahk")
        ld = code(body(tr, "TrainBookLoad"))
        self.assertIn("TrainBookLoad(path, &failed := false)", ld)
        self.assertRegex(ld, r"catch\n\t\t\{\n\t\tfailed := true\n\t\treturn \"\"")
        tk = code(body(tr, "TrainBookTick"))
        self.assertIn("tbtKnown := TrainBookLoad(tbtPath, &tbtFailed)", tk)
        self.assertLess(tk.find("if (tbtFailed)"), tk.find("TrainBookSave(tbtPath, tbtBook.spells, true)"))


class SlotsWritten(unittest.TestCase):
    def setUp(self):
        self.cl = read("CardLearn.ahk")

    def test_global(self):
        self.assertRegex(self.cl, r"(?m)^global LearnWrittenWait\b")
        self.assertIn('LearnWrittenWait := ""', body(self.cl, "CardLearnBlank"))

    def test_not_written_over_after_failed_read(self):
        b = code(body(self.cl, "LearnWritten"))
        self.assertIn("global LearnWrittenWait", b)
        self.assertIn("have := V1FileRead(file), failed := ErrorLevel", b)
        fail = b[b.find("if (failed && FileExist(file))"):b.find("list := V1Obj()")]
        self.assertIn("return", fail)
        self.assertNotIn("LearnWrittenWait := []", fail)
        self.assertLess(b.find("if (failed && FileExist(file))"), b.find("LearnFileReplace("))
        self.assertRegex(b, r"if \(LearnFileReplace\(file, out\)\)\n\t\tLearnWrittenWait := \[\]")

    def test_retried_between_battles(self):
        b = code(body(self.cl, "LearnOutOfBattle"))
        self.assertIn("static writtenTry := 0", b)
        self.assertIn('if (IsObject(LearnWrittenWait) && LearnWrittenWait.Length && (!writtenTry || A_TickCount - writtenTry >= 60000))'
                      '\n\t\twrittenTry := A_TickCount, LearnWritten("", true)', b)

    def test_retry_one_try_said_once(self):
        b = code(body(self.cl, "LearnWritten"))
        self.assertIn('Loop (paths = "" ? 1 : 3)', b)
        self.assertIn("static lwSaid := 0", b)
        self.assertIn('if (paths != "" || !lwSaid)', b)
        self.assertLess(b.find("lwSaid := 0\n\tlist := V1Obj()"), b.find("LearnFileReplace("))


class Crlf(unittest.TestCase):
    def test_crlf(self):
        for name in OWN:
            with open(os.path.join(AF, name), "rb") as fh:
                raw = fh.read()
            self.assertEqual(raw.count(b"\n"), raw.count(b"\r\n"), name)


if __name__ == "__main__":
    unittest.main()
