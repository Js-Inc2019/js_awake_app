// lib/screens/onboarding_screen.dart - 初回起動 2択画面
import 'package:flutter/material.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              // ロゴ
              const Text(
                "J's Inc.",
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '勤務管理システム',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 2,
                color: const Color(0xFFD4AF37),
              ),
              const Spacer(),
              // 招待コードで登録
              _OptionCard(
                icon: Icons.vpn_key_rounded,
                title: '招待コードで登録',
                subtitle: '管理者から招待コードを受け取った方\n（機種変更・初回登録）',
                isPrimary: true,
                onTap: () => Navigator.of(context).pushNamed('/invite-activate'),
              ),
              const SizedBox(height: 16),
              // 新規登録
              _OptionCard(
                icon: Icons.person_add_alt_1_rounded,
                title: '新規登録',
                subtitle: '会社名・名前・PINを設定して\nすぐに使い始める',
                isPrimary: false,
                onTap: () => Navigator.of(context).pushNamed('/register'),
              ),
              const Spacer(),
              const Text(
                'ご不明な点は管理者にお問い合わせください',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isPrimary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: isPrimary ? gold : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gold, width: isPrimary ? 0 : 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isPrimary
                    ? Colors.black.withValues(alpha: 0.15)
                    : gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isPrimary ? Colors.black : gold,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isPrimary ? Colors.black : gold,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isPrimary
                          ? Colors.black.withValues(alpha: 0.6)
                          : const Color(0xFF9E9E9E),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: isPrimary ? Colors.black54 : const Color(0xFF555555),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
