#!/usr/bin/env python3
"""Splits a large State class into `part` files.

Usage:
  split_state.py list FILE CLASS
  split_state.py split FILE CLASS GROUPS.json

GROUPS.json: [{"part": "x_part.dart", "extension": "_Foo",
               "from": "firstMemberName", "to": "lastMemberName"}, ...]
Members between `from` and `to` (inclusive, source order) move into an
extension on CLASS. Members annotated with @override stay in the class.
"""
import json
import re
import sys


def parse_members(lines, class_name):
    start = next(
        i for i, l in enumerate(lines) if re.match(rf'class {class_name}\b', l)
    )
    # class body ends at the first line that is exactly "}" after start
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == '}')
    members = []
    i = start + 1
    while i < end:
        line = lines[i]
        if line.strip() == '' or not line.startswith('  ') or line.startswith('   '):
            i += 1
            continue
        # member start: include preceding doc comments / annotations
        m_start = i
        while m_start - 1 > start and (
            lines[m_start - 1].startswith('  ///')
            or lines[m_start - 1].startswith('  @')
            or lines[m_start - 1].startswith('  //')
        ):
            m_start -= 1
        # find member end: matching braces / semicolon at depth 0
        depth = 0
        j = i
        seen_body = False
        while j < end:
            for ch in lines[j]:
                if ch in '({[':
                    depth += 1
                elif ch in ')}]':
                    depth -= 1
            if depth == 0 and (
                lines[j].rstrip().endswith(';') or lines[j].rstrip().endswith('}')
            ):
                break
            j += 1
        text = '\n'.join(lines[m_start : j + 1])
        header = '\n'.join(lines[m_start : i + 1])
        name_match = re.search(r'([A-Za-z_][A-Za-z0-9_]*)\s*(\(|=|;|\{|=>)', lines[i])
        # prefer identifier before "(" for methods / getters
        nm = re.search(r'\b(?:get\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|=>|\{)', lines[i])
        name = nm.group(1) if nm else (name_match.group(1) if name_match else '?')
        if re.search(r'\bget\s+([A-Za-z_]\w*)', lines[i]):
            name = re.search(r'\bget\s+([A-Za-z_]\w*)', lines[i]).group(1)
        members.append(
            {
                'name': name,
                'start': m_start,
                'end': j,
                'override': '@override' in header,
                'is_field': not re.search(r'\)\s*(async\s*)?(\{|=>)|\)\s*\{', text.split('\n')[i - m_start] if False else lines[i]) and '(' not in lines[i].split('=')[0],
                'text': text,
            }
        )
        i = j + 1
    return start, end, members


def main():
    mode, path, cls = sys.argv[1:4]
    lines = open(path).read().split('\n')
    start, end, members = parse_members(lines, cls)
    if mode == 'list':
        for idx, m in enumerate(members):
            flag = 'OVR' if m['override'] else ('FLD' if m['is_field'] else '   ')
            print(f"{idx:3d} {flag} {m['start']+1:5d}-{m['end']+1:5d} {m['name']}")
        return
    groups = json.load(open(sys.argv[4]))
    names = [m['name'] for m in members]
    moved = set()
    parts = []
    lib = path.split('/')[-1]
    for g in groups:
        a = names.index(g['from'])
        b = len(names) - 1 - names[::-1].index(g['to'])
        chunk = [
            m
            for m in members[a : b + 1]
            if not m['override'] and not m['is_field']
        ]
        for m in chunk:
            moved.add(m['start'])
        body = '\n\n'.join(m['text'] for m in chunk)
        existing = next((x for x in parts if x[0] == g['part']), None)
        if existing:
            parts.remove(existing)
            body = existing[2] + '\n\n' + body
        parts.append((g['part'], g['extension'], body))
    out = []
    i = 0
    skip_ranges = [(m['start'], m['end']) for m in members if m['start'] in moved]
    while i < len(lines):
        r = next((r for r in skip_ranges if r[0] == i), None)
        if r:
            i = r[1] + 1
            # swallow one following blank line
            if i < len(lines) and lines[i].strip() == '':
                i += 1
            continue
        out.append(lines[i])
        i += 1
    text = '\n'.join(out)
    # add part directives after the last import
    imp_lines = [k for k, l in enumerate(text.split('\n')) if l.startswith('import ')]
    tl = text.split('\n')
    insert_at = imp_lines[-1] + 1
    directives = [''] + [f"part '{p[0]}';" for p in parts]
    tl[insert_at:insert_at] = directives
    open(path, 'w').write('\n'.join(tl))
    base = '/'.join(path.split('/')[:-1])
    for p, ext, body in parts:
        content = (
            f"part of '{lib}';\n\n"
            "// ignore_for_file: invalid_use_of_protected_member\n\n"
            f"extension {ext} on {cls} {{\n{body}\n}}\n"
        )
        open(f'{base}/{p}', 'w').write(content)
    print('moved', len(moved), 'members into', len(parts), 'parts')


main()
