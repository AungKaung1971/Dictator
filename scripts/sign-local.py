#!/usr/bin/env python3
"""Sign with the persistent local identity, keeping its private key in Keychain."""
import pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
folder = pathlib.Path.home() / 'Library/Application Support/DictatorSigning'
keychain = pathlib.Path.home() / 'Library/Keychains/DictatorSigning.keychain-db'
if not (folder/'password').exists():
    raise SystemExit('Run python3 scripts/setup-signing.py once before building.')
result = subprocess.run(['/usr/bin/security', 'unlock-keychain', '-p', (folder/'password').read_text(), str(keychain)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if result.returncode: raise SystemExit('Cannot unlock local signing keychain; build outside the sandbox.')
subprocess.run(['/usr/bin/codesign', '--force', '--keychain', str(keychain), '--sign', 'Dictator Local Signing', '--options', 'runtime', '--entitlements', str(root/'Resources/Dictator.entitlements'), sys.argv[1]], check=True)
