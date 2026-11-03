import fs from 'node:fs';
const base='D:/pb0online/game-instances/host/platform/steam/ue4ss/Mods/PBZCoop/';
const run=JSON.parse(fs.readFileSync('runs/videos/quality-current.json','utf8')).run;
const start=performance.now(),observed={out:[],in:[]},last={};
while(performance.now()-start<12000){
 for(const [kind,name] of [['out','net_out.txt'],['in','net_in.txt']]){
  try{const text=fs.readFileSync(base+name,'utf8'),seq=/^P (\d+)/m.exec(text)?.[1];
   if(seq&&seq!==last[kind]){last[kind]=seq;observed[kind].push({wallMs:Date.now(),ms:performance.now()-start,seq:Number(seq)});}
  }catch{}
 }
 await new Promise(r=>setTimeout(r,4));
}
const result={seconds:(performance.now()-start)/1000,streams:{}};
for(const [kind,rows] of Object.entries(observed)){
 const span=(rows.at(-1)?.ms-rows[0]?.ms)/1000;
 result.streams[kind]={distinctSnapshots:rows.length,distinctHz:span>0?(rows.length-1)/span:0,sequenceHz:span>0?(rows.at(-1).seq-rows[0].seq)/span:0,rows};
}
fs.writeFileSync(run+'/state-cadence.json',JSON.stringify(result,null,2));
console.log(JSON.stringify({seconds:result.seconds,streams:Object.fromEntries(Object.entries(result.streams).map(([k,v])=>[k,{distinctHz:v.distinctHz,sequenceHz:v.sequenceHz,snapshots:v.distinctSnapshots}]))}));