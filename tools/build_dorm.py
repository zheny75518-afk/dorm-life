from pathlib import Path
import json, math, re, random, sys, xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
for folder in ['Scripts/Dorm','Data/Floors','Art/Dorm','docs','Scenes/Environment','Scenes/UI']:
    (ROOT/folder).mkdir(parents=True,exist_ok=True)
cells={c.get('id'):c for c in ET.parse(next((ROOT/'references').glob('*.drawio'))).iter('mxCell')}
def offset(c):
    g=c.find('mxGeometry'); x=float(g.get('x',0));y=float(g.get('y',0))
    p=cells.get(c.get('parent'))
    if p is not None and p.find('mxGeometry') is not None:
        a,b=offset(p); x+=a;y+=b
    return x,y
zones=[]
for c in cells.values():
    g=c.find('mxGeometry'); style=c.get('style','')
    if g is None or 'group' in style or not c.get('vertex'):continue
    x,y=offset(c);w=float(g.get('width',0));h=float(g.get('height',0))
    rot=float((re.search(r'rotation=([-\d.]+)',style) or [None,0])[1])
    if abs(rot)%180==90:x+=(w-h)/2;y+=(h-w)/2;w,h=h,w
    label=c.get('value','')
    kind='corridor'
    for ru,en in [('блок','block'),('кухня','kitchen'),('холл','hall'),('лоджия','loggia'),('лифт','elevator'),('лестница','stairs'),('аудитория','classroom'),('балкон','balcony')]:
        if ru in label.lower():kind=en;break
    zones.append(dict(id=c.get('id').split('-')[-1],label=label,kind=kind,source=[x,y,w,h],rect=[round(v*.6/16)*16 for v in [x,y,w,h]]))
data=dict(floor_id=8,tile_size=16,source_scale=.6,spawn=[256,232],zones=zones)
if not (ROOT/'Data/Floors/floor08.json').exists() or '--reset-layout' in sys.argv:
    (ROOT/'Data/Floors/floor08.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

# Small, hand-authored pixel assets. No downloaded interior art.
random.seed(8)
def asset(name,size,paint):
    im=Image.new('RGBA',size);d=ImageDraw.Draw(im);paint(d);im.save(ROOT/f'Art/Dorm/{name}.png')
def tile(d):
    d.rectangle((0,0,15,15),fill='#999f9b');d.rectangle((1,1,14,14),fill='#c4c8ba');d.line((1,1,14,1),fill='#d7d7c8');d.line((1,1,1,14),fill='#d7d7c8')
    for i in range(8):
        x=random.randrange(2,14);y=random.randrange(2,14);d.point((x,y),fill=random.choice(['#bcc0b3','#cdd0c1']))
asset('floor',(16,16),tile)
def hall(d):
    d.rectangle((0,0,15,15),fill='#8e7261');d.rectangle((1,1,14,14),fill='#b48b70');d.line((1,1,14,1),fill='#ccb08a')
    for i in range(15):d.point((random.randrange(1,15),random.randrange(1,15)),fill='#c49c79')
asset('terrazzo',(16,16),hall)
def wall(d):
    d.rectangle((0,0,15,31),fill='#8b725f');d.rectangle((1,1,14,7),fill='#ead7ae');d.rectangle((1,8,14,27),fill='#d1ac89');d.line((1,9,14,9),fill='#e2c49d');d.rectangle((1,28,14,30),fill='#eee2c3')
    for i in range(16):d.point((random.randrange(2,14),random.randrange(11,27)),fill='#caa582')
asset('wall',(16,32),wall)
def door(d):
    d.rectangle((0,0,31,31),fill='#44372f');d.rectangle((2,2,29,30),fill='#81543a');d.rectangle((5,5,26,26),outline='#a06b46');d.line((7,6,7,25),fill='#95623e');d.line((24,6,24,25),fill='#684632');d.rectangle((23,17,27,18),fill='#d4c7a0');d.rectangle((11,3,21,8),fill='#e9d9ad')
asset('door',(32,32),door)
def lift(d):
    d.rectangle((0,0,47,47),fill='#474e4e');d.rectangle((2,6,45,46),fill='#d4d6c7');d.rectangle((5,9,23,44),fill='#a7b4ae');d.rectangle((25,9,42,44),fill='#bac3b7');d.line((23,9,23,44),fill='#667976');d.line((7,11,7,42),fill='#dce0cb');d.rectangle((18,0,30,5),fill='#272f32');d.text((22,-2),'8',fill='#ff8a6a');d.rectangle((43,24,46,31),fill='#ede6cb');d.point((44,27),fill='#e8a65d')
asset('elevator',(48,48),lift)
def stove(d):
    d.rectangle((1,6,30,30),fill='#634b36');d.rectangle((2,3,29,23),fill='#bc8d52');d.rectangle((4,5,27,19),fill='#414643')
    for x in [9,21]:
        for y in [9,16]:d.ellipse((x-4,y-3,x+3,y+2),fill='#222d2d',outline='#727c72')
    d.line((5,22,26,22),fill='#d9ba7d');d.rectangle((5,25,26,28),fill='#9c7547');d.line((5,30,5,31),fill='#2f3d3b');d.line((27,30,27,31),fill='#2f3d3b')
asset('stove',(32,32),stove)
def sink(d):
    d.rectangle((1,5,30,30),fill='#728b86');d.rectangle((0,3,31,22),fill='#ecedd9');d.rounded_rectangle((4,6,27,19),radius=3,fill='#a3b5b0');d.rectangle((14,0,17,9),fill='#b4c5c0');d.line((14,0,20,0),fill='#e9edda');d.ellipse((14,14,17,16),fill='#667c7a');d.rectangle((4,24,27,29),outline='#aab9a9')
asset('sink',(32,32),sink)
def window(d):
    d.rectangle((0,0,63,31),fill='#d9e2c9');d.rectangle((3,3,60,26),fill='#5d6e81')
    for x in range(5,60,10):
        d.rectangle((x,12,x+7,25),fill='#4c596d')
        for y in [15,21]:d.rectangle((x+2,y,x+3,y+2),fill=random.choice(['#efbb7c','#d88b68','#687b8b']))
    for x in [1,20,41,61]:d.rectangle((x,0,x+1,29),fill='#eff0d9')
    d.line((2,5,58,5),fill='#c18d7d');d.rectangle((0,29,63,31),fill='#f0e8cc')
asset('window',(64,32),window)
def radiator(d):
    for x in range(1,31,4):d.rectangle((x,1,x+2,10),fill='#e4dfc5',outline='#aaa995')
    d.line((0,3,31,3),fill='#dfd8b9');d.line((0,8,31,8),fill='#c8c6ad')
asset('radiator',(32,12),radiator)
def board(d):
    d.rectangle((0,0,47,31),fill='#5b493b');d.rectangle((2,2,45,29),fill='#9d8b65');d.rectangle((3,3,44,8),fill='#465e64')
    for x,y in [(5,11),(20,11),(33,11),(7,21),(25,21)]:
        d.rectangle((x,y,x+9,y+7),fill='#e6dfbf');d.line((x+1,y+2,x+7,y+2),fill='#a8ab97');d.point((x+4,y),fill='#c96e52')
asset('board',(48,32),board)
def rack(d):
    d.line((2,3,2,29),fill='#e2dfc9');d.line((29,3,29,29),fill='#e2dfc9')
    for y in range(4,26,5):d.line((1,y,30,y),fill='#b5c7bd')
    for x,c in [(4,'#6c8290'),(13,'#d9cfaf'),(22,'#b88469')]:
        d.rectangle((x,7,x+5,22),fill=c);d.line((x+1,8,x+1,20),fill='#e6ddbf')
asset('rack',(32,32),rack)
def stairs(d):
    d.rectangle((0,0,47,63),fill='#6d7976')
    for y in range(0,61,7):d.rectangle((4,y,42,y+4),fill='#bfc5b5');d.line((4,y+5,42,y+5),fill='#8e9c93')
    d.line((1,1,1,62),fill='#d9d4bc');d.line((45,1,45,62),fill='#d9d4bc')
asset('stairs',(48,64),stairs)
def table(d):
    d.rectangle((2,4,45,30),fill='#5e4d39');d.rectangle((0,0,47,24),fill='#bd925e',outline='#77563c');d.line((2,2,45,2),fill='#ddba7c');d.rectangle((29,8,37,14),fill='#e9ddbc');d.rectangle((8,8,14,16),fill='#7e9991');d.line((10,7,13,7),fill='#d9debe')
asset('table',(48,32),table)
def lamp(d):
    d.rectangle((0,1,31,6),fill='#a5b4a7');d.rectangle((2,2,29,4),fill='#f4efd0')
asset('lamp',(32,8),lamp)

project=ROOT/'project.godot';s=project.read_text(encoding='utf-8');s=s.replace('config/name="Topdown Starter"','config/name="Dorm Life"').replace('run/main_scene="res://Scenes/Levels/MainFloor.tscn"','run/main_scene="res://Scenes/Levels/DormFloor08.tscn"');s=s if 'window/size/window_width_override=' in s else s.replace('window/size/viewport_width=640','window/size/viewport_width=640\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720');s=s.replace('environment/defaults/default_clear_color=Color(0, 0, 0, 1)','environment/defaults/default_clear_color=Color(0.105, 0.137, 0.145, 1)');project.write_text(s,encoding='utf-8')
(ROOT/'Scenes/Levels/DormFloor08.tscn').write_text('''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Scripts/Dorm/FloorManager.gd" id="1"]

[node name="DormFloor08" type="Node2D"]
script = ExtResource("1")
''',encoding='utf-8')
print('Generated',len(zones),'source zones and 14 pixel assets')
