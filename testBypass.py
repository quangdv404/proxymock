import socket
import time

print("Testing Bypass CONNECT directly")
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(("127.0.0.1", 9090))
s.send(b"CONNECT config.teams.microsoft.com:443 HTTP/1.1\r\nHost: config.teams.microsoft.com:443\r\n\r\n")
resp = s.recv(4096)
print("Proxy response:", resp)

if b"200 Connection" in resp:
    print("Tunnel established. Trying to send a raw byte...")
    try:
        s.send(b"hello")
        time.sleep(1)
        resp2 = s.recv(4096)
        print("Response 2:", resp2)
    except Exception as e:
        print("Failed:", e)
