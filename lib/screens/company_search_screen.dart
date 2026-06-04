// lib/screens/company_search_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, showJsSnackbar;
import '../config/constants.dart';

const String _API_URL = kApiBaseUrl;

class CompanySearchScreen extends StatefulWidget {
  const CompanySearchScreen({super.key});
  @override
  State<CompanySearchScreen> createState() => _CompanySearchScreenState();
}

class _CompanySearchScreenState extends State<CompanySearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _filtered  = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.get(
        Uri.parse('$_API_URL/companies'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['companies'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        if (mounted) setState(() { _companies = list; _filtered = list; });
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, '会社一覧の取得に失敗しました', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _companies
          : _companies.where((c) =>
              (c['company_name'] as String).toLowerCase().contains(q) ||
              (c['company_code'] as String).toLowerCase().contains(q),
            ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会社を選択')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _filter,
            decoration: const InputDecoration(
              labelText: '会社名・会社コードで検索',
              prefixIcon: Icon(Icons.search, color: JsColors.silver),
            ),
            style: const TextStyle(color: JsColors.offWhite),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
              : _filtered.isEmpty
                  ? const Center(
                      child: Text('会社が見つかりません',
                          style: TextStyle(color: JsColors.silver)))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        final isMaster = c['is_master'] as bool? ?? false;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isMaster
                                ? JsColors.gold.withValues(alpha: 0.2)
                                : JsColors.gunmetal,
                            child: Icon(
                              isMaster ? Icons.star : Icons.business,
                              color: isMaster ? JsColors.gold : JsColors.silver,
                              size: 18,
                            ),
                          ),
                          title: Text(c['company_name'] as String,
                              style: const TextStyle(
                                  color: JsColors.offWhite,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(c['company_code'] as String,
                              style: const TextStyle(
                                  color: JsColors.silver, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right,
                              color: JsColors.silver),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
