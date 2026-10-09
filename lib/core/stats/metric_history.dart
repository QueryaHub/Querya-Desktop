/// One sample of a metric: when it was taken and its value.
class MetricSample {
  const MetricSample(this.at, this.value);

  final DateTime at;
  final double value;
}

/// The last samples of named metrics, kept while a dashboard is open. Counters
/// (cumulative totals such as transactions committed) become rates per second
/// from their change between two samples.
class MetricHistory {
  MetricHistory({this.capacity = 120});

  /// Samples kept per metric: 120 at the 5 s poll is ten minutes.
  final int capacity;

  final Map<String, List<MetricSample>> _series = {};
  final Map<String, MetricSample> _lastCounter = {};

  void record(String name, double value, DateTime at) {
    final list = _series.putIfAbsent(name, () => []);
    list.add(MetricSample(at, value));
    if (list.length > capacity) list.removeRange(0, list.length - capacity);
  }

  /// Records the rate of a cumulative [total] since the previous sample. The
  /// first sample gives no rate; a counter that went down (a server restart)
  /// gives none either.
  void recordCounter(String name, double total, DateTime at) {
    final last = _lastCounter[name];
    _lastCounter[name] = MetricSample(at, total);
    if (last == null) return;
    final seconds =
        at.difference(last.at).inMicroseconds / Duration.microsecondsPerSecond;
    final delta = total - last.value;
    if (seconds <= 0 || delta < 0) return;
    record(name, delta / seconds, at);
  }

  List<MetricSample> series(String name) =>
      List.unmodifiable(_series[name] ?? const <MetricSample>[]);
}
