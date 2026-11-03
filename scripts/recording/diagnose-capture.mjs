import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
export async function diagnoseCapture({api,run,base,root,selectors,wait=ms=>new Promise(r=>setTimeout(r,ms))}){
 const output=path.join(base,'presentation-fix'),results=[];
 fs.mkdirSync(output,{recursive:true});
 const child=(exe,args)=>new Promise((resolve,reject)=>{
  const p=spawn(exe,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});let text='';
  p.stdout.on('data',b=>text+=b);p.stderr.on('data',b=>text+=b);p.on('error',reject);p.on('exit',code=>code===0?resolve(text):reject(Error(text)));
 });
 let seq=0;
 async function evalGame(role,lua){
  const inbox=path.join(root,'game-instances',role,'platform/steam/ue4ss/Mods/PBZCoop/cmd.txt');
  const ack=path.join(run,'presentation-ack-'+(++seq)+'-'+role);
  const end=Date.now()+5000;
  while(Date.now()<end){if(!fs.readFileSync(inbox,'utf8').trim())break;await wait(50);}
  fs.writeFileSync(inbox,'eval '+lua+' local f=io.open('+JSON.stringify(ack.replaceAll('\\','/'))+',"w") f:write("ok") f:close()\n');
  while(!fs.existsSync(ack)){if(Date.now()>end)throw Error(role+' presentation command failed');await wait(50);}
 }
 async function visible(name,value){
  const item=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:name});
  await api('SetSceneItemEnabled',{sceneName:'PB0 Live',sceneItemId:item.sceneItemId,sceneItemEnabled:value});
 }
 async function use(method,single=false){
  for(const role of ['Host','Guest']){
   const active=role==='Host'||!single;
   await visible('PB0 '+role,method==='game'&&active);
   if(wgcCreated)await visible('PB0 '+role+' WGC',method==='wgc'&&active);
  }
 }
 let wgcCreated=false;
 async function createWGC(){
  for(const role of ['Host','Guest']){
   const name='PB0 '+role+' WGC';
   await api('CreateInput',{sceneName:'PB0 Live',inputName:name,inputKind:'window_capture',inputSettings:{method:2,window:selectors[role],priority:0,cursor:false,client_area:true,force_sdr:true},sceneItemEnabled:false}).catch(async()=>{
    await api('SetInputSettings',{inputName:name,inputSettings:{method:2,window:selectors[role],priority:0,cursor:false,client_area:true,force_sdr:true},overlay:true});
   });
   const windows=await api('GetInputPropertiesListPropertyItems',{inputName:name,propertyName:'window'});
   const candidates=windows.propertyItems.filter(x=>String(x.itemValue).includes('PB0 '+role+' -'));
   if(candidates.length!==1)throw Error('No unique WGC '+role+' window');
   await api('SetInputSettings',{inputName:name,inputSettings:{window:candidates[0].itemValue},overlay:true});
   const item=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:name});
   await api('SetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:item.sceneItemId,sceneItemTransform:{positionX:role==='Host'?0:960,positionY:270,boundsType:'OBS_BOUNDS_SCALE_INNER',boundsWidth:960,boundsHeight:540,alignment:5}});
  }
  wgcCreated=true;
 }
 async function stage(name,method,{single=false,mode='legacy'}={}){
  for(const role of ['host','guest'])await evalGame(role,'PB0_QUALITY.presentation('+JSON.stringify(mode)+') PB0_LOCO_CONFIG.presentationPan=true');
  await use(method,single);await wait(2200);
  const shot=await api('GetSourceScreenshot',{sourceName:'PB0 Host'+(method==='wgc'?' WGC':''),imageFormat:'png',imageWidth:960,imageHeight:540});
  const png=path.join(output,name+'-input.png');fs.writeFileSync(png,Buffer.from(shot.imageData.split(',')[1],'base64'));
  let valid=true;
  try{await child('python',['-c','import cv2,sys;g=cv2.imread(sys.argv[1]);assert g is not None and g.std()>8',png]);}catch{valid=false;}
  if(!valid){results.push({name,method,mode,valid:false});return;}
  await api('StartRecord');await wait(4200);const stop=await api('StopRecord');
  const report=path.join(output,name+'-seams.json');
  await child('python',['scripts/recording/check-video-seams.py',stop.outputPath,report,...(single?['single']:[])]);
  const data=JSON.parse(fs.readFileSync(report,'utf8'));
  results.push({name,method,mode,valid:true,png,video:stop.outputPath,...data});
 }
 try{
  if(process.env.PB0_REUSE_CAPTURE_DIAGNOSIS==='1'||(process.env.PB0_DIAGNOSE_CAPTURE!=='1'&&fs.existsSync(path.join(output,'verified-capture.json'))&&JSON.parse(fs.readFileSync(path.join(output,'verified-capture.json'),'utf8')).p0Pass)){
   await createWGC();await use('wgc');
   for(const role of ['host','guest'])await evalGame(role,'PB0_QUALITY.presentation("synced") PB0_LOCO_CONFIG.presentationPan=false PB0_LOCO.phaseTo("setup")');
   await wait(2500);
   return {run,chosenMethod:'wgc',finalVSync:true,finalFPSLimit:0,reusedDiagnosis:path.join(output,'capture-diagnosis.json'),reason:'One targeted balanced-render-load retest; P0 capture comparisons are not repeated'};
  }
  await stage('single-game-legacy','game',{single:true});
  await stage('dual-game-legacy','game');
  await stage('dual-game-vsync60','game',{mode:'diagnostic60'});
  try{await createWGC();await stage('dual-wgc-unlimited','wgc',{mode:'synced'});}catch(e){results.push({name:'dual-wgc-unlimited',valid:false,error:e.message});}
  let chosen=results.find(x=>x.method==='wgc'&&x.valid);
  if(!chosen)chosen=results.find(x=>x.name==='dual-game-vsync60'&&x.valid);
  if(!chosen)throw Error('No functioning real capture path');
  await use(chosen.method);
  for(const role of ['host','guest'])await evalGame(role,'PB0_QUALITY.presentation("synced") PB0_LOCO_CONFIG.presentationPan=false PB0_LOCO.phaseTo("setup")');
  await wait(1200);
  const receipt={run,results,chosenMethod:chosen.method,finalVSync:true,finalFPSLimit:0};
  fs.writeFileSync(path.join(output,'capture-diagnosis.json'),JSON.stringify(receipt,null,2));
  console.log(JSON.stringify({type:'presentation_diagnosis',chosenMethod:chosen.method,results:results.map(x=>({name:x.name,valid:x.valid,seams:x.suspectedSeamFrames,error:x.error}))}));
  return receipt;
 }finally{
  for(const role of ['host','guest'])try{await evalGame(role,'PB0_LOCO_CONFIG.presentationPan=false');}catch{}
 }
}
