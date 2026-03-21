/// Unit tests for [BackupService].
///
/// Uses [Directory.systemTemp] for file I/O so no special setup is needed.
/// All temporary files and directories are cleaned up in [tearDown].
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:gastrocore_pos/core/services/backup_service.dart';

// ---------------------------------------------------------------------------
// Fake path_provider that returns a temp directory
// ---------------------------------------------------------------------------

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.docsDir);

  final String docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsDir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory docsDir;
  late BackupService svc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gc_backup_test_');
    docsDir = Directory(p.join(tempDir.path, 'docs'))
      ..createSync();

    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    svc = BackupService();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  // createBackup
  // -------------------------------------------------------------------------

  group('createBackup', () {
    test('throws BackupException when source DB does not exist', () async {
      await expectLater(
        svc.createBackup(),
        throwsA(isA<BackupException>()),
      );
    });

    test('creates a .db file in the backup directory', () async {
      // Create a fake source DB.
      final dbPath = p.join(docsDir.path, 'gastrocore_pos.sqlite');
      File(dbPath).writeAsBytesSync([1, 2, 3, 4]);

      final info = await svc.createBackup();

      expect(info.file.existsSync(), isTrue);
      expect(info.name, startsWith('gastrocore_backup_'));
      expect(info.name, endsWith('.db'));
      expect(info.sizeBytes, 4);
    });

    test('backup file content matches source', () async {
      final dbPath = p.join(docsDir.path, 'gastrocore_pos.sqlite');
      final data = List<int>.generate(256, (i) => i % 256);
      File(dbPath).writeAsBytesSync(data);

      final info = await svc.createBackup();
      final content = info.file.readAsBytesSync();
      expect(content, equals(data));
    });

    test('prunes backups beyond 30', () async {
      final dbPath = p.join(docsDir.path, 'gastrocore_pos.sqlite');
      File(dbPath).writeAsBytesSync([0]);

      // Create 31 backups by calling createBackup 31 times.
      for (int i = 0; i < 31; i++) {
        // Small delay so timestamps differ in the filename.
        await svc.createBackup();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final backups = await svc.listBackups();
      expect(backups.length, lessThanOrEqualTo(30));
    });
  });

  // -------------------------------------------------------------------------
  // listBackups
  // -------------------------------------------------------------------------

  group('listBackups', () {
    test('returns empty list when no backups exist', () async {
      final list = await svc.listBackups();
      expect(list, isEmpty);
    });

    test('returns backups sorted newest first', () async {
      final dbPath = p.join(docsDir.path, 'gastrocore_pos.sqlite');
      File(dbPath).writeAsBytesSync([0]);

      await svc.createBackup();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await svc.createBackup();

      final list = await svc.listBackups();
      expect(list.length, 2);
      expect(list[0].createdAt.isAfter(list[1].createdAt), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // restoreBackup
  // -------------------------------------------------------------------------

  group('restoreBackup', () {
    test('overwrites the live DB with the backup content', () async {
      final dbPath = p.join(docsDir.path, 'gastrocore_pos.sqlite');
      File(dbPath).writeAsBytesSync([1, 2, 3]);

      final info = await svc.createBackup();

      // Corrupt the live DB.
      File(dbPath).writeAsBytesSync([99]);

      await svc.restoreBackup(info);

      final restored = File(dbPath).readAsBytesSync();
      expect(restored, equals([1, 2, 3]));
    });

    test('throws BackupException when backup file missing', () async {
      final fakeFile = File(p.join(docsDir.path, 'nonexistent.db'));
      final info = BackupInfo(
        file: fakeFile,
        createdAt: DateTime.now(),
        sizeBytes: 0,
      );

      await expectLater(
        svc.restoreBackup(info),
        throwsA(isA<BackupException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // deleteBackup
  // -------------------------------------------------------------------------

  group('deleteBackup', () {
    test('removes the file from disk', () async {
      final dbPath = p.join(docsDir.path, 'gastrocore_pos.sqlite');
      File(dbPath).writeAsBytesSync([0]);

      final info = await svc.createBackup();
      expect(info.file.existsSync(), isTrue);

      await svc.deleteBackup(info);
      expect(info.file.existsSync(), isFalse);
    });

    test('does not throw when file already missing', () async {
      final fakeFile = File(p.join(docsDir.path, 'gone.db'));
      final info = BackupInfo(
        file: fakeFile,
        createdAt: DateTime.now(),
        sizeBytes: 0,
      );
      await expectLater(svc.deleteBackup(info), completes);
    });
  });

  // -------------------------------------------------------------------------
  // BackupInfo helpers
  // -------------------------------------------------------------------------

  group('BackupInfo.sizeLabel', () {
    test('bytes label', () {
      final info = BackupInfo(
        file: File('x'),
        createdAt: DateTime.now(),
        sizeBytes: 512,
      );
      expect(info.sizeLabel, '512 B');
    });

    test('KB label', () {
      final info = BackupInfo(
        file: File('x'),
        createdAt: DateTime.now(),
        sizeBytes: 2048,
      );
      expect(info.sizeLabel, '2.0 KB');
    });

    test('MB label', () {
      final info = BackupInfo(
        file: File('x'),
        createdAt: DateTime.now(),
        sizeBytes: 3 * 1024 * 1024,
      );
      expect(info.sizeLabel, '3.0 MB');
    });
  });
}
