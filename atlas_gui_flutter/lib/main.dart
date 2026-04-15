import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);
final ValueNotifier<String> appBackgroundPath = ValueNotifier('');
final ValueNotifier<double> appBackgroundBlur = ValueNotifier(15);
final ValueNotifier<double> appBackgroundParticlesOpacity = ValueNotifier(1.0);
final ValueNotifier<bool> appDialogBlurEnabled = ValueNotifier(true);
final ValueNotifier<bool> appStartupAnimationEnabled = ValueNotifier(true);
final ValueNotifier<int> userToggleStatesRevision = ValueNotifier(0);

const _fallbackAcrylicColor = Color(0x260A0E14);
const _legacyMsiResetMarkerFileName = '.legacy-msi-reset';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.clear();
  imageCache.clearLiveImages();

  // Initialize app data directory structure if running from installed location
  await _initializeAppDataDirectory();
  UserToggleStatesService.startWatching();

  // Check if another instance is already running
  if (!await _acquireInstanceLock()) {
    debugPrint('Another instance of ATLAS Backend is already running.');
    exit(1);
  }

  await Window.initialize();
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: _fallbackAcrylicColor,
  );
  await Window.makeTitlebarTransparent();
  await Window.enableFullSizeContentView();
  runApp(const AtlasApp());
}

ServerSocket? _instanceLockSocket;

Future<bool> _acquireInstanceLock() async {
  try {
    _instanceLockSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      43621,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _initializeAppDataDirectory() async {
  final atlasDataDir = Directory(getBackendRoot());
  final requiredDirs = [
    atlasDataDir,
    Directory(joinPath([atlasDataDir.path, 'static', 'assets'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'cms'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'profiles'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'ClientSettings'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'athenaprofiles'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'battlepass'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'shop'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'discovery'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'hotfixes'])),
    Directory(
      joinPath([atlasDataDir.path, 'static', 'hotfixes', 'DefaultGame Data']),
    ),
    Directory(joinPath([atlasDataDir.path, 'static', 'events'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'gameconfig'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'images'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'items'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'playlists'])),
    Directory(joinPath([atlasDataDir.path, 'responses'])),
    Directory(joinPath([atlasDataDir.path, 'exports'])),
    Directory(joinPath([atlasDataDir.path, 'logs'])),
    Directory(joinPath([atlasDataDir.path, 'src', 'config'])),
  ];

  for (final dir in requiredDirs) {
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }

  await _restoreInstallerMigrationData(atlasDataDir);
  await _seedInstalledDataDirectory(atlasDataDir);
  await _syncInstalledRuntimeSourceDirectory(atlasDataDir);
  await _syncInstalledRuntimeDependencyFiles(atlasDataDir);
  await _synchronizeInstalledMutableDataFiles(atlasDataDir);
  await _migrateLegacyPresetFolders(atlasDataDir);
  await UserToggleStatesService.applySavedStateIfPresent();
  await UserToggleStatesService.syncFromCurrentState();
}

Future<void> _seedInstalledDataDirectory(Directory atlasDataDir) async {
  final installRoot = getInstallationRoot();
  if (_samePath(installRoot, atlasDataDir.path)) {
    return;
  }

  final missingOnlyDirs = <List<String>>[
    ['responses'],
    ['static', 'hotfixes'],
    ['static', 'hotfixes', 'DefaultGame Data'],
    ['static', 'profiles'],
    ['static', 'ClientSettings', 'config'],
    ['static', 'athenaprofiles', 'Profile Presets'],
    ['public', 'gameconfig'],
    ['public', 'images'],
    ['public', 'items'],
    ['public', 'playlists'],
  ];

  for (final relativeDir in missingOnlyDirs) {
    final sourceDir = Directory(joinPath([installRoot, ...relativeDir]));
    final targetDir = Directory(joinPath([atlasDataDir.path, ...relativeDir]));
    await _copyMissingDirectoryContents(sourceDir, targetDir);
  }

  final runtimeAssetDirs = <List<String>>[
    ['static', 'assets'],
    ['static', 'battlepass'],
    ['static', 'cms'],
    ['static', 'discovery'],
    ['static', 'events'],
    ['static', 'shop'],
  ];

  for (final relativeDir in runtimeAssetDirs) {
    final sourceDir = Directory(joinPath([installRoot, ...relativeDir]));
    final targetDir = Directory(joinPath([atlasDataDir.path, ...relativeDir]));
    await _copyDirectoryContentsReplacingFiles(sourceDir, targetDir);
  }

  // Always sync shipped config files that live alongside user-mutable data.
  await _copyFileReplacingIfDifferent(
    File(joinPath([installRoot, 'static', 'athenaprofiles', 'presets.json'])),
    File(
      joinPath([atlasDataDir.path, 'static', 'athenaprofiles', 'presets.json']),
    ),
  );

  for (final name in ['curves.defaults.json', 'datatables.defaults.json']) {
    await _copyFileReplacingIfDifferent(
      File(joinPath([installRoot, 'responses', name])),
      File(joinPath([atlasDataDir.path, 'responses', name])),
    );
  }

  // Always sync update notes so users see the latest version.
  for (final name in ['update-notes.md', 'update-notes.txt']) {
    await _copyFileReplacingIfDifferent(
      File(joinPath([installRoot, name])),
      File(joinPath([atlasDataDir.path, name])),
    );
  }
}

Future<void> _copyMissingDirectoryContents(
  Directory source,
  Directory target,
) async {
  if (!await source.exists()) {
    return;
  }

  await target.create(recursive: true);

  await for (final entity in source.list(followLinks: false)) {
    final name = _entityName(entity);
    if (name.isEmpty) continue;

    final targetPath = joinPath([target.path, name]);
    if (entity is Directory) {
      await _copyMissingDirectoryContents(entity, Directory(targetPath));
      continue;
    }

    if (entity is File) {
      final targetFile = File(targetPath);
      if (!await targetFile.exists()) {
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetFile.path);
      }
    }
  }
}

Future<void> _syncInstalledRuntimeSourceDirectory(
  Directory atlasDataDir,
) async {
  final installRoot = getInstallationRoot();
  if (_samePath(installRoot, atlasDataDir.path)) {
    return;
  }

  await _copyDirectoryContentsReplacingFiles(
    Directory(joinPath([installRoot, 'src'])),
    Directory(joinPath([atlasDataDir.path, 'src'])),
  );
}

Future<void> _syncInstalledRuntimeDependencyFiles(
  Directory atlasDataDir,
) async {
  final installRoot = getInstallationRoot();
  if (_samePath(installRoot, atlasDataDir.path)) {
    return;
  }

  final installPackageJson = File(joinPath([installRoot, 'package.json']));
  final runtimePackageJson = File(
    joinPath([atlasDataDir.path, 'package.json']),
  );
  final installLockfile = File(joinPath([installRoot, 'bun.lockb']));
  final runtimeLockfile = File(joinPath([atlasDataDir.path, 'bun.lockb']));
  final installNodeModules = Directory(joinPath([installRoot, 'node_modules']));
  final runtimeNodeModules = Directory(
    joinPath([atlasDataDir.path, 'node_modules']),
  );

  final dependenciesChanged =
      await _filesDiffer(installPackageJson, runtimePackageJson) ||
      await _filesDiffer(installLockfile, runtimeLockfile) ||
      !await _directoryHasEntries(runtimeNodeModules);

  await _copyFileReplacingIfDifferent(installPackageJson, runtimePackageJson);
  await _copyFileReplacingIfDifferent(installLockfile, runtimeLockfile);

  if (dependenciesChanged) {
    await _copyDirectoryContentsReplacingFiles(
      installNodeModules,
      runtimeNodeModules,
    );
  }
}

Future<void> _copyDirectoryContentsReplacingFiles(
  Directory source,
  Directory target,
) async {
  if (!await source.exists()) {
    return;
  }

  await target.create(recursive: true);

  await for (final entity in source.list(followLinks: false)) {
    final name = _entityName(entity);
    if (name.isEmpty) continue;

    final targetPath = joinPath([target.path, name]);
    if (entity is Directory) {
      await _copyDirectoryContentsReplacingFiles(entity, Directory(targetPath));
      continue;
    }

    if (entity is File) {
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await entity.copy(targetFile.path);
    }
  }
}

Future<bool> _directoryHasEntries(Directory directory) async {
  if (!await directory.exists()) {
    return false;
  }

  await for (final _ in directory.list(followLinks: false)) {
    return true;
  }

  return false;
}

Future<bool> _filesDiffer(File source, File target) async {
  if (!await source.exists()) {
    return false;
  }

  if (!await target.exists()) {
    return true;
  }

  final sourceStat = await source.stat();
  final targetStat = await target.stat();
  if (sourceStat.size != targetStat.size) {
    return true;
  }

  final sourceBytes = await source.readAsBytes();
  final targetBytes = await target.readAsBytes();
  if (sourceBytes.length != targetBytes.length) {
    return true;
  }

  for (var i = 0; i < sourceBytes.length; i++) {
    if (sourceBytes[i] != targetBytes[i]) {
      return true;
    }
  }

  return false;
}

Future<void> _copyFileReplacingIfDifferent(File source, File target) async {
  if (!await _filesDiffer(source, target)) {
    return;
  }

  await target.parent.create(recursive: true);
  if (await target.exists()) {
    await target.delete();
  }
  await source.copy(target.path);
}

bool _samePath(String a, String b) {
  String normalize(String input) {
    return input
        .replaceAll('/', '\\')
        .toLowerCase()
        .replaceAll(RegExp(r'\\+$'), '');
  }

  return normalize(a) == normalize(b);
}

String _pathFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/').where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? '' : segments.last;
}

String _entityName(FileSystemEntity entity) {
  return _pathFileName(entity.path);
}

Future<void> _migrateLegacyPresetFolders(Directory atlasDataDir) async {
  final presetsDir = Directory(
    joinPath([
      atlasDataDir.path,
      'static',
      'athenaprofiles',
      'Profile Presets',
    ]),
  );
  if (!await presetsDir.exists()) return;

  final configFile = File(
    joinPath([atlasDataDir.path, 'static', 'athenaprofiles', 'presets.json']),
  );
  List<Map<String, dynamic>> migrations = [];
  if (await configFile.exists()) {
    try {
      final contents = await configFile.readAsString();
      final config = jsonDecode(contents) as Map<String, dynamic>;
      final migrationsList = config['migrations'] as List<dynamic>? ?? [];
      for (final m in migrationsList) {
        migrations.add(m as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  if (migrations.isEmpty) {
    // Hardcoded fallback if presets.json is missing or invalid
    migrations = [
      {'from': 'Blank Profile', 'to': 'Empty Profile'},
      {'from': 'Blank', 'to': 'Empty Profile'},
      {'from': 'Reboot X Pulse Profile', 'to': 'Pulse Profile'},
      {'from': 'Reboot X Stellar Profile', 'to': 'Stellar Profile'},
      {'from': 'Reboot X Tozo Profile', 'to': 'Tozo Profile'},
      {'from': 'Reboot X Retrac Profile', 'to': 'Retrac Profile'},
      {'from': 'Reboot X Twine Profile', 'to': 'Twine Profile'},
    ];
  }

  for (final migration in migrations) {
    final from = migration['from'] as String?;
    final to = migration['to'] as String?;
    if (from == null || to == null) continue;
    await _migratePresetFolderName(
      presetsDir: presetsDir,
      legacyFolderName: from,
      canonicalFolderName: to,
    );
  }
}

Future<void> _migratePresetFolderName({
  required Directory presetsDir,
  required String legacyFolderName,
  required String canonicalFolderName,
}) async {
  final legacyDir = Directory(joinPath([presetsDir.path, legacyFolderName]));
  if (!await legacyDir.exists()) return;

  final canonicalDir = Directory(
    joinPath([presetsDir.path, canonicalFolderName]),
  );

  if (!await canonicalDir.exists()) {
    try {
      await legacyDir.rename(canonicalDir.path);
      return;
    } catch (_) {}
  }

  try {
    await legacyDir.delete(recursive: true);
  } catch (_) {}
}

String _resolveInstallerMigrationRoot() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final base = localAppData ?? Directory.systemTemp.path;
  return joinPath([base, 'ATLAS', 'installer-migration']);
}

Future<void> _restoreInstallerMigrationData(Directory atlasDataDir) async {
  final migrationRoot = Directory(_resolveInstallerMigrationRoot());
  if (!await migrationRoot.exists()) {
    return;
  }

  try {
    final legacyMsiResetMarker = File(
      joinPath([migrationRoot.path, _legacyMsiResetMarkerFileName]),
    );
    if (await legacyMsiResetMarker.exists()) {
      await _resetAtlasDataRootForLegacyMsiMigration(atlasDataDir);
      await migrationRoot.delete(recursive: true);
      return;
    }

    await _mergeInstallerMigrationData(
      migrationRoot: migrationRoot,
      atlasDataDir: atlasDataDir,
    );
    await migrationRoot.delete(recursive: true);
  } catch (_) {
    // Leave the staged data in place so the next launch can retry recovery.
  }
}

Future<void> _resetAtlasDataRootForLegacyMsiMigration(
  Directory atlasDataDir,
) async {
  if (await atlasDataDir.exists()) {
    await atlasDataDir.delete(recursive: true);
  }
  await atlasDataDir.create(recursive: true);
}

Future<void> _mergeInstallerMigrationData({
  required Directory migrationRoot,
  required Directory atlasDataDir,
}) async {
  Future<File> targetFile(List<String> relativeParts) async {
    final file = File(joinPath([atlasDataDir.path, ...relativeParts]));
    await file.parent.create(recursive: true);
    return file;
  }

  File sourceFile(List<String> relativeParts) {
    return File(joinPath([migrationRoot.path, ...relativeParts]));
  }

  Directory sourceDir(List<String> relativeParts) {
    return Directory(joinPath([migrationRoot.path, ...relativeParts]));
  }

  // Treat the installer-staged files as the authoritative pre-update user data.
  // New release additions are merged later from the install root.
  await _restoreFileFromInstallerMigration(
    sourceFile(['gui.ini']),
    await targetFile(['gui.ini']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['profiles-ui-state.json']),
    await targetFile(['static', 'athenaprofiles', 'profiles-ui-state.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'athenaprofiles', 'profiles-ui-state.json']),
    await targetFile(['static', 'athenaprofiles', 'profiles-ui-state.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'curvetables-state.json']),
    await targetFile(['responses', 'curvetables-state.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'datatables-ui.json']),
    await targetFile(['responses', 'datatables-ui.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'epic-settings.json']),
    await targetFile(['responses', 'epic-settings.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'straight-bloom-state.json']),
    await targetFile(['responses', 'straight-bloom-state.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'user-toggle-states.json']),
    await targetFile(['responses', 'user-toggle-states.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'modifications-backup.json']),
    await targetFile(['responses', 'modifications-backup.json']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'hotfixes', 'DefaultGame Data', 'StraightBloom.ini']),
    await targetFile([
      'static',
      'hotfixes',
      'DefaultGame Data',
      'StraightBloom.ini',
    ]),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'hotfixes', 'DefaultGame Data', 'Fixes.ini']),
    await targetFile(['static', 'hotfixes', 'DefaultGame Data', 'Fixes.ini']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'hotfixes', 'DefaultGame Data', 'CurveTables.ini']),
    await targetFile([
      'static',
      'hotfixes',
      'DefaultGame Data',
      'CurveTables.ini',
    ]),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'hotfixes', 'DefaultGame Data', 'DataTables.ini']),
    await targetFile([
      'static',
      'hotfixes',
      'DefaultGame Data',
      'DataTables.ini',
    ]),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'user-curvetables.ini']),
    await targetFile(['responses', 'user-curvetables.ini']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['responses', 'user-datatables.ini']),
    await targetFile(['responses', 'user-datatables.ini']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['src', 'config', 'config.ini']),
    await targetFile(['src', 'config', 'config.ini']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'hotfixes', 'DefaultGame.ini']),
    await targetFile(['static', 'hotfixes', 'DefaultGame.ini']),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'hotfixes', 'DefaultEngine.ini']),
    await targetFile(['static', 'hotfixes', 'DefaultEngine.ini']),
  );

  await _mergeCustomCurvesJson(
    sourceFile(['responses', 'curves.json']),
    await targetFile(['responses', 'curves.json']),
  );
  await _mergeCustomDataTablesJson(
    sourceFile(['responses', 'datatables.json']),
    await targetFile(['responses', 'datatables.json']),
  );

  await _restoreDirectoryContentsFromInstallerMigration(
    sourceDir(['static', 'athenaprofiles', 'Profile Presets']),
    Directory(
      joinPath([
        atlasDataDir.path,
        'static',
        'athenaprofiles',
        'Profile Presets',
      ]),
    ),
  );
  await _restoreFileFromInstallerMigration(
    sourceFile(['static', 'athenaprofiles', 'custom-presets.json']),
    await targetFile(['static', 'athenaprofiles', 'custom-presets.json']),
  );
  await _restoreDirectoryContentsFromInstallerMigration(
    sourceDir(['static', 'ClientSettings']),
    Directory(joinPath([atlasDataDir.path, 'static', 'ClientSettings'])),
  );
  await _restoreDirectoryContentsFromInstallerMigration(
    sourceDir(['static', 'profiles']),
    Directory(joinPath([atlasDataDir.path, 'static', 'profiles'])),
  );
  await _restoreDirectoryContentsFromInstallerMigration(
    sourceDir(['exports']),
    Directory(joinPath([atlasDataDir.path, 'exports'])),
  );
  await _restoreDirectoryContentsFromInstallerMigration(
    sourceDir(['public', 'items', 'custom-groups']),
    Directory(
      joinPath([atlasDataDir.path, 'public', 'items', 'custom-groups']),
    ),
  );
  await _restoreMatchingFilesFromInstallerMigration(
    sourceDir(['public', 'items']),
    Directory(joinPath([atlasDataDir.path, 'public', 'items'])),
    (name) => name.toLowerCase().startsWith('custom_'),
  );

  await DataTableService.ensureAtlasTextHotfixInDefaultGame();
}

Future<void> _restoreFileFromInstallerMigration(
  File source,
  File target,
) async {
  if (!await source.exists()) {
    return;
  }

  await target.parent.create(recursive: true);
  await target.writeAsBytes(await source.readAsBytes(), flush: true);
}

Future<void> _restoreDirectoryContentsFromInstallerMigration(
  Directory source,
  Directory target,
) async {
  if (!await source.exists()) {
    return;
  }

  await target.create(recursive: true);

  await for (final entity in source.list(followLinks: false)) {
    final name = _entityName(entity);
    if (name.isEmpty) continue;

    final targetPath = joinPath([target.path, name]);
    if (entity is Directory) {
      await _restoreDirectoryContentsFromInstallerMigration(
        entity,
        Directory(targetPath),
      );
      continue;
    }

    if (entity is File) {
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(await entity.readAsBytes(), flush: true);
    }
  }
}

Future<void> _restoreMatchingFilesFromInstallerMigration(
  Directory source,
  Directory target,
  bool Function(String name) shouldCopy,
) async {
  if (!await source.exists()) {
    return;
  }

  await target.create(recursive: true);

  await for (final entity in source.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = _entityName(entity);
    if (name.isEmpty || !shouldCopy(name)) continue;

    final targetFile = File(joinPath([target.path, name]));
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(await entity.readAsBytes(), flush: true);
  }
}

Future<Map<String, dynamic>?> _readJsonObject(File file) async {
  if (!await file.exists()) {
    return null;
  }

  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } catch (_) {}

  return null;
}

Future<void> _mergeCustomDataTablesJson(File source, File target) async {
  final sourceMap = await _readJsonObject(source);
  if (sourceMap == null || sourceMap.isEmpty) {
    return;
  }

  if (!await target.exists()) {
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return;
  }

  final targetMap = await _readJsonObject(target);
  if (targetMap == null) {
    return;
  }

  var changed = false;
  for (final entry in sourceMap.entries) {
    if (!entry.key.startsWith('custom-')) {
      continue;
    }
    if (targetMap.containsKey(entry.key)) {
      continue;
    }
    targetMap[entry.key] = entry.value;
    changed = true;
  }

  if (!changed) {
    return;
  }

  await target.writeAsString(
    const JsonEncoder.withIndent('  ').convert(targetMap),
  );
}

Future<void> _mergeCustomCurvesJson(File source, File target) async {
  final sourceMap = await CurveTableService._readCurveMap(source);
  if (sourceMap == null || sourceMap.isEmpty) {
    return;
  }

  if (!await target.exists()) {
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return;
  }

  final targetMap = await CurveTableService._readCurveMap(target);
  if (targetMap == null) {
    return;
  }

  final existingSignatures = <String>{};
  for (final value in targetMap.values) {
    if (value is! Map) continue;
    final signature = CurveTableService._curveSignature(
      Map<String, dynamic>.from(value),
    );
    if (signature.isNotEmpty) {
      existingSignatures.add(signature);
    }
  }

  var maxId = 0;
  for (final id in targetMap.keys) {
    final parsed = int.tryParse(id);
    if (parsed != null && parsed > maxId) {
      maxId = parsed;
    }
  }

  var changed = false;
  final sourceEntries = sourceMap.entries.toList()
    ..sort((a, b) {
      final aId = int.tryParse(a.key) ?? (1 << 30);
      final bId = int.tryParse(b.key) ?? (1 << 30);
      return aId.compareTo(bId);
    });

  for (final entry in sourceEntries) {
    if (entry.value is! Map) {
      continue;
    }

    final curveData = Map<String, dynamic>.from(entry.value);
    final isRelevant =
        curveData['isCustom'] == true ||
        (curveData['groupImagePath']?.toString().contains('custom-groups/') ??
            false);
    if (!isRelevant) {
      continue;
    }

    final signature = CurveTableService._curveSignature(curveData);
    if (signature.isNotEmpty && existingSignatures.contains(signature)) {
      continue;
    }

    maxId += 1;
    targetMap['$maxId'] = jsonDecode(jsonEncode(curveData));
    if (signature.isNotEmpty) {
      existingSignatures.add(signature);
    }
    changed = true;
  }

  if (!changed) {
    return;
  }

  await target.writeAsString(
    const JsonEncoder.withIndent('  ').convert(targetMap),
  );
}

class AtlasApp extends StatefulWidget {
  const AtlasApp({super.key});

  @override
  State<AtlasApp> createState() => _AtlasAppState();
}

class _AtlasAppState extends State<AtlasApp> {
  int _acrylicToken = 0;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    appBackgroundPath.addListener(_scheduleAcrylicUpdate);
  }

  Future<void> _loadTheme() async {
    final config = await ConfigService.load();
    appThemeMode.value = ThemeMode.dark;
    appBackgroundPath.value = config.backgroundImagePath;
    appBackgroundBlur.value = config.backgroundBlur;
    appBackgroundParticlesOpacity.value = config.backgroundParticlesOpacity;
    appDialogBlurEnabled.value = config.dialogBlurEnabled;
    appStartupAnimationEnabled.value = config.startupAnimationEnabled;
    _scheduleAcrylicUpdate();
  }

  @override
  void dispose() {
    appBackgroundPath.removeListener(_scheduleAcrylicUpdate);
    super.dispose();
  }

  void _scheduleAcrylicUpdate() {
    final token = ++_acrylicToken;
    _applyAcrylicForBackground(appBackgroundPath.value).then((_) {
      if (!mounted || token != _acrylicToken) return;
    });
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF64D7FF);
    const accentBlue = Color(0xFF1E88E5);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (_, mode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ATLAS Backend',
        themeMode: mode,
        scrollBehavior: const _AtlasScrollBehavior(),
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF2F4F7),
          colorScheme: const ColorScheme.light(
            primary: seed,
            secondary: accentBlue,
            surface: Color(0xFFF7F9FC),
            onSurface: Color(0xFF121724),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accentBlue,
            inactiveTrackColor: accentBlue.withOpacity(0.2),
            thumbColor: accentBlue,
            overlayColor: accentBlue.withOpacity(0.2),
            valueIndicatorColor: accentBlue,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return accentBlue;
              return Colors.grey.shade400;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return accentBlue.withOpacity(0.55);
              }
              return Colors.black.withOpacity(0.2);
            }),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accentBlue),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E14),
          colorScheme: const ColorScheme.dark(
            primary: seed,
            secondary: accentBlue,
            surface: Color(0xFF101722),
            onSurface: Color(0xFFE9F1FF),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accentBlue,
            inactiveTrackColor: accentBlue.withOpacity(0.25),
            thumbColor: accentBlue,
            overlayColor: accentBlue.withOpacity(0.25),
            valueIndicatorColor: accentBlue,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return accentBlue;
              return Colors.white54;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return accentBlue.withOpacity(0.55);
              }
              return Colors.white24;
            }),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accentBlue),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        home: const AtlasHomePage(),
      ),
    );
  }
}

class _AtlasScrollBehavior extends MaterialScrollBehavior {
  const _AtlasScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const _SmoothScrollPhysics(
      parent: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    // Keep mouse drag selection available inside text inputs on desktop.
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class _SmoothScrollPhysics extends ScrollPhysics {
  const _SmoothScrollPhysics({super.parent, this.multiplier = 0.35});

  final double multiplier;

  @override
  _SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SmoothScrollPhysics(
      parent: buildParent(ancestor),
      multiplier: multiplier,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * multiplier);
  }
}

final _atlasToastManager = _AtlasToastManager();

void showAtlasSnackBar(BuildContext context, SnackBar snackBar) {
  final message = _snackBarMessage(snackBar);
  if (message == null || message.trim().isEmpty) return;
  _atlasToastManager.show(context, message);
}

String? _snackBarMessage(SnackBar snackBar) {
  final content = snackBar.content;
  if (content is! Text) return null;
  final plain = content.data;
  if (plain != null) return plain;
  final span = content.textSpan;
  if (span != null) return span.toPlainText();
  return null;
}

class _AtlasToastManager {
  OverlayEntry? _toastOverlayEntry;
  final GlobalKey<_ToastOverlayHostState> _toastHostKey =
      GlobalKey<_ToastOverlayHostState>();

  void show(BuildContext context, String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    if (!_ensureToastOverlayReady(context)) return;
    _toastHostKey.currentState?.show(trimmed);
  }

  bool _ensureToastOverlayReady(BuildContext context) {
    if (_toastOverlayEntry != null) return true;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;

    _toastOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final safePadding = MediaQuery.of(overlayContext).padding;
        return Positioned(
          right: 18 + safePadding.right,
          bottom: 18 + safePadding.bottom,
          child: Material(
            color: Colors.transparent,
            child: _ToastOverlayHost(
              key: _toastHostKey,
              onEmpty: () {
                _toastOverlayEntry?.remove();
                _toastOverlayEntry = null;
              },
            ),
          ),
        );
      },
    );
    overlay.insert(_toastOverlayEntry!);
    return true;
  }
}

class _ToastOverlayHost extends StatefulWidget {
  const _ToastOverlayHost({super.key, required this.onEmpty});

  final VoidCallback onEmpty;

  @override
  State<_ToastOverlayHost> createState() => _ToastOverlayHostState();
}

class _ToastOverlayHostState extends State<_ToastOverlayHost> {
  static const _toastDuration = Duration(seconds: 3);
  final GlobalKey<_AnimatedToastCardState> _cardKey =
      GlobalKey<_AnimatedToastCardState>();
  Timer? _timer;
  String _message = '';

  void show(String message) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    _timer?.cancel();
    _message = trimmed;

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardKey.currentState?.show(_message);
    });

    _timer = Timer(_toastDuration, () {
      if (!mounted) return;
      _cardKey.currentState?.dismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: _AnimatedToastCard(
        key: _cardKey,
        initialMessage: _message,
        onDismissed: widget.onEmpty,
      ),
    );
  }
}

class _AnimatedToastCard extends StatefulWidget {
  const _AnimatedToastCard({
    super.key,
    required this.initialMessage,
    required this.onDismissed,
  });

  final String initialMessage;
  final VoidCallback onDismissed;

  @override
  State<_AnimatedToastCard> createState() => _AnimatedToastCardState();
}

class _AnimatedToastCardState extends State<_AnimatedToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _dismissing = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    final reverseCurve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(reverseCurve);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(curve);
    _message = widget.initialMessage;
    if (_message.trim().isNotEmpty) {
      _controller.forward();
    }
  }

  void show(String message) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _message = trimmed;
    });

    final wasHidden = _controller.value <= 0.001;
    _dismissing = false;

    _controller.stop();
    if (wasHidden) {
      _controller
        ..value = 0
        ..forward();
    } else {
      _controller.value = 1;
    }
  }

  Future<void> dismiss() async {
    if (!mounted || _dismissing) return;
    _dismissing = true;
    try {
      await _controller.reverse();
    } finally {
      if (mounted) widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = _onSurface(context, 0.92);
    const radius = 18.0;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: _dialogShadowColor(context),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _dialogSurfaceColor(context),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: _onSurface(context, 0.12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    _message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> _showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final baseTheme = Theme.of(dialogContext);
      final dialogTheme = baseTheme.copyWith(
        dialogTheme: DialogThemeData(
          backgroundColor: _dialogSurfaceColor(dialogContext),
          elevation: 0,
          shadowColor: _dialogShadowColor(dialogContext),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _onSurface(dialogContext, 0.1)),
          ),
          titleTextStyle: baseTheme.textTheme.headlineSmall?.copyWith(
            color: _onSurface(dialogContext, 0.96),
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
            color: _onSurface(dialogContext, 0.9),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: baseTheme.colorScheme.secondary,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      return SafeArea(
        child: Center(
          child: Theme(
            data: dialogTheme,
            child: Builder(builder: (themeContext) => builder(themeContext)),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final blurEnabled = appDialogBlurEnabled.value;
      return Stack(
        children: [
          Positioned.fill(
            child: blurEnabled
                ? BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 3.2 * curved.value,
                      sigmaY: 3.2 * curved.value,
                    ),
                    child: Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
                  )
                : Container(
                    color: _dialogBarrierColor(dialogContext, curved.value),
                  ),
          ),
          FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.975, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

class AtlasHomePage extends StatefulWidget {
  const AtlasHomePage({super.key});

  @override
  State<AtlasHomePage> createState() => _AtlasHomePageState();
}

class _AtlasHomePageState extends State<AtlasHomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final BackendController _controller;
  bool _exitInProgress = false;
  bool _checkingUpdate = false;
  bool _loadingReleaseHistory = false;
  List<ReleaseInfo> _releaseHistory = const [];
  String _backendVersionLabel = '1.0.0';
  bool _showStartupAnimation = true;
  bool _startupAnimationWasShown = true;
  bool _startupIntroFinished = false;
  bool _revealHomeContent = false;
  bool _startupWarmupActive = false;
  bool _startupWarmupStarted = false;
  bool _startupWarmupComplete = false;
  double _startupWarmupProgress = 0.0;
  String _startupWarmupLabel = 'Loading backend data...';
  bool _postStartupTasksQueued = false;
  late final AnimationController _shellEntranceController;
  late final Animation<double> _shellEntranceFade;
  late final Animation<double> _shellEntranceScale;
  late final VoidCallback _startupAnimationListener;
  final Completer<void> _startupAnimationGate = Completer<void>();
  final Completer<void> _homeRevealGate = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BackendController()..startPolling();
    _shellEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _shellEntranceFade = CurvedAnimation(
      parent: _shellEntranceController,
      curve: const Interval(0.0, 0.92, curve: Curves.easeOutCubic),
    );
    _shellEntranceScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _shellEntranceController,
        curve: Curves.easeOutCubic,
      ),
    );
    _showStartupAnimation = appStartupAnimationEnabled.value;
    _startupAnimationWasShown = _showStartupAnimation;
    if (!_showStartupAnimation) {
      _startupIntroFinished = true;
      _startupAnimationGate.complete();
    }
    _startupAnimationListener = () {
      if (!mounted) return;
      if (!appStartupAnimationEnabled.value && _showStartupAnimation) {
        setState(() {
          _showStartupAnimation = false;
          _startupIntroFinished = true;
        });
        if (!_startupAnimationGate.isCompleted) {
          _startupAnimationGate.complete();
        }
        _tryRevealHomeContent();
        unawaited(_beginStartupWarmup());
      }
    };
    appStartupAnimationEnabled.addListener(_startupAnimationListener);
    unawaited(_initStartup());
    unawaited(_loadBackendVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmUiAssets());
      unawaited(_beginStartupWarmup());
      unawaited(_runPostStartupTasks());
    });
  }

  Future<void> _warmUiAssets() async {
    if (!mounted) return;

    final candidatePaths = <String>{
      joinPath([
        getBackendRoot(),
        'public',
        'images',
        'DefaultBackground.webp',
      ]),
      joinPath([getBackendRoot(), 'public', 'gameconfig', 'default.webp']),
    };
    final resolvedBackgroundPath = _resolveBackgroundPath(
      appBackgroundPath.value,
    );
    if (resolvedBackgroundPath != null) {
      candidatePaths.add(resolvedBackgroundPath);
    }

    for (final path in candidatePaths) {
      final provider = _atlasBackgroundImageProvider(path);
      if (provider == null) continue;
      try {
        await precacheImage(provider, context);
      } catch (_) {}
      if (!mounted) return;
    }
  }

  void _finishStartupAnimation() {
    if (!mounted || !_showStartupAnimation) return;
    setState(() {
      _showStartupAnimation = false;
      _startupIntroFinished = true;
    });
    if (!_startupAnimationGate.isCompleted) {
      _startupAnimationGate.complete();
    }
    _tryRevealHomeContent();
  }

  void _tryRevealHomeContent() {
    if (!mounted ||
        _revealHomeContent ||
        !_startupIntroFinished ||
        !_startupWarmupComplete) {
      return;
    }

    setState(() {
      _revealHomeContent = true;
    });
    if (!_homeRevealGate.isCompleted) {
      _homeRevealGate.complete();
    }
    _shellEntranceController.forward(from: 0);
  }

  Future<void> _beginStartupWarmup() async {
    if (_startupWarmupStarted) return;
    _startupWarmupStarted = true;
    if (mounted) {
      setState(() {
        _startupWarmupActive = true;
        _startupWarmupComplete = false;
        _startupWarmupProgress = 0.0;
        _startupWarmupLabel = 'Loading backend data...';
      });
    }

    final tasks = <(String, Future<void> Function())>[
      (
        'Loading menu data...',
        () async {
          await _ModificationsScreenCache.warm(forceRefresh: false);
        },
      ),
      (
        'Loading arena data...',
        () async {
          await _ArenaScreenCache.warm();
        },
      ),
      (
        'Loading profile data...',
        () async {
          await _ProfilesScreenCache.warm();
        },
      ),
      (
        'Loading user values...',
        () async {
          await _UserValuesWarmupCache.warm();
        },
      ),
    ];

    for (var i = 0; i < tasks.length; i++) {
      if (!mounted) return;
      setState(() {
        _startupWarmupLabel = tasks[i].$1;
        _startupWarmupProgress = i / tasks.length;
      });
      try {
        await tasks[i].$2();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _startupWarmupProgress = (i + 1) / tasks.length;
      });
      await _yieldForUi();
    }

    if (!mounted) return;
    setState(() {
      _startupWarmupActive = false;
      _startupWarmupComplete = true;
      _startupWarmupLabel = 'Loading backend data...';
      _startupWarmupProgress = 1.0;
    });
    _tryRevealHomeContent();
  }

  Future<void> _runPostStartupTasks() async {
    if (_postStartupTasksQueued) return;
    _postStartupTasksQueued = true;

    await _homeRevealGate.future;
    if (!mounted) return;

    await _waitForShellEntranceAnimation();
    if (!mounted) return;

    await _yieldForUi();
    if (!mounted) return;

    await UpdateBackupService.restoreIfNeeded(context);
    if (!mounted) return;

    await _yieldForUi();
    if (!mounted) return;

    await _maybeCheckForUpdatesOnLaunch();
    if (!mounted) return;

    await _yieldForUi();
    if (!mounted) return;

    await _maybeShowUpdateNotesOnLaunch();
  }

  Future<void> _waitForShellEntranceAnimation() async {
    if (_shellEntranceController.value >= 1.0) return;

    final completer = Completer<void>();
    late AnimationStatusListener listener;
    listener = (status) {
      if (status == AnimationStatus.completed && !completer.isCompleted) {
        completer.complete();
      }
    };

    _shellEntranceController.addStatusListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // If the entrance animation is interrupted, continue startup tasks.
    } finally {
      _shellEntranceController.removeStatusListener(listener);
    }
  }

  Future<void> _yieldForUi() async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _maybeCheckForUpdatesOnLaunch() async {
    final config = await ConfigService.load();
    if (config.disableBackendUpdateCheck) return;
    await _checkForUpdates(silent: true);
  }

  Future<void> _initStartup() async {
    final config = await ConfigService.load();
    await DataTableService.setBackendInfiniteRenderEnabled(
      config.backendInfiniteRenderEnabled,
    );
    await DataTableService.setSwapCooldownEnabled(config.swapCooldownEnabled);
    if (config.startBackendOnLaunch) {
      await _controller.ensureStoppedOnLaunch();
      await _controller.startBackend();
    } else {
      await _controller.ensureStoppedOnLaunch();
    }
  }

  Future<void> _loadBackendVersion() async {
    final version = await _readBackendVersion();
    if (version.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _backendVersionLabel = version;
    });
  }

  Future<String> _readBackendVersion() async {
    return _readBackendVersionFromCandidates();
  }

  Future<void> _checkForUpdates({required bool silent}) async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    final info = await UpdateService.checkForUpdate();
    _checkingUpdate = false;
    if (!mounted) return;
    if (info == null) {
      if (!silent) {
        showAtlasSnackBar(
          context,
          const SnackBar(content: Text('No updates available.')),
        );
      }
      return;
    }
    await _showUpdateDialog(info);
  }

  Future<void> _maybeShowUpdateNotesOnLaunch() async {
    final currentVersion = await _readBackendVersion();
    if (currentVersion.isEmpty) return;
    final config = await ConfigService.load();
    final normalizedCurrent = _normalizeVersion(currentVersion);
    final normalizedLast = _normalizeVersion(
      config.lastShownUpdateNotesVersion,
    );
    if (normalizedCurrent.isEmpty || normalizedCurrent == normalizedLast) {
      return;
    }

    final notesPayload = await UpdateNotesService.loadNotes();
    if (notesPayload == null) return;
    if (!mounted) return;
    await _showUpdateNotesDialog(
      normalizedCurrent,
      notesPayload.notes,
      notesPayload.style,
    );
    if (!mounted) return;
    await ConfigService.save(
      config.copyWith(lastShownUpdateNotesVersion: normalizedCurrent),
    );
  }

  Future<void> _showUpdateNotesDialog(
    String version,
    String notes,
    UpdateNotesStyle style,
  ) async {
    await _showBlurDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded),
            const SizedBox(width: 10),
            const Text('What\'s New'),
            const Spacer(),
            _VersionTag(
              label: _formatVersion(version),
              color: Colors.greenAccent,
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: notes,
                styleSheet: MarkdownStyleSheet.fromTheme(
                  Theme.of(dialogContext),
                ).copyWith(p: Theme.of(dialogContext).textTheme.bodyMedium),
                blockSyntaxes: _roundedHrBlockSyntaxes,
                inlineSyntaxes: _roundedHrInlineSyntaxes,
                builders: {
                  'rounded-hr': _MarkdownHrBuilder(
                    color: _onSurface(
                      dialogContext,
                      style.hrOpacity.clamp(0.0, 1.0),
                    ),
                    thickness: style.hrThickness <= 0
                        ? UpdateNotesService._defaultStyle.hrThickness
                        : style.hrThickness,
                    verticalPadding: 10,
                  ),
                },
                onTapLink: (text, href, title) async {
                  if (href == null) return;
                  final url = Uri.tryParse(href);
                  if (url == null) return;
                  await _openUrl(url.toString());
                },
              ),
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVersionHistoryMenu(BuildContext anchorContext) async {
    if (_loadingReleaseHistory) return;
    setState(() => _loadingReleaseHistory = true);
    final history = await UpdateService.fetchReleaseHistory();
    if (!mounted || !anchorContext.mounted) return;
    setState(() {
      if (history.isNotEmpty) {
        _releaseHistory = history;
      }
      _loadingReleaseHistory = false;
    });

    final currentVersion = _normalizeVersion(_backendVersionLabel);
    final newerReleases = _releaseHistory
        .where(
          (release) =>
              _compareVersions(
                _normalizeVersion(release.version),
                currentVersion,
              ) >
              0,
        )
        .toList();
    final olderReleases = _releaseHistory
        .where(
          (release) =>
              _compareVersions(
                _normalizeVersion(release.version),
                currentVersion,
              ) <
              0,
        )
        .toList();

    if (newerReleases.isEmpty && olderReleases.isEmpty) {
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('No other versions available.')),
      );
      return;
    }

    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + box.size.height,
        box.size.width,
        box.size.height,
      ),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<ReleaseInfo>(
      context: anchorContext,
      position: position,
      color: Theme.of(context).colorScheme.surface.withOpacity(0.98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _onSurface(context, 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      items: [
        PopupMenuItem<ReleaseInfo>(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          onTap: () {
            unawaited(_showCurrentVersionNotes(anchorContext));
          },
          child: Text(
            'Current: ${_formatVersion(currentVersion)}',
            style: TextStyle(color: _onSurface(context, 0.7)),
          ),
        ),
        if (newerReleases.isNotEmpty) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<ReleaseInfo>(
            enabled: false,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              'Newer versions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _onSurface(context, 0.6),
              ),
            ),
          ),
          ...newerReleases.map((release) {
            final dateLabel = release.publishedAt == null
                ? null
                : _formatReleaseDate(release.publishedAt!);
            return PopupMenuItem<ReleaseInfo>(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              value: release,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatVersion(release.version),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (dateLabel != null)
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.0,
                        color: _onSurface(context, 0.6),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
        if (olderReleases.isNotEmpty) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<ReleaseInfo>(
            enabled: false,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              'Older versions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _onSurface(context, 0.6),
              ),
            ),
          ),
          ...olderReleases.map((release) {
            final dateLabel = release.publishedAt == null
                ? null
                : _formatReleaseDate(release.publishedAt!);
            return PopupMenuItem<ReleaseInfo>(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              value: release,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatVersion(release.version),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (dateLabel != null)
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.0,
                        color: _onSurface(context, 0.6),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ],
    );

    if (selected == null) return;
    final selectedVersion = _normalizeVersion(selected.version);
    final isUpgrade = _compareVersions(selectedVersion, currentVersion) > 0;

    final info = UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: selectedVersion,
      downloadUrl: selected.downloadUrl,
      isInstaller: true,
      notes: selected.notes,
      currentCommit: null,
      latestCommit: null,
    );
    await _showUpdateDialog(
      info,
      title: isUpgrade ? 'Update available' : 'Downgrade available',
      actionLabel: isUpgrade ? 'Update' : 'Downgrade',
    );
  }

  Future<void> _showCurrentVersionNotes(BuildContext _) async {
    final currentVersion = await _readBackendVersion();
    if (!mounted) return;
    if (currentVersion.isEmpty) {
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Current version unavailable.')),
      );
      return;
    }

    final notesPayload = await UpdateNotesService.loadNotes();
    if (!mounted) return;
    if (notesPayload == null) {
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('No update notes found.')),
      );
      return;
    }

    await _showUpdateNotesDialog(
      _normalizeVersion(currentVersion),
      notesPayload.notes,
      notesPayload.style,
    );
  }

  Future<void> _showUpdateDialog(
    UpdateInfo info, {
    String title = 'An update is available',
    String actionLabel = 'Update now',
  }) async {
    final progress = ValueNotifier<double>(0);
    bool updating = false;
    String? error;
    final notes = info.notes?.trim() ?? '';
    Future<void> restartApp() async {
      final exePath = Platform.resolvedExecutable;
      if (exePath.isNotEmpty) {
        try {
          await Process.start(
            exePath,
            const [],
            mode: ProcessStartMode.detached,
          );
        } catch (_) {}
      }
      exit(0);
    }

    await _showBlurDialog<void>(
      context: context,
      barrierDismissible: !updating,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Widget buildVersionTag({
            required String label,
            required Color accent,
          }) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: accent.withOpacity(0.2),
                border: Border.all(color: accent.withOpacity(0.55)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: _onSurface(context, 0.96),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            );
          }

          return Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Container(
                decoration: BoxDecoration(
                  color: _dialogSurfaceColor(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _onSurface(context, 0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: _dialogShadowColor(context),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: _onSurface(context, 0.95),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          buildVersionTag(
                            label: info.currentLabel,
                            accent: const Color(0xFFDC3545),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'to',
                            style: TextStyle(
                              color: _onSurface(context, 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          buildVersionTag(
                            label: info.latestLabel,
                            accent: const Color(0xFF16C47F),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: _adaptiveScrimColor(
                            context,
                            darkAlpha: 0.08,
                            lightAlpha: 0.18,
                          ),
                          border: Border.all(color: _onSurface(context, 0.1)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: _onSurface(context, 0.82),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                info.isInstaller
                                    ? 'ATLAS Backend will download the latest setup and launch it. The backend will close so the update can install.'
                                    : 'ATLAS Backend will download the latest update package, apply it, and restart automatically.',
                                style: TextStyle(
                                  color: _onSurface(context, 0.78),
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: SingleChildScrollView(
                            child: MarkdownBody(
                              data: notes,
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(
                                    Theme.of(context),
                                  ).copyWith(
                                    p: TextStyle(
                                      color: _onSurface(context, 0.9),
                                      height: 1.35,
                                    ),
                                    horizontalRuleDecoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          width: 2.0,
                                          color: _onSurface(context, 0.12),
                                        ),
                                      ),
                                    ),
                                  ),
                              onTapLink: (text, href, title) async {
                                if (href == null || href.trim().isEmpty) return;
                                await _openUrl(href);
                              },
                            ),
                          ),
                        ),
                      ],
                      if (updating) ...[
                        const SizedBox(height: 14),
                        ValueListenableBuilder<double>(
                          valueListenable: progress,
                          builder: (context, value, _) {
                            final clamped = value.clamp(0.0, 1.0);
                            final isIndeterminate =
                                clamped <= 0 || clamped >= 1;
                            final pct = (clamped * 100).toStringAsFixed(0);
                            final status = clamped >= 1
                                ? (info.isInstaller
                                      ? 'Launching installer...'
                                      : 'Applying update...')
                                : clamped > 0
                                ? (info.isInstaller
                                      ? 'Downloading latest setup... $pct%'
                                      : 'Downloading update package... $pct%')
                                : 'Preparing download...';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: isIndeterminate ? null : clamped,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: _onSurface(context, 0.82),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFFDC3545),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _HoverScale(
                            child: TextButton(
                              onPressed: updating
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text('Later'),
                            ),
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _HoverScale(
                              child: TextButton(
                                onPressed: updating
                                    ? null
                                    : () => _showUpdateNotesDialog(
                                        info.latestVersion,
                                        notes,
                                        UpdateNotesService._defaultStyle,
                                      ),
                                child: const Text('Update notes'),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          _HoverScale(
                            child: ElevatedButton(
                              onPressed: updating
                                  ? null
                                  : () async {
                                      setState(() {
                                        updating = true;
                                        error = null;
                                      });
                                      try {
                                        await _controller.stopBackend();
                                        await UpdateBackupService.backupBeforeUpdate();
                                        await UpdateService.downloadAndApply(
                                          info,
                                          progress,
                                        );
                                        if (!mounted ||
                                            !dialogContext.mounted) {
                                          return;
                                        }
                                        Navigator.of(dialogContext).pop();
                                        showAtlasSnackBar(
                                          this.context,
                                          SnackBar(
                                            content: Text(
                                              'Updated to ${info.latestLabel}. Restarting...',
                                            ),
                                          ),
                                        );
                                        await Future<void>.delayed(
                                          const Duration(milliseconds: 600),
                                        );
                                        await restartApp();
                                      } catch (err) {
                                        setState(() {
                                          error = 'Update failed: $err';
                                          updating = false;
                                        });
                                      } finally {
                                        progress.value = 0;
                                      }
                                    },
                              child: Text(
                                updating ? 'Updating...' : actionLabel,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appStartupAnimationEnabled.removeListener(_startupAnimationListener);
    _shellEntranceController.dispose();
    unawaited(_controller.stopBackend());
    unawaited(_controller.forceKillBackendPort());
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    if (_exitInProgress) return false;
    if (!_controller.isRunning) return true;
    _exitInProgress = true;
    final confirm = await DataService._confirmDialog(
      context,
      'Close the backend before exiting?',
    );
    if (confirm) {
      await _controller.stopBackend();
      await _controller.forceKillBackendPort();
    }
    _exitInProgress = false;
    return confirm;
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!mounted) return AppExitResponse.exit;
    if (_exitInProgress) return AppExitResponse.cancel;
    if (!_controller.isRunning) return AppExitResponse.exit;

    // Cancel the platform close request first, then show the confirmation dialog
    // on the next event-loop tick so the dialog transition can animate smoothly.
    Future<void>(() async {
      if (!mounted) return;
      final confirm = await _confirmExit();
      if (confirm) {
        exit(0);
      }
    });

    return AppExitResponse.cancel;
  }

  static const List<MenuItemData> _menuItems = [
    MenuItemData(
      title: 'Modifications',
      subtitle: 'Manage Straight Bloom, CurveTables, DataTables and more',
      icon: Icons.tune,
      accent: Color(0xFF6BE7FF),
      actions: [
        MenuAction(
          title: 'Toggle Straight Bloom',
          description: 'Enable or disable straight bloom.',
        ),
        MenuAction(
          title: 'Toggle CurveTables',
          description: 'Enable or disable all CurveTables.',
        ),
        MenuAction(
          title: 'CurveTable Settings',
          description: 'Manage individual tables.',
        ),
      ],
    ),
    MenuItemData(
      title: 'Arena',
      subtitle: 'Leaderboard and other arena settings',
      icon: Icons.emoji_events,
      accent: Color(0xFFFF6A8C),
      enabled: true,
      actions: [
        MenuAction(
          title: 'Arena Leaderboard',
          description: 'View top profiles.',
        ),
        MenuAction(
          title: 'Save Arena Points',
          description: 'Toggle saving points.',
        ),
      ],
    ),
    MenuItemData(
      title: 'Game Configuration',
      subtitle: 'Manage In Game Events and Stages',
      icon: Icons.settings_suggest,
      accent: Color(0xFF5BF2B3),
      actions: [
        MenuAction(title: 'Rufus Week Stage', description: 'Set 1-4.'),
        MenuAction(title: 'Water Level', description: 'Set 1-8.'),
        MenuAction(title: 'Water Storm', description: 'Toggle storm events.'),
      ],
    ),
    MenuItemData(
      title: 'Users',
      subtitle: 'Manage users, profiles, and client settings',
      icon: Icons.people_alt_rounded,
      accent: Color(0xFF7EE081),
      actions: [
        MenuAction(title: 'View Users', description: 'See all local users.'),
        MenuAction(
          title: 'Apply Preset',
          description: 'Replace a user with a preset.',
        ),
        MenuAction(
          title: 'Edit User Values',
          description: 'Modify level, V-Bucks, and other attributes.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final showIntro = _showStartupAnimation;
    final showIntroHold =
        _startupAnimationWasShown &&
        !showIntro &&
        !_revealHomeContent &&
        !_startupWarmupComplete;
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => _TopBar(
              textTheme: textTheme,
              statusText: _controller.statusText,
              statusColor: _controller.statusColor,
              versionLabel: _backendVersionLabel,
              onVersionPressed: _showVersionHistoryMenu,
              onSettingsPressed: () => Navigator.of(
                context,
              ).push(_buildRoute(const SettingsScreen())),
              onCheckUpdates: () => _checkForUpdates(silent: false),
              height: 110,
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: RepaintBoundary(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _MenuGrid(items: _menuItems)),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 2,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => _SidePanel(controller: _controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await _confirmExit();
        if (confirm) {
          exit(0);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            AtlasBackground(showParticles: true, animateParticles: !showIntro),
            if (_revealHomeContent)
              Positioned.fill(
                child: FadeTransition(
                  opacity: _shellEntranceFade,
                  child: ScaleTransition(
                    scale: _shellEntranceScale,
                    child: IgnorePointer(ignoring: showIntro, child: content),
                  ),
                ),
              ),
            if (showIntro)
              _AtlasStartupAnimationOverlay(onFinished: _finishStartupAnimation)
            else if (showIntroHold)
              const _AtlasStartupAnimationHoldOverlay()
            else if (!_revealHomeContent || _startupWarmupActive)
              _AtlasStartupWarmupOverlay(
                progress: _startupWarmupProgress,
                label: _startupWarmupLabel,
              ),
          ],
        ),
      ),
    );
  }
}

class _AtlasStartupWarmupOverlay extends StatefulWidget {
  const _AtlasStartupWarmupOverlay({
    required this.progress,
    required this.label,
  });

  final double progress;
  final String label;

  @override
  State<_AtlasStartupWarmupOverlay> createState() =>
      _AtlasStartupWarmupOverlayState();
}

class _AtlasStartupAnimationHoldOverlay extends StatelessWidget {
  const _AtlasStartupAnimationHoldOverlay();

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final startupLogoFigureless = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Logo-Figureless.png',
      ]),
    );
    final startupLogoDefault = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Logo.png',
      ]),
    );
    final textStyle = TextStyle(
      fontSize: 54,
      height: 1.0,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: dark ? Colors.white.withOpacity(0.95) : _onSurface(context, 0.96),
      fontFamily: 'Coolvetica',
      fontFamilyFallback: const ['Segoe UI', 'Arial', 'Roboto'],
      shadows: [
        Shadow(
          color: dark
              ? Colors.black.withOpacity(0.45)
              : Colors.black.withOpacity(0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return Positioned.fill(
      child: AbsorbPointer(
        child: RepaintBoundary(
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _adaptiveScrimColor(
                          context,
                          darkAlpha: 0.22,
                          lightAlpha: 0.08,
                        ),
                        _adaptiveScrimColor(
                          context,
                          darkAlpha: 0.34,
                          lightAlpha: 0.12,
                        ),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    startupLogoFigureless.existsSync()
                        ? Image.file(
                            startupLogoFigureless,
                            width: 180,
                            height: 180,
                            fit: BoxFit.contain,
                          )
                        : startupLogoDefault.existsSync()
                        ? Image.file(
                            startupLogoDefault,
                            width: 180,
                            height: 180,
                            fit: BoxFit.contain,
                          )
                        : Image.asset(
                            'assets/images/atlas_logo.png',
                            width: 180,
                            height: 180,
                            fit: BoxFit.contain,
                          ),
                    const SizedBox(height: 22),
                    Text(
                      'Launching ATLAS Backend',
                      textAlign: TextAlign.center,
                      style: textStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AtlasStartupWarmupOverlayState extends State<_AtlasStartupWarmupOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  )..repeat();

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final surface = _dialogSurfaceColor(context).withOpacity(0.92);
    final clampedProgress = widget.progress.clamp(0.0, 1.0);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.08),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _onSurface(context, 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, _) => _ArcSpinner(
                      progress: clampedProgress,
                      rotationTurns: _rotationController.value,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Loading backend data',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _onSurface(context, 0.7),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: clampedProgress <= 0 ? null : clampedProgress,
                      minHeight: 5,
                      backgroundColor: accent.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AtlasStartupAnimationOverlay extends StatefulWidget {
  const _AtlasStartupAnimationOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_AtlasStartupAnimationOverlay> createState() =>
      _AtlasStartupAnimationOverlayState();
}

class _AtlasStartupAnimationOverlayState
    extends State<_AtlasStartupAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _overlayOpacity;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoOffsetY;
  late final Animation<double> _textOpacity;
  late final Animation<double> _textOffsetY;
  late final Animation<double> _textBlur;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _overlayOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 90),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 10,
      ),
    ]).animate(_controller);

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.35, curve: Curves.easeOutCubic),
    );

    _logoOffsetY = Tween<double>(begin: -140.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.6, curve: Curves.easeOut),
    );

    _textOffsetY = Tween<double>(begin: 48.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        // Use a non-overshooting curve so the startup text doesn't "bounce".
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _textBlur = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final startupLogoFigureless = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Logo-Figureless.png',
      ]),
    );
    final startupLogoDefault = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Logo.png',
      ]),
    );
    final textStyle = TextStyle(
      fontSize: 54,
      height: 1.0,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: dark ? Colors.white.withOpacity(0.95) : _onSurface(context, 0.96),
      fontFamily: 'Coolvetica',
      fontFamilyFallback: const ['Segoe UI', 'Arial', 'Roboto'],
      shadows: [
        Shadow(
          color: dark
              ? Colors.black.withOpacity(0.45)
              : Colors.black.withOpacity(0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return Positioned.fill(
      child: AbsorbPointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Opacity(
                opacity: _overlayOpacity.value,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.22,
                                lightAlpha: 0.08,
                              ),
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.34,
                                lightAlpha: 0.12,
                              ),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            offset: Offset(0, _logoOffsetY.value),
                            child: Opacity(
                              opacity: _logoOpacity.value,
                              child: startupLogoFigureless.existsSync()
                                  ? Image.file(
                                      startupLogoFigureless,
                                      width: 180,
                                      height: 180,
                                      fit: BoxFit.contain,
                                    )
                                  : startupLogoDefault.existsSync()
                                  ? Image.file(
                                      startupLogoDefault,
                                      width: 180,
                                      height: 180,
                                      fit: BoxFit.contain,
                                    )
                                  : Image.asset(
                                      'assets/images/atlas_logo.png',
                                      width: 180,
                                      height: 180,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Transform.translate(
                            offset: Offset(0, _textOffsetY.value),
                            child: Opacity(
                              opacity: _textOpacity.value,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: _textBlur.value,
                                  sigmaY: _textBlur.value,
                                ),
                                child: Text(
                                  'Launching ATLAS Backend',
                                  textAlign: TextAlign.center,
                                  style: textStyle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.textTheme,
    required this.statusText,
    required this.statusColor,
    required this.versionLabel,
    required this.onVersionPressed,
    required this.onSettingsPressed,
    required this.onCheckUpdates,
    required this.height,
  });

  final TextTheme textTheme;
  final String statusText;
  final Color statusColor;
  final String versionLabel;
  final void Function(BuildContext context)? onVersionPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback? onCheckUpdates;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bannerFigureless = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Banner-Transparent-Figureless.png',
      ]),
    );
    final bannerDefault = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Banner-Transparent.png',
      ]),
    );
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showAboutDialog(context, versionLabel: versionLabel),
            child: bannerFigureless.existsSync()
                ? Image.file(bannerFigureless, height: 100, fit: BoxFit.contain)
                : bannerDefault.existsSync()
                ? Image.file(bannerDefault, height: 100, fit: BoxFit.contain)
                : Row(
                    children: [
                      Image.asset(
                        'assets/images/atlas_logo.png',
                        width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ATLAS Backend',
                            style: textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Backend control center',
                            style: textTheme.bodyMedium?.copyWith(
                              color: _onSurface(context, 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const Spacer(),
          SizedBox(
            width: 40,
            child: _HoverScale(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onSettingsPressed,
                icon: const Icon(Icons.settings_rounded),
                tooltip: 'Settings',
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(label: 'Backend', value: statusText, color: statusColor),
          const SizedBox(width: 16),
          Builder(
            builder: (pillContext) => _HoverScale(
              enabled: onVersionPressed != null,
              child: GestureDetector(
                onTap: onVersionPressed == null
                    ? null
                    : () => onVersionPressed!(pillContext),
                child: _StatusPill(
                  label: 'Version',
                  value: versionLabel,
                  color: _onSurface(context, 0.24),
                  trailing: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _onSurface(context, 0.6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: _HoverScale(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Check for updates',
                onPressed: onCheckUpdates,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  final String label;
  final String value;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _VersionTag extends StatelessWidget {
  const _VersionTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _onSurface(context, 0.96),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AtlasTagPill extends StatelessWidget {
  const _AtlasTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0E3F73),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2F9CFF).withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF7FC4FF),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.items});

  final List<MenuItemData> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.6,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MenuCard(
          data: item,
          onTap: item.enabled
              ? () {
                  Navigator.of(
                    context,
                  ).push(_buildRoute(_pageForMenu(item.title)));
                }
              : null,
        );
      },
    );
  }
}

class MenuCard extends StatefulWidget {
  const MenuCard({super.key, required this.data, required this.onTap});

  final MenuItemData data;
  final VoidCallback? onTap;

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.data.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = widget.data.enabled && widget.onTap != null;
    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _hovered && isEnabled ? 1.02 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isEnabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(isDark ? 0.22 : 0.32),
                    isDark ? const Color(0xFF141B26) : const Color(0xFFF2F5FB),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _hovered && isEnabled
                      ? accent.withOpacity(0.8)
                      : _onSurface(context, 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  if (isDark)
                    BoxShadow(
                      color: _menuShadowColor(context, accent),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    )
                  else ...[
                    BoxShadow(
                      color: _menuShadowColor(context, accent),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(widget.data.icon, color: accent, size: 26),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: _onSurface(context, 0.7),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.data.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.data.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _onSurface(context, 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller});

  final BackendController controller;
  static final ScrollController _logsController = ScrollController();
  static int _lastLogCount = 0;

  @override
  Widget build(BuildContext context) {
    final logCount = controller.recentLogs.length;
    if (logCount != _lastLogCount) {
      _lastLogCount = logCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logsController.hasClients) {
          _logsController.animateTo(
            _logsController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _ActionButton(
              label: controller.isStarting ? 'Starting...' : 'Start Backend',
              icon: Icons.play_arrow_rounded,
              color: const Color(0xFF5BE0B3),
              onPressed:
                  (controller.isRunning ||
                      controller.isStarting ||
                      controller.isStopping ||
                      controller.isRestarting ||
                      controller.hasProcess)
                  ? null
                  : controller.startBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: controller.isRestarting
                  ? 'Restarting...'
                  : 'Restart Backend',
              icon: Icons.refresh_rounded,
              color: const Color(0xFF7CC0FF),
              onPressed:
                  (!controller.isRunning ||
                      controller.isStarting ||
                      controller.isStopping ||
                      controller.isRestarting)
                  ? null
                  : controller.restartBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: controller.isStopping ? 'Stopping...' : 'Stop Backend',
              icon: Icons.stop_circle_outlined,
              color: const Color(0xFFFF6A8C),
              onPressed:
                  (controller.isStopping ||
                      controller.isRestarting ||
                      (!controller.isRunning && !controller.hasProcess))
                  ? null
                  : controller.stopBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Close Fortnite',
              icon: Icons.sports_esports,
              color: const Color(0xFFFFB86B),
              onPressed: controller.closeFortnite,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Open Logs',
              icon: Icons.receipt_long,
              color: const Color(0xFF7CC0FF),
              onPressed: () =>
                  Navigator.of(context).push(_buildRoute(const LogsScreen())),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Live Logs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    _LiveLogsRuntimeTimer(controller: controller),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.recentLogs.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(
                              text: controller.recentLogs.join('\n'),
                            ),
                          );
                          showAtlasSnackBar(
                            context,
                            const SnackBar(
                              content: Text('Live logs copied to clipboard'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  controller: _logsController,
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      controller.recentLogs.join('\n'),
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _onSurface(context, 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLogsRuntimeTimer extends StatefulWidget {
  const _LiveLogsRuntimeTimer({required this.controller});

  final BackendController controller;

  @override
  State<_LiveLogsRuntimeTimer> createState() => _LiveLogsRuntimeTimerState();
}

class _LiveLogsRuntimeTimerState extends State<_LiveLogsRuntimeTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Keep the update scoped to this small widget instead of rebuilding
    // the whole UI every second.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.controller.backendStartedAt;
    final show = startedAt != null;
    final elapsed = show ? DateTime.now().difference(startedAt) : Duration.zero;
    final text = show ? _formatElapsed(elapsed) : '';

    final label = Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _onSurface(context, 0.35),
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.2,
      ),
    );

    if (!show) return label; // Keeps a baseline for Row alignment.

    return Padding(padding: const EdgeInsets.only(left: 10), child: label);
  }

  String _formatElapsed(Duration elapsed) {
    var totalSeconds = elapsed.inSeconds;
    if (totalSeconds < 0) totalSeconds = 0;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = onPressed != null;
    final fgColor = isDark ? color : _darken(color, 0.38);
    return _HoverScale(
      enabled: isEnabled,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled
              ? color.withOpacity(isDark ? 0.28 : 0.35)
              : _onSurface(context, isDark ? 0.14 : 0.06),
          foregroundColor: isEnabled ? fgColor : _onSurface(context, 0.35),
          disabledBackgroundColor: _onSurface(context, isDark ? 0.14 : 0.06),
          disabledForegroundColor: _onSurface(context, 0.35),
          elevation: isDark ? 0 : 1.5,
          shadowColor: color.withOpacity(isDark ? 0.0 : 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isEnabled
                  ? fgColor.withOpacity(isDark ? 0.4 : 0.55)
                  : _onSurface(context, isDark ? 0.18 : 0.12),
            ),
          ),
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key, required this.data});

  final MenuItemData data;

  @override
  Widget build(BuildContext context) {
    final menuKey = 'feature-${data.title}';
    return Scaffold(
      body: Stack(
        children: [
          const AtlasBackground(showParticles: false),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _menuEntrance(
                  context,
                  menuKey: menuKey,
                  index: 0,
                  child: Row(
                    children: [
                      _HoverScale(
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: data.accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(data.icon, color: data.accent),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.subtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: _onSurface(context, 0.7)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 1,
                    child: GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Actions',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.separated(
                                itemCount: data.actions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final action = data.actions[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    tileColor: Colors.white10,
                                    leading: Icon(
                                      Icons.chevron_right_rounded,
                                      color: data.accent,
                                    ),
                                    title: Text(action.title),
                                    subtitle: Text(action.description),
                                    trailing: _HoverScale(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          showAtlasSnackBar(
                                            context,
                                            SnackBar(
                                              content: Text(
                                                '${action.title} (coming soon)',
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: data.accent
                                              .withOpacity(0.15),
                                          foregroundColor: data.accent,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Open'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _onSurface(context, 0.08)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

final Map<String, ImageProvider<Object>> _fileImageCache =
    <String, ImageProvider<Object>>{};

ImageProvider<Object>? _cachedFileImageProvider(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return _fileImageCache.putIfAbsent(path, () => FileImage(file));
}

ImageProvider<Object>? _atlasBackgroundImageProvider(String path) {
  return _cachedFileImageProvider(path);
}

class AtlasBackground extends StatelessWidget {
  const AtlasBackground({
    super.key,
    this.showParticles = true,
    this.animateParticles = true,
  });

  final bool showParticles;
  final bool animateParticles;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final defaultImagePath = joinPath([
      getBackendRoot(),
      'public',
      'images',
      'DefaultBackground.webp',
    ]);
    final defaultBackgroundProvider = _atlasBackgroundImageProvider(
      defaultImagePath,
    );
    return Stack(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([appBackgroundPath, appBackgroundBlur]),
          builder: (context, _) {
            final path = appBackgroundPath.value;
            final blurSigma = appBackgroundBlur.value
                .clamp(0.0, 30.0)
                .toDouble();
            ImageProvider<Object>? provider;
            final resolvedPath = _resolveBackgroundPath(path);
            if (resolvedPath != null) {
              provider = _atlasBackgroundImageProvider(resolvedPath);
            }
            provider ??= defaultBackgroundProvider;
            if (provider != null) {
              final background = RepaintBoundary(
                child: Image(
                  image: provider,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.low,
                ),
              );
              if (blurSigma <= 0.01) {
                return Positioned.fill(child: background);
              }
              return Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: background,
                ),
              );
            }
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A0E14), Color(0xFF0F1726)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            );
          },
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      Colors.black.withOpacity(0.65),
                      Colors.black.withOpacity(0.35),
                    ]
                  : [
                      Colors.white.withOpacity(0.55),
                      Colors.white.withOpacity(0.2),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        ValueListenableBuilder<double>(
          valueListenable: appBackgroundParticlesOpacity,
          builder: (context, opacity, _) {
            if (!showParticles) {
              return const SizedBox.shrink();
            }
            final clamped = opacity.clamp(0.0, 2.0).toDouble();
            if (clamped <= 0.0) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: animateParticles ? 1.0 : 0.0,
                  child: TickerMode(
                    enabled: routeIsCurrent && animateParticles,
                    child: _AtlasParticleField(opacity: clamped),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AtlasParticleField extends StatefulWidget {
  const _AtlasParticleField({required this.opacity});

  final double opacity;

  @override
  State<_AtlasParticleField> createState() => _AtlasParticleFieldState();
}

class _AtlasParticleFieldState extends State<_AtlasParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_AtlasParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    _particles = _AtlasParticle.generate(seed: 90210, count: 120);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = widget.opacity.clamp(0.0, 2.0).toDouble();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AtlasParticlePainter(
          controller: _controller,
          particles: _particles,
          color: isDark ? Colors.white : Colors.black,
          opacity: opacity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AtlasParticle {
  const _AtlasParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.alpha,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.glow,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double radius;
  final double alpha;
  final double twinkleSpeed;
  final double twinklePhase;
  final bool glow;

  static List<_AtlasParticle> generate({
    required int seed,
    required int count,
  }) {
    final rng = Random(seed);

    double nextDoubleRange(double min, double max) =>
        min + (max - min) * rng.nextDouble();

    final particles = <_AtlasParticle>[];
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble();
      final y = rng.nextDouble();

      final sizeRoll = rng.nextDouble();
      final radius = sizeRoll < 0.12
          ? nextDoubleRange(1.8, 2.8)
          : nextDoubleRange(0.8, 1.8);
      final baseAlpha = sizeRoll < 0.12
          ? nextDoubleRange(0.08, 0.16)
          : nextDoubleRange(0.04, 0.12);

      final speed = nextDoubleRange(0.002, 0.012) * (radius / 2.0);
      final angle = nextDoubleRange(0, pi * 2);
      final vx = cos(angle) * speed;
      final vy = sin(angle) * speed;

      final twinkleSpeed = nextDoubleRange(0.6, 1.6);
      final twinklePhase = nextDoubleRange(0, pi * 2);

      particles.add(
        _AtlasParticle(
          x: x,
          y: y,
          vx: vx,
          vy: vy,
          radius: radius,
          alpha: baseAlpha,
          twinkleSpeed: twinkleSpeed,
          twinklePhase: twinklePhase,
          glow: sizeRoll < 0.08,
        ),
      );
    }
    return particles;
  }
}

class _AtlasParticlePainter extends CustomPainter {
  _AtlasParticlePainter({
    required this.controller,
    required this.particles,
    required this.color,
    required this.opacity,
  }) : super(repaint: controller);

  final AnimationController controller;
  final List<_AtlasParticle> particles;
  final Color color;
  final double opacity;

  final Paint _paint = Paint()..isAntiAlias = true;
  final Paint _glowPaint = Paint()
    ..isAntiAlias = true
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (controller.lastElapsedDuration?.inMilliseconds ?? 0) / 1000.0;

    for (final p in particles) {
      final px = ((p.x + p.vx * t) % 1.0) * size.width;
      final py = ((p.y + p.vy * t) % 1.0) * size.height;
      final twinkle = 0.65 + 0.35 * sin(p.twinklePhase + t * p.twinkleSpeed);
      final a = (p.alpha * twinkle * opacity).clamp(0.0, 1.0);

      if (p.glow) {
        _glowPaint.color = color.withOpacity(a * 0.6);
        canvas.drawCircle(Offset(px, py), p.radius + 1.4, _glowPaint);
      }

      _paint.color = color.withOpacity(a);
      canvas.drawCircle(Offset(px, py), p.radius, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtlasParticlePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.particles != particles;
  }
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({
    required this.child,
    this.enabled = true,
    this.scale = 1.05,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverRegion extends StatefulWidget {
  const _HoverRegion({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<_HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

class _ImageDropShadow extends StatelessWidget {
  const _ImageDropShadow({
    required this.child,
    this.opacity = 0.75,
    this.blurSigma = 2.5,
    this.offset = const Offset(0, 2),
  });

  final Widget child;
  final double opacity;
  final double blurSigma;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: offset,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(opacity),
                BlendMode.srcIn,
              ),
              child: child,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _HoverShadow extends StatefulWidget {
  const _HoverShadow({
    required this.child,
    this.opacity = 0.75,
    this.blurSigma = 2.5,
    this.baseOffset = const Offset(0, 2),
    this.hoverOffset = const Offset(4, 2),
    this.hovered,
  });

  final Widget child;
  final double opacity;
  final double blurSigma;
  final Offset baseOffset;
  final Offset hoverOffset;
  final bool? hovered;

  @override
  State<_HoverShadow> createState() => _HoverShadowState();
}

class _HoverShadowState extends State<_HoverShadow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveHovered = widget.hovered ?? _hovered;
    final content = TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(
        begin: widget.baseOffset,
        end: effectiveHovered ? widget.hoverOffset : widget.baseOffset,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) {
        return _ImageDropShadow(
          opacity: widget.opacity,
          blurSigma: widget.blurSigma,
          offset: offset,
          child: child!,
        );
      },
      child: widget.child,
    );
    if (widget.hovered != null) {
      return content;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );
  }
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

Color _onSurface(BuildContext context, double opacity) {
  return Theme.of(context).colorScheme.onSurface.withOpacity(opacity);
}

bool _isDarkTheme(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark;
}

Color _dialogSurfaceColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  if (dark) {
    return const Color(0xFF081225).withOpacity(0.96);
  }
  return const Color(0xFFF6FAFF).withOpacity(0.96);
}

Color _dialogShadowColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  return Colors.black.withOpacity(dark ? 0.40 : 0.18);
}

Color _dialogBarrierColor(BuildContext context, double transitionValue) {
  final dark = _isDarkTheme(context);
  final base = dark ? Colors.black : Colors.white;
  final alpha = (dark ? 0.34 : 0.22) * transitionValue;
  return base.withOpacity(alpha);
}

Color _adaptiveScrimColor(
  BuildContext context, {
  required double darkAlpha,
  required double lightAlpha,
}) {
  final dark = _isDarkTheme(context);
  final base = dark ? Colors.black : Colors.white;
  return base.withOpacity(dark ? darkAlpha : lightAlpha);
}

Future<void> _applyAcrylicForBackground(String path) async {
  final color = await _computeAcrylicTint(path);
  await Window.setEffect(effect: WindowEffect.acrylic, color: color);
}

Future<Color> _computeAcrylicTint(String path) async {
  final resolved = _resolveBackgroundPath(path);
  final fallbackPath = joinPath([
    getBackendRoot(),
    'public',
    'images',
    'DefaultBackground.webp',
  ]);
  final candidatePath = resolved ?? fallbackPath;
  try {
    final file = File(candidatePath);
    if (!await file.exists()) return _fallbackAcrylicColor;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _fallbackAcrylicColor;
    final width = decoded.width;
    final height = decoded.height;
    if (width == 0 || height == 0) return _fallbackAcrylicColor;
    final stepX = max(1, (width / 60).floor());
    final stepY = max(1, (height / 60).floor());
    var r = 0;
    var g = 0;
    var b = 0;
    var count = 0;
    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final a = pixel.a;
        if (a < 20) continue;
        r += pixel.r.toInt();
        g += pixel.g.toInt();
        b += pixel.b.toInt();
        count++;
      }
    }
    if (count == 0) return _fallbackAcrylicColor;
    final avg = Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    final base = const Color(0xFF0A0E14);
    final mixed = _mixColors(base, avg, 0.55);
    return mixed.withAlpha(_fallbackAcrylicColor.alpha);
  } catch (_) {
    return _fallbackAcrylicColor;
  }
}

Color _mixColors(Color a, Color b, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final r = (a.red + (b.red - a.red) * clamped).round();
  final g = (a.green + (b.green - a.green) * clamped).round();
  final bVal = (a.blue + (b.blue - a.blue) * clamped).round();
  return Color.fromARGB(255, r, g, bVal);
}

Color _menuShadowColor(BuildContext context, Color accent) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return accent.withOpacity(isDark ? 0.25 : 0.18);
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).toColor();
}

class _AboutCreatorProfile {
  const _AboutCreatorProfile({
    required this.name,
    required this.handle,
    required this.role,
    required this.githubUrl,
    required this.avatarUrl,
    required this.description,
  });

  final String name;
  final String handle;
  final String role;
  final String githubUrl;
  final String avatarUrl;
  final String description;
}

class _CreditProjectLink {
  const _CreditProjectLink({required this.label, required this.url});

  final String label;
  final String url;
}

class _CreditProfileData {
  const _CreditProfileData({
    required this.name,
    required this.handle,
    required this.role,
    required this.githubUrl,
    required this.avatarUrl,
    required this.description,
    required this.projects,
  });

  final String name;
  final String handle;
  final String role;
  final String githubUrl;
  final String avatarUrl;
  final String description;
  final List<_CreditProjectLink> projects;
}

Widget _aboutCreatorAvatar(BuildContext context, {required String avatarUrl}) {
  final dark = _isDarkTheme(context);
  final secondary = Theme.of(context).colorScheme.secondary;

  return Container(
    width: 86,
    height: 86,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: SweepGradient(
        colors: [
          secondary.withOpacity(0.92),
          Colors.white.withOpacity(dark ? 0.55 : 0.90),
          secondary.withOpacity(0.50),
          secondary.withOpacity(0.92),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: secondary.withOpacity(dark ? 0.24 : 0.14),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (dark ? const Color(0xFF07111F) : Colors.white).withOpacity(
          dark ? 0.92 : 0.96,
        ),
      ),
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _aboutCreatorAvatarFallback(context),
        ),
      ),
    ),
  );
}

Widget _aboutCreatorAvatarFallback(BuildContext context) {
  final fallbackPath = joinPath([
    getBackendRoot(),
    'public',
    'images',
    'default_pfp.png',
  ]);
  final fallbackFile = File(fallbackPath);
  if (fallbackFile.existsSync()) {
    return Image.file(
      fallbackFile,
      width: 80,
      height: 80,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _aboutCreatorAvatarFallbackPlaceholder(context),
    );
  }

  return _aboutCreatorAvatarFallbackPlaceholder(context);
}

Widget _aboutCreatorAvatarFallbackPlaceholder(BuildContext context) {
  return Container(
    color: _adaptiveScrimColor(
      context,
      darkAlpha: 0.18,
      lightAlpha: 0.08,
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.person_rounded,
      color: _onSurface(context, 0.72),
      size: 32,
    ),
  );
}

Widget _aboutCreatorCard(
  BuildContext dialogContext,
  _AboutCreatorProfile creator,
) {
  final dark = _isDarkTheme(dialogContext);
  final secondary = Theme.of(dialogContext).colorScheme.secondary;
  final cardTop = dark
      ? const Color(0xFF0D1628).withOpacity(0.94)
      : Colors.white.withOpacity(0.94);
  final cardBottom = dark
      ? secondary.withOpacity(0.10)
      : secondary.withOpacity(0.08);

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cardTop, cardBottom],
      ),
      border: Border.all(color: _onSurface(dialogContext, 0.10)),
      boxShadow: [
        BoxShadow(
          color: _dialogShadowColor(
            dialogContext,
          ).withOpacity(dark ? 0.34 : 0.14),
          blurRadius: 24,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _aboutCreatorAvatar(dialogContext, avatarUrl: creator.avatarUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: secondary.withOpacity(dark ? 0.18 : 0.12),
                      border: Border.all(
                        color: secondary.withOpacity(dark ? 0.36 : 0.24),
                      ),
                    ),
                    child: Text(
                      creator.role,
                      style: TextStyle(
                        color: _onSurface(dialogContext, 0.92),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    creator.name,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _onSurface(dialogContext, 0.96),
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    creator.handle,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _onSurface(dialogContext, 0.66),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          creator.description,
          style: TextStyle(
            color: _onSurface(dialogContext, 0.82),
            height: 1.5,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(height: 18),
        _HoverScale(
          child: FilledButton.icon(
            onPressed: () => unawaited(_openUrl(creator.githubUrl)),
            style: FilledButton.styleFrom(
              backgroundColor: dark
                  ? const Color(0xFF0A0F18)
                  : const Color(0xFFEAF3FF),
              foregroundColor: _onSurface(dialogContext, 0.96),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: const StadiumBorder(),
            ),
            icon: const FaIcon(FontAwesomeIcons.github, size: 16),
            label: Text('View ${creator.handle}'),
          ),
        ),
      ],
    ),
  );
}

Widget _creditProfileCard(BuildContext context, _CreditProfileData credit) {
  final dark = _isDarkTheme(context);
  final secondary = Theme.of(context).colorScheme.secondary;
  final cardTop = dark
      ? const Color(0xFF0E1728).withOpacity(0.92)
      : Colors.white.withOpacity(0.92);
  final cardBottom = dark
      ? secondary.withOpacity(0.12)
      : secondary.withOpacity(0.10);
  final accent = dark ? secondary.withOpacity(0.88) : const Color(0xFF1565C0);

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cardTop, cardBottom],
      ),
      border: Border.all(color: _onSurface(context, 0.10)),
      boxShadow: [
        BoxShadow(
          color: _dialogShadowColor(context).withOpacity(dark ? 0.18 : 0.10),
          blurRadius: 26,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _aboutCreatorAvatar(context, avatarUrl: credit.avatarUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: accent.withOpacity(dark ? 0.18 : 0.12),
                      border: Border.all(
                        color: accent.withOpacity(dark ? 0.36 : 0.24),
                      ),
                    ),
                    child: Text(
                      credit.role,
                      style: TextStyle(
                        color: _onSurface(context, 0.92),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    credit.name,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _onSurface(context, 0.96),
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    credit.handle,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _onSurface(context, 0.66),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          credit.description,
          style: TextStyle(
            color: _onSurface(context, 0.82),
            height: 1.5,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Projects',
          style: TextStyle(
            color: _onSurface(context, 0.92),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final project in credit.projects)
              ActionChip(
                onPressed: () => unawaited(_openUrl(project.url)),
                backgroundColor: _onSurface(context, 0.06),
                side: BorderSide(color: _onSurface(context, 0.12)),
                avatar: Icon(
                  Icons.open_in_new_rounded,
                  size: 15,
                  color: _onSurface(context, 0.82),
                ),
                label: Text(project.label),
                labelStyle: TextStyle(
                  color: _onSurface(context, 0.90),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => unawaited(_openUrl(credit.githubUrl)),
          style: FilledButton.styleFrom(
            backgroundColor: dark
                ? const Color(0xFF0A0F18)
                : const Color(0xFF111827),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: const StadiumBorder(),
          ),
          icon: const FaIcon(FontAwesomeIcons.github, size: 18),
          label: Text('View ${credit.handle}'),
        ),
      ],
    ),
  );
}

Future<void> _showAboutDialog(
  BuildContext context, {
  required String versionLabel,
}) async {
  const supportUrl = 'https://discord.gg/GqgakxU6bm';
  const githubUrl = 'https://github.com/cipherfps/ATLAS-Backend';
  final formattedVersion = _formatVersion(versionLabel);
  const creators = <_AboutCreatorProfile>[
    _AboutCreatorProfile(
      name: 'cipher',
      handle: '@cipherfps',
      role: 'Owner',
      githubUrl: 'https://github.com/cipherfps',
      avatarUrl: 'https://github.com/cipherfps.png?size=240',
      description:
          'Creator of ATLAS and constantly updates and develops the launcher/backend for the best possible experience. (Thank you for trying ATLAS! <3)',
    ),
    _AboutCreatorProfile(
      name: 'ralz',
      handle: '@Ralzify',
      role: 'Co-Owner',
      githubUrl: 'https://github.com/Ralzify',
      avatarUrl: 'https://github.com/Ralzify.png?size=240',
      description:
          'Co-creator of ATLAS and helps maintain the gameserver Magnesium, as well as contributing to launcher/backend features and improvements.',
    ),
  ];

  await _showBlurDialog<void>(
    context: context,
    builder: (dialogContext) {
      final secondary = Theme.of(dialogContext).colorScheme.secondary;
      final size = MediaQuery.sizeOf(dialogContext);
      final dialogWidth = max(320.0, min(920.0, size.width - 24));
      final dialogMaxHeight = max(420.0, min(760.0, size.height - 24));

      Widget aboutActionButton({
        required Widget icon,
        required String label,
        required VoidCallback onPressed,
      }) {
        return _HoverScale(
          child: OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: _onSurface(dialogContext, 0.92),
              backgroundColor: _onSurface(dialogContext, 0.03),
              side: BorderSide(color: _onSurface(dialogContext, 0.14)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: icon,
            label: Text(label),
          ),
        );
      }

      return Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: dialogMaxHeight,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _dialogSurfaceColor(dialogContext),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _onSurface(dialogContext, 0.1)),
              boxShadow: [
                BoxShadow(
                  color: _dialogShadowColor(dialogContext),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _adaptiveScrimColor(
                            dialogContext,
                            darkAlpha: 0.24,
                            lightAlpha: 0.14,
                          ),
                          border: Border.all(
                            color: _onSurface(dialogContext, 0.12),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            'assets/images/atlas_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'About',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: _onSurface(dialogContext, 0.96),
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Created by the ATLAS team',
                              style: TextStyle(
                                color: _onSurface(dialogContext, 0.72),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _VersionTag(label: formattedVersion, color: secondary),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'ATLAS Backend is created and maintained by cipher and ralz. The backend experience is shaped by the team below.',
                    style: TextStyle(
                      color: _onSurface(dialogContext, 0.82),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      aboutActionButton(
                        onPressed: () => unawaited(_openUrl(githubUrl)),
                        icon: const FaIcon(FontAwesomeIcons.github, size: 16),
                        label: 'ATLAS Repo',
                      ),
                      aboutActionButton(
                        onPressed: () => unawaited(_openUrl(supportUrl)),
                        icon: const Icon(Icons.discord_rounded, size: 18),
                        label: 'Support',
                      ),
                      aboutActionButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).push(
                            _buildRoute(
                              const SettingsScreen(initialTabIndex: 3),
                            ),
                          );
                        },
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: 'Extra Credits',
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = creators
                          .map(
                            (creator) =>
                                _aboutCreatorCard(dialogContext, creator),
                          )
                          .toList(growable: false);
                      if (constraints.maxWidth < 780) {
                        return Column(
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(height: 16),
                              cards[i],
                            ],
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 16),
                          Expanded(child: cards[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Spacer(),
                      _HoverScale(
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _showCustomCosmeticPresetsInfoDialog(BuildContext context) async {
  const discordUrl = 'https://discord.gg/GqgakxU6bm';
  await _showBlurDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.palette_rounded,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          const Text('Custom Cosmetic Presets'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            final onSurface = colorScheme.onSurface;
            final onSurfaceMuted = onSurface.withOpacity(0.75);
            final accent = colorScheme.secondary;
            final cardFill = colorScheme.surfaceContainerHighest.withOpacity(
              0.6,
            );
            final cardBorder = onSurface.withOpacity(0.18);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withOpacity(0.28)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Custom Cosmetic Presets require additional pak files. '
                          'You can download the required paks from the Discord server.',
                          style: TextStyle(color: onSurfaceMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.forum_rounded,
                        size: 18,
                        color: onSurfaceMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Discord server',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: onSurface.withOpacity(0.92),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              discordUrl,
                              style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 12.8,
                                fontWeight: FontWeight.w500,
                                color: onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _HoverScale(
                        child: IconButton(
                          tooltip: 'Open Discord',
                          onPressed: () => _openUrl(discordUrl),
                          icon: const Icon(Icons.open_in_new_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: discordUrl));
              if (context.mounted) {
                showAtlasSnackBar(
                  context,
                  const SnackBar(content: Text('Discord link copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy link'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton.icon(
            onPressed: () => _openUrl(discordUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open Discord'),
          ),
        ),
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ),
      ],
    ),
  );
}

Future<bool> _openUrl(String url) async {
  try {
    await Process.start('cmd', ['/c', 'start', '', url]);
    return true;
  } catch (_) {
    return false;
  }
}

class _ModificationsScreenSnapshot {
  const _ModificationsScreenSnapshot({
    required this.straightBloom,
    required this.curveTablesEnabled,
    required this.curves,
    required this.curveStates,
    required this.dataTablesEnabled,
    required this.backendInfiniteRenderEnabled,
    required this.swapCooldownEnabled,
    required this.victoryTextReplacementSettings,
    required this.weapons,
  });

  final bool straightBloom;
  final bool curveTablesEnabled;
  final List<CurveEntry> curves;
  final Map<String, _CurveEntryResolvedState> curveStates;
  final bool dataTablesEnabled;
  final bool backendInfiniteRenderEnabled;
  final bool swapCooldownEnabled;
  final VictoryTextReplacementSettings victoryTextReplacementSettings;
  final List<DataTableWeapon> weapons;
}

class _ModificationsScreenCache {
  static _ModificationsScreenSnapshot? _snapshot;
  static Future<_ModificationsScreenSnapshot>? _pending;
  static final Set<void Function(double)> _progressListeners =
      <void Function(double)>{};
  static double _progress = 0;

  static _ModificationsScreenSnapshot? get snapshot => _snapshot;

  static void store(_ModificationsScreenSnapshot snapshot) {
    _snapshot = snapshot;
  }

  static Future<_ModificationsScreenSnapshot> warm({
    bool forceRefresh = false,
    void Function(double progress)? onProgress,
  }) {
    if (onProgress != null) {
      _progressListeners.add(onProgress);
      onProgress(_progress);
    }

    void cleanup() {
      if (onProgress != null) {
        _progressListeners.remove(onProgress);
      }
    }

    final pending = _pending;
    if (pending != null) {
      return pending.whenComplete(cleanup);
    }

    if (!forceRefresh) {
      final cached = _snapshot;
      if (cached != null) {
        _emitProgress(1.0);
        return Future<_ModificationsScreenSnapshot>.value(
          cached,
        ).whenComplete(cleanup);
      }
    }

    _emitProgress(0);
    final future = _loadSnapshot();
    _pending = future;
    return future
        .then((snapshot) {
          _snapshot = snapshot;
          _emitProgress(1.0);
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_pending, future)) {
            _pending = null;
          }
          cleanup();
        });
  }

  static void _emitProgress(double progress) {
    _progress = progress.clamp(0.0, 1.0);
    for (final listener in _progressListeners.toList()) {
      listener(_progress);
    }
  }

  static Future<_ModificationsScreenSnapshot> _loadSnapshot() async {
    var completedSteps = 0;
    const totalSteps = 9;
    void markStepDone() {
      completedSteps += 1;
      _emitProgress(completedSteps / totalSteps);
    }

    final straightBloomFuture = StraightBloomService.isEnabled();
    final curveTablesEnabledFuture = CurveTableService.areGlobalEnabled();
    final curvesFuture = CurveTableService.loadCurves();
    final weaponsFuture = DataTableService.loadWeapons();
    final dataTablesEnabledFuture = DataTableService.getUIEnabledState();
    final backendInfiniteRenderEnabledFuture =
        DataTableService.isBackendInfiniteRenderEnabled();
    final swapCooldownEnabledFuture = DataTableService.isSwapCooldownEnabled();
    final victoryTextReplacementSettingsFuture =
        DataTableService.getVictoryTextReplacementSettings();

    final curves = await curvesFuture;
    markStepDone();
    final curveStatesFuture = CurveTableService._loadCurveStates(curves);
    final straightBloom = await straightBloomFuture;
    markStepDone();
    final curveTablesEnabled = await curveTablesEnabledFuture;
    markStepDone();
    final curveStates = await curveStatesFuture;
    markStepDone();
    final dataTablesEnabled = await dataTablesEnabledFuture;
    markStepDone();
    final backendInfiniteRenderEnabled =
        await backendInfiniteRenderEnabledFuture;
    markStepDone();
    final swapCooldownEnabled = await swapCooldownEnabledFuture;
    markStepDone();
    final victoryTextReplacementSettings =
        await victoryTextReplacementSettingsFuture;
    markStepDone();
    final weapons = await weaponsFuture;
    markStepDone();

    return _ModificationsScreenSnapshot(
      straightBloom: straightBloom,
      curveTablesEnabled: curveTablesEnabled,
      curves: curves,
      curveStates: curveStates,
      dataTablesEnabled: dataTablesEnabled,
      backendInfiniteRenderEnabled: backendInfiniteRenderEnabled,
      swapCooldownEnabled: swapCooldownEnabled,
      victoryTextReplacementSettings: victoryTextReplacementSettings,
      weapons: weapons,
    );
  }
}

class _ArenaScreenSnapshot {
  const _ArenaScreenSnapshot({
    required this.saveArenaPoints,
    required this.leaderboard,
  });

  final bool saveArenaPoints;
  final List<ArenaEntry> leaderboard;
}

class _ArenaScreenCache {
  static _ArenaScreenSnapshot? _snapshot;
  static Future<_ArenaScreenSnapshot>? _pending;

  static _ArenaScreenSnapshot? get snapshot => _snapshot;

  static Future<_ArenaScreenSnapshot> warm({bool forceRefresh = false}) {
    final pending = _pending;
    if (pending != null) return pending;

    if (!forceRefresh) {
      final cached = _snapshot;
      if (cached != null) {
        return Future<_ArenaScreenSnapshot>.value(cached);
      }
    }

    final future = _loadSnapshot();
    _pending = future;
    return future
        .then((snapshot) {
          _snapshot = snapshot;
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_pending, future)) {
            _pending = null;
          }
        });
  }

  static Future<_ArenaScreenSnapshot> _loadSnapshot() async {
    final configFuture = ConfigService.load();
    final leaderboardFuture = ArenaService.loadLeaderboard();
    final config = await configFuture;
    final leaderboard = await leaderboardFuture;
    return _ArenaScreenSnapshot(
      saveArenaPoints: config.saveArenaPoints,
      leaderboard: leaderboard,
    );
  }
}

class _ProfilesScreenSnapshot {
  const _ProfilesScreenSnapshot({
    required this.profiles,
    required this.presets,
    required this.hasAnyUsers,
    required this.uiState,
  });

  final List<ProfileSummary> profiles;
  final List<ProfilePreset> presets;
  final bool hasAnyUsers;
  final ProfilesUiState uiState;
}

class _ProfilesScreenCache {
  static _ProfilesScreenSnapshot? _snapshot;
  static Future<_ProfilesScreenSnapshot>? _pending;

  static _ProfilesScreenSnapshot? get snapshot => _snapshot;

  static Future<_ProfilesScreenSnapshot> warm({bool forceRefresh = false}) {
    final pending = _pending;
    if (pending != null) return pending;

    if (!forceRefresh) {
      final cached = _snapshot;
      if (cached != null) {
        return Future<_ProfilesScreenSnapshot>.value(cached);
      }
    }

    final future = _loadSnapshot();
    _pending = future;
    return future
        .then((snapshot) {
          _snapshot = snapshot;
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_pending, future)) {
            _pending = null;
          }
        });
  }

  static Future<_ProfilesScreenSnapshot> _loadSnapshot() async {
    final profilesFuture = ProfileService.listProfiles();
    final presetsFuture = ProfileService.listPresets();
    final hasAnyUsersFuture = ProfileService.hasAnyUsers();
    final uiStateFuture = ProfilesUiStateService.load();
    final profiles = await profilesFuture;
    final presets = await presetsFuture;
    final hasAnyUsers = await hasAnyUsersFuture;
    final uiState = await uiStateFuture;
    return _ProfilesScreenSnapshot(
      profiles: profiles,
      presets: presets,
      hasAnyUsers: hasAnyUsers,
      uiState: uiState,
    );
  }
}

class _UserValuesWarmupSnapshot {
  const _UserValuesWarmupSnapshot({
    required this.accountId,
    required this.values,
  });

  final String accountId;
  final UserValues values;
}

class _UserValuesWarmupCache {
  static _UserValuesWarmupSnapshot? _snapshot;
  static Future<_UserValuesWarmupSnapshot?>? _pending;

  static _UserValuesWarmupSnapshot? get snapshot => _snapshot;

  static void store(String accountId, UserValues values) {
    _snapshot = _UserValuesWarmupSnapshot(accountId: accountId, values: values);
  }

  static Future<_UserValuesWarmupSnapshot?> warm({String? accountId}) {
    final pending = _pending;
    if (pending != null) return pending;

    final cached = _snapshot;
    if (accountId == null && cached != null) {
      return Future<_UserValuesWarmupSnapshot?>.value(cached);
    }
    if (accountId != null && cached != null && cached.accountId == accountId) {
      return Future<_UserValuesWarmupSnapshot?>.value(cached);
    }

    final future = _loadSnapshot(accountId: accountId);
    _pending = future;
    return future
        .then((snapshot) {
          _snapshot = snapshot;
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_pending, future)) {
            _pending = null;
          }
        });
  }

  static Future<_UserValuesWarmupSnapshot?> _loadSnapshot({
    String? accountId,
  }) async {
    var resolvedAccountId = accountId;
    if (resolvedAccountId == null) {
      final profilesSnapshot = await _ProfilesScreenCache.warm();
      if (profilesSnapshot.profiles.isEmpty) return null;
      final profileIds = {
        for (final profile in profilesSnapshot.profiles) profile.accountId,
      };
      final savedSelectedProfile = profilesSnapshot.uiState.lastSelectedProfile;
      resolvedAccountId =
          savedSelectedProfile != null &&
              profileIds.contains(savedSelectedProfile)
          ? savedSelectedProfile
          : profilesSnapshot.profiles.first.accountId;
    }

    final values = await UserValuesService.loadUserValues(resolvedAccountId);
    return _UserValuesWarmupSnapshot(
      accountId: resolvedAccountId,
      values: values,
    );
  }
}

PageRouteBuilder<void> _buildRoute(Widget page) {
  return PageRouteBuilder<void>(
    allowSnapshotting: true,
    transitionDuration: const Duration(milliseconds: 140),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, __, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return child;
      }
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curve, child: child);
    },
  );
}

void _scheduleDeferredScreenLoad(
  State state,
  Future<void> Function() load, {
  Duration delay = const Duration(milliseconds: 150),
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    unawaited(
      Future<void>(() async {
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        if (!state.mounted) return;
        await load();
      }),
    );
  });
}

Widget _menuSwap(
  BuildContext context, {
  required Object switchKey,
  required Widget child,
  Offset slideBegin = const Offset(0, 0.03),
  Duration duration = const Duration(milliseconds: 240),
  bool expand = false,
  AlignmentGeometry layoutAlignment = Alignment.center,
}) {
  final keyed = KeyedSubtree(key: ValueKey(switchKey), child: child);
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return keyed;

  return AnimatedSwitcher(
    duration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (currentChild, previousChildren) {
      return Stack(
        fit: expand ? StackFit.expand : StackFit.loose,
        alignment: layoutAlignment,
        children: [
          ...previousChildren,
          ...?(currentChild == null ? null : [currentChild]),
        ],
      );
    },
    transitionBuilder: (child, animation) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: slideBegin,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    child: keyed,
  );
}

Widget _menuEntrance(
  BuildContext context, {
  required Object menuKey,
  required int index,
  required Widget child,
}) {
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;

  final delay = (0.08 * index).clamp(0.0, 0.42);
  final curve = Interval(delay, 1.0, curve: Curves.easeOutCubic);
  return TweenAnimationBuilder<double>(
    key: ValueKey('menu-$menuKey-$index'),
    tween: Tween<double>(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: 520),
    curve: curve,
    child: RepaintBoundary(child: child),
    builder: (context, t, animatedChild) {
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: animatedChild,
        ),
      );
    },
  );
}

Widget _menuToggleReveal(
  BuildContext context, {
  required Object revealKey,
  required bool visible,
  required Widget child,
  Widget hiddenChild = const SizedBox.shrink(),
  int index = 0,
}) {
  final resolvedChild = visible ? child : hiddenChild;
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
    return resolvedChild;
  }

  return _menuEntrance(
    context,
    menuKey: '$revealKey-${visible ? 'visible' : 'hidden'}',
    index: index,
    child: resolvedChild,
  );
}

class _ScreenLoadGate extends StatefulWidget {
  const _ScreenLoadGate({
    required this.loading,
    required this.transitionKey,
    required this.child,
    this.progress,
  });

  final bool loading;
  final Object transitionKey;
  final Widget child;
  final double? progress;

  @override
  State<_ScreenLoadGate> createState() => _ScreenLoadGateState();
}

class _ArcSpinner extends StatelessWidget {
  const _ArcSpinner({
    required this.progress,
    required this.rotationTurns,
    required this.color,
  });

  final double progress;
  final double rotationTurns;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: CustomPaint(
        painter: _ArcSpinnerPainter(
          progress: progress,
          rotationTurns: rotationTurns,
          color: color,
        ),
      ),
    );
  }
}

class _ArcSpinnerPainter extends CustomPainter {
  const _ArcSpinnerPainter({
    required this.progress,
    required this.rotationTurns,
    required this.color,
  });

  final double progress;
  final double rotationTurns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.2;
    final radius = (min(size.width, size.height) - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -pi / 2 + (rotationTurns * pi * 2);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final arcPulse = Curves.easeInOut.transform(
      ((sin(rotationTurns * pi * 2 - (pi / 2)) + 1) / 2).clamp(0.0, 1.0),
    );
    final progressBoost = lerpDouble(0.9, 1.0, clampedProgress)!;
    final leadingColor = Color.lerp(color, const Color(0xFF65DAFF), 0.35)!;
    final midColor = Color.lerp(color, const Color(0xFF8EEBFF), 0.58)!;
    final highlight = Color.lerp(color, Colors.white, 0.55 * progressBoost)!;
    final tailColor = Color.lerp(color, const Color(0xFF1E8FFF), 0.2)!;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.8
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    final sweepAngle = clampedProgress >= 0.995
        ? pi * 1.02
        : lerpDouble(pi * 0.58, pi * 1.18, arcPulse)!;
    final glowShader = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      transform: GradientRotation(startAngle),
      colors: [
        leadingColor.withOpacity(0.0),
        midColor.withOpacity(0.18),
        highlight.withOpacity(0.42),
        tailColor.withOpacity(0.16),
        tailColor.withOpacity(0.0),
      ],
      stops: const [0.0, 0.26, 0.7, 0.9, 1.0],
    ).createShader(rect);
    glowPaint.shader = glowShader;
    gradientPaint
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        transform: GradientRotation(startAngle),
        colors: [
          leadingColor.withOpacity(0.0),
          leadingColor.withOpacity(0.16),
          midColor.withOpacity(0.88),
          highlight.withOpacity(0.98),
          tailColor.withOpacity(0.86),
          tailColor.withOpacity(0.0),
        ],
        stops: const [0.0, 0.08, 0.34, 0.72, 0.92, 1.0],
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
    canvas.drawArc(rect, startAngle, sweepAngle, false, gradientPaint);
  }

  @override
  bool shouldRepaint(covariant _ArcSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.rotationTurns != rotationTurns ||
        oldDelegate.color != color;
  }
}

class _ScreenLoadGateState extends State<_ScreenLoadGate>
    with SingleTickerProviderStateMixin {
  DateTime? _loadingStartedAt;
  bool _primeContent = false;
  bool _showContent = false;
  int _revealEpoch = 0;
  int _scheduleToken = 0;
  late final AnimationController _spinnerRotationController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 560),
      );

  @override
  void initState() {
    super.initState();
    _loadingStartedAt = widget.loading ? DateTime.now() : null;
    _showContent = !widget.loading;
    if (widget.loading) {
      _spinnerRotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ScreenLoadGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading) {
      _scheduleToken += 1;
      _loadingStartedAt = DateTime.now();
      if (!_spinnerRotationController.isAnimating) {
        _spinnerRotationController.repeat();
      }
      if (_primeContent || _showContent) {
        setState(() {
          _primeContent = false;
          _showContent = false;
        });
      }
      return;
    }

    if (!widget.loading && oldWidget.loading) {
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    final token = ++_scheduleToken;
    final loadingStartedAt = _loadingStartedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(loadingStartedAt);
    final remaining = const Duration(milliseconds: 320) - elapsed;

    unawaited(
      Future<void>(() async {
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
        if (!mounted || widget.loading || token != _scheduleToken) return;
        await Future<void>.delayed(const Duration(milliseconds: 110));
        if (!mounted || widget.loading || token != _scheduleToken) return;
        if (!_primeContent) {
          setState(() => _primeContent = true);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.loading || token != _scheduleToken) return;
          if (_spinnerRotationController.isAnimating) {
            _spinnerRotationController.stop();
          }
          setState(() {
            _loadingStartedAt = null;
            _primeContent = false;
            _showContent = true;
            _revealEpoch += 1;
          });
        });
      }),
    );
  }

  Widget _loadingSpinner(BuildContext context) {
    final spinnerProgress = widget.loading ? widget.progress : 1.0;
    final accent = Theme.of(context).colorScheme.secondary;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: (spinnerProgress ?? 0.0).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) {
          final displayedProgress = animatedProgress <= 0.02
              ? 0.18
              : animatedProgress;
          return AnimatedBuilder(
            animation: _spinnerRotationController,
            builder: (context, _) {
              return _ArcSpinner(
                progress: displayedProgress.clamp(0.0, 1.0),
                rotationTurns: _spinnerRotationController.value,
                color: accent,
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _spinnerRotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleChild = _showContent ? widget.child : _loadingSpinner(context);
    final switched = _menuSwap(
      context,
      switchKey: _showContent
          ? 'load-content-${widget.transitionKey}-$_revealEpoch'
          : 'load-spinner-${widget.transitionKey}',
      expand: true,
      layoutAlignment: Alignment.topLeft,
      child: visibleChild,
    );

    if (!_primeContent || _showContent) {
      return switched;
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: Opacity(opacity: 0, child: widget.child)),
        ),
        switched,
      ],
    );
  }
}

class MenuItemData {
  const MenuItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.actions,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<MenuAction> actions;
  final bool enabled;
}

class MenuAction {
  const MenuAction({required this.title, required this.description});

  final String title;
  final String description;
}

Widget _pageForMenu(String title) {
  switch (title) {
    case 'Modifications':
      return const ModificationsScreen();
    case 'CurveTables':
      return const CurveTablesScreen();
    case 'Arena':
      return const ArenaScreen();
    case 'Game Configuration':
      return const GameConfigurationScreen();
    case 'Users':
      return const ProfilesScreen();
    case 'Edit User Values':
      return const UserValuesScreen();
    case 'Logs':
      return const LogsScreen();
    default:
      return FeatureScreen(
        data: MenuItemData(
          title: title,
          subtitle: 'Coming soon',
          icon: Icons.dashboard_customize,
          accent: const Color(0xFF6BE7FF),
          actions: const [
            MenuAction(
              title: 'Coming soon',
              description: 'This menu is being built.',
            ),
          ],
        ),
      );
  }
}

class ModificationsScreen extends StatefulWidget {
  const ModificationsScreen({super.key});

  @override
  State<ModificationsScreen> createState() => _ModificationsScreenState();
}

enum _ModificationsTab { curveTables, dataTables }

class _ModificationsScreenState extends State<ModificationsScreen> {
  bool _isLoading = true;
  double _loadProgress = 0.0;
  bool _straightBloom = false;
  bool _curveTablesEnabled = true;
  bool _curveTablesBusy = false;
  bool _curveLoading = true;
  List<CurveEntry> _curves = [];
  Map<String, _CurveEntryResolvedState> _curveStates = {};
  int _contentAnimationEpoch = 0;
  String _selectedGroupId = 'shockwave';
  final Map<String, ImageProvider<Object>?> _curveGroupImageProviders = {};
  final Map<String, TextEditingController> _valueControllers = {};

  // DataTable state
  bool _dataTablesEnabled = false;
  bool _dataTablesBusy = false;
  bool _backendInfiniteRenderEnabled = false;
  bool _swapCooldownEnabled = false;
  VictoryTextReplacementSettings _victoryTextReplacementSettings =
      VictoryTextReplacementSettings.defaultSettings;
  bool _dataTablesLoading = true;
  List<DataTableWeapon> _weapons = [];
  String? _selectedWeaponId;
  String? _selectedVariantWeaponId;
  DataTableSettings? _selectedWeaponSettings;
  final Map<String, ImageProvider<Object>?> _weaponImageProviders = {};
  final Map<String, TextEditingController> _dataTableControllers = {};
  final Map<String, String> _weaponVariantSelections =
      {}; // weaponId -> variantWeaponId

  _ModificationsTab _tab = _ModificationsTab.curveTables;

  void _handleExternalToggleStateChanged() {
    if (!mounted) return;
    unawaited(_load(forceRefresh: true));
  }

  @override
  void initState() {
    super.initState();
    userToggleStatesRevision.addListener(_handleExternalToggleStateChanged);
    _scheduleDeferredScreenLoad(
      this,
      () => _load(forceRefresh: true),
      delay: Duration.zero,
    );
  }

  @override
  void dispose() {
    userToggleStatesRevision.removeListener(_handleExternalToggleStateChanged);
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    for (final controller in _dataTableControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applySnapshot(
    _ModificationsScreenSnapshot snapshot, {
    required bool replayContentEntrance,
    required bool notify,
  }) {
    void apply() {
      _curveGroupImageProviders.clear();
      _weaponImageProviders.clear();
      _straightBloom = snapshot.straightBloom;
      _curveTablesEnabled = snapshot.curveTablesEnabled;
      _curves = snapshot.curves;
      _curveStates = snapshot.curveStates;
      _curveTablesBusy = false;
      _weapons = snapshot.weapons;
      _dataTablesEnabled = snapshot.dataTablesEnabled;
      _dataTablesBusy = false;
      _backendInfiniteRenderEnabled = snapshot.backendInfiniteRenderEnabled;
      _swapCooldownEnabled = snapshot.swapCooldownEnabled;
      _victoryTextReplacementSettings = snapshot.victoryTextReplacementSettings;
      _loadProgress = 1.0;
      _isLoading = false;
      _curveLoading = false;
      _dataTablesLoading = false;

      if (_selectedWeaponId != null &&
          !_weapons.any((weapon) => weapon.id == _selectedWeaponId)) {
        _selectedWeaponId = null;
        _selectedVariantWeaponId = null;
        _selectedWeaponSettings = null;
      }

      if (!_dataTablesEnabled) {
        _selectedWeaponSettings = null;
      }

      if (replayContentEntrance) {
        _contentAnimationEpoch += 1;
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  _ModificationsScreenSnapshot _currentSnapshot() {
    return _ModificationsScreenSnapshot(
      straightBloom: _straightBloom,
      curveTablesEnabled: _curveTablesEnabled,
      curves: List<CurveEntry>.of(_curves),
      curveStates: Map<String, _CurveEntryResolvedState>.of(_curveStates),
      dataTablesEnabled: _dataTablesEnabled,
      backendInfiniteRenderEnabled: _backendInfiniteRenderEnabled,
      swapCooldownEnabled: _swapCooldownEnabled,
      victoryTextReplacementSettings: _victoryTextReplacementSettings,
      weapons: List<DataTableWeapon>.of(_weapons),
    );
  }

  void _storeCurrentSnapshot() {
    _ModificationsScreenCache.store(_currentSnapshot());
  }

  ImageProvider<Object>? _resolveCachedItemImage(
    Map<String, ImageProvider<Object>?> cache,
    String? absolutePath,
  ) {
    if (absolutePath == null || absolutePath.isEmpty) return null;
    return cache.putIfAbsent(
      absolutePath,
      () => _cachedFileImageProvider(absolutePath),
    );
  }

  ImageProvider<Object>? _groupImageProvider(CurveGroup group) {
    return _resolveCachedItemImage(
      _curveGroupImageProviders,
      _groupImagePath(group),
    );
  }

  String? _weaponCardImagePath(
    DataTableWeapon weapon, {
    required bool isSelected,
  }) {
    String? effectiveImagePath = weapon.imagePath;
    final variants = weapon.variants;
    if (variants != null && variants.isNotEmpty) {
      final variantWeaponId = isSelected
          ? _selectedVariantWeaponId
          : _weaponVariantSelections[weapon.id];
      if (variantWeaponId != null) {
        final variant = variants.firstWhere(
          (entry) => entry.weaponId == variantWeaponId,
          orElse: () => variants.first,
        );
        if (variant.imagePath != null && variant.imagePath!.isNotEmpty) {
          effectiveImagePath = variant.imagePath;
        }
      }
    }

    if (effectiveImagePath == null || effectiveImagePath.isEmpty) return null;
    return joinPath([getBackendRoot(), 'public', 'items', effectiveImagePath]);
  }

  ImageProvider<Object>? _weaponImageProvider(
    DataTableWeapon weapon, {
    required bool isSelected,
  }) {
    return _resolveCachedItemImage(
      _weaponImageProviders,
      _weaponCardImagePath(weapon, isSelected: isSelected),
    );
  }

  DataTableWeapon? _currentSelectedWeapon() {
    final selectedWeaponId = _selectedWeaponId;
    if (selectedWeaponId == null) return null;
    for (final weapon in _weapons) {
      if (weapon.id == selectedWeaponId) {
        return weapon;
      }
    }
    return null;
  }

  String? _defaultVariantWeaponIdForWeapon(DataTableWeapon weapon) {
    final variants = weapon.variants;
    if (variants == null || variants.isEmpty) return null;
    return _weaponVariantSelections[weapon.id] ?? variants.first.weaponId;
  }

  Future<void> _selectDataTableWeapon(DataTableWeapon weapon) async {
    final variantWeaponId = _defaultVariantWeaponIdForWeapon(weapon);
    final settings = await DataTableService.getWeaponSettings(
      weapon,
      variantWeaponId: variantWeaponId,
    );
    if (!mounted) return;
    setState(() {
      _selectedWeaponId = weapon.id;
      _selectedVariantWeaponId = variantWeaponId;
      _selectedWeaponSettings = settings;
    });
  }

  void _selectFirstDataTableWeapon({bool loadSettings = true}) {
    if (_weapons.isEmpty) {
      setState(() {
        _selectedWeaponId = null;
        _selectedVariantWeaponId = null;
        _selectedWeaponSettings = null;
      });
      return;
    }

    final firstWeapon = _weapons.first;
    final variantWeaponId = _defaultVariantWeaponIdForWeapon(firstWeapon);
    setState(() {
      _selectedWeaponId = firstWeapon.id;
      _selectedVariantWeaponId = variantWeaponId;
      _selectedWeaponSettings = null;
    });

    if (loadSettings && _dataTablesEnabled) {
      unawaited(_loadSelectedWeaponSettings());
    }
  }

  void _handleModificationsTabSelected(_ModificationsTab tab) {
    if (tab == _ModificationsTab.dataTables) {
      if (_tab != tab) {
        setState(() => _tab = tab);
      }
      _selectFirstDataTableWeapon();
      return;
    }

    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  Future<void> _loadSelectedWeaponSettings() async {
    if (!_dataTablesEnabled) return;
    final weapon = _currentSelectedWeapon();
    if (weapon == null) return;

    final selectedWeaponId = weapon.id;
    final selectedVariantWeaponId = _selectedVariantWeaponId;
    final settings = await DataTableService.getWeaponSettings(
      weapon,
      variantWeaponId: selectedVariantWeaponId,
    );
    if (!mounted || !_dataTablesEnabled) return;
    if (_selectedWeaponId != selectedWeaponId ||
        _selectedVariantWeaponId != selectedVariantWeaponId) {
      return;
    }
    setState(() => _selectedWeaponSettings = settings);
  }

  bool _isValidNumericInput(String value) =>
      RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(value.trim());

  TextEditingController _dataTableValueController(String key, String value) {
    final controller = _dataTableControllers.putIfAbsent(
      key,
      () => TextEditingController(),
    );
    if (controller.text != value) {
      controller.text = value;
    }
    return controller;
  }

  Future<void> _applySelectedWeaponSettings(
    DataTableWeapon weapon,
    DataTableSettings settings,
  ) async {
    final selectedWeaponId = weapon.id;
    final selectedVariantWeaponId = _selectedVariantWeaponId;
    await DataTableService.applyWeaponSettings(
      weapon,
      settings,
      variantWeaponId: selectedVariantWeaponId,
    );
    final updated = await DataTableService.getWeaponSettings(
      weapon,
      variantWeaponId: selectedVariantWeaponId,
    );
    if (!mounted) return;
    if (_selectedWeaponId != selectedWeaponId ||
        _selectedVariantWeaponId != selectedVariantWeaponId) {
      return;
    }
    setState(() => _selectedWeaponSettings = updated);
  }

  Future<void> _updateSelectedWeaponSimpleValue({
    required DataTableWeapon weapon,
    required DataTableSettings settings,
    required String field,
    required String value,
  }) async {
    final trimmed = value.trim();
    if (!_isValidNumericInput(trimmed)) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Enter a valid numeric value.')),
      );
      return;
    }

    late final DataTableSettings newSettings;
    switch (field) {
      case 'damage':
        newSettings = settings.copyWith(damageValue: trimmed);
        break;
      case 'envDamage':
        newSettings = settings.copyWith(envDamageValue: trimmed);
        break;
      case 'clipSize':
        newSettings = settings.copyWith(clipSizeValue: trimmed);
        break;
      case 'reloadTime':
        newSettings = settings.copyWith(reloadTimeValue: trimmed);
        break;
      default:
        return;
    }

    await _applySelectedWeaponSettings(weapon, newSettings);
  }

  Future<void> _toggleSelectedWeaponSimpleField({
    required DataTableWeapon weapon,
    required DataTableSettings settings,
    required String field,
    required String label,
    required bool enabled,
    required String defaultValue,
    bool promptOnEnable = true,
  }) async {
    var resolvedValue = () {
      switch (field) {
        case 'damage':
          return settings.damageValue.trim().isNotEmpty
              ? settings.damageValue
              : defaultValue;
        case 'envDamage':
          return settings.envDamageValue.trim().isNotEmpty
              ? settings.envDamageValue
              : defaultValue;
        case 'clipSize':
          return settings.clipSizeValue.trim().isNotEmpty
              ? settings.clipSizeValue
              : defaultValue;
        case 'reloadTime':
          return settings.reloadTimeValue.trim().isNotEmpty
              ? settings.reloadTimeValue
              : defaultValue;
        default:
          return defaultValue;
      }
    }();

    if (enabled && promptOnEnable) {
      final promptedValue = await _promptValue(
        context,
        label,
        defaultValue: resolvedValue,
      );
      if (promptedValue == null) return;
      resolvedValue = promptedValue;
    }

    late final DataTableSettings newSettings;
    switch (field) {
      case 'damage':
        newSettings = settings.copyWith(
          damageEnabled: enabled,
          damageValue: resolvedValue,
        );
        break;
      case 'envDamage':
        newSettings = settings.copyWith(
          envDamageEnabled: enabled,
          envDamageValue: resolvedValue,
        );
        break;
      case 'clipSize':
        newSettings = settings.copyWith(
          clipSizeEnabled: enabled,
          clipSizeValue: resolvedValue,
        );
        break;
      case 'reloadTime':
        newSettings = settings.copyWith(
          reloadTimeEnabled: enabled,
          reloadTimeValue: resolvedValue,
        );
        break;
      default:
        return;
    }

    await _applySelectedWeaponSettings(weapon, newSettings);
  }

  Future<void> _openSelectedWeaponAdvancedSettings({
    required DataTableWeapon weapon,
    required DataTableSettings settings,
    required String displayDefaultDamage,
    required String displayDefaultEnvDamage,
  }) async {
    final allFields = <String>[];
    if (settings.damageEnabled) {
      allFields.addAll(weapon.damageFields);
    }
    if (settings.envDamageEnabled) {
      allFields.addAll(weapon.environmentalDamageFields);
    }

    if (allFields.isEmpty) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(
          content: Text('Enable Damage or Environmental Damage first.'),
        ),
      );
      return;
    }

    var defaultValue = displayDefaultDamage;
    if (!settings.damageEnabled && settings.envDamageEnabled) {
      defaultValue = displayDefaultEnvDamage;
    }

    final values = await _promptAdvancedSettings(
      context,
      allFields,
      settings.customValues,
      defaultValue,
    );
    if (values == null) return;

    final newSettings = settings.copyWith(
      advancedMode: true,
      customValues: values,
    );
    await _applySelectedWeaponSettings(weapon, newSettings);
  }

  Future<void> _refreshCurveStatesAfterGlobalToggle() async {
    if (_curves.isEmpty) return;
    final refreshedStates = await CurveTableService._loadCurveStates(_curves);
    if (!mounted || !_curveTablesEnabled) return;
    setState(() => _curveStates = refreshedStates);
    _storeCurrentSnapshot();
  }

  Future<void> _load({bool forceRefresh = true}) async {
    final snapshot = await _ModificationsScreenCache.warm(
      forceRefresh: forceRefresh,
      onProgress: (progress) {
        if (!mounted || !_isLoading) return;
        setState(() => _loadProgress = progress);
      },
    );
    if (!mounted) return;
    final shouldReplayContentEntrance = _isLoading;
    _applySnapshot(
      snapshot,
      replayContentEntrance: shouldReplayContentEntrance,
      notify: true,
    );
  }

  Future<void> _toggleStraightBloom(bool value) async {
    if (!mounted) return;
    setState(() {
      _straightBloom = value;
    });
    _storeCurrentSnapshot();
    StraightBloomService.setEnabled(value).ignore();
  }

  Future<void> _toggleCurveTables() async {
    if (_curveTablesBusy) return;

    final previousEnabled = _curveTablesEnabled;
    final previousStates = Map<String, _CurveEntryResolvedState>.of(
      _curveStates,
    );
    final nextEnabled = !previousEnabled;

    setState(() {
      _curveTablesBusy = true;
      _curveTablesEnabled = nextEnabled;
    });
    _storeCurrentSnapshot();

    try {
      await CurveTableService.toggleGlobal();
      if (!mounted) return;
      if (nextEnabled) {
        unawaited(_refreshCurveStatesAfterGlobalToggle());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _curveTablesEnabled = previousEnabled;
        _curveStates = previousStates;
      });
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to update CurveTables: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _curveTablesBusy = false);
        _storeCurrentSnapshot();
      }
    }
  }

  Future<void> _setDataTablesEnabled(bool enabled) async {
    if (_dataTablesBusy) return;

    final previousEnabled = _dataTablesEnabled;
    final previousSelectedWeaponId = _selectedWeaponId;
    final previousSelectedVariantWeaponId = _selectedVariantWeaponId;
    final previousSelectedWeaponSettings = _selectedWeaponSettings;
    setState(() {
      _dataTablesEnabled = enabled;
      _dataTablesBusy = true;
      if (enabled && _weapons.isNotEmpty && _selectedWeaponId == null) {
        final firstWeapon = _weapons.first;
        final hasVariants =
            firstWeapon.variants != null && firstWeapon.variants!.isNotEmpty;
        _selectedWeaponId = firstWeapon.id;
        _selectedVariantWeaponId = hasVariants
            ? firstWeapon.variants!.first.weaponId
            : null;
        _selectedWeaponSettings = null;
      } else if (!enabled) {
        _selectedWeaponSettings = null;
      }
    });
    _storeCurrentSnapshot();

    try {
      await DataTableService.setUIEnabledState(enabled);
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dataTablesEnabled = previousEnabled;
        _selectedWeaponId = previousSelectedWeaponId;
        _selectedVariantWeaponId = previousSelectedVariantWeaponId;
        _selectedWeaponSettings = previousSelectedWeaponSettings;
      });
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to update DataTables: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _dataTablesBusy = false);
        _storeCurrentSnapshot();
      }
    }

    if (enabled &&
        _selectedWeaponId != null &&
        _selectedWeaponSettings == null) {
      unawaited(_loadSelectedWeaponSettings());
    }
  }

  Future<void> _setBackendInfiniteRenderEnabled(bool enabled) async {
    final existing = await ConfigService.load();
    await ConfigService.save(
      existing.copyWith(backendInfiniteRenderEnabled: enabled),
    );
    await DataTableService.setBackendInfiniteRenderEnabled(enabled);
    final current = await DataTableService.isBackendInfiniteRenderEnabled();
    if (!mounted) return;
    setState(() => _backendInfiniteRenderEnabled = current);
    _storeCurrentSnapshot();
  }

  Future<void> _setSwapCooldownEnabled(bool enabled) async {
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(swapCooldownEnabled: enabled));
    await DataTableService.setSwapCooldownEnabled(enabled);
    final current = await DataTableService.isSwapCooldownEnabled();
    if (!mounted) return;
    setState(() => _swapCooldownEnabled = current);
    _storeCurrentSnapshot();
  }

  Future<void> _editVictoryTextReplacementSettings({
    VictoryTextReplacementSettings? initialSettings,
  }) async {
    final updated = await _promptVictoryTextReplacementSettings(
      context,
      initialSettings:
          initialSettings ??
          (_victoryTextReplacementSettings.enabled
              ? _victoryTextReplacementSettings
              : VictoryTextReplacementSettings.defaultSettings.copyWith(
                  enabled: true,
                )),
    );
    if (updated == null) return;

    await DataTableService.setVictoryTextReplacementSettings(updated);
    final current = await DataTableService.getVictoryTextReplacementSettings();
    if (!mounted) return;
    setState(() => _victoryTextReplacementSettings = current);
    _storeCurrentSnapshot();
  }

  Future<void> _importCurvesInModifications() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();
    await _importCurvesFromIniContent(importContent);
  }

  Future<int> _importCurvesFromIniContent(
    String importContent, {
    bool showSummary = true,
    bool enableImportedState = true,
    void Function(
      Map<String, List<String>> grouped,
      List<_ImportCurveDraft> missing,
    )?
    onSummary,
  }) async {
    final curvesWereEnabled = await CurveTableService.areGlobalEnabled();
    final regex = RegExp(
      '^\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$',
      multiLine: true,
    );
    final matches = regex.allMatches(importContent).toList();
    if (matches.isEmpty) return 0;

    final grouped = <String, List<String>>{};
    for (final match in matches) {
      final pathPart = match.group(1)!;
      final key = match.group(2)!;
      final line = match.group(0)!;
      final groupKey = '$pathPart|||$key';
      grouped.putIfAbsent(groupKey, () => []).add(line);
    }

    final existing = await CurveTableService.loadCurves();
    final existingKeys = existing
        .map(
          (entry) =>
              '${entry.pathPart ?? BackendPaths.defaultCurvePath}|||${entry.key}',
        )
        .toSet();

    final missing = <_ImportCurveDraft>[];
    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final pathPart = parts[0];
      final key = parts[1];
      if (!existingKeys.contains(entry.key)) {
        final parsed = _parseCurveLines(entry.value.join('\n'));
        missing.add(
          _ImportCurveDraft(
            key: key,
            pathPart: pathPart,
            lines: entry.value,
            staticValue: parsed?.staticValue ?? '0',
          ),
        );
      }
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      await CurveTableService.applyCurveLines(parts[0], parts[1], entry.value);
    }

    if (missing.isNotEmpty) {
      if (!mounted) return matches.length;
      final inputs = await _promptImportMissingCurves(
        context,
        missing,
        _groupInfosForPrompt(_curves),
      );
      if (inputs != null && inputs.isNotEmpty) {
        await CurveTableService.addCustomCurves(inputs);
      }
    }

    if (enableImportedState && matches.isNotEmpty && !curvesWereEnabled) {
      await CurveTableService._writeGlobalEnabledState(true);
      await ManagedHotfixService.rebuildDefaultGame();
    }

    await _load();
    if (!mounted) return matches.length;
    onSummary?.call(grouped, missing);
    if (showSummary) {
      await _showCurveImportSummary(context, grouped, missing: missing);
    }
    return matches.length;
  }

  Future<void> _restoreDefaultGameIniFromTemplate() async {
    final confirm = await DataService._confirmDialog(
      context,
      'Repair DefaultGame.ini from template? This will overwrite your current DefaultGame.ini in static/hotfixes, then rebuild it from your current managed data.',
    );
    if (!confirm) return;

    final templatePaths = [
      joinPath([
        getBackendRoot(),
        'static',
        'hotfixes',
        'DefaultGame Template',
        'DefaultGame.ini',
      ]),
      joinPath([
        getInstallationRoot(),
        'static',
        'hotfixes',
        'DefaultGame Template',
        'DefaultGame.ini',
      ]),
    ];
    File? templateFile;
    for (final path in templatePaths) {
      final candidate = File(path);
      if (await candidate.exists()) {
        templateFile = candidate;
        break;
      }
    }
    if (templateFile == null) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Template DefaultGame.ini not found in static/hotfixes/DefaultGame Template.',
          ),
        ),
      );
      return;
    }

    final targetFile = File(BackendPaths.defaultGameIni);
    try {
      if (await targetFile.exists()) {
        await targetFile.copy('${targetFile.path}.bak');
      }
      await templateFile.copy(targetFile.path);

      // Rebuild from the current managed source files instead of clearing them.
      // Repair INI should be non-destructive and preserve the user's live state.
      await ManagedHotfixService.rebuildDefaultGame();

      await _load();
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(
          content: Text('DefaultGame.ini repaired from template.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to repair DefaultGame.ini: $error')),
      );
    }
  }

  Future<void> _toggleCurve(CurveEntry entry, bool value) async {
    if (!_curveTablesEnabled) return;
    if (value && entry.type == 'amount' && entry.staticValue == null) {
      bool isValidNumeric(String input) =>
          RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(input.trim());
      final controller = _valueControllers[entry.id];
      final valueText = controller?.text.trim();
      if (valueText == null || valueText.isEmpty) {
        final promptedValue = await _promptValue(context, entry.name);
        if (promptedValue == null) return;
        controller?.text = promptedValue;
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: promptedValue,
        );
      } else {
        if (!isValidNumeric(valueText)) {
          if (!mounted) return;
          showAtlasSnackBar(
            context,
            const SnackBar(content: Text('Enter a valid numeric value.')),
          );
          return;
        }
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: valueText,
        );
      }
    } else {
      await CurveTableService.setCurveEnabled(entry, value);
    }
    await _load();
  }

  Future<void> _updateCurveValue(CurveEntry entry, String newValue) async {
    if (!_curveTablesEnabled) return;
    final enabled = _curveStates[entry.id]?.enabled ?? false;
    if (!enabled) return;
    final isValid = RegExp(
      r'^[+-]?(?:\d+\.?\d*|\.\d+)$',
    ).hasMatch(newValue.trim());
    if (!isValid) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Enter a valid numeric value.')),
      );
      return;
    }
    await CurveTableService.setCurveEnabled(entry, true, customValue: newValue);
    await _load();
  }

  List<CurveGroup> get _groups {
    final builtinIds = _baseCurveGroups.map((group) => group.id).toSet();
    final customGroups =
        _customGroupsFromCurves(_curves, excludeIds: builtinIds).map((group) {
          return CurveGroup(
            id: group.id,
            title: group.name,
            imagePath: group.imagePath,
            icon: Icons.auto_awesome,
            keywords: const [],
            isCustom: true,
          );
        }).toList();

    return [..._baseCurveGroups, ...customGroups];
  }

  List<CurveEntry> _entriesForGroup(
    CurveGroup group,
    List<CurveEntry> entries,
  ) {
    final scopedEntries = group.isCustom
        ? entries.where((entry) => entry.isCustom).toList()
        : entries
              .where((entry) => !entry.isCustom || entry.groupId == group.id)
              .toList();
    final groupMatches = scopedEntries
        .where((entry) => group.matches(entry))
        .toList();
    if (!group.isCustom && group.id == 'glider') {
      return groupMatches.where((entry) {
        final name = entry.name.toLowerCase();
        final key = entry.key.toLowerCase();
        return !name.contains('jules') && !key.contains('grapplinghoot');
      }).toList();
    }
    if (!group.isCustom && group.id == 'impulse') {
      return groupMatches.where((entry) {
        final name = entry.name.toLowerCase();
        final key = entry.key.toLowerCase();
        return !name.contains('cube') && !key.contains('cube');
      }).toList();
    }
    return groupMatches;
  }

  String _groupImagePath(CurveGroup group) {
    final customPath = group.imagePath;
    if (customPath != null && customPath.isNotEmpty) {
      return joinPath([getBackendRoot(), 'public', 'items', customPath]);
    }
    final imageName = group.imageName ?? '';
    return joinPath([getBackendRoot(), 'public', 'items', imageName]);
  }

  Future<void> _addCustomCurve() async {
    final inputs = await _promptCustomCurves(
      context,
      _groupInfosForPrompt(_curves),
    );
    if (inputs == null || inputs.isEmpty) return;
    await CurveTableService.addCustomCurves(inputs);
    await _load();
  }

  Future<void> _importDataTablesINI() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();
    await _importDataTablesFromIniContent(importContent);
  }

  Future<int> _importDataTablesFromIniContent(
    String importContent, {
    bool showNoEntriesSnackBar = true,
    bool showImportedSnackBar = true,
    bool enableImportedState = true,
    void Function(int fixesLines)? onFixesDetected,
  }) async {
    final dataTablesWereEnabled = await DataTableService.getUIEnabledState();
    final knownFixLines = await ManagedHotfixService.readLines(
      File(BackendPaths.fixesLinesIni),
    );
    final knownStraightBloomLines =
        await StraightBloomService._readConfiguredLines();
    final imported = extractImportedDataTableAndFixLines(
      content: importContent,
      knownFixLines: knownFixLines,
      knownStraightBloomLines: knownStraightBloomLines,
    );
    final lines = imported.dataTableLines;
    final fixesLines = imported.fixesLines;
    if (lines.isEmpty && fixesLines.isEmpty) {
      if (showNoEntriesSnackBar) {
        if (!mounted) return 0;
        showAtlasSnackBar(
          context,
          const SnackBar(content: Text('No DataTable entries found in file')),
        );
      }
      return 0;
    }

    if (lines.isNotEmpty) {
      await DataTableService.importDataTableLines(lines);
    }
    if (enableImportedState && lines.isNotEmpty && !dataTablesWereEnabled) {
      await DataTableService.setUIEnabledState(true);
    }
    if (lines.isNotEmpty) {
      await _load();
    }

    onFixesDetected?.call(fixesLines.length);
    if (!mounted) return lines.length;
    if (showImportedSnackBar) {
      final summaryParts = <String>[];
      if (lines.isNotEmpty) {
        summaryParts.add(
          '${lines.length} DataTable ${lines.length == 1 ? 'entry' : 'entries'}',
        );
      }
      if (fixesLines.isNotEmpty) {
        summaryParts.add(
          '${fixesLines.length} ${fixesLines.length == 1 ? 'Fixes line' : 'Fixes lines'} detected (current Fixes.ini kept)',
        );
      }
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Imported ${summaryParts.join(' and ')}')),
      );
    }
    return lines.length;
  }

  Future<int> _importStraightBloomFromIniContent(
    String importContent, {
    bool showNoEntriesSnackBar = true,
    bool showImportedSnackBar = true,
    bool enableImportedState = true,
  }) async {
    final configuredLines = await StraightBloomService._readConfiguredLines();
    final imported = extractImportedDataTableAndFixLines(
      content: importContent,
      knownStraightBloomLines: configuredLines,
    );
    final lines = imported.straightBloomLines;
    if (lines.isEmpty) {
      if (showNoEntriesSnackBar) {
        if (!mounted) return 0;
        showAtlasSnackBar(
          context,
          const SnackBar(
            content: Text('No Straight Bloom entries found in file'),
          ),
        );
      }
      return 0;
    }

    if (enableImportedState) {
      await StraightBloomService.setEnabled(
        imported.hasActiveStraightBloomLines,
      );
    }
    await _load();

    if (!mounted) return lines.length;
    if (showImportedSnackBar) {
      final stateLabel = imported.hasActiveStraightBloomLines
          ? 'enabled'
          : 'left off';
      showAtlasSnackBar(
        context,
        SnackBar(
          content: Text(
            'Detected ${lines.length} Straight Bloom ${lines.length == 1 ? 'line' : 'lines'} ($stateLabel, current StraightBloom.ini kept)',
          ),
        ),
      );
    }
    return lines.length;
  }

  Future<void> _importIniInModifications() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();

    int curveLines = 0;
    int straightBloomLines = 0;
    int dataTableLines = 0;
    int fixesLines = 0;
    Map<String, List<String>> curveGrouped = const {};
    List<_ImportCurveDraft> curveMissing = const [];

    curveLines = await _importCurvesFromIniContent(
      importContent,
      showSummary: false,
      onSummary: (grouped, missing) {
        curveGrouped = grouped;
        curveMissing = missing;
      },
    );
    straightBloomLines = await _importStraightBloomFromIniContent(
      importContent,
      showNoEntriesSnackBar: false,
      showImportedSnackBar: false,
    );
    dataTableLines = await _importDataTablesFromIniContent(
      importContent,
      showNoEntriesSnackBar: false,
      showImportedSnackBar: false,
      onFixesDetected: (count) => fixesLines = count,
    );

    if (!mounted) return;

    if (curveLines == 0 &&
        straightBloomLines == 0 &&
        dataTableLines == 0 &&
        fixesLines == 0) {
      const message =
          'No CurveTable, Straight Bloom, DataTable, or Fixes entries found in file';
      showAtlasSnackBar(context, SnackBar(content: Text(message)));
      return;
    }

    // Always rebuild after import so developer-managed Fixes.ini lines are
    // fully materialized back into DefaultGame.ini even if the imported file
    // was missing some of them.
    await ManagedHotfixService.rebuildDefaultGame();
    await _load();
    if (!mounted) return;

    await _showModificationsIniImportSummary(
      context,
      attemptedCurves: true,
      attemptedDataTables: true,
      curveGrouped: curveGrouped,
      curveMissing: curveMissing,
      curveLines: curveLines,
      straightBloomLines: straightBloomLines,
      dataTableLines: dataTableLines,
      fixesLines: fixesLines,
    );
  }

  Widget _buildLoadingPlaceholderList(
    BuildContext context, {
    int rows = 4,
    double height = 64,
  }) {
    return Column(
      children: List.generate(rows, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 12),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.035),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _onSurface(context, 0.08)),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLoadingPlaceholderCards(BuildContext context, {int count = 6}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(count, (_) {
        return Container(
          width: 140,
          height: 130,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _onSurface(context, 0.08)),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentMenuKey = _isLoading
        ? 'modifications-shell'
        : 'modifications-loaded-$_contentAnimationEpoch';
    final entriesByGroup = <String, List<CurveEntry>>{
      for (final group in _groups) group.id: _entriesForGroup(group, _curves),
    };
    final visibleGroups = _groups
        .where((group) => (entriesByGroup[group.id] ?? const []).isNotEmpty)
        .toList();
    final selectedGroup = visibleGroups.firstWhere(
      (group) => group.id == _selectedGroupId,
      orElse: () =>
          visibleGroups.isNotEmpty ? visibleGroups.first : _groups.first,
    );
    final selectedGroupEntries =
        entriesByGroup[selectedGroup.id] ?? const <CurveEntry>[];
    return _BaseScreen(
      title: 'Modifications',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            child: OutlinedButton.icon(
              onPressed: () async {
                final hotfixesPath = joinPath([
                  getBackendRoot(),
                  'static',
                  'hotfixes',
                ]);
                try {
                  await Process.start('explorer', [hotfixesPath]);
                } catch (_) {}
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Folder'),
            ),
          ),
          const SizedBox(width: 10),
          _HoverScale(
            enabled: !_isLoading,
            child: OutlinedButton.icon(
              onPressed: !_isLoading ? _importIniInModifications : null,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import INI'),
            ),
          ),
          const SizedBox(width: 10),
          _HoverScale(
            child: OutlinedButton.icon(
              onPressed: _restoreDefaultGameIniFromTemplate,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Repair INI'),
            ),
          ),
        ],
      ),
      child: _ScreenLoadGate(
        loading: _isLoading,
        transitionKey: 'modifications-$_contentAnimationEpoch',
        progress: _loadProgress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1040;

            Widget disabledCard({
              required IconData icon,
              required String title,
              required String message,
            }) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _onSurface(context, 0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: _onSurface(context, 0.6)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _onSurface(context, 0.7)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final straightBloomSwitch = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _straightBloom,
              onChanged: _isLoading ? null : _toggleStraightBloom,
              title: Text(
                _straightBloom
                    ? 'Straight Bloom Enabled'
                    : 'Straight Bloom Disabled',
              ),
              subtitle: const Text('Toggles no-spread for all snipers.'),
            );

            final curveTablesSwitch = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _curveTablesEnabled,
              onChanged: (_isLoading || _curveTablesBusy)
                  ? null
                  : (_) => _toggleCurveTables(),
              title: Text(
                _curveTablesEnabled
                    ? 'CurveTables Enabled'
                    : 'CurveTables Disabled',
              ),
              subtitle: const Text('Toggle all CurveTable entries on/off'),
            );

            final dataTablesSwitch = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _dataTablesEnabled,
              onChanged: (_isLoading || _dataTablesBusy)
                  ? null
                  : _setDataTablesEnabled,
              title: Text(
                _dataTablesEnabled
                    ? 'DataTables Enabled'
                    : 'DataTables Disabled',
              ),
              subtitle: const Text('Toggle weapon damage modifications'),
            );

            Widget versionTag(String label) {
              return _AtlasTagPill(label: label);
            }

            final backendInfiniteRenderSwitch = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _backendInfiniteRenderEnabled,
              onChanged: _isLoading ? null : _setBackendInfiniteRenderEnabled,
              title: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Backend Infinite Render'),
                  versionTag('v26+'),
                ],
              ),
              subtitle: const Text(
                'Keeps projectiles and bullets active and rendering over long distances on v26.00 and higher',
              ),
            );

            final swapCooldownSwitch = SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _swapCooldownEnabled,
              onChanged: _isLoading ? null : _setSwapCooldownEnabled,
              title: const Text('No Swap Cooldown'),
              subtitle: const Text(
                'Removes the delay between switching weapons or items (Ex. Double Pump)',
              ),
            );

            final victoryEditColor = Theme.of(context).colorScheme.secondary;
            final switchTheme = Theme.of(context).switchTheme;
            final victoryUsesDefaultText =
                _victoryTextReplacementSettings.usesDefaultText;
            final victoryActiveTrackColor =
                switchTheme.trackColor?.resolve({WidgetState.selected}) ??
                victoryEditColor.withOpacity(0.55);
            final victoryActiveThumbColor =
                switchTheme.thumbColor?.resolve({WidgetState.selected}) ??
                victoryEditColor;
            final victoryDefaultTrackColor =
                switchTheme.trackColor?.resolve(<WidgetState>{}) ??
                _onSurface(context, 0.22);
            final victoryDefaultThumbColor =
                switchTheme.thumbColor?.resolve(<WidgetState>{}) ??
                _onSurface(context, 0.58);
            final victoryEditBackground = victoryUsesDefaultText
                ? victoryDefaultTrackColor
                : victoryActiveTrackColor;
            final victoryEditIconColor = victoryUsesDefaultText
                ? victoryDefaultThumbColor
                : victoryActiveThumbColor;
            const victorySwitchSlot = Size(60, 40);
            const victorySwitchTrack = Size(52, 32);
            final victoryButtonOutlineColor = victoryUsesDefaultText
                ? Colors.white.withOpacity(0.9)
                : Colors.transparent;
            final victoryTrackOutlineWidth = victoryUsesDefaultText
                ? (switchTheme.trackOutlineWidth?.resolve(<WidgetState>{}) ??
                    2.0)
                : 0.0;
            final victoryTextReplacementTile = ListTile(
              contentPadding: EdgeInsets.zero,
              title: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Victory Text Replacement'),
                  versionTag('v11+'),
                ],
              ),
              subtitle: const Text(
                'Change the "#1 Victory Royale" placement and text.',
              ),
              trailing: _HoverScale(
                enabled: !_isLoading,
                child: SizedBox.fromSize(
                  size: victorySwitchSlot,
                  child: Center(
                    child: SizedBox.fromSize(
                      size: victorySwitchTrack,
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => _editVictoryTextReplacementSettings(),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          fixedSize: victorySwitchTrack,
                          minimumSize: victorySwitchTrack,
                          maximumSize: victorySwitchTrack,
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: victoryButtonOutlineColor,
                            width: victoryTrackOutlineWidth,
                          ),
                          backgroundColor: victoryEditBackground,
                          foregroundColor: victoryEditIconColor,
                        ),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 16,
                          color: victoryEditIconColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            final listPadding = EdgeInsets.only(
              right: isWide ? 16 : 12,
              bottom: 12,
            );
            final togglesPanel = ListView(
              padding: listPadding,
              children: [
                const _SectionTitle(title: 'Straight Bloom'),
                straightBloomSwitch,
                const SizedBox(height: 20),
                const _SectionTitle(title: 'CurveTables'),
                curveTablesSwitch,
                const SizedBox(height: 20),
                const _SectionTitle(title: 'DataTables'),
                dataTablesSwitch,
                const SizedBox(height: 20),
                const _SectionTitle(title: 'Other'),
                victoryTextReplacementTile,
                backendInfiniteRenderSwitch,
                swapCooldownSwitch,
              ],
            );

            final accent = Theme.of(context).colorScheme.secondary;

            Widget tabPill({
              required String label,
              required _ModificationsTab tab,
            }) {
              final selected = _tab == tab;
              return _HoverRegion(
                builder: (context, hovered) {
                  final bgColor = selected
                      ? accent.withOpacity(0.18)
                      : hovered
                      ? Colors.black.withOpacity(0.06)
                      : Colors.transparent;
                  final borderColor = selected
                      ? accent.withOpacity(0.55)
                      : Colors.transparent;
                  return GestureDetector(
                    onTap: () => _handleModificationsTabSelected(tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? accent : _onSurface(context, 0.75),
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            final tablesTabs = Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _onSurface(context, 0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: tabPill(
                      label: 'CurveTables',
                      tab: _ModificationsTab.curveTables,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: tabPill(
                      label: 'DataTables',
                      tab: _ModificationsTab.dataTables,
                    ),
                  ),
                ],
              ),
            );

            final contentPanel = ListView(
              padding: listPadding,
              children: [
                if (!isWide) ...[
                  const _SectionTitle(title: 'Straight Bloom'),
                  straightBloomSwitch,
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Other'),
                  victoryTextReplacementTile,
                  backendInfiniteRenderSwitch,
                  swapCooldownSwitch,
                  const SizedBox(height: 20),
                ],
                tablesTabs,
                const SizedBox(height: 20),
                if (_tab == _ModificationsTab.curveTables) ...[
                  if (!isWide) curveTablesSwitch,
                  const SizedBox(height: 8),
                  _menuToggleReveal(
                    context,
                    revealKey: 'modifications-curvetables-$isWide',
                    visible: _curveTablesEnabled,
                    hiddenChild: isWide
                        ? disabledCard(
                            icon: Icons.table_rows_outlined,
                            title: 'CurveTables Disabled',
                            message:
                                'Enable CurveTables on the left to manage hotfix curve entries.',
                          )
                        : const SizedBox.shrink(),
                    child: _curveTablesEnabled
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              _curveLoading
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildLoadingPlaceholderCards(
                                          context,
                                          count: isWide ? 6 : 4,
                                        ),
                                        const SizedBox(height: 12),
                                        _buildLoadingPlaceholderList(
                                          context,
                                          rows: isWide ? 5 : 4,
                                          height: 68,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 12,
                                          children: visibleGroups.map((group) {
                                            final isSelected =
                                                selectedGroup.id == group.id;
                                            final imageProvider =
                                                _groupImageProvider(group);
                                            final isDark =
                                                Theme.of(context).brightness ==
                                                Brightness.dark;
                                            return GestureDetector(
                                              onTap: () => setState(
                                                () =>
                                                    _selectedGroupId = group.id,
                                              ),
                                              child: _HoverRegion(
                                                builder: (context, hovered) => AnimatedScale(
                                                  duration: const Duration(
                                                    milliseconds: 140,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                  scale: hovered ? 1.03 : 1,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 180,
                                                    ),
                                                    width: 140,
                                                    height: 130,
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      color: isSelected
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                                .withOpacity(
                                                                  0.18,
                                                                )
                                                          : Colors.black
                                                                .withOpacity(
                                                                  0.08,
                                                                ),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .secondary
                                                                  .withOpacity(
                                                                    0.6,
                                                                  )
                                                            : _onSurface(
                                                                context,
                                                                0.12,
                                                              ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        if (imageProvider !=
                                                            null)
                                                          _HoverShadow(
                                                            opacity: 0.75,
                                                            blurSigma: 2,
                                                            baseOffset:
                                                                const Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                            hoverOffset:
                                                                const Offset(
                                                                  4,
                                                                  2,
                                                                ),
                                                            hovered: hovered,
                                                            child:
                                                                (group.id ==
                                                                    'fall'
                                                                ? ColorFiltered(
                                                                    colorFilter: ColorFilter.mode(
                                                                      isDark
                                                                          ? Colors.white
                                                                          : Colors.black,
                                                                      BlendMode
                                                                          .srcIn,
                                                                    ),
                                                                    child: Image(
                                                                      image:
                                                                          imageProvider,
                                                                      width: 52,
                                                                      height:
                                                                          52,
                                                                      fit: BoxFit
                                                                          .contain,
                                                                      filterQuality:
                                                                          FilterQuality
                                                                              .low,
                                                                    ),
                                                                  )
                                                                : Image(
                                                                    image:
                                                                        imageProvider,
                                                                    width: 52,
                                                                    height: 52,
                                                                    fit: BoxFit
                                                                        .contain,
                                                                    filterQuality:
                                                                        FilterQuality
                                                                            .low,
                                                                  )),
                                                          )
                                                        else
                                                          _HoverShadow(
                                                            opacity: 0.75,
                                                            blurSigma: 2,
                                                            baseOffset:
                                                                const Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                            hoverOffset:
                                                                const Offset(
                                                                  4,
                                                                  2,
                                                                ),
                                                            hovered: hovered,
                                                            child: Icon(
                                                              group.icon,
                                                              size: 38,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .secondary,
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Text(
                                                          group.title,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Text(
                                              selectedGroup.title,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                            const Spacer(),
                                            if (selectedGroup.isCustom)
                                              _HoverScale(
                                                child: OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final updated =
                                                        await _promptEditCustomGroup(
                                                          context,
                                                          selectedGroup.id,
                                                          selectedGroup.title,
                                                        );
                                                    if (updated == null) return;
                                                    await CurveTableService.updateCustomGroup(
                                                      selectedGroup.id,
                                                      updated.name,
                                                      updated.imagePath,
                                                    );
                                                    await _load();
                                                  },
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                  label: const Text(
                                                    'Edit Group',
                                                  ),
                                                ),
                                              ),
                                            if (selectedGroup.isCustom)
                                              const SizedBox(width: 8),
                                            if (selectedGroup.isCustom)
                                              _HoverScale(
                                                child: OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final confirm =
                                                        await DataService._confirmDialog(
                                                          context,
                                                          'Delete group "${selectedGroup.title}" and all its custom curves?',
                                                        );
                                                    if (!confirm) return;
                                                    await CurveTableService.deleteCustomGroup(
                                                      selectedGroup.id,
                                                    );
                                                    await _load();
                                                  },
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                  ),
                                                  label: const Text(
                                                    'Delete Group',
                                                  ),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        foregroundColor:
                                                            Colors.redAccent,
                                                      ),
                                                ),
                                              ),
                                            if (selectedGroup.isCustom)
                                              const SizedBox(width: 8),
                                            _HoverScale(
                                              enabled: _curveTablesEnabled,
                                              child: OutlinedButton.icon(
                                                onPressed: _addCustomCurve,
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                ),
                                                label: const Text(
                                                  'Add Custom Curve',
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(
                                                    0xFF1E88E5,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _HoverScale(
                                              enabled: _curveTablesEnabled,
                                              child: OutlinedButton.icon(
                                                onPressed: () async {
                                                  final confirm =
                                                      await DataService._confirmDialog(
                                                        context,
                                                        'Clear all CurveTables from DefaultGame.ini?',
                                                      );
                                                  if (!confirm) return;
                                                  await CurveTableService.clearAllCurveTables();
                                                  await _load();
                                                },
                                                icon: const Icon(
                                                  Icons.delete_sweep_outlined,
                                                ),
                                                label: const Text(
                                                  'Clear All CurveTables',
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(
                                                    0xFF1E88E5,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        ...selectedGroupEntries.map((entry) {
                                          final controller = _valueControllers
                                              .putIfAbsent(
                                                entry.id,
                                                () => TextEditingController(),
                                              );
                                          final resolvedState =
                                              _curveStates[entry.id] ??
                                              const _CurveEntryResolvedState();
                                          return _CurveEntryTile(
                                            entry: entry,
                                            enabled: _curveTablesEnabled,
                                            resolvedState: resolvedState,
                                            valueController: controller,
                                            onToggle: (value) =>
                                                _toggleCurve(entry, value),
                                            onSubmit: (value) =>
                                                _updateCurveValue(entry, value),
                                            onEdit: entry.isCustom
                                                ? () async {
                                                    final updated =
                                                        await _promptEditCustomCurve(
                                                          context,
                                                          entry,
                                                          _groupInfosForPrompt(
                                                            _curves,
                                                          ),
                                                        );
                                                    if (updated == null) return;
                                                    await CurveTableService.updateCustomCurve(
                                                      entry.id,
                                                      updated,
                                                    );
                                                    await _load();
                                                  }
                                                : null,
                                            onDelete: entry.isCustom
                                                ? () async {
                                                    final confirm =
                                                        await DataService._confirmDialog(
                                                          context,
                                                          'Delete custom curve "${entry.name}"?',
                                                        );
                                                    if (!confirm) return;
                                                    await CurveTableService.deleteCustomCurve(
                                                      entry.id,
                                                    );
                                                    await _load();
                                                  }
                                                : null,
                                          );
                                        }),
                                      ],
                                    ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
                if (_tab == _ModificationsTab.dataTables) ...[
                  if (!isWide) dataTablesSwitch,
                  const SizedBox(height: 8),
                  _menuToggleReveal(
                    context,
                    revealKey: 'modifications-datatables-$isWide',
                    visible: _dataTablesEnabled,
                    hiddenChild: isWide
                        ? disabledCard(
                            icon: Icons.tune_rounded,
                            title: 'DataTables Disabled',
                            message:
                                'Enable DataTables on the left to manage weapon damage modifications.',
                          )
                        : const SizedBox.shrink(),
                    child: _dataTablesEnabled
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              _dataTablesLoading
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildLoadingPlaceholderCards(
                                          context,
                                          count: isWide ? 6 : 4,
                                        ),
                                        const SizedBox(height: 20),
                                        _buildLoadingPlaceholderList(
                                          context,
                                          rows: 3,
                                          height: 76,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 12,
                                          children: _weapons.map((weapon) {
                                            final isSelected =
                                                _selectedWeaponId == weapon.id;
                                            final imageProvider =
                                                _weaponImageProvider(
                                                  weapon,
                                                  isSelected: isSelected,
                                                );
                                            return GestureDetector(
                                              onTap: () async {
                                                await _selectDataTableWeapon(
                                                  weapon,
                                                );
                                              },
                                              child: _HoverRegion(
                                                builder: (context, hovered) => AnimatedScale(
                                                  duration: const Duration(
                                                    milliseconds: 140,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                  scale: hovered ? 1.03 : 1,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 180,
                                                    ),
                                                    width: 140,
                                                    height: 130,
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      color: isSelected
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                                .withOpacity(
                                                                  0.18,
                                                                )
                                                          : Colors.black
                                                                .withOpacity(
                                                                  0.08,
                                                                ),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .secondary
                                                                  .withOpacity(
                                                                    0.6,
                                                                  )
                                                            : _onSurface(
                                                                context,
                                                                0.12,
                                                              ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        if (imageProvider !=
                                                            null)
                                                          _HoverShadow(
                                                            opacity: 0.75,
                                                            blurSigma: 2,
                                                            baseOffset:
                                                                const Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                            hoverOffset:
                                                                const Offset(
                                                                  4,
                                                                  2,
                                                                ),
                                                            hovered: hovered,
                                                            child: Image(
                                                              image:
                                                                  imageProvider,
                                                              width: 52,
                                                              height: 52,
                                                              fit: BoxFit
                                                                  .contain,
                                                              filterQuality:
                                                                  FilterQuality
                                                                      .low,
                                                            ),
                                                          )
                                                        else
                                                          _HoverShadow(
                                                            opacity: 0.75,
                                                            blurSigma: 2,
                                                            baseOffset:
                                                                const Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                            hoverOffset:
                                                                const Offset(
                                                                  4,
                                                                  2,
                                                                ),
                                                            hovered: hovered,
                                                            child: Icon(
                                                              Icons
                                                                  .sports_esports,
                                                              size: 38,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .secondary,
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Text(
                                                          weapon.name,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                        if (_selectedWeaponId != null &&
                                            _selectedWeaponSettings !=
                                                null) ...[
                                          const SizedBox(height: 20),
                                          _buildWeaponSettings(),
                                        ],
                                      ],
                                    ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            );
            if (!isWide) {
              return _menuEntrance(
                context,
                menuKey: contentMenuKey,
                index: 0,
                child: contentPanel,
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: _menuEntrance(
                    context,
                    menuKey: contentMenuKey,
                    index: 0,
                    child: togglesPanel,
                  ),
                ),
                const SizedBox(width: 24),
                Container(width: 1, color: _onSurface(context, 0.08)),
                const SizedBox(width: 24),
                Expanded(
                  child: _menuEntrance(
                    context,
                    menuKey: contentMenuKey,
                    index: 1,
                    child: contentPanel,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWeaponSettings() {
    final weapon = _weapons.firstWhere((w) => w.id == _selectedWeaponId);
    final settings = _selectedWeaponSettings!;
    final hasVariants = weapon.variants != null && weapon.variants!.isNotEmpty;

    WeaponVariant? currentVariant;
    if (hasVariants && _selectedVariantWeaponId != null) {
      currentVariant = weapon.variants!.firstWhere(
        (v) => v.weaponId == _selectedVariantWeaponId,
        orElse: () => weapon.variants!.first,
      );
    }
    final variantKey = _selectedVariantWeaponId ?? 'base';

    final displayDefaultDamage = currentVariant?.damagePB ?? weapon.damagePB;
    final displayDefaultEnvDamage =
        currentVariant?.defaultEnvDamage ?? weapon.defaultEnvDamage;
    final displayDefaultClipSize = weapon.clipSize ?? '30';
    final displayDefaultReloadTime = currentVariant?.reloadTime ?? '2.0';

    // Check which fields are available for this weapon
    final hasDamageFields = weapon.damageFields.isNotEmpty;
    final hasEnvDamageFields = weapon.environmentalDamageFields.isNotEmpty;
    final hasClipSize = weapon.clipSize != null;
    final hasReloadTime = hasVariants
        ? (currentVariant?.reloadTime != null)
        : false;
    final damageController = hasDamageFields
        ? _dataTableValueController(
            '${weapon.id}::$variantKey::damage',
            settings.damageValue,
          )
        : null;
    final envDamageController = hasEnvDamageFields
        ? _dataTableValueController(
            '${weapon.id}::$variantKey::envDamage',
            settings.envDamageValue,
          )
        : null;
    final clipSizeController = hasClipSize
        ? _dataTableValueController(
            '${weapon.id}::$variantKey::clipSize',
            settings.clipSizeValue,
          )
        : null;
    final reloadTimeController = hasReloadTime
        ? _dataTableValueController(
            '${weapon.id}::$variantKey::reloadTime',
            settings.reloadTimeValue,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Text(
                weapon.name,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 7,
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HoverScale(
                      enabled: _dataTablesEnabled,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await DataService._confirmDialog(
                            context,
                            'Clear all DataTables from DefaultGame.ini?',
                          );
                          if (!confirm) return;
                          await DataTableService.clearAllDataTables();
                          await _load();
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Clear All DataTables'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E88E5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hasVariants) ...[
          DropdownButtonFormField<String>(
            initialValue: _selectedVariantWeaponId,
            decoration: InputDecoration(
              labelText: 'Variant',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: weapon.variants!.map((variant) {
              return DropdownMenuItem(
                value: variant.weaponId,
                child: Text(variant.name),
              );
            }).toList(),
            onChanged: (value) async {
              if (value != null) {
                final newSettings = await DataTableService.getWeaponSettings(
                  weapon,
                  variantWeaponId: value,
                );
                setState(() {
                  _selectedVariantWeaponId = value;
                  _selectedWeaponSettings = newSettings;
                  _weaponVariantSelections[weapon.id] =
                      value; // Remember this selection
                });
              }
            },
          ),
          const SizedBox(height: 12),
        ],
        if (hasDamageFields)
          _DataTableSettingTile(
            title: 'Damage',
            subtitle: settings.damageEnabled
                ? (settings.advancedMode
                      ? 'Managed by advanced settings'
                      : 'Custom damage value')
                : 'Enable custom damage values',
            isEnabled: settings.damageEnabled,
            enabled: _dataTablesEnabled,
            showValueField: settings.damageEnabled && !settings.advancedMode,
            valueController: damageController,
            onSubmitted: (value) => _updateSelectedWeaponSimpleValue(
              weapon: weapon,
              settings: settings,
              field: 'damage',
              value: value,
            ),
            onToggle: (value) async {
              await _toggleSelectedWeaponSimpleField(
                weapon: weapon,
                settings: settings,
                field: 'damage',
                label: 'Damage',
                enabled: value,
                defaultValue: displayDefaultDamage,
                promptOnEnable: !settings.advancedMode,
              );
            },
          ),
        if (hasEnvDamageFields)
          _DataTableSettingTile(
            title: 'Environmental Damage',
            subtitle: settings.envDamageEnabled
                ? (settings.advancedMode
                      ? 'Managed by advanced settings'
                      : 'Custom environmental damage value')
                : 'Enable custom environmental damage',
            isEnabled: settings.envDamageEnabled,
            enabled: _dataTablesEnabled,
            showValueField: settings.envDamageEnabled && !settings.advancedMode,
            valueController: envDamageController,
            onSubmitted: (value) => _updateSelectedWeaponSimpleValue(
              weapon: weapon,
              settings: settings,
              field: 'envDamage',
              value: value,
            ),
            onToggle: (value) async {
              await _toggleSelectedWeaponSimpleField(
                weapon: weapon,
                settings: settings,
                field: 'envDamage',
                label: 'Environmental Damage',
                enabled: value,
                defaultValue: displayDefaultEnvDamage,
                promptOnEnable: !settings.advancedMode,
              );
            },
          ),
        if (hasClipSize)
          _DataTableSettingTile(
            title: 'Clip Size',
            subtitle: settings.clipSizeEnabled
                ? 'Custom clip size value'
                : 'Enable custom clip size',
            isEnabled: settings.clipSizeEnabled,
            enabled: _dataTablesEnabled,
            showValueField: settings.clipSizeEnabled,
            valueController: clipSizeController,
            onSubmitted: (value) => _updateSelectedWeaponSimpleValue(
              weapon: weapon,
              settings: settings,
              field: 'clipSize',
              value: value,
            ),
            onToggle: (value) async {
              await _toggleSelectedWeaponSimpleField(
                weapon: weapon,
                settings: settings,
                field: 'clipSize',
                label: 'Clip Size',
                enabled: value,
                defaultValue: displayDefaultClipSize,
              );
            },
          ),
        if (hasReloadTime)
          _DataTableSettingTile(
            title: 'Reload Time',
            subtitle: settings.reloadTimeEnabled
                ? 'Custom reload time value'
                : 'Enable custom reload time',
            isEnabled: settings.reloadTimeEnabled,
            enabled: _dataTablesEnabled,
            showValueField: settings.reloadTimeEnabled,
            valueController: reloadTimeController,
            onSubmitted: (value) => _updateSelectedWeaponSimpleValue(
              weapon: weapon,
              settings: settings,
              field: 'reloadTime',
              value: value,
            ),
            onToggle: (value) async {
              await _toggleSelectedWeaponSimpleField(
                weapon: weapon,
                settings: settings,
                field: 'reloadTime',
                label: 'Reload Time',
                enabled: value,
                defaultValue: displayDefaultReloadTime,
              );
            },
          ),
        if (hasDamageFields || hasEnvDamageFields)
          _DataTableActionTile(
            title: 'Advanced Settings',
            subtitle: settings.advancedMode
                ? 'Viewing individual field values'
                : 'View and customize each damage field individually',
            isActive: settings.advancedMode,
            enabled: _dataTablesEnabled,
            actionLabel: settings.advancedMode ? 'Edit' : 'View',
            onPressed: () async {
              await _openSelectedWeaponAdvancedSettings(
                weapon: weapon,
                settings: settings,
                displayDefaultDamage: displayDefaultDamage,
                displayDefaultEnvDamage: displayDefaultEnvDamage,
              );
            },
          ),
      ],
    );
  }
}

class CurveTablesScreen extends StatefulWidget {
  const CurveTablesScreen({super.key});

  @override
  State<CurveTablesScreen> createState() => _CurveTablesScreenState();
}

class _CurveTablesScreenState extends State<CurveTablesScreen> {
  bool _loading = true;
  double _loadProgress = 0.0;
  bool _globalEnabled = true;
  List<CurveEntry> _curves = [];
  Map<String, _CurveEntryResolvedState> _curveStates = {};
  String _search = '';
  final Map<String, TextEditingController> _valueControllers = {};

  void _handleExternalToggleStateChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  @override
  void initState() {
    super.initState();
    userToggleStatesRevision.addListener(_handleExternalToggleStateChanged);
    _scheduleDeferredScreenLoad(this, _load);
  }

  @override
  void dispose() {
    userToggleStatesRevision.removeListener(_handleExternalToggleStateChanged);
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final modificationsSnapshot = _ModificationsScreenCache.snapshot;
    if (modificationsSnapshot != null) {
      setState(() {
        _curves = modificationsSnapshot.curves;
        _curveStates = modificationsSnapshot.curveStates;
        _globalEnabled = modificationsSnapshot.curveTablesEnabled;
        _loadProgress = 1.0;
        _loading = false;
      });
      return;
    }

    final curvesFuture = CurveTableService.loadCurves();
    final enabledFuture = CurveTableService.areGlobalEnabled();
    final curves = await curvesFuture;
    if (mounted) {
      setState(() => _loadProgress = 0.34);
    }
    final curveStatesFuture = CurveTableService._loadCurveStates(curves);
    final enabled = await enabledFuture;
    if (mounted) {
      setState(() => _loadProgress = 0.67);
    }
    final curveStates = await curveStatesFuture;
    if (!mounted) return;
    setState(() {
      _curves = curves;
      _curveStates = curveStates;
      _globalEnabled = enabled;
      _loadProgress = 1.0;
      _loading = false;
    });
  }

  Future<void> _toggleCurve(CurveEntry entry, bool value) async {
    if (!_globalEnabled) return;
    if (value && entry.type == 'amount' && entry.staticValue == null) {
      bool isValidNumeric(String input) =>
          RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(input.trim());
      final controller = _valueControllers[entry.id];
      final valueText = controller?.text.trim();
      if (valueText == null || valueText.isEmpty) {
        final promptedValue = await _promptValue(context, entry.name);
        if (promptedValue == null) return;
        controller?.text = promptedValue;
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: promptedValue,
        );
      } else {
        if (!isValidNumeric(valueText)) {
          if (!mounted) return;
          showAtlasSnackBar(
            context,
            const SnackBar(content: Text('Enter a valid numeric value.')),
          );
          return;
        }
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: valueText,
        );
      }
    } else {
      await CurveTableService.setCurveEnabled(entry, value);
    }
    await _load();
  }

  Future<void> _updateCurveValue(CurveEntry entry, String newValue) async {
    if (!_globalEnabled) return;
    final enabled = _curveStates[entry.id]?.enabled ?? false;
    if (!enabled) return;
    final isValid = RegExp(
      r'^[+-]?(?:\d+\.?\d*|\.\d+)$',
    ).hasMatch(newValue.trim());
    if (!isValid) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Enter a valid numeric value.')),
      );
      return;
    }
    await CurveTableService.setCurveEnabled(entry, true, customValue: newValue);
    await _load();
  }

  Future<void> _addCustomCurve() async {
    final inputs = await _promptCustomCurves(
      context,
      _groupInfosForPrompt(_curves),
    );
    if (inputs == null || inputs.isEmpty) return;
    await CurveTableService.addCustomCurves(inputs);
    await _load();
  }

  Future<void> _importCurves() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    await CurveTableService.importFromIni(picked.files.single.path!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _curves.where((entry) {
      if (_search.trim().isEmpty) return true;
      final query = _search.toLowerCase();
      return entry.name.toLowerCase().contains(query) ||
          entry.key.toLowerCase().contains(query);
    }).toList();
    const menuKey = 'curvetables';

    return _BaseScreen(
      title: 'CurveTables',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            enabled: _globalEnabled,
            child: IconButton(
              tooltip: 'Import DefaultGame.ini',
              onPressed: _globalEnabled ? _importCurves : null,
              icon: const Icon(Icons.file_upload),
            ),
          ),
          _HoverScale(
            enabled: _globalEnabled,
            child: OutlinedButton.icon(
              onPressed: _globalEnabled ? _addCustomCurve : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Custom Curve'),
            ),
          ),
        ],
      ),
      child: _ScreenLoadGate(
        loading: _loading,
        transitionKey: 'curvetables',
        progress: _loadProgress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _menuEntrance(
              context,
              menuKey: menuKey,
              index: 0,
              child: TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(
                  labelText: 'Search CurveTables',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_globalEnabled)
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 1,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'CurveTables are disabled. Enable them in Modifications to edit.',
                  ),
                ),
              ),
            Expanded(
              child: _menuEntrance(
                context,
                menuKey: menuKey,
                index: 2,
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    _valueControllers.putIfAbsent(
                      entry.id,
                      () => TextEditingController(),
                    );
                    final resolvedState =
                        _curveStates[entry.id] ??
                        const _CurveEntryResolvedState();
                    final enabled = resolvedState.enabled;
                    final value = resolvedState.value;
                    final controller = _valueControllers[entry.id]!;
                    if (!enabled) {
                      if (controller.text.isNotEmpty) {
                        controller.text = '';
                      }
                    } else if (value != null && controller.text != value) {
                      controller.text = value;
                    }
                    final canEdit =
                        entry.type == 'amount' ||
                        (entry.type == 'static' && entry.staticValue == null);
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: enabled
                              ? const Color(0xFF6BE7FF).withOpacity(0.3)
                              : Colors.white10,
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _onSurface(context, 0.75),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (enabled && canEdit && value != null) ...[
                              const SizedBox(width: 12),
                              _CurveValueField(
                                controller: controller,
                                enabled: _globalEnabled,
                                onSubmitted: (newValue) =>
                                    _updateCurveValue(entry, newValue),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Switch(
                              value: enabled,
                              onChanged: _globalEnabled
                                  ? (value) => _toggleCurve(entry, value)
                                  : null,
                            ),
                            if (entry.isCustom) ...[
                              const SizedBox(width: 8),
                              _HoverScale(
                                child: IconButton(
                                  tooltip: 'Edit Curve',
                                  onPressed: () async {
                                    final updated =
                                        await _promptEditCustomCurve(
                                          context,
                                          entry,
                                          _groupInfosForPrompt(_curves),
                                        );
                                    if (updated == null) return;
                                    await CurveTableService.updateCustomCurve(
                                      entry.id,
                                      updated,
                                    );
                                    await _load();
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ),
                              _HoverScale(
                                child: IconButton(
                                  tooltip: 'Delete Curve',
                                  onPressed: () async {
                                    final confirm =
                                        await DataService._confirmDialog(
                                          context,
                                          'Delete custom curve "${entry.name}"?',
                                        );
                                    if (!confirm) return;
                                    await CurveTableService.deleteCustomCurve(
                                      entry.id,
                                    );
                                    await _load();
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  bool _loading = true;
  double _loadProgress = 0.0;
  bool _saveArenaPoints = false;
  bool _leaderboardLoading = true;
  List<ArenaEntry> _leaderboard = [];

  void _handleExternalToggleStateChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  @override
  void initState() {
    super.initState();
    userToggleStatesRevision.addListener(_handleExternalToggleStateChanged);
    _scheduleDeferredScreenLoad(this, _load);
  }

  @override
  void dispose() {
    userToggleStatesRevision.removeListener(_handleExternalToggleStateChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final snapshot = await _ArenaScreenCache.warm();
    if (!mounted) return;
    setState(() {
      _saveArenaPoints = snapshot.saveArenaPoints;
      _leaderboard = snapshot.leaderboard;
      _loadProgress = 1.0;
      _loading = false;
      _leaderboardLoading = false;
    });
  }

  void _showFullLeaderboard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    unawaited(
      _showBlurDialog<void>(
        context: context,
        builder: (dialogContext) =>
            _buildLeaderboardDialog(dialogContext, isDark),
      ),
    );
  }

  Widget _buildLeaderboardDialog(BuildContext context, bool isDark) {
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 500,
            height: 600,
            decoration: BoxDecoration(
              color: _dialogSurfaceColor(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _onSurface(context, 0.1)),
              boxShadow: [
                BoxShadow(
                  color: _dialogShadowColor(context),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Full Leaderboard',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          'Rank',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Name',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        'Points',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _leaderboard.length,
                    itemBuilder: (context, index) {
                      final entry = _leaderboard[index];
                      final rank = index + 1;

                      Color? rankColor;
                      FontWeight rankWeight = FontWeight.bold;
                      double rankSize = 14;

                      if (rank == 1) {
                        rankColor = const Color(0xFFD4AF37); // Gold
                        rankWeight = FontWeight.w900;
                        rankSize = 16;
                      } else if (rank == 2) {
                        rankColor = const Color(0xFFC0C0C0); // Silver
                        rankWeight = FontWeight.w900;
                        rankSize = 16;
                      } else if (rank == 3) {
                        rankColor = const Color(0xFFCD7F32); // Bronze
                        rankWeight = FontWeight.w900;
                        rankSize = 16;
                      } else {
                        rankColor = isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                (isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade100)
                                    .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 50,
                                child: Text(
                                  '#$rank',
                                  style: TextStyle(
                                    fontWeight: rankWeight,
                                    fontSize: rankSize,
                                    color: rankColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.accountId,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${entry.hype}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.orangeAccent
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSavePoints(bool value) async {
    final config = await ConfigService.load();
    await ConfigService.save(config.copyWith(saveArenaPoints: value));
    if (!mounted) return;
    setState(() => _saveArenaPoints = value);
  }

  @override
  Widget build(BuildContext context) {
    final top3 = _leaderboard.take(3).toList();
    final rest = _leaderboard.skip(3).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leaderboardTitleColor = isDark ? Colors.white70 : Colors.black87;
    final podiumBaselineColor = isDark
        ? Colors.grey.shade700
        : Colors.grey.shade300;
    final listRowColor = (isDark ? Colors.grey.shade800 : Colors.grey.shade100)
        .withOpacity(0.5);
    final listRankColor = isDark ? Colors.grey.shade300 : Colors.grey.shade600;
    final listNameColor = isDark ? Colors.white70 : Colors.black87;
    final listHypeColor = isDark ? Colors.orangeAccent : Colors.orange.shade700;
    final podiumNameColor = isDark ? Colors.white : Colors.black87;
    const menuKey = 'arena';

    return _BaseScreen(
      title: 'Arena',
      child: _ScreenLoadGate(
        loading: _loading,
        transitionKey: 'arena',
        progress: _loadProgress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _menuEntrance(
              context,
              menuKey: menuKey,
              index: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orangeAccent),
                    SizedBox(width: 8),
                    Text(
                      'Arena leaderboard and point saving is in development.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side: Save Arena Points
                  Expanded(
                    flex: 1,
                    child: _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 1,
                      child: SwitchListTile(
                        value: _saveArenaPoints,
                        onChanged: null,
                        title: const Text('Save Arena Points'),
                        subtitle: const Text(
                          'Persist player hype between sessions',
                        ),
                        secondary: const Tooltip(
                          message: 'Disabled',
                          child: Icon(Icons.info_outline, size: 20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Right side: Leaderboard Box
                  Expanded(
                    flex: 1,
                    child: _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 2,
                      child: Stack(
                        children: [
                          GlassPanel(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Text(
                                          'Leaderboard',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: leaderboardTitleColor,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _showFullLeaderboard(context),
                                        icon: const Icon(
                                          Icons.list_alt,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'View Full List',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Top 3 Podium
                                  Column(
                                    children: [
                                      SizedBox(
                                        height: 230,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            // 2nd Place
                                            Flexible(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  top3.length >= 2
                                                      ? _buildPodiumPillarContent(
                                                          entry: top3[1],
                                                          rank: 2,
                                                          medalColor:
                                                              const Color(
                                                                0xFFC0C0C0,
                                                              ),
                                                          nameColor:
                                                              podiumNameColor,
                                                        )
                                                      : _buildEmptyPodiumPillarContent(
                                                          rank: 2,
                                                        ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    width: 60,
                                                    height: 100,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFC0C0C0,
                                                      ),
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                            topLeft:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                            topRight:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFB0B0B0,
                                                        ),
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '#2',
                                                        style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          color: Colors
                                                              .grey
                                                              .shade200,
                                                          shadows: const [
                                                            Shadow(
                                                              blurRadius: 8,
                                                              color: Color(
                                                                0x99000000,
                                                              ),
                                                              offset: Offset(
                                                                0,
                                                                2,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // 1st Place
                                            Flexible(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  top3.isNotEmpty
                                                      ? _buildPodiumPillarContent(
                                                          entry: top3[0],
                                                          rank: 1,
                                                          medalColor:
                                                              const Color(
                                                                0xFFD4AF37,
                                                              ),
                                                          nameColor:
                                                              podiumNameColor,
                                                        )
                                                      : _buildEmptyPodiumPillarContent(
                                                          rank: 1,
                                                        ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    width: 60,
                                                    height: 140,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFD4AF37,
                                                      ),
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                            topLeft:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                            topRight:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFC89B2C,
                                                        ),
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '#1',
                                                        style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          color: Colors
                                                              .yellow
                                                              .shade100,
                                                          shadows: const [
                                                            Shadow(
                                                              blurRadius: 10,
                                                              color: Color(
                                                                0xCC000000,
                                                              ),
                                                              offset: Offset(
                                                                0,
                                                                2,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // 3rd Place
                                            Flexible(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  top3.length >= 3
                                                      ? _buildPodiumPillarContent(
                                                          entry: top3[2],
                                                          rank: 3,
                                                          medalColor:
                                                              const Color(
                                                                0xFFCD7F32,
                                                              ),
                                                          nameColor:
                                                              podiumNameColor,
                                                        )
                                                      : _buildEmptyPodiumPillarContent(
                                                          rank: 3,
                                                        ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    width: 60,
                                                    height: 80,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFCD7F32,
                                                      ),
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                            topLeft:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                            topRight:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFB56A2A,
                                                        ),
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '#3',
                                                        style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          color: Colors
                                                              .orange
                                                              .shade100,
                                                          shadows: const [
                                                            Shadow(
                                                              blurRadius: 8,
                                                              color: Color(
                                                                0x99000000,
                                                              ),
                                                              offset: Offset(
                                                                0,
                                                                2,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        height: 2,
                                        color: podiumBaselineColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Column headers for the list
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 40,
                                          child: Text(
                                            'Rank',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            child: Text(
                                              'Name',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade500,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'Points',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Scrollable list of remaining players
                                  Expanded(
                                    child: rest.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No more players',
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: rest.length,
                                            itemBuilder: (context, index) {
                                              final entry = rest[index];
                                              final rank = index + 4;
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 6,
                                                    ),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: listRowColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 40,
                                                        child: Text(
                                                          '#$rank',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                listRankColor,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                              ),
                                                          child: Text(
                                                            entry.accountId,
                                                            style: TextStyle(
                                                              color:
                                                                  listNameColor,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        '${entry.hype}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: listHypeColor,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Loading overlay with blur
                          if (_leaderboardLoading)
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedOpacity(
                                  opacity: _leaderboardLoading ? 1 : 0,
                                  duration: const Duration(milliseconds: 400),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 5,
                                      sigmaY: 5,
                                    ),
                                    child: Container(
                                      color: Colors.black.withOpacity(0.3),
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodiumPillar({
    required int rank,
    required ArenaEntry entry,
    required double height,
    required Color color,
    required Color medalColor,
  }) {
    final medalIcons = {
      1: Icons.emoji_events,
      2: Icons.military_tech,
      3: Icons.grade,
    };

    final displayName = entry.accountId.trim().isEmpty
        ? 'You'
        : entry.accountId.trim();
    final shortName = displayName.length > 14
        ? '${displayName.substring(0, 14)}…'
        : displayName;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(medalIcons[rank] ?? Icons.circle, color: medalColor, size: 20),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: SizedBox(
            width: 72,
            child: Text(
              shortName,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${entry.hype}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPodiumPillar({
    required int rank,
    required double height,
    required Color color,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
        const SizedBox(height: 4),
        const SizedBox(
          width: 60,
          child: Text(
            'Empty',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPodiumPillarContent({
    required ArenaEntry entry,
    required int rank,
    required Color medalColor,
    required Color nameColor,
  }) {
    final medalIcons = {
      1: Icons.emoji_events,
      2: Icons.military_tech,
      3: Icons.military_tech,
    };

    return Column(
      children: [
        Icon(medalIcons[rank] ?? Icons.circle, color: medalColor, size: 20),
        const SizedBox(height: 4),
        SizedBox(
          width: 70,
          child: Text(
            entry.accountId,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: nameColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${entry.hype}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: nameColor.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPodiumPillarContent({required int rank}) {
    final medalColor = rank == 2
        ? const Color(0xFFC0C0C0)
        : const Color(0xFFCD7F32);

    return Column(
      children: [
        Icon(Icons.military_tech, color: medalColor, size: 20),
        const SizedBox(height: 4),
        const SizedBox(
          width: 70,
          child: Text(
            'Empty',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}

class GameConfigurationScreen extends StatefulWidget {
  const GameConfigurationScreen({super.key});

  @override
  State<GameConfigurationScreen> createState() =>
      _GameConfigurationScreenState();
}

class _GameConfigurationScreenState extends State<GameConfigurationScreen> {
  bool _loading = true;
  double _loadProgress = 0.0;
  int _rufusStage = 1;
  int _waterLevel = 1;
  bool _useWaterStorm = false;
  bool _saving = false;
  _GameConfigPreview _preview = _GameConfigPreview.none;
  Timer? _saveDebounce;

  void _handleExternalToggleStateChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  @override
  void initState() {
    super.initState();
    userToggleStatesRevision.addListener(_handleExternalToggleStateChanged);
    _scheduleDeferredScreenLoad(this, _load);
  }

  @override
  void dispose() {
    userToggleStatesRevision.removeListener(_handleExternalToggleStateChanged);
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    if (!mounted) return;
    setState(() {
      _rufusStage = config.rufusStage;
      _waterLevel = config.waterLevel;
      _useWaterStorm = config.useWaterStorm;
      _preview = _GameConfigPreview.none;
      _loadProgress = 1.0;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = await ConfigService.load();
    final config = ConfigSettings(
      rufusStage: _rufusStage,
      waterLevel: _waterLevel,
      saveArenaPoints: existing.saveArenaPoints,
      useWaterStorm: _useWaterStorm,
      startBackendOnLaunch: existing.startBackendOnLaunch,
      backendInfiniteRenderEnabled: existing.backendInfiniteRenderEnabled,
      swapCooldownEnabled: existing.swapCooldownEnabled,
      disableBackendUpdateCheck: existing.disableBackendUpdateCheck,
      useDarkMode: existing.useDarkMode,
      backgroundImagePath: existing.backgroundImagePath,
      backgroundBlur: existing.backgroundBlur,
      backgroundParticlesOpacity: existing.backgroundParticlesOpacity,
      dialogBlurEnabled: existing.dialogBlurEnabled,
      startupAnimationEnabled: existing.startupAnimationEnabled,
      lastShownUpdateNotesVersion: existing.lastShownUpdateNotesVersion,
    );
    await ConfigService.save(config);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!_saving) {
        _save();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Game Configuration',
      child: _ScreenLoadGate(
        loading: _loading,
        transitionKey: 'game-configuration',
        progress: _loadProgress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const menuKey = 'game-configuration';
            final imagePath = _gameConfigImagePath();
            final controls = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _menuEntrance(
                  context,
                  menuKey: menuKey,
                  index: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitleWithTag(
                        title: 'Rufus Week Stage',
                        tag: 'v27.11',
                      ),
                      MouseRegion(
                        onEnter: (_) => setState(
                          () => _preview = _GameConfigPreview.rufusStage,
                        ),
                        child: Slider(
                          value: _rufusStage.toDouble(),
                          min: 1,
                          max: 4,
                          divisions: 3,
                          label: 'Stage $_rufusStage',
                          onChanged: (value) => setState(() {
                            _rufusStage = value.round();
                            _preview = _GameConfigPreview.rufusStage;
                            _scheduleSave();
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _menuEntrance(
                  context,
                  menuKey: menuKey,
                  index: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitleWithTag(
                        title: 'Water Level',
                        tag: 'v13.X',
                      ),
                      MouseRegion(
                        onEnter: (_) => setState(
                          () => _preview = _GameConfigPreview.waterLevel,
                        ),
                        child: Slider(
                          value: _waterLevel.toDouble(),
                          min: 1,
                          max: 7,
                          divisions: 6,
                          label: _waterLevel == 1
                              ? 'Level 1'
                              : 'Level $_waterLevel',
                          onChanged: (value) => setState(() {
                            _waterLevel = value.round();
                            _preview = _GameConfigPreview.waterLevel;
                            _scheduleSave();
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _menuEntrance(
                  context,
                  menuKey: menuKey,
                  index: 2,
                  child: MouseRegion(
                    onEnter: (_) => setState(
                      () => _preview = _GameConfigPreview.waterStorm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitleWithTag(
                          title: 'Water Storm',
                          tag: 'v12.61',
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _useWaterStorm,
                          onChanged: (value) => setState(() {
                            _useWaterStorm = value;
                            _preview = _GameConfigPreview.waterStorm;
                            _scheduleSave();
                          }),
                          title: const Text(
                            'Toggle the water storm in Chapter 2 Season 2',
                          ),
                          subtitle: const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
            final isDefault = _preview == _GameConfigPreview.none;
            final preview = _GameConfigPreviewImage(
              imagePath: imagePath,
              switchKey: '${_preview.name}::$imagePath',
              isDefault: isDefault,
            );
            final isWide = constraints.maxWidth >= 920;
            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 3,
                    child: preview,
                  ),
                  const SizedBox(height: 16),
                  controls,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: controls),
                const SizedBox(width: 28),
                Expanded(
                  child: _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 3,
                    child: preview,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _gameConfigImagePath() {
    final base = joinPath([getBackendRoot(), 'public', 'gameconfig']);
    switch (_preview) {
      case _GameConfigPreview.rufusStage:
        return joinPath([base, 'stage$_rufusStage.webp']);
      case _GameConfigPreview.waterLevel:
        for (var level = _waterLevel; level >= 1; level--) {
          final candidate = joinPath([base, 'waterlevel$level.webp']);
          if (File(candidate).existsSync()) {
            return candidate;
          }
        }
        return joinPath([base, 'default.webp']);
      case _GameConfigPreview.waterStorm:
        return joinPath([base, 'waterstorm.webp']);
      default:
        return joinPath([base, 'default.webp']);
    }
  }
}

enum _GameConfigPreview { none, rufusStage, waterLevel, waterStorm }

class _GameConfigPreviewImage extends StatelessWidget {
  const _GameConfigPreviewImage({
    required this.imagePath,
    required this.switchKey,
    required this.isDefault,
  });

  final String imagePath;
  final String switchKey;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = _cachedFileImageProvider(imagePath);
    final image = provider == null
        ? const SizedBox.expand()
        : RepaintBoundary(
            child: Image(
              image: provider,
              key: ValueKey(switchKey),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              reverseDuration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              layoutBuilder: (currentChild, previousChildren) {
                final currentKey = currentChild?.key;
                final filteredPrevious = previousChildren
                    .where((child) => child.key != currentKey)
                    .toList();
                return SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ...filteredPrevious,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                );
              },
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: ValueKey(switchKey),
                child: isDefault
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                        child: image,
                      )
                    : image,
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _onSurface(context, isDark ? 0.2 : 0.1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class CurveGroup {
  const CurveGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.keywords,
    this.imageName,
    this.imagePath,
    this.isCustom = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<String> keywords;
  final String? imageName;
  final String? imagePath;
  final bool isCustom;

  bool matches(CurveEntry entry) {
    if (isCustom || (entry.isCustom && entry.groupId == id)) {
      return entry.groupId == id;
    }
    final name = entry.name.toLowerCase();
    final key = entry.key.toLowerCase();
    return keywords.any(
      (keyword) => name.contains(keyword) || key.contains(keyword),
    );
  }
}

class _CurveEntryResolvedState {
  const _CurveEntryResolvedState({this.enabled = false, this.value});

  final bool enabled;
  final String? value;
}

class _CurveValueField extends StatelessWidget {
  const _CurveValueField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF6BE7FF);
    final fillColor = isDark
        ? const Color(0xFF141A24).withOpacity(0.65)
        : const Color(0xFFF7F9FC).withOpacity(0.65);
    final borderColor = _onSurface(context, enabled ? 0.14 : 0.08);
    final focusedBorderColor = accent.withOpacity(isDark ? 0.42 : 0.34);
    final textColor = enabled
        ? _onSurface(context, 0.92)
        : _onSurface(context, 0.42);

    return SizedBox(
      width: 138,
      child: TextField(
        controller: controller,
        enabled: enabled,
        onSubmitted: onSubmitted,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
        ],
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        cursorColor: accent,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: fillColor,
          hintText: 'Value',
          hintStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _onSurface(context, 0.34),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: borderColor),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _onSurface(context, 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: focusedBorderColor, width: 1.3),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: borderColor),
          ),
        ),
      ),
    );
  }
}

class _CurveEntryTile extends StatelessWidget {
  const _CurveEntryTile({
    required this.entry,
    required this.enabled,
    required this.resolvedState,
    required this.valueController,
    required this.onToggle,
    required this.onSubmit,
    this.onEdit,
    this.onDelete,
  });

  final CurveEntry entry;
  final bool enabled;
  final _CurveEntryResolvedState resolvedState;
  final TextEditingController valueController;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final canEdit =
        entry.type == 'amount' ||
        (entry.type == 'static' && entry.staticValue == null);
    final isEnabled = resolvedState.enabled;
    final value = resolvedState.value;
    if (!isEnabled) {
      if (valueController.text.isNotEmpty) {
        valueController.text = '';
      }
    } else if (value != null && valueController.text != value) {
      valueController.text = value;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? const Color(0xFF6BE7FF).withOpacity(0.3)
              : _onSurface(context, 0.12),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 12,
                      color: _onSurface(context, 0.75),
                    ),
                  ),
                ],
              ),
            ),
            if (isEnabled && canEdit) ...[
              const SizedBox(width: 12),
              _CurveValueField(
                controller: valueController,
                enabled: enabled,
                onSubmitted: onSubmit,
              ),
            ],
            const SizedBox(width: 8),
            Switch(value: isEnabled, onChanged: enabled ? onToggle : null),
            if (entry.isCustom) ...[
              const SizedBox(width: 8),
              _HoverScale(
                child: IconButton(
                  tooltip: 'Edit Curve',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              _HoverScale(
                child: IconButton(
                  tooltip: 'Delete Curve',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataTableSettingTile extends StatelessWidget {
  const _DataTableSettingTile({
    required this.title,
    required this.subtitle,
    required this.isEnabled,
    required this.enabled,
    required this.onToggle,
    this.showValueField = false,
    this.valueController,
    this.onSubmitted,
  });

  final String title;
  final String subtitle;
  final bool isEnabled;
  final bool enabled;
  final bool showValueField;
  final TextEditingController? valueController;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? const Color(0xFF6BE7FF).withOpacity(0.3)
              : _onSurface(context, 0.12),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _onSurface(context, 0.75),
                    ),
                  ),
                ],
              ),
            ),
            if (showValueField &&
                valueController != null &&
                onSubmitted != null) ...[
              const SizedBox(width: 12),
              _CurveValueField(
                controller: valueController!,
                enabled: enabled,
                onSubmitted: onSubmitted!,
              ),
            ],
            const SizedBox(width: 8),
            Switch(value: isEnabled, onChanged: enabled ? onToggle : null),
          ],
        ),
      ),
    );
  }
}

class _DataTableActionTile extends StatelessWidget {
  const _DataTableActionTile({
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.enabled,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final bool isActive;
  final bool enabled;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFF6BE7FF).withOpacity(0.3)
              : _onSurface(context, 0.12),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _onSurface(context, 0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HoverScale(
              child: OutlinedButton.icon(
                onPressed: enabled ? onPressed : null,
                icon: const Icon(Icons.tune),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Data Management',
      child: const DataManagementPanel(),
    );
  }
}

class DataManagementPanel extends StatefulWidget {
  const DataManagementPanel({super.key});

  @override
  State<DataManagementPanel> createState() => _DataManagementPanelState();
}

class _DataManagementPanelState extends State<DataManagementPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _openBackendFolder() async {
    final backendRoot = getBackendRoot();
    if (!Directory(backendRoot).existsSync()) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Backend folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [backendRoot], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Failed to open backend folder.')),
      );
    }
  }

  Future<void> _openExportsFolder() async {
    final exportsPath = joinPath([getBackendRoot(), 'exports']);
    if (!Directory(exportsPath).existsSync()) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Exports folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [exportsPath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Failed to open exports folder.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const menuKey = 'data-management-panel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _menuEntrance(
          context,
          menuKey: menuKey,
          index: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(title: 'Files'),
              ListTile(
                title: const Text('View Internal Files'),
                subtitle: const Text('Open ATLAS Backend folder on disk'),
                trailing: _HoverScale(
                  enabled: !_busy,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _openBackendFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Open Exports Folder'),
                subtitle: const Text('View your Exported Data on Disk'),
                trailing: _HoverScale(
                  enabled: !_busy,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _openExportsFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _menuEntrance(
          context,
          menuKey: menuKey,
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(title: 'Export & Import'),
              ListTile(
                title: const Text('Export Backend Settings'),
                subtitle: const Text(
                  'Exports all important data in ATLAS Backend for reimporting or transfer to the folder exports/',
                ),
                trailing: _HoverScale(
                  enabled: !_busy,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => DataService.exportData(context)),
                    child: const Text('Export'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Import Backend Settings'),
                subtitle: const Text(
                  'Load exported data stored within ATLAS Backend from exports/',
                ),
                trailing: _HoverScale(
                  enabled: !_busy,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => DataService.importData(context)),
                    child: const Text('Import'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Clear Exported Data'),
                subtitle: const Text(
                  'Completely clear all of your exported data contained in the exports/ folder',
                ),
                trailing: _HoverScale(
                  enabled: !_busy,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => DataService.clearExportedData(context),
                          ),
                    child: const Text('Clear'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _menuEntrance(
          context,
          menuKey: menuKey,
          index: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(title: 'Reset'),
              ListTile(
                title: const Text('Clear Backend Data'),
                subtitle: const Text(
                  'Clear All ATLAS Backend data as if you were starting fresh',
                ),
                trailing: _HoverScale(
                  enabled: !_busy,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy
                        ? null
                        : () =>
                              _run(() => DataService.clearBackendData(context)),
                    child: const Text('Clear'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _loading = true;
  double _loadProgress = 0.0;
  List<ProfileSummary> _profiles = [];
  List<ProfilePreset> _presets = [];
  bool _hasAnyUsers = false;
  String? _selectedProfile;
  String? _selectedPreset;
  Map<String, String> _lastAppliedPresetByUser = {};

  @override
  void initState() {
    super.initState();
    _scheduleDeferredScreenLoad(this, () => _load(forceRefresh: true));
  }

  Future<void> _load({bool forceRefresh = true}) async {
    try {
      final snapshot = await _ProfilesScreenCache.warm(
        forceRefresh: forceRefresh,
      );
      final profiles = snapshot.profiles;
      final presets = snapshot.presets;
      final hasAnyUsers = snapshot.hasAnyUsers;
      final uiState = snapshot.uiState;
      final profileIds = profiles.map((profile) => profile.accountId).toSet();
      final presetFolders = presets.map((preset) => preset.folder).toSet();
      final savedPresetByUser = <String, String>{};
      uiState.lastAppliedPresetByUser.forEach((accountId, presetFolder) {
        if (accountId.trim().isEmpty || presetFolder.trim().isEmpty) return;
        if (!profileIds.contains(accountId)) return;
        savedPresetByUser[accountId] = presetFolder;
      });

      String? resolvedSelectedProfile = _selectedProfile;
      if (resolvedSelectedProfile == null ||
          !profileIds.contains(resolvedSelectedProfile)) {
        final savedSelectedProfile = uiState.lastSelectedProfile;
        if (savedSelectedProfile != null &&
            profileIds.contains(savedSelectedProfile)) {
          resolvedSelectedProfile = savedSelectedProfile;
        } else {
          resolvedSelectedProfile = profiles.isNotEmpty
              ? profiles.first.accountId
              : null;
        }
      }

      String? resolvedSelectedPreset;
      if (resolvedSelectedProfile != null) {
        final mappedPreset = savedPresetByUser[resolvedSelectedProfile];
        if (mappedPreset != null && presetFolders.contains(mappedPreset)) {
          resolvedSelectedPreset = mappedPreset;
        }
      }
      if (resolvedSelectedPreset == null &&
          _selectedPreset != null &&
          presetFolders.contains(_selectedPreset)) {
        resolvedSelectedPreset = _selectedPreset;
      }
      resolvedSelectedPreset ??= presets.isNotEmpty
          ? presets.first.folder
          : null;

      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _presets = presets;
        _hasAnyUsers = hasAnyUsers;
        _selectedProfile = resolvedSelectedProfile;
        _selectedPreset = resolvedSelectedPreset;
        _lastAppliedPresetByUser = savedPresetByUser;
        _loadProgress = 1.0;
        _loading = false;
      });
      unawaited(_persistProfilesUiState());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadProgress = 1.0;
        _loading = false;
        _hasAnyUsers = false;
      });
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to load profiles: $error')),
      );
    }
  }

  String? _resolvedPresetForUser(String? accountId) {
    if (accountId == null) return null;
    final presetFolder = _lastAppliedPresetByUser[accountId];
    if (presetFolder == null) return null;
    return _presets.any((preset) => preset.folder == presetFolder)
        ? presetFolder
        : null;
  }

  void _selectProfile(String? accountId) {
    final mappedPreset = _resolvedPresetForUser(accountId);
    setState(() {
      _selectedProfile = accountId;
      if (mappedPreset != null) {
        _selectedPreset = mappedPreset;
      } else if (_presets.isNotEmpty) {
        _selectedPreset = _presets.first.folder;
      } else {
        _selectedPreset = null;
      }
    });
    unawaited(_persistProfilesUiState());
  }

  Future<void> _persistProfilesUiState() async {
    try {
      await ProfilesUiStateService.save(
        ProfilesUiState(
          lastSelectedProfile: _selectedProfile,
          lastAppliedPresetByUser: _lastAppliedPresetByUser,
        ),
      );
    } catch (_) {}
  }

  String? _validateNewUserName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'User name is required.';
    }
    if (trimmed == '.' || trimmed == '..') {
      return 'That name is not allowed.';
    }
    if (trimmed.startsWith('.')) {
      return 'User name cannot start with a dot.';
    }
    if (RegExp(r'[<>:"/\\|?*]').hasMatch(trimmed)) {
      return 'User name contains invalid characters.';
    }
    if (trimmed.endsWith(' ') || trimmed.endsWith('.')) {
      return 'User name cannot end with a space or dot.';
    }
    if (trimmed.toLowerCase() == 'host') {
      return 'The name "host" is reserved.';
    }
    return null;
  }

  Future<_CreateUserResult?> _showCreateUserDialog() async {
    if (_presets.isEmpty) {
      if (!mounted) return null;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('No presets found.')),
      );
      return null;
    }

    final controller = TextEditingController();
    String? selectedPreset =
        _presets.any((preset) => preset.folder == _selectedPreset)
        ? _selectedPreset
        : _presets.first.folder;
    String? errorText;

    return _showBlurDialog<_CreateUserResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create User'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'User name',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedPreset,
                  decoration: const InputDecoration(
                    labelText: 'Preset',
                    border: OutlineInputBorder(),
                  ),
                  items: _presets
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset.folder,
                          child: _PresetLabel(
                            name: preset.name,
                            tag: preset.versionTag,
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (context) => _presets
                      .map(
                        (preset) => _PresetLabel(
                          name: preset.name,
                          tag: preset.versionTag,
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => selectedPreset = value ?? _presets.first.folder,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            _HoverScale(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            _HoverScale(
              child: ElevatedButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  final validationError = _validateNewUserName(name);
                  if (validationError != null) {
                    setState(() => errorText = validationError);
                    return;
                  }
                  if (await ProfileService.userExists(name)) {
                    if (!context.mounted) return;
                    setState(() => errorText = 'That user already exists.');
                    return;
                  }
                  final presetFolder = selectedPreset ?? _presets.first.folder;
                  if (!context.mounted) return;
                  Navigator.pop(
                    context,
                    _CreateUserResult(
                      accountId: name,
                      presetFolder: presetFolder,
                    ),
                  );
                },
                child: const Text('Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createUser() async {
    final result = await _showCreateUserDialog();
    if (result == null) return;
    try {
      await ProfileService.createUser(
        result.accountId,
        presetFolder: result.presetFolder,
      );
      await _load();
      if (!mounted) return;
      setState(() {
        _selectedProfile = result.accountId;
        _selectedPreset = result.presetFolder;
        _lastAppliedPresetByUser[result.accountId] = result.presetFolder;
      });
      unawaited(_persistProfilesUiState());
      showAtlasSnackBar(
        context,
        SnackBar(
          content: Text(
            'Created "${result.accountId}" with preset "${result.presetFolder}".',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to create user: $error')),
      );
    }
  }

  Future<void> _applyPreset() async {
    final profileId = _selectedProfile;
    final presetFolder = _selectedPreset;
    if (profileId == null || presetFolder == null) return;
    ProfilePreset? preset;
    for (final entry in _presets) {
      if (entry.folder == presetFolder) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      showAtlasSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Selected preset no longer exists. Refresh and try again.',
          ),
        ),
      );
      return;
    }
    final confirm = await DataService._confirmDialog(
      context,
      'Replace profile_athena.json for "$profileId" with preset "${preset.displayName}"?',
    );
    if (!confirm) return;
    try {
      await ProfileService.applyPreset(profileId, presetFolder);
      if (!mounted) return;
      setState(() {
        _lastAppliedPresetByUser[profileId] = presetFolder;
      });
      unawaited(_persistProfilesUiState());
      showAtlasSnackBar(
        context,
        SnackBar(
          content: Text('Applied "${preset.displayName}" to $profileId'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to apply preset: $error')),
      );
    }
  }

  Future<void> _applyPresetToAll() async {
    final presetFolder = _selectedPreset;
    if (presetFolder == null) return;
    ProfilePreset? preset;
    for (final entry in _presets) {
      if (entry.folder == presetFolder) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      showAtlasSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Selected preset no longer exists. Refresh and try again.',
          ),
        ),
      );
      return;
    }
    final confirm = await DataService._confirmDialog(
      context,
      'Replace profile_athena.json for all users with preset "${preset.displayName}"?',
    );
    if (!confirm) return;
    try {
      final applied = await ProfileService.applyPresetToAll(presetFolder);
      if (!mounted) return;
      setState(() {
        for (final profile in _profiles) {
          _lastAppliedPresetByUser[profile.accountId] = presetFolder;
        }
      });
      unawaited(_persistProfilesUiState());
      showAtlasSnackBar(
        context,
        SnackBar(
          content: Text(
            'Applied "${preset.displayName}" to $applied profile(s).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(
          content: Text('Failed to apply preset to all profiles: $error'),
        ),
      );
    }
  }

  Future<void> _createCustomPreset() async {
    final nameController = TextEditingController();
    final versionController = TextEditingController();
    final filePathController = TextEditingController();
    String? pickedFilePath;
    String? nameError;
    String? fileError;

    final result = await _showBlurDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create Profile Preset'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Preset name',
                    hintText: 'e.g. My Custom Build',
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: versionController,
                  decoration: const InputDecoration(
                    labelText: 'Version tag (optional)',
                    hintText: 'e.g. v14.40',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: filePathController,
                        style: TextStyle(color: _onSurface(context, 0.92)),
                        onChanged: (value) {
                          final trimmed = value.trim();
                          if (trimmed.isEmpty) {
                            setState(() {
                              pickedFilePath = null;
                              fileError = null;
                            });
                            return;
                          }
                          final name = trimmed
                              .split(RegExp(r'[\\/]'))
                              .last
                              .toLowerCase();
                          if (name != 'profile_athena.json' &&
                              name != 'athena.json') {
                            setState(() {
                              pickedFilePath = null;
                              fileError =
                                  'File must be profile_athena.json or athena.json.';
                            });
                          } else {
                            setState(() {
                              pickedFilePath = trimmed;
                              fileError = null;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Select profile_athena.json',
                          hintStyle: TextStyle(
                            color: _onSurface(context, 0.48),
                          ),
                          prefixIcon: Icon(
                            Icons.description_rounded,
                            color: _onSurface(context, 0.78),
                          ),
                          filled: true,
                          fillColor: _adaptiveScrimColor(
                            context,
                            darkAlpha: 0.1,
                            lightAlpha: 0.2,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _onSurface(context, 0.12),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondary.withValues(alpha: 0.95),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _HoverScale(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await FilePicker.platform.pickFiles(
                            dialogTitle:
                                'Select profile_athena.json or athena.json',
                            type: FileType.custom,
                            allowedExtensions: ['json'],
                          );
                          if (picked == null ||
                              picked.files.single.path == null) {
                            return;
                          }
                          final fileName = picked.files.single.name
                              .toLowerCase();
                          if (fileName != 'profile_athena.json' &&
                              fileName != 'athena.json') {
                            setState(() {
                              fileError =
                                  'File must be profile_athena.json or athena.json.';
                            });
                            return;
                          }
                          setState(() {
                            pickedFilePath = picked.files.single.path!;
                            filePathController.text = picked.files.single.path!;
                            fileError = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          fixedSize: const Size(86, 42),
                          foregroundColor: _onSurface(context, 0.92),
                          backgroundColor: _adaptiveScrimColor(
                            context,
                            darkAlpha: 0.08,
                            lightAlpha: 0.16,
                          ),
                          side: BorderSide(color: _onSurface(context, 0.14)),
                        ),
                        child: const Text('Browse'),
                      ),
                    ),
                  ],
                ),
                if (fileError != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      fileError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _HoverScale(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HoverScale(
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            setState(() => nameError = 'Name cannot be empty.');
                            return;
                          }
                          if (pickedFilePath == null) {
                            setState(
                              () => fileError = 'Please select a JSON file.',
                            );
                            return;
                          }
                          setState(() {
                            nameError = null;
                            fileError = null;
                          });
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        },
                        style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          fixedSize: const Size(86, 42),
                        ),
                        child: const Text('Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: const [],
          actionsPadding: EdgeInsets.zero,
        ),
      ),
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final versionTag = versionController.text.trim();

    try {
      await ProfileService.createCustomPreset(
        name: name,
        sourceFilePath: pickedFilePath!,
        versionTag: versionTag.isNotEmpty ? versionTag : null,
      );
      _ProfilesScreenCache._snapshot = null;
      await _load(forceRefresh: true);
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Created preset "$name".')),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to create preset: $error')),
      );
    }
  }

  Future<void> _deleteCustomPreset() async {
    final customConfig = await ProfileService._loadCustomPresetsConfig();
    final customList = customConfig['presets'] as List<dynamic>? ?? [];
    if (customList.isEmpty) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('No custom presets to delete.')),
      );
      return;
    }

    final customPresets = <ProfilePreset>[];
    for (final p in customList) {
      final map = p as Map<String, dynamic>;
      customPresets.add(
        ProfilePreset(
          name: map['name'] as String? ?? map['folder'] as String? ?? '',
          folder: map['folder'] as String? ?? '',
          versionTag: map['versionTag'] as String?,
        ),
      );
    }

    String? selectedFolder = customPresets.first.folder;

    final confirmed = await _showBlurDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete Custom Preset'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedFolder,
                  decoration: const InputDecoration(
                    labelText: 'Custom preset',
                    border: OutlineInputBorder(),
                  ),
                  items: customPresets
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset.folder,
                          child: _PresetLabel(
                            name: preset.name,
                            tag: preset.versionTag,
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (context) => customPresets
                      .map(
                        (preset) => _PresetLabel(
                          name: preset.name,
                          tag: preset.versionTag,
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => selectedFolder = value),
                ),
                const SizedBox(height: 8),
                Text(
                  'This will permanently delete the preset folder and its profile.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                ),
              ],
            ),
          ),
          actions: [
            _HoverScale(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            _HoverScale(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedFolder == null) return;

    final presetName = customPresets
        .firstWhere(
          (p) => p.folder == selectedFolder,
          orElse: () =>
              ProfilePreset(name: selectedFolder!, folder: selectedFolder!),
        )
        .name;

    try {
      await ProfileService.deleteCustomPreset(selectedFolder!);
      _ProfilesScreenCache._snapshot = null;
      if (_selectedPreset == selectedFolder) {
        _selectedPreset = null;
      }
      await _load(forceRefresh: true);
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Deleted preset "$presetName".')),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to delete preset: $error')),
      );
    }
  }

  Future<void> _deleteProfile() async {
    final profileId = _selectedProfile;
    if (profileId == null) return;

    // Check which folders exist
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles', profileId]),
    );
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings', profileId]),
    );
    final profileFolderExists = await profilesDir.exists();
    final clientSettingsFolderExists = await clientSettingsDir.exists();

    bool deleteProfile = profileFolderExists;
    bool deleteClientSettings = clientSettingsFolderExists;

    if (!mounted) return;
    final result = await _showBlurDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: Text('Delete profile "$profileId"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select what to delete:'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteProfile,
                onChanged: profileFolderExists
                    ? (value) => setState(() => deleteProfile = value ?? true)
                    : null,
                title: const Text('User Profile'),
                subtitle: const Text(
                  'profile_athena.json and related profile data',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: deleteClientSettings,
                onChanged: clientSettingsFolderExists
                    ? (value) =>
                          setState(() => deleteClientSettings = value ?? true)
                    : null,
                title: const Text('ClientSettings'),
                subtitle: const Text('Game settings and preferences'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(stateContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: (deleteProfile || deleteClientSettings)
                  ? () => Navigator.of(stateContext).pop({
                      'profile': deleteProfile,
                      'settings': deleteClientSettings,
                    })
                  : null,
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await ProfileService.deleteProfile(
        profileId,
        deleteProfile: result['profile']!,
        deleteClientSettings: result['settings']!,
      );
      await _load();
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Deleted profile "$profileId".')),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to delete profile: $error')),
      );
    }
  }

  Future<void> _deleteAllProfiles() async {
    bool deleteProfiles = true;
    bool deleteClientSettings = true;

    final result = await _showBlurDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: const Text('Delete ALL profiles?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select what to delete for all users:'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteProfiles,
                onChanged: (value) =>
                    setState(() => deleteProfiles = value ?? true),
                title: const Text('User Profiles'),
                subtitle: const Text(
                  'All profile_athena.json files and related data',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: deleteClientSettings,
                onChanged: (value) =>
                    setState(() => deleteClientSettings = value ?? true),
                title: const Text('ClientSettings'),
                subtitle: const Text('All game settings and preferences'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(stateContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: (deleteProfiles || deleteClientSettings)
                  ? () => Navigator.of(stateContext).pop({
                      'profiles': deleteProfiles,
                      'settings': deleteClientSettings,
                    })
                  : null,
              child: const Text(
                'Delete All',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await ProfileService.deleteAllProfiles(
        deleteProfiles: result['profiles']!,
        deleteClientSettings: result['settings']!,
      );
      await _load();
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Deleted all profiles.')),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to delete all profiles: $error')),
      );
    }
  }

  Future<void> _openClientSettingsFolder(String accountId) async {
    final clientSettingsPath = joinPath([
      getBackendRoot(),
      'static',
      'ClientSettings',
      accountId,
    ]);
    if (!Directory(clientSettingsPath).existsSync()) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('ClientSettings folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [clientSettingsPath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Failed to open Client Settings folder.')),
      );
    }
  }

  Future<void> _openProfileFolder(String accountId) async {
    final profilePath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
    ]);
    if (!Directory(profilePath).existsSync()) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Profile folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [profilePath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Failed to open Profile folder.')),
      );
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDir = Directory(
          joinPath([
            destination.path,
            entity.path.split(Platform.pathSeparator).last,
          ]),
        );
        await newDir.create(recursive: true);
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        final newFile = File(
          joinPath([
            destination.path,
            entity.path.split(Platform.pathSeparator).last,
          ]),
        );
        await entity.copy(newFile.path);
      }
    }
  }

  Future<void> _exportUserSettings(String accountId) async {
    bool exportProfile = true;
    bool exportClientSettings = true;

    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles', accountId]),
    );
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings', accountId]),
    );
    final profileFolderExists = await profilesDir.exists();
    final clientSettingsFolderExists = await clientSettingsDir.exists();

    if (!profileFolderExists && !clientSettingsFolderExists) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        const SnackBar(
          content: Text('No profile or client settings found to export.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final result = await _showBlurDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: Text('Export settings for "$accountId"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select what to export:'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: exportProfile,
                onChanged: profileFolderExists
                    ? (value) => setState(() => exportProfile = value ?? true)
                    : null,
                title: const Text('User Profile'),
                subtitle: const Text(
                  'profile_athena.json and related profile data',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: exportClientSettings,
                onChanged: clientSettingsFolderExists
                    ? (value) =>
                          setState(() => exportClientSettings = value ?? true)
                    : null,
                title: const Text('ClientSettings'),
                subtitle: const Text('Game settings and preferences'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(stateContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: (exportProfile || exportClientSettings)
                  ? () => Navigator.of(stateContext).pop({
                      'profile': exportProfile,
                      'settings': exportClientSettings,
                    })
                  : null,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Export'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      final backendRoot = getBackendRoot();
      final zipFileName =
          '${accountId}_export_${DateTime.now().millisecondsSinceEpoch}.zip';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Export Zip',
        fileName: zipFileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (savePath == null) return;

      final tempDir = Directory.systemTemp.createTempSync('atlas_export_');
      final exportDir = Directory(joinPath([tempDir.path, accountId]));
      await exportDir.create();

      if (result['profile']!) {
        final profileSource = Directory(
          joinPath([backendRoot, 'static', 'profiles', accountId]),
        );
        final profileDest = Directory(
          joinPath([exportDir.path, 'profiles', accountId]),
        );
        await profileDest.create(recursive: true);
        await _copyDirectory(profileSource, profileDest);
      }

      if (result['settings']!) {
        final settingsSource = Directory(
          joinPath([backendRoot, 'static', 'ClientSettings', accountId]),
        );
        final settingsDest = Directory(
          joinPath([exportDir.path, 'ClientSettings', accountId]),
        );
        await settingsDest.create(recursive: true);
        await _copyDirectory(settingsSource, settingsDest);
      }

      final zipPath = savePath;

      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Add-Type -AssemblyName System.IO.Compression.FileSystem; '
            '[System.IO.Compression.ZipFile]::CreateFromDirectory(\'${exportDir.path}\', \'$zipPath\')',
      ]);

      await tempDir.delete(recursive: true);

      if (!mounted) return;
      showAtlasSnackBar(context, SnackBar(content: Text('Exported: $zipPath')));
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to export settings: $error')),
      );
    }
  }

  Future<void> _importUserSettingsZip() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import User Settings (zip)',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final zipPath = picked.files.single.path!;

    try {
      final backendRoot = getBackendRoot();
      final input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeBuffer(input);

      final matched = <String>{};
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        final segments = name.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length < 3) continue;

        String? accountId;
        String? category;
        int relativeStart = 0;

        if (segments[0] == 'profiles' || segments[0] == 'ClientSettings') {
          category = segments[0];
          accountId = segments[1];
          relativeStart = 2;
        } else if (segments.length >= 4 &&
            (segments[1] == 'profiles' || segments[1] == 'ClientSettings')) {
          accountId = segments[0];
          category = segments[1];
          if (segments[2] != accountId) continue;
          relativeStart = 3;
        }

        if (accountId == null || category == null) continue;

        String? baseDir;
        if (category == 'profiles') {
          baseDir = joinPath([backendRoot, 'static', 'profiles', accountId]);
        } else if (category == 'ClientSettings') {
          baseDir = joinPath([
            backendRoot,
            'static',
            'ClientSettings',
            accountId,
          ]);
        } else {
          continue;
        }

        final relative = segments.sublist(relativeStart).join('/');
        if (relative.isEmpty) continue;
        final outPath = joinPath([baseDir, relative]);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        final data = file.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);
        matched.add(accountId);
      }

      if (!mounted) return;
      if (matched.isEmpty) {
        showAtlasSnackBar(
          context,
          const SnackBar(content: Text('No valid profiles found in zip.')),
        );
        return;
      }

      await _load();
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Imported ${matched.length} profile(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      showAtlasSnackBar(
        context,
        SnackBar(content: Text('Failed to import zip: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final presetItems = {
      for (final preset in _presets) preset.folder: preset,
    }.values.toList();
    final profileItems = {
      for (final profile in _profiles) profile.accountId: profile,
    }.values.toList();
    final presetValue = presetItems.any((p) => p.folder == _selectedPreset)
        ? _selectedPreset
        : null;
    final profileValue =
        profileItems.any((p) => p.accountId == _selectedProfile)
        ? _selectedProfile
        : null;
    const menuKey = 'users';
    return _BaseScreen(
      title: 'Users',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            enabled: !_loading,
            child: IconButton(
              tooltip: 'Create user',
              onPressed: _loading ? null : _createUser,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ),
          const SizedBox(width: 8),
          _HoverScale(
            enabled: !_loading,
            child: IconButton(
              tooltip: 'Refresh users',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      child: _ScreenLoadGate(
        loading: _loading,
        transitionKey: 'users',
        progress: _loadProgress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 0,
                    child: _SectionTitle(title: 'Users (${_profiles.length})'),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 1,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: _profiles.isEmpty
                            ? const Center(child: Text('No users found.'))
                            : ListView.separated(
                                itemCount: _profiles.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Colors.white12,
                                ),
                                itemBuilder: (context, index) {
                                  final profile = _profiles[index];
                                  final selected =
                                      profile.accountId == _selectedProfile;
                                  return GestureDetector(
                                    onSecondaryTapDown: (details) {
                                      showMenu(
                                        context: context,
                                        position: RelativeRect.fromLTRB(
                                          details.globalPosition.dx,
                                          details.globalPosition.dy,
                                          details.globalPosition.dx,
                                          details.globalPosition.dy,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        items: [
                                          PopupMenuItem(
                                            child: const Text(
                                              'Open Client Settings Folder',
                                            ),
                                            onTap: () =>
                                                _openClientSettingsFolder(
                                                  profile.accountId,
                                                ),
                                          ),
                                          PopupMenuItem(
                                            child: const Text(
                                              'Open Profile Folder',
                                            ),
                                            onTap: () => _openProfileFolder(
                                              profile.accountId,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            child: const Text(
                                              'Export User Settings',
                                            ),
                                            onTap: () => _exportUserSettings(
                                              profile.accountId,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                    child: ListTile(
                                      selected: selected,
                                      selectedTileColor: Colors.white10,
                                      title: Text(profile.accountId),
                                      subtitle: Text(
                                        profile.hasAthena
                                            ? 'profile_athena.json found'
                                            : 'Missing profile_athena.json',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                        ),
                                      ),
                                      trailing: selected
                                          ? const Icon(
                                              Icons.check_circle,
                                              color: Colors.greenAccent,
                                            )
                                          : null,
                                      onTap: () =>
                                          _selectProfile(profile.accountId),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 2,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.flash_on_rounded,
                            color: const Color(0xFF7EE081),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Level and Currency',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          _HoverScale(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  _buildRoute(
                                    UserValuesScreen(
                                      initialProfile: _selectedProfile,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF7EE081,
                                ).withOpacity(0.15),
                                foregroundColor: const Color(0xFF7EE081),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit User Values'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 3,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SectionTitle(title: 'Custom Cosmetic Presets'),
                        const SizedBox(width: 8),
                        _HoverScale(
                          scale: 1.08,
                          child: Tooltip(
                            message: 'Info',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    _showCustomCosmeticPresetsInfoDialog(
                                      context,
                                    ),
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _onSurface(context, 0.06),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _onSurface(context, 0.14),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.help_outline_rounded,
                                    size: 18,
                                    color: _onSurface(context, 0.78),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: presetValue,
                          decoration: InputDecoration(
                            labelText: 'Preset',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.secondary,
                                width: 1.6,
                              ),
                            ),
                          ),
                          items: presetItems
                              .map(
                                (preset) => DropdownMenuItem(
                                  value: preset.folder,
                                  child: _PresetLabel(
                                    name: preset.name,
                                    tag: preset.versionTag,
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) => presetItems
                              .map(
                                (preset) => _PresetLabel(
                                  name: preset.name,
                                  tag: preset.versionTag,
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedPreset = value),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: profileValue,
                          decoration: InputDecoration(
                            labelText: 'User',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.secondary,
                                width: 1.6,
                              ),
                            ),
                          ),
                          items: profileItems
                              .map(
                                (profile) => DropdownMenuItem(
                                  value: profile.accountId,
                                  child: Text(profile.accountId),
                                ),
                              )
                              .toList(),
                          onChanged: _selectProfile,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _HoverScale(
                                enabled:
                                    _selectedProfile != null &&
                                    _selectedPreset != null,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      (_selectedProfile != null &&
                                          _selectedPreset != null)
                                      ? _applyPreset
                                      : null,
                                  icon: const Icon(Icons.auto_fix_high),
                                  label: const Text('Apply preset to user'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HoverScale(
                                enabled:
                                    _selectedPreset != null &&
                                    _profiles.isNotEmpty,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      (_selectedPreset != null &&
                                          _profiles.isNotEmpty)
                                      ? _applyPresetToAll
                                      : null,
                                  icon: const Icon(Icons.group_rounded),
                                  label: const Text(
                                    'Apply preset to all users',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This replaces profile_athena.json for the selected user.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _onSurface(context, 0.6)),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _HoverScale(
                                child: ElevatedButton.icon(
                                  onPressed: _createCustomPreset,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Create profile preset'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HoverScale(
                                child: ElevatedButton.icon(
                                  onPressed: _deleteCustomPreset,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete profile preset'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create or delete custom profile presets.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _onSurface(context, 0.6)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _HoverScale(
                                enabled: _selectedProfile != null,
                                child: OutlinedButton.icon(
                                  onPressed: _selectedProfile != null
                                      ? _deleteProfile
                                      : null,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  label: const Text('Delete user'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HoverScale(
                                enabled: _hasAnyUsers,
                                child: OutlinedButton.icon(
                                  onPressed: _hasAnyUsers
                                      ? _deleteAllProfiles
                                      : null,
                                  icon: const Icon(
                                    Icons.delete_sweep,
                                    color: Colors.redAccent,
                                  ),
                                  label: const Text('Delete all users'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Permanently removes user data and game settings.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _onSurface(context, 0.6)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _HoverScale(
                                enabled: !_loading && _selectedProfile != null,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      (_loading || _selectedProfile == null)
                                      ? null
                                      : () => _exportUserSettings(
                                          _selectedProfile!,
                                        ),
                                  icon: const Icon(Icons.download_rounded),
                                  label: const Text('Export User'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HoverScale(
                                enabled: !_loading,
                                child: OutlinedButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : _importUserSettingsZip,
                                  icon: const Icon(Icons.file_upload_outlined),
                                  label: const Text('Import User (Select ZIP)'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Export or import a user into the backend.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _onSurface(context, 0.6)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserValuesScreen extends StatefulWidget {
  const UserValuesScreen({super.key, this.initialProfile});

  final String? initialProfile;

  @override
  State<UserValuesScreen> createState() => _UserValuesScreenState();
}

class _UserValuesScreenState extends State<UserValuesScreen> {
  bool _loading = true;
  double _loadProgress = 0.0;
  List<ProfileSummary> _profiles = [];
  String? _selectedProfile;

  final TextEditingController _levelController = TextEditingController();
  final TextEditingController _vbucksController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scheduleDeferredScreenLoad(this, _load);
  }

  @override
  void dispose() {
    _levelController.dispose();
    _vbucksController.dispose();
    super.dispose();
  }

  void _applyUserValuesToControllers(UserValues values) {
    final displayLevel = values.level > 1 ? values.level : values.accountLevel;
    _levelController.text = displayLevel.toString();
    _vbucksController.text = values.vbucks.toString();
  }

  Future<void> _load() async {
    final profilesSnapshot = _ProfilesScreenCache.snapshot;
    final profiles =
        profilesSnapshot?.profiles ?? await ProfileService.listProfiles();
    final profileIds = {for (final profile in profiles) profile.accountId};
    final savedSelectedProfile =
        profilesSnapshot?.uiState.lastSelectedProfile ??
        (await ProfilesUiStateService.load()).lastSelectedProfile;
    if (!mounted) return;
    final resolvedSelectedProfile =
        widget.initialProfile != null &&
            profileIds.contains(widget.initialProfile)
        ? widget.initialProfile
        : _selectedProfile != null && profileIds.contains(_selectedProfile)
        ? _selectedProfile
        : savedSelectedProfile != null &&
              profileIds.contains(savedSelectedProfile)
        ? savedSelectedProfile
        : profiles.isNotEmpty
        ? profiles.first.accountId
        : null;
    final warmedValues = _UserValuesWarmupCache.snapshot;
    setState(() {
      _profiles = profiles;
      _loadProgress = 1.0;
      _loading = false;
      _selectedProfile = resolvedSelectedProfile;
      if (warmedValues != null &&
          warmedValues.accountId == resolvedSelectedProfile) {
        _applyUserValuesToControllers(warmedValues.values);
      }
    });
    if (resolvedSelectedProfile != null &&
        (warmedValues == null ||
            warmedValues.accountId != resolvedSelectedProfile)) {
      unawaited(_loadUserValues());
    }
  }

  Future<void> _loadUserValues() async {
    if (_selectedProfile == null) return;

    final warmedValues = _UserValuesWarmupCache.snapshot;
    if (warmedValues != null && warmedValues.accountId == _selectedProfile) {
      if (!mounted) return;
      setState(() => _applyUserValuesToControllers(warmedValues.values));
      return;
    }

    final values = await UserValuesService.loadUserValues(_selectedProfile!);
    if (!mounted) return;
    _UserValuesWarmupCache.store(_selectedProfile!, values);

    setState(() => _applyUserValuesToControllers(values));
  }

  Future<void> _saveUserValues() async {
    if (_selectedProfile == null || _saving) return;

    setState(() => _saving = true);

    final level = int.tryParse(_levelController.text) ?? 1;
    final vbucks = int.tryParse(_vbucksController.text) ?? 0;

    // Use the same level value for all three level fields
    await UserValuesService.saveUserValues(
      _selectedProfile!,
      UserValues(
        level: level,
        bookLevel: level,
        accountLevel: level,
        vbucks: vbucks,
      ),
    );
    _UserValuesWarmupCache.store(
      _selectedProfile!,
      UserValues(
        level: level,
        bookLevel: level,
        accountLevel: level,
        vbucks: vbucks,
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    showAtlasSnackBar(
      context,
      const SnackBar(content: Text('User values saved successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF1A1F2E).withOpacity(0.5)
        : Colors.white.withOpacity(0.5);
    final borderColor = _onSurface(context, 0.12);
    const menuKey = 'user-values';

    return _BaseScreen(
      title: 'Edit User Values',
      child: _ScreenLoadGate(
        loading: _loading,
        transitionKey: 'user-values',
        progress: _loadProgress,
        child: _profiles.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_off,
                      size: 64,
                      color: _onSurface(context, 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No users found',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a user first from the Users menu',
                      style: TextStyle(color: _onSurface(context, 0.6)),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(title: 'Select User'),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedProfile,
                              decoration: const InputDecoration(
                                labelText: 'User',
                                border: OutlineInputBorder(),
                              ),
                              items: _profiles.map((profile) {
                                return DropdownMenuItem(
                                  value: profile.accountId,
                                  child: Text(profile.accountId),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedProfile = value);
                                  unawaited(_loadUserValues());
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(title: 'Level Settings'),
                          const SizedBox(height: 12),
                          _buildValueCard(
                            context,
                            cardColor,
                            borderColor,
                            icon: Icons.trending_up,
                            title: 'Level',
                            description:
                                'Sets level, book_level, and accountLevel to the same value',
                            imagePath: 'public/items/levels.webp',
                            fields: [
                              _ValueField(
                                label: 'Level',
                                controller: _levelController,
                                hint: 'e.g., 100 or 999',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(title: 'Currency Settings'),
                          const SizedBox(height: 12),
                          _buildValueCard(
                            context,
                            cardColor,
                            borderColor,
                            icon: Icons.monetization_on,
                            title: 'V-Bucks',
                            imagePath: 'public/items/VBucks.webp',
                            fields: [
                              _ValueField(
                                label: 'V-Bucks Amount',
                                controller: _vbucksController,
                                hint: 'Total V-Bucks (e.g., 13500)',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _menuEntrance(
                      context,
                      menuKey: menuKey,
                      index: 3,
                      child: Center(
                        child: _HoverScale(
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _saveUserValues,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_saving ? 'Saving...' : 'Save Changes'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildValueCard(
    BuildContext context,
    Color cardColor,
    Color borderColor, {
    required IconData icon,
    required String title,
    String? description,
    required String imagePath,
    required List<_ValueField> fields,
  }) {
    final fullImagePath = joinPath([getBackendRoot(), imagePath]);
    final imageFile = File(fullImagePath);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageFile.existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                imageFile,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _onSurface(context, 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 40, color: _onSurface(context, 0.3)),
            ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _onSurface(context, 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ...fields.map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: field.controller,
                      decoration: InputDecoration(
                        labelText: field.label,
                        hintText: field.hint,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueField {
  const _ValueField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
}

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logStore = LogStore.instance;
    return AnimatedBuilder(
      animation: logStore,
      builder: (context, _) {
        final allLogsText = logStore.allLogs.join('\n');
        return _BaseScreen(
          title: 'Logs',
          trailing: _HoverScale(
            child: IconButton(
              tooltip: 'Copy all logs',
              onPressed: allLogsText.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: allLogsText));
                      showAtlasSnackBar(
                        context,
                        const SnackBar(
                          content: Text('Logs copied to clipboard'),
                        ),
                      );
                    },
              icon: const Icon(Icons.copy_all_rounded),
            ),
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  allLogsText,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _onSurface(context, 0.7),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BaseScreen extends StatelessWidget {
  const _BaseScreen({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final menuKey = 'base-$title';
    return Scaffold(
      body: Stack(
        children: [
          const AtlasBackground(showParticles: false),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _menuEntrance(
                  context,
                  menuKey: menuKey,
                  index: 0,
                  child: Row(
                    children: [
                      _HoverScale(
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Spacer(),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _menuEntrance(
                    context,
                    menuKey: menuKey,
                    index: 1,
                    child: GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SectionTitleWithTag extends StatelessWidget {
  const _SectionTitleWithTag({required this.title, required this.tag});

  final String title;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        _AtlasTagPill(label: tag),
      ],
    );
  }
}

class _PresetLabel extends StatelessWidget {
  const _PresetLabel({required this.name, this.tag});

  final String name;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(name, overflow: TextOverflow.ellipsis),
        ),
        if (tag != null) ...[
          const SizedBox(width: 8),
          _AtlasTagPill(label: tag!),
        ],
      ],
    );
  }
}

class ArenaEntry {
  const ArenaEntry({required this.accountId, required this.hype});

  final String accountId;
  final int hype;
}

class ArenaService {
  static Future<List<ArenaEntry>> loadLeaderboard() async {
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    if (!await profilesDir.exists()) return [];
    final entries = <ArenaEntry>[];
    await for (final entity in profilesDir.list()) {
      if (entity is Directory) {
        final profilePath = File(
          joinPath([entity.path, 'profile_athena.json']),
        );
        if (await profilePath.exists()) {
          try {
            final data =
                jsonDecode(await profilePath.readAsString())
                    as Map<String, dynamic>;
            final stats =
                (data['stats'] as Map<String, dynamic>?)?['attributes']
                    as Map<String, dynamic>?;
            final hype = stats?['arena_hype'] ?? 0;
            final folderName = entity.path.split(Platform.pathSeparator).last;
            entries.add(
              ArenaEntry(
                accountId: folderName,
                hype: hype is int ? hype : int.tryParse(hype.toString()) ?? 0,
              ),
            );
          } catch (_) {}
        }
      }
    }
    entries.sort((a, b) => b.hype.compareTo(a.hype));
    return entries;
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _tabIndex;
  bool _loading = true;
  double _loadProgress = 0.0;
  bool _startBackendOnLaunch = false;
  bool _disableBackendUpdateCheck = false;
  String _backgroundImagePath = '';
  double _backgroundBlur = 15;
  double _backgroundParticlesOpacity = 1.0;
  bool _dialogBlurEnabled = true;
  bool _startupAnimationEnabled = true;
  late final VoidCallback _backgroundPathListener;
  late final VoidCallback _backgroundBlurListener;
  late final VoidCallback _externalToggleStateListener;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex.clamp(0, 3);
    _scheduleDeferredScreenLoad(this, _load);
    _externalToggleStateListener = () {
      if (!mounted) return;
      unawaited(_load());
    };
    _backgroundPathListener = () {
      if (!mounted) return;
      setState(() => _backgroundImagePath = appBackgroundPath.value);
    };
    _backgroundBlurListener = () {
      if (!mounted) return;
      setState(() => _backgroundBlur = appBackgroundBlur.value);
    };
    appBackgroundPath.addListener(_backgroundPathListener);
    appBackgroundBlur.addListener(_backgroundBlurListener);
    userToggleStatesRevision.addListener(_externalToggleStateListener);
  }

  @override
  void dispose() {
    appBackgroundPath.removeListener(_backgroundPathListener);
    appBackgroundBlur.removeListener(_backgroundBlurListener);
    userToggleStatesRevision.removeListener(_externalToggleStateListener);
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    if (!mounted) return;
    setState(() {
      _startBackendOnLaunch = config.startBackendOnLaunch;
      _disableBackendUpdateCheck = config.disableBackendUpdateCheck;
      _backgroundImagePath = config.backgroundImagePath;
      _backgroundBlur = config.backgroundBlur;
      _backgroundParticlesOpacity = config.backgroundParticlesOpacity;
      _dialogBlurEnabled = config.dialogBlurEnabled;
      _startupAnimationEnabled = config.startupAnimationEnabled;
      _loadProgress = 1.0;
      _loading = false;
    });
  }

  Future<void> _pickBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _backgroundImagePath = path);
    appBackgroundPath.value = path;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundImagePath: path));
  }

  Future<void> _clearBackgroundImage() async {
    setState(() => _backgroundImagePath = '');
    appBackgroundPath.value = '';
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundImagePath: ''));
  }

  Future<void> _updateBackgroundBlur(double value) async {
    setState(() => _backgroundBlur = value);
    appBackgroundBlur.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundBlur: value));
  }

  Future<void> _updateBackgroundParticlesOpacity(double value) async {
    final clamped = value.clamp(0.0, 2.0).toDouble();
    setState(() => _backgroundParticlesOpacity = clamped);
    appBackgroundParticlesOpacity.value = clamped;
    final existing = await ConfigService.load();
    await ConfigService.save(
      existing.copyWith(backgroundParticlesOpacity: clamped),
    );
  }

  Future<void> _updateDialogBlur(bool value) async {
    setState(() => _dialogBlurEnabled = value);
    appDialogBlurEnabled.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(dialogBlurEnabled: value));
  }

  Future<void> _updateStartupAnimationEnabled(bool value) async {
    setState(() => _startupAnimationEnabled = value);
    appStartupAnimationEnabled.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(startupAnimationEnabled: value));
  }

  Future<void> _updateStartOnLaunch(bool value) async {
    setState(() => _startBackendOnLaunch = value);
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(startBackendOnLaunch: value));
  }

  Future<void> _updateDisableBackendUpdateCheck(bool value) async {
    setState(() => _disableBackendUpdateCheck = value);
    final existing = await ConfigService.load();
    await ConfigService.save(
      existing.copyWith(disableBackendUpdateCheck: value),
    );
  }

  String _backgroundSubtitle() {
    if (_backgroundImagePath.isEmpty) {
      return 'Default background';
    }
    final resolved = _resolveBackgroundPath(_backgroundImagePath);
    if (resolved == null) {
      return 'Missing image: $_backgroundImagePath';
    }
    return _backgroundImagePath;
  }

  @override
  Widget build(BuildContext context) {
    const menuKey = 'settings';
    return _BaseScreen(
      title: 'Settings',
      child: _ScreenLoadGate(
        loading: _loading,
        transitionKey: 'settings',
        progress: _loadProgress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _menuEntrance(
              context,
              menuKey: menuKey,
              index: 0,
              child: SizedBox(
                width: 220,
                child: ListView(
                  children: [
                    _SettingsTab(
                      label: 'Appearance',
                      icon: Icons.palette_outlined,
                      selected: _tabIndex == 0,
                      onTap: () => setState(() => _tabIndex = 0),
                    ),
                    _SettingsTab(
                      label: 'Data Management',
                      icon: Icons.storage_rounded,
                      selected: _tabIndex == 1,
                      onTap: () => setState(() => _tabIndex = 1),
                    ),
                    _SettingsTab(
                      label: 'Startup',
                      icon: Icons.power_settings_new_rounded,
                      selected: _tabIndex == 2,
                      onTap: () => setState(() => _tabIndex = 2),
                    ),
                    _SettingsTab(
                      label: 'Credits',
                      icon: Icons.auto_awesome_rounded,
                      selected: _tabIndex == 3,
                      onTap: () => setState(() => _tabIndex = 3),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _menuEntrance(
                context,
                menuKey: menuKey,
                index: 1,
                child: _menuSwap(
                  context,
                  switchKey: _tabIndex,
                  duration: const Duration(milliseconds: 220),
                  expand: true,
                  layoutAlignment: Alignment.topLeft,
                  child: _buildTabContent(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    final title = switch (_tabIndex) {
      0 => 'Appearance',
      1 => 'Data Management',
      2 => 'Startup',
      3 => 'Credits',
      _ => 'Settings',
    };
    final menuKey = 'settings-tab-$title';
    switch (_tabIndex) {
      case 0:
        return SingleChildScrollView(
          key: const ValueKey('appearance'),
          primary: false,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(title: title),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: _dialogBlurEnabled,
                      onChanged: _updateDialogBlur,
                      title: const Text('Popup background blur'),
                      subtitle: const Text(
                        'Blur the background behind popups.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _startupAnimationEnabled,
                      onChanged: _updateStartupAnimationEnabled,
                      title: const Text('Startup animation'),
                      subtitle: const Text(
                        'Play the intro animation when ATLAS Backend launches.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 1,
                child: ListTile(
                  title: const Text('Background image'),
                  subtitle: Text(
                    _backgroundSubtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HoverScale(
                        enabled: _backgroundImagePath.isNotEmpty,
                        child: TextButton(
                          onPressed: _backgroundImagePath.isEmpty
                              ? null
                              : _clearBackgroundImage,
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _HoverScale(
                        child: ElevatedButton(
                          onPressed: _pickBackgroundImage,
                          child: const Text('Choose image'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background blur (${_backgroundBlur.toStringAsFixed(0)})',
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const min = 0.0;
                        const max = 30.0;
                        const defaultBlur = 15.0;
                        final trackWidth = constraints.maxWidth;
                        final normalized = (defaultBlur - min) / (max - min);
                        final dotX = trackWidth * normalized;
                        return SizedBox(
                          height: 36,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Slider(
                                value: _backgroundBlur,
                                min: min,
                                max: max,
                                divisions: 30,
                                onChanged: _updateBackgroundBlur,
                              ),
                              Positioned(
                                left: dotX - 4,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background particles (${(_backgroundParticlesOpacity * 100).round()}%)',
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const min = 0.0;
                        const max = 2.0;
                        const defaultOpacity = 1.0;
                        final trackWidth = constraints.maxWidth;
                        final normalized = (defaultOpacity - min) / (max - min);
                        final dotX = trackWidth * normalized;
                        return SizedBox(
                          height: 36,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Slider(
                                value: _backgroundParticlesOpacity,
                                min: min,
                                max: max,
                                divisions: 20,
                                label:
                                    '${(_backgroundParticlesOpacity * 100).round()}%',
                                onChanged: _updateBackgroundParticlesOpacity,
                              ),
                              Positioned(
                                left: dotX - 4,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 1:
        return SingleChildScrollView(
          key: const ValueKey('data'),
          primary: false,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(title: title),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 1,
                child: const DataManagementPanel(),
              ),
            ],
          ),
        );
      case 2:
        return Column(
          key: const ValueKey('startup'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _menuEntrance(
              context,
              menuKey: menuKey,
              index: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(title: title),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _startBackendOnLaunch,
                    onChanged: _updateStartOnLaunch,
                    title: const Text('Start backend on launch'),
                    subtitle: const Text(
                      'Automatically start the backend when the GUI opens.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _menuEntrance(
              context,
              menuKey: menuKey,
              index: 1,
              child: SwitchListTile(
                value: _disableBackendUpdateCheck,
                onChanged: _updateDisableBackendUpdateCheck,
                title: const Text('Disable Update Checks'),
                subtitle: const Text(
                  'Skip update checks when launching the backend.',
                ),
              ),
            ),
          ],
        );
      case 3:
        const credits = <_CreditProfileData>[
          _CreditProfileData(
            name: 'andr1ww',
            handle: '@andr1ww',
            role: 'Backend Foundation',
            githubUrl: 'https://github.com/andr1ww',
            avatarUrl: 'https://github.com/andr1ww.png?size=240',
            description:
                'Created Nexa, the open-source base that ATLAS Backend was developed from.',
            projects: <_CreditProjectLink>[
              _CreditProjectLink(
                label: 'Nexa',
                url: 'https://github.com/andr1ww/Nexa',
              ),
            ],
          ),
          _CreditProfileData(
            name: 'Lawin',
            handle: '@Lawin0129',
            role: 'Backend Foundation #2',
            githubUrl: 'https://github.com/Lawin0129',
            avatarUrl: 'https://github.com/Lawin0129.png?size=240',
            description:
                'Created LawinServer, another open-source Fortnite backend that helped add certain features to ATLAS Backend.',
            projects: <_CreditProjectLink>[
              _CreditProjectLink(
                label: 'LawinServer',
                url: 'https://github.com/Lawin0129/LawinServer',
              ),
            ],
          ),
        ];
        return SingleChildScrollView(
          key: const ValueKey('credits'),
          primary: false,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(title: title),
                    const SizedBox(height: 12),
                    Text(
                      'ATLAS Backend builds on open-source work. These people and projects provided key foundations and reference points for the backend.',
                      style: TextStyle(
                        color: _onSurface(context, 0.78),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _menuEntrance(
                context,
                menuKey: menuKey,
                index: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = credits
                        .map((credit) => _creditProfileCard(context, credit))
                        .toList(growable: false);
                    if (constraints.maxWidth < 940) {
                      return Column(
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(height: 16),
                            cards[i],
                          ],
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 16),
                        Expanded(child: cards[1]),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.secondary
        : _onSurface(context, 0.7);
    return ListTile(
      selected: selected,
      selectedTileColor: Colors.white10,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
      ),
      onTap: onTap,
    );
  }
}

class ProfileSummary {
  const ProfileSummary({required this.accountId, required this.hasAthena});

  final String accountId;
  final bool hasAthena;
}

class ProfilePreset {
  const ProfilePreset({
    required this.name,
    required this.folder,
    this.versionTag,
  });

  final String name;
  final String folder;
  final String? versionTag;

  String get displayName =>
      versionTag == null ? name : '$name (${versionTag!})';
}

class _CreateUserResult {
  const _CreateUserResult({
    required this.accountId,
    required this.presetFolder,
  });

  final String accountId;
  final String presetFolder;
}

class ProfilesUiState {
  const ProfilesUiState({
    this.lastSelectedProfile,
    this.lastAppliedPresetByUser = const <String, String>{},
  });

  final String? lastSelectedProfile;
  final Map<String, String> lastAppliedPresetByUser;
}

class ProfilesUiStateService {
  static Future<ProfilesUiState> load() async {
    final stateFile = File(_statePath());
    if (!await stateFile.exists()) {
      // Migrate from legacy root-level location if present.
      final legacyFile = File(_legacyStatePath());
      if (await legacyFile.exists()) {
        try {
          await stateFile.parent.create(recursive: true);
          await legacyFile.copy(stateFile.path);
          await legacyFile.delete();
        } catch (_) {}
        if (!await stateFile.exists()) {
          return const ProfilesUiState();
        }
      } else {
        return const ProfilesUiState();
      }
    }

    try {
      final raw = await stateFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const ProfilesUiState();
      }

      final selectedProfileRaw = decoded['lastSelectedProfile'];
      final selectedProfile =
          selectedProfileRaw is String && selectedProfileRaw.trim().isNotEmpty
          ? selectedProfileRaw
          : null;

      final presetMap = <String, String>{};
      final presetRaw = decoded['lastAppliedPresetByUser'];
      if (presetRaw is Map) {
        presetRaw.forEach((key, value) {
          if (key is! String || value is! String) return;
          final accountId = key.trim();
          final presetFolder = value.trim();
          if (accountId.isEmpty || presetFolder.isEmpty) return;
          presetMap[accountId] = presetFolder;
        });
      }

      return ProfilesUiState(
        lastSelectedProfile: selectedProfile,
        lastAppliedPresetByUser: presetMap,
      );
    } catch (_) {
      return const ProfilesUiState();
    }
  }

  static Future<void> save(ProfilesUiState state) async {
    final stateFile = File(_statePath());
    final map = <String, dynamic>{
      'lastSelectedProfile': state.lastSelectedProfile,
      'lastAppliedPresetByUser': state.lastAppliedPresetByUser,
    };
    await stateFile.parent.create(recursive: true);
    await stateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
      flush: true,
    );
  }

  static String _statePath() {
    return joinPath([
      getBackendRoot(),
      'static',
      'athenaprofiles',
      'profiles-ui-state.json',
    ]);
  }

  static String _legacyStatePath() {
    return joinPath([getBackendRoot(), 'profiles-ui-state.json']);
  }
}

class UserValues {
  const UserValues({
    required this.level,
    required this.bookLevel,
    required this.accountLevel,
    required this.vbucks,
  });

  final int level;
  final int bookLevel;
  final int accountLevel;
  final int vbucks;
}

class UserValuesService {
  static Future<UserValues> loadUserValues(String accountId) async {
    int level = 1;
    int bookLevel = 1;
    int accountLevel = 1;
    int vbucks = 0;

    final athenaPath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_athena.json',
    ]);
    final athenaFile = File(athenaPath);
    if (await athenaFile.exists()) {
      try {
        final content = await athenaFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // Navigate to stats.attributes where the level data is stored
        final stats = json['stats'] as Map<String, dynamic>?;
        if (stats != null) {
          final attributes = stats['attributes'] as Map<String, dynamic>?;
          if (attributes != null) {
            // Read actual values, with fallbacks
            if (attributes.containsKey('level')) {
              level = (attributes['level'] is int)
                  ? attributes['level'] as int
                  : int.tryParse(attributes['level'].toString()) ?? 1;
            }
            if (attributes.containsKey('book_level')) {
              bookLevel = (attributes['book_level'] is int)
                  ? attributes['book_level'] as int
                  : int.tryParse(attributes['book_level'].toString()) ?? 1;
            }
            if (attributes.containsKey('accountLevel')) {
              accountLevel = (attributes['accountLevel'] is int)
                  ? attributes['accountLevel'] as int
                  : int.tryParse(attributes['accountLevel'].toString()) ?? 1;
            }
          }
        }
      } catch (e) {
        debugPrint('Error reading athena profile: $e');
      }
    }

    final commonCorePath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_common_core.json',
    ]);
    final commonCoreFile = File(commonCorePath);
    if (await commonCoreFile.exists()) {
      try {
        final content = await commonCoreFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final items = json['items'] as Map<String, dynamic>?;
        if (items != null) {
          final mtxPurchased =
              items['Currency:MtxPurchased'] as Map<String, dynamic>?;
          if (mtxPurchased != null && mtxPurchased.containsKey('quantity')) {
            vbucks = (mtxPurchased['quantity'] is int)
                ? mtxPurchased['quantity'] as int
                : int.tryParse(mtxPurchased['quantity'].toString()) ?? 0;
          }
        }
      } catch (e) {
        debugPrint('Error reading common_core profile: $e');
      }
    }

    return UserValues(
      level: level,
      bookLevel: bookLevel,
      accountLevel: accountLevel,
      vbucks: vbucks,
    );
  }

  static Future<void> saveUserValues(
    String accountId,
    UserValues values,
  ) async {
    final athenaPath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_athena.json',
    ]);
    final athenaFile = File(athenaPath);
    if (await athenaFile.exists()) {
      try {
        final content = await athenaFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // Navigate to stats.attributes to set the level values
        final stats = json['stats'] as Map<String, dynamic>?;
        if (stats != null) {
          final attributes = stats['attributes'] as Map<String, dynamic>?;
          if (attributes != null) {
            attributes['level'] = values.level;
            attributes['book_level'] = values.bookLevel;
            attributes['accountLevel'] = values.accountLevel;

            await athenaFile.writeAsString(
              const JsonEncoder.withIndent('  ').convert(json),
            );
          }
        }
      } catch (e) {
        debugPrint('Error saving athena profile: $e');
      }
    }

    final commonCorePath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_common_core.json',
    ]);
    final commonCoreFile = File(commonCorePath);
    if (await commonCoreFile.exists()) {
      try {
        final content = await commonCoreFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final items = json['items'] as Map<String, dynamic>?;
        if (items != null) {
          if (!items.containsKey('Currency:MtxPurchased')) {
            items['Currency:MtxPurchased'] = {
              'templateId': 'Currency:MtxPurchased',
              'attributes': {'platform': 'EpicPC'},
              'quantity': values.vbucks,
            };
          } else {
            final mtxPurchased =
                items['Currency:MtxPurchased'] as Map<String, dynamic>;
            mtxPurchased['quantity'] = values.vbucks;
          }
          await commonCoreFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(json),
          );
        }
      } catch (_) {}
    }
  }
}

class ProfileService {
  static const String _profileTemplateBackupDirName = '.defaults';
  static const String _hostAccountId = 'host';
  static const Set<String> _profileTemplateFiles = {
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trim().isNotEmpty) return parts[i];
    }
    return path;
  }

  static bool _isHostAccountId(String accountId) {
    return accountId.trim().toLowerCase() == _hostAccountId;
  }

  static Future<bool> userExists(String accountId) async {
    final trimmed = accountId.trim();
    if (trimmed.isEmpty) return false;
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles', trimmed]),
    );
    if (await profilesDir.exists()) return true;
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings', trimmed]),
    );
    return await clientSettingsDir.exists();
  }

  static Future<void> createUser(
    String accountId, {
    required String presetFolder,
  }) async {
    final trimmed = accountId.trim();
    if (trimmed.isEmpty) {
      throw Exception('User name is required.');
    }
    if (_isHostAccountId(trimmed)) {
      throw Exception('The name "host" is reserved.');
    }
    if (await userExists(trimmed)) {
      throw Exception('User already exists.');
    }
    final presetPath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        presetFolder,
        'profile_athena.json',
      ]),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    final profilesRoot = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    if (!await profilesRoot.exists()) {
      throw Exception('Profiles directory not found.');
    }
    final profileDir = Directory(joinPath([profilesRoot.path, trimmed]));
    await profileDir.create(recursive: true);
    for (final templateName in _profileTemplateFiles) {
      final templatePath = File(joinPath([profilesRoot.path, templateName]));
      if (await templatePath.exists()) {
        await templatePath.copy(joinPath([profileDir.path, templateName]));
      }
    }
    final profilePath = File(
      joinPath([profileDir.path, 'profile_athena.json']),
    );
    await presetPath.copy(profilePath.path);
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<List<ProfileSummary>> listProfiles() async {
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    final clientSettingsRoot = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings']),
    );

    final profiles = <ProfileSummary>[];
    final seenAccountIds = <String>{};

    // Check profiles directory
    if (await profilesDir.exists()) {
      await for (final entity in profilesDir.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        if (_isHostAccountId(accountId)) {
          continue;
        }
        final profilePath = File(
          joinPath([entity.path, 'profile_athena.json']),
        );
        profiles.add(
          ProfileSummary(
            accountId: accountId,
            hasAthena: await profilePath.exists(),
          ),
        );
        seenAccountIds.add(accountId);
      }
    }

    // Also check ClientSettings directory for accounts not in profiles
    if (await clientSettingsRoot.exists()) {
      await for (final entity in clientSettingsRoot.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId.toLowerCase() == 'config' ||
            accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        if (_isHostAccountId(accountId)) {
          continue;
        }

        // Only add if not already added from profiles directory
        if (!seenAccountIds.contains(accountId)) {
          profiles.add(ProfileSummary(accountId: accountId, hasAthena: false));
          seenAccountIds.add(accountId);
        }
      }
    }

    profiles.sort((a, b) => a.accountId.compareTo(b.accountId));
    return profiles;
  }

  static Future<bool> hasAnyUsers() async {
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    final clientSettingsRoot = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings']),
    );

    if (await profilesDir.exists()) {
      await for (final entity in profilesDir.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        return true;
      }
    }

    if (await clientSettingsRoot.exists()) {
      await for (final entity in clientSettingsRoot.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId.toLowerCase() == 'config' ||
            accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        return true;
      }
    }

    return false;
  }

  static Future<Map<String, dynamic>?> _loadPresetsConfig() async {
    final configFile = File(
      joinPath([getBackendRoot(), 'static', 'athenaprofiles', 'presets.json']),
    );
    if (!await configFile.exists()) return null;
    try {
      final contents = await configFile.readAsString();
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _customPresetsPath() => joinPath([
    getBackendRoot(),
    'static',
    'athenaprofiles',
    'custom-presets.json',
  ]);

  static Future<Map<String, dynamic>> _loadCustomPresetsConfig() async {
    final configFile = File(_customPresetsPath());
    if (!await configFile.exists()) return {'presets': <dynamic>[]};
    try {
      final contents = await configFile.readAsString();
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (_) {
      return {'presets': <dynamic>[]};
    }
  }

  static Future<void> _saveCustomPresetsConfig(
    Map<String, dynamic> config,
  ) async {
    final configFile = File(_customPresetsPath());
    await configFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await configFile.writeAsString(encoder.convert(config));
  }

  static Future<void> createCustomPreset({
    required String name,
    required String sourceFilePath,
    String? versionTag,
  }) async {
    final folderName = '$name Profile';
    final presetsDir = Directory(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
      ]),
    );
    final targetDir = Directory(joinPath([presetsDir.path, folderName]));
    if (await targetDir.exists()) {
      throw Exception('A preset folder named "$folderName" already exists.');
    }
    await targetDir.create(recursive: true);

    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file not found.');
    }
    final targetFile = File(joinPath([targetDir.path, 'profile_athena.json']));
    await sourceFile.copy(targetFile.path);

    final config = await _loadCustomPresetsConfig();
    final presetsList = config['presets'] as List<dynamic>? ?? [];
    presetsList.add({
      'name': name,
      'folder': folderName,
      'versionTag': versionTag?.trim().isNotEmpty == true
          ? versionTag!.trim()
          : null,
      'pinned': null,
    });
    config['presets'] = presetsList;
    await _saveCustomPresetsConfig(config);
  }

  static Future<void> deleteCustomPreset(String folderName) async {
    final presetsDir = Directory(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        folderName,
      ]),
    );
    if (await presetsDir.exists()) {
      await presetsDir.delete(recursive: true);
    }

    final config = await _loadCustomPresetsConfig();
    final presetsList = config['presets'] as List<dynamic>? ?? [];
    presetsList.removeWhere((p) {
      final map = p as Map<String, dynamic>;
      return (map['folder'] as String?)?.trim().toLowerCase() ==
          folderName.trim().toLowerCase();
    });
    config['presets'] = presetsList;
    await _saveCustomPresetsConfig(config);
  }

  static bool isCustomPreset(
    String folderName,
    Map<String, dynamic>? customConfig,
  ) {
    if (customConfig == null) return false;
    final presetsList = customConfig['presets'] as List<dynamic>? ?? [];
    for (final p in presetsList) {
      final map = p as Map<String, dynamic>;
      if ((map['folder'] as String?)?.trim().toLowerCase() ==
          folderName.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  static Future<List<ProfilePreset>> listPresets() async {
    final presetsDir = Directory(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
      ]),
    );
    if (!await presetsDir.exists()) return [];

    final config = await _loadPresetsConfig();
    final customConfig = await _loadCustomPresetsConfig();
    final configPresets = <String, Map<String, dynamic>>{};
    final hiddenFolders = <String>{};
    if (config != null) {
      final presetsList = config['presets'] as List<dynamic>? ?? [];
      for (final p in presetsList) {
        final map = p as Map<String, dynamic>;
        final folder = (map['folder'] as String?)?.trim().toLowerCase();
        if (folder != null) configPresets[folder] = map;
      }
      final hiddenList = config['hidden'] as List<dynamic>? ?? [];
      for (final h in hiddenList) {
        hiddenFolders.add((h as String).trim().toLowerCase());
      }
    }
    final customPresetsList = customConfig['presets'] as List<dynamic>? ?? [];
    for (final p in customPresetsList) {
      final map = p as Map<String, dynamic>;
      final folder = (map['folder'] as String?)?.trim().toLowerCase();
      if (folder != null) configPresets[folder] = map;
    }

    final presets = <ProfilePreset>[];
    await for (final entity in presetsDir.list(recursive: false)) {
      if (entity is! Directory) continue;
      final folder = _basename(entity.path);
      if (folder.trim().isEmpty) continue;
      final folderKey = folder.trim().toLowerCase();
      if (hiddenFolders.contains(folderKey)) continue;
      final presetPath = File(joinPath([entity.path, 'profile_athena.json']));
      if (!await presetPath.exists()) continue;

      final configEntry = configPresets[folderKey];
      if (configEntry != null) {
        presets.add(
          ProfilePreset(
            name: configEntry['name'] as String? ?? folder,
            folder: folder,
            versionTag: configEntry['versionTag'] as String?,
          ),
        );
      } else {
        presets.add(ProfilePreset(name: folder, folder: folder));
      }
    }

    presets.sort((a, b) {
      final configA = configPresets[a.folder.trim().toLowerCase()];
      final configB = configPresets[b.folder.trim().toLowerCase()];
      final aPinned = configA?['pinned'] as String?;
      final bPinned = configB?['pinned'] as String?;
      final aTop = aPinned == 'top';
      final bTop = bPinned == 'top';
      if (aTop != bTop) return aTop ? -1 : 1;
      final aBottom = aPinned == 'bottom';
      final bBottom = bPinned == 'bottom';
      if (aBottom != bBottom) return aBottom ? 1 : -1;

      final aVersion = _parseVersion(a.versionTag);
      final bVersion = _parseVersion(b.versionTag);
      final versionOrder = bVersion.compareTo(aVersion);
      if (versionOrder != 0) {
        return versionOrder; // Descending order (highest version first)
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return presets;
  }

  static double _parseVersion(String? versionTag) {
    if (versionTag == null || versionTag.isEmpty) return 0.0;

    final cleanVersion = versionTag.replaceAll('v', '').replaceAll('+', '');
    if (cleanVersion.isEmpty) return 0.0;

    try {
      return double.parse(cleanVersion);
    } catch (e) {
      return 0.0;
    }
  }

  static Future<void> applyPreset(String accountId, String presetFolder) async {
    final presetPath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        presetFolder,
        'profile_athena.json',
      ]),
    );
    final profilePath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'profiles',
        accountId,
        'profile_athena.json',
      ]),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    await profilePath.parent.create(recursive: true);
    await presetPath.copy(profilePath.path);
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<int> applyPresetToAll(String presetFolder) async {
    final presetPath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        presetFolder,
        'profile_athena.json',
      ]),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    final profiles = await listProfiles();
    if (profiles.isEmpty) {
      throw Exception('No profiles found.');
    }
    var appliedCount = 0;
    for (final profile in profiles) {
      final profilePath = File(
        joinPath([
          getBackendRoot(),
          'static',
          'profiles',
          profile.accountId,
          'profile_athena.json',
        ]),
      );
      await profilePath.parent.create(recursive: true);
      await presetPath.copy(profilePath.path);
      appliedCount += 1;
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
    return appliedCount;
  }

  static Future<void> deleteProfile(
    String accountId, {
    required bool deleteProfile,
    required bool deleteClientSettings,
  }) async {
    if (deleteProfile) {
      final profilesDir = Directory(
        joinPath([getBackendRoot(), 'static', 'profiles', accountId]),
      );
      if (await profilesDir.exists()) {
        await profilesDir.delete(recursive: true);
      }
    }

    if (deleteClientSettings) {
      final clientSettingsDir = Directory(
        joinPath([getBackendRoot(), 'static', 'ClientSettings', accountId]),
      );
      if (await clientSettingsDir.exists()) {
        await clientSettingsDir.delete(recursive: true);
      }
    }

    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<void> deleteAllProfiles({
    required bool deleteProfiles,
    required bool deleteClientSettings,
  }) async {
    if (deleteProfiles) {
      final profilesRoot = Directory(
        joinPath([getBackendRoot(), 'static', 'profiles']),
      );
      if (await profilesRoot.exists()) {
        await for (final entity in profilesRoot.list(recursive: false)) {
          if (entity is! Directory) continue;
          final name = _basename(entity.path);
          if (name.isEmpty || name.startsWith('.')) continue;
          await entity.delete(recursive: true);
        }
      }
    }

    if (deleteClientSettings) {
      final clientSettingsRoot = Directory(
        joinPath([getBackendRoot(), 'static', 'ClientSettings']),
      );
      if (await clientSettingsRoot.exists()) {
        await for (final entity in clientSettingsRoot.list(recursive: false)) {
          if (entity is! Directory) continue;
          final name = _basename(entity.path);
          if (name.isEmpty || name.startsWith('.')) continue;
          if (name.toLowerCase() == 'config') continue;
          await entity.delete(recursive: true);
        }
      }
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }
}

class LogStore extends ChangeNotifier {
  LogStore._();

  static final LogStore instance = LogStore._();

  final List<String> _logs = [];

  List<String> get allLogs => List.unmodifiable(_logs);
  List<String> get recentLogs =>
      _logs.length > 20 ? _logs.sublist(_logs.length - 20) : _logs;

  void addLog(String line) {
    _logs.add(line);
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
    }
    notifyListeners();
  }

  void clear() {
    if (_logs.isEmpty) return;
    _logs.clear();
    notifyListeners();
  }
}

class BackendPaths {
  static const String curveTableComment = '# CurveTables';
  static const String straightBloomComment = '# Straight Bloom';
  static const String dataTableComment = '# DataTables';
  static const String fixesComment = '# Fixes';
  static const String defaultCurvePath =
      '/Game/Athena/Balance/DataTables/AthenaGameData';
  static const String _defaultGameDataFolderName = 'DefaultGame Data';

  static String get defaultGameIni =>
      joinPath([getBackendRoot(), 'static', 'hotfixes', 'DefaultGame.ini']);
  static String get defaultEngineIni =>
      joinPath([getBackendRoot(), 'static', 'hotfixes', 'DefaultEngine.ini']);
  static String get defaultGameDataDir => joinPath([
    getBackendRoot(),
    'static',
    'hotfixes',
    _defaultGameDataFolderName,
  ]);
  static String get curvesJson =>
      joinPath([getBackendRoot(), 'responses', 'curves.json']);
  static String get curvesDefaultsJson =>
      joinPath([getBackendRoot(), 'responses', 'curves.defaults.json']);
  static String get curveTableLinesIni =>
      joinPath([defaultGameDataDir, 'CurveTables.ini']);
  static String get legacyCurveTableLinesIni =>
      joinPath([getBackendRoot(), 'responses', 'user-curvetables.ini']);
  static String get curveTableStateJson =>
      joinPath([getBackendRoot(), 'responses', 'curvetables-state.json']);
  static String get dataTablesJson =>
      joinPath([getBackendRoot(), 'responses', 'datatables.json']);
  static String get dataTablesDefaultsJson =>
      joinPath([getBackendRoot(), 'responses', 'datatables.defaults.json']);
  static String get dataTablesUiState =>
      joinPath([getBackendRoot(), 'responses', 'datatables-ui.json']);
  static String get dataTableLinesIni =>
      joinPath([defaultGameDataDir, 'DataTables.ini']);
  static String get legacyDataTableLinesIni =>
      joinPath([getBackendRoot(), 'responses', 'user-datatables.ini']);
  static String get straightBloomLinesIni =>
      joinPath([defaultGameDataDir, 'StraightBloom.ini']);
  static String get fixesLinesIni =>
      joinPath([defaultGameDataDir, 'Fixes.ini']);
  static String get userToggleStatesJson =>
      joinPath([getBackendRoot(), 'responses', 'user-toggle-states.json']);
  static String get modificationsBackup =>
      joinPath([getBackendRoot(), 'responses', 'modifications-backup.json']);
  static String get straightBloomStateJson =>
      joinPath([getBackendRoot(), 'responses', 'straight-bloom-state.json']);
  static String get configIni =>
      joinPath([getBackendRoot(), 'src', 'config', 'config.ini']);
  static String get updateNotesMarkdown =>
      joinPath([getBackendRoot(), 'update-notes.md']);
  static String get updateNotesText =>
      joinPath([getBackendRoot(), 'update-notes.txt']);
}

class IniService {
  static ({String content, int insertPoint}) ensureAssetSection(
    String content,
    String commentLabel, {
    bool preferPrepend = false,
  }) {
    var updated = content;
    if (!updated.contains(commentLabel)) {
      final assetIndex = updated.indexOf('[AssetHotfix]');
      if (assetIndex != -1) {
        final newlineAfter = updated.indexOf('\n', assetIndex);
        final insertAt = newlineAfter == -1 ? updated.length : newlineAfter + 1;
        updated =
            '${updated.substring(0, insertAt)}$commentLabel\n${updated.substring(insertAt)}';
      } else {
        updated = '${updated.trimRight()}\n[AssetHotfix]\n$commentLabel\n';
      }
    }

    final commentIndex = updated.indexOf(commentLabel);
    final newlineAfterComment = updated.indexOf('\n', commentIndex);
    final insertPoint = newlineAfterComment == -1
        ? updated.length
        : newlineAfterComment + 1;
    return (content: updated, insertPoint: insertPoint);
  }
}

Future<void> _synchronizeInstalledMutableDataFiles(
  Directory atlasDataDir,
) async {
  final installRoot = getInstallationRoot();
  if (!_samePath(installRoot, atlasDataDir.path)) {
    await _mergeInstalledIniFile(
      installPath: joinPath([
        installRoot,
        'static',
        'hotfixes',
        'DefaultGame.ini',
      ]),
      targetPath: joinPath([
        atlasDataDir.path,
        'static',
        'hotfixes',
        'DefaultGame.ini',
      ]),
      stripManagedHotfixBlocks: true,
    );
    await _mergeInstalledIniFile(
      installPath: joinPath([
        installRoot,
        'static',
        'hotfixes',
        'DefaultEngine.ini',
      ]),
      targetPath: joinPath([
        atlasDataDir.path,
        'static',
        'hotfixes',
        'DefaultEngine.ini',
      ]),
    );
  }

  await ManagedHotfixService.ensureInitialized();
}

Future<void> _mergeInstalledIniFile({
  required String installPath,
  required String targetPath,
  bool stripManagedHotfixBlocks = false,
}) async {
  final sourceFile = File(installPath);
  final targetFile = File(targetPath);
  if (!await sourceFile.exists() || !await targetFile.exists()) {
    return;
  }

  var source = await sourceFile.readAsString();
  final target = await targetFile.readAsString();
  if (stripManagedHotfixBlocks) {
    source = _stripManagedHotfixBlockContents(source);
  }
  source = _removeDuplicateAssetHotfixHeaders(source);

  final merged = _mergeIniSourceAdditions(
    targetContent: target,
    sourceContent: source,
  );
  if (merged != target) {
    await targetFile.writeAsString(merged);
  }
}

String _mergeIniSourceAdditions({
  required String targetContent,
  required String sourceContent,
}) {
  final lineEnding = targetContent.contains('\r\n')
      ? '\r\n'
      : (sourceContent.contains('\r\n') ? '\r\n' : '\n');
  final hadTrailingNewline =
      targetContent.endsWith('\n') || sourceContent.endsWith('\n');

  final targetSections = _parseIniSections(targetContent);
  final sourceSections = _parseIniSections(sourceContent);
  final targetByKey = <String, _IniSection>{};
  for (final section in targetSections) {
    targetByKey[section.key] = section;
  }

  for (final sourceSection in sourceSections) {
    final targetSection = targetByKey[sourceSection.key];
    if (targetSection == null) {
      targetSections.add(sourceSection.copy());
      targetByKey[sourceSection.key] = targetSections.last;
      continue;
    }

    final existingLines = targetSection.lines.toSet();
    for (final line in sourceSection.lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (existingLines.contains(line)) continue;
      targetSection.lines.add(line);
      existingLines.add(line);
    }
  }

  final rendered = _renderIniSections(
    targetSections,
    lineEnding: lineEnding,
    trailingNewline: hadTrailingNewline,
  );
  return _removeDuplicateAssetHotfixHeaders(rendered);
}

String mergeIniSourceAdditions({
  required String targetContent,
  required String sourceContent,
}) => _mergeIniSourceAdditions(
  targetContent: targetContent,
  sourceContent: sourceContent,
);

class _IniSection {
  _IniSection({required this.header, required this.lines});

  final String? header;
  final List<String> lines;

  String get key => (header ?? '').trim().toLowerCase();

  _IniSection copy() =>
      _IniSection(header: header, lines: List<String>.of(lines));
}

List<_IniSection> _parseIniSections(String content) {
  final sectionHeader = RegExp(r'^\[[^\r\n\]]+\]$');
  final sections = <_IniSection>[];
  var current = _IniSection(header: null, lines: <String>[]);
  sections.add(current);

  for (final line in content.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (sectionHeader.hasMatch(trimmed)) {
      current = _IniSection(header: trimmed, lines: <String>[]);
      sections.add(current);
      continue;
    }
    current.lines.add(line);
  }

  return sections;
}

String _renderIniSections(
  List<_IniSection> sections, {
  required String lineEnding,
  required bool trailingNewline,
}) {
  final lines = <String>[];
  for (final section in sections) {
    if (section.header != null) {
      lines.add(section.header!);
    }
    lines.addAll(section.lines);
  }
  var output = lines.join(lineEnding);
  if (trailingNewline && !output.endsWith(lineEnding)) {
    output = '$output$lineEnding';
  }
  return output;
}

String _removeDuplicateAssetHotfixHeaders(String content) {
  final lines = content.split(RegExp(r'\r?\n'));
  final output = <String>[];
  var seenAssetHotfix = false;
  for (final line in lines) {
    if (line.trim() == '[AssetHotfix]') {
      if (seenAssetHotfix) {
        continue;
      }
      seenAssetHotfix = true;
    }
    output.add(line);
  }
  return output.join('\n');
}

String removeDuplicateAssetHotfixHeaders(String content) =>
    _removeDuplicateAssetHotfixHeaders(content);

const Set<String> _managedHotfixBlockLabels = {
  'datatables',
  'straightbloom',
  'curvetables',
  'fixes',
};

class ManagedHotfixSnapshot {
  const ManagedHotfixSnapshot({
    this.dataTableLines = const [],
    this.hasActiveDataTableLines = false,
    this.straightBloomLines = const [],
    this.curveTableLines = const [],
    this.hasActiveCurveTableLines = false,
    this.hasActiveStraightBloomLines = false,
    this.fixesLines = const [],
  });

  final List<String> dataTableLines;
  final bool hasActiveDataTableLines;
  final List<String> straightBloomLines;
  final List<String> curveTableLines;
  final bool hasActiveCurveTableLines;
  final bool hasActiveStraightBloomLines;
  final List<String> fixesLines;
}

String? _normalizeHotfixLine(String line) {
  final trimmedLeft = line.trimLeft();
  if (trimmedLeft.isEmpty) return null;

  var normalized = trimmedLeft;
  if (normalized.startsWith(';')) {
    normalized = normalized.substring(1).trimLeft();
  }
  normalized = normalized.trimRight();
  return normalized.isEmpty ? null : normalized;
}

bool _isCommentedHotfixLine(String line) {
  return line.trimLeft().startsWith(';');
}

ManagedHotfixSnapshot extractManagedHotfixSnapshot({
  required String content,
  Iterable<String> straightBloomLines = const [],
}) {
  final straightBloomSet = straightBloomLines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet();
  final dataTableLines = <String>[];
  final capturedStraightBloomLines = <String>[];
  final curveTableLines = <String>[];
  final fixesLines = <String>[];
  final commentHeader = RegExp(r'^\s*#\s*(.+?)\s*$');
  final sectionHeader = RegExp(r'^\s*\[[^\r\n\]]+\]\s*$');
  var inAssetHotfix = false;
  String? activeBlock;
  var hasActiveDataTables = false;
  var hasActiveCurveTables = false;
  var hasActiveStraightBloom = false;

  for (final line in content.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (sectionHeader.hasMatch(trimmed)) {
      inAssetHotfix = trimmed.toLowerCase() == '[assethotfix]';
      activeBlock = null;
      continue;
    }
    if (!inAssetHotfix) continue;

    final commentMatch = commentHeader.firstMatch(line);
    if (commentMatch != null) {
      activeBlock = DataTableService._normalizeCommentLabel(
        commentMatch.group(1)!,
      );
      continue;
    }

    final normalizedLine = _normalizeHotfixLine(line);
    if (normalizedLine == null) continue;
    final isCommented = _isCommentedHotfixLine(line);

    if (straightBloomSet.contains(normalizedLine)) {
      capturedStraightBloomLines.add(normalizedLine);
      if (!isCommented) {
        hasActiveStraightBloom = true;
      }
      continue;
    }

    if (normalizedLine.startsWith('+CurveTable=')) {
      if (activeBlock == 'fixes') {
        fixesLines.add(normalizedLine);
        continue;
      }
      curveTableLines.add(normalizedLine);
      if (!isCommented) {
        hasActiveCurveTables = true;
      }
      continue;
    }

    if (!normalizedLine.startsWith('+DataTable=')) {
      if (activeBlock == 'fixes') {
        fixesLines.add(normalizedLine);
      }
      continue;
    }
    if (activeBlock == 'fixes') {
      fixesLines.add(normalizedLine);
      continue;
    }

    dataTableLines.add(normalizedLine);
    if (!isCommented) {
      hasActiveDataTables = true;
    }
  }

  return ManagedHotfixSnapshot(
    dataTableLines: ManagedHotfixService.mergeLines(const [], dataTableLines),
    hasActiveDataTableLines: hasActiveDataTables,
    straightBloomLines: ManagedHotfixService.mergeLines(
      const [],
      capturedStraightBloomLines,
    ),
    curveTableLines: ManagedHotfixService.mergeLines(const [], curveTableLines),
    hasActiveCurveTableLines: hasActiveCurveTables,
    hasActiveStraightBloomLines: hasActiveStraightBloom,
    fixesLines: ManagedHotfixService.mergeLines(const [], fixesLines),
  );
}

({
  List<String> dataTableLines,
  List<String> fixesLines,
  List<String> straightBloomLines,
  bool hasActiveStraightBloomLines,
})
extractImportedDataTableAndFixLines({
  required String content,
  Iterable<String> knownFixLines = const [],
  Iterable<String> knownStraightBloomLines = const [],
}) {
  final straightBloomLines = ManagedHotfixService.mergeLines(
    const [],
    knownStraightBloomLines.where(
      (line) => line.trim().startsWith('+DataTable='),
    ),
  );
  final snapshot = extractManagedHotfixSnapshot(
    content: content,
    straightBloomLines: straightBloomLines,
  );
  final allDataTableLines = ManagedHotfixService.mergeLines(
    const [],
    content
        .split(RegExp(r'\r?\n'))
        .map(_normalizeHotfixLine)
        .whereType<String>()
        .where((line) => line.startsWith('+DataTable=')),
  );
  final knownFixSet = ManagedHotfixService.mergeLines(
    const [],
    knownFixLines.where((line) => line.trim().startsWith('+DataTable=')),
  ).toSet();
  final managedMarkersPresent = RegExp(
    r'^\s*#\s*(data\s*tables|fixes)\b',
    caseSensitive: false,
    multiLine: true,
  ).hasMatch(content);
  final straightBloomSet = {
    ...straightBloomLines,
    ...snapshot.straightBloomLines,
  };
  final fixesSet = {
    ...snapshot.fixesLines.where((line) => line.startsWith('+DataTable=')),
    ...allDataTableLines.where(knownFixSet.contains),
  };
  final dataTableSet =
      (managedMarkersPresent ? snapshot.dataTableLines : allDataTableLines)
          .where(
            (line) =>
                !fixesSet.contains(line) && !straightBloomSet.contains(line),
          )
          .toSet();

  final dataTableLines = <String>[];
  final fixesLines = <String>[];
  final importedStraightBloomLines = <String>[];
  for (final line in allDataTableLines) {
    if (straightBloomSet.contains(line)) {
      importedStraightBloomLines.add(line);
      continue;
    }
    if (fixesSet.contains(line)) {
      fixesLines.add(line);
      continue;
    }
    if (dataTableSet.contains(line)) {
      dataTableLines.add(line);
    }
  }

  return (
    dataTableLines: ManagedHotfixService.mergeLines(const [], dataTableLines),
    fixesLines: ManagedHotfixService.mergeLines(const [], fixesLines),
    straightBloomLines: ManagedHotfixService.mergeLines(
      const [],
      importedStraightBloomLines,
    ),
    hasActiveStraightBloomLines: snapshot.hasActiveStraightBloomLines,
  );
}

String _stripManagedHotfixBlockContents(String content) {
  return _removeManagedHotfixArtifacts(content);
}

List<String> sanitizeManagedDataTableLines({
  required Iterable<String> dataTableLines,
  Iterable<String> straightBloomLines = const [],
  Iterable<String> fixesLines = const [],
}) {
  final excluded = {
    ...straightBloomLines.where(
      (line) => line.trim().startsWith('+DataTable='),
    ),
    ...fixesLines.where((line) => line.trim().startsWith('+DataTable=')),
  };
  return ManagedHotfixService.mergeLines(
    const [],
    dataTableLines.where((line) => !excluded.contains(line.trim())),
  );
}

String _removeManagedHotfixArtifacts(String content) {
  final lines = content.split(RegExp(r'\r?\n'));
  final output = <String>[];
  final commentHeader = RegExp(r'^\s*#\s*(.+?)\s*$');
  final sectionHeader = RegExp(r'^\s*\[[^\r\n\]]+\]\s*$');
  var inAssetHotfix = false;
  String? activeBlock;

  for (final line in lines) {
    final trimmed = line.trim();
    if (sectionHeader.hasMatch(trimmed)) {
      inAssetHotfix = trimmed.toLowerCase() == '[assethotfix]';
      activeBlock = null;
      output.add(line);
      continue;
    }
    if (!inAssetHotfix) {
      output.add(line);
      continue;
    }

    final commentMatch = commentHeader.firstMatch(line);
    if (commentMatch != null) {
      final normalized = DataTableService._normalizeCommentLabel(
        commentMatch.group(1)!,
      );
      activeBlock = normalized;
      if (_managedHotfixBlockLabels.contains(normalized)) {
        continue;
      }
      output.add(line);
      continue;
    }

    final normalizedLine = _normalizeHotfixLine(line);
    if (normalizedLine != null &&
        activeBlock != null &&
        _managedHotfixBlockLabels.contains(activeBlock)) {
      continue;
    }

    output.add(line);
  }

  return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

String rebuildManagedHotfixContent({
  required String content,
  required List<String> dataTableLines,
  required bool dataTablesEnabled,
  required List<String> straightBloomLines,
  required bool straightBloomEnabled,
  required List<String> curveTableLines,
  required bool curveTablesEnabled,
  required List<String> fixesLines,
}) {
  final lineEnding = content.contains('\r\n') ? '\r\n' : '\n';
  final trailingNewline = content.endsWith('\n');
  final managedBlockLines = <String>[];
  final sanitizedDataTableLines = sanitizeManagedDataTableLines(
    dataTableLines: dataTableLines,
    straightBloomLines: straightBloomLines,
    fixesLines: fixesLines,
  );

  void addBlock(String comment, Iterable<String> lines) {
    final normalizedLines = ManagedHotfixService.mergeLines(const [], lines);
    if (normalizedLines.isEmpty) return;
    managedBlockLines.add(comment);
    managedBlockLines.addAll(normalizedLines);
  }

  if (dataTablesEnabled) {
    addBlock(BackendPaths.dataTableComment, sanitizedDataTableLines);
  }
  if (straightBloomEnabled) {
    addBlock(BackendPaths.straightBloomComment, straightBloomLines);
  }
  if (curveTablesEnabled) {
    addBlock(BackendPaths.curveTableComment, curveTableLines);
  }
  addBlock(BackendPaths.fixesComment, fixesLines);

  final normalizedContent = _removeManagedHotfixArtifacts(
    _removeDuplicateAssetHotfixHeaders(content),
  );
  final lines = normalizedContent.split(RegExp(r'\r?\n')).toList();
  var assetIndex = lines.indexWhere((line) => line.trim() == '[AssetHotfix]');
  if (assetIndex == -1) {
    if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
      lines.add('');
    }
    lines.add('[AssetHotfix]');
    assetIndex = lines.length - 1;
  }

  if (managedBlockLines.isNotEmpty) {
    lines.insertAll(assetIndex + 1, managedBlockLines);
  }

  var output = lines.join(lineEnding);
  if (trailingNewline && !output.endsWith(lineEnding)) {
    output = '$output$lineEnding';
  }
  return output;
}

class ManagedHotfixService {
  static Future<void> ensureInitialized() async {
    await _migrateLegacyManagedStorageFiles();
    await _ensureManagedStorageFilesExist();
    await _migrateDataTableLines();
    await _migrateCurveTableLines();
    await _migrateStraightBloomLines();
    await _migrateFixesLines();
    await rebuildDefaultGame();
  }

  static Future<void> rebuildDefaultGame() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    final straightBloomLines =
        await StraightBloomService._readConfiguredLines();
    final fixesLines = await readLines(File(BackendPaths.fixesLinesIni));
    final dataTableFile = File(BackendPaths.dataTableLinesIni);
    final dataTableLines = sanitizeManagedDataTableLines(
      dataTableLines: await readLines(dataTableFile),
      straightBloomLines: straightBloomLines,
      fixesLines: fixesLines,
    );
    await writeLines(dataTableFile, dataTableLines);
    final curveLines = await readLines(File(BackendPaths.curveTableLinesIni));
    final content = rebuildManagedHotfixContent(
      content: await iniFile.readAsString(),
      dataTableLines: dataTableLines,
      dataTablesEnabled: await DataTableService.getUIEnabledState(),
      straightBloomLines: straightBloomLines,
      straightBloomEnabled: await StraightBloomService._readEnabledState(),
      curveTableLines: curveLines,
      curveTablesEnabled: await CurveTableService._readGlobalEnabledState(),
      fixesLines: fixesLines,
    );

    await iniFile.writeAsString(content);
    await DataTableService.ensureAtlasTextHotfixInDefaultGame();
  }

  static Future<List<String>> readLines(File file) async {
    if (!await file.exists()) return const [];
    final lines = await file.readAsLines();
    return _normalizeLines(lines);
  }

  static Future<void> writeLines(File file, Iterable<String> lines) async {
    final normalized = _normalizeLines(lines);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      normalized.isEmpty ? '' : '${normalized.join('\n')}\n',
    );
  }

  static Future<void> _ensureManagedStorageFilesExist() async {
    for (final path in [
      BackendPaths.curveTableLinesIni,
      BackendPaths.dataTableLinesIni,
      BackendPaths.straightBloomLinesIni,
      BackendPaths.fixesLinesIni,
    ]) {
      final file = File(path);
      if (await file.exists()) continue;
      await file.parent.create(recursive: true);
      await file.writeAsString('');
    }
  }

  static Future<void> _migrateLegacyManagedStorageFiles() async {
    await _migrateLegacyManagedStorageFile(
      legacyPath: BackendPaths.legacyCurveTableLinesIni,
      targetPath: BackendPaths.curveTableLinesIni,
    );
    await _migrateLegacyManagedStorageFile(
      legacyPath: BackendPaths.legacyDataTableLinesIni,
      targetPath: BackendPaths.dataTableLinesIni,
    );
  }

  static Future<void> _migrateLegacyManagedStorageFile({
    required String legacyPath,
    required String targetPath,
  }) async {
    if (_samePath(legacyPath, targetPath)) return;

    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) return;

    final legacyLines = await readLines(legacyFile);
    final targetFile = File(targetPath);
    final targetLines = await readLines(targetFile);
    final merged = mergeLines(targetLines, legacyLines);

    if (merged.length != targetLines.length || !await targetFile.exists()) {
      await writeLines(targetFile, merged);
    }

    try {
      await legacyFile.delete();
    } catch (_) {}
  }

  static List<String> mergeLines(
    Iterable<String> primary,
    Iterable<String> secondary,
  ) {
    final merged = <String>[];
    final seen = <String>{};
    for (final source in [primary, secondary]) {
      for (final rawLine in source) {
        final line = rawLine.trim();
        if (line.isEmpty || !seen.add(line)) continue;
        merged.add(line);
      }
    }
    return merged;
  }

  static Future<void> _migrateDataTableLines() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    final content = await iniFile.readAsString();
    final snapshot = extractManagedHotfixSnapshot(
      content: content,
      straightBloomLines: await StraightBloomService._readConfiguredLines(),
    );
    final targetFile = File(BackendPaths.dataTableLinesIni);
    final existing = await readLines(targetFile);
    final merged = mergeLines(existing, snapshot.dataTableLines);
    if (merged.length != existing.length) {
      await writeLines(targetFile, merged);
    }
  }

  static Future<void> _migrateCurveTableLines() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    final content = await iniFile.readAsString();
    final snapshot = extractManagedHotfixSnapshot(content: content);
    final targetFile = File(BackendPaths.curveTableLinesIni);
    final existing = await readLines(targetFile);

    final legacyBackupFile = File(BackendPaths.modificationsBackup);
    final legacyDisabledLines = <String>[];
    if (await legacyBackupFile.exists()) {
      try {
        final json =
            jsonDecode(await legacyBackupFile.readAsString())
                as Map<String, dynamic>;
        legacyDisabledLines.addAll(
          (json['curveTableLines'] as List<dynamic>? ?? [])
              .whereType<String>()
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty),
        );
      } catch (_) {}
      try {
        await legacyBackupFile.delete();
      } catch (_) {}
    }

    final merged = mergeLines(existing, [
      ...legacyDisabledLines,
      ...snapshot.curveTableLines,
    ]);
    if (merged.length != existing.length) {
      await writeLines(targetFile, merged);
    }
  }

  static Future<void> _migrateStraightBloomLines() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    final targetFile = File(BackendPaths.straightBloomLinesIni);
    final existing = await readLines(targetFile);
    final snapshot = extractManagedHotfixSnapshot(
      content: await iniFile.readAsString(),
      straightBloomLines: existing,
    );
    final merged = mergeLines(existing, snapshot.straightBloomLines);
    if (merged.length != existing.length || !await targetFile.exists()) {
      await writeLines(targetFile, merged);
    }
  }

  static Future<void> _migrateFixesLines() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    final snapshot = extractManagedHotfixSnapshot(
      content: await iniFile.readAsString(),
      straightBloomLines: await StraightBloomService._readConfiguredLines(),
    );
    final targetFile = File(BackendPaths.fixesLinesIni);
    final existing = await readLines(targetFile);
    final merged = mergeLines(existing, snapshot.fixesLines);
    if (merged.length != existing.length || !await targetFile.exists()) {
      await writeLines(targetFile, merged);
    }
  }

  static List<String> _normalizeLines(Iterable<String> lines) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || !seen.add(line)) continue;
      normalized.add(line);
    }
    return normalized;
  }
}

class StraightBloomService {
  static Future<bool> isEnabled() async {
    return _readEnabledState();
  }

  static Future<void> setEnabled(
    bool enabled, {
    bool syncUserToggleStates = true,
  }) async {
    await _writeEnabledState(
      enabled,
      syncUserToggleStates: syncUserToggleStates,
    );
    await ManagedHotfixService.rebuildDefaultGame();
  }

  static Future<void> _writeEnabledState(
    bool enabled, {
    bool syncUserToggleStates = true,
  }) async {
    if (syncUserToggleStates) {
      await UserToggleStatesService.updateState(
        (current) => current.copyWith(straightBloomEnabled: enabled),
      );
    }
  }

  static Future<void> importFromIni(String importPath) async {
    final source = File(importPath);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();
    final block = _extractLastHotfixBlock(importContent);
    if (block.trim().isEmpty) return;
    final blockLines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.startsWith(';') ? line.substring(1) : line)
        .toSet();
    final sniperLines = await _readConfiguredLines();
    final hasAll = sniperLines.every((line) => blockLines.contains(line));
    await setEnabled(hasAll);
  }

  static Future<bool> _readEnabledState() async {
    final saved = await UserToggleStatesService.readSavedBool(
      'straightBloomEnabled',
    );
    if (saved != null) {
      return saved;
    }
    final stateFile = File(BackendPaths.straightBloomStateJson);
    if (await stateFile.exists()) {
      try {
        final json =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        return json['enabled'] == true;
      } catch (_) {}
    }
    return _detectEnabledFromDefaultGame();
  }

  static Future<bool> _detectEnabledFromDefaultGame() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return false;
    final snapshot = extractManagedHotfixSnapshot(
      content: await iniFile.readAsString(),
      straightBloomLines: await _readConfiguredLines(),
    );
    return snapshot.hasActiveStraightBloomLines;
  }

  static Future<List<String>> _readConfiguredLines() async {
    return ManagedHotfixService.readLines(
      File(BackendPaths.straightBloomLinesIni),
    );
  }
}

class CurveEntry {
  const CurveEntry({
    required this.id,
    required this.name,
    required this.key,
    required this.type,
    required this.pathPart,
    required this.staticValue,
    required this.isCustom,
    required this.multiLines,
    this.groupId,
    this.groupName,
    this.groupImagePath,
  });

  final String id;
  final String name;
  final String key;
  final String type;
  final String? pathPart;
  final String? staticValue;
  final bool isCustom;
  final List<String> multiLines;
  final String? groupId;
  final String? groupName;
  final String? groupImagePath;
}

class CustomCurveInput {
  const CustomCurveInput({
    required this.name,
    required this.key,
    required this.pathPart,
    required this.lines,
    required this.staticValue,
    required this.isStatic,
    required this.groupId,
    required this.groupName,
    required this.groupImagePath,
    required this.groupImageSourcePath,
  });

  final String name;
  final String key;
  final String pathPart;
  final List<String> lines;
  final String staticValue;
  final bool isStatic;
  final String groupId;
  final String groupName;
  final String groupImagePath;
  final String groupImageSourcePath;
}

class CustomCurveGroupInfo {
  const CustomCurveGroupInfo({
    required this.id,
    required this.name,
    required this.imagePath,
  });

  final String id;
  final String name;
  final String? imagePath;
}

class DataTableWeapon {
  const DataTableWeapon({
    required this.id,
    required this.name,
    required this.weaponId,
    required this.weaponPath,
    required this.imagePath,
    required this.damageFields,
    required this.environmentalDamageFields,
    required this.damagePB,
    required this.defaultEnvDamage,
    this.variants,
    this.clipSize,
  });

  final String id;
  final String name;
  final String weaponId;
  final String weaponPath;
  final String? imagePath;
  final List<String> damageFields;
  final List<String> environmentalDamageFields;
  final String damagePB;
  final String defaultEnvDamage;
  final List<WeaponVariant>? variants;
  final String? clipSize;
}

class WeaponVariant {
  const WeaponVariant({
    required this.name,
    required this.weaponId,
    required this.damagePB,
    required this.defaultEnvDamage,
    this.imagePath,
    this.reloadTime,
  });

  final String name;
  final String weaponId;
  final String damagePB;
  final String defaultEnvDamage;
  final String? imagePath;
  final String? reloadTime;
}

class DataTableSettings {
  const DataTableSettings({
    required this.damageEnabled,
    required this.envDamageEnabled,
    required this.advancedMode,
    required this.damageValue,
    required this.envDamageValue,
    required this.customValues,
    required this.clipSizeEnabled,
    required this.clipSizeValue,
    required this.reloadTimeEnabled,
    required this.reloadTimeValue,
  });

  final bool damageEnabled;
  final bool envDamageEnabled;
  final bool advancedMode;
  final String damageValue;
  final String envDamageValue;
  final Map<String, String> customValues;
  final bool clipSizeEnabled;
  final String clipSizeValue;
  final bool reloadTimeEnabled;
  final String reloadTimeValue;

  DataTableSettings copyWith({
    bool? damageEnabled,
    bool? envDamageEnabled,
    bool? advancedMode,
    String? damageValue,
    String? envDamageValue,
    Map<String, String>? customValues,
    bool? clipSizeEnabled,
    String? clipSizeValue,
    bool? reloadTimeEnabled,
    String? reloadTimeValue,
  }) {
    return DataTableSettings(
      damageEnabled: damageEnabled ?? this.damageEnabled,
      envDamageEnabled: envDamageEnabled ?? this.envDamageEnabled,
      advancedMode: advancedMode ?? this.advancedMode,
      damageValue: damageValue ?? this.damageValue,
      envDamageValue: envDamageValue ?? this.envDamageValue,
      customValues: customValues ?? this.customValues,
      clipSizeEnabled: clipSizeEnabled ?? this.clipSizeEnabled,
      clipSizeValue: clipSizeValue ?? this.clipSizeValue,
      reloadTimeEnabled: reloadTimeEnabled ?? this.reloadTimeEnabled,
      reloadTimeValue: reloadTimeValue ?? this.reloadTimeValue,
    );
  }
}

class VictoryTextReplacementSettings {
  const VictoryTextReplacementSettings({
    required this.enabled,
    required this.placement,
    required this.victory,
    required this.royale,
  });

  static const String defaultPlacement = '1';
  static const String defaultVictory = 'VICTORY';
  static const String defaultRoyale = 'ROYALE';
  static const VictoryTextReplacementSettings defaultSettings =
      VictoryTextReplacementSettings(
        enabled: false,
        placement: defaultPlacement,
        victory: defaultVictory,
        royale: defaultRoyale,
      );

  final bool enabled;
  final String placement;
  final String victory;
  final String royale;

  bool get usesDefaultText =>
      placement == defaultPlacement &&
      victory == defaultVictory &&
      royale == defaultRoyale;

  VictoryTextReplacementSettings copyWith({
    bool? enabled,
    String? placement,
    String? victory,
    String? royale,
  }) {
    return VictoryTextReplacementSettings(
      enabled: enabled ?? this.enabled,
      placement: placement ?? this.placement,
      victory: victory ?? this.victory,
      royale: royale ?? this.royale,
    );
  }
}

const List<CurveGroup> _baseCurveGroups = [
  CurveGroup(
    id: 'shockwave',
    title: 'Shockwave',
    imageName: 'shock.webp',
    icon: Icons.waves,
    keywords: ['shockwave'],
  ),
  CurveGroup(
    id: 'impulse',
    title: 'Impulse',
    imageName: 'impulse.webp',
    icon: Icons.bolt,
    keywords: ['impulse', 'knockgrenade'],
  ),
  CurveGroup(
    id: 'boogie',
    title: 'Boogie',
    imageName: 'boogie.webp',
    icon: Icons.music_note,
    keywords: ['boogie', 'dancegrenade'],
  ),
  CurveGroup(
    id: 'chiller',
    title: 'Chiller',
    imageName: 'chiller.webp',
    icon: Icons.ac_unit,
    keywords: ['chiller', 'icegrenade'],
  ),
  CurveGroup(
    id: 'rift',
    title: 'Rift',
    imageName: 'rift.webp',
    icon: Icons.public,
    keywords: ['rift'],
  ),
  CurveGroup(
    id: 'hopflopper',
    title: 'Hop Flopper',
    imageName: 'hopflop.webp',
    icon: Icons.set_meal,
    keywords: ['hop flopper', 'hopflopper'],
  ),
  CurveGroup(
    id: 'glider',
    title: 'Glider Redeploy',
    imageName: 'glider.webp',
    icon: Icons.paragliding_rounded,
    keywords: ['glider', 'redeploy', 'parachute'],
  ),
  CurveGroup(
    id: 'bouncer',
    title: 'Bouncer',
    imageName: 'bouncer.webp',
    icon: Icons.unfold_more_double,
    keywords: ['bouncer', 'bouncepad', 'bounce pad'],
  ),
  CurveGroup(
    id: 'launchpad',
    title: 'Launch Pad',
    imageName: 'launch.webp',
    icon: Icons.flight_takeoff,
    keywords: ['launch pad', 'launchpad'],
  ),
  CurveGroup(
    id: 'crashpad',
    title: 'Crash Pad',
    imageName: 'crashpad.webp',
    icon: Icons.airline_seat_legroom_extra,
    keywords: ['crash pad', 'applesun', 'crashpad'],
  ),
  CurveGroup(
    id: 'runevent',
    title: 'Rune Vent',
    imageName: 'runevent.webp',
    icon: Icons.air,
    keywords: ['rune vent', 'runevent'],
  ),
  CurveGroup(
    id: 'cube',
    title: 'Cube',
    imageName: 'cube.webp',
    icon: Icons.crop_square,
    keywords: ['cube'],
  ),
  CurveGroup(
    id: 'flint',
    title: 'Flint-Knock',
    imageName: 'flintknock.webp',
    icon: Icons.local_fire_department,
    keywords: ['flint', 'flintlock'],
  ),
  CurveGroup(
    id: 'dub',
    title: 'Dub',
    imageName: 'dub.webp',
    icon: Icons.gavel,
    keywords: ['dub'],
  ),
  CurveGroup(
    id: 'jules',
    title: 'Jules',
    imageName: 'jules.webp',
    icon: Icons.person,
    keywords: ['jules', 'grappler', 'grapplinghoot'],
  ),
  CurveGroup(
    id: 'fall',
    title: 'Player',
    imageName: 'fall.webp',
    icon: Icons.heart_broken,
    keywords: [
      'fall damage',
      'falling',
      'neutralediting',
      'sliding',
      'safezone',
    ],
  ),
  CurveGroup(
    id: 'ammunition',
    title: 'Ammunition',
    imageName: 'ammo.webp',
    icon: Icons.inventory_2,
    keywords: ['ammo', 'ammunition'],
  ),
  CurveGroup(
    id: 'materials',
    title: 'Materials',
    imageName: 'materials.webp',
    icon: Icons.forest,
    keywords: ['materials', 'maxstack.resources'],
  ),
  CurveGroup(
    id: 'heals',
    title: 'Heals',
    imageName: 'heals.webp',
    icon: Icons.healing,
    keywords: [
      'shield',
      'bandage',
      'purplestuff',
      'chillbronco',
      'flopper.heal',
      'floppereffective',
      'donut',
    ],
  ),
];

List<CustomCurveGroupInfo> _customGroupsFromCurves(
  List<CurveEntry> curves, {
  Set<String> excludeIds = const {},
}) {
  final map = <String, CustomCurveGroupInfo>{};
  for (final entry in curves) {
    final groupId = entry.groupId;
    if (groupId == null || groupId.isEmpty) continue;
    if (excludeIds.contains(groupId)) continue;
    final existing = map[groupId];
    if (existing == null) {
      map[groupId] = CustomCurveGroupInfo(
        id: groupId,
        name: entry.groupName ?? 'Custom',
        imagePath: entry.groupImagePath,
      );
    } else if (existing.imagePath == null && entry.groupImagePath != null) {
      map[groupId] = CustomCurveGroupInfo(
        id: groupId,
        name: existing.name,
        imagePath: entry.groupImagePath,
      );
    }
  }
  return map.values.toList();
}

List<CustomCurveGroupInfo> _groupInfosForPrompt(List<CurveEntry> curves) {
  final builtinIds = _baseCurveGroups.map((group) => group.id).toSet();
  final builtinInfos = _baseCurveGroups
      .map(
        (group) => CustomCurveGroupInfo(
          id: group.id,
          name: group.title,
          imagePath: null,
        ),
      )
      .toList();
  final customInfos = _customGroupsFromCurves(curves, excludeIds: builtinIds);
  final hasOther =
      builtinInfos.any((group) => group.id == 'other') ||
      customInfos.any((group) => group.id == 'other');
  return [
    ...builtinInfos,
    ...customInfos,
    if (!hasOther)
      const CustomCurveGroupInfo(id: 'other', name: 'Other', imagePath: null),
  ];
}

String _humanizeCurveKey(String key) {
  final last = key.split('.').last;
  return last
      .replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match.group(0)}')
      .trim();
}

String _stripScheme(String url) {
  return url.replaceFirst(RegExp(r'^https?://'), '');
}

class _CustomCurveDraft {
  _CustomCurveDraft()
    : nameController = TextEditingController(),
      linesController = TextEditingController(),
      isStatic = false;

  final TextEditingController nameController;
  final TextEditingController linesController;
  bool isStatic;
}

class _CustomGroupEditResult {
  const _CustomGroupEditResult({required this.name, required this.imagePath});

  final String name;
  final String? imagePath;
}

class CustomCurveEditResult {
  const CustomCurveEditResult({
    required this.name,
    required this.lines,
    required this.staticValue,
    required this.isStatic,
    required this.key,
    required this.pathPart,
    required this.groupId,
    required this.groupName,
    required this.groupImagePath,
  });

  final String name;
  final List<String> lines;
  final String staticValue;
  final bool isStatic;
  final String key;
  final String pathPart;
  final String groupId;
  final String groupName;
  final String? groupImagePath;
}

class _ImportCurveDraft {
  _ImportCurveDraft({
    required this.key,
    required this.pathPart,
    required this.lines,
    required this.staticValue,
  }) : nameController = TextEditingController(),
       selectedGroupId = '';

  final String key;
  final String pathPart;
  final List<String> lines;
  final String staticValue;
  final TextEditingController nameController;
  String selectedGroupId;
}

String? _normalizeCustomGroupImagePath(Object? rawPath) {
  final value = rawPath?.toString().trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  final normalized = value.replaceAll('\\', '/');
  if (!normalized.startsWith('custom-groups/')) {
    return null;
  }
  return normalized;
}

List<String> customGroupImagePathsToDelete(
  Map<String, dynamic> curveMap,
  String deletedGroupId,
) {
  final deletedPaths = <String>{};
  final remainingPaths = <String>{};

  for (final value in curveMap.values) {
    if (value is! Map) {
      continue;
    }
    final data = Map<String, dynamic>.from(value);
    final imagePath = _normalizeCustomGroupImagePath(
      data['groupImagePath'] ?? data['imagePath'],
    );
    if (imagePath == null) {
      continue;
    }

    if (data['isCustom'] == true && data['groupId'] == deletedGroupId) {
      deletedPaths.add(imagePath);
    } else {
      remainingPaths.add(imagePath);
    }
  }

  final orphanedPaths = deletedPaths.difference(remainingPaths).toList();
  orphanedPaths.sort();
  return orphanedPaths;
}

class CurveTableService {
  static CurveEntry _entryFromJson(String id, Map<String, dynamic> data) {
    return CurveEntry(
      id: id,
      name: data['name'] ?? 'Curve $id',
      key: data['key'] ?? '',
      type: data['type'] ?? 'amount',
      pathPart: data['pathPart'],
      staticValue: data['staticValue'],
      isCustom: data['isCustom'] == true,
      multiLines:
          (data['multiLines'] as List<dynamic>?)?.cast<String>() ?? const [],
      groupId: data['groupId'],
      groupName: data['groupName'],
      groupImagePath: data['groupImagePath'] ?? data['imagePath'],
    );
  }

  static String _curveSignature(Map<String, dynamic> data) {
    final key = (data['key'] as String? ?? '').trim().toLowerCase();
    if (key.isEmpty) return '';
    final rawPathPart = (data['pathPart'] as String?)?.trim() ?? '';
    final pathPart = rawPathPart.isEmpty
        ? BackendPaths.defaultCurvePath
        : rawPathPart;
    return '${pathPart.toLowerCase()}|||$key';
  }

  static Future<Map<String, dynamic>?> _readCurveMap(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCurveMap(
    File file,
    Map<String, dynamic> map,
  ) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<Map<String, dynamic>?> _loadDefaultCurveMap() async {
    final candidates = <String>[
      joinPath([getInstallationRoot(), 'responses', 'curves.defaults.json']),
      joinPath([getInstallationRoot(), 'responses', 'curves.json']),
      BackendPaths.curvesDefaultsJson,
    ];

    for (final candidate in candidates) {
      final map = await _readCurveMap(File(candidate));
      if (map != null && map.isNotEmpty) {
        return map;
      }
    }

    return null;
  }

  static Future<void> _mergeMissingDefaultCurves() async {
    final curvesFile = File(BackendPaths.curvesJson);
    final defaults = await _loadDefaultCurveMap();
    if (defaults == null || defaults.isEmpty) return;

    if (!await curvesFile.exists()) {
      await _writeCurveMap(curvesFile, defaults);
      return;
    }

    final current = await _readCurveMap(curvesFile);
    if (current == null) return;

    final existingSignatures = <String>{};
    for (final value in current.values) {
      if (value is! Map) continue;
      final signature = _curveSignature(Map<String, dynamic>.from(value));
      if (signature.isNotEmpty) {
        existingSignatures.add(signature);
      }
    }

    var maxId = 0;
    for (final id in current.keys) {
      final parsed = int.tryParse(id);
      if (parsed != null && parsed > maxId) {
        maxId = parsed;
      }
    }

    var changed = false;
    final defaultEntries = defaults.entries.toList()
      ..sort((a, b) {
        final aId = int.tryParse(a.key) ?? (1 << 30);
        final bId = int.tryParse(b.key) ?? (1 << 30);
        return aId.compareTo(bId);
      });

    for (final entry in defaultEntries) {
      if (entry.value is! Map) continue;
      final curveData = Map<String, dynamic>.from(entry.value);
      final signature = _curveSignature(curveData);
      if (signature.isEmpty || existingSignatures.contains(signature)) {
        continue;
      }
      maxId += 1;
      current['$maxId'] = jsonDecode(jsonEncode(curveData));
      existingSignatures.add(signature);
      changed = true;
    }

    if (changed) {
      await _writeCurveMap(curvesFile, current);
    }
  }

  static Future<List<CurveEntry>> loadCurves() async {
    await _mergeMissingDefaultCurves();
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return [];
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final entries = map.entries.map((entry) {
      final data = entry.value as Map<String, dynamic>;
      return _entryFromJson(entry.key, data);
    }).toList();
    entries.sort((a, b) => a.id.compareTo(b.id));
    return entries;
  }

  static Future<bool> areGlobalEnabled() async {
    return _readGlobalEnabledState();
  }

  static Future<void> toggleGlobal() async {
    await _writeGlobalEnabledState(!(await _readGlobalEnabledState()));
    await ManagedHotfixService.rebuildDefaultGame();
  }

  static _CurveEntryResolvedState _resolveCurveState(
    String content,
    CurveEntry entry,
  ) {
    if (entry.multiLines.isNotEmpty) {
      var enabled = true;
      for (final line in entry.multiLines) {
        final parts = _splitCurveLine(line);
        if (parts == null) {
          enabled = false;
          break;
        }
        final regex = RegExp(
          '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
          multiLine: true,
        );
        if (!regex.hasMatch(content)) {
          enabled = false;
          break;
        }
      }
      final escapedKey = RegExp.escape(entry.key);
      final regex = RegExp(
        '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;(.+)\$',
        multiLine: true,
      );
      final match = regex.firstMatch(content);
      return _CurveEntryResolvedState(
        enabled: enabled,
        value: match?.group(1) ?? entry.staticValue,
      );
    }

    final escapedKey = RegExp.escape(entry.key);
    final regex = RegExp(
      '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;(.+)\$',
      multiLine: true,
    );
    final match = regex.firstMatch(content);
    return _CurveEntryResolvedState(
      enabled: match != null,
      value: match?.group(1),
    );
  }

  static Future<Map<String, _CurveEntryResolvedState>> _loadCurveStates(
    Iterable<CurveEntry> entries,
  ) async {
    final content = await _readConfiguredContent();
    if (content.isEmpty) {
      return <String, _CurveEntryResolvedState>{
        for (final entry in entries) entry.id: const _CurveEntryResolvedState(),
      };
    }
    final states = <String, _CurveEntryResolvedState>{};
    for (final entry in entries) {
      states[entry.id] = _resolveCurveState(content, entry);
    }
    return states;
  }

  static Future<bool> isCurveEnabled(CurveEntry entry) async {
    final content = await _readConfiguredContent();
    if (content.isEmpty) return false;
    return _resolveCurveState(content, entry).enabled;
  }

  static Future<String?> getCurrentValue(CurveEntry entry) async {
    final content = await _readConfiguredContent();
    if (content.isEmpty) return null;
    return _resolveCurveState(content, entry).value;
  }

  static Future<void> setCurveEnabled(
    CurveEntry entry,
    bool enabled, {
    String? customValue,
  }) async {
    var content = await _readConfiguredContent();
    if (!enabled) {
      if (entry.multiLines.isNotEmpty) {
        for (final line in entry.multiLines) {
          final parts = _splitCurveLine(line);
          if (parts == null) continue;
          final regex = RegExp(
            '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
            multiLine: true,
          );
          content = content.replaceAll(regex, '');
        }
      } else {
        final escapedKey = RegExp.escape(entry.key);
        final regex = RegExp(
          '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$',
          multiLine: true,
        );
        content = content.replaceAll(regex, '');
      }
      content = content.replaceAll(RegExp('\n\n+'), '\n');
      await _writeConfiguredContent(content);
      if (await _readGlobalEnabledState()) {
        await ManagedHotfixService.rebuildDefaultGame();
      }
      return;
    }

    if (entry.multiLines.isNotEmpty) {
      for (final line in entry.multiLines) {
        final parts = _splitCurveLine(line);
        if (parts == null) continue;
        final regex = RegExp(
          '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
          multiLine: true,
        );
        content = content.replaceAll(regex, '');
      }
    } else {
      final escapedKey = RegExp.escape(entry.key);
      final regex = RegExp(
        '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$',
        multiLine: true,
      );
      content = content.replaceAll(regex, '');
    }
    content = content.replaceAll(RegExp('\n\n+'), '\n');

    if (entry.multiLines.isNotEmpty) {
      final lines = entry.multiLines.map((line) {
        if (entry.type == 'amount' && customValue != null) {
          return _replaceCurveLineValue(line, customValue);
        }
        return line;
      }).toList();
      content = [
        content.trim(),
        lines.join('\n'),
      ].where((value) => value.isNotEmpty).join('\n');
    } else {
      final pathPart = entry.pathPart ?? BackendPaths.defaultCurvePath;
      final value = entry.type == 'static'
          ? (entry.staticValue ?? '0')
          : (customValue ?? '0');
      final line = '+CurveTable=$pathPart;RowUpdate;${entry.key};0;$value';
      content = [
        content.trim(),
        line,
      ].where((value) => value.isNotEmpty).join('\n');
    }
    await _writeConfiguredContent(content);
    if (await _readGlobalEnabledState()) {
      await ManagedHotfixService.rebuildDefaultGame();
    }
  }

  static Future<void> importFromIni(String importPath) async {
    final source = File(importPath);
    final target = File(BackendPaths.defaultGameIni);
    if (!await source.exists() || !await target.exists()) return;
    final importContent = await source.readAsString();
    final filteredContent = _extractLastHotfixBlock(importContent);
    if (filteredContent.trim().isEmpty) {
      return;
    }
    final regex = RegExp(
      '^\\s*;?\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$',
      multiLine: true,
    );
    final matches = regex.allMatches(filteredContent).toList();
    if (matches.isEmpty) return;

    final grouped = <String, List<String>>{};
    final allNormalized = <String>[];
    for (final match in matches) {
      final pathPart = match.group(1)!.trim();
      final key = match.group(2)!.trim();
      final rawLine = match.group(0)!.trim();
      final isCommented = rawLine.startsWith(';');
      final normalized = rawLine.startsWith(';')
          ? rawLine.substring(1).trim()
          : rawLine;
      allNormalized.add(normalized);
      final groupKey = '$pathPart|||$key';
      if (!isCommented) {
        grouped.putIfAbsent(groupKey, () => []).add(normalized);
      }
    }

    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) {
      await _writeCurveMap(curvesFile, const <String, dynamic>{});
    }

    final existing = await CurveTableService.loadCurves();
    final existingKeys = existing
        .map(
          (entry) =>
              '${(entry.pathPart ?? BackendPaths.defaultCurvePath).trim()}|||${entry.key.trim()}',
        )
        .toSet();

    final missing = <CustomCurveInput>[];
    for (final entry in grouped.entries) {
      if (existingKeys.contains(entry.key)) continue;
      final parts = entry.key.split('|||');
      final key = parts[1];
      missing.add(
        CustomCurveInput(
          name: _humanizeKey(key),
          key: key,
          pathPart: parts[0],
          lines: entry.value,
          staticValue: '0',
          isStatic: false,
          groupId: 'other',
          groupName: 'Other',
          groupImagePath: '',
          groupImageSourcePath: '',
        ),
      );
    }

    if (missing.isNotEmpty) {
      await CurveTableService.addCustomCurves(missing);
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final activeLines = entry.value;
      if (activeLines.isNotEmpty) {
        await CurveTableService.applyCurveLines(
          parts[0],
          parts[1],
          activeLines,
        );
      }
    }

    if (matches.isNotEmpty) {
      final activeLines = grouped.values
          .expand((lines) => lines)
          .toList(growable: false);
      final normalized = activeLines.isEmpty ? allNormalized : activeLines;
      await ManagedHotfixService.writeLines(
        File(BackendPaths.curveTableLinesIni),
        normalized,
      );
      await _writeGlobalEnabledState(activeLines.isNotEmpty);
      await ManagedHotfixService.rebuildDefaultGame();
    }
  }

  static String? _extractBlock(String content, String label) {
    final lines = content.split('\n');
    final startIndex = lines.indexWhere(
      (line) => line.trim() == label || line.trim().startsWith(label),
    );
    if (startIndex == -1) return null;
    final buffer = <String>[];
    for (var i = startIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#') || line.startsWith('[')) break;
      buffer.add(line);
    }
    return buffer.join('\n');
  }

  static Future<void> applyCurveLines(
    String pathPart,
    String key,
    List<String> lines,
  ) async {
    var content = await _readConfiguredContent();
    for (final line in lines) {
      final parts = _splitCurveLine(line);
      if (parts == null) continue;
      final regex = RegExp(
        '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
        multiLine: true,
      );
      content = content.replaceAll(regex, '');
    }
    content = content.replaceAll(RegExp('\n\n+'), '\n');
    content = [
      content.trim(),
      lines.join('\n'),
    ].where((value) => value.isNotEmpty).join('\n');
    content = content.replaceAll(RegExp(r'\n\n+'), '\n');
    await _writeConfiguredContent(content);
    if (await _readGlobalEnabledState()) {
      await ManagedHotfixService.rebuildDefaultGame();
    }
  }

  static Future<void> clearAllCurveTables() async {
    final curvesFile = File(BackendPaths.curvesJson);
    await ManagedHotfixService.writeLines(
      File(BackendPaths.curveTableLinesIni),
      const [],
    );
    await _writeGlobalEnabledState(false);
    await ManagedHotfixService.rebuildDefaultGame();

    // Remove all entries in the "Other" group
    if (await curvesFile.exists()) {
      final curvesContent = await curvesFile.readAsString();
      final curvesData = jsonDecode(curvesContent) as Map<String, dynamic>;
      curvesData.removeWhere((_, value) {
        if (value is! Map<String, dynamic>) return false;
        return value['groupId'] == 'other';
      });
      await _writeCurveMap(curvesFile, curvesData);
    }
  }

  static Future<void> addCustomCurve(CustomCurveInput input) async {
    await addCustomCurves([input]);
  }

  static Future<void> addCustomCurves(List<CustomCurveInput> inputs) async {
    if (inputs.isEmpty) return;
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    var nextId =
        (map.keys
            .map(int.tryParse)
            .whereType<int>()
            .fold(0, (a, b) => a > b ? a : b)) +
        1;
    final groupImageCache = <String, String>{};

    for (final input in inputs) {
      var storedGroupImagePath = input.groupImagePath;
      if (storedGroupImagePath.isEmpty) {
        storedGroupImagePath = groupImageCache[input.groupId] ?? '';
      }
      if (storedGroupImagePath.isEmpty &&
          input.groupImageSourcePath.isNotEmpty) {
        final source = File(input.groupImageSourcePath);
        if (await source.exists()) {
          final destDir = Directory(
            joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
          );
          await destDir.create(recursive: true);
          final fileName = source.uri.pathSegments.last;
          final stampedName =
              '${DateTime.now().millisecondsSinceEpoch}_$fileName';
          storedGroupImagePath = joinPath(['custom-groups', stampedName]);
          await source.copy(joinPath([destDir.path, stampedName]));
        }
      }
      if (storedGroupImagePath.isNotEmpty) {
        groupImageCache[input.groupId] = storedGroupImagePath;
      }

      map[nextId.toString()] = {
        'name': input.name,
        'key': input.key,
        'type': input.isStatic ? 'static' : 'amount',
        'pathPart': input.pathPart,
        if (input.isStatic) 'staticValue': input.staticValue,
        'isCustom': true,
        'multiLines': input.lines,
        'groupId': input.groupId,
        'groupName': input.groupName,
        if (storedGroupImagePath.isNotEmpty)
          'groupImagePath': storedGroupImagePath,
      };

      final entry = CurveEntry(
        id: nextId.toString(),
        name: input.name,
        key: input.key,
        type: input.isStatic ? 'static' : 'amount',
        pathPart: input.pathPart,
        staticValue: input.isStatic ? input.staticValue : null,
        isCustom: true,
        multiLines: input.lines,
        groupId: input.groupId,
        groupName: input.groupName,
        groupImagePath: storedGroupImagePath.isNotEmpty
            ? storedGroupImagePath
            : null,
      );
      await setCurveEnabled(entry, true);
      nextId++;
    }

    await _writeCurveMap(curvesFile, map);
  }

  static Future<bool> _readGlobalEnabledState() async {
    final saved = await UserToggleStatesService.readSavedBool(
      'curveTablesEnabled',
    );
    if (saved != null) {
      return saved;
    }
    final stateFile = File(BackendPaths.curveTableStateJson);
    if (await stateFile.exists()) {
      try {
        final json =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        return json['enabled'] == true;
      } catch (_) {}
    }
    final legacyBackup = File(BackendPaths.modificationsBackup);
    return !await legacyBackup.exists();
  }

  static Future<void> _writeGlobalEnabledState(
    bool enabled, {
    bool syncUserToggleStates = true,
  }) async {
    if (syncUserToggleStates) {
      await UserToggleStatesService.updateState(
        (current) => current.copyWith(curveTablesEnabled: enabled),
      );
    }
  }

  static Future<String> _readConfiguredContent() async {
    final lines = await ManagedHotfixService.readLines(
      File(BackendPaths.curveTableLinesIni),
    );
    return lines.join('\n');
  }

  static Future<void> _writeConfiguredContent(String content) async {
    await ManagedHotfixService.writeLines(
      File(BackendPaths.curveTableLinesIni),
      content.split('\n'),
    );
  }

  static Future<void> deleteCustomGroup(String groupId) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final entriesToDelete = <String, CurveEntry>{};
    final imagePathsToDelete = customGroupImagePathsToDelete(map, groupId);
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      if (data['isCustom'] == true && data['groupId'] == groupId) {
        entriesToDelete[entry.key] = _entryFromJson(entry.key, data);
      }
    }
    for (final entry in entriesToDelete.values) {
      await setCurveEnabled(entry, false);
    }
    for (final key in entriesToDelete.keys) {
      map.remove(key);
    }
    await _writeCurveMap(curvesFile, map);

    for (final imagePath in imagePathsToDelete) {
      final relativeParts = imagePath
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (relativeParts.isEmpty) {
        continue;
      }
      final imageFile = File(
        joinPath([getBackendRoot(), 'public', 'items', ...relativeParts]),
      );
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    }
  }

  static Future<void> deleteCustomCurve(String curveId) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final data = map[curveId];
    if (data is! Map<String, dynamic> || data['isCustom'] != true) return;
    final entry = _entryFromJson(curveId, data);
    await setCurveEnabled(entry, false);
    map.remove(curveId);
    await _writeCurveMap(curvesFile, map);
  }

  static Future<void> updateCustomCurve(
    String curveId,
    CustomCurveEditResult updated,
  ) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final data = map[curveId];
    if (data is! Map<String, dynamic> || data['isCustom'] != true) return;
    final oldEntry = _entryFromJson(curveId, data);
    await setCurveEnabled(oldEntry, false);
    map[curveId] = {
      ...data,
      'name': updated.name,
      'key': updated.key,
      'type': updated.isStatic ? 'static' : 'amount',
      'pathPart': updated.pathPart,
      if (updated.isStatic) 'staticValue': updated.staticValue,
      if (!updated.isStatic) 'staticValue': null,
      'multiLines': updated.lines,
      'groupId': updated.groupId,
      'groupName': updated.groupName,
      if (updated.groupImagePath != null)
        'groupImagePath': updated.groupImagePath,
    };
    if (updated.groupImagePath == null) {
      (map[curveId] as Map<String, dynamic>).remove('groupImagePath');
    }
    final newEntry = CurveEntry(
      id: curveId,
      name: updated.name,
      key: updated.key,
      type: updated.isStatic ? 'static' : 'amount',
      pathPart: updated.pathPart,
      staticValue: updated.isStatic ? updated.staticValue : null,
      isCustom: true,
      multiLines: updated.lines,
      groupId: updated.groupId,
      groupName: updated.groupName,
      groupImagePath: updated.groupImagePath ?? oldEntry.groupImagePath,
    );
    await setCurveEnabled(newEntry, true);
    await _writeCurveMap(curvesFile, map);
  }

  static Future<void> updateCustomGroup(
    String groupId,
    String name,
    String? newImagePath,
  ) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    String? storedImagePath;
    if (newImagePath != null && newImagePath.isNotEmpty) {
      final source = File(newImagePath);
      if (await source.exists()) {
        final destDir = Directory(
          joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
        );
        await destDir.create(recursive: true);
        final fileName = source.uri.pathSegments.last;
        final stampedName =
            '${DateTime.now().millisecondsSinceEpoch}_$fileName';
        storedImagePath = joinPath(['custom-groups', stampedName]);
        await source.copy(joinPath([destDir.path, stampedName]));
      }
    }
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      if (data['isCustom'] == true && data['groupId'] == groupId) {
        data['groupName'] = name;
        if (storedImagePath != null) {
          data['groupImagePath'] = storedImagePath;
        }
        map[entry.key] = data;
      }
    }
    await _writeCurveMap(curvesFile, map);
  }

  static Future<void> _ensureCurveInJson(String key, String pathPart) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) {
      await _writeCurveMap(curvesFile, const <String, dynamic>{});
    }
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final exists = map.values.any((value) {
      final data = value as Map<String, dynamic>;
      final existingPath =
          (data['pathPart'] ?? BackendPaths.defaultCurvePath) as String;
      return data['key'] == key && existingPath == pathPart;
    });
    if (exists) return;
    final nextId =
        (map.keys
            .map(int.tryParse)
            .whereType<int>()
            .fold(0, (a, b) => a > b ? a : b)) +
        1;
    map[nextId.toString()] = {
      'name': _humanizeKey(key),
      'key': key,
      'type': 'amount',
      'pathPart': pathPart,
      'isCustom': true,
      'groupId': 'other',
      'groupName': 'Other',
    };
    await _writeCurveMap(curvesFile, map);
  }

  static String _humanizeKey(String key) {
    final last = key.split('.').last;
    return last
        .replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match.group(0)}')
        .trim();
  }
}

class DataTableService {
  static const String _fixesComment = '# Fixes';
  static const String _textHotfixSection =
      '[/Script/FortniteGame.FortTextHotfixConfig]';
  static const List<String> _atlasTextReplacements = [
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="9F28701D47C7B91B048FEBA378ADDEAE", NativeString="Epic Games", LocalizedStrings=(("en","ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="LoadingScreen", Key="Connecting", NativeString="CONNECTING", LocalizedStrings=(("en","CONNECTING TO ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="FortLoginStatus", Key="LoggingIn", NativeString="Logging In...", LocalizedStrings=(("en","Logging Into ATLAS...")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="OnlineAccount", Key="DoQosPingTests", NativeString="Checking connection to datacenters...", LocalizedStrings=(("en","Checking connection to ATLAS...")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="37020CCD402F073607D9D4A9561EF035", NativeString="PLAY", LocalizedStrings=(("en","Play ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="C8C6606D4ED4B816D4A358A42DFBDD59", NativeString="PLAY", LocalizedStrings=(("en","Play ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="03875FFD49212D2F37B01788C09086B5", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="1D20854C403FDD474AE7C8B929815DA2", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="1FB7052F40BE8B647B5CA5A362BE8F21", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="2E42C9FB4F551A859C05BF99F7E36FB1", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="370415344EEEA09D8C01A48F4B8148D7", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="538BD1FD46BCEFA4813E2FAFAA07E1A2", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="FortOnlineAccount", Key="CreatingParty", NativeString="Creating party...", LocalizedStrings=(("en","Welcome to ATLAS")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="PartyContext", Key="BattleRoyaleInLobby", NativeString="Battle Royale - In Lobby", LocalizedStrings=(("en","ATLAS - Lobby")))',
    '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="OnlineAccount", Key="TokenExpired", NativeString="Login Expired or Logged In Elsewhere", LocalizedStrings=(("en","Backend Restarted... Restart your game")))',
  ];
  static const List<String> _backendInfiniteRenderFilterLines = [
    '+FilterConfigs=(ClassName=/Script/Engine.Pawn, DynamicFilterName=None, FilterProfile=None)',
    '+FilterConfigs=(ClassName=/Script/FortniteGame.FortPawn, DynamicFilterName=None, FilterProfile=None)',
    '+FilterConfigs=(ClassName=/Script/FortniteGame.FortPlayerPawn, DynamicFilterName=None, FilterProfile=None)',
    '+FilterConfigs=(ClassName=/Script/FortniteGame.FortPlayerPawnAthena, DynamicFilterName=None, FilterProfile=None)',
    '+FilterConfigs=(ClassName=/Script/FortniteGame.FortInventory, DynamicFilterName=None)',
    '+FilterConfigs=(ClassName=/Script/FortniteGame.FortBroadcastRemoteClientInfo, DynamicFilterName=None)',
  ];
  static const String _swapCooldownLine =
      'Weapon.TryToFireRestrictedByTypeCooldowns=0';
  static const String _victoryTextComment = '# Victory Royale Text';
  static const List<String> _victoryPlacementKeys = [
    'DB13D3C249748AF462C7C4BFBB31ED4A',
    'BAFBD2E7447420DB97DD4EB958BE94DA',
  ];
  static const List<String> _victoryVictoryKeys = [
    '42B31291461096DFE0F34C99B5BD5A72',
    '4F7B9E6C47089B1CAADF259983B09563',
  ];
  static const List<String> _victoryRoyaleKeys = [
    '1622E7A444CF92D16B083E9DB17907C4',
    '71DE29354A2AB0D1C24D85895B93023C',
  ];
  static const String _victoryPlacementNativeString =
      '<PlacementNumberSymbol>#</><PlacementValue>1</>';
  static const String _victoryVictoryNativeString = '<cap>V</>ICTORY';
  static const String _victoryRoyaleNativeString = '<cap>R</>OYALE';
  static final Set<String> _victoryTextKeys = <String>{
    ..._victoryPlacementKeys,
    ..._victoryVictoryKeys,
    ..._victoryRoyaleKeys,
  };

  static String _normalizeCommentLabel(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s#]+'), '');
  }

  static String _removeDataTableLinesFromBlocks(
    String content,
    Set<String> targetBlocks,
  ) {
    final lines = content.split('\n');
    final output = <String>[];
    final knownBlocks = <String>{
      _normalizeCommentLabel(BackendPaths.dataTableComment),
      _normalizeCommentLabel(BackendPaths.straightBloomComment),
      _normalizeCommentLabel(BackendPaths.curveTableComment),
      _normalizeCommentLabel(_fixesComment),
    };
    final dataTableLine = RegExp(r'^\s*\+DataTable=.*$');
    final commentHeader = RegExp(r'^\s*#\s*(.+?)\s*$');
    final assetHeader = RegExp(
      r'^\s*\[AssetHotfix\]\s*$',
      caseSensitive: false,
    );
    String? activeBlock;

    for (final line in lines) {
      if (assetHeader.hasMatch(line)) {
        activeBlock = null;
        output.add(line);
        continue;
      }

      final commentMatch = commentHeader.firstMatch(line);
      if (commentMatch != null) {
        final normalized = _normalizeCommentLabel(commentMatch.group(1)!);
        if (knownBlocks.contains(normalized)) {
          activeBlock = normalized;
        }
        output.add(line);
        continue;
      }

      final shouldRemove =
          activeBlock != null &&
          targetBlocks.contains(activeBlock) &&
          dataTableLine.hasMatch(line);
      if (shouldRemove) continue;
      output.add(line);
    }

    return output.join('\n').replaceAll(RegExp(r'\n\n+'), '\n');
  }

  static String clearDataTableSections(
    String content, {
    bool includeFixes = false,
  }) {
    final targetBlocks = <String>{
      _normalizeCommentLabel(BackendPaths.dataTableComment),
    };
    if (includeFixes) {
      targetBlocks.add(_normalizeCommentLabel(_fixesComment));
    }
    return _removeDataTableLinesFromBlocks(content, targetBlocks);
  }

  static VictoryTextReplacementSettings
  _normalizeVictoryTextReplacementSettings(
    VictoryTextReplacementSettings settings,
  ) {
    final placement = RegExp(r'^\d+$').hasMatch(settings.placement.trim())
        ? settings.placement.trim()
        : VictoryTextReplacementSettings.defaultPlacement;
    final victory = _sanitizeVictoryWord(
      settings.victory,
      VictoryTextReplacementSettings.defaultVictory,
    );
    final royale = _sanitizeVictoryWord(
      settings.royale,
      VictoryTextReplacementSettings.defaultRoyale,
    );
    final usesDefaultText =
        placement == VictoryTextReplacementSettings.defaultPlacement &&
        victory == VictoryTextReplacementSettings.defaultVictory &&
        royale == VictoryTextReplacementSettings.defaultRoyale;
    return VictoryTextReplacementSettings(
      enabled: settings.enabled && !usesDefaultText,
      placement: placement,
      victory: victory,
      royale: royale,
    );
  }

  static String _sanitizeVictoryWord(String value, String fallback) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    if (RegExp(r'[\s<>]').hasMatch(trimmed) || trimmed.contains('"')) {
      return fallback;
    }
    return trimmed;
  }

  static String _buildVictoryWordLocalizedString(String value) {
    final first = value.substring(0, 1);
    final rest = value.length > 1 ? value.substring(1) : '';
    return '<cap>$first</>$rest';
  }

  static String _buildVictoryTextReplacementLine({
    required String key,
    required String nativeString,
    required String localizedString,
  }) {
    return '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="$key", NativeString="$nativeString", LocalizedStrings=(("en","$localizedString")))';
  }

  static List<String> _buildVictoryTextReplacementLines(
    VictoryTextReplacementSettings settings,
  ) {
    final effective = settings.enabled
        ? settings
        : VictoryTextReplacementSettings.defaultSettings;
    final placementLocalized =
        '<PlacementNumberSymbol>#</><PlacementValue>${effective.placement}</>';
    final victoryLocalized = _buildVictoryWordLocalizedString(
      effective.victory,
    );
    final royaleLocalized = _buildVictoryWordLocalizedString(effective.royale);

    return <String>[
      ..._victoryPlacementKeys.map(
        (key) => _buildVictoryTextReplacementLine(
          key: key,
          nativeString: _victoryPlacementNativeString,
          localizedString: placementLocalized,
        ),
      ),
      ..._victoryVictoryKeys.map(
        (key) => _buildVictoryTextReplacementLine(
          key: key,
          nativeString: _victoryVictoryNativeString,
          localizedString: victoryLocalized,
        ),
      ),
      ..._victoryRoyaleKeys.map(
        (key) => _buildVictoryTextReplacementLine(
          key: key,
          nativeString: _victoryRoyaleNativeString,
          localizedString: royaleLocalized,
        ),
      ),
    ];
  }

  static String? _extractVictoryTextReplacementKey(String line) {
    final match = RegExp(r'Key="([^"]+)"').firstMatch(line);
    return match?.group(1);
  }

  static String? _extractVictoryLocalizedString(String line) {
    final match = RegExp(
      r'LocalizedStrings=\(\("en","(.+)"\)\)\)\s*$',
    ).firstMatch(line.trim());
    return match?.group(1);
  }

  static String? _findVictoryLocalizedStringForKeys(
    Iterable<String> lines,
    Iterable<String> keys,
  ) {
    final keySet = keys.toSet();
    for (final line in lines) {
      final key = _extractVictoryTextReplacementKey(line);
      if (key == null || !keySet.contains(key)) continue;
      final localized = _extractVictoryLocalizedString(line);
      if (localized != null && localized.isNotEmpty) {
        return localized;
      }
    }
    return null;
  }

  static String _parseVictoryPlacementValue(String? localized) {
    if (localized == null || localized.isEmpty) {
      return VictoryTextReplacementSettings.defaultPlacement;
    }
    final match = RegExp(
      r'^<PlacementNumberSymbol>#</><PlacementValue>([^<]+)</>$',
    ).firstMatch(localized);
    final value = match?.group(1)?.trim() ?? '';
    return RegExp(r'^\d+$').hasMatch(value)
        ? value
        : VictoryTextReplacementSettings.defaultPlacement;
  }

  static String _parseVictoryWordValue(String? localized, String fallback) {
    if (localized == null || localized.isEmpty) {
      return fallback;
    }
    final match = RegExp(r'^<cap>(.)</>(.*)$').firstMatch(localized);
    if (match == null) return fallback;
    final first = match.group(1) ?? '';
    final rest = match.group(2) ?? '';
    final combined = '$first$rest'.trim();
    return _sanitizeVictoryWord(combined, fallback);
  }

  static VictoryTextReplacementSettings
  _parseVictoryTextReplacementSettingsFromLines(Iterable<String> lines) {
    final placement = _parseVictoryPlacementValue(
      _findVictoryLocalizedStringForKeys(lines, _victoryPlacementKeys),
    );
    final victory = _parseVictoryWordValue(
      _findVictoryLocalizedStringForKeys(lines, _victoryVictoryKeys),
      VictoryTextReplacementSettings.defaultVictory,
    );
    final royale = _parseVictoryWordValue(
      _findVictoryLocalizedStringForKeys(lines, _victoryRoyaleKeys),
      VictoryTextReplacementSettings.defaultRoyale,
    );
    final normalized = _normalizeVictoryTextReplacementSettings(
      VictoryTextReplacementSettings(
        enabled: true,
        placement: placement,
        victory: victory,
        royale: royale,
      ),
    );
    return normalized.copyWith(
      enabled:
          normalized.placement !=
              VictoryTextReplacementSettings.defaultPlacement ||
          normalized.victory != VictoryTextReplacementSettings.defaultVictory ||
          normalized.royale != VictoryTextReplacementSettings.defaultRoyale,
    );
  }

  static List<String> _withVictoryTextReplacementLines(
    Iterable<String> lines,
    VictoryTextReplacementSettings settings,
  ) {
    final effective = _normalizeVictoryTextReplacementSettings(settings);
    final output = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      final key = _extractVictoryTextReplacementKey(trimmed);
      if (trimmed == _victoryTextComment) continue;
      if (key != null && _victoryTextKeys.contains(key)) continue;
      output.add(line);
    }
    output.add(_victoryTextComment);
    output.addAll(_buildVictoryTextReplacementLines(effective));
    return output;
  }

  static Future<VictoryTextReplacementSettings>
  getVictoryTextReplacementSettings() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) {
      return VictoryTextReplacementSettings.defaultSettings;
    }
    final lines = await iniFile.readAsLines();
    return _parseVictoryTextReplacementSettingsFromLines(lines);
  }

  static Future<bool> isVictoryTextReplacementEnabled() async {
    final settings = await getVictoryTextReplacementSettings();
    return settings.enabled;
  }

  static Future<void> setVictoryTextReplacementSettings(
    VictoryTextReplacementSettings settings, {
    bool syncUserToggleStates = true,
  }) async {
    final normalized = _normalizeVictoryTextReplacementSettings(settings);
    await ensureAtlasTextHotfixInDefaultGame(
      overrideVictoryTextSettings: normalized,
    );
    if (syncUserToggleStates) {
      await UserToggleStatesService.updateState(
        (current) => current.copyWith(
          victoryTextReplacementEnabled: normalized.enabled,
          victoryTextPlacement: normalized.placement,
          victoryTextVictory: normalized.victory,
          victoryTextRoyale: normalized.royale,
        ),
      );
    }
  }

  static Future<bool> isBackendInfiniteRenderEnabled() async {
    final engineFile = File(BackendPaths.defaultEngineIni);
    if (!await engineFile.exists()) return false;
    final content = await engineFile.readAsString();
    final lines = content.split(RegExp(r'\r?\n'));
    final active = <String>{};
    for (final line in lines) {
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft.isEmpty || trimmedLeft.startsWith(';')) continue;
      final normalized = trimmedLeft.trimRight();
      if (_backendInfiniteRenderFilterLines.contains(normalized)) {
        active.add(normalized);
      }
    }
    return _backendInfiniteRenderFilterLines.every(active.contains);
  }

  static Future<void> setBackendInfiniteRenderEnabled(
    bool enabled, {
    bool syncUserToggleStates = true,
  }) async {
    final engineFile = File(BackendPaths.defaultEngineIni);
    if (!await engineFile.exists()) return;
    final content = await engineFile.readAsString();
    final lineEnding = content.contains('\r\n') ? '\r\n' : '\n';
    final hasTrailingNewline = content.endsWith('\n');
    final lines = content.split(RegExp(r'\r?\n'));
    var changed = false;

    for (var i = 0; i < lines.length; i++) {
      final original = lines[i];
      final leadingMatch = RegExp(r'^\s*').firstMatch(original);
      final leading = leadingMatch?.group(0) ?? '';
      var rest = original.substring(leading.length);
      var isCommented = false;
      if (rest.startsWith(';')) {
        isCommented = true;
        rest = rest.substring(1).trimLeft();
      }
      final normalized = rest.trimRight();
      if (!_backendInfiniteRenderFilterLines.contains(normalized)) continue;

      final updated = enabled ? '$leading$normalized' : '$leading;$normalized';
      if (updated != original) {
        lines[i] = updated;
        changed = true;
      } else if (enabled && isCommented) {
        // Keep behavior deterministic when spacing around ";" differs.
        lines[i] = updated;
        changed = true;
      }
    }

    if (!changed) {
      if (syncUserToggleStates) {
        await UserToggleStatesService.syncFromCurrentState();
      }
      return;
    }

    var updatedContent = lines.join(lineEnding);
    if (hasTrailingNewline && !updatedContent.endsWith(lineEnding)) {
      updatedContent = '$updatedContent$lineEnding';
    }
    await engineFile.writeAsString(updatedContent);
    if (syncUserToggleStates) {
      await UserToggleStatesService.syncFromCurrentState();
    }
  }

  static Future<bool> isSwapCooldownEnabled() async {
    final engineFile = File(BackendPaths.defaultEngineIni);
    if (!await engineFile.exists()) return false;
    final content = await engineFile.readAsString();
    final lines = content.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft.isEmpty) continue;
      var rest = trimmedLeft;
      var isCommented = false;
      if (rest.startsWith(';')) {
        isCommented = true;
        rest = rest.substring(1).trimLeft();
      }
      if (rest.trimRight() != _swapCooldownLine) continue;
      return !isCommented;
    }
    return false;
  }

  static Future<void> setSwapCooldownEnabled(
    bool enabled, {
    bool syncUserToggleStates = true,
  }) async {
    final engineFile = File(BackendPaths.defaultEngineIni);
    if (!await engineFile.exists()) return;
    final content = await engineFile.readAsString();
    final lineEnding = content.contains('\r\n') ? '\r\n' : '\n';
    final hasTrailingNewline = content.endsWith('\n');
    final lines = content.split(RegExp(r'\r?\n'));
    var changed = false;

    for (var i = 0; i < lines.length; i++) {
      final original = lines[i];
      final leadingMatch = RegExp(r'^\s*').firstMatch(original);
      final leading = leadingMatch?.group(0) ?? '';
      var rest = original.substring(leading.length);
      var isCommented = false;
      if (rest.startsWith(';')) {
        isCommented = true;
        rest = rest.substring(1).trimLeft();
      }
      final normalized = rest.trimRight();
      if (normalized != _swapCooldownLine) continue;

      final updated = enabled ? '$leading$normalized' : '$leading;$normalized';
      if (updated != original) {
        lines[i] = updated;
        changed = true;
      } else if (enabled && isCommented) {
        lines[i] = updated;
        changed = true;
      }
    }

    if (!changed) {
      if (syncUserToggleStates) {
        await UserToggleStatesService.syncFromCurrentState();
      }
      return;
    }

    var updatedContent = lines.join(lineEnding);
    if (hasTrailingNewline && !updatedContent.endsWith(lineEnding)) {
      updatedContent = '$updatedContent$lineEnding';
    }
    await engineFile.writeAsString(updatedContent);
    if (syncUserToggleStates) {
      await UserToggleStatesService.syncFromCurrentState();
    }
  }

  static Future<void> ensureAtlasTextHotfixInDefaultGame({
    VictoryTextReplacementSettings? overrideVictoryTextSettings,
  }) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    final original = await iniFile.readAsString();
    final lineEnding = original.contains('\r\n') ? '\r\n' : '\n';
    final hasTrailingNewline = original.endsWith('\n');
    var lines = original.split(RegExp(r'\r?\n'));

    final sectionRanges = <({int start, int end})>[];
    final existingSectionLines = <String>[];
    final sectionHeaderRegex = RegExp(r'^\[[^\r\n\]]+\]$');

    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() != _textHotfixSection) continue;

      final start = i;
      i++;
      while (i < lines.length &&
          !sectionHeaderRegex.hasMatch(lines[i].trim())) {
        existingSectionLines.add(lines[i].trimRight());
        i++;
      }
      sectionRanges.add((start: start, end: i));
      i--;
    }

    if (sectionRanges.isNotEmpty) {
      final kept = <String>[];
      var rangeIndex = 0;
      for (var i = 0; i < lines.length;) {
        if (rangeIndex < sectionRanges.length &&
            i == sectionRanges[rangeIndex].start) {
          i = sectionRanges[rangeIndex].end;
          rangeIndex++;
          continue;
        }
        kept.add(lines[i]);
        i++;
      }
      lines = kept;
    }

    final mergedSectionLines = <String>[];
    final seen = <String>{};
    void addUnique(String line) {
      if (line.isEmpty) return;
      if (!seen.add(line)) return;
      mergedSectionLines.add(line);
    }

    for (final line in existingSectionLines) {
      addUnique(line);
    }
    for (final line in _atlasTextReplacements) {
      addUnique(line);
    }

    final victoryTextReplacementSettings =
        overrideVictoryTextSettings ??
        _parseVictoryTextReplacementSettingsFromLines(existingSectionLines);
    final sectionBlockLines = <String>[
      _textHotfixSection,
      ..._withVictoryTextReplacementLines(
        mergedSectionLines,
        victoryTextReplacementSettings,
      ),
    ];
    final firstAssetHotfixIndex = lines.indexWhere(
      (line) => line.trim() == '[AssetHotfix]',
    );
    late final List<String> resultLines;
    if (firstAssetHotfixIndex == -1) {
      resultLines = [...lines, ...sectionBlockLines];
    } else {
      resultLines = [
        ...lines.sublist(0, firstAssetHotfixIndex),
        ...sectionBlockLines,
        ...lines.sublist(firstAssetHotfixIndex),
      ];
    }

    var output = resultLines.join(lineEnding);
    if (hasTrailingNewline && !output.endsWith(lineEnding)) {
      output = '$output$lineEnding';
    }

    if (output != original) {
      await iniFile.writeAsString(output);
    }
  }

  // Preserve any manual fixes under the "# Fixes" marker in DefaultGame.ini.
  static ({String editable, String protected}) _splitProtectedFixesBlock(
    String content,
  ) {
    final match = RegExp(
      r'^\s*#\s*Fixes\s*$',
      multiLine: true,
    ).firstMatch(content);
    if (match == null) return (editable: content, protected: '');
    return (
      editable: content.substring(0, match.start),
      protected: content.substring(match.start),
    );
  }

  static String _dataTableSignature(Map<String, dynamic> data) {
    final weaponPath = (data['weaponPath']?.toString().trim() ?? '')
        .toLowerCase();
    final weaponId = (data['weaponId']?.toString().trim() ?? '').toLowerCase();
    if (weaponPath.isNotEmpty && weaponId.isNotEmpty) {
      return '$weaponPath|||$weaponId';
    }

    final variants = data['variants'];
    if (variants is! List || variants.isEmpty) {
      return '';
    }

    final variantIds =
        variants
            .map((variant) {
              if (variant is! Map) return '';
              return (variant['weaponId']?.toString().trim() ?? '')
                  .toLowerCase();
            })
            .where((id) => id.isNotEmpty)
            .toList()
          ..sort();
    if (variantIds.isEmpty) {
      return '';
    }

    return '$weaponPath|||${variantIds.join('||')}';
  }

  static Future<void> _writeDataTableMap(
    File file,
    Map<String, dynamic> map,
  ) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<Map<String, dynamic>?> _loadDefaultDataTableMap() async {
    final candidates = <String>[
      joinPath([
        getInstallationRoot(),
        'responses',
        'datatables.defaults.json',
      ]),
      joinPath([getInstallationRoot(), 'responses', 'datatables.json']),
      BackendPaths.dataTablesDefaultsJson,
    ];

    for (final candidate in candidates) {
      final map = await _readJsonObject(File(candidate));
      if (map != null && map.isNotEmpty) {
        return map;
      }
    }

    return null;
  }

  static Future<void> _mergeMissingDefaultDataTables() async {
    final dataTablesFile = File(BackendPaths.dataTablesJson);
    final defaults = await _loadDefaultDataTableMap();
    if (defaults == null || defaults.isEmpty) return;

    if (!await dataTablesFile.exists()) {
      await _writeDataTableMap(dataTablesFile, defaults);
      return;
    }

    final current = await _readJsonObject(dataTablesFile);
    if (current == null) return;

    final existingSignatures = <String>{};
    for (final value in current.values) {
      if (value is! Map) continue;
      final signature = _dataTableSignature(Map<String, dynamic>.from(value));
      if (signature.isNotEmpty) {
        existingSignatures.add(signature);
      }
    }

    var maxId = 0;
    for (final id in current.keys) {
      final parsed = int.tryParse(id);
      if (parsed != null && parsed > maxId) {
        maxId = parsed;
      }
    }

    var changed = false;
    final defaultEntries = defaults.entries.toList()
      ..sort((a, b) {
        final aId = int.tryParse(a.key) ?? (1 << 30);
        final bId = int.tryParse(b.key) ?? (1 << 30);
        return aId.compareTo(bId);
      });

    for (final entry in defaultEntries) {
      if (entry.value is! Map) continue;
      final dataTable = Map<String, dynamic>.from(entry.value);
      final signature = _dataTableSignature(dataTable);
      if (signature.isEmpty || existingSignatures.contains(signature)) {
        continue;
      }

      maxId += 1;
      current['$maxId'] = jsonDecode(jsonEncode(dataTable));
      existingSignatures.add(signature);
      changed = true;
    }

    if (changed) {
      await _writeDataTableMap(dataTablesFile, current);
    }
  }

  static Future<List<DataTableWeapon>> loadWeapons() async {
    await _mergeMissingDefaultDataTables();
    final dataTablesFile = File(BackendPaths.dataTablesJson);
    if (!await dataTablesFile.exists()) {
      return [];
    }
    final map =
        jsonDecode(await dataTablesFile.readAsString()) as Map<String, dynamic>;
    final weapons = <DataTableWeapon>[];
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final variantsData = data['variants'] as List<dynamic>?;
      List<WeaponVariant>? variants;
      if (variantsData != null && variantsData.isNotEmpty) {
        variants = variantsData.map((v) {
          final vMap = v as Map<String, dynamic>;
          return WeaponVariant(
            name: vMap['name'] ?? '',
            weaponId: vMap['weaponId'] ?? '',
            damagePB: vMap['damagePB'] ?? '0',
            defaultEnvDamage: vMap['defaultEnvDamage'] ?? '0',
            imagePath: vMap['imagePath'],
            reloadTime: vMap['reloadTime'],
          );
        }).toList();
      }
      weapons.add(
        DataTableWeapon(
          id: entry.key,
          name: data['name'] ?? 'Weapon ${entry.key}',
          weaponId: data['weaponId'] ?? '',
          weaponPath:
              data['weaponPath'] ??
              '/Game/Athena/Items/Weapons/AthenaRangedWeapons',
          imagePath: data['imagePath'],
          damageFields:
              (data['damageFields'] as List<dynamic>?)?.cast<String>() ?? [],
          environmentalDamageFields:
              (data['environmentalDamageFields'] as List<dynamic>?)
                  ?.cast<String>() ??
              [],
          damagePB: data['damagePB'] ?? '0',
          defaultEnvDamage: data['defaultEnvDamage'] ?? '0',
          variants: variants,
          clipSize: data['clipSize'],
        ),
      );
    }
    return weapons;
  }

  static Future<bool> areDataTablesEnabled() async {
    return getUIEnabledState();
  }

  static Future<bool> getUIEnabledState() async {
    final saved = await UserToggleStatesService.readSavedBool(
      'dataTablesEnabled',
    );
    if (saved != null) {
      return saved;
    }
    final stateFile = File(BackendPaths.dataTablesUiState);
    if (await stateFile.exists()) {
      try {
        final state =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        return state['enabled'] == true;
      } catch (_) {
        return false;
      }
    }

    final configured = await ManagedHotfixService.readLines(
      File(BackendPaths.dataTableLinesIni),
    );
    if (configured.isNotEmpty) {
      return true;
    }

    // Legacy fallback: migrate from modifications-backup.json if present.
    final backupFile = File(BackendPaths.modificationsBackup);
    if (!await backupFile.exists()) return false;
    try {
      final backup =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      final enabled = backup['dataTablesUIEnabled'] == true;
      if (!backup.containsKey('curveTableLines')) {
        final extraKeys = backup.keys
            .where((key) => key != 'dataTablesUIEnabled')
            .toList();
        if (extraKeys.isEmpty) {
          try {
            await backupFile.delete();
          } catch (_) {}
        }
      }
      return enabled;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setUIEnabledState(bool enabled) async {
    await _writeUiState(enabled);
    await ManagedHotfixService.rebuildDefaultGame();
  }

  static Future<void> _writeUiState(
    bool enabled, {
    bool syncUserToggleStates = true,
  }) async {
    if (syncUserToggleStates) {
      await UserToggleStatesService.updateState(
        (current) => current.copyWith(dataTablesEnabled: enabled),
      );
    }
  }

  static Future<DataTableSettings> getWeaponSettings(
    DataTableWeapon weapon, {
    String? variantWeaponId,
  }) async {
    final weaponId = variantWeaponId ?? weapon.weaponId;

    // Get default clipSize and reloadTime
    String defaultClipSize = weapon.clipSize ?? '30';
    String defaultReloadTime = '2.0';

    // If variant is selected, get reloadTime from variant
    if (variantWeaponId != null && weapon.variants != null) {
      final variant = weapon.variants!.firstWhere(
        (v) => v.weaponId == variantWeaponId,
        orElse: () => weapon.variants!.first,
      );
      defaultReloadTime = variant.reloadTime ?? '2.0';
    }

    final content = await _readConfiguredContent();
    if (content.isEmpty) {
      return DataTableSettings(
        damageEnabled: false,
        envDamageEnabled: false,
        advancedMode: false,
        damageValue: weapon.damagePB,
        envDamageValue: weapon.defaultEnvDamage,
        customValues: {},
        clipSizeEnabled: false,
        clipSizeValue: defaultClipSize,
        reloadTimeEnabled: false,
        reloadTimeValue: defaultReloadTime,
      );
    }
    final customValues = <String, String>{};
    bool hasDamage = false;
    bool hasEnvDamage = false;
    bool hasClipSize = false;
    bool hasReloadTime = false;
    String? clipSizeValue;
    String? reloadTimeValue;

    for (final field in weapon.damageFields) {
      final regex = RegExp(
        r'^\+DataTable=' +
            RegExp.escape(weapon.weaponPath) +
            r';RowUpdate;' +
            RegExp.escape(weaponId) +
            r';' +
            RegExp.escape(field) +
            r';(.+)$',
        multiLine: true,
      );
      final match = regex.firstMatch(content);
      if (match != null) {
        customValues[field] = match.group(1)!;
        hasDamage = true;
      }
    }

    for (final field in weapon.environmentalDamageFields) {
      final regex = RegExp(
        r'^\+DataTable=' +
            RegExp.escape(weapon.weaponPath) +
            r';RowUpdate;' +
            RegExp.escape(weaponId) +
            r';' +
            RegExp.escape(field) +
            r';(.+)$',
        multiLine: true,
      );
      final match = regex.firstMatch(content);
      if (match != null) {
        customValues[field] = match.group(1)!;
        hasEnvDamage = true;
      }
    }

    // Check for ClipSize
    final clipSizeRegex = RegExp(
      r'^\+DataTable=' +
          RegExp.escape(weapon.weaponPath) +
          r';RowUpdate;' +
          RegExp.escape(weaponId) +
          r';ClipSize;(.+)$',
      multiLine: true,
    );
    final clipSizeMatch = clipSizeRegex.firstMatch(content);
    if (clipSizeMatch != null) {
      clipSizeValue = clipSizeMatch.group(1)!;
      hasClipSize = true;
    }

    // Check for ReloadTime
    final reloadTimeRegex = RegExp(
      r'^\+DataTable=' +
          RegExp.escape(weapon.weaponPath) +
          r';RowUpdate;' +
          RegExp.escape(weaponId) +
          r';ReloadTime;(.+)$',
      multiLine: true,
    );
    final reloadTimeMatch = reloadTimeRegex.firstMatch(content);
    if (reloadTimeMatch != null) {
      reloadTimeValue = reloadTimeMatch.group(1)!;
      hasReloadTime = true;
    }

    // Check if values are consistent (simple mode) or different (advanced mode)
    bool advancedMode = false;
    String? dmgValue;
    String? envDmgValue;

    if (hasDamage) {
      final damageValues = weapon.damageFields
          .map((f) => customValues[f])
          .whereType<String>()
          .toSet();
      if (damageValues.length == 1) {
        dmgValue = damageValues.first;
      } else {
        advancedMode = true;
      }
    }

    if (hasEnvDamage) {
      final envValues = weapon.environmentalDamageFields
          .map((f) => customValues[f])
          .whereType<String>()
          .toSet();
      if (envValues.length == 1) {
        envDmgValue = envValues.first;
      } else {
        advancedMode = true;
      }
    }

    return DataTableSettings(
      damageEnabled: hasDamage,
      envDamageEnabled: hasEnvDamage,
      advancedMode: advancedMode,
      damageValue: dmgValue ?? weapon.damagePB,
      envDamageValue: envDmgValue ?? weapon.defaultEnvDamage,
      customValues: customValues,
      clipSizeEnabled: hasClipSize,
      clipSizeValue: clipSizeValue ?? defaultClipSize,
      reloadTimeEnabled: hasReloadTime,
      reloadTimeValue: reloadTimeValue ?? defaultReloadTime,
    );
  }

  static Future<void> applyWeaponSettings(
    DataTableWeapon weapon,
    DataTableSettings settings, {
    String? variantWeaponId,
  }) async {
    final weaponId = variantWeaponId ?? weapon.weaponId;
    var editable = await _readConfiguredContent();

    // Remove existing DataTable lines for this weapon
    for (final field in [
      ...weapon.damageFields,
      ...weapon.environmentalDamageFields,
      'ClipSize',
      'ReloadTime',
    ]) {
      final regex = RegExp(
        r'^\+DataTable=' +
            RegExp.escape(weapon.weaponPath) +
            r';RowUpdate;' +
            RegExp.escape(weaponId) +
            r';' +
            RegExp.escape(field) +
            r';.*$',
        multiLine: true,
      );
      editable = editable.replaceAll(regex, '');
    }
    editable = editable.replaceAll(RegExp(r'\n\n+'), '\n');

    // Add new lines if enabled
    final linesToAdd = <String>[];

    if (settings.damageEnabled) {
      if (settings.advancedMode) {
        for (final field in weapon.damageFields) {
          final value = settings.customValues[field] ?? weapon.damagePB;
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;$value',
          );
        }
      } else {
        for (final field in weapon.damageFields) {
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;${settings.damageValue}',
          );
        }
      }
    }

    if (settings.envDamageEnabled) {
      if (settings.advancedMode) {
        for (final field in weapon.environmentalDamageFields) {
          final value = settings.customValues[field] ?? weapon.defaultEnvDamage;
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;$value',
          );
        }
      } else {
        for (final field in weapon.environmentalDamageFields) {
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;${settings.envDamageValue}',
          );
        }
      }
    }

    if (settings.clipSizeEnabled) {
      linesToAdd.add(
        '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;ClipSize;${settings.clipSizeValue}',
      );
    }

    if (settings.reloadTimeEnabled) {
      linesToAdd.add(
        '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;ReloadTime;${settings.reloadTimeValue}',
      );
    }

    if (linesToAdd.isNotEmpty) {
      editable = [
        editable.trim(),
        linesToAdd.join('\n'),
      ].where((value) => value.isNotEmpty).join('\n');
    }

    await _writeConfiguredContent(editable);
    if (await getUIEnabledState()) {
      await ManagedHotfixService.rebuildDefaultGame();
    }
  }

  static Future<void> clearAllDataTables() async {
    final wasEnabled = await getUIEnabledState();
    await _writeConfiguredContent('');
    await _writeUiState(false);
    if (wasEnabled) {
      await ManagedHotfixService.rebuildDefaultGame();
    }
  }

  static Future<void> importDataTableLines(List<String> lines) async {
    final existing = await ManagedHotfixService.readLines(
      File(BackendPaths.dataTableLinesIni),
    );
    final merged = ManagedHotfixService.mergeLines(existing, lines);
    await ManagedHotfixService.writeLines(
      File(BackendPaths.dataTableLinesIni),
      merged,
    );
    if (await getUIEnabledState()) {
      await ManagedHotfixService.rebuildDefaultGame();
    }
  }

  static Future<String> _readConfiguredContent() async {
    final lines = await ManagedHotfixService.readLines(
      File(BackendPaths.dataTableLinesIni),
    );
    return lines.join('\n');
  }

  static Future<void> _writeConfiguredContent(String content) async {
    await ManagedHotfixService.writeLines(
      File(BackendPaths.dataTableLinesIni),
      content.split('\n'),
    );
  }
}

class UserToggleStates {
  const UserToggleStates({
    required this.rufusStage,
    required this.waterLevel,
    required this.saveArenaPoints,
    required this.useWaterStorm,
    required this.startBackendOnLaunch,
    required this.backendInfiniteRenderEnabled,
    required this.swapCooldownEnabled,
    required this.victoryTextReplacementEnabled,
    required this.victoryTextPlacement,
    required this.victoryTextVictory,
    required this.victoryTextRoyale,
    required this.disableBackendUpdateCheck,
    required this.useDarkMode,
    required this.backgroundImagePath,
    required this.backgroundBlur,
    required this.backgroundParticlesOpacity,
    required this.dialogBlurEnabled,
    required this.startupAnimationEnabled,
    required this.lastShownUpdateNotesVersion,
    required this.dataTablesEnabled,
    required this.curveTablesEnabled,
    required this.straightBloomEnabled,
  });

  final int rufusStage;
  final int waterLevel;
  final bool saveArenaPoints;
  final bool useWaterStorm;
  final bool startBackendOnLaunch;
  final bool backendInfiniteRenderEnabled;
  final bool swapCooldownEnabled;
  final bool victoryTextReplacementEnabled;
  final String victoryTextPlacement;
  final String victoryTextVictory;
  final String victoryTextRoyale;
  final bool disableBackendUpdateCheck;
  final bool useDarkMode;
  final String backgroundImagePath;
  final double backgroundBlur;
  final double backgroundParticlesOpacity;
  final bool dialogBlurEnabled;
  final bool startupAnimationEnabled;
  final String lastShownUpdateNotesVersion;
  final bool dataTablesEnabled;
  final bool curveTablesEnabled;
  final bool straightBloomEnabled;

  ConfigSettings toConfigSettings() {
    return ConfigSettings(
      rufusStage: rufusStage,
      waterLevel: waterLevel,
      saveArenaPoints: saveArenaPoints,
      useWaterStorm: useWaterStorm,
      startBackendOnLaunch: startBackendOnLaunch,
      backendInfiniteRenderEnabled: backendInfiniteRenderEnabled,
      swapCooldownEnabled: swapCooldownEnabled,
      disableBackendUpdateCheck: disableBackendUpdateCheck,
      useDarkMode: true,
      backgroundImagePath: backgroundImagePath,
      backgroundBlur: backgroundBlur,
      backgroundParticlesOpacity: backgroundParticlesOpacity,
      dialogBlurEnabled: dialogBlurEnabled,
      startupAnimationEnabled: startupAnimationEnabled,
      lastShownUpdateNotesVersion: lastShownUpdateNotesVersion,
    );
  }

  UserToggleStates copyWith({
    int? rufusStage,
    int? waterLevel,
    bool? saveArenaPoints,
    bool? useWaterStorm,
    bool? startBackendOnLaunch,
    bool? backendInfiniteRenderEnabled,
    bool? swapCooldownEnabled,
    bool? victoryTextReplacementEnabled,
    String? victoryTextPlacement,
    String? victoryTextVictory,
    String? victoryTextRoyale,
    bool? disableBackendUpdateCheck,
    bool? useDarkMode,
    String? backgroundImagePath,
    double? backgroundBlur,
    double? backgroundParticlesOpacity,
    bool? dialogBlurEnabled,
    bool? startupAnimationEnabled,
    String? lastShownUpdateNotesVersion,
    bool? dataTablesEnabled,
    bool? curveTablesEnabled,
    bool? straightBloomEnabled,
  }) {
    return UserToggleStates(
      rufusStage: rufusStage ?? this.rufusStage,
      waterLevel: waterLevel ?? this.waterLevel,
      saveArenaPoints: saveArenaPoints ?? this.saveArenaPoints,
      useWaterStorm: useWaterStorm ?? this.useWaterStorm,
      startBackendOnLaunch: startBackendOnLaunch ?? this.startBackendOnLaunch,
      backendInfiniteRenderEnabled:
          backendInfiniteRenderEnabled ?? this.backendInfiniteRenderEnabled,
      swapCooldownEnabled: swapCooldownEnabled ?? this.swapCooldownEnabled,
      victoryTextReplacementEnabled:
          victoryTextReplacementEnabled ?? this.victoryTextReplacementEnabled,
      victoryTextPlacement: victoryTextPlacement ?? this.victoryTextPlacement,
      victoryTextVictory: victoryTextVictory ?? this.victoryTextVictory,
      victoryTextRoyale: victoryTextRoyale ?? this.victoryTextRoyale,
      disableBackendUpdateCheck:
          disableBackendUpdateCheck ?? this.disableBackendUpdateCheck,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundParticlesOpacity:
          backgroundParticlesOpacity ?? this.backgroundParticlesOpacity,
      dialogBlurEnabled: dialogBlurEnabled ?? this.dialogBlurEnabled,
      startupAnimationEnabled:
          startupAnimationEnabled ?? this.startupAnimationEnabled,
      lastShownUpdateNotesVersion:
          lastShownUpdateNotesVersion ?? this.lastShownUpdateNotesVersion,
      dataTablesEnabled: dataTablesEnabled ?? this.dataTablesEnabled,
      curveTablesEnabled: curveTablesEnabled ?? this.curveTablesEnabled,
      straightBloomEnabled: straightBloomEnabled ?? this.straightBloomEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rufusStage': rufusStage,
      'waterLevel': waterLevel,
      'saveArenaPoints': saveArenaPoints,
      'useWaterStorm': useWaterStorm,
      'startBackendOnLaunch': startBackendOnLaunch,
      'backendInfiniteRenderEnabled': backendInfiniteRenderEnabled,
      'swapCooldownEnabled': swapCooldownEnabled,
      'victoryTextReplacementEnabled': victoryTextReplacementEnabled,
      'victoryTextPlacement': victoryTextPlacement,
      'victoryTextVictory': victoryTextVictory,
      'victoryTextRoyale': victoryTextRoyale,
      'disableBackendUpdateCheck': disableBackendUpdateCheck,
      'useDarkMode': useDarkMode,
      'backgroundImagePath': backgroundImagePath,
      'backgroundBlur': backgroundBlur,
      'backgroundParticlesOpacity': backgroundParticlesOpacity,
      'dialogBlurEnabled': dialogBlurEnabled,
      'startupAnimationEnabled': startupAnimationEnabled,
      'lastShownUpdateNotesVersion': lastShownUpdateNotesVersion,
      'dataTablesEnabled': dataTablesEnabled,
      'curveTablesEnabled': curveTablesEnabled,
      'straightBloomEnabled': straightBloomEnabled,
    };
  }

  static UserToggleStates fromJson(
    Map<String, dynamic> json, {
    required UserToggleStates fallback,
  }) {
    bool readBool(String key, bool fallbackValue) {
      final value = json[key];
      return value is bool ? value : fallbackValue;
    }

    int readInt(String key, int fallbackValue) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallbackValue;
    }

    double readDouble(String key, double fallbackValue) {
      final value = json[key];
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? fallbackValue;
    }

    String readString(String key, String fallbackValue) {
      final value = json[key];
      return value is String ? value : fallbackValue;
    }

    return UserToggleStates(
      rufusStage: readInt('rufusStage', fallback.rufusStage),
      waterLevel: readInt('waterLevel', fallback.waterLevel),
      saveArenaPoints: readBool('saveArenaPoints', fallback.saveArenaPoints),
      useWaterStorm: readBool('useWaterStorm', fallback.useWaterStorm),
      startBackendOnLaunch: readBool(
        'startBackendOnLaunch',
        fallback.startBackendOnLaunch,
      ),
      backendInfiniteRenderEnabled: readBool(
        'backendInfiniteRenderEnabled',
        fallback.backendInfiniteRenderEnabled,
      ),
      swapCooldownEnabled: readBool(
        'swapCooldownEnabled',
        fallback.swapCooldownEnabled,
      ),
      victoryTextReplacementEnabled: readBool(
        'victoryTextReplacementEnabled',
        fallback.victoryTextReplacementEnabled,
      ),
      victoryTextPlacement: readString(
        'victoryTextPlacement',
        fallback.victoryTextPlacement,
      ),
      victoryTextVictory: readString(
        'victoryTextVictory',
        fallback.victoryTextVictory,
      ),
      victoryTextRoyale: readString(
        'victoryTextRoyale',
        fallback.victoryTextRoyale,
      ),
      disableBackendUpdateCheck: readBool(
        'disableBackendUpdateCheck',
        fallback.disableBackendUpdateCheck,
      ),
      useDarkMode: readBool('useDarkMode', fallback.useDarkMode),
      backgroundImagePath: readString(
        'backgroundImagePath',
        fallback.backgroundImagePath,
      ),
      backgroundBlur: readDouble('backgroundBlur', fallback.backgroundBlur),
      backgroundParticlesOpacity: readDouble(
        'backgroundParticlesOpacity',
        fallback.backgroundParticlesOpacity,
      ),
      dialogBlurEnabled: readBool(
        'dialogBlurEnabled',
        fallback.dialogBlurEnabled,
      ),
      startupAnimationEnabled: readBool(
        'startupAnimationEnabled',
        fallback.startupAnimationEnabled,
      ),
      lastShownUpdateNotesVersion: readString(
        'lastShownUpdateNotesVersion',
        fallback.lastShownUpdateNotesVersion,
      ),
      dataTablesEnabled: readBool(
        'dataTablesEnabled',
        fallback.dataTablesEnabled,
      ),
      curveTablesEnabled: readBool(
        'curveTablesEnabled',
        fallback.curveTablesEnabled,
      ),
      straightBloomEnabled: readBool(
        'straightBloomEnabled',
        fallback.straightBloomEnabled,
      ),
    );
  }
}

class UserToggleStatesService {
  static StreamSubscription<FileSystemEvent>? _watchSubscription;
  static Timer? _watchDebounce;
  static String? _lastKnownSignature;
  static const String _legacyModificationTogglesFileName =
      'modification-toggles.json';

  static UserToggleStates freshInstallDefaults() {
    final config = ConfigService.defaultSettings;
    return UserToggleStates(
      rufusStage: config.rufusStage,
      waterLevel: config.waterLevel,
      saveArenaPoints: config.saveArenaPoints,
      useWaterStorm: config.useWaterStorm,
      startBackendOnLaunch: config.startBackendOnLaunch,
      backendInfiniteRenderEnabled: config.backendInfiniteRenderEnabled,
      swapCooldownEnabled: config.swapCooldownEnabled,
      victoryTextReplacementEnabled: false,
      victoryTextPlacement: VictoryTextReplacementSettings.defaultPlacement,
      victoryTextVictory: VictoryTextReplacementSettings.defaultVictory,
      victoryTextRoyale: VictoryTextReplacementSettings.defaultRoyale,
      disableBackendUpdateCheck: config.disableBackendUpdateCheck,
      useDarkMode: config.useDarkMode,
      backgroundImagePath: config.backgroundImagePath,
      backgroundBlur: config.backgroundBlur,
      backgroundParticlesOpacity: config.backgroundParticlesOpacity,
      dialogBlurEnabled: config.dialogBlurEnabled,
      startupAnimationEnabled: config.startupAnimationEnabled,
      lastShownUpdateNotesVersion: config.lastShownUpdateNotesVersion,
      dataTablesEnabled: false,
      curveTablesEnabled: false,
      straightBloomEnabled: false,
    );
  }

  static String _signature(UserToggleStates state) {
    return jsonEncode(state.toJson());
  }

  static Future<UserToggleStates> captureCurrentState() async {
    final config = await ConfigService.load();
    final dataTablesEnabled = await DataTableService.areDataTablesEnabled();
    final curveTablesEnabled = await CurveTableService.areGlobalEnabled();
    final straightBloomEnabled = await StraightBloomService.isEnabled();
    final backendInfiniteRenderEnabled =
        await DataTableService.isBackendInfiniteRenderEnabled();
    final swapCooldownEnabled = await DataTableService.isSwapCooldownEnabled();
    final victoryTextSettings =
        await DataTableService.getVictoryTextReplacementSettings();

    return UserToggleStates(
      rufusStage: config.rufusStage,
      waterLevel: config.waterLevel,
      saveArenaPoints: config.saveArenaPoints,
      useWaterStorm: config.useWaterStorm,
      startBackendOnLaunch: config.startBackendOnLaunch,
      dataTablesEnabled: dataTablesEnabled,
      curveTablesEnabled: curveTablesEnabled,
      straightBloomEnabled: straightBloomEnabled,
      backendInfiniteRenderEnabled: backendInfiniteRenderEnabled,
      swapCooldownEnabled: swapCooldownEnabled,
      victoryTextReplacementEnabled: victoryTextSettings.enabled,
      victoryTextPlacement: victoryTextSettings.placement,
      victoryTextVictory: victoryTextSettings.victory,
      victoryTextRoyale: victoryTextSettings.royale,
      disableBackendUpdateCheck: config.disableBackendUpdateCheck,
      useDarkMode: config.useDarkMode,
      backgroundImagePath: config.backgroundImagePath,
      backgroundBlur: config.backgroundBlur,
      backgroundParticlesOpacity: config.backgroundParticlesOpacity,
      dialogBlurEnabled: config.dialogBlurEnabled,
      startupAnimationEnabled: config.startupAnimationEnabled,
      lastShownUpdateNotesVersion: config.lastShownUpdateNotesVersion,
    );
  }

  static Future<void> syncFromCurrentState() async {
    final state = await captureCurrentState();
    await writeState(state);
  }

  static Future<File> _resolveStateFile() async {
    final current = File(BackendPaths.userToggleStatesJson);
    if (await current.exists()) {
      return current;
    }
    final legacy = File(
      joinPath([
        getBackendRoot(),
        'responses',
        _legacyModificationTogglesFileName,
      ]),
    );
    if (await legacy.exists()) {
      return legacy;
    }
    return current;
  }

  static Future<void> _migrateLegacyFileIfNeeded() async {
    final current = File(BackendPaths.userToggleStatesJson);
    if (await current.exists()) return;
    final legacy = File(
      joinPath([
        getBackendRoot(),
        'responses',
        _legacyModificationTogglesFileName,
      ]),
    );
    if (!await legacy.exists()) return;
    final fallback = await captureCurrentState();
    final state = await loadFromFile(legacy, fallback: fallback);
    if (state == null) return;
    await current.parent.create(recursive: true);
    await current.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
    try {
      await legacy.delete();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _readRawSavedJson() async {
    final file = await _resolveStateFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool?> readSavedBool(String key) async {
    final json = await _readRawSavedJson();
    final value = json?[key];
    return value is bool ? value : null;
  }

  static Future<UserToggleStates?> _loadSavedState({
    required UserToggleStates fallback,
  }) async {
    final file = await _resolveStateFile();
    final state = await loadFromFile(file, fallback: fallback);
    if (state == null) return null;
    if (file.path != BackendPaths.userToggleStatesJson) {
      await _migrateLegacyFileIfNeeded();
    }
    return state;
  }

  static Future<void> applySavedStateIfPresent() async {
    await _migrateLegacyFileIfNeeded();
    final fallback = await captureCurrentState();
    final state = await _loadSavedState(fallback: fallback);
    if (state == null) return;
    _lastKnownSignature = _signature(state);
    await apply(state);
  }

  static void startWatching() {
    if (_watchSubscription != null) return;
    final targetFile = File(BackendPaths.userToggleStatesJson);
    unawaited(targetFile.parent.create(recursive: true));
    _watchSubscription = targetFile.parent.watch().listen((event) {
      final changedName = event.path
          .replaceAll('/', '\\')
          .split('\\')
          .where((segment) => segment.isNotEmpty)
          .last
          .toLowerCase();
      if (changedName != 'user-toggle-states.json') return;
      if (event is! FileSystemModifyEvent && event is! FileSystemCreateEvent) {
        return;
      }
      _watchDebounce?.cancel();
      _watchDebounce = Timer(const Duration(milliseconds: 150), () {
        unawaited(_handleWatchedFileChange());
      });
    });
  }

  static Future<UserToggleStates?> loadFromFile(
    File file, {
    required UserToggleStates fallback,
  }) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return UserToggleStates.fromJson(decoded, fallback: fallback);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _handleWatchedFileChange() async {
    final fallback = await captureCurrentState();
    final state = await _loadSavedState(fallback: fallback);
    if (state == null) return;
    final signature = _signature(state);
    if (signature == _lastKnownSignature) return;
    _lastKnownSignature = signature;
    await apply(state, notifyExternalListeners: true);
  }

  static Future<void> writeState(
    UserToggleStates state, {
    bool notifyExternalListeners = false,
  }) async {
    final file = File(BackendPaths.userToggleStatesJson);
    final signature = _signature(state);
    _lastKnownSignature = signature;
    final desiredContent = const JsonEncoder.withIndent(
      '  ',
    ).convert(state.toJson());
    if (await file.exists()) {
      try {
        final existingContent = await file.readAsString();
        if (existingContent.trim() == desiredContent.trim()) {
          await _cleanupLegacyToggleStateFiles();
          if (notifyExternalListeners) {
            userToggleStatesRevision.value += 1;
          }
          return;
        }
      } catch (_) {}
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(desiredContent);
    await _cleanupLegacyToggleStateFiles();
    if (notifyExternalListeners) {
      userToggleStatesRevision.value += 1;
    }
  }

  static Future<void> updateState(
    UserToggleStates Function(UserToggleStates current) transform, {
    bool notifyExternalListeners = false,
  }) async {
    final fallback = await captureCurrentState();
    final current = await _loadSavedState(fallback: fallback) ?? fallback;
    await writeState(
      transform(current),
      notifyExternalListeners: notifyExternalListeners,
    );
  }

  static Future<void> _cleanupLegacyToggleStateFiles() async {
    final legacyFiles = <String>[
      BackendPaths.dataTablesUiState,
      BackendPaths.curveTableStateJson,
      BackendPaths.straightBloomStateJson,
      joinPath([
        getBackendRoot(),
        'responses',
        _legacyModificationTogglesFileName,
      ]),
    ];
    for (final path in legacyFiles) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static Future<bool> apply(
    UserToggleStates state, {
    bool notifyExternalListeners = false,
  }) async {
    final config = state.toConfigSettings();
    await ConfigService.save(config, syncUserToggleStates: false);
    await writeState(state);
    appThemeMode.value = ThemeMode.dark;
    appBackgroundPath.value = config.backgroundImagePath;
    appBackgroundBlur.value = config.backgroundBlur;
    appBackgroundParticlesOpacity.value = config.backgroundParticlesOpacity;
    appDialogBlurEnabled.value = config.dialogBlurEnabled;
    appStartupAnimationEnabled.value = config.startupAnimationEnabled;
    await DataTableService._writeUiState(
      state.dataTablesEnabled,
      syncUserToggleStates: false,
    );
    await CurveTableService._writeGlobalEnabledState(
      state.curveTablesEnabled,
      syncUserToggleStates: false,
    );
    await StraightBloomService._writeEnabledState(
      state.straightBloomEnabled,
      syncUserToggleStates: false,
    );
    await DataTableService.setBackendInfiniteRenderEnabled(
      state.backendInfiniteRenderEnabled,
      syncUserToggleStates: false,
    );
    await DataTableService.setSwapCooldownEnabled(
      state.swapCooldownEnabled,
      syncUserToggleStates: false,
    );
    await DataTableService.setVictoryTextReplacementSettings(
      VictoryTextReplacementSettings(
        enabled: state.victoryTextReplacementEnabled,
        placement: state.victoryTextPlacement,
        victory: state.victoryTextVictory,
        royale: state.victoryTextRoyale,
      ),
      syncUserToggleStates: false,
    );
    await ManagedHotfixService.rebuildDefaultGame();
    await syncFromCurrentState();
    if (notifyExternalListeners) {
      userToggleStatesRevision.value += 1;
    }
    return true;
  }
}

class ConfigSettings {
  const ConfigSettings({
    required this.rufusStage,
    required this.waterLevel,
    required this.saveArenaPoints,
    required this.useWaterStorm,
    required this.startBackendOnLaunch,
    required this.backendInfiniteRenderEnabled,
    required this.swapCooldownEnabled,
    required this.disableBackendUpdateCheck,
    required this.useDarkMode,
    required this.backgroundImagePath,
    required this.backgroundBlur,
    required this.backgroundParticlesOpacity,
    required this.dialogBlurEnabled,
    required this.startupAnimationEnabled,
    required this.lastShownUpdateNotesVersion,
  });

  final int rufusStage;
  final int waterLevel;
  final bool saveArenaPoints;
  final bool useWaterStorm;
  final bool startBackendOnLaunch;
  final bool backendInfiniteRenderEnabled;
  final bool swapCooldownEnabled;
  final bool disableBackendUpdateCheck;
  final bool useDarkMode;
  final String backgroundImagePath;
  final double backgroundBlur;
  final double backgroundParticlesOpacity;
  final bool dialogBlurEnabled;
  final bool startupAnimationEnabled;
  final String lastShownUpdateNotesVersion;

  ConfigSettings copyWith({
    int? rufusStage,
    int? waterLevel,
    bool? saveArenaPoints,
    bool? useWaterStorm,
    bool? startBackendOnLaunch,
    bool? backendInfiniteRenderEnabled,
    bool? swapCooldownEnabled,
    bool? disableBackendUpdateCheck,
    bool? useDarkMode,
    String? backgroundImagePath,
    double? backgroundBlur,
    double? backgroundParticlesOpacity,
    bool? dialogBlurEnabled,
    bool? startupAnimationEnabled,
    String? lastShownUpdateNotesVersion,
  }) {
    return ConfigSettings(
      rufusStage: rufusStage ?? this.rufusStage,
      waterLevel: waterLevel ?? this.waterLevel,
      saveArenaPoints: saveArenaPoints ?? this.saveArenaPoints,
      useWaterStorm: useWaterStorm ?? this.useWaterStorm,
      startBackendOnLaunch: startBackendOnLaunch ?? this.startBackendOnLaunch,
      backendInfiniteRenderEnabled:
          backendInfiniteRenderEnabled ?? this.backendInfiniteRenderEnabled,
      swapCooldownEnabled: swapCooldownEnabled ?? this.swapCooldownEnabled,
      disableBackendUpdateCheck:
          disableBackendUpdateCheck ?? this.disableBackendUpdateCheck,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundParticlesOpacity:
          backgroundParticlesOpacity ?? this.backgroundParticlesOpacity,
      dialogBlurEnabled: dialogBlurEnabled ?? this.dialogBlurEnabled,
      startupAnimationEnabled:
          startupAnimationEnabled ?? this.startupAnimationEnabled,
      lastShownUpdateNotesVersion:
          lastShownUpdateNotesVersion ?? this.lastShownUpdateNotesVersion,
    );
  }
}

class ConfigService {
  static const ConfigSettings defaultSettings = ConfigSettings(
    rufusStage: 4,
    waterLevel: 1,
    saveArenaPoints: false,
    useWaterStorm: false,
    startBackendOnLaunch: true,
    backendInfiniteRenderEnabled: true,
    swapCooldownEnabled: false,
    disableBackendUpdateCheck: false,
    useDarkMode: true,
    backgroundImagePath: '',
    backgroundBlur: 15,
    backgroundParticlesOpacity: 1.0,
    dialogBlurEnabled: true,
    startupAnimationEnabled: true,
    lastShownUpdateNotesVersion: '',
  );

  static Future<ConfigSettings> load() async {
    final base = await _loadConfigFile(File(BackendPaths.configIni));
    final gui = await _loadConfigFile(File(_guiConfigPath()));
    final map = {...base, ...gui};
    if (map.isEmpty) {
      return defaultSettings;
    }
    final lastShownUpdateNotesVersion =
        gui['LastShownUpdateNotesVersion'] ?? '';
    final legacyParticlesEnabled =
        (map['BackgroundParticlesEnabled'] ?? 'true').toLowerCase() == 'true';
    final parsedParticlesOpacity = double.tryParse(
      map['BackgroundParticlesOpacity'] ?? '',
    );
    final resolvedParticlesOpacity =
        parsedParticlesOpacity ?? (legacyParticlesEnabled ? 1.0 : 0.0);
    final storedUseDarkMode =
        (map['UseDarkMode'] ?? 'true').toLowerCase() == 'true';
    final shouldPersistDarkMode = !storedUseDarkMode;
    final hasGuiBackendInfiniteRender = gui.containsKey(
      'BackendInfiniteRenderEnabled',
    );
    final hasGuiSwapCooldown = gui.containsKey('SwapCooldownEnabled');
    var resolvedBackendInfiniteRender =
        (map['BackendInfiniteRenderEnabled'] ?? 'true').toLowerCase() == 'true';
    var resolvedSwapCooldown =
        (map['SwapCooldownEnabled'] ?? 'false').toLowerCase() == 'true';
    if (!hasGuiBackendInfiniteRender) {
      resolvedBackendInfiniteRender =
          await DataTableService.isBackendInfiniteRenderEnabled();
    }
    if (!hasGuiSwapCooldown) {
      resolvedSwapCooldown = await DataTableService.isSwapCooldownEnabled();
    }
    final storedWaterLevel = int.tryParse(map['WaterLevel'] ?? '') ?? 0;
    final waterLevelZeroIndexed =
        (map['WaterLevelZeroIndexed'] ?? '').toLowerCase() == 'true';
    final resolvedWaterLevel = _normalizeWaterLevel(
      storedWaterLevel,
      zeroIndexed: waterLevelZeroIndexed,
    );
    final shouldPersistWaterLevel =
        waterLevelZeroIndexed || resolvedWaterLevel != storedWaterLevel;

    final settings = ConfigSettings(
      rufusStage: int.tryParse(map['RufusStage'] ?? '') ?? 1,
      waterLevel: resolvedWaterLevel,
      saveArenaPoints: (map['SaveArenaPoints'] ?? '').toLowerCase() == 'true',
      useWaterStorm: (map['UseWaterStorm'] ?? '').toLowerCase() == 'true',
      startBackendOnLaunch:
          (map['StartBackendOnLaunch'] ?? '').toLowerCase() == 'true',
      backendInfiniteRenderEnabled: resolvedBackendInfiniteRender,
      swapCooldownEnabled: resolvedSwapCooldown,
      disableBackendUpdateCheck:
          (map['DisableBackendUpdateCheck'] ?? '').toLowerCase() == 'true',
      useDarkMode: true,
      backgroundImagePath: map['BackgroundImagePath'] ?? '',
      backgroundBlur: double.tryParse(map['BackgroundBlur'] ?? '') ?? 15,
      backgroundParticlesOpacity: resolvedParticlesOpacity,
      dialogBlurEnabled:
          (map['DialogBlurEnabled'] ?? 'true').toLowerCase() == 'true',
      startupAnimationEnabled:
          (map['StartupAnimationEnabled'] ?? 'true').toLowerCase() == 'true',
      lastShownUpdateNotesVersion: lastShownUpdateNotesVersion,
    );
    if (!hasGuiBackendInfiniteRender ||
        !hasGuiSwapCooldown ||
        shouldPersistWaterLevel ||
        shouldPersistDarkMode) {
      await save(settings, syncUserToggleStates: false);
    }
    return settings;
  }

  static Future<void> save(
    ConfigSettings settings, {
    bool syncUserToggleStates = true,
  }) async {
    final buffer = StringBuffer()
      ..writeln('RufusStage=${settings.rufusStage}')
      ..writeln('WaterLevel=${settings.waterLevel}')
      ..writeln('SaveArenaPoints=${settings.saveArenaPoints}')
      ..writeln('UseWaterStorm=${settings.useWaterStorm}')
      ..writeln('StartBackendOnLaunch=${settings.startBackendOnLaunch}')
      ..writeln(
        'BackendInfiniteRenderEnabled=${settings.backendInfiniteRenderEnabled}',
      )
      ..writeln('SwapCooldownEnabled=${settings.swapCooldownEnabled}')
      ..writeln(
        'DisableBackendUpdateCheck=${settings.disableBackendUpdateCheck}',
      )
      ..writeln('UseDarkMode=true')
      ..writeln('BackgroundImagePath=${settings.backgroundImagePath}')
      ..writeln('BackgroundBlur=${settings.backgroundBlur}')
      ..writeln(
        'BackgroundParticlesEnabled=${settings.backgroundParticlesOpacity > 0}',
      )
      ..writeln(
        'BackgroundParticlesOpacity=${settings.backgroundParticlesOpacity}',
      )
      ..writeln('DialogBlurEnabled=${settings.dialogBlurEnabled}')
      ..writeln('StartupAnimationEnabled=${settings.startupAnimationEnabled}')
      ..writeln(
        'LastShownUpdateNotesVersion=${settings.lastShownUpdateNotesVersion}',
      );
    final backendFile = File(BackendPaths.configIni);
    try {
      await backendFile.writeAsString(buffer.toString());
    } catch (_) {
      // Backend config might be read-only on some installs.
    }
    final guiFile = File(_guiConfigPath());
    try {
      await guiFile.parent.create(recursive: true);
      await guiFile.writeAsString(buffer.toString());
    } catch (_) {}
    if (syncUserToggleStates) {
      await UserToggleStatesService.syncFromCurrentState();
    }
  }

  static String _guiConfigPath() {
    return joinPath([getBackendRoot(), 'gui.ini']);
  }

  static int _normalizeWaterLevel(
    int storedLevel, {
    required bool zeroIndexed,
  }) {
    final normalized = zeroIndexed ? storedLevel + 1 : storedLevel;
    return normalized.clamp(1, 7).toInt();
  }

  static Future<Map<String, String>> _loadConfigFile(File file) async {
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    final map = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          !trimmed.contains('=')) {
        continue;
      }
      final parts = trimmed.split('=');
      map[parts.first.trim()] = parts.sublist(1).join('=').trim();
    }
    return map;
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.downloadUrl,
    this.publishedAt,
    this.notes,
  });

  final String version;
  final String downloadUrl;
  final DateTime? publishedAt;
  final String? notes;
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.isInstaller,
    this.notes,
    this.currentCommit,
    this.latestCommit,
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final bool isInstaller;
  final String? notes;
  final String? currentCommit;
  final String? latestCommit;

  String get currentLabel => _formatVersion(currentVersion);
  String get latestLabel => _formatVersion(latestVersion);
}

String? selectReleaseInstallerUrl(dynamic assetsRaw) {
  if (assetsRaw is! List) return null;

  String? atlasSetupExe;
  String? setupExe;
  String? atlasExe;
  String? firstExe;
  String? atlasInstallerMsi;
  String? installerMsi;
  String? atlasMsi;
  String? firstMsi;

  for (final asset in assetsRaw) {
    if (asset is! Map<String, dynamic>) continue;
    final name = asset['name']?.toString().toLowerCase() ?? '';
    final url = asset['browser_download_url']?.toString().trim();
    if (url == null || url.isEmpty || name.isEmpty) continue;

    final isAtlasAsset = name.contains('atlas') || name.contains('backend');
    final isInstaller =
        name.contains('setup') ||
        name.contains('installer') ||
        name.contains('install');

    if (name.endsWith('.exe')) {
      if (isInstaller && isAtlasAsset) {
        atlasSetupExe ??= url;
      } else if (isInstaller) {
        setupExe ??= url;
      } else if (isAtlasAsset) {
        atlasExe ??= url;
      } else {
        firstExe ??= url;
      }
      continue;
    }

    if (name.endsWith('.msi')) {
      if (isInstaller && isAtlasAsset) {
        atlasInstallerMsi ??= url;
      } else if (isInstaller) {
        installerMsi ??= url;
      } else if (isAtlasAsset) {
        atlasMsi ??= url;
      } else {
        firstMsi ??= url;
      }
    }
  }

  return atlasSetupExe ??
      setupExe ??
      atlasExe ??
      firstExe ??
      atlasInstallerMsi ??
      installerMsi ??
      atlasMsi ??
      firstMsi;
}

class UpdateService {
  static const String _repo = 'cipherfps/ATLAS-Backend';
  static const String _branch = 'gui';
  static const String _mainZipUrl =
      'https://github.com/cipherfps/ATLAS-Backend/archive/refs/heads/gui.zip';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases/latest';
  static const String _releasesListUrl =
      'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases?per_page=30';

  static Future<UpdateInfo?> checkForUpdate() async {
    final detectedVersion = await _readBackendVersionFromCandidates();
    final currentVersion = detectedVersion.isEmpty ? '0.0.0' : detectedVersion;
    final release = await _fetchLatestReleaseInfo();
    if (release != null && _isNewerVersion(release.version, currentVersion)) {
      final downloadUrl = release.installerUrl ?? _mainZipUrl;
      final isInstaller = release.installerUrl != null;
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: release.version,
        downloadUrl: downloadUrl,
        isInstaller: isInstaller,
        notes: release.notes,
        currentCommit: null,
        latestCommit: null,
      );
    }

    // Fallback for unreleased GUI branch updates.
    final remotePackage = await _fetchRemotePackage();
    if (remotePackage == null) return null;
    final latestVersion = (remotePackage['version'] ?? currentVersion)
        .toString();
    if (!_isNewerVersion(latestVersion, currentVersion)) return null;

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: _mainZipUrl,
      isInstaller: false,
      notes: null,
      currentCommit: null,
      latestCommit: null,
    );
  }

  static Future<List<ReleaseInfo>> fetchReleaseHistory() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_releasesListUrl));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return [];
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! List) return [];

      final releases = <ReleaseInfo>[];
      for (final entry in json) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['draft'] == true) continue;
        final tag = entry['tag_name']?.toString().trim();
        if (tag == null || tag.isEmpty) continue;

        final installerUrl = selectReleaseInstallerUrl(entry['assets']);
        if (installerUrl == null) continue;

        DateTime? published;
        final publishedRaw = entry['published_at']?.toString();
        if (publishedRaw != null) {
          published = DateTime.tryParse(publishedRaw);
        }

        releases.add(
          ReleaseInfo(
            version: tag,
            downloadUrl: installerUrl,
            publishedAt: published,
            notes: entry['body']?.toString(),
          ),
        );
      }

      releases.sort(
        (a, b) => _compareVersions(
          _normalizeVersion(b.version),
          _normalizeVersion(a.version),
        ),
      );
      return releases;
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }

  static Future<void> downloadAndApply(
    UpdateInfo info,
    ValueNotifier<double>? progress,
  ) async {
    if (info.isInstaller) {
      final installerFile = await _downloadInstaller(
        info.downloadUrl,
        progress,
      );
      final lowerPath = installerFile.path.toLowerCase();
      if (lowerPath.endsWith('.msi')) {
        await Process.start('msiexec', [
          '/i',
          installerFile.path,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start(
          installerFile.path,
          const [],
          mode: ProcessStartMode.detached,
        );
      }
      exit(0);
    } else {
      final zipFile = await _downloadZip(info.downloadUrl, progress);
      await _applyZip(zipFile);
    }
  }

  static Future<({String version, String? installerUrl, String? notes})?>
  _fetchLatestReleaseInfo() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name']?.toString().trim();
      if (tag == null || tag.isEmpty) return null;
      final installerUrl = selectReleaseInstallerUrl(json['assets']);
      return (
        version: tag,
        installerUrl: installerUrl,
        notes: json['body']?.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _fetchRemotePackage() async {
    final url = Uri.parse(
      'https://raw.githubusercontent.com/$_repo/$_branch/package.json?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<File> _downloadZip(
    String url,
    ValueNotifier<double>? progress,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('atlas_update_');
    final zipFile = File(joinPath([tempDir.path, 'update.zip']));
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = zipFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && progress != null) {
          progress.value = received / total;
        }
      }
      await sink.close();
      if (progress != null) {
        progress.value = 1;
      }
      return zipFile;
    } finally {
      client.close();
    }
  }

  static Future<File> _downloadInstaller(
    String url,
    ValueNotifier<double>? progress,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('atlas_update_');
    final uri = Uri.parse(url);
    var fileName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (fileName.trim().isEmpty) {
      fileName = 'ATLAS-Backend-Setup.exe';
    }
    final installerFile = File(joinPath([tempDir.path, fileName]));
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = installerFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && progress != null) {
          progress.value = received / total;
        }
      }
      await sink.close();
      if (progress != null) {
        progress.value = 1;
      }
      return installerFile;
    } finally {
      client.close();
    }
  }

  static Future<void> _applyZip(File zipFile) async {
    final backendRoot = getBackendRoot();
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final rawPath = file.name;
      final relative = _stripZipRoot(rawPath);
      if (relative.isEmpty) continue;
      if (_shouldPreserve(relative)) continue;

      final outPath = joinPath([backendRoot, ...relative.split('/')]);
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  static String _stripZipRoot(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return '';
    return parts.sublist(1).join('/');
  }

  static bool _shouldPreserve(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/').toLowerCase();
    if (normalized.startsWith('atlas_gui_flutter/')) return true;
    if (normalized.startsWith('node_modules/')) return true;
    if (normalized.startsWith('exports/')) return true;
    if (_mutableUpdateFileRelativePaths.contains(normalized)) return true;
    for (final prefix in _mutableUpdateDirRelativePrefixes) {
      if (normalized.startsWith(prefix)) return true;
    }

    if (normalized.startsWith('static/profiles/')) {
      final rest = normalized.substring('static/profiles/'.length);
      return !rest.startsWith('profile_');
    }
    if (normalized.startsWith('static/clientsettings/')) {
      final rest = normalized.substring('static/clientsettings/'.length);
      return !rest.startsWith('config/');
    }
    return false;
  }
}

const List<String> _mutableUpdateFileRelativePaths = [
  'gui.ini',
  'static/athenaprofiles/profiles-ui-state.json',
  'responses/user-toggle-states.json',
  'responses/curves.json',
  'responses/curvetables-state.json',
  'responses/datatables.json',
  'responses/datatables-ui.json',
  'static/hotfixes/defaultgame data/straightbloom.ini',
  'static/hotfixes/defaultgame data/fixes.ini',
  'static/hotfixes/defaultgame data/curvetables.ini',
  'static/hotfixes/defaultgame data/datatables.ini',
  'responses/user-curvetables.ini',
  'responses/user-datatables.ini',
  'responses/epic-settings.json',
  'responses/modifications-backup.json',
  'responses/straight-bloom-state.json',
  'src/config/config.ini',
  'static/hotfixes/defaultengine.ini',
  'static/hotfixes/defaultgame.ini',
];

const List<String> _mutableUpdateDirRelativePrefixes = [
  'public/items/custom_',
  'public/items/custom-groups/',
];

class UpdateNotesService {
  static const UpdateNotesStyle _defaultStyle = UpdateNotesStyle(
    hrThickness: 0.6,
    hrOpacity: 0.18,
  );

  static Future<UpdateNotesPayload?> loadNotes() async {
    final target = await _findNotesFile();
    if (target == null) return null;
    final content = await target.readAsString();
    final parsed = _extractStyleAndContent(content);
    if (parsed.notes.trim().isEmpty) return null;
    return parsed;
  }

  static Future<File?> _findNotesFile() async {
    final candidates = <String>[
      BackendPaths.updateNotesMarkdown,
      BackendPaths.updateNotesText,
      joinPath([getInstallationRoot(), 'update-notes.md']),
      joinPath([getInstallationRoot(), 'update-notes.txt']),
      joinPath([Directory.current.path, 'update-notes.md']),
      joinPath([Directory.current.path, 'update-notes.txt']),
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    return null;
  }

  static UpdateNotesPayload _extractStyleAndContent(String content) {
    final regex = RegExp(
      r'<!--\s*hr:\s*thickness\s*=\s*([0-9]*\.?[0-9]+)\s+opacity\s*=\s*([0-9]*\.?[0-9]+)\s*-->',
      caseSensitive: false,
    );
    final match = regex.firstMatch(content);
    var style = _defaultStyle;
    var notes = content;
    if (match != null) {
      final thickness = double.tryParse(match.group(1) ?? '');
      final opacity = double.tryParse(match.group(2) ?? '');
      if (thickness != null || opacity != null) {
        style = style.copyWith(hrThickness: thickness, hrOpacity: opacity);
      }
      notes = content.replaceFirst(match.group(0) ?? '', '').trim();
    }
    return UpdateNotesPayload(notes: notes, style: style);
  }
}

class UpdateNotesPayload {
  const UpdateNotesPayload({required this.notes, required this.style});

  final String notes;
  final UpdateNotesStyle style;
}

class UpdateNotesStyle {
  const UpdateNotesStyle({required this.hrThickness, required this.hrOpacity});

  final double hrThickness;
  final double hrOpacity;

  UpdateNotesStyle copyWith({double? hrThickness, double? hrOpacity}) {
    return UpdateNotesStyle(
      hrThickness: hrThickness ?? this.hrThickness,
      hrOpacity: hrOpacity ?? this.hrOpacity,
    );
  }
}

final List<md.BlockSyntax> _roundedHrBlockSyntaxes = [
  _RoundedHrSyntax(),
  ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
];

final List<md.InlineSyntax> _roundedHrInlineSyntaxes =
    md.ExtensionSet.gitHubFlavored.inlineSyntaxes;

class _RoundedHrSyntax extends md.BlockSyntax {
  const _RoundedHrSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}([-*_])[ \t]*\1[ \t]*\1(?:\1|[ \t])*$');

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Element.empty('rounded-hr');
  }
}

class _MarkdownHrBuilder extends MarkdownElementBuilder {
  _MarkdownHrBuilder({
    required this.color,
    required this.thickness,
    required this.verticalPadding,
  });

  final Color color;
  final double thickness;
  final double verticalPadding;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: thickness,
          width: double.infinity,
          child: DecoratedBox(decoration: BoxDecoration(color: color)),
        ),
      ),
    );
  }
}

class UpdateBackupService {
  static const String _backupFolderName = 'update-backup';

  static Future<void> backupBeforeUpdate() async {
    final backupRoot = Directory(_resolveBackupRoot());
    if (await backupRoot.exists()) {
      await backupRoot.delete(recursive: true);
    }
    await backupRoot.create(recursive: true);

    final backendRoot = getBackendRoot();
    final entries = _mutableUpdateEntries(backendRoot);

    for (final entry in entries) {
      final target = joinPath([
        backupRoot.path,
        ...entry.relativeParts(backendRoot),
      ]);
      if (entry.isDir) {
        final dir = Directory(entry.path);
        if (!dir.existsSync()) continue;
        await _copyDirectory(dir, Directory(target));
      } else {
        final file = File(entry.path);
        if (!file.existsSync()) continue;
        await File(target).parent.create(recursive: true);
        await file.copy(target);
      }
    }

    // Backup user-created profiles only (exclude template profiles)
    final profilesSource = Directory(
      joinPath([backendRoot, 'static', 'profiles']),
    );
    if (profilesSource.existsSync()) {
      final profilesTarget = Directory(
        joinPath([backupRoot.path, 'static', 'profiles']),
      );
      await _copyDirectoryExcludingProfiles(
        profilesSource,
        profilesTarget,
        _templateProfiles,
      );
    }

    // Don't backup built-in Profile Presets - they are templates.
    // But DO backup custom preset folders and their JSON config.
    final customPresetsFile = File(
      joinPath([
        backendRoot,
        'static',
        'athenaprofiles',
        'custom-presets.json',
      ]),
    );
    if (customPresetsFile.existsSync()) {
      final targetCustomPresetsFile = File(
        joinPath([
          backupRoot.path,
          'static',
          'athenaprofiles',
          'custom-presets.json',
        ]),
      );
      await targetCustomPresetsFile.parent.create(recursive: true);
      await customPresetsFile.copy(targetCustomPresetsFile.path);

      try {
        final customConfig =
            jsonDecode(await customPresetsFile.readAsString())
                as Map<String, dynamic>;
        final customPresetsList =
            customConfig['presets'] as List<dynamic>? ?? [];
        for (final p in customPresetsList) {
          final map = p as Map<String, dynamic>;
          final folder = map['folder'] as String?;
          if (folder == null || folder.trim().isEmpty) continue;
          final customPresetDir = Directory(
            joinPath([
              backendRoot,
              'static',
              'athenaprofiles',
              'Profile Presets',
              folder,
            ]),
          );
          if (!customPresetDir.existsSync()) continue;
          final targetPresetDir = Directory(
            joinPath([
              backupRoot.path,
              'static',
              'athenaprofiles',
              'Profile Presets',
              folder,
            ]),
          );
          await _copyDirectory(customPresetDir, targetPresetDir);
        }
      } catch (_) {}
    }

    final manifest = {
      'version': _normalizeVersion(await _readBackendVersion()),
      'createdAt': DateTime.now().toIso8601String(),
    };
    await File(
      joinPath([backupRoot.path, 'manifest.json']),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  }

  static Future<void> restoreIfNeeded(BuildContext context) async {
    final backupRoot = Directory(_resolveBackupRoot());
    if (!backupRoot.existsSync()) return;

    final backendRoot = getBackendRoot();
    final entries = _mutableUpdateEntries(backupRoot.path);

    for (final entry in entries) {
      final target = joinPath([
        backendRoot,
        ...entry.relativeParts(backupRoot.path),
      ]);
      if (entry.isDir) {
        final dir = Directory(entry.path);
        if (!dir.existsSync()) continue;
        await _copyDirectory(dir, Directory(target));
      } else {
        final file = File(entry.path);
        if (!file.existsSync()) continue;
        await File(target).parent.create(recursive: true);
        await file.copy(target);
      }
    }

    // Restore user-created profiles only (exclude template profiles)
    final profilesSource = Directory(
      joinPath([backupRoot.path, 'static', 'profiles']),
    );
    if (profilesSource.existsSync()) {
      final profilesTarget = Directory(
        joinPath([backendRoot, 'static', 'profiles']),
      );
      await _copyDirectoryExcludingProfiles(
        profilesSource,
        profilesTarget,
        _templateProfiles,
      );
    }

    // Note: Built-in Profile Presets are templates and are not backed up.
    // Custom preset folders and their config are restored below.
    final customPresetsBackup = File(
      joinPath([
        backupRoot.path,
        'static',
        'athenaprofiles',
        'custom-presets.json',
      ]),
    );
    if (customPresetsBackup.existsSync()) {
      final targetCustomPresetsFile = File(
        joinPath([
          backendRoot,
          'static',
          'athenaprofiles',
          'custom-presets.json',
        ]),
      );
      await targetCustomPresetsFile.parent.create(recursive: true);
      await customPresetsBackup.copy(targetCustomPresetsFile.path);

      try {
        final customConfig =
            jsonDecode(await customPresetsBackup.readAsString())
                as Map<String, dynamic>;
        final customPresetsList =
            customConfig['presets'] as List<dynamic>? ?? [];
        for (final p in customPresetsList) {
          final map = p as Map<String, dynamic>;
          final folder = map['folder'] as String?;
          if (folder == null || folder.trim().isEmpty) continue;
          final customPresetDir = Directory(
            joinPath([
              backupRoot.path,
              'static',
              'athenaprofiles',
              'Profile Presets',
              folder,
            ]),
          );
          if (!customPresetDir.existsSync()) continue;
          final targetPresetDir = Directory(
            joinPath([
              backendRoot,
              'static',
              'athenaprofiles',
              'Profile Presets',
              folder,
            ]),
          );
          await _copyDirectory(customPresetDir, targetPresetDir);
        }
      } catch (_) {}
    }

    // Rebuild managed hotfix output after restore so the restored source files
    // and current DefaultGame.ini stay in sync.
    await ManagedHotfixService.ensureInitialized();

    final restoredConfig = await ConfigService.load();
    appThemeMode.value = ThemeMode.dark;
    appBackgroundPath.value = restoredConfig.backgroundImagePath;
    appBackgroundBlur.value = restoredConfig.backgroundBlur;
    appBackgroundParticlesOpacity.value =
        restoredConfig.backgroundParticlesOpacity;
    appDialogBlurEnabled.value = restoredConfig.dialogBlurEnabled;
    appStartupAnimationEnabled.value = restoredConfig.startupAnimationEnabled;

    await backupRoot.delete(recursive: true);

    if (context.mounted) {
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Restored data from previous version.')),
      );
    }
  }

  static String _resolveBackupRoot() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = localAppData ?? Directory.systemTemp.path;
    return joinPath([base, 'ATLAS', _backupFolderName]);
  }

  static Future<String> _readBackendVersion() async {
    return _readBackendVersionFromCandidates();
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = _entityName(entity);
      final newPath = joinPath([destination.path, name]);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  static const Set<String> _templateProfiles = {
    'profile_athena.json',
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };

  static Future<void> _copyDirectoryExcludingProfiles(
    Directory source,
    Directory destination,
    Set<String> excludeFiles, {
    bool isRootLevel = true,
  }) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = _entityName(entity);
      // Only exclude template files at root level, not in user subfolders
      if (isRootLevel && excludeFiles.contains(name)) continue;
      final newPath = joinPath([destination.path, name]);
      if (entity is Directory) {
        await _copyDirectoryExcludingProfiles(
          entity,
          Directory(newPath),
          excludeFiles,
          isRootLevel: false,
        );
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}

List<_BackupEntry> _mutableUpdateEntries(String root) {
  final entries = <_BackupEntry>[
    _BackupEntry.file(joinPath([root, 'gui.ini'])),
    _BackupEntry.file(
      joinPath([root, 'static', 'athenaprofiles', 'profiles-ui-state.json']),
    ),
    _BackupEntry.file(joinPath([root, 'responses', 'user-toggle-states.json'])),
    _BackupEntry.dir(joinPath([root, 'exports'])),
    _BackupEntry.dir(joinPath([root, 'static', 'ClientSettings'])),
    _BackupEntry.file(
      joinPath([root, 'static', 'hotfixes', 'DefaultGame.ini']),
    ),
    _BackupEntry.file(
      joinPath([root, 'static', 'hotfixes', 'DefaultEngine.ini']),
    ),
    _BackupEntry.file(joinPath([root, 'responses', 'curves.json'])),
    _BackupEntry.file(joinPath([root, 'responses', 'curvetables-state.json'])),
    _BackupEntry.file(joinPath([root, 'responses', 'datatables.json'])),
    _BackupEntry.file(joinPath([root, 'responses', 'datatables-ui.json'])),
    _BackupEntry.file(
      joinPath([
        root,
        'static',
        'hotfixes',
        'DefaultGame Data',
        'StraightBloom.ini',
      ]),
    ),
    _BackupEntry.file(
      joinPath([root, 'static', 'hotfixes', 'DefaultGame Data', 'Fixes.ini']),
    ),
    _BackupEntry.file(
      joinPath([
        root,
        'static',
        'hotfixes',
        'DefaultGame Data',
        'CurveTables.ini',
      ]),
    ),
    _BackupEntry.file(
      joinPath([
        root,
        'static',
        'hotfixes',
        'DefaultGame Data',
        'DataTables.ini',
      ]),
    ),
    _BackupEntry.file(joinPath([root, 'responses', 'user-curvetables.ini'])),
    _BackupEntry.file(joinPath([root, 'responses', 'user-datatables.ini'])),
    _BackupEntry.file(joinPath([root, 'responses', 'epic-settings.json'])),
    _BackupEntry.file(
      joinPath([root, 'responses', 'modifications-backup.json']),
    ),
    _BackupEntry.file(
      joinPath([root, 'responses', 'straight-bloom-state.json']),
    ),
    _BackupEntry.file(joinPath([root, 'src', 'config', 'config.ini'])),
    _BackupEntry.dir(joinPath([root, 'public', 'items', 'custom-groups'])),
  ];

  final publicItemsDir = Directory(joinPath([root, 'public', 'items']));
  if (publicItemsDir.existsSync()) {
    for (final entity in publicItemsDir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = _entityName(entity);
      if (!name.toLowerCase().startsWith('custom_')) continue;
      entries.add(_BackupEntry.file(entity.path));
    }
  }

  return entries;
}

class _BackupEntry {
  _BackupEntry._(this.path, this.isDir);

  final String path;
  final bool isDir;

  static _BackupEntry dir(String path) => _BackupEntry._(path, true);
  static _BackupEntry file(String path) => _BackupEntry._(path, false);

  List<String> relativeParts(String root) {
    final normalizedRoot = root.replaceAll('\\', '/');
    final normalizedPath = path.replaceAll('\\', '/');
    if (!normalizedPath.startsWith(normalizedRoot)) {
      return normalizedPath.split('/');
    }
    final relative = normalizedPath
        .substring(normalizedRoot.length)
        .replaceFirst(RegExp('^/'), '');
    if (relative.isEmpty) return [];
    return relative.split('/');
  }
}

String _formatVersion(String version) {
  final trimmed = version.trim();
  return trimmed.startsWith('v') ? trimmed : 'v$trimmed';
}

Future<String> _readBackendVersionFromCandidates() async {
  final packagePaths = <String>[
    joinPath([getBackendRoot(), 'package.json']),
    joinPath([getInstallationRoot(), 'package.json']),
    joinPath([Directory.current.path, 'package.json']),
  ];
  final seen = <String>{};
  for (final path in packagePaths) {
    if (!seen.add(path)) continue;
    final packageFile = File(path);
    if (!await packageFile.exists()) continue;
    try {
      final json =
          jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
      final version = json['version']?.toString().trim();
      if (version != null && version.isNotEmpty) {
        return version;
      }
    } catch (_) {
      // Continue to the next candidate.
    }
  }

  return '';
}

String _normalizeVersion(String version) {
  final trimmed = version.trim();
  return trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
}

int _compareVersions(String left, String right) {
  final leftParts = left
      .split('.')
      .map(int.tryParse)
      .map((v) => v ?? 0)
      .toList();
  final rightParts = right
      .split('.')
      .map(int.tryParse)
      .map((v) => v ?? 0)
      .toList();
  final maxLen = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < maxLen; i++) {
    final l = i < leftParts.length ? leftParts[i] : 0;
    final r = i < rightParts.length ? rightParts[i] : 0;
    if (l == r) continue;
    return l > r ? 1 : -1;
  }
  return 0;
}

bool _isNewerVersion(String latest, String current) {
  return _compareVersions(
        _normalizeVersion(latest),
        _normalizeVersion(current),
      ) >
      0;
}

String _formatReleaseDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[date.month - 1];
  return '$month ${date.day}, ${date.year}';
}

class DataService {
  static const Set<String> _profileTemplateFiles = {
    'profile_athena.json',
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };
  static const String _profileTemplateBackupDirName = '.defaults';

  static Future<void> clearBackendData(BuildContext context) async {
    final confirm = await _confirmDialog(
      context,
      'Clear all backend data? This will reset user Profiles, Client settings, DataTables, CurveTables, and Straight Bloom.',
    );
    if (!confirm) return;
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings']),
    );
    final backupFile = File(BackendPaths.modificationsBackup);

    if (await profilesDir.exists()) {
      await _ensureProfileTemplateBackup(profilesDir);
      await for (final entity in profilesDir.list()) {
        final name = _entityName(entity);
        if (_profileTemplateFiles.contains(name)) continue;
        await entity.delete(recursive: true);
      }
      await _restoreProfileTemplates(profilesDir);
    }

    if (await clientSettingsDir.exists()) {
      await for (final entity in clientSettingsDir.list()) {
        final name = _entityName(entity);
        if (name.toLowerCase() == 'config') continue;
        await entity.delete(recursive: true);
      }
    }

    await _resetCatalogsToFreshInstallDefaults();
    await _deleteCustomCurveAndDataTableAssets();
    await _restoreFreshInstallHotfixFiles();
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await UserToggleStatesService.apply(
      UserToggleStatesService.freshInstallDefaults(),
      notifyExternalListeners: true,
    );

    if (context.mounted) {
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Backend data cleared.')),
      );
    }
  }

  static Future<void> _resetCatalogsToFreshInstallDefaults() async {
    final defaultCurves = await CurveTableService._loadDefaultCurveMap();
    await CurveTableService._writeCurveMap(
      File(BackendPaths.curvesJson),
      defaultCurves ?? <String, dynamic>{},
    );

    final defaultDataTables = await DataTableService._loadDefaultDataTableMap();
    await DataTableService._writeDataTableMap(
      File(BackendPaths.dataTablesJson),
      defaultDataTables ?? <String, dynamic>{},
    );
  }

  static Future<void> _deleteCustomCurveAndDataTableAssets() async {
    final customGroupDir = Directory(
      joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
    );
    await _clearDirectory(customGroupDir);
    if (await customGroupDir.exists()) {
      try {
        await customGroupDir.delete();
      } catch (_) {}
    }

    final itemsDir = Directory(joinPath([getBackendRoot(), 'public', 'items']));
    if (!await itemsDir.exists()) {
      return;
    }

    await for (final entity in itemsDir.list(recursive: false)) {
      if (entity is! File) continue;
      final name = _basename(entity.path).toLowerCase();
      if (!name.startsWith('custom_')) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  static Future<void> _restoreFreshInstallHotfixFiles() async {
    await _restoreInstalledFile(
      relativeParts: ['static', 'hotfixes', 'DefaultGame.ini'],
      targetPath: BackendPaths.defaultGameIni,
    );
    await _restoreInstalledFile(
      relativeParts: ['static', 'hotfixes', 'DefaultEngine.ini'],
      targetPath: BackendPaths.defaultEngineIni,
    );
    await _restoreInstalledFile(
      relativeParts: [
        'static',
        'hotfixes',
        'DefaultGame Data',
        'StraightBloom.ini',
      ],
      targetPath: BackendPaths.straightBloomLinesIni,
    );
    await _restoreInstalledFile(
      relativeParts: ['static', 'hotfixes', 'DefaultGame Data', 'Fixes.ini'],
      targetPath: BackendPaths.fixesLinesIni,
    );
    await ManagedHotfixService.writeLines(
      File(BackendPaths.curveTableLinesIni),
      const [],
    );
    await ManagedHotfixService.writeLines(
      File(BackendPaths.dataTableLinesIni),
      const [],
    );
  }

  static Future<void> _restoreInstalledFile({
    required List<String> relativeParts,
    required String targetPath,
  }) async {
    final sourcePath = joinPath([getInstallationRoot(), ...relativeParts]);
    if (_samePath(sourcePath, targetPath)) {
      return;
    }
    final source = File(sourcePath);
    if (!await source.exists()) {
      return;
    }
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
  }

  static Future<void> exportData(BuildContext context) async {
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    final hotfixDataDir = Directory(
      joinPath([exportsRoot.path, 'DefaultGame Data']),
    );
    final profilesDir = Directory(joinPath([exportsRoot.path, 'Profiles']));
    final clientDir = Directory(joinPath([exportsRoot.path, 'ClientSettings']));
    final toggleStatesFile = File(
      joinPath([exportsRoot.path, 'user-toggle-states.json']),
    );
    if (await _hasExistingExport(
      hotfixDataDir,
      profilesDir,
      clientDir,
      toggleStatesFile: toggleStatesFile,
    )) {
      if (!context.mounted) return;
      final confirm = await _confirmDialog(
        context,
        'Exports already exist. Overwrite them?',
      );
      if (!confirm) return;
      await _clearDirectory(hotfixDataDir);
      await _clearDirectory(profilesDir);
      await _clearDirectory(clientDir);
      if (await toggleStatesFile.exists()) {
        await toggleStatesFile.delete();
      }
    }
    await hotfixDataDir.create(recursive: true);
    await profilesDir.create(recursive: true);
    await clientDir.create(recursive: true);
    await _clearNonDirectoryEntries(profilesDir);
    await _clearNonDirectoryEntries(clientDir);

    final exportedCurveTables = await _copyFileIfExists(
      File(BackendPaths.curveTableLinesIni),
      File(joinPath([hotfixDataDir.path, 'CurveTables.ini'])),
    );
    final exportedDataTables = await _copyFileIfExists(
      File(BackendPaths.dataTableLinesIni),
      File(joinPath([hotfixDataDir.path, 'DataTables.ini'])),
    );
    final exportedCurvesCatalog = await _copyFileIfExists(
      File(BackendPaths.curvesJson),
      File(joinPath([hotfixDataDir.path, 'curves.json'])),
    );
    final exportedDataTablesCatalog = await _copyFileIfExists(
      File(BackendPaths.dataTablesJson),
      File(joinPath([hotfixDataDir.path, 'datatables.json'])),
    );
    final exportedToggleStates = await _copyFileIfExists(
      File(BackendPaths.userToggleStatesJson),
      toggleStatesFile,
    );
    final exportedCustomGroupImages = await _copyDirectoryIfHasFiles(
      Directory(
        joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
      ),
      Directory(joinPath([hotfixDataDir.path, 'custom-groups'])),
    );
    final exportedCustomItemImages = await _copyMatchingFilesIfAny(
      Directory(joinPath([getBackendRoot(), 'public', 'items'])),
      Directory(joinPath([hotfixDataDir.path, 'custom-items'])),
      (name) => name.toLowerCase().startsWith('custom_'),
    );
    final exportedProfilesUiState = await _copyFileIfExists(
      File(ProfilesUiStateService._statePath()),
      File(joinPath([exportsRoot.path, 'profiles-ui-state.json'])),
    );

    final profilesExported = await _copyNonEmptyChildDirs(
      Directory(joinPath([getBackendRoot(), 'static', 'profiles'])),
      profilesDir,
      skipDirs: {_profileTemplateBackupDirName},
    );
    final clientExported = await _copyNonEmptyChildDirs(
      Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings'])),
      clientDir,
    );

    // Export custom presets
    int customPresetsExported = 0;
    final customPresetsSource = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'custom-presets.json',
      ]),
    );
    if (await customPresetsSource.exists()) {
      try {
        final customConfig =
            jsonDecode(await customPresetsSource.readAsString())
                as Map<String, dynamic>;
        final customPresetsList =
            customConfig['presets'] as List<dynamic>? ?? [];
        if (customPresetsList.isNotEmpty) {
          final customPresetsExportDir = Directory(
            joinPath([exportsRoot.path, 'CustomPresets']),
          );
          await customPresetsExportDir.create(recursive: true);
          await customPresetsSource.copy(
            joinPath([customPresetsExportDir.path, 'custom-presets.json']),
          );
          for (final p in customPresetsList) {
            final map = p as Map<String, dynamic>;
            final folder = map['folder'] as String?;
            if (folder == null || folder.trim().isEmpty) continue;
            final presetDir = Directory(
              joinPath([
                getBackendRoot(),
                'static',
                'athenaprofiles',
                'Profile Presets',
                folder,
              ]),
            );
            if (!await presetDir.exists()) continue;
            await _copyDir(
              presetDir,
              Directory(joinPath([customPresetsExportDir.path, folder])),
            );
            customPresetsExported++;
          }
        }
      } catch (_) {}
    }

    await _clearNonDirectoryEntries(profilesDir);
    await _clearNonDirectoryEntries(clientDir);

    if (!exportedCurveTables &&
        !exportedDataTables &&
        !exportedCurvesCatalog &&
        !exportedDataTablesCatalog &&
        !exportedToggleStates &&
        !exportedProfilesUiState &&
        !exportedCustomGroupImages &&
        !exportedCustomItemImages &&
        profilesExported == 0 &&
        clientExported == 0 &&
        customPresetsExported == 0) {
      await _deleteIfEmpty(profilesDir);
      await _deleteIfEmpty(clientDir);
      await _deleteIfEmpty(hotfixDataDir);
      if (await toggleStatesFile.exists()) {
        await toggleStatesFile.delete();
      }
      if (context.mounted) {
        showAtlasSnackBar(
          context,
          const SnackBar(content: Text('No data found to export.')),
        );
      }
      return;
    }

    if (context.mounted) {
      await _showExportSummary(
        context,
        exportedToggleStates: exportedToggleStates,
        exportedProfilesUiState: exportedProfilesUiState,
        exportedCurveTables: exportedCurveTables,
        exportedDataTables: exportedDataTables,
        exportedCurvesCatalog: exportedCurvesCatalog,
        exportedDataTablesCatalog: exportedDataTablesCatalog,
        exportedCustomGroupImages: exportedCustomGroupImages,
        exportedCustomItemImages: exportedCustomItemImages,
        profilesExported: profilesExported,
        clientExported: clientExported,
        customPresetsExported: customPresetsExported,
      );
    }
  }

  static Future<void> importData(BuildContext context) async {
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    final hotfixDataDir = Directory(
      joinPath([exportsRoot.path, 'DefaultGame Data']),
    );
    final profilesDir = Directory(joinPath([exportsRoot.path, 'Profiles']));
    final clientDir = Directory(joinPath([exportsRoot.path, 'ClientSettings']));
    final toggleStatesFile = File(
      joinPath([exportsRoot.path, 'user-toggle-states.json']),
    );
    if (!await _hasExistingExport(
      hotfixDataDir,
      profilesDir,
      clientDir,
      toggleStatesFile: toggleStatesFile,
    )) {
      if (context.mounted) {
        showAtlasSnackBar(
          context,
          const SnackBar(content: Text('No exported data found.')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final confirm = await _confirmDialog(
      context,
      'Importing will overwrite existing data. Continue?',
    );
    if (!confirm) return;

    await _importFolderChildren(
      profilesDir,
      Directory(joinPath([getBackendRoot(), 'static', 'profiles'])),
      skipFiles: _profileTemplateFiles,
      skipDirs: {_profileTemplateBackupDirName},
      onlyDirs: true,
    );
    await _importFolderChildren(
      clientDir,
      Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings'])),
      onlyDirs: true,
    );

    // Import custom presets
    final customPresetsExportDir = Directory(
      joinPath([exportsRoot.path, 'CustomPresets']),
    );
    if (await customPresetsExportDir.exists()) {
      final exportedCustomPresetsFile = File(
        joinPath([customPresetsExportDir.path, 'custom-presets.json']),
      );
      if (await exportedCustomPresetsFile.exists()) {
        try {
          final customConfig =
              jsonDecode(await exportedCustomPresetsFile.readAsString())
                  as Map<String, dynamic>;
          final customPresetsList =
              customConfig['presets'] as List<dynamic>? ?? [];
          final presetsDir = Directory(
            joinPath([
              getBackendRoot(),
              'static',
              'athenaprofiles',
              'Profile Presets',
            ]),
          );
          await presetsDir.create(recursive: true);
          for (final p in customPresetsList) {
            final map = p as Map<String, dynamic>;
            final folder = map['folder'] as String?;
            if (folder == null || folder.trim().isEmpty) continue;
            final sourcePresetDir = Directory(
              joinPath([customPresetsExportDir.path, folder]),
            );
            if (!await sourcePresetDir.exists()) continue;
            final targetPresetDir = Directory(
              joinPath([presetsDir.path, folder]),
            );
            if (await targetPresetDir.exists()) {
              await targetPresetDir.delete(recursive: true);
            }
            await _copyDir(sourcePresetDir, targetPresetDir);
          }
          // Merge custom presets into existing custom-presets.json
          final existingConfig =
              await ProfileService._loadCustomPresetsConfig();
          final existingFolders = <String>{};
          final existingList =
              existingConfig['presets'] as List<dynamic>? ?? [];
          for (final p in existingList) {
            final map = p as Map<String, dynamic>;
            final folder = (map['folder'] as String?)?.trim().toLowerCase();
            if (folder != null) existingFolders.add(folder);
          }
          for (final p in customPresetsList) {
            final map = p as Map<String, dynamic>;
            final folder = (map['folder'] as String?)?.trim().toLowerCase();
            if (folder != null && !existingFolders.contains(folder)) {
              existingList.add(p);
            }
          }
          existingConfig['presets'] = existingList;
          await ProfileService._saveCustomPresetsConfig(existingConfig);
        } catch (_) {}
      }
    }

    await Directory(BackendPaths.defaultGameDataDir).create(recursive: true);
    final importedCurveTables = await _copyFileIfExists(
      File(joinPath([hotfixDataDir.path, 'CurveTables.ini'])),
      File(BackendPaths.curveTableLinesIni),
    );
    final importedDataTables = await _copyFileIfExists(
      File(joinPath([hotfixDataDir.path, 'DataTables.ini'])),
      File(BackendPaths.dataTableLinesIni),
    );
    final importedCurvesCatalog = await _copyFileIfExists(
      File(joinPath([hotfixDataDir.path, 'curves.json'])),
      File(BackendPaths.curvesJson),
    );
    final importedDataTablesCatalog = await _copyFileIfExists(
      File(joinPath([hotfixDataDir.path, 'datatables.json'])),
      File(BackendPaths.dataTablesJson),
    );
    final importedToggleStates = await _copyFileIfExists(
      toggleStatesFile,
      File(BackendPaths.userToggleStatesJson),
    );
    final profilesUiStateExportFile = File(
      joinPath([exportsRoot.path, 'profiles-ui-state.json']),
    );
    if (await profilesUiStateExportFile.exists()) {
      await _copyFileIfExists(
        profilesUiStateExportFile,
        File(ProfilesUiStateService._statePath()),
      );
    }
    final importedCustomGroupImages =
        await _replaceDirectoryFromExportIfPresent(
          Directory(joinPath([hotfixDataDir.path, 'custom-groups'])),
          Directory(
            joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
          ),
        );
    final importedCustomItemImages = await _replaceMatchingFilesFromExportIfAny(
      Directory(joinPath([hotfixDataDir.path, 'custom-items'])),
      Directory(joinPath([getBackendRoot(), 'public', 'items'])),
      (name) => name.toLowerCase().startsWith('custom_'),
    );
    if (importedCurvesCatalog) {
      await CurveTableService._mergeMissingDefaultCurves();
    }
    if (importedDataTablesCatalog) {
      await DataTableService._mergeMissingDefaultDataTables();
    }
    if (importedToggleStates) {
      final fallback = await UserToggleStatesService.captureCurrentState();
      final restoredState = await UserToggleStatesService.loadFromFile(
        File(BackendPaths.userToggleStatesJson),
        fallback: fallback,
      );
      if (restoredState != null) {
        await UserToggleStatesService.apply(
          restoredState,
          notifyExternalListeners: true,
        );
      }
    } else if (importedCurveTables || importedDataTables) {
      await ManagedHotfixService.rebuildDefaultGame();
    }

    // Clear profile cache on backend
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {
      // Backend might not be running, that's okay
    }

    if (context.mounted) {
      showAtlasSnackBar(
        context,
        SnackBar(
          content: Text(
            importedToggleStates ||
                    importedCurveTables ||
                    importedDataTables ||
                    importedCurvesCatalog ||
                    importedDataTablesCatalog ||
                    importedCustomGroupImages ||
                    importedCustomItemImages
                ? 'Import complete. Toggle states, hotfix data, and custom CurveTable/DataTable assets have been applied, and profile changes will be visible on next login.'
                : 'Import complete. Changes will be visible on next login.',
          ),
        ),
      );
    }
  }

  static Future<void> clearExportedData(BuildContext context) async {
    final confirm = await _confirmDialog(
      context,
      'Clear exported data? This will remove all user Profiles, Client Settings, toggle states, and exported DataTable/CurveTable data from exports/.',
    );
    if (!confirm) return;
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    await _clearDirectory(exportsRoot);
    if (context.mounted) {
      showAtlasSnackBar(
        context,
        const SnackBar(content: Text('Exported data cleared.')),
      );
    }
  }

  static Future<bool> _hasExistingExport(
    Directory a,
    Directory b,
    Directory c, {
    File? toggleStatesFile,
  }) async {
    final aHas = a.existsSync() && a.listSync().isNotEmpty;
    final bHas = b.existsSync() && b.listSync().isNotEmpty;
    final cHas = c.existsSync() && c.listSync().isNotEmpty;
    final toggleStatesHas = toggleStatesFile?.existsSync() ?? false;
    return aHas || bHas || cHas || toggleStatesHas;
  }

  static Future<void> _showExportSummary(
    BuildContext context, {
    required bool exportedToggleStates,
    required bool exportedProfilesUiState,
    required bool exportedCurveTables,
    required bool exportedDataTables,
    required bool exportedCurvesCatalog,
    required bool exportedDataTablesCatalog,
    required bool exportedCustomGroupImages,
    required bool exportedCustomItemImages,
    required int profilesExported,
    required int clientExported,
    required int customPresetsExported,
  }) async {
    final lines = <String>[];
    if (exportedToggleStates) {
      lines.add('user-toggle-states.json');
    }
    if (exportedProfilesUiState) {
      lines.add('profiles-ui-state.json');
    }
    if (exportedDataTables) {
      lines.add('DataTables.ini');
    }
    if (exportedCurveTables) {
      lines.add('CurveTables.ini');
    }
    if (exportedCurvesCatalog) {
      lines.add('curves.json');
    }
    if (exportedDataTablesCatalog) {
      lines.add('datatables.json');
    }
    if (exportedCustomGroupImages) {
      lines.add('custom curve group images');
    }
    if (exportedCustomItemImages) {
      lines.add('custom DataTable images');
    }
    if (profilesExported > 0) {
      lines.add(
        'Profiles: $profilesExported folder${profilesExported == 1 ? '' : 's'}',
      );
    }
    if (clientExported > 0) {
      lines.add(
        'ClientSettings: $clientExported folder${clientExported == 1 ? '' : 's'}',
      );
    }
    if (customPresetsExported > 0) {
      lines.add(
        'Custom Presets: $customPresetsExported preset${customPresetsExported == 1 ? '' : 's'}',
      );
    }
    await _showBlurDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exported items:'),
            const SizedBox(height: 12),
            for (final line in lines) Text('• $line'),
          ],
        ),
        actions: [
          _HoverScale(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool> _copyFileIfExists(File src, File dest) async {
    if (!await src.exists()) return false;
    await dest.parent.create(recursive: true);
    await src.copy(dest.path);
    return true;
  }

  static Future<bool> _copyDirectoryIfHasFiles(
    Directory src,
    Directory dest,
  ) async {
    if (!await _dirHasFiles(src)) {
      return false;
    }
    await _copyDir(src, dest);
    return true;
  }

  static Future<bool> _copyMatchingFilesIfAny(
    Directory src,
    Directory dest,
    bool Function(String name) shouldCopy,
  ) async {
    if (!await src.exists()) {
      return false;
    }
    var copied = false;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      if (entity is! File) {
        continue;
      }
      final name = _basename(entity.path);
      if (name.isEmpty || !shouldCopy(name)) {
        continue;
      }
      await entity.copy(joinPath([dest.path, name]));
      copied = true;
    }
    if (!copied) {
      await _deleteIfEmpty(dest);
    }
    return copied;
  }

  static Future<bool> _replaceDirectoryFromExportIfPresent(
    Directory src,
    Directory dest,
  ) async {
    if (!await _dirHasFiles(src)) {
      return false;
    }
    if (await dest.exists()) {
      await dest.delete(recursive: true);
    }
    await _copyDir(src, dest);
    return true;
  }

  static Future<bool> _replaceMatchingFilesFromExportIfAny(
    Directory src,
    Directory dest,
    bool Function(String name) shouldCopy,
  ) async {
    if (!await src.exists()) {
      return false;
    }
    var hasMatches = false;
    await for (final entity in src.list(recursive: false)) {
      if (entity is! File) {
        continue;
      }
      final name = _basename(entity.path);
      if (name.isNotEmpty && shouldCopy(name)) {
        hasMatches = true;
        break;
      }
    }
    if (!hasMatches) {
      return false;
    }
    await dest.create(recursive: true);
    await for (final entity in dest.list(recursive: false)) {
      if (entity is! File) {
        continue;
      }
      final name = _basename(entity.path);
      if (name.isEmpty || !shouldCopy(name)) {
        continue;
      }
      await entity.delete();
    }
    return _copyMatchingFilesIfAny(src, dest, shouldCopy);
  }

  static Future<void> _copyDir(Directory src, Directory dest) async {
    if (!await src.exists()) return;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = _entityName(entity);
      final destPath = joinPath([dest.path, name]);
      if (entity is Directory) {
        await _copyDir(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  static Future<int> _copyNonEmptyChildDirs(
    Directory src,
    Directory dest, {
    Set<String> skipDirs = const {},
  }) async {
    if (!await src.exists()) return 0;
    var copied = 0;
    await for (final entity in src.list(recursive: false)) {
      if (entity is Directory) {
        final name = _basename(entity.path);
        if (skipDirs.contains(name) || name.startsWith('.')) continue;
        if (!await _dirHasFiles(entity)) continue;
        await dest.create(recursive: true);
        await _copyDir(entity, Directory(joinPath([dest.path, name])));
        copied++;
      }
    }
    return copied;
  }

  static Future<bool> _dirHasFiles(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) return true;
    }
    return false;
  }

  static Future<void> _clearDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false)) {
      await entity.delete(recursive: true);
    }
  }

  static Future<void> _clearNonDirectoryEntries(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false)) {
      if (entity is! Directory) {
        await entity.delete();
      }
    }
  }

  static Future<void> _deleteIfEmpty(Directory dir) async {
    if (!await dir.exists()) return;
    final isEmpty = await dir.list(recursive: false).isEmpty;
    if (isEmpty) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> _importFolderChildren(
    Directory src,
    Directory dest, {
    Set<String> skipFiles = const {},
    Set<String> skipDirs = const {},
    bool onlyDirs = false,
  }) async {
    if (!await src.exists()) return;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = _basename(entity.path);
      if (entity is Directory) {
        if (skipDirs.contains(name)) continue;
        await _copyDir(entity, Directory(joinPath([dest.path, name])));
      } else if (!onlyDirs && entity is File) {
        if (skipFiles.contains(name)) continue;
        await entity.copy(joinPath([dest.path, name]));
      }
    }
  }

  static Future<void> _reorderDefaultGameHotfixBlocks(String iniPath) async {
    final iniFile = File(iniPath);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    final curveRegex = RegExp('^;?\\+CurveTable=.*\$', multiLine: true);
    final curveLines = curveRegex
        .allMatches(content)
        .map((m) => m.group(0)!)
        .toList();
    content = content.replaceAll(curveRegex, '');

    final straightLines = <String>[];
    final configuredStraightLines =
        await StraightBloomService._readConfiguredLines();
    for (final line in configuredStraightLines) {
      if (content.contains(line)) {
        straightLines.add(line);
        content = content.replaceAll(line, '');
      }
      final commented = ';$line';
      if (content.contains(commented)) {
        straightLines.add(commented);
        content = content.replaceAll(commented, '');
      }
    }

    content = content.replaceAll(BackendPaths.straightBloomComment, '');
    content = content.replaceAll(BackendPaths.curveTableComment, '');
    content = content.replaceAll(RegExp('\n\n+'), '\n');

    final linesOut = content.split('\n').toList();
    var assetIndex = linesOut.indexWhere(
      (line) => line.trim() == '[AssetHotfix]',
    );
    if (assetIndex == -1) {
      linesOut.add('[AssetHotfix]');
      assetIndex = linesOut.length - 1;
    }

    var insertAt = assetIndex + 1;
    final block = <String>[];
    if (straightLines.isNotEmpty) {
      block.add(BackendPaths.straightBloomComment);
      block.addAll(straightLines);
    }
    if (curveLines.isNotEmpty) {
      if (block.isNotEmpty) block.add('');
      block.add(BackendPaths.curveTableComment);
      block.addAll(curveLines);
    }
    if (block.isNotEmpty) {
      linesOut.insertAll(insertAt, block);
    }
    await iniFile.writeAsString(linesOut.join('\n'));
  }

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i].trim();
      if (part.isNotEmpty) return part;
    }
    return path;
  }

  static Future<void> _ensureProfileTemplateBackup(
    Directory profilesDir,
  ) async {
    final backupDir = Directory(
      joinPath([profilesDir.path, _profileTemplateBackupDirName]),
    );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    for (final name in _profileTemplateFiles) {
      final source = File(joinPath([profilesDir.path, name]));
      if (!await source.exists()) continue;
      final backup = File(joinPath([backupDir.path, name]));
      if (!await backup.exists()) {
        await source.copy(backup.path);
      }
    }
  }

  static Future<void> _restoreProfileTemplates(Directory profilesDir) async {
    final backupDir = Directory(
      joinPath([profilesDir.path, _profileTemplateBackupDirName]),
    );
    if (!await backupDir.exists()) return;
    for (final name in _profileTemplateFiles) {
      final backup = File(joinPath([backupDir.path, name]));
      if (!await backup.exists()) continue;
      await backup.copy(joinPath([profilesDir.path, name]));
    }
  }

  static Future<bool> _confirmDialog(
    BuildContext context,
    String message,
  ) async {
    return (await _showBlurDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(message),
            actions: [
              _HoverScale(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              _HoverScale(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes'),
                ),
              ),
            ],
          ),
        )) ??
        false;
  }
}

Future<String?> _promptValue(
  BuildContext context,
  String name, {
  String? defaultValue,
}) async {
  bool isValidNumeric(String value) =>
      RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(value.trim());
  final controller = TextEditingController();
  final result = await _showBlurDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Set value for $name'),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
        ],
        decoration: InputDecoration(
          labelText: 'Value',
          hintText: defaultValue,
          hintStyle: TextStyle(color: Colors.grey.shade600),
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty || !isValidNumeric(value)) {
                showAtlasSnackBar(
                  context,
                  const SnackBar(content: Text('Enter a valid numeric value.')),
                );
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );
  return result?.isEmpty == true ? null : result;
}

Future<Map<String, String>?> _promptAdvancedSettings(
  BuildContext context,
  List<String> fields,
  Map<String, String> currentValues,
  String defaultValue,
) async {
  bool isValidNumeric(String value) =>
      RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(value.trim());

  final controllers = <String, TextEditingController>{};
  for (final field in fields) {
    controllers[field] = TextEditingController(
      text: currentValues[field] ?? defaultValue,
    );
  }

  final result = await _showBlurDialog<Map<String, String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Advanced Settings'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: fields.map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[field],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton(
            onPressed: () {
              final values = <String, String>{};
              for (final field in fields) {
                final value = controllers[field]!.text.trim();
                if (value.isEmpty || !isValidNumeric(value)) {
                  showAtlasSnackBar(
                    context,
                    SnackBar(
                      content: Text('Enter a valid numeric value for $field.'),
                    ),
                  );
                  return;
                }
                values[field] = value;
              }
              Navigator.pop(context, values);
            },
            child: const Text('Save All'),
          ),
        ),
      ],
    ),
  );

  // Dispose controllers
  for (final controller in controllers.values) {
    controller.dispose();
  }

  return result;
}

Future<VictoryTextReplacementSettings?> _promptVictoryTextReplacementSettings(
  BuildContext context, {
  required VictoryTextReplacementSettings initialSettings,
}) async {
  bool isValidWord(String value) =>
      value.isNotEmpty &&
      !RegExp(r'[\s<>]').hasMatch(value) &&
      !value.contains('"');

  final placementController = TextEditingController();
  final victoryController = TextEditingController();
  final royaleController = TextEditingController();

  final result = await _showBlurDialog<VictoryTextReplacementSettings>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Victory Text Replacement'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: placementController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Placement',
                  hintText: initialSettings.placement,
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  prefixText: '#',
                  prefixStyle: Theme.of(dialogContext).textTheme.bodyLarge
                      ?.copyWith(
                        color: Theme.of(dialogContext).colorScheme.onSurface,
                      ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: victoryController,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\s"<>]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Word 1',
                  hintText: initialSettings.victory,
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: royaleController,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\s"<>]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Word 2',
                  hintText: initialSettings.royale,
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (initialSettings.enabled || !initialSettings.usesDefaultText)
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                VictoryTextReplacementSettings.defaultSettings,
              ),
              child: const Text('Reset'),
            ),
          ),
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton(
            onPressed: () {
              final placementInput = placementController.text.trim();
              final victoryInput = victoryController.text.trim();
              final royaleInput = royaleController.text.trim();
              final placement = placementInput.isEmpty
                  ? initialSettings.placement
                  : placementInput;
              final victory = victoryInput.isEmpty
                  ? initialSettings.victory
                  : victoryInput;
              final royale = royaleInput.isEmpty
                  ? initialSettings.royale
                  : royaleInput;

              if (!RegExp(r'^\d+$').hasMatch(placement)) {
                showAtlasSnackBar(
                  context,
                  const SnackBar(content: Text('Placement must be a number.')),
                );
                return;
              }
              if (!isValidWord(victory)) {
                showAtlasSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Victory text cannot contain spaces.'),
                  ),
                );
                return;
              }
              if (!isValidWord(royale)) {
                showAtlasSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Royale text cannot contain spaces.'),
                  ),
                );
                return;
              }

              Navigator.pop(
                dialogContext,
                VictoryTextReplacementSettings(
                  enabled: true,
                  placement: placement,
                  victory: victory,
                  royale: royale,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );

  placementController.dispose();
  victoryController.dispose();
  royaleController.dispose();
  return result;
}

Future<void> _showCurveImportSummary(
  BuildContext context,
  Map<String, List<String>> grouped, {
  required List<_ImportCurveDraft> missing,
}) async {
  if (grouped.isEmpty) return;
  final lines = _buildCurveImportSummaryLines(grouped, missing);

  await _showBlurDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('CurveTables imported'),
      content: SizedBox(
        width: 320,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${grouped.length} CurveTable${grouped.length == 1 ? '' : 's'} imported.',
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('New entries: ${missing.length}'),
                ],
                const SizedBox(height: 12),
                for (final line in lines) Text('• $line'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        _HoverScale(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  );
}

List<String> _buildCurveImportSummaryLines(
  Map<String, List<String>> grouped,
  List<_ImportCurveDraft> missing,
) {
  if (grouped.isEmpty) return const [];
  final missingKeys = missing
      .map((entry) => '${entry.pathPart}|||${entry.key}')
      .toSet();
  final labels = <String, Map<String, dynamic>>{};
  for (final entry in grouped.entries) {
    final parts = entry.key.split('|||');
    final key = parts.length > 1 ? parts[1] : entry.key;
    final label = _humanizeCurveKey(key);
    final count = entry.value.length;
    final isNew = missingKeys.contains(entry.key);
    final existing = labels[label];
    if (existing == null) {
      labels[label] = {'count': 1, 'lines': count, 'isNew': isNew};
    } else {
      labels[label] = {
        'count': (existing['count'] as int) + 1,
        'lines': (existing['lines'] as int) + count,
        'isNew': (existing['isNew'] as bool) || isNew,
      };
    }
  }
  return labels.entries.map((entry) {
    final label = entry.key;
    final count = entry.value['count'] as int;
    final totalLines = entry.value['lines'] as int;
    final isNew = entry.value['isNew'] as bool;
    final countSuffix = count > 1 ? ' ×$count' : '';
    final linesSuffix = totalLines > count ? ' ($totalLines lines)' : '';
    return '${isNew ? "New: " : ""}$label$countSuffix$linesSuffix';
  }).toList();
}

Future<void> _showModificationsIniImportSummary(
  BuildContext context, {
  required bool attemptedCurves,
  required bool attemptedDataTables,
  required Map<String, List<String>> curveGrouped,
  required List<_ImportCurveDraft> curveMissing,
  required int curveLines,
  required int straightBloomLines,
  required int dataTableLines,
  required int fixesLines,
}) async {
  final curveSummary = _buildCurveImportSummaryLines(
    curveGrouped,
    curveMissing,
  );

  await _showBlurDialog<void>(
    context: context,
    builder: (dialogContext) {
      Widget buildCard({
        required IconData icon,
        required String title,
        required Widget child,
      }) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _onSurface(dialogContext, 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: _onSurface(dialogContext, 0.65)),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        );
      }

      final curveSummaryScrollController = ScrollController();

      final curvesCard = buildCard(
        icon: Icons.show_chart_rounded,
        title: 'CurveTables',
        child: !attemptedCurves
            ? Text(
                'Disabled in Modifications.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: _onSurface(dialogContext, 0.6),
                ),
              )
            : curveLines == 0
            ? Text(
                'No CurveTable entries found.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: _onSurface(dialogContext, 0.6),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${curveGrouped.length} CurveTable${curveGrouped.length == 1 ? '' : 's'} imported ($curveLines lines).',
                  ),
                  if (curveMissing.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('New entries: ${curveMissing.length}'),
                  ],
                  if (curveSummary.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: Scrollbar(
                          controller: curveSummaryScrollController,
                          thumbVisibility: true,
                          thickness: 6,
                          radius: const Radius.circular(12),
                          child: SingleChildScrollView(
                            controller: curveSummaryScrollController,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final line in curveSummary)
                                  Text(
                                    '• $line',
                                    style: Theme.of(dialogContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: _onSurface(
                                            dialogContext,
                                            0.82,
                                          ),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      );

      final straightBloomCard = buildCard(
        icon: Icons.track_changes_rounded,
        title: 'Straight Bloom',
        child: straightBloomLines == 0
            ? Text(
                'No Straight Bloom entries found.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: _onSurface(dialogContext, 0.6),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$straightBloomLines Straight Bloom ${straightBloomLines == 1 ? 'line' : 'lines'} detected.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Current StraightBloom.ini is kept. Detected active lines will turn Straight Bloom on.',
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(color: _onSurface(dialogContext, 0.72)),
                  ),
                ],
              ),
      );

      final dataTablesCard = buildCard(
        icon: Icons.grid_view_rounded,
        title: 'DataTables',
        child: !attemptedDataTables
            ? Text(
                'Disabled in Modifications.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: _onSurface(dialogContext, 0.6),
                ),
              )
            : dataTableLines == 0 && fixesLines == 0
            ? Text(
                'No DataTable entries found.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: _onSurface(dialogContext, 0.6),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dataTableLines > 0)
                    Text(
                      '$dataTableLines DataTable ${dataTableLines == 1 ? 'entry' : 'entries'} imported.',
                    ),
                  if (dataTableLines > 0) const SizedBox(height: 6),
                  if (dataTableLines > 0)
                    Text(
                      'You can view and edit these in the DataTables tab.',
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(color: _onSurface(dialogContext, 0.72)),
                    ),
                  if (fixesLines > 0) ...[
                    if (dataTableLines > 0) const SizedBox(height: 10),
                    Text(
                      '$fixesLines ${fixesLines == 1 ? 'Fixes line' : 'Fixes lines'} detected. Current Fixes.ini is kept.',
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(color: _onSurface(dialogContext, 0.72)),
                    ),
                  ],
                ],
              ),
      );

      return AlertDialog(
        title: const Text('DefaultGame.ini imported'),
        content: SizedBox(
          width: 720,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 820;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: curvesCard),
                    const SizedBox(width: 12),
                    Expanded(child: straightBloomCard),
                    const SizedBox(width: 12),
                    Expanded(child: dataTablesCard),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  curvesCard,
                  const SizedBox(height: 12),
                  straightBloomCard,
                  const SizedBox(height: 12),
                  dataTablesCard,
                ],
              );
            },
          ),
        ),
        actions: [
          _HoverScale(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ),
        ],
      );
    },
  );
}

class _ParsedCurveLines {
  const _ParsedCurveLines({
    required this.pathPart,
    required this.key,
    required this.lines,
    required this.staticValue,
  });

  final String pathPart;
  final String key;
  final List<String> lines;
  final String staticValue;
}

class _CurveLineParts {
  const _CurveLineParts({
    required this.pathPart,
    required this.key,
    required this.row,
    required this.value,
  });

  final String pathPart;
  final String key;
  final String row;
  final String value;
}

_CurveLineParts? _splitCurveLine(String line) {
  final regex = RegExp('^\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$');
  final match = regex.firstMatch(line.trim());
  if (match == null) return null;
  return _CurveLineParts(
    pathPart: match.group(1)!,
    key: match.group(2)!,
    row: match.group(3)!,
    value: match.group(4)!,
  );
}

String _replaceCurveLineValue(String line, String value) {
  final parts = _splitCurveLine(line);
  if (parts == null) return line;
  return '+CurveTable=${parts.pathPart};RowUpdate;${parts.key};${parts.row};$value';
}

_ParsedCurveLines? _parseCurveLines(String raw) {
  final cleaned = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return null;
  String? pathPart;
  String? key;
  String? staticValue;
  for (final line in cleaned) {
    final parts = _splitCurveLine(line);
    if (parts == null) return null;
    final currentPath = parts.pathPart;
    final currentKey = parts.key;
    final value = parts.value;
    pathPart ??= currentPath;
    key ??= currentKey;
    staticValue ??= value;
    if (pathPart != currentPath || key != currentKey) return null;
  }
  return _ParsedCurveLines(
    pathPart: pathPart!,
    key: key!,
    lines: cleaned,
    staticValue: staticValue ?? '0',
  );
}

String _extractLastHotfixBlock(String content) {
  final lines = content.split('\n');
  final assetIndex = lines.indexWhere((line) => line.trim() == '[AssetHotfix]');
  if (assetIndex == -1) return '';
  var lastCommentIndex = -1;
  for (var i = assetIndex + 1; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.startsWith('#')) {
      lastCommentIndex = i;
    }
  }
  if (lastCommentIndex == -1) return '';
  final buffer = <String>[];
  for (var i = lastCommentIndex + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().startsWith('#') || line.trim().startsWith('[')) break;
    buffer.add(line);
  }
  return buffer.join('\n');
}

Future<List<CustomCurveInput>?> _promptCustomCurves(
  BuildContext context,
  List<CustomCurveGroupInfo> groups,
) async {
  final drafts = <_CustomCurveDraft>[_CustomCurveDraft()];
  final groupNameController = TextEditingController();
  String? newGroupImagePath;
  String selectedGroupId = '_new';
  String? errorText;

  final result = await _showBlurDialog<List<CustomCurveInput>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add Custom Curves'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: [
                    ...groups.map(
                      (group) => DropdownMenuItem(
                        value: group.id,
                        child: Text(group.name),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: '_new',
                      child: Text('Create new group'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedGroupId = value;
                      errorText = null;
                    });
                  },
                ),
                if (selectedGroupId == '_new') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: groupNameController,
                    decoration: const InputDecoration(labelText: 'Group name'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          newGroupImagePath == null
                              ? 'No group image selected'
                              : newGroupImagePath!
                                    .split(Platform.pathSeparator)
                                    .last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _HoverScale(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                            );
                            if (picked == null ||
                                picked.files.single.path == null) {
                              return;
                            }
                            setState(() {
                              newGroupImagePath = picked.files.single.path;
                              errorText = null;
                            });
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose image'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Curves',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                ...drafts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final draft = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: draft.nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Curve name ${index + 1}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
                                  const Text('Static'),
                                  Switch(
                                    value: draft.isStatic,
                                    onChanged: (value) =>
                                        setState(() => draft.isStatic = value),
                                  ),
                                ],
                              ),
                              if (drafts.length > 1)
                                _HoverScale(
                                  child: IconButton(
                                    tooltip: 'Remove curve',
                                    onPressed: () =>
                                        setState(() => drafts.removeAt(index)),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft.linesController,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'CurveTable line(s)',
                              hintText:
                                  '+CurveTable=/Game/...;RowUpdate;Key;0;Value',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _HoverScale(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => drafts.add(_CustomCurveDraft())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add another curve'),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final isNewGroup = selectedGroupId == '_new';
                final groupName = isNewGroup
                    ? groupNameController.text.trim()
                    : groups
                          .firstWhere((group) => group.id == selectedGroupId)
                          .name;
                final groupImagePath = isNewGroup
                    ? ''
                    : (groups
                              .firstWhere(
                                (group) => group.id == selectedGroupId,
                              )
                              .imagePath ??
                          '');
                final groupImageSourcePath = isNewGroup
                    ? (newGroupImagePath ?? '')
                    : '';

                if (isNewGroup && groupName.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                if (isNewGroup &&
                    (newGroupImagePath == null ||
                        newGroupImagePath!.trim().isEmpty)) {
                  setState(() => errorText = 'Group image is required.');
                  return;
                }
                if (drafts.isEmpty) {
                  setState(() => errorText = 'Add at least one curve.');
                  return;
                }

                final groupId = isNewGroup
                    ? 'custom-${DateTime.now().millisecondsSinceEpoch}'
                    : selectedGroupId;
                final inputs = <CustomCurveInput>[];
                for (final draft in drafts) {
                  final curveName = draft.nameController.text.trim();
                  if (curveName.isEmpty) {
                    setState(() => errorText = 'Each curve must have a name.');
                    return;
                  }
                  final parsed = _parseCurveLines(draft.linesController.text);
                  if (parsed == null) {
                    setState(
                      () => errorText =
                          'Enter valid +CurveTable line(s) with matching path/key.',
                    );
                    return;
                  }
                  inputs.add(
                    CustomCurveInput(
                      name: curveName,
                      key: parsed.key,
                      pathPart: parsed.pathPart,
                      lines: parsed.lines,
                      staticValue: parsed.staticValue,
                      isStatic: draft.isStatic,
                      groupId: groupId,
                      groupName: groupName,
                      groupImagePath: groupImagePath,
                      groupImageSourcePath: groupImageSourcePath,
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_CustomGroupEditResult?> _promptEditCustomGroup(
  BuildContext context,
  String groupId,
  String groupName,
) async {
  final nameController = TextEditingController(text: groupName);
  String? newImagePath;
  String? errorText;
  final result = await _showBlurDialog<_CustomGroupEditResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Group'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      newImagePath == null
                          ? 'No new image selected'
                          : newImagePath!.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HoverScale(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        if (picked == null ||
                            picked.files.single.path == null) {
                          return;
                        }
                        setState(() {
                          newImagePath = picked.files.single.path;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                Navigator.pop(
                  context,
                  _CustomGroupEditResult(name: name, imagePath: newImagePath),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<CustomCurveEditResult?> _promptEditCustomCurve(
  BuildContext context,
  CurveEntry entry,
  List<CustomCurveGroupInfo> groups,
) async {
  final nameController = TextEditingController(text: entry.name);
  final linesController = TextEditingController(
    text: entry.multiLines.join('\n'),
  );
  bool isStatic = entry.type == 'static';
  String selectedGroupId = entry.groupId ?? groups.first.id;
  String? errorText;

  final result = await _showBlurDialog<CustomCurveEditResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Custom Curve'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: groups
                      .map(
                        (group) => DropdownMenuItem(
                          value: group.id,
                          child: Text(group.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedGroupId = value;
                      errorText = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Curve name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Static'),
                    const SizedBox(width: 12),
                    Switch(
                      value: isStatic,
                      onChanged: (value) => setState(() => isStatic = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linesController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'CurveTable line(s)',
                    hintText: '+CurveTable=/Game/...;RowUpdate;Key;0;Value',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Curve name is required.');
                  return;
                }
                final parsed = _parseCurveLines(linesController.text);
                if (parsed == null) {
                  setState(
                    () => errorText =
                        'Enter valid +CurveTable line(s) with matching path/key.',
                  );
                  return;
                }
                final groupInfo = groups.firstWhere(
                  (group) => group.id == selectedGroupId,
                );
                Navigator.pop(
                  context,
                  CustomCurveEditResult(
                    name: name,
                    lines: parsed.lines,
                    staticValue: parsed.staticValue,
                    isStatic: isStatic,
                    key: parsed.key,
                    pathPart: parsed.pathPart,
                    groupId: groupInfo.id,
                    groupName: groupInfo.name,
                    groupImagePath: groupInfo.imagePath,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<CustomCurveGroupInfo?> _promptCreateCustomGroup(
  BuildContext context,
) async {
  final nameController = TextEditingController();
  String? imagePath;
  String? errorText;
  final result = await _showBlurDialog<CustomCurveGroupInfo>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create Group'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      imagePath == null
                          ? 'No image selected'
                          : imagePath!.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HoverScale(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        if (picked == null ||
                            picked.files.single.path == null) {
                          return;
                        }
                        setState(() {
                          imagePath = picked.files.single.path;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                if (imagePath == null || imagePath!.trim().isEmpty) {
                  setState(() => errorText = 'Group image is required.');
                  return;
                }
                Navigator.pop(
                  context,
                  CustomCurveGroupInfo(
                    id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    imagePath: imagePath,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<List<CustomCurveInput>?> _promptImportMissingCurves(
  BuildContext context,
  List<_ImportCurveDraft> missing,
  List<CustomCurveGroupInfo> groups,
) async {
  final groupOptions = [...groups];
  if (!groupOptions.any((group) => group.id == 'other')) {
    groupOptions.add(
      const CustomCurveGroupInfo(id: 'other', name: 'Other', imagePath: null),
    );
  }
  if (groupOptions.isNotEmpty) {
    for (final draft in missing) {
      draft.selectedGroupId = '';
    }
  }

  final result = await _showBlurDialog<List<CustomCurveInput>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Name Imported Curves'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...missing.map((draft) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            draft.pathPart,
                            style: TextStyle(
                              fontSize: 12,
                              color: _onSurface(context, 0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft.nameController,
                            decoration: const InputDecoration(
                              labelText: 'Curve name',
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: draft.selectedGroupId.isEmpty
                                ? null
                                : draft.selectedGroupId,
                            decoration: const InputDecoration(
                              labelText: 'Group',
                            ),
                            items: [
                              ...groupOptions.map(
                                (group) => DropdownMenuItem(
                                  value: group.id,
                                  child: Text(group.name),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: '__new__',
                                child: Text('Create new group'),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              if (value == '__new__') {
                                final newGroup = await _promptCreateCustomGroup(
                                  context,
                                );
                                if (newGroup != null) {
                                  setState(() {
                                    groupOptions.add(newGroup);
                                    draft.selectedGroupId = newGroup.id;
                                  });
                                }
                                return;
                              }
                              setState(() => draft.selectedGroupId = value);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: OutlinedButton(
              onPressed: () {
                final inputs = <CustomCurveInput>[];
                for (final draft in missing) {
                  final name = _humanizeCurveKey(draft.key);
                  final group = groupOptions.firstWhere((g) => g.id == 'other');
                  inputs.add(
                    CustomCurveInput(
                      name: name,
                      key: draft.key,
                      pathPart: draft.pathPart,
                      lines: draft.lines,
                      staticValue: draft.staticValue,
                      isStatic: false,
                      groupId: group.id,
                      groupName: group.name,
                      groupImagePath: '',
                      groupImageSourcePath: '',
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Continue without naming'),
            ),
          ),
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final inputs = <CustomCurveInput>[];
                for (final draft in missing) {
                  final name = draft.nameController.text.trim().isEmpty
                      ? _humanizeCurveKey(draft.key)
                      : draft.nameController.text.trim();
                  final groupId = draft.selectedGroupId.isEmpty
                      ? 'other'
                      : draft.selectedGroupId;
                  final group = groupOptions.firstWhere((g) => g.id == groupId);
                  final groupImageSourcePath =
                      (group.imagePath != null &&
                          File(group.imagePath!).existsSync())
                      ? group.imagePath!
                      : '';
                  final groupImagePath = groupImageSourcePath.isEmpty
                      ? (group.imagePath ?? '')
                      : '';
                  inputs.add(
                    CustomCurveInput(
                      name: name,
                      key: draft.key,
                      pathPart: draft.pathPart,
                      lines: draft.lines,
                      staticValue: draft.staticValue,
                      isStatic: false,
                      groupId: group.id,
                      groupName: group.name,
                      groupImagePath: groupImagePath,
                      groupImageSourcePath: groupImageSourcePath,
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

/// Handle for a Windows Job Object configured with KILL_ON_JOB_CLOSE.
/// When this process exits the OS automatically terminates every process in
/// the job, ensuring the backend does not outlive the GUI.
int _backendJobObject = 0;

void _ensureBackendJobObject() {
  if (!Platform.isWindows || _backendJobObject != 0) return;
  try {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final createJobObjectW = k32
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Void>),
          int Function(Pointer<Void>, Pointer<Void>)
        >('CreateJobObjectW');
    final setInformationJobObject = k32
        .lookupFunction<
          Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32),
          int Function(int, int, Pointer<Uint8>, int)
        >('SetInformationJobObject');
    final getProcessHeap = k32
        .lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
    final heapAlloc = k32
        .lookupFunction<
          Pointer<Uint8> Function(IntPtr, Uint32, IntPtr),
          Pointer<Uint8> Function(int, int, int)
        >('HeapAlloc');
    final heapFree = k32
        .lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Uint8>),
          int Function(int, int, Pointer<Uint8>)
        >('HeapFree');

    final hJob = createJobObjectW(nullptr, nullptr);
    if (hJob == 0) return;

    // Allocate a zeroed JOBOBJECT_EXTENDED_LIMIT_INFORMATION.
    final infoSize = sizeOf<IntPtr>() == 8 ? 144 : 112;
    final heap = getProcessHeap();
    final buf = heapAlloc(heap, 0x00000008 /* HEAP_ZERO_MEMORY */, infoSize);
    if (buf.address == 0) return;

    // LimitFlags sits at byte-offset 16 on both x86 and x64.
    (buf + 16).cast<Uint32>().value =
        0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    setInformationJobObject(
      hJob,
      9 /* JobObjectExtendedLimitInformation */,
      buf,
      infoSize,
    );
    heapFree(heap, 0, buf);

    _backendJobObject = hJob;
  } catch (_) {
    // Non-fatal: backend simply won't auto-stop on GUI exit.
  }
}

void _addProcessToBackendJob(int pid) {
  if (_backendJobObject == 0) return;
  try {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final openProcess = k32
        .lookupFunction<
          IntPtr Function(Uint32, Int32, Uint32),
          int Function(int, int, int)
        >('OpenProcess');
    final assignProcessToJobObject = k32
        .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
          'AssignProcessToJobObject',
        );
    final closeHandle = k32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'CloseHandle',
        );

    // PROCESS_SET_QUOTA | PROCESS_TERMINATE
    final hProcess = openProcess(0x0100 | 0x0001, 0, pid);
    if (hProcess == 0) return;
    assignProcessToJobObject(_backendJobObject, hProcess);
    closeHandle(hProcess);
  } catch (_) {
    // Non-fatal.
  }
}

class BackendController extends ChangeNotifier {
  BackendController() {
    _logStore.clear();
  }

  Process? _process;
  Timer? _pollTimer;
  bool isRunning = false;
  bool isStarting = false;
  bool isStopping = false;
  bool isRestarting = false;
  String _statusText = 'Offline';
  Color _statusColor = Colors.redAccent;
  final LogStore _logStore = LogStore.instance;
  DateTime? _backendStartedAt;
  Timer? _logNotifyTimer;
  bool _logNotifyQueued = false;

  String get statusText => _statusText;
  Color get statusColor => _statusColor;
  DateTime? get backendStartedAt => _backendStartedAt;
  List<String> get recentLogs => _logStore.recentLogs;
  List<String> get allLogs => _logStore.allLogs;
  bool get hasProcess => _process != null;
  String get activeProfilesLabel => '28';
  String get exportsLabel => '1,024 files';
  String get lastSyncLabel => '2 minutes ago';

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkBackend(),
    );
    _checkBackend();
  }

  Future<void> ensureStoppedOnLaunch() async {
    final ok = await _pingBackend();
    if (!ok) return;
    _addLog('Backend detected on launch. Stopping until Start is pressed.');
    await _killBackendOnPort(3551);
    _backendStartedAt = null;
    isRunning = false;
    _setStatus('Offline', Colors.redAccent);
    notifyListeners();
  }

  Future<void> startBackend() async {
    if (isStarting || isRestarting || isStopping) return;
    if (isRunning) {
      _addLog('Backend is already running.');
      return;
    }
    if (_process != null) {
      _addLog('Backend is already starting.');
      return;
    }
    if (await _pingBackend(timeout: const Duration(milliseconds: 350))) {
      isRunning = true;
      _backendStartedAt ??= DateTime.now();
      _setStatus('Running', Colors.greenAccent);
      _addLog('Backend already running.');
      notifyListeners();
      return;
    }
    isStarting = true;
    _logStore.clear();
    _backendStartedAt = null;
    _setStatus('Starting...', Colors.orangeAccent);
    _addLog('Starting backend...');
    notifyListeners();

    final backendRoot = getBackendRoot();
    final installRoot = getInstallationRoot();
    await _syncInstalledRuntimeSourceDirectory(Directory(backendRoot));
    await _syncInstalledRuntimeDependencyFiles(Directory(backendRoot));
    final bunPath = _resolveBunPath(installRoot);
    final bunAvailable = await _checkBunAvailable(installRoot, bunPath);
    if (!bunAvailable) {
      _addLog('Bun not found. Install Bun or include tools\\bun\\bun.exe.');
      isStarting = false;
      _setStatus('Bun missing', Colors.redAccent);
      notifyListeners();
      return;
    }

    final nodeModules = Directory(joinPath([backendRoot, 'node_modules']));
    if (!nodeModules.existsSync()) {
      _addLog('Installing dependencies (bun install)...');
      final install = await Process.run(bunPath ?? 'bun', [
        'install',
      ], workingDirectory: backendRoot);
      if (install.exitCode != 0) {
        _addLog('Dependency install failed: ${install.stderr}');
        isStarting = false;
        _setStatus('Install failed', Colors.redAccent);
        notifyListeners();
        return;
      }
      _addLog('Dependencies installed.');
    }

    final runtimeEntryPoint = File(joinPath([backendRoot, 'src', 'index.ts']));
    if (!runtimeEntryPoint.existsSync()) {
      _addLog(
        'Backend runtime source is missing from AppData. Restart the app or reinstall the backend.',
      );
      isStarting = false;
      _setStatus('Start failed', Colors.redAccent);
      notifyListeners();
      return;
    }

    final config = await ConfigService.load();
    final env = Map<String, String>.from(Platform.environment);
    if (config.disableBackendUpdateCheck) {
      env['ATLAS_DISABLE_UPDATE_CHECK'] = '1';
    }
    env['ATLAS_DATA_ROOT'] = backendRoot;
    env['ATLAS_INSTALL_ROOT'] = installRoot;
    final runtimeNodeModulesPath = joinPath([backendRoot, 'node_modules']);
    if (Directory(runtimeNodeModulesPath).existsSync()) {
      final existingNodePath = env['NODE_PATH']?.trim();
      final separator = Platform.isWindows ? ';' : ':';
      env['NODE_PATH'] = existingNodePath == null || existingNodePath.isEmpty
          ? runtimeNodeModulesPath
          : '$runtimeNodeModulesPath$separator$existingNodePath';
    }

    try {
      _process = await Process.start(
        bunPath ?? 'bun',
        ['run', 'src/index.ts'],
        workingDirectory: backendRoot,
        environment: env,
        mode: ProcessStartMode.detachedWithStdio,
      );
      _ensureBackendJobObject();
      _addProcessToBackendJob(_process!.pid);
      _backendStartedAt = DateTime.now();
      _setStatus('Starting...', Colors.orangeAccent);
      notifyListeners();
      try {
        _process?.stdout.transform(utf8.decoder).listen(_addLog);
        _process?.stderr.transform(utf8.decoder).listen(_addLog);
      } catch (_) {
        // Detached process may not expose stdio on some platforms.
      }
      _process?.exitCode.then((code) {
        _addLog('Backend exited with code $code');
        _process = null;
        isRunning = false;
        isStarting = false;
        _backendStartedAt = null;
        _setStatus('Offline', Colors.redAccent);
        notifyListeners();
      });

      // Avoid the perceived "startup lag" caused by the 3s poll cadence.
      // Ping aggressively for a short window so the UI flips to Running asap.
      final ready = await _waitForBackendReady();
      if (ready) {
        isRunning = true;
        isStarting = false;
        _backendStartedAt ??= DateTime.now();
        _setStatus('Running', Colors.greenAccent);
        notifyListeners();
      }
    } catch (error) {
      _backendStartedAt = null;
      if (_process != null) {
        // Suppress detached process warning in GUI logs.
        isRunning = false;
        isStarting = false;
        _setStatus('Starting...', Colors.orangeAccent);
        notifyListeners();
      } else {
        _addLog('Failed to start backend: $error');
        isRunning = false;
        isStarting = false;
        _setStatus('Start failed', Colors.redAccent);
        notifyListeners();
      }
    }
  }

  Future<bool> _waitForBackendReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _pingBackend(timeout: const Duration(milliseconds: 350))) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  Future<void> stopBackend() async {
    if (isStopping) return;
    isStopping = true;
    _setStatus('Stopping...', Colors.orangeAccent);
    _addLog('Stopping backend...');
    notifyListeners();

    final process = _process;
    if (process == null) {
      _addLog('No active process found.');
      await _killBackendOnPort(3551);
      isStopping = false;
      _setStatus('Offline', Colors.redAccent);
      notifyListeners();
      return;
    }

    final pid = process.pid;
    bool exited = false;
    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(const Duration(seconds: 4));
      exited = true;
    } catch (_) {
      exited = false;
    }

    if (!exited) {
      await Process.run('taskkill', ['/PID', pid.toString(), '/T', '/F']);
      try {
        await process.exitCode.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    _process = null;
    await _killBackendOnPort(3551);
    isStopping = false;
    isRunning = false;
    _backendStartedAt = null;
    _setStatus('Offline', Colors.redAccent);
    notifyListeners();
  }

  Future<void> closeFortnite() async {
    _addLog('Closing Fortnite...');
    const processes = <String>[
      'FortniteClient-Win64-Shipping.exe',
      'FortniteLauncher.exe',
      'FortniteClient-Win64-Shipping_BE.exe',
      'FortniteClient-Win64-Shipping_EAC.exe',
      'EasyAntiCheat.exe',
      'BEService.exe',
      'BattlEye.exe',
      'EpicGamesLauncher.exe',
      'EpicWebHelper.exe',
      'CrashReportClient.exe',
      'UnrealCEFSubProcess.exe',
    ];

    for (final process in processes) {
      try {
        await Process.run('taskkill', ['/F', '/IM', process]);
      } catch (_) {
        // Ignore failures (process not running, permissions, etc.).
      }
    }

    _addLog('Done.');
  }

  Future<void> restartBackend() async {
    if (isRestarting || isStarting || isStopping) return;
    isRestarting = true;
    _logStore.clear();
    _setStatus('Restarting...', Colors.orangeAccent);
    _addLog('Restarting backend...');
    notifyListeners();

    await stopBackend();
    await Future.delayed(const Duration(seconds: 1));
    isRestarting = false;
    notifyListeners();
    await startBackend();

    isRestarting = false;
    notifyListeners();
  }

  Future<void> _checkBackend() async {
    final ok = await _pingBackend();
    if (ok) {
      var changed = false;
      if (!isRunning) {
        isRunning = true;
        _backendStartedAt ??= DateTime.now();
        _setStatus('Running', Colors.greenAccent);
        changed = true;
      }
      if (isStarting) {
        isStarting = false;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    } else if (!ok && isRunning && !isStarting) {
      isRunning = false;
      _backendStartedAt = null;
      _setStatus('Offline', Colors.redAccent);
      notifyListeners();
    }
  }

  Future<bool> _pingBackend({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:3551/unknown'),
      );
      final response = await request.close().timeout(timeout);
      client.close();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkBunAvailable(
    String workingDirectory,
    String? bunPath,
  ) async {
    if (bunPath != null) {
      return File(bunPath).existsSync();
    }
    try {
      final result = await Process.run('bun', [
        '--version',
      ], workingDirectory: workingDirectory);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _killBackendOnPort(int port) async {
    try {
      final result = await Process.run('netstat', ['-ano']);
      if (result.exitCode != 0) return;
      final lines = result.stdout.toString().split('\n');
      final pids = <int>{};
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 5) continue;
        final localAddress = parts[1];
        if (!localAddress.endsWith(':$port')) continue;
        final pid = int.tryParse(parts.last);
        if (pid != null && pid > 0) {
          pids.add(pid);
        }
      }
      for (final pid in pids) {
        await Process.run('taskkill', ['/PID', pid.toString(), '/T', '/F']);
      }
    } catch (_) {
      // Ignore failures; status will reflect actual backend state on next poll.
    }
  }

  void _setStatus(String text, Color color) {
    _statusText = text;
    _statusColor = color;
  }

  void _addLog(String log) {
    final sanitized = log
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .trim();

    if (sanitized.isEmpty) return;

    final lines = sanitized
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    final now = DateTime.now();
    final hour = now.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timezoneAbbr = now.timeZoneName.replaceAll(RegExp(r'[^A-Z]'), '');
    final timestamp =
        '[${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} $period $timezoneAbbr]';

    for (final line in lines) {
      _logStore.addLog('$timestamp $line');
    }
    _queueLogRefresh();
  }

  void _queueLogRefresh() {
    if (_logNotifyQueued) return;
    _logNotifyQueued = true;
    _logNotifyTimer = Timer(const Duration(milliseconds: 120), () {
      _logNotifyQueued = false;
      notifyListeners();
    });
  }

  Future<void> forceKillBackendPort() async {
    await _killBackendOnPort(3551);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logNotifyTimer?.cancel();
    super.dispose();
  }
}

bool _isInstalledExecutableDirectory(String executablePath) {
  String normalize(String input) {
    return input.replaceAll('/', '\\').toLowerCase();
  }

  bool hasPrefix(String? prefix) {
    if (prefix == null || prefix.trim().isEmpty) return false;
    return normalize(executablePath).startsWith(normalize(prefix));
  }

  final localAppData = Platform.environment['LOCALAPPDATA'];
  final installedRoots = <String>[
    if (Platform.environment['ProgramFiles'] case final programFiles?)
      programFiles,
    if (Platform.environment['ProgramFiles(x86)'] case final programFilesX86?)
      programFilesX86,
    if (localAppData != null)
      joinPath([localAppData, 'Programs', 'ATLAS Backend']),
    if (localAppData != null)
      joinPath([localAppData, 'Programs', 'ATLAS-Backend']),
    if (localAppData != null) joinPath([localAppData, 'ATLAS Backend']),
    if (localAppData != null) joinPath([localAppData, 'ATLAS-Backend']),
  ];

  for (final root in installedRoots) {
    if (hasPrefix(root)) return true;
  }

  final packagedMarkers = [
    Directory(joinPath([executablePath, 'data'])).existsSync(),
    Directory(joinPath([executablePath, 'static'])).existsSync(),
    Directory(joinPath([executablePath, 'src'])).existsSync(),
    File(joinPath([executablePath, 'package.json'])).existsSync(),
    File(joinPath([executablePath, 'flutter_windows.dll'])).existsSync(),
  ];
  if (packagedMarkers.every((marker) => marker)) {
    return true;
  }

  return false;
}

String getBackendRoot() {
  // Installed builds keep mutable runtime data under %APPDATA%\ATLAS.
  final executablePath = File(Platform.resolvedExecutable).parent.path;
  if (_isInstalledExecutableDirectory(executablePath)) {
    final appDataDir = Platform.environment['APPDATA'];
    if (appDataDir != null) {
      final atlasDataDir = Directory(joinPath([appDataDir, 'ATLAS']));
      if (!atlasDataDir.existsSync()) {
        atlasDataDir.createSync(recursive: true);
      }
      return atlasDataDir.path;
    }
  }

  // Development/source mode - look for static and src directories
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory(File(Platform.resolvedExecutable).parent.path),
    Directory(File(Platform.resolvedExecutable).parent.parent.path),
  ];

  for (final start in candidates) {
    var current = start;
    while (true) {
      final staticDir = Directory(joinPath([current.path, 'static']));
      final srcDir = Directory(joinPath([current.path, 'src']));
      if (staticDir.existsSync() && srcDir.existsSync()) {
        return current.path;
      }
      if (current.parent.path == current.path) {
        break;
      }
      current = current.parent;
    }
  }
  return Directory.current.path;
}

String getInstallationRoot() {
  // Returns the directory where the backend code/assets are installed
  // This is different from getBackendRoot() which returns the data directory
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory(File(Platform.resolvedExecutable).parent.path),
    Directory(File(Platform.resolvedExecutable).parent.parent.path),
  ];

  for (final start in candidates) {
    var current = start;
    while (true) {
      final staticDir = Directory(joinPath([current.path, 'static']));
      final srcDir = Directory(joinPath([current.path, 'src']));
      if (staticDir.existsSync() && srcDir.existsSync()) {
        return current.path;
      }
      if (current.parent.path == current.path) {
        break;
      }
      current = current.parent;
    }
  }
  return Directory.current.path;
}

String joinPath(List<String> parts) {
  return parts.join(Platform.pathSeparator);
}

String? _resolveBunPath(String backendRoot) {
  // Check local bundled Bun first
  final candidates = [
    joinPath([backendRoot, 'tools', 'bun', 'bun.exe']),
    joinPath([backendRoot, 'tools', 'bun', 'bun']),
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  // Return null to let _checkBunAvailable try to find it in PATH
  return null;
}

String? _resolveBackgroundPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final direct = File(trimmed);
  if (direct.existsSync()) return direct.path;
  final backendRoot = getBackendRoot();
  final relative = File(joinPath([backendRoot, trimmed]));
  if (relative.existsSync()) return relative.path;
  final publicImage = File(
    joinPath([backendRoot, 'public', 'images', trimmed]),
  );
  if (publicImage.existsSync()) return publicImage.path;
  return null;
}
