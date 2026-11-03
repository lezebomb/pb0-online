import pathlib,json
r=pathlib.Path(json.loads(pathlib.Path('runs/dual-game-current.json').read_text())['run'])
for role in ['guest','host']:
 inv=None
 for line in (r/(role+'-locomotion.jsonl')).read_text(encoding='utf-8').splitlines():
  try: x=json.loads(line)
  except json.JSONDecodeError: continue
  if x['type']=='movement_inventory':inv=x
 if inv:
  (r/(role+'-inventory.json')).write_text(json.dumps(inv,ensure_ascii=False,indent=2),encoding='utf-8')
  for k in ['localProvider','remoteProvider','localDriver']:
   print(role,k,json.dumps(inv[k],ensure_ascii=False,indent=2))
 else: print(role,'inventory not yet ready')