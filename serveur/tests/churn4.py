import os, sys, time, socketio
PORT=int(sys.argv[1]); PID=int(sys.argv[2]); ROUNDS=int(sys.argv[3])
BASE="http://127.0.0.1:%d"%PORT
def rss():
    return int([l for l in open("/proc/%d/status"%PID) if l.startswith("VmRSS")][0].split()[1])
print("round  RSS(ko)  delta/round(o)",flush=True)
r0=rss(); t0=time.time()
for i in range(ROUNDS):
    c=socketio.Client(reconnection=False)
    try:
        c.connect(BASE,transports=["websocket"],wait_timeout=10); c.disconnect()
    except Exception as e: print(" err",repr(e),flush=True)
    if (i+1)%250==0:
        r=rss(); print("%5d %8d %10.0f  (%.0fs)"%(i+1,r,(r-r0)*1024.0/(i+1),time.time()-t0),flush=True)
