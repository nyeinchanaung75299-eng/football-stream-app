import 'function_gateway.dart';

class ConnectedChannelSource {
  Future<Map<String, dynamic>> request(String action,
      [Map<String, dynamic> fields = const {}]) async {
    final data = await FunctionGateway.invoke('channel-source-sync',
        body: {'action': action, ...fields});
    if (data is! Map || data['ok'] != true) {
      throw StateError('Channel source request failed.');
    }
    return Map<String, dynamic>.from(data);
  }
}
