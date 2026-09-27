import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/doc.dart';
import '../services/image_pipeline.dart';
import '../services/ocr/ocr.dart';
import '../services/pdf_service.dart';
import '../services/storage.dart';

const _uuid = Uuid();

/// Runs the pipeline off the UI thread. On web, `compute` degrades to a
/// microtask, which is still fine because the work is chunked per page.
Future<Uint8List> _processAsync(ProcessRequest r) {
  if (kIsWeb) {
    // No isolates on web: yield to the event loop so the spinner paints.
    return Future.delayed(
      const Duration(milliseconds: 16),
      () => ImagePipeline.process(r),
    );
  }
  return compute(ImagePipeline.process, r);
}

Future<List<Offset>?> _detectAsync(Uint8List bytes) {
  if (kIsWeb) {
    return Future.delayed(
      const Duration(milliseconds: 16),
      () => ImagePipeline.detectCorners(bytes),
    );
  }
  return compute(ImagePipeline.detectCorners, bytes);
}

class AppState extends ChangeNotifier {
  final List<ScanDoc> _docs = [];
  final List<Folder> _folders = [];

  String _query = '';
  String? _activeFolderId; // null = All
  SortMode _sort = SortMode.newest;
  bool _gridView = false;
  bool _onlyFavorites = false;
  int _themeMode = 0; // 0 system, 1 light, 2 dark
  bool _busy = false;
  String _busyLabel = '';
  double? _busyProgress;

  // Export defaults, remembered between sessions.
  PdfOptions _pdfOptions = const PdfOptions();

  // Multi-select
  final Set<String> _selected = {};

  bool _initialized = false;

  // ── Getters ─────────────────────────────────────────────────────────

  List<ScanDoc> get allDocs => List.unmodifiable(_docs);
  List<Folder> get folders => List.unmodifiable(_folders);
  String get query => _query;
  String? get activeFolderId => _activeFolderId;
  SortMode get sort => _sort;
  bool get gridView => _gridView;
  bool get onlyFavorites => _onlyFavorites;
  int get themeMode => _themeMode;
  bool get busy => _busy;
  String get busyLabel => _busyLabel;
  double? get busyProgress => _busyProgress;
  PdfOptions get pdfOptions => _pdfOptions;
  Set<String> get selected => _selected;
  bool get selecting => _selected.isNotEmpty;
  bool get initialized => _initialized;

  int get totalPages => _docs.fold<int>(0, (s, d) => s + d.pageCount);

  String get librarySize {
    final b = _docs.fold<int>(0, (s, d) => s + d.byteSize);
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Documents after folder / favourite / search filtering and sorting.
  List<ScanDoc> get visibleDocs {
    var list = _docs.where((d) {
      if (_activeFolderId != null && d.folderId != _activeFolderId) {
        return false;
      }
      if (_onlyFavorites && !d.favorite) return false;
      if (_query.trim().isEmpty) return true;
      return d.searchBlob.contains(_query.trim().toLowerCase());
    }).toList();

    switch (_sort) {
      case SortMode.newest:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case SortMode.oldest:
        list.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case SortMode.nameAsc:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case SortMode.nameDesc:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case SortMode.pages:
        list.sort((a, b) => b.pageCount.compareTo(a.pageCount));
        break;
    }
    return list;
  }

  ScanDoc? docById(String id) {
    for (final d in _docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  int docCountInFolder(String? id) {
    if (id == null) return _docs.length;
    return _docs.where((d) => d.folderId == id).length;
  }

  // ── Lifecycle ───────────────────────────────────────────────────────

  Future<void> init() async {
    await Storage.init();
    _docs.addAll(Storage.loadDocs());
    _folders.addAll(Storage.loadFolders());
    _themeMode = Storage.pref<int>('themeMode') ?? 0;
    _gridView = Storage.pref<bool>('gridView') ?? false;
    final sortName = Storage.pref<String>('sort');
    if (sortName != null) {
      _sort = SortMode.values.firstWhere(
        (s) => s.name == sortName,
        orElse: () => SortMode.newest,
      );
    }

    if (_folders.isEmpty && _docs.isEmpty) {
      await _seedDemoLibrary();
    }
    _initialized = true;
    notifyListeners();
  }

  /// Builds a small, believable starter library so the app never opens empty.
  Future<void> _seedDemoLibrary() async {
    final receipts = Folder(id: _uuid.v4(), name: 'Receipts', colorIndex: 0);
    final ids = Folder(id: _uuid.v4(), name: 'ID Cards', colorIndex: 1);
    final contracts = Folder(id: _uuid.v4(), name: 'Contracts', colorIndex: 2);
    _folders.addAll([receipts, ids, contracts]);
    for (final f in _folders) {
      await Storage.saveFolder(f);
    }

    Future<ScanDoc> make(
      String title,
      String kind,
      String? folderId,
      int pageCount,
      int seed, {
      bool favorite = false,
    }) async {
      final pages = <ScanPage>[];
      for (int i = 0; i < pageCount; i++) {
        final bytes = ImagePipeline.syntheticPage(
          seed: seed + i * 37,
          kind: kind,
        );
        pages.add(
          ScanPage(
            id: _uuid.v4(),
            original: bytes,
            processed: bytes,
            filter: ScanFilter.magic,
          ),
        );
      }
      final d = ScanDoc(
        id: _uuid.v4(),
        title: title,
        folderId: folderId,
        pages: pages,
        favorite: favorite,
      );
      await Storage.saveDoc(d);
      return d;
    }

    final now = DateTime.now();
    final seeded = <ScanDoc>[
      await make(
        'Rental Agreement',
        'contract',
        contracts.id,
        4,
        11,
        favorite: true,
      ),
      await make('Grocery Receipt', 'receipt', receipts.id, 1, 202),
      await make('Passport Copy', 'id', ids.id, 2, 77, favorite: true),
      await make('Meeting Notes', 'notes', null, 3, 310),
      await make('Utility Bill', 'receipt', receipts.id, 2, 415),
    ];

    // Stagger timestamps so "Newest first" looks natural.
    for (int i = 0; i < seeded.length; i++) {
      seeded[i].updatedAt = now.subtract(Duration(days: i * 2, hours: i * 5));
      seeded[i].createdAt = seeded[i].updatedAt;
      await Storage.saveDoc(seeded[i]);
    }
    _docs.addAll(seeded);
    _docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  // ── UI preferences ──────────────────────────────────────────────────

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setFolder(String? id) {
    _activeFolderId = id;
    notifyListeners();
  }

  void setSort(SortMode s) {
    _sort = s;
    Storage.setPref('sort', s.name);
    notifyListeners();
  }

  void toggleGrid() {
    _gridView = !_gridView;
    Storage.setPref('gridView', _gridView);
    notifyListeners();
  }

  void toggleOnlyFavorites() {
    _onlyFavorites = !_onlyFavorites;
    notifyListeners();
  }

  void setThemeMode(int m) {
    _themeMode = m;
    Storage.setPref('themeMode', m);
    notifyListeners();
  }

  void setPdfOptions(PdfOptions o) {
    _pdfOptions = o;
    notifyListeners();
  }

  // ── Busy indicator ──────────────────────────────────────────────────

  void _setBusy(String label, {double? progress}) {
    _busy = true;
    _busyLabel = label;
    _busyProgress = progress;
    notifyListeners();
  }

  void _clearBusy() {
    _busy = false;
    _busyLabel = '';
    _busyProgress = null;
    notifyListeners();
  }

  // ── Selection ───────────────────────────────────────────────────────

  void toggleSelect(String id) {
    if (_selected.contains(id)) {
      _selected.remove(id);
    } else {
      _selected.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  void selectAllVisible() {
    _selected.addAll(visibleDocs.map((d) => d.id));
    notifyListeners();
  }

  // ── Folder CRUD ─────────────────────────────────────────────────────

  Future<Folder> createFolder(String name, {int colorIndex = 0}) async {
    final f = Folder(id: _uuid.v4(), name: name, colorIndex: colorIndex);
    _folders.add(f);
    await Storage.saveFolder(f);
    notifyListeners();
    return f;
  }

  Future<void> renameFolder(String id, String name) async {
    final f = _folders.firstWhere((f) => f.id == id);
    f.name = name;
    await Storage.saveFolder(f);
    notifyListeners();
  }

  /// Deletes the folder; contained documents move back to "All".
  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    for (final d in _docs) {
      if (d.folderId == id) {
        d.folderId = null;
        await Storage.saveDoc(d);
      }
    }
    if (_activeFolderId == id) _activeFolderId = null;
    await Storage.deleteFolder(id);
    notifyListeners();
  }

  // ── Document CRUD ───────────────────────────────────────────────────

  /// Create a document from raw captured/imported bytes, running edge
  /// detection and enhancement on each page.
  Future<ScanDoc> createDocFromBytes(
    List<Uint8List> rawPages, {
    String? title,
    String? folderId,
    ScanFilter filter = ScanFilter.magic,
    bool autoCrop = true,
  }) async {
    final pages = <ScanPage>[];
    for (int i = 0; i < rawPages.length; i++) {
      _setBusy(
        'Enhancing page ${i + 1} of ${rawPages.length}',
        progress: rawPages.length == 1 ? null : i / rawPages.length,
      );
      final raw = rawPages[i];
      List<Offset>? corners;
      if (autoCrop) {
        corners = await _detectAsync(raw);
      }
      final processed = await _processAsync(
        ProcessRequest(bytes: raw, corners: corners, filter: filter),
      );
      pages.add(
        ScanPage(
          id: _uuid.v4(),
          original: raw,
          processed: processed,
          filter: filter,
          corners: corners,
        ),
      );
    }

    final doc = ScanDoc(
      id: _uuid.v4(),
      title: title ?? _autoTitle(),
      folderId: folderId ?? _activeFolderId,
      pages: pages,
    );
    _docs.insert(0, doc);
    await Storage.saveDoc(doc);
    _clearBusy();
    return doc;
  }

  String _autoTitle() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}${two(n.minute)}';
  }

  Future<void> addPagesToDoc(
    String docId,
    List<Uint8List> rawPages, {
    ScanFilter filter = ScanFilter.magic,
    bool autoCrop = true,
  }) async {
    final doc = docById(docId);
    if (doc == null) return;
    for (int i = 0; i < rawPages.length; i++) {
      _setBusy('Adding page ${i + 1} of ${rawPages.length}');
      final raw = rawPages[i];
      final corners = autoCrop ? await _detectAsync(raw) : null;
      final processed = await _processAsync(
        ProcessRequest(bytes: raw, corners: corners, filter: filter),
      );
      doc.pages.add(
        ScanPage(
          id: _uuid.v4(),
          original: raw,
          processed: processed,
          filter: filter,
          corners: corners,
        ),
      );
    }
    doc.updatedAt = DateTime.now();
    await Storage.saveDoc(doc);
    _clearBusy();
  }

  /// Re-run the pipeline for a single page after the user edits it.
  Future<void> reprocessPage(
    String docId,
    String pageId, {
    ScanFilter? filter,
    List<Offset>? corners,
    bool clearCorners = false,
    int? rotation,
    double? brightness,
    double? contrast,
    double? sharpen,
    bool silent = false,
  }) async {
    final doc = docById(docId);
    if (doc == null) return;
    final page = doc.pages.firstWhere((p) => p.id == pageId);

    if (filter != null) page.filter = filter;
    if (clearCorners) {
      page.corners = null;
    } else if (corners != null) {
      page.corners = corners;
    }
    if (rotation != null) page.rotation = rotation % 4;
    if (brightness != null) page.brightness = brightness;
    if (contrast != null) page.contrast = contrast;
    if (sharpen != null) page.sharpen = sharpen;

    if (!silent) _setBusy('Applying changes');
    page.processed = await _processAsync(
      ProcessRequest(
        bytes: page.original,
        corners: page.corners,
        filter: page.filter,
        rotation: page.rotation,
        brightness: page.brightness,
        contrast: page.contrast,
        sharpen: page.sharpen,
      ),
    );
    doc.updatedAt = DateTime.now();
    await Storage.saveDoc(doc);
    if (!silent) {
      _clearBusy();
    } else {
      notifyListeners();
    }
  }

  /// Detect edges for a page and return the quad (used by the crop editor).
  Future<List<Offset>?> autoDetect(String docId, String pageId) async {
    final doc = docById(docId);
    if (doc == null) return null;
    final page = doc.pages.firstWhere((p) => p.id == pageId);
    _setBusy('Finding page edges');
    final c = await _detectAsync(page.original);
    _clearBusy();
    return c;
  }

  // ── OCR ─────────────────────────────────────────────────────────────

  /// Run on-device text recognition for one page and remember the result
  /// so the text becomes searchable from the library.
  Future<OcrResult> recognisePage(String docId, String pageId) async {
    final doc = docById(docId);
    if (doc == null) {
      return const OcrResult.unavailable('Document not found.');
    }
    final page = doc.pages.firstWhere((p) => p.id == pageId);

    final result = await OcrEngine.recognise(page.processed);
    if (result.recognised) {
      page.ocrText = result.text;
      doc.updatedAt = DateTime.now();
      await Storage.saveDoc(doc);
      notifyListeners();
    }
    return result;
  }

  /// Recognise every page of a document, reporting progress.
  Future<int> recogniseDocument(String docId) async {
    final doc = docById(docId);
    if (doc == null || !OcrEngine.isSupported) return 0;

    int found = 0;
    for (int i = 0; i < doc.pages.length; i++) {
      _setBusy(
        'Reading page ${i + 1} of ${doc.pages.length}',
        progress: i / doc.pages.length,
      );
      final page = doc.pages[i];
      final r = await OcrEngine.recognise(page.processed);
      if (r.recognised && !r.isEmpty) {
        page.ocrText = r.text;
        found++;
      }
    }
    doc.updatedAt = DateTime.now();
    await Storage.saveDoc(doc);
    _clearBusy();
    return found;
  }

  /// True when at least one page in the document has stored text.
  bool docHasText(String docId) {
    final d = docById(docId);
    if (d == null) return false;
    return d.pages.any((p) => (p.ocrText ?? '').trim().isNotEmpty);
  }

  Future<void> renameDoc(String id, String title) async {
    final d = docById(id);
    if (d == null) return;
    d.title = title;
    d.updatedAt = DateTime.now();
    await Storage.saveDoc(d);
    notifyListeners();
  }

  Future<void> moveDoc(String id, String? folderId) async {
    final d = docById(id);
    if (d == null) return;
    d.folderId = folderId;
    d.updatedAt = DateTime.now();
    await Storage.saveDoc(d);
    notifyListeners();
  }

  Future<void> moveSelected(String? folderId) async {
    for (final id in _selected.toList()) {
      await moveDoc(id, folderId);
    }
    clearSelection();
  }

  Future<void> toggleFavorite(String id) async {
    final d = docById(id);
    if (d == null) return;
    d.favorite = !d.favorite;
    await Storage.saveDoc(d);
    notifyListeners();
  }

  Future<void> deleteDoc(String id) async {
    _docs.removeWhere((d) => d.id == id);
    _selected.remove(id);
    await Storage.deleteDoc(id);
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    for (final id in _selected.toList()) {
      _docs.removeWhere((d) => d.id == id);
      await Storage.deleteDoc(id);
    }
    clearSelection();
  }

  Future<ScanDoc?> duplicateDoc(String id) async {
    final src = docById(id);
    if (src == null) return null;
    _setBusy('Duplicating');
    final copy = ScanDoc(
      id: _uuid.v4(),
      title: '${src.title} copy',
      folderId: src.folderId,
      pages: src.pages.map((p) => p.clone(_uuid.v4())).toList(),
    );
    _docs.insert(0, copy);
    await Storage.saveDoc(copy);
    _clearBusy();
    return copy;
  }

  /// Merge several documents into a new one, preserving page order.
  Future<ScanDoc?> mergeDocs(List<String> ids, String title) async {
    if (ids.length < 2) return null;
    _setBusy('Merging documents');
    final pages = <ScanPage>[];
    for (final id in ids) {
      final d = docById(id);
      if (d == null) continue;
      pages.addAll(d.pages.map((p) => p.clone(_uuid.v4())));
    }
    final merged = ScanDoc(
      id: _uuid.v4(),
      title: title,
      folderId: _activeFolderId,
      pages: pages,
    );
    _docs.insert(0, merged);
    await Storage.saveDoc(merged);
    clearSelection();
    _clearBusy();
    return merged;
  }

  /// Split a document at a page index into two documents.
  Future<void> splitDoc(String id, int atIndex) async {
    final d = docById(id);
    if (d == null || atIndex <= 0 || atIndex >= d.pages.length) return;
    _setBusy('Splitting document');
    final tail = d.pages.sublist(atIndex);
    d.pages = d.pages.sublist(0, atIndex);
    d.updatedAt = DateTime.now();
    final newDoc = ScanDoc(
      id: _uuid.v4(),
      title: '${d.title} (2)',
      folderId: d.folderId,
      pages: tail,
    );
    _docs.insert(0, newDoc);
    await Storage.saveDoc(d);
    await Storage.saveDoc(newDoc);
    _clearBusy();
  }

  // ── Page operations ─────────────────────────────────────────────────

  Future<void> reorderPage(String docId, int from, int to) async {
    final d = docById(docId);
    if (d == null) return;
    if (from < 0 || from >= d.pages.length) return;
    final p = d.pages.removeAt(from);
    final idx = to.clamp(0, d.pages.length);
    d.pages.insert(idx, p);
    d.updatedAt = DateTime.now();
    await Storage.saveDoc(d);
    notifyListeners();
  }

  Future<void> deletePage(String docId, String pageId) async {
    final d = docById(docId);
    if (d == null) return;
    d.pages.removeWhere((p) => p.id == pageId);
    d.updatedAt = DateTime.now();
    if (d.pages.isEmpty) {
      await deleteDoc(docId);
      return;
    }
    await Storage.saveDoc(d);
    notifyListeners();
  }

  Future<void> duplicatePage(String docId, String pageId) async {
    final d = docById(docId);
    if (d == null) return;
    final i = d.pages.indexWhere((p) => p.id == pageId);
    if (i < 0) return;
    d.pages.insert(i + 1, d.pages[i].clone(_uuid.v4()));
    d.updatedAt = DateTime.now();
    await Storage.saveDoc(d);
    notifyListeners();
  }

  /// Apply one filter to every page of a document.
  Future<void> applyFilterToAll(String docId, ScanFilter f) async {
    final d = docById(docId);
    if (d == null) return;
    for (int i = 0; i < d.pages.length; i++) {
      _setBusy(
        'Applying ${f.label} · page ${i + 1}/${d.pages.length}',
        progress: i / d.pages.length,
      );
      final p = d.pages[i];
      p.filter = f;
      p.processed = await _processAsync(
        ProcessRequest(
          bytes: p.original,
          corners: p.corners,
          filter: f,
          rotation: p.rotation,
          brightness: p.brightness,
          contrast: p.contrast,
          sharpen: p.sharpen,
        ),
      );
    }
    d.updatedAt = DateTime.now();
    await Storage.saveDoc(d);
    _clearBusy();
  }

  Future<void> persist(String docId) async {
    final d = docById(docId);
    if (d == null) return;
    d.updatedAt = DateTime.now();
    await Storage.saveDoc(d);
    notifyListeners();
  }
}
