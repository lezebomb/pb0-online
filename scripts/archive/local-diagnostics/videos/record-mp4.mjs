import fs from 'node:fs';
import path from 'node:path';
import {api,close} from './obs-control.mjs';
const root=path.resolve('.'),base=path.join(root,'runs/videos');
const run=JSON.parse(fs.readFileSync(path.join(root,'runs/dual-game-current.json'),'utf8')).run;
const report=(type,data={})=>console.log(JSON.stringify({type,...data})),sleep=ms=>new Promise(r=>setTimeout(r,ms));
let recording=false,output;
try{
 if(!fs.existsSync(path.join(run,'showcase-ready.json')))throw Error('Real games are not ready');
 const status=await api('GetRecordStatus');if(status.outputActive)throw Error('Unexpected existing recording');
 await api('SetRecordDirectory',{recordDirectory:base});
 await api('StartRecord');recording=true;const started=Date.now();
 fs.writeFileSync(path.join(run,'showcase-start'),'OBS recording started; render actual gameplay for 60 seconds.');report('recording_started',{run});
 let next=15;
 while(Date.now()-started<68000){
  if(fs.existsSync(path.join(run,'showcase-done.json')))break;
  if(fs.existsSync(path.join(run,'result.json'))){const r=JSON.parse(fs.readFileSync(path.join(run,'result.json'),'utf8'));if(r.error)throw Error(r.error);}
  const elapsed=(Date.now()-started)/1000;
  if(elapsed>=next){const s=await api('GetSourceScreenshot',{sourceName:'PB0 Live',imageFormat:'png',imageWidth:1280,imageHeight:720});fs.writeFileSync(path.join(base,'recording-frame-'+String(next).padStart(3,'0')+'.png'),Buffer.from(s.imageData.split(',')[1],'base64'));report('recording_progress',{seconds:Math.round(elapsed)});next+=15;}
  await sleep(200);
 }
 output=await api('StopRecord');recording=false;
 const metadata={status:'recorded_pending_decoded_frame_validation',outputPath:output.outputPath,showcaseRun:run,completedAt:new Date().toISOString(),source:'OBS Direct3D 12 game-capture shared texture',desktopLocked:true,composition:'Single real game viewport showing both real actors'};
 fs.writeFileSync(path.join(base,'recording-output.json'),JSON.stringify(metadata,null,2));report('recording_stopped',metadata);
}catch(e){report('recording_error',{error:e.message});process.exitCode=1;if(recording){try{output=await api('StopRecord');report('partial_recording',{outputPath:output.outputPath});}catch{}}}
finally{fs.writeFileSync(path.join(run,'stop'),'Recording finished. Close all owned game processes.');await close();}