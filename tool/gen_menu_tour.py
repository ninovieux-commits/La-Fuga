"""Extrait les étapes de la visite guidée du menu depuis main.py.

Les textes sont ceux de Kivy, mot pour mot : on exécute `_build_stops` de
`MenuTourOverlay` plutôt que de les recopier.

Usage : python3 tool/gen_menu_tour.py ../lafuga/main.py
"""

import json
import sys
import textwrap

HEADER = '''/// Visite guidée du menu — **fichier généré**, ne pas modifier à la main.
///
/// Produit par `tool/gen_menu_tour.py` depuis `MenuTourOverlay._build_stops`
/// (main.py) : les textes sont ceux de Kivy, mot pour mot.
library;

/// Les étapes, au format JSON du client Kivy.
const String kMenuTourJson = r\'\'\'
'''

FOOTER = "\n\'\'\';\n"


def extract(main_py: str) -> list:
    src = open(main_py, encoding="utf-8").read()
    start = src.index("    def _build_stops(self):")
    end = src.index("    def on_touch_down(self, touch):", start)
    body = textwrap.dedent(src[start:end]).replace("def _build_stops(self):", "def _build_stops():")
    module = {"T": lambda s: s}
    exec(compile(body, "tour", "exec"), module)
    return module["_build_stops"]()


def main() -> None:
    stops = extract(sys.argv[1])
    payload = json.dumps(stops, ensure_ascii=False, indent=1)
    if "'''" in payload:
        raise SystemExit("le JSON casserait le littéral Dart")

    with open("lib/ui/tuto/menu_tour.g.dart", "w", encoding="utf-8") as f:
        f.write(HEADER + payload + FOOTER)
    print(f"{len(stops)} étapes de visite extraites")


if __name__ == "__main__":
    main()
