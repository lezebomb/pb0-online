import csv,json,pathlib,numpy as np
b=pathlib.Path('D:/pb0online/runs/videos')
m=json.loads((b/'quality-recording-output.json').read_text())
r=pathlib.Path(m['run'])
d=[x for x in csv.DictReader((r/'quality-frame-times.csv').open()) if x['capture']=='1']
t0=float(d[0]['realSeconds']);out=[];dreal=[]
for a,x in zip(d,d[1:]):
 interval=(float(x['realSeconds'])-float(a['realSeconds']))*1000
 dreal.append(interval)
 if interval>33.333:
  out.append({'relativeSeconds':float(x['realSeconds'])-t0,'phase':x['phase'],'engineDeltaMs':float(x['worldDeltaMs']),'realFrameIntervalMs':interval})
v=json.loads((b/'quality-validation.json').read_text())
v['performance']['realFrameIntervals']={'median':float(np.median(dreal)),'p95':float(np.percentile(dreal,95)),'max':float(np.max(dreal)),'hitches':out}
v['manualReviewPending']=False
v['review']={
 'actualGameFootage':True,
 'scene':'Real bamboo boardwalk map; local player plus simulated peer; foreground bamboo obstructs part of the scene. Later root-motion movement carries actors partly outside fixed framing.',
 'motions':'Native movement, local/remote attack, normal guard and engine Perfect deflect events were present in this recording session; no combat assertions rerun.',
 'background':'Fixed camera background is largely stable; fitted translation p95 0.061 pixels at 640px analysis width. Does not validate ordinary following-camera smoothness.',
 'remainingProblems':'One start-of-capture game-thread hitch; simulated peer still has visible chase/stop and sliding-like corrections. Picture quality alone does not explain these.',
 'syncAnalysis':[
  'Peer uses a nominal 50ms timer, but target sequence progression in this session was about 16.8 per second.',
  'Simulated target is recomputed relative to current local-player position/yaw; turning changes target trajectory, and the transmitted orbit speed is fixed at 180 rather than derived from trajectory.',
  'Existing Phantom Pact steering uses a 60cm stop radius, catch-up speed proportional to distance, and capped prediction; this can create visible chase/stop motion with that synthetic target.',
  'Walking animation was active through normal CharacterMovement: movement samples had no movement with zero reported velocity. A completely absent locomotion velocity is not supported.',
  'Root Motion was active during abilities; busy protection yields to correction when error exceeds 200cm. This interaction is plausible, not established as the root cause by this one clip.'
 ],
 'changes':'Only opt-in recording orchestration and read-only diagnostics added; no EasyTier, simulated-guest movement algorithm, original game executable or PvP logic changed.',
 'limit1080':'900p selected after 3s warmup was affected by a loading stall; steady-state 900p was much faster. 1080p performance remains unverified, and no second recording was made.',
 'cleanup':'Owned games, simulator, launchers, EasyTier cores and portable capture OBS stopped. Play mode restored; all 26 latest personal files and backup hashes match.',
 'encoderConfirmed':'OBS log: NVENC H.264, CQP 16, preset p5',
 'referenceMethods':[
  'https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/Kismet/UKismetSystemLibrary?application_version=5.5',
  'https://obsproject.com/kb/advanced-recording-settings-guide'
 ]
}
(b/'quality-validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(v['performance']['realFrameIntervals'],indent=2))