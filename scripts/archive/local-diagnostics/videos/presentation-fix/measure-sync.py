import pathlib,json,csv,numpy as np
base=pathlib.Path('D:/pb0online/runs/videos')
m=json.loads((base/'locomotion-recording.json').read_text(encoding='utf-8-sig'))
run=pathlib.Path(m['run'])
phases=['forward','stop-one','lateral','stop-two','turn','stop-three','attack','idle-final']
def readrows(r,role):
 a=[]
 for l in (r/(role+'-locomotion.jsonl')).read_text(encoding='utf-8-sig').splitlines():
  try:x=json.loads(l)
  except json.JSONDecodeError:continue
  if x.get('phase') in phases:a.append(x)
 return a
def response_lag(r):
 a=[x for x in readrows(r,'host') if x.get('type')=='sample' and x['phase'] not in ['attack','idle-final']]
 t=np.array([x['wallClock'] for x in a]);t-=t[0]
 target=np.array([[x['target'].get('VelX',0),x['target'].get('VelY',0)] for x in a]);ghost=np.array([[x['ghost']['vx'],x['ghost']['vy']] for x in a])
 lag=np.arange(0,.251,.001);scores=[]
 for dt in lag:
  wanted=np.column_stack([np.interp(t-dt,t,target[:,axis]) for axis in [0,1]])
  scores.append(np.mean(np.sum((wanted-ghost)**2,axis=1)))
 k=int(np.argmin(scores))
 return {'milliseconds':int(round(lag[k]*1000)),'metric':'Best-fit delay of actual Ghost velocity behind received authoritative velocity; host monotonic clock, ~25-40 ms sampling. Not end-to-end input latency.'}
out={'run':str(run),'video':m['outputPath'],'roles':{},'receivedToGhostVelocityLag':{'before':response_lag(pathlib.Path('D:/pb0online/runs/locomotion-game-1793686060264')),'after':response_lag(run)}}
data={role:readrows(run,role) for role in ['host','guest']}
for role in ['host','guest']:
 rows=[x for x in data[role] if x.get('type')=='sample']
 a,b=rows[0],rows[-1];seconds=(b['utcMs']-a['utcMs'])/1000
 frames=[x for x in csv.DictReader((run/role/'quality-frame-times.csv').open()) if x['capture']=='1']
 utc=np.array([float(x['utcMs']) for x in frames])/1000;fr=np.array([int(x['frame']) for x in frames])
 rec=[x for x in data[role] if x.get('type')=='motion_trace' and x.get('kind')=='received' and x.get('sourceUtcMs')]
 transit=np.array([x['utcMs']-x['sourceUtcMs'] for x in rec]);intervals=np.diff([x['utcMs'] for x in rec])
 clockdiff=np.diff([x['utcMs'] for x in rows])-np.diff([x['wallClock']*1000 for x in rows])
 r={'fpsBySharedUTC':float((fr[-1]-fr[0])/(utc[-1]-utc[0])),'frameIntervalMsP50P95':np.percentile(np.diff(utc)*1000,[50,95]).tolist(),'sendHz':(b['localSeq']-a['localSeq'])/seconds,'acceptedReceiveHz':(b['remoteDriver']['accepted']-a['remoteDriver']['accepted'])/seconds,'stateSampleToReceiverMsP50P95':np.percentile(transit,[50,95]).tolist(),'receiveIntervalMsP50P95':np.percentile(intervals,[50,95]).tolist(),'outOfOrder':b['remoteDriver']['reordered']-a['remoteDriver']['reordered'],'skippedSequence':b['remoteDriver']['skipped']-a['remoteDriver']['skipped'],'clockStepDisagreementMsMax':float(abs(clockdiff).max())}
 out['roles'][role]=r
out['movementOnsetLagMs']={}
out['renderedSourceAgeMs']={}
for phase in ['forward','lateral','turn']:
 h=[x for x in data['host'] if x.get('type')=='sample' and x['phase']==phase and x['ghost']['speed']>20]
 g=[x for x in data['guest'] if x.get('type')=='sample' and x['phase']==phase and x['player']['speed']>20]
 out['movementOnsetLagMs'][phase]=h[0]['utcMs']-g[0]['utcMs']
 ages=[x['utcMs']-x['remoteDriver']['render']['sourceUtcMs'] for x in h if x['remoteDriver']['render'].get('sourceUtcMs')]
 out['renderedSourceAgeMs'][phase]=np.percentile(ages,[50,95]).tolist()
def events(role):
 a=[]
 for l in (run/(role+'-observations.jsonl')).read_text().splitlines():
  try:a.append(json.loads(l))
  except json.JSONDecodeError:pass
 return a
source=[x for x in events('guest') if x.get('type')=='local_attack' and x.get('ok')]
remote=[x for x in events('host') if x.get('type')=='remote_move_applied']
assert len(source)==1 and len(remote)==1
out['oneAttackLocalAbilityToRemoteAbilityMs']=remote[0]['utcMs']-source[0]['utcMs']
out['packetLoss']='Not independently measured: sequence skips include latest-file coalescing and relay polling.'
(base/'presentation-fix/delivery-sync.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))
