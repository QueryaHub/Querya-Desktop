# План реализации парсера кастомных JSON-тем

Исходное ТЗ: [`scheme-parcer.md`](scheme-parcer.md).  
Цель этого документа — разбить работу на маленькие задачи так, чтобы реализация хорошо ложилась на текущую архитектуру Querya и не ухудшала производительность при 50+ темах.

## Текущее состояние

В проекте уже есть большая часть инфраструктуры тем:

- `lib/core/theme/querya_theme.dart` — главный объект темы: `QueryaWorkbenchTheme`, `QueryaEditorTheme`, `ColorScheme`, `tokenColors`.
- `lib/core/theme/theme_controller.dart` — singleton-контроллер темы, кэширует `QueryaTheme`, `ThemeData`, Material theme.
- `lib/core/theme/theme_import_service.dart` — импорт одного VS Code JSON/JSONC файла в app support.
- `lib/core/theme/parser/` — парсинг VS Code colors/tokenColors, JSONC, color parsing.
- `lib/features/settings/preferences_appearance_section.dart` — UI выбора темы и импорта.
- `lib/app/app.dart` — применение темы через `ShadcnApp` и `QueryaThemeScope`.

Поэтому не нужно создавать параллельную систему `ThemeData` с нуля. Лучше добавить новый слой: **реестр тем + парсер кастомного формата**, который на выходе дает существующий `QueryaTheme`.

## Целевая архитектура

```text
themes/*.json / ~/.querya/themes/*.json
        |
        v
ThemeRegistryService
  - сканирует директории
  - хранит легкие manifest-метаданные
  - лениво парсит выбранную тему
        |
        v
QueryaThemeManifestParser
  - custom Querya JSON
  - VS Code JSON/JSONC compatibility
        |
        v
QueryaThemeFactory
  - manifest -> QueryaTheme
  - fallback на QueryaTheme.darkDefault/lightDefault
        |
        v
ThemeController
  - selectedThemeId
  - cache
  - persist в AppSettings/SQLite
        |
        v
ShadcnApp + QueryaThemeScope + bitsdojo window colors
```

## JSON-формат

Поддержать новый формат с версией схемы, но сохранить совместимость с текущим VS Code import.

Минимальная структура:

```json
{
  "schema": "querya.theme.v1",
  "id": "cyberpunk-neon",
  "name": "Cyberpunk Neon",
  "type": "dark",
  "shadcn_colors": {
    "background": "#09090B",
    "foreground": "#F8FAFC",
    "card": "#111113",
    "cardForeground": "#F8FAFC",
    "popover": "#111113",
    "popoverForeground": "#F8FAFC",
    "primary": "#22D3EE",
    "primaryForeground": "#020617",
    "secondary": "#18181B",
    "secondaryForeground": "#F8FAFC",
    "muted": "#18181B",
    "mutedForeground": "#94A3B8",
    "accent": "#27272A",
    "accentForeground": "#F8FAFC",
    "destructive": "#EF4444",
    "destructiveForeground": "#F8FAFC",
    "border": "#27272A",
    "input": "#27272A",
    "ring": "#22D3EE"
  },
  "editor_colors": {
    "background": "#09090B",
    "foreground": "#E5E7EB",
    "selection": "#155E75",
    "lineNumber": "#64748B",
    "bracketMatch": "#164E63",
    "widgetBorder": "#22D3EE",
    "sidebarBackground": "#020617",
    "surface": "#111113",
    "accent": "#22D3EE"
  },
  "tokenColors": []
}
```

Правила:

- `schema`, `id`, `name`, `type` — обязательные.
- `type`: `dark` или `light`.
- Все цвета можно писать как `#RRGGBB`, `RRGGBB`, `#AARRGGBB`, `AARRGGBB`, короткие `#RGB/#RGBA` лучше поддержать только если это уже легко переиспользуется из `parseVsCodeColor`.
- Отсутствующие необязательные ключи добираются из `QueryaTheme.darkDefault` / `QueryaTheme.lightDefault`.
- Неизвестные ключи игнорируются, но в debug можно логировать.
- Поврежденный файл не должен ломать запуск приложения.

## Мини-задачи

### 1. Зафиксировать формат и тестовые fixtures

**Файлы:**

- `docs/theme-parser-implementation-tasks.md`
- `test/fixtures/themes/querya_custom_dark.json`
- `test/fixtures/themes/querya_custom_light.json`
- `test/fixtures/themes/querya_custom_invalid.json`

**Что сделать:**

- Добавить 2 валидных custom JSON темы и 1 битую.
- Описать обязательные/необязательные поля в `docs/theme-import.md` или отдельном `docs/theme-custom-json.md`.
- Явно указать, что текущий VS Code import остается поддержанным.

**Definition of Done:**

- Есть fixtures для dark/light/invalid.
- В документации есть пример структуры и fallback-правила.

### 2. Добавить модели manifest для custom themes

**Файлы:**

- `lib/core/theme/parser/querya_theme_manifest.dart`

**Что сделать:**

- Создать immutable-модель:
  - `QueryaThemeManifest`
  - `QueryaThemeType`
  - `QueryaThemeParseException`
- Поля:
  - `schema`
  - `id`
  - `name`
  - `isDark`
  - `shadcnColors: Map<String, String>`
  - `editorColors: Map<String, String>`
  - `tokenColors: List<TokenColorRule>`
- Метод `fromJsonString(String raw)`.
- Для JSONC использовать существующий `stripJsonc`.

**Производительность:**

- Не создавать `Color`/`ThemeData` на этапе чтения списка тем.
- Manifest-метаданные должны быть легкими.

**Definition of Done:**

- Парсер возвращает manifest без зависимости от Flutter widget layer.
- Ошибки возвращаются контролируемо через exception/result, без краша.

### 3. Унифицировать HEX parsing

**Файлы:**

- `lib/core/theme/parser/color_parser.dart`

**Что сделать:**

- Проверить, покрывает ли `parseVsCodeColor` все нужные форматы.
- Если нет — добавить wrapper:
  - `parseQueryaThemeColor(String raw)`
  - принимает `#RRGGBB`, `RRGGBB`, `#AARRGGBB`, `AARRGGBB`
  - нормализует ошибки в `FormatException`
- Не плодить второй несовместимый парсер.

**Тесты:**

- `test/core/theme/parser/color_parser_test.dart`
- Валидные и невалидные HEX.

**Definition of Done:**

- Все color formats из документации покрыты тестами.
- Invalid color не валит всю тему, если ключ необязательный.

### 4. Маппинг custom manifest -> QueryaTheme

**Файлы:**

- `lib/core/theme/parser/querya_theme_from_manifest.dart`

**Что сделать:**

- Реализовать pure-функцию:

```dart
QueryaTheme queryaThemeFromManifest(QueryaThemeManifest manifest)
```

- Базовый fallback:
  - `manifest.isDark ? QueryaTheme.darkDefault : QueryaTheme.lightDefault`
- `shadcn_colors` маппить в `ColorScheme`.
- `editor_colors` маппить в:
  - `QueryaWorkbenchTheme`
  - `QueryaEditorTheme`
- Для пересечения ключей (`background`, `accent`, `border`) выбрать единый источник:
  - UI/shadcn берет `shadcn_colors`
  - editor/workbench берет `editor_colors`
- `tokenColors` передать в `QueryaTheme.tokenColors`.

**Важно:**

- Не возвращать напрямую `ThemeData`. Внутри приложения единый источник истины — `QueryaTheme`, а `ThemeData` создается через `toShadcnThemeData()`.

**Definition of Done:**

- Custom manifest можно превратить в `QueryaTheme`.
- Missing optional fields берутся из fallback.
- Required missing fields дают controlled failure.

### 5. Результаты парсинга и fallback без крашей

**Файлы:**

- `lib/core/theme/theme_parse_result.dart` или рядом с сервисом

**Что сделать:**

- Ввести result-типы:
  - `ThemeLoadSuccess`
  - `ThemeLoadFailure`
- Для UI показывать failure message.
- Для старта приложения:
  - если выбранная тема сломана/удалена — тихо применить Querya Dark
  - сохранить в лог/debug причину
  - не перезаписывать пользовательские настройки сразу, чтобы файл можно было восстановить

**Definition of Done:**

- Поврежденный JSON не ломает запуск.
- Preferences показывает понятную ошибку при ручном импорте.

### 6. Реестр тем вместо одного imported.json

**Файлы:**

- `lib/core/theme/theme_registry_service.dart`
- `lib/core/theme/theme_definition.dart`

**Что сделать:**

- Добавить `ThemeDefinition`:
  - `id`
  - `name`
  - `source` (`builtin`, `imported`, `filesystem`)
  - `path`
  - `isDark`
  - `format` (`queryaCustom`, `vscode`)
  - `lastModified`
  - `contentHash`
- `ThemeRegistryService.loadThemeDefinitions()`:
  - встроенные темы из `themes/samples/` или будущего `assets/themes/`
  - persisted imported
  - пользовательская папка
- На первом этапе можно не делать asset bundle, а начать с app support + manual import.

**Производительность:**

- Сканирование читает только первые KB/manifest, а не строит `ThemeData`.
- Полный парсинг только при выборе/preview.
- Если 50+ файлов, UI получает список `ThemeDefinition`, а не тяжелые темы.

**Definition of Done:**

- Можно получить список доступных тем.
- Список не парсит каждую тему полностью.

### 7. Кэш parsed theme и ThemeData

**Файлы:**

- `lib/core/theme/theme_controller.dart`
- `lib/core/theme/theme_registry_service.dart`

**Что сделать:**

- Кэшировать минимум:
  - `Map<String, QueryaTheme> _themeCache`
  - `Map<String, ThemeData> _shadcnThemeCache`
- Ключ кэша:
  - `themeId + contentHash + brightness`
- При изменении файла:
  - обновить `contentHash`
  - инвалидировать только эту тему.
- Ограничить кэш, например LRU на 12-20 тем.

**Производительность:**

- Повторное переключение на уже открытую тему не читает файл и не парсит JSON.
- `ThemeController._invalidateThemeCache()` не должен сбрасывать весь registry без причины.

**Definition of Done:**

- Повторный выбор темы мгновенный.
- Тест проверяет, что один и тот же файл не парсится повторно без изменения hash.

### 8. Persist выбранной темы

**Файлы:**

- `lib/core/storage/app_settings.dart`

**Что сделать:**

- Добавить настройки:
  - `theme_selected_id`
  - `theme_selected_source`
  - `theme_selected_path` для filesystem themes
- Для совместимости:
  - текущий `QueryaThemePreset.imported` продолжает работать
  - при наличии old imported theme создать `ThemeDefinition` с id `imported`

**SQLite vs settings key-value:**

- Для выбранной темы достаточно текущего key-value слоя `AppSettings`.
- Для списка импортированных тем лучше отдельная таблица позже:
  - `theme_id`
  - `name`
  - `path`
  - `format`
  - `last_modified`
  - `content_hash`

**Definition of Done:**

- После перезапуска выбранная тема восстанавливается.
- Старые imported themes не ломаются.

### 9. Динамическая папка тем

**Файлы:**

- `lib/core/theme/theme_registry_service.dart`
- `lib/core/theme/theme_paths.dart`

**Что сделать:**

- Определить папку:
  - Linux/macOS: `${appSupport}/themes/`
  - можно дополнительно поддержать `~/.querya/themes/`, но лучше app support как основной путь.
- Методы:
  - `Future<Directory> userThemesDirectory()`
  - `Future<List<File>> scanThemeFiles()`
- Поддержать расширения:
  - `.json`
  - `.jsonc`
- Не использовать watcher на первом этапе. Достаточно кнопки `Refresh themes`.

**Производительность:**

- Сканировать async.
- Не блокировать startup дольше 50-100ms: если файлов много, загрузить built-in/default сразу, список пользовательских тем догрузить после первого кадра.

**Definition of Done:**

- Файлы, добавленные в папку, появляются после refresh/restart.
- Битый файл не ломает список.

### 10. Preferences UI для 50+ тем

**Файлы:**

- `lib/features/settings/preferences_appearance_section.dart`
- `lib/shared/widgets/querya_dropdown.dart`

**Что сделать:**

- Текущий `QueryaDropdown` уже построен на `MenuAnchor`, имеет `menuMaxHeight`.
- Для 50+ тем лучше сделать отдельный `ThemePickerButton`:
  - trigger показывает текущую тему
  - popup max height 300-360px
  - `ListView.builder`
  - scrollbar
  - search/filter по названию
  - source badge: Built-in / Imported / File
- Не строить превью каждой темы в списке.
- Для каждой строки использовать только `ThemeDefinition`.

**Live preview:**

- Hover не должен применять тему ко всему app.
- Если нужен preview:
  - показывать справа маленькую карточку-превью
  - парсить тему debounce 100-150ms
  - не вызывать `ThemeController.setTheme(...)` на hover
- Полное применение — только click/select.

**Definition of Done:**

- 50+ тем открываются без лагов.
- Hover по списку не перестраивает `ShadcnApp`.
- Popup не выходит за экран и скроллится.

### 11. Интеграция в ThemeController

**Файлы:**

- `lib/core/theme/theme_controller.dart`
- `lib/core/theme/querya_theme_preset.dart`

**Что сделать:**

- Не раздувать enum preset под каждую тему.
- Добавить понятие `selectedThemeId`.
- Сохранить старые preset-значения:
  - `queryaDark`
  - `queryaLight`
  - `imported` как legacy/single import
- Новый путь:
  - `ThemeController.loadAvailableThemes()`
  - `ThemeController.setThemeById(String id)`
  - `ThemeController.previewThemeById(String id)` только для preview-card, не для app.
- `activeTheme` должен брать тему из cache/registry.

**Definition of Done:**

- Старые тесты на presets проходят.
- Новые темы выбираются по id.
- Нет полного reparse при каждом rebuild.

### 12. Синхронизация bitsdojo_window

**Файлы:**

- `lib/main.dart`
- место, где настраивается окно/кнопки bitsdojo
- возможно `lib/features/main_screen/main_screen.dart`

**Что сделать:**

- Найти текущую точку отрисовки title bar и window buttons.
- Использовать `QueryaThemeScope.of(context).workbench.canvas/background`.
- Цвет кнопок/hover должен зависеть от текущей темы.
- Не обращаться к `ThemeController.instance.activeTheme` глубоко в виджетах, если можно получить тему из `QueryaThemeScope`.

**Производительность:**

- Title bar должен перестраиваться только при смене темы, не при scale preview/обычных workspace state changes.

**Definition of Done:**

- При смене темы title bar и кнопки окна меняют цвет.
- На hover кнопок нет лишнего app-wide rebuild.

### 13. Built-in themes и packaging

**Файлы:**

- `themes/samples/`
- возможно `assets/themes/`
- `pubspec.yaml`

**Что сделать:**

- Решить, shipped themes — это:
  - dev-only samples (`themes/samples/`)
  - или bundled assets (`assets/themes/`) для пользователей.
- Для релизной функциональности лучше `assets/themes/`.
- Добавить в `pubspec.yaml` assets:

```yaml
flutter:
  assets:
    - assets/themes/
```

- `ThemeRegistryService` должен читать built-in themes через `AssetManifest`.

**Definition of Done:**

- В релизной сборке встроенные темы доступны без файловой системы проекта.
- Samples остаются для docs/tests.

### 14. Тесты парсера и registry

**Файлы:**

- `test/core/theme/querya_theme_manifest_test.dart`
- `test/core/theme/querya_theme_from_manifest_test.dart`
- `test/core/theme/theme_registry_service_test.dart`
- `test/features/settings/theme_picker_test.dart`

**Что покрыть:**

- Валидный dark custom JSON.
- Валидный light custom JSON.
- Missing optional keys fallback.
- Missing required keys failure.
- Invalid HEX skipped/failure по правилам.
- JSONC comments/trailing commas.
- 50 fake definitions в picker без overflow.
- Cache hit: повторный выбор не вызывает parse повторно.
- Broken persisted selected theme falls back to Querya Dark.

**Definition of Done:**

- `flutter analyze` clean.
- `flutter test` green.
- Есть тест на производительный сценарий 50+ themes.

### 15. Миграция текущего imported theme

**Что сделать:**

- При `ThemeController.load()`:
  - если есть старые `theme_import_*` настройки — создать legacy `ThemeDefinition`.
  - `QueryaThemePreset.imported` продолжает работать.
- Не удалять `ThemeImportService` сразу.
- После внедрения registry можно постепенно заменить `ThemeImportService.importFromPath` на `ThemeRegistryService.importTheme`.

**Definition of Done:**

- Пользователь, который уже импортировал VS Code theme, не теряет тему после обновления.

### 16. Документация для пользователей

**Файлы:**

- `docs/theme-import.md`
- новый `docs/theme-custom-json.md`
- `README.md` короткая ссылка при необходимости

**Что описать:**

- Куда класть темы.
- Формат custom JSON.
- Отличие VS Code JSON от Querya custom JSON.
- Как работает fallback.
- Как импортировать через Preferences.

## Рекомендуемый порядок PR

1. **Parser core only**
   - manifest model
   - color parser wrapper
   - manifest -> QueryaTheme
   - fixtures/tests

2. **Registry + cache**
   - `ThemeDefinition`
   - scan app support themes
   - LRU/cache by hash
   - persistence selected id

3. **Preferences UI**
   - theme picker with max height / search / scrollbar
   - no app-wide preview on hover
   - import/refresh folder actions

4. **Built-in assets + docs**
   - package built-in themes
   - docs and samples

5. **Window chrome sync**
   - title bar/window button colors from `QueryaThemeScope`
   - focused tests/manual smoke

## Performance rules

- Никогда не строить `ThemeData` для всех тем при открытии Preferences.
- Не применять тему на hover.
- Не читать все файлы синхронно в `build()`.
- Не хранить `ThemeData` в SQLite; хранить только id/path/hash.
- Полный parse делать async и только для выбранной/preview темы.
- Кэшировать `QueryaTheme` и `ThemeData`.
- Для 50+ тем UI должен работать на `ThemeDefinition`, а не на parsed theme.
- Любая ошибка файла темы должна превращаться в fallback или UI error, но не в crash.

## Acceptance checklist

- [ ] Querya custom JSON импортируется и применяется.
- [ ] VS Code JSON/JSONC import продолжает работать.
- [ ] 50+ тем в Preferences не вызывают overflow и заметные лаги.
- [ ] Hover в списке не перестраивает весь app.
- [ ] Повторное переключение на уже открытую тему мгновенное.
- [ ] Сломанная выбранная тема не ломает запуск приложения.
- [ ] Выбранная тема сохраняется после рестарта.
- [ ] Window title bar синхронизирован с background/canvas темы.
- [ ] `flutter analyze` clean.
- [ ] `flutter test` green.
