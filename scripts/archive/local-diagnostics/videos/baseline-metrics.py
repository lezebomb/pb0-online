import pathlib,json,numpy as np
r=pathlib.Path(json.loads(pathlib.Path('runs/dual-game-current.json').read_text())['run'])
summary={}
for role in ['guest','host']:
 rows=[]
 for x in (r/(role+'-locomotion.jsonl')).read_text(encoding='utf-8').splitlines():
  try: rows.append(json.loads(x))
  except json.JSONDecodeError: pass
 inventories=[x for x in rows if x['type']=='movement_inventory']
 if inventories: (r/(role+'-inventory.json')).write_text(json.dumps(inventories[-1],ensure_ascii=False,indent=2),encoding='utf-8')
 print(role,'BONES',[(x.get('count'),x.get('names'),x.get('firstBones')) for x in rows if x['type']=='foot_bones'])
 print(role,'ERRORS',[x for x in rows if x['type']=='observer_error'])
 result={}
 for phase in sorted(set(x['phase'] for x in rows if x['type']=='sample' and x['phase'].startswith(('baseline','postfix')))):
  a=[x for x in rows if x['type']=='sample' and x['phase']==phase]
  subject='player' if role=='guest' else 'ghost'
  a=[x for x in a if subject in x]
  if not a: continue
  pos=np.array([[x[subject]['x'],x[subject]['y']] for x in a]);speed=[x[subject]['speed'] for x in a];start=a[0]['time']
  late=[x for x in a if x['time']-start>.6]
  result[phase]={'samples':len(a),'travelCm':float(np.linalg.norm(pos[-1]-pos[0])),'speedMedian':float(np.median(speed)),'speedMax':float(max(speed)),'lateSpeedMax':float(max([x[subject]['speed'] for x in late] or [0])),'speedRange':sorted(set(round(x,1) for x in speed))[:15],'lastInput':a[-1][subject]['lastInput'],'end':a[-1][subject],'targetSpeed':a[-1].get('target',{}).get('Speed')}
 summary[role]=result
print(json.dumps(summary,indent=2))
(r/'baseline-metrics.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')