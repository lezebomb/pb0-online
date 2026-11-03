// Two real, independently saved games. Uses the existing PB0 + Phantom Pact path; no simulated peer.
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {runLocomotion} from './test-locomotion.mjs';
const locomotion=process.argv.includes('--locomotion');
const showcase=process.argv.includes('--showcase');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),run=path.join(root,'runs',(locomotion?'locomotion-game-':showcase?'record-game-':'dual-game-')+Date.now());
const json=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
if(json(path.join(root,'runs/save-profile-state.json')).ActiveMode!=='Test')throw Error('Switch to test saves after user authorization first.');
fs.mkdirSync(run,{recursive:true});fs.writeFileSync(path.join(root,'runs/dual-game-current.json'),JSON.stringify({run}));
const deadline=Date.now()+(locomotion?480000:300000),players={},checks={isolatedSaves:false,twoRealGames:false,bothGhosts:false,hostHitsGuest:false,guestHitsHost:false,realParry:false,realBlock:false};
const result={schema:1,ok:false,mode:locomotion?'locomotion-comparison':showcase?'recording-showcase':'combat-verification',run,checks,measurements:{},startedAt:new Date().toISOString()};
let stopping=false;const sleep=ms=>new Promise(r=>setTimeout(r,ms)),report=(type,data={})=>console.log(JSON.stringify({type,...data}));
process.on('SIGINT',()=>stopping=true);process.on('SIGTERM',()=>stopping=true);
const stopped=()=>stopping||Date.now()>deadline||fs.existsSync(path.join(run,'stop'));
function pump(){
 for(const p of Object.values(players)){
  try{const b=fs.readFileSync(p.telemetry);p.partial+=b.subarray(p.offset).toString();p.offset=b.length;let i;while((i=p.partial.indexOf('\n'))>=0){const line=p.partial.slice(0,i);p.partial=p.partial.slice(i+1);try{const o=JSON.parse(line);if(o.runId===p.probeId)p.rows.push(o);}catch{}}}catch{}
 }
}
async function until(test,ms,label){const end=Date.now()+ms;while(Date.now()<end&&!stopped()){pump();if(test())return;for(const p of Object.values(players))if(p.exit!==undefined)throw Error(p.name+' launcher exited: '+JSON.stringify(p.events.slice(-2)));await sleep(80);}throw Error('Timeout/stopped: '+label);}
function latest(p){return p.rows.findLast(o=>o.type==='sample'&&o.playerReady);}
function rows(p,phase){return p.rows.filter(o=>o.type==='sample'&&o.phase===phase&&o.player);}
const attackActive=a=>a?.split(',').some(n=>/^GA_Hun/.test(n)&&!/Stance|Dash|Dodge|Deflect|Escape|Hit/.test(n));
async function command(p,text){const file=path.join(p.mod,'cmd.txt'),end=Date.now()+3000;while(Date.now()<end){let old='';try{old=fs.readFileSync(file,'utf8');}catch{}if(!old.trim()){fs.writeFileSync(file,'eval '+text+'\n');return;}await sleep(80);}throw Error(p.name+' inbox stalled');}
function launch(name,host,invite){
 const gameRoot=path.join(root,'game-instances',name),profile=json(path.join(gameRoot,'pb0-test-profile.json')),proof=json(path.join(gameRoot,'pb0-save-isolation-proof.json'));
 if(!profile.SaveIsolationVerifiedInGame||!proof.Verified)throw Error(name+' has no real save isolation proof');
 const mod=path.join(gameRoot,'platform/steam/ue4ss/Mods/PBZCoop'),probeId=crypto.randomUUID();
 const p={name,gameRoot,mod,probeId,rows:[],events:[],offset:0,partial:'',buffer:'',telemetry:path.join(run,name+'-observations.jsonl')};players[name]=p;
 p.devCreated=!fs.existsSync(path.join(mod,'dev.txt'));if(p.devCreated)fs.writeFileSync(path.join(mod,'dev.txt'),'PB0 isolated dual test');fs.writeFileSync(path.join(mod,'cmd.txt'),'');
 if(locomotion){p.qpcMarker=path.join(gameRoot,'platform/steam/ue4ss/Mods/PB0CombatAdapter/Scripts/pb0-shared-qpc-test.txt');p.qpcCreated=!fs.existsSync(p.qpcMarker);if(p.qpcCreated)fs.writeFileSync(p.qpcMarker,'Same-machine bounded recording only');}
 const params=[host?'host':'join','--json','--root',root,'--local','--game-root',gameRoot,'--run-dir',path.join(run,name),'--allow-isolated-games','--duration',locomotion?'480':'300','--launch-game',host?'--invite-out':'--invite-file',invite];
 p.child=spawn(path.join(root,'dist/PB0/PB0.exe'),params,{cwd:root,windowsHide:true,stdio:['pipe','pipe','pipe']});
 p.child.stdout.on('data',b=>{p.buffer+=b.toString();let i;while((i=p.buffer.indexOf('\n'))>=0){const line=p.buffer.slice(0,i);p.buffer=p.buffer.slice(i+1);try{const e=JSON.parse(line);p.events.push(e);if(e.type==='game_started'){p.pid=e.data.pid;p.gameStartedAt=Date.now();report('real_game_started',{name,pid:p.pid});}}catch{}}});
 p.child.stderr.on('data',b=>fs.appendFileSync(path.join(run,name+'-errors.log'),b));p.child.on('error',e=>{p.exit=1;p.error=e.message;});p.child.on('exit',code=>p.exit=code);
 return p;
}
async function loadProbe(p){
 await until(()=>{try{const log=path.join(p.gameRoot,'platform/steam/ue4ss/UE4SS.log');return fs.statSync(log).mtimeMs>=p.gameStartedAt&&fs.readFileSync(log,'utf8').includes('PB0 native PvP verdict adapter ready');}catch{return false;}},180000,p.name+' adapter');
 await command(p,'PB0_PROBE_CONFIG={autoContinue=true,autoParry='+String(p.name==='guest')+',runId='+JSON.stringify(p.probeId)+',parryDelay=0.25,output='+JSON.stringify(p.telemetry.replaceAll('\\','/'))+'} PB0_TEST=dofile('+JSON.stringify(path.join(root,'scripts/pvp-probe.lua').replaceAll('\\','/'))+')');
}
async function phase(name){for(const p of Object.values(players))await command(p,'PB0_TEST.release() PB0_TEST.setPhase('+JSON.stringify(name)+')');await until(()=>Object.values(players).every(p=>p.rows.some(o=>o.type==='phase_started'&&o.phase===name)),2500,'phase '+name);}
function loss(p,name,key){const a=rows(p,name).map(o=>o.player[key]).filter(Number.isFinite);return a.length>1?Math.max(0,a[0]-Math.min(...a)):null;}
let anchor;
async function align(){
 const a=anchor;
 await command(players.host,'local pc,p=PBZ.getPlayer1() p:K2_SetActorLocation({X='+a.x+',Y='+a.y+',Z='+a.z+'},false,{},true) p:K2_SetActorRotation({Pitch=0,Yaw=0,Roll=0},false) pc:SetControlRotation({Pitch=-8,Yaw=0,Roll=0})');
 await command(players.guest,'local pc,p=PBZ.getPlayer1() p:K2_SetActorLocation({X='+(a.x+140)+',Y='+a.y+',Z='+a.z+'},false,{},true) p:K2_SetActorRotation({Pitch=0,Yaw=180,Roll=0},false) pc:SetControlRotation({Pitch=-8,Yaw=180,Roll=0})');
 await sleep(1600);pump();
}
try{
 const invite=path.join(run,'invite.txt');const host=launch('host',true,invite);await until(()=>fs.existsSync(invite),6000,'invite');const guest=launch('guest',false,invite);
 checks.isolatedSaves=true;await until(()=>host.pid&&guest.pid,30000,'two real game launches');checks.twoRealGames=host.pid!==guest.pid;
 // Mod logs are reused on disk; require this launch's game_started first, then use the command-response path.
 await Promise.all([loadProbe(host),loadProbe(guest)]);
 await until(()=>[host,guest].every(p=>latest(p)?.ghostExists&&latest(p)?.meshVisible&&!latest(p)?.ghostHidden&&p.rows.some(o=>o.type==='capabilities'&&o.attackPath)),180000,'both loaded players and real ghosts');checks.bothGhosts=true;
 anchor={x:latest(host).player.x,y:latest(host).player.y,z:latest(host).player.z};
 if(locomotion){
  await runLocomotion({root,run,host,guest,command,phase,until,latest,pump,sleep,stopped,report,result});
 }else if(showcase){
  await align();for(const p of [host,guest])await command(p,'PB0_TEST.showcaseCamera('+(anchor.x+70)+','+anchor.y+','+anchor.z+')');await phase('showcase-ready');
  fs.writeFileSync(path.join(run,'showcase-ready.json'),JSON.stringify({run,players:Object.fromEntries(Object.values(players).map(p=>[p.name,{pid:p.pid,gameRoot:p.gameRoot}]))}));
  report('showcase_ready',{run});
  await until(()=>fs.existsSync(path.join(run,'showcase-start')),120000,'game capture confirmation');
  const began=Date.now(),at=async seconds=>{while(Date.now()-began<seconds*1000&&!stopped()){pump();await sleep(100);}if(stopped())throw Error('Showcase stopped');};
  const walk=async(p,direction)=>command(p,'local _,p=PBZ.getPlayer1() local ending=os.clock()+0.65 local function move() if os.clock()<ending and PBZ.valid(p) then p:AddMovementInput({X=0,Y='+direction+',Z=0},0.15,false) PBZ.game.after(0.016,move) end end move()');
  await phase('showcase-movement');await walk(host,1);await walk(guest,-1);await at(3);await walk(host,-1);await walk(guest,1);await at(7);await command(host,'PB0_TEST.face()');await command(guest,'PB0_TEST.face()');
  await at(10);await phase('showcase-attacks');await command(host,'PB0_TEST.attackOnce()');await at(13);await command(guest,'PB0_TEST.attackOnce()');await at(16);await command(host,'PB0_TEST.attackOnce()');await at(19);await command(guest,'PB0_TEST.attackOnce()');
  await at(25);await phase('showcase-block');await command(guest,'PB0_TEST.defend()');await sleep(900);await command(host,'PB0_TEST.attackOnce()');await at(29);await command(guest,'PB0_TEST.release()');await command(host,'PB0_TEST.defend()');await sleep(900);await command(guest,'PB0_TEST.attackOnce()');await at(33);await command(host,'PB0_TEST.release()');
  await at(40);await phase('parry');await command(host,'PB0_TEST.attackOnce()');await at(46);await command(host,'PB0_TEST.attackOnce()');
  await at(52);await phase('showcase-finale');await walk(host,1);await walk(guest,-1);await at(55);await walk(host,-1);await walk(guest,1);await at(60);
  result.showcaseSeconds=(Date.now()-began)/1000;result.ok=true;
  fs.writeFileSync(path.join(run,'showcase-done.json'),JSON.stringify({seconds:result.showcaseSeconds}));report('showcase_complete',{seconds:result.showcaseSeconds});
  const flush=Date.now()+15000;while(!stopped()&&Date.now()<flush){await sleep(200);}
 }else{
 for(const [name,attacker,defender,check] of [['host-hits-guest',host,guest,'hostHitsGuest'],['guest-hits-host',guest,host,'guestHitsHost']]){
  await align();await phase(name);await command(attacker,'PB0_TEST.attackOnce()');
  await until(()=>loss(defender,name,'hp')>0.5&&rows(defender,name).some(o=>attackActive(o.ghost?.active))&&rows(attacker,name).some(o=>attackActive(o.player.active)),5000,name+' native move and real HP loss');
  checks[check]=true;result.measurements[name]={hpLoss:loss(defender,name,'hp'),postureLoss:loss(defender,name,'posture')};report('real_damage_verified',{direction:name,...result.measurements[name]});await sleep(2000);
 }
 await align();await phase('parry');await until(()=>latest(host).player.posture>300&&latest(guest).player.posture>300,8000,'posture recovered');
 await command(host,'PB0_TEST.attackOnce()');
 await until(()=>guest.rows.some(o=>o.type==='engine_deflect'&&o.phase==='parry'&&o.tag==='Deflect.Result.Perfect'&&!o.hit)&&guest.rows.some(o=>o.type==='native_parry_sent'&&o.phase==='parry')&&loss(host,'parry','posture')>=50,6000,'real defender Perfect and real attacker posture penalty');
 checks.realParry=loss(guest,'parry','hp')<=0.5;result.measurements.parry={defenderHpLoss:loss(guest,'parry','hp'),attackerPostureLoss:loss(host,'parry','posture'),engineTag:'Deflect.Result.Perfect'};report('real_parry_verified',result.measurements.parry);
 await sleep(1800);await align();await phase('block');await command(guest,'PB0_TEST.defend()');await sleep(900);await command(host,'PB0_TEST.attackOnce()');
 await until(()=>loss(guest,'block','posture')>10&&rows(guest,'block').some(o=>attackActive(o.ghost?.active)),5000,'real block');
 checks.realBlock=loss(guest,'block','hp')<=0.5;result.measurements.block={hpLoss:loss(guest,'block','hp'),postureLoss:loss(guest,'block','posture')};report('real_block_verified',result.measurements.block);
 result.ok=Object.values(checks).every(Boolean);if(!result.ok)throw Error('Missing: '+Object.keys(checks).filter(k=>!checks[k]).join(', '));
 }
}catch(e){result.error=e.message;process.exitCode=1;}
finally{
 pump();result.finishedAt=new Date().toISOString();result.players=Object.fromEntries(Object.values(players).map(p=>[p.name,{pid:p.pid,gameRoot:p.gameRoot,telemetry:p.telemetry}]));
 fs.writeFileSync(path.join(run,'result.json'),JSON.stringify(result,null,2));report('result',result);
 for(const p of Object.values(players)){try{await command(p,'if PB0_LOCO then PB0_LOCO.stop() end if PB0_TEST then PB0_TEST.release() PB0_TEST.stop() end');}catch{}try{p.child.stdin.write('quit\n');}catch{}}
 await sleep(1800);for(const p of Object.values(players)){if(p.exit===undefined)p.child.kill();if(p.devCreated)fs.rmSync(path.join(p.mod,'dev.txt'),{force:true});if(p.qpcCreated)fs.rmSync(p.qpcMarker,{force:true});}
}
