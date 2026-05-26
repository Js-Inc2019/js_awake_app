with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# Snackbarをもっと大きく
old = """      content: Text(msg, style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      duration: const Duration(seconds: 3),"""

new = """      content: Text(msg, style: const TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      duration: const Duration(seconds: 3),"""

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('snackbar OK')
