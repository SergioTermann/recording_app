"""Glimpse: Art Deco fountain nib, midnight-blue enamel, chased antique gold."""
from pathlib import Path
import numpy as np
from scipy.ndimage import distance_transform_edt,gaussian_filter
from PIL import Image,ImageDraw,ImageFont,ImageFilter
ROOT=Path(__file__).resolve().parent.parent
S=2;N=1024*S
rng=np.random.default_rng(276)
y,x=np.mgrid[0:N,0:N].astype(np.float32)/S
u,v=x-512,y-512;r=np.hypot(u,v);ang=np.arctan2(v,u)
noise=rng.normal(0,1,(N,N)).astype(np.float32)
soft=np.exp(-((x-230)**2+(y-170)**2)/(2*660**2))
rgb=np.stack([9+9*soft,19+17*soft,29+24*soft],axis=-1)+noise[:,:,None]*.35
# Engine turning, visible only as fine undulations in the blue enamel.
turn=np.sin(r*.84+10*np.sin(ang*32+r*.09))
turn*=np.exp(-((r-250)/220)**4)*.9
rgb+=turn[:,:,None]*np.array([.35,.65,1])
orn=Image.new('L',(N,N));d=ImageDraw.Draw(orn)
def line(pts,w=1,fill=255):d.line([(int(a*S),int(b*S))for a,b in pts],fill=fill,width=max(1,round(w*S)),joint='curve')
def ellipse(box,w=1,fill=255):d.ellipse(tuple(round(a*S)for a in box),outline=fill,width=max(1,round(w*S)))
# Recessed architectural perimeter with stepped fan ornaments.
for inset,w in [(75,1.2),(84,1.8),(95,.8)]:d.rounded_rectangle((inset*S,inset*S,(1024-inset)*S,(1024-inset)*S),radius=(190-inset*.4)*S,outline=180,width=round(w*S))
for sx in (-1,1):
 for sy in (-1,1):
    def coords(pts):return[(512+sx*a,512+sy*b)for a,b in pts]
    for i in range(9):
        off=i*9
        line(coords([(238+off,400),(238+off,352-off*.20),(354-off*.20,238+off),(400,238+off)]),1.1,185)
    line(coords([(260,404),(260,353),(353,260),(404,260)]),2.3,225)
    for a in range(7):
        xx,yy=coords([(393-a*6,393-a*6)])[0]
        ellipse((xx-1.3,yy-1.3,xx+1.3,yy+1.3),1.1,230)
# Four slim diamonds frame the central writing instrument.
for a in [0,np.pi/2,np.pi,3*np.pi/2]:
    center=np.array([512+np.cos(a)*338,512+np.sin(a)*338])
    along=np.array([np.cos(a),np.sin(a)]);across=np.array([-np.sin(a),np.cos(a)])
    pts=[center+along*18,center+across*7,center-along*18,center-across*7,center+along*18]
    line(pts,1.9,225)
# Central medallion: interrupted radiating rays and interlaced concentric tooling.
for rad,w in [(288,1.4),(297,1),(308,1.4)]:ellipse((512-rad,512-rad,512+rad,512+rad),w,230)
for a in np.linspace(0,2*np.pi,128,endpoint=False):
    rr=265 if int(a/(2*np.pi)*128)%4==0 else 279
    line([(512+rr*np.cos(a),512+rr*np.sin(a)),(512+289*np.cos(a),512+289*np.sin(a))],.8,150)
for phase in [0,np.pi]:
    pts=[]
    for a in np.linspace(0,2*np.pi,3000):
        rr=302+3.4*np.sin(a*100+phase)
        pts.append((512+rr*np.cos(a),512+rr*np.sin(a)))
    line(pts,.7,190)
def metal(base,mask,height,tone=(171,143,94),shadow=2):
    coverage=np.asarray(mask,dtype=np.float32)/255
    shade=Image.new('L',(N,N));shade.paste(mask,(shadow*S,(shadow+2)*S))
    sh=np.asarray(shade.filter(ImageFilter.GaussianBlur(shadow*S)),dtype=np.float32)/255
    base*=1-sh[:,:,None]*.65
    gy,gx=np.gradient(gaussian_filter(height,.55),1/S,1/S)
    norm=np.sqrt(gx*gx+gy*gy+1);nx,ny,nz=-gx/norm,-gy/norm,1/norm
    light=np.clip(-.5*nx-.6*ny+.62*nz,0,1)
    panel=np.exp(-((nx*.8+ny*.2+.20)/.19)**2)
    dark=np.exp(-((nx*.4-ny*.5-.28)/.18)**2)
    gain=.45+.60*light+.25*panel-.23*dark
    face=gain[:,:,None]*np.array(tone)
    H=np.array([-.5,-.6,1.62]);H/=np.linalg.norm(H)
    spec=np.clip(nx*H[0]+ny*H[1]+nz*H[2],0,1)**24
    face+=spec[:,:,None]*np.array([80,77,66])+noise[:,:,None]*.65
    return base*(1-coverage[:,:,None])+face*coverage[:,:,None]
om=np.asarray(orn,dtype=np.float32)/255
rgb=metal(rgb,orn,gaussian_filter(om,1.1*S)*2.8)
# A broad sculpted fountain-pen nib pointing upwards. Its shoulders are curving,
# the slit and engraved ribs are physically recessed in the height field.
nib=Image.new('L',(N,N));nd=ImageDraw.Draw(nib)
def bezier(p):
    p=np.array(p,float)
    return[(1-t)**3*p[0]+3*(1-t)**2*t*p[1]+3*(1-t)*t*t*p[2]+t**3*p[3]for t in np.linspace(0,1,100)]
outline=[]
outline+=bezier([(512,282),(544,364),(628,425),(654,502)])
outline+=bezier([(654,502),(671,556),(592,586),(589,651)])
outline+=bezier([(589,651),(546,668),(478,668),(435,651)])
outline+=bezier([(435,651),(432,586),(353,556),(370,502)])
outline+=bezier([(370,502),(396,425),(480,364),(512,282)])
nd.polygon([(int(a*S),int(b*S))for a,b in outline],fill=255)
# Slit and breather hole are open apertures in the metal.
nd.line((512*S,280*S,512*S,472*S),fill=0,width=3*S)
nd.ellipse((500*S,460*S,524*S,484*S),fill=0)
coverage=np.asarray(nib,dtype=np.float32)/255
distance=distance_transform_edt(coverage>.5)/S
height=7*np.sin(np.minimum(distance/6,1)*np.pi/2)
height+=np.maximum(0,1-abs(u)/160)*6*coverage
# Etched double chevrons, scroll lines and fine radiating comb details.
engr=Image.new('L',(N,N));ed=ImageDraw.Draw(engr)
def el(pts,w=1.2):ed.line([(int(a*S),int(b*S))for a,b in pts],fill=255,width=round(w*S))
for side in(-1,1):
    for k in(0,9):
        pts=bezier([(512+side*20,383+k),(512+side*44,438+k),(512+side*130,490+k),(512+side*83,564+k)])
        el(pts,1.5)
    for k in range(11):
        yy=492+k*5.8
        el([(512+side*26,yy),(512+side*(45+k*3.1),yy+23)],.8)
for yy in(614,620,636):el([(447,yy),(577,yy)],1.2)
# Small diamond around the breather emphasizes bespoke engraving.
el([(512,492),(535,518),(512,544),(489,518),(512,492)],1.3)
cut=np.asarray(engr,dtype=np.float32)/255*coverage
height-=gaussian_filter(cut,.6)*1.6
rgb=metal(rgb,nib,height,(198,170,116),shadow=6)
rgb-=cut[:,:,None]*np.array([28,24,17])
# Sapphire enamel ferrule, bordered by polished metal underneath the nib.
ferrule=Image.new('L',(N,N));fd=ImageDraw.Draw(ferrule)
fd.rounded_rectangle((435*S,671*S,589*S,706*S),radius=6*S,fill=255)
f=np.asarray(ferrule,dtype=np.float32)/255
rgb=metal(rgb,ferrule,gaussian_filter(f,2*S)*5,shadow=3)
fd.rectangle((447*S,680*S,577*S,697*S),fill=0)
inner=((x>447)&(x<577)&(y>680)&(y<697)).astype(float)
blue=np.stack([np.ones_like(x)*15,29+soft*8,43+soft*12],axis=-1)
rgb=rgb*(1-inner[:,:,None])+blue*inner[:,:,None]
image=Image.fromarray(np.uint8(np.clip(rgb,0,255))).resize((1024,1024),Image.Resampling.LANCZOS).convert('RGB')
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
image.save(ROOT/'design/AppIcon-glimpse-deco.png')
sheet=Image.new('RGB',(1220,850),(233,228,219))
for xx,yy,size in[(45,45,740),(895,80,180),(925,355,120),(955,580,60)]:
    icon=image.resize((size,size),Image.Resampling.LANCZOS)
    clip=Image.new('L',(size*3,size*3));d=ImageDraw.Draw(clip)
    d.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
    sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
    if size<740:
        font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Baskerville.ttc',22)
        ImageDraw.Draw(sheet).text((xx+size/2,yy+size+18),'Glimpse',font=font,fill=(39,49,58),anchor='mt')
sheet.save(ROOT/'preview/app-icon.png')
print('Art Deco enamel-and-gold writing icon rendered: 1024x1024 RGB.')
