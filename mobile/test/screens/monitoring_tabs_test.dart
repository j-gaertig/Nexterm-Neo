import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/monitoring.dart';
import 'package:nexterm/screens/monitoring/format.dart';
import 'package:nexterm/screens/monitoring/tabs.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('formats bytes, uptime and percentages', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.50 KB');
    expect(formatBytes(5 * 1024 * 1024 * 1024), '5.00 GB');
    expect(formatUptime(90061), '1d 1h 1m');
    expect(formatUptime(null), 'Unknown');
    expect(formatPercent(12.0), '12%');
    expect(formatPercent(12.34), '12.3%');
  });

  testWidgets('overview shows system info and hides kernel on Windows', (
    tester,
  ) async {
    final linux = M.from({
      'cpuUsage': 12.5,
      'memoryUsage': 40,
      'memoryTotal': 8 * 1024 * 1024 * 1024,
      'processes': 210,
      'uptime': 3700,
      'loadAverage': [0.5, 0.4, 0.3],
      'osInfo': {
        'hostname': 'box',
        'name': 'Ubuntu',
        'version': '24.04',
        'kernel': '6.8',
        'architecture': 'x64',
        'platform': 'linux',
      },
    });
    await tester.pumpWidget(_host(OverviewTab(latest: linux, isPve: false)));
    expect(find.text('box'), findsOneWidget);
    expect(find.text('Kernel'), findsOneWidget);
    expect(find.text('Load average'), findsOneWidget);

    final windows = M.from({
      'osInfo': {'hostname': 'win', 'platform': 'windows'},
    });
    await tester.pumpWidget(_host(OverviewTab(latest: windows, isPve: false)));
    expect(find.text('Kernel'), findsNothing);
    expect(find.text('Load average'), findsNothing);
  });

  testWidgets('processes can be searched and sorted', (tester) async {
    final processes = [
      M.from({
        'pid': 1,
        'user': 'root',
        'command': 'systemd',
        'cpu': 1.0,
        'mem': 2.0,
      }),
      M.from({
        'pid': 2,
        'user': 'app',
        'command': 'node server',
        'cpu': 40.0,
        'mem': 5.0,
      }),
    ];
    await tester.pumpWidget(_host(ProcessesTab(processes: processes)));
    expect(find.text('systemd'), findsOneWidget);
    expect(find.text('node server'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'node');
    await tester.pump();
    expect(find.text('systemd'), findsNothing);
    expect(find.text('node server'), findsOneWidget);
  });

  testWidgets('empty tabs explain the missing data', (tester) async {
    await tester.pumpWidget(
      _host(const StorageTab(disks: [], isWindows: false)),
    );
    expect(find.text('No storage data available'), findsOneWidget);
    await tester.pumpWidget(_host(const NetworkTab(interfaces: [])));
    expect(find.text('No network data available'), findsOneWidget);
  });
}
