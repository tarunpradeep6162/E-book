from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET
p=Path(__file__).resolve().parents[1]/'dist/scaling-multi-cloud.epub'
with ZipFile(p) as z:
 assert z.namelist()[0]=='mimetype'
 assert z.read('mimetype')==b'application/epub+zip'
 for name in z.namelist():
  if name.endswith(('.xhtml','.opf','.xml','.ncx')): ET.fromstring(z.read(name))
print('EPUB container and XML structure: PASS (not EPUBCheck certification)')
