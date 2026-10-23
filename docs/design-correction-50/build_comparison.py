from pathlib import Path
import json, shutil, os
root=Path(__file__).resolve().parent
repo=root.parent.parent
build=Path('/Users/natemeadows/Plated/build')
entries=json.loads((repo/'docs/design-fidelity-2026-10-18/mapping-plan.json').read_text())['entries']
index={}
for manifest in sorted(build.glob('Release'+os.environ.get('CAPTURE_BUILD','50')+'*-captures/manifest.json')):
 for test in json.loads(manifest.read_text()):
  for a in test.get('attachments',[]):
   if a['exportedFileName'].endswith('.png'):
    name=a['suggestedHumanReadableName'].split('_0_')[0]
    if name not in index or a['timestamp'] > index[name][1]['timestamp']:
     index[name]=(manifest.parent/a['exportedFileName'],a)
alias={'plan-open/open/dark':['polish-plan-open-dark'],'plan-open/out/dark':['polish-plan-eating-out'],'ipad/default/dark':['ipad-matrix-plan-dark-default'],'plan-meal/today/dark':['polish-plan-dark'],'plan-meal/today/light':['polish-plan-light']}
result={}
(root/'captures').mkdir(exist_ok=True)
for e in entries:
 candidates=[x['attachmentName'] for x in (e['nativeCaptures'] or [])]+alias.get(e['key'],[])
 matches=[]
 for name in candidates:
  if name in index:
   src,a=index[name];dst=root/'captures'/f'{name}.png';shutil.copy2(src,dst)
   matches.append({'file':'captures/'+dst.name,'timestamp':a['timestamp'],'note':('Intermediate correction capture · development build 49' if 'Design-captures' in str(src) else 'Build '+os.environ.get('CAPTURE_BUILD','50'))+' · '+a['deviceName']+' · '+name+' · isolated fixture, not live account evidence'})
 if matches:
  matches.sort(key=lambda x:x['timestamp'],reverse=True)
  result[e['key']]=matches[0] | {'additional':matches[1:]}
(root/'capture-index.js').write_text('window.captureIndex = '+json.dumps(result)+';\n')
shutil.copy2(repo/'docs/design-fidelity-2026-10-18/approved-data.js',root/'approved-data.js')
s=(repo/'docs/design-fidelity-2026-10-18/Native-Design-Comparison.html').read_text().replace('This is an unreleased correction candidate after build 45.','This is the build 50 correction candidate.').replace('Native candidate · unreleased','Build 50 · native candidate')
s=s.replace('<div class="native">','<div class="native">')
s=s.replace('</section><section class="panel">', '<div id="capture-choices"></div></section><section class="panel">')
s=s.replace('if(c){img.src=c.file;', 'document.querySelector("#capture-choices").replaceChildren();if(c){img.src=c.file;')
s=s.replace('img.src=c.file;', '''img.src=c.file;const choices=document.querySelector('#capture-choices');choices.replaceChildren();[c,...(c.additional||[])].forEach((item,i)=>{const b=document.createElement('button');b.textContent='Capture '+(i+1);b.onclick=()=>{img.src=item.file;document.querySelector('#status').textContent=item.note};choices.append(b)});''')
s=s.replace('.panel h2{', '.panel>h2{').replace('Build 50 · native candidate', 'Native capture · see build above')
(root/'Comparison.html').write_text(s)
print(f'{len(result)}/72 exact state/appearance entries available; push concept has no simulator substitute.')
