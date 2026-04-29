import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GitHub extends AppSource {
  GitHub({bool hostChanged = false}) {
    hosts = ['github.com'];
    appIdInferIsOptional = true;
    showReleaseDateAsVersionToggle = true;
    this.hostChanged = hostChanged;
    allowIncludeZips = true;

    sourceConfigSettingFormItems = [
      GeneratedFormTextField(
        'github-creds',
        label: tr('githubPATLabel'),
        password: true,
        required: false,
        belowWidgets: [
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              launchUrlString(
                'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token',
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              tr('about'),
              style: const TextStyle(
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      GeneratedFormTextField(
        'GHReqPrefix',
        label: tr('GHReqPrefix'),
        hint: 'gh-proxy.org',
        required: false,
        additionalValidators: [
          (value) {
            try {
              if (value != null && Uri.parse(value).scheme.isNotEmpty) {
                throw true;
              }
              if (value != null) {
                Uri.parse('https://$value/api.github.com');
              }
            } catch (e) {
              return tr('invalidInput');
            }
            return null;
          },
        ],
        belowWidgets: [
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              launchUrlString(
                'https://github.com/sky22333/hubproxy',
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              tr('about'),
              style: const TextStyle(
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      GeneratedFormSwitch(
        'checkRepoRename',
        label: tr('repoRenamedCheck'),
      ),
    ];

    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch(
          'includePrereleases',
          label: tr('includePrereleases'),
        ),
      ],
      [
        GeneratedFormSwitch(
          'fallbackToOlderReleases',
          label: tr('fallbackToOlderReleases'),
          defaultValue: true,
        ),
      ],
      [
        GeneratedFormTextField(
          'filterReleaseTitlesByRegEx',
          label: tr('filterReleaseTitlesByRegEx'),
          required: false,
          additionalValidators: [
            (value) {
              return regExValidator(value);
            },
          ],
        ),
      ],
      [
        GeneratedFormTextField(
          'filterReleaseNotesByRegEx',
          label: tr('filterReleaseNotesByRegEx'),
          required: false,
          additionalValidators: [
            (value) {
              return regExValidator(value);
            },
          ],
        ),
      ],
      [GeneratedFormSwitch('verifyLatestTag', label: tr('verifyLatestTag'))],
      [
        GeneratedFormDropdown(
          'sortMethodChoice',
          [
            MapEntry('date', tr('releaseDate')),
            MapEntry('smartname', tr('smartname')),
            MapEntry('none', tr('none')),
            MapEntry(
              'smartname-datefallback',
              '${tr('smartname')} x ${tr('releaseDate')}',
            ),
            MapEntry('name', tr('name')),
          ],
          label: tr('sortMethod'),
          defaultValue: 'date',
        ),
      ],
      [
        GeneratedFormSwitch(
          'useLatestAssetDateAsReleaseDate',
          label: tr('useLatestAssetDateAsReleaseDate'),
        ),
      ],
      [
        GeneratedFormSwitch(
          'releaseTitleAsVersion',
          label: tr('releaseTitleAsVersion'),
        ),
      ],
    ];

    canSearch = true;
    searchQuerySettingFormItems = [
      GeneratedFormTextField(
        'minStarCount',
        label: tr('minStarCount'),
        defaultValue: '0',
        additionalValidators: [
          (value) {
            try {
              int.parse(value ?? '0');
            } catch (e) {
              return tr('invalidInput');
            }
            return null;
          },
        ],
      ),
    ];
  }

  @override
  Future<String?> tryInferringAppId(
    String standardUrl, {
    Map<String, dynamic> additionalSettings = const {},
  }) async {
    const possibleBuildGradleLocations = [
      '/app/build.gradle',
      'android/app/build.gradle',
      'src/app/build.gradle',
    ];
    for (var path in possibleBuildGradleLocations) {
      try {
        final res = await sourceRequest(
          '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/contents/$path',
          additionalSettings,
        );
        if (res.statusCode == 200) {
          try {
            final body = jsonDecode(res.body);
            final trimmedLines = utf8
                .decode(
                  base64.decode(
                    body['content'].toString().split('\n').join(),
                  ),
                )
                .split('\n')
                .map((e) => e.trim());
            var appIds = trimmedLines.where(
              (l) =>
                  l.startsWith('applicationId "') ||
                  l.startsWith('applicationId \''),
            );
            appIds = appIds.map(
              (appId) => appId.split(
                appId.startsWith('applicationId "') ? '"' : '\'',
              )[1],
            );
            appIds = appIds
                .map((appId) {
                  if (appId.startsWith('\${') && appId.endsWith('}')) {
                    appId = trimmedLines
                        .where(
                          (l) => l.startsWith(
                            'def ${appId.substring(2, appId.length - 1)}',
                          ),
                        )
                        .first;
                    appId = appId.split(appId.contains('"') ? '"' : '\'')[1];
                  }
                  return appId;
                })
                .where((appId) => appId.isNotEmpty);
            if (appIds.length == 1) {
              return appIds.first;
            }
          } catch (err) {
            unawaited(
              LogsProvider().add(
                'Error parsing build.gradle from ${res.request!.url.toString()}: ${err.toString()}',
              ),
            );
          }
        }
      } catch (err, stackTrace) {
        AppLogger.debug(
          'Failed to derive appId from source contents',
          error: err,
          stackTrace: stackTrace,
        );
      }
    }
    return null;
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    final RegExp standardUrlRegEx = RegExp(
      '^https?://(www\\.)?${getSourceRegex(hosts)}/[^/]+/[^/]+',
      caseSensitive: false,
    );
    final RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<Map<String, String>?> getRequestHeaders(
    Map<String, dynamic> additionalSettings,
    String url, {
    bool forAPKDownload = false,
  }) async {
    final token = await getTokenIfAny(additionalSettings);
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Token $token';
    }
    if (forAPKDownload == true) {
      headers[HttpHeaders.acceptHeader] = 'application/octet-stream';
    }
    if (headers.isNotEmpty) {
      return headers;
    } else {
      return null;
    }
  }

  Future<String?> getTokenIfAny(Map<String, dynamic> additionalSettings) async {
    final SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfig = await getSourceConfigValues(
      additionalSettings,
      settingsProvider,
    );
    String? creds = sourceConfig['github-creds'];
    if ((additionalSettings['GHReqPrefix'] as String? ?? '').isNotEmpty) {
      creds = null;
    }
    if (creds != null) {
      final userNameEndIndex = creds.indexOf(':');
      if (userNameEndIndex > 0) {
        creds = creds.substring(
          userNameEndIndex + 1,
        ); // For old username-included token inputs
      }
      return creds;
    } else {
      return null;
    }
  }

  @override
  Future<String?> getSourceNote() async {
    if (!hostChanged && (await getTokenIfAny({})) == null) {
      return '${tr('githubSourceNote')} ${hostChanged ? tr('addInfoBelow') : tr('addInfoInSettings')}';
    }
    return null;
  }

  @override
  Future<String> generalReqPrefetchModifier(
    String reqUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    if ((additionalSettings['GHReqPrefix'] as String? ?? '').isNotEmpty) {
      final uri = Uri.parse(reqUrl);
      return 'https://${additionalSettings['GHReqPrefix']}/${uri.toString().substring('https://'.length)}';
    }
    return reqUrl;
  }

  Future<String> getAPIHost(Map<String, dynamic> additionalSettings) async =>
      'https://api.${hosts[0]}';

  Future<String> convertStandardUrlToAPIUrl(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async =>
      '${await getAPIHost(additionalSettings)}/repos${standardUrl.substring('https://${hosts[0]}'.length)}';

  /// Checks if the repository has been renamed or transferred.
  ///
  /// This method explicitly disables automatic redirect following to detect when
  /// GitHub returns a redirect (indicating the repository has moved). A redirect
  /// from the GitHub API for a repository endpoint definitively indicates that
  /// the repository has been renamed or transferred to a different owner.
  ///
  /// Throws [RepositoryRenamedError] if a redirect is detected.
  Future<void> checkForRepositoryRename(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    Map<String, String> sourceConfigSettingValues,
  ) async {
    if (sourceConfigSettingValues['checkRepoRename'] == "false") {
      return;
    }
    final uri = Uri.tryParse(standardUrl);
    final host = uri?.host.toLowerCase() ?? '';
    // Guard against non-GitHub URLs
    if (host != hosts[0] && host != 'www.${hosts[0]}') {
      return;
    }
    final apiUrl = await convertStandardUrlToAPIUrl(
      standardUrl,
      additionalSettings,
    );
    final Response res = await sourceRequest(
      apiUrl,
      additionalSettings,
      followRedirects: false,
    );
    if (res.statusCode >= 300 && res.statusCode < 400) {
      final String? location = res.headers[HttpHeaders.locationHeader.toLowerCase()];
      if (location != null) {
        final Response res2 = await sourceRequest(
          location,
          additionalSettings,
          followRedirects: false,
        );
        String? newUrl;
        try {
          newUrl =
              (jsonDecode(res2.body) as Map<String, dynamic>)['html_url']
                  as String?;
        } catch (e, stackTrace) {
          AppLogger.debug(
            'Could not parse redirect metadata for potential repo rename at $location',
            error: e,
            stackTrace: stackTrace,
          );
        }
        if (newUrl != null) {
          throw RepositoryRenamedError(standardUrl, newUrl);
        }
      }
    }
  }

  @override
  String? changeLogPageFromStandardUrl(String standardUrl) =>
      '$standardUrl/releases';

  Future<APKDetails> getLatestAPKDetailsCommon(
    String requestUrl,
    String standardUrl,
    Map<String, dynamic> additionalSettings, {
    void Function(Response)? onHttpErrorCode,
  }) async {
    final SettingsProvider settingsProvider = SettingsProvider();
    await settingsProvider.initializeSettings();
    final sourceConfigSettingValues = await getSourceConfigValues(
      additionalSettings,
      settingsProvider,
    );
    await checkForRepositoryRename(
      standardUrl,
      additionalSettings,
      sourceConfigSettingValues,
    );
    final bool includePrereleases = additionalSettings['includePrereleases'] == true;
    final bool fallbackToOlderReleases =
        additionalSettings['fallbackToOlderReleases'] == true;
    final String? regexFilter =
        (additionalSettings['filterReleaseTitlesByRegEx'] as String?)
                ?.isNotEmpty ==
            true
        ? additionalSettings['filterReleaseTitlesByRegEx'] as String?
        : null;
    final String? regexNotesFilter =
        (additionalSettings['filterReleaseNotesByRegEx'] as String?)
                ?.isNotEmpty ==
            true
        ? additionalSettings['filterReleaseNotesByRegEx'] as String?
        : null;
    final bool verifyLatestTag = additionalSettings['verifyLatestTag'] == true;
    final bool useLatestAssetDateAsReleaseDate =
        additionalSettings['useLatestAssetDateAsReleaseDate'] == true;
    final String sortMethod =
        (additionalSettings['sortMethodChoice'] as String?) ??
        'smartname-datefallback';
    final bool includeZips = additionalSettings['includeZips'] == true;
    dynamic latestRelease;
    if (verifyLatestTag) {
      final temp = requestUrl.split('?');
      final Response res = await sourceRequest(
        '${temp[0]}/latest${temp.length > 1 ? '?${temp.sublist(1).join('?')}' : ''}',
        additionalSettings,
      );
      if (res.statusCode != 200) {
        if (onHttpErrorCode != null) {
          onHttpErrorCode(res);
        }
        throw getObtainiumHttpError(res);
      }
      latestRelease = jsonDecode(res.body);
    }
    final Response res = await sourceRequest(requestUrl, additionalSettings);
    if (res.statusCode == 200) {
      var releases = jsonDecode(res.body) as List<dynamic>;
      if (latestRelease != null) {
        final latestTag = latestRelease['tag_name'] ?? latestRelease['name'];
        if (releases
            .where(
              (element) =>
                  (element['tag_name'] ?? element['name']) == latestTag,
            )
            .isEmpty) {
          releases = [latestRelease, ...releases];
        }
      }

      findReleaseAssetUrls(dynamic release) =>
          (release['assets'] as List<dynamic>?)?.map((e) {
            final ext = e['name'].toString().toLowerCase().split('.').last;
            String? url =
                !(ext == 'apk' ||
                    ext == 'xapk' ||
                    (includeZips && ext == 'zip'))
                ? (e['browser_download_url'] ?? e['url']) as String?
                : (e['url'] ?? e['browser_download_url']) as String?;
            if (url != null) {
              url = undoGHProxyMod(url, sourceConfigSettingValues);
            }
            e['final_url'] = (e['name'] != null) && (url != null)
                ? MapEntry(e['name'] as String, url)
                : const MapEntry('', '');
            return e;
          }).toList() ??
          [];

      DateTime? getPublishDateFromRelease(dynamic rel) =>
          rel?['published_at'] != null
          ? DateTime.parse(rel['published_at'] as String)
          : rel?['commit']?['created'] != null
          ? DateTime.parse(rel['commit']['created'] as String)
          : null;
      DateTime? getNewestAssetDateFromRelease(dynamic rel) {
        final allAssets = rel['assets'] as List<dynamic>?;
        final filteredAssets = rel['filteredAssets'] as List<dynamic>?;
        final t = (filteredAssets ?? allAssets)
            ?.map((e) {
              return e?['updated_at'] != null
                  ? DateTime.parse(e['updated_at'] as String)
                  : null;
            })
            .where((e) => e != null)
            .toList();
        t?.sort((a, b) => b!.compareTo(a!));
        if (t?.isNotEmpty == true) {
          return t!.first;
        }
        return null;
      }

      DateTime? getReleaseDateFromRelease(dynamic rel, bool useAssetDate) =>
          !useAssetDate
          ? getPublishDateFromRelease(rel)
          : getNewestAssetDateFromRelease(rel);

      if (sortMethod == 'none') {
        releases = releases.reversed.toList();
      } else {
        releases.sort((a, b) {
          // See #478 and #534
          if (a == b) {
            return 0;
          } else if (a == null) {
            return -1;
          } else if (b == null) {
            return 1;
          } else {
            final nameA = (a['tag_name'] ?? a['name']) as String;
            final nameB = (b['tag_name'] ?? b['name']) as String;
            final stdFormats = findStandardFormatsForVersion(
              nameA,
              false,
            ).intersection(findStandardFormatsForVersion(nameB, false));
            if (sortMethod == 'date' ||
                (sortMethod == 'smartname-datefallback' &&
                    stdFormats.isEmpty)) {
              return (getReleaseDateFromRelease(
                        a,
                        useLatestAssetDateAsReleaseDate,
                      ) ??
                      DateTime(1))
                  .compareTo(
                    getReleaseDateFromRelease(
                          b,
                          useLatestAssetDateAsReleaseDate,
                        ) ??
                        DateTime(0),
                  );
            } else {
              if (sortMethod != 'name' && stdFormats.isNotEmpty) {
                final reg = RegExp(stdFormats.last);
                final matchA = reg.firstMatch(nameA);
                final matchB = reg.firstMatch(nameB);
                return compareAlphaNumeric(
                  (nameA).substring(matchA!.start, matchA.end),
                  (nameB).substring(matchB!.start, matchB.end),
                );
              } else {
                // 'name'
                return compareAlphaNumeric(
                  nameA,
                  nameB,
                );
              }
            }
          }
        });
      }
      if (latestRelease != null &&
          (latestRelease['tag_name'] ?? latestRelease['name']) != null &&
          releases.isNotEmpty &&
          latestRelease !=
              (releases[releases.length - 1]['tag_name'] ??
                  releases[0]['name'])) {
        final ind = releases.indexWhere(
          (element) =>
              (latestRelease['tag_name'] ?? latestRelease['name']) ==
              (element['tag_name'] ?? element['name']),
        );
        if (ind >= 0) {
          releases.add(releases.removeAt(ind));
        }
      }
      releases = releases.reversed.toList();
      dynamic targetRelease;
      var prerrelsSkipped = 0;
      for (int i = 0; i < releases.length; i++) {
        if (!fallbackToOlderReleases && i > prerrelsSkipped) break;
        if (!includePrereleases && releases[i]['prerelease'] == true) {
          prerrelsSkipped++;
          continue;
        }
        if (releases[i]['draft'] == true) {
          // Draft releases not supported
          continue;
        }
        var nameToFilter = releases[i]['name'] as String?;
        if (nameToFilter == null || nameToFilter.trim().isEmpty) {
          // Some leave titles empty so tag is used
          nameToFilter = releases[i]['tag_name'] as String;
        }
        if (regexFilter != null &&
            !RegExp(regexFilter).hasMatch(nameToFilter.trim())) {
          continue;
        }
        if (regexNotesFilter != null &&
            !RegExp(
              regexNotesFilter,
            ).hasMatch(((releases[i]['body'] as String?) ?? '').trim())) {
          continue;
        }
        final allAssetsWithUrls = findReleaseAssetUrls(releases[i]);
        final List<MapEntry<String, String>> allAssetUrls = allAssetsWithUrls
            .map((e) => e['final_url'] as MapEntry<String, String>)
            .toList();
        final apkAssetsWithUrls = allAssetsWithUrls.where((element) {
          final ext = (element['final_url'] as MapEntry<String, String>).key
              .toLowerCase()
              .split('.')
              .last;
          return ext == 'apk' || ext == 'xapk' || (includeZips && ext == 'zip');
        }).toList();

        final filteredApkUrls = filterApks(
          apkAssetsWithUrls
              .map((e) => e['final_url'] as MapEntry<String, String>)
              .toList(),
          additionalSettings['apkFilterRegEx'] as String?,
          additionalSettings['invertAPKFilter'] as bool?,
        );
        final filteredApks = apkAssetsWithUrls
            .where(
              (e) => filteredApkUrls
                  .where(
                    (e2) =>
                        e2.key ==
                        (e['final_url'] as MapEntry<String, String>).key,
                  )
                  .isNotEmpty,
            )
            .toList();

        if (filteredApks.isEmpty && additionalSettings['trackOnly'] != true) {
          continue;
        }
        targetRelease = releases[i];
        targetRelease['apkUrls'] = filteredApkUrls;
        targetRelease['filteredAssets'] = filteredApks;
        targetRelease['version'] =
            additionalSettings['releaseTitleAsVersion'] == true
            ? nameToFilter
            : targetRelease['tag_name'] ?? targetRelease['name'];
        if (targetRelease['tarball_url'] != null) {
          allAssetUrls.add(
            MapEntry(
              '${(targetRelease['version'] as String?) ?? 'source'}.tar.gz',
              undoGHProxyMod(
                targetRelease['tarball_url'] as String,
                sourceConfigSettingValues,
              ),
            ),
          );
        }
        if (targetRelease['zipball_url'] != null) {
          allAssetUrls.add(
            MapEntry(
              '${(targetRelease['version'] as String?) ?? 'source'}.zip',
              undoGHProxyMod(
                targetRelease['zipball_url'] as String,
                sourceConfigSettingValues,
              ),
            ),
          );
        }
        targetRelease['allAssetUrls'] = allAssetUrls;
        break;
      }
      if (targetRelease == null) {
        throw NoReleasesError();
      }
      final String? version = targetRelease['version'] as String?;

      final DateTime? releaseDate = getReleaseDateFromRelease(
        targetRelease,
        useLatestAssetDateAsReleaseDate,
      );
      if (version == null) {
        throw NoVersionError();
      }
      final changeLog = (targetRelease['body'] ?? '').toString();
      return APKDetails(
        version,
        targetRelease['apkUrls'] as List<MapEntry<String, String>>,
        getAppNames(standardUrl),
        releaseDate: releaseDate,
        changeLog: changeLog.isEmpty ? null : changeLog,
        allAssetUrls:
            targetRelease['allAssetUrls'] as List<MapEntry<String, String>>,
      );
    } else {
      if (onHttpErrorCode != null) {
        onHttpErrorCode(res);
      }
      throw getObtainiumHttpError(res);
    }
  }

  Future<APKDetails> getLatestAPKDetailsCommon2(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
    Future<String> Function(bool) reqUrlGenerator,
    dynamic Function(Response)? onHttpErrorCode,
  ) async {
    try {
      return await getLatestAPKDetailsCommon(
        await reqUrlGenerator(false),
        standardUrl,
        additionalSettings,
        onHttpErrorCode: onHttpErrorCode,
      );
    } catch (err) {
      if (err is NoReleasesError && additionalSettings['trackOnly'] == true) {
        return await getLatestAPKDetailsCommon(
          await reqUrlGenerator(true),
          standardUrl,
          additionalSettings,
          onHttpErrorCode: onHttpErrorCode,
        );
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    return await getLatestAPKDetailsCommon2(
      standardUrl,
      additionalSettings,
      (bool useTagUrl) async {
        return '${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/${useTagUrl ? 'tags' : 'releases'}?per_page=100';
      },
      (Response res) {
        rateLimitErrorCheck(res);
      },
    );
  }

  AppNames getAppNames(String standardUrl) {
    final String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    final List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names.sublist(1).join('/'));
  }

  Future<Map<String, List<String>>> searchCommon(
    String query,
    String requestUrl,
    String rootProp, {
    void Function(Response)? onHttpErrorCode,
    Map<String, dynamic> querySettings = const {},
  }) async {
    final Response res = await sourceRequest(requestUrl, {});
    if (res.statusCode == 200) {
      final int minStarCount = querySettings['minStarCount'] != null
          ? int.parse(querySettings['minStarCount'] as String)
          : 0;
      final Map<String, List<String>> urlsWithDescriptions = {};
      for (var e in ((jsonDecode(res.body) as Map<String, dynamic>)[rootProp]
          as List<dynamic>)) {
        final item = e as Map<String, dynamic>;
        final stars = (item['stargazers_count'] ?? item['stars_count'] ?? 0) as num;
        if (stars >= minStarCount) {
          urlsWithDescriptions.addAll({
            item['html_url'] as String: [
              item['full_name'] as String,
              ((item['archived'] == true ? '[ARCHIVED] ' : '') +
                  (item['description'] != null
                      ? item['description'] as String
                      : tr('noDescription'))),
            ],
          });
        }
      }
      return urlsWithDescriptions;
    } else {
      if (onHttpErrorCode != null) {
        onHttpErrorCode(res);
      }
      throw getObtainiumHttpError(res);
    }
  }

  String undoGHProxyMod(
    String reqUrl,
    Map<String, String> sourceConfigSettingValues,
  ) => reqUrl.replaceFirst(
    'https://${sourceConfigSettingValues['GHReqPrefix']}/',
    '',
  );

  @override
  Future<Map<String, List<String>>> search(
    String query, {
    Map<String, dynamic> querySettings = const {},
  }) async {
    final sp = SettingsProvider();
    await sp.initializeSettings();
    final sourceConfigSettingValues = await getSourceConfigValues({}, sp);
    final results = await searchCommon(
      query,
      '${await getAPIHost({})}/search/repositories?q=${Uri.encodeQueryComponent(query)}&per_page=100',
      'items',
      onHttpErrorCode: (Response res) {
        rateLimitErrorCheck(res);
      },
      querySettings: querySettings,
    );
    if ((sourceConfigSettingValues['GHReqPrefix'] ?? '').isNotEmpty) {
      final Map<String, List<String>> results2 = {};
      results.forEach((k, v) {
        results2[undoGHProxyMod(k, sourceConfigSettingValues)] = v;
      });
      return results2;
    } else {
      return results;
    }
  }

  void rateLimitErrorCheck(Response res) {
    if (res.headers['x-ratelimit-remaining'] == '0') {
      throw RateLimitError(
        (int.parse(res.headers['x-ratelimit-reset'] ?? '1800000000') / 60000000)
            .round(),
      );
    }
  }
}
