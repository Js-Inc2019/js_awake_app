// lib/screens/consent_screen.dart
import 'package:flutter/material.dart';
import '../main.dart' show JsColors;

class ConsentScreen extends StatefulWidget {
  final VoidCallback onAgreed;
  const ConsentScreen({super.key, required this.onAgreed});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  int _currentPage = 0;
  bool _agreed = false;
  late final PageController _pageController;

  final List<String> _titles = [
    '個人情報の取り扱い',
    '生体認証の利用',
    '位置情報の利用',
    '利用規約',
  ];

  final List<String> _details = [
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
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _details.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _details.length - 1;
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: const Text('利用規約・同意確認'),
        backgroundColor: JsColors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ページインジケーター
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_details.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _currentPage ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _currentPage ? JsColors.gold : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // タイトル
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                '${_currentPage + 1} / ${_details.length}　${_titles[_currentPage]}',
                style: const TextStyle(
                  color: JsColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 本文
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() {
                  _currentPage = i;
                  if (!isLast) _agreed = false;
                }),
                itemCount: _details.length,
                itemBuilder: (_, i) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      _details[i],
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 最終ページのみ同意チェックボックス
            if (isLast)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _agreed = !_agreed),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _agreed ? JsColors.gold : Colors.transparent,
                          border: Border.all(
                            color: _agreed ? JsColors.gold : Colors.white38,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _agreed
                            ? const Icon(Icons.check, size: 16, color: Colors.black)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '上記すべての内容を確認し、同意します',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // ナビゲーションボタン
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _prevPage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JsColors.silver,
                          side: const BorderSide(color: Colors.white24),
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('戻る'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isLast
                          ? (_agreed ? () {
                              widget.onAgreed();
                              Navigator.of(context).pop();
                            } : null)
                          : _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isLast && !_agreed ? Colors.white12 : JsColors.gold,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(0, 48),
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white38,
                      ),
                      child: Text(
                        isLast ? '同意して続ける' : '次へ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
