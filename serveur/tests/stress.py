"""Stress concurrence : N requetes simultanees (dont des ecritures) sur le
serveur. Mesure erreurs, latences, FD, RSS du serveur."""
import json, os, sys, threading, time, urllib.request, urllib.error
PORT=int(sys.argv[1]); PID=int(sys.argv[2]); NTH=int(sys.argv[3]); DUR=int(sys.argv[4])
BASE="http://127.0.0.1:%d"%PORT
def post(path,payload,timeout=30):
    req=urllib.request.Request(BASE+path,data=json.dumps(payload).encode(),
                               headers={"Content-Type":"application/json"})
    t0=time.time()
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r:
            return json.loads(r.read()), time.time()-t0, None
    except Exception as e:
        return None, time.time()-t0, repr(e)[:120]
toks=[]
for i in range(NTH):
    p="st%03d"%i
    r,_,_=post("/register",{"pseudo":p,"password":"test1234"})
    if not (r or {}).get("ok"):
        r,_,_=post("/login",{"pseudo":p,"password":"test1234"})
    toks.append((r or {}).get("token"))
print("[stress] %d comptes"%len(toks),flush=True)
lat=[]; errs={}
STOP=time.time()+DUR
def worker(i):
    t=toks[i]
    while time.time()<STOP:
        for path,pl in (("/corr_list",{"token":t}),
                        ("/save_game",{"token":t,"game_uid":"u%d-%f"%(i,time.time()),
                                       "nmc_text":"x"*2000,"joueur1":"a","joueur2":"b"}),
                        ("/send_message",{"token":t,"pseudo":"st%03d"%((i+1)%NTH),"text":"hi"}),
                        ("/list_conversations",{"token":t}),
                        ("/set_theme",{"token":t,"theme":"insectes"})):
            r,d,e=post(path,pl)
            lat.append(d)
            if e: errs[e]=errs.get(e,0)+1
            elif not r.get("ok"): errs["app:"+str(r.get("error"))[:40]]=errs.get("app:"+str(r.get("error"))[:40],0)+1
ths=[threading.Thread(target=worker,args=(i,),daemon=True) for i in range(NTH)]
for t in ths: t.start()
def stat():
    try:
        rss=int([l for l in open("/proc/%d/status"%PID) if l.startswith("VmRSS")][0].split()[1])
        return rss, len(os.listdir("/proc/%d/fd"%PID))
    except Exception: return None,None
print("  t  RSS(ko)  FD   p50   p95   max  reqs  err",flush=True)
t0=time.time()
while time.time()<STOP:
    time.sleep(10)
    rss,fd=stat()
    if rss is None: print("!! MORT apres %ds"%(time.time()-t0),flush=True); break
    c=sorted(lat[-2000:]) or [0]
    print("%4d %7s %4s %5.0f %5.0f %5.0f %5d %5d"%(time.time()-t0,rss,fd,
        c[len(c)//2]*1000,c[int(len(c)*0.95)]*1000,c[-1]*1000,len(lat),sum(errs.values())),flush=True)
time.sleep(1)
print("\n=== erreurs ===",flush=True)
for k,v in sorted(errs.items(),key=lambda x:-x[1])[:12]: print("%6d  %s"%(v,k),flush=True)
