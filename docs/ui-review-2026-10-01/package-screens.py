from pathlib import Path
import csv
import io
import json
import zipfile

root = Path(__file__).resolve().parent
archive = root / 'Plated UI Screens.zip'
app = json.loads((root / 'screen-manifest.json').read_text())
extras = json.loads((root / 'widget-manifest.json').read_text())
entries = []
for i, row in enumerate(app, 1):
    screen_id = f'A{i:02d}'
    matches = sorted((root / 'qa-captures').glob(f'{screen_id}-*.png'))
    preferred = root / 'qa-captures' / f'{screen_id}-edit-profile.png' if screen_id == 'A28' else None
    selected = preferred if preferred and preferred.exists() else (matches[0] if matches else None)
    source = str(selected.relative_to(root)) if selected else row['file']
    entries.append((screen_id, row['title'], 'App screen or state', source))
widget_i = share_i = 0
for row in extras:
    if row.get('family') == 'shareExtension':
        share_i += 1
        sid, group = f'X{share_i:02d}', 'Share extension state'
        source = row['file']
    else:
        widget_i += 1
        sid, group = f'W{widget_i:02d}', 'Widget or timer layout'
        crop = Path('widget-crops') / Path(row['file']).name
        source = str(crop) if (root / crop).exists() else row['file']
    entries.append((sid, row['title'], group, source))

readme = ('Plated UI screen review images\n\n'
          f'{len(entries)} numbered images: app screens and states (A), widget and timer layouts (W), '
          'and share extension states (X). Open manifest.csv to map screen IDs to filenames. '
          'Images are review captures using sample data; widget and timer layouts are source previews.\n')
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    zf.writestr('README.txt', readme)
    manifest = io.StringIO(newline='')
    writer = csv.writer(manifest)
    writer.writerow(['screen_id', 'name', 'type', 'filename'])
    for sid, title, group, source in entries:
        suffix = Path(source).suffix
        filename = f'{sid} - {title}{suffix}'
        writer.writerow([sid, title, group, f'images/{filename}'])
        zf.write(root / source, f'images/{filename}')
    zf.writestr('manifest.csv', manifest.getvalue())
print(f'Created {archive} with {len(entries)} images ({archive.stat().st_size:,} bytes).')
