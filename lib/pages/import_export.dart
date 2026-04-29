import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/app_sources/fdroidrepo.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool importInProgress = false;

  @override
  Widget build(BuildContext context) {
    final SourceProvider sourceProvider = SourceProvider();
    final appsProvider = context.watch<AppsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    final outlineButtonStyle = ButtonStyle(
      shape: WidgetStateProperty.all(
        StadiumBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );

    urlListImport({String? initValue, bool overrideInitValid = false}) {
      showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (BuildContext ctx) {
          return GeneratedFormModal(
            initValid: overrideInitValid,
            title: tr('importFromURLList'),
            items: [
              [
                GeneratedFormTextField(
                  'appURLList',
                  defaultValue: initValue ?? '',
                  label: tr('appURLList'),
                  max: 7,
                  additionalValidators: [
                    (String? value) {
                      if (value != null && value.isNotEmpty) {
                        final lines = value.trim().split('\n');
                        for (int i = 0; i < lines.length; i++) {
                          try {
                            sourceProvider.getSource(lines[i]);
                          } catch (e) {
                            return '${tr('line')} ${i + 1}: $e';
                          }
                        }
                      }
                      return null;
                    },
                  ],
                ),
              ],
            ],
          );
        },
      ).then((values) {
        if (values != null) {
          final urls = (values['appURLList'] as String).split('\n');
          setState(() {
            importInProgress = true;
          });
          appsProvider
              .addAppsByURL(urls)
              .then((errors) {
                if (!context.mounted) {
                  return;
                }
                if (errors.isEmpty) {
                  showMessage(
                    tr(
                      'importedX',
                      args: [plural('apps', urls.length).toLowerCase()],
                    ),
                    context,
                  );
                } else {
                  showDialog<void>(
                    context: context,
                    builder: (BuildContext ctx) {
                      return ImportErrorDialog(
                        urlsLength: urls.length,
                        errors: errors,
                      );
                    },
                  );
                }
              })
              .catchError((Object e) {
                if (context.mounted) {
                  showError(e, context);
                }
              })
              .whenComplete(() {
                if (!mounted) {
                  return;
                }
                setState(() {
                  importInProgress = false;
                });
              });
        }
      });
    }

    runObtainiumExport({bool pickOnly = false}) async {
      unawaited(HapticFeedback.selectionClick());
      unawaited(
        appsProvider
            .export(
              pickOnly:
                  pickOnly || (await settingsProvider.getExportDir()) == null,
              sp: settingsProvider,
            )
            .then((String? result) {
              if (result != null && context.mounted) {
                showMessage(tr('exportedTo', args: [result]), context);
              }
            })
            .catchError((Object e) {
              if (context.mounted) {
                showError(e, context);
              }
            }),
      );
    }

    runObtainiumImport() {
      HapticFeedback.selectionClick();
      unawaited(
        FilePicker.pickFiles()
            .then((result) {
              setState(() {
                importInProgress = true;
              });
              if (result != null) {
                final String data = File(
                  result.files.single.path!,
                ).readAsStringSync();
                try {
                  jsonDecode(data);
                } catch (e) {
                  throw ObtainiumError(tr('invalidInput'));
                }
                appsProvider.import(data).then((value) {
                  if (!context.mounted) {
                    return;
                  }
                  final cats = settingsProvider.categories;
                  appsProvider.apps.forEach((key, value) {
                    for (var c in value.app.categories) {
                      if (!cats.containsKey(c)) {
                        cats[c] = generateRandomLightColor().toARGB32();
                      }
                    }
                  });
                  appsProvider.addMissingCategories(settingsProvider);
                  showMessage(
                    '${tr('importedX', args: [plural('apps', value.key.length).toLowerCase()])}${value.value ? ' + ${tr('settings').toLowerCase()}' : ''}',
                    context,
                  );
                });
              } else {
                // User canceled the picker
              }
            })
            .catchError((Object e) {
              if (context.mounted) {
                showError(e, context);
              }
            })
            .whenComplete(() {
              if (!mounted) {
                return;
              }
              setState(() {
                importInProgress = false;
              });
            }),
      );
    }

    runUrlImport() {
      unawaited(
        FilePicker.pickFiles().then((result) {
          if (result != null) {
            urlListImport(
              overrideInitValid: true,
              initValue: RegExp('https?://[^"]+')
                  .allMatches(
                    File(result.files.single.path!).readAsStringSync(),
                  )
                  .map((e) => e.input.substring(e.start, e.end))
                  .toSet()
                  .toList()
                  .where((url) {
                    try {
                      sourceProvider.getSource(url);
                      return true;
                    } catch (e) {
                      return false;
                    }
                  })
                  .join('\n'),
            );
          }
        }),
      );
    }

    runSourceSearch(AppSource source) {
      unawaited(
        () async {
              final values = await showDialog<Map<String, dynamic>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return GeneratedFormModal(
                    title: tr('searchX', args: [source.name]),
                    items: [
                      [
                        GeneratedFormTextField(
                          'searchQuery',
                          label: tr('searchQuery'),
                          required: source.name != FDroidRepo().name,
                        ),
                      ],
                      ...source.searchQuerySettingFormItems.map((e) => [e]),
                      [
                        GeneratedFormTextField(
                          'url',
                          label: source.hosts.isNotEmpty
                              ? tr('overrideSource')
                              : plural('url', 1).substring(2),
                          defaultValue: source.hosts.isNotEmpty
                              ? source.hosts[0]
                              : '',
                        ),
                      ],
                    ],
                  );
                },
              );
              if (values != null) {
                setState(() {
                  importInProgress = true;
                });
                if (source.hosts.isEmpty || values['url'] != source.hosts[0]) {
                  source = sourceProvider.getSource(
                    values['url'] as String,
                    overrideSource: source.runtimeType.toString(),
                  );
                }
                final urlsWithDescriptions = await source.search(
                  values['searchQuery'] as String,
                  querySettings: values,
                );
                if (urlsWithDescriptions.isNotEmpty) {
                  final selectedUrls = !context.mounted
                      ? null
                      : await showDialog<List<String>?>(
                          context: context,
                          builder: (BuildContext ctx) {
                            return SelectionModal(
                              entries: urlsWithDescriptions,
                              selectedByDefault: false,
                            );
                          },
                        );
                  if (selectedUrls != null && selectedUrls.isNotEmpty) {
                    final errors = await appsProvider.addAppsByURL(
                      selectedUrls,
                      sourceOverride: source,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    if (errors.isEmpty) {
                      showMessage(
                        tr(
                          'importedX',
                          args: [
                            plural('apps', selectedUrls.length).toLowerCase(),
                          ],
                        ),
                        context,
                      );
                    } else {
                      unawaited(
                        showDialog(
                          context: context,
                          builder: (BuildContext ctx) {
                            return ImportErrorDialog(
                              urlsLength: selectedUrls.length,
                              errors: errors,
                            );
                          },
                        ),
                      );
                    }
                  }
                } else {
                  throw ObtainiumError(tr('noResults'));
                }
              }
            }()
            .catchError((Object e) {
              if (context.mounted) {
                showError(e, context);
              }
            })
            .whenComplete(() {
              if (!mounted) {
                return;
              }
              setState(() {
                importInProgress = false;
              });
            }),
      );
    }

    runMassSourceImport(MassAppUrlSource source) {
      unawaited(
        () async {
              final values = await showDialog<Map<String, dynamic>?>(
                context: context,
                builder: (BuildContext ctx) {
                  return GeneratedFormModal(
                    title: tr('importX', args: [source.name]),
                    items: source.requiredArgs
                        .map((e) => [GeneratedFormTextField(e, label: e)])
                        .toList(),
                  );
                },
              );
              if (values != null) {
                setState(() {
                  importInProgress = true;
                });
                final urlsWithDescriptions = await source
                    .getUrlsWithDescriptions(
                      values.values.map((e) => e.toString()).toList(),
                    );
                final selectedUrls = !context.mounted
                    ? null
                    : await showDialog<List<String>?>(
                        context: context,
                        builder: (BuildContext ctx) {
                          return SelectionModal(entries: urlsWithDescriptions);
                        },
                      );
                if (selectedUrls != null) {
                  final errors = await appsProvider.addAppsByURL(selectedUrls);
                  if (!context.mounted) {
                    return;
                  }
                  if (errors.isEmpty) {
                    showMessage(
                      tr(
                        'importedX',
                        args: [
                          plural('apps', selectedUrls.length).toLowerCase(),
                        ],
                      ),
                      context,
                    );
                  } else {
                    unawaited(
                      showDialog(
                        context: context,
                        builder: (BuildContext ctx) {
                          return ImportErrorDialog(
                            urlsLength: selectedUrls.length,
                            errors: errors,
                          );
                        },
                      ),
                    );
                  }
                }
              }
            }()
            .catchError((Object e) {
              if (context.mounted) {
                showError(e, context);
              }
            })
            .whenComplete(() {
              if (!mounted) {
                return;
              }
              setState(() {
                importInProgress = false;
              });
            }),
      );
    }

    final sourceStrings = <String, List<String>>{};
    sourceProvider.sources.where((e) => e.canSearch).forEach((s) {
      sourceStrings[s.name] = [s.name];
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: <Widget>[
          CustomAppBar(title: tr('importExport')),
          SliverFillRemaining(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!settingsProvider.isTV)
                    FutureBuilder(
                      future: settingsProvider.getExportDir(),
                      builder: (context, snapshot) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: outlineButtonStyle,
                                    onPressed: importInProgress
                                        ? null
                                        : () {
                                            runObtainiumExport(pickOnly: true);
                                          },
                                    child: Text(
                                      tr('pickExportDir'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextButton(
                                    style: outlineButtonStyle,
                                    onPressed:
                                        importInProgress ||
                                            snapshot.data == null
                                        ? null
                                        : runObtainiumExport,
                                    child: Text(
                                      tr('obtainiumExport'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: outlineButtonStyle,
                                    onPressed: importInProgress
                                        ? null
                                        : runObtainiumImport,
                                    child: Text(
                                      tr('obtainiumImport'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (snapshot.data != null)
                              Column(
                                children: [
                                  const SizedBox(height: 16),
                                  GeneratedForm(
                                    items: [
                                      [
                                        GeneratedFormSwitch(
                                          'autoExportOnChanges',
                                          label: tr('autoExportOnChanges'),
                                          defaultValue: settingsProvider
                                              .autoExportOnChanges,
                                        ),
                                      ],
                                      [
                                        GeneratedFormDropdown(
                                          'exportSettings',
                                          [
                                            MapEntry('0', tr('none')),
                                            MapEntry('1', tr('excludeSecrets')),
                                            MapEntry('2', tr('all')),
                                          ],
                                          label: tr('includeSettings'),
                                          defaultValue: settingsProvider
                                              .exportSettings
                                              .toString(),
                                        ),
                                      ],
                                    ],
                                    onValueChanges: (value, valid, isBuilding) {
                                      if (valid && !isBuilding) {
                                        if (value['autoExportOnChanges'] !=
                                            null) {
                                          settingsProvider.autoExportOnChanges =
                                              value['autoExportOnChanges'] ==
                                              true;
                                        }
                                        if (value['exportSettings'] != null) {
                                          settingsProvider
                                              .exportSettings = int.parse(
                                            value['exportSettings'] as String,
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  if (importInProgress)
                    const Column(
                      children: [
                        SizedBox(height: 14),
                        LinearProgressIndicator(),
                        SizedBox(height: 14),
                      ],
                    )
                  else
                    Column(
                      children: [
                        SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: importInProgress
                                    ? null
                                    : () async {
                                        final searchSourceName =
                                            await showDialog<List<String>?>(
                                              context: context,
                                              builder: (BuildContext ctx) {
                                                return SelectionModal(
                                                  title: tr(
                                                    'selectX',
                                                    args: [
                                                      tr(
                                                        'source',
                                                      ).toLowerCase(),
                                                    ],
                                                  ),
                                                  entries: sourceStrings,
                                                  selectedByDefault: false,
                                                  onlyOneSelectionAllowed: true,
                                                  titlesAreLinks: false,
                                                );
                                              },
                                            ) ??
                                            [];
                                        final searchSource = sourceProvider
                                            .sources
                                            .where(
                                              (e) => searchSourceName.contains(
                                                e.name,
                                              ),
                                            )
                                            .toList();
                                        if (searchSource.isNotEmpty) {
                                          runSourceSearch(searchSource[0]);
                                        }
                                      },
                                child: Text(
                                  tr(
                                    'searchX',
                                    args: [lowerCaseIfEnglish(tr('source'))],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: importInProgress ? null : urlListImport,
                          child: Text(tr('importFromURLList')),
                        ),
                        const SizedBox(height: 8),
                        if (!settingsProvider.isTV)
                          TextButton(
                            onPressed: importInProgress ? null : runUrlImport,
                            child: Text(tr('importFromURLsInFile')),
                          ),
                      ],
                    ),
                  ...sourceProvider.massUrlSources.map(
                    (source) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: importInProgress
                              ? null
                              : () {
                                  runMassSourceImport(source);
                                },
                          child: Text(tr('importX', args: [source.name])),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Divider(height: 32),
                  Text(
                    tr('importedAppsIdDisclaimer'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportErrorDialog extends StatefulWidget {
  const ImportErrorDialog({
    super.key,
    required this.urlsLength,
    required this.errors,
  });

  final int urlsLength;
  final List<List<String>> errors;

  @override
  State<ImportErrorDialog> createState() => _ImportErrorDialogState();
}

class _ImportErrorDialogState extends State<ImportErrorDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('importErrors')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'importedXOfYApps',
              args: [
                (widget.urlsLength - widget.errors.length).toString(),
                widget.urlsLength.toString(),
              ],
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            tr('followingURLsHadErrors'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          ...widget.errors.map((e) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(e[0]),
                Text(e[1], style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            );
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(tr('ok')),
        ),
      ],
    );
  }
}

// ignore: must_be_immutable
class SelectionModal extends StatefulWidget {
  SelectionModal({
    super.key,
    required this.entries,
    this.selectedByDefault = true,
    this.onlyOneSelectionAllowed = false,
    this.titlesAreLinks = true,
    this.title,
    this.deselectThese = const [],
  });

  String? title;
  Map<String, List<String>> entries;
  bool selectedByDefault;
  List<String> deselectThese;
  bool onlyOneSelectionAllowed;
  bool titlesAreLinks;

  @override
  State<SelectionModal> createState() => _SelectionModalState();
}

class _SelectionModalState extends State<SelectionModal> {
  Map<MapEntry<String, List<String>>, bool> entrySelections = {};
  String filterRegex = '';
  @override
  void initState() {
    super.initState();
    for (var entry in widget.entries.entries) {
      entrySelections.putIfAbsent(
        entry,
        () =>
            widget.selectedByDefault &&
            !widget.onlyOneSelectionAllowed &&
            !widget.deselectThese.contains(entry.key),
      );
    }
    if (widget.selectedByDefault && widget.onlyOneSelectionAllowed) {
      selectOnlyOne(widget.entries.entries.first.key);
    }
  }

  void selectOnlyOne(String url) {
    for (var e in entrySelections.keys) {
      entrySelections[e] = e.key == url;
    }
  }

  void selectAll({bool deselect = false}) {
    for (var e in entrySelections.keys) {
      entrySelections[e] = !deselect;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<SettingsProvider>().isTV;
    final Map<MapEntry<String, List<String>>, bool> filteredEntrySelections =
        {};
    entrySelections.forEach((key, value) {
      final searchableText = key.value.isEmpty ? key.key : key.value[0];
      if (filterRegex.isEmpty || RegExp(filterRegex).hasMatch(searchableText)) {
        filteredEntrySelections.putIfAbsent(key, () => value);
      }
    });
    if (filterRegex.isNotEmpty && filteredEntrySelections.isEmpty) {
      entrySelections.forEach((key, value) {
        final searchableText = key.value.isEmpty ? key.key : key.value[0];
        if (filterRegex.isEmpty ||
            RegExp(
              filterRegex,
              caseSensitive: false,
            ).hasMatch(searchableText)) {
          filteredEntrySelections.putIfAbsent(key, () => value);
        }
      });
    }
    getSelectAllButton() {
      if (widget.onlyOneSelectionAllowed) {
        return SizedBox.shrink();
      }
      final noneSelected = entrySelections.values
          .where((v) => v == true)
          .isEmpty;
      return noneSelected
          ? TextButton(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onPressed: () {
                setState(() {
                  selectAll();
                });
              },
              child: Text(tr('selectAll')),
            )
          : TextButton(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onPressed: () {
                setState(() {
                  selectAll(deselect: true);
                });
              },
              child: Text(tr('deselectX', args: [''])),
            );
    }

    return AlertDialog(
      scrollable: true,
      title: Text(widget.title ?? tr('pick')),
      content: Column(
        children: [
          GeneratedForm(
            items: [
              [
                GeneratedFormTextField(
                  'filter',
                  label: tr('filter'),
                  required: false,
                  additionalValidators: [
                    (value) {
                      return regExValidator(value);
                    },
                  ],
                ),
              ],
            ],
            onValueChanges: (value, valid, isBuilding) {
              if (valid && !isBuilding) {
                if (value['filter'] != null) {
                  setState(() {
                    filterRegex = value['filter'] as String;
                  });
                }
              }
            },
          ),
          ...filteredEntrySelections.keys.map((entry) {
            selectThis(bool? value) {
              setState(() {
                value ??= false;
                if (value! && widget.onlyOneSelectionAllowed) {
                  selectOnlyOne(entry.key);
                } else {
                  entrySelections[entry] = value!;
                }
              });
            }

            final urlLink = InkWell(
              onTap: !widget.titlesAreLinks
                  ? null
                  : () {
                      launchUrlString(
                        entry.key,
                        mode: LaunchMode.externalApplication,
                      );
                    },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.value.isEmpty ? entry.key : entry.value[0],
                    style: TextStyle(
                      decoration: widget.titlesAreLinks
                          ? TextDecoration.underline
                          : null,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  if (widget.titlesAreLinks)
                    Text(
                      Uri.parse(entry.key).host,
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            );

            final descriptionText = entry.value.length <= 1
                ? const SizedBox.shrink()
                : Text(
                    entry.value[1].length > 128
                        ? '${entry.value[1].substring(0, 128)}...'
                        : entry.value[1],
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  );

            final selectedEntries = entrySelections.entries
                .where((e) => e.value)
                .toList();

            final singleSelectTile = ListTile(
              title: InkWell(
                onTap: widget.titlesAreLinks
                    ? null
                    : () {
                        selectThis(!(entrySelections[entry] ?? false));
                      },
                child: urlLink,
              ),
              subtitle: entry.value.length <= 1
                  ? null
                  : InkWell(
                      onTap: () {
                        setState(() {
                          selectOnlyOne(entry.key);
                        });
                      },
                      child: descriptionText,
                    ),
              leading: RadioGroup<String>(
                groupValue: selectedEntries.isEmpty
                    ? null
                    : selectedEntries.first.key.key,
                onChanged: (value) {
                  if (isTV) {
                    Navigator.of(context).pop([entry.key]);
                  } else {
                    setState(() {
                      selectOnlyOne(entry.key);
                    });
                  }
                },
                child: Radio<String>(value: entry.key),
              ),
            );

            final multiSelectTile = Row(
              children: [
                Checkbox(
                  value: entrySelections[entry],
                  onChanged: (value) {
                    selectThis(value);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: widget.titlesAreLinks
                            ? null
                            : () {
                                selectThis(!(entrySelections[entry] ?? false));
                              },
                        child: urlLink,
                      ),
                      entry.value.length <= 1
                          ? const SizedBox.shrink()
                          : InkWell(
                              onTap: () {
                                selectThis(!(entrySelections[entry] ?? false));
                              },
                              child: descriptionText,
                            ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            );

            return widget.onlyOneSelectionAllowed
                ? singleSelectTile
                : multiSelectTile;
          }),
          if (isTV && !widget.onlyOneSelectionAllowed) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('cancel')),
                ),
                TextButton(
                  onPressed: entrySelections.values.where((b) => b).isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                          entrySelections.entries
                              .where((entry) => entry.value)
                              .map((e) => e.key.key)
                              .toList(),
                        ),
                  child: Text(
                    tr(
                      'selectX',
                      args: [
                        entrySelections.values
                            .where((b) => b)
                            .length
                            .toString(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        getSelectAllButton(),
        TextButton(
          autofocus: isTV,
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(tr('cancel')),
        ),
        TextButton(
          onPressed: entrySelections.values.where((b) => b).isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(
                    entrySelections.entries
                        .where((entry) => entry.value)
                        .map((e) => e.key.key)
                        .toList(),
                  );
                },
          child: Text(
            widget.onlyOneSelectionAllowed
                ? tr('pick')
                : tr(
                    'selectX',
                    args: [
                      entrySelections.values.where((b) => b).length.toString(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
