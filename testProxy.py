import socket
import ssl
import time

print("1. Testing CONNECT (MITM Disabled)")
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(("127.0.0.1", 9090))
s.send(b"CONNECT www.google.com:443 HTTP/1.1\r\nHost: www.google.com:443\r\n\r\n")
resp = s.recv(4096)
print("Proxy response:", resp)

if b"200 Connection" in resp:
    print("Testing TLS handshake...")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # ignore self-signed cert of proxy
    try:
        conn = ctx.wrap_socket(s, server_hostname="www.google.com")
        print("TLS handshake successful!")
        conn.send(b"GET / HTTP/1.1\r\nHost: www.google.com\r\n\r\n")
        http_resp = conn.recv(4096)
        print("App response (first 50):", http_resp[:50])
    except Exception as e:
        print("TLS handshake failed:", e)
