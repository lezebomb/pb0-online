import pathlib,json,cv2,numpy as np
b=pathlib.Path('D:/pb0online/runs/videos')
m=json.loads((b/'locomotion-recording.json').read_text())
r=pathlib.Path(m['run'])
phases=['forward','stop-one','lateral','stop-two','turn','stop-three','attack','idle-final']
out={'run':str(r),'video':m['outputPath'],'roles':{},'obs':{'renderDropped':m['after']['renderSkippedFrames']-m['before']['renderSkippedFrames'],'encodeDropped':m['after']['outputSkippedFrames']-m['before']['outputSkippedFrames']},'validationComplete':False}
for role in ['guest','host']:
 rows=[];errors=[]
 for line in (r/(role+'-locomotion.jsonl')).read_text(encoding='utf-8').splitlines():
  try: row=json.loads(line)
  except json.JSONDecodeError: continue
  if row['type']=='sample':rows.append(row)
  elif row['type'] in ['observer_error','inventory_error']: errors.append(row)
 who='player' if role=='guest' else 'ghost'
 metrics={}
 for phase in phases:
  a=[x for x in rows if x['phase']==phase and who in x]
  if len(a)<2:continue
  times=np.array([x['time'] for x in a]);pos=np.array([[x[who]['x'],x[who]['y']] for x in a]);speed=np.array([x[who]['speed'] for x in a])
  delta=np.diff(times);steps=np.linalg.norm(np.diff(pos,axis=0),axis=1)
  yaw=np.array([x[who]['yaw'] for x in a]);yawStep=(np.diff(yaw)+180)%360-180
  active=speed>20
  footRatios=[];plant=[];feetTravel=[]
  for old,new in zip(a,a[1:]):
   dt=new['time']-old['time']
   if dt<=0 or dt>.1 or new[who]['speed']<25:continue
   fo,fn=old[who].get('feet',{}),new[who].get('feet',{})
   if not all(k in fo and k in fn for k in ['foot_l','foot_r']):continue
   fv=[np.hypot(fn[k]['x']-fo[k]['x'],fn[k]['y']-fo[k]['y'])/dt for k in ['foot_l','foot_r']]
   footRatios.append(min(fv)/new[who]['speed']);plant.append(min(fv)<20)
   for k in ['foot_l','foot_r']: feetTravel.append(np.hypot(fn[k]['x']-new[who]['x'],fn[k]['y']-new[who]['y']))
  tail=times-times[0]>=.6
  metrics[phase]={'samples':len(a),'duration':float(times[-1]-times[0]),'travelCm':float(np.linalg.norm(pos[-1]-pos[0])),'speedPeak':float(max(speed)),'activeSpeedMedian':float(np.median(speed[active])) if active.any() else 0,'tailSpeedMax':float(max(speed[tail])) if tail.any() else None,'tailTravelCm':float(np.linalg.norm(pos[-1]-pos[np.where(tail)[0][0]])) if tail.any() else None,'maxPositionStepCm':float(max(steps)),'maxPositionStepRate':float(max(steps/delta)),'yawFirst':float(yaw[0]),'yawLast':float(yaw[-1]),'maxYawStep':float(max(abs(yawStep))),'gaits':sorted(set(x[who].get('animation',{}).get('gait',-1) for x in a)),'nativeInputUsed':any(sum(abs(float(v)) for v in x[who].get('nativeMoveInput',{}).values())>.01 for x in a),'footPlantFraction':float(np.mean(plant)) if plant else None,'lowerFootSpeedRatioMedian':float(np.median(footRatios)) if footRatios else None}
 activeRows=[x for x in rows if x['phase'] in phases]
 driver=[x.get('remoteDriver',{}) for x in activeRows]
 out['roles'][role]={'subject':who,'nativeRemoteControlledAll':all(x.get('controlled') for x in driver),'driverErrors':sorted(set(x.get('error','') for x in driver)),'observerErrors':errors,'phases':metrics}
cap=cv2.VideoCapture(m['outputPath']);fps=cap.get(cv2.CAP_PROP_FPS);count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
out['recording']={'fps':fps,'frames':count,'seconds':count/fps,'width':int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),'height':int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))}
shots=[]
for sec in [1,2,4,5.5,7.2,9,10.5,12,14,17]:
 cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,frame=cap.read();assert ok,'cannot decode recorded frame'
 for pane in [frame[270:810,:960],frame[270:810,960:]]:
  assert pane.std()>8,'one game pane is black'
 cv2.imwrite(str(b/('loco-frame-'+str(sec).replace('.','-')+'.jpg')),frame,[cv2.IMWRITE_JPEG_QUALITY,94])
 thumb=cv2.resize(frame,(960,540));cv2.putText(thumb,str(sec)+'s',(15,35),cv2.FONT_HERSHEY_SIMPLEX,1,(0,255,255),2);shots.append(thumb)
cap.release()
cv2.imwrite(str(b/'locomotion-contact-sheet.jpg'),np.vstack([np.hstack(shots[n:n+2]) for n in range(0,len(shots),2)]),[cv2.IMWRITE_JPEG_QUALITY,93])
out['checkedRealDecodedBothPanes']=True
(b/'locomotion-validation.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False,indent=2))