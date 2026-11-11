// Two-phone play over the local network (same Wi-Fi router, or one phone's mobile hotspot). No internet, no codes:
//
//  * the host announces its game with a small UDP broadcast every second (port [lanDiscoveryPort]);
//  * a joining phone listens for those announcements and shows the games it finds;
//  * tapping a game opens a TCP connection to the host. Messages are one JSON object per line.
//
// Messages after the hello/welcome handshake: start {you}, move {uci}, resign, draw {a: offer|accept|decline},
// rematch, bye. A ping every 2 s detects a dropped connection (phone left the Wi-Fi, hotspot switched off, ...).
// Nothing here depends on Flutter, so it is unit-tested with real sockets on loopback.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const int lanDiscoveryPort = 47820;
const String lanAppId = 'chess3d.lan';
const int lanProtocol = 1;

/// A live connection to the other phone.
abstract class RemoteLink {
  /// Messages from the other phone (pings are filtered out). Broadcast stream.
  Stream<Map<String, dynamic>> get messages;

  /// Completes when the connection ends, whichever side ended it.
  Future<void> get done;
  bool get isOpen;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

/// [RemoteLink] over a TCP socket with line framing and a keep-alive.
class SocketLink implements RemoteLink {
  SocketLink(this._socket, {Duration ping = const Duration(seconds: 2), Duration timeout = const Duration(seconds: 9)}) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _sub = _socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        _lastRx = DateTime.now();
        try {
          final j = jsonDecode(line);
          if (j is Map<String, dynamic> && j['t'] != 'ping') _messages.add(j);
        } catch (_) {
          // a garbled line is ignored
        }
      },
      onError: (_) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
    _timer = Timer.periodic(ping, (_) {
      if (DateTime.now().difference(_lastRx) > timeout) {
        _end();
      } else {
        send({'t': 'ping'});
      }
    });
  }

  final Socket _socket;
  late final StreamSubscription<String> _sub;
  late final Timer _timer;
  final StreamController<Map<String, dynamic>> _messages = StreamController.broadcast(sync: true);
  final Completer<void> _done = Completer<void>();
  DateTime _lastRx = DateTime.now();
  bool _open = true;

  String get remoteAddress => _socket.remoteAddress.address;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Future<void> get done => _done.future;
  @override
  bool get isOpen => _open;

  @override
  void send(Map<String, dynamic> message) {
    if (!_open) return;
    try {
      _socket.write('${jsonEncode(message)}\n');
    } catch (_) {
      _end();
    }
  }

  void _end() {
    if (!_open) return;
    _open = false;
    _timer.cancel();
    unawaited(_sub.cancel());
    try {
      _socket.destroy();
    } catch (_) {}
    if (!_done.isCompleted) _done.complete();
    unawaited(_messages.close());
  }

  @override
  Future<void> close() async {
    if (_open) {
      try {
        _socket.write('${jsonEncode({'t': 'bye'})}\n');
        await _socket.flush();
      } catch (_) {}
    }
    _end();
  }
}

/// A game found on the network.
class LanAdvert {
  const LanAdvert({required this.id, required this.name, required this.address, required this.port});
  final String id, name, address;
  final int port;

  @override
  bool operator ==(Object other) => other is LanAdvert && other.id == id && other.address == address && other.port == port && other.name == name;
  @override
  int get hashCode => Object.hash(id, name, address, port);
}

/// A phone that connected to our hosted game.
class LanGuest {
  const LanGuest(this.link, this.name);
  final RemoteLink link;
  final String name;
}

String randomGameName([math.Random? r]) => 'Chess game ${1000 + (r ?? math.Random()).nextInt(9000)}';

/// Hosts one game: listens for a guest and announces itself on every local network.
class LanHost {
  LanHost({
    required this.name,
    this.discoveryPort = lanDiscoveryPort,
    this.announceEvery = const Duration(seconds: 1),
    this.debugTargets,
  });

  final String name;
  final int discoveryPort;
  final Duration announceEvery;

  /// Tests: send announcements only to these addresses.
  final List<InternetAddress>? debugTargets;

  final String id = '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
  ServerSocket? _server;
  Timer? _timer;
  final Map<String, RawDatagramSocket> _senders = {};
  final StreamController<LanGuest> _guests = StreamController.broadcast();
  SocketLink? _current;
  bool _stopped = false;

  /// Port guests connect to (valid after [start]).
  int get port => _server!.port;
  Stream<LanGuest> get guests => _guests.stream;

  /// True while a guest is connected: new visitors are turned away and announcements pause.
  bool get hasGuest => _current != null && _current!.isOpen;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_onConnection, onError: (_) {});
    await _announce();
    _timer = Timer.periodic(announceEvery, (_) => unawaited(_announce()));
  }

  void _onConnection(Socket s) {
    final link = SocketLink(s);
    StreamSubscription<Map<String, dynamic>>? sub;
    final timeout = Timer(const Duration(seconds: 5), () => unawaited(link.close()));
    sub = link.messages.listen((m) {
      if (m['t'] != 'hello') return;
      timeout.cancel();
      sub?.cancel();
      if (m['app'] != lanAppId || m['v'] != lanProtocol) {
        link.send({'t': 'busy', 'why': 'version'});
        unawaited(link.close());
        return;
      }
      if (_stopped || hasGuest) {
        link.send({'t': 'busy', 'why': 'full'});
        unawaited(link.close());
        return;
      }
      _current = link;
      link.done.then((_) {
        if (identical(_current, link)) _current = null;
      });
      link.send({'t': 'welcome', 'name': name});
      final guestName = (m['name'] is String && (m['name'] as String).isNotEmpty) ? m['name'] as String : 'Guest';
      _guests.add(LanGuest(link, guestName));
    });
    link.done.then((_) {
      timeout.cancel();
      sub?.cancel();
    });
  }

  Future<List<(InternetAddress from, InternetAddress to)>> _routes() async {
    final t = debugTargets;
    if (t != null) return [for (final a in t) (InternetAddress.anyIPv4, a)];
    final routes = <(InternetAddress, InternetAddress)>[];
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in ni.addresses) {
          final p = a.address.split('.');
          if (p.length != 4) continue;
          routes.add((a, InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'))); // the usual /24 of Wi-Fi and hotspots
          routes.add((a, InternetAddress('255.255.255.255')));
        }
      }
    } catch (e) {
      debugPrint('could not list network interfaces: $e');
    }
    return routes;
  }

  Future<void> _announce() async {
    if (_stopped || hasGuest || _server == null) return;
    final payload = utf8.encode(jsonEncode({'app': lanAppId, 'v': lanProtocol, 'id': id, 'name': name, 'port': _server!.port}));
    for (final (from, to) in await _routes()) {
      try {
        // one socket per local address, so the packet leaves through that network (Wi-Fi / hotspot), not mobile data
        final sock = _senders['${from.address}'] ??= (await RawDatagramSocket.bind(from, 0))..broadcastEnabled = true;
        sock.send(payload, to, discoveryPort);
      } catch (_) {
        // an interface without broadcast support is skipped
      }
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    for (final s in _senders.values) {
      s.close();
    }
    _senders.clear();
    await _server?.close();
    unawaited(_guests.close());
  }
}

/// Listens for announced games and keeps a live list (entries vanish a few seconds after the host stops announcing).
class LanScanner {
  LanScanner({this.port = lanDiscoveryPort, this.expireAfter = const Duration(seconds: 4)});
  final int port;
  final Duration expireAfter;

  RawDatagramSocket? _socket;
  Timer? _prune;
  final Map<String, (LanAdvert, DateTime)> _found = {};
  final StreamController<List<LanAdvert>> _out = StreamController.broadcast();

  Stream<List<LanAdvert>> get games => _out.stream;
  List<LanAdvert> get current => [for (final e in _found.values) e.$1];

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
    _socket!.broadcastEnabled = true;
    _socket!.listen((e) {
      if (e != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = _socket!.receive()) != null) {
        _handle(d!);
      }
    });
    _prune = Timer.periodic(const Duration(seconds: 1), (_) => _expire());
  }

  void _handle(Datagram d) {
    try {
      final j = jsonDecode(utf8.decode(d.data));
      if (j is! Map || j['app'] != lanAppId || j['v'] != lanProtocol) return;
      final id = j['id'], name = j['name'], p = j['port'];
      if (id is! String || name is! String || p is! int) return;
      final ad = LanAdvert(id: id, name: name, address: d.address.address, port: p);
      final changed = _found[id]?.$1 != ad;
      _found[id] = (ad, DateTime.now());
      if (changed) _out.add(current);
    } catch (_) {
      // not ours
    }
  }

  void _expire() {
    final now = DateTime.now();
    final before = _found.length;
    _found.removeWhere((_, v) => now.difference(v.$2) > expireAfter);
    if (_found.length != before) _out.add(current);
  }

  Future<void> stop() async {
    _prune?.cancel();
    _socket?.close();
    _socket = null;
    unawaited(_out.close());
  }
}

class LanJoinException implements Exception {
  LanJoinException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Connects to an announced game. Throws [LanJoinException] with a player-readable reason.
Future<RemoteLink> joinLanGame(LanAdvert ad, {String name = 'Guest', Duration timeout = const Duration(seconds: 6)}) async {
  Socket socket;
  try {
    socket = await Socket.connect(ad.address, ad.port, timeout: timeout);
  } catch (_) {
    throw LanJoinException('Could not reach that game. Are both phones on the same Wi-Fi or hotspot?');
  }
  final link = SocketLink(socket);
  final reply = Completer<Map<String, dynamic>>();
  final sub = link.messages.listen((m) {
    if ((m['t'] == 'welcome' || m['t'] == 'busy') && !reply.isCompleted) reply.complete(m);
  });
  unawaited(link.done.then((_) {
    if (!reply.isCompleted) reply.completeError(LanJoinException('The host closed the connection.'));
  }));
  link.send({'t': 'hello', 'app': lanAppId, 'v': lanProtocol, 'name': name});
  try {
    final m = await reply.future.timeout(timeout);
    if (m['t'] == 'busy') {
      await link.close();
      throw LanJoinException(m['why'] == 'version' ? 'That game runs a different version of the app.' : 'That game already has two players.');
    }
    return link;
  } on TimeoutException {
    await link.close();
    throw LanJoinException('The host did not answer.');
  } finally {
    await sub.cancel();
  }
}

/// What the lobby needs from the network layer (replaced by fakes in widget tests).
class LanServices {
  const LanServices({this.makeHost = _defaultHost, this.makeScanner = _defaultScanner, this.join = _defaultJoin});
  final LanHost Function() makeHost;
  final LanScanner Function() makeScanner;
  final Future<RemoteLink> Function(LanAdvert ad) join;

  static LanHost _defaultHost() => LanHost(name: randomGameName());
  static LanScanner _defaultScanner() => LanScanner();
  static Future<RemoteLink> _defaultJoin(LanAdvert ad) => joinLanGame(ad);
}
