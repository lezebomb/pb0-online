import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const gameRoot=path.join(root,'game-instances','host');
const mod=path.join(gameRoot,'platform/steam/ue4ss/Mods/PBZCoop');
const run=path.join(root,'runs','game-bridge-'+Date.now());fs.mkdirSync(run,{recursive:true});
const clients=[],invite=path.join(run,'invite.txt');
let gamePid,sim;
function launch(args){
  const p=spawn(path.join(root,'dist/PB0/PB0.exe'),args,{cwd:root,windowsHide:true,stdio:['pipe','pipe','pipe']});
  const c={p,events:[],buffer:'',exit:undefined};clients.push(c);
  p.stdout.on('data',b=>{c.buffer+=b.toString();let i;while((i=c.buffer.indexOf('\n'))>=0){const line=c.buffer.slice(0,i);c.buffer=c.buffer.slice(i+1);try{const e=JSON.parse(line);c.events.push(e);if(e.type==='game_started')gamePid=e.data.pid;}catch{}}});
  p.stderr.on('data',b=>fs.appendFileSync(path.join(run,'stderr.log'),b));p.on('exit',code=>c.exit=code);
  return c;
}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(test,ms){const end=Date.now()+ms;while(Date.now()<end){if(test())return;const bad=clients.find(c=>c.exit!==undefined);if(bad)throw Error('Launcher exited: '+JSON.stringify(bad.events.slice(-4)));await sleep(200);}throw Error('Timeout');}
try{
  const host=launch(['host','--local','--json','--root',root,'--game-root',gameRoot,'--run-dir',path.join(run,'host'),'--invite-out',invite,'--launch-game']);
  await until(()=>fs.existsSync(invite),6000);
  launch(['join','--json','--root',root,'--invite-file',invite,'--run-dir',path.join(run,'guest')]);
  await until(()=>gamePid,12000);
  sim=spawn(process.execPath,['scripts/simulated-guest.mjs','--invite-file',invite,'--seconds','90'],{cwd:root,windowsHide:true});
  const messages=[];let partial='';
  sim.stdout.on('data',b=>{partial+=b.toString();let n;while((n=partial.indexOf('\n'))>=0){const line=partial.slice(0,n);partial=partial.slice(n+1);fs.appendFileSync(path.join(run,'simulator.jsonl'),line+'\n');try{messages.push(JSON.parse(line));}catch{}}});
  sim.stderr.on('data',b=>fs.appendFileSync(path.join(run,'simulator-errors.log'),b));
  await until(()=>messages.some(m=>m.type==='native_connected'),80000);
  // A signed native response proves both UDP directions, not yet that a character is in gameplay.
  await sleep(3000);
  const statusFile=path.join(mod,'net_status.txt');
  const status=fs.existsSync(statusFile)?fs.readFileSync(statusFile,'utf8'):'';
  const logPath=path.join(gameRoot,'platform/steam/ue4ss/UE4SS.log');
  const log=fs.existsSync(logPath)?fs.readFileSync(logPath,'utf8'):'';
  const result={nativeBidirectional:messages.some(m=>m.type==='native_connected'),
    playerSnapshots:messages.some(m=>m.type==='player_snapshot_received'),
    modLoaded:log.includes('Loaded (instance 1, v1.4.1'),
    connectedStatus:/connected=(yes|true|1)/.test(status),run};
  fs.writeFileSync(path.join(run,'result.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
}catch(e){console.error(e.message,run);process.exitCode=1;}
finally{
  sim?.kill();
  if(gamePid){try{process.kill(gamePid);}catch{}}
  await sleep(1200);
  clients.forEach(c=>{if(c.exit===undefined)c.p.stdin.write('quit\n');});
  await sleep(1200);
  clients.forEach(c=>{if(c.exit===undefined)c.p.kill();});
}
