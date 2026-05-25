lines = open('lib/main.dart', 'r', encoding='utf-8').readlines()

lines[1848] = '                ),\n'
lines[1849] = '              ),\n'
lines[1850] = '            ),\n'
lines[1951] = '              ),\n'
lines[1952] = '            ),\n'

open('lib/main.dart', 'w', encoding='utf-8').writelines(lines)
print('OK')
