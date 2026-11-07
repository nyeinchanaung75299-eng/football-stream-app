import 'function_gateway.dart';

class ConnectedChannelSource {
  ConnectedChannelSource({this.source = 'darkbyte'});
  final String source;
  Future<Map<String, dynamic>> request(String action,
      [Map<String, dynamic> fields = const {}]) async {
    final data = await FunctionGateway.invoke('channel-source-sync',
        body: {'action': action, if (source != 'darkbyte') 'source': source, ...fields});
    if (data is! Map || data['ok'] != true) {
      if (data is Map && data['code'] == 'drm_required') {
        throw StateError('This source needs a DRM configuration that is not provided. The saved channel was kept.');
      }
      throw StateError('Channel source request failed.');
    }
    return Map<String, dynamic>.from(data);
  }
}
