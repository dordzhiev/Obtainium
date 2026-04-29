import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

class Aptoide extends AppSource {
  Aptoide() {
    hosts = ['aptoide.com'];
    name = 'Aptoide';
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final RegExp standardUrlRegEx = RegExp(
      '^https?://([^\\.]+\\.){2,}${getSourceRegex(hosts)}',
      caseSensitive: false,
    );
    final RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    final appDetails = await getAppDetailsJSON(
      standardUrl,
      additionalSettings,
    );
    return appDetails['package'] as String?;
  }

  Future<Map<String, dynamic>> getAppDetailsJSON(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final idMatch = RegExp('"app":{"id":[0-9]+').firstMatch(res.body);
    String? id;
    if (idMatch != null) {
      id = res.body.substring(idMatch.start + 12, idMatch.end);
    } else {
      throw NoReleasesError();
    }
    final res2 = await sourceRequest(
      'https://ws2.aptoide.com/api/7/getApp/app_id/$id',
      additionalSettings,
    );
    if (res2.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final decoded = jsonDecode(res2.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(
      (decoded['nodes'] as Map<String, dynamic>)['meta'] is Map<String, dynamic>
          ? ((decoded['nodes'] as Map<String, dynamic>)['meta']
              as Map<String, dynamic>)['data'] as Map<String, dynamic>
          : ((decoded['nodes'] as Map)['meta'] as Map)['data'] as Map,
    );
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final appDetails = await getAppDetailsJSON(standardUrl, additionalSettings);
    final String appName = (appDetails['name'] as String?) ?? tr('app');
    final String author =
        ((appDetails['developer'] as Map<String, dynamic>?)?['name'] as String?) ??
        name;
    final String? dateStr = appDetails['updated'] as String?;
    final fileDetails = appDetails['file'] as Map<String, dynamic>?;
    final String? version = fileDetails?['vername'] as String?;
    final String? apkUrl = fileDetails?['path'] as String?;
    if (version == null) {
      throw NoVersionError();
    }
    if (apkUrl == null) {
      throw NoAPKError();
    }
    DateTime? relDate;
    if (dateStr != null) {
      relDate = DateTime.parse(dateStr);
    }

    return APKDetails(
      version,
      getApkUrlsFromUrls([apkUrl]),
      AppNames(author, appName),
      releaseDate: relDate,
    );
  }
}
