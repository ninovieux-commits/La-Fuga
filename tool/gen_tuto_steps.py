"""Extrait les 22 étapes du tuto de main.py et les écrit en Dart.

Les étapes sont des données pures (positions, annotations, textes) : les
recopier à la main serait long et fragile. On exécute donc la fonction
`_build_tuto_steps` de Kivy telle quelle, dans un module isolé, et on
encapsule le JSON obtenu dans un fichier Dart généré — ainsi le tuto n'a
aucun fichier à charger au démarrage.

Usage : python3 tool/gen_tuto_steps.py ../lafuga/main.py
"""

import json
import sys

HEADER = '''/// Étapes du tuto — **fichier généré**, ne pas modifier à la main.
///
/// Produit par `tool/gen_tuto_steps.py` depuis `_build_tuto_steps` (main.py).
library;

/// Les étapes, au format JSON du client Kivy.
const String kTutoStepsJson = r\'\'\'
'''

FOOTER = "\n\'\'\';\n"


def extract(main_py: str) -> list:
    src = open(main_py, encoding="utf-8").read()
    start = src.index("_TUTO_NOTES = [")
    end = src.index("class TutoScreen")
    # Les textes sont traduits à l'affichage, comme dans l'app : ici on veut
    # la clé française, donc T() rend son argument tel quel.
    module = {"T": lambda s: s}
    exec(compile(src[start:end], "tuto", "exec"), module)
    return module["_build_tuto_steps"]()


def main() -> None:
    steps = extract(sys.argv[1])
    payload = json.dumps(steps, ensure_ascii=False, indent=1)
    if "'''" in payload:
        raise SystemExit("le JSON casserait le littéral Dart")

    with open("tool/extracted/tuto.json", "w", encoding="utf-8") as f:
        f.write(payload)
    with open("lib/ui/tuto/tuto_data.g.dart", "w", encoding="utf-8") as f:
        f.write(HEADER + payload + FOOTER)
    print(f"{len(steps)} étapes extraites")


if __name__ == "__main__":
    main()
