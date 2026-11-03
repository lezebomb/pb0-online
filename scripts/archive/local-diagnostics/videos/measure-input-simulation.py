from pathlib import Path
import json,numpy as np,csv
b=Path('D:/pb0online/runs/videos');m=json.loads((b/'locomotion-recording.json').read_text());r=Path(m['run']);old=Path('D:/pb0online/runs/locomotion-game-1793690316676')
phases=['forward','lateral','turn']
def read(r,role):
 a=[]
 for l in (r/(role+'-locomotion.jsonl')).read_text().splitlines():
  try:a.append(json.loads(l))
  except json.JSONDecodeError:pass
 return a
data={role:read(r,role) for role in ['host','guest']}
def pct(a):return {'n':len(a),'p50':float(np.percentile(a,50)),'p95':float(np.percentile(a,95))} if a else None
def transition_times(r,role,who):
 rows=[x for x in read(r,role) if x.get('type')=='sample' and x['phase'] in phases+['stop-one','stop-two','stop-three']]
 ans={}
 for phase in phases:
  group={ 'forward':['forward','stop-one'], 'lateral':['lateral','stop-two'], 'turn':['turn','stop-three']}[phase]
  a=[x for x in rows if x['phase'] in group];active=[i for i,x in enumerate(a) if x[who]['speed']>3]
  if not active:continue
  first=active[0];last=active[-1];stop=next((x for x in a[last+1:] if x[who]['speed']<=3),None)
  ans[phase]={'start':a[first]['utcMs'],'stop':stop['utcMs'] if stop else None}
 return ans
out={'run':str(r),'video':m['outputPath'],'clock':'UTC-anchored monotonic per-process clock; startup calibration anchors clocks on this computer, later timestamps ignore wall-clock steps','beforeAfterSampledMotionLagMs':{},'stages':{},'roles':{},'onsets':{}}
for name,run in [('before',old),('after',r)]:
 source=transition_times(run,'guest','player');ghost=transition_times(run,'host','ghost')
 out['beforeAfterSampledMotionLagMs'][name]={'start':pct([ghost[p]['start']-source[p]['start'] for p in phases if p in ghost and p in source]),'stop':pct([ghost[p]['stop']-source[p]['stop'] for p in phases if p in ghost and p in source and ghost[p]['stop'] and source[p]['stop']])}
source=data['guest'];host=data['host']
for phase in phases:
 s=next(x for x in source if x['type']=='input_injected' and x['phase']==phase and abs(x['x'])+abs(x['y'])>.01)
 local=next(x for x in source if x['type']=='actor_motion' and x['phase']==phase and x['who']=='player' and x['moving'])
 remote=next(x for x in host if x['type']=='actor_motion' and x['phase']==phase and x['who']=='ghost' and x['moving'])
 applied=next(x for x in host if x.get('type')=='motion_trace' and x.get('kind')=='input_applied' and x['phase']==phase and abs(x.get('ix',0))+abs(x.get('iy',0))>.02)
 out['onsets'][phase]={'injectionToLocalMs':local['utcMs']-s['utcMs'],'injectionToGhostMs':remote['utcMs']-s['utcMs'],'localToGhostMs':remote['utcMs']-local['utcMs'],'injectionToApplyMs':applied['utcMs']-s['utcMs']}
out['stages']['nativeInputInjectionToGhostMs']=pct([x['injectionToGhostMs'] for x in out['onsets'].values()])
sent={x['seq']:x for x in source if x.get('type')=='motion_trace' and x.get('kind')=='input_sent' and x['phase'] in phases+['stop-one','stop-two','stop-three','attack','idle-final']}
arrived=[x for x in host if x.get('type')=='motion_trace' and x.get('kind')=='input_event_arrived' and x.get('seq') in sent]
out['stages']['inputEventAppendToHostDispatchMs']=pct([x['utcMs']-sent[x['seq']]['utcMs'] for x in arrived])
applied=[x for x in host if x.get('type')=='motion_trace' and x.get('kind')=='input_applied' and x['phase'] in phases+['stop-one','stop-two','stop-three','attack','idle-final']]
out['stages']['hostReceiveToGameThreadApplyMs']=pct([x['utcMs']-x['receivedMs'] for x in applied])
out['stages']['appliedByOrigin']={origin:sum(x.get('origin')==origin for x in applied) for origin in ['event','snapshot']}
def eventlog(role):
 a=[]
 for l in (r/(role+'-observations.jsonl')).read_text().splitlines():
  try:a.append(json.loads(l))
  except json.JSONDecodeError:pass
 return a
s=[x for x in eventlog('guest') if x.get('type')=='local_attack' and x.get('ok')];g=[x for x in eventlog('host') if x.get('type')=='remote_move_applied']
out['ordinaryAttackAppliedMs']=g[0]['utcMs']-s[0]['utcMs'];out['attackCount']=[len(s),len(g)]
for role in ['host','guest']:
 rows=[x for x in data[role] if x.get('type')=='sample' and x['phase'] in phases+['stop-one','stop-two','stop-three','attack','idle-final']]
 a,z=rows[0],rows[-1];duration=(z['utcMs']-a['utcMs'])/1000
 f=[x for x in csv.DictReader((r/role/'quality-frame-times.csv').open()) if x['capture']=='1']
 t=np.array([float(x['utcMs']) for x in f])/1000;frames=np.array([int(x['frame']) for x in f])
 received=[x for x in data[role] if x.get('type')=='motion_trace' and x.get('kind')=='received' and x['phase'] in phases+['stop-one','stop-two','stop-three','attack','idle-final']]
 times=[x['utcMs'] for x in received];who='ghost' if role=='host' else 'player'
 out['roles'][role]={'actualFPS':float((frames[-1]-frames[0])/(t[-1]-t[0])),'frameIntervalP50P95Ms':np.percentile(np.diff(t)*1000,[50,95]).tolist(),'sendHz':(z['localSeq']-a['localSeq'])/duration,'acceptedReceiveHz':(z['remoteDriver']['accepted']-a['remoteDriver']['accepted'])/duration,'snapshotReceiveIntervalMs':pct(list(np.diff(times))),'snapshotSampleToReceiveMs':pct([x['utcMs']-x['sourceUtcMs'] for x in received]),'correctionEpisodes':z['remoteDriver']['corrections']-a['remoteDriver']['corrections'],'correctionFrames':z['remoteDriver']['correctionFrames']-a['remoteDriver']['correctionFrames'],'watchdogStops':z['remoteDriver']['watchdogStops']-a['remoteDriver']['watchdogStops'],'walkingTeleports':z['remoteDriver']['teleports']-a['remoteDriver']['teleports'],'capsuleActorGapMaxCm':max(x[who].get('capsuleActorGap',-1) for x in rows),'meshCapsuleXYGapMaxCm':max(x[who].get('meshCapsuleGapXY',-1) for x in rows),'capsulePawnCollisionResponses':sorted(set(x[who].get('pawnCollision',-1) for x in rows))}
 clock=next(x['clock'] for x in data[role] if x.get('type')=='input_capabilities')
 out['roles'][role]['clockCalibration']=clock
(b/'input-simulation-latency.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))
