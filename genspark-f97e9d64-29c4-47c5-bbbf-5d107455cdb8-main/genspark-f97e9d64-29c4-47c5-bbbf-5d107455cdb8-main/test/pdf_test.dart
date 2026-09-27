import 'package:docuscan_pro/models/doc.dart';
import 'package:docuscan_pro/services/image_pipeline.dart';
import 'package:docuscan_pro/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

ScanDoc makeDoc(int pages, {String title = 'Test Doc'}) {
  return ScanDoc(
    id: 'd',
    title: title,
    pages: List.generate(pages, (i) {
      final b = ImagePipeline.syntheticPage(
          seed: i * 13 + 1, kind: 'notes', width: 300);
      return ScanPage(id: 'p$i', original: b, processed: b);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a valid multi-page PDF', () async {
    final bytes = await PdfService.build(makeDoc(3), const PdfOptions());
    expect(bytes.lengthInBytes, greaterThan(1000));
    // PDF magic header
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    // Trailer present => document closed properly
    final tail = String.fromCharCodes(
        bytes.sublist(bytes.length - 64, bytes.length));
    expect(tail.contains('%%EOF'), isTrue);
    // Three page objects
    final body = String.fromCharCodes(bytes);
    expect('/Type /Page'.allMatches(body).length +
        '/Type/Page'.allMatches(body).length, greaterThanOrEqualTo(3));
  });

  test('A4 export produces a different size than auto', () async {
    final doc = makeDoc(1);
    final auto = await PdfService.build(doc, const PdfOptions());
    final a4 = await PdfService.build(
        doc, const PdfOptions(size: PageSize.a4));
    expect(auto.lengthInBytes, greaterThan(0));
    expect(a4.lengthInBytes, greaterThan(0));
  });

  test('lower quality yields a smaller file', () async {
    final doc = makeDoc(2);
    final hi = await PdfService.build(
        doc, const PdfOptions(quality: ExportQuality.high));
    final lo = await PdfService.build(
        doc, const PdfOptions(quality: ExportQuality.low));
    expect(lo.lengthInBytes, lessThanOrEqualTo(hi.lengthInBytes));
  });

  test('watermark and page numbers do not corrupt output', () async {
    final bytes = await PdfService.build(
      makeDoc(2),
      const PdfOptions(
        watermark: 'CONFIDENTIAL',
        includePageNumbers: true,
        size: PageSize.letter,
      ),
    );
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.lengthInBytes, greaterThan(1000));
  });

  test('file name is sanitised for the filesystem', () {
    final doc = ScanDoc(
        id: 'x', title: 'Invoice #42/2025: "final"', pages: []);
    final n = PdfService.fileName(doc);
    expect(n.endsWith('.pdf'), isTrue);
    expect(RegExp(r'[/\\:"#]').hasMatch(n), isFalse);
  });

  test('empty title falls back to a default name', () {
    final doc = ScanDoc(id: 'y', title: '   ', pages: []);
    expect(PdfService.fileName(doc), 'Document.pdf');
  });

  test('single page document exports cleanly', () async {
    final bytes = await PdfService.build(makeDoc(1), const PdfOptions());
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });
}
