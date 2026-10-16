from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json
import threading

ROOT = Path(__file__).resolve().parent
LOCK = threading.Lock()
NOTES = ROOT / 'review-notes.json'

def screens():
    app = json.loads((ROOT / 'screen-manifest.json').read_text())
    extras = json.loads((ROOT / 'widget-manifest.json').read_text())
    result = []
    for prefix, rows in [('A', app), ('W', [r for r in extras if r.get('family') != 'shareExtension']), ('X', [r for r in extras if r.get('family') == 'shareExtension'])]:
        for i, row in enumerate(rows, 1):
            result.append(dict(row, screenId=f'{prefix}{i:02d}', file=('widget-crops/' + Path(row['file']).name) if prefix == 'W' else row['file']))
    return result

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def json_response(self, value, status=200):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/api/screens':
            return self.json_response(screens())
        if self.path == '/api/notes':
            with LOCK:
                return self.json_response(json.loads(NOTES.read_text()) if NOTES.exists() else {})
        return super().do_GET()

    def do_POST(self):
        if self.path != '/api/notes':
            return self.json_response({'error': 'Unknown route'}, 404)
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > 100000:
                raise ValueError('Note too large')
            value = json.loads(self.rfile.read(length))
            sid = value['screenId']
            if sid not in {r['screenId'] for r in screens()} or not isinstance(value['note'], str):
                raise ValueError('Invalid note')
            with LOCK:
                notes = json.loads(NOTES.read_text()) if NOTES.exists() else {}
                notes[sid] = {'note': value['note'], 'decision': value.get('decision', 'Discuss'), 'priority': value.get('priority', 'Medium')}
                temp = NOTES.with_suffix('.tmp')
                temp.write_text(json.dumps(notes, indent=2))
                temp.replace(NOTES)
            return self.json_response({'saved': True})
        except (ValueError, KeyError):
            return self.json_response({'error': 'Invalid note'}, 400)

    def log_message(self, *args):
        pass

if __name__ == '__main__':
    print('Plated review: http://127.0.0.1:8769/review.html', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8769), Handler).serve_forever()
