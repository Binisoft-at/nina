#!/usr/bin/env python3
"""Build Nina's bundled food database (Packages/NinaCore/Sources/NinaCore/Resources/foods.json).

Inputs
  data/food-catalog.tsv   curated selection of USDA SR28 foods (names, aliases, category, unit, portions)
  data/foods-extra.json   DACH foods USDA lacks: computed from recipes of USDA ingredients, or typical label values
  --sr28 DIR              the USDA SR28 ASCII files (FOOD_DES.txt, NUT_DATA.txt, WEIGHT.txt)

Usage
  python3 scripts/build_food_db.py --sr28 <dir with SR28 txt files> [--out Packages/NinaCore/Sources/NinaCore/Resources/foods.json]

Python 3 standard library only. The output is deterministic for a given input and --date.
See data/README.md for the file formats and the naming rules.
"""

import argparse
import datetime
import json
import math
import os
import re
import sys
from collections import Counter, OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CATEGORIES = [
    "fruit", "vegetables", "legumes", "grains", "bread", "cereals", "dairy", "cheese", "eggs", "meat",
    "poultry", "sausages", "fish", "plantProtein", "nuts", "fats", "sweets", "snacks", "beverages",
    "alcohol", "condiments", "spices", "dishes", "fastFood", "other",
]

# Output key -> USDA SR28 Nutr_No. The order here is the order in the JSON.
NUTRIENTS = OrderedDict([
    ("energy", "208"), ("protein", "203"), ("carbs", "205"), ("fat", "204"), ("fiber", "291"),
    ("sugar", "269"), ("saturatedFat", "606"), ("monoFat", "645"), ("polyFat", "646"),
    ("transFat", "605"), ("cholesterol", "601"), ("sodium", "307"), ("potassium", "306"),
    ("calcium", "301"), ("iron", "303"), ("magnesium", "304"), ("zinc", "309"), ("vitaminA", "320"),
    ("vitaminC", "401"), ("vitaminD", "328"), ("vitaminE", "323"), ("vitaminB12", "418"),
    ("folate", "435"), ("water", "255"), ("alcohol", "221"), ("caffeine", "262"),
])
NUTR_NO = set(NUTRIENTS.values())
REQUIRED = ("energy", "protein", "carbs", "fat")
MAX_NAME = 44
MAX_ALIASES = 6
MAX_PORTIONS = 4

SOURCES = OrderedDict([
    ("usda", "USDA SR28 (public domain)"),
    ("recipe", "Computed from USDA SR28 ingredients"),
    ("label", "Typical values from common product labels (approximate)"),
])

# Volume of USDA household measures in ml (used to derive densities for "ml" foods).
NOT_LIQUID_MEASURE = re.compile(
    r"whipped|chopped|sliced|diced|shredded|grated|packed|mashed|cubes|pieces|crushed|halves|ground|"
    r"dry|undiluted|frozen|concentrate|crumbs|flakes|powder|yields")
VOLUME_ML = [
    (re.compile(r"^fl oz\b"), 29.5735),
    (re.compile(r"^cup\b"), 236.588),
    (re.compile(r"^(tbsp|tablespoon)\b"), 14.7868),
    (re.compile(r"^(tsp|teaspoon)\b"), 4.92892),
    (re.compile(r"^ml\b"), 1.0),
    (re.compile(r"^(l|liter|litre)\b"), 1000.0),
]

# Named portion profiles usable in the catalog's portions column as "@name".
PROFILES = {
    "water": [("glass (250 ml)", "Glas (250 ml)", 250), ("bottle (500 ml)", "Flasche (0,5 l)", 500)],
    "softdrink": [("glass (250 ml)", "Glas (250 ml)", 250), ("can (330 ml)", "Dose (330 ml)", 330),
                  ("bottle (500 ml)", "Flasche (0,5 l)", 500)],
    "juice": [("glass (250 ml)", "Glas (250 ml)", 250), ("small glass (125 ml)", "kleines Glas (125 ml)", 125)],
    "milk": [("glass (250 ml)", "Glas (250 ml)", 250), ("cup (150 ml)", "Tasse (150 ml)", 150),
             ("dash (20 ml)", "Schuss (20 ml)", 20)],
    "plantdrink": [("glass (250 ml)", "Glas (250 ml)", 250), ("dash (20 ml)", "Schuss (20 ml)", 20)],
    "coffee": [("cup (150 ml)", "Tasse (150 ml)", 150), ("mug (250 ml)", "Häferl (250 ml)", 250)],
    "espresso": [("espresso cup (30 ml)", "Espressotasse (30 ml)", 30), ("double (60 ml)", "doppelt (60 ml)", 60)],
    "tea": [("cup (200 ml)", "Tasse (200 ml)", 200), ("mug (300 ml)", "Häferl (300 ml)", 300)],
    "beer": [("bottle (500 ml)", "Flasche (0,5 l)", 500), ("small beer (330 ml)", "kleines Bier (0,33 l)", 330)],
    "wine": [("wine glass (125 ml)", "Achtel (125 ml)", 125), ("large glass (250 ml)", "Viertel (250 ml)", 250),
             ("bottle (750 ml)", "Flasche (0,75 l)", 750)],
    "spirits": [("shot (20 ml)", "Stamperl (2 cl)", 20), ("double (40 ml)", "Doppelter (4 cl)", 40)],
    "cocktail": [("glass (200 ml)", "Glas (200 ml)", 200)],
    "energy": [("can (250 ml)", "Dose (250 ml)", 250), ("can (500 ml)", "Dose (500 ml)", 500)],
    "soup": [("bowl (250 ml)", "Teller (250 ml)", 250), ("cup (150 ml)", "Tasse (150 ml)", 150)],
}

# Deriving portions from USDA WEIGHT.txt measure descriptions (used when the catalog leaves the
# portions column empty, mostly fruit, vegetables and oils): a size word ("medium", "fruit, small",
# "potato large (...)") or a countable first word ("clove", "slice", "tbsp", ...) becomes a portion;
# cups, ounces, servings, packages and similar US measures are ignored. Lower priority = listed first.
_SIZE = [
    ("extra small", "extra small", "sehr klein", 14),
    ("small", "small", "klein", 11),
    ("medium", "medium", "mittelgroß", 10),
    ("large", "large", "groß", 12),
    ("extra large", "extra large", "sehr groß", 15),
    ("jumbo", "extra large", "sehr groß", 16),
]
_PIECE_WORDS = {
    # word -> (en, de)
    "fruit": ("piece", "Stück"), "whole": ("piece", "Stück"), "piece": ("piece", "Stück"),
    "pc": ("piece", "Stück"), "each": ("piece", "Stück"), "item": ("piece", "Stück"),
    "roll": ("piece", "Stück"), "bun": ("piece", "Stück"), "bagel": ("piece", "Stück"),
    "muffin": ("piece", "Stück"), "croissant": ("piece", "Stück"), "doughnut": ("piece", "Stück"),
    "pastry": ("piece", "Stück"), "pancake": ("piece", "Stück"), "waffle": ("piece", "Stück"),
    "tortilla": ("piece", "Stück"), "pita": ("piece", "Stück"), "biscuit": ("piece", "Stück"),
    "cookie": ("cookie", "Keks"), "cracker": ("cracker", "Cracker"), "crispbread": ("slice", "Scheibe"),
    "wafer": ("piece", "Stück"), "bar": ("bar", "Riegel"), "link": ("piece", "Stück"),
    "frankfurter": ("piece", "Stück"), "frank": ("piece", "Stück"), "sausage": ("piece", "Stück"),
    "patty": ("patty", "Laibchen"), "burger": ("piece", "Stück"), "sandwich": ("piece", "Stück"),
    "fillet": ("fillet", "Filet"), "steak": ("steak", "Steak"), "chop": ("chop", "Kotelett"),
    "drumstick": ("drumstick", "Unterschenkel"), "thigh": ("thigh", "Oberschenkel"),
    "wing": ("wing", "Flügel"), "clove": ("clove", "Zehe"), "ear": ("ear", "Kolben"),
    "head": ("head", "Kopf"), "stalk": ("stalk", "Stange"), "spear": ("spear", "Stange"),
    "leaf": ("leaf", "Blatt"), "sprig": ("sprig", "Zweig"), "pod": ("pod", "Schote"),
    "pepper": ("piece", "Stück"), "sprout": ("sprout", "Röschen"), "date": ("piece", "Stück"),
    "fig": ("piece", "Stück"), "olive": ("piece", "Stück"), "egg": ("piece", "Stück"),
    "wedge": ("wedge", "Spalte"), "cube": ("cube", "Würfel"), "scoop": ("scoop", "Kugel"),
    "can": ("can", "Dose"), "bottle": ("bottle", "Flasche"),
    "packet": ("packet", "Päckchen"), "envelope": ("packet", "Päckchen"),
    "slice": ("slice", "Scheibe"), "slices": ("slice", "Scheibe"),
    "tbsp": ("tbsp", "EL"), "tablespoon": ("tbsp", "EL"), "tsp": ("tsp", "TL"), "teaspoon": ("tsp", "TL"),
}
_PIECE_PRIORITY = {"tbsp": 40, "tsp": 41, "slice": 30, "can": 26, "bottle": 27}


def die(msg):
    sys.stderr.write("error: " + msg + "\n")
    sys.exit(1)


# ---------------------------------------------------------------- SR28 reading

def sr28_rows(path):
    """Yield the fields of an SR28 ASCII file (fields separated by ^, text in ~, latin-1, CRLF)."""
    with open(path, encoding="latin-1", newline="") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line:
                continue
            out = []
            for field in line.split("^"):
                if len(field) >= 2 and field[0] == "~" and field[-1] == "~":
                    field = field[1:-1]
                out.append(field)
            yield out


class SR28:
    def __init__(self, directory):
        for name in ("FOOD_DES.txt", "NUT_DATA.txt", "WEIGHT.txt"):
            if not os.path.exists(os.path.join(directory, name)):
                die("missing %s in %s" % (name, directory))
        self.desc = {}
        for r in sr28_rows(os.path.join(directory, "FOOD_DES.txt")):
            self.desc[r[0]] = {"group": r[1], "long": r[2]}
        self.nut = {}
        for r in sr28_rows(os.path.join(directory, "NUT_DATA.txt")):
            if r[1] in NUTR_NO and r[2] != "":
                self.nut.setdefault(r[0], {})[r[1]] = float(r[2])
        self.weights = {}
        for r in sr28_rows(os.path.join(directory, "WEIGHT.txt")):
            try:
                amount, grams = float(r[2]), float(r[4])
            except ValueError:
                continue
            if amount > 0 and grams > 0:
                self.weights.setdefault(r[0], []).append((int(r[1]), amount, r[3], grams))
        for lst in self.weights.values():
            lst.sort()

    def per100g(self, ndb):
        """Nutrients per 100 g edible portion as {key: value}; keys without USDA data are omitted."""
        if ndb not in self.desc:
            die("NDB %s not found in FOOD_DES.txt" % ndb)
        raw = self.nut.get(ndb, {})
        return OrderedDict((k, raw[no]) for k, no in NUTRIENTS.items() if no in raw)

    def density(self, ndb):
        """g per ml from household volume measures in WEIGHT.txt, or None.

        Preference: "fl oz", then "cup", then a container with its volume in the description
        ("can (12 fl oz)"), then tbsp/tsp. Measures of a changed state (whipped, chopped, ...) are ignored.
        """
        best = None
        for _seq, amount, desc, grams in self.weights.get(ndb, []):
            d = clean_measure(desc)
            if NOT_LIQUID_MEASURE.search(d):
                continue
            cand = None
            for rank, (rx, ml) in enumerate(VOLUME_ML):
                if rx.match(d):
                    cand = (rank if rank < 2 else rank + 1, grams / (amount * ml))
                    break
            if cand is None:
                m = re.search(r"\(?(\d+(?:\.\d+)?) fl oz\)?", d)
                if m and not d.startswith(("fl oz", "cup")):
                    cand = (2, grams / (amount * float(m.group(1)) * 29.5735))
            if cand and (best is None or cand[0] < best[0]):
                best = cand
        return None if best is None else best[1]


def clean_measure(desc):
    d = desc.lower().strip()
    d = re.sub(r"\s+", " ", d)
    return d


# ---------------------------------------------------------------- helpers

def round_sig(x, sig=3):
    """At most `sig` significant digits; returns int when the value is integral."""
    if x == 0:
        return 0
    digits = sig - int(math.floor(math.log10(abs(x)))) - 1
    v = round(x, digits)
    if digits <= 0 or v == int(v):
        return int(v)
    return v


def round_nutrients(n):
    out = OrderedDict()
    for key in NUTRIENTS:
        if key not in n or n[key] is None:
            continue
        v = n[key]
        if v < 0:
            v = 0.0
        out[key] = int(round(v)) if key == "energy" else round_sig(v)
    return out


def round_amount(x):
    """Portion amounts: whole numbers from 10 up (half up), else 2 significant digits."""
    if x >= 9.95:
        return int(math.floor(x + 0.5))
    return round_sig(x, 2)


def parse_list(s):
    return [p.strip() for p in s.split("|") if p.strip()] if s else []


def parse_notes_options(notes):
    """Options embedded in the notes column, e.g. 'density=1.03'."""
    opts = {}
    for m in re.finditer(r"\b(density)=([0-9.]+)", notes or ""):
        opts[m.group(1)] = float(m.group(2))
    return opts


# ---------------------------------------------------------------- portions

def derive_portions(weights, unit_density=None):
    """Household portions from WEIGHT.txt rows -> [(en, de, amount in the food's unit)], at most 4."""
    found = []
    seen_labels = set()
    for _seq, amount, desc, grams in weights:
        d = clean_measure(desc)
        label = None
        # "fruit (2-1/8" dia)" -> "fruit"; "potato medium (...)" -> "potato medium"
        base = re.sub(r"\(.*?\)", "", d).strip(" ,")
        base = re.sub(r"\s+", " ", base)
        # sizes: "medium", "large whole", "fruit, medium", "potato small", "croissant, large", "egg, large"
        m = re.match(r"^(?:(?:fruit|potato|croissant|egg|whole|bagel|muffin|roll|bun|pepper|onion|tomato|"
                     r"apple|banana|carrot|pear|peach|avocado|orange|cucumber|squash)[ ,]+)?"
                     r"(extra small|extra large|small|medium|large|jumbo)\b", base)
        if m and not re.search(r"\b(cup|slice|stalk|leaf|strip|spear|wedge|sprig|ring|scoop)\b", base):
            for word, en, de, prio in _SIZE:
                if m.group(1) == word:
                    label = (en, de, prio)
                    break
        if label is None:
            first = re.split(r"[ ,]", base)[0] if base else ""
            if first in _PIECE_WORDS:
                en, de = _PIECE_WORDS[first]
                if first in ("slice", "slices") and re.search(r"\b(thin|very thin|crust not eaten|large|thick)\b", base):
                    continue
                label = (en, de, _PIECE_PRIORITY.get(en, 20))
        if label is None:
            continue
        en, de, prio = label
        if en in seen_labels:
            continue
        per_unit = grams / amount
        if unit_density:
            per_unit = per_unit / unit_density
        seen_labels.add(en)
        found.append((en, de, per_unit, prio))
    # "extra small/extra large/jumbo" only when USDA has no plain small/medium/large
    if any(p[0] in ("small", "medium", "large") for p in found):
        found = [p for p in found if p[0] not in ("extra small", "extra large")]
    found.sort(key=lambda p: p[3])
    out, amounts = [], set()
    for en, de, amt, prio in found:
        r = round_amount(amt)
        if r in amounts or r <= 0:
            continue
        amounts.add(r)
        out.append((en, de, r))
        if len(out) == MAX_PORTIONS:
            break
    return out


def parse_portions(spec, derived, where):
    """Catalog portions column: empty = derived; '-' = none; tokens: auto | @profile | en/de=amount."""
    if spec is None or spec.strip() == "":
        return list(derived)
    spec = spec.strip()
    if spec == "-":
        return []
    out = []
    for tok in parse_list(spec):
        if tok == "auto":
            out.extend(derived)
        elif tok.startswith("@"):
            name = tok[1:]
            if name not in PROFILES:
                die("%s: unknown portion profile %s" % (where, tok))
            out.extend(PROFILES[name])
        else:
            m = re.match(r"^(.+?)/(.+?)=([0-9.]+)$", tok)
            if not m:
                die("%s: bad portion %r (expected en/de=amount)" % (where, tok))
            out.append((m.group(1).strip(), m.group(2).strip(), round_amount(float(m.group(3)))))
    # de-duplicate by en label, keep order, cap
    res, seen = [], set()
    for en, de, amt in out:
        if en in seen:
            continue
        seen.add(en)
        res.append((en, de, amt))
    return res[:MAX_PORTIONS]


# One-tap logging uses the first portion. A single almond (1.2 g) or grape (5 g) is a poor default
# when a handful or a bowl exists, so such a portion moves to the front; the count portion stays
# available ("2 almonds" still means two pieces in quick add).
_COUNT_LABELS = {"piece", "grape", "half", "pod", "sprig", "ring", "floret", "square"}
_TYPICAL_LABELS = ("handful", "bowl", "pack", "serving", "cup")


def typical_first(portions):
    if len(portions) < 2:
        return portions
    first_en, _, first_amount = portions[0]
    if first_en.split(" ")[0] not in _COUNT_LABELS or first_amount >= 8:
        return portions
    for index, (en, de, amount) in enumerate(portions[1:], start=1):
        if amount >= 15 and en.split(" ")[0] in _TYPICAL_LABELS:
            return [portions[index]] + portions[:index] + portions[index + 1:]
    return portions


def portions_json(portions):
    return [OrderedDict([("en", en), ("de", de), ("amount", amt)]) for en, de, amt in typical_first(list(portions))]


# ---------------------------------------------------------------- catalog (USDA)

CATALOG_COLUMNS = ["ndb", "en", "de", "aliases", "cat", "unit", "portions", "notes"]


def read_catalog(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        header = None
        for lineno, line in enumerate(f, 1):
            line = line.rstrip("\n").rstrip("\r")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.split("\t")
            if header is None:
                header = [c.strip().split("(")[0] for c in cells]
                if header[:6] != CATALOG_COLUMNS[:6]:
                    die("%s: unexpected header %r" % (path, cells))
                continue
            cells += [""] * (len(CATALOG_COLUMNS) - len(cells))
            row = dict(zip(CATALOG_COLUMNS, [c.strip() for c in cells[:len(CATALOG_COLUMNS)]]))
            row["_where"] = "%s:%d" % (os.path.basename(path), lineno)
            rows.append(row)
    return rows


def build_usda_food(sr, row, warnings):
    ndb = row["ndb"]
    where = row["_where"]
    if not re.match(r"^\d{5}$", ndb):
        die("%s: bad NDB number %r" % (where, ndb))
    n = sr.per100g(ndb)
    unit = row["unit"] or "g"
    if unit not in ("g", "ml"):
        die("%s: unit must be g or ml" % where)
    opts = parse_notes_options(row["notes"])
    density = None
    if unit == "ml":
        density = opts.get("density") or sr.density(ndb)
        if density is None:
            density = 1.0
            warnings.append("%s %s: no volume weight in WEIGHT.txt, density 1.0 assumed" % (ndb, row["en"]))
        n = OrderedDict((k, v * density) for k, v in n.items())
    derived = derive_portions(sr.weights.get(ndb, []), density if unit == "ml" else None)
    portions = parse_portions(row["portions"], derived, where)
    food = OrderedDict()
    food["id"] = "usda:" + ndb
    food["en"] = row["en"]
    food["de"] = row["de"]
    food["aliases"] = parse_list(row["aliases"])
    food["cat"] = row["cat"]
    food["unit"] = unit
    if unit == "ml":
        food["density"] = round(density, 3)
    food["n"] = round_nutrients(n)
    food["portions"] = portions_json(portions)
    food["src"] = "usda"
    return food


# ---------------------------------------------------------------- extras (recipe / label)

def ingredient_grams(sr, ing, where):
    if "g" in ing:
        return float(ing["g"])
    if "ml" in ing:
        d = ing.get("density") or sr.density(ing["ndb"])
        if d is None:
            die("%s: ingredient %s given in ml but has no volume weight; give density" % (where, ing["ndb"]))
        return float(ing["ml"]) * d
    die("%s: ingredient %s needs g or ml" % (where, ing.get("ndb")))


# Ingredients whose missing USDA values are true zeros (water, salt, sugar).
KNOWN_ZERO_NDB = {"14411", "14429", "14555", "02047", "19335", "19336"}
# A recipe nutrient is reported only if the ingredients lacking a value for it make up at most
# this share of the raw recipe mass (their contribution is then counted as 0).
MAX_MISSING_SHARE = 0.10


def compute_recipe(sr, recipe, unit, where):
    """Return (nutrients per 100 g or 100 ml, density or None, raw_g, cooked_g)."""
    totals = {k: 0.0 for k in NUTRIENTS}
    missing_g = {k: 0.0 for k in NUTRIENTS}
    raw_g, raw_ml = 0.0, 0.0
    for ing in recipe["ingredients"]:
        g = ingredient_grams(sr, ing, where)
        raw_g += g
        if "ml" in ing:
            raw_ml += float(ing["ml"])
        n = sr.per100g(ing["ndb"])
        for k in NUTRIENTS:
            if k in n:
                totals[k] += n[k] * g / 100.0
            elif ing["ndb"] not in KNOWN_ZERO_NDB and k not in ("alcohol", "caffeine"):
                missing_g[k] += g  # alcohol/caffeine: no value = none
    present = {k: missing_g[k] <= MAX_MISSING_SHARE * raw_g for k in NUTRIENTS}
    if "yield_g" in recipe:
        cooked_g = float(recipe["yield_g"])
    else:
        cooked_g = raw_g * float(recipe.get("yield", 1.0))
    if cooked_g <= 0:
        die("%s: recipe yield must be > 0" % where)
    lost_water = raw_g - cooked_g
    if "water" in totals:
        totals["water"] = max(0.0, totals["water"] - lost_water)
    if "alcohol_retention" in recipe:
        lost = totals["alcohol"] * (1.0 - float(recipe["alcohol_retention"]))
        totals["alcohol"] -= lost
        totals["energy"] -= 6.93 * lost  # USDA energy factor for ethanol
    density = None
    if unit == "ml":
        volume = float(recipe.get("yield_ml") or raw_ml)
        if volume <= 0:
            die("%s: ml recipe needs ingredients in ml or yield_ml" % where)
        density = cooked_g / volume
        base = volume
    else:
        base = cooked_g
    per100 = OrderedDict()
    for k in NUTRIENTS:
        if present[k] or k in REQUIRED:
            per100[k] = totals[k] * 100.0 / base
    # alcohol/caffeine only when some ingredient has it
    for k in ("alcohol", "caffeine"):
        if k in per100 and per100[k] == 0:
            has = any(k in sr.per100g(i["ndb"]) for i in recipe["ingredients"])
            if not has:
                del per100[k]
    return per100, density, raw_g, cooked_g


def label_nutrients(label, where):
    """Label values -> nutrients. EU 'carbs' exclude fiber; USDA's include it, so fiber is added."""
    n = OrderedDict()
    for k in NUTRIENTS:
        if k in label:
            n[k] = float(label[k])
    if "salt" in label and "sodium" not in n:
        n["sodium"] = float(label["salt"]) * 400.0  # g salt -> mg sodium (salt / 2.5 * 1000)
    if "carbsExclFiber" in label:
        n["carbs"] = float(label["carbsExclFiber"]) + float(label.get("fiber", 0.0))
    for k in REQUIRED:
        if k not in n:
            die("%s: label values need %s" % (where, k))
    return n


def build_extra_food(sr, item, warnings):
    where = "foods-extra.json:" + item.get("id", "?")
    for key in ("id", "en", "de", "cat", "src"):
        if key not in item:
            die("%s: missing %s" % (where, key))
    unit = item.get("unit", "g")
    density = None
    if item["src"] == "recipe":
        n, density, raw_g, cooked_g = compute_recipe(sr, item["recipe"], unit, where)
        if unit == "ml" and item["recipe"].get("density"):
            density = float(item["recipe"]["density"])
    elif item["src"] == "label":
        n = label_nutrients(item["label"], where)
        if unit == "ml":
            density = float(item.get("density", 1.0))
    else:
        die("%s: src must be recipe or label" % where)
    portions = parse_portions(item.get("portions", ""), [], where)
    food = OrderedDict()
    food["id"] = item["id"]
    food["en"] = item["en"]
    food["de"] = item["de"]
    food["aliases"] = list(item.get("aliases", []))
    food["cat"] = item["cat"]
    food["unit"] = unit
    if unit == "ml":
        food["density"] = round(density, 3)
    food["n"] = round_nutrients(n)
    food["portions"] = portions_json(portions)
    food["src"] = item["src"]
    if item.get("note"):
        food["note"] = item["note"]
    return food


# ---------------------------------------------------------------- validation

def validate(foods, warnings):
    errors = []
    ids, en_names, de_names = Counter(), Counter(), Counter()
    for f in foods:
        ids[f["id"]] += 1
        en_names[f["en"].casefold()] += 1
        de_names[f["de"].casefold()] += 1
    for k, c in ids.items():
        if c > 1:
            errors.append("duplicate id %s" % k)
    for k, c in en_names.items():
        if c > 1:
            errors.append("duplicate en name %r" % k)
    for k, c in de_names.items():
        if c > 1:
            errors.append("duplicate de name %r" % k)
    atwater = []
    for f in foods:
        tag = "%s (%s)" % (f["id"], f["en"])
        if f["cat"] not in CATEGORIES:
            errors.append("%s: invalid cat %r" % (tag, f["cat"]))
        for lang in ("en", "de"):
            name = f[lang]
            if not name or not name.strip():
                errors.append("%s: empty %s name" % (tag, lang))
            elif len(name) > MAX_NAME:
                errors.append("%s: %s name longer than %d chars: %r" % (tag, lang, MAX_NAME, name))
            elif name != name.strip() or "  " in name:
                errors.append("%s: stray spaces in %s name" % (tag, lang))
            if name.isupper() and len(name) > 4:
                errors.append("%s: all-caps %s name" % (tag, lang))
            if re.search(r"\b(NFS|includes USDA commodity|separable)\b", name, re.I):
                errors.append("%s: USDA jargon in %s name" % (tag, lang))
        if not re.match(r"^(usda:\d{5}|nina:[a-z0-9]+(-[a-z0-9]+)*)$", f["id"]):
            errors.append("%s: malformed id" % tag)
        if len(f["aliases"]) > MAX_ALIASES:
            errors.append("%s: more than %d aliases" % (tag, MAX_ALIASES))
        names = {f["en"].casefold(), f["de"].casefold()}
        seen = set()
        for a in f["aliases"]:
            if a.casefold() in names:
                errors.append("%s: alias %r repeats the name" % (tag, a))
            if a.casefold() in seen:
                errors.append("%s: duplicate alias %r" % (tag, a))
            seen.add(a.casefold())
        if f["unit"] not in ("g", "ml"):
            errors.append("%s: bad unit" % tag)
        if f["unit"] == "ml" and not (0.5 < f.get("density", 0) < 2.0):
            errors.append("%s: implausible density %r" % (tag, f.get("density")))
        n = f["n"]
        for k in REQUIRED:
            if k not in n:
                errors.append("%s: missing %s" % (tag, k))
        for k, v in n.items():
            if not isinstance(v, (int, float)) or v < 0 or math.isnan(v):
                errors.append("%s: bad value %s=%r" % (tag, k, v))
        if all(k in n for k in REQUIRED):
            calc = 4 * n["protein"] + 4 * n["carbs"] + 9 * n["fat"] + 7 * n.get("alcohol", 0)
            diff = abs(n["energy"] - calc)
            if diff > max(15.0, 0.2 * n["energy"]):
                atwater.append((f, calc, diff))
        if len(f["portions"]) > MAX_PORTIONS:
            errors.append("%s: more than %d portions" % (tag, MAX_PORTIONS))
        plabels = set()
        for p in f["portions"]:
            if not (p["amount"] > 0):
                errors.append("%s: portion %r amount must be > 0" % (tag, p["en"]))
            if not p["en"] or not p["de"]:
                errors.append("%s: portion label missing" % tag)
            if p["en"] in ("g", "100 g", "gram", "grams"):
                errors.append("%s: gram portion %r is not allowed" % (tag, p["en"]))
            if p["en"] in plabels:
                errors.append("%s: duplicate portion %r" % (tag, p["en"]))
            plabels.add(p["en"])
        if f["src"] not in SOURCES:
            errors.append("%s: bad src" % tag)
    return errors, atwater


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sr28", required=True, help="directory with the SR28 ASCII files")
    ap.add_argument("--out", default=os.path.join(ROOT, "Packages", "NinaCore", "Sources", "NinaCore", "Resources", "foods.json"))
    ap.add_argument("--catalog", default=os.path.join(ROOT, "data", "food-catalog.tsv"))
    ap.add_argument("--extras", default=os.path.join(ROOT, "data", "foods-extra.json"))
    ap.add_argument("--date", default=datetime.date.today().isoformat(), help="value of 'generated' (YYYY-MM-DD)")
    ap.add_argument("--report", help="also write a human-readable TSV report of every food to this path")
    args = ap.parse_args(argv)

    sr = SR28(args.sr28)
    warnings = []
    foods = []
    # Atwater deviations that were looked at: "atwater: <reason>" in the catalog notes,
    # "atwater": "<reason>" in an extra.
    reviewed = {}
    for row in read_catalog(args.catalog):
        food = build_usda_food(sr, row, warnings)
        m = re.search(r"\batwater:\s*([^;]+)", row["notes"])
        if m:
            reviewed[food["id"]] = m.group(1).strip()
        foods.append(food)
    with open(args.extras, encoding="utf-8") as f:
        extras = json.load(f, object_pairs_hook=OrderedDict)
    for item in extras["foods"]:
        foods.append(build_extra_food(sr, item, warnings))
        if item.get("atwater"):
            reviewed[item["id"]] = item["atwater"]
    foods.sort(key=lambda x: x["id"])

    errors, atwater = validate(foods, warnings)

    out = OrderedDict()
    out["version"] = 1
    out["generated"] = args.date
    out["sources"] = SOURCES
    out["foods"] = foods

    if errors:
        for e in errors:
            print("ERROR " + e)
        print("%d error(s); foods.json not written" % len(errors))
        return 1

    data = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(data)
        f.write("\n")

    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write("id\ten\tde\taliases\tcat\tunit\tkcal\tP\tC\tF\tportions\n")
            for x in foods:
                n = x["n"]
                f.write("\t".join([
                    x["id"], x["en"], x["de"], "|".join(x["aliases"]), x["cat"], x["unit"],
                    str(n["energy"]), str(n["protein"]), str(n["carbs"]), str(n["fat"]),
                    "; ".join("%s/%s=%s" % (p["en"], p["de"], p["amount"]) for p in x["portions"]),
                ]) + "\n")

    # summary
    cats = Counter(f["cat"] for f in foods)
    srcs = Counter(f["src"] for f in foods)
    print("foods: %d  (%s)" % (len(foods), ", ".join("%s %d" % (s, srcs[s]) for s in SOURCES)))
    for c in CATEGORIES:
        print("  %-13s %4d" % (c, cats.get(c, 0)))
    print("written: %s (%d bytes)" % (os.path.relpath(args.out, ROOT) if os.path.abspath(args.out).startswith(ROOT)
                                      else args.out, len(data.encode("utf-8")) + 1))
    for w in warnings:
        print("WARNING " + w)
    open_items = [(f, calc, diff) for f, calc, diff in atwater if f["id"] not in reviewed]
    print("Atwater check |energy - (4P + 4C + 9F + 7A)| > max(15 kcal, 20 %%): %d food(s), %d reviewed"
          % (len(atwater), len(atwater) - len(open_items)))
    for f, calc, diff in atwater:
        n = f["n"]
        why = reviewed.get(f["id"])
        print("  %s %-38s %4d kcal vs %4.0f (P %s C %s F %s fiber %s)%s" % (
            "ok  " if why is not None else "WARN", f["id"] + " " + f["en"][:24], n["energy"], calc,
            n["protein"], n["carbs"], n["fat"], n.get("fiber", "-"), ("  - " + why) if why else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
