/// Only removes a fixture prefix from repository-style stream labels.
/// Keep provider names, language, quality and suffixes intact.
String conciseMatchLineLabel(String label) {
  final original = label.trim();
  final match = RegExp(
    r'^[^•·\n]{1,90}\s+(?:vs\.?|v)\s+[^•·\n]{1,90}\s*[•·]\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(original);
  final server = match?.group(1)?.trim() ?? '';
  return server.isEmpty ? original : server;
}
