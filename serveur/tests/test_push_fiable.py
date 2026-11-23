# -*- coding: utf-8 -*-
"""Une notification perdue est reessayee, et un echec se dit.

CE TEST NE TOUCHE RIEN. Il n'a besoin ni du serveur de production ni meme
d'un `server.py` : il fabrique un serveur de poche qui porte exactement les
deux motifs du patch, lui applique `patch_push_fiable.py`, puis execute le
resultat avec un faux Firebase qui echoue a volonte. C'est donc le VRAI code
livre qui est mesure, et non une copie de sa logique.

    python3 tests/test_push_fiable.py
"""
import os
import subprocess
import sys
import tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
SERVEUR = os.path.dirname(ICI)

# Le serveur de poche : `_send_push` tel qu'il est en production, et la ligne
# de la reserve d'envoi. Rien d'autre.
POCHE = u'''# -*- coding: utf-8 -*-


def _send_push(fcm_token, title, body, data=None):
    """Envoie une notification push a un appareil. Ne leve jamais d'exception."""
    if not fcm_token:
        return
    try:
        if not _init_fcm():
            return
        from firebase_admin import messaging
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=fcm_token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    title=title, body=body, icon="notif_icon"),
            ),
            data={k: str(v) for k, v in (data or {}).items()},
        )
        messaging.send(message)
    except Exception as e:
        print("[FCM] envoi echoue :", e)


# Reserve de taches d'envoi de notifications (bornee : voir _notify_user).
_FCM_POOL = gevent.pool.Pool(int(os.environ.get("LAFUGA_FCM_POOL", "20")))
'''


class _Erreur(Exception):
    """Une panne passagere : reseau coupe, 503, Firebase qui tousse."""


class UnregisteredError(Exception):
    """Le jeton n'existe plus. Le nom compte : le patch le reconnait par la."""


class _Messaging(object):
    """Un Firebase de poche, qui echoue autant de fois qu'on lui dit."""

    def __init__(self, pannes):
        # `pannes` : la liste des exceptions a lever, dans l'ordre. Epuisee,
        # l'envoi reussit.
        self.pannes = list(pannes)
        self.essais = 0
        self.envoyes = []

    # Les classes que `_send_push` assemble : elles n'ont qu'a exister.
    def Message(self, **kw):
        return kw

    def Notification(self, **kw):
        return kw

    def AndroidConfig(self, **kw):
        return kw

    def AndroidNotification(self, **kw):
        return kw

    def send(self, message):
        self.essais += 1
        if self.pannes:
            raise self.pannes.pop(0)
        self.envoyes.append(message)


def _applique(chemin_poche):
    r = subprocess.run(
        [sys.executable, os.path.join(SERVEUR, "patch_push_fiable.py"),
         chemin_poche],
        capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit("le patch a refuse de s'appliquer")


def _execute(source, messaging):
    """Execute le serveur de poche corrige, avec ses dehors en toc."""
    dormi = []

    class _Pool(object):
        def Pool(self, n):
            return None

    class _Gevent(object):
        pool = _Pool()

        @staticmethod
        def sleep(s):
            dormi.append(s)

    # `from firebase_admin import messaging` doit trouver son module.
    import types
    faux = types.ModuleType("firebase_admin")
    faux.messaging = messaging
    sys.modules["firebase_admin"] = faux

    sorties = []

    def _print(*a, **kw):
        sorties.append(" ".join(str(x) for x in a))

    portee = {
        "gevent": _Gevent,
        "os": os,
        "_init_fcm": lambda: True,
        "print": _print,
    }
    exec(compile(source, "poche", "exec"), portee)
    return portee, sorties, dormi


def _cas(nom, pannes):
    with tempfile.TemporaryDirectory() as d:
        chemin = os.path.join(d, "poche.py")
        with open(chemin, "w", encoding="utf-8") as f:
            f.write(POCHE)
        _applique(chemin)
        with open(chemin, encoding="utf-8") as f:
            corrige = f.read()
    messaging = _Messaging(pannes)
    portee, sorties, dormi = _execute(corrige, messaging)
    portee["_send_push"]("jeton-de-test-ABCD1234", "La Fuga", "A vous de jouer")
    return messaging, sorties, dormi


def main():
    # 1. Tout va bien : un seul essai, rien dans le journal.
    m, sorties, dormi = _cas("tout va bien", [])
    assert m.essais == 1, m.essais
    assert len(m.envoyes) == 1
    assert not sorties, sorties
    assert not dormi
    print("OK  un envoi qui passe du premier coup ne reessaie pas")

    # 2. CE QUI MANQUAIT : deux pannes passageres, puis ca passe.
    m, sorties, dormi = _cas("deux pannes", [_Erreur("503"), _Erreur("reseau")])
    assert m.essais == 3, m.essais
    assert len(m.envoyes) == 1, "la notification doit finir par partir"
    assert dormi == [0.5, 2.0], dormi
    assert any("reussi au 3" in s for s in sorties), sorties
    assert not any("ECHEC" in s for s in sorties), sorties
    print("OK  deux pannes passageres ne perdent plus la notification")

    # 3. Panne permanente : trois essais, puis un echec qui se dit.
    m, sorties, dormi = _cas("panne totale", [_Erreur("x") for _ in range(9)])
    assert m.essais == 3, m.essais
    assert not m.envoyes
    echec = [s for s in sorties if "ECHEC" in s]
    assert len(echec) == 1, sorties
    assert "3 essai(s)" in echec[0], echec
    assert "ABCD1234" in echec[0], "le journal doit nommer l'appareil"
    assert "La Fuga" in echec[0], "et le titre, pour retrouver quel message"
    print("OK  un echec complet laisse une trace utilisable")

    # 4. Jeton mort : on n'insiste pas, et on le dit.
    m, sorties, dormi = _cas("jeton mort", [UnregisteredError("token dead")])
    assert m.essais == 1, "reessayer un jeton mort ne sert a rien"
    assert not dormi, "et ne doit pas tenir la place une seconde de plus"
    assert any("jeton mort" in s for s in sorties), sorties
    print("OK  un jeton mort s'arrete au premier essai et se signale")

    # 5. Et le patch refuse de s'appliquer deux fois, comme tous les autres.
    with tempfile.TemporaryDirectory() as d:
        chemin = os.path.join(d, "poche.py")
        with open(chemin, "w", encoding="utf-8") as f:
            f.write(POCHE)
        _applique(chemin)
        r = subprocess.run(
            [sys.executable, os.path.join(SERVEUR, "patch_push_fiable.py"),
             chemin],
            capture_output=True, text=True)
        assert r.returncode != 0, "un fichier deja corrige doit etre refuse"
        assert "REFUS" in r.stdout, r.stdout
    print("OK  un fichier deja corrige est refuse, rien n'est double")

    print("")
    print("Tout est vert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
