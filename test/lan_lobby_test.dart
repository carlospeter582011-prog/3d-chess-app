import 'dart:async';
import 'dart:math' as math;

import 'package:chess3d/chess/types.dart';
import 'package:chess3d/net/lan.dart';
import 'package:chess3d/ui/lan_lobby.dart';
import 'package:chess3d/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Link implements RemoteLink {
  final StreamController<Map<String, dynamic>> in_ = StreamController.broadcast(sync: true);
  final Completer<void> d = Completer<void>();
  final List<Map<String, dynamic>> sent = [];
  bool open = true;
  @override
  Stream<Map<String, dynamic>> get messages => in_.stream;
  @override
  Future<void> get done => d.future;
  @override
  bool get isOpen => open;
  @override
  void send(Map<String, dynamic> m) => sent.add(m);
  @override
  Future<void> close() async {
    open = false;
    if (!d.isCompleted) d.complete();
  }
}

class _Host extends LanHost {
  _Host() : super(name: 'Chess game 1234', debugTargets: const []);
  final StreamController<LanGuest> ctl = StreamController.broadcast();
  bool stopped = false;
  @override
  Stream<LanGuest> get guests => ctl.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async => stopped = true;
}

class _Scanner extends LanScanner {
  final StreamController<List<LanAdvert>> ctl = StreamController.broadcast();
  List<LanAdvert> list = [];
  @override
  Stream<List<LanAdvert>> get games => ctl.stream;
  @override
  List<LanAdvert> get current => list;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

Widget wrap(Widget w) => MaterialApp(theme: buildTheme(), home: Scaffold(body: w));

void main() {
  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(450, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('host: waits, shows the joined phone, then starts with the chosen colour', (t) async {
    tall(t);
    final host = _Host();
    final link = _Link();
    LanSetup? started;
    await t.pumpWidget(wrap(LanLobby(
      host: true,
      services: LanServices(makeHost: (_) => host),
      onStart: (s) => started = s,
      onCancel: () {},
      timeSec: 300,
      incSec: 2,
      playerName: 'Sam',
    )));
    await t.pump();
    expect(find.byKey(const Key('lan-waiting')), findsOneWidget);
    host.ctl.add(LanGuest(link, 'Phone B'));
    await t.pump();
    expect(find.byKey(const Key('lan-joined')), findsOneWidget);
    expect(find.text('Clock: 5 min + 2s'), findsOneWidget);
    await t.tap(find.byKey(const Key('lan-color-black')));
    await t.pump();
    await t.tap(find.byKey(const Key('lan-start')));
    await t.pump();
    expect(started!.mySide, Side.b);
    expect(started!.isHost, isTrue);
    final msg = link.sent.single;
    expect([msg['t'], msg['you'], msg['time'], msg['inc'], msg['host']], ['start', 'w', 300, 2, 'Sam']); // other colour, clock, host name
    expect((msg['sid'] as String).isNotEmpty, isTrue);
    expect(started!.oppName, 'Phone B');
    expect(started!.myName, 'Sam');
    expect(started!.reconnect, isA<HostReconnect>());
    expect(started!.timeSec, 300);
    expect(started!.incSec, 2);

    expect(host.stopped, isFalse); // kept running: it now listens for a rejoin
  });

  testWidgets('host: if the guest leaves before the start the lobby goes back to waiting', (t) async {
    tall(t);
    final host = _Host();
    final link = _Link();
    await t.pumpWidget(wrap(LanLobby(host: true, services: LanServices(makeHost: (_) => host), onStart: (_) {}, onCancel: () {})));
    await t.pump();
    host.ctl.add(LanGuest(link, 'B'));
    await t.pump();
    await link.close();
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('lan-waiting')), findsOneWidget);
  });

  testWidgets('join: lists found games, joins one, and begins when the host starts', (t) async {
    tall(t);
    final scanner = _Scanner();
    final link = _Link();
    LanAdvert? joined;
    String? joinedAs;
    LanSetup? started;
    await t.pumpWidget(wrap(LanLobby(
      host: false,
      services: LanServices(
        makeScanner: () => scanner,
        join: (ad, name) async {
          joined = ad;
          joinedAs = name;
          return link;
        },
      ),
      onStart: (s) => started = s,
      onCancel: () {},
      playerName: 'Lee',
    )));
    await t.pump();
    expect(find.byKey(const Key('lan-searching')), findsOneWidget);
    const ad = LanAdvert(id: 'g1', name: 'Chess game 4321', address: '192.168.1.20', port: 5000);
    scanner.list = [ad];
    scanner.ctl.add([ad]);
    await t.pump();
    expect(find.text('Chess game 4321'), findsOneWidget);
    await t.tap(find.byKey(const Key('lan-game-g1')));
    await t.pump();
    await t.pump();
    expect(joined, ad);
    expect(joinedAs, 'Lee'); // the host sees the guest's name
    expect(find.byKey(const Key('lan-wait-start')), findsOneWidget);
    expect(started, isNull);
    link.in_.add({'t': 'start', 'you': 'b', 'time': 600, 'inc': 5, 'sid': 'abc', 'host': 'Sam'});
    expect(started!.mySide, Side.b);
    expect(started!.timeSec, 600);
    expect(started!.incSec, 5);
    expect(started!.oppName, 'Sam');
    expect(started!.myName, 'Lee');
    expect(started!.reconnect, isA<GuestReconnect>());
    expect(started!.isHost, isFalse);
  });

  testWidgets('join: a refused join shows the reason and lets the player try again', (t) async {
    tall(t);
    final scanner = _Scanner();
    const ad = LanAdvert(id: 'g1', name: 'Full game', address: '10.0.0.5', port: 1);
    scanner.list = [ad];
    await t.pumpWidget(wrap(LanLobby(
      host: false,
      services: LanServices(makeScanner: () => scanner, join: (_, __) async => throw LanJoinException('That game already has two players.')),
      onStart: (_) {},
      onCancel: () {},
    )));
    await t.pump();
    await t.tap(find.byKey(const Key('lan-game-g1')));
    await t.pump();
    await t.pump();
    expect(find.text('That game already has two players.'), findsOneWidget);
    expect(find.byKey(const Key('lan-game-g1')), findsOneWidget);
  });

  testWidgets('cancel calls back', (t) async {
    tall(t);
    var cancelled = 0;
    await t.pumpWidget(wrap(LanLobby(host: false, services: LanServices(makeScanner: _Scanner.new), onStart: (_) {}, onCancel: () => cancelled++, rnd: math.Random(1))));
    await t.pump();
    await t.tap(find.byKey(const Key('lan-cancel')));
    expect(cancelled, 1);
  });
}
