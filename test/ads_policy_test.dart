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

    test('an App Open ad expires after 4 hours', () {
      expect(AdGate.appOpenExpired(t0, t0.add(const Duration(hours: 3, minutes: 59))), isFalse);
      expect(AdGate.appOpenExpired(t0, t0.add(const Duration(hours: 4))), isTrue);
    });
  });

  test('uses only the Google sample ad units', () {
    expect(AdsService.appOpenTestId, startsWith('ca-app-pub-3940256099942544/'));
    expect(AdsService.interstitialTestId, startsWith('ca-app-pub-3940256099942544/'));
  });

  test('the launch-ad step never blocks the intro when ads are unavailable', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final ads = AdsService();
    final sw = Stopwatch()..start();
    await ads.showColdStartAd(timeout: const Duration(seconds: 2)).timeout(const Duration(seconds: 4));
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    ads.dispose();
  });
}
