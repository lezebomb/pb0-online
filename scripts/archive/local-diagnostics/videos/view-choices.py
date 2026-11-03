import cv2,numpy as np
imgs=[]
for i in range(1,9):
 im=cv2.imread('runs/videos/framing-choice-'+str(i)+'.png')
 im=cv2.resize(im,(640,360))
 cv2.putText(im,str(i),(15,35),cv2.FONT_HERSHEY_SIMPLEX,1,(0,255,255),2)
 imgs.append(im)
cv2.imwrite('runs/videos/framing-choices.jpg',np.vstack([np.hstack(imgs[i:i+2]) for i in range(0,8,2)]))