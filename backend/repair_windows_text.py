import os
from pathlib import Path

backend_dir = Path(r"D:\Purepick\backend")

for root, _, files in os.walk(backend_dir):
    if "venv_new" in root: continue
    for fl in files:
        if not fl.endswith(".py"): continue
        path = Path(root) / fl
        
        try:
            with open(path, 'rb') as f:
                raw = f.read()
            
            try:
                raw.decode('utf-8')
                continue
            except UnicodeDecodeError:
                pass
                
            try:
                text = raw.decode('windows-1252')
                if '\x00' not in text:
                    with open(path, 'w', encoding='utf-8') as f:
                        f.write(text)
                    print(f"Fixed Windows-1252 -> UTF-8: {path.name}")
            except Exception:
                pass
        except Exception:
            pass
print("✅ Final encoding repair complete.")
