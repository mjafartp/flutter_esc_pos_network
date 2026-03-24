import 'dart:async';
import 'dart:io';
import 'enums.dart';

class PrinterNetworkManager {
  final String _host;
  final int _port;
  final Duration _timeout;
  Socket? _socket;
  bool _isConnected = false;
  bool _isPrinting = false;

  PrinterNetworkManager(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(seconds: 5),
  })  : _host = host,
        _port = port,
        _timeout = timeout;

  bool get isConnected => _isConnected;

  Future<PosPrintResult> connect({Duration? timeout}) async {
    // Close existing socket before creating a new one to prevent leaks
    if (_socket != null) {
      await _closeSocket();
    }

    try {
      _socket = await Socket.connect(
        _host,
        _port,
        timeout: timeout ?? _timeout,
      );
      _isConnected = true;
      return PosPrintResult.success;
    } on SocketException catch (e) {
      _isConnected = false;
      _socket = null;
      if (e.osError?.errorCode == 61 || e.osError?.errorCode == 111) {
        return PosPrintResult.connectionRefused;
      }
      return PosPrintResult.timeout;
    } catch (e) {
      _isConnected = false;
      _socket = null;
      return PosPrintResult.socketError;
    }
  }

  Future<PosPrintResult> printTicket(
    List<int> data, {
    bool isDisconnect = true,
  }) async {
    if (_isPrinting) {
      return PosPrintResult.printInProgress;
    }

    if (data.isEmpty) {
      return PosPrintResult.ticketEmpty;
    }

    _isPrinting = true;
    try {
      if (!_isConnected || _socket == null) {
        final connectResult = await connect();
        if (connectResult != PosPrintResult.success) {
          _isPrinting = false;
          return connectResult;
        }
      }

      _socket!.add(data);

      if (isDisconnect) {
        final disconnectResult = await disconnect();
        if (disconnectResult != PosPrintResult.success) {
          _isPrinting = false;
          return disconnectResult;
        }
      }

      _isPrinting = false;
      return PosPrintResult.success;
    } on SocketException {
      _isPrinting = false;
      await _closeSocket();
      return PosPrintResult.socketError;
    } catch (e) {
      _isPrinting = false;
      await _closeSocket();
      return PosPrintResult.socketError;
    }
  }

  Future<PosPrintResult> disconnect({Duration? timeout}) async {
    try {
      if (_socket != null) {
        await _socket!.flush();
        await _socket!.close();
      }
      _socket = null;
      _isConnected = false;
      if (timeout != null) {
        await Future.delayed(timeout, () => null);
      }
      return PosPrintResult.success;
    } catch (e) {
      // Even if flush/close fails, clean up state
      _socket = null;
      _isConnected = false;
      return PosPrintResult.disconnectError;
    }
  }

  /// Internal helper to safely close the socket without throwing
  Future<void> _closeSocket() async {
    try {
      await _socket?.close();
    } catch (_) {
      // Ignore errors during cleanup
    }
    _socket = null;
    _isConnected = false;
  }
}
