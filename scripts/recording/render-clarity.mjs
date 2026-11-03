// One short render A/B within the same owned two-game session, then restore temporal AA.
import fs from 'node:fs';
import path from 'node:path';
export async function configureMotionRender({run,root,wait=ms=>new Promise(r=>setTimeout(r,ms))}){
 for(const role of ['host','guest']){
  const file=path.join(root,'game-instances',role,'platform/steam/ue4ss/Mods/PBZCoop/cmd.txt');
  const ack=path.join(run,role+'-combat-render-ready'),end=Date.now()+6000;
  while(fs.readFileSync(file,'utf8').trim()){if(Date.now()>end)throw Error('Final render inbox stalled');await wait(30);}
  fs.writeFileSync(file,'eval PB0_QUALITY.rendering("combat") local f=assert(io.open('+JSON.stringify(ack.replaceAll('\\','/'))+',"w")) f:write("ok") f:close()\n');
  while(!fs.existsSync(ack)){if(Date.now()>end)throw Error('Final render not applied');await wait(30);}
 }
}
export async function compareRender({api,run,root,wait=ms=>new Promise(r=>setTimeout(r,ms))}){
 const ready=JSON.parse(fs.readFileSync(path.join(run,'locomotion-record-ready.json'),'utf8'));
 let serial=0,recording=false;const stages=[];
 async function command(role,text){
  const file=path.join(root,'game-instances',role,'platform/steam/ue4ss/Mods/PBZCoop/cmd.txt');
  const ack=path.join(run,'clarity-ack-'+(++serial)+'-'+role),end=Date.now()+6000;
  while(fs.readFileSync(file,'utf8').trim()){if(Date.now()>end)throw Error('Clarity inbox stalled');await wait(30);}
  fs.writeFileSync(file,'eval '+text+' local f=assert(io.open('+JSON.stringify(ack.replaceAll('\\','/'))+',"w")) f:write("ok") f:close()\n');
  while(!fs.existsSync(ack)){if(Date.now()>end)throw Error('Clarity command not applied: '+role);await wait(30);}
 }
 try{
  // The test helper restores the same start once per A/B segment, outside each measured movement.
  for(const role of ['host','guest'])await command(role,'local _,p=PBZ.getPlayer1() PB0_CLARITY_START=p:K2_GetActorLocation()');
  await api('StartRecord');recording=true;const start=Date.now();
  for(const mode of ['original','no-blur','fxaa','velocity']){
   await command('guest','PB0_LOCO.move(0,0,.1)');await wait(350);
   await command('guest','local _,p=PBZ.getPlayer1() p:K2_SetActorLocation(PB0_CLARITY_START,false,{},true) p.CharacterMovement:StopMovementImmediately()');
   await command('host','local g=PBZ.net.ghost g:K2_SetActorLocation(PBZ.net.target,false,{},true) g.CharacterMovement:StopMovementImmediately() PB0_REMOTE_LOCOMOTION.resetAfterAlignment()');
   for(const role of ['host','guest'])await command(role,'PB0_QUALITY.rendering('+JSON.stringify(mode)+') PB0_LOCO.phaseTo("render-'+mode+'")');
   await wait(900);const began=Date.now();
   await command('guest','PB0_LOCO.move('+ready.forwardAxis.join(',')+',1.65)');
   await wait(1000);
   const shot=await api('GetSourceScreenshot',{sourceName:'PB0 Host WGC',imageFormat:'png',imageWidth:1280,imageHeight:720});
   fs.writeFileSync(path.join(run,'render-'+mode+'.png'),Buffer.from(shot.imageData.split(',')[1],'base64'));
   await wait(1600);
   stages.push({mode,startSeconds:(began-start)/1000,endSeconds:(Date.now()-start)/1000});
  }
  const output=await api('StopRecord');recording=false;
  fs.writeFileSync(path.join(run,'render-comparison.json'),JSON.stringify({outputPath:output.outputPath,stages,diagnosticTeleportsBetweenSegments:true},null,2));
 }finally{
  if(recording)await api('StopRecord').catch(()=>{});
  for(const role of ['host','guest'])await command(role,'PB0_QUALITY.rendering("original") PB0_LOCO.phaseTo("setup")');
  await command('guest','local _,p=PBZ.getPlayer1() p:K2_SetActorLocation(PB0_CLARITY_START,false,{},true) p.CharacterMovement:StopMovementImmediately()');
  await wait(300);
  await command('host','local g=PBZ.net.ghost g:K2_SetActorLocation(PBZ.net.target,false,{},true) g.CharacterMovement:StopMovementImmediately() PB0_REMOTE_LOCOMOTION.resetAfterAlignment()');
  await wait(1700);
 }
}
