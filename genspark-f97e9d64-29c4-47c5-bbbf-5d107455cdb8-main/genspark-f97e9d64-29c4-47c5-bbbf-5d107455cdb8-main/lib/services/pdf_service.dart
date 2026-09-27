import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/doc.dart';
import 'image_pipeline.dart';

class PdfOptions {
  final PageSize size;
  final ExportQuality quality;
  final bool includePageNumbers;
  final String? watermark;
  final double watermarkOpacity;

  const PdfOptions({
    this.size = PageSize.auto,
    this.quality = ExportQuality.high,
    this.includePageNumbers = false,
    this.watermark,
    this.watermarkOpacity = 0.14,
  });

  PdfOptions copyWith({
    PageSize? size,
    ExportQuality? quality,
    bool? includePageNumbers,
    String? watermark,
    double? watermarkOpacity,
  }) => PdfOptions(
    size: size ?? this.size,
    quality: quality ?? this.quality,
    includePageNumbers: includePageNumbers ?? this.includePageNumbers,
    watermark: watermark ?? this.watermark,
    watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
  );
}

class PdfService {
  PdfService._();

  static PdfPageFormat? _format(PageSize s) {
    switch (s) {
      case PageSize.auto:
        return null;
      case PageSize.a4:
        return PdfPageFormat.a4;
      case PageSize.letter:
        return PdfPageFormat.letter;
      case PageSize.legal:
        return PdfPageFormat.legal;
      case PageSize.a5:
        return PdfPageFormat.a5;
    }
  }

  /// Build the PDF bytes for a document.
  static Future<Uint8List> build(ScanDoc doc, PdfOptions o) async {
    final pdf = pw.Document(
      title: doc.title,
      creator: 'DocuScan Pro',
      subject: doc.title,
    );

    final total = doc.pages.length;
    for (int i = 0; i < total; i++) {
      final page = doc.pages[i];
      final bytes = ImagePipeline.forExport(
        page.processed,
        o.quality.maxEdge,
        o.quality == ExportQuality.high ? 90 : 82,
      );
      final image = pw.MemoryImage(bytes);
      final fmt =
          _format(o.size) ??
          PdfPageFormat(image.width!.toDouble(), image.height!.toDouble());

      pdf.addPage(
        pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.zero,
          build: (ctx) {
            return pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Container(
                    color: PdfColors.white,
                    child: pw.Center(
                      child: pw.Image(image, fit: pw.BoxFit.contain),
                    ),
                  ),
                ),
                if (o.watermark != null && o.watermark!.trim().isNotEmpty)
                  pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: 0.5,
                        child: pw.Opacity(
                          opacity: o.watermarkOpacity,
                          child: pw.Text(
                            o.watermark!,
                            style: pw.TextStyle(
                              fontSize: fmt.width * 0.11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (o.includePageNumbers)
                  pw.Positioned(
                    bottom: 14,
                    right: 18,
                    child: pw.Opacity(
                      opacity: 0.55,
                      child: pw.Text(
                        '${i + 1} / $total',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static String fileName(ScanDoc doc) {
    var t = doc.title.trim();
    if (t.isEmpty) t = 'Document';
    t = t.replaceAll(RegExp(r'[^A-Za-z0-9 _\-]'), '').replaceAll(' ', '_');
    return '$t.pdf';
  }

  /// Open the OS print / save-as-PDF dialog. Works on web too.
  static Future<void> printDoc(ScanDoc doc, PdfOptions o) async {
    final bytes = await build(doc, o);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName(doc));
  }

  /// Share the PDF via the platform share sheet, with a download
  /// fallback on the web.
  static Future<void> shareDoc(ScanDoc doc, PdfOptions o) async {
    final bytes = await build(doc, o);
    final name = fileName(doc);
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: name);
      return;
    }
    try {
      await Share.shareXFiles([
        XFile.fromData(bytes, mimeType: 'application/pdf', name: name),
      ], subject: doc.title);
    } catch (e) {
      debugPrint('share failed, falling back to sharePdf: $e');
      await Printing.sharePdf(bytes: bytes, filename: name);
    }
  }

  /// Share the individual page images instead of a PDF.
  static Future<void> shareImages(ScanDoc doc) async {
    final files = <XFile>[];
    for (int i = 0; i < doc.pages.length; i++) {
      files.add(
        XFile.fromData(
          doc.pages[i].processed,
          mimeType: 'image/jpeg',
          name: '${doc.title}_${i + 1}.jpg',
        ),
      );
    }
    if (files.isEmpty) return;
    await Share.shareXFiles(files, subject: doc.title);
  }
}
