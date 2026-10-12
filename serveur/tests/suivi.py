import json, sys, time, urllib.request, socketio
PORT=sys.argv[1]; BASE="http://127.0.0.1:%s"%PORT
def post(p,d):
    r=urllib.request.Request(BASE+p,data=json.dumps(d).encode(),headers={"Content-Type":"application/json"})
    return json.loads(urllib.request.urlopen(r,timeout=20).read())
def sante(): return json.loads(urllib.request.urlopen(BASE+"/health",timeout=20).read())
def compte(p):
    try: r=post("/register",{"pseudo":p,"password":"motdepasse"})
    except Exception: r={}
    if not r.get("ok"): r=post("/login",{"pseudo":p,"password":"motdepasse"})
    return r["token"]
t=compte("YJ0")
c=socketio.Client(reconnection=False)
c.connect(BASE,transports=["websocket"],wait_timeout=10)
c.emit("auth",{"token":t})
for i in range(16):
    time.sleep(1)
    e=sante()["etat"]
    print("t+%2ds connectes=%d sockets_eio=%d  client.connected=%s"
          % (i+1, e["connectes"], e["sockets_eio"], c.connected), flush=True)
c.disconnect()
