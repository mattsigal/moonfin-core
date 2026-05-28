import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../auth/repositories/session_repository.dart';
import '../../../data/services/storage_path_service.dart';
import '../../../preference/user_preferences.dart';
import '../../theme/app_theme_controller.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import 'settings_app_bar.dart';

class SavedThemesScreen extends StatefulWidget {
  const SavedThemesScreen({super.key});

  @override
  State<SavedThemesScreen> createState() => _SavedThemesScreenState();
}

class _SavedThemesScreenState extends State<SavedThemesScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  final _storagePaths = GetIt.instance<StoragePathService>();
  final _sessionRepo = GetIt.instance<SessionRepository>();
  final _client = GetIt.instance<MediaServerClient>();

  bool _loading = true;
  String? _statusMessage;
  String? _deletingThemeId;
  List<_SavedThemeFile> _savedThemes = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedThemes());
  }

  String _serverSyncKey() {
    final serverId = _sessionRepo.activeServerId;
    if (serverId != null && serverId.trim().isNotEmpty) {
      return serverId.trim();
    }

    final normalized = _client.baseUrl.toLowerCase().trim();
    return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<Directory?> _resolveCacheDirectory() async {
    try {
      final root = await _storagePaths.getThemeCacheDir();
      final scoped = Directory('${root.path}/${_serverSyncKey()}');
      if (!await scoped.exists()) {
        await scoped.create(recursive: true);
      }
      return scoped;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSavedThemes() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    final cacheDirectory = await _resolveCacheDirectory();
    final themes = <_SavedThemeFile>[];

    if (cacheDirectory != null && await cacheDirectory.exists()) {
      final files =
          cacheDirectory
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        try {
          final raw = await file.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is! Map) {
            continue;
          }

          final spec = ThemeSpec.fromJson(Map<String, dynamic>.from(decoded));
          if (ThemeRegistry.builtInIds.contains(spec.id)) {
            continue;
          }

          themes.add(_SavedThemeFile(spec: spec, file: file));
        } catch (_) {}
      }
    }

    themes.sort((left, right) {
      return left.spec.displayName.toLowerCase().compareTo(
        right.spec.displayName.toLowerCase(),
      );
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _savedThemes = themes;
    });
  }

  Future<void> _confirmDelete(_SavedThemeFile theme) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete saved theme?'),
          content: Text(
            'Remove "${theme.spec.displayName}" from this device cache?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteTheme(theme);
    }
  }

  Future<void> _deleteTheme(_SavedThemeFile theme) async {
    if (_deletingThemeId != null) {
      return;
    }

    setState(() {
      _deletingThemeId = theme.spec.id;
      _statusMessage = null;
    });

    try {
      await theme.file.delete();
      ThemeRegistry.removeCustom(theme.spec.id);

      if (!mounted) {
        return;
      }

      final controller = AppThemeScope.of(context);
      final selectedCustomId = _prefs.get(UserPreferences.customThemeId);
      if (selectedCustomId == theme.spec.id) {
        await controller.applyCustomTheme(_prefs, '');
      } else {
        controller.refreshFromPreferences(_prefs);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _savedThemes.removeWhere((entry) => entry.spec.id == theme.spec.id);
        _statusMessage =
            'Deleted "${theme.spec.displayName}" from this device.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Could not delete "${theme.spec.displayName}".';
      });
    } finally {
      if (!mounted) {
        _deletingThemeId = null;
      } else {
        setState(() {
          _deletingThemeId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCustomId = _prefs.get(UserPreferences.customThemeId);

    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(
          context,
          const Text('Saved themes'),
          actions: [
            IconButton(
              onPressed: _loading ? null : () => unawaited(_loadSavedThemes()),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'These are themes downloaded from the Moonfin plugin for the current server. '
                    'Deleting removes only this local copy.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.74,
                      ),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.78,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_savedThemes.isEmpty)
                    Text(
                      'No saved themes were found for this server.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.74,
                        ),
                      ),
                    ),
                  for (final entry in _savedThemes) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.download_done_outlined),
                        title: Text(entry.spec.displayName),
                        subtitle: Text(
                          selectedCustomId == entry.spec.id
                              ? '${entry.spec.id} • Currently active'
                              : entry.spec.id,
                        ),
                        trailing: _deletingThemeId == entry.spec.id
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                onPressed: () =>
                                    unawaited(_confirmDelete(entry)),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete saved theme',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SavedThemeFile {
  final ThemeSpec spec;
  final File file;

  const _SavedThemeFile({required this.spec, required this.file});
}
