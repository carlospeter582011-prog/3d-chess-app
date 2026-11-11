// Two-phone play: the network layer on real loopback sockets, and the controller against a fake paired link.

import 'dart:async';
import 'dart:io';

import 'package:chess3d/chess/types.dart';
import 'package:chess3d/chess/uci_engine.dart';
import 'package:chess3d/game/game_controller.dart';
import 'package:chess3d/game/settings.dart';
import 'package:chess3d/game/storage.dart';
import 'package:chess3d/net/lan.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoEngine implements BotEngine {
  @override
  Future<String?> bestMove(String fen, int elo) async => null;
  @override
  void stop() {}
  @override
  void resetGame() {}
  @override
  void dispose() {}
}

GameController newGame() => GameController(
      board: BoardModel()..animations = false,
      engine: _NoEngine(),
      store: MemoryStore(),
      sfx: SilentSfx(),
      thinkMinimum: Duration.zero,
    );

/// One end of an in-memory connection.
class _FakeLink implements RemoteLink {
  _FakeLink();
  late _FakeLink peer;
  final StreamController<Map<String, dynamic>> _in = StreamController.broadcast(sync: true);
  final Completer<void> _done = Completer<void>();
  bool _open = true;
  final List<Map<String, dynamic>> sent = [];

  static (_FakeLink, _FakeLink) pair() {
    final a = _FakeLink(), b = _FakeLink();
    a.peer = b;
    b.peer = a;
    return (a, b);
  }

  @override
  Stream<Map<String, dynamic>> get messages => _in.stream;
  @override
  Future<void> get done => _done.future;
  @override
  bool get isOpen => _open;
  @override
  void send(Map<String, dynamic> m) {
    if (!_open) return;
    sent.add(m);
    peer._in.add(m);
  }

  void _end() {
    if (!_open) return;
    _open = false;
    _done.complete();
  }

  @override
  Future<void> close() async {
    _end();
    peer._end();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('LAN sockets', () {
    test('a hosted game is found, joined, and messages travel both ways', () async {
      const port = 47891;
      final host = LanHost(name: 'Test game', discoveryPort: port, announceEvery: const Duration(milliseconds: 100), debugTargets: [InternetAddress.loopbackIPv4]);
      final scanner = LanScanner(port: port);
      await scanner.start();
      await host.start();
      final guestFuture = host.guests.first;

      final found = await scanner.games.firstWhere((l) => l.isNotEmpty).timeout(const Duration(seconds: 5));
      expect(found.single.name, 'Test game');
      expect(found.single.port, host.port);

      final guestLink = await joinLanGame(found.single, name: 'Phone B');
      final g = await guestFuture.timeout(const Duration(seconds: 5));
      expect(g.name, 'Phone B');

      final atHost = g.link.messages.first;
      guestLink.send({'t': 'move', 'uci': 'e7e5'});
      expect((await atHost.timeout(const Duration(seconds: 5)))['uci'], 'e7e5');
      final atGuest = guestLink.messages.first;
      g.link.send({'t': 'start', 'you': 'b'});
      expect((await atGuest.timeout(const Duration(seconds: 5)))['you'], 'b');

      await guestLink.close();
      await g.link.done.timeout(const Duration(seconds: 5));
      await host.stop();
      await scanner.stop();
    });

    test('a second phone is turned away while a guest is connected', () async {
      final host = LanHost(name: 'Full', discoveryPort: 47892, debugTargets: const []);
      await host.start();
      final ad = LanAdvert(id: host.id, name: 'Full', address: '127.0.0.1', port: host.port);
      final first = await joinLanGame(ad);
      await host.guests.first.timeout(const Duration(seconds: 5));
      await expectLater(joinLanGame(ad), throwsA(isA<LanJoinException>()));
      await first.close();
      await host.stop();
    });

    test('joining a game that is gone gives a readable error', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      await expectLater(
        joinLanGame(LanAdvert(id: 'x', name: 'x', address: '127.0.0.1', port: port), timeout: const Duration(seconds: 2)),
        throwsA(isA<LanJoinException>()),
      );
    });

    test('games vanish from the list when the host stops announcing', () async {
      const port = 47893;
      final host = LanHost(name: 'Soon gone', discoveryPort: port, announceEvery: const Duration(milliseconds: 100), debugTargets: [InternetAddress.loopbackIPv4]);
      final scanner = LanScanner(port: port, expireAfter: const Duration(milliseconds: 600));
      await scanner.start();
      await host.start();
      await scanner.games.firstWhere((l) => l.isNotEmpty).timeout(const Duration(seconds: 5));
      await host.stop();
      final empty = await scanner.games.firstWhere((l) => l.isEmpty).timeout(const Duration(seconds: 5));
      expect(empty, isEmpty);
      await scanner.stop();
    });
  });

  group('two-phone controller', () {
    (GameController host, GameController guest, _FakeLink hl, _FakeLink gl) startPair() {
      final (hl, gl) = _FakeLink.pair();
      final h = newGame(), g = newGame();
      h.startLan(hl, Side.w, isHost: true);
      g.startLan(gl, Side.b, isHost: false);
      return (h, g, hl, gl);
    }

    test('a move on one phone appears on the other, and turns alternate', () async {
      final (h, g, _, _) = startPair();
      expect(h.snapshot.config.mode, GameMode.lan);
      h.tap('e2');
      h.tap('e4');
      await settle();
      expect(h.snapshot.history.length, 1);
      expect(g.snapshot.history.length, 1);
      expect(g.snapshot.turn, Side.b);
      // the guest cannot move White's pieces, the host cannot move Black's
      g.tap('d2');
      g.tap('d4');
      await settle();
      expect(g.snapshot.history.length, 1);
      g.tap('e7');
      g.tap('e5');
      await settle();
      expect(h.snapshot.history.length, 2);
      expect(h.snapshot.turn, Side.w);
      h.dispose();
      g.dispose();
    });

    test('an illegal move from the other phone is ignored', () async {
      final (h, g, hl, gl) = startPair();
      gl.send({'t': 'move', 'uci': 'e7e5'}); // Black moving on White's turn
      gl.send({'t': 'move', 'uci': 'a1a8'});
      await settle();
      expect(h.snapshot.history, isEmpty);
      hl.send({'t': 'move', 'uci': 'e2e5'}); // not a legal pawn move
      await settle();
      expect(g.snapshot.history, isEmpty);
      h.dispose();
      g.dispose();
    });

    test('resigning ends the game on both phones', () async {
      final (h, g, _, _) = startPair();
      h.resign();
      await settle();
      expect(h.snapshot.status, GameStatus.resigned);
      expect(g.snapshot.status, GameStatus.resigned);
      expect(g.snapshot.winner, Side.b);
      h.dispose();
      g.dispose();
    });

    test('a draw offer can be declined, then accepted', () async {
      final (h, g, _, _) = startPair();
      h.offerDraw();
      await settle();
      expect(h.snapshot.drawOfferOut, isTrue);
      expect(g.snapshot.drawOfferIn, isTrue);
      g.answerDraw(false);
      await settle();
      expect(h.snapshot.drawOfferOut, isFalse);
      expect(h.snapshot.status, GameStatus.playing);
      g.offerDraw();
      await settle();
      expect(h.snapshot.drawOfferIn, isTrue);
      h.answerDraw(true);
      await settle();
      expect(h.snapshot.status, GameStatus.draw);
      expect(g.snapshot.status, GameStatus.draw);
      h.dispose();
      g.dispose();
    });

    test('losing the connection is reported and the game cannot go on', () async {
      final (h, g, hl, _) = startPair();
      await hl.close();
      await settle();
      expect(h.snapshot.linkLost, isTrue);
      expect(g.snapshot.linkLost, isTrue);
      h.dispose();
      g.dispose();
    });

    test('rematch needs both players, then swaps the colours', () async {
      final (h, g, _, _) = startPair();
      h.resign();
      await settle();
      h.requestRematch();
      await settle();
      expect(h.snapshot.rematchWaiting, isTrue);
      expect(h.snapshot.status, GameStatus.resigned);
      g.requestRematch();
      await settle();
      expect(h.snapshot.status, GameStatus.playing);
      expect(h.snapshot.config.humanColor, Side.b);
      expect(g.snapshot.config.humanColor, Side.w);
      expect(h.snapshot.history, isEmpty);
      h.dispose();
      g.dispose();
    });

    test('leaving closes the link', () async {
      final (h, _, hl, gl) = startPair();
      h.leave();
      await settle();
      expect(hl.isOpen, isFalse);
      expect(gl.isOpen, isFalse);
      h.dispose();
    });
  });
}
