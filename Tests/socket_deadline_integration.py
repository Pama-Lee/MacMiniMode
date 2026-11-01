"""A trickling request must release the serial worker within its total deadline."""
import json
import pathlib
import socket
import subprocess
import tempfile
import threading
import time
import uuid

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mmm-deadline-', dir='/tmp') as tmp:
    path = pathlib.Path(tmp)
    sock = str(path / 'control.sock')
    service = subprocess.Popen([
        str(root / 'work/tests/macmini-moded'), '--dry-run', '--simulate-power=ac',
        '--socket=' + sock, '--state-file=' + str(path / 'state.json'),
        '--notify-prefix=com.macminimode.test.' + uuid.uuid4().hex,
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    stop = threading.Event()
    sender = None
    slow = socket.socket(socket.AF_UNIX)
    try:
        for _ in range(100):
            if pathlib.Path(sock).exists():
                break
            if service.poll() is not None:
                raise RuntimeError(service.stderr.read().decode())
            time.sleep(.05)
        slow.settimeout(8)
        slow.connect(sock)
        started = time.monotonic()
        slow.sendall(b'{')

        def trickle():
            while not stop.wait(.1):
                try:
                    slow.sendall(b' ')
                except OSError:
                    return

        sender = threading.Thread(target=trickle)
        sender.start()
        # Queue a normal request behind the incomplete first request.
        time.sleep(.2)
        with socket.socket(socket.AF_UNIX) as normal:
            normal.settimeout(7)
            normal.connect(sock)
            normal.sendall(b'{"operation":"status"}\n')
            chunks = b''
            while b'\n' not in chunks:
                part = normal.recv(4096)
                assert part, 'normal request lost its response'
                chunks += part
            response = json.loads(chunks)
            elapsed = time.monotonic() - started
            assert response['ok'] and response['status']['simulated'], response
            assert 4 <= elapsed < 6.5, elapsed
        failure = json.loads(slow.recv(4096))
        assert not failure['ok'] and not failure['saved'] and not failure['applied'], failure
        assert failure['error'] == 'socket_read_failed_or_timeout', failure
        print(f'PASS: trickling request timed out and queued status completed in {elapsed:.2f}s')
    finally:
        stop.set()
        if sender is not None:
            sender.join(timeout=2)
        slow.close()
        service.terminate()
        service.wait(timeout=5)
