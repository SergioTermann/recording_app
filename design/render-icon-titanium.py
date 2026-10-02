"""Deterministic height-field material rendering: graphite and brushed titanium."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parent.parent
S=2;N=1024*S
rng=np.random.default_rng(24)
y,x=np.mgrid[0:N,0:N].astype(np.float32)/S
cx,cy=x-512,y-502
r=np.sqrt(cx*cx+cy*cy)
noise=rng.normal(0,1,(N,N)).astype(np.float32)
# Softbox-lit graphite, with a restrained fine satin grain.
illum=np.exp(-((x-170)**2+(y-130)**2)/(2*720**2))
base=17+20*illum+noise*.65
rgb=np.stack([base*.96,base,base*1.05],axis=-1)
# Recessed circular bed. One top-left softbox produces a lit lower lip.
angle=np.arctan2(cy,cx)
inside=np.clip((332-r)*S,0,1)
disc=14+15*np.exp(-((x-340)**2+(y-280)**2)/(2*470**2))
disc+=noise*.5
# Almost imperceptible concentric machining marks.
disc+=.65*np.sin(r*3.8)
rgb=rgb*(1-inside[:,:,None])+np.stack([disc*.95,disc,disc*1.055],axis=-1)*inside[:,:,None]
# Black interior seam, broad directional bevel and contact shading.
seam=np.exp(-((r-334)/2.0)**2)
rgb*=1-seam[:,:,None]*.80
lip=np.exp(-((r-341)/3.8)**2)
light=np.clip((np.cos(angle-.8)+1)/2,0,1)
rgb+=lip[:,:,None]*(light*39-8)[:,:,None]
rgb*=1-(np.exp(-((r-322)/6)**2)*np.clip((-np.cos(angle-.8)+1)/2,0,1)*.34)[:,:,None]
# Capsule signed distances define the machined metal waveform.
distance=np.full((N,N),-1000,dtype=np.float32)
for center,h in [(316,100),(414,216),(512,344),(610,216),(708,100)]:
 radius=32
 delta_y=np.maximum(np.abs(y-502)-(h/2-radius),0)
 d=radius-np.sqrt((x-center)**2+delta_y**2)
 distance=np.maximum(distance,d)
coverage=np.clip(distance*S+.5,0,1)
# Ambient occlusion directly around each solid; cast shadow falls lower-right.
mask=Image.fromarray(np.uint8(coverage*255))
shadow=Image.new('L',(N,N));shadow.paste(mask,(9*S,15*S))
shadow=np.array(shadow.filter(ImageFilter.GaussianBlur(10*S)),dtype=np.float32)/255
rgb*=1-shadow[:,:,None]*.65
occlusion=np.exp(-np.maximum(-distance,0)/5)*(1-coverage)
rgb*=1-occlusion[:,:,None]*.62
# Smooth quarter-round bevel, with real surface normals from its height field.
b=np.clip(distance/8,0,1)
height=8*np.sin(b*np.pi/2)
gy,gx=np.gradient(height,1/S,1/S)
normal=np.stack([-gx,-gy,np.ones_like(gx)],axis=-1)
normal/=np.linalg.norm(normal,axis=-1)[:,:,None]
L=np.array([-.48,-.60,.64]);L=L/np.linalg.norm(L)
diffuse=np.clip(np.sum(normal*L,axis=-1),0,1)
# Brushed titanium face: long fine horizontal grain and a broad reflected panel.
rowgrain=rng.normal(0,1,(N,1)).astype(np.float32)
brush=rowgrain*1.65+noise*.45
face=142+46*np.exp(-((x+y*.36-440)/260)**2)-24*np.exp(-((x+y*.2-750)/110)**2)
metal=(face+brush)*(0.33+0.84*diffuse)
H=(L+np.array([0,0,1]));H/=np.linalg.norm(H)
spec=np.clip(np.sum(normal*H,axis=-1),0,1)**30
metal+=spec*95
metal=np.clip(metal,0,247)
metalrgb=np.stack([metal*1.015,metal*1.004,metal*.975],axis=-1)
rgb=rgb*(1-coverage[:,:,None])+metalrgb*coverage[:,:,None]
# A tiny inset red recording indicator, with a domed highlight, not a glow.
rr=np.sqrt((x-512)**2+(y-748)**2)
bezel=np.clip((14-rr)*S,0,1)
rgb=rgb*(1-bezel[:,:,None])+np.array([7,9,11])*bezel[:,:,None]
led=np.clip((8.5-rr)*S,0,1)
high=np.exp(-((x-509)**2+(y-745)**2)/12)
ledrgb=np.stack([145+80*high,32+55*high,24+42*high],axis=-1)
rgb=rgb*(1-led[:,:,None])+ledrgb*led[:,:,None]
image=Image.fromarray(np.uint8(np.clip(rgb,0,255))).resize((1024,1024),Image.Resampling.LANCZOS).convert('RGB')
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
sheet=Image.new('RGB',(1080,720),(228,227,224))
for xx,yy,size in [(40,40,640),(775,70,180),(800,330,120),(830,560,60)]:
 icon=image.resize((size,size),Image.Resampling.LANCZOS)
 clip=Image.new('L',(size*3,size*3));draw=ImageDraw.Draw(clip)
 draw.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
 sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
sheet.save(ROOT/'preview/app-icon.png')
