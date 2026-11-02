import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const readJson=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const profileState=readJson(path.join(root,'runs/save-profile-state.json'));
if(profileState.ActiveMode!=='Test')throw Error('Testing is paused for personal play. Switch profiles only after the user requests testing.');
const args=process.argv.slice(2),option=(n,d)=>{const i=args.indexOf(n);return i<0?d:args[i+1];};
const stage=option('--stage','pvp'),demo=args.includes('--demo'),hold=args.includes('--hold'),attach=option('--attach');
const gameRoot=path.join(root,'game-instances',option('--profile','host')),mod=path.join(gameRoot,'platform/steam/ue4ss/Mods/PBZCoop');
const run=attach?path.resolve(attach):path.join(root,'runs','game-bridge-'+Date.now());fs.mkdirSync(run,{recursive:true});
const probeId=crypto.randomUUID(),startedAt=Date.now(),maxSessionMs=Math.min(900,Number(option('--session-seconds','600')))*1000;
fs.writeFileSync(path.join(root,'runs/game-bridge-current.json'),JSON.stringify({run,gameRoot,probeId}));
const clients=[],invite=path.join(run,'invite.txt'),telemetry=path.join(run,attach?'observations-'+probeId+'.jsonl':'game-observations.jsonl'),controlFile=path.join(run,'simulator-control.json');
const observations=[],messages=[];
let gamePid,gameStartedAt=0,sim,probeLoaded=false,telemetryOffset=0,partial='',devCreated=false,stopping=false,simOffset=0,simPartial='',progressBase;
let control={mode:'orbit',range:220,attackOnce:0};
const checks={modLoaded:false,nativeBidirectional:false,connectedStatus:false,playerSnapshots:false,ghostVisible:false,ghostMoving:false,attackApplied:false,damage:false,block:false,parry:false};
const result={schema:3,ok:false,stage,checks,measurements:{},run,probeId,startedAt:new Date(startedAt).toISOString(),telemetry};
const sleep=ms=>new Promise(r=>setTimeout(r,ms)),report=(type,data={})=>console.log(JSON.stringify({type,...data}));
process.on('SIGINT',()=>{stopping=true;});process.on('SIGTERM',()=>{stopping=true;});
const shouldStop=()=>stopping||fs.existsSync(path.join(run,'stop'))||Date.now()-startedAt>maxSessionMs;
function saveControl(update){control={...control,...update};const tmp=controlFile+'.tmp';fs.writeFileSync(tmp,JSON.stringify(control));fs.renameSync(tmp,controlFile);}
function launch(params){
  const p=spawn(path.join(root,'dist/PB0/PB0.exe'),[...params,'--duration',String(Math.ceil(maxSessionMs/1000))],{cwd:root,windowsHide:true,stdio:['pipe','pipe','pipe']});
  const c={p,events:[],buffer:'',exit:undefined};clients.push(c);
  p.stdout.on('data',b=>{c.buffer+=b.toString();let i;while((i=c.buffer.indexOf('\n'))>=0){const line=c.buffer.slice(0,i);c.buffer=c.buffer.slice(i+1);try{
    const e=JSON.parse(line);c.events.push(e);if(e.type==='game_started'){gamePid=e.data.pid;gameStartedAt=Date.now();report('game_started',{pid:gamePid});}
  }catch{}}});
  p.stderr.on('data',b=>fs.appendFileSync(path.join(run,'stderr.log'),b));p.on('exit',code=>c.exit=code);
  p.on('error',e=>{c.exit=1;fs.appendFileSync(path.join(run,'stderr.log'),e.message);});return c;
}
async function command(text){
  const file=path.join(mod,'cmd.txt'),deadline=Date.now()+4000;
  while(Date.now()<deadline){let p='';try{p=fs.readFileSync(file,'utf8');}catch{}if(!p.trim()){fs.writeFileSync(file,text+'\n');return;}await sleep(100);}
  throw Error('Mod command inbox is not being consumed');
}
function pump(){
  if(attach){try{const b=fs.readFileSync(path.join(run,'simulator.jsonl'));simPartial+=b.subarray(simOffset).toString();simOffset=b.length;let i;while((i=simPartial.indexOf('\n'))>=0){const line=simPartial.slice(0,i);simPartial=simPartial.slice(i+1);try{messages.push(JSON.parse(line));}catch{}}}catch{}}
  try{const file=path.join(gameRoot,'platform/steam/ue4ss/UE4SS.log');checks.modLoaded=fs.statSync(file).mtimeMs>=gameStartedAt&&fs.readFileSync(file,'utf8').includes('Loaded (instance 1, v1.4.1');}catch{}
  try{const file=path.join(mod,'net_status.txt'),s=fs.readFileSync(file,'utf8');checks.connectedStatus=Date.now()-fs.statSync(file).mtimeMs<5000&&/connected=yes/.test(s)&&/auth=on/.test(s);}catch{}
  try{const b=fs.readFileSync(telemetry);partial+=b.subarray(telemetryOffset).toString();telemetryOffset=b.length;let cut;
    while((cut=partial.indexOf('\n'))>=0){const line=partial.slice(0,cut);partial=partial.slice(cut+1);try{const o=JSON.parse(line);if(o.runId===probeId)observations.push(o);}catch{}}
  }catch{}
  const progress=messages.filter(m=>m.type==='simulator_progress'&&m.at>=startedAt);
  progressBase??=progress[0];const latest=progress.at(-1);
  checks.nativeBidirectional=!!(latest&&progressBase&&latest.received-progressBase.received>=5&&Date.now()-latest.at<2500);
  checks.playerSnapshots=!!(latest&&progressBase&&latest.returned-progressBase.returned>=20&&Date.now()-latest.at<2500);
  const visible=observations.filter(o=>o.type==='sample'&&o.phase==='movement'&&o.playerReady&&o.ghostExists&&!o.ghostHidden&&o.meshVisible&&o.distance>0&&o.distance<600);
  checks.ghostVisible=visible.length>=10;
  if(visible.length>=20){const a=visible[0].ghost,travel=visible.reduce((max,o)=>Math.max(max,Math.hypot(o.ghost.x-a.x,o.ghost.y-a.y)),0);
    result.measurements.ghostTravelCm=travel;checks.ghostMoving=travel>=50&&visible.at(-1).clock-visible[0].clock>=2;}
}
async function until(test,ms,label){
  const end=Date.now()+ms;
  while(Date.now()<end&&!shouldStop()){pump();if(test())return;const bad=clients.find(c=>c.exit!==undefined);if(bad)throw Error('Launcher exited: '+JSON.stringify(bad.events.slice(-4)));await sleep(100);}
  throw Error('Timeout/stopped: '+label);
}
const sampleRows=name=>observations.filter(o=>o.type==='sample'&&o.phase===name&&o.player);
const lastSample=()=>observations.findLast(o=>o.type==='sample'&&o.player);
const isAttack=o=>o.ghost?.active?.split(',').some(n=>/^GA_Hun/.test(n)&&!/Stance|Dash|Dodge|Deflect|Escape|Hit/.test(n));
async function phase(name){await command('eval PB0_TEST.setPhase('+JSON.stringify(name)+')');await until(()=>observations.some(o=>o.type==='phase_started'&&o.phase===name),2000,'phase '+name);}
function measure(name){
  const rows=sampleRows(name),loss=key=>{const values=rows.map(o=>o.player[key]).filter(Number.isFinite);return values.length>1?Math.max(0,values[0]-Math.min(...values)):null;};
  const m={samples:rows.length,hpStart:rows[0]?.player.hp,postureStart:rows[0]?.player.posture,hpLoss:loss('hp'),postureLoss:loss('posture'),
    remoteMoves:observations.filter(o=>o.type==='remote_move_applied'&&o.phase===name).length,attackActive:rows.some(isAttack),
    playerMontages:[...new Set(rows.map(o=>o.player.montage).filter(Boolean))],deflectInput:observations.some(o=>o.type==='deflect_input'&&o.phase===name&&o.ok)};
  result.measurements[name]=m;return m;
}
async function recovered(){
  await command('eval PB0_TEST.release()');
  await until(()=>{const s=lastSample();return s&&s.player.hp>200&&s.player.posture>=350&&!/Stance/.test(s.player.active)&&!/Hit_|DBreak/.test(s.player.montage??'');},8000,'natural posture recovery and guard release');
}
async function swing(name){
  await phase(name);const start=messages.length;
  saveControl({attackOnce:control.attackOnce+1});
  await until(()=>messages.slice(start).some(m=>m.type==='attack_sent'),2000,name+' signed attack sent');
  await until(()=>sampleRows(name).some(isAttack),2500,name+' real attack activation');
  checks.attackApplied=true;await sleep(2200);pump();return {measurement:measure(name),responses:messages.slice(start).filter(m=>m.type==='pvp_response')};
}
const required=['modLoaded','nativeBidirectional','connectedStatus','playerSnapshots','ghostVisible','ghostMoving',...(stage==='pvp'?['attackApplied','damage','block','parry']:[])];
function saveResult(){result.ok=required.every(key=>checks[key]);result.missing=required.filter(key=>!checks[key]);if(result.ok)delete result.error;fs.writeFileSync(path.join(run,attach?'pvp-result.json':'result.json'),JSON.stringify(result,null,2));}
try{
  if(!['movement','pvp'].includes(stage))throw Error('stage must be movement or pvp');
  const profile=readJson(path.join(gameRoot,'pb0-test-profile.json'));
  if(path.resolve(profile.Root)!==gameRoot||fs.lstatSync(path.join(gameRoot,'ProjectPBZ/Saved')).isSymbolicLink())throw Error('Invalid isolated save directory');
  const dev=path.join(mod,'dev.txt');if(!fs.existsSync(dev)){fs.writeFileSync(dev,'PB0 isolated development probe\n');devCreated=true;}
  if(attach){
    control=readJson(controlFile);const history=fs.readFileSync(path.join(run,'host/events.jsonl'),'utf8').trim().split('\n').map(x=>JSON.parse(x));
    const started=history.findLast(e=>e.type==='game_started');gamePid=started?.data.pid;gameStartedAt=started?Date.parse(started.time):0;
    if(!gamePid)throw Error('Attached session has no game PID');saveControl({mode:'orbit',range:220});
  }else{
    fs.writeFileSync(path.join(mod,'cmd.txt'),'');saveControl({});
    launch(['host','--local','--json','--root',root,'--game-root',gameRoot,'--run-dir',path.join(run,'host'),'--invite-out',invite,'--launch-game']);
    await until(()=>fs.existsSync(invite),6000,'room creation');
    launch(['join','--json','--root',root,'--invite-file',invite,'--run-dir',path.join(run,'guest')]);
    await until(()=>gamePid,30000,'isolated game launch');
    sim=spawn(process.execPath,['scripts/simulated-guest.mjs','--invite-file',invite,'--control-file',controlFile,'--seconds',String(Math.ceil(maxSessionMs/1000))],{cwd:root,windowsHide:true});
    let buffer='';sim.stdout.on('data',b=>{buffer+=b.toString();let n;while((n=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,n);buffer=buffer.slice(n+1);fs.appendFileSync(path.join(run,'simulator.jsonl'),line+'\n');try{messages.push(JSON.parse(line));}catch{}}});
    sim.stderr.on('data',b=>fs.appendFileSync(path.join(run,'simulator-errors.log'),b));
  }
  report('waiting_for_gameplay',{run});
  await until(()=>checks.modLoaded&&checks.nativeBidirectional,90000,'mod and fresh signed UDP');
  const lua=path.join(root,'scripts/pvp-probe.lua').replaceAll('\\','/'),out=telemetry.replaceAll('\\','/');
  if(attach){await command('eval if PB0_TEST then PB0_TEST.stop() end');await sleep(200);}
  await command('eval PB0_PROBE_CONFIG={autoContinue=true,runId='+JSON.stringify(probeId)+',parryDelay='+Number(option('--parry-delay','0.25'))+',output='+JSON.stringify(out)+'} PB0_TEST=dofile('+JSON.stringify(lua)+') return "PB0 observer loaded"');probeLoaded=true;
  await until(()=>checks.playerSnapshots&&checks.ghostVisible&&checks.ghostMoving,Number(option('--timeout','180'))*1000,'fresh real visible moving opponent');
  report('moving_opponent_verified',{travelCm:result.measurements.ghostTravelCm});
  await until(()=>observations.some(o=>o.type==='capabilities'&&o.attackPath),8000,'loaded attack capabilities');
  const cap=observations.findLast(o=>o.type==='capabilities'&&o.attackPath);
  if(stage==='pvp'){
    saveControl({mode:'idle',range:135,attackPath:cap.attackPath});await sleep(1600);await command('eval PB0_TEST.face()');await recovered();
    const damage=await swing('damage');checks.damage=damage.measurement.hpLoss>0.5&&damage.measurement.remoteMoves>0;report('damage_verified',{ok:checks.damage,...damage.measurement});
    if(cap.guardPath){
      await recovered();const parry=await swing('parry'),m=parry.measurement;
      m.nativeParry=parry.responses.some(r=>/ V parry\b/.test(r.event));
      m.enginePerfect=observations.some(o=>o.type==='engine_deflect'&&o.phase==='parry'&&o.tag==='Deflect.Result.Perfect'&&!o.hit);
      m.nativeReward=observations.some(o=>o.type==='native_parry_sent'&&o.phase==='parry'&&o.tag==='Deflect.Result.Perfect');
      m.remotePostureLoss=parry.responses.reduce((n,r)=>Math.max(n,(r.postureBefore??0)-(r.postureAfter??0)),0);
      checks.parry=m.postureStart>=200&&m.hpLoss!==null&&m.hpLoss<=0.5&&m.deflectInput&&m.enginePerfect&&m.nativeReward&&m.nativeParry&&m.remotePostureLoss===60;
      report('parry_result',{ok:checks.parry,...m});
      await recovered();await phase('block');await command('eval PB0_TEST.defend()');await sleep(900);
      const start=messages.length;saveControl({attackOnce:control.attackOnce+1});await until(()=>sampleRows('block').some(isAttack),2500,'block real attack activation');await sleep(1700);pump();
      const block=measure('block');checks.block=block.postureStart>=200&&block.hpLoss!==null&&block.hpLoss<=0.5&&block.postureLoss>0.5&&block.remoteMoves>0&&sampleRows('block').some(o=>o.player.active?.includes('Stance'))&&messages.slice(start).some(m=>m.type==='attack_sent');
      report('block_result',{ok:checks.block,...block});await command('eval PB0_TEST.release()');
    }
  }
  saveResult();if(!result.ok&&!demo)throw Error('Missing in-game evidence: '+result.missing.join(', '));
  if(hold&&!demo){report('inspection_ready',{run,stage});saveControl({mode:'idle'});while(!shouldStop()){pump();await sleep(500);}}
  if(demo){
    await command('eval PB0_TEST.release() PB0_TEST.setPhase("demo")');saveControl({mode:'duel',range:150,attackPath:cap.attackPath});
    report('prototype_running',{run,checks});while(!shouldStop()){pump();await sleep(500);}
  }
}catch(e){
  result.error=e.message;process.exitCode=1;saveResult();
  if(hold){report('inspection_ready',{run,error:e.message});saveControl({mode:'idle'});while(!shouldStop()){pump();await sleep(500);}}
}finally{
  result.finishedAt=new Date().toISOString();saveResult();report('result',result);
  if(probeLoaded){try{await command('eval PB0_TEST.release() PB0_TEST.stop()');await sleep(150);}catch{}}
  if(attach){fs.writeFileSync(path.join(run,'stop'),'Attached validation finished');}else{
    sim?.kill();if(gamePid){try{process.kill(gamePid);}catch(e){report('cleanup_error',{pid:gamePid,error:e.message});}}
    await sleep(800);clients.forEach(c=>{if(c.exit===undefined){try{c.p.stdin.write('quit\n');}catch{}}});
    await sleep(800);clients.forEach(c=>{if(c.exit===undefined)c.p.kill();});
  }
  if(devCreated)fs.rmSync(path.join(mod,'dev.txt'),{force:true});
}
