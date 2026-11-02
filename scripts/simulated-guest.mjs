// Independent Phantom Pact 1.4.1 peer: attacks use signed UDP through the unchanged EasyTier route.
import dgram from 'node:dgram';
import crypto from 'node:crypto';
import fs from 'node:fs';
const args=process.argv.slice(2),option=(n,d)=>{const i=args.indexOf(n);return i<0?d:args[i+1];};
const invite=fs.readFileSync(option('--invite-file','runs/game-invite.txt'),'utf8').trim().split('.');
const bytes=Buffer.from(invite[1]??'','base64url');
if(invite[0]!=='PB0'||crypto.createHash('sha256').update(bytes).digest('hex').slice(0,12)!==invite[2])throw Error('Invalid invitation');
const room=JSON.parse(bytes),master=crypto.scryptSync(room.Secret,'PhantomPact/relay/1',32,{N:16384,r:8,p:1});
const key=crypto.createHmac('sha256',master).update('packet-mac').digest(),nonce=crypto.randomBytes(8),session=crypto.randomBytes(8).toString('hex');
const socket=dgram.createSocket('udp4'),lastCounters=new Map(),seenEvents=new Map(),pending=[];
const started=Date.now(),duration=Number(option('--seconds','300'))*1000,controlFile=option('--control-file');
let counter=0n,sequence=0,eventId=0,hostState,lastHostAt=0,received=0,returned=0,acked=0,lastControl='',lastAttack=0;
let control={mode:'orbit',attackPath:option('--attack-path',''),attackEveryMs:2500,attackOnce:0,range:150};
let handledAttack=0,lastReport=0,finished=false,posture=400;
const report=(type,data={})=>console.log(JSON.stringify({type,at:Date.now(),...data}));
function send(message){
  const h=Buffer.alloc(29);h.write('PPA1');h.write('C',4);nonce.copy(h,5);
  h.writeBigUInt64BE(++counter,13);h.writeBigUInt64BE(BigInt(Date.now()),21);
  const b=Buffer.concat([h,Buffer.from(JSON.stringify({...message,v:2}))]);
  socket.send(Buffer.concat([b,crypto.createHmac('sha256',key).update(b).digest()]),room.GuestGamePort,'127.0.0.1');
}
function playerLine(){
  if(!hostState||Date.now()-lastHostAt>2500)return null;
  const c=[...hostState],yaw=Number(c[5])*Math.PI/180,t=(Date.now()-started)/1000;
  const range=Number(control.range??150),side=control.mode==='orbit'?Math.sin(t*1.5)*120:0;
  const x=Number(c[2])+Math.cos(yaw)*range-Math.sin(yaw)*side,y=Number(c[3])+Math.sin(yaw)*range+Math.cos(yaw)*side;
  c[1]=String(++sequence);c[2]=x.toFixed(1);c[3]=y.toFixed(1);
  c[5]=(Math.atan2(Number(hostState[3])-y,Number(hostState[2])-x)*180/Math.PI).toFixed(1);
  c[6]=control.mode==='orbit'?'180':'0';c[7]=c[8];
  return {line:c.join(' ')+'\n',yaw:Number(c[5])};
}
function attack(target){
  if(!/^\/[\w/.-]+\.GA_Hun[\w]+$/.test(control.attackPath??''))return;
  const id=++eventId,line=id+' M '+control.attackPath+' '+target.yaw.toFixed(1);
  pending.push({id,line});lastAttack=Date.now();report('attack_sent',{id,path:control.attackPath,yaw:target.yaw});
}
socket.on('message',data=>{
  try{
    if(data.length<61||data.subarray(0,5).toString()!=='PPA1H')return;
    const b=data.subarray(0,-32),mac=data.subarray(-32);
    if(!crypto.timingSafeEqual(mac,crypto.createHmac('sha256',key).update(b).digest()))return;
    if(Math.abs(Number(data.readBigUInt64BE(21))-Date.now())>120000)return;
    const peer=data.subarray(5,13).toString('hex'),count=data.readBigUInt64BE(13);
    if(count<=(lastCounters.get(peer)??0n))return;
    lastCounters.set(peer,count);if(lastCounters.size>8)lastCounters.delete(lastCounters.keys().next().value);
    const m=JSON.parse(b.subarray(29).toString());if(m.v!==2)return;
    if(++received===1)report('native_connected');
    if(m.t==='ping')send({t:'pong',ts:m.ts});
    if(m.t==='hello')send({t:'hello',ver:'1.4.1',cfg:m.cfg??{}});
    if(m.t==='state'&&typeof m.s==='string'){
      const p=m.s.split('\n').find(x=>x.startsWith('P '));
      if(p){const c=p.trim().split(/\s+/);if(c.length>=9&&c.slice(2,9).every(x=>Number.isFinite(Number(x)))){
        if(!hostState)report('player_snapshot_received',{fields:c.length});hostState=c;lastHostAt=Date.now();
      }}
    }
    if(m.t==='state'&&m.e?.sid&&Array.isArray(m.e.l)){
      const eventSession=String(m.e.sid);let highest=0;
      for(const line of m.e.l){const m=/^(\d+)\s+(\S+)(.*)$/.exec(line);if(!m)continue;
        const id=Number(m[1]);highest=Math.max(highest,id);
        // The outer state owns the event session; retain a bounded set per session.
        const ids=seenEvents.get(eventSession)??new Set();
        if(!ids.has(id)){ids.add(id);if(m[2]==='V'){const before=posture;if(/^\s+parry\s+/.test(m[3]))posture=Math.max(0,posture-Number(m[3].trim().split(/\s+/)[1]??60));report('pvp_response',{event:line,sid:eventSession,id,postureBefore:before,postureAfter:posture});}}
        seenEvents.set(eventSession,ids);if(ids.size>2048)ids.delete(ids.values().next().value);
        if(seenEvents.size>8)seenEvents.delete(seenEvents.keys().next().value);
      }
      send({t:'ack',sid:m.e.sid,id:highest});
    }
    if(m.t==='ack'&&m.sid===session){
      if(m.id>acked){acked=m.id;report('attack_acknowledged',{id:acked});}
      while(pending.length&&pending[0].id<=m.id)pending.shift();
    }
  }catch(e){report('packet_error',{error:e.message});}
});
socket.on('error',e=>report('socket_error',{error:e.message}));
await new Promise(r=>socket.bind(0,'127.0.0.1',r));
const ping=setInterval(()=>send({t:'ping',ts:performance.now()/1000}),1000);
const tick=setInterval(()=>{
  if(controlFile){try{const text=fs.readFileSync(controlFile,'utf8');if(text!==lastControl){control={...control,...JSON.parse(text)};lastControl=text;report('control_changed',{mode:control.mode});}}catch{}}
  const target=playerLine();
  if(target){send({t:'state',s:target.line});returned++;
    if(control.attackOnce>handledAttack){handledAttack=control.attackOnce;attack(target);}
    else if(control.mode==='duel'&&Date.now()-lastAttack>Math.max(1500,Number(control.attackEveryMs)))attack(target);
  }
  if(pending.length||Date.now()-lastReport>1000)send({t:'state',e:{sid:session,l:pending.slice(0,16).map(x=>x.line)}});
  if(Date.now()-lastReport>1000){lastReport=Date.now();report('simulator_progress',{received,returned,attacks:eventId,acked});}
},50);
const finish=()=>{if(finished)return;finished=true;clearInterval(ping);clearInterval(tick);clearTimeout(timer);socket.close();report('simulator_stopped',{received,returned,attacks:eventId,acked});};
process.on('SIGINT',finish);process.on('SIGTERM',finish);
const timer=setTimeout(finish,duration);
report('simulator_started',{port:room.GuestGamePort});
