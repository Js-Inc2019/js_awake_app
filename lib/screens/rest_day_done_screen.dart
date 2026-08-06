// ============================================================
// lib/screens/rest_day_done_screen.dart - 本日休み（ねぎらい画面）
// 色は必ず field_tokens.dart のトークンを使う。Color(0x 直書き・Colors.* は使わない。
// ★イラスト画像は未存在。Image.asset の errorBuilder でフォールバック表示を必ず出す。
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import 'rest_day_screen.dart';

class RestDayDoneScreen extends StatefulWidget {
  const RestDayDoneScreen({super.key, this.reason, this.portion = 'full'});

  final String? reason; // paid_leave / absence / company_closed / personal / null
  final String portion; // full / am_half / pm_half

  @override
  State<RestDayDoneScreen> createState() => _RestDayDoneScreenState();
}

class _RestDayDoneScreenState extends State<RestDayDoneScreen> {
  late final String _cat;   // yasumi / yukyu / kyugyo
  late final int _n;        // 1..5（表示時ランダム）

  @override
  void initState() {
    super.initState();
    _cat = _categoryOf(widget.reason);
    _n = Random().nextInt(5) + 1; // 1..5
  }

  // reason → イラスト/文言カテゴリ。
  //   yukyu = paid_leave / kyugyo = company_closed / yasumi = absence・personal・null
  static String _categoryOf(String? reason) {
    switch (reason) {
      case 'paid_leave':
        return 'yukyu';
      case 'company_closed':
        return 'kyugyo';
      default:
        return 'yasumi';
    }
  }

  String get _message {
    // 半休は「働く日」なので portion 優先で分岐（full のみ従来のカテゴリ別文言）。
    switch (widget.portion) {
      case 'am_half':
        return '午後からもよろしくお願いします';
      case 'pm_half':
        return '午前おつかれさまでした';
    }
    switch (_cat) {
      case 'yukyu':
        return 'よい休日をお過ごしください';
      case 'kyugyo':
        return '本日は休業日です。おつかれさまです';
      default:
        return 'ゆっくり休んでください';
    }
  }

  @override
  Widget build(BuildContext context) {
    final imgSize = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.surfaceCard,
        foregroundColor: FieldTokens.textBody,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('本日休み'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              const Spacer(),

              // イラスト枠（画面幅の約70%・中央）。画像未存在時は errorBuilder で
              // Icons.self_improvement（accentDeep・大）にフォールバック。
              SizedBox(
                width: imgSize,
                height: imgSize,
                child: Image.asset(
                  'assets/rest/rest_${_cat}_$_n.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      Icons.self_improvement,
                      size: imgSize * 0.6,
                      color: FieldTokens.accentDeep,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ねぎらい文言（カテゴリ別・textBody・中央）
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),

              const Spacer(),

              // 取消・修正（修正モードで rest_day_screen を開く）
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RestDayScreen(
                        editMode: true,
                        initialReason: widget.reason,
                        initialPortion: widget.portion,
                      ),
                    ),
                  );
                },
                child: const Text('取消・修正',
                    style: TextStyle(color: FieldTokens.textSupport)),
              ),

              const SizedBox(height: 8),

              // ホームへ（スタックを畳んで最初のルートへ）
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FieldTokens.textSupport,
                    side: const BorderSide(color: FieldTokens.textSupport),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('ホームへ',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
