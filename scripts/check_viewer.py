#!/usr/bin/env python3
"""Offscreen app integration: events, helper lifetime, memory. No UI input."""
import json
import pathlib
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
app = root / 'dist/MD View.app/Contents/MacOS/MDView'

def wait_for(state_file, process, predicate):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        assert process.poll() is None, f'Viewer exited: {process.returncode}'
        try:
            state = json.loads(state_file.read_text())
            if predicate(state):
                return state
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.05)
    raise AssertionError('State timeout: ' + (state_file.read_text() if state_file.exists() else 'missing'))

with tempfile.TemporaryDirectory(prefix='md-view-app-check-') as directory:
    folder = pathlib.Path(directory)
    source = folder / 'readme.md'
    state_file = folder / 'state.json'
    source.write_text('# Initial\nNative **text**.\n')
    process = subprocess.Popen([str(app), '--inspect', str(source), str(state_file)])
    try:
        state = wait_for(state_file, process, lambda s: 'Initial' in s['text'])
        assert state['contentIsScrollView'], 'Window must contain only the document scroll view'
        assert {'Open…', 'Reload', 'Reveal in Finder', 'Find…', 'Zoom In', 'Zoom Out',
                'Actual Size', 'Fit Diagram to Window', 'Render Mermaid Diagrams', 'Back', 'Forward'} <= set(state['menuCommands'])
        assert not state['rendererRunning']
        assert state['handlesSystemKeys'], 'Application must route system navigation keys'
        print(f"Plain document: {state['footprintBytes'] / 1048576:.1f} MiB physical footprint, {state['rssBytes'] / 1048576:.1f} MiB RSS")
        source.write_text('# Direct save\nNative content changed.\n')
        wait_for(state_file, process, lambda s: 'Direct save' in s['text'])
        replacement = folder / 'replacement.md'
        replacement.write_text('# Atomic save\nReplacement content.\n')
        replacement.replace(source)
        wait_for(state_file, process, lambda s: 'Atomic save' in s['text'])
        source.unlink()
        time.sleep(0.4)
        source.write_text('# Recreated\nBack again.\n')
        wait_for(state_file, process, lambda s: 'Recreated' in s['text'])
        source.write_text((root / 'examples/demo.md').read_text())
        state = wait_for(state_file, process, lambda s: '2 diagram(s) rendered' in s['status'] and not s['rendererRunning'])
        assert 'Rendering diagram' not in state['text']
        assert state['text'].count('\ufffc') >= 2
        assert state['diagramVectors'] == 2, 'Mermaid previews must retain vector output'
        print(f"Two diagrams: {state['footprintBytes'] / 1048576:.1f} MiB physical footprint, {state['rssBytes'] / 1048576:.1f} MiB RSS")
        children = subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True, text=True)
        assert children.returncode == 1, f'Unexpected live child process: {children.stdout}'
        # Sample process CPU without interacting with the desktop.
        def cpu():
            return subprocess.check_output(['ps', '-p', str(process.pid), '-o', 'time='], text=True).strip()
        time.sleep(0.5)
        before = cpu()
        time.sleep(2)
        after = cpu()
        print(f'Idle CPU time over 2 seconds: {before} → {after}')
    finally:
        process.terminate()
        process.wait(timeout=5)
print('PASS: native text, in-place save, atomic save, delete/recreate, diagrams, renderer exit.')

# Exercise the real window/Auto Layout hierarchy, with text only.
with tempfile.TemporaryDirectory(prefix='md-view-text-layout-') as directory:
    folder = pathlib.Path(directory)
    source = folder / 'text.md'
    source.write_text('# Text viewport\n\n' + 'Long paragraphs should wrap within the reading margins. ' * 40
        + '\n\n## ' + 'A very long heading ' * 15
        + '\n\n```\n' + 'long_code_identifier_' * 25 + '\n' + '\tcolumn' * 15 + '\n```\n'
        + '\n\n| Feature | Implementation |\n| --- | --- |\n| Native text | A cell with many words to wrap within its column |\n')
    for width in [400, 600, 1200]:
        state_file = folder / f'{width}.json'
        process = subprocess.Popen([str(app), '--inspect', str(source), str(state_file), str(width)])
        try:
            state = wait_for(state_file, process, lambda s: 'Text viewport' in s['text'])
            assert abs(state['documentWidth'] - state['viewportWidth']) <= 1, state
            assert state['textOriginX'] >= 32, state
            assert state['containerWidth'] + 2 * state['textOriginX'] <= state['viewportWidth'] + 1, state
            assert state['renderedMinX'] >= 32, state
            assert state['renderedMaxX'] <= state['viewportWidth'] - 32 + 1, state
            print(f"Text layout at {width} pt: {state['renderedMinX']:.0f}…{state['renderedMaxX']:.0f}, viewport {state['viewportWidth']:.0f}")
        finally:
            process.terminate()
            process.wait(timeout=5)
print('PASS: text-only window layout at 400, 600, and 1200 points.')
