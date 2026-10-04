from pathlib import Path
import argparse
import hashlib
import json
import re
import sqlite3
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(
    description='Verify the lab 3 sample after an Android process restart.',
    epilog='Requires a saved Aglaonema plant with species Aglaonema commutatum, family Aroids, two weekly procedures and two care records created through the normal app UI.',
)
parser.add_argument('--adb', default='adb')
parser.add_argument('--device', default='emulator-5554')
parser.add_argument('--output-dir', default='reports/qa/lab3/restart')
args = parser.parse_args()
output = Path(args.output_dir).resolve()
output.mkdir(parents=True, exist_ok=True)
package = 'by.it41.home_plants_organizer'
command = [args.adb, '-s', args.device]

def adb(*arguments):
    return subprocess.run(command + list(arguments), check=True, capture_output=True).stdout

def copy_db(stage):
    target = output / (stage + '.sqlite')
    target.write_bytes(adb('exec-out', 'run-as', package, 'cat', 'files/garden.sqlite'))
    with sqlite3.connect(target) as db:
        return {table: db.execute('SELECT * FROM ' + table + ' ORDER BY rowid').fetchall()
                for table in ['plants', 'care_procedures', 'care_records', 'procedure_completions', 'settings']}

def hive_hashes():
    return {name: hashlib.sha256(adb('exec-out', 'run-as', package, 'cat', 'files/reference_catalog/' + name + '.hive')).hexdigest()
            for name in ['plant_families', 'fertilizer_types', 'reference_metadata']}

adb('shell', 'am', 'start', '-W', '-n', package + '/.MainActivity')
time.sleep(1)
old_pid = adb('shell', 'pidof', package).decode().strip()
adb('shell', 'am', 'force-stop', package)
before = copy_db('before')
hive_before = hive_hashes()
adb('shell', 'am', 'start', '-W', '-n', package + '/.MainActivity')
time.sleep(1)
new_pid = adb('shell', 'pidof', package).decode().strip()
assert new_pid and new_pid != old_pid, (old_pid, new_pid)
after = copy_db('after')
assert before == after, 'Relational state changed during a restart'
hive_after = hive_hashes()
assert hive_before == hive_after, 'Catalog values changed during a restart'
plant = next((row for row in after['plants'] if row[1] == 'Aglaonema'), None)
if plant is None:
    parser.error('The prepared Aglaonema sample is missing; create it through the normal app UI before this check.')
assert plant[2] == 'Aglaonema commutatum' and plant[6] == 'family-aroids'
assert sum(row[1] == plant[0] for row in after['care_records']) == 2
assert sum(row[1] == plant[0] and row[4] == 1 for row in after['care_procedures']) == 2

# Check the restored data through the normal application interface.
for _ in range(3):
    adb('shell', 'input', 'swipe', '360', '1300', '360', '300', '350')
    time.sleep(0.3)
adb('shell', 'uiautomator', 'dump', '/sdcard/plants_lab3_ui.xml')
xml = adb('shell', 'cat', '/sdcard/plants_lab3_ui.xml')
(output / 'catalog-ui.xml').write_bytes(xml)
nodes = list(ET.fromstring(xml).iter('node'))
assert any('Aglaonema' in node.get('content-desc', '') for node in nodes)
buttons = [node for node in nodes if node.get('content-desc') == 'Справка и журнал ухода']
assert buttons, 'Restored plant detail button is missing'
bounds = [int(value) for value in re.findall(r'\d+', buttons[-1].get('bounds', ''))]
adb('shell', 'input', 'tap', str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))
time.sleep(0.7)
adb('shell', 'uiautomator', 'dump', '/sdcard/plants_lab3_ui.xml')
xml = adb('shell', 'cat', '/sdcard/plants_lab3_ui.xml')
(output / 'detail-ui.xml').write_bytes(xml)
texts = [node.get('content-desc', '') for node in ET.fromstring(xml).iter('node')]
assert any('Aglaonema' in value for value in texts)
assert any('Семейство: Ароидные' in value for value in texts)
assert any('Ботаническая справка' in value for value in texts)
screenshot = Path('screenshots/lab3/11_android_restart.png')
screenshot.parent.mkdir(parents=True, exist_ok=True)
screenshot.write_bytes(adb('exec-out', 'screencap', '-p'))
result = {'status': 'passed', 'previous_pid': old_pid, 'new_pid': new_pid,
          'rows': {name: len(rows) for name, rows in after.items()},
          'catalog_files': hive_after, 'plant_id': plant[0], 'screenshot': str(screenshot)}
(output / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
