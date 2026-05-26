with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """      return result;
    } catch (e) {
      debugPrint('生体認証エラー: $e');
      return false; // キャンセル・エラー時はログイン不可
    }"""

new = """      return result;
    } catch (e) {
      debugPrint('生体認証エラー: $e');
      return true; // エラー時はスキップして続行
    }"""

content = content.replace(old, new)
with open('lib/screens/login_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
