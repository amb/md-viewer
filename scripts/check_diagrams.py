#!/usr/bin/env python3
"""Exercise the bundled renderer offscreen, including theme pixels and vector output."""
import json
import pathlib
import struct
import subprocess
import tempfile
import zlib

app = pathlib.Path(__file__).resolve().parents[1] / 'dist/MD View.app/Contents/MacOS/MDView'
jobs = [
    {'id': 0, 'source': 'flowchart LR\nA[Markdown] --> B[Native text]'},
    {'id': 1, 'source': 'sequenceDiagram\nAlice->>Bob: Hello\nBob-->>Alice: Hi'},
    {'id': 2, 'source': 'this is not a diagram'},
    {'id': 3, 'source': 'pie title Share\n"Swift" : 90\n"Mermaid" : 10'},
    {'id': 4, 'source': 'flowchart LR\n' + '\n'.join(f'n{i}[Node {i}] --> n{i+1}[Node {i+1}]' for i in range(80))},
]
for dark in [False, True]:
    name = 'dark' if dark else 'light'
    colors = (['#1e1e2e', '#cdd6f4', '#1e1e2e', '#313244', '#89b4fa', '#9399b2'] if dark else
              ['#ffffff', '#4c4f69', '#eff1f5', '#e6e9ef', '#1e66f5', '#7c7f93'])
    theme = dict(zip(['background', 'text', 'primary', 'secondary', 'accent', 'line'], colors), dark=dark)
    with tempfile.TemporaryDirectory(prefix='md-view-check-') as directory:
        folder = pathlib.Path(directory)
        (folder / 'jobs.json').write_text(json.dumps(jobs))
        (folder / 'theme.json').write_text(json.dumps(theme))
        subprocess.run([str(app.with_name('MermaidWorker')), directory], check=True, timeout=90)
        results = json.loads((folder / 'results.json').read_text())
        assert len(results) == len(jobs), results
        for result in results:
            if result['id'] == 2:
                assert result.get('error'), result
                continue
            assert not result.get('error'), result
            data = (folder / f"{result['id']}.png").read_bytes()
            assert data[:8] == b'\x89PNG\r\n\x1a\n'
            width, height = struct.unpack('>II', data[16:24])
            assert 0 < width <= 1400 and 0 < height <= 1400, (width, height)
            assert len(data) > 100, 'Empty diagram image'
            assert result.get('fontSize', 0) > 0, 'Missing rendered label font size'
            if result['id'] == 4:
                assert result['fontSize'] >= 15, 'Vector export must preserve natural-size labels'
            assert data[24] == 8 and data[25] in [2, 6], 'Expected 8-bit RGB(A)'
            # All PNG filters use zero predictors for the top-left pixel.
            position, compressed = 8, bytearray()
            while position < len(data):
                length = struct.unpack('>I', data[position:position + 4])[0]
                if data[position + 4:position + 8] == b'IDAT':
                    compressed.extend(data[position + 8:position + 8 + length])
                position += length + 12
            pixel = zlib.decompress(compressed)[1:4]
            expected = bytes.fromhex(theme['background'][1:])
            assert all(abs(a - b) <= 3 for a, b in zip(pixel, expected)), (name, list(pixel), list(expected))
            pdf = (folder / f"{result['id']}.pdf").read_bytes()
            assert pdf.startswith(b'%PDF-') and len(pdf) > 1000, 'Missing vector output'
            print(f"{name} diagram {result['id']}: {width}×{height}, label {result['fontSize']:.2f} pt, PDF {len(pdf)} bytes")
        (app.parents[4] / f'.build/diagram-{name}.png').write_bytes((folder / '0.png').read_bytes())
        (app.parents[4] / f'.build/diagram-{name}.pdf').write_bytes((folder / '0.pdf').read_bytes())
        if not dark:
            (app.parents[4] / 'examples/diagram.png').write_bytes((folder / '0.png').read_bytes())
print('PASS: both themes, vector output, flowchart, sequence, pie, malformed input, and renderer exit.')
