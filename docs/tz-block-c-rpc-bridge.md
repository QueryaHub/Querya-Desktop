# ТЗ Блок C: RPC Protocol Bridge (Транспортный слой)

## 1. Введение и Зона Ответственности
**RPC Bridge (Блок C)** — это изолированный модуль внутри Flutter-приложения, отвечающий за связь с дочерними процессами плагинов. Он скрывает сложность потоков (Streams) и предоставляет ядру удобный асинхронный API (Futures).

**Основные задачи:**
1. Запуск бинарных файлов плагинов (`Process.start`).
2. Сериализация вызовов в стандарт `JSON-RPC 2.0`.
3. Мониторинг "здоровья" дочернего процесса (краши, зависания).

---

## 2. Реализация JSON-RPC 2.0 через Stdio

Связь между Querya Desktop (Flutter) и Плагином происходит локально через стандартные потоки ввода-вывода (Standard I/O). Это безопасно, так как не требует открытия сетевых портов на машине пользователя.

**Технический стек в Dart:**
- Пакет `stream_channel` для склеивания `process.stdin` и `process.stdout`.
- Пакет `json_rpc_2` для реализации самого протокола.

**Пример инициализации:**
```dart
final process = await Process.start(pluginExecutablePath, []);

final channel = StreamChannel(
  process.stdout.transform(utf8.decoder).transform(jsonDocument),
  process.stdin.transform(utf8.encoder),
);

final rpcClient = json_rpc_2.Client(channel);
rpcClient.listen();

// Вызов метода на стороне плагина
final result = await rpcClient.sendRequest('db.connect', credentialsMap);
```

---

## 3. Обработка Ошибок и Жизненный Цикл Процесса (Watchdog)

Так как плагины (особенно сторонние драйверы БД) могут падать из-за ошибок в работе с сетью или памятью, Блок C обязан быть отказоустойчивым.

1. **Отслеживание `process.exitCode`:** При неожиданном завершении процесса (код != 0), RPC Bridge должен корректно закрыть все активные Future (выбросить `PluginCrashedException`), чтобы UI приложения не "завис" в бесконечном ожидании загрузки.
2. **Ping / Healthcheck:** RPC Bridge должен периодически (например, раз в минуту) отправлять запрос `system.ping`. Если ответа нет более 10 секунд — процесс считается зависшим (Deadlock).
3. **Graceful Shutdown:** При удалении подключения в приложении или закрытии самого Querya Desktop, ядро отправляет `system.shutdown`. Плагин обязан корректно закрыть все TCP-соединения с БД и завершить работу. Если процесс не умер через 3 секунды, вызывается `process.kill()`.

---

## 5. Лимиты полезной нагрузки (NDJSON)

Каждый ответ — **одна JSON-строка** на `stdout` (newline-delimited). Хост (`JsonRpcStdioClient`) применяет:

| Лимит | Значение по умолчанию | Поведение |
|-------|----------------------|-----------|
| Макс. длина одной строки ответа | **32 MiB** UTF-8 | Fail closed: `JsonRpcPayloadTooLargeException`, все pending RPC завершаются ошибкой |
| Декод больших строк | **> 64 KiB** | `jsonDecode` уходит в isolate |

Для `db.query` хост всегда передаёт `params.limit` (Preferences → Max rows in results), чтобы драйвер обрезал результат **до** сериализации. Драйверы обязаны уважать `limit`.

Чанкованный / бинарный framing для очень больших выборок — follow-up; до него bound + `limit` обязательны.
