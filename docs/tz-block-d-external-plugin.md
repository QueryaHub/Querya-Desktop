# ТЗ Блок D: External Plugin Process (Внешний Плагин)

## 1. Введение и Зона Ответственности
**External Plugin Process (Блок D)** — это независимый исполняемый бинарный файл (или скрипт, обернутый в стартер). Он пишется разработчиком расширения и не зависит от фреймворка Flutter. В контексте баз данных этот процесс играет роль "Прокси-Драйвера".

**Основные задачи:**
1. Поднятие сервера JSON-RPC поверх стандартных потоков (stdin/stdout).
2. Реализация сетевого протокола конкретной БД (TCP, HTTP, gRPC).
3. Маппинг данных (преобразование сырых ответов БД в стандартный формат Querya).
4. Отдача UI-схем (SDUI) по запросу.

---

## 2. Архитектура Плагина-Драйвера (На примере Dart)

Плагин, написанный на Dart, использует ту же библиотеку `json_rpc_2`, но выступает в роли Сервера (`json_rpc_2.Server`), а не Клиента.

**Жизненный цикл обработки запроса:**
1. Чтение команды с `stdin` (например, `{"jsonrpc": "2.0", "method": "db.executeSql", "params": {"query": "SELECT * FROM users"}, "id": 1}`).
2. Выполнение запроса через родной драйвер БД (например, пакет `clickhouse_client` или `mongo_dart`).
3. Запись стандартизованного ответа в `stdout`. Обязательно исключать любой "мусорный" вывод в `stdout` (вроде логов `print`), так как он сломает парсер JSON-RPC на стороне хоста. Все логи (Debug info) должны отправляться либо в `stderr`, либо специальными RPC-событиями (`window/logMessage`).

---

## 3. Стандартизация Данных (Data Mapping)

Поскольку Querya Desktop (Блок A) ничего не знает о специфичных типах данных баз (например, `DateTime64` из ClickHouse или `ObjectId` из MongoDB), плагин **обязан** приводить все типы к общему знаменателю (Standard JSON Types).

**Требования к возвращаемому результату для таблиц:**
```json
{
  "columns": [
    { "name": "id", "type": "integer", "is_primary": true },
    { "name": "created_at", "type": "datetime" },
    { "name": "metadata", "type": "json" }
  ],
  "rows": [
    [ 1, "2026-06-18T05:30:00Z", "{\"key\": \"value\"}" ],
    [ 2, "2026-06-18T05:31:00Z", null ]
  ]
}
```
* **Даты:** Должны отдаваться в стандарте ISO 8601 (строки).
* **Сложные типы (Arrays, Tuples):** Сериализуются в массивы или JSON-строки, чтобы Flutter мог безопасно их отрендерить в ячейках таблицы.
* **Бинарные данные (BLOB):** Отдаются в формате Base64 строки.

---

## 4. Предоставление Extension Points (Схемы UI)

Плагин обязан отвечать на запросы ядра о своих интерфейсах.
- **Метод `extension.getConnectionForm`**: Возвращает JSON с описанием полей (host, port, user, etc.).
- **Метод `extension.getTreeSchema`**: Возвращает первичную структуру бокового меню (например, корневые папки "Databases" и "Users").

Разделение логики: Ядро занимается пикселями и дизайном, Плагин — логикой и структурами данных.

---

## 5. Стандарт мутаций данных (Querya Extension Mutation Standard)

Если плагин поддерживает интерактивное редактирование данных в 2D-таблицах (`ExtensionDriverCapabilities.supportsMutations: true`), он реализует следующие JSON-RPC методы:

### 5.1. `db.getTableSchema`
Возвращает метаданные колонок, признак первичного ключа и возможность `NULL`.
* **Запрос:**
  ```json
  {
    "jsonrpc": "2.0",
    "method": "db.getTableSchema",
    "params": {
      "connectionId": 123,
      "database": "analytics",
      "schema": "public",
      "tableName": "users"
    },
    "id": 4
  }
  ```
* **Ответ:**
  ```json
  {
    "jsonrpc": "2.0",
    "result": {
      "tableName": "users",
      "schema": "public",
      "primaryKeys": ["id"],
      "columns": [
        { "name": "id", "dataType": "integer", "isPrimaryKey": true, "isNullable": false },
        { "name": "email", "dataType": "varchar", "isPrimaryKey": false, "isNullable": true },
        { "name": "age", "dataType": "integer", "isPrimaryKey": false, "isNullable": true }
      ]
    },
    "id": 4
  }
  ```

### 5.2. `db.mutate`
Выполняет атомарный пакет мутаций (вставка, обновление, удаление строк).
* **Запрос:**
  ```json
  {
    "jsonrpc": "2.0",
    "method": "db.mutate",
    "params": {
      "connectionId": 123,
      "database": "analytics",
      "tableName": "users",
      "mutations": [
        {
          "type": "update",
          "where": { "id": "42" },
          "set": { "email": "new_email@domain.com" }
        },
        {
          "type": "insert",
          "values": { "id": "43", "email": "bob@domain.com", "age": "30" }
        },
        {
          "type": "delete",
          "where": { "id": "10" }
        }
      ]
    },
    "id": 5
  }
  ```
* **Ответ:**
  ```json
  {
    "jsonrpc": "2.0",
    "result": {
      "success": true,
      "affectedRows": 3
    },
    "id": 5
  }
  ```

