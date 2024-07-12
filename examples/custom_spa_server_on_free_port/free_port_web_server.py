import http.server
from http.server import BaseHTTPRequestHandler
import socketserver
import sys

SERVER_PORT_STR = sys.argv[1] 
SERVER_PORT = int(SERVER_PORT_STR)

WEBUI_PORT_STR = sys.argv[2]

class MyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            f = open("." + self.path)
            content = f.read()
            self.send_response(200)
            if (self.path.endswith(".html")):
                self.send_header('Content-type','text/html')
                # now set webui port
                content = content.replace("[WEBUI_PORT]", WEBUI_PORT_STR)
            if (self.path.endswith(".js")):
                self.send_header('Content-type','text/javascript')
            self.send_header('cache-control', 'no-cache')
            self.end_headers()
            self.wfile.write(content.encode())
            f.close()
            return
        except IOError:
            self.send_error(404,'File Not Found: %s' % self.path)

with socketserver.TCPServer(("", SERVER_PORT), MyHandler) as httpd:
    print(f"Server started at http://localhost:{SERVER_PORT_STR}")
    httpd.serve_forever()
