#!/usr/bin/env python3
"""Create a persistent, local-only code-signing identity. Never changes system trust."""
import os, pathlib, secrets, subprocess, tempfile, shlex
root = pathlib.Path(__file__).resolve().parent.parent
folder = pathlib.Path.home() / 'Library/Application Support/DictatorSigning'
folder.mkdir(mode=0o700, exist_ok=True)
keychain = pathlib.Path.home() / 'Library/Keychains/DictatorSigning.keychain-db'

def run(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
if keychain.exists():
    print('Local signing identity already exists.')
    raise SystemExit()
password = secrets.token_urlsafe(32)
(folder / 'password').write_text(password)
os.chmod(folder / 'password', 0o600)
try:
    run(['/usr/bin/security', 'create-keychain', '-p', password, str(keychain)])
    run(['/usr/bin/security', 'set-keychain-settings', str(keychain)])
    with tempfile.TemporaryDirectory() as tmp:
        temp = pathlib.Path(tmp)
        config = temp / 'cert.cnf'
        config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Dictator Local Signing\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n')
        run(['/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:3072', '-nodes', '-days', '3650', '-config', str(config), '-keyout', str(temp/'key.pem'), '-out', str(temp/'cert.pem')])
        run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(temp/'key.pem'), '-in', str(temp/'cert.pem'), '-out', str(temp/'identity.p12'), '-passout', 'stdin'], input=(password+'\n').encode())
        run(['/usr/bin/security', 'import', str(temp/'identity.p12'), '-k', str(keychain), '-P', password, '-x', '-T', '/usr/bin/codesign'])
        (folder/'certificate.pem').write_bytes((temp/'cert.pem').read_bytes())
    run(['/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain)])
    os.chmod(keychain, 0o600)
    current = shlex.split(run(['/usr/bin/security', 'list-keychains', '-d', 'user']).stdout.decode())
    if str(keychain) not in current:
        run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *current, str(keychain)])
    print('Created local code-signing identity; system trust unchanged.')
except subprocess.CalledProcessError as error:
    print('Signing setup failed:', error.stderr.decode(errors='replace'))
    raise SystemExit(1)
