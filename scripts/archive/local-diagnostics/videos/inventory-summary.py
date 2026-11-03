import json,pathlib
r=pathlib.Path(json.loads(pathlib.Path('runs/dual-game-current.json').read_text())['run'])
x=json.loads((r/'guest-inventory.json').read_text(encoding='utf-8'))
for kind in ['localInput','localAnim','remoteAnim','localActor','remoteActor']:
 z=x[kind]
 print(kind,json.dumps({'class':z['class'],'fields':z['fields'],'functions':z['functions'] if kind=='localInput' else {k:v for k,v in z['functions'].items() if ('Input' in k or 'Locomotion' in k) and 'Replication' not in k}},indent=2))