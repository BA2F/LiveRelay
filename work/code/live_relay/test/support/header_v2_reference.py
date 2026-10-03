"""Independent cryptography/OpenSSL reference for public, fictional fixtures.
Run with the bundled Python runtime; does not read user vaults. cryptography 50.0.1.
"""
import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path

import cryptography
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


def enc(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def dec(text):
    return base64.urlsafe_b64decode(text + '=' * (-len(text) % 4))


def canon(obj):
    return json.dumps(obj, ensure_ascii=True, sort_keys=True, separators=(',', ':')).encode()


def hkdf(secret, salt, info):
    return HKDF(algorithm=SHA256(), length=32, salt=salt, info=info.encode()).derive(secret)


def argon(password, salt, memory=65536, iterations=3):
    return Argon2id(salt=salt, length=32, iterations=iterations,
                   lanes=1, memory_cost=memory).derive(password.encode())


def descriptor(header):
    d = {k: v for k, v in header.items() if k != 'headerMac'}
    d['branches'] = [{k: v for k, v in b.items() if k not in ('factorSlot', 'keySlot')}
                     for b in header['branches']]
    return hashlib.sha256(canon(d)).digest()


def aad(stage, digest, branch):
    return canon(['LiveRelay/Header/v2/' + stage, digest.hex(), branch])


def seal(clear, key, nonce, context):
    encrypted = AESGCM(key).encrypt(nonce, clear, context)
    return {'nonce': enc(nonce), 'cipherText': enc(encrypted[:-16]), 'mac': enc(encrypted[-16:])}


def open_slot(slot, key, context):
    return AESGCM(key).decrypt(dec(slot['nonce']), dec(slot['cipherText']) + dec(slot['mac']), context)


def verify(header, password, recovery, expected):
    digest = descriptor(header)
    unsigned = {k: v for k, v in header.items() if k != 'headerMac'}
    for b in header['branches']:
        if b['branchId'] == 'device':
            # Portable reader authenticates its descriptor and ciphertext via MAC,
            # but cannot execute Android Keystore operations.
            continue
        branch = b['branchId']
        factor = argon(password, dec(b['salt'])) if branch == 'password' else hkdf(
            recovery, dec(b['salt']), 'LiveRelay/Header/v2/RecoveryFactor')
        secret = open_slot(b['factorSlot'], factor, aad('factor', digest, branch))
        key = hkdf(secret, digest, 'LiveRelay/Header/v2/BranchKey/' + branch)
        master = open_slot(b['keySlot'], key, aad('master', digest, branch))
        assert hmac.compare_digest(master, expected)
        mac_key = hkdf(master, bytes.fromhex(header['vaultId']), 'LiveRelay/Header/v2/HeaderMac')
        assert hmac.compare_digest(hmac.new(mac_key, canon(unsigned), hashlib.sha256).digest(), dec(header['headerMac']))


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    vmk, recovery = bytes(range(32)), bytes(range(32, 64))
    checksum = hashlib.sha256(b'LiveRelay/RecoveryCredential/LRR1' + recovery).digest()[:4]
    recovery_text = 'LRR1-' + enc(recovery) + '-' + enc(checksum)
    assert len(recovery_text) == 55
    fixtures = []
    for kind, password, count in [('custom', 'fictional-password-中文-2026', None),
                                  ('diceware-cn-v1', 'aba adou afei age agong ahong', 6)]:
        h = {'formatVersion': 2, 'suite': 'lr-or-recovery-v2-evaluation',
             'vaultId': bytes(range(176, 192)).hex(), 'headerEpoch': 1,
             'keyGeneration': 1, 'createdAt': '2026-10-03T00:00:00.000Z',
             'dailyPolicy': 'any', 'biometricEnabled': False, 'passwordKind': kind,
             'wordCount': count, 'recoveryEnabled': True,
             'branches': [
                 {'branchId': 'password', 'kind': 'password',
                  'kdfProfile': 'argon2id-v19-m65536-t3-p1-l32', 'salt': enc(bytes(range(96, 112)))},
                 {'branchId': 'recovery', 'kind': 'recovery',
                  'kdfProfile': 'hkdf-sha256-lrr1', 'salt': enc(bytes(range(112, 128)))}]}
        digest = descriptor(h)
        for i, b in enumerate(h['branches']):
            branch = b['branchId']
            factor = argon(password, dec(b['salt'])) if i == 0 else hkdf(
                recovery, dec(b['salt']), 'LiveRelay/Header/v2/RecoveryFactor')
            secret = bytes(range(64 + i * 16, 96 + i * 16))
            b['factorSlot'] = seal(secret, factor, bytes(range(128 + i * 24, 140 + i * 24)), aad('factor', digest, branch))
            key = hkdf(secret, digest, 'LiveRelay/Header/v2/BranchKey/' + branch)
            b['keySlot'] = seal(vmk, key, bytes(range(140 + i * 24, 152 + i * 24)), aad('master', digest, branch))
        mac_key = hkdf(vmk, bytes.fromhex(h['vaultId']), 'LiveRelay/Header/v2/HeaderMac')
        h['headerMac'] = enc(hmac.new(mac_key, canon(h), hashlib.sha256).digest())
        verify(h, password, recovery, vmk)
        filename = 'custom.json' if kind == 'custom' else 'chinese.json'
        (output / filename).write_bytes(canon(h))
        fixtures.append({'file': filename, 'canonicalPassword': password,
                         'descriptorHash': digest.hex(),
                         'passwordFactorAad': aad('factor', digest, 'password').decode()})
    salt, nonce = bytes(range(16)), bytes(range(16, 28))
    p = 'fictional-legacy-password-2026'
    encrypted = AESGCM(argon(p, salt, 19456, 2)).encrypt(nonce, vmk, b'LiveRelay/VaultMasterKey/v1')
    legacy = {'formatVersion': 1, 'databaseCipher': 'sqlcipher', 'createdAt': '2026-10-03T00:00:00.000Z',
              'passwordKind': 'custom', 'wordCount': None, 'biometricEnabled': False,
              'kdf': {'algorithm': 'argon2id', 'version': 19, 'memoryKiB': 19456,
                      'iterations': 2, 'parallelism': 1, 'hashLength': 32,
                      'salt': base64.urlsafe_b64encode(salt).decode()},
              'passwordSlot': {'algorithm': 'aes-256-gcm', 'nonce': base64.urlsafe_b64encode(nonce).decode(),
                               'cipherText': base64.urlsafe_b64encode(encrypted[:-16]).decode(),
                               'mac': base64.urlsafe_b64encode(encrypted[-16:]).decode()}}
    (output / 'legacy.json').write_bytes(canon(legacy))
    cn_password = 'aba adou afei age agong ahong'
    cn_slot = AESGCM(argon(cn_password, salt, 19456, 2)).encrypt(nonce, vmk, b'LiveRelay/VaultMasterKey/v1')
    legacy_cn = json.loads(json.dumps(legacy))
    legacy_cn['passwordKind'], legacy_cn['wordCount'] = 'diceware-cn-v1', 6
    legacy_cn['passwordSlot']['cipherText'] = base64.urlsafe_b64encode(cn_slot[:-16]).decode()
    legacy_cn['passwordSlot']['mac'] = base64.urlsafe_b64encode(cn_slot[-16:]).decode()
    (output / 'legacy-chinese.json').write_bytes(canon(legacy_cn))

    (output / 'vectors.json').write_text(json.dumps(
        {'generator': 'Python cryptography ' + cryptography.__version__, 'fixtures': fixtures,
         'recoveryCredential': recovery_text, 'masterKey': enc(vmk), 'legacyPassword': p, 'legacyChinesePassword': cn_password},
        ensure_ascii=False, indent=2) + '\n')
    print('Generated and independently verified fictional header fixtures')


if __name__ == '__main__':
    cli = argparse.ArgumentParser()
    cli.add_argument('--generate', type=Path)
    cli.add_argument('--verify', type=Path)
    cli.add_argument('--password')
    cli.add_argument('--recovery')
    cli.add_argument('--master-key')
    args = cli.parse_args()
    if args.generate:
        generate(args.generate)
    if args.verify:
        raw = args.verify.read_bytes()
        header = json.loads(raw)
        assert canon(header) == raw
        recovery = dec(args.recovery[5:48])
        checksum = hashlib.sha256(b'LiveRelay/RecoveryCredential/LRR1' + recovery).digest()[:4]
        assert enc(checksum) == args.recovery[49:]
        verify(header, args.password, recovery, dec(args.master_key))
        print('Dart-written fictional header verified through both independent branches')
