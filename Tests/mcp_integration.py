"""Two independent stdio clients against one dry-run service."""
import json, os, pathlib, select, subprocess, tempfile, time, uuid
root=pathlib.Path(__file__).resolve().parents[1]
binary=pathlib.Path(os.environ.get('MCP_BINARY', root/'MCP/.build/arm64-apple-macosx/release/macminimode-mcp'))
if not binary.exists():
    bindir=subprocess.check_output(['swift','build','--package-path',str(root/'MCP'),'-c','release','--show-bin-path'],text=True).strip()
    binary=pathlib.Path(bindir)/'macminimode-mcp'
class Client:
    def __init__(self,env,capabilities=None):
        self.p=subprocess.Popen([str(binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
        self.i=0
        r=self.call('initialize',dict(protocolVersion='2025-11-25',capabilities=capabilities or {},clientInfo={'name':'integration','version':'1'}))
        assert 'result' in r,r
        self.send(dict(jsonrpc='2.0',method='notifications/initialized'))
    def send(self,v):
        self.p.stdin.write(json.dumps(v).encode()+b'\n');self.p.stdin.flush()
    def call(self,method,params):
        self.i+=1;self.send(dict(jsonrpc='2.0',id=self.i,method=method,params=params))
        while True:
            if not select.select([self.p.stdout],[],[],15)[0]: raise RuntimeError('MCP timeout')
            line=self.p.stdout.readline()
            if not line: raise RuntimeError(self.p.stderr.read().decode())
            r=json.loads(line)
            if r.get('id')==self.i:return r
    def tool(self,tool_name,**args):
        r=self.call('tools/call',dict(name=tool_name,arguments=args))
        assert 'result' in r,r
        return r['result']
    def close(self):
        self.p.stdin.close();self.p.wait(timeout=10)
with tempfile.TemporaryDirectory(prefix='mmm-mcp-',dir='/tmp') as tmp:
    sock=tmp+'/control.sock'
    service=subprocess.Popen([str(root/'work/tests/macmini-moded'),'--dry-run','--simulate-power=ac','--socket='+sock,'--notify-prefix=com.macminimode.test.'+uuid.uuid4().hex],stdout=subprocess.DEVNULL)
    env=dict(os.environ,MACMINIMODE_SOCKET=sock,MACMINIMODE_CONTROL=str(root/'work/tests/macminimode-control'))
    try:
        for _ in range(100):
            if os.path.exists(sock):break
            time.sleep(.05)
        a=Client(env, {'experimental': {'codex': {'enabled': True}, 'other': [1, False, None]}, 'roots': {'listChanged': True}});b=Client(env)
        assert len(a.call('tools/list',{})['result']['tools'])==4
        r=a.tool('begin_task',id='a',name='Build',source='Codex');assert not r.get('isError'),r
        r=b.tool('begin_task',id='b',name='Test',source='Claude',mode='on');assert r['structuredContent']['status']['totalTasks']==2,r
        r=a.tool('end_task',id='a');assert r['structuredContent']['status']['mode']=='on',r
        a.close();a=Client(env)
        assert a.tool('get_status')['structuredContent']['status']['totalTasks']==1
        r=b.tool('end_task',id='b');assert r['structuredContent']['status']['mode']=='off',r
        r=a.tool('begin_task',id='bad',name='Bad',source='Test',mode='off');assert r['isError'],r
        r=a.tool('set_mode',mode='invalid');assert r['isError'],r
        assert a.tool('get_status',extra='reject')['isError']
        assert a.tool('begin_task',id=42)['isError']
        a.close();b.close()
        print('PASS: MCP initialize/list/call, structured responses, two clients, reconnect and final release')
        print('PASS: invalid modes, unknown fields and non-string arguments rejected; stdout contains only JSON-RPC')
    finally:
        service.terminate();service.wait(timeout=5)
