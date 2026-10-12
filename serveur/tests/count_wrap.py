"""Compte les appels a sqlite3.connect() et les requetes executees, puis lance
server.py. Le total est expose par la route /dbcount ajoutee a la volee."""
import sqlite3, runpy, sys, threading
CPT = {"connect": 0, "execute": 0}
_connect = sqlite3.connect
class _Cur(sqlite3.Cursor):
    def execute(self, *a, **kw):
        CPT["execute"] += 1
        return sqlite3.Cursor.execute(self, *a, **kw)
    def executemany(self, *a, **kw):
        CPT["execute"] += 1
        return sqlite3.Cursor.executemany(self, *a, **kw)


class _Conn(sqlite3.Connection):
    def execute(self, *a, **kw):
        CPT["execute"] += 1
        return sqlite3.Connection.execute(self, *a, **kw)
    def cursor(self, *a, **kw):
        kw.setdefault("factory", _Cur)
        return sqlite3.Connection.cursor(self, *a, **kw)
def connect(*a, **kw):
    CPT["connect"] += 1
    kw["factory"] = _Conn
    return _connect(*a, **kw)
sqlite3.connect = connect

import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(CPT).encode()
        if self.path == "/reset":
            CPT["connect"] = 0; CPT["execute"] = 0
            body = b'{"reset":true}'
        self.send_response(200); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
threading.Thread(target=lambda: http.server.HTTPServer(
    ("127.0.0.1", int(sys.argv[1])), H).serve_forever(), daemon=True).start()
sys.argv = ["server.py"]
runpy.run_path("server.py", run_name="__main__")
