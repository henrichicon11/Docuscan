import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Enhancement presets applied to a captured page.
enum ScanFilter {
  original('Original', 'No enhancement'),
  magic('Magic Color', 'Whiten paper, boost ink'),
  lighten('Lighten', 'Soften heavy shadows'),
  grayscale('Grayscale', 'Neutral gray tones'),
  bw('B & W', 'High-contrast document'),
  ink('Ink Boost', 'Deepen faint pen strokes');

  const ScanFilter(this.label, this.blurb);
  final String label;
  final String blurb;
}

enum PageSize {
  auto('Auto (fit image)'),
  a4('A4  ·  210 × 297 mm'),
  letter('Letter  ·  8.5 × 11 in'),
  legal('Legal  ·  8.5 × 14 in'),
  a5('A5  ·  148 × 210 mm');

  const PageSize(this.label);
  final String label;
}

enum ExportQuality {
  high('High', 2000),
  medium('Medium', 1400),
  low('Small file', 1000);

  const ExportQuality(this.label, this.maxEdge);
  final String label;
  final int maxEdge;
}

/// A single scanned page.
class ScanPage {
  final String id;
  Uint8List original; // raw imported/captured bytes
  Uint8List processed; // after crop + filter + adjustments
  ScanFilter filter;
  int rotation; // quarter turns, 0..3
  double brightness; // -1..1
  double contrast; // -1..1
  double sharpen; // 0..1
  /// Normalised crop quad (tl, tr, br, bl) in 0..1 space of the original.
  List<Offset>? corners;
  String? ocrText;
  DateTime createdAt;

  ScanPage({
    required this.id,
    required this.original,
    required this.processed,
    this.filter = ScanFilter.magic,
    this.rotation = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpen = 0,
    this.corners,
    this.ocrText,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  ScanPage clone(String newId) => ScanPage(
    id: newId,
    original: Uint8List.fromList(original),
    processed: Uint8List.fromList(processed),
    filter: filter,
    rotation: rotation,
    brightness: brightness,
    contrast: contrast,
    sharpen: sharpen,
    corners: corners == null ? null : List<Offset>.from(corners!),
    ocrText: ocrText,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'original': original,
    'processed': processed,
    'filter': filter.name,
    'rotation': rotation,
    'brightness': brightness,
    'contrast': contrast,
    'sharpen': sharpen,
    'corners': corners?.expand((o) => [o.dx, o.dy]).toList(),
    'ocrText': ocrText,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static ScanPage fromMap(Map m) {
    List<Offset>? corners;
    final raw = m['corners'];
    if (raw is List && raw.length == 8) {
      corners = [
        for (int i = 0; i < 8; i += 2)
          Offset((raw[i] as num).toDouble(), (raw[i + 1] as num).toDouble()),
      ];
    }
    return ScanPage(
      id: m['id'] as String,
      original: _bytes(m['original']),
      processed: _bytes(m['processed']),
      filter: ScanFilter.values.firstWhere(
        (f) => f.name == m['filter'],
        orElse: () => ScanFilter.magic,
      ),
      rotation: (m['rotation'] as num?)?.toInt() ?? 0,
      brightness: (m['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (m['contrast'] as num?)?.toDouble() ?? 0,
      sharpen: (m['sharpen'] as num?)?.toDouble() ?? 0,
      corners: corners,
      ocrText: m['ocrText'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static Uint8List _bytes(dynamic v) {
    if (v is Uint8List) return v;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    return Uint8List(0);
  }
}

/// A multi-page document.
class ScanDoc {
  final String id;
  String title;
  String? folderId;
  List<ScanPage> pages;
  DateTime createdAt;
  DateTime updatedAt;
  bool favorite;
  bool locked;

  ScanDoc({
    required this.id,
    required this.title,
    this.folderId,
    List<ScanPage>? pages,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.favorite = false,
    this.locked = false,
  }) : pages = pages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  int get pageCount => pages.length;

  int get byteSize =>
      pages.fold<int>(0, (sum, p) => sum + p.processed.lengthInBytes);

  String get sizeLabel {
    final b = byteSize;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get searchBlob {
    final ocr = pages
        .map((p) => p.ocrText ?? '')
        .where((s) => s.isNotEmpty)
        .join(' ');
    return '$title $ocr'.toLowerCase();
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'folderId': folderId,
    'pages': pages.map((p) => p.toMap()).toList(),
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'favorite': favorite,
    'locked': locked,
  };

  static ScanDoc fromMap(Map m) => ScanDoc(
    id: m['id'] as String,
    title: (m['title'] as String?) ?? 'Untitled',
    folderId: m['folderId'] as String?,
    pages: ((m['pages'] as List?) ?? const [])
        .map((e) => ScanPage.fromMap(e as Map))
        .toList(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['updatedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
    favorite: m['favorite'] == true,
    locked: m['locked'] == true,
  );
}

class Folder {
  final String id;
  String name;
  int colorIndex;
  DateTime createdAt;

  Folder({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'colorIndex': colorIndex,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static Folder fromMap(Map m) => Folder(
    id: m['id'] as String,
    name: (m['name'] as String?) ?? 'Folder',
    colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
  );
}

enum SortMode {
  newest('Newest first'),
  oldest('Oldest first'),
  nameAsc('Name A–Z'),
  nameDesc('Name Z–A'),
  pages('Most pages');

  const SortMode(this.label);
  final String label;
}
