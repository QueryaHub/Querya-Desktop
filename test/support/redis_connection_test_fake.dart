
import 'package:querya_desktop/core/database/redis_connection.dart';

/// In-memory stub for widget tests (no socket). Handles SELECT, DBSIZE, SCAN,
/// TYPE, TTL used by [RedisKeysView].
class RedisConnectionTestFake extends RedisConnection {
  RedisConnectionTestFake({
    this.firstScanKeys = const ['alpha', 'beta'],
    this.secondScanKeys = const <String>[],
    this.dbSizeResult = 2,
    this.getResult,
    List<dynamic>? listItems,
    this.llenResult,
    this.hashFirstPage = const <String, String>{},
    this.hashSecondPage = const <String, String>{},
    this.hlenResult,
    this.setFirstPage = const <String>[],
    this.setSecondPage = const <String>[],
    this.scardResult,
    this.zsetItems = const <(String, double)>[],
    this.zcardResult,
    this.typeResult = 'string',
    this.failType = false,
    this.getBytesResult,
    this.binaryScanKeys = const <List<int>>[],
    this.unlinkUnsupported = false,
  })  : listItems =
            listItems != null ? List<dynamic>.from(listItems) : <dynamic>[],
        super(
          id: -1,
          name: 'test-fake',
          host: 'localhost',
          port: 6379,
        );

  final List<String> firstScanKeys;
  final List<String> secondScanKeys;
  final int dbSizeResult;
  final String? getResult;
  final List<dynamic> listItems;
  final int? llenResult;
  final Map<String, String> hashFirstPage;
  final Map<String, String> hashSecondPage;
  final int? hlenResult;
  final List<String> setFirstPage;
  final List<String> setSecondPage;
  final int? scardResult;
  final List<(String, double)> zsetItems;
  final int? zcardResult;
  final String typeResult;
  final bool failType;
  final List<int>? getBytesResult;
  final List<List<int>> binaryScanKeys;

  /// Answers `UNLINK` like a server before Redis 4.0.
  final bool unlinkUnsupported;
  final List<String> sentCommands = [];

  var _up = false;
  bool _firstScanDone = false;
  bool _firstHscanDone = false;
  bool _firstSscanDone = false;

  @override
  bool get isConnected => _up;

  @override
  Future<void> connect() async {
    _up = true;
  }

  @override
  Future<void> disconnect() async {
    _up = false;
  }

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    if (!_up) {
      throw StateError('Not connected to Redis');
    }
    final op = args.first.toString().toUpperCase();
    sentCommands.add(op);
    switch (op) {
      case 'SELECT':
        return 'OK';
      case 'DBSIZE':
        return dbSizeResult;
      case 'SCAN':
        final cursor = int.tryParse(args[1].toString()) ?? 0;
        List<Object> keysFor(List<String> named) =>
            [...named, ...binaryScanKeys];
        if (cursor == 0 && !_firstScanDone) {
          _firstScanDone = true;
          final next = secondScanKeys.isNotEmpty ? 1 : 0;
          return [next, keysFor(firstScanKeys)];
        }
        if (cursor == 1 && secondScanKeys.isNotEmpty) {
          return [0, keysFor(secondScanKeys)];
        }
        return [0, <Object>[]];
      case 'TYPE':
        if (failType) {
          throw StateError('TYPE failed');
        }
        return typeResult;
      case 'TTL':
        return -1;
      case 'GET':
        if (getBytesResult != null) return getBytesResult;
        if (typeResult != 'string') {
          throw StateError(
            'WRONGTYPE Operation against a key holding the wrong kind of value',
          );
        }
        return getResult;
      case 'SET':
        if (typeResult != 'string') {
          throw StateError('SET refused: key is $typeResult');
        }
        return 'OK';
      case 'HGETALL':
      case 'SMEMBERS':
        throw StateError('$op is unbounded; use a paged command');
      case 'HLEN':
        return hlenResult ?? hashFirstPage.length + hashSecondPage.length;
      case 'LLEN':
        return llenResult ?? listItems.length;
      case 'SCARD':
        return scardResult ?? setFirstPage.length + setSecondPage.length;
      case 'ZCARD':
        return zcardResult ?? zsetItems.length;
      case 'LRANGE':
        return _sliceList(listItems, args);
      case 'ZRANGE':
        final stop = int.tryParse(args[3].toString()) ?? -1;
        if (stop < 0) {
          throw StateError('unbounded ZRANGE');
        }
        final start = int.tryParse(args[2].toString()) ?? 0;
        if (start >= zsetItems.length || start > stop) return <dynamic>[];
        final end = (stop + 1).clamp(0, zsetItems.length);
        final out = <dynamic>[];
        for (final (member, score) in zsetItems.sublist(start, end)) {
          out.add(member);
          out.add(score);
        }
        return out;
      case 'HSCAN':
        return _pagedPairs(
          cursor: int.tryParse(args[2].toString()) ?? 0,
          first: hashFirstPage,
          second: hashSecondPage,
          firstDone: _firstHscanDone,
          markFirst: () => _firstHscanDone = true,
        );
      case 'SSCAN':
        final cursor = int.tryParse(args[2].toString()) ?? 0;
        if (cursor == 0 && !_firstSscanDone) {
          _firstSscanDone = true;
          final next = setSecondPage.isNotEmpty ? 1 : 0;
          return [next, setFirstPage];
        }
        if (cursor == 1 && setSecondPage.isNotEmpty) {
          return [0, setSecondPage];
        }
        return [0, <String>[]];
      case 'READONLY':
      case 'READWRITE':
        return 'OK';
      case 'EXISTS':
        final target = args[1].toString();
        final allKeys = [...firstScanKeys, ...secondScanKeys];
        return allKeys.contains(target) ? 1 : 0;
      case 'RENAME':
        return 'OK';
      case 'RENAMENX':
        final target = args[2].toString();
        final allKeys = [...firstScanKeys, ...secondScanKeys];
        return allKeys.contains(target) ? 0 : 1;
      case 'RPUSH':
        listItems.add(args[2].toString());
        return 'OK';
      case 'LINDEX':
        final lindexIdx = int.tryParse(args[2].toString()) ?? 0;
        if (lindexIdx >= 0 && lindexIdx < listItems.length) {
          return listItems[lindexIdx];
        }
        return null;
      case 'LSET':
        final idx = int.tryParse(args[2].toString()) ?? 0;
        final val = args[3].toString();
        if (idx >= 0 && idx < listItems.length) {
          listItems[idx] = val;
        }
        return 'OK';
      case 'LREM':
        final count = int.tryParse(args[2].toString()) ?? 0;
        final val = args[3].toString();
        var removed = 0;
        if (count == 0) {
          removed = listItems.where((e) => e == val).length;
          listItems.removeWhere((e) => e == val);
        } else if (count > 0) {
          for (var i = 0; i < count; i++) {
            final idx = listItems.indexOf(val);
            if (idx != -1) {
              listItems.removeAt(idx);
              removed++;
            }
          }
        } else {
          for (var i = 0; i < count.abs(); i++) {
            final idx = listItems.lastIndexOf(val);
            if (idx != -1) {
              listItems.removeAt(idx);
              removed++;
            }
          }
        }
        return removed;
      case 'UNLINK' when unlinkUnsupported:
        throw Exception("ERR unknown command 'UNLINK'");
      case 'DEL' || 'UNLINK':
        final allKeys = [...firstScanKeys, ...secondScanKeys];
        var count = 0;
        for (var i = 1; i < args.length; i++) {
          final target = args[i].toString();
          if (allKeys.contains(target)) {
            count++;
          }
        }
        return count;
      default:
        return null;
    }
  }

  List<dynamic> _sliceList(List<dynamic> items, List<dynamic> args) {
    if (items.isEmpty) return const [];
    final start = int.tryParse(args[2].toString()) ?? 0;
    var stop = int.tryParse(args[3].toString()) ?? -1;
    if (stop < 0) {
      throw StateError('unbounded LRANGE');
    }
    if (start >= items.length || start > stop) return const [];
    final end = (stop + 1).clamp(0, items.length);
    return items.sublist(start, end);
  }

  List<dynamic> _pagedPairs({
    required int cursor,
    required Map<String, String> first,
    required Map<String, String> second,
    required bool firstDone,
    required void Function() markFirst,
  }) {
    List<String> flatten(Map<String, String> map) {
      final out = <String>[];
      map.forEach((k, v) {
        out.add(k);
        out.add(v);
      });
      return out;
    }

    if (cursor == 0 && !firstDone) {
      markFirst();
      final next = second.isNotEmpty ? 1 : 0;
      return [next, flatten(first)];
    }
    if (cursor == 1 && second.isNotEmpty) {
      return [0, flatten(second)];
    }
    return [0, <String>[]];
  }
}
