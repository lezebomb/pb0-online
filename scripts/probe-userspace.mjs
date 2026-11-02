import {spawn, execFileSync} from 'node:child_process';
import dgram from 'node:dgram';
import {mkdirSync,createWriteStream} from 'node:fs';
const dir = new URL('../tools/easytier/easytier-windows-x86_64/',import.meta.url);
const core = decodeURIComponent(new URL('easytier-core.exe',dir).pathname.slice(1));
const cli = decodeURIComponent(new URL('easytier-cli.exe',dir).pathname.slice(1));
const cores=[], sockets=[];
mkdirSync('runs/probe',{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
try {
  for (let n=1;n<=2;n++) {
    const vip=`10.233.79.${n}`, remote=`10.233.79.${3-n}`;
    const args=['--network-name','pb0-probe-'+process.pid,'--network-secret','probe-'+process.pid,
      '--ipv4',vip,'--no-tun','--use-smoltcp','true','--bind-device','false','--proxy-networks',`127.0.0.1/32->${vip}/32`,
      '--listeners',`tcp://127.0.0.1:${23100+n}`,'--rpc-portal',`127.0.0.1:${23200+n}`,
      '--hostname',`probe-${n}`,'--port-forward',`udp://127.0.0.1:${23400+n}/${remote}:${23300+3-n}`];
    if(n===2) args.push('--peers','tcp://127.0.0.1:23101');
    const p=spawn(core,args,{windowsHide:true}); cores.push(p);
    const log=createWriteStream(`runs/probe/core-${n}.log`);p.stdout.pipe(log);p.stderr.pipe(log);
    const s=dgram.createSocket('udp4');sockets.push(s);
    await new Promise(r=>s.bind(23300+n,'127.0.0.1',r));
    s.on('message',b=>console.log(`RX-${n}: ${b.toString()}`));
  }
  await sleep(4500);
  console.log(execFileSync(cli,['-p','127.0.0.1:23201','-o','json','route'],{encoding:'utf8',windowsHide:true}));
  for(let k=0;k<5;k++){
    sockets[0].send(Buffer.from('from-host'),23401,'127.0.0.1');
    sockets[1].send(Buffer.from('from-guest'),23402,'127.0.0.1');
    await sleep(500);
  }
} finally {sockets.forEach(s=>s.close());cores.forEach(p=>p.kill());}
