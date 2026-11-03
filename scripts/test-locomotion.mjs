import fs from 'node:fs';
import path from 'node:path';
export async function runLocomotion(c){
 const {root,run,host,guest,command,phase,until,latest,pump,sleep,stopped,report,result}=c;
 const ready=p=>{try{return JSON.parse(fs.readFileSync(path.join(run,p.name+'-input.json'),'utf8'));}catch{return {};}};
 const lua=f=>JSON.stringify(path.join(root,'scripts',f).replaceAll('\\','/'));
 const file=f=>JSON.stringify(path.join(run,f).replaceAll('\\','/'));
 const a=latest(host).player;
 // Align once before the comparison. All measured travel then comes from real Enhanced Input.
 await command(host,'local pc,p=PBZ.getPlayer1() p:K2_SetActorRotation({Pitch=0,Yaw=90,Roll=0},false) pc:SetControlRotation({Pitch=-8,Yaw=90,Roll=0})');
 await command(guest,'local pc,p=PBZ.getPlayer1() p:K2_SetActorLocationAndRotation({X='+(a.x+180)+',Y='+a.y+',Z='+a.z+'},{Pitch=0,Yaw=90,Roll=0},false,{},true) pc:SetControlRotation({Pitch=-8,Yaw=90,Roll=0})');
 for(const p of [host,guest]){
  await command(p,'PB0_QUALITY_CONFIG={root='+file(p.name)+'} PB0_QUALITY=dofile('+lua('quality-probe.lua')+') PB0_QUALITY.resolution('+'1280,720'+')');
  await command(p,'PB0_LOCO_CONFIG={output='+file(p.name+'-locomotion.jsonl')+',status='+file(p.name+'-input.json')+'} PB0_LOCO=dofile('+lua('locomotion-probe.lua')+')');
 }
 await until(()=>ready(host).ready&&ready(guest).ready,8000,'actual IA_Move and matching Enhanced Input subsystem');
 for(const p of [host,guest])if(ready(p).driver?.version!==8||ready(p).driver?.mode!=='restored-native-input')throw Error(p.name+' did not load the restored movement adapter');
 const setPhase=async(name)=>{for(const p of [host,guest])await command(p,'PB0_LOCO.phaseTo('+JSON.stringify(name)+')');};
 for(const p of [host,guest])await command(p,'PB0_LOCO_CONFIG.subject="'+(p===host?'remote':'local')+'" PB0_LOCO_CAMERA=dofile('+lua('locomotion-camera.lua')+')');
 await sleep(8000);
 fs.writeFileSync(path.join(run,'locomotion-baseline-ready.json'),JSON.stringify({run,host:ready(host),guest:ready(guest),anchor:a,players:{host:host.pid,guest:guest.pid}}));
 report('locomotion_driver_ready',{run});
 await until(()=>[host,guest].every(p=>latest(p)?.ghostExists),5000,'native remote pawns');
 const baselineReference='D:/pb0online/runs/locomotion-game-1793680942899/baseline-metrics.json';
 if(!fs.existsSync(baselineReference))throw Error('Verified Enhanced Input baseline missing');
 result.baselineReference=baselineReference;
 let forwardAxis,probeMeasurements=[];
 for(const axis of [[0,-.3],[0,.3],[.3,0],[-.3,0]]){
  const probeSource=latest(guest).player,probeRemote=latest(host).ghost;
  await setPhase('postfix-forward');
  await command(guest,'PB0_LOCO.move('+axis[0]+','+axis[1]+',1.5)');await sleep(2300);pump();
  const sourceTravel=Math.hypot(latest(guest).player.x-probeSource.x,latest(guest).player.y-probeSource.y);
  const remoteTravel=Math.hypot(latest(host).ghost.x-probeRemote.x,latest(host).ghost.y-probeRemote.y);
  probeMeasurements.push({axis,sourceTravelCm:sourceTravel,remoteTravelCm:remoteTravel});
  if(sourceTravel>=15&&remoteTravel>=10){forwardAxis=axis;break;}
 }
 result.movementProbe=probeMeasurements;
 if(!forwardAxis)throw Error('No unobstructed native movement direction matched: '+JSON.stringify(probeMeasurements));
 const lateralAxis=[-forwardAxis[1],forwardAxis[0]],turnAxis=[-lateralAxis[0],-lateralAxis[1]];
 await setPhase('postfix-stop');await sleep(1500);
 fs.writeFileSync(path.join(run,'locomotion-baseline-ready.json'),JSON.stringify({run,host:ready(host),guest:ready(guest),anchor:a,players:{host:host.pid,guest:guest.pid},baselineReference}));
 report('locomotion_baseline_ready',{run,usingSavedBaseline:true});
 await command(guest,'PB0_LOCO.move(0,0,.3)');await sleep(600);
 // Restore source pawn before final short showcase. No position forcing during the recording.
 await command(guest,'local pc,p=PBZ.getPlayer1() p:K2_SetActorLocationAndRotation({X='+(a.x+180)+',Y='+a.y+',Z='+a.z+'},{Pitch=0,Yaw=90,Roll=0},false,{},true) p.CharacterMovement:StopMovementImmediately() pc:SetControlRotation({Pitch=-8,Yaw=90,Roll=0})');

 await command(host,'local g=PBZ.net.ghost g:K2_SetActorLocation({X='+(a.x+180)+',Y='+a.y+',Z='+a.z+'},false,{},true) g.CharacterMovement:StopMovementImmediately() PB0_REMOTE_LOCOMOTION.resetAfterAlignment()');
 await command(guest,'local g=PBZ.net.ghost g:K2_SetActorLocation({X='+a.x+',Y='+a.y+',Z='+a.z+'},false,{},true) g.CharacterMovement:StopMovementImmediately() PB0_REMOTE_LOCOMOTION.resetAfterAlignment()');
 await sleep(1700);
 for(const p of [host,guest])await command(p,'PB0_LOCO.presentationDiagnosticReady=true');
 fs.writeFileSync(path.join(run,'locomotion-record-ready.json'),JSON.stringify({run,width:1920,height:1080,hostPid:host.pid,guestPid:guest.pid,forwardAxis,lateralAxis}));
 report('locomotion_record_ready',{run});
 await until(()=>fs.existsSync(path.join(run,'locomotion-start')),150000,'actual game framing and recorder cue');
 const began=Date.now(),at=async(s)=>{while(Date.now()-began<s*1000&&!stopped()){pump();await sleep(40);}if(stopped())throw Error('Locomotion showcase stopped');};
 for(const p of [host,guest])await command(p,'PB0_QUALITY.capture=true PB0_QUALITY.mark("capture")');
 await setPhase('forward');await command(guest,'PB0_LOCO.move('+forwardAxis[0]+','+forwardAxis[1]+',1.25)');await at(3);
 await setPhase('stop-one');await at(4.5);
 await setPhase('lateral');await command(guest,'PB0_LOCO.move('+lateralAxis[0]+','+lateralAxis[1]+',1.0)');await at(6.5);
 await setPhase('stop-two');await at(8);
 await setPhase('turn');await command(guest,'PB0_LOCO.move('+turnAxis[0]+','+turnAxis[1]+',1.25)');await at(11);
 await setPhase('stop-three');await at(13);
 await setPhase('attack');await command(guest,'PB0_TEST.attackOnce(false)');await at(16);
 await setPhase('idle-final');await at(17.5);
 for(const p of [host,guest])await command(p,'PB0_QUALITY.capture=false PB0_QUALITY.finish()');
 result.ok=true;result.locomotion={seconds:(Date.now()-began)/1000,source:'two real games, actual guest IA_JoystickMoveInput; input-command remote simulation with authoritative corrections',phases:['forward','lateral','stops','turn','one attack'],combatAssertionsRepeated:false};
 fs.writeFileSync(path.join(run,'locomotion-done.json'),JSON.stringify(result.locomotion));report('locomotion_complete',result.locomotion);
 await until(()=>fs.existsSync(path.join(run,'locomotion-recorder-done')),12000,'recording flush');
}
