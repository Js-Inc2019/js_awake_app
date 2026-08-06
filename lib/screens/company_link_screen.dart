// lib/screens/company_link_screen.dart - 協力申請管理画面（FIELD 職人用）
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show showJsSnackbar;
import '../core/theme/field_tokens.dart';
import '../config/constants.dart';
import '../widgets/search_suggest_field.dart';

class CompanyLinkScreen extends StatefulWidget {
  const CompanyLinkScreen({super.key});
  @override
  State<CompanyLinkScreen> createState() => _CompanyLinkScreenState();
}

class _CompanyLinkScreenState extends State<CompanyLinkScreen> {
  List<Map<String, dynamic>> _links = [];
  bool _loading    = true;
  bool _submitting = false;

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('auth_token') ?? ''}',
      'Content-Type':  'application/json',
    };
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/company-links/my'),
        headers: await _headers,
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _links = (data['links'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRequestSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CompanySearchSheet(
        onSelect: (companyId, companyName) async {
          Navigator.pop(ctx);
          await _submitRequest(companyId, companyName);
        },
      ),
    );
  }

  Future<void> _submitRequest(String companyId, String companyName) async {
    setState(() => _submitting = true);
    try {
      final res = await http.post(
        Uri.parse('$kApiBaseUrl/company-links/request'),
        headers: await _headers,
        body: jsonEncode({'company_id': companyId}),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 201) {
        showJsSnackbar(context, '$companyName に申請を送信しました');
        _load();
      } else {
        final err = (jsonDecode(res.body) as Map<String, dynamic>)['error']
            as String? ?? 'エラーが発生しました';
        showJsSnackbar(context, err, isError: true);
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, '通信エラーが発生しました', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.length < 10) return '';
    final p = raw.substring(0, 10).split('-');
    if (p.length == 3) return '${int.parse(p[1])}月${int.parse(p[2])}日';
    return raw.substring(0, 10);
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'active':   return FieldTokens.statusSuccess;
      case 'rejected': return FieldTokens.statusError;
      default:         return FieldTokens.accent;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'active':   return '承認済み';
      case 'rejected': return '却下';
      default:         return '審査中';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        title: const Text('協力申請',
            style: TextStyle(color: FieldTokens.brand, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: FieldTokens.textSupport),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: FieldTokens.textSupport),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting ? null : _showRequestSheet,
        backgroundColor: FieldTokens.accent,
        foregroundColor: FieldTokens.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('新しく申請する', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: FieldTokens.accent))
          : _links.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.handshake_outlined,
                        color: FieldTokens.textSupport, size: 48),
                    SizedBox(height: 12),
                    Text('協力申請はありません',
                        style: TextStyle(color: FieldTokens.textSupport)),
                    SizedBox(height: 6),
                    Text('右下のボタンから申請できます',
                        style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: FieldTokens.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: _links.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final link        = _links[i];
                      final status      = link['status'] as String?;
                      final companyName = (link['resolved_company_name'] ??
                          link['company_name']) as String? ?? '不明';
                      final date   = _fmtDate(link['created_at'] as String?);
                      final reason = link['reject_reason'] as String?;
                      final sc     = _statusColor(status);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: FieldTokens.surfaceCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                            left:   BorderSide(color: sc, width: 3),
                            top:    const BorderSide(color: FieldTokens.outline),
                            right:  const BorderSide(color: FieldTokens.outline),
                            bottom: const BorderSide(color: FieldTokens.outline),
                          ),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(companyName,
                                    style: const TextStyle(
                                        color: FieldTokens.textBody,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                if (reason != null && reason.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('理由: $reason',
                                      style: const TextStyle(
                                          color: FieldTokens.statusError, fontSize: 11)),
                                ],
                                if (date.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(date,
                                      style: const TextStyle(
                                          color: FieldTokens.textSupport, fontSize: 11)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: sc.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sc),
                            ),
                            child: Text(_statusLabel(status),
                                style: TextStyle(
                                    color: sc,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── 会社名検索シート ───────────────────────────────────────

class _CompanySearchSheet extends StatefulWidget {
  const _CompanySearchSheet({required this.onSelect});
  final Future<void> Function(String companyId, String companyName) onSelect;

  @override
  State<_CompanySearchSheet> createState() => _CompanySearchSheetState();
}

class _CompanySearchSheetState extends State<_CompanySearchSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _searched  = false;
  Timer? _debounce;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results   = [];
        _searched  = false;
        _searching = false;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final uri = Uri.parse('$kApiBaseUrl/companies/search')
          .replace(queryParameters: {'q': q});
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _results   = (data['companies'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _searching = false;
          _searched  = true;
        });
      } else {
        setState(() { _searching = false; _searched = true; });
      }
    } catch (_) {
      if (mounted) setState(() { _searching = false; _searched = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ドラッグハンドル
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: FieldTokens.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            '協力申請',
            style: TextStyle(
                color: FieldTokens.accent,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          const SizedBox(height: 12),
          // 検索中インジケータ（_searching を参照＝従来の suffixIcon スピナー代替）
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: LinearProgressIndicator(
                  color: FieldTokens.accent, backgroundColor: Colors.transparent),
            ),
          // 候補リスト（検索欄の上に表示）
          if (_searched && _results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '該当する会社が見つかりません',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 13),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final c    = _results[i];
                  final name = c['company_name'] as String? ?? '';
                  final city = c['address_city'] as String? ?? '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: FieldTokens.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: FieldTokens.outline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                    color: FieldTokens.textBody,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                              if (city.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  city,
                                  style: const TextStyle(
                                      color: FieldTokens.textSupport,
                                      fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 36,
                          child: ElevatedButton(
                            onPressed: () => widget.onSelect(
                                c['company_id'] as String, name),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FieldTokens.accent,
                              foregroundColor: FieldTokens.onAccent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(8)),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                            ),
                            child: const Text(
                              '申請',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          // 検索欄（最下段・候補チップ直上）。onChanged=_onChanged（300msデバウンス+/companies/search）は不変。
          // 候補チップは API 取得済み _results の会社名（差し替えは親 setState）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchSuggestField(
              controller: _ctrl,
              candidates: _results
                  .map((c) => (c['company_name'] as String? ?? '').trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
              hintText: '会社名でさがす',
              autofocus: true, // シート表示で従来どおり自動フォーカス（旧autofocus保全）
              onChanged: _onChanged,
              onSelected: _onChanged,
              // 候補はサーバ(/companies/search)が正規化検索で絞り済み。
              // 生テキスト部分一致の再フィルタでサーバ候補を捨てない。
              serverFiltered: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
