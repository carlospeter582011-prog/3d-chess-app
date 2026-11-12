import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Pure show/no-show rules, kept separate from the SDK so they can be unit-tested.
class AdGate {
  AdGate({this.cooldown = const Duration(minutes: 2)});

  /// Minimum time between two full-screen ads, so ads never come back to back.
  final Duration cooldown;

  DateTime? lastShown;

  /// True while any full-screen ad is on screen.
  bool showing = false;

  bool allows(DateTime now) =>
      !showing && (lastShown == null || now.difference(lastShown!) > cooldown);

  void markShown(DateTime now) {
    showing = true;
    lastShown = now;
  }

  void markDismissed() => showing = false;
}

/// Google Mobile Ads with Google's sample ad units. Chess stays playable when ads are unavailable.
class AdsService {
  static const appOpenTestId = 'ca-app-pub-3940256099942544/9257395921';
  static const interstitialTestId = 'ca-app-pub-3940256099942544/1033173712';
  static const bannerTestId = 'ca-app-pub-3940256099942544/9214589741';

  final AdGate _gate = AdGate();
  InterstitialAd? _interstitial;
  bool _initialized = false;
  bool _loadingInterstitial = false;
  bool _disposed = false;
  Future<void>? _initFuture;

  /// Initializes the SDK once and preloads the interstitial for the end of a game.
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      await MobileAds.instance.initialize();
      if (_disposed) return;
      _initialized = true;
      _loadInterstitial();
    } catch (_) {
      // Offline chess must always remain playable.
    }
  }

  /// Requests one App Open ad during startup. The app decides when its loading screen can give way
  /// to the menu. A response after that point, or after the deadline, is discarded.
  Future<void> requestLaunchAd({
    required Duration timeout,
    required bool Function() canShow,
    required void Function(bool) onVisibilityChanged,
  }) async {
    final stopwatch = Stopwatch()..start();
    bool withinDeadline() =>
        !_disposed && stopwatch.elapsed < timeout && canShow();

    try {
      await initialize().timeout(timeout);
      if (!_initialized || !withinDeadline()) return;
      await AppOpenAd.load(
        adUnitId: appOpenTestId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            final now = DateTime.now();
            if (!withinDeadline() || !_gate.allows(now)) {
              unawaited(ad.dispose());
              return;
            }
            _gate.markShown(now);
            onVisibilityChanged(true);
            unawaited(_showLaunchAd(ad, onVisibilityChanged));
          },
          onAdFailedToLoad: (_) {},
        ),
      );
    } catch (_) {
      // An unavailable launch ad must never hold up the menu.
    }
  }

  Future<void> _showLaunchAd(
    AppOpenAd ad,
    void Function(bool) onVisibilityChanged,
  ) async {
    var closed = false;
    void finish() {
      if (closed) return;
      closed = true;
      unawaited(ad.dispose());
      _gate.markDismissed();
      if (!_disposed) onVisibilityChanged(false);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, error) => finish(),
    );
    try {
      await ad.show();
    } catch (_) {
      finish();
    }
  }

  void _loadInterstitial() {
    if (!_initialized ||
        _disposed ||
        _loadingInterstitial ||
        _interstitial != null)
      return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialTestId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          if (_disposed) {
            ad.dispose();
            return;
          }
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) {
          _loadingInterstitial = false;
        },
      ),
    );
  }

  /// At most one ad per completed game, never during an active match.
  void onGameFinished() {
    final ad = _interstitial;
    final now = DateTime.now();
    if (ad == null || !_gate.allows(now)) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    _gate.markShown(now);
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _gate.markDismissed();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _gate.markDismissed();
        _loadInterstitial();
      },
    );
    ad.show();
  }

  void dispose() {
    _disposed = true;
    _interstitial?.dispose();
    _interstitial = null;
  }
}
