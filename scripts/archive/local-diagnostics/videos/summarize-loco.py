import json,pathlib,numpy as np
r=pathlib.Path(json.loads(pathlib.Path('runs/dual-game-current.json').read_text())['run'])
for role in ['host','guest']:
 p=r/(role+'-locomotion.jsonl')
 rows=[]
 for line in p.read_text(encoding='utf-8').splitlines():
  try: rows.append(json.loads(line))
  except json.JSONDecodeError as e: print('INVALID_JSON',role,e.pos,repr(line[max(0,e.pos-40):e.pos+90]))
 cap=next((x for x in rows if x['type']=='input_capabilities'),None)
 samples=[x for x in rows if x['type']=='sample']
 print(json.dumps({'role':role,'capabilities':cap,'firstSample':samples[0] if samples else None,'errors':[x for x in rows if x['type']=='observer_error']},indent=2))