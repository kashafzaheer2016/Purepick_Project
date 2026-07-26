import os
from pathlib import Path

backend_dir = Path(r"D:\Purepick\backend")

for root, _, files in os.walk(backend_dir):
    for fl in files:
        if fl.endswith(".py"):
            path = Path(root) / fl
            if path.name == "build_purepick_db_local.py":
                continue # Already UTF-8
            # try to read as utf-16
            try:
                with open(path, 'rb') as f:
                    raw = f.read()
                # if it contains a utf-16 BOM or zero bytes, it's likely utf-16
                text = raw.decode('utf-16')
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(text)
                print(f"Converted encoding to UTF-8: {path}")
            except Exception:
                pass
print("✅ Encoding scan complete.")
