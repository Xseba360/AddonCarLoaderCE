import 'dart:convert';
import 'dart:io';

const _latestRelease = 'https://api.github.com/repos/Xseba360/AddonCarLoaderCE/releases/latest';

/// The newest GitHub release as (version, page): the tag without its "v", and the release's page.
/// Null when nothing has been released yet. Throws when GitHub cannot be reached.
Future<(String, String)?> latestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(_latestRelease));
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'AddonCarManagerCE') // GitHub refuses requests without one
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw HttpException('GitHub answered ${response.statusCode}');
    return parseRelease(body);
  } finally {
    client.close(force: true);
  }
}

/// (version, page) from the release JSON GitHub returns.
(String, String) parseRelease(String json) {
  final release = jsonDecode(json) as Map<String, dynamic>;
  return ((release['tag_name'] as String).replaceFirst(RegExp('^[vV]'), ''), release['html_url'] as String);
}

/// Whether [latest] is a higher dotted version than [current] ("0.10.0" is newer than "0.9.2").
bool isNewer(String latest, String current) {
  List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0];
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
