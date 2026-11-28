"""test_fix_cards.py - learned\\cards.txt and learned\\slots_written.txt are never lost to a failed read or write (the
script's text read, not run). Standard library only: python -m unittest test_fix_cards  (from AutoFarmer\\vision)

Review 2026-11-27 (x-persistence-3, cardlearn-2): LearnSave and LearnWritten moved their .tmp over the real file without
checking FileAppend, so a full disk (the .tmp made, the write failing partway) emptied the catalog; and LearnLoad took a
failed read of an existing cards.txt for an empty catalog, which the next LearnSave wrote over the file. Pins: both go
through LearnFileReplace (FileAppend's ErrorLevel and the .tmp's size checked before the FileMove, the .tmp deleted on a
failure); LearnLoad marks a failed read LearnLoadFailed (a missing file still an empty catalog), keeps a catalog read
before, and LearnSave / LearnNew / LearnBoostPicFix do nothing while it's set; LearnCards and LearnOutOfBattle read it
again; LearnLoadFailed is declared and blank at start (CardLearnBlank)."""
import os
import re
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CARDLEARN = os.path.join(ROOT, "AutoFarmer", "CardLearn.ahk")


def read():
    with open(CARDLEARN, encoding="utf-8", errors="replace") as fh:
        return fh.read().replace("\r\n", "\n")


def body(text, name):
    """function name's text, from its line to the next function's (a name at the line's start followed by ( and a {)"""
    m = re.search(r"^" + re.escape(name) + r"\([^\n]*\)\n\t\{\n", text, re.M)
    if not m:
        raise AssertionError(name + " not found in CardLearn.ahk")
    end = re.search(r"^\t\}\n", text[m.end():], re.M)
    return text[m.start():m.end() + end.end()]


def code(s):
    """s without its whole-line comments"""
    return "\n".join(ln for ln in s.split("\n") if not ln.lstrip().startswith(";"))


class FileReplace(unittest.TestCase):
    def setUp(self):
        self.text = read()
        self.fr = code(body(self.text, "LearnFileReplace"))

    def test_checks_append_before_move(self):
        a = self.fr.find("V1Do(FileAppend, out, path \".tmp\")")
        mv = self.fr.find("V1Do(FileMove, path \".tmp\", path, 1)")
        self.assertGreater(a, -1)
        self.assertGreater(mv, a)
        self.assertIn("failed := V1Do(FileAppend", self.fr)
        self.assertIn("FileGetSize(path \".tmp\") < StrLen(out)", self.fr)
        between = self.fr[a:mv]
        self.assertIn("if (!failed)", between)

    def test_tmp_deleted_on_failure(self):
        tail = self.fr[self.fr.find("V1Do(FileMove"):]
        self.assertRegex(tail, r"if \(failed\)\n\t\tV1Do\(FileDelete, path \"\.tmp\"\)")
        self.assertIn("return !failed", tail)

    def test_save_and_written_use_it(self):
        for name in ("LearnSave", "LearnWritten"):
            b = code(body(self.text, name))
            self.assertIn("LearnFileReplace(", b, name)
            self.assertNotIn("V1Do(FileMove", b, name + " moves a .tmp itself")
            self.assertNotIn("V1Do(FileAppend", b, name + " appends itself")


class LoadFailed(unittest.TestCase):
    def setUp(self):
        self.text = read()

    def test_declared_and_blank(self):
        self.assertRegex(self.text, r"(?m)^global LearnLoadFailed\b")
        blank = body(self.text, "CardLearnBlank")
        self.assertIn("LearnLoadFailed := \"\"", blank)

    def test_load_marks_failed_read(self):
        b = code(body(self.text, "LearnLoad"))
        self.assertIn("global LearnedCards, LearnLoadFailed", b)
        self.assertIn("failed := ErrorLevel", b)
        self.assertIn("if (failed && FileExist(path))", b)
        fail = b[b.find("if (failed && FileExist(path))"):b.find("LearnLoadFailed := 0")]
        self.assertIn("LearnedCards := [], LearnLoadFailed := 1", fail)
        self.assertIn("return", fail)
        self.assertIn("DebugLog(", fail)
        # a catalog read before kept on a failed reload
        self.assertIn("if (IsObject(LearnedCards) && !LearnLoadFailed)", fail)
        # the catalog emptied only after a good read (or a file that isn't there)
        self.assertLess(b.find("LearnLoadFailed := 0"), b.find("Loop Parse, text"))

    def test_nothing_written_or_learned_while_failed(self):
        for name in ("LearnSave", "LearnNew", "LearnBoostPicFix"):
            b = code(body(self.text, name))
            self.assertIn("if (LearnLoadFailed)", b, name)
        save = code(body(self.text, "LearnSave"))
        self.assertLess(save.find("if (LearnLoadFailed)"), save.find("LearnFileReplace("))
        new = code(body(self.text, "LearnNew"))
        self.assertLess(new.find("if (LearnLoadFailed)"), new.find("LearnedCards.Push"))

    def test_read_again(self):
        cards = code(body(self.text, "LearnCards"))
        self.assertIn("if (!IsObject(LearnedCards) || LearnLoadFailed)\n\t\tLearnLoad()", cards)
        oob = code(body(self.text, "LearnOutOfBattle"))
        self.assertIn("if (LearnLoadFailed)\n\t\tLearnLoad()", oob)
        self.assertLess(oob.find("LearnLoad()"), oob.find("if (!LearnRunDone.Has(\"load\"))"))

    def test_recovery_rearms_run_jobs(self):
        # review 2 (1.1/2.1): the once-a-run jobs done again whichever read recovers - LearnCards', the Spells tab's
        # or LearnOutOfBattle's - so it's LearnLoad's own recovery branch that clears them
        b = code(body(self.text, "LearnLoad"))
        rec = b[b.find("if (failed && FileExist(path))"):]
        rec = rec[rec.find("\n\tif (LearnLoadFailed)"):rec.find("LearnLoadFailed := 0")]
        self.assertIn("if (IsObject(LearnRunDone))", rec)
        self.assertIn("LearnRunDone.Delete(\"load\"), LearnRunDone.Delete(\"check\")", rec)

    def test_load_says_whether_read(self):
        # review 2 (2.2): 0 when the file couldn't be read (kept or stand-in), 1 when read - for the Spells tab's note
        b = code(body(self.text, "LearnLoad"))
        fail = b[b.find("if (failed && FileExist(path))"):b.find("LearnLoadFailed := 0")]
        self.assertEqual(fail.count("return 0"), 2)
        self.assertNotRegex(fail, r"return\n")
        self.assertTrue(b.rstrip().endswith("return 1\n\t}"))

    def test_crlf(self):
        with open(CARDLEARN, "rb") as fh:
            raw = fh.read()
        self.assertEqual(raw.count(b"\n"), raw.count(b"\r\n"))


if __name__ == "__main__":
    unittest.main()
