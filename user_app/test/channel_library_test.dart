import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/channel_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('favorites survive reload and recently watched is distinct and bounded', () async {
    final library = ChannelLibrary();
    await library.toggleFavorite('channel-a');
    for (var i = 0; i < 35; i++) { await library.recordRecent('channel-$i'); }
    await library.recordRecent('channel-10');
    final restored = ChannelLibrary();
    await restored.load();
    expect(restored.favorites, {'channel-a'});
    expect(restored.recent.length, 30);
    expect(restored.recent.first, 'channel-10');
    expect(restored.recent.toSet().length, 30);
    await restored.toggleFavorite('channel-a');
    expect(restored.favorites, isEmpty);
  });
}
