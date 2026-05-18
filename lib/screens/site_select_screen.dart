// ============================================================
// lib/screens/site_select_screen.dart - 現場選択画面
// ============================================================

import 'package:flutter/material.dart';
import '../services/site_service.dart';
import '../services/auth_service.dart';

class SiteSelectScreen extends StatefulWidget {
  const SiteSelectScreen({super.key});

  @override
  State<SiteSelectScreen> createState() => _SiteSelectScreenState();
}

class _SiteSelectScreenState extends State<SiteSelectScreen> {
  final SiteService _siteService = SiteService();
  final AuthService _auth = AuthService();

  List<dynamic> _sites = [];
  bool _isLoading = true;
  String? _error;
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _role = await _auth.getRole();
    await _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() { _isLoading = true; _error = null; });

    final result = await _siteService.getSites();

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _sites = result['sites'] as List<dynamic>;
      } else {
        _error = result['message'] as String?;
      }
    });
  }

  // ============================================================
  // 現場新規登録ダイアログ
  // ============================================================

  Future<void> _showAddSiteDialog() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          '現場を追加',
          style: TextStyle(color: Color(0xFFD4AF37)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '現場名 *',
                labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD4AF37)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: codeCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '現場コード（任意）',
                labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD4AF37)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addrCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '住所（任意）',
                labelStyle: TextStyle(color: Color(0xFF9E9E9E)),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3A3A3A)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD4AF37)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル',
                style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              final result = await _siteService.createSite(
                siteName: nameCtrl.text.trim(),
                siteCode: codeCtrl.text.trim().isEmpty
                    ? null
                    : codeCtrl.text.trim(),
                address: addrCtrl.text.trim().isEmpty
                    ? null
                    : addrCtrl.text.trim(),
              );
              if (result['success'] == true) {
                _loadSites();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('現場を登録しました')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['message'] ?? 'エラーが発生しました'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('登録'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = ['boss', 'admin_office', 'admin_exec'].contains(_role);

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFD4AF37),
        title: const Text('現場を選択'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSites,
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              onPressed: _showAddSiteDialog,
              child: const Icon(Icons.add),
            )
          : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSites,
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                )
              : _sites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_off,
                              color: Color(0xFF9E9E9E), size: 64),
                          const SizedBox(height: 16),
                          const Text(
                            '現場が登録されていません',
                            style: TextStyle(color: Color(0xFF9E9E9E)),
                          ),
                          if (canAdd) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4AF37),
                                foregroundColor: Colors.black,
                              ),
                              onPressed: _showAddSiteDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('現場を追加'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sites.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final site = _sites[i];
                        return ListTile(
                          tileColor: const Color(0xFF2A2A2A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: const Icon(
                            Icons.location_on,
                            color: Color(0xFFD4AF37),
                          ),
                          title: Text(
                            site['site_name'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: site['address'] != null
                              ? Text(
                                  site['address'] as String,
                                  style: const TextStyle(
                                      color: Color(0xFF9E9E9E)),
                                )
                              : null,
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Color(0xFF9E9E9E),
                          ),
                          onTap: () => Navigator.pop(context, site),
                        );
                      },
                    ),
    );
  }
}