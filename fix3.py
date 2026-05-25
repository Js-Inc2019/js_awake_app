lines = open('lib/main.dart', 'r', encoding='utf-8').readlines()

# 1847-1861行を正しいコードに置き換え
correct = [
    "                  label: const Text('\u5171\u6709\u3059\u308b'),\n",
    "                ),\n",
    "              ),\n",
    "            ),\n",
    "          ],\n",
    "        ),\n",
    "      ),\n",
    "    );\n",
    "  }\n",
    "\n",
]

lines[1847:1862] = correct

open('lib/main.dart', 'w', encoding='utf-8').writelines(lines)
print('OK lines:', len(lines))
