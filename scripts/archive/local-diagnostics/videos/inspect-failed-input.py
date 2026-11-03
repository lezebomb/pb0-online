import pathlib,json
r=pathlib.Path(json.loads(pathlib.Path('runs/videos/locomotion-recording.json').read_text())['run'])
a=[]
for line in (r/'host-locomotion.jsonl').read_text(encoding='utf-8').splitlines():
 try:x=json.loads(line)
 except:continue
 if x['type']=='sample' and x['phase'] in ['lateral','turn'] and x.get('target',{}).get('Speed',0)>20:a.append(x)
for x in a[::max(1,len(a)//5)]:
 print(json.dumps({'phase':x['phase'],'target':x['target'],'remoteDriver':x['remoteDriver'],'gameInputMode':x['ghost'].get('gameInputMode'),'nativeInput':x['ghost'].get('nativeMoveInput'),'velocity':x['ghost']['speed'],'maxWalk':x['ghost']['maxWalkSpeed'],'rootMotion':x['ghost']['rootMotion']},indent=2))