import fs from 'node:fs';
import path from 'node:path';
import {api,close} from './obs-control.mjs';
const base=path.resolve('runs/videos'),run=JSON.parse(fs.readFileSync(path.join(base,'quality-current.json'),'utf8')).run;
const command=path.resolve('game-instances/host/platform/steam/ue4ss/Mods/PBZCoop/cmd.txt');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
try{
 for(let index=1;index<=8;index++){
  const end=Date.now()+2500;
  while(fs.readFileSync(command,'utf8').trim()&&Date.now()<end)await sleep(60);
  fs.writeFileSync(command,'eval PB0_SCENE.select('+index+')\n');
  await sleep(850);
  const s=JSON.parse(fs.readFileSync(path.join(run,'scene-selection.json'),'utf8'));
  const file=path.join(run,'simulator-control.json'),c=JSON.parse(fs.readFileSync(file,'utf8'));
  c.mode='fixed';c.anchor={x:s.center.X+90,y:s.center.Y,z:s.center.Z};fs.writeFileSync(file,JSON.stringify(c));
  await sleep(250);
  const shot=await api('GetSourceScreenshot',{sourceName:'PB0 Live',imageFormat:'png',imageWidth:1280,imageHeight:720});
  fs.writeFileSync(path.join(base,'framing-choice-'+index+'.png'),Buffer.from(shot.imageData.split(',')[1],'base64'));
 }
 console.log(JSON.stringify({run,choices:8}));
}finally{await close();}