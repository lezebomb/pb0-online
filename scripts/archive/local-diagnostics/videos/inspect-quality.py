import cv2,csv,json,pathlib,numpy as np
base=pathlib.Path('D:/pb0online/runs/videos')
meta=json.loads((base/'quality-recording-output.json').read_text('utf-8-sig'))
run=pathlib.Path(meta['run'])
rows=list(csv.DictReader((run/'quality-frame-times.csv').open()))
r=[x for x in rows if x['capture']=='1']
f=np.array([int(x['frame']) for x in r]);t=np.array([float(x['realSeconds']) for x in r]);dt=np.array([float(x['worldDeltaMs']) for x in r])
gaps=np.diff(f)
performance={'method':'UE GFrameCounter delta / world real-time delta; per-frame world delta sampled only once per unique engine frame','engineFrames':int(f[-1]-f[0]),'seconds':float(t[-1]-t[0]),'averageGameFps':float((f[-1]-f[0])/(t[-1]-t[0])),'callbackCoverage':float((len(f)-1)/(f[-1]-f[0])),'observedFrames':len(f),'frameMs':{'median':float(np.median(dt)),'p95':float(np.percentile(dt,95)),'p99':float(np.percentile(dt,99)),'max':float(np.max(dt))},'framesOver33ms':int((dt>33.333).sum()),'phases':{}}
for phase in sorted(set(x['phase'] for x in r)):
 x=[y for y in r if y['phase']==phase]
 if len(x)>2:
  ts=[float(y['realSeconds']) for y in x];fc=[int(y['frame']) for y in x]
  performance['phases'][phase]={'fps':(fc[-1]-fc[0])/(ts[-1]-ts[0]),'p95FrameMs':float(np.percentile([float(y['worldDeltaMs']) for y in x],95))}
before,after=meta['before'],meta['after']
performance['obs']={'renderSkipped':after['renderSkippedFrames']-before['renderSkippedFrames'],'renderTotal':after['renderTotalFrames']-before['renderTotalFrames'],'encoderSkipped':after['outputSkippedFrames']-before['outputSkippedFrames'],'encoderTotal':after['outputTotalFrames']-before['outputTotalFrames'],'averageRenderMs':float(np.mean([x['averageFrameRenderTime'] for x in meta['stats']])),'activeFpsAverage':float(np.mean([x['activeFps'] for x in meta['stats']])), 'outputs':meta['outputStats']}
video=pathlib.Path(meta['outputPath'])
cap=cv2.VideoCapture(str(video))
fps=cap.get(cv2.CAP_PROP_FPS);width=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH));height=int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT));count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
info={'path':str(video),'fps':fps,'width':width,'height':height,'frames':count,'seconds':count/fps,'bytes':video.stat().st_size,'averageMbps':video.stat().st_size*8/(count/fps)/1e6}
samples={round(s*fps):s for s in [1,4,7,11,14,17.5,22.5,27.5]}
images=[];differences=[];translations=[];inliers=[];prev=None;decoded=0
mask=np.zeros((360,640),np.uint8);mask[15:190,20:620]=255;mask[190:310,20:155]=255;mask[190:310,500:620]=255
while True:
 ok,im=cap.read()
 if not ok: break
 idx=decoded;decoded+=1
 if idx in samples:
  s=samples[idx];file=base/('quality-frame-'+str(s).replace('.','-')+'.jpg');cv2.imwrite(str(file),im,[cv2.IMWRITE_JPEG_QUALITY,95])
  thumb=cv2.resize(im,(640,360));cv2.putText(thumb,f'{s:.1f}s',(15,30),cv2.FONT_HERSHEY_SIMPLEX,.8,(255,255,255),2);images.append(thumb)
 small=cv2.resize(cv2.cvtColor(im,cv2.COLOR_BGR2GRAY),(640,360))
 if prev is not None:
  differences.append(float(np.mean(cv2.absdiff(small,prev))))
  pts=cv2.goodFeaturesToTrack(prev,maxCorners=120,qualityLevel=.03,minDistance=12,mask=mask)
  if pts is not None and len(pts)>=12:
   dest,st,_=cv2.calcOpticalFlowPyrLK(prev,small,pts,None,winSize=(19,19),maxLevel=2)
   keep=st.reshape(-1)==1
   if keep.sum()>=10:
    mat,ins=cv2.estimateAffinePartial2D(pts[keep],dest[keep],method=cv2.RANSAC,ransacReprojThreshold=1.5)
    if mat is not None and ins is not None and ins.mean()>.5:
     translations.append(float(np.hypot(mat[0,2],mat[1,2])));inliers.append(float(ins.mean()))
 prev=small
cap.release()
assert decoded>fps*27 and images,'No actual decoded gameplay'
sheet=np.vstack([np.hstack(images[i:i+2]) for i in range(0,len(images),2)])
cv2.imwrite(str(base/'quality-contact-sheet.jpg'),sheet,[cv2.IMWRITE_JPEG_QUALITY,94])
info['decodedFrames']=decoded
info['motion']={'meanAdjacentFrameDifference':float(np.mean(differences)),'almostIdenticalFramePairsBelow0_05':int((np.array(differences)<.05).sum()),'pairCount':len(differences),'backgroundAffineTranslationAt640px':{'median':float(np.median(translations)),'p95':float(np.percentile(translations,95)),'max':float(np.max(translations)),'validPairs':len(translations)},'note':'Fixed recording camera; background feature fit excludes central character area. This does not establish normal follow-camera smoothness.'}
motion=list(csv.DictReader((run/'quality-motion.csv').open()))
mr=[x for x in motion if x['phase'].startswith('quality') or x['phase'] in ['block','parry']]
seq=np.array([int(x['targetSeq']) for x in mr]);times=np.array([float(x['realSeconds']) for x in mr])
positions=np.array([[float(x['ghostX']),float(x['ghostY'])] for x in mr]);targets=np.array([[float(x['targetX']),float(x['targetY'])] for x in mr])
steps=np.linalg.norm(np.diff(positions,axis=0),axis=1);error=np.linalg.norm(positions-targets,axis=1)
performance['ghostObservation']={'samples':len(mr),'ghostWalksValues':sorted(set(x['ghostWalks'] for x in mr)),'rootMotionValues':sorted(set(x['rootMotion'] for x in mr)),'targetSequencePerSecond':float((seq[-1]-seq[0])/(times[-1]-times[0])),'positionErrorCmMedian':float(np.median(error)),'positionErrorCmP95':float(np.percentile(error,95)),'largestSampleStepCm':float(max(steps)),'motionLog':str(run/'quality-motion.csv')}
out={'video':info,'performance':performance,'run':str(run),'checkedActualDecodedFrames':True,'manualReviewPending':True}
(base/'quality-validation.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))