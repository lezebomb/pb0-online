import {api,close} from './obs-control.mjs';
try{
 const kinds=(await api('GetInputKindList')).inputKinds;
 const kind=kinds.filter(x=>x.startsWith('text_gdiplus')).at(-1);
 if(!kind)throw Error('No native text label input');
 for(const [name,text,x] of [['PB0 Host Label','HOST: remote guest',20],['PB0 Guest Label','GUEST: local Enhanced Input',980]]){
  await api('CreateInput',{sceneName:'PB0 Live',inputName:name,inputKind:kind,inputSettings:{text,font:{face:'Arial',size:32,flags:1},color:4294967295,outline:true,outline_size:2},sceneItemEnabled:true}).catch(()=>{});
  const item=await api('GetSceneItemId',{sceneName:'PB0 Live',sourceName:name});
  await api('SetInputSettings',{inputName:name,inputSettings:{text,font:{face:'Arial',size:32,flags:1}},overlay:true});
  await api('SetSceneItemTransform',{sceneName:'PB0 Live',sceneItemId:item.sceneItemId,sceneItemTransform:{positionX:x,positionY:205,scaleX:1,scaleY:1}});
 }
 console.log('REAL_DUAL_VIEW_LABELS_READY');
}finally{await close();}