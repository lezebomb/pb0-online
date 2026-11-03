import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {api,close} from './obs-control.mjs';
const root=path.resolve('.'),base=path.join(root,'runs/videos'),sleep=ms=>new Promise(r=>setTimeout(r,ms));
const child=(exe,args)=>{const p=spawn(exe,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});p.stdout.on('data',b=>process.stdout.write(b));p.stderr.on('data',b=>process.stderr.write(b));p.finished=new Promise((r,j)=>{p.on('exit',r);p.on('error',j);});return p;};
let game,run;
try{
 await api('GetVersion');
 const launchedAt=Date.now();game=child(process.execPath,['scripts/test-dual-game.mjs','--showcase']);
 const end=Date.now()+230000;
 while(Date.now()<end){
  try{const r=JSON.parse(fs.readFileSync(path.join(root,'runs/dual-game-current.json'),'utf8')).run;
   if(r!==run&&Number(path.basename(r).replace(/^record-game-/,''))>=launchedAt)run=r;
   if(run&&fs.existsSync(path.join(run,'showcase-ready.json')))break;
   if(run&&fs.existsSync(path.join(run,'result.json')))throw Error(JSON.parse(fs.readFileSync(path.join(run,'result.json'),'utf8')).error??'showcase exited');
  }catch(e){if(e.message!=='ENOENT'&&!e.code&&e.message!=='Unexpected end of JSON input')throw e;}
  await sleep(250);
 }
 if(!run||!fs.existsSync(path.join(run,'showcase-ready.json')))throw Error('recording preparation exceeded bounded wait');
 await sleep(1500);
 const shot=await api('GetSourceScreenshot',{sourceName:'PB0 Live',imageFormat:'png',imageWidth:1280,imageHeight:720});
 fs.writeFileSync(path.join(base,'automatic-preflight.png'),Buffer.from(shot.imageData.split(',')[1],'base64'));
 const pre=child('python',['-c',"import cv2;g=cv2.imread('runs/videos/automatic-preflight.png',0);assert g is not None and (g>12).mean()>0.15 and g.std()>8,'game capture preview is black'"]);
 if(await pre.finished!==0)throw Error('No actual game image; do not record');
 await close();
 const recorder=child(process.execPath,['runs/videos/record-mp4.mjs']);if(await recorder.finished!==0)throw Error('Recording failed');
 await game.finished;
 const decoder=child('python',['runs/videos/verify-video.py']);if(await decoder.finished!==0)throw Error('Recorded video did not pass decoded-frame checks');
}catch(e){console.error('CAPTURE_ERROR '+e.message);process.exitCode=1;}
finally{
 if(run)fs.writeFileSync(path.join(run,'stop'),'Recording pipeline complete; close owned games.');
 await close().catch(()=>{});
 const cleaner=child('pwsh',['-NoLogo','-NoProfile','-File','runs/videos/cleanup-recording.ps1']);if(await cleaner.finished!==0)process.exitCode=1;
}