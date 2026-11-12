import 'package:chess3d/platform/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdGate', () {
    final t0 = DateTime(2026, 11, 10, 12);

    test('allows the first ad', () {
      expect(AdGate().allows(t0), isTrue);
    });

    test('never allows a second ad while one is on screen', () {
      final g = AdGate()..markShown(t0);
      expect(g.allows(t0.add(const Duration(hours: 1))), isFalse);
    });

    test('enforces the cooldown after an ad is dismissed', () {
      final g = AdGate()..markShown(t0);
      g.markDismissed();
      expect(g.allows(t0.add(const Duration(seconds: 30))), isFalse);
      expect(g.allows(t0.add(const Duration(minutes: 3))), isTrue);
    });
  });

  test('uses only the Google sample ad units', () {
    expect(
      AdsService.appOpenTestId,
      startsWith('ca-app-pub-3940256099942544/'),
    );
    expect(
      AdsService.interstitialTestId,
      startsWith('ca-app-pub-3940256099942544/'),
    );
    expect(AdsService.bannerTestId, startsWith('ca-app-pub-3940256099942544/'));
  });
}
