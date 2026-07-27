// lib/screens/consent_view_screen.dart - 同意内容閲覧専用画面
import 'package:flutter/material.dart';
import '../core/theme/js_colors.dart';

class ConsentViewScreen extends StatelessWidget {
  const ConsentViewScreen({super.key});

  static const List<String> _titles = [
    '個人情報の取り扱い',
    '生体認証の利用',
    '位置情報の利用',
    '利用規約',
  ];

  static const List<String> _details = [
    '当社は、以下の個人情報を取得します。\n\n'
    '【取得する情報】\n'
    '・氏名、電話番号、緊急連絡先\n'
    '・GPS位置情報（現場住所・移動経路）\n'
    '・労働時間（出勤・退勤・残業時間）\n'
    '・健康情報（血液型・健康診断日）\n\n'
    '【利用目的】\n'
    '・勤怠管理および給与計算\n'
    '・現場安全管理\n'
    '・交通費精算\n\n'
    '【第三者提供】\n'
    '法令に基づく場合を除き、'
    '第三者への提供は行いません。',

    '本人確認のため、以下の生体認証を使用します。\n\n'
    '・指紋認証\n'
    '・顔認証\n\n'
    '【重要事項】\n'
    '生体情報はお使いのデバイス内にのみ保存され、'
    '当社サーバーへの送信は一切行いません。\n\n'
    '生体認証が使用できない場合は、'
    '代替手段（PINコード）でのご利用が可能です。',

    'アプリの利用中、以下の目的でGPS位置情報を取得します。\n\n'
    '【取得目的】\n'
    '・現場への移動距離の計測\n'
    '・交通費の自動計算\n'
    '・現場住所の自動入力補完\n\n'
    '【取得タイミング】\n'
    '・アプリ起動時\n'
    '・日報入力時\n\n'
    '位置情報は勤怠管理目的にのみ使用し、'
    'マーケティング等への利用は行いません。',

    '【禁止事項】\n'
    '・虚偽の情報による登録\n'
    '・他者へのアカウント譲渡・貸与\n'
    '・システムへの不正アクセス\n'
    '・業務目的以外での位置情報の使用\n\n'
    '【免責事項】\n'
    'ネットワーク障害等による'
    'サービス中断については責任を負いかねます。\n\n'
    '【準拠法】\n'
    '本規約は日本法に準拠します。\n'
    '紛争は神戸地方裁判所を第一審とします。',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: const Text('同意内容の確認'),
        backgroundColor: JsColors.black,
        foregroundColor: JsColors.textStrong,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: JsColors.gold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _titles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => Container(
          decoration: BoxDecoration(
            color: JsColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JsColors.border),
          ),
          child: ExpansionTile(
            initiallyExpanded: i == 0,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: JsColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: JsColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              _titles[i],
              style: const TextStyle(
                color: JsColors.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            iconColor: JsColors.gold,
            collapsedIconColor: JsColors.textMid,
            children: [
              Text(
                _details[i],
                style: const TextStyle(
                  color: JsColors.textMid,
                  fontSize: 13,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
