// lib/services/pdf_service.dart - PDF生成・共有サービス
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class PdfService {
  static final PdfService instance = PdfService._();
  PdfService._();

  // ─── 日報PDF生成 ───────────────────────────────────────
  Future<File> generateDailyReport({
    required String date,
    required String siteName,
    required List<Map<String, dynamic>> reports,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();

    // 駐車料金合計
    final totalFee = reports.fold<int>(0, (sum, r) {
      final fee = r['parkingFee'] ?? r['parking_fee'];
      if (fee == null || fee.toString().isEmpty) return sum;
      return sum + (int.tryParse(fee.toString()) ?? 0);
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          // ヘッダー
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFD4AF37),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("J's Inc. 日報",
                    style: pw.TextStyle(font: bold, fontSize: 20, color: PdfColors.black)),
                pw.Text(date,
                    style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.black)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // 現場情報
          if (siteName.isNotEmpty) ...[
            pw.Text('現場: $siteName',
                style: pw.TextStyle(font: bold, fontSize: 14)),
            pw.SizedBox(height: 12),
          ],

          // サマリー
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const PdfColor.fromInt(0xFF3A3A3A)),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(children: [
                  pw.Text('出勤人数', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
                  pw.Text('${reports.length}人', style: pw.TextStyle(font: bold, fontSize: 18)),
                ]),
                pw.Column(children: [
                  pw.Text('駐車料金合計', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
                  pw.Text('¥$totalFee', style: pw.TextStyle(font: bold, fontSize: 18)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // テーブルヘッダー
          pw.Text('出勤記録', style: pw.TextStyle(font: bold, fontSize: 14)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(3),
            },
            children: [
              // ヘッダー行
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: ['名前', '交通手段', '時刻', '駐車料金', '作業内容']
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(h,
                              style: pw.TextStyle(font: bold, fontSize: 10)),
                        ))
                    .toList(),
              ),
              // データ行
              ...reports.map((r) {
                final name      = r['name']        ?? r['worker_name']   ?? '';
                final transport = r['transport']   ?? r['transport_type'] ?? '';
                final time      = r['timeLabel']   ?? r['clock_in_time']  ?? '';
                final fee       = r['parkingFee']  ?? r['parking_fee']    ?? '';
                final work      = r['workContent'] ?? r['work_content']   ?? '';
                final transportLabel = {
                  'train': '電車', 'car': '車', 'bus': 'バス',
                  'bike': '自転車', 'walk': '徒歩',
                }[transport] ?? transport;

                return pw.TableRow(children: [
                  name, transportLabel,
                  time.toString().length >= 5 ? time.toString().substring(0,5) : time.toString(),
                  fee.toString().isNotEmpty ? '¥$fee' : '-',
                  work,
                ].map((v) => pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(v.toString(),
                      style: pw.TextStyle(font: font, fontSize: 9)),
                )).toList());
              }),
            ],
          ),
          pw.SizedBox(height: 24),

          // フッター
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('株式会社J\'s',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
              pw.Text('Generated by J\'s Awake App',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
            ],
          ),
        ],
      ),
    );

    // 保存
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/js_report_$date.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ─── PDF共有 ───────────────────────────────────────────
  Future<void> sharePdf(File pdfFile, String date) async {
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      subject: "J's 日報 $date",
      text: "J's Awake App 日報レポート ($date)",
    );
  }

  // ─── PDFプレビュー ─────────────────────────────────────
  Future<void> previewPdf(BuildContext context, File pdfFile) async {
    await Printing.layoutPdf(
      onLayout: (_) async => pdfFile.readAsBytes(),
    );
  }
}
