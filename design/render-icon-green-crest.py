"""Glimpse: debossed forest leather, engraved brass and a Baskerville monogram."""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
ROOT=Path(__file__).resolve().parent.parent
S=2; N=1024*S
rng=np.random.default_rng(718)
y,x=np.mgrid[0:N,0:N].astype(np.float32)/S
noise=rng.normal(0,1,(N,N)).astype(np.float32)
cloud=Image.fromarray(np.uint8(rng.uniform(0,255,(256,256)))).resize((N,N),Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(2))
cloud=np.asarray(cloud,dtype=np.float32)/255-.5
light=np.exp(-((x-250)**2+(y-180)**2)/(2*690**2))
# Fine irregular leather grain, continuous to the edge for iOS's system mask.
pores=np.maximum(noise-1.0,0)*1.8
base=13+15*light+cloud*5+noise*.5-pores
rgb=np.stack([base*.65,base*1.33,base*1.08],axis=-1)
rgb+=np.exp(-((x-500)**2+(y-480)**2)/(2*310**2))[:,:,None]*np.array([2,5,3])
mask=Image.new('L',(N,N)); d=ImageDraw.Draw(mask)
def line(points,width=1,fill=255): d.line([(int(a*S),int(b*S)) for a,b in points],fill=fill,width=max(1,round(width*S)),joint='curve')
def ellipse(box,width=1,fill=255): d.ellipse(tuple(round(v*S) for v in box),outline=fill,width=max(1,round(width*S)))
def path(points,width=1,fill=255):
    # Cubic Bezier.
    p=np.asarray(points)
    ts=np.linspace(0,1,90)
    curve=[(1-t)**3*p[0]+3*(1-t)**2*t*p[1]+3*(1-t)*t*t*p[2]+t**3*p[3] for t in ts]
    line(curve,width,fill)
# Tailored double perimeter, deliberately low-key.
for inset,width in [(77,2),(87,0.9)]:
    d.rounded_rectangle((inset*S,inset*S,(1024-inset)*S,(1024-inset)*S),radius=(185-inset/3)*S,outline=155,width=round(width*S))
# Engraved oval cartouche and a guilloche engine-turned band.
cx,cy=512,488
for rx,ry,w in [(266,314,2),(274,322,1),(284,332,1.5)]: ellipse((cx-rx,cy-ry,cx+rx,cy+ry),w,235)
for phase in (0,math.pi):
    pts=[]
    for t in np.linspace(0,2*math.pi,2600):
        ripple=4*math.sin(84*t+phase)
        pts.append((cx+(279+ripple)*math.cos(t),cy+(327+ripple)*math.sin(t)))
    line(pts,.85,200)
# Botanical branches outside the cartouche, each leaf has a central cut.
for side in (-1,1):
    def stem(t):
        a=math.radians(35+120*t)
        return np.array([512+side*338*math.sin(a),482-348*math.cos(a)])
    line([stem(t) for t in np.linspace(0,1,180)],2.2,225)
    for i in range(15):
        t=.06+i*.058
        p=stem(t); tangent=stem(t+.003)-stem(t-.003); tangent/=np.linalg.norm(tangent)
        normal=np.array([tangent[1],-tangent[0]])
        for direction in (-1,1):
            v=tangent*18+normal*direction*29
            tip=p+v
            mid=p+v*.52
            perp=np.array([-v[1],v[0]]);perp/=np.linalg.norm(perp)
            a=mid+perp*6; b=mid-perp*6
            pts=[]
            for u in np.linspace(0,1,22): pts.append((1-u)**2*p+2*(1-u)*u*a+u*u*tip)
            for u in np.linspace(0,1,22): pts.append((1-u)**2*tip+2*(1-u)*u*b+u*u*p)
            d.polygon([(round(q[0]*S),round(q[1]*S)) for q in pts],fill=215)
            line([p+v*.15,p+v*.85],.9,50)
# Small engraved flourishes at the north and south of the composition.
for flip in (False,True):
    def cv(points): return [(a,1024-b if flip else b) for a,b in points]
    for side in (-1,1):
        def pts(points): return cv([(512+side*a,b) for a,b in points])
        path(pts([(0,137),(28,105),(59,114),(59,133)]),1.7,220)
        path(pts([(59,133),(59,151),(30,148),(41,131)]),1.7,220)
        path(pts([(25,134),(86,153),(109,121),(130,122)]),1.1,180)
    diamond=cv([(512,119),(517,129),(512,139),(507,129)])
    d.polygon([(a*S,b*S) for a,b in diamond],fill=230)
# The main mark stays legible at home-screen size.
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Baskerville.ttc',int(475*S))
glyph=Image.new('L',(N,N));gd=ImageDraw.Draw(glyph)
box=gd.textbbox((0,0),'G',font=font)
gx=(N-(box[2]-box[0]))/2-box[0]; gy=469*S-(box[3]-box[1])/2-box[1]
gd.text((gx,gy),'G',font=font,fill=255)
# Discreet audio signature below the monogram.
for offset,h in [(-28,12),(-14,23),(0,35),(14,23),(28,12)]:
    d.rounded_rectangle(((512+offset-2)*S,(713-h/2)*S,(512+offset+2)*S,(713+h/2)*S),radius=2*S,fill=230)
line([(459,713),(468,713)],1,170);line([(556,713),(565,713)],1,170)
# Render physical foil edges using mask-derived surface normals and contact shadows.
def metal_layer(rgb,mask,strength=1):
    coverage=np.asarray(mask,dtype=np.float32)/255
    shadow=Image.new('L',(N,N));shadow.paste(mask,(2*S,3*S))
    sh=np.asarray(shadow.filter(ImageFilter.GaussianBlur(2*S)),dtype=np.float32)/255
    rgb*=1-sh[:,:,None]*.58
    height=np.asarray(mask.filter(ImageFilter.GaussianBlur(1.1*S)),dtype=np.float32)/255*1.6
    gy,gx=np.gradient(height,1/S,1/S)
    norm=np.sqrt(gx*gx+gy*gy+1)
    diffuse=np.clip((-.48*-gx+-.62*-gy+.62)/norm,0,1)
    reflection=12*np.sin((x+y*.28)/195)+8*np.exp(-((x+y*.4-370)/160)**2)
    sheen=0.72+diffuse*.52
    grain=noise*.85+cloud*3
    metal=np.stack([(172+reflection+grain)*sheen,(143+reflection+grain)*sheen,(91+reflection*.65+grain)*sheen],axis=-1)
    a=(coverage*strength)[:,:,None]
    return rgb*(1-a)+metal*a
rgb=metal_layer(rgb,mask)
rgb=metal_layer(rgb,glyph)
image=Image.fromarray(np.uint8(np.clip(rgb,0,255))).resize((1024,1024),Image.Resampling.LANCZOS).convert('RGB')
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
image.save(ROOT/'design/AppIcon-glimpse.png')
sheet=Image.new('RGB',(1220,850),(238,235,227))
for xx,yy,size in [(45,45,740),(895,80,180),(925,355,120),(955,580,60)]:
    icon=image.resize((size,size),Image.Resampling.LANCZOS)
    clip=Image.new('L',(size*3,size*3));cd=ImageDraw.Draw(clip)
    cd.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
    sheet.paste(icon,(xx,yy),clip.resize((size,size),Image.Resampling.LANCZOS))
    if size<740:
        f=ImageFont.truetype('/System/Library/Fonts/Supplemental/Baskerville.ttc',22)
        ImageDraw.Draw(sheet).text((xx+size/2,yy+size+18),'Glimpse',font=f,fill=(51,60,49),anchor='mt')
sheet.save(ROOT/'preview/app-icon.png')
print('Rendered Glimpse icon: opaque RGB, 1024 × 1024.')
