import 'dart:io';
import 'enums.dart';

class PrinterNetworkManager {
  late String _host;
  int _port = 9100;
  Duration _timeout = const Duration(seconds: 5);
  late Socket _socket;

  PrinterNetworkManager(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(seconds: 5),
  }) {
    _host = host;
    _port = port;
    _timeout = timeout;
  }

  Future<PosPrintResult> connect() async {
    try {
      _socket = await Socket.connect(_host, _port, timeout: _timeout);
      return Future<PosPrintResult>.value(PosPrintResult.success);
    } catch (e) {
      return Future<PosPrintResult>.value(PosPrintResult.timeout);
    }
  }

  Future<PosPrintResult> printTicket(List<int> ticket) async {
    try {
      if (await _socket.isEmpty)
        return Future<PosPrintResult>.value(PosPrintResult.printerConnected);
      if (ticket.isNotEmpty) {
        _socket.add(ticket);
        return Future<PosPrintResult>.value(PosPrintResult.success);
      }
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    } catch (e) {
      return Future<PosPrintResult>.value(PosPrintResult.timeout);
    }
  }

  void disconnect({int delayMs = 0}) async {
    try {
      _socket.destroy();
      if (delayMs > 0)
        await Future.delayed(Duration(milliseconds: delayMs), () => null);
    } catch (e) {
      return;
    }
  }
}
