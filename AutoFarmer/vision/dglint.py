"""dglint.py - checks a dungeon run's file (AutoFarmer\\dungeons\\<name>.txt - the Dungeons tab's Record a run) before it's
walked again and again: read the way Dungeons.ahk's DgLoad reads it (the same lines kept, the same ones skipped), then
what the replay would trip on - a run that doesn't end where it starts, a zone change after a battle step (no doorway to
walk through), a walk step recorded right after a sigil's X (before v1.0.0 the replay walked on past it - off the sigil,
which stops its countdown), a coordinate that isn't a number - and the run's own optional lines (v1.0.0): slots| (the
gear slots the dungeon drops), stopafter| (dry runs before its gear counts as done), next| (the run to go on to once it
is), boss|<name>|<deck id> (the deck for a boss by name), untilgear| (repeat it until its gear is swapped). Older bot
versions skip those lines (DgLoad keeps only name|, deck| and the steps). Pure Python, nothing read from the game.

    run = parse_run(text, "Waterworks")            # {name, deck, steps [{kind, zone, x, y, z, line}], slots, ...}
    issues = lint(run, runs={"Darkmoor"}, decks={"large"}, cat=gearrank.catalogue(known))   # [(level, step, text)]
    print("\\n".join(lint_lines(run, issues)))
    zone_choice(run["steps"], i, zone, (x, y))     # Dungeons.ahk DungeonStep's rule when the wizard turns up in another
                                                   # zone: ("resume" / "ahead" / "stop", step) - kept the same as it

    python dglint.py [file or folder ...] [--decks <folder>] [--known <dungeons_known.txt>] [--out lint.txt]
                     (no file: AutoFarmer\\dungeons; decks: AutoFarmer\\decks; known: resources\\dungeons_known.txt)

The answer, one line each (| between fields):
    run|name|steps|zones|x presses|battles|start zone|end zone|away (from the start)|file
    gear|slots|stopafter|next|untilgear|bosses (name~deck,...)
    error|step (0 the file)|text      (DgLoad refuses it, or a step the replay can't walk)
    warn|step|text                    (it walks, but likely not as you meant)
    ok|errors|warnings
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import gearrank as G                 # noqa: E402 - pure (slots, the catalogue)

STEP_KINDS = ("walk", "x", "fight")  # (DgLoad's RegExMatch "^(walk|x|fight)$" - case-sensitive)
END_NEAR = 400                       # a run ends back where it began within this (DgRecordStop's warning)
X_DRIFT = 100                        # a walk step this near the X before it, into another zone: a sigil's drift
WALK_GAP = 2500                      # two walk steps in a zone further apart than this: a jump (a teleport?) - said


def _num(s):
    """AutoHotkey's V1Add(s, 0): a number (int or float) when s is one, else None (DgLoad's blank)"""
    s = (s or "").strip()
    if re.fullmatch(r"[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?|0[xX][0-9a-fA-F]+", s):
        return int(s, 16) if s.lower().startswith(("0x", "+0x", "-0x")) else float(s)
    return None


def parse_run(text, name=""):
    """a run file's text as DgLoad reads it: {name, deck, steps [{kind, zone, x, y, z, line}], slots [..], slots_raw,
    stopafter, stopafter_raw, next, untilgear, bosses [(name, deck)], skipped [(line no, text)] - lines DgLoad drops,
    unnumbered [{kind, zone, x, y, z, line}] - steps with a coordinate that isn't a number, which DgLoad leaves out too
    (not in steps: their numbering and the stats are the steps the bot walks)}. name: the file's own name (DgLoad's
    when there's no name| line)"""
    run = {"name": "", "deck": "", "steps": [], "slots": [], "slots_raw": "", "stopafter": None, "stopafter_raw": "",
           "next": "", "untilgear": 0, "bosses": [], "skipped": [], "unnumbered": [], "file_name": name}
    for no, raw in enumerate((text or "").splitlines(), 1):
        line = raw.strip(" \t")
        if line == "" or line.startswith(";"):
            continue
        f = line.split("|")
        key = f[0].lower()                          # (AutoHotkey's = isn't case-sensitive)
        val = f[1] if len(f) > 1 else ""
        if key == "name":
            run["name"] = val
        elif key == "deck":
            run["deck"] = re.sub(r"[^A-Za-z0-9_-]", "", val)
        elif key == "slots":
            run["slots_raw"], run["slots"] = val, G.parse_slots(val)
        elif key == "stopafter":
            run["stopafter_raw"] = val.strip()
            run["stopafter"] = int(val) if re.fullmatch(r"\s*\d{1,5}\s*", val) else None
        elif key == "next":
            run["next"] = val.strip()
        elif key == "untilgear":
            run["untilgear"] = 1 if val.strip() == "1" else 0
        elif key == "boss":
            if val.strip():
                run["bosses"].append((val.strip(), re.sub(r"[^A-Za-z0-9_-]", "", f[2] if len(f) > 2 else "")))
        elif f[0] in STEP_KINDS and len(f) >= 5 and (f[2] + f[3] + f[4]) != "":
            step = {"kind": f[0], "zone": f[1], "x": _num(f[2]), "y": _num(f[3]), "z": _num(f[4]), "line": no}
            run["steps" if None not in (step["x"], step["y"], step["z"]) else "unnumbered"].append(step)
        else:
            run["skipped"].append((no, line))
    if run["name"] == "":
        run["name"] = os.path.splitext(os.path.basename(name or ""))[0]
    return run


def _d(a, b):
    """the distance across (x, y) of two steps - None when a coordinate isn't a number"""
    if None in (a["x"], a["y"], b["x"], b["y"]):
        return None
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def nearest_first_visit(steps, zone, pos):
    """Dungeons.ahk DgNearest: the step (1...) of zone's FIRST visit - steps in a row there - nearest pos (x, y); 1 when
    that's step 1 and it's within 300 (the start); 0 when no step is in zone"""
    best, best_d, in_block = 0, None, False
    for i, s in enumerate(steps, 1):
        if s["zone"] != zone:
            if in_block:
                break
            continue
        in_block = True
        d = math.hypot((s["x"] or 0) - pos[0], (s["y"] or 0) - pos[1])
        if i == 1 and d < 300:
            return 1
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best


def zone_choice(steps, i, zone, pos, from_zone="", resumes=0):
    """Dungeons.ahk DungeonStep's rule (kept the same - this is it in Python, tested) when the wizard is in zone, not
    the zone of step i (1... - the step walked to), and not waiting for a load out of from_zone: ("resume", k) - an
    EARLIER zone of the run (its first visit before step i: a defeat's respawn, a potion run's Recall back): on from k,
    that first visit's step nearest pos (nearest_first_visit), 3 times a run (resumes: so far - a fourth: ("stop", k));
    ("ahead", k) - a zone the run hasn't been in yet: on from its first step after i (DgZoneAhead); ("stop", 0) none.
    An earlier zone is looked at first: the recorder's "walk back out to where you started" brings the start zone, and
    often the inner ones, again on the way back - jumping to that later step would walk out and count a run whose boss
    wasn't beaten"""
    k = nearest_first_visit(steps, zone, pos)
    if k and k < i:
        return ("resume", k) if resumes < 3 else ("stop", k)
    ahead = next((j for j in range(i + 1, len(steps) + 1) if steps[j - 1]["zone"] == zone), 0)
    if ahead and zone != from_zone:
        return "ahead", ahead
    return "stop", 0


def stats(run):
    """{steps, zones, x, fights, start, end, away} of a parsed run"""
    st = run["steps"]
    zones = []
    for s in st:
        if s["zone"] not in zones:
            zones.append(s["zone"])
    return {"steps": len(st), "zones": len(zones), "x": sum(s["kind"] == "x" for s in st),
            "fights": sum(s["kind"] == "fight" for s in st), "start": st[0]["zone"] if st else "",
            "end": st[-1]["zone"] if st else "", "away": _d(st[0], st[-1]) if len(st) >= 2 else None}


def lint(run, runs=None, decks=None, cat=None):
    """[(level "error" / "warn", step number (1...; 0 the file), text)] of a parsed run. runs: the other runs' names (a
    next| line checked against them - None: not checked); decks: the deck ids there are (deck| and boss| lines checked -
    None: not checked); cat: gearrank.catalogue's (a run of a known dungeon with no slots| line: its slots said)"""
    out = []
    st = run["steps"]
    if len(st) < 2:
        out.append(("error", 0, "%d step(s) - Dungeons.ahk needs at least two to run it" % len(st)))
    # (left out by DgLoad - not walked: said by its line, step 0)
    for s in run.get("unnumbered") or []:
        out.append(("error", 0, "line %d: a coordinate isn't a number (%s step in %s) - Dungeons.ahk leaves the step out"
                    % (s["line"], s["kind"], s["zone"] or "?")))
    for i, s in enumerate(st, 1):
        if None in (s["x"], s["y"], s["z"]):
            out.append(("error", i, "line %d: a coordinate isn't a number (%s step in %s)" % (s["line"], s["kind"],
                                                                                         s["zone"] or "?")))
        if not s["zone"]:
            out.append(("warn", i, "line %d: no zone - it never matches where the wizard is" % s["line"]))
    if len(st) >= 2:
        a, b = st[0], st[-1]
        away = _d(a, b)
        if a["zone"] != b["zone"]:
            out.append(("warn", len(st), "it ends in %s, not where it starts (%s): a run that starts over should end back "
                                         "where it began - and no gear pass or quick sell between runs then" %
                        (b["zone"], a["zone"])))
        elif away is not None and away > END_NEAR:
            out.append(("warn", len(st), "it ends %d away from where it starts (more than %d): no gear pass or quick sell "
                                         "between runs" % (away, END_NEAR)))
    for i in range(1, len(st)):
        prev, cur = st[i - 1], st[i]
        if cur["zone"] == prev["zone"]:
            if prev["kind"] == "walk" and cur["kind"] == "walk":
                d = _d(prev, cur)
                if d is not None and d > WALK_GAP:
                    out.append(("warn", i + 1, "%d from the step before in the same zone - a teleport or a jump the "
                                               "route can't walk?" % d))
            continue
        # (a zone change: after an X (a sigil, a door you X) or a walk (a doorway walked through))
        if prev["kind"] == "fight":
            out.append(("warn", i, "a zone change right after a battle step (%s -> %s): the replay waits 8 s there, then "
                                   "looks for %s with no doorway to walk through" % (prev["zone"], cur["zone"], cur["zone"])))
        elif prev["kind"] == "walk" and i >= 2 and st[i - 2]["kind"] == "x" and st[i - 2]["zone"] == prev["zone"]:
            d = _d(st[i - 2], prev)
            if d is not None and d <= X_DRIFT:
                out.append(("warn", i, "a walk step %d from the X before it, into %s: the wizard drifted at a sigil while "
                                       "recording - since v1.0.0 the replay waits for the load there (older versions walked "
                                       "on past it, off the sigil)" % (d, cur["zone"])))
    if run["slots_raw"] and not run["slots"]:
        out.append(("warn", 0, "slots|%s - none of them is a slot (%s)" % (run["slots_raw"], ", ".join(G.SLOTS))))
    if run["stopafter_raw"] and run["stopafter"] is None:
        out.append(("warn", 0, "stopafter|%s isn't a number of runs" % run["stopafter_raw"]))
    if run["untilgear"] and not run["slots"]:
        d = G.catalogue_for(run["name"], cat) if cat else None
        if d and d["slots"]:
            out.append(("warn", 0, "until its gear is swapped, no slots| line: the catalogue's %s ones go (%s)" %
                        (d["name"], ", ".join(d["slots"]))))
        else:
            out.append(("warn", 0, "until its gear is swapped, no slots| line and not in the catalogue: only the dry runs "
                                   "end it"))
    if runs is not None and run["next"] and run["next"].lower() not in {r.lower() for r in runs}:
        out.append(("warn", 0, "next|%s - no run of that name in the folder" % run["next"]))
    if decks is not None:
        have = {d.lower() for d in decks}
        if run["deck"] and run["deck"].lower() not in have:
            out.append(("warn", 0, "deck|%s - no deck of that id (decks\\%s.txt)" % (run["deck"], run["deck"])))
        for nm, dk in run["bosses"]:
            if not dk:
                out.append(("warn", 0, "boss|%s - no deck id after the name" % nm))
            elif dk.lower() not in have:
                out.append(("warn", 0, "boss|%s|%s - no deck of that id" % (nm, dk)))
    for no, text in run["skipped"][:10]:
        out.append(("warn", 0, "line %d skipped (not a step DgLoad reads): %s" % (no, text[:80])))
    return out


def lint_lines(run, issues, path=""):
    """the answer's lines (the docstring) for one run"""
    s = stats(run)
    cell = G.cell
    out = ["|".join(["run", cell(run["name"]), str(s["steps"]), str(s["zones"]), str(s["x"]), str(s["fights"]),
                     cell(s["start"]), cell(s["end"]), "" if s["away"] is None else "%d" % s["away"], cell(path)]),
           "|".join(["gear", ",".join(run["slots"]), cell(run["stopafter"]), cell(run["next"]), str(run["untilgear"]),
                     ",".join("%s~%s" % b for b in run["bosses"])])]
    for level, step, text in issues:
        out.append("|".join([level, str(step), cell(text)]))
    out.append("ok|%d|%d" % (sum(1 for x in issues if x[0] == "error"), sum(1 for x in issues if x[0] == "warn")))
    return out


def _read(path):
    """a file's text: UTF-8, else the ANSI code page's bytes as Latin-1 (FileAppend wrote it in the ANSI code page)"""
    with open(path, "rb") as f:
        data = f.read()
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def _main(argv=None):
    import argparse
    af = os.path.dirname(HERE)
    ap = argparse.ArgumentParser(description="checks dungeon run files (AutoFarmer\\dungeons\\*.txt) - nothing in the "
                                             "game is read")
    ap.add_argument("paths", nargs="*", help="run files or folders (none: AutoFarmer\\dungeons)")
    ap.add_argument("--decks", default=os.path.join(af, "decks"), help="the decks folder (deck ids checked)")
    ap.add_argument("--known", default=os.path.join(af, "resources", "dungeons_known.txt"), help="the catalogue")
    ap.add_argument("--out", default="", help="also write the answer to this file")
    a = ap.parse_args(argv)
    paths = a.paths or [os.path.join(af, "dungeons")]
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(os.path.join(p, n) for n in os.listdir(p) if n.lower().endswith(".txt"))
        elif os.path.isfile(p):
            files.append(p)
        else:
            print("none|%s isn't a file or a folder" % p)
    decks = None
    if os.path.isdir(a.decks):
        decks = {os.path.splitext(n)[0] for n in os.listdir(a.decks) if n.lower().endswith(".txt")}
    cat = []
    if os.path.isfile(a.known):
        cat = G.catalogue(_read(a.known))
    parsed = [(f, parse_run(_read(f), os.path.basename(f))) for f in files]
    names = {r["name"] for _f, r in parsed}
    lines = []
    for f, run in parsed:
        lines += lint_lines(run, lint(run, names, decks, cat), f)
    if not parsed:
        lines.append("none|no run files (record one on the Dungeons tab)")
    print("\n".join(lines))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    return 1 if any(ln.startswith("error|") for ln in lines) else 0


if __name__ == "__main__":
    sys.exit(_main())
