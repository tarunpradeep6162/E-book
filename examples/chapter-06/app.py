import json
import os
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ready = True

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ('/healthz', '/readyz', '/'):
            self.send_error(404)
            return
        code = 200 if self.path != '/readyz' or ready else 503
        body = json.dumps({'status': 'ok', 'service': 'orders-api'}).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = ThreadingHTTPServer(('0.0.0.0', int(os.getenv('PORT', '8080'))), Handler)

def stop(signum, frame):
    global ready
    ready = False
    # shutdown must run outside serve_forever's thread to avoid deadlock.
    threading.Thread(target=server.shutdown, daemon=True).start()

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    server.serve_forever()
finally:
    server.server_close()
