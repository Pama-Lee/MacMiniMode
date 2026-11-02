"""A slow response reader must release the service's serial socket worker."""
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import threading
import time
import uuid

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mmm-write-', dir='/tmp') as tmp:
    path = pathlib.Path(tmp)
    sock = str(path / 'control.sock')
    tasks = [dict(id=str(i), uid=os.getuid(), name='n' * 256, source='s' * 128,
                  mode='auto', started=0, suspended=False) for i in range(256)]
    state = path / 'state.json'
    state.write_text(json.dumps(dict(version=1, mode='auto', tasks=tasks, retired=[],
        settings=dict(enabled=False, threshold=20, restore=False), restoreManual=False)))
    service = subprocess.Popen([
        str(root / 'work/tests/macmini-moded'), '--dry-run', '--simulate-power=ac',
        '--socket=' + sock, '--state-file=' + str(state),
        '--notify-prefix=com.macminimode.test.' + uuid.uuid4().hex,
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    stop = threading.Event()
    receiver = None
    slow = socket.socket(socket.AF_UNIX)
    received = bytearray()
    stall = os.environ.get('MACMINIMODE_TEST_STALL') == '1'
    try:
        for _ in range(100):
            if pathlib.Path(sock).exists():
                break
            if service.poll() is not None:
                raise RuntimeError(service.stderr.read().decode())
            time.sleep(.05)
        slow.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
        slow.settimeout(.5)
        slow.connect(sock)
        started = time.monotonic()
        slow.sendall(b'{"operation":"status"}\n')

        def drain():
            while not stop.wait(.1):
                try:
                    chunk = slow.recv(512)
                    if not chunk:
                        return
                    received.extend(chunk)
                except socket.timeout:
                    continue
                except OSError:
                    return

        if not stall:
            receiver = threading.Thread(target=drain)
            receiver.start()
        time.sleep(.2)
        with socket.socket(socket.AF_UNIX) as normal:
            normal.settimeout(7)
            normal.connect(sock)
            normal.sendall(b'{"operation":"status"}\n')
            chunks = b''
            while b'\n' not in chunks:
                part = normal.recv(8192)
                assert part, 'queued request lost its response'
                chunks += part
            result = json.loads(chunks)
            elapsed = time.monotonic() - started
            assert result['ok'] and result['status']['totalTasks'] == 256, result
            assert 4 <= elapsed < 6.5, elapsed
            if not stall:
                assert len(received) > 0 and b'\n' not in received, 'slow reply unexpectedly completed'
        print(f'PASS: {"stalled" if stall else "slow"} response reader released worker; full queued status completed in {elapsed:.2f}s')
    finally:
        stop.set()
        if receiver is not None:
            receiver.join(timeout=2)
        slow.close()
        service.terminate()
        service.wait(timeout=5)
