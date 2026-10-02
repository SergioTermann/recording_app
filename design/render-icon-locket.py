"""Glimpse: ivory ground, engine-turned claret enamel and an antique gilt locket."""
from pathlib import Path
import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter
from PIL import Image, ImageDraw, ImageFont, ImageFilter
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
rgb=np.stack([226+shade+grain,220+shade+grain,207+shade+grain],axis=-1)
# Tall pocket-jewel proportions. All decoration is inside the iOS safe area.
rx,ry=276,347
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
etched=(turn+turn2)*.65*(.3+.7*dome)
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
# Ivory gold calligraphic G, hand-lettered character rather than a generic crest.
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/SnellRoundhand.ttc',int(510*S))
glyph=Image.new('L',(N,N));gd=ImageDraw.Draw(glyph)
box=gd.textbbox((0,0),'G',font=font)
gx=512*S-(box[2]+box[0])/2;gy=507*S-(box[3]+box[1])/2
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
for cy in (249,755):
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
image.save(ROOT/'design/AppIcon-glimpse-locket.png')
sheet=Image.new('RGB',(1220,850),(51,43,43))
for xx,yy,size in [(45,45,740),(895,80,180),(925,355,120),(955,580,60)]:
    icon=image.resize((size,size),Image.Resampling.LANCZOS)
    clip=Image.new('L',(size*3,size*3)); d=ImageDraw.Draw(clip)
    d.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
    sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
    if size<740:
        font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Baskerville.ttc',22)
        ImageDraw.Draw(sheet).text((xx+size/2,yy+size+18),'Glimpse',font=font,fill=(230,218,199),anchor='mt')
sheet.save(ROOT/'preview/app-icon.png')
print('Rendered ivory / claret enamel locket, 1024 × 1024 RGB.')
