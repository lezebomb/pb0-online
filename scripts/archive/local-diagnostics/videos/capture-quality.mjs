import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {api,close} from './obs-control.mjs';
const root=path.resolve('.'),base=path.join(root,'runs/videos'),sleep=ms=>new Promise(r=>setTimeout(r,ms));
let game,run,recording=false,exitCode,outputPath;
const stats=[],report=(type,data={})=>console.log(JSON.stringify({type,...data}));
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
async function readyFile(file,ms){const end=Date.now()+ms;while(Date.now()<end){if(fs.existsSync(file))return read(file);if(exitCode!==undefined)throw Error('Game session ended: '+(run&&fs.existsSync(path.join(run,'result.json'))?read(path.join(run,'result.json')).error:exitCode));await sleep(100);}throw Error('Timeout '+path.basename(file));}
try{
 // The portable frontend may need a few seconds after websocket is listening.
 const end=Date.now()+25000;
 while(true){try{await api('GetSceneList');break;}catch(e){if(Date.now()>end)throw e;await sleep(500);}}
 await api('SetCurrentProgramScene',{sceneName:'PB0 Live'});
 await api('SetVideoSettings',{baseWidth:1920,baseHeight:1080,outputWidth:1920,outputHeight:1080,fpsNumerator:60,fpsDenominator:1});
 const host=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:'PB0 Host'}),guest=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:'PB0 Guest'});
 await api('SetSceneItemEnabled',{sceneName:'PB0 Live',sceneItemId:guest.sceneItemId,sceneItemEnabled:false});
 await api('SetInputSettings',{inputName:'PB0 Host',inputSettings:{capture_mode:'window',window:'Phantom Blade Zero  :UnrealWindow:PBZ.exe',priority:0,capture_cursor:false,capture_audio:false,limit_framerate:true},overlay:true});
 const launched=Date.now();
 game=spawn(process.execPath,['scripts/test-game-bridge.mjs','--quality-showcase','--stage','movement','--session-seconds','480'],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
 game.stdout.on('data',b=>process.stdout.write(b));game.stderr.on('data',b=>process.stderr.write(b));game.on('exit',c=>exitCode=c);
 const wait=Date.now()+200000;
 while(Date.now()<wait){
  try{const current=read(path.join(root,'runs/game-bridge-current.json'));if(Number(path.basename(current.run).replace('game-bridge-',''))>=launched){run=current.run;break;}}catch{}
  if(exitCode!==undefined)throw Error('Game launcher stopped');await sleep(100);
 }
 if(!run)throw Error('No fresh session');
 fs.writeFileSync(path.join(base,'quality-current.json'),JSON.stringify({run}));
 const config=await readyFile(path.join(run,'quality-ready.json'),200000);
 await api('SetVideoSettings',{baseWidth:config.width,baseHeight:config.height,outputWidth:config.width,outputHeight:config.height,fpsNumerator:60,fpsDenominator:1});
 await api('SetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:host.sceneItemId,sceneItemTransform:{positionX:0,positionY:0,boundsType:'OBS_BOUNDS_SCALE_INNER',boundsWidth:config.width,boundsHeight:config.height,alignment:5}});
 await sleep(1200);
 const transform=await api('GetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:host.sceneItemId});
 if(transform.sceneItemTransform.sourceWidth!==config.width||transform.sceneItemTransform.sourceHeight!==config.height)throw Error('Actual game capture texture size does not match render resolution: '+JSON.stringify(transform));
 const shot=await api('GetSourceScreenshot',{sourceName:'PB0 Live',imageFormat:'png',imageWidth:config.width,imageHeight:config.height});
 fs.writeFileSync(path.join(base,'quality-preflight.png'),Buffer.from(shot.imageData.split(',')[1],'base64'));
 const validate=spawn('python',['-c',"import cv2;g=cv2.imread('runs/videos/quality-preflight.png',0);assert g is not None and (g>12).mean()>0.15 and g.std()>8,'black capture'"],{cwd:root,windowsHide:true});
 if(await new Promise(r=>validate.on('exit',r))!==0)throw Error('No actual game image');
 report('quality_framing_preview',{run,preview:path.join(base,'quality-preflight.png')});
 const reviewEnd=Date.now()+180000;
 while(!fs.existsSync(path.join(run,'quality-framing-approved'))){
  if(Date.now()>reviewEnd||exitCode!==undefined)throw Error('No clear full-body framing approved; recording not started');
  await sleep(200);
 }
 await readyFile(path.join(run,'quality-recording-ready.json'),5000);
 if((await api('GetRecordStatus')).outputActive)throw Error('Unexpected active recording');
 await api('SetRecordDirectory',{recordDirectory:base});
 const before=await api('GetStats');
 await api('StartRecord');recording=true;
 const started=Date.now();
 fs.writeFileSync(path.join(run,'quality-start'),'Start the 30 second single-game quality showcase');
 report('quality_recording_started',{run,...config});
 let next=0;
 while(Date.now()-started<37000&&!fs.existsSync(path.join(run,'quality-done.json'))){
  if(exitCode!==undefined)throw Error('Game ended during recording');
  if(Date.now()-started>=next){
   const s=await api('GetStats');stats.push({wallMs:Date.now(),elapsedMs:Date.now()-started,...s});
   fs.writeFileSync(path.join(run,'obs-stats.json'),JSON.stringify({before,samples:stats},null,2));next+=1000;
  }
  await sleep(100);
 }
 const last=await api('GetStats'),outputs=await api('GetOutputList'),outputStats=[];
 for(const o of outputs.outputs??[])if(o.outputActive)outputStats.push({name:o.outputName,...await api('GetOutputStatus',{outputName:o.outputName})});
 const stopped=await api('StopRecord');recording=false;outputPath=stopped.outputPath;
 const after=await api('GetStats');
 const metadata={outputPath,run,settings:config,encoderRequested:'NVIDIA NVENC H.264, CQP quality preset HQ',fps:60,sourceTexture:transform.sceneItemTransform,before,last,after,outputStats,stats,completedAt:new Date().toISOString()};
 fs.writeFileSync(path.join(base,'quality-recording-output.json'),JSON.stringify(metadata,null,2));
 fs.writeFileSync(path.join(run,'quality-recorder-done'),'MP4 safely finalized');
 report('quality_recording_saved',{outputPath,renderSkipped:after.renderSkippedFrames-before.renderSkippedFrames,encodeSkipped:after.outputSkippedFrames-before.outputSkippedFrames});
 const gameEnd=Date.now()+12000;while(exitCode===undefined&&Date.now()<gameEnd)await sleep(100);
 if(exitCode===undefined)fs.writeFileSync(path.join(run,'stop'),'Recording complete');
}catch(e){report('quality_capture_error',{error:e.message,run});process.exitCode=1;
 fs.writeFileSync(path.join(base,'quality-capture-error.json'),JSON.stringify({error:e.message,run,at:new Date().toISOString()}));
 if(recording){try{const stop=await api('StopRecord');recording=false;report('partial_video',stop);}catch{}}}
finally{
 if(run){fs.writeFileSync(path.join(run,'stop'),'End owned quality capture session');}
 await close();
 if(game&&exitCode===undefined){const end=Date.now()+10000;while(exitCode===undefined&&Date.now()<end)await sleep(200);}
}