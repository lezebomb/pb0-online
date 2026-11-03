import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const base=path.resolve('runs/videos'),config=JSON.parse(fs.readFileSync(path.join(base,'obs-control.json'),'utf8').replace(/^\uFEFF/,''));
const auth=JSON.parse(fs.readFileSync(config.config,'utf8').replace(/^\uFEFF/,''));
const pending=new Map();let seq=0;
const socket=new WebSocket('ws://127.0.0.1:'+config.port);
let readyResolve,readyReject;const ready=new Promise((r,j)=>{readyResolve=r;readyReject=j;});
ready.catch(()=>{});
const timer=setTimeout(()=>readyReject(Error('OBS control handshake timeout')),15000);
socket.addEventListener('error',()=>readyReject(Error('OBS control connection error')));
socket.addEventListener('message',e=>{
 const m=JSON.parse(e.data);
 if(m.op===0){let authentication;const a=m.d.authentication;if(a){const secret=crypto.createHash('sha256').update(auth.server_password+a.salt).digest('base64');authentication=crypto.createHash('sha256').update(secret+a.challenge).digest('base64');}socket.send(JSON.stringify({op:1,d:{rpcVersion:1,eventSubscriptions:0,...(authentication?{authentication}:{})}}));}
 if(m.op===2){clearTimeout(timer);readyResolve();}
 if(m.op===7){const p=pending.get(m.d.requestId);if(p){pending.delete(m.d.requestId);clearTimeout(p.timer);m.d.requestStatus.result?p.resolve(m.d.responseData??{}):p.reject(Error(m.d.requestType+': '+m.d.requestStatus.comment));}}
});
export async function api(requestType,requestData={}){
 await ready;return await new Promise((resolve,reject)=>{const requestId=String(++seq),timer=setTimeout(()=>{pending.delete(requestId);reject(Error(requestType+' timeout'));},12000);pending.set(requestId,{resolve,reject,timer});socket.send(JSON.stringify({op:6,d:{requestType,requestId,requestData}}));});
}
export async function close(){socket.close();}
async function main(){
 const cmd=process.argv[2]??'status';
 if(cmd==='status'){const v=await api('GetVersion'),video=await api('GetVideoSettings'),scenes=await api('GetSceneList');console.log(JSON.stringify({obs:v.obsVersion,websocket:v.obsWebSocketVersion,video,scenes}));}
 if(cmd==='setup'){
  const name='PB0 Live';await api('CreateScene',{sceneName:name}).catch(()=>{});await api('SetCurrentProgramScene',{sceneName:name});
  const existing=await api('GetInputList');for(const i of existing.inputs??[])await api('SetInputMute',{inputName:i.inputName,inputMuted:true}).catch(()=>{});
  for(const name of ['PB0 Host','PB0 Guest'])await api('CreateInput',{sceneName:'PB0 Live',inputName:name,inputKind:'game_capture',inputSettings:{capture_mode:'window',capture_cursor:false,capture_audio:false,allow_transparency:false,limit_framerate:true},sceneItemEnabled:true}).catch(()=>{});
  const defaults=await api('GetInputDefaultSettings',{inputKind:'game_capture'});
  const windows=await api('GetInputPropertiesListPropertyItems',{inputName:'PB0 Host',propertyName:'window'});
  console.log(JSON.stringify({defaults,windows}));
 }
 if(cmd==='select'){
  const file=JSON.parse(fs.readFileSync(process.argv[3],'utf8').replace(/^\uFEFF/,''));
  for(const item of file.sources){await api('SetInputSettings',{inputName:item.name,inputSettings:{capture_mode:'window',window:item.window,priority:0,capture_cursor:false,capture_audio:false,limit_framerate:true},overlay:true});const id=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:item.name});await api('SetSceneItemEnabled',{sceneName:'PB0 Live',sceneItemId:id.sceneItemId,sceneItemEnabled:item.enabled!==false});if(item.enabled!==false)await api('SetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:id.sceneItemId,sceneItemTransform:{positionX:item.x??0,positionY:0,boundsType:'OBS_BOUNDS_SCALE_INNER',boundsWidth:960,boundsHeight:540,alignment:5}});}
  console.log(JSON.stringify({selected:file.sources.map(x=>({name:x.name,enabled:x.enabled!==false}))}));
 }
 if(cmd==='single'){
  await api('SetVideoSettings',{baseWidth:1280,baseHeight:720,outputWidth:1280,outputHeight:720,fpsNumerator:30,fpsDenominator:1});
  const left=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:'PB0 Host'}),right=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:'PB0 Guest'});
  await api('SetSceneItemEnabled',{sceneName:'PB0 Live',sceneItemId:right.sceneItemId,sceneItemEnabled:false});
  await api('SetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:left.sceneItemId,sceneItemTransform:{positionX:0,positionY:0,boundsType:'OBS_BOUNDS_SCALE_INNER',boundsWidth:1280,boundsHeight:720,alignment:5}});
  console.log(JSON.stringify({layout:'one actual game viewport, both real characters',width:1280,height:720,fps:30}));
 }
 if(cmd==='preview'){
  const screenshot=await api('GetSourceScreenshot',{sourceName:'PB0 Live',imageFormat:'png',imageWidth:1280,imageHeight:720});
  const file=process.argv[3]??path.join(base,'capture-preview.png');fs.writeFileSync(file,Buffer.from(screenshot.imageData.split(',')[1],'base64'));console.log(JSON.stringify({preview:path.resolve(file)}));
 }
 if(cmd==='start')console.log(JSON.stringify(await api('StartRecord')));
 if(cmd==='stop')console.log(JSON.stringify(await api('StopRecord')));
 await close();
}
if(process.argv[1]?.endsWith('obs-control.mjs'))main().catch(async e=>{console.error(e.message);process.exitCode=1;await close();});