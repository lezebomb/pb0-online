import cv2,numpy as np,json,pathlib,sys
def score(p):
 g=cv2.cvtColor(p,cv2.COLOR_BGR2GRAY).astype(np.float32)
 if g.shape!=(540,960):g=cv2.resize(g,(960,540))
 # Ignore only the game's bottom HUD. Real full-width seams still cross the remaining background.
 mask=np.ones(g.shape,dtype=np.float32)
 mask[420:,:300]=0;mask[420:,850:]=0
 # Static compass at the very top, separately checked from full-width environment seams.
 mask[20:45,230:730]=0
 valid=mask[:-1]*mask[1:]
 d=(abs(np.diff(g,axis=0))*valid).sum(axis=1)/np.maximum(1,valid.sum(axis=1))
 med=np.median(np.lib.stride_tricks.sliding_window_view(np.pad(d,12,mode='reflect'),25),axis=1)
 ratio=d/(med+.1)
 ratio[:20]=0;ratio[470:]=0
 # A true seam is an isolated single row, not a normal band of horizontal scenery.
 near=np.maximum(np.roll(d,1),np.roll(d,-1))
 ratio[near>d*.75]=0
 k=int(ratio.argmax())
 return {'score':float(ratio[k]),'row':k+1+270,'difference':float(d[k])}
def analyze(video,output,single=False):
 cap=cv2.VideoCapture(str(video));fps=cap.get(cv2.CAP_PROP_FPS);n=0;hits=[[],[]];best=[(0,None,None),(0,None,None)]
 while True:
  ok,f=cap.read()
  if not ok:break
  for role in [0] if single else [0,1]:
   q=score(f[270:810,role*960:(role+1)*960])
   if q['score']>2.6:hits[role].append({'frame':n,'seconds':n/fps,**q})
   if q['score']>best[role][0]:best[role]=(q['score'],n,f.copy())
  n+=1
 cap.release()
 out=pathlib.Path(output);out.parent.mkdir(exist_ok=True,parents=True)
 data={'video':str(video),'frames':n,'fps':fps,'suspectedSeamFrames':{'host':len(hits[0]),'guest':len(hits[1])},'allCandidates':{'host':hits[0],'guest':hits[1]},'examples':{'host':sorted(hits[0],key=lambda x:x['score'],reverse=True)[:8],'guest':sorted(hits[1],key=lambda x:x['score'],reverse=True)[:8]}}
 for i,role in enumerate(['host','guest']):
  if best[i][2] is not None:cv2.imwrite(str(out.with_name(out.stem+'-'+role+'-worst.png')),best[i][2])
 data['maxScore']={'host':best[0][0],'guest':best[1][0]}
 out.write_text(json.dumps(data,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in data.items() if k not in ['examples','allCandidates']}))
 return data
if __name__=='__main__':analyze(sys.argv[1],sys.argv[2],len(sys.argv)>3 and sys.argv[3]=='single')
