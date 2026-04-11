# План: MySQL / MariaDB по образцу PostgreSQL

Документ описывает текущую реализацию PostgreSQL в Querya Desktop, проверяет каждый пункт плана по MySQL и детализирует рекомендуемые практики, компромиссы и порядок работ.

---

## Содержание

1. [Актуальная архитектура PostgreSQL в проекте](#1-актуальная-архитектура-postgresql-в-проекте)
2. [Выбор клиентской библиотеки Dart](#2-выбор-клиентской-библиотеки-dart)
3. [Слой `MysqlConnection`](#3-слой-mysqlconnection)
4. [Пул, сервис, жизненный цикл](#4-пул-сервис-жизненный-цикл)
5. [Форма подключения и `ConnectionRow`](#5-форма-подключения-и-connectionrow)
6. [Интеграция в панель соединений и главный экран](#6-интеграция-в-панель-соединений-и-главный-экран)
7. [Завершение приложения и отмена запросов](#7-завершение-приложения-и-отмена-запросов)
8. [Функциональность UI: дерево, SQL, просмотр данных](#8-функциональность-ui-дерево-sql-просмотр-данных)
9. [Настройки, тесты, безопасность](#9-настройки-тесты-безопасность)
10. [Документация и статус драйвера](#10-документация-и-статус-драйвера)
11. [Поэтапный roadmap](#11-поэтапный-roadmap)

---

## 1. Актуальная архитектура PostgreSQL в проекте

Ниже — «эталон», от которого логично отталкиваться для MySQL.

### 1.1 Зависимости

| Что | Где | Заметка |
|-----|-----|---------|
| Пакет `postgres` | `pubspec.yaml` | Протокол PostgreSQL на чистом Dart, без FFI-плагинов для драйвера. |

### 1.2 Соединение

**Файл:** `lib/core/database/postgres_connection.dart`

- **Конфигурация:** `PostgresConnection` и `PostgresConnection.fromConnectionRow` читают `ConnectionRow`: `host`, `port`, `username`, `password`, `databaseName`, `useSSL`, `connectionString`.
- **Два режима входа:** (1) отдельные поля + `Connection.open(endpoint, settings)`; (2) непустой `connectionString` — разбор URI, подмена имени БД через `replaceDatabaseInConnectionString`, чтобы пул мог открывать разные каталоги без дублирования учётных данных.
- **Параметры сессии:** `setSessionReadOnly` — `SET default_transaction_read_only` (важно для разделения «браузер / только чтение» и «SQL-редактор с записями»).
- **Таймауты:** в `ConnectionSettings` заданы `connectTimeout` и `queryTimeout`; отдельно `execute(..., timeout: ...)` для отдельных запросов.
- **Метаданные:** большой набор методов (`listDatabases`, `listSchemas`, `listTables`, `serverStats`, привилегии, индексы, …) — для MySQL понадобится **свой** слой запросов, а не копипаста SQL от PostgreSQL.

### 1.3 Пул и сервис

**Файлы:** `lib/core/database/postgres_connection_pool.dart`, `postgres_service.dart`

- **Ключ пула:** строка вида `` `${id}::$database::${mode.name}` `` — см. `keyFor` в пуле.
- **Режимы:** `PgSessionMode.readOnly` / `readWrite`; при повторном `acquire` переоткрытие и повторная установка read-only, если сессия отвалилась.
- **Lease:** `PgLease` с `release()` — счётчик ссылок, таймер простоя `idleDisposeDelay`, LRU-вытеснение при `maxEntries`.
- **Прерывание:** `interrupt` → `forceClose` на сокете (отмена клиентского I/O; сервер может ещё какое-то время держать запрос).
- **Синглтон:** `PostgresService.instance` — единая точка для UI.

### 1.4 Локальное хранилище

**Файл:** `lib/core/storage/local_db.dart`

- Таблица `connections` уже содержит все нужные поля для SQL-драйверов: `host`, `port`, `username`, `password`, `database_name`, `use_ssl`, `connection_string`.
- Тип задаётся строкой: для PG — `'postgresql'`. Для MySQL — **`'mysql'`** (уже используется в `new_connection_dialog.dart` / иконках).

### 1.5 UI

- **Форма:** `lib/features/postgresql/postgresql_connection_form.dart` — тест соединения перед сохранением, валидация URI vs host/db.
- **Браузер:** `lib/features/connections/connections_panel.dart` — `_PostgresConnectionTile`, вызовы `PostgresService.instance.acquire`, разворачиваемое дерево.
- **Рабочая область:** каталог `lib/features/postgresql/` (`postgres_sql_workspace.dart`, `postgres_table_view.dart`, `postgres_workspace_home.dart`, …).
- **Таймаут SQL-редактора:** `AppSettings.getPostgresSqlStmtTimeoutSeconds()` используется в `postgres_sql_workspace.dart` — для MySQL разумно завести **отдельный** ключ настроек (см. раздел 9).

### 1.6 Завершение работы

**Файл:** `lib/app/app_shutdown.dart` — `disconnectAllExternalServices()` вызывает `PostgresService.instance.disconnectAll()` наряду с Mongo и Redis.

### 1.7 Заглушки и драйвер-менеджер

- **Stub:** в `connections_panel.dart` удаляются записи с `type == 'mysql' && name == 'MySQL connection'`.
- **Driver Manager:** `lib/features/connections/driver_manager_dialog.dart` — у MySQL `fixedStatus: DriverStatus.comingSoon`, без `DownloadableDriver`.

---

## 2. Выбор клиентской библиотеки Dart

**Проверка пункта плана:** зависимость должна закрыть протокол MySQL, желательно на чистом Dart (как `postgres`), с поддержкой desktop (Linux/macOS/Windows).

### 2.1 Критерии выбора

1. **Лицензия** — совместимость с продуктом (BSD/MIT/Apache предпочтительно; читать полный текст).
2. **Активность** — последние релизы, совместимость с Dart 3.x.
3. **TLS** — возможность включить шифрование; для продакшена желательно проверка сертификата (хотя бы опционально `badCertificateCallback` только для dev).
4. **Аутентификация** — MySQL 8 по умолчанию `caching_sha2_password`; убедиться, что пакет её поддерживает или документировать ограничение + `mysql_native_password` на сервере.
5. **Кодировка** — явная установка `utf8mb4` на соединении (по умолчанию на многих серверах уже так; лучше зафиксировать в коде после handshake).
6. **API** — потоковый доступ к результатам для больших выборок; параметризованные запросы для метаданных и пользовательского SQL, где это уместно.

### 2.2 Типичные кандидаты (на момент планирования)

| Пакет | Плюсы | На что смотреть |
|-------|--------|-----------------|
| **`mysql_client`** | Современный async API, ориентация на чистый Dart | Документация по SSL, ограничения по платформам |
| **`mysql1`** | Долго в экосистеме, много примеров | Актуальность под Dart 3, API может быть менее удобным |

**Практика:** после выбора пакета зафиксировать в `README` или в этом документе **версию** и известные ограничения (например, «не поддерживается X»).

### 2.3 Что не забыть в `pubspec`

- Зависимость только в `dependencies` (не дублировать конфликтующие транспорты).
- При необходимости — отдельная секция в документации про **MariaDB** (обычно тот же протокол с мелкими отличиями в `information_schema`).

---

## 3. Слой `MysqlConnection`

**Проверка пункта плана:** один класс (или небольшой модуль), инкапсулирующий низкоуровневый клиент и дающий приложению стабильный API, похожий на `PostgresConnection`.

### 3.1 Конфигурация из `ConnectionRow`

- Повторить паттерн `fromConnectionRow` с дефолтами: порт **3306**, имя БД по умолчанию можно оставить пустым только если библиотека позволяет подключаться без default schema — иначе требовать явную БД или `mysql` / первую доступную после `SHOW DATABASES`.
- **URI:** распространённые формы `mysql://user:pass@host:3306/db?ssl-mode=REQUIRED`. Реализовать:
  - разбор query-параметров (`ssl`, `ssl-mode`, таймауты, если поддерживаются);
  - функцию уровня `replaceDatabaseInMysqlConnectionString` (аналог PG), если дерево переключает каталоги на одном сохранённом URI.

### 3.2 Методы жизненного цикла

| Метод | Назначение |
|-------|------------|
| `connect()` | Установить соединение, применить session defaults (charset, timezone — опционально). |
| `disconnect()` | Мягкое закрытие. |
| `forceClose()` | Аналог PG: оборвать сокет для `interrupt` из пула. |

### 3.3 Выполнение SQL

- Единая точка `execute` / `query` с опциональным **таймаутом** на уровне приложения (таймер Future + отмена — если библиотека не поддерживает отмену нативно).
- Для **пользовательского SQL** из редактора — не подмешивать автоматически `LIMIT` без явного согласия пользователя; для **просмотра таблицы** — пагинация `LIMIT/OFFSET` или keyset (лучше для больших таблиц).

### 3.4 Метаданные (MySQL-специфика)

В MySQL **DATABASE и SCHEMA — синонимы**; «схема» в смысле PostgreSQL часто соответствует **отдельной базе данных**. Для дерева типичны два UX:

1. **Одна БД на подключение** (как в многих клиентах): в форме задаётся default database, дерево показывает таблицы/вью внутри неё.
2. **Серверный уровень:** сначала `SHOW DATABASES` / `information_schema.SCHEMATA`, затем при выборе БД — переключение `USE db` или отдельное соединение с этой БД (второе согласуется с текущим пулом по ключу `database`).

Рекомендуемые запросы каталога (с параметрами, не конкатенацией строк для имён из БД):

- Список БД: `SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE ...` (исключить `information_schema`, `mysql`, `performance_schema`, `sys` — опционально, в настройках).
- Таблицы: `information_schema.TABLES` с фильтром `TABLE_SCHEMA = ?`.
- Колонки: `information_schema.COLUMNS`.
- Ограничения / индексы: `information_schema.STATISTICS`, `TABLE_CONSTRAINTS`, при необходимости `SHOW CREATE TABLE` для точного DDL.

**Квотирование идентификаторов:** обратные апострофы `` `identifier` ``; экранирование `` ` `` как `` `` ` ``.

### 3.5 Read-only сессия

- В MySQL нет прямого аналога `default_transaction_read_only` на всю сессию как в PG.
- Практики:
  - **`SET SESSION TRANSACTION READ ONLY`** — влияет на последующие транзакции в режимах, где это поддерживается; уточнить для целевых версий MySQL/MariaDB.
  - Альтернатива для «безопасного браузера»: отдельный пользователь БД с правами только `SELECT` (политика на стороне сервера) — вне scope клиента, но стоит упомянуть в документации.
- Для первой версии клиента можно **дублировать семантику PG**: после `connect` выставлять read-only флаг там, где сервер позволяет, а для SQL-редактора — режим `readWrite` без этих SET.

### 3.6 Ошибки

- Обернуть ошибки драйвера в свой тип (как `PostgresConnectionException`), чтобы UI показывал понятные сообщения и мог классифицировать «сеть / доступ / синтаксис».

---

## 4. Пул, сервис, жизненный цикл

**Проверка пункта плана:** повторить паттерн `PostgresConnectionPool` / `PostgresService`.

### 4.1 Структура

- **`MysqlSessionMode`** — `readOnly` / `readWrite` (зеркало `PgSessionMode`).
- **`MysqlLease`** — `release()` с тем же ref-count и idle-таймером.
- **`MysqlConnectionPool`** — те же константы `defaultIdleDisposeDelay`, `defaultMaxEntries`, та же логика `keyFor`, `_evictIfNeededBeforeNewSlot`, `interrupt`, `disconnectAll`.

### 4.2 Фабрика подключения

- Вынести `createAndConnect` в тестируемую функцию (как `_defaultCreateAndConnect` в `postgres_service.dart`), чтобы в unit-тестах подставлять mock.

### 4.3 DRY (не обязательно в первой итерации)

- Долгосрочно можно обобщить «пул по ключу» в generic, если MySQL и PG пулы окажутся идентичны по логике; **не усложнять преждевременно** — сначала два явных класса проще сопровождать.

---

## 5. Форма подключения и `ConnectionRow`

**Файл-образец:** `lib/features/postgresql/postgresql_connection_form.dart`

### 5.1 Поля UI

- Имя подключения, хост, порт (3306), пользователь, пароль, имя БД (опционально в зависимости от выбранного UX), чекбокс SSL, опционально поле **Connection URL**.
- **Тест соединения** перед сохранением — обязателен для согласованности с PG.
- Маскирование пароля, опция «показать пароль».

### 5.2 Валидация

- URI: префиксы `mysql://`, `mariadb://` (если поддерживаете оба в одной форме).
- Без URI: обязательны хост и (по политике) база.

### 5.3 Сохранение

- `ConnectionRow(type: 'mysql', ...)`, `createdAt` — как у других форм.
- Пароль хранится в том же SQLite, что и для PG/Mongo — **как и сейчас в приложении**; для усиленной безопасности в будущем рассмотреть keyring OS (отдельная задача).

---

## 6. Интеграция в панель соединений и главный экран

**Проверка пункта плана:** `connections_panel.dart`, `main_screen.dart`, `workspace_panel.dart`.

### 6.1 `connections_panel.dart`

- В `_createConnection` добавить ветку `ConnectionType.mysql` → `showMysqlConnectionForm(...)`.
- Добавить `_MysqlConnectionTile` по аналогии с `_PostgresConnectionTile`: раскрытие, индикатор загрузки, `MysqlService.instance.acquire` при обходе дерева.
- **Колбэки:** либо расширить существующие (`onPostgresObjectSelected` можно обобщить до SQL-объектов), либо ввести `onMysqlObjectSelected` — решение за командой; важно не раздувать `main_screen` бесконечными флагами — лучше единый контракт «SQL workspace target» с полем `engine: postgresql | mysql`.

### 6.2 Главный экран и workspace

- В `workspace_panel.dart` / `main_screen.dart` сейчас завязка на PostgreSQL (`postgresSqlTabRequestToken` и т.д.). Для MySQL:
  - либо отдельная вкладка/токен для MySQL SQL;
  - либо одна вкладка «SQL» с выбором активного движка — чище для пользователя, сложнее в состоянии.

### 6.3 Иконки и тип

- Уже есть `'mysql'` в `_iconForType` / `_iconAssetForType` — проверить, что новый тайл использует те же ключи.

---

## 7. Завершение приложения и отмена запросов

**Файл:** `lib/app/app_shutdown.dart`

- Добавить `await MysqlService.instance.disconnectAll()` в `disconnectAllExternalServices()` **в том же порядке**, что и остальные пулы (после или перед — главное, документировать идемпотентность).

### 7.1 Отмена долгого запроса

- **Клиент:** `forceClose` на пуле (уже есть паттерн).
- **Сервер (опционально, продвинуто):** выполнить `KILL QUERY` для другого thread_id нельзя без отдельного соединения с привилегией; для desktop-клиента обычно достаточно обрыва сокета. Если добавите «Отменить запрос» как в некоторых IDE — понадобится хранить `connection_id` из `SELECT CONNECTION_ID()` и второе соединение с правами — **отложить на v2**.

---

## 8. Функциональность UI: дерево, SQL, просмотр данных

**Ориентир:** каталог `lib/features/postgresql/`.

### 8.1 Минимально жизнеспособный продукт (MVP)

1. Подключение + тест.
2. Дерево: базы (или одна база) → таблицы → открыть таблицу.
3. Просмотр данных: сетка с пагинацией, только `SELECT` с квотированием имён.
4. SQL-редактор: выполнение произвольного запроса, отображение результата / сообщения об ошибке, таймаут из настроек.

### 8.2 Паритет с PostgreSQL (позже)

- Представления, процедуры/функции, индексы, привилегии — по отдельным экранам, с SQL, специфичным для MySQL.
- Статистика сервера — другие системные таблицы (`performance_schema`, `SHOW GLOBAL STATUS`), осторожно с нагрузкой на сервер.

### 8.3 Защита от опасных запросов в браузере

- В PG уже есть паттерны вроде проверок допустимости SELECT для просмотра таблицы — для MySQL аналогично: в read-only режиме не отправлять произвольный DML из «безопасного» UI без подтверждения.

---

## 9. Настройки, тесты, безопасность

### 9.1 Настройки

- Зеркало `AppSettingsKeys.postgresSqlStmtTimeoutSeconds` → например `mysql_sql_stmt_timeout_seconds`.
- Опционально: лимит строк в результате, таймаут подключения в UI (если вынесете из кода).

### 9.2 Тесты

| Уровень | Что |
|---------|-----|
| Unit | Парсинг connection string, квотирование идентификаторов, ключ пула. |
| Widget | Форма MySQL (как `postgresql_connection_form_test.dart`). |
| Интеграция | Docker `mysql:8` в CI или локально — один тест «подключился и `SELECT 1`». |

### 9.3 Безопасность

- Все **динамические имена** объектов из каталога — только через квотирование или параметры (имена схем/таблиц в MySQL нельзя биндить как `?` везде — использовать whitelist после `information_schema`).
- Не логировать пароли и полные URI с паролем.
- TLS: для production включать проверку сертификата; self-signed только с явным флагом «доверять» или импортом CA.

---

## 10. Документация и статус драйвера

- **`driver_manager_dialog.dart`:** заменить `comingSoon` на `installed` или `available`, когда функциональность готова; при необходимости добавить `DownloadableDriver.mysql`, если появится отдельный артефакт (сейчас PG тянется отдельно — следовать той же модели, если она актуальна для MySQL).
- **`README.md`:** кратко описать поддерживаемые версии MySQL/MariaDB и ограничения драйвера.

---

## 11. Поэтапный roadmap

| Фаза | Содержание |
|------|------------|
| **A** | Зависимость, `MysqlConnection`, тест `SELECT 1`, форма, сохранение в SQLite. |
| **B** | `MysqlConnectionPool`, `MysqlService`, `app_shutdown`, тайл в панели, простое дерево БД/таблиц. |
| **C** | Просмотр таблицы + SQL workspace + настройки таймаута. |
| **D** | Расширенные объекты (вью, процедуры), привилегии, полировка UX, интеграционные тесты. |

---

## Файлы-ориентиры в репозитории

| Назначение | PostgreSQL (эталон) |
|------------|---------------------|
| Соединение | `lib/core/database/postgres_connection.dart` |
| Пул | `lib/core/database/postgres_connection_pool.dart` |
| Сервис | `lib/core/database/postgres_service.dart` |
| Форма | `lib/features/postgresql/postgresql_connection_form.dart` |
| Панель | `lib/features/connections/connections_panel.dart` |
| Выход | `lib/app/app_shutdown.dart` |
| Настройки SQL | `lib/core/storage/app_settings.dart`, `lib/features/postgresql/postgres_sql_workspace.dart` |
| Драйверы UI | `lib/features/connections/driver_manager_dialog.dart` |

---

*Документ можно обновлять по мере реализации: зафиксировать выбранный пакет, версии MySQL/MariaDB в CI и отклонения от этого плана.*
