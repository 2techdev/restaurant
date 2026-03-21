/// Local backup / restore service for GastroCore POS.
///
/// Backups are full SQLite file copies stored in:
///   `<Documents>/GastroCore/backups/`
///
/// File naming:  `gastrocore_backup_YYYYMMDD_HHmmss.db`
/// Max retained: 30 (oldest auto-deleted when limit exceeded)
library;

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// BackupInfo value object
// ---------------------------------------------------------------------------

/// Metadata about a single backup file.
class BackupInfo {
  const BackupInfo({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
  });

  /// The underlying file on disk.
  final File file;

  /// Timestamp extracted from the filename.
  final DateTime createdAt;

  /// File size in bytes.
  final int sizeBytes;

  /// File name (without path).
  String get name => p.basename(file.path);

  /// Human-readable size string (e.g. "3.2 MB").
  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() => 'BackupInfo($name, $sizeLabel, $createdAt)';
}

// ---------------------------------------------------------------------------
// BackupService
// ---------------------------------------------------------------------------

class BackupService {
  static const int _maxBackups = 30;
  static const String _backupParentDir = 'GastroCore';
  static const String _backupSubDir = 'backups';
  static const String _dbFileName = 'gastrocore_pos.sqlite';

  final _tsFormat = DateFormat('yyyyMMdd_HHmmss_SSS');

  // ---------------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------------

  Future<String> _dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbFileName);
  }

  Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _backupParentDir, _backupSubDir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------------------
  // Create backup
  // ---------------------------------------------------------------------------

  /// Copy the live SQLite file to the backup directory.
  ///
  /// Returns a [BackupInfo] for the newly created backup.
  /// Automatically prunes old backups so at most [_maxBackups] are kept.
  Future<BackupInfo> createBackup() async {
    final source = File(await _dbPath());
    if (!source.existsSync()) {
      throw const BackupException('Database file not found.');
    }

    final dir = await _backupDir();
    final timestamp = _tsFormat.format(DateTime.now());
    final destPath = p.join(dir.path, 'gastrocore_backup_$timestamp.db');

    try {
      await source.copy(destPath);
    } catch (e) {
      throw BackupException('Failed to create backup.', cause: e);
    }

    await _pruneOldBackups(dir);

    final destFile = File(destPath);
    return BackupInfo(
      file: destFile,
      createdAt: DateTime.now(),
      sizeBytes: destFile.lengthSync(),
    );
  }

  // ---------------------------------------------------------------------------
  // List backups
  // ---------------------------------------------------------------------------

  /// Return all backup files, newest first.
  Future<List<BackupInfo>> listBackups() async {
    final dir = await _backupDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('gastrocore_backup_') && p.basename(f.path).endsWith('.db'))
        .toList();

    final infos = <BackupInfo>[];
    for (final f in files) {
      final name = p.basenameWithoutExtension(f.path);
      // Expected format: gastrocore_backup_YYYYMMDD_HHmmss_SSS
      final tsStr = name.replaceFirst('gastrocore_backup_', '');
      DateTime createdAt;
      try {
        createdAt = _parseTimestamp(tsStr);
      } catch (_) {
        createdAt = f.statSync().modified;
      }
      infos.add(BackupInfo(
        file: f,
        createdAt: createdAt,
        sizeBytes: f.lengthSync(),
      ));
    }

    infos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return infos;
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Overwrite the live database with [backup].
  ///
  /// **Warning:** the caller must restart (or re-open) the database after
  /// calling this method, because the live connection still points at the old
  /// file handle. In practice the app should be restarted.
  Future<void> restoreBackup(BackupInfo backup) async {
    if (!backup.file.existsSync()) {
      throw BackupException('Backup file not found: ${backup.name}');
    }

    final dbPath = await _dbPath();
    try {
      await backup.file.copy(dbPath);
    } catch (e) {
      throw BackupException('Failed to restore backup.', cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Delete a single backup file from disk.
  Future<void> deleteBackup(BackupInfo backup) async {
    if (backup.file.existsSync()) {
      await backup.file.delete();
    }
  }

  // ---------------------------------------------------------------------------
  // Prune old backups
  // ---------------------------------------------------------------------------

  /// Parse a timestamp string of the form `YYYYMMDD_HHmmss_SSS`.
  ///
  /// This avoids relying on `intl`'s millisecond pattern support which
  /// varies across versions.
  static DateTime _parseTimestamp(String s) {
    // s = '20260321_015428_360'
    final year = int.parse(s.substring(0, 4));
    final month = int.parse(s.substring(4, 6));
    final day = int.parse(s.substring(6, 8));
    final hour = int.parse(s.substring(9, 11));
    final min = int.parse(s.substring(11, 13));
    final sec = int.parse(s.substring(13, 15));
    // Milliseconds part: after second underscore
    final ms = s.length >= 19 ? int.parse(s.substring(16, 19)) : 0;
    return DateTime(year, month, day, hour, min, sec, ms);
  }

  Future<void> _pruneOldBackups(Directory dir) async {
    final all = await listBackups();
    if (all.length <= _maxBackups) return;

    // all is sorted newest-first; delete from the tail
    final toDelete = all.skip(_maxBackups);
    for (final b in toDelete) {
      try {
        await b.file.delete();
      } catch (_) {
        // Best effort — don't crash if an old file can't be deleted.
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class BackupException implements Exception {
  const BackupException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause != null ? 'BackupException: $message ($cause)' : 'BackupException: $message';
}
