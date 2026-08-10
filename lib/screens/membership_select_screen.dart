// ============================================================
// lib/screens/membership_select_screen.dart
// requires_selection（複数所属）時の役割選択画面。
// Asphalt Dawn テーマ（core/theme/field_tokens.dart）を使用。
//
// - 呼び出し元（login_screen）から pre_auth_token と、FIELD用に
//   role='worker'|'boss' でフィルタ済みの memberships（2件以上）を受け取る。
// - カードタップ → POST /auth/select-membership → full-login 応答(200) を
//   Navigator.pop(context, data) で呼び出し元へ返し、保存/遷移は
//   login_screen 側の既存 _saveAndNavigate に一任する（同意束の救済刻印・
//   version 判定を重複実装しない）。
// - 401（pre_auth 失効）: 「時間切れです。もう一度ログインしてください」→
//   ログイン画面へ戻す（pop(null)・袋小路なし）。
// - その他エラー: 画面内にエラー表示、戻るでログイン画面（pop(null)）。
//
// ※ pre_auth_token は本画面でもメモリ保持のみ（prefs に保存しない・5分揮発）。
// ============================================================
import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/auth_service.dart';

class MembershipSelectScreen extends StatefulWidget {
  /// verify-pin / verify-device が返した pre_auth_token（メモリ保持のみ）。
  final String preAuthToken;

  /// FIELD 用に role='worker'|'boss' でフィルタ済みの memberships（2件以上）。
  /// 各要素は BE membershipList 由来（membership_id / role / company_name 等。
  /// worker_id は verify-device 経路のみ含まれ得る・nullable）。
  final List<Map<String, dynamic>> memberships;

  const MembershipSelectScreen({
    super.key,
    required this.preAuthToken,
    required this.memberships,
  });

  @override
  State<MembershipSelectScreen> createState() => _MembershipSelectScreenState();
}

class _MembershipSelectScreenState extends State<MembershipSelectScreen> {
  // 送信中の membership_id（非null の間は全カードを無効化しスピナー表示）。
  String? _submittingId;
  String? _errorMessage;

  // 役割ラベル: worker=職人 / boss=職長
  String _roleLabel(String? role) {
    switch (role) {
      case 'worker':
        return '職人';
      case 'boss':
        return '職長';
      default:
        return role ?? '';
    }
  }

  Color _roleColor(String? role) {
    // boss は職長カラー、worker はゴールドアクセント（Asphalt Dawn）。
    return role == 'boss' ? FieldTokens.foremanBase : FieldTokens.accent;
  }

  Future<void> _select(Map<String, dynamic> membership) async {
    if (_submittingId != null) return; // 二重タップ防止
    final membershipId = membership['membership_id'] as String?;
    if (membershipId == null || membershipId.isEmpty) {
      setState(() => _errorMessage = '所属情報が不正です。もう一度ログインしてください');
      return;
    }
    setState(() {
      _submittingId = membershipId;
      _errorMessage = null;
    });
    final res = await AuthService().selectMembership(
      preAuthToken: widget.preAuthToken,
      membershipId: membershipId,
    );

    if (!mounted) return;

    final data = res.data;
    if (res.ok && data != null) {
      // full-login 応答をそのまま呼び出し元へ返す（保存は login_screen が担う）。
      Navigator.of(context).pop(data);
      return;
    }

    if (res.statusCode == 401) {
      // pre_auth 失効（TOKEN_EXPIRED / auth.js:255）→ 時間切れ案内 → ログインへ戻す。
      setState(() => _submittingId = null);
      await _showTimeoutDialog();
      if (mounted) Navigator.of(context).pop(); // 袋小路なし: ログイン画面へ
      return;
    }

    // その他（400/403/500 等）→ 画面内エラー表示（戻るでログイン画面へ）。
    // errorMessage は BE の error フィールド優先（無ければ本文先頭）＝移設前と同じ出所。
    // statusCode:0（通信不成立）も同じ枝に入る＝規約1の
    // 「サーバーに接続できません: $e」をそのまま出す（prefix を重ねない）。
    // ★同じ selectMembership を叩く login_screen.dart:795-804 と同一の形。
    final serverMsg = res.errorMessage;
    setState(() {
      _submittingId = null;
      _errorMessage = (serverMsg != null && serverMsg.isNotEmpty)
          ? serverMsg
          : '所属の選択に失敗しました。もう一度お試しください';
    });
  }

  Future<void> _showTimeoutDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.timer_off, color: FieldTokens.accent),
          SizedBox(width: 8),
          Flexible(
            child: Text('時間切れです',
                style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
          ),
        ]),
        content: const Text(
          'もう一度ログインしてください',
          style: TextStyle(color: FieldTokens.textSupport, height: 1.7),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: FieldTokens.accent,
              foregroundColor: FieldTokens.bgBase,
            ),
            child: const Text('OK',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _submittingId != null;
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        elevation: 0,
        // 選択せず戻れる（袋小路なし）。送信中は誤操作防止で無効化。
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          // 8pt グリッド
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                // コンテンツ群（見出し＋カード群）を画面の垂直中央に配置。
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'どの役割で入りますか？',
                      style: TextStyle(
                        color: FieldTokens.textBody,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '複数の所属があります。入る役割を選んでください',
                      style: TextStyle(color: FieldTokens.textSupport, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FieldTokens.statusError.withValues(alpha: 0.1),
                          border: Border.all(color: FieldTokens.statusError),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: FieldTokens.statusError, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    // ── membership カード（縦並び）──
                    for (final m in widget.memberships) ...[
                      _membershipCard(m),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _membershipCard(Map<String, dynamic> m) {
    final role = m['role'] as String?;
    final roleLabel = _roleLabel(role);
    final roleColor = _roleColor(role);
    final companyName = (m['company_name'] as String?) ?? '';
    // worker_id は verify-device 経路のみ含まれ得る（verify-pin 経路には無い）。
    // 存在し非空のときだけ表示する（決めつけて常時表示しない）。
    final workerId = m['worker_id'] as String?;
    final membershipId = m['membership_id'] as String?;
    final isThisSubmitting = _submittingId != null && _submittingId == membershipId;
    final anySubmitting = _submittingId != null;

    return Material(
      color: FieldTokens.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // タッチターゲット十分（カード全体・最小高72）。送信中は無効化。
        onTap: anySubmitting ? null : () => _select(m),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: roleColor, width: 1.5),
          ),
          child: Row(
            children: [
              // 役割バッジ
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  role == 'boss' ? Icons.engineering : Icons.construction,
                  color: roleColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      roleLabel,
                      style: TextStyle(
                        color: roleColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (companyName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        companyName,
                        style: const TextStyle(
                          color: FieldTokens.textBody,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (workerId != null && workerId.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        workerId,
                        style: const TextStyle(
                          color: FieldTokens.textSupport,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isThisSubmitting)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: FieldTokens.accent),
                )
              else
                const Icon(Icons.chevron_right, color: FieldTokens.textSupport),
            ],
          ),
        ),
      ),
    );
  }
}
