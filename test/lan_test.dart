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

GameController newGame([DateTime Function()? now]) => GameController(
      now: now,
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
  bool drop = false; // simulates a message lost on the way

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
    if (!drop) peer._in.add(m);
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

class _FakeReconnect implements LanReconnect {
  final StreamController<RemoteLink> ctl = StreamController.broadcast(sync: true);
  bool started = false, stopped = false;
  @override
  Stream<RemoteLink> get links => ctl.stream;
  @override
  Future<void> start() async => started = true;
  @override
  Future<void> stop() async => stopped = true;
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
      final guestFuture = host.guests.first;
      final first = await joinLanGame(ad);
      await guestFuture.timeout(const Duration(seconds: 5));
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
    test('a guest that lost its connection can come back with the game secret; strangers cannot', () async {
      final host = LanHost(name: 'Rejoin', discoveryPort: 47894, debugTargets: const []);
      await host.start();
      final ad = LanAdvert(id: host.id, name: 'Rejoin', address: '127.0.0.1', port: host.port);
      final first = host.guests.first;
      final link = await joinLanGame(ad, name: 'Lee');
      final g1 = await first.timeout(const Duration(seconds: 5));
      host.lock('secret-1');
      await link.close();
      await g1.link.done.timeout(const Duration(seconds: 5));

      await expectLater(joinLanGame(ad, name: 'Stranger'), throwsA(isA<LanJoinException>()));
      await expectLater(joinLanGame(ad, name: 'Stranger', sid: 'wrong'), throwsA(isA<LanJoinException>()));

      final back = host.guests.first;
      final link2 = await joinLanGame(ad, name: 'Lee', sid: 'secret-1');
      final g2 = await back.timeout(const Duration(seconds: 5));
      expect(g2.name, 'Lee');
      final got = g2.link.messages.first;
      link2.send({'t': 'sync', 'moves': ['e2e4']});
      expect((await got.timeout(const Duration(seconds: 5)))['t'], 'sync');
      await link2.close();
      await host.stop();
    });

    test('before the game starts, a visitor with a secret is turned away', () async {
      final host = LanHost(name: 'Early', discoveryPort: 47895, debugTargets: const []);
      await host.start();
      final ad = LanAdvert(id: host.id, name: 'Early', address: '127.0.0.1', port: host.port);
      await expectLater(joinLanGame(ad, sid: 'anything'), throwsA(isA<LanJoinException>()));
      await host.stop();
    });

    test('GuestReconnect keeps trying until the host answers, then stops', () async {
      var tries = 0;
      final link = _FakeLink();
      final r = GuestReconnect(
        ad: const LanAdvert(id: 'x', name: 'x', address: '1.2.3.4', port: 1),
        sid: 's',
        name: 'Lee',
        retryEvery: const Duration(milliseconds: 5),
        join: (ad, name, sid) async {
          tries++;
          if (tries < 3) throw LanJoinException('no');
          expect(sid, 's');
          return link;
        },
      );
      final got = r.links.first;
      await r.start();
      expect(await got, same(link));
      expect(tries, 3);
      await r.stop();
    });

    test('GuestReconnect gives up after the time limit', () async {
      var tries = 0;
      final r = GuestReconnect(
        ad: const LanAdvert(id: 'x', name: 'x', address: '1.2.3.4', port: 1),
        sid: 's',
        name: 'Lee',
        retryEvery: const Duration(milliseconds: 5),
        giveUpAfter: const Duration(milliseconds: 60),
        join: (ad, name, sid) async {
          tries++;
          throw LanJoinException('no');
        },
      );
      await r.start();
      expect(tries, greaterThan(1));
      await r.stop();
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

    test('names of both players are shown', () async {
      final (hl, gl) = _FakeLink.pair();
      final h = newGame(), g = newGame();
      h.startLan(hl, Side.w, isHost: true, myName: 'Sam', oppName: 'Lee');
      g.startLan(gl, Side.b, isHost: false, myName: 'Lee', oppName: 'Sam');
      expect(h.snapshot.opponentName, 'Lee');
      expect(g.snapshot.opponentName, 'Sam');
      h.dispose();
      g.dispose();
    });

    test('take back: my last move goes back on both phones when the opponent allows it', () async {
      final (h, g, _, _) = startPair();
      expect(h.snapshot.canTakeback, isFalse); // nothing to take back yet
      h.tap('e2');
      h.tap('e4');
      await settle();
      expect(h.snapshot.canTakeback, isTrue);
      expect(g.snapshot.canTakeback, isFalse); // Black has not moved: cannot ask
      h.requestTakeback();
      await settle();
      expect(h.snapshot.takebackOut, isTrue);
      expect(g.snapshot.takebackIn, isTrue);
      h.tap('d2'); // no moves while waiting for the answer
      h.tap('d4');
      await settle();
      expect(h.snapshot.history.length, 1);
      g.answerTakeback(true);
      await settle();
      expect(h.snapshot.history, isEmpty);
      expect(g.snapshot.history, isEmpty);
      expect(h.snapshot.turn, Side.w);
      expect(g.snapshot.takebackIn, isFalse);
      h.dispose();
      g.dispose();
    });

    test('take back after the reply: both moves go back', () async {
      final (h, g, _, _) = startPair();
      h.tap('e2');
      h.tap('e4');
      await settle();
      g.tap('e7');
      g.tap('e5');
      await settle();
      h.requestTakeback(); // White's move was answered, so both half-moves go
      await settle();
      g.answerTakeback(true);
      await settle();
      expect(h.snapshot.history, isEmpty);
      expect(g.snapshot.history, isEmpty);
      h.dispose();
      g.dispose();
    });

    test('Black can take back just their own last move', () async {
      final (h, g, _, _) = startPair();
      h.tap('e2');
      h.tap('e4');
      await settle();
      g.tap('e7');
      g.tap('e5');
      await settle();
      g.requestTakeback();
      await settle();
      h.answerTakeback(true);
      await settle();
      expect(h.snapshot.history.length, 1);
      expect(g.snapshot.history.length, 1);
      expect(g.snapshot.turn, Side.b);
      h.dispose();
      g.dispose();
    });

    test('a declined take-back is reported and play goes on', () async {
      final (h, g, _, _) = startPair();
      h.tap('e2');
      h.tap('e4');
      await settle();
      h.requestTakeback();
      await settle();
      g.answerTakeback(false);
      await settle();
      expect(h.snapshot.takebackOut, isFalse);
      expect(h.snapshot.notice, 'Take-back declined');
      expect(h.snapshot.history.length, 1);
      g.tap('e7');
      g.tap('e5');
      await settle();
      expect(h.snapshot.history.length, 2);
      expect(h.snapshot.notice, isNull);
      h.dispose();
      g.dispose();
    });

    test('a take-back request that no longer matches the position is declined by itself', () async {
      final (h, g, hl, _) = startPair();
      h.tap('e2');
      h.tap('e4');
      await settle();
      g.tap('e7');
      g.tap('e5'); // the guest moves...
      await settle();
      hl.send({'t': 'tb', 'a': 'req', 'n': 1}); // ...but the host's request still refers to the old position
      await settle();
      expect(g.snapshot.takebackIn, isFalse);
      h.dispose();
      g.dispose();
    });

    test('a lost connection comes back and a move lost on the way is recovered', () async {
      final (hl, gl) = _FakeLink.pair();
      final hr = _FakeReconnect(), gr = _FakeReconnect();
      final h = newGame(), g = newGame();
      h.startLan(hl, Side.w, isHost: true, reconnect: hr);
      g.startLan(gl, Side.b, isHost: false, reconnect: gr);
      hl.drop = true; // White's move is lost on the way, then the connection drops
      h.tap('e2');
      h.tap('e4');
      await settle();
      expect(g.snapshot.history, isEmpty);
      await hl.close();
      await settle();
      expect(h.snapshot.linkLost, isTrue);
      expect(g.snapshot.linkLost, isTrue);
      expect(gr.started, isTrue); // the guest starts trying to get back
      h.tap('d2'); // nobody can move while the connection is down
      h.tap('d4');
      await settle();
      expect(h.snapshot.history.length, 1);

      final (hl2, gl2) = _FakeLink.pair();
      gr.ctl.add(gl2); // the guest listens first, so the host's sync is not missed
      hr.ctl.add(hl2);
      await settle();
      expect(h.snapshot.linkLost, isFalse);
      expect(g.snapshot.linkLost, isFalse);
      expect(g.snapshot.history.length, 1); // synced
      expect(g.snapshot.turn, Side.b);
      g.tap('e7');
      g.tap('e5');
      await settle();
      expect(h.snapshot.history.length, 2);
      h.dispose();
      g.dispose();
      expect(hr.stopped, isTrue);
      expect(gr.stopped, isTrue);
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

  group('chess clock', () {
    late DateTime t0;
    late DateTime now;
    setUp(() {
      t0 = DateTime(2026, 1, 1);
      now = t0;
    });
    void advance(int sec) => now = now.add(Duration(seconds: sec));

    GameController timedLocal({int sec = 60, int inc = 0}) {
      final g = newGame(() => now);
      g.start(GameConfig(mode: GameMode.local, timeSec: sec, incSec: inc));
      return g;
    }

    test('no clock when the game is untimed', () {
      final g = newGame(() => now);
      g.start(const GameConfig(mode: GameMode.local));
      expect(g.snapshot.config.timed, isFalse);
      advance(500);
      g.debugTickClock();
      expect(g.snapshot.status, GameStatus.playing);
      g.dispose();
    });

    test('the clock starts after the first move, then charges the side to move', () async {
      final g = timedLocal(sec: 60, inc: 2);
      advance(30);
      g.debugTickClock();
      expect(g.snapshot.whiteMs, 60000); // nothing runs before the first move
      g.tap('e2');
      g.tap('e4');
      await settle();
      expect(g.snapshot.whiteMs, 62000); // +2 s increment
      advance(10);
      g.debugTickClock();
      expect(g.snapshot.blackMs, 50000);
      expect(g.snapshot.whiteMs, 62000);
      g.dispose();
    });

    test('running out of time loses the game', () async {
      final g = timedLocal(sec: 60);
      g.tap('e2');
      g.tap('e4');
      await settle();
      advance(61);
      g.debugTickClock();
      expect(g.snapshot.status, GameStatus.resigned);
      expect(g.snapshot.reason, 'Black ran out of time');
      expect(g.snapshot.winner, Side.w);
      expect(g.snapshot.blackMs, 0);
      // no more moves after the flag fell
      g.tap('e7');
      g.tap('e5');
      await settle();
      expect(g.snapshot.history.length, 1);
      g.dispose();
    });

    test('leaving the game to the menu pauses the clock', () async {
      final g = timedLocal(sec: 60);
      g.tap('e2');
      g.tap('e4');
      await settle();
      advance(5);
      g.leave();
      advance(100);
      g.resume();
      advance(5);
      g.debugTickClock();
      expect(g.snapshot.blackMs, 50000);
      expect(g.snapshot.status, GameStatus.playing);
      g.dispose();
    });

    test('a saved timed game comes back with its clock', () async {
      final store = MemoryStore();
      final g = GameController(board: BoardModel()..animations = false, engine: _NoEngine(), store: store, sfx: SilentSfx(), thinkMinimum: Duration.zero, now: () => now);
      g.start(const GameConfig(mode: GameMode.local, timeSec: 120, incSec: 1));
      g.tap('d2');
      g.tap('d4');
      await settle();
      advance(7);
      g.leave();
      final saved = GameController.loadSlots(store).single;
      expect(saved.config.timeSec, 120);
      expect(saved.config.incSec, 1);
      expect(saved.whiteMs, 121000);
      expect(saved.blackMs, 120000);
      g.dispose();
    });

    test('two phones: only the phone whose own clock ran out declares it, and both agree', () async {
      final (hl, gl) = _FakeLink.pair();
      final h = newGame(() => now), g = newGame(() => now);
      h.startLan(hl, Side.w, isHost: true, timeSec: 60);
      g.startLan(gl, Side.b, isHost: false, timeSec: 60);
      h.tap('e2');
      h.tap('e4');
      await settle();
      advance(61);
      h.debugTickClock(); // the host only estimates Black's clock: it must not end the game by itself
      expect(h.snapshot.status, GameStatus.playing);
      g.debugTickClock(); // Black's own phone sees its clock empty and says so
      await settle();
      expect(g.snapshot.status, GameStatus.resigned);
      expect(h.snapshot.status, GameStatus.resigned);
      expect(h.snapshot.winner, Side.w);
      expect(h.snapshot.reason, 'Black ran out of time');
      h.dispose();
      g.dispose();
    });

    test('a rematch keeps the clock settings', () async {
      final (hl, gl) = _FakeLink.pair();
      final h = newGame(() => now), g = newGame(() => now);
      h.startLan(hl, Side.w, isHost: true, timeSec: 180, incSec: 2);
      g.startLan(gl, Side.b, isHost: false, timeSec: 180, incSec: 2);
      h.resign();
      await settle();
      h.requestRematch();
      g.requestRematch();
      await settle();
      expect(h.snapshot.config.timeSec, 180);
      expect(g.snapshot.config.timeSec, 180);
      expect(g.snapshot.config.incSec, 2);
      expect(g.snapshot.whiteMs, 180000);
      h.dispose();
      g.dispose();
    });
  });
}
