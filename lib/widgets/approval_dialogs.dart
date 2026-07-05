// lib/widgets/approval_dialogs.dart - 承認/差戻しダイアログ 共通部品
// OFFICE(pending_reports_screen.dart)から移植。値を Navigator.pop で返す純UI部品。
import 'package:flutter/material.dart';
import '../main.dart' show JsColors;

class RevisionReasonDialog extends StatefulWidget {
  const RevisionReasonDialog({super.key, this.transportTypes});
  final List<dynamic>? transportTypes;
  @override
  State<RevisionReasonDialog> createState() => _RevisionReasonDialogState();
}

class _RevisionReasonDialogState extends State<RevisionReasonDialog> {
  // 基本3タグは常時表示。駐車系2タグは移動手段に car が含まれる場合のみ。
  // transport_types_json が取得不能/null のときは安全側で全5タグ表示。
  List<Map<String, String>> get _visibleTags {
    const base = <Map<String, String>>[
      {'key': 'work_content', 'label': '作業内容'},
      {'key': 'site_photo', 'label': '作業写真'},
      {'key': 'transport', 'label': '移動手段'},
    ];
    const parking = <Map<String, String>>[
      {'key': 'parking_fee', 'label': '駐車料金'},
      {'key': 'parking_photo', 'label': '駐車場写真'},
    ];
    final tt = widget.transportTypes;
    final showParking = tt == null || tt.contains('car'); // null/取得不能→安全側で表示
    return showParking ? [...base, ...parking] : base;
  }
  final Set<String> _selected = {}; // 送信値は英語キー（BE ALLOWED_REVISION_TARGETS）
  final _commentCtrl = TextEditingController();

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: JsColors.gunmetal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('修正依頼', style: TextStyle(color: Colors.white, fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('修正理由（複数選択可）', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _visibleTags.map((tag) {
              final key = tag['key']!;
              final label = tag['label']!;
              final sel = _selected.contains(key);
              return GestureDetector(
                onTap: () => setState(() {
                  if (sel) { _selected.remove(key); } else { _selected.add(key); }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? JsColors.warning.withValues(alpha: 0.2) : JsColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? JsColors.warning : JsColors.divider,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(label, style: TextStyle(
                    color: sel ? JsColors.warning : JsColors.offWhite,
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text('コメント（任意）', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            style: const TextStyle(color: JsColors.offWhite),
            decoration: InputDecoration(
              hintText: '任意：直し方の補足や、他に気づいた点があれば記入',
              hintStyle: const TextStyle(color: JsColors.silver),
              filled: true,
              fillColor: JsColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: JsColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: JsColors.divider),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
        ),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, {
                  'reasons': _selected.toList(),
                  'comment': _commentCtrl.text.trim().isNotEmpty ? _commentCtrl.text.trim() : null,
                }),
          style: ElevatedButton.styleFrom(
            backgroundColor: JsColors.warning,
            foregroundColor: const Color(0xFF3D1E00),
          ),
          child: const Text('送信'),
        ),
      ],
    );
  }
}

// ─── 起点確認ダイアログ ───────────────────────────────────────
class OriginConfirmDialog extends StatefulWidget {
  const OriginConfirmDialog({super.key, required this.initialOrigin, required this.onChanged});
  final String initialOrigin;
  final ValueChanged<String> onChanged;
  @override
  State<OriginConfirmDialog> createState() => _OriginConfirmDialogState();
}

class _OriginConfirmDialogState extends State<OriginConfirmDialog> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialOrigin;
  }

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      backgroundColor: JsColors.gunmetal,
      title: Text('起点の確認', style: TextStyle(color: pc)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('この日報の起点を確認・変更してください',
            style: TextStyle(color: JsColors.silver, fontSize: 13)),
        const SizedBox(height: 16),
        _OriginTile(
          label: '自宅',
          icon: Icons.home,
          value: 'home',
          selected: _selected == 'home',
          onTap: () {
            setState(() => _selected = 'home');
            widget.onChanged('home');
          },
        ),
        const SizedBox(height: 8),
        _OriginTile(
          label: '会社',
          icon: Icons.business,
          value: 'office',
          selected: _selected == 'office',
          onTap: () {
            setState(() => _selected = 'office');
            widget.onChanged('office');
          },
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: pc,
            foregroundColor: pc.computeLuminance() > 0.4 ? Colors.black : Colors.white,
            minimumSize: const Size(80, 36),
          ),
          child: const Text('承認する'),
        ),
      ],
    );
  }
}

class _OriginTile extends StatelessWidget {
  const _OriginTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String label, value;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? pc.withValues(alpha: 0.15) : JsColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? pc : JsColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? pc : JsColors.silver, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
            color: selected ? pc : JsColors.offWhite,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          )),
          const Spacer(),
          if (selected) Icon(Icons.check_circle, color: pc, size: 18),
        ]),
      ),
    );
  }
}
