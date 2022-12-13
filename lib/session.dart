// ignore_for_file: always_specify_types

import 'dart:async';

import 'device.dart';
import 'socket.dart';

enum CastSessionState {
  connecting,
  connected,
  closed,
}

class CastSession {
  CastSession._(this.sessionId, this._socket);
  static const String kNamespaceConnection =
      'urn:x-cast:com.google.cast.tp.connection';
  static const String kNamespaceHeartbeat =
      'urn:x-cast:com.google.cast.tp.heartbeat';
  static const String kNamespaceReceiver =
      'urn:x-cast:com.google.cast.receiver';
  static const String kNamespaceDeviceauth =
      'urn:x-cast:com.google.cast.tp.deviceauth';
  static const String kNamespaceMedia = 'urn:x-cast:com.google.cast.media';

  final String sessionId;
  CastSocket get socket => _socket;
  CastSessionState get state => _state;

  Stream<CastSessionState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  final CastSocket _socket;
  CastSessionState _state = CastSessionState.connecting;
  String? _transportId;

  final StreamController<CastSessionState> _stateController =
      StreamController<CastSessionState>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Future<CastSession> connect(
    String sessionId,
    CastDevice device, [
    Duration? timeout,
  ]) async {
    final CastSocket socket = await CastSocket.connect(
      device.host,
      device.port,
      timeout,
    );

    final CastSession session = CastSession._(sessionId, socket);

    session._startListening();

    session.sendMessage(kNamespaceConnection, <String, dynamic>{
      'type': 'CONNECT',
    });

    return session;
  }

  Future<dynamic> close() async {
    if (!_messageController.isClosed) {
      sendMessage(kNamespaceConnection, <String, dynamic>{
        'type': 'CLOSE',
      });
      try {
        await _socket.flush();
      } catch (_error) {}
    }

    return _socket.close();
  }

  void _startListening() {
    _socket.stream.listen(
      (CastSocketMessage message) {
        // happen
        if (_messageController.isClosed) {
          return;
        }

        if (message.namespace == kNamespaceHeartbeat &&
            message.payload['type'] == 'PING') {
          sendMessage(kNamespaceHeartbeat, <String, dynamic>{
            'type': 'PONG',
          });
        } else if (message.namespace == kNamespaceConnection &&
            message.payload['type'] == 'CLOSE') {
          close();
        } else if (message.namespace == kNamespaceReceiver &&
            message.payload['type'] == 'RECEIVER_STATUS') {
          _handleReceiverStatus(message.payload);
          _messageController.add(message.payload);
        } else {
          _messageController.add(message.payload);
        }
      },
      onError: (Object error) {
        _messageController.addError(error);
      },
      onDone: () {
        _messageController.close();

        _state = CastSessionState.closed;
        _stateController.add(_state);
        _stateController.close();
      },
      cancelOnError: false,
    );
  }

  void _handleReceiverStatus(Map<String, dynamic> payload) {
    if (_transportId != null) {
      return;
    }

    if (payload['status']?.containsKey('applications') == true) {
      _transportId =
          payload['status']['applications'][0]['transportId'] as String?;

      // reconnect with new _transportId
      sendMessage(kNamespaceConnection, <String, dynamic>{
        'type': 'CONNECT',
      });

      _state = CastSessionState.connected;
      _stateController.add(_state);
    }
  }

  void sendMessage(String namespace, Map<String, dynamic> payload) {
    _socket.sendMessage(
      namespace,
      sessionId,
      _transportId ?? 'receiver-0',
      payload,
    );
  }

  Future<dynamic> flush() {
    return _socket.flush();
  }
}
