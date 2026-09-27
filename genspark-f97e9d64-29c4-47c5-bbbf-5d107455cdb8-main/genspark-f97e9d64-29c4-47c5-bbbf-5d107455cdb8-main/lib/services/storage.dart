import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/doc.dart';

/// Persistence layer. Hive works on Android (files) and web (IndexedDB),
/// so the preview behaves exactly like the shipped app.
class Storage {
  Storage._();

  static const _docsBox = 'docs_v1';
  static const _foldersBox = 'folders_v1';
  static const _prefsBox = 'prefs_v1';

  static Box? _docs;
  static Box? _folders;
  static Box? _prefs;

  static bool get ready => _docs != null;

  static Future<void> init() async {
    try {
      await Hive.initFlutter('docuscan');
      _docs = await Hive.openBox(_docsBox);
      _folders = await Hive.openBox(_foldersBox);
      _prefs = await Hive.openBox(_prefsBox);
    } catch (e) {
      debugPrint('Storage init failed, running in-memory: $e');
    }
  }

  // ── Documents ───────────────────────────────────────────────────────

  static List<ScanDoc> loadDocs() {
    final box = _docs;
    if (box == null) return [];
    final out = <ScanDoc>[];
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw is Map) out.add(ScanDoc.fromMap(raw));
      } catch (e) {
        debugPrint('Skipping corrupt doc $key: $e');
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  static Future<void> saveDoc(ScanDoc d) async {
    try {
      await _docs?.put(d.id, d.toMap());
    } catch (e) {
      debugPrint('saveDoc failed: $e');
    }
  }

  static Future<void> deleteDoc(String id) async {
    try {
      await _docs?.delete(id);
    } catch (e) {
      debugPrint('deleteDoc failed: $e');
    }
  }

  // ── Folders ─────────────────────────────────────────────────────────

  static List<Folder> loadFolders() {
    final box = _folders;
    if (box == null) return [];
    final out = <Folder>[];
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw is Map) out.add(Folder.fromMap(raw));
      } catch (_) {}
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  static Future<void> saveFolder(Folder f) async {
    try {
      await _folders?.put(f.id, f.toMap());
    } catch (e) {
      debugPrint('saveFolder failed: $e');
    }
  }

  static Future<void> deleteFolder(String id) async {
    try {
      await _folders?.delete(id);
    } catch (e) {
      debugPrint('deleteFolder failed: $e');
    }
  }

  // ── Preferences ─────────────────────────────────────────────────────

  static T? pref<T>(String key) {
    try {
      final v = _prefs?.get(key);
      return v is T ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPref(String key, Object? value) async {
    try {
      await _prefs?.put(key, value);
    } catch (e) {
      debugPrint('setPref failed: $e');
    }
  }
}
