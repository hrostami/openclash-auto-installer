import os
import re
import time
from deep_translator import GoogleTranslator

CHINESE_PATTERN = re.compile(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+')
UPSTREAM_USER = 'slobys'
YOUR_USER = 'hrostami'
MAX_CHUNK_CHARS = 4500
SEPARATOR = '\n---\n'

def get_target_files():
    files = [f for f in os.listdir('.') if f.endswith('.sh')]
    if os.path.exists('README.md'):
        files.append('README.md')
    return files

def read_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        return f.readlines()

def write_file(filepath, lines):
    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)

def collect_segments(files_lines):
    segments = []
    for filepath, lines in files_lines.items():
        for line_idx, line in enumerate(lines):
            for m in CHINESE_PATTERN.finditer(line):
                segments.append({
                    'filepath': filepath,
                    'line_idx': line_idx,
                    'start': m.start(),
                    'end': m.end(),
                    'text': m.group(0),
                })
    return segments

def batch_segments(segments):
    batches = []
    current_batch = []
    current_len = 0
    for seg in segments:
        text_len = len(seg['text'])
        separator_len = len(SEPARATOR) if current_batch else 0
        if current_len + separator_len + text_len > MAX_CHUNK_CHARS and current_batch:
            batches.append(current_batch)
            current_batch = [seg]
            current_len = text_len
        else:
            current_batch.append(seg)
            current_len += separator_len + text_len
    if current_batch:
        batches.append(current_batch)
    return batches

def translate_batch(batch):
    combined = SEPARATOR.join(seg['text'] for seg in batch)
    try:
        translated = GoogleTranslator(source='zh-CN', target='en').translate(combined)
        parts = translated.split(SEPARATOR.strip())
        if len(parts) == len(batch):
            return [p.strip() for p in parts]
    except Exception as e:
        print(f"Batch translation failed: {e}, retrying individually...")
    results = []
    for seg in batch:
        try:
            results.append(GoogleTranslator(source='zh-CN', target='en').translate(seg['text']))
            time.sleep(0.3)
        except Exception:
            results.append(seg['text'])
    return results

def apply_translations(files_lines, segments, translations):
    replacements = {}
    for seg, translated in zip(segments, translations):
        key = (seg['filepath'], seg['line_idx'])
        if key not in replacements:
            replacements[key] = []
        replacements[key].append((seg['start'], seg['end'], translated))

    for (filepath, line_idx), repls in replacements.items():
        line = files_lines[filepath][line_idx]
        repls.sort(key=lambda x: x[0], reverse=True)
        for start, end, translated in repls:
            line = line[:start] + translated + line[end:]
        files_lines[filepath][line_idx] = line

def replace_username(files_lines):
    pattern = re.compile(re.escape(UPSTREAM_USER))
    for filepath, lines in files_lines.items():
        files_lines[filepath] = [pattern.sub(YOUR_USER, line) for line in lines]

target_files = get_target_files()
files_lines = {f: read_file(f) for f in target_files}

replace_username(files_lines)

segments = collect_segments(files_lines)
print(f"Found {len(segments)} Chinese segments across {len(target_files)} files")

batches = batch_segments(segments)
print(f"Translating in {len(batches)} batches...")

translations = []
for i, batch in enumerate(batches):
    print(f"Batch {i + 1}/{len(batches)} ({sum(len(s['text']) for s in batch)} chars)")
    results = translate_batch(batch)
    translations.extend(results)
    time.sleep(0.5)

apply_translations(files_lines, segments, translations)

for filepath, lines in files_lines.items():
    write_file(filepath, lines)

print("Done.")
