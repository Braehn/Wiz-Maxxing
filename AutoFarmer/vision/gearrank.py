"""gearrank.py - the GEAR MODEL (TODO goal 5, "gear dungeons until all gear is swapped"): an item's equip effects as stats,
whether the wizard may wear it, how good the wizard's totals are for its battle role, the best swap a slot (the plan),
and a dungeon run's drop log with its "done" check. Pure Python (numpy not needed): it reads nothing from the game
itself - the vision helper hands it what gearmem.py read (vision.py /gear) - and writes only the drop log
(AutoFarmer\\learned\\drops\\, DropBook).

    stats, unknown, index = item_stats(item["effects"])   # gearmem's effects -> {"damage.fire": 12, "health": 300...}
    ok, why = meets_reqs(item["reqs"], level=120, school="fire")      # True / False / None (not known) and why
    s = score(totals, "hitter", "fire")                    # log-points: a +0.05 change is about 5 % better
    r = swap_plan(worn, bag, totals, school="fire", level=120, role="hitter", margin=2.0)
                                                           # {plan, judged, notes}: one best piece a slot, why
    book = DropBook(folder)                                # learned\\drops: <run>.txt (drops), <run>.state (an .ini)
    book.mark(run, reading, when)                          # the backpack's ids at a run's start
    out = book.run_end(run, reading, plan, slots, stopafter, when)   # this run's drops logged, dry runs, done?
                                                           # (marked=False: its start wasn't noted - not counted)

    python gearrank.py --demo                              # a made-up wizard and backpack through swap_plan

NOT CONFIRMED IN THE GAME YET. The names and meaning of the gear's reflected properties are the community's (wiztype /
wizwalker dumps): StatisticEffectInfo's stat name (m_effectName: "CanonicalFireDamage") and its number - which may be an
index into a table looked up by the item's level (m_lookupIndex: bossmem.py saw that on mobs - "its number isn't here")
rather than the value. A number read is taken as the value only from a property named like one (VALUE_PROPS); an index
is kept as one ("#3" on /gear) and the stat's size is then NOT KNOWN - never guessed: such an item is compared by its
level requirement instead (basis "level"), else not at all (verdict "unknown"). Every delta is ADVICE - Gear.ahk logs it,
equips nothing (gearswap is a rehearsal), and holds the quick sell while a backpack piece looks better.

THE SCORE (one number for the wizard's totals; a swap's delta = the new totals' score less the old - in log-points: x100
is about the % it's better). The totals are the wizard's own (PlayerStats.txt's school stats - the worn gear in them) with
the worn piece's stats taken off and the candidate's added (baseline: a total not sent at least the worn piece's own;
health not sent - not counted). offence = the damage curve (battlesim.damage_multiplier) x
the hit chance (the school's own accuracy + accuracy, at most 100 %) x a critical's worth on average (crit_chance /
crit_mult against ENEMY_BLOCK) x what's left of ENEMY_RESIST after pierce; defence = health / (1 - resist) x incoming
healing; pips = 1 + half the power-pip chance + 0.1 a starting pip; healing = 1 + outgoing healing %. Each by its log, the
role's weights (ROLE_WEIGHTS - hitter, healer, blader; PlayerStats gearweight.off:1, gearweight.def:0.5... override), item cards
a small bonus each.
"""
import math
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import battlesim as B                # noqa: E402 - pure (the damage curve, the crit model, the schools' accuracy)

# the slots a plan may swap - never a deck, a pet or a mount (they're the deck profiles' and the Equipment Sets')
SLOTS = ("hat", "robe", "shoes", "weapon", "athame", "amulet", "ring")
NEVER = ("deck", "pet", "mount")
# an item's slot from its template's adjectives, the first it has (bagmem.KINDS' order and names)
SLOT_ADJ = (("Deck", "deck"), ("Hat", "hat"), ("Robe", "robe"), ("Shoes", "shoes"), ("Weapon", "weapon"),
            ("Athame", "athame"), ("Amulet", "amulet"), ("Ring", "ring"), ("Pet", "pet"), ("Mount", "mount"))
SCHOOLS = B.SCHOOLS
STAT_SCHOOLS = SCHOOLS + ("all", "shadow")
# a stat's kind from what follows its school in its name ("CanonicalFire" + "Damage"), the longest match first - names
# not here are kept as raw.<name> (shown, never scored)
STAT_KINDS = (("reducedamage", "resist"), ("flatreducedamage", "flatresist"), ("flatdamage", "flatdamage"),
              ("armorpiercing", "pierce"), ("piercing", "pierce"), ("criticalhit", "critical"), ("critical", "critical"),
              ("block", "block"), ("accuracy", "accuracy"), ("damage", "damage"), ("healing", "outheal"),
              ("incominghealing", "incheal"), ("incheal", "incheal"), ("inchealing", "incheal"),
              ("outgoinghealing", "outheal"), ("pipconversion", "pipconvert"), ("pipconversionrating", "pipconvert"),
              ("maxhealth", "health"), ("health", "health"), ("maxhitpoints", "health"), ("hitpoints", "health"),
              ("maxmana", "mana"), ("mana", "mana"), ("powerpip", "powerpip"), ("powerpipchance", "powerpip"),
              ("shadowpip", "shadowpip"), ("shadowpiprating", "shadowpip"), ("stunresistance", "stunresist"),
              ("stunresist", "stunresist"), ("archmastery", "archmastery"), ("fishingluck", "fishing"),
              ("maxenergy", "energy"), ("energy", "energy"))
SCHOOLED = ("damage", "resist", "flatdamage", "flatresist", "pierce", "critical", "block", "accuracy", "outheal",
            "pipconvert")
# a StatisticEffectInfo's name and number by property name (the first one the effect has); m_lookupIndex is an index
STAT_NAME_PROPS = ("m_effectName", "m_statName", "m_sStatName", "m_statisticName", "m_name")
VALUE_PROPS = ("m_value", "m_fValue", "m_nValue", "m_amount", "m_statValue", "m_bonus", "m_numericValue")
INDEX_PROPS = ("m_lookupIndex", "m_index", "m_statIndex")
PIP_PROPS = (("m_pipsGiven", "pips"), ("m_powerPipsGiven", "powerpips"), ("m_shadowPipsGiven", "shadowpips"))
SPEED_PROPS = ("m_speedMultiplier", "m_speed", "m_speedPercent")
CARD_PROPS = ("m_numSpells", "m_count")
LEVEL_PROPS = ("m_numericValue", "m_level", "m_magicLevel", "m_value")
SCHOOL_PROPS = ("m_magicSchool", "m_schoolName", "m_school", "m_sSchool")

ENEMY_RESIST = B.ENEMY_RESIST        # % an enemy resists the wizard's hits (the bot's enemyresist default)
ENEMY_BLOCK = 200                    # an enemy's block rating (a guess for the crit's worth - gearweight.eblock:N)
RESIST_CAP = 90
ROLE_WEIGHTS = {"hitter": {"off": 1.0, "def": 0.5, "pip": 0.3, "heal": 0.0, "cards": 0.002},
                "healer": {"off": 0.1, "def": 0.8, "pip": 0.3, "heal": 1.0, "cards": 0.002},
                "blader": {"off": 0.3, "def": 0.8, "pip": 0.6, "heal": 0.1, "cards": 0.002}}
MARGIN = 2.0                         # % a piece must be better by to be planned (PlayerStats gearmargin)
STOPAFTER = 30                       # dry runs (no upgrade dropped) before a dungeon's gear counts as done
TOTAL_KEYS = ("damage", "pierce", "crit", "block", "acc", "resist", "hp", "pp", "pips", "heal", "incheal", "cards")


# ============================================================================ an item's stats
def slot_of(adjs):
    """an item's slot ("hat", "deck"...) from its template's adjectives, "" none of them, None not read"""
    if adjs is None:
        return None
    have = set(adjs)
    return next((slot for adj, slot in SLOT_ADJ if adj in have), "")


def item_slot(it):
    """an item's slot: its own slot field, else its adjectives' (slot_of) - "" read and not a slot's, None NOT READ (gearmem:
    its template or adjective list couldn't be read - judged "unknown", never taken for "not gear" or an empty slot)"""
    s = (it or {}).get("slot")
    if s:
        return s
    a = slot_of((it or {}).get("adjs"))
    return a if a is not None else ("" if s == "" else None)


def parse_stat(name):
    """(kind, school) of a stat's name: "CanonicalFireDamage" -> ("damage", "fire"), "CanonicalAllReduceDamage" ->
    ("resist", "all"), "CanonicalMaxHealth" -> ("health", ""); one it doesn't know -> ("raw", name); None -> ("raw", "")"""
    if not name:
        return "raw", ""
    s = re.sub(r"[^a-z]", "", str(name).lower())
    s = re.sub(r"^(canonical|statistic|stat)", "", s)
    kinds = dict(STAT_KINDS)
    # (the whole name first - "ShadowPipRating" isn't Shadow's PipRating -, then a school's own: "Fire" + "Damage")
    if s in kinds:
        return kinds[s], "all" if kinds[s] in SCHOOLED else ""
    for sch in STAT_SCHOOLS:
        rest = s[len(sch):]
        if s.startswith(sch) and rest in kinds:
            kind = kinds[rest]
            if kind in SCHOOLED:
                return kind, sch
            return kind, "" if sch == "all" else sch
    return "raw", str(name)


def stat_key(kind, school):
    return kind + "." + school if school else kind


def _first(fields, names):
    """(property, value) of the first of names fields holds with a value (not None), else (None, None)"""
    for k in names:
        if k in fields and fields[k] is not None:
            return k, fields[k]
    return None, None


def _num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) else None


def effect_stats(e, lookup=None):
    """[(stat key, value or None, how)] of one equip effect (gearmem's {type, fields}): how is "value" (a number read),
    "index" (a lookup index - the size not known unless lookup(name, index) gives it: "table"), "unread" (no number read),
    "type" (an effect kind with no stat - its type name kept as raw.<type>)"""
    t = (e or {}).get("type") or ""
    f = (e or {}).get("fields") or {}
    out = []
    if "StatisticEffect" in t or (_first(f, STAT_NAME_PROPS)[1] and (_first(f, VALUE_PROPS)[0] or _first(f, INDEX_PROPS)[0])):
        _k, name = _first(f, STAT_NAME_PROPS)
        kind, sch = parse_stat(name)
        key = stat_key(kind, sch) if kind != "raw" else "raw." + (sch or "?")
        _vk, val = _first(f, VALUE_PROPS)
        val = _num(val)
        if val is not None:
            return [(key, val, "value")]
        _ik, idx = _first(f, INDEX_PROPS)
        if _num(idx) is not None:
            got = None
            if lookup is not None:
                try:
                    got = _num(lookup(name, idx))
                except Exception:  # noqa: BLE001 - not known then
                    got = None
            return [(key, got, "table")] if got is not None else [(key, None, "index:%d" % int(idx))]
        return [(key, None, "unread")]
    if "StartingPip" in t:
        for prop, key in PIP_PROPS:
            if prop in f:
                out.append((key, _num(f[prop]), "value" if _num(f[prop]) is not None else "unread"))
        return out or [("pips", None, "unread")]
    if "Speed" in t:
        _k, v = _first(f, SPEED_PROPS)
        return [("speed", _num(v), "value" if _num(v) is not None else "unread")]
    if "ProvideSpell" in t:
        _k, v = _first(f, CARD_PROPS)
        return [("cards", _num(v), "value" if _num(v) is not None else "unread")]
    return [("raw." + (t or "?"), None, "type")]


def item_stats(effects, lookup=None):
    """(stats {key: value}, unknown [keys whose size isn't known], how {key: "index:N"...}) of an item's equip effects -
    the same key twice added up. effects None (not read): (None, ["effects"], {}). raw.* keys are shown, never scored:
    not unknown"""
    if effects is None:
        return None, ["effects"], {}
    stats, unknown, how = {}, [], {}
    for e in effects:
        for key, val, h in effect_stats(e, lookup):
            if key.startswith("raw."):
                stats.setdefault(key, None)
                continue
            if val is None:
                if key not in unknown:
                    unknown.append(key)
                how[key] = h
                stats.setdefault(key, None)
                continue
            stats[key] = (stats.get(key) or 0) + val
    return stats, unknown, how


def stats_text(stats, how=None):
    """k=v,... of an item's stats for /gear: a size not known "?" (an index "#N"), raw.* names only"""
    if stats is None:
        return "?"
    out = []
    for k in sorted(stats):
        v = stats[k]
        if k.startswith("raw."):
            out.append(k)
        elif v is None:
            h = (how or {}).get(k, "")
            out.append("%s=%s" % (k, "#" + h[6:] if h.startswith("index:") else "?"))
        else:
            out.append("%s=%s" % (k, ("%d" % v) if float(v).is_integer() else ("%.2f" % v)))
    return ",".join(out)


def delta_of(stats, school):
    """the totals' keys (TOTAL_KEYS) an item's stats add for a wizard of school - a school's own stat and the "all" one
    added; a resist for one school counts a seventh (it's only against that school's hits)"""
    s = stats or {}
    sch = B.school_of(school)

    def g(k):
        v = s.get(k)
        return v if isinstance(v, (int, float)) else 0

    def both(kind):
        return g(kind + ".all") + (g(kind + "." + sch) if sch else 0)
    return {"damage": both("damage"), "pierce": both("pierce"), "crit": both("critical"), "block": both("block"),
            "acc": both("accuracy"), "heal": both("outheal"), "incheal": g("incheal"),
            "resist": g("resist.all") + sum(g("resist." + x) for x in SCHOOLS) / len(SCHOOLS),
            "hp": g("health"), "pp": g("powerpip"), "pips": g("pips") + g("powerpips"), "cards": g("cards")}


def scored_unknown(stats, unknown):
    """the unknown stats that would count in the score (raw.* and ones the score doesn't use - mana, speed - don't)"""
    used = {"health", "powerpip", "pips", "powerpips", "cards", "incheal"}
    out = []
    for k in unknown or []:
        kind = k.split(".")[0]
        if kind in SCHOOLED or k in used:
            out.append(k)
    return out


# ============================================================================ may the wizard wear it
def req_level(req):
    """the level a requirement asks (ReqMagicLevel's number), None not read"""
    _k, v = _first((req or {}).get("fields") or {}, LEVEL_PROPS)
    return _num(v)


def req_school(req):
    _k, v = _first((req or {}).get("fields") or {}, SCHOOL_PROPS)
    return (v or "").strip().lower() if isinstance(v, str) else None


def one_req(req, level, school):
    """(True / False / None, why) of one requirement - ReqMagicLevel (level at least its number - the operator's meaning
    isn't read: at least is the gear's), ReqSchoolOfFocus (the wizard's school); any other kind: None (not understood);
    its applyNOT turns it round"""
    t = (req or {}).get("type") or ""
    f = (req or {}).get("fields") or {}
    if "MagicLevel" in t or t == "ReqLevel":
        need = req_level(req)
        if need is None:
            ok, why = None, "its level requirement not read"
        elif level is None:
            ok, why = None, "level %d needed - your level not known" % need
        else:
            ok, why = level >= need, "level %d" % need
    elif "SchoolOfFocus" in t or t == "ReqSchool":
        sch = req_school(req)
        if not sch:
            ok, why = None, "its school requirement not read"
        elif not school:
            ok, why = None, "%s only - your school not known" % sch
        else:
            ok, why = (sch == school.lower()), "%s only" % sch
    else:
        return None, "a requirement not understood (%s)" % (t or "?")
    if f.get("m_applyNOT") is True and ok is not None:
        ok, why = (not ok), "not " + why
    elif f.get("m_applyNOT") not in (None, False, True):
        return None, "a requirement's NOT flag not read"
    return ok, why


def meets_reqs(reqs, level, school):
    """(True / False / None, why) - may a wizard of level and school wear an item with these requirements (gearmem's
    {op, not, list}: none - no requirement list - is True). op 0 (or one requirement): all of them; another op (an OR?
    its meaning isn't read): sure only when all agree. None: not known (a requirement not understood or not read)"""
    if reqs is None:
        return None, "its requirements not read"
    lst = reqs.get("list") or []
    if not lst:
        ok, why = True, "no requirement"
    else:
        res = [one_req(r, level, school) for r in lst]
        vals = [v for v, _w in res]
        whys = ", ".join(w for _v, w in res)
        if all(v is True for v in vals):
            ok = True
        elif all(v is False for v in vals):
            ok = False
        elif reqs.get("op") in (0, None) or len(lst) == 1:
            ok = False if any(v is False for v in vals) else None
        else:
            ok = None
        why = whys
    if reqs.get("not") is True and ok is not None:
        ok, why = (not ok), "not (%s)" % why
    return ok, why


def level_req(reqs):
    """the level an item's requirements ask (the highest ReqMagicLevel), None none read"""
    lv = [req_level(r) for r in (reqs or {}).get("list") or [] if "MagicLevel" in ((r or {}).get("type") or "")]
    lv = [v for v in lv if v is not None]
    return max(lv) if lv else None


# ============================================================================ the score
def parse_weights(text):
    """{key: number} of /gear's weights= "off:1,def:0.5,..." (also = between - Gear.ahk
    builds it from PlayerStats' gearweight.off:1, gearweight.def:0.5... lines); junk left out"""
    out = {}
    for kv in re.split(r"[,;]", text or ""):
        k, _, v = kv.replace("=", ":").partition(":")
        try:
            if k.strip():
                out[k.strip().lower()] = float(v)
        except ValueError:
            pass
    return out


def role_weights(role, weights=None):
    w = dict(ROLE_WEIGHTS.get((role or "hitter").lower(), ROLE_WEIGHTS["hitter"]))
    for k, v in (weights or {}).items():
        if k in w or k == "eblock":
            w[k] = v
    return w


def score(totals, role="hitter", school="", level=None, weights=None):
    """the wizard's totals ({damage, pierce, crit, block, acc, resist, hp, pp, pips, heal, incheal, cards} - % or
    ratings, hp in health) as one number for its role (see the top) - log-points"""
    t = {k: float((totals or {}).get(k) or 0) for k in TOTAL_KEYS}
    w = role_weights(role, weights)
    eblock = w.get("eblock", ENEMY_BLOCK)
    sch = B.school_of(school)
    acc = min(1.0, max(0.05, (B.SCHOOL_ACC.get(sch, 80) + t["acc"]) / 100.0))
    cc = B.crit_chance(t["crit"], eblock, level or 100)
    cm = B.crit_mult(t["crit"], eblock)
    eres = max(0.0, ENEMY_RESIST - t["pierce"])
    off = max(1e-6, B.damage_multiplier(t["damage"]) * acc * (1 + cc * (cm - 1)) * (1 - eres / 100.0))
    res = min(RESIST_CAP, max(-90.0, t["resist"]))
    ehp = max(1.0, t["hp"] or 1.0) / (1 - res / 100.0) * max(0.1, 1 + t["incheal"] / 100.0)
    pips = 1 + 0.5 * min(100.0, max(0.0, t["pp"])) / 100.0 + 0.1 * max(0.0, t["pips"])
    heal = max(0.1, 1 + t["heal"] / 100.0)
    return (w["off"] * math.log(off) + w["def"] * math.log(ehp) + w["pip"] * math.log(pips) + w["heal"] * math.log(heal)
            + w["cards"] * t["cards"])


def swapped(totals, worn_d, cand_d):
    """the totals with the worn piece's stats (delta_of) taken off and the candidate's added"""
    out = dict(totals or {})
    for k in TOTAL_KEYS:
        out[k] = float(out.get(k) or 0) - (worn_d or {}).get(k, 0) + (cand_d or {}).get(k, 0)
    return out


def baseline(totals, worn_d, cand_d):
    """(totals, worn_d, cand_d) a swap is scored on: a total not sent is 0 (Gear.ahk sends no pp, pips, heal, incheal,
    cards - nor a stat PlayerStats hasn't), but the wizard wears the worn piece, so each total is at least what that piece
    gives - taken off a 0 it'd go below 0 and be clamped there, a loss counted as nothing (a power-pip ring swapped for a
    damage one for free); and health not known (hp 0): health isn't counted at all (both pieces' health left out) - on a
    baseline of 1 a +20 health would outweigh every other stat, and the wizard's own health (thousands) is what makes a
    piece's few hundred count little"""
    t = {k: float((totals or {}).get(k) or 0) for k in TOTAL_KEYS}
    wd, cd = dict(worn_d or {}), dict(cand_d or {})
    if t["hp"] <= 0:
        wd["hp"] = cd["hp"] = 0
    for k in TOTAL_KEYS:
        if wd.get(k, 0) > t[k]:
            t[k] = float(wd[k])
    return t, wd, cd


def why_text(worn_d, cand_d):
    """"damage +4, health +120, resist -2" - what changes (the totals' keys that differ)"""
    names = {"damage": "damage", "pierce": "pierce", "crit": "critical", "block": "block", "acc": "accuracy",
             "resist": "resist", "hp": "health", "pp": "power pip", "pips": "pips", "heal": "healing",
             "incheal": "incoming healing", "cards": "item cards"}
    out = []
    for k in TOTAL_KEYS:
        d = (cand_d or {}).get(k, 0) - (worn_d or {}).get(k, 0)
        if abs(d) >= 0.05:
            out.append("%s %+g" % (names[k], round(d, 1)))
    return ", ".join(out) or "the same stats"


# ============================================================================ the plan
def _prep(it, school, lookup=None):
    """an item with its stats (item_stats), the totals it adds (delta_of) and its level requirement - kept on a copy"""
    d = dict(it)
    st, unk, how = item_stats(it.get("effects"), lookup)
    d["stats"], d["unknown"], d["how"] = st, unk, how
    d["scored_unknown"] = scored_unknown(st, unk) if st is not None else ["effects"]
    d["delta"] = delta_of(st, school) if st is not None else None
    d["level_req"] = level_req(it.get("reqs"))
    d["slot"] = item_slot(it)            # (None: not read)
    return d


def compare(worn, cand, totals, role, school, level, weights=None):
    """(delta, basis, why) of wearing cand instead of worn (both _prep'd; worn None: the slot's empty): basis "stats"
    (delta in % - every stat that counts known for both), "level" (delta the levels more - a stat's size not known: the
    level requirement compared), "empty" (nothing worn there), or None (delta None: can't be compared)"""
    if worn is None:
        return 100.0, "empty", "nothing worn there"
    if cand["stats"] is None or worn["stats"] is None:
        return None, None, "%s equip effects couldn't be read" % ("its" if cand["stats"] is None else "the worn piece's")
    if not cand["scored_unknown"] and not worn["scored_unknown"]:
        base, wd, cd = baseline(totals, worn["delta"], cand["delta"])
        s0 = score(base, role, school, level, weights)
        s1 = score(swapped(base, wd, cd), role, school, level, weights)
        return round((s1 - s0) * 100, 2), "stats", why_text(worn["delta"], cand["delta"])
    lw, lc = worn.get("level_req"), cand.get("level_req")
    unk = sorted(set(cand["scored_unknown"]) | set(worn["scored_unknown"]))
    if lw is not None and lc is not None:
        return float(lc - lw), "level", "level %d vs %d (the stats' sizes not known: %s)" % (lc, lw, ",".join(unk[:4]))
    return None, None, "the stats' sizes not known (%s) and no level requirement to go by" % ",".join(unk[:4])


def empty_worth(cand, totals, role, school, level, weights=None):
    """(sure, worth) of a piece for a slot with nothing worn - which of several to put on (compare's "empty" is the same
    100 for all of them): sure 2 its score against nothing worn (every stat that counts known - log-points), 1 its level
    requirement (a stat's size not known), 0 neither"""
    if cand.get("stats") is not None and not cand.get("scored_unknown"):
        base, wd, cd = baseline(totals, {}, cand["delta"])
        return 2, score(swapped(base, wd, cd), role, school, level, weights) - score(base, role, school, level, weights)
    if cand.get("level_req") is not None:
        return 1, float(cand["level_req"])
    return 0, 0.0


def swap_plan(worn, bag, totals, school="", level=None, role="hitter", margin=MARGIN, allow_sets=False, weights=None,
              lookup=None):
    """the plan: worn and bag are gearmem's items ({gid, tid, name, display, slot or adjs, effects, reqs, sets [n],
    crowns}), totals the wizard's (score's keys - the worn gear in them). {plan [{slot, gid, tid, name, worn_gid,
    worn_name, delta, basis, held, why}] (one a slot at most: the best piece of the backpack better by margin % - basis
    "level": by more levels, "empty": a slot with nothing worn; held 1: the worn piece is in an Equipment Set - a swap
    would be undone by the set's Ctrl+N: re-save the set (allow_sets: gearsets:1 - not held)), judged [{gid, slot,
    verdict, delta, basis, why}] (every backpack piece of a planned slot: better, not better, can't wear, in a set, unknown -
    and one whose slot couldn't be read: unknown, slot None), notes [text]}. Decks, pets and mounts are never in it. A
    worn piece whose slot couldn't be read may be any slot's with nothing else worn: those slots' pieces are unknown then,
    never better than "nothing worn there"."""
    worn_p = [_prep(w, school, lookup) for w in worn or []]
    bag_p = [_prep(b, school, lookup) for b in bag or []]
    by_slot = {}
    for w in worn_p:
        if w["slot"] in SLOTS and w["slot"] not in by_slot:
            by_slot[w["slot"]] = w
    worn_unread = [w for w in worn_p if w["slot"] is None]
    plan, judged, notes = [], [], []
    if level is None:
        notes.append("your level isn't known: a piece with a level requirement can't be judged")
    if worn_unread:
        notes.append("%d worn piece%s couldn't be read (%s): a slot with nothing else worn isn't judged as empty" %
                     (len(worn_unread), "" if len(worn_unread) == 1 else "s",
                      ", ".join("%x" % w["gid"] if w.get("gid") else "?" for w in worn_unread[:3])))
    for slot in SLOTS:
        w = by_slot.get(slot)
        held = bool(w and w.get("sets")) and not allow_sets
        best = None
        for c in (b for b in bag_p if b["slot"] == slot):
            j = {"gid": c.get("gid"), "slot": slot, "verdict": "", "delta": None, "basis": None, "why": ""}
            judged.append(j)
            ok, rwhy = meets_reqs(c.get("reqs"), level, school)
            if ok is False:
                j.update(verdict="can't wear", why=rwhy)
                continue
            if ok is None:
                j.update(verdict="unknown", why=rwhy)
                continue
            if c.get("sets") and not allow_sets:
                j.update(verdict="in a set", why="in Equipment Set %s (kept for it)" % ",".join(str(n) for n in c["sets"]))
                continue
            if w is None and worn_unread:
                j.update(verdict="unknown", why="nothing read as worn there, but a worn piece couldn't be read - it may be "
                                                "this slot's")
                continue
            delta, basis, cwhy = compare(w, c, totals, role, school, level, weights)
            j.update(delta=delta, basis=basis, why=cwhy)
            if delta is None:
                j["verdict"] = "unknown"
                continue
            better = delta >= (margin if basis == "stats" else 1)
            j["verdict"] = "better" if better else "not better"
            # (of several better ones: the surest basis first - the score's -, then the most better; nothing worn there:
            # each is "empty" 100 - the best of them by its own stats, else its level requirement - empty_worth)
            key = (_rank(basis), delta) + (empty_worth(c, totals, role, school, level, weights) if basis == "empty"
                                           else (0, 0.0))
            if better and (best is None or key > best[4]):
                best = (c, delta, basis, cwhy, key)
        if best is None:
            continue
        c, delta, basis, cwhy, _ = best
        plan.append({"slot": slot, "gid": c.get("gid"), "tid": c.get("tid"), "name": c.get("display") or c.get("name"),
                     "worn_gid": w.get("gid") if w else None, "worn_name": (w.get("display") or w.get("name")) if w else "",
                     "delta": delta, "basis": basis, "held": held,
                     "why": cwhy + ("; the worn piece is in Equipment Set %s - re-save the set after a swap (or gearsets:1)"
                                    % ",".join(str(n) for n in w["sets"]) if held else "")})
    # (a backpack piece whose slot couldn't be read - its template or adjectives: not judged, so a full backpack holding
    # it is never sold on the plan's word - Gear.ahk GearSellOk counts it)
    for c in (b for b in bag_p if b["slot"] is None):
        judged.append({"gid": c.get("gid"), "slot": None, "verdict": "unknown", "delta": None, "basis": None,
                       "why": "its template couldn't be read - its slot, stats and requirements aren't known"})
    return {"plan": plan, "judged": judged, "notes": notes}


def _rank(basis):
    """a plan's basis, surest first: stats (the score), empty (nothing worn), level"""
    return {"stats": 3, "empty": 2, "level": 1}.get(basis, 0)


# ============================================================================ the drop log and "done"
def run_file(run):
    """a run's name as a file name (no path characters; 80 at most) - Dungeons.ahk DgRunFile's (\\w ASCII, as
    AutoHotkey's)"""
    s = re.sub(r"[^\w .()-]+", "-", (run or "").strip(), flags=re.ASCII)[:80].strip(" .")
    return s or "run"


def parse_slots(text):
    """[slot] of a run's slots| line or a catalogue's ("hat, robe,shoes") - only SLOTS', in their order, once each"""
    have = {s.strip().lower() for s in re.split(r"[,;/ ]+", text or "") if s.strip()}
    have = {"shoes" if s in ("boots", "shoe") else "weapon" if s in ("wand", "sword", "staff") else s for s in have}
    return [s for s in SLOTS if s in have]


def catalogue(text):
    """[{name, world, link, slots [..], zones, sigil, bosses}] of resources\\dungeons_known.txt: name|world|link|slots|
    zones|sigil|bosses lines (; a note)"""
    out = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        f = (line.split("|") + [""] * 7)[:7]
        if not f[0].strip():
            continue
        out.append({"name": f[0].strip(), "world": f[1].strip(), "link": f[2].strip(), "slots": parse_slots(f[3]),
                    "zones": [z.strip() for z in f[4].split(",") if z.strip()], "sigil": f[5].strip(),
                    "bosses": [b.strip() for b in f[6].split(",") if b.strip()]})
    return out


def catalogue_for(run, cat):
    """the catalogue's dungeon a run is of: one whose name's letters are in the run's name (the longest such name), else
    None"""
    key = re.sub(r"[^a-z]", "", (run or "").lower())
    hits = [d for d in cat or [] if re.sub(r"[^a-z]", "", d["name"].lower()) and
            re.sub(r"[^a-z]", "", d["name"].lower()) in key]
    return max(hits, key=lambda d: len(d["name"])) if hits else None


def new_items(before_gids, items):
    """the items whose gid isn't among before_gids (the backpack at the run's start) - this run's drops"""
    before = set(before_gids or ())
    return [it for it in items or [] if it.get("gid") and it["gid"] not in before]


def owned_gids(reading):
    """[gid] a run's start is noted by: the backpack's (bag_gids - every item) and the worn pieces' - a piece worn at the
    start and taken off during the run (you put on the plan's piece) is in the backpack at its end, and isn't a drop"""
    r = reading or {}
    out = list(r.get("bag_gids") or [])
    have = set(out)
    for w in r.get("worn") or []:
        g = w.get("gid")
        if g and g not in have:
            have.add(g)
            out.append(g)
    return out


def log_drops(drops, new, when):
    """drops ({tid: {tid, name, slot, display, first, count}}) with the new items counted in - a template first seen
    gets first = when"""
    out = {k: dict(v) for k, v in (drops or {}).items()}
    for it in new or []:
        tid = it.get("tid")
        if tid is None:
            continue
        e = out.setdefault(tid, {"tid": tid, "name": it.get("name") or "", "slot": it.get("slot") or "",
                                 "display": it.get("display") or "", "first": when, "count": 0})
        e["count"] += 1
        if not e.get("display") and it.get("display"):
            e["display"] = it["display"]
    return out


def done_check(slots, worn, drops, dry, stopafter):
    """(done, why): every one of slots is worn with a template this run dropped (drops' tids), or stopafter runs went
    by with no upgrade (dry); slots [] - the dry runs only"""
    tids = set(drops or {})
    worn_by = {}
    for w in worn or []:
        worn_by.setdefault(w.get("slot"), w)
    if slots:
        mine = [s for s in slots if worn_by.get(s) and worn_by[s].get("tid") in tids]
        if len(mine) == len(slots):
            return True, "every slot it drops (%s) is worn with its own drop" % ", ".join(slots)
    if stopafter and dry >= stopafter:
        return True, "%d runs with no upgrade" % dry
    left = [s for s in slots if not (worn_by.get(s) and worn_by[s].get("tid") in tids)] if slots else []
    return False, ("%s not worn from its drops yet" % ", ".join(left) if left else "no slots listed") + \
        ", %d of %d dry runs" % (dry, stopafter or 0)


class DropBook:
    """a dungeon run's drop log and state in folder (learned\\drops): <run>.txt one line a template it dropped -
    tid|object name|slot|display|first seen|count -, <run>.state an .ini ([run]: runs, dry, done, why, at, worn
    slot:tid,..., before gid hex,...) Dungeons.ahk reads for its tab"""

    def __init__(self, folder):
        self.folder = folder

    def path(self, run, ext):
        return os.path.join(self.folder, run_file(run) + ext)

    def load_drops(self, run):
        out = {}
        try:
            with open(self.path(run, ".txt"), encoding="utf-8") as f:
                for line in f:
                    if not line.strip() or line.startswith(";"):
                        continue
                    p = (line.rstrip("\r\n").split("|") + [""] * 6)[:6]
                    try:
                        tid = int(p[0])
                    except ValueError:
                        continue
                    out[tid] = {"tid": tid, "name": p[1], "slot": p[2], "display": p[3], "first": p[4],
                                "count": int(p[5]) if p[5].isdigit() else 0}
        except OSError:
            pass
        return out

    def save_drops(self, run, drops):
        lines = ["; Wiz-Maxxing - what the dungeon run '%s' dropped (vision\\gearrank.py): tid|object name|slot|display|"
                 "first seen|count" % run.replace("\n", " ")]
        for tid in sorted(drops, key=lambda t: (drops[t].get("first") or "", t)):
            e = drops[tid]
            lines.append("|".join(str(x).replace("|", "/").replace("\n", " ") for x in
                                  (tid, e.get("name") or "", e.get("slot") or "", e.get("display") or "",
                                   e.get("first") or "", e.get("count") or 0)))
        self._write(self.path(run, ".txt"), "\r\n".join(lines) + "\r\n")

    def load_state(self, run):
        st = {"runs": 0, "dry": 0, "done": 0, "why": "", "at": "", "worn": {}, "before": None}
        try:
            with open(self.path(run, ".state"), encoding="utf-8") as f:
                for line in f:
                    k, eq, v = line.strip().partition("=")
                    if not eq:
                        continue
                    k, v = k.strip(), v.strip()
                    if k in ("runs", "dry", "done"):
                        st[k] = int(v) if v.isdigit() else 0
                    elif k == "worn":
                        st["worn"] = {a: int(b) for a, _, b in (p.partition(":") for p in v.split(",") if p)
                                      if b.isdigit()}
                    elif k == "before":
                        st["before"] = [int(g, 16) for g in v.split(",") if re.fullmatch(r"[0-9a-fA-F]{1,16}", g)]
                    elif k in ("why", "at"):
                        st[k] = v
        except OSError:
            pass
        return st

    def save_state(self, run, st):
        text = "[run]\r\n" + "".join("%s=%s\r\n" % (k, v) for k, v in (
            ("runs", st.get("runs", 0)), ("dry", st.get("dry", 0)), ("done", 1 if st.get("done") else 0),
            ("why", str(st.get("why") or "").replace("\n", " ")), ("at", st.get("at") or ""),
            ("worn", ",".join("%s:%d" % kv for kv in sorted((st.get("worn") or {}).items()))),
            ("before", ",".join("%x" % g for g in st.get("before") or []))))
        self._write(self.path(run, ".state"), text)

    def _write(self, path, text):
        os.makedirs(self.folder, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, path)

    def mark(self, run, reading, when):
        """a run started: the backpack's and the worn pieces' ids kept (owned_gids - the next run_end's drops are the
        items not among them)"""
        st = self.load_state(run)
        st["before"] = owned_gids(reading)
        st["at"] = when
        self.save_state(run, st)
        return st

    def run_end(self, run, reading, plan, slots, stopafter, when, marked=True):
        """a run done: {new [items], drops, runs, dry, done, why, marked (False: no backpack ids from its start - its
        drops not counted this time), unread (its new items whose slot couldn't be read), upgrade} - this run's new gear
        logged, an upgrade (a new piece in the plan, or a slot now worn with a drop of this run's that wasn't before)
        resets dry, else +1 - not when its drops weren't all known (not marked, or a new item not read): dry kept then;
        done_check; the backpack's and worn ids kept for the next run. reading: gearmem's (bag - gear items and unread
        ones -, bag_gids - every item -, worn). marked False (/gear's nomark=1 - Gear.ahk: this run's start wasn't noted, the
        mark failed or gearswap was off then): the state's before= is an older run's - never taken for this one's start
        (it would count everything picked up since as this dungeon's drops): not counted, the backpack kept afresh"""
        reading = reading or {}
        st = self.load_state(run)
        drops = self.load_drops(run)
        marked = bool(marked) and st.get("before") is not None
        new_all = new_items(st.get("before"), reading.get("bag") or []) if marked else []
        unread = [it for it in new_all if item_slot(it) is None]
        new = [dict(it, slot=item_slot(it)) for it in new_all if item_slot(it) in SLOTS]
        drops = log_drops(drops, new, when)
        worn_now = {}
        for w in reading.get("worn") or []:
            slot = item_slot(w)
            if slot in SLOTS and slot not in worn_now and w.get("tid") is not None:
                worn_now[slot] = w["tid"]
        new_gids = {it.get("gid") for it in new}
        # (an upgrade: a piece this run dropped is in the plan, or a slot is worn with one of this dungeon's drops now
        # that wasn't at the last run's end - you put it on; the first run's end has no worn slots to go by)
        upgrade = any(p.get("gid") in new_gids for p in plan or []) or bool(st["worn"]) and any(
            tid in drops and st["worn"].get(slot) != tid for slot, tid in worn_now.items())
        st["runs"] = st.get("runs", 0) + 1
        # (a dry run only when this run's drops are all known: not marked, or one not read - it may have been an upgrade)
        st["dry"] = 0 if upgrade else st.get("dry", 0) + (1 if marked and not unread else 0)
        worn_list = [{"slot": s, "tid": t} for s, t in worn_now.items()]
        done, why = done_check(slots, worn_list, drops, st["dry"], stopafter)
        st.update(done=done, why=why, at=when, worn=worn_now, before=owned_gids(reading))
        if new:
            self.save_drops(run, drops)
        self.save_state(run, st)
        return {"new": new, "drops": drops, "runs": st["runs"], "dry": st["dry"], "done": done, "why": why,
                "marked": marked, "unread": len(unread), "upgrade": upgrade}


# ============================================================================ /gear's answer
def cell(v):
    """a field of a /gear line: no | or line breaks; None empty; a flag 1/0"""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "1" if v else "0"
    return re.sub(r"[|\r\n]+", " ", str(v)).strip()


def reqs_text(reqs):
    """level>=50,school=fire,!school=ice,?ReqHasBadge - an item's requirements ("?" not read, "" none)"""
    if reqs is None:
        return "?"
    out = []
    for r in reqs.get("list") or []:
        t = r.get("type") or "?"
        neg = "!" if (r.get("fields") or {}).get("m_applyNOT") is True else ""
        if "MagicLevel" in t:
            lv = req_level(r)
            out.append("%slevel>=%s" % (neg, "?" if lv is None else "%g" % lv))
        elif "SchoolOfFocus" in t:
            out.append("%sschool=%s" % (neg, req_school(r) or "?"))
        else:
            out.append("?" + t)
    return ("!" if reqs.get("not") is True else "") + ",".join(out)


def gear_lines(r, why="", plan=None, totals=None, school="", role="", level=None, run=None, ms=None):
    """/gear's answer (vision.py's docstring) for gearmem's reading r (None: none|<why>) and swap_plan's plan:
    gear|worn n|bag gear n|bag items|level|school|role|sets ok|ms|why
    stats|damage|pierce|crit|block|acc|resist|hp|pp|level      (the totals the plan went by)
    worn|slot|gid hex|tid|object name|display|level req|stats|sets
    item|gid hex|tid|object name|display|slot|verdict|delta|basis|why|stats|reqs|crowns|nosell|sets
    plan|slot|gid hex|tid|name|worn gid hex|worn name|delta|basis|held|why
    note|text
    drop|tid|object name|slot|display|count|first             (run end=1: this run's new pieces)
    run|name|runs|dry|stopafter|done|why|new|marked"""
    if not r:
        return ["none|" + cell(why or "the gear can't be read")]
    plan = plan or {"plan": [], "judged": [], "notes": []}
    worn, bag = r.get("worn") or [], r.get("bag") or []
    out = ["|".join(["gear", str(len(worn)), str(len(bag)), cell(r.get("bag_size")), cell(level), cell(school), cell(role),
                     cell(bool(r.get("sets_ok"))), cell(ms), cell(why or r.get("why"))])]
    t = totals or {}
    out.append("|".join(["stats"] + [cell("%g" % t[k] if isinstance(t.get(k), (int, float)) else t.get(k))
                                     for k in ("damage", "pierce", "crit", "block", "acc", "resist", "hp", "pp")]
                        + [cell(level)]))
    for w in worn:
        st, _u, how = item_stats(w.get("effects"))
        out.append("|".join(["worn", cell(item_slot(w)), "%x" % w["gid"] if w.get("gid") else "",
                             cell(w.get("tid")), cell(w.get("name")), cell(w.get("display")),
                             cell(level_req(w.get("reqs"))), cell(stats_text(st, how)),
                             ",".join(str(n) for n in w.get("sets") or [])]))
    jby = {j["gid"]: j for j in plan.get("judged") or []}
    for b in bag:
        st, _u, how = item_stats(b.get("effects"))
        j = jby.get(b.get("gid")) or {}
        slot = item_slot(b)
        # (a slot not read: unknown even with no judged entry - never "not planned", which would let a sale through)
        out.append("|".join(["item", "%x" % b["gid"] if b.get("gid") else "", cell(b.get("tid")), cell(b.get("name")),
                             cell(b.get("display")), cell(slot), cell(j.get("verdict") or (
                                 "unknown" if slot is None else "" if slot in SLOTS else "not planned")),
                             cell(j.get("delta")), cell(j.get("basis")), cell(j.get("why")), cell(stats_text(st, how)),
                             cell(reqs_text(b.get("reqs"))), cell(bool(b.get("crowns"))), cell(bool(b.get("nosell"))),
                             ",".join(str(n) for n in b.get("sets") or [])]))
    for p in plan.get("plan") or []:
        out.append("|".join(["plan", cell(p["slot"]), "%x" % p["gid"] if p.get("gid") else "", cell(p.get("tid")),
                             cell(p.get("name")), "%x" % p["worn_gid"] if p.get("worn_gid") else "", cell(p.get("worn_name")),
                             cell(p.get("delta")), cell(p.get("basis")), cell(bool(p.get("held"))), cell(p.get("why"))]))
    for n in plan.get("notes") or []:
        out.append("note|" + cell(n))
    if run:
        for it in run.get("new") or []:
            e = (run.get("drops") or {}).get(it.get("tid")) or {}
            out.append("|".join(["drop", cell(it.get("tid")), cell(it.get("name")), cell(it.get("slot")),
                                 cell(it.get("display")), cell(e.get("count")), cell(e.get("first"))]))
        out.append("|".join(["run", cell(run.get("name")), cell(run.get("runs")), cell(run.get("dry")),
                             cell(run.get("stopafter")), cell(bool(run.get("done"))), cell(run.get("why")),
                             str(len(run.get("new") or [])), cell(bool(run.get("marked", True)))]))
    return out


def totals_of(q):
    """the wizard's totals from /gear's query ({damage, pierce, crit, block, acc, resist, hp, pp, heal, incheal} -
    numbers, junk 0)"""
    out = {}
    for k in TOTAL_KEYS:
        try:
            out[k] = float(q.get(k) or 0)
        except (TypeError, ValueError):
            out[k] = 0.0
    return out


def answer(r, why, q, drops_dir=None, known_text="", when=None):
    """/gear's lines for gearmem's reading r and the query q (vision.py: school, level, role, weights, margin, sets,
    the totals; run, mark=1 / end=1, slots, stopafter) - the drop log in drops_dir, the catalogue known_text
    (resources\\dungeons_known.txt) for a run with no slots; end=1&nomark=1: this run's start wasn't noted - Gear.ahk's
    mark failed or gearswap was off then - its drops not counted, the backpack kept afresh). Never raises"""
    try:
        if not r:
            return gear_lines(None, why)
        t0 = time.perf_counter()
        school = B.school_of(q.get("school"))
        try:
            level = int(float(q.get("level"))) if q.get("level") else r.get("level")
        except ValueError:
            level = r.get("level")
        role = (q.get("role") or "hitter").lower()
        role = role if role in ROLE_WEIGHTS else "hitter"
        try:
            margin = float(q.get("margin") or MARGIN)
        except ValueError:
            margin = MARGIN
        totals = totals_of(q)
        plan = swap_plan(r.get("worn"), r.get("bag"), totals, school, level, role, margin,
                         allow_sets=q.get("sets") == "1", weights=parse_weights(q.get("weights")))
        if not school:
            plan["notes"].append("your school isn't known: a school's own stats and school-only pieces can't be judged")
        if not totals.get("hp"):
            plan["notes"].append("your health isn't known (hp=): a piece's health isn't counted (resist still is)")
        if any(h.startswith("index:") for it in (r.get("worn") or []) + (r.get("bag") or [])
               for h in item_stats(it.get("effects"))[2].values()):
            plan["notes"].append("some stats are lookup indexes (#N), not values: their sizes aren't read yet - those "
                                 "pieces go by their level requirement")
        run = None
        name = (q.get("run") or "").strip()
        if name and drops_dir:
            book = DropBook(drops_dir)
            when = when or time.strftime("%Y-%m-%d %H:%M:%S")
            if q.get("mark") == "1":
                st = book.mark(name, r, when)
                run = {"name": name, "runs": st.get("runs"), "dry": st.get("dry"), "stopafter": "", "done": st.get("done"),
                       "why": "marked: the %d items in the backpack and worn kept" % len(st.get("before") or []), "new": []}
            elif q.get("end") == "1":
                slots = parse_slots(q.get("slots"))
                if not slots:
                    d = catalogue_for(name, catalogue(known_text))
                    slots = d["slots"] if d else []
                try:
                    stopafter = int(float(q.get("stopafter") or STOPAFTER))
                except ValueError:
                    stopafter = STOPAFTER
                run = book.run_end(name, r, plan["plan"], slots, stopafter, when, marked=q.get("nomark") != "1")
                run.update(name=name, stopafter=stopafter)
                if not run["marked"]:
                    plan["notes"].append("no backpack noted at this run's start (gearswap was off then, or the backpack "
                                         "couldn't be read): its drops aren't counted this time - the next run's are")
                if run.get("unread"):
                    plan["notes"].append("%d of this run's new items couldn't be read (their templates): not logged, and "
                                         "the run isn't counted as dry" % run["unread"])
        ms = round((time.perf_counter() - t0) * 1000, 1)
        return gear_lines(r, why, plan, totals, school, role, level, run, ms)
    except Exception as e:  # noqa: BLE001 - never into the server
        return ["none|the gear plan failed (%r)" % (e,)]


# ============================================================================ a demo
def _demo():
    def stat(name, v):
        return {"type": "StatisticEffectInfo", "fields": {"m_effectName": name, "m_value": v}}

    def lvl(n):
        return {"op": 0, "not": False, "list": [{"type": "ReqMagicLevel", "fields": {"m_numericValue": n}}]}
    worn = [{"gid": 0x10, "tid": 1, "name": "Hat-Old", "slot": "hat", "reqs": lvl(50),
             "effects": [stat("CanonicalFireDamage", 8), stat("CanonicalMaxHealth", 200)]}]
    bag = [{"gid": 0x20, "tid": 2, "name": "Hat-New", "slot": "hat", "reqs": lvl(60),
            "effects": [stat("CanonicalFireDamage", 12), stat("CanonicalMaxHealth", 250)]},
           {"gid": 0x21, "tid": 3, "name": "Robe-New", "slot": "robe", "reqs": lvl(200), "effects": []}]
    totals = {"damage": 60, "pierce": 10, "crit": 150, "block": 100, "acc": 5, "resist": 20, "hp": 3000}
    r = {"worn": worn, "bag": bag, "bag_gids": [0x20, 0x21], "bag_size": 2, "level": 70, "sets_ok": True}
    print("\n".join(answer(r, "", dict({k: str(v) for k, v in totals.items()}, school="fire"))))


if __name__ == "__main__":
    if "--demo" in sys.argv:
        _demo()
    else:
        print(__doc__)
