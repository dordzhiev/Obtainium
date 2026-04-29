import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';

extension Unique<E, Id> on List<E> {
  List<E> unique([Id Function(E element)? id, bool inplace = true]) {
    final ids = <dynamic>{};
    final list = inplace ? this : List<E>.from(this);
    list.retainWhere((x) => ids.add(id != null ? id(x) : x as Id));
    return list;
  }
}

class APKPure extends AppSource {
  APKPure() {
    hosts = ['apkpure.net', 'apkpure.com'];
    allowSubDomains = true;
    naiveStandardVersionDetection = true;
    showReleaseDateAsVersionToggle = true;
    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch(
          'fallbackToOlderReleases',
          label: tr('fallbackToOlderReleases'),
          defaultValue: true,
        ),
      ],
      [
        GeneratedFormSwitch(
          'stayOneVersionBehind',
          label: tr('stayOneVersionBehind'),
        ),
      ],
      [
        GeneratedFormSwitch(
          'useFirstApkOfVersion',
          label: tr('useFirstApkOfVersion'),
          defaultValue: true,
        ),
      ],
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final RegExp standardUrlRegExB = RegExp(
      '^https?://m.${getSourceRegex(hosts)}(/+[^/]{2})?/+[^/]+/+[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegExB.firstMatch(url);
    if (match != null) {
      final uri = Uri.parse(url);
      url = 'https://${uri.host.substring(2)}${uri.path}';
    }
    final RegExp standardUrlRegExA = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}(/+[^/]{2})?/+[^/]+/+[^/]+',
      caseSensitive: false,
    );
    match = standardUrlRegExA.firstMatch(url);
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
    return Uri.parse(standardUrl).pathSegments.last;
  }

  Future<APKDetails> getDetailsForVersion(
    List<Map<String, dynamic>> versionVariants,
    List<String> supportedArchs,
    Map<String, dynamic> additionalSettings,
  ) async {
    var apkUrls = versionVariants
        .map((e) {
          final String appId = e['package_name'] as String;
          final String versionCode = e['version_code'] as String;

          List<String> architectures =
              (e['native_code'] as List<dynamic>? ?? []).cast<String>();
          final String architectureString = architectures.join(',');
          if (architectures.contains("universal") ||
              architectures.contains("unlimited")) {
            architectures = [];
          }
          if (additionalSettings['autoApkFilterByArch'] == true &&
              architectures.isNotEmpty &&
              architectures.where((a) => supportedArchs.contains(a)).isEmpty) {
            return null;
          }

          final asset = e['asset'] as Map<String, dynamic>;
          final String type = asset['type'] as String;
          final String downloadUri = asset['url'] as String;

          return MapEntry(
            '$appId-$versionCode-$architectureString.${type.toLowerCase()}',
            downloadUri,
          );
        })
        .nonNulls
        .toList()
        .unique((e) => e.key);

    if (apkUrls.isEmpty) {
      throw NoAPKError();
    }

    // get version details from first variant
    final v = versionVariants.first;
    final String version = v['version_name'] as String;
    final String author = v['developer'] as String;
    final String appName = v['title'] as String;
    final DateTime releaseDate = DateTime.parse(v['update_date'] as String);
    String? changeLog = v['whatsnew'] as String?;
    if (changeLog != null && changeLog.isEmpty) {
      changeLog = null;
    }

    if (additionalSettings['useFirstApkOfVersion'] == true) {
      apkUrls = [apkUrls.first];
    }

    return APKDetails(
      version,
      apkUrls,
      AppNames(author, appName),
      releaseDate: releaseDate,
      changeLog: changeLog,
    );
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    if (forAPKDownload) {
      return null;
    } else {
      return {
        "Ual-Access-Businessid": "projecta",
        "Ual-Access-ProjectA":
            '{"device_info":{"os_ver":"${((await DeviceInfoPlugin().androidInfo).version.sdkInt)}"}}',
      };
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    final String appId = (await tryInferringAppId(standardUrl))!;

    final List<String> supportedArchs =
        (await DeviceInfoPlugin().androidInfo).supportedAbis;

    // request versions from API
    final res = await sourceRequest(
      "https://tapi.pureapk.com/v3/get_app_his_version?package_name=$appId&hl=en",
      additionalSettings,
    );
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final List<Map<String, dynamic>> apks =
        (decoded['version_list'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    // group by version
    final List<List<Map<String, dynamic>>> versions = apks
        .fold<Map<String, List<Map<String, dynamic>>>>({}, (
          Map<String, List<Map<String, dynamic>>> val,
          Map<String, dynamic> element,
        ) {
          final String v = element['version_name'] as String;
          if (!val.containsKey(v)) {
            val[v] = [];
          }
          val[v]?.add(element);
          return val;
        })
        .values
        .toList();

    if (versions.isEmpty) {
      throw NoReleasesError();
    }

    for (var i = 0; i < versions.length; i++) {
      final v = versions[i];
      try {
        if (i == 0 && additionalSettings['stayOneVersionBehind'] == true) {
          throw NoReleasesError();
        }
        return await getDetailsForVersion(
          v,
          supportedArchs,
          additionalSettings,
        );
      } catch (e) {
        if (additionalSettings['fallbackToOlderReleases'] != true ||
            i == versions.length - 1) {
          rethrow;
        }
      }
    }
    throw NoAPKError();
  }
}
