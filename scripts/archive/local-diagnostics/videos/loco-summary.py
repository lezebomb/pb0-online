import pathlib,json
v=json.loads(pathlib.Path('runs/videos/locomotion-validation.json').read_text(encoding='utf-8'))
print(json.dumps({'video':v['video'],'obs':v['obs'],'recording':v['recording']},indent=2))
for role in ['guest','host']:
 print(role)
 for name,x in v['roles'][role]['phases'].items():
  if name in ['forward','lateral','turn','stop-one','stop-two','stop-three']:
   print(name,json.dumps({k:x[k] for k in ['travelCm','activeSpeedMedian','tailTravelCm','tailSpeedMax','gaits','footPlantFraction','lowerFootSpeedRatioMedian','maxPositionStepCm']}))
r=pathlib.Path(v['run'])
rows=[]
for line in (r/'host-locomotion.jsonl').read_text(encoding='utf-8').splitlines():
 try:x=json.loads(line)
 except:continue
 if x['type']=='sample' and x['phase'] in ['forward','lateral','turn'] and x.get('target',{}).get('Speed',0)>25:rows.append(x)
print('GAIT_WIRE',json.dumps({'samples':len(rows),'receivedGaits':sorted(set(x['target'].get('Gait',-1) for x in rows)),'matchingNativeGait':sum(x['ghost']['animation']['gait']==x['target'].get('Gait') for x in rows),'hookErrors':sorted(set(x['remoteDriver'].get('gaitError','') for x in rows)),'hookActive':all(x['remoteDriver'].get('gaitHook') for x in rows)}))