"""Render the exact Lua scene with fixture data, not an in-game screenshot."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'.tools/python'))
from lupa.lua54 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='"+root.as_posix()+"/Scripts/?.lua;'..package.path")
fixture=lua.execute((root/'tests/preview.lua').read_text(encoding='utf-8'))
scene=lua.eval("require('overview_scene')")[0]
dest=root/'docs';dest.mkdir(exist_ok=True)
overflows=[]
for view,mode in (('Overview','Status'),('Overview','Trends'),('Overview','Stores'),('Pals',None),('Production',None),('Production','Recipes'),('Production','Supplies'),('Priorities',None)):
    state=lua.table_from({'view':view,'base':'preview','overview_mode':mode})
    if mode=='Recipes': state.picker=fixture.picker
    if mode=='Supplies': state.plan=fixture.plan
    nodes=scene.build(fixture.snapshot,state,fixture.priorities)
    im=Image.new('RGB',(1200,760),'#0B1C29');draw=ImageDraw.Draw(im)
    draw.text((20,730),'Example data  /  Bases dashboard layout',font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',15),fill='#A9C1D0')
    areas={}
    for _,n in nodes.items():
        x,y,w,h=n.x,n.y,n.w,n.h
        if n.kind=='scroll':
            areas[n.id]=n
            if n.content_height<=h: continue
            draw.rectangle((x+w-6,y,x+w,y+h),fill='#1C343D')
            draw.rectangle((x+w-6,y,x+w,y+h*min(1,h/n.content_height)),fill='#52D6F6')
            continue
        area=areas.get(n.parent)
        if area and y>=area.y+area.h:continue
        target=im
        if area:
            target=Image.new('RGBA',im.size)
            draw=ImageDraw.Draw(target)
        if n.kind!='text':draw.rectangle((x,y,x+w,y+h),fill=n.color)
        if n.text:
            font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',round(n.size*4/3))
            ink=n.ink or n.color
            longest=max(draw.textlength(line,font=font) for line in n.text.splitlines())
            if longest>w-(16 if n.kind=='button' else 0):overflows.append((view,n.id,round(longest),w,n.text))
            if n.kind=='button':
                bbox=draw.textbbox((0,0),n.text,font=font)
                x+=(w-longest)/2;y+=(h-(bbox[3]-bbox[1]))/2-bbox[1]
            draw.multiline_text((x,y),n.text,font=font,fill=ink,spacing=4)
        if area:
            bounds=(round(area.x),round(area.y),round(area.x+area.w-18),round(area.y+area.h))
            crop=target.crop(bounds)
            im.paste(crop,bounds,crop)
            draw=ImageDraw.Draw(im)
    name=mode.lower() if mode in ('Trends','Stores','Recipes','Supplies') else view.lower()
    im.save(dest/(name+'-preview.png'))
print('Rendered eight scene previews')
for item in overflows:print('TEXT OVERFLOW',item)
if overflows:sys.exit(1)
