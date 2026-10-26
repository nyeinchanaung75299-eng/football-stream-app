// A catalog ID contains only a public channel slug. Do not use a media URL,
// embed URL, or caller-supplied destination as an external navigation target.
String? tflixPublicChannelPage(Object? sourceId) {
  final id = sourceId?.toString() ?? '';
  final match = RegExp(
    r'^channel:([a-z0-9][a-z0-9_-]{0,159})$',
    caseSensitive: false,
  ).firstMatch(id);
  if (match == null) return null;
  return 'https://tflix.su/channel/${match.group(1)}';
}
