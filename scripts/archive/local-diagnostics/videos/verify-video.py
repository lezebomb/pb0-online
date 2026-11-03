import cv2,json,os,numpy as np
base=r'D:\pb0online\runs\videos'
meta=json.load(open(os.path.join(base,'recording-output.json'),encoding='utf-8-sig'))
file=meta['outputPath']; cap=cv2.VideoCapture(file)
if not cap.isOpened(): raise RuntimeError('MP4 cannot be decoded')
fps=cap.get(cv2.CAP_PROP_FPS); count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT)); duration=count/fps
samples=[]; images=[]
for sec in [0.5,5,12,20,28,42,48,58]:
 cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,frame=cap.read()
 if not ok: samples.append({'second':sec,'decoded':False});continue
 gray=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
 samples.append({'second':sec,'decoded':True,'mean':float(gray.mean()),'std':float(gray.std()),'nonblackFraction':float((gray>12).mean())})
 small=cv2.resize(frame,(480,270));images.append(small)
 cv2.imwrite(os.path.join(base,'video-frame-%02d.png'%int(sec)),frame)
cap.release()
differences=[float(cv2.absdiff(images[i-1],images[i]).mean()) for i in range(1,len(images))]
valid=len(images)==8 and 56<=duration<=72 and all(s.get('nonblackFraction',0)>0.15 and s.get('std',0)>8 for s in samples) and max(differences,default=0)>2
if len(images)==8:
 sheet=np.vstack([np.hstack(images[:4]),np.hstack(images[4:])]);cv2.imwrite(os.path.join(base,'video-contact-sheet.jpg'),sheet)
result={'videoPath':os.path.abspath(file),'durationSeconds':duration,'fps':fps,'frameCount':count,'bytes':os.path.getsize(file),'samples':samples,'frameDifferences':differences,'decodedChecksPassed':valid,'humanSceneReview':'pending','composition':'single actual game viewport with both real player roles'}
json.dump(result,open(os.path.join(base,'video-validation.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=2)
print(json.dumps(result,ensure_ascii=False))
if not valid: raise RuntimeError('Video failed real-frame/duration/motion checks')