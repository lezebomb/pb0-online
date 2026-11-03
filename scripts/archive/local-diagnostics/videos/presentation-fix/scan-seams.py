import cv2,numpy as np,json,pathlib,sys
def seam_candidates(frame,pane=0):
 g=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY).astype(np.float32)
 # Output can be a 960x540 input image or the 1920x1080 composed recording.
 if g.shape[1]>=1800:g=g[270:810,pane*960:(pane+1)*960]
 if g.shape!=(540,960):g=cv2.resize(g,(960,540))
 x=g[:,660:925]
 grad=cv2.Sobel(x,cv2.CV_32F,1,0,ksize=3)
 upper=(grad[:-3]+grad[1:-2])*.5;lower=(grad[2:-1]+grad[3:])*.5
 upper=upper[:,12:-12];lower=lower[:,12:-12]
 shifts=np.arange(-10,11);corr=[]
 for shift in shifts:
  b=np.roll(lower,shift,axis=1)
  a=upper-upper.mean(axis=1,keepdims=True);b=b-b.mean(axis=1,keepdims=True)
  corr.append((a*b).sum(axis=1)/(np.linalg.norm(a,axis=1)*np.linalg.norm(b,axis=1)+1e-9))
 corr=np.array(corr);best=corr.argmax(axis=0);dx=shifts[best]
 score=(corr.max(axis=0)-corr[10])*np.minimum(1,np.abs(dx)/3)
 score[:12]=0;score[-12:]=0;score[abs(dx)<2]=0
 ix=np.argsort(score)[-6:][::-1]
 return [{'row':int(i+2+270),'score':round(float(score[i]),3),'shift':int(dx[i])} for i in ix]
if __name__=='__main__':
 for p in sys.argv[1:]:
  f=cv2.imread(p);print(json.dumps({'file':p,'candidates':seam_candidates(f)},ensure_ascii=False))
