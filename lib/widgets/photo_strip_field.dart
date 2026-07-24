// lib/widgets/photo_strip_field.dart
// J's FIELD — 複数写真の横スクロール入力帯（制御コンポーネント）。
//
// ・状態は親が List<String>（ローカルパス）で保持し、onChanged で受け取る。
// ・撮影は ImageSource.camera 固定（証跡価値維持＝ギャラリー禁止）。
//   imageQuality:80 + maxWidth:1920 を必ず指定。
// ・種別ごと maxCount 枚（既定5）。到達で＋タイル非活性＋「上限n枚」表示。
// ・重要操作はラベル必須（＋タイルは「＋撮影」ラベル付き・アイコンのみ禁止）。
// ・配色は core/theme/js_colors.dart（Asphalt Dawn）準拠・直書きHEX禁止。
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/js_colors.dart';

class PhotoStripField extends StatelessWidget {
  const PhotoStripField({
    super.key,
    required this.label,
    required this.paths,
    required this.onChanged,
    this.note,
    this.maxCount = 5,
  });

  /// 種別ラベル（例: '作業写真' / '駐車場写真'）
  final String label;

  /// ラベル直下に出す補足（例: '※なくても報告できます'）。null なら非表示。
  final String? note;

  /// ローカルファイルパスの一覧（親が保持する制御状態）
  final List<String> paths;

  /// 追加・削除の結果を親へ返す
  final ValueChanged<List<String>> onChanged;

  /// 種別ごとの上限枚数（BE: PHOTO_LIMIT_EXCEEDED と一致）
  final int maxCount;

  static const double _thumb = 88; // サムネ 88×88（8ptグリッド整合）
  static const double _touch = 44; // 最小タッチターゲット
  static final ImagePicker _picker = ImagePicker();

  Future<void> _capture() async {
    if (paths.length >= maxCount) return;
    final f = await _picker.pickImage(
      source: ImageSource.camera, // カメラ固定（ギャラリー禁止）
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (f == null) return;
    onChanged(<String>[...paths, f.path]);
  }

  void _remove(int index) {
    final next = <String>[...paths]..removeAt(index);
    onChanged(next);
  }

  // 既存 main.dart _showPhoto と同方式（InteractiveViewer・ローカルFile表示）
  void _preview(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain)),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: JsColors.textWhite),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atLimit = paths.length >= maxCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダ: 種別ラベル + 枚数バッジ「n/5」（+ 上限表示）
        Padding(
          padding: EdgeInsets.only(bottom: note == null ? 8 : 2),
          child: Row(
            children: [
              Text(label,
                  style: const TextStyle(color: JsColors.textMid, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: JsColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: atLimit ? JsColors.accent : JsColors.border),
                ),
                child: Text('${paths.length}/$maxCount',
                    style: TextStyle(
                        color: atLimit ? JsColors.accent : JsColors.textMid,
                        fontSize: 11)),
              ),
              if (atLimit) ...[
                const SizedBox(width: 8),
                Text('上限$maxCount枚',
                    style: const TextStyle(color: JsColors.accent, fontSize: 11)),
              ],
            ],
          ),
        ),
        // ラベル直下の補足（note が null なら描画しない＝既存呼び出しは見た目不変）
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(note!,
                style: const TextStyle(
                    color: JsFormTokens.textMuted, fontSize: 11)),
          ),
        // 「＋撮影」を左端固定（スクロール外＝何枚撮っても絶対に隠れない）＋
        // サムネは横スクロール。表示は逆順（最新が左＝＋タイルの隣）だが paths の順序は不変。
        SizedBox(
          height: _thumb + 8, // サムネ88 + ✕オーバーハング用の上余白8（=96）
          child: Row(
            children: [
              _addTile(atLimit), // 固定・非スクロール
              const SizedBox(width: 8),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: paths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  // 表示のみ逆順: 表示i=0 が最新（paths.last）。実index を _thumbTile に渡すので
                  // ✕削除・タップ拡大は常に「表示中のその写真」に正しく対応する。
                  itemBuilder: (context, i) =>
                      _thumbTile(context, paths.length - 1 - i),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbTile(BuildContext context, int index) {
    return SizedBox(
      width: _thumb + 8,
      height: _thumb + 8,
      child: Stack(
        children: [
          // サムネ本体（タップで拡大）
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: GestureDetector(
              onTap: () => _preview(context, paths[index]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(paths[index]),
                  width: _thumb,
                  height: _thumb,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // ✕ 削除（送信前のローカル除去のみ・44ptタッチターゲット）
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _remove(index),
              child: SizedBox(
                width: _touch,
                height: _touch,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 16, color: JsColors.textWhite),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTile(bool atLimit) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Opacity(
        opacity: atLimit ? 0.4 : 1,
        child: GestureDetector(
          onTap: atLimit ? null : _capture,
          child: Container(
            width: _thumb,
            height: _thumb,
            decoration: BoxDecoration(
              color: JsColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JsColors.border),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, color: JsColors.accent, size: 22),
                SizedBox(height: 4),
                Text('＋撮影',
                    style: TextStyle(color: JsColors.accent, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
