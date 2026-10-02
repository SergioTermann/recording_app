"""Glimpse: garnet enamel and a sculpted antique-gold starburst jewel.
Deterministic supersampled material rendering; no image-generation API used.
"""
from pathlib import Path
import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ROOT=Path(__file__).resolve().parent.parent
S=2; N=1024*S
rng=np.random.default_rng(918)
y,x=np.mgrid[0:N,0:N].astype(np.float32)/S
u,v=x-512,y-495
r=np.hypot(u,v); theta=np.arctan2(v,u)
noise=rng.normal(0,1,(N,N)).astype(np.float32)
# Rich translucent burgundy lacquer; no repeating decorative frame.
soft=np.exp(-((x-260)**2/(2*560**2)+(y-185)**2/(2*420**2)))
pool=np.exp(-((x-520)**2+(y-430)**2)/(2*330**2))
edge=np.clip((np.maximum(abs(x-512),abs(y-512))-365)/180,0,1)
rgb=np.stack([31+35*soft+12*pool-11*edge,
              8+8*soft+2*pool-3*edge,
              16+14*soft+5*pool-6*edge],axis=-1)
# Subsurface striations and extremely fine vitreous surface texture.
cloud=gaussian_filter(noise,8)*7
rgb+=(noise*.27+cloud*.7)[:,:,None]
broad=np.exp(-((x+y*.8-210)/165)**2)
rgb+=broad[:,:,None]*np.array([9,4,5])
# Soft raised enamel tile edge highlights, using a rounded-square distance.
qx=abs(x-512)-310; qy=abs(y-512)-310
sd=np.hypot(np.maximum(qx,0),np.maximum(qy,0))+np.minimum(np.maximum(qx,qy),0)-164
rim=np.exp(-((sd+22)/2.2)**2)
direction=np.clip((-(u+v)/760+.65),0,1)
rgb+=rim[:,:,None]*(direction*8)[:,:,None]*np.array([1,.45,.53])
# Long elegant rays form a sculpted antique starburst setting.
# Separate shaped rays permit engraved faces and physically rounded bevels.
metal_mask=np.zeros((N,N),np.float32)
height=np.zeros_like(metal_mask)
engraving=np.zeros_like(metal_mask)
for i in range(16):
    a=i*np.pi/8-np.pi/2
    along=u*np.cos(a)+v*np.sin(a)
    across=-u*np.sin(a)+v*np.cos(a)
    if i%4==0: length=290 if i in (0,8) else 247; width=34
    elif i%2==0: length=222; width=25
    else: length=158; width=16
    t=np.clip((along-43)/(length-43),0,1)
    # Slight concavity echoes hand-cut elongated marquise settings.
    half=width*np.sin(np.pi*t)**.85*(1-.18*t)
    mask=(along>43)&(along<length)&(abs(across)<half)
    dist=distance_transform_edt(mask)/S
    coverage=np.clip(dist*S,0,1)
    bevel=np.sin(np.minimum(dist/3.7,1)*np.pi/2)
    ridge=(1-np.minimum(abs(across)/np.maximum(half,1),1))*5.2
    h=(3.6+ridge)*bevel
    # A tapered, hairline engraving follows the ray's center.
    cut=np.exp(-(across/1.1)**2)*np.clip((along-96)/20,0,1)*np.clip((length-18-along)/25,0,1)
    # Fine tapered parallel chisel marks catch the light at close range.
    secondary=np.exp(-((abs(across)-half*.55)/.60)**2)*np.clip((along-105)/30,0,1)*np.clip((length-28-along)/30,0,1)
    cut=np.maximum(cut,secondary*.38)
    h-=cut*.8
    height=np.maximum(height,h)
    engraving=np.maximum(engraving,cut*coverage)
    metal_mask=np.maximum(metal_mask,coverage)
# Beaded central bezel: restrained, not a second perimeter frame.
ring=np.clip(1-abs(r-76)/8,0,1)
height=np.maximum(height,ring*8)
metal_mask=np.maximum(metal_mask,np.clip((8-abs(r-76))*S,0,1))
for i in range(32):
    a=i*2*np.pi/32
    br=np.hypot(u-86*np.cos(a),v-86*np.sin(a))
    bead=np.sqrt(np.maximum(1-(br/2.5)**2,0))*4
    height=np.maximum(height,bead)
    metal_mask=np.maximum(metal_mask,np.clip((2.5-br)*S,0,1))
# Tiny granulated details along each diagonal; jeweller's milgrain work.
for i in range(8):
    a=i*np.pi/4+np.pi/8
    for rr,rad in [(178,3.3),(188,2.4)]:
        br=np.hypot(u-rr*np.cos(a),v-rr*np.sin(a))
        height=np.maximum(height,np.sqrt(np.maximum(1-(br/rad)**2,0))*4)
        metal_mask=np.maximum(metal_mask,np.clip((rad-br)*S,0,1))
maskimage=Image.fromarray(np.uint8(metal_mask*255))
shadow=Image.new('L',(N,N));shadow.paste(maskimage,(5*S,10*S))
shadow=np.asarray(shadow.filter(ImageFilter.GaussianBlur(7*S)),dtype=np.float32)/255
rgb*=1-shadow[:,:,None]*.65
# Polished gold reflects large studio cards, dark gaps, and fine tool marks.
height=gaussian_filter(height,.5)
gy,gx=np.gradient(height,1/S,1/S)
norm=np.sqrt(1+gx*gx+gy*gy)
nx,ny,nz=-gx/norm,-gy/norm,1/norm
ndotl=np.clip(nx*-.45+ny*-.61+nz*.65,0,1)
card=np.exp(-((nx*.85+ny*.30+.24)/.22)**2)
dark=np.exp(-((nx*.4-ny*.5-.32)/.16)**2)
metal=(.49+.63*ndotl+.30*card-.24*dark)
face=np.stack([185*metal,150*metal,92*metal],axis=-1)
# Narrow neutral highlights on polished bevels, softer patina in engraved recesses.
H=np.array([-.45,-.61,1.65]); H=H/np.linalg.norm(H)
spec=np.clip(nx*H[0]+ny*H[1]+nz*H[2],0,1)**30
face+=spec[:,:,None]*np.array([72,69,61])
face+=(noise*.70)[:,:,None]
face-=engraving[:,:,None]*np.array([19,16,12])
rgb=rgb*(1-metal_mask[:,:,None])+face*metal_mask[:,:,None]
# Domed garnet cabochon with depth, caustic rim, and a broad photographic glint.
cab=np.clip((66-r)*S,0,1)
z=np.sqrt(np.maximum(1-(r/66)**2,0))
inner=np.exp(-((u-16)**2+(v-19)**2)/(2*29**2))
caustic=np.exp(-((r-56)/5)**2)*np.clip((u+v)/65,0,1)
gem=np.stack([51+37*z+38*inner+caustic*33,
              7+6*z+8*inner+caustic*6,
              18+12*z+15*inner+caustic*10],axis=-1)
high=np.exp(-((u+22)/17)**2-((v+27)/7)**2)
gem+=high[:,:,None]*np.array([119,94,85])
rgb=rgb*(1-cab[:,:,None])+gem*cab[:,:,None]
# Discreet pin-prick at a polished edge, physically sized rather than a glow.
spot=np.exp(-((u+21)**2+(v+63)**2)/3)
rgb+=spot[:,:,None]*np.array([90,75,52])
image=Image.fromarray(np.uint8(np.clip(rgb,0,255))).resize((1024,1024),Image.Resampling.LANCZOS).convert('RGB')
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
image.save(ROOT/'design/AppIcon-glimpse-jewel.png')
sheet=Image.new('RGB',(1220,850),(235,230,221))
for xx,yy,size in [(45,45,740),(895,80,180),(925,355,120),(955,580,60)]:
    icon=image.resize((size,size),Image.Resampling.LANCZOS)
    clip=Image.new('L',(size*3,size*3)); d=ImageDraw.Draw(clip)
    d.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
    sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
    if size<740:
        font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Baskerville.ttc',22)
        ImageDraw.Draw(sheet).text((xx+size/2,yy+size+18),'Glimpse',font=font,fill=(62,42,41),anchor='mt')
sheet.save(ROOT/'preview/app-icon.png')
print('Rendered burgundy enamel and antique-gold jewel, 1024 × 1024 RGB.')
