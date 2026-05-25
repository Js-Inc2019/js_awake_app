content = open('lib/main.dart', 'r', encoding='utf-8').read()
# actionsの箇所を確認
idx = content.find('actions: widget.isBossMode')
print('found at:', idx)
if idx >= 0:
    print(repr(content[idx:idx+100]))
else:
    # 別の書き方か確認
    idx2 = content.find('actions:')
    print('actions found at:', idx2)
    print(repr(content[idx2:idx2+200]))
