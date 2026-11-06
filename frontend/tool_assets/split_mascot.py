"""Splits tool_assets/paige_mascot.svg into the layers the loading screen
animates (lib/widgets/paige_mascot.dart). Every layer keeps the full
400x420 viewBox, so stacking them at the same size rebuilds the mascot.

Run from frontend/:  python tool_assets/split_mascot.py
"""
import pathlib

SRC = pathlib.Path('tool_assets/paige_mascot.svg')
OUT = pathlib.Path('assets/branding/paige')

lines = SRC.read_text(encoding='utf-8').splitlines()[1:-1]


def find(snippet):
    return next(i for i, l in enumerate(lines) if snippet in l)


shadow = find('cx="200" cy="398"')
sparkles = [find('translate(322,44)'), find('translate(30,236)'), find('translate(380,176)')]
note_yellow = find('translate(352,98)')
note_teal = find('translate(106,54)')
arm_left = find('M100,232')
arm_right = find('M300,210')
legs = find('M172,282')
shoe = find('id="shoe"')
use = find('<use ')
eyes_start = find('cx="150" cy="166"')
cheeks = find('cx="124" cy="214"')
mouth_start = find('<path d="M174,206')
hand_left = find('id="hand"')
hand_right = find('translate(364,290)')

# flutter_svg's <use> support is limited, so draw the mirrored shoe directly.
shoe_plain = lines[shoe].replace('<g id="shoe">', '<g>')
shoe_mirror = lines[shoe].replace('<g id="shoe">', '<g transform="translate(400,0) scale(-1,1)">')

layers = {
    'sparkles': [lines[i] for i in sparkles],
    'note_yellow': [lines[note_yellow]],
    'note_teal': [lines[note_teal]],
    # Drawn behind the body so the shoulder end hides under the book.
    'arm_back': [lines[arm_left]],
    'body': [lines[arm_right], lines[legs], shoe_plain, shoe_mirror]
    + lines[use + 1:eyes_start]
    + [lines[cheeks], lines[cheeks + 1], lines[hand_right]],
    'eyes': lines[eyes_start:cheeks],
    'mouth': lines[mouth_start:mouth_start + 3],
    'hand_wave': [lines[hand_left].replace(' id="hand"', '')],
}

head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 420" width="400" height="420">'
OUT.mkdir(parents=True, exist_ok=True)
for name, body in layers.items():
    (OUT / f'{name}.svg').write_text(head + '\n' + '\n'.join(body) + '\n</svg>\n', encoding='utf-8', newline='\n')
    print(f'{name}: {len(body)} elements')
