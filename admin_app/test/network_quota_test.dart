import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/network_endpoints.dart';
import 'package:football_admin/services/repository_logo.dart';

void main() {
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
      'external images use a fixed channel lookup, never an arbitrary URL proxy',
      () {
    final url = Uri.parse(
        channelLogoUrl('https://images.example/logo.png', channelId: id));
    expect(url.origin, cloudflarePublicBase);
    expect(url.path, '/channel-logos/$id');
    expect(url.queryParameters.keys, ['v']);
    expect(url.queryParameters['v'], matches(RegExp(r'^[a-f0-9]{24}$')));
    expect(repositoryLogoUrl('https://img.sofascore.com/api/v1/team/123/image'),
        '$cloudflarePublicBase/team-logos/123');
    expect(repositoryLogoUrl('$vercelBackupBase/team-logos/123'),
        '$cloudflarePublicBase/team-logos/123');
  });
  test(
      'supported Cloudflare aliases precede Vercel without dropping the operator backup',
      () {
    final bases = publicApiBases();
    expect(bases.first, cloudflarePublicBase);
    expect(bases.last, vercelBackupBase);
    expect(bases.toSet().length, bases.length);
    expect(bases.any((base) => base.endsWith('.workers.dev')), false);
  });
}
