// lib/screens/privacy_consent_screen.dart - 初回プライバシー同意画面
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors;

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key, required this.onAgreed});
  final VoidCallback onAgreed;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _agreed = false;

  Future<void> _agree() async {
    if (!_agreed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'privacy_agreed_at', DateTime.now().toIso8601String());
    widget.onAgreed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text("J's Inc.",
                  style: TextStyle(
                      color: JsColors.gold,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('プライバシーポリシーと利用規約',
                  style: TextStyle(color: JsColors.silver, fontSize: 14)),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: JsColors.gunmetal,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: JsColors.divider),
                  ),
                  child: const SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Section(
                          icon: Icons.location_on,
                          title: '位置情報（GPS）の収集',
                          body:
                              '本アプリは現場の位置情報を日報に記録するため、GPS情報を収集します。'
                              '収集した位置情報は株式会社J\'sの業務管理目的のみに使用し、第三者へ提供しません。',
                        ),
                        _Section(
                          icon: Icons.camera_alt,
                          title: 'カメラ・写真へのアクセス',
                          body:
                              '領収書・作業現場の写真を日報に添付するため、カメラおよびフォトライブラリにアクセスします。',
                        ),
                        _Section(
                          icon: Icons.mic,
                          title: 'マイクへのアクセス',
                          body:
                              '作業内容を音声入力するため、マイクへのアクセスを必要とします。',
                        ),
                        _Section(
                          icon: Icons.person,
                          title: '個人情報の取り扱い',
                          body:
                              '氏名・勤務記録・GPS情報は労働基準法に基づき3年間保存されます。'
                              '退職後はアカウントが無効化され、個人情報へのアクセスができなくなります。',
                        ),
                        _Section(
                          icon: Icons.security,
                          title: 'セキュリティ',
                          body:
                              'PIN認証・生体認証により本人確認を行います。'
                              '日報データには改ざん検知のためのハッシュ値が付与されます（電子帳簿対応）。',
                        ),
                        _Section(
                          icon: Icons.gavel,
                          title: '利用規約',
                          body:
                              '本アプリは株式会社J\'sの従業員専用の業務アプリです。'
                              '業務外の目的での使用を禁止します。'
                              '不正アクセス・データの改ざんは厳罰の対象となります。',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(children: [
                  Checkbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                    activeColor: JsColors.gold,
                    checkColor: Colors.black,
                    side: const BorderSide(color: JsColors.silver),
                  ),
                  const Expanded(
                    child: Text(
                      'プライバシーポリシーと利用規約を読み、内容に同意します',
                      style: TextStyle(color: JsColors.offWhite, fontSize: 13),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _agreed ? _agree : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _agreed ? JsColors.gold : JsColors.gunmetal,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: JsColors.gunmetal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    '同意してはじめる',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _agreed ? Colors.black : JsColors.silver),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: JsColors.gunmetal,
                        title: const Text('アプリを終了します',
                            style: TextStyle(color: JsColors.error)),
                        content: const Text(
                            '同意しない場合、本アプリを使用できません。\nアプリを終了しますか？',
                            style: TextStyle(color: JsColors.offWhite)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('戻る',
                                style: TextStyle(color: JsColors.silver)),
                          ),
                          TextButton(
                            onPressed: () {
                              // プラットフォーム終了
                              Navigator.pop(context);
                            },
                            child: const Text('終了',
                                style: TextStyle(color: JsColors.error)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('同意しない',
                      style: TextStyle(color: JsColors.silver, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: JsColors.gold, size: 16),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                color: JsColors.gold,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ]),
      const SizedBox(height: 4),
      Text(body,
          style: const TextStyle(
              color: JsColors.offWhite, fontSize: 12, height: 1.5)),
      const Divider(color: JsColors.divider, height: 16),
    ]),
  );
}
