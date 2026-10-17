from pathlib import Path
import json, shutil, sys
from PIL import Image,ImageDraw
base=Path('docs/ux-audit-2026-10-16/evidence')
src=base/sys.argv[1]; dst=base/'screens';dst.mkdir(exist_ok=True)
for test in json.loads((src/'manifest.json').read_text()):
 prefix='first-run-' if test['testIdentifier'].startswith('FirstRun') else ''
 for a in test['attachments']:
  name=prefix+a['suggestedHumanReadableName'].split('_0_')[0]+Path(a['exportedFileName']).suffix
  shutil.copy2(src/a['exportedFileName'],dst/name)
patterns = [('default','[0-9]*.png'),('accessibility','ax-*.png'),('first-run','first-run-*.png')]
if len(sys.argv)>2: patterns=[('deep', '*.png')]
for group,pattern in patterns:
 pics=sorted(dst.glob(pattern)); w=250; h=470; cols=4
 for k in range(0,len(pics),12):
  batch=pics[k:k+12]; sheet=Image.new('RGB',(cols*w,((len(batch)+cols-1)//cols)*h),'#e8e8e8'); d=ImageDraw.Draw(sheet)
  for i,p in enumerate(batch):
   im=Image.open(p).convert('RGB'); im.thumbnail((w-12,h-30)); x=(i%cols)*w; y=(i//cols)*h
   sheet.paste(im,(x+(w-im.width)//2,y+25)); d.text((x+7,y+5),p.stem,fill='black')
  sheet.save(base/(group+'-contact-'+str(k//12+1)+'.jpg'))
print('screens',len(list(dst.glob('*.png'))))
