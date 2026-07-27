// ============================================================
// lib/screens/share_screen.dart - 他社報告送信画面
// 職長・事務が他社に日報を送信する
// ============================================================

import 'package:flutter/material.dart';
 import '../core/theme/js_colors.dart';
import '../services/share_service.dart';
import '../services/company_service.dart';

class ShareScreen extends StatefulWidget {
  final String reportId;
  final String workerName;
  final String reportDate;

  const ShareScreen({
    super.key,
    required this.reportId,
    required this.workerName,
    required this.reportDate,
  });

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final ShareService   _shareService   = ShareService();
  final CompanyService _companyService = CompanyService();

  List<dynamic> _companies = [];
  String? _selectedCompanyId;
  String? _selectedCompanyName;
  String  _shareType = 'in_app';
  final   _memoCtrl  = TextEditingController();
  bool    _isLoading = true;
  bool    _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    final result = await _companyService.getCompanies();
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        // 自社以外の会社一覧
        _companies = (result['companies'] as List<dynamic>)
            .where((c) => c['is_master'] != true)
            .toList();
      }
    });
  }

  Future<void> _send() async {
    if (_selectedCompanyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('送信先を選択してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    final result = await _shareService.sendReport(
      reportId:          widget.reportId,
      receiverCompanyId: _selectedCompanyId!,
      shareType:         _shareType,
      memo:              _memoCtrl.text.trim().isEmpty
          ? null
          : _memoCtrl.text.trim(),
    );

    setState(() => _isSending = false);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_selectedCompanyNameに送信しました'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'エラーが発生しました'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.background,
      appBar: AppBar(
        backgroundColor: JsColors.background,
        foregroundColor: JsColors.accent,
        title: const Text('他社に報告送信'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: JsColors.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 日報情報カード
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: JsColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('送信する日報',
                            style: TextStyle(
                                color: JsColors.textMid,
                                fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(
                          widget.workerName,
                          style: const TextStyle(
                            color: JsColors.textStrong,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.reportDate,
                          style: const TextStyle(
                              color: JsColors.textMid),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 送信先選択
                  const Text('送信先を選択 *',
                      style: TextStyle(
                          color: JsColors.textMid, fontSize: 12)),
                  const SizedBox(height: 8),

                  if (_companies.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: JsColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '繋がっている会社がありません\n管理者に確認してください',
                        style: TextStyle(color: JsColors.textMid),
                      ),
                    )
                  else
                    ...(_companies.map((company) {
                      final isSelected =
                          _selectedCompanyId == company['company_id'];
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedCompanyId =
                              company['company_id'] as String;
                          _selectedCompanyName =
                              company['company_name'] as String;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? JsColors.surfaceAlt
                                : JsColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? JsColors.accent
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.business,
                                color: isSelected
                                    ? JsColors.accent
                                    : JsColors.textMid,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      company['company_name'] as String,
                                      style: TextStyle(
                                        color: isSelected
                                            ? JsColors.accent
                                            : JsColors.textStrong,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      company['company_code'] as String,
                                      style: const TextStyle(
                                          color: JsColors.textMid,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    })),

                  const SizedBox(height: 24),

                  // 送信方法
                  const Text('送信方法',
                      style: TextStyle(
                          color: JsColors.textMid, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ShareTypeButton(
                        label: 'アプリ内',
                        icon: Icons.app_registration,
                        value: 'in_app',
                        selected: _shareType,
                        onTap: (v) => setState(() => _shareType = v),
                      ),
                      const SizedBox(width: 8),
                      _ShareTypeButton(
                        label: 'PDF',
                        icon: Icons.picture_as_pdf,
                        value: 'pdf',
                        selected: _shareType,
                        onTap: (v) => setState(() => _shareType = v),
                      ),
                      const SizedBox(width: 8),
                      _ShareTypeButton(
                        label: 'メール',
                        icon: Icons.email,
                        value: 'email',
                        selected: _shareType,
                        onTap: (v) => setState(() => _shareType = v),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // メモ
                  const Text('メモ（任意）',
                      style: TextStyle(
                          color: JsColors.textMid, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _memoCtrl,
                    style: const TextStyle(color: JsColors.textStrong),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: '送信先へのメモを入力...',
                      hintStyle:
                          const TextStyle(color: JsColors.textMid),
                      filled: true,
                      fillColor: JsColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: JsColors.accent),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 送信ボタン
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JsColors.accent,
                        foregroundColor: JsPalette.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: JsPalette.onAccent,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        _isSending ? '送信中...' : '送信する',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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

// ============================================================
// 送信方法ボタン
// ============================================================

class _ShareTypeButton extends StatelessWidget {
  const _ShareTypeButton({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String   label;
  final IconData icon;
  final String   value;
  final String   selected;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? JsColors.surfaceAlt
                : JsColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? JsColors.accent
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected
                      ? JsColors.accent
                      : JsColors.textMid,
                  size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color: isSelected
                        ? JsColors.accent
                        : JsColors.textMid,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}