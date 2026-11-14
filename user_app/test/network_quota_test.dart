import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/network_endpoints.dart';
import 'package:football_viewer/repository_logo.dart';

void main() {
  test(
    'a slow successful Cloudflare read does not invoke the speculative Vercel hedge',
    () async {
      final slow = Completer<String>();
      var backup = 0;
      final jobs = publicApiRequests<String>(
        [cloudflarePublicBase, vercelBackupBase],
        (base) => base == vercelBackupBase
            ? Future.value('backup-${++backup}')
            : slow.future,
      );
      final primary = jobs[0]();
      final hedge = jobs[1]();
      await Future<void>.delayed(Duration.zero);
      expect(backup, 0);
      slow.complete('current catalog');
      expect(await primary, 'current catalog');
      expect(await hedge, 'current catalog');
      expect(backup, 0);
    },
  );
  test(
    'failed Cloudflare aliases allow one operator fallback while a verified operator-first route starts immediately',
    () async {
      var backup = 0;
      final jobs = publicApiRequests<String>(
        [cloudflarePublicBase, vercelBackupBase],
        (base) async {
          if (base == vercelBackupBase) return 'backup-${++backup}';
          throw StateError('Blocked');
        },
      );
      await expectLater(jobs[0](), throwsStateError);
      expect(await jobs[1](), 'backup-1');
      final preferred = publicApiRequests<String>([
        vercelBackupBase,
        cloudflarePublicBase,
      ], (base) async => base);
      expect(await preferred[0](), vercelBackupBase);
    },
  );
  const id = '11111111-1111-4111-8111-111111111111';
  const asset =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/main/public/channel-logos/fixture.png';
  test('reviewed static logos avoid both Vercel and Worker function calls', () {
    expect(channelLogoUrl(asset, channelId: id), asset);
    final old =
        '$vercelBackupBase/api/channel-logo?id=$id&v=${Uri.encodeComponent(asset)}';
    expect(channelLogoUrl(old, channelId: id), asset);
  });
  test(
    'direct images stay direct while legacy relays use a fixed channel lookup',
    () {
      const external = 'https://images.example/logo.png';
      expect(channelLogoUrl(external, channelId: id), external);
      final legacy =
          '$vercelBackupBase/api/channel-logo?id=$id&v=${Uri.encodeComponent(external)}';
      final url = Uri.parse(channelLogoUrl(legacy, channelId: id));
      expect(url.origin, Uri.parse(independentPublicBase).origin);
      expect(
        url.path,
        '${Uri.parse(independentPublicBase).path}/channel-logos/$id',
      );
      expect(url.queryParameters.keys, containsAll(['apikey', 'v']));
      expect(url.queryParameters['apikey'], viewerPublicApiKey);
      expect(url.queryParameters['v'], matches(RegExp(r'^[a-f0-9]{24}$')));
      expect(
        repositoryLogoUrl('https://img.sofascore.com/api/v1/team/123/image'),
        independentImageUrl('/team-logos/123'),
      );
      expect(
        repositoryLogoUrl('$vercelBackupBase/team-logos/123'),
        independentImageUrl('/team-logos/123'),
      );
    },
  );
  test(
    'supported Cloudflare aliases precede Vercel without dropping the operator backup',
    () {
      final bases = publicApiBases();
      expect(bases.first, cloudflarePublicBase);
      expect(bases.last, vercelBackupBase);
      expect(bases.toSet().length, bases.length);
      expect(bases.any((base) => base.endsWith('.workers.dev')), false);
    },
  );
}
