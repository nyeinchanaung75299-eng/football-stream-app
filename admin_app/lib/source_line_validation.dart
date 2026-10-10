import 'services/manual_source_url.dart';

Map<String, String?> sourceLineKeyFields(Map<String, dynamic> line) {
  // Existing providers may omit keys entirely. An update must then preserve
  // the administrator's current pair rather than replace it with nulls.
  if (!line.containsKey('key_id') && !line.containsKey('key_data')) return {};
  String? normalized(dynamic value) {
    final text = value?.toString().trim().replaceAll('-', '') ?? '';
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(text)
        ? text.toLowerCase()
        : null;
  }

  if (line['stream_type']?.toString().toLowerCase() == 'dash') {
    final id = normalized(line['key_id']);
    final data = normalized(line['key_data']);
    if (id != null && data != null) {
      return {'key_id': id, 'key_data': data};
    }
  }
  if (line.containsKey('key_id') &&
      line.containsKey('key_data') &&
      (line['key_id']?.toString().trim().isEmpty ?? true) &&
      (line['key_data']?.toString().trim().isEmpty ?? true)) {
    return {'key_id': null, 'key_data': null};
  }
  return {};
}

bool isVerifiedTflixLine(Map<String, dynamic> line, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final uri = Uri.tryParse(line['url']?.toString().trim() ?? '');
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !const {'hls', 'dash'}
          .contains(line['stream_type']?.toString().toLowerCase()) ||
      !isValidManualStreamUrl(uri.toString(),
          streamType: line['stream_type'].toString().toLowerCase()) ||
      line['media_verified'] != true ||
      !const {'healthy', 'slow'}
          .contains(line['health_status']?.toString().toLowerCase())) {
    return false;
  }

  final checkedAt =
      DateTime.tryParse(line['checked_at']?.toString() ?? '')?.toUtc();
  if (checkedAt == null ||
      current.difference(checkedAt) > const Duration(minutes: 10) ||
      checkedAt.difference(current) > const Duration(minutes: 1)) {
    return false;
  }

  final expiryText = line['expires_at']?.toString().trim() ?? '';
  if (expiryText.isNotEmpty) {
    final expiry = DateTime.tryParse(expiryText)?.toUtc();
    if (expiry == null ||
        !expiry.isAfter(current.add(const Duration(seconds: 15)))) {
      return false;
    }
  }

  final hasKey = (line['key_id']?.toString().trim().isNotEmpty ?? false) ||
      (line['key_data']?.toString().trim().isNotEmpty ?? false);
  if (hasKey && sourceLineKeyFields(line)['key_id'] == null) return false;
  return true;
}
