with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# SharedWorkerFormのbuildをPopScopeでラップ
old = """      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),"""

new = """      body: PopScope(
        canPop: false,
        child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),"""

content = content.replace(old, new)

# 閉じ括弧を追加
old2 = """            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// サブウィジェット"""

new2 = """            ],
          ),
        ),
      ),
        ),
    );
  }
}

// ============================================================
// サブウィジェット"""

content = content.replace(old2, new2)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
