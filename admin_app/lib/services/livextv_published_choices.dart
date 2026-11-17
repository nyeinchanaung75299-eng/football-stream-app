/// Accept only selectors that the provider already published for this exact
/// event. A Watch selector is navigation metadata, not a verified media line.
/// Do not synthesize ?s= slots or accept player/credential URLs.
List<Map<String, dynamic>> liveXtvPublishedQualityOptions(
  dynamic raw,
  String eventPageUrl,
) {
  final event = Uri.tryParse(eventPageUrl.trim());
  const hosts = {'livextv.pro', 'www.livextv.pro'};
  if (event == null ||
      event.scheme != 'https' ||
      !hosts.contains(event.host) ||
      event.userInfo.isNotEmpty ||
      (event.hasPort && event.port != 443) ||
      !RegExp(r'^/watch/[1-9]\d{0,11}/?$').hasMatch(event.path) ||
      raw is! List) {
    return const [];
  }

  String eventPath(Uri uri) =>
      uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;

  final found = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final url = Uri.tryParse(entry['watch_url']?.toString() ?? '');
    final name = entry['nick_name']?.toString().trim() ?? '';
    final room = entry['room_num']?.toString().trim() ?? '';
    if (url == null ||
        url.scheme != 'https' ||
        !hosts.contains(url.host) ||
        url.userInfo.isNotEmpty ||
        (url.hasPort && url.port != 443) ||
        eventPath(url) != eventPath(event) ||
        url.queryParameters.length != 1 ||
        !url.queryParameters.containsKey('s') ||
        url.queryParametersAll['s']?.length != 1 ||
        !RegExp(r'^[1-9]\d?$').hasMatch(url.queryParameters['s'] ?? '') ||
        url.fragment.isNotEmpty ||
        name.isEmpty ||
        room.isEmpty) {
      continue;
    }
    if (!seen.add(url.queryParameters['s']!)) continue;
    found.add({
      'room_num': room,
      'page_url': event.replace(query: '', fragment: '').toString(),
      'watch_url': url.toString(),
      'nick_name': name,
    });
    if (found.length >= 12) break;
  }
  return found;
}
