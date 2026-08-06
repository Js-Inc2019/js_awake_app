// lib/screens/privacy_policy_screen.dart
import 'package:flutter/material.dart';
 import '../core/theme/field_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  String? _consentDate;

  @override
  void initState() {
    super.initState();
    _loadConsentDate();
  }

  Future<void> _loadConsentDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('consent_agreed_at') ?? '';
    if (raw.isEmpty) return;
    try {
      final dt = DateTime.parse(raw).toLocal();
      final formatted =
          '${dt.year}年${dt.month.toString().padLeft(2, '0')}月'
          '${dt.day.toString().padLeft(2, '0')}日 '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
      if (mounted) setState(() => _consentDate = formatted);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.textBody,
        title: const Text('プライバシーポリシー',
            style: TextStyle(
                color: FieldTokens.textBody,
                fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18,
              color: FieldTokens.accent),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_consentDate != null) ...[
              _consentBanner(_consentDate!),
              const SizedBox(height: 20),
            ],
            _buildTitle(),
            const SizedBox(height: 20),
            _buildBody(),
            const SizedBox(height: 32),
            Center(
              child: Text(
                "株式会社J's",
                style: TextStyle(
                    color: FieldTokens.textBody.withValues(alpha: 0.3),
                    fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _consentBanner(String date) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: FieldTokens.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: FieldTokens.accent.withValues(alpha: 0.4)),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle_outline,
          color: FieldTokens.accent, size: 16),
      const SizedBox(width: 8),
      Text('同意日時：$date',
          style: const TextStyle(
              color: FieldTokens.accent,
              fontSize: 12,
              fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildTitle() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('プライバシーポリシー',
          style: TextStyle(
              color: FieldTokens.accent,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5)),
      const SizedBox(height: 6),
      Text('制定日：2024年　最終改定日：2025年',
          style: TextStyle(
              color: FieldTokens.textBody.withValues(alpha: 0.4),
              fontSize: 11)),
      const SizedBox(height: 14),
      const Text(
        "株式会社J'sは、個人情報保護法およびその他関連法令を遵守し、\n以下のとおり個人情報を適切に取り扱います。",
        style: TextStyle(
            color: FieldTokens.textSupport, fontSize: 13, height: 1.8),
      ),
    ],
  );

  Widget _buildBody() => Column(
    children: [
      _section('1. 事業者情報', null, [
        "・会社名：株式会社J's",
        '・所在地：兵庫県神戸市長田区',
        '・お問い合わせ：info@j-denki.com',
      ]),
      _section('2. 取得する個人情報の種類', null, [
        '・氏名・所属会社・連絡先（電話番号・メールアドレス）',
        '・生体認証情報（指紋・顔認証データ）※個人識別符号に該当',
        '・GPS位置情報（現場住所の自動取得時）',
        '・作業記録・日報データ・勤怠情報',
      ]),
      _section('3. 利用目的', null, [
        '・業務管理アプリのサービス提供',
        '・本人認証（生体認証情報は本人確認の目的のみに使用）',
        '・現場住所の自動入力（GPS位置情報は打刻時・日報作成時・アプリ起動時に取得）',
        '・勤怠管理・作業記録の管理および集計',
        '・サービスの改善および新機能開発',
      ]),
      _section('4. 生体認証情報の取り扱い（特則）', null, [
        '・生体認証データは端末内でのみ処理し、サーバーへは送信しません',
        '・利用目的は本人認証に限定し、他の目的には一切使用しません',
        '・サービス解約または本人要請時に速やかに削除します',
        '・取得にあたっては事前に本人の明示的同意を取得します',
      ]),
      _section('5. GPS位置情報の取り扱い（特則）', null, [
        '・取得タイミング：日報送信時のみ（常時追跡は行いません）',
        '・利用目的：現場住所の自動入力のみ',
        '・位置情報の取得はアプリ内で許可・拒否を設定できます',
        '・保存期間：最大3年',
      ]),
      _section('6. 第三者提供（協力会社間データ共有）', null, [
        '・共有される情報：作業記録・日報データ・勤怠情報',
        '・共有先：利用契約を締結した元請け企業（読み取り専用）',
        '・共有目的：工事進捗管理および安全管理',
        '・本人は利用開始時の同意画面にて確認の上、同意いただきます',
      ]),
      _section('7. 安全管理措置', null, [
        '・通信の暗号化（SSL/TLS）',
        '・アクセス権限の管理（役割別アクセス制御）',
        '・定期的なセキュリティ診断の実施',
        '・従業員への個人情報保護教育の実施',
      ]),
      _section('8. 保存期間', null, [
        '・作業記録・日報データ：契約終了後3年以内に削除',
        '・生体認証情報：サービス解約または本人要請時に即時削除',
      ]),
      _section(
        '9. 本人からの請求への対応',
        '保有する個人情報について、開示・訂正・利用停止・削除の請求に対応します。',
        ['お問い合わせ：info@j-denki.com'],
      ),
      _section(
        '10. 改定について',
        '本ポリシーは法令の改正またはサービスの変更に伴い、\n予告なく改定する場合があります。',
        [],
      ),
    ],
  );

  Widget _section(String title, String? prose, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: FieldTokens.accent.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(
                  bottom: BorderSide(
                      color: FieldTokens.accent.withValues(alpha: 0.2))),
            ),
            child: Text(title,
                style: const TextStyle(
                    color: FieldTokens.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prose != null) ...[
                  Text(prose,
                      style: const TextStyle(
                          color: FieldTokens.textSupport,
                          fontSize: 12,
                          height: 1.7)),
                  if (items.isNotEmpty) const SizedBox(height: 8),
                ],
                ...items.map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(line,
                          style: const TextStyle(
                              color: FieldTokens.textBody,
                              fontSize: 12,
                              height: 1.7)),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
