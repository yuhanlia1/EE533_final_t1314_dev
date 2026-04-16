#!/usr/bin/env python3
import re
import argparse

def replace_instructions(line):
    # 替换 ldmia lr!, {r0, r1, r2, r3 }
    pattern_ldmia_lr = re.compile(r'^\s*ldmia\s+lr!,\s*\{r0,\s*r1,\s*r2,\s*r3\}')
    if pattern_ldmia_lr.search(line):
        indent = re.match(r'^(\s*)', line).group(1)
        replacement = (
            f"{indent}ldr r0, [lr]\n"
            f"{indent}add lr, lr, #4\n"
            f"{indent}ldr r1, [lr]\n"
            f"{indent}add lr, lr, #4\n"
            f"{indent}ldr r2, [lr]\n"
            f"{indent}add lr, lr, #4\n"
            f"{indent}ldr r3, [lr]\n"
            f"{indent}add lr, lr, #4\n"
        )
        return replacement

    # 替换 stmia ip!, {r0, r1, r2, r3 }
    pattern_stmia_ip = re.compile(r'^\s*stmia\s+ip!,\s*\{r0,\s*r1,\s*r2,\s*r3\}')
    if pattern_stmia_ip.search(line):
        indent = re.match(r'^(\s*)', line).group(1)
        replacement = (
            f"{indent}str r0, [ip]\n"
            f"{indent}add ip, ip, #4\n"
            f"{indent}str r1, [ip]\n"
            f"{indent}add ip, ip, #4\n"
            f"{indent}str r2, [ip]\n"
            f"{indent}add ip, ip, #4\n"
            f"{indent}str r3, [ip]\n"
            f"{indent}add ip, ip, #4\n"
        )
        return replacement

    # 替换 ldm lr, {r0, r1 }（无叹号，不更新基址）
    pattern_ldm_lr = re.compile(r'^\s*ldm\s+lr,\s*\{r0,\s*r1\}')
    if pattern_ldm_lr.search(line):
        indent = re.match(r'^(\s*)', line).group(1)
        replacement = (
            f"{indent}ldr r0, [lr]\n"
            f"{indent}ldr r1, [lr, #4]\n"
        )
        return replacement

    # 替换 stm ip, {r0, r1 }（无叹号，不更新基址）
    pattern_stm_ip = re.compile(r'^\s*stm\s+ip,\s*\{r0,\s*r1\}')
    if pattern_stm_ip.search(line):
        indent = re.match(r'^(\s*)', line).group(1)
        replacement = (
            f"{indent}str r0, [ip]\n"
            f"{indent}str r1, [ip, #4]\n"
        )
        return replacement

    # 替换任意寄存器的 ldr 指令
    # 匹配形如 "ldr <alias>, <mark>" 的行，其中 <mark> 不能以 '[' 开头（避免匹配内存寻址形式）
    pattern_ldr_mark = re.compile(r'^\s*ldr\s+([a-zA-Z0-9_]+),\s+([^[]\S*)')
    match = pattern_ldr_mark.search(line)
    if match:
        indent = re.match(r'^(\s*)', line).group(1)
        reg = match.group(1)
        replacement = f"{indent}mov {reg}, #128\n"
        return replacement

    # 如果不匹配上述情况，则返回原行
    return line

def main():
    parser = argparse.ArgumentParser(
        description="修改 .s 文件，将多寄存器传送指令拆分为单条 ldr/str/add 指令，并将带有 mark 的 ldr 指令替换为 mov 指令。")
    parser.add_argument("input_file", help="输入的 .s 文件路径")
    parser.add_argument("output_file", help="输出的新 .s 文件路径")
    args = parser.parse_args()

    # 读取输入文件内容
    with open(args.input_file, "r") as infile:
        lines = infile.readlines()

    new_lines = []
    for line in lines:
        new_lines.append(replace_instructions(line))

    # 将处理后的内容写入新文件
    with open(args.output_file, "w") as outfile:
        outfile.write("".join(new_lines))

if __name__ == "__main__":
    main()
