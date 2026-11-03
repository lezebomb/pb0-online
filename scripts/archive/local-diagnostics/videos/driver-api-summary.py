import json,pathlib
r=pathlib.Path(json.loads(pathlib.Path('runs/dual-game-current.json').read_text())['run'])
i=json.loads((r/'guest-inventory.json').read_text(encoding='utf-8'))
for k in ['localDriver','remoteDriver']:
 z=i[k]
 print(k,json.dumps({'class':z.get('class'),'functionNames':list(z.get('functions',{})),'fields':z.get('fields',{})},indent=2))