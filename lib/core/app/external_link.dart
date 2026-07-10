import 'package:querya_desktop/core/app/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser.
Future<bool> launchExternalUrl(String url) {
  final uri = Uri.parse(url);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> launchRepositoryUrl() => launchExternalUrl(AppLinks.repository);

Future<bool> launchDocumentationUrl() =>
    launchExternalUrl(AppLinks.documentation);
