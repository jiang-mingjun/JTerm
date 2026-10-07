#!/usr/bin/env python3
"""SSH test server for JTerm smoke tests (tool/ssh_smoke.dart).

Self-contained: generates its own client key and SFTP root on first run.
Supports password auth (testuser/testpass), publickey auth (test_key),
a PTY echo shell, and an SFTP subsystem rooted at sftproot/.

Usage:  python3 tool/test_sshd.py   (listens on 127.0.0.1:2222)
Needs:  pip install paramiko
"""
import os
import socket
import subprocess
import threading
import time

import paramiko

BASE = '/tmp/jterm_ssh_test'
KEY_PATH = os.path.join(BASE, 'test_key')
ROOT = os.path.join(BASE, 'sftproot')

os.makedirs(ROOT, exist_ok=True)
if not os.path.exists(os.path.join(ROOT, 'readme.txt')):
    with open(os.path.join(ROOT, 'readme.txt'), 'w') as f:
        f.write('hello jterm sftp\n')
os.makedirs(os.path.join(ROOT, 'docs'), exist_ok=True)
if not os.path.exists(os.path.join(ROOT, 'docs', 'a.txt')):
    with open(os.path.join(ROOT, 'docs', 'a.txt'), 'w') as f:
        f.write('doc\n')
if not os.path.exists(KEY_PATH):
    subprocess.run(
        ['ssh-keygen', '-t', 'ed25519', '-N', '', '-q', '-f', KEY_PATH],
        check=True)

HOST_KEY = paramiko.RSAKey.generate(2048)
CLIENT_KEY = paramiko.Ed25519Key.from_private_key_file(KEY_PATH)
print('[server] host key fingerprint: %s' % HOST_KEY.get_fingerprint().hex(),
      flush=True)


class FSFTP(paramiko.SFTPServerInterface):
    def _realpath(self, path):
        return os.path.normpath(os.path.join(ROOT, path.lstrip('/')))

    def _stat_to_attrs(self, st):
        attrs = paramiko.SFTPAttributes()
        attrs.st_size = st.st_size
        attrs.st_uid = st.st_uid
        attrs.st_gid = st.st_gid
        attrs.st_mode = st.st_mode
        attrs.st_mtime = int(st.st_mtime)
        return attrs

    def list_folder(self, path):
        path = self._realpath(path)
        try:
            out = []
            for fname in os.listdir(path):
                # NOTE: stat() re-resolves paths, so stat the already-resolved
                # absolute path directly to avoid double-prefixing ROOT.
                attr = self._stat_to_attrs(os.stat(os.path.join(path, fname)))
                attr.filename = fname
                out.append(attr)
            return out
        except OSError as e:
            return self._convert_errno(e.errno)

    def stat(self, path):
        try:
            return self._stat_to_attrs(os.stat(self._realpath(path)))
        except OSError as e:
            return self._convert_errno(e.errno)

    def lstat(self, path):
        try:
            return self._stat_to_attrs(os.lstat(self._realpath(path)))
        except OSError as e:
            return self._convert_errno(e.errno)

    def open(self, path, flags, attr):
        path = self._realpath(path)
        try:
            mode = getattr(attr, 'st_mode', None) or 0o666
            fd = os.open(path, flags, mode)
        except OSError as e:
            return self._convert_errno(e.errno)
        if flags & os.O_WRONLY:
            fstr = 'ab' if flags & os.O_APPEND else 'wb'
        elif flags & os.O_RDWR:
            fstr = 'a+b' if flags & os.O_APPEND else 'r+b'
        else:
            fstr = 'rb'
        try:
            f = os.fdopen(fd, fstr)
        except OSError as e:
            return self._convert_errno(e.errno)
        fobj = paramiko.SFTPHandle(flags)
        fobj.filename = path
        fobj.readfile = f
        fobj.writefile = f
        return fobj

    def remove(self, path):
        try:
            os.remove(self._realpath(path))
            return paramiko.SFTP_OK
        except OSError as e:
            return self._convert_errno(e.errno)

    def rename(self, oldpath, newpath):
        try:
            os.rename(self._realpath(oldpath), self._realpath(newpath))
            return paramiko.SFTP_OK
        except OSError as e:
            return self._convert_errno(e.errno)

    def mkdir(self, path, attr):
        try:
            os.mkdir(self._realpath(path), 0o777)
            return paramiko.SFTP_OK
        except OSError as e:
            return self._convert_errno(e.errno)

    def rmdir(self, path):
        try:
            os.rmdir(self._realpath(path))
            return paramiko.SFTP_OK
        except OSError as e:
            return self._convert_errno(e.errno)

    def canonicalize(self, path):
        if not path.startswith('/'):
            path = '/' + path
        return os.path.normpath(path)


class Handler(paramiko.ServerInterface):
    def __init__(self):
        self.event = threading.Event()
        self.subsystem_ids = set()

    def check_auth_password(self, username, password):
        ok = username == 'testuser' and password == 'testpass'
        print('[auth] password %s -> %s' % (username, ok), flush=True)
        return paramiko.AUTH_SUCCESSFUL if ok else paramiko.AUTH_FAILED

    def check_auth_publickey(self, username, key):
        ok = username == 'testuser' and key == CLIENT_KEY
        print('[auth] publickey %s -> %s' % (username, ok), flush=True)
        return paramiko.AUTH_SUCCESSFUL if ok else paramiko.AUTH_FAILED

    def get_allowed_auths(self, username):
        return 'password,publickey'

    def check_channel_request(self, kind, chanid):
        if kind == 'session':
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_pty_request(self, channel, term, width, height,
                                  pixelwidth, pixelheight, modes):
        return True

    def check_channel_shell_request(self, channel):
        self.event.set()
        return True

    def check_channel_subsystem_request(self, channel, name):
        if name == 'sftp':
            self.subsystem_ids.add(channel.chanid)
            print('[server] subsystem request: %s (chanid=%s)'
                  % (name, channel.chanid), flush=True)
        return super().check_channel_subsystem_request(channel, name)


def serve(client, addr):
    transport = paramiko.Transport(client)
    transport.add_server_key(HOST_KEY)
    transport.set_subsystem_handler('sftp', paramiko.SFTPServer, FSFTP)
    handler = Handler()
    try:
        transport.start_server(server=handler)
    except Exception as e:  # noqa: BLE001
        print('[server] handshake error: %r' % e, flush=True)
        transport.close()
        return
    chan = transport.accept(20)
    if chan is None:
        print('[server] no channel accepted', flush=True)
        transport.close()
        return
    print('[server] channel opened', flush=True)
    # An sftp subsystem request instantiates its own handler as soon as it
    # arrives, so wait briefly and leave such channels alone.
    for _ in range(40):
        if chan.chanid in handler.subsystem_ids:
            print('[server] channel is sftp subsystem', flush=True)
            while transport.is_active():
                time.sleep(0.2)
            return
        if not transport.is_active():
            return
        time.sleep(0.05)
    chan.send('Welcome to JTerm smoke server\r\n')
    try:
        while True:
            data = chan.recv(4096)
            if not data:
                break
            print('[recv] %r' % data, flush=True)
            chan.send(data)
    except Exception:  # noqa: BLE001
        pass
    finally:
        chan.close()
        transport.close()


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 2222))
    server.listen(10)
    print('[server] listening on 127.0.0.1:2222', flush=True)
    while True:
        client, addr = server.accept()
        print('[server] connection from %s' % (addr,), flush=True)
        threading.Thread(target=serve, args=(client, addr), daemon=True).start()


if __name__ == '__main__':
    main()
