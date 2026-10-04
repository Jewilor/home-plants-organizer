"""Build the separate lab 3 report from the retained lab 2 design."""
from pathlib import Path
from copy import deepcopy
from hashlib import sha256
import json
import re
import subprocess
from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.opc.constants import RELATIONSHIP_TYPE as RT
from build_lab2_report import style_paragraph, blank

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'reports/Лабораторная работа №3 с листингом А.docx'
MARKDOWN = REPORT.with_suffix('.md')
REFERENCE = ROOT / 'reports/Лабораторная работа №2.docx'
FENCE = chr(96) * 3
LISTING_FILES = [
    'pubspec.yaml',
    'lib/main.dart',
    'lib/models/plant.dart',
    'lib/models/garden_snapshot.dart',
    'lib/models/reference_entry.dart',
    'lib/services/garden_repository.dart',
    'lib/services/reference_repository.dart',
    'lib/services/sqlite_garden_repository.dart',
    'lib/services/hive_reference_repository.dart',
    'lib/services/garden_resources.dart',
    'lib/services/storage_bootstrap_native.dart',
    'lib/services/storage_bootstrap_web.dart',
    'lib/viewmodels/garden_view_model.dart',
    'lib/viewmodels/reference_view_model.dart',
    'lib/views/app_loader.dart',
    'lib/views/storage_notice.dart',
    'lib/views/reference_screen.dart',
    'lib/views/editors.dart',
    'lib/views/garden_screen.dart',
    'lib/views/plant_detail_screen.dart',
    'test/lab3_storage_test.dart',
    'integration_test/lab3_demo_test.dart',
    'test_driver/lab3_screenshots.dart',
    'tools/verify_lab3_restart.py',
]
APPENDIX_TITLE = 'Приложение А'
GITHUB_URL = 'https://github.com/Jewilor/home-plants-organizer'


def listing_sources():
    # The complete set of authored source/configuration files in the lab 3 commit.
    changed = subprocess.check_output(
        ['git', 'diff', '--name-only', '6183bbe', '7f97324'],
        cwd=ROOT, text=True,
    ).splitlines()
    expected = {path for path in changed if path.endswith(('.dart', '.py', '.yaml'))}
    if expected != set(LISTING_FILES):
        raise ValueError('The appendix file set differs from the implementation commit')
    return {path: (ROOT / path).read_text(encoding='utf-8-sig').rstrip()
            for path in LISTING_FILES}



def extract(relative, begin=None, end=None):
    source = (ROOT / relative).read_text(encoding='utf-8')
    a = source.index(begin) if begin else 0
    b = source.index(end, a) if end else len(source)
    return source[a:b].rstrip()


def report_text():
    parts = [
        '# Лабораторная работа №3',
        '',
        'Механизмы сериализации, локального и долговременного хранения данных средствами Flutter.',
        '',
        'Выполнил: студент группы ИТИ-41 Заяц М. С.',
        '',
        'Принял: старший преподаватель Семенченя Т. С.',
        '',
        '**Цель работы:** освоить сохранение состояния мобильного приложения и управление локальными данными, изучить сериализацию, реляционное и нереляционное хранение, реализовать восстановление коллекции растений и истории ухода после повторного запуска приложения.',
        '',
        '**Задание:** выполнить часть варианта № 7 «Мобильный органайзер домашних растений», выделенную жёлтым цветом. Основная реляционная база должна хранить карточки растений, журнал выполненных процедур и расписание ухода. Вспомогательная нереляционная база должна содержать справочники семейств растений и типов удобрений. Для каждой записи справочника необходимо сохранять уникальный идентификатор, название и значок.',
        '',
        'Проект выполнен на языке Dart с использованием Flutter. Для адаптации требований к выбранным средствам разработки применены SQLite через пакет sqflite и нереляционное хранилище Hive CE. SQLite выполняет роль основной базы данных, а Hive CE используется вместо указанного в первоначальном задании Realm. Постоянное хранение реализовано и проверено в приложении для Android. Исходный код и отчёт размещены в репозитории GitHub: [https://github.com/Jewilor/home-plants-organizer](https://github.com/Jewilor/home-plants-organizer).',
        '',
        '**Ход выполнения работы:** проанализирована структура приложения, подготовленного в предыдущих лабораторных работах. Сохранены каталог растений, календарь, журнал ухода, ручной ввод условий содержания и распознавание названия с этикетки. Для этих данных разработаны отдельные средства сохранения и восстановления. Сетевое получение справки и системные уведомления не относятся к выполненному этапу и в данной работе не используются.',
        '',
        'Для основной базы подготовлен файл garden.sqlite в каталоге служебных данных приложения. Созданы таблицы plants, care_procedures, care_records, procedure_completions и settings. Карточка растения содержит название, вид, комнату, условия содержания, обозначение изображения и ссылку на семейство. Процедура содержит ссылку на растение, дату начала, вид ухода, признак еженедельного повторения, дату выполнения и ссылку на удобрение. В журнале хранится фактически выполненное действие, а не будущий план.',
        '',
        'Связи растения с расписанием и журналом реализованы внешними ключами plant_id. Для них включено каскадное удаление. Отметки отдельных повторений связаны с процедурой через procedure_id; сочетание идентификатора процедуры и даты повторения образует составной первичный ключ. Ограничение UNIQUE в журнале запрещает повторную запись одинакового вида ухода для одного растения в один день. Перед работой с базой выполняется PRAGMA foreign_keys = ON. Создание схемы и сохранение связей приведены в приложении А, листинг А.8.',
        '',
        'Для вспомогательной базы созданы отдельные коллекции plant_families и fertilizer_types. Общая модель ReferenceEntry содержит поля id, name и icon. При записи объект преобразуется методом toMap в набор поддерживаемых значений, а при чтении восстанавливается методом fromMap. Значок сохраняется как имя элемента перечисления ReferenceIcon, поэтому сохранённая запись не зависит от устройства отображения. Для ввода названия и выбора значка разработана форма, представленная на рисунке 1. Модель записи и работа хранилища приведены в приложении А, листинги А.5 и А.9.',
        '',
    ]
    def fig(n, caption, filename):
        parts.extend([f'![Рисунок {n} – {caption}](../screenshots/lab3/{filename})', ''])
    def prose(text):
        parts.extend([text, ''])

    fig(1, 'Форма добавления семейства растения', '01_reference_editor.png')
    prose('Разработан экран «Справочники», который открывается кнопкой с изображением книги на главном экране. Раздел «Семейства» отображает записи в алфавитном порядке. После сохранения введённое семейство «Марантовые» появляется в списке. Данные сначала записываются в Hive CE, затем обновляется отображаемая коллекция. Результат добавления семейства представлен на рисунке 2.')
    fig(2, 'Справочник семейств после добавления записи', '02_families.png')
    prose('В разделе «Удобрения» реализованы аналогичные операции добавления, изменения и удаления. При проверке создано удобрение «Комплексное» со значком питательных веществ. ReferenceViewModel удаляет пробелы по краям названия, проверяет допустимую длину и не допускает одинаковых названий в одном разделе без учёта регистра. Справочник типов удобрений после сохранения новой записи представлен на рисунке 3.')
    fig(3, 'Справочник типов удобрений', '03_fertilizers.png')
    prose('Форма добавления и редактирования растения дополнена выбором семейства. Элемент ReferenceSelector отображает название и значок, но возвращает устойчивый идентификатор записи. Этот идентификатор записывается в поле family_id таблицы plants. Переименование семейства не нарушает связь, поскольку название не используется в качестве ключа. Собственные условия содержания сохраняются в поле care_conditions. Форма заполнения карточки учебного растения представлена на рисунке 4. Реализация выбора семейства приведена в приложении А, листинг А.18.')
    fig(4, 'Карточка растения с семейством и условиями содержания', '04_plant_editor.png')
    prose('Форма календарной процедуры дополнена выбором удобрения для подкормки. При выборе другого вида ухода ссылка на удобрение очищается. Признак «Еженедельно» сохраняется вместе с датой начала серии. На рисунке 5 представлена форма подкормки растения «Учебная аглаонема» с выбранным удобрением «Комплексное» и включённым еженедельным повторением.')
    fig(5, 'Подкормка с выбором удобрения и недельным повторением', '05_procedure_editor.png')
    prose('Сохранение сада отделено от пользовательского интерфейса через GardenRepository. После изменения GardenViewModel создаёт объект GardenSnapshot с копиями коллекций растений, процедур, записей ухода и отметок повторений. Операции записи выполняются последовательно через цепочку Future, поэтому более позднее состояние не записывается раньше более раннего. Каждое состояние сохраняется в одной транзакции SQLite. При ошибке показывается сообщение с возможностью повторного сохранения; успешное завершение подтверждается надписью «Изменения сохранены на устройстве». Очередь сохранения и отображение её состояния приведены в приложении А, листинги А.13 и А.16.')
    prose('При нажатии «Полить сегодня» в журнал добавляется факт полива, а соответствующее повторение получает отметку выполнения. Для записи подкормки использована форма «Записать уход». Процедуры будущих дат остаются в расписании. На рисунке 6 представлены сохранённые условия содержания, выбранное семейство и журнал с выполненным поливом и подкормкой за 04.10.2026.')
    fig(6, 'Сохранённая карточка и журнал выполненного ухода', '06_saved_journal.png')
    prose('При запуске openGarden открывает обе базы, загружает справочники и получает сохранённый GardenSnapshot. Переданное состояние используется конструктором GardenViewModel для восстановления коллекций и счётчика идентификаторов. Начальные демонстрационные записи создаются только при отсутствии признака initialized. Пустая коллекция после удаления всех растений является сохранённым состоянием и не заменяется демонстрационными данными. Для проверки обе базы были закрыты и повторно открыты из тех же файлов. Восстановленная карточка представлена на рисунке 7. Открытие хранилищ и ожидание загрузки реализованы в приложении А, листинги А.11 и А.15.')
    fig(7, 'Карточка после закрытия и повторного открытия баз данных', '07_after_reopen.png')
    prose('Еженедельное расписание сохраняется как дата начала и признак повторения. Приложение вычисляет наличие процедуры для выбранного календарного дня, а не создаёт бесконечную последовательность записей. Отдельные выполненные повторения сохраняются в procedure_completions. После восстановления данных полив и подкормка 04.10.2026 остаются выполненными, а следующие повторения доступны 11.10.2026. Восстановленное расписание на следующую неделю представлено на рисунке 8.')
    fig(8, 'Недельное расписание после восстановления данных', '08_saved_schedule.png')
    prose('Между SQLite и Hive CE отсутствует общий внешний ключ базы данных. Поэтому проверка ссылок выполнена в моделях состояния. Перед удалением семейства проверяются карточки растений, а перед удалением удобрения проверяется расписание. Пока основная база сохраняется либо её запись завершилась ошибкой, удаление справочника блокируется. Попытка удалить семейство «Ароидные», используемое учебным растением, завершилась сообщением, представленным на рисунке 9. Проверка использования записей приведена в приложении А, листинги А.13 и А.14.')
    fig(9, 'Проверка использования записи перед удалением', '09_reference_guard.png')
    prose('Запись справочника, на которую нет ссылок, удаляется после подтверждения пользователя. Для проверки из списка удалено ранее добавленное семейство «Марантовые растения». Сначала завершена операция delete в Hive CE, затем обновлено представление. Состояние справочника после удаления представлено на рисунке 10.')
    fig(10, 'Удаление неиспользуемого семейства', '10_reference_deleted.png')
    prose('Для обновления структуры основной базы предусмотрена миграция с первой версии на вторую. Метод upgradeToVersionTwo добавляет поля family_id и fertilizer_id командами ALTER TABLE. Существующие карточки, журнал и расписание сохраняются. В отличие от удаления файла базы такой подход позволяет установить новую версию приложения поверх предыдущей без потери данных. Проверка миграции выполнялась на специально подготовленной базе первой версии. Миграция и её проверка приведены в приложении А, листинги А.8 и А.21.')
    prose('Дополнительно проверена обычная сборка приложения версии 1.2.0, запущенная независимо от проверочного сценария. Через интерфейс добавлено растение Aglaonema, выбрано семейство «Ароидные», создано недельное расписание и записаны полив и подкормка. Затем процесс приложения был полностью остановлен средствами Android и запущен заново. До и после перезапуска сравнены строки всех таблиц SQLite и контрольные суммы файлов Hive CE. Значения совпали; восстановленное растение представлено на рисунке 11.')
    fig(11, 'Растение после полного перезапуска процесса Android', '11_android_restart.png')
    prose('Для работы с основной базой написан SqliteGardenRepository. Метод load читает связанные таблицы в транзакции и преобразует строки в модели. Метод save согласует сохранённые записи с переданным состоянием. Существующие строки обновляются командой UPDATE, новые вставляются, отсутствующие удаляются. Замена родительских строк не применяется, чтобы не запускать каскадное удаление при обычном редактировании карточки. Календарные даты записываются как строки вида 2026-10-04 без времени суток и преобразования часового пояса.')
    prose('Для хранения идентификаторов используются отдельные счётчики. Счётчик сада сохраняется в таблице settings вместе с остальными данными транзакции. Счётчик справочников находится в коллекции reference_metadata и резервируется до записи новой записи. После повторного запуска созданные объекты не получают идентификаторы уже существующих объектов. У справочников отдельно сохранён признак начального заполнения, поэтому намеренно удалённые записи не восстанавливаются автоматически.')
    prose('Полный исходный код файлов, добавленных или изменённых при выполнении третьей лабораторной работы, вынесен в приложение А. В основном тексте приведены пояснения реализации и ссылки на соответствующие листинги. В приложение также включены файлы автоматизированных проверок и конфигурация зависимостей.')

    prose('Проверка выполнена автоматизированными проверками моделей, хранилищ и интерфейса, а также запуском на эмуляторе Android. Успешно завершены 35 проверок проекта. Проверены восстановление данных, сохранение пустой коллекции, каскадное удаление, откат транзакции при ошибке, миграция схемы, последовательность записи, повторное сохранение после ошибки, операции Hive CE, устойчивость идентификаторов и проверка используемых справочников. На эмуляторе отдельно выполнен сценарий работы двух баз через формы приложения. Анализ исходного кода не выявил ошибок. Собран и установлен новый установочный пакет приложения. Исходный код проверок приведён в приложении А, листинги А.21–А.24.')

    prose('**Ответы на контрольные вопросы:**')
    prose('Хранилище UserDefaults предназначено прежде всего для небольших настроек приложения. Оно поддерживает строки, числа, логические значения, даты, двоичные данные, массивы и словари допустимых типов. Произвольный объект необходимо предварительно преобразовать в поддерживаемые данные. Такое хранилище не предоставляет связей между сущностями, сложных выборок и общей транзакции для карточек и журнала. Универсальный допустимый объём для всех задач не задаётся; большие коллекции следует хранить в базе данных. В выполненном проекте настройки служебного состояния размещены в settings, а пользовательские данные сохраняются в SQLite и Hive CE.')
    prose('Протокол Decodable определяет восстановление объекта из внешнего представления, Encodable определяет обратное преобразование, а Codable объединяет оба протокола. В Swift несовпадающие имена ключей и свойств задаются перечислением CodingKeys. В Dart соответствие задаётся явно в функциях преобразования. В данном проекте careConditions сопоставлено с care_conditions, familyId с family_id, а fertilizerId с fertilizer_id. ReferenceEntry.toMap и ReferenceEntry.fromMap выполняют сериализацию и восстановление записи справочника; отдельное преобразование всех данных в JSON для хранения в SQLite не требуется.')
    prose('SQLite является реляционной базой данных: сведения размещаются в таблицах, связи и ограничения задаются схемой, выборки выполняются средствами SQL. Realm использует объектную модель, в которой программа работает с сохраняемыми объектами и связями через предоставленные библиотекой средства. В проекте выбран SQLite для связанных карточек и журнала, а вспомогательная нереляционная база реализована на Hive CE. Hive CE хранит пары ключей и значений и не является объектной заменой Realm с полностью одинаковыми возможностями.')
    prose('В SwiftData компонент ModelContainer определяет схему моделей и конфигурацию постоянного хранилища. ModelContext управляет получением, добавлением, изменением, удалением и сохранением экземпляров моделей. В данном проекте аналогичные обязанности разделены между openGarden, SqliteGardenRepository и моделями состояния. Соединение Database выполняет транзакции, а GardenViewModel управляет состоянием приложения и направляет изменения на сохранение. Компоненты SwiftData в исходном коде Flutter не используются.')
    prose('В SwiftData отношения описываются ссылками на модель либо коллекцией моделей; при необходимости задаётся Relationship с обратной связью и правилом удаления. Правило cascade удаляет зависимые объекты при удалении владельца. В реляционной базе связь одного объекта с несколькими реализуется внешним ключом в зависимой таблице. Для отношения одного объекта с одним дополнительно используется ограничение уникальности внешнего ключа. В данном проекте одно растение имеет несколько процедур и записей журнала. Их удаление обеспечивается REFERENCES plants(id) ON DELETE CASCADE.')
    prose('Миграция схемы представляет собой переход сохранённых данных от прежней структуры к новой. Она необходима при добавлении, удалении либо изменении полей, связей и ограничений. Для SwiftData применяются версии схемы и план миграции. В SQLite проекта используется номер schemaVersion и обработчик onUpgrade. Переход с первой версии на вторую добавляет две ссылки на справочники и сохраняет содержимое прежних таблиц. Проверка миграции подтверждает сохранность карточки и служебного счётчика.')
    prose('В SwiftUI обёртка Query получает модели SwiftData с заданным условием отбора и порядком сортировки, а изменение данных отражается в представлении. В данном проекте SQLite.query задаёт порядок чтения журнала по дате, затем модель детального экрана отбирает записи нужного растения и выбранного вида ухода. Представления Flutter подписаны на ChangeNotifier и обновляются через ListenableBuilder после notifyListeners. Прямой аналог Query с автоматически отслеживаемым запросом базы в этой реализации не применяется.')
    prose('При работе Realm необходимо учитывать привязку управляемых объектов к потоку и передавать между потоками разрешённые ссылки либо независимые значения. В SwiftData операции следует выполнять в соответствующем контексте, а для выделенной работы с данными применяется ModelActor. В проекте Flutter изменяемое состояние принадлежит одному изоляту Dart. Неизменяемые снимки передаются в последовательную очередь асинхронных операций, а записи SQLite объединены транзакцией. Операции справочника ожидаются через await и блокируют повторное редактирование до завершения. Работа Hive CE из нескольких изолятов в проекте не реализована.')
    prose('Отложенная загрузка означает получение объекта или его связанных данных при первом обращении вместо предварительной загрузки всей коллекции. Такой подход уменьшает начальные затраты оперативной памяти и время запуска при большом количестве записей. Для крупных списков дополнительно применяются ограничение размера выборки и последовательная загрузка частей списка. В данной учебной реализации небольшие коллекции загружаются целиком, поэтому отложенная загрузка объектов базы не заявляется. Недельные повторения календаря вычисляются по запросу для выбранной даты.')
    prose('Защита локальной базы может включать шифрование файла базы либо отдельных конфиденциальных полей и безопасное хранение ключа. Для SQLite существуют средства шифрования, например SQLCipher; Realm поддерживает открытие зашифрованной базы с ключом. Hive CE предоставляет HiveAesCipher. На iOS ключ следует хранить средствами Keychain, на Android средствами Android Keystore, а не в исходном коде или обычных настройках. В данном проекте шифрование баз не включено; хранение в служебном каталоге приложения само по себе не является шифрованием.')

    prose('Вывод: реализовано долговременное локальное хранение мобильного органайзера домашних растений. Реляционная база SQLite сохраняет карточки растений, журнал выполненного ухода, расписание и отметки недельных повторений. Нереляционное хранилище Hive CE сохраняет редактируемые справочники семейств и удобрений. Реализованы преобразование моделей, последовательное сохранение, миграция схемы и проверка связей между хранилищами. Автоматизированные проверки и полный перезапуск приложения на Android подтвердили восстановление сохранённых данных.')
    parts.extend([APPENDIX_TITLE, '', '(обязательное)', '', 'Листинг программы', ''])
    prose('В приложении приведены полные тексты всех файлов исходного кода и конфигурации зависимостей, добавленных или изменённых при реализации третьей лабораторной работы. Для изменённых файлов сохранены также ранее существовавшие части, чтобы листинг отражал целостную текущую реализацию. Файлы проверок приведены после исходного кода приложения.')
    for index, (file, source) in enumerate(listing_sources().items(), 1):
        prose(f'Листинг А.{index} – Файл {file}')
        language = 'python' if file.endswith('.py') else 'yaml' if file.endswith('.yaml') else 'dart'
        parts.extend([FENCE + language, source, FENCE, ''])
    return '\n'.join(parts)


def hyperlink(p, label, url):
    node = OxmlElement('w:hyperlink')
    node.set(qn('r:id'), p.part.relate_to(url, RT.HYPERLINK, is_external=True))
    run = OxmlElement('w:r')
    props = OxmlElement('w:rPr')
    for tag, attributes in [
        ('w:rFonts', {'w:ascii':'Times New Roman','w:hAnsi':'Times New Roman','w:cs':'Times New Roman'}),
        ('w:sz', {'w:val':'28'}),
        ('w:i', {}),
        ('w:color', {'w:val':'000000'}),
        ('w:u', {'w:val':'single'}),
    ]:
        element = OxmlElement(tag)
        for key, value in attributes.items():
            element.set(qn(key), value)
        props.append(element)
    run.append(props)
    text = OxmlElement('w:t')
    text.text = label
    run.append(text)
    node.append(run)
    p._p.append(node)


def add_text(document, line):
    text = line.replace('**', '')
    if line.startswith('**') or line.startswith('Вывод:'):
        if document.paragraphs[-1].text.strip():
            blank(document)
    p = document.add_paragraph()
    if line.startswith('**') and ':' in text:
        label, rest = text.split(':', 1)
        p.add_run(label + ':').bold = True
        p.add_run(rest)
    else:
        cursor = 0
        for match in re.finditer(r'\[([^\]]+)\]\((https?://[^)]+)\)', text):
            p.add_run(text[cursor:match.start()])
            hyperlink(p, match[1], match[2])
            cursor = match.end()
        p.add_run(text[cursor:])
    style_paragraph(p)
    p.paragraph_format.widow_control = True
    return p


def build():
    before = sha256(REFERENCE.read_bytes()).hexdigest()
    content = report_text()
    MARKDOWN.write_text(content, encoding='utf-8')
    d = Document(REFERENCE)
    title = [deepcopy(p._p) for p in d.paragraphs[:36]]
    body = d._element.body
    for item in list(body):
        if not item.tag.endswith('sectPr'):
            body.remove(item)
    for element in title:
        body.insert(len(body)-1, element)
    d.paragraphs[15].text = 'ЛАБОРАТОРНАЯ РАБОТА № 3'
    d.paragraphs[18].text = 'на тему: «Механизмы сериализации, локального и долговременного хранения данных средствами Flutter»'
    for i, p in enumerate(d.paragraphs):
        style_paragraph(p, indent=False)
        p.paragraph_format.keep_with_next = False
        p.paragraph_format.keep_together = False
        if i in (25,26,27,28):
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.left_indent = Cm(8)
        elif p.text:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    section = d.sections[0]
    section.page_width = Cm(21)
    section.page_height = Cm(29.7)
    section.left_margin = Cm(3)
    section.right_margin = Cm(1)
    section.top_margin = section.bottom_margin = Cm(2)
    for style in d.styles:
        if style.type == 1:
            style.paragraph_format.space_before = Pt(0)
            style.paragraph_format.space_after = Pt(0)
            style.paragraph_format.line_spacing = 1
    d.styles['Normal'].font.name = 'Times New Roman'
    d.styles['Normal'].font.size = Pt(14)
    in_code = False
    started = False
    figures = 0
    appendix = False
    listing_count = 0
    for line in content.splitlines():
        if not started:
            if line.startswith('**Цель работы:'):
                started = True
            else:
                continue
        if line.startswith(FENCE):
            in_code = not in_code
            continue
        if in_code:
            p = d.add_paragraph(line)
            style_paragraph(p, indent=False, size=11 if line.strip() else 14, code=bool(line.strip()))
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.keep_together = True
            p.paragraph_format.widow_control = False
            continue
        if not line.strip():
            continue
        if line == APPENDIX_TITLE:
            appendix = True
            p = d.add_paragraph(line)
            style_paragraph(p, center=True, indent=False)
            p.paragraph_format.page_break_before = True
            p.paragraph_format.keep_with_next = True
            continue
        if appendix and line in ('(обязательное)', 'Листинг программы'):
            p = d.add_paragraph(line)
            style_paragraph(p, center=True, indent=False)
            p.paragraph_format.keep_with_next = True
            continue
        if appendix and line.startswith('Листинг А.'):
            if d.paragraphs[-1].text.strip():
                blank(d)
            listing_count += 1
            p = d.add_paragraph(line)
            style_paragraph(p, indent=False, size=11, code=True)
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.keep_with_next = True
            p.paragraph_format.keep_together = True
            continue
        image = re.fullmatch(r'!\[(.*?)\]\((.*?)\)', line)
        if image:
            d.paragraphs[-1].paragraph_format.keep_with_next = True
            blank(d, keep=True)
            p = d.add_paragraph()
            style_paragraph(p, center=True, indent=False)
            picture = p.add_run().add_picture(str((ROOT/'reports'/image[2]).resolve()), width=Cm(6.4))
            picture._inline.docPr.set('descr', image[1])
            p.paragraph_format.keep_with_next = True
            blank(d, keep=True)
            caption = d.add_paragraph(image[1])
            style_paragraph(caption, center=True, indent=False)
            caption.paragraph_format.keep_together = True
            blank(d)
            figures += 1
        else:
            p = add_text(d, line)
            if line.endswith('.dart.'):
                p.paragraph_format.keep_with_next = True
    d.core_properties.title = 'Лабораторная работа №3. Мобильный органайзер домашних растений'
    d.core_properties.subject = 'Сериализация и долговременное хранение данных'
    d.core_properties.author = 'Заяц М. С.'
    d.core_properties.last_modified_by = 'Заяц М. С.'
    drawing_id = 1
    parts = [d.part]
    parts.extend(part for part in d.part.related_parts.values() if hasattr(part, 'element'))
    for part in parts:
        for node in part.element.iter():
            if node.tag == '{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}docPr':
                node.set('id', str(drawing_id))
                drawing_id += 1
    d.save(REPORT)
    assert sha256(REFERENCE.read_bytes()).hexdigest() == before
    assert figures == 11
    assert listing_count == len(LISTING_FILES)
    assert any(rel.reltype == RT.HYPERLINK and rel.target_ref == GITHUB_URL for rel in d.part.rels.values())
    print(json.dumps({'report':str(REPORT),'figures':figures,'paragraphs':len(d.paragraphs),'listings':listing_count,'reference_unchanged':True},ensure_ascii=False))


if __name__ == '__main__':
    build()
