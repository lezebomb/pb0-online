import json,pathlib,csv,numpy as np
b=pathlib.Path('D:/pb0online/runs/videos')
meta=json.loads((b/'quality-recording-output.json').read_text())
r=pathlib.Path(meta['run'])
scenes=[json.loads(x) for x in (r/'scene-observations.jsonl').read_text().splitlines()]
scenes=[x for x in scenes if x['capture']]
first,last=meta['stats'][0]['wallMs'],meta['stats'][-1]['wallMs']
progress=[json.loads(x) for x in (r/'simulator.jsonl').read_text().splitlines()]
progress=[x for x in progress if x['type']=='simulator_progress' and first<=x['at']<=last]
a,z=progress[0],progress[-1]
duration=(z['at']-a['at'])/1000
obs=[json.loads(x) for x in (r/'game-observations.jsonl').read_text().splitlines()]
motion=list(csv.DictReader((r/'quality-motion.csv').open()))
capturePhases={'body-contact','quality-movement','quality-attack','block','parry','quality-finale'}
motion=[x for x in motion if x['phase'] in capturePhases]
gaps=[np.hypot(float(x['playerX'])-float(x['ghostX']),float(x['playerY'])-float(x['ghostY'])) for x in motion]
seq=[int(x['targetSeq']) for x in motion];times=[float(x['realSeconds']) for x in motion]
log=dict(run=str(r),framing={'samples':len(scenes),'fullyInFrame':sum(x['framed'] for x in scenes),'outOfFrame':sum(not x['framed'] for x in scenes),'indices':sorted(set(x['index'] for x in scenes)),'note':'Bounds cover both capsule head/feet plus horizontal margins. Actual decoded frames are reviewed separately for decorative occlusion.'},body={'radiusSumCm':scenes[0]['minimumDistance'],'minimumObservedSeparationCm':float(min(gaps)),'correctionsAtEnd':max(x['bodyCorrections'] for x in scenes),'nativeBidirectionalSweepProof':'D:/pb0online/runs/game-bridge-1793673910709/body-collision-proof.json'},sync={'secondsMeasured':duration,'peerGeneratedStatesHz':(z['returned']-a['returned'])/duration,'gameUniqueStatesReceivedByPeerHz':(z['hostUnique']-a['hostUnique'])/duration,'targetSequenceRateAtGameHz':(seq[-1]-seq[0])/(times[-1]-times[0]),'distinctTargetChangesObservedAt20HzProbe':sum(x!=y for x,y in zip(seq,seq[1:]))/(times[-1]-times[0]),'probeLimit':'Motion probe samples at about 20Hz, so distinct target changes is a lower bound, not a full application-rate measurement. The later state-file sampler ran after game shutdown and is invalid for cadence.'},combatEvents=[x for x in obs if x['type'] in ['local_attack','guard_activation','deflect_input','engine_deflect','native_parry_sent','remote_move_applied']])
(b/'interaction-validation.json').write_text(json.dumps(log,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(log,ensure_ascii=False,indent=2))