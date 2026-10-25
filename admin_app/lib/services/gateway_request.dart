import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GatewayResult {
  const GatewayResult(this.data, {this.base, this.statusCode});
  final dynamic data;
  final String? base;
  final int? statusCode;
}

/// Sequential failover for repeatable requests, with one deadline for all
/// routes and session refresh. Uncertain writes are never automatically sent
/// to another route after a timeout/network error.
class GatewayRequest {
  GatewayRequest({
    required this.bases,
    required this.send,
    required this.refresh,
    required this.direct,
    this.onFallback,
    this.totalTimeout,
    this.routeTimeout,
  });

  final List<String> bases;
  final Future<http.Response> Function(Uri uri, String bearer, Duration timeout)
      send;
  final Future<String?> Function() refresh;
  final Future<dynamic> Function() direct;
  final void Function(String reason)? onFallback;
  final Duration? totalTimeout;
  final Duration? routeTimeout;

  static bool canRetry(String functionName, Object? body) =>
      const {
        'source-match-list',
        'football-fixtures',
        'soco-links',
        'stream-health'
      }.contains(functionName) ||
      (functionName == 'system-monitor' &&
          body is Map &&
          body['action'] == 'summary');

  static String? _requestedSource(String functionName, Object? body) {
    if (!const {'source-match-list', 'soco-links'}.contains(functionName) ||
        body is! Map ||
        !body.containsKey('source')) {
      return null;
    }
    return (body['source'] ?? '').toString().trim().toLowerCase();
  }

  static bool _matchesRequestedSource(
      String functionName, Object? body, dynamic data) {
    final expected = _requestedSource(functionName, body);
    if (expected == null) return true;
    if (data is! Map ||
        (data['source'] ?? '').toString().trim().toLowerCase() != expected) {
      return false;
    }
    if (functionName != 'source-match-list') return true;

    final matches = data['matches'];
    if (matches is! List) return false;
    return matches.every((row) =>
        row is Map &&
        (row['source'] ?? '').toString().trim().toLowerCase() == expected);
  }

  Future<GatewayResult> run(String functionName, String token,
      {Object? body}) async {
    final repeatable = canRetry(functionName, body);
    final monitor = functionName == 'system-monitor';
    // Admin verified-source lookups include a provider catalog fetch plus
    // bounded manifest and sample checks. Give those legitimate requests
    // a little more gateway overhead without changing other CRUD timeouts.
    final verifiedSource = functionName == 'soco-links' &&
        body is Map &&
        const {'tflix', 'streame'}
            .contains(body['source']?.toString().toLowerCase()) &&
        body['action'] == 'streams';
    final limit = totalTimeout ??
        Duration(seconds: monitor ? 25 : verifiedSource ? 30 : 20);
    final perRoute = routeTimeout ??
        Duration(seconds: monitor ? 12 : verifiedSource ? 12 : 8);
    final elapsed = Stopwatch()..start();
    String accessToken = token;
    bool refreshed = false;
    bool phaseUsesRemainingBudget = false;

    Duration remaining([Duration? maximum]) {
      final left = limit - elapsed.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException('Connection timed out. Please retry.');
      }
      if (maximum != null && maximum < left) {
        phaseUsesRemainingBudget = false;
        return maximum;
      }
      phaseUsesRemainingBudget = true;
      return left;
    }

    for (final base in bases) {
      final uri = Uri.parse(
          '$base/admin/functions/${Uri.encodeComponent(functionName)}');
      http.Response response;
      try {
        var timeout = remaining(repeatable ? perRoute : null);
        response = await send(uri, accessToken, timeout).timeout(timeout);
        if (response.statusCode == 401 && !refreshed) {
          refreshed = true;
          final refreshTimeout = remaining(const Duration(seconds: 5));
          final nextToken = await refresh().timeout(refreshTimeout);
          if (nextToken != null && nextToken.isNotEmpty) {
            accessToken = nextToken;
            timeout = remaining(repeatable ? perRoute : null);
            response = await send(uri, accessToken, timeout).timeout(timeout);
          }
        }
      } catch (error) {
        if (!repeatable) {
          throw StateError(
              'Could not confirm the result. Refresh before trying again.');
        }
        // The phase timeout already consumed the final request budget. A
        // timer can fire just before Stopwatch reports the exact deadline;
        // that tiny remainder must not permit another route or auth error.
        if (error is TimeoutException && phaseUsesRemainingBudget) rethrow;
        onFallback?.call('gateway_network_error');
        remaining();
        continue;
      }

      dynamic decoded;
      if (response.body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          decoded = response.body;
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!_matchesRequestedSource(functionName, body, decoded)) {
          onFallback?.call('gateway_source_mismatch');
          remaining();
          continue;
        }
        return GatewayResult(decoded,
            base: base, statusCode: response.statusCode);
      }
      final missing = response.statusCode == 404;
      final unavailable = const {502, 503, 504}.contains(response.statusCode);
      if (missing || (repeatable && unavailable)) {
        onFallback?.call('gateway_http_${response.statusCode}');
        remaining();
        continue;
      }
      if (!repeatable && unavailable) {
        throw StateError(
            'Could not confirm the result. Refresh before trying again.');
      }
      final detail = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'HTTP ${response.statusCode}';
      throw Exception('Gateway error: $detail');
    }

    // The SDK fallback shares the same deadline; it cannot leave the UI
    // waiting indefinitely after the gateway attempts have finished.
    dynamic directData;
    try {
      final timeout = remaining();
      directData = await direct().timeout(timeout);
    } catch (_) {
      if (!repeatable) {
        throw StateError(
            'Could not confirm the result. Refresh before trying again.');
      }
      throw Exception('Could not connect. Check your connection and retry.');
    }
    if (!_matchesRequestedSource(functionName, body, directData)) {
      throw const FormatException(
          'The server returned data for a different stream source. Please retry.');
    }
    return GatewayResult(directData);
  }
}
