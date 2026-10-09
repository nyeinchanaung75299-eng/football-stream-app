import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/native_playback_progress.dart';

void main() {
  test('no media progress times out even when the player is unpaused', () {
    final progress = NativePlaybackProgress();
    expect(
      progress.observePosition(Duration.zero, const Duration(seconds: 1)),
      isFalse,
    );
    expect(progress.timeoutReason(const Duration(seconds: 19)), isNull);
    expect(
      progress.timeoutReason(const Duration(seconds: 20)),
      'startup_timeout',
    );
  });

  test(
    'advancing media starts playback and frozen media eventually times out',
    () {
      final progress = NativePlaybackProgress();
      expect(
        progress.observePosition(
          const Duration(milliseconds: 500),
          const Duration(seconds: 3),
        ),
        isTrue,
      );
      expect(progress.startupElapsed, const Duration(seconds: 3));
      expect(
        progress.observePosition(
          const Duration(milliseconds: 500),
          const Duration(seconds: 27),
        ),
        isFalse,
      );
      expect(progress.timeoutReason(const Duration(seconds: 27)), isNull);
      expect(
        progress.timeoutReason(const Duration(seconds: 28)),
        'stall_timeout',
      );
      expect(
        progress.observePosition(
          const Duration(seconds: 1),
          const Duration(seconds: 29),
        ),
        isTrue,
      );
      expect(progress.timeoutReason(const Duration(seconds: 40)), isNull);
    },
  );

  test(
    'background and deliberate pauses neither time out nor inflate duration',
    () {
      final progress = NativePlaybackProgress();
      progress.setSuspended(true, const Duration(seconds: 5));
      expect(
        progress.observePosition(
          const Duration(seconds: 2),
          const Duration(seconds: 90),
        ),
        isFalse,
      );
      expect(progress.timeoutReason(const Duration(seconds: 90)), isNull);
      progress.setSuspended(false, const Duration(seconds: 95));
      expect(
        progress.activeElapsed(const Duration(seconds: 96)),
        const Duration(seconds: 6),
      );
      expect(progress.timeoutReason(const Duration(seconds: 109)), isNull);
      expect(
        progress.timeoutReason(const Duration(seconds: 110)),
        'startup_timeout',
      );
      progress.observePosition(
        const Duration(seconds: 1),
        const Duration(seconds: 111),
      );
      progress.setSuspended(true, const Duration(seconds: 115));
      progress.setSuspended(false, const Duration(seconds: 215));
      expect(progress.timeoutReason(const Duration(seconds: 235)), isNull);
      expect(
        progress.timeoutReason(const Duration(seconds: 236)),
        'stall_timeout',
      );
    },
  );

  test(
    'a new line has its own deadline and backwards seeks are not progress',
    () {
      final oldLine = NativePlaybackProgress();
      oldLine.observePosition(
        const Duration(seconds: 8),
        const Duration(seconds: 4),
      );
      final nextLine = NativePlaybackProgress();
      expect(nextLine.started, isFalse);
      expect(
        nextLine.timeoutReason(const Duration(seconds: 20)),
        'startup_timeout',
      );
      expect(
        oldLine.observePosition(Duration.zero, const Duration(seconds: 5)),
        isFalse,
      );
      expect(
        oldLine.observePosition(
          const Duration(milliseconds: 500),
          const Duration(seconds: 6),
        ),
        isTrue,
      );
      expect(oldLine.timeoutReason(const Duration(seconds: 30)), isNull);
    },
  );
}
