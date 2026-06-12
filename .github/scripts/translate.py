import os
import re
import time
from deep_translator import GoogleTranslator

SHELL_FILES = [f for f in os.listdir('.') if f.endswith('.sh')]
CHINESE_PATTERN = re.compile(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+')

def has_chinese(text):
    return bool(CHINESE_PATTERN.search(text))

def translate_line(line):
    def replace_match(m):
        try:
            return GoogleTranslator(source='zh-CN', target='en').translate(m.group(0))
        except Exception:
            return m.group(0)
    return CHINESE_PATTERN.sub(replace_match, line)

def translate_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    chinese_indices = [i for i, line in enumerate(lines) if has_chinese(line)]
    if not chinese_indices:
        return

    print(f"Translating {filepath}: {len(chinese_indices)} lines")

    new_lines = list(lines)
    for i in chinese_indices:
        new_lines[i] = translate_line(lines[i])
        time.sleep(0.3)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

for sh_file in SHELL_FILES:
    translate_file(sh_file)

print("Done.")
