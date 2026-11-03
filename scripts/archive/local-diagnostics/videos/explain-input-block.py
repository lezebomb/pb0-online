import pathlib,json
r=pathlib.Path('D:/pb0online/runs/locomotion-game-1793682988889')
rows=[]
for line in (r/'guest-locomotion.jsonl').read_text(encoding='utf-8').splitlines():
 try:x=json.loads(line)
 except:continue
 if x['type']=='sample' and x['phase']=='postfix-forward':rows.append(x)
for x in rows[::max(1,len(rows)//4)]:
 p=x['player']
 print(json.dumps({'time':x['time'],'input':p.get('nativeMoveInput'),'lastInput':p['lastInput'],'speed':p['speed'],'maxWalk':p['maxWalkSpeed'],'acceleration':p['acceleration'],'gameMode':p.get('gameInputMode'),'rootMotion':p['rootMotion'],'position':[p['x'],p['y'],p['z']]},indent=2))