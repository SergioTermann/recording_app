"""Glimpse: ivory ground, engine-turned claret enamel and an antique gilt locket."""
from pathlib import Path
import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
ROOT=Path(__file__).resolve().parent.parent
S=2;N=1024*S
rng=np.random.default_rng(1019)
y,x=np.mgrid[0:N,0:N].astype(np.float32)/S
u,v=x-512,y-502
noise=rng.normal(0,1,(N,N)).astype(np.float32)
# Warm ivory, faint woven surface and naturally falling light.
light=np.exp(-((x-175)**2+(y-105)**2)/(2*840**2))
shade=11*light-6*((x+y)/2048)
grain=noise*.45+np.sin(x*np.pi*.73)*.18+np.sin(y*np.pi*.85)*.18
rgb=np.stack([35+shade*1.9+grain,10+shade*.5+grain*.4,22+shade*.8+grain*.6],axis=-1)
# Antique scrollwork is a sculpted metal overlay rather than a printed border.
ornament=Image.new('L',(N,N)); od=ImageDraw.Draw(ornament)
def curve(points,width=2,fill=255):
    p=np.array(points,float);ts=np.linspace(0,1,100)
    result=[(1-t)**3*p[0]+3*(1-t)**2*t*p[1]+3*(1-t)*t*t*p[2]+t**3*p[3] for t in ts]
    od.line([(round(q[0]*S),round(q[1]*S)) for q in result],fill=fill,width=round(width*S))
def leaf(start,end,bend,width):
    a=np.array(start,float);b=np.array(end,float);v=b-a;n=np.array([-v[1],v[0]]);n/=np.linalg.norm(n)
    mid=(a+b)/2+n*bend
    ts=np.linspace(0,1,45)
    pts=[(1-t)**2*a+2*(1-t)*t*(mid+n*width)+t*t*b for t in ts]
    pts += [(1-t)**2*b+2*(1-t)*t*(mid-n*width*.2)+t*t*a for t in ts]
    od.polygon([(int(q[0]*S),int(q[1]*S)) for q in pts],fill=235)
    curve([a,mid,mid,b],.9,80)
# Mirrored acanthus corners with tendrils, leaf fans and engraved veins.
for sx in (-1,1):
 for sy in (-1,1):
    def t(points):return [(512+sx*a,512+sy*b) for a,b in points]
    for pts,w in [([(53,399),(168,458),(392,393),(390,222)],3.2),
                  ([(116,406),(234,437),(337,326),(296,278)],4.5),
                  ([(296,278),(264,239),(217,289),(257,313)],3.6),
                  ([(257,313),(286,324),(294,292),(274,288)],2.3),
                  ([(293,343),(395,316),(423,223),(382,202)],3.1),
                  ([(382,202),(350,190),(328,229),(356,244)],2.8),
                  ([(356,244),(375,252),(384,229),(368,226)],2.0),
                  ([(60,427),(173,482),(405,428),(424,219)],1.2)]:curve(t(pts),w)
    for a,b,bend,w in [((147,416),(151,370),8,10),((183,411),(198,360),10,13),((223,391),(250,343),9,13),((275,365),(317,342),8,11),((360,315),(405,300),9,13),((383,270),(426,246),9,12),((342,370),(374,404),-8,11),((299,402),(315,444),-9,13),((250,422),(248,459),-8,9)]:
        aa,bb=t([a,b]);leaf(aa,bb,bend*sx*sy,w)
    for a,b in [(83,419),(104,427),(126,434),(420,190),(424,173)]:
        xx,yy=t([(a,b)])[0];od.ellipse(((xx-2)*S,(yy-2)*S,(xx+2)*S,(yy+2)*S),fill=245)
# Fine double beaded perimeter beneath the full corner compositions.
for inset,w in [(62,1.0),(71,1.0)]:od.rounded_rectangle((inset*S,inset*S,(1024-inset)*S,(1024-inset)*S),radius=170*S,outline=125,width=round(w*S))
om=np.asarray(ornament,dtype=np.float32)/255
oshadow=Image.new('L',(N,N));oshadow.paste(ornament,(3*S,4*S))
rgb*=1-(np.asarray(oshadow.filter(ImageFilter.GaussianBlur(2*S)),dtype=np.float32)/255)[:,:,None]*.58
og=gaussian_filter(om,1.3)*3;oy,ox=np.gradient(og,1/S,1/S)
ong=np.sqrt(ox*ox+oy*oy+1);ol=np.clip((.5*ox+.62*oy+.65)/ong,0,1)
ogold=np.stack([(131+65*ol),(102+57*ol),(58+40*ol)],axis=-1)+noise[:,:,None]*.8
rgb=rgb*(1-om[:,:,None])+ogold*om[:,:,None]
# Tall pocket-jewel proportions. All decoration is inside the iOS safe area.
rx,ry=250,324
rho=np.sqrt((u/rx)**2+(v/ry)**2)
a=np.arctan2(v/ry,u/rx)
dist=(1-rho)*300
silhouette=np.clip(dist*S+.5,0,1)
maskimage=Image.fromarray(np.uint8(silhouette*255))
shadow=Image.new('L',(N,N));shadow.paste(maskimage,(7*S,15*S))
sh=np.asarray(shadow.filter(ImageFilter.GaussianBlur(13*S)),dtype=np.float32)/255
rgb*=1-sh[:,:,None]*.37
# Engine-turned claret enamel under a smooth glass surface.
enamel=.88-rho
inside=np.clip(enamel*300*S,0,1)
dome=np.sqrt(np.maximum(1-(rho/.91)**2,0))
lighting=np.exp(-((u+90)**2/(2*220**2)+(v+140)**2/(2*240**2)))
turn=np.cos(rho*490+9*np.sin(a*22+rho*31))
turn2=np.cos(rho*490-9*np.sin(a*22-rho*27))
etched=(turn+turn2)*2.2*(.3+.7*dome)
red=np.stack([48+41*lighting+etched,10+11*lighting+etched*.35,22+18*lighting+etched*.5],axis=-1)
# Soft rectangular window reflection on convex glass.
reflect=np.exp(-((u+144)/67)**6-((v+175)/180)**6)*.10
red+=reflect[:,:,None]*np.array([75,59,54])
rgb=rgb*(1-silhouette[:,:,None])+red*silhouette[:,:,None]
# Rounded outer gold rail, rope edge, recessed grooves and milgrain.
metal_mask=np.clip((rho-.873)*300*S,0,1)*silhouette
h=np.zeros((N,N),np.float32)
for center,width,height in [(.992,.014,5),(.968,.010,3.8),(.915,.008,3.2),(.884,.011,5)]:
    h+=np.sqrt(np.maximum(1-((rho-center)/width)**2,0))*height
# Very fine twisted-wire texture in the middle channel.
h+=np.exp(-((rho-.941)/.014)**4)*(2+.9*np.cos(a*148+(rho-.94)*100))
# Little round granules in the outer channel.
h+=np.exp(-((rho-.975)/.008)**2)*np.maximum(np.cos(a*116),0)**4*1.4
# Metal render with a subdued champagne tone, bright rounded edges and patina.
def gilt(rgb,mask,height,base=(174,145,99),depth=1):
    gy,gx=np.gradient(gaussian_filter(height,.6),1/S,1/S)
    norm=np.sqrt(1+gx*gx+gy*gy);nx,ny,nz=-gx/norm,-gy/norm,1/norm
    diffuse=np.clip(-.48*nx-.58*ny+.66*nz,0,1)
    reflection=np.exp(-((nx*.65+ny*.35+.22)/.20)**2)
    dark=np.exp(-((nx*.4-ny*.5-.35)/.17)**2)
    gain=.43+.63*diffuse+.26*reflection-.18*dark
    metal=gain[:,:,None]*np.array(base)
    H=np.array([-.48,-.58,1.66]);H/=np.linalg.norm(H)
    spec=np.clip(nx*H[0]+ny*H[1]+nz*H[2],0,1)**25
    metal+=spec[:,:,None]*np.array([72,69,61])
    metal+=noise[:,:,None]*.8
    return rgb*(1-mask[:,:,None])+metal*mask[:,:,None]
rgb=gilt(rgb,metal_mask,h)
# Closely set seed pearls, warm ivory and individual directional highlights.
for i in range(108):
    angle=i*2*np.pi/108
    bx=rx*.912*np.cos(angle);by=ry*.912*np.sin(angle)
    br=np.hypot(u-bx,v-by)
    coverage=np.clip((2.7-br)*S,0,1)
    spot=np.exp(-((u-bx+.8)**2+(v-by+1)**2)/2.5)
    pearl=np.stack([156+75*spot,137+77*spot,101+87*spot],axis=-1)
    rgb=rgb*(1-coverage[:,:,None])+pearl*coverage[:,:,None]
# Ivory gold calligraphic G, hand-lettered character rather than a generic crest.
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/SnellRoundhand.ttc',int(385*S))
glyph=Image.new('L',(N,N));gd=ImageDraw.Draw(glyph)
box=gd.textbbox((0,0),'G',font=font)
gx=512*S-(box[2]+box[0])/2;gy=505*S-(box[3]+box[1])/2
gd.text((gx,gy),'G',font=font,fill=255)
coverage=np.asarray(glyph,dtype=np.float32)/255
distance=distance_transform_edt(coverage>.5)/S
height=3*np.sin(np.minimum(distance/3.4,1)*np.pi/2)
shadow=Image.new('L',(N,N));shadow.paste(glyph,(2*S,4*S))
sh=np.asarray(shadow.filter(ImageFilter.GaussianBlur(2*S)),dtype=np.float32)/255
rgb*=1-sh[:,:,None]*.46
rgb=gilt(rgb,coverage,height,(218,197,154))
# Small engraved fleurons, contained inside the oval instead of a second frame.
flourish=Image.new('L',(N,N));fd=ImageDraw.Draw(flourish)
for cy in (269,735):
    for side in (-1,1):
        t=np.linspace(0,1,100)
        xx=512+side*(7+45*t)
        yy=cy+6*np.sin(t*np.pi*2)*(1-t)
        fd.line([(int(xx[i]*S),int(yy[i]*S)) for i in range(len(t))],fill=255,width=2*S)
    fd.ellipse(((512-3)*S,(cy-3)*S,(512+3)*S,(cy+3)*S),fill=255)
f=np.asarray(flourish,dtype=np.float32)/255
rgb=gilt(rgb,f,np.asarray(flourish.filter(ImageFilter.GaussianBlur(S)),dtype=np.float32)/100)
image=Image.fromarray(np.uint8(np.clip(rgb,0,255))).resize((1024,1024),Image.Resampling.LANCZOS).convert('RGB')
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
image.save(ROOT/'design/AppIcon-glimpse-baroque.png')
sheet=Image.new('RGB',(1220,850),(233,226,215))
for xx,yy,size in [(45,45,740),(895,80,180),(925,355,120),(955,580,60)]:
    icon=image.resize((size,size),Image.Resampling.LANCZOS)
    clip=Image.new('L',(size*3,size*3)); d=ImageDraw.Draw(clip)
    d.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
    sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
    if size<740:
        font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Baskerville.ttc',22)
        ImageDraw.Draw(sheet).text((xx+size/2,yy+size+18),'Glimpse',font=font,fill=(68,46,44),anchor='mt')
sheet.save(ROOT/'preview/app-icon.png')
print('Rendered ivory / claret enamel locket, 1024 × 1024 RGB.')
