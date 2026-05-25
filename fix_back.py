with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """      if (result != null && mounted) {
        final action = result['action'] as String?;
        if (action == 'move') {
          final newAddr = result['newAddress'] as String? ?? '';
          setState(() => _gpsAddress = newAddr);
        }
      }
    }
  }"""

new = """      if (result != null && mounted) {
        final action = result['action'] as String?;
        if (action == 'move') {
          final newAddr = result['newAddress'] as String? ?? '';
          setState(() => _gpsAddress = newAddr);
          // 現場移動時は再度報告できるようにsubmittingリセット
          await _fetchGps();
        }
      }
      // 戻るボタン押した時もsubmittingリセット
      if (mounted) setState(() => _submitting = false);
    }
  }"""

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
