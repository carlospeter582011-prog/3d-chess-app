// Menu, HUD and dialogs as widgets.

import 'package:chess3d/chess/types.dart';
import 'package:chess3d/chess/uci_engine.dart';
import 'package:chess3d/game/game_controller.dart';
import 'package:chess3d/game/settings.dart';
import 'package:chess3d/game/storage.dart';
import 'package:chess3d/scene/board_model.dart';
import 'package:chess3d/ui/dialogs.dart';
import 'package:chess3d/ui/hud.dart';
import 'package:chess3d/ui/menu.dart';
import 'package:chess3d/ui/theme.dart';
import 'package:flutter/material.dart';
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

Widget host(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

bool noOverflow(WidgetTester t) => t.takeException() == null;

void useTallScreen(WidgetTester t) {
  t.view.physicalSize = const Size(450, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('Menu', () {
    Widget menu({
      required ValueNotifier<Settings> settings,
      required List<Settings> started,
      List<SavedGame> slots = const [],
      bool hasActive = false,
      VoidCallback? onContinue,
      void Function(SavedGame)? onResumeSlot,
      void Function(String)? onDeleteSlot,
    }) =>
        host(ValueListenableBuilder<Settings>(
          valueListenable: settings,
          builder: (_, s, __) => MenuScreen(
            settings: s,
            onSettings: (n) => settings.value = n,
            slots: slots,
            now: () => DateTime.fromMillisecondsSinceEpoch(10 * 60 * 1000),
            hasActive: hasActive,
            onStart: started.add,
            onContinue: onContinue ?? () {},
            onResumeSlot: onResumeSlot ?? (_) {},
            onDeleteSlot: onDeleteSlot ?? (_) {},
            onOpenSettings: () {},
            onHost: () {},
            onJoin: () {},
          ),
        ));

    testWidgets('shows bot options by default and starts with the chosen settings', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      final started = <Settings>[];
      await t.pumpWidget(menu(settings: settings, started: started));
      expect(find.text('3D Chess'), findsOneWidget);
      expect(find.byKey(const Key('elo-slider')), findsOneWidget);
      expect(find.text('1200 Elo'), findsOneWidget);
      await t.tap(find.byKey(const Key('elo-2000')));
      await t.pump();
      expect(find.text('2000 Elo'), findsOneWidget);
      await t.tap(find.text('♚ Black'));
      await t.pump();
      await t.tap(find.byKey(const Key('start')));
      expect(started.single.elo, 2000);
      expect(started.single.humanColor, HumanColor.black);
      expect(started.single.mode, GameMode.bot);
    });

    testWidgets('2 players hides the bot strength controls', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      await t.pumpWidget(menu(settings: settings, started: []));
      await t.tap(find.textContaining('1 phone'));
      await t.pump();
      expect(settings.value.mode, GameMode.local);
      expect(find.byKey(const Key('elo-slider')), findsNothing);
      expect(find.byKey(const Key('color-seg')), findsNothing);
    });

    testWidgets('clock: off by default, switch on and type the time and increment, switch off again', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      await t.pumpWidget(menu(settings: settings, started: []));
      expect(t.widget<Text>(find.byKey(const Key('clock-label'))).data, 'Off');
      expect(find.byKey(const Key('clock-min')), findsNothing);
      expect(find.byKey(const Key('clock-custom')), findsNothing); // no presets, no Custom button
      await t.ensureVisible(find.byKey(const Key('clock-switch')));
      await t.tap(find.byKey(const Key('clock-switch')));
      await t.pump();
      expect(settings.value.timeMin, 5);
      await t.enterText(find.byKey(const Key('clock-min')), '7');
      await t.enterText(find.byKey(const Key('clock-inc')), '4');
      await t.pump();
      expect(settings.value.timeMin, 7);
      expect(settings.value.incSec, 4);
      expect(t.widget<Text>(find.byKey(const Key('clock-label'))).data, '7 min + 4s');
      await t.tap(find.byKey(const Key('clock-switch')));
      await t.pump();
      expect(settings.value.timeMin, 0);
      expect(find.byKey(const Key('clock-min')), findsNothing);
    });

    testWidgets('slider changes the Elo within 400..3200', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      await t.pumpWidget(menu(settings: settings, started: []));
      final slider = find.byKey(const Key('elo-slider'));
      await t.drag(slider, const Offset(-2000, 0));
      await t.pump();
      expect(settings.value.elo, 400);
      await t.drag(slider, const Offset(4000, 0));
      await t.pump();
      expect(settings.value.elo, 3200);
    });

    testWidgets('saved games are listed with continue and delete; an active game offers to go back', (t) async {
      useTallScreen(t);
      final settings = ValueNotifier(const Settings());
      final g1 = SavedGame(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1500), const ['e2e4', 'e7e5'], id: 'a', ts: 7 * 60 * 1000);
      final g2 = SavedGame(const GameConfig(mode: GameMode.local, timeSec: 300, incSec: 2), const ['d2d4'], id: 'b', ts: 1 * 60 * 1000);
      final resumed = <String>[], deleted = <String>[];
      var continued = 0;
      await t.pumpWidget(menu(settings: settings, started: [], slots: [g1, g2], onResumeSlot: (g) => resumed.add(g.id), onDeleteSlot: deleted.add));
      expect(find.text('SAVED GAMES (2/3)'), findsOneWidget);
      expect(find.textContaining('Bot 1500'), findsOneWidget);
      expect(find.textContaining('3 min ago'), findsOneWidget);
      expect(find.textContaining('5 min + 2s'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('slot-a')));
      await t.tap(find.byKey(const Key('slot-a')));
      expect(resumed, ['a']);
      await t.ensureVisible(find.byKey(const Key('slot-del-b')));
      await t.tap(find.byKey(const Key('slot-del-b')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('slot-del-no')));
      await t.pumpAndSettle();
      expect(deleted, isEmpty);
      await t.tap(find.byKey(const Key('slot-del-b')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('slot-del-yes')));
      await t.pumpAndSettle();
      expect(deleted, ['b']);

      await t.pumpWidget(menu(settings: settings, started: [], hasActive: true, onContinue: () => continued++));
      expect(find.textContaining('SAVED GAMES'), findsNothing);
      await t.ensureVisible(find.byKey(const Key('continue')));
      await t.tap(find.byKey(const Key('continue')));
      expect(continued, 1);
    });

    testWidgets('no continue buttons on a fresh install', (t) async {
      useTallScreen(t);
      await t.pumpWidget(menu(settings: ValueNotifier(const Settings()), started: []));
      expect(find.textContaining('SAVED GAMES'), findsNothing);
      expect(find.byKey(const Key('continue')), findsNothing);
    });
  });

  group('HUD helpers', () {
    test('status text', () {
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200));
      expect(statusText(g.snapshot).text, 'Your move');
      final g2 = newGame();
      g2.start(const GameConfig(mode: GameMode.local));
      expect(statusText(g2.snapshot).text, 'White to move');
      g2.debugLoadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(statusText(g2.snapshot).text, 'Draw · Stalemate');
      g2.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      expect(statusText(g2.snapshot).text, 'Checkmate · White wins');
      g2.debugLoadFen('4k3/8/8/8/8/8/4r3/R3K3 w - - 0 1');
      expect(statusText(g2.snapshot).tone, 'check');
      expect(statusText(g2.snapshot).text, 'White is in check!');
    });
  });

  group('HUD', () {
    Widget hud(GameController g, {VoidCallback? onMenu}) => host(ListenableBuilder(
          listenable: g,
          builder: (_, __) => Hud(
            game: g,
            snapshot: g.snapshot,
            board: g.board,
            onMenu: onMenu ?? () {},
            onSettings: () {},
          ),
        ));

    testWidgets('shows the status and both players, but no move list or captured pieces', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1800));
      await t.pumpWidget(hud(g));
      expect(find.text('Your move'), findsOneWidget);
      expect(find.text('Bot · 1800'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Moves appear here'), findsNothing);
      g.tap('e2');
      g.tap('e4');
      await t.pump();
      await t.pump();
      expect(find.textContaining('1. e4'), findsNothing);
    });

    testWidgets('a timed game shows both clocks, an untimed one none', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local, timeSec: 300));
      await t.pumpWidget(hud(g));
      expect(find.byKey(const Key('clock-w')), findsOneWidget);
      expect(find.byKey(const Key('clock-b')), findsOneWidget);
      expect(find.text('5:00'), findsNWidgets(2));
      await t.pumpWidget(const SizedBox()); // the clock timer must be gone before the test ends
      g.dispose();
      final g2 = newGame();
      addTearDown(g2.dispose);
      g2.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(hud(g2));
      expect(find.byKey(const Key('clock-w')), findsNothing);
    });

    testWidgets('undo is disabled at the start', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(hud(g));
      expect(g.snapshot.canUndo, isFalse);
      g.tap('e2');
      g.tap('e4');
      await t.pump();
      await t.pump();
      expect(g.snapshot.canUndo, isTrue);
      await t.tap(find.byKey(const Key('btn-undo')));
      await t.pump();
      expect(g.snapshot.history, isEmpty);
    });

    testWidgets('resign asks for confirmation and then ends the game', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200));
      await t.pumpWidget(hud(g));
      await t.tap(find.byKey(const Key('btn-resign')));
      await t.pumpAndSettle();
      expect(find.text('Resign?'), findsOneWidget);
      expect(g.snapshot.status, GameStatus.playing);
      await t.tap(find.byKey(const Key('confirm-yes')));
      await t.pumpAndSettle();
      expect(g.snapshot.status, GameStatus.resigned);
      expect(find.textContaining('Black wins'), findsOneWidget);
    });

    testWidgets('2 players has draw and resign buttons; menu button calls back', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      var menu = 0;
      await t.pumpWidget(hud(g, onMenu: () => menu++));
      expect(find.byKey(const Key('btn-draw')), findsOneWidget);
      expect(find.byKey(const Key('btn-resign')), findsOneWidget);
      await t.tap(find.byTooltip('Menu'));
      expect(menu, 1);
    });

    testWidgets('flip button turns the camera to the other side', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(hud(g));
      expect(g.board.viewSide(), Side.w);
      await t.tap(find.byKey(const Key('btn-flip')));
      expect(g.board.viewSide(), Side.b);
    });

    testWidgets('after the game the rematch button replaces resign', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      g.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      await t.pumpWidget(hud(g));
      expect(find.byKey(const Key('btn-rematch')), findsOneWidget);
      expect(find.byKey(const Key('btn-resign')), findsNothing);
    });

    testWidgets('wide layout renders without overflow', (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      await t.pumpWidget(host(Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 340,
          child: ListenableBuilder(
            listenable: g,
            builder: (_, __) => Hud(game: g, snapshot: g.snapshot, board: g.board, onMenu: () {}, onSettings: () {}, wide: true),
          ),
        ),
      )));
      expect(t.takeException(), isNull);
    });
  });

  group('landscape phone HUD', () {
    for (final size in const [Size(800, 360), Size(732, 412), Size(640, 320), Size(900, 400)]) {
      testWidgets('side panel fits ${size.width.toInt()}x${size.height.toInt()} without overflow', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final g = newGame();
        g.start(const GameConfig(mode: GameMode.local));
        final panel = (size.width * 0.36).clamp(250.0, 340.0);
        await t.pumpWidget(host(Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panel,
            child: ListenableBuilder(
              listenable: g,
              builder: (_, __) => Hud(game: g, snapshot: g.snapshot, board: g.board, onMenu: () {}, onSettings: () {}, wide: true),
            ),
          ),
        )));
        expect(t.takeException(), isNull);
        // everything the player needs is on screen
        for (final k in ['btn-undo', 'btn-flip', 'btn-top', 'btn-reset', 'btn-draw', 'btn-resign', 'status']) {
          final r = t.getRect(find.byKey(Key(k)));
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$k below the screen');
          expect(r.right, lessThanOrEqualTo(size.width), reason: '$k right of the screen');
        }
      });
    }
  });

  group('dialogs', () {
    testWidgets('promotion picker offers queen, rook, bishop, knight', (t) async {
      useTallScreen(t);
      PT? chosen;
      await t.pumpWidget(host(PromotionDialog(side: Side.w, onChoose: (p) => chosen = p, onCancel: () {})));
      for (final k in ['q', 'r', 'b', 'n']) {
        expect(find.byKey(Key('promo-$k')), findsOneWidget);
      }
      expect(find.byKey(const Key('promo-k')), findsNothing);
      expect(find.byKey(const Key('promo-p')), findsNothing);
      await t.tap(find.byKey(const Key('promo-n')));
      expect(chosen, PT.n);
    });

    test('result titles', () async {
      final bot = newGame()..start(const GameConfig(mode: GameMode.bot, humanColor: Side.w, elo: 1200));
      bot.resign();
      expect(resultTitle(bot.snapshot), 'Bot wins');
      final local = newGame()..start(const GameConfig(mode: GameMode.local));
      local.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      expect(resultTitle(local.snapshot), 'White wins!');
      local.debugLoadFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(resultTitle(local.snapshot), 'Draw');
    });

    testWidgets('result dialog buttons', (t) async {
      useTallScreen(t);
      final g = newGame()..start(const GameConfig(mode: GameMode.local));
      g.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      var rematch = 0, menu = 0, close = 0;
      await t.pumpWidget(host(ResultDialog(snapshot: g.snapshot, onRematch: () => rematch++, onMenu: () => menu++, onClose: () => close++)));
      expect(find.text('White wins!'), findsOneWidget);
      await t.tap(find.byKey(const Key('rematch')));
      await t.tap(find.text('Menu'));
      await t.tap(find.text('View board'));
      expect([rematch, menu, close], [1, 1, 1]);
    });

    testWidgets('settings dialog reports changes immediately', (t) async {
      useTallScreen(t);
      var current = const Settings();
      await t.pumpWidget(host(SettingsDialog(settings: current, onChanged: (s) => current = s)));
      await t.tap(find.byKey(const Key('set-sound')));
      await t.pump();
      expect(current.sound, isFalse);
      await t.tap(find.byKey(const Key('set-labels')));
      await t.pump();
      expect(current.labels, isFalse);
      await t.tap(find.byKey(const Key('set-flip')));
      await t.pump();
      expect(current.autoFlip, isTrue);
      expect(find.text('Show move list'), findsNothing); // the move list and captured pieces are gone
      await t.ensureVisible(find.byKey(const Key('set-haptics')));
      await t.tap(find.byKey(const Key('set-haptics')));
      await t.pump();
      expect(current.haptics, isTrue);
      await t.ensureVisible(find.byKey(const Key('set-room-night')));
      await t.tap(find.byKey(const Key('set-room-night')));
      await t.pump();
      expect(current.room, Room.night);
      await t.ensureVisible(find.byKey(const Key('set-name')));
      await t.enterText(find.byKey(const Key('set-name')), 'Sam');
      await t.pump();
      expect(current.playerName, 'Sam');
      await t.ensureVisible(find.byKey(const Key('set-pack')));
      await t.tap(find.byKey(const Key('set-pack')));
      await t.pumpAndSettle();
      await t.tap(find.text('Glass').last);
      await t.pumpAndSettle();
      expect(current.soundPack, SoundPack.glass);
    });

    testWidgets('result card: Rematch has its own line and no label is cut', (t) async {
      useTallScreen(t);
      final g = newGame();
      g.start(const GameConfig(mode: GameMode.local));
      g.debugLoadFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      await t.pumpWidget(host(ResultDialog(snapshot: g.snapshot, onRematch: () {}, onMenu: () {}, onClose: () {})));
      final rematch = t.getSize(find.byKey(const Key('rematch')));
      final view = t.getSize(find.byKey(const Key('view-board')));
      expect(rematch.width, greaterThan(view.width)); // full width, not squeezed into a third
      for (final label in ['Rematch', 'View board', 'Menu']) {
        expect(find.textContaining(label), findsOneWidget);
      }
      expect(noOverflow(t), isTrue);
    });
  });
}

