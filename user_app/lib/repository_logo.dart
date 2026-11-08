import 'network_endpoints.dart';

String repositoryLogoUrl(String value) {
  final uri=Uri.tryParse(value);
  final id=uri?.host=='img.sofascore.com'?RegExp(r'^/api/v1/team/(\d+)/image$').firstMatch(uri!.path)?.group(1):null;
  return id==null?value:'$vercelBackupBase/team-logos/$id';
}
