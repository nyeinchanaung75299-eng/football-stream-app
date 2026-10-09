import 'dart:convert';

import 'function_gateway.dart';

class SystemMonitorService {
  static Future<Map<String, dynamic>> load() async {
    final response = await FunctionGateway.invoke('system-monitor',
        body: const {'action': 'summary'});
    if (response is! Map || response['services'] is! List) {
      throw StateError('Monitoring response was incomplete.');
    }
    return Map<String, dynamic>.from(response);
  }

  static Future<void> connect(
      String provider, Map<String, String> config, String secret) async {
    final response = await FunctionGateway.invoke('system-monitor', body: {
      'action': 'connect',
      'provider': provider,
      'config': config,
      'secret': secret
    });
    if (response is! Map || response['ok'] != true) {
      throw StateError('The service could not be connected.');
    }
  }

  // Export counts/status only, without stack traces or user/session IDs.
  static Map<String, dynamic> exportSummary(Map<String, dynamic> data) => {
        'version': 1,
        'generatedAt': data['generatedAt'],
        'windowHours': data['windowHours'],
        'services': [
          for (final s in (data['services'] as List? ?? const []))
            {
              'service': s['id'],
              'state': s['state'],
              'collectedAt': s['collectedAt'],
              if (s['metrics'] != null) 'metrics': s['metrics'],
              if (s['events'] != null) 'events': s['events'],
              if (s['timing'] != null)
                'timing': {
                  'state': s['timing']['state'],
                  'rows': s['timing']['rows'],
                },
              if (s['runs'] != null)
                'builds': [
                  for (final r in s['runs'])
                    {
                      'workflow': r['workflow'],
                      'state': r['state'],
                      'sha': r['sha']
                    },
                ],
            },
        ],
        if (data['streams'] != null)
          'streamHealth': {
            'counts': data['streams']['counts'],
            'total': data['streams']['total'],
            'truncated': data['streams']['truncated'],
          },
      };

  static String reportJson(Map<String, dynamic> data) =>
      const JsonEncoder.withIndent('  ').convert(exportSummary(data));

  static String reportCsv(Map<String, dynamic> data) {
    String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final lines = <String>['service,state,metric,value,collected_at'];
    for (final s in exportSummary(data)['services'] as List) {
      final metrics = Map<String, dynamic>.from(s['metrics'] ?? {});
      for (final e in (s['events'] as List? ?? const [])) {
        metrics[e['event'].toString()] = e['count'];
        metrics['${e['event']} affected users'] = e['affectedUsers'];
      }
      for (final t in (s['timing']?['rows'] as List? ?? const [])) {
        final label =
            '${t['event']} ${t['phase']} ${t['app']} ${t['platform']}';
        metrics['$label samples'] = t['samples'];
        metrics['$label p50 ms'] = t['p50Ms'];
        metrics['$label p95 ms'] = t['p95Ms'];
      }
      if (metrics.isEmpty) metrics['status'] = s['state'];
      for (final entry in metrics.entries) {
        lines.add([
          s['service'],
          s['state'],
          entry.key,
          entry.value,
          s['collectedAt']
        ].map(cell).join(','));
      }
    }
    return lines.join('\n');
  }
}
