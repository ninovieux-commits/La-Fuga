import json, sys, urllib.request
JEU, CPT, N = sys.argv[1], sys.argv[2], int(sys.argv[3])
def post(path, payload):
    req = urllib.request.Request("http://127.0.0.1:%s%s" % (JEU, path),
        data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r: return json.loads(r.read())
def cpt(reset=False):
    u = "http://127.0.0.1:%s/%s" % (CPT, "reset" if reset else "")
    return json.loads(urllib.request.urlopen(u, timeout=10).read())
def compte(p):
    try: r = post("/register", {"pseudo": p, "password": "motdepasse"})
    except Exception: r = {}
    if not r.get("ok"): r = post("/login", {"pseudo": p, "password": "motdepasse"})
    return r["token"]
moi = compte("CMoi")
for i in range(N):
    t = compte("CAmi%02d" % i)
    post("/send_message", {"token": t, "pseudo": "CMoi", "text": "coucou %d" % i})
    post("/send_message", {"token": moi, "pseudo": "CAmi%02d" % i, "text": "salut"})
cpt(reset=True)
r = post("/list_conversations", {"token": moi})
c = cpt()
print("/list_conversations  %d conversations -> %2d connexions, %2d requetes  (%d rendues)"
      % (N, c["connect"], c["execute"], len(r.get("conversations", []))))
