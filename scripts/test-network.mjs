import {spawn} from 'node:child_process';
import {mkdirSync,writeFileSync,createWriteStream,existsSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import net from 'node:net';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const exe=process.env.PB0_TEST_EXE??(existsSync(path.join(root,'dist/PB0/PB0.exe'))?path.join(root,'dist/PB0/PB0.exe'):path.join(root,'src/Pb0.Launcher/bin/Release/net9.0/PB0.exe'));
const mode=process.argv.includes('--relay')?'relay':process.argv.includes('--public')?'public':'local';
const run=path.join(root,'runs',`test-${mode}-${Date.now()}`);
mkdirSync(run,{recursive:true});
const clients=[];
let relay;
let deadline;
function start(role,args){
  const p=spawn(exe,[role,'--root',root,'--json','--run-dir',path.join(run,role),...args],{windowsHide:true,stdio:['pipe','pipe','pipe']});
  const c={p,events:[],partial:'',stderr:'',exit:undefined};clients.push(c);
  p.stdout.on('data',b=>{
    c.partial+=b.toString();let pos;
    while((pos=c.partial.indexOf('\n'))>=0){const line=c.partial.slice(0,pos);c.partial=c.partial.slice(pos+1);try{c.events.push(JSON.parse(line));}catch{}}
  });
  p.stderr.on('data',b=>c.stderr+=b.toString());p.on('exit',code=>c.exit=code);
  p.on('error',e=>c.stderr+=e.message);
  return c;
}
async function wait(predicate,timeout=45000){
  const end=Date.now()+timeout;
  while(Date.now()<end){if(predicate())return;const bad=clients.find(c=>c.exit!==undefined&&c.exit!==0);if(bad)throw Error(JSON.stringify(bad.events.filter(e=>e.type==='error'))+bad.stderr);await new Promise(r=>setTimeout(r,100));}
  throw Error('Timed out: '+JSON.stringify(clients.map(c=>c.events.filter(e=>['error','state','core_restarting','transport_error'].includes(e.type)))));
}
const has=(c,type,text)=>c.events.some(e=>e.type===type&&(!text||e.data?.text===text));
try{
  if(mode==='relay'){
    const probe=net.createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r));
    relay=spawn(path.join(root,'tools/easytier/easytier-windows-x86_64/easytier-core.exe'),
      ['--no-tun','--network-name','pb0-local-relay-test','--network-secret','pb0-local-relay-test',
       '--listeners',`tcp://127.0.0.1:${port}`,'--rpc-portal','0','--private-mode','false',
       '--bind-device','false','--disable-upnp','true','--accept-dns','false'],{windowsHide:true});
    const log=fsRelayLog();relay.stdout.pipe(log);relay.stderr.pipe(log);
    process.env.PB0_TEST_PEERS=`tcp://127.0.0.1:${port}`;
    await new Promise(r=>setTimeout(r,1000));
  }
  const invite=path.join(run,'invite.txt');
  const host=start('host',[...(mode==='local'?['--local']:[]),...(mode==='relay'?['--force-relay']:[]),...(process.env.PB0_TEST_PEERS?['--peers',process.env.PB0_TEST_PEERS]:[]),'--invite-out',invite,'--test-message','host-to-guest']);
  await wait(()=>has(host,'invite'),8000);
  const guest=start('join',[...(mode==='relay'?['--force-relay']:[]),'--invite-file',invite,'--test-message','guest-to-host']);
  await wait(()=>has(host,'message','guest-to-host')&&has(guest,'message','host-to-guest')&&
    has(host,'delivered','host-to-guest')&&has(guest,'delivered','guest-to-host')&&
    clients.every(c=>c.events.some(e=>e.type==='latency'&&e.data.Path!=='unknown')));
  let reconnect=false;
  if(process.argv.includes('--reconnect')){
    const core=host.events.findLast(e=>e.type==='core_started').data.pid;
    process.kill(core);
    await wait(()=>has(host,'core_restarting'),5000);
    await wait(()=>host.events.filter(e=>e.type==='core_started').length>1,5000);
    // Wait for a fresh route and pong after the replacement core started.
    await new Promise(r=>setTimeout(r,4500));
    host.p.stdin.write('msg after-core-restart\n');
    await wait(()=>has(guest,'message','after-core-restart')&&has(host,'delivered','after-core-restart'),15000);
    reconnect=true;
  }
  const result={ok:true,mode,bidirectionalMessages:true,acknowledged:true,
    rttMs:clients.map(c=>c.events.findLast(e=>e.type==='latency').data.RttMs),
    paths:clients.map(c=>c.events.findLast(e=>e.type==='latency').data.Path),reconnect,run};
  if(mode==='relay'&&result.paths.some(p=>p!=='relay'))throw Error('Expected actual relay path');
  clients.forEach(c=>c.p.stdin.write('quit\n'));
  await wait(()=>clients.every(c=>c.exit!==undefined),8000);
  if(clients.some(c=>c.exit!==0))throw Error('Nonzero launcher exit');
  const corePids=clients.flatMap(c=>c.events.filter(e=>e.type==='core_started').map(e=>e.data.pid));
  const alive=corePids.filter(pid=>{try{process.kill(pid,0);return true;}catch{return false;}});
  if(alive.length)throw Error('Core processes not cleaned up: '+alive);
  result.coreProcessesCleaned=true;
  writeFileSync(path.join(run,'result.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
}catch(e){console.error(e.message);process.exitCode=1;}
finally{clients.forEach(c=>{if(c.exit===undefined)c.p.kill();});relay?.kill();}
function fsRelayLog(){return createWriteStream(path.join(run,'relay.log'));}
