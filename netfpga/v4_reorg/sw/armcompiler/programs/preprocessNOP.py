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

def should_insert_nop(line):
    """
    判断一行是否为需要在后面插入4个nop的“指令”。
    对于空行、标签（以冒号结尾）、以.开头的指令或注释行，不插入nop。
    同时避免对已经是nop的行重复插入。
    """
    stripped = line.strip()
    if not stripped:
        return False
    if stripped.endswith(':'):
        return False
    if stripped.startswith('.'):
        return False
    if stripped.startswith('@') or stripped.startswith(';'):
        return False
    if re.match(r'^nop\b', stripped):
        return False
    return True

def is_cmp_instruction(line):
    """判断该行是否为 cmp 指令"""
    return re.match(r'^\s*cmp\b', line) is not None

def is_branch_instruction(line):
    """判断该行是否为 branch 指令（包括 b、bl、beq、bne 等）"""
    return re.match(r'^\s*b(?:[a-z]+)?\b', line) is not None

def main():
    parser = argparse.ArgumentParser(
        description="修改 .s 文件，将多寄存器传送指令拆分为单条 ldr/str/add 指令，并将带有 mark 的 ldr 指令替换为 mov 指令，同时在每条指令后插入4个nop来避免hazard。"
    )
    parser.add_argument("input_file", help="输入的 .s 文件路径")
    parser.add_argument("output_file", help="输出的新 .s 文件路径")
    args = parser.parse_args()

    # 读取输入文件内容
    with open(args.input_file, "r") as infile:
        lines = infile.readlines()

    # 第一步：将每行经过替换后分解为多条指令，存入一个列表
    instructions = []
    for line in lines:
        replaced = replace_instructions(line)
        for subline in replaced.splitlines():
            instructions.append(subline)

    new_lines = []
    # 第二步：遍历指令列表，根据是否为 cmp 后紧跟 branch 的情况决定是否插入 nop
    for i, instr in enumerate(instructions):
        new_lines.append(instr + "\n")
        # 判断是否需要在当前指令后插入 nop
        if should_insert_nop(instr):
            # 如果当前指令是 cmp，检查后续最近的有效指令是否为 branch
            if is_cmp_instruction(instr):
                next_instr = None
                for j in range(i + 1, len(instructions)):
                    candidate = instructions[j].strip()
                    if (not candidate or candidate.endswith(':') or candidate.startswith('.') or 
                        candidate.startswith('@') or candidate.startswith(';')):
                        continue
                    next_instr = candidate
                    break
                # 如果后续有效指令是 branch，则跳过在 cmp 后插入 nop
                if next_instr and is_branch_instruction(next_instr):
                    continue
            # 否则插入4条 nop (这里使用 mov r5, r5 作为 nop)
            indent = re.match(r'^(\s*)', instr).group(1)
            new_lines.append(f"{indent}mov r5, r5\n")
            new_lines.append(f"{indent}mov r5, r5\n")
            new_lines.append(f"{indent}mov r5, r5\n")
            new_lines.append(f"{indent}mov r5, r5\n")

    # 将处理后的内容写入新文件
    with open(args.output_file, "w") as outfile:
        outfile.write("".join(new_lines))

if __name__ == "__main__":
    main()
