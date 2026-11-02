// Independent test peer for the published Phantom Pact 1.4.1 packet/file protocol.
// Uses a real EasyTier guest's localhost game port; not a substitute for two real combat clients.
import dgram from 'node:dgram';
import crypto from 'node:crypto';
import fs from 'node:fs';
const args=process.argv.slice(2);
const option=(name,fallback)=>{const i=args.indexOf(name);return i<0?fallback:args[i+1];};
const invitation=fs.readFileSync(option('--invite-file','runs/game-invite.txt'),'utf8').trim();
const parts=invitation.split('.');
const bytes=Buffer.from(parts[1]??'','base64url');
if(parts[0]!=='PB0'||crypto.createHash('sha256').update(bytes).digest('hex').slice(0,12)!==parts[2])throw Error('Invalid invitation');
const room=JSON.parse(bytes);
const master=crypto.scryptSync(room.Secret,'PhantomPact/relay/1',32,{N:16384,r:8,p:1});
const key=crypto.createHmac('sha256',master).update('packet-mac').digest();
const nonce=crypto.randomBytes(8),session=crypto.randomBytes(8).toString('hex');
let counter=0n, sequence=0,eventId=0,snapshot='',settings={},received=0,returned=0;
const lastCounters=new Map(),events=[],seenEvents=new Set();
const started=Date.now(),duration=Number(option('--seconds','60'))*1000;
const socket=dgram.createSocket('udp4');
const report=(type,data)=>console.log(JSON.stringify({type,...data}));
function send(message){
  const header=Buffer.alloc(29);header.write('PPA1');header.write('C',4);nonce.copy(header,5);
  header.writeBigUInt64BE(++counter,13);header.writeBigUInt64BE(BigInt(Date.now()),21);
  const body=Buffer.concat([header,Buffer.from(JSON.stringify({...message,v:2}))]);
  const packet=Buffer.concat([body,crypto.createHmac('sha256',key).update(body).digest()]);
  socket.send(packet,room.GuestGamePort,'127.0.0.1');
}
socket.on('message',data=>{
  try{
    if(data.length<61||data.subarray(0,5).toString()!=='PPA1H')return;
    const body=data.subarray(0,-32),mac=data.subarray(-32);
    if(!crypto.timingSafeEqual(mac,crypto.createHmac('sha256',key).update(body).digest()))return;
    if(Math.abs(Number(data.readBigUInt64BE(21))-Date.now())>120000)return;
    const peer=data.subarray(5,13).toString('hex'),count=data.readBigUInt64BE(13);
    if(count<=(lastCounters.get(peer)??0n))return;
    lastCounters.set(peer,count);if(lastCounters.size>8)lastCounters.delete(lastCounters.keys().next().value);
    const m=JSON.parse(body.subarray(29).toString());if(m.v!==2)return;
    if(++received===1)report('native_connected',{});
    if(m.t==='ping')send({t:'pong',ts:m.ts});
    if(m.t==='hello'){settings=m.cfg??{};send({t:'hello',ver:'1.4.1',cfg:settings});}
    if(m.t==='state'&&typeof m.s==='string'){
      const player=m.s.split('\n').find(x=>x.startsWith('P '));
      if(player){
        const columns=player.trim().split(/\s+/);
        if(columns.length>=5){columns[1]=String(++sequence);columns[2]=String(Number(columns[2])+300+Math.sin((Date.now()-started)/1000)*50);snapshot=columns.join(' ')+'\n';if(returned===0)report('player_snapshot_received',{fields:columns.length});}
      }
    }
    if(m.t==='state'&&m.e?.sid&&Array.isArray(m.e.l)){
      let highest=0;
      for(const line of m.e.l){
        const match=/^(\d+)\s+(\S+)(.*)$/.exec(line);if(!match)continue;
        highest=Math.max(highest,Number(match[1]));
        // Replay only the partner's basic attack/move events; never echo story/loot/death events.
        const id=m.e.sid+':'+match[1];
        if(!seenEvents.has(id)&&['A','M'].includes(match[2])){seenEvents.add(id);events.push(`${++eventId} ${match[2]}${match[3]}`);}
      }
      send({t:'ack',sid:m.e.sid,id:highest});
    }
    if(m.t==='ack'&&m.sid===session){while(events.length&&Number(events[0].split(' ')[0])<=m.id)events.shift();}
  }catch(e){report('packet_error',{error:e.message});}
});
await new Promise(r=>socket.bind(0,'127.0.0.1',r));
const ping=setInterval(()=>send({t:'ping',ts:performance.now()/1000}),1000);
const tick=setInterval(()=>{
  if(snapshot){send({t:'state',s:snapshot});returned++;}
  if(events.length)send({t:'state',e:{sid:session,l:events.slice(0,16)}});
},50);
const finish=()=>{clearInterval(ping);clearInterval(tick);socket.close();report('simulator_stopped',{received,returned,attacksQueued:eventId});};
process.on('SIGINT',finish);setTimeout(finish,duration);
report('simulator_started',{port:room.GuestGamePort});
