"""Check preview routing using a fake socket service, including mutation rejection."""
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import threading

root = pathlib.Path(__file__).resolve().parents[1]
binary = str(root / 'work/tests/preview-tests')
base_env = dict(os.environ)
base_env.pop('MACMINIMODE_SOCKET', None)
for operation in ['status', 'set_mode', 'configure', 'end_task']:
    result = subprocess.run([binary, '--preview'], env=dict(base_env, TEST_OPERATION=operation),
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 1 and 'preview_socket_required' in result.stdout, result

with tempfile.TemporaryDirectory(prefix='mmm-preview-', dir='/tmp') as tmp:
    for simulated in [False, True]:
        for operation in ['status', 'set_mode', 'configure', 'end_task']:
            path = str(pathlib.Path(tmp) / 'service.sock')
            if os.path.exists(path):
                os.unlink(path)
            seen = []
            stop = threading.Event()
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(path)
                server.listen()
                server.settimeout(.1)

                def serve():
                    while not stop.is_set():
                        try:
                            client, _ = server.accept()
                        except socket.timeout:
                            continue
                        with client:
                            client.settimeout(2)
                            data = b''
                            while b'\n' not in data:
                                chunk = client.recv(4096)
                                if not chunk:
                                    break
                                data += chunk
                            seen.append(json.loads(data)['operation'])
                            response = dict(ok=True, saved=True, applied=True, status=dict(
                                mode='off', acPower=True, tasks=[], totalTasks=0,
                                settings=dict(enabled=False, threshold=20, restore=False),
                                waitingForRecovery=False, simulated=simulated))
                            client.sendall(json.dumps(response).encode() + b'\n')

                thread = threading.Thread(target=serve)
                thread.start()
                try:
                    result = subprocess.run([binary, '--preview'],
                        env=dict(base_env, MACMINIMODE_SOCKET=path, TEST_OPERATION=operation),
                        capture_output=True, text=True, timeout=5)
                    if simulated:
                        assert result.returncode == 0, result
                        assert seen == (['status'] if operation == 'status' else ['status', operation]), seen
                    else:
                        assert result.returncode == 1 and 'preview_requires_simulated_service' in result.stdout, result
                        assert seen == ['status'], seen
                finally:
                    stop.set()
                    thread.join(timeout=3)
                    assert not thread.is_alive()
print('PASS: preview status, mode/quit, settings and task actions reject live services and accept simulated services')
