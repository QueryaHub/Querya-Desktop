import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_core_commands.dart';

/// App-wide command catalog for Command Palette (CP-01) and later menus.
class QueryaCommandRegistry extends ChangeNotifier {
  QueryaCommandRegistry._();

  static final QueryaCommandRegistry instance = QueryaCommandRegistry._();

  final Map<String, QueryaCommand> _commands = {};
  var _coreInstalled = false;

  /// Registers built-in commands once. Safe to call from [QueryaApp].
  void ensureCoreDefaults() {
    if (_coreInstalled) return;
    _coreInstalled = true;
    registerAll(queryaCoreCommands());
  }

  void register(QueryaCommand command) {
    _commands[command.id] = command;
    notifyListeners();
  }

  void registerAll(Iterable<QueryaCommand> commands) {
    for (final command in commands) {
      _commands[command.id] = command;
    }
    notifyListeners();
  }

  void unregister(String id) {
    if (_commands.remove(id) != null) {
      notifyListeners();
    }
  }

  void unregisterWhere(bool Function(QueryaCommand command) test) {
    final before = _commands.length;
    _commands.removeWhere((_, command) => test(command));
    if (_commands.length != before) {
      notifyListeners();
    }
  }

  QueryaCommand? operator [](String id) => _commands[id];

  List<QueryaCommand> get commands =>
      List<QueryaCommand>.unmodifiable(_commands.values);

  /// Commands whose [QueryaCommand.isEnabled] is true (or unset).
  List<QueryaCommand> getAvailableCommands(BuildContext context) {
    ensureCoreDefaults();
    return [
      for (final command in _commands.values)
        if (command.enabledIn(context)) command,
    ];
  }

  /// Filter [getAvailableCommands] (or all, if [context] is null) by [query].
  List<QueryaCommand> search(String query, {BuildContext? context}) {
    ensureCoreDefaults();
    final pool = context == null
        ? _commands.values
        : getAvailableCommands(context);
    if (query.trim().isEmpty) {
      return List<QueryaCommand>.from(pool);
    }
    return [for (final command in pool) if (command.matches(query)) command];
  }

  @visibleForTesting
  void resetForTest() {
    _commands.clear();
    _coreInstalled = false;
  }
}
