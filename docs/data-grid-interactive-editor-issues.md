# GitHub Issues: Интерактивный редактор данных (Data Grid)

Формат ниже рассчитан на перенос в GitHub / GitLab Issues или трекер задач (Jira, Linear). Каждый блок содержит цель, контекст, технический дизайн, шаги реализации и критерии приемки.

## Labels

- `data-grid`
- `sql-editor`
- `frontend`
- `backend`
- `ux`
- `parser`
- `tests`

## Milestones / Epics

- **Epic A: In-Place Editing & Database DML Synchronization (Редактирование «на лету» и сохранение Ctrl+S)**
- **Epic B: Advanced Quick Filter Engine (Составная фильтрация, логические выражения и предикаты)**
- **Epic C: Value Inspector & Selection Calculations (Подсветка JSON/XML, расширенные метрики Calc)**
- **Epic D: Groupings & Pivot View (Многоуровневая группировка, агрегации SUM/AVG/MIN/MAX)**
- **Epic E: UI Hardening, UX Polish & Regression Tests (Адаптивность тулбара, интеграционные тесты)**

## Recommended Execution Order

1. **DG-01 → DG-04:** Архитектура DML-генератора и подключение сохранения к SQL-воркспейсам (PostgreSQL, MySQL, SQLite, Extensions).
2. **DG-05 → DG-07:** Парсер составных выражений `AND`/`OR`, кавычек, `LIKE`, `IN`, `IS NULL` для быстрого фильтра.
3. **DG-08 → DG-10:** Подсветка синтаксиса JSON/XML/YAML, форматирование XML и расширение панели Calc.
4. **DG-11 → DG-13:** Иерархическая группировка по нескольким колонкам и кастомные агрегации в сводных таблицах.
5. **DG-14 → DG-16:** Адаптивность тулбаров, предотвращение layout overflow и сквозные тесты.

---

# Epic A: In-Place Editing & Database DML Synchronization

## [DG-01](https://github.com/QueryaHub/Querya-Desktop/issues/564) (#564) — Data Grid DML SQL Generator (UPDATE, INSERT, DELETE builder with PK resolution)

**Labels:** `data-grid`, `backend`, `sql-editor`  
**Epic:** A  
**Depends on:** none

### Goal
Создать сервис `DataGridDmlGenerator`, который на основе изменений в `DataGridStagingBuffer` и метаданных таблицы (название таблицы, первичные ключи / уникальные колонки) генерирует безопасные параметризованные или экранированные SQL-выражения `UPDATE`, `INSERT` и `DELETE`.

### Context
`DataGridStagingBuffer` уже хранит `_modifiedCells`, `_insertedRows` и `_deletedRowIndices`. Однако в проекте отсутствует модуль, преобразующий эти дельты в конкретные SQL-запросы под диалекты PostgreSQL, MySQL и SQLite.

### Implementation
1. Создать `lib/features/main_screen/data_grid_dml_generator.dart`:
   - Модель `DmlStatement` (тип операции `insert`/`update`/`delete`, SQL-текст, исходная строка).
   - Метод `generateDml({required String tableName, required List<String> columns, required List<String> primaryKeys, required DataGridStagingBuffer buffer, required SqlDialect dialect})`.
   - Для `UPDATE`: генерировать `UPDATE <table> SET col1 = 'val1', col2 = 'val2' WHERE pk1 = 'old_pk1' AND ...`.
   - Для `INSERT`: генерировать `INSERT INTO <table> (col1, col2) VALUES ('val1', 'val2')`.
   - Для `DELETE`: генерировать `DELETE FROM <table> WHERE pk1 = 'pk1'`.
   - Корректное экранирование спецсимволов и кавычек под целевой диалект (Postgres `$1` / кавычки, MySQL backticks, SQLite).
2. Написать модульные тесты в `test/features/main_screen/data_grid_dml_generator_test.dart`.

### Acceptance Criteria
- [ ] Генерируются точные SQL-запросы для единичных и множественных правок ячеек.
- [ ] Если в строке изменены 3 ячейки, генерируется один `UPDATE` со всеми 3 колонками в `SET`.
- [ ] Если primary key отсутствует, используется сопоставление по всем исходным колонкам строки (`WHERE col1 = 'old1' AND col2 = 'old2' ...`).
- [ ] Тесты покрывают диалекты PostgreSQL, MySQL и SQLite.

---

## [DG-02](https://github.com/QueryaHub/Querya-Desktop/issues/565) (#565) — Staging Buffer & Save Integration in SQL Workspaces

**Labels:** `data-grid`, `frontend`, `sql-editor`  
**Epic:** A  
**Depends on:** DG-01

### Goal
Подключить `DataGridStagingBuffer` и кнопку сохранения к реальным воркспейсам: `postgres_sql_workspace.dart`, `mysql_sql_workspace.dart`, `sqlite_sql_workspace.dart` и `extension_sql_workspace.dart`.

### Context
Сейчас `ResultsTab` в этих воркспейсах вызывается без передачи `stagingBuffer` и `onApplyChanges`, из-за чего тулбар редактирования не отображается для результатов SQL-запросов.

### Implementation
1. В состояниях SQL-воркспейсов (`_PostgresSqlWorkspaceState`, `_MysqlSqlWorkspaceState`, `_SqliteSqlWorkspaceState`) сохранять активный `DataGridStagingBuffer? _stagingBuffer`.
2. При успешном выполнении `SELECT`-запроса инициализировать `_stagingBuffer = DataGridStagingBuffer(columns: _columns, rows: _rows)`.
3. Передавать `stagingBuffer: _stagingBuffer`, `isSaving: _savingChanges` и `onApplyChanges: _applyStagedChanges` в `ResultsTab`.
4. В методе `_applyStagedChanges`:
   - Определять имя целевой таблицы из выполненного запроса (или запрашивать у пользователя/схемы).
   - Вызывать `DataGridDmlGenerator`.
   - Выполнять сгенерированные DML-запросы в транзакции через драйвер подключения.
   - При успехе: обновлять базовые строки `_rows`, сбрасывать `_stagingBuffer` и выводить уведомление о сохраненных строках.
   - При ошибке: откатывать транзакцию и выводить всплывающую ошибку без потери правок в буфере.

### Acceptance Criteria
- [ ] После выполнения `SELECT * FROM table` доступно редактирование ячеек, добавление строк и удаление строк.
- [ ] При нажатии кнопки *Save Changes* или <kbd>Ctrl+S</kbd> / <kbd>⌘S</kbd> изменения атомарно применяются к базе данных.
- [ ] После успешного сохранения статус буфера становится clean (`No changes`).
- [ ] При ошибке базы данных буфер не очищается, пользователь видит текст ошибки и может исправить данные.

---

## [DG-03](https://github.com/QueryaHub/Querya-Desktop/issues/566) (#566) — DML Preview & Confirmation Modal Dialog

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** A  
**Depends on:** DG-01, DG-02

### Goal
Предоставить пользователю возможность просмотреть и скорректировать сгенерированные SQL DML-запросы перед их отправкой в базу данных.

### Context
При массовом редактировании или удалении строк пользователю важно видеть точные `UPDATE`/`DELETE` инструкции для предотвращения случайной перезаписи или потери данных.

### Implementation
1. Создать `lib/features/main_screen/data_grid_dml_preview_dialog.dart`:
   - Список сгенерированных SQL-запросов с подсветкой синтаксиса.
   - Отображение количества затрагиваемых записей (X updates, Y inserts, Z deletes).
   - Кнопки: *Cancel*, *Copy SQL*, *Execute SQL*.
2. Добавить настройку в Preferences: `Confirm before applying Data Grid changes` (по умолчанию включена).
3. Интегрировать диалог в `onApplyChanges` поток.

### Acceptance Criteria
- [ ] При нажатии *Save Changes* открывается модальное окно с текстом SQL-запросов.
- [ ] Пользователь может скопировать запросы или сразу подтвердить их выполнение.
- [ ] Если в настройках отключено подтверждение, сохранение происходит сразу.

---

## [DG-04](https://github.com/QueryaHub/Querya-Desktop/issues/567) (#567) — In-Cell Data Type Validation and Editor Shortcuts

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** A  
**Depends on:** none

### Goal
Добавить валидацию типов вводимых данных в инлайн-редакторе `GridCellEditor` (числа, даты, булевы значения, JSON) и расширить хоткеи навигации.

### Context
Сейчас ячейка принимает любую строку. Если колонка числовая (`INT`, `FLOAT`), а пользователь ввел текст, ошибка возникнет только на этапе сохранения в БД.

### Implementation
1. Передавать метаданные типов колонок (если доступны из драйвера) в `GridCellEditor`.
2. Если ячейка числовая, подсвечивать некорректный ввод красной рамкой и блокировать подтверждение или показывать tooltip.
3. Для boolean колонок добавить быстрый переключатель по клику или нажатию <kbd>Space</kbd> (`true` / `false` / `NULL`).
4. Поддержать быстрый переход по стрелкам вверх/вниз при завершении редактирования по Enter.

### Acceptance Criteria
- [ ] Числовые поля валидируются на клиенте перед отправкой в буфер.
- [ ] Булевы поля можно переключать клавишей <kbd>Space</kbd>.
- [ ] Все хоткеи работают предсказуемо и покрыты тестами.

---

# Epic B: Advanced Quick Filter Engine

## [DG-05](https://github.com/QueryaHub/Querya-Desktop/issues/568) (#568) — Multi-Clause Query Parser with AND / OR and Parentheses

**Labels:** `data-grid`, `parser`, `frontend`  
**Epic:** B  
**Depends on:** none

### Goal
Расширить `GridFilterEngine` для поддержки сложных составных выражений с логическими связками `AND`, `OR` и группирующими скобками `(...)`.

### Context
Сейчас `GridFilterEngine._parsePredicate` обрабатывает только один предикат вида `col op val`. Запросы вроде `status = 'ACTIVE' AND amount > 100` или `dept = 'IT' OR dept = 'HR'` не парсятся как предикаты и сваливаются в простой поиск по подстроке.

### Implementation
1. В `lib/features/main_screen/grid_filter_engine.dart` создать лексер и рекурсивный AST-парсер выражений:
   - Токены: `Identifier`, `StringLiteral`, `NumberLiteral`, `Operator` (`=`, `!=`, `<`, `<=`, `>`, `>=`, `:`, `LIKE`, `ILIKE`, `IN`, `IS`), `LogicalOp` (`AND`, `OR`, `NOT`), `OpenParen`, `CloseParen`.
   - Построение дерева условий `FilterExpressionNode` (`BinaryNode`, `ComparisonNode`, `NotNode`, `TextSearchNode`).
   - Вычисление предиката для каждой строки: `node.evaluate(row, columnIndices)`.
2. Поддержать регистронезависимые ключевые слова (`and`, `AND`, `or`, `OR`).
3. Добавить подробные тесты в `test/features/main_screen/data_grid_engines_test.dart`.

### Acceptance Criteria
- [ ] Корректно вычисляются выражения вида: `status = ACTIVE AND amount > 100`.
- [ ] Корректно вычисляются выражения с `OR` и скобками: `(role = admin OR role = manager) AND active = true`.
- [ ] При синтаксической ошибке в выражении фильтр плавно переключается в режим полнотекстового поиска без исключений и падений.

---

## [DG-06](https://github.com/QueryaHub/Querya-Desktop/issues/569) (#569) — String Literals, Escaped Quotes and Extended Operators (`IN`, `LIKE`, `IS NULL`, `BETWEEN`)

**Labels:** `data-grid`, `parser`, `frontend`  
**Epic:** B  
**Depends on:** DG-05

### Goal
Добавить поддержку строковых литералов в кавычках (с пробелами), а также операторов `IN (...)`, `LIKE`, `ILIKE`, `IS NULL`, `IS NOT NULL`, `BETWEEN`.

### Context
Значения часто содержат пробелы (например `city = 'New York'` или `name LIKE '%John%'`). Без кавычек такие выражения невозможно распарсить однозначно.

### Implementation
1. Поддержать строки в одинарных `'...'` и двойных `"..."` кавычках.
2. Реализовать операторы:
   - `col IN ('A', 'B', 'C')` / `col NOT IN (...)`
   - `col LIKE '%pattern%'` (с поддержкой `%` и `_`)
   - `col ILIKE '%pattern%'` (регистронезависимый)
   - `col IS NULL` и `col IS NOT NULL`
   - `col BETWEEN 10 AND 50`
3. Реализовать экранирование кавычек (`\'`, `\"`).

### Acceptance Criteria
- [ ] Запрос `city = 'New York'` находит только строки со значением `New York` в колонке `city`.
- [ ] Запрос `email LIKE '%@gmail.com'` корректно фильтрует почтовые адреса.
- [ ] Запрос `deleted_at IS NULL` фильтрует только `NULL` или пустые значения.

---

## [DG-07](https://github.com/QueryaHub/Querya-Desktop/issues/570) (#570) — Autocomplete & Syntax Suggestions in Filter Bar

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** B  
**Depends on:** DG-05

### Goal
Добавить всплывающие подсказки (автокомплит) в `DataGridFilterBar` при вводе названий колонок, операторов и уникальных значений.

### Context
Пользователю удобно видеть доступные имена колонок таблицы и подсказки по операторам сразу при наборе в строке фильтра.

### Implementation
1. Разработать оверлей подсказок `DataGridFilterAutocomplete`:
   - При вводе первого слова предлагать список колонок таблицы.
   - После имени колонки предлагать список допустимых операторов (`=`, `!=`, `>`, `<`, `LIKE`, `IN`).
   - После оператора предлагать топ-5 уникальных значений из текущих данных этой колонки.
2. Навигация по подсказкам клавишами <kbd>↑</kbd> / <kbd>↓</kbd> и выбор по <kbd>Enter</kbd> или <kbd>Tab</kbd>.

### Acceptance Criteria
- [ ] При наборе первых букв колонки всплывает список подсказок.
- [ ] Подсказки корректно вставляются по нажатию <kbd>Tab</kbd> / <kbd>Enter</kbd>.
- [ ] Оверлей не мешает прокрутке таблицы и закрывается по <kbd>Esc</kbd>.

---

# Epic C: Value Inspector & Selection Calculations

## [DG-08](https://github.com/QueryaHub/Querya-Desktop/issues/571) (#571) — Color Syntax Highlighting for JSON, XML, HTML, SQL in Value Panel

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** C  
**Depends on:** none

### Goal
Реализовать цветную подсветку синтаксиса (Syntax Highlighting) в `DataGridValuePanel` и `GridCellPopoverInspector` в соответствии с активной темой оформления.

### Context
Сейчас длинные строки JSON/XML в инспекторе форматируются отступами, но отображаются монохромным текстом без цветового выделения ключей, строковых значений, чисел, тегов и атрибутов.

### Implementation
1. Использовать легковесный парсер/хайлайтер токенов или `RichText` / `TextSpan` построитель:
   - JSON: подсветка ключей, строк, чисел, boolean и null разными цветами из текущей палитры `QueryaTheme`.
   - XML/HTML: подсветка тегов, названий атрибутов, строковых значений атрибутов, комментариев.
   - SQL: подсветка ключевых слов, функций и строк.
2. Автоматически определять формат данных ячейки (JSON, XML, SQL, Plain text) или предоставлять переключатель формата в шапке панели.
3. Сохранить производительность для больших документов (до 1-5 МБ).

### Acceptance Criteria
- [ ] JSON-структуры отображаются с подсветкой ключей, строк и чисел.
- [ ] XML-документы отображаются с подсветкой тегов и атрибутов.
- [ ] Цвета токенов адаптируются под темную и светлую тему Querya.

---

## [DG-09](https://github.com/QueryaHub/Querya-Desktop/issues/572) (#572) — XML / HTML Formatter and Validator in Value Panel

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** C  
**Depends on:** none

### Goal
Добавить кнопки форматирования (pretty-print) и валидации для XML и HTML контента в `DataGridValuePanel` аналогично существующему форматированию JSON.

### Context
В `DataGridValuePanel` есть кнопки `Format JSON` и `Minify`. Для XML-данных (SOAP-ответы, конфигурации) таких инструментов нет.

### Implementation
1. Создать легковесный утилитный класс `XmlFormatter`:
   - Автоматическая расстановка отступов (indent = 2 пробела).
   - Минификация XML (удаление лишних пробелов между тегами).
   - Базовая валидация закрытия тегов с подсветкой строки с ошибкой.
2. Добавить в тулбар панели кнопку `Format XML` / `Format Document`, которая автоматически определяет JSON или XML и форматирует его.

### Acceptance Criteria
- [ ] Неформатированный XML аккуратно разбивается по строкам с отступами.
- [ ] При синтаксической ошибке в XML выводится понятное сообщение без сбоя UI.

---

## [DG-10](https://github.com/QueryaHub/Querya-Desktop/issues/573) (#573) — Advanced Selection Calculations (Median, Distinct Count, Copy Stats)

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** C  
**Depends on:** none

### Goal
Расширить `GridSelectionCalcEngine` и `DataGridCalcBar` дополнительными статистическими метриками и возможностью копирования сводки.

### Context
Сейчас `GridSelectionCalcEngine` считает: `Count`, `NULLs`, `Sum`, `Avg`, `Min`, `Max`. Пользователям часто требуются `Distinct Count` (количество уникальных значений) и `Median`.

### Implementation
1. В `lib/features/main_screen/grid_selection_calc_engine.dart`:
   - Добавить расчет `distinctCount` (Set размер).
   - Добавить расчет `median` (для числовых рядов).
2. В `DataGridCalcBar`:
   - Добавить бейдж `Distinct: X`.
   - Добавить бейдж `Median: Y` (если выделено >= 2 чисел).
   - Добавить кнопку контекстного меню / копирования полной сводки: `Copy All Stats (Summary)`.

### Acceptance Criteria
- [ ] При выделении смешанных строк или чисел корректно вычисляется количество уникальных значений.
- [ ] Для числовых значений корректно вычисляется медиана.
- [ ] При клике на "Copy All Stats" в буфер копируется форматированный текст со всеми метриками.

---

# Epic D: Groupings & Pivot View

## [DG-11](https://github.com/QueryaHub/Querya-Desktop/issues/574) (#574) — Multi-Column Hierarchical Grouping (Nested Group By)

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** D  
**Depends on:** none

### Goal
Реализовать многоуровневую группировку по двум и более колонкам в `DataGridGroupingsView` (например `Group by: Department → Job Title`).

### Context
Сейчас `GridGroupingsEngine` поддерживает выбор только одной колонки. В аналитических сценариях требуется строить вложенные деревья групп.

### Implementation
1. В `lib/features/main_screen/grid_groupings_engine.dart`:
   - Обновить `buildGroups` для поддержки списка индексов колонок `List<int> colIndices`.
   - Рекурсивная структура `GroupedCategory`: поле `List<GroupedCategory>? subGroups`.
2. В `lib/features/main_screen/data_grid_groupings_view.dart`:
   - Тулбар с возможностью добавления нескольких чипов колонок (Add Grouping Column).
   - Рекурсивное отображение дерева аккордеонов с уровнями вложенности.
   - Кнопки *Expand All* / *Collapse All*.

### Acceptance Criteria
- [ ] Пользователь может выбрать 2+ колонки для группировки.
- [ ] Вложенные группы корректно раскрываются с отображением строк нижнего уровня.
- [ ] Проценты и количества рассчитываются как для родительских, так и для дочерних групп.

---

## [DG-12](https://github.com/QueryaHub/Querya-Desktop/issues/575) (#575) — Custom Aggregations in Groupings (SUM, AVG, MIN, MAX over columns)

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** D  
**Depends on:** DG-11

### Goal
Позволить пользователю выбирать числовую колонку и агрегатную функцию (`SUM`, `AVG`, `MIN`, `MAX`) для расчета показателей внутри каждой группы.

### Context
Сейчас группировка отображает только количество записей (`X rows, Y%`). Для аналитики важно видеть, например, `SUM(salary)` или `AVG(duration)` по группам.

### Implementation
1. Добавить селекторы в тулбар группировки:
   - Выпадающий список выбора функции агрегации: `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`.
   - Выпадающий список выбора целевой числовой колонки для агрегации.
2. В `GroupedCategory` сохранять вычисленное значение агрегата.
3. Отображать агрегат рядом с количеством строк в заголовке группы (например: `Engineering — 42 rows | Sum(salary): $350,000`).

### Acceptance Criteria
- [ ] При выборе `SUM(amount)` для каждой группы рассчитывается точная сумма.
- [ ] Корректно обрабатываются `NULL` и нечисловые значения (игнорируются).
- [ ] Значения форматируются с учетом разрядов чисел.

---

## [DG-13](https://github.com/QueryaHub/Querya-Desktop/issues/576) (#576) — Sort Groups by Column Key, Count or Aggregate Value & Export Pivot

**Labels:** `data-grid`, `frontend`, `ux`  
**Epic:** D  
**Depends on:** DG-12

### Goal
Добавить сортировку сформированных групп (по имени группы А-Я / Я-А, по количеству строк, по значению агрегата) и экспорт сводной таблицы в CSV / JSON.

### Context
Сейчас группы всегда сортируются только по количеству записей по убыванию (`count desc`). Пользователям требуется алфавитный порядок категорий или экспорт полученного отчета.

### Implementation
1. Добавить контролы сортировки групп: `Order by: Count ↓ / Count ↑ / Key A-Z / Key Z-A / Agg Value ↓`.
2. Добавить кнопку *Export Groupings* в форматы CSV, JSON, Markdown Table.

### Acceptance Criteria
- [ ] Группы мгновенно пересортировываются при изменении порядка сортировки.
- [ ] Экспорт формирует корректный файл со структурой сводной таблицы.

---

# Epic E: UI Hardening, UX Polish & Regression Tests

## [DG-14](https://github.com/QueryaHub/Querya-Desktop/issues/577) (#577) — Fix ResultsTab Header Horizontal Overflow on Narrow Viewports

**Labels:** `data-grid`, `frontend`, `bug`  
**Epic:** E  
**Depends on:** none

### Goal
Устранить ошибку `RenderFlex overflowed` в тулбаре `ResultsTab` на компактных окнах или экранах с низким разрешением.

### Context
При запуске `flutter test test/features/main_screen/results_tab_test.dart` на фиксированной ширине 800px тулбар с переключателем режимов `SegmentedButton`, статусной строкой, кнопками фильтра, инспектора и меню экспорта вызывает горизонтальный оверфлоу (`overflowed by 105 pixels`).

### Implementation
1. В `lib/features/main_screen/results_tab.dart` (строка ~162):
   - Обернуть `material.Row` тулбара экспорта и селектора в `material.SingleChildScrollView(scrollDirection: material.Axis.horizontal)` или использовать адаптивный flex layout с `material.Flexible`.
   - Настроить плотность `VisualDensity.compact` для тулбарных контролов.
2. Проверить прохождение всех тестов в `test/features/main_screen/results_tab_test.dart`.

### Acceptance Criteria
- [ ] Все тесты в `results_tab_test.dart` проходят без ошибок и предупреждений `RenderFlex overflowed`.
- [ ] Тулбар корректно скроллится или сжимается на узких экранах без графических артефактов.

---

## [DG-15](https://github.com/QueryaHub/Querya-Desktop/issues/578) (#578) — End-to-End Integration Tests for Data Grid Staging and DML Execution

**Labels:** `data-grid`, `tests`  
**Epic:** E  
**Depends on:** DG-01, DG-02, DG-14

### Goal
Написать набор интеграционных тестов для проверки полного цикла: выполнение запроса → редактирование ячейки → добавление строки → удаление строки → сохранение в базу данных (SQLite memory DB / Mock driver).

### Implementation
1. Создать `test/features/main_screen/data_grid_e2e_editing_test.dart`:
   - Тест сквозного сценария редактирования в `SqliteSqlWorkspace` с in-memory базой данных.
   - Тест отката изменений по нажатию *Revert All*.
   - Тест обработки ошибки внешнего ключа или уникальности при сохранении.

### Acceptance Criteria
- [ ] Тесты выполняются в CI без внешних зависимостей.
- [ ] Покрыты сценарии `INSERT`, `UPDATE`, `DELETE` и `ROLLBACK`.

---

## [DG-16](https://github.com/QueryaHub/Querya-Desktop/issues/579) (#579) — Visual Polish & Keyboard Navigation Accessibility Audit

**Labels:** `data-grid`, `frontend`, `ux`, `accessibility`  
**Epic:** E  
**Depends on:** DG-04, DG-08

### Goal
Провести аудит доступности и удобства клавиатурной навигации: фокусные рамки, читаемость цветов в светлой/темной темах, подсказки к кнопкам тулбара.

### Implementation
1. Убедиться, что все интерактивные кнопки Data Grid тулбаров снабжены `tooltip` с указанием горячих клавиш.
2. Проверить контрастность выделения ячеек и строк в высококонтрастных и кастомных JSON-темах.
3. Добавить визуальную индикацию текущего фокуса таблицы при навигации стрелками.

### Acceptance Criteria
- [ ] Все кнопки имеют информативные всплывающие подсказки с хоткеями.
- [ ] Навигация стрелками и выделение ячеек четко видны на всех темах оформления.
