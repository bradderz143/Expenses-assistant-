import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/expense_package.dart';
import '../../domain/entities/trip.dart';

/// Owns the on-device folder tree:
///
/// ```
/// Expenses/
///   Trips/<TripFolder>/<package>/
///   Standalone_Expenses/<package>/
///   Exports/
/// ```
///
/// The database stores paths relative to [root] so the tree can be moved
/// (e.g. restored from backup) without rewriting rows.
class FileStorageService {
  FileStorageService(this.root);

  final Directory root;

  static const String rootName = 'Expenses';
  static const String tripsFolder = 'Trips';
  static const String standaloneFolder = 'Standalone_Expenses';
  static const String exportsFolder = 'Exports';

  static Future<FileStorageService> initialise() async {
    final docs = await getApplicationDocumentsDirectory();
    final service = FileStorageService(Directory(p.join(docs.path, rootName)));
    await service.ensureStructure();
    return service;
  }

  Directory get exportsDir => Directory(p.join(root.path, exportsFolder));

  Future<void> ensureStructure() async {
    for (final name in [tripsFolder, standaloneFolder, exportsFolder]) {
      await Directory(p.join(root.path, name)).create(recursive: true);
    }
  }

  String absolute(String relativePath) => p.join(root.path, relativePath);

  String relative(String absolutePath) =>
      p.relative(absolutePath, from: root.path);

  /// Where a receipt's package folder lives, relative to [root].
  String packageParent(Trip? trip) =>
      trip == null ? standaloneFolder : p.join(tripsFolder, trip.folderName);

  Future<bool> existsRelative(String relativePath) =>
      FileSystemEntity.isDirectory(absolute(relativePath));

  /// Copies [sourcePath] byte-for-byte to [relativeTarget].
  Future<File> copyIn(
    String sourcePath,
    String relativeTarget, {
    bool overwrite = false,
  }) async {
    final target = File(absolute(relativeTarget));
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      if (!overwrite) {
        throw FileSystemException('Refusing to overwrite', target.path);
      }
      await target.delete();
    }
    return File(sourcePath).copy(target.path);
  }

  /// Moves a package directory. Falls back to copy+delete across volumes.
  Future<void> moveDirectory(String fromRelative, String toRelative) async {
    final from = Directory(absolute(fromRelative));
    final to = Directory(absolute(toRelative));
    if (!await from.exists()) {
      await to.create(recursive: true);
      return;
    }
    await to.parent.create(recursive: true);
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await to.create(recursive: true);
      await for (final entity in from.list()) {
        if (entity is File) {
          await entity.copy(p.join(to.path, p.basename(entity.path)));
        }
      }
      await from.delete(recursive: true);
    }
    await _removeIfEmpty(from.parent);
  }

  /// Writes via a temp file + rename so a crash never leaves half a file.
  Future<void> writeBytesAtomic(String relativePath, List<int> bytes) async {
    final target = File(absolute(relativePath));
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }

  Future<void> writeStringAtomic(String relativePath, String contents) async {
    final target = File(absolute(relativePath));
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(target.path);
  }

  /// Moves a file within storage, replacing the target if it exists.
  Future<void> replaceFile(String fromRelative, String toRelative) async {
    final from = File(absolute(fromRelative));
    if (!await from.exists()) return;
    final to = File(absolute(toRelative));
    if (await to.exists()) await to.delete();
    await from.rename(to.path);
  }

  Future<void> deleteFileIfExists(String relativePath) async {
    final file = File(absolute(relativePath));
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteDirectory(String relativePath) async {
    final dir = Directory(absolute(relativePath));
    if (await dir.exists()) await dir.delete(recursive: true);
    await _removeIfEmpty(dir.parent);
  }

  Future<List<File>> filesIn(String relativeDir) async {
    final dir = Directory(absolute(relativeDir));
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          !name.endsWith('.tmp') &&
          !name.startsWith(PackageFiles.draftPrefix)) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<List<File>> exports() async {
    if (!await exportsDir.exists()) return const [];
    final files = <File>[];
    await for (final entity in exportsDir.list()) {
      if (entity is File && entity.path.endsWith('.zip')) files.add(entity);
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<int> totalBytes() async {
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Tidies empty trip folders, but never the fixed top-level folders.
  Future<void> _removeIfEmpty(Directory dir) async {
    final rel = relative(dir.path);
    final protected = {'.', tripsFolder, standaloneFolder, exportsFolder};
    if (protected.contains(rel) || rel.startsWith('..')) return;
    if (await dir.exists() && await dir.list().isEmpty) {
      await dir.delete();
    }
  }
}
