"""Embed local review assets into one portable HTML file. No app files are changed."""
from pathlib import Path
import base64
import json
import mimetypes
import re

root = Path(__file__).resolve().parent


def data_uri(path):
    mime = mimetypes.guess_type(str(path))[0] or 'application/octet-stream'
    return 'data:' + mime + ';base64,' + base64.b64encode(path.read_bytes()).decode()


html = (root / 'index.html').read_text()
css = (root / 'review.css').read_text()
css = re.sub(r"url\('([^']+)'\)", lambda m: "url('" + data_uri(root / m[1]) + "')", css)
assets = {str(p.relative_to(root)): data_uri(p) for folder in ('current', 'photos')
          for p in sorted((root / 'assets' / folder).iterdir()) if p.is_file()}
js = 'window.PL_reviewAssets=' + json.dumps(assets, separators=(',', ':')) + ';\n'
js += (root / 'review.js').read_text()
licenses = '\n\n'.join(p.read_text() for p in sorted((root / 'assets' / 'fonts').glob('*OFL.txt')))
html = html.replace('<link rel="stylesheet" href="review.css">', '<style>' + css + '</style>')
html = html.replace('<script src="review.js"></script>', '<script>' + js.replace('</script', '<\\/script') + '</script>')
html = html.replace('</head>', '<!-- Bundled font licenses:\n' + licenses.replace('--', '—') + '\n--></head>')
out = root / 'Plated-Design-Review.html'
out.write_text(html)
print(f'Built {out.name} ({out.stat().st_size / 1024 / 1024:.1f} MB), {len(assets)} embedded images.')
