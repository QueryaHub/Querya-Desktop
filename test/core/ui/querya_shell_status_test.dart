import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';

void main() {
  final status = QueryaShellStatus.instance;

  setUp(status.resetForTest);
  tearDown(status.resetForTest);

  test('the busy message goes away with the busy state', () {
    status.beginBusy(message: 'Running query…');
    expect(status.isBusy, isTrue);
    expect(status.statusMessage, 'Running query…');

    status.endBusy();

    expect(status.isBusy, isFalse);
    expect(status.statusMessage, isNull);
  });

  test('a failure replaces the busy message and drops old counts', () {
    status.reportQueryResult(
      duration: const Duration(milliseconds: 7),
      rowCount: 12,
      columnCount: 8,
      message: '12 row(s).',
    );
    status.beginBusy(message: 'Running query…');

    status.reportQueryFailure(
      duration: const Duration(milliseconds: 3),
      message: 'Query failed',
    );

    expect(status.isBusy, isFalse);
    expect(status.statusMessage, 'Query failed');
    expect(status.rowCount, isNull);
    expect(status.columnCount, isNull);
    expect(status.lastQueryDuration, const Duration(milliseconds: 3));
  });

  test('endBusy after a failure keeps the failure message', () {
    status.beginBusy(message: 'Explaining query…');
    status.reportQueryFailure(message: 'Explain failed');

    status.endBusy();

    expect(status.statusMessage, 'Explain failed');
  });

  test('a plain-count result leaves no "Running query…" behind (#1556)', () {
    status.beginBusy(message: 'Running query…');

    status.reportQueryResult(
      duration: const Duration(milliseconds: 1),
      rowCount: 12,
      columnCount: 8,
    );

    expect(status.isBusy, isFalse);
    expect(status.statusMessage, isNull);
    expect(status.rowCount, 12);
    expect(status.columnCount, 8);

    status.endBusy();
    expect(status.statusMessage, isNull);
  });

  test('a result without a message does not keep the text of an earlier run',
      () {
    status.reportQueryResult(rowCount: 3, columnCount: 1, message: 'Script done.');
    status.beginBusy(message: 'Running query…');

    status.reportQueryResult(rowCount: 12, columnCount: 8);

    expect(status.statusMessage, isNull);
  });

  test('a result with a message shows it after the busy message', () {
    status.beginBusy(message: 'Running query…');

    status.reportQueryResult(message: '3 statements, 5 row(s) affected.');

    expect(status.statusMessage, '3 statements, 5 row(s) affected.');
  });

  test('a result message is not cleared by a later endBusy', () {
    status.reportQueryResult(rowCount: 1, columnCount: 1, message: '1 row(s).');

    status.endBusy();

    expect(status.statusMessage, '1 row(s).');
  });

  test('setQueryMetrics replaces the numbers of the last run (#1479)', () {
    status.reportQueryResult(
      duration: const Duration(milliseconds: 48),
      rowCount: 8,
      columnCount: 6,
      message: 'OK',
    );

    status.setQueryMetrics();

    expect(status.statusMessage, isNull);
    expect(status.rowCount, isNull);
    expect(status.columnCount, isNull);
    expect(status.lastQueryDuration, isNull);
  });

  test('setQueryMetrics shows a notice and drops the old counts (#1478)', () {
    status.reportQueryResult(rowCount: 1, columnCount: 1, message: '1 row(s).');

    status.setQueryMetrics(message: 'Nothing to run');

    expect(status.statusMessage, 'Nothing to run');
    expect(status.rowCount, isNull);
  });

  test('setQueryMetrics leaves a running query\'s busy message alone', () {
    status.beginBusy(message: 'Running query…');

    status.setQueryMetrics(message: 'Nothing to run');

    expect(status.isBusy, isTrue);
    expect(status.statusMessage, 'Running query…');
  });
}
