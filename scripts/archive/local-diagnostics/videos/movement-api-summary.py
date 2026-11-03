import json,pathlib
r=pathlib.Path('D:/pb0online/runs/locomotion-game-1793680942899')
i=json.loads((r/'guest-inventory.json').read_text(encoding='utf-8'))
for k in ['localActor','remoteActor','localMovement','remoteMovement','localAnim']:
 z=i[k];fn={n:p for n,p in z['functions'].items() if not n.startswith('InpActEvt') and ('Locomotion' in n or 'MoveInput' in n or 'InputMove' in n or 'MovementInput' in n)}
 print(k,json.dumps({'functions':fn,'fields':{n:v for n,v in z['fields'].items() if any(w in n.lower() for w in ['locomotion','motion','movementinput','moveinput','speed','acceleration']) and not n.startswith('AnimGraph')}},indent=2))