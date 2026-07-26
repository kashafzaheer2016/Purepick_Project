#!/usr/bin/env python3
"""
patch_google_client_id.py
=========================
Run this ONCE after you create the Web Client ID in Google Cloud Console.

Usage:
    python patch_google_client_id.py 475901765248-YOURNEWID.apps.googleusercontent.com

What it patches:
    1. mobile_app/lib/screens/login_screen.dart  → serverClientId
    2. backend/.env                               → GOOGLE_CLIENT_ID
    3. backend/.env.example                       → GOOGLE_CLIENT_ID
"""
import sys
import re
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: python patch_google_client_id.py <WEB_CLIENT_ID>")
        print("Example: python patch_google_client_id.py 475901765248-abc123.apps.googleusercontent.com")
        sys.exit(1)

    web_client_id = sys.argv[1].strip()

    if not web_client_id.endswith('.apps.googleusercontent.com'):
        print(f"ERROR: '{web_client_id}' doesn't look like a valid Google Client ID")
        print("It should end with .apps.googleusercontent.com")
        sys.exit(1)

    # Paths — adjust if your project structure differs
    base = os.path.dirname(os.path.abspath(__file__))
    files = {
        'Flutter login screen': os.path.join(base, 'mobile_app', 'lib', 'screens', 'login_screen.dart'),
        'Backend .env':         os.path.join(base, 'backend', '.env'),
        'Backend .env.example': os.path.join(base, 'backend', '.env.example'),
    }

    print(f"\nPatching all files with Web Client ID:\n  {web_client_id}\n")

    for label, path in files.items():
        if not os.path.exists(path):
            print(f"  SKIP  {label} — file not found at {path}")
            continue

        with open(path) as f:
            content = f.read()

        # Replace any placeholder or old client ID in serverClientId line (Dart)
        content_new = re.sub(
            r"serverClientId: '[^']*'",
            f"serverClientId: '{web_client_id}'",
            content,
        )

        # Replace GOOGLE_CLIENT_ID in .env files
        content_new = re.sub(
            r'GOOGLE_CLIENT_ID=.*',
            f'GOOGLE_CLIENT_ID={web_client_id}',
            content_new,
        )

        if content_new != content:
            with open(path, 'w') as f:
                f.write(content_new)
            print(f"  ✅  {label} — updated")
        else:
            print(f"  ⚠   {label} — no matching pattern found (check file manually)")

    print("\nDone. Next steps:")
    print("  1. flutter clean && flutter pub get && flutter run")
    print("  2. Restart Django: python manage.py runserver")
    print("  3. Test Google Sign-In")


if __name__ == '__main__':
    main()
