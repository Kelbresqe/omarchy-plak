"""i18n/*.json against the code: every key the UI asks for exists in en.json,
every catalog has the same keys, and plural entries carry the forms the
plural rules need. No shell, no Qt."""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "i18n")
fail = []

catalogs = {}
for name in sorted(os.listdir(I18N)):
    if name.endswith(".json"):
        with open(os.path.join(I18N, name), encoding="utf-8") as f:
            catalogs[name[:-5]] = json.load(f)
en = catalogs.get("en")
if en is None:
    print("test-i18n: no en.json")
    sys.exit(1)

# Keys used by the code: tr("key", …) / trn("key", …) in QML, describe() keys in Bridge.js.
used = set()
sources = [os.path.join(ROOT, "BarWidget.qml"), os.path.join(ROOT, "Panel.qml"), os.path.join(ROOT, "Bridge.js")]
sources += [os.path.join(ROOT, "views", n) for n in os.listdir(os.path.join(ROOT, "views")) if n.endswith(".qml")]
for path in sources:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    used |= set(re.findall(r'\btrn?\("([A-Za-z0-9_.]+)"', text))
    used |= set(re.findall(r'\bkey: "([A-Za-z0-9_.]+)"', text))

for key in sorted(used - set(en)):
    fail.append("used in code, missing from en.json: " + key)
for key in sorted(set(en) - used):
    fail.append("in en.json, not used by the code: " + key)

for lang, cat in catalogs.items():
    if set(cat) != set(en):
        fail.append("%s.json keys differ from en.json: %s" % (lang, sorted(set(cat) ^ set(en))))
    for key, value in cat.items():
        if isinstance(value, dict):
            if "other" not in value or not all(isinstance(v, str) and v for v in value.values()):
                fail.append("%s.json %s: plural entry needs a non-empty 'other'" % (lang, key))
            if lang in ("en", "tr") and "one" not in value:
                fail.append("%s.json %s: plural entry needs 'one'" % (lang, key))
        elif not isinstance(value, str) or not value:
            fail.append("%s.json %s: empty or not a string" % (lang, key))
        # Placeholders must match English, or .arg() fills the wrong thing.
        want = sorted(set(re.findall(r"%\d", json.dumps(en.get(key)))))
        got = sorted(set(re.findall(r"%\d", json.dumps(value))))
        if want != got:
            fail.append("%s.json %s: placeholders %s, en has %s" % (lang, key, got, want))

for f in fail:
    print("FAIL:", f)
print("test-i18n: %d keys, %d catalogs, %d problems" % (len(en), len(catalogs), len(fail)))
sys.exit(1 if fail else 0)
