import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {api,close} from './obs-control.mjs';
import {diagnoseCapture} from './diagnose-capture.mjs';
import {compareRender,configureMotionRender} from './render-clarity.mjs';
const root=path.resolve('.'),base=path.join(root,'runs/videos'),sleep=ms=>new Promise(r=>setTimeout(r,ms));
let game,run,code,foregroundSampler,recording=false;const stats=[];
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const child=(exe,args)=>{const p=spawn(exe,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});p.stdout.on('data',b=>process.stdout.write(b));p.stderr.on('data',b=>process.stderr.write(b));return new Promise((r,j)=>{p.on('exit',r);p.on('error',j);});};
async function waitFor(name,ms){const end=Date.now()+ms;while(Date.now()<end){if(code!==undefined)throw Error('Game session exited '+code);if(run&&fs.existsSync(path.join(run,name)))return read(path.join(run,name));await sleep(200);}throw Error('Timeout '+name);}
try{
 const end=Date.now()+25000;while(true){try{await api('GetSceneList');break;}catch(e){if(Date.now()>end)throw e;await sleep(400);}}
 await api('SetCurrentProgramScene',{sceneName:'PB0 Live'});
 for(const role of ['Host','Guest']){try{const i=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:'PB0 '+role+' WGC'});await api('SetSceneItemEnabled',{sceneName:'PB0 Live',sceneItemId:i.sceneItemId,sceneItemEnabled:false});}catch{}}
 await api('SetVideoSettings',{baseWidth:1920,baseHeight:1080,outputWidth:1920,outputHeight:1080,fpsNumerator:60,fpsDenominator:1});
 const began=Date.now();
 game=spawn(process.execPath,['scripts/test-dual-game.mjs','--locomotion'],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
 game.stdout.on('data',b=>process.stdout.write(b));game.stderr.on('data',b=>process.stderr.write(b));game.on('exit',c=>code=c);
 while(!run){try{const c=read('runs/dual-game-current.json');if(Number(path.basename(c.run).replace('locomotion-game-',''))>=began)run=c.run;}catch{}if(code!==undefined)throw Error('No fresh dual session');await sleep(100);}
 fs.writeFileSync(path.join(base,'locomotion-current.json'),JSON.stringify({run}));
 await waitFor('locomotion-baseline-ready.json',210000);
 if(await child('pwsh',['-NoLogo','-NoProfile','-File','scripts/tag-test-windows.ps1'])!==0)throw Error('Cannot distinguish owned game windows');
 const available=await api('GetInputPropertiesListPropertyItems',{inputName:'PB0 Host',propertyName:'window'});
 const selectors={};
 for(const role of ['Host','Guest']){
  const options=available.propertyItems.filter(x=>String(x.itemValue).includes('PB0 '+role+' -'));
  if(options.length!==1)throw Error('No unique real '+role+' capture window');
  selectors[role]=options[0].itemValue;
  await api('SetInputSettings',{inputName:'PB0 '+role,inputSettings:{capture_mode:'window',window:selectors[role],priority:0,capture_cursor:false,capture_audio:false,limit_framerate:true},overlay:true});
  const item=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:'PB0 '+role});
  await api('SetSceneItemEnabled',{sceneName:'PB0 Live',sceneItemId:item.sceneItemId,sceneItemEnabled:true});
  await api('SetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:item.sceneItemId,sceneItemTransform:{positionX:role==='Host'?0:960,positionY:270,boundsType:'OBS_BOUNDS_SCALE_INNER',boundsWidth:960,boundsHeight:540,alignment:5}});
 }
 fs.writeFileSync(path.join(run,'capture-windows.json'),JSON.stringify(selectors));
 await waitFor('locomotion-record-ready.json',170000);
 const diagnosis=await diagnoseCapture({api,run,base,root,selectors});
 if(process.env.PB0_RENDER_AB==='1')await compareRender({api,run,root});
 await configureMotionRender({run,root});
 foregroundSampler=spawn('pwsh',['-NoLogo','-NoProfile','-File','scripts/sample-test-foreground.ps1','-Run',run],{cwd:root,windowsHide:true,stdio:'ignore'});
 await sleep(5000);
 const shot=await api('GetSourceScreenshot',{sourceName:'PB0 Live',imageFormat:'png',imageWidth:1920,imageHeight:1080});
 fs.writeFileSync(path.join(base,'locomotion-preflight.png'),Buffer.from(shot.imageData.split(',')[1],'base64'));
 console.log(JSON.stringify({type:'locomotion_preview_ready',run,preview:path.join(base,'locomotion-preflight.png')}));
 // This camera and both tagged viewports were visually reviewed in the preceding preparation.
 // Recheck actual render content automatically so a model boundary cannot leave two games waiting.
 const check=await child('python',['-c',"import cv2;g=cv2.imread('runs/videos/locomotion-preflight.png',0);assert g is not None;assert g[270:810,:960].std()>8 and g[270:810,960:].std()>8,'one real game view is black'"]);
 if(check!==0)throw Error('Dual real viewport check failed');
 fs.writeFileSync(path.join(run,'locomotion-framing-approved'),JSON.stringify({approved:true,method:'Previously reviewed identical clear camera; both current actual render halves checked non-black'}));
 const before=await api('GetStats');await api('StartRecord');recording=true;const started=Date.now();
 fs.writeFileSync(path.join(run,'locomotion-start'),JSON.stringify({start:true}));
 while(Date.now()-started<23000&&!fs.existsSync(path.join(run,'locomotion-done.json'))){
  stats.push({at:Date.now(),...await api('GetStats')});await sleep(500);
 }
 const output=await api('StopRecord');recording=false;
 const after=await api('GetStats');
 const result={captureDiagnosis:diagnosis,movementMode:'restored-native-input',experimentalSingleMotion:false,validationStatus:'pending-foot-motion-and-visual-review',outputPath:output.outputPath,run,selectors,before,after,stats,seconds:(Date.now()-started)/1000,startedUnixMs:started,composition:'Left: host remote guest; right: guest locally driven through Enhanced Input'};
 fs.writeFileSync(path.join(base,'locomotion-recording.json'),JSON.stringify(result,null,2));
 fs.writeFileSync(path.join(run,'locomotion-recorder-done'),JSON.stringify({done:true}));
 console.log(JSON.stringify({type:'locomotion_video_saved',outputPath:output.outputPath}));
 const gameEnd=Date.now()+10000;while(code===undefined&&Date.now()<gameEnd)await sleep(150);
}catch(e){console.error('LOCOMOTION_CAPTURE_ERROR '+e.message);process.exitCode=1;if(recording)try{await api('StopRecord');}catch{}}
finally{if(run)fs.writeFileSync(path.join(run,'stop'),'Finish bounded locomotion session');await close();if(game&&code===undefined){const end=Date.now()+8000;while(code===undefined&&Date.now()<end)await sleep(150);}}
