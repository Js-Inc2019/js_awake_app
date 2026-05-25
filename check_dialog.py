with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# _OvertimeDialogのpopをtrueに変更
old = "    if (mounted) Navigator.pop(context, {"
new = "    if (mounted) Navigator.pop(context, true); // bool\n    // {"

# submitの最後をtrueで閉じる
idx = content.find("if (mounted) Navigator.pop(context, {")
print("found:", idx)
if idx >= 0:
    print(repr(content[idx:idx+200]))
