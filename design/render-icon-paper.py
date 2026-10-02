"""Render the editable icon geometry with supersampled gradients, plus size previews."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SCALE = 3
SIZE = 1024 * SCALE

def gradient(stops, weights=(0.3, 0.7)):
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    t = (xx * weights[0] + yy * weights[1]) / (SIZE - 1)
    channels = [np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops]) for c in range(3)]
    return Image.fromarray(np.stack(channels, axis=-1).astype('uint8'))

def curve(a, b, c):
    return [((1-t)**2*a[0]+2*(1-t)*t*b[0]+t*t*c[0],
             (1-t)**2*a[1]+2*(1-t)*t*b[1]+t*t*c[1]) for t in np.linspace(0,1,80)]

def mask(points):
    m = Image.new('L', (SIZE, SIZE))
    ImageDraw.Draw(m).polygon([(round(x*SCALE), round(y*SCALE)) for x,y in points], fill=255)
    return m

paper = [(344,194),(680,194)] + curve((680,194),(808,194),(808,322)) + [(808,650),(648,810),(344,810)] + curve((344,810),(216,810),(216,682)) + [(216,322)] + curve((216,322),(216,194),(344,194))
fold = [(648,810),(648,706)] + curve((648,706),(648,650),(704,650)) + [(808,650)]
paper_mask = mask(paper)
image = gradient([(0,(255,254,253)),(1,(255,244,238))],(0.15,0.85))
shadow = Image.new('L',(SIZE,SIZE))
shadow.paste(paper_mask,(0,26*SCALE))
shadow = shadow.filter(ImageFilter.GaussianBlur(28*SCALE)).point(lambda x: round(x*0.14))
image.paste((167,46,32),(0,0,SIZE,SIZE),shadow)
image.paste(gradient([(0,(255,140,107)),(0.48,(255,80,59)),(1,(212,34,31))]),(0,0),paper_mask)
image.paste(gradient([(0,(255,241,219)),(1,(255,152,119))]),(0,0),mask(fold))
draw = ImageDraw.Draw(image)
for x, y, h in [(325,456,92),(407,404,196),(489,350,304),(571,404,196),(653,456,92)]:
    draw.rounded_rectangle((x*SCALE,y*SCALE,(x+46)*SCALE,(y+h)*SCALE),23*SCALE,fill=(255,254,251))
image = image.resize((1024,1024),Image.Resampling.LANCZOS)
image.save(ROOT/'QuickRecord/Assets.xcassets/AppIcon.appiconset/AppIcon.png')

# Preview uses rounded corners only to simulate the system mask. Shipping PNG is opaque square.
sheet = Image.new('RGB',(1000,670),(239,239,244))
for x,y,size in [(45,45,560),(685,65,180),(685,300,120),(695,490,60)]:
    icon = image.resize((size,size),Image.Resampling.LANCZOS)
    clip = Image.new('L',(size*3,size*3));d = ImageDraw.Draw(clip)
    d.rounded_rectangle((0,0,size*3-1,size*3-1),radius=size*.225*3,fill=255)
    sheet.paste(icon,(x,y),clip.resize((size,size),Image.Resampling.LANCZOS))
sheet.save(ROOT/'preview/app-icon.png')
