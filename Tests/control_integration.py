"""Isolated service tests: never change host power settings or installed services."""
import json, os, pathlib, socket, subprocess, tempfile, time, uuid
root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mmm-', dir='/tmp') as tmp:
    path = pathlib.Path(tmp)
    sock = str(path/'control.sock')
    state = path/'state.json'
    sim = path/'power.json'
    def power(ac=True, battery=80, **extra):
        sim.write_text(json.dumps(dict(ac=ac, battery=battery, **extra)))
        if "p" in globals() and p.poll() is None: time.sleep(5.1)
    power()
    command = [str(root/'work/tests/macmini-moded'), '--dry-run', '--socket='+sock,
               '--state-file='+str(state), '--simulation-file='+str(sim),
               '--notify-prefix=com.macminimode.test.'+uuid.uuid4().hex]
    def start():
        p = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            try:
                call('status'); return p
            except (OSError, ValueError):
                if p.poll() is not None: raise RuntimeError(p.stderr.read().decode())
                time.sleep(.05)
        raise RuntimeError('service did not start')
    def call(operation, **kwargs):
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(8); s.connect(sock)
            s.sendall(json.dumps(dict(operation=operation, **kwargs)).encode()+b'\n')
            chunks=b''
            while b'\n' not in chunks:
                part=s.recv(4096)
                if not part: raise ValueError('missing response')
                chunks+=part
            return json.loads(chunks)
    def good(op, **kwargs):
        r=call(op, **kwargs); assert r['ok'], r
        assert r['saved'] and r['applied'], r
        return r['status']
    p=start()
    try:
        assert good('status')['simulated']
        assert good('begin_task', id='a', name='Build', source='Codex')['mode']=='auto'
        assert good('begin_task', id='b', name='Test', source='Claude', mode='on')['totalTasks']==2
        assert good('end_task', id='a')['mode']=='on'
        p.terminate(); p.wait(timeout=5); p=start()
        assert good('status')['totalTasks']==1
        assert good('end_task', id='b')['mode']=='off'
        good('set_mode', mode='auto')
        assert good('end_task', id='b')['mode']=='auto'
        assert not call('begin_task', id='b', name='Test', source='Claude')['ok']
        assert not call('bogus')['ok']
        assert not call('configure', settings=dict(enabled=True,threshold=9,restore=False))['ok']
        good('configure', settings=dict(enabled=True,threshold=20,restore=True))
        good('begin_task', id='c', name='Battery work', source='Codex', mode='on')
        power(False,20)
        s=good('status'); assert s['mode']=='auto' and s['sleepDisabled'] is False and s['waitingForRecovery']
        power(False,24); assert good('status')['mode']=='auto'
        power(False,25); assert good('status')['mode']=='on'
        power(False,19); assert good('status')['mode']=='auto'
        good('end_task', id='c'); power(); assert good('status')['mode']=='off'
        good('configure', settings=dict(enabled=False,threshold=20,restore=False))
        power(False,10); s=good('set_mode',mode='on'); assert s['mode']=='on' and not s['sleepDisabled']
        power(False,14); assert not good('status')['sleepDisabled']
        power(False,15); assert good('status')['sleepDisabled']
        good('set_mode',mode='off'); power(failApply=True)
        r=call('set_mode',mode='on'); assert not r['ok'] and r['saved'] and not r['applied'], r
        power(); assert good('status')['mode']=='on'
        good('begin_task',id='d',name='Old task',source='Codex')
        good('set_mode',mode='on'); assert good('end_task',id='d')['mode']=='on'
        # Force atomic persistence failure without relying on running as a non-root user.
        state.unlink(); state.mkdir()
        r=call('set_mode',mode='off'); assert not r['ok'] and not r['saved'],r
        assert call('status')['status']['mode']=='on'
        state.rmdir()
        good('set_mode',mode='off')
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(8); client.connect(sock); client.sendall(b'not-json\n')
            assert not json.loads(client.recv(4096))['ok']
        print('PASS: service persistence, two clients, final release, stale requests, settings validation')
        print('PASS: simulated power transitions, original 10/15 protection, application/save failures, malformed requests')
    finally:
        p.terminate(); p.wait(timeout=5)
    env=dict(os.environ,MACMINIMODE_SOCKET=sock)
    r=subprocess.run([str(root/'work/tests/macminimode-control'),'status'],env=env,capture_output=True,text=True)
    assert r.returncode!=0 and not json.loads(r.stdout)['ok']
    print('PASS: unavailable service returns structured failure')
