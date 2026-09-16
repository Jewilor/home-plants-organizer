from zipfile import ZipFile
from lxml import etree
from pathlib import Path
p=Path('D:/4 курс/РПдiPiP/РПiPiP Задания на лабораторные работы.docx')
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
with ZipFile(p) as z:
 root=etree.fromstring(z.read('word/document.xml'))
 lines=[]
 for para in root.xpath('//w:body//w:p',namespaces=ns):
  chunks=[]
  for r in para.xpath('./w:r|./w:hyperlink/w:r',namespaces=ns):
   t=''.join(r.xpath('.//w:t/text()',namespaces=ns))
   c=r.xpath('./w:rPr/w:color/@w:val|./w:rPr/w:highlight/@w:val|./w:rPr/w:shd/@w:fill',namespaces=ns)
   chunks.append(('['+','.join(c)+']' if c else '')+t)
  if chunks: lines.append(''.join(chunks))
 Path('docs/source-extracted.txt').write_text('\n'.join(lines),encoding='utf-8')
 print('\n'.join(lines))
