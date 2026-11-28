"""test_fix_stats.py - StatsRead.ahk's StatsCharID reads the game's log from its end, not all of it. Standard library only:
python -m unittest test_fix_stats  (from AutoFarmer\\vision)

WizardClient.261124_0018.log got to 2,146,435,246 bytes in one session (texture error spam, about 70 MB an hour), and
StatsCharID read the whole of it every 20 s - from PartyTick and NetTick too - stopping every thread for seconds. Pins:
no whole-file read; the log opened and read a MB at a time backwards, with overlap; an unchanged log not read again; a
new log (time stamp on its first line, or shorter) looked through afresh; at most 256 MB a look - and when that runs
out before a login line turns up (the bot started hours into a one-zone spam session, its only login line 2 GB back),
the looks after carry on further down, so the id still turns up, not "" for the rest of the session. And a Python copy
of the scan gives the same id as searching the whole text, at every size the log grows through (with the 256 MB cap
made small, once it has got all the way down)."""
import os
import random
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "MSG_LoginComplete CharID:"


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def whole(text):
    """What the old StatsCharID gave: the last login line in all of it, and the id after it"""
    at = text.lower().rfind(MARK.lower())
    if at < 0:
        return ""
    m = re.search(r"CharID:(\d+)", text[at:at + 80], re.I)
    return m.group(1) if m else ""


class Scan:
    """StatsCharID and StatsLoginScan, by the same steps (the chunk and the cap smaller here, to cross their edges often)"""
    def __init__(self, chunk, cap=268435456):
        self.chunk, self.cap = chunk, cap
        self.now, self.was, self.down, self.floor, self.fresh = "", 0, 0, 0, True

    def pending(self):
        return self.down > self.floor

    def login_scan(self, text, read_to, floor_at, got):
        while read_to > floor_at and got[0] < self.cap:
            read_from = max(floor_at, read_to - self.chunk)
            c = text[read_from:read_to]
            got[0] += read_to - read_from
            at = c.lower().rfind(MARK.lower())
            if at >= 0:
                m = re.search(r"CharID:(\d+)", c[at:at + 80], re.I)
                return True, (m.group(1) if m else ""), None
            read_to = read_from + 120 if read_from > floor_at else floor_at
        return False, "", read_to

    def look(self, text):
        size = len(text)
        if self.fresh or size < self.was:
            self.now, self.was, self.down, self.floor, self.fresh = "", 0, 0, 0, False
        elif size == self.was and not self.pending():
            return self.now
        floor_at = self.was - 120 if self.was > 120 else 0
        got = [0]
        hit, cid, down_to = self.login_scan(text, size, floor_at, got)
        if hit:
            self.now, self.down, self.floor = cid, 0, 0
        elif down_to > floor_at:
            if not self.pending():
                self.floor = floor_at
            self.down = down_to
        elif self.pending():
            hit, cid, down_to = self.login_scan(text, self.down, self.floor, got)
            if hit:
                self.now, self.down, self.floor = cid, 0, 0
            else:
                self.down = down_to
        self.was = size
        return self.now


def random_log(rnd, lines=30):
    parts = []
    for i in range(rnd.randint(0, lines)):
        r = rnd.random()
        if r < 0.15:
            parts.append("x MSG_LoginComplete CharID:%d More\n" % rnd.randint(1, 10 ** 12))
        elif r < 0.18:
            parts.append("MSG_LoginComplete CharID:abc\n")
        else:
            parts.append("".join(rnd.choice("ab \nCD:") for _ in range(rnd.randint(1, 400))))
    return "".join(parts)


class StatsCharIdTail(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = read("..", "StatsRead.ahk")
        m = re.search(r"\nStatsCharID\(again := false\)\n\t\{\n(.*?)\n\t\}\n", src, re.S)
        assert m, "StatsCharID not found"
        cls.body = m.group(1)
        m = re.search(r"\nStatsLoginScan\(logFile, readTo, floorAt, &readSum, &id, &downTo\)\n\t\{\n(.*?)\n\t\}\n", src, re.S)
        assert m, "StatsLoginScan not found"
        cls.scan = m.group(1)

    def test_no_whole_file_read(self):
        for body in (self.body, self.scan):
            self.assertNotIn("V1FileRead", body)
            self.assertNotIn("FileRead(", body)
        self.assertIn('logFile := FileOpen(logPath, "r", "CP0")', self.body)
        self.assertIn("logFile.Close()", self.body)

    def test_backwards_a_mb_at_a_time(self):
        self.assertIn("while (readTo > floorAt && readSum < 268435456)", self.scan)
        self.assertIn("readFrom := Max(floorAt, readTo - 1048576)", self.scan)
        self.assertIn("logFile.Pos := readFrom", self.scan)
        self.assertIn("chunk := logFile.Read(readTo - readFrom)", self.scan)
        self.assertIn("readSum += readTo - readFrom", self.scan)
        self.assertIn('InStr(chunk, "MSG_LoginComplete CharID:", false, -1)', self.scan)
        self.assertIn("readTo := readFrom > floorAt ? readFrom + 120 : floorAt", self.scan)
        self.assertIn("downTo := readTo", self.scan)

    def test_unchanged_or_new_log(self):
        self.assertIn("if (!again && readAt && A_TickCount - readAt < 20000)", self.body)
        self.assertIn("logHead := logFile.Read(17)", self.body)
        self.assertIn("if (logPath != logWas || logHead != headWas || logSize < sizeWas)", self.body)
        self.assertIn("else if (logSize = sizeWas && scanDown <= scanFloor)", self.body)
        # (set before the scan: a log with nothing in it doesn't read them unset after)
        self.assertIn('floorAt := sizeWas > 120 ? sizeWas - 120 : 0, readSum := 0, id := "", downTo := 0', self.body)

    def test_cap_carries_on_further_down(self):
        # The growth first, then what the cap left (one readSum for both, so a look stays at 256 MB); a new log's part
        # still to do starts at its floor, and is only dropped once a login line turns up or it's all been read
        self.assertIn("static charNow := \"\", readAt := 0, logWas := \"\", headWas := \"\", sizeWas := 0, scanDown := 0, scanFloor := 0", self.body)
        self.assertIn("if (StatsLoginScan(logFile, logSize, floorAt, &readSum, &id, &downTo))", self.body)
        self.assertIn("else if (downTo > floorAt)", self.body)
        self.assertIn("if (scanDown <= scanFloor)\n\t\t\tscanFloor := floorAt\n\t\tscanDown := downTo", self.body)
        self.assertIn("else if (scanDown > scanFloor)", self.body)
        self.assertIn("if (StatsLoginScan(logFile, scanDown, scanFloor, &readSum, &id, &downTo))", self.body)
        self.assertEqual(self.body.count("charNow := id, scanDown := 0, scanFloor := 0"), 2)
        self.assertIn("scanDown := downTo  ;", self.body)
        self.assertNotIn("sizeWas := logSize\n\treturn charNow", self.scan)
        self.assertTrue(self.body.rstrip().endswith("logFile.Close()\n\tsizeWas := logSize\n\treturn charNow"))

    def test_same_id_as_the_whole_log(self):
        rnd = random.Random(7)
        for trial in range(1500):
            full, scan, pos = random_log(rnd), Scan(rnd.choice([150, 200, 300, 1000])), 0
            while True:
                pos = min(len(full), pos + rnd.randint(0, 500))
                self.assertEqual(scan.look(full[:pos]), whole(full[:pos]), (trial, pos))
                self.assertFalse(scan.pending(), (trial, pos))
                if pos == len(full):
                    break

    def test_capped_scan_finds_it_later(self):
        # The cap made small: while there's still a part to look through, a new log's id is "" (or the one a newer login
        # line gave), and once it's all been read it's what the whole-log search gives - never "" for good by mistake
        rnd = random.Random(11)
        for trial in range(1500):
            chunk = rnd.choice([300, 500, 1000])
            full, scan, pos = random_log(rnd, 60), Scan(chunk, rnd.choice([chunk, 2 * chunk, 4000])), 0
            # (the log already well grown when the bot starts, sometimes - the case the cap is about)
            if rnd.random() < 0.5:
                pos = rnd.randint(0, len(full))
            while True:
                got = scan.look(full[:pos])
                if not scan.pending():
                    self.assertEqual(got, whole(full[:pos]), (trial, pos))
                if pos == len(full):
                    break
                pos = min(len(full), pos + rnd.randint(0, 300))
            for i in range(len(full) // 100 + 5):
                if not scan.pending():
                    break
                scan.look(full)
            self.assertFalse(scan.pending(), trial)
            self.assertEqual(scan.look(full), whole(full), trial)

    def test_two_gb_log_after_a_restart(self):
        # WizardClient.261124_0018.log by the numbers, a MB made 10,000 bytes (a MB a chunk, 256 a look): its only login
        # line at 22.6 MB of 2,146 - the first look finds nothing, and the looks after go on down to it, 9 looks in all
        mb = "-" * 10000
        full = mb * 22 + "x MSG_LoginComplete CharID:191965897236120345 More\n" + mb * 2124
        scan, looks = Scan(10000, 2560000), 1
        self.assertEqual(scan.look(full), "")
        self.assertTrue(scan.pending())
        while scan.pending():
            got, looks = scan.look(full), looks + 1
        self.assertEqual(got, "191965897236120345")
        self.assertLessEqual(looks, 9)




class StatsCharKept(unittest.TestCase):
    """A found character id kept for the next run (stats_char.ini), reused only for the same log, no shorter since"""

    def test_saved_and_reused(self):
        src = read("..", "StatsRead.ahk").replace("\r\n", "\n")
        # (found: a newer login line, no save yet - saved once nothing older is left to look through)
        self.assertEqual(2, src.count("charNow := id, scanDown := 0, scanFloor := 0, newer := true"))
        # (the saved id pending, not returned, till what was added since it was found is all looked through)
        self.assertIn("if (StatsCharSaved(logPath, logHead, logSize, &svId, &svSize))\n\t\t\tsvPend := svId, sizeWas := svSize", src)
        self.assertIn("else if (scanDown <= scanFloor)\n\t\t\tcharNow := svPend, svPend := \"\"", src)
        self.assertIn("if (charNow != \"\" && scanDown <= scanFloor && (charNow != svSavedId || logSize - svSavedSize >= 33554432))", src)
        self.assertNotIn("charNow := svId", src)
        body = re.search(r"\nStatsCharSaved\(logPath, logHead, logSize, &id, &size\)\n\t\{\n(.*?)\n\t\}\n", src, re.S).group(1)
        self.assertIn('IniRead(f, "log", "path", "") != logPath', body)
        self.assertIn('StatsIniSafe(logHead)', body)
        self.assertIn('size + 0 <= logSize', body)
        self.assertIn('AutoFarmer/stats_char.ini', open(os.path.join(os.path.dirname(__file__), "..", "..", ".gitignore"), encoding="utf-8").read())


if __name__ == "__main__":
    unittest.main()
