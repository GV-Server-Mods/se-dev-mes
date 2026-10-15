import re
import os
import subprocess
from PIL import Image

# 1. Read source HTML
with open('docs/se-dev-mes-architecture.html', 'r', encoding='utf-8') as f:
    html = f.read()

m = re.search(r'(<svg[\s\S]*?</svg>)', html)
if not m:
    raise RuntimeError('SVG not found in HTML')
svg = m.group(1)

# Ensure xmlns
if 'xmlns="http://www.w3.org/2000/svg"' not in svg:
    svg = svg.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')

# 2. Export Standalone SVG per export.md
font_style = """<style>@import url('https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&amp;family=Geist:wght@400;500;600&amp;family=Geist+Mono:wght@400;500;600&amp;display=swap');</style>"""
svg_standalone = svg.replace('<defs>', '<defs>\n        ' + font_style)

svg_standalone = re.sub(
    r'(fill|stroke)="rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d*\.?\d+)\s*\)"',
    lambda match: '{0}="#{1:02x}{2:02x}{3:02x}" {0}-opacity="{4}"'.format(
        match.group(1), int(match.group(2)), int(match.group(3)), int(match.group(4)), match.group(5)
    ),
    svg_standalone
)
svg_standalone = re.sub(r'(fill|stroke)="transparent"', r'\1="none"', svg_standalone)
standalone_svg = '<?xml version="1.0" encoding="UTF-8"?>\n' + svg_standalone

with open('docs/se-dev-mes-architecture.svg', 'w', encoding='utf-8') as f:
    f.write(standalone_svg)
print('Exported docs/se-dev-mes-architecture.svg')

# 3. Create minimal HTML for exact diagram-only capture at 1200x760
diag_html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    html, body {{ background: #f5f5f5; width: 1200px; height: 760px; overflow: hidden; }}
    svg {{ width: 1200px; height: 760px; display: block; }}
  </style>
</head>
<body>
  {svg}
</body>
</html>"""

temp_html = os.path.join(os.environ['TEMP'], 'diagram_export.html')
with open(temp_html, 'w', encoding='utf-8') as f:
    f.write(diag_html)

edge_exe = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
temp_diag_png = os.path.join(os.environ['TEMP'], 'diagram_only_raw.png')

cmd1 = f'Start-Process -FilePath "{edge_exe}" -ArgumentList "--headless --disable-gpu --window-size=1200,760 --screenshot={temp_diag_png} file:///{temp_html.replace(chr(92), "/")}" -Wait'
subprocess.run(["powershell", "-Command", cmd1], check=True)

if os.path.exists(temp_diag_png):
    img = Image.open(temp_diag_png)
    cropped = img.crop((0, 0, 1200, 760))
    pixel_only = Image.new('RGB', (1200, 760), (245, 245, 245))
    pixel_only.paste(cropped, (0, 0))
    pixel_only.save('docs/se-dev-mes-diagram-only.png', 'PNG', optimize=True)
    print('Saved docs/se-dev-mes-diagram-only.png (1200x760, clean pixel data only)')

# 4. Render full editorial page
temp_full_png = os.path.join(os.environ['TEMP'], 'diagram_full_raw.png')
html_full_path = os.path.abspath('docs/se-dev-mes-architecture.html').replace('\\', '/')
cmd2 = f'Start-Process -FilePath "{edge_exe}" -ArgumentList "--headless --disable-gpu --window-size=1280,1050 --screenshot={temp_full_png} file:///{html_full_path}" -Wait'
subprocess.run(["powershell", "-Command", cmd2], check=True)

if os.path.exists(temp_full_png):
    full_img = Image.open(temp_full_png)
    pixel_full = Image.new('RGB', full_img.size, (245, 245, 245))
    pixel_full.paste(full_img, (0, 0))
    pixel_full.save('docs/se-dev-mes-architecture.png', 'PNG', optimize=True)
    print('Saved docs/se-dev-mes-architecture.png (full editorial page, clean pixel data)')
