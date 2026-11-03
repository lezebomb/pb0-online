import pathlib,json,csv,numpy as np,cv2
b=pathlib.Path('D:/pb0online/runs/videos')
m=json.loads((b/'locomotion-recording.json').read_text(encoding='utf-8-sig'))
run=pathlib.Path(m['run']);baseline=pathlib.Path('D:/pb0online/runs/locomotion-game-1793690316676')
phases=['forward','stop-one','lateral','stop-two','turn','stop-three','attack','idle-final']
def rows(r,role):
 result=[]
 for line in (r/(role+'-locomotion.jsonl')).read_text(encoding='utf-8-sig').splitlines():
  try:a=json.loads(line)
  except json.JSONDecodeError:continue
  if a.get('type')=='sample' and a.get('phase') in phases:result.append(a)
 return result
def metrics(r,role):
 a=rows(r,role);who='ghost' if role=='host' else 'player'
 f=[x for x in csv.DictReader((r/role/'quality-frame-times.csv').open()) if x['capture']=='1']
 times=np.array([float(x['realSeconds']) for x in f]);frames=np.array([int(x['frame']) for x in f])
 result={'fps':float((frames[-1]-frames[0])/(times[-1]-times[0])),'frameMsP50P95':np.percentile([float(x['worldDeltaMs']) for x in f],[50,95]).tolist(),'phases':{}}
 duration=a[-1]['time']-a[0]['time']
 changes=[x for i,x in enumerate(a) if i==0 or x['targetSeq']!=a[i-1]['targetSeq']]
 dt=np.diff([x['time'] for x in changes]);seq=np.diff([x['targetSeq'] for x in changes])
 result['observedReceiveHz']=float(len(dt)/sum(dt));result['receiveMsP50P95']=np.percentile(dt*1000,[50,95]).tolist()
 result['observedSeqGaps']=int(np.maximum(0,seq-1).sum())
 if 'localSeq' in a[0]:
  result['actualSendHz']=(a[-1]['localSeq']-a[0]['localSeq'])/duration
  driver=a[-1]['remoteDriver'];old=a[0]['remoteDriver']
  result['acceptedReceiveHz']=(driver['accepted']-old['accepted'])/duration
  result['outOfOrderRejected']=driver['reordered']-old['reordered']
  result['skippedSnapshotSequences']=driver['skipped']-old['skipped']
  result['walkingTeleports']=driver['teleports']-old['teleports']
  result['rootMotionYields']=driver['rootMotionYields']-old['rootMotionYields']
  result['interpolationDelayMs']=driver['delay']*1000
  result['errors']=sorted(set(x['remoteDriver'].get('gaitError','') for x in a))
 for phase in phases:
  p=[x for x in a if x['phase']==phase and who in x];t=np.array([x['time'] for x in p])
  if len(p)<3:continue
  pos=np.array([[x[who]['x'],x[who]['y']] for x in p]);v=np.array([[x[who]['vx'],x[who]['vy']] for x in p]);speed=np.linalg.norm(v,axis=1);steps=np.linalg.norm(np.diff(pos,axis=0),axis=1)
  yaw=np.array([x[who]['yaw'] for x in p]);yawdiff=(np.diff(yaw)+180)%360-180
  delta=np.diff(t);valid=(delta>0)&(delta<.12);moving=(speed[:-1]>25)&(speed[1:]>25)&valid
  acceleration=np.linalg.norm(np.diff(v,axis=0),axis=1)/np.maximum(delta,.001)
  plants=[];ratio=[]
  for old,new in zip(p,p[1:]):
   d=new['time']-old['time']
   if not 0<d<.12 or new[who]['speed']<25:continue
   if not all(k in old[who]['feet'] and k in new[who]['feet'] for k in ['foot_l','foot_r']):continue
   speeds=[np.hypot(new[who]['feet'][k]['x']-old[who]['feet'][k]['x'],new[who]['feet'][k]['y']-old[who]['feet'][k]['y'])/d for k in ['foot_l','foot_r']]
   plants.append(min(speeds)<20);ratio.append(min(speeds)/new[who]['speed'])
  gap=np.array([np.hypot(x['target']['X']-x['ghost']['x'],x['target']['Y']-x['ghost']['y']) for x in p])
  tail=t-t[0]>=.6
  d={'travelCm':float(np.linalg.norm(pos[-1]-pos[0])),'speedMedianMoving':float(np.median(speed[speed>25])) if (speed>25).any() else 0,'movingAccelerationP95':float(np.percentile(acceleration[moving],95)) if moving.any() else 0,'maxPositionStepCm':float(steps[valid].max()) if valid.any() else 0,'maxUnexpectedPositionStepCm':float(np.maximum(0,steps-np.linalg.norm(v[:-1],axis=1)*delta)[valid].max()) if valid.any() else 0,'maxYawStepDeg':float(abs(yawdiff[valid]).max()) if valid.any() else 0,'footPlantFraction':float(np.mean(plants)) if plants else None,'lowerFootSpeedRatioMedian':float(np.median(ratio)) if ratio else None,'rawTargetGapMedianP95Cm':np.percentile(gap,[50,95]).tolist(),'stopTailTravelCm':float(np.linalg.norm(pos[-1]-pos[np.where(tail)[0][0]])) if tail.any() else None,'stopTailMaxSpeed':float(speed[tail].max()) if tail.any() else None}
  if p[0].get('remoteDriver',{}).get('render',{}):
   rg=np.array([np.hypot(x['remoteDriver']['render']['X']-x['ghost']['x'],x['remoteDriver']['render']['Y']-x['ghost']['y']) for x in p])
   d['bufferedTargetGapMedianP95Cm']=np.percentile(rg,[50,95]).tolist()
  result['phases'][phase]=d
 return result
out={'run':str(run),'video':m['outputPath'],'baselineVideo':'D:/pb0online/runs/videos/PB0-PresentationSync-20261103-152007.mp4','before':{role:metrics(baseline,role) for role in ['host','guest']},'after':{role:metrics(run,role) for role in ['host','guest']},'networkLimit':'Sequence gaps include latest-file coalescing and native-relay polling; they are not proven UDP packet loss.','obs':{'renderDropped':m['after']['renderSkippedFrames']-m['before']['renderSkippedFrames'],'encoderDropped':m['after']['outputSkippedFrames']-m['before']['outputSkippedFrames']}}
fg=list(csv.DictReader((run/'window-foreground.csv').open()))
fg=[x for x in fg if m['startedUnixMs']<=int(x['unixMs'])<=m['startedUnixMs']+m['seconds']*1000]
out['foreground']={'samples':len(fg),'hostForegroundSamples':sum(int(x['hostForeground']) for x in fg),'guestForegroundSamples':sum(int(x['guestForeground']) for x in fg)}
cap=cv2.VideoCapture(m['outputPath']);fps=cap.get(cv2.CAP_PROP_FPS);count=cap.get(cv2.CAP_PROP_FRAME_COUNT)
out['recording']={'fps':fps,'seconds':count/fps,'width':cap.get(cv2.CAP_PROP_FRAME_WIDTH),'height':cap.get(cv2.CAP_PROP_FRAME_HEIGHT)}
shots=[]
for sec in [1,2,3.8,5.2,6,8.8,9.5,11.5,14,17]:
 cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,frame=cap.read();assert ok,'cannot decode frame'
 assert all(p.std()>8 for p in [frame[270:810,:960],frame[270:810,960:]]),'black viewport'
 cv2.imwrite(str(b/('smooth-'+str(sec)+'.jpg')),frame,[cv2.IMWRITE_JPEG_QUALITY,95])
 thumb=cv2.resize(frame,(960,540));cv2.putText(thumb,str(sec)+'s',(15,35),cv2.FONT_HERSHEY_SIMPLEX,1,(0,255,255),2);shots.append(thumb)
cap.release()
cv2.imwrite(str(b/'smooth-motion-contact-sheet.jpg'),np.vstack([np.hstack(shots[i:i+2]) for i in range(0,len(shots),2)]),[cv2.IMWRITE_JPEG_QUALITY,93])
out['decodedBothRealViewports']=True
(b/'smooth-motion-validation.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in out.items() if k not in ['before','after']},indent=2))
for role in ['host','guest']:
 print(role,json.dumps(out['after'][role],indent=2))
