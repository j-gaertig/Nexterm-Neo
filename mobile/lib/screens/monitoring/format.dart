/// Number and duration formatting shared by the monitoring pages.
String formatBytes(num? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : (value >= 100 ? 0 : (value >= 10 ? 1 : 2));
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatUptime(int? seconds) {
  if (seconds == null || seconds <= 0) return 'Unknown';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h ${m}m';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String formatPercent(num? value) =>
    value == null ? 'N/A' : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
