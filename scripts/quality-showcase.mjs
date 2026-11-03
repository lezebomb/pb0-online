import fs from 'node:fs';
import path from 'node:path';
// Reuse native PvP and the signed simulated peer; this branch directs the new recording only.
export async function qualityShowcase(c){
 const {root,run,command,saveControl,observations,pump,sleep,shouldStop,phase,cap,report,result}=c;
 const evalLua=text=>command('eval '+text);
 const until=async(test,ms,label)=>{const end=Date.now()+ms;while(Date.now()<end&&!shouldStop()){pump();if(test())return;await sleep(100);}throw Error('Quality recording timeout: '+label);};
 const status=()=>{try{return JSON.parse(fs.readFileSync(path.join(run,'quality-status.json'),'utf8'));}catch{return {};}};
 const read=name=>JSON.parse(fs.readFileSync(path.join(run,name),'utf8'));
 saveControl({mode:'idle',range:180,attackPath:cap.attackPath});
 const file=name=>JSON.stringify(path.join(root,'scripts',name).replaceAll('\\','/'));
 await evalLua('PB0_QUALITY_CONFIG={root='+JSON.stringify(run.replaceAll('\\','/'))+'} PB0_QUALITY=dofile('+file('quality-probe.lua')+')');
 await until(()=>status().ready,5000,'quality telemetry');
 await evalLua('PB0_QUALITY.resolution(1920,1080)');
 await sleep(6000);await until(()=>status().width===1920&&status().height===1080,5000,'native 1080p viewport');
 await evalLua('PB0_SCENE=dofile('+file('recording-scene.lua')+') PB0_SCENE.boardwalk()');
 await until(()=>fs.existsSync(path.join(run,'scene-selection.json')),10000,'open floor and camera sight lines');
 const anchor=()=>{const s=read('scene-selection.json');return {x:s.center.X+90,y:s.center.Y,z:s.center.Z};};
 saveControl({mode:'fixed',anchor:anchor()});
 await sleep(1800);

 fs.writeFileSync(path.join(run,'quality-ready.json'),JSON.stringify({run,width:1920,height:1080,telemetry:'quality-frame-times.csv',needsFramingReview:true}));
 report('quality_ready',{run,width:1920,height:1080,framing:read('scene-selection.json')});
 await until(()=>fs.existsSync(path.join(run,'quality-framing-approved')),180000,'clear full-body framing review');
 saveControl({mode:'fixed',anchor:anchor()});await sleep(1200);
 fs.writeFileSync(path.join(run,'quality-recording-ready.json'),JSON.stringify({ready:true}));
 await until(()=>fs.existsSync(path.join(run,'quality-start')),15000,'OBS cue');
 await evalLua('PB0_QUALITY.capture=true PB0_QUALITY.mark("capture")');
 const began=Date.now(),at=async(s)=>{while(Date.now()-began<s*1000&&!shouldStop()){pump();await sleep(50);}if(shouldStop())throw Error('Quality recording stopped');};
 const walk=async(x,y,s,scale=.2)=>evalLua('local _,p=PBZ.getPlayer1() local ending=os.clock()+'+s+' local function walk() if os.clock()<ending and PBZ.valid(p) then p:AddMovementInput({X='+x+',Y='+y+',Z=0},'+scale+',false) PBZ.game.after(0.008,walk) end end walk()');
 await phase('body-contact');await walk(1,0,1.4,.35);await at(3);
 // Both characters stay as separate capsule bodies. Back away using real movement input.
 await walk(-1,0,.7,.15);await at(5);
 await phase('quality-movement');saveControl({mode:'orbit-fixed',anchor:anchor()});
 await walk(0,1,.7,.15);await at(7);await walk(0,-1,.7,.15);await at(9);
 saveControl({mode:'fixed',anchor:anchor()});await phase('quality-attack');await at(11);
 saveControl({attackOnce:1});await at(14);await evalLua('PB0_TEST.attackOnce()');await at(17);
 await phase('block');await evalLua('PB0_TEST.defend()');await at(18);saveControl({attackOnce:2});await at(21);await evalLua('PB0_TEST.release()');
 await phase('parry');await at(23);saveControl({attackOnce:3});await at(27);
 await phase('quality-finale');saveControl({mode:'orbit-fixed',anchor:anchor()});await at(32);
 await evalLua('PB0_QUALITY.capture=false PB0_QUALITY.finish()');
 await until(()=>fs.existsSync(path.join(run,'quality-telemetry-done')),3000,'frame log flush');
 result.quality={width:1920,height:1080,seconds:(Date.now()-began)/1000,phases:['body-contact','movement','attack','block','parry'],combatAssertionsRepeated:false};
 fs.writeFileSync(path.join(run,'quality-done.json'),JSON.stringify(result.quality));
 report('quality_done',result.quality);
 await until(()=>fs.existsSync(path.join(run,'quality-recorder-done')),12000,'MP4 flush');
}