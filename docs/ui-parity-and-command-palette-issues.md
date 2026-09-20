# GitHub Issues: Консистентность UI рабочих областей и Командная палитра (Command Palette)

Формат ниже рассчитан на перенос в GitHub / GitLab Issues или трекер задач (Linear, Jira). Задачи разбиты на два ключевых направления:
1. **Эпик A: UI Parity & Workspace Coherence** — приведение всех СУБД-экранов к единому стандарту, унификация табов и внедрение строки состояния (Status Bar).
2. **Эпик B: Command Palette & Quick Switcher** — внедрение клавиатурно-ориентированной навигации (Obsidian / VS Code style) для мгновенного выполнения команд и поиска таблиц/схем.

---

## Labels

- `ui`
- `ux`
- `command-palette`
- `parity`
- `workspace`
- `frontend`
- `accessibility`
- `tests`

---

## Milestones / Epics

- **Epic A — Workspace & Driver UI Parity (Консистентность экранов СУБД)**
  - `UI-01`: Унификация переключателей рабочих областей через `QueryaTabStrip`
  - `UI-02`: Стандартизация именования вкладок и навигации (`Overview` vs `SQL`)
  - `UI-03`: Поддержка 1-Click Return to Object во всех драйверах
  - `UI-04`: Создание нижнего статус-бара (`QueryaStatusBar`) и разгрузка TitleBar
  - `UI-05`: Иерархические направляющие и оптимизация отступов в дереве `ConnectionsPanel`

- **Epic B — Command Palette & Quick Switcher (Командная палитра)**
  - `CP-01`: Архитектура реестра команд приложения (`QueryaCommandRegistry`)
  - `CP-02`: UI модального окна командной палитры (`CommandPaletteDialog`, `Ctrl/Cmd+P`)
  - `CP-03`: Quick Switcher объектов базы данных (`Ctrl/Cmd+O` / `Ctrl/Cmd+K`)
  - `CP-04`: Связывание команд с `SqlEditorCommandBridge`, TitleBar и Shortcuts
  - `CP-05`: Регистрация команд из манифестов расширений (Extensions SDK Command Contribution)

---

# Epic A — Workspace & Driver UI Parity

## UI-01 — Унификация таб-баров рабочих областей через QueryaTabStrip

**Labels:** `ui`, `parity`, `workspace`, `frontend`  
**Epic:** A  
**Depends on:** none

### Goal
Заменить разнородные и рукописные реализации переключения вкладок на единый компонент `QueryaTabStrip` во всех рабочих пространствах СУБД.

### Context
- В `PostgresWorkspaceHome` и `MysqlWorkspaceHome` используется стандартный `QueryaTabStrip`.
- В `ExtensionWorkspaceHome` табы `Server` и `SQL` сверстаны вручную через `material.AnimatedContainer` со своим стилем, hover-эффектами и отступами.
- Это приводит к визуальному дрейфу, разному поведению при изменении тем и рассинхрону анимаций `QueryaMotion`.

### Implementation
1. В `lib/features/extensions/extension_workspace_home.dart`:
   - Заменить блок `...List.generate(2, (i) { ... })` в строках 100–131 на `QueryaTabStrip`.
   - Подключить `selectedIndex: _tab` и `onSelected: (index) => unawaited(_selectTab(index))`.
2. Проверить `SqliteWorkspaceHome` на использование токенов `QueryaTabStrip`.
3. Добавить в `test/features/extensions/extension_workspace_home_test.dart` тест на корректный рендеринг `QueryaTabStrip` и переключение вкладок.

### Acceptance Criteria
- [ ] `ExtensionWorkspaceHome` использует `QueryaTabStrip` без кастомного дублирования кода.
- [ ] Вкладки корректно меняют темы и используют токены `context.workbench`.
- [ ] Юнит- и виджет-тесты проходят без регрессий.

---

## UI-02 — Стандартизация именования вкладок и навигации (Parity Standard)

**Labels:** `ui`, `ux`, `parity`  
**Epic:** A  
**Depends on:** `UI-01`

### Goal
Привести текстовые метрики и структуру вкладок рабочих областей всех драйверов к единому словарю: **`Overview`** (сводка/метрики) и **`SQL`** (консоль запросов).

### Context
- PostgreSQL и MySQL используют метку `Server`.
- SQLite использует метку `Overview` (так как локальный файл — это не сервер).
- Extensions используют `Server` даже для встроенных файловых баз (например, DuckDB/LibSQL).
- Разнобой терминов сбивает пользователей при переключении между вкладками.

### Implementation
1. Стандартизировать названия вкладок первого уровня:
   - Если драйвер серверный (PostgreSQL, MySQL): `Overview` (или `Server Stats` с тултипом) / `SQL`.
   - Рекомендуемый общий стандарт для всех: `Overview` и `SQL`.
2. Обновить:
   - `lib/features/postgresql/postgres_workspace_home.dart`
   - `lib/features/mysql/mysql_workspace_home.dart`
   - `lib/features/extensions/extension_workspace_home.dart`
   - `lib/features/sqlite/sqlite_workspace_home.dart`
3. Обновить текстовые ожидания в тестах (`find.text('Server')` → `find.text('Overview')`).

### Acceptance Criteria
- [ ] Во всех реляционных и плагинных СУБД верхние табы именуются единообразно: `Overview` и `SQL`.
- [ ] Соответствующие тесты обновлены и успешно выполняются.

---

## UI-03 — Поддержка 1-Click Return to Object во всех драйверах

**Labels:** `ui`, `ux`, `workspace`  
**Epic:** A  
**Depends on:** `UI-02`

### Goal
Реализовать кнопку быстрого возврата к последней открытой таблице/представлению (`Return to <object_name>`) для драйверов расширений (`ExtensionWorkspaceHome`), MongoDB и Redis.

### Context
- В `PostgresWorkspaceHome`, `MysqlWorkspaceHome` и `SqliteWorkspaceHome` реализован удобный паттерн: если пользователь перешел с таблицы в корень соединения (SQL или Server Stats), в шапке появляется кнопка `Return to users` со значком таблицы, позволяющая в один клик вернуться к данным.
- В `ExtensionWorkspaceHome` и NoSQL данный механизм отсутствует, из-за чего пользователю приходится заново раскрывать дерево в сайдбаре.

### Implementation
1. В `lib/features/extensions/extension_workspace_home.dart`:
   - Добавить параметры `lastSelectedObject` и `onRestoreLastSelectedObject`.
   - Встроить кнопку `OutlineButton(leading: Icon(Icons.table_chart_outlined), child: Text('Return to ${widget.lastSelectedObject!.name}'))`.
2. В `lib/features/main_screen/workspace_panel.dart` пробросить запомненный `lastSelectedExtensionObject`.
3. Добавить аналогичную кнопку быстрого возврата для MongoDB коллекций в `MongoStatsView`.

### Acceptance Criteria
- [ ] При переходе из таблицы стороннего драйвера в корень базы отображается кнопка возврата.
- [ ] Нажатие восстанавливает просмотр таблицы и её состояние.

---

## UI-04 — Создание нижнего статус-бара (QueryaStatusBar) и разгрузка TitleBar

**Labels:** `ui`, `ux`, `workspace`, `frontend`  
**Epic:** A  
**Depends on:** none

### Goal
Разгрузить верхний `QueryaWindowTitleBar` и создать современный нижний `QueryaStatusBar` по стандарту Obsidian / IDE, отображающий статус соединения, задержку (ping), счетчики строк и состояние транзакции.

### Context
- В текущем интерфейсе `QueryaWindowTitleBar` перегружен меню, кнопками сайдбара, индикаторами `Read-only` и кнопками закрытия.
- Внизу окна отсутствует статус-бар, из-за чего пользователю негде увидеть глобальное состояние (например: `Connected: postgres-prod (12ms)`, `Encoding: UTF-8`, `Autocommit: ON`, `Selected: 12 rows`).

### Implementation
1. Создать `lib/features/main_screen/querya_status_bar.dart`:
   - Фиксированная высота: 26px (масштабируется через `context.scaled`).
   - Фоновый цвет: `context.workbench.surface` с верхней границей `borderSubtle.withValues(alpha: 0.22)`.
   - Левая секция:
     - Индикатор статуса соединения (зеленый / серый dot).
     - Имя активного подключения и драйвер (`postgresql://localhost:5432`).
     - Иконка `Read-only` (замочек), если включен безопасный режим.
   - Центральная секция:
     - Индикатор активных фоновых операций (Spinner при загрузке схемы или выполнении тяжелого запроса).
   - Правая секция:
     - Время выполнения последнего запроса (например: `48 ms`).
     - Количество строк/колонок активного дата-грида (`500 rows, 14 cols`).
     - Кнопка вызова настроек масштаба или переключателя темы.
2. Подключить `QueryaStatusBar` в `lib/features/main_screen/main_screen.dart` в нижней части `WindowBorder`.
3. Убрать избыточный бейдж `QueryaReadOnlyBadge` из правого угла `QueryaWindowTitleBar` (оставив индикатор в статус-баре).

### Acceptance Criteria
- [ ] Внизу приложения отображается компактный статус-бар.
- [ ] Статус-бар корректно обновляется при смене соединений, выполнении запросов и смене read-only режима.
- [ ] TitleBar выглядит разгруженным и сбалансированным.

---

## UI-05 — Иерархические направляющие и отступы в ConnectionsPanel

**Labels:** `ui`, `ux`, `accessibility`  
**Epic:** A  
**Depends on:** none

### Goal
Улучшить визуальную читаемость глубоко вложенных деревьев объектов БД (Connection → Database → Schema → Tables → Views → Columns) за счет тонких направляющих линий (indentation guide lines) и сбалансированных отступов.

### Context
- При раскрытии множества схем и папок в `ConnectionsPanel` строки деревьев сливаются по горизонтали, пользователю сложно отследить принадлежность таблицы к схеме.
- Отступ заголовка `SERVERS` (`fromLTRB(20, 24, 16, 12)`) тратит драгоценное вертикальное пространство на небольших экранах ноутбуков.

### Implementation
1. В `lib/features/connections/connections_panel.dart`:
   - Оптимизировать верхний паддинг заголовка `SERVERS`: уменьшить `top: 24` до `top: 12`.
   - Внедрить `QueryaTreeIndentGuide`: тонкие вертикальные полупрозрачные линии (1px `borderSubtle.withValues(alpha: 0.15)`) на каждом уровне отступа `level * 16px`.
2. Стилизовать счетчик найденных элементов в поиске как деликатный chip-бейдж.

### Acceptance Criteria
- [ ] В дереве отображаются деликатные вертикальные направляющие для вложенных узлов.
- [ ] Сайдбар вмещает на 1–2 строки больше за счет оптимизации отступов шапки.

---

# Epic B — Command Palette & Quick Switcher

## CP-01 — Архитектура реестра команд приложения (QueryaCommandRegistry)

**Labels:** `command-palette`, `frontend`, `architecture`  
**Epic:** B  
**Depends on:** none

### Goal
Создать централизованный сервис `QueryaCommandRegistry` для регистрации, управления и фильтрации действий приложения с поддержкой категорий, хоткеев, иконок и предикатов доступности (`isEnabled`).

### Context
- Сейчас действия размазаны по `main_screen.dart` (`_handleGlobalKeyEvent`, `CallbackShortcuts`), `Menubar` в `querya_window_title_bar.dart` и `SqlEditorCommandBridge`.
- Чтобы внедрить Command Palette как в Obsidian или VS Code, необходим единый реестр, знающий обо всех действиях в системе и их текущем статусе (активно / неактивно).

### Implementation
1. Создать `lib/core/actions/querya_command.dart`:
   ```dart
   class QueryaCommand {
     final String id;
     final String title;
     final String? category; // 'Connection', 'SQL', 'View', 'Tools'
     final IconData? icon;
     final String? shortcutLabel; // 'Ctrl+Enter', 'Ctrl+N'
     final bool Function(BuildContext context)? isEnabled;
     final void Function(BuildContext context) execute;
   }
   ```
2. Создать синглтон/сервис `lib/core/actions/querya_command_registry.dart`:
   - Регистрация базовых команд (новое соединение, открыть SQL, запустить запрос, переключить сайдбар, открыть настройки, переключить тему, очистить историю, экспортировать в CSV).
   - Метод `List<QueryaCommand> getAvailableCommands(BuildContext context)`.
   - Поиск по ключевым словам и алиасам (например: запрос `dark` находит команду `Toggle Dark/Light Theme`).
3. Покрыть реестр тестами в `test/core/actions/querya_command_registry_test.dart`.

### Acceptance Criteria
- [ ] `QueryaCommandRegistry` регистрирует системные и контекстные команды.
- [ ] Команды проверяют предикат `isEnabled` (например, `Execute Query` доступен только при активном редакторе).

---

## CP-02 — UI модального окна командной палитры (Ctrl/Cmd+P)

**Labels:** `command-palette`, `ui`, `ux`, `frontend`  
**Epic:** B  
**Depends on:** `CP-01`

### Goal
Разработать всплывающее диалоговое окно Command Palette на базе `shadcn_flutter Command / Dialog`, вызываемое глобальным сочетанием клавиш <kbd>Ctrl+P</kbd> (или <kbd>Cmd+P</kbd> на macOS).

### Context
- Пользователи Obsidian, VS Code и Sublime Text ожидают возможность выполнить любое действие системы без мыши.
- Палитра должна мгновенно открываться, поддерживать навигацию стрелками <kbd>↑</kbd>/<kbd>↓</kbd>, нечеткий поиск (fuzzy search) и закрытие по <kbd>Esc</kbd>.

### Implementation
1. Создать `lib/features/command_palette/command_palette_dialog.dart`:
   - Использовать `shadcn_flutter` компоненты: `Command`, `CommandInput`, `CommandList`, `CommandGroup`, `CommandItem`.
   - Интегрировать анимацию появления через `QueryaFadeSlide`.
   - Отображать категорию серым текстом, иконку действия и бейдж сочетания клавиш справа.
2. В `lib/features/main_screen/main_screen.dart`:
   - Зарегистрировать глобальный шорткат <kbd>Ctrl+P</kbd> / <kbd>Cmd+P</kbd> (а также русскую раскладку <kbd>З</kbd>).
   - Обработчик вызывает `showCommandPalette(context)`.
3. При выборе команды: закрывать диалог и вызывать `command.execute(context)`.

### Acceptance Criteria
- [ ] Нажатие <kbd>Ctrl+P</kbd> / <kbd>Cmd+P</kbd> в любом месте приложения открывает палитру команд.
- [ ] Ввод текста фильтрует команды с подсветкой совпадений.
- [ ] Нажатие <kbd>Enter</kbd> выполняет команду и закрывает палитру; <kbd>Esc</kbd> отменяет выбор.
- [ ] Написаны виджет-тесты в `test/features/command_palette/command_palette_dialog_test.dart`.

---

## CP-03 — Quick Switcher объектов базы данных (Ctrl/Cmd+O / Ctrl+K)

**Labels:** `command-palette`, `ui`, `ux`, `workspace`  
**Epic:** B  
**Depends on:** `CP-02`

### Goal
Создать инструмент быстрого перехода (Quick Switcher) к любой таблице, представлению или сохраненному запросу по сочетанию клавиш <kbd>Ctrl+O</kbd> / <kbd>Cmd+O</kbd> (или <kbd>Ctrl+K</kbd>).

### Context
- В Obsidian <kbd>Ctrl+O</kbd> открывает Quick Switcher заметок.
- В СУБД с сотнями таблиц поиск нужной таблицы в дереве вручную занимает слишком много времени. Быстрый нечеткий поиск по кэшу схемы драматически повышает скорость работы.

### Implementation
1. В `lib/features/command_palette/quick_switcher_dialog.dart`:
   - Источник данных: кэш объектов активного соединения (таблицы, вьюхи, процедуры, коллекции).
   - Элемент списка: имя таблицы, схема/база данных, иконка типа объекта (таблица / вью / коллекция), количество строк (если известно).
2. Действие при выборе:
   - Мгновенно открывает вкладку таблицы в Grid-режиме.
3. Добавить шорткат <kbd>Ctrl+K</kbd> / <kbd>Cmd+K</kbd> (альтернатива: переключение режимов внутри Command Palette через префикс `#` или `@`).

### Acceptance Criteria
- [ ] Пользователь может нажать <kbd>Ctrl+K</kbd>, набрать `users` и нажать <kbd>Enter</kbd> для немедленного перехода к таблице `public.users`.
- [ ] Поиск не блокирует UI-поток при наличии сотен объектов в схеме.

---

## CP-04 — Связывание команд с существующими подсистемами приложения

**Labels:** `command-palette`, `architecture`, `tests`  
**Epic:** B  
**Depends on:** `CP-01`, `CP-02`

### Goal
Связать реестр команд со всеми существующими экшенами и меню (`SqlEditorCommandBridge`, `MainScreenWorkspaceState`, экспорт, управление соединениями).

### Context
- Чтобы палитра не была оторвана от функционала, она должна вызывать те же обработчики, что и пункты верхнего Menubar и кнопки тулбаров.

### Implementation
1. Зарегистрировать в `QueryaCommandRegistry`:
   - **Workspace**: `Toggle Sidebar`, `Close Active Workspace`, `Return to Home`.
   - **Connection**: `New Connection`, `Connect`, `Disconnect`, `Reconnect / Invalidate`, `Toggle Read-Only Mode`.
   - **SQL Editor**: `Execute Query`, `New Query Tab`, `Close Current Tab`, `Format SQL Query`, `Clear Editor`.
   - **Data Grid**: `Toggle Quick Filter`, `Inspect Cell Panel`, `Copy as CSV`, `Copy as JSON`, `Copy as Markdown`, `Save Export File`, `Apply Staged Edits (Save)`.
   - **Application**: `Open Preferences`, `Open Extension Manager`, `Check for Updates`, `Welcome Tour`, `About Querya`.
2. Добавить юнит-тесты на связку реестра и вызовы команд.

### Acceptance Criteria
- [ ] Все ключевые команды приложения доступны через Command Palette.
- [ ] Команды контекстно активны только тогда, когда доступна соответствующая рабочая область.

---

## CP-05 — Регистрация команд из манифестов расширений (Extensions Contribution)

**Labels:** `command-palette`, `extensions`, `architecture`  
**Epic:** B  
**Depends on:** `CP-01`

### Goal
Предоставить сторонним драйверам и плагинам возможность декларировать собственные команды в `manifest.json`, которые автоматически попадают в `QueryaCommandRegistry` и Command Palette.

### Context
- В рамках блоков архитектуры плагинов (Roadmap 0.5.0) расширениям требуется точка входа для пользовательских действий (например, `ClickHouse: Show Cluster Status`, `DuckDB: Export Parquet`).

### Implementation
1. Расширить модель `ExtensionManifest` полем:
   ```json
   "contributes": {
     "commands": [
       {
         "id": "ext.clickhouse.cluster_status",
         "title": "ClickHouse: Show Cluster Status",
         "category": "ClickHouse"
       }
     ]
   }
   ```
2. При активации плагина регистрировать его команды в `QueryaCommandRegistry` с перенаправлением вызова в `PluginRpcBridge`.

### Acceptance Criteria
- [ ] Установленные расширения отображают свои команды в Command Palette.
- [ ] При отключении расширения команды удаляются из реестра.
