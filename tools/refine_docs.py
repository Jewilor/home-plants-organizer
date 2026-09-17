from pathlib import Path
p=Path('tools/build_documents.py')
s=p.read_text(encoding='utf-8-sig')
s=s.replace(" return d\n", " for border in list(d.styles.element.xpath('.//w:pBdr')):\n  border.getparent().remove(border)\n return d\n")
p.write_text(s,encoding='utf-8')
p=Path('README.md');s=p.read_text(encoding='utf-8-sig').replace('Откройте папку проекта, установите плагины Flutter и Dart, если IDE их предложит.', 'Откройте `D:\\Development\\home-plants-organizer` в Android Studio. Плагины Flutter и Dart уже установлены.').replace('Запустите Android-эмулятор в Device Manager.', 'Запустите `Plants_API_36` в Device Manager.');p.write_text(s,encoding='utf-8')
