import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';

void main() {
  group('PosPrintResult', () {
    test('success message', () {
      expect(PosPrintResult.success.msg, 'Success');
    });

    test('timeout message', () {
      expect(PosPrintResult.timeout.msg, 'Error. Printer connection timeout');
    });

    test('printerConnected message', () {
      expect(
          PosPrintResult.printerConnected.msg, 'Error. Printer not connected');
    });

    test('ticketEmpty message', () {
      expect(PosPrintResult.ticketEmpty.msg, 'Error. Ticket is empty');
    });

    test('printInProgress message', () {
      expect(PosPrintResult.printInProgress.msg,
          'Error. Another print in progress');
    });

    test('scanInProgress message', () {
      expect(PosPrintResult.scanInProgress.msg,
          'Error. Printer scanning in progress');
    });

    test('connectionRefused message', () {
      expect(PosPrintResult.connectionRefused.msg,
          'Error. Printer connection refused');
    });

    test('socketError message', () {
      expect(PosPrintResult.socketError.msg, 'Error. Socket error');
    });

    test('disconnectError message', () {
      expect(PosPrintResult.disconnectError.msg, 'Error. Failed to disconnect');
    });

    test('each result has unique value', () {
      final results = [
        PosPrintResult.success,
        PosPrintResult.timeout,
        PosPrintResult.printerConnected,
        PosPrintResult.ticketEmpty,
        PosPrintResult.printInProgress,
        PosPrintResult.scanInProgress,
        PosPrintResult.connectionRefused,
        PosPrintResult.socketError,
        PosPrintResult.disconnectError,
      ];
      final values = results.map((r) => r.value).toSet();
      expect(values.length, results.length);
    });
  });

  group('PrinterNetworkManager', () {
    test('constructor sets default values', () {
      final printer = PrinterNetworkManager('192.168.1.100');
      expect(printer.isConnected, false);
    });

    test('constructor accepts custom port and timeout', () {
      final printer = PrinterNetworkManager(
        '192.168.1.100',
        port: 9200,
        timeout: const Duration(seconds: 10),
      );
      expect(printer.isConnected, false);
    });

    test('connect to unreachable host returns timeout', () async {
      final printer = PrinterNetworkManager(
        '192.168.254.254',
        timeout: const Duration(seconds: 1),
      );
      final result = await printer.connect();
      expect(result.value, isNot(PosPrintResult.success.value));
      expect(printer.isConnected, false);
    });

    test('connect to invalid host returns error', () async {
      final printer = PrinterNetworkManager(
        '0.0.0.0',
        port: 1,
        timeout: const Duration(seconds: 1),
      );
      final result = await printer.connect();
      expect(result.value, isNot(PosPrintResult.success.value));
      expect(printer.isConnected, false);
    });

    test('printTicket with empty data returns ticketEmpty', () async {
      final printer = PrinterNetworkManager('192.168.1.100');
      final result = await printer.printTicket([]);
      expect(result, PosPrintResult.ticketEmpty);
    });

    test('printTicket without connection attempts reconnect', () async {
      final printer = PrinterNetworkManager(
        '192.168.254.254',
        timeout: const Duration(seconds: 1),
      );
      final result = await printer.printTicket([1, 2, 3]);
      // Should fail because host is unreachable
      expect(result.value, isNot(PosPrintResult.success.value));
    });

    test('disconnect when not connected succeeds', () async {
      final printer = PrinterNetworkManager('192.168.1.100');
      final result = await printer.disconnect();
      expect(result, PosPrintResult.success);
      expect(printer.isConnected, false);
    });

    test('disconnect with timeout delays', () async {
      final printer = PrinterNetworkManager('192.168.1.100');
      final stopwatch = Stopwatch()..start();
      await printer.disconnect(timeout: const Duration(milliseconds: 200));
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(150));
    });
  });

  group('PrinterNetworkManager with mock server', () {
    late ServerSocket server;
    late int serverPort;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    test('connect to local server succeeds', () async {
      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );
      final result = await printer.connect();
      expect(result, PosPrintResult.success);
      expect(printer.isConnected, true);
      await printer.disconnect();
      expect(printer.isConnected, false);
    });

    test('multiple connect calls do not leak sockets', () async {
      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );

      // Connect multiple times - each should close the previous socket
      final result1 = await printer.connect();
      expect(result1, PosPrintResult.success);

      final result2 = await printer.connect();
      expect(result2, PosPrintResult.success);

      final result3 = await printer.connect();
      expect(result3, PosPrintResult.success);

      // Clean up
      await printer.disconnect();
      expect(printer.isConnected, false);
    });

    test('printTicket sends data and disconnects', () async {
      final completer = Completer<List<int>>();
      server.listen((socket) {
        final data = <int>[];
        socket.listen(
          (chunk) => data.addAll(chunk),
          onDone: () => completer.complete(data),
        );
      });

      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );

      final testData = [0x1B, 0x40, 0x48, 0x65, 0x6C, 0x6C, 0x6F];
      final result = await printer.printTicket(testData);
      expect(result, PosPrintResult.success);
      expect(printer.isConnected, false);

      final received = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => <int>[],
      );
      expect(received, testData);
    });

    test('printTicket with isDisconnect=false keeps connection', () async {
      server.listen((socket) {
        socket.listen((_) {});
      });

      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );

      final result = await printer.printTicket(
        [1, 2, 3],
        isDisconnect: false,
      );
      expect(result, PosPrintResult.success);
      expect(printer.isConnected, true);

      // Clean up
      await printer.disconnect();
    });

    test('connect then disconnect lifecycle', () async {
      server.listen((socket) {
        socket.listen((_) {});
      });

      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );

      // Full lifecycle
      expect(printer.isConnected, false);

      final connectResult = await printer.connect();
      expect(connectResult, PosPrintResult.success);
      expect(printer.isConnected, true);

      final disconnectResult = await printer.disconnect();
      expect(disconnectResult, PosPrintResult.success);
      expect(printer.isConnected, false);
    });

    test('disconnect after server closes handles gracefully', () async {
      server.listen((socket) {
        socket.listen((_) {});
      });

      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );

      await printer.connect();
      expect(printer.isConnected, true);

      // Close server before disconnect
      await server.close();

      // Disconnect should handle error gracefully
      final result = await printer.disconnect();
      // Should succeed or return disconnectError, but not throw
      expect(
        result.value,
        anyOf(
          PosPrintResult.success.value,
          PosPrintResult.disconnectError.value,
        ),
      );
      expect(printer.isConnected, false);
    });

    test('printTicket auto-connects when not connected', () async {
      server.listen((socket) {
        final data = <int>[];
        socket.listen((chunk) => data.addAll(chunk));
      });

      final printer = PrinterNetworkManager(
        '127.0.0.1',
        port: serverPort,
      );

      // Don't call connect() explicitly
      expect(printer.isConnected, false);
      final result = await printer.printTicket([0x1B, 0x40]);
      expect(result, PosPrintResult.success);
    });
  });
}
