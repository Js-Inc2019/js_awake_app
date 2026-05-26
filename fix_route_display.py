with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """        if (sections.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...sections.map((s) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('  ${s.from} \u2192 [${s.line}] \u2192 ${s.to}',
                style: const TextStyle(color: JsColors.silver, fontSize: 11)),
          )),
        ],"""

new = """        if (sections.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...sections.map((s) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Expanded(
                child: Text('${s.from} \u2192 ${s.to}',
                    style: const TextStyle(color: JsColors.offWhite, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(s.line,
                  style: const TextStyle(color: JsColors.silver, fontSize: 11)),
            ]),
          )),
        ],"""

if old in content:
    content = content.replace(old, new)
    print('OK')
else:
    print('not found')
    idx = content.find('sections.isNotEmpty')
    print(repr(content[idx-20:idx+200]))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
