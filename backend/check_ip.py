import socket
hostname = socket.gethostname()
local_ip = socket.gethostbyname(hostname)
print(f"DEBUG: Your Laptop IP is: {local_ip}")

# Try to find all IPs (in case of multiple adapters)
ips = socket.gethostbyname_ex(hostname)[2]
print(f"DEBUG: All available IPs: {ips}")

with open('my_ip.txt', 'w') as f:
    f.write(f"Laptop IP: {local_ip}\nAll IPs: {ips}")
