from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent
app = json.loads((root / 'screen-manifest.json').read_text())
extras = json.loads((root / 'widget-manifest.json').read_text())
rows = []
for i, item in enumerate(app, 1):
    screen_id = f'A{i:02d}'
    matches = sorted((root / 'qa-captures').glob(f'{screen_id}-*.png'))
    preferred = root / 'qa-captures' / f'{screen_id}-edit-profile.png' if screen_id == 'A28' else None
    path = preferred if preferred and preferred.exists() else (matches[0] if matches else root / item['file'])
    rows.append((screen_id, item['title'], path))
wi = xi = 0
for item in extras:
    if item.get('family') == 'shareExtension':
        xi += 1
        sid = f'X{xi:02d}'
        path = root / item['file']
    else:
        wi += 1
        sid = f'W{wi:02d}'
        crop = root / 'widget-crops' / Path(item['file']).name
        path = crop if crop.exists() else root / item['file']
    rows.append((sid, item['title'], path))

cols, cell_w, image_h, label_h, gap = 5, 360, 620, 48, 22
margin = 36
row_h = image_h + label_h + gap
canvas = Image.new('RGB', (margin * 2 + cols * cell_w, margin * 2 + ((len(rows) + cols - 1) // cols) * row_h), '#f2f0ec')
draw = ImageDraw.Draw(canvas)
font_path = '/System/Library/Fonts/Supplemental/Arial.ttf'
bold_path = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
font = ImageFont.truetype(font_path, 18)
bold = ImageFont.truetype(bold_path, 19)
for index, (sid, title, path) in enumerate(rows):
    x = margin + (index % cols) * cell_w
    y = margin + (index // cols) * row_h
    with Image.open(path) as source:
        source = source.convert('RGB')
        source.thumbnail((cell_w - 24, image_h), Image.Resampling.LANCZOS)
        px = x + (cell_w - source.width) // 2
        py = y + image_h - source.height
        canvas.paste(source, (px, py))
    draw.text((x + 8, y + image_h + 6), sid, font=bold, fill='#292620')
    draw.text((x + 62, y + image_h + 8), title[:34], font=font, fill='#49453f')

out = root / 'Plated UI Screens Overview.png'
canvas.save(out, optimize=True)
print(f'Created {out} ({canvas.width}x{canvas.height}; {len(rows)} screens).')
