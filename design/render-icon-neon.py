"""Render a luminous acoustic core, supersampled for a clean iOS icon."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parent.parent
S=2; N=1024*S
y,x=np.mgrid[0:N,0:N].astype(np.float32)/S
dx,dy=x-512,y-512
r=np.sqrt(dx*dx+dy*dy); theta=np.arctan2(dy,dx)
rgb=np.zeros((N,N,3),dtype=np.float32);rgb[:]=(5,8,23)
def light(cx,cy,sigma,color,strength=1):
 global rgb
 weight=np.exp(-((x-cx)**2+(y-cy)**2)/(2*sigma**2))*strength
 rgb+=weight[:,:,None]*np.array(color,dtype=np.float32)
light(260,240,350,(5,29,44),.7)
light(770,790,340,(27,7,58),.7)
inside=np.clip((295-r)/2,0,1);z=np.sqrt(np.clip(1-(r/297)**2,0,1))
surface=np.zeros_like(rgb);surface[:]=(6,13,33)
surface+=z[:,:,None]*np.array((7,13,28))
surface+=np.exp(-((dx+130)**2+(dy+150)**2)/(2*150**2))[:,:,None]*np.array((4,28,35))
rgb=rgb*(1-inside[:,:,None])+surface*inside[:,:,None]
t=(np.cos(theta-.65)+1)/2
ring_color=(1-t[:,:,None])*np.array((41,235,253))+t[:,:,None]*np.array((150,91,255))
rim=np.exp(-((r-300)/4.2)**2)
glow=np.exp(-((r-300)/24)**2)*.25
halo=np.exp(-((r-300)/64)**2)*.09
rgb+=(rim+glow+halo)[:,:,None]*ring_color
rgb+=np.exp(-((r-282)/1.3)**2)[:,:,None]*ring_color*.18
light(322,302,24,(95,214,245),.8)
image=Image.fromarray(np.uint8(np.clip(rgb,0,255)))
def blank(): return Image.new('L',(N,N))
def stroke(mask,points,width,fill=255):
 ImageDraw.Draw(mask).line([(int(a*S),int(b*S)) for a,b in points],fill=fill,width=int(width*S),joint='curve')
def orbit(a,b):
 pts=[]
 for t in np.linspace(a,b,700):
  xx,yy=380*np.cos(t),123*np.sin(t);angle=-.49
  pts.append((512+xx*np.cos(angle)-yy*np.sin(angle),512+xx*np.sin(angle)+yy*np.cos(angle)))
 return pts
orb=blank();stroke(orb,orbit(0,np.pi),3)
orb_glow=orb.filter(ImageFilter.GaussianBlur(9*S)).point(lambda v:min(255,v*3))
image.paste((64,109,242),(0,0,N,N),orb_glow)
image.paste((114,162,242),(0,0,N,N),orb.point(lambda v:int(v*.6)))
bars=blank();d=ImageDraw.Draw(bars)
for xx,hh in [(330,94),(408,196),(486,302),(564,196),(642,94)]:
 d.rounded_rectangle((xx*S,(512-hh/2)*S,(xx+52)*S,(512+hh/2)*S),radius=26*S,fill=255)
glow=bars.filter(ImageFilter.GaussianBlur(22*S)).point(lambda v:int(v*.60))
image.paste((32,179,232),(0,0,N,N),glow)
blend=np.clip((x+y-650)/740,0,1)
colors=(1-blend[:,:,None])*np.array((204,255,255))+blend[:,:,None]*np.array((110,146,255))
image.paste(Image.fromarray(np.uint8(colors)),(0,0),bars)
edges=ImageDraw.Draw(image)
for xx,hh in [(330,94),(408,196),(486,302),(564,196),(642,94)]:
 edges.rounded_rectangle((xx*S,(512-hh/2)*S,(xx+52)*S,(512+hh/2)*S),radius=26*S,outline=(195,249,255),width=S)
for cx,cy in [(305,294),(722,726)]:
 dot=blank();dd=ImageDraw.Draw(dot)
 dd.ellipse(((cx-4)*S,(cy-4)*S,(cx+4)*S,(cy+4)*S),fill=255)
 image.paste((74,219,255),(0,0,N,N),dot.filter(ImageFilter.GaussianBlur(7*S)).point(lambda v:min(255,v*6)))
 image.paste((225,255,255),(0,0,N,N),dot)
image=image.resize((1024,1024),Image.Resampling.LANCZOS).convert('RGB')
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
sheet=Image.new('RGB',(1080,720),(17,20,32))
for xx,yy,size in [(40,40,640),(775,70,180),(800,330,120),(830,560,60)]:
 icon=image.resize((size,size),Image.Resampling.LANCZOS)
 clip=Image.new('L',(size*3,size*3));d=ImageDraw.Draw(clip)
 d.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
 sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
sheet.save(ROOT/'preview/app-icon.png')
